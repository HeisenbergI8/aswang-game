# Plan: V10 — Buntot pagi, the only kill

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V10 (`docs/BUILD-PLAN.md` §V10). Deps V05 (health) and V08 (the slot), both shipped.
- **Description:** Give the buntot pagi the one verb it has left. A pure module decides the two-condition
  grid, the server resolves the target and the outcome, the client only requests, and the item is spent
  on every swing that reaches the spend line.
- **Date:** 2026-09-01
- **What the client is told:** **nothing new.** V10 adds ONE remote and it goes UP only —
  `RequestStrike`, argument-free, with no reply on any path including a kill. No new
  server→client remote, no field on `ClientRoundSnapshot`, no attribute, no tag. The public half of a
  strike is that the monster falls over, which replicates as geometry and as the round ending, exactly
  as `GarlicBarriers`' header argues for the bulb on the doorway.

### 1.1 Scope boundary — V10 ends at "the Aswang dies"

**V10 does not touch win conditions and does not touch bodies.** `RoundService.MarkKilled` already ends
the round with `RoundResult.Aborted` when the Aswang becomes DEAD, on the disconnect path's reasoning
("end cleanly rather than leaving survivors wandering a monster-free map"). That is the **wrong result**
for a strike — the survivors did not abort, they won — and **V11 owns replacing it.** V10 routes the
strike through the existing death path, accepts `ABORTED` as the round result, and says so in Follow Ups.
Changing `RoundResult` here would be building half of V11 with none of its six invariants written down,
which is the exact failure `pure/ItemUse`'s header exists to prevent.

Likewise V12 owns the corpse the dead Aswang leaves. V10 calls `RoundService.MarkKilled(aswang, false)`
and lets `applyBodyRule` do whatever it does today.

### 1.2 The three decisions this plan makes, and the arguments for them

These are stated here, above Phase 1, because `npm run plan:phase` serves this preamble alongside Phase 1
and because Phases 2, 3 and 4 each depend on all three. They are repeated in the phase bodies that act on
them rather than cross-referenced.

**Decision A — `RequestStrike` carries NO argument.** The client names no target, no direction and no
item. `Remotes.luau`'s `RequestPlaceGarlic` header is the precedent and its argument transfers whole: a
target argument "needs a verdict for *that player is not near you*, which is the distance comparison the
server was already positioned to make; and it hands a compromised client a PROBE." The probe here is
sharper than garlic's. A `RequestStrike(targetUserId)` lets a client aim at **one named player** and
observe whether that player died — a per-player oracle whose answer is "yes" exactly once and "no" for
everyone else. With no argument the client can only ask *"is there something killable within arm's
reach of me"*, and the answer to that question is a monster falling over in the open, which every
client with line of sight was going to see anyway. The server resolves the candidate from the
striker's own character position, which is `RequestSearch`'s rule, `RequestCamouflage`'s rule,
`RequestDropItem`'s rule and `RequestPlaceGarlic`'s rule, restated for the fifth time.

**Decision B — the buntot pagi is spent on EVERY swing the striker was entitled to make.** §4.6 says
"it breaks on use"; a swing is a use. The competing reading — "against anything else it does nothing",
therefore a refused swing costs nothing — **is a perfect oracle and must be rejected on secrecy grounds
rather than on balance grounds.** `ClientRoundSnapshot.YourCarriedItem` is pushed to every client every
`Round.SnapshotInterval`, so "did my item disappear" is directly readable off the striker's own HUD. A
conditional spend therefore turns the buntot pagi into a **reusable monster-health-and-identity
detector**: swing at each player in turn, watch your own slot, and the one swing that does not consume
names the Aswang and reports that it is not yet Weakened. That is `ItemService`'s throw handler's rule
inherited verbatim — "a miss that cost nothing would make salt a probe you throw at everyone" — with
higher stakes, because there is exactly one buntot pagi and it IS the second win condition.

The spend line therefore sits **above** every target-side branch and **below** the striker-side ones.
Concretely: a swing is spent iff the phase is ACTIVE, the striker is ALIVE, and the striker is holding
`BUNTOT_PAGI`. Everything about the target — nobody near, a survivor near, a healthy Aswang near, an
Exposed-but-not-Weakened Aswang near, a Weakened-but-not-Exposed Aswang near — is below that line and
produces an identical observable: the item is gone, a noise cue fires from the striker's position, and
nothing else happens. This is what makes the refusal grid indistinguishable *in the world*, not merely
in the return value.

**Decision C — there is no new drop path.** §4.6's "drops where the carrier falls" is **already
implemented and item-agnostic.** `ItemService.spillItem` is called from `Humanoid.Died` inside
`watchCharacter` and from `Players.PlayerRemoving`, places the item at the carrier's own root with no
forward offset ("a corpse in the open with the win condition next to it"), and its header already names
the buntot pagi as the item whose loss it warns about. V10 writes **no second drop path**; it inherits
this one and the playtester confirms it end to end. Adding one would be the duplication surface
`spillItem`'s header refuses.

### 1.3 The finding that changes the Done line's signature

**`docs/BUILD-PLAN.md`'s V10 signature — `(monsterState, monsterHealth, distance, phase)` — cannot be
implemented literally, and taking it literally ships a buntot pagi that never kills.** Two reasons, both
already written down in the tree:

- **`monsterStateOf` never returns `EXPOSED`.** `MonsterService.luau:451-484` has three producers —
  `CAMOUFLAGED`, `FEEDING`, `TRANSFORMED` — and its header states why in as many words: "`EXPOSED` IS A
  LATCH, NOT AN ACTIVITY… a salted Aswang is Exposed AND still an Aswang. Returning EXPOSED here would
  shadow TRANSFORMED." A module gating on `monsterState == "EXPOSED"` would therefore return a refusal
  for every cell of the grid, forever, silently — the second win condition would simply not exist, which
  is precisely the failure §6.5 invariant 1 and spec §11's risk table call out as symptomless.
- **`Weakened` is not a state and must not become one.** `Enums.luau:69-71`: "it is a HEALTH PREDICATE…
  duplicating it as an enum member is how two sources of truth for one fact get out of step."

So the module takes **two booleans** — `TargetExposed` and `TargetWeakened` — supplied by
`MonsterService.IsExposed(userId)` and `MonsterService.IsWeakened(userId)`, which exist for exactly this
and are named for it: `MonsterService.luau:59-60` calls them "V08's strike gate, half one" and "half two."
`monsterState` is still carried, as `TargetState: MonsterState?`, because it has one real job (see §2,
Phase 2) and because the grid the Done line asks for should be literal rather than interpretive.

### 1.4 Why `src/shared/pure/` is the right home, answered rather than assumed

CLAUDE.md's test is about **inputs and seeds**, not about logic. `StrikeValidation` has no seed and no
input a client can supply: `TargetExposed` and `TargetWeakened` come off a server-only table, the
distance is measured from the server's copy of two characters, the phase is `RoundService.GetPhase()`,
and `Held` is the server's own slot. A client that requires and runs this module learns the *rule* — that
the buntot pagi kills an Exposed, Weakened Aswang — which is §4.6 stated in the spec, printed on the
tutorial (§9.1) and inferable from one round of play. It cannot supply the arguments that would make the
rule answer anything about a real player. This is `KillValidation`'s header's own test and
`MonsterHealth`'s, applied a third time.

**The health NUMBER stays out of the module, and that is the part that is a decision rather than a
default.** Passing `TargetHealth: number` would typecheck and would leak nothing through the pure layer
— but it would force `ItemService` to hold the Aswang's health in a local at the call site, and
`MonsterService`'s header is explicit that none of its four seams "returns the health value." A number
that exists in a second service's local is a number a future log line, a future `Debug.VerboseLogging`
print or a future payload field grows out of. `IsWeakened` already collapses it to a boolean on the
server that owns it; V10 uses that and adds no `GetHealth`.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The contract — the range, the invariants, the verdict union, and the verb

Nothing in this phase is reachable from the game yet. It puts the numbers where `check:config` requires
them, pins the two relationships that nothing in the game would report breaking, and flips
`pure/ItemUse`'s last unimplemented cell — which is the boundary marker V08 and V09 both left standing
for exactly this chunk.

#### Step 1.1: Add `Items.BuntotPagiStrikeRangeStuds` and the `RequestStrike` anti-cheat budget to Config

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

The strike's reach and its token bucket. Both are tunables, so both belong here or `check:config` fails
the build; the budget is priced as a once-per-round deliberate act, not a button press.

The range goes in the `Items` local at the top of the file, beside `GarlicPlaceRangeStuds` — it is an
item's reach, and `Config.Monster` is where the monster's own numbers live. Insert after
`GarlicBarrierPadStuds` (currently line 101) and before the garlic breach block:

```diff
 	GarlicBarrierHeight = 12,
 	GarlicBarrierPadStuds = 1.5,
 
+	--[[
+		V10, §4.6. HOW CLOSE THE STRIKER MUST GET, AND IT IS A CEILING RATHER THAN A REACH.
+
+		THE SERVER RESOLVES THE TARGET, NOT THE CLIENT. `RequestStrike` has no argument, so this is
+		the radius the server measures from the striker's OWN character position — the same rule
+		`RequestSearch` applies to containers and `GarlicPlaceRangeStuds` to doorways, and the reason
+		there is no per-player strike probe.
+
+		IT MUST NOT EXCEED `Monster.KillRange` (8), AND `tests/config.test.luau` PINS THAT. §4.6 gives
+		the buntot pagi to a survivor who has already salted the monster three times and caught it
+		inside a ten-second reveal; what it does not give them is the ability to finish from further
+		away than the monster can reach back. A strike range above the kill range makes the last beat
+		of the round free, and §C.5's third property — "it cannot be used to hunt; it can only
+		finish" — starts leaking. At the shipped value the two are EQUAL: you stand exactly where it
+		could take you.
+
+		AT OR BELOW IT, NEVER BELOW `Monster.FeedLeashStuds` (6) IN PRACTICE. The feed is the window
+		§4.3 built for this item — the monster locked on a corpse for FeedDuration — and a striker who
+		walks to the body is within 6 studs of the feeder by construction. This number therefore
+		decides whether the DESIGNED window works; anything under the leash makes it a coin flip
+		against a faster player, which is the sentence §4.6 uses about having no window at all.
+	]]
+	BuntotPagiStrikeRangeStuds = 8,
+
 	--[[
 		V09. THE ANTI-CHEAT BACKSTOP, AND ITS ONLY JOB IS TO NOT FIRE ON HONEST PLAYERS.
```

And the budget, in `AntiCheat.Budgets`, immediately after `RequestPlaceGarlic` (currently line 1688):

```diff
 			RequestPlaceGarlic = { Capacity = 3, RefillPerSecond = 0.25 },
+			--[[
+				V10, §4.6. THE TIGHTEST ITEM BUDGET IN THIS TABLE, AND THE ONE HONEST PLAYERS WILL
+				NEVER NOTICE — because an honest client can fire this remote at most ONCE per round.
+
+				There is exactly one buntot pagi (`Items.BuntotPagiSpawnCount`) and every swing that
+				reaches the spend line consumes it, hit or miss (see the handler in `ItemService`).
+				So the second press of an honest player's key finds an empty slot and refuses at
+				`STRIKE_NOT_HELD`, ABOVE the spend — which is why a capacity of 2 covers a
+				double-click and a reconnect retry without ever costing anybody a second item.
+
+				PRICED LIKE `RequestSmoke` NEXT DOOR RATHER THAN LIKE THE BUTTON PRESSES ABOVE. Both
+				are once-in-a-round deliberate acts whose handler walks the player list and casts a
+				ray, so an unbudgeted firehose here is server CPU spent on a question whose answer is
+				"no" for every player but one.
+
+				IT IS NOT WHAT STOPS THE PROBE. `RequestStrike` has no argument, so there is no probe
+				to rate-limit — the limiter is a cost ceiling, and the ABSENT argument is the security
+				design. See the declaration in `Remotes.luau`.
+			]]
+			RequestStrike = { Capacity = 2, RefillPerSecond = 0.1 },
 			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
```

