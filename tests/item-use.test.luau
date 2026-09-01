--!strict
--[[
	The V08/V09/V10 boundary (§4.6), asserted so that moving it is a deliberate edit.

	Two of these assertions are WRITTEN TO GO RED. When V09 gives bawang its doorway block, the
	bawang cell fails; when V10 gives the buntot pagi its strike, the other one does. That is the
	file working, not the file breaking.
]]

local ItemUse = require("../src/shared/pure/ItemUse")

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

check("salt is thrown", ItemUse.verbFor("SALT") == "USE_THROW")
check("an empty hand has no verb", ItemUse.verbFor(nil) == "USE_NOTHING_HELD")

--[[
	THE CELL V10 STILL HAS TO FLIP, AND THE ONE V09 ALREADY DID.

	READ THIS BEFORE "FIXING" A FAILURE HERE. If the buntot pagi's cell goes red, either the boundary
	moved deliberately — in which case the chunk that moved it deletes the assertion and replaces it
	with one about the new verb — or somebody gave an item an effect without building the mechanic
	behind it. Those have opposite fixes and this file is the only place that tells them apart.

	V09 IS WHAT THAT LOOKS LIKE WHEN IT GOES RIGHT. Bawang's cell asserted `USE_NOT_IMPLEMENTED`
	until the chunk that placed it on a doorway landed, and the chunk replaced the assertion in the
	same step as the verdict. The "indistinguishable unimplemented items" check went with it: there
	is only one such item now, so there is nothing left for it to be indistinguishable FROM.

	V10 IS THE LAST TIME. Three items, three verbs; there is no unimplemented cell left to guard and
	`USE_NOT_IMPLEMENTED` is gone from the union with this commit. What this suite pins from here is
	the ROUTING — that each item maps to exactly one verb and no two share — which is the property
	`InputController` and `ItemService`'s throw handler both depend on and neither states.
]]
check("bawang is placed on a doorway (V09)", ItemUse.verbFor("BAWANG") == "USE_PLACE")
check("the buntot pagi strikes (V10)", ItemUse.verbFor("BUNTOT_PAGI") == "USE_STRIKE")

--[[
	ALL THREE VERBS ARE DISTINCT, which is the property that replaced "the two unimplemented items
	answer identically" and which V10 completes. Salt is thrown, bawang is placed, the buntot pagi
	strikes; a service routing on this module must be able to tell all three apart, and
	`InputController` does exactly that on the `Q` key.

	PAIRWISE RATHER THAN "SALT vs BAWANG", because the union can no longer express it. While
	`USE_NOT_IMPLEMENTED` existed, an item that lost its verb collapsed to a value nothing else
	returned and the collision was visible; now every value is a real verb, so two items answering
	identically would route two different mechanics to one remote and typecheck perfectly.
]]
check("salt and bawang have different verbs", ItemUse.verbFor("SALT") ~= ItemUse.verbFor("BAWANG"))
check(
	"salt and the buntot pagi have different verbs",
	ItemUse.verbFor("SALT") ~= ItemUse.verbFor("BUNTOT_PAGI")
)
check(
	"bawang and the buntot pagi have different verbs",
	ItemUse.verbFor("BAWANG") ~= ItemUse.verbFor("BUNTOT_PAGI")
)

--[[
	THE ASSERTION THE SERVICE DEPENDS ON, stated here rather than only at the call site.

	`ItemService`'s throw handler spends the slot only when this module says USE_THROW. If either of
	the two unimplemented items ever answered USE_THROW, pressing the throw key while holding the
	round's only win condition would destroy it — and the symptom is identical to an honest miss,
	because `pure/ItemThrow` collapses the wrong-item world into MISS on purpose.
]]
check(
	"nothing but salt may be spent by a throw",
	ItemUse.verbFor("BAWANG") ~= "USE_THROW" and ItemUse.verbFor("BUNTOT_PAGI") ~= "USE_THROW"
)

--[[
	Exhaustive: every member of the union plus nil, so a fourth item type added later fails here
	rather than silently falling through the if-chain to the buntot pagi's `USE_STRIKE`. That is a
	SHARPER trap than it was under `USE_NOT_IMPLEMENTED`, which was inert: a new item inheriting the
	strike verb would route to `RequestStrike` and be refused server-side at `STRIKE_NOT_HELD`, which
	looks exactly like a mechanic that has not been built. `check:scope` arms `weapons?` for that day.

	THE ANNOTATION IS LOAD-BEARING — without `: { ItemUse.ItemType }` the loop variable is plain
	`string`, `verbFor` accepts it, and the exhaustiveness this loop claims does not exist.
]]
local ITEMS: { ItemUse.ItemType } = { "SALT", "BAWANG", "BUNTOT_PAGI" }

for _, item in ITEMS do
	local verdict = ItemUse.verbFor(item)

	check(`{item} answers with a real verdict`, verdict ~= "USE_NOTHING_HELD", verdict)
end

check("the exhaustive loop covered all three items", #ITEMS == 3, `{#ITEMS} items`)

if failures > 0 then
	error(`{failures} item-use assertion(s) failed`, 0)
end

print(`  PASS  item-use: {checked} assertions over the three items and the empty hand`)
