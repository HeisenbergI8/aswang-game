--!strict
-- REVIEW: src/server/Services/TaskService.luau:1-49 (the whole file — it is a 49-line stub)
--
-- This stub is the specification for this chunk. It is the only file in the plan whose header survives
-- the change unedited, and the seed section below is why.

--[[
	STILL A STUB, DELIBERATELY, AND HALF OF C07 IS ALREADY DONE ELSEWHERE.
	...
	Wiring discovery now would ship a service whose only observable behaviour is finding an empty pool
	— indistinguishable from a broken one, and unverifiable by anything in this repo.
]]
-- The author's stated reason for not shipping discovery. IMPORTANT: this plan does not overrule it,
-- it discharges it. Step 2.1's disposable rig removes "unverifiable", and Step 1.2's TaskPool verdict
-- removes "indistinguishable" — an empty pool now produces a named verdict a Lune test asserts on and
-- an unconditional warn naming the tag. Shipping discovery without BOTH would be shipping the thing
-- this comment refused.

	--[[
		local rng = Random.new()            -- correct: server-only entropy, no argument
		local rng = Random.new(roundNumber) -- FATAL: the client has the round number in every snapshot
		local rng = Random.new(os.time())   -- FATAL: client-observable to the second
	]]
-- IMPORTANT: the load-bearing part of C07's map half, and it is already correct here. The plan copies
-- it verbatim rather than restating it. Note WHY it is fatal rather than untidy: TaskSelection lives
-- under src/shared/, so a client can require AND CALL it — a reproducible stream means the Aswang
-- knows every task location before STARTING ends.

	-- Create the Random ONCE at Start(), keep it as a server-side local, and pass
	-- `function() return rng:NextNumber() end` as the module's `nextFloat`.
-- QUESTION → resolved as a deliberate deviation, Step 2.2. The plan makes it a MODULE-level local
-- rather than a Start() local. Every property this line asks for is kept and "exactly once" is
-- strengthened: a module local cannot be created twice, and the type becomes `Random` rather than
-- `Random?`, which deletes a nil branch whose only honest behaviour would be to error inside a phase
-- handler. Flagged in the plan as a written justification, per Hard Rule 4.

-- TODO(C17): discover the pool by CollectionService tag `TaskPoint`, then call
-- TaskSelection.select(pool, Config.Tasks.TotalRequired, Config.Tasks.MinSpacingStuds, nextFloat)
-- from RoundService's STARTING handler.
-- IMPORTANT: "from RoundService's STARTING handler" is the one instruction here the plan does NOT
-- follow. Doing so means RoundService requires TaskService; TaskService needs RoundService for
-- SetTasksCompleted and GetPlayerState; that is a load-time require cycle. Step 2.3 subscribes to
-- PhaseChanged instead, which is the shape MonsterService already uses. See RoundService-review.

-- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
-- NOTE: only HOLD is in scope. Step 2.3 reads a `TaskType` attribute and warns on anything else,
-- which is the single line C09/C10 need in order not to revisit discovery. Nothing else is pre-built.

-- The Aswang sees a fake task list; its progress must never count.
-- IMPORTANT: C12, out of scope, and the constraint that shaped two of this plan's decisions —
-- TaskProgress's max-not-sum rate, and TaskProgressChanged being per-player. Both were required by
-- C08's own secrecy constraint; neither is speculative work for C12.

function TaskService.Init() end
function TaskService.Start() end
-- NOTE: both already exist and `TaskService` is ALREADY listed in init.server.luau's SERVICE_ORDER,
-- so no bootstrap change appears anywhere in this plan. Verified by reading init.server.luau:19-36.
