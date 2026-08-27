# Plan: V06 — Feeding

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V06 (`docs/BUILD-PLAN.md` — "V06 — Feeding", Tier Large, Deps V05, 🔒)
- **Description:** Replace the kill cooldown's role as the cost of a kill with an ACTION: after a
  validated kill the Aswang is pinned to the corpse for `Config.Monster.FeedDuration` seconds —
  transformed, locked, visible and interruptible. A completed feed pays `+FeedHeal` through
  `pure/MonsterHealth`; an interrupted one pays nothing, and "nothing" includes the camouflage
  refresh V07 will hang off the same completion path.
- **Date:** 2026-08-28
- **What the client is told:** Nothing new is broadcast. One new DOWN remote, `FeedUpdate`, is
  `FireClient` to the feeder alone and carries `{ Verdict, HoldSeconds }` — three verdicts
  (`FEED_STARTED`, `FEED_OK`, `FEED_INTERRUPTED`) and a number the client already has from replicated
  `Config`. No second client receives it, in any form. `ClientRoundSnapshot` is **not** widened. There
  is no new up-remote at all, so `check:ratelimit`'s surface does not grow. Full argument in
  §Preamble → "Secrecy: who learns a feed is happening".

---

### Preamble — read this with every phase

`npm run plan:phase -- <plan> 1` prints this alongside Phase 1. Every phase after that is read on its
own, so the sentences here that a later phase depends on are **repeated inside that phase** rather
than cross-referenced. That repetition is deliberate.

#### The seven decisions this plan makes, and the evidence for each

**1. There is no `RequestFeed`. The feed is a server-initiated consequence of a validated kill.**

§4.3: "After a kill, the Aswang **must** feed on the corpse for 5 seconds." *Must*, not *may*. An
opt-in feed is a feed the Aswang declines, and declining it costs nothing the moment the kill
cooldown stops being the gate — which is the whole point of the chunk. §4.3's own bullet says the
mechanic exists so the monster "cannot chain-kill, because it is pinned to the body it just made";
a remote the client can simply not fire deletes that property.

So `commitKill` starts the feed, on the server, with no client input of any kind. Consequences worth
stating up front:

- **No new `OnServerEvent` handler**, therefore no new `AntiCheatService.Consume` site and no new
  `Config.AntiCheat.Budgets` entry. `npm run check:ratelimit` is used as a step's verify in Phase 4
  precisely to prove that the surface did not grow.
- **Nothing to rate-limit means nothing to spam.** The strongest anti-cheat property available here
  is the absence of an entry point, and this plan takes it.
- `FeedUpdate` is a DOWN remote and `check:remotes` requires it in `EVENTS_DOWN`. Down remotes have
  no rate-limit obligation; the server decides when it fires.

**2. `commitKill` currently reverts immediately, and V06 must defer that revert. This is the single
most consequential edit in the chunk.**

`src/server/Services/MonsterService.luau:902-955` — `commitKill` runs `makeCorpse`, then
`RoundService.MarkKilled`, then **`revert(killer)`**, then the `PlayerKilled` FireClient. §4.3 says
the feed happens "transformed, locked in place, visible". A monster that reverted a frame after the
kill is not transformed and there is nothing to see. So the revert moves to the END of the feed, and
every feed-end path calls it.

Two knock-on effects, both real, both handled in Phase 2:

- `revert()` stamps `monster.LastRevertedAt`, and both `pure/TransformRules` and
  `pure/KillValidation` measure `Config.Monster.KillCooldown` from it. Deferring the revert by
  `FeedDuration` therefore starts the cooldown 5 seconds later. That is a **balance** change, not a
  bug, and it is V16's to judge.
- `transform()` arms `task.delay(Config.Monster.MaxTransformTime, ...)` (line 765) which force-reverts
  at 8 seconds. Kill at t=7, feed until t=12, and that timer fires **mid-feed**. The forced-revert
  callback must decline while `monster.Feeding` is true; the feed's own end path is then the only
  reverter. The form is bounded at `MaxTransformTime + FeedDuration` and that bound is stated in the
  Config comment so a tuner sees it.

**3. `Config.Monster.KillCooldown` is NOT deleted by this chunk, and here is the count.**

The brief asked whether V06 is the chunk that retires it. It is not, because it has live readers:

| Reader | Location |
| --- | --- |
| `TransformRules.evaluate` | `src/shared/pure/TransformRules.luau:44` (`Cooldown` field, `ON_COOLDOWN`) |
| `KillValidation.evaluate` | `src/shared/pure/KillValidation.luau:69,163-176` |
| `MonsterService` | three call sites: lines 792, 1013, 1114 |
| `tests/config.test.luau` | three assertions: lines 54, 160, 341 |
| `tests/transform-rules.test.luau` | lines 41, 100 |
| `tests/anti-cheat-budgets.test.luau` | line 114 |

`Config.luau:240-244` says it "dies with the chunk that builds feeding", and `docs/MVP-SPEC.md` §4.3
says v2.0 "replaces the timer with an action". **The spec is right and this plan does not carry it
out**, and that is a conflict raised rather than resolved: retiring the number means editing two pure
modules, three Lune suites and three call sites, and it changes what an Aswang can do after a revert
(instant re-transform) in a way that must be tuned, not guessed. See §4 Follow Ups — it wants its own
chunk with `balance(monster):` in the subject. **A plan step that deletes a live reader is refused.**

**4. Movement lock: `WalkSpeed = 0` is the affordance. The LEASH is the authority.**

A compromised client owns its character's physics — network ownership is on the client, so a player
who ignores `Humanoid.WalkSpeed` and drives the root part directly walks away from a "locked" feed.
Therefore the lock is two mechanisms with two different jobs:

- **`humanoid.WalkSpeed = 0` and jumping disabled, set in `beginFeed`.** This is what makes an honest
  client stand still and what makes the five seconds *feel* like a commitment. It is not security.
- **A server-side leash in `feedTick`**, measuring the feeder's `HumanoidRootPart` distance to the
  corpse's recorded position every 0.25s and ending the feed with `FEED_INTERRUPTED` beyond
  `Config.Monster.FeedLeashStuds`. **This is the authority.** A client that cheats the lock loses the
  heal and the camouflage refresh, which is exactly what a salt hit costs it. The cheat buys nothing.

This is `SearchService`'s Path 2 (`src/server/Services/SearchService.luau:448-500`) applied to a body
instead of a container, and it is the established shape in this repo for "a timed hold you must stand
still for".

**THE C14 HAZARD, AND IT IS THE REASON THIS PHASE IS SEPARATE.** `MonsterService`'s header states the
invariant in capitals: *no path added here may leave a living player's Humanoid properties different
from every other living player's.* `WalkSpeed` replicates. A feed that ends without restoring it
leaves exactly one character in the barrio reading 0 — a permanent, map-wide, remote-free role brand
with `check:secrecy` green over it, which is the shape that shipped twice already (C04's revert, C14's
stun). So `endFeed` restores `monster.BaseWalkSpeed` — **the honest pre-transform baseline, never the
transformed speed** — and then calls `revert()`, which writes the same value again. Both writes agree;
neither can leave a difference. `endFeed` does the restore itself rather than trusting `revert()`
because `revert()` early-returns for a player who is already un-transformed.

**Unverified Roblox behaviour, flagged for the playtester rather than assumed:** whether
`Humanoid.JumpPower = 0` alone stops a jump under this game's `Humanoid` configuration, or whether
`Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)` is also required, and whether either
survives a client that has already queued a jump. Nothing in this codebase touches either API today
(`grep -rn "JumpPower\|SetStateEnabled" src` finds nothing). Phase 5's artifact is where that is
settled. Anchoring `HumanoidRootPart` server-side is **rejected**, not deferred: it fights the client's
character controller, and this repo has no precedent for it.

**5. `FeedRules` consumes the existing body vocabulary. It does not re-implement the husk transition.**

The husk→corpse transition already exists and is not in a pure module:
`MonsterService.validateAndKillHusk` (line 979) validates the kill, calls
`RoundService.MarkHuskKilled(targetUserId)`, then `makeCorpse(targetUserId, huskCharacter)` — which
reparents the body into `workspace.Corpses` as `Corpse_{userId}`. A killed husk therefore *becomes* a
corpse, physically, in a different folder. `FeedRules` does not model that transition; it reads the
result. The resolver is one function in `MonsterService`, `bodyKindOf(model) -> Types.BodyKind?`,
which answers by parent folder — `corpses` → `CORPSE`, `RoundService.GetHusksFolder()` → `HUSK`, and
`nil` for anything else. This is the **first live use of `Enums.BodyKind`**, which V02 declared and
wired nowhere (`src/shared/Enums.luau:56-59`).

**6. Secrecy: who learns a feed is happening, and by what path.**

| Who | How | Is it a derived hint? |
| --- | --- | --- |
| Anyone with line of sight | By looking. A transformed monster stands at a body for five seconds | No — the form was already broadcast |
| The feeder | `FeedUpdate` `FireClient`, about itself | No — it learns nothing it did not do |
| Every other client | Nothing. No broadcast, no attribute, no tag, no Highlight | — |

**A feed can never precede the reveal of the form**, and that is structural rather than argued:
`KillValidation` gates the kill on `Transformed = monster.Announced`
(`MonsterService.luau:1105-1114`), and `Announced` is only true after `MonsterTransformed(true)` has
gone out to every client. `commitKill` is the only feed starter. So there is no state in which a feed
is observable before the transform that licenses it.

**NO `NoiseService.Emit` FOR A FEED, AND THIS IS A REFUSAL RATHER THAN AN OMISSION.** §4.4's four
noisy actions are `SEARCH`, `ITEM_USE`, `DOOR`, `SPRINT` (`Types.NoiseAction`). Feeding is not among
them, and adding it would be the first mechanic in the game whose noise **only one role can produce** —
a `NoiseCue` no survivor could ever have caused, arriving at every listener in radius. That inverts
`.claude/lessons/absence-is-observable.md`: it is not an absence, it is a presence exclusive to the
Aswang. `check:secrecy` would not catch it. Do not add it.

**The one replicated difference a feed does create is `WalkSpeed = 0`**, on a character that is
already in monster form and already announced, for exactly `FeedDuration` seconds. Bounded audience,
bounded lifetime, and decision 4 above is what keeps it bounded.

**7. `Feeding` is a boolean field, not a rewrite of `MonsterState`.**

`Enums.MonsterState` has five members and `Enums.luau:62-72` explicitly defers the question of
"whether this is one field or a field plus a flag" to the chunk that builds the state machine. V06
does not answer it. It adds `Feeding: boolean` beside the existing `Transformed` and `Exposed`
booleans and derives the enum value on demand:

```
monsterStateOf(monster) -> Types.MonsterState
    Feeding      -> "FEEDING"
    Transformed  -> "TRANSFORMED"
    otherwise    -> "NORMAL"
```

