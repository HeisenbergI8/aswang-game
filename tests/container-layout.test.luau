--!strict
--[[
	tests/container-layout.test.luau

	V03's stated Verify line: 10,000 draws asserting every item placed exactly once, no container
	double-seeded, and a distribution across the pool that is not degenerate.

	THE LAST THIRD IS THE PART WORTH ARGUING ABOUT, because "not degenerate" is not a check. Two bands
	are asserted and they catch different failures:

	  · OCCUPANCY, any item, per container. Expected 10000 x 7/15 = 4666.7, sd 49.9. The band is +-5%
	    (+-233), which is +-4.68 sd. This catches every MARGINAL degeneracy: an off-by-one that never
	    picks container 1 or 15, a bias toward low indices, items only ever landing in the first seven.
	  · THE BUNTOT PAGI, per container. Expected 10000/15 = 666.7, sd 24.9, band +-15% (+-100), which is
	    +-4.01 sd. This catches a CORRELATION the first band cannot see: if the one item that decides
	    the round always landed beside a salt, the aggregate counts would stay flat while the layout
	    became predictable. There is one buntot pagi and §4.6 makes it the only thing that kills, so it
	    is the item worth watching on its own.

	THE GENERATOR IS HAND-ROLLED AND SEEDED, and that is deliberate rather than lazy. A band asserted
	over `math.random` is a band whose pass depends on the Lune build, and one that fails a run in
	twenty thousand is a flake that costs more attention than it catches. xorshift32 makes this
	hermetic, so a failure means the ALGORITHM changed — which is the only thing this file is for.
]]

local ContainerLayout = require("../src/server/pure/ContainerLayout")

local DRAWS = 10000
local CONTAINERS = 15
local COUNTS = { Salt = 4, Bawang = 2, BuntotPagi = 1 }
local ITEMS = COUNTS.Salt + COUNTS.Bawang + COUNTS.BuntotPagi

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

-- xorshift32. Period 2^32-1, and the modulo bias over a range of 15 is far below anything the bands
-- below could resolve.
local function generator(seed: number): (number, number) -> number
	local state = seed

	return function(lo: number, hi: number): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))

		return lo + state % (hi - lo + 1)
	end
end

local nextInt = generator(0x2A5C1D07)

--------------------------------------------------------------------------------
-- Exactness, on every single draw. One counter per failure MODE rather than a
-- check() per draw, so a broken algorithm reports once instead of 10,000 times.
--------------------------------------------------------------------------------

local occupancy: { number } = {}
local buntotPagi: { number } = {}

for index = 1, CONTAINERS do
	occupancy[index] = 0
	buntotPagi[index] = 0
end

local wrongPlaced = 0
local wrongMultiset = 0
local outOfRange = 0

for _ = 1, DRAWS do
	local layout = ContainerLayout.draw(CONTAINERS, COUNTS, nextInt)
	local tally: { [string]: number } = { SALT = 0, BAWANG = 0, BUNTOT_PAGI = 0 }
	local occupied = 0

	for containerIndex, id in layout.Contents do
		occupied += 1

		if containerIndex < 1 or containerIndex > CONTAINERS or containerIndex % 1 ~= 0 then
			outOfRange += 1
			continue
		end

		occupancy[containerIndex] += 1
		tally[id] = (tally[id] or 0) + 1

		if id == "BUNTOT_PAGI" then
			buntotPagi[containerIndex] += 1
		end
	end

	-- `Contents` is keyed BY container index, so a count of 7 distinct keys IS "no container was
	-- double-seeded". A second write to one index would leave 6 keys, not 7.
	if occupied ~= ITEMS or layout.Placed ~= ITEMS then
		wrongPlaced += 1
	end

	if
		tally.SALT ~= COUNTS.Salt
		or tally.BAWANG ~= COUNTS.Bawang
		or tally.BUNTOT_PAGI ~= COUNTS.BuntotPagi
	then
		wrongMultiset += 1
	end
end

check(
	`all {DRAWS} draws fill exactly {ITEMS} distinct containers — no container double-seeded`,
	wrongPlaced == 0,
	`{wrongPlaced} draw(s) did not`
)

