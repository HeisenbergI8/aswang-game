--!strict
-- Review of src/shared/Config.luau — which knobs C05/C06/C07 already have.
-- Excerpts only.

-- src/shared/Config.luau:12-23
	Round = {
		Intermission = 25,
		Duration = 420,
		EndScreen = 12,
		StartingDelay = 4, -- NOTE: "role assignment + teleport fade". Phase 1's LoadCharacter on the
		-- LOBBY -> ALIVE transition IS a teleport, and this is the budget that already covers it.
		MinPlayers = 3,
		-- IMPORTANT: 3 players is 1 Aswang + 2 survivors, so §4.8's "living survivors ≤ 2" is TRUE
		-- before anyone moves. Phase 5's dealt-in clamp exists because of this line.
		MaxPlayers = 8,
		SnapshotInterval = 0.5,
	},
	-- NOTE: Phase 2 adds `AswangWinSurvivorThreshold = 2` to this block.

-- src/shared/Config.luau:51-59 — three of the four knobs C05 needs ALREADY EXIST.
	Monster = {
		TransformTime = 1.2,
		RevertTime = 1.0,
		MaxTransformTime = 8,
		KillRange = 8, -- studs                          -- §4.3, used by Phase 3
		KillCooldown = 30, -- seconds after revert        -- §4.3 step 5, used by Phase 3
		TransformedSpeedMult = 1.25,
		TransformAudioRange = 40,
		CorpseDuration = 45, -- §4.3 step 4, used by Phase 4
	},
	-- IMPORTANT: C05 introduces only ONE new Monster key — `CorpseFadeTime`. The scaffold already
	-- carried the other three, so a plan that "adds the kill's tunables" would mostly be re-adding
	-- numbers that are there. Worth checking before writing the diff.

-- src/shared/Config.luau:61-70 — the Lune trap, and why positions are plain tables.
	--[[
		STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
		LUNE, which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to
		typecheck — it fails at TEST time, in every balance test at once, with an error naming
		Config rather than the edit that broke it.
	]]
-- IMPORTANT: the same trap, one layer out. A `Vector3` inside pure/KillValidation or
-- pure/TaskSelection would not fail `analyze`; it would fail every Lune run of that module. Both take
-- `{ X, Y, Z }` tables and the services convert at the call site.

-- src/shared/Config.luau:79-86
	Tasks = {
		TotalRequired = 5,
		PoolSize = 12,
		-- NOTE: §4.4's "5 of 12" is already data. Phase 6 adds `MinSpacingStuds = 20`; the draw itself
		-- reads TotalRequired and the pool size comes from the map at C17.
	},

-- src/shared/Config.luau:156-172 — the rate-limit budgets.
	AntiCheat = {
		Budgets = {
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
			-- IMPORTANT: RequestKill's budget ALREADY EXISTS. Phase 4 adds no Config entry, and the
			-- playtester's burst probe (8 calls, 3 through) is calibrated against this Capacity.
		},
		AllowUnbudgetedRemote = false, -- fail closed
		LogOnly = true,
		-- NOTE: LogOnly means nothing is kicked. A refusal is still a refusal; only the punishment is
		-- deferred to C41. A quiet console is not evidence the limiter ran.
	},

-- src/shared/Config.luau:191-198
	Debug = {
		SoloTesting = false,
		VerboseLogging = false,
		-- IMPORTANT: added by commit 3c70cfc. Without it a solo round draws ZERO Aswangs (see
		-- RoleDraw-review) and every kill probe returns NOT_ASWANG for the wrong reason — which is
		-- exactly how C04's transform verification failed. This flag is what makes the plan's six
		-- refusal probes reachable at all.
		-- IMPORTANT: pinned false by check:debug and by tests/config.test.luau. The playtester cannot
		-- set it; the coordinator must, and must revert all six debug values afterwards.
		ForceAswangWhenSolo = false,
	},
