--!strict
--[[
	REVIEW — src/shared/Config.luau (1484 lines). Phase 2 owns the edits.

	The `Items` block near the top is CANONICAL (V02); `Config.Salt` near line 449 is a shrinking
	alias table that V08 is the chunk to finish off.

	Cited against the file as read on 2026-08-29.
]]

-- src/shared/Config.luau:12-25
--[[
	§6.5's ITEM BLOCK, HOISTED INTO A LOCAL SO `Config.Salt` CAN ALIAS IT (V02).
	... a missing Config key is a HARD analyzer error, not a warning:
		TypeError: Key 'SpawnCount' not found in table '{| CarryLimit: number |}'
	V02 is a vocabulary chunk that may not touch services, so `Items` below is CANONICAL and the four
	matching fields of `Config.Salt` are ALIASES pointing at it. Tune here. `Config.Salt` shrinks to
	nothing as each consumer is renamed, and disappears with the last one.
]]
-- IMPORTANT: V08 RENAMES THE LAST CONSUMER OF ALL FOUR, so `Config.Salt` disappears in this chunk.
-- IMPORTANT: "a missing Config key is a HARD analyzer error" is the reason the deletion must be
-- SEQUENCED. Five modules read `Config.Salt` today — ItemService, TrialService, MonsterService,
-- UIController, InputController — and they are fixed in Phases 1, 3 and 5. Delete the table before
-- the last reader and `analyze` fails immediately. That is the desired failure mode; do not leave a
-- stub table behind to soften it.

-- src/shared/Config.luau:26-49
local Items = {
	--[[
		READ THIS BEFORE CHANGING SaltDamage OR SaltSpawnCount. §6.5 invariant 1 requires
		`SaltDamage x (SaltSpawnCount - 1) >= Monster.MaxHealth - Monster.WeakenedThreshold` ... At the
		shipped values that is `25 x 3 = 75 >= 100 - 25 = 75` — EQUALITY, with zero margin. Every pouch
		but one must connect. V11 pins this; until V11 lands, this comment is the only guard.
	]]
	SaltSpawnCount = 4,
	SaltDamage = 25,
	SaltStunDuration = 4,
	SaltRevealDuration = 10,
	SaltThrowRange = 25,
}
-- NOTE: the "V11 pins this" comment is STALE — V05 already added the assertion at
-- tests/config.test.luau:230-243. Worth correcting in Phase 2 while editing the block, per CLAUDE.md
-- Hard Rule 5 (say so rather than planning around it).
-- IMPORTANT: ZERO MARGIN. Nothing in V08 may move SaltDamage or SaltSpawnCount. If a step is tempted
-- to tune either for feel, the suite goes red and the answer is to stop, not to relax it.
-- IMPORTANT: V08 DOES bear on invariant 1 in a way the assertion cannot see. The suite reads Config;
-- it does not count pouches in the world. Two live salt economies (SaltSpawn pouches AND
-- container-seeded salt) put 8 in a round and break the invariant with the test green.

-- src/shared/Config.luau:51-69
	GarlicSpawnCount = 2,
	GarlicDuration = 15,
-- QUESTION: the build plan and this chunk's brief both say `BawangSpawnCount`; the code says
-- `Garlic*`, and `Types.ItemType` says `"BAWANG"`. Plan uses the on-disk name and renames nothing —
-- but a reader who greps one spelling misses the other. Raised in Follow Ups.
-- NOTE: `GarlicDuration = 15` is V09's number and V08 must not read it. Its presence in the block is
-- correct — one home for the item economy — but a V08 step touching it is out of scope.

-- src/shared/Config.luau:71-86
	--[[
		ONE IS A DESIGN CONSTANT, NOT A TUNABLE ... §8.3 is blunter: selling a second one sells the win
		condition, and it is named there as the sharpest monetisation temptation in the game.
		`check:scope` arms `weapons?` for the day someone adds a third item.
	]]
	BuntotPagiSpawnCount = 1,
-- IMPORTANT: THIS IS WHY THE TWO CRITICAL ISSUES IN THIS PLAN ARE CRITICAL. There is exactly one, it
-- IS the second win condition, and both the full-handed-search path (Phase 3) and the throw-key path
-- (Phase 4) can destroy it silently. Neither has a symptom distinguishable from ordinary play.

-- src/shared/Config.luau:452-518 — the Config.Salt table
Salt = {
	SpawnCount = Items.SaltSpawnCount,
	StunDuration = Items.SaltStunDuration,
	RevealDuration = Items.SaltRevealDuration,
	ThrowRange = Items.SaltThrowRange,

	CarryLimit = 1,
	PickupRangeStuds = 6,
	ThrowConeDegrees = 20,
	PouchPoolSize = 6,

	PouchRgb = { 240, 238, 225 },
	RevealGlowFillRgb = { 255, 250, 235 },
	RevealGlowOutlineRgb = { 190, 235, 255 },
},
-- NOTE: the four aliases die with their assertions at tests/config.test.luau:154-174.
-- NOTE: PouchPoolSize and PickupRangeStuds die with the pool and the tick they describe.
-- IMPORTANT: RevealGlow*Rgb are read by MonsterService.applyExposed (:868-869), NOT by ItemService.
-- They move to `Config.Monster`, beside the ExposedGlowTransparency* ramp they colour — not to
-- `Items`. MonsterService.luau:747 calls the current split "not an accident"; V08 ends it by moving
-- the colours to the ramp rather than the ramp to the colours.
-- NOTE: PouchRgb becomes three colours under Items (SaltRgb/BawangRgb/BuntotPagiRgb) — from Step 4.3
-- onward all three items can be lying on the floor and must be tellable apart.

-- src/shared/Config.luau:504-510 — PickupRangeStuds' comment
--[[
	**V03 owes this a new right-hand side**: the container search range is what it must sit under once
	that lands, and until then nothing in `tests/config.test.luau` pins it at all.
]]
-- NOTE: C13 asked for exactly the assertion V08 Phase 2 adds, pointed at the new drop radius:
-- `DropPickupRangeStuds < Search.RangeStuds`. The debt is paid by the number's successor rather than
-- by the number, which is the right outcome — the walk-over radius it described is being deleted.

-- src/shared/Config.luau:1371 and :1355-1362
RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
--[[
	Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here. The test
	pins BOTH directions ... Tune these LOOSER than legitimate play, never tighter.
]]
-- IMPORTANT: `RequestDropItem` needs an entry or `tests/anti-cheat-budgets.test.luau` fails, AND
-- AntiCheatService refuses the remote outright (see UnknownRemote). Both directions are pinned, so
-- Steps 2.3 and 2.4 are red apart and green together — which is why they are adjacent.
