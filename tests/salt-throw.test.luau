--!strict
--[[
	The salt throw (§4.6, C14) — the cone, the range, and the four worlds that are all MISS.

	THE ASSERTION THIS FILE EXISTS FOR is the last one: that every geometric and identity refusal
	collapses to the SAME verdict. `SaltThrow` returning `MISS_NOT_ASWANG` beside `MISS_OUT_OF_RANGE`
	would be a free role oracle — stand in front of each player in turn, throw, read the monster off the
	refusal — and it is a refactor somebody will reach for the first time they debug a miss. A test that
	only checked "an untransformed Aswang is not a hit" would pass happily while that shipped.
]]

local SaltThrow = require("../src/shared/pure/SaltThrow")

type Vec3 = SaltThrow.Vec3
type PlayerState = SaltThrow.PlayerState
type RoundPhase = SaltThrow.RoundPhase

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

local function v(x: number, y: number, z: number): Vec3
	return { X = x, Y = y, Z = z }
end

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

--[[
	A throw that hits: thrower at the origin looking down +X, a transformed Aswang ten studs along it.
	Every case below is this, with one thing changed.
]]
local function request(overrides: {
	Phase: RoundPhase?,
	ThrowerState: PlayerState?,
	Carried: number?,
	ThrowerPos: Vec3?,
	Direction: Vec3?,
	TargetPos: Vec3?,
	TargetIsTransformedAswang: boolean?,
	Range: number?,
	ConeDegrees: number?,
}): SaltThrow.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		ThrowerState = overrides.ThrowerState or "ALIVE",
		Carried = overrides.Carried or 1,
		ThrowerPos = overrides.ThrowerPos or v(0, 0, 0),
		Direction = overrides.Direction or v(1, 0, 0),
		TargetPos = overrides.TargetPos or v(10, 0, 0),
		TargetIsTransformedAswang = if overrides.TargetIsTransformedAswang == nil
			then true
			else overrides.TargetIsTransformedAswang,
		Range = overrides.Range or 25,
		ConeDegrees = overrides.ConeDegrees or 20,
	}
end

check("the baseline throw hits", SaltThrow.evaluate(request({})) == "OK")

--------------------------------------------------------------------------------
-- Phase and thrower state: the full grid, one OK cell.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local verdict = SaltThrow.evaluate(request({ Phase = phase, ThrowerState = state }))

		local expected: SaltThrow.Verdict = if phase ~= "ACTIVE"
			then "WRONG_PHASE"
			elseif state ~= "ALIVE" then "THROWER_NOT_ALIVE"
			else "OK"

		check(`{phase} x {state} is {expected}`, verdict == expected, `got {verdict}`)
	end
end

do
	local permitted = 0

	for _, state in STATES do
		if SaltThrow.evaluate(request({ ThrowerState = state })) == "OK" then
			permitted += 1
		end
	end

	check("exactly one PlayerState may throw", permitted == 1, `{permitted} permitted`)
end

--------------------------------------------------------------------------------
-- The pouch.
--------------------------------------------------------------------------------

check("no pouch, no throw", SaltThrow.evaluate(request({ Carried = 0 })) == "NO_POUCH")
check("a negative carry is refused", SaltThrow.evaluate(request({ Carried = -1 })) == "NO_POUCH")
check("a NaN carry is refused", SaltThrow.evaluate(request({ Carried = 0 / 0 })) == "NO_POUCH")
check(
	"an infinite carry is refused",
	SaltThrow.evaluate(request({ Carried = math.huge })) == "NO_POUCH"
)
check("carrying two still throws", SaltThrow.evaluate(request({ Carried = 2 })) == "OK")

--------------------------------------------------------------------------------
-- Range.
--------------------------------------------------------------------------------

check(
	"a target exactly at range hits",
	SaltThrow.evaluate(request({ TargetPos = v(25, 0, 0), Range = 25 })) == "OK"
)

check(
	"a target one stud past range misses",
	SaltThrow.evaluate(request({ TargetPos = v(26, 0, 0), Range = 25 })) == "MISS"
)

check(
	"a zero range misses rather than hitting everything",
	SaltThrow.evaluate(request({ Range = 0 })) == "MISS"
)

