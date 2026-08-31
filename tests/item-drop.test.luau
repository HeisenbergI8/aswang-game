--!strict
--[[
	The drop rule (§4.6, V08) over the full phase x state grid and both slot states.

	SMALL, BUT NOT SKIPPABLE. The drop is the only way a living player empties a slot without using
	the item, so a rule that is wrong here either strands the buntot pagi in a dead player's hand or
	lets it be dropped twice. Both are silent, and one of them duplicates the win condition.
]]

local ItemDrop = require("../src/shared/pure/ItemDrop")

type PlayerState = ItemDrop.PlayerState
type RoundPhase = ItemDrop.RoundPhase
type ItemType = ItemDrop.ItemType

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
local ITEMS: { ItemType } = { "SALT", "BAWANG", "BUNTOT_PAGI" }

-- The full grid, with something in hand. 20 cells, exactly one OK.
for _, phase in PHASES do
	for _, state in STATES do
		local verdict = ItemDrop.evaluate({ Phase = phase, PlayerState = state, Held = "SALT" })

		local expected: ItemDrop.Verdict = if phase ~= "ACTIVE"
			then "ITEM_WRONG_PHASE"
			elseif state ~= "ALIVE" then "ITEM_NOT_ALIVE"
			else "OK"

		check(`{phase} x {state} is {expected}`, verdict == expected, `got {verdict}`)
	end
end

do
	local permitted = 0

	for _, state in STATES do
		if ItemDrop.evaluate({ Phase = "ACTIVE", PlayerState = state, Held = "SALT" }) == "OK" then
			permitted += 1
		end
	end

	check("exactly one PlayerState may drop", permitted == 1, `{permitted} permitted`)
end

-- An empty hand, at the one phase/state where everything else would have said OK.
check(
	"an empty hand has nothing to drop",
	ItemDrop.evaluate({ Phase = "ACTIVE", PlayerState = "ALIVE", Held = nil })
		== "ITEM_NOTHING_HELD"
)

--[[
	ITEM-TYPE BLINDNESS, as a property. The drop must not care WHICH item it is — a rule that
	refused to drop the buntot pagi would be defensible-sounding and wrong: §4.6 requires it to be
	"dropped, passed, and picked up from a body", and a carrier who cannot put it down cannot pass it.
]]
do
	local seen: { [string]: boolean } = {}

	for _, item in ITEMS do
		seen[ItemDrop.evaluate({ Phase = "ACTIVE", PlayerState = "ALIVE", Held = item })] = true
	end

	local distinct = 0
	for _ in seen do
		distinct += 1
	end

	check("every item type drops identically", distinct == 1, `{distinct} verdicts`)
	check(
		"and that one verdict is OK",
		ItemDrop.evaluate({ Phase = "ACTIVE", PlayerState = "ALIVE", Held = "BUNTOT_PAGI" }) == "OK"
	)
end

-- Precedence: world, then player, then slot.
check(
	"phase outranks state",
	ItemDrop.evaluate({ Phase = "IDLE", PlayerState = "DEAD", Held = nil }) == "ITEM_WRONG_PHASE"
)

check(
	"state outranks the empty slot",
	ItemDrop.evaluate({ Phase = "ACTIVE", PlayerState = "DEAD", Held = nil }) == "ITEM_NOT_ALIVE"
)

if failures > 0 then
	error(`{failures} item-drop assertion(s) failed`, 0)
end

print(`  PASS  item-drop: {checked} assertions over the phase x state grid and the slot`)
