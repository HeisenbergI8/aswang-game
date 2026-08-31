--!strict
--[[
	REVIEW — src/shared/pure/ItemUse.luau (71 lines at time of reading)

	The smallest file in the chunk and the one V09 is contractually obliged to change.
]]

-- src/shared/pure/ItemUse.luau:14-19
-- The module states its own expiry date.
--
-- IMPORTANT: "V09 replaces `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real mechanic
-- in the same chunk, or it does not land." This is a constraint on the chunk, not a note: a V09 that
-- shipped the barrier without moving this cell would leave `ItemService`'s throw handler still
-- treating bawang as unimplemented, and `tests/item-use.test.luau` still asserting it.
--
-- NOTE: it is explicitly NOT a feature flag — "no config, no toggle and no dead code path". So the
-- change is a new branch returning a new value, never a boolean somewhere.
--[[
	IT IS NOT A FEATURE FLAG. There is no config, no toggle and no dead code path behind the
	unimplemented verbs. V09 replaces `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real
	mechanic in the same chunk, or it does not land.
]]

-- src/shared/pure/ItemUse.luau:21-30
-- The real bug this module guards, and it is the reason Step 2.3 cannot be deferred.
--
-- IMPORTANT: `pure/ItemThrow` returns MISS for a player holding BAWANG or BUNTOT_PAGI, and MISS
-- reaches `ItemService`'s spend line. Without the `ItemUse` guard, pressing throw with bawang in hand
-- destroys one of the round's two, with a symptom indistinguishable from an honest miss. V09 must
-- keep the guard testing `~= "USE_THROW"` — rewriting it as `== "USE_NOT_IMPLEMENTED"` would compile,
-- pass every check, and silently start burning bawang again.
--[[
	IT ALSO GUARDS A REAL BUG, WHICH IS THE HALF THAT IS NOT DOCUMENTATION. `ItemService`'s throw
	handler spends the slot on a MISS, because §4.6 says a miss still costs you the pouch. Under
	`pure/ItemThrow` a player holding a BAWANG or the BUNTOT_PAGI who presses throw also gets MISS —
	the fifth world, collapsed deliberately — so the spend line would destroy the round's only win
	condition on a keypress, with a symptom indistinguishable from an honest miss.
]]

-- src/shared/pure/ItemUse.luau:47-53
-- Why this is an if-chain and not a lookup table.
--
-- IMPORTANT: this is `.claude/lessons/pure-module-unions-widen-in-lists.md` applied prospectively. A
-- `{ [ItemType]: Verdict }` table infers its values as plain `string`. V09 adds a branch; it must not
-- "tidy" the three branches into a table on the way past, and neither of the two new pure modules may
-- return a literal union from inside a list.
--[[
	A `{ [ItemType]: Verdict }` table would infer its values as plain `string` — a literal union
	survives `require` as a scalar but NOT inside a table
	(`.claude/lessons/pure-module-unions-widen-in-lists.md`), so the table would need an annotation
	that is longer than the branches, and a missing key would return `nil` instead of failing to
	compile. Branches return the union directly and the analyzer checks every one.
]]

-- src/shared/pure/ItemUse.luau:63-70
-- The branch V09 splits.
--
-- IMPORTANT: the comment's argument — that two "not yet" values would hint at the roadmap — EXPIRES
-- when only one item is left unimplemented. Rewrite the comment rather than leaving it, or a reader
-- at V10 finds a justification for a split that no longer exists.
--
-- NOTE: do NOT delete the `USE_NOT_IMPLEMENTED` case. V10 needs the boundary to still exist for the
-- buntot pagi, and the whole reason this module was written was to keep that boundary in a test
-- rather than in someone's head.
--[[
	BAWANG (V09) AND BUNTOT PAGI (V10). Both answer the same thing, deliberately, and NOT two
	distinct "not yet" values — a split here would be a hint about which chunk is closer to
	landing, which is a fact about the roadmap and not about the game.
]]
return "USE_NOT_IMPLEMENTED"
