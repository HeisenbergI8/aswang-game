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

local CONTROLLER_ORDER = {
	"AudioController",
	"CameraFXController",
	"UIController",
	"QuickChatController",
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
-- TODO(M7): hand this off to UIController for the real HUD.
Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: string, duration: number)
	local label = if phase == Enums.RoundPhase.Active then "ROUND LIVE" else phase
	print(`[Client] Phase -> {label} ({duration}s)`)
end)

print(`[Client] Ready. {#CONTROLLER_ORDER} controllers loaded.`)
