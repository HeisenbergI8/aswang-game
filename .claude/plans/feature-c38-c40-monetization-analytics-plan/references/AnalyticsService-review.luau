--!strict
--[[
	REVIEW — src/server/Services/AnalyticsService.luau:1-19 (the ENTIRE file)

	The other C01-era stub. Nineteen lines, one TODO. Reviewed in full for the same reason as
	MonetizationService: there is nothing here to summarise, and the TODO names the funnel correctly.
]]

--!strict
--[[
	AnalyticsService — Emits the gameplay funnel events.

	Milestone: M11
	Spec: docs/MVP-SPEC.md
]]

local AnalyticsService = {}
-- IMPORTANT: THE NAME COLLIDES WITH A REAL ROBLOX SERVICE. `game:GetService("AnalyticsService")`
--            exists and is exactly what this module must call
--            (.luau-defs/globalTypes.d.luau:9229-9235). Inside this file the two names would be
--            indistinguishable at a glance, and writing `AnalyticsService:LogCustomEvent` against
--            our own table is a nil-call at runtime IN A SERVICE WHOSE JOB IS TO BE SILENT WHEN IT
--            WORKS — so the failure would look like "the dashboard is empty", not like an error.
--            The plan binds Roblox's to `RobloxAnalytics`.

-- TODO(M11): emit the events listed in docs/MVP-SPEC.md Appendix B.
-- NOTE: fifteen names, all on one spec line (:694). The plan hand-copies them into
--       `server/pure/AnalyticsEvents.luau` as a literal union so a typo is an analyze error, and
--       pins the set in both directions under Lune. A misspelled event name has NO symptom — the
--       dashboard shows zero, which is indistinguishable from an event that never fires.

-- The funnel that matters: joined -> reached ACTIVE round -> completed a round
-- -> returned on day 2. Track win rate per side from day one or you cannot balance.
-- NOTE: implemented as `LogFunnelStepEvent` with four contiguous 1-based steps, which is how Roblox
--       models a funnel. Step 4 cannot be observed from a session event — no server sees a return
--       while it happens — so it rides on `ProgressionService.ProfileLoaded`, whose second argument
--       is the PRE-STAMP `FirstSeenUTC`. C35 added that signal for `Balik-Balik` and it is the
--       correct precedent here.
-- NOTE: "win rate per side" needs no sixteenth event — `round_ended (winner, ...)` segmented by
--       winner IS the win rate, and Appendix A's target is that neither side exceeds 60%.

function AnalyticsService.Init() end

function AnalyticsService.Start() end

return AnalyticsService
-- NOTE: `AnalyticsService` is FIRST in `init.server.luau`'s SERVICE_ORDER (:21), ahead of
--       AntiCheat and Progression, and `RoundService` is last. So the module reference every
--       emitting service holds resolves long before any event fires.

-- IMPORTANT: THIS FILE MUST NEVER GAIN A CLIENT EGRESS, and Phase 3 Step 3.2 makes that mechanical
--            rather than aspirational — check-secrecy Rule 6 refuses `Remotes`, `ReplicatedStorage`,
--            `FireClient`, `FireAllClients` and `:Fire(` in this one file.
--
--            The reason is that two Appendix B events legitimately carry things that must not reach
--            a client: `role_assigned (role)` IS the secret (§6.2), and `player_killed
--            (secondsIntoRound, wasIsolated)` is Amendment A3's death oracle in a table. Both are
--            safe going to Roblox's telemetry backend and fatal one line lower in a broadcast — and
--            the two statements read alike.
--
-- IMPORTANT: rules 0-4 of check-secrecy scan Fire* payloads, attributes and tags — NOT general
--            server code. So without Rule 6 this file's most dangerous line would pass
--            `npm run verify` GREEN. It is not a leak; it is simply unwatched. That gap is what the
--            C02-C04 plan flagged twice and left for C40.

-- QUESTION: Rule 6 forbids naming `ReplicatedStorage`, but funnel step 4 wants
--           `shared/pure/DailyStreak.dayIndex` for UTC-day arithmetic. Genuine collision. Resolve by
--           moving the `ProfileLoaded` subscription into ProgressionService (which already requires
--           DailyStreak) — NOT by waiving the rule, which would reopen the whole egress surface for
--           a date comparison. Follow Up #5.
