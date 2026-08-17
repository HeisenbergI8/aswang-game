# Plan: C25 — Quick Chat Wheel

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M7 (BUILD-PLAN C25, Track D). Spec §4.5.
- **Description:** One button opens a radial menu of the eight fixed phrases from §4.5. The client sends
  a phrase **id** and nothing else; the server resolves the accusation target, derives the ping position
  from its own copy of the sender's character, filters the audience through `pure/GhostChat`, and
  broadcasts. Thumb-reachable and one-handed on a phone, because §5 puts ~60% of players there and
  §4.5's whole argument is that typing mid-chase is impossible.
- **Date:** 2026-08-17
- **What the client is told:** **nothing new about roles, and no new liveness signal beyond what
  `TextChatService` already carries.** The `QuickChatBroadcast` payload is
  `{ SenderUserId, PhraseId, TargetUserId?, PingPosition? }` — four fields, **no free strings**, no role,
  no player-state field. Delivery is per-recipient `FireClient` gated on
  `GhostChat.shouldDeliver(senderState, recipientState)`, exactly as C15 gates text chat: a ghost's
  quick chat reaches ghosts only, and the living reach everyone. `TargetUserId` names a player the
  sender could already see (range **and** line of sight are both required server-side), so the
  accusation asserts nothing a third party could not have inferred by watching the sender. See §4's
  "The liveness question" for the one residual leak and why it is accepted.

### The three decisions this plan turns on

Stated up front because they are the reason C25 is 🔒 and plan-backed rather than a UI chunk.

**1. Two remotes are sufficient. There is no third remote for the world ping.** The ping is a *derived
field on the same broadcast*, not a channel. `RequestQuickChat` carries **one argument, a phrase id**,
which puts it in the same class as `RequestTimingStop` and `RequestStartTrial` — remotes deliberately
built so there is no argument in which a client could name a position, a person or an outcome
(`Remotes.luau:88-91`, `Remotes.luau:150-155`). The ping position is **the sender's own server-side
`HumanoidRootPart.Position` at the instant the request lands**, and whether a phrase pings at all is a
property of the phrase in `pure/QuickChatPhrases`, not a client choice. A separate ping remote would
hand the client a "draw an arrow anywhere" primitive — including on top of a player, which accuses by
geometry while the phrase says something innocent — and would add a second budget entry and a second row
to the hand-copied list in `tests/anti-cheat-budgets.test.luau` that has drifted twice.

**2. No `TextService` call on the hot path, because no free text crosses the boundary.** The eight
phrases are author-written constants that live in `pure/QuickChatPhrases` and are **rendered on the
receiving client from the id**. The only user-generated string anywhere near this feature is the
accused player's display name — and it is never sent: the payload carries `TargetUserId`, and each
client renders the name itself from `Players:GetPlayerByUserId(...)`. This contradicts the C25 row's
"**`TextService`-filtered**" and that conflict is raised in §4 rather than resolved quietly. Phase 5
carries the conditional filter path and its fallback for the case where the policy answer says
otherwise.

**3. Ghosts may quick-chat, to ghosts only, and may never use the accusation phrase.** The audience rule
is `pure/GhostChat.shouldDeliver` **reused, not reimplemented** — that sixteen-cell predicate exists
precisely so a second feature does not get a second, subtly different wall
(`GhostChat.luau:28-33`). The accusation is refused for ghosts for a reason that is not squeamishness:
a ghost **has no server character**, so the only position available to resolve "nearest" from is the
client-reported one that `ReportGhostPosition`'s own header says the server cannot verify
(`Remotes.luau:118-136`). Resolving a target from a client-supplied position is the impersonation
exploit the C25 row forbids, one level of indirection removed.

## 2. Comprehensive Plan by Phases

### Phase 1: Config, types, and the eight phrases as pure data

Everything C25 needs that no service or controller has to exist for. Leaves the tree runnable: nothing
reads any of it yet.

#### Step 1.1: Add the `Config.QuickChat` block

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

Every tunable C25 introduces — the accusation range, the ping and message lifetimes, the wheel radius,
the touch-target floor and the drag dead zone — in one block, so the mobile layout is tuned during
playtesting rather than recompiled.

```diff
 		CameraDistance = 12,
 	},
 
+	--[[
+		§4.5, C25. The quick-chat wheel.
+
+		THE LAYOUT NUMBERS ARE HERE RATHER THAN IN THE CONTROLLER ON PURPOSE, and they are the ones
+		most likely to move: §5 puts ~60% of players on a phone, and "is this reachable with one
+		thumb" is a question answered by holding a phone, not by reading code. A wheel radius baked
+		into a controller is a wheel radius nobody re-tunes after the first playtest.
+	]]
+	QuickChat = {
+		--[[
+			How far the `"It's [nearest player]!"` phrase will look for a target, in studs.
+
+			BOUNDED ON BOTH SIDES BY `tests/config.test.luau`, and both bounds are security rather
+			than feel:
+
+			  · It MUST exceed `Monster.KillRange` (8). The moment §4.5 exists for is the one where
+			    something is close enough to kill you and you have no time to type. A range that
+			    cannot name the thing standing on top of you has no reason to exist.
+			  · It MUST stay far below `Tasks.MarkerVisibleStuds` (220). This is the half that
+			    matters for §6.2. The phrase resolves its target from the sender's own position, so a
+			    large range turns it into a map-wide proximity radar the sender can poll — and the
+			    player with the most to gain from "who is near me, through walls" is the Aswang
+			    hunting. Line of sight is the primary defence (see QuickChatService); this is the
+			    second.
+		]]
+		AccuseRangeStuds = 40,
+
+		-- How long a world ping marker lives on a receiving client, in seconds. Long enough to walk
+		-- toward, short enough that a plaza full of stale pings is not the HUD.
+		PingLifetimeSeconds = 8,
+		-- How long a received phrase stays on screen, and how many stack before the oldest is dropped.
+		MessageLifetimeSeconds = 6,
+		MaxVisibleMessages = 4,
+
+		-- The wheel's radius in pixels, measured from the press point to the middle of a sector.
+		WheelRadiusPx = 150,
+		--[[
+			THE ACCESSIBILITY FLOOR FOR A TOUCH TARGET, and the number the mobile argument rests on.
+			44px is the long-standing minimum for a reliable thumb press; a sector whose narrowest
+			dimension falls below it is a sector that gets mis-hit mid-chase, which for this feature
+			means accusing the wrong person. Pinned in `tests/config.test.luau` against
+			`WheelRadiusPx` so shrinking the wheel cannot silently shrink the targets below it.
+		]]
+		MinTouchTargetPx = 44,
+		-- A drag shorter than this from the press point is a CANCEL, not a selection. Without it,
+		-- opening the wheel and thinking better of it sends whichever sector the thumb was resting on.
+		DeadZonePx = 30,
+	},
+
 	Economy = {
 		XPPerRound = 50,
```

#### Step 1.2: Add the C25 types

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

`QuickChatPhraseId`, `QuickChatVerdict` and `QuickChatBroadcastPayload`. The payload's field list is the
enforceable statement of what crosses the boundary, and writing it as a closed type is what makes a
fifth field a review event.

