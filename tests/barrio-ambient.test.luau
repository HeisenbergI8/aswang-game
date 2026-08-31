--!strict
--[[
	THE EIGHTEEN AMBIENT SPAWN POINTS, AND WHY ZERO IS WORSE THAN IT LOOKS.

	`AmbientService` creates the rigs; the map's only job is to say WHERE, via the `AmbientSpawn` tag.
	Until Phase 2 the builder emitted none, and the consequence is not "no ambient life" — the service
	falls back to a RING AT THE ORIGIN, so the whole population stood in a circle through the middle of
	the spawn plaza. That is both absurd to look at and directly harmful to §4.5: camouflage works
	because the deduction is "which cat", never "is that a cat", and an Aswang wearing a cat needs
	other cats plausibly near wherever it hides — not all of them in one heap where everyone spawns.

	THE FALLBACK FIRES ONLY ON ZERO TAGGED PARTS, which makes a partial list the worst of the three
	states: the ring switches off and the population clusters into whatever few points exist, and it
	looks deliberate. So the count is asserted exactly, not as a minimum.
]]

local fs = require("@lune/fs")

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

local builder = fs.readFile("tools/greybox/barrio.luau")
local config = fs.readFile("src/shared/Config.luau")

local rawPerForm = string.match(config, "\n\t\tPerForm = (%d+),")

assert(
	rawPerForm,
	"Config.luau has no two-tab 'PerForm = <number>,' — the key was renamed or re-nested"
)

--[[
	SIX FORMS, HARD-CODED HERE ON PURPOSE. `Config.Ambient.PerForm` is per-form and the form list lives
	in `AmbientService.FORM_LOOKS`, which is Luau this suite cannot require. The list is asserted
	against the service's own roster below rather than assumed, and
	`tests/camouflage-forms.test.luau` pins it against `Types.luau` — so this copy cannot drift alone.
]]
local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }
local perForm = tonumber(rawPerForm) :: number
local expected = perForm * #FORMS

local roster = fs.readFile("src/server/Services/AmbientService.luau")
local formsFound = 0

for _, form in FORMS do
	if string.find(roster, `"{form}"`, 1, true) then
		formsFound += 1
	end
end

check(
	`AmbientService still names all {#FORMS} forms`,
	formsFound == #FORMS,
	`{formsFound} of {#FORMS} found — if a form was added or removed, {expected} is the wrong count`
)

local block = string.match(builder, "local AMBIENT_POINTS = {(.-)\n}")

check("the builder declares an AMBIENT_POINTS table", block ~= nil)

if not block then
	error("1 barrio-ambient assertion(s) failed", 0)
end

type Point = { Form: string, X: number, Z: number }

local points: { Point } = {}

for form, x, z in
	string.gmatch(block :: string, '{ Form = "([A-Z_]+)", X = (%-?%d+), Z = (%-?%d+) }')
do
	table.insert(points, { Form = form, X = tonumber(x) :: number, Z = tonumber(z) :: number })
end

check(
	`the builder sites exactly {expected} ambient spawns`,
	#points == expected,
	`{#points} parsed; Config.Ambient.PerForm ({perForm}) x {#FORMS} forms = {expected}`
)

--[[
	EVERY POINT NAMES A FORM, AND EXACTLY `PerForm` OF THEM NAME EACH.

	This is the assertion that keeps `AmbientTerritory`'s lockstep contract honest: the service spawns
	one rig per point in point order, so slot index and point index are the same number, and
	`nearestFreeIndex` returns a POINT index that `AmbientService` uses as a SLOT index. A form with
	four points and three rigs breaks that identity silently — the fourth point is never occupied, and
	a monster standing on it is refused a claim for a form whose territory it is visibly inside.
]]
local perFormCount: { [string]: number } = {}

for _, form in FORMS do
	perFormCount[form] = 0
end

for _, point in points do
	check(`{point.Form} is a declared form`, perFormCount[point.Form] ~= nil, point.Form)

	if perFormCount[point.Form] ~= nil then
		perFormCount[point.Form] += 1
	end
end

for _, form in FORMS do
	check(
		`{form} has exactly PerForm ({perForm}) territories`,
		perFormCount[form] == perForm,
		`{perFormCount[form]} sited`
	)
end

--[[
	AND THE ATTRIBUTE THE SERVICE ACTUALLY READS. The NAME carrying the form is for a human in Studio;
	the ATTRIBUTE is the contract, and a builder that stopped setting it would leave every rig formless
	with the point count still correct — `spawnPointsByForm` would skip all eighteen and the service
	would fall back to its ring.

	MATCHED AGAINST `anchor()`'s SIXTH PARAMETER rather than a `SetAttribute` call, because that is the
	door every other tagged pad in the builder already uses.
]]
check(
	"the builder passes the Form attribute through anchor()",
	string.find(builder, "{ Form = at.Form }", 1, true) ~= nil
)

-- Two entities starting inside each other is the one placement fault that looks like a rendering bug.
local overlaps = 0

for i = 1, #points do
	for j = i + 1, #points do
		local a, b = points[i], points[j]

		if math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) < 8 then
			overlaps += 1
		end
	end
end

check("no two spawn points are within 8 studs", overlaps == 0, `{overlaps} overlapping pair(s)`)

--[[
	SPREAD ACROSS QUADRANTS, because §4.5's disguise is only as good as the nearest plausible neighbour.
	A quadrant with no ambient life in it is a quadrant where wearing an animal is a confession.
]]
local quadrants: { [string]: number } = { NE = 0, NW = 0, SE = 0, SW = 0 }

for _, at in points do
	local key = (if at.Z < 0 then "N" else "S") .. (if at.X < 0 then "W" else "E")

	quadrants[key] += 1
end

for key, count in quadrants do
	check(
		`quadrant {key} carries ambient life`,
		count >= 2,
		`{count} point(s) in {key}, wanted at least 2`
	)
end

--[[
	EVERY FORM'S TERRITORY CARRIES THE PROP THAT EXPLAINS IT.

	`AmbientService.ClaimSlot` refuses a camouflage unless the Aswang is standing near a territory of
	the form it wants, so a pig on the basketball court is impossible. That is a real tactical
	constraint — and it is only COUNTERPLAY if the player can see it. A pig territory with no wallow
	beside it is a rule with no evidence, which is a trap.

	CHECKED AS A BRANCH PER FORM in `territoryProp`, because the props are built in a loop over
	`AMBIENT_POINTS` and a literal grep cannot match `{name}_Wallow`. A form with no branch silently
	gets no prop, and the eighteen points would still all be sited.
]]
for _, form in FORMS do
	check(
		`territoryProp explains a {form} territory`,
		string.find(builder, `form == "{form}"`, 1, true) ~= nil,
		"a territory with no prop is a rule the player cannot see"
	)
end

if failures > 0 then
	error(`{failures} barrio-ambient assertion(s) failed`, 0)
end

print(`  PASS  barrio-ambient: {checked} assertions over {#points} spawn points`)