**It never returns `EXPOSED` or `CAMOUFLAGED`, and that is a decision.** `Exposed` is a LATCH that
coexists with the form — a salted monster is Exposed *and* still whatever it was — so returning
`EXPOSED` would shadow `TRANSFORMED` and `FeedRules` would refuse a legitimate feed by a glowing
monster. `CAMOUFLAGED` has no producer until V07. `FeedRules` still answers for both, because the
grid enumerates all five and a value with no stated answer is how this repo's transition tables get
bugs (`pure/BodyTransitions.luau`'s header is the long version). V07 revisits the derivation; §4
Follow Ups records that.

#### Pure-module constraints (`CLAUDE.md` → "Where testable logic goes")

- **No `require(script.Parent.X)`.** Lune has no `script`. `FeedRules` re-declares `RoundPhase`,
  `MonsterState` and `BodyKind` locally. Luau unions are structural, so the local type and
  `Types.MonsterState` are the same type and pass to each other without a cast.
- **Return a SCALAR union, never a list of them.** `.claude/lessons/pure-module-unions-widen-in-lists.md`:
  a literal union survives `require` as a scalar and widens to plain `string` inside a list, and the
  analyzer reports it at the call site in the wrong file. `FeedRules.evaluate` returns one string.
  Every other pure module here (`TransformRules`, `KillValidation`, `SaltThrow`) has the same shape.
- **`src/shared/pure/` is safe for this module.** It publishes a rule the spec already states and has
  no seed and no client-suppliable input: `MonsterState` comes from server memory, `BodyKind` from a
  folder a client cannot write, `distance` from server-read positions. Logic is not secret; inputs
  are, and this module has none that a client provides. Same argument `MonsterHealth`'s header makes.

#### The verify lines, honestly labelled

Phase 3 is the DataModel phase — a `WalkSpeed` write, a jump lock, five exit paths. **None of its
three checks proves the behaviour**; each is a tree-wide suite that can genuinely fail if the edit
breaks something, which is the best a terminal can do for code that only means anything inside a
running Studio. The proof is Phase 5's playtester artifact. This is said here rather than left for a
reader to discover, because a plan where every check claims to prove its step is worse than one that
names the two that do not.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The rules, the numbers, and the invariant

Everything that can be proven from a terminal, before a line of DataModel code exists. At the end of
this phase `lune run tests/feed-rules.test.luau` passes over the full state × body × distance × phase
grid and nothing in `src/server/` has changed.

#### Step 1.1: Add `Monster.FeedLeashStuds` and retarget the `KillCooldown` comment

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

One new tunable — how far the feeder may stray from the corpse before the feed breaks — and an edit
to the `KillCooldown` comment recording that V06 did NOT retire it and why, so the next reader does
not delete a live reader on the strength of a stale note.

```diff
-		-- DEAD UNDER v2.0, KEPT BECAUSE IT STILL HAS READERS (V02). §4.3's heading is literally
-		-- "Feeding — what replaced the kill cooldown": FeedDuration below is the v2 mechanism. This is
-		-- still read by MonsterService and pinned by config.test, so deleting it reds analyze AND
-		-- test:unit. It dies with the chunk that builds feeding.
+		--[[
+			DEAD UNDER v2.0 BY INTENT, ALIVE IN CODE BY COUNT — and V06 DID NOT RETIRE IT (V06).
+
+			§4.3's heading is literally "Feeding — what replaced the kill cooldown", and V06 built the
+			feed. It did not delete this number, and the reason is a list rather than a preference:
+			`pure/TransformRules` and `pure/KillValidation` both take a `Cooldown` field, MonsterService
+			passes this value at three call sites, and three Lune suites assert relationships over it
+			(`config`, `transform-rules`, `anti-cheat-budgets`). Deleting it reds `analyze` AND
+			`test:unit`, and it changes what an Aswang may do the instant it reverts — which is a
+			BALANCE question for V16, not a cleanup.
+
+			WHAT V06 DID CHANGE IS WHEN IT STARTS. `revert()` stamps `LastRevertedAt` and both pure
+			modules measure from it; V06 moved the post-kill revert to the END of the feed, so this
+			countdown now begins FeedDuration seconds later than it did under v1.3.
+
+			It dies with a chunk of its own, whose subject line is `balance(monster):`. See the V06
+			plan's Follow Ups.
+		]]
 		KillCooldown = 30, -- seconds after revert
```

And the leash, inside the existing FEEDING block, immediately after `FeedHeal`:

```diff
 		FeedDuration = 5,
 		FeedHeal = 25,
+
+		--[[
+			THE LEASH (V06, §4.3) — AND IT IS THE SERVER'S AUTHORITY, NOT THE MOVEMENT LOCK.
+
+			§4.3 says the feed happens "locked in place". `MonsterService` sets `WalkSpeed = 0` for the
+			duration, and that is what makes an honest client stand still — but a client OWNS its
+			character's physics, so WalkSpeed is an affordance and never a guarantee. The guarantee is
+			this number: every tick, the server measures the feeder's distance to the body it is
+			feeding on, and beyond this many studs the feed ends with no heal and no camouflage
+			refresh. A client that walks away from the lock gets exactly what a salt hit would have
+			cost it, which is why walking away buys nothing.
+
+			SMALLER THAN `KillRange` (8), AND `tests/config.test.luau` PINS THAT. A leash at or above
+			the kill range would let the monster drift a full kill's worth of distance and still be
+			"locked in place", at which point the corpse has stopped being the reliable window §4.3
+			says the buntot pagi needs. Compare `Search.RangeStuds = 10`, which is deliberately looser:
+			a container is furniture you stand beside, a body is one you stand ON.
+		]]
+		FeedLeashStuds = 6,
```

#### Step 1.2: Create `src/shared/pure/FeedRules.luau`

**File:** `src/shared/pure/FeedRules.luau`
**Verify:** `test -f src/shared/pure/FeedRules.luau`

`(monsterState, bodyKind, distance, phase, range) -> verdict` as a named-field Request table, with a
six-value scalar verdict union that distinguishes *why* a feed was refused. Fixed check order, fail
closed on every degenerate distance.

**A NAMED-FIELD REQUEST RATHER THAN FIVE POSITIONAL ARGUMENTS, and that is a deviation from the build
plan's literal wording that needs saying out loud.** `docs/BUILD-PLAN.md` writes the signature as
`(monsterState, bodyKind, distance, phase)`. It is naming the INPUTS, and every other decision module
in this repo takes them as one table — `TransformRules.evaluate(request)`, `KillValidation.evaluate
(request)`, `SaltThrow.evaluate(request)`. Two of those have five or more fields and one of them
(`KillValidation`) has twelve; positional arguments at that width are how a caller silently swaps two
booleans. The `Range` field is the fifth input and it comes from `Config.Monster.FeedLeashStuds`,
exactly as `KillValidation` takes `Range` from `Config.Monster.KillRange` rather than reaching for
Config itself.

**TWO EXPORTED FUNCTIONS OVER ONE PRIVATE CORE, and the second one is not padding.** `evaluate`
answers "may this feed START"; `mayContinue` answers "may this feed still be RUNNING", which is what
the server's tick asks four times a second. They cannot be the same function, because the state that
means *refuse* to one of them means *proceed* to the other: `FEEDING` is `ALREADY_FEEDING` to a start
and is the required state for a continuation. Collapsing them means the tick has to lie about the
state it passes, and a pure module you have to lie to is a pure module that has stopped being the
authority.

```diff
+--!strict
+--[[
+	FeedRules — may this Aswang feed on this body, right now? (V06, §4.3)
+
+		evaluate(request)    -> verdict    may a feed START
+		mayContinue(request) -> verdict    may a feed still be RUNNING
+
+	§4.3: "After a kill, the Aswang must feed on the corpse for 5 seconds — transformed, locked in
+	place, visible, and interruptible." This module owns the FIRST and THIRD words of that sentence
+	and nothing else. It holds no clock, no player, no Instance and no body; `MonsterService` owns the
+	five seconds, the lock, the corpse and the heal.
+
+	WHY THE VERDICT NAMES THE REASON. There is no client request behind a feed — the server starts it
+	as a consequence of a kill it already validated — so the refusal reasons exist for the SERVER's
+	log, which is where a feed that never starts gets diagnosed. They are also what a client hint
+	would be built from later, and the union is written so that such a hint could not become a role
+	oracle: every value here concerns THE RECEIVER'S OWN monster state, and a client that is not the
+	Aswang can never cause this function to run at all.
+
+	CONTRAST `SaltThrow`, WHICH DELIBERATELY COLLAPSES ITS REFUSALS INTO ONE `MISS`. That module is
+	called on a request a SURVIVOR sends about ANOTHER PLAYER, so a split verdict would let a client
+	stand in front of each player in turn and read the monster off the refusal shape. This module is
+	called about the feeder itself, by the server, unprompted. Different question, different answer.
+
+	WHY `src/shared/pure/` IS SAFE FOR THIS. The rule is in the spec, in this comment, and visible in
+	one round of play; a client that requires this module learns that feeding needs a corpse and eight
+	studs. What it cannot obtain is any INPUT: `MonsterState` is derived from `monsters[userId]` in
+	server memory, `BodyKind` from which workspace folder a model is parented to, and `Distance` from
+	two server-read positions. There is no seed here and no draw. `.claude/lessons/absence-is-
+	observable.md` applies in its structural direction: the module mentions no player and no UserId,
+	so there is no arrangement of it in which one player's answer is distinguishable from another's.
+
+	NO `script.Parent` REQUIRES — Lune has no `script`. The three unions are re-declared; Luau unions
+	are structural, so these and the matching ones in `Types` are the same types and pass to each
+	other without a cast. The verdict is returned as a SCALAR and never inside a list:
+	`.claude/lessons/pure-module-unions-widen-in-lists.md` is what that rule costs when it is broken.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
+export type BodyKind = "CORPSE" | "HUSK"
+
+--[[
+	`NOT_A_CORPSE` COVERS BOTH A HUSK AND NO BODY AT ALL, and that is one value on purpose.
+
+	The build plan's rule is "a husk is not feedable until it has been killed, at which point it is a
+	corpse". Splitting `HUSK` from `NO_BODY` would buy a log line one adjective and would create the
+	only place in this module where the answer varies by something a MAP AUTHOR controls — a body that
+	stopped existing mid-feed and a body that was never a corpse are the same fact to a feeder.
+]]
+export type Verdict =
+	"OK"
+	| "WRONG_PHASE" -- feeding is an ACTIVE-phase activity and nothing else
+	| "ALREADY_FEEDING" -- a feed is already running; one body at a time
+	| "NOT_TRANSFORMED" -- the feed belongs to the monster form, not to the role
+	| "NOT_A_CORPSE" -- a husk, or no body resolved at all
+	| "OUT_OF_RANGE" -- past the leash, or a degenerate distance or range
+
+export type Request = {
+	MonsterState: MonsterState,
+	-- OPTIONAL, and nil is a real answer rather than a caller's mistake: `MonsterService.bodyKindOf`
+	-- returns nil for a model in neither the Corpses nor the Husks folder, which is what a corpse
+	-- destroyed mid-feed looks like from the tick.
+	BodyKind: BodyKind?,
+	Distance: number,
+	Phase: RoundPhase,
+	-- Config.Monster.FeedLeashStuds at the call site. Taken as a field rather than read here, so the
+	-- test can hand this module a synthetic range and `check:config` has no literal to flag.
+	Range: number,
+}
+
+local FeedRules = {}
+
+--[[
+	FAIL CLOSED ON EVERY DEGENERATE NUMBER, and test the values rather than trusting them.
+
+	Lifted from `KillValidation.withinRange`, whose header records what each guard cost. The idiom is
+	`not (positive and finite)` rather than two negative tests, because NaN compares false to
+	EVERYTHING: written the other way round, `range <= 0 or range >= math.huge`, every NaN comparison
+	is false and a NaN sails straight through into `distance <= NaN`, which is also false, which
+	GRANTS the feed.
+
+	A NEGATIVE DISTANCE IS REFUSED TOO. It cannot arise from a `Magnitude`, and that is exactly why:
+	if one ever appears, something upstream has stopped being a distance and the safe answer is to
+	break the feed rather than to hold a monster in place on a number nobody can explain.
+]]
+local function withinRange(distance: number, range: number): boolean
+	if not (range > 0 and range < math.huge) then
+		return false
+	end
+
+	if not (distance >= 0 and distance < math.huge) then
+		return false
+	end
+
+	-- `<=`, so a feeder at exactly the leash is still on the body. Same boundary choice as
+	-- KillValidation's "within 8 studs", and the test asserts it rather than leaving it to a reader.
+	return distance <= range
+end
+
+--[[
+	THE SHARED CORE: everything that must be true for a feed to be HAPPENING, in the order that
+	decides which reason a log line carries when more than one applies.
+
+	World facts first (phase), then the feeder's own form, then the body, then geometry. Geometry is
+	LAST for `KillValidation`'s reason: it is the only condition an honest Aswang hits routinely, so a
+	log full of OUT_OF_RANGE is a UX finding and a log full of anything above it is a bug.
+
+	`FEEDING` COUNTS AS THE FORM HERE. A feed in progress is a transform being held — see
+	`MonsterService.monsterStateOf`, which returns FEEDING only when `Feeding AND Transformed`, so
+	this value can never mean "feeding, but reverted". The two callers below decide what to do about
+	FEEDING before they get here.
+]]
+local function feedable(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "WRONG_PHASE"
+	end
+
+	--[[
+		AN ALLOWLIST OVER FIVE STATES, NEVER `~= "NORMAL"`. `MonsterState` has five values and exactly
+		two of them are the monster form. `EXPOSED` and `CAMOUFLAGED` are refused here and neither has
+		a producer today — `monsterStateOf` never returns them (Exposed is a LATCH that coexists with
+		the form; camouflage is V07) — but a state with no stated answer is how `pure/BodyTransitions`
+		says these tables acquire bugs, so both are answered and both are in the grid.
+	]]
+	if request.MonsterState ~= "TRANSFORMED" and request.MonsterState ~= "FEEDING" then
+		return "NOT_TRANSFORMED"
+	end
+
+	--[[
+		THE HUSK RULE, AND IT IS A READ RATHER THAN A RE-IMPLEMENTATION.
+
+		The husk -> corpse transition already exists in `MonsterService.validateAndKillHusk`: it marks
+		the husk killed in `RoundService` and calls `makeCorpse`, which reparents the body into
+		`workspace.Corpses` as `Corpse_{userId}`. A killed husk therefore IS a corpse, physically, in
+		a different folder. This module does not model that; it compares the answer.
+	]]
+	if request.BodyKind ~= "CORPSE" then
+		return "NOT_A_CORPSE"
+	end
+
+	if not withinRange(request.Distance, request.Range) then
+		return "OUT_OF_RANGE"
+	end
+
+	return "OK"
+end
+
+--[[
+	MAY A FEED START? Called once, by `MonsterService.beginFeed`, on a kill the server already
+	validated.
+
+	THE `ALREADY_FEEDING` CHECK MUST PRECEDE `feedable`, AND IT IS NOT AN ORDERING PREFERENCE. Left to
+	`feedable`, a monster mid-feed would be told `OK` — FEEDING passes that allowlist — and the server
+	would start a second feed on a second body while the first one's tick was still running. Two live
+	feeds is two heals for one corpse.
+
+	THE PHASE CHECK IS REPEATED ABOVE IT RATHER THAN INHERITED, and the duplicated comparison is the
+	price of keeping this module's stated contract true: world facts first, always. Without it,
+	`FEEDING` during `ENDING` reports ALREADY_FEEDING — a fact about the feeder — when the fact worth
+	acting on is that the round is over. `tests/feed-rules.test.luau`'s precedence table pins it.
+]]
+function FeedRules.evaluate(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "WRONG_PHASE"
+	end
+
+	if request.MonsterState == "FEEDING" then
+		return "ALREADY_FEEDING"
+	end
+
+	return feedable(request)
+end
+
+--[[
+	MAY A FEED STILL BE RUNNING? Called four times a second by `MonsterService.feedTick`, and it is
+	the whole of §4.3's "interruptible" that lives in a pure module.
+
+	NOT `FEEDING` MEANS THE FORM WENT AWAY UNDER THE FEED, which is what a salt hit looks like from
+	here: `ApplySaltHit` reverts, `monsterStateOf` stops returning FEEDING, and the next tick reads
+	NOT_TRANSFORMED and ends the feed. That path is a BACKSTOP rather than the mechanism —
+	`ApplySaltHit` ends the feed explicitly and in order — but it is the one that also covers a revert
+	from any source nobody has thought of yet.
+]]
+function FeedRules.mayContinue(request: Request): Verdict
+	-- World facts first, for `evaluate`'s reason: a feed running when the round ends is refused
+	-- because the ROUND ended, not because of anything about the feeder.
+	if request.Phase ~= "ACTIVE" then
+		return "WRONG_PHASE"
+	end
+
+	if request.MonsterState ~= "FEEDING" then
+		return "NOT_TRANSFORMED"
+	end
+
+	return feedable(request)
+end
+
+return FeedRules
```

#### Step 1.3: Create `tests/feed-rules.test.luau` over the full grid

**File:** `tests/feed-rules.test.luau`
**Verify:** `lune run tests/feed-rules.test.luau`

5 states × 3 body kinds (`CORPSE`, `HUSK`, nil) × 5 distances × 5 phases = 375 cells for `evaluate`
and 375 for `mayContinue`, plus the degenerate-distance and degenerate-range boundary cases.

**THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCH ORDER**, and this is the one design
decision in the test worth arguing before it is written. Enumerating 750 cells and computing each
expectation with the same `if` chain the module uses proves that the module agrees with itself. So
the grid asserts **one boolean written as the spec states it** — "ACTIVE, and the form, and a corpse,
and inside the leash" — against `verdict == "OK"`, in one direction and the other. Which refusal wins
when several apply is a separate, SMALLER claim, and it is pinned by an explicit table of named rows
that a reader can check against the module's stated order by eye. Two claims, two mechanisms, neither
one a restatement of the code.

```diff
+--!strict
+--[[
+	May the Aswang feed, over the whole domain. (V06, §4.3)
+
+	The build plan's Verify line asks for "the state x body x distance x phase grid", and this is that
+	grid twice — once for `evaluate` (may a feed START) and once for `mayContinue` (may one still be
+	RUNNING). 5 x 3 x 5 x 5 is 375 cells each, which is the shape `monster-health` and `noise-model`
+	already set: a small pure function over a BOUNDED domain is the one case where enumerating beats
+	writing a case per bug.
+
+	WHY IT IS WORTH ENUMERATING AT ALL. Every failure this module can have is silent. A feed that
+	refuses when it should not means the Aswang keeps its kill and loses its heal, which reads as
+	balance; a feed that grants when it should not means chain-killing over a husk, which reads as an
+	exploit nobody can reproduce. Neither shows up as an error and neither is visible in one round.
+
+	THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCHES. `isOk` below is §4.3 written as one
+	conjunction. Computing the expectation with the module's own `if` order would prove only that the
+	module agrees with itself; PRECEDENCE — which refusal is reported when two apply — is a separate
+	and much smaller claim, and it has its own explicit table at the bottom.
+]]
+
+local Config = require("../src/shared/Config")
+local FeedRules = require("../src/shared/pure/FeedRules")
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
+-- SYNTHETIC, not Config's. These assertions are about the MODULE's rules; V16 retunes Config and must
+-- not be able to red this file. The live block is cross-checked at the bottom, as `monster-health`
+-- does.
+local RANGE = 6
+
+local STATES = { "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
+-- Three body answers, and the third is nil rather than a string: `bodyKindOf` returns nil for a model
+-- in neither folder, which is what a corpse destroyed mid-feed looks like from the tick.
+local BODIES: { any } = { "CORPSE", "HUSK", nil }
+local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
+-- On the body, well inside, EXACTLY at the leash (must be inside), a hair outside, and far away.
+local DISTANCES = { 0, RANGE / 2, RANGE, RANGE + 0.01, 400 }
+
+--[[
+	§4.3 AS ONE CONJUNCTION. "After a kill, the Aswang must feed on the corpse for 5 seconds —
+	transformed, locked in place, visible, and interruptible", plus §6.4's rule that every round
+	activity belongs to ACTIVE. Written from the spec so that it is an INDEPENDENT statement of the
+	same rule rather than a copy of the implementation.
+]]
+local function isOk(state: string, body: string?, distance: number, phase: string, starting: boolean): boolean
+	local formHeld = if starting then state == "TRANSFORMED" else state == "FEEDING"
+
+	return phase == "ACTIVE" and formHeld and body == "CORPSE" and distance <= RANGE
+end
+
+--[[
+	THE GRID, BOTH DIRECTIONS, BOTH FUNCTIONS. `#BODIES + 1` rather than `#BODIES`, because a trailing
+	nil is not counted by the length operator and the nil body is a third of the point — this is
+	exactly the shape of hole a `for _, body in BODIES` loop would silently skip.
+]]
+for _, starting in { true, false } do
+	local name = if starting then "evaluate" else "mayContinue"
+
+	for _, state in STATES do
+		for bodyIndex = 1, #BODIES + 1 do
+			local body: string? = BODIES[bodyIndex]
+
+			for _, phase in PHASES do
+				for _, distance in DISTANCES do
+					local request = {
+						MonsterState = state :: any,
+						BodyKind = body :: any,
+						Distance = distance,
+						Phase = phase :: any,
+						Range = RANGE,
+					}
+
+					local verdict = if starting
+						then FeedRules.evaluate(request)
+						else FeedRules.mayContinue(request)
+					local expected = isOk(state, body, distance, phase, starting)
+
+					check(
+						`{name}: {state}/{body or "nil"}/{distance}/{phase} agrees with §4.3`,
+						(verdict == "OK") == expected,
+						`verdict={verdict}, expectedOk={expected}`
+					)
+				end
+			end
+		end
+	end
+end
+
+--[[
+	PRECEDENCE. Which reason is reported when more than one applies — the module's header calls the
+	order part of the contract, and this table is that contract. Every row has TWO or more conditions
+	failing, so a reordered branch changes an answer here and nothing else in the file notices.
+]]
+local PRECEDENCE: { { any } } = {
+	-- state, body, distance, phase, starting, expected
+	{ "NORMAL", "HUSK", 400, "IDLE", true, "WRONG_PHASE" },
+	-- THE ROW THAT PINS "WORLD FACTS FIRST". Move the phase test below the FEEDING test in
+	-- `evaluate` and this row alone turns red.
+	{ "FEEDING", "HUSK", 400, "ENDING", true, "WRONG_PHASE" },
+	{ "FEEDING", "CORPSE", 0, "ENDING", false, "WRONG_PHASE" },
+	{ "FEEDING", "HUSK", 400, "ACTIVE", true, "ALREADY_FEEDING" },
+	{ "NORMAL", "HUSK", 400, "ACTIVE", true, "NOT_TRANSFORMED" },
+	{ "EXPOSED", "CORPSE", 0, "ACTIVE", true, "NOT_TRANSFORMED" },
+	{ "CAMOUFLAGED", "CORPSE", 0, "ACTIVE", true, "NOT_TRANSFORMED" },
+	{ "TRANSFORMED", "HUSK", 400, "ACTIVE", true, "NOT_A_CORPSE" },
+	{ "TRANSFORMED", nil, 0, "ACTIVE", true, "NOT_A_CORPSE" },
+	{ "TRANSFORMED", "CORPSE", 400, "ACTIVE", true, "OUT_OF_RANGE" },
+	{ "TRANSFORMED", "CORPSE", 0, "ACTIVE", true, "OK" },
+	-- mayContinue inverts exactly one row and nothing else.
+	{ "TRANSFORMED", "CORPSE", 0, "ACTIVE", false, "NOT_TRANSFORMED" },
+	{ "FEEDING", "CORPSE", 0, "ACTIVE", false, "OK" },
+	{ "FEEDING", "HUSK", 0, "ACTIVE", false, "NOT_A_CORPSE" },
+	{ "FEEDING", "CORPSE", 400, "ACTIVE", false, "OUT_OF_RANGE" },
+	{ "NORMAL", "CORPSE", 0, "ACTIVE", false, "NOT_TRANSFORMED" },
+}
+
+for _, row in PRECEDENCE do
+	local starting = row[5]
+	local request = {
+		MonsterState = row[1] :: any,
+		BodyKind = row[2] :: any,
+		Distance = row[3] :: number,
+		Phase = row[4] :: any,
+		Range = RANGE,
+	}
+
+	local verdict = if starting then FeedRules.evaluate(request) else FeedRules.mayContinue(request)
+
+	check(
+		`precedence: {row[1]}/{row[2] or "nil"}/{row[3]}/{row[4]} reports {row[6]}`,
+		verdict == row[6],
+		`got {verdict}`
+	)
+end
+
+--[[
+	THE BOUNDARY, ASSERTED RATHER THAN LEFT TO A READER. `<=` is the module's choice and §4.3's "on
+	the corpse" is what it implements; a `<` here would make a feeder standing at exactly the leash
+	break their own feed every tick, which reads in a playtest as "feeding is broken sometimes".
+]]
+check(
+	"a feeder at exactly the leash is still on the body",
+	FeedRules.evaluate({
+		MonsterState = "TRANSFORMED",
+		BodyKind = "CORPSE",
+		Distance = RANGE,
+		Phase = "ACTIVE",
+		Range = RANGE,
+	}) == "OK"
+)
+
+--[[
+	DEGENERATE NUMBERS, IN BOTH SLOTS, AND EVERY ONE MUST REFUSE.
+
+	This is the half of `KillValidation`'s history that cost three attempts and shipped wrong twice.
+	NaN compares false to everything, so a guard written as `distance > range` grants on NaN; an
+	infinite range makes every distance in the map land; a negative range squares to a positive one.
+	None of these is reachable from a client here — no client supplies any of them — and all of them
+	are reachable from a V16 Config edit, which is the failure this module is guarding against.
+]]
+local NAN = 0 / 0
+
+for _, distance in { -1, NAN, math.huge, -math.huge } do
+	check(
+		`a degenerate distance ({distance}) refuses`,
+		FeedRules.evaluate({
+			MonsterState = "TRANSFORMED",
+			BodyKind = "CORPSE",
+			Distance = distance,
+			Phase = "ACTIVE",
+			Range = RANGE,
+		}) == "OUT_OF_RANGE"
+	)
+end
+
+for _, range in { 0, -6, NAN, math.huge } do
+	check(
+		`a degenerate range ({range}) refuses even at zero distance`,
+		FeedRules.evaluate({
+			MonsterState = "TRANSFORMED",
+			BodyKind = "CORPSE",
+			Distance = 0,
+			Phase = "ACTIVE",
+			Range = range,
+		}) == "OUT_OF_RANGE"
+	)
+end
+
+--[[
+	AND THE LIVE CONFIG, cross-checked exactly as `monster-health` does its tuning block: the grid
+	above proves the MODEL, this proves the numbers this game actually ships can express a feed.
+]]
+check(
+	"Config's leash admits a feeder standing on the body",
+	FeedRules.evaluate({
+		MonsterState = "TRANSFORMED",
+		BodyKind = "CORPSE",
+		Distance = 0,
+		Phase = "ACTIVE",
+		Range = Config.Monster.FeedLeashStuds,
+	}) == "OK"
+)
+check(
+	"Config's leash refuses a feeder who walked to the next house",
+	FeedRules.evaluate({
+		MonsterState = "TRANSFORMED",
+		BodyKind = "CORPSE",
+		Distance = Config.Monster.FeedLeashStuds + 1,
+		Phase = "ACTIVE",
+		Range = Config.Monster.FeedLeashStuds,
+	}) == "OUT_OF_RANGE"
+)
+
+print(`  {checked - failures}/{checked} checks passed`)
+
+if failures > 0 then
+	error(`{failures} FeedRules check(s) failed`, 0)
+end
```

**Two notes for whoever implements this.**

- `BODIES` has a trailing `nil` and is therefore iterated by `for bodyIndex = 1, #BODIES + 1`, never
  by `for _, body in BODIES`. The length operator does not count a trailing nil, so the generic-for
  spelling silently drops a third of the grid and reports 250 passing checks — the exact shape of
  hole this file exists to close. If that reads badly, use a sentinel table with an explicit `NONE`
  entry mapped to nil at the call, but do not use the generic for.
