--!strict
--[[
	InputController — keyboard, touch and gamepad input.

	Milestone: M7 owns the real HUD button and the mobile thumb zones (C18/C27). Today this file exists
	for one reason: WITHOUT IT, C04 AND C05 CANNOT BE TESTED BY A HUMAN AT ALL. Nothing else in the tree
	fires `RequestTransform` or `RequestKill`, so both would be reachable only from a console.

	It is a keyboard bind, deliberately minimal, so the two-client test is possible now. C18 replaces it.

	NEITHER BIND CREATES A TOUCH BUTTON. `createTouchButton` is false on both, so mobile — 60% of the
	audience, per §5 — cannot transform or kill yet. That is C27's subject and it is a known hole rather
	than an oversight; naming it here so it is not rediscovered as a bug.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local InputController = {}

local TRANSFORM_ACTION = "AswangTransform"
local KILL_ACTION = "AswangKill"

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

--------------------------------------------------------------------------------
-- The kill (§4.3 step 3, C05)
--------------------------------------------------------------------------------

local function rootPosition(player: Player): Vector3?
	local character = player.Character

	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

--[[
	THE CLIENT PICKS THE TARGET, AND THAT IS NOT A SECURITY DECISION.

	§4.3 says the Aswang "can kill on touch/prompt within 8 studs", so something has to turn a keypress
	into a UserId. Doing it here reads only positions this client already has — every character
	replicates — and the server then re-derives distance, line of sight, phase, both roles, both player
	states, the transform state and the cooldown from ITS own state before committing anything. A
	compromised client can send any UserId it likes and gains nothing; `KillValidation` is the authority
	and this is a convenience.

	It is NOT a role oracle either, which is the thing worth checking twice in this game: the selection
	runs entirely locally, sends nothing on its own, and the server answers every refusal with silence.

	Nearest wins, and `<=` matches the server's boundary exactly (§4.3, "within 8 studs") so a target
	the server would accept is never skipped here. Returning nil when nothing is in reach means an
	out-of-range press costs no rate-limit token at all.
]]
local function nearestTarget(): Player?
	local me = Players.LocalPlayer
	local myPosition = rootPosition(me)

	if myPosition == nil then
		return nil
	end

	local best: Player? = nil
	local bestDistance = Config.Monster.KillRange

	for _, player in Players:GetPlayers() do
		if player ~= me then
			local position = rootPosition(player)

			if position ~= nil then
				local distance = (position - myPosition).Magnitude

				if distance <= bestDistance then
					best = player
					bestDistance = distance
				end
			end
		end
	end

	return best
end

local function onKillAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	-- Same gate, same reasoning as the transform above: courtesy and rate-limit hygiene, never security.
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return Enum.ContextActionResult.Pass
	end

	local target = nearestTarget()

	if target == nil then
		return Enum.ContextActionResult.Pass
	end

	Remotes.Get("RequestKill"):FireServer(target.UserId)

	return Enum.ContextActionResult.Sink
end

function InputController.Init() end

function InputController.Start()
	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
end

return InputController
