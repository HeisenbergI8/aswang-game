# Plan: V05 — Monster Health, Exposed and Weakened

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V05 (`docs/BUILD-PLAN.md` line ~247) — "MonsterService: health, Exposed, Weakened"
- **Description:** Give the Aswang the 100-health tug-of-war from spec §4.6. Salt takes 25 and can
  never take it below `WeakenedThreshold`; feeding gives 25 back (V06 calls the seam, V05 does not
  build feeding). `Exposed` becomes a real server-side latch owned by `MonsterService` rather than a
  Highlight owned by `ItemService`, and the glow brightens as health falls — which is the entire
  presentation, because §4.6 forbids a health bar.
- **Date:** 2026-08-27
- **What the client is told:** **nothing new.** No remote is added, removed or changed. No field is
  added to `ClientRoundSnapshot`. The only thing that crosses the wire is a property change on a
  `Highlight` instance that `ItemService` already created on exactly the same players at exactly the
  same moments — its `FillTransparency` now moves. Health itself never leaves the server, never
  touches `Humanoid.Health` or `Humanoid.MaxHealth`, never becomes an attribute or a tag.

---

### Preamble — read this with every phase

Four things bind every step below. They are repeated inside the phases that need them, because
`npm run plan:phase` hands out one phase at a time and a constraint stated only here does not exist
for whoever implements Phase 4.

**1. `Humanoid.Health` and `Humanoid.MaxHealth` are replicated properties, and they are the trap this
chunk is built around.** "The Aswang has 100 health" reads as an instruction to set
`humanoid.MaxHealth = Config.Monster.MaxHealth`. Do that and any client polls every character in
`workspace`, finds the one whose Health reads 75 while four others read 100, and knows the monster —
permanently, for free, with no remote to intercept and nothing for `check:secrecy` to see. This is
`.claude/lessons/absence-is-observable.md` in its exact shape: the leak is a **difference between
players**, not a piece of data. V05's health is a number in a server-side Lua table keyed by UserId
and it is nowhere else.

**2. The same rule kills the obvious flavour instinct.** A weakened monster that moves slower, breathes
louder, glows dimmer when *not* Exposed, or gets any per-player cue is branded. `ItemService`'s
`applyHit` header (line ~484) records that this repo already shipped exactly that bug once — a
transformed WalkSpeed of 20 surviving a revert and persisting across rounds, readable map-wide, with
`verify` and `check:secrecy` green over it. The invariant it wrote is inherited here verbatim: **no
path added by V05 may leave a living player's `Humanoid` properties different from every other living
player's.**

**3. The floor is the mechanic, not a clamp.** §4.6: salt is floored at `WeakenedThreshold`, so salt
alone can never kill and the buntot pagi is the only thing that does. The floor applies to **salt**,
not to health generally — nothing in V05 reduces health by any other route, but the pure module is
written so the floor belongs to the salt event rather than to the state, because V08's salt and V06's
feed will both call it and only one of them is floored.

**4. `RoundService` owns the phase.** Nothing in this plan calls `setPhase`. `MonsterService` already
subscribes via `RoundService.PhaseChanged.Event` (its `Start`, line ~1096) and V05 adds work to the
existing `onPhaseChanged`, never a second subscription.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The health model as a pure function

The whole decision — floor, heal, cap, and the `isWeakened` predicate — as a module over plain
tables, gated on a Lune grid rather than on a playtest nobody can run against ±inf.

#### Step 1.1: Create `src/shared/pure/MonsterHealth.luau`

**File:** `src/shared/pure/MonsterHealth.luau`
**Verify:** `test -f src/shared/pure/MonsterHealth.luau`

**This check only proves the file landed, and that is deliberate.** The module's real proof is Step
1.2's grid, which cannot run without it; a `grep` for a function name here would prove authorship and
nothing else. `analyze` is spent on Phase 4, where the strict-Luau risk actually is.

Three exports — `apply`, `isWeakened`, `weakenedFraction` — over a `Tuning` table the caller
assembles from `Config.Monster` and `Config.Items`. Scalar returns only, no `script.Parent` requires.

**Why the signature is what it is.** `.claude/lessons/pure-module-unions-widen-in-lists.md`: a
literal union survives `require` as a **scalar** and does not survive it inside a **list** — the
element arrives as a union of plain `string`s, `::` cannot narrow it back, and the analyzer reports
the failure at the call site in the wrong file. `apply` returns a `number` and `isWeakened` returns a
`boolean`, so there is no list of literals anywhere in this module and the failure has no surface
here. The `event` parameter is typed plain `string` rather than `HealthEvent`, exactly as
`NoiseModel.evaluate(action: string, ...)` is: an unrecognised id is then a normal call with a normal
answer — health unchanged — instead of a type error at a call site that got its id from a table.

