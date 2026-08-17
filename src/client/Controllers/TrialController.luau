--!strict
--[[
	TrialController — what a player in the Solo Trial sees (C21/C22, §9.1).

	═══ IT RENDERS A DIFFERENT PANEL FROM THE ROUND HUD, DELIBERATELY ════════════

	The trial's timer is not a sunrise timer and its "1/2" is not the round's task bar. Drawing them
	in UIController's slots would teach a player to read those slots and then change what they mean —
	and, more practically, would leave the round HUD holding trial numbers if a push arrived out of
	order. A separate panel with its own position cannot be confused with the thing it is not.

	The types enforce the same separation from the other end: `Types.TrialSnapshot` shares no field
	name with `ClientRoundSnapshot`, so this controller could not render a round snapshot even if it
	were wired to the wrong remote — it would fail to typecheck.

	═══ IT OWNS NO WORDS ═════════════════════════════════════════════════════════

	Every teaching line goes through `OnboardingController.ShowLine`. There is one teaching-line slot
	on this screen and that controller owns it — see its header. This file maps a beat to a string and
	hands it over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local OnboardingController = require(script.Parent.OnboardingController)

local TrialController = {}

--[[
	LAYOUT, in one block for the reason UIController's and OnboardingController's headers give:
	`check:config` flags every literal in `src/client/`, and scattering waivers makes them invisible.
]]
local LAYOUT = {
	Width = 260, -- config-ok: trial panel size in pixels, not balance
	Height = 96, -- config-ok: trial panel size
	Inset = 24, -- config-ok: distance from the screen edge
	TitleSize = 20, -- config-ok: type scale
	BodySize = 26, -- config-ok: type scale
	ButtonHeight = 28, -- config-ok: leave-button size
	Scrim = 0.35, -- config-ok: placeholder background opacity
}

local COLOUR = {
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: trial palette, not balance
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: trial palette
	Accent = Color3.fromRGB(150, 210, 255), -- config-ok: deliberately NOT the HUD's sunrise amber
}

--[[
	THE COPY. Keyed by beat id, because the payload carries an id and never a string — player-facing
	text on the wire is a localisation and a trust problem for no gain.

	BEAT_TRANSFORM HAS NO LINE, AND THAT IS THE DESIGN. §9.1 says "you learn the tell". A caption over
	a transform tells you what you are seeing instead of letting you see it, which is precisely §10's
	"teach by doing, not by reading". The tell is the teaching.
]]
local COPY: { [string]: string } = {
	BEAT_WELCOME = "A quick run-through. Nobody else is here.",
	BEAT_TASKS = "Find the two glowing points. Hold <b>E</b> at each.",
	BEAT_SALT_GIVEN = "Take the salt.",
	BEAT_SALT_TAUGHT = "Salt burns the aswang — throw it to reveal and stun.",
	BEAT_HANDOFF = "Now do it when the monster is one of your friends.",
}

local panel: Frame? = nil
local timerLabel: TextLabel? = nil
local taskLabel: TextLabel? = nil

--[[
	Destroys the whole `ScreenGui`, not just the Frame inside it. `ensurePanel` creates a fresh
	ScreenGui on every call, so tearing down only the Frame left an empty ScreenGui behind per trial —
	a slow accumulation in PlayerGui across a session, invisible until someone opened the explorer.
]]
local function teardown()
	if panel ~= nil then
		local gui = panel:FindFirstAncestorWhichIsA("ScreenGui")

		if gui ~= nil then
			gui:Destroy()
		else
			panel:Destroy()
		end

		panel = nil
		timerLabel = nil
		taskLabel = nil
	end
end

local function ensurePanel()
	if panel ~= nil and panel.Parent ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Trial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "TrialPanel"
	frame.Size = UDim2.fromOffset(LAYOUT.Width, LAYOUT.Height)
	-- Top-LEFT, where the round HUD has nothing. The sunrise timer is top-centre and the task bar is
	-- beside it; a trial panel in either slot is the confusion this controller's header refuses.
	frame.Position = UDim2.fromOffset(LAYOUT.Inset, LAYOUT.Inset)
	frame.BackgroundColor3 = COLOUR.Panel
	frame.BackgroundTransparency = LAYOUT.Scrim
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, LAYOUT.TitleSize)
	title.BackgroundTransparency = 1
	title.TextColor3 = COLOUR.Accent
	title.TextSize = LAYOUT.TitleSize
	title.Font = Enum.Font.GothamBold
	title.Text = "SOLO TRIAL"
	title.Parent = frame

	local timer = Instance.new("TextLabel")
	timer.Size = UDim2.new(1, 0, 0, LAYOUT.BodySize)
	timer.Position = UDim2.fromOffset(0, LAYOUT.TitleSize)
	timer.BackgroundTransparency = 1
	timer.TextColor3 = COLOUR.Text
	timer.TextSize = LAYOUT.BodySize
	timer.Font = Enum.Font.GothamBold
	timer.Parent = frame

	local tasks = Instance.new("TextLabel")
	tasks.Size = UDim2.new(1, 0, 0, LAYOUT.BodySize)
	tasks.Position = UDim2.fromOffset(0, LAYOUT.TitleSize + LAYOUT.BodySize)
	tasks.BackgroundTransparency = 1
	tasks.TextColor3 = COLOUR.Text
	tasks.TextSize = LAYOUT.BodySize
	tasks.Font = Enum.Font.Gotham
	tasks.Parent = frame

	-- The way out, always visible. §9.1's trial is a thing you are OFFERED, and an offer you cannot
	-- decline halfway through is a thing you were made to do.
	local leave = Instance.new("TextButton")
	leave.Size = UDim2.new(1, 0, 0, LAYOUT.ButtonHeight)
	leave.Position = UDim2.new(0, 0, 1, -LAYOUT.ButtonHeight)
	leave.BackgroundTransparency = 1
	leave.TextColor3 = COLOUR.Accent
	leave.TextSize = LAYOUT.TitleSize
	leave.Font = Enum.Font.Gotham
	leave.Text = "leave the trial"
	leave.Parent = frame

	leave.Activated:Connect(function()
		-- No arguments: the server knows whose session it is. It re-checks everything regardless.
		Remotes.Get("RequestEndTrial"):FireServer()
	end)

	panel = frame
	timerLabel = timer
	taskLabel = tasks
end

--[[
	Whether THIS client is currently in a trial. Read by `InputController` to decide which throw
	remote Q fires — see its `performThrow`.

	It is derived from the panel's existence rather than from a separate flag, so there is exactly one
	piece of state and it cannot disagree with what the player can see. The server re-checks the
	session on every request regardless; this only picks which question to ask.
]]
function TrialController.IsActive(): boolean
	return panel ~= nil and panel.Parent ~= nil
end

function TrialController.Init() end

function TrialController.Start()
	Remotes.Get("TrialSnapshot").OnClientEvent:Connect(function(snapshot: Types.TrialSnapshot)
		if snapshot.TrialPhase == "TRIAL_OFF" then
			teardown()
			return
		end

		ensurePanel()

		local timer = timerLabel
		local tasks = taskLabel

		if timer ~= nil then
			local left = math.max(0, math.floor(snapshot.TrialSecondsLeft))

			timer.Text = `{left // 60}:{string.format("%02d", left % 60)}`
		end

		if tasks ~= nil then
			tasks.Text = `tasks {snapshot.TrialTasksDone}/{snapshot.TrialTasksRequired}`
		end

		--[[
			The beat's line, delegated. A push carries a `Beat` only on the tick it fired, so this
			runs once per beat rather than twice a second — the snapshot's other fields update
			continuously and the words do not.
		]]
		local beat = snapshot.Beat

		if beat ~= nil then
			local line = COPY[beat]

			if line ~= nil then
				OnboardingController.ShowLine(line)
			end
		end
	end)
end

return TrialController
