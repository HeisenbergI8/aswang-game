--!strict
--[[
	REVIEW — src/server/pure/TaskWeight.luau (68 lines) and src/server/pure/TaskPool.luau (86 lines)

	Excerpted ranges:
	  · src/server/pure/TaskWeight.luau:7-16    the anti-oracle contract
	  · src/server/pure/TaskWeight.luau:41-66   forPlayer, and the GHOST row written for C15
	  · src/server/pure/TaskPool.luau:16-26     why server/pure/ rather than shared/pure/
	  · src/server/pure/TaskPool.luau:39-84     evaluate — the function C13 reuses unchanged

	Two pure modules, both read for reuse rather than for editing. Neither is modified by this plan.
]]

-- src/server/pure/TaskWeight.luau:7-16
--	THE ANTI-ORACLE RULE, AND IT IS THE WHOLE REASON THIS IS A MODULE RATHER THAN THREE LINES IN
--	TaskService.
--		For any given PlayerState, the weight MUST NOT vary by Role.
--	`tests/task-weight.test.luau` enumerates the full `PlayerState × Role` domain — eight cells, every
--	one asserted — so a future change that special-cases the Aswang fails a terminal test
-- IMPORTANT PHASE 8 MUST NOT TOUCH THIS FUNCTION. Opening the gates in TaskService is the whole change;
--      the weighting is already correct and already proven. Step 8.2 only ADDS assertions.

-- src/server/pure/TaskWeight.luau:49-54
--	GHOST is C15's case and is priced in now because the max rule in `TaskProgress` makes it free:
--	a ghost alone is slow, a ghost beside a survivor changes nothing. §4.7 asks for "they still
--	matter", not "they stack".
--	LOBBY and SPECTATOR are zero — they are not in the round.
-- IMPORTANT C16's CONTRIBUTION HAS BEEN WIRED SINCE C08 AND HAS SIMPLY BEEN UNREACHABLE. This is the
--      single most useful finding for Phase 8's sizing: the 25% exists, `TaskService.weightFor` already
--      passes `Config.Ghost.TaskContributionMult` into it, and the only thing between a ghost and a task
--      point is two `~= Enums.PlayerState.Alive` gates.
-- NOTE "a ghost beside a survivor changes nothing" is the max rule in `TaskProgress`, not arithmetic
--      here. Worth knowing before anyone playtests two ghosts and a survivor and reports the bar as slow.

-- src/server/pure/TaskWeight.luau:56-66
function TaskWeight.forPlayer(playerState: PlayerState, _role: Role, ghostMult: number): number
	if playerState == "ALIVE" then
		return 1
	end

	if playerState == "GHOST" then
		return math.max(0, ghostMult)
	end

	return 0
end
-- NOTE `_role` is accepted and deliberately never read, and its header explains why: "the grid can only
--      assert 'weight does not vary by role' if a role can actually be passed in. An unused parameter
--      that a test proves is unused is a stronger statement than an absent one."
-- NOTE `math.max(0, ghostMult)` is a floor and not a fail-closed guard — a NaN ghostMult would pass
--      through. Harmless today (the value comes from Config, and `tests/config.test.luau` pins it in
--      (0,1)), and worth not "fixing" as a drive-by during Phase 8.

-- src/server/pure/TaskPool.luau:16-22
--	WHY src/server/pure/ AND NOT src/shared/pure/ — deliberately the opposite of TaskSelection next
--	door... the client renders what the server sends and has no use for a pool verdict, and
--	the inputs are the pool contents themselves — the exact thing TaskService's seed warning says to
--	keep off the wire. Lune resolves by file path, so none of this costs testability.
-- NOTE THE TEST THIS PLAN APPLIES TO ITS OWN FIVE NEW PURE MODULES. `SaltCarry`, `SaltThrow`,
--      `RejoinResolve`, `GhostChat` and `SpookBudget` all go in `shared/pure/`, because none of their
--      inputs is a map's contents or a seed: they take a phase, a state, a count and a geometry the
--      client already holds or cannot obtain. `SaltThrow`'s one privileged input,
--      `TargetIsTransformedAswang`, exists only in server memory and is ANDed at the call site so the
--      module never sees a role at all.

-- src/server/pure/TaskPool.luau:39-56
--	PRECEDENCE IS BLOCKING-FIRST, and the order is the whole content of this function.
--		EMPTY        no usable point at all
--		SHORT        fewer distinct points than TotalRequired
--		DUPLICATE_ID enough points, but two share a Name
--		OVERSIZED    more points than PoolSize expects
--	SHORT OUTRANKS DUPLICATE_ID on purpose. Both are map defects; only one of them means the round is
--	unwinnable.
function TaskPool.evaluate(names: { string }, required: number, expected: number): Report
-- IMPORTANT REUSED UNCHANGED BY STEP 2.2, called with `(names, Config.Salt.SpawnCount,
--      Config.Salt.PouchPoolSize)`. Nothing in this function mentions tasks — plain strings and two
--      numbers — and every verdict reads correctly for salt: SHORT means fewer points than pouches,
--      OVERSIZED means the map and Config disagree.
-- NOTE A `SaltPool.luau` would be these forty lines with `SaltSpawn` in the strings and a second place
--      for the precedence order to drift. The blocking-first ordering is a decision, not boilerplate, and
--      it should exist once.
