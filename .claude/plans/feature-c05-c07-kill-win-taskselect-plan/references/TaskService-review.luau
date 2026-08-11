--!strict
-- Review of src/server/Services/TaskService.luau — the 20-line stub Phase 6 annotates and does NOT wire.
-- The whole file is quoted because the whole file is twenty lines.

--!strict
--[[
	TaskService — Picks 5 of 12 task spawns per round and validates progress.

	Milestone: M3
	Spec: docs/MVP-SPEC.md
]]

local TaskService = {}

-- TODO(M3): randomly select Config.Tasks.TotalRequired from PoolSize spawn points.
-- IMPORTANT: this TODO is the half Phase 6 builds — as pure/TaskSelection.luau, not here. The service
-- half stays a stub because the POOL does not exist: `TaskPoint` appears zero times in src/ (verified),
-- and the greybox that places those tags is a later chunk. A discovery loop written today can only
-- ever be observed finding nothing, which is indistinguishable from finding nothing because it is
-- broken. That is the definition of unverifiable, and the plan says so in §1.1 rather than leaving the
-- omission to be read as an oversight.

-- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
-- NOTE: C08–C10. Out of scope entirely.

-- TODO(M3): validate progress server-side (proximity + rate). Open the gate at 5/5.
-- NOTE: C08 and C11. The gate counts Config.Tasks.TotalRequired, which is why Phase 6's TaskSelection
-- must ALWAYS return `count` points when the pool is large enough — a spacing filter that returned
-- three would leave the gate shut forever and produce an unwinnable round out of a balance number.

-- The Aswang sees a fake task list; its progress must never count.
-- IMPORTANT: this is a property of what TaskService SENDS, not of what it DRAWS. TaskSelection returns
-- the real set; the fake list is built per player at C08. Nothing in Phase 6 touches a remote.

function TaskService.Init() end

function TaskService.Start() end
-- NOTE: both empty, and they stay empty. Phase 6 changes the header comment only — which is why its
-- Verify line is `npm run verify` (the tree still passes) rather than anything claiming behaviour.
-- IMPORTANT for whoever wires this up: create `Random.new()` ONCE here, with NO argument, keep it as a
-- server-side local, and pass `function() return rng:NextNumber() end` as TaskSelection's `nextFloat`.
-- `Random.new(roundNumber)` is fatal — RoundNumber is on every ClientRoundSnapshot, twice a second.

return TaskService
