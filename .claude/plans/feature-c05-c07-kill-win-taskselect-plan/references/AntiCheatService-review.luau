--!strict
-- Review of src/server/Services/AntiCheatService.luau — consulted by Phase 4's RequestKill handler.
-- Excerpts only.

-- src/server/Services/AntiCheatService.luau:10-19 — what it is and is not.
--[[
	It answers ONE question: has this player asked for this remote more often than a human could? It
	does NOT validate the request. Distance, line of sight, phase, cooldown and role all belong to the
	service that owns the mechanic.

	... a handler that consults Consume() and then does no validation of its own is NOT protected, and
	`check:ratelimit` — which is a text tripwire, by its own admission — will report it as clean.
]]
-- IMPORTANT: this is the split Phase 4 relies on. `check:ratelimit` going green on the new RequestKill
-- handler proves the limiter is CALLED, and nothing about the six conditions behind it. Those are
-- proven by `lune run tests/kill-validation.test.luau` and by the playtester's refusal probes.

-- src/server/Services/AntiCheatService.luau:106-133 — the entry point, and its NAME.
--[[
	The NAME of this function is load-bearing, not stylistic: `check-ratelimit.mjs` matches
	`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of an
	`.OnServerEvent:Connect(`.
]]
function AntiCheatService.Consume(player: Player, remoteName: string): boolean
	local now = os.clock()
	local bucket = bucketFor(player.UserId, remoteName, now)

	if bucket == nil then
		-- IMPORTANT: FAIL CLOSED. A remote with no budget in Config.AntiCheat.Budgets is REFUSED, not
		-- allowed. `RequestKill` already has a budget (Config.luau:166, Capacity 3 / RefillPerSecond
		-- 0.25), so Phase 4 adds no Config entry — but a future remote added without one is dead on
		-- arrival rather than unlimited, and the symptom is "the button does nothing".
		logRefusal(player, `{remoteName} (no budget declared)`, now)

		return Config.AntiCheat.AllowUnbudgetedRemote
	end

	local allowed, updated = TokenBucket.consume(bucket, now, Config.AntiCheat.DefaultCost)
	-- NOTE: the returned bucket is stored on BOTH paths. A refusal still refilled; discarding it would
	-- freeze the player's tokens at the moment of first refusal — a permanent mute.

	if not allowed then
		logRefusal(player, remoteName, now)
	end

	return allowed
end

-- src/server/Services/AntiCheatService.luau:21-27, and Config.luau:183-188
--[[
	LOG-ONLY, DELIBERATELY (C02; enforcement is C41)
	A refused request IS refused — Consume returns false and the handler returns early. What `LogOnly`
	governs is everything BEYOND refusal: kicking, throttling, flagging an account.
]]
-- IMPORTANT for the Phase 4 playtest: the burst probe (8 calls, expect 3 through) works TODAY. The
-- refusal is real; only the punishment is deferred. A quiet console is not evidence the limiter ran —
-- the evidence is the `[AntiCheat] Rate limit refused ... on RequestKill` line, throttled to one per
-- player per remote per LogThrottleSeconds (5).

-- src/server/Services/AntiCheatService.luau:135-138
local function onPlayerRemoving(player: Player)
	-- NOTE: buckets are dropped on disconnect, so a rejoin resets them. Recorded as an accepted Low in
	-- the C02–C04 plan; unchanged by this plan and not worth re-litigating here.
	buckets[player.UserId] = nil
	lastLoggedAt[player.UserId] = nil
end
