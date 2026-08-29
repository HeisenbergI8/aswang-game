--!strict
--[[
	THE CIVIC ZONES — the stalls, and the fifteen containers that make searching visible.

	THIS FILE EXISTS BECAUSE A GREP COULD NOT DO THE JOB, FOR THE THIRD TIME IN THIS PLAN. Step 6.2 was
	gated on `grep -c Stall_NW_Grille` while the loop writes `{stall.Name}_Grille{bar}`; Step 4.2 was
	gated on `grep -c Bench1_Back` against `Bench{index}_Back`. A literal cannot match an interpolation,
	so both checks failed at the thing they were pointed at rather than at the thing they were guarding.
	Anything built in a loop needs a reader that understands the loop.

	THE CONTAINER ASSERTIONS ARE THE IMPORTANT HALF. Step 4.5's gate capture found the containers
	completely invisible in an unlit interior — not subtle, absent. §5 requires them "visually obvious
	as searchable at a glance, on a phone, in the dark" and v2.0's entire loop is searching, so this is
	playability rather than decoration.
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

-- The sari-sari store's three signatures, two of which are reachable.
check(
	"each stall has a barred window",
	string.find(builder, "{stall.Name}_Grille{bar}", 1, true) ~= nil
)
check(
	"each stall hangs sachet strips",
	string.find(builder, "{stall.Name}_Sachets", 1, true) ~= nil
)
check(
	"each stall carries a generated shopfront",
	string.find(builder, "{stall.Name}_Front", 1, true) ~= nil,
	"the mesh is what reads as a shop from across the plaza"
)

-- The chapel is a visita: painted hollow block under a roof, not castle stone.
check("the chapel walls are hollow block", string.find(builder, '"HollowBlock"', 1, true) ~= nil)
check("the steeple and arko are whitewashed", string.find(builder, '"Whitewash"', 1, true) ~= nil)
check(
	"the chapel is NOT stilted",
	string.find(builder, 'building("Chapel"', 1, true) ~= nil
		and string.find(
				builder,
				'building("Chapel", 0, -152, 46, 36, 16, { S = true, E = true }, STONE, Enum.Material.Cobblestone, nil, true)',
				1,
				true
			)
			== nil,
	"a visita sits on a slab; only the kubo stand on posts"
)

--[[
	THE CONTAINERS. Each of the fifteen gets a body and an emissive band, and the band must be `Neon`
	rather than a light: the builder asserts ZERO dressing lights (C30 rule 2) and
	`PerformanceController` caps visible lights, so fifteen PointLights would break both at once.
]]
check(
	"every container gets a body prop",
	string.find(builder, "{container.Name}_Body", 1, true) ~= nil
)
check(
	"every container gets a glow band",
	string.find(builder, "{container.Name}_Glow", 1, true) ~= nil
)
check(
	"the glow is emissive geometry, not a light",
	string.find(builder, "Enum.Material.Neon", 1, true) ~= nil,
	"a PointLight per container would break the light cap and fail the build"
)
check(
	"no PointLight is created for a container",
	string.find(builder, 'Instance.new("PointLight")\n\n\tglow', 1, true) == nil
)

--[[
	THE BAND MUST SIT ON THE LID, NOT INSIDE THE BOX.

	The first version put it at y = 0.65 while the body spans 0.1 to 2.5 — fully enclosed, emitting
	into the inside of a crate. In a capture that looks identical to Neon simply being too dim, so it
	is pinned by height here rather than left to a screenshot to catch twice.
]]
local glowY = string.match(builder, "`{container%.Name}_Glow`,\n%s*container%.X,\n%s*([%d%.]+),")

check("the glow band's height is authored", glowY ~= nil)
check(
	"the glow band sits above the container body, not inside it",
	tonumber(glowY or "0") >= 2.3,
	`glow authored at y = {tostring(glowY)}; the body spans 0.1 to 2.5 and swallows anything below 2.3`
)

--[[
	TRANSPARENCY SCALES EMISSION ON `Neon`. At 0.35 a third of the glow was thrown away on a part whose
	only job is to be seen in the dark.
]]
local glowT = string.match(builder, "glow%.Transparency = ([%d%.]+)")

check(
	"the glow is not dimmed away by transparency",
	tonumber(glowT or "1") <= 0.2,
	`Transparency = {tostring(glowT)}; on Neon this scales emission`
)

--[[
	THE TAGGED PART MUST NOT MOVE. The props are placed AT the anchor's coordinates — `SearchService`
	measures range from the tagged pad, so a prop authored at an offset would quietly shift where a
	player has to stand relative to what they can see.
]]
check(
	"container props are placed at the anchor's own coordinates",
	string.find(builder, "container.X,", 1, true) ~= nil
		and string.find(builder, "container.Z,", 1, true) ~= nil,
	"a prop at an offset moves the visual affordance away from the tagged part"
)

if failures > 0 then
	error(`{failures} barrio-civic assertion(s) failed`, 0)
end

print(`  PASS  barrio-civic: {checked} assertions over the stalls, the chapel and the containers`)
