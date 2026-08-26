--!strict
--[[
	ProgressionService — the profile: load it, hold it, save it. (M9, C31, §6.6)

	WHAT IT OWNS. One session-locked profile per player, from join to leave, plus the single write path
	every other service must go through to change one. It owns the DATA; C32 owns the POLICY of what a
	round is worth, C33 the daily streak, C35 the gamepass cache.

	THE SECRET IS NOT IN HERE, AND ONE FIELD IS WORTH NAMING. `Stats.AswangRounds` and `AswangWins` are
	a history of how often this player drew the role. Server-only, like the rest of the profile — but
	unlike XP they would be a genuine leak if surfaced, so no attribute, no tag, and NO `leaderstats`
	FOLDER: `leaderstats` is the standard Roblox way to show a number and it replicates to every client
	by design.

	C32 ADDED THE DELIBERATE REMOTE THE LINE ABOVE PROMISED, AND IT SENDS A FIELD LIST RATHER THAN A
	PROFILE. `PushProfile` fires `ProfileUpdated` with `Types.ProfileSnapshot` — XP, level, the bar's
	two spans, coins, the equipped ids, the owned set and the daily preview. `Stats` is absent in full,
	not trimmed, so there is no field for the role history to arrive in. FireClient to one player,
	always; there is no FireAllClients path here and there must not be.

	NOTHING HERE TAKES A CLIENT VALUE — §6.6's fourth rule, and it is still true. `Award`, `BumpStat`,
	`SpendCoins`, `GrantCosmetic`, `SetEquipped` and `SetDaily` are called by server code with
	server-computed numbers; there is still no `OnServerEvent` handler in this file, which is why
	`check:ratelimit` has nothing to say about it. C33's `DailyService` and C34's `CosmeticsService`
	own the three request handlers and consult `AntiCheatService` before calling in here — that
	separation is the reason this file's one-way property survived those chunks.

	THE WRAPPER IS THIN ON PURPOSE. Every decision about SHAPE lives in
	`shared/pure/ProfileMigration.luau`, which runs under Lune and is tested exhaustively. What is left
	here is the part Lune cannot see: DataStore calls, player lifecycle, and the shutdown flush.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.pure.Cosmetics)
local DailyStreak = require(Shared.pure.DailyStreak)
local Enums = require(Shared.Enums)
local ProfileMigration = require(Shared.pure.ProfileMigration)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local XPCurve = require(Shared.pure.XPCurve)
local RoundService = require(script.Parent.RoundService)
local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)

--[[
	Vendored, and deliberately outside `src/` — see `vendor/README.md`. It is at
	`ServerScriptService.Packages`, a SIBLING of `Server`, so no client can require it and no gate in
	this repo has to grade someone else's Luau.
]]
local Packages = ServerScriptService:WaitForChild("Packages")
local ProfileStore = require(Packages:WaitForChild("ProfileStore"))

type Profile = ProfileMigration.Profile

local ProgressionService = {}

--[[
	FIRED WHEN A PLAYER'S PROFILE IS LOADED AND READABLE (C35), with the value of `FirstSeenUTC` from
	BEFORE this session stamped it.

	THE SECOND ARGUMENT IS THE WHOLE REASON THIS SIGNAL EXISTS rather than subscribers polling
	`GetProfile`. `startSession` stamps `FirstSeenUTC` for anyone who has none, so by the time any
	subscriber could read the live profile it already says "today" — and `Balik-Balik`, which asks
	whether today differs from the first day, could never be true for anybody. Passing the pre-stamp
	value is the only way a subscriber can tell a returning player from a new one.

	NOT FIRED when the load failed outright: there is no profile to read, and a subscriber that awarded
	on a nil would be awarding on a DataStore outage.
]]
ProgressionService.ProfileLoaded = Instance.new("BindableEvent")

--[[
	FIRED AFTER A STAT ACTUALLY MOVED (C35). `(player, statName)`.

	`BumpStat` is the single choke point every badge-gating counter passes through — `TasksDone` from
	the round's task system at the moment a task completed, `Rounds` and `AswangRounds` from `awardRound` at
	ENDING. One subscription here covers three of the five badges, which is why `BadgeService` does not
	subscribe to `PhaseChanged` alongside this service and hope the connections fire in the right
	order. Two services listening to one event and depending on which runs first is the shape of bug
	that only appears once the service list is reordered for an unrelated reason.

	AFTER the write, never before, and only when the write was not refused — a subscriber's whole job
	is to read the new value.

	IT CARRIES NO ROLE AND MUST NOT. `AswangRounds` is a stat NAME, not a role: it says this player has
	now been the Aswang some number of times in their life, and it is only ever bumped at ENDING where
	the reveal has already gone out. This is a server-side BindableEvent with no remote behind it.
]]
ProgressionService.StatChanged = Instance.new("BindableEvent")

