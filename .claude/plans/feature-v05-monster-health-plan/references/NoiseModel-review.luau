--!strict
--[[
	REVIEW — src/shared/pure/NoiseModel.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite (UNTRACKED — V04 has not committed yet;
	`git status` shows it as `??`). This is the idiom `MonsterHealth.luau` copies.
]]

-- src/shared/pure/NoiseModel.luau:16-22
--[[
	WHY `src/shared/pure/` IS SAFE HERE, which is a fair question after V03 put `ContainerLayout` in
	`server/pure/` for the opposite reason. The rule is about INPUTS, not folders. `ContainerLayout`
	is a draw: a client that can guess the seed replays it and knows where the buntot pagi is before
	the round starts. This is a table lookup over numbers `Config.luau` already replicates to every
	client, with no seed and no input a client supplies. ... Logic is not secret; inputs are.
]]
-- IMPORTANT: `MonsterHealth` is in the same position and the plan's header states the same argument.
-- It is a subtraction and a comparison over four replicated numbers, with no seed and no
-- client-supplied input. If a later chunk adds a per-round or per-player input to `Tuning`, the
-- module moves to `src/server/pure/` and the test's require path moves with it.

-- src/shared/pure/NoiseModel.luau:24-27
--[[
	THERE IS NO ROLE PARAMETER AND NO FORM PARAMETER, and that is structural rather than careful:
	with no player and no role in the signature there is no arrangement of this module in which two
	players doing the same thing make different noise.
]]
-- IMPORTANT: the exact property `MonsterHealth` needs and gets for free — no player, no UserId, no
-- role in the signature, so no arrangement of it distinguishes one player's health from another's.

-- src/shared/pure/NoiseModel.luau:31-33
-- Re-declared rather than imported (no `script` under Lune). Luau unions are structural, so this and
-- `Types.NoiseAction` are the same type and pass to each other without a cast.
export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"
-- NOTE: exported as a SCALAR union and used as a scalar. `.claude/lessons/pure-module-unions-widen
-- -in-lists.md` bites only on a union inside a LIST crossing the require boundary; this shape is the
-- one the lesson explicitly calls fine. `MonsterHealth.HealthEvent` follows it.

-- src/shared/pure/NoiseModel.luau:66-73
-- NaN fails every comparison it is given, so `speed < threshold` would be FALSE for NaN and a NaN
-- speed would emit. Normalised here once rather than guarded at three comparison sites.
local function finiteSpeed(value: number?): number
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(value, 0)
end
-- IMPORTANT: the shape `MonsterHealth.normalise` copies — one normaliser at the top, not a guard at
-- every comparison. The difference is that NoiseModel's safe direction is ZERO (silent) and
-- MonsterHealth's is THE FLOOR (weakened, therefore killable), because an unkillable monster is the
-- silent failure and a killable one is the loud one.

-- src/shared/pure/NoiseModel.luau:75-93
--[[
	NIL IS A LEGITIMATE ANSWER AND FAILS CLOSED. An action id with no row is silent rather than loud
	... The parameter is `string` rather than `NoiseAction` so an unknown id is a normal call with a
	normal answer, instead of a type error at a call site that got its id off the wire.
]]
function NoiseModel.evaluate(action: string, state: State, tuning: Tuning): Emission?
	local entry: ActionTuning? = tuning.Actions[action]
-- IMPORTANT: `apply(health, event: string, tuning)` copies this exactly. An unknown event returns the
-- health unchanged, which is the fail-closed direction — a free heal or a free hit for an undefined
-- string is the unsafe one.
-- NOTE: `: ActionTuning?` is load-bearing under --!strict — indexing a `{ [string]: T }` yields a
-- NON-optional value, so comparing it to nil is a type error. `MonsterHealth` has no table lookup, so
-- it does not hit this; `MonsterService`'s `monsters[userId]` does.

-- src/shared/pure/NoiseModel.luau:104-108
	-- Clamped rather than trusted. Config is hand-edited during M12/V16 and a negative radius would
	-- otherwise mean "audible to nobody" in one place and "audible to everybody" in another.
	return {
		Loudness = math.clamp(entry.Loudness, 0, 1),
		Radius = math.max(entry.Radius, 0),
	}
-- NOTE: the precedent for `MonsterHealth.magnitude` clamping `SaltDamage` and `FeedHeal` to
-- non-negative. A negative SaltDamage would make salt HEAL the monster.
