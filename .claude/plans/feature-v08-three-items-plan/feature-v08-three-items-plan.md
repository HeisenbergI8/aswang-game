# Plan: V08 — ItemService: the three items

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V08 (`docs/BUILD-PLAN.md`, "ItemService: the three items"). Deps V03, V05. 🔒
- **Description:** Generalise the shipped salt-only carry/throw into a one-slot, three-item system fed
  by V03's containers. `SaltCarry`/`SaltThrow` become `ItemCarry`/`ItemThrow` with their ~70
  assertions carried over. Salt's five jobs are proven end to end. Bawang and buntot pagi are carried
  and dropped only — their effects are V09 and V10.
- **Date:** 2026-08-29
- **What the client is told:** Nothing new about anybody else. One field starts being *produced* that
  the type already declares — `ClientRoundSnapshot.YourCarriedItem` (`src/shared/Types.luau:464`),
  which is per-player, `FireClient`-only, and `nil` for an empty-handed survivor and for the Aswang
  alike. One new client→server remote, `RequestDropItem`, argument-free. No new server→client remote,
  no addition to `check-secrecy.mjs`'s `REVEAL_ALLOWLIST`, no new attribute and no new tag on a
  character.

### 1.1 The finding that reshapes this chunk — read before Phase 1

**Salt's five jobs are already implemented.** `MonsterService.ApplySaltHit`
(`src/server/Services/MonsterService.luau:2926-3011`) already exits camouflage, calls
`endFeed(userId, "FEED_INTERRUPTED")`, calls `revert`, calls `applyHealthEvent(userId, "SALT")`, calls
`applyExposed`, and sets `HasBeenRevealed` through `CamouflageRules.revealedAfter(flag, "SALT_HIT")`.
V05, V06 and V07 each landed their own share of it, in order, with the ordering reasoning written into
the function.

So **V08 does not build the five jobs. V08 proves them and stops anything from taking them apart.**
The construction work in this plan is all on the other side of the seam:

| V08's real work | Where |
| --- | --- |
| Items come from V03 containers, not from `SaltSpawn` points | Phase 3 |
| One SLOT holding one of three item types, not a salt COUNT | Phases 1, 3 |
| Dropping, so a second item can be picked up | Phases 2, 4 |
| The pure modules generalise, keeping their assertions | Phase 1 |
| The carried item does not become a role tell | Phase 5 |

A phase that starts rewriting `ApplySaltHit` has misread this section.

### 1.2 The V09/V10 boundary, stated so nobody reads this chunk as under-delivered

`docs/MVP-SPEC.md` §4.6 gives bawang a doorway block and buntot pagi a conditional kill. **Neither is
in V08.** V08 gives all three item types the same carry, drop and slot machinery, and gives salt its
use verb. Bawang and buntot pagi are objects you can hold and put down and nothing else.

This is not an omission to be quietly fixed by an implementer who has spare capacity. It is pinned
mechanically in Phase 4 by `pure/ItemUse`, whose test asserts that `BAWANG` and `BUNTOT_PAGI` answer
`NOT_IMPLEMENTED` today. V09 flips one cell of that table and V10 flips the other, and each flip is a
red test until the effect behind it exists.

### 1.3 Constraints every phase inherits

Repeated here rather than cross-referenced, because `npm run plan:phase` serves one phase at a time
and a rule stated only inside Phase 3 does not exist for whoever implements Phase 5.

- **`Config.Items` is canonical; `Config.Salt` is a shrinking alias table.** `src/shared/Config.luau:12-25`
  says so and `tests/config.test.luau:154-174` pins the four aliases. Every new number this chunk needs
  goes in `Items`. Each `Config.Salt` key whose last reader this chunk renames is DELETED in the same
  step, and its `tests/config.test.luau` alias assertion with it.
- **The client only requests.** The server resolves what a player is standing at from that player's own
  character position, and the client names nothing. This is `ItemService`'s own stated rule
  (`src/server/Services/ItemService.luau:16-20`) and `RequestSearch`'s (`src/shared/Remotes.luau:288-301`).
  `RequestDropItem` therefore takes **no arguments**: you drop what you are holding, and the server
  knows what that is.
- **Every `OnServerEvent` handler consumes an AntiCheat token FIRST, inline.** `check-ratelimit.mjs` is
  a proximity tripwire — it matches `AntiCheat\w*[.:](Allow|Check|Consume|…)` within 1200 characters of
  the `.OnServerEvent:Connect(` — so the call must be the first line of the handler body, not delegated.
- **`Config.AntiCheat.Budgets` and `Remotes.EVENTS_UP` are pinned in BOTH directions** by
  `tests/anti-cheat-budgets.test.luau`. A new up-remote without a budget entry fails that suite, and a
  budget for a remote that does not exist fails it too.
- **Pure modules may not `require(script.Parent.X)`.** Re-declare the literal unions locally; Luau
  unions are structural. And per `.claude/lessons/pure-module-unions-widen-in-lists.md`, a literal union
  survives `require` as a scalar but **not inside a list** — so any exported table of verdicts or item
  types must be annotated at its declaration site in the consuming file, not inferred.
- **`RoundService` owns the phase.** Nothing in this plan calls `setPhase`. `ItemService` subscribes to
  `RoundService.PhaseChanged` exactly as it already does.
- **Nothing from §3's OUT list.** No second monster, no weapons beyond the three items, no consumable
  content, no permanent safe room. `check:scope` arms `weapons?`; the buntot pagi count is a design
  constant (`src/shared/Config.luau:72-85`) and this chunk does not make it tunable.

## 2. Comprehensive Plan by Phases

### Phase 1: The pure modules generalise

Everything downstream depends on this, so it lands first and lands alone. Two modules are renamed and
widened, two test suites move with them, and the one other consumer of `SaltThrow` — `TrialService` —
is retargeted in the same phase so the tree never spends a commit red.

#### Step 1.1: `SaltCarry` becomes `ItemCarry` — a slot, not a count

**File:** `src/shared/pure/ItemCarry.luau`
**Verify:** `lune run tests/item-carry.test.luau`

Rewrite the carry rule around an optional occupied slot and an incoming item type, keeping the fixed
verdict order and both fail-closed numeric guards intact.

The shape change is `Carried: number` → `Held: ItemType?`. That is not cosmetic: §4.6 gives the three
items different meanings, and a count cannot say *which* one you are holding. `Config.Items.CarryLimit`
survives as a number because `SaltCarry`'s `NO_LIMIT_SET` fail-closed guard is worth keeping — a limit
that silently stops existing is the exploit that module was written to refuse — but the limit is now
compared against a slot occupancy of 0 or 1 rather than against a free-running counter.

```diff
+--!strict
+--[[
+	ItemCarry — may this player take this item right now? (§4.6, V08)
+
+		(request) -> verdict
+
+	MIGRATED FROM `pure/SaltCarry` (C13). The carry half of §4.6 is unchanged and its reasoning is
+	kept verbatim below; what changed at V08 is that there are THREE item types and ONE slot, so the
+	question stopped being "how many are you holding" and became "is your hand full".
+
+	§4.6 IN THREE LINES: four salt pouches, two bawang and one buntot pagi are seeded into containers
+	(§4.4). One carried at a time. No recharge — once used, it's gone. Scarcity makes it a decision.
+
+	The scarcity half is enforced by `Config.Items.*SpawnCount` and by V03's container layout; THIS
+	module enforces the carry half, and it is a separate rule because the two fail differently. Too
+	few items in the barrio is a balance problem you notice. A carry limit that does not hold is an
+	exploit: walk every container, hold everything, and the survivors' entire arsenal stops being a
+	decision and becomes an inventory.
+
+	WHY A VERDICT RATHER THAN A BOOLEAN — the same argument TransformRules, KillValidation and
+	SearchService's verdicts make. The server logs WHY it declined, and "you are dead and standing at
+	a container" and "your hand is already full" send a reader to two different places.
+
+	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. This module never takes a role and it
+	must not start. A carry limit that differed for the Aswang would be a role oracle readable by
+	opening a container — and note that §4.4 has the Aswang searching on identical rules, so the
+	Aswang DOES reach this module, DOES get OK, and DOES fill a slot. That is correct. See
+	`Types.ClientRoundSnapshot.YourCarriedItem`: an empty-handed survivor and the Aswang must be
+	indistinguishable, which they are only if the monster can genuinely hold things.
+
+	IT LIVES IN `src/shared/pure/` AND NOT `src/server/pure/`, which is CLAUDE.md's test applied
+	rather than assumed: are the inputs client-suppliable, and is there a seed? There is no seed, and
+	every input is already on the client — the phase and `YourState` ride the snapshot, `Held` is that
+	client's OWN slot, and `Limit` is in the replicated Config. A client that requires and runs this
+	module learns that it may not hold two things, which it could also learn by trying.
+
+	NO `script.Parent` REQUIRES. All three unions are re-declared; Luau unions are structural, so
+	these and the ones in Types.luau are the same types and pass to each other without a cast.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
+export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+--[[
+	`ITEM_SLOT_FULL` REPLACES C13's `AT_LIMIT` AND THE RENAME IS THE POINT. §4.4's anti-frustration
+	rule means a refused pickup leaves the item in the container for somebody else, so this verdict
+	is a UX finding rather than a fault — and its name should say which of the two mechanics refused.
+
+	PREFIXED `ITEM_` FOR `SearchVerdict`'S REASON (Types.luau:520). `SaltVerdict` already carries a
+	bare `WRONG_PHASE` and `SearchVerdict` a prefixed one; a third union sharing the bare spelling
+	makes a handler wired to the wrong path a working program with the wrong meaning.
+]]
+export type Verdict =
+	"OK"
+	| "ITEM_WRONG_PHASE"
+	| "ITEM_NOT_ALIVE"
+	| "ITEM_SLOT_FULL"
+	| "ITEM_NO_LIMIT_SET"
+
+export type Request = {
+	Phase: RoundPhase,
+	PlayerState: PlayerState,
+	-- The slot's CURRENT occupant, or nil for an empty hand. NOT a count: §4.6's three items are
+	-- different mechanics and "you are holding one thing" cannot say which.
+	Held: ItemType?,
+	-- What the container is offering. Present so a future rule can differ by item without a second
+	-- module; V08 treats all three identically and `tests/item-carry.test.luau` asserts that it does.
+	Incoming: ItemType,
+	Limit: number,
+}
+
+local ItemCarry = {}
+
+--[[
+	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in KillValidation and C13's SaltCarry:
+	world facts first, then the player, then the slot. A log full of ITEM_SLOT_FULL is a UX finding —
+	players opening containers they cannot benefit from — and a log full of anything above it is a
+	correctness finding.
+
+	ITEM_NOT_ALIVE IS AN ALLOWLIST OF ALIVE, never `~= "SPECTATOR"`. A DEAD player must not pick
+	anything up — the arsenal belongs to players who can still be killed by the thing it answers —
+	and DEAD is a state a body walks around in, so the denylist form starts admitting them the moment
+	anything gives a dead player a position. This is `pure/PlayerBody`'s warning in a second file.
+]]
+function ItemCarry.evaluate(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "ITEM_WRONG_PHASE"
+	end
+
+	if request.PlayerState ~= "ALIVE" then
+		return "ITEM_NOT_ALIVE"
+	end
+
+	--[[
+		FAIL CLOSED ON THE LIMIT, and test it for positive-and-finite rather than for zero.
+
+		INHERITED FROM C13 UNCHANGED AND STILL EARNING ITS PLACE even though the slot is now a
+		presence rather than a count. `Limit` arrives from Config. A `CarryLimit` typo of `0` reads as
+		"carry nothing" and the occupancy comparison below would catch it; `-1` and `0/0` would not,
+		and `math.huge` is worse than either because it silently deletes the limit. KillValidation's
+		cooldown took three attempts to get this right; this is the fifth version of that lesson.
+	]]
+	if not (request.Limit > 0 and request.Limit < math.huge) then
+		return "ITEM_NO_LIMIT_SET"
+	end
+
+	--[[
+		OCCUPANCY, COMPARED THE SAME WAY C13's COUNT WAS. With CarryLimit = 1 a player holding
+		anything has occupancy 1, which is `>=` the limit and must be refused — `>` would admit them
+		and the limit would be off by exactly one, which is the whole limit when the limit is one.
+
+		WRITTEN AS AN OCCUPANCY RATHER THAN AS `if request.Held ~= nil` SO THAT `Limit` STAYS
+		LOAD-BEARING. If `Config.Items.CarryLimit` ever rises, `Held` becomes a list and this line is
+		the one that already knows what to do with it. `Types.ClientRoundSnapshot.YourCarriedItem`
+		says the same thing about the snapshot field: a rising limit is a contract change to argue in
+		a plan, not a field to widen quietly.
+	]]
+	local occupancy = if request.Held ~= nil then 1 else 0
+
+	if occupancy >= request.Limit then
+		return "ITEM_SLOT_FULL"
+	end
+
+	return "OK"
+end
+
+return ItemCarry
```

The C13 NaN-carried branch is **deleted rather than migrated**, and that is deliberate. It existed
because `Carried` was a running integer produced by arithmetic that could reach NaN; `Held` is an
optional string written only by an assignment from `SearchService.ItemFound`, so `occupancy` above is
provably 0 or 1 and there is no arithmetic left to poison. `tests/item-carry.test.luau` asserts the
occupancy is exactly one of those two values across the whole grid, which is what replaces the guard.

#### Step 1.2: `SaltThrow` becomes `ItemThrow` — the same cone, an item-typed request

**File:** `src/shared/pure/ItemThrow.luau`
**Verify:** `lune run tests/item-throw.test.luau`

Carry over the cone, the range and the four-MISS-worlds property verbatim; replace `Carried: number`
with `Held: ItemType?` and add the "you are holding the wrong item" world to the same single `MISS`.

**`inCone` is copied byte-for-byte.** It is the half `TrialService` shares (Step 1.3), and every one of
`tests/salt-throw.test.luau:299-379`'s geometric assertions is about it. Changing it while renaming the
file around it is how a migration turns into a rewrite.

