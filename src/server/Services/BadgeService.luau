--!strict
--[[
	BadgeService — Awards the 5 funnel badges. (C35, Appendix B)

	Milestone: M9
	Spec: docs/MVP-SPEC.md Appendix B, §10

	WHAT THIS IS FOR, because it is not a reward system. Badge award counts are publicly readable
	through the Roblox API, permanently, for free — which is exactly how Appendix C reconstructed the
	competitor's funnel from the outside. Mirroring our own funnel in badges buys a retention dashboard
	that no analytics outage can lose and no client can forge, and §10's launch gate reads directly off
	it: `First Task / Welcome` must clear 50%, against the 20.1% that killed them. (V01 removed the
	thing that increments `TasksDone`, so this ratio is FLAT until V4 rebinds the badge to searching.
	The badge id is a live Roblox award and cannot be renamed without a migration — see V01's log.)

	SERVER-SIDE ONLY, AND NOTHING HERE TAKES A CLIENT VALUE. There is no remote in this file and no
	`OnServerEvent` handler — a client that could ask for a badge could forge the one dataset the
	project steers by. Every award is decided from `ProgressionService`'s profile and the server clock.

	THE RULES ARE NOT IN HERE. `shared/pure/BadgeRules` owns which counter maps to which badge and the
	day comparison behind `Balik-Balik`, because those five booleans are permanent — Roblox has no
	un-award — and `tests/badge-rules.test.luau` is the only thing that can prove them before they
	ship. This file is the plumbing: when to ask, and how to award without hammering the web API.

	IT DOES NOTHING UNTIL A HUMAN CREATES THE BADGES. `Config.Badges` ships as five zeros, and C35's
	brief splits that way on purpose: 🧍 creates them in the Creator Hub, 🤖 wires them. An id of 0 is
	skipped silently rather than erroring, so the game is fully playable before the badges exist —
	`Start` warns once, with the list, so "the badges never award" has a visible cause.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
	ALIASED, because Roblox's own service is also called `BadgeService` and this file is too. Left as
	`BadgeService` the local would shadow the module table below and every `AwardBadge` call would go
	to whichever one happened to be in scope — which the analyzer would not catch, since both are
	tables with methods.
]]
local RobloxBadges = game:GetService("BadgeService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BadgeRules = require(Shared.pure.BadgeRules)
local DailyStreak = require(Shared.pure.DailyStreak)
-- One direction only, as everywhere else in this folder: ProgressionService requires RoundService and
-- nothing here, so this edge cannot close a load-order cycle.
local ProgressionService = require(script.Parent.ProgressionService)

local BadgeService = {}

--[[
	WHAT THIS SERVER BELIEVES THE PLAYER ALREADY HAS. `userId -> badgeKey -> true`.

	A CACHE OF OUR OWN CALLS, not of Roblox's state, and it only ever grows. Awarding a badge twice is
	harmless on Roblox's side — the second call is a no-op — but `AwardBadge` and `UserHasBadgeAsync`
	are both web requests against a per-server budget, and a player standing on a task point generates
	a `StatChanged` every time a task completes. Without this, a full server would re-ask Roblox about
	five badges per player per task.

	Cleared on leave. It is a session cache and must not outlive the session: a rejoining player gets a
	fresh `UserHasBadgeAsync` on their first evaluation, which is the one place it is worth paying for.
]]
local known: { [number]: { [string]: boolean } } = {}

--[[
	`Profile.FirstSeenUTC` AS IT WAS BEFORE THIS SESSION STAMPED IT, per player.

	This is the value `Balik-Balik` is decided from, and it exists only for an instant: `startSession`
	stamps the field for anyone who has none, so the live profile says "today" from that point on. It
	arrives on `ProfileLoaded`'s second argument and is kept here for the rest of the session, because
	`StatChanged` evaluations later in the round need the same answer and can no longer read it.
]]
local firstSeenAtLoad: { [number]: number } = {}

--[[
	BADGE AWARDS CURRENTLY IN FLIGHT, keyed `"<userId>:<badgeKey>"`.

	`known` is not enough on its own, because it is written AFTER the web call returns and `evaluate`
	runs concurrently. `awardRound` bumps two or three stats for one player in the same frame, each
	firing `StatChanged`, each spawning its own `evaluate` — so two threads reach the same badge,
	both pass the `known` test, and both yield on `UserHasBadgeAsync`.

	The cost is not a double award; Roblox no-ops the second. It is that the second call returns
	`false` WITHOUT erroring, which lands in the "Roblox refused" warn below — the one diagnostic that
	is supposed to mean "this badge is misconfigured in the Creator Hub". Left unguarded it would fire
	for nearly every player's first completed round, and the single signal distinguishing a broken
	setup from a working one would be buried in noise.

	Claimed before the first yield and released on every exit path.
]]
local inFlight: { [string]: boolean } = {}

--[[
	AWARDS ONE BADGE, ONCE, AND NEVER THROWS.

	Both calls are HTTP requests to Roblox and both fail in normal operation — a moderation action, a
	web outage, a badge deleted in the Creator Hub. A badge failing to award must never take the
	surrounding round logic with it, so everything here is inside `pcall` and every failure is a warn.
	Losing one badge award costs a row in a dashboard; an error thrown from a `StatChanged` handler
	would unwind whatever bumped the stat.

	`UserHasBadgeAsync` FIRST, so a returning veteran does not spend an `AwardBadge` call per session
	on five badges they earned months ago.
]]
local function award(player: Player, key: string, badgeId: number)
	local userId = player.UserId
	local cache = known[userId]

	if cache == nil or cache[key] then
		return
	end

	-- Claimed BEFORE the first yield, which is the whole point — see `inFlight`. A second thread for
	-- the same badge coalesces here instead of racing to a duplicate `AwardBadge`.
	local ticket = `{userId}:{key}`

	if inFlight[ticket] then
		return
	end

	inFlight[ticket] = true

	local hasOk, has = pcall(function()
		return RobloxBadges:UserHasBadgeAsync(userId, badgeId)
	end)

	if not hasOk then
		inFlight[ticket] = nil
		warn(`[Badges] could not check "{key}" for {player.Name}: {has}`)
		return
	end

	--[[
		The player left while we were asking. `known` is cleared on leave, so writing into a stale
		table here would leak one entry per departure — and awarding a badge to someone who is gone is
		a wasted call rather than a wrong one, so both halves stop here.
	]]
	if known[userId] == nil then
		inFlight[ticket] = nil
		return
	end

	if has then
		known[userId][key] = true
		inFlight[ticket] = nil
		return
	end

	local awardOk, granted = pcall(function()
		return RobloxBadges:AwardBadge(userId, badgeId)
	end)

	inFlight[ticket] = nil

	if not awardOk then
		warn(`[Badges] could not award "{key}" to {player.Name}: {granted}`)
		return
	end

	--[[
		`AwardBadge` returns FALSE without erroring in the ordinary cases — the badge is disabled in
		the Creator Hub, the place does not belong to the badge's game, the player already had it. Not
		caching a false is what makes the next evaluation retry, which is correct for a transient
		failure and merely wasteful for a permanent one.
	]]
	if not granted then
		warn(
			`[Badges] Roblox refused "{key}" for {player.Name} — is the badge enabled and on THIS game?`
		)
		return
	end

	if known[userId] ~= nil then
		known[userId][key] = true
	end

	if Config.Debug.VerboseLogging then
		print(`[Badges] awarded "{key}" to {player.Name}`)
	end
end

--[[
	ASKS THE RULES, THEN AWARDS WHAT THEY SAY. Safe to call as often as anything changes.

	Yields — `award` makes web calls — so every caller spawns it. It must never run on a thread that
	something else is waiting on.
]]
local function evaluate(player: Player)
	local userId = player.UserId
	local profile = ProgressionService.GetProfile(player)

	--[[
		NO PROFILE, NO BADGES, INCLUDING `Welcome`. A nil profile means the DataStore did not answer,
		and `Welcome` is the funnel's denominator — awarding it to a player whose stats this server
		cannot read would put someone in the denominator who can never enter any numerator, and every
		conversion rate in the dashboard would read low for a reason that is not the game.

		They are re-evaluated the moment a profile does load, because that fires `ProfileLoaded`.
	]]
	if profile == nil then
		return
	end

	if known[userId] == nil then
		known[userId] = {}
	end

	local earned = BadgeRules.earned({
		Stats = profile.Stats,
		TodayIndex = DailyStreak.dayIndex(os.time()),
		FirstSeenDayIndex = DailyStreak.dayIndex(firstSeenAtLoad[userId] or 0),
	})

	for _, key in BadgeRules.IDS do
		if not (earned :: any)[key] then
			continue
		end

		local badgeId = (Config.Badges :: any)[key]

		-- The 🧍 half of C35 has not been done yet. Skipped rather than warned per call, so a game
		-- running before the badges exist does not fill the output with one line per task completed.
		if type(badgeId) ~= "number" or badgeId <= 0 then
			continue
		end

		award(player, key, badgeId)
	end
end

--[[
	A PLAYER'S PROFILE IS READABLE. Carries the pre-stamp `FirstSeenUTC`, which is the only moment
	`Balik-Balik` can be decided — see `firstSeenAtLoad`.
]]
local function onProfileLoaded(player: Player, firstSeenBefore: number)
	firstSeenAtLoad[player.UserId] = firstSeenBefore

	task.spawn(evaluate, player)
end

--[[
	A STAT MOVED. Three of the five badges are a counter crossing 1, and this is every path that can
	move one: `TasksDone` from TaskService at the moment a task advances, `Rounds` and `AswangRounds`
	from `awardRound` at ENDING.

	SUBSCRIBING HERE RATHER THAN TO `PhaseChanged` IS DELIBERATE. Both this service and
	ProgressionService would be listening to that event, and `First Round` would then depend on which
	of the two connected first — a dependency on service list order that nothing tests and that breaks
	the first time the list is reordered for an unrelated reason.

	`First Blood` rides `AswangRounds`, which is bumped inside `awardRound` at ENDING — after the round
	is decided and in the same frame as the reveal that `enterEnding` broadcasts unconditionally. The
	badge is a lifetime fact ("has been the Aswang at least once"), the toast is local to the player
	who already knows their own role, and nothing about it is readable by another client mid-round.
]]
local function onStatChanged(player: Player, _stat: string)
	task.spawn(evaluate, player)
end

function BadgeService.Init()
	table.clear(known)
	table.clear(firstSeenAtLoad)
	table.clear(inFlight)
end

function BadgeService.Start()
	--[[
		ONE WARN AT STARTUP, NAMING THE MISSING IDS. Without it the failure is silent and looks exactly
		like a game nobody plays: every funnel stage reads zero in the Creator Hub, and the obvious
		reading of that is a retention problem rather than five unfilled config values.
	]]
	local missing: { string } = {}

	for _, key in BadgeRules.IDS do
		local badgeId = (Config.Badges :: any)[key]

		if type(badgeId) ~= "number" or badgeId <= 0 then
			table.insert(missing, key)
		end
	end

	if #missing > 0 then
		warn(
			`[Badges] {#missing} of {#BadgeRules.IDS} badge ids are unset ({table.concat(
				missing,
				", "
			)}) `
				.. `— those badges will NOT award. Create them in the Creator Hub and put the ids in `
				.. `Config.Badges (C35).`
		)
	end

	ProgressionService.ProfileLoaded.Event:Connect(onProfileLoaded)
	ProgressionService.StatChanged.Event:Connect(onStatChanged)

	Players.PlayerRemoving:Connect(function(player)
		known[player.UserId] = nil
		firstSeenAtLoad[player.UserId] = nil

		-- Any ticket still held by a call that is mid-yield for this player. `award` re-checks
		-- `known[userId]` after each yield and bails, so the ticket would otherwise be released by a
		-- thread that has already decided to do nothing — or, on the `known == nil` path, leak.
		for _, key in BadgeRules.IDS do
			inFlight[`{player.UserId}:{key}`] = nil
		end
	end)
end

return BadgeService