--[[
	SERVER-ONLY STATE. Keyed by UserId, never replicated, never enumerated to a client.

	`sessions` holds the live ProfileStore profile object, not our table — `profile.Data` is the table.
	`readOnly` latches a player whose stored profile came from a NEWER schema than this server runs:
	we never touch their `Data`, so whatever ProfileStore writes back is byte-identical to what it
	read. See `ProfileMigration.migrate`'s REFUSED branch for why that is the only safe answer.
]]
local sessions: { [number]: any } = {}
local readOnly: { [number]: boolean } = {}
local store: any = nil

--[[
	IN-FLIGHT STARTS, WHICH `sessions` CANNOT REPRESENT. `sessions[userId]` is not written until
	`StartSessionAsync` has RETURNED, so for the whole duration of a slow start — a contested lock, or
	`SessionStartAttempts x SessionStartRetryDelay` of retries — a second entry point sees `nil` and
	would start a duplicate. ProfileStore answers that with `error("Profile is already loaded in this
	session")` (`vendor/ProfileStore.luau:1390`), and `startSession` runs under a bare `task.spawn`, so
	the thread would die between taking the lock and recording it — leaving a lock held with NO entry in
	`sessions`, which `PlayerRemoving` then cannot release. The next server that player joins waits it
	out.

	Today no interleaving reaches that: there is no yield between `Start`'s connect and its backfill
	loop. The guard is here because that is safety by accident of statement order, and the comment on
	the backfill claimed it was safety by the guard.
]]
local inFlight: { [number]: boolean } = {}

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

--[[
	The one down-remote this service owns, resolved once. Created by `Remotes` on the server at load,
	so there is no WaitForChild here and no window in which a push could find nothing to fire.
]]
local profileUpdatedRemote = Remotes.Get("ProfileUpdated")

--[[
	The catalogue, annotated so `Cosmetics`'s functions typecheck against it rather than against
	whatever the analyzer inferred from a Config table literal. It is DATA in `Config` and RULES in
	`shared/pure/Cosmetics` — see that module's header for why the split is drawn there.
]]
local CATALOGUE: { Cosmetics.Item } = Config.Cosmetics.Catalogue

-- The three parameter bundles the pure modules take, assembled from Config in one place each. Built
-- per call rather than hoisted: they are three table constructors on paths that run once per round or
-- once per button press, and a hoisted table is one a caller could mutate.
local function curve(): XPCurve.Curve
	return {
		Base = Config.Economy.XPPerLevel,
		Growth = Config.Economy.XPPerLevelGrowth,
		MaxLevel = Config.Economy.MaxLevel,
	}
end

local function rates(): XPCurve.Rates
	return {
		XPPerRound = Config.Economy.XPPerRound,
		XPWinBonus = Config.Economy.XPWinBonus,
		XPSurvivorEscapeBonus = Config.Economy.XPSurvivorEscapeBonus,
		XPPerKill = Config.Economy.XPPerKill,
		CoinsPerRound = Config.Economy.CoinsPerRound,
		CoinsWinBonus = Config.Economy.CoinsWinBonus,
	}
end

local function dailyParams(): DailyStreak.Params
	return { Rewards = Config.Daily.Rewards }
end

--[[
	LEVEL IS DERIVED FROM XP, AND STORED ANYWAY. The redundancy is deliberate and it is worth the line.

	`XPCurve.levelFor` is the authority — the stored `Level` is never read to decide anything, and this
	function overwrites it from `XP` after every award, so the two cannot drift. What the stored copy
	buys is the case where they SHOULD drift: retuning `Economy.XPPerLevel` at M12 moves everybody's
	level, and having the old value on disk is the difference between noticing that and not.

	It also grants whatever the new level has earned (§7: "levels unlock cosmetics"). Run on every
	award rather than only on a level-up, because `grantsAtLevel` answers "what should be owned at this
	level" rather than "what is new" — so a grant missed during a DataStore outage, or one added to the
	catalogue after a player passed its level, repairs itself on the next round instead of being lost.

	Writes `Data` directly rather than going through `GrantCosmetic`, because every caller has already
	passed the read-only latch and the finite guards by the time it gets here — and re-entering the
	public path would `Save()` once per granted item.
]]
local function syncLevel(data: Profile)
	local standing = XPCurve.levelFor(data.XP, curve())

	data.Level = standing.Level

	for _, id in Cosmetics.grantsAtLevel(CATALOGUE, standing.Level) do
		if data.Cosmetics.Owned[id] ~= true then
			data.Cosmetics.Owned[id] = true
		end
	end
end

-- `source` is `any`, so the cast always holds. Copying key-by-key rather than reassigning
-- `profile.Data` keeps the table identity ProfileStore was handed at session start.
local function copyInto(target: any, source: any)
	for key, value in source :: { [string]: any } do
		target[key] = value
	end
end

--[[
	`Save` on a MEANINGFUL CHANGE, which is §6.6's third rule and the one most often skipped. It does
	not mean "on every field write" — ProfileStore autosaves on its own schedule, and a `Save()` per XP
	point is a request budget spent on nothing. It means: after a change a player would be angry to
	lose. A round's award is one. A cosmetic purchase (C34) is one. A stat increment is not.
]]
local function saveNow(userId: number)
	local profile = sessions[userId]

	if profile ~= nil and profile:IsActive() then
		profile:Save()
	end
