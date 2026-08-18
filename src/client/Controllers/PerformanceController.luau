--!strict
--[[
	PerformanceController — §5's mobile budget, spent. (C27)

	§5 is hedged everywhere except here: the mobile performance budget is **non-negotiable**, because
	~60% of this game's players are on a phone and the failure is not a worse experience, it is a game
	that cannot be played during the one moment it is about — a chase.

	Its sharpest clause is "cap dynamic lights to ~8 visible at once — many point lights are the #1
	mobile FPS killer". `Config.Performance.MaxVisibleLights` has held that 8 since the scaffold and
	nothing read it. This controller reads it.

	═══ WHAT IT ACTUALLY DOES ══════════════════════════════════════════════════

	Once a second it asks `shared/pure/LightBudget` which of the barrio's tagged scenery lights this
	client should keep lit, and switches the rest off. The decision is distance from THIS camera, so
	the lanterns behind you and across the map stop costing you frames, and the ones you are walking
	toward do not.

	It also draws an FPS readout when `Debug.VerboseLogging` is on, which exists for exactly one
	reason: C27's done condition is "30fps sustained on a real phone during a chase", and there is no
	way to read that off Studio. The number has to be visible ON the phone, in the player's hand,
	while something is chasing them.

	═══ THE TWO THINGS IT IS NOT ALLOWED TO TOUCH ══════════════════════════════

	It only ever sees lights the greybox tagged `MapLight`. The Aswang's eye glow
	(`Monster.EyeGlowRgb`, on the character's Head) and a salt pouch's glow (`ItemService`) carry no
	such tag and are structurally invisible to this file — not skipped by a condition somebody could
	relax, but never collected in the first place.

	That is a secrecy property as much as a gameplay one. The eye glow is §4.3's warning and the pouch
	glow is how §4.6's counterplay is found; a culler that could switch either off would be deciding
	what a player is allowed to notice, and it would do so from a distance rule that a compromised
	client could invert into "light up everything, always". Instead the worst a tampered client
	achieves here is a slower phone with all twelve lanterns lit — which is not an advantage, and is
	already available to anyone who deletes this file.

	Every client runs the identical rule over its own camera, nothing reaches the server, and a lit
	lantern is lit for whoever stands next to it regardless of who they are. See
	`.claude/lessons/absence-is-observable.md`.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LightBudget = require(Shared.pure.LightBudget)

local PerformanceController = {}

--[[
	The tag is set by `tools/greybox/barrio.luau` on every scenery light it creates, and it is a MAP
	CONTRACT in exactly the sense that file's header describes: discovery by tag, never by name or by
	walking `workspace`.

	A map built before C27 carries no such tag, and the honest consequence is that this controller
	finds nothing and does nothing — the lights stay as the map left them. That is the right failure:
	a stale map costs frames, it does not go dark.
]]
local TAG_MAP_LIGHT = "MapLight"

local tracked: { Light } = {}
local candidates: { LightBudget.Candidate } = {}

local function isLight(instance: Instance): boolean
	return instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")
end

local function track(instance: Instance)
	if not isLight(instance) then
		return
	end

	for _, existing in tracked do
		if existing == instance then
			return
		end
	end

	table.insert(tracked, instance :: Light)
end

local function untrack(instance: Instance)
	local index = table.find(tracked, instance :: any)

	if index ~= nil then
		table.remove(tracked, index)
	end
end

--[[
	A light is a decoration on a part, and the part is what has a position.

	`Light.Parent` is a BasePart in every case the barrio produces. Anything else — a light parented
	to a Model, or one whose part has streamed out from under it — is skipped for this pass rather
	than dropped, because under `StreamingEnabled` a part that is gone now is frequently back in ten
	seconds and re-discovering it would mean walking the tag list again.
]]
local function positionOf(light: Light): Vector3?
	local parent = light.Parent

	if parent ~= nil and parent:IsA("BasePart") then
		return parent.Position
	end

	return nil
end

local lit = 0

--[[
	ONE PASS. Build the candidate list, ask the pure module, apply the answer by index.

	`candidates` is reused across passes rather than reallocated: this runs for the whole session and
	the list is the same twelve entries every time. `WasOn` is read from the live `Enabled` property
	rather than remembered, so an external change — a future cutscene, a plugin, a developer poking at
	Studio — is what the hysteresis term reasons about, instead of a private copy that has drifted.
]]
local function cull()
	local camera = workspace.CurrentCamera

	if camera == nil then
		return
	end

	local eye = camera.CFrame.Position
	local count = 0

	--[[
		`present` is the SAME INDEXING as `candidates`, and keeping them in step is the whole
		correctness condition here: `LightBudget.choose` answers by position in the list, so a light
		skipped for having no position must not consume an index. Hence a counter rather than
		`table.insert` on both — an append into one of two parallel arrays is how a cull ends up
		switching off the lantern next to the one it decided about.
	]]
	local present: { Light } = {}

	for _, light in tracked do
		local position = positionOf(light)

		if position == nil then
			continue
		end

		count += 1
		candidates[count] = {
			Distance = (position - eye).Magnitude,
			WasOn = light.Enabled,
		}
		present[count] = light
	end

	-- Trim, so a light that streamed out does not leave a stale distance behind for the next pass to
	-- rank against.
	for index = #candidates, count + 1, -1 do
		candidates[index] = nil
	end

	local decisions = LightBudget.choose({
		Candidates = candidates,
		Budget = Config.Performance.MaxVisibleLights,
		Reserved = Config.Performance.ReservedGameplayLights,
		CullRadiusStuds = Config.Performance.LightCullRadiusStuds,
		HysteresisStuds = Config.Performance.LightHysteresisStuds,
	})

	lit = 0

	for index = 1, count do
		local light = present[index]
		local on = decisions[index] == true

		if light.Enabled ~= on then
			light.Enabled = on
		end

		if on then
			lit += 1
		end
	end
end

--------------------------------------------------------------------------------
-- The readout, and why a debug HUD earns its place in this one chunk
--------------------------------------------------------------------------------

--[[
	C27's done condition cannot be checked from a desk: "30fps sustained on a real phone during a
	chase — the worst case, not the lobby". Studio's frame rate answers a different question, and
	Roblox's own stats overlay is awkward to reach on a phone and gone the moment you touch the
	screen to run.

	So the number is drawn on the HUD, behind `Debug.VerboseLogging` — already the flag that gates the
	client's console tracing, already pinned false for commits by `check:debug`, and already the thing
	a tester turns on before a session. It shows the frame rate, whether it is under §5's target, and
	the lit-light count, because "is the cull working" and "is the phone keeping up" are the same
	question asked twice.
]]
local LAYOUT = {
	Width = 150, -- config-ok: debug readout layout in pixels, not a balance knob
	Height = 22, -- config-ok: debug readout layout
	TextSize = 15, -- config-ok: debug readout type scale
	Inset = 12, -- config-ok: debug readout layout
	-- Clears the CoreGui topbar the same way UIController's TopInset does — a readout hidden behind
	-- the Roblox menu is a readout nobody can read on the device it was drawn for.
	TopInset = 76, -- config-ok: clears the CoreGui topbar cluster
	Scrim = 0.35, -- config-ok: placeholder background opacity
}

local COLOUR = {
	Ok = Color3.fromRGB(150, 230, 150), -- config-ok: debug palette, not balance
	Under = Color3.fromRGB(255, 96, 96), -- config-ok: debug palette
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: debug palette
}

local function buildReadout(): TextLabel
	local gui = Instance.new("ScreenGui")

	gui.Name = "PerfReadout"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")

	label.Name = "Fps"
	label.Size = UDim2.fromOffset(LAYOUT.Width, LAYOUT.Height)
	-- Top LEFT, deliberately: the HUD's timer owns the top centre and the quick-chat messages own the
	-- bottom left, so this is the one corner a readout can take without covering something a player
	-- is meant to be reading.
	label.Position = UDim2.fromOffset(LAYOUT.Inset, LAYOUT.TopInset)
	label.BackgroundColor3 = COLOUR.Panel
	label.BackgroundTransparency = LAYOUT.Scrim
	label.BorderSizePixel = 0
	label.TextColor3 = COLOUR.Ok
	label.TextSize = LAYOUT.TextSize
	label.Font = Enum.Font.Code
	label.Text = "--"
	label.Parent = gui

	return label
end

--[[
	Averaged over a whole second rather than shown per frame.

	An instantaneous 1/dt jitters by twenty frames between reads and is unreadable on a phone held at
	arm's length; the number a tester is trying to answer — "did it hold 30 through that chase" — is a
	sustained one anyway.
]]
local function trackFps(label: TextLabel)
	local frames = 0
	local elapsed = 0

	RunService.RenderStepped:Connect(function(delta: number)
		frames += 1
		elapsed += delta

		if elapsed < 1 then
			return
		end

		local fps = math.round(frames / elapsed)

		label.Text = `{fps} fps · {lit} lit`
		label.TextColor3 = if fps >= Config.Performance.TargetFPSMobile
			then COLOUR.Ok
			else COLOUR.Under

		frames = 0
		elapsed = 0
	end)
end

function PerformanceController.Init() end

function PerformanceController.Start()
	for _, instance in CollectionService:GetTagged(TAG_MAP_LIGHT) do
		track(instance)
	end

	--[[
		Both signals, because `StreamingEnabled` is on (§5, C17) and the barrio's far half genuinely
		is not in this client's DataModel most of the time. A one-shot scan at Start would cull an
		empty list forever on a map larger than the streaming radius.
	]]
	CollectionService:GetInstanceAddedSignal(TAG_MAP_LIGHT):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG_MAP_LIGHT):Connect(untrack)

	task.spawn(function()
		while true do
			task.wait(Config.Performance.LightCullIntervalSeconds)

			cull()
		end
	end)

	if Config.Debug.VerboseLogging then
		trackFps(buildReadout())
	end
end

return PerformanceController
