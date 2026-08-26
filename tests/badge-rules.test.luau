--!strict
--[[
	The five funnel badges (C35, Appendix B).

	C35's Verify line is a playtester triggering each condition in Studio, which proves the WIRING.
	This file proves the RULE, and the two catch different things: a playtester who plays one round on
	one day cannot distinguish "BalikBalik is awarded on a return" from "BalikBalik is awarded always",
	because both look identical from inside a single session.

	That distinction is the reason this file exists. Badge counts are permanent and public — Roblox has
	no un-award — so a `>=` where a `>` belongs cannot be corrected later, only explained. §10's launch
	gate reads `FirstTask / Welcome`, and Appendix C's whole diagnosis of the competitor was read off
	numbers exactly like these.

	The day boundary itself is NOT re-tested here; `tests/daily-streak.test.luau` owns `dayIndex`. What
	is tested is that `BadgeRules` compares the two indices the right way round and excludes the
	unstamped case.
]]

local BadgeRules = require("../src/shared/pure/BadgeRules")
local DailyStreak = require("../src/shared/pure/DailyStreak")

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

local function stats(overrides: { [string]: number }?): BadgeRules.Stats
	local base = {
		Rounds = 0,
		Survived = 0,
		AswangRounds = 0,
		AswangWins = 0,
		Kills = 0,
		TasksDone = 0,
	}

	for key, value in overrides or {} do
		base[key] = value
	end

	return base
end

local function earned(statOverrides: { [string]: number }?, today: number, firstSeen: number)
	return BadgeRules.earned({
		Stats = stats(statOverrides),
		TodayIndex = today,
		FirstSeenDayIndex = firstSeen,
	})
end

--[[
	A day index from a real timestamp rather than a hand-picked integer, so the test is anchored to the
	same arithmetic the service will use rather than to a number that happens to work.
]]
local DAY_ONE = DailyStreak.dayIndex(1_760_000_000)

-- ---------------------------------------------------------------------------
-- The denominator
-- ---------------------------------------------------------------------------

check("Welcome awards on a bare first join", earned(nil, DAY_ONE, 0).Welcome)

check(
	"Welcome awards for a veteran too — it is unconditional",
	earned({ Rounds = 400, TasksDone = 900 }, DAY_ONE + 50, DAY_ONE).Welcome
)

-- ---------------------------------------------------------------------------
-- FirstTask — the number that killed the competitor (20.1%, §10 wants >50%)
-- ---------------------------------------------------------------------------

check("FirstTask is withheld at zero tasks", not earned(nil, DAY_ONE, 0).FirstTask)

check("FirstTask awards on the very first task", earned({ TasksDone = 1 }, DAY_ONE, 0).FirstTask)

check("FirstTask stays awarded at many tasks", earned({ TasksDone = 73 }, DAY_ONE, 0).FirstTask)

--[[
	The load-bearing one. A player whose first task completes mid-round and who then quits before
	ENDING must still be in the numerator — those players are 79.9% of the competitor's audience, so
	a rule that needed a finished round would be measuring the wrong population.
]]
check(
	"FirstTask does not require a completed round",
	earned({ TasksDone = 1, Rounds = 0 }, DAY_ONE, 0).FirstTask
)

-- ---------------------------------------------------------------------------
-- FirstRound and FirstBlood
-- ---------------------------------------------------------------------------

check("FirstRound is withheld at zero rounds", not earned(nil, DAY_ONE, 0).FirstRound)

check(
	"FirstRound awards on a round that was LOST",
	earned({ Rounds = 1, Survived = 0 }, DAY_ONE, 0).FirstRound
)

check(
	"FirstRound awards on a round that was survived",
	earned({ Rounds = 1, Survived = 1 }, DAY_ONE, 0).FirstRound
)

check(
	"FirstBlood is withheld at zero Aswang rounds",
	not earned({ Rounds = 40 }, DAY_ONE, 0).FirstBlood
)

