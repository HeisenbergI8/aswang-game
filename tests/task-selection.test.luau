--!strict
--[[
	The 5-of-12 draw, over 10,000 rounds.

	This is C07's stated Verify line: no duplicates, distribution within tolerance, graceful on a short
	pool. Ten thousand draws rather than a handful because the two failures that matter here are
	statistical — a shuffle that is subtly biased, and a duplicate that appears once in a thousand
	rounds. Both look perfect in a spot check and both are permanent once shipped.

	THE RNG IS THE TEST'S OWN. Lune has no Roblox `Random` class, and `math.randomseed` mutates global
	state that every other test in this directory would then inherit. A four-line LCG is deterministic,
	self-contained, and reproduces a failure exactly from the seed printed with it.
]]

local TaskSelection = require("../src/shared/pure/TaskSelection")

type Point = TaskSelection.Point

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- A textbook 32-bit LCG (Numerical Recipes constants). Its statistical quality does not need to be
-- good — it needs to be REPRODUCIBLE, so that a failing draw can be replayed from its seed.
local function lcg(seed: number): () -> number
	local stateValue = seed % 2147483647

	return function(): number
		stateValue = (1664525 * stateValue + 1013904223) % 4294967296

		return stateValue / 4294967296
	end
end

local POOL_SIZE = 12 -- Config.Tasks.PoolSize
local DRAW = 5 -- Config.Tasks.TotalRequired
local DRAWS = 10000

-- Twelve points on a wide grid, far enough apart that spacing never binds. Spacing gets its own pool.
local function spreadPool(): { Point }
	local pool: { Point } = {}

	for index = 1, POOL_SIZE do
		table.insert(pool, {
			Id = `T{index}`,
			Position = { X = index * 100, Y = 0, Z = 0 },
		})
	end

	return pool
end

-- The same twelve with no positions at all: this is what a pool looks like before C17 tags anything,
-- and it is the pool the uniformity assertion uses, because spacing biases distribution by design.
local function positionlessPool(): { Point }
	local pool: { Point } = {}

	for index = 1, POOL_SIZE do
		table.insert(pool, { Id = `T{index}` })
	end

	return pool
end

--------------------------------------------------------------------------------
-- 10,000 draws: no duplicates, ever; correct size; every Id from the pool
--------------------------------------------------------------------------------

local counts: { [string]: number } = {}
local duplicateSeed: number? = nil
local wrongSizeSeed: number? = nil

for seed = 1, DRAWS do
	local chosen = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(seed))

	if #chosen ~= DRAW then
		wrongSizeSeed = wrongSizeSeed or seed
	end

	local seen: { [string]: boolean } = {}

	for _, point in chosen do
		if seen[point.Id] then
			duplicateSeed = duplicateSeed or seed
		end

		seen[point.Id] = true
		counts[point.Id] = (counts[point.Id] or 0) + 1
	end
end

-- §4.4 and C07's Done line: "the same point never appears twice in one round".
check(
	`no duplicates across {DRAWS} draws`,
	duplicateSeed == nil,
	if duplicateSeed then `first at seed {duplicateSeed}` else nil
)

check(
	`every draw returns exactly {DRAW} points`,
	wrongSizeSeed == nil,
	if wrongSizeSeed then `first at seed {wrongSizeSeed}` else nil
)

--------------------------------------------------------------------------------
-- Distribution. Expected share is DRAW/POOL_SIZE of DRAWS ≈ 4166 appearances each.
--
-- ±10% is loose on purpose. A tighter band turns a correct shuffle into a flaky test the first time
-- the LCG's constants change; a looser one would not catch the bias this exists to catch, which is an
-- off-by-one in the Fisher-Yates range starving the first or last element.
--------------------------------------------------------------------------------

local expected = DRAWS * DRAW / POOL_SIZE
local tolerance = expected * 0.1

for index = 1, POOL_SIZE do
	local id = `T{index}`
	local seen = counts[id] or 0

	check(
		`{id} is drawn about as often as every other point`,
		math.abs(seen - expected) <= tolerance,
		`{seen} appearances, expected {expected} ± {tolerance}`
	)
end

--------------------------------------------------------------------------------
-- Spacing (§4.4 "spread"), and the fallback when it cannot be honoured
--------------------------------------------------------------------------------

local MIN_SPACING = 20 -- Config.Tasks.MinSpacingStuds

local spacingViolations = 0

for seed = 1, 1000 do
	local chosen = TaskSelection.select(spreadPool(), DRAW, MIN_SPACING, lcg(seed))

	for i = 1, #chosen do
		for j = i + 1, #chosen do
			local a = chosen[i].Position
			local b = chosen[j].Position

			if a ~= nil and b ~= nil then
				local dx = a.X - b.X
				local dy = a.Y - b.Y
				local dz = a.Z - b.Z

				if dx * dx + dy * dy + dz * dz < MIN_SPACING * MIN_SPACING then
					spacingViolations += 1
				end
			end
		end
	end
end

check(
	"no two selected points are closer than the minimum spacing",
	spacingViolations == 0,
	`{spacingViolations} pairs too close`
)

-- THE FALLBACK. Twelve points stacked in one room cannot satisfy any spacing at all, and the round
-- must still get five tasks — Config.Tasks.TotalRequired is what the escape gate counts, so returning
-- three would leave the gate shut forever and produce an unwinnable round from a balance number.
local crowded: { Point } = {}

for index = 1, POOL_SIZE do
	table.insert(crowded, { Id = `C{index}`, Position = { X = index, Y = 0, Z = 0 } })
end

local crowdedDraw = TaskSelection.select(crowded, DRAW, MIN_SPACING, lcg(7))
local crowdedSeen: { [string]: boolean } = {}
local crowdedDuplicate = false

for _, point in crowdedDraw do
	if crowdedSeen[point.Id] then
		crowdedDuplicate = true
	end

	crowdedSeen[point.Id] = true
end

check("an unspaceable pool still yields a full draw", #crowdedDraw == DRAW, `got {#crowdedDraw}`)
check("the fallback pass introduces no duplicates", not crowdedDuplicate)

--------------------------------------------------------------------------------
-- Degenerate pools. A live server that reaches one of these has a bigger problem than the draw, and
-- erroring inside enterStarting would leave the round stuck in STARTING with no log.
--------------------------------------------------------------------------------

local short = TaskSelection.select({ { Id = "A" }, { Id = "B" } }, DRAW, 0, lcg(1))

check("a pool smaller than the draw returns the whole pool", #short == 2, `got {#short}`)

check(
	"an empty pool returns nothing rather than erroring",
	#TaskSelection.select({}, DRAW, 0, lcg(1)) == 0
)

check(
	"a draw of zero returns nothing",
	#TaskSelection.select(positionlessPool(), 0, 0, lcg(1)) == 0
)

-- Reproducibility, which is what makes every assertion above replayable from its seed — and, on the
-- server, what makes an unseeded Random.new() the only thing standing between a client and the draw.
local first = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(42))
local second = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(42))
local identical = true

for index, point in first do
	if second[index].Id ~= point.Id then
		identical = false
	end
end

check("the same stream produces the same draw", identical)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print(
	`  PASS  task-selection: {DRAWS} draws, {checked} assertions over bands, spacing and edge cases`
)
