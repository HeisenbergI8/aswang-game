--!strict
--[[
	TaskSelection — which 5 of the 12 task points does this round use? (§4.4, C07)

		(pool, count, nextFloat) -> chosen

	§4.4's ONE LOAD-BEARING DECISION. "12 possible task locations exist on the map. Each round randomly
	picks 5. Players cannot memorise a route." Appendix C.4 names route memorisation as cause #2 of the
	competitor's death — 2.5M visits, $0 — and this is the fix that keeps one map fresh for dozens of
	plays at the cost of one function.

	THE RNG IS INJECTED, NEVER CREATED HERE. Same rule as RoleDraw, and here is why it applies to a
	module whose output is public within seconds anyway:

	  · This file lives in src/shared/, which replicates. A client can require it AND call it.
	  · A `seed` parameter would put a reproducible generator on that side of the wire. Guess the seed
	    and you know every task location before STARTING ends — enough for an Aswang to be standing at
	    one when the round begins.
	  · `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and both fatal.
	    TaskService seeds with `Random.new()` — no argument — at C17.

	The algorithm being public costs nothing. The stream being reproducible costs the round.

	NO `script.Parent` REQUIRES, and no Vector3: positions are plain { X, Y, Z } tables so Lune can run
	this. TaskService converts at the call site, exactly as MonsterService does for KillValidation.
]]

export type Vec3 = { X: number, Y: number, Z: number }

-- One candidate task location. `Position` is optional because C17's greybox is what puts positions on
-- these, and a pool without them must still draw correctly rather than erroring — see spacing below.
export type Point = {
	Id: string,
	Position: Vec3?,
}

local TaskSelection = {}

local function distanceSquared(a: Vec3, b: Vec3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z

	return dx * dx + dy * dy + dz * dz
end

--[[
	Would adding this point keep every selected pair at least `minSpacing` apart?

	A point with no Position never blocks and is never blocked. That is the graceful half of "spatially
	spread IF the pool carries positions": a pool discovered before C17 tags anything with a position
	still draws five distinct points, it just draws them without spacing.
]]
local function respectsSpacing(chosen: { Point }, candidate: Point, minSpacing: number): boolean
	local candidatePosition = candidate.Position

	if candidatePosition == nil or minSpacing <= 0 then
		return true
	end

	local floor = minSpacing * minSpacing

	for _, point in chosen do
		local position = point.Position

		if position ~= nil and distanceSquared(position, candidatePosition) < floor then
			return false
		end
	end

	return true
end

--[[
	A PARTIAL FISHER-YATES OVER A COPY, with a spacing filter layered on top.

	Fisher-Yates is the part that has to be right: it is uniform over the pool and it CANNOT produce a
	duplicate, because a drawn index is swapped out of the live range rather than being re-rolled. The
	obvious alternative — "pick a random index, retry if already taken" — is uniform too and unbounded
	in the worst case, which is a hang on a server rather than a wrong answer, and hangs are the failure
	mode this game can least afford inside STARTING.

	SPACING BIASES THE DISTRIBUTION AND THAT IS ACCEPTED. A point in a crowded corner of the map is
	drawn slightly less often than an isolated one, because it is more often rejected. §4.4 asks for
	spread and Appendix C.4 asks for unpredictability; perfect uniformity is neither of those things,
	and the test measures uniformity on a pool WITHOUT positions so it measures the shuffle rather than
	the filter.

	THE FALLBACK IS NOT OPTIONAL. If spacing cannot be satisfied — twelve points in one room, or a
	minSpacing tuned too high at M12 — the second pass takes whatever is left, in the shuffled order,
	ignoring spacing. Returning fewer than `count` points would open the escape gate at 3/5 forever
	(Config.Tasks.TotalRequired is what the gate counts), which is an unwinnable round produced by a
	balance number. Fewer points is only ever returned when the POOL is genuinely smaller.
]]
function TaskSelection.select(
	pool: { Point },
	count: number,
	minSpacing: number,
	nextFloat: () -> number
): ({ Point }, boolean)
	local shuffled = table.clone(pool)

	-- Fisher-Yates, back to front. nextFloat returns [0, 1), so the index is in [i, #shuffled].
	for i = #shuffled, 2, -1 do
		local j = math.floor(nextFloat() * i) + 1

		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local chosen: { Point } = {}
	local skipped: { Point } = {}

	for _, point in shuffled do
		if #chosen >= count then
			break
		end

		if respectsSpacing(chosen, point, minSpacing) then
			table.insert(chosen, point)
		else
			table.insert(skipped, point)
		end
	end

	--[[
		The fallback pass. Still in shuffled order, so it is still a random selection — just an unspaced
		one. Reached only when the pool cannot satisfy the spacing at all.

		IT REPORTS ITSELF NOW, AND THAT IS THE SECOND RETURN VALUE. An exploit audit measured what this
		silence cost: twelve points in one 30x30 room produced a spacing violation in 2000 of 2000
		draws, every one of them placing two selected points inside a single presence radius — while
		`Config.Tasks.MinSpacingStuds` and a passing `tests/config.test.luau` invariant both said the
		spread was guaranteed. It was never guaranteed; it was requested, and this loop is where the
		request quietly fails.

		`spacingRespected` is what lets TaskService say so out loud. It does NOT make the caller safe on
		its own — see `taskPointAt`, which was rewritten to resolve the NEAREST INCOMPLETE point so that
		two overlapping selections are merely untidy rather than an unwinnable round.
	]]
	--[[
		A non-empty `skipped` is NOT a violation on its own: the first pass may have filled `count`
		before running out of pool, in which case every chosen point is properly spaced and the skipped
		ones simply were not needed. Only an actual insertion below breaks the spread — and a point that
		was rejected earlier stays rejected, because `chosen` only ever grows.
	]]
	local spacingRespected = true

	for _, point in skipped do
		if #chosen >= count then
			break
		end

		table.insert(chosen, point)
		spacingRespected = false
	end

	return chosen, spacingRespected
end

return TaskSelection
