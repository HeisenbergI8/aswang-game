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

--[[
	THE v2.0 VOCABULARY (V02). Declared here rather than in `Enums.luau` because Enums requires this
	module for its `:: Types.X` casts, and a union that lives beside its consumer cannot be cast to.

	All four are UPPER_SNAKE string literals, matching the four above: readable in a log line, readable
	in analytics, and — unlike a number — impossible to confuse with an unrelated enum of the same
	arity. Luau unions are structural, so none of these is assignable to `RoundPhase` or to each other.
]]

-- §4.4/§4.6. The three things folklore says stop an aswang, and the entire item vocabulary of v2.0.
-- §3's OUT list forbids a fourth; `check:scope` watches `weapons?` for the day someone adds one.
export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"

--[[
	§4.3. What the Aswang is doing right now.

	NORMAL and TRANSFORMED are the v1.3 pair. FEEDING (§4.3) is the 5-second lock on a corpse that
	replaced the kill cooldown. CAMOUFLAGED (§4.3) is the ambient-animal form. EXPOSED is the odd one
	out and it is a QUESTION for the chunk that builds the state machine, not for V02 — see Follow Ups:
	§4.3 says camouflage is locked "until it has taken a salt hit", which reads as a LATCH that persists
	across transforms and feeds, while the other four read as mutually-exclusive activities. V02
	declares the five values the build plan asks for and takes no position on exclusivity.
]]
export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"

--[[
	§4.7. A body on the ground is one of two things, and telling them apart is a DESIGN GOAL rather
	than a leak: §4.7 requires husk state to be "publicly obvious", because a husk that differed from a
	live body in some replicated-but-subtle way would let a client enumerate exactly which bodies are
	husks — and since the Aswang can never be one, every husk is provably innocent. Public information
	cannot be exploited; half-hidden information can.

	Neither literal contains the word `ghost`, which `check:scope` arms as of V01. That is not luck —
	`check-scope.mjs` names corpse and husk as its two ALLOW cases.
]]
export type BodyKind = "CORPSE" | "HUSK"

--[[
	§4.3. What a revealed Aswang can turn into. Six ambient forms so the barrio's scenery is a place
	the monster can hide IN rather than a backdrop, and so §4.5's "It's the [animal]!" phrase has a
	closed set of things it can name.

	SIX RATHER THAN FOUR, AND THE POPULATION DID NOT GROW TO PAY FOR IT. `Config.Ambient.PerForm`
	drops 4 -> 3 in the same change, so the barrio carries 18 entities instead of 16. §5 asks for
	"3-4 each"; three is inside that and above the secrecy floor `tests/config.test.luau` pins.

	WHY THESE TWO. Both are animals a rural Philippine barrio genuinely carries in numbers, and both
	are TETHERED OR YARD-BOUND in life rather than free-roaming — goats are tethered and rotated at a
	field edge, chickens forage a household yard. That is what lets each form have a TERRITORY without
	the constraint reading as an arbitrary game rule, which matters because the territory is also a
	constraint on the monster: a pig on the basketball court is now wrong, so the Aswang can only wear
	a pig near the mud. That is deliberate and it is the counterplay §4.5 asks for.

	NOT A PET SYSTEM, and the distance matters because `check:scope` arms `pets?`. These are forms the
	Aswang wears, owned by nobody, purchasable never (§8.3).
]]
export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"

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
-- ⚠️ V08 IS RETIRING THIS. `ItemService.resolveThrow` is its last reader and Step 4.2 replaces it
-- with `ItemThrowVerdict` below. It survives only so Phases 2 and 3 leave a green tree; do not wire
-- anything new to it.
export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"

--[[
	V08, §4.6. THE THREE ITEM VERDICTS, AND WHY THEY ARE THREE UNIONS RATHER THAN ONE.

	Each one is the return type of a different pure module, and the modules refuse for different
	reasons at different moments: `ItemCarry` refuses a pickup, `ItemThrow` refuses a use, and the
	drop refuses a put-down. One merged union would let a handler compare against a value its module
	can never return, which compiles and means nothing.

	ALL THREE ARE PREFIXED `ITEM_`, and that is `SearchVerdict`'s rule below, restated because it is
	not decoration. `SaltVerdict` above carries a bare `WRONG_PHASE` and `MonsterState` a bare
	`NORMAL`; three more unions spelling it the same way makes a handler wired to the wrong path a
	working program with the wrong meaning. `check:remotes` and `check:secrecy` are text tripwires
	and cannot see that. The prefix makes it an analyzer error instead.

	NONE OF THE THREE IS EVER ECHOED TO A CLIENT. This is `SaltVerdict`'s rule inherited verbatim:
	`ItemService`'s handlers return nothing on any path, including OK, and the client learns what
	happened from the world and from its own snapshot. A verdict echoed back is a role oracle for the
	price of one pouch — see `pure/ItemThrow`'s header for the five worlds that argument covers.
]]
export type ItemCarryVerdict =
	"OK"
	| "ITEM_WRONG_PHASE"
	| "ITEM_NOT_ALIVE"
	| "ITEM_SLOT_FULL"
	| "ITEM_NO_LIMIT_SET"

