--!strict
--[[
	REVIEW — src/client/Controllers/UIController.luau:241-280, 861

	Read for the GUI construction idiom C25's wheel copies, and to check the wheel will not collide
	with the HUD that already exists.
]]

local function makeActionButton(parent: Instance, name: string, label: string, order: number): TextButton
	local button = Instance.new("TextButton")

	button.Name = name
	button.Size = UDim2.fromOffset(LAYOUT.ButtonWidth, LAYOUT.ButtonHeight)
	button.Position = UDim2.fromOffset(0, (LAYOUT.ButtonHeight + LAYOUT.Pad) * order)
	button.BackgroundColor3 = COLOUR.Panel
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = parent

	return button
end

-- NOTE: the house style is imperative Instance.new with every property set explicitly and `.Parent`
-- assigned LAST. C25's sector buttons follow it. Note `BorderSizePixel = 0` and an explicit `Font` on
-- every control — Roblox's defaults are not what this game looks like.

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

--[[
	IMPORTANT — `ResetOnSpawn = false` IS LOAD-BEARING FOR C25, and the inline comment says why in
	seven words: "a ghost has no respawn to survive". The wheel must carry the same flag. A wheel that
	reset on death would silently remove the ghost quick-chat channel the moment a player needs it,
	and §4.7's whole retention argument is that a dead player must still have something to do.

	NOTE — the idempotence guard (`if hud ~= nil and hud.Parent ~= nil then return end`) is copied into
	`buildWheel`. It matters more there than here: `buildWheel` is called from BOTH `Init` and
	`openAt`, so without it a press before Init completed would build a second wheel.

	IMPORTANT — LAYOUT COLLISION CHECK. buildHud places the timer panel top-centre
	(`UDim2.new(0.5, -BarWidth/2, 0, TopInset)`), the task bar below it, and action buttons in a
	left-hand column. Nothing in the HUD occupies the bottom-right quadrant, which is where C25's open
	button goes and where ContextActionService already places the salt throw button. So the conflict
	to watch is wheel-vs-salt, NOT wheel-vs-HUD — which is the plan's Follow Up 4 and the
	playtester's screenshot in Step 5.1.

	NOTE — `IgnoreGuiInset = true` on both. The comment at UIController.luau:103 explains it clears
	Roblox's own topbar. The wheel opens under the thumb near the bottom, so the inset is not a
	practical concern there, but matching the flag keeps the two GUIs in the same coordinate space —
	which matters if anyone later wants to position the wheel relative to a HUD element.

	QUESTION — resolved: should the wheel live inside the existing "Hud" ScreenGui instead of its own?
	No. A separate ScreenGui can be enabled and disabled wholesale — which is how `openAt` and
	`closeAndCommit` work — without touching HUD visibility. Sharing one would mean toggling
	individual frames and risking the HUD disappearing with the wheel. `showIntro` and `showEndScreen`
	(UIController.luau:413, 485) both create their own ScreenGui for the same reason, so this is the
	established pattern rather than a new one.
]]
