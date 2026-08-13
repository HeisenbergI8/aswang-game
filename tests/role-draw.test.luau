--!strict
--[[
	tests/role-draw.test.luau

	The one decision the whole game rests on, proven over ten thousand rounds.

	C03's Verify line asks for two numbers, and they pull in OPPOSITE directions — that is why both are
	required and why either alone is misleading:

	  · back-to-back Aswang rate BELOW the unweighted baseline  — the anti-repeat actually works
	  · every player eventually eligible                        — it did not work by banning people

	A draw that excluded the last Aswang outright would ace the first and fail the second, and would
	feel fine for two rounds before a player noticed they were never the monster on a full server.

	LUNE HAS NO `Random`. That is a feature here: the module takes an injected `nextFloat`, so the test
	supplies a Park–Miller LCG and gets exact reproducibility, while RoleService supplies
	`Random.new()` — no argument, server-only entropy — and gets a draw nobody can replay.
]]

local Config = require("../src/shared/Config")
local RoleDraw = require("../src/server/pure/RoleDraw")

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

--[[
	Park–Miller minimal standard. Deterministic, and every intermediate value stays exactly
	representable in a float64, so this produces identical streams on every machine.

	THE WARM-UP IS NOT DECORATION. Park–Miller's first output is `seed * 16807 / 2^31`, so a small seed
	produces a tiny first float: seed 1 yields 0.0000078, seed 50 yields 0.00039. Feed those into a
	weighted draw and every one of them rolls into the bottom of the cumulative range and picks the SAME
	candidate — which is exactly how the "different streams can draw different Aswangs" check below
	failed on first run, against a draw that was working correctly.

	Discarding the first few outputs decorrelates the stream from the seed. Without it this file reports
	a bug in RoleDraw that does not exist, and — worse in the other direction — a real draw that ignored
	`nextFloat` entirely would still pass, because the smoke test it defeats is the one written to catch
	precisely that.
]]
local RNG_WARMUP = 10

local function makeRng(seed: number): () -> number
	local state = seed % 2147483647

	if state <= 0 then
		state += 2147483646
	end

	local function nextFloat(): number
		state = (state * 16807) % 2147483647

		return (state - 1) / 2147483646
	end

	for _ = 1, RNG_WARMUP do
		nextFloat()
	end

	return nextFloat
end

-- The real weights, so this test fails when someone tunes them past the point of working.
local WEIGHTS: RoleDraw.Weights = {
	Base = Config.Roles.BaseWeight,
	Recent = Config.Roles.RecentAswangWeight,
	Older = Config.Roles.OlderAswangWeight,
	HistoryRounds = Config.Roles.RepeatCooldownRounds,
}

local PLAYERS = { 101, 102, 103, 104, 105, 106, 107, 108 }

local function aswangIn(assignments: { [number]: RoleDraw.Role }): number?
	for userId, role in assignments do
		if role == "ASWANG" then
			return userId
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Shape: exactly one Aswang, everyone else a survivor, nobody missing
--------------------------------------------------------------------------------

do
	local assignments = RoleDraw.draw(PLAYERS, {}, Config.Roles.AswangCount, WEIGHTS, makeRng(1))
	local aswangs = 0
	local assigned = 0

	for _, userId in PLAYERS do
		local role = assignments[userId]

		check(`player {userId} was assigned a role`, role ~= nil)

		if role ~= nil then
			assigned += 1
		end

		if role == "ASWANG" then
			aswangs += 1
		end
	end

	check("everyone in the round got a role", assigned == #PLAYERS, `{assigned}/{#PLAYERS}`)
	check("exactly AswangCount monsters", aswangs == Config.Roles.AswangCount, `{aswangs}`)
end

--------------------------------------------------------------------------------
-- Determinism: the property that makes the 10,000-round simulation meaningful
--------------------------------------------------------------------------------

do
	local first = RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(42))
	local again = RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(42))

	check("the same stream draws the same Aswang", aswangIn(first) == aswangIn(again))

	-- Not a correctness property — a smoke test that the stream is CONSULTED at all. A draw that
	-- ignored nextFloat and returned candidates[1] would pass every other assertion in this file.
	local differed = false

	for seed = 1, 50 do
		if aswangIn(RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(seed))) ~= aswangIn(first) then
			differed = true
			break
		end
	end

	check("different streams can draw different Aswangs", differed)
