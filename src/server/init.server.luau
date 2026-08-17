--!strict
--[[
	Server bootstrap.

	Loads every service in a deterministic order with a two-phase lifecycle:

	  Init()  — set up internal state, no cross-service calls. Runs for ALL
	            services before any Start() does.
	  Start() — wire up events, begin loops, talk to other services.

	The two phases exist so services can depend on each other without caring
	about load order. Add new services to the SERVICE_ORDER list below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SERVICE_ORDER = {
	-- Infrastructure first
	"AnalyticsService",
	"AntiCheatService",
	"ProgressionService",
	"BadgeService",
	"MonetizationService",
	"CommunityService",
	-- Gameplay
	"RoleService",
	"TaskService",
	"GateService",
	"MonsterService",
	"ItemService",
	"GhostService",
	"TrialService",
	--[[
		C23. After the four services that CALL it — ItemService, GhostService, MonsterService and
		TaskService — because those hold a module reference from their own `require` at load, and this
		list only governs Init/Start. It is placed here so `Start` has run before any gameplay can
		produce a cue, not because the require needs it.
	]]
	"TeachingService",
	-- The state machine drives everything, so it starts last
	"RoundService",
}

type Service = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	[string]: any,
}

local servicesFolder = script:WaitForChild("Services")
local loaded: { [string]: Service } = {}

local function log(message: string)
	print(`[Bootstrap] {message}`)
end

-- Phase 1: require + Init
for _, name in SERVICE_ORDER do
	local moduleScript = servicesFolder:FindFirstChild(name)
	if not moduleScript then
		warn(`[Bootstrap] Missing service module: {name}`)
		continue
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(`[Bootstrap] Failed to require {name}: {result}`)
		continue
	end

	loaded[name] = result
	if type(result) == "table" and type(result.Init) == "function" then
		local initOk, err = pcall(result.Init)
		if not initOk then
			warn(`[Bootstrap] {name}.Init() errored: {err}`)
		end
	end
end

-- Phase 2: Start
for _, name in SERVICE_ORDER do
	local service = loaded[name]
	if service and type(service.Start) == "function" then
		-- `:: any` because pcall over a `() -> ()` is typed as returning only the boolean,
		-- so binding `err` is an arity error under --!strict.
		local startOk, err = pcall(service.Start :: any)
		if not startOk then
			warn(`[Bootstrap] {name}.Start() errored: {err}`)
		end
	end
end

log(`Ready. {#SERVICE_ORDER} services loaded.`)

if Config.Debug.SoloTesting then
	warn("[Bootstrap] SoloTesting is ENABLED — do not ship with this on.")
end
