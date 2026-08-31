--!strict
--[[
	THE GENERATED MESH REGISTRY — the only durable record of Phase 5's work.

	Every mesh here was minted by `generate_mesh` and lives in the PLACE FILE, which is gitignored,
	binary and unsearchable. `git log` will never contain these ids. If this block is lost, the
	geometry is unrecoverable without regenerating all eight props — which is why each row also carries
	the `Prompt` it was generated from.

	THE TRIANGLE BUDGET IS THE ONE HARD NUMBER. §5's mobile budget is non-negotiable and 60% of players
	are on a phone. The asset-pipeline skill's rule is 1,500–3,000 per prop and up to 6,000 for a single
	hero, so eight props cap at 27,000. That ceiling is summed here rather than trusted to a comment.
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

check("the ASSETS registry block is present", block ~= nil)

if block == nil then
	error("1 barrio-assets assertion(s) failed", 0)
end

local loader = loadstring or load
local assets = (assert(loader(`{block}\nreturn ASSETS`, "assets")) :: any)()

check("the registry carries a Meshes list", type(assets.Meshes) == "table")
check(
	"all eight hero meshes are recorded",
	#assets.Meshes == 8,
	`{#assets.Meshes} row(s); the shortlist names eight`
)

local TRI_CEILING = 27000
local totalTris = 0
local ids: { [string]: boolean } = {}

for index, entry in assets.Meshes do
	local label = tostring(entry.Id or `row {index}`)

	check(`{label} names an id`, type(entry.Id) == "string" and #entry.Id > 0)
	check("no two mesh rows share an id", ids[entry.Id] ~= true, `{label} appears twice`)
	ids[entry.Id] = true

	--[[
		A PLACEHOLDER ID IS THE FAILURE THIS CATCHES. `rbxassetid://0` and an empty string both look
		like a filled-in row and both load nothing. A regex on the shape alone would pass them, which
		is why the zero case is called out separately.
	]]
	check(
		`{label} has a real asset id`,
		type(entry.Asset) == "string" and string.match(entry.Asset, "^rbxassetid://%d+$") ~= nil,
		`Asset = {tostring(entry.Asset)}`
	)
	check(
		`{label}'s asset id is not a placeholder`,
		entry.Asset ~= "rbxassetid://0" and entry.Asset ~= "rbxassetid://",
		`{label} would generate nothing and leave a hole where its prop was`
	)
	check(
		`{label} has a real texture id`,
		type(entry.Texture) == "string" and string.match(entry.Texture, "^rbxassetid://%d+$") ~= nil,
		`Texture = {tostring(entry.Texture)} — an untextured mesh reads as flat grey`
	)
	check(
		`{label} records the prompt it was generated from`,
		type(entry.Prompt) == "string" and #entry.Prompt > 0,
		"without the prompt a lost asset cannot be regenerated"
	)
	check(
		`{label} stays inside the per-prop triangle rule`,
		type(entry.Tris) == "number" and entry.Tris >= 12 and entry.Tris <= 6000,
		`Tris = {tostring(entry.Tris)}; props are 1500-3000 and one hero may reach 6000`
	)

	totalTris += (if type(entry.Tris) == "number" then entry.Tris else 0)
end

check(
	`the eight meshes total no more than {TRI_CEILING} triangles`,
	totalTris <= TRI_CEILING,
	`{totalTris} requested — §5's mobile budget is non-negotiable and 60% of players are on a phone`
)

--[[
	ONLY ONE MESH MAY SPEND THE HERO BUDGET. Two 6,000-triangle props is how a budget that "totals
	under the ceiling" still ships a scene that stutters on the phone standing between them.
]]
local heroes = 0

for _, entry in assets.Meshes do
	if type(entry.Tris) == "number" and entry.Tris > 3000 then
		heroes += 1
	end
end

check(
	"at most one mesh exceeds the 3,000 prop budget",
	heroes <= 1,
	`{heroes} meshes over 3000 triangles`
)

--[[
	A ROW THAT IS NEVER PLACED IS NOT A DEFECT, BUT IT MUST BE DELIBERATE. The chapel is recorded at
	`Placed = 0` on purpose — it is an enterable interior holding two search containers, and a solid
	generated shell over it would bury them. Requiring the field to EXIST is what stops a row being
	silently forgotten rather than knowingly parked.
]]
for _, entry in assets.Meshes do
	check(
		`{tostring(entry.Id)} declares how many instances it places`,
		type(entry.Placed) == "number" and entry.Placed >= 0,
		"Placed is missing; a row nobody places should say so explicitly"
	)
end

--[[
	EVERY PLACED MESH MUST ACTUALLY BE CALLED FOR. A row in the registry that no `mesh()` call
	references is an asset paid for and never used, and the registry is the only place it would ever
	show up — the map itself simply would not have it.
]]
local unreferenced = {}

--[[
	THE REGISTRY BLOCK IS CUT OUT BEFORE SEARCHING, and both simpler versions of this were wrong.

	Searching for the literal `mesh("Banana"` misses every call StyLua has split across lines — which
	is most of them, since the calls take seven arguments. Searching the whole file for `"Banana"`
	instead always succeeds, because the registry row that declares the id contains it: the check would
	pass by finding the very row it is trying to prove is used.

	So the declaration is removed and only the rest of the builder is searched.
]]
local body = string.gsub(builder, "%-%-#ASSETS%-BEGIN.-%-%-#ASSETS%-END", "")

for _, entry in assets.Meshes do
	if entry.Placed > 0 and not string.find(body, `"{entry.Id}"`, 1, true) then
		table.insert(unreferenced, tostring(entry.Id))
	end
end

check(
	"every mesh with Placed > 0 is referenced by a mesh() call",
	#unreferenced == 0,
	`never placed: {table.concat(unreferenced, ", ")}`
)

--[[
	THE RIG MESHES, AND THEIR OWN CEILING SEPARATE FROM THE PROPS' ON PURPOSE.

	A prop mesh is placed once or twice and sits in fog at 200 studs. A rig mesh is placed THREE times
	and one of them is standing next to the player, at night, being stared at — because §4.5's whole
	deduction is "which cat". They are not interchangeable triangles, and one shared sum would let a
	cheap prop pass pay for an expensive rig with nothing failing.

	UNTIL THIS SUITE LEARNED TO COUNT THEM, THE RIGS WERE SPENT AND UNBUDGETED. Four generated meshes
	at sixteen instances existed only as asset ids inside `AmbientService.FORM_LOOKS`, which no check
	reads. §5's mobile budget is called non-negotiable and half of what was drawn was invisible to it.
]]
local RIG_TRI_CEILING = 9000
local RIG_DRAWN_CEILING = 27000

local perForm = tonumber(
	string.match(fs.readFile("src/shared/Config.luau"), "\n\t\tPerForm = (%d+),")
) :: number

check("Config.Ambient.PerForm parses", perForm ~= nil and perForm > 0, tostring(perForm))

check("the registry carries a RigMeshes list", type(assets.RigMeshes) == "table")
check(
	"all six camouflage forms have a rig mesh",
	#assets.RigMeshes == 6,
	`{#assets.RigMeshes} row(s); Types.CamouflageForm names six`
)

local rigTris = 0
local rigDrawn = 0

for _, entry in assets.RigMeshes do
	local label = tostring(entry.Id)

	check(
		`{label} records a real asset id`,
		type(entry.Asset) == "string" and string.match(entry.Asset, "^rbxassetid://%d+$") ~= nil,
		tostring(entry.Asset)
	)
	check(
		`{label} records a real texture id`,
		type(entry.Texture) == "string" and string.match(entry.Texture, "^rbxassetid://%d+$") ~= nil,
		tostring(entry.Texture)
	)
	check(
		`{label} records the prompt it was generated from`,
		type(entry.Prompt) == "string" and #entry.Prompt > 0,
		"the meshes live in the gitignored place file; the prompt is the only way back"
	)
	check(
		`{label} is within the per-rig budget`,
		type(entry.Tris) == "number" and entry.Tris >= 12 and entry.Tris <= 2000,
		`Tris = {tostring(entry.Tris)}; eighteen rigs are on screen at once`
	)
	check(
		`{label} records how many are spawned`,
		entry.Instances == perForm,
		`Instances = {tostring(entry.Instances)}, Config.Ambient.PerForm = {perForm}`
	)

	rigTris += (if type(entry.Tris) == "number" then entry.Tris else 0)
	rigDrawn += (if type(entry.Tris) == "number" and type(entry.Instances) == "number"
		then entry.Tris * entry.Instances
		else 0)
end

check(
	`the six rig meshes total under {RIG_TRI_CEILING}`,
	rigTris <= RIG_TRI_CEILING,
	`{rigTris} requested`
)
check(
	`the rig INSTANCES draw under {RIG_DRAWN_CEILING}`,
	rigDrawn <= RIG_DRAWN_CEILING,
	`{rigDrawn} triangles across {perForm} of each form — this is the number a phone pays`
)

--[[
	AND THE IDS MUST MATCH THE SERVICE. The registry is the durable RECORD; `FORM_LOOKS` is what
	actually loads. Two copies of an asset id is one copy too many, and the failure is silent: the
	budget suite would happily certify a mesh the game never loads.
]]
local service = fs.readFile("src/server/Services/AmbientService.luau")

for _, entry in assets.RigMeshes do
	check(
		`AmbientService loads the registered {entry.Id} mesh`,
		string.find(service, tostring(entry.Asset), 1, true) ~= nil,
		tostring(entry.Asset)
	)
	check(
		`AmbientService loads the registered {entry.Id} texture`,
		string.find(service, tostring(entry.Texture), 1, true) ~= nil,
		tostring(entry.Texture)
	)
end

if failures > 0 then
	error(`{failures} barrio-assets assertion(s) failed`, 0)
end

print(
	`  PASS  barrio-assets: {checked} assertions over {#assets.Meshes} props ({totalTris} tris) `
		.. `and {#assets.RigMeshes} rigs ({rigDrawn} drawn)`
)
