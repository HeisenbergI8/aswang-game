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
local SEARCH_ACTION = "SearchContainer"
-- V07. C and G were both unclaimed; the four bound today are T, F, Q and E.
local CAMOUFLAGE_ACTION = "AswangCamouflage"
local SMOKE_ACTION = "AswangSmoke"

--[[
	V08, §4.6. THE DROP KEY, AND IT DECIDES NOTHING.

	NO ARGUMENT AND NO CLIENT-SIDE CHECK. `Config.Items.CarryLimit` is 1, so the server already knows
	what this player is holding, and `pure/ItemDrop` on the server owns whether they may put it down.
	An `if carried == nil then return end` guard here would be a second copy of a rule, and the two
	would disagree the first time a pickup and a drop crossed on the wire — which is verbatim the
	reasoning this file already gives for not pre-checking the throw.

	MOBILE GETS A BUTTON, NOT A KEY. §5 puts ~60% of players on a phone; the pad is how the throw
	already reaches them, and the drop is registered with it below for the same reason. Its
	thumb-zone placement is `ui-polish`'s question, not this chunk's.
]]
local DROP_ACTION = "ItemDrop"

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

--[[
	V07, §4.3. BOUND FOR EVERY PLAYER, EVERY ROUND — `performTransform`'s rule, for its reason.

	A BUTTON THAT ONLY THE ASWANG CAN SEE IS THE REVEAL, on the monster's own screen, where a stream
	or a screen recording makes it permanent. The bind is unconditional and the role check is local
	and silent, exactly as the transform's is; the server refuses a survivor independently (Step 5.1)
	and tells them nothing, so the two agree without the client having to be trusted.

	NO LOCAL COOLDOWN, DELIBERATELY. `SmokeCooldown` and the camouflage charge both live on the
	server. A client-side timer here would mask a server refusal and let the two disagree about
	whether an ability was available — and the client's copy would be the one the player believes.
]]
local function performCamouflage(): boolean
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return false
	end

	-- No arguments. The server picks the form from the population it owns; see `Remotes.luau` for why
	-- a client-named form would be a probe for the live ambient roster.
	Remotes.Get("RequestCamouflage"):FireServer()

	return true
end

local function performSmoke(): boolean
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return false
	end

	-- No arguments. The burst happens at the requester's own position, read server-side.
	Remotes.Get("RequestSmoke"):FireServer()

	return true
end

local function onCamouflageAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performCamouflage()
		then Enum.ContextActionResult.Sink
		else Enum.ContextActionResult.Pass
end

local function onSmokeAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performSmoke() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
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

	--[[
		V08 DELETED THE OPTIMISTIC DECREMENT WITH THE ESTIMATE IT CORRECTED.

		C13 called `UIController.NoteThrow()` here because the HUD counted salt itself and
		`SaltEffect` names nobody, so a throw could not be attributed. The HUD now reads
		`ClientRoundSnapshot.YourCarriedItem`, which the server owns — so the display updates from
		the next snapshot, at most `Config.Round.SnapshotInterval` away.

		THE THROW'S OWN FEEDBACK WAS NEVER THE HUD ANYWAY. `SaltEffect` broadcasts a burst at the
		impact point and every client renders it, the thrower's included. That is immediate and
		diegetic; the label was always the slower half.
	]]
	return true
end

--[[
	V08, §4.6. Put down what you are holding. Argument-free — see `DROP_ACTION` above and the
	declaration in `Remotes.luau`; the server resolves the item from the player's own slot.
]]
local function performDrop(): boolean
	Remotes.Get("RequestDropItem"):FireServer()

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

-- V08. A press, not a hold — dropping is instantaneous, unlike §4.4's search.
local function onDropAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	return if performDrop() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

--[[
	V03, §4.4. A HOLD RATHER THAN A PRESS, which is why this is a PAIR of functions where every other
	verb in this file is one.

	NOT GATED ON ROLE, and the absence of that gate is the design. `performTransform` and `performKill`
	check the role because they are Aswang verbs; searching is everyone's, and §4.4 is explicit that
	the Aswang searches on identical rules — rummaging in a house is blending justified by mechanics.
	A gate here would make the monster's client behave differently from a survivor's, which is
	Amendment A2's oracle in the one place nobody would look for it.

	NEITHER SENDS AN ARGUMENT. The server resolves which container from this player's own character
	position; naming one here would hand a compromised client a probe. See `Remotes.luau`.

	NO CLIENT-SIDE GATE ON PHASE OR DISTANCE EITHER, unlike `performKill`'s role check. The server
	answers with a verdict the controller can show, and a client-side pre-check would only ever
	disagree with it — the client does not know `opened`, and cannot.
]]
local function performSearch(): boolean
	Remotes.Get("RequestSearch"):FireServer()

	return true
