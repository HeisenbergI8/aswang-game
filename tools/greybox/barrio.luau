--[[
	BARRIO — the C17 greybox, as a script rather than as a place file.

	═══ WHY THIS IS ON DISK AND THE MAP IS NOT ═══════════════════════════════════

	The place file is gitignored: binary, merge-hostile, and backed up only by Roblox's cloud version
	history. So the map itself cannot be reviewed in a diff, cannot be reverted with git, and cannot
	tell you what changed between two playtests.

	The LAYOUT can. This file is the layout — every coordinate, every zone, every tag — and running it
	produces the map. That buys three things a hand-built greybox does not have:

	  · a diff. "we moved the chapel 40 studs south" is a line, not a memory
	  · idempotence. It destroys `workspace.Barrio` and rebuilds, so re-running after an edit
	    applies the edit rather than layering a second barrio on top of the first
	  · a measurable target. §5 asks for a ~35-second crossing, and `SCALE` is the one number that
	    moves it. `tools/greybox/measure.luau` walks it with PathfindingService and reports seconds

	It is NOT game code and does not live under `src/`. Nothing requires it, Rojo does not sync it, and
	it runs exactly once per edit — from Studio's command bar, or through MCP `execute_luau` in EDIT
	mode. Run it in Edit, never in Play: Play-mode geometry is discarded when you stop.

	═══ WHAT THE SERVICES DEMAND OF THE MAP ══════════════════════════════════════

	This script's real contract is with four services, all of which discover the map by CollectionService
	tag and identify things by part NAME. Every one of them warns loudly and unconditionally when the
	map fails it, because the alternative symptom is a player reporting "the game is boring".

	  SearchContainer ×15  SearchService.discoverPool  unique Names; Config.Search.ContainerCount
	  SaltSpawn    × 6  ItemService.discoverPool      Config.Salt.PouchPoolSize
	  AmbientSpawn ×16  AmbientService spawn points   Config.Ambient.PerForm x 4; ZERO = ring fallback
	  TrialSpawn   × 1  TrialService.trialSpawn       where a trial player is placed
	  TrialChase   × 1  TrialService (C22 rig)        where the scripted rig appears
	  MapLight     ×14  PerformanceController         SCENERY lights only — never a gameplay tell
	                    12 street lanterns + the trial corner's + the chapel candle glow
	  TaskPoint    × 2  TrialService.trialPoints      attribute `TrialOnly = true` — see the corner

	THIS TABLE WAS WRONG FOR THE WHOLE OF V01–V07 AND NOTHING COULD HAVE TOLD YOU. It described a
	contract with two services that V01 deleted, and it listed neither of the two tags v2.0 actually
	needs. The builder is outside `src/`, so `lint`, `analyze`, `fmt:check` and all five repo checks
	skip it; the map it builds is not in git. A stale comment here is the most expensive kind of stale
	comment in the repo, because it is the only description of the contract that anyone reads.
	`tests/barrio-legacy.test.luau` and `tests/barrio-receipt.test.luau` now hold it to this.

	TWO OF THESE FAIL SILENTLY AND BOTH ARE ASSERTED AT THE FOOT OF THIS FILE:

	  · ZERO `SearchContainer` is a barrio with nothing to do in it. Searching IS v2.0 (§4.4), and
	    `SearchService`'s own comment names the symptom — "there is nothing to do and nobody knows why".
	  · ZERO `AmbientSpawn` does not disable ambient life, it puts all sixteen animals in a RING at the
	    origin. `AmbientService`'s fallback fires only on zero tagged parts, so a partial list is worse
	    than an empty one: it looks deliberate.

	`TrialOnly` IS AN EXCLUSION AND IT IS KEPT THOUGH ITS ORIGINAL REASON IS GONE. The trial's two
	points carry the `TaskPoint` tag, which after V01 only `TrialService` reads. Under v1.3 the
	attribute stopped a round drawing an objective into a walled corner nobody could reach; that
	failure died with the task system. It stays because it costs nothing and it is the only marker
	saying which two points are sealed off from the barrio proper.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local ROOT = "Barrio"

--[[
	THE ONE NUMBER THAT MOVES THE CROSSING TIME.

	§5's size target is ~35 seconds end to end at the default WalkSpeed of 16, which is ~560 studs of
	WALKED path — not straight-line distance, because buildings make the walk longer than the diagonal.
	Every coordinate below is multiplied by this, so re-scaling the whole barrio is one edit and one
	re-run rather than a hundred.

	New devs build maps 3× too big and the game dies of players never meeting each other (§5, and the
	build plan says it twice). Measure before believing: `measure.luau` reports the real number.

	THIS VALUE WAS MEASURED, NOT CHOSEN, AND IT TOOK THREE READINGS BECAUSE IT IS NOT LINEAR.

	The layout below is authored in scale-1 units. `measure.luau` walked it at 25.1s — too small — so
	1.35 should have given 33.9s and gave 30.2s instead. The scaling of a WALK is sub-linear: widening
	the map also widens every doorway and every gap between buildings, and the navmesh answers by
	finding straighter routes that the tighter version did not offer. Estimating from one reading
	would have shipped a map 4 seconds shorter than the arithmetic promised.

	1.55 is the third reading, and it puts the worst crossing near the middle of the 30–40s band rather
	than on its floor. The middle matters more than the number: 30.2s was the WORST pair, so the
	typical crossing was well under it, and §5's failure mode is one-directional — a map that is
	slightly tight still has players meeting each other, and a map that is slightly big does not.
]]
local SCALE = 1.55

-- Playable half-extent. Walls sit just inside it; nothing is placed beyond.
local HALF = 180
local WALL_H = 18

-- The road network, in studs from the centre. See the ROADS section for why these three numbers
-- guarantee loops rather than dead ends.
local PLAZA = 45 -- half-width of the central plaza
local RING = 130 -- centreline of the square ring road
local ROAD_W = 18
local ALLEY_W = 8

--[[
	C30 — MATERIALS ALONGSIDE THE COLOURS.

	The greybox painted everything `Concrete` because `box` had one default and C17's deliverable was
	the LAYOUT. §5's art strategy is that darkness and fog hide geometry, and the asset-pipeline skill
	names the corollary: a correct material on a plain Part reads better in fog than a detailed mesh
	with a plastic finish. This is the cheapest half of the dressing and it moves nothing.
]]
local GREY = Color3.fromRGB(112, 112, 108)
local ROAD = Color3.fromRGB(88, 86, 82)
local PLAZA_C = Color3.fromRGB(124, 122, 116)
local WOOD = Color3.fromRGB(96, 84, 68)
local THATCH = Color3.fromRGB(120, 104, 74)

-- Declared here rather than with the dressing palette below, because `building()` runs long before
-- that block exists. `BAMBOO` down there is the same colour for the same reason; this is its twin.
local BAMBOO_C = Color3.fromRGB(104, 118, 72)
local STONE = Color3.fromRGB(104, 104, 104)
local GRASS = Color3.fromRGB(74, 92, 58)
local ANCHOR_C = Color3.fromRGB(70, 90, 120)

-- Seeded, so two runs of the same file produce the same barrio. The rice field is the only thing that
-- uses it; a jittered field that moved every run would make "did the layout change?" unanswerable.
local rng = Random.new(20260816)

--#ASSETS-BEGIN
--[[
	THE ASSET REGISTRY — the one thing in this file that is NOT reproducible by re-running it.

	Every MaterialVariant and every generated mesh is minted by Studio and lives in the PLACE FILE,
	which is gitignored, binary and unsearchable. The asset-pipeline skill's instruction is exact:
	"Record every asset ID you insert somewhere durable — the place file is not searchable and
	`git log` will not have it." This block is that durable place.

	IT IS ALSO A TEST FIXTURE. `tests/barrio-materials.test.luau` and `tests/barrio-assets.test.luau`
	slice this block out between the two sentinels and `loadstring` it into a real table. So the
	registry cannot drift from the file that uses it without the tree going red, which is the only
	reason a hand-maintained registry is trustworthy at all.

	DO NOT REFORMAT THE TWO SENTINEL LINES that bracket this block. The suites slice between them.
	They are deliberately not spelled out here: an earlier draft quoted the closing sentinel inside
	this very comment, and the non-greedy slice stopped on the quotation instead of the real one,
	handing `loadstring` an unfinished comment. A sentinel must not appear in the region it delimits.
]]
local ASSETS = {
	--[[
		THE SURFACE VOCABULARY — fourteen generated PBR materials, one per distinct surface the barrio
		has. `Id` is what the builder asks for by name, `Base` the stock `Enum.Material` the variant was
		generated against, and `Variant` the live `MaterialVariant` in `MaterialService`.

		THESE ARE REAL GENERATED MATERIALS, NOT STOCK ONES. Each carries its own uploaded Color, Normal,
		Roughness and Metalness maps — the four ids recorded per row. That is the difference between a
		part that looks like Roblox's concrete and one that looks like a cracked barangay court slab.

		`generate_material` IS INTERMITTENT, WHICH IS WORTH KNOWING BEFORE YOU CONCLUDE IT IS BROKEN.
		The first four attempts in this project all failed with the same internal error
		(`MaterialGenTool:649: invalid argument #2 to 'assert'`), which read as a dead tool. A later
		session generated thirteen of fourteen first time, and the fourteenth succeeded on one retry.
		If it fails, retry before redesigning around it.

		THE TOOL RETURNS FOUR OPTIONS PER REQUEST, nested under `MaterialService.AssistantMaterials`.
		A `MaterialVariant` only resolves when it is a DIRECT child of `MaterialService`, so one of each
		four was promoted and the spares deleted. Left nested in that folder, a variant binds nothing at
		all — silently, with the part keeping its stock base material, which is this file's favourite
		failure mode and the reason `paint()` exists.

		THE MAP IDS ARE THE DURABLE RECORD, for the same reason the mesh asset ids are: the variants
		live in the place file, which is gitignored, binary and unsearchable. `git log` will never have
		them. Lose this block and every surface falls back to its stock base material.
	]]
	Materials = {
		{ Id = "Nipa", Base = "Grass", Pattern = "Organic", Prompt = "weathered nipa palm thatch, overlapping dried leaf shingles, sun-bleached grey-brown with fresher tan repair patches", Variant = "BarrioNipa", Color = "rbxassetid://108873044154730", Normal = "rbxassetid://95916432346873", Rough = "rbxassetid://135680787932501", Metal = "rbxassetid://140716985042697" },
		{ Id = "Sawali", Base = "WoodPlanks", Pattern = "Regular", Prompt = "woven split-bamboo sawali wall panel, diagonal plait, dry and splitting", Variant = "BarrioSawali", Color = "rbxassetid://137939066534199", Normal = "rbxassetid://95798484897338", Rough = "rbxassetid://126897870024037", Metal = "rbxassetid://102925602219852" },
		{ Id = "Bamboo", Base = "Wood", Pattern = "Organic", Prompt = "cut bamboo poles, nodes and vertical grain, green fading to straw", Variant = "BarrioBamboo", Color = "rbxassetid://107432787497803", Normal = "rbxassetid://116873965026644", Rough = "rbxassetid://78535808997944", Metal = "rbxassetid://132674140450464" },
		{ Id = "CourtSlab", Base = "Concrete", Pattern = "Regular", Prompt = "hand-troweled outdoor court concrete, hairline cracks, patched repairs, faded paint lines", Variant = "BarrioCourtSlab", Color = "rbxassetid://106122569340322", Normal = "rbxassetid://74847761901764", Rough = "rbxassetid://72374742602072", Metal = "rbxassetid://120212410107846" },
		{ Id = "HollowBlock", Base = "Brick", Pattern = "Regular", Prompt = "unrendered CHB hollow block wall, mortar lines, grey and porous", Variant = "BarrioHollowBlock", Color = "rbxassetid://70583548972308", Normal = "rbxassetid://132975197419680", Rough = "rbxassetid://120576848126545", Metal = "rbxassetid://139964456952937" },
		{ Id = "GIRoof", Base = "CorrodedMetal", Pattern = "Regular", Prompt = "corrugated galvanised iron sheet, rust streaking down the corrugations from the nail heads", Variant = "BarrioGIRoof", Color = "rbxassetid://95841156096652", Normal = "rbxassetid://134110095670870", Rough = "rbxassetid://128976136520561", Metal = "rbxassetid://83669620260260" },
		{ Id = "Tarp", Base = "Fabric", Pattern = "Regular", Prompt = "faded polyethylene tarpaulin, creased, sun-bleached, frayed grommets", Variant = "BarrioTarp", Color = "rbxassetid://83753027347167", Normal = "rbxassetid://138718330382751", Rough = "rbxassetid://107163346649451", Metal = "rbxassetid://102132402856303" },
		{ Id = "WetEarth", Base = "Mud", Pattern = "Organic", Prompt = "wet packed dirt path, tyre ruts, puddled and uneven", Variant = "BarrioWetEarth", Color = "rbxassetid://119654707766458", Normal = "rbxassetid://134870826698674", Rough = "rbxassetid://102594483926645", Metal = "rbxassetid://133704791027744" },
		{ Id = "DryEarth", Base = "Ground", Pattern = "Organic", Prompt = "dry compacted barrio earth, scuffed bare ground between buildings", Variant = "BarrioDryEarth", Color = "rbxassetid://139741873853050", Normal = "rbxassetid://73531310450058", Rough = "rbxassetid://129986608957807", Metal = "rbxassetid://92525933764445" },
		{ Id = "Paddy", Base = "LeafyGrass", Pattern = "Organic", Prompt = "rice paddy stalks, dense vertical blades, wet at the root", Variant = "BarrioPaddy", Color = "rbxassetid://97260815498079", Normal = "rbxassetid://84810786479225", Rough = "rbxassetid://117954264724182", Metal = "rbxassetid://124016757579868" },
		{ Id = "Whitewash", Base = "Plaster", Pattern = "Regular", Prompt = "whitewashed rendered concrete, chalky, streaked with rain and mildew", Variant = "BarrioWhitewash", Color = "rbxassetid://106384944404034", Normal = "rbxassetid://93275637616693", Rough = "rbxassetid://80834692996214", Metal = "rbxassetid://109887196819914" },
		{ Id = "RustedSteel", Base = "CorrodedMetal", Pattern = "Regular", Prompt = "rusted steel post, pitted, flaking paint over orange oxide", Variant = "BarrioRustedSteel", Color = "rbxassetid://123108516534979", Normal = "rbxassetid://96709395359102", Rough = "rbxassetid://92016084843561", Metal = "rbxassetid://136006039352924" },
		{ Id = "Cloth", Base = "Fabric", Pattern = "Regular", Prompt = "faded cotton bunting, bruised pink and sickly cream, a year in the sun", Variant = "BarrioCloth", Color = "rbxassetid://131379210087991", Normal = "rbxassetid://99175893829691", Rough = "rbxassetid://106717344257550", Metal = "rbxassetid://93309980918532" },
		{ Id = "Sack", Base = "Sand", Pattern = "Organic", Prompt = "jute rice sack, coarse woven fibre, dusty", Variant = "BarrioSack", Color = "rbxassetid://122565081261005", Normal = "rbxassetid://78245490899431", Rough = "rbxassetid://80753268388718", Metal = "rbxassetid://105919758313040" },
	},

	--[[
		MESHES — generated by `generate_mesh`, which unlike `generate_material` works in this build.

		`Asset` and `Texture` are Studio-minted ids and they are the ONLY durable record of this work:
		the meshes live in the place file, which is gitignored, binary and unsearchable, and `git log`
		will never have them. Lose this block and the geometry is unrecoverable without regenerating
		every prop from its prompt.

		`Tris` is the maxTriangles the mesh was REQUESTED at, which is the budget line
		`tests/barrio-assets.test.luau` sums. `Placed` records how many instances the builder makes,
		and `Replaces` the part count each one removes — the two numbers that decide whether a mesh is
		a budget win or a budget cost.
	]]
	Meshes = {
		{ Id = "GraveMarker", Asset = "rbxassetid://102652084623425", Texture = "rbxassetid://138946538788851", Tris = 1500, Placed = 8, Replaces = 16, Prompt = "weathered concrete grave marker cross, tilted, moss-stained, chipped" },
		{ Id = "Tricycle", Asset = "rbxassetid://138513457644055", Texture = "rbxassetid://130404028419497", Tris = 3000, Placed = 2, Replaces = 2, Prompt = "Philippine tricycle, motorcycle with welded sidecar cab, tin roof, rusted" },
		{ Id = "Banana", Asset = "rbxassetid://73194128927755", Texture = "rbxassetid://94692050392434", Tris = 1500, Placed = 12, Replaces = 60, Prompt = "banana plant, fibrous trunk, broad drooping torn leaves" },
		{ Id = "SariSari", Asset = "rbxassetid://124419709324438", Texture = "rbxassetid://95326402783318", Tris = 2500, Placed = 4, Replaces = 0, Prompt = "sari-sari store front, barred slat window, hanging sachets, tarp awning" },
		{ Id = "WellPump", Asset = "rbxassetid://131852474817632", Texture = "rbxassetid://139752002527040", Tris = 2000, Placed = 1, Replaces = 1, Prompt = "hand water pump and low stone well ring, rusted iron, mossy concrete" },
		{ Id = "Scarecrow", Asset = "rbxassetid://96879056842732", Texture = "rbxassetid://120170772317000", Tris = 1500, Placed = 2, Replaces = 10, Prompt = "scarecrow, crossed bamboo poles, ragged shirt, straw hat, leaning" },
		{ Id = "KuboShell", Asset = "rbxassetid://99633808685983", Texture = "rbxassetid://94282992515102", Tris = 3000, Placed = 2, Replaces = 0, Prompt = "bahay kubo, stilt house, sawali walls, steep nipa roof, open undercroft" },
		--[[
			THE CHAPEL IS RECORDED AND DELIBERATELY NOT PLACED — `Placed = 0`.

			It generated well, and dropping it in would break the game. The chapel is one of §5's five
			enterable interiors and it holds TWO of the fifteen search containers; a solid exterior
			shell over it occludes the doorway the containers are reached through, and a hollow one
			would need collision authored by hand. The greybox chapel is a real room with two doors,
			which is worth more than a better-looking exterior that cannot be entered.

			It stays in the registry because the asset exists and the id is the only record of it. A
			later chunk that splits the chapel into shell-plus-interior can use it without paying for
			generation again.
		]]
		{ Id = "Chapel", Asset = "rbxassetid://72865002641738", Texture = "rbxassetid://87324092289695", Tris = 6000, Placed = 0, Replaces = 0, Prompt = "rural barangay chapel, concrete visita, corrugated roof, bell arch, whitewashed" },
	},
}
--#ASSETS-END

--[[
	PAINT A PART — and the reason this is a function rather than two assignments.

	A MaterialVariant does nothing unless BOTH `Material` and `MaterialVariant` are set, and it fails
	SILENTLY: no error, no warning, and a plastic-looking part among eleven hundred of them. Across a
	map this size that is not findable by eye. This helper makes the pair impossible to half-apply, and
	it warns when asked for a variant the registry has never heard of — the typo case, which a
	screenshot would not catch either.

	ALWAYS `paint()` LAST. Setting a part's `Material` after the variant is bound silently unbinds it,
	because the variant only applies while the part's base material matches the one it was generated
	against.
]]
local SURFACE: { [string]: { Base: Enum.Material, Variant: string? } } = {}

for _, entry in ASSETS.Materials do
	-- Indexing `Enum.Material` by a runtime string has no typed form. Contained to this one line.
	SURFACE[entry.Id] = { Base = (Enum.Material :: any)[entry.Base], Variant = entry.Variant }
end

local function paint(p: BasePart, id: string): BasePart
	local surface = SURFACE[id]

	if surface == nil then
		warn(
			`[barrio] surface "{id}" is not in the ASSETS registry — {p.Name} keeps its base material. `
				.. `Add the row, or fix the name.`
		)

		return p
	end

	--[[
		ORDER IS LOAD-BEARING. `Material` first, then the variant: a variant only applies while the
		part's base material matches the one it was generated against, so assigning `Material` after
		the variant silently unbinds it. That is also why nothing outside this function may set either
		property — `tests/barrio-materials.test.luau` enforces it.
	]]
	p.Material = surface.Base

	if surface.Variant ~= nil then
		p.MaterialVariant = surface.Variant
	end

	return p
end

local root: Folder

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x * SCALE, y, z * SCALE)
end

--[[
	PLACE A GENERATED MESH.

	`MeshPart.MeshId` IS NOT SCRIPT-WRITABLE — probed directly in this place, and it fails SILENTLY:
	the assignment raises "lacking capability NotAccessible" and leaves the property as `""`, which
	would give a zero-size invisible part and a build that reports success while omitting the prop.
	`AssetService:CreateMeshPartAsync` is the supported route and is what this uses.

	IT YIELDS, which is fine here: this file already fetches its own source over HTTP inside
	`execute_luau`, so yielding in this context is established practice rather than a new risk.

	A FAILED LOAD MUST NOT BE SILENT. If the asset is gone — moderated, or the place rolled back — the
	prop it replaced is already deleted, so a quiet failure leaves a hole in the map with nothing to
	explain it. This warns loudly and returns nil, and the caller leaves the boxes alone.
]]
local MESH_BY_ID: { [string]: { Asset: string, Texture: string } } = {}

for _, entry in ASSETS.Meshes do
	MESH_BY_ID[entry.Id] = { Asset = entry.Asset, Texture = entry.Texture }
end

local function mesh(id: string, name: string, cx: number, cy: number, cz: number, size: Vector3, parent: Instance?): MeshPart?
	local entry = MESH_BY_ID[id]

	if entry == nil then
		warn(`[barrio] mesh "{id}" is not in the ASSETS registry — nothing placed for {name}.`)

		return nil
	end

	local ok, result = pcall(function()
		return game:GetService("AssetService"):CreateMeshPartAsync(entry.Asset)
	end)

	if not ok or result == nil then
		warn(
			`[barrio] mesh "{id}" ({entry.Asset}) failed to load for {name} — {tostring(result)}. `
				.. `The prop it replaces is NOT rebuilt; expect a hole here.`
		)

		return nil
	end

	local part = result :: MeshPart

	part.Name = name
	part.Size = size
	part.Position = v(cx, cy, cz)
	part.TextureID = entry.Texture
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent or root

	return part
end

local function box(
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	colour: Color3,
	parent: Instance?
): Part
	local p = Instance.new("Part")

	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(math.max(sx * SCALE, 0.2), sy, math.max(sz * SCALE, 0.2))
	p.Position = v(cx, cy, cz)
	p.Color = colour
	p.Material = Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or root

	return p
end

-- A road is a thin slab painted on the ground. It carries no collision and no gameplay meaning — it
-- exists so a screenshot of the layout is readable and so a human walking it can tell a street from a
-- courtyard. Layout legibility is the entire deliverable at this milestone.
local function road(name: string, cx: number, cz: number, sx: number, sz: number, parent: Instance)
	local p = box(name, cx, 0.05, cz, sx, 0.1, sz, ROAD, parent)

	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false

	--[[
		Packed dirt. A barrio street is not paved. `DryEarth` is the compacted scuffed ground between
		buildings; the plaza and the court get their own harder surfaces below, and the difference
		between a dirt street and a concrete slab is one of the few readable ones at ClockTime 0.
	]]
	paint(p, "DryEarth")
end

--[[
	A building, greybox-style: floor, four walls, roof, and a door gap on each named side.

	`doors` is a set of "N"/"S"/"E"/"W". A side with a door is built as two wall segments with a gap
	between them; a side without is one slab. An empty `doors` set produces a sealed block — which is
	what the four non-enterable kubo are, and they exist for silhouette and sightline breaking rather
	than for interiors.
]]
local function building(
	name: string,
	cx: number,
	cz: number,
	w: number,
	d: number,
	height: number,
	doors: { [string]: boolean },
	wallColour: Color3,
	wallMaterial: Enum.Material?,
	--[[
		OPT-IN, because `building()` also builds the chapel and a chapel on stilts is wrong. A visita
		is concrete on the ground; a bahay kubo stands on posts. One boolean keeps both correct
		without a second helper.
	]]
	stilted: boolean?
): Folder
	local folder = Instance.new("Folder")

	folder.Name = name
	folder.Parent = root

	local t = 2 -- wall thickness
	local door = 10
	local hw, hd = w / 2, d / 2

	local floor = box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
	local roof = box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)

	--[[
		ONE EDIT, SIXTEEN PARTS. Every kubo and the chapel are built through this helper, so the roof
		and floor of all eight buildings change here rather than in eight per-zone edits. Prefer the
		helper over per-part work wherever the helper exists: it is fewer lines and it cannot miss one.

		Nipa thatch has no stock material and `Grass` remains the closest read — fibrous, directionless
		grain is all that survives at distance and in fog. A bamboo floor beats plank: a real bahay kubo
		floor is split bamboo laid in strips, and the grain runs the right way for it.
	]]
	paint(floor, "Bamboo")
	paint(roof, "Nipa")

	--[[
		THE STILTS AND THE SILONG — the bahay kubo's entire silhouette, in four parts.

		A house on posts with an open undercroft reads instantly as Filipino, and it reads at DISTANCE,
		which is the only way anything is read in this fog.

		THEY ARE DECORATION AND THE FLOOR DOES NOT MOVE. This is the one place in the realism pass
		where §5's layout rule and the real silhouette genuinely conflict, and the layout rule wins.
		A floor raised to the real post height with collidable walls around it makes the interior
		unreachable without a ramp; a ramp is a navmesh change; a navmesh change moves the crossing
		time §5 measures and would put `Container_KuboNW_Chest` behind a step. So the posts stand
		AROUND a ground-level floor. At night, under a roof overhang, the difference is not visible —
		and the alternative is trading a measured guarantee for a detail nobody can see.

		THE POSTS DO NOT COLLIDE. `prop()` guarantees that, and the builder asserts zero dressing
		colliders at the foot of this file. A collidable post beside a doorway would narrow it.
	]]
	if stilted then
		--[[
			`box()` RATHER THAN `prop()`, AND THAT IS NOT A STYLE CHOICE. `prop`, `turn` and `lean` are
			declared with the C30 dressing helpers, hundreds of lines BELOW this function. Calling them
			from here compiles fine and dies at run time with "attempt to call a nil value" — which is
			exactly what the first version of this block did. `box` is in scope; the four extra
			property lines are the price.

			Sizes are in `box` units (multiplied by SCALE on the way out), the same units the floor and
			roof above use — not `prop` units, which pre-divide.
		]]
		local function decor(dname: string, dx: number, dy: number, dz: number, sx: number, sy: number, sz: number, colour: Color3): Part
			local q = box(dname, dx, dy, dz, sx, sy, sz, colour, folder)

			q.CanCollide = false
			q.CanQuery = false
			q.CanTouch = false
			q.CastShadow = false

			return q
		end

		for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			paint(
				decor(
					`{name}_Stilt{if corner[1] < 0 then "W" else "E"}{if corner[2] < 0 then "N" else "S"}`,
					cx + corner[1] * (w / 2 - 1.5),
					1.6,
					cz + corner[2] * (d / 2 - 1.5),
					0.5,
					3.2,
					0.5,
					BAMBOO_C
				),
				"Bamboo"
			)
		end

		--[[
			THE PITCH. A nipa roof is steep — it sheds monsoon rain, and that steepness is most of what
			separates the silhouette from a shed. The flat slab above keeps its job as the eaves; two
			leaning panels make the ridge over it.
		]]
		for _, sign in { -1, 1 } do
			local panel = decor(
				`{name}_Pitch{if sign < 0 then "N" else "S"}`,
				cx,
				height + 2.4,
				cz + sign * (d / 5),
				w + 4,
				0.5,
				d / 2 + 2,
				THATCH
			)

			panel.CFrame = panel.CFrame * CFrame.Angles(math.rad(sign * 32), 0, 0)
			paint(panel, "Nipa")
		end
	end

	--[[
		THE WALLS ARE THE LARGEST VISIBLE SURFACE IN THE MAP and they were stock until now. A kubo wall
		is woven split bamboo — `Sawali` — and the chapel's is painted hollow block, which is why the
		surface is chosen from the caller's material rather than hardcoded: `building()` makes both.
	]]
	local material = wallMaterial or Enum.Material.WoodPlanks
	local wallSurface = if wallMaterial == Enum.Material.Cobblestone then "HollowBlock" else "Sawali"

	local function side(tag: string, isNS: boolean, sign: number)
		local span = if isNS then w else d
		local cross = if isNS then hd else hw

		if not doors[tag] then
			if isNS then
				box(
					`{name}_Wall{tag}`,
					cx,
					height / 2,
					cz + sign * cross,
					span,
					height,
					t,
					wallColour,
					folder
				).Material =
					material
			else
				box(
					`{name}_Wall{tag}`,
					cx + sign * cross,
					height / 2,
					cz,
					t,
					height,
					span,
					wallColour,
					folder
				).Material =
					material
			end

			return
		end

		local segment = (span - door) / 2
		local offset = (door + segment) / 2

		for index, dir in { -1, 1 } do
			if isNS then
				box(
					`{name}_Wall{tag}{index}`,
					cx + dir * offset,
					height / 2,
					cz + sign * cross,
					segment,
					height,
					t,
					wallColour,
					folder
				).Material =
					material
			else
				box(
					`{name}_Wall{tag}{index}`,
					cx + sign * cross,
					height / 2,
					cz + dir * offset,
					t,
					height,
					segment,
					wallColour,
					folder
				).Material =
					material
			end
		end
	end

	side("N", true, -1)
	side("S", true, 1)
	side("E", false, 1)
	side("W", false, -1)

	--[[
		PAINTED AFTER THE SIDES ARE BUILT, not inside `side()`, because that function creates walls
		through three different branches (solid, split-for-a-door, and the door segments themselves)
		and painting in one branch silently leaves the others stock. Walking the folder catches all of
		them, including any a later edit adds.
	]]
	for _, piece in folder:GetChildren() do
		if piece:IsA("BasePart") and string.find(piece.Name, "_Wall") then
			paint(piece, wallSurface)
		end
	end

	return folder
