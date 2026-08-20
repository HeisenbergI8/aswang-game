--!strict
--[[
	The daily login streak (C33, §7).

	C33's Verify line is this file — "same day, next day, skipped day, DST, year boundary" — and the
	brief says why it is worth a suite rather than a glance: "timezone bugs here are silent and
	permanent, and a streak that resets wrongly is worse than no streak at all."

	Permanent is the operative word. A streak that resets when it should not deletes six days of a
	player's reason to come back, throws no error, and cannot be repaired afterwards because the
	profile no longer holds what the streak was. There is no symptom, no log line, and no way to tell
	an incorrect reset from a player who genuinely missed a day.

	EVERY TIMESTAMP BELOW IS A REAL UNIX SECOND, computed once and written in. Deriving them inside
	the suite from the same `math.floor(t / 86400)` the module uses would make the arithmetic agree
	with itself and prove nothing — which is exactly the failure mode a timezone test is prone to.
	The comment beside each names the UTC instant it is.
]]

local Config = require("../src/shared/Config")
local DailyStreak = require("../src/shared/pure/DailyStreak")

type Input = DailyStreak.Input

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
	A reward table that is NOT the shipped one, so an assertion passes because the wrap arithmetic is
	right rather than because it happens to agree with Config. Three days, escalating, so the cycle
	boundary lands inside the range every loop below walks. The real table gets its own section.
]]
local PARAMS: DailyStreak.Params = {
	Rewards = {
		{ XP = 1, Coins = 10 },
		{ XP = 2, Coins = 20 },
		{ XP = 3, Coins = 30 },
	},
}

-- Real UTC instants, computed outside this file. See the header for why they are literals.
local MAY_01_MIDNIGHT = 1777593600 -- 2026-05-01 00:00:00 UTC, day 20574
local MAY_01_LAST_SECOND = 1777679999 -- 2026-05-01 23:59:59 UTC, day 20574
local MAY_02_MIDNIGHT = 1777680000 -- 2026-05-02 00:00:00 UTC, day 20575
local MAY_04_NOON = 1777896000 -- 2026-05-04 12:00:00 UTC, day 20577

local function evaluate(lastClaim: number, streak: number, now: number): DailyStreak.Result
	local input: Input = { LastClaimUTC = lastClaim, Streak = streak, NowUTC = now }

	return DailyStreak.evaluate(input, PARAMS)
end

--------------------------------------------------------------------------------
-- dayIndex — the entire timezone story of this module
--------------------------------------------------------------------------------

check("midnight UTC opens a day", DailyStreak.dayIndex(MAY_01_MIDNIGHT) == 20574)
check(
	"the last second before midnight is still the same day",
	DailyStreak.dayIndex(MAY_01_LAST_SECOND) == 20574
)
check("the next midnight is the next day", DailyStreak.dayIndex(MAY_02_MIDNIGHT) == 20575)
check("the epoch is day zero", DailyStreak.dayIndex(0) == 0)

--[[
	A NEGATIVE TIMESTAMP can only arrive from corruption, and a negative day index would make every
	comparison in `evaluate` mean something different. Floored to day 0 rather than errored, for the
	same reason `ProfileMigration` defaults a malformed field instead of refusing the profile.
]]
check("a pre-epoch timestamp floors to day zero", DailyStreak.dayIndex(-99999) == 0)
check("a NaN timestamp floors to day zero", DailyStreak.dayIndex(0 / 0) == 0)
check("an infinite timestamp floors to day zero", DailyStreak.dayIndex(math.huge) == 0)

--------------------------------------------------------------------------------
-- The three cases the feature actually is
--------------------------------------------------------------------------------

local firstEver = evaluate(0, 0, MAY_01_MIDNIGHT)

check("a player who has never claimed can claim", firstEver.Outcome == "CLAIMED")
check("a first claim starts the streak at one", firstEver.Streak == 1)
check("a first claim pays the first tier", firstEver.RewardCoins == 10)
check("a first claim stamps the current time", firstEver.ClaimedAtUTC == MAY_01_MIDNIGHT)

