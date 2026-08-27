--!strict
--[[
	REVIEW — src/shared/Config.luau:26-88, 277, 316-334, 1055-1097
	Read for V03 to answer QUESTION 4: which keys exist, which must be added. Answer: V02 landed
	almost everything; V03 adds ONE gameplay key and TWO budgets.
]]

--------------------------------------------------------------------------------
-- ALREADY THERE, from V02. Config.luau:26-88 (the hoisted `Items` local).
--------------------------------------------------------------------------------

local Items = { -- :26
	SaltSpawnCount = 4, -- :38
	GarlicSpawnCount = 2, -- :66
	BuntotPagiSpawnCount = 1, -- :86
}
-- NOTE V03 reads exactly these three and sums them for SearchPool's `required`. Summing rather than
-- typing 7 is what keeps `check:config` quiet AND what makes a V16 tune move the pool requirement
-- with it.

-- IMPORTANT (:71-79) BuntotPagiSpawnCount = 1 is "A DESIGN CONSTANT, NOT A TUNABLE", and §8.3 calls
-- selling a second one "the sharpest monetisation temptation in the game". ContainerLayout takes it
-- as a parameter like any other count — the module cannot enforce a design constant — but the SHORT
-- priority order places it FIRST for exactly this reason: it is the only thing that kills.

-- IMPORTANT (:29-37) Invariant 1 is at EQUALITY with zero margin: SaltDamage x (SaltSpawnCount - 1)
-- = 25 x 3 = 75 = MaxHealth - WeakenedThreshold. "V11 pins this; until V11 lands, this comment is the
-- only guard." V03 must not touch SaltSpawnCount — and note that V03's new pool-ratio assertion reads
-- it, so raising it later now fails TWO ways instead of zero.

--------------------------------------------------------------------------------
-- Config.Search, V02, at :316-334. TWO of the three keys are used by V03.
--------------------------------------------------------------------------------

	Search = {
		ContainerCount = 15, -- :324  read as SearchPool's `expected`
		SearchTime = 6, -- :327     the hold duration
		-- IMPORTANT V03 READS THIS NOWHERE. Noise is V04. §4.4 calls noise "the entire risk economy",
		-- so V03 ships the COST of searching without the RISK — stated in the plan's Follow Ups so
		-- nobody judges the loop's feel before V04 lands.
		NoiseRadius = 60, -- :333
	},

-- NOTE the existing comment on ContainerCount (:321-323) already says "It must comfortably exceed the
-- total items placed (Items.*SpawnCount sums to 7) or every container is a hit and searching stops
-- being a gamble." V03 turns that sentence into an assertion in tests/config.test.luau — which is
-- what §6.5 asks for, since a comment cannot fail.

-- ADDED BY STEP 1.3. The only new gameplay tunable in the chunk.
+		RangeStuds = 10,
-- QUESTION This is a guess, not a derivation. It sits just above Monster.KillRange (8), which says
-- "a searcher stands roughly where the monster can reach them" — §4.4's trade. Pinned only by a > 0
-- floor because I could not find a relationship that is true rather than merely plausible. V16.

--------------------------------------------------------------------------------
-- The precedent for it, at :277.
--------------------------------------------------------------------------------
		PickupRangeStuds = 6, -- Config.Salt
-- NOTE Salt is picked up by WALKING OVER it, so 6 is a footprint. A container is opened by STANDING
-- AT it for six seconds, so V03's radius is an arm's length plus the slack a phone player needs to
-- hold still — §5 puts ~60% of players on one, and a radius tuned on a mouse cancels their search
-- every time the thumbstick drifts. That is the whole argument for 10 > 6.

--------------------------------------------------------------------------------
-- Config.AntiCheat.Budgets, :1059-1097. TWO entries added by Step 2.3.
--------------------------------------------------------------------------------
		Budgets = { -- :1059
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
			-- NOTE The existing spread is Capacity 2-5, Refill 0.05-0.5. V03's RequestSearch at
			-- {4, 0.3} is the most permissive gameplay verb in the table, which is correct: it is
			-- the most frequent honest action in v2.0 and a six-second hold rate-limits itself.
		}

--[[
	IMPORTANT — THE FILE'S ONE LOCAL AND WHY IT EXISTS (Config.luau:11-24). `Config.Salt` is now an
	ALIAS of the hoisted `Items` table for four fields, because §6.5 renamed them and five live modules
	still read the old names. "Config.Salt shrinks to nothing as each consumer is renamed, and
	disappears with the last one."

	V03 READS THE CANONICAL NAMES (Config.Items.*) EXCLUSIVELY and adds no consumer of the aliases. It
	also renames nothing — V03 is not the rename chunk, and touching a consumer would put it in the way
	of V08.
]]
