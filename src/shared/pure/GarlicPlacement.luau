--!strict
--[[
	GarlicPlacement — may this player put bawang on this doorway right now? (§4.6, V09)

		(request) -> verdict

	THE FOURTH ITEM VERDICT, AND IT IS A SEPARATE MODULE FROM `ItemDrop` FOR THE REASON `ItemDrop`'S
	OWN HEADER PREDICTED: "a placement rule would be V09's, not V08's. Bawang is PLACED on a doorway
	and that placement has conditions — a doorway, a duration, a burn-out. Dropping is the plain act
	of ceasing to hold something." This is that module, and merging the two would give each a verdict
	it can never return.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It never takes a role and it must not
	start. §4.4 has the Aswang searching and carrying on identical rules, so the monster reaches this
	module, gets `GARLIC_OK`, places bawang, and is then blocked by its own garlic. That is correct.
	A rule that refused the monster would be a role oracle readable by pressing a key, and it would
	also delete the best bluff in the design — an Aswang that seals a doorway and then declines to
	walk through it is playing the loyalty test rather than failing it.

	IT DECIDES NOTHING ABOUT THE BLOCK. Whether a barrier stops a character is physics on one client
	and geometry on the server (`pure/GarlicBarrier`); this module only decides whether one is
	created. Keeping the two apart is what lets the block's mechanism change without re-arguing the
	placement rule.

	THE CALLER RESOLVES THE DOORWAY. `DoorwayDistance` is nil when the server found no tagged
	`Doorway` at all, which is a different world from "there is one and you are too far from it" —
	the second is a UX finding, the first is a map fault. Both land on `GARLIC_NO_DOORWAY` because
	nothing is echoed to the client either way, and the SERVER logs which by looking at its own
	lookup.

	NO `script.Parent` REQUIRES. All three unions are re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

export type Verdict =
	"GARLIC_OK"
	| "GARLIC_WRONG_PHASE"
	| "GARLIC_NOT_ALIVE"
	| "GARLIC_NOT_HELD"
	| "GARLIC_NO_DOORWAY"
	| "GARLIC_DOORWAY_TAKEN"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	-- The slot's CURRENT occupant, or nil for an empty hand. Anything that is not BAWANG refuses.
	Held: ItemType?,
	-- Distance to the nearest tagged doorway the SERVER resolved, or nil if there was none.
	DoorwayDistance: number?,
	Range: number,
	-- Whether that doorway already carries live garlic. Two bawang on one doorway would double the
	-- denial to 30s from a supply of two, which is the safe room §3 forbids assembled by accident.
	DoorwayOccupied: boolean,
}

local GarlicPlacement = {}

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in `ItemCarry`, `ItemDrop` and
	`ItemThrow`: world facts first, then the player, then the slot, then the geometry.

	`GARLIC_NOT_ALIVE` IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s
	reason. A DEAD player must not seal a doorway: the death path already spills what they held
	(§4.6), and a body that can still deny the monster a room is a corpse playing the round.

	FAIL CLOSED ON THE RANGE, tested positive-and-finite rather than for zero — `ItemCarry.Limit`'s
	guard, fifth time. A `Range` of `math.huge` deletes the walk that IS the cost of placing garlic,
	and nothing in the game would say so.
]]
function GarlicPlacement.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "GARLIC_WRONG_PHASE"
	end

	if request.PlayerState ~= "ALIVE" then
		return "GARLIC_NOT_ALIVE"
	end

	if request.Held ~= "BAWANG" then
		return "GARLIC_NOT_HELD"
	end

	if not (request.Range > 0 and request.Range < math.huge) then
		return "GARLIC_NO_DOORWAY"
	end

	local distance = request.DoorwayDistance

	if distance == nil or distance ~= distance or distance > request.Range then
		return "GARLIC_NO_DOORWAY"
	end

	if request.DoorwayOccupied then
		return "GARLIC_DOORWAY_TAKEN"
	end

	return "GARLIC_OK"
end

return GarlicPlacement
