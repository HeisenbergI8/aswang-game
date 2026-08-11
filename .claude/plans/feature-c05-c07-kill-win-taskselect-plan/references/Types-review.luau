--!strict
-- Review of src/shared/Types.luau — the payload contracts, and what the typechecker does NOT catch.
-- Excerpts only.

-- src/shared/Types.luau:11-15
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
-- IMPORTANT: FOUR values, and this plan adds none. A killed player becomes GHOST (§4.7 already calls a
-- dead survivor a ghost), which gives two properties for free: pure/PlayerBody denies them a body, and
-- pure/KillValidation denies them as a target. Adding a fifth `DEAD` value would have rippled through
-- Enums, the snapshot, and every allowlist in the game.

export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"
-- NOTE: Phase 5 raises ASWANG_WINS. The union is what stops `EndRound("ASWANG_WINS:" .. player.Name)`
-- typechecking — see RoundService.luau:242-250, which measured exactly what it does and does not block.

-- src/shared/Types.luau:57-75 — the paragraph every new payload must be read against.
--[[
	  · a field of the WRONG TYPE      -> caught  ("Property 'Result' is not compatible")
	  · a MISSING field                -> caught  ("...missing field 'RoundNumber'")
	  · an EXTRA field                 -> NOT CAUGHT. Silently accepted.

	That last line is the one that matters, because an extra field is exactly the leak shape: adding
	`KillerName = killer.Name` beside `Result` is the natural way to build a richer end screen ...
]]
-- IMPORTANT: this applies verbatim to the new PlayerKilledPayload, and one guard LESS applies to it.
-- RoundEnded is on check-secrecy.mjs's REVEAL_ALLOWLIST, so its FIELDS are now checked against
-- PAYLOAD_FIELDS. PlayerKilled is deliberately not on that allowlist — and the field check only runs
-- for remotes that are (check-secrecy.mjs:186, `if (!remote || !REVEAL_ALLOWLIST.has(remote)) continue`).
-- So on PlayerKilled: the typechecker misses an extra field, and the scanner never looks.
-- IMPORTANT: the scanner's own SECRET regex (check-secrecy.mjs:127) is
--   /\b(aswang|imposter|impostor|monsteruserid|iskiller|isaswang|aswanguserid|secretrole)\b/i
-- It matches `IsKiller`. It does NOT match `KillerUserId`, `KillerName`, or `Killer`. The most natural
-- wrong field in this game's history would pass every gate. This is Issues Found row 1 in the plan.

-- src/shared/Types.luau:102-117
--[[
	THE payload for the one remote allowed to carry a role, and the reason it has exactly one field.
	... the fields that must never appear: a UserId (the receiver already knows who they are), a
	roster, a survivor count, a round seed, the draw history, or the other players' roles.
]]
export type RoleAssignedPayload = {
	Role: Role,
}
-- NOTE: "a survivor count" and "a round seed" are already listed here as forbidden. Phase 5's living
-- survivor count and Phase 6's draw seed are both covered by an existing rule; neither needs a new one.

-- src/shared/Types.luau:134-147
--[[
	The verdict from `pure/TransformRules.luau` (C04). A literal union rather than a boolean so the
	server can log WHY it refused ...
	NOT_ALIVE covers the spectator-containment case carried over from C01; it is wired at Step 7.2.
]]
export type TransformVerdict = "OK" | "NOT_ASWANG" | "WRONG_PHASE" | "NOT_ALIVE" | "ALREADY_TRANSFORMED" | "ON_COOLDOWN"
-- NOTE: Phase 2's KillVerdict is the same idea with nine refusal reasons. It splits NOT_ALIVE into
-- KILLER_NOT_ALIVE and TARGET_NOT_ALIVE, because the two are very different events in a log: one is a
-- player acting out of turn, the other is a client aiming at something it should not be able to see.

-- src/shared/Types.luau:161-172 — the contract for what may cross.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	AlivePlayerCount: number,
	YourRole: Role?,
	YourState: PlayerState,
}
-- IMPORTANT: this plan adds NO field here. `AlivePlayerCount` starts moving mid-round (it always was
-- going to) and `YourState` starts reporting GHOST for a killed player — both are existing fields
-- carrying existing meanings. Widening this type would be a decision for Follow Ups; it did not arise.
-- NOTE: `RoundNumber` is on this snapshot, which is why `Random.new(roundNumber)` is fatal for the
-- task draw — the seed would be delivered to every client twice a second.
