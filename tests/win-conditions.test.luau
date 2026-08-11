--!strict
--[[
	The Aswang's attrition win (§4.8), across every roster size this game can have.

	The cells below are the whole point: the rule is one comparison, and every bug it can have is a bug
	at a boundary — the round that starts already won, the round that can never be won, the last
	survivor. Each one is a cell somebody can argue with.
]]

local WinConditions = require("../src/shared/pure/WinConditions")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local THRESHOLD = 2 -- Config.Round.AswangWinSurvivorThreshold at time of writing

local function wins(dealtIn: number, living: number): boolean
	return WinConditions.aswangWinsByAttrition({
		LivingSurvivors = living,
		DealtInSurvivors = dealtIn,
		Threshold = THRESHOLD,
	})
end

type Case = { dealtIn: number, living: number, expected: boolean, why: string }

local CASES: { Case } = {
	-- SOLO (Debug.SoloTesting + ForceAswangWhenSolo). One player, who IS the Aswang, so zero survivors
	-- were dealt in. Must NEVER win by attrition: solo rounds are the only rounds an agent can drive,
	-- and a round that ends on tick one cannot verify anything downstream of it.
	{ dealtIn = 0, living = 0, expected = false, why = "solo Studio round" },

	-- MinPlayers = 3: one Aswang, two survivors. The literal §4.8 rule is satisfied before anyone
	-- moves, which is the whole reason the clamp exists.
	{ dealtIn = 2, living = 2, expected = false, why = "3-player round, nobody dead yet" },
	{ dealtIn = 2, living = 1, expected = true, why = "3-player round, one killed" },
	{ dealtIn = 2, living = 0, expected = true, why = "3-player round, both killed" },

	-- 4 players: three survivors. One kill takes it to the threshold.
	{ dealtIn = 3, living = 3, expected = false, why = "4-player round, nobody dead" },
	{ dealtIn = 3, living = 2, expected = true, why = "4-player round, one killed" },

	-- 6 players — the spec's picture of a round.
	{ dealtIn = 5, living = 5, expected = false, why = "6-player, full" },
	{ dealtIn = 5, living = 3, expected = false, why = "6-player, two killed" },
	{ dealtIn = 5, living = 2, expected = true, why = "6-player, three killed" },

	-- 8 players — MaxPlayers.
	{ dealtIn = 7, living = 3, expected = false, why = "8-player, four killed" },
	{ dealtIn = 7, living = 2, expected = true, why = "8-player, five killed" },
	{ dealtIn = 7, living = 0, expected = true, why = "8-player, wiped out" },

	-- A two-player round: one Aswang, one survivor. Reachable only through SoloTesting or a shutdown
	-- race, and it must terminate rather than being unwinnable forever.
	{ dealtIn = 1, living = 1, expected = false, why = "two players, survivor alive" },
	{ dealtIn = 1, living = 0, expected = true, why = "two players, survivor killed" },
}

for _, case in CASES do
	local actual = wins(case.dealtIn, case.living)

	check(
		`dealtIn={case.dealtIn} living={case.living} ({case.why})`,
		actual == case.expected,
		`expected {case.expected}, got {actual}`
	)
end

--------------------------------------------------------------------------------
-- The properties the cells exist to express. A future edit must not satisfy the table by accident
-- while breaking the rule underneath it.
--------------------------------------------------------------------------------

-- THE ONE THAT KEEPS THE HARNESS WORKING. Stated separately from its cell because the cell is one
-- line in a table and this is a constraint on the whole project's ability to verify itself.
check("a solo round is never won on tick one", not wins(0, 0))

-- No round may be over before it starts, at ANY roster size. This is the general form of the §4.8
-- degeneracy, and it is what the clamp actually guarantees.
for dealtIn = 1, 7 do
	check(
		`a round of {dealtIn} survivors is not already won at kickoff`,
		not wins(dealtIn, dealtIn),
		"the round would end during STARTING"
	)
end

-- Every round must be winnable by attrition eventually, or the Aswang has no path but the timer.
for dealtIn = 1, 7 do
	check(`a round of {dealtIn} survivors is won when all are dead`, wins(dealtIn, 0))
end

--[[
	A SELF-REMOVAL MUST NOT WIN THE ROUND FOR THE ASWANG.

	`RoundService.MarkKilled` decrements `DealtInSurvivors` for any death it was not told came from a
	validated kill, so a player who resets or falls out of the world drops BOTH sides of this
	comparison together. These cases pin the property that makes that work.

	The arithmetic this replaced was a live exploit: at MinPlayers = 3, DealtInSurvivors is 2 and the
	effective threshold is min(2, 1) = 1, so ONE survivor pressing the stock reset button dropped
	LivingSurvivors to 1, satisfied `1 <= 1`, and ended the round as ASWANG_WINS. One button, no
	remote, nothing for AntiCheat to see.

	NOTE what this file can and cannot prove. It pins the predicate's behaviour when both sides move
	together; that the SERVICE actually moves both is in RoundService and is not reachable from Lune —
	that half is verified live in artifacts/console-exploit-retest.txt.
]]
for dealtIn = 1, 7 do
	check(
		`a self-removal at dealtIn={dealtIn} does not hand the Aswang the round`,
		not wins(dealtIn - 1, dealtIn - 1),
		"both sides of the comparison must fall together"
	)
end

-- MONOTONIC IN THE DIRECTION THE GAME MOVES. Survivors only ever decrease, so once the round is won
-- it must stay won. Walking `living` downwards is the same order the round walks it in; a comparison
-- written with the wrong operator satisfies several cells above and fails here.
for dealtIn = 1, 7 do
	local won = false

	for living = dealtIn, 0, -1 do
		local result = wins(dealtIn, living)

		if won and not result then
			check(`monotonic at dealtIn={dealtIn}`, false, `un-won at living={living}`)
		end

		won = won or result
	end
end

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  win-conditions: 14 cases + 29 properties")
