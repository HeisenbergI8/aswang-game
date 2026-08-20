--!strict
--[[
	DailyStreak — the login streak, resolved in UTC days. (C33, §7)

		dayIndex(unixSeconds)        -> number    -- which UTC day that instant falls in
		evaluate(input, params)      -> Result    -- what a claim RIGHT NOW would do
		preview(input, params)       -> Preview   -- the same question, asked by the HUD

	§7 calls this "the single highest-ROI retention feature you can build", and C33's brief adds the
	part that makes it worth a pure module: "timezone bugs here are silent and permanent, and a streak
	that resets wrongly is worse than no streak at all."

	Worse, specifically, because of what it costs to be wrong in each direction. A streak that resets
	when it should not deletes six days of a player's reason to come back, produces no error, and is
	unrecoverable — the profile no longer contains what the streak was. A streak that fails to reset
	just hands out a reward. So every ambiguous case in this file resolves toward NOT breaking the
	streak, and the one case that resolves the other way (`CLOCK_BEHIND`) is the one where allowing it
	would let the same day be claimed twice.

	── WHY UTC DAYS, AND WHY THAT MAKES DST A NON-EVENT ──────────────────────────

	The whole module is `math.floor(t / 86400)` over Unix epoch seconds, and every property C33 asks
	about falls out of that one line:

	  · DST. A daylight-saving transition moves a LOCAL clock; it does not move the epoch, and there
	    are no 23- or 25-hour UTC days. Nothing here can observe one. The test walks a real DST weekend
	    anyway, because "it cannot happen" is the sentence every timezone bug is written under.
	  · Year boundaries. 2025-12-31 23:00 UTC and 2026-01-01 01:00 UTC are two hours apart and land on
	    consecutive day indices. No calendar arithmetic, no month lengths, no leap years.
	  · Leap seconds. Unix time does not have them.

	THE HONEST COST, stated rather than hidden: a player two hours west of UTC crosses the boundary at
	their local 4pm, and a claim at 23:30 UTC followed by one at 00:30 UTC — ninety minutes apart —
	counts as two days. That is a real property of every UTC-day streak, it favours the player, and it
	cannot be used to SKIP a day, which is the direction that would matter. A per-player local
	midnight would need a timezone in the profile and a v2 schema, and it buys nothing §7 is asking
	for.

	NO `script.Parent` REQUIRES (tests/README.md). `Outcome` is a SCALAR and never travels in a list —
	see `.claude/lessons/pure-module-unions-widen-in-lists.md`. The reward table arrives as a
	parameter out of `Config.Daily`.

	NOTHING SECRET PASSES THROUGH. A streak is one player's own history, its inputs are their profile
	and the server clock, and no other player appears in any signature here.
]]

local SECONDS_PER_DAY = 86400

export type Reward = {
	XP: number,
	Coins: number,
}

--[[
	The cycle is the LENGTH OF THE REWARD LIST, not a separate number, so the two cannot disagree.
	§7 asks for "escalating rewards with a meaningful day-7 payoff", which is a statement about this
	table's contents and about nothing else in the file.
]]
export type Params = {
	Rewards: { Reward },
}

export type Input = {
	LastClaimUTC: number, -- 0 for a player who has never claimed
	Streak: number,
	NowUTC: number,
}

--[[
	CLAIMED               the streak advanced (or started) and a reward is owed.
	ALREADY_CLAIMED_TODAY this UTC day is already spent. Not an error; the ordinary second press.
	CLOCK_BEHIND          the stored claim is in the FUTURE relative to `NowUTC`. See `evaluate`.
]]
export type Outcome = "CLAIMED" | "ALREADY_CLAIMED_TODAY" | "CLOCK_BEHIND"

export type Result = {
	Outcome: Outcome,
	Streak: number, -- what the profile should hold AFTER this call
	CycleDay: number, -- 1..#Rewards — which reward tier this claim sits on
	RewardXP: number,
	RewardCoins: number,
	-- What to write into `Profile.Daily.LastClaimUTC`. Equal to the stored value on a refusal, so a
	-- caller that writes it back unconditionally cannot advance the clock by refusing.
	ClaimedAtUTC: number,
}

export type Preview = {
	Claimable: boolean,
	Streak: number, -- the streak this player would be on AFTER claiming
	CycleDay: number,
	RewardXP: number,
	RewardCoins: number,
}

local DailyStreak = {}

-- Same finite guard as `ProfileMigration.num` and `XPCurve.finite`, and for the same reason: a stored
-- number is not trusted, and an infinity in a profile makes every later DataStore write for that
-- player fail silently and forever.
local function finite(value: number, fallback: number): number
	if type(value) ~= "number" or not (value >= 0 and value < math.huge) then
		return fallback
	end

	return math.floor(value)
end

--[[
	WHICH UTC DAY AN INSTANT FALLS IN. The entire timezone story of this module.

	Negative inputs (a pre-1970 timestamp, which can only arrive from corruption) are floored to day
	0 rather than producing a negative index, so the comparisons below stay meaningful.
]]
function DailyStreak.dayIndex(unixSeconds: number): number
	return math.floor(finite(unixSeconds, 0) / SECONDS_PER_DAY)
end

