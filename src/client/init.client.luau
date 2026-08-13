--!strict
--[[
	Client bootstrap.

	Mirrors the server's two-phase lifecycle. Controllers own presentation and
	input only — they never own truth. Every meaningful decision is made on the
	server and sent down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CONTROLLER_ORDER = {
	"AudioController",
	"CameraFXController",
	"UIController",
	"QuickChatController",
	-- Before InputController, deliberately. The order governs Init/Start rather than requires — the
	-- require is direct — but InputController.Start binds a key that calls into this controller, and a
	-- bind that can fire before Init has run is a race worth not having.
	"TaskController",
	-- C15. Owns the ghost's LOCAL body — ghosts have no server character, because a replicated body
	-- per dead player named the dead set to every client. Before InputController for the same reason
	-- TaskController is: it reacts to snapshots and should be listening before any bind can fire.
	"GhostController",
	"InputController",
}

local controllersFolder = script:WaitForChild("Controllers")
local loaded: { [string]: any } = {}

for _, name in CONTROLLER_ORDER do
	local moduleScript = controllersFolder:FindFirstChild(name)
	if not moduleScript then
		warn(`[Client] Missing controller: {name}`)
		continue
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(`[Client] Failed to require {name}: {result}`)
		continue
	end

	loaded[name] = result
	if type(result) == "table" and type(result.Init) == "function" then
		local initOk, err = pcall(result.Init)
		if not initOk then
			warn(`[Client] {name}.Init() errored: {err}`)
		end
	end
end

for _, name in CONTROLLER_ORDER do
	local controller = loaded[name]
	if controller and type(controller.Start) == "function" then
		local startOk, err = pcall(controller.Start)
		if not startOk then
			warn(`[Client] {name}.Start() errored: {err}`)
		end
	end
end

-- Smoke test for M1: prove the round state machine is reaching the client.
-- TODO(C18): hand this off to UIController for the real HUD.
Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: string, duration: number)
	local label = if phase == Enums.RoundPhase.Active then "ROUND LIVE" else phase
	print(`[Client] Phase -> {label} ({duration}s)`)
end)

-- The snapshot arrives several times a second, so log only when something a player would notice has
-- actually changed. A per-tick print buries every other line in the output window, which is where
-- you will be looking when something breaks.
local lastSnapshotLine: string? = nil

Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
	local gate = if snapshot.GateOpen then "OPEN" else "shut"
	local tasks = `{snapshot.TasksCompleted}/{snapshot.TasksRequired}`
	-- No alive count. Amendment A3 removed the field; see the comment in Types.ClientRoundSnapshot for
	-- the names it must not come back under.
	local line = `{snapshot.Phase} round #{snapshot.RoundNumber} · tasks {tasks} · gate {gate}`
		.. ` · you: {snapshot.YourState}`

	if line == lastSnapshotLine then
		return
	end

	lastSnapshotLine = line
	print(`[Client] Snapshot — {line} ({math.floor(snapshot.SecondsRemaining)}s left)`)
end)

print(`[Client] Ready. {#CONTROLLER_ORDER} controllers loaded.`)