export type ItemThrowVerdict =
	"OK"
	| "ITEM_WRONG_PHASE"
	| "ITEM_THROWER_NOT_ALIVE"
	| "ITEM_NO_ITEM"
	| "MISS"

--[[
	THE DROP, AND IT HAS NO GEOMETRY AT ALL. You may put down what you are holding, wherever you are
	standing, whenever you are alive in an ACTIVE round. There is no "you cannot drop here".

	A PLACEMENT RULE WOULD BE V09'S, NOT V08'S. Bawang is PLACED on a doorway and that placement has
	conditions; dropping is the plain act of ceasing to hold something, and conflating the two now
	would build half of V09 inside V08 with none of its rules written down.
]]
export type ItemDropVerdict = "OK" | "ITEM_WRONG_PHASE" | "ITEM_NOT_ALIVE" | "ITEM_NOTHING_HELD"

--[[
	V08, §4.6. WHAT `pure/ItemUse` ANSWERS — which verb, if any, this item currently has.

	`USE_NOT_IMPLEMENTED` WAS THE V09/V10 BOUNDARY AND IS GONE AS OF V10, which is that boundary
	CLOSING rather than a tidy-up. It was deliberately a value rather than a gap: V08 gave all three
	items carry, drop and a slot and only salt a verb, so the hole was asserted in
	`tests/item-use.test.luau` rather than left to be discovered. V09 filled bawang's, V10 fills the
	buntot pagi's, and a value no item can return is exactly the dead path `pure/ItemUse`'s header
	refuses ("it is not a feature flag").

	THREE ITEMS, THREE VERBS, AND AN EMPTY HAND. What this union pins from here is the ROUTING — each
	item maps to exactly one verb and no two share — which is the property `InputController` and
	`ItemService`'s throw handler both depend on and neither states.
]]
export type ItemUseVerdict = "USE_THROW" | "USE_PLACE" | "USE_STRIKE" | "USE_NOTHING_HELD"

--[[
	V09, §4.6. MAY THIS PLAYER PUT BAWANG ON THIS DOORWAY?

	PREFIXED `GARLIC_`, which is `ItemCarryVerdict`'s rule and `SearchVerdict`'s before it. A fourth
	union sharing the bare `WRONG_PHASE` spelling makes a handler wired to the wrong path a working
	program with the wrong meaning, and this one runs beside three others in the same service.

	NOTHING HERE IS ECHOED BACK TO THE CALLER, on any path including OK — the throw handler's rule and
	the drop handler's, inherited. `GARLIC_DOORWAY_TAKEN` in particular would be a free doorway probe:
	fire the remote from across the barrio and difference the refusals to learn which doorways are
	sealed without walking to any of them. It exists so the server can log WHY.

	IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching and carrying on
	identical rules, so the monster reaches this union and gets `GARLIC_OK` exactly as a survivor
	does — and is then blocked by its own garlic, which is correct and is the funniest outcome in the
	chunk. A "the monster may not place" verdict would be an oracle readable by pressing a key.
]]
export type GarlicPlaceVerdict =
	"GARLIC_OK"
	| "GARLIC_WRONG_PHASE"
	| "GARLIC_NOT_ALIVE"
	| "GARLIC_NOT_HELD"
	| "GARLIC_NO_DOORWAY"
	| "GARLIC_DOORWAY_TAKEN"

