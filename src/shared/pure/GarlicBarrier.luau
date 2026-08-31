--!strict
--[[
	GarlicBarrier — the burn-out clock, and did something cross this doorway? (§4.6, V09)

		isLive(barrier, now) -> boolean
		isAuthoritative(barrier, now, grace) -> boolean
		secondsRemaining(barrier, now) -> number
		sideOf(barrier, point) -> number
		suppress(barrier, point, move, margin) -> Vec3
		crossed(barrier, from, to, tolerance) -> boolean

	`crossed`, `isLive`, `isAuthoritative` and `sideOf` ARE NOT THE BLOCK — `suppress` is. The block is
	a movement the Aswang's own client never issues (see `suppress` below and `GarlicController`).
	These four are the SERVER'S answer to "did it go through anyway", which is the only question left
	once the block lives on a machine the server does not control.

	IT WAS A COLLIDABLE PART ON THAT CLIENT UNTIL IT WAS MEASURED. A character held against one reports
	`Humanoid.MoveDirection` of `(-1, 0, -0)` where a still one reports `(0, 0, 0)` — a replicated
	property, readable off any peer, and therefore a perfect oracle for §4.6's loyalty test. That
	history is kept here because the numbers below are still sized for it.

	WHY THE SERVER NEEDS A PREDICATE AT ALL. A client that deletes its own barrier walks through. The
	server cannot see the barrier and cannot re-simulate the character, so the one thing it can do is
	compare two positions it DID see against a plane it owns. That is this function.

	THE TOLERANCE IS THE HALF THAT MATTERS AND IT ONLY EVER MAKES THE ANSWER `false`. §4.6's
	blockquote forbids the barrier playing any effect on the monster, and a server correction that
	rubber-bands IS an effect. So a crossing is only reported when the destination is more than
	`tolerance` PAST the plane: a character standing in the threshold, or drifting across it under lag,
	is not a breach. This fails toward doing nothing, deliberately, and the cost of a false negative is
	at most fifteen seconds of a doorway.

	IT DOES NOT PROTECT AGAINST "A SHOVE FROM A CORPSE", WHICH AN EARLIER VERSION OF THIS COMMENT
	CLAIMED. Corpses are `Anchored = true, CanCollide = false` (`MonsterService.makeCorpse`), so they
	cannot push anybody anywhere. The vector that IS real is the one that comment did not name: the
	server enforcing a barrier the client has not built yet — see `isAuthoritative`.

	NOTHING HERE IS SECRET AND THERE IS NO SEED. The barrier's position is a garlic bulb every client
	can see on a doorway every client can walk to; the two positions are the SERVER'S samples of a
	character that replicates anyway. A client that requires and runs this module learns geometry it
	is already looking at, which is CLAUDE.md's test applied rather than assumed.

	ANGLES ARE RADIANS HERE AND DEGREES ON THE MAP. `barrio.luau` writes a `Yaw` attribute in degrees
	because that is what a human editing a layout reads; `ItemService` converts once, at the boundary.

	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table, converted at the
	call site, exactly as `pure/ItemThrow` does it.
]]

export type Vec3 = { X: number, Y: number, Z: number }

--[[
	`Y` IS THE DOORWAY'S FLOOR, not its centre, and `Height` runs upward from it. A doorway's floor is
	what the map gives us (the anchor pad sits on it) and a centre would have to be derived from a
	height that is in Config, which would put the same number in two places.

	`ExpiresAt` IS ON THE SERVER'S CLOCK and never crosses to a client — `Types.GarlicBarrierSpec`
	carries a DURATION for that reason. This field exists so `isLive` has one comparison to make.

	`CreatedAt` EXISTS BECAUSE A BARRIER IS LIVE ON THE SERVER BEFORE IT EXISTS ON THE CLIENT, and that
	gap was a shipped bug. `ItemService` inserts the barrier the instant the placement resolves, but
	the Aswang's client cannot build its collidable part until `GarlicBarriers` has crossed the wire
	and `rebuild` has run — one network round trip later. In between, the server would enforce a wall
	the monster has no way to be stopped by, and the correction fires on a completely honest player at
	the exact moment a survivor places garlic in a doorway they are walking through. That is the
	rubber-band §4.6's blockquote forbids, produced against someone who did nothing wrong, in front of
	the witnesses the loyalty test gathered. See `isAuthoritative`.
]]
export type Barrier = {
	X: number,
	Y: number,
	Z: number,
	Yaw: number,
	HalfWidth: number,
	Height: number,
	CreatedAt: number,
	ExpiresAt: number,
}

local GarlicBarrier = {}

--[[
	THE TWO AXES, AND THE CONVENTION IS `barrio.luau`'S RATHER THAN AN INVENTED ONE.

	`along` is the direction the doorway's WIDTH runs; `normal` is the direction you cross. At yaw 0
	`along` is +X and `normal` is +Z, which is a door in an N or S wall; at 90 degrees they swap,
	which is a door in an E or W wall. The builder writes `yaw = if nx ~= 0 then 90 else 0` on exactly
	that reading, so the two files agree by construction rather than by a comment.
]]
local function axes(yaw: number): (Vec3, Vec3)
	local c, s = math.cos(yaw), math.sin(yaw)

	return { X = c, Y = 0, Z = s }, { X = -s, Y = 0, Z = c }
