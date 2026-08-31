--!strict
--[[
	ItemCarry — may this player take this item right now? (§4.6, V08)

		(request) -> verdict

	MIGRATED FROM `pure/SaltCarry` (C13). The carry half of §4.6 is unchanged and its reasoning is
	kept verbatim below; what changed at V08 is that there are THREE item types and ONE slot, so the
	question stopped being "how many are you holding" and became "is your hand full".

	§4.6 IN THREE LINES: four salt pouches, two bawang and one buntot pagi are seeded into containers
	(§4.4). One carried at a time. No recharge — once used, it's gone. Scarcity makes it a decision.

	The scarcity half is enforced by `Config.Items.*SpawnCount` and by V03's container layout; THIS
	module enforces the carry half, and it is a separate rule because the two fail differently. Too
	few items in the barrio is a balance problem you notice. A carry limit that does not hold is an
	exploit: walk every container, hold everything, and the survivors' entire arsenal stops being a
	decision and becomes an inventory — including, at V08, the one thing that kills.

	WHY A VERDICT RATHER THAN A BOOLEAN — the same argument TransformRules, KillValidation and
	SearchService's verdicts make. The server logs WHY it declined, and "you are dead and standing at
	a container" and "your hand is already full" send a reader to two different places.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. This module never takes a role and it
	must not start. A carry limit that differed for the Aswang would be a role oracle readable by
	opening a container — and note that §4.4 has the Aswang searching on identical rules, so the
	Aswang DOES reach this module, DOES get OK, and DOES fill a slot. That is correct. See
	`Types.ClientRoundSnapshot.YourCarriedItem`: an empty-handed survivor and the Aswang must be
	indistinguishable, which they are only if the monster can genuinely hold things.

	IT LIVES IN `src/shared/pure/` AND NOT `src/server/pure/`, which is CLAUDE.md's test applied
	rather than assumed: are the inputs client-suppliable, and is there a seed? There is no seed, and
	every input is already on the client — the phase and `YourState` ride the snapshot, `Held` is that
	client's OWN slot, and `Limit` is in the replicated Config. A client that requires and runs this
	module learns that it may not hold two things, which it could also learn by trying.

	NO `script.Parent` REQUIRES. All three unions are re-declared; Luau unions are structural, so
	these and the ones in Types.luau are the same types and pass to each other without a cast.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

--[[
	`ITEM_SLOT_FULL` REPLACES C13's `AT_LIMIT` AND THE RENAME IS THE POINT. §4.4's anti-frustration
	rule means a refused pickup leaves the item in the container for somebody else, so this verdict
	is a UX finding rather than a fault — and its name should say which of the two mechanics refused.

	PREFIXED `ITEM_` FOR `SearchVerdict`'S REASON (Types.luau:520). `SaltVerdict` already carries a
	bare `WRONG_PHASE` and `SearchVerdict` a prefixed one; a third union sharing the bare spelling
	makes a handler wired to the wrong path a working program with the wrong meaning.
]]
export type Verdict =
	"OK"
	| "ITEM_WRONG_PHASE"
	| "ITEM_NOT_ALIVE"
	| "ITEM_SLOT_FULL"
	| "ITEM_NO_LIMIT_SET"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	-- The slot's CURRENT occupant, or nil for an empty hand. NOT a count: §4.6's three items are
	-- different mechanics and "you are holding one thing" cannot say which.
	Held: ItemType?,
	-- What the container is offering. Present so a future rule can differ by item without a second
	-- module; V08 treats all three identically and `tests/item-carry.test.luau` asserts that it does.
	Incoming: ItemType,
	Limit: number,
}

local ItemCarry = {}

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in KillValidation and C13's SaltCarry:
	world facts first, then the player, then the slot. A log full of ITEM_SLOT_FULL is a UX finding —
	players opening containers they cannot benefit from — and a log full of anything above it is a
	correctness finding.

	ITEM_NOT_ALIVE IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`. A DEAD player must not pick
	anything up — the arsenal belongs to players who can still be killed by the thing it answers —
	and DEAD is a state a body walks around in, so the denylist form starts admitting them the moment
	anything gives a dead player a position. This is `pure/PlayerBody`'s warning in a second file,
	and V01's husk work landed exactly the thing it predicted.
]]
function ItemCarry.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "ITEM_WRONG_PHASE"
	end

	if request.PlayerState ~= "ALIVE" then
		return "ITEM_NOT_ALIVE"
	end

	--[[
		FAIL CLOSED ON THE LIMIT, and test it for positive-and-finite rather than for zero.

		INHERITED FROM C13 UNCHANGED AND STILL EARNING ITS PLACE even though the slot is now a
		presence rather than a count. `Limit` arrives from Config. A `CarryLimit` typo of `0` reads as
		"carry nothing" and the occupancy comparison below would catch it; `-1` and `0/0` would not,
		and `math.huge` is worse than either because it silently deletes the limit. KillValidation's
		cooldown took three attempts to get this right; this is the fifth version of that lesson.
	]]
	if not (request.Limit > 0 and request.Limit < math.huge) then
		return "ITEM_NO_LIMIT_SET"
	end

	--[[
		OCCUPANCY, COMPARED THE SAME WAY C13's COUNT WAS. With CarryLimit = 1 a player holding
		anything has occupancy 1, which is `>=` the limit and must be refused — `>` would admit them
		and the limit would be off by exactly one, which is the whole limit when the limit is one.

		WRITTEN AS AN OCCUPANCY RATHER THAN AS `if request.Held ~= nil` SO THAT `Limit` STAYS
		LOAD-BEARING. If `Config.Items.CarryLimit` ever rises, `Held` becomes a list and this line is
		the one that already knows what to do with it. `Types.ClientRoundSnapshot.YourCarriedItem`
		says the same thing about the snapshot field: a rising limit is a contract change to argue in
		a plan, not a field to widen quietly.

		C13's SECOND GUARD — the NaN-carried branch — IS DELETED RATHER THAN MIGRATED. It closed a
		hole in an input SHAPE that no longer exists: `Carried` was a running integer produced by
		arithmetic that could reach NaN, while `occupancy` below is provably 0 or 1 with no
		arithmetic left to poison. `tests/item-carry.test.luau` asserts that across the whole grid,
		which is what replaces the guard.
	]]
	local occupancy = if request.Held ~= nil then 1 else 0

	if occupancy >= request.Limit then
		return "ITEM_SLOT_FULL"
	end

	return "OK"
end

return ItemCarry
