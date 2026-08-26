--!strict
--[[
	OnboardingController — the one-sentence teaching layer (C20/C23, §10).

	═══ WHAT IS LEFT OF THIS FILE AFTER V01 ═════════════════════════════════════

	It used to do two things: draw a waypoint on the new player's first task, and show a single line of
	copy at the moment it was needed. **V01 deleted the task system, so the waypoint went with it.** The
	line survives, and it is the half that generalises: `ShowLine` renders one sentence, low on screen,
	for `HintSeconds`, and `TrialService`'s cues and C23's `TeachingCue` both arrive through it.

	The waypoint is NOT reinstated for searching by default. V03 introduces containers and V17 owns the
	guaranteed first find; whether a new player needs a marker pointing at one is a question for the
	GATE 1 playtest (V16), not an assumption to carry over from a mechanic that no longer exists.

	═══ WHY THE COPY LAYER IS WORTH KEEPING ALONE ═══════════════════════════════

	Appendix C is a teardown of the closest competitor: 2.5M visits, 1.43M players, **$0 earned**, and
	the number that explains it is that **79.9% of those players never completed a single objective**.
	They had seven zones, a mountain and unlockable weapons. Content was not the problem — a player
	spawned into a dark map with no reason to think any direction was right. §10 is explicit that the
	failure is a wall of text as much as it is silence, so the answer is one sentence at the moment it
	is needed, which is exactly what this file still is.

	═══ EVERYTHING HERE IS LOCAL, AND THAT IS A SECRECY PROPERTY ════════════════

	The hint is a `TextLabel` in this client's own `PlayerGui` and nothing about it leaves the client.
	`.claude/lessons/absence-is-observable.md` is the general rule: a hint only some players see is a
	difference between players. It is safe because the difference is "is new", which is not a role and
	is visible from behaviour anyway — but it is safe by argument, not by accident, and the argument is
	that the server decides WHICH line is owed and the client only draws it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TeachingLines = require(Shared.pure.TeachingLines)

local OnboardingController = {}

--[[
	LAYOUT AND COPY, in one block for the reason UIController's header gives: `check:config` flags every
	literal in `src/client/`, and scattering waivers through the file makes them invisible in a diff.
]]
local LAYOUT = {
	HintSize = 24, -- config-ok: teaching line type scale
	HintLift = 120, -- config-ok: keeps the teaching line clear of UIController's prompt row
	HintSeconds = 6, -- config-ok: how long the teaching line stays once shown
	Scrim = 0.3, -- config-ok: placeholder background opacity
}

local COLOUR = {
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: onboarding palette
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: onboarding palette
}

local hint: TextLabel? = nil

-- Bumped on every ShowLine so an older hide-timer can tell it has been superseded. See ShowLine.
local lineToken = 0

local function ensureHint()
	if hint ~= nil and hint.Parent ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Onboarding"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Teach"
	label.Size = UDim2.new(1, 0, 0, LAYOUT.HintSize * 2)
	label.Position = UDim2.new(0, 0, 1, -LAYOUT.HintLift)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLOUR.Text
	label.TextSize = LAYOUT.HintSize
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.TextStrokeTransparency = 0
	label.Visible = false
	label.Parent = gui

	hint = label
end

--[[
	THE TEACHING-LINE SLOT, and after C21/C23 this controller owns it for the whole client.

	Three callers now: this file's own C20 arrival line, `TrialController`'s beats (C21/C22), and the
	`TeachingCue` handler (C23). They share a LABEL and nothing else — no state, no timer, no memory of
	what was shown. `hintShown` above stays private to the C20 objective and is not consulted here.

	A SIBLING CONTROLLER WOULD HAVE COLLIDED ON SCREEN. The label sits at `1, -LAYOUT.HintLift` with
	`HintLift = 120`, chosen to clear `UIController`'s prompt row. A second controller drawing its own
	teaching line would either duplicate that constant or pick a different one, and the two would
	overlap the first time a trial beat and a C23 cue landed together. There is one teaching-line slot
	on this screen and it should have one owner.

	FIRE-ONCE IS DELIBERATELY NOT THIS FUNCTION'S JOB. C20 tracks its own; C23's "once ever" lives on
	the server where it survives a rejoin. A `ShowLine` that remembered would give those two subtly
	different meanings of "once", and one of them would be wrong.

	LAST WRITER WINS, on purpose. Two lines inside `HintSeconds` of each other is a real possibility —
	a trial beat landing on a C23 cue — and the newer one describes what just happened. The pending
	hide is re-armed on every call rather than left to the older one, which would otherwise blank the
	newer line early.
]]
function OnboardingController.ShowLine(text: string)
	ensureHint()

	local teach = hint

	if teach == nil then
		return
	end

	teach.Text = text
	teach.Visible = true

	lineToken += 1

	local token = lineToken

	task.delay(LAYOUT.HintSeconds, function()
		-- The token is what makes re-arming safe: an older timer finds the counter moved on and does
		-- nothing, instead of hiding a line that replaced the one it was scheduled for.
		if token == lineToken and teach.Parent ~= nil then
			teach.Visible = false
		end
	end)
end

function OnboardingController.Init() end

function OnboardingController.Start()
	--[[
		C23. NO NEW LABEL AND NO NEW CONTROLLER — the cue resolves to copy through the same pure module
		the server used to decide it was owed, and renders through the same `ShowLine` this file
		already owns.

		THE COPY IS RESOLVED HERE RATHER THAN SENT. The payload is an id, so player-facing text never
		crosses the wire — a localisation and a trust problem avoided for no cost, since
		`shared/pure/TeachingLines` is replicated and the client can read it.

		FIRE-ONCE IS NOT CHECKED HERE. The server owns it and has already decided: receiving this
		remote at all means the server believes this player has not seen this line. Re-checking
		client-side against an empty local set would be a second, weaker answer to a question already
		settled — and it would be wrong after a rejoin, which is the case the server-side set exists
		for.
	]]
	Remotes.Get("TeachingCue").OnClientEvent:Connect(function(cueId: string)
		local line = TeachingLines.resolve(cueId, {})

		if line ~= nil then
			OnboardingController.ShowLine(line)
		end
	end)
end

return OnboardingController
