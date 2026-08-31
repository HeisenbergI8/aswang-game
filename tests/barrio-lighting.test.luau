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
	confusing. Fear comes from PARTIAL information." Raising Ambient flattens the whole map at once and
	erases the deep shadow that IS the look of a rural barrio at night.

	THE CEILING MOVED FROM 30 TO 55, AND THE REASON IS AN ENGINE CHANGE RATHER THAN A CONCESSION.

	This check was written when the fill came from `EnvironmentDiffuseScale`, so Ambient could be
	pinned very low and something else could carry the legibility. This place now runs Unified Lighting
	(`RBX_LightingTechnologyUnifiedMigration`), where `EnvironmentDiffuseScale` IS INERT — measured:
	raising it 0.12 -> 0.35 changed nothing in a captured frame. With that lever dead and Ambient at
	15, every unlit surface rendered pure black: not a dark house, a house-shaped hole, and a player
	standing in the plaza was a black cutout. That was reported from a screenshot.

	So the old ceiling no longer protected the property it names — it forbade the only remaining fix for
	it. 40 was chosen by capturing the PLAZA at successive values and stopping at the last one where
	the lantern pools and the lit windows were still clearly the brightest things in frame and the
	stretches between them were still dark enough to walk into blind.

	AND THE SECOND CHECK IS THE ONE THAT ACTUALLY GUARDS THE LOOK. A number alone cannot see flatness;
	what makes a night read as lit-from-somewhere is that the sky fill EXCEEDS the flat ambient. Pinning
	`Ambient < OutdoorAmbient` keeps that ordering true whatever either value becomes, which is a
	property rather than a threshold, and it is the half of this to defend if the numbers move again.
]]
local r, g, b = string.match(builder, "Lighting.Ambient = Color3.fromRGB%((%d+), (%d+), (%d+)%)")
local outR, outG, outB =
	string.match(builder, "Lighting.OutdoorAmbient = Color3.fromRGB%((%d+), (%d+), (%d+)%)")

check("Lighting.Ambient is authored as an RGB triple", r ~= nil)
check("Lighting.OutdoorAmbient is authored as an RGB triple", outR ~= nil)

if r then
	local brightest = math.max(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)

	check(
		"Lighting.Ambient stays dark enough for shadow to exist",
		brightest <= 55,
		`brightest channel is {brightest}; above ~55 the map flattens and the shadow §5 depends on is gone`
	)
end

if r and outR then
	local ambient = math.max(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)
	local outdoor =
		math.max(tonumber(outR) :: number, tonumber(outG) :: number, tonumber(outB) :: number)

	check(
		"the flat ambient stays below the sky fill, so the night still reads as lit from somewhere",
		ambient < outdoor,
		`Ambient {ambient} is not below OutdoorAmbient {outdoor} — at or above it every surface takes `
			.. `the same light from every direction, which is flatness by definition`
	)
end

--[[
	THE LANTERN MIX — TWO ERAS, AND ROUGHLY ONE IN FOUR DARK.

	These are gameplay facts, not decoration. A dark stretch of street is §5's "fear comes from PARTIAL
	information" made physical, and a dead fixture costs NO light slot — which is the whole reason the
	ratio exists rather than being an aesthetic. Someone lighting all twelve to "fix" a dark map would
	be undoing that with every gate still green, so it is pinned here.

	PARSED FROM THE PLACEMENT TABLE, which is where the decision is written down. `lantern()` itself
	only obeys.
]]
local lanternBlock = string.match(builder, "for index, at in\n\t{(.-)\n\t}\ndo\n\tlantern")

check("the builder declares a lantern placement table", lanternBlock ~= nil)

if lanternBlock ~= nil then
	local total, dark, cobra, wedge = 0, 0, 0, 0

	for isCobra, isLit in string.gmatch(lanternBlock :: string, "Cobra = (%a+), Lit = (%a+)") do
		total += 1

		if isLit == "false" then
			dark += 1
		end

		if isCobra == "true" then
			cobra += 1
		else
			wedge += 1
		end
	end

	check("twelve lanterns are sited", total == 12, `{total} parsed`)
	check(
		"roughly one lantern in four is dark",
		dark >= 2 and dark <= 4,
		`{dark} of {total} dark — none is a lit-up town, half is a map nobody can navigate`
	)
	check(
		"both fixture eras are present",
		cobra >= 3 and wedge >= 3,
		`{cobra} cobra, {wedge} wedge — one era alone reads as a single lighting pass, not a barangay`
	)

	--[[
		AND THE COUNT THE CONTRACT TABLE PROMISES. `AmbientService`'s header and the builder's own
		contract both name a `MapLight` total, and a lantern going dark changes it. A header that
		names a number the file no longer produces is the most expensive kind of stale comment here,
		because it is the only description of the contract anyone reads.
	]]
	local promised = string.match(builder, "MapLight     ×(%d+)")

	check("the header names a MapLight count", promised ~= nil)

	if promised ~= nil then
		-- 9 lit lanterns + the trial corner's + the chapel candle glow.
		check(
			"the header's MapLight count matches the lit lanterns plus the two fixed ones",
			tonumber(promised) == (total - dark) + 2,
			`header says {promised}, the table implies {(total - dark) + 2}`
		)
	end
end

if failures > 0 then
	error(`{failures} barrio-lighting assertion(s) failed`, 0)
end

print(`  PASS  barrio-lighting: {checked} assertions over the builder/runtime lighting split`)
