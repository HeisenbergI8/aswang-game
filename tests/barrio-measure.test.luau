--!strict
--[[
	`measure.luau`'s REACHABILITY SET MUST MATCH THE LIVE TAGS, AND THE FAILURE IS A FALSE GREEN.

	This is the subtlest fault Phase 2 fixed and it is worth stating plainly. `measure.luau` proves the
	layout claim §5 makes — a ~35-second crossing, loops rather than dead ends, every tagged point
	reachable — and every phase of the realism pass cites it as evidence the art pass did not move the
	map. Its reachability set was built from `TaskPoint`, `FetchSource`, `SaltSpawn` and the escape
	gate, and V01 deleted the services behind two of those.

	`CollectionService:GetTagged` on a dead tag returns an EMPTY LIST. It does not error. So the script
	would have walked a fraction of the points it claimed to, found no dead ends among them, and
	printed a healthy report — proof of a layout it had barely visited. A crash would have been kinder.

	This suite pins the table to the tags the services actually read, and pins the one range that is a
	gameplay number to `Config.luau`.
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

local measure = fs.readFile("tools/greybox/measure.luau")
local config = fs.readFile("src/shared/Config.luau")

local block = string.match(measure, "local RANGE_BY_TAG: { %[string%]: number } = {(.-)\n}")

check("measure.luau declares a RANGE_BY_TAG table", block ~= nil)

if not block then
	error("1 barrio-measure assertion(s) failed", 0)
end

local ranges: { [string]: number } = {}
local count = 0

for tag, range in string.gmatch(block :: string, "(%w+) = (%d+),") do
	ranges[tag] = tonumber(range) :: number
	count += 1
end

--[[
	THE TAGS THAT MUST BE WALKED. `SearchContainer` is the round's whole objective surface and
	`SaltSpawn` is §4.6's only counterplay; a corridor that seals off either is a round nobody can
	win, and this file is the only thing that would ever notice.

	`AmbientSpawn` is here for a weaker but real reason: the service places rigs at those points, and a
	point on unwalkable ground puts an animal inside geometry. That is not a lost round, but it is a
	visible defect in a map whose camouflage depends on the population reading as ordinary.
]]
for _, tag in { "SearchContainer", "SaltSpawn", "AmbientSpawn" } do
	check(`the reachability set includes {tag}`, ranges[tag] ~= nil)
end

-- The dead tags must be gone, not merely unused. A stale entry walks an empty list and reports success.
for _, dead in { "TaskPoint", "FetchSource", "EscapeGate" } do
	check(
		`the reachability set no longer includes {dead}`,
		ranges[dead] == nil,
		"GetTagged on a dead tag returns an empty list and reports ok — a false green, not a crash"
	)
end

--[[
	THE ONE RANGE THAT IS A GAMEPLAY NUMBER. "Reachable" is a claim about the SERVER'S rule, so the
	radius this script paths against must be the radius `SearchService` enforces. If Config's
	`RangeStuds` is tuned and this is not, the script measures a game that is not being played.
]]
local rawRange = string.match(config, "\n\t\tRangeStuds = (%d+),")

assert(
	rawRange,
	"Config.luau has no two-tab 'RangeStuds = <number>,' — the key was renamed or re-nested"
)

local rangeStuds = tonumber(rawRange) :: number

check(
	"the SearchContainer range equals Config.Search.RangeStuds",
	ranges.SearchContainer == rangeStuds,
	`measure.luau uses {tostring(ranges.SearchContainer)}, Config says {rangeStuds}`
)

if failures > 0 then
	error(`{failures} barrio-measure assertion(s) failed`, 0)
end

print(`  PASS  barrio-measure: {checked} assertions over {count} tag range(s)`)