end

-- Declared ABOVE `startSession` rather than beside its other callers, because `startSession` calls it
-- for the C35 first-seen stamp — and a `local function` below its use site is not an upvalue at all
-- but an unknown global, which under `--!strict` the analyzer refuses outright rather than letting it
-- fail at runtime.
local function startSession(player: Player)
	local userId = player.UserId

	if inFlight[userId] or sessions[userId] ~= nil then
		return
	end

	inFlight[userId] = true

	local profile: any = nil

	for attempt = 1, Config.Profile.SessionStartAttempts do
		--[[
			`Cancel` is checked by ProfileStore while it waits on another server's lock. Without it, a
			player who joins and leaves inside the lock window leaves a request in flight that resolves
			into a session nobody ends.
		]]
		profile = store:StartSessionAsync(keyFor(player), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})

		if profile ~= nil or player.Parent ~= Players then
			break
		end

		warn(`[Progression] session start failed for {player.Name}, attempt {attempt}`)

		if attempt < Config.Profile.SessionStartAttempts then
			task.wait(Config.Profile.SessionStartRetryDelay)
		end
	end

	--[[
		A FAILED LOAD IS NOT FATAL AND MUST NOT BE. Kicking a player because a DataStore was briefly
		unavailable turns a Roblox outage into an empty server. They play; nothing saves; the warn says
		so. `GetProfile` returns nil and every caller already has to handle that, because a player can
		leave between the award and the write.
	]]
	if profile == nil then
		inFlight[userId] = nil
		warn(`[Progression] no profile for {player.Name} — nothing will be saved this session`)
		return
	end

	-- They left while we were loading. Release the lock immediately or the next server waits it out.
	if player.Parent ~= Players then
		inFlight[userId] = nil
		profile:EndSession()
		return
	end

	profile:AddUserId(userId)

	--[[
		MIGRATE FIRST, RECONCILE SECOND, AND THE ORDER IS THE WHOLE POINT.

		`Profile:Reconcile()` walks the v1 template and writes every missing key straight into `Data`,
		recursing into nested tables. Calling it BEFORE the version is classified defeats the read-only
		latch below completely: a v2 profile passing through this v1 server would be stamped with v1
		defaults before anything decided it must not be touched, and ProfileStore autosaves `Data` on
		its own schedule regardless of what we latch afterwards.

		The damage is additive, so nothing looks broken on the day. It lands on whoever writes v2,
		because an in-place migration is conventionally keyed on a field being ABSENT — re-materialising
		a deleted `Coins = 0` makes the v2 server skip its own migration and read that zero as
		authoritative. Months later it reads as "some players lost coins after the rollback", with
		nothing left to reconstruct the truth from.

		On the accepted path `Reconcile` is redundant anyway — `copyInto` fills every field the template
		would have — but it is kept as the belt to that braces: it is ProfileStore's own notion of a
		complete profile, and it costs nothing once the version is known to be one we own.
	]]
	local result = ProfileMigration.migrate(profile.Data)

	if result.Outcome == "REFUSED" then
		readOnly[userId] = true
		warn(
			`[Progression] {player.Name} has a v{result.FromVersion} profile and this server writes `
				.. `v{ProfileMigration.CURRENT_VERSION}. Read-only for this session — not reconciled, `
				.. `not migrated, not written.`
		)
	else
		profile:Reconcile()
		copyInto(profile.Data, result.Profile)
	end

	--[[
		ProfileStore ends a session on its own when another server steals the lock — which is what
		happens when a player rejoins elsewhere before this server has released. Kicking is correct
		and is the standard handling: the profile they are holding is no longer theirs to write.
	]]
	profile.OnSessionEnd:Connect(function()
		sessions[userId] = nil
		readOnly[userId] = nil
		inFlight[userId] = nil

		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Rejoin to continue.")
		end
	end)

	sessions[userId] = profile
	inFlight[userId] = nil

	--[[
		RECONCILE THE LEVEL WITH THE CURVE ON THE WAY IN (C32), before anything reads it.

		The stored `Level` was computed by whatever `Config.Economy` said the day it was written, and
		M12 retunes exactly those numbers. Without this a player who levelled under the old curve keeps
		a level the curve no longer agrees with — and, worse, never receives the cosmetics their real
		level has earned, because `grantsAtLevel` is only consulted on an award. Both repair here, once
		per session, for the cost of one arithmetic walk.

		Skipped for a read-only profile: `syncLevel` writes, and the whole point of the latch is that
		this server never touches `Data` for a schema it does not own.
	]]
	if not readOnly[userId] then
		syncLevel(profile.Data)
	end

	--[[
		AND THE FIRST PUSH. The lobby's level bar, coin count, daily button and cosmetics list all read
		one snapshot, so a player who joins and never finishes a round would otherwise see an empty
		progression panel until the next round ended.

		After `sessions[userId]` is set, because `PushProfile` reads through `GetProfile`, which reads
		that table. `task.spawn`ed so a `FireClient` cannot stall the session-start thread — this runs
		under `PlayerAdded`, and a player who leaves in the same frame is a live case.
	]]
	task.spawn(ProgressionService.PushProfile, player, nil)

	--[[
		THE FIRST-SEEN STAMP (C35), AND IT IS READ BEFORE IT IS WRITTEN.

		`Balik-Balik` is Appendix B's day-2 retention, and it asks one question: is today a different
		UTC day from the first day this game ever saw this player. Stamping first and firing afterwards
		would make the answer permanently "no" — every subscriber would read a profile that says the
		player was first seen moments ago. So the pre-stamp value is captured here and carried on the
		signal, and `BadgeRules` takes it as an argument rather than reading the profile at all.

		WRITTEN ONCE AND NEVER REWRITTEN. A field that moved forward on each login would answer "no"
		forever in a second way, and this one is not recoverable — there is no other record of when a
		player arrived.

		Skipped for a read-only profile, like `syncLevel` above and for the same reason: this server
		does not own that schema. The consequence is that a player whose profile was REFUSED gets no
		stamp this session and no `Balik-Balik` until they land on a server that understands their
		version, which is the correct trade against writing into a profile we cannot read properly.
	]]
	local data: Profile = profile.Data
	local firstSeenBefore = data.FirstSeenUTC

	if not readOnly[userId] and firstSeenBefore <= 0 then
		data.FirstSeenUTC = os.time()

		--[[
			SAVED IMMEDIATELY, like every other guarded write in this file. §6.6's "meaningful change"
			covers a once-ever field better than it covers almost anything else: lose this to a crash
			or a session steal inside the autosave window and the player's NEXT session re-stamps with
			a later date, so `Balik-Balik` — which IS Appendix B's day-2 retention — silently
			undercounts them, permanently and with no way to reconstruct the truth.

			The v1 profiles that arrive unstamped have the same gap once, before launch, and that is
			argued in `ProfileMigration`. This one would recur forever, and a retention dip with no
			cause in any diff is the most expensive kind of wrong number.
		]]
		saveNow(userId)
	end

	--[[
		`task.spawn` for the same reason `PushProfile` above is spawned: subscribers award badges,
		which yields on `UserHasBadgeAsync`, and a yield on the session-start thread would hold up the
		player's own load behind a Roblox web call.
	]]
	task.spawn(function()
		ProgressionService.ProfileLoaded:Fire(player, firstSeenBefore)
	end)

	if Config.Debug.VerboseLogging then
		print(
			`[Progression] {player.Name}: {result.Outcome} from v{result.FromVersion} -> L{(
				profile.Data :: Profile
			).Level}`
		)
	end
