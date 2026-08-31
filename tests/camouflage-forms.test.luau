--!strict
--[[
	tests/camouflage-forms.test.luau

	`CamouflageForm` IS DECLARED IN EIGHT PLACES AND NOTHING CHECKED THAT THEY AGREE.

	Three are Luau literal unions, one is a table of cast values, and the rest are lists and branch
	chains inside `AmbientService`. A union that drifts does
	not fail where it is wrong: it widens to plain `string` on `require`, and the analyzer reports the
	failure at a CALL SITE IN ANOTHER FILE. That is
	`.claude/lessons/pure-module-unions-widen-in-lists.md`, which cost eight failed fixes at C21
	because every error named the wrong file.

	SO THIS SUITE READS ALL FIVE AS TEXT AND COMPARES THE SETS. Text, not `require`, for the reason
	every other `barrio-*` suite gives: Lune has no `game`, `Enums` requires `script.Parent`, and
	`AmbientService` requires `ReplicatedStorage`. None of the three can be loaded here, and the thing
	being checked is spelling rather than behaviour.

	THE CANONICAL SET IS DECLARED HERE, ONCE, AND EVERY SITE IS COMPARED TO IT rather than to each
	other. Comparing sites pairwise passes when all five are wrong in the same way, which is exactly
	what a careless find-and-replace produces.
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

--[[
	§4.3's forms, and the order is the spawn order in `AmbientService.Start`.

	SIX RATHER THAN FOUR, AND THE TWO NEW ONES ARE NOT DECORATION. §5 asks for a population dense
	enough that "which cat" is a real question; GOAT and CHICKEN are the two animals a rural Philippine
	barrio actually carries in numbers, and both are TETHERED OR YARD-BOUND in life, which is what
	makes per-form territories accurate rather than arbitrary.
]]
local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }

local function setOf(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}

	for _, item in list do
		set[item] = true
	end

	return set
end

local CANONICAL = setOf(FORMS)

-- Counted rather than typed, because three of the comparisons below are guarded by a `nil` check on
-- their own block match — so a scan that silently stopped finding its site would otherwise leave the
-- summary claiming a coverage the run did not have.
local sites = 0

-- Compare one site's members against the canonical set, in BOTH directions. A site that is missing a
-- form and a site that carries an extra one are different bugs and both are silent.
local function compare(site: string, found: { string })
	local seen = setOf(found)

	sites += 1

	check(`{site} declares exactly {#FORMS} forms`, #found == #FORMS, `{#found} found`)

	for _, form in FORMS do
		check(`{site} declares {form}`, seen[form] == true)
	end

	for member in seen do
		check(`{site} declares nothing beyond the canonical set`, CANONICAL[member] == true, member)
	end
end

-- Pull the members out of a `"A" | "B" | "C"` union, wherever it is spelled and however it wraps.
local function unionMembers(source: string, declaration: string): { string }
	local body = string.match(source, `{declaration}([^\n]*\n?[^\n]*\n?[^\n]*)`)
	local members: { string } = {}

	if body == nil then
		return members
	end

	for member in string.gmatch(body, `"([A-Z_]+)"`) do
		table.insert(members, member)
	end

	return members
end

compare(
	"Types.luau",
	unionMembers(fs.readFile("src/shared/Types.luau"), "export type CamouflageForm =")
)
compare(
	"pure/AmbientRoster.luau",
	unionMembers(fs.readFile("src/shared/pure/AmbientRoster.luau"), "export type CamouflageForm =")
)
compare(
	"pure/CamouflageRules.luau",
	unionMembers(
		fs.readFile("src/shared/pure/CamouflageRules.luau"),
		"export type CamouflageForm ="
	)
)

--[[
	`Enums` IS CHECKED THROUGH ITS CASTS, NOT ITS KEYS. `Cat = "CAT" :: Types.CamouflageForm` is the
	shape, and the CAST is the load-bearing half — CLAUDE.md is explicit that without it the field
	infers as plain `string` and fails to satisfy the literal union. A member added without its cast
	would pass a key scan and break at the first call site.
]]
local enums = fs.readFile("src/shared/Enums.luau")
local enumBlock = string.match(enums, "Enums%.CamouflageForm = table%.freeze%({(.-)%}%)")

check("Enums declares a frozen CamouflageForm table", enumBlock ~= nil)

if enumBlock ~= nil then
	local cast: { string } = {}

	for member in string.gmatch(enumBlock, `"([A-Z_]+)" :: Types%.CamouflageForm`) do
		table.insert(cast, member)
	end

	compare("Enums.luau (with its :: Types.CamouflageForm cast)", cast)
end

--[[
	`AmbientService` IS THREE SITES IN ONE FILE AND ALL THREE ARE CHECKED SEPARATELY.

	`FORM_LOOKS` says what a form LOOKS like, `formFromId` says which strings NARROW to a form, and
	`Start` says which forms are SPAWNED. A form present in the first two and missing from the third
	has a look, a type and no entities — `ClaimSlot` refuses it forever and the Aswang simply never
	gets that disguise, with nothing anywhere reporting it.
]]
local service = fs.readFile("src/server/Services/AmbientService.luau")
local looksBlock = string.match(service, "local FORM_LOOKS: {.-} =\n\t{(.-)\n\t}")

check("AmbientService declares a FORM_LOOKS table", looksBlock ~= nil)

if looksBlock ~= nil then
	local looks: { string } = {}

	for member in string.gmatch(looksBlock, "\n\t\t([A-Z_]+) = {") do
		table.insert(looks, member)
	end

	compare("AmbientService FORM_LOOKS", looks)
end

local narrowed: { string } = {}

--[[
	THE OPENING `if` IS ANCHORED TO THE START OF ITS LINE, and the unanchored version was wrong in a
	way that could never pass. `if id == "` is a SUBSTRING of `elseif id == "`, so a bare pattern
	matched every branch twice — six forms scanned as eleven members, and the count assertion below
	failed no matter how the file was written. Anchoring keeps the two patterns disjoint, which is what
	lets the count still mean "no form is listed twice" rather than being deduped into always passing.
]]
for member in string.gmatch(service, `\n\tif id == "([A-Z_]+)" then`) do
	table.insert(narrowed, member)
end

for member in string.gmatch(service, `elseif id == "([A-Z_]+)" then`) do
	table.insert(narrowed, member)
end

compare("AmbientService formFromId", narrowed)

local spawned: { string } = {}

for member in string.gmatch(service, `spawnForm%("([A-Z_]+)"%)`) do
	table.insert(spawned, member)
end

compare("AmbientService Start spawns", spawned)

--[[
	AND `FORM_IDS`, THE SEVENTH SITE, WHICH PHASE 3 ADDED.

	It is a `{ string }` rather than a `{ Types.CamouflageForm }`, deliberately — nothing is ever
	RETURNED from it, so there is no narrowing to lose and the lesson about unions widening in lists
	does not bite. What it does do is KEY the per-form partition of spawn points and SIZE the fallback
	ring, so a form missing from it is a form with no territories and no ring slots: `ClaimSlot`
	refuses it forever and the Aswang never gets that disguise.
]]
local idsBlock = string.match(service, "local FORM_IDS = {(.-)}")

check("AmbientService declares a FORM_IDS list", idsBlock ~= nil)

if idsBlock ~= nil then
	local ids: { string } = {}

	for member in string.gmatch(idsBlock, `"([A-Z_]+)"`) do
		table.insert(ids, member)
	end

	compare("AmbientService FORM_IDS", ids)
end

--[[
	AND THE MULTIPLIER, WHICH IS NOW DERIVED RATHER THAN TYPED.

	It was `PerForm * 4`, hand-written because the form count was not a value this codebase had. Six
	forms with a `* 4` still there is a fallback ring of 24 points for 18 entities — the wrong size,
	and only in the fallback path, which nothing exercises until the map is missing.

	PHASE 3 GAVE THE CODEBASE THAT VALUE, so the assertion changed from "the literal is 6" to "there
	is no literal". `#FORM_IDS` cannot drift from the list above it, and the list is pinned against
	the canonical set six assertions up.
]]
check(
	"the fallback ring is sized from #FORM_IDS, not a hand-written form count",
	string.find(service, "Config.Ambient.PerForm * #FORM_IDS", 1, true) ~= nil,
	"a typed multiplier goes stale silently the next time a form is added"
)

if failures > 0 then
	error(`{failures} camouflage-forms assertion(s) failed`, 0)
end

print(
	`  PASS  camouflage-forms: {checked} assertions over {#FORMS} forms in {sites} declaration sites`
)
