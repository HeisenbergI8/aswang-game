--!strict
--[[
	REVIEW — src/shared/pure/KillValidation.luau (221 lines)

	The decision module `FeedRules` is modelled on. V06 changes nothing here — and specifically does
	NOT remove its `Cooldown` field, which is one of the six live readers of
	`Config.Monster.KillCooldown`.
]]

-- src/shared/pure/KillValidation.luau:56-71
export type Request = {
	Phase: RoundPhase,
	KillerUserId: number,
	-- …
	Range: number,
	Now: number,
	LastRevertedAt: number?, -- nil means "has not reverted this round"; never on cooldown
	Cooldown: number,
}
-- IMPORTANT  A NAMED-FIELD REQUEST TABLE WITH TWELVE FIELDS. This is the convention `FeedRules`
--       follows, and it is why the build plan's `(monsterState, bodyKind, distance, phase)` is read
--       as naming the INPUTS rather than prescribing positional parameters. Every decision module in
--       this repo takes one table.
-- IMPORTANT  `Cooldown` IS A LIVE READER OF `Config.Monster.KillCooldown`. Retiring that number means
--       deleting this field, `MonsterService:1114`'s assignment, and the assertions in
--       `tests/config.test` and `tests/kill-validation.test` that depend on it. V06 does not.
-- NOTE  `Range` is taken as a field rather than read from Config inside the module, so the test can
--       hand it a synthetic value. `FeedRules.Request.Range` is the same decision for the same
--       reason, and it is what keeps `check:config` with nothing to flag.

-- src/shared/pure/KillValidation.luau:78-94
--   A DEGENERATE RANGE FAILS CLOSED. `range * range` is what makes this necessary… `math.huge` would
--   make every kill in the map land. Both are M12 tuning traps rather than exploits — no client
--   supplies this number — but the failure direction is the whole point.
--   …Expressed as `not (positive and finite)` rather than as two negative tests, because NaN compares
--   false to EVERYTHING… Written the other way round — `range <= 0 or range >= math.huge` — every NaN
--   comparison is false and NaN would pass straight through.
	if not (range > 0 and range < math.huge) then
		return false
	end
-- IMPORTANT  COPIED VERBATIM INTO `FeedRules.withinRange`, for both the range AND the distance.
--       `FeedRules` takes a distance rather than two positions, so it has one more degenerate input
--       than this module does — a negative distance cannot come from a `Magnitude`, which is exactly
--       why it must refuse if it ever appears.
-- NOTE  `FeedRules` compares a distance directly rather than squaring, so it does not inherit the
--       "-8 maps onto the same 64 as 8" hazard. The guard is kept anyway; the failure direction is
--       the property, not the arithmetic.

-- src/shared/pure/KillValidation.luau:108-124
--   THE ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in TransformRules. It decides which
--   reason a log line carries when more than one applies…
--   World facts first (phase), then the killer (alive, not itself, role, form, cooldown), then the
--   target (alive, not the Aswang), then geometry last. Geometry is last deliberately: it is the only
--   condition an honest player hits routinely, so a log full of OUT_OF_RANGE is a UX finding and a log
--   full of anything above it is a SECURITY finding.
-- IMPORTANT  THE RULE `FeedRules` INHERITS, INCLUDING THE PART THAT COST AN EDIT WHILE PLANNING.
--       `FeedRules.evaluate` repeats its phase test above the ALREADY_FEEDING test rather than
--       inheriting it from the shared core, precisely so world-facts-first stays true; without it,
--       FEEDING during ENDING reports a fact about the feeder when the fact worth acting on is that
--       the round is over. `tests/feed-rules.test.luau`'s precedence table pins it.
-- NOTE  Geometry last is copied too: OUT_OF_RANGE is the only refusal an honest Aswang hits, so a log
--       full of anything above it means something upstream is wrong.

-- src/shared/pure/KillValidation.luau:130-140
	-- AN ALLOWLIST, on both sides, never `~= "SPECTATOR"`. See pure/PlayerBody.luau: PlayerState has
	-- four values, exactly one of them may kill and exactly one of them may be killed…
	if request.KillerState ~= "ALIVE" then
		return "KILLER_NOT_ALIVE"
	end
-- NOTE  `FeedRules`'s form test is the same allowlist over five MonsterState values, never
--       `~= "NORMAL"`. `feedTick`'s liveness check is this one, over PlayerState.

-- src/shared/pure/KillValidation.luau:152-156
	-- §4.3 step 5: FROM THE REVERT, not from the kill. Measured from the kill, an Aswang holding the
	-- form for its full MaxTransformTime serves most of the penalty while still being a monster.
-- IMPORTANT  V06 MOVES WHEN THE REVERT HAPPENS, SO IT MOVES WHEN THIS COUNTDOWN STARTS — five seconds
--       later than before. The pure module is untouched; the meaning of `LastRevertedAt` shifts under
--       it. That is a balance change for V16, recorded in Config's KillCooldown comment.

-- src/shared/pure/KillValidation.luau:178-190
	--   `> 0`, NOT `>= 0`, and the difference is a decision rather than a typo. A zero cooldown means
	--   "no cooldown", which reads as a sensible thing to want and is not… An audit caught this line
	--   saying `>= 0` while the comment below claimed positive-and-finite.
	if not (request.Cooldown > 0 and request.Cooldown < math.huge) then
		return "ON_COOLDOWN"
	end
-- IMPORTANT  THIS IS WHY "JUST PASS Cooldown = 0" IS NOT A WAY TO RETIRE THE KILL COOLDOWN. A zero
--       here refuses every kill outright. Retiring the number means DELETING the field and this
--       guard, which is a chunk with its own tests — see the plan's Follow Up 1.
