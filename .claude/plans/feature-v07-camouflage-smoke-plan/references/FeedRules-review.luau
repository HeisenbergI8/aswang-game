--!strict
--[[
	REVIEW — src/shared/pure/FeedRules.luau (V06, shipped in the last commit)

	Read as the STRUCTURAL PRECEDENT for `CamouflageRules`. V07's pure module copies its shape almost
	line for line, and the three places it deliberately departs are annotated below.
]]

-- src/shared/pure/FeedRules.luau:38-40
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
export type BodyKind = "CORPSE" | "HUSK"
-- IMPORTANT: re-declared, NOT required from `Types`. Lune has no `script`, so a pure module that
-- reaches for `Types` or `Enums` stops being runnable from a terminal and the point of `pure/` is
-- lost. Luau unions are structural, so these and `Types.RoundPhase` are the same type and pass to
-- each other without a cast. `CamouflageRules` must do exactly this.

-- src/shared/pure/FeedRules.luau:44-53
export type Verdict =
	"OK"
	| "WRONG_PHASE"
	| "ALREADY_FEEDING"
	| "NOT_TRANSFORMED"
	| "NOT_A_CORPSE"
	| "OUT_OF_RANGE"
-- NOTE: every value names the RECEIVER'S OWN state. The header's argument for why that is safe is the
-- one V07 inherits: "a client that is not the Aswang can never cause this function to run at all".
-- IMPORTANT: the CONTRAST it draws is the load-bearing half. `SaltThrow` deliberately collapses every
-- refusal into ONE `MISS`, because it answers a request a SURVIVOR makes about ANOTHER PLAYER — a
-- split verdict there would let a client stand in front of each player in turn and read the monster
-- off the refusal shape. V07's smoke work touches the throw path (Step 5.4) and must NOT add a
-- `MISS_SMOKE`: that value is only ever produced when the Aswang has planted a cloud.

-- src/shared/pure/FeedRules.luau:57-70
export type Request = {
	MonsterState: MonsterState,
	BodyKind: BodyKind?,
	Distance: number,
	Phase: RoundPhase,
	-- Config.Monster.FeedLeashStuds at the call site, taken as a FIELD rather than read here.
	Range: number,
}
-- IMPORTANT: taking the tunable as a field is what lets the test hand the module a synthetic range
-- AND what leaves `check:config` with no literal to flag. `CamouflageRules.evaluateSmoke` copies it
-- for `Cooldown`, and `smokeBlocks` for `radius`.

-- src/shared/pure/FeedRules.luau:76-96
local function withinRange(distance: number, range: number): boolean
	if not (range > 0 and range < math.huge) then
		return false
	end
	if not (distance >= 0 and distance < math.huge) then
		return false
	end
	return distance <= range
end
-- IMPORTANT: the `not (positive and finite)` idiom is not a style choice. Written the other way round
-- — `range <= 0 or range >= math.huge` — every NaN comparison is false and a NaN sails through into
-- `distance <= NaN`, which is also false, WHICH GRANTS THE FEED. V07's smoke cooldown check must use
-- the same form: `not (elapsed >= cooldown)`.
-- NOTE: `<=` means a feeder at exactly the leash is still on the body, and the test asserts that
-- boundary rather than leaving it to a reader. `camouflage-rules.test.luau` should do the same for
-- the cooldown boundary and for `smokeBlocks`'s tangent case.

-- src/shared/pure/FeedRules.luau:112-125
local function feedable(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end
	if request.MonsterState ~= "TRANSFORMED" and request.MonsterState ~= "FEEDING" then
		return "NOT_TRANSFORMED"
	end
	-- ...
end
-- NOTE: "World facts first (phase), then the feeder's own form, then the body, then geometry", and
-- geometry LAST because it is the only condition an honest Aswang hits routinely — so a log full of
-- OUT_OF_RANGE is a UX finding and a log full of anything above it is a bug.
-- IMPORTANT: V07 DEPARTS FROM THIS ORDER, deliberately, and the plan says so. `CamouflageRules` puts
-- the reveal gate ABOVE the phase, because the gate's precedence is a security property rather than a
-- diagnostic preference. It keeps the rest of the ordering rule intact below that.
-- NOTE: "an allowlist over five states, never `~= NORMAL`" — and it already answers for CAMOUFLAGED
-- with no producer, on `pure/BodyTransitions`'s rule that "a state with no stated answer is how these
-- tables acquire bugs". V07 gives that value a producer for the first time, which is why
-- `npm run test:unit` is the right verify on the `monsterStateOf` step.

-- tests/feed-rules.test.luau:52-62
local function isOk(state, body, distance, phase, starting): boolean
	local formHeld = if starting then state == "TRANSFORMED" else state == "FEEDING"
	return phase == "ACTIVE" and formHeld and body == "CORPSE" and distance <= RANGE
end
-- IMPORTANT: "THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCHES." Computing the expectation
-- with the module's own `if` order would prove only that the module agrees with itself. V07's grid
-- must write §4.3 as an independent conjunction the same way, and keep PRECEDENCE as a separate,
-- smaller claim with its own table.
-- NOTE: synthetic RANGE, not Config's — "V16 retunes Config and must not be able to red this file" —
-- with the live values cross-checked in a handful of assertions at the bottom. Copied in both of
-- V07's new suites.
