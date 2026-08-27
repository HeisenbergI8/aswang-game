--!strict
--[[
	May the Aswang feed, over the whole domain. (V06, §4.3)

	The build plan's Verify line asks for "the state x body x distance x phase grid", and this is that
	grid twice — once for `evaluate` (may a feed START) and once for `mayContinue` (may one still be
	RUNNING). 5 x 3 x 5 x 5 is 375 cells each, which is the shape `monster-health` and `noise-model`
	already set: a small pure function over a BOUNDED domain is the one case where enumerating beats
	writing a case per bug.

	WHY IT IS WORTH ENUMERATING AT ALL. Every failure this module can have is silent. A feed that
	refuses when it should not means the Aswang keeps its kill and loses its heal, which reads as
	balance; a feed that grants when it should not means chain-killing over a husk, which reads as an
	exploit nobody can reproduce. Neither shows up as an error and neither is visible in one round.

	THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCHES. `isOk` below is §4.3 written as one
	conjunction. Computing the expectation with the module's own `if` order would prove only that the
	module agrees with itself; PRECEDENCE — which refusal is reported when two apply — is a separate
	and much smaller claim, and it has its own explicit table at the bottom.
]]

local Config = require("../src/shared/Config")
local FeedRules = require("../src/shared/pure/FeedRules")

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

-- SYNTHETIC, not Config's. These assertions are about the MODULE's rules; V16 retunes Config and must
-- not be able to red this file. The live block is cross-checked at the bottom, as `monster-health`
-- does.
local RANGE = 6

