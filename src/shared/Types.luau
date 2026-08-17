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

	Position is a Vector3, and THE DEFENCE THAT USED TO SIT HERE WAS FALSE. It read: "the corpse model
	stands at that position and replicates to every client on its own. The payload states nothing the
	workspace does not state one frame later." That holds only on an unstreamed baseplate. §5 requires
	`StreamingEnabled`, under which a corpse 200 studs away does NOT reach a client — and this remote
	did. The two were never equivalent; they only looked it during development.

	Since Amendment A3 this payload is `FireClient(victim, …)`, and the field is safe for the reason it
	always should have been: the only recipient is the player it describes, who watched it happen.
]]
export type PlayerKilledPayload = {
	VictimUserId: number,
	Position: Vector3,
}

--[[
	The verdict from `server/pure/TaskPool.luau` (C07) — is the map's TaskPoint pool usable.

	EMPTY and SHORT are the two that BLOCK a draw. DUPLICATE_ID and OVERSIZED are loud and
	non-blocking: the round still runs, and the map still has a defect somebody has to fix. That split
	is why this is a union rather than a boolean — "unusable" and "usable but wrong" send a reader to
	two different places, and a boolean would collapse them into a shrug.

	This one is SAFE TO LOG AND SAFE TO SHOW. It describes the map, not a player, and every fact in it
	is readable off the workspace by any client that cares to count tagged parts.
]]
export type TaskPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"

--[[
	Why the server refused a RequestTaskProgress. Same shape and same rule as KillVerdict: a union so
	the server can log WHY, and NEVER echoed to any client.

	The echo rule is not inherited caution here, it is the specific hazard C08 has to design around.
	Under Amendment A2 no verdict names a role — the Aswang's holds count in full — but the refusal
	set still describes the round's private state, and NO_TASK_IN_RANGE in particular would tell a
	client which of the twelve points are live faster than walking there would. There is no safe
	subset to return, so the handler returns NOTHING on every refusal, exactly as the kill does.

	NO_TASK_IN_RANGE covers both "you are nowhere near one" and "that point is not one of this round's
	five". They are deliberately the same value: distinguishing them would tell a client which of the
	twelve are live faster than walking there would.
]]
export type TaskProgressVerdict =
	"OK"
	| "WRONG_PHASE"
	| "NOT_ALIVE"
	| "NO_TASK_IN_RANGE"
	| "ALREADY_COMPLETE"

--[[
	The task bar (§4.4, C08). THREE FIELDS, AND THE THIRD IS THE ONE WITH A DESIGN BEHIND IT.

	It does NOT carry who did what — not a UserId, not a name, not a count of who is present. §4.4 says
	"a global task bar shows overall progress (not who did what)" and this payload is that sentence.

	`YourTaskProgress` is the 0..1 fill of the ONE task point the receiving player is standing at, and
	nil for everyone else. It is fired with FireClient per player and never with FireAllClients.

	BE PRECISE ABOUT WHAT THAT DOES AND DOES NOT BUY, because an earlier version of this comment
	overstated it. This field carries the WORLD's fill for that point, not the receiver's own
	contribution, and becoming "the person standing on it" costs one keypress — so per-player firing
	restricts who ASKS, and anyone may ask. It is a bandwidth saving and a narrowing, not a seal.

	The reason that is safe is Amendment A2, not this remote: no task's fill is a function of anyone's
	role, so a frozen bar says "nobody is holding" and never "the holder is the Aswang". Keep it that
	way. If a future change makes any player's contribution differ by role, this field becomes a role
	oracle readable in two seconds by any bystander, and per-player firing will not save it.

	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
	table is accepted silently by the typechecker, and `TaskProgressChanged` is not on
	check-secrecy.mjs's REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, which catches
	a field named `role` or `aswang` or `killer` and catches nothing else. A field named
	`PresentPlayerCount` would pass every check in this repo and would still be the oracle above.
]]
export type TaskProgressPayload = {
	TasksCompleted: number,
	TasksRequired: number,
	YourTaskProgress: number?,
}

