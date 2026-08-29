--!strict
--[[
	THE HERO-ZONE GEOMETRY, AND THE MOBILE BUDGET IT SPENDS.

	Lune has no `game`, so this cannot count the parts the builder actually produces — the live
	instance count is recorded by hand in `artifacts/hero-zone.md` from the builder's own receipt. What
	this suite CAN do is assert the authored structures that produce that count, which is the half that
	silently regresses: a loop bound edited from 6 to 60, a brace added inside a per-hoop loop, a
	dressing part that gains collision.

	IT ALSO REPLACES A GREP. Step 4.2 was gated on `grep -c Bench1_Back`, which cannot match the
	interpolated `Bench{index}_Back` the loop actually writes — the check the plan itself called the
	grep trap, failing in exactly the way it warned about. Structure is checkable; "does it look right"
	is not, and that is Step 4.5's job rather than this file's.
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

local function occurrences(needle: string): number
	local _, n = string.gsub(builder, needle, "")

	return n
end

--[[
	THE COURT. Its proportion is the one number here that is a research finding rather than a
	preference: a barangay court follows roughly the FIBA 28x15m ratio even when undersized, and the
	greybox's 30x18 was squarer than any real one. A court that reads wrong reads as a car park.
]]
check(
	"the court slab is 30 x 16, not the original 30 x 18",
	string.find(builder, "16 %* SCALE") ~= nil and string.find(builder, '"Court_Slab"') ~= nil,
	"the slab proportion was reverted, or the name changed"
)
check(
	"the court's side lines moved in with the slab",
	occurrences("COURT_Z %- 8") >= 1 and occurrences("COURT_Z %+ 8") >= 1,
	"lines still sit at +/-9 and now hang off the narrowed slab"
)
check(
	"the slab is painted rather than left bare cement",
	string.find(builder, '"CourtSlab"') ~= nil
)

--[[
	THE CRACKS. Six is a budget decision as much as a visual one, and the bound is what stops a later
	edit turning the highest realism-per-part item in the plaza into sixty parts.
]]
local crackBound =
	string.match(builder, "for index = 1, (%d+) do\n\tturn%(\n\t\tprop%(\n\t\t\t`Court_Crack")

check("the court has cracks in it at all", crackBound ~= nil, "Court_Crack loop not found")
check(
	"the crack count stays at 6",
	tonumber(crackBound or "0") == 6,
	`crack loop runs {tostring(crackBound)} times; 6 is what the budget was measured against`
)

--[[
	THE HOOPS. Netless and bent is the single most repeated observation about real barangay hoops, and
	the two rims must lean by DIFFERENT amounts — symmetry is the tell that something was placed rather
	than used.
]]
check(
	"the rims lean",
	string.find(builder, "if index == 1 then %-7 else %-4") ~= nil,
	"both rims are level or equal"
)
check("the rims are rusted steel", string.find(builder, '"RustedSteel"') ~= nil)
check("each backboard has braces behind it", string.find(builder, "Hoop{index}_Brace") ~= nil)

--[[
	THE BAHAY KUBO. Stilts and pitch are opt-in, because `building()` also builds the chapel and a
	chapel on stilts is wrong.
]]
check(
	"stilts are opt-in rather than applied to every building",
	string.find(builder, "stilted: boolean?") ~= nil
)
check("the kubo get stilts", string.find(builder, "{name}_Stilt") ~= nil)
check("the kubo roof is pitched", string.find(builder, "{name}_Pitch") ~= nil)

--[[
	THE COLLISION RULE, WHICH IS THE ONE THAT COSTS FRAMES AND CROSSING TIME.

	Every decorative part must be non-collidable. `prop()` guarantees it for the dressing; the stilts
	and roof panels are built with `box()` instead, because `prop` is declared hundreds of lines below
	`building()` — so they carry the flags themselves through a local helper, and that helper must not
	quietly lose them.
]]
check(
	"the in-building decoration helper clears collision",
	string.find(builder, "q.CanCollide = false") ~= nil,
	"a collidable stilt beside a doorway narrows it and moves the navmesh"
)
check(
	"the builder still asserts zero dressing colliders",
	string.find(builder, "dressColliders") ~= nil,
	"C30's collision assert was removed; nothing now fails the build on a collidable prop"
)

--[[
	PHASE 5 — THE MESHES ARE PLACED, AND THE BOXES THEY REPLACED ARE GONE.

	A mesh dropped in beside the boxes it was meant to replace is the expensive failure here: the map
	pays for both, the budget quietly doubles, and the screenshot looks fine because the mesh is
	drawn on top. So this asserts the DELETION, not just the placement.
]]
check(
	"meshes are created through CreateMeshPartAsync",
	string.find(builder, "CreateMeshPartAsync", 1, true) ~= nil,
	"MeshPart.MeshId is not script-writable — it fails silently and leaves a zero-size invisible part"
)
check(
	"a failed mesh load warns rather than leaving a silent hole",
	string.find(builder, "expect a hole here", 1, true) ~= nil,
	"the prop a mesh replaces is already deleted, so a quiet failure is an unexplained gap in the map"
)

for _, gone in
	{
		"Banana{index}_Leaf",
		"Banana{index}_Trunk",
		"Grave{index}_V",
		"Grave{index}_H",
		"{base}_Hat",
		"{base}_Sidecar",
	}
do
	check(
		`the box version of {gone} is gone`,
		string.find(builder, gone, 1, true) == nil,
		"the mesh was added without removing what it replaces, so the map pays for both"
	)
end

--[[
	PHASE 7 — AND THESE EXIST BECAUSE A SILENT DELETION GOT ALL THE WAY TO A GREEN BUILD.

	The bamboo rewrite located the end of the block it was replacing by counting `end` lines, miscounted
	the nesting, and deleted the fence runs, the banana coordinate table, the `FieldDressing` folder and
	the scarecrows along with it. Every downstream signal said success: the build ran, `measure.luau`
	reported all ten lines ok, and the part count DROPPED — which is exactly what Phase 7 exists to do,
	so the loss read as the saving working. `local field` silently became nil and the drying racks
	reparented themselves to `dress`.

	Nothing structural was asserted, so nothing could object. These do.
]]
for _, structure in
	{
		"local FENCES",
		"local BANANA_AT",
		"local BAMBOO_AT",
		'field.Name = "FieldDressing"',
		"Bamboo{index}_Crown",
		"{kubo.Name}_RoofPatch",
	}
do
	check(
		`the builder still declares {structure}`,
		string.find(builder, structure, 1, true) ~= nil,
		"deleted, and a deletion here lowers the part count rather than raising an error"
	)
end

--[[
	THE FENCES ARE THE ONE PART OF `Planting` THAT MUST NOT BE THINNED. They are the only planting
	doing LAYOUT work — they suggest the alley walls and field edges §5's sightline rule depends on —
	and they were the specific thing the plan told Phase 7 to leave alone.
]]
check(
	"all six fence runs survive",
	select(2, string.gsub(builder, 'Name = "Fence_', "")) == 6,
	`{select(2, string.gsub(builder, 'Name = "Fence_', ""))} fence run(s); the plan names six and forbids thinning them`
)

--[[
	THE GRAVE CANDLES AND CONTAINER BANDS MUST STAY EMISSIVE GEOMETRY. Eight grave lights alone would
	be a 57% overspend of the whole map's light budget, and the builder asserts zero dressing lights —
	so a PointLight here does not degrade the map, it fails the build.
]]
check(
	"the builder still asserts zero dressing lights",
	string.find(builder, "dressLights", 1, true) ~= nil,
	"C30 rule 2's guard was removed; nothing now fails the build on a dressing PointLight"
)

if failures > 0 then
	error(`{failures} barrio-budget assertion(s) failed`, 0)
end

print(`  PASS  barrio-budget: {checked} assertions over the hero zone's authored geometry`)
