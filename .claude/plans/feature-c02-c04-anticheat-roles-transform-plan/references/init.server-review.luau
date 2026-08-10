--!strict
--[[
	REVIEW — src/server/init.server.luau

	Read to answer one question: does this plan need to change the bootstrap? It does not.
]]

local SERVICE_ORDER = {
	-- Infrastructure first
	"AnalyticsService",
	"AntiCheatService", -- IMPORTANT: already SECOND, ahead of every gameplay service. Its Init() runs
	--                     long before MonsterService.Start() connects the first handler. No change.
	"ProgressionService",
	"BadgeService",
	"MonetizationService",
	"CommunityService",
	-- Gameplay
	"RoleService", -- already present. No change.
	"TaskService",
	"MonsterService", -- already present. No change.
	"ItemService",
	"GhostService",
	"TrialService",
	-- The state machine drives everything, so it starts last
	"RoundService",
}

--[[
	IMPORTANT — the two-phase lifecycle, and why it makes `local rng: Random = nil :: any` safe:

		"Init()  — set up internal state, no cross-service calls. Runs for ALL services before any
		           Start() does."

	Every Init() completes before any Start(). RoleService.Init() creates the RNG; nothing can reach
	AssignRoles before that, because the only caller is RoundService.enterStarting, which runs off a
	loop started in RoundService.Start().
]]

--[[
	IMPORTANT — the failure this plan must not introduce. Both loops pcall and only WARN:

		local ok, result = pcall(require, moduleScript)
		if not ok then warn(`[Bootstrap] Failed to require {name}: {result}`) continue end

	A require CYCLE (RoleService requiring RoundService back) therefore does not crash the server. It
	produces one warn line and a server missing a service, which looks exactly like normal operation
	until a round never starts. The plan's require graph is a DAG:
	  MonsterService -> RoundService -> RoleService,  MonsterService -> {RoleService, AntiCheatService}
]]

--[[
	NOTE — the strict-Luau idiom this plan reuses for `rng`:

		-- `:: any` because pcall over a `() -> ()` is typed as returning only the boolean,
		-- so binding `err` is an arity error under --!strict.
		local startOk, err = pcall(service.Start :: any)
]]