end

local function planarDot(a: Vec3, b: Vec3): number
	return a.X * b.X + a.Z * b.Z
end

function GarlicBarrier.isLive(barrier: Barrier, now: number): boolean
	return now < barrier.ExpiresAt
end

--[[
	MAY THE SERVER ENFORCE THIS BARRIER YET? Distinct from `isLive`, and the distinction is a bug fix.

	`isLive` answers "has it burned out", which is about the GARLIC. This answers "has the Aswang's
	client had time to build it", which is about the NETWORK — and enforcing before that is true
	corrects an honest player who was never given anything to be stopped by. `grace` is
	`GarlicBreachGraceSeconds`, sized for a round trip plus one sample interval.

	IT ONLY EVER DELAYS ENFORCEMENT, never extends it: a cheater still has to cross some interval in
	which the barrier is both live and authoritative, and a barrier that is not yet authoritative is
	also not yet crossable by anyone honest, because the bulb is already visible.
]]
function GarlicBarrier.isAuthoritative(barrier: Barrier, now: number, grace: number): boolean
	return now >= barrier.CreatedAt + grace
end

-- Floored at zero so a barrier the sweep has not reached yet never sends a negative duration to a
-- client, which would render as a wall that is already gone.
function GarlicBarrier.secondsRemaining(barrier: Barrier, now: number): number
	return math.max(0, barrier.ExpiresAt - now)
end

--[[
	WHICH SIDE OF THE DOORWAY'S PLANE IS THIS POINT ON? Signed distance along the crossing normal;
	negative and positive are the two sides and exactly zero is the plane itself.

	IT IS NOT A BREACH TEST AND MUST NEVER BE USED AS ONE. The plane is INFINITE and a doorway is a
	hole in one wall, so "on the far side" is true of a great deal of the barrio — including, at the
	chapel, of standing inside it having walked in through the OTHER door. A correction driven by
	side alone would restore that player forever. `crossed` is the breach test because it also
	requires the crossing point to fall inside the opening; this function exists only so
	`ItemService` can tell whether an ALREADY-CONFIRMED breach has been walked back.
]]
function GarlicBarrier.sideOf(barrier: Barrier, point: Vec3): number
	local _, normal = axes(barrier.Yaw)

	return planarDot({ X = point.X - barrier.X, Y = 0, Z = point.Z - barrier.Z }, normal)
end

--[[
	DID A CHARACTER MOVE FROM ONE SIDE OF THIS DOORWAY TO THE OTHER, THROUGH THE OPENING?

	FOUR TESTS, AND EVERY ONE OF THEM CAN ONLY REFUSE:

	  1. A STRICT SIGN CHANGE. `dFrom * dTo >= 0` is not a crossing — which deliberately includes a
	     sample that landed exactly ON the plane, because a character standing in the threshold is the
	     honest case and must never be corrected.
	  2. THE DESTINATION IS PAST THE PLANE BY MORE THAN `tolerance`. See the header.
	  3. THE CROSSING POINT IS INSIDE THE OPENING'S WIDTH. Walking around the house and through a
	     different wall crosses the same infinite plane and is not a breach — this is the test that
	     makes the plane a doorway rather than a fence across the barrio.
	  4. THE CROSSING POINT IS UNDER THE BARRIER'S HEIGHT and at or above its floor. A character on a
	     roof passing over the doorway is not passing through it.
]]
function GarlicBarrier.crossed(barrier: Barrier, from: Vec3, to: Vec3, tolerance: number): boolean
	local along, normal = axes(barrier.Yaw)
	local centre: Vec3 = { X = barrier.X, Y = barrier.Y, Z = barrier.Z }

	local dFrom = planarDot({ X = from.X - centre.X, Y = 0, Z = from.Z - centre.Z }, normal)
	local dTo = planarDot({ X = to.X - centre.X, Y = 0, Z = to.Z - centre.Z }, normal)

	if dFrom * dTo >= 0 then
		return false
	end

	if math.abs(dTo) <= tolerance then
		return false
	end

	-- Where along the segment the plane was met. The denominator cannot be zero: the sign test above
	-- already proved the two are strictly opposite, so they differ.
	local t = dFrom / (dFrom - dTo)
	local at: Vec3 = {
		X = from.X + (to.X - from.X) * t,
		Y = from.Y + (to.Y - from.Y) * t,
		Z = from.Z + (to.Z - from.Z) * t,
	}

	local lateral = planarDot({ X = at.X - centre.X, Y = 0, Z = at.Z - centre.Z }, along)

	if math.abs(lateral) > barrier.HalfWidth then
		return false
	end

	return at.Y >= centre.Y and at.Y <= centre.Y + barrier.Height
