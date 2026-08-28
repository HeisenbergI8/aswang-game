# Plan: V07 — Camouflage and Smoke

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V07 (`docs/BUILD-PLAN.md` — "Camouflage and smoke"; spec §4.3)
- **Description:** The Aswang gains two abilities behind one gate. Camouflage lets a **revealed**
  monster take the form of an ambient cat, dog, pig or villager by **swapping with** one that already
  exists — never by spawning a new one — spending a charge that only a completed feed restores. Smoke
  gives it one burst that genuinely breaks line of sight **on the server** so a salt hit is a setback
  rather than a death sentence.
- **Date:** 2026-08-28
- **What the client is told:** Nothing new about the role, the charge, or the reveal flag.
  `ClientRoundSnapshot` is **not widened** by this chunk. Two payloads cross:
  `CamouflageUpdate` (FireClient to the Aswang alone — a verdict and a form, no UserId, no charge
  count, no health) and `SmokeBurst` (FireClient to the players the **server** decides are within
  `Config.Monster.SmokeCueRadius` of the burst — a position and a duration, and **no player field of
  any kind**). There is no broadcast form of either. The public half of camouflage is that a player
  avatar is gone and an animal is standing there, which replicates as geometry and needs no remote.

---

### Preamble — the six facts every phase in this plan depends on

Read alongside Phase 1 via `npm run plan:phase -- <plan> 1 --with-preamble`. Each of these is repeated
inside the phase that needs it, because a phase is loaded on its own.

**1. The gate is not a balance dial.** Spec §4.3: camouflage is locked until the Aswang has taken a
salt hit. An unrevealed Aswang that camouflages removes a player avatar from a world where everyone can
count heads — four visible, one missing, in a five-player lobby. That performs the reveal for free, for
anyone willing to count, with nothing to argue about. **This plan makes the gate fail closed by
construction:** `HasBeenRevealed` starts false, exactly one line in the repo sets it true, and the pure
module denies every request whose `HasBeenRevealed` is false before it looks at anything else.

**2. `hasBeenRevealed` does not exist in `src/` today.** Zero hits. This plan introduces it **and its
single setter**, in `MonsterService.ApplySaltHit` — see §2 Phase 4 and Follow Ups Q1 for why V07 owns
the setter rather than deferring it to V08.

**3. There is no ambient life in `src/` today.** No `Ambient*` service, no cats, no dogs, no pigs, no
villager NPCs. The map is not in Git (the place file is gitignored — geometry, lighting and spawn
points live only in Studio), so **nothing in this plan may depend on a model a human placed.** Phase 3
builds a server-owned population with a map-authored spawn contract *and a code fallback*, so the
system is exercisable in `build/aswang.rbxl`, which contains code and an empty world.

**4. `MonsterService.FeedCompleted` is already the seam and it is already correct.** V06 shipped a
BindableEvent fired from `completeFeed` and from nowhere else, carrying the feeding `Player` and
nothing else, with no subscriber. Every interruption path goes through `endFeed`, which fires neither
`HealFromFeed` nor this event. **Nobody has to remember to withhold the camouflage refresh on a salt
hit, because there will be no code that could grant it.** V07 attaches exactly one listener.

**5. The transform's look machinery is what camouflage reuses.** `captureLook` / `restoreLook` /
`applyScale` / `trackedEffect` / `clearEffects` in `MonsterService` already capture a part's colour,
material and scale before changing it and restore what was captured. C04 shipped a revert that restored
**hardcoded defaults** instead — permanently branding the ex-Aswang, map-wide, with `verify` and
`check:secrecy` green over it. Camouflage is a second appearance change on the same character; it must
go through the same capture/restore path or it is that bug again.

**6. Smoke's line-of-sight break is a SERVER rule.** A particle cloud a client can delete is not a
mechanic. `MonsterService.hasLineOfSight` already raycasts for kills and `pure/SaltThrow.inCone`
already resolves throws server-side; V07 adds one pure predicate — does this segment pass through a
live smoke sphere — and consults it in both. The particles are presentation on top of a decision that
has already been made without them.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The gate, proven before anything can call it

#### Step 1.1: Create `CamouflageRules` with the four-input gate

**File:** `src/shared/pure/CamouflageRules.luau`
**Verify:** `test -f src/shared/pure/CamouflageRules.luau`

`evaluate(request) -> Verdict` over `(HasBeenRevealed, HasCharge, MonsterState, Phase)`, with the
reveal test first and unconditional.

**The module must not `require(script.Parent.X)`.** Lune has no `script`, and a pure module that reaches
for `Types` or `Enums` stops being runnable from a terminal — which is the whole point of `pure/`. The
unions are re-declared locally; Luau unions are structural, so these and the ones in `Types.luau` are
the same type and pass to each other without a cast (`FeedRules.luau:38-40` does exactly this).

```diff
+--!strict
+--[[
+	CamouflageRules — may this Aswang hide, right now? (V07, §4.3)
+
+		evaluate(request)      -> Verdict        may camouflage BEGIN
+		evaluateSmoke(request) -> SmokeVerdict   may a smoke burst be spent
+		revealedAfter(flag, event)  -> boolean   the reveal flag's ONLY transition table
+		chargeAfter(charge, event)  -> boolean   the charge's ONLY transition table
+		smokeBlocks(from, to, centre, radius) -> boolean   the pure half of "breaks line of sight"
+
+	THE FIRST TEST IS THE REVEAL AND IT IS UNCONDITIONAL. §4.3: "Camouflage is locked until the Aswang
+	has been publicly revealed — that is, until it has taken a salt hit. Before that, it cannot
+	camouflage at all." This module is the only place that sentence is written as code, and the
+	ordering is load-bearing rather than stylistic: with the reveal test first, there is no
+	combination of the other three inputs that can produce OK for an unrevealed monster, and
+	`tests/camouflage-rules.test.luau` asserts the entire `HasBeenRevealed = false` half of the grid
+	rather than a sample of it.
+
+	WHY THAT SENTENCE IS WORTH A MODULE. Camouflage removes a player avatar from the world. Fired
+	before a reveal, four players are visible and one is missing in a five-player lobby, and anyone
+	who counts knows who the Aswang is — permanently, with no transform witnessed, no risk taken and
+	nothing to argue about. The disguise would PERFORM the reveal rather than hide anything. No test
+	elsewhere in this repo would report it: the leak is a difference between players, not a piece of
+	data, and `check:secrecy` is a text tripwire that cannot see it (`.claude/lessons/absence-is-
+	observable.md`).
+
+	WHY `src/shared/pure/` IS SAFE FOR THIS, stated rather than assumed. `default.project.json` maps
+	`src/shared` wholesale into `ReplicatedStorage`, so any client can require AND RUN this module.
+	What it learns is the rule — which §4.3 states in public and one round of play demonstrates. What
+	it cannot obtain is an INPUT: `HasBeenRevealed` and `HasCharge` are fields on `MonsterService`'s
+	server-only `monsters` table, `MonsterState` is derived from that table by `monsterStateOf`, and
+	`Phase` is already public. There is no seed here and no draw, so there is no arrangement of this
+	module in which one player's answer is distinguishable from another's.
+
+	NO `script.Parent` REQUIRES — Lune has no `script`. The unions below are re-declared; Luau unions
+	are structural, so these and the matching ones in `Types` are the same types. The verdict is
+	returned as a SCALAR and never inside a list: `.claude/lessons/pure-module-unions-widen-in-
+	lists.md` is what that rule costs when it is broken.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
+export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
+
+--[[
+	`NOT_REVEALED` IS FIRST IN THE UNION AND FIRST IN THE FUNCTION, and it is the only verdict in this
+	game that is a DESIGN INVARIANT rather than a state report. Every other value here describes
+	something the monster could fix in the next ten seconds; this one describes a round in which it
+	has not yet been salted, and the answer does not change until a survivor lands a throw.
+]]
+export type Verdict =
+	"OK"
+	| "NOT_REVEALED" -- §4.3's gate. Nothing overrides it and nothing is checked before it
+	| "WRONG_PHASE" -- hiding is an ACTIVE-phase activity and nothing else
+	| "NO_CHARGE" -- spent on the last hide, and only a completed feed brings it back
+	| "ALREADY_CAMOUFLAGED" -- one form at a time
+	| "NOT_TRANSFORMED" -- the disguise is the monster's, and it steps out of monster form to wear it
+	| "NO_SLOT" -- no ambient entity of that form to swap with (V07, Phase 3)
+
+export type Request = {
+	--[[
+		THE GATE. False until this monster has taken a salt hit THIS ROUND, and false is the value a
+		freshly-created record carries — see `MonsterService.stateFor`. A caller that cannot answer
+		this question must pass false; there is no nil case and no default-true anywhere in the path.
+	]]
+	HasBeenRevealed: boolean,
+	-- Spent on entry, restored ONLY by a completed feed. See `chargeAfter` for the whole transition.
+	HasCharge: boolean,
+	MonsterState: MonsterState,
+	Phase: RoundPhase,
+	--[[
+		OPTIONAL, and nil is a real answer rather than a caller's mistake: `AmbientRoster.claim`
+		returns nil when every entity of that form is already claimed or the population failed to
+		spawn. Answered as NO_SLOT so that swap-not-spawn is enforced HERE rather than trusted at the
+		call site — §4.3 is explicit that the monster "must never SPAWN a new one: two pigs where
+		there was one is a head count with extra steps".
+	]]
+	SlotAvailable: boolean,
+}
+
+local CamouflageRules = {}
+
+--[[
+	MAY CAMOUFLAGE BEGIN? Called by `MonsterService`'s `RequestCamouflage` handler, on a request a
+	client sent about ITSELF.
+
+	THE ORDER IS THE CONTRACT, and it is not `FeedRules`'s order. `FeedRules` puts world facts first
+	so that a log full of OUT_OF_RANGE is a UX finding; this module puts THE GATE first, above even
+	the phase, because the gate is the one refusal whose precedence is a security property. Were
+	`WRONG_PHASE` checked first, an unrevealed Aswang firing this remote in INTERMISSION and again in
+	ACTIVE would receive two different refusals — and a client that can distinguish "wrong phase" from
+	"not revealed" has been handed a probe for whether it has been salted yet. It already knows that,
+	so the leak is small; the ORDERING RULE is what stops it growing when someone later adds an input
+	whose refusal is not already public.
+]]
+function CamouflageRules.evaluate(request: Request): Verdict
+	if not request.HasBeenRevealed then
+		return "NOT_REVEALED"
+	end
+
+	if request.Phase ~= "ACTIVE" then
+		return "WRONG_PHASE"
+	end
+
+	if request.MonsterState == "CAMOUFLAGED" then
+		return "ALREADY_CAMOUFLAGED"
+	end
+
+	--[[
+		AN ALLOWLIST OVER FIVE STATES, NEVER `~= "NORMAL"` — `FeedRules`'s rule, and it matters more
+		here. FEEDING is refused because §4.3 pins the monster to the body for the duration and a hide
+		mid-meal would be an escape from the one predictable window the buntot pagi needs. EXPOSED is
+		never produced by `monsterStateOf` (it is a LATCH that coexists with the form), and it is
+		answered anyway: a state with no stated answer is how these tables acquire bugs.
+	]]
+	if request.MonsterState ~= "TRANSFORMED" then
+		return "NOT_TRANSFORMED"
+	end
+
+	if not request.HasCharge then
+		return "NO_CHARGE"
+	end
+
+	-- LAST, because it is the only refusal that depends on what OTHER entities in the world are doing,
+	-- and a log full of NO_SLOT is a population finding rather than a rules one.
+	if not request.SlotAvailable then
+		return "NO_SLOT"
+	end
+
+	return "OK"
+end
+
+return CamouflageRules
```

#### Step 1.2: Add the reveal and charge transition functions

**File:** `src/shared/pure/CamouflageRules.luau`
**Verify:** `npm run analyze`

`revealedAfter(hasBeenRevealed, event)` and `chargeAfter(hasCharge, event)` over an explicit event
enum, so "only salt reveals" and "only a completed feed restores" become tested facts rather than
call-site discipline.

**This is the step that makes the gate provable rather than merely correct.** A boolean set by hand at
one call site is a convention; a transition table with a Lune grid behind it is a fact, and the shape
is `pure/MonsterHealth`'s `(health, event) -> health'`, which this repo already uses for exactly this
reason. Enumerating the events means a future chunk that adds a seventh event has to state its answer
here — and the test reds until it does.

```diff
 export type Request = {
 	HasBeenRevealed: boolean,
 	HasCharge: boolean,
 	MonsterState: MonsterState,
 	Phase: RoundPhase,
 	SlotAvailable: boolean,
 }
 
+--[[
+	EVERY EVENT IN THE ROUND THAT COULD PLAUSIBLY TOUCH EITHER BOOLEAN, enumerated so that the answer
+	for each is written down rather than implied by which call sites someone remembered to edit.
+
+	`pure/MonsterHealth` set this shape at V05 and the reason holds harder here: health is a number a
+	playtester notices when it is wrong, and these two are booleans nobody can see from inside the
+	game at all. The failure mode is not "camouflage misbehaves"; it is "camouflage was available one
+	round earlier than the design allows and the round looked normal".
+]]
+export type MonsterEvent =
+	"SALT_HIT" -- the ONLY event that reveals. §4.3, and V08 changes nothing about that
+	| "FEED_COMPLETED" -- the ONLY event that restores the charge. §4.3
+	| "FEED_INTERRUPTED" -- restores NOTHING. "Interrupting a feed is a real victory"
+	| "CAMOUFLAGE_ENTERED" -- spends the charge
+	| "CAMOUFLAGE_EXITED" -- does NOT return it. Once revealed, the monster must kill to hide
+	| "TRANSFORMED"
+	| "REVERTED"
+	| "KILLED" -- the kill, not the feed that follows it. A kill alone restores nothing
+
+--[[
+	THE REVEAL FLAG'S ONLY TRANSITION, AND IT IS ONE-WAY.
+
+	§4.3 and the build plan agree on the source: "`hasBeenRevealed` is the gate and it is set by the
+	first salt hit, never by anything else. 'Someone saw it transform' is not knowable server-side; a
+	salt hit is a fact the server already owns."
+
+	IT NEVER GOES BACK TO FALSE, and that is a decision rather than an omission. The Exposed window
+	expires after `Items.SaltRevealDuration`; this does not. Once the barrio has seen a glowing
+	monster, the information is out there and no timer takes it back — §4.3's "everyone already knows
+	who it is, so a head count tells them nothing new" is a statement about the ROUND, not about the
+	ten seconds. The reset is `onPhaseChanged`'s existing `table.clear(monsters)` on the way out of
+	ACTIVE, exactly as it is for `Health`, and it is the only one.
+
+	A `false` RETURN FOR AN UNKNOWN EVENT IS NOT AVAILABLE HERE — the function returns the CURRENT
+	value for everything that is not a salt hit, so an event nobody has thought of cannot un-reveal a
+	monster mid-round either. Fail closed in both directions.
+]]
+function CamouflageRules.revealedAfter(hasBeenRevealed: boolean, event: MonsterEvent): boolean
+	if event == "SALT_HIT" then
+		return true
+	end
+
+	return hasBeenRevealed
+end
+
+--[[
+	THE CHARGE'S ONLY TRANSITION. §4.3: "Camouflage is spent on use and only a feed restores it. Once
+	revealed, the Aswang must kill to hide."
+
+	THE PRESSURE LOOP IS THESE FOUR LINES. Spend on entry, restore on a COMPLETED feed, and nothing
+	else moves it — so a revealed monster that wants to hide again has to kill somebody and stand on
+	the body for five seconds in the open, which is §4.3's "being salted does not make the monster
+	cautious — it makes it desperate".
+
+	`FEED_INTERRUPTED` IS IN THE ENUM AND ANSWERS WITH THE CURRENT VALUE, deliberately. It is the
+	event a reader most expects to find handled, and leaving it to the fallthrough would make
+	"interrupting a feed costs the camouflage refresh" a property of an ABSENCE. `MonsterService`
+	already guarantees it structurally — `endFeed` fires neither `HealFromFeed` nor `FeedCompleted` —
+	and this line states the same thing where the grid can assert it.
+
+	`CAMOUFLAGE_EXITED` DOES NOT RESTORE IT. Stepping out of a cat is not a feed.
+]]
+function CamouflageRules.chargeAfter(hasCharge: boolean, event: MonsterEvent): boolean
+	if event == "FEED_COMPLETED" then
+		return true
+	end
+
+	if event == "CAMOUFLAGE_ENTERED" then
+		return false
+	end
+
+	return hasCharge
+end
+
 return CamouflageRules
