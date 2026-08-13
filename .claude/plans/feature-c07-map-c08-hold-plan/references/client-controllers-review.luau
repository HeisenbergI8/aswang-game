--!strict
-- REVIEW: src/client/init.client.luau:17-23, 60-84
--         src/client/Controllers/InputController.luau:1-13, 31-57, 76-100, 145-152
--         src/client/Controllers/UIController.luau:1-35
--
-- The client precedent this plan copies, and the one thing it must NOT copy.

-- ── init.client.luau ──────────────────────────────────────────────────────────
local CONTROLLER_ORDER = {
	"AudioController", "CameraFXController", "UIController", "QuickChatController", "InputController",
}
-- NOTE: Step 5.1 inserts "TaskController" before "InputController". The order governs Init/Start, not
-- requires (those are direct, as InputController already does for UIController) — but InputController's
-- bind calls into TaskController, and a bind that can fire before Init has run is a race worth avoiding.
-- NOTE the loop pcalls each Init and Start and only warns on failure, same as the server bootstrap. A
-- controller that throws in Start is a silent partial client.

Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
	local tasks = `{snapshot.TasksCompleted}/{snapshot.TasksRequired}`
	if line == lastSnapshotLine then return end
-- IMPORTANT: the M1 smoke test ALREADY prints the global task counter. Once this plan lands it becomes
-- the second, coarser view of the same number — the snapshot at 2 Hz, TaskProgressChanged on change —
-- and the two must agree. If they ever disagree the bug is RoundService.SetTasksCompleted, because that
-- is the only writer either of them reads.
-- NOTE the change-detection idiom (skip when the line is identical) is exactly what publishProgress
-- does with lastSentProgress, for the same reason: a per-tick message nobody needed.

-- ── InputController.luau ──────────────────────────────────────────────────────
--[[ Today this file exists for one reason: WITHOUT IT, C04 AND C05 CANNOT BE TESTED BY A HUMAN AT ALL.
	 It is a keyboard bind, deliberately minimal, so the two-client test is possible now. C18 replaces it. ]]
-- IMPORTANT: the precedent that justifies Phases 1-5 building the hold on ContextActionService rather
-- than on an unconfirmed ProximityPrompt. The repo has already decided once that a minimal keybind is
-- the right way to make a mechanic testable before its real affordance exists.

	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)  -- :149
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)            -- :150
-- NOTE: T and F are taken. Step 5.2 binds E — ProximityPrompt's default key, so Step 6.3 is a swap
-- rather than retraining the player.
-- NOTE both pass `false` for createTouchButton, so neither works on mobile. The new bind matches, and
-- that is a WORSE hole for tasks than for transform or kill: 60% of the audience per §5, and tasks are
-- what all eight players do all round. Risk R8, deferred to C27, named rather than hidden.

	if inputState ~= Enum.UserInputState.Begin then                                -- :37, :123
		return Enum.ContextActionResult.Pass
	end
-- IMPORTANT: both existing handlers are FIRE-ON-PRESS and therefore only ever look at Begin. The task
-- bind is the first HOLD in this repo, so it is the first to need End — and Cancel, which appears
-- nowhere in this codebase. That is Follow Ups Q2. Consequence if Cancel never raises: `holding` sticks
-- true and the client burns rate-limit tokens; it gains no progress, because the server re-measures
-- distance every tick. A throttle, not an exploit.

	--[[ GATED ON THIS CLIENT'S OWN ROLE, from its own RoleAssigned. Never on a broadcast...
		 This gate is UX and rate-limit courtesy, NOT security ]]                   -- :41-48
	if UIController.GetMyRole() ~= Enums.Role.Aswang then
		return Enum.ContextActionResult.Pass
	end
-- IMPORTANT — THE ONE THING THIS PLAN MUST NOT COPY. Both existing handlers gate on the local role and
-- are right to: transform and kill are the Aswang's alone. A task is something all eight players do, so
-- a role gate on the task bind would make the Aswang's client behave observably differently from a
-- survivor's — a different send rate, or none at all — which is a confession on a stream and a
-- distinguishable client to anyone who can watch one. Step 5.2's header states the rule and Step 5.3
-- checks the whole client path against it.

	--[[ THE CLIENT PICKS THE TARGET, AND THAT IS NOT A SECURITY DECISION. ... the server then
		 re-derives distance, line of sight, phase, both roles ... A compromised client can send any
		 UserId it likes and gains exactly nothing ]]                               -- :76-95
-- NOTE the shape, and note that Step 4.1 does not need it. RequestKill must accept a target because
-- §4.3 says so; RequestTaskProgress accepts nothing, because Config pins that at most one task point
-- can be in range. Strictly less client input, and it was available only because of that invariant.
-- NOTE also "the server answers every refusal with silence" — the rule TaskProgressVerdict inherits.

-- ── UIController.luau ─────────────────────────────────────────────────────────
--[[ THIS CONTROLLER HOLDS THE ONLY COPY OF THE ROLE THAT EXISTS ON ANY CLIENT ... `myRole` is a module
	 local. It is never written to an attribute, a StringValue, the character, or anything under
	 ReplicatedStorage or Workspace — all of which replicate. ]]
-- IMPORTANT: TaskController must never read GetMyRole(). It has no reason to, and Step 5.3's table
-- lists the four tempting ways it might. The third — caching TasksCompleted and comparing it against a
-- locally predicted value — is the dangerous one, because it defeats C12 before C12 is written and no
-- check in this repo would see it.
