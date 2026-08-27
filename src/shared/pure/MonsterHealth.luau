--!strict
--[[
	MonsterHealth — the tug-of-war, as arithmetic. (V05, §4.6)

		apply(health, event, tuning) -> health'
		isWeakened(health, tuning) -> boolean
		weakenedFraction(health, tuning) -> 0..1

	§4.6: "the survivors' progress toward killing it and the Aswang's progress toward killing them
	are the same resource, pulling in opposite directions." This module is that resource and nothing
	else. It owns no player, no clock, no Instance, and no decision about WHETHER a salt hit landed —
	`ItemService` decides that (V08) and `MonsterService` owns the number between calls.

	WHY `src/shared/pure/` IS SAFE HERE, which V03 answered the other way. The rule is about INPUTS.
	`ContainerLayout` is a DRAW: a client that can guess its seed knows where the buntot pagi is
	before the round starts, so it lives in `server/pure/`. This is a subtraction and a comparison
	over four numbers `Config.luau` already replicates to every client. A client that requires this
	module learns that salt takes 25 and stops at 25 — which §10's FTUE is going to TELL it in the
	tutorial. Logic is not secret; inputs are, and this module has no input a client supplies.

	WHAT IT DELIBERATELY DOES NOT CONTAIN: any notion of who the health belongs to. There is no
	player, no UserId and no role in the signature, so there is no arrangement of this module in
	which the health of one player is distinguishable from the health of another. That is structural
	rather than careful — `.claude/lessons/absence-is-observable.md` is the long version.

	THE FLOOR BELONGS TO THE SALT EVENT, NOT TO THE STATE. §4.6: salt is floored at
	WeakenedThreshold so that "salt alone can never kill" and the buntot pagi is the only thing that
	does. A floor on the STATE would also silently floor a future damage source; a floor on the
	EVENT means the next chunk that wants one has to ask for it in a diff.
]]

-- Re-declared rather than imported (no `script` under Lune). Luau unions are structural, so this
-- and any matching union in `Types` are the same type and pass to each other without a cast.
-- Exported for documentation and for a caller that wants to name an event; `apply` takes a plain
-- `string` on purpose, so an id that came from a table is answered rather than rejected.
export type HealthEvent = "SALT" | "FEED" | "NONE"

export type Tuning = {
	MaxHealth: number,
	WeakenedThreshold: number,
	SaltDamage: number,
	FeedHeal: number,
}

local MonsterHealth = {}

--[[
	THE FLOOR, RESOLVED SAFELY. `math.min` rather than a bare read, so a Config typo that puts
	WeakenedThreshold ABOVE MaxHealth produces a floor of MaxHealth — a monster permanently at the
	floor — instead of an inverted clamp where `math.max(x - d, floor)` silently HEALS on a salt hit.
	`tests/config.test.luau` pins the relationship (Step 2.3); this is the second line of defence.
]]
local function floorOf(tuning: Tuning): number
	return math.min(tuning.WeakenedThreshold, tuning.MaxHealth)
end

--[[
	NORMALISE A HEALTH VALUE INTO [floor, MaxHealth], INCLUDING THE VALUES THAT BREAK COMPARISONS.

	NaN fails every comparison it is given, so `nan <= threshold` is FALSE and an unguarded
	`isWeakened` would report a corrupted monster as NOT weakened — an Aswang that cannot be killed,
	with no symptom except that the second win condition stopped existing. §6.5 invariant 1 is about
	precisely that silence.

	SO NaN AND -inf RESOLVE TO THE FLOOR, NOT TO FULL HEALTH, and that direction is chosen rather
	than defaulted. Both failures are bad; one is loud. A corrupted monster at the floor glows at
	full brightness and dies to the next buntot pagi, which somebody notices within one round. A
	corrupted monster at MaxHealth is unkillable and looks exactly like a balance problem.
]]
local function normalise(health: number, tuning: Tuning): number
	local floor = floorOf(tuning)

	if health ~= health or health == -math.huge then
		return floor
	end

	if health == math.huge then
		return tuning.MaxHealth
	end

	return math.clamp(health, floor, tuning.MaxHealth)
end

-- A magnitude that cannot be negative and cannot be NaN. A negative SaltDamage would make salt heal
-- the monster; a NaN one would poison the state on the first hit. Config is hand-edited during V16.
local function magnitude(value: number): number
	if value ~= value then
		return 0
	end

	return math.max(value, 0)
end

--[[
	APPLY ONE EVENT. Returns the new health; never mutates, never errors.

	AN UNKNOWN EVENT RETURNS THE HEALTH UNCHANGED AND THAT IS FAILING CLOSED, the same way
	`NoiseModel.evaluate` answers nil for an action id with no row. The unsafe direction here is a
	free heal or a free hit for a string nobody defined.
]]
function MonsterHealth.apply(health: number, event: string, tuning: Tuning): number
	local current = normalise(health, tuning)

	if event == "SALT" then
		-- THE FLOOR (§4.6). Salt alone must never kill, or the buntot pagi is decoration.
		return math.max(current - magnitude(tuning.SaltDamage), floorOf(tuning))
	end

	if event == "FEED" then
		return math.min(current + magnitude(tuning.FeedHeal), tuning.MaxHealth)
	end

	return current
end

-- §4.6: the buntot pagi kills an Aswang that is Exposed AND "at or below 25 health". `<=`, and the
-- boundary is asserted in the test rather than left to a reader.
function MonsterHealth.isWeakened(health: number, tuning: Tuning): boolean
	return normalise(health, tuning) <= tuning.WeakenedThreshold
end

--[[
	HOW FAR ALONG THE RAMP THIS HEALTH IS: 0 at full, 1 at the floor. `MonsterService` lerps the two
	Config glow endpoints by it, so §4.6's "the glow gets brighter as it weakens" is one number here
	rather than arithmetic in a service that `check:config` would flag.

	A ZERO-WIDTH SPAN RETURNS 1 rather than dividing by it — same loud direction as `normalise`.
]]
function MonsterHealth.weakenedFraction(health: number, tuning: Tuning): number
	local floor = floorOf(tuning)
	local span = tuning.MaxHealth - floor

	if span <= 0 or span ~= span then
		return 1
	end

	return math.clamp((tuning.MaxHealth - normalise(health, tuning)) / span, 0, 1)
end

return MonsterHealth
