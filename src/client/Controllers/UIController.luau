--!strict
--[[
	UIController — the HUD (C18, milestone M7).

	Sunrise timer, salt indicator, contextual prompts, the Aswang's action
	buttons, and the end screen with the reveal. It replaces the C13-C16 placeholder wholesale, as that
	placeholder's own header asked to be replaced.

	C18 built this ugly and functional on purpose. C26 has since done the half of the polish that does
	not need an opinion — motion on change, edge definition, text that survives any background, and a
	reveal with three beats instead of none. See the MOTION block for where that line was drawn.

	THE PALETTE AND THE TYPEFACE ARE STILL PLACEHOLDERS. §C26 says the theming pass is "informed by
	what GATE 1 told you", and GATE 1 has not run — so anything here that looks like TASTE is still a
	decision six humans have not made yet, even though the craft around it is now finished.

	═══ THE ALIVE COUNT IS NOT HERE, AND THAT IS THE SPEC, NOT AN OMISSION ═══════

	`BUILD-PLAN.md` §C18 listed "sunrise timer, global task bar, alive count — all from RoundSnapshot".
	V01 removed the task bar with the task system, and Amendment A3 removed the alive count long before
	that; the sunrise timer is what is left, and V15 rebuilds this HUD around the v2 loop.
	Three of those exist. The fourth is forbidden by **Amendment A3** (MVP-SPEC v1.3), which outranks
	the build plan and names this chunk directly:

	  > C18's planned HUD alive-count element has no data source and must not be given one — not under
	  > this name and not under another (SurvivorsRemaining, DeadCount, a roster the client can count).

	`ClientRoundSnapshot.AlivePlayerCount` was pushed to every client twice a second plus an immediate
	extra push the instant a kill landed. That is a sub-second global death signal, and a death signal
	is the missing input to an attack this genre does not survive: record replicated character
	positions, timestamp each kill from the decrement, then ask who was within `Monster.KillRange` of
	the victim's last position. In the open that is frequently one candidate.

	Do not compute it here either. A client-side tally over anything the client can observe — bodies,
	characters, a roster, `YourState` transitions — is the same oracle with the arithmetic moved. If
	C19 says players are lost without it, A3 says the answer is DIEGETIC and latency-bearing: a board
	in the plaza someone walks to, a tally the quick-chat wheel can assert. That is a GATE 1 design
	decision, not a field and not a label.

	═══ WHAT MAY DIFFER BETWEEN TWO CLIENTS' SCREENS ════════════════════════════

	THIS CONTROLLER HOLDS THE ONLY COPY OF THE ROLE THAT EXISTS ON ANY CLIENT, and it is this client's
	OWN role, received on RoleAssigned. Two rules follow and they are not stylistic:

	  · `myRole` is a module local. It is never written to an attribute, a StringValue, the character,
	    or anything under ReplicatedStorage or Workspace — all of which replicate.
	  · Nothing on screen may differ between a survivor's client and the Aswang's EXCEPT what only that
	    player can see. A recording of the Aswang's screen is a confession; a recording of anyone
	    else's must not be.

	The action buttons are the sharpest case of that second rule and they are safe for a specific
	reason rather than a general one: they live in `Players.LocalPlayer.PlayerGui`, which replicates to
	exactly one player. A button parented anywhere under `workspace` or onto the character — a Billboard
	over the Aswang's head, a Tool in the backpack — would be the same feature and a total leak.
	`.claude/lessons/absence-is-observable.md` is the long version: a difference between players IS the
	leak, in either direction.

	This controller must never learn anyone else's role. The one exception is the reveal on RoundEnded,
	which is sanctioned precisely because the round is over by then (§4.8).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.pure.Cosmetics)
local TrialAdmission = require(Shared.pure.TrialAdmission)
local Types = require(Shared.Types)

local UIController = {}

--[[
	LAYOUT, IN ONE BLOCK, WAIVED ONCE EACH.

	`check:config` flags every numeric literal in `src/client/` that is not 0, 1, 2, -1, 0.5 or 100,
	which is the correct threshold for a gameplay knob and the wrong one for a pixel offset. The two
	honest ways to satisfy it are a `Config.Hud` section or per-line waivers, and both were considered:

	  · `Config.Hud` would put forty layout numbers into the file whose entire value is that EVERY
	    number in it is a balance decision worth arguing about at M12. Diluting that costs more than it
	    buys — a HUD offset is never the answer to "does the Aswang win too often".
	  · scattering `-- config-ok:` through four hundred lines makes the waiver invisible, which defeats
	    the point of a waiver being greppable in a diff.

	So every literal in this file lives in this block or the `COLOUR` one below it, waived once each,
	and the rest of the file refers to names. `grep -n "config-ok" UIController.luau` returns the two
	tables, the two seconds-in-a-minute divisors, and the startup wait — nothing scattered.
]]
local LAYOUT = {
	Pad = 12, -- config-ok: HUD layout in pixels, not a balance knob
	BarHeight = 18, -- config-ok: HUD layout
	TimerSize = 44, -- config-ok: HUD type scale
	LabelSize = 18, -- config-ok: HUD type scale
	PromptSize = 20, -- config-ok: HUD type scale
	RevealSize = 34, -- config-ok: HUD type scale
	ButtonWidth = 150, -- config-ok: HUD layout
	ButtonHeight = 54, -- config-ok: HUD layout
	StatusWidth = 300, -- config-ok: HUD layout
	StatusHeight = 96, -- config-ok: HUD layout
	BarWidth = 320, -- config-ok: HUD layout

	-- How far the bottom prompt sits above the screen edge. Clears the mobile jump button, which is
	-- drawn bottom-right by the CoreGui and is the one control this HUD must not sit under.
	PromptLift = 36, -- config-ok: HUD layout

	--[[
		CLEARS ROBLOX'S OWN TOPBAR. `IgnoreGuiInset` puts this GUI in the same space as the CoreGui
		logo, menu, chat and voice buttons, which draw ON TOP — the placeholder learned this the hard
		way by hiding the phase and the countdown behind them, the two lines a tester needs most.
	]]
	TopInset = 76, -- config-ok: clears the CoreGui topbar cluster

	Scrim = 0.35, -- config-ok: placeholder background opacity

	-- The end screen is a TAKEOVER, not a panel: it dims the map far harder than the HUD does, so the
	-- reveal is the only lit thing on screen.
	RevealScrim = 0.12, -- config-ok: end-screen background opacity
	BarBackScrim = 0.55, -- config-ok: placeholder background opacity

	-- When the sunrise timer starts reading as urgent. Presentation, not balance: the round is not
	-- affected, the number just turns red so a player looks up.
	UrgentSeconds = 30, -- config-ok: when the timer turns red; changes nothing about the round

	-- Corner rounding and edge stroke. Restrained on purpose — see the MOTION block's note about
	-- what C26 may and may not decide before GATE 1 has run.
	Corner = 6, -- config-ok: HUD layout
	StrokeWeight = 1, -- config-ok: HUD layout
	StrokeScrim = 0.75, -- config-ok: HUD palette
	TextStroke = 0.5, -- config-ok: HUD legibility over an unknown background

	--[[
		THE TOUCH PAD (C27), AND EVERY NUMBER HERE IS A THUMB MEASUREMENT RATHER THAN A PIXEL ONE.

		The build plan's line is "thumb zones, not desktop positions scaled down", and the constraint
		that actually decides these five numbers is the one a desk cannot show you: a phone's usable
		GUI height in landscape is around 400, of which the CoreGui topbar takes the first 76 and
		Roblox's own jump button owns the bottom-right corner. A five-button column at desktop sizes
		does not fit on the screen at all — it runs off the top.

		So the pad is TWO SHORT COLUMNS rather than one tall one: the survivor's three verbs at the
		right edge under the thumb, and the Aswang's two beside them, which caps the tallest possible
		stack at three buttons however many are visible.

		`TouchBottomInset` is the load-bearing one. It lifts the whole pad clear of the jump button,
		which is drawn by the CoreGui and cannot be moved — a pad that overlapped it would trade the
		hold for the jump at the exact moment a player is running.
	]]
	TouchButton = 60, -- config-ok: touch target size in pixels, not a balance knob
	TouchGap = 8, -- config-ok: touch pad layout
	TouchTextSize = 14, -- config-ok: touch pad type scale
	TouchRightInset = 16, -- config-ok: touch pad layout
	TouchBottomInset = 150, -- config-ok: clears the CoreGui jump button
}

--[[
	MOTION, AND THE LINE BETWEEN "ANIMATED" AND "THEMED".

	C26's done condition is "every HUD element themed, readable, and animated on change; the reveal has
	weight". Three of those four words are craft and one is taste, and GATE 1 has not run — so this
	chunk does the craft in full and the taste conservatively. Concretely:

	  · ANIMATED ON CHANGE and READABLE are answerable without six humans. A bar that steps twice a
	    second is a bar that steps twice a second; white text with no stroke is unreadable over a bright
	    wall whoever is looking at it. Both are fixed here properly.
	  · THEMED is where a palette, a typeface and an identity get chosen, and §C26 says explicitly that
	    it happens "informed by what GATE 1 told you". So the palette below is unchanged from C18, and
	    what is added is only edge definition and legibility — the parts that help ANY theme read.

	WHY THESE DURATIONS. They are shorter than one snapshot so they finish before the value they describe can change
	again — an animation still running when its own input moves is how a HUD ends up showing a number
	that was true a second ago.
]]
local MOTION = {
	Colour = 0.25, -- config-ok: HUD motion, not balance
	Pulse = 0.18, -- config-ok: HUD motion
	PulseScale = 1.35, -- config-ok: how far a changed number overshoots before settling
	Fade = 0.4, -- config-ok: HUD motion

	-- The reveal's beats. The headline lands, the room holds, then the name. The hold is the whole
	-- point of §4.8 calling this "the screenshot people share" — a name that appears simultaneously
	-- with the result is information, and information is not drama.
	RevealFade = 0.5, -- config-ok: HUD motion
	RevealHold = 1.1, -- config-ok: the pause before the name lands
	RevealRise = 24, -- config-ok: how far the reveal line travels as it fades in
}

--[[
	The palette, and it is RGB TRIPLES for the same reason Config's are: `Config.Monster`,
	`Config.Monster` and `Config.Salt` store colours as `{ r, g, b }` rather than as `Color3`, so
	that a value is data rather than a constructed object.

	These are not in Config because they are not shared with the server and nothing balances against
	them. The Aswang red and the survivor blue in particular are C26's theming pass to replace, once
	GATE 1 has said whether the HUD reads at all. (This said C34 for two chunks; C34 is "Six cosmetics"
	and has nothing to do with the HUD.)
]]
local COLOUR = {
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: HUD palette, not balance
	Dim = Color3.fromRGB(178, 178, 178), -- config-ok: HUD palette
	Urgent = Color3.fromRGB(255, 96, 96), -- config-ok: HUD palette
	Aswang = Color3.fromRGB(255, 85, 85), -- config-ok: HUD palette
	Survivor = Color3.fromRGB(136, 221, 255), -- config-ok: HUD palette
	Dead = Color3.fromRGB(170, 170, 255), -- config-ok: HUD palette
	Progress = Color3.fromRGB(96, 220, 120), -- config-ok: HUD palette
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: HUD palette

	--[[
		C32/C33/C34's two, and they are two rather than reused because the checklist rule is that a
		colour carries ONE meaning on a screen. `Progress` green is in-round progress, so borrowing it
		for a level bar would mean the same colour saying two things to a player who has just spent
		seven minutes learning the first.

		They only ever appear in the lobby, so they never share a screen with the round palette.
	]]
	Coin = Color3.fromRGB(240, 198, 96), -- config-ok: HUD palette
	Level = Color3.fromRGB(206, 128, 255), -- config-ok: HUD palette
}

--[[
	THE BUTTONS DO NOT KNOW HOW TO TRANSFORM OR KILL. `InputController` tells them.

	They fired their remotes directly at first and the KILL button shipped BROKEN because of it:
	`RequestKill` takes a target UserId, the button sent none, and `MonsterService`'s handler consumes
	a rate-limit token BEFORE its `typeof(targetUserId) ~= "number"` guard. So every tap was a silent
	no-op that spent one of `Config.AntiCheat.Budgets.RequestKill`'s three tokens — three taps and the
	Aswang's next real `F` press is refused for seconds, with a warn in the log naming them. Found by
	`exploit-auditor`, and neither `analyze` nor any of the five checks could have: the shapes are
	identical and only the arity differs.

	The lesson generalises past the missing argument. A button that assembles its own request is a
	SECOND implementation of an action, and the second one drifts — here it skipped `nearestTarget()`
	AND the no-target early return, both of which are the keyboard path's real work.

	So the dependency is INVERTED rather than mirrored: `InputController` already requires this module
	for `GetMyRole`, so it cannot be required back without a cycle. It registers its handlers here at
	Start, and the buttons invoke exactly what the keys invoke.

	C27 EXTENDS THE SAME REGISTRATION TO THE OTHER THREE VERBS rather than inventing a second
	mechanism for the touch pad. `Act` and `Throw` are what `E`, `R` and `Q` already run, handed over
	by the same call at Start, so the phone and the keyboard remain ONE implementation with several
	triggers. Every argument above applies unchanged — and applies harder, because a touch button is
	the only trigger 60% of players have.
]]
export type ActionHandlers = {
	Transform: () -> (),
	Kill: () -> (),
	Throw: () -> (),
	--[[
		V03, §4.4. A PAIR, because searching is a HOLD and not a tap. The pad reports when the thumb
		goes down and when it comes up — exactly as the quick-chat wheel's press-drag-release does —
		and registering only a `Search` would give a mobile player a way to start a search and no way
		to stop one.

		NEITHER IS DRAWN BY `buildTouchPad` YET. That is a real gap and not a rounding error:
		searching is the ONLY activity in the game (§4.4), and §5 puts ~60% of players on a phone.
		The contract is widened here so the pad chunk finds both ends waiting for it.
	]]
	Search: () -> (),
	CancelSearch: () -> (),
}

--[[
	THE WHEEL IS REGISTERED SEPARATELY BECAUSE IT BELONGS TO A DIFFERENT CONTROLLER.

	`QuickChatController` owns the wheel, its geometry and its gesture; this file owns the button that
	starts one. Registration inverts that dependency the same way `BindActions` does — nothing here
	requires the quick-chat module, so neither can require the other back — and it stays a PAIR
	because §4.5's gesture is press-drag-release rather than a tap: the pad reports where the thumb
	went down and when it came up, and every decision in between is the wheel's.
]]
export type QuickChatHandlers = {
	Open: (origin: Vector2) -> (),
	Commit: () -> (),
}

local actionHandlers: ActionHandlers? = nil
local quickChatHandlers: QuickChatHandlers? = nil

function UIController.BindActions(handlers: ActionHandlers)
	actionHandlers = handlers
end

function UIController.BindQuickChat(handlers: QuickChatHandlers)
	quickChatHandlers = handlers
end

-- This client's OWN role, and nothing else. Read the header before adding to this.
local myRole: Types.Role? = nil

function UIController.GetMyRole(): Types.Role?
	return myRole
end

--[[
	Salt carried, counted BY THIS CLIENT from its own pickups and throws.

	The server owns the real number and never sends it: a per-player count on a broadcast remote is a
	shape `check:secrecy` cannot describe, and a per-player DOWN remote carrying it would be a new
	network surface needing its own secrecy argument. So this is a display estimate, prefixed `~` on
	screen so a tester reads it as a hint rather than a truth.
]]
local saltSeen = 0

--------------------------------------------------------------------------------
-- Construction. Every element is made once and then only updated, so `render`
-- allocates nothing while the world is holding still — it runs at
-- Config.Round.SnapshotInterval, several times a second, for the whole round.
-- C26's tweens are the one exception and they are edge-triggered precisely so
-- that the exception stays rare; see the tween helpers below.
--------------------------------------------------------------------------------

--[[
	LAST-RENDERED VALUES, WHICH ARE THE WHOLE ANIMATION SYSTEM.

	`render` is level-triggered — it receives the current state of the world twice a second and has no
	idea what changed. Animation is edge-triggered by definition. These four locals are the adapter
	between the two, and they are the reason `tweenTo` is never called for a value that is already
	where it should be.

	They are seeded to values no first snapshot can equal (-1, and nil for the flags) so the first
	render after a join sets everything without animating — a HUD that plays four transitions the
	instant it appears looks broken, not alive.
]]
local lastUrgent: boolean? = nil

local hud: ScreenGui? = nil
local timerLabel: TextLabel? = nil
local phaseLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local promptLabel: TextLabel? = nil
local actionFrame: Frame? = nil

--[[
	C27's touch pad, and the two locals are separate because they have different lifetimes: the frame
	is destroyed with the HUD, the button table is how `render` reaches five buttons without a
	`FindFirstChild` twice a second for the whole round.
]]
local touchPad: Frame? = nil
local touchButtons: { [string]: TextButton } = {}

--[[
	EDGE DEFINITION, AND WHY A PANEL NEEDS IT AT ALL.

	Every panel is a translucent black rectangle over the map. At `Scrim = 0.35` that is 65% of
	whatever is behind it, so over the barrio's dark geometry the panel has no visible boundary and the
	text inside it appears to float on the world. A one-pixel stroke and a rounded corner cost nothing,
	commit to no palette, and turn four floating labels into four things that are obviously UI.

	This is the "readable" half of C26's done condition rather than the "themed" half — see MOTION.
]]
local function panel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.BackgroundColor3 = COLOUR.Panel
	frame.BackgroundTransparency = LAYOUT.Scrim
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, LAYOUT.Corner)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOUR.Text
	stroke.Thickness = LAYOUT.StrokeWeight
	stroke.Transparency = LAYOUT.StrokeScrim
	stroke.Parent = frame

	frame.Parent = parent

	return frame
