--!strict
--[[
	REVIEW — tests/config.test.luau and tests/round-transitions.test.luau and tests/README.md

	Read to copy the house style for the four test files this plan adds, and for two constraints.
]]

-- tests/config.test.luau — the house style, verbatim. Every new test in this plan uses it:
local Config = require("../src/shared/Config") -- BY FILE PATH. Lune knows nothing about Rojo.

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- ... checks ...

if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end

print("  PASS  config: 13 balance invariants")
-- NOTE that count is PROSE. Nothing asserts it, which is exactly why it gets missed. Step 1.2 adds six
-- checks and updates it to 19.

--[[
	IMPORTANT — the purpose statement, which is the bar the six new invariants have to clear:

		"These are not tests of Config's VALUES — every number in there is explicitly 'a starting value
		 to tune' (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and
		 silent: nothing tells you when two numbers that must agree have stopped agreeing, and the
		 symptom shows up as a design failure rather than a bug."

	The six added in Step 1.2 are all relationships: weight ordering, weights positive, history shorter
	than the server, AswangCount below MinPlayers, and the intro fitting inside StartingDelay.
]]

-- One existing invariant this plan leans on directly, in tests/transform-rules.test.luau:
check(
	"the kill cooldown outlasts a full transform cycle",
	Config.Monster.KillCooldown > Config.Monster.TransformTime + Config.Monster.RevertTime
)
-- NOTE the transform-rules test states the STRONGER version of the same idea — cooldown must exceed
-- TransformTime + MaxTransformTime + RevertTime — because the cooldown runs from revert.

-- tests/round-transitions.test.luau — the pattern for exhaustive coverage over an enum, copied by
-- Step 7.2's loop over all four PlayerStates:
local ALL_PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
check("all 20 phase/expired/headcount combinations are covered", #CASES == 20, `got {#CASES}`)
-- IMPORTANT: asserting the COUNT is what makes an exhaustive test stay exhaustive when someone adds a
-- sixth enum value. Step 7.2 does the same with `#ALL_PLAYER_STATES == 4`.

--[[
	IMPORTANT — tests/README.md, and the line Step 4.4 amends:

		"Pure modules — no Roblox globals, no `script.Parent` requires."
		"...write it as a pure function taking plain tables, put it in `src/shared/pure/`, and have the
		 service call it."

	That second sentence is now incomplete: RoleDraw goes in `src/server/pure/` because its inputs and
	output are secret. Step 4.4 rewrites it with the two-location table. CLAUDE.md and BUILD-PLAN carry
	the same wording and are raised in Follow Ups rather than edited.

	NOTE also: "A non-zero exit is the whole protocol — `error()` produces one. The runner reports the
	file and the output; it does not parse a format, so there is nothing to keep in sync."
]]
