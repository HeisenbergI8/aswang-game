--!strict
--[[
	Client bootstrap.

	Mirrors the server's two-phase lifecycle. Controllers own presentation and
	input only — they never own truth. Every meaningful decision is made on the
	server and sent down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CONTROLLER_ORDER = {
	"AudioController",
	"CameraFXController",
	--[[
		C28. Drives `Lighting` from the round clock — Appendix C.3's diegetic countdown. Early in the
		list because it CAPTURES the place's authored night at Start and lerps away from it: anything
		that touched Lighting first would be captured as though it were the night.
	]]
	"SkyController",
	--[[
		C27. §5's light cap, spent. Order is not load-bearing — it discovers its lights by tag and
		reacts to streaming — but it sits beside the sky because both are the mobile budget: one
		decides how much light there is, the other how much of it costs frames.
	]]
	"PerformanceController",
	"UIController",
	"QuickChatController",
	--[[
		C21/V01. Before InputController for the same reason everything else here is — it listens for a
		remote that can arrive the instant the round goes ACTIVE — and it now exists only for
		`ShowLine`: the objective waypoint went with the task system (V01).
	]]
	"OnboardingController",
	--[[
		C21. AFTER OnboardingController, and that ordering is a real dependency rather than a
		preference: this controller REQUIRES it, for `ShowLine`. A controller requiring a sibling is a
		new pattern in this codebase and it is deliberately one-way — `OnboardingController` knows
		nothing about the trial, so the arrow cannot become a cycle.

		Before InputController for the same reason as everything else in this list: it listens for a
		remote that can arrive the instant a trial opens.
	]]
	--[[
		V03. AFTER OnboardingController, and that ordering is a real dependency rather than a
		preference: this controller REQUIRES it, for `ShowLine`. One-way, exactly as TrialController's
		does — OnboardingController knows nothing about searching, so the arrow cannot become a cycle.

		Before InputController for the same reason as everything else in this list: it listens for a
		remote that can arrive the instant a key is pressed.
	]]
	"SearchController",
	--[[
		V06. AFTER OnboardingController, and that ordering is a real dependency rather than a
		preference: this controller REQUIRES it, for `ShowLine`. One-way, exactly as SearchController's
		is — OnboardingController knows nothing about feeding, so the arrow cannot become a cycle.
	]]
	"FeedController",
	"TrialController",
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

--[[
	Console tracing, and it is NOW GATED because C18 exists.

	These two connections were M1's smoke test — the only way to see that the round state machine was
	reaching the client at all — and the TODO here said to hand them to UIController for the real HUD.
	The HUD is built, so the handoff is done: a player reads the phase, the countdown and the task
	count off the screen, and nobody needs a print to know the round started.

	They are kept rather than deleted because the console is still where you look when the HUD is the
	thing that is broken, and a silent client is the worst possible state to debug. `VerboseLogging` is
	false on a published place, so this costs players nothing.
]]
Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: string, duration: number)
	if not Config.Debug.VerboseLogging then
		return
	end

	local label = if phase == Enums.RoundPhase.Active then "ROUND LIVE" else phase
	print(`[Client] Phase -> {label} ({duration}s)`)
end)

-- The snapshot arrives several times a second, so log only when something a player would notice has
-- actually changed. A per-tick print buries every other line in the output window, which is where
-- you will be looking when something breaks.
local lastSnapshotLine: string? = nil

Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
	if not Config.Debug.VerboseLogging then
		return
	end

	-- No alive count. Amendment A3 removed the field; see the comment in Types.ClientRoundSnapshot for
	-- the names it must not come back under.
	local line = `{snapshot.Phase} round #{snapshot.RoundNumber} · you: {snapshot.YourState}`

	if line == lastSnapshotLine then
		return
	end

	lastSnapshotLine = line
	print(`[Client] Snapshot — {line} ({math.floor(snapshot.SecondsRemaining)}s left)`)
end)

print(`[Client] Ready. {#CONTROLLER_ORDER} controllers loaded.`)