check(
	"an infinite range misses rather than reaching the whole map",
	SaltThrow.evaluate(request({ Range = math.huge })) == "MISS"
)

check("a NaN range misses", SaltThrow.evaluate(request({ Range = 0 / 0 })) == "MISS")

--------------------------------------------------------------------------------
-- The cone. 20 degrees half-angle around +X.
--------------------------------------------------------------------------------

check(
	"dead ahead hits",
	SaltThrow.evaluate(request({ TargetPos = v(10, 0, 0), Direction = v(1, 0, 0) })) == "OK"
)

--[[
	tan(19 deg) * 10 ~= 3.44 studs of lateral offset at ten studs out — inside a 20-degree half-angle.
	tan(21 deg) * 10 ~= 3.84 — outside it. Computed rather than eyeballed so the two cases genuinely
	straddle the boundary rather than both sitting comfortably on one side of it.
]]
check(
	"just inside the cone hits",
	SaltThrow.evaluate(request({ TargetPos = v(10, 0, math.tan(math.rad(19)) * 10) })) == "OK"
)

check(
	"just outside the cone misses",
	SaltThrow.evaluate(request({ TargetPos = v(10, 0, math.tan(math.rad(21)) * 10) })) == "MISS"
)

check("directly behind misses", SaltThrow.evaluate(request({ TargetPos = v(-10, 0, 0) })) == "MISS")

check("perpendicular misses", SaltThrow.evaluate(request({ TargetPos = v(0, 0, 10) })) == "MISS")

check(
	"a zero direction misses rather than dividing by zero",
	SaltThrow.evaluate(request({ Direction = v(0, 0, 0) })) == "MISS"
)

check(
	"a NaN direction misses",
	SaltThrow.evaluate(request({ Direction = v(0 / 0, 0, 0) })) == "MISS"
)

check(
	"an infinite direction misses",
	SaltThrow.evaluate(request({ Direction = v(math.huge, 0, 0) })) == "MISS"
)

check(
	"an unnormalised direction still hits — magnitude is not trusted either way",
	SaltThrow.evaluate(request({ Direction = v(500, 0, 0) })) == "OK"
)

check("a cone of zero degrees misses", SaltThrow.evaluate(request({ ConeDegrees = 0 })) == "MISS")

check(
	"a cone of 90 degrees or more misses rather than hitting behind you",
	SaltThrow.evaluate(request({ ConeDegrees = 90 })) == "MISS"
)

check("a NaN cone misses", SaltThrow.evaluate(request({ ConeDegrees = 0 / 0 })) == "MISS")

check(
	"the thrower standing on the target misses rather than dividing by zero",
	SaltThrow.evaluate(request({ TargetPos = v(0, 0, 0) })) == "MISS"
)

--------------------------------------------------------------------------------
-- THE ONE THAT MATTERS: every failing world collapses to the same verdict.
--------------------------------------------------------------------------------

check(
	"an untransformed Aswang in the cone is a MISS, not a weaker hit",
	SaltThrow.evaluate(request({ TargetIsTransformedAswang = false })) == "MISS"
)

do
	--[[
		The four worlds §4.6's secrecy argument turns on. If any future edit splits these, this
		assertion fails and the role oracle is caught here rather than in a playtest — or worse, never,
		because a compromised client is the only party who would notice.
	]]
	local worlds: { { label: string, verdict: SaltThrow.Verdict } } = {
		{
			label = "nothing / a survivor in the cone",
			verdict = SaltThrow.evaluate(request({ TargetIsTransformedAswang = false })),
		},
		{
			label = "the Aswang, untransformed, dead ahead",
			verdict = SaltThrow.evaluate(
				request({ TargetIsTransformedAswang = false, TargetPos = v(5, 0, 0) })
			),
		},
		{
			label = "the Aswang, transformed, past range",
			verdict = SaltThrow.evaluate(request({ TargetPos = v(100, 0, 0) })),
		},
		{
			label = "the Aswang, transformed, in range, outside the cone",
			verdict = SaltThrow.evaluate(request({ TargetPos = v(0, 0, 10) })),
		},
	}

	local distinct: { [string]: boolean } = {}

	for _, world in worlds do
		distinct[world.verdict] = true
		check(`{world.label} is MISS`, world.verdict == "MISS", `got {world.verdict}`)
	end

	local count = 0

	for _ in distinct do
		count += 1
	end

	check(
		"all four failing worlds return ONE verdict — no refusal shape to read a role off",
		count == 1,
		`{count} distinct verdicts across the four worlds`
	)