end

local function endSession(userId: number)
	local profile = sessions[userId]

	sessions[userId] = nil
	readOnly[userId] = nil
	inFlight[userId] = nil

	--[[
		`EndSession` SAVES AND THEN RELEASES THE LOCK, in that order, which is why a leaving player
		needs no explicit `Save` first. It is also why a read-only profile is safe to end: we never
		mutated `Data`, so the write is byte-identical to the read.
	]]
	if profile ~= nil then
		profile:EndSession()
	end
end

type StatName = "Rounds" | "Survived" | "AswangRounds" | "AswangWins" | "Kills" | "TasksDone"

--[[
	READ, AND ONLY READ. Returns the LIVE table, not a copy, so it is cheap — but that makes it a third
	write path if anyone treats it as one, and it consults neither the read-only latch nor `Award`'s
	finite guard.

	`local p = GetProfile(player); p.Coins += price` is the natural line for C34 to write. It compiles,
	it runs, and it silently writes into a profile this server has latched read-only. **Currency,
	stats, cosmetics and the daily stamp go through `Award`, `BumpStat`, `SpendCoins`,
	`GrantCosmetic`, `SetEquipped` and `SetDaily`; nothing else.** Every one of them re-checks the
	latch. `IsReadOnly` below is how a caller that genuinely needs to branch finds out, rather than
	discovering it by writing.

	Nil is a normal answer, not an error: a DataStore outage, a player mid-load, or a player who has
	already left all produce one.
]]
function ProgressionService.GetProfile(player: Player): Profile?
	local profile = sessions[player.UserId]

	return if profile ~= nil then profile.Data else nil
end

--[[
	Whether this player's profile came from a schema this server does not understand, and is therefore
	being held without writing. C33/C34/C35 should refuse a purchase or a claim rather than take a
	payment that will never be saved — a silent no-op is worse here than a visible refusal.
]]
function ProgressionService.IsReadOnly(player: Player): boolean
	return readOnly[player.UserId] == true
end

