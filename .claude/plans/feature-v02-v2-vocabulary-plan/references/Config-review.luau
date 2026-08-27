--!strict
--[[
	REVIEW — src/shared/Config.luau (904 lines). Excerpted, not transcribed.
	Ranges cited: :11-18, :65-77, :97-102, :113-118, :176-179, :241-243, :548-556.
	Read for: V02 Phase 3, which adds spec §6.5's v2 block to it.
]]

-- src/shared/Config.luau:11-18
-- IMPORTANT `local Config = {` is currently the file's FIRST and ONLY top-level statement. Step 3.4
-- adds a `local Items = { ... }` above it — the file's first hoisted local ever. Nothing reads this
-- module positionally (every consumer `require`s it and reads the returned table, and
-- check-config.mjs:36 scans only src/server and src/client), but Step 3.5's verify:fast is the proof.
local Config = {
	Round = {
		Intermission = 25, -- seconds in lobby before a round starts
		Duration = 420, -- 7 minutes of "night" before sunrise
		EndScreen = 12, -- reveal + stats screen
		StartingDelay = 4, -- role assignment + teleport fade
		MinPlayers = 3, -- MUST be playable at this count (see spec §9 cold start)
		MaxPlayers = 8,

		-- NOTE Duration 420 -> 300 and MaxPlayers 8 -> 5 are Step 3.1. Both are spec-mandated:
		-- §6.5 line 729, §4.1 line 170 (flat 300s), §C line 873 (MaxPlayers 5, not 20).
		-- IMPORTANT Nothing in src/ reads Round.MaxPlayers. Grepped: only tests/config.test.luau
		-- (lines 39, 45, 99, 171, 634) and the prose comment at :242. The number that would actually
		-- cap a server is Roblox's Players.MaxPlayers, which lives in the PLACE FILE, outside Git.
	},

-- src/shared/Config.luau:65-77
	Monster = {
		TransformTime = 1.2, -- visible windup — the core risk/reward moment
		RevertTime = 1.0,
		MaxTransformTime = 8, -- forced revert if no kill
		KillRange = 8, -- studs
		-- IMPORTANT DEAD UNDER v2.0 AND V02 MUST NOT DELETE IT. §4.3's heading is literally "Feeding —
		-- what replaced the kill cooldown". Still read by MonsterService and pinned by
		-- config.test:238. Deleting it reds `analyze` AND `test:unit`, violating V02's Done.
		KillCooldown = 30, -- seconds after revert
		TransformedSpeedMult = 1.25,
		TransformAudioRange = 40, -- <- Step 3.2 inserts the six v2 Monster numbers directly after this
		-- IMPORTANT §6.5 files this under `Bodies`, not `Monster`. Read at MonsterService.luau:335 and
		-- cited at Types.luau:406; moving it reds `analyze`. Unlike the Salt renames the NAME does not
		-- change, so a reader finds it either way and no alias is warranted. Step 3.3 builds `Bodies`
		-- WITHOUT it.
		CorpseDuration = 45,
	},

-- src/shared/Config.luau:97-102
	Salt = {
		-- IMPORTANT THE FOUR §6.5 RENAMES. Step 3.4 converts exactly these four to aliases into the
		-- hoisted `Items` local. Live readers of the old names, grepped: ItemService.luau,
		-- TrialService.luau, UIController.luau, InputController.luau, shared/pure/SaltCarry.luau,
		-- plus tests/config.test.luau and tests/anti-cheat-budgets.test.luau.
		SpawnCount = 4, -- -> Items.SaltSpawnCount
		StunDuration = 4, -- -> Items.SaltStunDuration
		RevealDuration = 10, -- -> Items.SaltRevealDuration
		ThrowRange = 25, -- -> Items.SaltThrowRange
		-- NOTE everything below this line has NO §6.5 counterpart and stays put: CarryLimit,
		-- PickupRangeStuds, ThrowConeDegrees, PouchPoolSize, PouchRgb, RevealGlow{Fill,Outline}Rgb.
		CarryLimit = 1, -- why the carry slot is a single optional and not a list
	},

--[[
	MEASURED, AND IT IS THE PIVOT OF THIS WHOLE PLAN.

	A missing Config key is a HARD analyzer error, not a warning. Reproduced directly against this
	repo's pinned luau-lsp on 2026-08-27:

		local T = { Salt = { CarryLimit = 1 } }
		local x: number = T.Salt.SpawnCount
		-> TypeError: Key 'SpawnCount' not found in table '{| CarryLimit: number |}'   (exit 1)

	So the obvious reading of V02 — rename Salt.* to §6.5's Items.Salt* names — reds `npm run analyze`
	across five live modules, contradicting V02's own Done line ("analyze clean"). That is why Step 3.4
	aliases instead, and why the plan's preamble contradicts BUILD-PLAN.md:191's prediction that
	config.test will go red. It does not; it PASSES today (82 invariants) and passes after V02.
]]

-- src/shared/Config.luau:113-118 and :176-179
-- NOTE V01's tombstones, and useful context for Step 3.3. The first says PickupRangeStuds "DELIBERATELY
-- SMALL, and V01 removed the number it used to be measured against — the task system's nine-stud
-- presence range... V03 owes this a new right-hand side": the container SEARCH range. So `Search` in
-- Step 3.3 is the table V03 will measure PickupRangeStuds against, and §6.5 pins no relationship
-- between them. The second is the same shape for a QuickChat bound V01 orphaned.

-- src/shared/Config.luau:241-243
-- IMPORTANT DEAD BY NAME UNDER v2.0. The escape gate is retired (§4.6), so an "escape bonus" is a
-- reward for a win condition that no longer exists. Read by XPCurve and config.test:634. Deleting it
-- reds analyze; deferred to the win-conditions chunk alongside RoundResult. See Follow Ups Q4.
		XPSurvivorEscapeBonus = 25,

-- src/shared/Config.luau:548-556
-- IMPORTANT TASK-NAMED AND STALE. §10's launch gate now measures a first FIND rather than a first
-- task. Renaming touches BadgeService and config.test:135. Not V02's; listed in Issues Found.
	Badges = {
		FirstTask = 0,
		FirstTaskConversionGate = 0.50,
	},

--[[
	NOT DEAD, AND WORTH SAYING SO — the Solo Trial keeps its tasks BY DECISION.

	`Trial.TasksToComplete = 2` (:457), `TrialPhase.TRIAL_TASKS` and `TrialBeat.BEAT_TASKS` all survive
	v2.0. The Config comment at :458 records V01 reworking the Trial's presence numbers deliberately
	rather than deleting them. So "task" appearing in this file is not automatically a V01 leftover;
	the four entries listed above are, and the Trial's are not.
]]
