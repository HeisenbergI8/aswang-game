--!strict
--[[
	REVIEW — src/shared/Types.luau (384 lines)

	Excerpted ranges:
	  · src/shared/Types.luau:57-80    RoundEndedPayload's warning, which every new payload inherits
	  · src/shared/Types.luau:170-203  PlayerKilledPayload — the one this plan narrows
	  · src/shared/Types.luau:359-382  RoundState and ClientRoundSnapshot

	Phase 1 removes one field here and adds four types. The file's existing comments are the reason the
	four new ones are written the way they are.
]]

-- src/shared/Types.luau:60-74
--	  · a field of the WRONG TYPE      → caught  ("Property 'Result' is not compatible")
--	  · a MISSING field                → caught  ("...missing field 'RoundNumber'")
--	  · an EXTRA field                 → NOT CAUGHT. Silently accepted.
--	That last line is the one that matters, because an extra field is exactly the leak shape
-- IMPORTANT MEASURED AGAINST THIS REPO'S OWN ANALYZER, not assumed. Every new payload this plan adds
--      (SaltEffectPayload, GhostRosterPayload) carries the same warning, because the guard genuinely is
--      only two thirds of one: a typed local catches a wrong type and a missing field and accepts an
--      extra one silently.
-- NOTE This is why Steps 4.3 and 6.5 both build a TYPED LOCAL rather than an inline table — FireClient
--      and FireAllClients take `...any`, so an inline literal is checked against nothing at all.

-- src/shared/Types.luau:171
--	It does NOT carry the killer — not a UserId, not a name, not a direction, not a distance
-- src/shared/Types.luau:186-190
--	    Its broadcast rule DOES now run here, and it did not used to. An audit found two holes and both
--	    are fixed... It now resolves the payload to its declaration and matches `killer\w*`
-- NOTE `check-secrecy.mjs` DOES scan this payload, and it scans it whether the fire is to one client or
--      to all. So Step 1.5's direction change cannot be used as cover for making the payload richer —
--      "the recipient is only the victim, so anything is safe now" is a plausible and wrong reading. A
--      compromised victim client is still a client.

-- src/shared/Types.luau:196-199
--	Position is a Vector3 and that is safe: the corpse model stands at that position and replicates to
--	every client on its own. The payload states nothing the workspace does not state one frame later.
-- IMPORTANT THIS SENTENCE IS FALSE UNDER §5's StreamingEnabled, and it is load-bearing for Decision 1.
--      §5 and BUILD-PLAN C17 both require StreamingEnabled from the start, under which a corpse 200 studs
--      away does NOT replicate to a distant client — while `FireAllClients` reaches every one of them.
--      The two were never equivalent; they only looked it on an unstreamed baseplate, which is the
--      environment this comment was written in.
-- NOTE Step 1.5 replaces this paragraph rather than leaving it to contradict the code.

-- src/shared/Types.luau:359-369
-- SERVER ONLY. Never send this table to a client.
export type RoundState = {
	Phase: RoundPhase,
	AswangUserId: number?, -- THE SECRET
	PlayerStates: { [number]: PlayerState },
	-- ...
}
-- NOTE `RoundState` is a documentation type — RoundService keeps its own `state` local rather than using
--      it, so adding a field here changes nothing at runtime. Phase 5's `dealtIn` and `leftDuringRound`
--      are locals in RoundService for the same reason, and are documented in place.

-- src/shared/Types.luau:371-382
-- What the client is allowed to know. Note the absence of AswangUserId.
export type ClientRoundSnapshot = {
	-- ...
	AlivePlayerCount: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}
-- IMPORTANT DECISION 1's TARGET. Step 1.3 removes `AlivePlayerCount` and leaves a comment in its place
--      naming the substitutes that must not reintroduce it: SurvivorsRemaining, DeadCount, RosterSize, or
--      a roster field a client can count. None of them contains a token check-secrecy.mjs matches, and a
--      count is the shape no text tripwire in this repo can see.
-- NOTE `YourRole` is declared and deliberately never set — buildSnapshot leaves it nil, and RoleAssigned
--      is the single allowlisted carrier. Worth knowing when reading buildSnapshot and finding a field
--      in the type that is not in the constructor: that is intentional, not an omission.
-- QUESTION Should `YourRole` be deleted from this type at some point? It is a field that exists only to
--      be unused, and an unused optional is exactly where a future author would put a role. Out of scope
--      here; raised because Phase 1 is the chunk that reads this type most closely.