--[[
	V10, §4.6. WHY THE SERVER REFUSED — OR DID NOT REFUSE — A `RequestStrike`. Mirrored from
	`pure/StrikeValidation.Verdict`.

	PREFIXED `STRIKE_`, which is `ItemCarryVerdict`'s rule and `SearchVerdict`'s before it. A sixth
	union sharing a bare `WRONG_PHASE` spelling makes a handler wired to the wrong path a working
	program with the wrong meaning. It matters more here than anywhere else in this file because
	`ItemService`'s strike handler tests verdict values BY NAME to decide whether to spend the round's
	only win condition; a spelling collision there is a destroyed win condition.

	IT IS NEVER ECHOED TO A CLIENT, which is `SaltVerdict`'s rule and `KillVerdict`'s — and here it is
	the WHOLE mechanic rather than a precaution. See `pure/StrikeValidation`'s header: the four
	target-side worlds are collapsed into ONE value on purpose, so that even a future author who
	echoed this union by mistake would echo nothing usable. "Never echoed" is a rule someone has to
	keep; "nothing to echo" is a property. The union is shaped so the leak is unavailable.

	FIVE VALUES: a kill, THREE about the striker's own business, and ONE for every world that involves
	a target. There is no `STRIKE_NOT_EXPOSED`, no `STRIKE_NOT_WEAKENED`, no `STRIKE_NO_TARGET` and no
	`STRIKE_TARGET_NOT_ALIVE`. Adding any of them reds the indistinguishability property in
	`tests/strike-validation.test.luau`, which is where the argument for their absence is enforced
	rather than remembered.

	THE THREE STRIKER-SIDE VALUES ARE ALLOWED TO DIFFER because they sit ABOVE the spend line and
	describe facts the striker already holds: their own phase, their own aliveness, their own hand.
	Nothing about anybody else is derivable from any of them.
]]
export type StrikeVerdict =
	"STRIKE_KILL"
	| "STRIKE_WRONG_PHASE"
	| "STRIKE_NOT_ALIVE"
	| "STRIKE_NOT_HELD"
	| "STRIKE_NO_EFFECT"

--[[
	V09, §4.6. ONE LIVE BARRIER, AS THE ASWANG'S OWN CLIENT NEEDS IT TO BUILD A COLLIDABLE PART.

	WHAT IS ABSENT IS THE SECURITY DESIGN, and every absence is deliberate:

	  · NO PLACER. Not a UserId, not a name, not a `PlacedByYou`. Who put the garlic there is a fact
	    about a player, and the recipient is the one player in the round who must not be handed a
	    survivor's movements for free. `placeItem`'s header refuses the same field on the dropped part.
	  · NO DOORWAY ID. With no key in the payload there is nothing to log, difference or accumulate —
	    `SearchUpdatePayload`'s structural argument. The Aswang can see the garlic on the doorway; the
	    server never tells it which doorway the doorway is.
	  · NO ROLE, AND NO FLAG THAT WOULD IMPLY ONE. The recipient is resolved server-side from
	    `RoundService.GetAswangUserId()`, exactly as `FeedUpdate` and `CamouflageUpdate` resolve theirs.

	`SecondsRemaining` RATHER THAN AN EXPIRY TIMESTAMP. A server `os.clock()` is meaningless on a
	client and an `os.time()` would be a shared clock two clients could difference. A duration is what
	the client needs and states nothing about when the round started.
]]
export type GarlicBarrierSpec = {
	Position: Vector3,
	Yaw: number,
	Width: number,
	Height: number,
	SecondsRemaining: number,
}