- Rows 2 and 3 of `PRECEDENCE` are the ones that pin "world facts first". They are the only rows that
  turn red if the phase test is moved below the state test in either exported function, and they are
  the reason that duplicated comparison is in the module at all.

#### Step 1.4: Add `FeedVerdict` and `FeedUpdatePayload` to `Types.luau`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

The client-facing three-value union, deliberately narrower than `FeedRules.Verdict`, with the
absent-fields argument written out the way `SearchUpdatePayload`'s is.

**TWO UNIONS FOR ONE MECHANIC, AND THE NARROWER ONE IS THE POINT.** `FeedRules.Verdict` has six
values and names refusal reasons; `Types.FeedVerdict` has three and names outcomes. They are not the
same union because they do not have the same audience: the six are for a server log, and the three
cross the wire. Collapsing them would put `NOT_A_CORPSE` and `ALREADY_FEEDING` on a remote — harmless
today, since only the Aswang ever receives one, and exactly the kind of "harmless today" that
`MonsterService`'s transform handler refuses on principle ("logged, never echoed").

Add after the `SearchUpdatePayload` block, so the two timed-hold payloads sit together:

```diff
+--[[
+	V06, §4.3. WHAT A FEED LOOKS LIKE TO THE ONE PLAYER DOING IT.
+
+	THREE OUTCOMES, NOT SIX REASONS. `pure/FeedRules` returns six verdicts and five of them are
+	refusals; those exist for the server's log and none of them crosses the wire. What the feeder
+	needs is the same three things a searcher needs — it started, it finished, it broke — which is why
+	this union is shaped like `SearchVerdict`'s first three values and not like the pure module's.
+
+	`FEED_INTERRUPTED` IS ONE VALUE COVERING SIX PATHS: salt, walking past the leash, the corpse
+	fading or being destroyed, dying, the round ending, and disconnecting. Splitting them would tell
+	the Aswang WHY its feed broke, and the one it would most like to know — "was that salt, or did I
+	drift?" — is a fact about a survivor's aim that the monster should have to work out by looking.
+]]
+export type FeedVerdict =
+	"FEED_STARTED" -- the feed began; HoldSeconds is how long it will take
+	| "FEED_OK" -- the feed completed; the heal has already been applied server-side
+	| "FEED_INTERRUPTED" -- it broke, by any of six paths, and paid nothing
+
+--[[
+	V06, §4.3. `FeedUpdate`'s payload. FireClient to the ONE player whose feed it is, always; there is
+	no broadcast form of this remote and there must not be.
+
+	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:
+
+	  · NO HEALTH, in any form — not a value, not a fraction, not a "you are weak now". §4.6 is
+	    explicit that "a health value attached to a player is the reveal", and the ONLY licensed
+	    readout is the Exposed glow's brightness, which exists only while the licence does. A feed
+	    changes the health and this payload still says nothing about it.
+	  · NO VICTIM AND NO POSITION. The feeder is standing on the body; a field naming it would be the
+	    server telling a client something the client is already looking at, and it would be the first
+	    place a corpse's identity could be logged and differenced.
+	  · NO CAMOUFLAGE CHARGE. V07's reward rides `MonsterService.FeedCompleted`, a server-side
+	    BindableEvent. When V07 needs to tell the client it may hide again, that is a decision for
+	    V07's plan to argue in a diff — not a field to widen quietly here.
+
+	IT IS NOT A ROLE ORACLE, and the reason is that no second client ever receives it. A remote that
+	only the Aswang can receive tells the Aswang something it already knows: it just killed somebody.
+	Compare `RoleAssigned`, which is allowlisted in `check-secrecy.mjs` on exactly this reasoning —
+	fired to one player, carrying only that player's own business.
+]]
+export type FeedUpdatePayload = {
+	Verdict: FeedVerdict,
+	-- Config.Monster.FeedDuration on FEED_STARTED, 0 on the other two — `SearchUpdatePayload`'s rule,
+	-- for its reason: a client that could read a timing difference off an ending could distinguish
+	-- the paths this union deliberately collapses. It carries no information either way, since
+	-- Config replicates and the client already knew the number.
+	HoldSeconds: number,
+}
```

#### Step 1.5: Pin §6.5 invariant 2 in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

V05 did not add it — `grep -n FeedDuration tests/config.test.luau` returns nothing today. The
relationship, not the number: `FeedDuration` must exceed the time to cross ~15 studs at
`Trial.PlayerBaselineWalkSpeed` plus a strike, or the corpse-as-bait window stops being real and the
second win condition goes back to being a coin flip.

**THE SWING HAS NO CONFIG NUMBER YET, AND THIS INVARIANT SAYS SO RATHER THAN INVENTING ONE.** V08
builds the buntot pagi strike; until it exists there is nothing in `Config` for how long a swing
takes. The check below uses named locals for the allowance, with the V08 handoff written into the
comment. **Its headroom is deliberate and it is stated in the file**: at shipped values the floor is
about 2.9s against a `FeedDuration` of 5, so this catches a tune to 2.5 and not a tune to 3. That is
what the spec's own sentence licenses, and tightening it on a guess would be worse than the honest
looser bound — a balance test nobody trusts is a balance test somebody deletes.

Add near the existing `Monster` block of checks, after the KillCooldown assertions:

```diff
+--[[
+	§6.5 INVARIANT 2, AND §4.3'S "THE FEED DURATION IS LOAD-BEARING, NOT COSMETIC" (V06).
+
+	"It must exceed the time for a survivor to cross ~15 studs and land a buntot pagi swing… otherwise
+	someone tunes it to 3 seconds later and silently deletes a win condition."
+
+	WHY IT IS SILENT: the feed is the ONLY reliably predictable moment in the round — the monster is
+	stationary, visible, and standing somewhere survivors already know because there is a body there.
+	§4.6 says that window is what the buntot pagi needs. Shorten it and nothing errors, nothing warns,
+	and the second win condition quietly becomes a coin flip against a faster player. The symptom is
+	"the Aswang always wins", which reads as balance and gets fixed by moving a different number.
+
+	THE SWING HAS NO CONFIG NUMBER UNTIL V08. These two locals are the placeholder, and they are
+	locals rather than Config entries because they are not knobs — they are this test's model of a
+	human. V08 replaces SWING_SECONDS with the strike's real wind-up and deletes this note.
+]]
+local CROSSING_STUDS = 15 -- §4.3's own figure
+local REACTION_SECONDS = 1 -- registering the kill and turning toward it
+local SWING_SECONDS = 1 -- placeholder; V08 replaces this with the strike's real wind-up
+
+local crossing = CROSSING_STUDS / Config.Trial.PlayerBaselineWalkSpeed
+local window = crossing + REACTION_SECONDS + SWING_SECONDS
+
+check(
+	"the feed outlasts a survivor crossing fifteen studs and landing a swing",
+	Config.Monster.FeedDuration > window,
+	`FeedDuration={Config.Monster.FeedDuration}, needed>{window}`
+)
+
+--[[
+	AND THE FEED MUST NOT BECOME THE DOMINANT TERM IN HOW LONG A MONSTER IS A MONSTER (V06).
+
+	V06 defers the post-kill revert until the feed ends and makes `transform`'s MaxTransformTime timer
+	decline while a feed is live, so the form is held for at most MaxTransformTime + FeedDuration.
+	That bound is fine at 8 + 5. It stops being fine the moment FeedDuration passes MaxTransformTime,
+	at which point the "8 second" transform is mostly feeding and §4.3 step 4's forced revert has
+	stopped meaning anything. Nothing in the game reports that; the transform simply gets long.
+]]
+check(
+	"the feed never outlasts the transform it is holding open",
+	Config.Monster.FeedDuration < Config.Monster.MaxTransformTime,
+	`FeedDuration={Config.Monster.FeedDuration}, MaxTransformTime={Config.Monster.MaxTransformTime}`
+)
+
+--[[
+	AND THE LEASH MUST MEAN "LOCKED IN PLACE" (V06, §4.3).
+
+	The leash is the server's authority over the feed — `WalkSpeed = 0` is an affordance a compromised
+	client ignores, and the distance test is what actually costs it the heal. A leash at or above
+	KillRange would let the monster drift a full kill's worth of distance and still be feeding, at
+	which point the corpse has stopped being the fixed, known point §4.3 sells it as.
+]]
+check(
+	"the feed leash keeps the monster on the body",
+	Config.Monster.FeedLeashStuds < Config.Monster.KillRange,
+	`FeedLeashStuds={Config.Monster.FeedLeashStuds}, KillRange={Config.Monster.KillRange}`
+)
```

#### Step 1.6: Format the two new files to `stylua.toml`

**File:** `src/shared/pure/FeedRules.luau`
**Verify:** `npm run fmt:check`

`stylua src tests`, then `npm run fmt:check`. Tabs, double quotes, 100 columns. This is its own step
because `fmt:check` is part of `npm run verify` and a phase that cannot go green on formatting halts
the task loop over whitespace — which has cost this repo a loop iteration before.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private
  one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the
  other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply
  here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **The literal-union return is the predictable failure, and it is in the TEST, not the module.**
  `FeedRules.evaluate` returns a scalar, which `.claude/lessons/pure-module-unions-widen-in-lists.md`
  says is the safe case. The grid, however, builds its request from `STATES`/`PHASES`/`BODIES`, which
  ARE lists — so each element arrives as plain `string` and `:: any` is used at the four field sites
  rather than `:: FeedRules.MonsterState`, which would fail with "none of the union options are
  compatible". `:: any` in a test is acceptable where it would not be in `src/`: the test's job is to
  hit every cell, and the type it is asserting about is the RETURN.
- **`Config.Trial.PlayerBaselineWalkSpeed` is under `Trial`, not under `Round` or `Monster`**, and
  invariant 2 reads a trial number to check a round mechanic. That is not a mistake — it is the only
  place in `Config` that states how fast a player walks — but it is a coupling worth naming, and it
  is in Follow Ups.
- **`check:config` governs `src/server/` and `src/client/` only** (`GOVERNED = /(^|\/)src\/(server|
  client)\//` in `check-config.mjs:36`). The literals in `tests/config.test.luau` and the `RANGE = 6`
  in the grid are therefore not flagged, correctly — they are a test's model, not a knob. Do not
  "fix" this by moving them into `Config`; a synthetic tuning that V16 can retune is a test that
  stops testing the model.
- **`FeedLeashStuds = 6` is a guess and is labelled as one.** It has no playtest behind it. The
  invariant pins it below `KillRange`; V16 tunes the value. Flagged in Follow Ups.
