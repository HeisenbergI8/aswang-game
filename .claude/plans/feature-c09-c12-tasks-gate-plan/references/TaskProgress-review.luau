--!strict
--[[
	REVIEW — src/server/pure/TaskProgress.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 97 lines.

	Unmodified by this plan and reused by three of its phases. Its own header predicted this:
	"THE SHAPE THE OTHER THREE TASK TYPES COPY. C09 and C10 differ in what produces a `weight` and in
	nothing else." That turned out to be exactly right for FETCH and TWO_PERSON, and NOT right for
	TIMING — see below, because that divergence is the one thing the header did not anticipate.
]]

-- src/server/pure/TaskProgress.luau:43-53
function TaskProgress.strongestWeight(weights: { number }): number
	local best = 0
	for _, weight in weights do
		if weight > best then
			best = weight
		end
	end
	return best
end
-- IMPORTANT: MAX, NOT SUM, and the reason survives A2. "A summed rate [...] makes the bar's speed a
-- function of HOW MANY people are contributing, which turns any per-player difference in weight into
-- arithmetic a bystander can read off a bar."
-- NOTE for Phase 5: a TWO_PERSON task therefore does NOT go faster with three people. The participant
-- count decides whether the rate is nonzero; the max decides what it is. §4.4 asks for "requires 2",
-- never "scales with N", and the plan states this consequence explicitly because it is the opposite
-- of what a reader expects from a task that counts people.

-- src/server/pure/TaskProgress.luau:69-96
function TaskProgress.tick(progress, elapsed, weight, holdTime): Result
	if current >= 1 then return { Progress = 1, Completed = true } end
	if weight <= 0 or elapsed <= 0 then return { Progress = current, Completed = false } end
	if holdTime <= 0 then return { Progress = 1, Completed = true } end
	local updated = math.clamp(current + (elapsed * weight) / holdTime, 0, 1)
	return { Progress = updated, Completed = updated >= 1 }
end
-- IMPORTANT — `weight <= 0` FREEZES, it does not decay: "progress belongs to the WORLD, not to the
-- player (§4.4 anti-frustration), so a survivor who dies at 90% leaves 90% for whoever arrives next."
-- Phase 5 relies on this DIRECTLY and it is why the plan zeroes the weight rather than skipping the
-- task: the second person walking away from a two-person task freezes the bar through this existing
-- guard, with no new code and no new decay rule.
-- NOTE: `holdTime` is a PARAMETER, which is what lets Phase 4's `durationFor` swap in
-- `FetchDeliverTime` and `TwoPersonTime` without touching this module at all.

-- IMPORTANT — WHERE THE HEADER'S PREDICTION BREAKS, AND PHASE 3 MUST HANDLE IT:
-- TIMING does NOT differ only in "what produces a weight". Its progress is a HIT COUNT, advanced by a
-- discrete event (`noteTimingStop`), not by elapsed time under a weight. So a TIMING task has two
-- possible progress sources, and if the tick's loop is allowed to run over it as well, standing still
-- completes it in `HoldTime` and the minigame is decoration.
-- Step 3.2 therefore adds a `continue` for TIMING in the progress loop. That `continue` is the single
-- most deletable line in the plan — it looks like an optimisation and is a mechanic.
-- NOTE: the failure would be quiet and plausible. `SetTasksCompleted` is clamped and idempotent, so
-- the symptom is "timing tasks finish themselves", not a crash or a bad count.

-- src/server/pure/TaskProgress.luau:22-27
-- "Under Amendment A2 the Aswang's weight is no longer one of those differences [...] So the max rule
--  is no longer the thing standing between this game and a role oracle; it stands between the game
--  and the NEXT such difference, and C15's ghosts are already one."
-- NOTE: this plan adds no new per-player weight difference. Every contributor is 1 (ALIVE) or 0.25
-- (GHOST, C15) or 0, from `TaskWeight`, unchanged. Phases 4 and 5 add REQUIREMENTS (must be the
-- carrier; must be two of you) rather than new rates, which is deliberately the cheaper axis: a
-- requirement gates the bar at zero or full, and a rate would be readable in the bar's speed.

-- src/server/pure/TaskProgress.luau:78-83
--   · elapsed <= 0  — os.clock() is not guaranteed monotonic across a server's lifetime
-- NOTE: Phase 2's `TimingWindow` inherits the same hazard from the same clock and handles it
-- differently — `%` is total over the reals, so a backwards jump produces a bar that SKIPS rather
-- than an error. Different failure, same root, and both are now written down.
return nil
