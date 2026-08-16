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

	  TaskPoint    ×12  TaskService.discoverPool      unique Names; Config.Tasks.PoolSize
	                    attribute `TaskType`          HOLD | TIMING | FETCH | TWO_PERSON, absent = HOLD
	                    attribute `FetchSourceName`   names a FetchSource; absent = furthest unused
	  FetchSource  × 4  TaskService.discoverSources   one per FETCH task drawn in a round
	  SaltSpawn    × 6  ItemService.discoverPool      Config.Salt.PouchPoolSize
	  EscapeGate   × 1  GateService.discoverGates     proximity win, Config.Tasks.GateRangeStuds = 6

	THE TYPE MIX IS A MAP DECISION AND IT IS LOAD-BEARING. Five of the twelve are drawn each round, and
	the draw does not balance types — plan `feature-c09-c12` logged the open risk that a round could
	draw five TWO_PERSON and be unfinishable at MinPlayers = 3. The mix below is 5 HOLD / 3 TIMING /
	2 FETCH / 2 TWO_PERSON, so the worst possible draw is two TWO_PERSON and two FETCH, which three
	players can finish. Changing that ratio is changing the game's floor, not its decoration.
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

local GREY = Color3.fromRGB(112, 112, 108)
local ROAD = Color3.fromRGB(88, 86, 82)
local PLAZA_C = Color3.fromRGB(124, 122, 116)
local WOOD = Color3.fromRGB(96, 84, 68)
local THATCH = Color3.fromRGB(120, 104, 74)
local STONE = Color3.fromRGB(104, 104, 104)
local GRASS = Color3.fromRGB(74, 92, 58)
local ANCHOR_C = Color3.fromRGB(70, 90, 120)

-- Seeded, so two runs of the same file produce the same barrio. The rice field is the only thing that
-- uses it; a jittered field that moved every run would make "did the layout change?" unanswerable.
local rng = Random.new(20260816)

local root: Folder

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x * SCALE, y, z * SCALE)
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
	wallColour: Color3
): Folder
	local folder = Instance.new("Folder")

	folder.Name = name
	folder.Parent = root

	local t = 2 -- wall thickness
	local door = 10
	local hw, hd = w / 2, d / 2

	box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
	box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)

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
				)
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
				)
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
				)
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
				)
			end
		end
	end

	side("N", true, -1)
	side("S", true, 1)
	side("E", false, 1)
	side("W", false, -1)

	return folder
end

--[[
	A lantern: a post and one warm PointLight.

	§5's mobile budget caps DYNAMIC LIGHTS AT ~8 VISIBLE AT ONCE and names many point lights the #1
	mobile FPS killer. Twelve exist, spread over 360 studs at range 26, so two or three are in view at
	any time — the cap is met by SPACING rather than by count, which is what lets the sightline rule
	("you should almost always be able to see *something*") hold at the same time.
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
ground.Material = Enum.Material.Grass

local walls = Instance.new("Folder")
walls.Name = "Perimeter"
walls.Parent = root

box("Wall_N", 0, WALL_H / 2, -HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_S", 0, WALL_H / 2, HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_E", HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)
box("Wall_W", -HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)

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
			)
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
			)
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
spawnPad.Position = v(0, 0.5, 14)
spawnPad.Anchored = true
spawnPad.Color = PLAZA_C
spawnPad.Neutral = true
spawnPad.Parent = workspace

--[[
	THE ARKO — the escape gate, and it stands IN the plaza because §5 puts it there.

	Escaping is a PROXIMITY check, not a doorway you pass through: `GateService` measures
	`Config.Tasks.GateRangeStuds` (6) from this part's position and `pure/GateEscape` decides. So the
	gate does not need to lead anywhere, and the design gains something from that — survivors must come
	BACK to the middle of the map to win, which is the one place the Aswang can reliably camp.

	`GateService` captures Transparency and CanCollide at STARTING and restores what it captured when
	the gate closes, rather than restoring defaults. So whatever is set here is what "closed" looks
	like for the rest of the session — the MonsterService revert bug was exactly the opposite mistake.
]]
local arko = Instance.new("Folder")
arko.Name = "Arko"
arko.Parent = root

box("Arko_PillarW", -11, 8, -32, 4, 16, 4, STONE, arko)
box("Arko_PillarE", 11, 8, -32, 4, 16, 4, STONE, arko)
box("Arko_Lintel", 0, 17, -32, 26, 3, 4, STONE, arko)

