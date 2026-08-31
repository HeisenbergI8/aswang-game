--!strict
--[[
	REVIEW — tools/greybox/barrio.luau (4928 lines at time of reading)

	The question this file answers: WHAT IS A DOORWAY IN THIS MAP, and what does tagging one cost?

	THE ANSWER IS "NOTHING IS A DOORWAY YET, AND TAGGING THEM COSTS NINE CALLS TO A HELPER THAT
	ALREADY EXISTS." The detail below is why the obvious cheaper answer does not work.
]]

-- tools/greybox/barrio.luau:23-27
-- The file's own contract, and the reason a TAG is the only thing V09 may rely on.
--
-- IMPORTANT: this file is outside `src/`, so it is behind no gate, and the map it builds is not in
-- git. A doorway that failed to appear would have no symptom except "bawang does nothing".
--[[
	This script's real contract is with four services, all of which discover the map by CollectionService
]]

-- tools/greybox/barrio.luau:91
-- THE NUMBER THAT WILL SILENTLY BREAK THE BARRIER'S WIDTH.
--
-- IMPORTANT: `box()` multiplies POSITIONS by SCALE and leaves SIZES alone, so `building()`'s
-- `local door = 6` is 6 pre-scale units = 9.3 REAL STUDS on the ground. The file's own comment at
-- :521 says "Six is nine and a half studs". A `Width = 6` attribute would build a barrier two thirds
-- the width of the doorway it is meant to deny, and the Aswang would walk around its edge with no
-- error anywhere. The attribute must be written `6 * SCALE`, and the new suite pins that spelling.
local SCALE = 1.55

-- tools/greybox/barrio.luau:487-532
-- `building()`, and the door as a GAP rather than as an object.
--
-- IMPORTANT: "a side with a door is built as two wall segments with a gap between them". There is no
-- part that IS the doorway. That is the whole finding.
--
-- IMPORTANT: `door = 6` is "the one navmesh number in this function", and the file warns twice to
-- re-run `measure.luau` after touching it. V09 must NOT touch `building()`. The doorway pads are
-- emitted at the CALL SITES, which is why nothing in this chunk goes near the navmesh.
--[[
	A building, greybox-style: floor, four walls, roof, and a door gap on each named side.
	`doors` is a set of "N"/"S"/"E"/"W".
]]
local door = 6

-- tools/greybox/barrio.luau:840-856
-- WHY `DoorSill` CANNOT BE THE DOORWAY MARKER, WHICH IS THE FIRST THING ANYONE WILL TRY.
--
-- IMPORTANT: the whole door-frame block — jambs, lintel, sill, leaf, hagdan — is behind
-- `if stilted then`. All seven kubo pass `stilted = true`; the chapel passes nothing. So `DoorSill`
-- exists for SEVEN of the nine doors and not for the chapel's two, and the chapel is the map's only
-- real room with two doors and the most likely venue for the loyalty test. There is no part shape
-- that means "doorway" across the whole map.
--
-- NOTE: the orientation table here is what V09's `Yaw` attribute copies. `nx`/`nz` is the outward
-- normal of the face, `ax`/`az` runs along it, and `yaw = if nx ~= 0 then math.rad(90) else 0`. The
-- pure module's axis convention is written to agree with this line rather than to a fresh derivation.
if stilted then
	local nx = if tag == "E" then 1 elseif tag == "W" then -1 else 0
	local nz = if tag == "S" then 1 elseif tag == "N" then -1 else 0
	local yaw = if nx ~= 0 then math.rad(90) else 0
end

-- tools/greybox/barrio.luau:817-819, 830-838
-- The doorway's history, and why nothing in V09 may narrow it.
--
-- IMPORTANT: "EVERY PART HERE IS `decor` — non-colliding, non-querying, no shadow. A collidable jamb
-- would narrow the doorway the paragraph above just finished widening enough to walk through." The
-- barrier V09 adds is collidable but exists on ONE CLIENT, so it narrows nothing for anybody else —
-- and the visible garlic bulb is `CanCollide = false` for exactly this rule.
--
-- NOTE: the opening was once fifteen studs and read as a missing wall; it was narrowed to be
-- door-shaped and a player reported the earlier version. `measure.luau` walks a real path through
-- this gap to every container.

