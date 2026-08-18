--!strict
--[[
	The diegetic sunrise (C28, Appendix C.3), proven where a screenshot cannot reach.

	C28's verification is three screenshots at 0%, 50% and 90% of a round, and screenshots are the
	right evidence for "does it look like dawn". They are the wrong evidence for the two properties
	that actually break:

	  · MONOTONICITY. A sky that dips is a clock running backwards, and it would take a screenshot at
	    exactly the wrong second to catch it.
	  · EXACT RECOVERY OF THE NIGHT. `frameFor(0)` must return the captured baseline UNCHANGED, or
	    every round leaves the lobby a shade warmer than it found it. Nothing on screen names that
	    until three rounds later, when the barrio is grey.

	The second one is C04's bug wearing a different hat: MonsterService's revert restored hardcoded
	defaults instead of captured state and permanently branded the ex-Aswang. Only `exploit-auditor`
	found it, and only because it was reading for that shape. Here it is one assertion.
]]

local SkyCycle = require("../src/shared/pure/SkyCycle")

type Params = SkyCycle.Params

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

--[[
	A night baseline that is NOT the barrio's, deliberately.

	These are arbitrary numbers no source file contains, so an assertion that passes here passes
	because the arithmetic is right rather than because it happens to agree with `Config`. The one
	place this suite reads real values is the Config-shaped params below.
]]
local NIGHT_AMBIENT = { 11, 13, 23 }
local NIGHT_OUTDOOR = { 27, 31, 47 }

local function params(over: { StartClockTime: number?, EndClockTime: number? }?): Params
	local o = over or {}

	return {
		NightClockTime = o.StartClockTime or 3,
		DawnClockTime = o.EndClockTime or 6.4,

		NightBrightness = 1,
		DawnBrightnessMult = 2.4,

		NightFogEnd = 341,
		DawnFogEndMult = 2.6,

		NightAtmosphereDensity = 0.42,
		DawnAtmosphereDensityMult = 0.55,

		NightAmbientRgb = NIGHT_AMBIENT,
		DawnAmbientRgb = { 74, 66, 62 },

		NightOutdoorAmbientRgb = NIGHT_OUTDOOR,
		DawnOutdoorAmbientRgb = { 138, 122, 110 },
	}
end

local DURATION = 420

--------------------------------------------------------------------------------
-- The phase decides before the arithmetic does
--------------------------------------------------------------------------------

--[[
	Every phase that is not a running round pins to one end or the other, whatever the clock says.
	`SecondsRemaining` is deliberately a mid-round value in all four cases: if the phase gate were
	missing, three of these would return 0.5 instead.
]]
for _, phase in { "IDLE", "INTERMISSION", "STARTING" } :: { SkyCycle.RoundPhase } do
	check(
		`{phase} is the deepest night, whatever the clock reads`,
		SkyCycle.progressFor({ Phase = phase, SecondsRemaining = DURATION / 2, Duration = DURATION })
			== 0
	)
end

--[[
	ENDING IS DAWN UNCONDITIONALLY, and that includes an aborted round.

	Pinning it rather than remembering the last ACTIVE value is what keeps the module stateless. The
	night is over for that server either way — the survivors reached the morning or they did not.
]]
check(
	"ENDING is full dawn",
	SkyCycle.progressFor({ Phase = "ENDING", SecondsRemaining = 0, Duration = DURATION }) == 1
)

check(
	"ENDING is full dawn even when a round was aborted with time left",
	SkyCycle.progressFor({ Phase = "ENDING", SecondsRemaining = DURATION, Duration = DURATION })
		== 1
)

--------------------------------------------------------------------------------
-- The arithmetic, at the two ends and in the middle
--------------------------------------------------------------------------------

local function progressAt(secondsRemaining: number): number
	return SkyCycle.progressFor({
		Phase = "ACTIVE",
		SecondsRemaining = secondsRemaining,
		Duration = DURATION,
	})
end

check("a round begins at night", progressAt(DURATION) == 0)
check("a round ends at dawn", progressAt(0) == 1)
check("halfway is halfway", progressAt(DURATION / 2) == 0.5)

--[[
	BOTH OVERSHOOTS ARE CLAMPED, and neither is hypothetical.

	`SecondsRemaining` is computed from a server clock and rendered by a client that may receive a
	snapshot late; a negative value is what the last tick of a round looks like when the phase change
	has not arrived yet. An unclamped negative would drive `ClockTime` past dawn into midday, which
	on a horror map is not a small artifact.
]]
check("a late snapshot cannot push the sky past dawn", progressAt(-30) == 1)
check("an early snapshot cannot push the sky before night", progressAt(DURATION * 2) == 0)

