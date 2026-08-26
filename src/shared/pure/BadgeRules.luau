--!strict
--[[
	BadgeRules — which of the five funnel badges a player has earned. (C35, Appendix B)

		earned(input) -> { Welcome, FirstTask, FirstRound, FirstBlood, BalikBalik }

	WHY THIS IS A PURE MODULE AND NOT FIVE `if`s IN THE SERVICE. These five booleans are the retention
	dashboard the whole project is steered by. Appendix C diagnosed the competitor entirely from their
	public badge counts, §10's launch gate is `FirstTask / Welcome > 0.50`, and `BalikBalik` IS day-2
	retention — there is no second measurement to check any of them against.

	An off-by-one in the `BalikBalik` comparison awards it on the player's FIRST day, day-2 retention
	reads 100%, and the number that would have told you to stop and fix the game instead tells you to
	ship. Nothing errors, nothing looks wrong, and the badge counts are permanent — Roblox has no
	un-award. That is the failure this file exists to make impossible, and `tests/badge-rules.test.luau`
	pins the boundary from both sides.

	NO DATE ARITHMETIC LIVES HERE, DELIBERATELY. The caller passes DAY INDICES that
	`DailyStreak.dayIndex` already computed and `tests/daily-streak.test.luau` already pins. A pure
	module cannot require another pure module — Lune has no `script`, and re-implementing the UTC day
	boundary here would be a second source of truth for the one piece of arithmetic C33's brief calls
	"silent and permanent".

	A CLIENT CAN REQUIRE AND RUN THIS, and it learns nothing. It is five comparisons over a player's
	own lifetime counters, and the mapping is printed in the spec's own Appendix B table.
]]

-- Re-declared rather than required from `Types`, for the reason in the header. Luau records are
-- structural, so this and `Types.PlayerStats` are the same type and pass to each other uncast.
export type Stats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number,
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}

export type Input = {
	Stats: Stats,
	--[[
		`DailyStreak.dayIndex(os.time())` on the server. The client never supplies either of these: a
		claimed "today" is the field that would forge day-2 retention, and unlike the daily streak
		there is no reward to notice going missing if it were forged.
	]]
	TodayIndex: number,
	--[[
		The day index of `Profile.FirstSeenUTC`, and **the value from BEFORE this session stamped it**.

		This is the whole subtlety of the module. `FirstSeenUTC` is stamped at session start for a
		player who has never had one, so by the time anything reads the live profile it says "today"
		and the comparison below can never be true for anybody, ever. `ProgressionService.ProfileLoaded`
		carries the pre-stamp value as its second argument for exactly this reason.

		0 means never stamped — a genuinely first-ever join, or a v1 profile that predates the field.
	]]
	FirstSeenDayIndex: number,
}

export type Earned = {
	Welcome: boolean,
	FirstTask: boolean,
	FirstRound: boolean,
	FirstBlood: boolean,
	BalikBalik: boolean,
}

local BadgeRules = {}

--[[
	The five ids, in Appendix B's order. Exported so `BadgeService` iterates this rather than
	re-typing the names next to `Config.Badges` — a badge misspelled in a second list is a badge that
	silently never awards, and the funnel just reads as a game nobody plays.
]]
BadgeRules.IDS = { "Welcome", "FirstTask", "FirstRound", "FirstBlood", "BalikBalik" }

local function finite(value: number): number
	if type(value) ~= "number" or not (value >= 0 and value < math.huge) then
		return 0
	end

	return math.floor(value)
end

--[[
	Appendix B's table, one line each.

	`Welcome` is unconditional because its condition is "first join" and the caller only asks on a
	join. It is the funnel's DENOMINATOR, so it must be the one badge that cannot fail to award for a
	reason of ours — every other number in the dashboard is a fraction of it, and an undercounted
	denominator inflates all four of them at once.

	`FirstTask` is `TasksDone >= 1` rather than a per-round flag because Appendix B says "ever". It is
	awarded the moment the counter moves, NOT at the end of the round: 79.9% of the competitor's
	players never completed an objective, so the players this number is about are precisely the ones
	most likely to close the game before ENDING, and awarding at round end would drop them from the
	numerator while leaving them in the denominator.

	`FirstBlood` is `AswangRounds >= 1` — "first round AS the Aswang", which is a round they were
	DEALT, not a round they won. `AswangWins` would measure something else and read as a much rarer
	event; the question the badge answers is "are people reaching the fun role", so being dealt it is
	the whole of the condition.

	`BalikBalik` is a STRICT `>`, and that is the assertion the test exists for. Equal indices are the
	same UTC day, which is the same session or a second one an hour later — neither is a return.
	`FirstSeenDayIndex == 0` is excluded separately: an unstamped profile would otherwise compare 0
	against today's ~20,000 and hand day-2 retention to every first-time player alive.
]]
function BadgeRules.earned(input: Input): Earned
	local stats = input.Stats
	local firstSeen = finite(input.FirstSeenDayIndex)

	return {
		Welcome = true,
		FirstTask = finite(stats.TasksDone) >= 1,
		FirstRound = finite(stats.Rounds) >= 1,
		FirstBlood = finite(stats.AswangRounds) >= 1,
		BalikBalik = firstSeen > 0 and finite(input.TodayIndex) > firstSeen,
	}
end

return BadgeRules