--[[
	V09. A FULL SNAPSHOT OF THE LIVE BARRIERS, NOT A DELTA, and `RequestSearch`/`RequestCancelSearch`'s
	header is the argument: two messages for one state are how a client and a server come to disagree
	about it. A dropped "barrier added" leaves the Aswang walking through garlic; a dropped "barrier
	expired" leaves it walled out of a room forever. A snapshot cannot desync, is idempotent on a
	duplicate, and re-sending it on `CharacterAdded` is the whole of the rejoin path.

	AT MOST `Config.Items.GarlicSpawnCount` ENTRIES — two. The list is not a cost worth optimising.
]]
export type GarlicBarriersPayload = {
	Barriers: { GarlicBarrierSpec },
}

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
	--[[
		V02, §4.4. WHAT THE RECEIVING PLAYER IS CARRYING, AND THE `Your` PREFIX IS THE WHOLE CONTRACT.

		Safe for a reason that is structural rather than argued: `RoundSnapshot` is built per player and
		sent with `:FireClient` precisely because `YourState` already differs between a survivor and a
		mid-round spectator. There is no broadcast form of this payload to accidentally put someone
		else's inventory on.

		IT IS NOT A ROLE ORACLE. The Aswang carries nothing — the three items are the survivors' (§4.6)
		— so its slot is `nil`, which is also what an empty-handed survivor's slot is. The two are
		indistinguishable, and they must stay that way: do not add a "cannot carry" or "carry denied"
		value to `ItemType` for the monster's benefit.

		IT IS NOT A DEATH SIGNAL. It is not a count, it does not move when another player dies, and it
		says nothing about the roster. Amendment A3 (§4.7) is untouched by it.

		CARRY IS DELIBERATELY NOT PUBLIC. §4.5's v2 phrase list includes "I have the buntot pagi" —
		announcing what you hold is a CHOICE with a cost, and that is what turns the single buntot pagi
		into a protection problem. A field that told every client who held it would delete that phrase's
		reason to exist. So: never widen this to another player's carry, and never mirror it onto an
		attribute or a tag, both of which replicate to everyone.

		OPTIONAL BECAUSE `Config.Items.*SpawnCount` PLUS `Config.Items.CarryLimit = 1` MEAN ONE SLOT.
		If the carry limit ever rises this becomes a list, and that is a contract change to argue in a
		plan rather than a field to widen quietly.

		V02 ADDS NO PRODUCER. `buildSnapshot` does not set it, exactly as it deliberately does not set
		`YourRole`, so no service changes and `analyze` stays clean.
	]]
	YourCarriedItem: ItemType?,
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

	V02: STILL NO, AND v2.0 MAKES IT WORSE RATHER THAN BETTER. `Round.MaxPlayers` drops from 8 to 5
	(§C, spec line 873), so every survivor is a fifth of the field instead of an eighth and a count
	narrows it twice as fast. The Aswang must now kill EVERYONE (§4.1), which means the count would
	also be a live progress bar on the monster's own win condition — for both sides, for free.
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

--[[
	V03, §4.4. The answer to "may I search what I am standing at, and what did I get".

	PREFIXED `SEARCH_` FOR `TrialPhase`'S REASON, restated because it is not decoration. `SaltVerdict`
	already carries a bare `WRONG_PHASE` and `MonsterState` a bare `NORMAL`; a third union sharing
	those spellings makes a handler wired to the wrong remote a working program with the wrong
	meaning. `check:remotes` and `check:secrecy` are text tripwires and would pass a semantic mix-up
	like that. The prefix makes it an analyzer error instead.

	SEARCH_STARTED IS A VERDICT RATHER THAN A SECOND REMOTE. The client needs to know its hold began
	so it can draw a bar; that is the same conversation as the refusals, on the same wire, to the same
	one player.

	NONE OF THESE NAMES A CONTAINER, AND NONE NAMES A PLAYER. `SEARCH_OCCUPIED` says "someone is at
	this one" and `SEARCH_ALREADY_SEARCHED` says "this one is spent" — both are facts about the world
	that §4.4 puts in the world deliberately ("items belong to the world, not to individuals"), both
	concern a container the receiver is already standing at, and neither is role-correlated because
	the Aswang searches on identical rules.
]]
export type SearchVerdict =
	"SEARCH_STARTED" -- the hold began; HoldSeconds is how long it will take
	| "SEARCH_OK" -- the hold completed; `Found` is the item, or nil for an empty container
	| "SEARCH_INTERRUPTED" -- you cancelled, moved out of range, died, or the round moved on
	| "SEARCH_WRONG_PHASE" -- searching is an ACTIVE-phase activity and nothing else
	| "SEARCH_NOT_ALIVE" -- dead players and mid-round spectators do not search
	| "SEARCH_NO_CONTAINER" -- nothing tagged within Config.Search.RangeStuds, or the map has no pool
	| "SEARCH_OCCUPIED" -- somebody else is holding this container right now
	| "SEARCH_ALREADY_SEARCHED" -- this container was opened earlier in the round
	| "SEARCH_BUSY" -- you are already holding a different container