- **Nothing in this phase touches a remote, a handler or the DataModel**, so five of the nine checks
  above are vacuous here by construction. That is the phase ordering working: everything provable
  from a terminal lands before anything that is not.

---

### Phase 2: The feed lifecycle in `MonsterService`

State, resolution, the three lifecycle functions, the tick, and the deferred revert. At the end of
this phase a kill starts a feed that completes and heals; nothing is locked and nothing is sent yet.

#### Step 2.1: Add `Feeding` to `MonsterState` and the `monsterStateOf` derivation

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify:fast`

One boolean beside `Transformed` and `Exposed`, initialised in `stateFor`, plus the derivation that
never returns `EXPOSED`. `verify:fast` runs `analyze`, which is what catches the strict-Luau literal
return the derivation is going to get wrong first.

**ONE TABLE, NOT TWO.** `SearchService` keeps `holds` beside `occupied` and its header spends a
paragraph on why they cannot disagree. This chunk needs no second table: the feed's three facts —
whether one is running, which body, and when it ends — all go on the existing `monsters[userId]`
entry, which is already the single authority for everything about an Aswang and is already cleared
by `onPhaseChanged`'s `table.clear` and by `onPlayerRemoving`. A separate `feeds` table would need
its own entry in both of those and would be one more thing that can outlive the round.

```diff
 	Health: number,
 	Exposed: boolean,
 	ExposedGlow: Highlight?,
 	ExposedGeneration: number,
+	--[[
+		FEEDING (V06, §4.3). SERVER-ONLY, LIKE EVERY OTHER FIELD IN THIS TABLE.
+
+		Three facts and no fourth. `Feeding` is the state, `FeedBody` is the corpse it is pinned to,
+		`FeedEndsAt` is the `os.clock()` deadline. There is no generation counter here and that is
+		deliberate: `revert()` and `applyExposed` both need one because both arm a `task.delay` whose
+		callback can outlive the thing that armed it, and a feed has no delayed callback at all — it
+		is driven by a tick that reads this table fresh every pass, so a stale one cannot exist.
+
+		`FeedBody` IS A MODEL REFERENCE, NOT A POSITION. A corpse is anchored and cannot move, so a
+		cached position would be correct — but a cached position cannot tell the tick that the body
+		was DESTROYED, which is what `clearCorpses` does on the way into INTERMISSION. Holding the
+		Model lets `bodyKindOf` re-answer every tick and lets a destroyed body end the feed through
+		the same path a husk would.
+
+		NOT A `MonsterState` ENUM VALUE. `Enums.luau:62-72` defers "one field or a field plus a flag"
+		to the chunk that builds the state machine, and V06 is not it: `Transformed` has four readers
+		outside this file and `Exposed` is a LATCH that coexists with the form. V06 adds one boolean
+		and derives the enum on demand. V07 decides the final shape.
+	]]
+	Feeding: boolean,
+	FeedBody: Model?,
+	FeedEndsAt: number?,
 }
```

```diff
 		Health = Config.Monster.MaxHealth,
 		Exposed = false,
 		ExposedGlow = nil,
 		ExposedGeneration = 0,
+		Feeding = false,
+		FeedBody = nil,
+		FeedEndsAt = nil,
 	}
```

And the derivation, placed immediately after `stateFor` so a reader meets the state and its projection
together:

```diff
+--[[
+	THE MONSTER'S STATE AS `pure/FeedRules` WANTS IT (V06, §4.3).
+
+	`Enums.MonsterState` has five members and this function produces three. The two it never produces
+	are the whole content of the decision, so they are stated rather than omitted:
+
+	  · `EXPOSED` IS A LATCH, NOT AN ACTIVITY. §4.6's reveal coexists with whatever form the monster
+	    is in — a salted Aswang is Exposed AND still an Aswang. Returning EXPOSED here would shadow
+	    TRANSFORMED, and `FeedRules` would answer NOT_TRANSFORMED for a glowing monster standing on
+	    a body it is entitled to feed on. That is not a hypothetical: §4.3 makes salt the thing that
+	    INTERRUPTS a feed, so a salted feeder is the common case, not the edge one.
+	  · `CAMOUFLAGED` has no producer until V07. `FeedRules` still answers for it and the grid still
+	    covers it, because `pure/BodyTransitions`'s header is right that a state with no stated answer
+	    is where these tables acquire bugs.
+
+	`FEEDING` REQUIRES BOTH FLAGS, AND THAT IS LOAD-BEARING FOR THE TICK. `Feeding and Transformed`,
+	never `Feeding` alone: `FeedRules.mayContinue` reads a non-FEEDING state as "the form went away
+	under the feed" and ends it, which is exactly the backstop that catches a revert from a source
+	nobody has thought of. Written as `if Feeding then return "FEEDING"`, a reverted-but-still-flagged
+	monster would report FEEDING forever and the backstop would never fire.
+]]
+local function monsterStateOf(monster: MonsterState): Types.MonsterState
+	if monster.Feeding and monster.Transformed then
+		return Enums.MonsterState.Feeding
+	end
+
+	if monster.Transformed then
+		return Enums.MonsterState.Transformed
+	end
+
+	return Enums.MonsterState.Normal
+end
```

**The strict-Luau trap in that function, named so it is not rediscovered.** Returning the bare string
`"FEEDING"` infers as plain `string` and fails against the `Types.MonsterState` return annotation —
which is the failure `Enums.luau`'s header calls out ("six of the scaffold's seven original analyze
errors were exactly that"). Returning `Enums.MonsterState.Feeding` works because that field already
carries its `:: Types.MonsterState` cast. Use the Enums field, never the literal. `npm run verify:fast`
runs `analyze` and is what catches it.

**One naming collision to watch.** `MonsterService` already has a local type named `MonsterState`
(the server's per-Aswang record) and `Types.MonsterState` is the five-value union. They are different
things with the same name and the file already lives with it. `monsterStateOf` takes the former and
returns the latter; annotate both sides explicitly rather than letting inference pick.

#### Step 2.2: Resolve a body's kind and a feeder's distance to it

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run lint`

Two small resolvers. `bodyKindOf` answers `CORPSE` / `HUSK` / nil by parent folder — the **first live
use of `Enums.BodyKind`**, which V02 declared and wired nowhere. `feedDistance` is
`SearchService.holdDistance` with a body in place of a container.

**NO REGISTRY, AND THIS IS A SIMPLIFICATION WORTH DEFENDING.** The obvious design records corpses in
a `{ [userId]: Model }` table so a feed can look one up. Nothing needs that: `commitKill` already
holds the corpse Model it just made and hands it straight to `beginFeed`, which stores it on
`monster.FeedBody`. A registry would be a second copy of `workspace.Corpses`, needing its own clearing
in `onPhaseChanged` and its own removal in `onPlayerRemoving`, to answer a question the folder already
answers. `lean-code`'s rule applies: search for what exists before adding anything.

```diff
+--[[
+	WHAT KIND OF BODY IS THIS? (V06, §4.7) The first live use of `Enums.BodyKind`, which V02 declared
+	and deliberately wired nowhere.
+
+	ANSWERED BY PARENT FOLDER, and that is not a shortcut — it is where the distinction actually
+	lives. `makeCorpse` reparents a body into `workspace.Corpses` and renames it `Corpse_{userId}`;
+	`RoundService.onPlayerRemoving` reparents a departing character into `workspace.Husks` as
+	`Husk_{userId}`. The two folders ARE the two kinds.
+
+	AND IT IS WHY `FeedRules` DOES NOT MODEL THE HUSK -> CORPSE TRANSITION. That transition already
+	exists, one screen down: `validateAndKillHusk` marks the husk killed in `RoundService` and calls
+	`makeCorpse` on the same Model, which moves it between these two folders. A husk that has been
+	killed IS a corpse by the time anything asks, so the rule "a husk is not feedable until it has
+	been killed" needs no clock and no second state — it is this function returning a different word.
+
+	NAME MATCHING IS DELIBERATELY NOT USED. `Corpse_{userId}` would work today and would silently
+	start lying the moment anything renames a body; the parent is what the rest of this file already
+	treats as authoritative (`clearCorpses` iterates it, the kill's raycast excludes it wholesale).
+
+	nil FOR ANYTHING ELSE, INCLUDING A DESTROYED MODEL. `clearCorpses` Destroys bodies on the way into
+	INTERMISSION, which sets `Parent` to nil — and `FeedRules` reads nil as NOT_A_CORPSE and ends the
+	feed. That is the corpse-destroyed exit, and it costs no extra code.
+]]
+local function bodyKindOf(body: Model): Types.BodyKind?
+	local parent = body.Parent
+
+	if parent == nil then
+		return nil
+	end
+
+	if parent == corpses then
+		return Enums.BodyKind.Corpse
+	end
+
+	if parent == RoundService.GetHusksFolder() then
+		return Enums.BodyKind.Husk
+	end
+
+	return nil
+end
+
+--[[
+	HOW FAR THE FEEDER HAS STRAYED FROM THE BODY. `SearchService.holdDistance` with a corpse in place
+	of a container, and the nil case means the same thing: something stopped existing, so break the
+	hold rather than error inside the tick.
+
+	RESOLVED FROM BOTH SIDES EVERY TICK, not cached. The corpse is anchored and cannot move, so a
+	cached corpse position would be correct — but the FEEDER moves, which is the entire point of the
+	leash, and a character that is replaced underneath a feed (a respawn, a `LoadCharacterAsync` from
+	`RoundService`) must read as nil rather than as a stale distance of zero.
+]]
+local function feedDistance(player: Player, body: Model): number?
+	local bodyRoot = rootOf(body)
+	local character = player.Character
+	local root = if character ~= nil then rootOf(character) else nil
+
+	if bodyRoot == nil or root == nil then
+		return nil
+	end
+
+	return (bodyRoot.Position - root.Position).Magnitude
+end
```

#### Where the whole feed section goes, and why it is not where you would first put it

**The entire V06 block — both resolvers from this step and all four lifecycle functions from Steps
2.3 and 2.4 — goes immediately BEFORE `commitKill`**, between `hasLineOfSight` (ends ~line 888) and
`commitKill`'s header comment (~line 890). Not after the kill section, and not in a new section at
the bottom.

Lua resolves a `local function` at its point of definition, so this is a compile-time fact rather
than a style preference — and the obvious placement is wrong in both directions at once:

| Callee | Declared at | Called by | Verdict |
| --- | --- | --- | --- |
| `rootOf` | 818 | `feedDistance` | feed block must be **after** 818 |
| `revert` | 621 | `endFeed` | ✓ |
| `applyHealthEvent` | 510 | via `HealFromFeed` | ✓ |
| `corpses` (upvalue) | 180 | `bodyKindOf` | ✓ |
| `monsterStateOf` | ~207 (Step 2.1) | `beginFeed`, `feedTick` | ✓ |
| `beginFeed` | this block | `commitKill` (902) | feed block must be **before** 890 |

