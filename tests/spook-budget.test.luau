--!strict
--[[
	The spook budget (§4.7, C16) — "one per round", as arithmetic.

	This file exists to convert C16's own acceptance criterion — *"second spook attempt refused"* — from
	a human observation needing a running place into a terminal check. The playtest still happens; it
	stops being the only evidence.
]]

local SpookBudget = require("../src/shared/pure/SpookBudget")

type PlayerState = SpookBudget.PlayerState
type RoundPhase = SpookBudget.RoundPhase

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

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

local function request(overrides: {
	Phase: RoundPhase?,
	PlayerState: PlayerState?,
	Used: number?,
	Allowance: number?,
}): SpookBudget.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		PlayerState = overrides.PlayerState or "GHOST",
		Used = overrides.Used or 0,
		Allowance = overrides.Allowance or 1,
	}
end

--------------------------------------------------------------------------------
-- C16's acceptance criterion.
--------------------------------------------------------------------------------

check("a ghost's first spook is allowed", SpookBudget.evaluate(request({ Used = 0 })) == "OK")

check(
	"a ghost's SECOND spook is refused",
	SpookBudget.evaluate(request({ Used = 1, Allowance = 1 })) == "NO_SPOOKS_LEFT",
	"this is C16's Verify line, as arithmetic"
)

--------------------------------------------------------------------------------
-- The full PHASE x STATE grid. 20 cells, one OK.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local got = SpookBudget.evaluate(request({ Phase = phase, PlayerState = state }))

		local expected: SpookBudget.Verdict = if phase ~= "ACTIVE"
			then "WRONG_PHASE"
			elseif state ~= "GHOST" then "NOT_GHOST"
			else "OK"

		check(`{phase} x {state} is {expected}`, got == expected, `got {got}`)
	end
end

--[[
	THE ONLY ALLOWLIST IN THIS REPO THAT EXCLUDES ALIVE, asserted as a property. A living player
	spooking would be a living player producing a ghost's effect, which is a channel §4.7 does not
	have and did not ask for.
]]
do
	local permitted = 0

	for _, state in STATES do
		if SpookBudget.evaluate(request({ PlayerState = state })) == "OK" then
			permitted += 1
		end
	end

	check("exactly one PlayerState may spook", permitted == 1, `{permitted} permitted`)
end

check(
	"a living player may not spook",
	SpookBudget.evaluate(request({ PlayerState = "ALIVE" })) == "NOT_GHOST"
)

--------------------------------------------------------------------------------
-- Degenerate allowances. `math.huge` is the one that deletes the rule rather than raising it.
--------------------------------------------------------------------------------

check(
	"a zero allowance refuses",
	SpookBudget.evaluate(request({ Allowance = 0 })) == "NO_SPOOKS_LEFT"
)

check(
	"a negative allowance refuses rather than inverting",
	SpookBudget.evaluate(request({ Allowance = -1 })) == "NO_SPOOKS_LEFT"
)

check(
	"an INFINITE allowance refuses — it would delete the limit, not raise it",
	SpookBudget.evaluate(request({ Allowance = math.huge })) == "NO_SPOOKS_LEFT"
)

check(
	"a NaN allowance refuses",
	SpookBudget.evaluate(request({ Allowance = 0 / 0 })) == "NO_SPOOKS_LEFT"
)

check(
	"a NaN used-count refuses rather than being rewarded",
	SpookBudget.evaluate(request({ Used = 0 / 0 })) == "NO_SPOOKS_LEFT"
)

check(
	"an infinite used-count refuses",
	SpookBudget.evaluate(request({ Used = math.huge })) == "NO_SPOOKS_LEFT"
)

check(
	"a negative used-count refuses",
	SpookBudget.evaluate(request({ Used = -1 })) == "NO_SPOOKS_LEFT"
)

--------------------------------------------------------------------------------
-- A larger allowance behaves, in case M12 tunes it.
--------------------------------------------------------------------------------

check("2 of 3 is allowed", SpookBudget.evaluate(request({ Used = 2, Allowance = 3 })) == "OK")
check(
	"3 of 3 is refused",
	SpookBudget.evaluate(request({ Used = 3, Allowance = 3 })) == "NO_SPOOKS_LEFT"
)

--------------------------------------------------------------------------------
-- Precedence and purity.
--------------------------------------------------------------------------------

check(
	"phase outranks everything",
	SpookBudget.evaluate(request({ Phase = "IDLE", PlayerState = "ALIVE", Used = 9 }))
		== "WRONG_PHASE"
)

check(
	"state outranks the budget",
	SpookBudget.evaluate(request({ PlayerState = "ALIVE", Used = 9 })) == "NOT_GHOST"
)

do
	local input = request({ Used = 0, Allowance = 1 })
	local first = SpookBudget.evaluate(input)
	local second = SpookBudget.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check("evaluate does not mutate its request", input.Used == 0 and input.Allowance == 1)
end

if failures > 0 then
	error(`{failures} spook-budget assertion(s) failed`, 0)
end

print(`  PASS  spook-budget: {checked} assertions over the phase x state grid and the budget`)
