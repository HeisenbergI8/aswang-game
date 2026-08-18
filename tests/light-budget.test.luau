--!strict
--[[
	§5's light cap, made mechanical (C27).

	"Cap dynamic lights to ~8 visible at once — many point lights are the #1 mobile FPS killer" has
	been a sentence in the spec and a number in `Config` since the scaffold, read by nothing. What
	makes it a rule is this decision, and what makes the decision worth testing is that its two hard
	parts are invisible on a phone:

	  · a flickering lantern looks like a lighting artifact, not like a budget bug
	  · a budget that is quietly never reached looks exactly like a budget that works

	The properties at the bottom carry the weight — a cell table can be satisfied by accident after an
	edit, a property stating "never more than the allowance, over every input in the table" cannot.
]]

local LightBudget = require("../src/shared/pure/LightBudget")

type Candidate = LightBudget.Candidate
type Input = LightBudget.Input

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

-- Mirrors Config.Performance, whose own relationships (Reserved below MaxVisibleLights) are pinned
-- separately in tests/config.test.luau.
local BUDGET = 8
local RESERVED = 3
local ALLOWANCE = BUDGET - RESERVED
local CULL = 140
local HYSTERESIS = 12

local function input(over: {
	Candidates: { Candidate },
	Budget: number?,
	Reserved: number?,
	CullRadiusStuds: number?,
	HysteresisStuds: number?,
}): Input
	return {
		Candidates = over.Candidates,
		Budget = over.Budget or BUDGET,
		Reserved = if over.Reserved == nil then RESERVED else over.Reserved,
		CullRadiusStuds = over.CullRadiusStuds or CULL,
		HysteresisStuds = if over.HysteresisStuds == nil then HYSTERESIS else over.HysteresisStuds,
	}
end

local function at(distance: number, wasOn: boolean?): Candidate
	return { Distance = distance, WasOn = wasOn == true }
end

local function litCount(decisions: { boolean }): number
	local n = 0

	for _, on in decisions do
		if on then
			n += 1
		end
	end

	return n
end

--------------------------------------------------------------------------------
-- The nearest win, and only the allowance is spent
--------------------------------------------------------------------------------

--[[
	Twelve lanterns is the barrio's real count, and they are handed over SHUFFLED relative to
	distance on purpose: a decision that only worked on a pre-sorted list would pass a tidier test
	and fail on the map, where the order is whatever `CollectionService` hands back.
]]
local TWELVE = {
	at(90),
	at(10),
	at(200),
	at(35),
	at(5),
	at(120),
	at(60),
	at(25),
	at(15),
	at(300),
	at(45),
	at(80),
}

local twelve = LightBudget.choose(input({ Candidates = TWELVE }))

check(
	`twelve lanterns spend exactly the allowance ({ALLOWANCE})`,
	litCount(twelve) == ALLOWANCE,
	`lit {litCount(twelve)}`
)

check(
	"the five nearest are the five lit",
	twelve[5] and twelve[2] and twelve[9] and twelve[8] and twelve[4],
	"expected the 5, 10, 15, 25 and 35 stud lanterns"
)

check("the 45-stud lantern misses the cut", not twelve[11])
check("the 300-stud lantern is not lit", not twelve[10])

--------------------------------------------------------------------------------
-- The gameplay reservation is subtracted, not shared
--------------------------------------------------------------------------------

--[[
	THE POINT OF `Reserved`, IN ONE ASSERTION.

	The Aswang's eye glow and a salt pouch's glow never reach this module — the caller only hands it
	scenery — so the only way they are protected is that the map is not allowed to spend their slots.
	If this ever reads `BUDGET` the tells go dark in a lit street, which is the one failure mode §4.3
	and §4.6 cannot absorb.
]]
check(
	"the map never spends the gameplay lights' slots",
	litCount(LightBudget.choose(input({ Candidates = TWELVE }))) == BUDGET - RESERVED
)

check(
	"a reservation as large as the budget leaves the map dark rather than negative",
	litCount(LightBudget.choose(input({ Candidates = TWELVE, Reserved = BUDGET }))) == 0
)

check(
	"a reservation larger than the budget is still zero, not an error",
	litCount(LightBudget.choose(input({ Candidates = TWELVE, Reserved = BUDGET + 4 }))) == 0
)

--------------------------------------------------------------------------------
-- The cull radius overrides the budget, never the other way round
--------------------------------------------------------------------------------

--[[
	Three lanterns, all beyond the radius, with the budget wide open. A light 200 studs away
	contributes nothing a player can see at `Range = 26`, so an empty allowance is the right answer
	and "we had slots left" is not a reason to light one.
]]
local farOnly =
	LightBudget.choose(input({ Candidates = { at(200), at(400), at(141) }, Budget = 99 }))