end

--[[
	A lantern: a post and one warm PointLight.

	§5's mobile budget caps DYNAMIC LIGHTS AT ~8 VISIBLE AT ONCE and names many point lights the #1
	mobile FPS killer. Twelve exist, spread over 360 studs at range 26, so two or three are in view at
	any time — the cap is met by SPACING rather than by count, which is what lets the sightline rule
	("you should almost always be able to see *something*") hold at the same time.

	SINCE C27 THE SPACING IS BACKED BY A MECHANISM, and this tag is the whole contract for it.
	`MapLight` marks a light as SCENERY, which is the client's permission to switch it off:
	`PerformanceController` keeps the nearest `Config.Performance.MaxVisibleLights` minus the reserved
	few lit and darkens the rest, per client, by distance from that client's camera.

	WHAT MUST NEVER CARRY THIS TAG is the more important half. The Aswang's eye glow and a salt
	pouch's glow are TELLS — §4.3's warning and §4.6's counterplay — and they are protected by never
	being tagged rather than by a rule somebody could relax. Tag one of them here and the culler will
	obediently switch off the only warning a survivor gets.
]]
local function lantern(name: string, cx: number, cz: number, parent: Instance)
	local post = box(`{name}_Post`, cx, 4, cz, 1, 8, 1, WOOD, parent)
	local head = box(`{name}_Head`, cx, 8.4, cz, 2, 1.6, 2, Color3.fromRGB(200, 170, 110), parent)

	head.Material = Enum.Material.Neon
	post.CanCollide = true

	local light = Instance.new("PointLight")

	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 196, 120)
	light.Brightness = 1.6
	light.Range = 26
	light.Shadows = false
	light.Parent = head

	CollectionService:AddTag(light, "MapLight")
end

--[[
	A tagged anchor — the only parts in this file the SERVICES care about.

	Deliberately visible rather than invisible. A greybox is walked by a human deciding whether the
	layout works, and an invisible task point makes "is the spread right?" unanswerable by looking.
	C34 hides these behind real props; until then a coloured pad IS the affordance, alongside the one
	`TaskController` draws for the five that are live.
]]
local function anchor(
	name: string,
	tag: string,
	cx: number,
	cz: number,
	parent: Instance,
	attributes: { [string]: any }?
): Part
	-- POSITION SCALES, SIZE DOES NOT — the `/ SCALE` cancels the one `box` applies.
	--
	-- An anchor pad is not scenery, it is a reading of a Config range: 6 studs against
	-- `Tasks.PresenceRangeStuds` (9) and `Salt.PickupRangeStuds` (6). Letting it grow with the map
	-- would silently widen the affordance away from the number that actually governs it, and the pad
	-- would start promising a reach the server does not honour.
	local p = box(name, cx, 0.4, cz, 6 / SCALE, 0.8, 6 / SCALE, ANCHOR_C, parent)

	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false

	if attributes then
		for key, value in attributes do
			p:SetAttribute(key, value)
		end
	end

	CollectionService:AddTag(p, tag)

	return p
