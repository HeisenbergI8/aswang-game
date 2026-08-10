--!strict
--[[
	AntiCheatService — the rate-limit core (C02).

	Every OnServerEvent handler in this game calls Consume() before it does anything else, and
	`check:ratelimit` fails the build if one does not. This chunk is built BEFORE any handler exists so
	that every later handler is born compliant rather than retrofitted — retrofitting a limiter means
	auditing handlers that already work, which is the audit nobody finishes.

	WHAT THIS SERVICE IS, AND IS NOT
	--------------------------------
	It answers ONE question: has this player asked for this remote more often than a human could? It
	does NOT validate the request. Distance, line of sight, phase, cooldown and role all belong to the
	service that owns the mechanic, because only that service knows what "valid" means. A limiter that
	tried to validate would need to know everything and would be wrong about most of it.

	The split matters for reading the code too: a handler that consults Consume() and then does no
	validation of its own is NOT protected, and `check:ratelimit` — which is a text tripwire, by its own
	admission — will report it as clean. That gap is what `exploit-auditor` is for.

	LOG-ONLY, DELIBERATELY (C02; enforcement is C41)
	------------------------------------------------
	A refused request IS refused — Consume returns false and the handler returns early. What `LogOnly`
	governs is everything BEYOND refusal: kicking, throttling, flagging an account. None of that exists
	yet and none of it should, because kicking on a limit with no real data behind the numbers kicks
	real players on bad connections, and a false kick is unrecoverable. C41 flips the flag with a
	playtest's worth of evidence behind it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TokenBucket = require(Shared.pure.TokenBucket)
local Types = require(Shared.Types)

local AntiCheatService = {}

-- SERVER-ONLY state. buckets[userId][remoteName] -> bucket. Never replicated, never attributed.
local buckets: { [number]: { [string]: Types.TokenBucketState } } = {}

-- lastLoggedAt[userId][remoteName] -> os.clock() of the last warn for that pair. An exploiter firing a
-- thousand requests a second would otherwise produce a thousand warn() calls a second, which is its
-- own denial of service and buries every other line in the output window.
local lastLoggedAt: { [number]: { [string]: number } } = {}

local function bucketFor(userId: number, remoteName: string, now: number): Types.TokenBucketState?
	local budget = Config.AntiCheat.Budgets[remoteName]

	if budget == nil then
		return nil
	end

	local playerBuckets = buckets[userId]

	if playerBuckets == nil then
		playerBuckets = {}
		buckets[userId] = playerBuckets
	end

	local bucket = playerBuckets[remoteName]

	if bucket == nil then
		bucket = TokenBucket.new(budget.Capacity, budget.RefillPerSecond, now)
		playerBuckets[remoteName] = bucket
	end

	return bucket
end

local function logRefusal(player: Player, remoteName: string, now: number)
	local playerLogs = lastLoggedAt[player.UserId]

	if playerLogs == nil then
		playerLogs = {}
		lastLoggedAt[player.UserId] = playerLogs
	end

	local last = playerLogs[remoteName]

	if last ~= nil and now - last < Config.AntiCheat.LogThrottleSeconds then
		return
	end

	playerLogs[remoteName] = now

	-- UNGATED by VerboseLogging, matching RoundService's treatment of a dropped round result: this is a
	-- fault, not routine tracing, and a published server is exactly where it matters. Safe to log —
	-- a remote name and a UserId, never a role.
	warn(`[AntiCheat] Rate limit refused {player.Name} ({player.UserId}) on {remoteName}`)
end

--[[
	The one entry point. Returns true when the request may proceed.

		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

	The NAME of this function is load-bearing, not stylistic: `check-ratelimit.mjs` matches
	`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of an
	`.OnServerEvent:Connect(`. Renaming it to something outside that set turns every handler in the game
	into an unguarded one as far as the gate is concerned, silently and all at once.
]]
function AntiCheatService.Consume(player: Player, remoteName: string): boolean
	local now = os.clock()
	local bucket = bucketFor(player.UserId, remoteName, now)

	if bucket == nil then
		-- FAIL CLOSED. A remote with no budget is refused. The alternative means any remote added
		-- without a Config entry is silently unlimited, which is the exact state C02 exists to prevent.
		logRefusal(player, `{remoteName} (no budget declared)`, now)

		return Config.AntiCheat.AllowUnbudgetedRemote
	end

	local allowed, updated = TokenBucket.consume(bucket, now, Config.AntiCheat.DefaultCost)

	-- Store the returned bucket on BOTH paths. A refusal still refilled, and discarding it here would
	-- freeze the player's tokens at the moment they were first refused — a permanent mute.
	local playerBuckets = buckets[player.UserId]

	if playerBuckets then
		playerBuckets[remoteName] = updated
	end

	if not allowed then
		logRefusal(player, remoteName, now)
	end

	return allowed
end

local function onPlayerRemoving(player: Player)
	buckets[player.UserId] = nil
	lastLoggedAt[player.UserId] = nil
end

function AntiCheatService.Init()
	table.clear(buckets)
	table.clear(lastLoggedAt)
end

function AntiCheatService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return AntiCheatService
