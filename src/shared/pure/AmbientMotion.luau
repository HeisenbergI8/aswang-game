--!strict
--[[
	AmbientMotion — the bob, the sway and the idle, as arithmetic over time and measured speed.

		phaseFor(index)                        -> a per-entity offset, so eighteen rigs are not a chorus
		speedFrom(distance, deltaTime)         -> how fast this rig ACTUALLY moved
		amplitudeFor(speed, tuning)            -> how much motion that speed earns, continuously
		bobOffset(t, phase, speed, tuning)     -> vertical, in studs
		swayDegrees(t, phase, speed, tuning)   -> roll, in degrees
		strideWeight(speed, tuning)            -> 0..1 blend from an idle clip to a walk clip
		strideRate(speed, tuning)              -> playback multiplier for that walk clip

	THIS MODULE IS THE PARITY MECHANISM, not a decoration. `AmbientService` used to move free rigs in
	`wanderTick` and claimed rigs in `PuppetSlot` — two functions, two files — and adding motion to one
	of them would have made the disguised animal THE ONE THAT DOES NOT BREATHE. So the motion lives
	here, both paths call it, and a claim changes only the target and the speed cap.

	EVERY TERM READS `speed`, AND `speed` IS ALWAYS MEASURED. Neither caller passes in the number that
	caused the movement — not `Config.Ambient.WanderSpeed`, not the monster's WalkSpeed. A rig learns
	how fast it is going by how far it went, so two rigs travelling at the same rate animate
	identically no matter what is driving them, and one travelling faster differs only in degree. That
	degree IS §4.5's designed tell: "which cat is behaving oddly".

	CONTINUOUS, WITH NO IDLE/WALK THRESHOLD. A discrete switch is the obvious implementation and it is
	a leak: the claimed rig crosses the threshold on the monster's movement and a free rig near wander
	speed crosses it on its own schedule, so the two visibly change mode at different moments. There is
	no mode here to change.

	SEEDLESS. Time and index in, numbers out. `phaseFor` is a hash of the index rather than a draw, so
	two servers agree and there is nothing to replay — and there is nothing worth replaying, because a
	slot index is not a secret (`AmbientRoster`'s header).

	NO `script.Parent` REQUIRES; the tuning is passed in as a table so `Config` never reaches this file.
]]

export type Tuning = {
	BobStuds: number,
	BobHz: number,
	SwayDegrees: number,
	SwayHz: number,
	IdleHz: number,
	MotionKneeStuds: number,
	StrideReferenceStuds: number,
	StrideRateMin: number,
	StrideRateMax: number,
}

local AmbientMotion = {}

local TAU = math.pi * 2

--[[
	HOW MUCH MOTION A RIG HAS WHEN IT IS COMPLETELY STILL, as a fraction of its moving amplitude.

	NOT A BALANCE KNOB — it is the shape of the curve, and the reason it is not zero. A rig that froze
	when still would make STILLNESS the tell, and a camouflaged monster standing perfectly still is
	precisely what a hiding player does. A quarter is enough to read as breathing at a distance and
	little enough that walking is still visibly different.
]]
local IDLE_FLOOR = 0.25

--[[
	THE 0..1 BLEND BETWEEN STILL AND MOVING, AND EVERY OTHER FUNCTION HERE IS BUILT ON IT.

	`speed / (speed + knee)` saturates smoothly: zero at rest, one half at `knee`, asymptotic to one.
	That shape is chosen over a clamp because a clamp has a CORNER, and a corner is a speed at which
	the animation visibly stops changing — which a survivor could learn to read as "that one is at the
	cap", a difference of kind rather than of degree.

	`knee` IS A SPEED IN STUDS PER SECOND AND THE FIRST VERSION OF THIS GOT THAT WRONG. It used
	`1 / BobHz`, which is an inverse frequency — dimensionally a time, numerically 0.71 — so the half
	point sat below walking pace and a rig ambling at `WanderSpeed` was already at 85% amplitude, with
	sprinting barely distinguishable from strolling. The knee belongs at wander speed, so a wandering
	animal reads as half-lively and a monster keeping up with a sprint reads as clearly faster. That
	difference IS §4.5's designed tell, and flattening it would have quietly removed the one signal
	camouflage is supposed to give.
]]
local function saturation(speed: number, tuning: Tuning): number
	local knee = math.max(tuning.MotionKneeStuds, 1e-6)

	return speed / (speed + knee)
end

--[[
	A STABLE OFFSET PER ENTITY. The golden-ratio conjugate as the step gives a low-discrepancy sequence
	— consecutive indices land far apart on the circle — so neighbouring rigs are maximally out of
	phase rather than merely different. Eighteen rigs on a shared phase read as one animated object.
]]
function AmbientMotion.phaseFor(index: number): number
	return (index * 0.61803398875) % 1 * TAU
end

--[[
	HOW FAST THIS RIG ACTUALLY MOVED. The only speed input either caller has.

	A NON-POSITIVE DELTA ANSWERS ZERO RATHER THAN DIVIDING. Heartbeat can hand back a zero delta on the
	first frame after a resume, and `distance / 0` is `inf`, which would put the amplitude at its cap
	for one frame — a single-frame twitch on every rig at once, at the moment a player's game unpauses.
]]
function AmbientMotion.speedFrom(distance: number, deltaTime: number): number
	if deltaTime <= 0 then
		return 0
	end

	return distance / deltaTime
end

-- HOW MUCH MOTION A SPEED EARNS, IN 0..1, CONTINUOUSLY AND WITH NO THRESHOLD. See `saturation` and
-- `IDLE_FLOOR` above; this is the two of them composed, and it is the only amplitude in the file.
function AmbientMotion.amplitudeFor(speed: number, tuning: Tuning): number
	return IDLE_FLOOR + (1 - IDLE_FLOOR) * saturation(speed, tuning)
end

--[[
	VERTICAL, IN STUDS. Bounded by `BobStuds` for every input, which is what keeps a fast-moving
	disguise on the ground that Phase 2 put it on.

	THE RATE BLENDS `IdleHz` INTO `BobHz` ALONG THE SAME SATURATION the amplitude uses, so a resting
	animal breathes slowly and shallowly while a moving one steps quickly and deeply — one curve, two
	readings, and no second threshold to fall out of step with the first.
]]
function AmbientMotion.bobOffset(t: number, phase: number, speed: number, tuning: Tuning): number
	local moving = saturation(speed, tuning)
	local rate = tuning.IdleHz + (tuning.BobHz - tuning.IdleHz) * moving

	return math.sin(t * rate * TAU + phase)
		* tuning.BobStuds
		* AmbientMotion.amplitudeFor(speed, tuning)
end

-- Roll, in degrees. Slower than the bob and offset from it, so the two never align into a single
-- pendulum — an animal that rolls exactly in time with its own bounce reads as a toy.
function AmbientMotion.swayDegrees(t: number, phase: number, speed: number, tuning: Tuning): number
	return math.sin(t * tuning.SwayHz * TAU + phase * 1.7)
		* tuning.SwayDegrees
		* AmbientMotion.amplitudeFor(speed, tuning)
end

--[[
	THE TWO STRIDE TERMS — FOR THE ONE FORM THAT HAS JOINTS INSTEAD OF A BOB.

	VILLAGER IS AN R15 RIG, AND THE BOB IS WRONG FOR IT. Everything above animates a rigid body by
	moving the whole thing: a sine on Y and a roll on Z, which is a fair approximation of a four-legged
	animal at a distance and is exactly what a person walking does NOT do. Applied to a humanoid mesh
	it read, in a player's words, as "bouncing instead of walking" — a five-stud human sliding along
	the ground while rising and falling and rolling from side to side.

	SO A RIGGED FORM GETS ITS LEGS ANIMATED AND ITS BODY LEFT ALONE, and these two functions are the
	whole interface to that. `AmbientService` blends an idle clip into a walk clip by `strideWeight`
	and plays the walk clip at `strideRate`.

	THEY READ THE SAME `speed` AND THE SAME `saturation` CURVE AS THE BOB, and that is the parity
	argument in this file's header holding for a second animation system: a claimed rig and a free rig
	at the same measured speed produce the same weights and the same playback rate, because there is
	one function and both callers are the one `stepEntity`. A rigged form that animated off
	`Humanoid.MoveDirection` — the obvious implementation — would have been a leak, because a puppeted
	rig is moved by `PivotTo` and has no MoveDirection at all: the disguised villager would have been
	the one standing still while walking.
]]
function AmbientMotion.strideWeight(speed: number, tuning: Tuning): number
	return saturation(speed, tuning)
end

--[[
	HOW FAST TO PLAY THE WALK CLIP. A clip authored for one pace looks wrong at any other, so the
	playback rate tracks measured speed rather than being pinned at 1.

	CLAMPED AT BOTH ENDS, and the LOW clamp is the one that matters. `speed` approaches zero whenever
	an entity is idling, and a walk clip at rate 0 is a FROZEN POSE — a villager caught mid-step,
	perfectly still, which reads as a bug and, worse, as a difference if it happened to only some of
	them. The floor keeps the legs moving slowly under a mostly-idle blend instead.
]]
function AmbientMotion.strideRate(speed: number, tuning: Tuning): number
	local reference = math.max(tuning.StrideReferenceStuds, 1e-6)

	return math.clamp(speed / reference, tuning.StrideRateMin, tuning.StrideRateMax)
end

return AmbientMotion
