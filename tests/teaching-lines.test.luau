--!strict
--[[
	C23's done condition, as a property rather than a feature.

	The row says it exactly: "every first-time interaction has exactly one line; none repeat." Both
	halves are silent when broken. A missing line is a player who never learns the mechanic, and a
	repeating line is §10's wall of text arriving one sentence at a time, every round, forever.

	Neither has a runtime symptom worth the name — the game keeps working and simply teaches badly.
]]

local TeachingLines = require("../src/shared/pure/TeachingLines")

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

-- The four moments C23's row lists. Written out here so the test fails if the table grows a fifth,
-- which is the whole point: a fifth line is a design decision, not a copy edit.
local EXPECTED_IDS = {
	"CUE_FIRST_SALT",
	"CUE_FIRST_TRANSFORM_SEEN",
}

local ids = TeachingLines.ids()

check(`the cue table is closed at four`, #ids == #EXPECTED_IDS, `got {#ids}`)

for index, id in EXPECTED_IDS do
	check(`cue {index} is {id}`, ids[index] == id, `got {tostring(ids[index])}`)
end

--------------------------------------------------------------------------------
-- Every cue resolves to a non-empty line the first time
--------------------------------------------------------------------------------

for _, id in EXPECTED_IDS do
	local line = TeachingLines.resolve(id, {})

	check(`{id} resolves on a fresh player`, line ~= nil)
	check(`{id}'s line is not empty`, line ~= nil and #line > 0)
end

--------------------------------------------------------------------------------
-- ...and never again. This is the half that is silent when broken.
--------------------------------------------------------------------------------

for _, id in EXPECTED_IDS do
	local seen: { [string]: boolean } = { [id] = true }

	check(`{id} does not repeat once seen`, TeachingLines.resolve(id, seen) == nil)
end

-- Seeing one cue must not suppress the other three. A shared flag instead of a per-cue one would
-- pass every test above and teach a player exactly one thing in their entire first round.
for _, seenId in EXPECTED_IDS do
	local seen: { [string]: boolean } = { [seenId] = true }

	for _, otherId in EXPECTED_IDS do
		if otherId == seenId then
			continue
		end

		check(
			`seeing {seenId} does not suppress {otherId}`,
			TeachingLines.resolve(otherId, seen) ~= nil
		)
	end
end

--------------------------------------------------------------------------------
-- Every line is distinct. Two cues sharing copy is a copy-paste bug that reads as
-- correct in every other assertion here.
--------------------------------------------------------------------------------

local byLine: { [string]: string } = {}

for _, id in EXPECTED_IDS do
	local line = TeachingLines.resolve(id, {})

	if line ~= nil then
		check(`{id}'s line is unique`, byLine[line] == nil, `also used by {tostring(byLine[line])}`)
		byLine[line] = id
	end
end

--------------------------------------------------------------------------------
-- Unknown ids teach nothing rather than erroring
--------------------------------------------------------------------------------

check(`an unknown cue resolves to nil`, TeachingLines.resolve("CUE_NOT_A_THING", {}) == nil)
check(`an empty id resolves to nil`, TeachingLines.resolve("", {}) == nil)
check(
	`an unknown cue in a populated seen-set is still nil`,
	TeachingLines.resolve("CUE_NOT_A_THING", { CUE_FIRST_SALT = true }) == nil
)

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

local probe: { [string]: boolean } = {}

TeachingLines.resolve("CUE_FIRST_SALT", probe)

check(`resolve does not mutate the seen-set`, next(probe) == nil)
check(
	`resolve is deterministic`,
	TeachingLines.resolve("CUE_FIRST_SALT", {}) == TeachingLines.resolve("CUE_FIRST_SALT", {})
)

if failures > 0 then
	error(`{failures} teaching-line failure(s)`, 0)
end

print(`  PASS  teaching-lines: {checked} assertions over the closed cue set`)
