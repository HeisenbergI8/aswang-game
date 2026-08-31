--!strict
--[[
	REVIEW — src/shared/Config.luau (1648 lines at time of reading)

	V09 adds five tunables to the Items block and one budget to the AntiCheat block. The garlic keys
	the spec commits to are already here; what is missing is the invariant that guards one of them.
]]

-- src/shared/Config.luau:55-73
-- THE GARLIC BLOCK, ALREADY WRITTEN AND ALREADY CORRECT.
--
-- IMPORTANT: "Invariant 4: GarlicDuration < Round.Duration / 4 (15 < 75)" is written HERE and in the
-- spec (line 758) and pinned in `tests/config.test.luau` NOWHERE. Step 1.2 adds it. Until it lands,
-- this comment is the only guard — the same situation `SaltDamage` was in before V11 was scheduled,
-- and the file says so about itself two blocks above.
--
-- NOTE: "WHY TWO… No §6.5 invariant pins this, so it is a judgement to re-open at V16 rather than a
-- relationship that will break silently." V09 must NOT invent an invariant for `GarlicSpawnCount`.
-- The spec deliberately leaves it a judgement, and pinning a judgement makes it look derived.
--
-- IMPORTANT: "its effect is SILENT AND INVISIBLE: no knockback, no VFX, nothing that tells the
-- survivors it worked." Note the phrasing — nothing tells the SURVIVORS either. The barrier produces
-- no confirmation for the person who placed it. Placing garlic and then watching who declines IS the
-- feedback, and the design has no other.
GarlicSpawnCount = 2,
GarlicDuration = 15,

-- src/shared/Config.luau:94-105
-- The carry limit, and why it makes `RequestPlaceGarlic` argument-free.
--
-- IMPORTANT: `CarryLimit = 1` is what lets the placement remote take no item argument — there is
-- exactly one thing a player can be holding and the server knows what it is. If it ever rises,
-- `RequestPlaceGarlic` needs an argument and every "the server already knows" argument in this chunk
-- has to be re-made. The comment already names that as "a contract change to argue in a plan".
CarryLimit = 1,

-- src/shared/Config.luau:126-141
-- `DropForwardStuds` / `DropPickupRangeStuds`, and the bug they shipped with.
--
-- IMPORTANT: read this as a warning about V09's own numbers. The invariant was GREEN over a rule the
-- code did not apply — the config value had a declaration, a Remotes comment and a test pinning it,
-- and no reader anywhere in `src/`. "Found by an exploit audit, not by a gate."
--
-- NOTE: the same failure is available to `GarlicBarrierPadStuds`. It is read in exactly one place
-- (`placeGarlic`'s `HalfWidth`) and if that line ever loses it, the barrier narrows to the doorway's
-- exact width, the Aswang slips past its edge, and every check stays green. The playtester's E/W
-- doorway screenshot is what catches it.
DropPickupRangeStuds = 6,
DropForwardStuds = 6,

-- src/shared/Config.luau:157-163
-- The item colours, and why V09 adds none.
--
-- NOTE: `BawangRgb` already exists and the placed bulb reuses it. A `PlacedGarlicRgb` would let a
-- future tune make placed garlic look different from carried garlic, which is a distinction the game
-- has no reason to draw — and RGB TRIPLES, NEVER Color3, is the file's standing rule.
BawangRgb = { 236, 222, 180 },

-- src/shared/Config.luau:1507-1531
-- The AntiCheat budgets block, and the shape `RequestPlaceGarlic` joins.
--
-- IMPORTANT: `tests/anti-cheat-budgets.test.luau` asserts in BOTH directions — every up-remote has a
-- budget, and every budget names a real up-remote — against a HAND-COPIED list of remote names in the
-- suite. So the budget and the suite's list entry must land in the same step or the step is red. That
-- coupling is what makes Step 2.2's verify a real check rather than a formality.
--
-- NOTE: `RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 }` is the closest sibling — an
-- argument-free request that makes the server sweep a tagged pool. `RequestPlaceGarlic` is rarer
-- (two per round, ever) so its capacity and refill are both smaller.
Budgets = {
	RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
	RequestDropItem = { Capacity = 6, RefillPerSecond = 0.5 },
	RequestCamouflage = { Capacity = 3, RefillPerSecond = 0.2 },
}
