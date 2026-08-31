--!strict
--[[
	tests/ambient-territory.test.luau

	WHICH FORM MAY STAND WHERE, AND THE TWO PROPERTIES THAT KEEP THAT FAIR.

	Per-form territories are a real constraint on the ASWANG, not only on the scenery: a pig on the
	basketball court is wrong, so the monster can only wear a pig near mud. That is deliberate and it
	is good counterplay — but it is only fair if the territories are SPREAD. Three pig territories all
	in the south-east is a rule that says "you may not hide as a pig anywhere you are likely to be",
	and nothing in the game would ever say so.

	SO THE TWO ASSERTIONS ARE COVERAGE AND SPREAD, and both are about the monster's options rather
	than about the animals. The animals are fine wherever they are put.

	IT ALSO PINS THE CLAIM RADIUS AGAINST THE WANDER RADIUS, which is the invariant that decides
	whether the constraint has any teeth. See the check's own comment.
]]

local AmbientTerritory = require("../src/shared/pure/AmbientTerritory")
local Config = require("../src/shared/Config")

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

local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }

--[[
	The eighteen points, mirroring `AMBIENT_POINTS` in `tools/greybox/barrio.luau`. Duplicated rather
	than parsed, because THIS suite is about the RULE and `tests/barrio-ambient.test.luau` is about the
	MAP — and that suite asserts the two lists agree, so the duplication is checked rather than trusted.
]]
local POINTS = {
	{ Form = "CAT", X = 34, Z = -100 },
	{ Form = "CAT", X = -100, Z = 34 },
	{ Form = "CAT", X = 96, Z = 100 },
	{ Form = "DOG", X = 0, Z = -76 },
	{ Form = "DOG", X = -130, Z = -44 },
	{ Form = "DOG", X = 62, Z = 130 },
	{ Form = "PIG", X = -64, Z = 44 },
	{ Form = "PIG", X = -70, Z = -104 },
	{ Form = "PIG", X = 108, Z = 108 },
	{ Form = "GOAT", X = 146, Z = -70 },
	{ Form = "GOAT", X = -124, Z = 118 },
	{ Form = "GOAT", X = 128, Z = 148 },
	{ Form = "CHICKEN", X = -92, Z = -78 },
	{ Form = "CHICKEN", X = 92, Z = -78 },
	{ Form = "CHICKEN", X = 78, Z = 92 },
	{ Form = "VILLAGER", X = -78, Z = -64 },
	{ Form = "VILLAGER", X = 78, Z = 64 },
	{ Form = "VILLAGER", X = -42, Z = 30 },
}

-- 1. COVERAGE. Every form has at least `PerForm` territories, or two rigs share one point and stand
-- inside each other — which looks like a rendering bug and is the one placement fault a player
-- reports as "the game is broken" rather than as "that pig is odd".
for _, form in FORMS do
	local owned = AmbientTerritory.pointsFor(POINTS, form)

	check(
		`{form} has at least PerForm ({Config.Ambient.PerForm}) territories`,
		#owned >= Config.Ambient.PerForm,
		`{#owned} territories`
	)
end

-- 2. SPREAD. No form's territories are all in one quadrant. This is the fairness half: it bounds how
-- much of the map a given disguise is unavailable in.
for _, form in FORMS do
	local owned = AmbientTerritory.pointsFor(POINTS, form)
	local quadrants: { [string]: boolean } = {}
	local distinct = 0

	for _, point in owned do
		local key = (if point.Z < 0 then "N" else "S") .. (if point.X < 0 then "W" else "E")

		if not quadrants[key] then
			quadrants[key] = true
			distinct += 1
		end
	end

	check(
		`{form}'s territories span at least 3 quadrants`,
		distinct >= 3,
		`{distinct} quadrant(s) for {#owned} territories`
	)
end

--[[
	3. THE CLAIM RADIUS HAS TO BE SMALLER THAN THE WANDER RADIUS, and this is the invariant that
	decides whether the constraint means anything at all.

	A free rig roams `WanderRadius` from its point. If the monster may claim from FURTHER than that, it
	can hide as a pig standing somewhere no real pig has ever been — the territory becomes advisory and
	the whole tactical constraint the design bought evaporates, silently, with every test still green.

	IT IS ALSO THE TELEPORT BOUND. On claim the entity is driven to the monster, so this number IS how
	far an ambient animal can be seen to jump. Smaller is a tighter constraint and a smaller jump; the
	cost is that camouflage is refused more often, which is a V16 balance question and not a
	correctness one.
]]
check(
	"Ambient.ClaimRadius < Ambient.WanderRadius — or the territory is advisory",
	Config.Ambient.ClaimRadius < Config.Ambient.WanderRadius,
	`claim={Config.Ambient.ClaimRadius}, wander={Config.Ambient.WanderRadius}`
)

-- 4. THE LOOKUP ITSELF. `nearestFreeIndex` must refuse rather than return a far one, because the
-- refusal IS the mechanic — a version that fell back to the nearest at any distance would pass every
-- assertion above and restore the map-wide teleport.
local free = {
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
	true,
}

check(
	"a monster standing on a PIG territory may claim it",
	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", -64, 44, 20) == 7
)
check(
	"a monster far from every PIG territory is refused",
	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", 0, 0, 20) == nil
)
check(
	"a claimed slot is skipped and the next nearest is refused if out of range",
	AmbientTerritory.nearestFreeIndex(POINTS, {
		true,
		true,
		true,
		true,
		true,
		true,
		false,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
		true,
	}, "PIG", -64, 44, 20) == nil
)
check(
	"form is respected — a CAT territory does not satisfy a PIG request",
	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", 34, -100, 20) == nil
)

if failures > 0 then
	error(`{failures} ambient-territory assertion(s) failed`, 0)
end

print(`  PASS  ambient-territory: {checked} assertions over {#POINTS} territories`)