```diff
+--!strict
+--[[
+	ItemThrow — did this throw hit? (§4.6, V08)
+
+		evaluate(request) -> verdict          the whole round question
+		inCone(from, direction, target, range, coneDegrees) -> boolean   the aim, shared with C22
+
+	MIGRATED FROM `pure/SaltThrow` (C14) WITH ITS GEOMETRY UNCHANGED. `inCone` below is byte-for-byte
+	what C14 shipped and what `tests/item-throw.test.luau` inherited ~40 assertions about. What
+	changed at V08 is the CARRY input: a slot holding one of three item types, not a pouch count.
+
+	THE CLIENT NEVER DECIDES A HIT. It sends a direction; this module, called on the server, decides.
+	That sentence was C14's whole brief and it is why there is no `Hit: boolean` in the request.
+
+	WHAT COUNTS AS A HIT, AND THE FIVE THINGS THAT DO NOT
+	----------------------------------------------------
+	A hit requires a TRANSFORMED Aswang, inside `Range`, inside the cone, thrown by someone holding
+	SALT. Everything else is MISS, and MISS IS ONE VALUE ON PURPOSE:
+
+	  · nothing in the cone
+	  · a survivor in the cone
+	  · the Aswang in the cone, NOT transformed
+	  · the Aswang in the cone, transformed, past Range
+	  · V08 — the thrower is holding a BAWANG or a BUNTOT_PAGI
+
+	THE FIFTH WORLD IS NEW AND IT IS THE ONE MOST LIKELY TO BE SPLIT OUT. Do not. Splitting them is
+	the obvious refactor and it hands over the game: `MISS_NOT_ASWANG` beside `MISS_OUT_OF_RANGE`
+	lets a compromised client stand in front of each player in turn and read the monster off the
+	refusal shape — for the price of one pouch, which is what §4.6 charges for an HONEST reveal.
+
+	AND THE FIFTH IS WORSE THAN THE OTHER FOUR IF SPLIT, because it is knowable to the thrower
+	already: you know what you are holding. A `MISS_WRONG_ITEM` therefore looks harmless — it tells
+	the thrower nothing new — right up until a client uses its ABSENCE as the oracle: throw while
+	holding salt, and a refusal that is NOT `MISS_WRONG_ITEM` is a refusal about the target. The
+	empty slot is answered separately and above the geometry (`ITEM_NO_ITEM`) precisely because that
+	one depends only on the thrower and is knowable without a target; the wrong-ITEM case is not,
+	because reaching it means a target was evaluated.
+
+	WHY UNTRANSFORMED IS A MISS RATHER THAN A WEAKER HIT (C14, unchanged). §4.6 says salt "forces
+	revert", which only means something for a transformed target. Making salt work on a human-shaped
+	Aswang turns four pouches into four free identity probes. The observable outcome varies by FORM,
+	and the form is already public — `MonsterTransformed` broadcasts it to everyone by design.
+
+	WHY `src/shared/pure/` IS SAFE FOR THIS. The module is callable by any client and reading it
+	teaches an attacker the rule — but the rule is in the spec, in this comment, and visible in one
+	round of play. What a client cannot obtain is the INPUT `TargetIsTransformedAswang`, which exists
+	only in server memory (`monsters[userId].Transformed` ANDed with `RoundService.GetAswangUserId()`).
+	Logic is not secret; inputs are. There is no seed here at all.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — Vec3 is a plain table, converted at the
+	call site exactly as KillValidation's is.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
+export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+-- `ITEM_NO_ITEM` REPLACES C14's `NO_POUCH`. Same position in the order, same meaning: the thrower
+-- has nothing to throw. It stays ABOVE the geometry because it depends only on the thrower, so it
+-- is the same answer for every candidate and cannot be differenced against a target.
+export type Verdict =
+	"OK"
+	| "ITEM_WRONG_PHASE"
+	| "ITEM_THROWER_NOT_ALIVE"
+	| "ITEM_NO_ITEM"
+	| "MISS"
+
+export type Vec3 = { X: number, Y: number, Z: number }
+
+export type Request = {
+	Phase: RoundPhase,
+	ThrowerState: PlayerState,
+	-- V08. The slot's occupant, or nil. `SALT` is the only value that can produce OK; the other two
+	-- fall through to MISS with the geometry, deliberately, per the header's fifth world.
+	Held: ItemType?,
+	ThrowerPos: Vec3,
+	-- Unit-length in the caller's intent, NOT trusted to be. `normalise` handles any magnitude and
+	-- refuses a zero vector, because a client sends this and a client can send Vector3.zero.
+	Direction: Vec3,
+	TargetPos: Vec3,
+	-- The one input a client cannot obtain. True only when the target IS the Aswang AND is currently
+	-- transformed; the caller ANDs those two, so this module never sees a role.
+	TargetIsTransformedAswang: boolean,
+	Range: number,
+	ConeDegrees: number,
+}
+
+local ItemThrow = {}
```

`sub`, `magnitude`, `dot`, `normalise` and the whole of `inCone` move across **unchanged**, comments
included — they are `src/shared/pure/SaltThrow.luau:76-176` and nothing in this chunk touches geometry.
Only `evaluate`'s third gate changes:

```diff
 function ItemThrow.evaluate(request: Request): Verdict
 	if request.Phase ~= "ACTIVE" then
-		return "WRONG_PHASE"
+		return "ITEM_WRONG_PHASE"
 	end
 
 	-- ALLOWLIST of ALIVE. A dead player throwing salt is this bug's shape, and the denylist form
 	-- admits them the moment anything gives a dead player a body and a position.
 	if request.ThrowerState ~= "ALIVE" then
-		return "THROWER_NOT_ALIVE"
+		return "ITEM_THROWER_NOT_ALIVE"
 	end
 
-	if not (request.Carried >= 1 and request.Carried < math.huge) then
-		return "NO_POUCH"
+	--[[
+		AN EMPTY HAND IS ANSWERED HERE; THE WRONG ITEM IS NOT. The distinction is the header's, and
+		it is the single most important line in this migration.
+
+		Empty depends only on the thrower, so every candidate gets the same answer and there is
+		nothing to difference. The wrong ITEM would also be knowable to an honest thrower — but a
+		verdict only reachable AFTER a target was considered can be used in the negative, so it is
+		collapsed into MISS below with the other four worlds.
+
+		C14's NaN and infinity guards are gone with the number they guarded. `Held` is an optional
+		string assigned from `SearchService.ItemFound`; there is no arithmetic left to poison.
+	]]
+	if request.Held == nil then
+		return "ITEM_NO_ITEM"
 	end
 
 	--[[
 		EVERYTHING BELOW THIS LINE RETURNS MISS. Not "returns one of several geometric refusals" —
 		MISS, one value, for FIVE different worlds now. See the header. A future edit that wants to
 		know WHY a throw missed should add a second, SERVER-ONLY return value; it must not widen
 		this union.
 	]]
+	if request.Held ~= "SALT" then
+		return "MISS"
+	end
+
 	if not request.TargetIsTransformedAswang then
 		return "MISS"
 	end
```

The test suite migrates whole. `tests/item-throw.test.luau` is `tests/salt-throw.test.luau` with the
module name, the three renamed verdicts and `Carried = n` → `Held = "SALT"` substituted, **plus** these
new assertions, which are what make the fifth world a property rather than a line of code:

```diff
+check("an empty hand is refused above the geometry", ItemThrow.evaluate(request({
+	Held = nil,
+	TargetIsTransformedAswang = false,
+	TargetPos = v(100, 0, 0),
+})) == "ITEM_NO_ITEM")
+
+--[[
+	THE FIFTH WORLD, ASSERTED AS INDISTINGUISHABLE FROM THE OTHER FOUR.
+
+	This is `tests/salt-throw.test.luau:216-240`'s four-worlds table with a fifth row. The assertion
+	is not "bawang cannot hit" — that would pass while `MISS_WRONG_ITEM` shipped. It is that all five
+	rows produce the SAME value, which is the property a role oracle would break.
+]]
+local worlds: { { label: string, verdict: ItemThrow.Verdict } } = {
+	{ label = "not the Aswang", verdict = ItemThrow.evaluate(request({
+		TargetIsTransformedAswang = false,
+	})) },
+	{ label = "the Aswang, untransformed", verdict = ItemThrow.evaluate(request({
+		TargetIsTransformedAswang = false,
+	})) },
+	{ label = "transformed, out of range", verdict = ItemThrow.evaluate(request({
+		TargetPos = v(100, 0, 0),
+	})) },
+	{ label = "transformed, outside the cone", verdict = ItemThrow.evaluate(request({
+		TargetPos = v(0, 0, 10),
+	})) },
+	{ label = "holding a bawang", verdict = ItemThrow.evaluate(request({ Held = "BAWANG" })) },
+	{ label = "holding the buntot pagi", verdict = ItemThrow.evaluate(request({
+		Held = "BUNTOT_PAGI",
+	})) },
+}
+
+for _, world in worlds do
+	check(`{world.label} is MISS and nothing more specific`, world.verdict == "MISS", world.verdict)
+end
```

**The annotation on `worlds` is load-bearing and is why this diff spells it out.**
`.claude/lessons/pure-module-unions-widen-in-lists.md`: a literal union survives `require` as a scalar
but **not** inside a list. Without `: { { label: string, verdict: ItemThrow.Verdict } }` the field
infers as plain `string`, the comparison still compiles, and the test passes while asserting nothing
about the union. C14's original table carried the same annotation for the same reason.

#### Step 1.3: Delete `SaltThrow`, retargeting its two callers first

**File:** `src/shared/pure/SaltThrow.luau`
**Verify:** `npm run analyze`

`TrialService` is the only other reader of `SaltThrow.inCone`. Point it at `ItemThrow.inCone`, then
delete `src/shared/pure/SaltCarry.luau` and `src/shared/pure/SaltThrow.luau`.

```diff
-local SaltThrow = require(Shared.pure.SaltThrow)
+local ItemThrow = require(Shared.pure.ItemThrow)
```

```diff
--- Vector3 -> the plain table `pure/SaltThrow` takes. That module cannot mention Vector3: Lune has no
+-- Vector3 -> the plain table `pure/ItemThrow` takes. That module cannot mention Vector3: Lune has no
 -- Roblox datatypes and the whole module would stop being runnable from a terminal.
-local function vec3(v: Vector3): SaltThrow.Vec3
+local function vec3(v: Vector3): ItemThrow.Vec3
```

```diff
 		IT SHARES THE AIM WITH THE REAL THROW AND NOTHING ELSE. `ItemThrow.inCone` is the same
 		function `ItemService` resolves a live round's throw through, so the throw a player learns
 		here is the throw that works in a round. V08 renamed the module and changed NOTHING about
 		this function; that is the property C22 depends on and it survived the migration.
 	]]
-			local hit = SaltThrow.inCone(
+			local hit = ItemThrow.inCone(
 				vec3(origin),
 				vec3(direction),
 				vec3(rigRoot.Position),
-				Config.Salt.ThrowRange,
-				Config.Salt.ThrowConeDegrees
+				Config.Items.SaltThrowRange,
+				Config.Items.ThrowConeDegrees
 			)
```

`TrialService` also reads `Config.Salt.PickupRangeStuds` at line 650, for its own scripted pouch. That
line moves to `Config.Items.TrialPickupRangeStuds` in Step 2.1 — the trial keeps a pickup radius even
though the live game stops having one, because the trial's pouch is a scripted prop that is not in a
container and never was. Its two long comments at lines 555-560 and 634-640, which describe
`ItemService.discoverPool` and `ItemService.pickupTick`, both describe functions Step 3.1 deletes;
rewrite them to say the trial's prop is deliberately outside the container system rather than
deliberately outside a pool that no longer exists.

**`TrialService` is not otherwise in scope.** It is edited here only so that Step 1.3's deletions leave
a green tree. Do not touch the trial's timeline, its admission rules or its rig.

#### Step 1.4: Delete `SaltCarry` and retire both old suites

**File:** `src/shared/pure/SaltCarry.luau`
**Verify:** `npm run test:unit`

Delete `src/shared/pure/SaltCarry.luau` — `ItemService.pickupTick` is its only caller and Phase 3
deletes that whole function, so this step leaves one dangling reference which Step 3.1 clears. **If
that offends the one-green-tree-per-step rule, move this deletion into Step 3.1 and keep only the test
retirement here.** Then delete `tests/salt-carry.test.luau` and `tests/salt-throw.test.luau` once their
assertions live in the migrated suites, and confirm the whole Lune tree still passes.

**Count the assertions before and after.** `tests/salt-carry.test.luau` and
`tests/salt-throw.test.luau` print a checked total on exit; the two migrated suites must print a total
that is **greater**, never merely non-zero. A migration that quietly drops a dozen grid cells produces
two green suites and looks exactly like a migration that kept them. The chunk's own Done line says the
70 assertions "carry over", so the count is the contract — record both totals in
`implementation-log.md`.

`npm run test:unit` rather than the two suites individually, because this step's risk is a suite that
stopped being *discovered*: the runner globs `tests/*.test.luau`, so a typo'd filename is a suite that
silently no longer runs while every named suite passes.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — neither pure module takes a role, and neither may start. `ItemCarry` in
  particular must return the same verdict for the Aswang as for a survivor: §4.4 has the monster
  searching on identical rules, so it reaches this module and gets OK.
- **Remote direction** — no remote changes in this phase.
- **Rate limiting** — no handler changes in this phase.
- **Magic numbers** — `ItemThrow.inCone`'s clamp of `coneDegrees` to `(0, 90)` is a domain guard, not
  a tunable; it stays hardcoded exactly as C14 had it, and the Config value is pinned separately by
  `tests/config.test.luau:203`.
- **Phase ownership** — both modules take `Phase` as an input and neither sets it.
- **Player leaving mid-round** — not reachable from a pure module; Phase 3 owns it.
- **Strict Luau** — the `worlds` table annotation in Step 1.2, and every `:: ItemThrow.Verdict` cast
  in the migrated suite. A literal union widens to `string` inside a list.
- **Mobile budget** — untouched.
- **Scope** — three item types and no fourth. `check:scope` arms `weapons?`.

**Issues identified:**

- **`Types.SaltVerdict` still exists and still has a reader after this phase.** `ItemService` returns
  it from `resolveThrow` (`src/server/Services/ItemService.luau:520`) and will keep doing so until
  Step 4.2. That is deliberate — Phase 1 must not touch `ItemService` — but it means `analyze` sees
  two verdict vocabularies for one mechanic between Phase 1 and Phase 4. Do not "tidy" it early; the
  cast at `ItemService.luau:558` is load-bearing and Step 4.2 replaces it as a unit.
- **`Config.Items.ThrowConeDegrees` does not exist yet** when Step 1.3 writes the `TrialService` diff
  above. Either land Step 2.1 first, or write Step 1.3's Config reads against the current
  `Config.Salt.ThrowConeDegrees` and re-point them in Step 2.1. The second is cleaner: each step
  leaves a green tree, which is the ordering rule for the whole plan.

### Phase 2: Config, Types and the remote surface

The data half of the chunk, landed before any service reads it so that Phase 3 compiles on its first
attempt. Nothing here changes behaviour.

#### Step 2.1: `Config.Items` absorbs the carry, pickup and throw numbers

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

Move `CarryLimit`, `ThrowConeDegrees` and the drop numbers into the canonical `Items` block; retire
`PouchPoolSize` and `PickupRangeStuds` with the pool they described; add the invariant assertions that
pin the new relationships.

V02 declared `Items` as the canonical home and `Config.Salt`'s four spec-named keys as aliases into
it, with the instruction: "DELETE EACH ONE with the chunk that renames its last reader"
(`src/shared/Config.luau:12-25`). V08 renames the last reader of all four. `Config.Salt` therefore
**disappears entirely** in this chunk, and the four alias assertions at `tests/config.test.luau:154-174`
go with it.