end

--[[
	`TextStrokeTransparency` is the single highest-value line in this file for readability.

	The HUD draws over a map whose brightness this controller does not know and, after C28 drives
	`Lighting.ClockTime` from the round clock, cannot know — the background legitimately changes from
	night to sunrise underneath a label that is not told about it. White text on the sunrise is white
	on white. A dark outline makes every label survive any background, at no cost and with no theme
	decision taken.
]]
local function text(parent: Instance, name: string, size: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = colour
	label.TextSize = size
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.TextStrokeColor3 = COLOUR.Panel
	label.TextStrokeTransparency = LAYOUT.TextStroke
	label.Text = ""
	label.Parent = parent

	return label
end

--[[
	THE TWEEN HELPERS, AND THE ALLOCATION RULE THEY EXIST TO KEEP.

	`render` runs at `Config.Round.SnapshotInterval` for the whole round, and this file's construction
	comment promises it never allocates. `TweenService:Create` DOES allocate, so the promise is kept a
	different way: nothing here is called unless the value it animates actually CHANGED since the last
	snapshot. At steady state — a bar that has not moved, a timer that is not crossing the urgency
	threshold — the render path allocates exactly nothing, as before.

	That is also what "animated ON CHANGE" means literally. Tweening every frame toward a value that
	is already correct is not animation, it is a slower render.
]]
local EASE = Enum.EasingStyle.Quad

local function tweenTo(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, EASE, Enum.EasingDirection.Out), goal)
		:Play()
end