--[[
	Why the server refused (or failed) a RequestTimingStop (§4.4, C09). Same shape and same rule as
	TaskProgressVerdict: a union so the server can log WHY, and NEVER echoed to any client.

	MISS IS A VERDICT AND NOT AN ERROR, and it is the one worth reading twice. A miss is a legitimate
	outcome of a legitimate request — the player pressed at the wrong moment — so unlike every other
	value here it corresponds to a state change (the hit count resets). It is still never echoed: the
	client learns it missed from the bar it is already being sent, which carries `Hits` and moves
	whether the stop landed or not. Sending a verdict would add a second, differently-timed channel
	saying the same thing, and two channels that can disagree is how a desync becomes a bug report.

	NOT_A_TIMING_TASK exists because `RequestTimingStop` resolves its task from the player's position
	exactly as `RequestTaskProgress` does, so a player standing on a HOLD point can reach this handler
	honestly. It is a refusal, not an accusation.
]]
export type TimingVerdict =
	"OK"
	| "MISS"
	| "WRONG_PHASE"
	| "NOT_ALIVE"
	| "NO_TASK_IN_RANGE"
	| "ALREADY_COMPLETE"
	| "NOT_A_TIMING_TASK"

--[[
	The moving bar (§4.4, C09). SEVEN FIELDS, ALL OF THEM ABOUT A TASK POINT AND NONE ABOUT A PLAYER.

	`Phase` is the bar's position in its sweep at the moment the server sent this, in 0..1, NOT the
	rendered bar position — the rendered position is a triangle fold of it, and the client computes
	that with `TimingWindow.positionFromPhase`. Sending the phase rather than the position is what
	makes a single send sufficient: position alone is ambiguous (the bar passes every value twice per
	sweep) and would need a direction flag beside it, which is a second field that can disagree with
	the first.

	THE CLIENT EXTRAPOLATES BETWEEN SENDS AND THE SERVER DOES NOT CARE. The server re-derives the
	phase from its own `os.clock()` at the instant a stop arrives; nothing the client renders is an
	input to that. A client that renders the bar frozen, doubled, or backwards gets exactly the same
	hit decision as one that renders it perfectly. That is the C09 brief's "a client-decided timing
	minigame is a free task for any exploiter", answered structurally.

	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
	table is accepted silently by the typechecker, and `TimingBarChanged` is not on
	check-secrecy.mjs's REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, catching a
	field named `role` or `aswang` and catching nothing else. A field named `LastStopByUserId` would
	pass every check in this repo and would name who is standing where.
]]
export type TimingBarPayload = {
	TaskId: string,
	Phase: number, -- 0..1 through one sweep, at send time
	Period: number,
	GreenCenter: number,
	GreenHalfWidth: number,
	Hits: number,
	HitsRequired: number,
}

--[[
	The task list one player is shown (§4.4 + Amendment A2, C12). ONE FIELD, AND THE LIE IS WHICH
	VALUE IT HOLDS RATHER THAN WHAT SHAPE IT IS.

	Every player receives this, at STARTING, in one loop, with one payload shape. Survivors receive
	this round's real five; the Aswang receives a decoy five drawn from the same pool. Nothing about
	the send distinguishes them — same moment, same field, same count — which is the property that
	survives a compromised client reading its own traffic.

	IT IS NOT A SECRET AND MUST NEVER BE TREATED AS ONE. `ActiveTaskPoint` tags replicate, so a
	compromised client reads the true five directly off CollectionService and the decoy is defeated in
	one line. This is a UX affordance for honest clients and a cost in walking distance for an honest
	Aswang. No balance decision may depend on it.
]]
export type TaskListPayload = {
	TaskIds: { string },
}

--[[
	What should happen to one fetch item this tick (§4.4, C09) — the verdict from
	`server/pure/FetchCarry.luau`.

	SAFE TO LOG AND SAFE TO ACT ON IN THE OPEN, unlike every other verdict in this file. It describes
	an object in the workspace that every client can already see, and the object's own position states
	the outcome one tick later regardless.

	DROP is the interesting one and it is deliberately not called "death". A carrier stops carrying
	when they stop being a full contributor, and being killed is only one of the four ways that
	happens — disconnecting, being reset, and joining as a spectator are the others. Naming the action
	after the cause would have meant a branch per cause, and three of them would have been missed.
]]
export type FetchAction = "NONE" | "PICK_UP" | "DELIVER" | "DROP"