```diff
 export type SpookVerdict =
 	"OK"
 	| "WRONG_PHASE"
 	| "NOT_GHOST"
 	| "NO_SPOOKS_LEFT"
 	| "NOTHING_IN_RANGE"
 
+--[[
+	§4.5, C25. The eight phrases, as IDS rather than as strings.
+
+	THE WHOLE SECURITY DESIGN OF THIS FEATURE IS THAT THIS IS A CLOSED UNION. `RequestQuickChat`
+	carries one of these and nothing else — no name, no position, no free text — which puts it in the
+	same class as `RequestTimingStop` and `RequestStartTrial`, remotes built so that there is no
+	argument in which a client could name a person, a place or an outcome.
+
+	The display strings live in `shared/pure/QuickChatPhrases` and are rendered by the RECEIVER from
+	the id. That is what removes user-generated text from the wire entirely — see
+	QuickChatService's header for why that also removes the TextService question.
+]]
+export type QuickChatPhraseId =
+	"SAW_TRANSFORM"
+	| "BODY_HERE"
+	| "FOLLOW_ME"
+	| "ACCUSE"
+	| "TASK_HERE"
+	| "RUN"
+	| "IM_ALONE"
+	| "TRUST_ME"
+
+--[[
+	Why the server refused a RequestQuickChat. Same shape and same rule as SpookVerdict above: a union
+	so the server can log WHY, and never echoed to the client.
+
+	LOGGED, NEVER ECHOED — not even to the sender. GhostService's spook handler states the reason and
+	it applies here unchanged: a verdict returned to a client is a STATE ORACLE. `NOT_ALLOWED_FOR_
+	STATE` echoed back would let a player fire the wheel and read their own aliveness off the
+	refusal, which is the death signal Amendment A3 removed `AlivePlayerCount` to close, rebuilt out
+	of an error code.
+
+	SO HOW DOES THE SENDER KNOW IT FAILED? They receive their own broadcast, like everyone else. A
+	message that appears succeeded; one that does not, did not. That is a complete signal, it needs
+	no remote, and it cannot be fired as a probe because the absence carries no detail.
+]]
+export type QuickChatVerdict =
+	"OK"
+	| "WRONG_PHASE"
+	| "UNKNOWN_PHRASE"
+	| "NOT_ALLOWED_FOR_STATE"
+	| "NO_SENDER_CHARACTER"
+	| "NO_TARGET_IN_SIGHT"
+
+--[[
+	C25. What `QuickChatBroadcast` carries, and the reason it is written as a closed type.
+
+	FOUR FIELDS, NO STRINGS. Every one is either a UserId the receiver can already resolve or a
+	position the SERVER derived from its own copy of the sender's character.
+
+	  · SenderUserId  — who said it. Attributable by design: an accusation nobody can attribute is
+	    not an accusation, and the cost of accusing is that you are on record.
+	  · PhraseId      — rendered locally from `pure/QuickChatPhrases`. Never a string on the wire.
+	  · TargetUserId  — present ONLY for ACCUSE, and only for a player the sender could see. Range
+	    AND line of sight are both checked server-side, so this names somebody the sender's own eyes
+	    already named. See the liveness note in the C25 plan's Follow Ups for the residual leak.
+	  · PingPosition  — the SENDER's own root position at the instant the request landed, present
+	    only for phrases whose meaning is locative. Never client-supplied: a client-named position is
+	    a "draw an arrow anywhere" primitive, including on top of a player.
+
+	NO PlayerState FIELD, AND THERE MUST NEVER BE ONE. Amendment A3 removed `AlivePlayerCount`
+	because a death signal is the missing input to a position-correlation attack, and a field saying
+	"the sender is ALIVE" would be that signal wearing a different hat. The audience filter already
+	encodes the same fact for the recipients entitled to it, and encodes it by WHO RECEIVES rather
+	than by what is written down — the same asymmetry that makes `GhostRoster` safe.
+]]
+export type QuickChatBroadcastPayload = {
+	SenderUserId: number,
+	PhraseId: QuickChatPhraseId,
+	TargetUserId: number?,
+	PingPosition: Vector3?,
+}
+
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

#### Step 1.3: Create `pure/QuickChatPhrases`

**File:** `src/shared/pure/QuickChatPhrases.luau`
**Verify:** `npm run lint`

The eight §4.5 phrases as plain data — id, display template, sector order, and three predicates
(`NeedsTarget`, `Pings`, `GhostMay`) — plus `sectorFor(angle)`, the pure angle→sector function the
mobile gesture depends on. No `script.Parent` requires.

```diff
+--!strict
+--[[
+	QuickChatPhrases — the eight §4.5 phrases, and the wheel's geometry. (C25)
+
+	THE PHRASE SET IS FIXED AND CLOSED, AND THAT IS THE FEATURE. §4.5 names eight phrases; C25's
+	BUILD-PLAN row and §C22's scope warning both say the same thing in different words — this is a
+	wheel with eight fixed phrases, not a chat system. A ninth phrase is a design decision, not an
+	implementation detail, and it lands here where it is one line in a diff.
+
+	WHY THE STRINGS LIVE ON THE CLIENT SIDE OF THE WIRE. `Text` is a TEMPLATE rendered by the
+	RECEIVER from a `PhraseId`. Nothing here is ever sent. That is what makes the entire TextService
+	question go away: the only user-generated string anywhere near this feature is a player's display
+	name, and it is never transmitted either — the payload carries a UserId and each client resolves
+	the name itself. No free text crosses the boundary, so there is no free text to filter.
+
+	It is callable by any client and that is fine, for exactly the reason `pure/GhostChat`'s header
+	gives: this is eight author-written strings and a division. Logic is not secret, and there is no
+	seed and no client-suppliable input here to make it one.
+
+	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural, so this type
+	and `Types.QuickChatPhraseId` are the same type and pass to each other without a cast.
+]]
+
+export type QuickChatPhraseId =
+	"SAW_TRANSFORM"
+	| "BODY_HERE"
+	| "FOLLOW_ME"
+	| "ACCUSE"
+	| "TASK_HERE"
+	| "RUN"
+	| "IM_ALONE"
+	| "TRUST_ME"
+
+export type Phrase = {
+	Id: QuickChatPhraseId,
+	-- The display template. Contains `{name}` if and only if `NeedsTarget`, and `tests` pins the iff.
+	Text: string,
+	-- Sector index, 0..7, clockwise from straight up. The wheel's layout and the gesture's angle
+	-- maths both read this, so the hit region and the selection cannot drift apart.
+	Order: number,
+	-- Resolves a target player SERVER-SIDE. Exactly one phrase does.
+	NeedsTarget: boolean,
+	-- Carries a world ping. A PROPERTY OF THE PHRASE, not a client choice — the three locative
+	-- phrases ping and the five social ones do not, which removes a boolean from the wire.
+	Pings: boolean,
+	--[[
+		May a GHOST send this? All but one, and the exception is not squeamishness.
+
+		A ghost has NO SERVER CHARACTER (see `ReportGhostPosition`'s header in Remotes.luau), so the
+		only position available to resolve "nearest" from is the client-reported one that the same
+		header says the server cannot independently verify. Resolving an accusation target from a
+		client-supplied position IS the impersonation exploit C25's row forbids, one level of
+		indirection removed — the client does not name the player, it names the point the server
+		will pick the player from, which is the same power with an extra step.
+
+		`Pings` phrases are allowed for ghosts because a ghost's ping goes only to other ghosts, and
+		the ping is the sender's own reported position — a ghost lying about where it is buys it
+		nothing it does not already have.
+	]]
+	GhostMay: boolean,
+}
+
+local QuickChatPhrases = {}
+
+local SECTORS = 8
+local TAU = math.pi * 2
+
+-- §4.5's list, in its own order. `Order` is the sector, and the two locative "here" phrases sit
+-- adjacent on the wheel because they are the pair a player reaches for under pressure.
+local PHRASES: { Phrase } = {
+	{
+		Id = "SAW_TRANSFORM" :: QuickChatPhraseId,
+		Text = "I saw it transform!",
+		Order = 0,
+		NeedsTarget = false,
+		Pings = false,
+		GhostMay = true,
+	},
+	{
+		Id = "BODY_HERE" :: QuickChatPhraseId,
+		Text = "Body here!",
+		Order = 1,
+		NeedsTarget = false,
+		Pings = true,
+		GhostMay = true,
+	},
+	{
+		Id = "TASK_HERE" :: QuickChatPhraseId,
+		Text = "Task here",
+		Order = 2,
+		NeedsTarget = false,
+		Pings = true,
+		GhostMay = true,
+	},
+	{
+		Id = "FOLLOW_ME" :: QuickChatPhraseId,
+		Text = "Follow me",
+		Order = 3,
+		NeedsTarget = false,
+		Pings = true,
+		GhostMay = true,
+	},
+	{
+		-- THE ONLY PHRASE WITH A SERVER-RESOLVED TARGET. `{name}` is filled by the RECEIVER from
+		-- `TargetUserId`, never by the sender.
+		Id = "ACCUSE" :: QuickChatPhraseId,
+		Text = "It's {name}!",
+		Order = 4,
+		NeedsTarget = true,
+		Pings = false,
+		GhostMay = false,
+	},
+	{
+		Id = "RUN" :: QuickChatPhraseId,
+		Text = "Run!",
+		Order = 5,
+		NeedsTarget = false,
+		Pings = false,
+		GhostMay = true,
+	},
+	{
+		Id = "IM_ALONE" :: QuickChatPhraseId,
+		Text = "I'm alone",
+		Order = 6,
+		NeedsTarget = false,
+		Pings = false,
+		GhostMay = true,
+	},
+	{
+		Id = "TRUST_ME" :: QuickChatPhraseId,
+		Text = "Trust me",
+		Order = 7,
+		NeedsTarget = false,
+		Pings = false,
+		GhostMay = true,
+	},
+}
+
+local BY_ID: { [string]: Phrase } = {}
+
+for _, phrase in PHRASES do
+	BY_ID[phrase.Id] = phrase
+end
+
+QuickChatPhrases.All = PHRASES
+QuickChatPhrases.Sectors = SECTORS
+
+--[[
+	Look up a phrase by id, returning nil for anything not in the set.
+
+	THE SERVER CALLS THIS BEFORE IT DOES ANYTHING ELSE WITH A REQUEST. A `nil` here is a refusal, not
+	a lookup that fails later — an unvalidated id from a compromised client would otherwise index a
+	table and produce a `nil` field access several lines further down, where the error is about
+	something else entirely.
+]]
+function QuickChatPhrases.get(id: string): Phrase?
+	return BY_ID[id]
+end
+
+--[[
+	Which sector an angle falls in, 0..SECTORS-1, clockwise from straight up.
+
+	THIS IS THE FUNCTION THE MOBILE ARGUMENT RESTS ON, which is why it is pure and tested rather than
+	inline in a touch callback. Eight equal sectors means each is 45 degrees wide, so a thumb drag
+	only has to be accurate to +/-22.5 degrees — that is the concrete reason a radial menu is usable
+	one-handed mid-chase and a vertical list is not.
+
+	TOTAL OVER ALL REALS, deliberately. `angleRadians` comes from `math.atan2` on a drag delta, which
+	returns (-pi, pi], and a function that answered nil at the wrap point would drop exactly the
+	sector sitting at straight up. The modulo makes every input land somewhere.
+]]
+function QuickChatPhrases.sectorFor(angleRadians: number): number
+	local normalised = angleRadians % TAU
+	-- Offset by half a sector so a sector is CENTRED on its angle rather than starting at it.
+	local shifted = (normalised + TAU / (SECTORS * 2)) % TAU
+
+	return math.floor(shifted / (TAU / SECTORS)) % SECTORS
+end
+
+return QuickChatPhrases
```

#### Step 1.4: Pin the phrase table with a Lune test

**File:** `tests/quick-chat-phrases.test.luau`
**Verify:** `lune run tests/quick-chat-phrases.test.luau`

Eight phrases, unique ids, sector orders 0–7 with no gaps, `{name}` present in the template **iff**
`NeedsTarget`, exactly one target-taking phrase, and `sectorFor` total and correct on every boundary.

```diff
+--!strict
+--[[
+	tests/quick-chat-phrases.test.luau
+
+	The phrase set is a CLOSED SET and the wheel's geometry is arithmetic. Both are exactly the kind
+	of thing that is obviously right when written and quietly wrong six chunks later, and both are
+	cheap to enumerate.
+
+	THE `{name}` IFF IS THE ONE WORTH READING TWICE. A template carrying `{name}` for a phrase the
+	server never resolves a target for renders the literal text "It's {name}!" to every player; a
+	phrase that needs a target but has no slot silently drops the accusation and reads as a phrase
+	that does nothing. Neither throws, and neither shows up in `analyze`.
+]]
+
+local Config = require("../src/shared/Config")
+local QuickChatPhrases = require("../src/shared/pure/QuickChatPhrases")
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+--------------------------------------------------------------------------------
+-- The set itself. §4.5 names eight; C25's row and §C22 both say eight is the number.
+--------------------------------------------------------------------------------
+
+check("§4.5 ships exactly eight phrases", #QuickChatPhrases.All == 8, `got {#QuickChatPhrases.All}`)
+check("the wheel has one sector per phrase", QuickChatPhrases.Sectors == #QuickChatPhrases.All)
+
+local seenIds: { [string]: boolean } = {}
+local seenOrders: { [number]: boolean } = {}
+local targetTaking = 0
+local ghostForbidden = 0
+
+for _, phrase in QuickChatPhrases.All do
+	check(`{phrase.Id} has a unique id`, seenIds[phrase.Id] ~= true)
+	seenIds[phrase.Id] = true
+
+	check(
+		`{phrase.Id} sits in a unique sector`,
+		seenOrders[phrase.Order] ~= true,
+		`Order={phrase.Order}`
+	)
+	seenOrders[phrase.Order] = true
+
+	check(
+		`{phrase.Id} sits inside the wheel`,
+		phrase.Order >= 0 and phrase.Order < QuickChatPhrases.Sectors,
+		`Order={phrase.Order}`
+	)
+
+	check(`{phrase.Id} has display text`, #phrase.Text > 0)
+
+	-- THE IFF. Both directions, because both fail silently and differently.
+	local hasSlot = string.find(phrase.Text, "{name}", 1, true) ~= nil
+
+	check(
+		`{phrase.Id} carries a name slot iff it resolves a target`,
+		hasSlot == phrase.NeedsTarget,
+		`slot={hasSlot} needsTarget={phrase.NeedsTarget}`
+	)
+
+	if phrase.NeedsTarget then
+		targetTaking += 1
+	end
+
+	if not phrase.GhostMay then
+		ghostForbidden += 1
+	end
+
+	-- A phrase a ghost may not send must be one the server could not resolve for a ghost anyway.
+	-- If these ever come apart, the refusal has stopped being a consequence and become a policy.
+	if not phrase.GhostMay then
+		check(`{phrase.Id} is ghost-forbidden because it needs a target`, phrase.NeedsTarget)
+	end
+end
+
+-- Sector coverage: 0..7 with no gaps, so no sector of the wheel is dead under the thumb.
+for sector = 0, QuickChatPhrases.Sectors - 1 do
+	check(`sector {sector} has a phrase`, seenOrders[sector] == true)
+end
+
+check("exactly one phrase resolves a target", targetTaking == 1, `got {targetTaking}`)
+check("exactly one phrase is closed to ghosts", ghostForbidden == 1, `got {ghostForbidden}`)
+
+check("an unknown id resolves to nil", QuickChatPhrases.get("NOT_A_PHRASE") == nil)
+check("a known id resolves", QuickChatPhrases.get("RUN") ~= nil)
+check("the empty string resolves to nil", QuickChatPhrases.get("") == nil)
+
+--------------------------------------------------------------------------------
+-- The geometry. Total over all reals, and centred rather than offset by half a sector.
+--------------------------------------------------------------------------------
+
+local TAU = math.pi * 2
+local step = TAU / QuickChatPhrases.Sectors
+
+for sector = 0, QuickChatPhrases.Sectors - 1 do
+	local centre = sector * step
+
+	check(`the centre of sector {sector} selects it`, QuickChatPhrases.sectorFor(centre) == sector)
+	-- Just inside each edge. NOT the edge itself: a boundary belongs to one side by definition and
+	-- pinning which one would be pinning a rounding mode, not a behaviour.
+	check(
+		`just clockwise of sector {sector}'s centre still selects it`,
+		QuickChatPhrases.sectorFor(centre + step * 0.45) == sector
+	)
+	check(
+		`just anticlockwise of sector {sector}'s centre still selects it`,
+		QuickChatPhrases.sectorFor(centre - step * 0.45) == sector
+	)
+end
+
+-- TOTALITY. `math.atan2` returns (-pi, pi], so negative and wrapped inputs are the normal case, not
+-- the edge case. A nil or an out-of-range sector here is a dead zone at straight up.
+for _, angle in { -TAU, -math.pi, -0.001, 0, math.pi, TAU, TAU * 3.5, -TAU * 2.25 } do
+	local sector = QuickChatPhrases.sectorFor(angle)
+
+	check(
+		`sectorFor({angle}) lands inside the wheel`,
+		sector >= 0 and sector < QuickChatPhrases.Sectors and sector == math.floor(sector),
+		`got {sector}`
+	)
+end
+
+-- A full turn is the identity, which is the property that makes the wrap safe rather than lucky.
+for sector = 0, QuickChatPhrases.Sectors - 1 do
+	local centre = sector * step
+
+	check(
+		`sector {sector} is stable across a full turn`,
+		QuickChatPhrases.sectorFor(centre) == QuickChatPhrases.sectorFor(centre + TAU)
+	)
+end
+
+--------------------------------------------------------------------------------
+-- The wheel has to be big enough to hold its own touch targets.
+--------------------------------------------------------------------------------
+
+--[[
+	§5, and the reason C25 is not a desktop feature with a phone port.
+
+	The narrowest dimension of a sector is its ARC at the inner edge of the ring the labels sit on.
+	Approximating that ring at half the wheel radius, the arc is `2 * pi * (r / 2) / SECTORS`. If
+	that falls below the 44px touch floor, the wheel is a control that mis-fires under a thumb — and
+	for this feature a mis-fire means accusing the wrong player.
+]]
+local innerArcPx = (TAU * (Config.QuickChat.WheelRadiusPx / 2)) / QuickChatPhrases.Sectors
+
+check(
+	"a sector is wider than the touch floor",
+	innerArcPx >= Config.QuickChat.MinTouchTargetPx,
+	`arc={innerArcPx}px floor={Config.QuickChat.MinTouchTargetPx}px`
+)
+
+-- The cancel zone must be smaller than the wheel, or every selection is a cancel.
+check(
+	"the dead zone sits well inside the wheel",
+	Config.QuickChat.DeadZonePx < Config.QuickChat.WheelRadiusPx / 2,
+	`dead={Config.QuickChat.DeadZonePx} radius={Config.QuickChat.WheelRadiusPx}`
+)
+
+if failures > 0 then
+	error(`{failures} quick-chat phrase failure(s)`, 0)
+end
+
+print(`  PASS  quick-chat-phrases: {#QuickChatPhrases.All} phrases, {checked} assertions`)
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`Vector3` in a shared type is fine; `Vector3` in a pure module is not.** `QuickChatBroadcastPayload`
  carries a `Vector3?` and lives in `Types.luau`, which is Roblox-side and never required by Lune. Both
  new pure modules must stay free of it — `pure/QuickChatTarget` therefore takes **pre-computed
  distances**, not positions. This is the same constraint that shaped `pure/SaltThrow`.
- **`Config.QuickChat.AccuseRangeStuds = 40` needs its two-sided relationship pinned in
  `tests/config.test.luau`, which this plan does not otherwise touch.** Add both bounds there in Step
  1.1 (`> Monster.KillRange`, `< Tasks.MarkerVisibleStuds`); `check:config` proves the number is in the
  right *file*, and only `config.test.luau` proves it is the right *number*.
- **The literal-type casts on every `Id` field are load-bearing.** `Id = "ACCUSE"` infers as plain
  `string` and then fails to satisfy `QuickChatPhraseId`. This is the exact failure CLAUDE.md names as
  six of the scaffold's seven original analyze errors.

### Phase 2: Who the accusation names, and who hears it

The two rules that make C25 a 🔒 chunk, both written as pure functions over plain tables so a Lune test
can enumerate them instead of a playtester guessing.

#### Step 2.1: Create `pure/QuickChatTarget`

**File:** `src/shared/pure/QuickChatTarget.luau`
**Verify:** `npm run analyze`

`nearest(candidates, maxRangeStuds) -> number?`. Takes **pre-computed distances and a line-of-sight
boolean**, never a `Vector3` — Lune has no `Vector3` and no raycast, so the Roblox-shaped half stays in
the service and the decision stays testable.

```diff
+--!strict
+--[[
+	QuickChatTarget — who does `"It's [nearest player]!"` actually name? (§4.5, C25)
+
+		({ Candidate }, maxRangeStuds) -> userId?
+
+	THE CLIENT SUPPLIES NO PART OF THIS. C25's row says a client-supplied name is a free
+	impersonation exploit, and it is: `FireServer("RequestQuickChat", "ACCUSE", "Bob")` lets any
+	player put any name in every other player's HUD, attributed to themselves, from anywhere on the
+	map. The remote therefore carries a phrase id and nothing else, and the target is resolved here
+	from positions the SERVER owns.
+
+	WHY LINE OF SIGHT IS REQUIRED AND NOT JUST RANGE — THE PROXIMITY ORACLE
+	----------------------------------------------------------------------
+	Range alone turns this phrase into a radar. Fire it repeatedly and the server answers "who is
+	within 40 studs of me", through walls, roughly every two seconds at the C25 budget (Capacity 4,
+	RefillPerSecond 0.5). The player with the most to gain from that is the Aswang mid-hunt, and it
+	would be a hunting tool handed over by the communication feature.
+
+	Requiring line of sight collapses the oracle to nothing: a hit names somebody the sender can
+	already see, and — this is the half that is easy to miss — so does a MISS. `NO_TARGET_IN_SIGHT`
+	tells the sender "nobody is visible near you", which their eyes said first. Both outcomes are
+	information the sender already had, which is the property that makes the phrase safe to spam.
+
+	The service does the raycast, because a raycast is a DataModel call. This module takes the
+	ANSWER, so the rule stays enumerable from a terminal.
+
+	NO `Vector3`, DELIBERATELY. Lune has no `Vector3` and no raycast, so a module that took positions
+	would not be runnable from a terminal and the whole point of putting it in `pure/` is lost. The
+	caller measures; this decides.
+
+	NO `script.Parent` REQUIRES.
+]]
+
+export type Candidate = {
+	UserId: number,
+	-- Studs from the SENDER, measured server-side by the caller.
+	DistanceStuds: number,
+	-- `GhostChat.isLivingSide` of this candidate, computed by the caller. A candidate the sender
+	-- cannot see because they are dead is not a candidate.
+	IsAliveSide: boolean,
+	-- The result of the caller's raycast. See the header: this is the whole anti-oracle defence.
+	HasLineOfSight: boolean,
+}
+
+local QuickChatTarget = {}
+
+--[[
+	The nearest eligible candidate, or nil.
+
+	AN ALLOWLIST OF CONDITIONS, in the discipline `pure/GhostChat` and `pure/PlayerBody` both use: a
+	candidate must pass EVERY test to be eligible, so a field added to `Candidate` later defaults to
+	"does not qualify anybody" rather than to "silently admits a new class".
+
+	THE CALLER MUST NOT PUT THE SENDER IN THE LIST, and this module does not know who the sender is
+	so it cannot check. That is a real seam and it is why `tests/quick-chat-target.test.luau`
+	includes a case asserting the caller's own exclusion, and why the service builds the list by
+	iterating `Players:GetPlayers()` with an explicit `player ~= sender` rather than by filtering
+	afterwards.
+
+	TIES BREAK TO THE LOWEST USERID. Two players at identical distance is vanishingly rare and
+	completely possible, and an unstable answer there means the same situation names different people
+	on different frames — which reads to players as the feature being broken, and to an auditor as
+	nondeterminism on the 🔒 surface. Lowest UserId is arbitrary but it is STABLE, which is the
+	property that matters.
+]]
+function QuickChatTarget.nearest(candidates: { Candidate }, maxRangeStuds: number): number?
+	local bestUserId: number? = nil
+	local bestDistance = math.huge
+
+	for _, candidate in candidates do
+		if not candidate.IsAliveSide then
+			continue
+		end
+
+		if not candidate.HasLineOfSight then
+			continue
+		end
+
+		if candidate.DistanceStuds > maxRangeStuds then
+			continue
+		end
+
+		-- Guard against a NaN distance rather than trusting the caller's arithmetic: `NaN > x` is
+		-- false, so a NaN would slip past the range test above and then lose every comparison here,
+		-- which is the safe direction but only by accident. Make it deliberate.
+		if candidate.DistanceStuds ~= candidate.DistanceStuds then
+			continue
+		end
+
+		if
+			candidate.DistanceStuds < bestDistance
+			or (candidate.DistanceStuds == bestDistance and bestUserId ~= nil and candidate.UserId < bestUserId)
+		then
+			bestDistance = candidate.DistanceStuds
+			bestUserId = candidate.UserId
+		end
+	end
+
+	return bestUserId
+end
+
+return QuickChatTarget
```

#### Step 2.2: Pin the target rule with a Lune test

**File:** `tests/quick-chat-target.test.luau`
**Verify:** `lune run tests/quick-chat-target.test.luau`

Empty list, everything out of range, nearest-but-no-line-of-sight, a tie, a dead-side candidate, and the
sender's own id in the list. Each returns the safe answer.

```diff
+--!strict
+--[[
+	tests/quick-chat-target.test.luau
+
+	The one place in C25 where the server names a player out loud. Every case below is a way that
+	could go wrong that produces NO ERROR — a wrong name, or a name where there should have been
+	silence — so none of them would be caught by `analyze`, by any check script, or by a playtester
+	who did not happen to stand in the right place.
+]]
+
+local Config = require("../src/shared/Config")
+local QuickChatTarget = require("../src/shared/pure/QuickChatTarget")
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local RANGE = Config.QuickChat.AccuseRangeStuds
+
+local function candidate(userId: number, distance: number, alive: boolean?, los: boolean?)
+	return {
+		UserId = userId,
+		DistanceStuds = distance,
+		IsAliveSide = if alive == nil then true else alive,
+		HasLineOfSight = if los == nil then true else los,
+	}
+end
+
+--------------------------------------------------------------------------------
+-- Nothing to name
+--------------------------------------------------------------------------------
+
+check("an empty room names nobody", QuickChatTarget.nearest({}, RANGE) == nil)
+
+check(
+	"everybody out of range names nobody",
+	QuickChatTarget.nearest({ candidate(1, RANGE + 1), candidate(2, RANGE * 10) }, RANGE) == nil
+)
+
+-- THE ANTI-ORACLE CASE. Somebody is standing right there, and the wall means the sender does not get
+-- to know it. This is the assertion that makes the phrase un-spammable for information.
+check(
+	"the nearest player behind a wall names nobody",
+	QuickChatTarget.nearest({ candidate(1, 2, true, false) }, RANGE) == nil
+)
+
+check(
+	"a visible player further away wins over an invisible one nearby",
+	QuickChatTarget.nearest({ candidate(1, 2, true, false), candidate(2, 20, true, true) }, RANGE) == 2
+)
+
+-- A ghost or a spectator is not a candidate. They are not rendered to the living, so naming one
+-- would tell the whole server that somebody nobody can see is standing somewhere.
+check(
+	"a dead-side player is never named",
+	QuickChatTarget.nearest({ candidate(1, 1, false, true) }, RANGE) == nil
+)
+
+check(
+	"a living player is named over a nearer dead one",
+	QuickChatTarget.nearest({ candidate(1, 1, false, true), candidate(2, 30, true, true) }, RANGE) == 2
+)
+
+--------------------------------------------------------------------------------
+-- Naming the right one
+--------------------------------------------------------------------------------
+
+check("the only candidate is named", QuickChatTarget.nearest({ candidate(7, 5) }, RANGE) == 7)
+
+check(
+	"the nearest of several is named",
+	QuickChatTarget.nearest({ candidate(1, 30), candidate(2, 4), candidate(3, 12) }, RANGE) == 2
+)
+
+-- Exactly at the range boundary is INSIDE. An exclusive bound would make the outermost stud a place
+-- where the feature silently stops working, which reads as a bug and is impossible to report.
+check("the range boundary is inclusive", QuickChatTarget.nearest({ candidate(9, RANGE) }, RANGE) == 9)
+
+check(
+	"one stud past the boundary is out",
+	QuickChatTarget.nearest({ candidate(9, RANGE + 1) }, RANGE) == nil
+)
+
+--------------------------------------------------------------------------------
+-- Stability. See the module header: an unstable answer reads as a broken feature.
+--------------------------------------------------------------------------------
+
+check(
+	"a tie breaks to the lowest UserId",
+	QuickChatTarget.nearest({ candidate(88, 10), candidate(12, 10), candidate(45, 10) }, RANGE) == 12
+)
+
+check(
+	"a tie breaks the same way whatever the list order",
+	QuickChatTarget.nearest({ candidate(12, 10), candidate(88, 10) }, RANGE)
+		== QuickChatTarget.nearest({ candidate(88, 10), candidate(12, 10) }, RANGE)
+)
+
+-- A NaN distance is a caller bug, not an attack, but it must not name anybody by default.
+check("a NaN distance names nobody", QuickChatTarget.nearest({ candidate(1, 0 / 0) }, RANGE) == nil)
+
+--[[
+	THE SEAM THIS MODULE CANNOT CLOSE ITSELF, asserted here so it is written down somewhere.
+
+	`nearest` does not know who the sender is, so it cannot exclude them. If the service builds its
+	candidate list without an explicit `player ~= sender`, the sender is at distance 0 with perfect
+	line of sight to themselves and wins EVERY accusation — the phrase becomes "It's me!", for
+	everyone, always. That is a total feature failure that throws no error.
+
+	The assertion below is a statement of the contract rather than a test of this module: at distance
+	0 the module WILL name you, which is exactly why the caller must not offer you.
+]]
+check(
+	"the module names a zero-distance candidate, so the caller must exclude the sender",
+	QuickChatTarget.nearest({ candidate(101, 0), candidate(202, 5) }, RANGE) == 101
+)
+
+if failures > 0 then
+	error(`{failures} quick-chat target failure(s)`, 0)
+end
+
+print(`  PASS  quick-chat-target: {checked} assertions`)
```

#### Step 2.3: Extend the ghost-chat suite to cover the quick-chat reuse

**File:** `tests/ghost-chat.test.luau`
**Verify:** `lune run tests/ghost-chat.test.luau`

Assert the four quick-chat audience cases against the **same** `shouldDeliver`, so a future edit to that
predicate reports which of the two features it broke.

```diff
+--------------------------------------------------------------------------------
+-- C25. The quick-chat wheel reuses this predicate rather than growing its own.
+--------------------------------------------------------------------------------
+
+--[[
+	WHY THESE ASSERTIONS ARE HERE AND NOT IN A quick-chat FILE.
+
+	They are not testing quick chat. They are pinning that quick chat's audience rule IS this
+	sixteen-cell grid and not a second, subtly different wall — which is the whole reason
+	`pure/GhostChat` was written as a predicate over a bounded domain instead of an `if` in
+	GhostService's callback. A future edit to `shouldDeliver` now reports BOTH features it changed,
+	in one file, rather than breaking the one whose test happened to live next to it.
+
+	§4.5 GAVE US NO GUIDANCE HERE, so the reasoning is C15's, applied unchanged: a ghost watched
+	their own death and usually knows who did it. "It's Bob!" from a ghost is that knowledge in one
+	thumb press — strictly WORSE than the typed version C15 closed, because the wheel makes it
+	instant and the phrase is server-attributed rather than a human claim.
+]]
+
+check(
+	"a living player's quick chat reaches the living",
+	GhostChat.shouldDeliver("ALIVE", "ALIVE") == true
+)
+
+-- Information flows DOWN to the dead, always. §4.7's retention argument is the reason ghosts exist
+-- at all, and a ghost cut off from the round's chatter is a ghost that leaves.
+check(
+	"a living player's quick chat reaches ghosts",
+	GhostChat.shouldDeliver("ALIVE", "GHOST") == true
+)
+
+-- THE ONE THAT MATTERS. Never, in any state pairing, upward.
+check(
+	"a ghost's quick chat never reaches the living",
+	GhostChat.shouldDeliver("GHOST", "ALIVE") == false
+)
+
+check(
+	"a ghost's quick chat never reaches a lobby player",
+	GhostChat.shouldDeliver("GHOST", "LOBBY") == false
+)
+
+-- Ghosts still get a wheel among themselves, which is what makes the refusal above a channel rather
+-- than a mute. A muted ghost is a bored ghost.
+check("a ghost's quick chat reaches ghosts", GhostChat.shouldDeliver("GHOST", "GHOST") == true)
+
+-- And the dead do not form one bloc: a spectator is a mid-round arrival, so the ghost channel stays
+-- closed to them for the alt-account reason `shouldDeliver`'s own header gives.
+check(
+	"a ghost's quick chat never reaches a spectator",
+	GhostChat.shouldDeliver("GHOST", "SPECTATOR") == false
+)
```

#### Step 2.4: Confirm the up-remote hand copy already carries `RequestQuickChat`

**File:** `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

C25 adds **no** up-remote, so this step is a check rather than an edit — the drift that has bitten twice
is discharged by running the suite and annotating the entry, not by assuming.

```diff
 -- Hand copy of Remotes.EVENTS_UP, last synced at C22. See the header for why.
+-- C25 checked this list and added nothing: the quick-chat wheel ships on the `RequestQuickChat`
+-- entry that was already here, because the world ping is a DERIVED FIELD on the broadcast rather
+-- than a second remote. See the C25 plan's §1 for why a client-named ping position was refused.
 local UP_REMOTES = {
 	"RequestTaskProgress",
 	"RequestTimingStop",
 	"RequestTransform",
 	"RequestKill",
 	"RequestThrowSalt",
-	"RequestQuickChat",
+	-- C25. ONE ARGUMENT — a `Types.QuickChatPhraseId` — and the budget below is priced for a
+	-- deliberate thumb press rather than a heartbeat. Note that the limiter is the SECOND line of
+	-- defence for the accusation phrase and not the first: the first is that a target must be in
+	-- line of sight, which is what stops a spammed phrase from being a proximity radar.
+	"RequestQuickChat",
 	--[[
 		C15. The one up-remote that is not a Request: a ghost REPORTS where its client-side body is,
```

And one relationship worth pinning while this file is open — a wheel a player cannot use twice in a
conversation is a wheel they stop using:

```diff
+--[[
+	§4.5, C25. A quick chat is a DELIBERATE thumb press, so the budget is priced like
+	`RequestGhostSpook` rather than like a heartbeat — but it must still cover a real exchange. A
+	player answering "Body here!" with "Follow me" and then "Run!" is three presses in a few seconds,
+	and a limiter that refuses the third has throttled a conversation rather than an exploiter.
+
+	The burst is what carries that; the sustained rate is deliberately slow, because a SUSTAINED
+	stream of quick chats is not communication and the accusation phrase in particular should be
+	expensive to repeat.
+]]
+check(
+	"the wheel affords a short exchange in one burst",
+	Config.AntiCheat.Budgets.RequestQuickChat.Capacity >= 3,
+	`Capacity={Config.AntiCheat.Budgets.RequestQuickChat.Capacity}`
+)
+
+-- And the refill must not out-pace the on-screen message life, or a player can hold the HUD full.
+check(
+	"a refilled token arrives no faster than a message expires",
+	1 / Config.AntiCheat.Budgets.RequestQuickChat.RefillPerSecond
+		<= Config.QuickChat.MessageLifetimeSeconds,
+	`{1 / Config.AntiCheat.Budgets.RequestQuickChat.RefillPerSecond}s per token`
+)
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **The sender-exclusion seam is real and this module cannot close it.** `QuickChatTarget.nearest` does
  not know the sender, so a service that builds its candidate list without an explicit
  `player ~= sender` makes every accusation name the accuser — at distance 0 with perfect line of sight
  to themselves. It throws nothing and `analyze` cannot see it. Step 3.3 must build the list with the
  exclusion in the loop, not filter afterwards, and the test asserts the contract from this side.
- **`tests/ghost-chat.test.luau` gains assertions but `pure/GhostChat` gains nothing.** If implementing
  Phase 2 produces an urge to add a `shouldDeliverQuickChat`, stop — that is the second wall the
  sixteen-cell grid exists to prevent, and the C04 revert bug is what a second copy of a rule looks like
  after it drifts.
- **The liveness question is answered by precedent, not by this plan.** "Who has sent recently" is a
  partial liveness signal, and it is **exactly the signal `TextChatService` has carried since C15** under
  the same predicate. C25 does not widen it. What C25 *does* add is the accusation naming a third party
  as alive — see Follow Ups, where it is raised as a GATE 1 question rather than resolved here.

### Phase 3: `QuickChatService` — the handler, the resolution, the broadcast

The server half. Follows the `RoundService` service shape; the closest existing model for the handler is
`GhostService`'s `RequestGhostSpook` block (`GhostService.luau:698-712`).

#### Step 3.1: Create the service skeleton and subscribe to the phase

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run analyze`

`Init`/`Start`, module-scope state, and `RoundService.PhaseChanged.Event:Connect` — the same
subscription `ItemService` and `TaskService` use (`ItemService.luau:694`). Nothing calls `setPhase`.

```diff
+--!strict
+--[[
+	QuickChatService — the eight-phrase wheel, server side. (§4.5, C25)
+
+	§4.5 is blunt: "This is a small system with an outsized effect on how fun the game is. Do not cut
+	it." Voice needs 13+ verification most of this audience lacks and typing mid-chase on a phone is
+	impossible, so this IS the communication system. Accusation gameplay with no way to accuse is not
+	gameplay.
+
+	THREE THINGS THIS SERVICE REFUSES TO ACCEPT FROM A CLIENT
+	--------------------------------------------------------
+	The whole 🔒 surface of C25 is here, and it is best read as a list of what `RequestQuickChat`
+	does NOT carry:
+
+	  1. A NAME. C25's row: a client-supplied name is a free impersonation exploit, and it is a total
+	     one — `FireServer("ACCUSE", "Bob")` puts any name in every player's HUD, attributed to the
+	     sender, from anywhere on the map. The target is resolved here, from `pure/QuickChatTarget`,
+	     over positions this server owns.
+	  2. A POSITION. The world ping is the SENDER's own root position at the instant the request
+	     landed. A client-named position is a "draw an arrow anywhere" primitive — including on top of
+	     another player, which accuses by geometry while the phrase says something harmless.
+	  3. A STRING. The phrase is an id; the text is rendered by the receiver from
+	     `shared/pure/QuickChatPhrases`. See the TextService note further down — this is what makes
+	     that entire question disappear rather than get answered.
+
+	So the remote's payload is one `Types.QuickChatPhraseId` and nothing else, which puts it in the
+	same class as `RequestTimingStop` (C09) and `RequestStartTrial` (C21): remotes deliberately built
+	so there is no argument in which a client could name a moment, a place, a person or an outcome.
+
+	WHY THERE IS NO `TextService` CALL IN THIS FILE
+	----------------------------------------------
+	The C25 row says "`TextService`-filtered", and this service does not filter. That is a deliberate
+	deviation raised in the plan's Follow Ups rather than a gap, and the argument is that there is
+	nothing left to filter:
+
+	  · The eight phrases are AUTHOR-WRITTEN constants. They are not user-generated content, they are
+	    game copy, and they never travel — the receiver renders them from an id it already has.
+	  · The one user-generated string in the neighbourhood is the accused player's DISPLAY NAME, and
+	    it is never transmitted either. The payload carries `TargetUserId`; each client resolves the
+	    name locally through `Players:GetPlayerByUserId`.
+
+	A filter call would therefore be a yielding web request, inside an `OnServerEvent` handler, on
+	the 🔒 surface, to sanitise a string that was already ours. `Config.QuickChat.FilterDisplayNames`
+	exists for the case where the policy answer overrules this; see Step 5.3 for its shape and its
+	fail-closed fallback.
+
+	PHASE OWNERSHIP. This service SUBSCRIBES to `RoundService.PhaseChanged` and never calls
+	`setPhase` — spec §6.4, and the same shape ItemService and TaskService use.
+]]
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local GhostChat = require(Shared.pure.GhostChat)
+local QuickChatPhrases = require(Shared.pure.QuickChatPhrases)
+local QuickChatTarget = require(Shared.pure.QuickChatTarget)
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
+
+local AntiCheatService = require(script.Parent.AntiCheatService)
+local RoundService = require(script.Parent.RoundService)
+
+local QuickChatService = {}
+
+local broadcastRemote = Remotes.Get("QuickChatBroadcast")
+
+--[[
+	SERVER-ONLY. Nothing here is replicated, attributed or tagged.
+
+	This is a verdict log for C41, not state any client reads. It exists because a refusal that
+	produces no record is a refusal nobody can tune the budget against — and `NO_TARGET_IN_SIGHT` in
+	particular is the one whose frequency tells you whether `AccuseRangeStuds` is right.
+]]
+local verdictCounts: { [string]: number } = {}
+
+local function recordVerdict(verdict: Types.QuickChatVerdict)
+	verdictCounts[verdict] = (verdictCounts[verdict] or 0) + 1
+end
+
+local function onPhaseChanged(phase: Types.RoundPhase)
+	--[[
+		Nothing to tear down on the server: a quick chat is a fire-and-forget broadcast with no
+		lifetime here, and the message and ping lifetimes are the RECEIVER's business.
+
+		The counters reset per round so C41 reads a round's worth of verdicts rather than a server's.
+	]]
+	if phase == Enums.RoundPhase.Starting then
+		table.clear(verdictCounts)
+	end
+end
+
+function QuickChatService.Init()
+	table.clear(verdictCounts)
+end
+
+function QuickChatService.Start()
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+	-- The handler is attached in Step 3.2.
+end
+
+return QuickChatService
```

#### Step 3.2: The `RequestQuickChat` handler — limiter first, then the four gates

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run check:ratelimit`

`AntiCheatService.Consume` before any work, then phase, sender state, phrase-id validity, and
`GhostMay`. The id is validated against `pure/QuickChatPhrases` rather than trusted — an unknown id is a
refusal, not a `nil` index later.

```diff
 function QuickChatService.Start()
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
-	-- The handler is attached in Step 3.2.
+
+	--[[
+		`AntiCheatService.Consume` IS THE FIRST STATEMENT IN THE HANDLER, and it must stay inside this
+		function body rather than being hoisted into a helper. `check-ratelimit.mjs` matches the
+		Consume call within a character window of the `.OnServerEvent:Connect(`, so a handler limited
+		somewhere else reads as unguarded — the same note GhostService carries above its spook
+		handler.
+	]]
+	Remotes.Get("RequestQuickChat").OnServerEvent:Connect(function(player: Player, phraseId: unknown)
+		if not AntiCheatService.Consume(player, "RequestQuickChat") then
+			return
+		end
+
+		--[[
+			TYPE THE ARGUMENT AS `unknown` AND NARROW IT HERE.
+
+			A remote argument annotated `Types.QuickChatPhraseId` is a LIE the typechecker will
+			believe: the wire carries whatever the client sent, and a compromised client sends a
+			table, a function reference, or nothing at all. Every one of those would sail past a
+			declared parameter type and fail several lines later somewhere less obvious.
+		]]
+		if typeof(phraseId) ~= "string" then
+			recordVerdict("UNKNOWN_PHRASE")
+			return
+		end
+
+		local phrase = QuickChatPhrases.get(phraseId)
+
+		if phrase == nil then
+			recordVerdict("UNKNOWN_PHRASE")
+			return
+		end
+
+		--[[
+			PHASE GATE. Quick chat is a round mechanic, so it runs at ACTIVE and nowhere else.
+
+			ENDING is excluded on purpose and it is the interesting exclusion: the reveal has already
+			happened by then, so an accusation fired into the end screen is either noise or — worse —
+			a player who now KNOWS the answer broadcasting it into a phase where a late-joining
+			spectator could read it. There is no version of this that helps.
+		]]
+		if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+			recordVerdict("WRONG_PHASE")
+			return
+		end
+
+		local senderState = RoundService.GetPlayerState(player)
+
+		--[[
+			GHOSTS MAY SPEAK, BUT NOT ACCUSE, and the refusal is a CONSEQUENCE rather than a policy.
+
+			A ghost has no server character (see `ReportGhostPosition`'s header in Remotes.luau), so
+			there is no server-owned position to resolve "nearest" from. The only position available
+			is the client-reported one that the same header states plainly the server cannot verify
+			— and resolving an accusation target from a client-supplied position is precisely the
+			impersonation exploit C25's row forbids, with one extra step in front of it. The client
+			would not be naming the player; it would be naming the point the server picks the player
+			from, which is the same power.
+
+			`GhostMay` lives on the phrase in `pure/QuickChatPhrases` rather than as an `if` here, so
+			the rule is enumerable and `tests/quick-chat-phrases.test.luau` pins that the one
+			ghost-forbidden phrase is exactly the one that needs a target.
+		]]
+		if senderState == Enums.PlayerState.Ghost and not phrase.GhostMay then
+			recordVerdict("NOT_ALLOWED_FOR_STATE")
+			return
+		end
+
+		--[[
+			A LOBBY PLAYER IS NOT IN THE ROUND. The phase gate above already means a round is running,
+			so LOBBY here is somebody between states — a player who joined this second, or one whose
+			body rule has not settled. They have nothing to say about a round they are not in, and
+			letting them say it would let a spectator-adjacent account inject into the living channel.
+		]]
+		if senderState ~= Enums.PlayerState.Alive and senderState ~= Enums.PlayerState.Ghost then
+			recordVerdict("NOT_ALLOWED_FOR_STATE")
+			return
+		end
+
+		-- Resolution and broadcast land in Steps 3.3 and 3.4.
+	end)
 end
```

#### Step 3.3: Resolve the target and derive the ping, server-side only

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run verify:fast`

Build the candidate list from the server's own characters, raycast for line of sight, hand it to
`pure/QuickChatTarget`. The ping is the sender's own root position. No client-supplied position or name
touches either.

```diff
+--[[
+	The sender's own root part, from the SERVER's copy of their character.
+
+	Returns nil for a ghost (no server character at all), for a player mid-respawn, and for anyone
+	whose character the body rule has containment-parked. Every one of those is a legitimate reason
+	to refuse rather than an error.
+]]
+local function rootPartOf(player: Player): BasePart?
+	local character = player.Character
+
+	if character == nil then
+		return nil
+	end
+
+	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
+end
+
+--[[
+	Can the sender actually SEE this player? A raycast from root to root.
+
+	THIS IS THE ANTI-ORACLE DEFENCE and it is worth stating why it is here rather than in the pure
+	module: a raycast is a DataModel call, so it cannot be Lune-tested, and `pure/QuickChatTarget`
+	therefore takes the ANSWER as a boolean. The rule stays enumerable; the physics stays here.
+
+	Range alone would make the accusation phrase a through-wall proximity radar the sender can poll
+	roughly every two seconds at the C25 budget. Requiring line of sight collapses that to nothing —
+	a hit names somebody the sender can already see, and a miss says "nobody visible", which their
+	eyes said first. Both outcomes are information the sender already had.
+
+	⚠ THE FILTER LIST IS NOT CONFIRMED SUFFICIENT. `RaycastParams.FilterDescendantsInstances` with
+	both characters excluded is the standard shape, but this map is greyboxed (C17) and whether
+	decorative parts, the husk models RoundService parks, or CollectionService-tagged task props sit
+	in the default collision group is not established anywhere in this repo. A raycast that clips a
+	husk reports "no line of sight" to a player standing in the open. Playtester — see Follow Ups.
+]]
+local function hasLineOfSight(fromPart: BasePart, toPart: BasePart, ignore: { Instance }): boolean
+	local params = RaycastParams.new()
+
+	params.FilterType = Enum.RaycastFilterType.Exclude
+	params.FilterDescendantsInstances = ignore
+	params.IgnoreWater = true
+
+	local delta = toPart.Position - fromPart.Position
+	local result = workspace:Raycast(fromPart.Position, delta, params)
+
+	-- Nothing between the two roots. A hit on ANYTHING is a refusal: this is the conservative
+	-- direction, and the cost of being wrong is a phrase that says "nobody in sight" once.
+	return result == nil
+end
+
+--[[
+	Who does this accusation name? Returns a UserId, or nil for "nobody, and say so to the sender".
+
+	THE SENDER IS EXCLUDED IN THE LOOP, NOT FILTERED AFTERWARDS. `QuickChatTarget.nearest` does not
+	know who the sender is and cannot check — and a sender left in the list is at distance 0 with
+	perfect line of sight to themselves, so they win EVERY accusation. "It's me!", for everyone,
+	always. It throws nothing, `analyze` cannot see it, and
+	`tests/quick-chat-target.test.luau` asserts the contract from the other side.
+]]
+local function resolveTarget(sender: Player, senderRoot: BasePart): number?
+	local candidates: { QuickChatTarget.Candidate } = {}
+	local ignore: { Instance } = { sender.Character :: Instance }
+
+	for _, other in Players:GetPlayers() do
+		if other == sender then
+			continue
+		end
+
+		local otherRoot = rootPartOf(other)
+
+		if otherRoot == nil then
+			continue
+		end
+
+		local otherState = RoundService.GetPlayerState(other)
+
+		table.insert(candidates, {
+			UserId = other.UserId,
+			DistanceStuds = (otherRoot.Position - senderRoot.Position).Magnitude,
+			--[[
+				A GHOST OR SPECTATOR IS NOT A CANDIDATE, and the reason is a leak rather than a
+				nicety: they are not rendered to the living, so naming one would tell every recipient
+				that somebody nobody can see is standing somewhere — a death signal with a position
+				attached, which is the exact shape Amendment A3 removed `AlivePlayerCount` to close.
+			]]
+			IsAliveSide = GhostChat.isLivingSide(otherState :: GhostChat.PlayerState),
+			HasLineOfSight = hasLineOfSight(
+				senderRoot,
+				otherRoot,
+				{ sender.Character :: Instance, other.Character :: Instance }
+			),
+		})
+	end
+
+	return QuickChatTarget.nearest(candidates, Config.QuickChat.AccuseRangeStuds)
+end
```

And the handler's tail, continuing from Step 3.2:

```diff
-		-- Resolution and broadcast land in Steps 3.3 and 3.4.
+		local senderRoot = rootPartOf(player)
+		local targetUserId: number? = nil
+		local pingPosition: Vector3? = nil
+
+		if phrase.NeedsTarget then
+			if senderRoot == nil then
+				recordVerdict("NO_SENDER_CHARACTER")
+				return
+			end
+
+			targetUserId = resolveTarget(player, senderRoot)
+
+			--[[
+				NOBODY IN SIGHT IS A SILENT REFUSAL, and every part of that is deliberate.
+
+				NOT BROADCAST: a "nobody there" variant would tell the whole server the sender is
+				alone, which is a free position hint about a player who did not choose to give one.
+				Rendering the phrase with an empty name gives "It's !" and reads as broken.
+
+				NOT ECHOED TO THE SENDER EITHER, which is the less obvious half. GhostService's spook
+				handler refuses to return its verdict for exactly this reason — a refusal a client
+				can read is a state oracle. The sender learns it failed by not seeing their own
+				message appear, and an absence carries no detail to probe with.
+
+				And what the sender learns from the silence is nothing new: line of sight was
+				required, so "nobody visible near you" is what their eyes already said. That is the
+				property that makes this phrase safe to spam.
+			]]
+			if targetUserId == nil then
+				recordVerdict("NO_TARGET_IN_SIGHT")
+				return
+			end
+		end
+
+		--[[
+			THE PING IS THE SENDER'S OWN POSITION, and it is derived here rather than sent.
+
+			A ghost has no server character, so a pinging phrase from a ghost simply carries no ping
+			— it still delivers to the other ghosts, just without the marker. That degradation is
+			preferable to reaching for `GhostService.GetGhostPosition`, which would put a
+			client-reported position on a broadcast and hand a lying client the "draw an arrow
+			anywhere" primitive this service refuses in its header.
+		]]
+		if phrase.Pings and senderRoot ~= nil then
+			pingPosition = senderRoot.Position
+		end
+
+		-- The broadcast lands in Step 3.4.
+		recordVerdict("OK")
```

#### Step 3.4: Broadcast per recipient, gated on `GhostChat.shouldDeliver`

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run check:secrecy`

A loop of `FireClient`, never `FireAllClients` — the same shape and the same reason as `GhostRoster`
(`Remotes.luau:57-70`). The state test lives at the fire site because `check:secrecy` cannot see it.

```diff
+--[[
+	Deliver to everyone entitled to hear it, and to nobody else.
+
+	`FireClient` IN A LOOP, NEVER `FireAllClients`, and the reason is the same one `GhostRoster`
+	gives: what makes this safe is its AUDIENCE, not its contents. A `FireAllClients` here would put
+	a ghost's accusation in front of the living, which is the four-word rule `pure/GhostChat`'s header
+	calls the most dangerous one in the game.
+
+	AND `check:secrecy` CANNOT POLICE IT. It reads payload fields and call shapes, and
+	`FireClient(player, payload)` inside a loop over the wrong list is textually identical to one
+	over the right list. So the state test lives HERE, at the fire site, exactly as GhostService's
+	roster does — the check script is not the thing keeping this correct, this loop is.
+]]
+local function broadcast(sender: Player, payload: Types.QuickChatBroadcastPayload)
+	local senderState = RoundService.GetPlayerState(sender)
+
+	for _, recipient in Players:GetPlayers() do
+		local recipientState = RoundService.GetPlayerState(recipient)
+
+		--[[
+			THE SAME PREDICATE TEXT CHAT USES, REUSED RATHER THAN REIMPLEMENTED.
+
+			`pure/GhostChat` is a sixteen-cell grid precisely so a second feature does not get a
+			second, subtly different wall — its own header notes that an earlier single-wall version
+			delivered GHOST -> SPECTATOR, which an audit caught and a hand-rolled `if` here would
+			have reintroduced. `tests/ghost-chat.test.luau` now pins both features against it.
+
+			The casts cross a pure-module boundary: `Types.PlayerState` and `GhostChat.PlayerState`
+			are the same structural union, declared twice because a pure module may not require
+			`Types`.
+		]]
+		if
+			GhostChat.shouldDeliver(
+				senderState :: GhostChat.PlayerState,
+				recipientState :: GhostChat.PlayerState
+			)
+		then
+			broadcastRemote:FireClient(recipient, payload)
+		end
+	end
+end
```

And the handler's final lines, replacing the Step 3.3 placeholder:

```diff
-		-- The broadcast lands in Step 3.4.
 		recordVerdict("OK")
+
+		--[[
+			FOUR FIELDS, NO STRINGS, NO PLAYER STATE. See `Types.QuickChatBroadcastPayload` for the
+			full argument; the short version is that every field here is either a UserId the receiver
+			can already resolve or a position this server derived itself, and there must never be a
+			field saying whether anybody is alive.
+		]]
+		broadcast(player, {
+			SenderUserId = player.UserId,
+			PhraseId = phraseId :: Types.QuickChatPhraseId,
+			TargetUserId = targetUserId,
+			PingPosition = pingPosition,
+		})
```

#### Step 3.5: Register the service in the server bootstrap

**File:** `src/server/init.server.luau`
**Verify:** `npm run check:remotes`

```diff
 	"GhostService",
 	"TrialService",
+	--[[
+		C25. After GhostService, because this service reads `RoundService.GetPlayerState` and routes
+		through the same `pure/GhostChat` wall that GhostService installs on TextChatService — having
+		the two audience rules start in a predictable order makes a divergence easier to find. It is
+		not a require dependency: nothing here calls into GhostService.
+
+		Before RoundService for the reason every gameplay service is: the state machine starts last,
+		so no phase change can land before this handler is attached.
+	]]
+	"QuickChatService",
 	--[[
 		C23. After the four services that CALL it — ItemService, GhostService, MonsterService and
 		TaskService — because those hold a module reference from their own `require` at load, and this
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`require(script.Parent.RoundService)` from a service is an established pattern here but check for a
  cycle.** `RoundService` does not require `QuickChatService`, so the arrow is one-way — but
  `RoundService.luau:780` documents a cycle that was already hit once with `TaskService`. Confirm at
  implementation time that nothing was added to `RoundService` pointing back.
- **The raycast filter list is the one genuinely unconfirmed Roblox behaviour in this phase.** Whether
  husks, greybox decoration and tagged task props sit in the default collision group is not established
  anywhere in this repo, and a raycast that clips one reports "no line of sight" for a player standing
  in the open. Flagged in Follow Ups with a playtester artifact, not assumed.
- **`workspace:Raycast` runs once per living player per request.** At eight players that is seven casts
  per press, against a bucket that refills at 0.5/s — negligible, but it is per-request work on the
  server and it belongs in the §5 budget conversation rather than being invisible.
- **`recordVerdict("OK")` fires before the broadcast, deliberately.** If `broadcast` throws, the verdict
  log still shows the request was accepted, which is the state you want to see when debugging "it said
  it worked and nothing appeared".

### Phase 4: The wheel — GUI, gesture, and rendering what arrives

Replaces the 19-line M7 stub. Its slot in `CONTROLLER_ORDER` is already correct and already commented
for this chunk — see `references/init.client-review.luau`.

#### Step 4.1: Build the wheel GUI

**File:** `src/client/Controllers/QuickChatController.luau`
**Verify:** `npm run analyze`

A `ScreenGui` with `ResetOnSpawn = false` and `IgnoreGuiInset = true`, matching `UIController.buildHud`
(`UIController.luau:273-278`), holding eight sector buttons laid out from `sectorFor`'s own geometry so
the hit regions and the selection maths cannot disagree.

The stub's slot in `CONTROLLER_ORDER` needs **no change** — it already sits fourth, before
`InputController`, under a comment that anticipated exactly this chunk
(`references/init.client-review.luau`).

```diff
 --!strict
 --[[
 	QuickChatController — The radial quick-chat wheel.
 
-	Milestone: M7
-	Spec: docs/MVP-SPEC.md
+	Milestone: M7, chunk C25. Spec §4.5.
+
+	THIS IS THE COMMUNICATION SYSTEM, not a convenience on top of one. §4.5: voice chat requires 13+
+	age verification most of this audience does not have, and typing on a phone mid-chase is
+	impossible. Accusation gameplay with no way to accuse is not gameplay, which is why the spec says
+	"do not cut it" in bold.
+
+	WHAT THIS CONTROLLER OWNS AND WHAT IT DOES NOT
+	----------------------------------------------
+	It owns a wheel, a gesture, and the rendering of what arrives. It owns NO decision. The sequence
+	is: the player picks a sector, this fires `RequestQuickChat` with a phrase ID and NOTHING ELSE,
+	and the server decides who is named, where the ping lands and who hears it.
+
+	In particular this controller never sends a name and never sends a position — see
+	QuickChatService's header for why both would be exploits rather than shortcuts. It also never
+	sends the phrase TEXT: the strings live in `shared/pure/QuickChatPhrases` and are rendered here
+	from an id, which is what keeps user-generated text off the wire entirely.
+
+	THE WHEEL IS A RADIAL MENU BECAUSE OF §5, NOT BECAUSE IT LOOKS GOOD. Eight sectors is 45 degrees
+	each, so a thumb drag only has to be accurate to +/-22.5 degrees. A vertical list of eight items
+	needs positional accuracy on a moving screen with a thumb covering the target. That difference is
+	the entire reason this shape was chosen, and it is why `QuickChatPhrases.sectorFor` is a tested
+	pure function rather than arithmetic inlined in a touch callback.
 ]]
 
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local QuickChatPhrases = require(Shared.pure.QuickChatPhrases)
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
+
 local QuickChatController = {}
 
--- TODO(M7): 8-phrase radial menu + world ping.
--- Voice chat needs 13+ verification and typing mid-chase is impossible, so
--- this IS the communication system. Do not cut it (spec §4.5).
+local wheelGui: ScreenGui? = nil
+local wheelFrame: Frame? = nil
+local sectorButtons: { [number]: TextButton } = {}
+local isOpen = false
+local highlightedSector: number? = nil
+
+--[[
+	Build the wheel once, hidden, and show/hide it thereafter.
+
+	`ResetOnSpawn = false` and `IgnoreGuiInset = true` match `UIController.buildHud`, and the first
+	one is load-bearing rather than cosmetic: a ghost has no respawn to survive, and a wheel that
+	vanished on death would silently remove the ghost channel §4.7's retention argument depends on.
+]]
+local function buildWheel()
+	if wheelGui ~= nil and wheelGui.Parent ~= nil then
+		return
+	end
+
+	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
+	local gui = Instance.new("ScreenGui")
+
+	gui.Name = "QuickChatWheel"
+	gui.ResetOnSpawn = false
+	gui.IgnoreGuiInset = true
+	gui.Enabled = false
+	gui.Parent = playerGui
+	wheelGui = gui
+
+	local frame = Instance.new("Frame")
+
+	frame.Name = "Wheel"
+	frame.AnchorPoint = Vector2.new(0.5, 0.5)
+	frame.Size = UDim2.fromOffset(
+		Config.QuickChat.WheelRadiusPx * 2,
+		Config.QuickChat.WheelRadiusPx * 2
+	)
+	frame.BackgroundTransparency = 1
+	frame.Parent = gui
+	wheelFrame = frame
+
+	--[[
+		ONE BUTTON PER SECTOR, POSITIONED FROM THE SAME GEOMETRY `sectorFor` INVERTS.
+
+		The label sits at half the wheel radius along its sector's centre angle, and the button is
+		sized to the touch floor. Deriving the position from `phrase.Order` and `Sectors` rather than
+		from a hand-written table of offsets is what stops the hit region and the selection maths
+		from drifting apart — a wheel where the label says "Run!" and the angle selects "Trust me" is
+		a bug that only shows up under a thumb.
+	]]
+	local step = (math.pi * 2) / QuickChatPhrases.Sectors
+	local ring = Config.QuickChat.WheelRadiusPx / 2
+
+	for _, phrase in QuickChatPhrases.All do
+		local angle = phrase.Order * step
+		local button = Instance.new("TextButton")
+
+		button.Name = phrase.Id
+		button.AnchorPoint = Vector2.new(0.5, 0.5)
+		button.Size = UDim2.fromOffset(
+			Config.QuickChat.MinTouchTargetPx * 2,
+			Config.QuickChat.MinTouchTargetPx
+		)
+		-- Sector 0 is straight UP, so sin drives X and cos drives -Y.
+		button.Position = UDim2.new(0.5, math.sin(angle) * ring, 0.5, -math.cos(angle) * ring)
+		button.BackgroundTransparency = 0.35
+		button.BorderSizePixel = 0
+		button.Font = Enum.Font.GothamBold
+		button.TextScaled = true
+		button.Text = phrase.Text
+		-- The gesture drives selection, so the buttons are targets and highlights rather than
+		-- clickables. `Active = false` keeps them from swallowing the drag that is selecting them.
+		button.Active = false
+		button.AutoButtonColor = false
+		button.Parent = frame
+
+		sectorButtons[phrase.Order] = button
+	end
+end
 
-function QuickChatController.Init() end
+function QuickChatController.Init()
+	buildWheel()
+end
 
 function QuickChatController.Start() end
 
 return QuickChatController
```

#### Step 4.2: The open / drag / release gesture

**File:** `src/client/Controllers/QuickChatController.luau`
**Verify:** `npm run lint`

One gesture, one thumb: press opens the wheel anchored at the press point, drag past
`Config.QuickChat.DeadZonePx` picks a sector by **angle**, release commits. Angular selection is why a
radial menu works on a phone at all — 8 sectors is ±22.5° of tolerance.

```diff
+--[[
+	ONE GESTURE: press, drag, release. Not press-then-tap.
+
+	THIS IS THE MOBILE DECISION, and it is worth being explicit about what it buys. A press-then-tap
+	wheel needs the thumb to leave the screen and land accurately on a small target a second time,
+	while the player is being chased and the camera is moving. Press-drag-release never lifts the
+	thumb: the wheel opens under it, the selection is an ANGLE from where it started, and letting go
+	commits. The accuracy required is +/-22.5 degrees of direction rather than a pixel position.
+
+	It also gives cancel for free — drag back inside `DeadZonePx` and release, which is the gesture
+	a player will try without being told.
+]]
+local function openAt(screenPosition: Vector2)
+	buildWheel()
+
+	local frame = wheelFrame
+	local gui = wheelGui
+
+	if frame == nil or gui == nil then
+		return
+	end
+
+	--[[
+		THE WHEEL OPENS AT THE THUMB, NOT AT SCREEN CENTRE.
+
+		A centred wheel on a phone means reaching across the screen with the hand that is also
+		holding it. Opening under the press point is what makes this one-handed — the thumb is
+		already where the wheel is. It is also why the open button lives in the bottom-right thumb
+		arc (Step 5.1) rather than anywhere that looks tidy on a desktop screenshot.
+	]]
+	frame.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y)
+	gui.Enabled = true
+	isOpen = true
+	highlightedSector = nil
+end
+
+--[[
+	Which sector is the drag pointing at, or nil for "inside the dead zone, this is a cancel".
+
+	The angle maths is `math.atan2`, which returns (-pi, pi] — negative and wrapped values are the
+	normal case here, not the edge case, which is why `QuickChatPhrases.sectorFor` is total over all
+	reals and why the test enumerates the wrap.
+]]
+local function sectorAt(screenPosition: Vector2, origin: Vector2): number?
+	local delta = screenPosition - origin
+
+	if delta.Magnitude < Config.QuickChat.DeadZonePx then
+		return nil
+	end
+
+	-- Y grows DOWNWARD in screen space, so it is negated to make sector 0 point up.
+	return QuickChatPhrases.sectorFor(math.atan2(delta.X, -delta.Y))
+end
+
+local function highlight(sector: number?)
+	if sector == highlightedSector then
+		return
+	end
+
+	for order, button in sectorButtons do
+		button.BackgroundTransparency = if order == sector then 0 else 0.35
+	end
+
+	highlightedSector = sector
+end
+
+--[[
+	Commit the selection, or close with nothing.
+
+	THE ONLY THING THAT CROSSES THE WIRE IS `phrase.Id`. No name, no position, no text. Everything
+	else about the resulting message is the server's decision — see QuickChatService's header.
+]]
+local function closeAndCommit()
+	local gui = wheelGui
+
+	if gui ~= nil then
+		gui.Enabled = false
+	end
+
+	isOpen = false
+
+	local sector = highlightedSector
+
+	highlight(nil)
+
+	if sector == nil then
+		return
+	end
+
+	for _, phrase in QuickChatPhrases.All do
+		if phrase.Order == sector then
+			Remotes.Get("RequestQuickChat"):FireServer(phrase.Id)
+			return
+		end
+	end
+end
```

#### Step 4.3: Render a received `QuickChatBroadcast`

**File:** `src/client/Controllers/QuickChatController.luau`
**Verify:** `npm run check:remotes`

Resolve both names from `Players:GetPlayerByUserId`, substitute into the phrase template held locally,
and stack at most `Config.QuickChat.MaxVisibleMessages`. No string from the wire is ever displayed.

```diff
+--[[
+	Resolve a UserId to a name, or to a placeholder.
+
+	THE PAYLOAD CARRIES IDS AND THIS FUNCTION IS WHY. A display name is user-generated content; a
+	UserId is a number. Sending the number and resolving it here means no player-authored string ever
+	travels over a remote, which is what removes the filtering question rather than answering it —
+	see QuickChatService's header and the plan's Follow Ups.
+
+	The nil case is not hypothetical: a player named in an accusation can leave in the milliseconds
+	between the server resolving them and this client rendering it. "Someone" is the honest render,
+	and it degrades the message rather than the client.
+]]
+local function nameOf(userId: number): string
+	local player = Players:GetPlayerByUserId(userId)
+
+	return if player ~= nil then player.DisplayName else "Someone"
+end
+
+--[[
+	Render an arriving broadcast.
+
+	The template comes from the LOCAL phrase table, never from the wire. An unknown id is dropped
+	silently rather than rendered — a client running an older build than the server should show
+	nothing, not a raw enum name.
+]]
+local function onBroadcast(payload: Types.QuickChatBroadcastPayload)
+	local phrase = QuickChatPhrases.get(payload.PhraseId)
+
+	if phrase == nil then
+		return
+	end
+
+	local body = phrase.Text
+
+	if phrase.NeedsTarget then
+		local targetUserId = payload.TargetUserId
+
+		-- A target-taking phrase with no target should not have been broadcast at all — the server
+		-- refuses that case. Dropping it here rather than rendering "It's !" keeps a server bug from
+		-- becoming a visibly broken feature.
+		if targetUserId == nil then
+			return
+		end
+
+		body = string.gsub(body, "{name}", nameOf(targetUserId))
+	end
+
+	pushMessage(`{nameOf(payload.SenderUserId)}: {body}`)
+
+	if payload.PingPosition ~= nil then
+		showPing(payload.PingPosition :: Vector3)
+	end
+end
```

The message stack itself, capped at `MaxVisibleMessages` so a burst cannot become the HUD:

```diff
+local messages: { TextLabel } = {}
+
+local function pushMessage(line: string)
+	-- Oldest out first. §5's mobile budget is the reason this is a hard cap rather than a scroll:
+	-- an unbounded stack of labels on a phone is unbounded per-frame layout work.
+	while #messages >= Config.QuickChat.MaxVisibleMessages do
+		local oldest = table.remove(messages, 1)
+
+		if oldest ~= nil then
+			oldest:Destroy()
+		end
+	end
+
+	-- ... construct the label, parent it to the message column, and schedule its removal after
+	-- Config.QuickChat.MessageLifetimeSeconds.
+end
```

And the wiring, in `Start`:

```diff
-function QuickChatController.Start() end
+function QuickChatController.Start()
+	Remotes.Get("QuickChatBroadcast").OnClientEvent:Connect(onBroadcast)
+	-- Input binding lands in Step 5.1.
+end
```

#### Step 4.4: Draw the world ping

**File:** `src/client/Controllers/QuickChatController.luau`
**Verify:** `npm run check:config`

A client-drawn `BillboardGui` in `PlayerGui`, living for `Config.QuickChat.PingLifetimeSeconds`. Client
side because a server-created marker is a permanent replicated instance attached to one player, which is
the shape §6.2 refuses — the same argument `FirstObjectiveAssigned` makes (`Remotes.luau:44-46`).

```diff
+--[[
+	Draw a world ping at a server-derived position.
+
+	CLIENT-SIDE, AND THAT IS A SECURITY DECISION RATHER THAN A PERFORMANCE ONE. A `BillboardGui` or
+	`Beam` created on the SERVER is a permanent replicated instance sitting at a place a specific
+	player just stood — visible to every client, including one that was not entitled to the message
+	that produced it. `FirstObjectiveAssigned` makes exactly this argument for its waypoint, and the
+	reasoning transfers unchanged: the marker is drawn by each entitled recipient, into their own
+	PlayerGui, from a payload they were entitled to receive.
+
+	Adornee is a throwaway anchored part rather than a character: the ping marks WHERE SOMETHING WAS,
+	not who is there now, and attaching it to a player would turn "Body here!" into a tracker that
+	follows the sender around.
+
+	§5 BUDGET. A BillboardGui with `LightInfluence = 0` and no ParticleEmitter costs no dynamic
+	light, which matters because `Performance.MaxVisibleLights` is 8 and this is a feature players
+	will use in bursts. The lifetime cap plus `MaxVisibleMessages` bounds how many can exist.
+]]
+local function showPing(position: Vector3)
+	local anchor = Instance.new("Part")
+
+	anchor.Name = "QuickChatPing"
+	anchor.Anchored = true
+	anchor.CanCollide = false
+	anchor.CanQuery = false
+	anchor.CanTouch = false
+	anchor.Transparency = 1
+	anchor.Size = Vector3.one
+	anchor.CFrame = CFrame.new(position)
+	anchor.Parent = workspace
+
+	local billboard = Instance.new("BillboardGui")
+
+	billboard.Name = "Ping"
+	billboard.AlwaysOnTop = true
+	billboard.LightInfluence = 0
+	billboard.Size = UDim2.fromOffset(
+		Config.QuickChat.MinTouchTargetPx,
+		Config.QuickChat.MinTouchTargetPx
+	)
+	billboard.Adornee = anchor
+	billboard.Parent = anchor
+
+	-- ... the marker label, then removal after Config.QuickChat.PingLifetimeSeconds.
+	task.delay(Config.QuickChat.PingLifetimeSeconds, function()
+		anchor:Destroy()
+	end)
+end
```

⚠ **A client-created `Part` parented to `workspace` is not confirmed to stay local.** Instances created
on the client in `workspace` are conventionally client-only, but this repo has no precedent for it and
`StreamingEnabled` (§5) is on. Flagged in Follow Ups; if it proves unreliable the anchor moves to
`Camera`, which is unambiguously local.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Lua has no forward declarations, so `pushMessage` and `showPing` must be defined ABOVE
  `onBroadcast`.** The diffs above are presented in reading order, not in file order. This is the kind
  of thing `analyze` does catch, but only after the edit.
- **`string.gsub` returns two values.** `body = string.gsub(...)` is correct in an assignment but
  becomes a bug the moment it is used in a call argument or a table constructor, where the count leaks
  in as a second argument. CLAUDE.md names the `pcall`-over-`() -> ()` version of this trap; it is the
  same shape.
- **The wheel must not be openable while it is already open.** `isOpen` is declared but the guard lives
  in the input binding in Step 5.1 — if that step is skipped or simplified, a second press re-anchors
  the wheel mid-drag and the release commits a sector the player never aimed at.
- **`Config.QuickChat.WheelRadiusPx` is in raw pixels and mobile screens vary.** Offset units are
  correct here rather than scale — a wheel sized as a fraction of the screen is a wheel that is too
  small on a phone and absurd on a monitor, and the touch floor is an absolute number. But it does mean
  a very high-DPI device is a case the playtester should look at rather than assume.

### Phase 5: Mobile reach, the filter question, and the lifecycle edges

#### Step 5.1: The touch button and the thumb zone

**File:** `src/client/Controllers/QuickChatController.luau`

**No `**Verify:**` line, deliberately.** "Is this reachable with one thumb" is a judgement about a human
hand and there is no command that answers it. `verify-plan` will report this step as `unverifiable` and
`next-phase.mjs` will mark the phase `needs-human`, which is the accurate outcome.

**Artifact the playtester must produce:** `artifacts/wheel-touch-layout.png` — a touch-emulated viewport
(iPhone-class aspect) with the wheel **open**, showing it inside the bottom-right thumb arc, not
overlapping the salt throw button `ContextActionService` creates, and not covering screen centre. Plus
`artifacts/wheel-received-message.png` showing a broadcast rendered on a second client.

**What "thumb-reachable" means concretely here**, so the judgement is against a stated target rather
than a feeling:

- The **open button** sits in the bottom-right quadrant, at least `MinTouchTargetPx` on its shortest
  side, within roughly the lower third of the screen height — the arc a thumb sweeps while the other
  four fingers hold the device.
- It is **stacked vertically above** the salt throw button rather than beside it. Salt is the only
  other bind in the game that asks for a touch button (`InputController.luau:365`), and it is the one
  that must never be blocked: §4.6 is the only counterplay survivors have.
- The **wheel opens under the thumb**, not at screen centre, so no part of the gesture crosses the
  device. This is already how `openAt` works; the layout step is about where the *button* is.
- The **centre of the screen stays clear** while the wheel is open. That is the chase view, and §4.5's
  whole premise is that this gets used mid-chase.
- Sector hit regions are **angular**, so the tolerance is ±22.5°, and `tests/quick-chat-phrases.test.luau`
  already pins that the resulting arc exceeds the 44px floor at the configured radius.

**This is C25's wheel only.** General touch buttons for transform, interact and task are **C27** and
explicitly out of scope — this step adds one button for one feature, not a mobile input layer.

```diff
+	--[[
+		`true` FOR createTouchButton — THE SECOND BIND IN THE GAME TO ASK FOR ONE.
+
+		`InputController` passes `false` for transform, kill, task and timing, and calls mobile a
+		known hole deferred to C27. Salt was the first exception, for the reason its comment gives:
+		§5 puts ~60% of players on a phone and a mobile player with no throw has no counterplay.
+
+		Quick chat is the second, and the argument is §4.5's own: voice needs 13+ verification this
+		audience lacks and typing mid-chase on a phone is impossible, so a phone player with no wheel
+		cannot communicate AT ALL. That is not a missing convenience, it is the accusation game
+		removed for 60% of the players.
+
+		⚠ `ContextActionService`'s touch buttons are placed by CoreGui in a region this code does not
+		control, and whether a second requested button stacks predictably above the salt one is NOT
+		confirmed anywhere in this repo. If they collide or reorder, the fallback is a hand-placed
+		TextButton in this controller's own ScreenGui, which costs the ContextActionService
+		integration but gives absolute placement. Playtester decides — see Follow Ups.
+
+		⚠ The KEYBOARD key is NOT confirmed free of a CoreScript claim, the same caveat `R` and `Q`
+		carry in InputController. C08 shipped unreachable because ProximityPrompt's default `E`
+		silently swallowed an identical bind.
+	]]
+	ContextActionService:BindAction(WHEEL_ACTION, onWheelAction, true, Enum.KeyCode.B)
```

#### Step 5.2: The lifecycle edges

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run test:unit`

Round ends with the wheel open; the accused leaves between resolution and render; a sender dies in the
same frame. Each resolves to "the client renders a fallback and the server asserts nothing".

Spec §6.4's five edge cases, answered for C25 specifically:

| Edge case | C25's answer |
| --- | --- |
| **The accused leaves between resolution and render** | `nameOf` returns `"Someone"`. Already handled in Step 4.3; the point of listing it is that this is why the payload carries an id rather than a name — a name resolved server-side would have frozen a departed player's name into every HUD. |
| **The sender dies in the same frame** | The server read `GetPlayerState` once, at the top of the handler, and `broadcast` re-reads it at the fire site. A player who died between the two delivers to ghosts, which is the safe direction. |
| **The round ends with the wheel open** | The wheel is client state and closes on the next phase change; a `RequestQuickChat` arriving after `ACTIVE` is refused `WRONG_PHASE`. Nothing is left holding a lock. |
| **A player joins mid-round** | `SPECTATOR`. `GhostChat.shouldDeliver` gives them their own island — they receive nothing from ghosts and nothing from the living reaches them from the ghost side. They can hear the living, which is correct and is what text chat already does. |
| **A ghost rejoins as their own alt** | Unchanged by C25 — `pure/RejoinResolve` owns it, and the wheel adds no new channel a returning account could read. |

```diff
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase == Enums.RoundPhase.Starting then
+		table.clear(verdictCounts)
+	end
+
+	--[[
+		C41 will want to know how often the accusation found nobody: a high NO_TARGET_IN_SIGHT rate
+		means `AccuseRangeStuds` is too tight or the greybox has too many sight-blockers, and a rate
+		near zero across a whole round means it is loose enough to be worth re-examining as an
+		oracle. Logged at round end, ungated, because it is a tuning fact rather than tracing.
+	]]
+	if phase == Enums.RoundPhase.Ending and Config.Debug.VerboseLogging then
+		print(`[QuickChat] verdicts this round: {game:GetService("HttpService"):JSONEncode(verdictCounts)}`)
+	end
+end
```

#### Step 5.3: Document the `TextService` decision in place, behind a Config flag

**File:** `src/server/Services/QuickChatService.luau`
**Verify:** `npm run check:scope`

The reasoning for shipping no filter call, and the guarded path if the policy answer overrules it —
`pcall` inside `task.spawn`, never inline in the handler, failing **closed**.

**The three-part answer to "is filtering required at all":**

1. **The eight phrases are not user-generated content.** They are author-written game copy, fixed at
   build time, that a player *selects* rather than *authors*. Roblox's filtering obligation attaches to
   text a user produces. A dropdown of developer-written strings is the same category as a button label.
2. **The one UGC string in scope is the accused player's display name** — display names are user-chosen,
   so interpolating one into a broadcast is putting UGC in front of other players. **This plan never
   transmits it.** `TargetUserId` crosses the wire; each client resolves the name from
   `Players:GetPlayerByUserId(...).DisplayName`, which is the same path the default leaderboard and
   Roblox's own chat use, and which reads an already-moderated account-level string.
3. **Therefore no `FilterStringAsync` call exists on the hot path, and the failure mode asked about
   does not arise.** There is no web call inside the `OnServerEvent` handler to yield or throw.

⚠ **UNCONFIRMED, and it is the load-bearing uncertainty of this chunk:** whether Roblox policy treats a
display name rendered in *custom* UI as needing `FilterStringAsync`, given it is already moderated at
account level. I have not verified this against current policy and will not guess it — see Follow Ups.
It is the one question whose answer could change the payload shape.

```diff
+--[[
+	THE FILTER PATH, OFF BY DEFAULT. See this service's header for why it is off.
+
+	If the policy answer says a display name rendered in custom UI must be filtered, this is where it
+	goes — and the SHAPE matters more than the call:
+
+	  · `FilterStringAsync` IS A YIELDING WEB REQUEST. Calling it inline in an `OnServerEvent`
+	    handler makes every quick chat wait on Roblox's text service, on the 🔒 surface, at a moment
+	    when the player pressing the button is being chased. It must run in `task.spawn` so the
+	    handler returns immediately.
+	  · IT CAN THROW. A network failure or a moderation outage raises rather than returning a bad
+	    string, so it must be wrapped in `pcall` — and `pcall` over a call returning one value gives
+	    `(ok, result)`, the trap CLAUDE.md names.
+	  · IT FAILS CLOSED. On a throw or a timeout the broadcast is DROPPED, not sent unfiltered and
+	    not sent with a placeholder name. Dropping costs one message; sending unfiltered text is the
+	    kind of failure that ends a Roblox game rather than degrading it. This is the same direction
+	    `AntiCheat.AllowUnbudgetedRemote = false` picks.
+	  · IT IS PER-RECIPIENT. `GetChatForUserAsync(toUserId)` filters differently per viewer, which
+	    means the payload could no longer be one shared table — it would become a per-recipient
+	    string, which is a materially different broadcast and a materially larger change. That cost
+	    is the strongest practical argument for resolving names client-side.
+]]
+-- config-ok: a policy switch, not a balance number. Default false; see the header above.
+FilterDisplayNames = false,
```

#### Step 5.4: The full gate

**File:** `src/shared/Config.luau`
**Verify:** `npm run verify`

The whole gate — analyze, lint, format, all five checks, every Lune suite, the harness self-tests. The
file named is `Config.luau` because the last thing to confirm before this chunk is done is that the
playtester's debug values (`Round.Intermission/Duration/EndScreen`, `Debug.SoloTesting`,
`Debug.VerboseLogging`) are **reverted** — `guard-commit.mjs` runs `check:debug` and will refuse the
commit otherwise, and `git diff src/shared/Config.luau` should show only the C25 block.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`FilterDisplayNames` will trip `check:config` unless it carries the waiver.** It is a boolean policy
  switch rather than a tunable, and the `-- config-ok:` comment with its reason is what makes that a
  visible decision instead of a silenced check.
- **Step 5.1 is the phase's only unverifiable step and it gates the chunk's "Done".** C25's row says
  "the wheel is usable one-handed", and no command establishes that. `next-phase.mjs` will mark Phase 5
  `needs-human`, which is correct — do not add a check to clear it.
- **`exploit-auditor` is mandatory for this diff and is not a judgement call.** It touches
  `src/server/**` and the audience rule; `review-gate.mjs` will name it. The scoped brief should be:
  *can a client cause `resolveTarget` to name a player it could not see, and can any sequence of
  quick-chat requests distinguish "nobody nearby" from "somebody nearby but occluded"?*
- **The playtester needs three clients, not two.** The audience rule is only observable with a living
  sender, a living recipient and a ghost — two clients cannot distinguish "delivered to everyone" from
  "delivered correctly".

## 3. Related Files

| File | Role in C25 | Reference review |
| --- | --- | --- |
| `docs/MVP-SPEC.md` §4.5 | The eight phrases, and the "do not cut it" instruction | — |
| `docs/BUILD-PLAN.md` C25 (line 570) | The row: Large, 🔒, plan-backed, and the `TextService` line this plan disputes | — |
| `src/shared/Remotes.luau` | `RequestQuickChat` / `QuickChatBroadcast` already declared; no new remote | `references/Remotes-review.luau` |
| `src/shared/Config.luau` | `RequestQuickChat` budget already present; gains the `QuickChat` block | `references/Config-review.luau` |
| `src/shared/pure/GhostChat.luau` | The audience rule, **reused not reimplemented** | `references/GhostChat-review.luau` |
| `src/server/Services/GhostService.luau` | The model for a per-recipient filtered broadcast and a guarded handler | `references/GhostService-review.luau` |
| `src/server/Services/AntiCheatService.luau` | `Consume` — and why its NAME is load-bearing | `references/AntiCheatService-review.luau` |
| `src/server/Services/RoundService.luau` | `GetPhase`, `GetPlayerState`, `PhaseChanged`. Read-only for C25 | `references/RoundService-review.luau` |
| `src/client/Controllers/QuickChatController.luau` | The 19-line stub this replaces | `references/QuickChatController-review.luau` |
| `src/client/init.client.luau` | `CONTROLLER_ORDER` — already correct, needs no edit | `references/init.client-review.luau` |
| `src/client/Controllers/InputController.luau` | The `createTouchButton` precedent and the CoreScript-collision caveat | `references/InputController-review.luau` |
| `src/client/Controllers/UIController.luau` | The GUI construction idiom, and the layout-collision check | `references/UIController-review.luau` |
| `tests/anti-cheat-budgets.test.luau` | The hand-copied up-remote list that has drifted twice | `references/anti-cheat-budgets-review.luau` |
| `src/shared/Types.luau` | `ClientRoundSnapshot`'s A3 note — the reasoning C25 inherits | `references/Types-review.luau` |

## 4. Follow Ups

### Questions / Clarifications

**1. The `TextService` conflict with the C25 row — decide before Phase 5.** The BUILD-PLAN row says the
broadcast is "**`TextService`-filtered**". This plan ships no filter call, because the design removes
every user-generated string from the wire rather than sanitising one (§2 Step 5.3). Per CLAUDE.md's
precedence rule the build plan wins unless the conflict is raised, so it is raised: **is the row asking
for filtering as a mechanism, or as an outcome?** If the outcome, this plan satisfies it more completely
than a filter call would. If the mechanism, Step 5.3's guarded path is the implementation and
`FilterDisplayNames` flips to true — at the cost of a per-recipient payload, which is a materially
larger change.

**2. UNCONFIRMED Roblox behaviour — `TextService`.** I have not verified `FilterStringAsync`'s current
signature, its `TextFilterContext` values, or whether `GetNonChatStringForBroadcastAsync` remains the
right companion for a non-chat broadcast. There is no `TextService` usage anywhere in this repo to check
against. If Step 5.3's path is ever enabled, **confirm the API before writing it** rather than trusting
the shape described in that comment.

**3. UNCONFIRMED Roblox behaviour — policy on display names in custom UI.** Whether an account-level
display name rendered in developer UI requires `FilterStringAsync`. This is the single question that
could change the payload shape, and it is a policy question rather than an API one — it needs a reading
of current Roblox rules, not a Studio test.

**4. UNCONFIRMED Roblox behaviour — a second `createTouchButton`.** `ContextActionService` places touch
buttons in a CoreGui-managed region. Whether a second requested button stacks predictably above the salt
throw button, and whether the two can collide or reorder between sessions, is not established anywhere
in this repo. Fallback named in Step 5.1: a hand-placed button in this controller's own ScreenGui.

**5. UNCONFIRMED Roblox behaviour — client-created instances in `workspace` under `StreamingEnabled`.**
The ping anchor is a client-made `Part` parented to `workspace`. Conventionally that stays local, but
this repo has no precedent and §5 turns streaming on. Fallback: parent to `Camera`.

**6. UNCONFIRMED Roblox behaviour — the raycast filter list.** Whether greybox decoration, husk models
and tagged task props sit in the default collision group. A cast that clips one reports "no line of
sight" for a player standing in the open, which degrades the accusation phrase silently.

**7. UNCONFIRMED Roblox behaviour — the keyboard key.** `B` is a placeholder. C08 shipped unreachable
because ProximityPrompt's default `E` swallowed an identical bind, and nothing static proves `B` is
unclaimed. Same caveat `R` and `Q` already carry in `InputController`.

**8. THE LIVENESS QUESTION, for GATE 1 rather than for this plan.** Amendment A3 removed
`AlivePlayerCount` because a death signal is the missing input to a position-correlation attack. C25
does not reintroduce one — but two things are worth stating out loud rather than buried:

- **"Who has sent recently" is a partial liveness signal, and it is not new.** `TextChatService` has
  carried exactly this since C15 under the same `GhostChat` predicate. Quick chat makes it *denser*
  (one thumb press instead of typing) but not *different in kind*. No decision needed; noted so nobody
  rediscovers it as a finding.
- **The accusation asserts a THIRD PARTY was alive at time T, and that is genuinely new.** A recipient
  who did not see the exchange learns that the accused was alive, in line of sight of the sender, within
  `AccuseRangeStuds`, at that instant. Text chat cannot do this mechanically — a human typing "I saw
  Bob" is a *claim*, whereas this is a *server-attested fact*.

  **Why this plan accepts it:** A3's objection was to an **involuntary, automatic, unattributable**
  signal correlated with a **death**. This is voluntary, attributable, and correlated with nothing — the
  sender pays for it by revealing their own adjacency to the accused, and no death timestamp is
  produced anywhere. An accusation that costs the accuser information is the accusation mechanic
  working as §4.5 intends. But it is the one place C25 touches A3's reasoning, so **GATE 1 should be
  asked whether players use it as an accusation or as a liveness ping.** If the latter, the lever is
  `AccuseRangeStuds`, not the payload.

**9. Amendment A3 names this chunk by implication, and the plan does not build what it points at.**
Found while reviewing `Types.luau`. The A3 note says C18's alive-count HUD element "has no data source
and must not be given one", and that if players are lost without it the answer is "a *diegetic*,
latency-bearing one — **a tally the quick-chat wheel can assert**, a board in the plaza someone has to
walk to". That is this wheel, named in the amendment. **C25 as planned builds no such tally** — there is
no "3 of us left" phrase among §4.5's eight, and §C22's scope warning plus C25's own row say the phrase
set is fixed at eight. So this is left deliberately unbuilt and flagged rather than silently skipped:
**if GATE 1 says players need an alive count, the ninth phrase is the sanctioned way to give them one**,
and it is a design decision for that gate, not an implementation detail for this chunk.

**10. The clean fix for the hand-copied up-remote list is still unbuilt.** `anti-cheat-budgets.test.luau`
has named it in its own header since C02: a check script that parses both `Remotes.luau` and
`Config.luau`. C25 is the third chunk to read that comment and route around it. Not this chunk's job —
but it is now a recurring cost rather than a hypothetical one, and worth a `lessons-review` candidate.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 2 | `QuickChatTarget.nearest` cannot exclude the sender; a caller that forgets makes every accusation name the accuser, silently | High | Closed by design — Step 3.3 excludes in the loop, `tests/quick-chat-target.test.luau` asserts the contract |
| 3 | Line of sight is the only thing preventing the accusation phrase being a through-wall proximity radar for the Aswang | High | Closed by design — required in `resolveTarget`, and both the hit and the miss are non-informative as a result |
| 3 | Ghosts have no server character, so an accusation from one could only resolve from a client-supplied position | High | Closed by design — `GhostMay = false` on the one target-taking phrase, pinned by test |
| 3 | `check:secrecy` cannot see whether the `FireClient` loop iterates the right list | Medium | Accepted — the state test lives at the fire site, same as `GhostRoster` |
| 3 | **Caught during reference review:** an early draft echoed `NO_TARGET_IN_SIGHT` to the sender for a "nobody in sight" toast. `GhostService`'s spook handler refuses to echo its verdict because a readable refusal is a state oracle — fire it and read your own aliveness off the error code | High | Closed — the plan now echoes nothing; the sender learns the result by receiving their own broadcast |
| 5 | Build plan says `TextService`-filtered; this plan ships no filter call | Medium | **Open** — Follow Up 1, needs a decision before Phase 5 |
| 5 | Display-name filtering policy unconfirmed; could change the payload shape | Medium | **Open** — Follow Up 3 |
| 4 | Second `createTouchButton` placement unconfirmed | Low | **Open** — Follow Up 4, fallback named |
| 4 | Client-created `workspace` part under `StreamingEnabled` unconfirmed | Low | **Open** — Follow Up 5, fallback named |
| 3 | Raycast filter list vs. greybox/husk collision groups unconfirmed | Low | **Open** — Follow Up 6, playtester |
| 5 | `B` not confirmed free of a CoreScript claim | Low | **Open** — Follow Up 7, same caveat as `R` and `Q` |
