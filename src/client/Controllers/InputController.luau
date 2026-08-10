--!strict
--[[
	InputController — keyboard, touch and gamepad input.

	Milestone: M7 owns the real HUD button and the mobile thumb zones (C18/C27). Today this file exists
	for one reason: WITHOUT IT, C04 CANNOT BE TESTED BY A HUMAN AT ALL. Nothing else in the tree fires
	`RequestTransform`, so the transform would be reachable only from a console.

	It is a keyboard bind, deliberately minimal, so the two-client test is possible now. C18 replaces it.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local InputController = {}

local TRANSFORM_ACTION = "AswangTransform"

local function onTransformAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	--[[
		GATED ON THIS CLIENT'S OWN ROLE, from its own RoleAssigned. Never on a broadcast, never on
		anything derived from another player.

		This gate is UX and rate-limit courtesy, NOT security: the server re-evaluates every rule in
		TransformRules against its own state and refuses regardless of what the client believes. A
		compromised client can delete this check and gain exactly nothing, which is the correct
		relationship between a client-side gate and a server-side one.
	]]
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return Enum.ContextActionResult.Pass
	end

	-- No arguments. The server knows who fired it and reads every other input from its own state;
	-- anything passed here would be a client-supplied value the server must then refuse to trust.
	Remotes.Get("RequestTransform"):FireServer()

	return Enum.ContextActionResult.Sink
end

function InputController.Init() end

function InputController.Start()
	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
end

return InputController