```diff
 	SaltSpawnCount = 4,
 	SaltDamage = 25,
 	SaltStunDuration = 4,
 	SaltRevealDuration = 10,
 	SaltThrowRange = 25,
+
+	--[[
+		V08. THE SLOT. One item at a time, whichever of the three it is (§4.6).
+
+		MOVED FROM `Config.Salt.CarryLimit` UNCHANGED, and it is now the number that makes the whole
+		item economy a series of decisions rather than a shopping trip. Seven items are seeded across
+		fifteen containers (§4.4); with a limit of one, a survivor who finds the buntot pagi and then
+		finds salt has to CHOOSE, in the open, while the thing that wants to kill them is somewhere.
+
+		IT IS ONE NUMBER FOR ALL THREE ITEMS, deliberately. A per-item limit ("you may hold one salt
+		AND one bawang") is two numbers, four states and a UI problem, and it deletes the choice
+		above. `pure/ItemCarry` compares an occupancy against this, so raising it is a real change
+		rather than a typo — and `Types.ClientRoundSnapshot.YourCarriedItem` would become a list,
+		which that field's comment names as a contract change to argue in a plan.
+	]]
+	CarryLimit = 1,
+
+	--[[
+		The half-angle, in degrees, of the cone a throw sweeps (C14, moved from `Config.Salt` at V08).
+
+		IT IS A CONE RATHER THAN A RAYCAST ON PURPOSE. A ray demands the accuracy of a shooter from a
+		player on a phone (§5: ~60% of players), and §4.6 is buying counterplay, not aim. It is also
+		why the throw cannot be a probe: widening it does not make salt tell you MORE, because a miss
+		and a hit on a survivor are the same silent outcome.
+
+		`tests/config.test.luau` pins it under 90. At 90 the cone is a hemisphere and past 90 you hit
+		what is behind you, which is not a throw. `pure/ItemThrow.inCone` re-checks the same bound
+		because it is called with numbers rather than with Config.
+	]]
+	ThrowConeDegrees = 20,
+
+	--[[
+		V08. HOW FAR IN FRONT OF THE DROPPER A DROPPED ITEM LANDS, and how close you must be to take
+		one back off the ground.
+
+		A DROPPED ITEM IS NOT A CONTAINER. Containers are searched — six seconds, noisy, refusable
+		(§4.4). A thing lying on the floor is picked up by walking over it, because you already paid
+		the search that produced it and §4.4's anti-frustration rule says items belong to the world.
+		So this is a footprint radius, and it is the ONLY pickup radius left in the game once Step
+		3.1 deletes the pouch tick.
+
+		DELIBERATELY SMALLER THAN `Search.RangeStuds` (10). A drop radius at arm's-length-plus-slack
+		would let a player standing at a container also sweep up whatever is on the floor beside it,
+		which turns "choose what to carry" into "carry both, one frame apart".
+
+		AND THE DROP DISTANCE IS AT LEAST THE PICKUP RADIUS, or an item drops inside the radius of
+		the player who dropped it and is instantly re-taken. `tests/config.test.luau` pins that
+		relationship; it is the kind of two-number agreement §6.5 exists for, and nothing in the game
+		would tell you it had broken — the drop would simply appear not to work.
+	]]
+	DropPickupRangeStuds = 6,
+	DropForwardStuds = 6,
+
+	--[[
+		V08. C22's SCRIPTED TRIAL POUCH, and it is here rather than under `Trial` because it is an
+		item radius and this is the item block.
+
+		THE TRIAL KEEPS A PICKUP RADIUS THAT THE LIVE GAME NO LONGER HAS. §9.1 asks that a player
+		"learn to throw salt", and the trial hands them a pouch directly — it runs at IDLE against a
+		scripted rig, with no round, no containers and no search. Teaching the search would be
+		teaching V03's mechanic inside V08's tutorial; C22 deliberately teaches ONE thing.
+	]]
+	TrialPickupRangeStuds = 6,
 }
```

And the deletion, which is the larger half of this step:

```diff
-	Salt = {
-		SpawnCount = Items.SaltSpawnCount,
-		StunDuration = Items.SaltStunDuration,
-		RevealDuration = Items.SaltRevealDuration,
-		ThrowRange = Items.SaltThrowRange,
-
-		CarryLimit = 1,
-		PickupRangeStuds = 6,
-		ThrowConeDegrees = 20,
-		PouchPoolSize = 6,
-
-		PouchRgb = { 240, 238, 225 },
-		RevealGlowFillRgb = { 255, 250, 235 },
-		RevealGlowOutlineRgb = { 190, 235, 255 },
-	},
```

Three of those need a decision rather than a deletion:

- **`PouchPoolSize` and `PickupRangeStuds` die with the pool.** They describe `SaltSpawn` points and a
  walk-over tick, both of which Step 3.1 removes. `SearchService` already owns the pool question
  through `Config.Search.ContainerCount` and `SearchService.TotalItems()`.
- **`RevealGlowFillRgb` / `RevealGlowOutlineRgb` MOVE TO `Config.Monster`**, not to `Items`. They are
  read by `MonsterService.applyExposed` (`MonsterService.luau:868-869`) and the glow they colour is the
  Exposed Highlight, whose brightness ramp is already under `Config.Monster.ExposedGlowTransparency*`.
  `MonsterService.luau:747` explicitly notes the split as "not an accident" — V08 ends the split by
  moving the colours to the ramp, rather than by moving the ramp to the colours.
- **`PouchRgb` moves to `Items` as `ItemRgb`, and becomes three colours.** A dropped bawang and a
  dropped buntot pagi need to be distinguishable from a dropped pouch, and from Step 4.3 onward all
  three can be lying on the ground.

```diff
+	-- V08. The three items' placeholder colours, RGB TRIPLES, NEVER Color3 — same reason as
+	-- Monster's palette. V15 replaces these with real models; until then a tester has to be able to
+	-- tell the win condition from a pouch at ten paces.
+	SaltRgb = { 240, 238, 225 },
+	BawangRgb = { 236, 222, 180 },
+	BuntotPagiRgb = { 120, 96, 72 },
```

The new assertions in `tests/config.test.luau`, replacing the four deleted alias checks:

```diff
+--[[
+	V08. THE DROP CANNOT LAND INSIDE ITS OWN PICKUP RADIUS.
+
+	A silent invariant of exactly the kind §6.5 collects. Drop an item within `DropPickupRangeStuds`
+	of where you are standing and the pickup pass takes it straight back — the item never reaches the
+	floor, the slot never empties, and the player sees a drop button that does nothing. No error, no
+	warning, and the only symptom is a control that appears broken.
+]]
+check(
+	"a dropped item lands outside the radius that would re-take it",
+	Config.Items.DropForwardStuds >= Config.Items.DropPickupRangeStuds,
+	`DropForwardStuds={Config.Items.DropForwardStuds}, `
+		.. `DropPickupRangeStuds={Config.Items.DropPickupRangeStuds}`
+)
+
+--[[
+	V08. A DROPPED ITEM IS NOT SWEPT UP FROM A CONTAINER.
+
+	`Search.RangeStuds` (10) is how far you may stand from a container and still search it. If the
+	drop pickup radius reached that far, a player at a container would collect whatever was on the
+	floor beside it without moving — and the one-slot choice §4.6 is built on becomes "hold both,
+	one frame apart".
+]]
+check(
+	"the drop pickup radius is tighter than the search radius",
+	Config.Items.DropPickupRangeStuds < Config.Search.RangeStuds,
+	`DropPickupRangeStuds={Config.Items.DropPickupRangeStuds}, `
+		.. `SearchRangeStuds={Config.Search.RangeStuds}`
+)
+
+-- V08. `pure/ItemCarry` fails closed on a limit that is not positive-and-finite, so a typo here is
+-- a game in which nobody can carry anything. One is the design (§4.6); this pins the range.
+check(
+	"the carry limit is a positive finite number",
+	Config.Items.CarryLimit > 0 and Config.Items.CarryLimit < math.huge,
+	`CarryLimit={Config.Items.CarryLimit}`
+)
```

**Do not touch invariant 1.** `tests/config.test.luau:230-243` already pins
`SaltDamage x (SaltSpawnCount - 1) >= MaxHealth - WeakenedThreshold`, V05 added it, and it currently
holds with **zero margin** (`25 x 3 = 75 >= 75`). No number this step moves appears in it. If a later
step in this plan is tempted to tune `SaltDamage` or `SaltSpawnCount` for feel, that suite goes red and
the answer is to stop, not to relax the assertion.

Two existing assertions must be **re-pointed, not deleted**, because they read through the alias table:
`tests/config.test.luau:127` (`ThrowRange > KillRange`, §6.5 invariant 3) and `:135`
(`RevealDuration > StunDuration`, invariant 6). Both become `Config.Items.Salt*` reads. Losing either
would remove a §6.5 invariant from the suite, which is the one thing this step must not do while
deleting a table.

#### Step 2.2: The three verdict unions and the drop payload

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

Add `ItemCarryVerdict`, `ItemThrowVerdict` and `ItemDropVerdict`, prefixed per the `SEARCH_` precedent
at `src/shared/Types.luau:520-524`, and leave `SaltVerdict` deleted once `ItemService` stops using it.

`Types.ItemType` and `Enums.ItemType` already exist (`Types.luau:27`, `Enums.luau:46-49`) and are
correct. Nothing in this chunk widens them.

```diff
+--[[
+	V08, §4.6. THE THREE ITEM VERDICTS, AND WHY THEY ARE THREE UNIONS RATHER THAN ONE.
+
+	Each one is the return type of a different pure module, and the modules refuse for different
+	reasons at different moments: `ItemCarry` refuses a pickup, `ItemThrow` refuses a use,
+	`ItemDrop` refuses a put-down. One merged union would let a handler compare against a value its
+	module can never return, which compiles and means nothing.
+
+	ALL THREE ARE PREFIXED `ITEM_`, and that is `SearchVerdict`'s rule (below, and worth re-reading).
+	`SaltVerdict` carried a bare `WRONG_PHASE`; three more unions spelling it the same way makes a
+	handler wired to the wrong path a working program with the wrong meaning, which `check:remotes`
+	and `check:secrecy` are text tripwires and cannot see. The prefix makes it an analyzer error.
+
+	NONE OF THE THREE IS EVER ECHOED TO A CLIENT. This is `SaltVerdict`'s rule inherited verbatim:
+	`ItemService`'s handlers return nothing on any path, including OK, and the client learns what
+	happened from the world and from its own snapshot. A verdict echoed back is a role oracle for
+	the price of one pouch — see `pure/ItemThrow`'s header for the five worlds that argument covers.
+]]
+export type ItemCarryVerdict =
+	"OK"
+	| "ITEM_WRONG_PHASE"
+	| "ITEM_NOT_ALIVE"
+	| "ITEM_SLOT_FULL"
+	| "ITEM_NO_LIMIT_SET"
+
+export type ItemThrowVerdict =
+	"OK"
+	| "ITEM_WRONG_PHASE"
+	| "ITEM_THROWER_NOT_ALIVE"
+	| "ITEM_NO_ITEM"
+	| "MISS"
+
+--[[
+	THE DROP, AND IT HAS NO GEOMETRY AT ALL. You may put down what you are holding, wherever you are
+	standing, whenever you are alive in an ACTIVE round. There is no "you cannot drop here".
+
+	A PLACEMENT RULE WOULD BE V09'S, NOT V08'S. Bawang is PLACED on a doorway and that placement has
+	conditions; dropping is the plain act of ceasing to hold something, and conflating the two now
+	would build half of V09 inside V08 with none of its rules written down.
+]]
+export type ItemDropVerdict = "OK" | "ITEM_WRONG_PHASE" | "ITEM_NOT_ALIVE" | "ITEM_NOTHING_HELD"
+
+--[[
+	V08, §4.6. WHAT `pure/ItemUse` ANSWERS — which verb, if any, this item currently has.
+
+	`USE_NOT_IMPLEMENTED` IS THE V09/V10 BOUNDARY AND IT IS DELIBERATELY A VALUE RATHER THAN A GAP.
+	V08 gives all three items carry, drop and a slot; only salt gets a verb. Bawang's doorway block
+	is V09 and the buntot pagi's strike is V10, and each is a real mechanic with its own rules — not
+	something to be filled in by whoever notices the hole. A named verdict means the hole is
+	asserted in `tests/item-use.test.luau` rather than left to be discovered.
+]]
+export type ItemUseVerdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
```

And the deletion, which happens here rather than in Phase 4 only if `ItemService` no longer reads it —
so **land this half in Step 4.2 instead** if the analyzer objects:

```diff
-export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"
```

`Types.SaltEffectPayload` (`Types.luau:340`) **stays exactly as it is.** Its three fields are a
trajectory and nothing about a player, its comment at `:334-338` explains that an EXTRA field on an
annotated table is accepted silently by the typechecker and that `SaltEffect` is not on
`check-secrecy.mjs`'s `REVEAL_ALLOWLIST`. V08 adds no field to it and renames nothing in it — the
remote is still called `SaltEffect` and still describes a salt throw, because bawang and buntot pagi
have no throw. Renaming it to `ItemEffect` would be a change to the remote surface bought for
symmetry, and it would invite exactly the extra field that comment refuses.

#### Step 2.3: A budget for `RequestDropItem`

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

Price the drop generously for `RequestCancelSearch`'s reason — a refused drop reads as the game
ignoring your input — and pin its relationship to the carry limit.

```diff
 			RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
 			RequestCancelSearch = { Capacity = 6, RefillPerSecond = 0.5 },
+			--[[
+				V08, §4.6. THE DROP, PRICED LIKE `RequestCancelSearch` RATHER THAN LIKE THE THROW.
+
+				A refused THROW costs a player one pouch's worth of opportunity and the salt stays in
+				their hand. A refused DROP leaves them holding something they asked to put down —
+				which reads as the game ignoring their input, the worse of the two failures and the
+				one a player blames the game for. Same asymmetry `RequestCancelSearch` documents.
+
+				AND THE DROP IS HONESTLY BURSTY IN THE ONE MOMENT THAT MATTERS. §4.6 makes the buntot
+				pagi's carrier a target; the play the design wants is a carrier under pressure
+				dropping it so it is not lost with their body, and a survivor swapping items at a
+				container fires drop-then-pickup back to back. A limiter that refuses either is a
+				gameplay bug that presents as lag.
+
+				NOTHING BEHIND IT IS EXPENSIVE. The handler reads one slot entry, spawns one anchored
+				part and clears one table key — so the reason to bound it at all is a firehose into
+				`Instance.new`, not the decision. `Config.AntiCheat.Budgets`' own header says to tune
+				these looser than legitimate play and let the validation refuse the exploiter.
+			]]
+			RequestDropItem = { Capacity = 6, RefillPerSecond = 0.5 },
```

`tests/anti-cheat-budgets.test.luau` pins `Remotes.EVENTS_UP` and this table against each other in both
directions, so this step is red until Step 2.4 declares the remote and green the moment it does — which
is why the two steps are adjacent. Add one relationship assertion beside the existing
`RequestThrowSalt` one at `tests/anti-cheat-budgets.test.luau:127`:

```diff
+--[[
+	V08. A PLAYER MAY DROP AT LEAST AS OFTEN AS THEY MAY PICK UP.
+
+	With `Items.CarryLimit = 1`, swapping items is drop-then-pickup, and a player working a row of
+	containers does that once per container. A drop budget tighter than the carry limit would make
+	the swap fail on exactly the play §4.6's one-slot rule exists to create.
+]]
+check(
+	"the drop budget covers a swap",
+	Config.AntiCheat.Budgets.RequestDropItem.Capacity >= Config.Items.CarryLimit,
+	`DropCapacity={Config.AntiCheat.Budgets.RequestDropItem.Capacity}, `
+		.. `CarryLimit={Config.Items.CarryLimit}`
+)
```

Line 127 of that suite currently reads `Config.Salt.CarryLimit` and must be re-pointed to
`Config.Items.CarryLimit` in this step, or Step 2.1's deletion of `Config.Salt` takes it down.

#### Step 2.4: Declare `RequestDropItem`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