--[[
	V03, §4.4. `SearchUpdate`'s payload. FireClient to ONE player, always; there is no broadcast form
	of this remote and there must not be.

	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:

	  · NO CONTAINER ID, in either direction. The client does not name one when it requests — the
	    server resolves the nearest tagged part from that player's own character position, which is
	    `ItemService`'s stated rule for pickups — and the server does not name one when it answers.
	    There is therefore NO KEY ON WHICH TWO CLIENTS COULD DIFFERENCE THEIR PAYLOADS. What colluding
	    players can pool is what each of them found by standing somewhere and opening something, which
	    is the information §4.4 intends them to have and §4.5 gives them a phrase for.
	  · NO LAYOUT, NO REMAINING COUNT, NO "3 of 7 found". A count is a map index compressed: it tells
	    a client how much of the pool is still worth walking to, which is exactly the walk §4.4 wants
	    to cost something. It also would not survive Amendment A3's spirit — see `ClientRoundSnapshot`.
	  · NO SEARCHER. `SEARCH_OCCUPIED` does not say who.

	`Found` IS NOT A ROLE ORACLE. The Aswang searches on identical rules and can find any of the three
	(§4.4 — denying survivors the buntot pagi is a legitimate strategy that looks exactly like
	survival), so this field's value distribution is the same for both roles.
]]
export type SearchUpdatePayload = {
	Verdict: SearchVerdict,
	-- Config.Search.SearchTime on SEARCH_STARTED, 0 on every other verdict. The client draws its own
	-- bar from this one number; the server does not stream progress, because a per-frame per-player
	-- remote would be a network cost paid for something the client can interpolate. It carries no
	-- information — Config is replicated, so the client already knew it.
	HoldSeconds: number,
	-- What THIS player just found. nil on every path except a completed search of a seeded container,
	-- including a completed search of an empty one — "you searched it and it held nothing" and "you
	-- did not finish" are different verdicts, not different Found values.
	Found: ItemType?,
}

--[[
	V06, §4.3. WHAT A FEED LOOKS LIKE TO THE ONE PLAYER DOING IT.

	THREE OUTCOMES, NOT SIX REASONS. `pure/FeedRules` returns six verdicts and five of them are
	refusals; those exist for the server's log and none of them crosses the wire. What the feeder
	needs is the same three things a searcher needs — it started, it finished, it broke — which is why
	this union is shaped like `SearchVerdict`'s first three values and not like the pure module's.

	`FEED_INTERRUPTED` IS ONE VALUE COVERING SIX PATHS: salt, walking past the leash, the corpse
	fading or being destroyed, dying, the round ending, and disconnecting. Splitting them would tell
	the Aswang WHY its feed broke, and the one it would most like to know — "was that salt, or did I
	drift?" — is a fact about a survivor's aim that the monster should have to work out by looking.
]]
export type FeedVerdict =
	"FEED_STARTED" -- the feed began; HoldSeconds is how long it will take
	| "FEED_OK" -- the feed completed; the heal has already been applied server-side
	| "FEED_INTERRUPTED" -- it broke, by any of six paths, and paid nothing

--[[
	V06, §4.3. `FeedUpdate`'s payload. FireClient to the ONE player whose feed it is, always; there is
	no broadcast form of this remote and there must not be.

	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:

	  · NO HEALTH, in any form — not a value, not a fraction, not a "you are weak now". §4.6 is
	    explicit that "a health value attached to a player is the reveal", and the ONLY licensed
	    readout is the Exposed glow's brightness, which exists only while the licence does. A feed
	    changes the health and this payload still says nothing about it.
	  · NO VICTIM AND NO POSITION. The feeder is standing on the body; a field naming it would be the
	    server telling a client something the client is already looking at, and it would be the first
	    place a corpse's identity could be logged and differenced.
	  · NO CAMOUFLAGE CHARGE. V07's reward rides `MonsterService.FeedCompleted`, a server-side
	    BindableEvent. When V07 needs to tell the client it may hide again, that is a decision for
	    V07's plan to argue in a diff — not a field to widen quietly here.

	IT IS NOT A ROLE ORACLE, and the reason is that no second client ever receives it. A remote that
	only the Aswang can receive tells the Aswang something it already knows: it just killed somebody.
	Compare `RoleAssigned`, which is allowlisted in `check-secrecy.mjs` on exactly this reasoning —
	fired to one player, carrying only that player's own business.
]]
export type FeedUpdatePayload = {
	Verdict: FeedVerdict,
	-- Config.Monster.FeedDuration on FEED_STARTED, 0 on the other two — `SearchUpdatePayload`'s rule,
	-- for its reason: a client that could read a timing difference off an ending could distinguish
	-- the paths this union deliberately collapses. It carries no information either way, since
	-- Config replicates and the client already knew the number.
	HoldSeconds: number,
}

