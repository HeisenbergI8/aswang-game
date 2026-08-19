--!strict
--[[
	ProgressionService — the profile: load it, hold it, save it. (M9, C31, §6.6)

	WHAT IT OWNS. One session-locked profile per player, from join to leave, plus the single write path
	every other service must go through to change one. It owns the DATA; C32 owns the POLICY of what a
	round is worth, C33 the daily streak, C35 the gamepass cache.

	THE SECRET IS NOT IN HERE, AND ONE FIELD IS WORTH NAMING. `Stats.AswangRounds` and `AswangWins` are
	a history of how often this player drew the role. Server-only, like the rest of the profile — but
	unlike XP they would be a genuine leak if surfaced, so no remote in this file, no attribute, no
	tag, and NO `leaderstats` FOLDER: `leaderstats` is the standard Roblox way to show a number and it
	replicates to every client by design. C33 surfaces progression through a deliberate remote.

	NOTHING HERE TAKES A CLIENT VALUE — §6.6's fourth rule. `Award` and `BumpStat` are called by
	server code with server-computed numbers; there is no `OnServerEvent` handler in this file, which
	is why `check:ratelimit` has nothing to say about it. If that ever changes, the handler consults
	`AntiCheatService` first and the remote is declared in `Remotes.luau` — both, or neither.

	THE WRAPPER IS THIN ON PURPOSE. Every decision about SHAPE lives in
	`shared/pure/ProfileMigration.luau`, which runs under Lune and is tested exhaustively. What is left
	here is the part Lune cannot see: DataStore calls, player lifecycle, and the shutdown flush.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local ProfileMigration = require(Shared.pure.ProfileMigration)
local Types = require(Shared.Types)
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

-- `source` is `any`, so the cast always holds. Copying key-by-key rather than reassigning
-- `profile.Data` keeps the table identity ProfileStore was handed at session start.
local function copyInto(target: any, source: any)
	for key, value in source :: { [string]: any } do
		target[key] = value
	end
end

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

	if Config.Debug.VerboseLogging then
		print(`[Progression] {player.Name}: {result.Outcome} from v{result.FromVersion}`)
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
	it runs, and it silently writes into a profile this server has latched read-only. **Currency and
	stats go through `Award` and `BumpStat`; nothing else.** `IsReadOnly` below is how a caller that
	genuinely needs to branch finds out, rather than discovering it by writing.

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

	saveNow(userId)

	if Config.Debug.VerboseLogging then
		print(`[Progression] {player.Name} +{xp} xp +{coins} coins ({reason})`)
	end

	return true
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
local function onPhaseChanged(phase: Types.RoundPhase)
	if phase ~= Enums.RoundPhase.Ending then
		return
	end

	--[[
		A FLAT AWARD, AND C32 REPLACES IT. §4.8's real table — win bonus, survivor escape bonus, the
		Aswang's own split — is C32's work and belongs in a pure `XPCurve`-shaped module where it can
		be tested. What C31 owns is that the number reaches the profile and survives a rejoin.

		IT READS `GetPlayerState` AND NEVER THE ROLE, and that line is worth holding: the moment the
		award is role-conditional, the XP number itself becomes a derived hint — a player comparing
		their end-screen total against a friend's would learn something the round never told them.

		LOBBY IS THE EXCLUSION, not "alive" — someone who died in the third minute played the round and
		is a GHOST at ENDING. A SPECTATOR joined after the draw and did not.
	]]
	for _, player in Players:GetPlayers() do
		local state = RoundService.GetPlayerState(player)

		if state == Enums.PlayerState.Lobby or state == Enums.PlayerState.Spectator then
			continue
		end

		ProgressionService.BumpStat(player, "Rounds", 1)
		ProgressionService.Award(
			player,
			Config.Economy.XPPerRound,
			Config.Economy.CoinsPerRound,
			"round"
		)
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