--[[
	THE ONLY WRITE PATH FOR CURRENCY, and the enforcement point for §6.6's fourth rule.

	Every argument is computed on the server. NO CLIENT VALUE REACHES THIS FUNCTION — not through a
	remote, not through an attribute, not laundered through a "requested amount". The validation below
	is therefore not defending against a player; it is defending against a bug in C32 writing a NaN or
	a negative into a table that then fails every subsequent DataStore write for that player, silently,
	forever.

	Returns whether anything was written, so a caller can log a refusal instead of assuming.
]]
function ProgressionService.Award(
	player: Player,
	xp: number,
	coins: number,
	reason: string
): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	--[[
		FINITE, NOT MERELY NON-NaN. `x >= 0 and x < math.huge` rejects NaN (which fails every
		comparison), negatives, and INFINITY — the case a `~= itself` test misses entirely, because
		`math.floor(math.huge)` is `inf` rather than an error. An infinite field cannot be encoded as
		JSON, so it makes every later DataStore write for this player fail silently and permanently,
		which is precisely the outcome this guard is here to prevent.
	]]
	if not (xp >= 0 and xp < math.huge) or not (coins >= 0 and coins < math.huge) then
		warn(
			`[Progression] refused a malformed award to {player.Name} ({reason}): {xp} xp, {coins} c`
		)
		return false
	end

	local data: Profile = profile.Data

	data.XP += math.floor(xp)
	data.Coins += math.floor(coins)

	syncLevel(data)
	saveNow(userId)

	if Config.Debug.VerboseLogging then
		print(`[Progression] {player.Name} +{xp} xp +{coins} coins ({reason}) -> L{data.Level}`)
	end

	return true
end

--[[
	SPEND (C34). The mirror of `Award`, and the asymmetry between them is deliberate.

	`Award` cannot fail on the arithmetic — a bad number is refused and logged. A SPEND can, and its
	failure is the entire security property: it returns false when the player cannot afford it, and
	the caller must not deliver the goods on a false. `CosmeticsService` grants the item only after
	this returns true, in that order, so a refused spend cannot leave a granted cosmetic behind.

	THE AMOUNT IS NOT A CLIENT VALUE. `pure/Cosmetics.evaluatePurchase` reads the price out of
	`Config.Cosmetics.Catalogue` and returns it; the request that started this carries an id and
	nothing else. There is no number on the wire for a compromised client to shrink.
]]
function ProgressionService.SpendCoins(player: Player, amount: number, reason: string): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	-- Same finite test as `Award` — see its comment on why infinity is the case that matters. A
	-- negative spend would be an award through the wrong door, so it is refused rather than clamped.
	if not (amount >= 0 and amount < math.huge) then
		warn(`[Progression] refused a malformed spend by {player.Name} ({reason}): {amount}`)

		return false
	end

	local data: Profile = profile.Data
	local cost = math.floor(amount)

	if data.Coins < cost then
		return false
	end

	data.Coins -= cost

	saveNow(userId)

	if Config.Debug.VerboseLogging then
		print(`[Progression] {player.Name} -{cost} coins ({reason})`)
	end

	return true
end

--[[
	GRANT A COSMETIC (C34). Idempotent, and bounded.

	Idempotent because `grantsAtLevel` answers "what should be owned at this level" rather than "what
	is new", so this is called with ids the player may already have on every single award. Bounded
	because `ProfileMigration.ownedFrom` caps a stored inventory at `MAX_OWNED_COSMETICS` on the way
	in, and a write path that could exceed it would produce a profile that silently loses entries the
	next time it is loaded.

	The id is checked against the catalogue rather than trusted, so a caller cannot write a key that
	`Cosmetics.find` will never resolve — an unresolvable id is an inventory entry nothing can equip
	and nothing can explain.
]]
function ProgressionService.GrantCosmetic(player: Player, id: string): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	if Cosmetics.find(CATALOGUE, id) == nil then
		warn(`[Progression] refused a grant of unknown cosmetic "{id}" to {player.Name}`)

		return false
	end

	local data: Profile = profile.Data

	if data.Cosmetics.Owned[id] == true then
		return false
	end

	data.Cosmetics.Owned[id] = true

	saveNow(userId)

	return true
end

--[[
	CLAIM §9.2's GROUP JOIN REWARD, ONCE, EVER (C39).

	TEST-AND-SET IN ONE CALL, and that is the whole reason it is a setter here rather than two lines in
	`CommunityService`. The claim path yields on `Player:IsInGroup` — a Roblox web call — and a player
	who presses the button twice has two threads in flight across that yield. Read-then-write split
	across the two files would let both threads see `false` and both pay, which is the classic double
	spend and is worth 250 coins per press.

	This function does not yield, so the read and the write happen in one resumption and the second
	caller sees `true`. The caller must pay ONLY on a `true` return, in that order — `CommunityService`
	does, and its comment says why.

	Returns false for an unclaimed reward on a read-only profile too. That is correct rather than
	unfortunate: a latched profile cannot record the claim, so paying would grant coins that vanish at
	the next login and re-arm the button forever.
]]
function ProgressionService.ClaimGroupReward(player: Player): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	local data: Profile = profile.Data

	if data.GroupRewardClaimed then
		return false
	end

	data.GroupRewardClaimed = true

	-- §6.6's "save on a meaningful change". A one-time reward is the definition of one: losing this
	-- write to a crash re-arms a button that has already paid.
	saveNow(userId)

	return true
