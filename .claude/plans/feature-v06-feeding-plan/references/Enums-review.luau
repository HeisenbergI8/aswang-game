--!strict
--[[
	REVIEW — src/shared/Enums.luau (92 lines)

	V02 declared the entire v2 vocabulary and wired none of it. V06 is the first chunk to consume two
	of these tables. V06 does not edit this file.
]]

-- src/shared/Enums.luau:9-11
-- The `:: Types.X` casts are load-bearing under --!strict. Without them every field
-- infers as plain `string`, and passing one to a parameter typed as the literal union
-- fails to typecheck — which is how the scaffold shipped six analyze errors.
-- IMPORTANT  THE PREDICTABLE FAILURE IN `monsterStateOf`. Returning the bare literal `"FEEDING"`
--       against a `Types.MonsterState` return annotation infers as plain `string` and reds `analyze`.
--       Return `Enums.MonsterState.Feeding`, which already carries its cast. `npm run verify:fast`
--       (Step 2.1's verify) runs `analyze` and is what catches it.

-- src/shared/Enums.luau:53-59
-- V02, §4.7. A corpse is a killed player; a husk is one who left or went AFK. `PlayerState.Dead`
-- already spells the state, so this names the BODY rather than the player — a husk's owner is not
-- dead, they are gone, and §4.7's roster deliberately does not shrink for either.
Enums.BodyKind = table.freeze({
	Corpse = "CORPSE" :: Types.BodyKind,
	Husk = "HUSK" :: Types.BodyKind,
})
-- IMPORTANT  DECLARED AT V02 AND WIRED NOWHERE — `grep -rn BodyKind src tests` finds only this
--           declaration and `Types.luau:51`. V06's `bodyKindOf` is the first live use.
-- NOTE  "This names the BODY rather than the player" is exactly why `FeedRules` takes a `BodyKind`
--       rather than a `PlayerState`. The husk's owner is not dead, so no player-state answer can
--       express "there is a body here that has not been killed yet".

-- src/shared/Enums.luau:61-80
--   V02 DECLARES THESE AND WIRES NONE OF THEM. Read `Types.MonsterState`'s comment before building
--   the state machine: `Exposed` reads as a LATCH (§4.3 — camouflage is locked "until it has taken a
--   salt hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed AND weakened) while the
--   other four read as mutually-exclusive activities. WHETHER THIS IS ONE FIELD OR A FIELD PLUS A
--   FLAG IS THAT CHUNK'S DECISION, and V02 must not pre-empt it by wiring a `setState`.
Enums.MonsterState = table.freeze({
	Normal = "NORMAL" :: Types.MonsterState,
	Transformed = "TRANSFORMED" :: Types.MonsterState,
	Exposed = "EXPOSED" :: Types.MonsterState,
	Feeding = "FEEDING" :: Types.MonsterState,
	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
})
-- IMPORTANT  V06 DOES NOT ANSWER THE DEFERRED QUESTION EITHER, and says so. It adds `Feeding:
--       boolean` beside the existing `Transformed` and `Exposed` booleans and DERIVES the enum value
--       via `monsterStateOf`. Reason: `Transformed` has four readers outside MonsterService and
--       `Exposed` is a latch that coexists with the form, so collapsing them into one field is a
--       redesign V06 does not need and V07 will have opinions about.
-- IMPORTANT  "EXPOSED READS AS A LATCH" IS THE LINE THAT DECIDES `monsterStateOf`'s SHAPE. A salted
--       Aswang is Exposed AND still transformed. If the derivation returned EXPOSED it would shadow
--       TRANSFORMED, and `FeedRules` would refuse a feed by a glowing monster — which is the COMMON
--       case, since §4.3 makes salt the thing that interrupts a feed. So the derivation returns three
--       of these five values and never EXPOSED or CAMOUFLAGED.
-- NOTE  `FeedRules` still answers for all five, because `pure/BodyTransitions`'s header is right that
--       a state with no stated answer is where these tables acquire bugs. The grid covers the two
--       that have no producer.
-- NOTE  "`Weakened` is deliberately absent. It is a HEALTH PREDICATE" — the same discipline says do
--       not add `Enums.MonsterState.Locked` or similar for the movement lock. The lock is an effect
--       of feeding, not a state beside it.

-- src/shared/Enums.luau:27-32
Enums.PlayerState = table.freeze({
	Lobby = "LOBBY" :: Types.PlayerState,
	Alive = "ALIVE" :: Types.PlayerState,
	Dead = "DEAD" :: Types.PlayerState, -- V01: killed in-round. Spectates; the corpse is the body
	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
})
-- NOTE  `feedTick`'s liveness check compares against `Enums.PlayerState.Alive` as an ALLOWLIST, never
--       `~= Dead`. Four values; exactly one may be feeding. This is `pure/PlayerBody`'s rule and C01's
--       bug wearing its fourth hat.
