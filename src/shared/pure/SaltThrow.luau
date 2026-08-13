--!strict
--[[
	SaltThrow — did this throw hit? (§4.6, C14)

		(request) -> verdict

	THE CLIENT NEVER DECIDES A HIT. It sends a direction; this module, called on the server, decides.
	That sentence is C14's whole brief and it is why there is no `Hit: boolean` anywhere in the request.

	WHAT COUNTS AS A HIT, AND THE FOUR THINGS THAT DO NOT
	----------------------------------------------------
	A hit requires a TRANSFORMED Aswang, inside `Range`, inside the cone. Everything else is MISS, and
	MISS IS ONE VALUE ON PURPOSE:

	  · nothing in the cone
	  · a survivor in the cone
	  · the Aswang in the cone, NOT transformed
	  · the Aswang in the cone, transformed, past Range

	Splitting them is the obvious refactor and it hands over the game. `MISS_NOT_ASWANG` beside
	`MISS_OUT_OF_RANGE` lets a compromised client stand in front of each player in turn and read the
	monster off the refusal shape — for the price of one pouch, which is what §4.6 charges for an
	HONEST reveal. See Types.SaltVerdict; the handler echoes nothing regardless, but a verdict that
	could be echoed safely is the property worth having, and this one has it.

	WHY UNTRANSFORMED IS A MISS RATHER THAN A WEAKER HIT. §4.6 says salt "forces revert", which only
	means something for a transformed target. Making salt work on a human-shaped Aswang turns four
	pouches into four free identity probes, and the closest thing this repo has to a rule about that is
	`pure/TaskWeight`'s: no mechanic's OBSERVABLE OUTCOME may vary by role. Here it varies by FORM, and
	the form is already public — `MonsterTransformed` broadcasts it to everyone by design.

	WHY `src/shared/pure/` IS SAFE FOR THIS, which is a fair question given the above. The module is
	callable by any client and reading it teaches an attacker the rule — but the rule is in the spec, in
	this comment, and visible in one round of play. What a client cannot obtain is the INPUT
	`TargetIsTransformedAswang`, which exists only in server memory (`monsters[userId].Transformed` and
	`RoundService.GetAswangUserId()`). Logic is not secret; inputs are. There is no seed here at all.

	NO `script.Parent` REQUIRES and no Roblox datatypes — Vec3 is a plain table, converted at the call
	site exactly as KillValidation's is.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"

export type Vec3 = { X: number, Y: number, Z: number }

export type Request = {
	Phase: RoundPhase,
	ThrowerState: PlayerState,
	Carried: number,
	ThrowerPos: Vec3,
	-- Unit-length in the caller's intent, NOT trusted to be. `normalise` below handles any magnitude
	-- and refuses a zero vector, because a client sends this and a client can send Vector3.zero.
	Direction: Vec3,
	TargetPos: Vec3,
	-- The one input a client cannot obtain. True only when the target IS the Aswang AND is currently
	-- in the transformed form; the caller ANDs those two, so this module never sees a role.
	TargetIsTransformedAswang: boolean,
	Range: number,
	ConeDegrees: number,
}

local SaltThrow = {}

local function sub(a: Vec3, b: Vec3): Vec3
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function magnitude(v: Vec3): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local function dot(a: Vec3, b: Vec3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

--[[
	Returns nil for a zero-length or non-finite vector rather than dividing by it.

	A NaN component reaches this from one place only — a client's `Direction` — and every comparison
	against NaN is false, so an un-normalised NaN direction would sail past the cone test as "not
	outside it". Refusing here is the same fail-closed shape KillValidation's cooldown arrived at after
	three attempts, applied to geometry.
]]
local function normalise(v: Vec3): Vec3?
	local length = magnitude(v)

	if not (length > 0 and length < math.huge) then
		return nil
	end

	return { X = v.X / length, Y = v.Y / length, Z = v.Z / length }
end

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT. World facts, then the thrower, then the pouch, then
	geometry — the identical ordering KillValidation uses and for the identical reason: geometry is the
	only condition an honest player hits routinely, so a log full of MISS is a UX finding and a log full
	of anything above it is a security finding.

	NOTE WHAT IS NOT IN THE ORDER: there is no cooldown. §4.6 gives salt no recharge and no cadence —
	scarcity IS the limiter, and `Config.AntiCheat.Budgets.RequestThrowSalt` bounds the request rate
	regardless. A cooldown here would be a fifth number nobody tuned.
]]
function SaltThrow.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	-- ALLOWLIST of ALIVE. A ghost throwing salt is C15's shape of this bug, and the denylist form
	-- admits them the moment Phase 6 gives a ghost a body and a position.
	if request.ThrowerState ~= "ALIVE" then
		return "THROWER_NOT_ALIVE"
	end

	--[[
		`< 1` refuses a NaN carry too, because `NaN < 1` is false — which would WRONGLY admit it. Guard
		the finite range explicitly rather than relying on this comparison, the same asymmetry
		`pure/SaltCarry` documents between its limit guard and its carried guard.
	]]
	if not (request.Carried >= 1 and request.Carried < math.huge) then
		return "NO_POUCH"
	end

	--[[
		EVERYTHING BELOW THIS LINE RETURNS MISS. Not "returns one of several geometric refusals" — MISS,
		one value, for four different worlds. See the header. A future edit that wants to know WHY a
		throw missed should add a second, server-only return value; it must not widen this union.
	]]
	if not request.TargetIsTransformedAswang then
		return "MISS"
	end

	if not (request.Range > 0 and request.Range < math.huge) then
		return "MISS"
	end

	local toTarget = sub(request.TargetPos, request.ThrowerPos)
	local distance = magnitude(toTarget)

	if not (distance >= 0 and distance < math.huge) or distance > request.Range then
		return "MISS"
	end

	local aim = normalise(request.Direction)
	local bearing = normalise(toTarget)

	if aim == nil or bearing == nil then
		return "MISS"
	end

	--[[
		A HALF-ANGLE IN DEGREES, COMPARED AS A COSINE. `math.cos` is monotonically decreasing over
		[0, pi], so "inside the cone" is `dot >= cos(halfAngle)` — no `math.acos`, which is the call
		that would need its own domain guard for a dot product that floating-point error pushed to
		1.0000001.

		Clamped to (0, 90) rather than trusted: `tests/config.test.luau` pins the Config value in that
		range, and this module is called with numbers rather than with Config, so it re-checks. A
		half-angle of 90 or more means a throw hits what is behind you.
	]]
	if not (request.ConeDegrees > 0 and request.ConeDegrees < 90) then
		return "MISS"
	end

	if dot(aim, bearing) < math.cos(math.rad(request.ConeDegrees)) then
		return "MISS"
	end

	return "OK"
end

return SaltThrow
