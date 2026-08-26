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
export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
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
	--[[
		§6.6's fourth field, missing from the scaffold. A CACHE STAMP, not an entitlement: it records
		when this server last asked Roblox which gamepasses the player owns, so C35 can avoid a
		`UserOwnsGamePassAsync` call on every check. Ownership itself is never stored here — a cached
		"owns it" is a value that survives a refund, and the authority is Roblox, not us.
	]]
	Purchases: {
		GamepassCacheUTC: number,
	},
	--[[
		WHEN THIS GAME FIRST SAW THIS PLAYER (v2, C35). Stamped once at session start and never
		rewritten, because the one thing that reads it — Appendix B's `Balik-Balik` badge — is asking
		whether TODAY is a different UTC day from the first one, and a field that moved would answer
		"no" forever.

		SERVER-ONLY LIKE THE REST OF THIS TYPE, and not in `ProfileSnapshot`. It is not secret, it is
		simply not the client's business: nothing on the HUD renders it, and the rule for that payload
		is an explicit field list rather than whatever happens to be harmless.
	]]
	FirstSeenUTC: number,
	--[[
		§9.2's one-time group join reward, paid once and never again (C39). A profile boolean rather
		than a live `Player:IsInGroup` check, because membership can be left and rejoined and the
		reward cannot.

		THE CLIENT DOES SEE THIS ONE — `ProfileSnapshot.GroupRewardClaimed` mirrors it, unlike
		`FirstSeenUTC` above, and the difference is what the field is FOR. A first-seen timestamp
		decides a badge the server awards; a claim flag decides what a lobby button says, and a button
		that cannot tell "claim" from "claimed" offers a reward it will silently refuse.

		Sending it changes nothing about who decides. `CommunityService` re-reads THIS field on every
		claim and re-asks Roblox about membership — the snapshot is what the button renders, never
		what the server trusts.
	]]
	GroupRewardClaimed: boolean,
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
	The verdict from `server/pure/SearchPool.luau` (C07, V01) — is the map's tagged pool usable.

	EMPTY and SHORT are the two that BLOCK a draw. DUPLICATE_ID and OVERSIZED are loud and
	non-blocking: the round still runs, and the map still has a defect somebody has to fix. That split
	is why this is a union rather than a boolean — "unusable" and "usable but wrong" send a reader to
	two different places, and a boolean would collapse them into a shrug.

	This one is SAFE TO LOG AND SAFE TO SHOW. It describes the map, not a player, and every fact in it
	is readable off the workspace by any client that cares to count tagged parts.
]]
export type SearchPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"

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
	PlayerStates: { [number]: PlayerState }, -- keyed by UserId
}

-- What the client is allowed to know. Note the absence of AswangUserId.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}

--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).

	`AlivePlayerCount: number` sat between RoundNumber and YourRole and was pushed to every client every
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
export type TeachingCueId = "CUE_FIRST_SALT" | "CUE_FIRST_TRANSFORM_SEEN"

--[[
	One line of the end screen's XP breakdown (C32). Plain strings and numbers — the copy is already
	public and no literal union travels inside this list.
]]
export type AwardLine = {
	Label: string,
	XP: number,
	Coins: number,
}

export type RoundAward = {
	XP: number,
	Coins: number,
	Lines: { AwardLine },
}

-- What the lobby's daily button needs to draw itself (C33). A preview, never a claim: pressing it
-- fires `RequestClaimDaily` and `DailyService` re-runs `pure/DailyStreak` and decides.
export type DailyPreview = {
	Claimable: boolean,
	Streak: number,
	CycleDay: number,
	RewardXP: number,
	RewardCoins: number,
}

--[[
	THE `ProfileUpdated` PAYLOAD (C32/C33/C34), AND `PlayerProfile` IS NOT IT.

	READ THE RoundEndedPayload COMMENT ABOVE FIRST — both of its warnings apply here and neither guard
	is watching this remote:

	  · Luau accepts an EXTRA field on an annotated table silently. Measured, and still true.
	  · `check-secrecy.mjs` checks payload FIELDS only for remotes on its REVEAL_ALLOWLIST, and
	    `ProfileUpdated` is deliberately NOT on that list — it carries no role, so it must keep being
	    scanned like any other remote rather than being skipped like the two that do.

	So this type is the whole of the enforcement, and it is an EXPLICIT FIELD LIST rather than a
	trimmed profile. `PlayerProfile.Stats` holds `AswangRounds` and `AswangWins` — a per-player history
	of drawing the role — and the way that never reaches a client is that there is no field here for it
	to arrive in. `Remotes.luau`'s entry says the same thing; adding a field to this type is a decision
	to review by hand, because nothing mechanical will review it.

	FIRED TO ONE PLAYER, ALWAYS. Every field describes the receiver: their own XP, their own coins,
	their own inventory. A `FireAllClients` of this payload would hand eight clients eight players'
	levels and owned sets, which is enough to follow a specific person across rounds.
]]
export type ProfileSnapshot = {
	XP: number,
	Level: number,
	-- The level bar, pre-divided by `pure/XPCurve` so the client never does the arithmetic and the two
	-- ends cannot disagree about where the fill sits. `XPForNextLevel` is 0 at the cap, and a client
	-- that divides by it gets a NaN — so `Progress` is sent as well and is what the bar reads.
	XPIntoLevel: number,
	XPForNextLevel: number,
	Progress: number, -- 0..1
	Coins: number,
	Equipped: {
		Skin: string,
		Lantern: string,
		DeathFX: string,
	},
	-- The receiver's OWN inventory, as an id -> true set. Never anyone else's.
	Owned: { [string]: boolean },
	Daily: DailyPreview,
	--[[
		C39, §9.2. Whether this player has already taken the one-time group join reward, so the lobby
		panel can render "claimed" instead of offering a claim the server will refuse.

		A BOOLEAN ABOUT THE RECEIVER, like every other field here. It says nothing about anyone else,
		and group membership is public on a Roblox profile page in any case. It is NOT authority: the
		server re-reads `PlayerProfile.GroupRewardClaimed` and re-asks `IsInGroupAsync` on every claim.
	]]
	GroupRewardClaimed: boolean,
	-- Present only on the push that follows a round, so the end screen can show what was earned and
	-- every other push leaves it nil rather than repeating a stale award.
	LastAward: RoundAward?,
}

return {}