--[[
	Why the server refused (or failed) a RequestThrowSalt (§4.6, C14). Same shape and same rule as
	KillVerdict: a union so the server can log WHY, and NEVER echoed to any client.

	MISS IS THE ONE THAT CARRIES THE DESIGN, and it is deliberately a single value covering four
	different worlds:

	  · the cone was empty
	  · the cone held a survivor
	  · the cone held the Aswang, untransformed
	  · the cone held the Aswang, transformed, but past ThrowRange

	Splitting them is the obvious refactor and it is a role oracle. `MISS_NOT_ASWANG` versus
	`MISS_OUT_OF_RANGE` would let a compromised client stand in front of each player in turn, throw,
	and read the monster off the refusal — and it would do it for the price of one pouch, which is
	the price §4.6 already charges for a legitimate reveal. There is no safe subset to return, so the
	handler returns NOTHING on every value including OK; what the world does is the only answer.

	NO_POUCH is the C13 half: you are not carrying salt. It is also never echoed, because the client
	already knows what it is carrying — the server told it and it can count its own pickups.
]]
export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"

--[[
	The salt throw, broadcast to every client (§4.6, C14). THREE FIELDS, ALL ABOUT A TRAJECTORY AND
	NONE ABOUT A PLAYER.

	It does NOT carry the thrower, the target, or a UserId of any kind. A throw is a thing that
	happens in the world — a white burst at a place — and every client standing there sees it whether
	or not this remote exists.

	`Hit` IS SAFE AND IS NOT THE REVEAL. It says "the salt struck something the salt can strike",
	which given SaltVerdict above means "a transformed Aswang", and a transformed Aswang is ALREADY
	public: `MonsterTransformed` broadcast it, by design (see MonsterTransformedPayload). This field
	is what lets a client play a hit sound instead of a fizzle. The information that is genuinely new
	— WHO it was, once they revert — arrives as a Highlight on a character in the workspace, not on
	this payload.

	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
	table is accepted silently by the typechecker, and `SaltEffect` is not on check-secrecy.mjs's
	REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, catching a field named `role`
	or `aswang` or `killer` and catching nothing else. A field named `TargetUserId` would pass every
	check in this repo and would name the monster to eight clients.
]]
export type SaltEffectPayload = {
	Origin: Vector3,
	Impact: Vector3,
	Hit: boolean,
}

--[[
	Who the other ghosts are (§4.7, C15). Fired ONLY to players whose own state is GHOST.

	IT CARRIES UserIds AND THAT IS SAFE, for one reason that must stay true: being dead is not a
	role. A ghost is a player the Aswang has already killed, or one who died some other way, and
	`PlayerKilled` used to broadcast exactly this fact to every client until Amendment A3 stopped it.
	What makes this payload safe is not its contents but its RECIPIENTS — the server fires it per
	player and never with FireAllClients, and the one thing a living client must not learn is which
	of the eight are dead, because that is the death oracle Amendment A3 exists to close.

	So the rule for this remote is the mirror of RoleAssigned's: RoleAssigned is safe because its
	payload is minimal, this is safe because its audience is. Widening the audience is the leak, and
	no check in this repo would see it — `check-secrecy.mjs` reads payload fields and call shapes,
	and `FireClient(player, roster)` inside a loop over the wrong list looks identical to the right
	one. The state test belongs at the fire site for that reason.
]]
export type GhostRosterPayload = {
	UserIds: { number },
}

--[[
	Why the server refused a RequestGhostSpook (§4.7, C16). Same shape and same rule as every other
	verdict here: a union so the server can log WHY, and never echoed.

	NOT_GHOST is a refusal and not an accusation — a living player's client has no spook button, so
	reaching this value means either a stale button on a player who was just revived by a round
	ending, or a compromised client. Both look the same from here, which is why C41 reads the log
	rather than this function.
]]
export type SpookVerdict =
	"OK"
	| "WRONG_PHASE"
	| "NOT_GHOST"
	| "NO_SPOOKS_LEFT"
	| "NOTHING_IN_RANGE"