So a feed section placed "after the kill section, with the other new code" leaves `commitKill`
calling an undeclared `beginFeed`, and one placed beside `makeCorpse` leaves `feedDistance` calling
an undeclared `rootOf`. There is exactly one window and it is the one named above. V05's
`refreshExposedGlow` carries this same note for the same reason ("DECLARED ABOVE `applyHealthEvent`
BECAUSE THAT FUNCTION CALLS IT").

Two things that look like ordering constraints and are not: `MonsterService.HealFromFeed` and
`MonsterService.FeedCompleted` are fields on the service table, resolved at call time, so
`completeFeed` may reference both from above their definitions. `feedTick` is referenced from
`Start`, which is last in the file.

#### Step 2.3: `beginFeed`, `completeFeed`, `endFeed`, and the `FeedCompleted` seam

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

The three lifecycle functions, `HealFromFeed` called from exactly one of them, and the BindableEvent
V07 connects to — modelled on `SearchService.ItemFound`, which is this repo's established shape for
"a seam the next chunk fills".

**THE ANSWER TO "WHAT IS THE CAMOUFLAGE SEAM", IN ONE SENTENCE:
`MonsterService.FeedCompleted`, a `BindableEvent` fired from `completeFeed` and from nowhere else.**

§4.3 says an interrupted feed costs the Aswang "the heal *and* the camouflage refresh". V06 makes
that **structural rather than careful**: `completeFeed` is the only caller of `HealFromFeed` and the
only firer of `FeedCompleted`, and `endFeed` — which every one of the six interruption paths goes
through — fires neither. There is no arrangement in which one reward is paid and the other is not,
because there is one place that pays and it pays both or runs not at all. V07 connects a listener and
changes nothing in this file. **V06 must not add a camouflage charge, a form, or a smoke anything;**
§3's OUT list and `check:scope` both apply, and Phase 5 sweeps for it.

Declared at module level, beside the service table, exactly where `SearchService.ItemFound` sits
(`SearchService.luau:76`):

```diff
 local MonsterService = {}
+
+--[[
+	THE V07 SEAM, AND V06 CONNECTS NOTHING TO IT (V06, §4.3).
+
+	§4.3 gives a completed feed two rewards: `+FeedHeal` health, and — "once the Aswang has been
+	revealed" — its camouflage back. V06 owns the first and V07 owns the second, and this event is the
+	joint. It fires with the feeding Player, from `completeFeed`, on a COMPLETED feed and never on an
+	interrupted one.
+
+	THAT IS WHAT MAKES §4.3'S "INTERRUPTING A FEED IS A REAL VICTORY" TRUE STRUCTURALLY RATHER THAN
+	CAREFULLY. The heal and this event have exactly one caller between them; every interruption path
+	goes through `endFeed`, which calls neither. Nobody has to remember to withhold the camouflage
+	refresh on a salt hit, because there is no code that could grant it.
+
+	IT CARRIES A PLAYER AND NOTHING ELSE. No health, no victim, no charge count, no body. A listener
+	that needs more should take a UserId and ask this service, the way `ItemService` already ANDs
+	`IsTransformed` with `RoundService.GetAswangUserId()` — the seams answer questions, they do not
+	volunteer state.
+
+	A BindableEvent RATHER THAN A REMOTE, and the distinction is the secrecy one: this never leaves the
+	server. The client half of a feed is `FeedUpdate`, fired to the feeder alone, and it deliberately
+	carries no camouflage field — see `Types.FeedUpdatePayload`.
+]]
+MonsterService.FeedCompleted = Instance.new("BindableEvent")
```

The three functions, placed after the kill section so `rootOf`, `revert` and `applyHealthEvent` are
all already in scope:

```diff
+--------------------------------------------------------------------------------
+-- The feed (§4.3, V06). What replaced the kill cooldown.
+--------------------------------------------------------------------------------
+
+--[[
+	THE ONLY WAY A FEED ENDS. Six paths reach here and every one of them must:
+
+	  1. the tick's deadline (via completeFeed, which calls this first)
+	  2. salt — `ApplySaltHit`
+	  3. walking past the leash, or the body ceasing to be a corpse — the tick
+	  4. dying, or the character going away — `watchCharacter`
+	  5. the round leaving ACTIVE — `onPhaseChanged`
+	  6. disconnecting — `onPlayerRemoving`
+
+	`verdict` IS nil WHEN THE CALLER SENDS ITS OWN MESSAGE. `completeFeed` sends FEED_OK and must not
+	be followed by a FEED_INTERRUPTED; every other caller passes FEED_INTERRUPTED. This is
+	`SearchService.releaseHold`'s contract verbatim, and it is copied rather than reinvented because
+	the failure it prevents — two contradictory messages for one ending — is the same failure.
+
+	SAFE TO CALL FOR A PLAYER WHO IS NOT FEEDING. Three of the six paths fire for players who were
+	not, and an early return is cheaper than six callers checking.
+
+	IT CALLS `revert`, AND THAT IS §4.3 STEP 4 ARRIVING LATE ON PURPOSE. Under v1.3 `commitKill`
+	reverted immediately; V06 moved that here, because §4.3 requires the feed to happen "transformed
+	… and visible" and a monster that reverted a frame after the kill is neither. Every feed therefore
+	ends in a revert, whichever of the six paths got here — which is also what stops a broken feed
+	leaving a permanent monster standing in the barrio.
+]]
+local function endFeed(userId: number, verdict: Types.FeedVerdict?)
+	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId, which is
+	-- the bug `revert()`'s first line and `applyHealthEvent`'s first line were both written to avoid.
+	local monster: MonsterState? = monsters[userId]
+
+	if monster == nil or not monster.Feeding then
+		return
+	end
+
+	-- STATE FIRST, THEN THE WORLD. `revert` below can reach code that asks whether this player is
+	-- feeding; it must already read false by then, or a re-entrant path finds a half-ended feed.
+	monster.Feeding = false
+	monster.FeedBody = nil
+	monster.FeedEndsAt = nil
+
+	local player = Players:GetPlayerByUserId(userId)
+
+	if player ~= nil then
+		-- Phase 3.1 restores the movement lock here, BEFORE this line. See that step.
+		revert(player)
+	end
+
+	if verdict == nil then
+		return
+	end
+
+	-- Phase 4.2 sends FeedUpdate here.
+end
+
+--[[
+	THE FEED RAN ITS COURSE. THE ONLY PATH THAT PAYS ANYTHING (§4.3, §4.6).
+
+	`endFeed` FIRST, so the state is already clean before the rewards land. `HealFromFeed` reads
+	`monsters[userId]` and `FeedCompleted`'s listener may too; both should see a monster that has
+	finished feeding, not one mid-teardown.
+
+	THE HEAL GOES THROUGH `MonsterService.HealFromFeed`, WHICH GOES THROUGH `pure/MonsterHealth`. Not
+	`monster.Health += Config.Monster.FeedHeal`, which would be a second implementation of §4.6's
+	arithmetic — one that does not cap at MaxHealth, does not repaint the Exposed glow, and is not
+	covered by `tests/monster-health.test.luau`. V05 built that seam and wrote "V06, on a COMPLETED
+	feed" on it; this is the call it was written for.
+
+	THE GLOW REPAINT IS NOT OPTIONAL AND IT IS ALREADY HANDLED. `applyHealthEvent` calls
+	`refreshExposedGlow` on every health change, and V05's comment there names this exact case: a feed
+	completed inside a live Exposed window would otherwise restore 25 health and leave the glow reading
+	the pre-feed value for the rest of the ten seconds — survivors looking at a monster that appears
+	one hit from death and is not. Nothing to add here; do not add a second repaint.
+]]
+local function completeFeed(player: Player)
+	endFeed(player.UserId, nil)
+
+	MonsterService.HealFromFeed(player.UserId)
+
+	--[[
+		AND V07'S HALF. Fired here and nowhere else, so an interrupted feed cannot pay it — see the
+		event's own comment. V06 connects no listener; `FeedCompleted` has no subscriber until V07,
+		which is the same state `SearchService.ItemFound` shipped in at V03.
+	]]
+	MonsterService.FeedCompleted:Fire(player)
+
+	-- Phase 4.2 sends FeedUpdate(FEED_OK) here.
+end
+
+--[[
+	START A FEED. ONE CALLER: `commitKill`, on a kill the server has already validated (§4.3).
+
+	THERE IS NO `RequestFeed` AND THERE MUST NOT BE. §4.3: "After a kill, the Aswang MUST feed on the
+	corpse for 5 seconds." An opt-in feed is a feed the Aswang declines, and declining costs nothing
+	once the kill cooldown has stopped being the gate — which is the whole point of the chunk. §4.3's
+	own bullet says the mechanic exists so the monster "cannot chain-kill, because it is pinned to the
+	body it just made"; a remote a client can simply not fire deletes that property. It also means this
+	chunk adds no `OnServerEvent` handler, no `AntiCheatService.Consume` site and no `Config.AntiCheat
+	.Budgets` entry — the strongest anti-cheat property available here is the absence of an entry point.
+
+	THE VALIDATION STILL RUNS, EVEN THOUGH THE SERVER IS THE ONLY CALLER. `FeedRules.evaluate` is not
+	guarding against a client here; it is guarding against the server having changed its mind between
+	`makeCorpse` and this line — a phase that ended, a body that failed to parent, a killer whose
+	character went away inside `commitKill`. Refusing on those is how a feed that cannot work becomes
+	a log line instead of a monster locked in place forever.
+
+	AND A REFUSED FEED STILL OWES A REVERT. §4.3 step 4 says the transform ends after a kill; V06 moved
+	that revert into `endFeed`, so a feed that never starts has to do it here or the killer stays a
+	monster until `MaxTransformTime` — which, because the forced-revert timer learns to decline while
+	feeding (Step 2.5), it might not even do. This is the single easiest line in the chunk to omit and
+	the hardest to notice: the symptom is a monster that occasionally never reverts.
+]]
+local function beginFeed(player: Player, body: Model)
+	local monster: MonsterState? = monsters[player.UserId]
+
+	if monster == nil then
+		return
+	end
+
+	local distance = feedDistance(player, body)
+
+	local verdict = FeedRules.evaluate({
+		MonsterState = monsterStateOf(monster),
+		BodyKind = bodyKindOf(body),
+		-- nil means the killer or the body has no root part any more. `math.huge` rather than a
+		-- sentinel number: FeedRules refuses a non-finite distance by the same guard that refuses a
+		-- NaN one, so "we could not measure" and "too far" resolve to one OUT_OF_RANGE.
+		Distance = if distance ~= nil then distance else math.huge,
+		Phase = RoundService.GetPhase(),
+		Range = Config.Monster.FeedLeashStuds,
+	})
+
+	if verdict ~= "OK" then
+		-- LOGGED, NEVER ECHOED, on the same terms as the transform and the kill refusals above. There
+		-- is no client to echo to here, and the property is kept anyway: a verdict that could safely
+		-- be echoed is the one worth having.
+		if Config.Debug.VerboseLogging then
+			print(`[MonsterService] Refused feed for {player.Name}: {verdict}`)
+		end
+
+		revert(player)
+
+		return
+	end
+
+	monster.Feeding = true
+	monster.FeedBody = body
+	monster.FeedEndsAt = os.clock() + Config.Monster.FeedDuration
+
+	-- Phase 3.1 applies the movement lock here. Phase 4.2 sends FeedUpdate(FEED_STARTED).
+end
```

**Two forward references, deliberately left as comments.** Phase 3.1 adds the lock to `beginFeed` and
its restore to `endFeed`; Phase 4.2 adds three `sendFeedUpdate` calls. Both are named in the code
above so the implementer of this step does not invent them early and the implementer of those steps
knows exactly where they go. A phase that leaves the game runnable is the requirement, and it does:
after this step a feed starts, ticks (Step 2.4), heals and reverts, with no lock and no client
message.

#### Step 2.4: `feedTick` and the scheduler loop

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run build`

The leash, the liveness check, the gone-player backstop and the corpse-destroyed path, on a 0.25s
`task.spawn` loop copied from `SearchService.Start`.

**THIS TICK IS THE SERVER'S AUTHORITY OVER THE FEED, and the movement lock in Phase 3 is not.** A
client owns its character's physics under Roblox's network ownership model, so a compromised client
can ignore `WalkSpeed = 0` and drive the root part directly. It cannot ignore this loop: the server
measures the distance itself, from positions it reads, and beyond `Config.Monster.FeedLeashStuds` the
feed ends with no heal and no `FeedCompleted`. Cheating the lock therefore buys exactly what a salt
hit would have cost — which is to say, it buys nothing. **This sentence is repeated in Phase 3
because Phase 3 is read on its own and it is the sentence that makes that phase not a security hole.**

```diff
+--[[
+	THE TICK. Four exits and one completion, four times a second.
+
+	IT ITERATES `monsters`, NOT A SEPARATE FEED TABLE, and that is the one-authority decision from
+	Step 2.1 paying off: there is nothing here that can disagree with the state, and nothing that
+	`onPhaseChanged`'s `table.clear` could leave behind. The table holds at most one entry per player
+	who has ever fired RequestTransform this round — realistically one — so the skip is free.
+
+	ASSIGNING TO FIELDS OF A VALUE DURING A GENERALISED-FOR IS DEFINED BEHAVIOUR IN LUAU, and unlike
+	`SearchService.searchTick` this loop never removes a KEY: `endFeed` clears three fields on an
+	entry and leaves the entry in place. Strictly safer than the precedent it copies.
+
+	`mayContinue`, NOT `evaluate`. The state here IS `FEEDING`, which `evaluate` refuses with
+	ALREADY_FEEDING by design — see `pure/FeedRules`'s header for why these are two functions and not
+	one with a flag.
+]]
+local function feedTick()
+	local now = os.clock()
+
+	for userId, monster in monsters do
+		if not monster.Feeding then
+			continue
+		end
+
+		local player = Players:GetPlayerByUserId(userId)
+
+		-- Path 6's backstop. `onPlayerRemoving` normally gets here first; this covers the window
+		-- where it has not fired yet. No verdict — there is nobody left to send one to.
+		if player == nil then
+			endFeed(userId, nil)
+			continue
+		end
+
+		--[[
+			DEAD, or a mid-round SPECTATOR. An allowlist against `Enums.PlayerState.Alive`, never
+			`~= Dead`: `PlayerState` has four values and exactly one of them may be feeding. This is
+			`pure/PlayerBody`'s rule and C01's bug wearing its fourth hat.
+
+			IT IS NOT REDUNDANT WITH THE FORM CHECK BELOW. A killed Aswang aborts the round (§4.8), so
+			today an Aswang cannot be DEAD mid-feed — but V08 builds the buntot pagi strike, which is
+			a second way for a feeding monster to stop being alive, and this line is what makes that
+			end the feed rather than leave a tick running against a corpse's corpse.
+		]]
+		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+			endFeed(userId, "FEED_INTERRUPTED")
+			continue
+		end
+
+		local body = monster.FeedBody
+
+		if body == nil then
+			endFeed(userId, "FEED_INTERRUPTED")
+			continue
+		end
+
+		local distance = feedDistance(player, body)
+
+		--[[
+			THE LEASH, THE FORM AND THE BODY, ALL THREE THROUGH THE PURE MODULE.
+
+			  · past FeedLeashStuds        -> OUT_OF_RANGE     the monster walked off its meal
+			  · the form went away         -> NOT_TRANSFORMED  a salt hit, or any revert
+			  · the body left the folder   -> NOT_A_CORPSE     `clearCorpses` destroyed it
+			  · the round left ACTIVE      -> WRONG_PHASE      `onPhaseChanged` normally gets here first
+
+			ALL FOUR COLLAPSE TO ONE `FEED_INTERRUPTED` ON THE WIRE. `Types.FeedVerdict`'s comment says
+			why: telling the Aswang WHICH of these broke its feed hands it "was that salt, or did I
+			drift?" for free, and that is a fact about a survivor's aim it should have to work out by
+			looking.
+		]]
+		local verdict = FeedRules.mayContinue({
+			MonsterState = monsterStateOf(monster),
+			BodyKind = bodyKindOf(body),
+			Distance = if distance ~= nil then distance else math.huge,
+			Phase = RoundService.GetPhase(),
+			Range = Config.Monster.FeedLeashStuds,
+		})
+
+		if verdict ~= "OK" then
+			if Config.Debug.VerboseLogging then
+				print(`[MonsterService] Feed broken for {player.Name}: {verdict}`)
+			end
+
+			endFeed(userId, "FEED_INTERRUPTED")
+			continue
+		end
+
+		local endsAt = monster.FeedEndsAt
+
+		if endsAt ~= nil and now >= endsAt then
+			completeFeed(player)
+		end
+	end
+end
```

And the loop, in `MonsterService.Start`, beside the two remote handlers:

```diff
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
 	Players.PlayerAdded:Connect(onPlayerAdded)
 	Players.PlayerRemoving:Connect(onPlayerRemoving)
+
+	--[[
+		THE FEED'S CLOCK (V06). Lifted from `SearchService.Start`, quarter-second cadence and all.
+
+		A LOOP RATHER THAN A `task.delay(FeedDuration)`, and the difference is §4.3's "interruptible".
+		A delayed callback knows only that five seconds passed; it cannot notice that the monster
+		walked away at second two, and a feed that pays out because nobody was watching is not a
+		mechanic. Four times a second is `SearchService`'s cadence for the same reason — the leash is
+		six studs and a transformed Aswang covers about five in a quarter-second, so the worst-case
+		overshoot is roughly one leash.
+
+		RUNS UNCONDITIONALLY, in every phase. `feedTick` skips every entry that is not feeding, and
+		`monsters` is empty outside a round; gating the loop on the phase would be a second copy of
+		the phase rule with nothing to gain.
+	]]
+	task.spawn(function()
+		while true do
+			feedTick()
+			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
+		end
+	end)
```

**The `-- config-ok:` waiver is mandatory and its wording matters.** `check:config` flags `0.25` in
`src/server/`, and `SearchService.luau:670` carries the identical waiver for the identical line. A
waiver with a reason shows up in a diff and can be argued with; the number genuinely is a scheduler
cadence rather than a balance knob, and it is the same one this repo already chose once.

#### Step 2.5: `commitKill` starts the feed; the revert is deferred; the forced-revert declines

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `lune run tests/transform-rules.test.luau`

The edit the whole chunk turns on. `revert(killer)` leaves `commitKill`; `beginFeed` takes its place;
`transform`'s `MaxTransformTime` timer learns to decline while a feed is live.

`commitKill`'s header documents its four steps as an order in which "every line depends on the one
above it", so the header changes with the code:

```diff
 	  3. The revert (§4.3 step 4, "after a kill it must revert"). This is ALSO what starts the cooldown,
 	     because revert() stamps LastRevertedAt — §4.3 step 5's "30s from revert" is not implemented as
 	     a separate timer anywhere, it is this line.
+	     V06 REPLACED THIS LINE WITH `beginFeed`, AND THE REVERT MOVED TO THE END OF THE FEED. §4.3's
+	     "Feeding — what replaced the kill cooldown" requires the feed to happen "transformed, locked
+	     in place, visible": a monster that reverted a frame after the kill is none of those, and there
+	     would be nothing for a survivor to walk up to. `endFeed` now calls `revert` on all six of its
+	     paths, so the transform still always ends — FeedDuration seconds later than it used to, which
+	     also moves the start of the KillCooldown countdown by the same amount. That is a BALANCE
+	     change for V16 to judge and it is recorded in Config's KillCooldown comment.
+	     A REFUSED FEED STILL REVERTS, inside `beginFeed`. Without that line a feed that cannot start
+	     leaves a permanent monster, because the forced-revert timer below now declines while feeding.
 	  4. The broadcast, last, so no client is told about a kill the server has not finished committing.
```

```diff
 	RoundService.MarkKilled(victim, true)
 
-	revert(killer)
+	--[[
+		§4.3 STEP 4, VIA THE FEED (V06). `victimCharacter` is the corpse by this line — `makeCorpse`
+		above mutated it in place and reparented it into `workspace.Corpses` — so this is the body the
+		Aswang is pinned to, handed over directly rather than looked up. There is no corpse registry
+		precisely because this line already holds the Model.
+	]]
+	beginFeed(killer, victimCharacter)
```

And the forced-revert timer in `transform`:

```diff
 	task.delay(Config.Monster.MaxTransformTime, function()
-		if monster.Generation == generation and monster.Transformed then
+		--[[
+			`not monster.Feeding` IS V06'S ADDITION AND IT IS NOT COSMETIC.
+
+			Transform at t=0, kill at t=7, feed until t=12 — and without this clause the 8-second
+			forced revert fires at t=8, in the middle of a feed, reverting a monster that §4.3 requires
+			to stay "transformed, locked in place, visible" for five full seconds. The feed would then
+			be broken by the game's own timer rather than by a survivor, which is the mechanic failing
+			silently in the Aswang's favour's opposite direction.
+
+			NOTHING RE-ARMS THIS TIMER, and nothing needs to: `endFeed` reverts on every one of its six
+			paths, so a declined forced revert is a revert deferred to the feed's end, not one skipped.
+			The form is therefore held for at most MaxTransformTime + FeedDuration, and
+			`tests/config.test.luau` pins FeedDuration below MaxTransformTime so that bound stays a
+			transform with a feed on the end rather than a feed with a transform on the front.
+		]]
+		if monster.Generation == generation and monster.Transformed and not monster.Feeding then
 			revert(player)
 		end
 	end)
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private
  one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the
  other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply
  here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **A refused `beginFeed` that forgets to revert leaves a permanent monster, and after Step 2.5 the
  forced-revert timer will not rescue it.** This is the highest-severity defect the phase can ship
  and it has no symptom until somebody watches an Aswang stay transformed for a whole round. The
  `revert(player)` in `beginFeed`'s refusal branch is the fix and it is written into the diff; do not
  simplify it away on the reasoning that "the feed always starts".
- **The 0.25s tick is per-frame-ish work and §5's mobile budget applies to the CLIENT.** This loop is
  server-side and iterates a table with at most five entries, so it costs nothing on a phone. Worth
  stating because "new per-frame work" is on the checklist and the honest answer is that this one is
  not the kind the checklist means.
- **`monsterStateOf` returning `Enums.MonsterState.Feeding` requires `Enums` to already be required
  in this file.** It is (`MonsterService.luau:90`), and it is already used for `RoundPhase` and
  `PlayerState` comparisons. No new import.
- **`bodyKindOf` compares against `RoundService.GetHusksFolder()`, which returns `Folder?`.** A nil
  return makes the comparison false, which lands on the final `return nil` — correct, and worth
  noting because "the husks folder does not exist yet" is a real state during `Start`.
- **Player leaving mid-round (§6.4):** covered twice on purpose. `onPlayerRemoving` ends the feed
  (Phase 3.3) and `feedTick`'s `player == nil` branch is the backstop for the window before it fires.
  V05 found this exact double-cover missing for `clearExposed` and it cost a glowing husk.
- **Nothing in this phase adds a remote or a handler**, so `check:remotes` and `check:ratelimit` are
  unchanged by it — which is the point, and Phase 4 proves it rather than asserting it.

---

### Phase 3: The lock, and every way a feed ends

Five exits, one restore, and no path that leaves a Humanoid property differing from every other
living player's. **None of this phase's checks proves the behaviour** — see the preamble.

#### Step 3.1: The movement lock, and its restore on every exit

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run test:unit`

`WalkSpeed = 0` and jumping disabled in `beginFeed`; `BaseWalkSpeed` and jumping restored in
`endFeed`, before `revert()` writes the same value again.

**READ THIS BEFORE THE DIFF — the two sentences this phase cannot be implemented without.**

**1. The lock is the affordance. The leash is the authority.** A client owns its character's physics
under Roblox's network ownership model, so a compromised client can ignore `WalkSpeed = 0` and drive
the root part directly. `WalkSpeed = 0` exists to make an honest client stand still and to make five
seconds *feel* like a commitment. The thing that actually holds a feed to a body is `feedTick`'s
distance test against `Config.Monster.FeedLeashStuds` (Step 2.4), which runs on the server against
positions the server reads. A client that cheats the lock walks out of the leash and loses the heal
and the camouflage refresh — which is exactly what a salt hit costs it. **The cheat buys nothing.**
If this phase is implemented without Step 2.4 already in place, the feed is not server-authoritative.

**2. `WalkSpeed` replicates, and a feed that ends without restoring it is a permanent role brand.**
`MonsterService`'s own header states the invariant in capitals: *no path added here may leave a living
player's Humanoid properties different from every other living player's.* One character in the barrio
reading `WalkSpeed = 0` while four read 16 is map-wide, remote-free, and invisible to
`check:secrecy` — the same shape as C04's revert bug and C14's stun brand, both of which shipped with
the full gate green over them (`ItemService.applyHit`'s header is the long version). So:

- **Do not lock what you cannot unlock.** The lock is applied only when `monster.BaseWalkSpeed ~= nil`
  and a Humanoid resolves. That makes the restore total rather than conditional, and it costs nothing:
  `captureLook` sets `BaseWalkSpeed` at the start of every transform, and `FeedRules` refuses a feed
  by anyone who is not transformed, so the nil case is unreachable and guarded anyway.
- **Restore `BaseWalkSpeed`, never the transformed speed.** `revert()` writes the same value a line
  later, so both writes agree. C14's bug was precisely the other choice: a stun that restored the
  captured *transformed* speed onto a player who was no longer transformed.
- **`endFeed` does the restore itself rather than trusting `revert()`.** `revert()` early-returns for
  a player who is not `Transformed`, and there is at least one path — the tick's NOT_TRANSFORMED
  branch, which fires *because* a revert already happened — where that early return is guaranteed.

**Capture before mutating, for the jump properties too.** `captureLook` captures `BaseWalkSpeed` and
nothing about jumping. Rather than assume a default, the feed captures both jump properties on the
way in and restores both on the way out — C04's lesson, applied to two more fields. Both are written
regardless of `Humanoid.UseJumpPower`, so the lock works whichever mode this game's Humanoids are in
and the restore is correct either way.

```diff
 	Feeding: boolean,
 	FeedBody: Model?,
 	FeedEndsAt: number?,
+	--[[
+		THE LOCK'S CAPTURED STATE (V06, §4.3). Added in Phase 3 rather than Phase 2 so that the feed
+		lifecycle landed with no Humanoid write in it at all — the two halves are separable and the
+		dangerous one is this one.
+
+		C04'S LESSON, APPLIED TO TWO MORE FIELDS: capture what you are about to change, restore what
+		you captured, never a hardcoded default. C04 restored every part to white Plastic at scale 1.0
+		and branded the ex-Aswang map-wide; the same mistake here is `JumpPower = 50` on revert, which
+		is right for almost every player and wrong for whoever the game gave a different value.
+
+		BOTH PROPERTIES, NOT ONE. `Humanoid.UseJumpPower` decides which of JumpPower and JumpHeight is
+		live, and nothing in this repo sets it. Writing and restoring both means the lock holds and the
+		restore is correct without this file having to know which mode is in use.
+
+		WALKSPEED IS NOT HERE, DELIBERATELY. `BaseWalkSpeed` above already holds the honest
+		pre-transform speed, captured by `captureLook`, and that is what the feed restores — not the
+		transformed speed, which is C14's bug spelled out.
+	]]
+	FeedBaseJumpPower: number?,
+	FeedBaseJumpHeight: number?,
 }
