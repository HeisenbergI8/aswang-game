--!strict
--[[
	OnboardingController — the first thing a new player is ever told (C20, §10).

	═══ WHY THIS FILE IS THE HIGHEST-LEVERAGE ONE IN THE CLIENT ══════════════════

	Appendix C is a teardown of the closest competitor: 2.5M visits, 1.43M players, **$0 earned**, and
	the number that explains it is that **79.9% of those players never completed a single objective**.
	They had seven zones, a mountain and unlockable weapons. Content was not the problem. A player
	spawned into a dark map with objectives somewhere in it and no reason to think any direction was
	right, and four out of five of them left without ever doing the thing the game is about.

	This controller removes that decision exactly once: on your first round the server names the live
	task nearest your spawn, and this draws a waypoint on it and says the one sentence that explains
	what to do when you arrive. Nothing else. §10 is explicit that the failure is a wall of text as
	much as it is silence.

	═══ EVERYTHING HERE IS LOCAL, AND THAT IS A SECRECY PROPERTY ═════════════════

	The waypoint is a `BillboardGui` parented to `PlayerGui` with its `Adornee` set to the task part.
	Adornee is the crucial half: it makes the GUI FOLLOW a part in the world without the GUI ever being
	PARENTED into the world. A Billboard parented onto the task point itself would be created by one
	client and — even client-side, where it does not replicate — is the exact shape that becomes a leak
	the moment someone "fixes" it by moving the creation to the server, at which point every player can
	see which of them are beginners.

	`.claude/lessons/absence-is-observable.md` is the general rule and it applies here in the mild
	direction: a marker only some players have is a difference between players. It is safe because the
	difference is "is new", which is not a role and is visible from behaviour anyway — but it is safe by
	argument, not by accident, and the argument is that nothing about it leaves this client.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local OnboardingController = {}

local TAG_POINT = "TaskPoint"
local TAG_DONE = "CompletedTaskPoint"

--[[
	LAYOUT AND COPY, in one block for the reason UIController's header gives: `check:config` flags every
	literal in `src/client/`, and scattering waivers through the file makes them invisible in a diff.
]]
local LAYOUT = {
	Width = 220, -- config-ok: waypoint billboard size in pixels, not balance
	Height = 56, -- config-ok: waypoint billboard size
	HeightOffset = 8, -- config-ok: how far above the task point the marker floats
	TextSize = 22, -- config-ok: waypoint type scale
	HintSize = 24, -- config-ok: teaching line type scale
	HintLift = 120, -- config-ok: keeps the teaching line clear of UIController's prompt row
	HintSeconds = 6, -- config-ok: how long the teaching line stays once shown
	Scrim = 0.3, -- config-ok: placeholder background opacity
}

local COLOUR = {
	Marker = Color3.fromRGB(255, 214, 92), -- config-ok: onboarding palette, not balance
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: onboarding palette
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: onboarding palette
}

--[[
	THE ONE LINE, and §10 asks for it "at the moment it's needed" rather than up front.

	It is shown when the player first comes within presence range of their objective — not on
	assignment, when they are 200 studs away and it would mean nothing, and not on a timer. A tutorial
	sentence that arrives while you are looking at the thing it describes is instruction; the same
	sentence at spawn is a wall of text with one brick in it.
]]
local TEACH_LINE = "Hold <b>E</b> to complete the task."

local objectiveId: string? = nil
local marker: BillboardGui? = nil
local markerLabel: TextLabel? = nil
local hint: TextLabel? = nil
local hintShown = false
local heartbeat: RBXScriptConnection? = nil

-- The streaming-retry listener, held here rather than only in its own closure so `clearObjective` can
-- tear it down. It used to self-disconnect only when SOME tagged part was next added, which for a
-- round that ended before the part streamed in meant it outlived the objective it was waiting for.
local pendingPoint: RBXScriptConnection? = nil

local function findPoint(id: string): BasePart?
	for _, instance in CollectionService:GetTagged(TAG_POINT) do
		if instance.Name == id and instance:IsA("BasePart") then
			return instance
		end
	end

	return nil
end

local function clearObjective()
	objectiveId = nil
	hintShown = false

	if marker ~= nil then
		marker:Destroy()
		marker = nil
		markerLabel = nil
	end

	if hint ~= nil then
		hint.Visible = false
	end

	if heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end

	if pendingPoint ~= nil then
		pendingPoint:Disconnect()
		pendingPoint = nil
	end
end

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
	label.Text = TEACH_LINE
	label.Visible = false
	label.Parent = gui

	hint = label
end

--[[
	The waypoint. A billboard rather than a Beam, and `AlwaysOnTop` rather than a line of sight test.

	§5's map is deliberately dark with heavy fog, so a marker that respects occlusion is a marker a new
	player cannot find — which is the failure this chunk exists to delete. Through-the-wall is the
	correct behaviour for exactly one task for exactly one round.

	A KNOWN DEVIATION FROM C20'S WORDING, recorded rather than glossed. The build plan asks for "a beam
	or arrow"; this is neither, and the difference is real: a beam or an arrow is DIRECTIONAL and tells
	a player facing the wrong way which way to turn, where a billboard only marks a destination already
	in frame. The distance readout below softens it — a number that does not change as you walk tells
	you that you are walking the wrong way — but it does not close it.

	It is shipped this way because the target is by construction the NEAREST live task, which bounds how
	wrong the initial facing can be, and because an off-screen arrow is a real piece of UI work that
	C34 owns. If GATE 1 shows new players still wandering, THIS is the thing to replace, and the
	replacement is an edge-of-screen arrow rather than anything about the server half.
]]
local function showMarker(point: BasePart)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local billboard = Instance.new("BillboardGui")

	billboard.Name = "FirstObjective"
	billboard.Adornee = point
	billboard.Size = UDim2.fromOffset(LAYOUT.Width, LAYOUT.Height)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LAYOUT.HeightOffset, 0)
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLOUR.Panel
	label.BackgroundTransparency = LAYOUT.Scrim
	label.BorderSizePixel = 0
	label.TextColor3 = COLOUR.Marker
	label.TextSize = LAYOUT.TextSize
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.Text = "YOUR TASK"
	label.Parent = billboard

	marker = billboard
	markerLabel = label
end

--[[
	Watches two things and stops as soon as either resolves: has the player arrived (show the line), and
	has the point been finished (clear everything).

	Finished is read off the `CompletedTaskPoint` tag rather than off a remote, because that tag is
	already the replicated truth `TaskController` renders from — one source, and it stays correct for a
	player who joined late or streamed the part in seconds ago.
]]
local function watch(point: BasePart)
	-- Guarded because the retry path below could resolve twice for one objective, and the second
	-- `Connect` would overwrite the handle to the first — leaving a Heartbeat running for the rest of
	-- the session, holding a reference to a part from a round that is over.
	if heartbeat ~= nil then
		return
	end

	heartbeat = RunService.Heartbeat:Connect(function()
		if objectiveId == nil then
			return
		end

		if CollectionService:HasTag(point, TAG_DONE) then
			clearObjective()
			return
		end

		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

		if root == nil or not root:IsA("BasePart") then
			return
		end

		local distance = (point.Position - root.Position).Magnitude

		--[[
			The distance readout, and it is the cheap half of the directionality this marker does not
			have — see `showMarker`'s deviation note. A billboard says WHERE; a number that grows as you
			move says you have chosen wrongly, which is most of what an arrow would have told you.

			Rounded to whole studs so it does not flicker every frame, and updated before the arrival
			check so it keeps counting down after the teaching line has been and gone.
		]]
		local label = markerLabel

		if label ~= nil then
			label.Text = `YOUR TASK · {math.floor(distance)}`
		end

		if hintShown then
			return
		end

		if distance > Config.Tasks.PresenceRangeStuds then
			return
		end

		hintShown = true

		ensureHint()

		local teach = hint

		if teach == nil then
			return
		end

		teach.Visible = true

		task.delay(LAYOUT.HintSeconds, function()
			if teach.Parent ~= nil then
				teach.Visible = false
			end
		end)
	end)
end

function OnboardingController.Init() end

function OnboardingController.Start()
	Remotes.Get("FirstObjectiveAssigned").OnClientEvent:Connect(function(taskId: string)
		--[[
			The part may not exist on this client YET. §5's `StreamingEnabled` means a task point 300
			studs away has not been replicated here, and the whole point of this remote is that the
			objective is the NEAREST one — so in practice it is streamed in, and the retry is for the
			edge where it is not rather than the common case.

			Retried on the tag's own added signal rather than on a poll, so it costs nothing while
			waiting and fires the moment the part arrives.
		]]
		clearObjective()
		objectiveId = taskId

		local point = findPoint(taskId)

		if point ~= nil then
			showMarker(point)
			watch(point)

			return
		end

		pendingPoint = CollectionService:GetInstanceAddedSignal(TAG_POINT)
			:Connect(function(instance: Instance)
				if
					objectiveId ~= taskId
					or instance.Name ~= taskId
					or not instance:IsA("BasePart")
				then
					return
				end

				-- Torn down through the same module local `clearObjective` owns, so there is exactly
				-- one place that disconnects this and no way to lose the handle. The stale-objective
				-- case is handled there too, rather than here on the next unrelated tag add.
				if pendingPoint ~= nil then
					pendingPoint:Disconnect()
					pendingPoint = nil
				end

				showMarker(instance)
				watch(instance)
			end)
	end)

	-- A round ending takes the waypoint with it. Without this a player who never reached their first
	-- objective keeps a marker pointing at a task point that is no longer part of any round.
	Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: Types.RoundPhase)
		if phase ~= Enums.RoundPhase.Active then
			clearObjective()
		end
	end)
end

return OnboardingController
