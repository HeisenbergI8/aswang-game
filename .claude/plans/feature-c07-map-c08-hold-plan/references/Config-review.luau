--!strict
-- REVIEW: src/shared/Config.luau:110-128 (Tasks), 197-227 (AntiCheat), and Ghost.TaskContributionMult
--
-- Every knob this plan needs except three already exists. The three it adds are presence tuning.

	Tasks = {
		TotalRequired = 5, -- how many must be completed to open the gate            -- :111
		PoolSize = 12, -- how many possible spawn points exist on the map            -- :112
		HoldTime = 8,                                                                -- :113
		TimingAttempts = 3,
		FetchTime = 25,
		TwoPersonTime = 12,
-- NOTE: TotalRequired and HoldTime are the two this plan reads. TimingAttempts, FetchTime and
-- TwoPersonTime belong to C09/C10 and are untouched — their presence here is not a licence to build
-- them.
-- QUESTION (Follow Ups Q5): PoolSize becomes ADVISORY under this plan. Discovery counts whatever is
-- tagged; PoolSize only drives TaskPool's OVERSIZED warning. After C17 the map is the authority, and a
-- number that can silently disagree with reality is worth deleting rather than maintaining.

		--[[
			The minimum distance between two SELECTED task points (§4.4, "spread")...
			It must exceed Monster.KillRange or the spread does nothing that matters
		]]
		MinSpacingStuds = 20,                                                        -- :127
-- IMPORTANT: this plan gives MinSpacingStuds a SECOND job, and the new one is correctness rather than
-- balance. Because RequestTaskProgress carries no arguments, the server resolves which task point a
-- player is at from position alone — which only has an answer if two selected points can never both be
-- in range. Step 1.4 pins PresenceRangeStuds * 2 < MinSpacingStuds for exactly that, and the knob's
-- own comment has to say so or M12 will tune it away as a pure balance number. Risk R6.

		Budgets = {
			-- A presence heartbeat while standing at a task point. Must out-pace the snapshot tick or
			-- a player holding a task is throttled while doing exactly what the game asked of them.
			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },              -- :204
		},
-- IMPORTANT: the budget ALREADY EXISTS and is already the right shape — no change to AntiCheat is
-- needed anywhere in this plan. NOTE the comment states an intent ("must out-pace") that nothing
-- checked, because until now no number drove the sends. Step 1.4 adds HeartbeatInterval = 0.25 and
-- pins 1/0.25 = 4/s < 6/s, which turns that sentence into an invariant.
-- NOTE Capacity 12 covers three seconds of holding at 4/s with the refill stopped, which is the
-- reconnect-retry headroom the comment two lines down asks for on the other remotes.

		-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
		-- The test pins BOTH directions
-- NOTE: tests/anti-cheat-budgets.test.luau already covers this and needs no change, because this plan
-- adds no remote. Confirmed against Remotes.luau:35-44.

		AllowUnbudgetedRemote = false, -- FAIL CLOSED                                 -- :222
-- NOTE: worth knowing for Step 4.1 — if the budget name were ever misspelled at the Consume call site,
-- the request is REFUSED rather than silently unlimited, so the symptom is "tasks do not work at all"
-- rather than "the limiter is off". Loud, which is the right direction.

	Ghost = {
		TaskContributionMult = 0.25, -- ghosts progress tasks at 25% speed
-- IMPORTANT for Step 3.1's design even though C15 is far away. It is the value that proves the rate
-- must be a MAX over contributors rather than a sum: with a max, a ghost helping a survivor is neither
-- faster nor slower than the survivor alone, which is what §4.7's "they still matter" means and what
-- "they stack" would not. tests/task-progress.test.luau asserts it against this exact constant.

		--[[ STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
			LUNE, which has no Roblox datatypes at all. ]]                             -- :95-100
-- IMPORTANT constraint on the three new knobs: they are plain numbers, which is fine. But it is the
-- reason tests/task-progress.test.luau can `require("../src/shared/Config")` and read HoldTime and
-- TaskContributionMult directly instead of duplicating them — the test asserts against the SHIPPING
-- numbers, not against a copy that can drift.