--[[
	The Aswang's action buttons.

	They exist here rather than as `ContextActionService` touch buttons because CAS creates a touch
	button for EVERY client that runs the bind, and `InputController` binds transform and kill on all
	of them — the role gate is inside the handler, not on the bind. A CAS touch button would therefore
	appear on every mobile screen. Identical for everyone, so not a leak, but a survivor tapping a
	transform button that silently does nothing is worse UX than no button.

	This also closes half of a known hole: `InputController`'s header records that neither bind makes a
	touch button, so mobile — ~60% of the audience per §5 — could not transform or kill at all. Full
	mobile is C27's subject; the Aswang's two verbs are the half that made the game unplayable rather
	than awkward.
]]
local function makeActionButton(
	parent: Instance,
	name: string,
	label: string,
	order: number
): TextButton
	local button = Instance.new("TextButton")

	button.Name = name
	button.Size = UDim2.fromOffset(LAYOUT.ButtonWidth, LAYOUT.ButtonHeight)
	button.Position = UDim2.fromOffset(0, (LAYOUT.ButtonHeight + LAYOUT.Pad) * order)
	button.BackgroundColor3 = COLOUR.Panel
	button.BackgroundTransparency = LAYOUT.Scrim
	button.BorderSizePixel = 0
	button.TextColor3 = COLOUR.Aswang
	button.TextSize = LAYOUT.LabelSize
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = parent

	return button
end

--------------------------------------------------------------------------------
-- The touch pad (C27, §5)
--------------------------------------------------------------------------------

--[[
	IS THIS A PHONE.

	`TouchEnabled and not KeyboardEnabled` rather than `TouchEnabled` alone, because a Windows laptop
	with a touchscreen reports both — and a player with a keyboard already has every verb bound to a
	key. The pad is for the device that has no other way in.

	Read once, at build time, rather than watched. `LastInputTypeChanged` would let the pad appear and
	vanish as a player alternated between a controller and a screen, and a control that disappears
	mid-round is worse than one that is always there: the pad costs a phone nothing when unused, and
	costs a desktop nothing because it is never built.
]]
local function isTouchDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--[[
	One round button. Circular, because a round target reads as "press me" at a size where a label
	does not, and because `UICorner` at half the height costs nothing.

	`AutoButtonColor` is off and the press is drawn by hand: the stock highlight is a brightness shift
	that is invisible over the barrio at night, which is the entire lighting condition this game is
	played in.
]]
local function makeTouchButton(
	parent: Instance,
	name: string,
	label: string,
	order: number,
	colour: Color3
): TextButton
	local button = Instance.new("TextButton")

	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(LAYOUT.TouchButton, LAYOUT.TouchButton)
	button.BackgroundColor3 = COLOUR.Panel
	button.BackgroundTransparency = LAYOUT.Scrim
	button.BorderSizePixel = 0
	button.TextColor3 = colour
	button.TextSize = LAYOUT.TouchTextSize
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextWrapped = true
	button.AutoButtonColor = false
	button.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = colour
	stroke.Thickness = LAYOUT.StrokeWeight
	stroke.Transparency = LAYOUT.StrokeScrim
	stroke.Parent = button

	-- Feedback the player can see in the dark: the ring solidifies while the thumb is down. Connected
	-- for every input type rather than for Touch alone, so the pad behaves identically if it is ever
	-- shown on a device with a mouse.
	button.InputBegan:Connect(function()
		stroke.Transparency = 0
	end)

	button.InputEnded:Connect(function()
		stroke.Transparency = LAYOUT.StrokeScrim
	end)

	button.Parent = parent

	return button
end

local function touchColumn(parent: Instance, name: string, xOffset: number): Frame
	local column = Instance.new("Frame")

	column.Name = name
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0, LAYOUT.TouchButton, 1, 0)
	column.Position = UDim2.fromOffset(xOffset, 0)
	column.Parent = parent

	local layout = Instance.new("UIListLayout")

	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, LAYOUT.TouchGap)
	layout.FillDirection = Enum.FillDirection.Vertical
	-- Bottom-aligned, so the stack grows UPWARD from the thumb rather than downward from a fixed top
	-- edge. A hidden button collapses out of the column and the ones below it do not move — which is
	-- what stops the Aswang's verbs appearing and shifting the hold button out from under a thumb
	-- that is already reaching for it.
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = column

	return column
end

--[[
	THE PAD ITSELF, WITH THE FIVE VERBS 60% OF THIS AUDIENCE OTHERWISE HAS NO ACCESS TO.

	Before C27 a phone could transform, kill and throw salt — the first two through the desktop-shaped
	buttons in the corner, the third through a `ContextActionService` touch button whose position
	Roblox chooses. It could not do a TASK, which is what all eight players do all round, and it could
	not stop a TIMING bar. `InputController`'s header has carried that hole as a named defect since
	C08.

	The pad closes it and takes over the two CAS buttons at the same time, so there is exactly ONE
	system placing touch controls in this game. That was worth doing on its own: C25's header records
	that whether a second requested CAS button stacks predictably above the first was never
	established, and two systems placing buttons is a collision nobody can debug from a screenshot.

	RIGHT COLUMN: the verbs everyone has, most-used at the bottom.
	LEFT COLUMN: the Aswang's two, which only exist on the Aswang's own screen — the same
	PlayerGui-only argument the desktop buttons rest on, in the same file, for the same reason.
]]
local function buildTouchPad(gui: ScreenGui)
	if not isTouchDevice() then
		return
	end

	local pad = Instance.new("Frame")

	pad.Name = "TouchPad"
	pad.BackgroundTransparency = 1
	pad.AnchorPoint = Vector2.new(1, 1)
	pad.Size = UDim2.fromOffset(
		LAYOUT.TouchButton * 2 + LAYOUT.TouchGap,
		LAYOUT.TouchButton * 3 + LAYOUT.TouchGap * 2 -- config-ok: three buttons and two gaps
	)
	pad.Position = UDim2.new(1, -LAYOUT.TouchRightInset, 1, -LAYOUT.TouchBottomInset)
	pad.Visible = false
	pad.Parent = gui

	local aswangColumn = touchColumn(pad, "Aswang", 0)
	local mainColumn = touchColumn(pad, "Main", LAYOUT.TouchButton + LAYOUT.TouchGap)

	local transform = makeTouchButton(aswangColumn, "Transform", "SHIFT", 1, COLOUR.Aswang)
	local kill = makeTouchButton(aswangColumn, "Kill", "KILL", 2, COLOUR.Aswang)
	local say = makeTouchButton(mainColumn, "Say", "SAY", 1, COLOUR.Text)
	local salt = makeTouchButton(mainColumn, "Salt", "SALT", 2, COLOUR.Progress)
	touchButtons = {
		Transform = transform,
		Kill = kill,
		Say = say,
		Salt = salt,
	}
	touchPad = pad

	--[[
		EVERY ONE OF THESE INVOKES A REGISTERED HANDLER AND BUILDS NOTHING.

		The rule is C18's, learned the expensive way — see `BindActions` above. A button that
		assembles its own `FireServer` is a second implementation of a verb, and the second one
		drifts. On a phone that would be worse than it was on the desktop: the key path would still
		work, so the bug would be invisible to the person writing it and total for the person playing.
	]]
	transform.Activated:Connect(function()
		local handlers = actionHandlers

		if handlers ~= nil then
			handlers.Transform()
		end
	end)

	kill.Activated:Connect(function()
		local handlers = actionHandlers

		if handlers ~= nil then
			handlers.Kill()
		end
	end)

	salt.Activated:Connect(function()
		local handlers = actionHandlers

		if handlers ~= nil then
			handlers.Throw()
		end
	end)

	--[[
		THE WHEEL OPENS WHERE THE THUMB IS, NOT WHERE THE BUTTON IS.

		`QuickChatController` places the wheel at the point it is handed, and §4.5's gesture is
		press-drag-release without lifting. So the origin passed here is the real touch coordinate:
		opening at the button's own centre would work identically for the maths and put the wheel a
		thumb-width from where the player is actually looking.
	]]
	say.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local handlers = quickChatHandlers

		if handlers ~= nil then
			handlers.Open(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	say.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local handlers = quickChatHandlers

		if handlers ~= nil then
			handlers.Commit()
		end
	end)
end

