--!strict
--[[
	REVIEW — src/shared/Enums.luau
	Excerpt only. Range as of 2026-08-27, branch v2-rewrite.
]]

-- src/shared/Enums.luau:60-79
--[[
	V02, §4.3. What the Aswang is doing.

	V02 DECLARES THESE AND WIRES NONE OF THEM. Read `Types.MonsterState`'s comment before building the
	state machine: `Exposed` reads as a LATCH (§4.3 — camouflage is locked "until it has taken a salt
	hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed AND weakened) while the other four
	read as mutually-exclusive activities. Whether this is one field or a field plus a flag is that
	chunk's decision, and V02 must not pre-empt it by wiring a `setState`.

	`Weakened` is deliberately absent. It is a HEALTH PREDICATE — `health <= Config.Monster
	.WeakenedThreshold` — not a state, and duplicating it as an enum member is how two sources of truth
	for one fact get out of step.
]]
Enums.MonsterState = table.freeze({
	Normal = "NORMAL" :: Types.MonsterState,
	Transformed = "TRANSFORMED" :: Types.MonsterState,
	Exposed = "EXPOSED" :: Types.MonsterState,
	Feeding = "FEEDING" :: Types.MonsterState,
	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
})

-- IMPORTANT: "whether this is one field or a field plus a flag is that chunk's decision" — V05 IS
-- that chunk, at least for `Exposed`, and the plan decides: A FLAG, not a member of a single state
-- field. `Exposed` is a latch that coexists with Transformed, Feeding and Camouflaged; collapsing it
-- into one enum field would make "transformed AND exposed" unrepresentable, which is the ONLY state
-- in which §4.6's kill can happen.
--
-- IMPORTANT: `Weakened` stays absent. V05 adds `MonsterService.IsWeakened`, a predicate over the
-- health number, and adds NO enum member. This comment is the reason, written a chunk in advance.
--
-- NOTE: V05 therefore wires none of these five constants either. They remain declared-and-unwired
-- after this chunk, and the boolean `Exposed` on `MonsterState` (the SERVER type in MonsterService,
-- not `Types.MonsterState`) is what actually holds the latch. The name collision between
-- `MonsterService.MonsterState` (a server record) and `Types.MonsterState` (a string union) predates
-- V05 and is not worth renaming inside this chunk — but it will confuse a reader, so it is noted.
--
-- NOTE: the `:: Types.MonsterState` casts are load-bearing under --!strict. `"EXPOSED"` alone infers
-- as plain `string` and then fails to satisfy a parameter typed as the literal union. Six of the
-- scaffold's seven original analyze errors were exactly this (CLAUDE.md, "Strict Luau, and it bites").
