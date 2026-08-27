--!strict
--[[
	The noise history's bound, proven. (V04, §4.4)

	The build plan's Done line says the history is "server-only and bounded". Server-only is a
	placement and a code review; BOUNDED is arithmetic, and this is where it is checked — including
	the case the service should never produce, because the reason to have a cap at all is the day
	something removes a throttle.
]]

local NoiseLog = require("../src/server/pure/NoiseLog")

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

local LIMITS = { HistorySeconds = 120, MaxRecords = 512 }

local function recordAt(at: number, x: number): NoiseLog.Record
	return {
		Action = "SEARCH",
		Loudness = 1,
		Radius = 60,
		Position = { X = x, Y = 0, Z = 0 },
		At = at,
	}
end

print("NoiseLog")

-- THE THROTTLE.
check("a first noise always records", NoiseLog.shouldRecord(nil, 100, 6))
check("a noise inside the interval is refused", not NoiseLog.shouldRecord(100, 105.9, 6))
check("a noise exactly at the interval records", NoiseLog.shouldRecord(100, 106, 6))
check("a noise after the interval records", NoiseLog.shouldRecord(100, 400, 6))
check("a backwards clock refuses", not NoiseLog.shouldRecord(100, 99, 6))
check("a zero interval never refuses", NoiseLog.shouldRecord(100, 100, 0))

-- APPEND DOES NOT MUTATE ITS INPUT.
local original = { recordAt(1, 0) }
local grown = NoiseLog.append(original, recordAt(2, 0), LIMITS)

check("append leaves the input alone", #original == 1)
check("append returns the longer list", #grown == 2)

-- AGE PRUNING. A record older than the window is gone; one exactly at the edge is kept.
local aged = NoiseLog.append({ recordAt(0, 0), recordAt(10, 0) }, recordAt(121, 0), LIMITS)

check("a record past the window is dropped", #aged == 2)
check("the survivors stay in order", aged[1].At == 10 and aged[2].At == 121)

local edge = NoiseLog.append({ recordAt(1, 0) }, recordAt(121, 0), LIMITS)

check("a record exactly at the window edge is kept", #edge == 2)

--[[
	THE FLOOD. Ten noises a second for ten minutes — an emit rate the throttles make impossible,
	which is exactly the case the cap exists for. The history must stay capped AND stay recent.
]]
local history: { NoiseLog.Record } = {}
local ceiling = 0

for step = 1, 6000 do
	history = NoiseLog.append(history, recordAt(step / 10, 0), LIMITS)
	ceiling = math.max(ceiling, #history)
end

check("the flood never exceeds the cap", ceiling <= LIMITS.MaxRecords, `peak={ceiling}`)
check("the flood keeps the newest record", history[#history].At == 600)
check(
	"nothing older than the window survives",
	history[1].At >= 600 - LIMITS.HistorySeconds,
	`oldest={history[1].At}`
)

-- A CAP THAT CANNOT HOLD ANYTHING STILL HOLDS THE NEW RECORD.
local squeezed = NoiseLog.append({ recordAt(1, 0) }, recordAt(2, 0), {
	HistorySeconds = 120,
	MaxRecords = 0,
})

check("a zero cap still records the newest", #squeezed == 1 and squeezed[1].At == 2)

-- THE WINDOW QUERY, INCLUDING THE COPY. A tracker will sort what it is handed.
local queried = NoiseLog.recentSince({ recordAt(10, 0), recordAt(90, 0) }, 100, 30)

check("only the recent tail comes back", #queried == 1 and queried[1].At == 90)
check("an empty window is empty, not nil", #NoiseLog.recentSince({}, 100, 30) == 0)

local source = { recordAt(90, 5) }
local handed = NoiseLog.recentSince(source, 100, 30)

handed[1].Position.X = 999
handed[1].At = 0

check("the query returns copies", source[1].Position.X == 5 and source[1].At == 90)

-- EARSHOT. Inclusive at the boundary, and silent for a radius that is not one.
local here = { X = 0, Y = 0, Z = 0 }

check("a listener on top of it hears", NoiseLog.withinRadius(here, here, 60))
check(
	"a listener exactly at the radius hears",
	NoiseLog.withinRadius(here, { X = 60, Y = 0, Z = 0 }, 60)
)
check(
	"a listener past it does not",
	not NoiseLog.withinRadius(here, { X = 60.1, Y = 0, Z = 0 }, 60)
)
check("height counts", not NoiseLog.withinRadius(here, { X = 0, Y = 61, Z = 0 }, 60))
check("a zero radius reaches nobody", not NoiseLog.withinRadius(here, here, 0))
check("a negative radius reaches nobody", not NoiseLog.withinRadius(here, here, -60))

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} NoiseLog check(s) failed`, 0)
end