end

--------------------------------------------------------------------------------
-- TEARDOWN. Idempotence lives here: a re-run replaces the barrio rather than
-- stacking a second one on top of it, and the C09/C13 temp rigs go with it —
-- their own comments name C17 as the chunk that deletes them.
--------------------------------------------------------------------------------

--[[
	`Baseplate` is Roblox's stock part in a new place, and it is on this list because the barrio brings
	its own `Ground`. Leaving it would put two large collidable slabs at overlapping heights, which is
	a navmesh problem rather than a cosmetic one — pathfinding would have two surfaces to choose from.

	Named here rather than left implicit because an audit flagged it as silent scope: the other three
	entries are this project's own, and deleting something the engine created is the one line in this
	teardown a reader would not expect.
]]
for _, name in { ROOT, "TaskRig_TEMP", "SaltRig_TEMP", "Baseplate" } do
	local existing = workspace:FindFirstChild(name)

	if existing then
		existing:Destroy()
	end
end

root = Instance.new("Folder")
root.Name = ROOT
root.Parent = workspace

--------------------------------------------------------------------------------
-- GROUND AND PERIMETER
--------------------------------------------------------------------------------

local ground = box("Ground", 0, -1, 0, HALF * 2 + 16, 2, HALF * 2 + 16, GRASS)

-- The single largest surface in the map, so the cheapest square-stud of realism available.
paint(ground, "Paddy")

local walls = Instance.new("Folder")
walls.Name = "Perimeter"
walls.Parent = root

box("Wall_N", 0, WALL_H / 2, -HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_S", 0, WALL_H / 2, HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_E", HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)
box("Wall_W", -HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)

for _, wall in walls:GetChildren() do
	-- The barrio's edge reads as a rendered block wall rather than a castle. `Whitewash` is chalky and
	-- streaked, which at night is a pale band that tells you where the map stops without lighting it.
	paint(wall :: Part, "Whitewash")
end

--------------------------------------------------------------------------------
-- ROADS — the loop guarantee, and it is structural rather than a promise.
--
-- Four radial streets leave the plaza on the cardinals and run to the perimeter.
-- One square RING road at |x| = 130 / |z| = 130 crosses all four of them. That
-- alone means every radial reaches every other radial two ways round, so no
-- street can be a dead end.
--
-- Three ALLEYS then cut the inner blocks, each joining a radial to the ring:
-- north↔east, west↔south, south↔east. Each closes a third, tighter loop — §5's
-- "loops create chases, dead ends are unfair" — and each is 8 studs wide against
-- the streets' 18, so a chase through one feels different from a chase down a road.
--------------------------------------------------------------------------------

local roads = Instance.new("Folder")
roads.Name = "Roads"
roads.Parent = root

road("Plaza", 0, 0, PLAZA * 2, PLAZA * 2, roads)
local plazaSlab = roads:FindFirstChild("Plaza") :: Part
plazaSlab.Color = PLAZA_C
paint(plazaSlab, "CourtSlab")

local reach = HALF - 4

road("Road_N", 0, -(PLAZA + reach) / 2, ROAD_W, reach - PLAZA, roads)
road("Road_S", 0, (PLAZA + reach) / 2, ROAD_W, reach - PLAZA, roads)
road("Road_E", (PLAZA + reach) / 2, 0, reach - PLAZA, ROAD_W, roads)
road("Road_W", -(PLAZA + reach) / 2, 0, reach - PLAZA, ROAD_W, roads)

road("Ring_N", 0, -RING, RING * 2 + ROAD_W, ROAD_W, roads)
road("Ring_S", 0, RING, RING * 2 + ROAD_W, ROAD_W, roads)
road("Ring_E", RING, 0, ROAD_W, RING * 2 + ROAD_W, roads)
road("Ring_W", -RING, 0, ROAD_W, RING * 2 + ROAD_W, roads)

-- Alleys, and the walls that make them narrow. The walls are what turn a painted lane into a place
-- you can be cornered in; without them the "alley" is just a differently-coloured patch of plaza.
local ALLEYS = {
	{ Name = "Alley_NE", Axis = "X", At = -100, From = 9, To = RING - ROAD_W / 2 },
	{ Name = "Alley_SW", Axis = "Z", At = -100, From = 9, To = RING - ROAD_W / 2 },
	{ Name = "Alley_SE", Axis = "X", At = 100, From = 9, To = RING - ROAD_W / 2 },
}

for _, alley in ALLEYS do
	local length = alley.To - alley.From
	local mid = (alley.From + alley.To) / 2
	local runsEastWest = alley.Axis == "X"

	if runsEastWest then
		road(alley.Name, mid, alley.At, length, ALLEY_W, roads)

		for index, sign in { -1, 1 } do
			box(
				`{alley.Name}_Wall{index}`,
				mid,
				5,
				alley.At + sign * (ALLEY_W / 2 + 1),
				length,
				10,
				2,
				GREY,
				roads
			).Material =
				Enum.Material.Brick
		end
	else
		road(alley.Name, alley.At, mid, ALLEY_W, length, roads)

		for index, sign in { -1, 1 } do
			box(
				`{alley.Name}_Wall{index}`,
				alley.At + sign * (ALLEY_W / 2 + 1),
				5,
				mid,
				2,
				10,
				length,
				GREY,
				roads
			).Material =
				Enum.Material.Brick
		end
	end
end

--------------------------------------------------------------------------------
-- ZONES — §5's required list, in the order it names them.
--------------------------------------------------------------------------------

-- The plaza's spawn. RoundService turns CharacterAutoLoads off and drives every body itself through
-- LoadCharacterAsync, which still spawns at a SpawnLocation — so this part is load-bearing, not
-- decoration. It is reused rather than recreated if one already exists in the place.
local spawnPad = workspace:FindFirstChildWhichIsA("SpawnLocation") or Instance.new("SpawnLocation")
spawnPad.Name = "PlazaSpawn"
spawnPad.Size = Vector3.new(24, 1, 24)

--[[
	C30 — SUNK FLUSH AND MADE INVISIBLE, and both halves of that are deliberate.

	A `SpawnLocation` draws Roblox's stock sun decal on its top face, and there is no property that
	turns the decal off on its own. It was a 24-stud studio logo in the middle of the plaza and the
	single most "unfinished Roblox place" thing in any screenshot of this map.

	Transparency alone would have left an INVISIBLE ONE-STUD STEP, because the pad used to sit at
	y = 0.5 spanning 0..1 while `Ground`'s top face is y = 0. Sinking it to span -0.9..0.1 puts its
	walkable surface level with the plaza slab painted over it, so the step goes away with the decal
	rather than becoming a thing you trip on and cannot see.

	IT MUST STILL EXIST AND STILL COLLIDE. `RoundService` turns `CharacterAutoLoads` off and drives
	every body through `LoadCharacterAsync`, which still requires a `SpawnLocation` to place them —
	the zone comment above already says so. This is dressing a load-bearing part, not removing one.
]]
spawnPad.Position = v(0, -0.4, 14)
spawnPad.Anchored = true
spawnPad.Color = PLAZA_C
spawnPad.Transparency = 1
spawnPad.CanCollide = true
spawnPad.Neutral = true
spawnPad.Parent = workspace

--[[
	THE ARKO — the village gate arch, at the north edge of the plaza because §5 puts a landmark there.

	V2.0: IT IS NOW SCENERY, AND THAT IS THE POINT. Under v1.3 this arch carried a tagged gate leaf and
	escaping was a proximity check against it. V01 deleted the escape win and the service that read it,
	so the leaf became geometry nothing referenced — still built, still tagged, still in the place file,
	and invisible to git because the map is not in git.

	The arch survives on its own merits. It is the barrio's most legible landmark, it frames the north
	road, and §5's sightline rule wants something recognisable at the end of a street. Phase 6 dresses
	it. What it must never regain is a tag: v2.0 has exactly two win conditions (§4.9) and neither one
	is a place you stand.
]]
local arko = Instance.new("Folder")
arko.Name = "Arko"
arko.Parent = root

paint(box("Arko_PillarW", -11, 8, -32, 4, 16, 4, STONE, arko), "Whitewash")
paint(box("Arko_PillarE", 11, 8, -32, 4, 16, 4, STONE, arko), "Whitewash")
paint(box("Arko_Lintel", 0, 17, -32, 26, 3, 4, STONE, arko), "Whitewash")

--[[
	NO LEAF UNDER THE ARCH ANY MORE, AND THE EMPTY ARCHWAY IS DELIBERATE.

	v1.3 hung a waist-high wooden leaf here, tagged and solid, because escaping was a proximity check
	and the barrier had to be real. V01 removed the escape win. A solid leaf with no meaning left would
	be worse than useless: it blocks the north road's mouth, and §5 forbids dead ends by name.

	So the archway is open and you walk through it. If a later chunk ever wants a physical gate here it
	is scenery with `CanCollide = false`, never a tagged part — see the arko comment above.
]]

--[[
	THE CHAPEL — §5's "one interior, strong lighting moment", at the north end of the north road.

	TWO DOORS, and the second one is not decoration. A single-door chapel at the end of a radial is a
	dead end, which §5 rules out by name; the east door opens onto the outer band beyond the ring, so
	even the building loops.
]]
--[[
	THE CHAPEL. NOT stilted — `building()`'s last argument stays off. A visita sits on the ground on a
	concrete slab; only the kubo stand on posts.

	Its two doors stay, its two `SearchContainer` anchors stay, and `Chapel_Candles` keeps its position
	and its `MapLight` tag untouched: §5's "strong lighting moment" IS that light, and the builder
	asserts `mapLights == totalLights` at the foot of this file. If the interior ever needs more light
	the answer is emissive Neon geometry costing no light slot, exactly as the banderitas do — not a
	second PointLight, which would fail the build.
]]
local chapel = building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE, Enum.Material.Cobblestone)

for _, wall in chapel:GetChildren() do
	if wall:IsA("BasePart") and string.find(wall.Name, "Wall") then
		paint(wall, "HollowBlock")
	end
end
--[[
	THE STEEPLE. A barangay visita is painted hollow-block concrete under corrugated GI, not the stone
	the greybox implied — `Whitewash` is chalky and rain-streaked, which is what one actually looks
	like after a wet season and reads pale against the night sky from the length of the north road.
]]
paint(box("Chapel_Steeple", 0, 24, -164, 10, 16, 10, STONE), "Whitewash")

-- The one bright interior. Its own light rather than a lantern's: §5 asks for a lighting MOMENT, and a
-- lit doorway seen from the dark road is the cheapest fear-per-hour in the file.
local candles = box("Chapel_Candles", 0, 3, -166, 6, 6, 3, Color3.fromRGB(240, 220, 170))
candles.Material = Enum.Material.Neon

local chapelLight = Instance.new("PointLight")
chapelLight.Name = "ChapelGlow"
chapelLight.Color = Color3.fromRGB(255, 214, 150)
chapelLight.Brightness = 3
chapelLight.Range = 34
chapelLight.Shadows = false
chapelLight.Parent = candles

CollectionService:AddTag(chapelLight, "MapLight")

--[[
	SEVEN BAHAY KUBO, FIVE ENTERABLE — §5 asks for 6–8 with AT LEAST FIVE interiors.

	IT SAID THREE UNDER v1.3 AND THE REWRITE RAISED IT, for a reason it states outright: "up from 3,
	because searching is now the whole game and the containers live inside them." A sealed house in
	v2.0 is a house with no reason to exist — the containers are why you cross a threshold at all.

	Kubo_SW and Kubo_N were sealed boxes until this phase, and Kubo_SW is where that stopped being
	cosmetic: Step 2.3 sited a `SearchContainer` at its centre and `measure.luau` reported the part
	unreachable, plus SEVEN loop failures, because sealing any corridor cannot connect what was never
	connected. Under v1.3 nothing needed to go in there, so nothing ever asked.

	The two that stay sealed are not laziness. Their job is to BREAK SIGHTLINES so the sightline rule
	can be partial rather than absent: you can almost always see something, and almost never
	everything. Two is enough for that; four was more than §5 can now afford.
]]
-- ANNOTATED, and it is the same class of cast CLAUDE.md warns about for `Enums.RoundPhase`. Without
-- it Luau infers the whole array's element type from the FIRST entry — `Doors: { S: boolean }` — and
-- then every kubo with a different door set is a type error for not having an `S` field. The
-- annotation is what makes `Doors` the open map it was always meant to be.
type KuboSpec = {
	Name: string,
	X: number,
	Z: number,
	Doors: { [string]: boolean },
	Enterable: boolean,
}

local KUBO: { KuboSpec } = {
	{ Name = "Kubo_NW", X = -78, Z = -78, Doors = { S = true }, Enterable = true },
	{ Name = "Kubo_NE", X = 78, Z = -78, Doors = { W = true }, Enterable = true },
	{ Name = "Kubo_SE", X = 78, Z = 78, Doors = { N = true }, Enterable = true },
	-- Both doors face INWARD, toward the plaza, like the three above. A door on the outward face would
	-- put its threshold in the dead band between the ring and the perimeter, where nobody walks.
	{ Name = "Kubo_SW", X = -78, Z = 78, Doors = { N = true }, Enterable = true },
	{ Name = "Kubo_N", X = 35, Z = -75, Doors = { S = true }, Enterable = true },

	--[[
		THESE TWO SIT OUTSIDE THE RING, and they were moved there after looking at the map from above.

		The first build put all seven inside the ring, which left the band between the ring and the
		perimeter as bare field on the east and the west — about a quarter of the walkable area with
		nothing in it, no cover, and nothing to look at. That is §5's OTHER failure mode: it warns
		about maps that are too big, and the reason a big map is bad is that it feels dead, not that
		the number is large. A crossing time hit by padding the route with empty grass would pass the
		measurement and fail the intent.

		Moving two rather than adding two keeps the count at seven, inside §5's 6–8.
	]]
	{ Name = "Kubo_E", X = 158, Z = -30, Doors = {}, Enterable = false },
	{ Name = "Kubo_W", X = -158, Z = 40, Doors = {}, Enterable = false },
}

