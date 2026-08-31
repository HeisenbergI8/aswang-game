--!strict
--[[
	The garlic barrier's clock and its crossing predicate (§4.6, V09).

	TESTED AT TWO YAWS, 0 AND 90 DEGREES, AND THAT IS THE POINT OF THE FILE. The axis convention is
	shared between three places that cannot see each other — `barrio.luau` writes the `Yaw` attribute,
	`ItemService` converts it to radians, and `pure/GarlicBarrier` builds a plane from it. A
	convention that is right at yaw 0 and transposed at yaw 90 would deny the seven kubo (all N/S
	doors in the table) correctly and silently fail to deny the chapel's east door, which is the map's
	only two-door room and the most likely venue for the loyalty test. Every geometric case below runs
	at both.

	THE PREDICATE'S JOB IS TO SAY `false`. It is the server's anti-cheat backstop, not the block —
	the block is physics on the Aswang's own client. §4.6 forbids the barrier playing ANY effect on
	the monster, and the server's correction is an effect, so every one of the four tests exists to
	stop the correction firing on an honest player. The cases that must be `false` are therefore the
	load-bearing half: the threshold-stander, the walk around the house, the roof, the jitter.

	THE `tolerance` CASE IS THE ONE THAT PROTECTS AN HONEST ASWANG. A character standing in a garlic
	doorway drifts across the plane under lag. Correcting that would rubber-band the monster at a
	garlic doorway in front of witnesses, which is the exact tell the whole chunk is built to avoid.
]]

local GarlicBarrier = require("../src/shared/pure/GarlicBarrier")

type Barrier = GarlicBarrier.Barrier
type Vec3 = GarlicBarrier.Vec3

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

local TOLERANCE = 2.5

