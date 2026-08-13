--!strict
-- REVIEW: src/shared/pure/TaskSelection.luau:1-140 (excerpts)
--
-- The pure half of C07, already built and proven over 10,000 draws. UNCHANGED by this plan. Read for
-- its call signature, its Vec3 shape, and the seed argument that constrains everything around it.

	--[[
	  · This file lives in src/shared/, which replicates. A client can require it AND call it.
	  · A `seed` parameter would put a reproducible generator on that side of the wire.
	]]
-- IMPORTANT: this is why the plan puts BOTH new pure modules under src/server/pure/ instead. Nothing
-- about TaskPool or TaskProgress needs this argument re-run, and re-running it is the cost of putting
-- a module under shared/ by default. Recorded as a written decision in TaskPool's header (Step 1.2).

export type Vec3 = { X: number, Y: number, Z: number }
-- NOTE: plain table, no Vector3, so Lune can run the module. Step 2.3 converts at the call site with a
-- `toVec` helper that mirrors MonsterService's `vec` exactly (MonsterService.luau:525). The plan does
-- not introduce a new conversion pattern; it copies the one that exists.

export type Point = {
	Id: string,
	Position: Vec3?,
}
-- IMPORTANT: `Id` is a string and the plan makes it the anchor part's Name. That is what forces the
-- map contract "every TaskPoint must have a unique Name", and it is what TaskPool's DUPLICATE_ID
-- verdict exists to police. Position is optional and the plan always supplies it — the greybox has
-- positions and the rig does too — but the optionality is why a pool discovered before C17 still draws.

function TaskSelection.select(
	pool: { Point },
	count: number,
	minSpacing: number,
	nextFloat: () -> number
): { Point }
-- The exact call Step 2.3 makes. NOTE all three numbers come from Config (TotalRequired, PoolSize is
-- not passed, MinSpacingStuds) — `npm run check:config` is that step's gate precisely because
-- `select(pool, 5, 20, nextFloat)` is the tempting version.

	--[[
		THE FALLBACK IS NOT OPTIONAL. If spacing cannot be satisfied ... the second pass takes whatever
		is left, in the shuffled order, ignoring spacing. Returning fewer than `count` points would open
		the escape gate at 3/5 forever ... Fewer points is only ever returned when the POOL is
		genuinely smaller.
	]]
-- IMPORTANT, and it is what lets Step 2.1's rig be a clean 30-stud grid. The spacing REJECTION path
-- and its fallback are already proven purely — tests/task-selection.test.luau:169-180 draws from twelve
-- points stacked in one room — so the in-game rig does not need to reproduce them, and a rig that did
-- would make every other observation in the Studio session harder to read.
--
-- NOTE the second half: `select` returning fewer than `count` means the POOL was short. Step 2.3's
-- post-draw warn ("drew N of 5") is therefore reporting a map defect, never an algorithm one, which is
-- why its message points at the map.
