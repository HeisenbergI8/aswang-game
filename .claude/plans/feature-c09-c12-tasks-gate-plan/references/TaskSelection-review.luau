--!strict
--[[
	REVIEW — src/shared/pure/TaskSelection.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 160 lines.

	Unmodified, and called a SECOND time per round by Phase 7 to draw the Aswang's decoy list. That
	second call is the only new use in the plan and it needs three of this file's properties to hold.
]]

-- src/shared/pure/TaskSelection.luau:95-101
function TaskSelection.select(
	pool: { Point },
	count: number,
	minSpacing: number,
	nextFloat: () -> number
): ({ Point }, boolean)
-- NOTE: returns (chosen, spacingRespected). Phase 7 discards the second value deliberately —
-- `selectForRound` has already warned about an unspaced draw this round, and a decoy that is not
-- spread is still a decoy. Discarding it is written as `local decoy = TaskSelection.select(...)`,
-- which is valid Luau and drops the extra return.

-- src/shared/pure/TaskSelection.luau:102-109
	local shuffled = table.clone(pool)
	for i = #shuffled, 2, -1 do
		local j = math.floor(nextFloat() * i) + 1
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
-- IMPORTANT FOR PHASE 7: the decoy draw MUST pass TaskService's existing `nextFloat`, which closes
-- over the ONE module-local `Random.new()` (TaskService:76, no argument). Consequences, both wanted:
--   · the decoy consumes from the same stream, so it is server-entropy-seeded like the real draw
--   · it ADVANCES that stream, so the real draw of round N+1 is not a function of round N's
-- A fresh `Random.new()` would be harmless; `Random.new(roundNumber)` or `Random.new(os.time())`
-- would be fatal, and both are named as such in TaskService's header. The seed is the part to get
-- right, and Phase 7 is the first code to touch the stream since C07.

-- src/shared/pure/TaskSelection.luau:110-125
	local chosen: { Point } = {}
	for _, point in shuffled do
		if #chosen >= count then break end
		if respectsSpacing(chosen, point, minSpacing) then
			table.insert(chosen, point)
		else
			table.insert(skipped, point)
		end
	end
-- NOTE: the decoy is drawn from the SAME twelve-point pool as the real five and is NOT made disjoint
-- from them. That is deliberate in the plan: a decoy guaranteed never to overlap the real set is a
-- decoy an Aswang can partially INVERT by elimination — every point on its list is provably not a
-- real task, which is information the real list does not give a survivor.
-- IMPORTANT: because both draws are independent shuffles of the same pool, the decoy CAN overlap the
-- real five by chance. That is correct and should not be "fixed".

-- src/shared/pure/TaskSelection.luau:88-94 + :126-140 (the fallback)
-- "THE FALLBACK IS NOT OPTIONAL. If spacing cannot be satisfied [...] the second pass takes whatever
--  is left, in the shuffled order, ignoring spacing. Returning fewer than `count` points would open
--  the escape gate at 3/5 forever."
-- IMPORTANT — this is fact #5 of the plan's brief and it binds C09-C12 twice:
--   1. NO new code may assume selected points are spaced. Phase 4's furthest-unused source pairing is
--      a preference, not a guarantee; Step 3.2's timing resolution goes through `taskPointAt`, which
--      handles overlap by nearest-incomplete.
--   2. Fewer points ARE returned when the POOL is genuinely smaller — which is the case Phase 7's
--      `TaskListView` pads for. A decoy of four against a real five is a role oracle measurable with
--      `#`, and this is the only path that produces one.
-- NOTE: the second return value exists because "an exploit audit measured what this silence cost:
-- twelve points in one 30x30 room produced a spacing violation in 2000 of 2000 draws."

-- src/shared/pure/TaskSelection.luau (module placement)
-- IMPORTANT: this lives under `src/shared/pure/`, so a LocalScript can require AND CALL it. CLAUDE.md
-- is explicit that this is safe because logic is not secret — inputs and seeds are. Phase 7 does not
-- change that calculus: publishing the decoy ALGORITHM costs nothing, because a client that
-- reimplements it perfectly still cannot predict the stream position. What would be fatal is sending
-- the pool ordering or the seed, and Phase 7 sends neither — only five resolved Ids.
return nil