--[[
	A LOW GATE LEAF UNDER A TALL ARCH, AND THE HEIGHT IS A GAMEPLAY NUMBER RATHER THAN A LOOK.

	This filled the whole archway first — 15 studs tall, centred at y = 7.5 — and that quietly broke
	escaping. `GateService.step` computes `(position - gate.Position).Magnitude`, a FULL 3D distance
	from the player's `HumanoidRootPart` (about 3 studs off the ground) to this part's CENTRE, against
	`Config.Tasks.GateRangeStuds` = 6. A centre 7.5 studs up spends 4.5 of those 6 studs going
	vertically, leaving `sqrt(36 - 20.25)` ≈ 3.97 studs of horizontal reach across a gate 27.9 studs
	wide. Survivors would have finished every task, opened the gate, stood in it, and not won.

	Nothing would have reported that. The round simply would not end, and the bug report is "we did
	everything and nothing happened" — the exact sentence `GateService`'s own no-gate warning exists to
	prevent, arriving by a route that warning cannot see.

	Centred at y = 3 the vertical term is ~0 and the full 6 studs are horizontal. Six studs tall still
	blocks a character (max step is ~2), so the barrier is real, and a waist-high leaf under a tall arch
	is what an arko looks like anyway.

	MEASURED, NOT REASONED: `measure.luau`'s REACH check now includes the gate, which is how this was
	found at all. Before that fix it only walked `Anchors` children and the gate lives under `Arko`.
]]
local gate = box("EscapeGate", 0, 3, -32, 18, 6, 1.5, Color3.fromRGB(148, 128, 92), arko)
gate.Material = Enum.Material.WoodPlanks
gate.Transparency = 0
gate.CanCollide = true
CollectionService:AddTag(gate, "EscapeGate")

--[[
	THE CHAPEL — §5's "one interior, strong lighting moment", at the north end of the north road.

	TWO DOORS, and the second one is not decoration. A single-door chapel at the end of a radial is a
	dead end, which §5 rules out by name; the east door opens onto the outer band beyond the ring, so
	even the building loops.
]]
building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE)
box("Chapel_Steeple", 0, 24, -164, 10, 16, 10, STONE)

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

--[[
	SEVEN BAHAY KUBO, THREE ENTERABLE — §5 asks for 6–8 with at least 3 interiors.

	The four sealed ones are not laziness. Their job is to BREAK SIGHTLINES so the sightline rule can be
	partial rather than absent: you can almost always see something, and almost never everything.
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
	{ Name = "Kubo_SW", X = -78, Z = 78, Doors = {}, Enterable = false },
	{ Name = "Kubo_N", X = 35, Z = -75, Doors = {}, Enterable = false },

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

for _, kubo in KUBO do
	-- Sealed ones are built SHORTER rather than stilted. Stilts would be the real bahay kubo
	-- silhouette and they were tried first, but a stilted floor needs a ramp to be walkable and a ramp
	-- is a pathfinding problem this milestone has no reason to buy. Height is the cheap way to vary a
	-- skyline, and varying the skyline is all the silhouette has to do before GATE 1.
	building(kubo.Name, kubo.X, kubo.Z, 24, 20, if kubo.Enterable then 12 else 9, kubo.Doors, WOOD)
end

-- THE WELL / PUMP AREA — §5's fifth zone. A social waypoint off the west road, tucked behind Kubo_SW
-- so that reaching it costs a moment out of sight.
local wellFolder = Instance.new("Folder")
wellFolder.Name = "Well"
wellFolder.Parent = root

for index = 1, 8 do
	local angle = (index - 1) * math.pi / 4

	box(
		`Well_Ring{index}`,
		-70 + math.cos(angle) * 6,
		1.5,
		32 + math.sin(angle) * 6,
		3,
		3,
		3,
		STONE,
		wellFolder
	)
end

box("Well_Pump", -58, 2.5, 40, 2, 5, 2, STONE, wellFolder)
box("Well_LowWall", -70, 1, 48, 26, 2, 2, STONE, wellFolder)

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
	blade.Material = Enum.Material.Grass
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
	Twelve task points, and the SPREAD is the point of the list.

	Two sit in the plaza where it is safest, three in interiors, two in the rice field where it is
	worst, and the rest along the ring and the alleys. A pool clustered in one quarter would make the
	5-of-12 draw meaningless: every round would send everyone to the same place, and §4.4's isolation —
	the thing that gives the Aswang any opening at all — would never happen.

	The two FETCH points name their sources explicitly through `FetchSourceName` rather than leaning on
	TaskService's furthest-unused fallback. The fallback is correct but it is a fallback: it picks by
	distance alone, and a pairing chosen by hand can also cross the map's worst ground on the way.
]]
local TASK_POINTS = {
	{ Name = "Task_ChapelAltar", X = 0, Z = -158, Type = "TIMING" },
	{ Name = "Task_ChapelBell", X = 17, Z = -140, Type = "HOLD" },
	{ Name = "Task_PlazaNotice", X = -25, Z = 20, Type = "HOLD" },
	{ Name = "Task_PlazaCart", X = 28, Z = -18, Type = "TWO_PERSON" },
	{ Name = "Task_WellPump", X = -64, Z = 42, Type = "HOLD" },
	{ Name = "Task_KuboNWHearth", X = -78, Z = -78, Type = "FETCH", Source = "FetchSource_Rice" },
	{ Name = "Task_KuboNELoom", X = 78, Z = -78, Type = "HOLD" },
	{ Name = "Task_KuboSEStore", X = 78, Z = 78, Type = "FETCH", Source = "FetchSource_Chapel" },
	{ Name = "Task_RiceSluice", X = 95, Z = 155, Type = "TIMING" },
	{ Name = "Task_RiceDrier", X = 45, Z = 158, Type = "TWO_PERSON" },
	{ Name = "Task_AlleyGenset", X = 95, Z = -100, Type = "TIMING" },
	{ Name = "Task_RingCistern", X = -RING, Z = 90, Type = "HOLD" },
}