--[[
	Being DEALT the role is the condition, not winning with it. `AswangWins` is a much rarer event and
	the badge answers "are people reaching the fun role" rather than "are they good at it".
]]
check(
	"FirstBlood awards on an Aswang round that was LOST",
	earned({ Rounds = 1, AswangRounds = 1, AswangWins = 0 }, DAY_ONE, 0).FirstBlood
)

-- ---------------------------------------------------------------------------
-- BalikBalik — day-2 retention, measured directly. The boundary, from both sides.
-- ---------------------------------------------------------------------------

check(
	"BalikBalik is withheld on the very first join (nothing stamped)",
	not earned(nil, DAY_ONE, 0).BalikBalik
)

--[[
	THE ASSERTION THIS FILE WAS WRITTEN FOR. A second session on the SAME UTC day is not a return, and
	a `>=` here would award day-2 retention to every player who joined twice in one evening — which is
	most of them, on day one, forever.
]]
check(
	"BalikBalik is withheld on a second session the SAME day",
	not earned({ Rounds = 1 }, DAY_ONE, DAY_ONE).BalikBalik
)

check("BalikBalik awards on the NEXT day", earned({ Rounds = 1 }, DAY_ONE + 1, DAY_ONE).BalikBalik)

check(
	"BalikBalik awards on a return weeks later, not only on day 2 exactly",
	earned({ Rounds = 1 }, DAY_ONE + 90, DAY_ONE).BalikBalik
)

--[[
	A CLOCK THAT WENT BACKWARDS must not award. Server clock skew and a corrupt stored timestamp both
	land here, and awarding on a negative difference would mean a badly-stamped profile grants day-2
	retention on a first join.
]]
check(
	"BalikBalik is withheld when today is BEFORE the first-seen day",
	not earned({ Rounds = 1 }, DAY_ONE - 3, DAY_ONE).BalikBalik
)

check(
	"BalikBalik does not require a completed round — a return is a return",
	earned(nil, DAY_ONE + 1, DAY_ONE).BalikBalik
)

-- ---------------------------------------------------------------------------
-- Corrupt inputs degrade to withheld, never to awarded
-- ---------------------------------------------------------------------------

--[[
	Every one of these can only arrive from a corrupt save, and the safe direction is unambiguous: a
	badge withheld from someone who earned it is a support message, a badge awarded to someone who did
	not is a permanent lie in the only retention data the project has.
]]
check(
	"a NaN task count does not award FirstTask",
	not earned({ TasksDone = 0 / 0 }, DAY_ONE, 0).FirstTask
)

check(
	"an infinite round count does not award FirstRound",
	not earned({ Rounds = math.huge }, DAY_ONE, 0).FirstRound
)

check(
	"a negative Aswang round count does not award FirstBlood",
	not earned({ AswangRounds = -1 }, DAY_ONE, 0).FirstBlood
)

check(
	"a NaN first-seen index does not award BalikBalik",
	not earned({ Rounds = 1 }, DAY_ONE, 0 / 0).BalikBalik
)

check(
	"an infinite today index does not award BalikBalik",
	not earned({ Rounds = 1 }, math.huge, DAY_ONE).BalikBalik
)

-- ---------------------------------------------------------------------------
-- The id list is the one the rules produce
-- ---------------------------------------------------------------------------

--[[
	`BadgeService` iterates `IDS` and indexes `Config.Badges` with each entry. A name in one list and
	not the other is a badge that silently never awards, and the only symptom is a funnel stage that
	reads as zero — indistinguishable from a game nobody plays.
]]
local produced = earned(nil, DAY_ONE, 0)

for _, id in BadgeRules.IDS do
	check(`IDS entry "{id}" is a field the rules actually produce`, (produced :: any)[id] ~= nil)
end

local idCount = 0

for _ in produced :: any do
	idCount += 1
end

check(
	"IDS covers every field of Earned",
	#BadgeRules.IDS == idCount,
	`{#BadgeRules.IDS} ids, {idCount} fields`
)

if failures > 0 then
	error(`{failures} badge-rules failure(s)`, 0)
end

print(`  PASS  badge-rules: {checked} assertions over the five funnel badges`)