#### Step 1.2: Pin the two strike-range invariants in the config suite

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

`BuntotPagiStrikeRangeStuds <= Monster.KillRange` — closing to strike must never be safer than standing
in the monster's own kill range — and `> 0`, because a degenerate range makes the second win condition
unreachable with no symptom.

Append beside the existing item invariants (the suite is a flat sequence of `assert` calls with a
message; match whatever helper the file already uses at that point):

```diff
+--[[
+	V10, §4.6 / §C.5. THE STRIKE IS NEVER SAFER THAN BEING KILLED.
+
+	`Items.BuntotPagiStrikeRangeStuds <= Monster.KillRange`. §C.5's exception for shipping a weapon at
+	all rests on four properties, and the third is "it cannot be used to hunt; it can only finish."
+	A strike range above the kill range is the first step out of that: the survivor finishes the
+	monster from outside the distance at which the monster could have answered, and the last beat of
+	the round stops costing anything. Nothing in the game reports this — the strike simply starts
+	landing from further away and feels good.
+]]
+assert(
+	Config.Items.BuntotPagiStrikeRangeStuds <= Config.Monster.KillRange,
+	`StrikeRange={Config.Items.BuntotPagiStrikeRangeStuds} exceeds KillRange={Config.Monster.KillRange}`
+)
+
+--[[
+	AND POSITIVE AND FINITE, for `pure/KillValidation.withinRange`'s reason, which this suite has now
+	pinned for the fifth range in the game. `pure/StrikeValidation` fails closed on a degenerate range
+	— it must, or a Config typo of `-8` maps onto the same 64 and keeps working — so a bad value here
+	produces a buntot pagi that never kills rather than one that kills from across the barrio. That is
+	the safe direction and it is also the SILENT one: §6.5 invariant 1's whole subject is a second win
+	condition that stops existing without a symptom. This assertion is the symptom.
+]]
+assert(
+	Config.Items.BuntotPagiStrikeRangeStuds > 0
+		and Config.Items.BuntotPagiStrikeRangeStuds < math.huge,
+	`StrikeRange={Config.Items.BuntotPagiStrikeRangeStuds} is not positive and finite`
+)
```

Update the suite's closing `print` count if the file carries one, as `config.test.luau` does.

#### Step 1.3: Declare `StrikeVerdict` and retire `USE_NOT_IMPLEMENTED` from `ItemUseVerdict`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

A prefixed `STRIKE_` union mirroring `pure/StrikeValidation`, and `ItemUseVerdict` gains `USE_STRIKE`
and loses the value no item returns any more.

```diff
 export type ItemUseVerdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD" | "USE_PLACE"
+export type ItemUseVerdict = "USE_THROW" | "USE_PLACE" | "USE_STRIKE" | "USE_NOTHING_HELD"
```

`USE_NOT_IMPLEMENTED` is DELETED rather than left as a dead value, and that is the point of the V08/V09
boundary marker rather than a tidy-up. `pure/ItemUse`'s header says the module "is not a feature flag —
there is no config, no toggle and no dead code path behind the unimplemented verb"; keeping the value
after the last item acquires a verb makes it exactly the dead path that header refuses. The analyzer
finds every remaining reader, which is how Step 1.5 knows what to change.

Then, beside `GarlicPlaceVerdict` (currently around line 404):

```diff
+--[[
+	V10, §4.6. Why the server refused — or did not refuse — a `RequestStrike`. Mirrored from
+	`pure/StrikeValidation.Verdict`.
+
+	PREFIXED `STRIKE_`, which is `ItemCarryVerdict`'s rule and `SearchVerdict`'s before it. A sixth
+	union sharing a bare `WRONG_PHASE` spelling makes a handler wired to the wrong path a working
+	program with the wrong meaning.
+
+	IT IS NEVER ECHOED TO A CLIENT, which is `SaltVerdict`'s rule and `KillVerdict`'s — and here it is
+	the WHOLE mechanic rather than a precaution. See `pure/StrikeValidation`'s header: the four
+	target-side worlds are collapsed into ONE value on purpose, so that even a future author who
+	echoed this union by mistake would echo nothing usable. The union is shaped so the leak is
+	unavailable, not merely forbidden.
+
+	FIVE VALUES: a kill, THREE about the striker's own business, and ONE for every world that involves
+	a target. There is no `STRIKE_NOT_EXPOSED`, no `STRIKE_NOT_WEAKENED`, no `STRIKE_NO_TARGET` and no
+	`STRIKE_TARGET_NOT_ALIVE`. Adding any of them reds `tests/strike-validation.test.luau`'s
+	indistinguishability property (Step 4.2), which is where the argument for their absence is
+	enforced rather than remembered.
+
+	THE THREE STRIKER-SIDE VALUES ARE ALLOWED TO DIFFER because they sit ABOVE the spend line and
+	describe facts the striker already holds: their own phase, their own aliveness, their own hand.
+	§1.2 Decision B is the reason that boundary is where it is.
+]]
+export type StrikeVerdict =
+	"STRIKE_KILL"
+	| "STRIKE_WRONG_PHASE"
+	| "STRIKE_NOT_ALIVE"
+	| "STRIKE_NOT_HELD"
+	| "STRIKE_NO_EFFECT"
```

#### Step 1.4: Give the buntot pagi its verb in `pure/ItemUse`

**File:** `src/shared/pure/ItemUse.luau`
**Verify:** `npm run verify:fast`

`verbFor("BUNTOT_PAGI")` returns `"USE_STRIKE"`. This is the line V08 and V09 both pointed at, and
flipping it is what stops the throw handler destroying the round's only win condition on a mis-press.

```diff
 export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
 
-export type Verdict = "USE_THROW" | "USE_PLACE" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
+export type Verdict = "USE_THROW" | "USE_PLACE" | "USE_STRIKE" | "USE_NOTHING_HELD"
```

```diff
 	--[[
-		BUNTOT PAGI (V10), AND IT IS NOW THE ONLY ITEM WITHOUT A VERB. The reason a split between two
-		unimplemented items would have been a roadmap hint has expired with the split — there is one
-		left, and `tests/item-use.test.luau` is where its boundary is written down until V10 moves it.
+		BUNTOT PAGI (V10), §4.6's third verb: a strike that kills an Aswang which is BOTH Exposed and
+		Weakened, and does nothing to anything else. `pure/StrikeValidation` owns the grid; this
+		module owns only which remote the key press belongs to.
+
+		THE UNION LOST `USE_NOT_IMPLEMENTED` WITH THIS LINE, AND THAT IS THE BOUNDARY CLOSING RATHER
+		THAN A CLEANUP. This module's header sells itself as "not a feature flag — no config, no
+		toggle and no dead code path behind the unimplemented verb"; a value no item can return after
+		the last item acquires a verb is exactly the dead path it refuses. Three items, three verbs,
+		and an empty hand. There is no fifth world left for this module to have an opinion about.
+
+		IT IS STILL WHAT STOPS THE THROW HANDLER DESTROYING THE WIN CONDITION. `pure/ItemThrow`
+		collapses a player holding the buntot pagi into MISS — the fifth world, deliberately — and
+		MISS reaches `ItemService`'s spend line. That handler asks this module for `USE_THROW` before
+		spending, so pressing throw with the buntot pagi in hand still costs nothing. What changed is
+		that the same key press now routes to `RequestStrike` instead of being swallowed, which is
+		Step 4.1.
 	]]
-	return "USE_NOT_IMPLEMENTED"
+	return "USE_STRIKE"
 end
```

Nothing else in `src/` reads `USE_NOT_IMPLEMENTED` — `InputController` compares against `USE_PLACE` and
`ItemService`'s throw handler against `USE_THROW`, both positively — so `npm run verify:fast` covers the
whole blast radius. If the analyzer reports a reader this plan did not anticipate, treat it as a finding
and record it in §4 rather than deleting the comparison.

#### Step 1.5: Move the boundary the item-use suite pins

**File:** `tests/item-use.test.luau`
**Verify:** `lune run tests/item-use.test.luau`

The cell asserting `BUNTOT_PAGI -> USE_NOT_IMPLEMENTED` goes red on purpose in Step 1.4 and is replaced
here, which is what V09 did to bawang's cell and what the suite's own header describes.

```diff
-	ItemUse.verbFor("BUNTOT_PAGI") == "USE_NOT_IMPLEMENTED"
+	ItemUse.verbFor("BUNTOT_PAGI") == "USE_STRIKE"
```

The header around line 37 currently reads "V09 IS WHAT THAT LOOKS LIKE WHEN IT GOES RIGHT. Bawang's cell
asserted `USE_NOT_IMPLEMENTED`…". Extend it rather than replacing it — the paragraph is a record of the
convention working twice, and V10 is the third and last time it can:

```diff
+	V10 IS THE LAST TIME. Three items, three verbs; there is no unimplemented cell left to guard and
+	`USE_NOT_IMPLEMENTED` is gone from the union with this commit. What this suite pins from here is
+	the ROUTING — that each item maps to exactly one verb and no two share — which is the property
+	`InputController` and `ItemService`'s throw handler both depend on and neither states.
```

The `ITEMS` list at line 75 and the exhaustiveness loop under it are unchanged: they already iterate all
three, which is why this step is a two-line edit rather than a rewrite. Confirm the loop asserts every
item receives a verb OTHER than `USE_NOTHING_HELD`, and add that assertion if it does not — with
`USE_NOT_IMPLEMENTED` deleted, "every item has a real verb" is a property the union can no longer
express on its own.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing in this phase runs at round time. The one thing to confirm is that
  `Config.luau` gained no per-player number: `BuntotPagiStrikeRangeStuds` is a world constant that
  already replicates alongside `KillRange` and `SaltThrowRange`, so it publishes nothing new.
- **Remote direction** — no remote changes in this phase. `RequestStrike` is Phase 2, Step 2.3.
- **Rate limiting** — the budget entry lands here but the handler does not, so `check:ratelimit` has
  nothing to see yet. `tests/anti-cheat-budgets.test.luau` will go RED at Step 2.3 and green at 3.4;
  that gap is expected and is called out in Phase 2's issues.
