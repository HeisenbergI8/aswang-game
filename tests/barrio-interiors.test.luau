--!strict
--[[
	tests/barrio-interiors.test.luau

	SEVEN KUBO INTERIORS, AND WHY A GREP COULD NOT CHECK THEM.

	The kit is a helper called in a loop — `interior(kubo.Name, ...)` writes `{name}_Banggera` by
	interpolation — and a literal `grep -c Kubo_NW_Banggera` cannot match an interpolation. The realism
	pass wrote four such Verify lines, named the trap in its own plan, and fell into it anyway. So
	anything built in a loop is checked by a suite that parses the SOURCE, or it is not checked.

	WHAT THIS SUITE IS ACTUALLY DEFENDING, in order of how silently each fails:

	  1. AN INTERIOR SITED AWAY FROM ITS HOUSE. The exact class of bug that put
	     `Container_KuboN_Drum` forty studs outside `Kubo_N` — coordinates typed twice and drifting
	     apart. Every interior's coordinates are compared against the `KUBO` table rather than trusted.
	  2. A RE-SEALED HOUSE. `Enterable = true` with an empty `Doors` set is a house with an interior
	     nobody can reach, and nothing in the game says so.
	  3. TWO OPPOSED DOORS. This is the invariant `references/sightline-compensation.md` rests its
	     whole argument on: a door is a gap in ONE face, so the house still occludes. Two opposed doors
	     cut a real window through it and the argument silently stops being true.
	  4. A CONTAINER IN AN UNENTERABLE HOUSE. Searching is the whole of v2.0; a container behind a
	     sealed wall is a fifteenth of the game that does not exist.
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
	THE `KUBO` TABLE IS THE SOURCE OF TRUTH and everything else is compared against it. Parsed rather
	than duplicated, because a duplicated table is one more copy to drift.
]]
type Kubo = { Name: string, X: number, Z: number, Doors: { [string]: boolean }, Enterable: boolean }

local kuboBlock = string.match(builder, "local KUBO: { KuboSpec } = {(.-)\n}")

check("the builder declares a KUBO table", kuboBlock ~= nil)

if kuboBlock == nil then
	error("1 barrio-interiors assertion(s) failed", 0)
end

local kubos: { Kubo } = {}

for line in string.gmatch(kuboBlock :: string, "[^\n]+") do
	local name, x, z, doors, enterable = string.match(
		line,
		'{ Name = "([%w_]+)", X = (%-?%d+), Z = (%-?%d+), Doors = {(.-)}, Enterable = (%a+) }'
	)

	if name ~= nil then
		local doorSet: { [string]: boolean } = {}

		for side in string.gmatch(doors :: string, "(%u) = true") do
			doorSet[side] = true
		end

		table.insert(kubos, {
			Name = name,
			X = tonumber(x) :: number,
			Z = tonumber(z) :: number,
			Doors = doorSet,
			Enterable = enterable == "true",
		})
	end
end

