--!strict
--[[
	REVIEW — src/server/Services/TaskService.luau (1423 lines)

	Excerpted ranges:
	  · src/server/Services/TaskService.luau:196-236    discoverPool — the tag-discovery pattern C13 copies
	  · src/server/Services/TaskService.luau:260-298    reportPool — the loud half
	  · src/server/Services/TaskService.luau:516-534    weightFor — where the ghost's 25% already lives
	  · src/server/Services/TaskService.luau:1012-1031  evaluatePresence and the C15 note
	  · src/server/Services/TaskService.luau:1090-1101  evaluateTimingStop — the twin gate

	Phase 8 changes two lines in this file. Phase 2 copies two functions from it without editing it.
]]

-- src/server/Services/TaskService.luau:196-206
--	Discovery. Rebuilt from scratch on every call rather than cached, because C17 will add, move and
--	delete these parts while a server is running and a cached pool would hand out a point that no
--	longer exists.
--	SORTED BEFORE THE DRAW. `GetTagged` returns instances in an order this code does not control
local function discoverPool(): TaskPool.Report
-- NOTE THE PATTERN C13's SaltSpawn DISCOVERY COPIES VERBATIM (Step 2.2): GetTagged, IsA guard with a
--      named warn, name-uniqueness, sort, then a pure verdict. Rebuilt per call for the same C17 reason.
-- IMPORTANT The sort is not cosmetic even though salt's draw is seeded from `Random.new()` with no
--      argument: it removes a hidden, engine-defined input from a random selection.

-- src/server/Services/TaskService.luau:222-230
	-- The `: BasePart?` is load-bearing under --!strict. Indexing a `{ [string]: BasePart }` yields
	-- a non-optional `BasePart`, and comparing THAT to nil is a type error rather than a lookup
	local existing: BasePart? = pointsByName[instance.Name]
-- IMPORTANT Step 2.2's `analyze` check exists for this line. It is the single most likely typecheck
--      failure in the whole of Phase 2 and it is invisible to a reader.

-- src/server/Services/TaskService.luau:235
	return TaskPool.evaluate(names, Config.Tasks.TotalRequired, Config.Tasks.PoolSize)
-- IMPORTANT THE REUSE STEP 2.2 DEPENDS ON. `TaskPool.evaluate(names, required, expected)` mentions tasks
--      NOWHERE — it takes plain strings and two numbers. C13 calls it with
--      (Config.Salt.SpawnCount, Config.Salt.PouchPoolSize) and gets EMPTY / SHORT / DUPLICATE_ID /
--      OVERSIZED with the correct meanings for salt. A `SaltPool.luau` would be the same forty lines
--      with different strings and a second place to fix a precedence bug.

-- src/server/Services/TaskService.luau:260-266
--	THE LOUD HALF, and the reason every warn here is UNGATED by VerboseLogging.
--	An unusable task pool is a fault: the round runs, nobody can finish it, and the only symptom a
--	player reports is "the game is boring". VerboseLogging is false on a published place
-- NOTE Step 2.2's `reportPool` copies this reasoning. A map with no salt is worse: §4.6's counterplay
--      does not exist, and survivors have no answer to the Aswang at all. The EMPTY message names the tag
--      and the count because the person reading it is looking at an empty baseplate.

-- src/server/Services/TaskService.luau:526-534
	--	MonsterService does. There is one owner of PlayerStates and this is not it.
	return TaskWeight.forPlayer(
		RoundService.GetPlayerState(player),
		role,
		Config.Ghost.TaskContributionMult
	)
-- IMPORTANT C16's CONTRIBUTION IS ALREADY WIRED AND HAS BEEN SINCE C08. This call passes
--      Config.Ghost.TaskContributionMult, and TaskWeight prices GHOST at exactly that. Nothing in Phase 8
--      needs to touch weighting — the 25% has simply been unreachable, because no ghost could get past
--      the gate below to ask.

-- src/server/Services/TaskService.luau:1019-1023
--	NOT_ALIVE is where C15 will change: §4.7 wants a GHOST to contribute at a reduced rate, so this line
--	becomes an allowlist of ALIVE and GHOST and `weightFor` supplies the difference. Today a ghost is
--	refused, which is correct for C08 and wrong for §4.7 — named here so it is found rather than
--	rediscovered.
-- IMPORTANT C07 WROTE STEP 8.1's INSTRUCTIONS. This is why C16 is a Small chunk sitting behind a Large
--      one: the change is two lines and the note that says which two has been sitting here since C08.

-- src/server/Services/TaskService.luau:1024-1031
local function evaluatePresence(player: Player): (Types.TaskProgressVerdict, string?)
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return "WRONG_PHASE", nil
	end

	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
		return "NOT_ALIVE", nil
	end
-- NOTE Step 8.1 replaces the second condition with an explicit two-state allowlist, not a denylist. A
--      `~= "SPECTATOR"` form reads identically today and admits LOBBY — safe only because the phase gate
--      above happens to catch it, which is exactly the "it happens to be safe" reasoning pure/PlayerBody's
--      header refuses.

-- src/server/Services/TaskService.luau:1094-1101
local function evaluateTimingStop(player: Player): (Types.TimingVerdict, string?)
	-- ...
	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
		return "NOT_ALIVE", nil
	end
-- IMPORTANT THE TWIN, AND IT IS EASY TO MISS. C07's note is attached to `evaluatePresence` only, so a
--      literal reading of it changes one gate. A ghost admitted to HOLD and refused at TIMING is silently
--      useless at two of any round's five tasks — which reads as a bug and is unattributable, because
--      nothing distinguishes "my ghost holds do nothing here" from "this task is just slow".
-- NOTE This is the shape BodyTransitions' header is about: "one entry point handled and its twin not."
