--!strict
--[[
	tests/task-list-view.test.luau

	`server/pure/TaskListView.luau` over every decoy length from 0 to 7 against a real list of 5, both
	roles: 16 cells, enumerated.

	🔒 THE ASSERTION THAT MATTERS IS THE LENGTH ONE. Everything else here checks that the right list
	comes back; that one checks that the WRONG list is indistinguishable in the one property a client
	can measure without knowing anything. `#myTaskList` is one token of Luau on a compromised client,
	and if it ever differs by role, C12 has built a cheaper oracle than the one A2 removed.
]]

local TaskListView = require("../src/server/pure/TaskListView")

local REAL = { "TaskPoint_01", "TaskPoint_02", "TaskPoint_03", "TaskPoint_04", "TaskPoint_05" }
local ROLES: { TaskListView.Role } = { "SURVIVOR", "ASWANG" }

local failures = 0
local assertions = 0

local function check(label: string, ok: boolean, detail: string?)
	assertions += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function decoyOfLength(count: number): { string }
	local ids = {}

	for index = 1, count do
		table.insert(ids, `TaskPoint_{index + 5}`)
	end

	return ids
end

-- 🔒 The length property, over every decoy size a draw could produce — including zero, which is what
-- an empty pool returns.
for count = 0, 7 do
	local decoy = decoyOfLength(count)

	for _, role in ROLES do
		local shown = TaskListView.forPlayer(REAL, decoy, role)

		check(
			`{role} is shown exactly {#REAL} points (decoy had {count})`,
			#shown == #REAL,
			`got {#shown}`
		)
	end
end

-- The survivor's list is the real one, element for element.
for count = 0, 7 do
	local shown = TaskListView.forPlayer(REAL, decoyOfLength(count), "SURVIVOR")
	local same = true

	for index, id in REAL do
		same = same and shown[index] == id
	end

	check(`a survivor sees the real five (decoy had {count})`, same)
end

--[[
	A full decoy reaches the Aswang unaltered — no truncation, no padding, no reordering.

	This is the normal case and it is the one that would silently stop working if the pad/truncate
	loops were written with the wrong comparison. The length assertion above would still pass.
]]
local FULL_DECOY = decoyOfLength(5)
local shownToAswang = TaskListView.forPlayer(REAL, FULL_DECOY, "ASWANG")
local matchesDecoy = true

for index, id in FULL_DECOY do
	matchesDecoy = matchesDecoy and shownToAswang[index] == id
end

check("a full decoy reaches the Aswang unaltered", matchesDecoy)

--[[
	THE CALLER CANNOT MUTATE THIS ROUND'S REAL TASK LIST through what it was handed.

	Both branches `table.clone`. Without it, a survivor's returned list IS `realIds`, and any caller
	that sorted or truncated it for display would silently edit the round's task set.
]]
local handed = TaskListView.forPlayer(REAL, decoyOfLength(5), "SURVIVOR")

table.remove(handed)

check("the returned list is a copy, not the round's own", #REAL == 5, `REAL is now {#REAL}`)

-- The degenerate map: no decoy at all. The Aswang must still be shown five, and they are real ones —
-- see the module header for why that is the least-bad padding.
local noDecoy = TaskListView.forPlayer(REAL, {}, "ASWANG")

check("an empty decoy still shows five", #noDecoy == 5, `got {#noDecoy}`)

for _, id in noDecoy do
	check(
		`the padded id {id} is a real point rather than an invention`,
		table.find(REAL, id) ~= nil
	)
end

if failures > 0 then
	error(`{failures} task-list-view failure(s)`, 0)
end

print(`  PASS  task-list-view: {assertions} assertions over every decoy length, both roles`)