-- A doorway at the origin, 9.3 studs wide (the map's real gap) and 12 tall, floor at y = 0.
local function barrierAt(yaw: number): Barrier
	return {
		X = 0,
		Y = 0,
		Z = 0,
		Yaw = yaw,
		HalfWidth = 4.65,
		Height = 12,
		CreatedAt = 0,
		ExpiresAt = 100,
	}
end

--[[
	THE SAME CASE EXPRESSED IN THE DOORWAY'S OWN FRAME, so a test reads the same at both yaws.

	`n` is how far along the crossing axis, `l` is how far sideways along the opening, `y` is height.
	At yaw 0 the crossing axis is +Z and the opening runs along +X; at yaw 90 they swap. Building the
	world-space point from the axes rather than hand-writing coordinates is what makes the yaw-90 run
	a genuine second test instead of a transcription of the first.
]]
local function point(yaw: number, n: number, l: number, y: number): Vec3
	local c, s = math.cos(yaw), math.sin(yaw)
	-- along = (c, 0, s); normal = (-s, 0, c)
	return {
		X = l * c + n * -s,
		Y = y,
		Z = l * s + n * c,
	}
end

for _, yaw in { 0, math.pi / 2 } do
	local label = if yaw == 0 then "yaw 0 (N/S door)" else "yaw 90 (E/W door)"
	local barrier = barrierAt(yaw)

	local function crossed(from: Vec3, to: Vec3): boolean
		return GarlicBarrier.crossed(barrier, from, to, TOLERANCE)
	end

	-- THE BREACH. Straight through the middle of the opening, well past the plane.
	check(
		`{label}: a walk straight through the opening is a crossing`,
		crossed(point(yaw, -4, 0, 1), point(yaw, 4, 0, 1))
	)

	check(
		`{label}: the same walk in the other direction is a crossing`,
		crossed(point(yaw, 4, 0, 1), point(yaw, -4, 0, 1))
	)

	-- NOT A CROSSING: never changed sides.
	check(
		`{label}: both samples on the near side is not a crossing`,
		not crossed(point(yaw, -6, 0, 1), point(yaw, -3, 0, 1))
	)

	check(
		`{label}: both samples on the far side is not a crossing — already through`,
		not crossed(point(yaw, 3, 0, 1), point(yaw, 6, 0, 1))
	)

	-- NOT A CROSSING: the tolerance. This is the honest-Aswang case.
	check(
		`{label}: a destination inside the tolerance is not a breach`,
		not crossed(point(yaw, -1, 0, 1), point(yaw, TOLERANCE - 0.1, 0, 1))
	)

	check(
		`{label}: a destination exactly at the tolerance is not a breach`,
		not crossed(point(yaw, -1, 0, 1), point(yaw, TOLERANCE, 0, 1))
	)

	check(
		`{label}: a destination just past the tolerance is a breach`,
		crossed(point(yaw, -1, 0, 1), point(yaw, TOLERANCE + 0.1, 0, 1))
	)

	-- NOT A CROSSING: a sample sitting exactly on the plane. The threshold-stander.
	check(
		`{label}: a sample exactly on the plane is not a crossing`,
		not crossed(point(yaw, 0, 0, 1), point(yaw, 4, 0, 1))
	)

	check(
		`{label}: arriving exactly on the plane is not a crossing`,
		not crossed(point(yaw, -4, 0, 1), point(yaw, 0, 0, 1))
	)

	-- NOT A CROSSING: outside the opening's width. The walk around the house.
	check(
		`{label}: crossing the plane past the opening's edge is not a breach`,
		not crossed(point(yaw, -4, 8, 1), point(yaw, 4, 8, 1))
	)

	check(
		`{label}: crossing past the opposite edge is not a breach`,
		not crossed(point(yaw, -4, -8, 1), point(yaw, 4, -8, 1))
	)

	check(
		`{label}: crossing just inside the opening's edge IS a breach`,
		crossed(point(yaw, -4, 4.5, 1), point(yaw, 4, 4.5, 1))
	)

	-- NOT A CROSSING: over the top, or under the floor.
	check(
		`{label}: passing over the barrier is not a breach`,
		not crossed(point(yaw, -4, 0, 14), point(yaw, 4, 0, 14))
	)

	check(
		`{label}: passing below the doorway floor is not a breach`,
		not crossed(point(yaw, -4, 0, -3), point(yaw, 4, 0, -3))
	)

	check(
		`{label}: passing just under the barrier's top IS a breach`,
		crossed(point(yaw, -4, 0, 11), point(yaw, 4, 0, 11))
	)

	-- A stationary character is never a crossing, wherever it stands.
	check(
		`{label}: standing still in the doorway is not a crossing`,
		not crossed(point(yaw, 0, 0, 1), point(yaw, 0, 0, 1))
	)

	check(
		`{label}: standing still outside is not a crossing`,
		not crossed(point(yaw, -4, 0, 1), point(yaw, -4, 0, 1))
	)
end

--------------------------------------------------------------------------------
-- THE CLOCK. `isLive` is strict on the expiry instant and `secondsRemaining` never goes negative.
--------------------------------------------------------------------------------

do
	local barrier = barrierAt(0)

	check("a barrier before its expiry is live", GarlicBarrier.isLive(barrier, 99))
	check("a barrier exactly at its expiry is NOT live", not GarlicBarrier.isLive(barrier, 100))
	check("a barrier past its expiry is not live", not GarlicBarrier.isLive(barrier, 101))

	check(
		"secondsRemaining counts down",
		GarlicBarrier.secondsRemaining(barrier, 85) == 15,
		`{GarlicBarrier.secondsRemaining(barrier, 85)}`
	)

	check(
		"secondsRemaining is zero exactly at expiry",
		GarlicBarrier.secondsRemaining(barrier, 100) == 0
	)

	check(
		"secondsRemaining floors at zero rather than going negative",
		GarlicBarrier.secondsRemaining(barrier, 130) == 0,
		`{GarlicBarrier.secondsRemaining(barrier, 130)}`
	)
end

--------------------------------------------------------------------------------
-- PURITY. Same input, same answer; and neither the barrier nor the samples are written through.
--------------------------------------------------------------------------------

do
	local barrier = barrierAt(0)
	local from: Vec3 = { X = 0, Y = 1, Z = -4 }
	local to: Vec3 = { X = 0, Y = 1, Z = 4 }

	local first = GarlicBarrier.crossed(barrier, from, to, TOLERANCE)
	local second = GarlicBarrier.crossed(barrier, from, to, TOLERANCE)

	check("crossed is deterministic", first == second)
	check(
		"crossed does not mutate its inputs",
		barrier.X == 0
			and barrier.Yaw == 0
			and barrier.HalfWidth == 4.65
			and from.Z == -4
			and to.Z == 4
	)
end

--------------------------------------------------------------------------------
-- AUTHORITY. Separate from liveness, and the separation is a bug fix: a barrier is in the server's
-- list the instant a placement resolves, but the Aswang's client cannot build its collidable part
-- until the snapshot has crossed the wire. Enforcing inside that window corrects an honest player
-- who had nothing to be stopped by — §4.6's forbidden rubber-band, produced by the game itself.
--------------------------------------------------------------------------------

do
	local barrier = barrierAt(0)
	local GRACE = 1

	check(
		"a barrier is NOT authoritative at the instant it is created",
		not GarlicBarrier.isAuthoritative(barrier, 0, GRACE)
	)

	check(
		"a barrier is not authoritative part-way through its grace",
		not GarlicBarrier.isAuthoritative(barrier, GRACE / 2, GRACE)
	)

	check(
		"a barrier IS authoritative exactly at the end of its grace",
		GarlicBarrier.isAuthoritative(barrier, GRACE, GRACE)
	)

	check(
		"a barrier is authoritative after its grace",
		GarlicBarrier.isAuthoritative(barrier, GRACE + 5, GRACE)
	)

	-- A zero grace is the pre-fix behaviour, and it must still be expressible: the guard is a Config
	-- number, and a suite that only passes at one value pins the value rather than the rule.
	check("a zero grace is authoritative immediately", GarlicBarrier.isAuthoritative(barrier, 0, 0))

	--[[
		AUTHORITY AND LIVENESS ARE INDEPENDENT, asserted directly because collapsing them is the
		obvious "simplification" a later reader will reach for. A barrier can be live and not yet
		authoritative (the window this fix exists for), and — with a grace longer than the duration —
		authoritative and no longer live.
	]]
	check(
		"live but not yet authoritative is a real state",
		GarlicBarrier.isLive(barrier, 0) and not GarlicBarrier.isAuthoritative(barrier, 0, GRACE)
	)

	check(
		"expired but authoritative is a real state",
		not GarlicBarrier.isLive(barrier, 150)
			and GarlicBarrier.isAuthoritative(barrier, 150, GRACE)
	)
end

--------------------------------------------------------------------------------
-- SIDE. Signed, and it is NOT a breach test — the plane is infinite. `ItemService` uses it only to
-- ask whether an already-confirmed breach has been walked back. A correction driven by side alone
-- would restore an Aswang standing inside the chapel having entered through its other door.
--------------------------------------------------------------------------------

for _, yaw in { 0, math.pi / 2 } do
	local label = if yaw == 0 then "yaw 0" else "yaw 90"
	local barrier = barrierAt(yaw)

	check(
		`{label}: a point on the negative side reports negative`,
		GarlicBarrier.sideOf(barrier, point(yaw, -5, 0, 1)) < 0
	)

	check(
		`{label}: a point on the positive side reports positive`,
		GarlicBarrier.sideOf(barrier, point(yaw, 5, 0, 1)) > 0
	)

	check(
		`{label}: a point on the plane reports zero`,
		math.abs(GarlicBarrier.sideOf(barrier, point(yaw, 0, 0, 1))) < 1e-9,
		`{GarlicBarrier.sideOf(barrier, point(yaw, 0, 0, 1))}`
	)

	--[[
		THE CHAPEL CASE, WRITTEN AS AN ASSERTION RATHER THAN AS A COMMENT. Far along the opening's own
		axis — around the house, nowhere near the doorway — still reports a side, because the plane is
		infinite. This is exactly why `sideOf` must never gate a correction on its own.
	]]
	check(
		`{label}: a point far outside the opening still reports a side`,
		GarlicBarrier.sideOf(barrier, point(yaw, 5, 500, 1)) > 0
	)

	check(
		`{label}: side is independent of height`,
		GarlicBarrier.sideOf(barrier, point(yaw, 5, 0, 1))
			== GarlicBarrier.sideOf(barrier, point(yaw, 5, 0, 900))
	)
end

--------------------------------------------------------------------------------
-- SUPPRESSION — THE BLOCK ITSELF, and the reason it replaced a collidable wall.
--
-- A character held against a CanCollide part reports `Humanoid.MoveDirection` of (-1, 0, -0) while a
-- still one reports (0, 0, 0) — measured server-side off a live character, reproduced across two
-- approach angles. That property replicates to every client, so the wall made §4.6's loyalty test a
-- perfect oracle. The movement is now never issued, so MoveDirection reads what a player walking
-- somewhere else reads, because that is what it is.
--
-- THE CASES THAT MUST RETURN THE MOVE UNCHANGED ARE THE LOAD-BEARING HALF. Suppressing where it does
-- not belong is a LOUDER tell than the one being removed: a monster that cannot walk down the outside
-- of a house is more legible than one pressed against a doorway.
--------------------------------------------------------------------------------

for _, yaw in { 0, math.pi / 2 } do
	local label = if yaw == 0 then "yaw 0" else "yaw 90"
	local barrier = barrierAt(yaw)
	local MARGIN = 3.5

	-- A move expressed in the doorway's own frame, so a case reads the same at both yaws.
	local function move(n: number, l: number): Vec3
		local c, s = math.cos(yaw), math.sin(yaw)
		return { X = l * c + n * -s, Y = 0, Z = l * s + n * c }
	end

	local function suppressed(at: Vec3, m: Vec3): Vec3
		return GarlicBarrier.suppress(barrier, at, m, MARGIN)
	end

	-- Component of a vector along the crossing normal, for asserting what survived.
	local function normalPart(v: Vec3): number
		local c, s = math.cos(yaw), math.sin(yaw)
		return v.X * -s + v.Z * c
	end

	local function lateralPart(v: Vec3): number
		local c, s = math.cos(yaw), math.sin(yaw)
		return v.X * c + v.Z * s
	end

	--[[
		THE BLOCK IS A FULL STOP, AND THE THREE ASSERTIONS BELOW ARE WHY IT IS NOT A SLIDE.

		Subtracting only the inward component — the first design — left a vector whose normal component
		was identically zero and whose magnitude was `|cos t|`. Both are readable off a replicated
		property, so an Aswang sliding along a doorway published a signature no ordinary input can
		produce. The zero vector is the ONLY output measured indistinguishable from standing still
		(300 frames against 300). Asserting the whole vector, not just its normal part, is what stops
		that regressing.
	]]
	do
		local out = suppressed(point(yaw, -2, 0, 1), move(1, 0))

		check(
			`{label}: walking into the doorway stops the character entirely`,
			out.X == 0 and out.Y == 0 and out.Z == 0,
			`{out.X}, {out.Y}, {out.Z}`
		)
	end

	do
		local out = suppressed(point(yaw, -2, 0, 1), move(1, 1))

		check(
			`{label}: a diagonal into the doorway also stops entirely — no residual slide`,
			out.X == 0 and out.Y == 0 and out.Z == 0,
			`{out.X}, {out.Y}, {out.Z}`
		)
	end

	--[[
		THE MAGNITUDE PROPERTY, STATED DIRECTLY. A keyboard emits a `MoveDirection` of magnitude 0 or 1
		and nothing between. Any suppressed output must therefore be exactly 0 or exactly the input —
		a value strictly inside (0, 1) identifies its owner as standing next to garlic.
	]]
	for _, angleDeg in { 15, 30, 45, 60, 75 } do
		local rad = math.rad(angleDeg)
		local out = suppressed(point(yaw, -2, 0, 1), move(math.cos(rad), math.sin(rad)))
		local magnitude = math.sqrt(out.X * out.X + out.Y * out.Y + out.Z * out.Z)

		check(
			`{label}: a {angleDeg}-degree approach yields magnitude 0, never a fraction`,
			magnitude == 0,
			`magnitude {magnitude}`
		)
	end

	-- FROM THE OTHER SIDE, symmetrically. An Aswang sealed INSIDE a house cannot walk out either.
	do
		local out = suppressed(point(yaw, 2, 0, 1), move(-1, 0))

		check(
			`{label}: walking in from the far side also stops entirely`,
			out.X == 0 and out.Y == 0 and out.Z == 0,
			`{out.X}, {out.Y}, {out.Z}`
		)
	end

	-- MOVING AWAY IS NEVER TOUCHED. The monster must be able to leave.
	do
		local m = move(-1, 0)
		local out = suppressed(point(yaw, -2, 0, 1), m)

		check(
			`{label}: moving away from the doorway is unchanged`,
			math.abs(normalPart(out) - normalPart(m)) < 1e-9,
			`normal component {normalPart(out)}`
		)
	end

	-- MOVING ALONG THE WALL IS NEVER TOUCHED.
	do
		local m = move(0, 1)
		local out = suppressed(point(yaw, -2, 0, 1), m)

		check(
			`{label}: moving along the wall is unchanged`,
			math.abs(lateralPart(out) - 1) < 1e-9 and math.abs(normalPart(out)) < 1e-9
		)
	end

	--[[
		THE FOUR REFUSALS. Each returns the move untouched, and each is a place where suppressing
		would be a louder tell than the leak it removes — a monster that cannot walk down the outside
		of a house, or cannot cross a field two hundred studs away on the same infinite plane.
	]]
	do
		local m = move(1, 0)

		check(
			`{label}: beyond the margin, nothing is suppressed`,
			math.abs(normalPart(suppressed(point(yaw, -(MARGIN + 0.1), 0, 1), m)) - 1) < 1e-9
		)

		check(
			`{label}: just inside the margin, it IS suppressed`,
			math.abs(normalPart(suppressed(point(yaw, -(MARGIN - 0.1), 0, 1), m))) < 1e-9
		)

		check(
			`{label}: outside the opening's width, nothing is suppressed — the plane is infinite`,
			math.abs(normalPart(suppressed(point(yaw, -2, 8, 1), m)) - 1) < 1e-9
		)

		check(
			`{label}: far down the wall, nothing is suppressed`,
			math.abs(normalPart(suppressed(point(yaw, -2, 500, 1), m)) - 1) < 1e-9
		)

		check(
			`{label}: above the barrier, nothing is suppressed`,
			math.abs(normalPart(suppressed(point(yaw, -2, 0, 14), m)) - 1) < 1e-9
		)

		check(
			`{label}: below the doorway floor, nothing is suppressed`,
			math.abs(normalPart(suppressed(point(yaw, -2, 0, -3), m)) - 1) < 1e-9
		)
	end

	--[[
		STANDING EXACTLY ON THE PLANE. Reachable when a barrier is created around a character, and the
		one case where no side can be picked — so the whole normal component goes, in either direction.
	]]
	do
		check(
			`{label}: on the plane, an inward move is suppressed`,
			math.abs(normalPart(suppressed(point(yaw, 0, 0, 1), move(1, 0)))) < 1e-9
		)

		check(
			`{label}: on the plane, the opposite move is also suppressed`,
			math.abs(normalPart(suppressed(point(yaw, 0, 0, 1), move(-1, 0)))) < 1e-9
		)
	end

	-- A ZERO MOVE STAYS ZERO. A standing player must never be given motion by this function.
	do
		local out = suppressed(point(yaw, -1, 0, 1), { X = 0, Y = 0, Z = 0 })

		check(
			`{label}: a zero move stays exactly zero`,
			out.X == 0 and out.Y == 0 and out.Z == 0,
			`{out.X}, {out.Y}, {out.Z}`
		)
	end

	-- PURITY. The inputs are not written through.
	do
		local at = point(yaw, -2, 0, 1)
		local m = move(1, 0)
		local mx, mz = m.X, m.Z

		GarlicBarrier.suppress(barrier, at, m, MARGIN)

		check(`{label}: suppress does not mutate its move`, m.X == mx and m.Z == mz)
	end
end

if failures > 0 then
	error(`{failures} garlic-barrier assertion(s) failed`, 0)
end

print(
	`  PASS  garlic-barrier: {checked} assertions over yaw x crossing x width x height x clock x authority x side x suppression`
)
