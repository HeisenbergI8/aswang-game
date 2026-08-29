--!strict
--[[
	THE FIFTEEN SEARCHABLE CONTAINERS, AND THE SPACING RULE THAT MAKES THEM FIFTEEN.

	`SearchService.discoverPool` reads the `SearchContainer` tag and evaluates the pool against
	`Config.Search.ContainerCount`. Before Phase 2 the builder emitted ZERO of them while Config asked
	for fifteen — searching is the whole of v2.0 (§4.4) and the map had nothing to search. Nothing in
	the repo could have told you: the builder is outside `src/`, so it is behind no other gate, and the
	map it builds is not in git.

	Lune has no `game`, so this reads the builder as TEXT and parses the table. That is weaker than
	running it and stronger than nothing — it catches the faults that actually happen to a hand-edited
	coordinate list: a dropped row, a duplicated name, two containers close enough to be one stop.

	THE SPACING RULE IS §5's, MADE ARITHMETIC. "No two are close enough that one search covers two."
	The distance that makes that concrete is `Config.Search.RangeStuds` — the radius you must be inside
	to start a search AND stay inside for all six seconds. Two containers nearer than 2 x that share a
	standing spot, so the pair is one container wearing two names.
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

--[[
	READ THE TWO NUMBERS FROM `Config.luau` RATHER THAN RESTATING THEM.

	`barrio.luau` runs in Studio's command bar and cannot reliably `require` a Rojo-synced module at
	build time, so its counts are hand-copied literals. This is the reconciliation that makes copying
	them safe: if Config moves and the builder does not, this suite fails instead of the map going
	quietly short. The two-tab anchor pins each key to its own table — `RangeStuds` would otherwise
	also match `PickupRangeStuds` and `PresenceRangeStuds`.
]]
local function configNumber(key: string): number
	local raw = string.match(config, `\n\t\t{key} = (%d+),`)

	assert(
		raw,
		`Config.luau has no two-tab '{key} = <number>,' — the key was renamed or re-nested`
	)

	return tonumber(raw) :: number
end

local containerCount = configNumber("ContainerCount")
local rangeStuds = configNumber("RangeStuds")

-- The block, isolated, so a stray `{ Name = ... }` elsewhere in a 2200-line file cannot inflate it.
local block = string.match(builder, "local SEARCH_CONTAINERS = {(.-)\n}")

check("the builder declares a SEARCH_CONTAINERS table", block ~= nil)

if not block then
	error("1 barrio-contract assertion(s) failed", 0)
end

type Container = { Name: string, X: number, Z: number }

local containers: { Container } = {}

for name, x, z in
	string.gmatch(block :: string, '{ Name = "([%w_]+)", X = (%-?%d+), Z = (%-?%d+) }')
do
	table.insert(containers, { Name = name, X = tonumber(x) :: number, Z = tonumber(z) :: number })
end

check(
	`the builder sites exactly {containerCount} containers`,
	#containers == containerCount,
	`{#containers} parsed, Config.Search.ContainerCount says {containerCount}`
)

--[[
	UNIQUE NAMES ARE A HARD REQUIREMENT, NOT TIDINESS. `discoverPool` keys the pool by Name and reports
	duplicates as skipped, so two parts called `Container_Kubo` are ONE container and a silent short
	pool — the map and Config disagree and only a warning in the output says so.
]]
local seen: { [string]: boolean } = {}
local duplicates = 0

for _, container in containers do
	if seen[container.Name] then
		duplicates += 1
	end

	seen[container.Name] = true
end

check("every container name is unique", duplicates == 0, `{duplicates} duplicate name(s)`)

check(
	"every container name carries the Container_ prefix",
	(function()
		for _, container in containers do
			if not string.match(container.Name, "^Container_") then
				return false
			end
		end

		return true
	end)(),
	"a name outside the prefix is invisible when grepping the map contract"
)

-- §5's spread rule, as arithmetic. Reported with the offending pair, because "spacing failed" without
-- a pair is a message you have to re-derive by hand.
local minimum = rangeStuds * 2
local closest = math.huge
local closestPair = ""

for i = 1, #containers do
	for j = i + 1, #containers do
		local a, b = containers[i], containers[j]
		local distance = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)

		if distance < closest then
			closest = distance
			closestPair = `{a.Name} <-> {b.Name}`
		end
	end
end

check(
	`no two containers are within {minimum} studs of each other`,
	closest > minimum,
	`closest pair is {closestPair} at {string.format("%.1f", closest)} studs, needs > {minimum}`
)

--[[
	§5 asks for "at least 5 enterable" houses, and the containers are the reason to enter one. If the
	kubo carry fewer than five between them, the houses are scenery and searching happens entirely in
	the open — which removes the whole risk shape §4.4 is built on.
]]
local inKubo = 0

for _, container in containers do
	if string.match(container.Name, "^Container_Kubo") then
		inKubo += 1
	end
end

check(
	"at least five containers sit inside kubo",
	inKubo >= 5,
	`{inKubo} kubo container(s) — §5 wants at least 5 enterable houses and this is the reason to enter`
)

--[[
	EVERY `Container_Kubo*` MUST SIT AT THE KUBO IT IS NAMED AFTER.

	`Container_KuboN_Drum` was authored at (0, -104) while `Kubo_N` stands at (35, -75) — open ground
	forty studs from the house whose name it carried. `measure.luau` passed it, correctly: the part was
	perfectly reachable. Nothing was wrong except the only thing a reader would ever check, which is
	that the name means what it says. A container advertised as being inside a house, sitting outside
	it, is a player walking into an empty room.
]]
local kuboBlock = string.match(builder, "local KUBO: { KuboSpec } = {(.-)\n}")

check("the builder declares a KUBO table", kuboBlock ~= nil)

if kuboBlock then
	local kubos: { [string]: { X: number, Z: number, Enterable: boolean } } = {}
	local enterable = 0

	for name, x, z in
		string.gmatch(kuboBlock :: string, '{ Name = "([%w_]+)", X = (%-?%d+), Z = (%-?%d+)')
	do
		local entry = string.match(kuboBlock :: string, `Name = "{name}".-\n`) or ""

		kubos[name] = {
			X = tonumber(x) :: number,
			Z = tonumber(z) :: number,
			Enterable = string.find(entry, "Enterable = true", 1, true) ~= nil,
		}

		if kubos[name].Enterable then
			enterable += 1
		end
	end

	--[[
		§5, RAISED BY THE v2.0 REWRITE: "6–8 bahay kubo / small houses, at least 5 enterable — up from
		3, because searching is now the whole game and the containers live inside them." The greybox
		was built to the v1.3 number and stayed there; this is the assertion that stops it drifting
		back the next time a house is resealed to fix a sightline.
	]]
	check(
		"at least five kubo are enterable",
		enterable >= 5,
		`{enterable} enterable — §5 wants at least 5, and a sealed house is a container nobody reaches`
	)

	for _, container in containers do
		--[[
			`Container_KuboNW_Chest` names its house as `KuboNW`; the KUBO table keys it as `Kubo_NW`.
			The underscore has to be reinserted or every lookup below misses and the loop silently
			checks nothing — which is exactly what the first version of this block did, passing with
			eight assertions where eighteen were intended. A check that quietly matches zero rows is
			worse than no check, because the count still goes up.
		]]
		local suffix = string.match(container.Name, "^Container_Kubo(%u+)_")
		local kubo = if suffix then `Kubo_{suffix}` else nil

		if kubo and kubos[kubo] then
			local spec = kubos[kubo]

			check(
				`{container.Name} sits at {kubo}`,
				container.X == spec.X and container.Z == spec.Z,
				`container at ({container.X}, {container.Z}), {kubo} at ({spec.X}, {spec.Z})`
			)
			check(
				`{kubo} is enterable, so {container.Name} can be reached`,
				spec.Enterable,
				`{kubo} has no door — measure.luau will report the container unreachable and every loop test will fail on it`
			)
		end
	end
end

if failures > 0 then
	error(`{failures} barrio-contract assertion(s) failed`, 0)
end

print(`  PASS  barrio-contract: {checked} assertions over {#containers} containers`)
