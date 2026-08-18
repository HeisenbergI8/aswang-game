--!strict
--[[
	SkyCycle — the round clock, as a sky. (C28, Appendix C.3)

		progressFor(input) -> number          -- 0..1, how far through the night the round is
		frameFor(progress, params) -> Frame   -- what Lighting should read at that progress

	WHY THIS IS THE ONE THING C28 ACTUALLY BUILDS
	----------------------------------------------
	Appendix C.3 is a teardown of the competitor's "dynamic sunset-to-night" and the instruction is to
	steal it and point it at something: "the sky visibly progressing toward sunrise IS the countdown —
	a diegetic clock, no UI needed, and it raises tension for free". A HUD timer tells you the round is
	ending; a sky tells you while you are looking at the thing that is chasing you.

	So this module is a MAPPING and nothing else: seconds left -> a number between 0 and 1 -> a set of
	Lighting values. It owns no state, holds no clock of its own and never decides when a round ends —
	`RoundService` owns the phase (§6.4) and this reads the snapshot everyone already receives.

	WHY IT IS PURE RATHER THAN SIX LINES INSIDE THE CONTROLLER
	----------------------------------------------------------
	Two properties are invisible until they break, and both are cheap to prove out here:

	  · MONOTONICITY. The sky must never go backwards while a round runs. A brightening sky that dips
	    reads as a bug in the world rather than in the code, and nothing on screen would name it.
	  · THE NIGHT BASELINE IS EXACTLY RECOVERABLE. `frameFor(0, params)` returns the captured night
	    values UNCHANGED — not "close to". That is the C04 lesson restated: MonsterService's revert
	    once restored hardcoded defaults instead of captured state and permanently branded an
	    ex-Aswang. A lobby that comes back one shade warmer every round is the same bug, slower.

	NO `script.Parent` REQUIRES (tests/README.md), so no Types, no Enums, no Config. `RoundPhase` is
	re-declared — Luau unions are structural, so this and `Types.RoundPhase` are the same type — and
	every tunable arrives as a parameter. There are also NO Color3s anywhere in here: Lune has no
	Roblox datatypes, so colours are RGB triples exactly as `Config.Monster` stores them, and the
	caller constructs the Color3.

	NOTHING SECRET PASSES THROUGH THIS MODULE. Its inputs are the phase and the seconds remaining,
	both of which reach every client on `RoundSnapshot`, and its output is the same on every screen.
	The sky is the one element in the game that MUST be identical for everybody: a sunrise that came
	early for one player would be `absence-is-observable` written in the sky.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"

export type Input = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	Duration: number,
}

-- An RGB triple, 0-255, matching how `Config` stores every colour. Never a Color3.
export type Rgb = { number }

--[[
	The night half is CAPTURED FROM THE PLACE at runtime rather than written here, which is why these
	fields exist at all. `tools/greybox/barrio.luau` authors the barrio's night — ambient, fog, the
	Atmosphere — and that authoring is the art direction §5 asks for. The controller reads those
	values once at startup and passes them in, so C30's art pass can retune the night without this
	module or `Config` learning anything.

	The dawn half is the destination, and the multipliers are multipliers for the same reason: a fog
	distance is a fraction of the map (barrio scales it by `SCALE`), so a dawn expressed as "2.6x the
	authored fog" survives a map resize that an absolute number would silently break.
]]
export type Params = {
	NightClockTime: number,
	DawnClockTime: number,

	NightBrightness: number,
	DawnBrightnessMult: number,

	NightFogEnd: number,
	DawnFogEndMult: number,

	NightAtmosphereDensity: number,
	DawnAtmosphereDensityMult: number,

	NightAmbientRgb: Rgb,
	DawnAmbientRgb: Rgb,

	NightOutdoorAmbientRgb: Rgb,
	DawnOutdoorAmbientRgb: Rgb,
}

export type Frame = {
	ClockTime: number,
	Brightness: number,
	FogEnd: number,
	AtmosphereDensity: number,
	AmbientRgb: Rgb,
	OutdoorAmbientRgb: Rgb,
}

local SkyCycle = {}

local function clamp01(value: number): number
	if value ~= value then -- NaN: a zero-length round divided by itself
		return 0
	end

	return math.clamp(value, 0, 1)
end

local function lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

--[[
	Rounded, because every consumer of a colour channel wants an integer 0-255 and rounding at the
	edges is what makes `frameFor(0)` return the captured triple UNCHANGED rather than 25.999999.
]]
local function lerpRgb(from: Rgb, to: Rgb, alpha: number): Rgb
	local out = table.create(3)

	for channel = 1, 3 do
		out[channel] = math.round(lerp(from[channel] or 0, to[channel] or 0, alpha)) -- config-ok: RGB has three channels
	end

	return out
end

--[[
	HOW FAR THROUGH THE NIGHT, IN 0..1, AND THE PHASE DECIDES BEFORE THE ARITHMETIC DOES.

	  IDLE / INTERMISSION / STARTING -> 0. The lobby is the deepest part of the night. A countdown to
	    a round that has not started would be a sky already claiming tension the round has not earned.
	  ACTIVE -> elapsed / duration, clamped. `SecondsRemaining` is what the snapshot carries.
	  ENDING -> 1, unconditionally. §4.8's reveal is the sunrise; the survivors either reached it or
	    did not, and either way the night is over. Pinning it here rather than remembering the last
	    ACTIVE value is what keeps this module stateless — and an ABORTED round (nobody left, no
	    winner) still ends at dawn, which is honest: the night is over for that server too.

	A zero or negative `Duration` returns 0 rather than dividing. A map with no round length is a
	config error, and a NaN written into `Lighting.ClockTime` is an unrecoverable render state that
	looks like a driver bug.
]]
function SkyCycle.progressFor(input: Input): number
	if input.Phase == "ENDING" then
		return 1
	end

	if input.Phase ~= "ACTIVE" then
		return 0
	end

	if input.Duration <= 0 then
		return 0
	end

	local elapsed = input.Duration - input.SecondsRemaining

	return clamp01(elapsed / input.Duration)
end

--[[
	THE SKY AT THAT PROGRESS.

	Every term is a straight lerp from the captured night to the dawn target, and that linearity is
	the design rather than the shortcut. The alternative — an ease that holds the night and then rushes
	the dawn — makes the sky a worse clock precisely when it matters most, because a player cannot read
	"how long do I have" off a curve they have to know the shape of.

	The reason the whole frame moves rather than just `ClockTime`: between ClockTime 3 and 5 Roblox's
	sky barely changes to the eye, so a round driving only the clock would look static for two thirds
	of its length and then dawn all at once. The fog thinning, the ambient warming and the Atmosphere
	dropping are what make the arc legible minute by minute — and they are §5's own night dressing
	being walked back, not new art.

	`alpha` is clamped here as well as in `progressFor`, because this function is also called directly
	with 0 to rebuild the night baseline and a caller that passed 1.2 would over-brighten past dawn.
]]
function SkyCycle.frameFor(progress: number, params: Params): Frame
	local alpha = clamp01(progress)

	return {
		ClockTime = lerp(params.NightClockTime, params.DawnClockTime, alpha),
		Brightness = lerp(
			params.NightBrightness,
			params.NightBrightness * params.DawnBrightnessMult,
			alpha
		),
		FogEnd = lerp(params.NightFogEnd, params.NightFogEnd * params.DawnFogEndMult, alpha),
		AtmosphereDensity = lerp(
			params.NightAtmosphereDensity,
			params.NightAtmosphereDensity * params.DawnAtmosphereDensityMult,
			alpha
		),
		AmbientRgb = lerpRgb(params.NightAmbientRgb, params.DawnAmbientRgb, alpha),
		OutdoorAmbientRgb = lerpRgb(
			params.NightOutdoorAmbientRgb,
			params.DawnOutdoorAmbientRgb,
			alpha
		),
	}
end

return SkyCycle