--[[
	SAME DAY. The ordinary second press of the button, not an error — the lobby is on screen for a
	whole intermission and a player will press it again.
]]
local sameDay = evaluate(MAY_01_MIDNIGHT, 1, MAY_01_LAST_SECOND)

check("a second claim on the same UTC day is refused", sameDay.Outcome == "ALREADY_CLAIMED_TODAY")
check("a refused claim pays nothing", sameDay.RewardXP == 0 and sameDay.RewardCoins == 0)
check("a refused claim leaves the streak alone", sameDay.Streak == 1)

--[[
	AND LEAVES THE STAMP ALONE. A caller writing `Result.ClaimedAtUTC` back unconditionally — the
	obvious loop, and the one somebody will write — must not be able to walk the stored timestamp
	forward by pressing a button that was refused, because that would silently move the boundary of
	"tomorrow".
]]
check("a refused claim does not advance the stored stamp", sameDay.ClaimedAtUTC == MAY_01_MIDNIGHT)

-- NEXT DAY. Ninety minutes apart in wall-clock terms and two different UTC days; see the module
-- header on why that is the honest, player-favouring property of any UTC-day streak.
local nextDay = evaluate(MAY_01_LAST_SECOND, 1, MAY_02_MIDNIGHT)

check("the next UTC day advances the streak", nextDay.Outcome == "CLAIMED")
check("the streak advances by exactly one", nextDay.Streak == 2)
check("day two pays the second tier", nextDay.RewardCoins == 20)

-- SKIPPED DAY. May 1st then May 4th: two whole days missed.
local skipped = evaluate(MAY_01_MIDNIGHT, 6, MAY_04_NOON)

check("a missed day still allows a claim", skipped.Outcome == "CLAIMED")
check("a missed day resets the streak to one", skipped.Streak == 1, `got {skipped.Streak}`)
check("a reset claim pays the first tier again", skipped.RewardCoins == 10)

--------------------------------------------------------------------------------
-- DST — a real transition weekend, walked day by day
--------------------------------------------------------------------------------

--[[
	8 March 2026 is the US spring-forward: local clocks jump from 02:00 to 03:00 and that Sunday is 23
	hours long WHERE THE PLAYER IS. It is exactly 86400 seconds long in UTC, because the epoch has no
	daylight saving in it and there are no 23-hour UTC days for this module to observe.

	So this is a test of a thing that cannot happen, and it is written anyway: "it cannot happen" is
	the sentence every timezone bug in history has been shipped under, and the cost of being wrong
	here is a silently deleted streak.

	The instants are chosen to straddle the transition — 18:00 UTC on the Saturday, then 09:00 UTC on
	the Sunday, Monday and Tuesday. In a timezone-aware implementation the Saturday-to-Sunday step
	would be the one that broke.
]]
local DST_SAT = 1772906400 -- 2026-03-07 18:00:00 UTC, day 20519
local DST_SUN = 1772960400 -- 2026-03-08 09:00:00 UTC, day 20520 — the short local day
local DST_MON = 1773046800 -- 2026-03-09 09:00:00 UTC, day 20521
local DST_TUE = 1773133200 -- 2026-03-10 09:00:00 UTC, day 20522

local dstWalk = { DST_SAT, DST_SUN, DST_MON, DST_TUE }
local lastClaim = 0
local streak = 0
local dstOk = true
local dstDetail = ""

for index, now in dstWalk do
	local result = evaluate(lastClaim, streak, now)

	if result.Outcome ~= "CLAIMED" or result.Streak ~= index then
		dstOk = false
		dstDetail = `day {index}: {result.Outcome}, streak {result.Streak}`
	end

	lastClaim = result.ClaimedAtUTC
	streak = result.Streak
end

check(
	`a streak survives the DST weekend unbroken across {#dstWalk} days`,
	dstOk and streak == #dstWalk,
	dstDetail
)

--------------------------------------------------------------------------------
-- The year boundary
--------------------------------------------------------------------------------

