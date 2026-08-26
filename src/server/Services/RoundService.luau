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
-- A LEAF. It requires nothing but Config, so it cannot participate in a require cycle — which is the
-- reason the flush goes through it instead of this service requiring ProgressionService directly.
local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)
local BodyTransitions = require(Shared.pure.BodyTransitions)
local RejoinResolve = require(Shared.pure.RejoinResolve)
local RoundTransitions = require(Shared.pure.RoundTransitions)
local Types = require(Shared.Types)

type RoundPhase = Types.RoundPhase
type PlayerState = Types.PlayerState
-- Aliased for the same reason as the two above, so `state.LastResult` and `GetLastResult` read the
-- way `Phase` and `GetPhase` do. It does NOT survive the `require` boundary on its own — see
-- `ProgressionService.awardRound`, which re-annotates on arrival, and
-- `.claude/lessons/pure-module-unions-widen-in-lists.md` for the family of trap this belongs to.
type RoundResult = Types.RoundResult

local RoundService = {}

-- SERVER-ONLY state. Never replicate this table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	AswangUserId = nil :: number?,
	-- How many SURVIVORS were dealt into this round, snapshotted at STARTING. A snapshot rather than a
	-- live count on purpose: see enterStarting.
	DealtInSurvivors = 0,
	-- Kills the Aswang has actually COMMITTED this round. Only commitKill increments it. §4.8's win is
	-- counted from this rather than from who is still standing, because presence cannot tell a kill
	-- from a quit — three patches failed on that before the rule changed shape.
	AswangKills = 0,
	--[[
		How the LAST round ended (C32). Written by `enterEnding` and never cleared, so it survives into
		INTERMISSION and IDLE and reads as the result of the most recent round rather than as "no round
		is running" — which is the question nobody asks and the one a cleared field would answer.

		ABORTED is the initial value on purpose. A server that has never run a round has no result, and
		of the four `RoundResult` members ABORTED is the only one that pays nobody a win in
		`pure/XPCurve.awardFor` — so a reader that somehow arrives before any round cannot be handed a
		victory for a round that did not happen.
	]]
	LastResult = Enums.RoundResult.Aborted :: RoundResult,
	-- Keyed by UserId. LOBBY between rounds, ALIVE for everyone dealt into a round, SPECTATOR for
	-- anyone who joined after it started (spec §6.4), DEAD once C15 lands.
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
	HOW MANY VALIDATED KILLS THE ASWANG HAS THIS ROUND (C32). Server-only, like every query above it.

	Read by `ProgressionService` at ENDING for §4.8's per-kill split, and by nothing else. It is a
	COUNT and never a roster: it says how many, never who, so it carries none of the death oracle
	Amendment A3 removed `AlivePlayerCount` to close — and it is not sent anywhere in any case.

	Reset in `enterIdle` alongside the rest of the round's state, so a value read after IDLE is zero
	rather than last round's.
]]
function RoundService.GetAswangKills(): number
	return state.AswangKills
end

--[[
	HOW THE LAST ROUND ENDED (C32). Read by `ProgressionService` at ENDING to price §4.8's award table.

	A `RoundResult` names an outcome and never a player, so this is the one round query in this block
	that carries nothing sensitive at all — it is the same value `RoundEnded` broadcasts to every
	client. It is server-side anyway, for consistency with its neighbours rather than out of need.
]]
function RoundService.GetLastResult(): RoundResult
	return state.LastResult
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
	  · MarkKilled               — a death, which clears the body for a DEAD
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
	table's comments implying otherwise. `MarkKilled` writes DEAD *before* calling here, and
	`setAllPlayerStates` writes the whole table before its loop, so `GetPlayerState` always answers
	with where the player has ARRIVED, never where they came from. The cells agree either way today —
	`ALIVE/DIED` and `DEAD/DIED` are both REVOKE — but a future cell where they differ would be read
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
						KEEP for DEAD and SPECTATOR, who are owed nothing and whose retry would loop
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
	ACTIVE routes through MarkKilled and makes them a DEAD — uncounted, bodiless and unkillable, the
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
	Living SURVIVORS — alive, and not the Aswang. Distinct from aliveCount(), which is a SERVER-ONLY
	headcount, and the difference is exactly one player.

	`aliveCount()` used to be described here as "what the client snapshot carries". Amendment A3 removed
	that field; the function survives only for the VerboseLogging line below and for future server-side
	bookkeeping. Neither number reaches a client, and re-attaching either to a payload reopens the death
	oracle A3 closed.

	Reads state.AswangUserId, which is why this cannot live in the pure module: the count is derived
	from the secret. What ever crosses OUT of it is a NUMBER, and a number is not a hint — "how many
	survivors are alive" is arithmetic anyone watching the barrio can do. Nothing here is broadcast,
	and V11's win rule must keep it that way: it may read this count, never the id behind it.
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

