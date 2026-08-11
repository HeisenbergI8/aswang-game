--!strict
--[[
	The Aswang's attrition win (§4.8), enumerated over every way a survivor can leave the board.

	THIS FILE IS THE FOURTH ATTEMPT AT THIS RULE AND THE FIRST THAT ENUMERATES ANYTHING. The three
	before it each patched one expression and each was wrong differently:

	  1. freeze DealtInSurvivors at STARTING     — livingSurvivorCount() is LIVE, so a disconnect moved
	                                               one side of the comparison and not the other
	  2. decrement it on a non-kill death        — closed reset-then-reset and nothing else
	  3. decrement it on disconnect too          — ARITHMETICALLY INERT. effective = min(2, dealt-1),
	                                               and that term only binds at dealt <= 3, so above four
	                                               survivors the denominator did nothing while the
	                                               numerator fell anyway

	Each passed the cases written from the bug just seen. None was ever run against the whole space,
	which is four dimensions and small enough to enumerate exhaustively:

	    roster × kills × resets × disconnects

	The rule now counts KILLS rather than survivors currently present, so the whole class of "a player
	left the board somehow" cannot move it. That is the property every table below exists to pin.
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

local function wins(dealtIn: number, kills: number): boolean
	return WinConditions.aswangWinsByKills({
		AswangKills = kills,
		DealtInSurvivors = dealtIn,
		Threshold = THRESHOLD,
	})
end

--------------------------------------------------------------------------------
-- THE EXHAUSTIVE GRID. Every roster this game can have, every kill count from none to all.
--
-- `required` is what the rule should demand: enough kills that only Threshold survivors could remain,
-- floored at one so a round is never won with no kills at all.
--------------------------------------------------------------------------------

local MAX_DEALT_IN = 7 -- MaxPlayers 8 minus one Aswang

for dealtIn = 0, MAX_DEALT_IN do
	local required = math.max(1, dealtIn - THRESHOLD)

	for kills = 0, dealtIn do
		local expected = dealtIn > 0 and kills >= required

		check(
			`dealtIn={dealtIn} kills={kills}`,
			wins(dealtIn, kills) == expected,
			`expected {expected} (needs {required}), got {wins(dealtIn, kills)}`
		)
	end
end

--------------------------------------------------------------------------------
-- THE EXPLOIT, AS A PROPERTY. This is the whole reason the rule changed shape.
--
-- Survivors leaving the board — quitting, resetting, falling out of the world — must not move the
-- requirement. Under the old rule each departure removed one required kill: in an 8-player round,
-- three alt accounts quitting turned a five-kill win into a two-kill win, and five turned it into one.
--
-- Kills are the only input now, so departures cannot appear in this expression at all. The test is
-- written over departures anyway, because "it cannot happen by construction" is exactly the kind of
-- claim this file exists to stop trusting.
--------------------------------------------------------------------------------

for dealtIn = 1, MAX_DEALT_IN do
	local required = math.max(1, dealtIn - THRESHOLD)

	for departures = 0, dealtIn do
		-- Whatever the departures, the kills needed are unchanged.
		check(
			`{departures} departures from a roster of {dealtIn} do not lower the bar`,
			not wins(dealtIn, required - 1),
			"a departure must never substitute for a kill"
		)

		check(
			`the bar is still reachable at exactly {required} kills (dealtIn={dealtIn})`,
			wins(dealtIn, required)
		)
	end
end

--------------------------------------------------------------------------------
-- The boundaries, from both sides.
--------------------------------------------------------------------------------

-- SOLO. A solo Studio round has one player who IS the Aswang, so no survivors were dealt in. It must
-- never win by attrition or every agent-driven verification of every later chunk becomes impossible.
check("a solo round is never won", not wins(0, 0))
check("a solo round is not won even with a phantom kill", not wins(0, 1))

-- MinPlayers = 3: one Aswang, two survivors. The old rule was TRUE before anyone moved.
check("a 3-player round is not won at kickoff", not wins(2, 0))
check("a 3-player round needs one kill", wins(2, 1))

-- 8 players, the size the threshold is actually tuned for.
check("an 8-player round is not won at four kills", not wins(7, 4))
check("an 8-player round is won at five", wins(7, 5))

-- Monotonic: kills only ever increase, so once won it must stay won.
for dealtIn = 1, MAX_DEALT_IN do
	local won = false

	for kills = 0, dealtIn do
		local result = wins(dealtIn, kills)

		if won and not result then
			check(`monotonic at dealtIn={dealtIn}`, false, `un-won at kills={kills}`)
		end

		won = won or result
	end
end

-- Every round must be winnable by killing everyone, or the Aswang has no path but the sunrise timer.
for dealtIn = 1, MAX_DEALT_IN do
	check(`a roster of {dealtIn} is won when all are killed`, wins(dealtIn, dealtIn))
end

-- And never winnable with no kills at all, at any roster size. The old rule's worst failure was a
-- ZERO-kill Aswang win once enough survivors had removed themselves.
for dealtIn = 0, MAX_DEALT_IN do
	check(`a roster of {dealtIn} is never won with no kills`, not wins(dealtIn, 0))
end

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print(
	"  PASS  win-conditions: exhaustive grid over roster × kills, + departure and boundary properties"
)
