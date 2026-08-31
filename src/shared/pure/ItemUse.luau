--!strict
--[[
	ItemUse — which verb does the thing in my hand have? (§4.6, V08, extended V09)

		verbFor(held) -> verdict

	THIS MODULE EXISTS TO MAKE A BOUNDARY MECHANICAL RATHER THAN REMEMBERED. §4.6 gives each of the
	three items a different verb: salt is thrown, bawang is placed on a doorway for 15 seconds, and
	the buntot pagi strikes an Aswang that is both Exposed and Weakened. V08 built the CARRY, the DROP
	and the SLOT for all three, and the THROW for salt; V09 added the PLACE for bawang. The strike is
	V10 and is the only verb left.

	WHY THAT IS WORTH A FILE. "The buntot pagi does nothing yet" is a fact that lives nowhere: not in
	a type, not in a test, and — once V08 ships and the item can be picked up and dropped and looks
	finished — not in anyone's head either. A reader six weeks later finds an item with no effect and
	cannot tell a deliberate boundary from a bug, and the two have opposite fixes. Written down here,
	the boundary is `tests/item-use.test.luau` asserting one cell. V09 already turned the other one
	red on purpose and replaced it in the same chunk, which is what that is supposed to look like.

	IT IS NOT A FEATURE FLAG. There is no config, no toggle and no dead code path behind the
	unimplemented verb. V09 replaced `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real
	mechanic in the same chunk; V10 does the same for the buntot pagi, or it does not land.

	IT ALSO GUARDS A REAL BUG, WHICH IS THE HALF THAT IS NOT DOCUMENTATION. `ItemService`'s throw
	handler spends the slot on a MISS, because §4.6 says a miss still costs you the pouch. Under
	`pure/ItemThrow` a player holding a BAWANG or the BUNTOT_PAGI who presses throw also gets MISS —
	the fifth world, collapsed deliberately — so the spend line would destroy the round's only win
	condition on a keypress, with a symptom indistinguishable from an honest miss. The handler asks
	this module before spending, so the boundary asserted here is the boundary the service enforces.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It takes an item and returns a verb.
	It never sees a role, a phase, a player or a position — those are the caller's, and the caller
	asks `ItemThrow` or `GarlicPlacement` about them. A client that requires and runs this learns that
	the buntot pagi has no verb yet, which it also learns by pressing the key.

	THE CLIENT LEGITIMATELY ROUTES ON IT (V09). `InputController` asks this module which remote the
	`Q` key should fire. That is a convenience and never an authority: the server re-derives the item
	from its own slot table on every path, so a client that answers wrongly gets a refusal.

	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural.
]]

export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

export type Verdict = "USE_THROW" | "USE_PLACE" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"

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
		BAWANG (V09). §4.6's second verb: placed on a doorway, denying it for `GarlicDuration`, then
		burning out.

		THE VALUE IS WHAT STOPS THE THROW HANDLER DESTROYING IT. `pure/ItemThrow` collapses a player
		holding bawang into MISS — the fifth world, deliberately, so a refusal shape cannot be
		differenced into a role oracle — and MISS reaches `ItemService`'s spend line. The throw
		handler asks this module before spending, so the moment `USE_PLACE` exists a mis-press with
		bawang in hand stops burning one of the round's two.
	]]
	if held == "BAWANG" then
		return "USE_PLACE"
	end

	--[[
		BUNTOT PAGI (V10), AND IT IS NOW THE ONLY ITEM WITHOUT A VERB. The reason a split between two
		unimplemented items would have been a roadmap hint has expired with the split — there is one
		left, and `tests/item-use.test.luau` is where its boundary is written down until V10 moves it.
	]]
	return "USE_NOT_IMPLEMENTED"
end

return ItemUse
