--!strict
--[[
	REVIEW — src/server/init.server.luau
	Read 2026-08-12 for the C09-C12 plan. Phase 6 adds one line to it.

	Small file, one real hazard: it is where a require cycle goes to die quietly.
]]

-- src/server/init.server.luau:19-36
local SERVICE_ORDER = {
	-- Infrastructure first
	"AnalyticsService",
	"AntiCheatService",
	"ProgressionService",
	"BadgeService",
	"MonetizationService",
	"CommunityService",
	-- Gameplay
	"RoleService",
	"TaskService",
	"MonsterService",
	"ItemService",
	"GhostService",
	"TrialService",
	-- The state machine drives everything, so it starts last
	"RoundService",
}
-- Phase 6 inserts "GateService" after "TaskService".
-- IMPORTANT: this list is HAND-MAINTAINED — ":12 Add new services to the SERVICE_ORDER list below."
-- A service file that exists and is not listed is never Init'd or Start'd. It does not error, does
-- not fail analyze, and does not fail any of the five checks: it simply never runs. For GateService
-- that means the gate opens (RoundService writes GateOpen) and nobody ever wins, which reads exactly
-- like a bug in the win condition rather than a missing line in a list.
-- NOTE: `npm run verify:fast` is Step 6.4's check and it does NOT catch this. What catches it is the
-- boot log — `Ready. N services loaded.` — which is why Step 6.5 should record the count going 13 -> 14.

-- src/server/init.server.luau (placement rationale)
-- NOTE: position among the gameplay services does not matter for correctness here. `require` resolves
-- at load regardless of this list; SERVICE_ORDER controls only Init/Start ordering, and GateService's
-- `Start` only connects a handler and spawns a loop that early-returns unless the phase is ACTIVE.
-- RoundService still starts LAST, which is the property that matters: "The state machine drives
-- everything, so it starts last." GateService subscribing to PhaseChanged before RoundService starts
-- is correct — that is the same position TaskService and MonsterService are in.

-- src/server/init.server.luau:37-42
type Service = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	[string]: any,
}
-- NOTE: both optional, so GateService could omit `Init`. It should still define an empty one, matching
-- TaskService and every other service — the shape is the convention and an absent Init reads as an
-- oversight rather than a decision.

-- src/server/init.server.luau (the swallowed-cycle hazard)
-- IMPORTANT — the single most repeated warning in this codebase, and it appears in TaskService's
-- header, MonsterService's, RoundService's and RoleService's: a require cycle "errors at load,
-- init.server.luau swallows it into a single warn, and the server sits in IDLE forever looking
-- exactly like 'nobody has joined yet'."
-- GateService requires RoundService. RoundService must NEVER require GateService back. The temptation
-- exists and it is specific: `enterEnding` could plausibly want to tell the gate to shut. It must not
-- — GateService already learns that from `PhaseChanged`, which is the one-directional channel that
-- exists precisely so this require never has to be written.
-- NOTE: the symptom to watch for at Step 6.4 is the boot log reading `13 services loaded` (or fewer)
-- with one warn above it, rather than `14`. Plan 1's `artifacts/task-rig.md` §4 used exactly this
-- signal — "No require-cycle warning: `13 services loaded` on every boot."

-- src/server/init.server.luau:87
log(`Ready. {#SERVICE_ORDER} services loaded.`)
-- IMPORTANT: this counts the LIST, not the successful loads. So it prints 14 whether or not
-- GateService actually loaded — the warn above it is the real signal. Worth knowing before treating
-- the count as proof.
return nil
