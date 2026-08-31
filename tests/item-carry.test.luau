--!strict
--[[
	The item carry rule (§4.6, V08), over every player state, every item type and both sides of the
	limit.

	MIGRATED FROM `tests/salt-carry.test.luau` (C13, 38 assertions). Every cell of that grid is here
	under its V08 spelling, plus the item-type dimension the slot introduced.

	The cell this file exists for is DEAD. `ItemCarry.evaluate` uses an allowlist of ALIVE, and the
	denylist form (`~= "SPECTATOR"`) is identical in behaviour TODAY and wrong the moment a dead
	player has a body to walk to a container with. That is `pure/PlayerBody`'s warning arriving in a
	second file, and V01's husk work landed exactly the thing it predicted.

	THE NEW PROPERTY IS ITEM-TYPE BLINDNESS. V08 gives the slot three possible occupants, and the
	carry rule must not care which — a limit that differed by item is a rule nobody tuned, and a
	limit that differed by ROLE would be a role oracle readable by opening a container. §4.4 has the
	Aswang searching on identical rules, so the monster reaches this module, gets OK, and fills a
	slot. `Types.ClientRoundSnapshot.YourCarriedItem` is only safe because that is true.

	IT ALSO REPLACES C13's NaN-CARRIED GUARD WITH A PROPERTY. That guard closed a hole in an input
	SHAPE that no longer exists: `Carried` was a running integer produced by arithmetic, while
	occupancy is `if Held ~= nil then 1 else 0`. The grid below asserts the consequence directly —
	inside ACTIVE/ALIVE with a sane limit, the verdict is OK if and only if the hand is empty.
]]

local ItemCarry = require("../src/shared/pure/ItemCarry")

type PlayerState = ItemCarry.PlayerState
type RoundPhase = ItemCarry.RoundPhase
type ItemType = ItemCarry.ItemType

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

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

--[[
	ANNOTATED, AND THE ANNOTATION IS LOAD-BEARING.
	`.claude/lessons/pure-module-unions-widen-in-lists.md`: a literal union survives `require` as a
	SCALAR and does not survive it inside a LIST. Without `: { ItemType }` these infer as plain
	`string`, every comparison below still compiles, and the suite passes while asserting nothing
	about the union.
]]
local ITEMS: { ItemType } = { "SALT", "BAWANG", "BUNTOT_PAGI" }

local function request(overrides: {
	Phase: RoundPhase?,
	PlayerState: PlayerState?,
	Held: ItemType?,
	Incoming: ItemType?,
	Limit: number?,
}): ItemCarry.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		PlayerState = overrides.PlayerState or "ALIVE",
		-- No `or` fallback: nil IS the meaningful value here (an empty hand).
		Held = overrides.Held,
		Incoming = overrides.Incoming or "SALT",
		Limit = overrides.Limit or 1,
	}
end

--------------------------------------------------------------------------------
-- The full PHASE × STATE grid. 20 cells, and exactly one of them says OK.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local verdict = ItemCarry.evaluate(request({ Phase = phase, PlayerState = state }))

		local expected: ItemCarry.Verdict = if phase ~= "ACTIVE"
			then "ITEM_WRONG_PHASE"
			elseif state ~= "ALIVE" then "ITEM_NOT_ALIVE"
			else "OK"

		check(`{phase} x {state} is {expected}`, verdict == expected, `got {verdict}`)
	end
end

--[[
	The allowlist, asserted as a PROPERTY rather than as four cells: exactly one state may ever
	carry. A denylist rewrite that admitted DEAD would keep every cell above passing if someone
	"fixed" the expectation table to match, and would fail here.
]]
do
	local permitted = 0

	for _, state in STATES do
		if ItemCarry.evaluate(request({ PlayerState = state })) == "OK" then
			permitted += 1
		end
	end

	check("exactly one PlayerState may pick an item up", permitted == 1, `{permitted} permitted`)
end

--------------------------------------------------------------------------------
-- The HELD × INCOMING matrix — 12 cells, and the item-type blindness property.
-- This is the dimension the slot introduced and it is the reason this file exists.
--------------------------------------------------------------------------------

for _, incoming in ITEMS do
	check(
		`an empty hand accepts {incoming}`,
		ItemCarry.evaluate(request({ Held = nil, Incoming = incoming })) == "OK"
	)
end

for _, held in ITEMS do
	for _, incoming in ITEMS do
		check(
			`holding {held}, offered {incoming}, is ITEM_SLOT_FULL`,
			ItemCarry.evaluate(request({ Held = held, Incoming = incoming })) == "ITEM_SLOT_FULL"
		)
	end
end

--[[
	BLINDNESS AS A PROPERTY, NOT AS TWELVE CELLS. The cells above would all keep passing if someone
	added a per-item rule and updated the expectations to match. These two assert that the verdict
	set has exactly one member across each dimension, which a per-item rule cannot satisfy.
]]
do
	local seen: { [string]: boolean } = {}

	for _, incoming in ITEMS do
		seen[ItemCarry.evaluate(request({ Held = nil, Incoming = incoming }))] = true
	end

	local distinct = 0
	for _ in seen do
		distinct += 1
	end

	check("an empty hand answers every item type identically", distinct == 1, `{distinct} verdicts`)
end

do
	local seen: { [string]: boolean } = {}

	for _, held in ITEMS do
		for _, incoming in ITEMS do
			seen[ItemCarry.evaluate(request({ Held = held, Incoming = incoming }))] = true
		end
	end

	local distinct = 0
	for _ in seen do
		distinct += 1
	end

	check(
		"a full hand answers every item pairing identically",
		distinct == 1,
		`{distinct} verdicts`
	)
