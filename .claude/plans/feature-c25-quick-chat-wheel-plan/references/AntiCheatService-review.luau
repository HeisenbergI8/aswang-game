--!strict
--[[
	REVIEW — src/server/Services/AntiCheatService.luau:94-133

	One entry point, and two properties of it that C25's handler depends on.
]]

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
	-- ...
end

--[[
	IMPORTANT — THE 1200-CHARACTER WINDOW CONSTRAINS HOW C25'S HANDLER IS WRITTEN.

	The plan's Step 3.2 handler is long: a typeof narrowing, a phrase lookup, a phase gate and two
	state gates, all before it reaches resolution. Every one of those is inside the connect callback,
	and the `Consume` call is its first statement — so the distance is fine as planned. But if
	implementation refactors the gates into a `validateRequest` helper and leaves only the helper call
	in the handler, `check:ratelimit` will still pass (the Consume is inside the window) while the
	structure has quietly moved. Worse in the other direction: moving `Consume` INTO such a helper
	pushes it outside the window and turns the handler unguarded as far as the gate can see.

	Keep `Consume` as the first statement of the connect callback. GhostService.luau:694-701 states
	this rule at its own handler and it is the shape to copy.

	NOTE — this service answers ONE question and its header is explicit that it "does NOT validate the
	request. Distance, line of sight, phase, cooldown and role all belong to the service that owns the
	mechanic." Everything C25 cares about — line of sight, range, phase, player state, phrase validity
	— is QuickChatService's job. Consuming a token proves nothing about a request's legitimacy.

	IMPORTANT — the header's next paragraph is the one that matters most for a 🔒 chunk:
	  "a handler that consults Consume() and then does no validation of its own is NOT protected, and
	   `check:ratelimit` — which is a text tripwire, by its own admission — will report it as clean.
	   That gap is what `exploit-auditor` is for."
	C25's plan names exploit-auditor as mandatory for exactly this reason, with a scoped brief rather
	than "audit the diff".

	NOTE — `Config.AntiCheat.LogOnly` is still true and `tests/anti-cheat-budgets.test.luau` pins it
	that way until C41. So a rate-limited quick chat is REFUSED (Consume returns false, handler
	returns) but produces no further consequence. Correct for C25 and worth knowing during playtesting:
	a player mashing the wheel sees messages silently not appear, with a throttled warn in the server
	log as the only evidence.

	QUESTION — resolved: does the existing budget (Capacity 4, RefillPerSecond 0.5) fit the wheel?
	Yes — one press per 2s sustained, four in a burst. The plan's Phase 2 adds two relationship
	assertions rather than changing the numbers: the burst must cover a short exchange, and the refill
	must not out-pace `MessageLifetimeSeconds`. Note that the limiter is the SECOND line of defence
	for the accusation phrase, not the first — line of sight is.
]]