--[[
	No calendar arithmetic anywhere in the module, so no month lengths, no leap years and no December
	special case. Two hours apart, across a year, and consecutive.
]]
local NYE = 1767222000 -- 2025-12-31 23:00:00 UTC, day 20453
local NYD = 1767229200 -- 2026-01-01 01:00:00 UTC, day 20454
local JAN_02 = 1767355200 -- 2026-01-02 12:00:00 UTC, day 20455

local newYear = evaluate(NYE, 4, NYD)

check("the streak crosses new year", newYear.Outcome == "CLAIMED")
check("the streak advances across the year boundary", newYear.Streak == 5)

local dayAfter = evaluate(NYD, 5, JAN_02)

check("and keeps going the day after", dayAfter.Streak == 6)

--------------------------------------------------------------------------------
-- CLOCK_BEHIND — the one case that resolves against the player
--------------------------------------------------------------------------------

--[[
	A stored claim stamped LATER than `NowUTC`: a Roblox server whose clock disagreed with another's,
	or a profile that crossed a rollback. Treated as "a different day, therefore claimable", the same
	day pays out repeatedly for as long as the skew lasts.

	Refusing costs the player at most one day and self-heals the moment the clock catches up, because
	the stored stamp is returned unchanged.
]]
local behind = evaluate(MAY_04_NOON, 3, MAY_01_MIDNIGHT)

check("a stored claim from the future is refused", behind.Outcome == "CLOCK_BEHIND")
check("a clock-behind refusal pays nothing", behind.RewardXP == 0 and behind.RewardCoins == 0)
check("a clock-behind refusal preserves the streak", behind.Streak == 3)
check("a clock-behind refusal preserves the stamp", behind.ClaimedAtUTC == MAY_04_NOON)

--------------------------------------------------------------------------------
-- The cycle wraps, so the day-7 payoff recurs
--------------------------------------------------------------------------------

--[[
	§7 asks for "a meaningful day-7 payoff", and a payoff that happens once is a payoff that stops
	being a reason to come back on day 8. Walked over two full cycles of the fixture table.
]]
local wrapOk = true
local wrapDetail = ""

