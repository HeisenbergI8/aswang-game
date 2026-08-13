--!strict
--[[
	Which task point is the player at? C08's resolver, and the soft-lock it was rewritten to remove.

	THE OVERLAP CASES ARE THE POINT OF THIS FILE. The old resolver returned the first in-range point in
	table order and relied on a Config relation to guarantee that only one point could ever be in range.
	That guarantee was never real — `TaskSelection`'s fallback drops spacing rather than short a round —
	and the result was an unwinnable 4/5 that produced no error, no warning and no client feedback.

	So the overlap is enumerated here rather than assumed away: both orderings of the same two points,
	the completed-nearest case, the all-complete case, and an exact tie. Table order must decide
	nothing, which is a property a single example cannot establish and a reversal can.
]]

local TaskResolve = require("../src/server/pure/TaskResolve")

local RANGE = 9

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function at(x: number): TaskResolve.Vec3
	return { X = x, Y = 0, Z = 0 }
end

local function point(id: string, x: number, completed: boolean): TaskResolve.Point
	return { Id = id, Position = at(x), Completed = completed }
end

local ORIGIN = at(0)

-- Nothing anywhere near.
local none, noneInRange = TaskResolve.at({ point("A", 100, false) }, ORIGIN, RANGE)

check("a distant point does not resolve", none == nil, tostring(none))
check("and reports nothing in range", not noneInRange)

-- The ordinary case.
local one, oneInRange = TaskResolve.at({ point("A", 3, false) }, ORIGIN, RANGE)

check("a single in-range point resolves", one == "A", tostring(one))
check("and reports something in range", oneInRange)

-- The boundary: exactly at `range` is in, one stud beyond is out.
local edge = TaskResolve.at({ point("A", RANGE, false) }, ORIGIN, RANGE)
local past = TaskResolve.at({ point("A", RANGE + 1, false) }, ORIGIN, RANGE)

check("a point exactly at the range limit is in range", edge == "A", tostring(edge))
check("a point past the limit is not", past == nil, tostring(past))

--[[
	THE SOFT-LOCK, IN BOTH TABLE ORDERS.

	A completed point at 2 studs and an incomplete one at 5. The old resolver returned whichever came
	first, so in one of these two orderings the player was refused ALREADY_COMPLETE while standing on a
	perfectly good task. Reversing the list is what proves table order no longer decides.
]]
local nearDone = point("A", 2, true)
local farOpen = point("B", 5, false)

local forward, forwardInRange = TaskResolve.at({ nearDone, farOpen }, ORIGIN, RANGE)
local reversed, reversedInRange = TaskResolve.at({ farOpen, nearDone }, ORIGIN, RANGE)

check(
	"a nearer COMPLETED point does not mask a further open one",
	forward == "B",
	tostring(forward)
)
check("and the same holds with the list reversed", reversed == "B", tostring(reversed))
check("table order does not change the answer", forward == reversed)
check("both report something in range", forwardInRange and reversedInRange)

-- Two open points: the nearer one wins, in either order.
local nearOpen = point("A", 2, false)
local farOpen2 = point("B", 5, false)

check("the nearest open point wins", TaskResolve.at({ nearOpen, farOpen2 }, ORIGIN, RANGE) == "A")
check("in either order", TaskResolve.at({ farOpen2, nearOpen }, ORIGIN, RANGE) == "A")

--[[
	EVERYTHING IN RANGE IS FINISHED. This is the case `anyInRange` exists for: the caller must be able
	to log ALREADY_COMPLETE rather than NO_TASK_IN_RANGE, while telling the client neither.
]]
local allDone, allDoneInRange =
	TaskResolve.at({ point("A", 2, true), point("B", 5, true) }, ORIGIN, RANGE)

check("no open point resolves when all in range are complete", allDone == nil, tostring(allDone))
check("but something WAS in range", allDoneInRange)

-- A completed point in range and an open point out of range: still nothing to do, still in range.
local mixed, mixedInRange =
	TaskResolve.at({ point("A", 2, true), point("B", 50, false) }, ORIGIN, RANGE)

check("an out-of-range open point does not rescue it", mixed == nil, tostring(mixed))
check("and the completed one still counts as in range", mixedInRange)

