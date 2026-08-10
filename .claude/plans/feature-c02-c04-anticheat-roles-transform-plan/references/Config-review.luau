--!strict
--[[
	REVIEW — src/shared/Config.luau

	Every number this plan touches, plus one constraint on this file that is not obvious and would break
	the whole test suite if missed.
]]

Round = {
	StartingDelay = 4, -- IMPORTANT: the Aswang intro (3s) must finish inside this. Step 1.2 pins it.
	MinPlayers = 3, -- with AswangCount = 1 this leaves 2 survivors at the floor. Step 1.2 pins it.
	MaxPlayers = 8, -- the unweighted back-to-back baseline in tests/role-draw.test.luau is 1/8
	SnapshotInterval = 0.5, -- RequestTaskProgress must refill faster than this. Step 1.1 pins it.
},

Roles = {
	AswangCount = 1,
	RepeatCooldownRounds = 2, -- becomes RoleDraw.Weights.HistoryRounds
	IntroDuration = 3, -- read by UIController; typing `3` there would fail check:config
	-- Step 1.2 ADDS: BaseWeight, RecentAswangWeight, OlderAswangWeight
},

Monster = {
	TransformTime = 1.2, -- the visible windup. Broadcast fires BEFORE it, not after (§4.3).
	RevertTime = 1.0,
	MaxTransformTime = 8, -- measured from windup COMPLETION in this plan; see Step 7.1
	KillCooldown = 30, -- IMPORTANT: also used as the re-transform gate. See Follow Up #4.
	TransformedSpeedMult = 1.25,
	TransformAudioRange = 40, -- AudioController's RollOffMaxDistance
	-- Step 6.4 ADDS: TransformedScale, TransformedTintRgb, EyeGlowRgb, EyeGlowRange,
	--                EyeGlowBrightness, TransformParticleRate
},

Performance = {
	MaxVisibleLights = 8, -- two PointLights per transformed Aswang draw from this
},

Debug = {
	SoloTesting = false, -- pinned false by tests/config.test.luau; the playtester turns it on locally
	VerboseLogging = false, -- gates the RoleService draw log and the transform-refusal log
},

--[[
	IMPORTANT — THE CONSTRAINT THAT IS NOT WRITTEN ANYWHERE IN THIS FILE.

	`tests/config.test.luau` does `require("../src/shared/Config")` under LUNE, which has no Roblox
	datatypes at all. So this file may contain NO `Color3`, `Vector3`, `UDim2`, `Enum` or `Instance`
	value, ever.

	A `Color3.fromRGB(...)` added here does not fail to typecheck. It fails at TEST time, in every
	balance test at once, with an error naming Config rather than naming the edit that broke it. That
	is why Step 6.4 stores the monster's colours as RGB number triples and has MonsterService build the
	Color3.

	NOTE this file is also EXEMPT from check:config — check-config.mjs governs `src/(server|client)/`
	only. `src/server/pure/RoleDraw.luau` is therefore governed and `src/shared/pure/TokenBucket.luau`
	is not, which is one of the two measured consequences of the plan's §1.1 decision.
]]
