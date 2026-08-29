--!strict
--[[
	THE BUILDER'S SELF-AUDIT — its header contract table, and the receipt it prints at build time.

	Separate from `barrio-legacy` on purpose. That suite bans dead tokens; this one guards the two
	pieces of the file whose whole job is to DESCRIBE the contract truthfully: the header table a
	reader trusts, and the receipt plus asserts that fail the build when the map does not match.

	THIS IS THE SUITE THAT WOULD HAVE CAUGHT THE DEFECT THAT PROMPTED IT. An earlier draft of the
	Phase 2 diff deleted four of the five stale header lines and left
	`TaskPoint ×12  TaskService.discoverPool` in place as unchanged context — six lines above a
	near-identical `TaskPoint × 2  TrialService.trialPoints` line that is CORRECT and must stay. The
	two differ only in count and service name. Gated on `npm run test:unit`, that miss would have
	shipped green.

	THE THREE LITERALS ARE THE OTHER HALF. `barrio.luau` runs in Studio's command bar and cannot
	reliably require a Rojo-synced module, so its asserted counts are hand-copied from `Config.luau`.
	Reconciling them here is what makes hand-copying a safe thing to do rather than a time bomb.
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

local builder = fs.readFile("tools/greybox/barrio.luau")
local config = fs.readFile("src/shared/Config.luau")

local header = string.match(builder, "^(.-)\nlocal CollectionService")

check("the builder opens with a header block", header ~= nil)

if not header then
	error("1 barrio-receipt assertion(s) failed", 0)
end

local head = header :: string

--[[
	THE HEADER MUST NAME THE LIVE CONTRACT AND ONLY THE LIVE CONTRACT.

	`barrio-legacy` already bans the dead service names across the whole file. What is checked here is
	the positive half, which that suite cannot express: the table must actually LIST the two tags v2.0
	depends on. A header that names no dead service and also names no live one is not a contract.
]]
for _, tag in
	{ "SearchContainer", "AmbientSpawn", "SaltSpawn", "TrialSpawn", "TrialChase", "MapLight" }
do
	check(`the header contract table lists {tag}`, string.find(head, tag, 1, true) ~= nil)
end

--[[
	EXACTLY ONE `TaskPoint` LINE SURVIVES, AND IT IS THE TRIAL'S.

	The deleted line named `TaskService`; the surviving one names `TrialService`, whose
	`trialPoints` still reads the tag. Asserting the count rather than the absence is deliberate — a
	blanket ban on `TaskPoint` would be wrong and would break §9.1's cold-start answer silently.
]]
local taskPointRows = 0

for line in string.gmatch(head, "[^\n]+") do
	--[[
		COUNT TABLE ROWS, NOT MENTIONS. The header discusses `TaskPoint` in prose as well, which is
		legitimate and must not fail this. What must be unique is the ROW — the `TagName ×N  Service`
		shape in the contract table — because that is the line a reader takes as the contract.
	]]
	if string.match(line, "^%s+TaskPoint%s+×") then
		taskPointRows += 1
	end
end

check(
	"the contract table has exactly one TaskPoint row — the Solo Trial's",
	taskPointRows == 1,
	`{taskPointRows} row(s); v1.3 had two and the '×12 TaskService.discoverPool' one is the one that goes`
)
check(
	"the surviving TaskPoint line is the TrialService one",
	string.find(head, "TrialService.trialPoints", 1, true) ~= nil
)

-- The receipt must count what the map is now judged on. A receipt naming dead tags prints zeros.
local receipt = string.match(builder, "\nprint%(\n\t`%[barrio%] built(.-)\n%)")

check("the builder prints a build receipt", receipt ~= nil)

if receipt then
	for _, tag in
		{ "SearchContainer", "SaltSpawn", "AmbientSpawn", "TrialOnly", "TrialSpawn", "TrialChase" }
	do
		check(`the receipt counts {tag}`, string.find(receipt :: string, tag, 1, true) ~= nil)
	end
end

--[[
	THE RECONCILIATION. Each asserted literal in the builder must equal the value `Config.luau` holds,
	because the builder cannot read Config and the two drifting apart is silent in both directions:
	Config raised without the builder gives a short pool that only warns, and the builder raised
	without Config gives a map the services never fully use.
]]
local function configNumber(key: string): number
	local raw = string.match(config, `\n\t\t{key} = (%d+),`)

	assert(
		raw,
		`Config.luau has no two-tab '{key} = <number>,' — the key was renamed or re-nested`
	)

	return tonumber(raw) :: number
end

local function assertedCount(tag: string): number?
	local raw = string.match(builder, `count%("{tag}"%) == (%d+),`)

	return if raw then tonumber(raw) else nil
end

local containerCount = configNumber("ContainerCount")
local ambientExpected = configNumber("PerForm") * 4

local assertedContainers = assertedCount("SearchContainer")
local assertedAmbient = assertedCount("AmbientSpawn")

check("the builder asserts its SearchContainer count", assertedContainers ~= nil)
check("the builder asserts its AmbientSpawn count", assertedAmbient ~= nil)

check(
	"the asserted SearchContainer count equals Config.Search.ContainerCount",
	assertedContainers == containerCount,
	`builder asserts {tostring(assertedContainers)}, Config says {containerCount}`
)
check(
	"the asserted AmbientSpawn count equals Config.Ambient.PerForm x 4",
	assertedAmbient == ambientExpected,
	`builder asserts {tostring(assertedAmbient)}, Config implies {ambientExpected}`
)
check(
	"the builder asserts the Solo Trial still has its two points",
	string.find(builder, "countTrialOnly() == 2", 1, true) ~= nil,
	"without this a trial with nothing to do is silent"
)

if failures > 0 then
	error(`{failures} barrio-receipt assertion(s) failed`, 0)
end

print(`  PASS  barrio-receipt: {checked} assertions over the header and the receipt`)