end

--------------------------------------------------------------------------------
-- The weighting itself
--------------------------------------------------------------------------------

do
	local history = { { 101 }, { 102 }, { 103 } }

	check(
		"last round's Aswang carries the recent weight",
		RoleDraw.weightFor(101, history, WEIGHTS) == WEIGHTS.Recent
	)
	check(
		"the round before carries the older weight",
		RoleDraw.weightFor(102, history, WEIGHTS) == WEIGHTS.Older
	)
	check(
		"beyond the history window, full weight returns",
		RoleDraw.weightFor(103, history, WEIGHTS) == WEIGHTS.Base,
		`RepeatCooldownRounds={WEIGHTS.HistoryRounds}`
	)
	check(
		"a player who has never been the Aswang carries full weight",
		RoleDraw.weightFor(999, history, WEIGHTS) == WEIGHTS.Base
	)
end

--------------------------------------------------------------------------------
-- 10,000 rounds — C03's Verify line, both halves
--------------------------------------------------------------------------------

do
	local ROUNDS = 10000
	local rng = makeRng(20260810)
	local history: RoleDraw.History = {}
	local timesDrawn: { [number]: number } = {}
	local backToBack = 0
	local previous: number? = nil

	for _, userId in PLAYERS do
		timesDrawn[userId] = 0
	end

	for _ = 1, ROUNDS do
		local assignments = RoleDraw.draw(PLAYERS, history, Config.Roles.AswangCount, WEIGHTS, rng)
		local aswang = aswangIn(assignments)

		if aswang ~= nil then
			timesDrawn[aswang] += 1

			if aswang == previous then
				backToBack += 1
			end

			previous = aswang

			-- Most recent first, trimmed to the window the draw actually consults.
			table.insert(history, 1, { aswang })

			while #history > WEIGHTS.HistoryRounds do
				table.remove(history)
			end
		end
	end

	-- With no weighting at all, the same player draws again with probability 1/#players.
	local baseline = 1 / #PLAYERS
	local rate = backToBack / ROUNDS

	check(
		"back-to-back Aswang is rarer than an unweighted draw",
		rate < baseline,
		`rate={rate}, unweighted baseline={baseline}`
	)

	-- "Heavily reduced" (§4.2) is a stronger claim than "reduced". Half the baseline is a floor with
	-- room to tune inside it: at the shipped weights the expected rate is roughly 0.014.
	check("back-to-back is HEAVILY reduced, not marginally", rate < baseline * 0.5, `rate={rate}`)

	-- No starvation. Anti-repeat should make the distribution MORE even, not less, so a player far
	-- below their share means the weighting has become an exclusion.
	local fairShare = ROUNDS / #PLAYERS

	for _, userId in PLAYERS do
		check(
			`player {userId} is not starved of the role`,
			timesDrawn[userId] > fairShare * 0.5,
			`drawn {timesDrawn[userId]} of {ROUNDS}, fair share {fairShare}`
		)
	end
end

--------------------------------------------------------------------------------
-- Degenerate rosters. A live server reaching one of these must not get an error.
--------------------------------------------------------------------------------

do
	local empty = RoleDraw.draw({}, {}, 1, WEIGHTS, makeRng(7))

	check("an empty roster draws nobody", next(empty) == nil)

	local solo = RoleDraw.draw({ 101 }, {}, 1, WEIGHTS, makeRng(7))

	check("a single player is never the Aswang alone", solo[101] == "SURVIVOR")

	local greedy = RoleDraw.draw(PLAYERS, {}, #PLAYERS + 5, WEIGHTS, makeRng(7))
	local survivors = 0

	for _, role in greedy do
		if role == "SURVIVOR" then
			survivors += 1
		end
	end

	check("a round always keeps at least one survivor", survivors >= 1, `survivors={survivors}`)

	local none = RoleDraw.draw(PLAYERS, {}, 0, WEIGHTS, makeRng(7))

	check("asking for zero Aswangs draws zero", aswangIn(none) == nil)
end

if failures > 0 then
	error(`{failures} role-draw failure(s)`, 0)
end

print(
	`  PASS  role-draw: {checked} assertions — shape, determinism, weighting, degenerate rosters`
)
