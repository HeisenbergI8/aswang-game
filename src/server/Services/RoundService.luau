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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type RoundPhase = Types.RoundPhase

local RoundService = {}

-- SERVER-ONLY state. Never replicate this table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	AswangUserId = nil :: number?,
	TasksCompleted = 0,
	GateOpen = false,
}

RoundService.PhaseChanged = Instance.new("BindableEvent")

local phaseChangedRemote = Remotes.Get("PhaseChanged")

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

local function eligiblePlayerCount(): number
	if Config.Debug.SoloTesting then
		return math.max(#Players:GetPlayers(), Config.Round.MinPlayers)
	end
	return #Players:GetPlayers()
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

	if Config.Debug.VerboseLogging then
		print(`[RoundService] -> {newPhase}{duration and ` ({duration}s)` or ""}`)
	end
end

--------------------------------------------------------------------------------
-- Phase handlers
--
-- TODO(M2): assign roles via RoleService in STARTING
-- TODO(M3): pick tasks via TaskService in STARTING, check win conditions in ACTIVE
-- TODO(M4): convert dead players to ghosts via GhostService
--------------------------------------------------------------------------------

local function enterIdle()
	state.AswangUserId = nil
	state.TasksCompleted = 0
	state.GateOpen = false
	setPhase(Enums.RoundPhase.Idle)
end

local function enterIntermission()
	setPhase(Enums.RoundPhase.Intermission, Config.Round.Intermission)
end

local function enterStarting()
	state.RoundNumber += 1
	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
	-- TODO(M2): RoleService.AssignRoles()
	-- TODO(M3): TaskService.SelectTasksForRound()
end

local function enterActive()
	setPhase(Enums.RoundPhase.Active, Config.Round.Duration)
end

local function enterEnding(result: string)
	setPhase(Enums.RoundPhase.Ending, Config.Round.EndScreen)
	-- The reveal. This is the moment players screenshot — make it dramatic.
	Remotes.Get("RoundEnded"):FireAllClients({
		Result = result,
		AswangUserId = state.AswangUserId, -- safe: the round is over
		RoundNumber = state.RoundNumber,
	})
end

-- Exposed so gameplay services can end a round early.
function RoundService.EndRound(result: string)
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

	if state.Phase == Enums.RoundPhase.Idle then
		if enoughPlayers then
			enterIntermission()
		end
	elseif state.Phase == Enums.RoundPhase.Intermission then
		if not enoughPlayers then
			enterIdle()
		elseif expired then
			enterStarting()
		end
	elseif state.Phase == Enums.RoundPhase.Starting then
		if expired then
			enterActive()
		end
	elseif state.Phase == Enums.RoundPhase.Active then
		if expired then
			-- Sunrise with tasks unfinished: the Aswang wins.
			enterEnding(Enums.RoundResult.Timeout)
		end
	elseif state.Phase == Enums.RoundPhase.Ending then
		if expired then
			if enoughPlayers then
				enterIntermission()
			else
				enterIdle()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Edge cases (see docs/MVP-SPEC.md §6.4 — these WILL bite you)
--------------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end

	-- The Aswang rage-quits / disconnects: end cleanly rather than leaving
	-- survivors wandering a monster-free map for six minutes.
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RoundService.Init()
	state.Phase = Enums.RoundPhase.Idle
end

function RoundService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			step()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
end

return RoundService