--[[
	AN EXACT TIE. Two open points equidistant on opposite sides. Without a tiebreak, table order decides
	— which is the property this whole rewrite removes, so it must not creep back in at equal distance.
]]
local tieForward = TaskResolve.at({ point("B", 4, false), point("A", -4, false) }, ORIGIN, RANGE)
local tieReversed = TaskResolve.at({ point("A", -4, false), point("B", 4, false) }, ORIGIN, RANGE)

check(
	"an exact tie is broken deterministically",
	tieForward == tieReversed,
	`{tieForward} vs {tieReversed}`
)
check("and it is broken toward the lower Id", tieForward == "A", tostring(tieForward))

-- An empty round (no tasks drawn yet, or all torn down) resolves to nothing rather than erroring.
local empty, emptyInRange = TaskResolve.at({}, ORIGIN, RANGE)

check("an empty point list resolves to nothing", empty == nil)
check("and reports nothing in range", not emptyInRange)

-- A zero range admits only a point you are standing exactly on.
check(
	"a zero range still admits an exact overlap",
	TaskResolve.at({ point("A", 0, false) }, ORIGIN, 0) == "A"
)
check("but nothing beside it", TaskResolve.at({ point("A", 1, false) }, ORIGIN, 0) == nil)

--[[
	THE NON-FINITE ROW OF THE DOMAIN, enumerated rather than argued about.

	An exploit audit proved that the original `d > range` guard let a NaN distance fall THROUGH: every
	comparison against NaN is false, so the point was counted as in range, failed both distance tests,
	and left the caller logging ALREADY_COMPLETE for a player standing nowhere. `anyInRange` was set
	from nothing.

	Whether a client can actually replicate a NaN HumanoidRootPart position is unproven — Roblox
	generally rejects it. That is exactly why it belongs in the grid instead of in a comment claiming
	it cannot happen: the cost of the cells is nothing, and this repo's own history is four reactive
	patches to a clock guard that a single NaN-and-infinities grid would have closed in one pass.

	Both infinities are here for the same reason. +inf must be out of range; -inf must not sneak in
	under `d <= range` and win the nearest test with a distance no real point can beat.
]]
local NAN = 0 / 0
local INF = math.huge

check("NaN is genuinely NaN in this runtime", NAN ~= NAN)

local nanId, nanInRange = TaskResolve.at({ point("A", NAN, false) }, ORIGIN, RANGE)

check("a NaN position resolves to nothing", nanId == nil, tostring(nanId))
check("and is NOT counted as in range", not nanInRange)

-- A NaN point must not poison a perfectly good one sitting beside it.
local nanMixed, nanMixedInRange =
	TaskResolve.at({ point("A", NAN, false), point("B", 3, false) }, ORIGIN, RANGE)

check("a NaN point does not mask a real one", nanMixed == "B", tostring(nanMixed))
check("and the real one still reports in range", nanMixedInRange)

local posInf, posInfInRange = TaskResolve.at({ point("A", INF, false) }, ORIGIN, RANGE)

check("a +inf position is out of range", posInf == nil, tostring(posInf))
check("and reports nothing in range", not posInfInRange)

local negInf, negInfInRange = TaskResolve.at({ point("A", -INF, false) }, ORIGIN, RANGE)

check("a -inf position is out of range too", negInf == nil, tostring(negInf))
check("and reports nothing in range", not negInfInRange)

-- An infinite RANGE is not a real config, but it must not make NaN admissible either.
local nanUnbounded = TaskResolve.at({ point("A", NAN, false) }, ORIGIN, INF)

check("NaN stays out even when the range is infinite", nanUnbounded == nil, tostring(nanUnbounded))

-- A NaN player position is the reachable half of this, if it is reachable at all.
local nanPlayer, nanPlayerInRange = TaskResolve.at(
	{ point("A", 3, false) },
	{ X = NAN, Y = 0, Z = 0 },
	RANGE
)

check("a NaN PLAYER position resolves to nothing", nanPlayer == nil, tostring(nanPlayer))
check("and is not counted as in range", not nanPlayerInRange)

if failures > 0 then
	error(`{failures} task-resolve assertion(s) failed`, 0)
end

print("  PASS  task-resolve: 33 assertions — overlap in both orders, NaN and both infinities")
