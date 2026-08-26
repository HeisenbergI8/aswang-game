--!strict
--[[
	WinConditions — DELIBERATELY EMPTY UNTIL V11 (§4.8, V01).

	v1.3's attrition rule (`AswangKills >= DealtInSurvivors - 2`) and the module behind it were deleted
	at V01. v2.0's Aswang wins by killing EVERYONE, and V11 writes that rule and refills this file.

	WHY THIS FILE SURVIVED THE MODULE IT TESTED. The rule it used to pin took FOUR attempts, and the
	first three each passed a suite written from the bug just seen:

	  1. freeze DealtInSurvivors at STARTING   — livingSurvivorCount() was LIVE, so a disconnect moved
	                                             one side of the comparison and not the other
	  2. decrement it on a non-kill death      — closed reset-then-reset and nothing else
	  3. decrement it on disconnect too        — ARITHMETICALLY INERT above four survivors

	What finally worked was not a better expression. It was ENUMERATING the space — roster × kills ×
	resets × disconnects — instead of sampling it. V11's win condition has the same shape and the same
	four dimensions, so it earns the same treatment, and the habit is easier to keep than to rediscover.

	V11: restore `local WinConditions = require("../src/shared/pure/WinConditions")`, fill CASES, and
	delete this note.
]]

local checked = 0

-- The grid goes here. `checked` is incremented by the assertions V11 adds, and the PASS line below
-- interpolates it rather than stating a number — see `.claude/scripts/check-testcount.mjs` for why a
-- literal tally in a summary line is structurally incapable of noticing a deleted assertion.

print(`  PASS  win-conditions: {checked} assertions — skeleton, awaiting the rewritten win rule`)
