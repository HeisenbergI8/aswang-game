--!strict
--[[
	UIController — HUD: task bar, sunrise timer, role card, end screen.

	Milestone: M7. It owns the 3-second private role intro (§4.2, C03) and a DELIBERATELY MINIMAL
	status HUD.

	═══ SCOPE NOTE ═══════════════════════════════════════════════════════════════

	The status HUD is C18's job and this is not C18. It exists because C13-C16 could not be TESTED
	without it: a tester looking at the screen could not see the phase, the timer, the task count,
	their own state, or how much salt they were carrying, so "does salt work" was unanswerable by
	looking. This is the smallest thing that makes a three-client session legible.

	What that means for C18: this is a placeholder to REPLACE, not a foundation to build on. No theme,
	no layout system, no scaling for mobile, default fonts, flat rectangles. §3's OUT list is intact —
	nothing here is a feature, it is a readout of state the client already had.

	WHAT THE HUD MAY SHOW, and the rule is the same as the intro card's: only what THIS player is
	allowed to know. The role line is drawn from `myRole`, which arrives on RoleAssigned and concerns
	only the receiving player. Nothing on screen may differ between two survivors' clients.

	THIS CONTROLLER HOLDS THE ONLY COPY OF THE ROLE THAT EXISTS ON ANY CLIENT, and it is this client's
	OWN role, received on RoleAssigned. Two rules follow and they are not stylistic:

	  · `myRole` is a module local. It is never written to an attribute, a StringValue, the character,
	    or anything under ReplicatedStorage or Workspace — all of which replicate.
	  · Nothing on screen may differ between a survivor's client and the Aswang's EXCEPT what only that
	    player can see. A recording of the Aswang's screen is a confession; a recording of anyone else's
	    must not be.

	This controller must never learn anyone else's role. If a future screen needs one, the answer is
	that it does not — §4.8's reveal arrives on RoundEnded when the round is over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UIController = {}

-- This client's OWN role, and nothing else. Read the header before adding to this.
local myRole: Types.Role? = nil

function UIController.GetMyRole(): Types.Role?
	return myRole
end

local function showIntro(role: Types.Role)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoleIntro"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new()
	label.BackgroundTransparency = 0.35 -- config-ok: placeholder scrim opacity, replaced at C18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
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
-- The status HUD. Placeholder for C18 — see the scope note in the header.
--------------------------------------------------------------------------------

local statusLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil

-- Salt carried, counted BY THIS CLIENT from its own pickups and throws. The server owns the real
-- number and never sends it (a per-player count on a broadcast remote is a shape check:secrecy cannot
-- describe), so this is a display estimate and is labelled as one on screen.
local saltSeen = 0

local function makeLabel(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	align: Enum.TextXAlignment
): TextLabel
	local label = Instance.new("TextLabel")

	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundColor3 = Color3.new()
	label.BackgroundTransparency = 0.4 -- config-ok: placeholder scrim, replaced at C18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 20 -- config-ok: placeholder type scale, replaced at C18
	label.Font = Enum.Font.Code
	label.TextXAlignment = align
	label.RichText = true
	label.Text = ""
	label.Parent = parent

	return label
end

local function ensureHud()
	if statusLabel ~= nil and statusLabel.Parent ~= nil then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusHud"
	gui.ResetOnSpawn = false -- survives a respawn, and a ghost has no respawn to survive
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	--[[
		LAYOUT CONSTANTS, WAIVED RATHER THAN PUT IN CONFIG. `Config.luau` is the balance surface — the
		numbers M12 tunes while asking "does the Aswang win too often". A label's pixel offset is not one
		of those and putting it there would dilute the file whose whole value is that everything in it
		matters. They are also all replaced wholesale at C18.

		The waiver is per-line and mandatory-reason, so this decision shows up in a diff and can be
		argued with — which is the point of the escape hatch.
	]]
	statusLabel = makeLabel(
		gui,
		"Status",
		--[[
			BELOW ROBLOX'S OWN TOPBAR CLUSTER. At y=8 this sat directly under the CoreGui logo, menu,
			chat and voice buttons, which are drawn ON TOP — the phase and the countdown were the two
			lines they covered, and those are the two a tester most needs. `IgnoreGuiInset = true` puts
			this in the same space as those buttons rather than below them, so the offset has to clear
			them manually.
		]]
		UDim2.fromOffset(8, 120), -- config-ok: HUD layout, not balance; replaced at C18
		UDim2.fromOffset(460, 108), -- config-ok: HUD layout, not balance; replaced at C18
		Enum.TextXAlignment.Left
	)
	hintLabel = makeLabel(
		gui,
		"Hints",
		UDim2.new(0, 8, 1, -40), -- config-ok: HUD layout, not balance; replaced at C18
		UDim2.fromOffset(620, 32), -- config-ok: HUD layout, not balance; replaced at C18
		Enum.TextXAlignment.Left
	)
end

local function render(snapshot: Types.ClientRoundSnapshot)
	ensureHud()

	local status = statusLabel
	local hints = hintLabel

	if status == nil or hints == nil then
		return
	end

	local minutes = math.floor(snapshot.SecondsRemaining / 60) -- config-ok: seconds in a minute
	local seconds = math.floor(snapshot.SecondsRemaining % 60) -- config-ok: seconds in a minute

	--[[
		THE ROLE LINE IS THE ONE THING ON SCREEN THAT DIFFERS BETWEEN CLIENTS, and it is drawn from
		`myRole` — this client's own, from RoleAssigned. It is deliberately NOT read from the snapshot's
		`YourRole`, so there is exactly one place in this file that knows a role.
	]]
	local roleLine = if myRole == Enums.Role.Aswang
		then '<font color="#ff5555">ASWANG</font>  ·  T transform  ·  F kill'
		else '<font color="#88ddff">SURVIVOR</font>'

	local stateColour = if snapshot.YourState == Enums.PlayerState.Ghost
		then "#aaaaff"
		else "#ffffff"

	status.Text = string.format(
		"<b>%s</b>   %d:%02d\n"
			.. "tasks  <b>%d/%d</b>   gate %s\n"
			.. 'you  <font color="%s">%s</font>   salt ~%d\n'
			.. "%s",
		snapshot.Phase,
		minutes,
		seconds,
		snapshot.TasksCompleted,
		snapshot.TasksRequired,
		if snapshot.GateOpen then "OPEN" else "shut",
		stateColour,
		snapshot.YourState,
		saltSeen,
		roleLine
	)

	if snapshot.YourState == Enums.PlayerState.Ghost then
		hints.Text = "GHOST — WASD fly · Space up · LeftCtrl down · chat reaches ghosts only"
	elseif snapshot.Phase == Enums.RoundPhase.Active then
		hints.Text =
			"E hold task · R time it · Q throw salt · walk over a white pouch to pick it up"
	else
		hints.Text = "waiting for the round"
	end
end

function UIController.Init() end

function UIController.Start()
	Remotes.Get("RoleAssigned").OnClientEvent:Connect(function(payload: Types.RoleAssignedPayload)
		myRole = payload.Role

		showIntro(payload.Role)
	end)

	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(render)

	-- A round ending clears the local salt estimate, because the server clears the real one.
	Remotes.Get("PhaseChanged").OnClientEvent:Connect(function(phase: Types.RoundPhase)
		if phase ~= Enums.RoundPhase.Active then
			saltSeen = 0
		end
	end)

	--[[
		THE SALT ESTIMATE, and why it is an estimate rather than a fact.

		`SaltEffect` fires to every client on every throw, carrying a trajectory and no player — so this
		client cannot tell whose throw it was. What it CAN tell is that it pressed Q itself, which
		InputController records. A pickup is inferred the same way: the pouch this client was standing
		on disappeared.

		The honest alternative is a new down-remote carrying an authoritative count to one player, which
		is a real change to the network surface and belongs to C18 with its own secrecy argument. Until
		then the number is prefixed `~` on screen so a tester reads it as a hint, not a truth.
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
				Generous radius: this is a display hint, and being slightly wrong is better than showing
				zero to somebody holding salt.
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
				game, not as an estimate, and a tester would reasonably report "I have salt but cannot
				throw it" as a gameplay bug.

				Matching the server's radius makes a miscount rare; the clamp makes an IMPOSSIBLE count
				unreachable, which is the property that matters for a readout nobody should have to
				double-check.
			]]
			if (pouch.Position - root.Position).Magnitude <= Config.Salt.PickupRangeStuds then
				saltSeen = math.min(saltSeen + 1, Config.Salt.CarryLimit)
			end
		end)
	end

	--[[
		A throw spends one. The client knows it threw because it pressed the key — `SaltEffect` names
		nobody, deliberately, so it cannot be used to attribute a throw. `math.max` because the estimate
		can drift below zero if a pickup was missed.
	]]
	Remotes.Get("SaltEffect").OnClientEvent:Connect(function()
		-- Fires for EVERY throw by anyone, so it cannot decrement on its own. The decrement lives with
		-- the keypress in InputController; this connection exists only to keep the remote wired.
	end)
end

--[[
	Called by InputController when this client actually presses the throw key. Kept here rather than
	letting InputController touch the HUD directly, so `saltSeen` has one owner.
]]
function UIController.NoteThrow()
	saltSeen = math.max(0, saltSeen - 1)
end

return UIController
