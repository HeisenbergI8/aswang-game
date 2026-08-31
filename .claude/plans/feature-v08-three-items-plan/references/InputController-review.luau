--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau. Phase 5 Step 5.3 only.

	The client's whole job here is routing a keypress to a remote. It decides nothing today and must
	decide nothing after V08 — the file already argues that at length, and the drop key inherits the
	argument verbatim.

	Cited against the file as read on 2026-08-29.
]]

-- src/client/Controllers/InputController.luau:46
local THROW_ACTION = "SaltThrow"
-- NOTE: a ContextActionService action name, not a module reference — it does NOT need renaming when
-- pure/SaltThrow becomes pure/ItemThrow, and renaming it would change the touch button's identity for
-- no reason. Leave it. The drop gets a sibling, `DROP_ACTION = "ItemDrop"`.

-- src/client/Controllers/InputController.luau:256-262
--[[
	... `carried` and refuses with NO_POUCH; a client-side check here would be a second copy of a rule
	and the two would disagree the first time a pickup and a throw crossed on the wire.
]]
-- IMPORTANT: THE ARGUMENT THE DROP KEY INHERITS WORD FOR WORD. No `if carried == nil then return end`
-- guard in the drop handler. Config.Items.CarryLimit is 1, the server already knows what this player
-- holds, and pure/ItemDrop on the server owns whether they may put it down.
-- NOTE: `NO_POUCH` in this comment becomes `ITEM_NO_ITEM` at V08. A comment naming a verdict that no
-- longer exists sends the next reader looking for it.

-- src/client/Controllers/InputController.luau:268-286
--[[
	C22. IN A TRIAL, Q FIRES THE TRIAL'S THROW INSTEAD.

	Both remotes take a direction and nothing else, and both resolve through the same
	`SaltThrow.inCone` on the server — so this is a routing decision, not two mechanics. The player
	presses the same key and learns the same aim.

	It has to be routed because `ItemService` resolves against the ROUND phase, which is IDLE during a
	trial: sending the real remote there gets a silent WRONG_PHASE and the tutorial teaches an action
	the player is refused. Asking `TrialController` rather than tracking a second flag here keeps one
	piece of state; the server re-checks the session either way, so a client that picks wrongly gets a
	refusal rather than an advantage.
]]
if TrialController.IsActive() then
	Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
else
	Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
end
-- IMPORTANT: THE ROUTE STAYS EXACTLY AS IT IS. V08 does not merge the two remotes, does not relax
-- ItemService's phase gate, and does not make the trial go through the slot — the trial's pouch is a
-- scripted prop outside the container system (Config.Items.TrialPickupRangeStuds).
-- IMPORTANT: "the server re-checks the session either way, so a client that picks wrongly gets a
-- refusal rather than an advantage" is the property that makes a CLIENT-SIDE ROUTE acceptable here.
-- The drop key has no equivalent routing question — there is no trial drop — so it fires one remote
-- unconditionally.
-- NOTE: `SaltThrow.inCone` in this comment becomes `ItemThrow.inCone`. Step 1.3 or 5.3, but do it.

-- src/client/Controllers/InputController.luau:288-292
-- The HUD's salt estimate lives in UIController and is decremented HERE, at the keypress, because
-- `SaltEffect` names nobody and cannot attribute a throw. Optimistic: the server may refuse this
-- (no pouch, wrong phase), in which case the display is briefly one low and self-corrects on the next
-- pickup. It is prefixed `~` on screen for exactly that reason.
UIController.NoteThrow()
-- IMPORTANT: DELETED. `NoteThrow` goes with UIController's estimate in Step 5.2, and a stale call
-- here is an analyze error — which is the good outcome. The HUD now updates from the next snapshot,
-- at most Config.Round.SnapshotInterval (0.5s) away.
-- NOTE: "SaltEffect names nobody and cannot attribute a throw" is still true and is still correct
-- design — the burst is a thing that happens at a place, not to a person. The immediate feedback the
-- optimistic decrement was buying is already provided by that burst, which the thrower's own client
-- renders with everyone else's.

-- src/client/Controllers/InputController.luau:444-450
--[[
	... why `Config.Salt.ThrowConeDegrees` exists rather than a raycast.
]]
-- NOTE: a fourth `Config.Salt` mention, in a comment. Re-point to `Config.Items.ThrowConeDegrees`
-- when the table dies in Step 5.2. Grep this file for `Config.Salt` before declaring the step done —
-- comments are the readers most easily missed, and a comment naming a deleted table is worse than
-- none because it reads as current.

-- THE NEW ACTION
-- IMPORTANT: MOBILE GETS A BUTTON, NOT A KEY. §5 puts ~60% of players on a phone, and
-- ContextActionService's touch button is how the throw already reaches them. The drop is the same
-- kind of deliberate, rare press. Thumb-zone placement is the `ui-polish` skill's question and is
-- explicitly NOT decided in this plan.
-- IMPORTANT: the drop fires with NO ARGUMENT. Not the item, not a position, not a target. See
-- Remotes.luau's declaration for why each of those would be an exploit surface on the one item that
-- is the win condition.
