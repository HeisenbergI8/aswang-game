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
	  TrialSpawn   × 1  TrialService.trialSpawn       where a trial player is placed
	  TrialChase   × 1  TrialService (C22 rig)        where the scripted rig appears
	  MapLight     ×14  PerformanceController         SCENERY lights only — never a gameplay tell
	                    12 street lanterns + the trial corner's + the chapel candle glow
	  TaskPoint    × 2  TrialService.trialPoints      attribute `TrialOnly = true` — see the corner

	`TrialOnly` IS AN EXCLUSION AND IT IS THE ONE CONTRACT HERE THAT FAILS SILENTLY. The trial's two
	points carry the ordinary `TaskPoint` tag, so `TaskService.discoverPool` sees them and skips them
	only because of that attribute. Omit it and a real round draws an objective into a walled corner
	nobody can reach — a task nobody can find, every few rounds, with nothing logged.

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

	-- Packed dirt. A barrio street is not paved, and `Ground` is the one material that reads as a
	-- road at ClockTime 0 without needing a texture nobody can generate here.
	p.Material = Enum.Material.Ground
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
	wallMaterial: Enum.Material?
): Folder
	local folder = Instance.new("Folder")

	folder.Name = name
	folder.Parent = root

	local t = 2 -- wall thickness
	local door = 10
	local hw, hd = w / 2, d / 2

	local floor = box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
	local roof = box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)

	-- Nipa thatch has no Roblox material. `Grass` at the THATCH colour is the closest read: it is the
	-- only stock material with a fibrous, directionless grain, and a roof is seen from below and at
	-- distance where the grain is all that survives.
	floor.Material = Enum.Material.WoodPlanks
	roof.Material = Enum.Material.Grass

	local material = wallMaterial or Enum.Material.WoodPlanks

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
ground.Material = Enum.Material.LeafyGrass

local walls = Instance.new("Folder")
walls.Name = "Perimeter"
walls.Parent = root

box("Wall_N", 0, WALL_H / 2, -HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_S", 0, WALL_H / 2, HALF, HALF * 2 + 8, WALL_H, 4, STONE, walls)
box("Wall_E", HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)
box("Wall_W", -HALF, WALL_H / 2, 0, 4, WALL_H, HALF * 2 + 8, STONE, walls)

for _, wall in walls:GetChildren() do
	(wall :: Part).Material = Enum.Material.Cobblestone
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
plazaSlab.Material = Enum.Material.Concrete

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

box("Arko_PillarW", -11, 8, -32, 4, 16, 4, STONE, arko).Material = Enum.Material.Cobblestone
box("Arko_PillarE", 11, 8, -32, 4, 16, 4, STONE, arko).Material = Enum.Material.Cobblestone
box("Arko_Lintel", 0, 17, -32, 26, 3, 4, STONE, arko).Material = Enum.Material.Cobblestone

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
building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE, Enum.Material.Cobblestone)
box("Chapel_Steeple", 0, 24, -164, 10, 16, 10, STONE).Material = Enum.Material.Cobblestone

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

box("Well_Pump", -58, 2.5, 40, 2, 5, 2, STONE, wellFolder).Material = Enum.Material.CorrodedMetal
box("Well_LowWall", -70, 1, 48, 26, 2, 2, STONE, wellFolder).Material = Enum.Material.Cobblestone

for _, stone in wellFolder:GetChildren() do
	if (stone :: Part).Name:match("^Well_Ring") then
		(stone :: Part).Material = Enum.Material.Cobblestone
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

prop(
	"Court_Slab",
	COURT_X,
	0.12,
	COURT_Z,
	30 * SCALE,
	0.14,
	18 * SCALE,
	Color3.fromRGB(92, 84, 76),
	Enum.Material.Concrete,
	plaza
)

