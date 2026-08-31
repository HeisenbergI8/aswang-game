--!strict
--[[
	REVIEW — src/client/Controllers/InputController.luau (modified in the working tree at time of
	reading; line numbers are from that state)

	V09 adds one branch. It adds no key and no touch button.
]]

-- src/client/Controllers/InputController.luau:18-24
-- Why the key list is not V09's to grow.
--
-- IMPORTANT: every verb here is registered with `UIController.BindActions` and drawn by C27's touch
-- layer, so a new `ContextActionService` action is a new thumb button on a phone — and §5 puts ~60%
-- of players there. `Q` already means "use the thing in my hand", which is exactly what placing
-- bawang is.
--[[
	Every verb here is registered with `UIController.BindActions` and drawn by C27's touch
]]

-- src/client/Controllers/InputController.luau:286-303
-- THE ROUTING DECISION V09 ADDS A THIRD ARM TO, AND ITS OWN JUSTIFICATION IS THE ONE TO REUSE.
--
-- IMPORTANT: "this is a routing decision, not two mechanics. The player presses the same key and
-- learns the same aim." And the closing sentence is the security argument V09's branch inherits
-- verbatim: "the server re-checks the session either way, so a client that picks wrongly gets a
-- refusal rather than an advantage."
--
-- IMPORTANT: the trial branch must stay FIRST. A trial runs at IDLE, and `pure/GarlicPlacement`
-- refuses a non-ACTIVE phase — so a bawang branch placed above the trial check would swallow the
-- trial's throw and teach the player an action the server refuses, which is the exact bug the trial
-- remote was created to avoid.
if TrialController.IsActive() then
	Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
else
	Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
end

-- src/client/Controllers/InputController.luau:305-312
-- The HUD's source of truth for what the player is holding.
--
-- IMPORTANT: "The HUD now reads `ClientRoundSnapshot.YourCarriedItem`, which the server owns — so the
-- display updates from the next snapshot, at most `Config.Round.SnapshotInterval` away." That is what
-- V09's branch reads to decide which remote to fire, and the staleness is why the decision must not
-- be authoritative: half a second of a wrong guess costs a refusal, not an item.
--
-- QUESTION: the accessor's NAME was not confirmed. If `UIController` keeps the value private, the
-- smaller change is for this controller to hold the last snapshot's `YourCarriedItem` itself rather
-- than widening `UIController`'s surface for one branch. Confirm before writing the line.
--
-- NOTE: V08 deleted an optimistic client-side decrement here and the reasoning applies to V09 too —
-- do not add a local "I placed it" assumption. The slot is the server's.
--[[
	V08 DELETED THE OPTIMISTIC DECREMENT WITH THE ESTIMATE IT CORRECTED.
]]

-- src/client/Controllers/InputController.luau:318-326
-- The drop verb, and the pattern a placement fire should look like.
--
-- NOTE: argument-free, one line, with the reasoning deferred to `Remotes.luau`. `RequestPlaceGarlic`
-- is the same shape and should not accumulate a direction on the way past — the camera's `LookVector`
-- is read one branch above and a placement has no aim.
local function performDrop(): boolean
	Remotes.Get("RequestDropItem"):FireServer()

	return true
end

-- src/client/Controllers/InputController.luau:504-529
-- The bindings, for completeness: Q throw, E search, X drop, T transform, F kill, C camouflage,
-- G smoke.
--
-- IMPORTANT: V09 binds NOTHING new. If a later chunk wants a dedicated place key, the free letters
-- and the thumb-zone cost are `ui-polish`'s problem, not this chunk's.
ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q)
