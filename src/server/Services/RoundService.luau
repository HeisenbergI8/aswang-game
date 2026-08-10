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
local RoundTransitions = require(Shared.pure.RoundTransitions)
local Types = require(Shared.Types)

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

	snapshotRemote:FireClient(player, buildSnapshot(player))
end

local function onPlayerRemoving(player: Player)
	state.PlayerStates[player.UserId] = nil

	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end

	-- The Aswang rage-quits / disconnects: end cleanly rather than leaving
	-- survivors wandering a monster-free map for six minutes.
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)
	end

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