One new name in `EVENTS_UP`, argument-free, with the "the client names nothing" reasoning written into
the declaration beside `RequestSearch`'s.

```diff
 	"RequestCancelSearch",
+	--[[
+		V08, §4.6. NO ARGUMENTS, and the absent argument is the entire security design.
+
+		THE ITEM IS NOT NAMED BY THE CLIENT. `Config.Items.CarryLimit` is 1, so there is exactly one
+		thing a player can be holding and the server already knows what it is. This is
+		`RequestClaimDaily`'s and `RequestCamouflage`'s rule — everything the decision needs is
+		server-side already — and `RequestSearch`'s: the server resolves what a player has from that
+		player's own state, and the client names nothing.
+
+		A `RequestDropItem(itemType)` WOULD HAVE BEEN A FREE PROBE AND A FREE DUPLICATOR. It needs a
+		verdict for "you are not holding that", which is the comparison the server was already going
+		to make; and a client naming `BUNTOT_PAGI` while holding salt is a request the server must
+		refuse rather than one it can simply not be asked. There is exactly one buntot pagi per round
+		(§4.6) and it IS the second win condition, so a handler that spawns an item the client named
+		is the sharpest exploit surface this chunk has. It has no argument, so it cannot be asked.
+
+		NOR IS THERE A POSITION. A drop lands `Config.Items.DropForwardStuds` in front of the
+		player's OWN character, read on the server. A client-supplied position drops the win
+		condition through a wall, inside the map, or at a teammate's feet across the barrio.
+
+		IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching on identical
+		rules, so the monster can hold and drop items exactly as a survivor can, and must — see
+		`Types.ClientRoundSnapshot.YourCarriedItem`: an empty-handed survivor and the Aswang are
+		indistinguishable only if the monster genuinely fills slots. Nothing is returned to the
+		caller on any path, including OK.
+	]]
+	"RequestDropItem",
```

**No `EVENTS_DOWN` entry, and no `check-secrecy.mjs` edit.** Worth stating plainly because the brief
for this chunk raised it: `REVEAL_ALLOWLIST` exempts server→client calls that legitimately carry the
role, and it holds exactly two names for that reason (`check-secrecy.mjs:70-73`). `RequestDropItem` is
client→server and carries nothing at all, so it has no business in that file. What a new up-remote
actually costs is the `Config.AntiCheat.Budgets` entry from Step 2.3 and the inline
`AntiCheatService.Consume` from Step 4.3 — both mechanically enforced, neither by `check:secrecy`.

The drop's *effect* is visible to everyone — an item appears on the floor — and that is correct and
already public: it is an object in the world that every client can see, exactly as the `SaltPouch` tag
was (`ItemService.luau:157-163`). What must not exist is any per-player channel announcing it; Step 5.4
owns that.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing in this phase sends anything. The one field that starts existing on the
  wire is `YourCarriedItem`, which Phase 5 produces; `Types.luau:435-464` already argues it is not a
  role oracle, not a death signal, and never widened to another player's carry.
- **Remote direction** — `RequestDropItem` in `EVENTS_UP` only. `check:remotes` catches the wrong list.
- **Rate limiting** — the budget exists here; the `Consume` call is Step 4.3, so `check:ratelimit` has
  nothing to see yet and will not until the handler lands.
- **Magic numbers** — every number added is in `Config.Items`. `check:config` fails on a tunable typed
  anywhere else, including in the test suite.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — untouched.
- **Strict Luau** — a missing `Config` key is a HARD analyzer error, not a warning
  (`Config.luau:17-20`), so deleting `Config.Salt` in Step 2.1 while any reader survives fails
  `analyze` immediately rather than at runtime. That is the desired failure mode; do not soften it by
  leaving a stub table behind.
- **Mobile budget** — untouched.
- **Scope** — three item types, one buntot pagi. §3's OUT list forbids permanent safe rooms and this
  chunk adds no barrier of any kind.

**Issues identified:**

- **Deleting `Config.Salt` is the single riskiest edit in this plan and it must be last within the
  phase.** Five modules read it today: `ItemService`, `TrialService`, `MonsterService`, `UIController`
  and `InputController` (`Config.luau:16-18` names four of them from V02's survey; `MonsterService` is
  the fifth, at `:868-869`). Step 2.1 as written deletes the table, but `ItemService` (Phase 3),
  `UIController` and `InputController` (Phase 5) still read it. **Either** re-point all five readers
  inside Step 2.1 — a wider step than the rest of this plan, but one green tree — **or** leave
  `Config.Salt` in place through Phase 2 and delete it in Step 5.2 when its last reader goes. The
  second is recommended and the plan assumes it: each phase then leaves the game runnable, which is
  the ordering rule. Flag whichever was chosen in `implementation-log.md`.
- **The four alias assertions cannot outlive the table they check.** `tests/config.test.luau:154-174`
  goes red the instant `Config.Salt` disappears. Delete those four checks in the same edit, and only
  those four — `:127` and `:135` are §6.5 invariants wearing alias clothing and get re-pointed instead.

### Phase 3: `ItemService` — the slot, fed by containers

The demolition and the rebuild. The `SaltSpawn` pool, the pouch parts and the pickup tick all die; the
service starts listening to `SearchService.ItemFound`, which V03 built and left connected to nothing.

#### Step 3.1: Demolish the `SaltSpawn` pool, the pouches and the pickup tick

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run lint`

Remove `discoverPool`, `reportPool`, `EvaluatePool`, `spawnPouches`, `clearPouches`, `pickupTick`, the
`SaltPouches` folder and both tags. Selene catches every local left dangling by the cut.

The build plan is unambiguous: "Items come from containers (V03), never from a spawn point." V03 already
built that — `SearchService` seeds all seven items into containers using
`Config.Items.*SpawnCount` (`SearchService.luau:238-240`) and fires `SearchService.ItemFound` on a
completed search (`SearchService.luau:439`), connected to nothing. `ItemService` meanwhile still runs a
**second, parallel salt economy**: four pouches at `SaltSpawn` points, picked up by walking over them.
Both are live today. Leaving both would put eight pouches in a round where §4.6 says four, and would
break §6.5 invariant 1 without touching a single number in `Config`.

Delete, in this order:

| Removed | Lines | Why it goes |
| --- | --- | --- |
| `TAG_SPAWN`, `pointsByName`, `discoverPool`, `reportPool` | `ItemService.luau:47-128` | The `SaltSpawn` pool. `SearchService.discoverPool` is the surviving copy and it reports on containers |
| `ItemService.EvaluatePool` | `:130-141` | Public, and its only caller is the pouch spawn |
| `TAG_POUCH`, `rng`, `spawnPouches` | `:150-243` | Pouch parts, the billboard, the PointLight and the Fisher-Yates draw |
| `clearPouches`, `pouches` folder | `:57-59`, `:245-259` | The `SaltPouches` folder in `workspace` |
| `pickupTick` and its `task.spawn` loop | `:261-330`, `:735-741` | Walk-over pickup. Containers replace it |
| `rgb` helper | `:143-147` | Only Step 3.2's dropped-item colours need it — **keep it**, see below |

`rgb` is the one entry that survives: dropped items in Step 4.3 need `Config.Items.SaltRgb` and its two
siblings turned into a `Color3`, and the helper's comment already explains why it is copied from
`MonsterService` rather than exported by it. Keep the function and the comment.

The `SearchPool` require goes with `discoverPool`:

```diff
-local SearchPool = require(script.Parent.Parent.pure.SearchPool)
```

`server/pure/SearchPool.luau` itself **stays** — `SearchService` is its remaining caller and V03's
comment at `SearchService.luau:108` records that it was lifted from here.

Two comments elsewhere describe functions that no longer exist and must be rewritten rather than left:
`TrialService.luau:555-560` and `:634-640` (handled in Step 1.3), and `SearchService.luau:108`, which
should now say the pool logic is shared through `server/pure/SearchPool` rather than lifted from a
service that no longer has any.

**`npm run lint` is the check because selene is what actually catches this cut.** A deletion this size
leaves unused locals, unused requires and unreachable helpers, and every one of them is a sign that a
reference survived somewhere the deleter did not look. `analyze` would pass over an orphaned local.

#### Step 3.2: The slot, and the `ItemFound` connection

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:secrecy`

Replace `carried: { [number]: number }` with `slot: { [number]: Types.ItemType }`, and fill it from
`SearchService.ItemFound` through `ItemCarry.evaluate`.

```diff
-local SearchPool = require(script.Parent.Parent.pure.SearchPool)
+local SearchService = require(script.Parent.SearchService)
```

**Check the bootstrap order before adding that require.** `src/server/init.server.luau:54-67` starts
`ItemService` **before** `SearchService`, with a comment saying the second half of `SearchService`'s
position is load-bearing (it must start before `RoundService` so it does not miss the STARTING that
seeds its containers). A `require` at the top of a module is evaluated when the module is first
required, not when it is started, so the require itself is safe — but `ItemService.Start` connecting to
`SearchService.ItemFound` is only safe because the BindableEvent is created at module scope
(`SearchService.luau:76`), not inside `Start`. That is why V03 built it that way. Do not move it.

```diff
-local carried: { [number]: number } = {}
+--[[
+	SERVER-ONLY. THE SLOT. What each player is holding, keyed by UserId, or absent for an empty hand.
+
+	NEVER REPLICATED AS A TABLE. A roster of who holds what is a roster of who can answer the Aswang
+	— C13 said it about a salt count and it is sharper now, because one entry in this table is the
+	buntot pagi and §4.6 makes its carrier a target. `SearchService.foundByPlayer` carries the same
+	warning for the same reason.
+
+	THE ASWANG IS IN THIS TABLE LIKE EVERYONE ELSE. §4.4 has the monster searching on identical
+	rules, so it finds items, fills this slot and drops things. That is not an oversight to be
+	optimised away: `Types.ClientRoundSnapshot.YourCarriedItem` is safe precisely because an
+	empty-handed survivor and the Aswang are indistinguishable, and they only are if the monster can
+	genuinely hold things. A `if isAswang then return end` here would make an empty slot a tell.
+
+	ONE ENTRY PER PLAYER, NOT A LIST, and `Config.Items.CarryLimit = 1` is why. `pure/ItemCarry`
+	compares an occupancy against that number so the rule has one home; this table's SHAPE is the
+	second enforcement, and it is the one that cannot drift.
+]]
+local slot: { [number]: Types.ItemType } = {}
```

The pickup, replacing the whole of `pickupTick`:

```diff
+--[[
+	V08. A CONTAINER YIELDED AN ITEM (§4.4, §4.6). THE ONLY WAY AN ITEM ENTERS A SLOT FROM THE WORLD
+	that is not a deliberate pick-up-off-the-floor.
+
+	`SearchService.ItemFound` fires from `completeFeed`'s search equivalent — the ONE path that
+	yields an item (`SearchService.luau:398-439`) — after the container is marked opened. So by the
+	time this runs, the item has already left the world and the container is already spent.
+
+	WHICH IS WHY A REFUSAL HERE HAS TO PUT THE ITEM BACK, AND THAT IS THE HARD PART OF THIS STEP.
+	§4.4's anti-frustration rule says items belong to the world, not to individuals; a player whose
+	hand is full completes a six-second search, makes noise, and would otherwise DESTROY the item.
+	With seven items in the round and one of them the win condition, a full-handed search on the
+	buntot pagi's container would delete the second win condition silently. See the issue below.
+
+	A BindableEvent's arguments are `...any`, so this narrows rather than casts — V03's own
+	instruction at `SearchService.luau:67-69`.
+]]
+local function onItemFound(player: unknown, itemId: unknown)
+	if typeof(player) ~= "Instance" or not player:IsA("Player") then
+		return
+	end
+
+	if
+		itemId ~= Enums.ItemType.Salt
+		and itemId ~= Enums.ItemType.Bawang
+		and itemId ~= Enums.ItemType.BuntotPagi
+	then
+		warn(`[ItemService] SearchService.ItemFound fired with an unknown item: {tostring(itemId)}`)
+		return
+	end
+
+	-- The narrowing above is what makes this cast honest: three equality tests against the frozen
+	-- Enums table, not a `:: Types.ItemType` over whatever arrived.
+	local item = itemId :: Types.ItemType
+
+	local verdict = ItemCarry.evaluate({
+		Phase = RoundService.GetPhase(),
+		PlayerState = RoundService.GetPlayerState(player),
+		Held = slot[player.UserId],
+		Incoming = item,
+		Limit = Config.Items.CarryLimit,
+	})
+
+	if verdict ~= "OK" then
+		--[[
+			THE ITEM GOES TO THE FLOOR, NOT TO NOTHING. See the header. `dropItemAt` is Step 4.3's
+			world-placement helper, called here with the searcher's own position so the item lands
+			where the container was — which is where a player who could not carry it would expect to
+			find it when they come back with an empty hand.
+		]]
+		spillItem(player, item)
+
+		if Config.Debug.VerboseLogging then
+			-- A UserId and a verdict. Never the item, and never a role: an item id in the log beside
+			-- a UserId is the roster this table's comment refuses to build, written to disk.
+			print(`[ItemService] Pickup refused for {player.UserId}: {verdict}`)
+		end
+
+		return
+	end
+
+	slot[player.UserId] = item
+
+	-- C23. The first pouch a player ever takes explains what it is for; §10 is explicit that the
+	-- folklore must not be assumed. Fired to the player who did it, about a thing they did
+	-- themselves — no audience question here. SALT ONLY: the cue's copy is about salt, and V09/V10
+	-- own whether their items deserve one.
+	if item == Enums.ItemType.Salt then
+		TeachingService.Cue(player, "CUE_FIRST_SALT")
+	end
+end
```

`onPhaseChanged` loses `spawnPouches` and `clearPouches` and gains the slot clear:

```diff
 local function onPhaseChanged(phase: Types.RoundPhase)
-	if phase == Enums.RoundPhase.Starting then
-		spawnPouches()
-	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
-		clearPouches()
+	--[[
+		INTERMISSION AND IDLE ONLY, mirroring what `clearPouches` did and what
+		`MonsterService.clearCorpses` does — NOT "any phase that is not ACTIVE", which is the mistake
+		that destroyed the winning kill's corpse within a frame of creating it.
+
+		Items lying on the ground during ENDING are scenery, and a slot during ENDING is a fact about
+		a round that has finished. Neither is a mark on a player, which is the distinction the split
+		below draws for effects.
+	]]
+	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
+		clearDroppedItems()
+		table.clear(slot)
 	end
 
 	if phase ~= Enums.RoundPhase.Active then
 		clearAllEffects()
 	end
 end
```

**`npm run check:secrecy` is the check for this step** because the slot is the new per-player fact and
this is where a leak would enter. It is a text tripwire and cannot follow data flow — Step 5.4 and
`exploit-auditor` cover what it cannot — but it does catch the shapes most likely to appear here: a
`SetAttribute` carrying an item, a `CollectionService:AddTag` on a character, and a `FireAllClients`
whose payload names a player.