check(
	"every item is placed exactly once, every draw",
	wrongMultiset == 0,
	`{wrongMultiset} draw(s) had the wrong item multiset`
)

check(
	"no container index outside 1..CONTAINERS was ever written",
	outOfRange == 0,
	`{outOfRange} did`
)

--------------------------------------------------------------------------------
-- Distribution. The thresholds and their derivation are in the header.
--------------------------------------------------------------------------------

local expectedOccupancy = DRAWS * ITEMS / CONTAINERS
local occupancyBand = expectedOccupancy * 0.05
local expectedPagi = DRAWS / CONTAINERS
local pagiBand = expectedPagi * 0.15

local occupancyStrays: { string } = {}
local pagiStrays: { string } = {}

for index = 1, CONTAINERS do
	if math.abs(occupancy[index] - expectedOccupancy) > occupancyBand then
		table.insert(occupancyStrays, `#{index}={occupancy[index]}`)
	end

	if math.abs(buntotPagi[index] - expectedPagi) > pagiBand then
		table.insert(pagiStrays, `#{index}={buntotPagi[index]}`)
	end
end

check(
	`every container is hit {math.floor(expectedOccupancy)} +- 5% times across {DRAWS} draws`,
	#occupancyStrays == 0,
	`outside the band: {table.concat(occupancyStrays, ", ")}`
)

check(
	`the buntot pagi lands in every container {math.floor(expectedPagi)} +- 15% times`,
	#pagiStrays == 0,
	`outside the band: {table.concat(pagiStrays, ", ")}`
)

--------------------------------------------------------------------------------
-- The SHORT map. A greybox barrio with three containers must still be playable,
-- and WHICH three items survive is the difference between thin and unwinnable.
--------------------------------------------------------------------------------

local short = ContainerLayout.draw(3, COUNTS, nextInt)
local shortTally: { [string]: number } = { SALT = 0, BAWANG = 0, BUNTOT_PAGI = 0 }

for _, id in short.Contents do
	shortTally[id] += 1
end

check("a 3-container pool places 3 items and no more", short.Placed == 3, `Placed={short.Placed}`)

check(
	"the buntot pagi survives a SHORT pool — it is the only thing that kills",
	shortTally.BUNTOT_PAGI == 1,
	`BUNTOT_PAGI={shortTally.BUNTOT_PAGI}`
)

check(
	"salt takes the remaining slots ahead of bawang — the weaken step gates the kill",
	shortTally.SALT == 2 and shortTally.BAWANG == 0,
	`SALT={shortTally.SALT}, BAWANG={shortTally.BAWANG}`
)

-- A map with no containers at all. `SearchService` never calls this path — it refuses at the EMPTY
-- verdict — but the module must not throw if a future caller forgets.
local none = ContainerLayout.draw(0, COUNTS, nextInt)

check("an empty pool places nothing and does not error", none.Placed == 0)
check("an empty pool has no contents", next(none.Contents) == nil)

--------------------------------------------------------------------------------
-- itemAt: the narrowing function, which is the reason Contents holds strings.
--------------------------------------------------------------------------------

local narrow = ContainerLayout.draw(CONTAINERS, COUNTS, nextInt)
local narrowed = 0

for containerIndex in narrow.Contents do
	if ContainerLayout.itemAt(narrow, containerIndex) ~= nil then
		narrowed += 1
	end
end

check("itemAt narrows every placed id", narrowed == ITEMS, `narrowed {narrowed} of {ITEMS}`)
check("itemAt returns nil for an empty container", ContainerLayout.itemAt(none, 1) == nil)

-- An id the module does not recognise is DROPPED, not cast. This is the behaviour a `::` would have
-- destroyed, and the reason the lesson prescribes a function.
local forged = { ContainerCount = 1, Contents = { [1] = "SPAM" }, Placed = 1 }

check(
	"itemAt drops an unrecognised id rather than passing it on",
	ContainerLayout.itemAt(forged, 1) == nil
)

if failures > 0 then
	error(`{failures} container-layout failure(s)`, 0)
end

print(
	`  PASS  container-layout: {checked} assertions — exactness over {DRAWS} draws, two distribution `
		.. `bands, the SHORT priority order, and itemAt`
)
