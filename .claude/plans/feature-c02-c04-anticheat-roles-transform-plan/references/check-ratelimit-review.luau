--!strict
--[[
	REVIEW — .claude/scripts/check-ratelimit.mjs

	Read because Step 6.3 is gated on it and because two of its details dictate how the handler is
	WRITTEN, not merely whether it passes.
]]

-- IMPORTANT — the guard pattern. `AntiCheatService.Consume` matches; a function named anything outside
-- {Allow, Check, Consume, RateLimit, Permit} does not. Renaming Consume later turns EVERY handler in
-- the game into an unguarded one as far as this gate is concerned — silently, and all at once.
local GUARDED = "/\\bAntiCheat\\w*[.:]\\s*(Allow|Check|Consume|RateLimit|Permit)\\b/"

-- IMPORTANT — the scan window is 1200 characters from the `.OnServerEvent:Connect(` match, not the
-- matching `end)`. A guard placed after a long validation block may fall outside it. This is why the
-- plan puts `AntiCheatService.Consume` as the FIRST statement of the handler body.
local WINDOW = 1200

-- NOTE — the path filter is `src/server/` only, and it is exercised by the self-test rather than
-- assumed. Client listeners (.OnClientEvent) are never flagged.

--[[
	IMPORTANT — quoted from the header, because it is the honest statement of what a green check means:

		"The check is deliberately shallow. It asks ONE question — does this handler consult AntiCheat at
		 all — because that is the question a static reader can answer honestly. Whether the validation
		 is CORRECT is `exploit-auditor`'s job, and pretending a grep could decide it would be worse than
		 not checking."

	And:

		"It currently passes vacuously: no OnServerEvent handler exists yet. That is the intended shape
		 of a good gate — it costs nothing today and fails the moment M2 wires the first remote without a
		 limit."

	VERIFIED: as of C01 there is still no OnServerEvent handler anywhere in src/. Step 6.3 is the first,
	which is why it is the step gated on this check and why Phase 3's C02 gate cannot be.
]]

-- The waiver form, if a handler ever genuinely needs one:
--   ev.OnServerEvent:Connect(function(p) -- ratelimit-ok: read-only ping
-- This plan uses none.
