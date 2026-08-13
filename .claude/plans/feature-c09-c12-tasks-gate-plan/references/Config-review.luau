--!strict
--[[
	REVIEW — src/shared/Config.luau
	Read 2026-08-12 for the C09-C12 plan. Cited ranges below; the file is 287 lines.

	Phase 1 adds nine knobs and renames one. Everything C09-C12 tunes lands here, because
	`check:config` refuses a balance number anywhere under src/server/ or src/client/.
]]

-- src/shared/Config.luau:110-117
	Tasks = {
		TotalRequired = 5,
		PoolSize = 12,
		HoldTime = 8,
		TimingAttempts = 3,
		FetchTime = 25,
		TwoPersonTime = 12,
	},
-- IMPORTANT: three of these have existed since the scaffold and NOTHING READS THEM. Grepped across
-- src/, tests/ and .claude/scripts/: `TimingAttempts`, `FetchTime` and `TwoPersonTime` occur exactly
-- once each, on these lines. So Phase 1's rename of `TimingAttempts` -> `TimingHitsRequired` is free
-- TODAY and will never be free again.
-- QUESTION resolved in the plan's §4: "3 attempts" against §4.4's "~10s" duration column reads as
-- three REQUIRED HITS (three sweeps plus reaction), not three ALLOWED MISSES (about two seconds).
-- The spec's own duration column picks the reading. Worth a spec sentence either way.

-- src/shared/Config.luau:118-150
		MinSpacingStuds = 20,
		PresenceRangeStuds = 9,
-- IMPORTANT — the comment here is the corrected one and it must stay corrected:
--   "**THE DRAW DOES NOT GUARANTEE THE SPACING** — that claim used to sit here and it was false."
-- `PresenceRangeStuds * 2 < MinSpacingStuds` (18 < 20) is DEFENCE IN DEPTH, not an invariant. What
-- actually makes resolution safe is `taskPointAt` picking the nearest incomplete point.
-- NOTE for Phase 4: the fetch SOURCE pickup radius reuses `PresenceRangeStuds`. That is deliberate
-- reuse rather than a new knob — a source is a place you stand at, and giving it its own radius would
-- be a second number to keep in agreement with nothing.
-- NOTE: verified live since drafting — `artifacts/delta-3-spacing-warning-both-cases.md` proves the
-- warning fires when packed and stays silent when spread, in both directions.

-- src/shared/Config.luau:152-168
		PresenceGraceSeconds = 0.75,
		HeartbeatInterval = 0.25,
-- NOTE: Phase 3 adds NO grace of this kind for the timing stop. A stop is a discrete event with no
-- window to fall out of between heartbeats; `TimingGraceSeconds` is a LATENCY allowance and a
-- different quantity entirely, measured in the same unit. Do not let the two names collapse.

-- src/shared/Config.luau:78-90
	Monster = {
		KillRange = 8,
	},
-- IMPORTANT for Phase 1's fifth invariant: `Tasks.GateRangeStuds <= Monster.KillRange` (6 <= 8). The
-- relation is a DESIGN constraint, not a safety margin — a gate triggering from beyond the Aswang's
-- reach deletes gate-camping, which is the last thirty seconds of a good round (§4.8). Tune either
-- number, never past each other.

-- src/shared/Config.luau:179-183
	Ghost = {
		TaskContributionMult = 0.25,
	},
-- IMPORTANT for Phase 5: this is the number that separates §4.4's "2 survivors present" from §4.7's
-- ghosts "still matter". `TaskParticipants` counts contributors at or above
-- `Tasks.FullContributionWeight` (1), so 0.25 < 1 is the WHOLE of why two ghosts do not open a
-- two-person task. Phase 1 pins it in `tests/config.test.luau`, because nothing else would notice if
-- it drifted upward at M12.

-- src/shared/Config.luau:226-255
	AntiCheat = {
		Budgets = {
			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },
		},
	},
-- IMPORTANT: "Every name here must appear in Remotes.EVENTS_UP, and every name there must appear
-- here." `tests/anti-cheat-budgets.test.luau` pins BOTH directions against its own hand copy of the
-- list, so Phase 1's `RequestTimingStop` must be added in THREE places — Remotes.luau, this table,
-- and the test's `UP_REMOTES`. That is why the Lune test is Step 1.4's check rather than
-- `check:remotes`: it fails on absent work, and `check:remotes` reports an unwired remote as a NOTE.
-- NOTE: "Tune these LOOSER than legitimate play, never tighter. A limiter that refuses a real player
-- is a gameplay bug that presents as lag."

-- src/shared/Config.luau:274-284
	Debug = {
		SoloTesting = false,
		VerboseLogging = false,
		ForceAswangWhenSolo = false,
	},
-- IMPORTANT for whoever briefs the playtester: all three are pinned false by `check:debug` and
-- `guard-commit.mjs` refuses a commit carrying them. The COORDINATOR sets them before launching the
-- playtester and reverts them after — the agent cannot edit Config and will correctly refuse.
-- NOTE for Phase 5 and Phase 6 specifically: `ForceAswangWhenSolo` is what makes a solo Studio round
-- have an Aswang at all. Phase 7's decoy list and Phase 6's gate refusal are BOTH unobservable
-- without it, because a lone player is otherwise always a survivor by construction.

-- src/shared/Config.luau:1-9 (header)
-- "Rule: no magic numbers anywhere else in the codebase."
-- NOTE: `check-config.mjs` governs `/src/(server|client)/` ONLY — so `src/server/pure/` IS governed
-- (four of this plan's five new pure modules live there) and `src/shared/pure/` is NOT. Every new
-- pure module takes its tunables as PARAMETERS, which is what keeps them clean of it either way.
-- Allowed literals: 0, 1, 2, -1, 0.5, 100, for-loop headers, and any line already reading `Config.`.
return nil