end

--------------------------------------------------------------------------------
-- Precedence and purity.
--------------------------------------------------------------------------------

check(
	"phase outranks everything",
	SaltThrow.evaluate(request({ Phase = "ENDING", ThrowerState = "GHOST", Carried = 0 }))
		== "WRONG_PHASE"
)

check(
	"thrower state outranks the pouch",
	SaltThrow.evaluate(request({ ThrowerState = "GHOST", Carried = 0 })) == "THROWER_NOT_ALIVE"
)

check(
	"the pouch outranks geometry",
	SaltThrow.evaluate(request({ Carried = 0, TargetIsTransformedAswang = false })) == "NO_POUCH"
)

do
	local input = request({})
	local first = SaltThrow.evaluate(input)
	local second = SaltThrow.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check(
		"evaluate does not mutate its request",
		input.Carried == 1 and input.Range == 25 and input.TargetPos.X == 10
	)
end

--------------------------------------------------------------------------------
-- `inCone` DIRECTLY (C22). It was extracted from `evaluate` so the Solo Trial could
-- share the real aim without inheriting the round's rules — the trial runs at IDLE
-- against a scripted rig, where phase, thrower state and carry have no meaning.
--
-- Tested on its own because it now has a caller that never goes through `evaluate`,
-- and a geometry function with two callers and one test path is a function whose
-- second caller is unverified.
--------------------------------------------------------------------------------

local ORIGIN: SaltThrow.Vec3 = { X = 0, Y = 0, Z = 0 }
local FORWARD: SaltThrow.Vec3 = { X = 0, Y = 0, Z = 1 }

check(
	"a target dead ahead and in range is in the cone",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 10 }, 20, 30) == true
)

check(
	"a target dead behind is not, whatever the range",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = -10 }, 20, 30) == false
)

check(
	"a target beyond the range is not, however well aimed",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 30 }, 20, 30) == false
)

check(
	"a target exactly at the range boundary is in",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 20 }, 20, 30) == true
)

-- The degenerate inputs, each of which must answer false rather than error. A zero direction is the
-- one a client can actually send.
check(
	"a zero direction refuses rather than erroring",
	SaltThrow.inCone(ORIGIN, { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 5 }, 20, 30) == false
)

check(
	"a cone at 90 degrees or more refuses — it would hit what is behind you",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 20, 90) == false
)

check(
	"a zero cone refuses",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 20, 0) == false
)

check(
	"an infinite range refuses",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, math.huge, 30) == false
)

check(
	"a zero range refuses",
	SaltThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 0, 30) == false
)

--[[
	THE PROPERTY THAT KEEPS THE TUTORIAL HONEST: `inCone` is what `evaluate` uses, so a throw the
	real game would land is a throw the trial lands, at the same Config numbers. If these two ever
	disagree, the tutorial has started teaching an aim the game does not have — which is the exact
	failure C22 teaches by doing in order to avoid.
]]
for _, distance in { 1, 5, 10, 14, 15 } do
	local target: SaltThrow.Vec3 = { X = 0, Y = 0, Z = distance }

	local geometric = SaltThrow.inCone(ORIGIN, FORWARD, target, 15, 25)

	local full = SaltThrow.evaluate({
		Phase = "ACTIVE" :: SaltThrow.RoundPhase,
		ThrowerState = "ALIVE" :: SaltThrow.PlayerState,
		Carried = 1,
		ThrowerPos = ORIGIN,
		Direction = FORWARD,
		TargetPos = target,
		TargetIsTransformedAswang = true,
		Range = 15,
		ConeDegrees = 25,
	}) == "OK"

	check(`the trial's aim and the round's agree at {distance} studs`, geometric == full)
end

if failures > 0 then
	error(`{failures} salt-throw assertion(s) failed`, 0)
end

print(`  PASS  salt-throw: {checked} assertions over the cone, the range and the four MISS worlds`)