check("distance beats a spare slot", litCount(farOnly) == 0)

check(
	"the radius is inclusive at its edge",
	LightBudget.choose(input({ Candidates = { at(CULL) } }))[1] == true
)

check(
	"and exclusive one stud past it",
	LightBudget.choose(input({ Candidates = { at(CULL + 1) } }))[1] == false
)

--------------------------------------------------------------------------------
-- PROPERTY 1 — hysteresis, which is the whole reason this is not a sort
--------------------------------------------------------------------------------

--[[
	A player standing still between two lanterns that are all but equidistant. Without the margin,
	the lit one loses its slot to a rival one stud closer, wins it back on the next pass, and the
	street strobes at the cull rate.

	Allowance forced to one so the contest is visible in a two-element answer.
]]
local contested = LightBudget.choose(input({
	Candidates = { at(41, true), at(40, false) },
	Budget = 4,
	Reserved = 3,
}))

check("a lit lantern is not stolen from by a rival one stud closer", contested[1] == true)
check("and the rival stays dark", contested[2] == false)

--[[
	But the margin is a margin, not a lock. A rival decisively closer takes the slot, or a player
	walking down a street drags a lantern behind them that they have already passed.
]]
local overtaken = LightBudget.choose(input({
	Candidates = { at(41, true), at(41 - HYSTERESIS - 1, false) },
	Budget = 4,
	Reserved = 3,
}))

check("a decisively closer rival does take the slot", overtaken[2] == true)
check("and the lit one goes out", overtaken[1] == false)

--[[
	AND HYSTERESIS DOES NOT DEFEAT THE CULL RADIUS. A lit lantern that walks out of range goes out;
	the margin decides who wins a slot, never whether a light 200 studs away deserves one.
]]
check(
	"a lit lantern past the radius still goes out",
	LightBudget.choose(input({ Candidates = { at(CULL + 5, true) } }))[1] == false
)

--------------------------------------------------------------------------------
-- PROPERTY 2 — determinism, including ties
--------------------------------------------------------------------------------

--[[
	Ties are the second way a lantern flickers: two lights at an identical distance that swap on
	every pass look exactly like the hysteresis bug and are not fixed by it. The index breaks the tie,
	so the answer is total and repeatable over any input.
]]
local tied = { at(50), at(50), at(50), at(50) }
local firstPass = LightBudget.choose(input({ Candidates = tied, Budget = 4, Reserved = 3 }))

for pass = 1, 5 do
	local again = LightBudget.choose(input({ Candidates = tied, Budget = 4, Reserved = 3 }))
	local same = true

	for index = 1, #tied do
		if again[index] ~= firstPass[index] then
			same = false
		end
	end

	check(`an exact tie resolves the same way on pass {pass}`, same)
end

--------------------------------------------------------------------------------
-- PROPERTY 3 — never over budget, over every shape at once
--------------------------------------------------------------------------------

local overBudget = ""

for count = 0, 40 do
	local candidates: { Candidate } = {}

	for index = 1, count do
		-- Deterministic pseudo-spread rather than Random: same list every run, and no seed to argue
		-- about. Distances repeat, so ties are exercised here as well.
		candidates[index] = at((index * 37) % 160, index % 3 == 0)
	end

	local decisions = LightBudget.choose(input({ Candidates = candidates }))

	if litCount(decisions) > ALLOWANCE and overBudget == "" then
		overBudget = `{count} candidates lit {litCount(decisions)}`
	end

	if #decisions ~= count and overBudget == "" then
		overBudget = `{count} candidates returned {#decisions} decisions`
	end
end

check("no input lights more than the allowance", overBudget == "", overBudget)
check("an empty map is an empty answer", #LightBudget.choose(input({ Candidates = {} })) == 0)

--------------------------------------------------------------------------------
-- PROPERTY 4 — purity. The caller's list is the live one it built from the map.
--------------------------------------------------------------------------------

local probe = { at(90), at(10), at(50, true) }
local probeInput = input({ Candidates = probe })

LightBudget.choose(probeInput)

check(
	"choose does not reorder the caller's list",
	probe[1].Distance == 90 and probe[2].Distance == 10 and probe[3].Distance == 50,
	"the decisions are indexed against this list — a sort in place would misapply every one"
)

check("choose does not mutate a candidate's state", probe[3].WasOn == true)

if failures > 0 then
	error(`{failures} light-budget failure(s)`, 0)
end

print(`  PASS  light-budget: {checked} assertions`)
