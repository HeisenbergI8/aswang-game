--!strict
--[[
	REVIEW — src/shared/pure/ItemUse.luau
	Read for V10 planning. This whole module is a boundary marker left standing for this chunk, and
	Step 1.4 is the line that closes it.
]]

-- src/shared/pure/ItemUse.luau:8-11 — the header names V10 by number
--[[
	§4.6 gives each of the three items a different verb: salt is thrown, bawang is placed on a doorway
	for 15 seconds, and the buntot pagi strikes an Aswang that is both Exposed and Weakened. V08 built
	the CARRY, the DROP and the SLOT for all three, and the THROW for salt; V09 added the PLACE for
	bawang. The strike is V10 and is the only verb left.
]]
-- NOTE The module was written knowing exactly what V10 would do to it. Step 1.4 is a two-line change
--      to the code and a paragraph to the comment.

-- src/shared/pure/ItemUse.luau:20-21
--[[
	IT IS NOT A FEATURE FLAG. There is no config, no toggle and no dead code path behind the
	unimplemented verb. V09 replaced `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real
	mechanic in the same chunk; V10 does the same for the buntot pagi, or it does not land.
]]
-- IMPORTANT This is why the plan DELETES `USE_NOT_IMPLEMENTED` from the union rather than leaving it
--           as an unused value. After Step 1.4 no item returns it, so keeping it is precisely the
--           dead path this paragraph refuses. `Types.ItemUseVerdict` loses it in the same step.

-- src/shared/pure/ItemUse.luau:23-29 — the real bug this module guards
--[[
	IT ALSO GUARDS A REAL BUG, WHICH IS THE HALF THAT IS NOT DOCUMENTATION. `ItemService`'s throw
	handler spends the slot on a MISS, because §4.6 says a miss still costs you the pouch. Under
	`pure/ItemThrow` a player holding a BAWANG or the BUNTOT_PAGI who presses throw also gets MISS —
	the fifth world, collapsed deliberately — so the spend line would destroy the round's only win
	condition on a keypress, with a symptom indistinguishable from an honest miss.
]]
-- IMPORTANT THE GUARD MUST SURVIVE V10. `ItemService`'s throw handler asks `verbFor(...) ==
--           "USE_THROW"` before spending; that comparison is POSITIVE, so returning `USE_STRIKE`
--           instead of `USE_NOT_IMPLEMENTED` leaves it working unchanged. Do not "simplify" it into
--           a `~= "USE_NOT_IMPLEMENTED"` on the way past — that inverts to allow after this chunk.
-- NOTE      "the fifth world, collapsed deliberately so a refusal shape cannot be differenced into a
--           role oracle" is the SAME move `pure/StrikeValidation` makes with `STRIKE_NO_EFFECT`.
--           V10 inherits the pattern rather than inventing one.

-- src/shared/pure/ItemUse.luau:31-35
--[[
	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. ... A client that requires and runs
	this learns that the buntot pagi has no verb yet, which it also learns by pressing the key.

	THE CLIENT LEGITIMATELY ROUTES ON IT (V09). `InputController` asks this module which remote the
	`Q` key should fire. That is a convenience and never an authority.
]]
-- IMPORTANT This sentence is Step 4.1's whole licence. The client asking `verbFor` to choose a
--          remote is established, and the server re-derives the item from its own slot on every
--          path — so a client that answers wrongly gets a refusal, not an advantage.

-- src/shared/pure/ItemUse.luau:52-58 — why branches, not a lookup table
--[[
	A `{ [ItemType]: Verdict }` table would infer its values as plain `string` — a literal union
	survives `require` as a scalar but NOT inside a table
	(`.claude/lessons/pure-module-unions-widen-in-lists.md`) ...
]]
-- IMPORTANT THE SAME TRAP APPLIES TO `tests/strike-validation.test.luau`'s AXIS LISTS. The plan's
--           Step 2.2 annotates every axis local with its union type for exactly this reason; without
--           the annotation the axes widen to `{ string }` and the module's parameter rejects them.

-- src/shared/pure/ItemUse.luau:84-88 — the line Step 1.4 replaces
--[[
	BUNTOT PAGI (V10), AND IT IS NOW THE ONLY ITEM WITHOUT A VERB. ... `tests/item-use.test.luau` is
	where its boundary is written down until V10 moves it.
]]
return "USE_NOT_IMPLEMENTED"
-- NOTE `tests/item-use.test.luau:45` asserts this cell and goes red on purpose at Step 1.4. Step 1.5
--      moves it. That red-then-green pair IS the convention working; the test file's own header
--      calls V09 "what that looks like when it goes right".
