--!strict
--[[
	REVIEW — src/server/Services/AntiCheatService.luau
	Read 2026-08-12 for the C09-C12 plan. Unmodified by this plan; consulted by one new handler.

	Phase 1 adds a budget and Phase 3 adds the only new `OnServerEvent` in C09-C12.
]]

-- src/server/Services/AntiCheatService.luau:95-105 (header of Consume)
-- "The NAME of this function is load-bearing, not stylistic: `check-ratelimit.mjs` matches
--  `AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 CHARACTERS of an
--  `.OnServerEvent:Connect(`."
-- IMPORTANT FOR STEP 3.2: the new `RequestTimingStop` handler must sit BESIDE the existing
-- `RequestTaskProgress` handler in `TaskService.Start`, with `Consume` as its first statement. A
-- handler that IS limited but calls Consume through a helper 200 lines away reads as unguarded and
-- fails the build. TaskService:759-772 and MonsterService both spell this out at the connect site.

-- src/server/Services/AntiCheatService.luau:106-135
function AntiCheatService.Consume(player: Player, remoteName: string): boolean
	local bucket = bucketFor(player.UserId, remoteName, now)

	if bucket == nil then
		logRefusal(player, `{remoteName} (no budget declared)`, now)
		return Config.AntiCheat.AllowUnbudgetedRemote
	end

	local allowed, updated = TokenBucket.consume(bucket, now, Config.AntiCheat.DefaultCost)
end
-- IMPORTANT — FAIL CLOSED. `AllowUnbudgetedRemote = false`, so a remote declared in `Remotes.luau`
-- with no `Config.AntiCheat.Budgets` entry is REFUSED OUTRIGHT at runtime. The symptom is that the
-- handler simply never runs: no error, no analyze failure, no check failure — just a feature that
-- does nothing. This is precisely why Phase 1 gates Step 1.4 on
-- `lune run tests/anti-cheat-budgets.test.luau` (which pins both directions of the name sets) rather
-- than on `check:remotes` (which reports an unwired remote as a passing NOTE).
-- NOTE: "Store the returned bucket on BOTH paths. A refusal still refilled, and discarding it here
-- would freeze the player's tokens at the moment they were first refused — a permanent mute."

-- src/server/Services/AntiCheatService.luau:266-271 (via Config)
	LogOnly = true,
-- IMPORTANT: C02 LOGS, C41 ENFORCES. So the limiter currently REFUSES the request (Consume returns
-- false and the handler returns early) but never kicks. For Phase 3 that is the right posture: the
-- timing stop is the one remote in C09-C12 where spamming has a theoretical payoff — enough stops per
-- sweep and one lands inside the zone by arithmetic rather than skill — and the limiter is the second
-- line of defence, not the first.
-- NOTE: THE FIRST LINE IS THE MISS-RESETS-TO-ZERO RULE, and it is worth stating because it is what
-- makes the limiter sufficient rather than merely present. A burst of five stops containing one hit
-- and four misses ends at ZERO hits, not one. Spamming is actively counterproductive, which is a
-- stronger property than "rate-limited" and is the same shape as C08's "spamming gains nothing".

-- Budget sizing, for Step 1.4 (`RequestTimingStop = { Capacity = 5, RefillPerSecond = 1 }`):
-- NOTE: an honest player at a 1.8s sweep fires ~0.55/s against a sustained 1/s, so a legitimate run
-- of three hits across three sweeps never throttles. Capacity 5 covers a player mashing through one
-- sweep plus a reconnect retry. Compare `RequestTaskProgress` at 12 / 6 per second — deliberately far
-- looser, because a presence heartbeat is CONTINUOUS and idempotent while a stop is DISCRETE and
-- changes state every time it lands.
-- IMPORTANT: Config's own budget header says "Tune these LOOSER than legitimate play, never tighter.
-- A limiter that refuses a real player is a gameplay bug that presents as lag." Phase 1's new
-- invariant in `tests/anti-cheat-budgets.test.luau` pins exactly that against `TimingBarPeriod`, so
-- lowering the period at M12 cannot silently start throttling honest players.

-- src/server/Services/AntiCheatService.luau (what it does NOT cover)
-- IMPORTANT for Phase 4: the fetch pickup has NO REMOTE. It is proximity, evaluated on the server's
-- own 4 Hz tick, so `check:ratelimit` has nothing to inspect and there is nothing to spam. That is a
-- feature of the design rather than a gap in the coverage — the cheapest handler to secure is the one
-- that does not exist. The same is true of Phase 6's gate: reaching it is walking, not a request.
-- NOTE: `Config.Round.RespawnCooldown`'s comment records the mirror-image case — `Humanoid.Died` is a
-- client-triggerable state change that is NOT a remote, so AntiCheat never sees it and
-- `check:ratelimit` structurally cannot cover it. Proximity is safe because it needs a character in a
-- place; a reset is not, because it needs nothing.
return nil
