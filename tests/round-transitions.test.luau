--!strict
--[[
	The round state machine, proven exhaustively.

	Five phases × expired × enoughPlayers is twenty cases — small enough to write out in full, which
	is worth far more than a handful of spot checks. Every cell below is a decision someone can argue
	with; a spot check only tells you the cells somebody happened to think of.

	The invariants at the bottom are the ones spec §6.4 actually cares about, restated as properties
	rather than cells, so that a future edit cannot satisfy the cells by accident while breaking the
	rule they exist to express.
]]

local RoundTransitions = require("../src/shared/pure/RoundTransitions")

type RoundPhase = RoundTransitions.RoundPhase

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

--------------------------------------------------------------------------------
-- The full table
--------------------------------------------------------------------------------

type Case = {
	phase: RoundPhase,
	expired: boolean,
	enough: boolean,
	expected: RoundPhase?,
}

local CASES: { Case } = {
	-- IDLE — nothing is running, so only headcount matters. There is no timer to expire.
	{ phase = "IDLE", expired = false, enough = false, expected = nil },
	{ phase = "IDLE", expired = false, enough = true, expected = "INTERMISSION" },
	{ phase = "IDLE", expired = true, enough = false, expected = nil },
	{ phase = "IDLE", expired = true, enough = true, expected = "INTERMISSION" },

	-- INTERMISSION — headcount is read BEFORE the countdown, so a lobby that collapses drops back
	-- to IDLE rather than starting a round that cannot be played.
	{ phase = "INTERMISSION", expired = false, enough = false, expected = "IDLE" },
	{ phase = "INTERMISSION", expired = false, enough = true, expected = nil },
	{ phase = "INTERMISSION", expired = true, enough = false, expected = "IDLE" },
	{ phase = "INTERMISSION", expired = true, enough = true, expected = "STARTING" },

	-- STARTING — roles are being drawn. Uninterruptible: a player leaving between the draw and
	-- ACTIVE must not rewind a round that has already picked its Aswang.
	{ phase = "STARTING", expired = false, enough = false, expected = nil },
	{ phase = "STARTING", expired = false, enough = true, expected = nil },
	{ phase = "STARTING", expired = true, enough = false, expected = "ACTIVE" },
	{ phase = "STARTING", expired = true, enough = true, expected = "ACTIVE" },

	-- ACTIVE — spec §6.4: a round that drops below MinPlayers FINISHES, then returns to IDLE.
	{ phase = "ACTIVE", expired = false, enough = false, expected = nil },
	{ phase = "ACTIVE", expired = false, enough = true, expected = nil },
	{ phase = "ACTIVE", expired = true, enough = false, expected = "ENDING" },
	{ phase = "ACTIVE", expired = true, enough = true, expected = "ENDING" },

	-- ENDING — the reveal plays in full, and only then does the headcount decide whether there is
	-- another round or the server goes quiet.
	{ phase = "ENDING", expired = false, enough = false, expected = nil },
	{ phase = "ENDING", expired = false, enough = true, expected = nil },
	{ phase = "ENDING", expired = true, enough = false, expected = "IDLE" },
	{ phase = "ENDING", expired = true, enough = true, expected = "INTERMISSION" },
}

check("all 20 phase/expired/headcount combinations are covered", #CASES == 20, `got {#CASES}`)

for _, case in CASES do
	local actual = RoundTransitions.next(case.phase, case.expired, case.enough)

	check(
		`{case.phase} (expired={case.expired}, enough={case.enough}) -> {case.expected or "stay"}`,
		actual == case.expected,
		`got {actual or "stay"}`
	)
end

--------------------------------------------------------------------------------
-- The properties behind the table
--------------------------------------------------------------------------------

local ALL_PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
local BOOLS = { false, true }

-- Spec §6.4: a round in progress finishes. If losing a player could end ACTIVE, quitting becomes a
-- way to void a round you are losing, and every dropped connection reads as an Aswang win. The same
-- reasoning applies one phase earlier, where the Aswang has already been drawn.
for _, phase: RoundPhase in { "STARTING", "ACTIVE" } do
	for _, expired in BOOLS do
		check(
			`{phase} ignores the player count (expired={expired})`,
			RoundTransitions.next(phase, expired, true)
				== RoundTransitions.next(phase, expired, false)
		)
	end
end

-- A transition into the phase you are already in would fire PhaseChanged for a no-op, restart the
-- phase timer, and re-run every subscriber's enter logic. setPhase() guards against it as well;
-- this pins that the table never asks for it in the first place.
for _, phase in ALL_PHASES do
	for _, expired in BOOLS do
		for _, enough in BOOLS do
			check(
				`{phase} never transitions to itself (expired={expired}, enough={enough})`,
				RoundTransitions.next(phase, expired, enough) ~= phase
			)
		end
	end
end

-- Nothing may leave a phase except along an edge the spec §6.4 diagram draws. This catches a stray
-- branch added later far better than re-reading the cells does.
local LEGAL: { [string]: { [string]: boolean } } = {
	IDLE = { INTERMISSION = true },
	INTERMISSION = { IDLE = true, STARTING = true },
	STARTING = { ACTIVE = true },
	ACTIVE = { ENDING = true },
	ENDING = { IDLE = true, INTERMISSION = true },
}

for _, phase in ALL_PHASES do
	for _, expired in BOOLS do
		for _, enough in BOOLS do
			local nextPhase = RoundTransitions.next(phase, expired, enough)

			if nextPhase ~= nil then
				check(
					`{phase} -> {nextPhase} is an edge the spec draws`,
					LEGAL[phase][nextPhase] == true
				)
			end
		end
	end
end

if failures > 0 then
	error(`{failures} round-transition failure(s)`, 0)
end

print(`  PASS  round-transitions: {#CASES} exhaustive cases + 3 invariants`)