-- Faded paint. Three lines is enough to read as a court from across the plaza, which is the only
-- distance anyone will read it from. The LENGTHS scale with the slab; the 0.5-stud line width does
-- not, because a painted line does not get wider when the map does.
prop(
	"Court_LineN",
	COURT_X,
	0.2,
	COURT_Z - 9,
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
	COURT_Z + 9,
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
	18 * SCALE,
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
	prop(
		`Hoop{index}_Rim`,
		x - side * 3,
		9.2,
		COURT_Z,
		2.6,
		0.3,
		2.6,
		Color3.fromRGB(196, 96, 48),
		Enum.Material.CorrodedMetal,
		plaza
	)
end

--[[
	FIESTA BULBS STRUNG BETWEEN THE FOUR PLAZA LANTERNS.

	Neon spheres on a drooping wire, and NOT PointLights — see rule 2 at the top. Twelve small emissive
	dots read as a strung plaza from anywhere in it, cost no light slot, and give the safest place on
	the map a warmth the streets deliberately do not have. §5 wants the plaza to feel different from
	the alleys; this is that difference, drawn rather than lit.
]]
local CORNERS = { { -40, -40 }, { 40, -40 }, { 40, 40 }, { -40, 40 } }

for index, corner in CORNERS do
	local nextCorner = CORNERS[if index == #CORNERS then 1 else index + 1]

	droop(
		`Fiesta{index}`,
		corner[1],
		corner[2],
		nextCorner[1],
		nextCorner[2],
		9.6,
		2.4,
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
		end
	)
end

-- A flagpole, and benches along the plaza edge. The pole is the civic marker every barrio plaza has;
-- the benches are where a player waiting out an intermission will stand, which is worth dressing.
prop("Flagpole", 0, 11, -8, 0.8, 22, 0.8, Color3.fromRGB(198, 196, 188), Enum.Material.Metal, plaza)
prop("Flag", 2.6, 19, -8, 5, 3, 0.2, Color3.fromRGB(150, 60, 56), Enum.Material.Fabric, plaza)

for index, at in { { -30, 30 }, { 30, 24 }, { 26, -34 }, { -18, -30 } } do
	prop(`Bench{index}_Seat`, at[1], 2.2, at[2], 7, 0.5, 2, WOOD, Enum.Material.WoodPlanks, plaza)
	prop(
		`Bench{index}_LegL`,
		at[1] - 3,
		1.1,
		at[2],
		0.6,
		2.2,
		1.8,
		STONE,
		Enum.Material.Concrete,
		plaza
	)
	prop(
		`Bench{index}_LegR`,
		at[1] + 3,
		1.1,
		at[2],
		0.6,
		2.2,
		1.8,
		STONE,
		Enum.Material.Concrete,
		plaza
	)
end

--------------------------------------------------------------------------------
-- MARKET STALLS — the talipapa. Four, on the plaza's edges.
--------------------------------------------------------------------------------

local STALLS = {
	{ Name = "Stall_NW", X = -38, Z = 28, Yaw = 12 },
	{ Name = "Stall_NE", X = 34, Z = 38, Yaw = -8 },
	{ Name = "Stall_SE", X = 38, Z = -28, Yaw = 24 },
	{ Name = "Stall_SW", X = -36, Z = -24, Yaw = -18 },
}

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
		prop(`{stall.Name}_Roof`, x, 6.4, z, 11, 0.4, 8, TIN, Enum.Material.CorrodedMetal, folder),
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
	prop(`{stall.Name}_Tarp`, x, 4.4, z + 3.4, 10, 3.6, 0.2, TARP, Enum.Material.Fabric, folder)

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
	parent: Instance
)
	local pane = prop(
		name,
		cx,
		cy,
		cz,
		if wide then 4.5 else 4,
		3,
		if wide then 4 else 4.5,
		WARM,
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

for _, kubo in KUBO_WINDOWS do
	-- ±7.5 RATHER THAN ±6, AND THE REASON IS `building`'s DOOR GAP. A doored side is two segments
	-- with a 10-stud hole between them, so the wall only exists beyond ±5. A 4.5-wide pane centred
	-- at ±6 spanned ±3.75..±8.25 and hung half of itself in the doorway.
	window(`{kubo.Name}_WindowN`, kubo.X - 7.5, kubo.Z - 10, kubo.Height, true, houses)
	window(`{kubo.Name}_WindowS`, kubo.X + 7.5, kubo.Z + 10, kubo.Height, true, houses)
	window(`{kubo.Name}_WindowE`, kubo.X + 12, kubo.Z - 6, kubo.Height, false, houses)
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
	for pole = 1, rng:NextInteger(5, 8) do
		local height = rng:NextNumber(16, 26)
		local stalk = prop(
			`Bamboo{index}_{pole}`,
			at[1] + rng:NextNumber(-3.5, 3.5),
			height / 2,
			at[2] + rng:NextNumber(-3.5, 3.5),
			0.7,
			height,
			0.7,
			BAMBOO,
			Enum.Material.Wood,
			planting
		)

		-- Bamboo is never vertical, and the lean is what stops sixteen clumps reading as sixteen
		-- copies of one clump.
		lean(turn(stalk, rng:NextInteger(0, 90)), rng:NextNumber(-7, 7), rng:NextNumber(0, 1) > 0.5)

		-- A crown of leaves, only on the taller poles. Foliage is what the eye uses to tell a plant
		-- from a post at distance.
		if height > 20 then
			for leaf = 1, 3 do
				lean(
					turn(
						prop(
							`Bamboo{index}_{pole}_Leaf{leaf}`,
							stalk.Position.X / SCALE,
							height - 1.5,
							stalk.Position.Z / SCALE,
							5,
							0.2,
							2.5,
							LEAF,
							Enum.Material.Grass,
							planting
						),
						leaf * 60 + rng:NextInteger(-20, 20)
					),
					rng:NextNumber(-30, -10)
				)
			end
		end
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
	prop(
		`Banana{index}_Trunk`,
		at[1],
		3.5,
		at[2],
		1.6,
		7,
		1.6,
		Color3.fromRGB(86, 96, 62),
		Enum.Material.Wood,
		planting
	)

	for blade = 1, 4 do
		lean(
			turn(
				prop(
					`Banana{index}_Leaf{blade}`,
					at[1],
					7.6,
					at[2],
					9,
					0.25,
					3.4,
					LEAF,
					Enum.Material.Grass,
					planting
				),
				blade * 90 + rng:NextInteger(-25, 25)
			),
			rng:NextNumber(-38, -18)
		)
	end
end

-- Bamboo fencing along the yards, as pickets. Runs are given as two layout points; the pickets are
-- spaced along them so a longer run simply gets more.
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

for index, at in { { 75, 150 }, { 140, 164 } } do
	local base = `Scarecrow{index}`

	prop(`{base}_Post`, at[1], 5, at[2], 0.6, 10, 0.6, WOOD, Enum.Material.Wood, field)
	prop(`{base}_Arms`, at[1], 8, at[2], 7, 0.5, 0.5, WOOD, Enum.Material.Wood, field)
	turn(
		prop(`{base}_Body`, at[1], 7, at[2], 3, 4, 1.6, CLOTH[index], Enum.Material.Fabric, field),
		20 * index
	)

	local head = prop(
		`{base}_Head`,
		at[1],
		9.6,
		at[2],
		1.8,
		1.8,
		1.8,
		Color3.fromRGB(148, 132, 96),
		Enum.Material.Fabric,
		field
	)

	head.Shape = Enum.PartType.Ball

	-- The hat is what makes it read as a figure rather than as a post with a bag on it, at the
	-- distance the rice field is actually seen from.
	prop(
		`{base}_Hat`,
		at[1],
		10.6,
		at[2],
		4.5,
		0.4,
		4.5,
		Color3.fromRGB(158, 138, 92),
		Enum.Material.Grass,
		field
	)
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

local details = Instance.new("Folder")
details.Name = "Details"
details.Parent = dress

-- Beside the chapel, west of it and clear of the north road and FetchSource_Chapel.
for index = 1, 8 do
	local x = -50 + (index % 3) * 7
	local z = -164 + math.floor((index - 1) / 3) * 10
	local height = rng:NextNumber(2.4, 3.6)

	lean(
		prop(
			`Grave{index}_V`,
			x,
			height / 2,
			z,
			0.5,
			height,
			0.5,
			Color3.fromRGB(126, 124, 116),
			Enum.Material.Concrete,
			details
		),
		rng:NextNumber(-8, 8),
		true
	)
	prop(
		`Grave{index}_H`,
		x,
		height * 0.78,
		z,
		2,
		0.5,
		0.4,
		Color3.fromRGB(126, 124, 116),
		Enum.Material.Concrete,
		details
	)
end

-- Two tricycles, parked. The sidecar is what makes the shape unmistakable, and it is three boxes.
for index, at in { { -22, -40 }, { 95, -90 } } do
	local base = `Tricycle{index}`
	local folder = Instance.new("Folder")

	folder.Name = base
	folder.Parent = details

	prop(
		`{base}_Body`,
		at[1],
		2,
		at[2],
		4.5,
		2.2,
		1.6,
		Color3.fromRGB(140, 92, 72),
		Enum.Material.Metal,
		folder
	)
	prop(
		`{base}_Sidecar`,
		at[1],
		2.2,
		at[2] + 2,
		4,
		2.6,
		2.4,
		Color3.fromRGB(92, 108, 122),
		Enum.Material.CorrodedMetal,
		folder
	)
	prop(
		`{base}_Roof`,
		at[1],
		4.2,
		at[2] + 2,
		4.4,
		0.3,
		2.8,
		TIN,
		Enum.Material.CorrodedMetal,
		folder
	)
	prop(`{base}_Bars`, at[1] - 2.2, 3.2, at[2], 0.4, 2.4, 1.8, TIN, Enum.Material.Metal, folder)

	-- Axis-aligned on purpose: turning the folder means turning every child about a shared centre,
	-- and a tricycle is not worth a transform helper nothing else in the file would use.
	for wheel, offset in { { -1.6, 0 }, { 1.6, 0 }, { 1.4, 2 } } do
		local w = prop(
			`{base}_Wheel{wheel}`,
			at[1] + offset[1],
			0.9,
			at[2] + offset[2],
			1.8,
			1.8,
			0.5,
			Color3.fromRGB(32, 32, 34),
			Enum.Material.Rubber,
			folder
		)

		w.Shape = Enum.PartType.Cylinder
		w.CFrame = CFrame.new(w.Position) * CFrame.Angles(0, math.rad(90), 0)
		w.Size = Vector3.new(0.5, 1.8, 1.8)
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
	local puddle = prop(
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

	The trial's two practice points carry the SAME `TaskPoint` tag as the twelve above, because they
	are task points and the trial's job is to teach the real interaction. That means
	`TaskService.discoverPool` finds them, and a round could DRAW one — putting a live objective in a
	corner of the map no player can walk to, and counting it toward the escape gate. `discoverPool`
	therefore skips any part attributed `TrialOnly`, and this is what puts the attribute there.

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
	warn(
		`[barrio] could not set Lighting.Technology to Future ({err}) — set it by hand in Studio.`
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
	`[barrio] built — {count("TaskPoint") - countTrialOnly()} TaskPoint (+{countTrialOnly()} TrialOnly), `
		.. `{count("FetchSource")} FetchSource, {count("SaltSpawn")} SaltSpawn, `
		.. `{count("EscapeGate")} EscapeGate, {count("TrialSpawn")} TrialSpawn, `
		.. `{count("TrialChase")} TrialChase, {#root:GetDescendants()} instances, scale {SCALE}`
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
