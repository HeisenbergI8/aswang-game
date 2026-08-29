--!strict
--[[
	THE MATERIAL REGISTRY, AND THE SILENT FAILURE IT EXISTS TO PREVENT.

	A `MaterialVariant` needs BOTH `Material` and `MaterialVariant` set on the part, or it does nothing
	at all — no error, no warning, and no visual difference from a typo. Across ~1,100 parts that is not
	findable by eye, which is why it is findable by this instead.

	The registry is sliced out of the builder between two sentinels and `loadstring`ed into a real
	table, so it cannot drift from the file that uses it without the tree going red. That round trip is
	the only reason a hand-maintained registry is worth having.
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

local block = string.match(builder, "%-%-#ASSETS%-BEGIN\n(.-)%-%-#ASSETS%-END")

check("the ASSETS registry block is present and sentinel-delimited", block ~= nil)

if block == nil then
	error("1 barrio-materials assertion(s) failed", 0)
end

local loader = loadstring or load
local assets = (assert(loader(`{block}\nreturn ASSETS`, "assets")) :: any)()

check("the registry loads as a table with a Materials list", type(assets.Materials) == "table")

--[[
	THE PAIRING RULE, CHECKED STRUCTURALLY RATHER THAN BY REVIEW.

	`paint()` is the only sanctioned way to bind a variant, precisely because it cannot half-apply the
	pair. A hand-written `.MaterialVariant =` anywhere else is the shape that fails silently, so it is
	banned outright. The one legitimate assignment is the line INSIDE `paint()` itself.
]]
local handWritten = {}

for line in string.gmatch(builder, "[^\n]+") do
	--[[
		THE ONE LEGITIMATE ASSIGNMENT is the line inside `paint()` itself. It is matched exactly rather
		than by indentation, because StyLua re-indents and an indentation-based exclusion silently
		starts flagging the helper the first time the surrounding block changes depth.
	]]
	if
		string.match(line, "%.MaterialVariant%s*=")
		and not string.match(line, "p%.MaterialVariant = surface%.Variant")
	then
		table.insert(handWritten, (string.gsub(line, "^%s+", "")))
	end
end

check(
	"no MaterialVariant is bound outside the paint() helper",
	#handWritten == 0,
	`{#handWritten} hand-written assignment(s): {table.concat(handWritten, " | ")}`
)

--[[
	EVERY VARIANT THE BUILDER PAINTS WITH MUST BE IN THE REGISTRY. Otherwise `paint()` only warns, at
	build time, in Studio's output — where nobody is watching during an art pass, and where the part
	quietly keeps its base material.
]]
local unknown = {}

--[[
	THE CALL SITES ARE SCANNED LINE BY LINE, AND BOTH SIMPLER VERSIONS WERE WRONG.

	The first attempt enumerated the characters a part expression may contain and
	`paint(wall :: Part, "Whitewash")` slipped straight past it — a type cast is not in `[%w_%.%[%]"]`.
	Broadening the first argument to `.-` then over-matched in the other direction: `gmatch` runs over
	the whole file, so a `paint(` on one line happily paired with `AddTag(p, "MapLight")` forty lines
	below and reported `MapLight` as an unregistered surface.

	A Lua pattern cannot express "within one call", so this does not try. It walks lines, and for each
	line containing `paint(` it takes either the id on that same line or, when StyLua has split the
	call across lines, the next lone quoted string — which is where the final argument lands.
]]
local lines = {}

for line in string.gmatch(builder, "[^\n]*") do
	table.insert(lines, line)
end

local painted = 0

for index, line in lines do
	if not string.find(line, "paint(", 1, true) then
		continue
	end

	local id = string.match(line, ',%s*"([%w_]+)"%s*%)')

	if id == nil then
		--[[
			Split across lines by StyLua. Taking the FIRST lone quoted string is wrong — in
			`paint(prop("Court_Slab", ...), "CourtSlab")` that is the prop's NAME, and the scan
			duly reported `Court_Slab` as an unregistered surface. The id is the LAST one before the
			call closes, so this counts parens from the `paint(` line and keeps the most recent
			candidate until depth returns to zero.
		]]
		local depth = 0

		for ahead = index, math.min(index + 32, #lines) do
			local text = lines[ahead]

			depth += select(2, string.gsub(text, "%(", ""))
			depth -= select(2, string.gsub(text, "%)", ""))

			local lone = string.match(text, '^%s*"([%w_]+)",?%s*$')

			if lone then
				id = lone
			end

			if ahead > index and depth <= 0 then
				break
			end
		end
	end

	if id == nil then
		continue
	end

	painted += 1

	local found = false

	for _, entry in assets.Materials do
		if entry.Id == id then
			found = true
			break
		end
	end

	if not found then
		table.insert(unknown, id)
	end
end

check(
	"the builder actually paints something",
	painted > 0,
	"no paint() call sites parsed — the scan is broken, and a broken scan reports zero problems"
)

check(
	"every painted surface id is in the registry",
	#unknown == 0,
	`unregistered: {table.concat(unknown, ", ")} — paint() only warns, in Studio, where nobody is watching`
)

--[[
	THE REGISTRY MUST BE COMPLETE. A row with no `Base` cannot be applied at all; a row with no
	`Variant` cannot be looked up; a `Base` that is not a real `Enum.Material` name makes
	`MATERIAL_BY_VARIANT` nil for that row, and `paint()` then warns for every part that asks for it.
]]
local BASE_MATERIALS: { [string]: boolean } = {}

for _, name in
	{
		"Plastic",
		"SmoothPlastic",
		"Wood",
		"WoodPlanks",
		"Marble",
		"Basalt",
		"Slate",
		"CrackedLava",
		"Concrete",
		"Limestone",
		"Granite",
		"Pavement",
		"Brick",
		"Pebble",
		"Cobblestone",
		"Rock",
		"Sandstone",
		"CorrodedMetal",
		"DiamondPlate",
		"Foil",
		"Metal",
		"Grass",
		"LeafyGrass",
		"Sand",
		"Fabric",
		"Snow",
		"Mud",
		"Ground",
		"Asphalt",
		"Salt",
		"Ice",
		"Glacier",
		"Cardboard",
		"Carpet",
		"CeramicTiles",
		"ClayRoofTiles",
		"RoofShingles",
		"Leather",
		"Plaster",
		"Rubber",
	}
do
	BASE_MATERIALS[name] = true
end

local variantNames: { [string]: boolean } = {}
local duplicates = 0

for index, entry in assets.Materials do
	check(
		`registry row {index} names a surface id`,
		type(entry.Id) == "string" and #entry.Id > 0,
		"the id is what the builder asks for by name"
	)
	--[[
		EVERY ROW NOW CARRIES A REAL GENERATED `MaterialVariant`. `Variant` stays technically optional —
		a row without one falls back to its stock base, which is a soft, sane failure — but an EMPTY
		string is not: it binds nothing while looking exactly like a row somebody filled in.
	]]
	check(
		`registry row {index} has a usable Variant or none at all`,
		entry.Variant == nil or (type(entry.Variant) == "string" and #entry.Variant > 0),
		`Variant = {tostring(entry.Variant)}`
	)

	--[[
		THE FOUR TEXTURE MAPS ARE THE DURABLE RECORD OF A GENERATED MATERIAL. The variant itself lives
		in the place file — gitignored, binary, unsearchable — so these ids are the only thing that
		survives a lost place. A row with a Variant but no maps is a material nobody can regenerate.
	]]
	if entry.Variant ~= nil then
		for _, map in { "Color", "Normal", "Rough", "Metal" } do
			check(
				`registry row {index} records its {map} map`,
				type(entry[map]) == "string"
					and string.match(entry[map], "^rbxassetid://%d+$") ~= nil,
				`{map} = {tostring(entry[map])}`
			)
		end
	end
	check(
		`registry row {index} records a regeneration prompt`,
		type(entry.Prompt) == "string" and #entry.Prompt > 0,
		"without the prompt the surface's intent is lost and cannot be re-attempted later"
	)
	check(
		`registry row {index} names a real BaseMaterial`,
		type(entry.Base) == "string" and BASE_MATERIALS[entry.Base] == true,
		`Base = {tostring(entry.Base)} is not an Enum.Material name`
	)
	check(
		`registry row {index} records the generation pattern`,
		entry.Pattern == "Regular" or entry.Pattern == "Organic",
		`Pattern = {tostring(entry.Pattern)}; without it a lost variant cannot be regenerated`
	)

	if variantNames[entry.Id] then
		duplicates += 1
	end

	variantNames[entry.Id] = true
end

check("no two registry rows share a surface id", duplicates == 0, `{duplicates} duplicate(s)`)

--[[
	THE POINT OF THE WHOLE PHASE: every surface should be a GENERATED material, not a stock one. A row
	that quietly loses its variant degrades to Roblox's built-in look, which is precisely the "lego"
	appearance this pass exists to remove — and it degrades silently, part by part, with no error.
]]
local withVariant = 0

for _, entry in assets.Materials do
	if entry.Variant ~= nil then
		withVariant += 1
	end
end

check(
	"every registered surface has a generated MaterialVariant",
	withVariant == #assets.Materials,
	`{withVariant} of {#assets.Materials} — the rest fall back to stock Roblox materials`
)

if failures > 0 then
	error(`{failures} barrio-materials assertion(s) failed`, 0)
end

print(
	`  PASS  barrio-materials: {checked} assertions over {#assets.Materials} registered material(s)`
)
