--!strict
--[[
	ItemThrow — did this throw hit? (§4.6, V08)

		evaluate(request) -> verdict                                      the whole round question
		inCone(from, direction, target, range, coneDegrees) -> boolean    the aim, shared with C22

	MIGRATED FROM `pure/SaltThrow` (C14) WITH ITS GEOMETRY UNCHANGED. `inCone` below is byte-for-byte
	what C14 shipped and what `tests/item-throw.test.luau` inherited ~40 assertions about. What
	changed at V08 is the CARRY input: a slot holding one of three item types, not a pouch count.

	THE CLIENT NEVER DECIDES A HIT. It sends a direction; this module, called on the server, decides.
	That sentence was C14's whole brief and it is why there is no `Hit: boolean` in the request.

	WHAT COUNTS AS A HIT, AND THE FIVE THINGS THAT DO NOT
	----------------------------------------------------
	A hit requires a TRANSFORMED Aswang, inside `Range`, inside the cone, thrown by someone holding
	SALT. Everything else is MISS, and MISS IS ONE VALUE ON PURPOSE:

	  · nothing in the cone
	  · a survivor in the cone
	  · the Aswang in the cone, NOT transformed
	  · the Aswang in the cone, transformed, past Range
	  · V08 — the thrower is holding a BAWANG or a BUNTOT_PAGI

	Splitting them is the obvious refactor and it hands over the game. `MISS_NOT_ASWANG` beside
	`MISS_OUT_OF_RANGE` lets a compromised client stand in front of each player in turn and read the
	monster off the refusal shape — for the price of one pouch, which is what §4.6 charges for an
	HONEST reveal. See Types.SaltVerdict; the handler echoes nothing regardless, but a verdict that
	could be echoed safely is the property worth having, and this one has it.

	THE FIFTH WORLD IS NEW AND IT IS THE ONE MOST LIKELY TO BE SPLIT OUT. Do not. AND THE FIFTH IS
	WORSE THAN THE OTHER FOUR IF SPLIT, because it is knowable to the thrower already: you know what
	you are holding. A `MISS_WRONG_ITEM` therefore looks harmless — it tells the thrower nothing new
	— right up until a client uses its ABSENCE as the oracle: throw while holding salt, and a refusal
	that is NOT `MISS_WRONG_ITEM` is a refusal about the target. The empty slot is answered
	separately and above the geometry (`ITEM_NO_ITEM`) precisely because that one depends only on the
	thrower and is knowable without a target; the wrong-ITEM case is not, because reaching it means a
	target was evaluated.

	WHY UNTRANSFORMED IS A MISS RATHER THAN A WEAKER HIT (C14, unchanged). §4.6 says salt "forces
	revert", which only means something for a transformed target. Making salt work on a human-shaped
	Aswang turns four pouches into four free identity probes, and the closest thing this repo has to a
	rule about that is the deleted task-weight rule's: no mechanic's OBSERVABLE OUTCOME may vary by
	role. Here it varies by FORM, and the form is already public — `MonsterTransformed` broadcasts it
	to everyone by design.

	WHY `src/shared/pure/` IS SAFE FOR THIS, which is a fair question given the above. The module is
	callable by any client and reading it teaches an attacker the rule — but the rule is in the spec,
	in this comment, and visible in one round of play. What a client cannot obtain is the INPUT
	`TargetIsTransformedAswang`, which exists only in server memory (`monsters[userId].Transformed`
	and `RoundService.GetAswangUserId()`). Logic is not secret; inputs are. There is no seed here at
	all — and V08's new input, `Held`, is the requesting client's OWN slot and therefore already
	known to it.

	NO `script.Parent` REQUIRES and no Roblox datatypes — Vec3 is a plain table, converted at the call
	site exactly as KillValidation's is.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

-- `ITEM_NO_ITEM` REPLACES C14's `NO_POUCH`. Same position in the order, same meaning: the thrower
-- has nothing to throw. It stays ABOVE the geometry because it depends only on the thrower, so it
-- is the same answer for every candidate and cannot be differenced against a target.
export type Verdict = "OK" | "ITEM_WRONG_PHASE" | "ITEM_THROWER_NOT_ALIVE" | "ITEM_NO_ITEM" | "MISS"

export type Vec3 = { X: number, Y: number, Z: number }

export type Request = {
	Phase: RoundPhase,
	ThrowerState: PlayerState,
	-- V08. The slot's occupant, or nil. `SALT` is the only value that can produce OK; the other two
	-- fall through to MISS with the geometry, deliberately, per the header's fifth world.
	Held: ItemType?,
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

local ItemThrow = {}

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
	ORDER IS FIXED AND IS PART OF THE CONTRACT. World facts, then the thrower, then the item, then
	geometry — the identical ordering KillValidation uses and for the identical reason: geometry is the
	only condition an honest player hits routinely, so a log full of MISS is a UX finding and a log full
	of anything above it is a security finding.

	NOTE WHAT IS NOT IN THE ORDER: there is no cooldown. §4.6 gives the items no recharge and no
	cadence — scarcity IS the limiter, and `Config.AntiCheat.Budgets.RequestThrowSalt` bounds the
	request rate regardless. A cooldown here would be a fifth number nobody tuned.
]]
--[[
	THE AIM, SPLIT OUT SO TWO CALLERS CAN SHARE IT WITHOUT SHARING THE ROUND'S RULES.

	`evaluate` above answers a ROUND question — right phase, alive thrower, holding salt, and the
	target is the transformed Aswang — and then asks this. C21's Solo Trial needs only this half: it
	runs at IDLE against a scripted rig, so every one of those round preconditions is either false or
	meaningless there, and the trial establishes its own (you are in a session, the rig exists).

	Extracted rather than duplicated, and rather than having the trial pass `Phase = "ACTIVE"` to get
	past a gate it does not mean. THE POINT IS THAT THE TUTORIAL TEACHES THE REAL AIM: same range,
	same cone, same feel, one implementation. A second copy would drift, and the throw a player
	learned in the tutorial would stop being the throw that works in a round — which is the entire
	reason C22 teaches it by doing. V08 renamed the module and changed NOTHING about this function.

	Returns false for every degenerate input rather than erroring: a zero direction, a NaN distance,
	an infinite range, a cone at or past 90 degrees (which would hit what is behind the thrower).
]]
function ItemThrow.inCone(
	from: Vec3,
	direction: Vec3,
	target: Vec3,
	range: number,
	coneDegrees: number
): boolean
	if not (range > 0 and range < math.huge) then
		return false
	end

	local toTarget = sub(target, from)
	local distance = magnitude(toTarget)

	if not (distance >= 0 and distance < math.huge) or distance > range then
		return false
	end

	local aim = normalise(direction)
	local bearing = normalise(toTarget)

	if aim == nil or bearing == nil then
		return false
	end

	--[[
		A HALF-ANGLE IN DEGREES, COMPARED AS A COSINE. `math.cos` is monotonically decreasing over
		[0, pi], so "inside the cone" is `dot >= cos(halfAngle)` — no `math.acos`, which is the call
		that would need its own domain guard for a dot product that floating-point error pushed to
		1.0000001.

		Clamped to (0, 90) rather than trusted: `tests/config.test.luau` pins the Config value in that
		range, and this module is called with numbers rather than with Config, so it re-checks. A
		half-angle of 90 or more means a throw hits what is behind you. THE CLAMP IS A DOMAIN GUARD,
		NOT A TUNABLE, and stays hardcoded — `check:config` must not be appeased by moving it.
	]]
	if not (coneDegrees > 0 and coneDegrees < 90) then
		return false
	end

	return dot(aim, bearing) >= math.cos(math.rad(coneDegrees))
end

function ItemThrow.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "ITEM_WRONG_PHASE"
	end

	-- ALLOWLIST of ALIVE. A dead player throwing salt is this bug's shape, and the denylist form
	-- admits them the moment anything gives a dead player a body and a position.
	if request.ThrowerState ~= "ALIVE" then
		return "ITEM_THROWER_NOT_ALIVE"
	end

	--[[
		AN EMPTY HAND IS ANSWERED HERE; THE WRONG ITEM IS NOT. The distinction is the header's, and
		it is the single most important line in this migration.

		Empty depends only on the thrower, so every candidate gets the same answer and there is
		nothing to difference. The wrong ITEM would also be knowable to an honest thrower — but a
		verdict only reachable AFTER a target was considered can be used in the negative, so it is
		collapsed into MISS below with the other four worlds.

		C14's NaN and infinity guards are gone with the number they guarded. `Held` is an optional
		string assigned from `SearchService.ItemFound`; there is no arithmetic left to poison.
	]]
	if request.Held == nil then
		return "ITEM_NO_ITEM"
	end

	--[[
		EVERYTHING BELOW THIS LINE RETURNS MISS. Not "returns one of several geometric refusals" —
		MISS, one value, for FIVE different worlds now. See the header. A future edit that wants to
		know WHY a throw missed should add a second, SERVER-ONLY return value; it must not widen
		this union.
	]]
	if request.Held ~= "SALT" then
		return "MISS"
	end

	if not request.TargetIsTransformedAswang then
		return "MISS"
	end

	if
		not ItemThrow.inCone(
			request.ThrowerPos,
			request.Direction,
			request.TargetPos,
			request.Range,
			request.ConeDegrees
		)
	then
		return "MISS"
	end

	return "OK"
end

return ItemThrow
