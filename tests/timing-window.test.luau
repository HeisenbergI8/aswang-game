--!strict
--[[
	tests/timing-window.test.luau

	`server/pure/TimingWindow.luau` over its WHOLE domain rather than a sample of it.

	Enumerable, so enumerated. The bar is periodic and the zone is a closed interval, so "every 64th
	of a sweep, across three sweeps, at three widths and three graces" is not a sampling strategy —
	it is the domain, at a resolution finer than any decision the module makes.

	SIX PROPERTIES, AND ONLY THE LAST TWO CAN FAIL ON A BROKEN `isHit`. Properties 1-4 are all
	satisfied by an `isHit` that returns `true` unconditionally; property 5 is satisfied by one that
	returns `false` too rarely and property 6 pins the actual width of the accepting window. Both are
	written out for that reason, not for coverage.
]]

local TimingWindow = require("../src/server/pure/TimingWindow")

local PERIOD = 1.8
local CENTER = 0.5
local SAMPLES_PER_SWEEP = 64
local SWEEPS = 3
local EPSILON = 1e-9

local HALF_WIDTHS = { 0, 0.1, 0.25 }
local GRACES = { 0, 0.05, 0.2 }

local failures = 0
local assertions = 0

local function check(label: string, ok: boolean, detail: string?)
	assertions += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function hitAt(elapsed: number, halfWidth: number, grace: number): boolean
	return TimingWindow.isHit({
		Elapsed = elapsed,
		Period = PERIOD,
		GreenCenter = CENTER,
		GreenHalfWidth = halfWidth,
		GraceSeconds = grace,
	})
end

--  1. The bar never leaves the track. A position outside 0..1 renders off the end of the UI at C18
--     and is the failure a triangle fold written with the wrong constant produces.
for step = 0, SAMPLES_PER_SWEEP * SWEEPS - 1 do
	local elapsed = step * PERIOD / SAMPLES_PER_SWEEP
	local position = TimingWindow.positionAt(elapsed, PERIOD)

	check(
		`position stays on the track at step {step}`,
		position >= -EPSILON and position <= 1 + EPSILON,
		`position={position}`
	)
end

--  2. Periodic. positionAt(e) == positionAt(e + period), which is what lets the client extrapolate
--     from one sent phase for the rest of the task instead of being fed the bar continuously.
for step = 0, SAMPLES_PER_SWEEP - 1 do
	local elapsed = step * PERIOD / SAMPLES_PER_SWEEP
	local here = TimingWindow.positionAt(elapsed, PERIOD)
	local aSweepLater = TimingWindow.positionAt(elapsed + PERIOD, PERIOD)

	check(
		`the bar repeats one period later at step {step}`,
		math.abs(here - aSweepLater) <= EPSILON,
		`{here} vs {aSweepLater}`
	)
end

--  3. Symmetric about the midpoint of the sweep: positionFromPhase(p) == positionFromPhase(1 - p).
--     A zone at CENTER = 0.5 is therefore equally hittable on the way out and the way back, which is
--     the reason Config pins the centre there.
for step = 0, SAMPLES_PER_SWEEP do
	local phase = step / SAMPLES_PER_SWEEP
	local out = TimingWindow.positionFromPhase(phase)
	local back = TimingWindow.positionFromPhase(1 - phase)

	check(
		`the sweep is symmetric at phase {phase}`,
		math.abs(out - back) <= EPSILON,
		`{out} vs {back}`
	)
end

--  4. Grace is monotone: if a stop lands with grace g, it lands with any grace >= g. This is what
--     makes the knob safe to tune in one direction at M12 — raising it can only ever make the task
--     easier, never differently hard.
for _, halfWidth in HALF_WIDTHS do
	for step = 0, SAMPLES_PER_SWEEP * SWEEPS - 1 do
		local elapsed = step * PERIOD / SAMPLES_PER_SWEEP
		local previous = false

		for _, grace in GRACES do
			local hit = hitAt(elapsed, halfWidth, grace)

			check(
				`grace only ever widens (half={halfWidth}, step={step}, grace={grace})`,
				not previous or hit
			)

			previous = previous or hit
		end
	end
