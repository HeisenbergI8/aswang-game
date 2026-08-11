--!strict
--[[
	TaskService — Picks 5 of 12 task spawns per round and validates progress.

	Milestone: M3
	Spec: docs/MVP-SPEC.md

	STILL A STUB, DELIBERATELY, AND HALF OF C07 IS ALREADY DONE ELSEWHERE.

	The DECISION — which five of the twelve — is built and proven: `shared/pure/TaskSelection.luau`
	plus `tests/task-selection.test.luau`, 10,000 draws. What is missing is the half that needs a map:
	the pool itself. §4.4's twelve locations are CollectionService-tagged `TaskPoint` parts placed by
	the greybox at C17, and `TaskPoint` appears nowhere in this repository today. Wiring discovery now
	would ship a service whose only observable behaviour is finding an empty pool — indistinguishable
	from a broken one, and unverifiable by anything in this repo.

	WHEN C17 WIRES THIS UP, THE SEED IS THE PART TO GET RIGHT
	---------------------------------------------------------
	`TaskSelection` lives under src/shared/, so a client can require it AND call it. The algorithm being
	public costs nothing; a reproducible STREAM costs the round, because the Aswang would know where
	every task is before STARTING ends.

		local rng = Random.new()            -- correct: server-only entropy, no argument
		local rng = Random.new(roundNumber) -- FATAL: the client has the round number in every snapshot
		local rng = Random.new(os.time())   -- FATAL: client-observable to the second

	Create the Random ONCE at Start(), keep it as a server-side local, and pass
	`function() return rng:NextNumber() end` as the module's `nextFloat`. Never send the seed, the
	stream position, or the unselected pool to a client.

	Selection happens in STARTING (C07) and the chosen set is server state. The Aswang sees a fake task
	list (§4.4) — which is a property of what TaskService SENDS, not of what it draws, and belongs with
	the task types at C08.
]]

local TaskService = {}

-- TODO(C17): discover the pool by CollectionService tag `TaskPoint`, then call
-- TaskSelection.select(pool, Config.Tasks.TotalRequired, Config.Tasks.MinSpacingStuds, nextFloat)
-- from RoundService's STARTING handler.
-- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
-- TODO(M3): validate progress server-side (proximity + rate). Open the gate at 5/5.
-- The Aswang sees a fake task list; its progress must never count.

function TaskService.Init() end

function TaskService.Start() end

return TaskService
