--!strict
--[[
	The pool verdict, at every boundary. C07's map half.

	THE FIRST ASSERTION IS THE POINT OF THE WHOLE FILE. "The map has no TaskPoints" is the failure this
	repo has actually been living with — Workspace is an empty baseplate — and the stub's author was
	right that a service which can only report it silently is not worth shipping. This test is what
	turns that report into something a terminal can fail on.

	Boundaries rather than samples: required-1, required, expected, expected+1. Every off-by-one in
	`evaluate` lands on one of those four and on nothing else.
]]

local TaskPool = require("../src/server/pure/TaskPool")

local REQUIRED = 5
local EXPECTED = 12

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function names(count: number): { string }
	local list = {}

	for i = 1, count do
		table.insert(list, `TaskPoint_{i}`)
	end

	return list
end

-- The reason this module exists. An untagged map must be reported, not shrugged at.
local empty = TaskPool.evaluate({}, REQUIRED, EXPECTED)

check("an empty pool is EMPTY", empty.Verdict == "EMPTY", empty.Verdict)
check("an empty pool has no unique points", #empty.Unique == 0)

-- One below the gate's requirement: the round could never reach 5/5, so this must block.
local short = TaskPool.evaluate(names(REQUIRED - 1), REQUIRED, EXPECTED)

check("a pool one short of the requirement is SHORT", short.Verdict == "SHORT", short.Verdict)

-- Exactly enough is fine. The draw returns all of them and the spacing filter falls back; that is
-- TaskSelection's contract, already proven in tests/task-selection.test.luau.
local exact = TaskPool.evaluate(names(REQUIRED), REQUIRED, EXPECTED)

check("a pool of exactly the requirement is OK", exact.Verdict == "OK", exact.Verdict)

local full = TaskPool.evaluate(names(EXPECTED), REQUIRED, EXPECTED)

check("the intended 12-point pool is OK", full.Verdict == "OK", full.Verdict)
check("the intended pool keeps all 12", #full.Unique == EXPECTED, `{#full.Unique}`)

-- Non-blocking, but a defect: C17 left a thirteenth tag somewhere.
local oversized = TaskPool.evaluate(names(EXPECTED + 1), REQUIRED, EXPECTED)

check(
	"a pool larger than PoolSize is OVERSIZED",
	oversized.Verdict == "OVERSIZED",
	oversized.Verdict
)

--[[
	Two parts with one Name. The server identifies a task point by Name, so this is the map defect that
	would otherwise surface as a task completing itself at the wrong end of the barrio.
]]
local duplicated = names(EXPECTED)

table.insert(duplicated, "TaskPoint_3")

local dupes = TaskPool.evaluate(duplicated, REQUIRED, EXPECTED)

check("a repeated Name is DUPLICATE_ID", dupes.Verdict == "DUPLICATE_ID", dupes.Verdict)
check("the duplicate is named for the log", dupes.Duplicates[1] == "TaskPoint_3")
check("the duplicate is counted once", #dupes.Unique == EXPECTED, `{#dupes.Unique}`)

--[[
	SHORT OUTRANKS DUPLICATE_ID. Four distinct names and a repeat is still an unwinnable round, and a
	reader sent to fix the name first would fix the wrong thing. This assertion is the precedence rule
	from the module header, pinned.
]]
local shortAndDuplicated = names(REQUIRED - 1)

table.insert(shortAndDuplicated, "TaskPoint_1")

local both = TaskPool.evaluate(shortAndDuplicated, REQUIRED, EXPECTED)

check(
	"a short pool reports SHORT even when it also has duplicates",
	both.Verdict == "SHORT",
	both.Verdict
)
check("the duplicate is still reported alongside it", #both.Duplicates == 1)

-- A pool of nothing but the same name is EMPTY of usable points, not DUPLICATE_ID.
local allSame = TaskPool.evaluate({ "A", "A", "A" }, REQUIRED, EXPECTED)

check("a pool of one repeated name is SHORT, not OK", allSame.Verdict == "SHORT", allSame.Verdict)
check("it keeps exactly one", #allSame.Unique == 1)

if failures > 0 then
	error(`{failures} task-pool assertion(s) failed`, 0)
end

print("  PASS  task-pool: 14 assertions across 8 pools")
