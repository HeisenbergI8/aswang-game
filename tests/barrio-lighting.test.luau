--!strict
--[[
	THE LIGHTING SPLIT — which properties the builder owns and which the runtime does.

	THIS IS THE TRAP THE PLAN'S BRIEF GOT BACKWARDS, and the correction is worth stating. The concern
	going in was that `SkyController` OVERWRITES the builder's lighting. It does not. It reads five
	properties ONCE at startup — Brightness, FogEnd, Ambient, OutdoorAmbient and the Atmosphere's
	Density — and treats whatever it finds as the baseline it lerps toward dawn and back. `Config.Sky`
	holds only multipliers over that baseline.

	So retuning those five in the builder is correct and supported, and this suite's job is not to stop
	it. Its job is to make sure BOTH halves keep being authored: the five captured ones, so the
	controller has a baseline to lerp from, and the ones nothing owns at runtime, which are the safest
	realism budget in the plan precisely because no controller will argue with them.

	`ClockTime` IS THE EXCEPTION AND IT IS ASSERTED, NOT TUNED. The builder's 0 is what a map author
	sees in Studio; the ROUND owns the real value through `Config.Sky.StartClockTime`. Raising it to
	make Studio look nicer changes nothing a player sees and makes the builder disagree with the
	runtime for no gain.
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
local controller = fs.readFile("src/client/Controllers/SkyController.luau")

--[[
	THE FIVE THE CONTROLLER CAPTURES. If the builder stops authoring one, the controller's baseline
	becomes whatever the place file happened to hold — which is not in git, so the map's night would
	depend on an artefact nobody can review.
]]
for _, captured in { "Brightness", "FogEnd", "Ambient", "OutdoorAmbient" } do
	check(
		`the builder authors Lighting.{captured}`,
		string.find(builder, `Lighting.{captured} = `, 1, true) ~= nil,
		"SkyController lerps from this baseline; unauthored, it comes from the ungitted place file"
	)
	check(
		`SkyController still reads {captured}`,
		string.find(controller, captured, 1, true) ~= nil,
		"the controller stopped reading it, so the builder's value may no longer mean what this assumes"
	)
end

check(
	"the builder authors the Atmosphere's Density",
	string.find(builder, "atmosphere.Density = ", 1, true) ~= nil
)

--[[
	THE ONES NOTHING OWNS. These have no runtime owner at all, so they are the builder's outright.
	A later edit moving one of these INTO the controller would silently make the builder's value dead.
]]
for _, owned in
	{
		"Lighting.EnvironmentDiffuseScale",
		"Lighting.EnvironmentSpecularScale",
		"Lighting.GlobalShadows",
		"Lighting.FogColor",
		"atmosphere.Color",
		"atmosphere.Decay",
		"atmosphere.Glare",
		"atmosphere.Haze",
	}
do
	check(`the builder authors {owned}`, string.find(builder, `{owned} = `, 1, true) ~= nil)

	--[[
		"UNOWNED" MEANS THE CONTROLLER NEVER ASSIGNS IT, and the test for that has to be an ASSIGNMENT
		rather than a mention. A first version stripped the prefix and searched for the bare property
		name, so `atmosphere.Color` became `Color` and matched `Color3` in the controller's own imports
		— reporting the split as broken when nothing had moved.

		The controller names the Atmosphere `air`, so both spellings of a write are checked.
	]]
	local property = string.gsub(owned, "^%a+%.", "")

	check(
		`{owned} is still unowned by SkyController`,
		string.find(controller, `Lighting.{property} = `, 1, true) == nil
			and string.find(controller, `air.{property} = `, 1, true) == nil,
		"the controller now writes this, so the builder's value is dead and the split has moved"
	)
end

-- ClockTime belongs to the round, not to the art pass.
check(
	"the builder leaves ClockTime at 0",
	string.find(builder, "Lighting.ClockTime = 0", 1, true) ~= nil,
	"the round owns the real value through Config.Sky.StartClockTime"
)

--[[
	AMBIENT MUST NOT BE RAISED TO 'FIX' A DARK MAP. §5: "total darkness is not scary, it's just
	confusing. Fear comes from PARTIAL information." The answer to a too-dark barrio is more lanterns
	spaced further apart — raising Ambient flattens the whole map at once and erases the deep shadow
	that IS the look of a rural barrio at night. This pins the ceiling rather than the value.
]]
local r, g, b = string.match(builder, "Lighting.Ambient = Color3.fromRGB%((%d+), (%d+), (%d+)%)")

check("Lighting.Ambient is authored as an RGB triple", r ~= nil)

if r then
	local brightest = math.max(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)

	check(
		"Lighting.Ambient stays dark enough for shadow to exist",
		brightest <= 30,
		`brightest channel is {brightest}; above ~30 the map flattens and the shadow §5 depends on is gone`
	)
end

if failures > 0 then
	error(`{failures} barrio-lighting assertion(s) failed`, 0)
end

print(`  PASS  barrio-lighting: {checked} assertions over the builder/runtime lighting split`)
