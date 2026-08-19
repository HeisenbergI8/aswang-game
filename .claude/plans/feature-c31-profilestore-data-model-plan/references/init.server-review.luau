--!strict
--[[
	REVIEW — src/server/init.server.luau:19-51, 59, 74-99
	Read for: where ProgressionService sits in the load order, what happens to a require cycle, and
	whether a non-service module can live under src/server without being Init'ed.
]]

--------------------------------------------------------------------------------
-- :19-33 — the order
--------------------------------------------------------------------------------

local SERVICE_ORDER = {
	-- Infrastructure first
	"AnalyticsService",
	"AntiCheatService",
	-- IMPORTANT: third, and ahead of every gameplay service. `ProgressionService.Init()` therefore
	-- runs before RoleService, TaskService, MonsterService or RoundService — so constructing the
	-- ProfileStore store in Init() is safe, and any service may call GetProfile from its own Start().
	"ProgressionService",
	"BadgeService",
	-- ...
	-- The state machine drives everything, so it starts last
	"RoundService",
}

--------------------------------------------------------------------------------
-- :59 — only the Services folder is loaded
--------------------------------------------------------------------------------

-- IMPORTANT: the loader walks SERVICE_ORDER inside `script.Services` and nothing else. A module at
-- `src/server/ShutdownFlush.luau` — a SIBLING of the Services folder — is therefore never Init'ed or
-- Start'ed, which is exactly what the plan's leaf registry needs. From a service, it resolves as
-- `script.Parent.Parent.ShutdownFlush`: Parent is the Services folder, Parent.Parent is the `Server`
-- Script that `init.server.luau` becomes.
local servicesFolder = script:WaitForChild("Services")

--------------------------------------------------------------------------------
-- :74-86 — the failure mode that makes require cycles catastrophic
--------------------------------------------------------------------------------

local ok, result = pcall(require, moduleScript)
if not ok then
	-- IMPORTANT: THIS IS THE SINGLE MOST DANGEROUS LINE FOR C31'S DEPENDENCY DECISION. A require
	-- cycle errors at load and lands HERE — one `warn`, the service silently absent, and the server
	-- carries on. RoundService's own header says the symptom is a server sitting in IDLE forever
	-- looking exactly like "nobody has joined yet". It is why the plan routes the shutdown flush
	-- through a leaf module instead of RoundService requiring ProgressionService.
	warn(`[Bootstrap] Failed to require {name}: {result}`)
	continue
end

--------------------------------------------------------------------------------
-- :93-95 — the pcall arity bite, quoted because the plan reuses it
--------------------------------------------------------------------------------

-- NOTE: `:: any` because pcall over a `() -> ()` is typed as returning only the boolean, so binding
-- `err` is an arity error under --!strict. `ShutdownFlush.flushAll` hits the same wall and takes the
-- same workaround; this is the repo's established spelling, not a new invention.
local startOk, err = pcall(service.Start :: any)
