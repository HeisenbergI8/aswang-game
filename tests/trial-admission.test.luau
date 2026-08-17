--!strict
--[[
	The Solo Trial's mutual-exclusion rule, proven exhaustively.

	This suite is the plan's central architectural claim made falsifiable. C21's row names the risk in
	one sentence — "TrialService and RoundService sharing state is how you get a trial that ends a live
	round" — and the rule that prevents it is a predicate small enough to walk in full: five phases ×
	in-trial × three population positions × enabled, which is sixty cells.

	The properties at the bottom carry the weight. A cell table can be satisfied by accident after an
	edit; a property stating "for every non-IDLE phase, evaluate never returns OK" cannot.
]]

local TrialAdmission = require("../src/shared/pure/TrialAdmission")

type RoundPhase = TrialAdmission.RoundPhase
type TrialStartVerdict = TrialAdmission.TrialStartVerdict
type Input = TrialAdmission.Input

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

-- The threshold every case is written against. Mirrors Config.Trial.OfferBelowPlayerCount == 3, whose
-- equality with Round.MinPlayers is pinned separately in tests/config.test.luau.
local THRESHOLD = 3

local ALL_PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
local BOOLS = { true, false }

local function input(over: {
	Enabled: boolean?,
	RoundPhase: RoundPhase?,
	PlayerCount: number?,
	AlreadyInTrial: boolean?,
}): Input
	return {
		Enabled = if over.Enabled == nil then true else over.Enabled,
		RoundPhase = over.RoundPhase or "IDLE",
		PlayerCount = over.PlayerCount or 1,
		OfferBelowPlayerCount = THRESHOLD,
		AlreadyInTrial = over.AlreadyInTrial == true,
	}
end

--------------------------------------------------------------------------------
-- The full table — every phase × in-trial × below/at/above the threshold
--------------------------------------------------------------------------------

type Case = {
	phase: RoundPhase,
	inTrial: boolean,
	count: number,
	expected: TrialStartVerdict,
}

local CASES: { Case } = {
	-- IDLE, not already in one. The only phase that can ever answer OK, and population decides.
	{ phase = "IDLE", inTrial = false, count = 1, expected = "OK" },
	{ phase = "IDLE", inTrial = false, count = 2, expected = "OK" },
	{ phase = "IDLE", inTrial = false, count = 3, expected = "TOO_MANY_PLAYERS" },
	{ phase = "IDLE", inTrial = false, count = 8, expected = "TOO_MANY_PLAYERS" },

	-- IDLE, already in one. ALREADY_IN_TRIAL outranks population — a player mid-trial is told the
	-- durable thing, not a headcount that changes every few seconds.
	{ phase = "IDLE", inTrial = true, count = 1, expected = "ALREADY_IN_TRIAL" },
	{ phase = "IDLE", inTrial = true, count = 3, expected = "ALREADY_IN_TRIAL" },

	-- Every non-IDLE phase refuses, at every population. These sixteen cells ARE the mutual exclusion.
	{ phase = "INTERMISSION", inTrial = false, count = 1, expected = "ROUND_NOT_IDLE" },
	{ phase = "INTERMISSION", inTrial = false, count = 3, expected = "ROUND_NOT_IDLE" },
	{ phase = "STARTING", inTrial = false, count = 1, expected = "ROUND_NOT_IDLE" },
	{ phase = "STARTING", inTrial = false, count = 3, expected = "ROUND_NOT_IDLE" },
	{ phase = "ACTIVE", inTrial = false, count = 1, expected = "ROUND_NOT_IDLE" },
	{ phase = "ACTIVE", inTrial = false, count = 3, expected = "ROUND_NOT_IDLE" },
	{ phase = "ENDING", inTrial = false, count = 1, expected = "ROUND_NOT_IDLE" },
	{ phase = "ENDING", inTrial = false, count = 3, expected = "ROUND_NOT_IDLE" },

	-- Non-IDLE and already in one: ALREADY_IN_TRIAL still outranks, because it is checked first and
	-- is the more actionable statement. `mustEnd` is what actually closes that session, not this.
	{ phase = "ACTIVE", inTrial = true, count = 1, expected = "ALREADY_IN_TRIAL" },
	{ phase = "ENDING", inTrial = true, count = 8, expected = "ALREADY_IN_TRIAL" },
}

