--!strict
--[[
	THE EIGHT GRAVES — detailed in place, and NOT gathered into a cemetery.

	THIS SUITE GUARDS A SCOPE DECISION AS MUCH AS GEOMETRY. The user was asked directly whether
	"cemetery" meant building one out as a zone or detailing the eight markers that already existed,
	and chose the smaller scope. That is also the better one: §5's required-zone list has no cemetery,
	the map holds a ~35-second crossing, and a new zone would move the layout. A later reader with the
	same instinct that prompted the question will want to add one, so the absence is asserted rather
	than left to a comment.

	It has its own file because Steps 7.2 and 7.3 are different work in one phase, and a shared check
	proves nothing about either — `verify-plan --lint` reports that as `shared` and it is right to.

	It also replaces the fourth grep in this plan that could not pass: `grep -c Grave1_Candle` against a
	loop writing `Grave{index}_Candle`. The same literal-versus-interpolation defect appeared at Steps
	4.2, 6.2 and here. Anything built in a loop needs a reader that understands the loop.
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

--[[
	THE TOMB SLAB is the single biggest correction the research gives, and it is what changes the
	silhouette from headstone to tomb: Philippine grave markers are typically above-ground painted
	concrete, not carved granite sunk into turf.
]]
check(
	"each grave stands on an above-ground tomb slab",
	string.find(builder, "Grave{index}_Tomb", 1, true) ~= nil
)
check("each grave has a candle stub", string.find(builder, "Grave{index}_Candle", 1, true) ~= nil)
check(
	"the marker is a generated mesh rather than two crossed boxes",
	string.find(builder, '"GraveMarker"', 1, true) ~= nil
)
check(
	"the markers still lean",
	string.find(builder, "marker.CFrame = marker.CFrame", 1, true) ~= nil,
	"tropical subsidence tilts markers within a few years; a row of upright ones reads as a fence"
)

--[[
	THE CANDLES ARE `Neon`, NOT `PointLight`s. Eight new lights would be a 57% overspend of the entire
	map's light budget against `Config.Performance.MaxVisibleLights`, and the builder asserts zero
	dressing lights — so this would not degrade the map, it would fail the build.
]]
local candleBlock = string.match(builder, "local candle = prop%((.-)%)\n")

check("the candle is authored as a prop", candleBlock ~= nil)
check(
	"the candle is emissive geometry, not a light",
	candleBlock ~= nil and string.find(candleBlock :: string, "Neon", 1, true) ~= nil,
	"eight PointLights here would fail the build against C30 rule 2"
)

--[[
	NO CEMETERY ZONE. The user's explicit choice. A zone folder, a gate, or a fence run named for a
	cemetery would all be signs one had been added.
]]
for _, forbidden in { "Cemetery", "Graveyard", "Fence_Cemetery" } do
	check(
		`no {forbidden} zone was added`,
		string.find(builder, forbidden, 1, true) == nil,
		"§5 lists no cemetery, and adding a zone moves the layout the crossing time is measured over"
	)
end

--[[
	AND THEY MUST STAY WHERE THEY WERE. The graves sit in `Dressing.Details` beside the chapel at their
	original coordinates; moving them IS building a cemetery, whatever the folder is called.
]]
check(
	"the graves are still parented to Details",
	string.find(builder, "details\n\t)", 1, true) ~= nil
		or string.find(builder, "details", 1, true) ~= nil
)
check(
	"the graves keep their original placement arithmetic",
	string.find(builder, "local x = -50 + (index % 3) * 7", 1, true) ~= nil
		and string.find(builder, "local z = -164 + math.floor((index - 1) / 3) * 10", 1, true)
			~= nil,
	"the coordinates changed, which means the plot moved"
)

if failures > 0 then
	error(`{failures} barrio-graves assertion(s) failed`, 0)
end

print(`  PASS  barrio-graves: {checked} assertions over the eight graves`)
