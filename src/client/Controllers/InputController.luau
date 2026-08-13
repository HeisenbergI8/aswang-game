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

local TaskController = require(script.Parent.TaskController)
local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local InputController = {}

local TRANSFORM_ACTION = "AswangTransform"
local KILL_ACTION = "AswangKill"
local TASK_ACTION = "TaskHold"
local TIMING_ACTION = "TaskTimingStop"

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

--------------------------------------------------------------------------------
-- The hold (§4.4, C08)
--------------------------------------------------------------------------------

--[[
	THE TWO BINDS ABOVE GATE ON UIController.GetMyRole(). THIS ONE MUST NOT, AND THE ABSENCE IS THE
	SECURITY PROPERTY.

	A role gate here would be a client that behaves differently depending on who it is, and every one
	of those is a confession waiting to be recorded. The transform and kill binds can afford it because
	the actions they guard are the Aswang's alone and visible when used; a task is something all eight
	players do all round, so an Aswang whose client sent no heartbeat — or sent one at a different rate,
	or stopped when the bar stopped — would be distinguishable from a survivor's by anyone who could
	watch the wire, and identical-looking to anyone who could not only by accident.

	SO: THE ASWANG'S CLIENT SENDS EXACTLY WHAT A SURVIVOR'S SENDS, and the server treats what it sends
	identically — Amendment A2, which reversed §4.4's original "its progress does not count" after an
	audit showed that rule builds the very oracle §4.4 feared. C12's deception is what the Aswang is
	SHOWN, never what its hands do. Nothing on either side of the boundary knows the difference, which
	is the only arrangement that is still true when the client is compromised.

	Cancel is handled alongside End: ContextActionService raises it when a bind is unbound or the input
	is interrupted, and treating it as Pass would leave `holding` true forever.
]]
local function onTaskAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		TaskController.SetHolding(true)

		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		TaskController.SetHolding(false)

		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

--[[
	NO ROLE GATE, for the reason the hold bind above spells out at length: a client that behaves
	differently depending on who it is, is a confession waiting to be recorded. Under Amendment A2
	there is not even a server-side difference left to hide — the Aswang's stops count exactly like
	anyone else's — but the rule stands on its own and this bind obeys it.

	Unconditional `FireServer` on Begin, with no local check of any kind. There is deliberately no
	client-side "am I at a timing task" test: the client would have to know which of the five points
	are TIMING to run one, and the honest cost of not running it is a rate-limit token.
]]
local function onTimingAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	Remotes.Get("RequestTimingStop"):FireServer()

	return Enum.ContextActionResult.Sink
end

function InputController.Init() end

function InputController.Start()
	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
	-- `E` because it is ProximityPrompt's default key, so Phase 6 is a swap rather than a retraining.
	-- `false` for createTouchButton matches the two binds above: mobile is C27's subject, and this is a
	-- known hole rather than an oversight. It is a WORSE hole here than for the other two — 60% of the
	-- audience per §5, and tasks are what all eight players do all round.
	ContextActionService:BindAction(TASK_ACTION, onTaskAction, false, Enum.KeyCode.E)
	-- `R`, because `E` is the hold and a timing point needs both. `false` for createTouchButton
	-- matches every other bind in this file: mobile is C27's subject, and this is the fourth known
	-- hole rather than a new one.
	--
	-- ⚠ `R` is NOT confirmed free of a CoreScript claim. C08 shipped unreachable because
	-- ProximityPrompt's default `E` silently swallowed the identical bind, and nothing in the tree
	-- proves `R` is not similarly claimed. `attachPrompt` sets `Enum.KeyCode.None`, which removes the
	-- known collision — but "the known one" is all that can be established statically. Playtester.
	ContextActionService:BindAction(TIMING_ACTION, onTimingAction, false, Enum.KeyCode.R)
end

return InputController
