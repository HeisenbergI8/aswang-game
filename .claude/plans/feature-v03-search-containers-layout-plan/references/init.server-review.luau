--!strict
--[[
	REVIEW — src/server/init.server.luau:4-13, 19-57, 74-105
	Read for V03 to place `SearchService` in SERVICE_ORDER. The position is a real dependency, not a
	preference, and getting it wrong fails SILENTLY.
]]

--[[
	NOTE — THE LIFECYCLE (init.server.luau:6-12):

	  Init()  — "set up internal state, no cross-service calls. Runs for ALL services before any
	            Start() does."
	  Start() — "wire up events, begin loops, talk to other services."

	V03 obeys: `SearchService.Init` only calls `clearLayout` (local tables), while `Start` connects
	PhaseChanged, the two OnServerEvent handlers and the tick loop.
]]

local SERVICE_ORDER = { -- :19
	-- Infrastructure first
	"AntiCheatService", -- :22
	-- Gameplay
	"RoleService",
	"MonsterService",
	"ItemService",
	-- + "SearchService" HERE, by Step 4.3
	"TrialService",

	-- IMPORTANT :55-56 — "The state machine drives everything, so it starts last"
	"RoundService",
}

--[[
	IMPORTANT — WHY SEARCHSERVICE MUST BE ABOVE `RoundService`, AND WHY THE FAILURE IS SILENT.

	RoundService starts LAST so that every subscriber is connected before a phase can change. A
	SearchService started afterwards could miss the STARTING that seeds its layout — and the resulting
	nil layout produces NO WARNING, because only the EMPTY pool path warns and this would not take it.
	The symptom is "the map has no items in it", which points a debugger straight at the map.

	This list governs only Init/Start, NOT require order — every service holds its module references
	from its own `require` at load — so the position is about lifecycle and nothing else. The file
	already documents three such reasoned placements and they are the model for V03's comment:

	  · TeachingService (:32-35): "After the two services that still CALL it [...] because those hold a
	    module reference from their own `require` at load, and this list only governs Init/Start."
	  · CosmeticsService (:43-47): "AFTER MonsterService, and that position is load-bearing rather than
	    tidy: its `Start` subscribes to `MonsterService.GetCorpsesFolder()`, and the folder is created
	    in MonsterService's own `Start`. [...] listing it earlier would hand it a nil folder and
	    silently turn the death effects off for the session."
	  · QuickChatService (:48-53): "it needs no particular position [...] Quick chat is a leaf."

	SearchService is the CosmeticsService case, not the QuickChatService one.
]]

--[[
	IMPORTANT — EVERY LIFECYCLE CALL IS pcall'd (init.server.luau:80-89, 96-102), so an error inside
	`SearchService.Start` becomes ONE warn line and the server keeps going with searching silently
	dead. Two consequences for V03:

	  · `seedLayout` must not be able to throw. `GetTagged` on an unknown tag returns an empty table
	    rather than erroring, `SearchPool.evaluate` handles an empty list (its own test asserts it),
	    and `ContainerLayout.draw` handles containerCount = 0. The chain is total by construction.
	  · Order inside `Start` matters for the same reason RoundService documents at :1265-1268 —
	    connections and loops first, anything that could throw last. V03 has nothing that can throw,
	    but the tick loop still goes last so a future addition inherits the right shape.
]]

	-- NOTE :98-100 — the pcall arity trap, quoted because a V03 implementer will meet it if they add
	-- any pcall of their own:
	-- "`:: any` because pcall over a `() -> ()` is typed as returning only the boolean, so binding
	--  `err` is an arity error under --!strict."
	local startOk, err = pcall(service.Start :: any)

-- NOTE :106 prints `{#SERVICE_ORDER} services loaded`. The list holds 15 today, so the line must read
-- 16 after Step 4.3 — the cheapest confirmation a playtester has that the bootstrap saw the new
-- service at all, and one a screenshot of the output window captures for free.
