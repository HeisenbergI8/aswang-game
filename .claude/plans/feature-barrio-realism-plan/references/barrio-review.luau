--!strict
--[[
	REVIEW — tools/greybox/barrio.luau (2,216 lines)

	The file that builds the entire barrio, and the only file this plan's visual work lands in.
	Excerpts only; open the real file for everything else.
]]

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:26-39  — THE STALE CONTRACT BLOCK
--------------------------------------------------------------------------------

--	  TaskPoint    ×12  TaskService.discoverPool      unique Names; Config.Tasks.PoolSize
--	  FetchSource  × 4  TaskService.discoverSources   one per FETCH task drawn in a round
--	  SaltSpawn    × 6  ItemService.discoverPool      Config.Salt.PouchPoolSize
--	  EscapeGate   × 1  GateService.discoverGates     proximity win, Config.Tasks.GateRangeStuds = 6

-- The header's own summary of what the services demand of the map.
-- IMPORTANT: `TaskService` and `GateService` DO NOT EXIST. V01 deleted them. This block is the single
-- most misleading text in the repo — it reads authoritative and describes a game that was demolished.
-- The brief was right not to trust it; I established the real contract by reading the services instead.
-- IMPORTANT: it also OMITS `SearchContainer` and `AmbientSpawn`, which is how their absence stayed
-- invisible. A contract that lists only what exists cannot show you what is missing.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:563-567  — THE RESURRECTED ESCAPE GATE
--------------------------------------------------------------------------------

local gate = box("EscapeGate", 0, 3, -32, 18, 6, 1.5, Color3.fromRGB(148, 128, 92), arko)

gate.Material = Enum.Material.WoodPlanks
CollectionService:AddTag(gate, "EscapeGate")

-- Builds the v1.3 escape gate under the arko and tags it.
-- IMPORTANT: nothing reads this tag any more. Running the builder today RESURRECTS deleted v1.3
-- geometry into the place file — and because the place file is gitignored, `git status` would never
-- show it. This is the clearest example of why the builder needed a gate of its own. Deleted at Step 2.2.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:325-352  — THE ANCHOR HELPER
--------------------------------------------------------------------------------

local function anchor(name, tag, cx, cz, parent, attributes)
	-- POSITION SCALES, SIZE DOES NOT — the `/ SCALE` cancels the one `box` applies.
	local p = box(name, cx, 0.4, cz, 6 / SCALE, 0.8, 6 / SCALE, ANCHOR_C, parent)

	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	-- ... attributes ...
	CollectionService:AddTag(p, tag)

	return p
end

-- Every tagged gameplay point in the map is one of these: a flat 6-stud non-collidable pad.
-- NOTE: the 6 studs is not decoration — C17's comment argues it is "a reading of a Config range", so
-- the pad is the honest affordance for how close you must stand. That argument carries over unchanged
-- to `SearchContainer` and `Config.Search.ProximityStuds`, which is why Step 6.3 keeps the pad visible
-- under the container prop rather than hiding it.
-- IMPORTANT: the pad is BLUE and FLAT. §5 requires containers be "visually obvious as searchable at a
-- glance, on a phone, in the dark". Step 2.3 creates fifteen of these; Step 6.3 is the debt that pays
-- for them. Do not consider searching "done" at the end of Phase 2.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:171-200  — building(), and why edits belong HERE
--------------------------------------------------------------------------------

local floor = box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
local roof = box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)

floor.Material = Enum.Material.WoodPlanks
roof.Material = Enum.Material.Grass

-- Builds every kubo AND the chapel. Eight buildings through one function.
-- NOTE: `w + 4` / `d + 4` makes the roof overhang the walls — which research-01 confirms is correct
-- ("long eaves give people limited space to move around the outside of the house when it rains").
-- That was right by accident and should be kept, possibly widened.
-- IMPORTANT: the roof is a FLAT 1-STUD SLAB. It is not a pitch at all. Research-01's inferred 45-50°
-- is uncertain, but anything in that range is a large improvement, so the uncertainty costs nothing.
-- NOTE: one edit here re-materials sixteen floor and roof parts across eight buildings. Prefer
-- helper-level edits over per-part ones throughout this plan — fewer lines, and it cannot miss one.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:867-890  — prop(), the non-collidable guarantee
--------------------------------------------------------------------------------

local p = box(name, cx, cy, cz, sx / SCALE, sy, sz / SCALE, colour, parent or dress)

p.Material = material
p.CanCollide = false
p.CanQuery = false
p.CanTouch = false
p.CastShadow = false

-- Every piece of dressing in the map goes through this.
-- IMPORTANT: `CanCollide = false` here is what makes "the layout did not move" true BY CONSTRUCTION
-- rather than by re-measuring and hoping. PathfindingService builds its navmesh from collision
-- geometry. Every new prop in this plan — cracks, bench backs, grilles, banderitas triangles, meshes —
-- MUST go through `prop()` or `mesh()`. A hand-rolled `Instance.new("Part")` that forgets one of these
-- four lines is the single most likely way this plan breaks the crossing time.
-- NOTE: `CastShadow = false` also matters on mobile and is easy to forget when hand-rolling.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:2057-2076  — THE AUTHORED NIGHT
--------------------------------------------------------------------------------

Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(14, 16, 26)
Lighting.OutdoorAmbient = Color3.fromRGB(26, 30, 46)
Lighting.FogEnd = 220 * SCALE

local atmosphere = Lighting:FindFirstChildWhichIsA("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.42

-- IMPORTANT: five of these are CAPTURED BY SkyController AT STARTUP as the baseline it lerps toward
-- dawn and back — Brightness, FogEnd, Ambient, OutdoorAmbient, Atmosphere.Density. Retuning them here
-- is CORRECT and supported; C28's own comment says C30's art pass "retunes it here without touching
-- Config or any controller". This is not the trap people expect.
-- IMPORTANT: `ClockTime` is the exception. The round owns it via `Config.Sky.StartClockTime = 3.0`.
-- The 0 is what a map author sees in Studio, never what a player sees. Do not treat it as an art value.
-- NOTE: everything SkyController does NOT capture is free for the builder to own outright —
-- EnvironmentDiffuseScale, GlobalShadows, FogColor, and the Atmosphere's Color/Decay/Glare/Haze.
-- Phase 8 spends most of its budget there because those have no runtime owner to fight.

--------------------------------------------------------------------------------
-- src: tools/greybox/barrio.luau:2196-2216  — THE THREE ASSERTIONS THIS PLAN INHERITS
--------------------------------------------------------------------------------

assert(dressColliders == 0, "...the navmesh, and therefore the crossing time, has moved")
assert(dressLights == 0, "...Config.Performance.MaxVisibleLights is being overspent")
assert(mapLights == totalLights, "...PerformanceController cannot cull what it cannot see")

-- C30's second receipt. These FAIL THE BUILD rather than warning.
-- IMPORTANT: a realism pass is exactly the pressure that breaks all three. A "solid" concrete bench
-- wants CanCollide. A covered court wants a light under it. Eight grave candles want to be PointLights.
-- Every one is refused, and the plan says so at each site. They are not obstacles to work around —
-- they are the reason this art pass can be trusted not to have moved the game.
-- NOTE: the third one is a SECRECY guard wearing a performance costume. `MapLight` is the client's
-- permission to switch a light OFF; the Aswang's eye glow is protected by never carrying the tag.
-- An untagged light in the barrio means the culler cannot see it — hence the assert.
