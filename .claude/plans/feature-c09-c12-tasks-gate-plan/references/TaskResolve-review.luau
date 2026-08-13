--!strict
--[[
	REVIEW — src/server/pure/TaskResolve.luau
	Read 2026-08-12 for the C09-C12 plan, and RE-READ after the tree changed mid-plan.

	Reused unchanged by this plan, in two places that matter: Step 3.2's `evaluateTimingStop` resolves
	its task through `taskPointAt`, which is this module, and Phase 4's fetch DESTINATION check
	deliberately does NOT use it (see below).
]]

-- src/server/pure/TaskResolve.luau:60-84
function TaskResolve.at(points: { Point }, position: Vec3, range: number): (string?, boolean)
	for _, point in points do
		local d = distance(point.Position, position)

		-- CHANGED SINCE THIS PLAN WAS DRAFTED. Was `if d > range then continue end`.
		if not (d <= range) then
			continue
		end

		anyInRange = true

		if point.Completed then
			continue
		end
	end
end
-- IMPORTANT: `not (d <= range)`, NOT `d > range`, and the difference is NaN. Every comparison against
-- NaN is false, so `d > range` let a NaN distance fall THROUGH the guard — past it the point set
-- `anyInRange`, failed both distance tests, and the caller logged ALREADY_COMPLETE for a player
-- standing nowhere near anything. Inverting makes the guard total.
-- NOTE: the header calls this "a guard against a state that may be unreachable rather than a fixed
-- bug" — a NaN distance needs a NaN character position, which Roblox generally refuses to replicate.
-- It costs one word and `tests/task-resolve.test.luau` enumerates NaN and both infinities rather than
-- trusting that reasoning. 33 assertions.

-- IMPORTANT FOR THIS PLAN, and it is a consistency obligation rather than an observation:
-- Phase 4's `tickFetch` writes TWO distance comparisons by hand, both in the `d <= range` direction:
--
--     if distance <= bestDistance then            -- the source pickup scan
--     ... .Magnitude <= Config.Tasks.PresenceRangeStuds   -- CarrierAtDestination
--
-- Both are already NaN-total by construction (a NaN fails `<=`, so the branch is not taken and the
-- candidate is skipped) — which is the SAFE direction and matches this module's fix. Phase 6's
-- `GateEscape.escapes` uses `request.Distance <= request.Range` for the same reason.
-- QUESTION for the implementer: keep them written as `<=` tests that must PASS to act, never as `>`
-- tests that must pass to skip. The two are equivalent for finite numbers and opposite for NaN, and
-- this module is the precedent for which one this repo picks.

-- src/server/pure/TaskResolve.luau:16-31 (header)
-- "The original resolved to the first in-range point in table order, resting on
--  `PresenceRangeStuds * 2 < MinSpacingStuds` to guarantee only one point could be in range. That
--  guarantee does not exist."
-- IMPORTANT: this is fact #5 in the plan's brief and it binds every new line of C09-C12. An audit
-- measured 2000/2000 draws violating spacing for twelve points in one 30x30 room. NOTHING added by
-- this plan may assume selected points are spaced — notably Phase 4's furthest-unused source pairing,
-- which is a preference and not a guarantee.
-- NOTE: verified LIVE since the plan was drafted —
-- `.claude/plans/feature-c07-map-c08-hold-plan/artifacts/delta-2-nearest-incomplete-overlap.md`
-- reproduced the soft-lock by forcing an overlap: a COMPLETED point at ~0 studs did not mask an
-- INCOMPLETE one at ~4. So the fix is engine-confirmed, not just Lune-confirmed.

-- src/server/pure/TaskResolve.luau:53-59
-- TIES GO TO THE LOWER Id [...] `<` alone would let table order decide it again
-- NOTE: worth copying the reasoning, not the code, into Phase 4's source-pickup scan. That scan
-- resolves "which player picks the item up" by nearest, and two players arriving in the same tick at
-- equal distance would otherwise be decided by `Players:GetPlayers()` order — the same class of
-- hash-order-decides-gameplay bug this module exists to delete. The plan says "nearest so that two
-- players arriving together resolve deterministically"; a distance tie still falls back to iteration
-- order there, which is a small, real, and acceptable-if-known gap.

-- src/server/pure/TaskResolve.luau:33-40 (the two return values)
-- `anyInRange` is returned separately so the caller can tell "nowhere near a task" from "everything
-- near you is already done" WITHOUT this module knowing what a verdict is.
-- NOTE: Step 3.2's `evaluateTimingStop` consumes both, mapping them to NO_TASK_IN_RANGE and
-- ALREADY_COMPLETE exactly as `evaluatePresence` does. That symmetry is deliberate and is the reason
-- the plan says the two validators must mirror each other line for line.
return nil