for _, point in TASK_POINTS do
	local attributes: { [string]: any } = { TaskType = point.Type }

	if point.Source then
		attributes.FetchSourceName = point.Source
	end

	anchor(point.Name, "TaskPoint", point.X, point.Z, anchors, attributes)
end

-- Four fetch sources. Two are named by a task point above; two are spare, so a future FETCH point has
-- somewhere to draw from and `setUpFetchTasks`'s `used` set never starves into a HOLD demotion.
local FETCH_SOURCES = {
	{ Name = "FetchSource_Rice", X = 130, Z = 150 },
	{ Name = "FetchSource_Chapel", X = -14, Z = -146 },
	{ Name = "FetchSource_Well", X = -76, Z = 44 },
	{ Name = "FetchSource_Plaza", X = 22, Z = 30 },
}

for _, source in FETCH_SOURCES do
	local p = anchor(source.Name, "FetchSource", source.X, source.Z, anchors)

	p.Color = Color3.fromRGB(120, 96, 64)
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
	warn(
		`[barrio] could not set Lighting.Technology to Future ({err}) — set it by hand in Studio.`
	)
end

Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(14, 16, 26)
Lighting.OutdoorAmbient = Color3.fromRGB(26, 30, 46)
Lighting.EnvironmentDiffuseScale = 0.2
Lighting.EnvironmentSpecularScale = 0.2
Lighting.GlobalShadows = true
-- Scaled with the map, because fog is a fraction of the map rather than a distance. §5 wants partial
-- information — "you should almost always be able to see *something*" — and a fog wall that stayed put
-- while the barrio grew would make a bigger map no darker, only emptier.
Lighting.FogEnd = 220 * SCALE
Lighting.FogColor = Color3.fromRGB(18, 20, 30)

local atmosphere = Lighting:FindFirstChildWhichIsA("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.42
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(150, 156, 172)
atmosphere.Decay = Color3.fromRGB(60, 66, 88)
atmosphere.Glare = 0.1
atmosphere.Haze = 2.2
atmosphere.Parent = Lighting

-- §5: "Enable StreamingEnabled" — and the build plan adds "from the start, retrofitting it later is
-- miserable". It is set here rather than by hand so a fresh place file gets it by running this file.
workspace.StreamingEnabled = true

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

print(
	`[barrio] built — {count("TaskPoint")} TaskPoint, {count("FetchSource")} FetchSource, `
		.. `{count("SaltSpawn")} SaltSpawn, {count("EscapeGate")} EscapeGate, `
		.. `{#root:GetDescendants()} instances, scale {SCALE}`
)
