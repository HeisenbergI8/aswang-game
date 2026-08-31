--!strict
--[[
	tests/ambient-motion.test.luau

	THE PROPERTIES THAT MAKE PROCEDURAL MOTION SAFE TO ADD TO A DISGUISE.

	Motion is the half of camouflage §4.5 hangs on — "which cat is behaving oddly" — so the moment
	ambient rigs start bobbing and swaying, HOW they bob becomes a secrecy surface. The rule is that a
	claimed rig and a free rig run the SAME function over the SAME kind of input, and the only
	difference is the input's value.

	SO EVERY ASSERTION HERE IS ABOUT THE FUNCTION BEING TOTAL AND CONTINUOUS. A function with a
	discontinuity, a clamp, or a special case at some speed is a function that behaves differently for
	a monster than for a pig, and the special case is exactly what a careful implementer adds when the
	fast case "looks wrong".

	SEEDLESS AND DETERMINISTIC. There is no `Random` here and no `os.clock()`: the caller passes time
	in. That is what makes it testable and it is also why it is safe in `src/shared` — CLAUDE.md's rule
	is that a published algorithm is fine and a published algorithm with client-suppliable INPUTS is
	not, and every input here is a number the client can already read off the part it is watching.
]]

local AmbientMotion = require("../src/shared/pure/AmbientMotion")

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
	`MotionKneeStuds` IS `Config.Ambient.WanderSpeed`, and that pairing is the point rather than a
	coincidence: the half-amplitude speed sits at the pace a free animal ambles, so wandering reads as
	half-lively and a monster keeping up with a sprint reads as clearly faster. Set the knee below
	walking pace and every rig saturates, which erases §4.5's one licensed difference.
]]
local TUNING = {
	BobStuds = 0.12,
	BobHz = 1.4,
	SwayDegrees = 4,
	SwayHz = 0.9,
	IdleHz = 0.25,
	MotionKneeStuds = 4,
}

--[[
	1. PHASE OFFSETS ARE DISTINCT ACROSS THE POPULATION.

	Eighteen rigs bobbing in lockstep is not scenery, it is a chorus line — and it is worse than
	static, because a viewer reads the synchronised set as one system and the monster's rig as the
	only one out of step the moment its speed differs. Distinct offsets mean the population never had
	a phase to be out of.
]]
local seen: { [number]: boolean } = {}

for index = 1, 18 do
	local phase = AmbientMotion.phaseFor(index)

	check(`phaseFor({index}) is inside one period`, phase >= 0 and phase < math.pi * 2, `{phase}`)
	check(`phaseFor({index}) is distinct`, seen[phase] ~= true, `{phase}`)
	seen[phase] = true
end

check(
	"phaseFor is deterministic across calls",
	AmbientMotion.phaseFor(7) == AmbientMotion.phaseFor(7)
)

--[[
	2. BOUNDED, AND THE BOUND IS THE TUNING RATHER THAN A CONSTANT INSIDE THE MODULE.

	An unbounded bob at high speed is a rig launching itself off the ground — which for a CLAIMED rig
	means the disguise leaves the floor exactly when the monster sprints. Phase 2 spent the whole phase
	putting these bodies on the ground; an unbounded vertical term would undo it under motion only,
	which is far harder to notice than a static offset.
]]
for _, speed in { 0, 0.5, 4, 16, 40, 1000 } do
	for step = 0, 40 do
		local t = step * 0.137
		local bob = AmbientMotion.bobOffset(t, 1.1, speed, TUNING)

		check(
			`bob is bounded at speed={speed}`,
			math.abs(bob) <= TUNING.BobStuds + 1e-9,
			`{bob} at t={t}`
		)
	end
end

--[[
	3. CONTINUOUS IN SPEED — no threshold, no "walking vs idle" switch.

	A discrete idle/walk switch is the single most likely thing to be written here, and it is the leak:
	a claimed rig crosses the threshold whenever the monster moves and a free rig at wander speed may
	sit near it, so the two visibly switch modes at different moments. A continuous blend has no mode
	to be in.
]]
local previous = AmbientMotion.amplitudeFor(0, TUNING)

for tenths = 1, 200 do
	local speed = tenths / 10
	local current = AmbientMotion.amplitudeFor(speed, TUNING)

	check(
		`amplitude does not jump between {(tenths - 1) / 10} and {speed}`,
		math.abs(current - previous) < 0.05,
		`{previous} -> {current}`
	)
	previous = current
end

check("a still rig still idles rather than freezing", AmbientMotion.amplitudeFor(0, TUNING) > 0)

--[[
	4. THE SPEED THE MOTION READS IS THE MEASURED ONE, and this is the parity assertion.

	`speedFrom` takes a displacement and a delta time. It is the ONLY way either path learns how fast
	its rig is going — neither passes in `WanderSpeed`, and neither passes in the monster's WalkSpeed —
	so a free rig and a claimed rig that happen to move at the same rate animate identically, and the
	one that moves faster differs only in degree.
]]
check("speedFrom is displacement over time", AmbientMotion.speedFrom(8, 0.5) == 16)
check("a zero delta does not divide by zero", AmbientMotion.speedFrom(8, 0) == 0)
check("a negative delta is refused rather than inverted", AmbientMotion.speedFrom(8, -0.5) == 0)

if failures > 0 then
	error(`{failures} ambient-motion assertion(s) failed`, 0)
end

print(`  PASS  ambient-motion: {checked} assertions`)
