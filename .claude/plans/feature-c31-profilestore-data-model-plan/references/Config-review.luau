--!strict
--[[
	REVIEW — src/shared/Config.luau:1-9, 434-438, 867-877
	Read for: where C31's knobs go, what already exists, and the file's own no-magic-numbers rule.
]]

--	Config — every tunable number in the game lives here.
--	Rule: no magic numbers anywhere else in the codebase.
-- NOTE: enforced by check:config, which governs `src/server/` and `src/client/` only
-- (check-config.mjs:41). So C31's three new numbers MUST land here; MAX_ID_LENGTH in
-- src/shared/pure/ProfileMigration.luau is outside the governed path and needs no waiver.

--------------------------------------------------------------------------------
-- :434-438 — already present, and NOT C31's to spend
--------------------------------------------------------------------------------

	Economy = {
		XPPerRound = 50,
		XPWinBonus = 40,
		XPSurvivorEscapeBonus = 25,
		CoinsPerRound = 25,
		XPPerLevel = 500,
	},
-- IMPORTANT: C32 spends these. C31 reads exactly two of them — XPPerRound and CoinsPerRound — for the
-- single flat award in Step 4.2, which exists only so persistence is observable. The three it does not
-- touch (WinBonus, SurvivorEscapeBonus, XPPerLevel) are the shape of the work C32 still has to do, and
-- their presence here is a good check on whether a step has quietly become C32's.
-- NOTE: no `Profile` section exists yet. Step 1.4 adds one immediately after this block.

--------------------------------------------------------------------------------
-- :867-877 — the debug flags the playtest needs
--------------------------------------------------------------------------------

	Debug = {
		SoloTesting = false,
		VerboseLogging = false,
		ForceAswangWhenSolo = false, -- Pinned false by check:debug
	},
-- IMPORTANT: Step 4.3 requires a human to set SoloTesting and VerboseLogging (plus shorter Round
-- timings) BEFORE launching the playtester, and to revert all five afterwards. guard-commit.mjs runs
-- check:debug and refuses a commit carrying them, so they cannot reach history — but a run that
-- forgets to revert them will be blocked at commit time rather than at edit time.
-- NOTE: the plan's own logging is gated on VerboseLogging throughout, matching RoundService's
-- onServerClosing. The one exception is the DataStoreState warning in Step 4.1, which fires
-- unconditionally when access is missing — a silent fallback to mock storage is the failure this
-- chunk is most likely to be misdiagnosed by.