end

--------------------------------------------------------------------------------
-- The carry boundary. This is C13's "refused the second" in arithmetic, on a slot.
--------------------------------------------------------------------------------

check("empty-handed is OK", ItemCarry.evaluate(request({ Held = nil })) == "OK")

check(
	"holding one at a limit of one is refused",
	ItemCarry.evaluate(request({ Held = "SALT", Limit = 1 })) == "ITEM_SLOT_FULL"
)

--[[
	`>=` NOT `>`, which is the comparison C13's Verify line exercised. With a limit of one, a player
	holding anything has occupancy 1; `>` would admit them and the limit would be off by exactly
	one, which is the whole limit when the limit is one.

	The limit-of-two cell is kept from C13 even though `Config.Items.CarryLimit` is 1, because it is
	what proves `Limit` is still load-bearing rather than a decorative parameter beside an
	`if Held ~= nil` test. A rewrite to that shape passes every other assertion in this file.
]]
check(
	"a limit of two admits a second item",
	ItemCarry.evaluate(request({ Held = "SALT", Limit = 2 })) == "OK"
)

--------------------------------------------------------------------------------
-- Degenerate limits. The guard fails CLOSED, and `math.huge` is the dangerous one:
-- an infinite limit silently deletes the rule rather than loosening it.
--------------------------------------------------------------------------------

check(
	"a zero limit carries nothing",
	ItemCarry.evaluate(request({ Limit = 0 })) == "ITEM_NO_LIMIT_SET"
)

check(
	"a negative limit is refused rather than inverted",
	ItemCarry.evaluate(request({ Limit = -1 })) == "ITEM_NO_LIMIT_SET"
)

check(
	"an infinite limit is refused, not honoured",
	ItemCarry.evaluate(request({ Limit = math.huge })) == "ITEM_NO_LIMIT_SET"
)

check(
	"a NaN limit is refused",
	ItemCarry.evaluate(request({ Limit = 0 / 0 })) == "ITEM_NO_LIMIT_SET"
)

--[[
	THE REPLACEMENT FOR C13's NaN-CARRIED GUARD.

	That guard existed because `Carried` was a running integer and arithmetic can reach NaN. `Held`
	is an optional string assigned from `SearchService.ItemFound`, so occupancy is provably 0 or 1
	and there is nothing left to poison. Rather than trust that sentence, assert its consequence
	over the whole grid: inside ACTIVE/ALIVE with a sane limit, OK happens if and only if the hand
	is empty. A regression that reintroduced arithmetic here would break this, whatever it computed.
]]
do
	--[[
		WRAPPED IN A RECORD RATHER THAN LISTED AS A BARE `nil` FIRST ELEMENT, and this is not style.
		`for _, held in { nil, "SALT", "BAWANG", "BUNTOT_PAGI" }` iterates THREE times, not four:
		generalized iteration skips the nil at index 1 entirely, so the empty-hand row — the only row
		that can produce OK — is never evaluated and the "if and only if" below proves one direction
		while reading as though it proved both. Measured, not assumed: a probe of that exact literal
		printed `iterations = 3`.
	]]
	local hands: { { Held: ItemType? } } = {
		{ Held = nil },
		{ Held = "SALT" },
		{ Held = "BAWANG" },
		{ Held = "BUNTOT_PAGI" },
	}

	local wrong = 0
	local cells = 0

	for _, hand in hands do
		for _, incoming in ITEMS do
			local verdict = ItemCarry.evaluate(request({ Held = hand.Held, Incoming = incoming }))
			local emptyHanded = hand.Held == nil
			cells += 1

			if (verdict == "OK") ~= emptyHanded then
				wrong += 1
			end
		end
	end

	check("OK happens if and only if the hand is empty", wrong == 0, `{wrong} disagreeing cells`)

	-- The grid actually ran. Without this, a loop that iterated zero times passes the line above.
	check("that property covered all 12 cells", cells == 12, `{cells} cells`)
end

--------------------------------------------------------------------------------
-- Precedence. The order is part of the contract: world, then player, then slot.
--------------------------------------------------------------------------------

check(
	"phase outranks state",
	ItemCarry.evaluate(request({ Phase = "IDLE", PlayerState = "DEAD" })) == "ITEM_WRONG_PHASE"
)

check(
	"state outranks the slot",
	ItemCarry.evaluate(request({ PlayerState = "DEAD", Held = "SALT", Limit = 1 }))
		== "ITEM_NOT_ALIVE"
)

check(
	"the limit guard outranks the slot",
	ItemCarry.evaluate(request({ Held = "SALT", Limit = 0 })) == "ITEM_NO_LIMIT_SET"
)

--------------------------------------------------------------------------------
-- Purity: the same request twice is the same verdict, and the request is not mutated.
--------------------------------------------------------------------------------

do
	local input = request({ Held = "SALT", Incoming = "BAWANG", Limit = 2 })
	local first = ItemCarry.evaluate(input)
	local second = ItemCarry.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check(
		"evaluate does not mutate its request",
		input.Held == "SALT" and input.Incoming == "BAWANG" and input.Limit == 2
	)
end

if failures > 0 then
	error(`{failures} item-carry assertion(s) failed`, 0)
end

print(`  PASS  item-carry: {checked} assertions over PlayerState x RoundPhase x Held x Incoming`)
