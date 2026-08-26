--!strict
--[[
	InputController — keyboard, touch and gamepad input.

	Milestone: M7. This file owns the KEYS and the target selection; C18's HUD owns the on-screen
	buttons, and both run the same two functions — `performTransform` and `performKill` — which this
	controller registers with `UIController.BindActions` at Start.

	THAT REGISTRATION IS NOT PLUMBING, IT IS THE FIX FOR A REAL BUG. C18's KILL button first built its
	own request, omitted the target UserId, and so fired something the server refuses AFTER spending a
	rate-limit token. Two implementations of one action drift; one implementation with two triggers
	cannot. See `performKill`.

	The dependency only points one way: this module requires `UIController` for `GetMyRole`, so the HUD
	cannot require this one back. Registration is what makes the arrow point the right way.

	NO BIND IN THIS FILE CREATES A TOUCH BUTTON, and since C27 that is the whole story rather than
	half of it. Every verb here is registered with `UIController.BindActions` and drawn by C27's touch
	pad, which is the one thing in this game that places a touch control.

	The division is deliberate and `ContextActionService` is the reason: a CAS touch button appears for
	EVERY client that runs the bind, so it cannot be Aswang-only (the role gate lives inside the
	handler, not on the bind), cannot appear only while a timing bar exists, and cannot be placed in a
	thumb zone this game chose. The pad does all three. What is left in this file is the KEYS.

	The hole this header used to name — mobile could not do a TASK, the thing all eight players do all
	round — is closed. If it reopens, it reopens in `UIController.buildTouchPad`.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrialController = require(script.Parent.TrialController)
local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local InputController = {}

local TRANSFORM_ACTION = "AswangTransform"
local KILL_ACTION = "AswangKill"
local THROW_ACTION = "SaltThrow"

--[[
	A plain function for the same reason `performKill` below is one: C18's HUD button must invoke THIS,
	not a second copy of it. Returns whether the request was sent.

	GATED ON THIS CLIENT'S OWN ROLE, from its own RoleAssigned. Never on a broadcast, never on
	anything derived from another player.

	This gate is UX and rate-limit courtesy, NOT security: the server re-evaluates every rule in
	TransformRules against its own state and refuses regardless of what the client believes. A
	compromised client can delete this check and gain exactly nothing, which is the correct
	relationship between a client-side gate and a server-side one.
]]
local function performTransform(): boolean
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return false
	end

	-- No arguments. The server knows who fired it and reads every other input from its own state;
	-- anything passed here would be a client-supplied value the server must then refuse to trust.
	Remotes.Get("RequestTransform"):FireServer()

	return true
end

local function onTransformAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performTransform()
		then Enum.ContextActionResult.Sink
		else Enum.ContextActionResult.Pass
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

--[[
	THE KILL, AS A PLAIN FUNCTION, SO THE HUD BUTTON CANNOT DIVERGE FROM THE KEY.

	It used to live entirely inside `onKillAction`, and C18's KILL button therefore reimplemented it —
	badly. It fired `RequestKill` with NO target, which `MonsterService` refuses after already spending
	a rate-limit token, so the button was a silent no-op that drained the Aswang's budget. The two
	things it skipped are exactly the two things this function does that a naive re-implementation
	would not think to: pick a target, and DO NOT FIRE when there isn't one.

	Returns whether the request was actually sent, so the key handler can Sink or Pass correctly. A
	press with nobody in range must Pass rather than Sink — the rate limiter is the reason: firing on
	empty air is how you arrive at the moment that matters with no tokens left.
]]
local function performKill(): boolean
	-- Courtesy and rate-limit hygiene, never security — same reasoning as the transform gate above.
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return false
	end

	local target = nearestTarget()

	if target == nil then
		return false
	end

	Remotes.Get("RequestKill"):FireServer(target.UserId)

	return true
end

local function onKillAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performKill() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

--[[
	THE SALT THROW (§4.6, C14). The client's entire contribution to this mechanic is a direction.

	It sends `camera.CFrame.LookVector` and stops. It does not raycast, does not pick a target, does
	not check range, does not check whether anyone is in front of it, and — critically — does not
	predict a hit and render one optimistically. A client that renders a hit the server refused is a
	client that has told its player the monster is stunned when it is not, which is worse than latency.

	IT DOES NOT GATE ITSELF ON A POUCH COUNT EITHER, beyond hiding the button. The server owns
	`carried` and refuses with NO_POUCH; a client-side check here would be a second copy of a rule and
	the two would disagree the first time a pickup and a throw crossed on the wire.
]]
local function performThrow(): boolean
	local camera = workspace.CurrentCamera

	if camera == nil then
		return false
	end

	--[[
		C22. IN A TRIAL, Q FIRES THE TRIAL'S THROW INSTEAD.

		Both remotes take a direction and nothing else, and both resolve through the same
		`SaltThrow.inCone` on the server — so this is a routing decision, not two mechanics. The
		player presses the same key and learns the same aim.

		It has to be routed because `ItemService` resolves against the ROUND phase, which is IDLE
		during a trial: sending the real remote there gets a silent WRONG_PHASE and the tutorial
		teaches an action the player is refused. Asking `TrialController` rather than tracking a
		second flag here keeps one piece of state; the server re-checks the session either way, so a
		client that picks wrongly gets a refusal rather than an advantage.
	]]
	if TrialController.IsActive() then
		Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
	else
		Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
	end

	-- The HUD's salt estimate lives in UIController and is decremented HERE, at the keypress, because
	-- `SaltEffect` names nobody and cannot attribute a throw. Optimistic: the server may refuse this
	-- (no pouch, wrong phase), in which case the display is briefly one low and self-corrects on the
	-- next pickup. It is prefixed `~` on screen for exactly that reason.
	UIController.NoteThrow()

	return true
end

local function onThrowAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performThrow() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

function InputController.Init() end

function InputController.Start()
	--[[
		HAND THE HUD THE SAME TWO FUNCTIONS THE KEYS RUN.

		The dependency points this way and cannot point the other: this module already requires
		`UIController` for `GetMyRole`, so `UIController` requiring this one back would be a cycle.
		Registration is what lets the button and the key be the SAME code rather than two copies that
		agree until one of them is edited — which is exactly how C18 shipped a KILL button that fired
		with no target and silently burned the Aswang's rate limit.

		Registered before the binds, so a button cannot be pressed against a nil handler in the window
		between them. `UIController.Start` has already run — `init.client.luau` orders this controller
		last for precisely this class of reason.
	]]
	UIController.BindActions({
		Transform = function()
			performTransform()
		end,
		Kill = function()
			performKill()
		end,
		--[[
			C27 REGISTERS THE THROW TOO, so the touch pad runs this file's verbs rather than its own
			copies of them. Mobile is ~60% of the audience per §5, so the drift this prevents would be
			the majority experience being broken while the desktop path — the one being tested from a
			desk — stayed green. (C27 registered three more; V01 took the hold and the timing stop with
			the task system, and V03's search takes the hold's slot back.)
		]]
		Throw = function()
			performThrow()
		end,
	})

	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)

	--[[
		`Q`, and `false` for createTouchButton SINCE C27 — this bind was the one exception in the file
		and it is now the rule again, because the reason for the exception was ANSWERED rather than
		withdrawn.

		C14 asked for a CAS touch button here on the grounds that §5 puts ~60% of players on a phone
		and §4.6 is the only counterplay in the game: a mobile player with no throw is playing a
		version of the round with no answer to the monster at all, which is Appendix C's failure mode
		rather than a polish item. Every word of that still holds. What changed is who draws the
		button — C27's pad in `UIController` draws SALT itself, in a thumb zone this game chose,
		alongside the four verbs a CAS button cannot express: an Aswang-only gate, a press-and-hold,
		and a button that exists only while a timing bar does.

		THERE IS NOW EXACTLY ONE SYSTEM PLACING TOUCH CONTROLS, which was worth doing on its own.
		C25's header records that whether a SECOND requested CAS button stacks predictably above the
		first was never established; two systems placing buttons is a collision nobody can debug from
		a screenshot, and this repo has already lost rounds to a control that silently did not exist.

		The throw is still the bind that survives a touch button best — it is aimed by the CAMERA,
		which a phone player is already controlling, so the button carries no aiming burden. That is
		why `Config.Salt.ThrowConeDegrees` exists rather than a raycast.

		`Q` REACHES THIS HANDLER — confirmed at C27, the same way `R` above was. One press produced one
		`RequestThrowSalt` carrying the camera LookVector, and `RequestTrialThrow` stayed silent, so
		C22's routing survived the extraction into `performThrow`:
		`.claude/plans/c27-c28-verification/artifacts/desktop-keys-console.txt`. The pad remains the
		answer for a phone regardless, which is why the throw no longer rests on this key alone.
	]]
	ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q)
end

return InputController