for index, kubo in KUBO do
	-- Sealed ones are built SHORTER rather than stilted. Stilts would be the real bahay kubo
	-- silhouette and they were tried first, but a stilted floor needs a ramp to be walkable and a ramp
	-- is a pathfinding problem this milestone has no reason to buy. Height is the cheap way to vary a
	-- skyline, and varying the skyline is all the silhouette has to do before GATE 1.
	building(
		kubo.Name,
		kubo.X,
		kubo.Z,
		24,
		20,
		if kubo.Enterable then 12 else 9,
		kubo.Doors,
		WOOD,
		nil,
		true
	)

	--[[
		A GENERATED SHELL OVER THE TWO SEALED KUBO, AND ONLY THOSE TWO.

		The mesh is a far better bahay kubo than the box version — real sawali weave, a proper nipa
		pitch, an open undercroft. It cannot go on an enterable house: it is a solid exterior with no
		authored interior, so dropping it over `Kubo_NW` would occlude the doorway and bury the search
		container inside it. §5 needs five enterable houses and the containers are why you enter them.

		`Kubo_E` and `Kubo_W` are sealed by design — they exist to break sightlines from outside the
		ring — so they have no interior to occlude and nothing to reach. They get the good geometry,
		and they are the two most often seen at distance, which is where a mesh earns the most.
	]]
	--[[
		PER-HOUSE VARIATION, BY INDEX RATHER THAN RANDOMLY, so the barrio does not read as seven copies
		of one house and two runs still produce the same map — the same argument the seeded `rng` makes.

		ROOF AGE IS THE AXIS THAT SHOWS MOST AT NIGHT, and research-01 corrected how to apply it: fresh
		nipa is straw-gold and a four-year-old roof is grey-brown, but ageing a WHOLE roof uniformly is
		unsourced. What is sourced is frequent PARTIAL replacement — so the variation belongs within a
		roof, as fresher patches against older material, and the per-house tint below is deliberately
		subtle rather than seven distinct colours.
	]]
	local house = root:FindFirstChild(kubo.Name)

	if house then
		local age = (index % 4) / 3

		for _, piece in house:GetChildren() do
			if piece:IsA("BasePart") and (string.find(piece.Name, "Roof") or string.find(piece.Name, "Pitch")) then
				piece.Color = THATCH:Lerp(Color3.fromRGB(96, 92, 80), age)
			end
		end

		--[[
			One fresher patch per roof, laid across the pitch. This is the sourced half of the finding.

			`box()` RATHER THAN `prop()` FOR THE SAME REASON AS THE STILTS — `prop` is declared with the
			dressing helpers, hundreds of lines below this loop. Calling it here compiles and dies at
			run time with "attempt to call a nil value", which is exactly what happened. The four
			property lines are the price of being above the helper.
		]]
		local patch = box(
			`{kubo.Name}_RoofPatch`,
			kubo.X + ((index % 3) - 1) * 4,
			(if kubo.Enterable then 12 else 9) + 2.9,
			kubo.Z + ((index % 2) * 5 - 2),
			7,
			0.3,
			5,
			Color3.fromRGB(158, 138, 96),
			house
		)

		patch.CanCollide = false
		patch.CanQuery = false
		patch.CanTouch = false
		patch.CastShadow = false

		paint(patch, "Nipa")
	end

	if not kubo.Enterable then
		mesh(
			"KuboShell",
			`{kubo.Name}_Shell`,
			kubo.X,
			8,
			kubo.Z,
			Vector3.new(26, 16, 22),
			root:FindFirstChild(kubo.Name)
		)
	end
end

-- THE WELL / PUMP AREA — §5's fifth zone. A social waypoint off the west road, tucked behind Kubo_SW
-- so that reaching it costs a moment out of sight.
local wellFolder = Instance.new("Folder")
wellFolder.Name = "Well"
wellFolder.Parent = root

--[[
	THE WELL — a `poso`, and it was eight unrotated cubes in a nineteen-stud circle with solid ground
	underneath. It read as blocks because it WAS blocks: no rotation, so the ring never closed, and no
	hole, so it was a low fence rather than a well.

	THREE CHANGES, IN ORDER OF WHAT SHOWS:

	1. THE HOLE. A dark shaft sunk into the middle is the entire difference between a well and a ring
	   of stones. It is emissive-free black at 0 transparency, non-collidable, and recessed just below
	   the coping so you see INTO it rather than at a lid.
	2. ROTATION. Each coping stone is turned to face the centre, so the ring reads as a circle of
	   fitted stones instead of eight cubes on a circular path.
	3. SCALE. The old radius of 6 authored units is 9.3 studs — a nineteen-stud well, which is a
	   swimming pool. A real barrio poso coping is roughly waist-high and a body-width across; 3.4
	   authored units puts it near five studs, which a character can stand at rather than in.
]]
local WELL_X, WELL_Z = -70, 32
local WELL_R = 3.4

for index = 1, 10 do
	local angle = (index - 1) * math.pi / 5
	local stone = box(
		`Well_Ring{index}`,
		WELL_X + math.cos(angle) * WELL_R,
		1.5,
		WELL_Z + math.sin(angle) * WELL_R,
		1.9,
		3,
		1.5,
		STONE,
		wellFolder
	)

	-- Faced inward. `turn` takes degrees about Y, and the stone's long axis is X, so the angle is the
	-- polar angle plus a quarter turn.
	stone.CFrame = CFrame.new(stone.Position) * CFrame.Angles(0, -angle + math.pi / 2, 0)
end

--[[
	THE SHAFT. Non-collidable so it cannot trap a player, and sunk 2 studs so the rim casts into it.
	`Basalt` rather than a colour alone: at the bottom of an unlit hole the material is all that stops
	it reading as a flat black decal painted on the ground.
]]
local shaft = box("Well_Shaft", WELL_X, -0.6, WELL_Z, WELL_R * 1.7, 4, WELL_R * 1.7, Color3.fromRGB(10, 10, 12), wellFolder)

shaft.Material = Enum.Material.Basalt
shaft.CanCollide = false
shaft.CanQuery = false
shaft.CanTouch = false

--[[
	THE BUCKET FRAME — two posts and a crossbeam over the shaft. It is what makes a well read as a well
	in SILHOUETTE from across the plaza, which at night is the only way it is read at all.
]]
for _, side in { -1, 1 } do
	paint(
		box(
			`Well_Post{if side < 0 then "W" else "E"}`,
			WELL_X + side * (WELL_R + 0.4),
			4,
			WELL_Z,
			0.5,
			6,
			0.5,
			BAMBOO_C,
			wellFolder
		),
		"Bamboo"
	)
end

paint(box("Well_Beam", WELL_X, 7, WELL_Z, WELL_R * 2.6, 0.5, 0.5, BAMBOO_C, wellFolder), "Bamboo")

-- The rope and the bucket, hanging into the shaft.
box("Well_Rope", WELL_X, 5.4, WELL_Z, 0.12, 3, 0.12, Color3.fromRGB(120, 108, 84), wellFolder).Material =
	Enum.Material.Fabric

paint(
	box("Well_Bucket", WELL_X, 3.6, WELL_Z, 1.3, 1.4, 1.3, Color3.fromRGB(92, 74, 54), wellFolder),
	"Bamboo"
)

--[[
	THE PUMP. A `poso` is the social waypoint of a barrio and it was a grey box. The mesh carries the
	cast-iron pump and its low stone ring together. It stays NON-COLLIDABLE like all dressing, and the
	well's own collidable ring parts around it are untouched — the shape you can stand on has not moved.
]]
mesh("WellPump", "Well_Pump", -58, 2.6, 40, Vector3.new(5, 6, 5), wellFolder)
paint(box("Well_LowWall", -70, 1, 48, 26, 2, 2, STONE, wellFolder), "HollowBlock")

for _, stone in wellFolder:GetChildren() do
	if (stone :: Part).Name:match("^Well_Ring") then
		paint(stone :: Part, "HollowBlock")
	end
end

--[[
	THE RICE FIELD EDGE — §5's killing field, in the south-east outer band.

	Tall thin blades, non-collidable, so you can WALK THROUGH it and see almost nothing while you do.
	That is the whole mechanic: §5 says fear comes from PARTIAL information, and this is the one place
	on the map where the information is worst. It is deliberately far from the plaza and adjacent to
	two task points, so the errand that takes you here is an errand that isolates you.
]]
local rice = Instance.new("Folder")
rice.Name = "RiceField"
rice.Parent = root

for index = 1, 90 do
	local x = rng:NextNumber(28, 168)
	local z = rng:NextNumber(140, 170)
	local blade = box(`Rice_{index}`, x, 5, z, 1.6, 10, 1.6, GRASS, rice)

	blade.CanCollide = false
	blade.CanQuery = false
	paint(blade, "Paddy")
	blade.Color = Color3.fromRGB(62, rng:NextInteger(78, 100), 48)
end

--------------------------------------------------------------------------------
-- LANTERNS — twelve, spaced. See `lantern` for why spacing IS the mobile budget.
--------------------------------------------------------------------------------

local lights = Instance.new("Folder")
lights.Name = "Lanterns"
lights.Parent = root

for index, at in
	{
		{ -40, -40 },
		{ 40, -40 },
		{ -40, 40 },
		{ 40, 40 }, -- plaza corners
		{ 0, -128 }, -- chapel approach
		{ -62, 46 }, -- well
		{ 62, -100 },
		{ -100, 62 },
		{ 62, 100 }, -- alley mouths
		{ -RING, -RING },
		{ RING, RING }, -- ring corners
		{ 120, 136 }, -- rice field edge
	}
do
	lantern(`Lantern_{index}`, at[1], at[2], lights)
end

--------------------------------------------------------------------------------
-- THE TAGGED ANCHORS — the contract in the header, made real.
--------------------------------------------------------------------------------

local anchors = Instance.new("Folder")
anchors.Name = "Anchors"
anchors.Parent = root

--[[
	THE FIFTEEN SEARCHABLE CONTAINERS — §5's "~15 searchable containers", and the reason the map exists
	at all in v2.0. This block REPLACES v1.3's twelve task points and four fetch sources, deleted with
	the services that read them.

	`SearchService.discoverPool` reads this tag and evaluates the pool against
	`Config.Search.ContainerCount`. A short pool warns unconditionally; a ZERO pool is a barrio with
	nothing to do in it, and that was the state of this map until this block existed — the builder
	emitted no `SearchContainer` at all while Config asked for fifteen. `SearchService`'s own comment
	names the symptom: "there is nothing to do and nobody knows why."

	NAMES MUST BE UNIQUE. `discoverPool` keys by Name and reports duplicates as skipped, so two
	`Container_Kubo` parts are one container and a silent short pool.

	SPREAD IS A DESIGN CONSTRAINT, NOT A LAYOUT PREFERENCE. §5: "no single house is worth camping and
	no two are close enough that one search covers two." The distance that makes the second half
	concrete is `Config.Search.RangeStuds` (10) — the radius you must be inside to search, and stay
	inside for the whole six seconds. Two containers closer than 2 x that are one stop, so every pair
	below is more than 20 studs apart; `tests/barrio-contract.test.luau` asserts it rather than
	trusting this comment.

	At least five of the seven kubo carry one, because §5 asks for "at least 5 enterable" and the
	containers are the reason to enter.
]]
local SEARCH_CONTAINERS = {
	-- Five kubo interiors, one each, so no single house is the obvious first stop.
	{ Name = "Container_KuboNW_Chest", X = -78, Z = -78 },
	{ Name = "Container_KuboNE_Sack", X = 78, Z = -78 },
	{ Name = "Container_KuboSE_Chest", X = 78, Z = 78 },
	{ Name = "Container_KuboSW_Basket", X = -78, Z = 78 },
	-- MUST MATCH `Kubo_N`'s own X/Z in the KUBO table above. This read (0, -104) first, which is open
	-- ground 40 studs from the house it is named after — reachable, so `measure.luau` passed it, and
	-- wrong in a way only the name revealed. `tests/barrio-contract.test.luau` now pins each
	-- `Container_Kubo*` to its kubo's coordinates so the next one fails a terminal instead of a reader.
	{ Name = "Container_KuboN_Drum", X = 35, Z = -75 },
	-- The civic buildings. The chapel carries two because it is the one lit interior and §5 wants a
	-- reason to cross its threshold twice.
	{ Name = "Container_Chapel_Pew", X = 0, Z = -158 },
	{ Name = "Container_Chapel_Vestry", X = 17, Z = -140 },
	{ Name = "Container_Well_Crate", X = -76, Z = 44 },
	-- The four sari-sari stalls, which are literally shops and read as searchable at a glance.
	{ Name = "Container_StallNW_Goods", X = -58, Z = -58 },
	{ Name = "Container_StallNE_Goods", X = 58, Z = -58 },
	{ Name = "Container_StallSE_Goods", X = 58, Z = 58 },
	{ Name = "Container_StallSW_Goods", X = -58, Z = 58 },
	-- The edges, so the rice field and the alleys are worth walking into at all.
	{ Name = "Container_Rice_Rack", X = 120, Z = 148 },
	{ Name = "Container_AlleySW_Crate", X = -100, Z = 60 },
	-- Renamed from `Container_Plaza_Bench` when the benches were removed. A container named after a
	-- prop that no longer exists is the same defect as `Container_KuboN_Drum` sitting outside Kubo_N:
	-- the name is the only part a reader checks, and it was the only part that was wrong.
	{ Name = "Container_Plaza_Crate", X = -25, Z = 20 },
}

for _, container in SEARCH_CONTAINERS do
	anchor(container.Name, "SearchContainer", container.X, container.Z, anchors)
end

--[[
	WHERE THE AMBIENT POPULATION STANDS. `AmbientService` spawns the rigs; this only sites them.

	§5 is explicit that the COUNT is what matters — "if there is one pig in the barrio, the disguise is
	meaningless" — and `Config.Ambient.PerForm` (4) x 4 forms is sixteen. Sixteen points, so no two
	entities start inside each other.

	WITHOUT THESE THE SERVICE FALLS BACK TO A RING AT THE ORIGIN, which is what this barrio did until
	now: sixteen animals in a circle through the middle of the plaza, which is both absurd to look at
	and actively harmful to §4.5 — camouflage needs the population spread across the places a monster
	would want to hide, not gathered where everyone spawns. The fallback fires only on ZERO tagged
	parts, so a partial list is worse than none: add all sixteen or the ring stays.
]]
local AMBIENT_POINTS = {
	-- The plaza and its approaches, where villagers and dogs plausibly gather.
	{ -30, 30 },
	{ 30, 24 },
	{ 26, -34 },
	{ -18, -30 },
	-- The four stall corners.
	{ -58, -58 },
	{ 58, -58 },
	{ 58, 58 },
	{ -58, 58 },
	-- The civic and outlying zones, so no quarter of the map is animal-dead.
	{ -76, 44 },
	{ 0, -104 },
	{ -14, -146 },
	{ 120, 148 },
	{ -100, 60 },
	{ 100, -60 },
	{ -40, 100 },
	{ 40, -100 },
}

for index, at in AMBIENT_POINTS do
	anchor(`AmbientSpawn_{index}`, "AmbientSpawn", at[1], at[2], anchors)
end

-- Six salt spawns against Config.Salt.PouchPoolSize, four of which carry a pouch each round. Spread so
-- that no quarter of the map is salt-dead: salt is the ONLY answer to the monster (§4.6), and a corner
-- with none in reach is a corner where the counterplay does not exist.
local SALT_SPAWNS = {
	{ Name = "SaltSpawn_Plaza", X = 12, Z = 34 },
	{ Name = "SaltSpawn_Chapel", X = -16, Z = -138 },
	{ Name = "SaltSpawn_KuboNE", X = 92, Z = -66 },
	{ Name = "SaltSpawn_Well", X = -58, Z = 26 },
	{ Name = "SaltSpawn_Rice", X = 120, Z = 148 },
	{ Name = "SaltSpawn_AlleySW", X = -100, Z = 60 },
}

for _, salt in SALT_SPAWNS do
	local p = anchor(salt.Name, "SaltSpawn", salt.X, salt.Z, anchors)

	p.Color = Color3.fromRGB(200, 198, 188)
end

--------------------------------------------------------------------------------
-- C30 — THE DRESSING
--
-- §5's art strategy and the build plan's one hard instruction for this chunk:
-- "Do not change the layout; it passed GATE 1 and the layout is the thing that
-- was validated." So nothing below moves a coordinate, a road, a building or an
-- anchor. Every part in this section is NEW and additive, and the section can be
-- deleted wholesale to get the C17 greybox back.
--
-- ═══ THE TWO RULES THAT KEEP THE DONE CONDITION TRUE ═══════════════════════════
--
-- C30's done condition is "reads as a Filipino village at night; crossing time
-- unchanged; FPS unchanged". Both halves of that are held by construction rather
-- than by measuring afterwards and hoping:
--
--   1. NOTHING HERE COLLIDES. PathfindingService builds its navmesh from collision
--      geometry, so a non-collidable prop cannot move a route, cannot lengthen a
--      walk, and cannot change the number `measure.luau` reports. The re-measure
--      after this chunk is a CONFIRMATION, not a discovery — if the crossing time
--      had moved, the rule would have been broken somewhere.
--
--      The cost is a market stall you can walk through. That is the right trade at
--      this milestone: the layout's cover comes from the buildings, which still
--      collide, and a prop that blocks SIGHT does the horror work without touching
--      the navmesh at all. §5 wants partial information, and occlusion is what
--      delivers it.
--
--   2. NOT ONE NEW DYNAMIC LIGHT. The light count stays at fourteen, and the mobile
--      budget in `Config.Performance` is untouched. Everything here that reads as
--      "lit" — the capiz windows, the fiesta bulbs, the chapel candles' spill — is
--      `Enum.Material.Neon`, which is emissive SHADING and costs no light slot. The
--      asset-pipeline skill names many point lights as the #1 mobile FPS killer, and
--      the whole reason this map can look lit at ClockTime 0 is that almost none of
--      the lit-looking things are lights.
--
--      `CastShadow = false` on every prop is the same argument one layer down. Future
--      lighting shadows every caster against every visible light; several hundred
--      shadow-casting props is exactly the cost this dressing exists to avoid, and a
--      bamboo pole's shadow is invisible in fog at 220 studs anyway.
--------------------------------------------------------------------------------

