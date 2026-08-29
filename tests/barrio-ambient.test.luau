--!strict
--[[
	THE SIXTEEN AMBIENT SPAWN POINTS, AND WHY ZERO IS WORSE THAN IT LOOKS.

	`AmbientService` creates the rigs; the map's only job is to say WHERE, via the `AmbientSpawn` tag.
	Until Phase 2 the builder emitted none, and the consequence is not "no ambient life" — the service
	falls back to a RING AT THE ORIGIN, so all sixteen animals stood in a circle through the middle of
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
	FOUR FORMS, HARD-CODED HERE ON PURPOSE. `Config.Ambient.PerForm` is per-form and the form list
	lives in `AmbientService.FORM_LOOKS` (CAT / DOG / PIG / VILLAGER), which is Luau this suite cannot
	require. Four is asserted against the service's own roster below rather than assumed.
]]
local FORMS = { "CAT", "DOG", "PIG", "VILLAGER" }
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

local points: { { number } } = {}

for x, z in string.gmatch(block :: string, "{ (%-?%d+), (%-?%d+) }") do
	table.insert(points, { tonumber(x) :: number, tonumber(z) :: number })
end

check(
	`the builder sites exactly {expected} ambient spawns`,
	#points == expected,
	`{#points} parsed; Config.Ambient.PerForm ({perForm}) x {#FORMS} forms = {expected}`
)

-- Two entities starting inside each other is the one placement fault that looks like a rendering bug.
local overlaps = 0

for i = 1, #points do
	for j = i + 1, #points do
		local a, b = points[i], points[j]

		if math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) < 8 then
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
	local key = (if at[2] < 0 then "N" else "S") .. (if at[1] < 0 then "W" else "E")

	quadrants[key] += 1
end

for key, count in quadrants do
	check(
		`quadrant {key} carries ambient life`,
		count >= 2,
		`{count} point(s) in {key}, wanted at least 2`
	)
end

if failures > 0 then
	error(`{failures} barrio-ambient assertion(s) failed`, 0)
end

print(`  PASS  barrio-ambient: {checked} assertions over {#points} spawn points`)