--[[
	§4.5, C25. The eight phrases, as IDS rather than as strings.

	THE WHOLE SECURITY DESIGN OF THIS FEATURE IS THAT THIS IS A CLOSED UNION. `RequestQuickChat`
	carries one of these and nothing else — no name, no position, no free text — which puts it in the
	same class as `RequestTimingStop` and `RequestStartTrial`, remotes built so that there is no
	argument in which a client could name a person, a place or an outcome.

	The display strings live in `shared/pure/QuickChatPhrases` and are rendered by the RECEIVER from
	the id. That is what removes user-generated text from the wire entirely — see QuickChatService's
	header for why that also removes the TextService question.
]]
export type QuickChatPhraseId =
	"SAW_TRANSFORM"
	| "BODY_HERE"
	| "FOLLOW_ME"
	| "ACCUSE"
	| "TASK_HERE"
	| "RUN"
	| "IM_ALONE"
	| "TRUST_ME"

--[[
	Why the server refused a RequestQuickChat. Same shape and same rule as SpookVerdict above: a union
	so the server can log WHY, and never echoed to the client.

	LOGGED, NEVER ECHOED — not even to the sender. GhostService's spook handler states the reason and
	it applies here unchanged: a verdict returned to a client is a STATE ORACLE.
	`NOT_ALLOWED_FOR_STATE` echoed back would let a player fire the wheel and read their own aliveness
	off the refusal, which is the death signal Amendment A3 removed `AlivePlayerCount` to close,
	rebuilt out of an error code.

	SO HOW DOES THE SENDER KNOW IT FAILED? They receive their own broadcast, like everyone else. A
	message that appears succeeded; one that does not, did not. That is a complete signal, it needs no
	remote, and it cannot be fired as a probe because the absence carries no detail.
]]
export type QuickChatVerdict =
	"OK"
	| "WRONG_PHASE"
	| "UNKNOWN_PHRASE"
	| "NOT_ALLOWED_FOR_STATE"
	| "NO_SENDER_CHARACTER"
	| "NO_TARGET_IN_SIGHT"

--[[
	C25. What `QuickChatBroadcast` carries, and the reason it is written as a closed type.

	FOUR FIELDS, NO STRINGS. Every one is either a UserId the receiver can already resolve or a
	position the SERVER derived from its own copy of the sender's character.

	  · SenderUserId  — who said it. Attributable by design: an accusation nobody can attribute is
	    not an accusation, and the cost of accusing is that you are on record.
	  · PhraseId      — rendered locally from `pure/QuickChatPhrases`. Never a string on the wire.
	  · TargetUserId  — present ONLY for ACCUSE, and only for a player the sender could see. Range
	    AND line of sight are both checked server-side, so this names somebody the sender's own eyes
	    already named. See the liveness note in the C25 plan's Follow Ups for the residual leak.
	  · PingPosition  — the SENDER's own root position at the instant the request landed, present
	    only for phrases whose meaning is locative. Never client-supplied: a client-named position is
	    a "draw an arrow anywhere" primitive, including on top of a player.

	NO PlayerState FIELD, AND THERE MUST NEVER BE ONE. Amendment A3 removed `AlivePlayerCount`
	because a death signal is the missing input to a position-correlation attack, and a field saying
	"the sender is ALIVE" would be that signal wearing a different hat. The audience filter already
	encodes the same fact for the recipients entitled to it, and encodes it by WHO RECEIVES rather
	than by what is written down — the same asymmetry that makes `GhostRoster` safe.
]]
export type QuickChatBroadcastPayload = {
	SenderUserId: number,
	PhraseId: QuickChatPhraseId,
	TargetUserId: number?,
	PingPosition: Vector3?,
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
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}