for streakValue = 1, #PARAMS.Rewards * 2 do
	local expectedDay = ((streakValue - 1) % #PARAMS.Rewards) + 1
	local result = evaluate(MAY_01_MIDNIGHT, streakValue - 1, MAY_02_MIDNIGHT)

	if result.Streak ~= streakValue or result.CycleDay ~= expectedDay then
		wrapOk = false
		wrapDetail = `streak {streakValue}: cycle day {result.CycleDay}, expected {expectedDay}`
	end

	if result.RewardCoins ~= PARAMS.Rewards[expectedDay].Coins then
		wrapOk = false
		wrapDetail = `streak {streakValue}: paid {result.RewardCoins}`
	end
end

check(
	`the reward cycle wraps correctly over {#PARAMS.Rewards * 2} consecutive days`,
	wrapOk,
	wrapDetail
)

--------------------------------------------------------------------------------
-- Corrupt stored fields degrade rather than propagate
--------------------------------------------------------------------------------

for _, corrupt in { 0 / 0, math.huge, -1 } do
	local result = evaluate(MAY_01_MIDNIGHT, corrupt, MAY_02_MIDNIGHT)

	check(
		`a corrupt streak of {corrupt} restarts at one rather than propagating`,
		result.Streak == 1 and result.CycleDay == 1,
		`got streak {result.Streak}`
	)
end

local corruptStamp = evaluate(0 / 0, 3, MAY_02_MIDNIGHT)

check(
	"a corrupt stored stamp reads as never-claimed and restarts the streak",
	corruptStamp.Outcome == "CLAIMED" and corruptStamp.Streak == 1
)

--------------------------------------------------------------------------------
-- preview — the button and the server cannot disagree
--------------------------------------------------------------------------------

--[[
	`preview` runs `evaluate` rather than reimplementing it, which is what makes the lobby button and
	the server's decision the same decision. These assertions pin that they agree on the day a claim
	is available AND on what it pays, because a button showing the wrong reward is the version of this
	bug a player reports.
]]
local claimable = DailyStreak.preview(
	{ LastClaimUTC = MAY_01_MIDNIGHT, Streak = 1, NowUTC = MAY_02_MIDNIGHT },
	PARAMS
)

check("preview says today is claimable when it is", claimable.Claimable)
check("preview names the streak the claim would reach", claimable.Streak == 2)
check("preview names the reward the claim would pay", claimable.RewardCoins == 20)

local spent = DailyStreak.preview(
	{ LastClaimUTC = MAY_01_MIDNIGHT, Streak = 1, NowUTC = MAY_01_LAST_SECOND },
	PARAMS
)

check("preview says today is spent when it is", not spent.Claimable)
check("a spent day previews TOMORROW's reward rather than nothing", spent.RewardCoins == 20)
check("a spent day previews tomorrow's streak", spent.Streak == 2)

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

local probe: Input = { LastClaimUTC = MAY_01_MIDNIGHT, Streak = 4, NowUTC = MAY_02_MIDNIGHT }
local a = DailyStreak.evaluate(probe, PARAMS)
local b = DailyStreak.evaluate(probe, PARAMS)

check("evaluate is deterministic", a.Streak == b.Streak and a.RewardCoins == b.RewardCoins)
check("evaluate does not mutate its input", probe.Streak == 4 and probe.NowUTC == MAY_02_MIDNIGHT)
check("evaluate does not mutate its params", PARAMS.Rewards[1].Coins == 10)

--------------------------------------------------------------------------------
-- The SHIPPED table — §7's "meaningful day-7 payoff", measured
--------------------------------------------------------------------------------

local SHIPPED: DailyStreak.Params = { Rewards = Config.Daily.Rewards }

check("the shipped cycle is a week", #SHIPPED.Rewards == 7, `{#SHIPPED.Rewards} days`)

local escalating = true
local escalationDetail = ""

for day = 2, #SHIPPED.Rewards do
	local previous = SHIPPED.Rewards[day - 1]
	local current = SHIPPED.Rewards[day]

	if current.XP <= previous.XP or current.Coins <= previous.Coins then
		escalating = false
		escalationDetail = `day {day} does not beat day {day - 1}`
	end
end

check("the shipped rewards escalate every day", escalating, escalationDetail)

--[[
	"MEANINGFUL" IS A COMPARISON, NOT A FEELING. Day 7 has to be worth crossing six days for, so it is
	pinned against the day before it — a gentle sixth-to-seventh step is a week that ends in a shrug —
	and against a ROUND, so the whole week is worth roughly an evening of play rather than replacing
	one.
]]
local daySeven = SHIPPED.Rewards[#SHIPPED.Rewards]
local daySix = SHIPPED.Rewards[#SHIPPED.Rewards - 1]

check(
	"day 7 is a step rather than a nudge",
	daySeven.Coins >= daySix.Coins * 2,
	`day 7 pays {daySeven.Coins}, day 6 pays {daySix.Coins}`
)

check(
	"day 7 is worth more than a round, and less than an evening of them",
	daySeven.Coins > Config.Economy.CoinsPerRound
		and daySeven.Coins < Config.Economy.CoinsPerRound * 15,
	`{daySeven.Coins} coins vs {Config.Economy.CoinsPerRound}/round`
)

local weekCoins = 0

for _, reward in SHIPPED.Rewards do
	weekCoins += reward.Coins
end

check(
	"a full week does not out-earn playing the game",
	weekCoins < Config.Economy.CoinsPerRound * 30,
	`{weekCoins} coins per week vs {Config.Economy.CoinsPerRound}/round`
)

print(
	`  ....  shipped week: {weekCoins} coins over {#SHIPPED.Rewards} days, `
		.. `day 7 pays {daySeven.Coins} ({math.floor(weekCoins / Config.Economy.CoinsPerRound)} rounds' worth)`
)

if failures > 0 then
	error(`{failures} daily-streak failure(s)`, 0)
end

print(`  PASS  daily-streak: {checked} assertions`)
