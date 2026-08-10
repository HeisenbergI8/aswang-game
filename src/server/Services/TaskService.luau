--!strict
--[[
	TaskService — Picks 5 of 12 task spawns per round and validates progress.

	Milestone: M3
	Spec: docs/MVP-SPEC.md
]]

local TaskService = {}

-- TODO(M3): randomly select Config.Tasks.TotalRequired from PoolSize spawn points.
-- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
-- TODO(M3): validate progress server-side (proximity + rate). Open the gate at 5/5.
-- The Aswang sees a fake task list; its progress must never count.

function TaskService.Init() end

function TaskService.Start() end

return TaskService