end

--[[
	EQUIP (C34). The three-branch write, and the branches are why this is not a table index.

	`Cosmetics.Equipped` is a RECORD with three named fields, not a dictionary, so `equipped[slot]`
	does not typecheck under `--!strict` — and the natural workaround is a cast, which would let a
	slot string that matches no field write nothing and report success. Three explicit branches make
	an unknown slot a `return false` that a caller can see.

	The slot is not a client value: `pure/Cosmetics.evaluateEquip` reads it off the catalogue entry, so
	a client cannot name an item in one slot and a slot in another.
]]
function ProgressionService.SetEquipped(player: Player, slot: string, id: string): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	local equipped = (profile.Data :: Profile).Cosmetics.Equipped

	if slot == "Skin" then
		equipped.Skin = id
	elseif slot == "Lantern" then
		equipped.Lantern = id
	elseif slot == "DeathFX" then
		equipped.DeathFX = id
	else
		warn(`[Progression] refused an equip into unknown slot "{slot}" for {player.Name}`)

		return false
	end

	saveNow(userId)

	return true
end

--[[
	THE DAILY STAMP (C33). Written only after `pure/DailyStreak.evaluate` has said a claim happened.

	BOTH FIELDS MOVE TOGETHER OR NEITHER DOES, which is why this is one call rather than two setters.
	A streak advanced without its timestamp is a streak that advances again on the next button press;
	a timestamp advanced without its streak silently resets a week. `DailyStreak` returns both from one
	evaluation and this writes both from one call, so the two cannot drift apart in a caller's `if`.
]]
function ProgressionService.SetDaily(player: Player, lastClaimUTC: number, streak: number): boolean
	local userId = player.UserId
	local profile = sessions[userId]

	if profile == nil or readOnly[userId] then
		return false
	end

	if
		not (lastClaimUTC >= 0 and lastClaimUTC < math.huge)
		or not (streak >= 0 and streak < math.huge)
	then
		warn(`[Progression] refused a malformed daily write for {player.Name}`)

		return false
	end

	local daily = (profile.Data :: Profile).Daily

	daily.LastClaimUTC = math.floor(lastClaimUTC)
	daily.Streak = math.floor(streak)

	saveNow(userId)

	return true
end

--[[
	THE ONE PLACE A PROFILE REACHES A CLIENT (C32/C33/C34), AND IT SENDS A FIELD LIST.

	`Types.ProfileSnapshot` is the contract and its header is where the reasoning lives; the short
	version is that `PlayerProfile.Stats` holds `AswangRounds` and `AswangWins`, so the payload is
	BUILT rather than trimmed and there is no field for that history to arrive in.

	FIRECLIENT, TO ONE PLAYER, ALWAYS. Every field describes the receiver. A broadcast would hand eight
	clients eight players' levels and owned sets, which is enough to follow one person across rounds —
	so `ProfileUpdated` has no FireAllClients call site anywhere in this repo and must not acquire one.

	BUILT AS A TYPED LOCAL, not inline: `FireClient` takes `...any`, so an inline literal is checked
	against nothing at all. The annotation catches a wrong type and a missing field — but NOT an extra
	one, which is the leak shape. Adding a field here is a decision to review by hand.

	NOT CALLED FROM `Award`, deliberately. Each of the three request paths — a round's award, a daily
	claim, a cosmetic transaction — is a transaction of several writes, and pushing after each write
	would send two or three snapshots for one player action and leave the HUD animating a number that
	is already stale. Every caller pushes once, at the end, which is also the only point at which
	`lastAward` is known.
]]
function ProgressionService.PushProfile(player: Player, lastAward: Types.RoundAward?)
	local data = ProgressionService.GetProfile(player)

	if data == nil then
		return
	end

	local standing = XPCurve.levelFor(data.XP, curve())
	local preview = DailyStreak.preview({
		LastClaimUTC = data.Daily.LastClaimUTC,
		Streak = data.Daily.Streak,
		NowUTC = os.time(),
	}, dailyParams())

	-- A COPY, not the live table. `GetProfile` returns the profile itself, and handing the live
	-- inventory to `FireClient` would let a later grant mutate a table already queued for
	-- serialisation — a race with no symptom other than an occasional wrong shop. Shallow is enough:
	-- the values are booleans.
	local ownedCopy: { [string]: boolean } = table.clone(data.Cosmetics.Owned)

	local payload: Types.ProfileSnapshot = {
		XP = data.XP,
		Level = standing.Level,
		XPIntoLevel = standing.XPIntoLevel,
		XPForNextLevel = standing.XPForNextLevel,
		Progress = standing.Progress,
		Coins = data.Coins,
		Equipped = {
			Skin = data.Cosmetics.Equipped.Skin,
			Lantern = data.Cosmetics.Equipped.Lantern,
			DeathFX = data.Cosmetics.Equipped.DeathFX,
		},
		Owned = ownedCopy,
		Daily = {
			Claimable = preview.Claimable,
			Streak = preview.Streak,
			CycleDay = preview.CycleDay,
			RewardXP = preview.RewardXP,
			RewardCoins = preview.RewardCoins,
		},
		GroupRewardClaimed = data.GroupRewardClaimed,
		LastAward = lastAward,
	}

	profileUpdatedRemote:FireClient(player, payload)