local function buildHud()
	if hud ~= nil and hud.Parent ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")

	gui.Name = "Hud"
	gui.ResetOnSpawn = false -- survives a respawn, and a ghost has no respawn to survive
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	hud = gui

	-- Top centre: the sunrise countdown, the largest thing on screen because it is the one number
	-- every player is acting on.
	local timerPanel = panel(gui, "Timer")
	timerPanel.Size =
		UDim2.fromOffset(LAYOUT.BarWidth, LAYOUT.TimerSize + LAYOUT.LabelSize + LAYOUT.Pad)
	timerPanel.Position = UDim2.new(0.5, -LAYOUT.BarWidth / 2, 0, LAYOUT.TopInset)

	phaseLabel = text(timerPanel, "Phase", LAYOUT.LabelSize, COLOUR.Dim);
	(phaseLabel :: TextLabel).Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize);
	(phaseLabel :: TextLabel).Position = UDim2.fromOffset(0, LAYOUT.Pad / 2)

	timerLabel = text(timerPanel, "Clock", LAYOUT.TimerSize, COLOUR.Text);
	(timerLabel :: TextLabel).Size = UDim2.new(1, 0, 0, LAYOUT.TimerSize);
	(timerLabel :: TextLabel).Position = UDim2.fromOffset(0, LAYOUT.LabelSize + LAYOUT.Pad / 2)

	-- Bottom left: who you are to yourself, what you are carrying, whether the gate is open.
	local statusPanel = panel(gui, "Status")
	statusPanel.Size = UDim2.fromOffset(LAYOUT.StatusWidth, LAYOUT.StatusHeight)
	statusPanel.Position = UDim2.new(0, LAYOUT.Pad, 1, -(LAYOUT.StatusHeight + LAYOUT.Pad))

	statusLabel = text(statusPanel, "Lines", LAYOUT.LabelSize, COLOUR.Text);
	(statusLabel :: TextLabel).Size = UDim2.new(1, -LAYOUT.Pad, 1, -LAYOUT.Pad);
	(statusLabel :: TextLabel).Position = UDim2.fromOffset(LAYOUT.Pad / 2, LAYOUT.Pad / 2);
	(statusLabel :: TextLabel).TextXAlignment = Enum.TextXAlignment.Left;
	(statusLabel :: TextLabel).TextYAlignment = Enum.TextYAlignment.Top

	-- Bottom centre: one line, the thing you can do right now.
	promptLabel = text(gui, "Prompt", LAYOUT.PromptSize, COLOUR.Text);
	(promptLabel :: TextLabel).Size = UDim2.new(1, 0, 0, LAYOUT.PromptSize + LAYOUT.Pad);
	(promptLabel :: TextLabel).Position =
		UDim2.new(0, 0, 1, -(LAYOUT.PromptSize + LAYOUT.PromptLift))

	-- Bottom right: the Aswang's verbs. Hidden until RoleAssigned says so, and for everyone else,
	-- always.
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.fromOffset(LAYOUT.ButtonWidth, (LAYOUT.ButtonHeight + LAYOUT.Pad) * 2)
	actions.Position = UDim2.new(
		1,
		-(LAYOUT.ButtonWidth + LAYOUT.Pad),
		1,
		-((LAYOUT.ButtonHeight + LAYOUT.Pad) * 2 + LAYOUT.Pad)
	)
	actions.Parent = gui
	actionFrame = actions

	local transform = makeActionButton(actions, "Transform", "TRANSFORM  (T)", 0)
	local kill = makeActionButton(actions, "Kill", "KILL  (F)", 1)

	--[[
		THE BUTTONS INVOKE THE KEYBOARD'S HANDLERS. They do not build requests of their own — see
		`BindActions` above for the bug that rule exists to prevent.

		WHAT THE SERVER ACTUALLY GUARANTEES, stated precisely because the sentence that used to be here
		was wrong. `RequestTransform` genuinely takes no argument: the server reads every input from its
		own state. `RequestKill` DOES take a client-chosen target UserId — the server validates it for
		range, line of sight, phase and cooldown (`MonsterService.validateAndKill`), but it does not
		derive it. Claiming otherwise invites the next reader to conclude a target cannot be chosen,
		which is how the missing argument survived review in the first place.

		Either way a compromised client gains nothing: what it can choose is checked, and what it cannot
		choose is not its to send.

		They do not re-check `myRole`. The buttons are only ever VISIBLE to the Aswang, the handlers
		gate on it again, and the server refuses a survivor regardless — a fourth gate here would imply
		the visibility was load-bearing for security, which it is not.
	]]
	transform.Activated:Connect(function()
		local handlers = actionHandlers

		if handlers ~= nil then
			handlers.Transform()
		end
	end)

	kill.Activated:Connect(function()
		local handlers = actionHandlers

		if handlers ~= nil then
			handlers.Kill()
		end
	end)

	--[[
		Last, and only on a phone. On a desktop this returns immediately and the HUD is exactly what
		C18 and C26 built; on a phone the pad above takes over the Aswang's two verbs as well, so
		`render` hides the corner buttons rather than drawing both.
	]]
	buildTouchPad(gui)
end