```

#### Step 1.3: Add the smoke gate and the segment/sphere predicate

**File:** `src/shared/pure/CamouflageRules.luau`
**Verify:** `npm run lint`

`evaluateSmoke(request) -> SmokeVerdict` behind the same reveal flag, plus `smokeBlocks(from, to,
centre, radius)` — the pure half of "breaks line of sight".

**Smoke sits behind the reveal flag too, and that is a decision this plan is making.** Spec §4.3 frames
smoke entirely as the answer to a salt hit — "taking a salt hit forces a revert and leaves the Aswang
glowing… to stop that from being a death sentence, it has one smoke ability" — so the gate costs the
mechanic nothing: you are revealed exactly when you want it. What it buys is that an **unrevealed**
Aswang cannot plant a cloud on its own head in the middle of a group, which is a self-inflicted but
irreversible tell, and it means **both abilities in this chunk live behind one flag with one setter**.
Raised in Follow Ups Q4 as a balance question for V16, not settled forever.

```diff
+export type SmokeVerdict =
+	"OK"
+	| "SMOKE_NOT_REVEALED" -- the same gate, and a DISTINCT value from camouflage's on purpose
+	| "SMOKE_WRONG_PHASE"
+	| "SMOKE_COOLING" -- Config.Monster.SmokeCooldown has not elapsed since the last burst
+
+export type SmokeRequest = {
+	HasBeenRevealed: boolean,
+	Phase: RoundPhase,
+	-- os.clock() at the call site and at the last burst, or nil if there has not been one this round.
+	-- Taken as fields rather than read here so the test can hand this module a synthetic clock and
+	-- `check:config` has no literal to flag.
+	Now: number,
+	LastBurstAt: number?,
+	Cooldown: number,
+}
+
+--[[
+	MAY A SMOKE BURST BE SPENT? Same gate, same ordering rule, separate verdict union.
+
+	THE VERDICT VALUES ARE PREFIXED AND NOT SHARED WITH `Verdict`. Two unions that happen to contain
+	the same strings are one refactor away from being passed to each other's handler, and under
+	`--!strict` a shared union would typecheck that mistake. `Types.luau:521` already records this
+	repo hitting the bare-`WRONG_PHASE` collision once.
+
+	NO CHARGE FIELD, AND NO FEED DEPENDENCY. §4.3 ties the FEED to camouflage and says nothing of the
+	kind about smoke — "it has one smoke ability" names the ability, not a per-round use — so smoke is
+	a cooldown and camouflage is a charge. Wiring smoke to the feed as well would mean a salted Aswang
+	that has not killed recently cannot escape, which is the death sentence §4.3 built smoke to
+	prevent.
+]]
+function CamouflageRules.evaluateSmoke(request: SmokeRequest): SmokeVerdict
+	if not request.HasBeenRevealed then
+		return "SMOKE_NOT_REVEALED"
+	end
+
+	if request.Phase ~= "ACTIVE" then
+		return "SMOKE_WRONG_PHASE"
+	end
+
+	local lastBurstAt = request.LastBurstAt
+
+	if lastBurstAt == nil then
+		return "OK"
+	end
+
+	--[[
+		FAIL CLOSED ON EVERY DEGENERATE NUMBER, and test the values rather than trusting them —
+		`KillValidation.withinRange`'s idiom, and `FeedRules` copied it for the same reason. Written
+		`not (elapsed >= cooldown)` rather than `elapsed < cooldown` so a NaN elapsed (a clock that
+		went backwards, a nil-coalesced field) REFUSES instead of granting: NaN compares false to
+		everything, so the naive form lets it straight through.
+	]]
+	local elapsed = request.Now - lastBurstAt
+
+	if not (elapsed >= request.Cooldown) then
+		return "SMOKE_COOLING"
+	end
+
+	return "OK"
+end
+
+--[[
+	DOES A SMOKE CLOUD SIT ON THE LINE BETWEEN THESE TWO POINTS? (V07, §4.3)
+
+	THIS IS THE WHOLE OF "BREAKS LINE OF SIGHT" THAT IS ALLOWED TO BE A MECHANIC. The particles are
+	presentation: a client can delete an emitter, lower its graphics quality, or never receive the
+	burst at all, and none of that may change what the server permits. So the server asks this
+	function — a closest-approach test from a segment to a sphere centre — and refuses the kill or the
+	throw on its answer, exactly as `hasLineOfSight`'s raycast already refuses a kill through a wall.
+
+	PURE GEOMETRY OVER THREE NUMBERS PER POINT, not Vector3, because Lune has no Roblox datatypes and
+	the point of putting it here is that `tests/camouflage-rules.test.luau` can enumerate it.
+	`KillValidation.Vec3` is the same trick and `MonsterService.vec` is the adapter that already
+	exists for it.
+
+	THE DEGENERATE SEGMENT IS A REAL CASE: `from == to` happens when a monster is standing on its
+	victim. `length2 <= 0` falls through to the endpoint distance test, which is correct — a
+	zero-length segment is a point, and a point is inside the sphere or it is not.
+]]
+export type Vec3 = { X: number, Y: number, Z: number }
+
+function CamouflageRules.smokeBlocks(from: Vec3, to: Vec3, centre: Vec3, radius: number): boolean
+	if not (radius > 0 and radius < math.huge) then
+		return false
+	end
+
+	local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
+	local fx, fy, fz = centre.X - from.X, centre.Y - from.Y, centre.Z - from.Z
+	local length2 = dx * dx + dy * dy + dz * dz
+
+	-- How far along the segment the closest point to the centre lies, clamped to the segment itself.
+	-- Unclamped, a cloud BEHIND the shooter would block a shot away from it.
+	local t = if length2 > 0 then math.clamp((fx * dx + fy * dy + fz * dz) / length2, 0, 1) else 0
+	local cx, cy, cz = fx - dx * t, fy - dy * t, fz - dz * t
+	local closest2 = cx * cx + cy * cy + cz * cz
+
+	if closest2 ~= closest2 then
+		return false -- NaN anywhere upstream. Refusing to block is the safe direction: it fails
+		-- towards the survivors' counterplay, never towards the monster's escape.
+	end
+
+	return closest2 <= radius * radius
+end
```

#### Step 1.4: Write the exhaustive grid test

**File:** `tests/camouflage-rules.test.luau`
**Verify:** `lune run tests/camouflage-rules.test.luau`

2 × 2 × 5 × 5 over `evaluate`, with **the whole `HasBeenRevealed = false` half asserted as universally
denied**, plus the two transition grids, the smoke grid and the geometry cases.

The build plan's Verify line for V07 asks for exactly this: "exhaustive over the four-input grid, with
the pre-reveal row asserted as universally denied". `tests/feed-rules.test.luau` is the shape to copy —
an oracle written **from the spec sentence**, not from the module's own branch order, so that the test
proves agreement with §4.3 rather than agreement with itself.

```diff
+--!strict
+--[[
+	May the Aswang hide, over the whole domain. (V07, §4.3)
+
+	THE PRE-REVEAL HALF IS THE POINT OF THIS FILE. 2 x 2 x 5 x 5 x 2 is 200 cells and half of them
+	share one expected answer — `NOT_REVEALED`, unconditionally, for every phase, every state, every
+	charge and every slot. That half is not a sample and must never become one: the failure it exists
+	to catch is a future input added ABOVE the reveal test, which would look like a tidy refactor and
+	would silently hand the deduction layer away (see the module header, and `.claude/lessons/
+	absence-is-observable.md`).
+
+	THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCHES. `isOk` below is §4.3 written as one
+	conjunction. Computing the expectation from the module's own `if` order would prove only that the
+	module agrees with itself; PRECEDENCE — which refusal is reported when two apply — is a separate,
+	much smaller claim and it gets its own explicit table at the bottom.
+
+	SYNTHETIC NUMBERS, NOT CONFIG'S. These assertions are about the MODULE's rules; V16 retunes
+	balance and must not be able to red this file. The live Config values are cross-checked at the
+	bottom, as `monster-health` and `feed-rules` both do.
+]]
+
+local Config = require("../src/shared/Config")
+local CamouflageRules = require("../src/shared/pure/CamouflageRules")
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
+local REVEALED = { false, true }
+local CHARGED = { false, true }
+local SLOTS = { false, true }
+local STATES = { "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
+local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
+
+--[[
+	§4.3 AS ONE CONJUNCTION. "The Aswang can take the form of an ambient cat, dog, pig or villager
+	NPC… camouflage is locked until the Aswang has been publicly revealed… spent on use and only a
+	feed restores it", plus §6.4's rule that every round activity belongs to ACTIVE, plus the build
+	plan's swap-not-spawn rule as the slot term.
+]]
+local function isOk(
+	revealed: boolean,
+	charged: boolean,
+	state: string,
+	phase: string,
+	slot: boolean
+): boolean
+	return revealed and charged and slot and state == "TRANSFORMED" and phase == "ACTIVE"
+end
+
+for _, revealed in REVEALED do
+	for _, charged in CHARGED do
+		for _, state in STATES do
+			for _, phase in PHASES do
+				for _, slot in SLOTS do
+					local verdict = CamouflageRules.evaluate({
+						HasBeenRevealed = revealed,
+						HasCharge = charged,
+						MonsterState = state :: any,
+						Phase = phase :: any,
+						SlotAvailable = slot,
+					})
+
+					local label = `evaluate revealed={revealed} charge={charged} {state}/{phase} slot={slot}`
+
+					check(label, (verdict == "OK") == isOk(revealed, charged, state, phase, slot), verdict)
+
+					--[[
+						THE ASSERTION THE BUILD PLAN NAMES, AND IT IS SEPARATE FROM THE ONE ABOVE.
+						`(verdict == "OK") == isOk(...)` would already fail on a leaked grant — but it
+						would ALSO pass if an unrevealed monster were refused for the wrong reason,
+						which is the state a half-finished refactor leaves behind. Asserting the exact
+						verdict pins the ORDER as well as the outcome.
+					]]
+					if not revealed then
+						check(`pre-reveal denied: {label}`, verdict == "NOT_REVEALED", verdict)
+					end
+				end
+			end
+		end
+	end
+end
+
+-- THE TWO TRANSITION TABLES, over every event x every starting value. Eight events, two booleans,
+-- two functions: 32 cells, and every one of them has a stated answer in §4.3.
+local EVENTS = {
+	"SALT_HIT",
+	"FEED_COMPLETED",
+	"FEED_INTERRUPTED",
+	"CAMOUFLAGE_ENTERED",
+	"CAMOUFLAGE_EXITED",
+	"TRANSFORMED",
+	"REVERTED",
+	"KILLED",
+}
+
+for _, event in EVENTS do
+	for _, before in { false, true } do
+		local revealedAfter = CamouflageRules.revealedAfter(before, event :: any)
+		local expectedRevealed = before or event == "SALT_HIT"
+
+		check(`revealedAfter {before}/{event}`, revealedAfter == expectedRevealed, tostring(revealedAfter))
+
+		local chargeAfter = CamouflageRules.chargeAfter(before, event :: any)
+		local expectedCharge = if event == "FEED_COMPLETED"
+			then true
+			elseif event == "CAMOUFLAGE_ENTERED" then false
+			else before
+
+		check(`chargeAfter {before}/{event}`, chargeAfter == expectedCharge, tostring(chargeAfter))
+	end
+end
+
+-- THE ONE-WAY PROPERTY, STATED AS ITSELF rather than left to fall out of the grid: no event in the
+-- game un-reveals a monster mid-round. The reset is a new round, and a new round is a new record.
+for _, event in EVENTS do
+	check(`{event} never un-reveals`, CamouflageRules.revealedAfter(true, event :: any) == true)
+end
+
+-- AND THE CONFIG CROSS-CHECK. The grid above runs on synthetic values; this is the one place the live
+-- numbers are asserted to be usable at all, so a Config edit that zeroes the cooldown reds here.
+check("SmokeCooldown is a positive finite number", Config.Monster.SmokeCooldown > 0
+	and Config.Monster.SmokeCooldown < math.huge)
+check("SmokeRadius is a positive finite number", Config.Monster.SmokeRadius > 0
+	and Config.Monster.SmokeRadius < math.huge)
+
+print(`camouflage-rules: {checked - failures}/{checked} passed`)
+
+if failures > 0 then
+	error(`{failures} camouflage-rules assertions failed`)
+end
```

The smoke grid (`evaluateSmoke` over revealed × phase × three clock positions — never burst, exactly at
the cooldown, a hair inside it — plus `smokeBlocks` over the through-the-centre, tangent, past-the-end
and behind-the-shooter cases) goes in the same file, in the same shape. **`smokeBlocks` must assert the
clamp case explicitly:** a cloud behind the thrower is the one geometry bug that reads as balance.

#### Step 1.5: Fold the new suite into the unit run

**File:** `tests/camouflage-rules.test.luau`
**Verify:** `npm run test:unit`

`npm run test:unit` runs every `tests/*.test.luau` under Lune, so a file dropped in the directory needs
no registration — confirm the whole suite is still green rather than only the new one. This step exists
because a new pure module can red an OLD suite: `FeedRules` and this module both answer for
`CAMOUFLAGED`, and `tests/feed-rules.test.luau` already asserts that a camouflaged monster may not
feed. If that assertion has moved, this is where it shows.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing in this phase touches an Instance, so there is no attribute and no tag
  to replicate. The real question is the one the module header answers: `src/shared/pure/` is
  requirable AND CALLABLE by any client, so confirm no INPUT to these functions is client-suppliable.
  All four come from `MonsterService`'s server-only `monsters` table or from `RoundService.GetPhase()`.
- **Remote direction** — none added this phase.
- **Rate limiting** — no `OnServerEvent` handler added this phase.
- **Magic numbers** — `Cooldown` and `radius` are taken as FIELDS, never read from `Config` inside the
  module. That is what keeps the test able to hand it synthetic values, and it is why `check:config`
  has nothing to flag here.
- **Phase ownership** — the module compares against `Phase`; it never sets one.
- **Player leaving mid-round** — not reachable from a pure module; Phase 4 owns it.
- **Strict Luau** — the three unions are re-declared locally rather than imported, and the test casts
  its loop variables with `:: any` at the call boundary. Without that, `state` infers as plain `string`
  and fails to satisfy the literal union — six of the scaffold's seven original analyze errors were
  exactly this.
- **Mobile budget** — nothing rendered this phase.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **`--!strict` and the `if/elseif/else` expression in the test.** `expectedCharge` uses an
  if-expression across three branches; confirm StyLua's 100-column formatting of it matches
  `stylua.toml` before assuming a red `fmt:check` is a real problem.
- **The `smokeBlocks` NaN guard is asserted, not assumed.** `closest2 ~= closest2` is the NaN test and
  it must stay above the comparison. Written the other way round, a NaN sails through
  `closest2 <= radius^2` as false, which returns "does not block" — which happens to be the safe
  direction, so the bug would never surface. Test it anyway; the next person to edit this may reverse
  the polarity.

---

### Phase 2: Tunables, types and the declared network surface

#### Step 2.1: Add the camouflage and smoke tunables to `Config.Monster`

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

`SmokeDuration = 4` and `SmokeRadius = 18` **already exist** at `Config.luau:346-347`, under a header
explaining why they sit under `Monster` rather than `Items`. Do not re-add them and do not move them.
Four numbers are new.

```diff
 		SmokeDuration = 4,
 		SmokeRadius = 18,
 
+		--[[
+			CAMOUFLAGE (V07, §4.3) — AND THE GATE IS NOT IN THIS BLOCK, DELIBERATELY.
+
+			§4.3's rule — "camouflage is locked until the Aswang has been publicly revealed" — has no
+			number and must never acquire one. A `CamouflageRequiresReveal = true` here would be a
+			one-character edit away from deleting the deduction layer, on a line a tuner would read as
+			a balance knob during V16. The gate lives in `pure/CamouflageRules.evaluate`, where it is
+			the first branch and where 100 grid cells assert it.
+
+			WHAT IS TUNABLE IS THE COST. One charge, spent on entry, restored only by a completed feed
+			(§4.3: "once revealed, the Aswang must kill to hide"). The count is here because V16 may
+			well find that one is too punishing — but the RESTORE PATH is not a number and does not
+			appear here either.
+		]]
+		CamouflageCharges = 1,
+		-- The windup, mirroring `TransformTime`. A hide that is instant is a hide with no counterplay:
+		-- §4.3's whole design is that risky acts are VISIBLE while they happen. Shorter than
+		-- TransformTime (1.2) because the monster is already in monster form and already revealed —
+		-- there is nothing left to hide by being slow about it.
+		CamouflageEnterTime = 0.8,
+		-- How far a survivor must be from the Aswang for it to begin hiding. Watching a player become
+		-- a pig from four studs away is not a disguise; it is a magic trick with a witness. Compare
+		-- `KillRange = 8`: the monster must be further from everyone than it could kill them from.
+		CamouflageWitnessRadius = 12,
+
+		--[[
+			SMOKE'S TWO NEW NUMBERS (V07, §4.3). The other two are above.
+
+			A COOLDOWN RATHER THAN A CHARGE, and the spec sentence is the reason: "it has one smoke
+			ability" names the ability, not a per-round use. Wiring smoke to the feed the way
+			camouflage is wired would mean a salted Aswang that has not killed recently cannot escape
+			— the death sentence §4.3 built smoke to prevent.
+
+			SmokeCueRadius IS A NETWORK NUMBER, NOT A GAMEPLAY ONE, and it is the larger of the two on
+			purpose. `SmokeBurst` is sent only to players within this radius (V07 Phase 5) — never
+			FireAllClients, for `NoiseCue`'s reason: a broadcast carrying a position is a live index of
+			where the monster is, readable by any client, and strictly more than V13's tracker will
+			ever give the survivors. Bigger than SmokeRadius so that a player at the cloud's edge sees
+			it form rather than having it appear on top of them.
+		]]
+		SmokeCooldown = 45,
+		SmokeCueRadius = 40,
```

#### Step 2.2: Add the `Config.Ambient` population block

**File:** `src/shared/Config.luau`
**Verify:** `npm run fmt:check`

A new top-level block beside `Search`, `Items` and `Bodies`. **The count is the mechanic** — §5: "3–4
each of cats, dogs, pigs and villager NPCs, wandering. If there is one pig in the barrio, the disguise
is meaningless."

```diff
+	--[[
+		AMBIENT LIFE (V07, §5) — AND THE COUNT IS THE MECHANIC, NOT THE FLAVOUR.
+
+		§5: "3-4 each of cats, dogs, pigs and villager NPCs, wandering. If there is one pig in the
+		barrio, the disguise is meaningless. They need no AI worth the name — a wander loop and an
+		idle is enough. What matters is the *count*."
+
+		SO PerForm IS A BALANCE NUMBER WITH A SECRECY FLOOR UNDER IT, and `tests/config.test.luau`
+		pins it: below 2, a camouflaged Aswang is the ONLY entity of its form once the real one has
+		wandered off, and §4.5's "It's the cat!" stops being a guess. It is the same class of silent
+		invariant as `SaltDamage x (SaltSpawnCount - 1)` — nothing in the game tells you when it has
+		been tuned away.
+
+		THE CEILING IS §5'S MOBILE BUDGET. Four forms at four each is 16 wandering models; whoever
+		builds their appearance counts them against the part and light caps `PerformanceController`
+		already enforces, and V07's are parts with no lights and no particles.
+	]]
+	Ambient = {
+		PerForm = 4,
+		--[[
+			HOW FAR AN ENTITY WANDERS FROM THE POINT IT SPAWNED AT, and it is deliberately small.
+
+			A population that roams the whole barrio ends up clustered by chance, which defeats the
+			count: four pigs in the plaza and none anywhere else means the pig standing alone by the
+			chapel is the monster. Leashing each entity near its own spawn keeps the DISTRIBUTION as
+			stable as the count.
+		]]
+		WanderRadius = 24,
+		WanderSpeed = 4,
+		-- Seconds between retargets, and the pause an entity takes on arrival. §5's "a wander loop and
+		-- an idle is enough", in two numbers.
+		WanderInterval = 6,
+		IdleSeconds = 3,
+		--[[
+			THE FALLBACK SCATTER, used ONLY when the map provides no `AmbientSpawn`-tagged points.
+
+			The place file is gitignored, so `npm run build` produces code and an empty world — and a
+			population that exists only where a human placed markers cannot be exercised there at all.
+			These two numbers make the system self-starting: a ring around the origin, at a radius
+			wide enough that the entities are not stacked. It is scaffolding for the harness, not a
+			design; the map contract in `AmbientService`'s header is the real answer.
+		]]
+		FallbackScatterRadius = 60,
+		FallbackHeight = 3,
+	},
```

#### Step 2.3: Declare `RequestCamouflage`, `RequestSmoke`, `CamouflageUpdate`, `SmokeBurst`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

Declared here, fired by nobody until Phase 5. Direction lists matter: two up, two down. Declaring early
is deliberate — the server creates every remote eagerly at boot, and a client `WaitForChild` on a name
the server never created **hangs forever**, with no error, no output and no stack trace.

```diff
 	"FeedUpdate",
+	--[[
+		V07, §4.3. FireClient to the ONE player whose disguise it is. Never FireAllClients — there is
+		no broadcast form of this payload and adding one would be a redesign, not an optimisation.
+
+		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The
+		public half of camouflage needs no remote at all — a player avatar is gone and a pig is
+		standing where it was, and both of those replicate as geometry. That is the whole of what the
+		barrio is told, and §4.3 is content with it: the monster is already revealed by the time it
+		can do this, so there is no secret left for the geometry to give away.
+
+		THE PAYLOAD CARRIES NO CHARGE COUNT. `Types.CamouflageUpdatePayload` is a verdict and an
+		optional form. The charge is a boolean on the server-only `monsters` table and it has no
+		field, no attribute and no tag anywhere — a client that knew its own charge could not leak it
+		(it is the Aswang's own business), but the field would be the obvious place for a later
+		broadcast to grow one, and there is no reason to build the socket.
+
+		AND NO REVEAL FLAG. `HasBeenRevealed` never crosses in any form. A `NOT_REVEALED` verdict does
+		reach the requester, and that is safe on `RoleAssigned`'s reasoning: it is fired to a single
+		player, about that player, telling them a fact they already have — they know whether they have
+		been salted, because they were standing inside the glow.
+	]]
+	"CamouflageUpdate",
+	--[[
+		V07, §4.3. FireClient to every player the SERVER decides is within `Config.Monster
+		.SmokeCueRadius` of the burst — NEVER FireAllClients. `Types.SmokeBurstPayload` is the payload.
+
+		THE BROADCAST FORM IS THE WHOLE RISK AND IT IS REFUSED, for `NoiseCue`'s reason exactly. A
+		FireAllClients carrying a position hands every client the monster's live location the instant
+		it tries to escape — readable from a compromised client with no exploit beyond listening, and
+		strictly more than V13's 90s-to-30s tracker will ever give the survivors. The distance test
+		happens on the server and a player out of radius receives NOTHING.
+
+		THE POSITION IS EXACT RATHER THAN QUANTISED, AND THAT IS A DELIBERATE DIFFERENCE FROM
+		`NoiseCue`. Noise is heard at 60 studs — far beyond what a listener can see — so its position
+		is quantised to a grid because the payload would otherwise state more than the world does.
+		Smoke's send radius is 40 and the cloud itself is 18: everyone who receives this is close
+		enough to WATCH the cloud form, so an exact centre states nothing they will not see rendered a
+		frame later. If `SmokeCueRadius` is ever raised well past visual range, this reasoning expires
+		and the position must be quantised — that dependency is stated in Config beside the number.
+
+		THE PAYLOAD HAS NO PLAYER FIELD OF ANY KIND. No UserId, no Character, no name. A cloud is a
+		fact about a place; "the Aswang is inside it" is an inference a client is welcome to make from
+		looking, and the server never states it. This matters more than it looks: smoke is fired only
+		by the Aswang, so a UserId here would be a role broadcast with a position attached — the
+		single worst payload in the game — and `check:secrecy` matches `killer\w*` and the enumerated
+		role tokens, not a field called `Source`.
+	]]
+	"SmokeBurst",
 }
```

```diff
 	"RequestCancelSearch",
+	--[[
+		V07, §4.3. NO ARGUMENTS, and the absent argument is the security design.
+
+		THE FORM IS NOT NAMED BY THE CLIENT. The server picks it from whatever `AmbientRoster.claim`
+		can actually supply, from the population it owns — the rule `SearchService` already applies to
+		containers: "the server resolves what a player is standing at from that player's own character
+		position, and the client names nothing."
+
+		A `RequestCamouflage(form)` would have been strictly worse in the way that matters. It needs a
+		verdict for "there is no cat left", which is the roster query the server was already going to
+		make; and it hands a compromised client a PROBE — ask for each of the four forms in turn, read
+		the verdicts, and learn the live ambient population without walking anywhere. That is a map of
+		which corners of the barrio have been depopulated, which is exactly the information a hunting
+		survivor pays attention for.
+	]]
+	"RequestCamouflage",
+	--[[
+		V07, §4.3. Also argument-free. The burst happens at the requester's OWN character position,
+		which the server reads; a position argument would be a "put a cloud anywhere" primitive, and
+		the first thing to do with it is drop one on a survivor's face across the map.
+
+		THERE IS NO `RequestExitCamouflage`, AND THAT IS THE THIRD REMOTE THIS CHUNK DID NOT ADD.
+		Stepping out of the disguise is `RequestTransform`, which already exists, is already budgeted
+		and already means "become the monster" — a camouflaged Aswang firing it exits the form and
+		transforms, which is the only reason it would ever want out. A dedicated exit remote would be
+		a second entry point into the same state change, and `RequestSearch`/`RequestCancelSearch`'s
+		header is right that two messages for one state are how a client and a server come to
+		disagree about it.
+	]]
+	"RequestSmoke",
 }
```

#### Step 2.4: Budget the two new up-remotes and sync the budgets test's hand copy

**File:** `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

**Both edits or neither.** That suite asserts in two directions — every up-remote has a budget, and
every budget names a real remote — against a **hand copy** of `EVENTS_UP` that lives in the test,
because `Remotes.luau` calls `game:GetService` at module scope and Lune cannot require it. Adding a
budget without the hand copy reds `EXTRA_BUDGETS`; adding the hand copy without the budget reds the
other direction. Note also that `Consume` **fails closed** — `AllowUnbudgetedRemote = false` — so a
missing budget disables the ability entirely rather than leaving it unlimited.

```diff
 	"RequestSearch",
 	"RequestCancelSearch",
+	-- V07. Both argument-free: the server picks the form from the population it owns, and the burst
+	-- happens at the requester's own character position. `RequestCamouflage` is the tighter of the
+	-- two — see Config for why a refused hide is cheap and a hide firehose is not.
+	"RequestCamouflage",
+	"RequestSmoke",
 }
```

```diff
 			RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
+			--[[
+				V07, §4.3. A DELIBERATE, RARE ACT, priced like `RequestTransform` above it rather than
+				like a search: the charge is the real limiter — one hide per completed feed — and this
+				budget exists for the refusals, which are the only thing a client can fire freely.
+
+				AND THE REFUSALS ARE THE INTERESTING HALF. An unrevealed Aswang gets `NOT_REVEALED`
+				every time, forever, for free; a capacity of 3 at 0.2/s means it can ask about 12
+				times a minute. That is not a leak — it is telling a player a fact about themselves
+				they already have — but it is the shape that WOULD be one if a later verdict ever
+				depended on another player, so the budget is sized as though it did.
+			]]
+			RequestCamouflage = { Capacity = 3, RefillPerSecond = 0.2 },
+			--[[
+				V07. Tighter still, because this handler is the only one in the chunk that FIRES A
+				REMOTE TO OTHER PLAYERS: a granted burst sends `SmokeBurst` to everyone within
+				`SmokeCueRadius`. `Config.Monster.SmokeCooldown = 45` already means an honest client
+				fires this at most once every 45 seconds, so capacity 2 covers a double-tap and a
+				reconnect retry and nothing else.
+			]]
+			RequestSmoke = { Capacity = 2, RefillPerSecond = 0.1 },
```

#### Step 2.5: Add the payload types and widen the server-only monster record

**File:** `src/shared/Types.luau`
**Verify:** `npm run verify:fast`

`Types.MonsterState` already declares `CAMOUFLAGED` and `Types.CamouflageForm` already declares the
four forms (`Types.luau:39,61`), both added at V02 with no producer. **This chunk is the one Enums.luau
named** — "whether this is one field or a field plus a flag is that chunk's decision" — and the answer
is: **a field plus two flags**, matching what V06 did for `Feeding`.

**`ClientRoundSnapshot` is not touched.** If a later chunk needs to widen it for camouflage, that is a
decision for Follow Ups, not a field slipped in here.

```diff
+--[[
+	V07, §4.3. What the Aswang's own client is told about its disguise, and nothing else is.
+
+	NO CHARGE COUNT AND NO REVEAL FLAG — see `Remotes.luau`'s `CamouflageUpdate` entry for the full
+	argument. A verdict and an optional form, fired to one player about themselves.
+
+	`Form` IS OPTIONAL BECAUSE A REFUSAL HAS NONE. It is populated on OK and on the exit message, so
+	the client can say "You are a pig" and later "You are yourself"; every other verdict carries nil.
+]]
+export type CamouflageUpdatePayload = {
+	Verdict: CamouflageVerdict,
+	Form: CamouflageForm?,
+}
+
+-- The verdict union, mirrored from `pure/CamouflageRules` plus the two the SERVER owns rather than
+-- the rules module: `CAMO_EXITED` (a state change, never a refusal) and `CAMO_WITNESSED` (a survivor
+-- inside `CamouflageWitnessRadius`, which is a distance the pure module never sees).
+export type CamouflageVerdict =
+	"CAMO_OK"
+	| "CAMO_EXITED"
+	| "CAMO_NOT_REVEALED"
+	| "CAMO_WRONG_PHASE"
+	| "CAMO_NO_CHARGE"
+	| "CAMO_ALREADY"
+	| "CAMO_NOT_TRANSFORMED"
+	| "CAMO_NO_SLOT"
+	| "CAMO_WITNESSED"
+
+--[[
+	V07, §4.3. A cloud, at a place, for a while — and the ABSENT FIELDS are the design.
+
+	No UserId, no Character, no name, no role. Smoke is fired only by the Aswang, so a player field
+	here would be a role broadcast with a position attached. See `Remotes.luau`'s `SmokeBurst` entry
+	for why the position itself is safe: everyone who receives this payload is inside
+	`Config.Monster.SmokeCueRadius` and can watch the cloud form.
+
+	`Duration` AND `Radius` ARE SENT RATHER THAN READ FROM CONFIG BY THE CLIENT, even though Config
+	replicates. The server is the authority on how long ITS burst lasts, and a client that computed
+	the lifetime from Config would draw a stale cloud for four seconds after a Config change that the
+	server had already applied. One fewer place where the two can disagree.
+]]
+export type SmokeBurstPayload = {
+	Position: Vector3,
+	Duration: number,
+	Radius: number,
+}
```

#### Step 2.6: Pin the new balance relationships

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

Spec §6.5 lists six invariants and says why they are pinned as **relationships** rather than values:
they are silent, and no symptom tells you when two numbers that must agree have stopped agreeing. V07
adds three of the same kind.

```diff
+--[[
+	V07, §4.3/§5. THE DISGUISE NEEDS A CROWD TO HIDE IN.
+
+	`Ambient.PerForm` must be at least 2. At 1, the moment the Aswang claims the only cat, there is
+	exactly one cat in the barrio and it is the monster — §4.5's "It's the cat!" stops being a guess
+	and becomes a lookup. This is the camouflage system's equivalent of invariant 1: tune the number
+	and a win condition changes with nothing in the game to report it. §5 asks for 3-4; the floor
+	pinned here is the point below which the mechanic is not merely weak but INVERTED.
+]]
+check("Ambient.PerForm >= 2 — a lone entity of a form IS the monster", Config.Ambient.PerForm >= 2)
+
+--[[
+	V07, §4.3. THE HIDE MUST NOT BE FASTER THAN THE WITNESS RADIUS IS WIDE.
+
+	`CamouflageWitnessRadius` must exceed `Monster.KillRange`. A monster that may hide from further
+	away than it may kill from still has to break contact first; the other way round, it can kill a
+	survivor and hide before the survivor's partner — standing at kill range, watching — has anything
+	to report. The corpse-as-bait window §4.3 built the feed for depends on the killer being findable.
+]]
+check(
+	"CamouflageWitnessRadius > KillRange",
+	Config.Monster.CamouflageWitnessRadius > Config.Monster.KillRange
+)
+
+--[[
+	V07, §4.3. THE ESCAPE MUST OUTLAST THE REVEAL IT IS ESCAPING FROM — or rather, must not.
+
+	`SmokeDuration` must be SHORTER than `Items.SaltRevealDuration`. Smoke exists so a salted Aswang
+	can disengage, not so it can wait out the glow inside a cloud: if the smoke outlasts the reveal,
+	the survivors' counterplay is spent and they never see the thing they paid an item to expose.
+	Compare §6.5 invariant 6, which pins the reveal above the stun for the mirror-image reason.
+]]
+check(
+	"SmokeDuration < SaltRevealDuration — smoke covers a retreat, it does not erase the reveal",
+	Config.Monster.SmokeDuration < Config.Items.SaltRevealDuration
+)
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the two new payload types are the surface. Confirm `CamouflageUpdatePayload`
  has no charge field and no UserId, and that `SmokeBurstPayload` has no player field of any kind. Both
  are FireClient-only by declaration; a `FireAllClients` on either lands in Phase 5's issues.
- **Remote direction** — `CamouflageUpdate` and `SmokeBurst` in `EVENTS_DOWN`; `RequestCamouflage` and
  `RequestSmoke` in `EVENTS_UP`. Getting this backwards is silent on the server and hangs the client.
- **Rate limiting** — the budgets land here, the handlers land in Phase 5. Between the two, the remotes
  exist and nothing listens, which is the state `SearchService.ItemFound` and `FeedCompleted` both
  shipped in.
- **Magic numbers** — every number in this phase is IN `Config.luau`, which is the point of the phase.
  The test file's synthetic values are outside `src/` and `check:config` does not scan them.
- **Phase ownership** — nothing here reads or sets a phase.
- **Player leaving mid-round** — not reachable this phase.
- **Strict Luau** — `CamouflageVerdict` must be declared BEFORE `CamouflageUpdatePayload` references
  it, and the `Form: CamouflageForm?` field needs the existing `CamouflageForm` union at `Types.luau:61`
  rather than a second copy.
- **Mobile budget** — `Ambient.PerForm = 4` across four forms is 16 wandering models. Counted properly
  in Phase 3, where they acquire parts.
- **Scope** — nothing from §3's OUT list. `Ambient` is §5 map population, not a second monster.

**Issues identified:**

- **`Config.Ambient` is a new top-level block and `check:config` may not know it.** The check scans
  `src/` for numeric literals outside `Config.luau`; a new block inside the file is not the risky
  direction. Confirm nonetheless that `tests/config.test.luau`'s own structural walk (if it has one)
  does not enumerate top-level keys against a fixed list.
- **The three new invariants are asserted against numbers that do not exist until Step 2.1 and 2.2
  land.** Ordering within the phase matters: 2.6 reds until both Config steps are in.

---

### Phase 3: The ambient population, and the slot that gets swapped

#### Step 3.1: Create the pure roster module

**File:** `src/shared/pure/AmbientRoster.luau`
**Verify:** `test -f src/shared/pure/AmbientRoster.luau`

`claim(roster, form) -> (roster', slotIndex?)` and `release(roster, slotIndex)`, over plain tables.
The property it exists to make testable is **visible head count is invariant across a claim**.

This is the answer to `exploit-auditor`'s second V07 question — "does the ambient population count
change when it fires" — turned from a thing someone reads the code to check into a thing a grid asserts.
§4.3: "The Aswang swaps with an existing ambient entity — the real one wanders off, the monster takes
its slot. It must never *spawn* a new one: two pigs where there was one is a head count with extra
steps."

```diff
+--!strict
+--[[
+	AmbientRoster — who is standing in the barrio, and which slot the monster took. (V07, §4.3/§5)
+
+		claim(roster, form)   -> (roster, slotIndex?)   swap the monster into an existing slot
+		release(roster, slot) -> roster                 give it back
+		visibleCount(roster, form) -> number            what a survivor counting heads would see
+
+	THE ONE PROPERTY THIS MODULE EXISTS TO MAKE TESTABLE: `visibleCount` is INVARIANT across a claim.
+	One entity stops being real and one starts being the monster; the number of things standing in the
+	barrio does not move. That is §4.3's swap-not-spawn rule expressed as arithmetic, and it is the
+	only form of it a Lune test can check — `AmbientService` owns the Instances, and Lune has no
+	DataModel.
+
+	WHY THAT IS WORTH A MODULE RATHER THAN A COMMENT. The failure is silent and permanent. Spawn
+	instead of swap and there are five pigs where §5 promised four — nobody counts pigs, so nobody
+	notices, and the disguise degrades a little every time it is used until a survivor who DOES count
+	has a free monster detector. No error, no log line, and no screenshot shows it.
+
+	A SLOT IS AN INDEX, NEVER AN INSTANCE. This module holds no Model, no Player and no position:
+	`AmbientService` maps the index back to the entity it spawned. Keeping Instances out is what lets
+	the test run at all, and it is also why nothing in here could leak — there is no UserId in the
+	type, so there is no arrangement of it in which one player's answer differs from another's.
+
+	NO `script.Parent` REQUIRES — Lune has no `script`. `CamouflageForm` is re-declared; Luau unions
+	are structural.
+]]
+
+export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
+
+-- One ambient entity. `Claimed` means the monster is wearing this slot; the real entity has wandered
+-- off and `AmbientService` has parked its Model out of the world until the slot is released.
+export type Slot = {
+	Form: CamouflageForm,
+	Claimed: boolean,
+}
+
+export type Roster = { Slot }
+
+local AmbientRoster = {}
+
+--[[
+	WHAT A SURVIVOR COUNTING HEADS WOULD SEE. Every slot of that form, claimed or not — because a
+	claimed slot has the monster standing in it, wearing the form, and it looks exactly like the
+	entity it replaced.
+
+	THE FUNCTION IS TRIVIAL AND THE TEST OVER IT IS NOT. It is here so `visibleCount(claim(r)) ==
+	visibleCount(r)` is a statement that can be written down and asserted over the whole roster space,
+	rather than a property a reader has to reconstruct from `AmbientService`'s parenting.
+]]
+function AmbientRoster.visibleCount(roster: Roster, form: CamouflageForm): number
+	local count = 0
+
+	for _, slot in roster do
+		if slot.Form == form then
+			count += 1
+		end
+	end
+
+	return count
+end
+
+--[[
+	TAKE A SLOT OF THIS FORM, IF THERE IS ONE.
+
+	RETURNS nil RATHER THAN CREATING ONE, and that refusal is the whole security of the mechanic.
+	`CamouflageRules.evaluate` answers NO_SLOT on it and the hide does not happen. A version of this
+	function that appended a slot when none was free would satisfy every test about camouflage
+	working and would break the only rule §4.3 wrote in bold.
+
+	MUTATES A COPY, NOT THE ARGUMENT. `AmbientService` holds the authoritative roster and assigns the
+	returned one; a pure function that edited its input in place would be indistinguishable from a
+	correct one until two callers shared a roster, which is exactly what a rejoin does.
+
+	FIRST FREE SLOT, NOT A RANDOM ONE. A random pick would need a seed, and a seeded draw in a
+	replicated module is the one shape `CLAUDE.md` names as fatal: `Random.new(roundNumber)` lets a
+	client replay the draw. There is nothing to hide here — which slot is claimed is not a secret —
+	but the rule is worth not bending, and `AmbientService` scatters the spawn points anyway.
+]]
+function AmbientRoster.claim(roster: Roster, form: CamouflageForm): (Roster, number?)
+	local updated: Roster = table.clone(roster)
+
+	for index, slot in updated do
+		if slot.Form == form and not slot.Claimed then
+			updated[index] = { Form = slot.Form, Claimed = true }
+
+			return updated, index
+		end
+	end
+
+	return updated, nil
+end
+
+--[[
+	GIVE IT BACK. IDEMPOTENT, and that is a requirement rather than a nicety: Phase 4 releases from
+	five different exits (an exit request, a transform, a salt hit, a death, the round ending) and at
+	least two of them can fire for the same slot in the same frame — `ApplySaltHit` calls `endFeed`,
+	which calls `revert`, which exits camouflage, on a path `onPhaseChanged` may also be walking.
+
+	AN OUT-OF-RANGE INDEX IS ANSWERED, NOT ERRORED. A stale slot index outliving its roster is what a
+	player rejoining into a new round looks like, and throwing inside a `PlayerRemoving` handler is how
+	one cleanup failure becomes several.
+]]
+function AmbientRoster.release(roster: Roster, slotIndex: number?): Roster
+	local updated: Roster = table.clone(roster)
+
+	if slotIndex == nil then
+		return updated
+	end
+
+	local slot = updated[slotIndex]
+
+	if slot == nil then
+		return updated
+	end
+
+	updated[slotIndex] = { Form = slot.Form, Claimed = false }
+
+	return updated
+end
+
+return AmbientRoster
```

#### Step 3.2: Test head-count invariance across every claim and release

**File:** `tests/ambient-roster.test.luau`
**Verify:** `lune run tests/ambient-roster.test.luau`

```diff
+--!strict
+--[[
+	The barrio's head count does not move when the monster hides. (V07, §4.3/§5)
+
+	ONE PROPERTY, ASSERTED OVER THE WHOLE ROSTER SPACE. `visibleCount(claim(r, form), form) ==
+	visibleCount(r, form)`, for every form, at every occupancy from empty to fully claimed. §4.3: "it
+	must never SPAWN a new one: two pigs where there was one is a head count with extra steps."
+
+	THE EXHAUSTION CASE IS THE ONE THAT MATTERS MOST and it is the last row of every loop: claim every
+	slot of a form, then claim once more. The correct answer is nil, and the tempting wrong answer —
+	appending a slot so the hide always works — passes every test about camouflage functioning.
+]]
+
+local Config = require("../src/shared/Config")
+local AmbientRoster = require("../src/shared/pure/AmbientRoster")
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
+local FORMS = { "CAT", "DOG", "PIG", "VILLAGER" }
+-- SYNTHETIC, not Config's — V16 retunes `Ambient.PerForm` and must not be able to red this file. The
+-- live value is cross-checked at the bottom, as `feed-rules` and `monster-health` both do.
+local PER_FORM = 3
+
+local function build(): AmbientRoster.Roster
+	local roster: AmbientRoster.Roster = {}
+
+	for _, form in FORMS do
+		for _ = 1, PER_FORM do
+			table.insert(roster, { Form = form :: any, Claimed = false })
+		end
+	end
+
+	return roster
+end
+
+for _, form in FORMS do
+	local roster = build()
+	local before = AmbientRoster.visibleCount(roster, form :: any)
+
+	-- Claim every slot of this form in turn. The count must never move, and every claim must succeed
+	-- until the form is exhausted.
+	for attempt = 1, PER_FORM do
+		local claimed, slotIndex = AmbientRoster.claim(roster, form :: any)
+
+		check(`claim {attempt} of {form} succeeds`, slotIndex ~= nil, tostring(slotIndex))
+		check(
+			`head count invariant after claim {attempt} of {form}`,
+			AmbientRoster.visibleCount(claimed, form :: any) == before,
+			`{AmbientRoster.visibleCount(claimed, form :: any)} vs {before}`
+		)
+
+		-- AND NO OTHER FORM MOVED. A claim that reached across forms would let one hide depopulate
+		-- the pigs while the monster became a cat, which is the same leak by a longer route.
+		for _, other in FORMS do
+			if other ~= form then
+				check(
+					`claiming {form} does not touch {other}`,
+					AmbientRoster.visibleCount(claimed, other :: any) == PER_FORM
+				)
+			end
+		end
+
+		roster = claimed
+	end
+
+	-- EXHAUSTED. The refusal is the rule.
+	local exhausted, none = AmbientRoster.claim(roster, form :: any)
+
+	check(`claim past exhaustion refuses`, none == nil, tostring(none))
+	check(
+		`refused claim spawns nothing`,
+		AmbientRoster.visibleCount(exhausted, form :: any) == before
+	)
+
+	-- AND THE INPUT WAS NOT MUTATED. Asserted explicitly because an in-place edit is invisible until
+	-- two callers share a roster, which is what a rejoin looks like.
+	check(`claim does not mutate its argument`, roster ~= exhausted)
+end
+
+-- RELEASE IS IDEMPOTENT AND TOTAL. Phase 4 releases from five exits, at least two of which can fire
+-- for the same slot in the same frame.
+local roster = build()
+local claimed, slotIndex = AmbientRoster.claim(roster, "CAT")
+local released = AmbientRoster.release(claimed, slotIndex)
+
+check("release frees the slot", AmbientRoster.claim(released, "CAT") ~= nil)
+check("double release is a no-op", #AmbientRoster.release(released, slotIndex) == #released)
+check("release of nil is a no-op", #AmbientRoster.release(released, nil) == #released)
+check("release of a stale index is a no-op", #AmbientRoster.release(released, 9999) == #released)
+
+-- CONFIG CROSS-CHECK. The grid runs on PER_FORM = 3; this is where the live number is asserted to be
+-- usable at all, so a Config edit to 1 or 0 reds here as well as in `config.test.luau`.
+check("Ambient.PerForm >= 2", Config.Ambient.PerForm >= 2)
+
+print(`ambient-roster: {checked - failures}/{checked} passed`)
+
+if failures > 0 then
+	error(`{failures} ambient-roster assertions failed`)
+end
```

#### Step 3.3: Create `AmbientService` — spawn, wander, and the claim seam

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run analyze`

Server-owned population built from `Config.Ambient`, placed at `AmbientSpawn`-tagged points when the
map provides them and at a code-generated scatter when it does not.

**This is the answer to "is ambient life map content or code?" and the answer is code.** Three reasons,
in the order that decided it: the place file is gitignored, so a plan step depending on a human-placed
model is a step nothing can verify and `npm run build` cannot exercise; the SWAP has to be
server-authoritative anyway, because a client that decided which pig vanished would be deciding where
the monster is; and §5 says the entities need "no AI worth the name — a wander loop and an idle is
enough", which is well under the cost of a service. The map's job shrinks to placing markers, and
Step 3.5 writes that contract down.

```diff
+--!strict
+--[[
+	AmbientService — the barrio's cats, dogs, pigs and villagers. (V07, §4.3/§5)
+
+	WHAT THIS SERVICE IS FOR, IN ONE SENTENCE: camouflage needs a crowd, and §5 is explicit that "what
+	matters is the *count*". Three or four of each form, wandering, so that no single one is
+	conspicuous and a survivor who counts heads learns nothing.
+
+	IT OWNS THE POPULATION AND `MonsterService` OWNS THE MONSTER. The seam is two functions —
+	`ClaimSlot(form)` and `ReleaseSlot(index)` — and the decision behind them is `shared/pure/
+	AmbientRoster`, which is where "the head count does not move" is asserted over the whole roster
+	space. Nothing about a Player, a role or a UserId reaches this file.
+
+	SWAP, NEVER SPAWN (§4.3). A claim PARKS the real entity — reparented out of `workspace` into a
+	holding folder, not destroyed — and `MonsterService` re-skins the Aswang's own character into that
+	form. One thing stops being visible, one thing starts; the number standing in the barrio is
+	unchanged. Destroying the real one instead would work identically today and would silently break
+	the release path, because a released slot has to put something back.
+
+	WHERE THEY STAND, AND WHY THERE ARE TWO ANSWERS. The map is not in Git — geometry and spawn points
+	live in the place file, which is gitignored — so this service reads `CollectionService` tagged
+	`AmbientSpawn` parts when the map provides them, and falls back to a code-generated ring when it
+	finds none. The fallback is scaffolding for `npm run build` and for a fresh Studio session, not a
+	design: see the map contract below.
+
+	NO HUMANOID, NO PATHFINDING, NO PHYSICS. Each entity is a small anchored Model that the server
+	steps toward a target CFrame. §5 asked for a wander and an idle; a Humanoid per entity is 16
+	Humanoids on a phone, and `PathfindingService`'s cost at this population is a Roblox behaviour
+	this plan has NOT verified — recorded in Follow Ups rather than assumed.
+
+	THE APPEARANCE IS PARTS (§3's OUT list, and the zero art budget). A scaled, coloured block rig per
+	form, built in code, exactly as the transform re-uses the avatar rather than shipping a mesh. It
+	is placeholder-grade on purpose and V15 is where it stops being.
+]]
+
+local CollectionService = game:GetService("CollectionService")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local AmbientRoster = require(Shared.pure.AmbientRoster)
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local Types = require(Shared.Types)
+
+local AmbientService = {}
+
+local SPAWN_TAG = "AmbientSpawn"
+
+-- SERVER-ONLY. The roster is the pure module's; this table maps a slot index back to the Model that
+-- slot spawned, which is the half Lune cannot see.
+local roster: AmbientRoster.Roster = {}
+local models: { [number]: Model } = {}
+local entities: Folder? = nil
+local parked: Folder? = nil
+
+--[[
+	CLAIM A SLOT OF THIS FORM FOR THE MONSTER. Returns the index, or nil when this form is exhausted.
+
+	`MonsterService` calls this and refuses the hide on nil — `CamouflageRules.evaluate` answers
+	NO_SLOT. THERE IS NO PATH IN THIS FILE THAT CREATES AN ENTITY TO SATISFY A CLAIM, and that absence
+	is the mechanic: `AmbientRoster.claim` returns nil rather than appending, and this function has
+	nothing to add to it.
+
+	THE REAL ENTITY IS PARKED, NOT DESTROYED. Reparented into a folder outside `workspace` so the
+	release can put it back where it was. Its CFrame is not reset on return: a cat that reappears
+	across the map from where it vanished is a tell that costs nothing to avoid.
+]]
+function AmbientService.ClaimSlot(form: Types.CamouflageForm): number?
+	local claimed, slotIndex = AmbientRoster.claim(roster, form)
+
+	roster = claimed
+
+	if slotIndex == nil then
+		return nil
+	end
+
+	local model = models[slotIndex]
+
+	if model ~= nil and parked ~= nil then
+		model.Parent = parked
+	end
+
+	return slotIndex
+end
+
+--[[
+	GIVE THE SLOT BACK. IDEMPOTENT AND TOTAL, because Phase 4 releases from five exits and at least
+	two of them can fire for the same slot in the same frame — `ApplySaltHit` walks
+	`endFeed` -> `revert` -> exit camouflage, on a path `onPhaseChanged` may also be walking.
+]]
+function AmbientService.ReleaseSlot(slotIndex: number?)
+	roster = AmbientRoster.release(roster, slotIndex)
+
+	if slotIndex == nil then
+		return
+	end
+
+	local model = models[slotIndex]
+
+	if model ~= nil and entities ~= nil then
+		model.Parent = entities
+	end
+end
+
+--[[
+	WHERE THE POPULATION STANDS. Tagged points if the map has them; a ring if it does not.
+
+	THE FALLBACK MUST NOT SILENTLY REPLACE A REAL MAP. It fires only on ZERO tagged parts, never on
+	"fewer than we wanted" — a map with three markers and a Config asking for sixteen gets three
+	spawn points reused, which is visibly wrong in Studio and therefore fixable, rather than a ring of
+	pigs at the origin overlapping the barrio.
+]]
+local function spawnPoints(): { CFrame }
+	local points: { CFrame } = {}
+
+	for _, tagged in CollectionService:GetTagged(SPAWN_TAG) do
+		if tagged:IsA("BasePart") then
+			table.insert(points, tagged.CFrame)
+		end
+	end
+
+	if #points > 0 then
+		return points
+	end
+
+	local total = Config.Ambient.PerForm * 4
+
+	for index = 1, total do
+		local angle = (index / total) * math.pi * 2 -- config-ok: a full turn, not a knob
+		local radius = Config.Ambient.FallbackScatterRadius
+
+		table.insert(
+			points,
+			CFrame.new(math.cos(angle) * radius, Config.Ambient.FallbackHeight, math.sin(angle) * radius)
+		)
+	end
+
+	return points
+end
```

The remainder of the service — `buildEntity(form)` (the parts rig), `wanderTick()` (retarget every
`WanderInterval`, step at `WanderSpeed`, idle `IdleSeconds` on arrival, leashed to `WanderRadius` of
the spawn point) and `Init`/`Start` — follows `SearchService`'s shape: `Init` clears the tables, `Start`
creates the two folders, spawns the population and starts one `task.spawn` loop. **`Start` spawns
`Config.Ambient.PerForm` of each of `Enums.CamouflageForm`'s four values and nothing else ever calls
the spawn path** — a population that grows after `Start` is the swap-not-spawn rule broken from the
other end.

#### Step 3.4: Register the service in the bootstrap

**File:** `src/server/init.server.luau`
**Verify:** `npm run build`

The bootstrap runs `Init()` on every service and then `Start()` on every service. **Order matters in
one direction only:** `AmbientService.Start` must have run before any `MonsterService.ClaimSlot` can
succeed, and it will have — `MonsterService` cannot claim before a round is ACTIVE, which is many
seconds after both `Start` calls. `MonsterService` requires `AmbientService`, so `AmbientService` must
come before it in the require order for the same reason `SkyController` comes early on the client.

`npm run build` verifies this step rather than `analyze` because a bootstrap edit's failure mode is a
service that does not load at all, and `rojo build` is what proves the whole tree still assembles into
a place file.

#### Step 3.5: State the map's spawn-point contract

**File:** `src/server/Services/AmbientService.luau`

The tag contract a human satisfies in Studio, written into the service header where whoever opens the
place will find it. **No verify line, deliberately.** The map is not in Git — geometry, lighting and
spawn points live in the place file, which is gitignored and merge-hostile — so any check over it
either always passes or checks the wrong thing. `verify-plan` reports this step as `unverifiable` and
`next-phase.mjs` marks the phase `needs-human`, which is the accurate outcome: a person has to open
Studio, place the markers and publish.

The contract, in full, so nobody has to derive it:

- **Tag:** `AmbientSpawn`, applied with `CollectionService` (the Tag Editor in Studio) to a **BasePart**.
  Anything tagged that is not a BasePart is skipped rather than erroring.
- **Count:** at least `Config.Ambient.PerForm × 4` — sixteen at the shipped value. Fewer works: points
  are reused in order, which looks visibly wrong in Studio and is therefore fixable. Zero triggers the
  code fallback ring, which is scaffolding and not a map.
- **Placement:** spread across the bahay kubo, the chapel and the well area, matching §5's sightline
  rule — "you should almost always be able to see *something*". Entities wander
  `Config.Ambient.WanderRadius` (24) from their point and no further, so the points determine the
  distribution and the distribution is half the disguise: four pigs clustered in the plaza means the
  pig by the chapel is the monster.
- **The part itself is invisible scaffolding.** Anchored, `CanCollide = false`, `Transparency = 1`.
  Only its `CFrame` is read.
- **Publish afterwards.** The place file's only backup is Roblox's cloud version history, and a
  missing marker will never show up in `git status`.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the sharp one in this phase. The ambient entities are **Instances in
  `workspace`, and `workspace` replicates to every client**. Confirm three things: a parked entity is
  reparented OUT of `workspace` (a claimed slot whose Model stays in the tree with `Transparency = 1`
  is a client-readable index of where the monster is); no entity carries an attribute or tag naming a
  Player, a UserId or a claim state; and the Models are named by form and index (`Ambient_PIG_2`),
  never by anything derived from who claimed them.
- **Remote direction** — this service declares and fires no remotes at all, which is the strongest
  version of the property. Confirm it stays that way.
- **Rate limiting** — no `OnServerEvent` handler.
- **Magic numbers** — the wander, the leash, the count and the fallback ring all read from
  `Config.Ambient`. `math.pi * 2` carries a `-- config-ok:` waiver with a reason, as `rgb()` does.
- **Phase ownership** — `AmbientService` does not subscribe to `PhaseChanged` and must not set one.
  Ambient life is barrio scenery: it wanders in the lobby too, and a population that appeared when a
  round started would be a round-state readout in the geometry.
- **Player leaving mid-round** — §6.4 edge case. A player who leaves while camouflaged never calls
  `ReleaseSlot`, and the slot stays claimed with its entity parked for the rest of the round.
  `MonsterService.onPlayerRemoving` owns this and it is Step 4.6; this phase must make `ReleaseSlot`
  safe to call from inside a `PlayerRemoving` handler, which is why it is total rather than throwing.
- **Strict Luau** — `Enums.CamouflageForm`'s values already carry their `:: Types.CamouflageForm`
  casts, so iterating it and passing values into `ClaimSlot` typechecks. Constructing a form from a
  string literal in this file does not, and needs the cast.
- **Mobile budget** — 16 anchored Models, no Humanoids, no lights, no particles, and one server-side
  wander loop rather than 16 per-entity threads. §5's cap is about lights and particles and this
  spends neither; the part count is the thing to watch as V15 replaces the placeholder rigs.
- **Scope** — nothing from §3's OUT list. These are scenery with a wander loop, not NPCs with
  behaviour, and nothing about them is unlockable, purchasable or persistent.

**Issues identified:**

- **The wander loop and `workspace` streaming.** If the place has `StreamingEnabled` on, a server-moved
  anchored Model outside a client's streamed region is fine, but the client sees it pop in at its
  current position rather than mid-walk. Cosmetic, and named here because it will read as a bug in a
  playtest. `PerformanceController` already reacts to streaming and is the place to look.
- **A parked entity's CFrame must be preserved across the park/release cycle.** Reparenting an anchored
  Model does not move it, so this is free — but confirm the release path does not call a
  `PivotTo(spawnPoint)` that someone adds later for tidiness. A cat that reappears where it started
  rather than where it vanished is a tell.

---

### Phase 4: Server-side camouflage, and the one line that opens the gate

#### Step 4.1: Add the camouflage fields to the server-only monster record

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

Five fields on `MonsterState` and five initialisers in `stateFor`. **`monsters` is server-only, keyed by
UserId, never replicated** — the file header says so and every field added since V05 has honoured it.
None of these becomes an attribute, a tag, a Humanoid property or a payload field.

```diff
 	FeedBaseJumpPower: number?,
 	FeedBaseJumpHeight: number?,
+	--[[
+		THE GATE (V07, §4.3). SERVER-ONLY, AND THIS FIELD IS THE ONLY COPY OF IT.
+
+		False until this monster has taken a salt hit THIS ROUND. `MonsterService.ApplySaltHit` is the
+		only writer in the repo — see the assignment there for why that is a structural property and
+		not a convention.
+
+		NOT AN ATTRIBUTE AND NOT A TAG. Both replicate to every client and there is no private one, and
+		this particular boolean is worse than most: it is true for exactly one player in the round and
+		false for everyone else, so a single `GetAttribute` sweep of `Players` would name the Aswang
+		outright. The same shape as C04's revert brand and C14's WalkSpeed, both of which shipped with
+		`verify` and `check:secrecy` green (`.claude/lessons/absence-is-observable.md`).
+
+		SURVIVES A TRANSFORM CYCLE, DIES WITH THE ROUND — `Health`'s rule, for `Health`'s reason.
+		`revert()` does not clear it: §4.3's reveal is a fact about what the barrio has SEEN, and
+		reverting does not un-see it. `onPhaseChanged`'s existing `table.clear(monsters)` on the way
+		out of ACTIVE is the reset and it is the only one.
+	]]
+	HasBeenRevealed: boolean,
+	--[[
+		THE CHARGE (V07, §4.3). Spent on entry, restored ONLY by a completed feed.
+
+		A BOOLEAN RATHER THAN A COUNTER, even though `Config.Monster.CamouflageCharges` is a number.
+		The Config value is the ceiling V16 may raise; today it is 1, and a boolean cannot drift out of
+		range or go negative. When V16 raises it, this becomes a number and `pure/CamouflageRules
+		.chargeAfter` becomes `chargeCountAfter` — a change with a grid already around it.
+
+		STARTS TRUE, and that is safe ONLY because `HasBeenRevealed` starts false. The charge is the
+		second condition, never the first: an Aswang begins the round holding a charge it cannot spend,
+		and `CamouflageRules.evaluate` answers NOT_REVEALED before it ever looks at this field.
+	]]
+	HasCamouflageCharge: boolean,
+	--[[
+		THE DISGUISE ITSELF (V07, §4.3). Three fields, mirroring V06's `Feeding`/`FeedBody` shape.
+
+		`Camouflaged` is the state, `CamouflageForm` is which of the four it is wearing, `AmbientSlot`
+		is the index `AmbientService.ClaimSlot` returned — held so that every exit can hand it back,
+		and held as an INDEX rather than a Model for the same reason `AmbientRoster` deals in indices:
+		the service owns the Instances.
+
+		NOT A `MonsterState` ENUM VALUE, WHICH IS THE QUESTION `Enums.luau:62-72` DEFERRED TO THIS
+		CHUNK. The answer is the one V06 gave for `Feeding`: a field plus a derivation, because
+		`Transformed` has four readers outside this file and `Exposed` is a latch that coexists with
+		the form. `monsterStateOf` (Step 4.5) derives CAMOUFLAGED on demand.
+	]]
+	Camouflaged: boolean,
+	CamouflageForm: Types.CamouflageForm?,
+	AmbientSlot: number?,
 }
```

```diff
 		FeedBaseJumpPower = nil,
 		FeedBaseJumpHeight = nil,
+		--[[
+			FALSE, AND THIS IS THE LINE THE WHOLE CHUNK RESTS ON.
+
+			A record is created by `stateFor` the first time anything asks about a player, which for
+			the Aswang is its first transform. It begins un-revealed, and no code path anywhere sets
+			this true except `ApplySaltHit`. Change this initialiser to `true` and camouflage is
+			available from the first second of the round to a monster nobody has salted — which is
+			§4.3's stated total failure, and no test outside `tests/camouflage-rules.test.luau` would
+			report it.
+		]]
+		HasBeenRevealed = false,
+		HasCamouflageCharge = true,
+		Camouflaged = false,
+		CamouflageForm = nil,
+		AmbientSlot = nil,
 	}
```

#### Step 4.2: Set `HasBeenRevealed` in `ApplySaltHit`, and nowhere else

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

**This is the decision the request asked for, and here is the answer with its reasoning.** V07 ships
the gate **and** its setter. It does not defer the setter to V08.

The build plan's V08 entry says salt "sets `hasBeenRevealed` (the V07 gate)", which reads as a
deferral — but V08's actual work there is a *rework of salt into the generalised `ItemCarry`/`ItemThrow`
surface*, and that rework does not change where a salt hit lands. `ItemService.applyHit` already calls
`MonsterService.ApplySaltHit(target)` and that call site survives V08 untouched. So the choice is not
"V07 or V08" — it is "one line inside the function that already exists, or a V07 that ships a gate
nothing can ever open".

The second option is worse in three concrete ways:

1. **It cannot be playtested.** A `playtester` driving Studio at V07 would find camouflage refusing
   every request, correctly, and have no way to distinguish that from a broken implementation. The
   chunk's own Done criteria — "spent on use; restored only by feeding; swap-not-spawn" — are all
   downstream of a reveal that never happens.
2. **It moves the gate's most dangerous edit into a chunk that is not about the gate.** V08 is a
   670-line item rework. A `HasBeenRevealed = true` added there is one line in a large diff about
   something else, reviewed by someone thinking about carry slots.
3. **It does not make the shipped tree safer.** A gate with no setter and a gate with exactly one
   setter are equally closed; the difference is only whether the mechanic works.

**And the fail-closed property the request demands holds either way**, because it comes from the pure
module, not from the setter: `CamouflageRules.evaluate` returns `NOT_REVEALED` as its first branch, the
field initialises false, and 100 grid cells assert that no combination of the other three inputs
produces `OK` without it. If the setter were deleted tomorrow, camouflage would be provably impossible
rather than accidentally available.

**Why `ApplySaltHit` is the right line and not merely a convenient one.** The V06 header already
records that it is "the ONLY entry point for a salt hit; there is no bare `ForceRevert` any more,
precisely so a caller cannot revert without damaging". That property was built for the health system
and V07 inherits it: **there is no way to salt a monster without revealing it, and no way to reveal one
without salting it.** The flag and the damage are set three lines apart in the one function every salt
hit in the game goes through.

**The transition goes through the pure module rather than being written inline**, so that "only a salt
hit reveals" is a fact `tests/camouflage-rules.test.luau` asserts over all eight events rather than a
property of this call site.

```diff
 	endFeed(player.UserId, "FEED_INTERRUPTED")
 	revert(player)
 	applyHealthEvent(player.UserId, "SALT")
 	applyExposed(player)
+
+	--[[
+		AND THE GATE OPENS (V07, §4.3). THE ONLY LINE IN THIS REPOSITORY THAT SETS `HasBeenRevealed`.
+
+		§4.3: "Camouflage is locked until the Aswang has been publicly revealed — that is, until it has
+		taken a salt hit." The build plan adds the reason the condition is THIS one: "'someone saw it
+		transform' is not knowable server-side; a salt hit is a fact the server already owns."
+
+		HERE RATHER THAN ANYWHERE ELSE, because this function is already the only entry point for a
+		salt hit — V05 removed the bare `ForceRevert` precisely so a caller could not revert without
+		damaging, and V07 inherits that: there is now no way to salt a monster without revealing it and
+		no way to reveal one without salting it. A second writer added later would break a property
+		that three chunks are leaning on, which is why it is stated here rather than left implicit.
+
+		AFTER `applyExposed`, NOT BEFORE, AND THE ORDER IS DELIBERATE THOUGH NOT LOAD-BEARING TODAY.
+		Nothing in the four lines above reads this field. Setting it last means that if any of them
+		ever throws, the monster is not left revealed by a salt hit that did not fully land — the
+		failure falls towards the survivors having to throw again, never towards a free camouflage.
+
+		THROUGH `CamouflageRules.revealedAfter` RATHER THAN `= true`, and the indirection earns its
+		keep: the transition table is asserted over all eight round events, so "nothing but salt
+		reveals" is proven in `tests/camouflage-rules.test.luau` rather than being a property of
+		whichever call sites someone remembered to check. It is also one-way — no event un-reveals —
+		so a stray call with the wrong event cannot re-close the gate mid-round either.
+
+		READ, DO NOT CONSTRUCT. `stateFor` here would re-insert a departed player's UserId; `revert()`
+		above documents the same trap. A player with no monster state cannot have been salted.
+	]]
+	local monster: MonsterState? = monsters[player.UserId]
+
+	if monster ~= nil then
+		monster.HasBeenRevealed = CamouflageRules.revealedAfter(monster.HasBeenRevealed, "SALT_HIT")
+	end
 end
```

**`check:secrecy` is the verify here rather than `analyze`** because this is the step that adds the
role-adjacent boolean, and the check is a text tripwire over attributes, tags and broadcast payloads. It
proves the flag did not land on one of those. It does **not** prove the flag has one writer — that is a
question for `exploit-auditor`, and it is question (1) of the three the build plan names for this chunk.

#### Step 4.3: Restore the charge from the `FeedCompleted` seam

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify:fast`

V06 built this seam for V07 and documented it as such. **Do not add a second path.** The header states
the property that makes §4.3's "interrupting a feed is a real victory" structural rather than careful:
`completeFeed` is the only caller of `HealFromFeed` and the only firer of `FeedCompleted`, and `endFeed`
— which all six interruption paths go through — does neither. **Nobody has to remember to withhold the
camouflage refresh on a salt hit, because there will be no code that could grant it.**

Connect in `Start`, beside the other subscriptions, rather than at module scope.

```diff
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
 	Players.PlayerAdded:Connect(onPlayerAdded)
 	Players.PlayerRemoving:Connect(onPlayerRemoving)
+
+	--[[
+		THE CHARGE COMES BACK (V07, §4.3). THE FIRST AND ONLY SUBSCRIBER TO `FeedCompleted`.
+
+		§4.3: "Camouflage is spent on use and only a feed restores it. Once revealed, the Aswang must
+		kill to hide." That sentence is the best pressure loop in the design — a revealed monster that
+		wants to disappear again has to make a corpse and stand on it, in the open, for five seconds,
+		at a place the survivors already know about.
+
+		THIS EVENT AND NOT A CALL INSIDE `completeFeed`, even though this service owns both ends. The
+		event is the documented seam; a direct call would work identically today and would make the
+		next listener — V09's, V13's — the one that has to decide whether to use the event or copy the
+		call. One joint, one shape.
+
+		THROUGH `CamouflageRules.chargeAfter`, for the reason Step 4.2 states: the transition is
+		asserted over all eight events, so "an interrupted feed restores nothing" is a tested fact
+		rather than an absence someone has to notice.
+
+		IT DOES NOT CHECK `HasBeenRevealed`. §4.3 gives a completed feed its two rewards
+		unconditionally; the gate is on SPENDING the charge, not on holding one. An unrevealed Aswang
+		that feeds restores a charge it already had and still cannot use — which is exactly right, and
+		a reveal check here would mean a monster salted AFTER a feed found itself with no charge for
+		reasons no player could reconstruct.
+
+		READ, DO NOT CONSTRUCT: `stateFor` would re-insert a departed player.
+	]]
+	MonsterService.FeedCompleted.Event:Connect(function(player: Player)
+		local monster: MonsterState? = monsters[player.UserId]
+
+		if monster == nil then
+			return
+		end
+
+		monster.HasCamouflageCharge =
+			CamouflageRules.chargeAfter(monster.HasCamouflageCharge, "FEED_COMPLETED")
+	end)
```

`verify:fast` (analyze + remotes + secrecy + toolchain) is the check here: the risk in this step is a
type error on the `BindableEvent`'s payload and a subscriber that accidentally sends something, and it
covers both in about three seconds.

#### Step 4.4: Enter and exit camouflage against the roster claim

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run lint`

Two functions, `enterCamouflage` and `exitCamouflage`, called by nothing until Phase 5. **The look
change goes through the transform's existing `captureLook` / `restoreLook` / `applyScale` /
`trackedEffect` machinery and must not invent a second one.** C04 shipped a revert that restored
hardcoded defaults instead of captured state and branded the ex-Aswang map-wide, with `verify` and
`check:secrecy` green over it; camouflage is a *second* appearance change on the same character, so a
parallel restore path is that bug with a longer fuse.

```diff
+--[[
+	BECOME THE CAT. (V07, §4.3) One caller: Phase 5's `RequestCamouflage` handler, on a request the
+	rules module has already granted.
+
+	THE ORDER IS: CLAIM, THEN SPEND, THEN CHANGE THE LOOK. A claim that fails must cost nothing — the
+	rules module answers NO_SLOT and the charge is still there — so the claim happens first and the
+	spend happens only after a slot index is in hand. Reversed, an Aswang in a barrio with no cats left
+	would lose its charge to a hide that never happened, and would have to kill again to get it back
+	for reasons invisible from inside the game.
+
+	THE MONSTER STAYS TRANSFORMED UNDERNEATH. `Transformed` is not cleared: camouflage is a second
+	appearance layer over the monster form, not a revert. This matters at both exits — stepping out
+	returns to the monster, not to the player — and it is why `monsterStateOf` (Step 4.5) has to check
+	`Camouflaged` BEFORE `Transformed` rather than after.
+
+	NO BROADCAST. `MonsterTransformed` is not fired and no new remote is either. §4.3's public half is
+	that a player avatar is gone and an animal is standing there, and both replicate as geometry. A
+	broadcast would be the server STATING what the world already shows, which is the difference between
+	`MonsterTransformed` (a moment nobody may miss) and this (a thing you either saw or did not).
+]]
+local function enterCamouflage(player: Player, form: Types.CamouflageForm): boolean
+	local monster = monsters[player.UserId]
+	local character = player.Character
+
+	if monster == nil or character == nil then
+		return false
+	end
+
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+
+	if humanoid == nil then
+		return false
+	end
+
+	local slotIndex = AmbientService.ClaimSlot(form)
+
+	if slotIndex == nil then
+		return false
+	end
+
+	monster.AmbientSlot = slotIndex
+	monster.Camouflaged = true
+	monster.CamouflageForm = form
+	monster.HasCamouflageCharge =
+		CamouflageRules.chargeAfter(monster.HasCamouflageCharge, "CAMOUFLAGE_ENTERED")
+
+	--[[
+		THE LOOK, THROUGH THE PATH THAT ALREADY EXISTS. `captureLook` records every part's colour and
+		material and every humanoid scale value BEFORE anything is written, and `restoreLook` puts back
+		exactly what was captured — never a default. C04 shipped the other version of this function and
+		branded the ex-Aswang permanently, map-wide, with every check green.
+
+		CAPTURING TWICE IS THE TRAP HERE AND IT IS WHY THIS CALL IS GUARDED. The transform already
+		captured this character; capturing again would record the MONSTER's colours as the originals,
+		and the eventual revert would leave a player wearing them. `Applied` is the existing flag for
+		"the look is physically on a character", so the capture is skipped when it is already set.
+	]]
+	if not monster.Applied then
+		captureLook(monster, character, humanoid)
+		monster.Applied = true
+		monster.AppliedTo = character
+	end
+
+	applyCamouflageLook(monster, character, humanoid, form)
+
+	return true
+end
+
+--[[
+	STOP BEING THE CAT. (V07, §4.3) FIVE CALLERS, and that is why it is idempotent and total: the
+	transform request, a salt hit, death, leaving, and the round ending. At least two of them can fire
+	for the same player in the same frame — `ApplySaltHit` walks `endFeed` -> `revert`, and
+	`onPhaseChanged` may be walking the same monster.
+
+	THE SLOT GOES BACK FIRST. `AmbientService.ReleaseSlot` un-parks the real entity, so the barrio's
+	head count is restored before anything else can fail. A version that released last would leave a
+	permanently missing pig behind any error in the look restore — invisible, cumulative, and exactly
+	the degradation §4.3's swap rule exists to prevent.
+
+	THE CHARGE DOES NOT COME BACK. `CamouflageRules.chargeAfter(_, "CAMOUFLAGE_EXITED")` returns the
+	current value and the grid asserts it. Stepping out of a cat is not a feed.
+]]
+local function exitCamouflage(player: Player)
+	local monster = monsters[player.UserId]
+
+	if monster == nil or not monster.Camouflaged then
+		return
+	end
+
+	AmbientService.ReleaseSlot(monster.AmbientSlot)
+
+	monster.AmbientSlot = nil
+	monster.Camouflaged = false
+	monster.CamouflageForm = nil
+
+	--[[
+		BACK TO THE MONSTER, NOT BACK TO THE PLAYER. `Transformed` was never cleared, so the character
+		is still an Aswang underneath and `applyFullLook` is the right restore — `restoreLook` here
+		would return the player's own appearance while `Transformed` stayed true, and the next
+		`revert()` would then restore the MONSTER's colours as though they were the originals.
+
+		A CHARACTER THAT WENT AWAY IS NOT AN ERROR. Death and leaving both reach this function, and
+		both may arrive with no character or no humanoid. The slot has already been handed back above,
+		which is the part that must happen regardless.
+	]]
+	local character = monster.AppliedTo
+
+	if character == nil then
+		return
+	end
+
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+
+	if humanoid ~= nil and monster.Transformed then
+		applyFullLook(monster, character, humanoid)
+	end
+end
```

`applyCamouflageLook` is a sibling of the existing `applyFullLook`: it scales the character down per
form, recolours through the same tracked path, and hides accessories. **Every instance it creates goes
through `trackedEffect`**, so `clearEffects` removes exactly what this service made and nothing else.

`npm run lint` (selene) is the check here rather than a test: there is nothing pure in this step to run,
the two functions have no caller yet, and the failure mode selene actually catches at this size is a
shadowed local or an unused variable left behind by the capture guard.

#### Step 4.5: Teach `monsterStateOf` the fifth state

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run test:unit`

`monsterStateOf` currently produces three of `Enums.MonsterState`'s five values and its header states
why the other two are absent: `EXPOSED` is a latch, and "`CAMOUFLAGED` has no producer until V07". This
is V07.

```diff
 local function monsterStateOf(monster: MonsterState): Types.MonsterState
+	--[[
+		CAMOUFLAGED FIRST, ABOVE FEEDING AND ABOVE TRANSFORMED (V07, §4.3). ORDER IS THE CONTRACT.
+
+		A camouflaged Aswang is still `Transformed` underneath — camouflage is an appearance layer over
+		the monster form, not a revert — so checking `Transformed` first would report TRANSFORMED for a
+		monster standing in the barrio as a pig. `FeedRules.evaluate` would then grant it a feed, and
+		`CamouflageRules.evaluate` would never see ALREADY_CAMOUFLAGED, so a second hide would claim a
+		second slot and the first one would leak for the rest of the round.
+
+		FEEDING AND CAMOUFLAGED ARE MUTUALLY EXCLUSIVE BY CONSTRUCTION, not by this ordering: the
+		rules module refuses a hide while FEEDING, and `beginFeed` is reached only from `commitKill`,
+		which needs a kill, which needs monster form. The order here decides what is REPORTED if they
+		ever both become true, and reporting CAMOUFLAGED is the safer of the two — it refuses the feed
+		rather than granting a hide.
+	]]
+	if monster.Camouflaged and monster.Transformed then
+		return Enums.MonsterState.Camouflaged
+	end
+
 	if monster.Feeding and monster.Transformed then
 		return Enums.MonsterState.Feeding
 	end
```

**`BOTH FLAGS, NEVER `Camouflaged` ALONE`** — V06's rule for `Feeding`, and it is load-bearing for the
same reason: written as `if Camouflaged then`, a camouflaged monster whose transform was reverted by a
path nobody thought of would report CAMOUFLAGED forever and every backstop that reads "the form went
away" would stop firing.

`npm run test:unit` is the check because `tests/feed-rules.test.luau` already asserts what a
`CAMOUFLAGED` monster may do — it may not feed — over the full grid. This step makes that value
producible for the first time, so the existing suite is the thing that can genuinely fail.

#### Step 4.6: Close the five exits — phase change, leave, death, salt, revert

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify`

Spec §6.4 lists the edge cases that will bite; V06 closed its six and this chunk has five. **Each one
leaves a claimed ambient slot behind if it is missed**, and a leaked slot is silent, cumulative and
un-diagnosable from inside the game: the barrio quietly loses a pig per round until the disguise stops
working.

**1. A salt hit while camouflaged.** §4.6 forces a revert; a monster wearing a cat must be forced out of
the cat too, or salt would strip the monster form and leave the disguise on. Ordering in
`ApplySaltHit`, above the existing `endFeed` line so the disguise is gone before anything else runs:

```diff
 function MonsterService.ApplySaltHit(player: Player)
+	--[[
+		THE DISGUISE DIES FIRST (V07, §4.3/§4.6). Before `endFeed`, before `revert`.
+
+		Salt forces a revert, and a revert out of the MONSTER form while the CAT form stayed on would
+		leave a player-shaped nothing wearing a cat: `revert` restores from `OriginalParts`, which
+		camouflage overwrote on top of. Exiting first means `revert` finds the character in exactly the
+		state it expects — transformed, un-camouflaged — which is the state every one of its comments
+		was written about.
+
+		AND IT IS THE COUNTERPLAY. A survivor who lands salt on a suspicious pig gets a monster, in the
+		open, glowing. That is §4.6's reveal doing its job on §4.3's disguise, and it is the single
+		most satisfying thing this chunk can produce.
+	]]
+	exitCamouflage(player)
 	endFeed(player.UserId, "FEED_INTERRUPTED")
 	revert(player)
```

**2. The round ends while camouflaged.** `onPhaseChanged` already walks `monsters` on the way out of
ACTIVE, calling `endFeed`, `revert` and `clearExposed` before `table.clear`. Camouflage joins that loop,
**before the revert** for the reason above, and it must run **before `table.clear` drops the handle** —
the same argument the `clearExposed` comment makes about orphaning a Highlight, except that what is
orphaned here is an ambient entity parked outside `workspace` with nothing left that knows it exists.

**3. A player leaves while camouflaged.** `onPlayerRemoving` nils the entry, and the existing comment
records that it calls `clearExposed` first "for what nilling alone leaves behind". Same shape:
`exitCamouflage` before the nil, or the slot is claimed for the rest of the round and the parked entity
never comes back. This is the one case `onPhaseChanged`'s loop **cannot** cover, because the player is
already out of `monsters` by the time it runs.

**4. Death while camouflaged.** `watchCharacter`'s `Humanoid.Died` connection already reverts; it gains
the exit for the same reason. Note what this is not: the kill path does not go through `Humanoid.Died`
— the victim's character is detached and anchored — so this covers falling out of the world and a
Studio reset, which are exactly the paths that produce a character with no humanoid.

**5. A transform request while camouflaged.** `validateAndTransform` is how the Aswang steps out
(there is deliberately no `RequestExitCamouflage` — see `Remotes.luau`). A camouflaged monster firing it
must exit the disguise and stay transformed, **not** run a fresh transform: `TransformRules` would
answer `ALREADY_TRANSFORMED`, correctly, and the handler must exit camouflage *before* consulting it or
the request refuses and the player is stuck as a pig with no way out.

`npm run verify` is the check for this step, and it is the right one: five edit sites across four
functions, and the failure mode is a path that no longer typechecks or a suite that no longer passes.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the highest-risk phase in the chunk, and there are three distinct questions.
  (a) Do any of the five new fields reach an attribute, a tag, a Humanoid property or a payload? They
  must not; `monsters` is server-only and every field since V05 has honoured that. (b) Does
  `applyCamouflageLook` write anything a client can read as a *difference between players* — a
  WalkSpeed, a JumpPower, a Humanoid scale left at a value nobody else has? C14's WalkSpeed brand and
  C04's revert brand were both exactly this and both shipped green. (c) Does the exit path restore
  captured state rather than a default, on every one of the five exits?
- **Remote direction** — this phase adds no handler and fires nothing. `CamouflageUpdate` exists from
  Phase 2 and stays unfired until Phase 5.
- **Rate limiting** — no `OnServerEvent` handler added this phase.
- **Magic numbers** — the per-form scale factors in `applyCamouflageLook` are the ones to watch.
  `Config.Monster` or a `Config.Ambient.FormScale` table, never a literal in the service.
- **Phase ownership** — `MonsterService` subscribes to `PhaseChanged` and never calls `setPhase`.
  Confirm the camouflage exit is inside the existing subscriber rather than in a new one.
- **Player leaving mid-round** — edge case 3 above, and it is the one that cannot be covered from
  anywhere else.
- **Strict Luau** — `Types.CamouflageForm?` on the record needs the union from `Types`, and
  `Enums.CamouflageForm`'s members already carry their casts. A form built from a bare string literal
  in this file infers as `string` and fails to satisfy `ClaimSlot`.
- **Mobile budget** — `applyCamouflageLook` must not add a light or an emitter. The transform already
  spends particles; a second effect layer on the same character doubles it for the one player most
  likely to be on screen.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **The capture guard in `enterCamouflage` is the subtlest thing in this phase.** `captureLook` is
  skipped when `Applied` is already set, which is correct for the normal path (transform, then hide) —
  but confirm there is no order in which a character can reach `enterCamouflage` with `Applied` false
  and a look already on it. If one exists, the monster's colours become the "originals" and the
  eventual revert brands the player.
- **`exitCamouflage` calls `applyFullLook`, which may re-create tracked effects.** Confirm
  `clearEffects` runs first or that `applyFullLook` is idempotent; otherwise a hide/unhide cycle leaves
  two particle emitters on the character, which is both a mobile-budget leak and a visible tell.
- **Five exits and one entry is an asymmetry worth auditing rather than trusting.** This is
  `exploit-auditor` question (2) — "does the ambient population count change when it fires" — and the
  honest answer is that `AmbientRoster` proves the arithmetic while only a reader can prove that every
  exit reaches `ReleaseSlot`. Name all five in the audit brief.

---

### Phase 5: The remote surface and the smoke field

#### Step 5.1: Wire `RequestCamouflage`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:ratelimit`

**The rate limit lives inline, at the connect site, and `Consume` comes first** — before any state is
read. `check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within 1200
characters of an `.OnServerEvent:Connect(`, and it is a proximity tripwire by its own admission: a
handler that IS limited but does it 250 lines away reads as unguarded and fails the build. Copy the
shape `RequestTransform` and `RequestKill` already set.

```diff
+	--[[
+		V07, §4.3. Same shape as the two handlers above, for the same reason: `check-ratelimit.mjs`
+		matches the Consume call within 1200 characters of the connect site. Consume FIRST, before any
+		state is read — a handler that validates first has already done the expensive work by the time
+		it refuses, which is what makes a remote worth spamming.
+
+		NO ARGUMENTS FROM THE CLIENT, so there is no `typeof` guard here and nothing to validate about
+		the payload. The form is the SERVER's choice — see `Remotes.luau` for why a client-named form
+		would be a probe for the live ambient population.
+	]]
+	Remotes.Get("RequestCamouflage").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestCamouflage") then
+			return
+		end
+
+		validateAndCamouflage(player)
+	end)
```

`validateAndCamouflage` follows `validateAndTransform`'s shape exactly:

```diff
+--[[
+	MAY THIS PLAYER HIDE, AND IF SO, AS WHAT? (V07, §4.3)
+
+	THE ROLE CHECK IS FIRST AND IT IS `RoleService`'S ANSWER, NOT AN INFERENCE FROM `monsters`. A
+	player with no monster state is not the Aswang, but the converse is what matters: `stateFor` is
+	called from several paths and an entry existing is not a role. `validateAndTransform` already ANDs
+	the two and this does the same.
+
+	THE REFUSAL VERDICT IS NOT ECHOED BACK IN FULL, AND THAT IS THE ONE PLACE THIS HANDLER DIFFERS
+	FROM `validateAndTransform`. A non-Aswang firing this remote is told NOTHING — no CamouflageUpdate
+	at all — because a `NOT_ASWANG` verdict on the wire is a free role oracle for anyone willing to
+	spam a remote, which is exactly the reasoning the transform's header records. An ASWANG gets its
+	real verdict, because every value in `CamouflageVerdict` concerns the receiver's own business.
+
+	THE WITNESS CHECK IS THE SERVER'S AND IT IS NOT IN THE PURE MODULE. `CamouflageWitnessRadius` needs
+	positions of other characters, which is a DataModel read; the pure module deals in the four inputs
+	§4.3 names. Refusing here rather than there is the same split `FeedRules` makes with the leash.
+]]
+local function validateAndCamouflage(player: Player)
+	if RoleService.GetRole(player.UserId) ~= Enums.Role.Aswang then
+		return
+	end
+
+	local monster = monsters[player.UserId]
+
+	if monster == nil then
+		return
+	end
+
+	--[[
+		ALREADY HIDING MEANS "STOP", AND IT IS RESOLVED BEFORE THE RULES MODULE IS ASKED.
+
+		`CamouflageRules.evaluate` would answer ALREADY_CAMOUFLAGED, correctly — it is a refusal to
+		START a second hide, which is what that function is about. Exiting is a different verb and it
+		is unconditional: a monster that cannot get out of a cat because the phase changed underneath
+		it is stuck as scenery for the rest of the round.
+	]]
+	if monster.Camouflaged then
+		exitCamouflage(player)
+		sendCamouflageUpdate(player, "CAMO_EXITED", nil)
+		return
+	end
+
+	local form = AmbientService.PickAvailableForm()
+
+	local verdict = CamouflageRules.evaluate({
+		HasBeenRevealed = monster.HasBeenRevealed,
+		HasCharge = monster.HasCamouflageCharge,
+		MonsterState = monsterStateOf(monster),
+		Phase = RoundService.GetPhase(),
+		SlotAvailable = form ~= nil,
+	})
+
+	if verdict ~= "OK" or form == nil then
+		sendCamouflageUpdate(player, camouflageVerdictFor(verdict), nil)
+		return
+	end
+
+	if not isUnwitnessed(player) then
+		sendCamouflageUpdate(player, "CAMO_WITNESSED", nil)
+		return
+	end
+
+	if enterCamouflage(player, form) then
+		sendCamouflageUpdate(player, "CAMO_OK", form)
+	end
+end
```

`AmbientService.PickAvailableForm()` returns a form with a free slot, or nil — the read-only companion
to `ClaimSlot`, so the rules module can be told `SlotAvailable` without a claim happening first.
`isUnwitnessed` walks `Players`, skips the requester, and returns false if any living character's root
is within `Config.Monster.CamouflageWitnessRadius`. `camouflageVerdictFor` maps the pure module's
`Verdict` onto `Types.CamouflageVerdict` — the prefixed union exists so the two cannot be passed to each
other's handler by accident.

#### Step 5.2: Wire `RequestSmoke` and hold the live bursts server-side

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:remotes`

**This is the answer to "smoke in a server-authoritative game", and the split is: the CLOUD is server
state, the PARTICLES are presentation.** A live burst is an entry in a server-side table holding a
centre, a radius and an expiry. Steps 5.3 and 5.4 consult that table before granting a kill or a
throw. The client is sent a position and a duration so it can draw something, and **nothing the client
does with that message changes what the server permits** — a player who deletes the emitter, turns
graphics to minimum, or never receives the payload gets exactly the same rules as everyone else.

```diff
+--[[
+	THE LIVE SMOKE FIELD (V07, §4.3). SERVER-ONLY, and it is the mechanic rather than the effect.
+
+	"Breaks line of sight" has to mean something the server enforces, or it is a decoration a client
+	can switch off. So a burst is three numbers and a deadline here, `pure/CamouflageRules.smokeBlocks`
+	answers whether a given segment passes through one, and the two places in this game that ask a
+	line-of-sight question — `hasLineOfSight` for a kill, `ItemService`'s throw resolution — consult it.
+
+	A LIST RATHER THAN ONE ENTRY, even though `SmokeCooldown` means one Aswang can only have one live
+	at a time. Bursts outlive the requester's state — a monster that dies inside its own cloud leaves
+	it standing for the remainder of `SmokeDuration`, which is correct: the cloud is a thing in the
+	world, not a property of a player.
+
+	NO PLAYER FIELD, HERE EITHER. The table holds no UserId and no character. Nothing needs one — the
+	cooldown lives on the monster record where the rest of that player's state is — and its absence
+	means there is no field for a later payload to grow one from.
+]]
+type SmokeBurst = {
+	Centre: Vector3,
+	Radius: number,
+	ExpiresAt: number,
+}
+
+local smokeBursts: { SmokeBurst } = {}
```

```diff
+	-- V07. Same shape and same reason as every handler above it: Consume FIRST, inline, within sight
+	-- of the connect site. No arguments — the burst happens at the requester's own position, and a
+	-- position argument would be a "drop a cloud anywhere" primitive.
+	Remotes.Get("RequestSmoke").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestSmoke") then
+			return
+		end
+
+		validateAndSmoke(player)
+	end)
```

`validateAndSmoke` checks the role against `RoleService` first and silently returns for a non-Aswang —
the transform handler's rule, and for its reason — then asks `CamouflageRules.evaluateSmoke` with the
monster's `HasBeenRevealed`, the phase, `os.clock()`, `monster.LastSmokeAt` and
`Config.Monster.SmokeCooldown`. On `OK` it stamps `LastSmokeAt`, appends a burst at the requester's
root position with `Config.Monster.SmokeRadius` and an expiry of `now + Config.Monster.SmokeDuration`,
and fires Step 5.5's send. `LastSmokeAt: number?` is a sixth field on `MonsterState`, initialised nil,
cleared with the round by the existing `table.clear`.

**Expired bursts are dropped lazily, inside the function that reads them** — a back-to-front loop with
`table.remove` at read time rather than a seventh `task.spawn` tick. There is at most one live burst per
Aswang and the readers already run per-kill and per-throw.

`npm run check:remotes` is the check: this step is where the two up-remotes acquire handlers, and the
failure it catches — a remote fired in the wrong direction, or used but not declared — is the one that
**hangs the client forever with no error, no output and no stack trace**.

#### Step 5.3: Make smoke block a kill on the server

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

`hasLineOfSight(killerRoot, targetRoot)` already raycasts and already excludes the corpses folder. Smoke
becomes a second reason the same function answers false.

```diff
 local function hasLineOfSight(killerRoot: BasePart, targetRoot: BasePart): boolean
+	--[[
+		SMOKE BREAKS IT, AND THIS IS WHERE "BREAKS LINE OF SIGHT" BECOMES A RULE (V07, §4.3).
+
+		Asked BEFORE the raycast, because it is cheap arithmetic over at most one live burst and the
+		raycast is not — and because the answer does not depend on geometry the map author controls.
+
+		THE SAME FUNCTION FOR BOTH DIRECTIONS, WHICH IS THE PROPERTY WORTH KEEPING. A cloud that
+		stopped the monster killing but not the survivors throwing would make smoke a gift to the
+		survivors; the reverse would make it a free kill button. `smokeBlocks` is symmetric in its two
+		points, so there is no version of this that is asymmetric by accident.
+
+		IT DOES NOT CARE WHO PLANTED IT. The monster is blinded by its own cloud, which is §4.3's
+		design — smoke "covers a disengage", and a disengage is not a kill.
+	]]
+	if smokeBlocksSegment(killerRoot.Position, targetRoot.Position) then
+		return false
+	end
+
```

`smokeBlocksSegment(from, to)` is the thin adapter: it drops expired bursts, converts two `Vector3`s
through the existing `vec()` helper into `CamouflageRules.Vec3`, and returns true if any live burst's
`smokeBlocks` says so. `vec()` already exists for `KillValidation` and does exactly this job.

`npm run analyze` is the check — the risk in this step is a type error at the `Vector3`/`Vec3` boundary,
which is precisely what `luau-lsp` graded against `analyze-baseline.json` catches.

#### Step 5.4: Make smoke block a salt throw on the server

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:secrecy`

The other half of symmetry. `ItemService` resolves every throw through `pure/SaltThrow.inCone` and
calls `applyHit(target)` on a hit; a target standing behind or inside a live cloud must resolve as a
`MISS`, through the **same collapsed verdict `SaltThrow` already uses**.

**That collapse is load-bearing and must not be widened here.** `SaltThrow` deliberately reports one
`MISS` for every failure reason, because a throw is a request a *survivor* makes about *another player*
— a split verdict would let a client stand in front of each player in turn and read the monster off the
refusal shape. A new `MISS_SMOKE` value would be exactly that: a verdict that is only ever produced when
the Aswang has planted a cloud, delivered to a survivor, naming a direction. Reuse `MISS`.

`MonsterService` exposes the query as a seam rather than `ItemService` reaching into the burst table:

```diff
+--[[
+	IS THIS SEGMENT INSIDE A LIVE SMOKE CLOUD? (V07, §4.3) V07'S SEAM FOR `ItemService`, joining the
+	five `MonsterService` already publishes.
+
+	SAFE TO EXPOSE FOR `IsExposed`'S REASON: a smoke cloud is ALREADY PUBLIC — there is a visible burst
+	standing in the world that every client with line of sight can see, which is the entire point of
+	it. This function states nothing a player standing there cannot see, it never enumerates, and it
+	takes two positions the caller already holds.
+
+	IT NAMES NO PLAYER IN EITHER DIRECTION. It does not say whose cloud, and it does not ask who is
+	throwing. A boolean about a line segment is not a fact about a person.
+]]
+function MonsterService.SmokeBlocks(from: Vector3, to: Vector3): boolean
+	return smokeBlocksSegment(from, to)
+end
```

`ItemService` consults it beside the existing checks and resolves a blocked throw as `MISS` — the same
path as a throw that landed outside the cone. **`check:secrecy` is the check** because this step widens
`MonsterService`'s public seam surface and touches the throw's verdict path, which is the one place in
the game where a refusal shape is itself a role oracle.

#### Step 5.5: Send `SmokeBurst` to the players in radius, and to nobody else

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run build`

**Never `FireAllClients`.** The send walks `Players`, measures each character's distance to the burst
centre on the **server**, and `FireClient`s only those inside `Config.Monster.SmokeCueRadius`. A player
out of radius receives nothing at all.

This is `NoiseCue`'s pattern and it exists for `NoiseCue`'s reason, restated because a phase is read on
its own: **a broadcast carrying a position hands every client a live index of where the monster is the
instant it tries to escape** — readable from a compromised client with no exploit beyond listening, and
strictly more than V13's 90s-to-30s tracker will ever give the survivors. The distance test happens on
the server; there is no client-side filter and there must not be one.

```diff
+--[[
+	TELL THE PEOPLE WHO CAN SEE IT (V07, §4.3), AND NOBODY ELSE.
+
+	THE AUDIENCE IS ONE EXPRESSION, and that is deliberate rather than tidy — `announceTransform`'s
+	header records why. When someone later wants to narrow or widen this, a change to the audience is
+	a change to the whole send, visible as such in a diff, rather than two adjacent loops that can
+	drift apart.
+
+	THE POSITION IS EXACT RATHER THAN QUANTISED, unlike `NoiseCue`'s. Noise carries 60 studs, far past
+	what a listener can see, so its position is quantised because the payload would otherwise state
+	more than the world does. Smoke's send radius is 40 and the cloud is 18: everyone who receives
+	this is close enough to WATCH it form, so an exact centre states nothing they will not see rendered
+	a frame later. IF `SmokeCueRadius` IS EVER RAISED WELL PAST VISUAL RANGE, THIS REASONING EXPIRES
+	and the position must be quantised to `Config.Noise.CueGridStuds`.
+
+	NO PLAYER FIELD. `Types.SmokeBurstPayload` is a position, a duration and a radius. Smoke is fired
+	only by the Aswang, so a UserId here would be a role broadcast with a location attached — the
+	single worst payload this game could produce, and `check:secrecy` matches `killer\w*` and the
+	enumerated role tokens rather than a field called `Source`.
+
+	THE REQUESTER IS IN THE AUDIENCE, by the same distance test as everyone else rather than by a
+	special case. It is standing at the centre, so it passes trivially — and writing it as a special
+	case would be the first line of a version of this function that treats the Aswang differently,
+	which is the shape `.claude/lessons/absence-is-observable.md` is about.
+]]
+local function sendSmokeBurst(centre: Vector3)
+	local payload: Types.SmokeBurstPayload = {
+		Position = centre,
+		Duration = Config.Monster.SmokeDuration,
+		Radius = Config.Monster.SmokeRadius,
+	}
+
+	for _, witness in Players:GetPlayers() do
+		local character = witness.Character
+		local root = if character ~= nil then rootOf(character) else nil
+
+		if root ~= nil and (root.Position - centre).Magnitude <= Config.Monster.SmokeCueRadius then
+			smokeRemote:FireClient(witness, payload)
+		end
+	end
+end
```

`npm run build` is the check: this step completes the server half of the chunk, and `rojo build` proving
the whole tree assembles is the strongest single command available before a Studio session.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — three questions. (a) Is `SmokeBurst` fired with `FireClient` in a distance-gated
  loop, with no `FireAllClients` anywhere? (b) Does a **non-Aswang** firing either remote receive
  anything at all? It must not — a verdict on the wire for a player who is not the monster is a free
  role oracle for anyone willing to spam. (c) Does `CamouflageUpdate` carry a charge count or a reveal
  flag? It must carry a verdict and an optional form.
- **Remote direction** — two `OnServerEvent` handlers on `EVENTS_UP` names; two `FireClient` sites on
  `EVENTS_DOWN` names. `check:remotes` catches the crossed version.
- **Rate limiting** — both handlers consult `AntiCheatService.Consume` as their **first** statement, at
  the connect site, within the 1200-character window the tripwire scans.
- **Magic numbers** — `SmokeCueRadius`, `SmokeRadius`, `SmokeDuration`, `SmokeCooldown` and
  `CamouflageWitnessRadius` all read from `Config`. The lazy expiry sweep must not hardcode a slack.
- **Phase ownership** — both validators read `RoundService.GetPhase()` and pass it into a pure module.
  Neither sets one.
- **Player leaving mid-round** — a burst outlives its planter deliberately (the cloud is a thing in the
  world). Confirm nothing in the burst table holds a Player, so a departure leaks nothing.
- **Strict Luau** — `rootOf` returns `BasePart?` and the `if character ~= nil then ... else nil`
  expression needs its nil branch; `Config.Monster.SmokeDuration` is a number and the payload field is
  typed, so a Config restructure surfaces here rather than at runtime.
- **Mobile budget** — no particles yet; Phase 6 spends them. The send loop is O(players) once per
  burst, at most once per 45 seconds per Aswang.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **`isUnwitnessed` will refuse most hides in a busy barrio, and that is intended but untested.**
  `CamouflageWitnessRadius = 12` against a five-player lobby in a small map may make camouflage
  effectively unusable. It is a Config number and V16's job, but the playtester should be asked to
  report how often `CAMO_WITNESSED` appears — it is the most likely reason this feature reads as broken
  rather than as gated.
- **A camouflaged Aswang inside its own smoke cannot be killed *by* anything and cannot kill.** Two
  abilities stacking is not obviously wrong, but nothing in §4.3 discusses it. Flagged in Follow Ups.
- **The lazy expiry sweep runs inside `hasLineOfSight`, which is on the kill path.** Confirm the sweep
  is a back-to-front loop with `table.remove` and not an allocation per call; the kill path is not hot,
  but the throw path is called per throw per target.

---

### Phase 6: What the two abilities look like

#### Step 6.1: Create `SmokeController`

**File:** `src/client/Controllers/SmokeController.luau`
**Verify:** `test -f src/client/Controllers/SmokeController.luau`

One controller for both of this chunk's down-remotes. **It owns no truth** — the server has already
decided that the cloud exists, that it blocks a kill, and that this player may hide; this file draws
the consequences.

```diff
+--!strict
+--[[
+	SmokeController — the cloud, and the one line the Aswang reads about its own disguise. (V07, §4.3)
+
+	OWNS NO TRUTH, and here that is a security property rather than a slogan. The smoke's line-of-sight
+	break is resolved on the SERVER — `MonsterService.SmokeBlocks` over `pure/CamouflageRules
+	.smokeBlocks`, consulted by the kill path and the throw path — so a player who deletes this
+	emitter, drops to minimum graphics, or never receives the payload plays under exactly the same
+	rules as everyone else. The particles are what the decision LOOKS like, never what makes it.
+
+	IT DRAWS A CLOUD FOR EVERYONE WHO RECEIVES ONE, AND THE SERVER DECIDES WHO THAT IS. There is no
+	distance filter in this file and there must not be: a client-side filter would mean every client
+	received every burst, which is the live monster-position feed `Remotes.luau` refuses.
+
+	THE CAMOUFLAGE HALF IS ONE PLAYER'S, LIKE `FeedController`'S FEED. Every client loads this file and
+	connects the handler; four of five never receive a `CamouflageUpdate`, so the branch never runs, and
+	nothing about that is observable to anyone but themselves. The asymmetry that WOULD leak is on the
+	server side and there is none — `CamouflageUpdate` is FireClient to the requester, never a
+	broadcast, so no client can time or count another's hides.
+
+	NO HUD AND NO CHARGE METER, EVEN FOR THE ASWANG. §4.6's rule that "a health value attached to a
+	player is the reveal" generalises: the moment a charge counter exists on screen, a screen recording
+	of an Aswang's client is a document of the camouflage system, and a streamer's overlay is a
+	permanent one. The feedback is `OnboardingController.ShowLine`, which `SearchController`,
+	`FeedController` and `TeachingService` all already use this way.
+]]
```

The rest is small: a `SmokeBurst` handler that builds a `ParticleEmitter` on an anchored, non-collidable
part at `payload.Position`, emits, and `Destroy`s after `payload.Duration`; a `CamouflageUpdate` handler
that maps each verdict to one line; and `Init`/`Start` in the standard shape.

**`Duration` and `Radius` come from the payload, not from `Config`.** The server is the authority on how
long *its* burst lasts, and a client computing the lifetime from replicated Config would draw a stale
cloud after a Config change the server had already applied.

#### Step 6.2: Register it in the client bootstrap

**File:** `src/client/init.client.luau`
**Verify:** `npm run analyze`

`CONTROLLER_ORDER` is a list of names and the ordering rule in it is real: **after
`OnboardingController`, before `InputController`.** The first is a genuine dependency — this controller
requires it for `ShowLine`, one-way, exactly as `SearchController` and `FeedController` do, so the arrow
cannot become a cycle. The second is the rule everything in that list follows: a controller listening
for a remote that can arrive the instant a key is pressed must be connected before the key can be
pressed.

#### Step 6.3: Bind the two verbs

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run check:remotes`

Two `ContextActionService` bindings beside the four that exist (`T` transform, `F` kill, `Q` throw,
`E` search), and two entries in the `UIController.BindActions` table so C27's touch buttons exist on a
phone. **The keys are new and unclaimed:** `C` for camouflage, `G` for smoke — neither collides with the
four bound today.

```diff
+	ContextActionService:BindAction(CAMOUFLAGE_ACTION, onCamouflageAction, false, Enum.KeyCode.C)
+	ContextActionService:BindAction(SMOKE_ACTION, onSmokeAction, false, Enum.KeyCode.G)
```

Both handlers are one line — `Remotes.Get("RequestCamouflage"):FireServer()` and the same for
`RequestSmoke` — with no arguments, no local validation and no state. **The client must not hide the
buttons for a survivor.** A button that only the Aswang can see IS the reveal, on the monster's own
screen where a stream captures it; both verbs are bound for every player, every round, and the server
silently ignores a survivor who presses them (Step 5.1). This is the same reasoning that keeps
`RequestTransform` bound for everyone.

#### Step 6.4: Draw the camouflage feedback the Aswang alone receives

**File:** `src/client/Controllers/SmokeController.luau`
**Verify:** `npm run fmt:check`

One `ShowLine` per verdict, and the copy is the deliverable. `CAMO_OK` names the form ("You are a
pig."); `CAMO_EXITED` says "You step out."; `CAMO_NOT_REVEALED` has to explain a rule the player has
never been told, so it says what unlocks it rather than what refused ("They have to see you first.");
`CAMO_NO_CHARGE` points at the loop §4.3 built ("You need to feed again."); `CAMO_WITNESSED` names the
fixable condition ("Someone is watching."). `CAMO_WRONG_PHASE`, `CAMO_ALREADY` and `CAMO_NOT_TRANSFORMED`
share one line — they are states the player can see for themselves.

**`CAMO_NO_SLOT` is the interesting one.** "There is nothing left to hide as" tells the Aswang something
true about the world; it is safe because it is fired to the requester alone about its own refused
action, and because the ambient population is visible to everyone anyway.

`fmt:check` is the verify because this step is copy and its failure mode is a line over 100 columns.

#### Step 6.5: Spend the particle budget

**File:** `src/client/Controllers/SmokeController.luau`

Emitter rate, lifetime and count against §5's mobile budget. **No verify line** — this is a look, and a
check over it would always pass. `verify-plan` reports it as `unverifiable` and `next-phase.mjs` marks
the phase `needs-human`, which is the accurate outcome: somebody has to stand in the cloud on a phone.

What to spend and what not to: **one emitter, no light.** §5's budget is about lights and particles and
`PerformanceController` already enforces the light cap; a `PointLight` inside the smoke would be the
cheapest-looking and most expensive thing available. A single emitter with a burst `:Emit(n)` rather
than a sustained `Rate`, `LightEmission = 0`, and the part `Destroy`ed on expiry so nothing accumulates
across a round.

**One Roblox behaviour is deliberately not depended on:** whether a `ParticleEmitter` visually occludes
anything is not a question this plan answers, because the mechanic never asks it — the server has
already decided (Steps 5.3, 5.4). If the cloud turns out to be visually thin, that is a texture and
density problem with no gameplay consequence. Recorded in Follow Ups.

#### Step 6.6: The whole gate

**File:** `src/client/Controllers/SmokeController.luau`
**Verify:** `npm run verify`

The full gate — analyze, lint, format, the five checks, the tests and the harness — over the finished
chunk. This is the last mechanical step; everything after it needs a person in Studio.

#### Phase 6 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the client-side questions. (a) Are both input bindings created for **every**
  player, with no role branch? A button that appears only for the Aswang is the reveal, on the
  monster's own screen. (b) Does `SmokeController` filter bursts by distance locally? It must not —
  that would mean the server broadcast them. (c) Does any verdict line name another player?
- **Remote direction** — `OnClientEvent` on the two down-remotes, `FireServer` on the two up-remotes.
  Reversed, `check:remotes` catches it; unreversed but undeclared, the client `WaitForChild` hangs
  forever with no error.
- **Rate limiting** — client-side, none applies. Confirm `InputController` does not add a local
  cooldown that would mask a server refusal and make the two disagree.
- **Magic numbers** — emitter rate, lifetime, size and the `:Emit` count belong in `Config` if they are
  balance and may carry a `-- config-ok:` waiver with a reason if they are genuinely presentation.
  `SkyController`'s Color3 channel waivers are the precedent for the shape.
- **Phase ownership** — the client reads a phase and never sets one.
- **Player leaving mid-round** — a cloud whose planter left still expires on its own timer, because the
  lifetime came down in the payload rather than being tied to a player.
- **Strict Luau** — `Types.SmokeBurstPayload` and `Types.CamouflageUpdatePayload` are the handler
  signatures. An untyped `payload` parameter infers `any` and every field access silently stops being
  checked, which is how a renamed field ships.
- **Mobile budget** — Step 6.5, and it is the one thing in this phase a person has to look at.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **`C` and `G` are unclaimed today but `UIController` owns the touch layer.** Confirm the two new
  `BindActions` entries do not push the thumb-zone button count past what C27 laid out for a phone;
  six verbs on a small screen is where that layout starts to fight itself.
- **The `CAMO_NOT_REVEALED` line teaches a rule the game never otherwise states.** That is correct and
  it is also the only place a player learns the gate exists. Worth asking the playtester whether it
  reads as a rule or as a bug.

---

## 3. Related Files

**Created by this plan:**

| File | Phase | What it is |
| --- | --- | --- |
| `src/shared/pure/CamouflageRules.luau` | 1 | The gate, the two transition tables, the smoke gate, the segment/sphere test |
| `tests/camouflage-rules.test.luau` | 1 | The four-input grid, with the pre-reveal half universally denied |
| `src/shared/pure/AmbientRoster.luau` | 3 | Slot claim/release, and head-count invariance as arithmetic |
| `tests/ambient-roster.test.luau` | 3 | Swap-not-spawn, over the whole roster space |
| `src/server/Services/AmbientService.luau` | 3 | The population, the wander, the claim seam, the map contract |
| `src/client/Controllers/SmokeController.luau` | 6 | The cloud and the Aswang's own one-line feedback |

**Edited by this plan:**

| File | Phase | Why |
| --- | --- | --- |
| `src/shared/Config.luau` | 2 | Four camouflage/smoke tunables and the `Ambient` block. `SmokeDuration`/`SmokeRadius` already exist at :346-347 |
| `src/shared/Remotes.luau` | 2 | Two up, two down |
| `src/shared/Types.luau` | 2 | `CamouflageUpdatePayload`, `CamouflageVerdict`, `SmokeBurstPayload`. **`ClientRoundSnapshot` untouched** |
| `tests/anti-cheat-budgets.test.luau` | 2 | The hand copy of `EVENTS_UP`, which must move with the budgets |
| `tests/config.test.luau` | 2 | Three new silent invariants |
| `src/server/Services/MonsterService.luau` | 4, 5 | Six state fields, the single reveal setter, the charge listener, enter/exit, five edge cases, two handlers, the smoke field |
| `src/server/init.server.luau` | 3 | `AmbientService` before `MonsterService` |
| `src/server/Services/ItemService.luau` | 5 | A throw through smoke resolves as the existing collapsed `MISS` |
| `src/client/init.client.luau` | 6 | `SmokeController` after `OnboardingController`, before `InputController` |
| `src/client/Controllers/InputController.luau` | 6 | Two bindings, bound for every player |

**Read while planning, reviewed in `references/`:** `MonsterService.luau`, `FeedRules.luau`,
`Remotes.luau`, `Config.luau`, `Types.luau`, `Enums.luau`.

**Read and deliberately not changed:** `RoundService.luau` (owns the phase; this chunk subscribes and
never sets), `AntiCheatService.luau` (the two budgets are Config entries; the service needs no edit),
`FeedController.luau` (its "once V07 lands" comment describes a line it does not have to change).

---

## 4. Follow Ups

### Questions / Clarifications

**Q1 — V07 owns the reveal setter, not V08. Confirm the build plan is read this way.**
The V08 entry says salt "sets `hasBeenRevealed` (the V07 gate)", which reads as a deferral. This plan
sets it in V07, at `MonsterService.ApplySaltHit` — the function `ItemService.applyHit` already calls and
which V08's `ItemCarry`/`ItemThrow` rework does not move. Step 4.2 carries the full argument; the short
version is that a gate with no setter cannot be playtested, and the fail-closed property comes from the
pure module rather than from the setter's absence. **V08 then has nothing to add for this line**, and
its plan should say so rather than adding a second writer.

**Q2 — Smoke is gated on `HasBeenRevealed` too. This is a design decision, not a spec reading.**
§4.3 frames smoke entirely as the answer to a salt hit, so the gate costs the mechanic nothing — you are
revealed exactly when you want it. What it buys is that an unrevealed Aswang cannot plant a cloud on its
own head in a crowd, and that **both abilities in this chunk live behind one flag with one setter**. The
cost is a use the spec never named: smoke to break a chase before ever being salted. **A V16 balance
question.**

**Q3 — `Config.Monster.SmokeCooldown = 45` and `CamouflageWitnessRadius = 12` are invented numbers.**
§6.5's Config block specifies `SmokeDuration` and `SmokeRadius` and nothing else for either ability.
Both new numbers are first guesses with a stated relationship behind them (the witness radius must
exceed `KillRange`; the cooldown must be long enough that smoke is a decision). They are the two most
likely things V16 retunes.

**Q4 — Camouflage plus smoke stacking is not discussed anywhere in the spec.**
A camouflaged Aswang standing inside its own live cloud cannot be hit by a throw and cannot kill. That
may be fine, or it may be the combination that makes the monster unkillable in the hands of a good
player. Nothing in this plan prevents it; the playtester should be asked to try it deliberately.

**Q5 — Roblox behaviours this plan has NOT verified, and does not depend on.**
Three, named rather than assumed. (a) **Whether a `ParticleEmitter` visually occludes anything** — the
mechanic never asks, because the server decides line of sight before any particle exists. If the cloud
looks thin, that is a texture problem with no gameplay consequence. (b) **`PathfindingService`'s cost at
16 simultaneous agents** — which is why the ambient entities are anchored Models stepped by one server
loop rather than Humanoids with paths. (c) **How a server-moved anchored Model behaves under
`StreamingEnabled`** — it should stream in at its current position rather than mid-walk, which is
cosmetic; `PerformanceController` already reacts to streaming and is where to look.

**Q6 — The map work is a human step and it is the only one.**
Sixteen `AmbientSpawn`-tagged invisible parts, spread across the bahay kubo, the chapel and the well
area. Until they exist the fallback ring runs, which is scaffolding rather than a design. The place file
is gitignored and its only backup is Roblox's cloud version history — **publish after placing them.**

**Q7 — `Enums.MonsterState`'s deferred question is answered here, and the answer should be recorded.**
`Enums.luau:62-72` says "whether this is one field or a field plus a flag is that chunk's decision".
This chunk chose **a field plus a flag**, matching V06's `Feeding`. That comment can now be updated to
say so rather than deferring — a small edit worth making in whichever chunk next touches `Enums.luau`.

**Q8 — The audit brief for this chunk, pre-scoped.**
The build plan names three questions for `exploit-auditor` and this plan adds the files and phases:
(1) *can camouflage fire before a reveal by any path* — Phases 1 and 4, `CamouflageRules.evaluate` and
the single setter in `ApplySaltHit`; (2) *does the ambient population count change when it fires* —
Phases 3 and 4, `AmbientRoster` plus **all five exits** reaching `ReleaseSlot`; (3) *is the charge state
readable by a non-Aswang client* — Phases 2, 5 and 6, the two payloads and the input bindings.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 4 | `enterCamouflage`'s capture guard: a character reaching it with `Applied` false and a look already on it would record the monster's colours as the originals and brand the player on revert — C04's bug with a longer fuse | High | Open — audit in Phase 4 |
| 4 | Five exits, one entry. `AmbientRoster` proves the arithmetic; only a reader can prove every exit reaches `ReleaseSlot`. A leaked slot is silent and cumulative | High | Open — `exploit-auditor` Q2 |
| 4 | `exitCamouflage` calls `applyFullLook`, which may re-create tracked effects; a hide/unhide cycle could leave two emitters on one character | Medium | Open |
| 5 | `isUnwitnessed` at radius 12 may refuse most hides in a five-player barrio, reading as broken rather than gated | Medium | Open — playtest question |
| 5 | Camouflage and smoke stacking is undiscussed in the spec (Q4) | Medium | Open |
| 2 | `SmokeCueRadius` being raised past visual range would retire the "exact position is safe" reasoning and require quantising to `Config.Noise.CueGridStuds` | Low | Documented at the Config value and the send site |
| 3 | The fallback spawn ring is scaffolding, not a map. It fires only on **zero** tagged points, never on "fewer than we wanted" | Low | By design — Q6 |
| 1 | `smokeBlocks`'s NaN guard fails towards "does not block", which is the safe direction and therefore an invisible bug if its polarity is ever reversed | Low | Tested in Phase 1 |