--[[
	WHO WAS DEALT INTO THIS ROUND (§6.4, C15). Its OWN table, and that is not a style choice.

	It cannot live inside `state.PlayerStates`, because `setAllPlayerStates` opens with `table.clear`
	— so the set would be wiped by the very function that should be populating it. Populated in
	`enterStarting`, cleared in `enterIntermission`, `enterIdle` and `Init`.

	It is keyed by UserId and survives a disconnect ON PURPOSE: that is the entire point. `PlayerStates`
	is also keyed by UserId and now survives one too, and the two together are what let a returning
	player be resolved by `pure/RejoinResolve` instead of being blanket-marked SPECTATOR.
]]
local dealtIn: { [number]: boolean } = {}

--[[
	THE HUSKS. A disconnected player's body, left standing in the Barrio (§6.4, C15).

	Roblox removes a player's character when the Player object goes, so a body that outlives its owner
	has to be taken from them first — `player.Character = nil` and re-parent — which is exactly what
	`MonsterService.makeCorpse` already does for a kill. This is the same move for a different reason.

	WHY THIS EXISTS. Without it a survivor could Alt-F4 the moment they heard the transform and return
	invulnerable, because C01 marked every mid-round arrival SPECTATOR and a SPECTATOR cannot be killed.
	Resolving them to DEAD would close that but still pay the quitter — they would land with the full
	dead player feature set having never been caught. The husk makes quitting NEUTRAL: the body stays, the
	Aswang can kill it, and the owner comes back to whatever is true when they come back.

	THE HOLE THIS DOES NOT CLOSE, stated here so nobody discovers it as a surprise: Roblox does not
	guarantee a rejoining player the server they left. A quitter who lands on a different server never
	meets their husk. This deters the player who comes back HERE and does nothing about one who comes
	back anywhere.
]]
type Husk = {
	Character: Model,
	UserId: number,
}

local husks: { [number]: Husk } = {}
local husksFolder: Folder? = nil

local function clearHusk(userId: number)
	local husk = husks[userId]

	if husk == nil then
		return
	end

	husks[userId] = nil
	husk.Character:Destroy()
end

local function clearAllHusks()
	for userId in husks do
		clearHusk(userId)
	end

	table.clear(husks)
end

local function setAllPlayerStates(newState: PlayerState)
	--[[
		A PLAYER LEAVING DEAD LOSES THEIR BODY EXPLICITLY, AND THIS IS A C15 REGRESSION FIX.

		Until C15, `mayHaveBody("DEAD")` was false, so a dead player had no body and this function had
		nothing to clean up. C15 gave dead players bodies — and quietly removed the only thing that was
		destroying them, because `applyBodyRule`'s GRANT branch is gated on `player.Character == nil`
		and a dead player body is very much not nil. GRANT therefore no-ops and the dead player body SURVIVES the
		transition to LOBBY.

		What that shipped, before this fix: die in round N; in round N+1 you are ALIVE, invisible,
		non-collidable and still tagged `GhostBody` — and if the draw picks you, an INVISIBLE ASWANG,
		because `applyFullLook` writes Colour and Material and never Transparency. Two audits found it
		independently; `npm run verify` was green over it, which is this repo's recurring lesson.

		Detaching here rather than teaching GRANT to replace a body is deliberate: GRANT cannot tell a
		stale body from a correct one without knowing what state the character was BUILT for, and
		threading that through is a bigger change than the one bug needs. This function is the single
		place every player's state is rewritten at once, so it is the honest place for "your old body
		is no longer valid".
	]]
	local hadDeadBody: { Player } = {}

	if newState ~= Enums.PlayerState.Dead then
		for _, player in Players:GetPlayers() do
			if state.PlayerStates[player.UserId] == Enums.PlayerState.Dead then
				table.insert(hadDeadBody, player)
			end
		end
	end

	table.clear(state.PlayerStates)
	for _, player in Players:GetPlayers() do
		state.PlayerStates[player.UserId] = newState
	end

	-- BEFORE applyBodyRule, so the GRANT below finds `Character == nil` and builds a fresh, visible,
	-- collidable body rather than declining to act.
	for _, player in hadDeadBody do
		local character = player.Character

		player.Character = nil

		if character ~= nil then
			character:Destroy()
		end
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
-- V11 owns the win conditions in ACTIVE. Until then a round ends on the sunrise timer or on the
-- roster falling below MinPlayers, and on nothing else.
--------------------------------------------------------------------------------