--[[
	Shown once per round to the player it concerns, on their own RoleAssigned. Three seconds, then gone.

	The Aswang's copy names the role; everyone else's names theirs. Both exist, both last the same time,
	and neither is skippable — an intro one role could dismiss faster than another would be a tell
	visible to anyone watching a stream.
]]
local function showIntro(role: Types.Role)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoleIntro"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLOUR.Panel
	label.BackgroundTransparency = LAYOUT.Scrim
	label.TextColor3 = COLOUR.Text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = if role == Enums.Role.Aswang
		then "YOU ARE THE ASWANG.\nDo not get seen."
		else "You are a survivor.\nStay alive until sunrise."
	label.Parent = screenGui

	screenGui.Parent = playerGui

	task.delay(Config.Roles.IntroDuration, function()
		screenGui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- The end screen, and the one moment a client is allowed to learn someone
-- else's role.
--------------------------------------------------------------------------------

local function describeResult(result: Types.RoundResult): (string, Color3)
	if result == Enums.RoundResult.SurvivorsEscaped then
		return "THE SURVIVORS ESCAPED", COLOUR.Survivor
	elseif result == Enums.RoundResult.AswangWins then
		return "THE ASWANG WON", COLOUR.Aswang
	elseif result == Enums.RoundResult.Timeout then
		return "SUNRISE — NOBODY FINISHED", COLOUR.Urgent
	end

	return "ROUND ABORTED", COLOUR.Dim
end

--[[
	THE REVEAL, AND WHY IT IS SAFE HERE AND NOWHERE ELSE.

	`RoundEnded` is one of exactly two remotes `check-secrecy.mjs` permits to carry a role, and its
	listed reason is that the round is over — the reveal IS the point (§4.8). The other is
	`RoleAssigned`, fired to one player about themselves.

	`AswangUserId` is optional because an ABORTED round may have no Aswang to name (they disconnected,
	which is what aborted it). A nil there is a real case, not a defensive nil-check.
]]
local function nameOfAswang(userId: number?): string
	if userId == nil then
		return "nobody — the round was aborted"
	end

	local player = Players:GetPlayerByUserId(userId)

	-- They may have left before the reveal landed. Naming the UserId is still the honest answer, and
	-- it is already public: the round is over.
	return if player ~= nil then player.DisplayName else `a player who left (#{userId})`
end

--[[
	FADE A LABEL IN FROM BELOW.

	Both transparencies are tweened together, and that is not a flourish. `text()` gives every label a
	stroke at `LAYOUT.TextStroke`, so tweening `TextTransparency` alone fades the glyphs in from behind
	a fully-opaque OUTLINE of themselves — the words are legible as a dark silhouette before they are
	legible as words, which is worse than no animation at all.
]]
local function riseIn(label: TextLabel, restingY: number, delaySeconds: number)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Position = UDim2.new(0, 0, 0.5, restingY + MOTION.RevealRise)

	task.delay(delaySeconds, function()
		-- The end screen may already have been dismissed if `Config.Round.EndScreen` is ever tuned
		-- shorter than the beats below; a destroyed label is not an error worth a warning.
		if label.Parent == nil then
			return
		end

		tweenTo(label, MOTION.RevealFade, {
			TextTransparency = 0,
			TextStrokeTransparency = LAYOUT.TextStroke,
			Position = UDim2.new(0, 0, 0.5, restingY),
		})
	end)
end

--[[
	THE ROUND'S AWARD, HELD SEPARATELY FROM THE SNAPSHOT, because two remotes have no ordering
	guarantee between them.

	`ProfileUpdated` (carrying `LastAward`) and `RoundEnded` (which builds the end screen) are
	different RemoteEvents, and Roblox promises ordering WITHIN a remote and not ACROSS two. So both
	arrival orders happen and both must work: `pendingAward` covers award-then-screen, and `awardSink`
	covers screen-then-award. Assuming either order would produce an end screen that is missing its
	breakdown on some fraction of rounds, on some players' connections, and never in Studio.
]]
local pendingAward: Types.RoundAward? = nil
local awardSink: ((Types.RoundAward) -> ())? = nil

--[[
	THE REVEAL, IN THREE BEATS, BECAUSE §4.8 CALLS THIS "THE SCREENSHOT PEOPLE SHARE".

	What it did before was correct and inert: the result and the name appeared in the same frame, at
	full opacity, over a scrim the same weight as the HUD's. Everything a player needed to know arrived
	simultaneously, which is the most efficient way to deliver information and the worst way to deliver
	a REVEAL. Nobody screenshots a fact.

	  1. the map dims hard          — RevealScrim, well past the HUD's, so nothing else is lit
	  2. the RESULT rises in        — you won, or you did not. The half you already suspected
	  3. a held beat, then the NAME — the half you did not, and the reason the round was worth playing

	The hold is the whole mechanism. It is the moment six people say "wait, WHO?" out loud, and it is
	the difference between a stat line and a punchline.

	THE BEATS MUST FIT INSIDE `Config.Round.EndScreen`. At the committed 12s they occupy roughly two,
	and `riseIn` no-ops against a destroyed label if that ever stops being true — so tuning the end
	screen shorter degrades the reveal rather than erroring in everyone's console.
]]
local function showEndScreen(payload: Types.RoundEndedPayload)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("EndScreen")

	if existing ~= nil then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EndScreen"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = COLOUR.Panel
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	tweenTo(backdrop, MOTION.RevealFade, { BackgroundTransparency = LAYOUT.RevealScrim })

	local headline, colour = describeResult(payload.Result)

	local title = text(backdrop, "Result", LAYOUT.RevealSize, colour)
	title.Size = UDim2.new(1, 0, 0, LAYOUT.RevealSize * 2)
	title.Text = headline

	local reveal = text(backdrop, "Reveal", LAYOUT.PromptSize, COLOUR.Text)
	reveal.Size = UDim2.new(1, 0, 0, LAYOUT.PromptSize * 2)
	reveal.Text = `The aswang was <b>{nameOfAswang(payload.AswangUserId)}</b>`

	-- Parented before the beats are scheduled, so `riseIn`'s own parent check is testing what it
	-- means to test — dismissal — rather than losing a race with construction.
	screenGui.Parent = playerGui

	--[[
		THE FOURTH BEAT — WHAT THE ROUND WAS WORTH (C32, §4.8: "award XP and coins").

		It arrives AFTER the name, and last on purpose. §7's "unfinished business" is the mechanic
		here: the last thing on screen before the lobby returns should be how close the player is to
		the next thing, and a breakdown that landed alongside the reveal would be a stat block
		competing with the punchline. The reveal is the screenshot; this is the reason to stay.

		IT IS ROLE-CONDITIONAL IN CONTENT — the Aswang's breakdown has a kill line and a survivor's has
		an escape line — and this is the one screen in the game where that is fine, because the name of
		the Aswang is being displayed six lines above it. `ui-polish`'s "same panels, same positions,
		same animations" rule governs the HUD during a round; here the round is over and the secret is
		on screen.
	]]
	local awardLabel = text(backdrop, "Award", LAYOUT.LabelSize, COLOUR.Dim)
	awardLabel.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 8) -- config-ok: layout multiple

	local function renderAward(earned: Types.RoundAward)
		local lines = { `<b>+{earned.XP} XP</b>   ·   <b>+{earned.Coins} coins</b>` }

		for _, line in earned.Lines do
			--[[
				Coins are only named on lines that carry them, so "round played +50 xp +25" and
				"you survived the night +25 xp" read as the two different things they are rather than
				as one of them having a suspicious zero in it.
			]]
			table.insert(
				lines,
				if line.Coins > 0
					then `{line.Label}  +{line.XP} xp  +{line.Coins}`
					else `{line.Label}  +{line.XP} xp`
			)
		end

		awardLabel.Text = table.concat(lines, "\n")

		riseIn(awardLabel, LAYOUT.RevealSize * 2, 0)
	end

	--[[
		BOTH ARRIVAL ORDERS. `ProfileUpdated` and `RoundEnded` are different RemoteEvents and Roblox
		orders packets within a remote, not across two — so the award can land before this screen
		exists or after it. `pendingAward` covers the first, the sink covers the second, and the sink
		is cleared on dismissal so a late award cannot write into a destroyed label.
	]]
	local earlyAward = pendingAward
	local sink: (Types.RoundAward) -> () = function(late: Types.RoundAward)
		if awardLabel.Parent ~= nil then
			renderAward(late)
		end
	end

	pendingAward = nil
	awardSink = sink

	if earlyAward ~= nil then
		task.delay(MOTION.RevealFade + MOTION.RevealHold * 2, sink, earlyAward)
	end

	riseIn(title, -LAYOUT.RevealSize * 2, 0)
	riseIn(reveal, LAYOUT.Pad, MOTION.RevealFade + MOTION.RevealHold)

	-- Dismissed on the same clock the server uses to start the next round, so the screen is never
	-- still up when the lobby is already running.
	task.delay(Config.Round.EndScreen, function()
		--[[
			CLEARED ONLY IF IT IS STILL OURS. `showEndScreen` destroys a screen it finds already up, so
			two of these timers can be in flight — and an unconditional `awardSink = nil` from the
			OLDER one would silently disable the newer screen's breakdown. Comparing identity is the
			whole fix; the sink closes over its own label and is already inert once that is destroyed.
		]]
		if awardSink == sink then
			awardSink = nil
		end

		screenGui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Progression — the level bar, the daily claim and the wardrobe (C32, C33, C34)
--------------------------------------------------------------------------------

--[[
	THE LOBBY IS THE ONLY PLACE ANY OF THIS DRAWS, and that is a horror-rules decision rather than a
	layout one. `ui-polish`'s list is explicit: "information minimalism — show a thing at the moment it
	is needed and fade it when it is not", and "never obscure the play space". A level bar during a
	chase is a panel competing with the thing that is chasing you.

	It is also what makes the whole panel safe to be as busy as it is. Nothing here is on screen while
	a round is running, so none of it can be a tell, and none of it costs a frame during the case §5
	measures — 30fps on a mid-range Android, in a chase.

	SECRECY: THIS PANEL NEVER READS A ROLE, and it structurally cannot. Its only input is
	`Types.ProfileSnapshot`, which has no role field and no `Stats` at all — see that type's header for
	why the payload is built rather than trimmed. `myRole` is not consulted anywhere below.
]]

-- The last `ProfileUpdated`. One snapshot drives every element here, so nothing on this panel can
-- disagree with anything else on it.
--
-- The round's award is NOT held here — see `pendingAward` and `awardSink` above `showEndScreen`,
-- which is the only thing that renders it and had to be declared before them.
local profile: Types.ProfileSnapshot? = nil

local progressPanel: Frame? = nil
local levelLabel: TextLabel? = nil
local coinLabel: TextLabel? = nil
local xpLabel: TextLabel? = nil
local levelFill: Frame? = nil
local dailyButton: TextButton? = nil
-- C39. The lobby's group panel, §9.2's one-time reward. Nil outside the lobby, like every other handle
-- in this block — `resetProgressPanel` clears it when the panel is torn down.
local groupButton: TextButton? = nil

--[[
	One cycler per slot, and a CURSOR per slot that is purely local.

	The cursor is where the player is LOOKING, not what they are wearing. Advancing it is free and
	tells the server nothing; acting on it fires a remote and the server decides. That is §6.2's
	"the client requests, the server decides" applied to a wardrobe, and it is why a tap that lands on
	a locked item costs no network traffic at all.
]]
local SLOTS = { "Skin", "Lantern", "DeathFX" }
local slotButtons: { [string]: TextButton } = {}
local slotCursor: { [string]: number } = {}

local CATALOGUE: { Cosmetics.Item } = Config.Cosmetics.Catalogue

-- Forward-declared because `tapSlot` redraws after moving the cursor and is defined above it. A local
-- rather than a method on `UIController`: nothing outside this file has any business redrawing a
-- panel it cannot see, and the public surface here is four functions that other controllers call.
local renderProgress: () -> ()

local function itemsForSlot(slot: string): { Cosmetics.Item }
	local items: { Cosmetics.Item } = {}

	for _, item in CATALOGUE do
		if item.Slot == slot then
			table.insert(items, item)
		end
	end

	return items
end

local function equippedIdFor(snapshot: Types.ProfileSnapshot, slot: string): string
	if slot == "Skin" then
		return snapshot.Equipped.Skin
	elseif slot == "Lantern" then
		return snapshot.Equipped.Lantern
	end

	return snapshot.Equipped.DeathFX
end

--[[
	WHAT THE CYCLER SAYS, AND IT IS THE SAME DECISION THE SERVER WILL MAKE.

	`pure/Cosmetics.evaluatePurchase` runs here, client-side, over the snapshot this client already
	has — exactly as the trial door runs `TrialAdmission` for display. A label that says BUY when the
	server would refuse gets a refusal and a corrected snapshot; a label that says LOCKED when the
	server would allow merely hides an item. Neither is a security question, which is what lets the
	display side be approximate.

	The PHASE is passed as IDLE rather than as the live phase, deliberately: this panel only exists in
	the lobby, and reading a phase the panel cannot be shown during would make the label depend on a
	value that is constant wherever it is read.
]]
local function labelFor(snapshot: Types.ProfileSnapshot, item: Cosmetics.Item): string
	if equippedIdFor(snapshot, item.Slot) == item.Id then
		return `{item.Slot:upper()}  {item.Name}  ·  worn`
	end

	if Cosmetics.isOwned(item, snapshot.Owned) then
		return `{item.Slot:upper()}  {item.Name}  ·  tap to wear`
	end

	local verdict = Cosmetics.evaluatePurchase({
		Catalogue = CATALOGUE,
		Id = item.Id,
		Owned = snapshot.Owned,
		Level = snapshot.Level,
		Coins = snapshot.Coins,
		Phase = Enums.RoundPhase.Idle,
	})

	if verdict.Verdict == "OK" then
		return `{item.Slot:upper()}  {item.Name}  ·  buy for {verdict.Cost}`
	elseif verdict.Verdict == "NOT_ENOUGH_COINS" then
		return `{item.Slot:upper()}  {item.Name}  ·  {item.Price} coins`
	elseif verdict.Verdict == "LOCKED_BY_LEVEL" then
		return `{item.Slot:upper()}  {item.Name}  ·  level {item.Level}`
	end

	-- NOT_FOR_SALE. The gamepass item, until C37 supplies a product id — see `Config.Cosmetics`.
	return `{item.Slot:upper()}  {item.Name}  ·  soon`
end

--[[
	WHAT A TAP DOES, and why a purchase takes two of them.

	  · looking at something you are already wearing  -> advance the cursor
	  · looking at something you own                  -> wear it
	  · looking at something you can afford           -> BUY IT, and stop there

	The purchase does not also equip, and the cursor does not move past an affordable item on the
	first tap. Both are the same guard against the same accident: a wardrobe whose cycler spends coins
	as you scroll through it is one nobody scrolls through twice.

	Anything else — locked by level, not enough coins, a gamepass item before C37 — advances, because
	there is nothing to do with it and stopping would trap the cursor.
]]
local function tapSlot(slot: string)
	local snapshot = profile

	if snapshot == nil then
		return
	end

	local items = itemsForSlot(slot)

	if #items == 0 then
		return
	end

	local index = slotCursor[slot] or 1
	local item = items[index]

	if item ~= nil and equippedIdFor(snapshot, slot) ~= item.Id then
		if Cosmetics.isOwned(item, snapshot.Owned) then
			Remotes.Get("RequestEquipCosmetic"):FireServer(item.Id)

			return
		end

		local verdict = Cosmetics.evaluatePurchase({
			Catalogue = CATALOGUE,
			Id = item.Id,
			Owned = snapshot.Owned,
			Level = snapshot.Level,
			Coins = snapshot.Coins,
			Phase = Enums.RoundPhase.Idle,
		})

		if verdict.Verdict == "OK" then
			Remotes.Get("RequestBuyCosmetic"):FireServer(item.Id)

			return
		end
	end

	slotCursor[slot] = (index % #items) + 1

	renderProgress()
end

--[[
	REDRAWN FROM THE SNAPSHOT, and safe to call when there is no panel and when there is no snapshot.

	Both cases are ordinary rather than defensive: `ProfileUpdated` can arrive during a round (a round
	award lands at ENDING, when the lobby is torn down), and the lobby can be built before the first
	snapshot has arrived on a slow join.
]]
function renderProgress()
	local snapshot = profile
	local panelFrame = progressPanel

	if panelFrame == nil or panelFrame.Parent == nil then
		return
	end

	if snapshot == nil then
		panelFrame.Visible = false

		return
	end

	panelFrame.Visible = true

	local level = levelLabel
	local coins = coinLabel
	local xp = xpLabel
	local fill = levelFill

	if level ~= nil then
		level.Text = `LEVEL {snapshot.Level}`
	end

	if coins ~= nil then
		coins.Text = `{snapshot.Coins}`
	end

	if xp ~= nil then
		--[[
			AT THE CAP THERE IS NO "OF", because there is nothing to be out of. `XPForNextLevel` is
			exactly 0 there and a client that divided by it would render a NaN — which is why
			`Progress` is sent pre-divided and is what the bar actually reads.
		]]
		xp.Text = if snapshot.XPForNextLevel <= 0
			then `{snapshot.XP} xp · max level`
			else `{snapshot.XPIntoLevel} / {snapshot.XPIntoLevel + snapshot.XPForNextLevel} xp`
	end

	if fill ~= nil then
		-- Tweened rather than assigned, so a level-up in the lobby is something a player SEES happen.
		-- One of the few animations here that fires on arrival rather than on a per-tick change.
		tweenTo(fill, MOTION.Fade, { Size = UDim2.fromScale(snapshot.Progress, 1) })
	end

	local daily = dailyButton

	if daily ~= nil then
		local preview = snapshot.Daily

		daily.Text = if preview.Claimable
			then `DAY {preview.CycleDay}  ·  claim +{preview.RewardXP} xp +{preview.RewardCoins}`
			else `DAY {preview.CycleDay} tomorrow  ·  +{preview.RewardXP} xp +{preview.RewardCoins}`
		daily.TextColor3 = if preview.Claimable then COLOUR.Coin else COLOUR.Dim
	end

	local group = groupButton

	if group ~= nil then
		--[[
			THE UNCLAIMED LABEL NAMES THE CONDITION rather than just the reward, because the server can
			refuse silently and this row is the only place that refusal is explicable. A player who is
			not in the group presses, nothing happens, and "join the group" is the difference between
			that reading as a broken button and reading as an instruction.

			`Coin` for the offer and `Dim` once taken, matching the daily row directly above it — one
			colour meaning per the checklist, and the same one both rows already use for "there is
			something here for you".
		]]
		group.Text = if snapshot.GroupRewardClaimed
			then "GROUP REWARD claimed"
			else `JOIN THE GROUP  ·  claim +{Config.Community.GroupJoinRewardCoins}`
		group.TextColor3 = if snapshot.GroupRewardClaimed then COLOUR.Dim else COLOUR.Coin
	end

	for _, slot in SLOTS do
		-- Annotated optional: the map's value type is not, so an unannotated local reads as a
		-- TextButton the analyzer refuses to compare against nil.
		local button: TextButton? = slotButtons[slot]

		if button == nil then
			continue
		end

		local items = itemsForSlot(slot)

		if #items == 0 then
			continue
		end

		--[[
			THE CURSOR STARTS ON WHAT IS WORN. Without this the panel opens showing the first
			catalogue entry for every slot, and a player's first tap is "wear the thing I am already
			wearing" — which reads as a button that does nothing.

			Re-clamped on every render rather than only on creation, because the catalogue can shrink
			between builds and a stale cursor would index past the end.
		]]
		if slotCursor[slot] == nil or slotCursor[slot] > #items then
			local worn = equippedIdFor(snapshot, slot)
			local found = 1

			for index, item in items do
				if item.Id == worn then
					found = index
				end
			end

			slotCursor[slot] = found
		end

		local item = items[slotCursor[slot]]

		if item ~= nil then
			button.Text = labelFor(snapshot, item)
			button.TextColor3 = if equippedIdFor(snapshot, slot) == item.Id
				then COLOUR.Text
				else COLOUR.Dim
		end
	end
end

local function teardownProgress()
	if progressPanel ~= nil then
		progressPanel:Destroy()
		progressPanel = nil
	end

	levelLabel = nil
	coinLabel = nil
	xpLabel = nil
	levelFill = nil
	dailyButton = nil
	groupButton = nil
	table.clear(slotButtons)
end

--[[
	A `UIListLayout` RATHER THAN HAND-COMPUTED OFFSETS, which is `ui-polish`'s rule for a stack: manual
	`(Height + Pad) * order` arithmetic is how alignment rots, and this stack has seven rows in it.

	The panel sits on the LEFT EDGE, vertically centred. Both bottom corners belong to Roblox's
	thumbstick and jump button and the top belongs to the CoreGui cluster; the left-middle is the one
	region of a landscape phone that is nobody else's, and nothing here is needed during play so it
	never has to share.
]]
local function buildProgress()
	if progressPanel ~= nil and progressPanel.Parent ~= nil then
		return
	end

	local gui = hud

	if gui == nil then
		return
	end

	local frame = panel(gui, "Progress")
	--[[
		SIXTEEN UNITS BECAME EIGHTEEN WHEN C39 ADDED THE GROUP ROW, and the reason is worth a line
		because nothing catches it: this height is FIXED while the stack inside it is a `UIListLayout`
		that grows, and the frame has no `ClipsDescendants`. So a row added without touching this
		number does not clip — it renders BELOW the panel's own rounded background and stroke, in open
		space, looking like a stray label rather than part of the panel.

		The stack now measures 302px: 20 header + 18 bar + 18 xp + 36 daily + 108 for three cosmetic
		slots + 36 group = 236, plus seven `Pad // 2` gaps (42), plus top and bottom `Pad` (24).
		Eighteen units is 324, so there is real headroom; sixteen was 288 and overflowed by 14.

		The half in `Position` tracks it — `LabelSize * 9` is half of `* 18` — because the panel is
		centred by offsetting half its own height, and the two numbers falling out of step is how a
		centred panel drifts.
	]]
	frame.Size = UDim2.fromOffset(LAYOUT.BarWidth, LAYOUT.LabelSize * 18) -- config-ok: layout multiple
	frame.Position = UDim2.new(0, LAYOUT.Pad, 0.5, -LAYOUT.LabelSize * 9) -- config-ok: layout multiple
	frame.Visible = false

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, LAYOUT.Pad)
	padding.PaddingBottom = UDim.new(0, LAYOUT.Pad)
	padding.PaddingLeft = UDim.new(0, LAYOUT.Pad)
	padding.PaddingRight = UDim.new(0, LAYOUT.Pad)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, LAYOUT.Pad // 2) -- config-ok: layout multiple
	layout.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, LAYOUT.PromptSize)
	header.LayoutOrder = 1
	header.Parent = frame

	local level = text(header, "Level", LAYOUT.PromptSize, COLOUR.Level)
	level.Size = UDim2.fromScale(0.6, 1) -- config-ok: layout split
	level.TextXAlignment = Enum.TextXAlignment.Left
	level.Text = "LEVEL 1"

	local coins = text(header, "Coins", LAYOUT.PromptSize, COLOUR.Coin)
	coins.Size = UDim2.fromScale(0.4, 1) -- config-ok: layout split
	coins.Position = UDim2.fromScale(0.6, 0) -- config-ok: layout split
	coins.TextXAlignment = Enum.TextXAlignment.Right
	coins.Text = "0"

	-- The bar: a scrim back and a fill whose Size.X.Scale is the
	-- only thing that ever moves. One instance changed per update, which is what keeps this cheap.
	local back = Instance.new("Frame")
	back.Name = "LevelBarBack"
	back.Size = UDim2.new(1, 0, 0, LAYOUT.BarHeight)
	back.BackgroundColor3 = COLOUR.Panel
	back.BackgroundTransparency = LAYOUT.BarBackScrim
	back.BorderSizePixel = 0
	back.LayoutOrder = 2
	back.Parent = frame

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, LAYOUT.Corner)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "LevelBarFill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOUR.Level
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, LAYOUT.Corner)
	fillCorner.Parent = fill

	local xp = text(frame, "XP", LAYOUT.LabelSize, COLOUR.Dim)
	xp.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize)
	xp.TextXAlignment = Enum.TextXAlignment.Left
	xp.LayoutOrder = 3 -- config-ok: stack order, not balance

	--[[
		A BUTTON RATHER THAN AN AUTOMATIC PAYOUT, and the difference is the whole feature. §7 calls the
		daily streak the highest-ROI retention mechanic there is, and what a player comes back FOR is
		the press — a reward that arrives silently on join is a number that changed while they were
		looking at a loading screen.
	]]
	local daily = Instance.new("TextButton")
	daily.Name = "DailyClaim"
	daily.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 2) -- config-ok: layout multiple
	daily.BackgroundTransparency = 1
	daily.TextColor3 = COLOUR.Dim
	daily.TextSize = LAYOUT.LabelSize
	daily.Font = Enum.Font.GothamBold
	daily.TextXAlignment = Enum.TextXAlignment.Left
	daily.TextTruncate = Enum.TextTruncate.AtEnd
	daily.Text = ""
	daily.LayoutOrder = 4 -- config-ok: stack order, not balance
	daily.Parent = frame

	daily.Activated:Connect(function()
		--[[
			FIRED WITHOUT CHECKING `Claimable` FIRST, deliberately. The label is drawn from a snapshot
			that can be a whole UTC day old on a client that never closed the game, and the server
			re-runs `pure/DailyStreak` on every call and answers. A refusal costs one rate-limit token
			and pushes a corrected snapshot back, which is exactly what a client with a stale view
			needs — whereas a client-side gate would leave it stale and silent.
		]]
		Remotes.Get("RequestClaimDaily"):FireServer()
	end)

	dailyButton = daily

	for order, slot in SLOTS do
		local button = Instance.new("TextButton")
		button.Name = `Slot{slot}`
		button.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 2) -- config-ok: layout multiple
		button.BackgroundTransparency = 1
		button.TextColor3 = COLOUR.Dim
		button.TextSize = LAYOUT.LabelSize
		button.Font = Enum.Font.GothamBold
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Text = ""
		button.LayoutOrder = 4 + order -- config-ok: layout order, after the daily row
		button.Parent = frame

		button.Activated:Connect(function()
			tapSlot(slot)
		end)

		slotButtons[slot] = button
	end

	--[[
		§9.2's GROUP PANEL (C39), AND IT IS ONE ROW RATHER THAN A PANEL.

		The competitor shipped 16 months of updates to 1.43M players with no group to announce them to
		— Appendix C — so this row is worth 250 coins to the project. It is not worth a modal: the
		lobby is where a waiting player reads the tips C24 put there, and a dialog over that is a
		thing to dismiss rather than a thing to read.

		BUILT IN THE SAME SHAPE AS THE DAILY ROW ABOVE, deliberately. `ui-polish`'s checklist wants one
		type ramp and one spacing unit across sibling rows, and copying the row that is already there
		is how sibling rows stay siblings — a second size or a second alignment here is the 2px
		misalignment the checklist calls the loudest amateur signal.
	]]
	local group = Instance.new("TextButton")
	group.Name = "GroupReward"
	group.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 2) -- config-ok: layout multiple
	group.BackgroundTransparency = 1
	group.TextColor3 = COLOUR.Dim
	group.TextSize = LAYOUT.LabelSize
	group.Font = Enum.Font.GothamBold
	group.TextXAlignment = Enum.TextXAlignment.Left
	group.TextTruncate = Enum.TextTruncate.AtEnd
	group.Text = ""
	group.LayoutOrder = 8 -- config-ok: stack order, after the three cosmetic slots
	group.Parent = frame

	group.Activated:Connect(function()
		--[[
			FIRED WITHOUT CHECKING THE SNAPSHOT FIRST, for the reason the daily row gives: the label is
			drawn from a snapshot that may predate the player joining the group in another tab, and the
			server re-asks `IsInGroupAsync` on every call. A client-side gate would leave someone who
			has just joined the group looking at a button that refuses to fire.
		]]
		Remotes.Get("RequestClaimGroupReward"):FireServer()
	end)

	groupButton = group

	progressPanel = frame
	levelLabel = level
	coinLabel = coins
	xpLabel = xp
	levelFill = fill

	renderProgress()
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function promptFor(snapshot: Types.ClientRoundSnapshot): string
	if snapshot.YourState == Enums.PlayerState.Dead then
		return "you are dead — watching · your chat reaches the dead only"
	elseif snapshot.YourState == Enums.PlayerState.Spectator then
		return "watching — you join the next round"
	elseif snapshot.Phase ~= Enums.RoundPhase.Active then
		return "waiting for the round to start"
	end

	--[[
		C27: THE PROMPT NAMES THE CONTROLS THIS PLAYER ACTUALLY HAS.

		The keyboard line was the only instruction in the game for three of the five verbs, and on a
		phone it named three keys that do not exist — which is worse than saying nothing, because a
		player who cannot find a key concludes the game is broken rather than that the hint is.

		Keyed off the pad's existence rather than off `UserInputService` again, so the sentence and
		the buttons can never disagree about what device this is.
	]]
	if touchPad ~= nil then
		return "survive until sunrise · SALT to throw · walk over a pouch to take it"
	end

	return "survive until sunrise · Q throw salt · walk over a pouch to take it"