```

Initialise both to nil in `stateFor` beside the other three feed fields, then:

```diff
 	monster.Feeding = true
 	monster.FeedBody = body
 	monster.FeedEndsAt = os.clock() + Config.Monster.FeedDuration
 
-	-- Phase 3.1 applies the movement lock here. Phase 4.2 sends FeedUpdate(FEED_STARTED).
+	--[[
+		THE LOCK (§4.3, "locked in place"). AN AFFORDANCE, NOT THE AUTHORITY — `feedTick`'s leash is
+		what actually holds a feed to a body, because a client owns its own character's physics and can
+		ignore every line below. This is what makes an honest client stand still.
+
+		GUARDED ON `BaseWalkSpeed`, SO THE RESTORE CANNOT FAIL. Do not lock what you cannot unlock: one
+		character reading WalkSpeed 0 for the rest of the round is a map-wide role brand that
+		`check:secrecy` cannot see. The nil case is unreachable — `captureLook` sets it at the start of
+		every transform and FeedRules refuses a feed by anyone untransformed — and it is guarded anyway,
+		because "unreachable" is what C04 and C14 both were.
+	]]
+	local character = player.Character
+	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
+
+	if humanoid ~= nil and monster.BaseWalkSpeed ~= nil then
+		monster.FeedBaseJumpPower = humanoid.JumpPower
+		monster.FeedBaseJumpHeight = humanoid.JumpHeight
+
+		-- 0 is on `check-config.mjs`'s IDIOMATIC list; these are not knobs. "Cannot move" has one
+		-- value and it is not a balance number, exactly as `makeCorpse`'s own `WalkSpeed = 0` says.
+		humanoid.WalkSpeed = 0
+		humanoid.JumpPower = 0
+		humanoid.JumpHeight = 0
+	end
+
+	-- Phase 4.2 sends FeedUpdate(FEED_STARTED) here.
```

And the restore, in `endFeed`, **before** the `revert` call:

```diff
 	local player = Players:GetPlayerByUserId(userId)
 
 	if player ~= nil then
-		-- Phase 3.1 restores the movement lock here, BEFORE this line. See that step.
+		--[[
+			UNLOCK FIRST, THEN REVERT, AND BOTH WRITE THE SAME WALKSPEED.
+
+			`revert()` restores `BaseWalkSpeed` too — but only when the player is still `Transformed`,
+			and it early-returns otherwise. At least one path reaches here with that already false: the
+			tick's NOT_TRANSFORMED branch fires BECAUSE a revert has happened. Leaving the unlock to
+			`revert` would therefore strand WalkSpeed at 0 on exactly the path a salt hit takes, which
+			is the most common interruption in the game.
+
+			BaseWalkSpeed, NOT THE TRANSFORMED SPEED. C14 restored the captured transformed value onto
+			an un-transformed player and left one character in the barrio reading 20 while everyone
+			else read 16 — a permanent role brand with the full gate green over it.
+		]]
+		local character = player.Character
+		local humanoid = if character ~= nil
+			then character:FindFirstChildOfClass("Humanoid")
+			else nil
+
+		if humanoid ~= nil then
+			if monster.BaseWalkSpeed ~= nil then
+				humanoid.WalkSpeed = monster.BaseWalkSpeed
+			end
+
+			if monster.FeedBaseJumpPower ~= nil then
+				humanoid.JumpPower = monster.FeedBaseJumpPower
+			end
+
+			if monster.FeedBaseJumpHeight ~= nil then
+				humanoid.JumpHeight = monster.FeedBaseJumpHeight
+			end
+		end
+
+		monster.FeedBaseJumpPower = nil
+		monster.FeedBaseJumpHeight = nil
+
 		revert(player)
 	end
```

**The one path this does not cover, stated rather than papered over.** `endFeed` resolves the humanoid
from `player.Character`, which is the character the player has NOW. If the character was replaced
under the feed — a respawn, a `RoundService.LoadCharacterAsync` — the lock was applied to a body that
no longer exists and the restore writes to a fresh one that was never locked. Both are harmless: the
old body is gone, and the new one is being written its own honest baseline. `revert()` solves the
harder version of this problem by resolving `monster.AppliedTo` instead, and the feed deliberately
does not copy that: the lock is on a *living* character the player is currently driving, and the
right answer when it is replaced is to write the current one.

**UNVERIFIED ROBLOX BEHAVIOUR — this is the flag the brief asked for.** Nothing in this repo touches
`JumpPower`, `JumpHeight`, `UseJumpPower` or `SetStateEnabled` today (`grep -rn "JumpPower\|JumpHeight\|SetStateEnabled" src` finds nothing). Three things are therefore assumed and must be
confirmed by the playtester in Phase 5, not by this plan:

1. Whether zeroing both jump properties actually prevents a jump under this game's Humanoid
   configuration, or whether `Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)` is
   also required.
2. Whether a jump the client has already queued still fires after the write lands.
3. Whether the server's `WalkSpeed = 0` write is honoured promptly given client network ownership, or
   whether there is a visible slide before it takes.

**Anchoring `HumanoidRootPart` server-side is rejected rather than deferred.** It would be genuinely
authoritative, and it fights the client's character controller, has no precedent anywhere in this
codebase, and would make the feeder's body behave unlike every other living character in a way a
player will read as a bug. The leash already provides the authority; the lock only has to provide the
feel. If the playtester reports the lock is porous for an honest client, the fix is `SetStateEnabled`
or a tighter leash, not an anchor.

#### Step 3.2: Salt interrupts a feed, in the right order

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `lune run tests/monster-health.test.luau`

`ApplySaltHit` ends the feed FIRST, with no heal and no `FeedCompleted`, then does what V05 built:
revert, damage, expose. The ordering is the correctness.

**WHY EXPLICIT, WHEN THE TICK WOULD CATCH IT ANYWAY.** `ApplySaltHit` reverts, `monsterStateOf` stops
returning `FEEDING`, and the next `feedTick` reads `NOT_TRANSFORMED` and ends the feed. That backstop
is real and it stays. It is not sufficient, and the gap is a whole quarter of a second wide:

> Salt lands at t = 4.99 of a 5-second feed. The revert happens immediately. The tick runs at t = 5.05,
> reads a `FeedEndsAt` that has passed — and the ordering inside `feedTick` decides whether the monster
> gets healed by the feed a survivor just interrupted.

§4.3 calls interrupting a feed "a real victory". A victory that depends on which side of a 0.25s tick
the throw landed is not one, and nothing in the game would report it: the survivor sees the monster
break off, and the heal happens anyway. So the salt path ends the feed **deterministically, in the
same frame as the hit**, and the tick's version is what catches a revert from a source nobody has
thought of yet.

```diff
 function MonsterService.ApplySaltHit(player: Player)
+	--[[
+		THE FEED DIES FIRST (V06, §4.3). "Salt it mid-meal and it loses the heal and the camouflage
+		refresh, and has to leave the body."
+
+		BEFORE `revert`, NOT AFTER, AND NOT LEFT TO THE TICK. `endFeed` is what withholds both rewards
+		— it is the path that fires neither `HealFromFeed` nor `FeedCompleted` — and calling it here
+		makes the interruption exact. Left to `feedTick`'s NOT_TRANSFORMED backstop, a hit landing in
+		the last quarter-second of a feed races the deadline, and the outcome of §4.3's most important
+		counterplay would depend on tick alignment.
+
+		`endFeed` CALLS `revert` ITSELF, so the line below runs a second time and early-returns. That
+		redundancy is deliberate and cheap: this function's contract is "revert, damage, expose" and
+		removing its own revert on the grounds that a callee happens to do it would make the ordering
+		depend on `endFeed`'s internals.
+
+		SAFE FOR A PLAYER WHO IS NOT FEEDING, which is most salt hits. `endFeed` early-returns.
+	]]
+	endFeed(player.UserId, "FEED_INTERRUPTED")
 	revert(player)
 	applyHealthEvent(player.UserId, "SALT")
 	applyExposed(player)
 end
```

**One ordering fact worth checking at implementation time.** `endFeed` is a `local function` in the
feed block (before `commitKill`, ~line 890) and `ApplySaltHit` is a service-table method near the end
of the file, so the reference resolves. `ItemService` calls `MonsterService.ApplySaltHit(target)` at
`ItemService.luau:449` and needs no change — the seam V05 built is doing exactly the job its header
said it would, which is why the salt half of this chunk is four lines.

#### Step 3.3: The remaining exits — phase change, death, and leaving

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `lune run tests/body-transitions.test.luau`

`onPhaseChanged`, `watchCharacter`'s `Died`, and `onPlayerRemoving` all end any live feed before they
do anything else, on the same reasoning `clearExposed` was added to each of them at V05: **an exit
that clears the state but not the lock leaves a mark on a character, and a mark on a character is a
role brand.** V05 shipped `onPlayerRemoving` as a bare nil on the reasoning that "the entry goes and
the health goes with it", which was true of the number and false of the Highlight, and an exploit
audit traced it to a glowing husk standing in the barrio naming the round's Aswang. `WalkSpeed = 0`
is that failure with a cheaper instance and the identical shape.

```diff
 	for userId in monsters do
 		local player = Players:GetPlayerByUserId(userId)
 
+		--[[
+			AND EVERY LIVE FEED (V06, §4.3), BEFORE THE REVERT BELOW AND BEFORE `table.clear`.
+
+			`endFeed` restores the movement lock and then reverts, so this line does the loop's revert
+			for a feeder and the one below early-returns. Ordered this way rather than after, because a
+			revert that ran first would leave `Feeding` true on an entry `table.clear` is about to drop
+			— and with it a character whose WalkSpeed is 0 and whose owner is standing in the lobby.
+
+			`FEED_INTERRUPTED` RATHER THAN nil: the player is still here and their client is still
+			drawing a feed bar. The round ending is exactly the case where a client left holding a
+			stale bar looks like the game froze.
+		]]
+		endFeed(userId, "FEED_INTERRUPTED")
+
 		if player ~= nil then
 			revert(player)
 		end
 
 		clearExposed(userId)
 	end
```

```diff
 	humanoid.Died:Connect(function()
+		-- V06: a feeding Aswang that dies stops feeding, and gets its Humanoid back to the honest
+		-- baseline before anything else looks at it. Today only a fall or a reset reaches here — a
+		-- killed Aswang aborts the round — but V08's buntot pagi strike is a second way, and this is
+		-- the line that makes the feed end rather than tick on against a body that has no driver.
+		endFeed(player.UserId, "FEED_INTERRUPTED")
 		revert(player)
 	end)
```

```diff
 local function onPlayerRemoving(player: Player)
+	--[[
+		THE FEED GOES BEFORE THE ENTRY DOES (V06), for the reason the line below this one exists.
+
+		V05's comment here is the whole argument and it applies unchanged: nilling the entry forgets
+		the state, it does not undo what the state did to the world. `RoundService.onPlayerRemoving`
+		reparents the departing character into `workspace.Husks` as `Husk_{userId}`, and MonsterService
+		runs FIRST in SERVICE_ORDER — so a feed left un-ended here becomes a husk standing in the
+		barrio with WalkSpeed 0 and jumping disabled, which is one property scan away from naming the
+		round's Aswang. `feedTick`'s `player == nil` branch would eventually reach it and find the
+		entry already gone.
+
+		nil VERDICT, NOT `FEED_INTERRUPTED`: there is nobody left to send it to, and `FireClient` to a
+		departing player is a warn in the log for no benefit. Same contract as
+		`SearchService.releaseHold`'s nil case.
+	]]
+	endFeed(player.UserId, nil)
+
 	clearExposed(player.UserId)
 
 	monsters[player.UserId] = nil
 end
