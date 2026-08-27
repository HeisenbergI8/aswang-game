--!strict
--[[
	REVIEW — src/server/Services/AntiCheatService.luau:94-133, 140-146
	Read for V03 because both new handlers must consult it, and because its fail-closed behaviour
	changes what a missing Config budget MEANS.
]]

--[[
	IMPORTANT — THE NAME IS LOAD-BEARING (AntiCheatService.luau:99-104):

	  "`check-ratelimit.mjs` matches `AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within
	   1200 characters of an `.OnServerEvent:Connect(`. Renaming it to something outside that set turns
	   every handler in the game into an unguarded one as far as the gate is concerned, silently and
	   all at once."

	V03 calls `AntiCheatService.Consume(player, "RequestSearch")` — matching spelling, first line of
	the handler. No wrapper, no helper, no `guard()` indirection: a helper that called Consume would
	move the matched text away from the Connect and fail the check while being perfectly correct.
]]
function AntiCheatService.Consume(player: Player, remoteName: string): boolean -- :106
	local bucket = bucketFor(player.UserId, remoteName, now)

	if bucket == nil then
		-- IMPORTANT THIS IS THE LINE THAT CHANGES WHAT A MISSING BUDGET MEANS.
		-- "FAIL CLOSED. A remote with no budget is refused. The alternative means any remote added
		--  without a Config entry is silently unlimited, which is the exact state C02 exists to
		--  prevent."
		--
		-- So forgetting Config.AntiCheat.Budgets.RequestSearch does NOT ship unlimited searching — it
		-- ships a game where NOBODY CAN SEARCH, for everyone, with only a warn line to say so. Since
		-- searching is the only activity in v2.0 (§4.4), that is a total failure that looks like a
		-- map problem. `Config.AntiCheat.AllowUnbudgetedRemote` is the switch and it is false.
		--
		-- This is why the budgets land in Phase 2 (before any handler exists) rather than beside the
		-- handlers in Phase 3, and why Step 2.3's Verify is the budget suite.
		logRefusal(player, `{remoteName} (no budget declared)`, now)

		return Config.AntiCheat.AllowUnbudgetedRemote
	end

	local allowed, updated = TokenBucket.consume(bucket, now, Config.AntiCheat.DefaultCost)

	-- NOTE "Store the returned bucket on BOTH paths. A refusal still refilled, and discarding it here
	-- would freeze the player's tokens at the moment they were first refused — a permanent mute."
	-- Nothing for V03 to do; noted because it is why a refused search self-heals rather than latching.

-- NOTE The refusal log "names a remote name and a UserId, never a role" (:89). V03 adds no logging of
-- its own on the refusal path, so nothing here widens.

--[[
	NOTE — CLEANUP IS ALREADY HANDLED (AntiCheatService.luau:133-146).

		local function onPlayerRemoving(player: Player)
			buckets[player.UserId] = nil
			lastLoggedAt[player.UserId] = nil
		end

	Keyed by UserId, so V03's two new budgets need no cleanup of their own — they are entries inside
	the same per-player table. V03 still connects its OWN PlayerRemoving for `holds` and
	`foundByPlayer`, which are its tables and nobody else's.
]]

--[[
	IMPORTANT — WHAT THIS SERVICE DOES NOT DO, and V03 must not assume otherwise.

	It is a TOKEN BUCKET AND NOTHING ELSE. It does not validate distance, phase, liveness or target;
	CLAUDE.md is explicit that check:ratelimit and check:secrecy are "text tripwires on obvious shapes"
	that "cannot follow data flow". Every gate in `evaluateSearch` — phase, PlayerState, RangeStuds,
	opened, occupied — is V03's own work and none of it is covered by a check script. That is the half
	`exploit-auditor` is for, and the chunk's own Verify line hands it the right question.

	Concretely: a compromised client can fire RequestSearch at 0.3/s forever, legitimately, and the
	only thing standing between that and a free layout probe is that the remote NAMES NO CONTAINER and
	the server refuses anything outside Config.Search.RangeStuds of the sender's own character.
]]
