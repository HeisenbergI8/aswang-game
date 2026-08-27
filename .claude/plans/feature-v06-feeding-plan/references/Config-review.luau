--!strict
--[[
	REVIEW — src/shared/Config.luau (1312 lines)

	Every tunable in the game. V06 adds one number and rewrites one comment.
]]

-- src/shared/Config.luau:235-244
	Monster = {
		TransformTime = 1.2,
		RevertTime = 1.0,
		MaxTransformTime = 8, -- forced revert if no kill
		KillRange = 8, -- studs
		-- DEAD UNDER v2.0, KEPT BECAUSE IT STILL HAS READERS (V02)… It dies with the chunk that
		-- builds feeding.
		KillCooldown = 30, -- seconds after revert
-- IMPORTANT  "IT DIES WITH THE CHUNK THAT BUILDS FEEDING" NAMES V06, AND V06 DOES NOT KILL IT.
--       Counted before deciding: `pure/TransformRules:44`, `pure/KillValidation:69,163-176`,
--       `MonsterService:792,1013,1114`, `tests/config.test:54,160,341`,
--       `tests/transform-rules:41,100`, `tests/anti-cheat-budgets:114`. Six files. Deleting it reds
--       `analyze` AND `test:unit`, exactly as this comment warns, and it changes what an Aswang may
--       do the instant it reverts — a balance question, not a cleanup.
-- IMPORTANT  §4.3 says v2.0 "replaces the timer with an action", so the spec and the shipped code
--       disagree after V06 and the plan raises that rather than resolving it. V06 REWRITES THIS
--       COMMENT so the next reader does not delete a live reader on the strength of a stale note.
-- NOTE  `MaxTransformTime = 8` is the number V06's forced-revert clause interacts with: the form is
--       held for at most MaxTransformTime + FeedDuration, and `config.test` gains an assertion that
--       FeedDuration stays below it so that bound stays "a transform with a feed on the end".
-- NOTE  `KillRange = 8` bounds `FeedLeashStuds` from above, by a new invariant.

-- src/shared/Config.luau:280-299
		--[[
			FEEDING (§4.3) — WHAT REPLACED THE KILL COOLDOWN, and the design's most deliberate window.
			…So FeedDuration is load-bearing rather than cosmetic. §6.5 invariant 2 requires it to
			exceed the time to cross ~15 studs and land a swing; at Trial.PlayerBaselineWalkSpeed = 16
			that crossing is ~0.94s, leaving ~4s for the approach and the swing. V11 PINS THE
			RELATIONSHIP.
		]]
		FeedDuration = 5,
		FeedHeal = 25,
-- IMPORTANT  THE COMMENT SAYS "V11 PINS THE RELATIONSHIP" AND NOTHING PINS IT TODAY —
--       `grep -n FeedDuration tests/config.test.luau` returns nothing. §6.5 lists it as invariant 2
--       and the brief asks whether V05 added it. It did not. V06 Step 1.5 adds it.
-- NOTE  The comment already did the arithmetic (0.94s crossing at walk speed 16), which is where the
--       test's `CROSSING_STUDS / Config.Trial.PlayerBaselineWalkSpeed` comes from.
-- QUESTION  Is V11 or V06 the right owner? V06, because V06 is the chunk that makes FeedDuration
--       mean something; an invariant guarding a number nothing reads is a test with no failure mode.
-- NOTE  `FeedHeal = 25` is consumed only through `pure/MonsterHealth`'s `Tuning`, assembled once in
--       `MonsterService.HEALTH_TUNING` (line 110). V06 adds no second reader.
-- NOTE  V06's `FeedLeashStuds` goes immediately after `FeedHeal`, inside this same block, so a tuner
--       opening it finds all three feed numbers together.

-- src/shared/Config.luau:874-878
		PlayerBaselineWalkSpeed = 16,
-- IMPORTANT  THE ONLY STATEMENT IN THIS FILE OF HOW FAST A PLAYER WALKS, and it lives under `Trial`.
--       §6.5 invariant 2 needs it, so a round mechanic's balance test now reads a trial number. Odd
--       but correct — there is no other. Recorded in the plan's Follow Ups so it moves with the block
--       if a `Player` section is ever added.

-- src/shared/Config.luau:30-47
--   READ THIS BEFORE CHANGING SaltDamage OR SaltSpawnCount. §6.5 invariant 1 requires
--   `SaltDamage x (SaltSpawnCount - 1) >= Monster.MaxHealth - Monster.WeakenedThreshold`
	SaltDamage = 25,
-- NOTE  Invariant 1 is ALREADY PINNED (V05, `config.test:308-318`). V06 does not touch it, but the
--       feed is the other side of the tug-of-war it describes: every completed feed heals away
--       exactly one salt hit, so the survivors' four pouches minus their misses minus the Aswang's
--       feeds is the real margin. Nothing in `Config` states THAT relationship, and nothing can —
--       it depends on how many kills the Aswang gets, which is the game.

-- src/shared/Config.luau:225-260 (AntiCheat.Budgets)
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
			RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
-- IMPORTANT  V06 ADDS NO ENTRY HERE, and that is the point rather than an oversight: there is no
--       `RequestFeed`, so there is no `OnServerEvent` handler and nothing to budget. If a later chunk
--       adds one, it is priced like `RequestTransform` — a deliberate, rare act — and `AllowUnbudgeted
--       Remote = false` means a missing entry refuses rather than allows.
