--!strict
--[[
	REVIEW — src/shared/pure/ItemCarry.luau (135 lines at time of reading)

	V09 does not modify this file. It is reviewed because `pure/GarlicPlacement` is written to its
	shape, and three of its rules are copied rather than re-derived.
]]

-- src/shared/pure/ItemCarry.luau:24-31
-- The secrecy paragraph every new item module inherits.
--
-- IMPORTANT: "§4.4 has the Aswang searching on identical rules, so the Aswang DOES reach this module,
-- DOES get OK, and DOES fill a slot. That is correct." `pure/GarlicPlacement` inherits this exactly:
-- the monster reaches it, gets GARLIC_OK, places bawang and is then blocked by its own garlic. A
-- placement rule that refused the monster would be a role oracle readable by pressing a key — and it
-- would also delete the best bluff in the design.
--[[
	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. This module never takes a role and it
	must not start. A carry limit that differed for the Aswang would be a role oracle readable by
	opening a container — and note that §4.4 has the Aswang searching on identical rules, so the
	Aswang DOES reach this module, DOES get OK, and DOES fill a slot.
]]

-- src/shared/pure/ItemCarry.luau:33-40
-- CLAUDE.md's shared/ vs server/pure/ test, applied rather than assumed.
--
-- NOTE: `pure/GarlicPlacement` and `pure/GarlicBarrier` pass the same test and the plan states why.
-- No seed anywhere; every input is already on the client (its own phase, its own state, its own slot,
-- a Config number, and a doorway everyone can walk to). A client that requires and runs either module
-- learns something it could learn by trying.
--[[
	IT LIVES IN `src/shared/pure/` AND NOT `src/server/pure/`, which is CLAUDE.md's test applied
	rather than assumed: are the inputs client-suppliable, and is there a seed?
]]

-- src/shared/pure/ItemCarry.luau:53-61
-- The verdict-prefix rule.
--
-- IMPORTANT: `SaltVerdict` carries a bare `WRONG_PHASE` and `SearchVerdict` a prefixed one, and "a
-- third union sharing the bare spelling makes a handler wired to the wrong path a working program
-- with the wrong meaning". V09 adds a FOURTH union in the same service. `GARLIC_` prefixes are not
-- cosmetic — four verdict unions now run inside one file.
--[[
	PREFIXED `ITEM_` FOR `SearchVerdict`'S REASON (Types.luau:520). `SaltVerdict` already carries a
	bare `WRONG_PHASE` and `SearchVerdict` a prefixed one; a third union sharing the bare spelling
	makes a handler wired to the wrong path a working program with the wrong meaning.
]]

-- src/shared/pure/ItemCarry.luau:82-93
-- The fixed order, and the allowlist-of-ALIVE rule.
--
-- IMPORTANT: both are copied verbatim into `pure/GarlicPlacement`. "ITEM_NOT_ALIVE IS AN ALLOWLIST OF
-- ALIVE, never `~= "SPECTATOR"`" — a DEAD player walks around as a body in this game, so the denylist
-- form starts admitting them the moment anything gives a dead player a position. V01's husk work
-- landed exactly the thing that warning predicted.
--
-- NOTE: the order is asserted by the suite, not merely written down — a dead player at no doorway
-- holding nothing must return the ALIVE verdict, not the doorway one, because the order is what makes
-- the server's log readable.
function ItemCarry.evaluate(request: Request): Verdict

-- src/shared/pure/ItemCarry.luau:107-117
-- The fail-closed limit guard, on its fifth outing.
--
-- IMPORTANT: `pure/GarlicPlacement` copies this for `Range`. Test positive-and-finite, not for zero:
-- `-1` and `0/0` slip past a zero test and `math.huge` is worse than either because it silently
-- deletes the walk that IS the cost of placing garlic. "KillValidation's cooldown took three attempts
-- to get this right; this is the fifth version of that lesson" — do not make it the sixth.
if not (request.Limit > 0 and request.Limit < math.huge) then
	return "ITEM_NO_LIMIT_SET"
end