end

local function performCancelSearch(): boolean
	Remotes.Get("RequestCancelSearch"):FireServer()

	return true
end

--[[
	`Begin` starts, `End` AND `Cancel` stop. Cancel matters: ContextActionService fires it when the
	bind is unbound or the input is stolen — a chat box opening mid-hold — and treating it as anything
	other than a release leaves a player holding a container they cannot let go of by any input.
]]
local function onSearchAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		performSearch()

		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		performCancelSearch()

		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
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
		-- V08. The drop rides the same registration path as the throw, so the pad and the key run
		-- one implementation rather than two that agree until one is edited.
		Drop = function()
			performDrop()
		end,
		--[[
			V03. REGISTERED AS A PAIR because §4.4's verb is a hold, not a tap — the pad reports when
			the thumb goes down and when it comes up, exactly as `BindQuickChat` does for the wheel's
			press-drag-release. Registering only a `Search` would give a mobile player a way to start a
			search and no way to stop one.

			THE PAD DOES NOT DRAW A SEARCH BUTTON YET, and that is a real gap rather than a rounding
			error: searching is the thing all five players do all round, and §5 puts ~60% of them on a
			phone. It is exactly the hole this file's header describes closing for tasks, now re-opened
			by the mechanic that replaced them. It must not survive past V16.
		]]
		Search = function()
			performSearch()
		end,
		CancelSearch = function()
			performCancelSearch()
		end,
		--[[
			V07. REGISTERED FOR THE TOUCH PAD LIKE EVERY OTHER VERB, so mobile runs this file's
			functions rather than its own copies. §5 puts ~60% of players on a phone, so a verb that
			exists only on a keyboard is a verb the majority of Aswangs never get.
		]]
		Camouflage = function()
			performCamouflage()
		end,
		Smoke = function()
			performSmoke()
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
		why `Config.Items.ThrowConeDegrees` exists rather than a raycast.

		`Q` REACHES THIS HANDLER — confirmed at C27, the same way `R` above was. One press produced one
		`RequestThrowSalt` carrying the camera LookVector, and `RequestTrialThrow` stayed silent, so
		C22's routing survived the extraction into `performThrow`:
		`.claude/plans/c27-c28-verification/artifacts/desktop-keys-console.txt`. The pad remains the
		answer for a phone regardless, which is why the throw no longer rests on this key alone.
	]]
	ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q)

	--[[
		V03. `E`, and `false` for the touch-button argument for the same reason every bind in this file
		passes it: NO BIND HERE CREATES A TOUCH BUTTON. A CAS touch button appears for every client
		that runs the bind, and the pad is the one thing in this game that places a touch control.

		`E` IS ALSO ROBLOX'S DEFAULT `ProximityPrompt` KEY. No prompt exists in this game today, so
		there is no conflict now — but this bind is registered first, and a prompt added to the map
		later would simply look broken.
	]]
	ContextActionService:BindAction(SEARCH_ACTION, onSearchAction, false, Enum.KeyCode.E)

	-- V07, §4.3. Bound for everyone; the role check is inside the two perform functions and the
	-- server refuses a survivor independently.
	ContextActionService:BindAction(CAMOUFLAGE_ACTION, onCamouflageAction, false, Enum.KeyCode.C)
	ContextActionService:BindAction(SMOKE_ACTION, onSmokeAction, false, Enum.KeyCode.G)

	--[[
		V08, §4.6. `X`. Bound for everyone — §4.4 has the Aswang carrying and dropping on identical
		rules, so a bind that existed for only one role would be a role oracle in the keymap.

		`false` for the touch-button argument, like every bind in this file: no bind here creates a
		CAS touch button, and the pad is the one thing in this game that places a touch control.
	]]
	ContextActionService:BindAction(DROP_ACTION, onDropAction, false, Enum.KeyCode.X)
end

return InputController