--[[
	A ZERO-LENGTH ROUND IS A CONFIG ERROR AND MUST NOT BECOME A RENDER ERROR.

	0/0 is NaN, and a NaN written into `Lighting.ClockTime` is not a wrong sky — it is an
	unrecoverable render state that reads as a driver bug on the player's phone.
]]
check("a zero-length round is night, not NaN", progressAt(0 / 0) == 0)
check(
	"a zero duration is night, not a division",
	SkyCycle.progressFor({ Phase = "ACTIVE", SecondsRemaining = 0, Duration = 0 }) == 0
)

--------------------------------------------------------------------------------
-- PROPERTY 1 — the night is recovered EXACTLY
--------------------------------------------------------------------------------

local night = SkyCycle.frameFor(0, params())

check("frameFor(0) returns the captured ClockTime", night.ClockTime == 3)
check("frameFor(0) returns the captured brightness", night.Brightness == 1)
check("frameFor(0) returns the captured fog", night.FogEnd == 341)
check("frameFor(0) returns the captured atmosphere", night.AtmosphereDensity == 0.42)

for channel = 1, 3 do
	check(
		`frameFor(0) returns the captured ambient channel {channel}`,
		night.AmbientRgb[channel] == NIGHT_AMBIENT[channel],
		`got {night.AmbientRgb[channel]}, captured {NIGHT_AMBIENT[channel]}`
	)
	check(
		`frameFor(0) returns the captured outdoor ambient channel {channel}`,
		night.OutdoorAmbientRgb[channel] == NIGHT_OUTDOOR[channel],
		`got {night.OutdoorAmbientRgb[channel]}, captured {NIGHT_OUTDOOR[channel]}`
	)
end

--------------------------------------------------------------------------------
-- PROPERTY 2 — the sky never goes backwards
--------------------------------------------------------------------------------

--[[
	Walked at one-second resolution across a whole round, because a monotonicity bug introduced by a
	future ease would show up at some interior pair and nowhere else. Colour channels are included:
	a rounded lerp is where a non-monotone step would actually hide.
]]
local previous = SkyCycle.frameFor(0, params())
local monotone = true
local firstBreak = ""

for second = 1, DURATION do
	local frame = SkyCycle.frameFor(progressAt(DURATION - second), params())

	local ok = frame.ClockTime >= previous.ClockTime
		and frame.Brightness >= previous.Brightness
		and frame.FogEnd >= previous.FogEnd
		and frame.AtmosphereDensity <= previous.AtmosphereDensity
		and frame.AmbientRgb[1] >= previous.AmbientRgb[1]
		and frame.OutdoorAmbientRgb[1] >= previous.OutdoorAmbientRgb[1]

	if not ok and monotone then
		monotone = false
		firstBreak = `at second {second}: clock {previous.ClockTime} -> {frame.ClockTime}`
	end

	previous = frame
end

check("the sky never goes backwards over a whole round", monotone, firstBreak)

--[[
	And it actually ARRIVES. A mapping that is monotone but barely moves is a countdown nobody can
	read — the failure Appendix C.3 is warning about, where the cycle is decoration rather than
	information.
]]
local dawn = SkyCycle.frameFor(1, params())

check("dawn reaches the configured clock time", dawn.ClockTime == 6.4)
check("dawn is brighter than night", dawn.Brightness > night.Brightness)
check("dawn sees further than night", dawn.FogEnd > night.FogEnd)
check("dawn's fog is thinner than night's", dawn.AtmosphereDensity < night.AtmosphereDensity)
check("dawn is warmer than night", dawn.AmbientRgb[1] > dawn.AmbientRgb[3])

--------------------------------------------------------------------------------
-- PROPERTY 3 — purity
--------------------------------------------------------------------------------

local probe = { Phase = "ACTIVE" :: SkyCycle.RoundPhase, SecondsRemaining = 210, Duration = 420 }
local first = SkyCycle.progressFor(probe)
local second = SkyCycle.progressFor(probe)

check("progressFor is deterministic", first == second)
check(
	"progressFor does not mutate its input",
	probe.SecondsRemaining == 210 and probe.Duration == 420
)

local p = params()
local before = p.NightAmbientRgb[1]
SkyCycle.frameFor(0.5, p)

check("frameFor does not mutate its params", p.NightAmbientRgb[1] == before)
check(
	"frameFor does not alias the captured triples",
	SkyCycle.frameFor(0, p).AmbientRgb ~= p.NightAmbientRgb
)

if failures > 0 then
	error(`{failures} sky-cycle failure(s)`, 0)
end

print(`  PASS  sky-cycle: {checked} assertions`)
