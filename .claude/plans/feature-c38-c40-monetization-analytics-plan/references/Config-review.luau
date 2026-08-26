--!strict
--[[
	REVIEW — src/shared/Config.luau:12-18, :641-660, :729-746, :1022-1090

	Read for two things: the zeroed-id precedent C38 must copy, and the budgets table Phase 4 adds
	to. Also the round durations the plan's new cache-TTL invariant is pinned against.
]]

-- src/shared/Config.luau:729-746
	Community = {
		GroupId = 0, -- TODO(M10): set once the Roblox group exists
		GroupJoinRewardCoins = 250,
	},

	-- Award thresholds mirror the public funnel we can read back via the API.
	Badges = {
		Welcome = 0, -- TODO(M9): fill in badge IDs after creating them
		FirstTask = 0,
		...
	},
-- IMPORTANT: THE PRECEDENT THE BRIEF NAMES. Ids that a human must create in the Creator Hub sit at
--            0 in Config with a TODO, and every read guards on `~= 0` and no-ops. `Config.Monetization`
--            is placed immediately after `Community` and before `Badges` so all three "awaiting a
--            human" blocks read together.
--
-- NOTE, and it matters for expectations: `BadgeService.luau` is still a 23-line C01 stub, so there
--       is no existing IMPLEMENTED zero-id guard to copy — only the DATA convention. C38 writes the
--       first one. Nothing mechanical enforces the guard; `tests/config.test.luau` asserting every
--       catalogue id is still 0 is the closest this plan gets, and it guards the opposite mistake
--       (a real id committed before C37).

-- src/shared/Config.luau:12-18
	Round = {
		Intermission = 25,
		Duration = 420,
		EndScreen = 12,
		...
	},
-- NOTE: 25 + 420 + 12 = 457 seconds for one full cycle. `Monetization.GamepassCacheSeconds = 600`
--       is pinned ABOVE that in tests/config.test.luau, so the cache outlives a whole round and a
--       player is not re-queried every round for an answer that almost never changes.
-- NOTE: `EndScreen = 12` is the window `ShopOffer` has to arrive in. A cold-cache
--       `UserOwnsGamePassAsync` per player eats into it — the plan's Phase 4 issue about warming
--       the cache at `ProfileLoaded` instead.

-- src/shared/Config.luau:641-660
	Profile = {
		...
		ShutdownFlushBudget = 25,
	},
-- IMPORTANT: "ROBLOX GIVES ABOUT 30 SECONDS AND THEN KILLS THE PROCESS MID-WRITE". C38's
--            `ReceiptDurabilityTimeout` is pinned UNDER this in tests/config.test.luau, because a
--            receipt can arrive during BindToClose and a durability wait longer than the flush
--            budget is a wait the process does not survive — the purchase is then answered by
--            nobody, which Roblox reads as no answer and retries. Recoverable, but only by luck.

-- src/shared/Config.luau:1022-1090
	AntiCheat = {
		-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
		Budgets = {
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			...
			RequestBuyCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
			RequestClaimDaily = { Capacity = 2, RefillPerSecond = 0.1 },
		},
		AllowUnbudgetedRemote = false,
		LogOnly = true,
	},
-- IMPORTANT: `AllowUnbudgetedRemote = false` — FAIL CLOSED. A remote with no budget is REFUSED, so
--            forgetting Step 4.2 makes the shop button silently do nothing rather than making it
--            unlimited. The plan says so at the step, because "no error, no effect" is the hardest
--            kind of bug to attribute.
-- NOTE: `RequestOpenShop` is priced like `RequestEquipCosmetic` (browsing), `RequestPromptPurchase`
--       like `RequestGhostSpook` (a deliberate, rare act that opens a modal).
-- IMPORTANT: `LogOnly = true` until C41 — "C02 LOGS. C41 ENFORCES." So a rate limit today produces a
--            warn, not a refusal. Phase 4's handlers must still branch on `Consume`'s return value;
--            they simply will not observe a false yet.

-- NOTE: `check-config.mjs`'s GOVERNED regex is `src/(server|client)/`, so Config.luau itself is not
--       scanned — `npm run check:config` is the WRONG verify line for a Config edit, which is why
--       Step 1.1 gates on `lune run tests/config.test.luau` instead.