--[[
	V07, §4.3. The verdict union the SERVER reports for a camouflage request.

	Mirrored from `pure/CamouflageRules.Verdict` plus the two the server owns rather than the rules
	module: `CAMO_EXITED` (a state change, never a refusal) and `CAMO_WITNESSED` (a survivor inside
	`Config.Monster.CamouflageWitnessRadius`, which is a distance the pure module never sees).

	THE VALUES ARE PREFIXED AND NOT SHARED WITH `FeedVerdict` OR THE PURE MODULE'S UNION. Two unions
	that happen to contain the same strings are one refactor away from being passed to each other's
	handler, and under `--!strict` a shared union would typecheck that mistake.
]]
export type CamouflageVerdict =
	"CAMO_OK"
	| "CAMO_EXITED"
	| "CAMO_NOT_REVEALED"
	| "CAMO_WRONG_PHASE"
	| "CAMO_NO_CHARGE"
	| "CAMO_ALREADY"
	| "CAMO_NOT_TRANSFORMED"
	| "CAMO_NO_SLOT"
	| "CAMO_WITNESSED"

--[[
	V07, §4.3. What the Aswang's own client is told about its disguise, and nothing else is.

	NO CHARGE COUNT AND NO REVEAL FLAG — see `Remotes.luau`'s `CamouflageUpdate` entry for the full
	argument. A verdict and an optional form, fired to one player about themselves.

	`Form` IS OPTIONAL BECAUSE A REFUSAL HAS NONE. It is populated on CAMO_OK and on the exit message,
	so the client can say "You are a pig" and later "You are yourself"; every other verdict carries
	nil.
]]
export type CamouflageUpdatePayload = {
	Verdict: CamouflageVerdict,
	Form: CamouflageForm?,
}

--[[
	V07, §4.3. A cloud, at a place, for a while — and the ABSENT FIELDS are the design.

	No UserId, no Character, no name, no role. Smoke is fired only by the Aswang, so a player field
	here would be a role broadcast with a position attached. See `Remotes.luau`'s `SmokeBurst` entry
	for why the position itself is safe: everyone who receives this payload is inside
	`Config.Monster.SmokeCueRadius` and can watch the cloud form.

	`Duration` AND `Radius` ARE SENT RATHER THAN READ FROM CONFIG BY THE CLIENT, even though Config
	replicates. The server is the authority on how long ITS burst lasts, and a client that computed
	the lifetime from Config would draw a stale cloud for four seconds after a Config change that the
	server had already applied. One fewer place where the two can disagree.
]]
export type SmokeBurstPayload = {
	Position: Vector3,
	Duration: number,
	Radius: number,
}

--[[
	V04, §4.4. THE FOUR NOISY ACTIONS.

	Only two of them have an emitter in V04, and that is a statement about the GAME rather than about
	this chunk: `grep -rni door src --include="*.luau"` finds no door, and `grep -rn "Sprint\|Crouch"`
	finds no movement verb. `NoiseModel` prices all four so the model is decided in one place; the
	chunk that adds a door adds the call, not the price.
]]
export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"

--[[
	V04, §4.4. `NoiseCue`'s payload. FireClient, to one player at a time, after the server has
	decided that player is within the noise's radius.

	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:

	  · NO ACTOR, in any form — not a UserId, not a name, not a character reference. §4.4's whole
	    point is that hearing a search tells you somebody is searching, not who. Adding one would
	    also be the first place a role could be inferred, since only the receiver knows it was not
	    them.
	  · NO RADIUS AND NO DISTANCE. The client reads `Config.Noise.Actions[Action].Radius` for its
	    rolloff — Config is replicated, so this is a lookup rather than a transfer — and a DISTANCE
	    would be a solved triangle: three cues and a compromised client has an exact position.
	  · NO COUNT AND NO HISTORY. The history is server-only (§4.4, build plan V04) and V13 is its
	    only reader.

	`Position` IS QUANTISED to Config.Noise.CueGridStuds by the sender and is therefore a CELL, not a
	person. §4.6 requires the Aswang's information to be an area rather than an address.
]]
export type NoiseCuePayload = {
	Action: NoiseAction,
	-- 0..1, scaling the volume. The receiver already knows this number from Config; it is sent so
	-- the client never has to guess which action produced the cue it is playing.
	Loudness: number,
	Position: Vector3,
	-- Whether the receiver is the one who made it. TRUE ONLY FOR THE ACTOR, which is why the actor's
	-- cue can be non-positional and can carry a line of copy: it is the "that was loud" feedback
	-- §4.6 asks for, and a sound you cannot perceive is not tension, it is a dice roll.
	Mine: boolean,
}

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
