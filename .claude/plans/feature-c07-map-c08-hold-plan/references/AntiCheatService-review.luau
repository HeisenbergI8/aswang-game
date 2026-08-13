--!strict
-- REVIEW: src/server/Services/AntiCheatService.luau:9-27, 88-104, 106-127 (excerpts)
--
-- Read for the one call Step 4.1 makes and the two things this service explicitly does NOT do.

	--[[
		It answers ONE question: has this player asked for this remote more often than a human could? It
		does NOT validate the request. Distance, line of sight, phase, cooldown and role all belong to
		the service that owns the mechanic, because only that service knows what "valid" means.
	]]
-- IMPORTANT: the split Step 4.1 has to honour. Consume answers "may this player speak"; evaluatePresence
-- answers "is what they said true". Both are required and neither is optional.

	--[[
		a handler that consults Consume() and then does no validation of its own is NOT protected, and
		`check:ratelimit` — which is a text tripwire, by its own admission — will report it as clean.
		That gap is what `exploit-auditor` is for.
	]]
-- IMPORTANT, and it is why the plan says green on check:ratelimit means very little for this handler.
-- RequestTaskProgress is trivially compliant with the tripwire — Consume is the first line — and its
-- actual safety is that `tick` re-derives elapsed time and distance from server state. No check in this
-- repo can see that. exploit-auditor is mandatory on this diff and review-gate.mjs names it for
-- src/server/** anyway.

	--[[
		The NAME of this function is load-bearing, not stylistic: `check-ratelimit.mjs` matches
		`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of an
		`.OnServerEvent:Connect(`.
	]]
function AntiCheatService.Consume(player: Player, remoteName: string): boolean    -- :104
-- NOTE: the exact signature Step 4.1 calls, with the remote name as a string literal matching the
-- Config.AntiCheat.Budgets key. The 1200-character envelope is what forces the guard inline at the
-- connect site rather than inside notePresence.

	if bucket == nil then
		-- FAIL CLOSED. A remote with no budget is refused.
		return Config.AntiCheat.AllowUnbudgetedRemote                              -- :113
	end
-- NOTE: RequestTaskProgress HAS a budget (Config.luau:204), so this path is not reachable for it. It
-- matters only as the failure mode of a misspelled remote name: the requests are refused outright and
-- the symptom is "tasks never work", which is loud. Preferable to the alternative.

local function logRefusal(player: Player, remoteName: string, now: number)        -- :69
	warn(`[AntiCheat] Rate limit refused {player.Name} ({player.UserId}) on {remoteName}`)
-- NOTE: UNGATED by VerboseLogging, and throttled to one line per player per remote per
-- Config.AntiCheat.LogThrottleSeconds. IMPORTANT for the highest-frequency remote in the game — an
-- exploiter looping RequestTaskProgress would otherwise produce its own denial of service in the
-- output window. Already handled here; nothing for TaskService to add.
-- NOTE the log carries a remote name and a UserId, never a role. Safe. The same rule constrains
-- Step 4.1's verbose refusal print, which must be re-read at C12 when the verdict set gains a value
-- that names a role.

	-- C02 LOGS. C41 ENFORCES.
	LogOnly = true,
-- NOTE: a refused request IS refused — Consume returns false and the handler returns early. LogOnly
-- governs only what happens BEYOND refusal (kicking, flagging), none of which exists. So "a client
-- spamming RequestTaskProgress gains nothing" is true today via two independent mechanisms: the bucket
-- refuses the excess, and the tick loop makes the accepted ones worth nothing extra.