--[[
	WHICH REWARD TIER A STREAK OF `streak` SITS ON, wrapping at the end of the table.

	Wrapping rather than clamping so day 7's payoff RECURS — §7's "meaningful day-7 payoff" is a
	weekly rhythm, not a one-off. A player on a 30-day streak is on cycle day 2, and their day-7 is
	four days away, which is the returning reason the feature exists for.
]]
local function cycleDayFor(streak: number, count: number): number
	if count <= 0 then
		return 1
	end

	return ((math.max(finite(streak, 1), 1) - 1) % count) + 1
end

local function rewardFor(cycleDay: number, params: Params): Reward
	local reward = params.Rewards[cycleDay]

	if reward == nil then
		return { XP = 0, Coins = 0 }
	end

	return { XP = finite(reward.XP, 0), Coins = finite(reward.Coins, 0) }
end

--[[
	THE STREAK THIS PLAYER WOULD BE ON IF THEY CLAIMED AT `NowUTC`.

	Three cases and they are the whole feature:

	  never claimed / gap of 2+ days -> 1   the streak starts (or restarts) at today
	  exactly the next day           -> +1  the streak advances
	  the same day                   -> unchanged, and nothing is owed

	`LastClaimUTC <= 0` is the never-claimed sentinel from `ProfileMigration.template`, and it is
	checked BEFORE the day arithmetic: day index 0 is a real day (1 January 1970) and treating a fresh
	profile as "last claimed on that day" would put every new player on a 20,000-day gap. The answer
	happens to be the same — a gap resets to 1 — which is exactly why this is worth an explicit branch
	rather than an accident that survives until the sentinel changes.
]]
local function streakAfter(input: Input): number
	local lastClaim = finite(input.LastClaimUTC, 0)

	if lastClaim <= 0 then
		return 1
	end

	local lastDay = DailyStreak.dayIndex(lastClaim)
	local today = DailyStreak.dayIndex(input.NowUTC)

	if today == lastDay + 1 then
		return math.max(finite(input.Streak, 0), 0) + 1
	end

	return 1
end

--[[
	WHAT A CLAIM RIGHT NOW WOULD DO. The server calls this and writes the result; nothing else decides.

	CLOCK_BEHIND IS THE ONE CASE THAT RESOLVES AGAINST THE PLAYER, and it is the only one where the
	generous answer is exploitable. A stored claim stamped LATER than `NowUTC` means either a Roblox
	server's clock disagreed with another's, or a profile crossed a rollback — and if that were treated
	as "a different day, therefore claimable", the same day pays out twice for as long as the skew
	lasts. Refusing costs the player at most one day's reward and self-heals the moment the clock
	catches up, because `LastClaimUTC` is returned UNCHANGED on this path.

	The refusal branches return the STORED streak rather than the prospective one, so a caller that
	writes `Result.Streak` back on every outcome — the obvious loop, and the one somebody will write —
	cannot corrupt a streak by refusing a claim.
]]
function DailyStreak.evaluate(input: Input, params: Params): Result
	local lastClaim = finite(input.LastClaimUTC, 0)
	local now = finite(input.NowUTC, 0)
	local storedStreak = math.max(finite(input.Streak, 0), 0)

	local held: Result = {
		Outcome = "ALREADY_CLAIMED_TODAY",
		Streak = storedStreak,
		CycleDay = cycleDayFor(storedStreak, #params.Rewards),
		RewardXP = 0,
		RewardCoins = 0,
		ClaimedAtUTC = lastClaim,
	}

	if lastClaim > now then
		-- Annotated local with a literal branch: the analyzer narrows a literal checked against a
		-- declared type and does NOT narrow a `::` cast over a union.
		local outcome: Outcome = "CLOCK_BEHIND"

		held.Outcome = outcome

		return held
	end

	if lastClaim > 0 and DailyStreak.dayIndex(lastClaim) == DailyStreak.dayIndex(now) then
		return held
	end

	local streak = streakAfter(input)
	local cycleDay = cycleDayFor(streak, #params.Rewards)
	local reward = rewardFor(cycleDay, params)
	local outcome: Outcome = "CLAIMED"

	return {
		Outcome = outcome,
		Streak = streak,
		CycleDay = cycleDay,
		RewardXP = reward.XP,
		RewardCoins = reward.Coins,
		ClaimedAtUTC = now,
	}
end

--[[
	THE SAME QUESTION, WITHOUT THE COMMITMENT — what the lobby button should say.

	It runs `evaluate` rather than reimplementing it, so the button and the server can never disagree
	about whether today is claimable. That is the same inversion `TrialAdmission` uses for the trial
	door: the client shows a hint, the server re-runs the identical module and decides.

	On a day that is already spent it reports the reward the player WILL get next — a preview of the
	next tier is a reason to come back, and a preview of a reward that cannot be taken is a button
	that lies.
]]
function DailyStreak.preview(input: Input, params: Params): Preview
	local result = DailyStreak.evaluate(input, params)

	if result.Outcome == "CLAIMED" then
		return {
			Claimable = true,
			Streak = result.Streak,
			CycleDay = result.CycleDay,
			RewardXP = result.RewardXP,
			RewardCoins = result.RewardCoins,
		}
	end

	local nextStreak = math.max(finite(input.Streak, 0), 0) + 1
	local cycleDay = cycleDayFor(nextStreak, #params.Rewards)
	local reward = rewardFor(cycleDay, params)

	return {
		Claimable = false,
		Streak = nextStreak,
		CycleDay = cycleDay,
		RewardXP = reward.XP,
		RewardCoins = reward.Coins,
	}
end

return DailyStreak
