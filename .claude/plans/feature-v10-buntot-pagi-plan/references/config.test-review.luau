--!strict
--[[
	REVIEW — tests/config.test.luau
	Read for V10 planning: this is where Step 1.2's two invariants go, and where §6.5 invariant 1 —
	the one that silently kills the second win condition — is currently NOT pinned.
]]

-- CLAUDE.md's description of what this suite is for, which is worth having beside the diff:
--[[
	`tests/config.test.luau` pins *relationships* between those numbers, not the numbers themselves —
	salt must reach further than the Aswang kills, the reveal must outlast the stun, the feed must
	last longer than it takes to cross fifteen studs and swing. Those are silent invariants: no
	symptom tells you when two numbers that must agree have stopped agreeing.
]]
-- NOTE "the feed must last longer than it takes to cross fifteen studs and swing" IS ABOUT V10'S
--      SWING. §6.5 invariant 2 was written for this chunk before it existed.

-- IMPORTANT §6.5 INVARIANT 1 IS NOT IN THIS FILE YET AND V10 IS WHAT MAKES ITS ABSENCE MATTER.
--           `Config.luau:31-40` says so in as many words: "V11 pins this; until V11 lands, this
--           comment is the only guard." The invariant is
--             `SaltDamage x (SaltSpawnCount - 1) >= MaxHealth - WeakenedThreshold`
--           and at shipped values it holds with EQUALITY and zero margin. Until V10, it guarded a
--           win condition nobody could reach; from V10 it guards one that works, so a tightening
--           becomes a silently unwinnable game.
-- QUESTION  SHOULD V10 PIN INVARIANT 1 RATHER THAN WAITING FOR V11? The plan says no — V11's Done
--           line explicitly owns "the six invariants from spec §6.5" and splitting them across two
--           chunks is how one gets forgotten. But V10 is the chunk that arms the failure, so the
--           argument for pulling invariant 1 forward is real. Decide before Phase 1; if pulled
--           forward, it becomes a fourth assertion in Step 1.2 and V11's list drops to five.

-- The existing item invariants this file already carries, which Step 1.2's diff sits beside:
--   · SaltThrowRange > Monster.KillRange              (§6.5 invariant 3)
--   · SaltRevealDuration > SaltStunDuration           (§6.5 invariant 6)
--   · ThrowConeDegrees < 90
--   · DropForwardStuds >= DropPickupRangeStuds
--   · FeedLeashStuds < Monster.KillRange
--   · ExposedGlowTransparencyWeakened < ...Full
-- NOTE THE HOUSE STYLE IS `assert(condition, message)` WITH THE ACTUAL VALUES INTERPOLATED INTO THE
--      MESSAGE, not a bare assert. Step 1.2's diff follows it; a failure that does not print the two
--      numbers sends the reader back to Config to find out which one moved.

-- src/shared/Config.luau:695-701, quoted here because Step 1.2's first invariant relates to it
	--[[
		IT IS ALSO JUST OUTSIDE `Monster.KillRange` (8) AT THIS VALUE, which is worth seeing rather
		than deriving ...
	]]
-- IMPORTANT `Monster.KillRange = 8` IS THE ANCHOR FOR THREE RELATIONSHIPS NOW: salt must reach
--           further than it (invariant 3), the feed leash must be shorter than it, and V10 adds that
--           the strike range must not EXCEED it. Anyone tuning KillRange during V16 moves all three.
--           Worth a comment at the Config site as well as here.

-- QUESTION IS `<=` OR `<` RIGHT FOR THE STRIKE RANGE? The plan chooses `<=`, so the shipped values
--          are EQUAL (8 and 8) — closing to strike puts you exactly where the monster could take
--          you, which is the intended feel and the strongest reading of §C.5's "it can only finish".
--          `<` would force a strictly braver approach and is defensible. This is a V16 balance
--          question wearing an invariant's clothes; the plan pins the safe direction and says so.

-- NOTE This suite prints a PASS line with an assertion count. Update it if the file carries one, or
--      the count silently understates what ran — which is the same class of quiet failure the suite
--      exists to catch.
