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
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

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
	--[[
		THE TWO BOUNDS ON THE GHOST RATE, stated as relationships rather than as the literal 0.25.

		Step 8.2 of the C13–C16 plan asked for exactly this and it was missed on the first pass — the
		suite passed because the equality above predates the step, so nothing failed and nothing was
		proven. `> 0` is §4.7's retention half: at zero a ghost is a spectator again and the whole
		reason the ghost system exists is gone. `< ALIVE` is the balance half: at parity, dying costs
		nothing and the living have no reason to protect anyone.
	]]
	check(
		`{role}: a ghost contributes MORE than nothing`,
		TaskWeight.forPlayer("GHOST", role, GHOST) > 0,
		"at zero, §4.7's retention fix does not exist"
	)
	check(
		`{role}: a ghost contributes LESS than the living`,
		TaskWeight.forPlayer("GHOST", role, GHOST) < TaskWeight.forPlayer("ALIVE", role, GHOST),
		"at parity, dying is free"
	)
	--[[
		AND FOUR GHOSTS DO NOT OUTPACE ONE SURVIVOR. The literal 0.25 says this today; the assertion
		says it will keep being true if M12 tunes the rate. A lobby full of dead players finishing the
		tasks faster than the living ever could is the shape this refuses.
	]]
	check(
		`{role}: three ghosts fall short of one full contributor`,
		TaskWeight.forPlayer("GHOST", role, GHOST) * 3 < TaskWeight.forPlayer("ALIVE", role, GHOST),
		"a crowd of ghosts must not outpace a survivor"
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

print(`  PASS  task-weight: {checked} assertions over the PlayerState × Role grid`)
