--!strict
--[[
	The bawang placement rule (§4.6, V09), over every phase, every player state, every item type,
	and both sides of the doorway distance.

	THE CELL THIS FILE EXISTS FOR IS ORDER. Five refusals share one entry point and the SERVER'S LOG
	is the only place they are ever distinguishable — nothing is echoed to the caller on any path,
	including OK. So the order is the contract: a dead player holding nothing at no doorway must
	return `GARLIC_NOT_ALIVE`, because that is the first true thing about them. Assert the order
	directly or it drifts the first time somebody reshuffles the guards to read better.

	THE PROPERTY THAT MUST NEVER BREAK IS ROLE-BLINDNESS, and it is asserted structurally rather than
	by a case: the `Request` type has no role field and `evaluate` takes nothing else. §4.4 has the
	Aswang carrying and placing on identical rules, so the monster reaches this module, gets
	`GARLIC_OK`, seals a doorway and is then blocked by its own garlic. A refusal for the monster
	would be an oracle readable by pressing a key.

	`Range` IS GUARDED POSITIVE-AND-FINITE, which is `ItemCarry.Limit`'s guard in a fifth file. A
	`math.huge` range deletes the walk that IS the cost of placing garlic, and no symptom anywhere
	would say so — the game would simply let anyone seal any doorway from where they stand.
]]

local GarlicPlacement = require("../src/shared/pure/GarlicPlacement")

type RoundPhase = GarlicPlacement.RoundPhase
type PlayerState = GarlicPlacement.PlayerState
type ItemType = GarlicPlacement.ItemType
type Request = GarlicPlacement.Request

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

local RANGE = 8

-- The one world in which placement succeeds. Every case below is this, minus one thing.
local function ok(overrides: { [string]: any }?): Request
	local request: Request = {
		Phase = "ACTIVE",
		PlayerState = "ALIVE",
		Held = "BAWANG",
		DoorwayDistance = 3,
		Range = RANGE,
		DoorwayOccupied = false,
	}

	if overrides then
		for key, value in overrides do
			(request :: any)[key] = value
		end
	end

	return request
end

check("the baseline world places garlic", GarlicPlacement.evaluate(ok()) == "GARLIC_OK")

--------------------------------------------------------------------------------
-- PHASE. Placement is an ACTIVE-only act, allowlisted rather than denylisted.
--------------------------------------------------------------------------------

for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } :: { RoundPhase } do
	check(
		`phase {phase} refuses placement`,
		GarlicPlacement.evaluate(ok({ Phase = phase })) == "GARLIC_WRONG_PHASE",
		GarlicPlacement.evaluate(ok({ Phase = phase }))
	)
end

check(
	"phase ACTIVE allows placement",
	GarlicPlacement.evaluate(ok({ Phase = "ACTIVE" })) == "GARLIC_OK"
)

--------------------------------------------------------------------------------
-- PLAYER STATE. An ALLOWLIST of ALIVE — `pure/PlayerBody`'s warning in a sixth file.
--
-- DEAD is the cell that matters. V12 gives the dead a body that stays in the world, and a corpse
-- that can still seal a doorway is a corpse playing the round. `~= "SPECTATOR"` would pass it.
--------------------------------------------------------------------------------

for _, state in { "LOBBY", "DEAD", "SPECTATOR" } :: { PlayerState } do
	check(
		`player state {state} refuses placement`,
		GarlicPlacement.evaluate(ok({ PlayerState = state })) == "GARLIC_NOT_ALIVE",
		GarlicPlacement.evaluate(ok({ PlayerState = state }))
	)
end

--------------------------------------------------------------------------------
-- THE SLOT. Only bawang is placeable; the other two items and the empty hand refuse.
--------------------------------------------------------------------------------

for _, item in { "SALT", "BUNTOT_PAGI" } :: { ItemType } do
	check(
		`holding {item} refuses placement`,
		GarlicPlacement.evaluate(ok({ Held = item })) == "GARLIC_NOT_HELD",
		GarlicPlacement.evaluate(ok({ Held = item }))
	)
end

do
	local empty = ok()
	empty.Held = nil

	check(
		"an empty hand refuses placement",
		GarlicPlacement.evaluate(empty) == "GARLIC_NOT_HELD",
		GarlicPlacement.evaluate(empty)
	)
end

check("holding BAWANG places", GarlicPlacement.evaluate(ok({ Held = "BAWANG" })) == "GARLIC_OK")