end

-- Stat bookkeeping. No `Save` — see `saveNow`'s comment on what "meaningful" means.
function ProgressionService.BumpStat(player: Player, stat: StatName, amount: number)
	local userId = player.UserId
	local profile = sessions[userId]

	-- Same finite test as `Award` — see its comment on why infinity is the case that matters.
	if profile == nil or readOnly[userId] or not (amount >= 0 and amount < math.huge) then
		return
	end

	local data: Profile = profile.Data

	data.Stats[stat] += math.floor(amount)

	-- After the write, so a subscriber reading `GetProfile().Stats` sees the new total rather than
	-- the one it was called about.
	ProgressionService.StatChanged:Fire(player, stat)
end

--[[
	Called from `ShutdownFlush` on `BindToClose`. Ends every live session, which saves each one.
	SEQUENTIAL AND YIELDING ON PURPOSE — see `ShutdownFlush.flushAll`.
]]
function ProgressionService.FlushAll()
	for userId in sessions do
		endSession(userId)
	end
end

--[[
	SUBSCRIBE, NEVER SET. `RoundService` owns the phase (§6.4) and this service is one of eight that
	listen. The edge points that way for a second reason too: it is why the shutdown flush goes through
	`ShutdownFlush` rather than RoundService calling into here — the reverse require would close a cycle.
]]
--[[
	THE ROUND'S AWARD (C32, §4.8's end screen), AND THE REASON IT MAY READ THE ROLE.

	C31 paid a flat participation XP here and its comment held the line that made that necessary: "the
	moment the award is role-conditional, the XP number itself becomes a derived hint — a player
	comparing their end-screen total against a friend's would learn something the round never told
	them." §4.8's award table is role-conditional in three of its four terms, so C32 does not avoid
	that warning, it DISCHARGES it, and the discharge is a matter of timing rather than of trimming.

	THE ORDER INSIDE `enterEnding` IS THE WHOLE ARGUMENT, and it is worth being precise about because
	it is the only thing making this safe:

	    setPhase(ENDING)  ->  PhaseChanged fires  ->  THIS RUNS
	    Remotes.Get("RoundEnded"):FireAllClients({ ..., AswangUserId = ... })

	So this handler runs microseconds BEFORE the reveal is broadcast, in the same frame — and that
	ordering does not matter, because what makes the award safe is not that the reveal has already
	landed but that it CANNOT NOT LAND. `enterEnding` broadcasts unconditionally and is the only
	path into ENDING; a player cannot read their XP total, compare it with anyone, and act on the
	difference before a reveal that arrives in the same tick on the same wire.

	`RoleIsPublic` is nevertheless computed rather than assumed, and it is `false` for a round that
	reached ENDING with no Aswang recorded. `pure/XPCurve.awardFor` then collapses the award to flat
	participation, identical for all eight players — the C31 behaviour, exactly. That branch is
	defensive rather than reachable today (`state.AswangUserId` survives both abort paths and is
	cleared only in `enterIdle`), and it is written because being wrong about it is the one failure
	this game does not survive.

	LOBBY AND SPECTATOR ARE THE EXCLUSIONS, not "alive" — someone who died in the third minute played
	the round and is a GHOST at ENDING. A SPECTATOR joined after the draw and did not.
]]
local function awardRound()
	local aswangUserId = RoundService.GetAswangUserId()
	local roleIsPublic = aswangUserId ~= nil
	--[[
		ANNOTATED ON ARRIVAL, and the annotation is not decoration. `GetLastResult` returns
		`Types.RoundResult` — a literal union — and a literal union does NOT survive the `require`
		boundary on its own: without this line the analyzer reads it as
		`string | string | string | string` and refuses the `AwardInput` below, reporting the error in
		THIS file about a value born in another. The scalar re-annotation is the whole fix; the same
		trap inside a LIST has no fix at all and needs a narrowing function instead — see
		`.claude/lessons/pure-module-unions-widen-in-lists.md`.
	]]
	local result: XPCurve.RoundResult = RoundService.GetLastResult()
	local kills = RoundService.GetAswangKills()

	for _, player in Players:GetPlayers() do
		local playerState = RoundService.GetPlayerState(player)

		if playerState == Enums.PlayerState.Lobby or playerState == Enums.PlayerState.Spectator then
			continue
		end

		local wasAswang = roleIsPublic and player.UserId == aswangUserId
		local survived = playerState == Enums.PlayerState.Alive

		local award = XPCurve.awardFor({
			Result = result,
			RoleIsPublic = roleIsPublic,
			WasAswang = wasAswang,
			Survived = survived,
			Kills = if wasAswang then kills else 0,
		}, rates())

		--[[
			THE STATS, AND WHY THEY ARE WRITTEN HERE RATHER THAN AT THE MOMENT THEY HAPPEN.

			`Rounds` and `Survived` are facts about the whole round and only exist once it is over.
			`AswangRounds` and `AswangWins` are the two fields this file's header names as the genuine
			leak risk — so they are written in the one place where the role is already public, and
			`PushProfile` has no field to carry them out in. Nothing reads them yet; C35's `Balik-Balik`
			badge and C41's analytics are what they are for.

			`Kills` and `TasksDone` are deliberately NOT written here: they are per-event counts that
			only the gameplay services can see, and inferring them from a round summary
			would be a second, wrong source of truth. They stay at zero until whoever needs them wires
			the call at the event.
		]]
		ProgressionService.BumpStat(player, "Rounds", 1)

		if survived and not wasAswang then
			ProgressionService.BumpStat(player, "Survived", 1)
		end

		if wasAswang then
			ProgressionService.BumpStat(player, "AswangRounds", 1)

			if result == Enums.RoundResult.AswangWins or result == Enums.RoundResult.Timeout then
				ProgressionService.BumpStat(player, "AswangWins", 1)
			end
		end

		local written = ProgressionService.Award(player, award.XP, award.Coins, "round")

		--[[
			PUSHED EVEN WHEN THE WRITE WAS REFUSED, and the two refusal cases differ in what the player
			sees.

			A READ-ONLY LATCH still has a loaded profile, so this pushes: the snapshot carries the
			REAL totals (which did not move) beside the award that was earned, and the client renders
			"+90" over a bar that did not fill. That is the honest picture of a server that cannot save,
			and it beats either lying about the total or showing nothing.

			NO PROFILE AT ALL — a DataStore outage, or a player still loading — pushes nothing, because
			`PushProfile` has no profile to build a snapshot from and returns early. Their end screen
			shows the reveal without a breakdown, which is the same thing every player saw before C32
			and is the only answer available.

			Either way the log line below names it, and neither is a mistake worth a `warn`: both are
			Roblox being unavailable, which `startSession` has already warned about once.
		]]
		ProgressionService.PushProfile(player, {
			XP = award.XP,
			Coins = award.Coins,
			Lines = award.Lines,
		})

		if not written and Config.Debug.VerboseLogging then
			print(
				`[Progression] {player.Name}'s round award was not banked (no profile / read-only)`
			)
		end
	end
