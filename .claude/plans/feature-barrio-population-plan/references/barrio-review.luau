--!strict
--[[
	REVIEW — tools/greybox/barrio.luau (3,112 lines)

	Excerpts only, from the four regions this plan edits: the spawn points, the kubo table, the mesh
	registry and the build-failing asserts.

	SUMMARY. This file is in far better shape than its size suggests — nine Lune suites were put behind
	it by the realism plan, and three of its receipts fail the BUILD rather than printing a number
	nobody reads. The plan follows that pattern rather than inventing one.
]]

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tools/greybox/barrio.luau:277-279 and :653-688 — v() and anchor()
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x * SCALE, y, z * SCALE)
end

local function anchor(name, tag, cx, cz, parent, attributes): Part
	-- POSITION SCALES, SIZE DOES NOT
	local p = box(name, cx, 0.4, cz, 6 / SCALE, 0.8, 6 / SCALE, ANCHOR_C, parent)

	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	-- ...attributes, AddTag...
end

-- IMPORTANT: THIS IS HALF OF THE FLOATING-RIG DEFECT, and it is why the arithmetic is worth spelling
-- out. `v()` scales X and Z by SCALE and leaves Y alone. `anchor()` passes `cy = 0.4` and a height of
-- 0.8, so an `AmbientSpawn` pad spans y 0..0.8 with its CENTRE at 0.4 — regardless of SCALE.
--
-- `AmbientService.buildEntity` then assigns that CFrame straight onto the rig body
-- (`AmbientService.luau:278`), so every rig's centre is at 0.4 and every rig is buried by half its own
-- height. The pad is `CanCollide = false`, so the surface a rig should stand on is whatever is beneath
-- it — which is why Phase 2 raycasts rather than subtracting a constant.
--
-- NOTE: `attributes` already exists as a parameter and is unused by `AmbientSpawn` today. Phase 3's
-- `Form` attribute needs no signature change.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tools/greybox/barrio.luau:1308-1334 — AMBIENT_POINTS
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local AMBIENT_POINTS = {
	{ -30, 30 }, { 30, 24 }, { 26, -34 }, { -18, -30 },      -- plaza and approaches
	{ -58, -58 }, { 58, -58 }, { 58, 58 }, { -58, 58 },      -- the four stall corners
	{ -76, 44 }, { 0, -104 }, { -14, -146 }, { 120, 148 },   -- civic and outlying
	{ -100, 60 }, { 100, -60 }, { -40, 100 }, { 40, -100 },
}

for index, at in AMBIENT_POINTS do
	anchor(`AmbientSpawn_{index}`, "AmbientSpawn", at[1], at[2], anchors)
end

-- Sixteen bare coordinate pairs, form-blind. `AmbientService` walks them in order and reuses them
-- sequentially across its four `spawnForm` calls, so which form lands where is an accident of order.
--
-- IMPORTANT: `tests/barrio-ambient.test.luau:77` parses these with `"{ (%-?%d+), (%-?%d+) }"`. Adding
-- a `Form` field changes that pattern, which is why Step 3.4 rewrites the suite in the same phase.
-- The 8-stud minimum separation and the per-quadrant minimum both survive unchanged.
--
-- NOTE: the coordinates this plan replaces them with are chosen against real map features — the three
-- alleys in `ALLEYS` (:771-775), the ring and radial roads, the seven kubo, the well at (-70, 32) and
-- the rice edge — because a territory has to be somewhere the thing that justifies it can stand.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tools/greybox/barrio.luau:960-982 — the KUBO table, and :1004-1011 — the shell
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

local KUBO: { KuboSpec } = {
	{ Name = "Kubo_NW", X = -78, Z = -78, Doors = { S = true }, Enterable = true },
	-- ...NE, SE, SW, N, all Enterable with ONE inward door...
	{ Name = "Kubo_E", X = 158, Z = -30, Doors = {}, Enterable = false },
	{ Name = "Kubo_W", X = -158, Z = 40, Doors = {}, Enterable = false },
}

--	A GENERATED SHELL OVER THE TWO SEALED KUBO, AND ONLY THOSE TWO. ... It cannot go on an enterable
--	house: it is a solid exterior with no authored interior, so dropping it over `Kubo_NW` would
--	occlude the doorway and bury the search container inside it.

-- NOTE: the shell comment's premise is that the mesh must be SOLID. It need not be. `building()` at
-- :388-391 already builds a doored side as two wall segments with a gap, and those boxes can stay,
-- become invisible, and keep doing the collision while a `CanCollide = false` mesh does the looking.
-- That is the dressing pass's own rule (C30 RULE 1, asserted at the foot of this file) applied one
-- layer up, and it is why the plan's answer to "retire or split the shell" is neither.
--
-- IMPORTANT: it also unlocks the CHAPEL mesh, recorded at `Placed = 0` for the same wrong reason —
-- 6,000 triangles already generated and drawing nothing.
--
-- NOTE: the claim that the two sealed kubo "exist to BREAK SIGHTLINES" (:944-947) does not survive
-- reading `building()`. Occlusion comes from the 24 x 20 x 9 MASS, and a single 10-stud gap in one
-- face removes none of it — you still cannot see through, because no two doors are opposite. So the
-- compensation the brief asked for is not needed, PROVIDED each new door is a single inward one.
-- Step 7.2 records that argument with its cites, and the interiors suite pins "no opposed doors".

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- tools/greybox/barrio.luau — the build-failing asserts at the foot of the file
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

assert(count("AmbientSpawn") == 16, "...AmbientService will fall back to a ring at the origin")
assert(dressColliders == 0, "...the navmesh, and therefore the crossing time, has moved")
assert(dressLights == 0, "...Config.Performance.MaxVisibleLights is being overspent")
assert(mapLights == totalLights, "...PerformanceController cannot cull what it cannot see")

-- Four asserts that fail the BUILD, because "a receipt you have to read is a receipt nobody reads".
--
-- IMPORTANT: the instance count is PRINTED and not asserted, and it is the budget line this plan
-- spends hardest. Phase 8 adds the fourth assert as a BAND rather than a maximum — the realism plan's
-- Phase 7 deleted the fence runs, the banana table and the scarecrow loop by miscounting `end` lines,
-- and the instance count went DOWN, which is exactly what that phase was trying to do. Every gate was
-- green. A ceiling alone would have certified that deletion.
--
-- NOTE: the literals here are hand-copied from `Config.luau` because this file runs in Studio's
-- command bar where `require` is not reliably available, and `tests/barrio-receipt.test.luau`
-- reconciles them against Config as TEXT. That is what makes the hand-copy safe, and 16 -> 18 has to
-- move in both places.
