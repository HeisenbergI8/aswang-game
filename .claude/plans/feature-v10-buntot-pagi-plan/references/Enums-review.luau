--!strict
--[[
	REVIEW — src/shared/Enums.luau
	Read for V10 planning. Excerpts only; open the file for the rest.
]]

-- src/shared/Enums.luau:42-50
-- The three items, and the comment that already anticipated this chunk's scope check.
-- NOTE `BuntotPagi` splits to Buntot + Pagi under check:scope's word splitter and matches no OUT-list
--      token. `Config.Items.BuntotPagiStrikeRangeStuds` inherits that property for free.
-- IMPORTANT "the only three there will ever be" is load-bearing for §C.5's four-property argument.
--           A plan that adds a fourth item, or a second buntot pagi, loses the scope exception.
Enums.ItemType = table.freeze({
	Salt = "SALT" :: Types.ItemType,
	Bawang = "BAWANG" :: Types.ItemType,
	BuntotPagi = "BUNTOT_PAGI" :: Types.ItemType,
})

-- src/shared/Enums.luau:60-79
-- MonsterState's header, and the two sentences that decide V10's pure-module signature.
--[[
	V02 DECLARES THESE AND WIRES NONE OF THEM. ... `Exposed` reads as a LATCH (§4.3 — camouflage is
	locked "until it has taken a salt hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed
	AND weakened) while the other four read as mutually-exclusive activities.

	`Weakened` is deliberately absent. It is a HEALTH PREDICATE — `health <= Config.Monster
	.WeakenedThreshold` — not a state, and duplicating it as an enum member is how two sources of truth
	for one fact get out of step.
]]
-- IMPORTANT THIS IS THE SENTENCE THAT INVALIDATES THE BUILD PLAN'S V10 SIGNATURE.
--           `docs/BUILD-PLAN.md` asks for `(monsterState, monsterHealth, ...)`. Read literally that
--           needs either an `EXPOSED` this enum's own producer never emits, or a `Weakened` member
--           this comment forbids. The plan takes two booleans from MonsterService instead, and
--           Follow Up 1 asks that the build plan be corrected rather than the code bent.
-- NOTE      "Exposed reads as a LATCH ... while the other four read as mutually-exclusive
--           activities" is exactly why `TargetState` in the pure module is NOT the gate. A Weakened,
--           Exposed Aswang dies whether it is TRANSFORMED, CAMOUFLAGED or FEEDING.
Enums.MonsterState = table.freeze({
	Normal = "NORMAL" :: Types.MonsterState,
	Transformed = "TRANSFORMED" :: Types.MonsterState,
	Exposed = "EXPOSED" :: Types.MonsterState,
	Feeding = "FEEDING" :: Types.MonsterState,
	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
})

-- src/shared/Enums.luau:8-10
-- QUESTION Every value in this file carries a `:: Types.X` cast and the header says the casts are
--          load-bearing. `pure/StrikeValidation` re-declares its unions locally instead (no
--          `script.Parent` under Lune) — confirm at implementation time that the service passes
--          `Enums.MonsterState.Transformed` into the module's `TargetState` field without a cast.
--          Luau unions are structural so it should, but the scaffold shipped six errors of exactly
--          this shape and the plan's diffs have not been typechecked.
local Types = require(script.Parent.Types)