for _, case in CASES do
	local verdict = TrialAdmission.evaluate(input({
		RoundPhase = case.phase,
		PlayerCount = case.count,
		AlreadyInTrial = case.inTrial,
	}))

	check(
		`{case.phase} · inTrial={case.inTrial} · {case.count} players -> {case.expected}`,
		verdict == case.expected,
		`got {verdict}`
	)
end

--------------------------------------------------------------------------------
-- DISABLED outranks everything, from every cell above
--------------------------------------------------------------------------------

for _, phase in ALL_PHASES do
	for _, inTrial in BOOLS do
		for _, count in { 1, 2, 3, 8 } do
			local verdict = TrialAdmission.evaluate(input({
				Enabled = false,
				RoundPhase = phase,
				PlayerCount = count,
				AlreadyInTrial = inTrial,
			}))

			check(
				`Enabled=false -> DISABLED at {phase} · inTrial={inTrial} · {count}`,
				verdict == "DISABLED",
				`got {verdict}`
			)
		end
	end
end

--------------------------------------------------------------------------------
-- The exact boundary. `OfferBelowPlayerCount` means strictly below, and the two gates must
-- partition the headcount line with no value on both sides of it.
--------------------------------------------------------------------------------

check(
	`one below the threshold is OK`,
	TrialAdmission.evaluate(input({ PlayerCount = THRESHOLD - 1 })) == "OK"
)

check(
	`exactly the threshold is TOO_MANY_PLAYERS`,
	TrialAdmission.evaluate(input({ PlayerCount = THRESHOLD })) == "TOO_MANY_PLAYERS"
)

--------------------------------------------------------------------------------
-- The properties. These are the plan's thesis, stated so a future edit cannot satisfy the
-- table above by accident while breaking the rule the table exists to express.
--------------------------------------------------------------------------------

-- PROPERTY 1 — the one that matters. No non-IDLE phase can ever open a trial, and every non-IDLE
-- phase closes a live one. If this fails, a trial can run alongside a round.
for _, phase in ALL_PHASES do
	if phase == "IDLE" then
		continue
	end

	for _, inTrial in BOOLS do
		for _, count in { 0, 1, 2, 3, 8 } do
			for _, enabled in BOOLS do
				local verdict = TrialAdmission.evaluate(input({
					Enabled = enabled,
					RoundPhase = phase,
					PlayerCount = count,
					AlreadyInTrial = inTrial,
				}))

				check(`{phase} never opens a trial`, verdict ~= "OK", `got {verdict}`)
			end
		end
	end

	check(`{phase} closes a live trial`, TrialAdmission.mustEnd(phase) == true)
end

-- PROPERTY 2 — IDLE is the only phase that does NOT close a live session. A trial that died on its
-- own opening phase would be a tutorial nobody could finish.
check(`IDLE does not close a live trial`, TrialAdmission.mustEnd("IDLE") == false)

--[[
	PROPERTY 3 — `mustEnd` IS NOT `evaluate ~= "OK"`, and this is the cell that proves the two
	predicates are genuinely different rather than one wrapping the other.

	At IDLE with the population at the threshold, a NEW session is refused (TOO_MANY_PLAYERS) while a
	RUNNING one survives (mustEnd false). Conflating them would kill a player's trial the moment a
	third player joined, before any round had actually started — a tutorial that ends on an event
	that changed nothing.
]]
check(
	`at IDLE and at the threshold, opening is refused`,
	TrialAdmission.evaluate(input({ PlayerCount = THRESHOLD })) == "TOO_MANY_PLAYERS"
)

check(`...but a running session survives it`, TrialAdmission.mustEnd("IDLE") == false)

-- PROPERTY 4 — purity. The same input twice gives the same answer, and the input is not mutated.
local probe = input({ RoundPhase = "IDLE", PlayerCount = 2 })
local first = TrialAdmission.evaluate(probe)
local second = TrialAdmission.evaluate(probe)

check(`evaluate is deterministic`, first == second)
check(`evaluate does not mutate its input`, probe.PlayerCount == 2 and probe.RoundPhase == "IDLE")

if failures > 0 then
	error(`{failures} trial-admission failure(s)`, 0)
end

-- Counted, not typed — see the note at the bottom of tests/config.test.luau. A suite that reports the
-- same total whatever it contains cannot tell you an assertion was dropped.
print(`  PASS  trial-admission: {checked} assertions over {#CASES} cells and the properties`)