end

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Ending then
		awardRound()
	end
end

function ProgressionService.Init()
	--[[
		`New` is cheap and does no I/O, so it belongs in Init: the store must exist before any other
		service's `Start` can call `GetProfile`. The TEMPLATE is the pure module's — one definition of
		a fresh player, shared by ProfileStore's own reconcile and by our migration.
	]]
	store = ProfileStore.New(Config.Profile.StoreName, ProfileMigration.template())

	table.clear(sessions)
	table.clear(readOnly)
	table.clear(inFlight)
end

function ProgressionService.Start()
	--[[
		§6.6's third rule: save on meaningful change, ON LEAVE, and on `BindToClose`. `PlayerRemoving`
		covers the second; this covers the third. Registered FIRST, before any player can be loaded,
		so a server that dies during startup still flushes whatever it managed to load.
	]]
	ShutdownFlush.register("Progression", ProgressionService.FlushAll)

	--[[
		`DataStoreState` is `"NotReady" | "NoInternet" | "NoAccess" | "Access"`, and data persists ONLY
		on `"Access"`. Anything else means ProfileStore is quietly using mock storage — which behaves
		perfectly within one session and loses everything between them. Without this line the symptom
		is "rejoin loses XP", the obvious reading is a bug in the flush, and the cause is a checkbox.

		This is a `warn`, not an `error`. A local Studio session without API access is a legitimate way
		to test everything except persistence, and refusing to start would make the rest of the game
		untestable to fix a problem that is not a code problem.

		`task.spawn` because the state may still be `"NotReady"` at `Start()` — ProfileStore settles it
		with its own request, and reading it on the bootstrap thread would cry wolf on every launch.
	]]
	task.spawn(function()
		if ProfileStore.DataStoreState ~= "Access" then
			warn(
				`[Progression] DataStoreState is "{ProfileStore.DataStoreState}" — NOTHING WILL `
					.. `PERSIST. In Studio: Game Settings > Security > Enable Studio Access to API `
					.. `Services, and the place must be published.`
			)
		elseif Config.Debug.VerboseLogging then
			print("[Progression] DataStore access confirmed — profiles will persist.")
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(startSession, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		endSession(player.UserId)
	end)

	--[[
		Anyone who joined before this ran. The same backfill `RoundService.Start` does and for the same
		reason: connecting first means the window cannot drop a player, and the price is that someone
		arriving inside it is handled twice.

		The idempotence guard lives INSIDE `startSession` now, against `inFlight` as well as `sessions`
		— a check here on `sessions` alone would read `nil` for a start that is under way but has not
		returned yet, which is the window that matters.
	]]
	for _, player in Players:GetPlayers() do
		task.spawn(startSession, player)
	end

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
end

return ProgressionService