end

--[[
	THE THREE THINGS (C24's done condition: "the lobby has three things to look at and a countdown
	that is always visible").

	  1. the status line   — above: a countdown when there is one, a headcount when there is not
	  2. these tips        — rotating on Config.Community.LobbyTipSeconds
	  3. the Trial door    — the button below, which is the one that is actually a GAME

	§9.3's "cosmetic preview stand" is deliberately NOT here, and that is a scope call rather than an
	oversight: a preview stand is map geometry plus a cosmetic-equip path through MonetizationService,
	and neither is in C24's row. Three things exist without it.
]]
local TIPS = {
	"Salt burns the aswang. Throw it to reveal and stun.", -- config-ok: lobby copy, not balance
	"Stay together. Alone is when it takes you.", -- config-ok: lobby copy
	"The aswang has to transform to kill. That is your warning.", -- config-ok: lobby copy
	"Watch who is never around when someone dies.", -- config-ok: lobby copy
}

local lobbyPanel: Frame? = nil
local tipLabel: TextLabel? = nil
local trialButton: TextButton? = nil
local tipIndex = 1
local tipLoop: thread? = nil

local function teardownLobby()
	-- The progression panel shares the lobby's lifetime exactly. It is torn down HERE rather than in
	-- `render`'s else-branch so there is one place that knows the lobby is going away, and a future
	-- third lobby element cannot be added to the build path and forgotten in the teardown.
	teardownProgress()

	if tipLoop ~= nil then
		task.cancel(tipLoop)
		tipLoop = nil
	end

	if lobbyPanel ~= nil then
		lobbyPanel:Destroy()
		lobbyPanel = nil
		tipLabel = nil
		trialButton = nil
	end
end

local function buildLobby()
	if lobbyPanel ~= nil and lobbyPanel.Parent ~= nil then
		return
	end

	local gui = hud

	if gui == nil then
		return
	end

	local frame = panel(gui, "Lobby")
	-- Four label-heights tall (two of tip, two of button), sitting six up from the bottom edge so it
	-- clears the prompt row. config-ok: panel proportions in label-heights, not balance.
	frame.Size = UDim2.fromOffset(LAYOUT.BarWidth, LAYOUT.LabelSize * 4) -- config-ok: layout multiple
	frame.Position = UDim2.new(0.5, -LAYOUT.BarWidth / 2, 1, -LAYOUT.LabelSize * 6) -- config-ok: layout multiple

	local tip = text(frame, "Tip", LAYOUT.LabelSize, COLOUR.Dim) :: TextLabel
	tip.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 2)
	tip.Text = TIPS[tipIndex]

	--[[
		THE TRIAL DOOR. Its availability is `TrialAdmission.evaluate` run CLIENT-SIDE FOR DISPLAY
		ONLY, over the phase and the headcount this client already has. Pressing it fires
		`RequestStartTrial`, and the server re-runs the same module and decides.

		A client that shows the button when it should not gets a refusal; a client that hides it when
		it should not merely misses a trial. Neither is a security question, which is exactly why the
		display side can afford to be approximate — §6.2's "the client requests, the server decides",
		with the request being the only part that matters.
	]]
	local button = Instance.new("TextButton")
	button.Name = "TrialDoor"
	button.Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize * 2)
	button.Position = UDim2.fromOffset(0, LAYOUT.LabelSize * 2)
	button.BackgroundTransparency = 1
	button.TextColor3 = COLOUR.Text
	button.TextSize = LAYOUT.LabelSize
	button.Font = Enum.Font.GothamBold
	button.Text = "try the solo run"
	button.Visible = false
	button.Parent = frame

	button.Activated:Connect(function()
		Remotes.Get("RequestStartTrial"):FireServer()
	end)

	lobbyPanel = frame
	tipLabel = tip
	trialButton = button

	buildProgress()

	-- Rotating so a waiting screen is never the same screen twice. §9 item 3: a static screen reads
	-- as broken, and that is true of a static SENTENCE as much as of a stopped clock.
	tipLoop = task.spawn(function()
		while true do
			task.wait(Config.Community.LobbyTipSeconds)

			tipIndex = (tipIndex % #TIPS) + 1

			local label = tipLabel

			if label == nil then
				return
			end

			label.Text = TIPS[tipIndex]
		end
	end)
end

local function render(snapshot: Types.ClientRoundSnapshot)
	buildHud()

	local clock = timerLabel
	local phase = phaseLabel
	local status = statusLabel
	local prompt = promptLabel

	if clock == nil or phase == nil or status == nil or prompt == nil then
		return
	end

	local minutes = math.floor(snapshot.SecondsRemaining / 60) -- config-ok: seconds in a minute
	local seconds = math.floor(snapshot.SecondsRemaining % 60) -- config-ok: seconds in a minute

	--[[
		C24, §9 item 3. WHAT THE BIG NUMBER SAYS WHEN THERE IS NOTHING TO COUNT.

		During IDLE there is no deadline — `RoundService` leaves `PhaseEndsAt` at 0 because IDLE has no
		duration, so `GetSecondsRemaining` honestly returns 0. Rendering that as "0:00" puts a STOPPED
		CLOCK in the largest type on screen, and a stopped clock does not read as "waiting", it reads
		as "this game is broken" — precisely the §9 item 3 failure and, per Appendix C, the moment a
		player who arrived in a TikTok wave leaves and never comes back.

		So IDLE gets a SENTENCE about the thing that will actually change: how many more people are
		needed. Derived from `Config.Round.MinPlayers` and this client's own headcount — no new remote
		and nothing about anybody's state.

		ONE HONEST LIMITATION: `#Players:GetPlayers()` is a second source for a number the server also
		knows, and if they disagree the client's is wrong. It is used because widening
		`ClientRoundSnapshot` for a lobby label would move the round contract for a cosmetic reason,
		and a headcount is already visible in Roblox's own player list — so it leaks nothing.
	]]
	if snapshot.Phase == Enums.RoundPhase.Idle then
		local here = #Players:GetPlayers()
		local needed = math.max(0, Config.Round.MinPlayers - here)

		clock.Text = if needed == 1 then "1 more" else `{needed} more`
		clock.TextColor3 = COLOUR.Dim
		phase.Text = "WAITING FOR PLAYERS"

		--[[
			IDLE OWNS THE CLOCK COLOUR DIRECTLY, so the urgency edge has to be forgotten here or the
			next round starts dim.

			Without this line `lastUrgent` is still `false` from the previous round, the first ACTIVE
			snapshot computes `urgent == false`, finds no edge, and leaves the countdown rendering in
			`Dim` — the lobby's colour — for the entire night. Setting it back to `nil` makes the next
			active render take the un-animated first-render path and assign `Text` outright.
		]]
		lastUrgent = nil

		buildLobby()

		local door = trialButton

		if door ~= nil then
			door.Visible = TrialAdmission.evaluate({
				Enabled = Config.Trial.Enabled,
				RoundPhase = snapshot.Phase,
				PlayerCount = here,
				OfferBelowPlayerCount = Config.Trial.OfferBelowPlayerCount,
				AlreadyInTrial = false,
			}) == "OK"
		end
	else
		teardownLobby()
		clock.Text = string.format("%d:%02d", minutes, seconds)

		--[[
			THE URGENCY COLOUR IS AN EDGE, NOT A LEVEL.

			It used to be assigned every render, which is correct and invisible: the timer turned red
			between one frame and the next, at the exact moment a player was least likely to be looking
			at it. Crossing `UrgentSeconds` is the HUD's single most important state change and it
			deserves to be seen happening, so it is now tweened once, on the crossing.

			Tracked as a boolean rather than by comparing colours, because the timer is also DIM during
			IDLE — comparing `clock.TextColor3` would read that as an urgency change on the first
			active snapshot and flash the whole HUD red as the round starts.
		]]
		local urgent = snapshot.Phase == Enums.RoundPhase.Active
			and snapshot.SecondsRemaining <= LAYOUT.UrgentSeconds

		if urgent ~= lastUrgent then
			local target = if urgent then COLOUR.Urgent else COLOUR.Text

			if lastUrgent == nil then
				clock.TextColor3 = target
			else
				tweenTo(clock, MOTION.Colour, { TextColor3 = target })
			end

			lastUrgent = urgent
		end

		phase.Text = if snapshot.Phase == Enums.RoundPhase.Active
			then "UNTIL SUNRISE"
			else snapshot.Phase
	end

	--[[
		THE ROLE LINE IS THE ONE THING ON SCREEN THAT DIFFERS BETWEEN CLIENTS, and it is drawn from
		`myRole` — this client's own, from RoleAssigned. It is deliberately NOT read from the snapshot's
		`YourRole`, so there is exactly one place in this file that knows a role.
	]]
	local roleColour = if myRole == Enums.Role.Aswang then COLOUR.Aswang else COLOUR.Survivor
	local roleWord = if myRole == Enums.Role.Aswang then "ASWANG" else "SURVIVOR"

	local stateColour = if snapshot.YourState == Enums.PlayerState.Dead
		then COLOUR.Dead
		else COLOUR.Text

	status.Text = string.format(
		'<font color="#%s">%s</font>\n' .. '<font color="#%s">%s</font>   salt ~%d',
		roleColour:ToHex(),
		roleWord,
		stateColour:ToHex(),
		snapshot.YourState,
		saltSeen
	)

	prompt.Text = promptFor(snapshot)

	--[[
		The buttons follow the phase as well as the role: a transform button during INTERMISSION is an
		affordance for something the server will refuse, and a refusal the player cannot explain reads
		as a bug. `myRole` alone decides whether they EXIST; the phase decides whether they are offered.
	]]
	local aswangVerbs = myRole == Enums.Role.Aswang
		and snapshot.Phase == Enums.RoundPhase.Active
		and snapshot.YourState == Enums.PlayerState.Alive

	local actions = actionFrame

	if actions ~= nil then
		-- On a phone the pad below owns these two, so the desktop corner never appears — otherwise
		-- the Aswang gets two of every button and one of them is where a thumb cannot reach.
		actions.Visible = aswangVerbs and touchPad == nil

		for _, child in actions:GetChildren() do
			if child:IsA("TextButton") then
				child.Visible = actions.Visible
			end
		end
	end

	--[[
		THE TOUCH PAD FOLLOWS THE SAME RULES, BUTTON BY BUTTON (C27).

		Each verb is offered exactly when the server would accept it, because an affordance for
		something that will be refused reads as a broken game and a phone player has no console to
		check. That is the same argument the desktop buttons make; what is new is that the pad has
		verbs a survivor uses, so the gating is per-button rather than per-frame:

		  SAY   — alive, any phase. §4.5 is how a phone player talks, and the lobby is where the
		          accusations from the last round get made.
		  SALT  — a live round only: a throw outside ACTIVE is a request the server discards.
		  the Aswang's two — exactly as the desktop pair, including the role gate.

		A hidden button collapses out of its column, so a survivor sees three and an Aswang five with
		no gap where the other's verbs would be — and nothing on this screen is a difference another
		player could observe, because the whole pad lives in this client's own PlayerGui.
	]]
	local pad = touchPad

	if pad ~= nil then
		local alive = snapshot.YourState == Enums.PlayerState.Alive
		local inRound = alive and snapshot.Phase == Enums.RoundPhase.Active

		--[[
			THE PAD IS ALWAYS THERE AND SAY IS ALWAYS ON IT, INCLUDING FOR THE DEAD.

			`QuickChatService` accepts a ghost's phrases — the ones flagged `GhostMay` — and delivers
			them to the other ghosts, which is §4.7's "ghosts still matter" and the only voice a dead
			phone player has. Hiding SAY with the rest of the pad would have taken it away, and the
			bug would have been invisible from a desk: on a keyboard `B` still works.

			The lobby keeps it too. The accusations from the last round are made there.
		]]
		pad.Visible = true

		touchButtons.Say.Visible = true
		touchButtons.Salt.Visible = inRound
		touchButtons.Transform.Visible = aswangVerbs
		touchButtons.Kill.Visible = aswangVerbs
	end
end

function UIController.Init() end

function UIController.Start()
	Remotes.Get("RoleAssigned").OnClientEvent:Connect(function(payload: Types.RoleAssignedPayload)
		myRole = payload.Role

		showIntro(payload.Role)
	end)

	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(render)

	Remotes.Get("RoundEnded").OnClientEvent:Connect(showEndScreen)

	--[[
		THE PROFILE (C32/C33/C34). One remote, one cached snapshot, every progression element drawn
		from it — so nothing on the panel can disagree with anything else on it.

		`LastAward` is present ONLY on the push that follows a round, and it is lifted out here rather
		than left on the snapshot because the two have different lifetimes: the snapshot is the current
		truth and is replaced by every later push, while the award belongs to one end screen and must
		survive until that screen exists to render it. Leaving it in place would mean a daily claim
		during the end screen (a push with `LastAward = nil`) silently blanking the breakdown.
	]]
	Remotes.Get("ProfileUpdated").OnClientEvent:Connect(function(snapshot: Types.ProfileSnapshot)
		profile = snapshot

		local earned = snapshot.LastAward

		if earned ~= nil then
			local sink = awardSink

			if sink ~= nil then
				sink(earned)
			else
				pendingAward = earned
			end
		end

		renderProgress()
	end)

	--[[
		A round ending clears the local salt estimate, because the server clears the real one.

		It also clears `myRole`. That matters for more than tidiness: without it a player who is the
		Aswang once keeps their buttons and their red role line into the next round's lobby, and the
		next round may deal them a survivor. RoleAssigned arrives again at STARTING, so the only window
		this creates is one where the HUD says SURVIVOR before the draw — which is what every other
		client shows too.
	]]
	Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: Types.RoundPhase)
		if phase ~= Enums.RoundPhase.Active then
			saltSeen = 0

			--[[
				The animation edges reset with the round, for the same reason `myRole` does.

				Left alone, the first snapshot of a new round finds 0/5 against last round's 5/5 and
				plays the completed bar draining and the count popping — a recap of the previous round
				animating over the new one's lobby. Back at their seed values, the new round's first
				render assigns silently and only animates what actually happens next.
			]]
		end

		if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
			myRole = nil
		end
	end)

	--[[
		THE SALT ESTIMATE, and why it is an estimate rather than a fact.

		`SaltEffect` fires to every client on every throw, carrying a trajectory and no player — so this
		client cannot tell whose throw it was. What it CAN tell is that it pressed Q itself, which
		`InputController` records through `NoteThrow`. A pickup is inferred the same way: the pouch this
		client was standing on disappeared.
	]]
	local pouches = workspace:WaitForChild("SaltPouches", 30) -- config-ok: startup wait, not balance

	if pouches ~= nil then
		pouches.ChildRemoved:Connect(function(pouch: Instance)
			--[[
				DISTANCE-GATED, or every client counts every pickup. `ChildRemoved` fires on ALL clients
				when ANY pouch is taken, so an ungated increment would show a survivor across the map
				collecting salt they never touched.

				The pouch is already destroyed by the time this fires, so its position cannot be read
				from it — but a `Part` retains its last CFrame after Destroy, which is enough to compare.
			]]
			if not pouch:IsA("BasePart") then
				return
			end

			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

			if root == nil or not root:IsA("BasePart") then
				return
			end

			--[[
				THE SERVER'S OWN RADIUS, NOT A GENEROUS ONE, AND CLAMPED TO THE CARRY LIMIT.

				This read `PickupRangeStuds * 2` on the theory that a generous display was kinder than a
				strict one. It is not: the server picks up at `PickupRangeStuds` (6) and `CarryLimit` is
				1, so two players 7-12 studs apart near one pouch BOTH incremented, and the HUD could
				show `~2` — a number the rules make impossible. An impossible number reads as a broken
				game, not as an estimate.
			]]
			if (pouch.Position - root.Position).Magnitude <= Config.Salt.PickupRangeStuds then
				saltSeen = math.min(saltSeen + 1, Config.Salt.CarryLimit)
			end
		end)
	end
end

--[[
	Called by InputController when this client actually presses the throw key. Kept here rather than
	letting InputController touch the HUD directly, so `saltSeen` has one owner.

	`math.max` because the estimate can drift below zero if a pickup was missed.
]]
function UIController.NoteThrow()
	saltSeen = math.max(0, saltSeen - 1)
end

return UIController
