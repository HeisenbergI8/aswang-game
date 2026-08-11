--!strict
--[[
	RoundService — the round state machine. This is milestone M1.

	IDLE ──(players >= MinPlayers)──> INTERMISSION ──> STARTING ──> ACTIVE
	  ^                                                               │
	  └──────────(players < min)──── ENDING <──(win/lose/timeout)─────┘

	DESIGN RULE: nothing outside this module mutates the phase. Other services
	subscribe via RoundService.PhaseChanged. Round logic is the single most
	bug-prone area of a game like this; funnelling every transition through one
	SetPhase() function is what keeps it debuggable.

	The transition table itself lives in `shared/pure/RoundTransitions.luau` so it can be tested
	exhaustively from a terminal. What remains here is the Roblox-shaped half: timers, player
	bookkeeping, and the two things the client is allowed to know.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
-- One direction only. RoleService must NEVER require RoundService back: a require cycle errors at load,
-- init.server.luau swallows it into a single warn, and the server sits in IDLE forever looking exactly
-- like "nobody has joined yet".
local RoleService = require(script.Parent.RoleService)
local BodyTransitions = require(Shared.pure.BodyTransitions)
local RoundTransitions = require(Shared.pure.RoundTransitions)
local Types = require(Shared.Types)
local WinConditions = require(Shared.pure.WinConditions)

type RoundPhase = Types.RoundPhase
type PlayerState = Types.PlayerState

local RoundService = {}

-- SERVER-ONLY state. Never replicate this table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	AswangUserId = nil :: number?,
	TasksCompleted = 0,
	GateOpen = false,
	-- How many SURVIVORS were dealt into this round, snapshotted at STARTING. A snapshot rather than a
	-- live count on purpose: see enterStarting.
	DealtInSurvivors = 0,
	-- Kills the Aswang has actually COMMITTED this round. Only commitKill increments it. §4.8's win is
	-- counted from this rather than from who is still standing, because presence cannot tell a kill
	-- from a quit — three patches failed on that before the rule changed shape.
	AswangKills = 0,
	-- Keyed by UserId. LOBBY between rounds, ALIVE for everyone dealt into a round, SPECTATOR for
	-- anyone who joined after it started (spec §6.4), GHOST once C15 lands.
	PlayerStates = {} :: { [number]: PlayerState },
}

RoundService.PhaseChanged = Instance.new("BindableEvent")

local phaseChangedRemote = Remotes.Get("PhaseChanged")
local snapshotRemote = Remotes.Get("RoundSnapshot")

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function RoundService.GetPhase(): RoundPhase
	return state.Phase
end

function RoundService.IsActive(): boolean
	return state.Phase == Enums.RoundPhase.Active
end

function RoundService.GetSecondsRemaining(): number
	return math.max(0, state.PhaseEndsAt - os.clock())
end

-- Deliberately NOT exposed to any client-facing code path.
function RoundService.GetAswangUserId(): number?
	return state.AswangUserId
end

function RoundService.GetPlayerState(player: Player): PlayerState
	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
end

--[[
	THE BODY RULE, applied. C04's carried-over warning from C01 (BUILD-PLAN lines ~203–219).

	`Players.CharacterAutoLoads` is a SERVICE-level property, not a per-player one, so containment
	cannot be expressed by "do not auto-load for this player". Turning it off globally and loading
	explicitly is the only shape that admits a per-player rule at all, and it has the side benefit of
	putting every spawn in this game through one function that a reader can find.

	SIX CALL SITES, all in this file. The count is spelled out because this comment claimed three for
	two rounds after it had stopped being true, and stale comments about who touches a player's body
	have already caused two real bugs on this surface:

	  · onPlayerAdded            — on join, and via Start()'s backfill
	  · setAllPlayerStates       — every wholesale state change, after the table is fully written
	  · MarkKilled               — a death, which clears the body for a GHOST
	  · watchForDeath, twice     — the immediate respawn, and the DEFERRED one inside task.delay
	  · itself                   — the post-yield re-apply, when the state changed during a load

	The deferred one is the load-bearing one for the respawn throttle: the body is destroyed before the
	cooldown is consulted, so the player is left at `Character == nil`, a state this function repairs.
	An earlier version returned before the destroy and stranded them permanently.

	THE `Character == nil` GUARD IS LOAD BEARING, and not for the reason you would guess. A second
	`LoadCharacter()` on a player who already has one does NOT error — probed live in Studio, see
	`artifacts/spectator-premise.md`. It respawns them. Without the guard, every setAllPlayerStates
	call teleports every already-embodied player back to the SpawnLocation, including LOBBY→LOBBY
	transitions that changed nothing.
]]
--[[
	UserIds with a LoadCharacterAsync in flight.

	The async deviation below costs one guarantee the plan's synchronous version had for free:
	applyBodyRule is no longer idempotent on its own. `Start()`'s backfill loop calls onPlayerAdded for
	players who joined in the connect window — and its comment promises that repeat is safe — but two
	calls in the same frame both see `Character == nil`, because the first load has not landed yet, and
	both fire. This table is what keeps that promise true.
]]
local pendingLoads: { [number]: boolean } = {}

-- Last player-triggered respawn per UserId, for the cooldown in watchForDeath. Separate from
-- `pendingLoads` on purpose: that one bounds concurrency, this one bounds rate, and conflating them
-- would let a client alternate faster than either intends.
local lastRespawnAt: { [number]: number } = {}

--[[
	`cause` defaults to PHASE_CHANGE because five of the six call sites are one: something moved the
	player's state and the body must catch up. Only the failed-load retry passes anything else.

	THE STATE PASSED IS THE POST-TRANSITION ONE, and that is worth stating because an audit found the
	table's comments implying otherwise. `MarkKilled` writes GHOST *before* calling here, and
	`setAllPlayerStates` writes the whole table before its loop, so `GetPlayerState` always answers
	with where the player has ARRIVED, never where they came from. The cells agree either way today —
	`ALIVE/DIED` and `GHOST/DIED` are both REVOKE — but a future cell where they differ would be read
	off the wrong row, so the convention is pinned here rather than left to inspection.
]]
local function applyBodyRule(player: Player, cause: BodyTransitions.Cause?)
	local action =
		BodyTransitions.actionFor(RoundService.GetPlayerState(player), cause or "PHASE_CHANGE")

	if action == "KEEP" then
		return
	end

	--[[
		DEFER is "should have a body, but not yet" — the rung that did not exist when this function was
		imperative, and whose absence WAS the permanent-strand bug: a throttled respawn returned having
		neither granted nor revoked, so the player kept a dead character forever.
	]]
	if action == "DEFER" then
		task.delay(Config.Round.RespawnCooldown, function()
			if player.Parent ~= nil then
				applyBodyRule(player)
			end
		end)

		return
	end

	if action == "GRANT" then
		if player.Character == nil and not pendingLoads[player.UserId] then
			--[[
				DEVIATION FROM THE PLAN, forced by the analyzer: `LoadCharacter` is deprecated in
				favour of `LoadCharacterAsync`, and `analyze-baseline.json` is empty — this repo
				blesses no diagnostics, so the deprecated call cannot land.

				The Async form YIELDS, and this function must not. `enterStarting` calls
				setAllPlayerStates and then reads `dealtInUserIds()` before `setPhase`, deliberately,
				so that no subscriber sees a STARTING round without an Aswang. A yield inside the
				loop would put the role draw on the far side of every player's character load, and a
				player leaving during that window would change the roster mid-transition.

				task.spawn keeps the caller synchronous and the transition ordering exactly as C01
				built it. The pcall is for the player who disconnects between the state write and the
				load, which throws.
			]]
			pendingLoads[player.UserId] = true

			task.spawn(function()
				local ok, err = pcall(function()
					player:LoadCharacterAsync()
				end)

				pendingLoads[player.UserId] = nil

				if not ok then
					if Config.Debug.VerboseLogging then
						warn(`[RoundService] LoadCharacterAsync failed for {player.Name}: {err}`)
					end

					--[[
						RE-ARM. A failed load used to warn and give up, and during ACTIVE this is the ONLY
						path that can put a body back: MarkKilled and onPlayerAdded both reach
						applyBodyRule on their DENY branches, and setAllPlayerStates does not run inside
						a round. So one throw left a player ALIVE with no character for the rest of the
						round — and MonsterService returns early on `targetCharacter == nil`, making them
						unkillable while still counted by livingSurvivorCount(). An unkillable survivor
						puts §4.8's attrition win out of reach and the round runs to Timeout.

						That is the round-1 bug's shape — a body state nothing repairs — reached by a
						different route, which is why "eventually applied" has to be a property of this
						function rather than of any one caller.

						THE TABLE DECIDES WHETHER TO RETRY, not a hand-written guard here. Re-entering with
						cause LOAD_FAILED answers DEFER for LOBBY and ALIVE — who are owed a body — and
						KEEP for GHOST and SPECTATOR, who are owed nothing and whose retry would loop
						against a rule that will never say yes.
					]]
					applyBodyRule(player, "LOAD_FAILED")

					return
				end

				--[[
					RE-APPLY, because the state can have changed while we yielded. A player who was
					LOBBY when the load started and SPECTATOR when it finished would otherwise keep the
					body this rule exists to deny them — the exact C04 hole, reopened by the async call.
					The recursion terminates: re-entering can only reach the REVOKE branch, which yields.
				]]
				if
					BodyTransitions.actionFor(RoundService.GetPlayerState(player), "PHASE_CHANGE")
					== "REVOKE"
				then
					applyBodyRule(player)
				end
			end)
		end

		return
	end

	--[[
		DETACH, THEN DESTROY, AND ONLY WHAT WE STILL OWN.

		Step 4.2 takes a killed player's character AWAY from the player (`player.Character = nil`) and
		keeps it in the workspace as the corpse. By the time MarkKilled reaches here, `player.Character`
		is already nil, so this branch finds nothing and the corpse survives. That ordering is the whole
		reason MarkKilled hands the body to MonsterService before it changes the state.
	]]
	local character = player.Character

	player.Character = nil

	if character ~= nil then
		character:Destroy()
	end
end

--[[
	A DEATH THIS SERVICE DID NOT CAUSE. The other half of owning every character load.

	Turning `CharacterAutoLoads` off made RoundService the only thing that can put a body in the world,
	and the first version of that wired only three call sites — join, phase change, and MarkKilled.
	None of them is a death. So a player who died any other way stayed a corpse for the rest of the
	SERVER SESSION: no respawn, and still `ALIVE` in PlayerStates, so livingSurvivorCount kept counting
	them and §4.8's attrition win could never reach its threshold. Measured live before this fix —
	64 seconds and three rounds with `health=0 state=Dead` and `alive 1 · you: ALIVE` in every snapshot
	(`artifacts/console-finding2-no-respawn.txt`). Reachable by accident, from the default reset button.

	THE KILL PATH NEVER REACHES HERE, by construction. `makeCorpse` DETACHES the victim's character
	(`player.Character = nil`) and anchors it; it never kills the Humanoid, because §4.9 wants a body
	that lies there rather than a death animation. So `player.Character ~= character` on that path and
	the first guard returns. What reaches this line is a reset, a fall out of the world, and whatever
	C14's salt does to someone standing in a bad place.

	A ROUND DEATH IS A DEATH, which also closes reset-to-escape: without this, an Aswang cornering a
	survivor could be beaten by Escape → Reset, which teleports the victim to spawn for free. Dying in
	ACTIVE routes through MarkKilled and makes them a GHOST — uncounted, bodiless and unkillable, the
	same as being killed, minus the corpse and the broadcast because nobody killed them.
]]
local function watchForDeath(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return
	end

	humanoid.Died:Connect(function()
		-- Already taken from the player — this is the corpse, and MonsterService owns it now.
		if player.Character ~= character then
			return
		end

		if
			state.Phase == Enums.RoundPhase.Active
			and RoundService.GetPlayerState(player) == Enums.PlayerState.Alive
		then
			-- MarkKilled applies the body rule, which clears the dead body, and runs the win check.
			RoundService.MarkKilled(player)

			return
		end

		--[[
			Not a round death: the lobby, or STARTING before the round is live. Give the body back.
			Explicitly rather than by falling through to applyBodyRule — that function's load branch is
			gated on `Character == nil`, and the dead character is still attached, so it would decline
			to act and the player would stay dead.

			RATE LIMITED, because this is a client-controlled trigger and the work is not cheap.
			`Humanoid.Died` is reachable from the stock reset button as fast as a player can press it,
			and each pass costs a full rig build, an appearance fetch and a replication to every client.
			It is not a remote, so AntiCheatService never sees it and check:ratelimit cannot cover it —
			this is the only place the limit can live. `pendingLoads` bounds CONCURRENCY to one per
			player and bounds nothing about rate, which is a different property.
		]]
		--[[
			DETACH FIRST, ALWAYS. THROTTLE ONLY THE LOAD, AND DEFER IT RATHER THAN DROPPING IT.

			The first version of this rate limit returned ABOVE these two lines, and that reintroduced
			the exact bug this whole watcher exists to prevent — in a worse form. The comment fourteen
			lines up already spelled out why: applyBodyRule's load branch is gated on
			`Character == nil`, so a DEAD character left attached is never repaired by any later phase
			change. Not for three seconds — for the rest of the server session.

			Reproduced live before this fix (`artifacts/console-throttle-strand-repro.txt`): reset, wait
			for the respawn, reset again 0.6s later, and the player holds a dead body through multiple
			full round cycles while every snapshot still reports them ALIVE — dealt into later rounds
			and, worst of all, still eligible for the Aswang draw. Drawn in that state they are an
			immobile monster who can never reach anyone, and because `MarkKilled` never fires, NEITHER
			of the two round-abort paths runs.

			So: the body always goes, which leaves `Character == nil` — a state the body rule can and
			will repair. The cooldown then bounds only the expensive half, the `LoadCharacterAsync` rig
			build, which is all it was ever meant to bound.
		]]
		player.Character = nil
		character:Destroy()

		local now = os.clock()
		local previous = lastRespawnAt[player.UserId]
		local remaining = if previous ~= nil
			then Config.Round.RespawnCooldown - (now - previous)
			else 0

		if remaining > 0 then
			--[[
				DEFERRED, NOT DROPPED.

				MORE THAN ONE OF THESE CAN BE OUTSTANDING, and an earlier version of this comment
				claimed otherwise. `lastRespawnAt` is stamped when the deferred FIRES, not when it is
				scheduled, so `previous` stays stale for the whole window — and a phase change during
				that window calls applyBodyRule through setAllPlayerStates, which loads a body without
				stamping anything. A second death then schedules a second closure.

				It is harmless: both land at roughly the same moment, the first loads, and the second is
				absorbed by `pendingLoads` and the `Character == nil` guard. Stated accurately rather
				than repaired, because the concurrency bound that matters already comes from those two
				and not from this delay. Three rounds of bugs on this surface came from a comment
				asserting an invariant the neighbouring path quietly broke; this one claims only what it
				can keep.

				`player.Parent` is the disconnect check — `Players` is the parent while they are on the
				server, and `LoadCharacterAsync` on a departed player throws inside the pcall for nothing.
			]]
			task.delay(remaining, function()
				if player.Parent == nil then
					return
				end

				lastRespawnAt[player.UserId] = os.clock()

				applyBodyRule(player)
			end)

			return
		end

		lastRespawnAt[player.UserId] = now

		applyBodyRule(player)
	end)
end

local function eligiblePlayerCount(): number
	if Config.Debug.SoloTesting then
		return math.max(#Players:GetPlayers(), Config.Round.MinPlayers)
	end
	return #Players:GetPlayers()
end

local function aliveCount(): number
	local count = 0
	for _, playerState in state.PlayerStates do
		if playerState == Enums.PlayerState.Alive then
			count += 1
		end
	end
	return count
end

--[[
	Living SURVIVORS — alive, and not the Aswang. Distinct from aliveCount(), which is what the client
	snapshot carries, and the difference is exactly one player.

	Reads state.AswangUserId, which is why this cannot live in the pure module: the count is derived
	from the secret. What crosses to WinConditions is a NUMBER, and a number is not a hint — the
	snapshot already tells every client how many players are alive, and "one fewer than that" is
	arithmetic anyone can do. Nothing here is broadcast.
]]
local function livingSurvivorCount(): number
	local count = 0

	for userId, playerState in state.PlayerStates do
		if playerState == Enums.PlayerState.Alive and userId ~= state.AswangUserId then
			count += 1
		end
	end

	return count
end

--------------------------------------------------------------------------------
-- Player bookkeeping (spec §6.4)
--------------------------------------------------------------------------------

local function isRoundUnderway(): boolean
	return state.Phase == Enums.RoundPhase.Starting
		or state.Phase == Enums.RoundPhase.Active
		or state.Phase == Enums.RoundPhase.Ending
end

local function setAllPlayerStates(newState: PlayerState)
	table.clear(state.PlayerStates)
	for _, player in Players:GetPlayers() do
		state.PlayerStates[player.UserId] = newState
	end

	-- After the whole table is written, not inside the loop: applyBodyRule reads GetPlayerState, and a
	-- half-written table would answer LOBBY (the default) for everyone not yet assigned.
	for _, player in Players:GetPlayers() do
		applyBodyRule(player)
	end
end

--[[
	The roster dealt into this round, SORTED.

	The sort is not cosmetic. `RoleDraw.draw` is only reproducible from a seed if its candidate list
	arrives in a stable order, and `Players:GetPlayers()` makes no such promise. Without it the draw is
	still fair and still secret — but `tests/role-draw.test.luau` stops describing the game, because the
	property it proves ("same stream, same Aswang") would no longer hold at the call site.
]]
local function dealtInUserIds(): { number }
	local userIds = {}

	for userId, playerState in state.PlayerStates do
		if playerState == Enums.PlayerState.Alive then
			table.insert(userIds, userId)
		end
	end

	table.sort(userIds)

	return userIds
end

--------------------------------------------------------------------------------
-- The client's view
--------------------------------------------------------------------------------

--[[
	Everything a HUD needs and nothing else. Compare against Types.ClientRoundSnapshot: there is no
	AswangUserId field to forget to strip, because the type does not have one.

	`YourRole` is deliberately left unset. The snapshot is built per player, so a role here would be
	*technically* safe — but RoleAssigned (fired to exactly one player) is the single allowlisted
	carrier of a role in `check-secrecy.mjs`, and one carrier is auditable in a way that two are not.
	C03 puts the role on RoleAssigned and the client caches it locally.
]]
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
	return {
		Phase = state.Phase,
		SecondsRemaining = RoundService.GetSecondsRemaining(),
		RoundNumber = state.RoundNumber,
		TasksCompleted = state.TasksCompleted,
		TasksRequired = Config.Tasks.TotalRequired,
		GateOpen = state.GateOpen,
		AlivePlayerCount = aliveCount(),
		YourState = RoundService.GetPlayerState(player),
	}
end

-- Per player, not FireAllClients: YourState differs between a survivor and a mid-round spectator,
-- and a broadcast could only ever carry one of them.
local function broadcastSnapshot()
	for _, player in Players:GetPlayers() do
		snapshotRemote:FireClient(player, buildSnapshot(player))
	end
end

--------------------------------------------------------------------------------
-- Transitions
--------------------------------------------------------------------------------

local function setPhase(newPhase: RoundPhase, duration: number?)
	if state.Phase == newPhase then
		return
	end

	state.Phase = newPhase
	state.PhaseEndsAt = duration and (os.clock() + duration) or 0

	RoundService.PhaseChanged:Fire(newPhase, duration)

	-- Clients get the phase and a duration, never the round's secrets.
	phaseChangedRemote:FireAllClients(newPhase, duration or 0)

	-- Push a snapshot immediately rather than letting the HUD lag by up to SnapshotInterval on the
	-- one frame players are actually looking at it.
	broadcastSnapshot()

	if Config.Debug.VerboseLogging then
		print(`[RoundService] -> {newPhase}{duration and ` ({duration}s)` or ""}`)
	end
end

--------------------------------------------------------------------------------
-- Phase handlers
--
-- TODO(C03): assign roles via RoleService in STARTING
-- TODO(C07): pick tasks via TaskService in STARTING; TODO(C11): win conditions in ACTIVE
-- TODO(C15): convert dead players to ghosts via GhostService
--------------------------------------------------------------------------------

local function enterIdle()
	state.AswangUserId = nil
	state.TasksCompleted = 0
	state.GateOpen = false
	state.DealtInSurvivors = 0
	state.AswangKills = 0
	-- The live assignments go; RoleService's HISTORY deliberately survives, because it is the whole
	-- anti-repeat mechanism and a server that reset it every lobby would have no memory at all.
	RoleService.ClearRoles()
	-- Spectator status lifts here: whoever is on the server is a candidate for the next round.
	setAllPlayerStates(Enums.PlayerState.Lobby)
	setPhase(Enums.RoundPhase.Idle)
end

local function enterIntermission()
	RoleService.ClearRoles()
	setAllPlayerStates(Enums.PlayerState.Lobby)
	setPhase(Enums.RoundPhase.Intermission, Config.Round.Intermission)
end

local function enterStarting()
	state.RoundNumber += 1
	-- Everyone present when the round is drawn is dealt in. Anyone arriving from here until the
	-- next INTERMISSION becomes a SPECTATOR in onPlayerAdded.
	setAllPlayerStates(Enums.PlayerState.Alive)

	-- BEFORE setPhase, deliberately. setPhase fires PhaseChanged and pushes a snapshot to every
	-- client; drawing first means no subscriber can observe a STARTING round that has no Aswang yet.
	-- The snapshot carries no role either way — this is about services, not clients.
	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())

	--[[
		SNAPSHOTTED HERE, AFTER THE DRAW, AND NEVER UPDATED AGAIN THIS ROUND.

		It has to be after the draw, because "survivors" means "dealt in and not the Aswang" and the
		Aswang does not exist a line earlier. It has to be frozen, because §4.8's rule is about how many
		of the people who started have died — a count that fell when somebody disconnected would let a
		losing survivor quit and hand the Aswang the win, which is the same mistake RoundTransitions
		refuses to make in ACTIVE (see its comment) for the same reason.
	]]
	state.DealtInSurvivors = livingSurvivorCount()
	state.AswangKills = 0

	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
	-- TODO(C07): TaskService.SelectTasksForRound()
end

local function enterActive()
	setPhase(Enums.RoundPhase.Active, Config.Round.Duration)
end

-- `Types.RoundResult`, NOT `string`. This value is broadcast to every client on RoundEnded, and
-- check:secrecy inspects the literal argument at that call — where it sees only a variable name. A
-- `string` parameter permits `EndRound("ASWANG_WINS:" .. player.Name)`: a plausible shape for a richer
-- end screen, and an eight-client leak no check in this repo can see.
--
-- Measured, not assumed: the union blocks that concat and any `string`-typed helper. It does NOT block
-- a `:: any` cast, a `:: Types.RoundResult` downcast, or a caller whose file is headed `--!nonstrict`.
-- It raises the cost of the obvious mistake; it does not make it impossible. The guard that actually
-- constrains the wire is Types.RoundEndedPayload on the local below.
local function enterEnding(result: Types.RoundResult)
	-- setPhase() no-ops when the phase is unchanged, but the reveal below does not. Without this
	-- guard a second caller landing in ENDING would re-broadcast RoundEnded — a second reveal on a
	-- timer that never restarted. Guarded here rather than in each caller so a future win condition
	-- added at C06/C11 cannot reintroduce it by forgetting.
	if state.Phase == Enums.RoundPhase.Ending then
		-- UNGATED, unlike the phase tracing below. VerboseLogging is false on a published place, and a
		-- live server is exactly where this fires: C11 raising SURVIVORS_ESCAPED one tick after the
		-- sunrise timeout already ended the round. Discarding the correct result silently surfaces
		-- much later as wrong analytics and wrong XP, with nothing pointing back to here. This repo
		-- warns unconditionally for faults (see init.server.luau) and gates only routine tracing;
		-- a dropped round result is a fault. Safe to log: a RoundResult names an outcome, never a
		-- player, and every client already received it on RoundEnded.
		warn(`[RoundService] Discarded a late round result ({result}) — already ENDING.`)
		return
	end

	setPhase(Enums.RoundPhase.Ending, Config.Round.EndScreen)

	-- The reveal. This is the moment players screenshot — make it dramatic.
	--
	-- Built as a TYPED LOCAL, not an inline table: `FireAllClients` takes `...any`, so an inline
	-- literal is checked against nothing at all. The annotation catches a wrong type and a missing
	-- field — but NOT an extra one, which is the leak shape. See Types.RoundEndedPayload; adding a
	-- field here is a decision to review by hand, because no check in this repo will review it.
	local payload: Types.RoundEndedPayload = {
		Result = result,
		AswangUserId = state.AswangUserId, -- safe: the round is over
		RoundNumber = state.RoundNumber,
	}

	Remotes.Get("RoundEnded"):FireAllClients(payload)
end

-- Exposed so gameplay services can end a round early.
function RoundService.EndRound(result: Types.RoundResult)
	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end
	enterEnding(result)
end

--[[
	A survivor died (C05). The ONLY writer of a death, and it lives here because this service owns
	PlayerStates — MonsterService asks rather than writes, exactly as it asks for the phase rather than
	reading a copy.

	GHOST, NOT A FIFTH STATE. §4.7 already calls a dead survivor a ghost, and Types.PlayerState has
	four values that this plan does not extend. Two consequences land immediately and both are wanted:
	pure/PlayerBody says a GHOST has no body, and pure/KillValidation says a GHOST is not a valid
	target — which is the C04 warning's "a ghost must not be killable", satisfied by construction
	rather than by a rule someone has to remember at C15.

	THE CALLER HAS ALREADY TAKEN THE BODY. MonsterService detaches the victim's character
	(`player.Character = nil`) to make it the corpse BEFORE calling this, so applyBodyRule below finds
	nothing to destroy. Reversing those two steps deletes the corpse in the same frame it is created,
	and the symptom is "the corpse code does not work" — a full step away from the cause.

	Guarded on ACTIVE and on the victim currently being ALIVE, so a duplicate call — two kill requests
	landing in the same tick, a retry after a dropped packet — is a no-op rather than a second death.
	Phase 5 hangs the win check off the end of this function, which is why that idempotence matters.
]]
function RoundService.MarkKilled(player: Player, causedByKill: boolean?)
	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end

	if state.PlayerStates[player.UserId] ~= Enums.PlayerState.Alive then
		return
	end

	state.PlayerStates[player.UserId] = Enums.PlayerState.Ghost

	applyBodyRule(player)

	--[[
		THE ASWANG DIED, SO THE ROUND IS OVER. Mirrors onPlayerRemoving's abort exactly.

		That handler already ends the round when the Aswang DISCONNECTS, with the comment "end cleanly
		rather than leaving survivors wandering a monster-free map for six minutes". Routing non-kill
		deaths through here opened a second door to that same state which walked straight past it: the
		Aswang presses Escape → Reset, becomes a GHOST, `KillValidation` then refuses every RequestKill
		on `KILLER_NOT_ALIVE`, and six players walk an empty Barrio for the rest of the round. Repeatable
		every round you are drawn, without leaving the server.

		A kill can never reach this branch — `TARGET_IS_ASWANG` refuses it — so in practice this fires
		only for a reset, a fall, or whatever C14's salt does. It is written unconditionally anyway,
		because "the monster is gone" is the thing that matters and not how it happened.

		ABORTED rather than SURVIVORS_ESCAPED: they did not escape, and the round was void.
	]]
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)

		return
	end

	--[[
		THE ONLY PLACE A KILL IS COUNTED, and the reason `causedByKill` exists at all.

		A death the Aswang did not cause — a reset, a fall, C14's salt later — still makes the player a
		GHOST, still drops the alive count, and still shows on every HUD. It just does not advance the
		win, because §4.8's rule now asks how many people the Aswang KILLED rather than how many are
		still standing.

		The previous version decremented `DealtInSurvivors` here instead, to keep both sides of a
		comparison moving together. That was the third of three failed patches on this arithmetic, and
		it was inert above four survivors: `effective = min(2, dealt - 1)` only binds at `dealt <= 3`.
		With the rule counting kills, the denominator no longer has to be corrected at all — a
		departure simply is not a kill, which is what both previous comments claimed and neither
		delivered.
	]]
	if causedByKill == true then
		state.AswangKills += 1
	end

	-- Immediately, rather than waiting up to SnapshotInterval: AlivePlayerCount and the victim's own
	-- YourState both just changed, and the victim's HUD is the one screen guaranteed to be looked at.
	broadcastSnapshot()

	if Config.Debug.VerboseLogging then
		-- A UserId and a count. Never a role, and never who did it — this line is read while a round is
		-- still running, and VerboseLogging is exactly the flag a Studio playtest leaves on.
		print(`[RoundService] Killed {player.UserId}; {aliveCount()} alive.`)
	end

	--[[
		§4.8's attrition win (C06). AT THE END OF MarkKilled AND NOWHERE ELSE.

		Not in the step() loop: polling a win condition several times a second means the round can end
		on a tick that no player action caused, and debugging "why did it end there" starts from a
		timestamp instead of from an event.

		Not on PlayerRemoving either, and that is the deliberate one. A survivor disconnecting reduces
		the living count exactly as a kill does, and ending the round for it would (a) hand the Aswang a
		win every time a phone lost signal and (b) let a losing survivor void a round by quitting. Spec
		§6.4 already answers this for the headcount — "finish the round, then return to IDLE" — and this
		is the same answer for the same reason.

		THIS COMMENT HAS BEEN WRONG TWICE, so what it claims now is deliberately narrow. It used to say
		a frozen `DealtInSurvivors` meant a disconnect moved neither side of a comparison; that was
		false, because `livingSurvivorCount()` was computed live. The next version said the decrement
		fixed it; that was false too, and provably inert above four survivors.

		What is true now is structural rather than arithmetic: the rule reads `state.AswangKills`, and
		nothing but a validated kill ever writes it. A disconnect, a reset and a fall cannot move it
		because they do not touch it — there is no comparison left to keep balanced.

		EndRound is guarded on ACTIVE inside this service, so this stays a request rather than a second
		writer of the phase.
	]]
	if
		WinConditions.aswangWinsByKills({
			AswangKills = state.AswangKills,
			DealtInSurvivors = state.DealtInSurvivors,
			Threshold = Config.Round.AswangWinSurvivorThreshold,
		})
	then
		RoundService.EndRound(Enums.RoundResult.AswangWins)
	end
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local function step()
	local expired = state.PhaseEndsAt > 0 and os.clock() >= state.PhaseEndsAt
	local enoughPlayers = eligiblePlayerCount() >= Config.Round.MinPlayers

	local nextPhase = RoundTransitions.next(state.Phase, expired, enoughPlayers)

	if nextPhase == nil then
		return
	elseif nextPhase == Enums.RoundPhase.Idle then
		enterIdle()
	elseif nextPhase == Enums.RoundPhase.Intermission then
		enterIntermission()
	elseif nextPhase == Enums.RoundPhase.Starting then
		enterStarting()
	elseif nextPhase == Enums.RoundPhase.Active then
		enterActive()
	elseif nextPhase == Enums.RoundPhase.Ending then
		-- The only automatic route into ENDING is the sunrise timer running out. Every other route
		-- (a win, an abort) goes through EndRound/enterEnding with its own result.
		enterEnding(Enums.RoundResult.Timeout)
	end
end

--------------------------------------------------------------------------------
-- Edge cases (see docs/MVP-SPEC.md §6.4 — these WILL bite you)
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Joined mid-round → spectator until the next round is drawn. Without this a late arrival is
	-- indistinguishable from a survivor and would be counted alive by every win check from C06 on.
	state.PlayerStates[player.UserId] = if isRoundUnderway()
		then Enums.PlayerState.Spectator
		else Enums.PlayerState.Lobby

	--[[
		BEFORE applyBodyRule, so the very first character this player gets is already watched. Connecting
		after would leave a window in which a death goes unnoticed, and this connection is what stops a
		dead player being counted alive forever.
	]]
	player.CharacterAdded:Connect(function(character: Model)
		watchForDeath(player, character)
	end)

	local existing = player.Character

	if existing ~= nil then
		watchForDeath(player, existing)
	end

	-- The other half of that sentence, and the half C01 left out. A SPECTATOR with a body is uncounted
	-- AND, from C05 on, unkillable — an alt account that watches the whole round from ten studs away.
	applyBodyRule(player, "JOINED")

	snapshotRemote:FireClient(player, buildSnapshot(player))
end

local function onPlayerRemoving(player: Player)
	state.PlayerStates[player.UserId] = nil
	-- The in-flight load (if any) will fail in its own pcall and clear this itself; dropping the key
	-- here as well keeps the table bounded by the players actually on the server.
	pendingLoads[player.UserId] = nil
	lastRespawnAt[player.UserId] = nil

	--[[
		STARTING COUNTS TOO, and leaving it out was a live exploit.

		The Aswang sees their role card for the whole of StartingDelay before ACTIVE begins. Guarding
		only on ACTIVE meant: get the card, quit within four seconds, and `state.AswangUserId` points
		at nobody. ACTIVE then runs its full duration with no monster in it — RoundTransitions ignores
		the headcount during ACTIVE by design — and the round ends on Timeout revealing a UserId that
		is not in the server. Every round you were drawn for, you could delete for six other people at
		zero cost.

		Redrawing from the remaining roster would be the richer fix; aborting is the honest one for
		C03, because a redraw mid-STARTING would fire a second RoleAssigned to players who already have
		a card and nothing yet handles that. C05 can revisit it.
	]]
	local inRound = state.Phase == Enums.RoundPhase.Active
		or state.Phase == Enums.RoundPhase.Starting

	if not inRound then
		return
	end

	-- The Aswang rage-quits / disconnects: end cleanly rather than leaving
	-- survivors wandering a monster-free map for six minutes.
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)

		return
	end

	--[[
		NOTHING TO ADJUST HERE ANY MORE, and its absence is the point.

		This block used to decrement `DealtInSurvivors` for a departing survivor, to keep both sides of
		the old comparison falling together. That was the third of three failed patches on this rule:
		`effective = min(2, dealt - 1)` only binds at `dealt <= 3`, so above four survivors the
		decrement did nothing while the live headcount fell anyway — an 8-player round still went from
		a five-kill win to two when three alt accounts quit.

		The rule now counts `state.AswangKills`, which only a validated kill writes. A disconnect
		cannot move it, so there is no longer a ratio to keep honest and no correction to apply. A
		redesign that DELETES the patches written against it is the sign the shape was the problem.

		The Aswang's own departure still aborts the round — that is the branch above, and it is about
		there being no monster left, not about counting.
	]]

	-- NOTE the absence of a headcount check here. Spec §6.4: a round that drops below MinPlayers
	-- FINISHES, then returns to IDLE — RoundTransitions ignores the count in ACTIVE and re-reads it
	-- at ENDING. Ending the round on a disconnect would make quitting a way to void a round you were
	-- losing, and would read as an Aswang win every time someone's connection dropped.
