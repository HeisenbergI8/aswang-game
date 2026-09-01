--!strict
--[[
	REVIEW — src/shared/pure/MonsterHealth.luau
	Read for V10 planning: `isWeakened` is half the strike gate, and this file's header is the
	`src/shared/pure/` argument the plan reuses.
]]

-- src/shared/pure/MonsterHealth.luau:13-19 — the shared/pure test, stated as a rule about INPUTS
--[[
	WHY `src/shared/pure/` IS SAFE HERE, which V03 answered the other way. The rule is about INPUTS.
	`ContainerLayout` is a DRAW: a client that can guess its seed knows where the buntot pagi is
	before the round starts, so it lives in `server/pure/`. This is a subtraction and a comparison
	over four numbers `Config.luau` already replicates to every client. ... Logic is not secret;
	inputs are, and this module has no input a client supplies.
]]
-- IMPORTANT THE TASK BRIEF ASKS THIS QUESTION OF `StrikeValidation` AND THE ANSWER IS THE SAME.
--           No seed. `TargetExposed`/`TargetWeakened` come off a server-only table, the distance is
--           measured between the server's copies of two characters, the phase is
--           `RoundService.GetPhase()`, `Held` is the server's own slot. A client can require and run
--           the module and cannot supply a single one of them.
-- NOTE      `server/pure/ContainerLayout` is the counter-example in this repo, and it is named here
--           for the right reason: it decides WHERE THE BUNTOT PAGI IS. A client that could replay
--           that draw knows the win condition's location before the round starts. `StrikeValidation`
--           decides nothing about placement and consumes no randomness.

-- src/shared/pure/MonsterHealth.luau:21-25
--[[
	WHAT IT DELIBERATELY DOES NOT CONTAIN: any notion of who the health belongs to. There is no
	player, no UserId and no role in the signature, so there is no arrangement of this module in
	which the health of one player is distinguishable from the health of another. That is structural
	rather than careful — `.claude/lessons/absence-is-observable.md` is the long version.
]]
-- IMPORTANT "STRUCTURAL RATHER THAN CAREFUL" IS THE STANDARD V10 IS HELD TO. `StrikeValidation`
--           takes no player and no role, and collapses four target-side worlds into ONE verdict so
--           the difference is not merely unsent — it was never computed.

-- src/shared/pure/MonsterHealth.luau:60-70 — the NaN direction, chosen rather than defaulted
--[[
	NaN fails every comparison it is given, so `nan <= threshold` is FALSE and an unguarded
	`isWeakened` would report a corrupted monster as NOT weakened — an Aswang that cannot be killed,
	with no symptom except that the second win condition stopped existing. §6.5 invariant 1 is about
	precisely that silence.

	SO NaN AND -inf RESOLVE TO THE FLOOR, NOT TO FULL HEALTH ... A corrupted monster at the floor
	glows at full brightness and dies to the next buntot pagi, which somebody notices within one
	round. A corrupted monster at MaxHealth is unkillable and looks exactly like a balance problem.
]]
-- IMPORTANT THIS IS ALREADY HANDLED UPSTREAM OF V10, which is why `StrikeValidation` takes a boolean
--           and inherits the guard for free. It also sets the direction for the plan's OWN
--           fail-closed guard: a degenerate RANGE must refuse the strike, and the plan pins the
--           range in `tests/config.test.luau` so the silent half has a loud counterpart.

-- src/shared/pure/MonsterHealth.luau:120-124 — half the strike gate, and the boundary
-- §4.6: the buntot pagi kills an Aswang that is Exposed AND "at or below 25 health". `<=`, and the
-- boundary is asserted in the test rather than left to a reader.
function MonsterHealth.isWeakened(health: number, tuning: Tuning): boolean
	return normalise(health, tuning) <= tuning.WeakenedThreshold
end
-- IMPORTANT `MonsterService.IsWeakened` IS A ONE-LINE WRAPPER OVER THIS, and it is where V10's
--           `TargetWeakened` comes from. The boundary (`<=`, so exactly 25 is Weakened) is already
--           proven in `tests/monster-health.test.luau`; `tests/strike-validation.test.luau` does not
--           re-prove it and should not — it takes the boolean as given.
-- NOTE      The floor means salt lands the monster EXACTLY at WeakenedThreshold and never below, so
--           in practice `isWeakened` is true at exactly the boundary value. A `<` here would make
--           the second win condition unreachable by construction. Worth knowing before anyone
--           "tightens" it.

-- src/shared/pure/MonsterHealth.luau:26-31 — the floor, and why salt cannot kill
--[[
	THE FLOOR BELONGS TO THE SALT EVENT, NOT TO THE STATE. §4.6: salt is floored at
	WeakenedThreshold so that "salt alone can never kill" and the buntot pagi is the only thing that
	does. A floor on the STATE would also silently floor a future damage source; a floor on the
	EVENT means the next chunk that wants one has to ask for it in a diff.
]]
-- NOTE V10 IS THE CHUNK THIS SENTENCE WAS WAITING FOR. "The buntot pagi is the only thing that does"
--      has been a comment about an unbuilt mechanic since V05; from V10 it is a description of a
--      code path. V10 adds NO damage source — the strike is a boolean gate and a death, never an
--      `apply` call — so the floor's reasoning is untouched.