end

--[[
	5. A zero-width zone with zero grace accepts a stop only where the bar is exactly on the centre.

	At CENTER = 0.5 the bar crosses the centre exactly TWICE per sweep — once outbound, once back —
	and the sample grid lands on both (steps 16 and 48 of 64). So the expected count is exact rather
	than approximate, and that is what gives this property teeth: an `isHit` written with `<` where
	`<=` was meant accepts NOTHING here and reports zero. Every other property in this file passes
	happily with that one-character bug in place.
]]
local zeroWidthHits = 0

for step = 0, SAMPLES_PER_SWEEP - 1 do
	if hitAt(step * PERIOD / SAMPLES_PER_SWEEP, 0, 0) then
		zeroWidthHits += 1
	end
end

check(
	"a zero-width zone accepts exactly the two centre crossings per sweep",
	zeroWidthHits == 2,
	`{zeroWidthHits} of {SAMPLES_PER_SWEEP} samples`
)

check("the outbound centre crossing lands", hitAt(16 * PERIOD / SAMPLES_PER_SWEEP, 0, 0))
check("the return centre crossing lands", hitAt(48 * PERIOD / SAMPLES_PER_SWEEP, 0, 0))
check("the start of the sweep does not", not hitAt(0, 0, 0))
check("the far end of the sweep does not", not hitAt(32 * PERIOD / SAMPLES_PER_SWEEP, 0, 0))

--[[
	6. THE ONE WITH TEETH. Across a full sweep, the fraction of sampled moments that accept a stop
	   equals 2 * effectiveHalfWidth, to within one sample. The bar sweeps the track linearly and
	   covers it twice per period, so a window of half-width h around the centre is open for exactly
	   that fraction of the time.

	   Properties 1-4 are all satisfied by an `isHit` that returns true unconditionally. This one is
	   not. It is also the sentence M12 tunes: "a timing stop lands about a fifth of the time" is a
	   balance statement, and this is where it is written down.
]]
for _, halfWidth in HALF_WIDTHS do
	for _, grace in GRACES do
		local hits = 0
		local total = SAMPLES_PER_SWEEP * SWEEPS

		for step = 0, total - 1 do
			if hitAt(step * PERIOD / SAMPLES_PER_SWEEP, halfWidth, grace) then
				hits += 1
			end
		end

		local expected = math.min(1, 2 * TimingWindow.effectiveHalfWidth({
			Elapsed = 0,
			Period = PERIOD,
			GreenCenter = CENTER,
			GreenHalfWidth = halfWidth,
			GraceSeconds = grace,
		}))
		local measured = hits / total

		check(
			`the open fraction matches the zone (half={halfWidth}, grace={grace})`,
			math.abs(measured - expected) <= 2 / SAMPLES_PER_SWEEP,
			`measured={measured}, expected={expected}`
		)
	end
end

-- The degenerate guards, which cannot arrive through Config and are therefore exactly the ones that
-- would reach a client unnoticed. A stopped bar must render at a real position, not a nan.
local stopped = TimingWindow.positionAt(5, 0)

check("a non-positive period gives a stopped bar, not a nan", stopped == stopped, `{stopped}`)
check("and that bar sits at the start of the track", stopped == 0, `{stopped}`)

-- A negative grace must not NARROW the zone — that knob was never meant to exist.
check(
	"a negative grace is floored rather than narrowing the zone",
	TimingWindow.effectiveHalfWidth({
		Elapsed = 0,
		Period = PERIOD,
		GreenCenter = CENTER,
		GreenHalfWidth = 0.1,
		GraceSeconds = -5,
	}) == 0.1
)

-- os.clock() is not guaranteed monotonic, so a backwards jump must skip the bar rather than error.
local backwards = TimingWindow.positionAt(-PERIOD / 4, PERIOD)

check(
	"a backwards clock still lands on the track",
	backwards >= -EPSILON and backwards <= 1 + EPSILON,
	`{backwards}`
)

if failures > 0 then
	error(`{failures} timing-window failure(s)`, 0)
end

print(`  PASS  timing-window: {assertions} assertions over {#HALF_WIDTHS * #GRACES} configurations`)
