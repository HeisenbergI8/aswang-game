--!strict
--[[
	Config — every tunable number in the game lives here.

	Rule: no magic numbers anywhere else in the codebase. During playtesting you
	will change these constantly; hunting them across ten files wastes a weekend.

	See docs/MVP-SPEC.md Appendix A for guidance on which knob to turn when.
]]

local Config = {
	Round = {
		Intermission = 25, -- seconds in lobby before a round starts
		Duration = 420, -- 7 minutes of "night" before sunrise
		EndScreen = 12, -- reveal + stats screen
		StartingDelay = 4, -- role assignment + teleport fade
		MinPlayers = 3, -- MUST be playable at this count (see spec §9 cold start)
		MaxPlayers = 8,
		-- How often the server pushes a RoundSnapshot to each client. This is a network cost paid
		-- per player per tick, and 60% of players are on a phone — raise it if the HUD stutters,
		-- lower it only with the mobile budget in mind.
		SnapshotInterval = 0.5,
	},

	Roles = {
		AswangCount = 1,
		-- A player who was Aswang recently gets reduced weight in the draw.
		-- Nothing kills a session faster than never being the monster.
		RepeatCooldownRounds = 2,
		IntroDuration = 3,

		--[[
			The anti-repeat weights (§4.2 "heavily reduced weight"). A player's draw weight is picked by
			how many rounds ago they were last the Aswang:

				1 round ago                        -> RecentAswangWeight
				2..RepeatCooldownRounds rounds ago -> OlderAswangWeight
				never, or longer ago               -> BaseWeight

			NONE OF THESE MAY BE ZERO. A zero weight is not "unlikely", it is "impossible", and with
			MinPlayers = 3 a zero-weight rule can leave a round with no eligible Aswang at all. The draw
			would then have to fall back to something, and a fallback that fires under a condition
			nobody tested is worse than a small number. `tests/role-draw.test.luau` proves no player
			starves; `tests/config.test.luau` proves the numbers stay ordered and positive.
		]]
		BaseWeight = 1,
		RecentAswangWeight = 0.1,
		OlderAswangWeight = 0.4,
	},

	Monster = {
		TransformTime = 1.2, -- visible windup — the core risk/reward moment
		RevertTime = 1.0,
		MaxTransformTime = 8, -- forced revert if no kill
		KillRange = 8, -- studs
		KillCooldown = 30, -- seconds after revert
		TransformedSpeedMult = 1.25,
		TransformAudioRange = 40, -- how far the transform sound carries
		CorpseDuration = 45,

		--[[
			The transform's LOOK (§4.3). No custom mesh — avatar scale, a colour and material shift,
			glowing eyes and a particle emitter. That is why this mechanic is cheap, and cheap is
			load-bearing for a project with no art budget.

			STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
			LUNE, which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to
			typecheck — it fails at TEST time, in every balance test at once, with an error naming
			Config rather than the edit that broke it. MonsterService builds the Color3.
		]]
		TransformedScale = 1.15,
		TransformedTintRgb = { 90, 20, 20 },
		EyeGlowRgb = { 255, 45, 45 },
		EyeGlowRange = 6,
		EyeGlowBrightness = 3,
		TransformParticleRate = 12,
	},

	Tasks = {
		TotalRequired = 5, -- how many must be completed to open the gate
		PoolSize = 12, -- how many possible spawn points exist on the map
		HoldTime = 8,
		TimingAttempts = 3,
		FetchTime = 25,
		TwoPersonTime = 12,
	},

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

	Economy = {
		XPPerRound = 50,
		XPWinBonus = 40,
		XPSurvivorEscapeBonus = 25,
		CoinsPerRound = 25,
		XPPerLevel = 500,
	},

	-- The Solo Trial: tutorial + low-population fallback. See spec §9.1.
	-- Exists because the closest competitor lost 79.9% of players before their
	-- first objective (Appendix C). Must never grow into a PvE campaign.
	Trial = {
		Enabled = true,
		Duration = 90,
		TasksToComplete = 2,
		ScriptedChaseAt = 55, -- seconds in: the Aswang reveals itself
		OfferBelowPlayerCount = 3, -- == Round.MinPlayers
	},

	Community = {
		GroupId = 0, -- TODO(M10): set once the Roblox group exists
		GroupJoinRewardCoins = 250,
	},

	-- Award thresholds mirror the public funnel we can read back via the API.
	Badges = {
		Welcome = 0, -- TODO(M9): fill in badge IDs after creating them
		FirstTask = 0,
		FirstRound = 0,
		FirstBlood = 0,
		BalikBalik = 0,
		-- LAUNCH GATE: FirstTask / Welcome must exceed this or FTUE is broken.
		FirstTaskConversionGate = 0.50,
	},

	Performance = {
		-- Mobile is ~60% of players. Many dynamic lights is the #1 mobile FPS killer.
		MaxVisibleLights = 8,
		TargetFPSMobile = 30,
	},

	--[[
		Rate limits, one budget per client->server remote (C02).

		A budget is a token bucket: `Capacity` tokens, refilling at `RefillPerSecond`, one token per
		request. Capacity is the BURST a legitimate player may produce in one moment; RefillPerSecond is
		the SUSTAINED rate they may hold.

		Tune these LOOSER than legitimate play, never tighter. A limiter that refuses a real player is a
		gameplay bug that presents as lag, and it is far more expensive than an exploiter getting three
		extra requests through — the validation behind the limiter is what actually refuses them.
		`tests/anti-cheat-budgets.test.luau` pins that relationship for the remotes where a legitimate
		cadence is known.
	]]
	AntiCheat = {
		-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
		-- The test pins BOTH directions, because a budget for a remote that no longer exists is a
		-- rename nobody noticed and a remote with no budget is refused outright (see UnknownRemote).
		Budgets = {
			-- A presence heartbeat while standing at a task point. Must out-pace the snapshot tick or
			-- a player holding a task is throttled while doing exactly what the game asked of them.
			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },
			-- Deliberate, rare acts. Capacity covers a double-tap and a reconnect retry; nothing more.
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
			RequestGhostSpook = { Capacity = 2, RefillPerSecond = 0.05 },
			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
			RequestClaimDaily = { Capacity = 2, RefillPerSecond = 0.1 },
		},

		-- One request costs one token. Here rather than in the service so C41 can price an expensive
		-- handler higher without touching code.
		DefaultCost = 1,

		-- FAIL CLOSED. A remote with no budget is refused, not allowed. The alternative — allowing the
		-- unknown — means a new remote added without a budget is silently unlimited, which is exactly
		-- the state C02 exists to make impossible.
		AllowUnbudgetedRemote = false,

		-- C02 LOGS. C41 ENFORCES. Kicking on a rate limit before there is real data behind the numbers
		-- kicks real players on bad connections, and a false kick is unrecoverable.
		LogOnly = true,
		-- One log line per player per remote per this many seconds. An exploiter firing 1000/s would
		-- otherwise produce 1000 warn() calls per second, which is its own denial of service.
		LogThrottleSeconds = 5,
	},

	Debug = {
		-- Set true in Studio to allow solo testing without MinPlayers.
		SoloTesting = false,
		VerboseLogging = false,
	},
}

return Config