```

**A fifth exit that needs no code, recorded so nobody adds it.** `player.CharacterRemoving` already
fires `clearExposed` in `onPlayerAdded`. A feed does not need a hook there: the character going away
means `feedDistance` returns nil, which the tick reads as `OUT_OF_RANGE` and ends the feed within a
quarter-second — and the lock died with the body it was applied to, so there is nothing to restore.
Adding a `CharacterRemoving` handler would restore a lock onto whatever character replaced it, which
is the one thing that could actually go wrong here.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private
  one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the
  other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply
  here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **This phase's three checks do not prove this phase.** `npm run test:unit`,
  `lune run tests/monster-health.test.luau` and `lune run tests/body-transitions.test.luau` are
  tree-wide suites that can genuinely fail if the edits break something they cover, and none of them
  runs a Humanoid, a tick or an exit path. That is the honest ceiling for DataModel code and it is
  why Phase 5's playtester artifact is a step rather than a courtesy. `verify-plan` will not report
  these as weak — they are runnable and discriminating — so this bullet is the disclosure.
- **The `WalkSpeed = 0` brand is the highest-severity thing in the chunk.** Six exits, one restore.
  The way to check it is not to read the six: it is to confirm that all six go through `endFeed` and
  that `endFeed` restores unconditionally. If a seventh exit is ever added, it goes through `endFeed`
  or it is a bug. **`exploit-auditor` must be asked this specific question** — see Phase 5.
- **Jumping is the unverified half.** Zeroing `JumpPower` and `JumpHeight` is the plan's best guess
  from outside Studio, and the plan says so rather than asserting it works. If the playtester finds a
  feeder can hop out of the leash, the follow-up is `SetStateEnabled`, and it is a one-line change to
  two functions.
- **Player leaving mid-round (§6.4) is covered three times**: `onPlayerRemoving` (explicit),
  `feedTick`'s `player == nil` branch (the window before it fires), and `onPhaseChanged`'s loop (the
  round ending underneath everything). That is deliberate over-cover on the path V05 got wrong.
- **`ApplySaltHit` now calls `endFeed`, which calls `revert`, and `ApplySaltHit` then calls `revert`
  again.** Verify by reading `revert`'s first lines that the second call is a clean early return
  (`monster == nil or not monster.Transformed`), and leave it in place — see the step's note.
- **No new remote, no new handler, no new Config number in this phase.** Three of the nine checks
  above are vacuous here; `check:config` sees only `0`, which is on its IDIOMATIC list.

---

### Phase 4: The remote surface and the client

One DOWN remote, one send site, one controller. No up-remote, and a check that proves it.

#### Step 4.1: Declare `FeedUpdate` in `Remotes.luau`'s `EVENTS_DOWN`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

In the DOWN list with the payload argument written out, in the shape `SearchUpdate`'s entry set.

**Why a down remote at all, when the feed is meant to be visible.** The feed's *public* half needs no
remote — a transformed monster standing on a body is the whole tell, and it replicates for free. The
*private* half does: without it, the Aswang's screen shows a character that has stopped responding to
input for five seconds with no explanation, which every player reads as a freeze. §10 calls the FTUE
the place the competitor actually died. One remote, to one player, about that player.

**`check:remotes` is not optional here and its failure mode is the reason.** A client
`WaitForChild`ing a name the server never created **hangs forever** — no error, no output, no stack
trace. `FeedController` would simply never start and nothing would say so.

```diff
 	"NoiseCue",
+	--[[
+		V06, §4.3. FireClient to the ONE player whose feed it is. Never FireAllClients — there is no
+		broadcast form of this payload and adding one would be a redesign, not an optimisation.
+
+		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The public
+		half of a feed is that a monster is standing on a body in the open for five seconds, which is
+		§4.3's entire design — "a corpse becomes bait… survivors now know exactly where the monster is
+		and exactly how long it will be there" — and it needs no remote at all. It replicates as
+		geometry and it is meant to be seen.
+
+		IT IS NOT A ROLE ORACLE, AND THE ARGUMENT IS `RoleAssigned`'S. Only the Aswang can ever receive
+		this, which is exactly the property that makes it safe rather than dangerous: it is fired to a
+		single player and carries only that player's own business, so the set of clients that learn
+		anything from it is the set of clients that already knew. `check-secrecy.mjs` allowlists
+		`RoleAssigned` on that reasoning and this remote does not need allowlisting at all, because
+		`Types.FeedUpdatePayload` contains no role, no UserId and no health.
+
+		THE PAYLOAD NAMES NO VICTIM AND NO BODY. Deliberate, and for `SearchUpdate`'s structural reason:
+		with no id in the payload there is nothing for a compromised client to log, difference or
+		accumulate. The feeder is standing on the corpse — a field naming it would be the server
+		telling a client what it is looking at.
+
+		AND NO HEALTH, IN ANY FORM. §4.6: "a health value attached to a player is the reveal." A feed
+		changes the Aswang's health by FeedHeal and this remote still says nothing about it; the only
+		licensed readout is the Exposed glow's brightness, which exists only while the licence does.
+
+		FEEDING EMITS NO `NoiseCue`, EITHER, AND THAT IS A REFUSAL RATHER THAN AN OMISSION. §4.4's four
+		noisy actions are SEARCH, ITEM_USE, DOOR and SPRINT. A fifth for feeding would be the first
+		mechanic in this game whose noise ONLY ONE ROLE CAN PRODUCE — a cue no survivor could ever have
+		caused, delivered to every listener in radius. That is `.claude/lessons/absence-is-observable.md`
+		inverted into a presence, and `check:secrecy` would be green over it.
+	]]
+	"FeedUpdate",
 }
```

#### Step 4.2: Fire it to the feeder, and only to the feeder

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:ratelimit`

`sendFeedUpdate` as the one send site, a typed local payload, `FireClient`. The verify is on point
rather than incidental: this step's whole claim is that no new `OnServerEvent` handler exists, and
`check:ratelimit` is the gate that fails if one appeared unguarded.

**THE ANSWER TO "DOES FEEDING NEED `RequestFeed`" IS NO, AND THIS STEP IS WHERE THAT IS PROVEN RATHER
THAN ASSERTED.** §4.3: "After a kill, the Aswang **must** feed on the corpse for 5 seconds." An
opt-in feed is one the Aswang declines, and once the cooldown has stopped being the gate, declining
costs nothing — which deletes §4.3's own stated property that the monster "cannot chain-kill, because
it is pinned to the body it just made". So the feed is a consequence, `commitKill` starts it, and this
chunk adds **zero** `OnServerEvent` handlers, **zero** `AntiCheatService.Consume` sites and **zero**
`Config.AntiCheat.Budgets` entries. `npm run check:ratelimit` passing is the mechanical statement of
that; if a future chunk ever adds a `RequestFeed`, it gets a budget entry priced like
`RequestTransform` and a `Consume` inside the connect site, and this check is what will say so.

The remote handle goes beside the two that already exist near the top of the file:

```diff
 local transformedRemote = Remotes.Get("MonsterTransformed")
 local killedRemote = Remotes.Get("PlayerKilled")
+local feedRemote = Remotes.Get("FeedUpdate")
```

The send site, at the head of the feed block so the three lifecycle functions can all reach it:

```diff
+--[[
+	THE ONLY FUNCTION IN THIS FILE THAT SENDS ANYTHING ABOUT A FEED. FireClient, to one player.
+
+	A TYPED LOCAL RATHER THAN AN INLINE TABLE, for `SearchService.sendUpdate`'s reason: `FireClient`
+	takes `...any`, so an inline literal is checked against nothing and a typo'd field name ships. The
+	annotation is what makes `Types.FeedUpdatePayload`'s absent-field argument enforceable rather than
+	aspirational, and it is what `check-secrecy.mjs` resolves the payload back to when it scans the
+	fire site.
+
+	`HoldSeconds` IS ZERO ON EVERY ENDING. Only a live feed has a duration; a completion and an
+	interruption both send 0, so a client cannot read a timing difference off which one it got.
+	`SearchUpdatePayload` sets the same rule for the same reason.
+]]
+local function sendFeedUpdate(player: Player, verdict: Types.FeedVerdict)
+	local payload: Types.FeedUpdatePayload = {
+		Verdict = verdict,
+		HoldSeconds = if verdict == "FEED_STARTED" then Config.Monster.FeedDuration else 0,
+	}
+
+	feedRemote:FireClient(player, payload)
+end
```

Three call sites replace the three comment markers Phases 2 and 3 left behind:

```diff
 	if verdict == nil then
 		return
 	end
 
-	-- Phase 4.2 sends FeedUpdate here.
+	-- The player may have left between the top of this function and here; `endFeed`'s nil-verdict
+	-- callers are the ones who know that, but a re-check costs a comparison and a departing player is
+	-- a warn in the log otherwise.
+	if player ~= nil then
+		sendFeedUpdate(player, verdict)
+	end
 end
```

```diff
 	MonsterService.FeedCompleted:Fire(player)
 
-	-- Phase 4.2 sends FeedUpdate(FEED_OK) here.
+	--[[
+		FEED_OK LAST, after the heal and after V07's seam. The client is being told a thing that has
+		already fully happened server-side — it draws no conclusion the server has not already reached,
+		and it cannot be raced by a listener that errors.
+
+		`endFeed` ABOVE WAS PASSED nil PRECISELY SO THIS LINE IS THE ONLY MESSAGE. Two messages for one
+		ending — FEED_INTERRUPTED then FEED_OK — is `SearchService.releaseHold`'s stated failure mode.
+	]]
+	sendFeedUpdate(player, "FEED_OK")
 end
```

```diff
-	-- Phase 4.2 sends FeedUpdate(FEED_STARTED) here.
+	sendFeedUpdate(player, "FEED_STARTED")
 end
```

#### Step 4.3: `FeedController` — what the five seconds look like from inside

**File:** `src/client/Controllers/FeedController.luau`
**Verify:** `test -f src/client/Controllers/FeedController.luau`

Owns no truth: it holds a deadline between two server messages so a bar can be drawn, and drops it
the moment the server says otherwise. Registered in `src/client/init.client.luau`'s ordered list.

This is `SearchController` with a different noun, and copying it is the right call rather than a lazy
one — it is 111 lines, it already solved "draw a hold between two messages without letting the client
decide the outcome", and its header is the argument this file needs to make too.

```diff
+--!strict
+--[[
+	FeedController — what the five seconds look like from inside. (V06, §4.3)
+
+	OWNS NO TRUTH, and here that is not a slogan either. The server decides whether a feed started,
+	whether it finished and whether the heal was paid; this file holds a deadline so a bar can be drawn
+	between two messages, and drops it the moment the server says otherwise. A client-side timer that
+	completed on its own would be a client deciding it had healed.
+
+	IT IS THE ONLY CONTROLLER ONLY ONE PLAYER EVER RUNS MEANINGFULLY, and that is worth stating because
+	it looks like a secrecy problem and is not. Every client loads this file — `src/client/` is
+	replicated wholesale — and every client connects the handler. Four of the five never receive a
+	payload, so the branch never runs, and nothing about that is observable to anyone but themselves.
+	The asymmetry that WOULD leak is on the server side and there is none: `FeedUpdate` is FireClient
+	to the feeder, never a broadcast, so no client can time or count another's feeds.
+
+	NO NEW HUD, AND NO HEALTH READOUT. §4.6 is explicit that a health value attached to a player is the
+	reveal, so a "you healed 25" line is not a thing this file may draw even to the Aswang — the moment
+	it exists, a screen recording of an Aswang's client is a document of the health system, and the
+	number has one home on the server. The feed renders through `OnboardingController.ShowLine`, which
+	`SearchController` and `TeachingService` already use this way, plus whatever bar `UIController`
+	draws from `IsFeeding()`.
+
+	NO INPUT, EITHER. There is no RequestFeed and there is nothing to press — §4.3 makes the feed a
+	consequence of a kill, not a choice — so this controller listens and never fires.
+]]
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local OnboardingController = require(script.Parent.OnboardingController)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Types = require(Shared.Types)
+local Remotes = require(Shared.Remotes)
+
+local FeedController = {}
+
+-- os.clock() at which the current feed is due to finish, or nil when not feeding. A DISPLAY estimate:
+-- the server owns the real deadline and re-derives it four times a second.
+local feedEndsAt: number? = nil
+
+function FeedController.IsFeeding(): boolean
+	return feedEndsAt ~= nil
+end
+
+--[[
+	SECONDS LEFT, FOR WHOEVER DRAWS THE BAR. Clamped at zero rather than allowed to go negative: the
+	server's tick can land up to a quarter-second after the deadline, and a bar that reads -0.2 for a
+	frame is the kind of thing that ships.
+]]
+function FeedController.SecondsRemaining(): number
+	local endsAt = feedEndsAt
+
+	if endsAt == nil then
+		return 0
+	end
+
+	return math.max(endsAt - os.clock(), 0)
+end
+
+local function onUpdate(payload: Types.FeedUpdatePayload)
+	if payload.Verdict == "FEED_STARTED" then
+		feedEndsAt = os.clock() + payload.HoldSeconds
+		OnboardingController.ShowLine("Feeding.")
+		return
+	end
+
+	-- Both endings drop the deadline. THE CLIENT NEVER COMPLETES A FEED ON ITS OWN — if this file
+	-- decided that `os.clock() >= feedEndsAt` meant success, a client whose FEED_INTERRUPTED was
+	-- dropped would draw a heal that did not happen.
+	feedEndsAt = nil
+
+	if payload.Verdict == "FEED_INTERRUPTED" then
+		-- ONE LINE FOR ALL SIX INTERRUPTION PATHS. `Types.FeedVerdict` collapses them on purpose:
+		-- telling the Aswang whether that was salt or a drift is a fact about a survivor's aim.
+		OnboardingController.ShowLine("Interrupted.")
+		return
+	end
+
+	-- §4.3: the feed restored health and, once V07 lands, the ability to hide. NO NUMBER — §4.6 says
+	-- a health value attached to a player is the reveal, and that holds on the monster's own screen.
+	OnboardingController.ShowLine("Fed.")
+end
+
+function FeedController.Init()
+	feedEndsAt = nil
+end
+
+function FeedController.Start()
+	Remotes.Get("FeedUpdate").OnClientEvent:Connect(onUpdate)
+end
+
+return FeedController
```

And the registration, in `src/client/init.client.luau`'s ordered list — **after**
`OnboardingController`, which this file requires for `ShowLine`, and beside `SearchController` for
the same stated reason:

```diff
 	"SearchController",
+	--[[
+		V06. AFTER OnboardingController, and that ordering is a real dependency rather than a
+		preference: this controller REQUIRES it, for `ShowLine`. One-way, exactly as SearchController's
+		is — OnboardingController knows nothing about feeding, so the arrow cannot become a cycle.
+	]]
+	"FeedController",
 	"TrialController",
 	"InputController",
```

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private
  one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the
  other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply
  here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Remote direction is the check that matters and its failure is silent.** `FeedUpdate` goes in
  `EVENTS_DOWN`, is fired with `FireClient` on the server, and is listened to with `OnClientEvent` on
  the client. Put it in `EVENTS_UP` by mistake and the client's `WaitForChild` hangs forever with no
  error — `check:remotes` exists for exactly that and is Step 4.1's verify.
- **`FeedController` is required by every client and meaningfully runs for one.** Argued in the file
  header. The thing to confirm is the server side: `feedRemote:FireClient(player, payload)` and never
  `FireAllClients`. There is one send site, which is what makes that confirmable by reading one
  function.
- **`OnboardingController.ShowLine` is a hard dependency and the registration order enforces it.** If
  `FeedController` is registered before `OnboardingController`, the `require` at the top resolves a
  module whose `Init` has not run. `SearchController` and `TrialController` both carry this note in
  the bootstrap already; copy the placement, do not reason about it fresh.
- **No new light, particle or per-frame client work.** `SecondsRemaining` is pull-based — whoever
  draws the bar calls it from a loop it already has — rather than a `RenderStepped` this file owns.
  §5's mobile budget is untouched.
- **The visual half of a feed is not in this plan at all.** No animation, no eating effect, no sound.
  §4.3 wants the feed visible and the transform already is; a feeding pose is a place-file and asset
  question that `asset-pipeline` owns, and it is in Follow Ups rather than as a step nobody could
  verify.

---