#### Step 3.3: Every number read from `Config.Items`

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:config`

The rewritten service reads `Config.Items.*` throughout and declares no tunable of its own; the two
surviving `config-ok` waivers keep their reasons.

Every `Config.Salt.X` read in this file becomes `Config.Items.X`, and the four renamed keys take their
spec-facing names:

| Was | Becomes |
| --- | --- |
| `Config.Salt.SpawnCount` | *deleted with the pouch spawn* |
| `Config.Salt.PickupRangeStuds` | *deleted with the pickup tick* |
| `Config.Salt.PouchPoolSize` | *deleted with the pool* |
| `Config.Salt.CarryLimit` | `Config.Items.CarryLimit` |
| `Config.Salt.ThrowRange` | `Config.Items.SaltThrowRange` |
| `Config.Salt.ThrowConeDegrees` | `Config.Items.ThrowConeDegrees` |
| `Config.Salt.StunDuration` | `Config.Items.SaltStunDuration` |
| `Config.Salt.PouchRgb` | `Config.Items.SaltRgb` |

The `config-ok` waivers that survive the rewrite, each keeping its existing reason:

```diff
-	pouch.Size = Vector3.new(1, 1, 1) -- config-ok: the pouch's own size, not a balance knob
-	pouch.Position = point.Position + Vector3.new(0, 1, 0) -- config-ok: sits on the pad, not a knob
+	part.Size = Vector3.new(1, 1, 1) -- config-ok: the item's own size, not a balance knob
+	-- config-ok: sits on the ground where it was dropped, not a knob
+	part.Position = groundPosition + Vector3.new(0, 1, 0)
```

```diff
 	humanoid.WalkSpeed = 0 -- config-ok: a stun is total; 0 is the mechanic, not a knob
 	humanoid.JumpPower = 0 -- config-ok: same
```

and the placeholder-presentation ones on the billboard and the glow, which move from the pouch to the
generic dropped item and keep saying "replaced at V15" rather than C34 — V15 is the chunk that brings
real models under the v2.0 numbering.

**The `task.wait(0.25)` scheduler waiver disappears with the pickup tick,** and it should not come back.
The rewritten service is entirely event-driven: `SearchService.ItemFound`, two `OnServerEvent` handlers,
`RoundService.PhaseChanged` and `Players.PlayerRemoving`. The one thing that plausibly wants a tick is
picking a dropped item back up off the floor, and Step 4.3 resolves that on a `Touched` connection on
the dropped part itself rather than by re-introducing an O(players x items) sweep — see that step for
why, and for the server-side distance re-check that makes `Touched` safe to trust.

**`npm run check:config` is the check** because this step's failure mode is a number that survived the
rename by being retyped as a literal. `check:config` fails on a tunable typed outside `Config.luau`,
and a waiver needs a mandatory reason, so a `20` that used to be `ThrowConeDegrees` cannot quietly
reappear.

#### Step 3.4: The four ways a slot empties without a use

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run verify:fast`

Death, disconnect, the round leaving ACTIVE, and a deliberate drop. §6.4's edge cases, applied to a
slot that now holds the barrio's only win condition.

§4.6 is explicit about the first one: the buntot pagi "can be dropped, passed, and picked up from a
body", and "when the carrier dies it drops where they fell, which means there is a corpse in the open
with the win condition lying next to it and a monster that knows you have to come back for it". That
sentence is a mechanic. A slot that is simply cleared on death deletes the second win condition the
first time the carrier is caught, and nothing in the game reports it.

```diff
+--[[
+	V08, §4.6/§6.4. THE FOUR WAYS A SLOT EMPTIES WITHOUT THE ITEM BEING USED, AND THREE OF THEM PUT
+	IT ON THE FLOOR.
+
+	  1. DEATH — it drops where they fell. §4.6 requires this by name and builds a whole beat on it.
+	  2. DISCONNECT — it drops where the husk stands. See the note below; this is a decision.
+	  3. THE ROUND LEAVING ACTIVE — the slot clears and the world is swept. Nothing to preserve.
+	  4. A DELIBERATE DROP — Step 4.3's handler.
+
+	ONLY (3) DESTROYS THE ITEM, and only because the round it belonged to is over.
+]]
```

**Death.** `RoundService.MarkKilled` is the one place a player becomes DEAD (`RoundService.luau:841`),
and it already fires a snapshot afterwards. `ItemService` must not require `RoundService` in reverse —
it already requires it forwards — so the connection is the same shape `MonsterService` uses: watch the
character. The corpse `MonsterService` creates is the natural anchor, and `MonsterService.GetCorpsesFolder`
(`:3054`) is already public.

```diff
+--[[
+	DROP ON DEATH, AT THE POSITION THE PLAYER DIED AT, NOT AT THE CORPSE'S FINAL RESTING PLACE.
+	Read the position BEFORE anything moves or destroys the character, because a Humanoid.Died
+	handler that reads `character.PrimaryPart.Position` after a ragdoll settles drops the win
+	condition somewhere nobody watched them die.
+
+	AND IT MUST NOT BE A ROLE TELL. Every player who dies drops what they were holding, and a player
+	holding nothing drops nothing — which is the same observable as the Aswang, who is holding
+	nothing far more often but is not special-cased anywhere. Step 5.4 owns this question in full.
+]]
```

**Disconnect.** The existing `PlayerRemoving` handler drops the carry and its comment
(`ItemService.luau:715-727`) explicitly leaves the question open: the husk rule preserves a player's
state across a reconnect, so does their carry travel with it? **V08 answers: no — the item goes to the
floor at the husk's position.** Three reasons, and they should go in the comment that replaces that one:

- §4.6's death rule already says the buntot pagi lands where its carrier fell. A disconnect that made
  it vanish would be strictly worse than dying with it, which gives players an incentive to alt-F4.
- The husk is a body standing in the barrio that other players can see and that
  `RoundService.MarkHuskKilled` (`:1200`) can kill. An item on the floor beside it is consistent with
  everything else about the husk.
- A carry preserved across a reconnect is a duplication surface: the slot table survives, the husk
  survives, and the reconnect path would need to prove it does not hand back an item that was also
  dropped. There is exactly one buntot pagi and it is the win condition.

```diff
 	Players.PlayerRemoving:Connect(function(player: Player)
-		carried[player.UserId] = nil
+		--[[
+			V08 ANSWERS C13's OPEN QUESTION: THE ITEM DOES NOT TRAVEL WITH THE HUSK.
+
+			C13 left this "conservative choice, revisit when Phase 5 lands". §4.6 settles it: the
+			buntot pagi lands where its carrier fell, so a disconnect must not be a better outcome
+			than a death. It goes on the floor at the husk's position, where a returning player finds
+			it exactly where they left themselves.
+
+			AND IT CLOSES A DUPLICATION SURFACE. There is one buntot pagi per round and it IS the
+			second win condition; a carry preserved across a reconnect would have to prove it cannot
+			also have been dropped. Dropping unconditionally makes that unprovable state unreachable.
+		]]
+		spillItem(player, slot[player.UserId])
+		slot[player.UserId] = nil
 
 		stunned[player.UserId] = nil
 	end)
```

**`npm run verify:fast` is the check** — `analyze` plus `check:remotes`, `check:secrecy` and the
toolchain, in about three seconds. This step's realistic failure is a nil-safety hole in the death path
(`player.Character` is optional at every one of these moments) and a `spillItem` called with a `nil`
slot, both of which are analyzer findings under `--!strict`.

#### Step 3.5: `SearchService`'s comments stop describing deleted code

**File:** `src/server/Services/SearchService.luau`
**Verify:** `npm run analyze`

Three comments in `SearchService` describe things that no longer exist after Step 3.1, and a comment
naming a deleted function is worse than no comment because it reads as current.

- `:108` — "Pool discovery. Lifted almost verbatim from `ItemService.discoverPool`". That function is
  gone. Say instead that the pool verdict is shared through `server/pure/SearchPool`, which is now the
  only pool logic in the repo.
- `:302` — "Built as a TYPED LOCAL rather than an inline table for `ItemService.broadcastEffect`'s
  reason". `broadcastEffect` survives Step 3.1, so this one is still accurate — **verify before
  editing** rather than assuming, and leave it if it still resolves.
- `:283-293` — `foundByPlayer`'s header. This is the substantive half of the step and it resolves
  Follow Up 2: narrow the comment to say plainly that this table is a **debugging aid, not state**,
  and that `ItemService.slot` is the authoritative answer to what a player is holding. Two server
  tables answering nearly the same question is how a later reader picks the wrong one, and this one is
  cumulative (everything ever found) while the slot is current. Keep the secrecy paragraph — it is
  correct and `ItemService.slot` inherits it — and add one sentence naming the other table.