end

local function onServerClosing()
	-- Spec §6.4: a shutdown must flush player data before the process dies, and Roblox gives you a
	-- short window to do it. Nothing owns player data yet — ProfileStore lands at C31 — so this is
	-- deliberately empty. It exists NOW so that there is exactly one flush point when there is
	-- something to flush, rather than three services each binding their own and racing.
	-- TODO(C31): flush every loaded profile here, and only here.
	if Config.Debug.VerboseLogging then
		print("[RoundService] Server closing — nothing to flush yet.")
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RoundService.Init()
	state.Phase = Enums.RoundPhase.Idle
	table.clear(state.PlayerStates)
end

function RoundService.Start()
	--[[
		BEFORE any PlayerAdded connection, and before the backfill loop below.

		Roblox loads a character as soon as a player joins while this is true, so a connection made after
		the flag is flipped can still be racing a spawn that has already been requested. Setting it here,
		at the top of Start(), is the earliest point this service runs. Step 1.1's Studio probe confirmed
		this flag reads `true` in this place file and that clearing it does suppress the automatic spawn
		— see `artifacts/spectator-premise.md`.
	]]
	Players.CharacterAutoLoads = false

	-- ORDER MATTERS. init.server.luau wraps Start() in a pcall that only warns, so anything throwing
	-- part-way through leaves a server with whatever had been registered so far — and a server with
	-- no tick loop, no snapshot loop and no close handler sits in IDLE forever behind one warn line,
	-- which looks exactly like "nobody has joined yet". Connections and loops go first; the player
	-- backfill, which is the part that touches remotes and could throw, goes last.
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onServerClosing)

	task.spawn(function()
		while true do
			step()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)

	task.spawn(function()
		while true do
			broadcastSnapshot()
			task.wait(Config.Round.SnapshotInterval)
		end
	end)

	-- Anyone who joined before this ran. Connecting PlayerAdded FIRST means the window between the
	-- connection and this loop cannot silently drop a player; the price is that someone joining in
	-- that window is handled twice, and onPlayerAdded is idempotent — it assigns a state and pushes
	-- a snapshot, both of which are safe to repeat.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return RoundService
