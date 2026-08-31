--!strict
--[[
	REVIEW — src/shared/Types.luau (918 lines at time of reading)

	V09 adds one union and two payload types, and changes one existing union by a single value.
]]

-- src/shared/Types.luau:27
-- The three items, and the union `pure/GarlicPlacement` re-declares locally rather than requiring.
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

-- src/shared/Types.luau:341-352
-- The prefix rule for the item verdicts, and it is now enforcing four unions rather than three.
--
-- IMPORTANT: `GarlicPlaceVerdict` uses `GARLIC_` for exactly this reason. Four verdict unions now run
-- inside `ItemService`, three of them with a wrong-phase value, and a handler wired to the wrong one
-- compiles and means something else.
export type ItemCarryVerdict =

-- src/shared/Types.luau:385
-- The union V09 changes, and it changes by exactly one value.
--
-- IMPORTANT: adding `"USE_PLACE"` is a scalar union edit — safe. Do NOT restructure it into a table
-- or a list on the way past: `.claude/lessons/pure-module-unions-widen-in-lists.md` is specific that
-- a literal union survives `require` as a SCALAR and not inside a LIST.
export type ItemUseVerdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"

-- src/shared/Types.luau:497-532
-- `ClientRoundSnapshot`, and V09 does not touch it.
--
-- IMPORTANT: this is worth stating positively rather than by omission. The garlic barrier does NOT
-- ride the snapshot, for two reasons. First, the snapshot is built for EVERY player, so a barrier
-- field would need a per-player branch in `buildSnapshot` — a role branch in the one function every
-- client's payload goes through, which is the most dangerous place in the codebase to put one.
-- Second, barriers change on placement and on burn-out, not on a 0.5s cadence, so a snapshot field
-- would either lag by half a second or force the snapshot rate up for everybody.
--
-- IMPORTANT: `YourCarriedItem`'s comment is the one V09's client routing depends on — the field is
-- the receiving player's OWN slot, server-owned, pushed per player with `:FireClient`. That makes it
-- safe for `InputController` to read when deciding which remote to fire, and the server re-derives
-- the item anyway, so a stale read costs a refusal rather than an advantage.
--
-- IMPORTANT: "The Aswang carries nothing… so its slot is `nil`, which is also what an empty-handed
-- survivor's slot is." That sentence is now WRONG in a way worth flagging: since V08 the Aswang
-- genuinely carries items (§4.4 has it searching on identical rules), which is what makes the field
-- safe. The comment reads as though the monster never holds anything. It is stale rather than
-- dangerous — the FIELD is correct either way — but a reader could take it as licence to special-case
-- the monster. Raised in Follow Ups.
export type ClientRoundSnapshot = {
	YourCarriedItem: ItemType?,
}

-- src/shared/Types.luau:534-560
-- The field that was DELETED, and why absence is load-bearing.
--
-- NOTE: the template for how `GarlicBarrierSpec`'s absent fields are documented. `AlivePlayerCount`
-- was a sub-second global death signal that let a client correlate replicated positions against
-- kills. A `PlacedBy` on a barrier spec is the same shape: it would let the one client that receives
-- it correlate a placement moment against replicated positions and learn who was standing at that
-- doorway. Absent, not trimmed.
--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).
]]

-- src/shared/Types.luau:730-747
-- `CamouflageUpdatePayload`, the shape `GarlicBarriersPayload` is written to.
--
-- NOTE: a verdict and an optional value, nothing else. `GarlicBarriersPayload` deliberately has NO
-- verdict field — it is a state snapshot rather than a reply, and a verdict inside a list would be
-- the exact literal-union-in-a-list failure the lesson describes.
export type CamouflageUpdatePayload = {
	Verdict: CamouflageVerdict,
}
