--!strict
--[[
	UIController — the HUD (C18, milestone M7).

	Sunrise timer, task bar, gate state, salt indicator, contextual prompts, the Aswang's action
	buttons, and the end screen with the reveal. It replaces the C13-C16 placeholder wholesale, as that
	placeholder's own header asked to be replaced.

	UGLY AND FUNCTIONAL, ON PURPOSE. Default fonts, flat rectangles, no theme, no art. C34 does polish
	and the build plan is explicit that it happens AFTER six humans have said what the HUD is missing —
	so anything here that looks like taste is a placeholder for a decision GATE 1 has not made yet.

	═══ THE ALIVE COUNT IS NOT HERE, AND THAT IS THE SPEC, NOT AN OMISSION ═══════

	`BUILD-PLAN.md` §C18 lists "sunrise timer, global task bar, alive count — all from RoundSnapshot".
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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
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
	BarBackScrim = 0.55, -- config-ok: placeholder background opacity

	-- When the sunrise timer starts reading as urgent. Presentation, not balance: the round is not
	-- affected, the number just turns red so a player looks up.
	UrgentSeconds = 30, -- config-ok: when the timer turns red; changes nothing about the round
}

--[[
	The palette, and it is RGB TRIPLES for the same reason Config's are: `Config.Monster`,
	`Config.Tasks` and `Config.Salt` all store colours as `{ r, g, b }` rather than as `Color3`, so
	that a value is data rather than a constructed object.

	These are not in Config because they are not shared with the server and nothing balances against
	them. The Aswang red and the survivor blue in particular are C34's to replace, once GATE 1 has said
	whether the HUD reads at all.
]]
local COLOUR = {
	Text = Color3.fromRGB(255, 255, 255), -- config-ok: HUD palette, not balance
	Dim = Color3.fromRGB(178, 178, 178), -- config-ok: HUD palette
	Urgent = Color3.fromRGB(255, 96, 96), -- config-ok: HUD palette
	Aswang = Color3.fromRGB(255, 85, 85), -- config-ok: HUD palette
	Survivor = Color3.fromRGB(136, 221, 255), -- config-ok: HUD palette
	Ghost = Color3.fromRGB(170, 170, 255), -- config-ok: HUD palette
	Progress = Color3.fromRGB(96, 220, 120), -- config-ok: HUD palette
	GateOpen = Color3.fromRGB(255, 214, 92), -- config-ok: HUD palette
	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: HUD palette
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
]]
export type ActionHandlers = {
	Transform: () -> (),
	Kill: () -> (),
}

local actionHandlers: ActionHandlers? = nil

function UIController.BindActions(handlers: ActionHandlers)
	actionHandlers = handlers
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
-- never allocates — it runs at Config.Round.SnapshotInterval, several times a
-- second, for the whole round.
--------------------------------------------------------------------------------

local hud: ScreenGui? = nil
local timerLabel: TextLabel? = nil
local phaseLabel: TextLabel? = nil
local barFill: Frame? = nil
local barLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local promptLabel: TextLabel? = nil
local actionFrame: Frame? = nil

local function panel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.BackgroundColor3 = COLOUR.Panel
	frame.BackgroundTransparency = LAYOUT.Scrim
	frame.BorderSizePixel = 0
	frame.Parent = parent

	return frame
end

