--!strict
--[[
	QuickChatController — The radial quick-chat wheel.

	Milestone: M7, chunk C25. Spec §4.5.

	THIS IS THE COMMUNICATION SYSTEM, not a convenience on top of one. §4.5: voice chat requires 13+
	age verification most of this audience does not have, and typing on a phone mid-chase is
	impossible. Accusation gameplay with no way to accuse is not gameplay, which is why the spec says
	"do not cut it" in bold.

	WHAT THIS CONTROLLER OWNS AND WHAT IT DOES NOT
	----------------------------------------------
	It owns a wheel, a gesture, and the rendering of what arrives. It owns NO decision. The sequence
	is: the player picks a sector, this fires `RequestQuickChat` with a phrase ID and NOTHING ELSE,
	and the server decides who is named, where the ping lands and who hears it.

	In particular this controller never sends a name and never sends a position — see
	QuickChatService's header for why both would be exploits rather than shortcuts. It also never
	sends the phrase TEXT: the strings live in `shared/pure/QuickChatPhrases` and are rendered here
	from an id, which is what keeps user-generated text off the wire entirely.

	THE WHEEL IS A RADIAL MENU BECAUSE OF §5, NOT BECAUSE IT LOOKS GOOD. Eight sectors is 45 degrees
	each, so a thumb drag only has to be accurate to +/-22.5 degrees. A vertical list of eight items
	needs positional accuracy on a moving screen with a thumb covering the target. That difference is
	the entire reason this shape was chosen, and it is why `QuickChatPhrases.sectorFor` is a tested
	pure function rather than arithmetic inlined in a touch callback.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- One way, and it cannot become a cycle: `UIController` does not know this module exists — the pad's
-- SAY button calls whatever was registered with `BindQuickChat`, exactly as its action buttons call
-- whatever `InputController` registered with `BindActions`.
local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local QuickChatPhrases = require(Shared.pure.QuickChatPhrases)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local QuickChatController = {}

local WHEEL_ACTION = "QuickChatWheel"

--[[
	LAYOUT AND PALETTE, in one block for the reason UIController's header gives: `check:config` flags
	every literal in `src/client/`, and scattering waivers through the file makes them invisible in a
	diff. The numbers that are BALANCE rather than decoration — the wheel radius, the touch-target
	floor and the dead zone — live in `Config.QuickChat`, because those are the ones a playtest moves.
]]
local LAYOUT = {
	SectorSize = 110, -- config-ok: sector button size in pixels, not balance
	SectorTextSize = 15, -- config-ok: type scale
	MessageSize = 20, -- config-ok: type scale for a received phrase
	MessageInset = 220, -- config-ok: keeps the message column clear of the HUD prompt row
	MessageWidth = 420, -- config-ok: message column width
	PingSize = 44, -- config-ok: world ping marker size
	Scrim = 0.35, -- config-ok: placeholder background opacity
	HighlightScrim = 0.05, -- config-ok: the selected sector reads as selected
}

local COLOUR = {
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: quick-chat palette, not balance
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: quick-chat palette
	Highlight = Color3.fromRGB(255, 214, 92), -- config-ok: quick-chat palette
	Ping = Color3.fromRGB(150, 210, 255), -- config-ok: quick-chat palette
}

local wheelGui: ScreenGui? = nil
local wheelFrame: Frame? = nil
local sectorButtons: { [number]: TextLabel } = {}
local messageGui: ScreenGui? = nil
local messageList: Frame? = nil

local isOpen = false
local origin = Vector2.zero
local highlightedSector: number? = nil
local messages: { TextLabel } = {}

local function playerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

--------------------------------------------------------------------------------
-- The wheel
--------------------------------------------------------------------------------

local function buildWheel()
	if wheelGui ~= nil and wheelGui.Parent ~= nil then
		return
	end

	local gui = Instance.new("ScreenGui")

	gui.Name = "QuickChatWheel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = playerGui()

	local frame = Instance.new("Frame")

	frame.Name = "Wheel"
	frame.Size = UDim2.fromOffset(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	--[[
		THE SECTORS ARE PLACED FROM `sectorFor`'S OWN GEOMETRY, not from a hand-written table of
		offsets. Both the hit region and the selection therefore derive from one definition of "where
		is sector N", and they cannot drift apart — a wheel whose buttons sit somewhere the angle
		maths does not agree with is a wheel that selects the phrase next to the one you touched,
		which for this feature means accusing the wrong person.
	]]
	local tau = math.pi * 2
	local sectors = QuickChatPhrases.Sectors

	for _, phrase in QuickChatPhrases.All do
		local angle = phrase.Order * (tau / sectors)
		-- Screen Y grows downward, so `-cos` puts sector 0 at the top and the order runs clockwise,
		-- matching what `sectorFor` computes from a drag delta.
		local x = math.sin(angle) * Config.QuickChat.WheelRadiusPx
		local y = -math.cos(angle) * Config.QuickChat.WheelRadiusPx

		local label = Instance.new("TextLabel")

		label.Name = phrase.Id
		label.Size = UDim2.fromOffset(LAYOUT.SectorSize, LAYOUT.SectorSize)
		label.Position = UDim2.fromOffset(x - LAYOUT.SectorSize / 2, y - LAYOUT.SectorSize / 2)
		label.BackgroundColor3 = COLOUR.Panel
		label.BackgroundTransparency = LAYOUT.Scrim
		label.BorderSizePixel = 0
		label.TextColor3 = COLOUR.Text
		label.TextSize = LAYOUT.SectorTextSize
		label.Font = Enum.Font.GothamBold
		label.TextWrapped = true
		--[[
			THE WHEEL SHOWS A READABLE FORM; THE SENT MESSAGE SHOWS THE RESOLVED NAME.

			`phrase.Text` is a template, and for ACCUSE it is literally "It's {name}!" — correct, since
			the target is not known until the server picks one, and, sitting among seven phrases of
			plain English, it reads to a player as unfinished code. A playtest caught it.

			Substituted at the point of DISPLAY rather than by giving the phrase table a second string
			field: the table stays one source of truth, `renderMessage` still fills in the real name
			the server chose, and the test asserting "{name} appears iff the phrase needs a target" is
			untouched.
		]]
		label.Text = string.gsub(phrase.Text, "{name}", function()
			return "them"
		end)
		label.Parent = frame

		sectorButtons[phrase.Order] = label
	end

	wheelGui = gui
	wheelFrame = frame
end

local function highlight(sector: number?)
	if highlightedSector == sector then
		return
	end

	highlightedSector = sector

	for order, label in sectorButtons do
		local selected = order == sector

		label.BackgroundTransparency = if selected then LAYOUT.HighlightScrim else LAYOUT.Scrim
		label.TextColor3 = if selected then COLOUR.Highlight else COLOUR.Text
	end
end

--[[
	ONE GESTURE: press, drag, release. Not press-then-tap.

	THIS IS THE MOBILE DECISION, and it is worth being explicit about what it buys. A press-then-tap
	wheel needs the thumb to leave the screen and land accurately on a small target a second time,
	while the player is being chased and the camera is moving. Press-drag-release never lifts the
	thumb: the wheel opens under it, the selection is an ANGLE from where it started, and letting go
	commits. The accuracy required is +/-22.5 degrees of direction rather than a pixel position.

	It also gives cancel for free — drag back inside `DeadRadiusPx` and release, which is the gesture a
	player will try without being told.
]]
--[[
	WHERE THE WHEEL IS DRAWN, WHICH SINCE C27 IS NOT ALWAYS WHERE THE THUMB IS.

	`origin` — the point every angle is measured from — stays exactly where the press landed and is
	untouched by this. What is clamped is the PICTURE: a wheel opened at a press near a screen edge
	drew half its sectors off-screen, which on a phone is four phrases a player cannot read. C25 never
	hit it because a `ContextActionService` button and a mouse both land somewhere central; C27's pad
	puts the SAY button against the right edge on purpose, because that is where a thumb is.

	SEPARATING THE TWO IS SAFE PRECISELY BECAUSE THE SELECTION IS A DIRECTION. Sector 0 is drawn at
	the top of the wheel and is selected by dragging UP from wherever the press started, whatever the
	wheel's centre pixel happens to be — so the labels and the gesture still agree, which is the
	property C25's own comment says the wheel lives or dies by ("a wheel whose buttons sit somewhere
	the angle maths does not agree with... means accusing the wrong person").

	The alternative — moving `origin` to the clamped point — is the version that breaks it: the drag
	would start with a large delta already registered, so a press-and-release with no drag at all would
	fire whichever phrase the offset happened to point at.
]]
local function drawnCentre(pressPoint: Vector2): UDim2
	local camera = workspace.CurrentCamera

	if camera == nil then
		return UDim2.fromOffset(pressPoint.X, pressPoint.Y)
	end

	local viewport = camera.ViewportSize
	-- Half a sector past the ring, so the outermost pixel of the furthest label is still on screen.
	local margin = Config.QuickChat.WheelRadiusPx + LAYOUT.SectorSize / 2

	return UDim2.fromOffset(
		math.clamp(pressPoint.X, margin, math.max(margin, viewport.X - margin)),
		math.clamp(pressPoint.Y, margin, math.max(margin, viewport.Y - margin))
	)
end

local function openAt(screenPosition: Vector2)
	buildWheel()

	local frame = wheelFrame
	local gui = wheelGui

	if frame == nil or gui == nil then
		return
	end

	--[[
		THE WHEEL OPENS AT THE POINTER, NOT AT SCREEN CENTRE.

		A centred wheel on a phone means reaching across the screen with the hand that is also
		holding it. Opening under the press point is what makes this one-handed — the thumb is
		already where the wheel is. On desktop the same rule puts it under the cursor; see
		`originFor` for why those two are not the same expression.
	]]
	origin = screenPosition
	frame.Position = drawnCentre(screenPosition)
	gui.Enabled = true
	isOpen = true

	highlight(nil)
end

local function close()
	isOpen = false
	highlight(nil)

	local gui = wheelGui

	if gui ~= nil then
		gui.Enabled = false
	end
end

--[[
	Which sector is the drag pointing at, or nil for "inside the cancel radius".

	The angle maths is `math.atan2`, which returns (-pi, pi] — negative and wrapped values are the
	normal case here, not the edge case, which is why `QuickChatPhrases.sectorFor` is total over all
	reals and why its test enumerates the wrap.
]]
local function sectorAt(screenPosition: Vector2): number?
	local delta = screenPosition - origin

	if delta.Magnitude < Config.QuickChat.DeadRadiusPx then
		return nil
	end

	-- `atan2(x, -y)` rather than the usual `(y, x)`: screen Y grows downward, and this rotates the
	-- result so that zero is straight UP, matching how the sectors were placed above.
	return QuickChatPhrases.sectorFor(math.atan2(delta.X, -delta.Y))
end

local function commit()
	local sector = highlightedSector

	close()

	if sector == nil then
		return
	end

	for _, phrase in QuickChatPhrases.All do
		if phrase.Order == sector then
			--[[
				A PHRASE ID AND NOTHING ELSE. No name, no position, no text. See this file's header
				and QuickChatService's — every one of those would be a client naming something the
				server must decide.
			]]
			Remotes.Get("RequestQuickChat"):FireServer(phrase.Id)

			return
		end
	end
end

--------------------------------------------------------------------------------
-- Received messages and world pings
--------------------------------------------------------------------------------

local function buildMessageList()
	if messageGui ~= nil and messageGui.Parent ~= nil then
		return
	end

	local gui = Instance.new("ScreenGui")

	gui.Name = "QuickChatMessages"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui()

	local list = Instance.new("Frame")

	list.Name = "Messages"
	list.Size = UDim2.fromOffset(
		LAYOUT.MessageWidth,
		LAYOUT.MessageSize * Config.QuickChat.MaxVisibleMessages
	)
	list.Position = UDim2.new(0, LAYOUT.SectorTextSize, 1, -LAYOUT.MessageInset)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")

	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	messageGui = gui
	messageList = list
end

--[[
	Render one received phrase.

	THE TEXT IS BUILT HERE, FROM AN ID, and the name is resolved locally from a UserId. Neither the
	phrase nor the display name ever crossed the wire — which is the whole reason there is no
	`TextService` call anywhere in this feature. See QuickChatService's header.

	A name that cannot be resolved falls back to "someone" rather than rendering an empty slot: the
	accused may have left between the server naming them and this client drawing it, and "It's !"
	reads as a broken game rather than as a player who left.
]]
local function renderMessage(payload: Types.QuickChatBroadcastPayload)
	local phrase = QuickChatPhrases.get(payload.PhraseId)

	if phrase == nil then
		return
	end

	buildMessageList()

	local list = messageList

	if list == nil then
		return
	end

	local sender = Players:GetPlayerByUserId(payload.SenderUserId)
	local senderName = if sender then sender.DisplayName else "someone"
	local text = phrase.Text

	if payload.TargetUserId ~= nil then
		local target = Players:GetPlayerByUserId(payload.TargetUserId)
		local targetName = if target then target.DisplayName else "someone"

		--[[
			THE FUNCTION FORM, because `%` is magic in a gsub REPLACEMENT string. A display name
			containing one raises "invalid use of '%' in replacement string" inside this
			`OnClientEvent` handler, which Roblox swallows into a warn and drops the message on this
			client only. The function form does no interpretation at all.
		]]
		text = string.gsub(text, "{name}", function()
			return targetName
		end)
	end

	local label = Instance.new("TextLabel")

	label.Size = UDim2.new(1, 0, 0, LAYOUT.MessageSize)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLOUR.Text
	label.TextSize = LAYOUT.MessageSize
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextStrokeTransparency = 0
	label.Text = `{senderName}: {text}`
	label.LayoutOrder = os.clock() // 1
	label.Parent = list

	table.insert(messages, label)

	-- Oldest out first, so a busy moment does not push the HUD off screen.
	while #messages > Config.QuickChat.MaxVisibleMessages do
		local oldest = table.remove(messages, 1)

		if oldest ~= nil then
			oldest:Destroy()
		end
	end

	task.delay(Config.QuickChat.MessageLifetimeSeconds, function()
		local index = table.find(messages, label)

		if index ~= nil then
			table.remove(messages, index)
		end

		if label.Parent ~= nil then
			label:Destroy()
		end
	end)
end

--[[
	The world ping.

	A `BillboardGui` in PlayerGui with an `Adornee`, exactly as `OnboardingController`'s waypoint is,
	and for the same reason: `Adornee` makes a GUI follow a world position without the GUI ever being
	PARENTED into the world. The anchor part is client-created and never replicates.

	⚠ UNCONFIRMED: whether a client-created `Part` in `workspace` stays local under §5's
	`StreamingEnabled` is not established anywhere in this repo. Conventionally it does. If a
	playtest shows otherwise, the fallback named in the plan is to parent the anchor to `Camera`.
]]
local function renderPing(position: Vector3)
	local anchor = Instance.new("Part")

	anchor.Name = "QuickChatPing"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")

	billboard.Name = "QuickChatPingMarker"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(LAYOUT.PingSize, LAYOUT.PingSize)
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.Parent = playerGui()

	local dot = Instance.new("TextLabel")

	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundTransparency = 1
	dot.TextColor3 = COLOUR.Ping
	dot.TextSize = LAYOUT.PingSize
	dot.Font = Enum.Font.GothamBold
	dot.TextStrokeTransparency = 0
	dot.Text = "◆"
	dot.Parent = billboard

	task.delay(Config.QuickChat.PingLifetimeSeconds, function()
		billboard:Destroy()
		anchor:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

--[[
	THE ORIGIN COMES FROM THE INPUT ONLY WHEN THE INPUT HAS ONE, and this is a bug a playtest found in
	Studio that no static check could have.

	`ContextActionService` hands the same callback both the touch button and the `B` key. For a TOUCH
	input, `inputObject.Position` is the real screen coordinate the thumb landed on. For a KEYBOARD
	input it is `(0, 0, 0)` — a key press has no location — so the first version opened the wheel
	pinned to the top-left corner of the screen for every mouse-and-keyboard player, with the sectors
	clipped off the edge. The file's own header claimed "THE WHEEL OPENS AT THE THUMB", which was true
	for exactly one of the two input paths.

	`analyze`, `lint` and every Lune suite passed over it. It took pressing the key in a running game.
]]
local function originFor(inputObject: InputObject): Vector2
	local fromInput = Vector2.new(inputObject.Position.X, inputObject.Position.Y)

	--[[
		A touch or mouse press at a genuine (0,0) is the very top-left pixel — indistinguishable from
		the keyboard's "no position", and not somewhere a thumb realistically lands. Falling back to
		the cursor there is correct for the keyboard and harmless for the vanishing touch case.
	]]
	if fromInput.Magnitude > 0 then
		return fromInput
	end

	return UserInputService:GetMouseLocation()
end

local function onWheelAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	inputObject: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		openAt(originFor(inputObject))

		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End and isOpen then
		commit()

		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

function QuickChatController.Init() end

function QuickChatController.Start()
	--[[
		`createTouchButton = true`, and this is the one bind in the client that most needs it: §5 puts
		~60% of players on a phone and §4.5's whole argument is that they cannot type.

		`B` REACHES THIS HANDLER — confirmed at C27 alongside `R` and `Q`. Held down in a live Play
		session it opened the wheel with all eight sectors drawn, so no CoreScript claims it in this
		place: `.claude/plans/c27-c28-verification/artifacts/desktop-keys-console.txt`. It is still a
		PLACEHOLDER as a design choice — nothing has argued `B` is the RIGHT key — but it is no longer
		an unknown.

		The second ⚠ that stood here is moot rather than answered: whether two requested CAS touch
		buttons stack predictably was never established, and C27 removed the question by taking both
		touch buttons away. `UIController`'s pad is the hand-placed fallback that note anticipated.
	]]
	ContextActionService:BindAction(WHEEL_ACTION, onWheelAction, false, Enum.KeyCode.B)

	--[[
		C27: THE PAD OWNS THE BUTTON, THIS FILE OWNS THE WHEEL.

		`createTouchButton` was `true` above and is now `false`, and the reason it was true has not
		gone away — §5 puts ~60% of players on a phone and §4.5's whole argument is that they cannot
		type. What changed is that `UIController` now draws every touch control in the game, in thumb
		zones it chooses, so SAY sits beside the other five verbs instead of wherever the CoreGui put
		it. This file's own header flagged the unknown that made the old arrangement uncomfortable:
		whether a second requested CAS button stacks predictably above the first was never
		established, and now there is no second one to find out about.

		Registered rather than required, so the arrow points one way: `UIController` knows nothing
		about this module, and this module reaches it through a call it makes itself. The gesture is
		still whole — the pad reports the press point and the release, and everything between them,
		including the drag, the highlight and the cancel radius, is decided here.
	]]
	UIController.BindQuickChat({
		Open = openAt,
		Commit = commit,
	})

	--[[
		The drag is read from a Heartbeat rather than from `InputChanged`, so touch and mouse take the
		same path and a drag that leaves the button's own region still tracks. Costs one vector
		subtraction per frame while the wheel is open, and nothing at all while it is closed.
	]]
	RunService.Heartbeat:Connect(function()
		if not isOpen then
			return
		end

		highlight(sectorAt(UserInputService:GetMouseLocation()))
	end)

	Remotes.Get("QuickChatBroadcast").OnClientEvent
		:Connect(function(payload: Types.QuickChatBroadcastPayload)
			renderMessage(payload)

			if payload.PingPosition ~= nil then
				renderPing(payload.PingPosition)
			end
		end)
end

return QuickChatController
