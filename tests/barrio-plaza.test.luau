--!strict
--[[
	THE PLAZA'S STREET FURNITURE — benches and banderitas.

	SEPARATE FROM `barrio-budget` BECAUSE A SHARED CHECK PROVES NOTHING. Steps 4.1 and 4.2 are two
	different pieces of work in one phase, and pointing both at the same suite means neither step's
	own check can fail for its own reason — `verify-plan --lint` reports that as `shared`, and it is
	right to. 4.1 owns the court and the kubo; this file owns what stands around them.

	It also replaces a grep that could not pass: `grep -c Bench1_Back` against a loop that writes
	`Bench{index}_Back`. The literal can never match the interpolation.
]]

local fs = require("@lune/fs")

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

local raw = fs.readFile("tools/greybox/barrio.luau")

--[[
	COMMENTS ARE STRIPPED BEFORE ANY SCAN, AND THAT IS NOT TIDINESS.

	These suites read the builder as text, so a check for a token finds it in PROSE as readily as in
	code. It has now happened three times in this project: a comment explaining why the escape gate was
	removed contained `EscapeGate`; a comment explaining the MaterialVariant binding rule contained an
	assignment; and the comment recording why the benches were deleted contained the word `Bench`. Each
	time the guard failed on the explanation of the fix rather than on the fix.

	A check that cannot be explained in a comment is a check nobody will document.
]]
local function stripComments(source: string): string
	-- Block comments first, so a `--` inside one cannot be mistaken for a line comment opener.
	local without = string.gsub(source, "%-%-%[%[.-%]%]", "")

	return (string.gsub(without, "%-%-[^\n]*", ""))
end

local builder = stripComments(raw)

--[[
	THERE ARE NO BENCHES, AND THAT IS THE ASSERTION.

	This file used to check that every bench had a back rail. Research says a Philippine barrio has no
	municipal park benches at all — people sit on the court's edge, a stall step, a plastic monobloc
	stool, or the low wall. Four benches were removed as a correction, not a budget cut, and the
	temptation to "add somewhere to sit" back into a plaza is strong enough to be worth pinning.

	This is the one check in the suite that guards an ABSENCE. Absences have no symptom: nothing looks
	broken when a bench reappears, it just quietly stops being a barrio.
]]
check(
	"the plaza has no benches",
	string.find(builder, "Bench", 1, true) == nil,
	"benches are street furniture from a different country; people sit on the court edge and stall steps"
)

--[[
	THE BANDERITAS. Faded, not fresh — this palette is a research finding that overrode the obvious
	choice, and it is the one most likely to be "corrected" back to primaries by a later reader.
]]
check("a faded fiesta palette exists", string.find(builder, "local FIESTA_COLOURS") ~= nil)
check(
	"the runs hang at uneven heights",
	string.find(builder, "local RUN_HEIGHT") ~= nil,
	"the tidy symmetrical square is back"
)
check("each bulb carries a paper triangle", string.find(builder, "{name}_Flag") ~= nil)

--[[
	THE FLAGPOLE stays — it is the civic marker every barrio plaza has, and it is the tallest thing in
	the middle of the map, which matters for §5's sightline rule.
]]
check("the plaza keeps its flagpole", string.find(builder, '"Flagpole"') ~= nil)

if failures > 0 then
	error(`{failures} barrio-plaza assertion(s) failed`, 0)
end

print(`  PASS  barrio-plaza: {checked} assertions over the benches and the banderitas`)