end

--[[
	V09, §4.6. THE BLOCK ITSELF: REMOVE THE PART OF A MOVEMENT THAT WOULD CARRY YOU THROUGH A DOORWAY.

	THIS REPLACED A COLLIDABLE WALL BECAUSE THE WALL WAS NOT SILENT, AND THAT WAS MEASURED. A character
	held against a `CanCollide` part reports `Humanoid.MoveDirection` of `(-1, 0, -0)`; one standing
	still reports `(0, 0, 0)`. `MoveDirection` is an ordinarily replicated Humanoid property, so any
	client can read it off a peer — and §4.6's loyalty test becomes a perfect oracle. The engine
	computes it from held input rather than from whether the motion succeeded, so nothing on the
	client could suppress it AFTER the fact. The movement has to never be issued.

	WHICH IS THE SPEC'S OWN SENTENCE, READ LITERALLY: "its movement simply does not carry it through."
	Not "it is stopped" — not carried. The Aswang's client asks this function what it is allowed to
	do and issues that instead, so `MoveDirection` reads exactly what a player who chose to walk
	somewhere else reads, because that is what it is.

	IT RETURNS A FULL STOP, NOT A SLIDE, AND THAT REVERSES AN EARLIER DECISION FOR A MEASURED REASON.

	The first version subtracted the component into the doorway and kept the rest, so the Aswang slid
	along an opening it could not enter — on the reasoning that halting dead at a threshold is its own
	tell. **That slide was a role oracle.** Subtracting a component leaves a vector whose component
	along the doorway normal is IDENTICALLY ZERO and whose magnitude is `|cos t|` for a unit input, so
	an Aswang inside the margin published, every frame, a `MoveDirection` that was axis-pinned to a
	doorway and possibly non-unit — where a refusing player's varies continuously with their camera
	and a keyboard emits only 0 or 1. The axis-pinning survives renormalisation.

	THE ZERO VECTOR IS THE ONE STATE THAT HAS BEEN MEASURED SILENT: 300 frames blocked against 300
	frames voluntarily still, both 0 non-zero `MoveDirection` frames, read server-side at 60fps.

	AND THE "DEAD STOP IS A TELL" ARGUMENT WAS WRONG ON ITS OWN TERMS. §4.6's whole design is that a
	survivor may decline to walk in for any reason — so a character that stops at a threshold reads as
	one that chose not to enter, which is precisely the bluff the loyalty test is supposed to permit.
	Stopping is the indistinguishable behaviour, not the conspicuous one.

	FOUR REFUSALS, AND EACH ONE RETURNS THE MOVE UNCHANGED — these are the load-bearing half. Stopping
	the monster where it does not belong is a LOUDER tell than the one this removes: a character that
	cannot walk down the outside of a house is far more legible than one pressed against a doorway.

	  1. TOO FAR FROM THE PLANE. Beyond `margin` this barrier is not the Aswang's problem yet.
	  2. OUTSIDE THE OPENING'S WIDTH. The plane is infinite and a doorway is a hole in one wall —
	     suppressing out here would stop the monster walking down the outside of a house, which is a
	     far louder tell than the one this whole function exists to remove.
	  3. ABOVE OR BELOW THE BARRIER. Same reasoning, vertically.
	  4. MOVING AWAY FROM, OR ALONG, THE PLANE. Only motion INTO the doorway is removed.

	`margin` MUST EXCEED THE CHARACTER'S HULL RADIUS or the character reaches the barrier anyway and
	the signature comes back. See `Config.Items.GarlicSuppressMarginStuds`.
]]
function GarlicBarrier.suppress(barrier: Barrier, point: Vec3, move: Vec3, margin: number): Vec3
	local along, normal = axes(barrier.Yaw)

	local offset: Vec3 = { X = point.X - barrier.X, Y = 0, Z = point.Z - barrier.Z }
	local distance = planarDot(offset, normal)

	if math.abs(distance) > margin then
		return move
	end

	if math.abs(planarDot(offset, along)) > barrier.HalfWidth then
		return move
	end

	if point.Y < barrier.Y or point.Y > barrier.Y + barrier.Height then
		return move
	end

	local into = planarDot(move, normal)

	--[[
		WHICH DIRECTION IS "INTO"? The side the Aswang is standing on decides it: from the negative
		side, a positive component crosses. Exactly ON the plane both directions cross, so the whole
		normal component goes — that case is reachable when a barrier appears around a character and
		is the one place this function may not pick a side.
	]]
	if distance < 0 and into <= 0 then
		return move
	end

	if distance > 0 and into >= 0 then
		return move
	end

	--[[
		A FULL STOP. NOT `move - normal * into`, which is what this used to be and what leaked: that
		leaves the normal component at exactly zero and the magnitude at `|cos t|`, both of which are
		readable off a replicated property by any client. The zero vector is the only output measured
		indistinguishable from a player standing still.
	]]
	return { X = 0, Y = 0, Z = 0 }
end

return GarlicBarrier
