--!strict
-- REVIEW: src/server/init.server.luau:1-36, 44-84
--
-- Read to answer two questions: does TaskService need registering, and what happens when a require
-- fails. Both answers changed the plan.

	Init()  — set up internal state, no cross-service calls. Runs for ALL services before any Start() does.
	Start() — wire up events, begin loops, talk to other services.
-- NOTE: the contract TaskService keeps. Discovery, the PhaseChanged subscription, the remote handler and
-- the tick loop all live in Start(); Init() stays empty. IMPORTANT that "no cross-service calls in Init"
-- is why the plan puts `local rng = Random.new()` at MODULE scope rather than in Init — it is not a
-- cross-service call, but a module local is created exactly once and an Init body is not.

local SERVICE_ORDER = {
	"AnalyticsService", "AntiCheatService", ...
	"RoleService",
	"TaskService",                                                                 -- :29
	"MonsterService", ...
	-- The state machine drives everything, so it starts last
	"RoundService",
}
-- IMPORTANT: TaskService is ALREADY LISTED. No bootstrap change appears anywhere in this plan, and a
-- step to add one would have been a step that verified nothing.
-- NOTE the order: TaskService is required and Init'd BEFORE RoundService. Since TaskService requires
-- RoundService at module scope, RoundService's module body runs early — which is fine and is exactly
-- what MonsterService already does two lines below. What would NOT be fine is the reverse edge.

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(`[Bootstrap] Failed to require {name}: {result}`)
		continue
	end
-- IMPORTANT: this is the machinery that makes a require cycle catastrophic-but-quiet. A cycle errors
-- during `require`, this pcall swallows it into ONE warn line, the loop `continue`s, and the server
-- comes up missing a service with no other symptom. RoundService's header describes the resulting state
-- as "sits in IDLE forever looking exactly like nobody has joined yet". That is the concrete cost behind
-- Step 2.3's decision not to follow the C07 TODO, and behind Step 3.4 deleting it.

		local startOk, err = pcall(service.Start :: any)
		-- `:: any` because pcall over a `() -> ()` is typed as returning only the boolean,
		-- so binding `err` is an arity error under --!strict.
-- NOTE: the strict-Luau gotcha the plan template lists. Nothing in this plan calls pcall over a
-- `() -> ()`, so it does not recur — recorded because it is one of the two the template names and a
-- reader checking the Potential Issues list should be able to see it was actually checked.

if Config.Debug.SoloTesting then
	warn("[Bootstrap] SoloTesting is ENABLED — do not ship with this on.")
end
-- NOTE: relevant to the playtester brief. A round cycle is 461s at committed values, so the debug
-- values must be set BEFORE launching it and reverted after — guard-commit.mjs runs check:debug and
-- refuses to commit them, so they cannot reach history. That is the main agent's job, not the plan's.
