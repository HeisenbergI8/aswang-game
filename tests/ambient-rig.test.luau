--!strict
--[[
	tests/ambient-rig.test.luau

	THE PROPERTY: A DISGUISED ANIMAL AND A REAL ONE STAND ON THE SAME GROUND.

	`AmbientService` seats a free rig from its spawn pad and a CLAIMED rig from the monster's
	HumanoidRootPart. Those are two different reference points — the pad's centre is at y = 0.4 and a
	character's root centre is about 3 studs above its own feet — so before this module the disguised
	cat floated roughly 2.6 studs above every real cat, permanently, for every client.

	THAT IS NOT THE TELL §4.5 DESIGNED. The intended deduction is "which cat is behaving oddly", which
	costs a survivor attention and time and can be wrong. An elevation offset costs nothing, is
	readable in a single frame without the monster moving, and is never wrong.
	`.claude/lessons/absence-is-observable.md`: the leak is a DIFFERENCE between entities, and
	`check:secrecy` — a text tripwire over role tokens — cannot see a number.

	WHY A PURE MODULE FOR TWO DIVISIONS. Because the property is an EQUALITY BETWEEN TWO CALL SITES in
	two different files, and that is exactly the shape no screenshot and no analyzer checks. A test can
	state "these agree for all inputs" once; a reader cannot.

	THE INPUTS ARE PLAIN NUMBERS AND NOTHING HERE KNOWS WHAT A PLAYER IS. Feeding it a UserId would be
	the only way to make it leak, and there is no parameter for one.
]]

local AmbientRig = require("../src/shared/pure/AmbientRig")

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

local EPSILON = 1e-6

local function near(a: number, b: number): boolean
	return math.abs(a - b) < EPSILON
end

-- The six forms' body heights, from `AmbientService.FORM_LOOKS`. Copied rather than required, because
-- that file requires `ReplicatedStorage` and Lune has no `game`; the range is what matters here and
-- it deliberately spans the smallest form and the largest.
local HEIGHTS = { 1.1, 1.2, 1.9, 1.8, 2.2, 5.0 }
local GROUNDS = { -4, 0, 0.1, 3.5, 18 }
-- A character's foot-to-root distance. R15 default is about 3; the transform SCALES the avatar, so
-- this is a range rather than a constant and that is the whole reason it is a parameter.
local FOOT_OFFSETS = { 1.65, 2.0, 3.0, 4.2 }

--[[
	THE ONE THAT MATTERS. Over every combination, a claimed rig and a free rig of the same form on the
	same ground occupy the SAME Y. This is the assertion that would have caught the shipped defect.
]]
for _, height in HEIGHTS do
	for _, ground in GROUNDS do
		local free = AmbientRig.restingY(ground, height)

		for _, footOffset in FOOT_OFFSETS do
			-- A monster standing on that same ground has its root `footOffset` above it.
			local puppeted = AmbientRig.puppetY(ground + footOffset, footOffset, height)

			check(
				`h={height} ground={ground} foot={footOffset}: claimed and free rigs share a Y`,
				near(free, puppeted),
				`free={free}, puppeted={puppeted}, delta={puppeted - free}`
			)
		end
	end
end

-- And the half that fixes the OTHER defect: a free rig rests ON the ground, not buried in it.
for _, height in HEIGHTS do
	for _, ground in GROUNDS do
		check(
			`h={height} ground={ground}: the rig's feet are on the ground, not under it`,
			near(AmbientRig.restingY(ground, height) - height / 2, ground),
			`bottom={AmbientRig.restingY(ground, height) - height / 2}, ground={ground}`
		)
	end
end

--[[
	MONOTONIC IN THE ROOT, so a monster walking up a ramp carries its disguise up with it. A function
	that clamped or floored would satisfy every equality above and freeze the cat at ground level while
	the monster climbed — a disguise that detaches on a slope, which is worse than one that floats.
]]
local previous = AmbientRig.puppetY(0, 3, 1.2)

for rootY = 1, 40 do
	local current = AmbientRig.puppetY(rootY, 3, 1.2)

	check(`puppetY rises with the root at rootY={rootY}`, current > previous)
	previous = current
end

--[[
	THE LIFT PAIR — AND THIS IS THE PAIR THE R15 VILLAGER ACTUALLY CALLS.

	Everything above tests `restingY`/`puppetY`, which spell the lift as `bodyHeight / 2`. That
	spelling is only true for a body whose pivot is its own centre; an R15 model pivots on its
	`HumanoidRootPart`, roughly three studs above the soles of a five-stud character. `AmbientService`
	therefore calls `restingYFromLift` and `puppetYFromLift` for that form — and an exploit audit
	pointed out that NO SUITE TOUCHED EITHER, so the parity claim in this module's header was asserted
	only for the pair the villager does not use.

	THE PROPERTY IS THE SAME ONE AND IT IS THE WHOLE POINT: a free rig and a claimed rig of the same
	form, on the same ground, must land on the same Y. Lifts are swept independently of heights because
	a lift is no longer derivable from a height.
]]
local LIFTS = { 0.55, 0.6, 0.9, 0.95, 1.1, 1.25, 2.59, 2.9, 3.05 }
local FOOT_OFFSETS = { 0, 1.5, 2.0, 3.0, 4.4, 7.25 }

for _, lift in LIFTS do
	for _, ground in GROUNDS do
		check(
			`restingYFromLift sits the pivot exactly lift above the ground (lift={lift}, ground={ground})`,
			near(AmbientRig.restingYFromLift(ground, lift) - lift, ground)
		)

		for _, footOffset in FOOT_OFFSETS do
			--[[
				THE PARITY EQUALITY. A monster whose feet are on this ground has its root at
				`ground + footOffset`, so the claimed rule fed that root must produce the free rule's
				answer. Any disagreement is a permanent, static elevation difference between the
				disguised entity and every free one of its form — readable with no motion at all.
			]]
			check(
				`free and claimed agree (lift={lift}, ground={ground}, foot={footOffset})`,
				near(
					AmbientRig.puppetYFromLift(ground + footOffset, footOffset, lift),
					AmbientRig.restingYFromLift(ground, lift)
				)
			)
		end
	end
end

--[[
	AND THE OLD PAIR MUST STAY THE NEW PAIR WITH `lift = bodyHeight / 2`, because `restingY` and
	`puppetY` now delegate. If someone re-implements either in terms of the height again, this is what
	catches the two drifting apart.
]]
for _, height in HEIGHTS do
	for _, ground in GROUNDS do
		check(
			`restingY is restingYFromLift at half height (height={height}, ground={ground})`,
			near(
				AmbientRig.restingY(ground, height),
				AmbientRig.restingYFromLift(ground, height / 2)
			)
		)
	end
end

if failures > 0 then
	error(`{failures} ambient-rig assertion(s) failed`, 0)
end

print(`  PASS  ambient-rig: {checked} assertions over {#HEIGHTS} forms x {#GROUNDS} grounds`)
