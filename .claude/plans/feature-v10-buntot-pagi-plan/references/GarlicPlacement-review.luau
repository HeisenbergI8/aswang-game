--!strict
--[[
	REVIEW — src/shared/pure/GarlicPlacement.luau
	Read for V10 planning. V09's verdict module is the closest template for `StrikeValidation`: same
	prefix rule, same fixed order, and the nil-distance convention V10 copies exactly.
]]

-- src/shared/pure/GarlicPlacement.luau:8-13
--[[
	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It never takes a role and it must not
	start. §4.4 has the Aswang searching and carrying on identical rules, so the monster reaches this
	module, gets `GARLIC_OK`, places bawang, and is then blocked by its own garlic. That is correct.
	A rule that refused the monster would be a role oracle readable by pressing a key ...
]]
-- IMPORTANT THIS PARAGRAPH IS WHY `ResolveStrikeTarget` MUST NOT REFUSE THE ASWANG'S OWN SWING. A
--           monster whose buntot pagi behaves differently from everybody's is a monster you can find
--           by handing it one. The plan states it in that function's header and flags it to the
--           exploit auditor as a decision rather than an oversight.

-- src/shared/pure/GarlicPlacement.luau:20-24 — THE nil CONVENTION V10 REUSES
--[[
	THE CALLER RESOLVES THE DOORWAY. `DoorwayDistance` is nil when the server found no tagged
	`Doorway` at all, which is a different world from "there is one and you are too far from it" —
	the second is a UX finding, the first is a map fault. Both land on `GARLIC_NO_DOORWAY` because
	nothing is echoed to the client either way, and the SERVER logs which by looking at its own
	lookup.
]]
-- IMPORTANT `StrikeValidation.TargetDistance: number?` IS THIS FIELD, WITH HIGHER STAKES. Here two
--           worlds collapse; there, FOUR do — nobody in reach, a survivor in reach, a healthy Aswang
--           in reach, an Exposed-but-not-Weakened one. The mechanism is identical and the
--           justification is stronger: nothing is echoed, and the server diagnoses by looking at its
--           own `ResolveStrikeTarget` return rather than at a verdict.

-- src/shared/pure/GarlicPlacement.luau:26-33 — the union, and the prefix rule
export type Verdict =
	"GARLIC_OK"
	| "GARLIC_WRONG_PHASE"
	| "GARLIC_NOT_ALIVE"
	| "GARLIC_NOT_HELD"
	| "GARLIC_NO_DOORWAY"
	| "GARLIC_DOORWAY_TAKEN"
-- NOTE SIX VALUES, THREE OF WHICH ARE TARGET-SIDE. `StrikeValidation` has FIVE, ONE of which is
--      target-side, and that asymmetry is the design rather than an economy. Garlic's world-side
--      refusals are safe to distinguish because a doorway is a public object; the strike's are not,
--      because the thing being resolved is a person.
-- IMPORTANT PREFIXED `STRIKE_` FOR THE SAME REASON THIS ONE IS PREFIXED `GARLIC_`: a sixth union
--           sharing a bare `WRONG_PHASE` spelling makes a handler wired to the wrong path a working
--           program with the wrong meaning. `Types.luau:341-347` states the rule.

-- src/shared/pure/GarlicPlacement.luau:15-18 — the separation-of-concerns rule
--[[
	IT DECIDES NOTHING ABOUT THE BLOCK. Whether a barrier stops a character is physics on one client
	and geometry on the server (`pure/GarlicBarrier`); this module only decides whether one is
	created. Keeping the two apart is what lets the block's mechanism change without re-arguing the
	placement rule.
]]
-- NOTE V10's equivalent: `StrikeValidation` decides nothing about what a DEATH is. Whether the
--      Aswang's body stays, what the round scores, and who is told are `MonsterService.StrikeDown`'s,
--      V11's and V12's. The module returns `STRIKE_KILL` and stops.

-- src/shared/pure/GarlicPlacement.luau:62-80 — the fixed order, fifth statement of it
--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in `ItemCarry`, `ItemDrop` and
	`ItemThrow`: world facts first, then the player, then the slot, then the geometry.

	`GARLIC_NOT_ALIVE` IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s
	reason. A DEAD player must not seal a doorway: the death path already spills what they held
	(§4.6), and a body that can still deny the monster a room is a corpse playing the round.

	FAIL CLOSED ON THE RANGE, tested positive-and-finite rather than for zero — `ItemCarry.Limit`'s
	guard, fifth time.
]]
-- IMPORTANT `StrikeValidation` FOLLOWS THE SAME ORDER AND THE SAME ALLOWLIST. A DEAD striker must
--           not swing for the same reason: the death path already spilled the item, so a dead
--           striker who could swing would be swinging something they no longer hold.
-- NOTE      "fail closed on the range, positive-and-finite" is now the SIXTH use of that idiom in
--           this repo. `StrikeValidation`'s copy is the seventh. Repeating it is correct — the two
--           earlier attempts at it both shipped broken (`KillValidation`'s header records why).
function GarlicPlacement.evaluate(request: Request): Verdict end
