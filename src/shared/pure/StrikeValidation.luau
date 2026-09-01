--!strict
--[[
	StrikeValidation — may this swing kill, and if not, may the striker learn why not. (§4.6, V10)

		(request) -> verdict

	§4.6: the buntot pagi "kills only an Aswang that is both Exposed (glowing from a salt hit) and
	Weakened (at or below 25 health). Against anything else it does nothing." Both halves of that
	sentence are mechanics and the SECOND one is the harder to build. "Does nothing" has to mean
	nothing observable, and this module is where that is made structural rather than careful.

	THE VERDICT UNION IS THE DESIGN. Four worlds involve a target — there is nobody in reach, the
	nearest reachable player is a survivor, the Aswang is in reach but not Exposed, the Aswang is
	Exposed but not Weakened — and this module CANNOT TELL THEM APART. They are one value,
	`STRIKE_NO_EFFECT`, and there is no arrangement of the code that recovers which. That is
	`pure/ItemThrow`'s "fifth world, collapsed into MISS deliberately" applied to a sharper case:
	salt's collapse protects a role, this one protects a role AND a health value AND a position.

	THE THREE STRIKER-SIDE VERDICTS ARE ALLOWED TO DIFFER, and where the line falls is the whole
	decision. WRONG_PHASE, NOT_ALIVE and NOT_HELD are facts about the requester that the requester
	already holds — its own phase off the snapshot, its own aliveness, its own hand. Nothing below
	them may differ, because everything below them is a fact about somebody else.

	IT TAKES TWO BOOLEANS, NOT A HEALTH VALUE AND NOT A `MonsterState` == "EXPOSED" TEST, AND BOTH
	ARE CORRECTIONS TO THE OBVIOUS SIGNATURE:

	  · `MonsterService.monsterStateOf` NEVER RETURNS `EXPOSED`. It produces CAMOUFLAGED, FEEDING,
	    TRANSFORMED and NORMAL, and its header says why: "EXPOSED IS A LATCH, NOT AN ACTIVITY… a
	    salted Aswang is Exposed AND still an Aswang." A module gating on the state enum would refuse
	    every cell of the grid forever, and the symptom would be that the second win condition
	    silently does not exist — §6.5 invariant 1's exact failure mode. So the gate is the LATCH,
	    read through `MonsterService.IsExposed`.
	  · `Weakened` IS A HEALTH PREDICATE, NOT A STATE. `Enums.luau` refuses to make it a
	    `MonsterState` member because "duplicating it as an enum member is how two sources of truth
	    for one fact get out of step." `MonsterService.IsWeakened` is the one source, and it is
	    already documented there as "V08's strike gate, half two."

	THE HEALTH NUMBER DELIBERATELY DOES NOT APPEAR IN THIS SIGNATURE. Passing it would typecheck and
	would leak nothing through the pure layer — a client cannot supply it — but it would force
	`ItemService` to hold the Aswang's health in a local at the call site, and `MonsterService`'s
	header is explicit that none of its seams "returns the health value." A number living in a second
	service's local is where a log line, a verbose print or a payload field grows.

	THE ROLE IS NOT A FIELD EITHER, AND IT DOES NOT NEED TO BE — which is a real improvement on
	`pure/KillValidation`, whose header has to warn that "TARGET_IS_ASWANG is a role oracle in one
	word." Only the Aswang has monster state, so only the Aswang can be Exposed or Weakened; both
	booleans are false for every survivor, every round. `Exposed AND Weakened` therefore IMPLIES the
	role rather than asking about it, and there is no value in this union that names one.

	IT LIVES IN `src/shared/pure/`, AND THAT IS CLAUDE.md'S TEST APPLIED RATHER THAN ASSUMED. There is
	no seed and no client-suppliable input: both booleans come off a server-only table, the distance
	is measured between the server's copies of two characters, the phase is `RoundService.GetPhase()`
	and `Held` is the server's own slot. A client that requires and runs this learns the RULE — which
	§4.6 states, §9.1's tutorial teaches and one round of play demonstrates — and cannot supply the
	arguments that would make it answer anything about a real player. Same test `KillValidation` and
	`MonsterHealth` both passed; `server/pure/ContainerLayout` is what failing it looks like.

	NO Vector3, FOR `KillValidation`'S REASON: Lune has no Roblox datatypes, so a Vector3 here fails
	at TEST time rather than at typecheck time. The caller passes a scalar distance it has already
	measured — this module does no geometry beyond comparing that scalar to a range.

	NO `script.Parent` REQUIRES. Every union is re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"

export type Verdict =
	"STRIKE_KILL"
	| "STRIKE_WRONG_PHASE"
	| "STRIKE_NOT_ALIVE"
	| "STRIKE_NOT_HELD"
	| "STRIKE_NO_EFFECT"

export type Request = {
	Phase: RoundPhase,
	-- The STRIKER's own three facts. Everything above the spend line.
	StrikerState: PlayerState,
	Held: ItemType?,
	--[[
		THE TARGET, AS FOUR OPTIONAL FACTS, AND `nil` MEANS "THE SERVER RESOLVED NOBODY".

		`GarlicPlacement.DoorwayDistance`'s convention exactly: nil is a different world from "there
		is one and it is out of reach", the two land on the same verdict because nothing is echoed
		either way, and the SERVER logs which by looking at its own lookup.
	]]
	TargetDistance: number?,
	--[[
		CARRIED AND ALMOST NEVER READ, WHICH IS DELIBERATE AND HAS EXACTLY ONE JOB.

		`nil` means the target has no monster state at all — which is every survivor, every round, and
		is the field that makes the Done line's grid LITERAL rather than interpretive. The Done line
		asks for a decision over `monsterState`; this is that axis, present and tested, even though
		the two booleans below already decide every cell. A field the function never reads is a field
		the analyzer cannot tell from a mistake, so it is read — see the branch in `evaluate`.
	]]
	TargetState: MonsterState?,
	TargetPlayerState: PlayerState?,
	-- From `MonsterService.IsExposed` / `IsWeakened`. False for anyone with no monster state.
	TargetExposed: boolean,
	TargetWeakened: boolean,
	Range: number,
}

local StrikeValidation = {}

--[[
	FAIL CLOSED ON A DEGENERATE RANGE — `pure/KillValidation.withinRange`'s guard, fourth use in this
	repo, and written as one negated conjunction for the identical NaN reason. `NaN > 0` and
	`NaN < math.huge` are both false, so the conjunction is false and the negation refuses; written
	the other way round every NaN comparison is false and NaN sails through.

	THE FAILURE DIRECTION IS THE POINT AND IT IS THE OPPOSITE OF THE KILL'S. A degenerate range on a
	kill grants a monster free kills; a degenerate range here produces a buntot pagi that never kills,
	which is the SILENT failure §6.5 invariant 1 exists to describe. `tests/config.test.luau` is the
	loud half; this is the second line of defence, and it refuses rather than granting because a
	strike that lands from `math.huge` studs is strictly worse than one that never lands.

	A NaN DISTANCE ALSO REFUSES, for free: `NaN <= range` is false.
]]
local function withinRange(distance: number?, range: number): boolean
	if distance == nil then
		return false
	end

	if not (range > 0 and range < math.huge) then
		return false
	end

	-- `<=`: §4.6 gives a reach, and a striker standing at exactly the reach is within it. Matches
	-- `KillValidation.withinRange`, which the config invariant compares this range against.
	return distance <= range
end

--[[
	THE ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in `KillValidation`, `ItemCarry`,
	`ItemDrop`, `ItemThrow` and `GarlicPlacement`: world facts, then the striker, then the slot, then
	everything about the target.

	THE BOUNDARY BETWEEN THE THIRD AND FOURTH GROUPS IS THE SPEND LINE, and it is the most important
	line in this chunk. `ItemService`'s handler spends the slot for every verdict BELOW
	`STRIKE_NOT_HELD` — including `STRIKE_NO_EFFECT` — and for none above it. §4.6 says "it breaks on
	use" and a swing is a use; the competing reading is refused on SECRECY grounds, not balance ones.

	WHY, IN ONE PARAGRAPH, BECAUSE THIS IS THE SENTENCE A LATER AUTHOR WILL WANT TO UNDO.
	`ClientRoundSnapshot.YourCarriedItem` is pushed to every client every `Round.SnapshotInterval`, so
	whether the item survived a swing is readable off the striker's OWN HUD. A spend conditional on
	the kill therefore turns the buntot pagi into a reusable detector: swing at each player in turn,
	watch your slot, and the swing that costs nothing has named the Aswang and reported that it is not
	yet Weakened. `ItemService`'s throw handler already refuses the same trade for salt — "a miss that
	cost nothing would make salt a probe you throw at everyone" — and there is exactly ONE buntot pagi
	and it IS the second win condition.

	SO THE FOUR TARGET-SIDE WORLDS COLLAPSE HERE, AND NOT IN THE CALLER. A service that mapped four
	verdicts onto one silent return would be correct today and one careless log line from being an
	oracle tomorrow. Collapsing in the module means the information is not merely unsent — it was
	never computed.
]]
function StrikeValidation.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "STRIKE_WRONG_PHASE"
	end

	-- AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s reason and `ItemDrop`'s.
	-- A DEAD striker must not swing: the death path already spilled the item where they fell (§4.6),
	-- so a dead striker who could still swing would be swinging something they no longer hold.
	if request.StrikerState ~= "ALIVE" then
		return "STRIKE_NOT_ALIVE"
	end

	if request.Held ~= "BUNTOT_PAGI" then
		return "STRIKE_NOT_HELD"
	end

	--------------------------------------------------------------------------
	-- THE SPEND LINE. Everything below here returns one of two values.
	--------------------------------------------------------------------------

	if not withinRange(request.TargetDistance, request.Range) then
		return "STRIKE_NO_EFFECT"
	end

	-- A target with no monster state is a survivor. Not a separate verdict, and not a separate
	-- BRANCH from the two below it in any observable sense — the three are one world.
	if request.TargetState == nil then
		return "STRIKE_NO_EFFECT"
	end

	-- The Aswang must be alive to be killed. Unreachable today (a dead Aswang ends the round) and
	-- kept for `KillValidation.TARGET_IS_ASWANG`'s reason: the day something else changes, the
	-- failure must be "the strike does nothing", not "the corpse can be struck again".
	if request.TargetPlayerState ~= "ALIVE" then
		return "STRIKE_NO_EFFECT"
	end

	--[[
		§4.6, AND BOTH ARE REQUIRED. Written as one condition rather than two branches SO THAT THERE
		IS NO PLACE TO PUT A DIFFERENT RETURN. Two `if`s with two bodies is the shape a future author
		fills in with `STRIKE_NOT_WEAKENED` on an afternoon when the spec is not open; one condition
		with one body has nowhere to put it.
	]]
	if not (request.TargetExposed and request.TargetWeakened) then
		return "STRIKE_NO_EFFECT"
	end

	return "STRIKE_KILL"
end

return StrikeValidation