- **Magic numbers** — `8` appears only in `Config.luau`. Do not repeat it in the pure module's defaults.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — not reachable from this phase.
- **Strict Luau** — `StrikeVerdict` is a literal union in `Types.luau` and needs no cast at its
  declaration, but any table that stores one does (`.claude/lessons/pure-module-unions-widen-in-lists.md`,
  cited by `pure/ItemUse`'s own if-chain comment). Write branches, not lookup tables.
- **Mobile budget** — no lights, no particles, no per-frame work.
- **Scope** — `BuntotPagi` splits to `Buntot` + `Pagi` under `check:scope`'s word splitter and matches
  neither `weapons?` nor anything else on §3's OUT list (`Enums.luau:42-45` states this is by design).
  `BuntotPagiStrikeRangeStuds` inherits that. Confirm `check:scope` stays green rather than assuming it.

**Issues identified:**

- **`tests/anti-cheat-budgets.test.luau` goes red between Steps 2.3 and 3.4.** Its `UP_REMOTES` list is
  hand-maintained and asserts in BOTH directions ("fails on any budget naming a remote this list does
  not carry"), so declaring the remote without listing it, or budgeting it without declaring it, both
  fail. Step 1.1 adds the budget and Step 2.3 the declaration, so the suite is red from 1.1 until 3.4.
  **`npm run verify` therefore cannot be green mid-phase**, which is why no step before 4.3 uses it.
  If the implementer prefers a green tree at every step, move Step 1.1's budget half into Step 3.4;
  the plan keeps them apart so that every tunable lands in one Config commit.
- **`STRIKE_NO_EFFECT` is a value the SERVER will log and must never echo.** It is not a leak on its
  own — it says nothing about which world produced it — but a `Debug.VerboseLogging` line that printed
  it *beside* a resolved target UserId would be a record of who was standing where, which is the log
  rule `ItemService`'s garlic handler already states ("a UserId and a verdict. NEVER the doorway").
  Phase 3 carries it forward.

---

### Phase 2: The decision — `pure/StrikeValidation` and the grid that proves it

The whole of V10's logic, in one pure module, with an exhaustive Lune grid over it. This is the phase
whose verification is worth the most: every other phase's correctness is a wiring question, and this one
is the mechanic.

#### Step 2.1: Write `pure/StrikeValidation.luau`

**File:** `src/shared/pure/StrikeValidation.luau`
**Verify:** `npm run analyze`

`evaluate(request) -> verdict`. Striker-side refusals are distinct (they sit above the spend line);
every target-side refusal collapses into one `STRIKE_NO_EFFECT`, so the module itself is incapable of
distinguishing empty air from a survivor from a healthy Aswang.

```diff
+--!strict
+--[[
+	StrikeValidation — may this swing kill, and if not, may the striker learn why not. (§4.6, V10)
+
+		(request) -> verdict
+
+	§4.6: the buntot pagi "kills only an Aswang that is both Exposed (glowing from a salt hit) and
+	Weakened (at or below 25 health). Against anything else it does nothing." Both halves of that
+	sentence are mechanics and the SECOND one is the harder to build. "Does nothing" has to mean
+	nothing observable, and this module is where that is made structural rather than careful.
+
+	THE VERDICT UNION IS THE DESIGN. Four worlds involve a target — there is nobody in reach, the
+	nearest reachable player is a survivor, the Aswang is in reach but not Exposed, the Aswang is
+	Exposed but not Weakened — and this module CANNOT TELL THEM APART. They are one value,
+	`STRIKE_NO_EFFECT`, and there is no arrangement of the code that recovers which. That is
+	`pure/ItemThrow`'s "fifth world, collapsed into MISS deliberately" applied to a sharper case:
+	salt's collapse protects a role, this one protects a role AND a health value AND a position.
+
+	THE THREE STRIKER-SIDE VERDICTS ARE ALLOWED TO DIFFER, and where the line falls is the whole
+	decision. WRONG_PHASE, NOT_ALIVE and NOT_HELD are facts about the requester that the requester
+	already holds — its own phase off the snapshot, its own aliveness, its own hand. Nothing below
+	them may differ, because everything below them is a fact about somebody else.
+
+	IT TAKES TWO BOOLEANS, NOT A HEALTH VALUE AND NOT A `MonsterState` == "EXPOSED" TEST, AND BOTH
+	ARE CORRECTIONS TO THE OBVIOUS SIGNATURE:
+
+	  · `MonsterService.monsterStateOf` NEVER RETURNS `EXPOSED`. It produces CAMOUFLAGED, FEEDING,
+	    TRANSFORMED and NORMAL, and its header says why: "EXPOSED IS A LATCH, NOT AN ACTIVITY… a
+	    salted Aswang is Exposed AND still an Aswang." A module gating on the state enum would refuse
+	    every cell of the grid forever, and the symptom would be that the second win condition
+	    silently does not exist — §6.5 invariant 1's exact failure mode. So the gate is the LATCH,
+	    read through `MonsterService.IsExposed`.
+	  · `Weakened` IS A HEALTH PREDICATE, NOT A STATE. `Enums.luau` refuses to make it a
+	    `MonsterState` member because "duplicating it as an enum member is how two sources of truth
+	    for one fact get out of step." `MonsterService.IsWeakened` is the one source, and it is
+	    already documented there as "V08's strike gate, half two."
+
+	THE HEALTH NUMBER DELIBERATELY DOES NOT APPEAR IN THIS SIGNATURE. Passing it would typecheck and
+	would leak nothing through the pure layer — a client cannot supply it — but it would force
+	`ItemService` to hold the Aswang's health in a local at the call site, and `MonsterService`'s
+	header is explicit that none of its seams "returns the health value." A number living in a second
+	service's local is where a log line, a verbose print or a payload field grows.
+
+	THE ROLE IS NOT A FIELD EITHER, AND IT DOES NOT NEED TO BE — which is a real improvement on
+	`pure/KillValidation`, whose header has to warn that "TARGET_IS_ASWANG is a role oracle in one
+	word." Only the Aswang has monster state, so only the Aswang can be Exposed or Weakened; both
+	booleans are false for every survivor, every round. `Exposed AND Weakened` therefore IMPLIES the
+	role rather than asking about it, and there is no value in this union that names one.
+
+	IT LIVES IN `src/shared/pure/`, AND THAT IS CLAUDE.md'S TEST APPLIED RATHER THAN ASSUMED. There is
+	no seed and no client-suppliable input: both booleans come off a server-only table, the distance
+	is measured between the server's copies of two characters, the phase is `RoundService.GetPhase()`
+	and `Held` is the server's own slot. A client that requires and runs this learns the RULE — which
+	§4.6 states, §9.1's tutorial teaches and one round of play demonstrates — and cannot supply the
+	arguments that would make it answer anything about a real player. Same test `KillValidation` and
+	`MonsterHealth` both passed; `server/pure/ContainerLayout` is what failing it looks like.
+
+	NO Vector3, FOR `KillValidation`'S REASON: Lune has no Roblox datatypes, so a Vector3 here fails
+	at TEST time rather than at typecheck time. The caller passes a scalar distance it has already
+	measured — this module does no geometry beyond comparing that scalar to a range.
+
+	NO `script.Parent` REQUIRES. Every union is re-declared; Luau unions are structural.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
+export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
+
+export type Verdict =
+	"STRIKE_KILL"
+	| "STRIKE_WRONG_PHASE"
+	| "STRIKE_NOT_ALIVE"
+	| "STRIKE_NOT_HELD"
+	| "STRIKE_NO_EFFECT"
+
+export type Request = {
+	Phase: RoundPhase,
+	-- The STRIKER's own three facts. Everything above the spend line.
+	StrikerState: PlayerState,
+	Held: ItemType?,
+	--[[
+		THE TARGET, AS FOUR OPTIONAL FACTS, AND `nil` MEANS "THE SERVER RESOLVED NOBODY".
+
+		`GarlicPlacement.DoorwayDistance`'s convention exactly: nil is a different world from "there
+		is one and it is out of reach", the two land on the same verdict because nothing is echoed
+		either way, and the SERVER logs which by looking at its own lookup.
+	]]
+	TargetDistance: number?,
+	--[[
+		CARRIED AND ALMOST NEVER READ, WHICH IS DELIBERATE AND HAS EXACTLY ONE JOB.
+
+		`nil` means the target has no monster state at all — which is every survivor, every round, and
+		is how "you swung at a teammate" enters the grid as a value rather than as an absence. The
+		five non-nil members are NOT a gate: §4.6 gates on Exposed AND Weakened and says nothing about
+		the form, so a Weakened, Exposed Aswang dies whether it is TRANSFORMED, CAMOUFLAGED or
+		FEEDING. Feeding is the intended case — §4.3 built that window for this item.
+
+		IT IS IN THE REQUEST SO THE GRID CAN BE LITERAL. `tests/strike-validation.test.luau` asserts
+		the verdict is INVARIANT across all five states for a fixed pair of booleans, which is a
+		property a future author cannot break by accident without turning a test red. Without the
+		field the property is unstateable and "the form does not matter" is a sentence in a comment.
+	]]
+	TargetState: MonsterState?,
+	TargetPlayerState: PlayerState?,
+	-- From `MonsterService.IsExposed` / `IsWeakened`. False for anyone with no monster state.
+	TargetExposed: boolean,
+	TargetWeakened: boolean,
+	Range: number,
+}
+
+local StrikeValidation = {}
+
+--[[
+	FAIL CLOSED ON A DEGENERATE RANGE — `pure/KillValidation.withinRange`'s guard, fourth use in this
+	repo, and written as one negated conjunction for the identical NaN reason. `NaN > 0` and
+	`NaN < math.huge` are both false, so the conjunction is false and the negation refuses; written
+	the other way round every NaN comparison is false and NaN sails through.
+
+	THE FAILURE DIRECTION IS THE POINT AND IT IS THE OPPOSITE OF THE KILL'S. A degenerate range on a
+	kill grants a monster free kills; a degenerate range here produces a buntot pagi that never kills,
+	which is the SILENT failure §6.5 invariant 1 exists to describe. `tests/config.test.luau` is the
+	loud half; this is the second line of defence, and it refuses rather than granting because a
+	strike that lands from `math.huge` studs is strictly worse than one that never lands.
+
+	A NaN DISTANCE ALSO REFUSES, for free: `NaN <= range` is false.
+]]
+local function withinRange(distance: number?, range: number): boolean
+	if distance == nil then
+		return false
+	end
+
+	if not (range > 0 and range < math.huge) then
+		return false
+	end
+
+	-- `<=`: §4.6 gives a reach, and a striker standing at exactly the reach is within it. Matches
+	-- `KillValidation.withinRange`, which the config invariant compares this range against.
+	return distance <= range
+end
+
+--[[
+	THE ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in `KillValidation`, `ItemCarry`,
+	`ItemDrop`, `ItemThrow` and `GarlicPlacement`: world facts, then the striker, then the slot, then
+	everything about the target.
+
+	THE BOUNDARY BETWEEN THE THIRD AND FOURTH GROUPS IS THE SPEND LINE, and it is the most important
+	line in this chunk. `ItemService`'s handler spends the slot for every verdict BELOW `STRIKE_NOT_HELD`
+	— including `STRIKE_NO_EFFECT` — and for none above it. §4.6 says "it breaks on use" and a swing is
+	a use; the competing reading is refused on SECRECY grounds, not balance ones.
+
+	WHY, IN ONE PARAGRAPH, BECAUSE THIS IS THE SENTENCE A LATER AUTHOR WILL WANT TO UNDO.
+	`ClientRoundSnapshot.YourCarriedItem` is pushed to every client every `Round.SnapshotInterval`, so
+	whether the item survived a swing is readable off the striker's OWN HUD. A spend conditional on the
+	kill therefore turns the buntot pagi into a reusable detector: swing at each player in turn, watch
+	your slot, and the swing that costs nothing has named the Aswang and reported that it is not yet
+	Weakened. `ItemService`'s throw handler already refuses the same trade for salt — "a miss that cost
+	nothing would make salt a probe you throw at everyone" — and there is exactly ONE buntot pagi and it
+	IS the second win condition.
+
+	SO THE FOUR TARGET-SIDE WORLDS COLLAPSE HERE, AND NOT IN THE CALLER. A service that mapped four
+	verdicts onto one silent return would be correct today and one careless log line from being an
+	oracle tomorrow. Collapsing in the module means the information is not merely unsent — it was never
+	computed.
+]]
+function StrikeValidation.evaluate(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "STRIKE_WRONG_PHASE"
+	end
+
+	-- AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`, for `pure/PlayerBody`'s reason and `ItemDrop`'s.
+	-- A DEAD striker must not swing: the death path already spilled the item where they fell (§4.6),
+	-- so a dead striker who could still swing would be swinging something they no longer hold.
+	if request.StrikerState ~= "ALIVE" then
+		return "STRIKE_NOT_ALIVE"
+	end
+
+	if request.Held ~= "BUNTOT_PAGI" then
+		return "STRIKE_NOT_HELD"
+	end
+
+	------------------------------------------------------------------------
+	-- THE SPEND LINE. Everything below here returns one of two values.
+	------------------------------------------------------------------------
+
+	if not withinRange(request.TargetDistance, request.Range) then
+		return "STRIKE_NO_EFFECT"
+	end
+
+	-- A target with no monster state is a survivor. Not a separate verdict, and not a separate
+	-- BRANCH from the two below it in any observable sense — the three are one world.
+	if request.TargetState == nil then
+		return "STRIKE_NO_EFFECT"
+	end
+
+	-- The Aswang must be alive to be killed. Unreachable today (a dead Aswang ends the round) and
+	-- kept for `KillValidation.TARGET_IS_ASWANG`'s reason: the day something else changes, the
+	-- failure must be "the strike does nothing", not "the corpse can be struck again".
+	if request.TargetPlayerState ~= "ALIVE" then
+		return "STRIKE_NO_EFFECT"
+	end
+
+	--[[
+		§4.6, AND BOTH ARE REQUIRED. Written as one condition rather than two branches SO THAT THERE
+		IS NO PLACE TO PUT A DIFFERENT RETURN. Two `if`s with two bodies is the shape a future author
+		fills in with `STRIKE_NOT_WEAKENED` on an afternoon when the spec is not open; one condition
+		with one body has nowhere to put it.
+	]]
+	if not (request.TargetExposed and request.TargetWeakened) then
+		return "STRIKE_NO_EFFECT"
+	end
+
+	return "STRIKE_KILL"
+end
+
+return StrikeValidation
```

**On the `TargetState == nil` branch reading as redundant.** It is: a survivor has both booleans false,
so the Exposed/Weakened condition would refuse them anyway. It is written because the field exists to
make the grid literal (see its comment), and a field the function never reads is a field the analyzer
cannot tell from a mistake. Keep it, and keep it above the boolean gate so the reading order matches the
grid's.

#### Step 2.2: The exhaustive grid — `tests/strike-validation.test.luau`

**File:** `tests/strike-validation.test.luau`
**Verify:** `lune run tests/strike-validation.test.luau`

Every cell of state × exposed × weakened × target-alive × distance × phase × striker-state × held,
asserting `STRIKE_KILL` in exactly the cells where the striker is entitled and the target is both, and a
refusal everywhere else. Plus the fail-closed boundary cases the range guard exists for.

```diff
+--!strict
+--[[
+	tests/strike-validation.test.luau — the two-condition grid, exhaustively. (V10, §4.6)
+
+	`docs/BUILD-PLAN.md`'s V10 Verify line asks for exactly this: "over state × health × distance ×
+	phase, asserting every non-Exposed-or-non-Weakened cell is a refusal." The grid below is that
+	product plus the striker's own three facts, because the spend line runs between the two groups and
+	a test that only covered the target half would prove the mechanic and miss the exploit.
+
+	IT IS A PRODUCT RATHER THAN A LIST OF CASES, for `tests/kill-validation.test.luau`'s reason: a
+	hand-written case list grows a hole every time the union does, and nothing reports it.
+]]
+
+local StrikeValidation = require("../src/shared/pure/StrikeValidation")
+
+local PHASES: { StrikeValidation.RoundPhase } =
+	{ "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
+local PLAYER_STATES: { StrikeValidation.PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }
+local HELD: { StrikeValidation.ItemType? } = { nil, "SALT", "BAWANG", "BUNTOT_PAGI" }
+local MONSTER_STATES: { StrikeValidation.MonsterState? } =
+	{ nil, "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
+local BOOLS: { boolean } = { false, true }
+-- Inside, exactly at the boundary, outside, and absent. `RANGE` matches nothing in Config on purpose:
+-- this suite proves the RULE, and `tests/config.test.luau` proves the number.
+local RANGE = 8
+local DISTANCES: { number? } = { nil, 0, 4, RANGE, RANGE + 0.001, 40 }
+
+--[[
+	A `{ ItemType? }` LIST CANNOT HOLD A LEADING nil IN LUAU AND HAVE `#` SEE IT. Build the held and
+	distance and monster-state axes with an explicit count rather than `#list`, or the nil cell — which
+	is "empty hand" and "nobody in reach" and "not the monster", the three most important cells in this
+	file — is silently never tested. Use `table.pack`-style explicit lengths or iterate `1, N` with N
+	written down.
+]]
+local HELD_N, MONSTER_N, DIST_N = 4, 6, 6
+
+local checked = 0
+
+local function expected(
+	phase: StrikeValidation.RoundPhase,
+	strikerState: StrikeValidation.PlayerState,
+	held: StrikeValidation.ItemType?,
+	distance: number?,
+	targetState: StrikeValidation.MonsterState?,
+	targetPlayerState: StrikeValidation.PlayerState?,
+	exposed: boolean,
+	weakened: boolean
+): StrikeValidation.Verdict
+	-- A SECOND, INDEPENDENT STATEMENT OF THE RULE, in the order the module fixes. Written out rather
+	-- than calling the module, or the test proves only that the module equals itself.
+	if phase ~= "ACTIVE" then
+		return "STRIKE_WRONG_PHASE"
+	end
+	if strikerState ~= "ALIVE" then
+		return "STRIKE_NOT_ALIVE"
+	end
+	if held ~= "BUNTOT_PAGI" then
+		return "STRIKE_NOT_HELD"
+	end
+	if distance == nil or distance > RANGE then
+		return "STRIKE_NO_EFFECT"
+	end
+	if targetState == nil or targetPlayerState ~= "ALIVE" then
+		return "STRIKE_NO_EFFECT"
+	end
+	if not (exposed and weakened) then
+		return "STRIKE_NO_EFFECT"
+	end
+	return "STRIKE_KILL"
+end
+
+for _, phase in PHASES do
+	for _, strikerState in PLAYER_STATES do
+		for h = 1, HELD_N do
+			local held = HELD[h]
+			for d = 1, DIST_N do
+				local distance = DISTANCES[d]
+				for m = 1, MONSTER_N do
+					local targetState = MONSTER_STATES[m]
+					for _, targetPlayerState in PLAYER_STATES do
+						for _, exposed in BOOLS do
+							for _, weakened in BOOLS do
+								local verdict = StrikeValidation.evaluate({
+									Phase = phase,
+									StrikerState = strikerState,
+									Held = held,
+									TargetDistance = distance,
+									TargetState = targetState,
+									TargetPlayerState = targetPlayerState,
+									TargetExposed = exposed,
+									TargetWeakened = weakened,
+									Range = RANGE,
+								})
+
+								local want = expected(
+									phase,
+									strikerState,
+									held,
+									distance,
+									targetState,
+									targetPlayerState,
+									exposed,
+									weakened
+								)
+
+								assert(
+									verdict == want,
+									`{phase}/{strikerState}/{held}/{distance}/{targetState}/`
+										.. `{targetPlayerState}/exposed={exposed}/weakened={weakened}: `
+										.. `got {verdict}, want {want}`
+								)
+
+								--[[
+									THE DONE LINE'S OWN SENTENCE, ASSERTED SEPARATELY FROM THE TABLE
+									ABOVE. "Kills ONLY if Exposed AND Weakened" is a claim about the
+									whole product, not about one cell, and stating it here means a
+									future edit to `expected` cannot quietly widen it.
+								]]
+								if verdict == "STRIKE_KILL" then
+									assert(
+										exposed and weakened,
+										`STRIKE_KILL with exposed={exposed} weakened={weakened}`
+									)
+								end
+
+								checked += 1
+							end
+						end
+					end
+				end
+			end
+		end
+	end
+end
+
+--[[
+	THE FAIL-CLOSED RANGE CASES, WHICH THE PRODUCT ABOVE CANNOT REACH because it holds `Range` fixed.
+
+	`pure/KillValidation`'s header records that this guard took three attempts and that the first two
+	both SHIPPED — a negative range mapping onto the same square, and an infinite one sailing past a
+	`> 0` test. This module compares scalars rather than squares so the negative case differs, but the
+	infinity and NaN cases are identical and are the reason the guard is a negated conjunction.
+
+	EVERY ONE MUST REFUSE. A degenerate range that GRANTED would let a Config typo kill the Aswang
+	from across the barrio; one that refuses produces a buntot pagi that never kills, which
+	`tests/config.test.luau` reports loudly.
+]]
+for _, badRange in { 0, -8, math.huge, 0 / 0 } do
+	assert(
+		StrikeValidation.evaluate({
+			Phase = "ACTIVE",
+			StrikerState = "ALIVE",
+			Held = "BUNTOT_PAGI",
+			TargetDistance = 1,
+			TargetState = "TRANSFORMED",
+			TargetPlayerState = "ALIVE",
+			TargetExposed = true,
+			TargetWeakened = true,
+			Range = badRange,
+		}) == "STRIKE_NO_EFFECT",
+		`a range of {badRange} granted a strike`
+	)
+	checked += 1
+end
+
+-- A NaN DISTANCE, which `<=` answers false for and which no Config value produces — the distance is
+-- measured from two live positions, and a character mid-teleport can hand `.Magnitude` a NaN.
+assert(
+	StrikeValidation.evaluate({
+		Phase = "ACTIVE",
+		StrikerState = "ALIVE",
+		Held = "BUNTOT_PAGI",
+		TargetDistance = 0 / 0,
+		TargetState = "TRANSFORMED",
+		TargetPlayerState = "ALIVE",
+		TargetExposed = true,
+		TargetWeakened = true,
+		Range = RANGE,
+	}) == "STRIKE_NO_EFFECT",
+	"a NaN distance granted a strike"
+)
+
+print(`  PASS  strike-validation: {checked} cells`)
```

The product is 5 × 4 × 4 × 6 × 6 × 4 × 2 × 2 = **46,080 cells**, which Lune runs in well under a second.
If that proves slow on the implementer's machine, drop `PLAYER_STATES` on the target axis to
`{ "ALIVE", "DEAD" }` (7,680 cells) rather than dropping an axis that carries a secrecy property —
`MONSTER_STATES` and the two booleans are the grid the Done line names.

#### Step 2.3: Declare `RequestStrike` in `Remotes.luau`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

In `EVENTS_UP`, argument-free, with the header stating Decision A in full. Nothing is added to
`EVENTS_DOWN`.

```diff
 	"RequestPlaceGarlic",
+	--[[
+		V10, §4.6. NO ARGUMENTS, and the absent argument is the entire security design — the fifth
+		remote in this list to say so, and the one where it matters most.
+
+		THE TARGET IS NOT NAMED BY THE CLIENT. The server resolves the candidate within
+		`Config.Items.BuntotPagiStrikeRangeStuds` of the striker's OWN character position, through its
+		own line-of-sight raycast (`MonsterService.ResolveStrikeTarget`) — the rule `RequestSearch`
+		states in full and `RequestCamouflage`, `RequestDropItem` and `RequestPlaceGarlic` each
+		restate: the server resolves what a player is standing at from that player's own character
+		position, and the client names nothing.
+
+		A `RequestStrike(targetUserId)` WOULD HAVE BEEN THE SHARPEST PROBE IN THE GAME, and sharper
+		than the two this list already refuses. `RequestPlaceGarlic(doorway)` would leak a map;
+		`RequestCamouflage(form)` would leak an ambient population. A target argument here leaks a
+		PERSON: it lets a compromised client aim at ONE NAMED PLAYER and observe whether that player
+		died — an oracle whose answer is "yes" for exactly one of the five and "no" for the rest.
+		With no argument the only question a client can ask is "is there something killable within
+		arm's reach of me", and the answer to that is a monster falling over in the open, which every
+		client with line of sight was going to see anyway. The question is unaskable, not merely
+		unanswered.
+
+		NOR IS THERE AN ITEM ARGUMENT, for `RequestDropItem`'s reason: `Config.Items.CarryLimit` is 1,
+		so there is exactly one thing a player can be holding and the server already knows what it is.
+		And no direction — a strike is resolved from a position, not aimed, so the camera's
+		`LookVector` stops at `InputController`'s branch.
+
+		NOTHING IS RETURNED TO THE CALLER ON ANY PATH, INCLUDING A KILL, and this remote is where that
+		convention stops being politeness. `pure/StrikeValidation` collapses all four target-side
+		worlds into one verdict, so there is nothing meaningful left to echo — but the reason the
+		SERVER stays silent even on `STRIKE_KILL` is that a kill acknowledgement is a timestamp. The
+		striker learns they killed the monster by watching it fall over, at the same moment as
+		everyone else with line of sight.
+
+		AND NO DOWNWARD REMOTE ACCOMPANIES IT. There is no `StrikeEffect` to match `SaltEffect`. The
+		public half of a strike needs no remote at all: the monster's death replicates as geometry and
+		as the round ending. What the swing DOES emit is a `NoiseCue` of `ITEM_USE` from the striker's
+		own position, on every swing that reaches the spend line, hit or miss — §4.4's rule and the
+		salt throw's, for `.claude/lessons/absence-is-observable.md`'s reason: an item use that made
+		no sound would be the only silent one in the game, and a listener who heard nothing would
+		learn which item was used.
+
+		IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching and carrying on
+		identical rules, so the monster can hold the buntot pagi and fire this remote exactly as a
+		survivor can, and must — see `Types.ClientRoundSnapshot.YourCarriedItem`. Its swing resolves
+		against itself, finds `IsExposed`/`IsWeakened` about its own state, and spends the item. That
+		is correct, and it is the case that keeps an unused buntot pagi from being a tell.
+	]]
+	"RequestStrike",
 }
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — `pure/StrikeValidation` is `require`-able and *callable* by any client, since
  `default.project.json` maps `src/shared` wholesale into `ReplicatedStorage`. Confirm the module has
  no seed, no `os.time()`, no `Random.new(...)` and no input a client holds. §1.4 is the argument;
  re-check it against the file that actually landed rather than against the plan.
- **Remote direction** — `RequestStrike` in `EVENTS_UP` only. `check:remotes` fails if it is fired from
  the server or listened to on the client.
- **Rate limiting** — no handler exists yet, so `check:ratelimit` is green vacuously. It becomes a real
  check at Step 3.3.
- **Magic numbers** — `RANGE = 8` inside the test file is a fixture, not a tunable; `check:config`
  scans `src/` and does not see `tests/`. Do NOT let it appear in the pure module.
- **Phase ownership** — the module *reads* the phase and never sets it.
- **Player leaving mid-round** — the module has no notion of a player at all. The disconnect case is
  Phase 3's, through the existing `spillItem`.
- **Strict Luau** — the `{ ItemType? }` and `{ MonsterState? }` axes will widen to `{ string }` unless
  annotated at the declaration; `.claude/lessons/pure-module-unions-widen-in-lists.md` and
  `pure/ItemUse`'s if-chain comment both record this. Annotate the locals.
- **Mobile budget** — nothing new renders.
- **Scope** — no OUT-list token; see Phase 1.

**Issues identified:**

- **A leading `nil` in a Luau list is invisible to `#`.** Three of this suite's axes have a `nil` cell
  and all three are the cells that matter most — empty hand, nobody in reach, target is not the monster.
  Iterating `for _, x in LIST` skips them silently and the suite still prints PASS. The plan writes
  explicit counts (`HELD_N`, `MONSTER_N`, `DIST_N`) for exactly this; if the implementer prefers
  `table.pack`, keep the property, not the idiom. **Sanity-check the printed cell count against the
  46,080 the plan computes** — a count of 30,720 means an axis lost its nil.
- **`tests/anti-cheat-budgets.test.luau` is red from Step 1.1 through Step 3.4.** Carried forward from
  Phase 1. This phase's Step 2.3 is the second half of the cause; it clears at 3.4.
- **The `expected` helper duplicates the rule and that is intentional.** An auditor may flag it as
  redundancy. It is not: a test that calls the module to compute its own expectation proves the module
  equals itself. `tests/kill-validation.test.luau` makes the same choice.

---

### Phase 3: The server — one resolver, one kill path, one handler that spends

`MonsterService` gains the two things only it can do (resolve a candidate through its own raycast, and
take the monster apart) and `ItemService` gains the remote and the spend, which is exactly how
`RequestThrowSalt` and `ApplySaltHit` already divide.

#### Step 3.1: `MonsterService.ResolveStrikeTarget(striker, range)` — the candidate, server-side

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

Returns the Aswang's UserId and its distance, or nil, having applied the same `hasLineOfSight` the kill
uses. The client names nobody; this function is the whole of how a target is chosen.

Add beside `IsExposed` (currently around line 3126), in the seam section `IsTransformed`, `IsWeakened`
and `SmokeBlocks` already occupy:

```diff
+--[[
+	WHO, IF ANYONE, IS THIS STRIKE ABOUT? (V10, §4.6) `ItemService`'s only way to name a target.
+
+	Returns the candidate's UserId and its distance, or `nil, nil`. `pure/GarlicPlacement`'s
+	`DoorwayDistance` convention: the caller gets a distance because the pure module wants one, and
+	the service gets the identity because it needs to ask `IsExposed`/`IsWeakened` about it — and
+	computing the distance twice is how the two come to disagree.
+
+	IT RESOLVES EXACTLY ONE CANDIDATE, AND THAT CANDIDATE IS THE ASWANG. Not "the nearest player."
+	The difference is worth stating because "nearest" is the obvious implementation and it is worse in
+	both directions: a survivor standing between the striker and the monster would BLOCK a strike that
+	§4.6 says should land, and a striker could learn something from being blocked. Resolving the one
+	player the strike could ever be about, and then asking the pure module whether it may land, means
+	the crowd is irrelevant and there is nothing to infer from it.
+
+	IT LIVES HERE RATHER THAN IN `ItemService` FOR TWO REASONS, AND THE SECOND IS THE ONE THAT DECIDES.
+	`RoundService.GetAswangUserId()` is reachable from both. But `hasLineOfSight` is a file-local in
+	THIS file, and it is not a raycast with a filter — it excludes the corpse folder AND the husk
+	folder AND both characters, and it consults `smokeBlocksSegment` first. Every one of those
+	exclusions is a rule somebody was bitten by (a body is not cover; two alts do not make a safe
+	room; smoke breaks it symmetrically). Reimplementing the ray in `ItemService` would be a second
+	copy that starts correct and drifts, on the surface where drift is an exploit.
+
+	IT NEVER ENUMERATES AND IT IS NOT A ROLE ORACLE, on `IsTransformed`'s terms: it is SERVER ONLY,
+	the return value crosses no wire, and `ItemService` hands the UserId straight back into
+	`IsExposed`/`IsWeakened` and then into a pure module that has no role field. The role is resolved
+	once, here, and never travels.
+
+	NIL FOR NO CHARACTER, NOT (0,0,0) — `nearestDoorway`'s rule. A player with no root has no position,
+	and the origin is a place in the barrio somebody can stand.
+
+	THE ASWANG STRIKING ITSELF RESOLVES TO ITSELF AND THAT IS DELIBERATE. Distance 0, line of sight
+	trivially true, and `pure/StrikeValidation` then answers on its Exposed/Weakened state exactly as
+	it would for a survivor's swing. A guard here would make the monster's own buntot pagi behave
+	differently from everybody's, which is a role oracle readable by pressing a key. If the Aswang
+	wants to salt itself three times and then kill itself, §4.6 does not forbid it and V11 will score
+	it; the item was spent either way.
+]]
+function MonsterService.ResolveStrikeTarget(striker: Player, range: number): (number?, number?)
+	local aswangUserId = RoundService.GetAswangUserId()
+
+	if aswangUserId == nil then
+		return nil, nil
+	end
+
+	local target = Players:GetPlayerByUserId(aswangUserId)
+	local strikerCharacter = striker.Character
+	local targetCharacter = if target ~= nil then target.Character else nil
+
+	if strikerCharacter == nil or targetCharacter == nil then
+		return nil, nil
+	end
+
+	local strikerRoot = rootOf(strikerCharacter)
+	local targetRoot = rootOf(targetCharacter)
+
+	if strikerRoot == nil or targetRoot == nil then
+		return nil, nil
+	end
+
+	local distance = (strikerRoot.Position - targetRoot.Position).Magnitude
+
+	--[[
+		THE RANGE TEST HAPPENS TWICE, HERE AND IN THE PURE MODULE, AND THAT IS NOT REDUNDANCY.
+		This one gates the RAYCAST — the only expensive thing in the path — so an unauthorised spam
+		of `RequestStrike` costs a subtraction rather than a physics query. `KillValidation`'s
+		handler makes the identical trade for the identical reason ("LAST, because it is the only
+		check that touches the physics engine").
+	]]
+	if distance > range then
+		return nil, nil
+	end
+
+	if not hasLineOfSight(strikerRoot, targetRoot) then
+		return nil, nil
+	end
+
+	return aswangUserId, distance
+end
```

`hasLineOfSight` is declared around line 1931 and `ResolveStrikeTarget` lands around line 3126, so the
forward reference resolves. `rootOf` (line 1413) and `Players` are both already in scope.

**A note on the returned distance and the pure module's second range test.** `ResolveStrikeTarget`
returns `nil` when the target is out of range, so `pure/StrikeValidation` will see `TargetDistance = nil`
and answer `STRIKE_NO_EFFECT` through its nil branch rather than through its comparison. Both paths
produce the same verdict, which is the point — but do NOT delete the module's range test on the grounds
that the service already made it. The module is what the Lune grid proves, and a rule proven only in a
service is a rule proven nowhere.

#### Step 3.2: `MonsterService.StrikeDown(userId)` — taking the monster apart before it dies

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

End the feed, exit camouflage, revert, clear the Exposed glow, then `RoundService.MarkKilled`. The
ordering is the C04 lesson: a Highlight or a scale left on a body is a permanent, map-wide brand.

Add beside `ApplySaltHit` (currently around line 3024), which is the seam this one is modelled on:

```diff
+--[[
+	THE ASWANG DIES (V10, §4.6). The ONLY entry point, and the ordering below is the whole function.
+
+	§4.6: the buntot pagi is "the only thing that kills." `ItemService` decides WHETHER — it owns the
+	slot, the remote and `pure/StrikeValidation` — and this owns WHAT HAPPENS, exactly as
+	`RequestThrowSalt` decides a hit and `ApplySaltHit` performs one. Returns whether monster state
+	existed, never anything about it, on `HealFromFeed`'s terms.
+
+	V10 ENDS AT "THE MONSTER IS DEAD" AND SAYS NOTHING ABOUT WHAT THAT MEANS FOR THE ROUND.
+	`RoundService.MarkKilled` currently routes an Aswang death to `RoundResult.Aborted`, on the
+	disconnect path's reasoning. For a STRIKE that is the wrong result — the survivors did not abort,
+	they won the second win condition — and V11 owns replacing it. Do not change `RoundResult` here:
+	§6.5's six invariants and the roster-freeze rule land together in that chunk, and a result changed
+	without them is a win condition nobody pinned. See this plan's §4.
+
+	`causedByKill = false`, DELIBERATELY. That flag increments `state.AswangKills`, which is the
+	ASWANG's progress toward ITS win. A survivor killing the monster must not advance the monster's
+	counter, and `MarkKilled`'s own comment is right that "a departure simply is not a kill" — neither
+	is this.
+
+	THE FOUR TEARDOWNS RUN BEFORE THE DEATH, AND THE ORDER IS THE C04 LESSON RESTATED. Every one of
+	them removes a REPLICATED difference from a character that is about to become a body somebody can
+	walk up to and inspect:
+
+	  1. `endFeed` — releases `WalkSpeed = 0`, which is "THE ONE REPLICATED DIFFERENCE A FEED CREATES"
+	     per this file's own header, and fires no FeedUpdate on this path (the interrupted verdict is
+	     correct: the feed did not complete).
+	  2. `exitCamouflage` — restores the character and releases the ambient slot. A monster struck
+	     while wearing a pig would otherwise leave the pig standing and the slot claimed for the rest
+	     of the round, which `enterCamouflage`'s comment already names as a leak.
+	  3. `revert` — restores the captured look. C04's bug was a revert that restored HARDCODED
+	     DEFAULTS instead of captured state, permanently branding the ex-Aswang; `restoreLook` is the
+	     repaired path and this must use it rather than reimplementing a reset.
+	  4. `clearExposed` — destroys the Highlight and clears the boolean TOGETHER, which is the
+	     invariant that function's header states. A glow orphaned onto a corpse is a permanent,
+	     map-wide, remote-free answer to "which body was the monster" — readable after the round by
+	     anyone who did not watch it die.
+
+	`endFeed` ALREADY CALLS `revert`, so step 3 is a no-op when the monster was feeding. It is written
+	unconditionally anyway: the common strike case is a monster that was salted and is NOT feeding,
+	and `revert` early-returns for a monster that is not transformed. Two safe no-ops are cheaper than
+	one caller having to know which of the six feed-exit paths it is on.
+]]
+function MonsterService.StrikeDown(userId: number): boolean
+	local monster: MonsterState? = monsters[userId]
+
+	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId — the bug
+	-- `revert()`'s first line and `applyHealthEvent`'s first line were both written to avoid.
+	if monster == nil then
+		return false
+	end
+
+	local player = Players:GetPlayerByUserId(userId)
+
+	if player == nil then
+		return false
+	end
+
+	endFeed(userId, Enums.FeedVerdict.Interrupted)
+	exitCamouflage(player)
+	revert(player)
+	clearExposed(userId)
+
+	RoundService.MarkKilled(player, false)
+
+	return true
+end
```

Confirm at implementation time that `Enums.FeedVerdict.Interrupted` is the correct spelling — `endFeed`'s
signature takes `Types.FeedVerdict?` and the six existing callers pass either that value or `nil`. Match
whichever the interruption paths already use; **do not pass `nil`**, which is reserved for `completeFeed`
and would leave the feeder with no message at all.

**The one thing this function must NOT do is destroy the character or make a corpse.** `commitKill` does
that for a survivor (`player.Character = nil`, then `makeCorpse`) and V12 owns what body a dead Aswang
leaves. `MarkKilled` calls `applyBodyRule(player, "KILLED")`, which answers KEEP today, so the Aswang's
own avatar stays where it fell — which is both the correct v2.0 behaviour and the one that needs no new
code. Verify by eye that no branch of `applyBodyRule` deletes it.

#### Step 3.3: The `RequestStrike` handler in `ItemService`

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:ratelimit`

AntiCheat first and inline; the pure module second; the spend third and unconditional; the noise cue
fourth; `StrikeDown` last. Nothing is returned to the caller on any path, including a kill.

Add in `ItemService.Start`, after the `RequestPlaceGarlic` handler (currently ends around line 1558) and
before the `RequestThrowSalt` one. Requires `StrikeValidation` at the top of the file beside the other
pure requires:

```diff
+	--[[
+		V10, §4.6. SWING THE BUNTOT PAGI.
+
+		THE RATE LIMIT IS INLINE AND FIRST, copying the throw, drop and garlic handlers exactly.
+		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
+		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire —
+		so a handler that IS limited but does it elsewhere reads as unguarded and fails the build.
+		Consume FIRST, before anything is read.
+
+		THERE IS NO ARGUMENT TO VALIDATE. See the declaration in `Remotes.luau`: the target is
+		resolved from the striker's own character position through `MonsterService.ResolveStrikeTarget`
+		and the item from this service's own slot. A `typeof()` guard like the throw handler's has
+		nothing to guard.
+
+		THE ORDER OF THE FIVE THINGS BELOW IS THE ENTIRE SECURITY DESIGN OF THIS CHUNK, and the spend
+		line is where it turns. Read §4.6 twice before reordering it.
+	]]
+	Remotes.Get("RequestStrike").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestStrike") then
+			return
+		end
+
+		local targetUserId, distance =
+			MonsterService.ResolveStrikeTarget(player, Config.Items.BuntotPagiStrikeRangeStuds)
+
+		--[[
+			THE TWO BOOLEANS, AND THE ROLE STOPS HERE. `ResolveStrikeTarget` resolved the Aswang, so
+			`targetUserId` IS the role — and it goes no further than these two calls. Both answer
+			false for a UserId with no monster state, so there is no arrangement in which a nil
+			target and a healthy one produce different code below.
+
+			THE HEALTH VALUE IS NEVER READ. `IsWeakened` is the seam `MonsterService`'s header names
+			as "V08's strike gate, half two" precisely so that the number stays in the service that
+			owns it. Do not add a `GetHealth`; see this plan's §1.4.
+		]]
+		local exposed = targetUserId ~= nil and MonsterService.IsExposed(targetUserId)
+		local weakened = targetUserId ~= nil and MonsterService.IsWeakened(targetUserId)
+
+		local targetPlayer = if targetUserId ~= nil
+			then Players:GetPlayerByUserId(targetUserId)
+			else nil
+
+		local verdict = StrikeValidation.evaluate({
+			Phase = RoundService.GetPhase(),
+			StrikerState = RoundService.GetPlayerState(player),
+			Held = slot[player.UserId],
+			TargetDistance = distance,
+			TargetState = if targetUserId ~= nil then MonsterService.GetMonsterState(targetUserId) else nil,
+			TargetPlayerState = if targetPlayer ~= nil
+				then RoundService.GetPlayerState(targetPlayer)
+				else nil,
+			TargetExposed = exposed,
+			TargetWeakened = weakened,
+			Range = Config.Items.BuntotPagiStrikeRangeStuds,
+		})
+
+		--[[
+			THE THREE STRIKER-SIDE REFUSALS RETURN WITHOUT SPENDING. They sit above the spend line
+			because they are facts about the requester that the requester already holds — its own
+			phase, its own aliveness, its own hand — so returning early costs nothing and reveals
+			nothing. `STRIKE_NOT_HELD` in particular is what makes a double-press free: the second
+			press finds an empty slot and stops here.
+		]]
+		if
+			verdict == "STRIKE_WRONG_PHASE"
+			or verdict == "STRIKE_NOT_ALIVE"
+			or verdict == "STRIKE_NOT_HELD"
+		then
+			if Config.Debug.VerboseLogging then
+				-- A UserId and a verdict. NEVER the resolved target, and never the item: a target
+				-- UserId beside a striker UserId in the log is a record of who was standing where,
+				-- written to disk. The garlic handler states the same rule about the doorway.
+				print(`[ItemService] Strike refused for {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		--[[
+			§4.6: "IT BREAKS ON USE." THE SPEND IS UNCONDITIONAL FROM HERE AND SITS ABOVE EVERY
+			REMAINING BRANCH, so no future early return can skip it. This is the throw handler's
+			ordering — "the salt is spent on a MISS too" — and V09's correction to it does NOT apply:
+			the garlic spend was moved below `placeGarlic` because that function could itself fail,
+			and nothing below this line can.
+
+			IT IS A SECRECY RULE BEFORE IT IS A BALANCE ONE. `ClientRoundSnapshot.YourCarriedItem` is
+			pushed to this client every `Round.SnapshotInterval`, so whether the item survived a swing
+			is readable off the striker's own HUD. A spend conditional on the kill would make the
+			buntot pagi a REUSABLE detector — swing at each player in turn, watch your slot, and the
+			swing that costs nothing has named the Aswang and reported it is not yet Weakened. The
+			throw handler refuses the identical trade for salt, and there is exactly ONE of these.
+
+			CLEARED RATHER THAN DECREMENTED: reaching here means the slot held BUNTOT_PAGI and the
+			slot holds one thing.
+		]]
+		slot[player.UserId] = nil
+
+		--[[
+			V04, §4.4. A SWING IS LOUD, AND IT IS EQUALLY LOUD WHEN IT HITS NOTHING.
+
+			The throw handler's argument and the garlic handler's, third use: a cue that only fired on
+			a kill would be an identity probe with a sound instead of a return value. More sharply
+			here — a SILENT item use would be the only silent one in the game, so a listener who heard
+			an ITEM_USE cue and saw no salt burst would learn that somebody within 60 studs is holding
+			bawang or the buntot pagi. `.claude/lessons/absence-is-observable.md` in miniature.
+
+			From the STRIKER's own position, which the server has. Emitted BELOW the spend so it fires
+			on exactly the swings that cost something, and ABOVE the kill so a refused swing and a
+			landed one sound alike.
+		]]
+		local strikerRoot = if player.Character
+			then player.Character:FindFirstChild("HumanoidRootPart")
+			else nil
+
+		if strikerRoot ~= nil and strikerRoot:IsA("BasePart") then
+			NoiseService.Emit(player, "ITEM_USE", strikerRoot.Position)
+		end
+
+		--[[
+			NOTHING IS RETURNED TO THE CALLER ON EITHER PATH, INCLUDING THE KILL — the throw
+			handler's rule, the drop handler's and the garlic handler's, inherited. The striker
+			learns they killed the monster by watching it fall over, at the same moment as everyone
+			else with line of sight. An acknowledgement would be a timestamp.
+		]]
+		if verdict ~= "STRIKE_KILL" or targetUserId == nil then
+			if Config.Debug.VerboseLogging then
+				print(`[ItemService] Strike spent by {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		MonsterService.StrikeDown(targetUserId)
+	end)
```

**`MonsterService.GetMonsterState` does not exist yet.** `monsterStateOf` is a file-local. Either add a
one-line public wrapper in Step 3.1 alongside `ResolveStrikeTarget`, or have `ResolveStrikeTarget` return
the state as a third value — the second is tidier and keeps the number of new seams at two. Choose one at
implementation time and record which in the log. Either way the state is **not** a gate (see
`pure/StrikeValidation`'s `TargetState` comment); it exists so the grid is literal.

**`NoiseService` is already required by this file** (the throw and garlic handlers both use it), as is
`Players`. `StrikeValidation` is the one new require.

#### Step 3.4: Budget the new remote in the anti-cheat suite

**File:** `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

The suite's `UP_REMOTES` list is hand-maintained and asserts both directions, so it goes red the moment
`RequestStrike` is declared and stays red until it is budgeted and pinned.

```diff
 local UP_REMOTES = {
 	...
 	"RequestPlaceGarlic",
+	"RequestStrike",
 }
```

And one relationship worth pinning, beside the existing `RequestDropItem` / `CarryLimit` assertion:

```diff
+--[[
+	V10. THE STRIKE'S CAPACITY COVERS A DOUBLE-PRESS AND NOTHING MORE.
+
+	An honest client can fire `RequestStrike` at most ONCE per round: there is one buntot pagi
+	(`Items.BuntotPagiSpawnCount`) and every swing that reaches the spend line consumes it, so the
+	second press finds an empty slot and refuses ABOVE the spend. Capacity therefore only has to
+	absorb a double-click and a reconnect retry — `>= CarryLimit + 1` states that as a relationship
+	rather than as the literal 2, so raising `CarryLimit` (which `Config.Items`' comment names as a
+	real change) moves this with it.
+]]
+assert(
+	Config.AntiCheat.Budgets.RequestStrike.Capacity >= Config.Items.CarryLimit + 1,
+	`StrikeCapacity={Config.AntiCheat.Budgets.RequestStrike.Capacity}, `
+		.. `CarryLimit={Config.Items.CarryLimit}`
+)
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — this is the phase where it could happen. Three specific things to verify by
  reading the landed code, not the plan: (1) no `Debug.VerboseLogging` line prints `targetUserId`;
  (2) `StrikeDown` calls `clearExposed` before the death, so no Highlight is orphaned onto a body;
  (3) `MonsterService.ResolveStrikeTarget`'s return value never crosses a wire.
- **Remote direction** — `RequestStrike` is listened to with `OnServerEvent` on the server and fired
  with `FireServer` on the client (Phase 4). `check:remotes` catches the reverse.
- **Rate limiting** — `AntiCheatService.Consume` is the FIRST statement in the handler, inline, before
  anything is read. `check:ratelimit`'s 1200-character proximity window means a consume that is correct
  but distant reads as absent.
- **Magic numbers** — `Config.Items.BuntotPagiStrikeRangeStuds` is read twice in the handler and passed
  once into the resolver. No `8` appears in either service.
- **Phase ownership** — neither service calls `setPhase`. `StrikeDown` calls `RoundService.MarkKilled`,
  which reaches `enterEnding` — that is `RoundService` setting its own phase in response to a death it
  was told about, which is the same path `commitKill` already uses.
- **Player leaving mid-round** — three cases, and all three are already handled by code this phase does
  not touch. The STRIKER disconnecting mid-swing: `Players.PlayerRemoving` calls `spillItem` and nils
  the slot, and `ItemService.Start` runs before `RoundService.Start` in `init.server.luau`, which
  `spillItem`'s header names as load-bearing and undocumented until an audit found it. The CARRIER
  dying: `Humanoid.Died` inside `watchCharacter` spills at the root with no forward offset — §4.6's
  "a corpse in the open with the win condition next to it", already built. The ASWANG disconnecting
  between the resolve and the strike: `ResolveStrikeTarget` returns nil for a player with no character,
  and `StrikeDown` returns false for a UserId with no `Players:GetPlayerByUserId`.
- **Strict Luau** — `ResolveStrikeTarget` returns `(number?, number?)`; the handler's `if targetUserId
  ~= nil` narrowing must happen before each use or the analyzer rejects the `IsExposed` call. The
  `and`-chained form in the diff narrows correctly; a `local exposed = MonsterService.IsExposed(
  targetUserId)` does not.
- **Mobile budget** — one extra raycast per strike attempt, gated behind a distance test and a token
  bucket of 2. Nothing renders.
- **Scope** — `check:scope` sees `BuntotPagi` split as `Buntot` + `Pagi` and matches no OUT-list token.
  Confirm it stays green with two services now naming it.

**Issues identified:**

- **`RoundService.MarkKilled` ends a struck round as `ABORTED`, which is wrong and is V11's to fix.**
  V10 ships it knowingly. A playtester will see "Round aborted" on the end screen after a successful
  kill; that is the expected result of this chunk, not a bug to file. Recorded in §4.
- **`MonsterService` requires `RoundService` and `ItemService` requires both.** `ResolveStrikeTarget`
  calls `RoundService.GetAswangUserId()` from inside `MonsterService`, which that file already does
  elsewhere, so no new cycle is introduced. Confirm with `npm run analyze` rather than by reading the
  require list — a cycle here would surface as a nil at `Start` time, not at typecheck.
- **The Aswang can strike itself.** Deliberate, argued in `ResolveStrikeTarget`'s header: a guard
  would make the monster's buntot pagi behave differently from everyone's, readable by pressing a key.
  Flag it to the exploit auditor as a decision rather than an oversight.
- **`endFeed`'s verdict argument.** Passing `nil` is reserved for `completeFeed` and would leave a
  struck feeder with no `FeedUpdate` at all. Pass the interrupted verdict, and confirm the exact enum
  spelling against the six existing callers rather than against this plan.

---

### Phase 4: The client's request, the indistinguishability property, and the gate

#### Step 4.1: Route `Q` to `RequestStrike` in `InputController`

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run analyze`

A third branch in `performThrow`, asking `pure/ItemUse` rather than comparing to `"BUNTOT_PAGI"`, and
sending no argument — the camera's `LookVector` stops at this branch as it does for garlic.

**`Q` rather than a new key, and that is a decision.** The alternative was binding the strike to `F`
beside the Aswang's kill, which reads well as "attack" — and is refused: `KILL_ACTION` is bound
unconditionally for every player precisely so the bind itself is not a tell, and adding a role-shaped
second meaning to it is the kind of client-side branch `ItemCarry`'s header refuses for the slot table.
`Q` already means "use the thing in my hand" and already routes through `pure/ItemUse`, so V10 costs one
branch and no new key, no new mobile button and no new `ContextActionService` binding.

```diff
 	if TrialController.IsActive() then
 		Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
 	elseif ItemUse.verbFor(carriedItem) == "USE_PLACE" then
 		...
 		Remotes.Get("RequestPlaceGarlic"):FireServer()
+	elseif ItemUse.verbFor(carriedItem) == "USE_STRIKE" then
+		--[[
+			V10, §4.6. THE CLIENT'S ENTIRE CONTRIBUTION TO THE STRIKE IS THAT IT HAPPENED.
+
+			No target, no direction, no item. It does not pick a player, does not measure a distance,
+			does not raycast, and — critically — does not predict a kill and render one optimistically.
+			The salt branch below already refuses that for the same reason ("a client that renders a
+			hit the server refused is a client that has told its player the monster is stunned when it
+			is not"), and here the lie would be bigger: it would tell the player the round is over.
+
+			THE CHOICE IS A CONVENIENCE AND NEVER AN AUTHORITY — the garlic branch's reasoning one
+			line above, unchanged. `ClientRoundSnapshot.YourCarriedItem` is the server's own view of
+			this player's slot, so a client with a stale snapshot or a lying one gets a refusal rather
+			than an advantage: `RequestStrike` re-reads the slot on the server and
+			`pure/StrikeValidation` answers `STRIKE_NOT_HELD`, above the spend line, costing nothing.
+
+			IT ASKS `pure/ItemUse`, NOT `== "BUNTOT_PAGI"`. Same call `ItemService`'s throw handler
+			makes, so the client and the server route on one rule rather than two copies of it, and
+			`tests/item-use.test.luau` covers both.
+		]]
+		Remotes.Get("RequestStrike"):FireServer()
 	else
 		Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
 	end
```

`UIController` needs no change: it already renders `"   buntot pagi"` for
`snapshot.YourCarriedItem == Enums.ItemType.BuntotPagi` (around line 1871). Confirm rather than assume,
and if the HUD hints at a verb anywhere, make sure it does not hint at the two CONDITIONS — "press Q"
is fine, "press Q when it glows and is weak" is a tutorial line for §9.1's FTUE, not a HUD label, and
it belongs to whoever builds that.

#### Step 4.2: Assert the refusal is indistinguishable, as a property rather than a cell

**File:** `tests/strike-validation.test.luau`
**Verify:** `lune run tests/strike-validation.test.luau`

Over the whole target-side grid, assert the set of distinct verdicts has size one. A future author who
adds `STRIKE_TARGET_NOT_WEAKENED` for a good reason turns this red rather than shipping an oracle.

```diff
+--[[
+	THE PROPERTY THE CELL-BY-CELL GRID ABOVE CANNOT STATE, AND IT IS THE ONE §4.6 ACTUALLY ASKS FOR.
+
+	"Against anything else it does nothing" is a claim about INDISTINGUISHABILITY, not about a set of
+	return values. The grid above proves each cell equals what this file expects; it would keep
+	passing if somebody split `STRIKE_NO_EFFECT` into four honest, accurate, correctly-tested
+	verdicts — and that change ships an oracle. So the property is asserted as a property.
+
+	FOUR WORLDS, ONE VERDICT: nobody in reach, a survivor in reach, a healthy Aswang in reach, an
+	Aswang that is Exposed but not Weakened (or Weakened but not Exposed). A striker holding the item,
+	alive, in an ACTIVE round, must not be able to tell these apart from the server's answer.
+
+	WHY THIS IS NOT PARANOIA. `.claude/lessons/absence-is-observable.md`: "a secrecy leak is a
+	DIFFERENCE between players, not a piece of data." A distinct refusal per world IS that difference,
+	delivered to whoever asks, once per round for free. The verdict is never echoed today — but the
+	union is what a future `FireClient` would carry, and a union that cannot express the difference is
+	a union no future author can leak through by accident.
+]]
+local seen: { [string]: boolean } = {}
+local distinct = 0
+
+for d = 1, DIST_N do
+	for m = 1, MONSTER_N do
+		for _, targetPlayerState in PLAYER_STATES do
+			for _, exposed in BOOLS do
+				for _, weakened in BOOLS do
+					local verdict = StrikeValidation.evaluate({
+						Phase = "ACTIVE",
+						StrikerState = "ALIVE",
+						Held = "BUNTOT_PAGI",
+						TargetDistance = DISTANCES[d],
+						TargetState = MONSTER_STATES[m],
+						TargetPlayerState = targetPlayerState,
+						TargetExposed = exposed,
+						TargetWeakened = weakened,
+						Range = RANGE,
+					})
+
+					-- The kill is the one outcome that is SUPPOSED to be distinguishable: the monster
+					-- falls over in front of everybody. Every other cell must be one value.
+					if verdict ~= "STRIKE_KILL" then
+						if not seen[verdict] then
+							seen[verdict] = true
+							distinct += 1
+						end
+					end
+				end
+			end
+		end
+	end
+end
+
+assert(
+	distinct == 1 and seen.STRIKE_NO_EFFECT == true,
+	`a refused strike has {distinct} distinguishable outcomes; §4.6 allows exactly 1`
+)
```

Place this after the main product loop and before the final `print`, and fold its count into `checked`
if the suite reports one.

#### Step 4.3: Mark V10 in the build plan and hand V11 the result question

**File:** `docs/BUILD-PLAN.md`
**Verify:** `npm run verify`

The whole gate, and the note that a struck Aswang currently ends the round `ABORTED`.

Tick V10's Done line, and add a sentence to **V11's** entry so the handoff is in the document V11's
implementer will read rather than only in this plan:

```diff
 ### V11 — Win conditions, rewritten
 **Tier** Large · **Runner** 🤖 · **Deps** V10, V12 · 🔒
 
 Both conditions, and the six Config invariants that keep them reachable.
 
+> **V10 LEFT THIS ONE THING FOR YOU AND IT IS OBSERVABLE IN THE GAME TODAY.** A successful buntot
+> pagi strike calls `RoundService.MarkKilled`, which routes an Aswang death to
+> `RoundResult.Aborted` — the disconnect path's result, inherited because V10 deliberately did not
+> touch win conditions. So the second win condition currently FIRES and then SCORES WRONG: the end
+> screen says the round was void. That is the line to replace, and it is the same line the timeout
+> inversion below warns may exist in more than one place.
```

`npm run verify` is the first green whole-tree gate in this plan — `tests/anti-cheat-budgets.test.luau`
is red from Step 1.1 until Step 3.4, by design, so no earlier step claims it.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the client branch sends no argument and receives no reply. Confirm nothing was
  added to `UIController` that renders a strike outcome: a "your strike failed" toast would be the
  oracle this entire plan is shaped to prevent, delivered through the one surface `check:secrecy`
  cannot see.
- **Remote direction** — `FireServer` on the client, `OnServerEvent` on the server. `npm run verify`
  runs `check:remotes` over both halves for the first time in this plan.
- **Rate limiting** — unchanged from Phase 3; `verify` re-runs `check:ratelimit`.
- **Magic numbers** — `verify` runs `check:config` over the finished tree.
- **Phase ownership** — unchanged.
- **Player leaving mid-round** — the client branch has no state to leave behind.
- **Strict Luau** — `ItemUse.verbFor(carriedItem)` is called twice in the if-chain now (once for
  `USE_PLACE`, once for `USE_STRIKE`). That is two calls to a pure function on a scalar and costs
  nothing; hoisting it into a local is fine if the implementer prefers, but keep the comparison
  positive in both branches.
- **Mobile budget** — no new binding, no new button, no new render work. This is the reason `Q` was
  chosen over a new key; §5's mobile budget has no room for a seventh action button.
- **Scope** — `verify` runs `check:scope`.

**Issues identified:**

- **`npm run verify` at Step 4.3 is the first time the whole tree is green in this plan.** If it fails,
  the two most likely causes in order are the budgets suite (Step 3.4 incomplete) and a stale reader of
  `USE_NOT_IMPLEMENTED` the analyzer found late. Neither is a design problem.
- **The playtester's evidence is the half no check can supply.** V10's Verify line in
  `docs/BUILD-PLAN.md` asks for "one successful kill end to end", which needs three salt hits, a fresh
  reveal window and a swing inside it — a long sequence for a solo Studio session. Brief the playtester
  to set `Items.SaltDamage` temporarily so one hit reaches the threshold, and to REVERT it, or the
  evidence costs an hour. Note that this is a debug change to `Config.luau`, which the playtester
  cannot make itself and `guard-commit.mjs` will refuse to commit.
- **What a playtest cannot establish here, and should not claim to.** That a refused strike is
  indistinguishable is a claim about what a SECOND client can observe, and a solo session has one.
  `tests/strike-validation.test.luau` proves it at the module; `exploit-auditor` is what proves it at
  the service. Do not let a screenshot of a failed swing stand in for either.

---

## 3. Related Files

Reviewed while planning; annotated excerpts in `references/`.

| File | Why it was read | Review |
| --- | --- | --- |
| `docs/BUILD-PLAN.md` §V10 | The contract: Done line, Verify line, deps | — (cited inline) |
| `docs/MVP-SPEC.md` §4.6, §6.5, §8.3, §C.5 | What the item is, the invariant, the four properties | — (cited inline) |
| `src/shared/Enums.luau` | `MonsterState` has no `Weakened` and must not grow one | `Enums-review.luau` |
| `src/shared/Remotes.luau` | The five standing argument conventions this remote inherits | `Remotes-review.luau` |
| `src/shared/Config.luau` | Where the range and the budget go, and what they must relate to | `Config-review.luau` |
| `src/shared/Types.luau` | Verdict-union prefixing rule; where `StrikeVerdict` lands | `Types-review.luau` |
| `src/shared/pure/ItemUse.luau` | The V08/V09 boundary marker V10 closes | `ItemUse-review.luau` |
| `src/shared/pure/KillValidation.luau` | The fixed-order contract, the fail-closed guards, the split | `KillValidation-review.luau` |
| `src/shared/pure/MonsterHealth.luau` | `isWeakened`, the floor, and the shared/pure argument | `MonsterHealth-review.luau` |
| `src/shared/pure/ItemDrop.luau` | Decision C: the drop path already exists | `ItemDrop-review.luau` |
| `src/shared/pure/GarlicPlacement.luau` | V09's verdict shape and its nil-distance convention | `GarlicPlacement-review.luau` |
| `src/server/Services/MonsterService.luau` | The two seams built for this chunk; `monsterStateOf`; LOS | `MonsterService-review.luau` |
| `src/server/Services/ItemService.luau` | The handler shape, the spend ordering, `spillItem` | `ItemService-review.luau` |
| `src/server/Services/RoundService.luau` | `MarkKilled`'s Aswang branch — the V11 handoff | `RoundService-review.luau` |
| `src/client/Controllers/InputController.luau` | Where the `Q` branch goes and what it may not do | `InputController-review.luau` |
| `tests/anti-cheat-budgets.test.luau` | Why the tree is red between Steps 1.1 and 3.4 | `anti-cheat-budgets.test-review.luau` |
| `.claude/lessons/absence-is-observable.md` | The rule behind the collapsed verdict and the noise cue | — (cited inline) |

Not read, deliberately: `docs/MVP-SPEC.md` §4.7 and §4.8, `pure/WinConditions`, `pure/BodyTransitions`.
Those are V11's and V12's, and reading them is how a V10 plan grows a win-condition phase.

## 4. Follow Ups

### Questions / Clarifications

1. **The Done line's signature cannot be implemented literally, and this plan deviates from it.**
   `docs/BUILD-PLAN.md` asks for `(monsterState, monsterHealth, distance, phase)`. `monsterStateOf`
   never returns `EXPOSED` (`MonsterService.luau:451-484`, and its header says why), so a module gating
   on the state enum refuses every cell forever and the second win condition silently does not exist.
   And `monsterHealth` as a parameter would require `ItemService` to hold the Aswang's health in a
   local, which `MonsterService`'s header refuses ("none of the four returns the health value"). The
   plan takes `TargetExposed` and `TargetWeakened` from `IsExposed`/`IsWeakened` — the two seams
   `MonsterService.luau:59-60` names as "V08's strike gate, half one / half two" — and carries
   `TargetState` for the grid rather than for the gate. **`docs/BUILD-PLAN.md`'s V10 signature should
   be corrected** rather than the code bent to match it.

2. **A struck Aswang currently ends the round `ABORTED`, and V10 ships that knowingly.** V11 owns
   `RoundResult`. Step 4.3 writes the handoff into V11's own build-plan entry so it is not carried only
   in this document. Until then the second win condition **fires and scores wrong**, which is the
   correct state for this chunk to be in and the wrong state to ship a build in.

3. **Is a swing consumed by a refusal the right BALANCE, as opposed to the right secrecy?** The plan
   settles the secrecy question (§1.2 Decision B) and cannot settle the balance one. A survivor who
   swings early — at a monster that is Exposed but at 50 health, which looks identical to one at 25
   because §4.6 gives health no UI — loses the round's only win condition to a reasonable mistake. The
   mitigations are all diegetic and all §4.6's: the glow brightens as it weakens, so the information IS
   there for a player who has learned to read it. **This is a V16 question and belongs in that
   playtest's third named question.** Do not "fix" it by making the refusal free.

4. **Should a swing that lands make any sound distinct from one that does not?** The plan says no —
   both emit the same `ITEM_USE` cue from the striker's position. A distinct kill sound is arguably
   fine (the monster is dying in the open) and arguably a timestamp for a listener 60 studs away who
   cannot see it. Left silent because the safe direction is available for free; raise it at V14's audio
   pass with the argument, rather than adding it here.

5. **`MonsterService.GetMonsterState` versus a third return value from `ResolveStrikeTarget`.** Step 3.3
   needs the monster's state for the pure module's `TargetState` field, and `monsterStateOf` is a
   file-local. Either shape works; the plan prefers the third return value because it keeps the count of
   new public seams at two. Record which was chosen in `implementation-log.md`.

6. **Not verified against Roblox behaviour:** nothing in this plan calls an API this repo has not
   already used. `RaycastParams`, `Highlight`, `Humanoid.Died`, `RemoteEvent.OnServerEvent` and
   `Players:GetPlayerByUserId` all appear in the files reviewed. The one runtime unknown is whether
   `applyBodyRule(player, "KILLED")` leaves the struck Aswang's avatar standing — the plan reads
   `BodyTransitions` as answering KEEP for every DEAD cause since the C15 redesign, but that is read
   from `MarkKilled`'s comment rather than from `BodyTransitions` itself. **Confirm before Phase 3
   lands, or the monster's body may vanish on the round's best clip.**

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 1–3 | `tests/anti-cheat-budgets.test.luau` is red from Step 1.1 until Step 3.4; `npm run verify` cannot be green mid-plan | Low | By design — no step before 4.3 claims `verify` |
| 1 | `USE_NOT_IMPLEMENTED` is deleted from two unions; the analyzer must find every reader | Low | Step 1.4's verify is `verify:fast`, which runs `analyze` |
| 2 | A leading `nil` in a Luau list is invisible to `#`, silently deleting the three most important test cells | **High** | Explicit counts written into Step 2.2; sanity-check the printed cell count |
| 2 | `pure/StrikeValidation` is callable by any client (`src/shared` replicates wholesale) | Medium | Argued in §1.4 — no seed, no client-suppliable input. Re-check the landed file |
| 3 | A `Debug.VerboseLogging` line printing `targetUserId` beside the striker's would be a positional record on disk | **High** | Diffs log the striker and the verdict only; called out in Phase 3's checklist |
| 3 | An orphaned Exposed `Highlight` on the struck body is a permanent, post-round role oracle | **High** | `StrikeDown` calls `clearExposed` before `MarkKilled`; this is C04's bug shape |
| 3 | The Aswang can strike itself | Low | Deliberate; a guard would be a role-shaped branch readable by pressing a key |
| 3 | `MonsterService.GetMonsterState` does not exist; two shapes are viable | Low | Choose at implementation time, record in the log |
| 3 | `applyBodyRule("KILLED")` answering KEEP is read from a comment, not from `BodyTransitions` | Medium | Confirm before Phase 3 lands |
| 4 | A struck round scores `ABORTED` | Medium | V11's; handoff written into `docs/BUILD-PLAN.md` at Step 4.3 |
| 4 | Reaching a live strike in a solo Studio session needs three salt hits inside one reveal window | Medium | Set `Items.SaltDamage` for the playtester and revert it; `check:debug` refuses the commit |
