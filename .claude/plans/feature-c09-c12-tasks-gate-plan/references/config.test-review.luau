--!strict
--[[
	REVIEW — tests/config.test.luau and tests/anti-cheat-budgets.test.luau
	Read 2026-08-12 for the C09-C12 plan. Phase 1 edits both.

	These two files are where this repo keeps its SILENT invariants — relationships between numbers
	where no symptom tells you when two values that must agree have stopped agreeing.
]]

-- tests/config.test.luau (the shape Phase 1 appends to)
local function check(label: string, ok: boolean, detail: string?) end
-- [... 29 invariants ...]
if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end
print("  PASS  config: 29 balance invariants")
-- IMPORTANT: THE PRINTED COUNT IS HAND-MAINTAINED and Phase 1 moves it 29 -> 34. It is not asserted
-- anywhere, so a stale count is a cosmetic lie rather than a failure — which is exactly why it drifts.
-- `tests/anti-cheat-budgets.test.luau` has the same convention (`+ 7 invariants` -> `+ 8`).
-- NOTE: plan 1's implementation log tracked this deliberately ("its final `print` moved 26 -> 29"), so
-- the convention is to update it in the same diff that adds the checks.

-- tests/config.test.luau (the presence invariant plan 1 added, and its correction)
check(
	"a player can only ever be present at one task point at a time",
	Config.Tasks.PresenceRangeStuds * 2 < Config.Tasks.MinSpacingStuds,
	`PresenceRangeStuds=..., MinSpacingStuds=...`
)
-- IMPORTANT: its comment carries a correction worth reading before adding any new spacing-adjacent
-- invariant — "THIS IS DEFENCE IN DEPTH, NOT THE GUARANTEE. An earlier version of this comment said
-- two selected points 'are guaranteed to be MinSpacingStuds apart' — they are not."
-- NOTE: the pattern to copy is that each check's comment states WHAT BREAKS if the relation fails, in
-- gameplay terms, not what the arithmetic is. Phase 1's five new checks follow it: an unreachable
-- green zone, a grace that replaces the zone it widens, a deliver hold that turns Fetch into Hold, a
-- ghost that opens a two-person task, a gate outside the Aswang's reach.

-- Phase 1's most load-bearing new invariant, and why it needs a test rather than a comment:
check(
	"the timing grace widens the zone rather than replacing it",
	Config.Tasks.TimingGraceSeconds * (2 / Config.Tasks.TimingBarPeriod)
		< Config.Tasks.TimingZoneHalfWidth
)
-- IMPORTANT: the grace is in SECONDS and the zone is in BAR UNITS. They are not comparable until the
-- sweep speed converts one to the other, and that conversion (`2 / Period`) lives inside
-- `TimingWindow.effectiveHalfWidth`. Restating it here against Config's own numbers is the point:
-- LOWERING `TimingBarPeriod` at M12 silently widens the effective window, and nothing else in the
-- tree would notice. This is the archetypal silent invariant.

-- Phase 1's C15 forward invariant:
check(
	"a ghost is not a two-person participant",
	Config.Ghost.TaskContributionMult < Config.Tasks.FullContributionWeight
)
-- IMPORTANT: this single relation is the WHOLE of what separates §4.4's "2 survivors present" from
-- §4.7's ghosts "still matter". `TaskParticipants` counts contributors at or above the full weight, so
-- if `TaskContributionMult` were ever tuned up to 1, two dead players would open the game's most
-- social task and no test outside this line would go red.

-- tests/anti-cheat-budgets.test.luau:24-34
local UP_REMOTES = {
	"RequestTaskProgress", "RequestTransform", "RequestKill", "RequestThrowSalt",
	"RequestQuickChat", "RequestGhostSpook", "RequestEquipCosmetic", "RequestClaimDaily",
}
-- IMPORTANT: A HAND COPY of `Remotes.EVENTS_UP`, and the header says why: "`src/shared/Remotes.luau`
-- calls `game:GetService` at module scope, so Lune cannot require it — there is no DataModel."
-- Phase 1 adds `RequestTimingStop` here AND to `Config.AntiCheat.Budgets` AND to `Remotes.luau`.
-- Three places. Missing any one is caught:
--   missing from Config    -> this test's "has a declared budget" assertion fails
--   missing from this list -> this test's EXTRA_BUDGETS assertion fails
--   missing from Remotes   -> `check:remotes` fails when the handler fires it
-- NOTE: that three-way coverage is precisely why Step 1.4's Verify is this Lune test rather than
-- `check:remotes` — it is the only one of the three that fails on ABSENT work.
-- IMPORTANT: the header names the surviving hole honestly — "a remote added to Remotes.luau and to
-- nothing else" is caught only when something fires it. And it names the clean fix (a check script
-- parsing both files) while deferring it, which the plan's §4 carries forward rather than silently
-- inheriting.

-- tests/anti-cheat-budgets.test.luau (the cadence invariants Phase 1 extends)
check(
	"the ghost can afford its one spook",
	Config.AntiCheat.Budgets.RequestGhostSpook.Capacity >= Config.Ghost.SpooksPerRound
)
-- NOTE: the model for Phase 1's new one. Each existing check ties a budget to the GAMEPLAY number that
-- drives it — carry limit, spooks per round, kill cooldown — rather than asserting a magic threshold.
-- Phase 1 ties `RequestTimingStop.RefillPerSecond` to `TimingBarPeriod`, because the honest cadence at
-- a timing bar is one press per sweep and Config's own budget header warns that a limiter refusing a
-- real player "is a gameplay bug that presents as lag".
return nil
