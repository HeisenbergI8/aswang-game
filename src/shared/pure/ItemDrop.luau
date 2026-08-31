--!strict
--[[
	ItemDrop — may this player put down what they are holding? (§4.6, V08)

		(request) -> verdict

	THE SMALLEST OF THE FOUR ITEM MODULES, AND IT HAS NO GEOMETRY AT ALL. You may put down what you
	are holding, wherever you are standing, whenever you are alive in an ACTIVE round. There is no
	"you cannot drop here", and the absence is deliberate.

	A PLACEMENT RULE WOULD BE V09'S, NOT V08'S. Bawang is PLACED on a doorway and that placement has
	conditions — a doorway, a duration, a burn-out. Dropping is the plain act of ceasing to hold
	something. Conflating the two now would build half of V09 inside V08 with none of its rules
	written down, which is the specific failure `pure/ItemUse` exists to prevent.

	WHY A SEPARATE MODULE FROM `ItemCarry` RATHER THAN AN `Incoming = nil` CASE. They refuse for
	different reasons and one of the refusals has no counterpart: `ITEM_NOTHING_HELD` is the whole
	question here and is not a state `ItemCarry` can be in, while `ITEM_SLOT_FULL` is meaningless
	for a drop. Merging them would give each module a verdict it can never return, which compiles
	and means nothing — the same argument `Types.luau` makes for keeping the three unions apart.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It never takes a role. §4.4 has the
	Aswang searching, carrying and dropping on identical rules, so the monster reaches this module
	and gets OK exactly as a survivor does — which is what keeps an empty slot from being a tell.

	NO `script.Parent` REQUIRES. The unions are re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

export type Verdict = "OK" | "ITEM_WRONG_PHASE" | "ITEM_NOT_ALIVE" | "ITEM_NOTHING_HELD"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Held: ItemType?,
}

local ItemDrop = {}

--[[
	THE SAME FIXED ORDER AS `ItemCarry` AND `ItemThrow`: world facts, then the player, then the slot.

	ITEM_NOT_ALIVE IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s reason.
	A DEAD player must not drop: the death path already spills the item where they fell (§4.6), so a
	dead player who could also drop would be a duplication surface — and there is exactly one buntot
	pagi in the round.

	DROPPING DURING A NON-ACTIVE PHASE IS REFUSED rather than tolerated, even though the slot is
	cleared on the way into INTERMISSION anyway. The tolerant version puts an item on the floor of a
	round that has ended, where the phase sweep may or may not have run yet depending on ordering.
]]
function ItemDrop.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "ITEM_WRONG_PHASE"
	end

	if request.PlayerState ~= "ALIVE" then
		return "ITEM_NOT_ALIVE"
	end

	if request.Held == nil then
		return "ITEM_NOTHING_HELD"
	end

	return "OK"
end

return ItemDrop
