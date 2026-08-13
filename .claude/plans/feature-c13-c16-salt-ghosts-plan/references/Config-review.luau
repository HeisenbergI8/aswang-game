--!strict
--[[
	REVIEW — src/shared/Config.luau (410 lines)

	Excerpted ranges:
	  · src/shared/Config.luau:92-101    the RGB-triple rule, which every new colour knob obeys
	  · src/shared/Config.luau:169-186   the two-person derivation, which settles C15 in advance
	  · src/shared/Config.luau:280-292   the Salt and Ghost blocks Phase 1 extends
	  · src/shared/Config.luau:335-378   the AntiCheat budgets, and why this plan adds none

	Phase 1 adds eight knobs and changes no existing value.
]]

-- src/shared/Config.luau:96-100
--	STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
--	LUNE, which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to
--	typecheck — it fails at TEST time, in every balance test at once, with an error naming
--	Config rather than the edit that broke it.
-- IMPORTANT BINDS `Salt.PouchRgb`, `RevealGlowFillRgb` and `RevealGlowOutlineRgb` (Step 1.1). The failure
--      is maximally misleading: every balance test red, all naming Config, none naming the edit.
-- NOTE It is also why `ItemService` needs its own private `rgb()` helper, copied from
--      MonsterService.luau:133 with its `-- config-ok: RGB channel indices` waiver. Step 2.5's snippet
--      calls one that does not exist yet; recorded in Phase 2's Issues.

-- src/shared/Config.luau:179-183
--		It also settles C15 in advance without a second decision: a ghost weighs
--		`Ghost.TaskContributionMult` (0.25), so two ghosts do not open a two-person task. §4.4 says
--		"2 survivors present", and §4.7 says ghosts "still matter", not that they substitute.
-- IMPORTANT PHASE 8 MUST NOT DISTURB THIS, and it does not have to: `TwoPersonParticipants` is derived
--      from `FullContributionWeight` rather than restated, so the property is arithmetic rather than a
--      rule someone enforces. Step 8.2 promotes the claim from this comment into an assertion, because a
--      future ghostMult of 0.5 would break it silently in a two-ghost round nobody tests.

-- src/shared/Config.luau:280-292
	Salt = {
		SpawnCount = 4,
		StunDuration = 4,
		RevealDuration = 10,
		ThrowRange = 25,
		CarryLimit = 1,
	},

	Ghost = {
		TaskContributionMult = 0.25, -- ghosts progress tasks at 25% speed
		SpooksPerRound = 1,
		FlySpeed = 24,
	},
-- NOTE EVERY NUMBER §4.6 AND §4.7 NAME IS ALREADY HERE, unused, since C01. This plan changes none of
--      them — `tests/config.test.luau:69-82` pins ThrowRange > KillRange and RevealDuration >
--      StunDuration, and both relations survive Phase 1 untouched.
-- NOTE What is missing is everything the IMPLEMENTATION needs and the spec does not name: a pickup
--      radius, a throw cone, a pool size, three colours, a roster interval, a spook range and duration.
--      Eight knobs, added in Step 1.1, each with a comment saying what breaks if it moves.

-- src/shared/Config.luau:373-375
				RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
				RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
				RequestGhostSpook = { Capacity = 2, RefillPerSecond = 0.05 },
-- IMPORTANT BOTH HANDLERS THIS PLAN WRITES ALREADY HAVE BUDGETS, so `AntiCheat.Budgets` needs no edit and
--      `tests/anti-cheat-budgets.test.luau` (which pins both directions of the
--      Remotes.EVENTS_UP ↔ Budgets correspondence) keeps passing unchanged.
-- NOTE Both are far looser than legitimate play, which is the direction this table's header requires:
--      with CarryLimit = 1 a player can throw at most four times a round against a capacity of 3, and the
--      spook budget allows one per twenty seconds against a rule of one per round.
-- IMPORTANT THE ONE THING THAT WOULD CHANGE THIS: Phase 7's fallback, if the TextChatService spike fails.
--      A `RequestGhostChat` remote needs an entry here, and adding one to EVENTS_UP without one here is
--      refused outright — `AllowUnbudgetedRemote = false`, fail closed. Recorded in Follow Up 5.

-- src/shared/Config.luau:349-351
			-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
			-- The test pins BOTH directions, because a budget for a remote that no longer exists is a
			-- rename nobody noticed and a remote with no budget is refused outright
-- NOTE Phase 6 adds `GhostRoster` to EVENTS_DOWN only. Down-remotes have no budget by construction, so
--      this correspondence is unaffected — worth checking rather than assuming, because the test's error
--      message would name Remotes rather than the plan step that caused it.
