--!strict
--[[
	TaskController — the task bar, and the presence heartbeat. (§4.4, C08)

	IT OWNS NO TRUTH, and that is a testable claim rather than a slogan: delete every line of this file
	and no outcome the server produces changes. It cannot complete a task, it cannot advance a bar, it
	cannot choose which task point it is reporting. It says "I am holding" four times a second and
	renders whatever comes back. Apply that test to anything added here.

	Milestone M7 owns the real bar (C18). Today this is a cache with a print behind VerboseLogging, and
	`GetLatest` is the seam C18 draws from.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local TaskController = {}

-- The whole pool of twelve, tagged in the MAP rather than at runtime, so a lookup by id works before
-- this round's five are drawn and keeps working for a decoy id that is not in them.
local TAG_POINT = "TaskPoint"
local TAG_ACTIVE = "ActiveTaskPoint"
local TAG_DONE = "CompletedTaskPoint"
-- Set by TaskService on the carried prop. Marked for the same reason the points are: "bring the item"
-- is not an instruction if the item is an unlabelled grey cube 160 studs away.
local TAG_ITEM = "FetchItem"
local MARKER_NAME = "TaskMarker"

local latest: Types.TaskProgressPayload? = nil
local latestBar: Types.TimingBarPayload? = nil
-- When the last bar arrived, for `IsTimingBarLive` below. Seeded to zero rather than nil so the
-- comparison never has to be guarded twice.
local latestBarAt = 0
local taskList: { string } = {}
local holding = false

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: R/G/B indices, not tunables
end

--[[
	The five task points this client was told about, and the seam C18 draws the HUD list from.

	THIS CLIENT CANNOT TELL WHETHER ITS LIST IS TRUE, and it is not supposed to be able to. For
	exactly one player per round it is a decoy (§4.4 + Amendment A2, C12); the payload is identical in
	shape, length and timing either way, so there is nothing here to compare against and no branch to
	write. Do not add one — a client that could detect its own list was fake would be a client that
	knows it is the Aswang, which is the whole thing C12 is buying.
]]
function TaskController.GetTaskList(): { string }
	return table.clone(taskList)
end

function TaskController.GetLatest(): Types.TaskProgressPayload?
	return latest
end

--[[
	The seam C18 draws the moving bar from.

	`Phase` in the cached payload is where the bar was WHEN THE SERVER SENT IT. C18 renders the live
	position by advancing it — `(Phase + sinceReceived / Period) % 1` through
	`TimingWindow.positionFromPhase` — and that extrapolation is a RENDERING and nothing more. The
	server re-derives the phase from its own clock on every stop, so a client whose bar drifts,
	freezes or runs backwards gets exactly the same hit decision as one that renders it perfectly.
]]
function TaskController.GetLatestBar(): Types.TimingBarPayload?
	return latestBar
end

--[[
	IS THERE A BAR IN FRONT OF THIS PLAYER RIGHT NOW (C27).

	`GetLatestBar` deliberately never clears — the last bar of the round is still cached at the end of
	it, which is correct for a cache and useless as a question. C27's touch pad needs the question:
	the STOP button may only exist while there is something to stop, because a button that does
	nothing on a phone reads as a broken game rather than as a button in the wrong place.

	FRESHNESS RATHER THAN A CLEAR, and the window is `PresenceGraceSeconds` because it is already
	exactly this quantity. `TaskService` publishes a bar on its own tick to a player whose PRESENCE
	is current, and presence is what the hold heartbeat maintains — so a bar arrives roughly four
	times a second for as long as a thumb is down on ACT, and stops arriving when it lifts.

	`os.clock` rather than `tick` or `os.time`: monotonic, sub-millisecond, and unaffected by a
	client's wall clock. Nothing is sent, nothing is decided — the server re-derives the phase from
	its own clock on every stop, so a client that answered this wrongly would get the same hit
	decision either way.
]]
function TaskController.IsTimingBarLive(): boolean
	return latestBar ~= nil and (os.clock() - latestBarAt) <= Config.Tasks.PresenceGraceSeconds
end

--[[
	Set by InputController when the hold begins and ends, and by the ProximityPrompt at Step 6.3.

	A STUCK `true` COSTS RATE-LIMIT TOKENS AND NOTHING ELSE. The server re-measures distance on every
	tick, so a client left holding while its player walks away accumulates zero — the failure is a
	throttled player, not a free task, and it is self-inflicted. That is the property to preserve if
	this ever grows a second caller.
]]
function TaskController.SetHolding(value: boolean)
	holding = value
end

--[[
	THE AFFORDANCE, DRAWN HERE BECAUSE A ProximityPrompt COULD NOT DRAW IT.

	C08 put a prompt on each active point. Freeing the `E` key required `KeyboardKeyCode = None`, and
	Roblox's CoreScript refuses to render a prompt with no keycode — so the marker silently did not
	exist, and a manual playtest spent three rounds hunting unmarked pads. See TaskService, where the
	prompt used to be attached.

	STILL OWNS NO TRUTH. Both tags are set by the server and this reads them; the marker cannot make a
	task complete any more than the print below could. A player who deletes this file is exactly as
	able to finish a round, and exactly as unable to see where to.

	NO ROLE BRANCH, EVER. Every client renders identically — the Aswang's lie is the LIST it is told
	(`server/pure/TaskListView.luau`), never the world. A marker that differed for one player would be
	a confession on a stream, and it is the same rule the old prompt carried.
]]
local function markerFor(part: BasePart): BillboardGui
	local existing = part:FindFirstChild(MARKER_NAME)

	if existing ~= nil then
		return existing :: BillboardGui
	end

	local billboard = Instance.new("BillboardGui")

	billboard.Name = MARKER_NAME
	billboard.Size = UDim2.fromScale(6, 1.4) -- config-ok: placeholder label proportions, C18 replaces
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Config.Tasks.MarkerHeightStuds, 0)
	billboard.MaxDistance = Config.Tasks.MarkerVisibleStuds
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")

	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.4 -- config-ok: placeholder legibility, replaced by C18's HUD pass
	label.Parent = billboard

	billboard.Parent = part

	return billboard
end

--[[
	WHAT THIS POINT ACTUALLY ASKS FOR, which is not "hold E" on three points in four.

	The first version of this marker said "hold E" on every pad. A manual playtest reached 4/5, stood
	on a FETCH point pressing E, and watched `here:` alternate 0% and nil forever — presence lands,
	nothing accumulates, and the label is the reason the player believed it should. A marker that
	names the wrong verb is worse than no marker: it converts "I cannot find the task" into "the task
	is broken".

	The `TaskType` attribute is on the part and already replicates. It carries no role and no UserId —
	it is a property of a PLACE, set in the map, identical for every player. Reading it here adds no
	channel that C12 depends on: `server/pure/TaskListView` lies about WHICH points the Aswang is told
	to visit, never about what a point is once you are standing at it.

	Every type is named explicitly rather than defaulted, so a fifth type added to Enums.TaskType
	arrives here as a visible `?` in game instead of silently reading "hold E".
]]
local function verbFor(part: BasePart): string
	local taskType = part:GetAttribute("TaskType")

	if taskType == nil or taskType == Enums.TaskType.Hold then
		return "hold E"
	elseif taskType == Enums.TaskType.Timing then
		return "time it — R"
	elseif taskType == Enums.TaskType.Fetch then
		return "bring the item"
	elseif taskType == Enums.TaskType.TwoPerson then
		return "needs 2 people"
	end

	return `? unknown type "{taskType}"`
end

--[[
	THE ROUND-START LIST, WITH WHAT EACH POINT ACTUALLY WANTS.

	It used to print five bare ids. A manual playtest called that out precisely: "some tasks need to
	bring people or to bring item but it's not clearly on the first instructions". Correct — an id
	names a PLACE and says nothing about the errand, so the only way to learn that a point needs two
	survivors, or a 160-stud round trip, was to walk to it and read the marker. That is a route you
	cannot plan, and planning the route is most of what the five-of-twelve draw is for (§4.4).

	Looked up from the tagged parts rather than sent by the server, deliberately. The pads and their
	`TaskType` attributes already replicate, so this adds no channel — and critically it keeps C12
	intact WITHOUT needing to think about it: the Aswang is handed decoy ids and this describes
	exactly those, truthfully, which is the same lie it was already being told and no bigger one.

	This is a stop-gap for having no HUD. C18 owns the real list.
]]
local function padNamed(id: string): BasePart?
	for _, instance in CollectionService:GetTagged(TAG_POINT) do
		if instance.Name == id and instance:IsA("BasePart") then
			return instance
		end
	end

	return nil
end

local function describeList(ids: { string }): string
	local lines = {}

	for _, id in ids do
		local pad = padNamed(id)

		table.insert(
			lines,
			`  · {id} — {if pad ~= nil then verbFor(pad) else "not in the map?"}`
		)
	end

	return table.concat(lines, "\n")
end

local function paint(part: BasePart)
	local done = CollectionService:HasTag(part, TAG_DONE)
	local billboard = markerFor(part)
	local label = billboard:FindFirstChild("Label") :: TextLabel?

	if label == nil then
		return
	end

	label.Text = if done then "TASK ✓ DONE" else `TASK — {verbFor(part)}`
	label.TextColor3 =
		rgb(if done then Config.Tasks.MarkerCompleteRgb else Config.Tasks.MarkerActiveRgb)
end

--[[
	THE FETCH ITEM NEEDS A MARKER AS BADLY AS THE POINT DOES.

	The playtest's item was 160 studs away on an unmarked anchor. "Bring the item" is not actionable
	if the item is invisible, so this is the same fix as the pad marker, applied to the other half of
	the errand. `FetchItem` is tagged by the server for exactly this kind of lookup.
]]
local function paintItem(part: BasePart)
	local billboard = markerFor(part)
	local label = billboard:FindFirstChild("Label") :: TextLabel?

	if label == nil then
		return
	end

	label.Text = "ITEM — press E"
	label.TextColor3 = rgb(Config.Tasks.MarkerActiveRgb)
end

local function unpaint(part: BasePart)
	local existing = part:FindFirstChild(MARKER_NAME)

	if existing ~= nil then
		existing:Destroy()
	end
end

--[[
	Tag signals rather than a poll, and `GetTagged` first rather than only the signal.

	A tag added by the server BEFORE this controller connected fires no signal here, and that is the
	normal case for a player who joins mid-round or whose client starts a frame late — the round is
	already drawn. Reading the current set once at Start closes it. `GetInstanceRemovedSignal` covers
	teardown, so a marker cannot outlive the round that owns it.
]]
local function watchTag(tag: string, painter: (BasePart) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			painter(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		if instance:IsA("BasePart") then
			painter(instance)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		if not instance:IsA("BasePart") then
			return
		end

		-- Removed from ACTIVE means the round is over and the marker goes. Removed from DONE means
		-- the same teardown a beat earlier, so re-paint only while the point is still active.
		if CollectionService:HasTag(instance, TAG_ACTIVE) then
			paint(instance)
		else
			unpaint(instance)
		end
	end)
end

function TaskController.Init()
	latest = nil
	latestBar = nil
	latestBarAt = 0
	taskList = {}
	holding = false
end

function TaskController.Start()
	-- ACTIVE first: it is what creates a marker, and DONE only ever recolours one that exists.
	watchTag(TAG_ACTIVE, paint)
	watchTag(TAG_DONE, paint)
	watchTag(TAG_ITEM, paintItem)

	Remotes.Get("TaskProgressChanged").OnClientEvent
		:Connect(function(payload: Types.TaskProgressPayload)
			latest = payload

			if Config.Debug.VerboseLogging then
				local fill = if payload.YourTaskProgress ~= nil
					then `{math.floor(payload.YourTaskProgress * 100)}%`
					else "-"

				print(`[Task] {payload.TasksCompleted}/{payload.TasksRequired} · here: {fill}`)
			end
		end)

	Remotes.Get("TaskListAssigned").OnClientEvent:Connect(function(payload: Types.TaskListPayload)
		taskList = payload.TaskIds

		if Config.Debug.VerboseLogging then
			print(`[Task] list:\n{describeList(payload.TaskIds)}`)
		end
	end)

	Remotes.Get("TimingBarChanged").OnClientEvent:Connect(function(payload: Types.TimingBarPayload)
		latestBar = payload
		latestBarAt = os.clock()

		if Config.Debug.VerboseLogging then
			print(`[Task] bar {payload.TaskId} · {payload.Hits}/{payload.HitsRequired} hits`)
		end
	end)

	--[[
		THE HEARTBEAT. It reports PRESENCE and only presence — no task id, no elapsed time, no progress,
		no completion. `FireServer()` with no arguments is the entire message, and the server ignores
		anything a modified client adds to it because the handler's signature takes none.

		The interval is Config's, and tests/config.test.luau pins its reciprocal below
		AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond so an honest hold never throttles itself.
	]]
	task.spawn(function()
		while true do
			if holding then
				Remotes.Get("RequestTaskProgress"):FireServer()
			end

			task.wait(Config.Tasks.HeartbeatInterval)
		end
	end)
end

return TaskController