local dress = Instance.new("Folder")
dress.Name = "Dressing"
dress.Parent = root

local BAMBOO = Color3.fromRGB(104, 118, 72)
local LEAF = Color3.fromRGB(52, 78, 42)
local RUST = Color3.fromRGB(116, 82, 60)
local TIN = Color3.fromRGB(96, 98, 96)
local TARP = Color3.fromRGB(66, 74, 88)
local WARM = Color3.fromRGB(255, 206, 140)

--[[
	FLUORESCENT INTERIOR LIGHT, AND IT IS A RESEARCH FINDING THAT INVERTS THE HORROR INSTINCT.

	The instinct is warm amber windows — it is what every horror village looks like, and it is what this
	map had. But warm amber in a rural Philippine house is unsourced: what is actually there is a bare
	CFL or LED tube, which is cold, slightly green, and unflattering. Research-04 argues for it and the
	argument is not only accuracy.

	IT CONTRASTS AGAINST THE STREET INSTEAD OF BLENDING INTO IT. The lanterns are sodium-warm; if the
	windows are warm too, every light source in the barrio is the same colour and the eye stops
	separating them. Cool windows make a lit house read as INHABITED and a lantern read as STREET, from
	across the map, with no extra geometry.

	THE CHAPEL DELIBERATELY KEEPS ITS WARM PANES, and that is now a meaningful distinction rather than
	an inconsistency: a barangay visita is lit by candles — `Chapel_Candles` is the map's one interior
	`MapLight` and §5's "strong lighting moment" — so it is the ONE warm interior in a barrio of cold
	ones. That contrast is free and it points at the building §5 wants you to notice.
]]
local FLUORO = Color3.fromRGB(198, 222, 226)

-- Not every house has the new tube in it. Two of the seven keep an older warm bulb, so the barrio
-- reads as a place people re-fit one at a time rather than a set dressed in one pass.
local OLD_BULB = Color3.fromRGB(244, 206, 152)

--[[
	BANDERITAS, FADED — and this palette is a research finding that OVERRODE the obvious choice.

	The instinct is saturated primaries. The reality is that banderitas are hung weeks before a fiesta
	and left up for months or a year, so their DEFAULT state in a barrio is faded and partly torn:
	screaming reds break into a bruised muted pink, sharp yellows fade to a sickly cream, deep blues
	turn a ghostly translucent grey. That is both more accurate and a far better fit for a muted map
	on a horror night than fresh colour would be.

	The last two entries are deliberately less faded — a real run always has a few recently patched
	flags among the old ones, and uniform fade is its own kind of tell.
]]
local FIESTA_COLOURS = {
	Color3.fromRGB(168, 116, 124),
	Color3.fromRGB(196, 186, 152),
	Color3.fromRGB(146, 150, 158),
	Color3.fromRGB(158, 138, 116),
	Color3.fromRGB(186, 128, 108),
	Color3.fromRGB(132, 144, 136),
}
local CLOTH = {
	Color3.fromRGB(178, 176, 166),
	Color3.fromRGB(120, 138, 150),
	Color3.fromRGB(160, 128, 116),
	Color3.fromRGB(136, 148, 120),
}

--[[
	A prop: a part that is seen and never touched.

	SIZE IS IN TRUE STUDS AND POSITION IS IN LAYOUT UNITS, which is the same split `anchor` makes and
	for the same reason. A bamboo pole is a bamboo pole whatever `SCALE` is set to; only WHERE it
	stands belongs to the map's coordinate space. The `/ SCALE` cancels the one `box` applies.
]]
local function prop(
	name: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance?
): Part
	local p = box(name, cx, cy, cz, sx / SCALE, sy, sz / SCALE, colour, parent or dress)

	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false

	return p
end

-- Yaw only. Props lean and turn; nothing here needs a full orientation, and a single angle keeps the
-- placement tables readable as data.
local function turn(p: Part, degrees: number): Part
	p.CFrame = CFrame.new(p.Position) * CFrame.Angles(0, math.rad(degrees), 0)

	return p
end

-- A lean, applied after a yaw. Used for bamboo, which is never quite vertical, and for banana leaves.
local function lean(p: Part, degrees: number, aboutZ: boolean?): Part
	local angle = math.rad(degrees)

	p.CFrame = p.CFrame
		* (if aboutZ then CFrame.Angles(0, 0, angle) else CFrame.Angles(angle, 0, 0))

	return p
end