**Why `Tuning` is assembled by the caller rather than being `Config.Monster`.** `NoiseModel` can take
`Config.Noise` whole because every number it needs lives in that block. Health's four numbers do not:
`MaxHealth`, `WeakenedThreshold` and `FeedHeal` are under `Config.Monster`, and `SaltDamage` is under
`Config.Items` (§6.5's canonical item block, where V02 put it). A `Request`/`Tuning` table built at
the call site is this repo's dominant pure-module idiom anyway — `SaltThrow.Request`,
`KillValidation.Request`, `TransformRules.Request` all do it.

```diff
+--!strict
+--[[
+	MonsterHealth — the tug-of-war, as arithmetic. (V05, §4.6)
+
+		apply(health, event, tuning) -> health'
+		isWeakened(health, tuning) -> boolean
+		weakenedFraction(health, tuning) -> 0..1
+
+	§4.6: "the survivors' progress toward killing it and the Aswang's progress toward killing them
+	are the same resource, pulling in opposite directions." This module is that resource and nothing
+	else. It owns no player, no clock, no Instance, and no decision about WHETHER a salt hit landed —
+	`ItemService` decides that (V08) and `MonsterService` owns the number between calls.
+
+	WHY `src/shared/pure/` IS SAFE HERE, which V03 answered the other way. The rule is about INPUTS.
+	`ContainerLayout` is a DRAW: a client that can guess its seed knows where the buntot pagi is
+	before the round starts, so it lives in `server/pure/`. This is a subtraction and a comparison
+	over four numbers `Config.luau` already replicates to every client. A client that requires this
+	module learns that salt takes 25 and stops at 25 — which §10's FTUE is going to TELL it in the
+	tutorial. Logic is not secret; inputs are, and this module has no input a client supplies.
+
+	WHAT IT DELIBERATELY DOES NOT CONTAIN: any notion of who the health belongs to. There is no
+	player, no UserId and no role in the signature, so there is no arrangement of this module in
+	which the health of one player is distinguishable from the health of another. That is structural
+	rather than careful — `.claude/lessons/absence-is-observable.md` is the long version.
+
+	THE FLOOR BELONGS TO THE SALT EVENT, NOT TO THE STATE. §4.6: salt is floored at
+	WeakenedThreshold so that "salt alone can never kill" and the buntot pagi is the only thing that
+	does. A floor on the STATE would also silently floor a future damage source; a floor on the
+	EVENT means the next chunk that wants one has to ask for it in a diff.
+]]
+
+-- Re-declared rather than imported (no `script` under Lune). Luau unions are structural, so this
+-- and any matching union in `Types` are the same type and pass to each other without a cast.
+-- Exported for documentation and for a caller that wants to name an event; `apply` takes a plain
+-- `string` on purpose, so an id that came from a table is answered rather than rejected.
+export type HealthEvent = "SALT" | "FEED" | "NONE"
+
+export type Tuning = {
+	MaxHealth: number,
+	WeakenedThreshold: number,
+	SaltDamage: number,
+	FeedHeal: number,
+}
+
+local MonsterHealth = {}
+
+--[[
+	THE FLOOR, RESOLVED SAFELY. `math.min` rather than a bare read, so a Config typo that puts
+	WeakenedThreshold ABOVE MaxHealth produces a floor of MaxHealth — a monster permanently at the
+	floor — instead of an inverted clamp where `math.max(x - d, floor)` silently HEALS on a salt hit.
+	`tests/config.test.luau` pins the relationship (Step 2.3); this is the second line of defence.
+]]
+local function floorOf(tuning: Tuning): number
+	return math.min(tuning.WeakenedThreshold, tuning.MaxHealth)
+end
+
+--[[
+	NORMALISE A HEALTH VALUE INTO [floor, MaxHealth], INCLUDING THE VALUES THAT BREAK COMPARISONS.
+
+	NaN fails every comparison it is given, so `nan <= threshold` is FALSE and an unguarded
+	`isWeakened` would report a corrupted monster as NOT weakened — an Aswang that cannot be killed,
+	with no symptom except that the second win condition stopped existing. §6.5 invariant 1 is about
+	precisely that silence.
+
+	SO NaN AND -inf RESOLVE TO THE FLOOR, NOT TO FULL HEALTH, and that direction is chosen rather
+	than defaulted. Both failures are bad; one is loud. A corrupted monster at the floor glows at
+	full brightness and dies to the next buntot pagi, which somebody notices within one round. A
+	corrupted monster at MaxHealth is unkillable and looks exactly like a balance problem.
+]]
+local function normalise(health: number, tuning: Tuning): number
+	local floor = floorOf(tuning)
+
+	if health ~= health or health == -math.huge then
+		return floor
+	end
+
+	if health == math.huge then
+		return tuning.MaxHealth
+	end
+
+	return math.clamp(health, floor, tuning.MaxHealth)
+end
+
+-- A magnitude that cannot be negative and cannot be NaN. A negative SaltDamage would make salt heal
+-- the monster; a NaN one would poison the state on the first hit. Config is hand-edited during V16.
+local function magnitude(value: number): number
+	if value ~= value then
+		return 0
+	end
+
+	return math.max(value, 0)
+end
+
+--[[
+	APPLY ONE EVENT. Returns the new health; never mutates, never errors.
+
+	AN UNKNOWN EVENT RETURNS THE HEALTH UNCHANGED AND THAT IS FAILING CLOSED, the same way
+	`NoiseModel.evaluate` answers nil for an action id with no row. The unsafe direction here is a
+	free heal or a free hit for a string nobody defined.
+]]
+function MonsterHealth.apply(health: number, event: string, tuning: Tuning): number
+	local current = normalise(health, tuning)
+
+	if event == "SALT" then
+		-- THE FLOOR (§4.6). Salt alone must never kill, or the buntot pagi is decoration.
+		return math.max(current - magnitude(tuning.SaltDamage), floorOf(tuning))
+	end
+
+	if event == "FEED" then
+		return math.min(current + magnitude(tuning.FeedHeal), tuning.MaxHealth)
+	end
+
+	return current
+end
+
+-- §4.6: the buntot pagi kills an Aswang that is Exposed AND "at or below 25 health". `<=`, and the
+-- boundary is asserted in the test rather than left to a reader.
+function MonsterHealth.isWeakened(health: number, tuning: Tuning): boolean
+	return normalise(health, tuning) <= tuning.WeakenedThreshold
+end
+
+--[[
+	HOW FAR ALONG THE RAMP THIS HEALTH IS: 0 at full, 1 at the floor. `MonsterService` lerps the two
+	Config glow endpoints by it, so §4.6's "the glow gets brighter as it weakens" is one number here
+	rather than arithmetic in a service that `check:config` would flag.
+
+	A ZERO-WIDTH SPAN RETURNS 1 rather than dividing by it — same loud direction as `normalise`.
+]]
+function MonsterHealth.weakenedFraction(health: number, tuning: Tuning): number
+	local floor = floorOf(tuning)
+	local span = tuning.MaxHealth - floor
+
+	if span <= 0 or span ~= span then
+		return 1
+	end
+
+	return math.clamp((tuning.MaxHealth - normalise(health, tuning)) / span, 0, 1)
+end
+
+return MonsterHealth
```

#### Step 1.2: Create `tests/monster-health.test.luau` over the enumerated domain

**File:** `tests/monster-health.test.luau`
**Verify:** `lune run tests/monster-health.test.luau`

health ∈ {full, mid, at-floor, below-floor, 0, ±inf, NaN} × event ∈ {salt, feed, none, unknown}, plus
the four properties that matter: the floor holds, salt never kills, a feed never exceeds `MaxHealth`,
and `isWeakened` agrees with `apply` on every cell.

The build plan is explicit about the shape: *"enumerate the domain rather than writing a case per
bug… a pure predicate over a bounded domain earns a grid, and this repo has already paid four review
rounds for learning that the reactive way."* Match `tests/noise-model.test.luau`'s idiom exactly — a
`check(label, ok, detail)` counter, a **synthetic** tuning for the model's own rules so V16 can
retune `Config` without redding this file, and a short **cross-check** against the real block at the
bottom so a missing or renamed number is still caught.

```diff
+--!strict
+--[[
+	The Aswang's health, over its whole domain. (V05, §4.6)
+
+	The build plan asks for the health x event GRID rather than a case per bug, and the reason is the
+	one `noise-model` states: this is a small pure function over a BOUNDED domain, which is the one
+	shape where enumerating beats reacting. Seven health values against four events is 28 cells, and
+	the three properties that matter — the floor holds, a feed never overfills, and `isWeakened`
+	agrees with `apply` — are exactly the ones a playtest cannot see. A monster that cannot be
+	weakened has no symptom; it just never dies, and that reads as balance.
+]]
+
+local Config = require("../src/shared/Config")
+local MonsterHealth = require("../src/shared/pure/MonsterHealth")
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
+-- SYNTHETIC, not Config's. These assertions are about the MODEL's rules; V16 will retune Config and
+-- must not be able to red this file. The real block is cross-checked at the bottom.
+local TUNING = {
+	MaxHealth = 100,
+	WeakenedThreshold = 25,
+	SaltDamage = 25,
+	FeedHeal = 25,
+}
+
+-- Full, mid, at the floor, below it, zero, and the four values that break a naive comparison.
+local HEALTHS = { 100, 60, 25, 10, 0, -40, 0 / 0, math.huge, -math.huge }
+local EVENTS = { "SALT", "FEED", "NONE", "SHOUT", "" }
+
+print("MonsterHealth")
+
+--[[
+	THE GRID. Every health against every event, asserting the invariant that must hold across all of
+	it: the answer is always a finite number inside [WeakenedThreshold, MaxHealth]. Nothing in this
+	game reduces health below the floor, so a result outside that band is a bug wherever it came
+	from.
+]]
+for _, health in HEALTHS do
+	for _, event in EVENTS do
+		local result = MonsterHealth.apply(health, event, TUNING)
+
+		check(`{event} on {health}: not NaN`, result == result, `{result}`)
+		check(
+			`{event} on {health}: inside the band`,
+			result >= TUNING.WeakenedThreshold and result <= TUNING.MaxHealth,
+			`{result}`
+		)
+		check(
+			`{event} on {health}: isWeakened agrees with the band`,
+			MonsterHealth.isWeakened(result, TUNING) == (result <= TUNING.WeakenedThreshold),
+			`{result}`
+		)
+	end
+end
+
+--[[
+	THE FLOOR IS THE MECHANIC (§4.6). Salt alone must never kill, so no chain of salt hits of any
+	length reaches below WeakenedThreshold — asserted by iterating rather than by trusting one call,
+	because the failure mode is a floor that holds for one hit and drifts over many.
+]]
+local chained = TUNING.MaxHealth
+
+for hit = 1, 20 do
+	chained = MonsterHealth.apply(chained, "SALT", TUNING)
+
+	check(
+		`salt hit {hit} never breaks the floor`,
+		chained >= TUNING.WeakenedThreshold,
+		`{chained}`
+	)
+	check(`salt hit {hit} never kills`, chained > 0, `{chained}`)
+end
+
+check("twenty salt hits land exactly on the floor", chained == TUNING.WeakenedThreshold, `{chained}`)
+
+-- §4.6's table, at the shipped shape: three hits reach the floor and the third is the one that
+-- makes it killable. This is the survivors' path to the second win condition, spelled out.
+local after1 = MonsterHealth.apply(TUNING.MaxHealth, "SALT", TUNING)
+local after2 = MonsterHealth.apply(after1, "SALT", TUNING)
+local after3 = MonsterHealth.apply(after2, "SALT", TUNING)
+
+check("one salt hit does not weaken", not MonsterHealth.isWeakened(after1, TUNING), `{after1}`)
+check("two salt hits do not weaken", not MonsterHealth.isWeakened(after2, TUNING), `{after2}`)
+check("three salt hits weaken", MonsterHealth.isWeakened(after3, TUNING), `{after3}`)
+
+-- THE TUG-OF-WAR (§4.6): "every kill the Aswang makes heals away one salt hit."
+check(
+	"a feed undoes exactly one salt hit",
+	MonsterHealth.apply(after3, "FEED", TUNING) == after2,
+	`{MonsterHealth.apply(after3, "FEED", TUNING)} vs {after2}`
+)
+
+local overfed = MonsterHealth.apply(TUNING.MaxHealth, "FEED", TUNING)
+
+check("a feed at full health does not overfill", overfed == TUNING.MaxHealth, `{overfed}`)
+
+-- THE BOUNDARY. §4.6 says "at or below 25 health", so the threshold itself is weakened.
+check("the threshold itself is weakened", MonsterHealth.isWeakened(25, TUNING))
+check("one point above the threshold is not", not MonsterHealth.isWeakened(25.1, TUNING))
+check("full health is not weakened", not MonsterHealth.isWeakened(TUNING.MaxHealth, TUNING))
+
+--[[
+	THE DEGENERATE INPUTS, ASSERTED IN THE LOUD DIRECTION. NaN fails every comparison, so an
+	unguarded `isWeakened` reports a corrupted monster as NOT weakened — unkillable, silently. The
+	module resolves NaN and -inf to the floor precisely so the failure is visible instead.
+]]
+check("NaN health is weakened, not immortal", MonsterHealth.isWeakened(0 / 0, TUNING))
+check("-inf health is weakened", MonsterHealth.isWeakened(-math.huge, TUNING))
+check("below the floor reads as weakened", MonsterHealth.isWeakened(-40, TUNING))
+check("+inf health is not weakened", not MonsterHealth.isWeakened(math.huge, TUNING))
+
+-- FAILS CLOSED. An event id with no rule changes nothing, rather than healing or hitting.
+check("an unknown event is a no-op", MonsterHealth.apply(60, "SHOUT", TUNING) == 60)
+check("an empty event is a no-op", MonsterHealth.apply(60, "", TUNING) == 60)
+check("NONE is a no-op", MonsterHealth.apply(60, "NONE", TUNING) == 60)
+
+--[[
+	A TUNING NOBODY WOULD WRITE ON PURPOSE BUT V16 COULD TYPO. A negative SaltDamage must not heal,
+	and a threshold above MaxHealth must not invert the clamp into a heal-on-hit.
+]]
+local perverse = { MaxHealth = 100, WeakenedThreshold = 25, SaltDamage = -50, FeedHeal = 0 / 0 }
+
+check(
+	"a negative SaltDamage does not heal",
+	MonsterHealth.apply(50, "SALT", perverse) == 50,
+	`{MonsterHealth.apply(50, "SALT", perverse)}`
+)
+check(
+	"a NaN FeedHeal does not poison the state",
+	MonsterHealth.apply(50, "FEED", perverse) == 50,
+	`{MonsterHealth.apply(50, "FEED", perverse)}`
+)
+
+local inverted = { MaxHealth = 50, WeakenedThreshold = 90, SaltDamage = 25, FeedHeal = 25 }
+local invertedResult = MonsterHealth.apply(50, "SALT", inverted)
+
+check("an inverted threshold does not heal on a hit", invertedResult <= 50, `{invertedResult}`)
+check("an inverted threshold reads as weakened", MonsterHealth.isWeakened(50, inverted))
+
+--[[
+	THE RAMP. `MonsterService` lerps the two glow endpoints by this, so its monotonicity IS the
+	presentation: §4.6's "the glow gets brighter as it weakens" is false the moment this stops
+	increasing as health falls, and nothing in the game would report it.
+]]
+check("full health is 0 along the ramp", MonsterHealth.weakenedFraction(100, TUNING) == 0)
+check("the floor is 1 along the ramp", MonsterHealth.weakenedFraction(25, TUNING) == 1)
+
+local previous = -1
+
+for health = 100, 25, -5 do
+	local fraction = MonsterHealth.weakenedFraction(health, TUNING)
+
+	check(`the ramp at {health} is in 0..1`, fraction >= 0 and fraction <= 1, `{fraction}`)
+	check(`the ramp at {health} did not go backwards`, fraction > previous, `{fraction}`)
+
+	previous = fraction
+end
+
+for _, health in HEALTHS do
+	local fraction = MonsterHealth.weakenedFraction(health, TUNING)
+
+	check(`the ramp survives {health}`, fraction == fraction and fraction >= 0 and fraction <= 1)
+end
+
+-- A zero-width span returns 1 rather than dividing by it.
+local flat = { MaxHealth = 25, WeakenedThreshold = 25, SaltDamage = 25, FeedHeal = 25 }
+
+check("a zero-width ramp answers 1", MonsterHealth.weakenedFraction(25, flat) == 1)
+
+--[[
+	THE CROSS-CHECK. Everything above runs on a synthetic tuning so V16 can retune freely — but a
+	RENAMED OR MISSING number in the real block would then go unnoticed until a live salt hit did
+	nothing, which is a silent failure whose only symptom is that the game got harder.
+
+	The balance RELATIONSHIP (§6.5 invariant 1) is pinned in `tests/config.test.luau` where every
+	other balance invariant lives, not here.
+]]
+local live = {
+	MaxHealth = Config.Monster.MaxHealth,
+	WeakenedThreshold = Config.Monster.WeakenedThreshold,
+	SaltDamage = Config.Items.SaltDamage,
+	FeedHeal = Config.Monster.FeedHeal,
+}
+
+check(
+	"Config's salt actually removes health",
+	MonsterHealth.apply(live.MaxHealth, "SALT", live) < live.MaxHealth
+)
+check(
+	"Config's feed actually restores health",
+	MonsterHealth.apply(live.WeakenedThreshold, "FEED", live) > live.WeakenedThreshold
+)
+check("Config's full health is not weakened", not MonsterHealth.isWeakened(live.MaxHealth, live))
+check(
+	"Config's floor is weakened",
+	MonsterHealth.isWeakened(MonsterHealth.apply(live.WeakenedThreshold, "SALT", live), live)
+)
+
+print(`  {checked - failures}/{checked} checks passed`)
+
+if failures > 0 then
+	error(`{failures} MonsterHealth check(s) failed`, 0)
+end
```

#### Step 1.3: Format both new files to `stylua.toml`

**File:** `tests/monster-health.test.luau`
**Verify:** `npm run fmt:check`

**No diff — run `npm run fmt` and then the check.** StyLua silently reformats a 100-column violation
on `fmt` and reds the gate on `fmt:check`, and two brand-new files with long comment blocks and long
interpolated `check` labels are exactly where that bites. This is a real gate rather than a
formality: `fmt:check` is inside `npm run verify`, so an unformatted file here blocks every later
phase's gate for a reason that has nothing to do with the phase that is failing.

Run `npm run test:unit` by hand at the same time to confirm the runner globs the new suite and that
no existing suite reds. Its own gate is Step 2.2.

---

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing here touches an Instance, but see the preamble: `src/shared/pure/` is
  requirable AND callable by any client, so ask whether the module publishes an input rather than a
  rule.
- **Remote direction** — n/a, no remote in this phase.
- **Rate limiting** — n/a, no handler in this phase.
- **Magic numbers** — `check:config` does not govern `src/shared/`, which is not licence: every
  balance number still arrives through `Tuning`.
- **Phase ownership** — n/a.
- **Player leaving mid-round** — n/a; the module has no player.
- **Strict Luau** — the lesson `pure-module-unions-widen-in-lists` decides the signature.
- **Mobile budget** — n/a.
- **Scope** — n/a.

**Issues identified:**

- **`Config.Items.SaltDamage`, not `Config.Salt.SaltDamage`.** V02 moved the four salt tunables into
  `Config.Items` and left `Config.Salt` as a set of aliases (`Config.luau:339-341`,
  `tests/config.test.luau:96-110`). The cross-check at the bottom of the test reads
  `Config.Items.SaltDamage`; reading it through the alias would still pass today and would break on
  the chunk that deletes the aliases.
- **`math.clamp` with an inverted range errors under Luau.** `normalise` calls
  `math.clamp(health, floor, MaxHealth)` and `floorOf` uses `math.min` specifically so `floor` can
  never exceed `MaxHealth`. Do not "simplify" `floorOf` to a bare `tuning.WeakenedThreshold`.
- **The module is client-callable.** `src/shared` maps wholesale into `ReplicatedStorage`, so a
  LocalScript can `require` and run this. That is fine here and the header says why — but if a later
  chunk wants a per-round or per-player input in `Tuning`, the module moves to `src/server/pure/` and
  the test's require path moves with it. Lune resolves by file path and cares nothing for Rojo.

---

### Phase 2: Config, and the invariant that goes silent

V02 already put `MaxHealth`, `WeakenedThreshold`, `FeedHeal`, `SaltDamage` and `SaltRevealDuration`
in `Config.luau`. What is missing is the glow ramp's two endpoints and — more importantly — §6.5
invariant 1, which is written in three comments in this repo and asserted in none.

#### Step 2.1: Add the two Exposed-glow endpoints, and pin the ramp's direction

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

**One step, two files, because neither half can be checked alone.** The Config addition on its own
has nothing that can fail — `check:config` does not look at `Config.luau`, and no reader exists until
Phase 4. The pins on their own red the suite, because the fields they read are `nil`. Landed
together, `lune run tests/config.test.luau` discriminates in both directions: it fails if the numbers
are missing (`nil < nil` errors) and it fails if they are inverted.

`ExposedGlowTransparencyFull` and `ExposedGlowTransparencyWeakened`, replacing `ItemService`'s
hardcoded `FillTransparency = 0.6` and its `config-ok` waiver.

**Why these two live under `Monster` and not next to `Salt.RevealGlow*Rgb` (`Config.luau:391-392`).**
The colours belong to salt — salt is what paints the glow. The **ramp** is a function of the
monster's health, so it moves whenever `MaxHealth` or `WeakenedThreshold` moves, and a tuner reading
§4.6's health block needs to see it there. That split is deliberate and is written into the comment
so the next reader does not "tidy" them together.

```diff
 		MaxHealth = 100,
 		WeakenedThreshold = 25,
 
+		--[[
+			THE EXPOSED GLOW'S RAMP (§4.6) — "the glow gets brighter as it weakens", and this is the
+			whole presentation of the health system. §4.6 is explicit that there is no UI: "a health
+			value attached to a player is the reveal", so the number is never drawn, never sent, and
+			never attached to anything. It is READ OFF THE BRIGHTNESS by whoever is standing there,
+			during the ten seconds the monster is Exposed and not one second longer.
+
+			TRANSPARENCY, SO LOWER IS BRIGHTER. Full lerps to Weakened as `MonsterHealth
+			.weakenedFraction` goes 0 -> 1. `tests/config.test.luau` pins Weakened BELOW Full,
+			because inverting these two is a one-character edit that makes a dying monster fade —
+			exactly backwards, entirely silent, and only findable by playing it.
+
+			THE COLOURS ARE NOT HERE. `Salt.RevealGlowFillRgb`/`OutlineRgb` stay where they are: the
+			colour belongs to the item that paints the glow, the RAMP belongs to the health it reads.
+			Do not merge them — a tuner opening this block is tuning health, not salt.
+		]]
+		ExposedGlowTransparencyFull = 0.75,
+		ExposedGlowTransparencyWeakened = 0.25,
+
 		--[[
 			FEEDING (§4.3) — WHAT REPLACED THE KILL COOLDOWN, and the design's most deliberate window.
```

Note the starting values differ from the `0.6` they replace on purpose: `0.6` was one point, and the
ramp needs two endpoints on either side of it so that a full-health Exposed monster is *visibly*
fainter than the one that ate a `0.6` before this chunk.

Then, in the same step, the three pins that make those numbers checkable — inserted in
`tests/config.test.luau` after the `check("the kill cooldown outlasts the salt stun", …)` block at
`tests/config.test.luau:158-164`, which is where the salt-versus-monster relationships live.
`MonsterHealth` already fails safe on all three (`floorOf`'s `math.min`, `weakenedFraction`'s
zero-span guard), which is why they are pinned here rather than left to the module: the module's job
is to not crash, and the test's job is to say the numbers were meant that way.

#### Step 2.2: Pin §6.5 invariant 1 in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `npm run test:unit`

`SaltDamage × (SaltSpawnCount − 1) ≥ MaxHealth − WeakenedThreshold`. Satisfied exactly at the shipped
numbers (25 × 3 = 75), which is precisely why it needs an assertion rather than a comment.

**This invariant is currently written in three comments and asserted nowhere.** `Config.luau:30-31`
tells the reader it exists, `Config.luau:249-255` tells them the same thing again, and §6.5 names it
as invariant 1 — but `grep -n "MaxHealth" tests/config.test.luau` returns nothing. It is satisfied
*with zero margin* at the shipped numbers, so the first balance pass that raises `MaxHealth` to 120
or drops `SaltSpawnCount` to 3 makes the second win condition unreachable and nothing in the game
says so. Insert after the "the kill cooldown outlasts the salt stun" check
(`tests/config.test.luau:158-164`), which is where the other salt-versus-monster relationships sit.

```diff
 check(
 	"the kill cooldown outlasts the salt stun",
 	Config.Monster.KillCooldown > Config.Salt.StunDuration,
 	`KillCooldown={Config.Monster.KillCooldown}, StunDuration={Config.Salt.StunDuration}`
 )
 
+--[[
+	§6.5 INVARIANT 1 (V05, §4.6). THE SECOND WIN CONDITION, AND IT HAS NO SYMPTOM.
+
+	"Land three salt hits, then land the buntot pagi during a reveal window. They have four pouches,
+	so exactly one may miss." That sentence is four numbers in three Config blocks, and it was a
+	comment in two of them and an assertion in none until this chunk.
+
+	IT IS SATISFIED WITH ZERO MARGIN at the shipped values — 25 x 3 = 75 = 100 - 25 — which is what
+	makes it dangerous rather than decorative. Raise MaxHealth, lower WeakenedThreshold, soften
+	SaltDamage or cut a pouch and survivors can no longer reach `Weakened` after one miss. The game
+	does not get harder in any visible way; the Aswang simply stops being killable, and that reads as
+	a balance opinion rather than as a broken win condition.
+
+	THE `- 1` IS THE MISS. Removing it is the tempting simplification and it is the bug: it asserts
+	that survivors win only if every single throw connects.
+]]
+check(
+	"survivors can still weaken the Aswang after one missed throw",
+	Config.Items.SaltDamage * (Config.Items.SaltSpawnCount - 1)
+		>= Config.Monster.MaxHealth - Config.Monster.WeakenedThreshold,
+	`SaltDamage={Config.Items.SaltDamage}, SaltSpawnCount={Config.Items.SaltSpawnCount}, `
+		.. `MaxHealth={Config.Monster.MaxHealth}, WeakenedThreshold={Config.Monster.WeakenedThreshold}`
+)
+
+--[[
+	THE FEED IS A SETBACK, NOT A RESET (§4.6). "Every kill the Aswang makes heals away one salt hit"
+	— ONE. A FeedHeal above SaltDamage means each kill undoes more than a pouch, and since there are
+	four pouches and no recharge, the tug-of-war stops being a tug-of-war and becomes arithmetic the
+	survivors lose by construction.
+]]
+check(
+	"a feed heals away no more than one salt hit",
+	Config.Monster.FeedHeal <= Config.Items.SaltDamage,
+	`FeedHeal={Config.Monster.FeedHeal}, SaltDamage={Config.Items.SaltDamage}`
+)
+
```

#### Step 2.3: Pin the two supporting relationships the ramp depends on

**File:** `tests/config.test.luau`
**Verify:** `npm run test:unit`

The glow must brighten rather than dim as health falls, and `WeakenedThreshold` must sit strictly
below `MaxHealth` or `weakenedFraction` divides by zero and the ramp has no domain.

`MonsterHealth` already fails safe on both (`floorOf`'s `math.min`, `weakenedFraction`'s zero-span
guard), which is why these are pinned here rather than left to the module: the module's job is to not
crash, and the test's job is to say the numbers were meant that way.

```diff
+-- V05, §4.6. The glow is the ONLY presentation of health, so its direction is the mechanic. Lower
+-- transparency is brighter; inverting these two makes a dying Aswang FADE, which is exactly
+-- backwards, entirely silent, and findable only by playing it while counting salt hits.
+check(
+	"the Exposed glow brightens as the Aswang weakens",
+	Config.Monster.ExposedGlowTransparencyWeakened < Config.Monster.ExposedGlowTransparencyFull,
+	`Weakened={Config.Monster.ExposedGlowTransparencyWeakened}, `
+		.. `Full={Config.Monster.ExposedGlowTransparencyFull}`
+)
+
+-- A Highlight's FillTransparency is 0..1. Outside it the property clamps silently and the ramp
+-- flattens at one end, which looks like "the glow stopped changing" rather than like a bad number.
+check(
+	"both glow endpoints are legal transparencies",
+	Config.Monster.ExposedGlowTransparencyWeakened >= 0
+		and Config.Monster.ExposedGlowTransparencyFull <= 1,
+	`Weakened={Config.Monster.ExposedGlowTransparencyWeakened}, `
+		.. `Full={Config.Monster.ExposedGlowTransparencyFull}`
+)
+
+-- V05, §4.6. The ramp needs a span to interpolate across, and `Weakened` needs to be a state a
+-- healthy monster is not in. Equal values make every Aswang permanently weakened from the first
+-- frame of the round; an inverted pair makes it permanently weakened AND unfloorable.
+check(
+	"there is room between full health and weakened",
+	Config.Monster.WeakenedThreshold < Config.Monster.MaxHealth,
+	`WeakenedThreshold={Config.Monster.WeakenedThreshold}, MaxHealth={Config.Monster.MaxHealth}`
+)
+
```

---

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — `Config.luau` replicates to every client in full. Nothing added here may be an
  input to a draw or a per-player value.
- **Remote direction** — n/a.
- **Rate limiting** — n/a.
- **Magic numbers** — this phase is the fix for one; check no new literal lands in `src/server/`.
- **Phase ownership** — n/a.
- **Player leaving mid-round** — n/a.
- **Strict Luau** — n/a; Config is a plain table and must stay free of Roblox datatypes (Lune).
- **Mobile budget** — the glow is one existing Highlight; no new instance.
- **Scope** — n/a.

**Issues identified:**

- **`tests/config.test.luau` counts its own checks** (`tests/config.test.luau:884-889`: *"COUNTED,
  NOT TYPED. This line read `34 balance invariants` as a literal for long enough…"*). Adding five
  checks needs no edit to that line — but do not reintroduce a literal count.
- **Config must stay free of Roblox datatypes.** `tests/config.test.luau` requires `Config.luau`
  under Lune, which has no `Color3`. The new numbers are plain floats, which is why the glow's ramp
  is two scalars and not a `ColorSequence` (`Config.luau:311-315` states the rule).
- **`.. ` string concatenation inside an interpolated detail string** is used here to stay inside
  100 columns. StyLua will not break a long backtick string for you; `fmt:check` will red it.
- **`FeedHeal <= SaltDamage` is a new relationship not named in §6.5.** It follows from §4.6's "every
  kill heals away one salt hit", but it is an inference rather than a quoted line — flagged in
  Follow Ups so it is argued rather than inherited.

---

### Phase 3: Health lives in `MonsterState`, server-only

Add the number and the two seams that write it. No presentation, no Exposed, nothing on the wire —
the game is runnable and unchanged at the end of this phase.

#### Step 3.1: Add `Health` to `MonsterState` and initialise it in `stateFor`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

One field on the existing server-only `monsters` table, defaulted to `Config.Monster.MaxHealth`, with
the reset semantics tied to the existing `table.clear(monsters)` on leaving `ACTIVE`.

**Read `MonsterService.luau:104` before touching anything here:** *"SERVER-ONLY. Keyed by UserId.
Never replicated — the only thing that crosses is the broadcast."* That table is where health goes
and it is the only place it goes. See the preamble's rule 1 for the trap this is avoiding.

```diff
 local KillValidation = require(Shared.pure.KillValidation)
+local MonsterHealth = require(Shared.pure.MonsterHealth)
 local Remotes = require(Shared.Remotes)
 local TransformRules = require(Shared.pure.TransformRules)
 local Types = require(Shared.Types)
 
 local MonsterService = {}
+
+--[[
+	THE HEALTH TUNING (V05, §4.6), ASSEMBLED ONCE FROM TWO CONFIG BLOCKS.
+
+	`MaxHealth`, `WeakenedThreshold` and `FeedHeal` live under `Config.Monster`; `SaltDamage` lives
+	under `Config.Items`, which is §6.5's canonical item block and where V02 put the four salt
+	numbers. `pure/MonsterHealth` takes one table rather than reaching for either, so it stays a
+	function over plain numbers and `tests/monster-health.test.luau` can hand it a synthetic tuning.
+
+	READ THROUGH `Config.Items`, NOT THROUGH `Config.Salt`. The `Salt` block is a set of aliases V02
+	kept alive for five v1.3 readers (Config.luau:326-342) and it dies with the chunk that renames
+	its last one.
+]]
+local HEALTH_TUNING: MonsterHealth.Tuning = {
+	MaxHealth = Config.Monster.MaxHealth,
+	WeakenedThreshold = Config.Monster.WeakenedThreshold,
+	SaltDamage = Config.Items.SaltDamage,
+	FeedHeal = Config.Monster.FeedHeal,
+}
```

Then the field on `MonsterState`, next to the other per-round facts:

```diff
 	LastRevertedAt: number?, -- nil until the first revert of the round; drives the cooldown
 	BaseWalkSpeed: number?,
 	Generation: number, -- invalidates an in-flight forced revert; see revert()
+	--[[
+		THE ASWANG'S HEALTH (V05, §4.6). SERVER-ONLY, AND THIS FIELD IS THE ONLY COPY OF IT.
+
+		NOT `Humanoid.Health` AND NOT `Humanoid.MaxHealth`. Both are replicated properties: writing
+		this number onto the humanoid lets any client walk `workspace`, find the one character
+		reading 75 while four others read 100, and know the monster — permanently, for free, with no
+		remote to intercept and nothing for `check:secrecy` to see. That is the same shape as C04's
+		revert bug and C14's WalkSpeed brand, both of which shipped green (see ItemService's
+		`applyHit` header and `.claude/lessons/absence-is-observable.md`).
+
+		Not an attribute and not a tag either; both replicate to every client and there is no private
+		one.
+
+		SURVIVES A TRANSFORM CYCLE, DIES WITH THE ROUND. It is deliberately not reset by `revert()` —
+		§4.6's tug-of-war is a round-long resource, so three salt hits across three separate
+		transforms still weaken. `onPhaseChanged`'s existing `table.clear(monsters)` on the way out
+		of ACTIVE is the reset, and it is the only one.
+	]]
+	Health: number,
 }
```

```diff
 	local created: MonsterState = {
 		Transformed = false,
 		Applied = false,
 		Announced = false,
 		AppliedTo = nil,
 		OriginalParts = {},
 		OriginalScales = {},
 		Effects = {},
 		LastRevertedAt = nil,
 		BaseWalkSpeed = nil,
 		Generation = 0,
+		Health = Config.Monster.MaxHealth,
 	}
```

**No round-start loop, deliberately.** The obvious alternative — seed the Aswang's health when
`RoundService` assigns the role — means writing a code path that runs for exactly one player at a
known moment, which is a role-shaped branch on the 🔒 surface for no gain. Lazy creation through the
existing `stateFor` keeps every player's server state identical until they transform, and a
transform is already public by design.

#### Step 3.2: Add the private health mutator and the `HealFromFeed` seam

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

One private function that resolves every health change through `pure/MonsterHealth.apply`, and one
public seam V06 calls. Neither returns the health value.

Place the private mutator just above `revert()`, so it sits with the other state writers rather than
with the public API at the bottom.

```diff
+--------------------------------------------------------------------------------
+-- Health (V05, §4.6). The tug-of-war: salt takes it down, feeding pulls it back.
+--------------------------------------------------------------------------------
+
+--[[
+	APPLY ONE HEALTH EVENT TO A PLAYER'S SERVER STATE. Returns true if the state existed.
+
+	READ, DO NOT CONSTRUCT — `stateFor` here would re-insert a departed player's UserId every time a
+	stale timer fired, which is the exact bug `revert()`'s first line was written to avoid. Every
+	caller reaches this function only after the server has already established that this player is a
+	transformed Aswang, so the entry exists; a missing entry means the round moved on and the answer
+	is to do nothing.
+
+	IT RETURNS A BOOLEAN AND NEVER THE HEALTH. The value has exactly one home (see MonsterState) and
+	handing it back is how a second copy starts existing — in a payload, in a log line, in an
+	attribute somebody added to debug it. Callers that need a decision ask `IsWeakened`.
+
+	THE FLOOR IS NOT ENFORCED HERE. `MonsterHealth.apply` owns it, gated on
+	`lune run tests/monster-health.test.luau`, so there is one implementation of §4.6's most
+	consequential rule and it is the tested one.
+]]
+local function applyHealthEvent(userId: number, event: MonsterHealth.HealthEvent): boolean
+	local monster: MonsterState? = monsters[userId]
+
+	if monster == nil then
+		return false
+	end
+
+	monster.Health = MonsterHealth.apply(monster.Health, event, HEALTH_TUNING)
+
+	return true
+end
+
 local function revert(player: Player)
```

Then the public seam, in the C14-seam block at the bottom of the file beside `IsTransformed` and
`ForceRevert`:

```diff
+--[[
+	FEEDING RESTORES HEALTH (V06, §4.3/§4.6). The seam, declared here and UNWIRED BY V05.
+
+	§4.6: "every kill the Aswang makes heals away one salt hit. That is the tug-of-war the whole
+	design turns on." V06 builds the five-second locked feed, validates the corpse, the distance and
+	the phase through `pure/FeedRules`, and calls this on completion. V05 owns the number; V06 owns
+	the ritual.
+
+	NOT A ROLE QUERY AND NOT AN ENUMERATION, on the same terms as `IsTransformed` above: the caller
+	must already hold a UserId it got from somewhere else, and a player with no monster state gets
+	`false` rather than an entry created for them.
+
+	CAMOUFLAGE IS NOT RESTORED HERE. §4.3 gives a completed feed two rewards — the heal and the
+	camouflage refresh — and V07 owns the second. Splitting them is deliberate: `MonsterService`
+	should not grow a charge it cannot yet spend.
+]]
+function MonsterService.HealFromFeed(userId: number): boolean
+	return applyHealthEvent(userId, "FEED")
+end
```

#### Step 3.3: Add `MonsterService.IsWeakened` as the V08 gate

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify:fast`

A predicate over a UserId the caller already holds — the same contract `IsTransformed` established at
C14, and for the same stated reason.

```diff
+--[[
+	IS THIS PLAYER AT OR BELOW `WeakenedThreshold`? (V05, §4.6) One half of V08's strike gate.
+
+	§4.6: the buntot pagi "kills only an Aswang that is both Exposed (glowing from a salt hit) and
+	Weakened (at or below 25 health). Against anything else it does nothing." V08 ANDs this with
+	`IsExposed` and with `RoundService.GetAswangUserId()`, exactly as `ItemService` already ANDs
+	`IsTransformed` with the role before handing a single boolean to a pure module — so the role
+	never enters the pure layer at all.
+
+	A PLAYER WITH NO MONSTER STATE IS NOT WEAKENED, and that is the safe direction twice over: a
+	survivor was never salted, and an Aswang who has not transformed this round has full health. It
+	is also the one that cannot be used as a probe — `false` is what every one of the five players
+	returns until somebody lands a salt hit.
+
+	`Weakened` IS A PREDICATE, NOT A `MonsterState` MEMBER, and `Enums.luau:69-71` says why: "it is a
+	HEALTH PREDICATE — `health <= Config.Monster.WeakenedThreshold` — not a state, and duplicating it
+	as an enum member is how two sources of truth for one fact get out of step." Do not add
+	`Enums.MonsterState.Weakened`.
+]]
+function MonsterService.IsWeakened(userId: number): boolean
+	local monster: MonsterState? = monsters[userId]
+
+	if monster == nil then
+		return false
+	end
+
+	return MonsterHealth.isWeakened(monster.Health, HEALTH_TUNING)
+end
```

Also confirm `onPlayerRemoving` (`MonsterService.luau:980-982`) still carries health out with the
entry — it nils the whole `monsters[userId]` slot, so it does, and no edit is needed. The step is to
*check* it rather than to change it.

---

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the preamble's rule 1 is this phase's whole risk: no `Humanoid.Health`, no
  `Humanoid.MaxHealth`, no attribute, no tag, no per-player remote.
- **Remote direction** — none added; `check:remotes` must stay green with no diff to `Remotes.luau`.
- **Rate limiting** — no new `OnServerEvent` handler in this phase.
- **Magic numbers** — `MaxHealth`, `WeakenedThreshold`, `SaltDamage`, `FeedHeal` all read from Config.
- **Phase ownership** — the reset hangs off the existing `onPhaseChanged`; no `setPhase` call.
- **Player leaving mid-round** — `onPlayerRemoving` already nils the entry; confirm health goes with it.
- **Strict Luau** — `monsters[userId]` is optional; annotate before comparing to nil.
- **Mobile budget** — n/a.
- **Scope** — n/a.

**Issues identified:**

- **`MonsterHealth.HealthEvent` as a parameter type is a scalar and therefore safe.** The lesson
  `pure-module-unions-widen-in-lists` bites on a literal union inside a LIST crossing a `require`
  boundary. `applyHealthEvent(userId, event: MonsterHealth.HealthEvent)` passes one literal to one
  parameter, which is the case the lesson explicitly calls fine (*"Scalars are fine. Do not
  restructure a pure module that returns one value."*). If `analyze` disagrees at the call site, the
  fix is to type the parameter `string` — `MonsterHealth.apply` already takes `string` — and NOT to
  start casting.
- **`check:config` governs `src/server/`.** Every number in this phase arrives through
  `HEALTH_TUNING`, and every line of that table has `Config.` on it, which is the shape the check
  allows. Do not inline a `25` into `applyHealthEvent` "for clarity".
- **`table.clear(monsters)` is the only health reset and it runs on the way OUT of `ACTIVE`**
  (`MonsterService.luau:919-938`). Note what that means for a round that ends and immediately
  restarts: the clear happens on `ENDING`, so the next round's first transform builds fresh state.
  Do not add a second reset in `Init` — one already exists there and a third place to reset is a
  third place to forget.
- **`HealFromFeed` has no caller until V06.** `selene` does not flag an unused public field on a
  returned table, and `analyze` does not either, so this will not red the tree — but it *is* dead
  code for one chunk, which is a deliberate deviation noted in Follow Ups.

---

### Phase 4: `Exposed` — the latch, the expiry, and the glow that reads health

The Highlight moves from `ItemService` to `MonsterService`, because the glow's brightness is a
function of health and health lives here. `ItemService`'s `applyHit` becomes two calls.

#### Step 4.1: Move the reveal Highlight into `MonsterService` as the Exposed presentation

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

`applyExposed` / `clearExposed`, using the `Generation` idiom the file already uses for the forced
revert, plus a `refreshExposedGlow` that lerps the two Config endpoints by `weakenedFraction`.

**Why the glow moves service.** §4.6's presentation of health is the glow's brightness, and health
lives in `MonsterService`. Leaving the Highlight in `ItemService` means either `ItemService` reads
the health value across a service boundary — a second copy of the one number that must have one home
— or `MonsterService` reaches into another service's instance table. V08 rewrites salt anyway
(`ItemCarry`/`ItemThrow`), so this is the cheapest moment in the whole rewrite to move it.

**What must survive the move, byte for byte.** `ItemService.luau:432-450` argues four choices, and
every one of them is load-bearing rather than stylistic: a `Highlight` and **not** an attribute, a
tag, a `TeamColor` or a per-client effect; parented to the **character** and stored as the
**instance** so a respawn cannot brand a fresh body; `DepthMode = Occluded` rather than `AlwaysOnTop`,
because on-top renders the glow **through walls** and turns a ten-second reveal into a ten-second
wallhack on the monster; and no role token anywhere in the code, because there is no role in this
call chain to name.

First, three fields on `MonsterState`:

```diff
 	Health: number,
+	-- V05, §4.6. EXPOSED IS THE TRUTH; the Highlight below is its presentation. Two fields rather
+	-- than one because `IsExposed` is V08's strike gate and must not depend on whether an Instance
+	-- happened to survive a respawn. Every exit clears both, together, in `clearExposed`.
+	Exposed: boolean,
+	ExposedGlow: Highlight?,
+	-- The same `os.clock()` generation trick `revert()` uses, for the same reason: a second salt hit
+	-- landing during the first one's window must not have its expiry cut short by the first timer.
+	ExposedGeneration: number,
```

…initialised in `stateFor` alongside `Health`:

```diff
 		Health = Config.Monster.MaxHealth,
+		Exposed = false,
+		ExposedGlow = nil,
+		ExposedGeneration = 0,
```

Then the three functions, placed just after `applyHealthEvent` and before `revert()`:

```diff
+--[[
+	THE GLOW'S BRIGHTNESS IS THE HEALTH READOUT (§4.6). "The intended presentation is diegetic and
+	needs no UI at all: the glow gets brighter as it weakens."
+
+	THIS IS THE ONE CHANNEL HEALTH IS ALLOWED TO USE, and it is legal for a reason that is structural
+	rather than permitted: §6.2 says health is "readable by others only while `Exposed`", and this
+	Highlight EXISTS only while Exposed. There is no arrangement in which it publishes health outside
+	the window, because outside the window there is no instance to read.
+
+	THE COLOURS STAY UNDER `Config.Salt` and the RAMP under `Config.Monster`, which is not an
+	oversight: salt paints the glow, health decides how bright it burns. See Config.luau's comment on
+	`ExposedGlowTransparency*`.
+]]
+local function refreshExposedGlow(monster: MonsterState)
+	local glow = monster.ExposedGlow
+
+	if glow == nil then
+		return
+	end
+
+	local full = Config.Monster.ExposedGlowTransparencyFull
+	local weakened = Config.Monster.ExposedGlowTransparencyWeakened
+	local fraction = MonsterHealth.weakenedFraction(monster.Health, HEALTH_TUNING)
+
+	glow.FillTransparency = full + (weakened - full) * fraction
+end
+
+--[[
+	END THE EXPOSED WINDOW. Idempotent, and safe to call for a player who was never exposed.
+
+	THE BOOLEAN AND THE INSTANCE ALWAYS DIE TOGETHER. A `clearExposed` that destroyed the glow and
+	left `Exposed = true` would leave V08 able to kill a monster nobody can see glowing; one that did
+	the reverse would leave a permanent mark on one character in the workspace, which is the C04/C14
+	failure exactly.
+]]
+local function clearExposed(userId: number)
+	local monster: MonsterState? = monsters[userId]
+
+	if monster == nil then
+		return
+	end
+
+	local glow = monster.ExposedGlow
+
+	monster.Exposed = false
+	monster.ExposedGlow = nil
+
+	if glow ~= nil then
+		glow:Destroy()
+	end
+end
+
+--[[
+	BEGIN THE EXPOSED WINDOW (§4.6): "a hit forces the revert, applies a visible glow for 10s".
+
+	Moved here from `ItemService.applyReveal` at V05 with its reasoning intact, because the
+	brightness is now a function of health. A Highlight AND NOT: an attribute (replicates, and
+	`check:secrecy` refuses role-named ones for exactly this reason), a CollectionService tag (same),
+	a name colour (`TeamColor` and `Team` both replicate and are the classic version of this
+	mistake), or a per-client effect (a "hidden" reveal is one a compromised client reads and an
+	honest one does not — the worst of both).
+
+	`DepthMode = Occluded` IS A DESIGN DECISION HIDING IN AN ENUM VALUE. `AlwaysOnTop` renders the
+	glow THROUGH WALLS, turning a ten-second reveal into a ten-second wallhack on the monster.
+
+	NOTHING HERE IS NAMED FOR A ROLE, and there is no role in this call chain to name: the decision
+	that this player was a transformed Aswang was made and discarded back in `ItemService`'s
+	`resolveThrow`.
+]]
+local function applyExposed(player: Player)
+	local monster: MonsterState? = monsters[player.UserId]
+	local character = player.Character
+
+	if monster == nil or character == nil then
+		return
+	end
+
+	clearExposed(player.UserId)
+
+	local glow = Instance.new("Highlight")
+	local generation = os.clock()
+
+	glow.Name = "SaltReveal"
+	glow.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
+	glow.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
+	glow.DepthMode = Enum.HighlightDepthMode.Occluded
+	glow.Parent = character
+
+	monster.Exposed = true
+	monster.ExposedGlow = glow
+	monster.ExposedGeneration = generation
+
+	refreshExposedGlow(monster)
+
+	task.delay(Config.Items.SaltRevealDuration, function()
+		local current: MonsterState? = monsters[player.UserId]
+
+		-- A NEW ENTRY OR A NEWER HIT BOTH DECLINE. `table.clear(monsters)` on the way out of ACTIVE
+		-- can drop this player's state entirely and `stateFor` can rebuild it next round with
+		-- `ExposedGeneration = 0`, which no live generation ever equals.
+		if current == nil or current.ExposedGeneration ~= generation then
+			return
+		end
+
+		clearExposed(player.UserId)
+	end)
+end
```

`FillTransparency` is deliberately absent from the constructor block: `refreshExposedGlow` sets it one
line later, so there is exactly one place the ramp is written and a reader cannot find a stale
constant next to it.

#### Step 4.2: Add `MonsterService.ApplySaltHit` and `MonsterService.IsExposed`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

One entry point that reverts, damages and exposes in the order `ItemService`'s audit fixed once
already, and one predicate for V08's two-condition strike gate.

**`ApplySaltHit` replaces `ForceRevert` rather than joining it.** `ForceRevert` has exactly one
caller in the repo — `ItemService.luau:511` — and after Step 4.3 it has none. Leaving a public seam
that still *only reverts* next to one that reverts-damages-exposes is an invitation for V08 to call
the wrong one and silently skip §4.6's damage; its own header (`MonsterService.luau:1006-1020`) makes
that argument about `ItemService` reimplementing the revert, and it applies to itself. Delete
`ForceRevert` and carry its reasoning across.

```diff
-function MonsterService.ForceRevert(player: Player)
-	revert(player)
-end
+--[[
+	A SALT HIT (§4.6, V05). Revert, damage, expose — in that order, and the order is the whole
+	correctness of this function.
+
+	IT SHIPPED WRONG ONCE, IN THE OTHER SERVICE, AND AN EXPLOIT AUDIT CAUGHT IT. `ItemService`'s
+	first version ran its stun before the revert, so `revert()` wrote `BaseWalkSpeed` (16) over the
+	stun's 0 in the same frame — the stun never happened — and four seconds later the stun restored
+	the captured TRANSFORMED speed (20) onto a player who was no longer transformed. `WalkSpeed` is
+	a replicated property, so any client could poll every character and find the single one reading
+	20: a permanent role brand, readable map-wide, with `check:secrecy` green over it. The full story
+	is in `ItemService.applyHit`'s header, and the invariant it wrote binds this function too: NO
+	PATH ADDED HERE MAY LEAVE A LIVING PLAYER'S HUMANOID PROPERTIES DIFFERENT FROM EVERY OTHER
+	LIVING PLAYER'S.
+
+	DAMAGE BEFORE EXPOSE, so the glow's first frame already reads the new health. Exposing first and
+	damaging after gives one frame at the old brightness, which is not a leak but is a lie.
+
+	THE REVERT IS `revert()` AND NOT A REIMPLEMENTATION. Everything the salt path needs already
+	happens in there: the generation bump that invalidates the in-flight forced-revert timer, the
+	`Announced` gate that stops a mid-windup revert broadcasting a transform nobody saw, the
+	`LastRevertedAt` stamp that charges the kill cooldown, and the look restoration that resolves
+	`AppliedTo` rather than `player.Character`. C04's audit found a second implementation getting the
+	last of those four wrong.
+
+	NO GUARD ON WHO CALLS THIS, deliberately: `revert` early-returns for a player who is not
+	transformed, `applyHealthEvent` returns false for a player with no state, and `applyExposed`
+	does nothing without one. A mistaken call is a no-op rather than a state change. The validation
+	that a hit happened at all lives in `ItemService`, next to the request that claimed it.
+
+	DELIBERATELY NOT A KILL AND NOT A `MarkKilled`: §4.6 is counterplay, not a win condition. Salt
+	never ends a round, which is why `MonsterHealth.apply` floors it at `WeakenedThreshold`.
+]]
+function MonsterService.ApplySaltHit(player: Player)
+	revert(player)
+	applyHealthEvent(player.UserId, "SALT")
+	applyExposed(player)
+end
+
+--[[
+	IS THIS PLAYER INSIDE THE EXPOSED WINDOW? (V05, §4.6) The other half of V08's strike gate.
+
+	SAFE TO EXPOSE FOR THE SAME REASON `IsTransformed` IS: being Exposed is ALREADY PUBLIC — there is
+	a Highlight on that character that every client with line of sight can see, which is the entire
+	point of §4.6's reveal. This function states nothing a player standing there cannot see, it never
+	enumerates, and the caller must already hold a UserId it got from somewhere else.
+
+	A PLAYER WITH NO MONSTER STATE IS NOT EXPOSED — false for every survivor, every round, so it is
+	useless as a probe.
+]]
+function MonsterService.IsExposed(userId: number): boolean
+	local monster: MonsterState? = monsters[userId]
+
+	return monster ~= nil and monster.Exposed
+end
```

The V08 strike gate this pair exists for, written here so the next chunk inherits it rather than
inventing it: `RoundService.GetAswangUserId() == userId and MonsterService.IsExposed(userId) and
MonsterService.IsWeakened(userId)`. Three booleans ANDed on the server; the role never enters the
pure layer, exactly as `ItemService.luau:606` already does it for `IsTransformed`.

#### Step 4.3: Rewrite `ItemService.applyHit` to call the seam

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run analyze`

Delete `applyReveal`, `clearReveal`, the `RevealState` type and the `reveals` table; `applyHit`
becomes `ApplySaltHit` then `applyStun`, preserving the revert-before-stun ordering the header
explains.

**Four call sites of `clearReveal` disappear and three of them are exits that must be re-homed in
`MonsterService`** — Step 4.4 is where they land. Do not delete them here and hope; list them as you
go: `ItemService.luau:521` (phase change), `:715` (`PlayerRemoving`), `:731` (`CharacterRemoving`),
and `applyReveal`'s own `clearExposed`-equivalent at `:458`.

```diff
-- Highlights this service created, keyed by UserId, with the same generation trick the stun uses.
-type RevealState = {
-	Instance: Highlight,
-	Generation: number,
-}
-
-local reveals: { [number]: RevealState } = {}
-
-local function clearReveal(userId: number)
-	local state = reveals[userId]
-
-	if state == nil then
-		return
-	end
-
-	reveals[userId] = nil
-	state.Instance:Destroy()
-end
```

`applyReveal` goes with it in full (`ItemService.luau:431-480`), and `applyHit` becomes:

```diff
 --[[
 	A SALT HIT: revert FIRST, then stun, then reveal.
+
+	V05 MOVED THE REVERT AND THE REVEAL INTO `MonsterService.ApplySaltHit`, because §4.6's reveal now
+	carries the health readout — the glow brightens as the Aswang weakens — and health is server
+	state that has exactly one home. What stays here is the STUN, which is salt's alone.
+
+	THE ORDERING RULE SURVIVES THE MOVE UNCHANGED AND IS THE WHOLE CORRECTNESS OF THIS FUNCTION.
+	`ApplySaltHit` reverts first; `applyStun` therefore captures the HONEST post-revert speed. The
+	first version of this file ran the stun before the revert and produced a permanent, map-readable
+	role brand — the story is below and it is worth reading before reordering these two lines.
 
 	THE ORDER IS THE WHOLE CORRECTNESS OF THIS FUNCTION AND IT SHIPPED WRONG ONCE. The first version
 	ran `applyStun` before `ForceRevert`, on the reasoning that capturing before the revert preserved
@@
 local function applyHit(target: Player)
-	MonsterService.ForceRevert(target)
+	MonsterService.ApplySaltHit(target)
 	applyStun(target)
-	applyReveal(target)
 end
```

`clearAllEffects` loses its reveal loop and keeps its stun loop, and its header comment moves to
`MonsterService` with the behaviour:

```diff
--- EVERY reveal and EVERY stun ends when the round does. Called from onPhaseChanged beside
--- clearPouches, and this is the exit that actually matters: without it a player hit at second 419 of a
--- 420-second round is still glowing in the lobby, where the glow is no longer an event that anybody
--- witnessed and is simply a mark on one of the eight people standing there.
+-- EVERY stun ends when the round does. Called from onPhaseChanged beside clearPouches. The REVEAL's
+-- half of this moved to `MonsterService.onPhaseChanged` at V05 along with the Highlight; the reason
+-- it exists is repeated there, because it is the exit that actually matters.
 local function clearAllEffects()
-	for userId in reveals do
-		clearReveal(userId)
-	end
-
 	for userId in stunned do
```

And the two lifecycle handlers:

```diff
 	Players.PlayerRemoving:Connect(function(player: Player)
 		carried[player.UserId] = nil
 
-		-- Both effect tables too, or a disconnect mid-stun leaves an entry pointing at a destroyed
-		-- character and a Highlight this service still believes it owns. `clearReveal` destroys the
-		-- instance it holds rather than looking it up through the character, so it works after the
-		-- character is gone; `stunned` is dropped directly because there is no humanoid left to restore.
-		clearReveal(player.UserId)
+		-- `stunned` is dropped directly because there is no humanoid left to restore. The reveal's
+		-- half of this is `MonsterService.onPlayerRemoving` since V05.
 		stunned[player.UserId] = nil
 	end)
```

The `CharacterRemoving` connection (`ItemService.luau:718-733`) is **deleted here and rebuilt in
`MonsterService`** at Step 4.4. Its comment — the glowing corpse — moves with it verbatim; it is the
only written record of that failure.

#### Step 4.4: Clear Exposed on every exit the reveal already had

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify`

Phase change out of `ACTIVE`, death, respawn and `PlayerRemoving` — the four exits `ItemService`
enumerated at lines ~516 and ~712, none of which may be lost in the move.

**The timing is preserved exactly, not approximated.** `ItemService.onPhaseChanged:678` cleared the
reveal on **every phase that is not ACTIVE** — including `ENDING`, deliberately, because *"pouches
lying on the ground during ENDING are scenery, a glow during ENDING is a mark on a player."*
`MonsterService.onPhaseChanged:919-938` already runs its revert loop on exactly that condition, so
the clear goes in the loop that is already there and the two behaviours cannot drift apart again.

```diff
 	-- Leaving ACTIVE ends every transform and clears the cooldowns, so a new round never begins with
 	-- a monster still standing or an Aswang serving the last round's penalty.
 	for userId in monsters do
 		local player = Players:GetPlayerByUserId(userId)
 
 		if player ~= nil then
 			revert(player)
 		end
+
+		--[[
+			AND EVERY EXPOSED WINDOW (V05, §4.6), BEFORE `table.clear` BELOW DROPS THE HANDLE.
+
+			`table.clear(monsters)` on its own would orphan the Highlight: the state that knows the
+			instance is gone, the instance is still parented to a living character, and nothing will
+			ever destroy it. A player hit at second 419 of a 420-second round would then glow in the
+			lobby permanently — where the glow is no longer an event anybody witnessed and is simply
+			a mark on one of the five people standing there.
+
+			CLEARED ON `ENDING` TOO, not just on INTERMISSION/IDLE. The split that keeps corpses
+			through ENDING (see above) is about scenery; this is about a mark on a player, and §4.8
+			calls the end screen "the screenshot people share".
+
+			This clear runs for a player who has LEFT as well, because it is keyed off the state
+			table rather than off `GetPlayerByUserId` — their character is already gone, and
+			`clearExposed` destroys the instance it holds rather than looking it up through a
+			character.
+		]]
+		clearExposed(userId)
 	end
 
 	table.clear(monsters)
```

`onPlayerRemoving` needs no edit — it nils the whole entry, and the departing player's character is
being removed by Roblox anyway. But the **respawn/death** exit does, and it is a new connection in
`watchCharacter`'s neighbourhood rather than a line inside `revert()`:

```diff
+--[[
+	THE GLOWING CORPSE, closed here rather than left to the ten-second timer. Moved from
+	`ItemService`'s `PlayerAdded` handler at V05, with its reasoning, because the Highlight moved.
+
+	`makeCorpse` DETACHES the victim's character and keeps it in the workspace for `CorpseDuration`.
+	A Highlight parented to that character goes with it — so a player revealed by salt and then
+	killed leaves a glowing body lying in the Barrio, which reads to every passer-by as "this corpse
+	was the monster". The reveal is supposed to be an event that expires, not a label on a body.
+
+	The Aswang cannot be killed, so the reachable paths are a reset or a fall while revealed. Cheap
+	to close and ugly if it ever shows up in a playtest video.
+
+	NOT FOLDED INTO `revert()`. A revert and an expiry are different events: §4.6 gives the glow ten
+	seconds and the revert is instant, so a revert that also cleared the glow would delete nine of
+	those seconds and with them the window the buntot pagi needs.
+]]
 local function onPlayerAdded(player: Player)
 	player.CharacterAdded:Connect(function(character: Model)
 		watchCharacter(player, character)
 	end)
 
+	player.CharacterRemoving:Connect(function()
+		clearExposed(player.UserId)
+	end)
+
 	-- RoundService turns CharacterAutoLoads off and loads explicitly (Step 1.4), so a character can
```

Finally, `revert()` gets **no** `clearExposed` call, and the diff for it is empty on purpose — see the
last paragraph of the comment above. A reviewer looking for it should find this sentence instead.

---

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the glow is the only channel health may use, and only while Exposed. Confirm
  the Highlight's lifetime is byte-for-byte the lifetime `ItemService` gave it: same players, same
  moments, same `DepthMode.Occluded`.
- **Remote direction** — still no remote. A `Highlight` property replicates without one, which is why
  this presentation needs no widening of any payload.
- **Rate limiting** — no new handler; `ItemService`'s existing `RequestThrowSalt` guard is untouched.
- **Magic numbers** — the `0.6` waiver is deleted, not moved.
- **Phase ownership** — the clear hangs off `onPhaseChanged`; nothing calls `setPhase`.
- **Player leaving mid-round** — an Exposed Aswang that leaves ends the round (§6.4); the glow must
  not outlive the character, and a stale `task.delay` must not resurrect a cleared table entry.
- **Strict Luau** — `Enums.RoundPhase.X` needs its `:: Types.RoundPhase` cast at any new comparison.
- **Mobile budget** — one Highlight, as before. No new light, no new particle.
- **Scope** — n/a.

**Issues identified:**

- **`Config.Salt.RevealDuration` loses its last reader in this phase.** `MonsterService` reads the
  canonical `Config.Items.SaltRevealDuration` instead. `Config.luau:330-337` says each alias "dies
  with the chunk that renames its last reader" — but `tests/config.test.luau:108-110` pins the alias
  to its source, so deleting it means editing the test too. **Leave it.** V08 generalises
  `Salt*` to `Item*` wholesale and is the chunk that should remove the block; flagged in Follow Ups.
- **`MonsterService` now reads `Config.Salt.RevealGlow*Rgb`.** That is a new cross-block read and it
  is deliberate — the colour belongs to the item that paints the glow. If it reads wrong to a
  reviewer, the alternative is moving two RGB triples, not duplicating them.
- **A second salt hit inside the first window.** `applyExposed` calls `clearExposed` first and stamps
  a fresh `os.clock()` generation, so the first timer declines and the window restarts at ten
  seconds. That is the intended behaviour (§4.6 gives a *hit* ten seconds) and it also means the
  glow's brightness re-reads health, which is the point.
- **`os.clock()` as a generation is not a seed.** It is compared for equality against a value the
  server stored, never used to drive a draw, and never sent. The `Random.new(os.time())` prohibition
  in CLAUDE.md is about draw inputs; this is a nonce.
- **The corpse-glow connection is on `CharacterRemoving`, not `Humanoid.Died`.** The kill path in
  this file never kills the humanoid — `makeCorpse` detaches and anchors, because §4.9 wants a fade
  rather than a death animation (`MonsterService.luau:941-952` states this). `CharacterRemoving`
  fires on the detach; `Died` would not.
- **`selene` may flag the now-unused `rgb` import path in `ItemService`** if `applyReveal` was its
  only remaining caller. It is not — the pouch spawn uses it — but confirm rather than assume, since
  `npm run lint` is inside `verify` and this is the phase that deletes code.

---

### Phase 5: The seams V06 and V08 will call, and the leak sweep

#### Step 5.1: Document the four seams in `MonsterService`'s header

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify`

`ApplySaltHit`, `HealFromFeed`, `IsExposed`, `IsWeakened` — what each returns, what it deliberately
does not return, and which chunk calls it.

```diff
 	WHAT THIS SERVICE DOES NOT SEND
 	-------------------------------
+
+	V05 ADDS A NUMBER AND SENDS NOTHING. The Aswang's health is a field on the server-only `monsters`
+	table and it has no remote, no attribute, no tag and no field on any payload. §6.2: "the Aswang's
+	health is server-only state, readable by others only while `Exposed`." The one channel it uses is
+	the brightness of a Highlight that EXISTS only during the Exposed window — so the permission and
+	the mechanism are the same fact, and there is no state in which the readout outlives the licence.
+
+	IT IS NOT ON THE HUMANOID, AND THAT IS THE WHOLE POINT. `Humanoid.Health` and `Humanoid.MaxHealth`
+	replicate. One character reading 75 while four read 100 is a permanent, map-wide, remote-free role
+	oracle — the same shape as C04's revert bug and C14's WalkSpeed brand, both of which shipped with
+	`verify` and `check:secrecy` green over them. See `.claude/lessons/absence-is-observable.md`: the
+	leak is a DIFFERENCE between players, not a piece of data.
+
+	THE FOUR SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:
+
+	  · `ApplySaltHit(player)` — V08. Revert, -SaltDamage floored at WeakenedThreshold, Exposed for
+	    SaltRevealDuration. The ONLY entry point for a salt hit; there is no bare `ForceRevert` any
+	    more, precisely so a caller cannot revert without damaging.
+	  · `HealFromFeed(userId) -> boolean` — V06, on a COMPLETED feed. Returns whether state existed,
+	    never the health. Does not restore camouflage; that is V07's half of §4.3's reward.
+	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
+	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
+	    Aswang that is BOTH. AND them with `RoundService.GetAswangUserId()` on the server and hand a
+	    single boolean to the pure module, exactly as `ItemService` does for `IsTransformed`.
+
+	NONE OF THE FOUR ENUMERATES, and none returns the health value. Every one takes a UserId the
+	caller already holds and answers false for a player with no monster state — which is every
+	survivor, every round, so none of them is usable as a probe.
```

#### Step 5.2: Run the full gate and hand the leak question to `exploit-auditor`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify`

The build plan's Verify line names an `exploit-auditor` question that no command answers; the brief
for it is written here rather than left to be improvised. **No source edit in this step** — it is the
full gate plus a handoff.

The build plan's V05 Verify reads: *"`exploit-auditor` answers: can any client read the Aswang's
health outside `Exposed`, by any path including a derived hint?"* Scope the brief the way CLAUDE.md
requires — the files, the phase, the questions:

> Audit **V05 only** — `.claude/plans/feature-v05-monster-health-plan/`, phases 3 and 4, loaded with
> `npm run plan:phase -- feature-v05-monster-health-plan 4`. Files: `MonsterService.luau`,
> `ItemService.luau`, `src/shared/pure/MonsterHealth.luau`, `src/shared/Config.luau`. Answer:
> (1) can any client read the Aswang's health outside the Exposed window, by any path including a
> derived hint — a replicated property, an instance that exists for one player and not others, a
> sound, a timing difference; (2) is the Exposed Highlight's lifetime identical to the one
> `ItemService` gave it before the move, across all four exits (phase change, respawn, disconnect,
> expiry); (3) can a compromised client make the server call `ApplySaltHit` or `HealFromFeed` on a
> player it chose; (4) does `IsExposed`/`IsWeakened` returning `false` for a player with no monster
> state create a probe — is there any observable difference between "not the Aswang" and "the Aswang,
> untransformed"; (5) any step in the plan with no traceable `file:line`.

Two things to hand it that a cold read will not surface: `check:secrecy` is a **text tripwire on
obvious shapes** and matches no token in any of this code, so a green check here means very little;
and the two prior failures of exactly this shape are documented at `ItemService.luau:484-510` (the
WalkSpeed brand) and in `MonsterService`'s `ForceRevert` header (C04's revert restoring hardcoded
defaults), both of which shipped green.

#### Step 5.3: Confirm in Studio that the glow brightens across three salt hits

**File:** `.claude/plans/feature-v05-monster-health-plan/artifacts/`

No `**Verify:**` line: this is a `playtester` step, and `verify-plan.mjs` reporting it as
`unverifiable` is the accurate answer. `next-phase.mjs` marks the phase `needs-human`, which is
correct — a ramp that is monotonic in a Lune test and invisible on a phone is a shipped feature that
does not exist.

What the artifact must show, dropped into this plan's `artifacts/`:

- Three screenshots of the same transformed Aswang, Exposed, after one, two and three salt hits, with
  a **visible** brightness difference between the first and the third. If they look the same,
  `Config.Monster.ExposedGlowTransparency*` is the fix, not the code.
- One screenshot ten seconds after the third hit showing **no glow at all**.
- `get_console_output` across a full round cycle, confirming no error from the expiry `task.delay`
  firing after a phase change cleared the state.

Set the debug values before launching it — the playtester cannot edit `Config.luau` and will correctly
refuse. `Round.Intermission/Duration/EndScreen` to 8/20/6 plus `Debug.SoloTesting`/`VerboseLogging`,
then revert all five and confirm with `git diff src/shared/Config.luau`. A round cycle is 461s at
committed values, which is longer than the Exposed window by a factor that makes this untestable
otherwise.

---

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the whole phase is this question.
- **Remote direction** — `Remotes.luau` must have no diff across the entire plan.
- **Rate limiting** — unchanged.
- **Magic numbers** — `check:config` green.
- **Phase ownership** — unchanged.
- **Player leaving mid-round** — covered in Phase 4; re-checked under a real Studio run here.
- **Strict Luau** — `analyze` green against the baseline, not widened.
- **Mobile budget** — unchanged.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **`review-gate.mjs` will name `exploit-auditor` automatically** — the diff touches
  `src/server/**` and `MonsterService`, which is the 🔒 row and not a judgement call. Launch it and
  the `playtester` concurrently, in one message, with `run_in_background: true`.
- **`git diff src/shared/Config.luau` must be clean before committing.** `guard-commit.mjs` runs
  `check:debug` and refuses the five playtest values, so they cannot reach history — but a dirty
  Config also makes the balance invariants in Phase 2 meaningless.
- **The `verify` in Steps 5.1 and 5.2 is the same command.** That is intentional: 5.1 is an edit
  whose gate is the tree staying green, 5.2 is the gate itself plus a handoff with no edit. If
  `verify-plan.mjs` objects to the duplicate, drop 5.2's line rather than inventing a second check.

---

## 3. Related Files

| File | Role in this plan | Review |
| --- | --- | --- |
| `src/shared/pure/MonsterHealth.luau` | **created** — the floor, the heal, the predicate, the ramp | — |
| `tests/monster-health.test.luau` | **created** — the health × event grid | — |
| `src/server/Services/MonsterService.luau` | health state, the Exposed latch, the glow, four seams | `MonsterService-review.luau` |
| `src/server/Services/ItemService.luau` | loses the reveal; `applyHit` calls the new seam | `ItemService-review.luau` |
| `src/shared/Config.luau` | two glow endpoints added; the health block already existed | `Config-review.luau` |
| `tests/config.test.luau` | §6.5 invariant 1, finally asserted | `config.test-review.luau` |
| `src/shared/Enums.luau` | `MonsterState.Exposed`; why `Weakened` is deliberately absent | `Enums-review.luau` |
| `src/shared/Types.luau` | `MonsterState`, `ClientRoundSnapshot` — read, not edited | `Types-review.luau` |
| `src/shared/Remotes.luau` | read only. **No diff in this plan** | `Remotes-review.luau` |
| `src/shared/pure/NoiseModel.luau` | V04's precedent for the pure-module idiom | `NoiseModel-review.luau` |
| `tests/noise-model.test.luau` | V04's precedent for the grid idiom | `noise-model.test-review.luau` |
| `src/server/Services/RoundService.luau` | phase ownership and `GetAswangUserId` — read, not edited | `RoundService-review.luau` |

## 4. Follow Ups

### Questions / Clarifications

1. **Does the Aswang get told its own health?** V05 says no: the glow is diegetic and the monster can
   see its own. But the monster only sees it while Exposed, so between hits it is guessing. Telling
   it would mean a `YourMonsterHealth: number?` on `ClientRoundSnapshot` — legitimate in shape (the
   `Your` prefix contract, `FireClient` per player, same class as `YourCarriedItem`) but it is a
   **widening of the client contract** and therefore a decision to argue, not a field to slip in.
   Recommend deciding it at **V07**, when camouflage gives the monster a reason to know how close to
   dead it is. Note the one real risk if it is added: `YourMonsterHealth` present-and-nil for a
   survivor versus present-and-100 for an Aswang is the `absence-is-observable` shape on a payload,
   so it must be nil for the Aswang too until it has been salted, or the field must not exist.

2. **`FeedHeal <= SaltDamage` is an inference, not a quoted line.** §6.5 lists six invariants and this
   is not among them; it follows from §4.6's "every kill heals away one salt hit". Pinned in Phase 2
   because an unpinned `FeedHeal` of 40 makes the second win condition unreachable while satisfying
   invariant 1 — but if the design wants feeding to be *worth more* than a pouch, delete the check
   and say so in the spec rather than letting the test lose the argument silently.

3. **`Config.Salt.RevealDuration` now has zero readers.** `Config.luau:330-337`'s rule says an alias
   dies with the chunk that renames its last reader, which would be this one — but
   `tests/config.test.luau:108-110` pins it, so removing it is a two-file edit for no behavioural
   gain, and **V08 generalises the whole `Salt*` surface to `Item*`** and should take the block. Left
   in place deliberately; if V08 does not remove it, it is dead weight to raise there.

4. **`MonsterService.HealFromFeed` ships with no caller.** A deliberate deviation from lean-code:
   V06 is the next chunk and the alternative is V06 editing `MonsterState`, which puts a health write
   in a service that does not own health. Declared here, wired there. If V06 slips, this is dead code
   for longer than one chunk and should be revisited.

5. **`MonsterService.ForceRevert` is deleted.** It had exactly one caller. Any chunk that wants a
   revert *without* the salt damage must add a seam and say why — the whole reason for deleting it is
   that "revert without damage" is the shape of a silent §4.6 failure.

6. **Roblox behaviour taken from this codebase, not assumed.** `Highlight.DepthMode`,
   `FillTransparency`, `CharacterRemoving`, `task.delay` and the `Instance.new`/`Parent` ordering are
   all used exactly as `ItemService.applyReveal` already uses them. Nothing in this plan calls a
   Roblox API this repo has not already exercised. The one property whose *replication* behaviour is
   assumed rather than observed is `Highlight.FillTransparency` — it is a normal replicated property
   and is set server-side here, but if a playtest shows the brightness not updating on other clients
   after the first frame, that is the thing to check first.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 2 | §6.5 invariant 1 was written in three comments and asserted nowhere; it holds with **zero margin** at shipped values | High | Fixed by Step 2.2 |
| 4 | `table.clear(monsters)` without a preceding `clearExposed` orphans the Highlight permanently on a living character | High | Fixed by Step 4.4 |
| 4 | The Exposed clear must run on `ENDING`, not only INTERMISSION/IDLE — a glow during ENDING is a mark on a player | Medium | Fixed by Step 4.4 |
| 3 | `Humanoid.Health`/`MaxHealth` is the obvious implementation and is a permanent map-wide role oracle | Critical | Prevented by design; `exploit-auditor` confirms at 5.2 |
| 4 | Two public entry points (`ForceRevert`, `ApplySaltHit`) into one salt path invites a caller that skips the damage | Medium | Fixed by deleting `ForceRevert` at 4.2 |
| 5 | Glow brightness legibility on a phone cannot be checked mechanically | Medium | Open — `playtester`, Step 5.3 |
| — | A weakened-monster speed, sound or non-Exposed visual change would re-create the C14 WalkSpeed brand | Critical | Refused in the preamble; no such code in this plan |
