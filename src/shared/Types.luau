--!strict
--[[
	Types — shared Luau type definitions.

	SECURITY NOTE: PlayerProfile and RoundState live on the SERVER ONLY.
	The Aswang's identity must never be replicated to another client in any
	form — not a tag, not an attribute, not a "hidden" value. Assume every
	client is compromised. See docs/MVP-SPEC.md §6.2.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type Role = "SURVIVOR" | "ASWANG"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
export type TaskType = "HOLD" | "TIMING" | "FETCH" | "TWO_PERSON"
export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"

export type PlayerStats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number,
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}

export type Cosmetics = {
	Owned: { [string]: boolean },
	Equipped: {
		Skin: string,
		Lantern: string,
		DeathFX: string,
	},
}

export type PlayerProfile = {
	SchemaVersion: number, -- versioned from day one; write the migration path
	XP: number,
	Level: number,
	Coins: number,
	Stats: PlayerStats,
	Cosmetics: Cosmetics,
	Daily: {
		LastClaimUTC: number,
		Streak: number,
	},
}

-- A task instance selected for the current round.
export type ActiveTask = {
	Id: string,
	Type: TaskType,
	SpawnPointName: string,
	Progress: number, -- 0..1
	Completed: boolean,
}

--[[
	The reveal, sent on RoundEnded when the round is over (spec §4.8 — the reveal is the point).

	KNOW WHAT THIS TYPE DOES AND DOES NOT BUY — measured against this repo's own analyzer, not assumed:

	  · a field of the WRONG TYPE      → caught  ("Property 'Result' is not compatible")
	  · a MISSING field                → caught  ("...missing field 'RoundNumber'")
	  · an EXTRA field                 → NOT CAUGHT. Silently accepted.

	That last line is the one that matters, because an extra field is exactly the leak shape: adding
	`KillerName = killer.Name` beside `Result` is the natural way to build a richer end screen, and it
	would reach eight clients with `npm run verify` green. Nothing catches it — `Remotes.Get` returns a
	plain RemoteEvent so `FireAllClients` takes `...any`, and `RoundEnded` sits on `check-secrecy.mjs`'s
	REVEAL_ALLOWLIST, so the scanner skips the entire call rather than inspecting its fields.

	So this type is documentation plus two thirds of a guard. It is worth having and it is NOT a reason
	to relax: **whatever you add to the reveal, re-read it as though the round were still running.**
	The enforceable version is a field allowlist inside `check-secrecy.mjs` for the two reveal remotes.
]]
export type RoundEndedPayload = {
	Result: RoundResult,
	AswangUserId: number?, -- safe ONLY here: the round is over
	RoundNumber: number,
}

--[[
	One player's bucket for one remote (C02). Server-only state; it is never sent anywhere, and it is
	declared here rather than inside AntiCheatService so `pure/TokenBucket.luau` and the service agree
	on the shape without the pure module having to require anything.

	The bucket carries its OWN capacity and refill rate rather than taking a budget alongside. That is
	what lets `TokenBucket.consume` have exactly the signature C02 asks for — `(bucket, now, cost) ->
	(allowed, newBucket)` — with no fourth argument that every caller has to look up and can get wrong.
	The values are copied out of Config.AntiCheat.Budgets when the bucket is created.

	`LastRefillAt` is an os.clock() timestamp, and os.clock() is NOT guaranteed monotonic across a
	Roblox server's lifetime. TokenBucket.consume handles a value in the future; see Step 2.1.
]]
export type TokenBucketState = {
	Tokens: number,
	LastRefillAt: number,
	Capacity: number,
	RefillPerSecond: number,
}

--[[
	THE payload for the one remote allowed to carry a role, and the reason it has exactly one field.

	`RoleAssigned` is fired to a single player with `:FireClient`, so it is on check-secrecy.mjs's
	REVEAL_ALLOWLIST — which means the scanner SKIPS the call entirely rather than inspecting it. Read
	the RoundEndedPayload comment above: an EXTRA field on an annotated table is accepted silently by
	the typechecker too. So both guards are off here, and this type is documentation backed by a habit.

	Concretely, the fields that must never appear: a UserId (the receiver already knows who they are),
	a roster, a survivor count, a round seed, the draw history, or the other players' roles. Any of
	them turns a private message into a broadcast the moment a client is compromised — which, for the
	player who IS the Aswang, is the case that matters least, and for everyone else is the whole game.
]]
export type RoleAssignedPayload = {
	Role: Role, -- the RECEIVING player's own role, and nothing else
}

--[[
	The transform broadcast (§4.3). PUBLIC BY DESIGN — this is the one thing in the game that
	legitimately reveals the Aswang, and replicating it is correct rather than tolerated.

	It carries a Model that is already in the workspace and already replicated. It does NOT carry a
	role string: "this character transformed" is a fact about the world, while "this player is the
	Aswang" is an inference the client is welcome to make and the server never states. The distinction
	matters at C14, where salt forces a revert — a reverted player is still the Aswang, and nothing in
	this payload says so.
]]
export type MonsterTransformedPayload = {
	Character: Model,
	Transformed: boolean, -- true on transform, false on revert
}

--[[
	The verdict from `pure/TransformRules.luau` (C04). A literal union rather than a boolean so the
	server can log WHY it refused — an exploiter probing the boundary and a real player hitting a
	cooldown look identical in a boolean, and telling them apart is what C41 needs.

	NOT_ALIVE covers the spectator-containment case carried over from C01; it is wired at Step 7.2.
]]
export type TransformVerdict =
	"OK"
	| "NOT_ASWANG"
	| "WRONG_PHASE"
	| "NOT_ALIVE"
	| "ALREADY_TRANSFORMED"
	| "ON_COOLDOWN"

--[[
	The verdict from `pure/KillValidation.luau` (C05). Same shape and same rule as TransformVerdict: a
	union rather than a boolean so the server can log WHY, and NEVER echoed to any client.

	The echo rule is stricter here than it looks. TARGET_IS_ASWANG is a direct role oracle — fire
	RequestKill at every player in turn and the one that answers differently is the monster — and
	KILLER_NOT_ASWANG is the same oracle pointed inward. There is no "safe subset" to return, which is
	why the handler returns nothing at all on every refusal rather than filtering the verdict.
]]
export type KillVerdict =
	"OK"
	| "WRONG_PHASE"
	| "KILLER_NOT_ALIVE"
	| "SELF"
	| "NOT_ASWANG"
	| "NOT_TRANSFORMED"
	| "ON_COOLDOWN"
	| "TARGET_NOT_ALIVE"
	| "TARGET_IS_ASWANG"
	| "OUT_OF_RANGE"

--[[
	The kill broadcast (§4.3 step 4, C05). TWO FIELDS, AND THE ABSENT ONE IS THE POINT.

	It does NOT carry the killer — not a UserId, not a name, not a direction, not a distance, not a
	"you were seen" flag. §4.8 says the reveal is the end screen's job, and a kill that named its author
	would delete the entire accusation game in one field.

	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD HERE, because both of its warnings
	apply and one extra one does:

	  · Luau accepts an EXTRA field on an annotated table silently. Measured; still true, and it is the
	    reason none of the rest of this is redundant.
	  · `check-secrecy.mjs` checks payload FIELDS against an allowlist only for remotes on its
	    REVEAL_ALLOWLIST, and PlayerKilled is deliberately not on that list. That part is unchanged: the
	    field ALLOWLIST still does not run here.
	  · Its broadcast rule DOES now run here, and it did not used to. An audit found two holes and both
	    are fixed: the rule read the argument TEXT, so the typed local three lines below reduced the
	    scan to the word `payload` and the fields were never seen; and the SECRET regex enumerated
	    `aswanguserid` by hand while matching no `Killer*` token at all. It now resolves the payload to
	    its declaration and matches `killer\w*`, so `KillerUserId` here goes red. Verified by injecting
	    it and watching the check fail.

	So the specific mistake this comment was written to warn about is now caught mechanically. Add a
	field here anyway only with a reason you would defend out loud: the check is a text tripwire, it
	cannot follow data flow, and a leak that avoids the word "killer" avoids it entirely. That is what
	`exploit-auditor` is for, and neither replaces the other.

	Position is a Vector3 and that is safe: the corpse model stands at that position and replicates to
	every client on its own. The payload states nothing the workspace does not state one frame later.
]]
export type PlayerKilledPayload = {
	VictimUserId: number,
	Position: Vector3,
}

-- SERVER ONLY. Never send this table to a client.
export type RoundState = {
	Phase: RoundPhase,
	PhaseEndsAt: number, -- os.clock() timestamp
	RoundNumber: number,
	AswangUserId: number?, -- THE SECRET
	Tasks: { ActiveTask },
	TasksCompleted: number,
	PlayerStates: { [number]: PlayerState }, -- keyed by UserId
	GateOpen: boolean,
}

-- What the client is allowed to know. Note the absence of AswangUserId.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	AlivePlayerCount: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}

return {}