--------------------------------------------------------------------------------
-- THE DOORWAY. `nil` is a map fault, a NaN is a corrupt sample, and past `Range` is a UX finding.
-- All three land on the same verdict because none of them is echoed to the client.
--------------------------------------------------------------------------------

do
	local none = ok()
	none.DoorwayDistance = nil

	check(
		"no doorway at all refuses",
		GarlicPlacement.evaluate(none) == "GARLIC_NO_DOORWAY",
		GarlicPlacement.evaluate(none)
	)
end

check(
	"a NaN doorway distance refuses",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = 0 / 0 })) == "GARLIC_NO_DOORWAY"
)

check(
	"a doorway exactly at Range is accepted — the boundary is inclusive",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = RANGE })) == "GARLIC_OK",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = RANGE }))
)

check(
	"a doorway one stud past Range refuses",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = RANGE + 1 })) == "GARLIC_NO_DOORWAY"
)

check(
	"a doorway underfoot is accepted",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = 0 })) == "GARLIC_OK"
)

--------------------------------------------------------------------------------
-- RANGE, FAIL-CLOSED. `ItemCarry.Limit`'s guard: positive and finite, or nothing is placeable.
--
-- `math.huge` is the dangerous direction and the reason this is tested at all — it would let any
-- player seal any doorway on the map from where they stand, silently.
--------------------------------------------------------------------------------

for _, range in { 0, -1, 0 / 0, math.huge } do
	check(
		`a Range of {range} refuses placement`,
		GarlicPlacement.evaluate(ok({ Range = range })) == "GARLIC_NO_DOORWAY",
		GarlicPlacement.evaluate(ok({ Range = range }))
	)
end

--------------------------------------------------------------------------------
-- OCCUPANCY. Two bawang on one doorway would deny it for 30s from a supply of two — the safe room
-- §3 forbids, assembled by accident rather than by design.
--------------------------------------------------------------------------------

check(
	"a doorway that already carries garlic refuses",
	GarlicPlacement.evaluate(ok({ DoorwayOccupied = true })) == "GARLIC_DOORWAY_TAKEN",
	GarlicPlacement.evaluate(ok({ DoorwayOccupied = true }))
)

--------------------------------------------------------------------------------
-- ORDER. The five refusals are ranked, and the rank is what makes the server's log readable.
-- Each case below is true of MORE THAN ONE guard and must return the FIRST.
--------------------------------------------------------------------------------

check(
	"a dead player holding nothing at no doorway reports NOT_ALIVE, not NOT_HELD",
	GarlicPlacement.evaluate({
		Phase = "ACTIVE",
		PlayerState = "DEAD",
		Held = nil,
		DoorwayDistance = nil,
		Range = RANGE,
		DoorwayOccupied = true,
	}) == "GARLIC_NOT_ALIVE"
)

check("the wrong phase outranks every other fault", GarlicPlacement.evaluate({
	Phase = "ENDING",
	PlayerState = "DEAD",
	Held = "SALT",
	DoorwayDistance = nil,
	Range = 0,
	DoorwayOccupied = true,
}) == "GARLIC_WRONG_PHASE")

check(
	"an empty hand at an occupied doorway reports NOT_HELD, not DOORWAY_TAKEN",
	GarlicPlacement.evaluate({
		Phase = "ACTIVE",
		PlayerState = "ALIVE",
		Held = nil,
		DoorwayDistance = 1,
		Range = RANGE,
		DoorwayOccupied = true,
	}) == "GARLIC_NOT_HELD"
)

check(
	"being out of range outranks the doorway being taken",
	GarlicPlacement.evaluate(ok({ DoorwayDistance = RANGE + 1, DoorwayOccupied = true }))
		== "GARLIC_NO_DOORWAY"
)

--------------------------------------------------------------------------------
-- PURITY. Same input, same answer; and the request is not written through.
--------------------------------------------------------------------------------

do
	local input = ok({ DoorwayDistance = 5 })
	local first = GarlicPlacement.evaluate(input)
	local second = GarlicPlacement.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check(
		"evaluate does not mutate its request",
		input.Phase == "ACTIVE"
			and input.PlayerState == "ALIVE"
			and input.Held == "BAWANG"
			and input.DoorwayDistance == 5
			and input.Range == RANGE
			and input.DoorwayOccupied == false
	)
end

if failures > 0 then
	error(`{failures} garlic-placement assertion(s) failed`, 0)
end

print(`  PASS  garlic-placement: {checked} assertions over Phase x PlayerState x Held x Doorway`)
