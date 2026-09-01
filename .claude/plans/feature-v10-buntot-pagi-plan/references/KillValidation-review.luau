--!strict
--[[
	REVIEW — src/shared/pure/KillValidation.luau
	Read for V10 planning. The closest structural sibling to `StrikeValidation`: same layer, same
	verdict-union shape, same fail-closed idioms — and one place where V10 can do better.
]]

-- src/shared/pure/KillValidation.luau:8-12 — the split V10 copies
--[[
	§4.3's five verbatim server-side rules are "distance ≤ 8 studs, raycast line-of-sight, cooldown
	elapsed, both alive, round ACTIVE". Four of the five are comparisons over numbers and string enums
	and live here. The fifth — the raycast — is irreducibly Roblox and stays in MonsterService.
]]
-- NOTE V10 makes the identical split: the two-condition grid is pure, the raycast stays in
--      `MonsterService.ResolveStrikeTarget`. Nothing new is being invented here.

-- src/shared/pure/KillValidation.luau:22-25 — the Vector3 trap
--[[
	NO Vector3. Lune has no Roblox datatypes at all, so a Vector3 here would not fail to typecheck —
	it would fail at TEST time ...
]]
-- IMPORTANT `StrikeValidation` avoids this more simply than KillValidation does: it takes a SCALAR
--           distance the caller has already measured, rather than two positions. Fewer inputs, no
--           `Vec3` type, and the geometry stays in the file that has a Vector3.

-- src/shared/pure/KillValidation.luau:28-35 — the shared/pure test, applied
--[[
	THIS ONE MAY LIVE IN src/shared/pure/ ... A client can require and call it, and it learns nothing:
	every input is either a fact that client already holds about itself, a Config number that already
	replicates, or a position it can read off the workspace. ... Logic is not secret; inputs and seeds
	are, and this function has neither.
]]
-- IMPORTANT THE PLAN'S §1.4 IS THIS PARAGRAPH APPLIED TO V10 AND IT PASSES. `StrikeValidation` has
--           no seed; both booleans come off a server-only table, the distance is measured between
--           the server's two characters, the phase is `RoundService.GetPhase()` and `Held` is the
--           server's own slot. A client can run the module and cannot supply the arguments.

-- src/shared/pure/KillValidation.luau:37 — the warning V10 does NOT need
--[[
	THE VERDICT NEVER REACHES A CLIENT. TARGET_IS_ASWANG is a role oracle in one word.
]]
-- IMPORTANT THIS IS WHERE V10 IMPROVES ON THE PRECEDENT. `StrikeValidation` has NO role field and NO
--           role-shaped verdict, because it does not need one: only the Aswang has monster state, so
--           only the Aswang can be Exposed or Weakened, and `Exposed AND Weakened` IMPLIES the role
--           rather than asking about it. There is no value in the union that a careless FireClient
--           could leak. Structural rather than careful.

-- src/shared/pure/KillValidation.luau:104-127 — the range guard, copied idiom-for-idiom
local function withinRange(a: Vec3, b: Vec3, range: number): boolean
	--[[
		A DEGENERATE RANGE FAILS CLOSED. ... FINITE AND POSITIVE, tested as one condition. `not (range
		> 0)` alone is not enough — it catches zero, negatives and NaN, but `math.huge > 0` is true, so
		an infinite range sailed past it and `25000000 <= inf` granted a kill from five thousand studs.

		Expressed as `not (positive and finite)` rather than as two negative tests, because NaN
		compares false to EVERYTHING ... Written the other way round — `range <= 0 or range >=
		math.huge` — every NaN comparison is false and NaN would pass straight through.
	]]
	if not (range > 0 and range < math.huge) then
		return false
	end
	-- SQUARED, so there is no square root and no float-comparison surprise at the boundary.
end
-- IMPORTANT V10 COPIES THE GUARD BUT NOT THE SQUARING — it compares a scalar distance directly, so
--           the negative-range-maps-onto-the-same-square failure does not exist there. The infinity
--           and NaN cases are identical and are why the negated-conjunction form must be kept.
-- IMPORTANT THE FAILURE DIRECTION IS OPPOSITE AND WORTH SAYING OUT LOUD. Here, failing closed stops
--           the monster killing. In `StrikeValidation`, failing closed stops the SURVIVORS killing —
--           which is §6.5 invariant 1's silent failure. The plan pins the range in
--           `tests/config.test.luau` so the loud half exists too.

-- src/shared/pure/KillValidation.luau:129-144 — the fixed-order contract
--[[
	THE ORDER IS FIXED AND IS PART OF THE CONTRACT ... It decides which reason a log line carries when
	more than one applies ...

	World facts first (phase), then the killer (alive, not itself, role, form, cooldown), then the
	target (alive, not the Aswang), then geometry last. Geometry is last deliberately: it is the only
	condition an honest player hits routinely, so a log full of OUT_OF_RANGE is a UX finding and a log
	full of anything above it is a security finding.
]]
-- IMPORTANT `StrikeValidation` KEEPS THE ORDER BUT MOVES GEOMETRY UP, and that is a deliberate
--           departure. Here geometry is last so the log is diagnostic; there, geometry is the FIRST
--           thing below the spend line because everything below the spend line is one verdict anyway
--           — there is no ordering left to be diagnostic about. The diagnosis is the server's own
--           lookup, exactly as `GarlicPlacement`'s header describes for its nil doorway.

-- src/shared/pure/KillValidation.luau:196-200 — the unreachable-today check kept anyway
	-- With AswangCount = 1 this is unreachable today. It is here because Config.Roles.AswangCount is a
	-- knob ... so the day someone sets it to 2 in a Studio session, the failure must be "the kill is
	-- refused", not "the monsters eat each other".
	if request.TargetIsAswang then
		return "TARGET_IS_ASWANG"
	end
-- NOTE This is the precedent for `StrikeValidation`'s `TargetPlayerState ~= "ALIVE"` branch, which is
--      also unreachable today (a dead Aswang ends the round) and kept for the same reason.
