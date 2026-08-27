--!strict
--[[
	The noise price list, over its whole domain. (V04, §4.4)

	The build plan asks for "the action x state grid", not a smoke test, and the reason is the same
	one `monster-health` will have at V05: this module is a small pure function over a BOUNDED
	domain, which is the one shape where enumerating beats writing a case per bug. There are four
	actions, one state field and a handful of degenerate values, so the grid is small enough to walk
	completely — and the two properties that matter (search is the loudest; the sprint threshold
	holds) are exactly the ones a playtest cannot see.
]]

local Config = require("../src/shared/Config")
local NoiseModel = require("../src/shared/pure/NoiseModel")

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

-- A SYNTHETIC tuning, not Config's. These assertions are about the MODEL's rules; V16 will retune
-- Config and must not be able to red this file. The real block is cross-checked at the bottom.
local TUNING = {
	Actions = {
		SEARCH = { Loudness = 1, Radius = 60, MinInterval = 6 },
		ITEM_USE = { Loudness = 0.7, Radius = 40, MinInterval = 2 },
		DOOR = { Loudness = 0.5, Radius = 30, MinInterval = 2 },
		SPRINT = { Loudness = 0.6, Radius = 35, MinInterval = 2 },
	},
	SprintSpeedStuds = 22,
	CueGridStuds = 8,
}

local ACTIONS = { "SEARCH", "ITEM_USE", "DOOR", "SPRINT" }
local STILL = { "SEARCH", "ITEM_USE", "DOOR" }
-- Zero, a walk, the baseline, a transformed Aswang's 20, either side of the threshold, and the four
-- values that break a naive comparison.
local SPEEDS = { 0, 4, 16, 20, 21.9, 22, 22.1, 400, -5, 0 / 0, math.huge, -math.huge }

print("NoiseModel")

-- THE GRID. Every action against every speed, asserting the one invariant that must hold across all
-- of it: an emission is either nil or a pair of finite, in-range numbers.
for _, action in ACTIONS do
	for _, speed in SPEEDS do
		local result = NoiseModel.evaluate(action, { SpeedStuds = speed }, TUNING)

		if result ~= nil then
			check(
				`{action} at {speed}: loudness in 0..1`,
				result.Loudness >= 0 and result.Loudness <= 1,
				`{result.Loudness}`
			)
			check(`{action} at {speed}: radius not negative`, result.Radius >= 0, `{result.Radius}`)
		end
	end
end

-- SPEED IS IGNORED BY EVERY NON-MOVEMENT ACTION. A search is a search at any speed, and the day this
-- stops being true is the day "who searched while standing still" becomes a thing to read off noise.
for _, action in STILL do
	local base = NoiseModel.evaluate(action, {}, TUNING)

	check(`{action} emits with no state at all`, base ~= nil)

	if base ~= nil then
		for _, speed in SPEEDS do
			local moving = NoiseModel.evaluate(action, { SpeedStuds = speed }, TUNING)

			check(
				`{action} is unchanged at {speed}`,
				moving ~= nil and moving.Loudness == base.Loudness and moving.Radius == base.Radius
			)
		end
	end
end

-- THE SPRINT THRESHOLD, at the boundary and on both sides of it, including the values a naive
-- comparison waves through: NaN fails every comparison, so `nan < threshold` is FALSE and an
-- unguarded model would emit for it.
check(
	"sprint is silent below the threshold",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = 21.9 }, TUNING) == nil
)
check(
	"sprint is silent at a walk",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = 16 }, TUNING) == nil
)
check(
	"sprint is silent for a transformed monster's speed",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = 20 }, TUNING) == nil
)
check("sprint is silent with no speed given", NoiseModel.evaluate("SPRINT", {}, TUNING) == nil)
check(
	"sprint is silent for NaN",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = 0 / 0 }, TUNING) == nil
)
check(
	"sprint is silent for -inf",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = -math.huge }, TUNING) == nil
)
check(
	"sprint is silent for a negative speed",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = -5 }, TUNING) == nil
)
check(
	"sprint emits at the threshold",
	NoiseModel.evaluate("SPRINT", { SpeedStuds = 22 }, TUNING) ~= nil
)
check("sprint emits above it", NoiseModel.evaluate("SPRINT", { SpeedStuds = 400 }, TUNING) ~= nil)

-- FAILS CLOSED. An id with no row is silent, not loud.
check(
	"an unknown action is silent",
	NoiseModel.evaluate("SHOUT", { SpeedStuds = 0 }, TUNING) == nil
)
check("an empty action is silent", NoiseModel.evaluate("", { SpeedStuds = 0 }, TUNING) == nil)

-- §4.4: searching is the loudest thing a survivor does. Asserted here over the MODEL's output as
-- well as over Config, because the model is what a caller sees.
local search = NoiseModel.evaluate("SEARCH", {}, TUNING)

check("SEARCH emits", search ~= nil)

if search ~= nil then
	for _, action in ACTIONS do
		local other = NoiseModel.evaluate(action, { SpeedStuds = 400 }, TUNING)

		if other ~= nil then
			check(`SEARCH is at least as loud as {action}`, search.Loudness >= other.Loudness)
			check(`SEARCH carries at least as far as {action}`, search.Radius >= other.Radius)
		end
	end
end

-- Clamping, proven with a tuning nobody would write on purpose but M12 could typo.
local absurd = {
	Actions = { SEARCH = { Loudness = 9, Radius = -3, MinInterval = 1 } },
	SprintSpeedStuds = 22,
	CueGridStuds = 8,
}
local clamped = NoiseModel.evaluate("SEARCH", {}, absurd)

check("loudness is clamped to 1", clamped ~= nil and clamped.Loudness == 1)
check("a negative radius clamps to 0", clamped ~= nil and clamped.Radius == 0)

-- THE QUANTISER. Every output lands on a grid cell, within half a cell of the truth, and two points
-- inside one cell are indistinguishable — which is the property §4.6 is actually asking for.
local POINTS = { 0, 0.1, 3.9, 4, 4.1, 12, -3.9, -4.1, 137.25 }

for _, x in POINTS do
	local q = NoiseModel.quantise({ X = x, Y = x, Z = x }, TUNING.CueGridStuds)

	check(`{x} lands on the grid`, q.X % TUNING.CueGridStuds == 0, `{q.X}`)
	check(`{x} moves less than a cell`, math.abs(q.X - x) <= TUNING.CueGridStuds / 2, `{q.X}`)
	check(`{x} quantises all three axes alike`, q.X == q.Y and q.Y == q.Z)
end

local a = NoiseModel.quantise({ X = 1, Y = 1, Z = 1 }, 8)
local b = NoiseModel.quantise({ X = 2.5, Y = 2.5, Z = 2.5 }, 8)

check("two points in one cell are indistinguishable", a.X == b.X and a.Z == b.Z)

local ungridded = NoiseModel.quantise({ X = 3, Y = 3, Z = 3 }, 0)

check("a zero grid returns the position unchanged", ungridded.X == 3)

--[[
	THE CROSS-CHECK. Everything above runs on a synthetic tuning so V16 can retune freely — but a
	MISSING ROW in the real block would then go unnoticed until a live search made no noise, which is
	a silent failure with no symptom except that the game got easier.
]]
for _, action in ACTIONS do
	check(
		`Config.Noise prices {action}`,
		NoiseModel.evaluate(action, { SpeedStuds = 999 }, Config.Noise) ~= nil
	)
end

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} NoiseModel check(s) failed`, 0)
end
