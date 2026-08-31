--!strict
--[[
	tests/barrio-doorways.test.luau

	NINE TAGGED DOORWAYS, AND WHY NONE OF THEM CAN BE CHECKED BY A GREP.

	Seven of the nine are emitted by `doorway(kubo.Name, side, ...)` inside the KUBO loop, so the part
	names are interpolations and a literal `grep Kubo_NW_DoorwayS` matches nothing —
	`tests/barrio-interiors.test.luau`'s opening finding, arriving in a second file exactly as it
	predicted. Anything built in a loop is checked by a suite that parses the SOURCE.

	AND THIS FILE IS OUTSIDE `src/`, so lint, analyze, fmt:check and the five repo checks all skip it.
	This suite is the only gate `doorway()` has.

	WHAT THIS SUITE IS DEFENDING, in order of how silently each fails:

	  1. `Width` WRITTEN AS A BARE `6`. `building()` works in pre-scale units and both `v()` and
	     `box()` multiply X/Z by `SCALE`, so the door gap of 6 units is 9.3 REAL STUDS. A barrier
	     built 6 studs wide across a 9.3-stud opening leaves 1.6 studs of gap at each jamb, and the
	     Aswang walks around the edge of the garlic. Nothing anywhere reports a fault — the barrier
	     exists, it is collidable, it is simply too narrow. This is the highest-value line in the file.
	  2. A PAD ON A FACE THAT HAS NO DOOR. A barrier in a solid wall denies nothing and the garlic is
	     spent. Driven off `kubo.Doors`, which is the builder's own source of truth.
	  3. A YAW THAT DISAGREES WITH THE AXIS CONVENTION. `pure/GarlicBarrier` builds its plane from
	     this attribute; a transposed yaw turns the barrier ninety degrees and it spans the wall
	     instead of the opening. The seven kubo would still be denied correctly by luck of their door
	     faces while the chapel's east door silently failed, and the chapel is the map's only two-door
	     room — the most likely venue for the loyalty test §4.6 exists for.
	  4. COORDINATES DRIFTING FROM THE `building()` CALL. The offsets are half-extents typed a second
	     time, which is the exact class of bug that put `Container_KuboN_Drum` forty studs outside its
	     house. Reconciled against the call rather than trusted.
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

--------------------------------------------------------------------------------
-- 1. THE HELPER. It must exist, tag `Doorway`, and write both attributes.
--------------------------------------------------------------------------------

local helper = string.match(builder, "local function doorway%b()%s*:%s*Part\n(.-)\nend")

check("the builder declares a `doorway()` helper", helper ~= nil)

if helper == nil then
	error("1 barrio-doorways assertion(s) failed — no doorway() helper to check", 0)
end

local body = helper :: string

check('doorway() tags "Doorway"', string.find(body, '"Doorway"', 1, true) ~= nil)

check("doorway() writes a Yaw attribute", string.find(body, "Yaw = ", 1, true) ~= nil)

check("doorway() writes a Width attribute", string.find(body, "Width = ", 1, true) ~= nil)

--[[
	THE BARE-`6` TRAP, PINNED BY SPELLING. `Width = 6 * SCALE` is 9.3 studs and `Width = 6` is a
	barrier two thirds the width of the doorway it is meant to deny. The failure has no symptom: the
	garlic is placed, the barrier exists, and the Aswang walks around its edge.
]]
check(
	"Width is `6 * SCALE` and not a bare 6 — the door gap is 9.3 real studs",
	string.find(body, "Width = 6 %* SCALE") ~= nil,
	string.match(body, "Width = [^,\n]*") or "no Width"
)

--[[
	THE AXIS CONVENTION, PINNED AGAINST `building()`'S OWN. An E or W door sits in a wall running
	along Z, so the opening's width runs along Z, which is yaw 90; N and S are yaw 0. `building()`
	writes `yaw = if nx ~= 0 then math.rad(90) else 0` on exactly that reading.
]]
check(
	"Yaw is 90 for E/W and 0 otherwise",
	string.find(body, 'Yaw = if side == "E" or side == "W" then 90 else 0', 1, true) ~= nil,
	string.match(body, "Yaw = [^,\n]*") or "no Yaw"
)

--------------------------------------------------------------------------------
-- 2. THE KUBO TABLE, re-parsed here rather than shared. `barrio-interiors` parses it too, and a
--    shared helper between two suites is one more thing that can be wrong in one place.
--------------------------------------------------------------------------------

type Kubo = { Name: string, X: number, Z: number, Doors: { [string]: boolean } }

local kuboBlock = string.match(builder, "local KUBO: { KuboSpec } = {(.-)\n}")

check("the builder declares a KUBO table", kuboBlock ~= nil)

if kuboBlock == nil then
	error(`{failures + 1} barrio-doorways assertion(s) failed`, 0)
end

local kubos: { Kubo } = {}

for line in string.gmatch(kuboBlock :: string, "[^\n]+") do
	local name, x, z, doors = string.match(
		line,
		'{ Name = "([%w_]+)", X = (%-?%d+), Z = (%-?%d+), Doors = {(.-)}, Enterable = %a+ }'
	)

	if name ~= nil then
		local doorSet: { [string]: boolean } = {}

		for side in string.gmatch(doors :: string, "(%u) = true") do
			doorSet[side] = true
		end

		table.insert(
			kubos,
			{ Name = name, X = tonumber(x) :: number, Z = tonumber(z) :: number, Doors = doorSet }
		)
	end
end

check("all seven kubo parse out of the KUBO table", #kubos == 7, `{#kubos} parsed`)

--------------------------------------------------------------------------------
-- 3. THE KUBO LOOP'S OFFSETS, reconciled against the `building()` call directly above them.
--------------------------------------------------------------------------------

--[[
	THE HALF-EXTENTS ARE READ FROM THE CALL, NOT ASSUMED. `building()` takes `w` then `d` and
	computes `hw, hd = w / 2, d / 2`, so a kubo built 24 x 20 has half-extents 12 and 10. If the call
	is ever re-sized, this suite fails rather than leaving nine pads offset from nine doorways.
]]
local kuboW = tonumber(
	string.match(builder, "for index, kubo in KUBO do.-building%(.-kubo%.Z,%s*(%d+),") or ""
)
local kuboD = tonumber(
	string.match(builder, "for index, kubo in KUBO do.-building%(.-kubo%.Z,%s*%d+,%s*(%d+),") or ""
)

check("the kubo building() call's width parses", kuboW ~= nil, `{kuboW}`)
check("the kubo building() call's depth parses", kuboD ~= nil, `{kuboD}`)

local kuboHalfW = (kuboW :: number) / 2
local kuboHalfD = (kuboD :: number) / 2

local loopBlock = string.match(builder, "V09%. ONE `Doorway` PAD PER DOOR(.-)\n\tend")

check("the KUBO loop emits doorway pads", loopBlock ~= nil)

if loopBlock ~= nil then
	local block = loopBlock :: string

	-- PLAIN FIND, NOT A PATTERN. The offsets are negated in the source (`then -12`), and `-` is a
	-- pattern quantifier — a pattern match here silently succeeds against the wrong text or fails
	-- against the right text, which is how a suite ends up asserting nothing.
	check(
		`the loop's E/W offset is the call's half-width ({kuboHalfW})`,
		string.find(block, `then {kuboHalfW} elseif side == "W" then -{kuboHalfW}`, 1, true) ~= nil,
		string.match(block, "local dx = [^\n]*") or "no dx"
	)

	check(
		`the loop's N/S offset is the call's half-depth ({kuboHalfD})`,
		string.find(block, `then {kuboHalfD} elseif side == "N" then -{kuboHalfD}`, 1, true) ~= nil,
		string.match(block, "local dz = [^\n]*") or "no dz"
	)

	--[[
		THE SIGNS ARE `building()`'S. It writes `nz = if tag == "S" then 1 elseif tag == "N" then -1`
		and `nx = if tag == "E" then 1 elseif tag == "W" then -1`. Inverting either pair puts every
		pad on the opposite face of the house from its door — a barrier in a solid wall.
	]]
	check(
		"E is +X and W is -X, matching building()",
		string.find(block, '"E" then ' .. kuboHalfW) ~= nil
	)
	check(
		"S is +Z and N is -Z, matching building()",
		string.find(block, '"S" then ' .. kuboHalfD) ~= nil
	)

	-- The pad must be driven off the door set, or a sealed face gets a barrier nobody can walk through.
	check(
		"the loop is gated on kubo.Doors[side]",
		string.find(block, "if kubo.Doors[side] then", 1, true) ~= nil
	)
end

--------------------------------------------------------------------------------
-- 4. THE CHAPEL'S TWO, reconciled against its own `building()` call.
--------------------------------------------------------------------------------

local chapelCall = string.match(
	builder,
	'local chapel = building%("Chapel", (%-?%d+), (%-?%d+), (%d+), (%d+),.-{(.-)}'
)

check("the chapel's building() call parses", chapelCall ~= nil)

local cx, cz, cw, cd, cdoors = string.match(
	builder,
	'local chapel = building%("Chapel", (%-?%d+), (%-?%d+), (%d+), (%d+),.-{(.-)}'
)

if cx ~= nil then
	local x = tonumber(cx) :: number
	local z = tonumber(cz) :: number
	local halfW = (tonumber(cw) :: number) / 2
	local halfD = (tonumber(cd) :: number) / 2

	local doorSet: { [string]: boolean } = {}

	for side in string.gmatch(cdoors :: string, "(%u) = true") do
		doorSet[side] = true
	end

	check("the chapel has a south door", doorSet.S == true)
	check("the chapel has an east door", doorSet.E == true)

	--[[
		THE TWO CALLS ARE MATCHED AS WRITTEN — `-152 + 18` rather than `-134` — because the sum is
		what shows a reader that the offset IS the half-extent. Pinning the spelling is what keeps
		the two literals reconcilable at all; a collapsed `-134` would parse and would have lost the
		only evidence that it came from `d / 2`.
	]]
	check(
		`the chapel's S pad sits at its own half-depth ({halfD})`,
		string.find(builder, `doorway("Chapel", "S", {x}, {z} + {halfD}, chapel)`, 1, true) ~= nil,
		string.match(builder, 'doorway%("Chapel", "S"[^\n]*') or "no S pad"
	)

	check(
		`the chapel's E pad sits at its own half-width ({halfW})`,
		string.find(builder, `doorway("Chapel", "E", {x} + {halfW}, {z}, chapel)`, 1, true) ~= nil,
		string.match(builder, 'doorway%("Chapel", "E"[^\n]*') or "no E pad"
	)
end

--------------------------------------------------------------------------------
-- 5. THE COUNT. Every door in the table, plus the chapel's two, against the receipt's literal.
--------------------------------------------------------------------------------

local implied = 2 -- the chapel's

for _, kubo in kubos do
	for _ in kubo.Doors do
		implied += 1
	end
end

check(`the KUBO table and the chapel imply 9 doorways`, implied == 9, `{implied} implied`)

--[[
	THE RECEIPT'S LITERAL IS RECONCILED AGAINST THE TABLE rather than read as gospel. The builder
	cannot `require` Config at build time — it runs in Studio's command bar — so the 9 is hand-typed,
	and a hand-typed count that nothing checks is how a doorway goes missing quietly.
]]
local receipt = tonumber(string.match(builder, 'count%("Doorway"%) == (%d+)') or "")

check("the builder asserts a Doorway count in its receipt", receipt ~= nil)

check(
	"the receipt's Doorway count equals what the table implies",
	receipt == implied,
	`receipt={receipt}, implied={implied}`
)

--[[
	ASSERTED, NOT PRINTED. A missing doorway's player-visible symptom is "I pressed the key and
	nothing happened", which is indistinguishable from bawang not being implemented yet — so the
	build must fail rather than print a line nobody reads.
]]
check(
	"the Doorway count is an assert() rather than a print",
	string.find(builder, 'assert(\n\tcount("Doorway") == 9,', 1, true) ~= nil
)

if failures > 0 then
	error(`{failures} barrio-doorways assertion(s) failed`, 0)
end

print(`  PASS  barrio-doorways: {checked} assertions over helper x KUBO x chapel x receipt`)
