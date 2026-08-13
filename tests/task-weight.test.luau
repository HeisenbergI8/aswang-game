--!strict
--[[
	The anti-oracle grid. §4.4 + Amendment A2.

	THE DOMAIN IS BOUNDED AND SMALL — 4 PlayerStates × 2 Roles = 8 cells — SO IT IS ENUMERATED RATHER
	THAN SAMPLED. This repo has already paid for the alternative: a guard patched case-by-case as each
	new hole was found, green after every patch, wrong four times running. A grid written before the
	rule finds in one pass what four reactive fixes did not converge on.

	The assertion that matters is not any single cell's value. It is the COLUMN COMPARISON: for every
	PlayerState, the Aswang's weight equals the Survivor's. That is what stops a future edit from
	reintroducing the role oracle Amendment A2 removed — the one where a survivor taps interact next to
	a held task, sees the bar frozen, and knows.
]]

local Config = require("../src/shared/Config")
local TaskWeight = require("../src/server/pure/TaskWeight")

local GHOST = Config.Ghost.TaskContributionMult

local STATES: { TaskWeight.PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local ROLES: { TaskWeight.Role } = { "SURVIVOR", "ASWANG" }

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

--[[
	THE WHOLE POINT OF THE FILE. Every state, both roles, compared to each other.

	If this loop ever fails, someone has made the task bar a function of who you are, and the game's
	central secret is readable by anyone willing to stand still for two seconds.
]]
local cells = 0

for _, state in STATES do
	local survivor = TaskWeight.forPlayer(state, "SURVIVOR", GHOST)
	local aswang = TaskWeight.forPlayer(state, "ASWANG", GHOST)

	cells += 2

	check(
		`{state}: the Aswang contributes exactly what a survivor does`,
		survivor == aswang,
		`survivor={survivor}, aswang={aswang}`
	)
end

-- The values themselves, once each. These are balance; the comparison above is secrecy.
for _, role in ROLES do
	check(`{role}: ALIVE contributes full weight`, TaskWeight.forPlayer("ALIVE", role, GHOST) == 1)
	check(
		`{role}: GHOST contributes the reduced rate (§4.7, C15)`,
		TaskWeight.forPlayer("GHOST", role, GHOST) == GHOST,
		`{TaskWeight.forPlayer("GHOST", role, GHOST)} vs {GHOST}`
	)
	check(`{role}: LOBBY contributes nothing`, TaskWeight.forPlayer("LOBBY", role, GHOST) == 0)
	check(
		`{role}: SPECTATOR contributes nothing (§6.4, joined mid-round)`,
		TaskWeight.forPlayer("SPECTATOR", role, GHOST) == 0
	)
end

check("the grid covered every cell", cells == #STATES * #ROLES, `{cells}`)

--[[
	A ghost multiplier that has been tuned negative must floor at zero rather than SUBTRACTING
	progress. Negative weight would make `TaskProgress.tick` treat a helping ghost as absent (its
	`weight <= 0` guard), which is survivable — but a future caller summing weights would see a
	contributor that actively removes progress, and §4.4's freeze-not-decay rule forbids that.
]]
check(
	"a negative ghost multiplier floors at zero",
	TaskWeight.forPlayer("GHOST", "SURVIVOR", -1) == 0
)
check("a zero ghost multiplier is zero", TaskWeight.forPlayer("GHOST", "ASWANG", 0) == 0)

if failures > 0 then
	error(`{failures} task-weight assertion(s) failed`, 0)
end

print("  PASS  task-weight: 8-cell PlayerState × Role grid + 10 value assertions")
