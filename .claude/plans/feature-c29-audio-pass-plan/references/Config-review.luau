--!strict
--[[
	REVIEW — src/shared/Config.luau (769 lines; read the block index, Round 12-51, Monster 78-109,
	Performance 533-609, Sky 610-688, Debug 756-766)

	EDITED BY THIS PLAN: gains an `Audio` block between `Sky` and `AntiCheat`.
]]

-- src/shared/Config.luau:78-84
Monster = {
	TransformTime = 1.2, -- visible windup — the core risk/reward moment
	RevertTime = 1.0,
	MaxTransformTime = 8, -- forced revert if no kill
	TransformAudioRange = 40, -- how far the transform sound carries
}
-- IMPORTANT: three of C29's four monster-cue numbers already exist here and the plan adds none.
-- `TransformAudioRange` is the ceiling `Config.Audio.HeartbeatRange` is pinned under, and
-- `MaxTransformTime + RevertTime` (9s) is the heartbeat's hard-timeout backstop — composed rather
-- than re-declared, so tuning the transform tunes the audio with it.

-- src/shared/Config.luau:98-106
--[[
	STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
	LUNE, which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to
	typecheck — it fails at TEST time, in every balance test at once, with an error naming
	Config rather than the edit that broke it. MonsterService builds the Color3.
]]
-- IMPORTANT: the constraint the `Audio` block must respect. An asset id is a STRING and is safe; a
-- `SoundGroup`, an `Enum.RollOffMode` or a `Vector3` in this file would red every balance invariant
-- at once with an error pointing at the wrong place. `Enum.RollOffMode.Linear` stays in the
-- controller, where it already is.

-- src/shared/Config.luau:12-18
Round = {
	Intermission = 25,
	Duration = 420, -- 7 minutes of "night" before sunrise
	EndScreen = 12, -- reveal + stats screen
	SnapshotInterval = 0.5,
}
-- NOTE: `Duration` is the sunrise cue's denominator via `SkyCycle.progressFor`, and `EndScreen` (12s)
-- is what the plan pins `Audio.BedFadeSeconds` (2s) below — the dawn bed must finish arriving before
-- the end screen is over.
-- IMPORTANT: `SnapshotInterval` = 0.5 means every snapshot-derived cue is evaluated twice a second.
-- The gate cue and the sunrise cue must both be edge-detected or they fire ~24 times each.

-- src/shared/Config.luau:533-547
Performance = {
	--[[
		§5: "Cap dynamic lights to ~8 visible at once ..." ... CLIENT-SIDE, ROLE-BLIND, AND NOTHING
		CROSSES THE WIRE. It is a rendering decision over a distance from a camera, so every client
		runs the same rule over its own view.
	]]
	MaxVisibleLights = 8,
	TargetFPSMobile = 30,
}
-- NOTE: the closest existing analogue to C29's design. A per-client decision over a local distance,
-- role-blind, nothing on the wire — that is exactly the shape the audio plan uses, and it is worth
-- noting that this one is allowed to use POSITIONS because the camera is the client's own.
-- IMPORTANT: `TargetFPSMobile` is C27's committed baseline. The audio pass must not move it; simultaneous
-- Sound streams are the budget line to watch, which is why the plan caps steady state at one bed +
-- one bounded one-shot + one heartbeat.

-- src/shared/Config.luau:756-766
Debug = {
	SoloTesting = false,
	VerboseLogging = false,
	ForceAswangWhenSolo = false,
}
-- IMPORTANT: `VerboseLogging` is what gates C29's cue log, which is the chunk's stated verification
-- ("playtester captures console confirmation of each cue"). All three are pinned false by
-- `check:debug` and `guard-commit.mjs` refuses to commit them true — so the playtester run needs
-- these set BY THE MAIN THREAD beforehand and reverted after (plan Step 4.4).

-- Block ordering (src/shared/Config.luau:11-767)
-- Round, Roles, Monster, Tasks, Salt, Ghost, QuickChat, Economy, Trial, Community, Badges,
-- Performance, Sky, AntiCheat, Debug
-- NOTE: the plan inserts `Audio` after `Sky` and before `AntiCheat`. Not alphabetical and not
-- arbitrary — Sky and Audio are the two C28/C29 presentation systems and both are driven from the
-- same snapshot; a reader tuning the feel of a round finds them together.