-- tools/greybox/barrio.luau:1234-1281
-- `anchor()` — THE HELPER V09 REUSES, AND ITS COMMENT WILL BECOME PARTLY FALSE.
--
-- IMPORTANT: it already takes an attributes table and already tags. Invisible, CanCollide = false,
-- CastShadow = false, and "NOTHING READS THE PAD'S APPEARANCE. Every service takes its CFrame and its
-- attributes." That is exactly what a doorway pad needs.
--
-- NOTE: its size is fixed at 6 x 0.8 x 6 and the comment explains that as "a reading of a Config
-- range: 6 studs against `Tasks.PresenceRangeStuds` (9) and `Salt.PickupRangeStuds` (6)". For a
-- `Doorway` pad the size means nothing — only the CFrame and the two attributes are read. One
-- sentence added to this comment, not a refactor.
--
-- IMPORTANT: it is declared at :1234, so both V09 call sites must be BELOW it. The chapel is at :1545
-- and the KUBO loop at :1648, so both already are. `prop()` is declared hundreds of lines lower and
-- calling it early "compiles and dies at run time with attempt to call a nil value, which is exactly
-- what happened" (:1717) — the same trap in the other direction.
local function anchor(name, tag, cx, cz, parent, attributes): Part

-- tools/greybox/barrio.luau:1536-1545
-- The chapel: two doors, not stilted, so no frame parts at all.
--
-- NOTE: 46 wide, 36 deep, doors on S and E — so the pads go at (0, -134) and (23, -152), yaw 0 and
-- yaw 90 respectively. Two literals typed twice, which is exactly the drift
-- `tests/barrio-interiors.test.luau` exists for, so the new suite reconciles them against this call.
local chapel = building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE, Enum.Material.Cobblestone)

-- tools/greybox/barrio.luau:1620-1660
-- The KUBO table and the loop, and the invariant V09's pads must not contradict.
--
-- IMPORTANT: "ONE DOOR EACH, AND THAT IS THE LOAD-BEARING HALF… `tests/barrio-interiors.test.luau`
-- pins 'no kubo has two opposed doors'." Seven kubo, one door each, all `stilted = true`, built
-- 24 wide by 20 deep — so half-extents 12 and 10. Sealed houses have an empty `Doors` set and must
-- get no pad; a pad in a wall is a barrier nobody can walk through and garlic that denies nothing.
--
-- QUESTION: `building()`'s half-extents are read from its signature and its `hw`/`hd` locals, not
-- from running it. If they are anything other than `w / 2` and `d / 2`, every pad is offset and the
-- new suite cannot catch it — it compares the same two literals. One Studio screenshot settles it.
--
-- NOTE: the stilts are DECORATION. ":1644 — Stilts would be the real bahay kubo silhouette and they
-- were tried first, but a stilted floor needs a ramp to be walkable and a ramp is a pathfinding
-- problem this milestone has no reason to buy." So the walkable floor is at ground level and the pad
-- sits at the right height. `ItemService` should nonetheless read the pad's OWN `Position.Y` rather
-- than assume a constant, so a future pass that does raise a floor takes the barrier with it.
for index, kubo in KUBO do

-- tools/greybox/barrio.luau:4741-4795
-- THE RECEIPT, and why V09's count is asserted rather than printed.
--
-- IMPORTANT: "A receipt you have to read is a receipt nobody reads. Each of these three fails the
-- BUILD, because each one's player-visible symptom is 'the game is boring' with nothing in the log to
-- explain it." A missing doorway's symptom is "I pressed the key and nothing happened", which is
-- indistinguishable from bawang not being implemented — so `count("Doorway") == 9` is an assert.
--
-- NOTE: "THE LITERALS ARE HAND-COPIED FROM `Config.luau` AND THAT IS UNAVOIDABLE HERE… this file
-- runs in Studio's command bar, where `require` of a Rojo-synced module is not reliably available at
-- build time." The 9 is not a Config number, so `tests/barrio-doorways.test.luau` reconciles it
-- against the KUBO table and the chapel call instead.
local function count(tag: string): number
	return #CollectionService:GetTagged(tag)
end