### Phase 5: The gate, the scope sweep, and the evidence

#### Step 5.1: Document the V07 seam in `MonsterService`'s header and sweep for scope

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:scope`

The header's "four seams" block becomes five, `HealFromFeed`'s comment stops saying "unwired", and
the sweep confirms no V07 vocabulary (camouflage, smoke, forms) crept in.

```diff
 	THE FOUR SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:
 
 	  · `ApplySaltHit(player)` — V08. Revert, -SaltDamage floored at WeakenedThreshold, Exposed for
 	    SaltRevealDuration. The ONLY entry point for a salt hit; there is no bare `ForceRevert` any
 	    more, precisely so a caller cannot revert without damaging.
-	  · `HealFromFeed(userId) -> boolean` — V06, on a COMPLETED feed. Returns whether state existed,
-	    never the health. Does not restore camouflage; that is V07's half of §4.3's reward.
+	  · `HealFromFeed(userId) -> boolean` — WIRED AT V06, called by `completeFeed` and by nothing else.
+	    Returns whether state existed, never the health. Does not restore camouflage.
+	  · `FeedCompleted` (BindableEvent) — V07'S SEAM, ADDED AT V06 AND CONNECTED TO BY NOTHING. Fires
+	    with the feeding Player on a COMPLETED feed and never on an interrupted one. §4.3 gives a
+	    completed feed two rewards and V06 pays one: this event is where V07 hangs the other. The
+	    reason the heal and the camouflage refresh cannot come apart is that `completeFeed` is the only
+	    caller of `HealFromFeed` AND the only firer of this event, and `endFeed` — which all six
+	    interruption paths go through — does neither.
 	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
 	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
```

And the "WHAT THIS SERVICE DOES NOT SEND" block gains V06's paragraph, next to V05's:

```diff
+	V06 ADDS ONE REMOTE AND IT GOES TO ONE PLAYER. `FeedUpdate` is FireClient to the feeder, carrying
+	a three-value verdict and a duration the client already had from replicated Config. There is no
+	broadcast form. The PUBLIC half of a feed needs no remote at all and never gets one: a transformed
+	monster standing on a body for five seconds is §4.3's "corpse becomes bait" rendering itself, and
+	it replicates as geometry.
+
+	FEEDING EMITS NO NOISE CUE, AND THAT IS A REFUSAL. §4.4 names four noisy actions and feeding is
+	not one. A fifth would be the first cue in this game only one role can cause — see `Remotes.luau`'s
+	`FeedUpdate` entry for the full argument. `check:secrecy` would be green over it.
+
+	THE ONE REPLICATED DIFFERENCE A FEED CREATES IS `WalkSpeed = 0`, on a character already in monster
+	form and already announced, for exactly FeedDuration seconds. `endFeed` is the single restore path
+	and all six exits go through it; a seventh exit that does not is the C04/C14 brand again.
```

**The scope sweep, and what it is looking for.** §3's OUT list and `check:scope` both bar the V07
vocabulary this chunk sits right next to. The specific temptation is real: making the interruption
"cost the camouflage refresh" *feels* like it needs a camouflage charge to take away. It does not —
it needs a completion path that does not fire. Confirm that `grep -rni "camouflage\|smoke\|disguise"
src --include="*.luau"` finds only comments naming V07 as the owner, and no field, no Config number,
no remote and no state.

#### Step 5.2: The full gate, and the auditor briefs

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify`

`npm run verify` is analyze + lint + format + the five checks + the Lune suites + the harness
self-tests. Then launch the reviewers **concurrently, in one message, with `run_in_background: true`**,
and scope both briefs — an unscoped brief costs three times a scoped one and returns less.

**`exploit-auditor` is not a judgement call on this diff.** It touches `src/server/**`,
`Remotes.luau` and `MonsterService`; `review-gate.mjs` names it automatically for those paths. Brief
it with these five questions and nothing else:

> Audit **V06 feeding** — `.claude/plans/feature-v06-feeding-plan/`, load with
> `npm run plan:phase -- <plan> <N>`. Files: `MonsterService.luau`, `Remotes.luau`,
> `pure/FeedRules.luau`, `FeedController.luau`. Answer:
> (1) Can any client learn that a feed is happening, or has happened, other than by looking at a
> monster it can already see? Include attributes, tags, replicated Humanoid properties and timing.
> (2) `WalkSpeed = 0` and the two jump properties are written on `beginFeed`. Enumerate every path out
> of a feed and prove each one restores them. A path that does not is a permanent role brand — this is
> C04's revert and C14's stun in a third costume.
> (3) Can a compromised client keep a feed alive while moving, or complete one it should have lost?
> The leash in `feedTick` is the claimed authority; the lock is not.
> (4) `commitKill` no longer reverts. Is there any path where a feed neither starts nor reverts,
> leaving a permanent monster? `beginFeed`'s refusal branch is the claimed answer.
> (5) Does `FeedUpdate`'s payload, or the fact of receiving it, distinguish any two players to a third?

**`auditor`** (not `change-auditor` — a plan directory exists) traces every step to a `file:line` and
an `implementation-log.md` entry. Brief it on **the plan as a whole**, since the phases interlock:
the deferred revert in Phase 2 is only safe because of the restore in Phase 3 and the refusal branch
in Phase 2.3.

#### Step 5.3: Record a completed feed and a salt-interrupted feed in Studio

**File:** `.claude/plans/feature-v06-feeding-plan/artifacts/feed-complete.png`
**Verify:** `test -f .claude/plans/feature-v06-feeding-plan/artifacts/feed-complete.png`

The build plan's own Verify line: "playtester records a feed and a salt-interrupted feed in Studio".
**Set the Config debug values yourself before launching it — it cannot edit `Config.luau` and will
correctly refuse.** `Round.Intermission/Duration/EndScreen` to 8/20/6 plus `Debug.SoloTesting` and
`Debug.VerboseLogging`; revert all five afterwards and confirm with `git diff src/shared/Config.luau`.
`guard-commit.mjs` runs `check:debug` and refuses to commit them.

**The six questions the artifacts must answer.** Three of them are the unverified Roblox behaviour
this plan refused to guess at, and they are the reason this step exists rather than being a courtesy:

1. **Does the lock hold for an honest client?** Kill, then try to walk. Does the character move at
   all in five seconds?
2. **Does jumping still work?** Zeroing `JumpPower` and `JumpHeight` is this plan's best guess from
   outside Studio. If a feeder can hop, the fix is
   `Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)` and it is two lines.
3. **Is there a visible slide before the lock lands?** The server writes `WalkSpeed` on a character
   the client has network ownership of.
4. **Does the feed complete and heal?** With `VerboseLogging` on, the server prints its refusals; a
   completed feed prints nothing, so the evidence is the absence of a refusal plus a second salt hit
   later still not killing (the heal restored the margin).
5. **Does salt interrupt it?** Throw during a feed. The expected observation: the monster reverts,
   glows, and the feed bar goes away — and a `[MonsterService] Feed broken` line does NOT appear,
   because `ApplySaltHit` ended it deterministically rather than leaving it to the tick.
6. **Does the killer revert at all?** The whole chunk moved the revert. A monster that is still a
   monster fifteen seconds after a kill is the failure mode with no other symptom.

**And one thing the playtester cannot do**, recorded so nobody asks: player count is a UI action no
agent can drive, and `execute_luau` cannot read a live service's private state — so `monsters[userId]
.Health` is not readable from a Studio command. The heal is confirmed behaviourally (question 4) or
not at all. `.claude/agents/playtester.md` has both traps in full.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private
  one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the
  other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply
  here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **A green `npm run verify` over this chunk means very little on its own, and the repo has the
  receipt.** C04's revert bug shipped with `analyze`, all five checks and six Lune suites green over a
  Critical secrecy failure; only `exploit-auditor` found it. This chunk writes a replicated Humanoid
  property on one character and moves the revert that ends a transform. Static green is the floor
  here, not the ceiling.
- **`test -f` on an artifact proves a file exists, not that it shows the right thing.** `goal-check
  .mjs` calls this out itself — the artifact check is "the strongest proxy and still a proxy". The six
  questions above are what turn it into evidence; a screenshot with no answer to question 2 leaves the
  jump lock unverified regardless of the exit code.
- **Reverting the debug Config values is a step people forget** and `guard-commit.mjs` will block the
  commit rather than let them through, which is the harness working. Confirm with
  `git diff src/shared/Config.luau` before committing.
- **Do not launch the playtester if Rojo is not syncing.** `npm run preflight -- --studio` reports
  three separate facts and only `rojo-synced` licenses evidence; an unblessed session reads as
  not-proven. An empty `ReplicatedStorage` in `search_game_tree` means Rojo never synced and the
  playtester establishes nothing.

---

## 3. Related Files

Every file below has an annotated review in `references/`, cited by line range so a reader can check
whether the live code has moved since.

**Created by this plan**

| File | Phase | What it is |
| --- | --- | --- |
| `src/shared/pure/FeedRules.luau` | 1.2 | `evaluate` and `mayContinue` over state × body × distance × phase |
| `tests/feed-rules.test.luau` | 1.3 | The grid, both functions, plus precedence and degenerates |
| `src/client/Controllers/FeedController.luau` | 4.3 | The feeder's own five seconds, drawing no truth |

**Modified by this plan**

| File | Phase | Change |
| --- | --- | --- |
| `src/shared/Config.luau` | 1.1 | `Monster.FeedLeashStuds`; the `KillCooldown` comment |
| `src/shared/Types.luau` | 1.4 | `FeedVerdict`, `FeedUpdatePayload` |
| `tests/config.test.luau` | 1.5 | §6.5 invariant 2 and two supporting relationships |
| `src/server/Services/MonsterService.luau` | 2, 3, 4.2, 5.1 | The whole feed; the deferred revert; the lock |
| `src/shared/Remotes.luau` | 4.1 | `FeedUpdate` in `EVENTS_DOWN` |
| `src/client/init.client.luau` | 4.3 | `FeedController` in the ordered list |

**Read while planning, unchanged by it** — `docs/BUILD-PLAN.md` (§V06), `docs/MVP-SPEC.md`
(§4.3, §4.6, §4.7, §6.2, §6.5), `src/shared/Enums.luau`, `src/shared/pure/MonsterHealth.luau`,
`src/shared/pure/PlayerBody.luau`, `src/shared/pure/BodyTransitions.luau`,
`src/shared/pure/KillValidation.luau`, `src/shared/pure/TransformRules.luau`,
`src/shared/pure/SaltThrow.luau`, `src/server/Services/SearchService.luau`,
`src/server/Services/ItemService.luau`, `src/client/Controllers/SearchController.luau`,
`.claude/lessons/pure-module-unions-widen-in-lists.md`,
`.claude/plans/feature-v05-monster-health-plan/`.

## 4. Follow Ups

### Questions / Clarifications

**1. `Config.Monster.KillCooldown` is still alive and the spec says it should not be. This is the
conflict this plan raises rather than resolves.** §4.3 is unambiguous — "v2.0 replaces the timer with
an action" — and `Config.luau:240-244` says the number "dies with the chunk that builds feeding",
which is this one. It did not, because it has six live readers (two pure modules, three MonsterService
call sites, three Lune suites) and removing it is a mechanical edit with a real balance consequence:
an Aswang with no cooldown may re-transform the instant it reverts. **Recommended: its own chunk,
subject line `balance(monster):`, sized as Medium** — the edit is `Cooldown` leaving
`TransformRules.Request` and `KillValidation.Request`, three assertions leaving `config.test`, and a
playtest question ("does an always-available transform make the monster boring or terrifying?") that
belongs at V16. **Do not fold it into V06's implementation**; a plan step that deletes a live reader
is refused, and the two changes want different evidence.

**2. What actually replaces the cooldown's job, if it goes?** Worth deciding before the chunk above
is written, because "nothing" is a defensible answer and it should be a chosen one. §4.3's argument is
that the feed IS the cost, and `MaxTransformTime`'s forced revert plus the feed's five-second pin are
the whole rate limit. That gives a monster roughly one kill per 13 seconds of committed, visible time.
Whether that is fast is a V16 question and this plan does not have an opinion.

**3. `Config.Trial.PlayerBaselineWalkSpeed` is the only statement in `Config` of how fast a player
walks, and invariant 2 now reads it to check a round mechanic.** That coupling is odd — a trial number
governing a feed — and it is correct today because there is no other. If `Round` or a new `Player`
block ever gains a walk speed, invariant 2 and the two `Trial` assertions that already read it should
move together.

**4. `FeedLeashStuds = 6` has no playtest behind it.** It is bounded below `KillRange` by an
invariant and it is otherwise a guess. V16 tunes it. The specific thing to watch: a corpse is a
ragdolled avatar with some spread, so "standing on the body" may measure further from the root part
than six studs in practice — question 1 of Phase 5.3's artifact list is where that first shows up.

**5. A feed has no visual and no sound, and §4.3 wants it visible.** The transform already provides
the silhouette; a feeding *pose*, an audio cue, or a particle at the corpse are asset questions that
`asset-pipeline` owns and that live in the place file, which is outside Git. Deliberately not a step
in this plan — "build the feeding animation" is not verifiable from a terminal. Worth a small chunk
alongside V07's forms, when the art pass happens.

**6. V07 must revisit `monsterStateOf`.** V06 derives three of `Enums.MonsterState`'s five values and
never returns `EXPOSED` or `CAMOUFLAGED`, with the reasoning in the function's comment. V07 adds a
producer for `CAMOUFLAGED` and will have to decide whether the derivation grows a fourth branch or
whether the whole flags-versus-field question `Enums.luau:62-72` deferred finally gets answered. It
should be answered in V07's plan, not discovered in V07's diff.

**7. Proximity inference at the moment of a kill is unchanged and still open.** `MonsterService`'s
header records it: a client reading replicated character positions at the instant of the
`MonsterTransformed` broadcast can see who was within eight studs. V06 makes the monster stand still
at that spot for five more seconds, which does not create the inference but does extend the window in
which it can be made comfortably. The counter is design rather than code — §4.3 wants the monster
standing there visibly — and it is recorded here rather than papered over.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 2 | `commitKill` no longer reverts, so a `beginFeed` that refuses without reverting leaves a permanent monster — and Step 2.5's forced-revert clause means the 8s timer will not rescue it | High | Handled in the plan: `revert(player)` in `beginFeed`'s refusal branch, called out in Step 2.3 and in Phase 2's issues |
| 3 | `WalkSpeed = 0` replicates; a feed ending without restoring it is a permanent, map-wide role brand invisible to `check:secrecy` — the C04/C14 shape a third time | Critical | Handled: one restore path (`endFeed`), six exits all routed through it, plus "do not lock what you cannot unlock". Question 2 of the `exploit-auditor` brief |
| 3 | Salt landing in the last 0.25s of a feed could still pay the heal if the interruption were left to `feedTick`'s backstop | High | Handled: `ApplySaltHit` calls `endFeed` in the same frame; the tick's version stays as a backstop |
| 2 | `transform`'s `MaxTransformTime` timer would force a revert mid-feed for any kill made after t=3 of a transform | High | Handled: `and not monster.Feeding` in the timer, plus `FeedDuration < MaxTransformTime` pinned in `config.test` |
| 3 | Zeroing `JumpPower`/`JumpHeight` is unverified Roblox behaviour in this codebase — nothing here touches those APIs | Medium | Open by design. Flagged, not guessed; question 2 of Phase 5.3's artifact list settles it |
| 1 | The feed grid's expectation could be written with the module's own branch order, making 750 checks a tautology | Medium | Handled: the oracle is §4.3 as one conjunction; precedence is a separate explicit table |
| 1 | `BODIES` has a trailing `nil`, so a generic-for silently drops a third of the grid and reports green | Medium | Handled: numeric for over `#BODIES + 1`, with the reason in the file and in Step 1.3's notes |
| 2 | The feed block has exactly one legal position in the file (after `rootOf`, before `commitKill`); both obvious placements fail to compile | Medium | Handled: the table in Step 2.2 states every ordering constraint |
| 4 | A `FeedUpdate` placed in `EVENTS_UP` makes the client's `WaitForChild` hang forever, with no error | Medium | Handled: `check:remotes` is Step 4.1's verify |
| 1 | `Config.Monster.KillCooldown` survives a chunk whose spec section says it should not | Medium | Open by decision. Argued in the Preamble and in Follow Up 1; wants its own `balance(monster):` chunk |
| 5 | Three of Phase 3's steps carry checks that run and can fail but do not prove the step | Low | Disclosed in the Preamble and in Phase 3's issues rather than dressed up; Phase 5.3 is the proof |