check("all seven kubo parse out of the KUBO table", #kubos == 7, `{#kubos} parsed`)

--[[
	§5 ASKS FOR AT LEAST FIVE ENTERABLE KUBO, raised from three by the v2.0 rewrite because the search
	containers live inside them. Asserted as a floor rather than as an equality: opening the last two
	is this phase's choice, and re-sealing one later is a decision, not a regression.
]]
local enterable = 0

for _, kubo in kubos do
	if kubo.Enterable then
		enterable += 1
	end
end

check(`at least 5 kubo are enterable (§5)`, enterable >= 5, `{enterable} enterable`)

-- 2. A house marked enterable with no door is a room nobody can reach.
for _, kubo in kubos do
	if not kubo.Enterable then
		continue
	end

	local doorCount = 0

	for _ in kubo.Doors do
		doorCount += 1
	end

	check(
		`{kubo.Name} is enterable and has a door`,
		doorCount > 0,
		"Enterable with an empty Doors set"
	)
end

--[[
	3. NO KUBO HAS TWO OPPOSED DOORS.

	`references/sightline-compensation.md` argues that opening the last two houses costs no occlusion,
	because `building()` cuts a door as a gap between two wall segments in ONE face and the mass of the
	house is what blocks a line. That argument holds only while no house has a door on both ends of an
	axis. This is the assertion that stops someone invalidating it by adding a convenient second door.
]]
local OPPOSITE: { [string]: string } = { N = "S", S = "N", E = "W", W = "E" }

for _, kubo in kubos do
	for side in kubo.Doors do
		local other = OPPOSITE[side]

		check(
			`{kubo.Name} has no door opposite its {side} door`,
			other == nil or kubo.Doors[other] ~= true,
			`{side} and {other} — this cuts a sightline through the house`
		)
	end
end

--[[
	1. EVERY KUBO HAS AN INTERIOR, AT THE SAME COORDINATES ITS HOUSE IS AT.

	The interiors are declared in their own table so this can compare two lists rather than trust one.
	`Container_KuboN_Drum` was authored forty studs from `Kubo_N` by exactly this mistake, and nothing
	reported it until a human walked there.
]]
local interiorBlock = string.match(builder, "local KUBO_INTERIORS = {(.-)\n}")

check("the builder declares a KUBO_INTERIORS table", interiorBlock ~= nil)

if interiorBlock ~= nil then
	type Interior = { Name: string, X: number, Z: number, Tier: string }

	local interiors: { Interior } = {}

	for name, x, z, tier in
		string.gmatch(
			interiorBlock :: string,
			'{ Name = "([%w_]+)", X = (%-?%d+), Z = (%-?%d+), Tier = "(%a+)" }'
		)
	do
		table.insert(
			interiors,
			{ Name = name, X = tonumber(x) :: number, Z = tonumber(z) :: number, Tier = tier }
		)
	end

	check(
		`every kubo has an interior`,
		#interiors == #kubos,
		`{#interiors} interiors for {#kubos} kubo`
	)

	local byName: { [string]: Interior } = {}

	for _, entry in interiors do
		byName[entry.Name] = entry
	end

	for _, kubo in kubos do
		local entry = byName[kubo.Name]

		check(`{kubo.Name} has an interior`, entry ~= nil)

		if entry ~= nil then
			check(
				`{kubo.Name}'s interior is sited at its house`,
				entry.X == kubo.X and entry.Z == kubo.Z,
				`interior ({entry.X}, {entry.Z}) vs house ({kubo.X}, {kubo.Z})`
			)
			check(
				`{kubo.Name}'s interior names a known tier`,
				entry.Tier == "Sparse" or entry.Tier == "Full" or entry.Tier == "Rich",
				`Tier = {entry.Tier}`
			)
		end
	end

	--[[
		THE TIERS ARE WHERE THE INSTANCE BUDGET IS REPAID, so at least one house must be sparse and
		at most one may be rich. Seven full interiors is the shape that quietly overspends §5's mobile
		budget, and seven rich ones is that twice over.
	]]
	local sparse, rich = 0, 0

	for _, entry in interiors do
		if entry.Tier == "Sparse" then
			sparse += 1
		elseif entry.Tier == "Rich" then
			rich += 1
		end
	end

	check("at least one interior is sparse", sparse >= 1, `{sparse} sparse`)
	check("at most one interior is rich", rich <= 1, `{rich} rich`)
end

--[[
	4. NO SEARCH CONTAINER IS SITED INSIDE A HOUSE NOBODY CAN ENTER.

	Searching is the whole of v2.0. A container behind a sealed wall is one fifteenth of the game
	silently missing, and `SearchService` would report a healthy pool of fifteen the whole time.

	MATCHED BY NAME rather than by coordinate: the containers are named `Container_KuboNW_Chest` and
	the houses `Kubo_NW`, so the house is recoverable from the container's own name — and a container
	named for a house it is not near is the OTHER bug, which `tests/barrio-contract.test.luau` already
	covers by distance.
]]
local containerBlock = string.match(builder, "local SEARCH_CONTAINERS = {(.-)\n}")

check("the builder declares a SEARCH_CONTAINERS table", containerBlock ~= nil)

if containerBlock ~= nil then
	local enterableByCompact: { [string]: boolean } = {}

	for _, kubo in kubos do
		-- `Kubo_NW` -> `KuboNW`, which is how the container names spell it.
		enterableByCompact[(string.gsub(kubo.Name, "_", ""))] = kubo.Enterable
	end

	local inKubo = 0

	for name in string.gmatch(containerBlock :: string, 'Name = "(Container_[%w_]+)"') do
		local house = string.match(name, "^Container_(Kubo%u+)_")

		if house ~= nil then
			inKubo += 1
			check(
				`{name} is inside an enterable house`,
				enterableByCompact[house] == true,
				`{house} is sealed, so this container cannot be reached`
			)
		end
	end

	check("at least one container is sited inside a kubo", inKubo > 0, `{inKubo} found`)
end

if failures > 0 then
	error(`{failures} barrio-interiors assertion(s) failed`, 0)
end

print(`  PASS  barrio-interiors: {checked} assertions over {#kubos} kubo`)