local function text(parent: Instance, name: string, size: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = colour
	label.TextSize = size
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.Text = ""
	label.Parent = parent

	return label
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

	--[[
		The global task bar, and it is a BAR rather than a number because it is the only shared goal on
		screen. §4.4 assigns progress to the WORLD, not to a player: everyone's bar reads the same, and
		that is the point — it is the thing survivors coordinate around and the thing the Aswang has to
		watch climb.
	]]
	local barPanel = panel(gui, "TaskBar")
	barPanel.Size =
		UDim2.fromOffset(LAYOUT.BarWidth, LAYOUT.BarHeight + LAYOUT.LabelSize + LAYOUT.Pad)
	barPanel.Position = UDim2.new(
		0.5,
		-LAYOUT.BarWidth / 2,
		0,
		LAYOUT.TopInset + LAYOUT.TimerSize + LAYOUT.LabelSize + LAYOUT.Pad * 2
	)

	barLabel = text(barPanel, "Count", LAYOUT.LabelSize, COLOUR.Dim);
	(barLabel :: TextLabel).Size = UDim2.new(1, 0, 0, LAYOUT.LabelSize);
	(barLabel :: TextLabel).Position = UDim2.fromOffset(0, LAYOUT.Pad / 2)

	local barBack = Instance.new("Frame")
	barBack.Name = "Track"
	barBack.Size = UDim2.new(1, -LAYOUT.Pad, 0, LAYOUT.BarHeight)
	barBack.Position = UDim2.fromOffset(LAYOUT.Pad / 2, LAYOUT.LabelSize + LAYOUT.Pad / 2)
	barBack.BackgroundColor3 = COLOUR.Panel
	barBack.BackgroundTransparency = LAYOUT.BarBackScrim
	barBack.BorderSizePixel = 0
	barBack.Parent = barPanel

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOUR.Progress
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	barFill = fill

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
		else "You are a survivor.\nFinish five tasks and escape."
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
		return "SUNRISE — NOBODY FINISHED", COLOUR.GateOpen
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
	backdrop.BackgroundTransparency = LAYOUT.Scrim
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	local headline, colour = describeResult(payload.Result)

	local title = text(backdrop, "Result", LAYOUT.RevealSize, colour)
	title.Size = UDim2.new(1, 0, 0, LAYOUT.RevealSize * 2)
	title.Position = UDim2.new(0, 0, 0.5, -LAYOUT.RevealSize * 2)
	title.Text = headline

	local reveal = text(backdrop, "Reveal", LAYOUT.PromptSize, COLOUR.Text)
	reveal.Size = UDim2.new(1, 0, 0, LAYOUT.PromptSize * 2)
	reveal.Position = UDim2.new(0, 0, 0.5, LAYOUT.Pad)
	reveal.Text = `The aswang was <b>{nameOfAswang(payload.AswangUserId)}</b>`

	screenGui.Parent = playerGui

	-- Dismissed on the same clock the server uses to start the next round, so the screen is never
	-- still up when the lobby is already running.
	task.delay(Config.Round.EndScreen, function()
		screenGui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

local function promptFor(snapshot: Types.ClientRoundSnapshot): string
	if snapshot.YourState == Enums.PlayerState.Ghost then
		return "WASD fly · Space up · LeftCtrl down · your chat reaches ghosts only"
	elseif snapshot.YourState == Enums.PlayerState.Spectator then
		return "watching — you join the next round"
	elseif snapshot.Phase ~= Enums.RoundPhase.Active then
		return "waiting for the round to start"
	elseif snapshot.GateOpen then
		return "THE GATE IS OPEN — get to the plaza"
	end

	return "E hold a task · R time it · Q throw salt · walk over a pouch to take it"
end

local function render(snapshot: Types.ClientRoundSnapshot)
	buildHud()

	local clock = timerLabel
	local phase = phaseLabel
	local fill = barFill
	local count = barLabel
	local status = statusLabel
	local prompt = promptLabel

	if
		clock == nil
		or phase == nil
		or fill == nil
		or count == nil
		or status == nil
		or prompt == nil
	then
		return
	end

	local minutes = math.floor(snapshot.SecondsRemaining / 60) -- config-ok: seconds in a minute
	local seconds = math.floor(snapshot.SecondsRemaining % 60) -- config-ok: seconds in a minute

	clock.Text = string.format("%d:%02d", minutes, seconds)
	clock.TextColor3 = if snapshot.Phase == Enums.RoundPhase.Active
			and snapshot.SecondsRemaining <= LAYOUT.UrgentSeconds
		then COLOUR.Urgent
		else COLOUR.Text
	phase.Text = if snapshot.Phase == Enums.RoundPhase.Active
		then "UNTIL SUNRISE"
		else snapshot.Phase

	-- Guarded because a map with no task points reports zero required, and dividing by it would put
	-- `nan` on screen — which reads as a broken game rather than as a broken map.
	local ratio = if snapshot.TasksRequired > 0
		then snapshot.TasksCompleted / snapshot.TasksRequired
		else 0

	fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	count.Text = `TASKS {snapshot.TasksCompleted}/{snapshot.TasksRequired}`

	--[[
		THE ROLE LINE IS THE ONE THING ON SCREEN THAT DIFFERS BETWEEN CLIENTS, and it is drawn from
		`myRole` — this client's own, from RoleAssigned. It is deliberately NOT read from the snapshot's
		`YourRole`, so there is exactly one place in this file that knows a role.
	]]
	local roleColour = if myRole == Enums.Role.Aswang then COLOUR.Aswang else COLOUR.Survivor
	local roleWord = if myRole == Enums.Role.Aswang then "ASWANG" else "SURVIVOR"

	local stateColour = if snapshot.YourState == Enums.PlayerState.Ghost
		then COLOUR.Ghost
		else COLOUR.Text

	status.Text = string.format(
		'<font color="#%s">%s</font>\n'
			.. '<font color="#%s">%s</font>   salt ~%d\n'
			.. 'gate <font color="#%s">%s</font>',
		roleColour:ToHex(),
		roleWord,
		stateColour:ToHex(),
		snapshot.YourState,
		saltSeen,
		if snapshot.GateOpen then COLOUR.GateOpen:ToHex() else COLOUR.Dim:ToHex(),
		if snapshot.GateOpen then "OPEN" else "shut"
	)

	prompt.Text = promptFor(snapshot)

	--[[
		The buttons follow the phase as well as the role: a transform button during INTERMISSION is an
		affordance for something the server will refuse, and a refusal the player cannot explain reads
		as a bug. `myRole` alone decides whether they EXIST; the phase decides whether they are offered.
	]]
	local actions = actionFrame

	if actions ~= nil then
		actions.Visible = myRole == Enums.Role.Aswang
			and snapshot.Phase == Enums.RoundPhase.Active
			and snapshot.YourState == Enums.PlayerState.Alive

		for _, child in actions:GetChildren() do
			if child:IsA("TextButton") then
				child.Visible = actions.Visible
			end
		end
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
