--!strict
--[[
	REVIEW — src/shared/Config.luau
	Read for V10 planning: where the new range goes, what it must relate to, and the two numbers
	whose relationship the second win condition already depends on.
]]

-- src/shared/Config.luau:31-53 — the salt block's header
--[[
	READ THIS BEFORE CHANGING SaltDamage OR SaltSpawnCount. §6.5 invariant 1 requires
	`SaltDamage x (SaltSpawnCount - 1) >= Monster.MaxHealth - Monster.WeakenedThreshold` ... At the
	shipped values that is `25 x 3 = 75 >= 100 - 25 = 75` — EQUALITY, with zero margin. Every pouch
	but one must connect. ... V11 pins this; until V11 lands, this comment is the only guard.
]]
-- IMPORTANT ZERO MARGIN, AND V10 IS THE CHUNK THAT MAKES IT MATTER. Until now the invariant guarded
--           a win condition that could not be reached at all. From V10 it guards one that CAN, so a
--           tightening here becomes a silently unwinnable game rather than a theoretical one.
-- IMPORTANT This also sets the playtester's problem: three connecting throws inside one 10s reveal
--           window is the ONLY route to a live strike. The plan tells the playtester to lower
--           `SaltDamage` temporarily and revert it (Phase 4 issues).

-- src/shared/Config.luau:86 and 100-101 — where the new number goes
GarlicPlaceRangeStuds = 8,
GarlicBarrierHeight = 12,
GarlicBarrierPadStuds = 1.5,
-- NOTE `BuntotPagiStrikeRangeStuds` lands immediately after these. It is an ITEM's reach, so it
--      belongs in this `Items` local rather than under `Config.Monster` — the same reasoning
--      `GarlicPlaceRangeStuds` already applies one block up.

-- src/shared/Config.luau:406-410 — the number the new range must not exceed
Monster = {
	TransformTime = 1.2,
	RevertTime = 1.0,
	MaxTransformTime = 8,
	KillRange = 8, -- studs
	-- IMPORTANT The plan's config invariant is `BuntotPagiStrikeRangeStuds <= KillRange`. At the
	--           shipped values they are EQUAL, which is deliberate: closing to strike puts you
	--           exactly where the monster could take you. §C.5's third property — "it cannot be used
	--           to hunt; it can only finish" — is what a larger strike range would erode.

-- src/shared/Config.luau:440-443
	--[[
		WeakenedThreshold is a HEALTH PREDICATE, not a `MonsterState` member — see Enums.MonsterState.
	]]
	MaxHealth = 100,
	WeakenedThreshold = 25,
	-- IMPORTANT V10 reads NEITHER of these. `MonsterService.IsWeakened` already collapses them to a
	--           boolean, and the plan's §1.4 argues that keeping the number inside the one service
	--           that owns it is a decision, not laziness — a health value in a second service's
	--           local is where a log line or a payload field grows.

-- src/shared/Config.luau:497-503
	FeedDuration = 5,
	FeedHeal = 25,
	-- NOTE §4.6 calls the feed "the window the buntot pagi needs — without it, killing the Aswang is
	--      a coin flip against a faster player." So V10's mechanic depends on V06's timing, and
	--      `FeedLeashStuds = 6` (below) means a striker who walks to the corpse is within 6 studs of
	--      the feeder by construction. `BuntotPagiStrikeRangeStuds = 8` covers that with slack.
	FeedLeashStuds = 6,
}

-- src/shared/Config.luau:1605, 1688-1696 — the budget table
Budgets = {
	RequestPlaceGarlic = { Capacity = 3, RefillPerSecond = 0.25 },
	-- NOTE `RequestStrike` goes here. Priced like `RequestSmoke` (Capacity 2, Refill 0.1) rather
	--      than like a button press: an honest client fires it AT MOST ONCE PER ROUND, because the
	--      swing consumes the only buntot pagi and the second press hits STRIKE_NOT_HELD above the
	--      spend line.
	RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
}
-- IMPORTANT `AllowUnbudgetedRemote = false` elsewhere in this block means a MISSING entry REFUSES
--           rather than allows. Good direction — but the failure would be "the buntot pagi does
--           nothing", which is indistinguishable from the mechanic working, so the budget must land
--           with the remote rather than after it.
