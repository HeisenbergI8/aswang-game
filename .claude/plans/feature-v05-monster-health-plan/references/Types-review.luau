--!strict
--[[
	REVIEW — src/shared/Types.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite (modified in the working tree by V04).
	V05 EDITS NOTHING IN THIS FILE. These notes record why.
]]

-- src/shared/Types.luau:39
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
-- NOTE: a string union describing the monster's activity. NOT the record `MonsterService` keeps in
-- its `monsters` table, which shares the name and is a different thing entirely. V05 adds its
-- `Health`, `Exposed`, `ExposedGlow` and `ExposedGeneration` fields to the SERVER record, so this
-- line does not move.

-- src/shared/Types.luau:420-427
export type RoundState = {
	AswangUserId: number?, -- THE SECRET
	PlayerStates: { [number]: PlayerState },
}
-- NOTE: server-only. V05 adds nothing here either — health lives in MonsterService's table, not in
-- the round's state, because MonsterService owns it and RoundService owns the phase (§6.4).

-- src/shared/Types.luau:429-478  (ClientRoundSnapshot)
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
	YourCarriedItem: ItemType?,
}
-- IMPORTANT: this is the contract for what may cross to a client, and V05 DOES NOT WIDEN IT. There is
-- no `YourMonsterHealth`, no `MonsterWeakened`, no anything. §4.6 is explicit that the presentation
-- is the glow, not a UI: "a health value attached to a player is the reveal."
-- QUESTION (Follow Ups #1): should the Aswang be told its OWN health? The `Your` prefix contract
-- would permit it in shape — built per player, sent with `:FireClient`, no broadcast form exists.
-- The trap is `absence-is-observable` on a payload: a field that is nil for survivors and 100 for the
-- Aswang is the leak, so it would have to be nil until the first salt hit, or not exist.

-- src/shared/Types.luau:434-460  (the YourCarriedItem comment — the precedent for that argument)
--[[
	IT IS NOT A ROLE ORACLE. The Aswang carries nothing — the three items are the survivors' (§4.6) —
	so its slot is `nil`, which is also what an empty-handed survivor's slot is. The two are
	indistinguishable, and they must stay that way ...
	... never mirror it onto an attribute or a tag, both of which replicate to everyone.
]]
-- IMPORTANT: the exact reasoning V05's health field would have to satisfy if it ever crossed. It is
-- the model for Follow Ups #1's condition, and the "never an attribute or a tag" clause applies to
-- the health number today, on the server, with no payload involved.

-- src/shared/Types.luau:479-514  (the AlivePlayerCount tombstone)
--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).
	... DO NOT REINTRODUCE IT UNDER ANOTHER NAME. `SurvivorsRemaining`, `DeadCount`, `RosterSize` and
	a `YourState`-derived tally over a roster field are the same oracle wearing different words, and
	none of them contains a token `check-secrecy.mjs` matches.
]]
-- IMPORTANT: read this before adding ANY field in a later chunk. The pattern — a number that is
-- individually innocent and collectively an oracle — is exactly what a monster health field would be
-- if it were ever broadcast: a live progress bar on the survivors' win condition, for both sides.

-- src/shared/Types.luau:317-344  (SaltEffectPayload)
export type SaltEffectPayload = {
	Origin: Vector3,
	Impact: Vector3,
	Hit: boolean,
}
--[[
	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
	table is accepted silently by the typechecker ... A field named `TargetUserId` would pass every
	check in this repo and would name the monster to eight clients.
]]
-- IMPORTANT: V05 does not touch this payload, and specifically does not add a `Health` or
-- `Weakened` field to it. `Hit` is already at the edge of what is safe, and it is safe only because
-- a transformed Aswang is already public via `MonsterTransformed`. Health is not.
