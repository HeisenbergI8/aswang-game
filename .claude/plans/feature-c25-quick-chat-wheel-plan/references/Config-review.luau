--!strict
--[[
	REVIEW — src/shared/Config.luau:82, 274, 283-284, 358, 480-506, 547-556

	Read for two things: where the C25 block goes and what it must relate to, and confirmation that
	the RequestQuickChat budget already exists.
]]

	Monster = {
		KillRange = 8, -- studs
	},

	Tasks = {
		MarkerVisibleStuds = 220,
	},

	Salt = {
		RevealDuration = 10,
		ThrowRange = 25,
	},

	Ghost = {
		-- "Thirty studs is comfortably larger than `Monster.KillRange` (8) and than
		-- `Tasks.PresenceRangeStuds` (9), so 'a light flickered near me' narrows nothing."
		SpookRangeStuds = 30,
	},

--[[
	IMPORTANT — THE SPOOK RANGE COMMENT IS THE MODEL FOR `AccuseRangeStuds`, and it is the best
	existing example in this file of a range justified by what it does NOT reveal. Thirty studs is
	chosen so the resulting signal narrows nothing.

	C25's number needs the same treatment from both sides, and the plan pins both in
	tests/config.test.luau:
	  · > Monster.KillRange (8). §4.5 exists for the moment something is close enough to kill you and
	    you cannot type. A range that cannot name the thing on top of you is pointless.
	  · << Tasks.MarkerVisibleStuds (220). This is the security half. The accusation resolves from the
	    sender's own position, so a large range is a pollable proximity radar, and the player who
	    gains most from "who is near me, through walls" is the Aswang mid-hunt.

	40 sits between Salt.ThrowRange (25) and Ghost.SpookRangeStuds (30) at the low end and nowhere
	near the marker range, which is the right neighbourhood: you can accuse someone you could have
	thrown salt at, and not much further.

	NOTE — line of sight, not this number, is the primary defence. See QuickChatService's header. If
	that requirement is ever relaxed, this number becomes load-bearing in a way it is not today.
]]

--------------------------------------------------------------------------------
-- Config.luau:484-506 — the budget already exists
--------------------------------------------------------------------------------

		Budgets = {
			-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
		},

-- NOTE: already present and correctly priced. Four in a burst, one per two seconds sustained — the
-- "deliberate, rare acts" band the transform/kill/throw entries above it occupy, which is right for a
-- thumb press and wrong for a heartbeat. C25 changes neither number.

		-- FAIL CLOSED. A remote with no budget is refused, not allowed.
		AllowUnbudgetedRemote = false,
		-- C02 LOGS. C41 ENFORCES.
		LogOnly = true,

--[[
	IMPORTANT — `LogOnly = true` means a rate-limited quick chat is refused silently. During
	playtesting a player mashing the wheel will see messages simply not appear, with only a throttled
	server warn as evidence. Brief the playtester on this or it reads as a broken feature.

	NOTE — the `Budgets` header says "Every name here must appear in Remotes.EVENTS_UP, and every name
	there must appear here. The test pins BOTH directions." That bidirectional pin is the thing a
	third remote for the world ping would have had to satisfy in three files. See
	anti-cheat-budgets-review.luau.
]]

--------------------------------------------------------------------------------
-- Config.luau:547-556 — the debug values the playtester needs and must not commit
--------------------------------------------------------------------------------

	Debug = {
		SoloTesting = false,
		VerboseLogging = false,
		ForceAswangWhenSolo = false,
	},

-- IMPORTANT: the playtester cannot edit this file and will correctly refuse. C25 needs THREE clients
-- to observe the audience rule (a living sender, a living recipient, a ghost), so SoloTesting alone
-- is not enough — the round timings must be shortened too. Set Round.Intermission/Duration/EndScreen
-- and these flags BEFORE launching the playtester, then revert all five. `guard-commit.mjs` runs
-- check:debug and refuses the commit otherwise, which is the plan's Step 5.4.

-- QUESTION — resolved: does `FilterDisplayNames` belong in the QuickChat block or in AntiCheat? The
-- QuickChat block, with a `-- config-ok:` waiver, because it is a policy switch rather than a
-- tunable and check:config will otherwise flag it. Putting it in AntiCheat would imply it is part of
-- the rate-limit surface, which it is not.
