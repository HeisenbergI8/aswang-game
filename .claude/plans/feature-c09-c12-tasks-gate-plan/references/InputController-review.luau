--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 201 lines.

	Phase 3 adds one bind. Phase 7 corrects one comment. The comment matters more than the bind.
]]

-- src/client/Controllers/InputController.luau:152-168
--[[
	THE TWO BINDS ABOVE GATE ON UIController.GetMyRole(). THIS ONE MUST NOT, AND THE ABSENCE IS THE
	SECURITY PROPERTY.

	A role gate here would be a client that behaves differently depending on who it is, and every one
	of those is a confession waiting to be recorded. [...] an Aswang whose client sent no heartbeat —
	or sent one at a different rate, or stopped when the bar stopped — would be distinguishable from a
	survivor's by anyone who could watch the wire.

	SO: THE ASWANG'S CLIENT SENDS EXACTLY WHAT A SURVIVOR'S SENDS. C12 makes the server value it at
	zero. [...]
]]
-- IMPORTANT — THE LAST SENTENCE IS FACTUALLY WRONG SINCE AMENDMENT A2, and it is wrong in the most
-- expensive possible place: on the file where a role gate is easiest to add, in a comment that reads
-- as a design decision already made. C12 does the OPPOSITE — the Aswang's hold counts in full.
-- Step 7.4 rewrites it. NOTE: everything ABOVE that sentence stays; the argument for no role gate is
-- correct and is now stronger, because under A2 there is not even a server-side difference to hide.

-- src/client/Controllers/InputController.luau:170-187
local function onTaskAction(_actionName: string, inputState: Enum.UserInputState)
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
-- The template Phase 3's `onTimingAction` copies, with one difference: the timing stop is a DISCRETE
-- press, so it handles `Begin` only and needs no Cancel branch.
-- NOTE: "Cancel is handled alongside End: ContextActionService raises it when a bind is unbound or
-- the input is interrupted, and treating it as Pass would leave `holding` true forever." That hazard
-- does not exist for a stateless press — worth knowing so the omission reads as deliberate.

-- src/client/Controllers/InputController.luau:191-199
function InputController.Start()
	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
	ContextActionService:BindAction(TASK_ACTION, onTaskAction, false, Enum.KeyCode.E)
end
-- Phase 3 adds `Enum.KeyCode.R` for the timing stop.
-- IMPORTANT — THE PLAN'S #1 UNRESOLVED RISK, and this file is where C08's equivalent bug lived. The
-- comment on :194 says `E` was chosen "because it is ProximityPrompt's default key, so Phase 6 is a
-- swap rather than a retraining" — and that default is exactly what SWALLOWED this bind and shipped
-- C08 unreachable by humans. See `artifacts/keyboard-swallow-bug-and-fix.md`: 90 seconds of a held
-- `E` on a live pad produced ZERO console output of any kind, not even a refusal.
-- QUESTION: is `R` claimed by any CoreScript, or by any prompt this plan adds? `attachPrompt` sets
-- `KeyboardKeyCode = Enum.KeyCode.None`, which removes the known collision — but "the known one" is
-- the whole of what can be established without pressing the key. The failure mode is silence, so a
-- playtest that does not explicitly test `R` will report success either way.
-- NOTE: taking `R` also means C14's salt throw (`RequestThrowSalt`) needs a different key. Nothing
-- in the tree reserves keys, so this is the second claim in a namespace with no registry.

-- src/client/Controllers/InputController.luau:11-13 (header)
-- "NEITHER BIND CREATES A TOUCH BUTTON. `createTouchButton` is false on both, so mobile — 60% of the
--  audience, per §5 — cannot transform or kill yet."
-- NOTE: Phase 3's bind makes this THREE, and the plan says so rather than quietly matching the
-- existing pattern. It is worse here than for transform and kill, because tasks are what all eight
-- players do all round. C27 owns it; the hole should be counted, not rediscovered.

-- src/client/Controllers/InputController.luau:78-94
-- "THE CLIENT PICKS THE TARGET, AND THAT IS NOT A SECURITY DECISION. [...] the server then re-derives
--  distance, line of sight, phase, both roles, both player states, the transform state and the
--  cooldown from ITS own state before committing anything."
-- NOTE: the precedent for what a client bind is ALLOWED to compute. Phase 3's timing bind computes
-- strictly less — nothing at all. It fires unconditionally on Begin, with no local check of whether
-- the player is at a TIMING point, because running one would require the client to know which of the
-- five points are TIMING. The honest cost of not checking is one rate-limit token.
return nil
