--!strict
--[[
	The salt carry rule (§4.6, C13), over every player state and both sides of the limit.

	The cell this file exists for is GHOST. `SaltCarry.evaluate` uses an allowlist of ALIVE, and the
	denylist form (`~= "SPECTATOR"`) is identical in behaviour TODAY and wrong the moment C15 gives a
	ghost a body to walk over a pouch with. That is `pure/PlayerBody`'s warning arriving in a second
	file, and this grid is what makes it fail here rather than in a playtest six chunks later.

	It also converts C13's acceptance criterion — "picks up two in a row and is refused the second" —
	from a human observation needing a running place into arithmetic that runs in milliseconds. The
	playtest still happens; it stops being the ONLY evidence.
]]

local SaltCarry = require("../src/shared/pure/SaltCarry")

type PlayerState = SaltCarry.PlayerState
type RoundPhase = SaltCarry.RoundPhase

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
	Carried: number?,
	Limit: number?,
}): SaltCarry.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		PlayerState = overrides.PlayerState or "ALIVE",
		Carried = overrides.Carried or 0,
		Limit = overrides.Limit or 1,
	}
end

--------------------------------------------------------------------------------
-- The full PHASE × STATE grid. 20 cells, and exactly one of them says OK.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local verdict = SaltCarry.evaluate(request({ Phase = phase, PlayerState = state }))

		local expected: SaltCarry.Verdict = if phase ~= "ACTIVE"
			then "WRONG_PHASE"
			elseif state ~= "ALIVE" then "NOT_ALIVE"
			else "OK"

		check(`{phase} x {state} is {expected}`, verdict == expected, `got {verdict}`)
	end
end

--[[
	The allowlist, asserted as a PROPERTY rather than as four cells: exactly one state may ever carry.
	A denylist rewrite that admitted GHOST would keep every cell above passing if someone "fixed" the
	expectation table to match, and would fail here.
]]
do
	local permitted = 0

	for _, state in STATES do
		if SaltCarry.evaluate(request({ PlayerState = state })) == "OK" then
			permitted += 1
		end
	end

	check(
		"exactly one PlayerState may pick up salt",
		permitted == 1,
		`{permitted} states permitted`
	)
end

--------------------------------------------------------------------------------
-- The carry boundary. This is C13's "refused the second" in arithmetic.
--------------------------------------------------------------------------------

check("empty-handed is OK", SaltCarry.evaluate(request({ Carried = 0 })) == "OK")

check(
	"carrying one at a limit of one is refused",
	SaltCarry.evaluate(request({ Carried = 1, Limit = 1 })) == "AT_LIMIT"
)

check(
	"carrying more than the limit is refused",
	SaltCarry.evaluate(request({ Carried = 5, Limit = 1 })) == "AT_LIMIT"
)

check(
	"a limit of two admits the second pouch",
	SaltCarry.evaluate(request({ Carried = 1, Limit = 2 })) == "OK"
)

check(
	"a limit of two refuses the third",
	SaltCarry.evaluate(request({ Carried = 2, Limit = 2 })) == "AT_LIMIT"
)

--------------------------------------------------------------------------------
-- Degenerate limits. The guard fails CLOSED, and `math.huge` is the dangerous one:
-- `Carried < inf` is always true, so an infinite limit silently deletes the rule.
--------------------------------------------------------------------------------

check("a zero limit carries nothing", SaltCarry.evaluate(request({ Limit = 0 })) == "NO_LIMIT_SET")

check(
	"a negative limit is refused rather than inverted",
	SaltCarry.evaluate(request({ Limit = -1 })) == "NO_LIMIT_SET"
)

check(
	"an infinite limit is refused, not honoured",
	SaltCarry.evaluate(request({ Limit = math.huge })) == "NO_LIMIT_SET"
)

check("a NaN limit is refused", SaltCarry.evaluate(request({ Limit = 0 / 0 })) == "NO_LIMIT_SET")

--[[
	A NaN CARRIED is a separate hole from a NaN limit and the module closes it separately. `NaN >= 1` is
	false, so the AT_LIMIT comparison alone would fall through and hand out a pouch. Asserted here
	because the two guards are not symmetric and a reader would reasonably assume they were.
]]
check(
	"a NaN carried count is refused rather than rewarded",
	SaltCarry.evaluate(request({ Carried = 0 / 0 })) == "AT_LIMIT"
)

check(
	"an infinite carried count is refused",
	SaltCarry.evaluate(request({ Carried = math.huge })) == "AT_LIMIT"
)

check(
	"a negative carried count is refused",
	SaltCarry.evaluate(request({ Carried = -1 })) == "AT_LIMIT"
)

--------------------------------------------------------------------------------
-- Precedence. The order is part of the contract: world, then player, then count.
--------------------------------------------------------------------------------

check(
	"phase outranks state",
	SaltCarry.evaluate(request({ Phase = "IDLE", PlayerState = "GHOST" })) == "WRONG_PHASE"
)

check(
	"state outranks the limit",
	SaltCarry.evaluate(request({ PlayerState = "GHOST", Carried = 9, Limit = 1 })) == "NOT_ALIVE"
)

check(
	"the limit guard outranks the carried count",
	SaltCarry.evaluate(request({ Carried = 9, Limit = 0 })) == "NO_LIMIT_SET"
)

--------------------------------------------------------------------------------
-- Purity: the same request twice is the same verdict, and the request is not mutated.
--------------------------------------------------------------------------------

do
	local input = request({ Carried = 1, Limit = 2 })
	local first = SaltCarry.evaluate(input)
	local second = SaltCarry.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check("evaluate does not mutate its request", input.Carried == 1 and input.Limit == 2)
end

if failures > 0 then
	error(`{failures} salt-carry assertion(s) failed`, 0)
end

print(`  PASS  salt-carry: {checked} assertions over the full PlayerState x RoundPhase grid`)