local function enterIdle()
	state.AswangUserId = nil
	state.DealtInSurvivors = 0
	state.AswangKills = 0
	-- The live assignments go; RoleService's HISTORY deliberately survives, because it is the whole
	-- anti-repeat mechanism and a server that reset it every lobby would have no memory at all.
	RoleService.ClearRoles()
	-- The round is over, so nobody is dealt into it and no body should be standing in for anyone.
	-- Cleared here as well as in enterIntermission because IDLE is reachable directly (too few players).
	table.clear(dealtIn)
	clearAllHusks()
	-- Spectator status lifts here: whoever is on the server is a candidate for the next round.
	setAllPlayerStates(Enums.PlayerState.Lobby)
	setPhase(Enums.RoundPhase.Idle)
end

local function enterIntermission()
	RoleService.ClearRoles()
	--[[
		The dealt-in set and every husk go here, and the ORDER matters relative to setAllPlayerStates.

		A husk left standing into INTERMISSION is a body in the lobby with no owner, and — worse — the
		next round's `enterStarting` would deal its owner in fresh while their old body still stood in
		the plaza. Both tables describe ONE round and neither may outlive it.
	]]
	table.clear(dealtIn)
	clearAllHusks()
	setAllPlayerStates(Enums.PlayerState.Lobby)
	setPhase(Enums.RoundPhase.Intermission, Config.Round.Intermission)
end

