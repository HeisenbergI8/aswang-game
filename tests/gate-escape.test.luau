--!strict
--[[
	tests/gate-escape.test.luau

	`server/pure/GateEscape.luau` over its entire domain — 64 cells.

	TWO ASSERTIONS PER CELL, AND THE SECOND IS THE 🔒 ONE. The first checks the cell against the rule.
	The second is a standing property: the Aswang never escapes, in any state, at any distance,
	through any gate. It is separated out because it is the sentence a future edit will be arguing
	with, and a property stated once is easier to defend than one implied by a table.
]]

local GateEscape = require("../src/server/pure/GateEscape")

local STATES: { GateEscape.PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local ROLES: { GateEscape.Role } = { "SURVIVOR", "ASWANG" }
local OPENS = { false, true }

local RANGE = 6
local DISTANCES = { 0, RANGE, RANGE + 1, 400 }

local failures = 0
local assertions = 0

local function check(label: string, ok: boolean, detail: string?)
	assertions += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

for _, open in OPENS do
	for _, state in STATES do
		for _, role in ROLES do
			for _, distance in DISTANCES do
				local request = {
					GateOpen = open,
					PlayerState = state,
					Role = role,
					Distance = distance,
					Range = RANGE,
				}
				local expected = open
					and role == "SURVIVOR"
					and state == "ALIVE"
					and distance <= RANGE

				check(
					`open={open} {state}/{role} at {distance} studs`,
					GateEscape.escapes(request) == expected,
					`got {GateEscape.escapes(request)}`
				)

				--[[
					🔒 §4.8. The Aswang wins by kills or by the clock — never by walking out of the
					map. Asserted in EVERY cell rather than once, so there is no combination of state,
					distance and gate condition where it holds only by accident.
				]]
				if role == "ASWANG" then
					check(
						`the Aswang never escapes (open={open}, {state}, {distance} studs)`,
						not GateEscape.escapes(request)
					)
				end
			end
		end
	end
end

-- The boundary, by name: `<=` means standing exactly at GateRangeStuds counts. A `<` here would make
-- the gate a stud smaller than Config says, which is the kind of drift nobody measures in play.
check(
	"exactly at the range limit still escapes",
	GateEscape.escapes({
		GateOpen = true,
		PlayerState = "ALIVE",
		Role = "SURVIVOR",
		Distance = RANGE,
		Range = RANGE,
	})
)

check("a ghost standing in an open gate does not win the round", not GateEscape.escapes({
	GateOpen = true,
	PlayerState = "GHOST",
	Role = "SURVIVOR",
	Distance = 0,
	Range = RANGE,
}))

check("a shut gate ends nothing", not GateEscape.escapes({
	GateOpen = false,
	PlayerState = "ALIVE",
	Role = "SURVIVOR",
	Distance = 0,
	Range = RANGE,
}))

if failures > 0 then
	error(`{failures} gate-escape failure(s)`, 0)
end

print(`  PASS  gate-escape: {assertions} assertions over the full 64-cell grid`)
