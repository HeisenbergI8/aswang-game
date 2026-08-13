--!strict
--[[
	tests/task-participants.test.luau

	`server/pure/TaskParticipants.luau` composed with `TaskWeight`, over every pair of players.

	THE NAMED CASE IS THE LAST ASSERTION IN THIS FILE and it is the reason the file exists:
	an ALIVE survivor beside an ALIVE Aswang satisfies a two-person task. Amendment A2 requires it,
	§4.4's "the Aswang can 'help' you and then betray you" depends on it, and a pair producing no
	progress would be an instantaneous reveal with nothing to deduce.
]]

local TaskParticipants = require("../src/server/pure/TaskParticipants")
local TaskWeight = require("../src/server/pure/TaskWeight")

local STATES: { TaskWeight.PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local ROLES: { TaskWeight.Role } = { "SURVIVOR", "ASWANG" }

local GHOST_MULT = 0.25
local FULL = 1
local REQUIRED = 2

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

-- Every pair, both roles on both sides. The expected count is derived from the STATES alone, which
-- is the assertion: if the roles mattered, this expectation would be unwriteable.
for _, stateA in STATES do
	for _, stateB in STATES do
		local expected = (if stateA == "ALIVE" then 1 else 0) + (if stateB == "ALIVE" then 1 else 0)

		for _, roleA in ROLES do
			for _, roleB in ROLES do
				local weights = {
					TaskWeight.forPlayer(stateA, roleA, GHOST_MULT),
					TaskWeight.forPlayer(stateB, roleB, GHOST_MULT),
				}

				check(
					`{stateA}/{roleA} + {stateB}/{roleB} counts {expected}`,
					TaskParticipants.count(weights, FULL) == expected,
					`got {TaskParticipants.count(weights, FULL)}`
				)

				check(
					`{stateA}/{roleA} + {stateB}/{roleB} meets {REQUIRED} iff {expected} >= {REQUIRED}`,
					TaskParticipants.meets(weights, REQUIRED, FULL) == (expected >= REQUIRED)
				)
			end
		end
	end
end

-- An empty task point. Not a hypothetical: it is the normal state of four of the five.
check("nobody present is nobody participating", TaskParticipants.count({}, FULL) == 0)

-- §4.7 forward case (C15): ghosts help, ghosts do not substitute.
check("two ghosts do not open a two-person task", not TaskParticipants.meets({
	TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
	TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
}, REQUIRED, FULL))

-- A ghost helping a living survivor is still one participant, not two. §4.7 asks ghosts to matter,
-- and they do — through the hold's weight — but they cannot be the second body this task requires.
check("a ghost does not make up the second participant", not TaskParticipants.meets({
	TaskWeight.forPlayer("ALIVE", "SURVIVOR", GHOST_MULT),
	TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
}, REQUIRED, FULL))

--[[
	AMENDMENT A2's SHARPEST CASE, ASSERTED BY NAME.

	It is already covered by the grid above. It is written out again because the grid proves it as one
	cell among 256, and this is the sentence somebody will come looking for when they are about to
	make the Aswang not count. A2: "A pair that stood there producing nothing would be an
	instantaneous reveal with nothing to deduce."
]]
check(
	"a survivor and the Aswang together complete a two-person task",
	TaskParticipants.meets({
		TaskWeight.forPlayer("ALIVE", "SURVIVOR", GHOST_MULT),
		TaskWeight.forPlayer("ALIVE", "ASWANG", GHOST_MULT),
	}, REQUIRED, FULL)
)

-- And two Aswangs would too, if the game ever drew two. Stated so the rule reads as "roles are not
-- consulted" rather than "the Aswang is special-cased in the other direction".
check(
	"the count never consults a role at all",
	TaskParticipants.meets({
		TaskWeight.forPlayer("ALIVE", "ASWANG", GHOST_MULT),
		TaskWeight.forPlayer("ALIVE", "ASWANG", GHOST_MULT),
	}, REQUIRED, FULL)
)

if failures > 0 then
	error(`{failures} task-participants failure(s)`, 0)
end

print(`  PASS  task-participants: {assertions} assertions over every PlayerState x Role pair`)
