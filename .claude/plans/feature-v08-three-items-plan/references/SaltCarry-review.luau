--!strict
--[[
	REVIEW — src/shared/pure/SaltCarry.luau (107 lines), migrating to pure/ItemCarry at V08 Phase 1.

	The smaller of the two migrations. ~30 assertions behind it in tests/salt-carry.test.luau (190
	lines). Cited against the file as read on 2026-08-29.
]]

-- src/shared/pure/SaltCarry.luau:8-14
--[[
	The scarcity half is enforced by `Config.Salt.SpawnCount`; THIS module enforces the carry half,
	and it is a separate rule because the two fail differently. A map with too few pouches is a
	balance problem you notice. A carry limit that does not hold is an exploit: walk the six spawn
	points, hold six pouches, and the one counterplay item in the game stops being a decision and
	becomes an arsenal.
]]
-- NOTE: the scarcity half moves to V03's containers + Config.Items.*SpawnCount at V08. The carry half
-- is this module and is unchanged in intent.
-- IMPORTANT: the exploit sentence gets WORSE at V08, not better. Seven items across fifteen
-- containers, one of them the win condition — "walk every container and hold everything" would hand
-- one player the survivors' entire arsenal including the only thing that kills.

-- src/shared/pure/SaltCarry.luau:16-19
--[[
	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET ... this module never takes a role at
	all, and it must not start. A carry limit that differed for the Aswang would be a role oracle
	readable by standing on a pouch.
]]
-- IMPORTANT: THE SINGLE MOST IMPORTANT SENTENCE TO CARRY ACROSS, and V08 makes it concrete. §4.4 has
-- the Aswang searching on identical rules, so the monster REACHES this module, GETS "OK", and FILLS A
-- SLOT. That is correct and must stay correct — Types.ClientRoundSnapshot.YourCarriedItem is only
-- safe because an empty-handed survivor and the Aswang send the same absent field, and they only do
-- if the monster can genuinely hold things.

-- src/shared/pure/SaltCarry.luau:21-27
--[[
	IT LIVES IN `src/shared/pure/` AND NOT `src/server/pure/` ... are the inputs client-suppliable,
	and is there a seed? There is no seed, and every input is already on the client — the phase and
	`YourState` ride the snapshot, and `CarryLimit` is in the replicated Config.
]]
-- NOTE: still true at V08. `Held` is the requesting client's OWN slot, which after Phase 5 rides the
-- snapshot as `YourCarriedItem`. `Incoming` is what the container just yielded to that same player.
-- Neither is another player's fact, so shared/pure/ remains correct.

-- src/shared/pure/SaltCarry.luau:38-51 — Request and Verdict
export type Verdict = "OK" | "WRONG_PHASE" | "NOT_ALIVE" | "AT_LIMIT" | "NO_LIMIT_SET"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Carried: number,
	Limit: number,
}
-- NOTE: all four verdicts gain an `ITEM_` prefix at V08 (Types.luau:520-524's rule), and `AT_LIMIT`
-- becomes `ITEM_SLOT_FULL` — the rename says which of the two mechanics refused, which matters now
-- that a refusal has a §4.4 consequence (the item goes back to the world rather than to the player).
-- NOTE: `Carried: number` → `Held: ItemType?` plus a new `Incoming: ItemType`.

-- src/shared/pure/SaltCarry.luau:53-64 — the ordering contract
--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT ... A log full of AT_LIMIT is a UX finding — players
	walking over pouches they cannot take — and a log full of anything above it is a correctness
	finding.

	NOT_ALIVE is an ALLOWLIST of ALIVE, never `~= "SPECTATOR"`. A DEAD player must not pick up salt ...
	DEAD is a state that a body walks around in, so the denylist form starts admitting them the moment
	Phase 6 lands.
]]
-- IMPORTANT: keep both, verbatim. The allowlist warning is pure/PlayerBody's, and V01's husk work
-- landed exactly the thing it predicted — a DEAD player with a body and a position.

-- src/shared/pure/SaltCarry.luau:66-76 — the limit guard
if not (request.Limit > 0 and request.Limit < math.huge) then
	return "NO_LIMIT_SET"
end
-- IMPORTANT: KEEP THIS EVEN THOUGH THE SLOT IS NOW A PRESENCE RATHER THAN A COUNT. A `CarryLimit`
-- typo of 0 would be caught by the occupancy comparison; -1, 0/0 and math.huge would not, and
-- math.huge silently deletes the limit entirely. Its comment records that KillValidation's cooldown
-- took three attempts to get this right.

-- src/shared/pure/SaltCarry.luau:78-99 — the two comparisons
if request.Carried >= request.Limit then
	return "AT_LIMIT"
end

-- The NaN-carried hole the comment above names, closed.
if not (request.Carried >= 0 and request.Carried < math.huge) then
	return "AT_LIMIT"
end
-- NOTE: `>=` NOT `>` — with CarryLimit = 1 a `>` is off by exactly one, which is the whole limit when
-- the limit is one. Carry that comment across; the occupancy form must use `>=` too.
-- NOTE: the SECOND guard (NaN carried) is DELETED at V08 rather than migrated, and the plan says why:
-- `Carried` was a running integer produced by arithmetic that could reach NaN, while occupancy is
-- `if Held ~= nil then 1 else 0` — provably 0 or 1, with no arithmetic left to poison. The replacement
-- is a test assertion that occupancy is one of those two across the grid.
-- QUESTION: is deleting a fail-closed guard ever the right call? Here yes, because the guard was
-- closing a hole in an input SHAPE that no longer exists. If the implementer cannot state that
-- sentence about it, keep the guard.