local STATES = { "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
-- Three body answers, and the third is nil rather than a string: `bodyKindOf` returns nil for a model
-- in neither folder, which is what a corpse destroyed mid-feed looks like from the tick.
local BODIES: { any } = { "CORPSE", "HUSK", nil }
local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
-- On the body, well inside, EXACTLY at the leash (must be inside), a hair outside, and far away.
local DISTANCES = { 0, RANGE / 2, RANGE, RANGE + 0.01, 400 }

--[[
	§4.3 AS ONE CONJUNCTION. "After a kill, the Aswang must feed on the corpse for 5 seconds —
	transformed, locked in place, visible, and interruptible", plus §6.4's rule that every round
	activity belongs to ACTIVE. Written from the spec so that it is an INDEPENDENT statement of the
	same rule rather than a copy of the implementation.
]]
local function isOk(
	state: string,
	body: string?,
	distance: number,
	phase: string,
	starting: boolean
): boolean
	local formHeld = if starting then state == "TRANSFORMED" else state == "FEEDING"

	return phase == "ACTIVE" and formHeld and body == "CORPSE" and distance <= RANGE
end

--[[
	THE GRID, BOTH DIRECTIONS, BOTH FUNCTIONS. `#BODIES + 1` rather than `#BODIES`, because a trailing
	nil is not counted by the length operator and the nil body is a third of the point — this is
	exactly the shape of hole a `for _, body in BODIES` loop would silently skip.
]]
for _, starting in { true, false } do
	local name = if starting then "evaluate" else "mayContinue"

	for _, state in STATES do
		for bodyIndex = 1, #BODIES + 1 do
			local body: string? = BODIES[bodyIndex]

			for _, phase in PHASES do
				for _, distance in DISTANCES do
					local request = {
						MonsterState = state :: any,
						BodyKind = body :: any,
						Distance = distance,
						Phase = phase :: any,
						Range = RANGE,
					}

					local verdict = if starting
						then FeedRules.evaluate(request)
						else FeedRules.mayContinue(request)
					local expected = isOk(state, body, distance, phase, starting)

					check(
						`{name}: {state}/{body or "nil"}/{distance}/{phase} agrees with §4.3`,
						(verdict == "OK") == expected,
						`verdict={verdict}, expectedOk={expected}`
					)
				end
			end
		end
	end
end

--[[
	PRECEDENCE. Which reason is reported when more than one applies — the module's header calls the
	order part of the contract, and this table is that contract. Every row has TWO or more conditions
	failing, so a reordered branch changes an answer here and nothing else in the file notices.
]]
local PRECEDENCE: { { any } } = {
	-- state, body, distance, phase, starting, expected
	{ "NORMAL", "HUSK", 400, "IDLE", true, "WRONG_PHASE" },
	-- THE ROW THAT PINS "WORLD FACTS FIRST". Move the phase test below the FEEDING test in
	-- `evaluate` and this row alone turns red.
	{ "FEEDING", "HUSK", 400, "ENDING", true, "WRONG_PHASE" },
	{ "FEEDING", "CORPSE", 0, "ENDING", false, "WRONG_PHASE" },
	{ "FEEDING", "HUSK", 400, "ACTIVE", true, "ALREADY_FEEDING" },
	{ "NORMAL", "HUSK", 400, "ACTIVE", true, "NOT_TRANSFORMED" },
	{ "EXPOSED", "CORPSE", 0, "ACTIVE", true, "NOT_TRANSFORMED" },
	{ "CAMOUFLAGED", "CORPSE", 0, "ACTIVE", true, "NOT_TRANSFORMED" },
	{ "TRANSFORMED", "HUSK", 400, "ACTIVE", true, "NOT_A_CORPSE" },
	{ "TRANSFORMED", nil, 0, "ACTIVE", true, "NOT_A_CORPSE" },
	{ "TRANSFORMED", "CORPSE", 400, "ACTIVE", true, "OUT_OF_RANGE" },
	{ "TRANSFORMED", "CORPSE", 0, "ACTIVE", true, "OK" },
	-- mayContinue inverts exactly one row and nothing else.
	{ "TRANSFORMED", "CORPSE", 0, "ACTIVE", false, "NOT_TRANSFORMED" },
	{ "FEEDING", "CORPSE", 0, "ACTIVE", false, "OK" },
	{ "FEEDING", "HUSK", 0, "ACTIVE", false, "NOT_A_CORPSE" },
	{ "FEEDING", "CORPSE", 400, "ACTIVE", false, "OUT_OF_RANGE" },
	{ "NORMAL", "CORPSE", 0, "ACTIVE", false, "NOT_TRANSFORMED" },
}

for _, row in PRECEDENCE do
	local starting = row[5]
	local request = {
		MonsterState = row[1] :: any,
		BodyKind = row[2] :: any,
		Distance = row[3] :: number,
		Phase = row[4] :: any,
		Range = RANGE,
	}

	local verdict = if starting then FeedRules.evaluate(request) else FeedRules.mayContinue(request)

	check(
		`precedence: {row[1]}/{row[2] or "nil"}/{row[3]}/{row[4]} reports {row[6]}`,
		verdict == row[6],
		`got {verdict}`
	)
end

--[[
	THE BOUNDARY, ASSERTED RATHER THAN LEFT TO A READER. `<=` is the module's choice and §4.3's "on
	the corpse" is what it implements; a `<` here would make a feeder standing at exactly the leash
	break their own feed every tick, which reads in a playtest as "feeding is broken sometimes".
]]
check("a feeder at exactly the leash is still on the body", FeedRules.evaluate({
	MonsterState = "TRANSFORMED",
	BodyKind = "CORPSE",
	Distance = RANGE,
	Phase = "ACTIVE",
	Range = RANGE,
}) == "OK")

--[[
	DEGENERATE NUMBERS, IN BOTH SLOTS, AND EVERY ONE MUST REFUSE.

	This is the half of `KillValidation`'s history that cost three attempts and shipped wrong twice.
	NaN compares false to everything, so a guard written as `distance > range` grants on NaN; an
	infinite range makes every distance in the map land; a negative range squares to a positive one.
	None of these is reachable from a client here — no client supplies any of them — and all of them
	are reachable from a V16 Config edit, which is the failure this module is guarding against.
]]
local NAN = 0 / 0

for _, distance in { -1, NAN, math.huge, -math.huge } do
	check(`a degenerate distance ({distance}) refuses`, FeedRules.evaluate({
		MonsterState = "TRANSFORMED",
		BodyKind = "CORPSE",
		Distance = distance,
		Phase = "ACTIVE",
		Range = RANGE,
	}) == "OUT_OF_RANGE")
end

for _, range in { 0, -6, NAN, math.huge } do
	check(`a degenerate range ({range}) refuses even at zero distance`, FeedRules.evaluate({
		MonsterState = "TRANSFORMED",
		BodyKind = "CORPSE",
		Distance = 0,
		Phase = "ACTIVE",
		Range = range,
	}) == "OUT_OF_RANGE")
end

--[[
	AND THE LIVE CONFIG, cross-checked exactly as `monster-health` does its tuning block: the grid
	above proves the MODEL, this proves the numbers this game actually ships can express a feed.
]]
check("Config's leash admits a feeder standing on the body", FeedRules.evaluate({
	MonsterState = "TRANSFORMED",
	BodyKind = "CORPSE",
	Distance = 0,
	Phase = "ACTIVE",
	Range = Config.Monster.FeedLeashStuds,
}) == "OK")
check("Config's leash refuses a feeder who walked to the next house", FeedRules.evaluate({
	MonsterState = "TRANSFORMED",
	BodyKind = "CORPSE",
	Distance = Config.Monster.FeedLeashStuds + 1,
	Phase = "ACTIVE",
	Range = Config.Monster.FeedLeashStuds,
}) == "OUT_OF_RANGE")

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} FeedRules check(s) failed`, 0)
end
