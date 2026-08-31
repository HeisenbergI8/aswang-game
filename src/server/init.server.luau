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
	--[[
		V07. BEFORE `MonsterService`, which requires it for `ClaimSlot`/`ReleaseSlot`.

		ORDER MATTERS IN ONE DIRECTION ONLY, and it is satisfied with a lot of room to spare:
		`AmbientService.Start` must have spawned the population before any `ClaimSlot` can succeed,
		and a claim cannot happen before a round is ACTIVE — many seconds after every `Start` in this
		list has run. The require edge is the real constraint, not the timing.

		IT SUBSCRIBES TO NO PHASE. Ambient life is barrio scenery and wanders in the lobby too; a
		population that appeared when a round started would be a round-state readout in the geometry,
		readable by any client.
	]]
	"AmbientService",
	"MonsterService",
	--[[
		V04. BEFORE its two callers (ItemService, SearchService) and, like every gameplay service
		here, before RoundService — which starts last precisely so every subscriber is connected
		before a phase can change. A NoiseService that started afterwards could miss the transition
		that clears the previous round's history, and the symptom would be a V13 pulse pointing at
		where somebody stood last round.

		It requires RoundService and neither of its callers, and nothing requires it back, so no
		cycle.
	]]
	"NoiseService",
	--[[
		V08. BEFORE `RoundService`, AND THAT HALF IS LOAD-BEARING FOR A REASON NEITHER FILE STATED
		UNTIL AN EXPLOIT AUDIT FOUND IT.

		Both services connect `Players.PlayerRemoving`. `RoundService`'s handler sets
		`player.Character = nil` and reparents the body into `workspace.Husks`; `ItemService`'s
		handler spills the carried item, and its `spillItem` reads `player.Character` to find where
		the body is. Connections fire in registration order, so ItemService's must be registered
		first — which it is, only because of this line's position in this list.

		INVERT THE ORDER AND EVERY DISCONNECT-WHILE-CARRYING DELETES THE ITEM, including the round's
		only buntot pagi, silently. `spillItem` now `warn`s on a missing character rather than
		returning quietly, so the failure would at least announce itself — but the ordering is the
		actual fix and this comment is what stops it being "tidied".
	]]
	"ItemService",
	--[[
		V03. AFTER ItemService and BEFORE RoundService, and only the second half is load-bearing.

		Like every gameplay service here it holds a module reference from its own `require` at load,
		and this list governs only Init/Start. What it must not do is start AFTER the state machine:
		`RoundService` starts last precisely so every subscriber is connected before a phase can
		change, and a SearchService that started afterwards could miss the STARTING that seeds its
		layout — producing a round with a nil layout and no warning, because the EMPTY path is the
		only one that warns and this would not take it.

		It requires `AntiCheatService` and `RoundService` and neither requires it back, so no cycle.
	]]
	"SearchService",
	"TrialService",
	--[[
		C23/V01. After the two services that still CALL it — ItemService and MonsterService — because
		those hold a module reference from their own `require` at load, and this list only governs
		Init/Start. It is placed here so `Start` has run before any gameplay can produce a cue.
	]]
	"TeachingService",
	--[[
		C33. After ProgressionService, whose guarded write paths it calls, and it needs nothing else —
		a daily claim reads the profile and the server clock and touches no round state at all.
	]]
	"DailyService",
	--[[
		C34. AFTER MonsterService, and that position is load-bearing rather than tidy: its `Start`
		subscribes to `MonsterService.GetCorpsesFolder()`, and the folder is created in MonsterService's
		own `Start`. This list governs Init and Start ordering, so listing it earlier would hand it a
		nil folder and silently turn the death effects off for the session.
	]]
	"CosmeticsService",
	--[[
		C25. After RoundService's dependants for the ordinary reason — it subscribes to PhaseChanged
		and reads GetPlayerState — and it needs no particular position relative to the others, because
		nothing else in the tree calls into it. Quick chat is a leaf: the client requests, this
		service decides and broadcasts, and no other service reads its state.
	]]
	"QuickChatService",
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
