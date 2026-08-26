--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau:1-17, :26-32, :48-62, :80-82, :89-106, :715-723

	The reference service shape, read before adding two. Three things here bind this plan: phase
	ownership, the require-cycle warning, and the ABSENCE of a round-start timestamp.
]]

-- src/server/Services/RoundService.luau:9-12
	DESIGN RULE: nothing outside this module mutates the phase. Other services
	subscribe via RoundService.PhaseChanged. Round logic is the single most
	bug-prone area of a game like this; funnelling every transition through one
	SetPhase() function is what keeps it debuggable.
-- IMPORTANT: C38 SUBSCRIBES, IT DOES NOT SET. `MonetizationService` connects to `PhaseChanged` for
--            the ENDING offer push and reads `GetPhase()` in its two handlers. It never calls
--            `setPhase`, and the ENDING gate is a READ of server-owned state, which is exactly what
--            makes §8.4's "never mid-round" structural rather than conventional.

-- src/server/Services/RoundService.luau:26-32
-- One direction only. RoleService must NEVER require RoundService back: a require cycle errors at
-- load, init.server.luau swallows it into a single warn, and the server sits in IDLE forever looking
-- exactly like "nobody has joined yet".
local RoleService = require(script.Parent.RoleService)
-- A LEAF. It requires nothing but Config, so it cannot participate in a require cycle...
local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)
-- IMPORTANT: THE TRAP C40 WALKS INTO. RoundService must call `AnalyticsService.Emit` for
--            `round_started`, `player_killed` and `round_ended`; AnalyticsService wants the phase
--            for `player_left`. That is a cycle, and its symptom is not an error message — it is a
--            server that boots into IDLE and stays there, which reads as "not enough players".
--
--            Broken the `ShutdownFlush` way: AnalyticsService does not require RoundService.
--            RoundService PUSHES the phase via `AnalyticsService.SetPhase` on its existing
--            transition. The pushed copy labels a metric and decides nothing.
-- NOTE: AnalyticsService requiring ProgressionService (for `ProfileLoaded`) is fine — Progression
--       does not require Analytics. The cycle is specifically with RoundService.

-- src/server/Services/RoundService.luau:48-62
-- SERVER-ONLY state. Never replicate this table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	AswangUserId = nil :: number?,
	TasksCompleted = 0,
	GateOpen = false,
	DealtInSurvivors = 0,
}
-- IMPORTANT: THERE IS NO ROUND-START TIMESTAMP. `PhaseEndsAt` is PER-PHASE (:721 sets it to
--            `os.clock() + duration` on every transition), so deriving "seconds into the round" from
--            it happens to work today and silently starts measuring something else the first time a
--            phase duration is tuned — which is M12, the one milestone where these numbers are what
--            you are reading.
--
--            C40 needs `secondsIntoRound` for `task_completed` and `player_killed`, so Phase 3 adds
--            `RoundStartedAt` and sets it in `enterActive`.
-- IMPORTANT: `AswangUserId` lives in this table and the table is never replicated. Nothing C40 adds
--            may put it on a payload; the analytics `role_assigned` event is emitted from
--            RoleService with the role VALUE, never the roster.

-- src/server/Services/RoundService.luau:80-82, :89-106
RoundService.PhaseChanged = Instance.new("BindableEvent")
function RoundService.GetPhase(): RoundPhase
function RoundService.GetAswangUserId(): number?
-- NOTE: `PhaseChanged` is a BindableEvent, so a subscriber receives the phase as a plain value
--       across the boundary — binding it to a `RoundPhase`-typed local needs a re-annotation under
--       --!strict. Comparing it directly to `Enums.RoundPhase.Ending` is fine.
-- IMPORTANT: `GetAswangUserId` exists and is server-only. C40 must NOT use it to enrich an analytics
--            payload with the Aswang's identity on a non-role event — `player_killed` is logged
--            against the VICTIM, and adding a killer field there would recreate exactly what
--            check-secrecy's `killer\w*` prefix rule was widened to catch on broadcasts.

-- src/server/Services/RoundService.luau:715-723
local function setPhase(newPhase: RoundPhase, duration: number?)
	...
	RoundService.PhaseChanged:Fire(newPhase, duration)
-- NOTE: fired SYNCHRONOUSLY. Phase 4's ENDING subscriber therefore runs inside the transition, which
--       is why its per-player ownership loop is `task.spawn`ed — `OwnsGamepass` yields on a cache
--       miss, and eight web calls inline would hold up the ENDING transition itself.
