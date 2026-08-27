--!strict
--[[
	REVIEW — src/shared/pure/MonsterHealth.luau (140 lines)

	V05's health model. V06 does not change a line of it. It is read to confirm that the feed heal
	goes THROUGH this module rather than around it, and to copy its fail-closed idioms into
	`FeedRules`.
]]

-- src/shared/pure/MonsterHealth.luau:16-22
--   WHY `src/shared/pure/` IS SAFE HERE, which V03 answered the other way. The rule is about INPUTS.
--   `ContainerLayout` is a DRAW: a client that can guess its seed knows where the buntot pagi is
--   before the round starts, so it lives in `server/pure/`. This is a subtraction and a comparison
--   over four numbers `Config.luau` already replicates… Logic is not secret; inputs are, and this
--   module has no input a client supplies.
-- IMPORTANT  THE TEST V06 APPLIED TO `FeedRules` AND PASSED. `FeedRules`'s inputs are `MonsterState`
--       (server memory), `BodyKind` (a workspace folder a client cannot write), `Distance` (two
--       server-read positions) and `Range` (Config, already replicated). No seed, no draw, no
--       client-suppliable input. So `shared/pure/` rather than `server/pure/`, and the argument is
--       written into the module header the way this one is.

-- src/shared/pure/MonsterHealth.luau:23-27
--   WHAT IT DELIBERATELY DOES NOT CONTAIN: any notion of who the health belongs to. There is no
--   player, no UserId and no role in the signature, so there is no arrangement of this module in
--   which the health of one player is distinguishable from the health of another. That is STRUCTURAL
--   rather than careful.
-- IMPORTANT  `FeedRules` COPIES THIS PROPERTY EXACTLY: no player, no UserId, no role in the Request.
--       It is the reason a six-value verdict union is safe here where `SaltThrow` had to collapse
--       its refusals into one `MISS` — `SaltThrow` answers about ANOTHER player, this answers about
--       the caller's own state.

-- src/shared/pure/MonsterHealth.luau:96-112
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
-- IMPORTANT  THE `FEED` BRANCH ALREADY EXISTS AND IS ALREADY TESTED. V06 writes no arithmetic: it
--       calls `MonsterService.HealFromFeed`, which calls `applyHealthEvent(userId, "FEED")`, which
--       lands here. A `monster.Health += Config.Monster.FeedHeal` in the service would be a second
--       implementation that does not cap at MaxHealth, does not repaint the glow, and is not covered
--       by `tests/monster-health.test.luau`.
-- NOTE  The cap is `math.min(…, MaxHealth)`, so a feed at full health is a no-op rather than an
--       overfill. §4.6's tug-of-war holds: three salt hits are healed away by three kills and no
--       more.
-- NOTE  "AN UNKNOWN EVENT RETURNS THE HEALTH UNCHANGED AND THAT IS FAILING CLOSED" — the same
--       direction `FeedRules` fails in for a degenerate distance or range.

-- src/shared/pure/MonsterHealth.luau:80-89
-- A magnitude that cannot be negative and cannot be NaN.
local function magnitude(value: number): number
	if value ~= value then
		return 0
	end

	return math.max(value, 0)
end
-- NOTE  The idiom `FeedRules.withinRange` copies, in its `not (positive and finite)` form: NaN
--       compares false to everything, so the guard has to be written as a negated conjunction or the
--       NaN sails through. `KillValidation`'s header records that this took three attempts and the
--       first two both shipped.

-- src/shared/pure/MonsterHealth.luau:28-33
--   THE FLOOR BELONGS TO THE SALT EVENT, NOT TO THE STATE… A floor on the STATE would also silently
--   floor a future damage source; a floor on the EVENT means the next chunk that wants one has to ask
--   for it in a diff.
-- NOTE  The same discipline says V06 must not add a "feed heals more when weakened" or any other
--       conditional to this module. The feed is `+FeedHeal`, flat, and any variation is a balance
--       decision that belongs in a diff.
