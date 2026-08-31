--!strict
--[[
	ItemUse — does the thing in my hand have a verb yet? (§4.6, V08)

		verbFor(held) -> verdict

	THIS MODULE EXISTS TO MAKE A BOUNDARY MECHANICAL RATHER THAN REMEMBERED. §4.6 gives each of the
	three items a different verb: salt is thrown, bawang is placed on a doorway for 15 seconds, and
	the buntot pagi strikes an Aswang that is both Exposed and Weakened. V08 builds the CARRY, the
	DROP and the SLOT for all three, and the THROW for salt. The other two verbs are V09 and V10.

	WHY THAT IS WORTH A FILE. "Bawang does nothing yet" is a fact that lives nowhere: not in a type,
	not in a test, and — once V08 ships and the item can be picked up and dropped and looks finished
	— not in anyone's head either. A reader six weeks later finds an item with no effect and cannot
	tell a deliberate boundary from a bug, and the two have opposite fixes. Written down here, the
	boundary is `tests/item-use.test.luau` asserting two cells, and V09 turns one of them red on
	purpose.

	IT IS NOT A FEATURE FLAG. There is no config, no toggle and no dead code path behind the
	unimplemented verbs. V09 replaces `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real
	mechanic in the same chunk, or it does not land.

	IT ALSO GUARDS A REAL BUG, WHICH IS THE HALF THAT IS NOT DOCUMENTATION. `ItemService`'s throw
	handler spends the slot on a MISS, because §4.6 says a miss still costs you the pouch. Under
	`pure/ItemThrow` a player holding a BAWANG or the BUNTOT_PAGI who presses throw also gets MISS —
	the fifth world, collapsed deliberately — so the spend line would destroy the round's only win
	condition on a keypress, with a symptom indistinguishable from an honest miss. The handler asks
	this module before spending, so the boundary asserted here is the boundary the service enforces.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It takes an item and returns a verb.
	It never sees a role, a phase, a player or a position — those are the caller's, and the caller
	asks `ItemThrow` about them. A client that requires and runs this learns that bawang has no verb
	yet, which it also learns by pressing the key.

	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural.
]]

export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

export type Verdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"

local ItemUse = {}

--[[
	EXHAUSTIVE OVER THE THREE ITEMS PLUS THE EMPTY HAND, AND WRITTEN AS AN IF-CHAIN RATHER THAN A
	LOOKUP TABLE ON PURPOSE.

	A `{ [ItemType]: Verdict }` table would infer its values as plain `string` — a literal union
	survives `require` as a scalar but NOT inside a table
	(`.claude/lessons/pure-module-unions-widen-in-lists.md`), so the table would need an annotation
	that is longer than the branches, and a missing key would return `nil` instead of failing to
	compile. Branches return the union directly and the analyzer checks every one.
]]
function ItemUse.verbFor(held: ItemType?): Verdict
	if held == nil then
		return "USE_NOTHING_HELD"
	end

	if held == "SALT" then
		return "USE_THROW"
	end

	--[[
		BAWANG (V09) AND BUNTOT PAGI (V10). Both answer the same thing, deliberately, and NOT two
		distinct "not yet" values — a split here would be a hint about which chunk is closer to
		landing, which is a fact about the roadmap and not about the game.
	]]
	return "USE_NOT_IMPLEMENTED"
end

return ItemUse