-- A part stretched between two world points. Wires, ropes and washing lines are all this.
local function span(
	name: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	local delta = to - from

	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(thickness, thickness, math.max(delta.Magnitude, 0.1))
	p.CFrame = CFrame.lookAt(from + delta / 2, to)
	p.Color = colour
	p.Material = material
	p.Parent = parent or dress

	return p
end

--[[
	A sagging line between two layout points, as `segments` straight pieces on a parabola.

	One function covers the three things that hang in this map — power lines, washing lines and fiesta
	bulbs — because they differ only in what, if anything, is hung at each node. A real catenary is a
	cosh; a parabola is visually identical over these spans and is four operations instead of an
	exponential.
]]
local function droop(
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y: number,
	sag: number,
	segments: number,
	thickness: number,
	colour: Color3,
	parent: Instance?,
	onNode: ((string, Vector3) -> ())?
)
	local function pointAt(t: number): Vector3
		return v(x1 + (x2 - x1) * t, y - sag * 4 * t * (1 - t), z1 + (z2 - z1) * t)
	end

	local previous = pointAt(0)

	for index = 1, segments do
		local current = pointAt(index / segments)

		span(
			`{name}_Seg{index}`,
			previous,
			current,
			thickness,
			colour,
			Enum.Material.SmoothPlastic,
			parent
		)

		if onNode and index < segments then
			onNode(`{name}_Node{index}`, current)
		end

		previous = current
	end
end

--------------------------------------------------------------------------------
-- POWER POSTS AND THE SAGGING WIRE
--
-- The single most recognisable thing about a Philippine street at night, and it
-- is nearly free: a leaning wooden post, a crossarm, and a wire that droops to
-- the next one. It also does real work for the camera — a horizontal line across
-- the top of the frame gives the fog something to sit behind.
--------------------------------------------------------------------------------

local posts = Instance.new("Folder")
posts.Name = "PowerLine"
posts.Parent = dress

-- Each run is a road, walked in order, with the posts set 12 studs off the centreline so they stand
-- on the verge rather than in the street. The offsets are hand-checked against the anchor list — a
-- post through a task pad would read as a bug in the map rather than as scenery.
local POWER_RUNS = {
	{ Name = "North", Points = { { 12, -58 }, { 12, -86 }, { 12, -114 } } },
	{ Name = "South", Points = { { 12, 58 }, { 12, 86 }, { 12, 114 } } },
	{ Name = "East", Points = { { 58, 12 }, { 86, 12 }, { 114, 12 } } },
	{ Name = "West", Points = { { -58, 12 }, { -86, 12 }, { -114, 12 } } },
}

for _, run in POWER_RUNS do
	for index, at in run.Points do
		local base = `Post_{run.Name}{index}`

		prop(`{base}_Pole`, at[1], 9, at[2], 1.4, 18, 1.4, WOOD, Enum.Material.Wood, posts)
		prop(`{base}_Arm`, at[1], 16.5, at[2], 7, 0.8, 0.8, WOOD, Enum.Material.Wood, posts)

		-- The transformer drum. Two per run, so the line is not a repeating stamp.
		if index == 2 then
			prop(
				`{base}_Can`,
				at[1] + 2,
				14,
				at[2],
				2.4,
				3.5,
				2.4,
				TIN,
				Enum.Material.CorrodedMetal,
				posts
			)
		end

		if index > 1 then
			local previous = run.Points[index - 1]

			for wire = 1, 2 do
				local offset = if wire == 1 then -2 else 2
				local acrossX = if run.Name == "East" or run.Name == "West" then 0 else offset
				local acrossZ = if run.Name == "East" or run.Name == "West" then offset else 0

				droop(
					`Wire_{run.Name}{index}_{wire}`,
					previous[1] + acrossX,
					previous[2] + acrossZ,
					at[1] + acrossX,
					at[2] + acrossZ,
					16.2,
					2.2,
					4,
					0.25,
					Color3.fromRGB(28, 28, 30),
					posts
				)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- THE PLAZA — a barrio's plaza is a basketball court with a plaza around it.
--
-- It sits on the WEST half, clear of the spawn pad (z 2..26), the arko (z = -32)
-- and both plaza task points. Court paint is a road-style slab: flat, thin, and
-- non-collidable exactly like the roads it borrows the trick from.
--------------------------------------------------------------------------------

local plaza = Instance.new("Folder")
plaza.Name = "PlazaDressing"
plaza.Parent = dress

local COURT_X, COURT_Z = -26, -8

--[[
	THE SLAB. Narrowed to the real proportion. A barangay court is laid out to roughly the FIBA 28x15m
	ratio even when it is undersized, and the greybox's 30x18 is squarer than any real one — a court
	that reads WRONG reads as a car park, which is the opposite of the most characteristic structure
	in a Philippine barrio.

	PAINTED, NOT BARE CEMENT. A barangay court is repainted for every fiesta and cracks between them,
	so its default state is a worn green-grey rather than the concrete colour it was.
]]
paint(
	prop(
		"Court_Slab",
		COURT_X,
		0.12,
		COURT_Z,
		30 * SCALE,
		0.14,
		16 * SCALE,
		Color3.fromRGB(78, 96, 92),
		Enum.Material.Concrete,
		plaza
	),
	"CourtSlab"
)

--[[
	THE CRACKS — the highest realism-per-part item in the whole phase.

	A perfectly flat, perfectly clean slab is the single strongest "this is a greybox" signal in the
	plaza, and six thin slivers fix it. Seeded from the existing `rng` so two runs produce the same
	barrio, for the same reason the rice field is seeded: a jittered map makes "did the layout change?"
	unanswerable.
]]
for index = 1, 6 do
	turn(
		prop(
			`Court_Crack{index}`,
			COURT_X + rng:NextNumber(-13, 13),
			0.19,
			COURT_Z + rng:NextNumber(-6, 6),
			rng:NextNumber(4, 11),
			0.04,
			0.25,
			Color3.fromRGB(44, 48, 46),
			Enum.Material.Slate,
			plaza
		),
		rng:NextNumber(0, 180)
	)
end

-- Faded paint. Three lines is enough to read as a court from across the plaza, which is the only
-- distance anyone will read it from. The LENGTHS scale with the slab; the 0.5-stud line width does
-- not, because a painted line does not get wider when the map does.
prop(
	"Court_LineN",
	COURT_X,
	0.2,
	COURT_Z - 8,
	30 * SCALE,
	0.06,
	0.5,
	Color3.fromRGB(196, 190, 176),
	Enum.Material.SmoothPlastic,
	plaza
)
prop(
	"Court_LineS",
	COURT_X,
	0.2,
	COURT_Z + 8,
	30 * SCALE,
	0.06,
	0.5,
	Color3.fromRGB(196, 190, 176),
	Enum.Material.SmoothPlastic,
	plaza
)
prop(
	"Court_LineMid",
	COURT_X,
	0.2,
	COURT_Z,
	0.5,
	0.06,
	16 * SCALE,
	Color3.fromRGB(196, 190, 176),
	Enum.Material.SmoothPlastic,
	plaza
)

for index, side in { -1, 1 } do
	local x = COURT_X + side * 15

	prop(`Hoop{index}_Pole`, x, 5, COURT_Z, 0.9, 10, 0.9, TIN, Enum.Material.CorrodedMetal, plaza)
	prop(
		`Hoop{index}_Board`,
		x - side * 1.6,
		10.5,
		COURT_Z,
		0.4,
		3.5,
		5,
		Color3.fromRGB(186, 182, 170),
		Enum.Material.WoodPlanks,
		plaza
	)
	--[[
		THE BENT, NETLESS RIM — the most repeated observation about real barangay hoops, and nearly
		free. `lean` tips it forward a few degrees, which is what a decade of people hanging off it
		does. No net, because a net is consumable and nobody replaces it. The two rims lean by
		DIFFERENT amounts: symmetry is the tell that something was placed rather than used.
	]]
	lean(
		paint(
			prop(
				`Hoop{index}_Rim`,
				x - side * 3,
				9.2,
				COURT_Z,
				2.6,
				0.25,
				2.6,
				Color3.fromRGB(176, 84, 44),
				Enum.Material.CorrodedMetal,
				plaza
			),
			"RustedSteel"
		) :: Part,
		if index == 1 then -7 else -4,
		true
	)

	-- Plywood backboards warp and delaminate; two braces behind each is what actually holds them on.
	for brace = -1, 1, 2 do
		turn(
			prop(
				`Hoop{index}_Brace{if brace < 0 then "L" else "R"}`,
				x - side * 0.8,
				9.6,
				COURT_Z + brace * 1.6,
				0.25,
				0.25,
				2.4,
				TIN,
				Enum.Material.CorrodedMetal,
				plaza
			),
			brace * 24
		)
	end
end

--[[
	FIESTA BULBS STRUNG BETWEEN THE FOUR PLAZA LANTERNS.

	Neon spheres on a drooping wire, and NOT PointLights — see rule 2 at the top. Twelve small emissive
	dots read as a strung plaza from anywhere in it, cost no light slot, and give the safest place on
	the map a warmth the streets deliberately do not have. §5 wants the plaza to feel different from
	the alleys; this is that difference, drawn rather than lit.
]]
--[[
	ANCHORED AT UNEVEN HEIGHTS, because real banderitas are tied to whatever is there — a sloping
	telephone pole, a rusty second-storey grill, a mango tree, a shop awning. The symmetrical square
	between four equal lantern tops was the tidiest thing in the plaza and tidy is the one quality a
	barrio plaza does not have. `droop` already takes a per-run height, so this is data, not new code.
]]
local CORNERS = { { -40, -40 }, { 40, -40 }, { 40, 40 }, { -40, 40 } }
local RUN_HEIGHT = { 9.6, 8.7, 10.2, 9.1 }
local RUN_SAG = { 2.4, 3.1, 2.0, 2.7 }

for index, corner in CORNERS do
	local nextCorner = CORNERS[if index == #CORNERS then 1 else index + 1]

	droop(
		`Fiesta{index}`,
		corner[1],
		corner[2],
		nextCorner[1],
		nextCorner[2],
		RUN_HEIGHT[index],
		RUN_SAG[index],
		10,
		0.18,
		Color3.fromRGB(30, 28, 26),
		plaza,
		function(name, at)
			local bulb = Instance.new("Part")

			bulb.Name = name
			bulb.Anchored = true
			bulb.CanCollide = false
			bulb.CanQuery = false
			bulb.CanTouch = false
			bulb.CastShadow = false
			bulb.Shape = Enum.PartType.Ball
			bulb.Size = Vector3.new(0.7, 0.7, 0.7)
			bulb.Position = at - Vector3.new(0, 0.4, 0)
			bulb.Material = Enum.Material.Neon
			bulb.Color = if index % 2 == 0 then WARM else Color3.fromRGB(255, 168, 132)
			bulb.Parent = plaza

			--[[
				A CUT PAPER TRIANGLE HUNG BESIDE EACH BULB. Real banderitas are cut plastic or paper,
				not bulbs — but the bulbs are the cheapest warmth in the map and cost no light slot, so
				both hang together rather than one replacing the other.

				NON-EMISSIVE ON PURPOSE. The flag reads as a small dark silhouette against the bulb it
				hangs next to, which is exactly how a strung plaza reads at night: you see the lights,
				and you see that something is hanging between them.
			]]
			local node = tonumber(string.match(name, "%d+$")) or 1
			local flag = prop(
				`{name}_Flag`,
				0,
				0,
				0,
				0.9,
				1.1,
				0.05,
				FIESTA_COLOURS[(node + index) % #FIESTA_COLOURS + 1],
				Enum.Material.SmoothPlastic,
				plaza
			)

			paint(flag, "Cloth")

			flag.CFrame = CFrame.new(at - Vector3.new(0, 1.2, 0))
		end
	)
end

-- A flagpole, and benches along the plaza edge. The pole is the civic marker every barrio plaza has;
-- the benches are where a player waiting out an intermission will stand, which is worth dressing.
prop("Flagpole", 0, 11, -8, 0.8, 22, 0.8, Color3.fromRGB(198, 196, 188), Enum.Material.Metal, plaza)
prop("Flag", 2.6, 19, -8, 5, 3, 0.2, Color3.fromRGB(150, 60, 56), Enum.Material.Fabric, plaza)

--[[
	NO BENCHES, AND THEIR REMOVAL IS A RESEARCH CORRECTION RATHER THAN A BUDGET CUT.

	Four wood-and-concrete benches stood around the plaza. A Philippine barrio does not have municipal
	park benches — people sit on the court's edge, on a stall's step, on a plastic monobloc stool, or on
	the low wall. Street furniture of that kind reads as a town plaza in a temperate country, and it was
	the most quietly wrong thing in the map: nothing about it looked broken, it was simply not there in
	the real place.

	Sixteen parts recovered. The plaza's social read now comes from the court, the stalls and the
	banderitas, which is where it comes from in the reference photographs.
]]


--------------------------------------------------------------------------------
-- MARKET STALLS — the talipapa. Four, on the plaza's edges.
--------------------------------------------------------------------------------

local STALLS = {
	{ Name = "Stall_NW", X = -38, Z = 28, Yaw = 12 },
	{ Name = "Stall_NE", X = 34, Z = 38, Yaw = -8 },
	{ Name = "Stall_SE", X = 38, Z = -28, Yaw = 24 },
	{ Name = "Stall_SW", X = -36, Z = -24, Yaw = -18 },
}

--[[
	A SARI-SARI SHOPFRONT BEHIND EACH STALL COUNTER — the one mesh in this pass that REPLACES NOTHING
	and is added anyway.

	Four of the fifteen search containers sit in these stalls, and Step 4.5's gate found the containers
	invisible in the dark. A shopfront is the strongest possible "there is something to search here"
	signal because it is what the thing actually is: a barred slat window with sachets hanging in it.
	It reads as a shop from across the plaza, which no arrangement of boxes on a counter does.

	They are yawed with their stall so the face lines up with the counter rather than the axis.
]]
--[[
	THE BARRED WINDOW — the sari-sari store's actual silhouette, and four thin parts each.

	Research-03 names three signatures of a sari-sari store. The grille is the one that reads from
	across a plaza, and the generated shopfront mesh above carries it too; these bars sit in front of
	the counter so the shape survives even where the mesh is edge-on. The tarpaulin SIGN is the second
	signature and it is out of reach: no tool in this toolchain generates images, so a sponsor tarp
	with lettering cannot be made. It is a coloured panel reading as a tarp in silhouette and the
	lettering is recorded in Follow Ups rather than faked.
]]
for _, stall in STALLS do
	local holder = dress:FindFirstChild(stall.Name) or dress

	for bar = 1, 4 do
		paint(
			prop(
				`{stall.Name}_Grille{bar}`,
				stall.X - 1.5 + bar * 0.9,
				4.6,
				stall.Z - 1.9,
				0.18,
				2.6,
				0.18,
				TIN,
				Enum.Material.Metal,
				holder
			),
			"RustedSteel"
		)
	end

	-- Hanging sachet strips. `droop` already does this for free and it is the third signature.
	droop(
		`{stall.Name}_Sachets`,
		stall.X - 3,
		stall.Z - 2.4,
		stall.X + 3,
		stall.Z - 2.4,
		6.2,
		0.5,
		6,
		0.1,
		Color3.fromRGB(52, 50, 46),
		holder
	)
end

for _, stall in STALLS do
	local face = mesh(
		"SariSari",
		`{stall.Name}_Front`,
		stall.X,
		4.2,
		stall.Z - 2.2,
		Vector3.new(9, 8, 3),
		dress:FindFirstChild(stall.Name) or dress
	)

	if face then
		face.CFrame = CFrame.new(face.Position) * CFrame.Angles(0, math.rad(stall.Yaw + 180), 0)
	end
end

for index, stall in STALLS do
	local folder = Instance.new("Folder")

	folder.Name = stall.Name
	folder.Parent = dress

	local x, z = stall.X, stall.Z

	for leg, corner in { { -4, -3 }, { 4, -3 }, { -4, 3 }, { 4, 3 } } do
		prop(
			`{stall.Name}_Leg{leg}`,
			x + corner[1],
			3,
			z + corner[2],
			0.7,
			6,
			0.7,
			BAMBOO,
			Enum.Material.Wood,
			folder
		)
	end

	-- Corrugated tin, the roof of every informal structure in the country, and the one surface here
	-- that catches a lantern hard enough to be seen from the next street.
	turn(
		paint(prop(`{stall.Name}_Roof`, x, 6.4, z, 11, 0.4, 8, TIN, Enum.Material.CorrodedMetal, folder), "GIRoof") :: Part,
		stall.Yaw
	)
	prop(
		`{stall.Name}_Counter`,
		x,
		2.6,
		z - 2.6,
		10,
		0.5,
		2.2,
		WOOD,
		Enum.Material.WoodPlanks,
		folder
	)
	paint(prop(`{stall.Name}_Tarp`, x, 4.4, z + 3.4, 10, 3.6, 0.2, TARP, Enum.Material.Fabric, folder), "Tarp")

	-- Produce on the counter, as three coloured heaps. At night and through fog this is the correct
	-- amount of detail: a silhouette with colour in it, not a modelled mango.
	for heap = 1, 3 do
		local heapPart = prop(
			`{stall.Name}_Heap{heap}`,
			x - 3 + heap * 3,
			3.2,
			z - 2.6,
			1.8,
			0.9,
			1.6,
			CLOTH[(index + heap) % #CLOTH + 1],
			Enum.Material.Fabric,
			folder
		)

		heapPart.Shape = Enum.PartType.Ball
		heapPart.Size = Vector3.new(1.8, 1.2, 1.6)
	end
end

--------------------------------------------------------------------------------
-- THE HOUSES — capiz windows, washing lines, and the clutter of a lived-in yard.
--
-- The windows are the highest-value twenty parts in this file. A dark building
-- is a wall; a dark building with two warm rectangles in it is a HOUSE, with
-- somebody in it, and the barrio stops reading as an empty set of blocks. They
-- are Neon, so they cost nothing (rule 2).
--------------------------------------------------------------------------------

local houses = Instance.new("Folder")
houses.Name = "Houses"
houses.Parent = dress

--[[
	A window on a wall face. `depth` deliberately EXCEEDS the wall it sits in, so the pane protrudes
	on both sides and the room appears lit from inside as well as out — one part doing the work of two,
	and no alignment arithmetic against `building`'s scaled wall thickness to get subtly wrong.
]]
local function window(
	name: string,
	cx: number,
	cz: number,
	cy: number,
	wide: boolean,
	parent: Instance,
	tint: Color3?
)
	local pane = prop(
		name,
		cx,
		cy,
		cz,
		if wide then 4.5 else 4,
		3,
		if wide then 4 else 4.5,
		tint or FLUORO,
		Enum.Material.Neon,
		parent
	)

	-- Not full brightness. A capiz shell pane is translucent, not a lamp, and a solid Neon block reads
	-- as a hole cut in the wall rather than as a window with something behind it.
	pane.Transparency = 0.25
end

-- Kubo footprints are 24 x 20, so the N/S walls sit at cz ± 10 and the E/W walls at cx ± 12.
local KUBO_WINDOWS = {
	{ Name = "Kubo_NW", X = -78, Z = -78, Height = 7 },
	{ Name = "Kubo_NE", X = 78, Z = -78, Height = 7 },
	{ Name = "Kubo_SE", X = 78, Z = 78, Height = 7 },
	{ Name = "Kubo_SW", X = -78, Z = 78, Height = 5.5 },
	{ Name = "Kubo_N", X = 35, Z = -75, Height = 5.5 },
	{ Name = "Kubo_E", X = 158, Z = -30, Height = 5.5 },
	{ Name = "Kubo_W", X = -158, Z = 40, Height = 5.5 },
}

for index, kubo in KUBO_WINDOWS do
	-- ±7.5 RATHER THAN ±6, AND THE REASON IS `building`'s DOOR GAP. A doored side is two segments
	-- with a 10-stud hole between them, so the wall only exists beyond ±5. A 4.5-wide pane centred
	-- at ±6 spanned ±3.75..±8.25 and hung half of itself in the doorway.
	-- Houses 3 and 6 keep the old warm bulb. By index rather than randomly, so the map is reproducible.
	local tint = if index % 3 == 0 then OLD_BULB else FLUORO

	window(`{kubo.Name}_WindowN`, kubo.X - 7.5, kubo.Z - 10, kubo.Height, true, houses, tint)
	window(`{kubo.Name}_WindowS`, kubo.X + 7.5, kubo.Z + 10, kubo.Height, true, houses, tint)
	window(`{kubo.Name}_WindowE`, kubo.X + 12, kubo.Z - 6, kubo.Height, false, houses, tint)
end

-- The chapel's are taller and colder — candlelight through glass, not a kitchen bulb.
-- The chapel's east door is centred at z = -152 with the same 10-stud gap, so the two east panes sit
-- outside z -157..-147 rather than straddling it. The west wall is solid and keeps the closer pair.
for index, at in { { 23, -164 }, { 23, -140 }, { -23, -158 }, { -23, -146 } } do
	local pane = prop(
		`Chapel_Window{index}`,
		at[1],
		9,
		at[2],
		4,
		6,
		5,
		Color3.fromRGB(240, 226, 190),
		Enum.Material.Neon,
		houses
	)

	pane.Transparency = 0.3
end

-- The cross on the steeple. The one piece of pure silhouette in the file: it is only ever seen
-- against the sky, which is precisely why it is worth having.
prop("Chapel_CrossV", 0, 36, -164, 1, 9, 1, STONE, Enum.Material.Concrete, houses)
prop("Chapel_CrossH", 0, 37.5, -164, 5, 1, 1, STONE, Enum.Material.Concrete, houses)

--[[
	WASHING LINES between each house and a bamboo pole in its yard.

	Hung at 9 studs — above head height, so it never reads as something you should be able to duck
	under and cannot. Non-collidable like everything here, but the height means nobody tests it.
]]
local LINES = {
	{ Name = "Wash_NW", X1 = -92, Z1 = -64, X2 = -64, Z2 = -64 },
	-- MOVED OFF SaltSpawn_KuboNE (92, -66), which the far pole stood 2 layout units from. See the
	-- salt-clearance note under the planting tables.
	{ Name = "Wash_NE", X1 = 62, Z1 = -58, X2 = 88, Z2 = -58 },
	{ Name = "Wash_SE", X1 = 64, Z1 = 64, X2 = 92, Z2 = 64 },
	{ Name = "Wash_SW", X1 = -92, Z1 = 92, X2 = -64, Z2 = 92 },
	{ Name = "Wash_N", X1 = 24, Z1 = -62, X2 = 46, Z2 = -62 },
}

for index, line in LINES do
	prop(`{line.Name}_PoleA`, line.X1, 5, line.Z1, 0.8, 10, 0.8, BAMBOO, Enum.Material.Wood, houses)
	prop(`{line.Name}_PoleB`, line.X2, 5, line.Z2, 0.8, 10, 0.8, BAMBOO, Enum.Material.Wood, houses)

	droop(
		`{line.Name}_Rope`,
		line.X1,
		line.Z1,
		line.X2,
		line.Z2,
		9.4,
		1.1,
		4,
		0.16,
		Color3.fromRGB(210, 206, 190),
		houses
	)

	-- Three garments per line, and they hang from the rope's sag rather than from a flat height, so
	-- the middle one sits lowest. Cloth is the cheapest motion-implying shape there is.
	for garment = 1, 3 do
		local t = garment / 4
		local x = line.X1 + (line.X2 - line.X1) * t
		local z = line.Z1 + (line.Z2 - line.Z1) * t
		local drop = 1.1 * 4 * t * (1 - t)

		lean(
			prop(
				`{line.Name}_Cloth{garment}`,
				x,
				9.4 - drop - 1.8,
				z,
				3,
				3.4,
				0.15,
				CLOTH[(index + garment) % #CLOTH + 1],
				Enum.Material.Fabric,
				houses
			),
			6 - garment * 4,
			true
		)
	end
end

--[[
	YARD CLUTTER — drums, sacks and crates, in clusters beside doors and the well.

	Placed as clusters rather than individually because that is how clutter actually accumulates, and
	because a table of nine coordinates is easier to check against the anchor list than a table of
	thirty. Each cluster is seeded from the file's existing `rng`, so a re-run reproduces it exactly —
	the same argument the rice field already makes.
]]
local CLUTTER = {
	{ -78, -62 },
	{ 64, -78 },
	{ 66, 64 },
	{ -62, 36 },
	{ 16, -128 },
	{ -92, 84 },
	{ 44, -66 },
	{ 150, -30 },
	{ -150, 40 },
}

for index, at in CLUTTER do
	for item = 1, rng:NextInteger(3, 5) do
		local ox = rng:NextNumber(-4, 4)
		local oz = rng:NextNumber(-4, 4)
		local kind = rng:NextInteger(1, 3)

		if kind == 1 then
			local drum = prop(
				`Clutter{index}_Drum{item}`,
				at[1] + ox,
				1.7,
				at[2] + oz,
				2.4,
				3.4,
				2.4,
				RUST,
				Enum.Material.CorrodedMetal,
				houses
			)

			drum.Shape = Enum.PartType.Cylinder
			drum.CFrame = CFrame.new(drum.Position) * CFrame.Angles(0, 0, math.rad(90))
			drum.Size = Vector3.new(3.4, 2.4, 2.4)
		elseif kind == 2 then
			turn(
				prop(
					`Clutter{index}_Sack{item}`,
					at[1] + ox,
					0.9,
					at[2] + oz,
					2.2,
					1.8,
					1.6,
					Color3.fromRGB(150, 136, 108),
					Enum.Material.Fabric,
					houses
				),
				rng:NextInteger(0, 180)
			)
		else
			turn(
				prop(
					`Clutter{index}_Crate{item}`,
					at[1] + ox,
					1.1,
					at[2] + oz,
					2.4,
					2.2,
					2.4,
					WOOD,
					Enum.Material.WoodPlanks,
					houses
				),
				rng:NextInteger(0, 90)
			)
		end
	end
end

--------------------------------------------------------------------------------
-- PLANTING — bamboo and banana, and the reason the outer band stops feeling bare.
--
-- The C17 header already records that two kubo were moved outside the ring
-- because the outer band was "about a quarter of the walkable area with nothing
-- in it, no cover, and nothing to look at". Buildings fixed the cover; this
-- fixes the looking. Planting is the cheapest possible answer — a clump of thin
-- vertical poles is six parts and breaks a sightline as well as a wall does.
--------------------------------------------------------------------------------

local planting = Instance.new("Folder")
planting.Name = "Planting"
planting.Parent = dress

local BAMBOO_AT = {
	{ -150, -110 },
	{ -152, -152 },
	{ 150, -150 },
	{ 152, 60 },
	{ 150, 112 },
	{ -110, 150 },
	{ -152, 150 },
	{ -60, -150 },
	{ 60, -150 },
	{ 112, -150 },
	{ -40, -112 },
	{ -112, -40 },
	{ 40, 118 },
	{ 118, 40 },
	{ -118, 108 },
	{ 108, -118 },
}

for index, at in BAMBOO_AT do
	--[[
		CLUMPING, NOT RUNNING — and the accurate shape is also the cheaper one.

		Philippine bamboo grows in dense clumps from a single base, with the leaf mass concentrated in
		the upper third, not spread evenly up every culm. The greybox gave a 3-blade crown to every
		pole over 20 studs, which is 201 leaf parts across sixteen clumps: the largest single block of
		geometry in the map, spent on the detail fog erases first.

		ONE CROWN PER CLUMP instead of one per culm. The silhouette that matters at night is a dark
		mass of verticals with foliage on top, and that reads from a single wide crown sitting over the
		tallest poles. `Planting` is 42% of the whole map and §5's mobile budget is non-negotiable, so
		this is where the saving comes from — never from the fence runs, which are the only thing in
		`Planting` doing layout work for the sightline rule.
	]]
	local tallest = 0

	for pole = 1, rng:NextInteger(5, 8) do
		local height = rng:NextNumber(16, 26)

		tallest = math.max(tallest, height)

		local stalk = paint(
			prop(
				`Bamboo{index}_{pole}`,
				at[1] + rng:NextNumber(-3, 3),
				height / 2,
				at[2] + rng:NextNumber(-3, 3),
				0.7,
				height,
				0.7,
				BAMBOO,
				Enum.Material.Wood,
				planting
			),
			"Bamboo"
		) :: Part

		-- Bamboo is never vertical, and the lean is what stops sixteen clumps reading as sixteen
		-- copies of one clump.
		lean(turn(stalk, rng:NextInteger(0, 90)), rng:NextNumber(-7, 7), rng:NextNumber(0, 1) > 0.5)
	end

	-- The clump's single crown, over the top of it. Three blades, not three per culm.
	for leaf = 1, 3 do
		lean(
			turn(
				prop(
					`Bamboo{index}_Crown{leaf}`,
					at[1],
					tallest - 1.5,
					at[2],
					9,
					0.2,
					5,
					LEAF,
					Enum.Material.Grass,
					planting
				),
				leaf * 60 + rng:NextInteger(-20, 20)
			),
			rng:NextNumber(-26, -8)
		)
	end
end

--[[
	Banana: a stubby trunk and four big drooping blades. Two dozen parts per plant would be a mesh's
	job; five is enough for a silhouette in fog.

	THE CLEARANCE RULE FOR EVERY TABLE IN THIS SECTION, and it is the one an art pass breaks silently.

	A prop may not come within ~4 studs of a tagged anchor's footprint. Task pads and salt spawns are
	AFFORDANCES — `Config.Salt.PickupRangeStuds` is 6 and `Tasks.PresenceRangeStuds` is 9 — so a pole
	or a leaf sitting on one does not break a check anywhere, it just quietly hides the thing a player
	is meant to find. Salt is §4.6's only answer to the Aswang, and a pouch behind a banana leaf is a
	round with no counterplay in that corner of the map.

	Nothing reports this. It was found by walking every `Dressing` part against every tagged anchor
	after the first build, which is the check worth re-running whenever a coordinate here changes.
]]
local BANANA_AT = {
	{ -96, -60 },
	{ 96, -60 },
	{ 96, 60 },
	{ -90, 52 }, -- moved off SaltSpawn_AlleySW (-100, 60); the leaves are 9 studs wide
	{ -96, -96 },
	{ 20, -96 },
	{ 52, -58 },
	{ -52, 56 },
	{ -140, -60 },
	{ 140, 100 },
	{ 62, 140 },
	{ -62, -140 },
}

for index, at in BANANA_AT do
	--[[
		ONE MESH WHERE FIVE BOXES WERE. The comment above this table said "two dozen parts per plant
		would be a mesh's job"; this is that job, done. A generated banana plant carries the drooping
		torn blades a five-box approximation cannot, at 1,500 triangles, and it removes 48 leaf parts
		and 12 trunks — the single largest budget saving in the realism pass.

		`Replaces = 60` in the registry is this line. If the asset fails to load, `mesh()` warns and
		returns nil, and the plant is absent rather than silently wrong.
	]]
	mesh("Banana", `Banana{index}`, at[1], 5.5, at[2], Vector3.new(8, 11, 8), planting)
end

--[[
	BAMBOO FENCING ALONG THE YARDS, AS PICKETS. Runs are given as two layout points; the pickets are
	spaced along them so a longer run simply gets more.

	THIS WHOLE REGION WAS DELETED BY ACCIDENT AND RESTORED FROM GIT, AND THE FAILURE IS WORTH KEEPING.
	The Phase 7 bamboo rewrite replaced a block whose end it located by counting `end` lines, miscounted
	the nesting, and took the fences, the banana table, the `FieldDressing` folder and the scarecrows
	with it. NOTHING FAILED: the build was green, `measure.luau` reported all ten lines ok, and the part
	count went DOWN — which is precisely what Phase 7 set out to do, so the deletion looked like the
	saving working. `local field` became nil and the drying racks silently reparented to `dress`.

	It was caught by counting MeshParts in the live map and finding fourteen missing. The plan had named
	these 72 fence parts as the one thing in `Planting` that must NOT be thinned — they are the only
	planting doing LAYOUT work, suggesting the alley walls and field edges §5's sightline rule needs.

	`tests/barrio-budget.test.luau` now asserts every structure in this region by name.
]]
local FENCES = {
	{ Name = "Fence_NW", X1 = -94, Z1 = -94, X2 = -62, Z2 = -94 },
	{ Name = "Fence_NE", X1 = 62, Z1 = -94, X2 = 94, Z2 = -94 },
	{ Name = "Fence_SE", X1 = 94, Z1 = 62, X2 = 94, Z2 = 94 },
	{ Name = "Fence_SW", X1 = -94, Z1 = 62, X2 = -94, Z2 = 94 },
	{ Name = "Fence_Well", X1 = -84, Z1 = 20, X2 = -84, Z2 = 46 },
	{ Name = "Fence_Chapel", X1 = -34, Z1 = -134, X2 = -34, Z2 = -166 },
}

for _, fence in FENCES do
	local length = math.sqrt((fence.X2 - fence.X1) ^ 2 + (fence.Z2 - fence.Z1) ^ 2)
	local count = math.max(math.floor(length / 2.2), 2)

	for picket = 0, count do
		local t = picket / count
		local height = rng:NextNumber(4.5, 5.8)

		lean(
			prop(
				`{fence.Name}_{picket}`,
				fence.X1 + (fence.X2 - fence.X1) * t,
				height / 2,
				fence.Z1 + (fence.Z2 - fence.Z1) * t,
				0.5,
				height,
				0.5,
				BAMBOO,
				Enum.Material.Wood,
				planting
			),
			rng:NextNumber(-5, 5),
			true
		)
	end
end

--------------------------------------------------------------------------------
-- THE RICE FIELD — §5's killing field, and the only place the dressing is
-- allowed to make things WORSE to see. A drying rack, sacks, and two scarecrows.
--
-- The scarecrows are deliberate: a human silhouette that does not move is the
-- single cheapest scare in a game whose whole tension is "is that a player".
-- §4.3 makes the Aswang read as a player until it transforms, so a field with
-- standing figures in it makes every glance across it cost something.
--------------------------------------------------------------------------------

local field = Instance.new("Folder")
field.Name = "FieldDressing"
field.Parent = dress

--[[
	THE SCARECROWS. Five boxes became one generated figure — crossed bamboo, ragged shirt, straw hat.
	The old comment was right that the hat "makes it read as a figure rather than a post with a bag on
	it"; the mesh carries that silhouette without spending five parts on it, twice.

	They lean, and they lean differently. A scarecrow standing perfectly upright in a paddy is the one
	pose a real one never holds.
]]
for index, at in { { 75, 150 }, { 140, 164 } } do
	local figure = mesh("Scarecrow", `Scarecrow{index}`, at[1], 5, at[2], Vector3.new(4.5, 10, 2.5), field)

	if figure then
		figure.CFrame = figure.CFrame * CFrame.Angles(math.rad(9 * index), math.rad(40 * index), math.rad(-6))
	end
end

-- A drying rack and its sacks: the reason a task point is out here at all.
for index, at in { { 60, 145 }, { 112, 167 } } do
	prop(`Rack{index}_Frame`, at[1], 2.6, at[2], 12, 0.5, 6, WOOD, Enum.Material.WoodPlanks, field)
	prop(`Rack{index}_LegA`, at[1] - 5, 1.3, at[2], 0.6, 2.6, 0.6, WOOD, Enum.Material.Wood, field)
	prop(`Rack{index}_LegB`, at[1] + 5, 1.3, at[2], 0.6, 2.6, 0.6, WOOD, Enum.Material.Wood, field)
	prop(
		`Rack{index}_Grain`,
		at[1],
		3,
		at[2],
		11,
		0.35,
		5,
		Color3.fromRGB(178, 158, 108),
		Enum.Material.Sand,
		field
	)

	for sack = 1, 3 do
		turn(
			prop(
				`Rack{index}_Sack{sack}`,
				at[1] - 6 + sack * 3,
				0.9,
				at[2] + 5,
				2.2,
				1.8,
				1.6,
				Color3.fromRGB(150, 136, 108),
				Enum.Material.Fabric,
				field
			),
			rng:NextInteger(0, 180)
		)
	end
end

--------------------------------------------------------------------------------
-- THE LAST DETAILS — a graveyard beside the chapel, two parked tricycles, and
-- puddles on the roads.
--
-- Puddles are the highest ratio of atmosphere to parts in the whole file: a flat
-- dark slab with a low Reflectance catches the lanterns and the moon, and wet
-- ground is most of why a night street looks like a night street.
--------------------------------------------------------------------------------

--[[
	THE FIFTEEN CONTAINERS, MADE VISIBLE — and this is a PLAYABILITY fix, not decoration.

	Step 4.5's gate capture looked into a kubo interior at `Container_KuboNW_Chest` and the container
	was not merely hard to see, it was INVISIBLE: a flat blue 6-stud pad in an unlit room reads as
	nothing at all. §5 requires containers be "visually obvious as searchable at a glance, on a phone,
	in the dark", and v2.0's whole loop is searching. A player standing four studs from a container and
	unable to tell it is there is not an art problem.

	NEON, NOT A LIGHT, AND THAT IS THE WHOLE TRICK. Fifteen PointLights would break two rules at once:
	the builder asserts zero dressing lights (C30 rule 2) and `PerformanceController` caps visible
	lights at `Config.Performance.MaxVisibleLights`. Neon is emissive geometry — it glows without
	occupying a light slot, costs nothing on a phone, and is exactly what the banderitas bulbs already
	do. A dim warm band on a dark crate reads from across a room and never from behind a wall.

	THE TAGGED PART DOES NOT MOVE. These props sit AT the anchor's coordinates; `anchor()` already
	placed the tagged pad there and `SearchService` measures from it. The pad also stays visible under
	the prop, deliberately: it is 6 studs across, which is the honest affordance for how close you have
	to get, and C17 made that argument for the task pads.
]]
local containers = Instance.new("Folder")

containers.Name = "Containers"
containers.Parent = dress

for _, container in SEARCH_CONTAINERS do
	local holder = Instance.new("Folder")

	holder.Name = container.Name
	holder.Parent = containers

	-- The body: a sack, crate or chest depending on what the name says it is.
	local isSack = string.find(container.Name, "Sack") ~= nil or string.find(container.Name, "Goods") ~= nil
	local body = paint(
		prop(
			`{container.Name}_Body`,
			container.X,
			1.3,
			container.Z,
			if isSack then 2.6 else 3.2,
			2.4,
			if isSack then 2.6 else 2.2,
			if isSack then Color3.fromRGB(150, 134, 104) else Color3.fromRGB(104, 82, 58),
			if isSack then Enum.Material.Sand else Enum.Material.WoodPlanks,
			holder
		),
		if isSack then "Sack" else "Bamboo"
	)

	turn(body :: Part, ((container.X * 7 + container.Z * 13) % 60) - 30)

	--[[
		THE GLOW BAND. Thin, dim and low on the body — enough to say "there is a thing here" at a
		glance without lighting the room, which would wreck the partial-information rule §5 is built
		on: "total darkness is not scary, it's just confusing. Fear comes from PARTIAL information."
	]]
	local glow = prop(
		`{container.Name}_Glow`,
		container.X,
		2.45,
		container.Z,
		if isSack then 2.8 else 3.4,
		0.18,
		if isSack then 2.8 else 2.4,
		Color3.fromRGB(255, 206, 148),
		Enum.Material.Neon,
		holder
	)

	--[[
		THE BAND SITS ON THE LID, NOT INSIDE THE BOX, AND THE FIRST VERSION DID NOT.

		It was authored at y = 0.65 while the body spans 0.1 to 2.5 — entirely enclosed, emitting into
		the inside of a crate. The re-test capture showed the crate silhouette appear and the glow
		still absent, which looks exactly like Neon being too dim rather than geometry being hidden.
		At 2.45 it rims the top edge, which is also where a lid would catch light.

		Transparency was 0.35 and is now 0.15: on `Neon` transparency scales the EMISSION, so a third
		of the glow was being thrown away on a part whose entire job is to be seen in the dark.
	]]
	glow.Transparency = 0.15
end

local details = Instance.new("Folder")
details.Name = "Details"
details.Parent = dress

--[[
	THE EIGHT GRAVES — beside the chapel, west of it, clear of the north road and the chapel's own
	container pads.

	NOT A CEMETERY ZONE, DELIBERATELY. §5's required-zone list does not include one and the map holds
	a ~35-second crossing; these are detailed where they already stood rather than gathered into a new
	plot. What changes is what they ARE: two crossed boxes became a generated concrete marker, tilted
	and moss-stained, which is what a Philippine grave marker actually looks like — painted concrete,
	not carved granite.
]]
for index = 1, 8 do
	local x = -50 + (index % 3) * 7
	local z = -164 + math.floor((index - 1) / 3) * 10
	local height = rng:NextNumber(2.6, 3.8)

	--[[
		THE TOMB SLAB — the single biggest correction research-05 gives, and it changes the silhouette
		from headstone to tomb. Philippine grave markers are typically ABOVE-GROUND painted concrete
		tombs, not carved granite stones sunk into turf. The marker stands ON this rather than in the
		ground.
	]]
	paint(
		prop(
			`Grave{index}_Tomb`,
			x,
			0.45,
			z,
			3.4,
			0.9,
			6.5,
			Color3.fromRGB(150, 148, 138),
			Enum.Material.Concrete,
			details
		),
		"Whitewash"
	)

	--[[
		A CANDLE STUB, AND IT IS `Neon` RATHER THAN A `PointLight`. Eight new lights would be a 57%
		overspend of the entire map's light budget against `Config.Performance.MaxVisibleLights`, and
		the builder asserts zero dressing lights outright — the build would fail, which is the guard
		working. Emissive geometry gives the same read for no light slot, exactly as the banderitas
		bulbs and the container bands do.
	]]
	local candle = prop(
		`Grave{index}_Candle`,
		x + rng:NextNumber(-1.1, 1.1),
		1.15,
		z + rng:NextNumber(-2.4, 2.4),
		0.34,
		0.5,
		0.34,
		Color3.fromRGB(255, 198, 132),
		Enum.Material.Neon,
		details
	)

	candle.Transparency = 0.1

	local marker = mesh("GraveMarker", `Grave{index}`, x, 0.9 + height / 2, z, Vector3.new(1.8, height, 0.6), details)

	-- Every one leans differently. A row of upright markers reads as a fence, not a graveyard.
	if marker then
		marker.CFrame = marker.CFrame * CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-7, 7)))
	end
end

--[[
	TWO TRICYCLES, PARKED. The old comment said "the sidecar is what makes the shape unmistakable, and
	it is three boxes" — plus a roof, bars and three cylinder wheels, so eight parts each. One
	generated mesh carries the whole silhouette including the welded cab and the dented tin roof, and
	it can be turned freely, which the box version explicitly could not: "axis-aligned on purpose,
	turning the folder means turning every child about a shared centre".

	So they now sit at angles, which is how a tricycle is actually parked — never square to the road.
]]
for index, at in { { -22, -40 }, { 95, -90 } } do
	--[[
	SCALED UP. It was 7 x 4.4 x 4 studs, which is roughly a large dog. A real tricycle is a motorcycle
	with a welded sidecar — about 2.5m long and tall enough to sit upright inside, so ~10 x 6 x 5.5
	studs puts it at the right size next to a 5-stud character.
]]
	local trike = mesh("Tricycle", `Tricycle{index}`, at[1], 3, at[2], Vector3.new(10, 6, 5.5), details)

	if trike then
		trike.CFrame = trike.CFrame * CFrame.Angles(0, math.rad(if index == 1 then 34 else -118), 0)
	end
end

-- On the roads, in the ruts. Reflectance rather than a material: `Ground` under a wet slab is what a
-- puddle actually is, and 0.35 is enough to catch a lantern without turning into a mirror.
for index, at in
	{
		{ 0, -70 },
		{ 0, 76 },
		{ 70, 0 },
		{ -86, 0 },
		{ 0, -112 },
		{ 100, -100 },
		{ -100, 48 },
		{ 130, 62 },
		{ -130, -70 },
		{ 46, 100 },
	}
do
	local puddle = paint(
		prop(
			`Puddle{index}`,
			at[1],
			0.14,
			at[2],
			rng:NextNumber(5, 11),
			0.1,
			rng:NextNumber(4, 9),
			Color3.fromRGB(24, 26, 32),
			Enum.Material.SmoothPlastic,
			details
		),
		"WetEarth"
	)

	puddle.Reflectance = 0.35
	turn(puddle, rng:NextInteger(0, 180))
end

--------------------------------------------------------------------------------
-- THE SOLO TRIAL CORNER (C21, §9.1)
--
-- A walled corner OUTSIDE the barrio's playable ring, reachable only by being
-- teleported into it. It is not connected to the streets on purpose: a player who
-- can wander into the tutorial area mid-round finds two task points that do not
-- count and a chase rig that is not there, which reads as a broken map.
--------------------------------------------------------------------------------

--[[
	`TrialOnly = true` IS THE WHOLE CONTRACT AND IT IS AN EXCLUSION, NOT AN INCLUSION.

	The trial's two practice points carry the `TaskPoint` tag, which after V01 NOTHING in the round
	reads — `TrialService` is its only remaining consumer. The attribute is kept anyway, and keeping it
	is a deliberate belt-and-braces: under v1.3 a round could draw one of these and put a live objective
	in a corner of the map no player can walk to. That failure is gone with the task system, but the
	attribute costs nothing and documents which two points are sealed off from the barrio proper.

	If a trial point is ever added by hand and the attribute is forgotten, the symptom is a task
	nobody can find, appearing at random every few rounds, with nothing logged and nothing failing.
	This is the one map contract in this file whose violation is completely silent, which is why it is
	written out at this length.

	NOTE THE NAME. An earlier draft called this `TrialZone`; `check:scope` refuses "Zone" because
	zone-based progression is on §3's OUT list — the competitor's seven zones (Appendix C.5). The
	current name is also the more accurate one: it states what the attribute does to the round's draw.
]]
local TRIAL_X = -300
local TRIAL_Z = 300

local trial = Instance.new("Folder")
trial.Name = "TrialCorner"
trial.Parent = root

box("TrialFloor", TRIAL_X, 0, TRIAL_Z, 90, 1, 90, Color3.fromRGB(38, 40, 50), trial)

-- Four walls, so a player cannot wander out of the tutorial into empty space and fall forever.
box("TrialWallN", TRIAL_X, 6, TRIAL_Z - 45, 90, 12, 2, Color3.fromRGB(30, 32, 40), trial)
box("TrialWallS", TRIAL_X, 6, TRIAL_Z + 45, 90, 12, 2, Color3.fromRGB(30, 32, 40), trial)
box("TrialWallW", TRIAL_X - 45, 6, TRIAL_Z, 2, 12, 90, Color3.fromRGB(30, 32, 40), trial)
box("TrialWallE", TRIAL_X + 45, 6, TRIAL_Z, 2, 12, 90, Color3.fromRGB(30, 32, 40), trial)

anchor("TrialSpawn_Entry", "TrialSpawn", TRIAL_X - 30, TRIAL_Z, trial)

-- The two practice points. Both HOLD: the trial teaches the ONE interaction a new player needs, and
-- §9.1's "complete two tasks to learn the interaction" is singular for a reason. A TIMING point here
-- would teach a second verb before the first has landed.
anchor("TrialTask_One", "TaskPoint", TRIAL_X, TRIAL_Z - 18, trial, {
	TaskType = "HOLD",
	TrialOnly = true,
})

anchor("TrialTask_Two", "TaskPoint", TRIAL_X + 20, TRIAL_Z + 16, trial, {
	TaskType = "HOLD",
	TrialOnly = true,
})

-- Where the scripted rig appears at ScriptedChaseAt — the far end, so the player sees it arrive
-- rather than finding it already beside them. C22's tell is only learnable if it is watched.
anchor("TrialChase_Far", "TrialChase", TRIAL_X + 34, TRIAL_Z, trial)

lantern("TrialLantern", TRIAL_X, TRIAL_Z, trial)

--------------------------------------------------------------------------------
-- LIGHTING AND STREAMING
--
-- §5's art strategy, and it is the reason a parts-only greybox is allowed to look
-- like anything at all: "darkness, fog and lighting hide low-poly geometry. This
-- is a genuine advantage of the genre you chose."
--------------------------------------------------------------------------------

-- `Technology` is not always writable from a command-bar context, and a refusal here would abort the
-- whole build after the geometry is already placed. It is the one property in this file that is a
-- preference rather than a requirement, so it is allowed to fail loudly and let the rest land.
local ok, err = pcall(function()
	Lighting.Technology = Enum.Technology.Future
end)

if not ok then
	--[[
		THIS WARNING USED TO SAY "set it by hand in Studio" AND THAT ADVICE IS NOW WRONG.

		`Lighting.Technology` is not merely script-blocked, it is GONE FROM THE PROPERTIES PANEL in
		current Studio — filtering for it returns nothing. Roblox has moved to Unified Lighting, where
		the engine owns `Technology` and the author's remaining control is `Lighting.LightingStyle`
		(`Realistic` or `Soft`). Both are blocked to this thread by capability, not by validity: the
		properties exist, a script just may not touch them.

		So §5's "use Future lighting" is a v1.3-era instruction. There is no Future to select any more,
		and the modern equivalent of that intent is LightingStyle. Set it in the Properties panel with
		Lighting selected; the enum has exactly two values.
	]]
	warn(
		`[barrio] Lighting.Technology is engine-owned now, not scriptable ({err}). `
			.. `There is no Technology dropdown in current Studio — select Lighting and set `
			.. `LightingStyle (Realistic or Soft) in the Properties panel instead.`
	)
end

--[[
	THESE VALUES ARE THE NIGHT, AND SINCE C28 THEY ARE ALSO AN INPUT.

	`SkyController` reads Brightness, FogEnd, Ambient, OutdoorAmbient and the Atmosphere's Density off
	the place once at startup and treats them as the baseline it lerps toward dawn and back — so this
	block is still the only place the barrio's night is authored, and C30's art pass retunes it here
	without touching `Config` or any controller.

	`ClockTime` is the exception: it is the one term the ROUND owns (`Config.Sky.StartClockTime`), and
	the 0 below is what a map author sees in Studio rather than what a player sees in a lobby.
]]
--[[
	THE FIVE PROPERTIES `SkyController` CAPTURES — retuning them here is correct and supported.

	The controller reads Brightness, FogEnd, Ambient, OutdoorAmbient and the Atmosphere's Density ONCE
	at startup and treats whatever it finds as the baseline it lerps toward dawn and back. `Config.Sky`
	holds only multipliers. So these are the map author's to set, and the dawn curve over them is what
	`tests/sky-cycle.test.luau` proves.

	ONE CONSEQUENCE THAT COSTS TIME IF YOU DO NOT KNOW IT: the capture happens once at `Start`, so a
	change here is invisible until the play session is restarted. A retune that "did nothing" almost
	always means the session was still running.

	WARMER, NOT BRIGHTER. Research-04 describes rural barangay light as sparse warm sodium and CFL with
	DEEP SHADOW between — so `OutdoorAmbient` moves off its blue toward a dim warm grey rather than up.
	Raising `Ambient` is the most tempting change available here and the most damaging: it flattens the
	entire map at once and erases exactly the shadow the look depends on. §5 wants partial information,
	and the answer to a too-dark barrio is more lanterns spaced further apart, never a higher ambient.
]]
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(15, 15, 22)
Lighting.OutdoorAmbient = Color3.fromRGB(34, 30, 34)

--[[
	THE PROPERTIES NOTHING OWNS AT RUNTIME — `SkyController` never touches these, so the builder owns
	them outright and they are the safest realism budget in the plan.

	`EnvironmentDiffuseScale` down: it is a flat fill from the skybox and it is what makes an unlit
	Roblox night read as evenly grey rather than dark. Specular stays a little higher than diffuse so
	wet ground and tin roofs still catch a highlight, which is most of what says "humid" here.
]]
Lighting.EnvironmentDiffuseScale = 0.12
Lighting.EnvironmentSpecularScale = 0.28
Lighting.GlobalShadows = true
-- Scaled with the map, because fog is a fraction of the map rather than a distance. §5 wants partial
-- information — "you should almost always be able to see *something*" — and a fog wall that stayed put
-- while the barrio grew would make a bigger map no darker, only emptier.
Lighting.FogEnd = 220 * SCALE
Lighting.FogColor = Color3.fromRGB(20, 19, 24)

local atmosphere = Lighting:FindFirstChildWhichIsA("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.42
atmosphere.Offset = 0.1
--[[
	The atmosphere's own colour and decay are unowned at runtime too. `Decay` is the colour distant
	geometry sinks toward, so it is the single strongest control over how the barrio reads at the fog
	boundary — warmed off blue toward a brown-grey, which is what humid air over dirt actually does to
	a silhouette, and which lets the lanterns stay the only cool-free warm points in the frame.

	`Haze` is raised a little rather than a lot: haze hides geometry, and §5's sightline rule needs you
	to almost always see SOMETHING. Density stays where it is because `SkyController` captures it.
]]
atmosphere.Color = Color3.fromRGB(158, 154, 156)
atmosphere.Decay = Color3.fromRGB(74, 68, 66)
atmosphere.Glare = 0.16
atmosphere.Haze = 2.6
atmosphere.Parent = Lighting

--[[
	§5: "Enable StreamingEnabled" — and the build plan adds "from the start, retrofitting it later is
	miserable". Set here rather than by hand so a fresh place file gets it by running this file.

	C27 TUNES THE RADII, and they live here rather than in `Config` for the same reason `SCALE` does:
	they are properties of the PLACE, saved into the place file, and they are meaningless without the
	map they are measured against. A streaming radius is a distance in this barrio, so a resize moves
	it — hence both are written as multiples of the fog distance the map already sets, which is
	already scaled.

	TARGET is what a client tries to have loaded: matched to the fog wall, because a part that appears
	inside visible range is a part a player watches pop in, and one that never loads past the fog is
	free. MIN is the guaranteed floor a client always holds regardless of memory pressure — a chase
	crossing an unloaded street is the failure this prevents, and §5's worst case is exactly a chase.

	`StreamingEnabled` itself can only be set in Studio, which is why this file is where it happens.
]]
workspace.StreamingEnabled = true

--[[
	THE TWO RADII ARE NO LONGER SCRIPTABLE, AND THIS ABORTED THE WHOLE BUILD.

	`workspace.StreamingTargetRadius = ...` now raises "StreamingTargetRadius is not a valid member of
	Workspace". Both radii have left the scriptable API — they are absent from `.luau-defs/globalTypes`
	as well, which is why `luau-lsp analyze` flags the same two lines — and they are set from the
	Properties panel instead.

	It threw at the LAST executable statement before the receipt, so the whole barrio built correctly
	and then the script died one line before printing that it had. The symptom was an error about
	streaming and no receipt at all, which reads as "the build failed" when nothing of the sort
	happened. That is the same shape as the `Lighting.Technology` refusal above, so it gets the same
	treatment: attempt it, survive the refusal, and say what a human has to do by hand.

	C17's measured values, for whoever sets them: TARGET 341, MIN 170 (220 and 110 at SCALE 1.55).
]]
local streamingOk, streamingErr = pcall(function()
	(workspace :: any).StreamingTargetRadius = math.floor(220 * SCALE);
	(workspace :: any).StreamingMinRadius = math.floor(110 * SCALE)
end)

if not streamingOk then
	warn(
		`[barrio] streaming radii are not scriptable ({streamingErr}) — set them on Workspace by hand: `
			.. `StreamingTargetRadius = {math.floor(220 * SCALE)}, StreamingMinRadius = {math.floor(
				110 * SCALE
			)}`
	)
end

--------------------------------------------------------------------------------
-- THE RECEIPT
--
-- Counted from CollectionService rather than from the tables above, because the
-- tables are what this script INTENDED and the tags are what the services will
-- actually find. A typo'd tag name would agree with the table and disagree here.
--------------------------------------------------------------------------------

local function count(tag: string): number
	return #CollectionService:GetTagged(tag)
end

-- The trial's two points are counted SEPARATELY from the round's twelve, because the round's draw is
-- the number that matters and `count("TaskPoint")` alone would now read 14 and look like a map error.
local function countTrialOnly(): number
	local n = 0

	for _, part in CollectionService:GetTagged("TaskPoint") do
		if part:GetAttribute("TrialOnly") == true then
			n += 1
		end
	end

	return n
end

print(
	`[barrio] built — {count("SearchContainer")} SearchContainer, {count("SaltSpawn")} SaltSpawn, `
		.. `{count("AmbientSpawn")} AmbientSpawn, {countTrialOnly()} TrialOnly TaskPoint, `
		.. `{count("TrialSpawn")} TrialSpawn, `
		.. `{count("TrialChase")} TrialChase, {#root:GetDescendants()} instances, scale {SCALE}`
)

--[[
	THE CONTRACT ASSERTED, NOT MERELY PRINTED — the same upgrade C30 made for colliders and lights.

	A receipt you have to read is a receipt nobody reads. Each of these three fails the BUILD, because
	each one's player-visible symptom is "the game is boring" with nothing in the log to explain it.

	THE LITERALS ARE HAND-COPIED FROM `Config.luau` AND THAT IS UNAVOIDABLE HERE. This file runs in
	Studio's command bar, where `require` of a Rojo-synced module is not reliably available at build
	time, so it cannot read Config directly. `tests/barrio-receipt.test.luau` reconciles these three
	numbers against `src/shared/Config.luau` as text, which is what makes hand-copying safe to do.
]]
assert(
	count("SearchContainer") == 15,
	`[barrio] {count("SearchContainer")} SearchContainer parts, expected 15 — SearchService's pool will be short`
)
assert(
	count("AmbientSpawn") == 16,
	`[barrio] {count("AmbientSpawn")} AmbientSpawn parts, expected 16 — AmbientService will fall back to a ring at the origin`
)
assert(
	countTrialOnly() == 2,
	`[barrio] {countTrialOnly()} TrialOnly TaskPoint parts, expected 2 — the Solo Trial has nothing to do`
)

--[[
	C30's SECOND RECEIPT, and it exists because this chunk's done condition is a PERFORMANCE claim
	as much as a visual one: "crossing time unchanged; FPS unchanged".

	Two of these three numbers are the ones that could break it, and both are asserted rather than
	merely printed — a dressing pass that quietly added a collidable prop or a PointLight would
	otherwise be discovered by a player on a phone, which is the worst place to discover it.

	  · COLLIDERS. Nothing in `Dressing` may collide. PathfindingService builds its navmesh from
	    collision geometry, so this is the property that makes "crossing time unchanged" true by
	    construction rather than by hoping the re-measure agrees.
	  · LIGHTS. `Dressing` adds none. Fourteen was the count before this chunk and it is the count
	    after it, so `Config.Performance.MaxVisibleLights` is spending exactly what it spent at C28.
]]
local dressing = root:FindFirstChild("Dressing")
local dressParts, dressColliders, dressLights = 0, 0, 0

if dressing then
	for _, item in dressing:GetDescendants() do
		if item:IsA("BasePart") then
			dressParts += 1

			if item.CanCollide then
				dressColliders += 1
			end
		elseif item:IsA("Light") then
			dressLights += 1
		end
	end
end

local mapLights = count("MapLight")
local totalLights = 0

for _, item in root:GetDescendants() do
	if item:IsA("Light") then
		totalLights += 1
	end
end

print(
	`[barrio] dressing — {dressParts} props, {dressColliders} colliders, {dressLights} own lights; `
		.. `{totalLights} lights in the barrio, {mapLights} tagged MapLight`
)

assert(
	dressColliders == 0,
	`[barrio] C30 RULE 1 BROKEN: {dressColliders} dressing parts collide — the navmesh, and therefore the crossing time, has moved`
)
assert(
	dressLights == 0,
	`[barrio] C30 RULE 2 BROKEN: dressing added {dressLights} dynamic lights — Config.Performance.MaxVisibleLights is being overspent`
)
assert(
	mapLights == totalLights,
	`[barrio] {totalLights - mapLights} light(s) in the barrio are not tagged MapLight — PerformanceController cannot cull what it cannot see`
)
