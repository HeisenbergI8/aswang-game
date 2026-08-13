--!strict
--[[
	REVIEW — src/server/pure/TaskPool.luau (and TaskService's discovery around it)
	Read 2026-08-12 for the C09-C12 plan. The file is 86 lines. Unmodified by this plan.

	Read because Phase 4 adds the THIRD instance of this discovery pattern, and because its verdict
	precedence is the model for how the plan handles a map that cannot satisfy a task type.
]]

-- src/server/pure/TaskPool.luau — evaluate(names, required, expected) -> Report
-- Blocking-first precedence: EMPTY -> SHORT -> DUPLICATE_ID -> OVERSIZED -> OK.
-- IMPORTANT: the split is between "unusable" (EMPTY, SHORT — the round cannot be won) and "usable but
-- wrong" (DUPLICATE_ID, OVERSIZED — the round runs, somebody must fix the map). Types.luau:205-216
-- explains why that is a union rather than a boolean: "'unusable' and 'usable but wrong' send a reader
-- to two different places, and a boolean would collapse them into a shrug."
-- NOTE: Phase 4 reuses the PRINCIPLE without adding a verdict type. A `FETCH` task with no available
-- source is DEMOTED to `HOLD` with an unconditional warn — "usable but wrong". The alternative, a task
-- that can never be started, is the unwinnable-and-silent failure class this whole module exists to
-- make loud.

-- src/server/pure/TaskPool.luau (the counting rule, via implementation-log Step 1.3)
-- "a pool of three identical names has three entries and one usable point. An implementation counting
--  `#names` where `#unique` was meant reports `OK` on a map with a single anchor in it."
-- IMPORTANT FOR PHASE 4: `discoverSources` must apply the same first-wins-on-duplicate-name rule as
-- `discoverPool` (TaskService:156-160), because the plan's `used` table keys off `source.Name`. Two
-- `FetchSource` parts sharing a Name would otherwise let one part be claimed twice and leave a task
-- pointing at an item that another task is also using.
-- NOTE: the plan's `discoverSources` does exactly this (`if sourcesByName[instance.Name] == nil`), but
-- it does NOT report duplicates the way `reportPool` does. That is a deliberate scope choice — a
-- duplicated source is less fatal than a duplicated task point — and it is worth knowing rather than
-- assuming it was handled.

-- src/server/Services/TaskService.luau:136-166 (discoverPool — the pattern Phase 4 copies)
local function discoverPool(): TaskPool.Report
	table.clear(pointsByName)
	for _, instance in CollectionService:GetTagged(TAG_POINT) do
		if not instance:IsA("BasePart") then
			warn(`... is tagged {TAG_POINT} but is a {instance.ClassName}, not a BasePart — skipped.`)
			continue
		end
		table.insert(names, instance.Name)
	end
	table.sort(names)
end
-- IMPORTANT — TWO PROPERTIES PHASE 4 MUST PRESERVE:
--   1. REBUILT FROM SCRATCH on every call, never cached. "C17 will add, move and delete these parts
--      while a server is running and a cached pool would hand out a point that no longer exists."
--      Phase 4's `discoverSources` and Phase 6's `discoverGates` both do this.
--   2. The `IsA("BasePart")` guard with a named warn. A tag can be applied to any Instance, and a
--      Folder tagged `FetchSource` would otherwise error on `.Position` at a distance check.
-- NOTE: `table.sort(names)` before the draw is NOT cosmetic here — "GetTagged returns instances in an
-- order this code does not control and should not inherit". Phase 4's source pairing iterates
-- `sourcesByName` (a hash) and picks by FURTHEST distance, so iteration order decides only exact
-- ties. Acceptable, and the same small gap flagged in the TaskResolve review.

-- src/server/Services/TaskService.luau:168-207 (reportPool — the logging discipline)
-- "THE LOUD HALF, and the reason every warn here is UNGATED by VerboseLogging. [...] An unusable task
--  pool is a fault: the round runs, nobody can finish it, and the only symptom a player reports is
--  'the game is boring'. VerboseLogging is false on a published place, which is exactly where that
--  report comes from."
-- IMPORTANT: every new warn in this plan follows it — the demoted `FETCH` task, the missing
-- `EscapeGate`, and `taskTypeOf`'s unknown-type warning are all unconditional. Routine tracing (the
-- bar, the list, the gate state) is gated. That split is the convention and it is worth stating why
-- when adding to either side.
-- NOTE: the EMPTY message "names the tag and the count, because the person reading it is looking at
-- an empty baseplate and needs to know what to do, not that something went wrong." GateService's
-- no-gate warn copies that shape verbatim, including naming the tag and citing §4.8.

-- src/server/Services/TaskService.luau:746-753 (discovery at BOOT)
	reportPool(discoverPool())
-- "DISCOVERY RUNS AT BOOT, not only at STARTING [...] On a map with no anchors the operator learns at
--  server start — while they are still looking at the output window — rather than 45 seconds later
--  when the first round draws nothing and nobody is watching."
-- IMPORTANT: `GateService.Start` copies this exactly, and it matters more there. A missing gate is
-- invisible until a round reaches 5/5, which may be several minutes and several rounds away.
-- NOTE: plan 1 proved this fires above `[Bootstrap] Ready` in the log — artifacts/task-rig.md §2.
return nil
