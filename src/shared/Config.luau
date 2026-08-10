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
	},

	Roles = {
		AswangCount = 1,
		-- A player who was Aswang recently gets reduced weight in the draw.
		-- Nothing kills a session faster than never being the monster.
		RepeatCooldownRounds = 2,
		IntroDuration = 3,
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

	Performance = {
		-- Mobile is ~60% of players. Many dynamic lights is the #1 mobile FPS killer.
		MaxVisibleLights = 8,
		TargetFPSMobile = 30,
	},

	Debug = {
		-- Set true in Studio to allow solo testing without MinPlayers.
		SoloTesting = false,
		VerboseLogging = false,
	},
}

return Config