local function enterStarting()
	state.RoundNumber += 1
	-- Everyone present when the round is drawn is dealt in. Anyone arriving from here until the
	-- next INTERMISSION and who is NOT in `dealtIn` becomes a SPECTATOR in onPlayerAdded.
	setAllPlayerStates(Enums.PlayerState.Alive)

	--[[
		AFTER setAllPlayerStates, not before, and this is the trap the plan called out by name:
		`setAllPlayerStates` opens with `table.clear(state.PlayerStates)`, so anything written into
		that table beforehand is destroyed. `dealtIn` is a separate table for exactly this reason, and
		populating it here — after the states are written, from the same roster — keeps the two in step.
	]]
	table.clear(dealtIn)
	clearAllHusks()

	for _, player in Players:GetPlayers() do
		dealtIn[player.UserId] = true
	end

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

	--[[
		GAMEPLAY SERVICES SUBSCRIBE TO PhaseChanged; this file must not call them. A service that needs
		`GetPlayerState`, `GetPhase` or `EndRound` from here cannot also be required BY here — that
		closes a load-time require cycle, which errors at load, `init.server.luau` swallows into a
		single warn, and leaves the server sitting in IDLE looking exactly like an empty lobby.

		MonsterService already subscribes rather than being called, for that reason. One direction
		only, and this is the wrong one. V03's container service arrives the same way.
	]]
	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
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

	--[[
		WRITTEN BEFORE `setPhase`, AND THAT ORDER IS LOAD-BEARING (C32).

		`setPhase` fires `PhaseChanged` synchronously, and `ProgressionService` subscribes to it to
		price §4.8's award table off `GetLastResult()`. Stamped afterwards, every round would be
		awarded against the PREVIOUS round's result — survivors paid for an escape they did not make,
		and the very first round of a server paid against the ABORTED default. Nothing would error and
		nothing on screen would name it; the XP would simply be wrong by one round, forever.
	]]
	state.LastResult = result

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

	DEAD, NOT A FIFTH STATE. §4.7 already calls a dead survivor a dead player, and Types.PlayerState has
	four values that this plan does not extend. Two consequences land immediately and both are wanted:
	pure/PlayerBody says a DEAD has no body, and pure/KillValidation says a DEAD is not a valid
	target — which is the C04 warning's "a dead player must not be killable", satisfied by construction
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

	state.PlayerStates[player.UserId] = Enums.PlayerState.Dead

	--[[
		KILLED, AND IT IS NOW A NO-OP FOR A DEAD — deliberately, and the cause is still passed.

		`BodyTransitions` answers KEEP for every DEAD cause since the C15 redesign, because a dead
		player's character IS THE CORPSE and `MonsterService` owns it. So this call changes nothing
		today. It stays for two reasons: the cause is the truthful description of what happened, and an
		audit found `"KILLED"` was previously passed by NOBODY, which made a tested cell unreachable
		from the running system.

		What it protects against is the reset/fall path. There, the dead character is still attached and
		the player becomes a DEAD — KEEP leaves that body exactly where it is, which is what a corpse
		is. Before the redesign this path left a player wearing a visible corpse that no rule owned; now
		the rule owns it by name.

		NO SECOND CALL, and no `lastRespawnAt` stamp. Both existed to make a dead player body spawn, and there
		is no dead player body to spawn any more.
	]]
	applyBodyRule(player, "KILLED")

	--[[
		THE ASWANG DIED, SO THE ROUND IS OVER. Mirrors onPlayerRemoving's abort exactly.

		That handler already ends the round when the Aswang DISCONNECTS, with the comment "end cleanly
		rather than leaving survivors wandering a monster-free map for six minutes". Routing non-kill
		deaths through here opened a second door to that same state which walked straight past it: the
		Aswang presses Escape → Reset, becomes a DEAD, `KillValidation` then refuses every RequestKill
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
		DEAD, still drops the alive count, and still shows on every HUD. It just does not advance the
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

	--[[
		THE VICTIM ONLY. Not `broadcastSnapshot()`, and the difference is Amendment A3's whole point.

		This line used to broadcast, on the reasoning that a bystander's payload was unchanged so the
		extra send carried nothing. An exploit audit showed that is false, and the attack is clean:
		snapshots otherwise arrive on a fixed `SnapshotInterval` cadence, so a client stamps arrivals
		and flags any gap under the interval as off-cadence. The only other off-cadence trigger is
		SELF-IDENTIFYING — a phase change ships `PhaseChanged` in the same frame. So: an early
		snapshot with the phase unchanged means SOMEBODY JUST DIED, to the millisecond, delivered to
		all eight clients. That is precisely the global sub-second death signal A3 removed
		`AlivePlayerCount` to kill; A3 deleted the payload and left the trigger.

		V01 REMOVED THE OTHER TWO TRIGGERS — the gate flip and the task count — and that NARROWS this
		channel rather than widening it: there is now exactly one benign off-cadence push to hide
		behind, so a broadcast here would be MORE legible than it was, not less. Anything V03 adds
		that pushes a snapshot off-cadence must be read against this paragraph before it ships.

		The victim is the only client whose snapshot actually changed — their own `YourState` is now
		DEAD — and they are the one screen guaranteed to be looked at. Everyone else waits for the
		next tick, which is what "death is not public" means.
	]]
	snapshotRemote:FireClient(player, buildSnapshot(player))

	if Config.Debug.VerboseLogging then
		-- A UserId and a count. Never a role, and never who did it — this line is read while a round is
		-- still running, and VerboseLogging is exactly the flag a Studio playtest leaves on.
		print(`[RoundService] Killed {player.UserId}; {aliveCount()} alive.`)
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
	--[[
		WHAT A MID-ROUND ARRIVAL BECOMES (§6.4, C15), decided by `pure/RejoinResolve` rather than here.

		This used to be an unconditional SPECTATOR for anyone arriving mid-round, and that was a live
		exploit: a SPECTATOR is uncounted, has no body and — since C05's "both alive" rule — CANNOT BE
		KILLED. Hear the transform, Alt-F4, come back, and you are invulnerable for the rest of the
		round. `tests/rejoin-resolve.test.luau` pins the cell that closes it.

		The rule is "stay as you were": a returning player who was dealt in resumes whatever state the
		server still holds for them. Their husk decides which one that is — untouched and they are
		still ALIVE, killed while they were gone and they are a DEAD. `onPlayerRemoving` preserves the
		entry rather than deleting it, which is what makes that lookup meaningful.
	]]
	local resolved = RejoinResolve.evaluate({
		Phase = state.Phase,
		WasDealtIn = dealtIn[player.UserId] == true,
		StoredState = state.PlayerStates[player.UserId],
	})

	-- The cast crosses a pure-module boundary: `RejoinResolve.PlayerState` and `Types.PlayerState` are
	-- the same structural union, but the analyzer widens the returned literals to plain `string` on the
	-- way out. Same bite CLAUDE.md documents for `Enums.RoundPhase.Idle`.
	state.PlayerStates[player.UserId] = resolved :: PlayerState

	--[[
		THE HUSK IS CONSUMED, NOT MERELY DISCARDED. It has served its purpose the moment its owner is
		back and re-stated: leaving it standing would put two bodies in the Barrio for one player, and
		the spare would still be killable, which is a second life rather than a deterrent.
	]]
	clearHusk(player.UserId)

	if Config.Debug.VerboseLogging and isRoundUnderway() then
		-- A UserId and a state. Never a role.
		print(`[RoundService] {player.UserId} arrived mid-round as {resolved}.`)
	end

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
	--[[
		THE HUSK (§6.4, C15). A disconnect during a live round leaves the body behind and CHANGES
		NOTHING about the player's state.

		This is the half that used to read `state.PlayerStates[player.UserId] = nil`, and dropping the
		entry is what made the returning player unaccountable — `onPlayerAdded` then had nothing to
		resolve against and marked them SPECTATOR, which is uncounted and unkillable. The entry now
		survives, and so does the body.

		The body has to be TAKEN before the Player object goes, because Roblox removes a character with
		its owner. `player.Character = nil` then re-parent is the same move `MonsterService.makeCorpse`
		makes for a kill, for a different reason: this body is still alive and still killable.

		A player who never returns leaves a husk standing until the round ends, and that is correct —
		they were dealt in, they are still counted, and the Aswang can still come for them. It is the
		absence of a free escape, which is the whole point.
	]]
	local dealtInThisRound = dealtIn[player.UserId] == true
	local shouldLeaveHusk = isRoundUnderway()
		and dealtInThisRound
		and state.PlayerStates[player.UserId] == Enums.PlayerState.Alive

	if shouldLeaveHusk then
		local character = player.Character
		local folder = husksFolder

		if character ~= nil and folder ~= nil then
			player.Character = nil
			character.Name = `Husk_{player.UserId}`
			character.Parent = folder

			--[[
				ANCHORED AND NON-COLLIDABLE, the same treatment `MonsterService.makeCorpse` gives a
				body and for the same reasons. A husk is a full rig with no owner: left collidable it
				is a wall players can stand on and hide behind, and left unanchored it is ragdoll
				physics the server simulates for nothing.

				It stays QUERYABLE on purpose — the Aswang has to be able to find and kill it, and the
				kill's own raycast excludes the husk folder wholesale rather than relying on the parts.
			]]
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
				end
			end

			husks[player.UserId] = { Character = character, UserId = player.UserId }
		end
		-- `state.PlayerStates` is deliberately NOT cleared on this path.
	else
		state.PlayerStates[player.UserId] = nil
	end

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
	-- short window to do it. This is still the ONLY `BindToClose` in the game; C31 filled it by way
	-- of a registry rather than by this service learning what a profile is. Anything else needing to
	-- run before the process dies calls `ShutdownFlush.register` in its own `Start()`.
	--
	-- SYNCHRONOUS AND YIELDING. `flushAll` calls its handlers on this thread; a DataStore write inside
	-- one is exactly the yield Roblox is waiting on here.
	ShutdownFlush.flushAll()

	if Config.Debug.VerboseLogging then
		print("[RoundService] Server closing — flush complete.")
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--[[
	THE HUSK SEAM FOR C15's KILL PATH. Two functions, deliberately narrow.

	A husk is a body with no `Player`, and `MonsterService.validateAndKill` opens with
	`Players:GetPlayerByUserId`, which returns nil for one. Without these the husk would be scenery and
	quitting would still be a free escape — the body would stand there unkillable, which is the exact
	exploit the husk exists to close, wearing a different shape.

	A HUSK IS ALWAYS A SURVIVOR, and that is guaranteed rather than assumed: `onPlayerRemoving` aborts
	the round outright when the Aswang leaves (see its comment), so the Aswang has no husk case at all.
	Callers may take `TargetIsAswang = false` for any husk, and `MonsterService` does.
]]
--[[
	The husk folder, for `MonsterService.hasLineOfSight`'s raycast filter.

	Exposed as the FOLDER rather than as a list of bodies so the exclusion is wholesale and cannot go
	stale between a husk being created and the next kill attempt — the same shape the corpse folder
	uses, for the same reason.
]]
function RoundService.GetHusksFolder(): Folder?
	return husksFolder
end

function RoundService.GetHuskCharacter(userId: number): Model?
	local husk = husks[userId]

	return if husk ~= nil then husk.Character else nil
end

--[[
	A husk was killed (§4.3, §6.4). The owner's stored state becomes DEAD, so when they reconnect
	`RejoinResolve` returns DEAD and they come back dead — which is what actually happened to them.

	The body is left in the world for `MonsterService` to turn into a corpse, exactly as a live
	player's is: the husk entry is dropped so nothing else claims it, but the Model is NOT destroyed
	here. Destroying it would delete the corpse before the corpse existed.
]]
function RoundService.MarkHuskKilled(userId: number)
	if husks[userId] == nil then
		return
	end

	husks[userId] = nil
	state.PlayerStates[userId] = Enums.PlayerState.Dead

	--[[
		The kill counts. §4.8's win condition is `AswangKills >= DealtInSurvivors - 2`, and a husk was
		dealt in and counted in `DealtInSurvivors` — so a husk kill that did not increment this would
		make the round unwinnable by exactly the number of people who quit. Amendment A1's whole point
		is that the win counts KILLS rather than presence, and this is a kill.
	]]
	state.AswangKills += 1

	if Config.Debug.VerboseLogging then
		print(`[RoundService] Husk of {userId} killed; {state.AswangKills} kill(s).`)
	end

	--[[
		NO SNAPSHOT PUSH AT ALL HERE, and that is not an omission.

		`MarkKilled` pushes to the victim because the victim's own `YourState` changed and they are
		watching. A husk's owner is DISCONNECTED — there is no client to send to. Broadcasting instead
		would be strictly worse than the bug the audit found in `MarkKilled`: an off-cadence snapshot
		to all eight clients announcing the death of somebody who was not even in the server, which no
		amount of "you had to find the body" covers. The corpse `makeCorpse` leaves behind is the
		signal, exactly as it is for a live kill.
	]]
end

function RoundService.Init()
	state.Phase = Enums.RoundPhase.Idle
	table.clear(state.PlayerStates)
	-- The dealt-in set is round-scoped and a fresh server is between rounds by definition. Cleared here
	-- as well as on both round exits, so a reloaded service cannot inherit a previous round's roster.
	table.clear(dealtIn)
	table.clear(husks)
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

	--[[
		One parent for every husk, so a round change clears them wholesale — the same shape
		`MonsterService`'s `Corpses` folder uses, and for the same reason: a body with no owner must
		never survive into the next round's lobby.
	]]
	local folder = Instance.new("Folder")

	folder.Name = "Husks"
	folder.Parent = workspace
	husksFolder = folder

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