--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).

	`AlivePlayerCount: number` sat between GateOpen and YourRole and was pushed to every client every
	`Round.SnapshotInterval` (0.5s), plus an immediate extra push from `MarkKilled` the instant a
	death landed. That made it a sub-second global death signal, and a death signal is an input to an
	attack this game cannot survive: record replicated character positions, timestamp each kill from
	the decrement, then ask who was within `Monster.KillRange` (8 studs) of the victim's last known
	position at that instant. In the open that is often one candidate. In a group it narrows the
	field, which is damaging on its own.

	DELAYING IT WAS CONSIDERED AND REJECTED. A fixed delay is a constant, and a constant is something
	an attacker subtracts; it converts a zero-latency oracle into a zero-latency oracle with an
	offset. A jittered delay is worse, because it is a claim of safety that is only ever statistical.

	WHAT A CLIENT LEARNS ABOUT A DEATH NOW, in full:
	  · the corpse, standing where the victim fell for `Monster.CorpseDuration` — LOCAL, discovery
	    latency, and under §5's StreamingEnabled it does not replicate at all from far away. This is
	    the signal the design wants and the only one the design wants.
	  · `SaltEffect` — a public world event that names nobody.
	  · `PlayerKilled` — fired to the victim alone since Amendment A3.

	DO NOT REINTRODUCE IT UNDER ANOTHER NAME. `SurvivorsRemaining`, `DeadCount`, `RosterSize` and a
	`YourState`-derived tally over a roster field are the same oracle wearing different words, and
	none of them contains a token `check-secrecy.mjs` matches. C18 wants an alive count on the HUD
	(BUILD-PLAN ~line 456) and this is the field it would reach for; Amendment A3 is the sentence
	that says no.
]]

--[[
	THE SOLO TRIAL'S TYPES (C21, §9.1), AND WHY THEY SHARE NOTHING WITH THE ROUND'S.

	Luau unions are STRUCTURAL. A `TrialPhase` whose literals overlapped `RoundPhase`'s would be
	assignable to a `RoundPhase` parameter with no cast and no analyzer complaint, which is a compile-
	time hole underneath the one rule this whole feature exists to keep: the trial cannot advance,
	end or observe a round. Not one string below appears in `RoundPhase` above.

	`TrialSnapshot` is the other half. It carries no field name `ClientRoundSnapshot` carries — no
	`Phase`, no `SecondsRemaining`, no `RoundNumber`, no `YourState` — so a handler wired to the wrong
	remote fails to typecheck rather than rendering trial state as round state. `check:remotes` and
	`check:secrecy` are text tripwires and would both pass a semantic mix-up like that; the type is
	what actually catches it.
]]
export type TrialPhase = "TRIAL_OFF" | "TRIAL_TASKS" | "TRIAL_CHASE" | "TRIAL_HANDOFF"

-- What the timeline fires, in order. FIRE-ONCE per session — see `shared/pure/TrialTimeline`.
export type TrialBeat =
	"BEAT_WELCOME"
	| "BEAT_TASKS"
	| "BEAT_SALT_GIVEN"
	| "BEAT_TRANSFORM"
	| "BEAT_SALT_TAUGHT"
	| "BEAT_HANDOFF"

-- Why a session ended. Read by nothing but a log line and the handoff copy, but naming the five
-- exits is what stops a sixth being added silently.
export type TrialEndReason =
	"COMPLETED"
	| "EXPIRED"
	| "PLAYER_LEFT"
	| "PLAYER_ASKED"
	| "ROUND_STARTED"

-- The answer to "may this player start a trial right now", decided by `shared/pure/TrialAdmission`.
export type TrialStartVerdict =
	"OK"
	| "DISABLED"
	| "ALREADY_IN_TRIAL"
	| "ROUND_NOT_IDLE"
	| "TOO_MANY_PLAYERS"

--[[
	FireClient to the ONE player in the session. Never FireAllClients, and there is no roster field to
	make that tempting: everything here describes the receiver's own session and is worthless to
	anybody else. The trial's Aswang is a scripted rig with no UserId and no role, so unlike every
	other payload in this file there is no secret in the vicinity of this one.
]]
export type TrialSnapshot = {
	TrialPhase: TrialPhase,
	Beat: TrialBeat?, -- the beat that just fired, if this push carries one
	TrialSecondsLeft: number,
	TrialTasksDone: number,
	TrialTasksRequired: number,
}

-- C23. The id of a one-liner, resolved to copy by `shared/pure/TeachingLines`. An ID rather than the
-- string itself so the copy lives in one place and the seen-set is keyed on something stable.
export type TeachingCueId =
	"CUE_FIRST_SALT"
	| "CUE_FIRST_GHOST_DEATH"
	| "CUE_FIRST_TRANSFORM_SEEN"
	| "CUE_FIRST_TWO_PERSON"

return {}
