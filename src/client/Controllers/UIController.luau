--!strict
--[[
	UIController — HUD: task bar, sunrise timer, role card, end screen.

	Milestone: M7. Today it owns exactly one thing: the 3-second private role intro (§4.2, C03).

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

function UIController.Init() end

function UIController.Start()
	Remotes.Get("RoleAssigned").OnClientEvent:Connect(function(payload: Types.RoleAssignedPayload)
		myRole = payload.Role

		showIntro(payload.Role)
	end)
end

return UIController
