--!strict
--[[
	REVIEW — src/shared/Config.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite (this file is modified in the working
	tree by V04, so line numbers may shift by a few once V04 commits).
]]

-- src/shared/Config.luau:28-46  (the Items block — where SaltDamage actually lives)
--[[
	READ THIS BEFORE CHANGING SaltDamage OR SaltSpawnCount. §6.5 invariant 1 requires
	`SaltDamage x (SaltSpawnCount - 1) >= Monster.MaxHealth - Monster.WeakenedThreshold`, so that
	...
]]
	SaltSpawnCount = 4,
	SaltDamage = 25,
	SaltRevealDuration = 10,
-- IMPORTANT: `SaltDamage` is in `Items`, NOT in `Monster`. That is why V05's `MonsterHealth.Tuning`
-- is assembled at the call site from two blocks instead of taking `Config.Monster` whole the way
-- `NoiseModel` takes `Config.Noise`.
-- IMPORTANT: invariant 1 is stated HERE and again at line 249, and asserted in NEITHER. Phase 2 of
-- the plan is the fix. It holds with zero margin: 25 x 3 = 75 = 100 - 25.

-- src/shared/Config.luau:83
--		It kills only an Aswang that is BOTH Exposed and below Monster.WeakenedThreshold (§4.6).
-- NOTE: the third place the two-condition gate is written down. V08 implements it; V05 supplies both
-- halves as predicates.

-- src/shared/Config.luau:240-244
	-- DEAD UNDER v2.0, KEPT BECAUSE IT STILL HAS READERS (V02) ... It dies with the chunk that
	-- builds feeding.
	KillCooldown = 30, -- seconds after revert
-- NOTE: V06, not V05. `tests/config.test.luau:158-164` pins KillCooldown against StunDuration for a
-- SECRECY reason (a transform while stunned would capture BaseWalkSpeed = 0), so whoever removes it
-- must remove that pin knowingly. V05 inserts its new invariants immediately after that check and
-- must not disturb it.

-- src/shared/Config.luau:248-260
--[[
	THE ASWANG'S HEALTH (§4.6), AND THE SECOND WIN CONDITION LIVES IN THESE TWO NUMBERS.
	... raise MaxHealth or lower WeakenedThreshold and survivors stop being able to win that way,
	with nothing in the game to tell you.
	WeakenedThreshold is a HEALTH PREDICATE, not a `MonsterState` member — see Enums.MonsterState.
]]
	MaxHealth = 100,
	WeakenedThreshold = 25,
-- IMPORTANT: V02 already landed these, so V05 adds NO health tunables — only the two glow-ramp
-- endpoints, which go immediately below this pair because the ramp is a function of these two.

-- src/shared/Config.luau:279-280
	FeedDuration = 5,
	FeedHeal = 25,
-- NOTE: also already present. V05 reads `FeedHeal` for the `HealFromFeed` seam; V06 owns the ritual.
-- QUESTION: nothing pins `FeedHeal <= SaltDamage`. §6.5 does not list it, but §4.6 says a kill heals
-- away ONE salt hit. The plan pins it and raises it in Follow Ups rather than assuming.

-- src/shared/Config.luau:306-315
--[[
	STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under LUNE,
	which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to typecheck — it
	fails at TEST time, in every balance test at once, with an error naming Config rather than the
	edit that broke it.
]]
-- IMPORTANT: V05's two new numbers are plain floats for this reason. The glow ramp is two scalars,
-- not a ColorSequence.

-- src/shared/Config.luau:326-342  (the Salt alias block)
--[[
	... five modules that read them are edited, and V02 may not edit a service. Tune `Items` above —
	changing a line here does nothing, because there is no value here to change.
	DELETE EACH ONE with the chunk that renames its last reader.
	`tests/config.test.luau` pins each of these four to its canonical source ...
]]
	RevealDuration = Items.SaltRevealDuration,
-- IMPORTANT: V05 is the chunk that renames `RevealDuration`'s last reader (ItemService:472). The
-- plan deliberately LEAVES the alias, because deleting it also means editing the pin at
-- config.test:108-110 for no behavioural gain, and V08 generalises the whole Salt block anyway.
-- Raised in Follow Ups so the decision is visible rather than forgotten.

-- src/shared/Config.luau:389-392
		-- as Monster's palette. `RevealGlow*` is a Highlight's two colours.
		RevealGlowFillRgb = { 255, 250, 235 },
		RevealGlowOutlineRgb = { 190, 235, 255 },
-- NOTE: real values, not aliases. V05 leaves them here and has MonsterService read them, because the
-- COLOUR belongs to the item that paints the glow while the RAMP belongs to the health it reads.
-- That cross-block read is deliberate; the alternative is duplicating two RGB triples.