**No logic changes.** `analyze` is the check because it is what proves the file still typechecks after
an edit to a module several services require, and because this step must not quietly change `sendUpdate`
or the hold machinery while it is in the file.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the slot table is server-only and must stay that way. The specific shapes to
  refuse: an attribute on the character naming the item, a `CollectionService` tag on a player, a
  `Tool` in a `Backpack` (which replicates and is visible in the character's hand), and any
  `FireAllClients` whose payload names who found what. Step 5.4 is where this is proven; this is where
  it would be introduced.
- **Remote direction** — no handler changes in this phase; `RequestThrowSalt`'s existing one still
  reads `carried` and must be updated to read `slot` here or in Step 4.2, not left comparing a table
  entry that no longer exists.
- **Rate limiting** — the surviving `RequestThrowSalt` handler keeps its inline `Consume` as the first
  line. A rewrite that moves it below the argument check fails `check:ratelimit`'s proximity match, and
  worse, does work before the token is spent.
- **Magic numbers** — Step 3.3's table, and the `config-ok` waivers keeping their reasons.
- **Phase ownership** — `onPhaseChanged` subscribes; it never calls `setPhase`.
- **Player leaving mid-round** — this whole step. The husk decision above is the load-bearing one.
- **Strict Luau** — `slot[player.UserId]` is `Types.ItemType?`, and every consumer must narrow it.
  `Enums.ItemType.Salt` carries its `:: Types.ItemType` cast already (`Enums.luau:47`), which is what
  makes the three equality tests in `onItemFound` typecheck.
- **Mobile budget** — the deleted `pickupTick` ran a `task.wait(0.25)` loop on the server for the life
  of the server. Nothing replaces it. Dropped items get a `PointLight` each, and §5's light budget is
  enforced by `PerformanceController` — with seven items maximum and most of them held, this is well
  inside it, but count it rather than assume it.
- **Scope** — no barrier, no second monster, no consumable content.

**Issues identified:**

- **A full-handed search currently destroys the item, and that can delete the win condition.**
  `SearchService.completeSearch` marks the container opened, reads the item, appends it to
  `foundByPlayer` and fires `ItemFound` (`SearchService.luau:398-439`) — all before `ItemService` has
  any say. If `ItemCarry` then refuses, the item has left the world and is in nobody's slot. With one
  buntot pagi per round, a survivor who searches its container while holding a pouch removes the second
  win condition from the game, silently. `spillItem` in `onItemFound` is the fix this plan takes
  because it needs no change to `SearchService`; the alternative — having `SearchService` ask
  `ItemService` whether the player can carry it *before* opening the container — is cleaner but
  reverses the dependency and is a V03 change. **Raise this with `exploit-auditor` explicitly**; it is
  the highest-consequence hole in the chunk and it is reachable by honest play, not only by an attacker.
- **`SearchService.foundByPlayer` becomes a second, divergent record of what a player has.** It is a
  cumulative list of everything they ever found; `ItemService.slot` is what they are holding now. They
  will disagree the first time anything is dropped, and that is correct — but two server tables
  describing "what this player has" is how a later reader picks the wrong one. V03 built
  `foundByPlayer` so "a playtester can confirm searching yields items from the server side"
  (`SearchService.luau:287-289`), which is a debugging aid, not state. Either narrow its comment to say
  so plainly, or delete it and let `ItemService.slot` be the single answer. Flagged in Follow Ups
  rather than decided here, because deleting it touches V03's verification story.
- **`Enums.ItemType` is frozen and has exactly three members, but `ContainerLayout.itemAt` returns a
  `Types.ItemType?` from a table `SearchService` seeded.** The narrowing in `onItemFound` is therefore
  defensive rather than necessary today. Keep it: a BindableEvent's arguments are `...any`, and V03's
  own instruction at `SearchService.luau:67-69` is to narrow with a function and not a cast.

### Phase 4: The verbs — throw, drop, and the boundary V09/V10 inherit

#### Step 4.1: `pure/ItemUse` — which item has a verb, and which does not yet

**File:** `src/shared/pure/ItemUse.luau`
**Verify:** `lune run tests/item-use.test.luau`

The V08/V09/V10 boundary as a decision table. `SALT` answers `USE_THROW`; `BAWANG` and `BUNTOT_PAGI`
answer `USE_NOT_IMPLEMENTED`, asserted, so a later chunk flipping a cell is a deliberate edit.

```diff
+--!strict
+--[[
+	ItemUse — does the thing in my hand have a verb yet? (§4.6, V08)
+
+		verbFor(held) -> verdict
+
+	THIS MODULE EXISTS TO MAKE A BOUNDARY MECHANICAL RATHER THAN REMEMBERED. §4.6 gives each of the
+	three items a different verb: salt is thrown, bawang is placed on a doorway for 15 seconds, and
+	the buntot pagi strikes an Aswang that is both Exposed and Weakened. V08 builds the CARRY, the
+	DROP and the SLOT for all three, and the THROW for salt. The other two verbs are V09 and V10.
+
+	WHY THAT IS WORTH A FILE. "Bawang does nothing yet" is a fact that lives nowhere: not in a type,
+	not in a test, and — once V08 ships and the item can be picked up and dropped and looks finished
+	— not in anyone's head either. A reader six weeks later finds an item with no effect and cannot
+	tell a deliberate boundary from a bug, and the two have opposite fixes. Written down here, the
+	boundary is `tests/item-use.test.luau` asserting two cells, and V09 turns one of them red on
+	purpose.
+
+	IT IS NOT A FEATURE FLAG. There is no config, no toggle and no dead code path behind the
+	unimplemented verbs. V09 replaces `USE_NOT_IMPLEMENTED` for BAWANG with a real verdict and a real
+	mechanic in the same chunk, or it does not land.
+
+	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. It takes an item and returns a verb.
+	It never sees a role, a phase, a player or a position — those are the caller's, and the caller
+	asks `ItemThrow` about them. A client that requires and runs this learns that bawang has no verb
+	yet, which it also learns by pressing the key.
+
+	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural.
+]]
+
+export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+export type Verdict = "USE_THROW" | "USE_NOT_IMPLEMENTED" | "USE_NOTHING_HELD"
+
+local ItemUse = {}
+
+--[[
+	EXHAUSTIVE OVER THE THREE ITEMS PLUS THE EMPTY HAND, AND WRITTEN AS AN IF-CHAIN RATHER THAN A
+	LOOKUP TABLE ON PURPOSE.
+
+	A `{ [ItemType]: Verdict }` table would infer its values as plain `string` — a literal union
+	survives `require` as a scalar but NOT inside a table
+	(`.claude/lessons/pure-module-unions-widen-in-lists.md`), so the table would need an annotation
+	that is longer than the branches, and a missing key would return `nil` instead of failing to
+	compile. Branches return the union directly and the analyzer checks every one.
+]]
+function ItemUse.verbFor(held: ItemType?): Verdict
+	if held == nil then
+		return "USE_NOTHING_HELD"
+	end
+
+	if held == "SALT" then
+		return "USE_THROW"
+	end
+
+	--[[
+		BAWANG (V09) AND BUNTOT PAGI (V10). Both answer the same thing, deliberately, and NOT two
+		distinct "not yet" values — a split here would be a hint about which chunk is closer to
+		landing, which is a fact about the roadmap and not about the game.
+	]]
+	return "USE_NOT_IMPLEMENTED"
+end
+
+return ItemUse
```

The suite is short and its two most important assertions are the ones that will go red on purpose:

```diff
+check("salt is thrown", ItemUse.verbFor("SALT") == "USE_THROW")
+check("an empty hand has no verb", ItemUse.verbFor(nil) == "USE_NOTHING_HELD")
+
+--[[
+	THE TWO CELLS V09 AND V10 FLIP.
+
+	READ THIS BEFORE "FIXING" A FAILURE HERE. If one of these two goes red, either the boundary moved
+	deliberately — in which case the chunk that moved it deletes the assertion and replaces it with
+	one about the new verb — or somebody gave an item an effect without building the mechanic behind
+	it. Those have opposite fixes and this file is the only place that tells them apart.
+]]
+check("bawang has no verb until V09", ItemUse.verbFor("BAWANG") == "USE_NOT_IMPLEMENTED")
+check(
+	"the buntot pagi has no verb until V10",
+	ItemUse.verbFor("BUNTOT_PAGI") == "USE_NOT_IMPLEMENTED"
+)
+
+-- The two unimplemented items are INDISTINGUISHABLE, which keeps the roadmap out of the game.
+check(
+	"the two unimplemented items answer identically",
+	ItemUse.verbFor("BAWANG") == ItemUse.verbFor("BUNTOT_PAGI")
+)
+
+-- Exhaustive: every member of the union plus nil, so a fourth item type added later fails here
+-- rather than silently inheriting USE_NOT_IMPLEMENTED. `check:scope` arms `weapons?` for that day.
+local ITEMS: { ItemUse.ItemType } = { "SALT", "BAWANG", "BUNTOT_PAGI" }
+
+for _, item in ITEMS do
+	local verdict = ItemUse.verbFor(item)
+
+	check(`{item} answers with a real verdict`, verdict ~= "USE_NOTHING_HELD", verdict)
+end
```

The `: { ItemUse.ItemType }` annotation on `ITEMS` is the lesson again: without it the loop variable is
`string`, `verbFor` accepts it, and the exhaustiveness this loop claims does not exist.

#### Step 4.2: `RequestThrowSalt` resolves against the slot

**File:** `src/server/Services/ItemService.luau`
**Verify:** `lune run tests/item-throw.test.luau`

The handler keeps its name, its shape and its inline `AntiCheatService.Consume`; what changes is that
it reads a slot and spends it through `ItemUse`.

**The remote is not renamed.** `RequestThrowSalt` still means "I am throwing salt", because salt is the
only item with a throw and V09/V10 give the other two verbs that are not throws. A generic
`RequestUseItem` would need an item argument to be useful — which is the free probe and free duplicator
`RequestDropItem`'s declaration refuses — or it would be `RequestThrowSalt` with a vaguer name. Renaming
it also costs a `Config.AntiCheat.Budgets` key, an `InputController` edit and a `TrialService` comment,
and buys nothing. Say this in Follow Ups so V09 does not re-open it by reflex.

`resolveThrow` changes in three places:

```diff
 local function resolveThrow(
 	thrower: Player,
 	direction: Vector3
-): (Types.SaltVerdict, Player?, Vector3)
+): (Types.ItemThrowVerdict, Player?, Vector3)
 	local character = thrower.Character
 	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
 
 	if root == nil or not root:IsA("BasePart") then
-		return "THROWER_NOT_ALIVE", nil, Vector3.zero
+		return "ITEM_THROWER_NOT_ALIVE", nil, Vector3.zero
 	end
```

```diff
-		local verdict = SaltThrow.evaluate({
+		local verdict = ItemThrow.evaluate({
 			Phase = RoundService.GetPhase(),
 			ThrowerState = RoundService.GetPlayerState(thrower),
-			Carried = carried[thrower.UserId] or 0,
+			-- V08. The slot, not a count. `pure/ItemThrow` collapses "holding a bawang" into MISS
+			-- with the four geometric worlds; see its header for why that fifth world may not be
+			-- split out even though the thrower already knows what they are holding.
+			Held = slot[thrower.UserId],
 			ThrowerPos = vec(origin),
 			Direction = vec(direction),
 			TargetPos = vec(candidateRoot.Position),
 			TargetIsTransformedAswang = isTransformedAswang,
-			Range = Config.Salt.ThrowRange,
-			ConeDegrees = Config.Salt.ThrowConeDegrees,
+			Range = Config.Items.SaltThrowRange,
+			ConeDegrees = Config.Items.ThrowConeDegrees,
 		})
```

```diff
 		if verdict ~= "OK" and verdict ~= "MISS" then
 			-- The cast is load-bearing and is CLAUDE.md's documented Luau bite: refining a literal
 			-- union by excluding two of its members widens the remainder to plain `string`, which
 			-- then fails to satisfy the declared return type. Six of the scaffold's seven original
 			-- analyze errors were this exact shape.
-			return verdict :: Types.SaltVerdict, nil, origin
+			return verdict :: Types.ItemThrowVerdict, nil, origin
 		end
```

**The `SmokeBlocks` line inside the `OK` branch does not move and does not change** (V07,
`ItemService.luau:594-612`). Its comment explains that a smoke cloud must break a throw exactly as it
breaks a kill, and that a `MISS_SMOKE` would be the worst of the split verdicts — produced only when the
Aswang has planted a cloud, delivered to a survivor, naming a direction. V08's fifth MISS world joins
that same collapse; nothing about the argument changes.

And the handler, whose one substantive change is what "spend" means:

```diff
 			local verdict, target, impact = resolveThrow(player, direction)
 
 			if verdict ~= "OK" and verdict ~= "MISS" then
 				if Config.Debug.VerboseLogging then
 					-- A UserId and a verdict. Never the target, and never a role.
 					print(`[ItemService] Throw refused for {player.UserId}: {verdict}`)
 				end
 
 				return
 			end
 
-			-- §4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO.
-			carried[player.UserId] = math.max(0, (carried[player.UserId] or 0) - 1)
+			--[[
+				§4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO, and this line sits
+				above the hit branch so that no future early-return can skip it. A miss that cost
+				nothing would make salt a probe you throw at everyone, which is the thing
+				`pure/ItemThrow`'s header refuses.
+
+				V08: THE SLOT IS CLEARED RATHER THAN DECREMENTED, and only reaching here means the
+				slot held SALT — `ItemThrow` returns MISS for the other two and `ITEM_NO_ITEM` for an
+				empty hand, and both of those either returned above or fall through to here having
+				already been resolved. Assert it rather than assume it: a `MISS` produced by holding
+				a bawang must NOT clear the slot, or a survivor loses the buntot pagi by pressing the
+				throw key with it in hand.
+			]]
+			if ItemUse.verbFor(slot[player.UserId]) ~= "USE_THROW" then
+				return
+			end
+
+			slot[player.UserId] = nil
```

**That guard is the bug this step exists to not ship.** Without it, a player holding the round's only
buntot pagi who presses the throw key gets `MISS` from `ItemThrow` — correctly, since the fifth world
collapses into it — and the old `carried = carried - 1` line would have destroyed the win condition on
a keypress. The guard runs `ItemUse.verbFor` rather than comparing to `"SALT"` inline, so the boundary
Step 4.1 pinned is the boundary the service enforces.

**Its position is load-bearing too.** It sits *below* the refusal branch, so a wrong-item press still
burns an AntiCheat token and still returns silently; and *above* the noise emit, so a press with a
bawang in hand makes no noise. That second half matters: `NoiseService.Emit` fires on a miss precisely
so a throw sounds the same whether or not it hit (`ItemService.luau:684-697`), and a noise that fired
for a non-throw would be a free "I am holding something that is not salt" broadcast to everyone within
`Config.Noise` radius.

**`lune run tests/item-throw.test.luau` is the check** rather than a grep, and the suite must gain one
assertion for the guard above — that `evaluate` with `Held = "BUNTOT_PAGI"` returns `MISS` and that
`ItemUse.verbFor("BUNTOT_PAGI")` is not `USE_THROW`, which together are the two halves the service ANDs.

#### Step 4.3: `RequestDropItem` — the handler

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:ratelimit`

Argument-free, token consumed first, verdict never echoed, item placed in the world where the player
stands so it can be picked up again by anyone.

```diff
+	--[[
+		THE RATE LIMIT IS INLINE AND FIRST, copying the throw handler above it and MonsterService's
+		two exactly. `check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|
+		Permit)` within 1200 characters of an `.OnServerEvent:Connect(`, by its own admission a
+		proximity tripwire — so a handler that IS limited but does it elsewhere reads as unguarded
+		and fails the build. Consume FIRST, before anything is read.
+
+		THERE IS NO ARGUMENT TO VALIDATE, which is the point of the declaration in Remotes.luau. The
+		throw handler needs a `typeof(direction) ~= "Vector3"` guard because a client sends a vector;
+		this one reads a server table and a server position and nothing else.
+	]]
+	Remotes.Get("RequestDropItem").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestDropItem") then
+			return
+		end
+
+		local verdict = ItemDrop.evaluate({
+			Phase = RoundService.GetPhase(),
+			PlayerState = RoundService.GetPlayerState(player),
+			Held = slot[player.UserId],
+		})
+
+		--[[
+			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK — the throw handler's rule,
+			inherited. The client learns its hand is empty from its own next snapshot, which is a
+			per-player `FireClient` it was going to receive anyway.
+		]]
+		if verdict ~= "OK" then
+			if Config.Debug.VerboseLogging then
+				-- A UserId and a verdict. NEVER the item: an item id beside a UserId in the log is
+				-- the roster `slot`'s comment refuses to build, written to disk.
+				print(`[ItemService] Drop refused for {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		spillItem(player, slot[player.UserId])
+		slot[player.UserId] = nil
+	end)
```

`pure/ItemDrop.luau` is a fourth small module with the same shape as `ItemCarry` — phase, then the
allowlist of ALIVE, then "are you holding anything" — returning `Types.ItemDropVerdict`. It has no
geometry, for the reason written into that type in Step 2.2: placement is V09's mechanic and building
half of it here would be building it without its rules.

**Dropping makes no noise, and that is a refusal rather than an omission.** §4.4 names four noisy
actions and dropping is not one of them, exactly as `MonsterService`'s header says feeding is not
(`MonsterService.luau:38`). More sharply: a drop cue would let anyone within noise radius hear the
buntot pagi's carrier decide to put it down, which is §4.5's "I have the buntot pagi" phrase — a
*choice* with a cost — converted into an automatic broadcast. Write that into the handler.

**The world part, and why pickup is `Touched` rather than a tick.**

```diff
+--[[
+	AN ITEM ON THE FLOOR. A part, a tag, a colour and nothing else — `spawnPouches`' shape, kept.
+
+	THE `DroppedItem` TAG IS REPLICATED AND THAT IS FINE, on the argument C13's `SaltPouch` tag won:
+	it describes an object in the world every client can already see, it names no player, and the
+	client needs it to draw a pickup affordance at all. `check:secrecy` inspects tags and this one
+	passes because it carries nothing — the ITEM TYPE is in the part's colour and label, which is
+	also public and also has to be, because a player has to be able to tell salt from the win
+	condition before walking over it.
+
+	WHAT MUST NOT GO ON IT: the UserId of whoever dropped it, in the Name, in an attribute, or in a
+	child value. "Who dropped this" is a fact about a player. A dropped item with a name like
+	`Dropped_12345` is a per-player fact lying on the floor of the barrio, readable by every client,
+	and no check in this repo would report it.
+]]
+local TAG_DROPPED = "DroppedItem"
```

Pickup resolves on a `Touched` connection on the dropped part, **with a server-side distance re-check
inside the handler**. `Touched` is a hint that something is nearby; the authority is the same
comparison `pickupTick` made — `(part.Position - root.Position).Magnitude <= Config.Items.DropPickupRangeStuds`
— read from the player's own character on the server. That keeps C13's rule ("the server resolves what
a player is standing at from that player's own character position") while removing the per-tick sweep
the deleted `pickupTick` ran forever.

The handler then runs `ItemCarry.evaluate` exactly as `onItemFound` does, and on `OK` destroys the part
and fills the slot. On any refusal it does nothing and the item stays on the floor, which is the
correct §4.4 outcome and needs no `spillItem` — the item never left the world.

**A `Touched` connection fires on the server for any BasePart, including a corpse, a dropped item, and
a part of the map.** Narrow to a `Humanoid`-owning character whose `Player` is resolvable, then to
ALIVE via `RoundService.GetPlayerState`. `ItemCarry` re-checks the state anyway; the narrowing is to
avoid resolving a player for every leaf that brushes the part.

**`npm run check:ratelimit` is the check** because the failure this step can ship is precisely the one
that check exists for: an `OnServerEvent` handler that does work before consuming a token. It is a text
tripwire and proves only that the call is near the connect — which is why the `Consume` must be the
first statement, not merely present.

#### Step 4.4: Salt's five jobs, audited rather than rebuilt

**File:** `src/server/Services/MonsterService.luau`

`ApplySaltHit` already does all five. This step changes no logic; it adds the V08 comment that names
the five and states that `ItemService` is the only caller, so the next reader of that function knows
what may not be reordered. Deliberately carries no `**Verify:**` line — the chunk's own Verify makes
this the playtester's, and a green check here would prove only that a comment was typed.

The five jobs, traced to the lines that already do them
(`src/server/Services/MonsterService.luau:2926-3011`):

| §4.6 job | Line | How |
| --- | --- | --- |
| Force revert | `:2951-2952` | `endFeed(userId, "FEED_INTERRUPTED")` then `revert(player)` |
| `Exposed` for `SaltRevealDuration` | `:2954` | `applyExposed(player)`, which arms a generation-guarded `task.delay` |
| −`SaltDamage` health | `:2953` | `applyHealthEvent(userId, "SALT")` → `pure/MonsterHealth`, floored at `WeakenedThreshold` |
| Interrupt any in-progress feed | `:2951` | `endFeed` with a verdict, the path that pays neither `HealFromFeed` nor `FeedCompleted` |
| Set `hasBeenRevealed` | `:3006-3010` | `CamouflageRules.revealedAfter(flag, "SALT_HIT")` |

Plus a sixth that V07 added ahead of the other five: `exitCamouflage(player)` at `:2940`, which must
stay first because `revert` restores from `OriginalParts` and `applyCamouflageLook` overwrote them.

```diff
+	V08 CLOSES THE LOOP AND CHANGES NOTHING. V05, V06 and V07 each landed their share of §4.6's five
+	jobs as they built the systems behind them; V08 is the chunk that gives salt a way to be thrown
+	at containers-sourced items, and it found all five already here.
+
+	SO THIS IS THE FULL LIST, IN ORDER, AND THE ORDER IS THE FUNCTION'S CORRECTNESS:
+
+	  1. exit camouflage    — before revert, or the character reverts into a cat's parts   (V07)
+	  2. interrupt the feed — before revert, so the interruption is exact rather than raced (V06)
+	  3. force the revert   — §4.6's headline effect                                        (C14)
+	  4. −SaltDamage        — through pure/MonsterHealth, floored at WeakenedThreshold      (V05)
+	  5. Exposed for SaltRevealDuration — the glow, whose brightness reads the health       (V05)
+	  6. HasBeenRevealed    — through CamouflageRules.revealedAfter, the camouflage gate    (V07)
+
+	`ItemService` IS THE ONLY CALLER, and V08 kept it that way. There is no bare `ForceRevert`, no
+	bare `Expose` and no way to damage the monster from outside this function — so there is no path
+	that reverts without damaging, damages without revealing, or reveals without opening the gate.
+	That property is worth more than any of the six individually: each was added by a different
+	chunk, and the only thing that stopped them drifting apart is that they share one entry point.
+
+	ADDING A SEVENTH JOB MEANS EDITING THIS LIST. Adding a second CALLER means arguing with this
+	paragraph first.
```

**The whole of this step is that comment.** No logic changes; `ApplySaltHit`'s body is correct as
shipped and the reasoning for every ordering decision is already written beside the line it governs.

**Why no `**Verify:**` line.** There is no mechanical check that proves this. `grep -q "V08 CLOSES THE
LOOP" src/server/Services/MonsterService.luau` would pass the instant the text was typed and would prove
authorship, not behaviour — the exact trap this plan's check discipline names. The five jobs are proven
by the chunk's own Verify line instead: **a playtester lands a salt hit and confirms the glow, the
revert and the health change in console output**, with `Config.Debug.VerboseLogging` on. That is a
runtime observation of all five at once, and it is what `artifacts/` is for. `next-phase.mjs` will mark
this phase `needs-human`, which is the accurate report.

What the playtester must capture, so `verification.md` cites something specific:

- A screenshot of a transformed Aswang **before** the throw and **after**, showing the revert and the
  Highlight.
- Console output showing the health change — `applyHealthEvent`'s verbose line — with the value
  dropping by exactly `Config.Items.SaltDamage` and floored at `Config.Monster.WeakenedThreshold` on
  the fourth hit.
- A hit landed **mid-feed**, with `FEED_INTERRUPTED` in the log and no `FeedCompleted` after it. This is
  the job most likely to be silently broken and the only one whose absence looks like nothing.
- A camouflage attempt **before** any salt hit (must be refused, `NOT_REVEALED`) and one **after** a
  hit and a completed feed (must succeed). That is the `HasBeenRevealed` gate, end to end.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the throw handler returns nothing to the caller on any path, including OK, and
  the drop handler must match it. `SaltEffect` keeps its three trajectory fields and gains none:
  `Types.luau:334-338` warns that an EXTRA field on an annotated table is accepted silently and that
  `SaltEffect` is not on `check-secrecy.mjs`'s allowlist, so a `TargetUserId` there would pass every
  check in this repo and name the monster to eight clients.
- **Remote direction** — `RequestDropItem` is fired from the client, listened to on the server. The
  drop has no server→client counterpart and does not need one.
- **Rate limiting** — both handlers consume first, inline, as their first statement.
- **Magic numbers** — `Config.Items.SaltThrowRange`, `ThrowConeDegrees`, `DropForwardStuds`,
  `DropPickupRangeStuds`. Nothing else.
- **Phase ownership** — both handlers read `RoundService.GetPhase()` and pass it to a pure module.
  Neither sets it.
- **Player leaving mid-round** — a `Touched` connection on a dropped part outlives the player who
  dropped it, by design. It must resolve the toucher fresh each time and never close over a `Player`.
- **Strict Luau** — the `:: Types.ItemThrowVerdict` cast at the refusal return, which is the documented
  widening bite; and `slot[player.UserId]` being `Types.ItemType?` everywhere it is read.
- **Mobile budget** — each dropped item is one anchored part, one BillboardGui and one PointLight.
  Seven items is the ceiling and most are held rather than dropped, but §5's light cap is enforced by
  `PerformanceController` and this is new light in the world — count it in the playtest.
- **Scope** — `ItemUse` returning `USE_NOT_IMPLEMENTED` twice is the scope line, mechanically.

**Issues identified:**

- **The throw guard in Step 4.2 is the highest-value line in the phase and it is easy to omit.** Without
  it, pressing the throw key while holding the buntot pagi destroys the round's only win condition, and
  the symptom is a `MISS` — which is exactly what a legitimate missed throw looks like. Nothing in the
  game reports it and no static check can see it. Ask `exploit-auditor` about this line by name.
- **`ItemDrop` is a fourth pure module and the plan should say why it is not a branch of `ItemCarry`.**
  They share three of four inputs. Kept separate because their verdicts mean opposite things — one
  refuses an item entering a full slot, the other refuses an empty one — and because a merged module
  would take a "direction" parameter, which is how one rule becomes two rules in a trench coat. If the
  implementer finds `ItemDrop` is under fifteen lines and its test under twenty, that is the expected
  size, not a sign it should be merged.
- **`SaltEffect` is still named for salt while the drop has no effect broadcast at all.** That is
  correct — a dropped item is a part appearing in the world, which every client sees without a remote —
  but it means the client cannot play a drop sound. Left out deliberately; a per-player drop sound is
  the derived-hint shape Step 5.4 exists to refuse, and a broadcast one is a noise cue §4.4 does not
  authorise. Raised in Follow Ups.

### Phase 5: The client, and the tell that must not exist

#### Step 5.1: `YourCarriedItem` gets a producer

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run check:secrecy`

A provider seam, because `ItemService` requires `RoundService` and the reverse would be a cycle.

`Types.ClientRoundSnapshot.YourCarriedItem` has existed since V02 and has **no producer**:
`buildSnapshot` (`RoundService.luau:626-633`) sets four fields and deliberately not this one, exactly as
it deliberately does not set `YourRole`. V02's comment says so and says why — "V02 ADDS NO PRODUCER …
so no service changes and `analyze` stays clean". V08 is the chunk that adds it.

**The dependency runs the wrong way.** `ItemService` requires `RoundService`
(`ItemService.luau:34`); `RoundService` requires `RoleService` and four shared modules and nothing else
(`RoundService.luau:23-36`). A `require(script.Parent.ItemService)` in `RoundService` is a cycle, and
Luau resolves cycles by returning a partially-initialised table — which fails at runtime, in one
direction only, depending on which service `init.server.luau` touched first.

```diff
+--[[
+	V08, §4.6. WHO ANSWERS "WHAT IS THIS PLAYER HOLDING", AND WHY IT IS INJECTED.
+
+	`ItemService` owns the slot and `ItemService` requires THIS service — for the phase, the player
+	state and the Aswang's UserId. A require in the other direction is a cycle, and Luau answers a
+	cycle with a half-built table rather than an error, so it would fail at runtime in whichever
+	direction `init.server.luau` happened to resolve first.
+
+	SO THE OWNER REGISTERS ITSELF. `ItemService.Start` calls this; `buildSnapshot` asks it. Same
+	shape as `RoundService.PhaseChanged`, pointed the other way: there, subscribers reach in; here,
+	the owner hands in a reader.
+
+	IT RETURNS ONE PLAYER'S OWN ITEM AND CANNOT BE ASKED ABOUT ANOTHER. The provider takes the
+	Player `buildSnapshot` is already building for, and `buildSnapshot` is called once per player and
+	sent with `:FireClient`. There is no broadcast form of this payload — `broadcastSnapshot` loops
+	and fires individually for exactly this reason (`:637-641`), and that loop is what makes
+	`YourState` safe today.
+
+	nil UNTIL `ItemService.Start` RUNS, and `buildSnapshot` handles that: a snapshot built during
+	bootstrap carries no item, which is also the truth. Not an error, not a warn — this is called
+	every `Round.SnapshotInterval` and a warn here would be a log flood in a Studio session.
+]]
+local carriedItemProvider: ((Player) -> Types.ItemType?)? = nil
+
+function RoundService.SetCarriedItemProvider(provider: (Player) -> Types.ItemType?)
+	carriedItemProvider = provider
+end
```

```diff
 local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
 	return {
 		Phase = state.Phase,
 		SecondsRemaining = RoundService.GetSecondsRemaining(),
 		RoundNumber = state.RoundNumber,
 		YourState = RoundService.GetPlayerState(player),
+		--[[
+			V08. THE PLAYER'S OWN SLOT, AND THE `Your` PREFIX IS THE WHOLE CONTRACT — see
+			Types.ClientRoundSnapshot, which argues this field at length and whose arguments V08 is
+			now relying on rather than restating.
+
+			THE ONE THAT MATTERS HERE: the Aswang's slot is `nil` far more often than a survivor's,
+			because the monster is usually hunting rather than searching — but `nil` is ALSO what an
+			empty-handed survivor sends, and the two are the same value on the same field at the same
+			cadence. What would break that is a special case: an `if isAswang then nil end`, or a
+			"cannot carry" member added to ItemType for the monster's benefit. Neither exists, and
+			`ItemService.slot`'s own comment refuses both.
+		]]
+		YourCarriedItem = if carriedItemProvider ~= nil then carriedItemProvider(player) else nil,
 	}
 end
```

and in `ItemService.Start`, beside the existing `RoundService.PhaseChanged` connect:

```diff
+	-- V08. The snapshot's producer for `YourCarriedItem`. Registered rather than required, because
+	-- this service requires RoundService and the reverse would be a cycle; see that function.
+	RoundService.SetCarriedItemProvider(function(player: Player): Types.ItemType?
+		return slot[player.UserId]
+	end)
```

**`npm run check:secrecy` is the check** because this step puts a new field on the wire and that is
precisely the surface the check watches. It will pass — the field carries no role token and the send is
a `FireClient` — and passing is not the same as being safe here, which is why Step 5.4 exists and why
`exploit-auditor` gets asked about the snapshot explicitly.

#### Step 5.2: The HUD stops guessing

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `npm run lint`

Delete the `ChildRemoved` pouch estimate and the `~` prefix that apologised for it; read the slot off
the snapshot instead.

The HUD currently **guesses**. `UIController` watches the `SaltPouches` folder for `ChildRemoved`,
distance-gates it against `Config.Salt.PickupRangeStuds`, clamps the result to `CarryLimit`, and
decrements optimistically from `UIController.NoteThrow()` when the throw key is pressed
(`UIController.luau:1975-2020`, `InputController.luau:289-292`). Its own comment explains the `~`
prefix: the estimate can be wrong, and it self-corrects on the next pickup.

All of that machinery exists because C13 had no truthful channel. V08 has one.

```diff
-	if pouches ~= nil then
-		pouches.ChildRemoved:Connect(function(pouch: Instance)
-			…
-			if (pouch.Position - root.Position).Magnitude <= Config.Salt.PickupRangeStuds then
-				saltSeen = math.min(saltSeen + 1, Config.Salt.CarryLimit)
-			end
-		end)
-	end
```

```diff
-function UIController.NoteThrow()
-	saltSeen = math.max(0, saltSeen - 1)
-end
```

The whole `saltSeen` local, the folder lookup and the `~` prefix in the label go with them. What
replaces it is one field read in the existing `RoundSnapshot` handler:

```diff
+--[[
+	V08. THE CARRY IS NOW TRUTH, NOT AN ESTIMATE, AND THE `~` IS GONE WITH THE GUESS.
+
+	C13's HUD counted `SaltPouches.ChildRemoved` within the pickup radius and decremented on a
+	keypress, because there was no channel carrying the real answer. `ClientRoundSnapshot`
+	`YourCarriedItem` is that channel: server-owned, per-player, `FireClient`-only, refreshed every
+	`Round.SnapshotInterval`. An estimate that can be wrong is worse than a value that lags half a
+	second, because a wrong number reads as a broken game — C13 found that when two players near one
+	pouch both incremented and the HUD showed a count the rules made impossible.
+
+	IT SHOWS ONLY THIS CLIENT'S OWN SLOT AND THERE IS NO OTHER SLOT TO SHOW. The snapshot has no
+	field for another player's carry and must not grow one — §4.5's "I have the buntot pagi" is a
+	phrase a player CHOOSES to say, and a HUD that showed who held what would delete its reason to
+	exist. See Types.ClientRoundSnapshot.
+]]
```

The label draws the item's name from the item type rather than a count — "SALT", "BAWANG",
"BUNTOT PAGI", or nothing at all for an empty hand. Copy comes from a shared pure module if one is
wanted, on `pure/TeachingLines`' argument that player-facing text should have one home and should not
cross the wire; a three-branch `if` in the controller is also acceptable at this size. The label being
**absent** rather than showing "NONE" is deliberate: an empty hand is the common case for both a
survivor between finds and the Aswang, and a persistent "NONE" element is a thing whose absence would
be readable if it were ever conditionally hidden.

**`npm run lint` is the check** because this step is mostly deletion, and selene is what reports the
locals, upvalues and functions the cut leaves behind — `saltSeen`, the folder handle, and
`UIController.NoteThrow`, whose caller in `InputController` is removed in Step 5.3. A stale
`NoteThrow()` call would be an analyzer error; a stale `saltSeen` would be a silent unused local, which
is the one only selene catches.

#### Step 5.3: `InputController` keeps one key and no item logic

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run check:remotes`

The throw key still fires `RequestThrowSalt` (or the trial's sibling); a drop key fires
`RequestDropItem`. Neither decides anything.

```diff
 	if TrialController.IsActive() then
 		Remotes.Get("RequestTrialThrow"):FireServer(camera.CFrame.LookVector)
 	else
 		Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
 	end
 
-	UIController.NoteThrow()
-
 	return true
 end
```

The optimistic decrement goes with Step 5.2's estimate. The HUD now updates from the next snapshot,
which is at most `Config.Round.SnapshotInterval` (0.5s) away — and the throw's own feedback is
immediate and diegetic anyway: `SaltEffect` broadcasts a burst at the impact point, which every client
including the thrower's renders.

The drop key is a second action on the same `ContextActionService` surface as the throw:

```diff
+--[[
+	V08. THE DROP KEY, AND IT DECIDES NOTHING.
+
+	NO ARGUMENT AND NO CLIENT-SIDE CHECK. `Config.Items.CarryLimit` is 1, so the server already knows
+	what this player is holding, and `pure/ItemDrop` on the server owns whether they may put it down.
+	A `if carried == nil then return end` guard here would be a second copy of a rule, and the two
+	would disagree the first time a pickup and a drop crossed on the wire — which is verbatim the
+	reasoning this file already gives for not pre-checking the throw (see performThrow's header).
+
+	MOBILE GETS A BUTTON, NOT A KEY. §5 puts ~60% of players on a phone; `ContextActionService`'s
+	touch button is how the throw already reaches them, and the drop is the same kind of deliberate,
+	rare press. Its thumb-zone placement is `ui-polish`'s question, not this chunk's.
+]]
+local DROP_ACTION = "ItemDrop"
```

**`npm run check:remotes` is the check.** It catches the two failures this step can actually produce: a
remote fired from the client that is not declared in `EVENTS_UP`, and a remote fired in the wrong
direction. Both are silent otherwise — a `WaitForChild` on a name the server never created **hangs
forever**, with no error, no output and no stack trace.

#### Step 5.4: The carried item is not a role tell

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run verify`

The explicit step this chunk exists to not get wrong: no Tool in a Backpack, no Highlight, no
character attribute, no CollectionService tag on a player, no sound played to one client.

**This step adds no code. It is a review with a check attached, and it is a step rather than a note
because the leak it looks for is the kind that ships green.** C04 shipped a permanent role brand with
`analyze`, all five checks and six Lune suites passing over it; C14 shipped a second one in the same
pair of services. Both were found by `exploit-auditor`, not by a gate.

The specific question: **does anything V08 added let a second client tell who is holding what?** Seven
shapes, each of which replicates and none of which contains the word "role":

| Shape | Why it leaks | Status after V08 |
| --- | --- | --- |
| A `Tool` in the player's `Backpack` | Replicates; a held Tool is **visible in the character's hand** to everyone | Not used. The slot is a table entry |
| An `Attribute` on the character or Player | Replicates to every client. There is no private one | Not used |
| A `CollectionService` tag on a character | Replicates. `check:secrecy` inspects tags | Only on the dropped PART, never on a player |
| A `Highlight` or any per-player visual | C04's exact bug | Not used. The only Highlight in the game is the Exposed glow, `MonsterService`'s |
| A sound played with `FireClient` | Audible difference between clients is a difference | No drop sound, deliberately — Step 4.3 |
| The dropped part's `Name` or a child value | A part named `Dropped_12345` is a per-player fact on the floor | Names carry the item type only — Step 4.3 |
| A `WalkSpeed` or movement difference | C14's exact bug; `Humanoid.WalkSpeed` is replicated and pollable | Nothing in V08 touches movement |

**The one that needs thinking about rather than checking off is the seventh row's cousin: absence.**
`.claude/lessons/absence-is-observable.md` is the relevant lesson, and V07's build-plan entry states the
failure shape — four players visible, one missing, and anyone who counts knows. Applied here:

- **The Aswang carries nothing more often than survivors do.** That is a statistical difference, not a
  mechanical one, and it is *correct*: it comes from the monster choosing to hunt rather than search,
  which is a choice it may reverse at any time. §4.4 has the Aswang searching on identical rules
  precisely so that the choice exists. What must not happen is anything that makes the difference
  categorical — a refusal, a skipped code path, an early return keyed on the role.
- **So the assertion is: no branch in `ItemService` reads the role.** `resolveThrow` is the only place
  in the file that touches `RoundService.GetAswangUserId()`, it ANDs it with `IsTransformed` into one
  boolean about a *target*, and `pure/ItemThrow` never learns a role exists
  (`ItemService.luau:551-556`). `onItemFound`, the drop handler, the pickup `Touched` handler and the
  provider must contain **no role read at all**. Grep the finished file for `GetAswangUserId` and expect
  exactly one hit.
- **And the empty slot must be indistinguishable on the wire.** `YourCarriedItem` is `nil` for an
  empty-handed survivor and `nil` for an empty-handed Aswang — the same absent field on the same
  per-player payload at the same cadence. There is no third value and no "cannot carry" member, and
  `Types.luau:443-446` names adding one as the mistake.

**`npm run verify` is the check** — the whole gate, deliberately, as the last step of the last phase.
Every one of the five repo checks bears on something this chunk touched: `check:remotes` on the new
remote, `check:secrecy` on the snapshot field and the tags, `check:config` on the moved item block,
`check:ratelimit` on the drop handler, `check:scope` on the three items. Running them individually
would prove each in isolation; this proves the tree.

**And `npm run verify` being green here proves less than it looks like it does.** Static green over a
secrecy surface means very little — that is CLAUDE.md's finding from C04, in this exact pair of
services. The real check for this step is `exploit-auditor`, briefed as below.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — this phase is the leakage review. The seven-row table above is the checklist and
  the absence argument is the part a table cannot hold.
- **Remote direction** — `RequestDropItem` up, nothing new down. `check:remotes` in Step 5.3.
- **Rate limiting** — no new handler in this phase; Step 4.3's is the last one.
- **Magic numbers** — the HUD's label copy is text, not a tunable. Any spacing or sizing added to the
  carry element is presentation and takes a `config-ok` waiver with a reason, as the existing HUD does.
- **Phase ownership** — `buildSnapshot` reads `state.Phase`; the provider seam sets nothing.
- **Player leaving mid-round** — `carriedItemProvider` closes over `ItemService.slot`, and a departed
  player's entry is nilled by the `PlayerRemoving` handler in Step 3.4. `buildSnapshot` is never called
  for a player who has left, but the provider returns `nil` for an absent key regardless.
- **Strict Luau** — `carriedItemProvider` is `((Player) -> Types.ItemType?)?`, doubly optional, and
  `buildSnapshot`'s `if … then … else nil` is what narrows it. A direct call would be a type error,
  which is the desired shape.
- **Mobile budget** — one more HUD element and one more `ContextActionService` touch button. §5 and
  `ui-polish` own the thumb zones; the element itself is a TextLabel.
- **Scope** — the HUD shows one slot. It does not show a second player's, an inventory, or a count.

**Issues identified:**

- **The provider seam is a new pattern in this repo and needs the justification Hard Rule 4 asks for.**
  Every other cross-service link here is either a direct `require` in the allowed direction or a
  `BindableEvent` the owner exposes (`RoundService.PhaseChanged`, `MonsterService.FeedCompleted`,
  `SearchService.ItemFound`). This is the first *injected reader*. A BindableEvent cannot do this job —
  events push, and `buildSnapshot` needs to pull, synchronously, at snapshot time. The alternative is
  `ItemService` pushing a `CarryUpdate` remote of its own, which adds a second server→client remote for
  a field the snapshot already declares, and gives the HUD two sources for one value. The seam is the
  smaller change; it is flagged here so the auditor evaluates it rather than discovering it.
- **`UIController.NoteThrow` is public API being deleted.** Grep for other callers before removing it;
  `InputController` is the only one this plan found, but the function is on the module table and
  `OnboardingController` and `TrialController` both draw HUD.
- **The trial's HUD still shows a salt count that no longer comes from anywhere.** C22 hands the player
  a scripted pouch outside the container system (Step 2.1's `TrialPickupRangeStuds`). Whatever
  `UIController` drew for the trial's salt must now be driven by the trial's own state rather than by
  the deleted `saltSeen`, or the tutorial teaches a throw while the HUD shows an empty hand. This is
  the most likely missed consequence of Step 5.2 — flag it for the playtester as a specific thing to
  open the trial and look at.

## 3. Related Files

Every file below was read while planning and has an annotated review in `references/`.

| File | Role in this plan | Review |
| --- | --- | --- |
| `src/server/Services/ItemService.luau` | The service being reworked. Phases 3, 4, 5 | `ItemService-review.luau` |
| `src/shared/pure/SaltThrow.luau` | Migrates to `ItemThrow`. Phase 1 | `SaltThrow-review.luau` |
| `src/shared/pure/SaltCarry.luau` | Migrates to `ItemCarry`. Phase 1 | `SaltCarry-review.luau` |
| `src/shared/Config.luau` | `Items` is canonical; `Config.Salt` dies. Phase 2 | `Config-review.luau` |
| `src/shared/Types.luau` | `YourCarriedItem`, the verdict unions. Phases 2, 5 | `Types-review.luau` |
| `src/shared/Remotes.luau` | `RequestDropItem`. Phase 2 | `Remotes-review.luau` |
| `src/server/Services/MonsterService.luau` | `ApplySaltHit` — the five jobs. Phase 4 | `MonsterService-review.luau` |
| `src/server/Services/SearchService.luau` | `ItemFound`, the seam items arrive through. Phase 3 | `SearchService-review.luau` |
| `src/server/Services/RoundService.luau` | The snapshot and the provider seam. Phase 5 | `RoundService-review.luau` |
| `src/client/Controllers/UIController.luau` | The guessed carry count, deleted. Phase 5 | `UIController-review.luau` |
| `src/client/Controllers/InputController.luau` | The throw key and the drop key. Phase 5 | `InputController-review.luau` |

Read but not reviewed separately, because nothing in them changes: `src/shared/Enums.luau`
(`ItemType` already correct at `:46-49`), `src/shared/pure/CamouflageRules.luau` (`revealedAfter` is
`ApplySaltHit`'s transition table), `src/server/init.server.luau` (bootstrap order, quoted in Step 3.2),
`docs/MVP-SPEC.md` §3/§4.6/§6.5, `docs/BUILD-PLAN.md` V07-V10, `tests/salt-carry.test.luau`,
`tests/salt-throw.test.luau`, `tests/config.test.luau`, `tests/anti-cheat-budgets.test.luau`,
`.claude/scripts/check-secrecy.mjs`.

## 4. Follow Ups

### Questions / Clarifications

1. **The build plan says `BawangSpawnCount`; the code says `GarlicSpawnCount`.** The brief for this
   chunk names `BawangSpawnCount`, and `src/shared/Config.luau:68` declares `GarlicSpawnCount = 2`,
   read as such by `SearchService.TotalItems()` (`:118`). The spec (§4.6) heads the section "Bawang
   (garlic)" and uses both words. **This plan uses the name on disk and renames nothing** — a rename
   would touch `Config`, `SearchService` and `tests/config.test.luau` for vocabulary, in a chunk with
   real work in it. But the split is a genuine trap: `Types.ItemType` is `"BAWANG"` while the Config
   key is `Garlic*`, so a reader greps one and misses the other. Worth one vocabulary chunk later, or
   a comment on the Config key naming its `Types` counterpart. **Not decided here.**

2. **Does `SearchService.foundByPlayer` survive V08?** It is a cumulative per-player list of everything
   found, built at V03 explicitly so "a playtester can confirm searching yields items from the server
   side" (`SearchService.luau:287-289`). After V08, `ItemService.slot` is the authoritative answer to
   "what does this player have", and two server tables answering nearly the same question is how a
   later reader picks the wrong one. Deleting it weakens V03's verification story; keeping it needs its
   comment narrowed to "debugging aid, not state". **Recommend narrowing the comment, not deleting.**

3. **Should `RequestThrowSalt` be renamed?** V09 and V10 will add verbs that are not throws, and a
   reader may reach for a generic `RequestUseItem`. This plan says no — a generic remote needs an item
   argument to be useful, which is the free probe and free duplicator `RequestDropItem`'s declaration
   refuses, and without one it is `RequestThrowSalt` with a vaguer name. Recorded so V09 does not
   re-open it by reflex.

4. **What does the trial's HUD show after Step 5.2?** C22 hands the player a scripted pouch that is not
   in a container and is not in `ItemService.slot`. The deleted `saltSeen` estimate was driving that
   display. Either `TrialService` gains its own snapshot field or `TrialController` draws it locally.
   **This plan does not answer it** and the playtester must open the Solo Trial and look.

5. **Should a dropped item persist across the ENDING phase?** Step 3.2 sweeps on INTERMISSION and IDLE,
   mirroring `MonsterService.clearCorpses`, so items lie on the ground through ENDING as scenery. That
   seems right — §4.8's reveal is the point of that phase and a tidy floor is not — but it means the
   buntot pagi is visible beside a corpse during the end screen, which is a nice image and might also
   be a distraction. A judgement for V16.

6. **`Roblox API behaviour not confirmed in this codebase: `Touched` on an anchored `CanCollide = false`
   part.** Step 4.3's pickup relies on it firing for a walking character. The repo has no precedent —
   C13 explicitly chose a distance tick over a `ProximityPrompt` and never used `Touched`, and C08 found
   that a `ProximityPrompt` with `KeyboardKeyCode = None` will not render. **This is the one unverified
   Roblox behaviour in the plan**, which is why the pickup lives in the last construction step rather
   than an early one. If `Touched` proves unreliable for an anchored non-colliding part, the fallback is
   the deleted `pickupTick`'s shape — a `task.wait(0.25)` sweep over at most seven items and eight
   players — restored under `Config.Items` with a scheduler waiver. **Do not guess: test it in Studio
   before building on it, and record the result in `artifacts/`.**

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 3 | A full-handed search destroys the item. With one buntot pagi per round, this silently deletes the second win condition and is reachable by honest play | 🔴 Critical | `spillItem` in `onItemFound` is the fix in Step 3.2; brief `exploit-auditor` on it by name |
| 4 | Pressing throw while holding the buntot pagi would spend the slot and destroy the win condition. The symptom is `MISS`, indistinguishable from an honest miss | 🔴 Critical | Guarded by the `ItemUse.verbFor` check in Step 4.2. The single highest-value line in the plan |
| 2 | Deleting `Config.Salt` while five modules still read it is a hard analyzer error, and the phases that fix those readers come later | 🟠 High | Plan assumes the table survives until Step 5.2. Record which ordering was taken in `implementation-log.md` |
| 3 | Two parallel salt economies exist today — `SaltSpawn` pouches AND container-seeded salt. Shipping both puts 8 pouches in a round where §4.6 says 4, breaking §6.5 invariant 1 with no Config change | 🟠 High | Step 3.1 deletes the pouch pool. `tests/config.test.luau:240` would not catch it — the invariant reads Config, not the world |
| 5 | The provider seam is a new cross-service pattern (Hard Rule 4) | 🟡 Medium | Justified in Step 5.1's Issues; alternatives named. For the auditor to evaluate |
| 4 | `Touched` on an anchored `CanCollide = false` part is unverified in this codebase | 🟡 Medium | Isolated in the last construction step. Fallback named in Follow Up 6. Test before building |
| 3 | `foundByPlayer` and `slot` become two server records of "what this player has" | 🟡 Medium | Follow Up 2. Recommend narrowing the comment |
| 5 | The Solo Trial's salt HUD loses its driver | 🟡 Medium | Follow Up 4. Playtester must open the trial |
| 1 | A migration that silently drops grid cells produces two green suites and looks identical to one that kept them | 🟡 Medium | Step 1.4 requires the before/after assertion counts in `implementation-log.md` |
| 4 | No drop sound, and no way to add one without a derived hint or an unauthorised noise cue | 🟢 Low | Deliberate. §4.4 names four noisy actions and dropping is not one |
| 2 | `Config.Items.GarlicSpawnCount` vs `Types.ItemType = "BAWANG"` | 🟢 Low | Follow Up 1. Not renamed in this chunk |

### The `exploit-auditor` brief this plan is written to leave clean

🔒 surface: `src/server/**`, `Remotes.luau`, `MonsterService`. Scope it to the files and questions
below rather than "audit the diff" — an unscoped brief costs three times as much and returns less.

> Audit **Phases 3 and 4** of `.claude/plans/feature-v08-three-items-plan/` — load with
> `npm run plan:phase -- feature-v08-three-items-plan 3` and `… 4`. Files: `ItemService.luau`,
> `MonsterService.luau` (`ApplySaltHit` only), `Remotes.luau`, `pure/ItemCarry.luau`,
> `pure/ItemThrow.luau`, `pure/ItemUse.luau`. Answer:
>
> 1. Can a client obtain, duplicate, or destroy the round's single buntot pagi by any path — the drop
>    handler, the `Touched` pickup, a full-handed search, or the throw key?
> 2. Does any branch in `ItemService` read the role? Expect exactly one `GetAswangUserId` hit, inside
>    `resolveThrow`, ANDed with `IsTransformed` into one boolean about a target.
> 3. Is a carried item observable by a second client through any channel — a tag, an attribute, a Tool,
>    a part name, a sound, a movement difference, or the absence of any of these?
> 4. Does `RequestDropItem` consume an AntiCheat token before doing any work, and does it return
>    anything to the caller on any path?
> 5. Is `ApplySaltHit` still the only entry point for a salt hit, with all six jobs intact and in order?
> 6. Any step in Phases 3 or 4 with no traceable `file:line`.
