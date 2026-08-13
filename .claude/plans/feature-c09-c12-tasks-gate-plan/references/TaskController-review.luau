--!strict
--[[
	REVIEW — src/client/Controllers/TaskController.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 80 lines.

	Phases 3 and 7 both extend it, and both extensions are caches. Its header states the test they
	have to pass.
]]

-- src/client/Controllers/TaskController.luau:5-8 (header)
-- "IT OWNS NO TRUTH, and that is a testable claim rather than a slogan: delete every line of this
--  file and no outcome the server produces changes. It cannot complete a task, it cannot advance a
--  bar, it cannot choose which task point it is reporting. [...] Apply that test to anything added
--  here."
-- IMPORTANT: both additions pass it, and it is worth stating HOW, because the timing bar is the first
-- thing in this game that could plausibly have failed it:
--   · `latestBar` is a render hint. The server re-derives the bar's phase from its own `os.clock()`
--     on every stop, so a client rendering the bar frozen, doubled or backwards gets the same hit
--     decision as one rendering it perfectly.
--   · `taskList` is a display list. For exactly one player per round it is false, and the client
--     cannot tell — which is the point of C12 rather than a limitation of it.

-- src/client/Controllers/TaskController.luau:10-11
-- "Milestone M7 owns the real bar (C18). Today this is a cache with a print behind VerboseLogging,
--  and `GetLatest` is the seam C18 draws from."
-- NOTE: this is why Phases 3 and 7 add `GetLatestBar()` and `GetTaskList()` rather than any UI. Three
-- seams, one owner, and C18 draws all three. A plan step that built a real moving bar here would be
-- doing M7's work in M3 and would have to be redone.

-- src/client/Controllers/TaskController.luau:23-28
local latest: Types.TaskProgressPayload? = nil
function TaskController.GetLatest(): Types.TaskProgressPayload?
	return latest
end
-- The shape both additions copy. NOTE: Phase 7's `GetTaskList()` returns `table.clone(taskList)`
-- rather than the cached table itself — a list is mutable in a way a payload record is not, and
-- handing C18 a reference it could sort in place would corrupt the cache. Small, but the existing
-- getter does not have to think about it and the new one does.

-- src/client/Controllers/TaskController.luau:30-40
--[[
	A STUCK `true` COSTS RATE-LIMIT TOKENS AND NOTHING ELSE. The server re-measures distance on every
	tick, so a client left holding while its player walks away accumulates zero — the failure is a
	throttled player, not a free task, and it is self-inflicted.
]]
function TaskController.SetHolding(value: boolean)
-- IMPORTANT: the property to preserve, and Phase 3's timing bind preserves it trivially by having no
-- state at all. A stuck timing press is impossible — there is nothing to stick.
-- NOTE: the same reasoning covers Phase 4's fetch entirely. Pickup is PROXIMITY, evaluated server-
-- side on the tick, so there is no client input to get stuck, no remote to spam, and no new client
-- state. That is why C09 needs one new UP remote rather than two.

-- src/client/Controllers/TaskController.luau:61-77
	task.spawn(function()
		while true do
			if holding then
				Remotes.Get("RequestTaskProgress"):FireServer()
			end
			task.wait(Config.Tasks.HeartbeatInterval)
		end
	end)
-- "THE HEARTBEAT. It reports PRESENCE and only presence — no task id, no elapsed time, no progress,
--  no completion. `FireServer()` with no arguments is the entire message."
-- IMPORTANT: Phase 3's `RequestTimingStop` copies the zero-argument shape and NOT the loop. A stop is
-- an event, not a heartbeat, so it fires from the bind directly. Its budget is sized accordingly
-- (Capacity 5, refill 1/s against the heartbeat's 12 and 6/s) — see `references/Config-review.luau`.
-- NOTE: "The interval is Config's, and tests/config.test.luau pins its reciprocal below
-- AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond so an honest hold never throttles itself."
-- Phase 1 adds the matching invariant for the timing stop against `TimingBarPeriod`, because the
-- honest cadence there is one press per sweep and nothing else would notice if the period dropped.

-- src/client/Controllers/TaskController.luau:42-45
function TaskController.Init()
	latest = nil
	holding = false
end
-- NOTE: Phases 3 and 7 must both extend `Init`, not just `Start`. `init.client.luau` calls Init on
-- every controller before Start, and a cache left populated across a round boundary would show last
-- round's task list during INTERMISSION — the same class of bug plan 1 fixed server-side when
-- `clearTasks` started clearing `lastSentProgress`.
return nil
