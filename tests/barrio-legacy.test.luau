--!strict
--[[
	The builder must not resurrect v1.3.

	`tools/greybox/barrio.luau` is not under `src/`, so `lint`, `fmt:check`, `analyze` and all five
	repo checks skip it — each one's scope was verified rather than assumed. Until this suite it was
	the only executable artefact in the repo behind no gate at all, and it still emitted the escape
	gate and twelve task anchors that V01 deleted from the code. Re-running it resurrected them into
	the place file, where nothing would ever have shown it: the map is not in git.

	Lune has no `game`, so this cannot run the builder. It reads it as TEXT, which is enough for the
	class of fault that actually happened here — a name that should no longer appear anywhere.
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

local function occurrences(haystack: string, needle: string): number
	local _, n = string.gsub(haystack, needle, "")

	return n
end

local builder = fs.readFile("tools/greybox/barrio.luau")
local measure = fs.readFile("tools/greybox/measure.luau")

--[[
	V01 demolished tasks, the escape gate and ghosts. No service reads either tag now, and no service
	by either name exists. A surviving mention is either dead geometry or a comment that lies about
	the contract — and the comment is the more expensive of the two, because it is what the next
	reader trusts.
]]
for _, dead in { "EscapeGate", "FetchSource", "TaskService", "GateService" } do
	check(
		`the builder no longer mentions {dead}`,
		occurrences(builder, dead) == 0,
		`{occurrences(builder, dead)} occurrence(s) in barrio.luau`
	)
	check(
		`measure.luau no longer mentions {dead}`,
		occurrences(measure, dead) == 0,
		`{occurrences(measure, dead)} occurrence(s) in measure.luau`
	)
end

--[[
	`TaskPoint` IS THE EXCEPTION AND IT IS THE WHOLE REASON THIS IS A TEST RATHER THAN A GREP.

	`TrialService` still holds `local TAG_POINT = "TaskPoint"` and reads it for the Solo Trial's two
	practice points. A blanket ban on the token would be wrong and would break §9.1's cold-start
	answer silently. What is banned is the ROUND's twelve, which all carried the `Task_` name prefix.
]]
check(
	"the round's twelve Task_ anchors are gone",
	occurrences(builder, '"Task_') == 0,
	`{occurrences(builder, '"Task_')} Task_ anchor name(s) remain`
)
check(
	"the Solo Trial's two TaskPoint anchors survive",
	occurrences(builder, "TrialOnly") >= 2,
	`{occurrences(builder, "TrialOnly")} TrialOnly reference(s) — TrialService.trialPoints needs both`
)

if failures > 0 then
	error(`{failures} barrio-legacy assertion(s) failed`, 0)
end

print(`  PASS  barrio-legacy: {checked} assertions across the builder and measure`)
