# Plan: Barrio Population — six forms, real motion, seven interiors

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** none directly. It spends against §5's map requirements and §4.3/§4.5's camouflage
  design, and it is the population half of what `docs/BUILD-PLAN.md` defers to **V15 (HUD v2)** and
  **V21 (sprites and dressing)**. It follows `.claude/plans/feature-barrio-realism-plan/`, which was an
  art pass under `tools/greybox/` only.
- **Description:** Six camouflage forms at three rigs each (18 entities, up from four forms at four),
  per-form territories, hybrid motion — procedural for animals, R15 Humanoids for villagers — detailed
  interiors in all seven kubo including the two currently sealed, and an enhancement pass over the
  ~600 parts still shipping as untextured boxes.
- **Date:** 2026-08-29
- **What the client is told:** **Nothing new.** No remote is added, no remote payload gains a field,
  and `ClientRoundSnapshot` is untouched. `CamouflageUpdatePayload.Form` already carries the form to
  exactly one player — its own — and widening `CamouflageForm` from four literals to six widens that
  existing field's domain without widening its audience. Everything else this plan adds is geometry in
  `workspace`, which replicates to everyone by design and is the mechanic rather than the leak.

  **What this plan changes is not what crosses the wire but what a client can DERIVE from geometry it
  already receives.** That is the whole risk surface, it is invisible to `check:secrecy`, and Phases 2,
  4 and 6 exist for it.

---

### Read this before Phase 1 — the preamble every phase depends on

`npm run plan:phase -- <plan> 1 --with-preamble` serves this section alongside Phase 1. Everything a
later phase needs that is not in its own body is repeated in that phase's body deliberately; this
section is the material that genuinely belongs to all eight.

#### The parity rule, which is this plan's single most important sentence

`MonsterService.enterCamouflage` does not re-skin the player. It hides the player's own body
(`hideCharacter`, `MonsterService.luau:978`) and puppets an ambient rig that was already standing in
the barrio (`AmbientService.PuppetSlot`, `AmbientService.luau:330`). The barrio's visible population is
byte-identical whether or not anyone is hidden — that inversion is V07's fix for a measured Critical,
and every line of this plan preserves it.

The consequence, and it is the thing to hold in your head for all eight phases:

> **Ask what is TRUE of a puppeted rig and FALSE of a free one, for every replicated property. A
> difference is the leak, in either direction.** (`.claude/lessons/absence-is-observable.md`)

**Exactly one difference is permitted, and it is the mechanic:** a puppeted rig moves at the monster's
speed and leaves its leash, because the monster is walking it. §4.5's intended deduction is "which cat
is behaving oddly", so *behaviour under motion* is the signal survivors are supposed to work for.

**Every other difference is a bug.** Resting height, animation state, idle cadence, Humanoid property
values, sound, territory membership, name, tag, attribute. `check:secrecy` is a text tripwire over role
tokens in tag names, attributes and payload fields; it can see none of this, and it will report green
over all of it.

#### Two live defects this plan inherits, both of which must be fixed before rigs get better

**1. Every ambient rig is sunk into the ground, and the disguised one floats above them.**

`buildEntity` sets `body.CFrame = at` (`AmbientService.luau:278`), where `at` is the `AmbientSpawn`
pad's CFrame. `anchor()` builds that pad at `cy = 0.4` and `v()` does not scale Y
(`tools/greybox/barrio.luau:277-279, 653-688`), so every rig's body **centre** sits at y = 0.4. A CAT
body is 1.2 tall, so it is 0.2 studs into the ground; a VILLAGER body is 5.0 tall, so it is 2.1 studs
into the ground.

`PuppetSlot` then does `model:PivotTo(cframe)` with the monster's **HumanoidRootPart** CFrame
(`MonsterService.luau:3256`), whose centre stands roughly 3 studs above the character's feet. So the
camouflaged cat's body centre is at y ≈ 3 while every free cat's is at y = 0.4.

**The disguised animal floats about 2.6 studs above every other animal of its form, permanently, for
every client, with no motion required to read it.** It is a static elevation difference, not a
behavioural one, so it is not the tell §4.5 designed — it is a free answer. Phase 2 fixes it as a pure
function before Phase 5 makes the rigs good enough for anyone to look twice at.

**2. The ambient rig meshes are outside the only triangle budget this repo asserts.**

`tests/barrio-assets.test.luau` sums `Tris` over `ASSETS.Meshes` in the builder against a 27,000
ceiling. The four rig meshes live in `AmbientService.FORM_LOOKS` (`AmbientService.luau:163-193`) and
appear in no registry at all. Four meshes — soon six, at 18 instances — are spent against §5's
non-negotiable mobile budget and counted by nothing. Phase 5 registers them.

#### The §5 budget, stated up front and repaid where it is spent

| Line | Now | After | Where it is repaid |
| --- | --- | --- | --- |
| Ambient rigs | 16 | **18** | `PerForm` 4 → 3, so six forms cost two entities, not eight |
| Rig meshes (tris) | 4, unbudgeted | **6, registered** | brought inside the 27,000 ceiling, not added to it |
| `MapLight` count | 14 | **14** | interiors and lanterns use `Neon`, never a `PointLight` |
| Dressing colliders | 0 | **0** | mesh cladding is `CanCollide = false` over existing greybox collision |
| Crossing time | 34.8s | **30–40s** | two new doorways are single-door and outside the ring |
| Total instances | ~1,141 | **≤ 1,450** | asserted at build time in Phase 8, as colliders and lights already are |

`Config.Debug.SoloTesting` and every other `Debug` flag stay off throughout. `check:debug` refuses a
commit that carries them.

#### Phasing, and why there are eight

Phases 1–6 are game code under `src/` and are the 🔒 half — `exploit-auditor` runs on them.
Phases 7–8 are `tools/greybox/` only and change no game code.

**The task loop caps at 8 iterations at roughly one phase each, so this plan is exactly at the ceiling
and has no room for a repair iteration.** Run it as two: Phases 1–6, then Phases 7–8. Phase 7 depends
on nothing in 1–6 except the crossing-time measurement, so the split is clean.

#### Sixteen of these checks are REGRESSION GATES, not proofs — know which

`verify:plan` run against today's tree, before a line is implemented, reports **23 of 44 steps already
passing**. That is not a bug in the plan and it is not a green light; it is the honest shape of a plan
whose work mostly lands in files that already have suites. Read it this way:

**The 15 steps that FAIL today are the ones proving their own work.** Every new Lune suite
(`camouflage-forms`, `ambient-rig`, `ambient-territory`, `ambient-motion`, `barrio-interiors`) and every
artifact fails until the step creates it. Those are the phase gates that matter.

**Seven of the 23 are legitimate traps** — they pass today *because the mistake has not been made yet*,
and would fail if this step made it. The four `check:config` steps (2.3, 4.3, 5.3, 6.4) each add
literals that must land in `Config` with a waiver; Step 3.3's `barrio-receipt` reconciles the builder's
hand-copied `16` against `Config`'s `PerForm × 6` and genuinely fails if only half the change lands;
and Step 1.3's `ambient-roster` passing **unedited** is precisely the claim that step makes.

**The other sixteen pass either way and prove nothing about their own step.** The five `npm run analyze`
steps are regression protection over a tree that is already green. Worse, eight steps
(3.4, 5.2, 6.6, 7.1, 7.3, 8.1, 8.2, 8.3) are gated on a suite **the step itself extends** —
`barrio-ambient` passes with four forms and with six, so it cannot see the rewrite.

**The fix is free, and it is a habit rather than an edit: for those eight, change the SUITE first and
watch it go red, then change the builder.** That is the red-then-green shape Steps 1.1, 2.1, 3.1, 4.1
and 7.4 carry structurally, and the only reason the existing suites cannot carry it the same way is
that they already exist, so `test -f` says nothing about them. **If a suite did not go red before your
change, you learned nothing from it going green.**

---

## 2. Comprehensive Plan by Phases

### Phase 1: Six forms, and one literal union declared in five places

**Why this phase is first and alone.** `CamouflageForm` is a literal union re-declared in **five
independent places**, and nothing in the repo checks that they agree. Four of the five are Luau type
declarations that widen on `require` — `.claude/lessons/pure-module-unions-widen-in-lists.md` — so a
missed one does not fail loudly; it produces `string` where a literal union was wanted, at a call site
in a different file, which is the exact failure that cost eight fixes and an hour at C21.

The five sites, with their current line numbers:

| # | File | Shape |
| --- | --- | --- |
| 1 | `src/shared/Types.luau:61` | `export type CamouflageForm = "CAT" \| "DOG" \| "PIG" \| "VILLAGER"` |
| 2 | `src/shared/Enums.luau:85-90` | `table.freeze` with a `:: Types.CamouflageForm` cast per member |
| 3 | `src/shared/pure/AmbientRoster.luau:29` | re-declared; Lune has no `script` |
| 4 | `src/shared/pure/CamouflageRules.luau:43` | re-declared, same reason |
| 5 | `src/server/Services/AmbientService.luau:163-193, 360-372, 559-562` | `FORM_LOOKS` keys, `formFromId`, the `spawnForm` call list |

#### Step 1.1: Write the form-consistency suite, and watch it fail

**File:** `tests/camouflage-forms.test.luau`
**Verify:** `test -f tests/camouflage-forms.test.luau`

Written first, against the six-member set, so it **fails on today's four** before anything is edited.
That red is the phase's only evidence that the suite discriminates; a suite written after the widening
passes whether or not it can see anything.

**Gated on existence rather than exit 0, deliberately.** This step's deliverable is a suite that goes
RED — demanding green here would be demanding Step 1.5's work. Step 1.5 widens the last of the seven
sites and is where it turns.

```diff
+--!strict
+--[[
+	tests/camouflage-forms.test.luau
+
+	`CamouflageForm` IS DECLARED IN FIVE PLACES AND NOTHING CHECKED THAT THEY AGREE.
+
+	Four of the five are Luau literal unions and the fifth is a table of keys. A union that drifts does
+	not fail where it is wrong: it widens to plain `string` on `require`, and the analyzer reports the
+	failure at a CALL SITE IN ANOTHER FILE. That is
+	`.claude/lessons/pure-module-unions-widen-in-lists.md`, which cost eight failed fixes at C21
+	because every error named the wrong file.
+
+	SO THIS SUITE READS ALL FIVE AS TEXT AND COMPARES THE SETS. Text, not `require`, for the reason
+	every other `barrio-*` suite gives: Lune has no `game`, `Enums` requires `script.Parent`, and
+	`AmbientService` requires `ReplicatedStorage`. None of the three can be loaded here, and the thing
+	being checked is spelling rather than behaviour.
+
+	THE CANONICAL SET IS DECLARED HERE, ONCE, AND EVERY SITE IS COMPARED TO IT rather than to each
+	other. Comparing sites pairwise passes when all five are wrong in the same way, which is exactly
+	what a careless find-and-replace produces.
+]]
+
+local fs = require("@lune/fs")
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
+--[[
+	§4.3's forms, and the order is the spawn order in `AmbientService.Start`.
+
+	SIX RATHER THAN FOUR, AND THE TWO NEW ONES ARE NOT DECORATION. §5 asks for a population dense
+	enough that "which cat" is a real question; GOAT and CHICKEN are the two animals a rural Philippine
+	barrio actually carries in numbers, and both are TETHERED OR YARD-BOUND in life, which is what
+	makes per-form territories accurate rather than arbitrary.
+]]
+local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }
+
+local function setOf(list: { string }): { [string]: boolean }
+	local set: { [string]: boolean } = {}
+
+	for _, item in list do
+		set[item] = true
+	end
+
+	return set
+end
+
+local CANONICAL = setOf(FORMS)
+
+-- Compare one site's members against the canonical set, in BOTH directions. A site that is missing a
+-- form and a site that carries an extra one are different bugs and both are silent.
+local function compare(site: string, found: { string })
+	local seen = setOf(found)
+
+	check(`{site} declares exactly {#FORMS} forms`, #found == #FORMS, `{#found} found`)
+
+	for _, form in FORMS do
+		check(`{site} declares {form}`, seen[form] == true)
+	end
+
+	for member in seen do
+		check(`{site} declares nothing beyond the canonical set`, CANONICAL[member] == true, member)
+	end
+end
+
+-- Pull the members out of a `"A" | "B" | "C"` union, wherever it is spelled and however it wraps.
+local function unionMembers(source: string, declaration: string): { string }
+	local body = string.match(source, `{declaration}([^\n]*\n?[^\n]*\n?[^\n]*)`)
+	local members: { string } = {}
+
+	if body == nil then
+		return members
+	end
+
+	for member in string.gmatch(body, `"([A-Z_]+)"`) do
+		table.insert(members, member)
+	end
+
+	return members
+end
+
+compare(
+	"Types.luau",
+	unionMembers(fs.readFile("src/shared/Types.luau"), "export type CamouflageForm =")
+)
+compare(
+	"pure/AmbientRoster.luau",
+	unionMembers(fs.readFile("src/shared/pure/AmbientRoster.luau"), "export type CamouflageForm =")
+)
+compare(
+	"pure/CamouflageRules.luau",
+	unionMembers(fs.readFile("src/shared/pure/CamouflageRules.luau"), "export type CamouflageForm =")
+)
+
+--[[
+	`Enums` IS CHECKED THROUGH ITS CASTS, NOT ITS KEYS. `Cat = "CAT" :: Types.CamouflageForm` is the
+	shape, and the CAST is the load-bearing half — CLAUDE.md is explicit that without it the field
+	infers as plain `string` and fails to satisfy the literal union. A member added without its cast
+	would pass a key scan and break at the first call site.
+]]
+local enums = fs.readFile("src/shared/Enums.luau")
+local enumBlock = string.match(enums, "Enums%.CamouflageForm = table%.freeze%({(.-)%}%)")
+
+check("Enums declares a frozen CamouflageForm table", enumBlock ~= nil)
+
+if enumBlock ~= nil then
+	local cast: { string } = {}
+
+	for member in string.gmatch(enumBlock, `"([A-Z_]+)" :: Types%.CamouflageForm`) do
+		table.insert(cast, member)
+	end
+
+	compare("Enums.luau (with its :: Types.CamouflageForm cast)", cast)
+end
+
+--[[
+	`AmbientService` IS THREE SITES IN ONE FILE AND ALL THREE ARE CHECKED SEPARATELY.
+
+	`FORM_LOOKS` says what a form LOOKS like, `formFromId` says which strings NARROW to a form, and
+	`Start` says which forms are SPAWNED. A form present in the first two and missing from the third
+	has a look, a type and no entities — `ClaimSlot` refuses it forever and the Aswang simply never
+	gets that disguise, with nothing anywhere reporting it.
+]]
+local service = fs.readFile("src/server/Services/AmbientService.luau")
+local looksBlock = string.match(service, "local FORM_LOOKS: {.-} =\n\t{(.-)\n\t}")
+
+check("AmbientService declares a FORM_LOOKS table", looksBlock ~= nil)
+
+if looksBlock ~= nil then
+	local looks: { string } = {}
+
+	for member in string.gmatch(looksBlock, "\n\t\t([A-Z_]+) = {") do
+		table.insert(looks, member)
+	end
+
+	compare("AmbientService FORM_LOOKS", looks)
+end
+
+local narrowed: { string } = {}
+
+for member in string.gmatch(service, `if id == "([A-Z_]+)" then`) do
+	table.insert(narrowed, member)
+end
+
+for member in string.gmatch(service, `elseif id == "([A-Z_]+)" then`) do
+	table.insert(narrowed, member)
+end
+
+compare("AmbientService formFromId", narrowed)
+
+local spawned: { string } = {}
+
+for member in string.gmatch(service, `spawnForm%("([A-Z_]+)", placed%)`) do
+	table.insert(spawned, member)
+end
+
+compare("AmbientService Start spawns", spawned)
+
+--[[
+	AND THE MULTIPLIER. `spawnPoints`'s fallback ring sizes itself as `PerForm * 4`, hand-written
+	because the form count is not a value this codebase has. Six forms with a `* 4` still there is a
+	fallback ring of 24 points for 18 entities, or of 16 for 18 — either way the ring is the wrong size
+	and only in the fallback path, which is the path nothing exercises until the map is missing.
+]]
+check(
+	`spawnPoints multiplies PerForm by {#FORMS}, not by 4`,
+	string.find(service, `Config.Ambient.PerForm * {#FORMS}`, 1, true) ~= nil,
+	"the fallback ring is sized from a hand-written form count"
+)
+
+if failures > 0 then
+	error(`{failures} camouflage-forms assertion(s) failed`, 0)
+end
+
+print(`  PASS  camouflage-forms: {checked} assertions over {#FORMS} forms in 7 declaration sites`)
```

#### Step 1.2: Widen the union in `Types.luau` and `Enums.luau`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

```diff
 --[[
-	§4.3. What a revealed Aswang can turn into. Four ambient forms so the barrio's scenery is a place
-	the monster can hide IN rather than a backdrop, and so §4.5's "It's the [animal]!" phrase has a
-	closed set of things it can name.
+	§4.3. What a revealed Aswang can turn into. Six ambient forms so the barrio's scenery is a place
+	the monster can hide IN rather than a backdrop, and so §4.5's "It's the [animal]!" phrase has a
+	closed set of things it can name.
+
+	SIX RATHER THAN FOUR, AND THE POPULATION DID NOT GROW TO PAY FOR IT. `Config.Ambient.PerForm`
+	drops 4 -> 3 in the same change, so the barrio carries 18 entities instead of 16. §5 asks for
+	"3-4 each"; three is inside that and above the secrecy floor `tests/config.test.luau` pins.
+
+	WHY THESE TWO. Both are animals a rural Philippine barrio genuinely carries in numbers, and both
+	are TETHERED OR YARD-BOUND in life rather than free-roaming — goats are tethered and rotated at a
+	field edge, chickens forage a household yard. That is what lets each form have a TERRITORY without
+	the constraint reading as an arbitrary game rule, which matters because the territory is also a
+	constraint on the monster: a pig on the basketball court is now wrong, so the Aswang can only wear
+	a pig near the mud. That is deliberate and it is the counterplay §4.5 asks for.
 
 	NOT A PET SYSTEM, and the distance matters because `check:scope` arms `pets?`. These are forms the
 	Aswang wears, owned by nobody, purchasable never (§8.3).
 ]]
-export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
+export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"
```

And `src/shared/Enums.luau`, where **every member needs its cast** or it infers as plain `string`:

```diff
--- V02, §4.3. The four forms a REVEALED Aswang may wear. §4.5's "It's the [animal]!" phrase names one
--- of these, which is what stops camouflage being unbeatable — a barrio full of scenery becomes a
--- barrio with one monster in it. Villager is in the set because three animals in an empty street is
--- a tell; a fourth option that looks like a person is what makes the guess cost something.
+-- V02, §4.3. The six forms a REVEALED Aswang may wear. §4.5's "It's the [animal]!" phrase names one
+-- of these, which is what stops camouflage being unbeatable — a barrio full of scenery becomes a
+-- barrio with one monster in it. Villager is in the set because animals alone in an empty street is
+-- a tell; an option that looks like a person is what makes the guess cost something.
+--
+-- THE ORDER HERE IS THE SPAWN ORDER in `AmbientService.Start`, and `tests/camouflage-forms.test.luau`
+-- pins all six against every other place the union is written down.
 Enums.CamouflageForm = table.freeze({
 	Cat = "CAT" :: Types.CamouflageForm,
 	Dog = "DOG" :: Types.CamouflageForm,
 	Pig = "PIG" :: Types.CamouflageForm,
+	Goat = "GOAT" :: Types.CamouflageForm,
+	Chicken = "CHICKEN" :: Types.CamouflageForm,
 	Villager = "VILLAGER" :: Types.CamouflageForm,
 })
```

#### Step 1.3: Widen the two pure modules' re-declared copies

**File:** `src/shared/pure/AmbientRoster.luau`
**Verify:** `lune run tests/ambient-roster.test.luau`

Both modules re-declare the union rather than requiring `Types`, because Lune has no `script`. Luau
unions are structural, so the local and the canonical are the same type — which is exactly why drift
here is silent.

```diff
-export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
+export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"
```

The identical line in `src/shared/pure/CamouflageRules.luau:43`:

```diff
 export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
 export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
-export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
+export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"
```

**Neither module's LOGIC changes, and that is the check on this step.** `AmbientRoster` never
enumerates the forms — `claim`, `release`, `freeSlots` and `visibleCount` all compare `slot.Form` to a
parameter — and `CamouflageRules` never mentions a form at all. `tests/ambient-roster.test.luau` and
`tests/camouflage-rules.test.luau` must both stay green **without being edited**. If either needs a
change to pass, a form was enumerated somewhere it should not have been.

#### Step 1.4: `PerForm` 4 → 3, and re-argue the secrecy floor rather than moving past it

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

```diff
 --[[
 	AMBIENT LIFE (V07, §5) — AND THE COUNT IS THE MECHANIC, NOT THE FLAVOUR.
 
 	§5: "3-4 each of cats, dogs, pigs and villager NPCs, wandering. If there is one pig in the
 	barrio, the disguise is meaningless. They need no AI worth the name — a wander loop and an
 	idle is enough. What matters is the *count*."
 
 	SO PerForm IS A BALANCE NUMBER WITH A SECRECY FLOOR UNDER IT, and `tests/config.test.luau`
 	pins it: below 2, a camouflaged Aswang is the ONLY entity of its form once the real one has
 	wandered off, and §4.5's "It's the cat!" stops being a guess. It is the same class of silent
 	invariant as `SaltDamage x (SaltSpawnCount - 1)` — nothing in the game tells you when it has
 	been tuned away.
 
-	THE CEILING IS §5'S MOBILE BUDGET. Four forms at four each is 16 wandering models; whoever
-	builds their appearance counts them against the part and light caps `PerformanceController`
-	already enforces, and V07's are parts with no lights and no particles.
+	THE CEILING IS §5'S MOBILE BUDGET, AND THIS NUMBER DROPPED 4 -> 3 TO PAY FOR TWO NEW FORMS.
+	Six forms at three each is 18 wandering models against the sixteen V07 shipped. Six at four
+	would have been 24 — a 50% rise in the most expensive scenery in the map, to buy a variety the
+	head count does not need.
+
+	THREE IS STILL INSIDE §5's "3-4 each" AND STILL ABOVE THE FLOOR, and the floor is what the
+	drop has to answer to rather than the spec sentence. At 3, claiming one leaves TWO free
+	entities of that form; at 4 it left three. The mechanic degrades from "one of four" to "one of
+	three", which is a real weakening of the disguise and it is the price of six silhouettes
+	instead of four. It is worth paying because the alternative failure is worse: a form whose
+	entities are all in one corner is a form the monster cannot wear anywhere else, and SPREAD is
+	what six forms buys. Below 3 do not tune this without re-reading the floor's argument in
+	`tests/config.test.luau`.
 ]]
 	Ambient = {
-		PerForm = 4,
+		PerForm = 3,
```

And in the same step, the guard the drop makes newly necessary. **The floor assertion stays exactly as
it is** — 3 clears `>= 2` and its argument is unchanged. What is **added** is a ceiling:

**File:** `tests/config.test.luau`

```diff
 check(
 	"Ambient.PerForm >= 2 — a lone entity of a form IS the monster",
 	Config.Ambient.PerForm >= 2,
 	`PerForm={Config.Ambient.PerForm}`
 )
+
+--[[
+	AND THE CEILING, WHICH ONLY BECAME BREAKABLE WHEN THE FORM COUNT STOPPED BEING FOUR.
+
+	§5 says "3-4 each" and the floor above says "at least 2". Nothing said "at most 4" — under four
+	forms nobody would raise it, because 4 x 4 was already the largest ambient population anyone had
+	costed. At six forms, `PerForm = 5` is 30 wandering rigs on a phone, which §5's mobile budget
+	refuses and which no error message would ever mention.
+
+	PINNED AGAINST THE SPEC SENTENCE RATHER THAN AGAINST A ROUND NUMBER, so the failure message can
+	point at the thing being violated.
+]]
+check(
+	"Ambient.PerForm <= 4 — §5 asks for '3-4 each' and 60% of players are on a phone",
+	Config.Ambient.PerForm <= 4,
+	`PerForm={Config.Ambient.PerForm}`
+)
```

**`tests/barrio-ambient.test.luau` also reads `PerForm` and will go red at this step**, because it
multiplies by a hard-coded four and asserts the builder sites exactly that many points. That is
correct and expected: it is the map contract noticing that the population changed, and Phase 3 is where
the map answers. Leave it red across Phases 1 and 2 rather than weakening it here.

#### Step 1.5: Widen `AmbientService`'s form surface

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `lune run tests/camouflage-forms.test.luau`

**This is the step where Step 1.1's suite finally goes green**, because `AmbientService` is the last
three of its seven declaration sites. Gated on the suite rather than on `analyze` for that reason: the
analyzer is happy with four forms and six, and the suite is the only thing that knows how many there
are supposed to be.

Three sites in one file, plus the fallback multiplier. `FORM_LOOKS` gains two rows carrying the
**fallback box** only — the mesh and texture ids arrive in Phase 5, and a row with an empty `Mesh`
falls back to a coloured box by the path the file already documents, which is strictly better than a
missing entity.

```diff
 		VILLAGER = {
 			-- The tall one, and that is the whole of what these four silhouettes must convey: §4.5's
 			-- deduction is "which cat", never "is that a cat".
 			Size = Vector3.new(2.0, 5.0, 1.2), -- config-ok: rig proportions, not balance
 			Colour = Color3.fromRGB(96, 108, 128), -- config-ok: fallback rig colour, not balance
 			Mesh = "rbxassetid://131254025115965", -- config-ok: generated mesh asset, not balance
 			Texture = "rbxassetid://81445534883746", -- config-ok: generated texture asset, not balance
 		},
+		--[[
+			GOAT AND CHICKEN ARRIVE WITH NO MESH AND THAT IS DELIBERATE (Phase 1 of 8).
+
+			An empty `Mesh` fails `CreateMeshPartAsync`, `buildEntity` warns and builds the coloured
+			box, and the SLOT STILL EXISTS — which is the property that matters. A form declared in
+			the type and absent from the roster is a form `ClaimSlot` refuses forever, and the Aswang
+			simply never gets that disguise with nothing reporting it. A box is ugly; a missing slot
+			is a mechanic quietly not existing. Phase 5 fills these two in.
+
+			THE SIZES ARE RESEARCHED, NOT GUESSED, and both are SMALL. The Philippine native goat is
+			10.5-24.4 kg with erect ears — knee-height on an adult, not a Western dairy goat. The
+			native chicken is 1.0-1.3 kg. Six silhouettes have to stay tellable apart in fog at
+			distance (§4.5: "which cat", never "is that a cat"), and the chicken is the one at real
+			risk of reading as a rock. See `references/research-01-barrio-animals.md`.
+		]]
+		GOAT = {
+			Size = Vector3.new(1.2, 2.2, 2.4), -- config-ok: rig proportions, not balance
+			Colour = Color3.fromRGB(74, 64, 58), -- config-ok: fallback rig colour, not balance
+			Mesh = "", -- config-ok: filled in at Phase 5; empty falls back to the box
+			Texture = "", -- config-ok: filled in at Phase 5
+		},
+		CHICKEN = {
+			Size = Vector3.new(0.8, 1.1, 1.4), -- config-ok: rig proportions, not balance
+			Colour = Color3.fromRGB(150, 108, 52), -- config-ok: fallback rig colour, not balance
+			Mesh = "", -- config-ok: filled in at Phase 5; empty falls back to the box
+			Texture = "", -- config-ok: filled in at Phase 5
+		},
 	}
```

The narrowing function, which is what stops an unknown id being cast into a payload:

```diff
 local function formFromId(id: string): Types.CamouflageForm?
 	if id == "CAT" then
 		return "CAT"
 	elseif id == "DOG" then
 		return "DOG"
 	elseif id == "PIG" then
 		return "PIG"
+	elseif id == "GOAT" then
+		return "GOAT"
+	elseif id == "CHICKEN" then
+		return "CHICKEN"
 	elseif id == "VILLAGER" then
 		return "VILLAGER"
 	end
 
 	return nil
 end
```

The spawn list, which stays six calls rather than becoming a loop:

```diff
 	--[[
-		FOUR CALLS RATHER THAN A LOOP OVER A LIST, and the order is the spawn order. A list would put
-		the literals back inside a table and widen them again, which is the whole reason this is
-		written out.
+		SIX CALLS RATHER THAN A LOOP OVER A LIST, and the order is the spawn order. A list would put
+		the literals back inside a table and widen them again, which is the whole reason this is
+		written out — and six is exactly the length at which someone will be tempted to "tidy" it
+		into a loop. `.claude/lessons/pure-module-unions-widen-in-lists.md` is why that tidy does not
+		typecheck, and the two shapes that fail are named in this file's header.
 	]]
 	local placed = 0
 	placed = spawnForm("CAT", placed)
 	placed = spawnForm("DOG", placed)
 	placed = spawnForm("PIG", placed)
+	placed = spawnForm("GOAT", placed)
+	placed = spawnForm("CHICKEN", placed)
 	placed = spawnForm("VILLAGER", placed)
```

And the fallback ring's multiplier, which is the one that fails only when the map is missing:

```diff
-	local total = Config.Ambient.PerForm * 4 -- config-ok: four forms, and there are four of them
+	-- config-ok: the form count, not a balance knob. `tests/camouflage-forms.test.luau` pins this
+	-- against the union so the fallback ring cannot be sized for a form count that no longer exists.
+	local total = Config.Ambient.PerForm * 6
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

- **`tests/barrio-ambient.test.luau` goes red at Step 1.4 and stays red until Phase 3.** Expected, and
  named here so it is not "fixed" by weakening the suite. It is the map contract correctly noticing
  that the population changed.
- **`check:scope` arms `pets?`.** Two new animals is exactly the shape that check exists to catch, and
  the defence is the one `Types.luau` already writes down: these are forms the Aswang wears, owned by
  nobody, purchasable never (§8.3). If `check:scope` objects, the answer is a waiver with that reason —
  not a rename.
- **`Config.Ambient.PerForm` is parsed as text by `tests/barrio-ambient.test.luau:36`** with a
  two-tab-indent pattern. Re-indenting or re-nesting the key breaks that parse with an assert that says
  so; do not move it.
- **The `-- config-ok:` waivers on `FORM_LOOKS` are load-bearing.** `check:config` flags every literal
  in a service, and rig proportions are not balance. Two new rows means eight new waivers, each with a
  reason.

---

### Phase 2: The resting height, as a pure function — the leak that needs no motion to read

**The finding, restated here because a phase is read on its own.** `buildEntity` seats a free rig by
`body.CFrame = at` (`AmbientService.luau:278`), where `at` is the `AmbientSpawn` pad's CFrame — centre
y = 0.4, because `anchor()` calls `box(name, cx, 0.4, cz, ...)` and `v()` does not scale Y
(`tools/greybox/barrio.luau:277-279, 653-688`). `PuppetSlot` seats the claimed rig by
`model:PivotTo(cframe)` with the monster's **HumanoidRootPart** CFrame (`MonsterService.luau:3256`),
whose centre is roughly 3 studs above the character's feet.

| | Body centre Y | Cat body 1.2 tall | Villager body 5.0 tall |
| --- | --- | --- | --- |
| Free rig | pad's 0.4 | bottom at −0.2 — 0.2 studs into the ground | bottom at −2.1 — 2.1 studs into the ground |
| Puppeted rig | root's ≈ 3.0 | bottom at 2.4 — **floating** | bottom at 0.5 — floating |

**Both halves are wrong and the difference between them is the leak.** A survivor does not need to
watch a cat move oddly; they need to notice that one cat is in the air. That is a static property of a
replicated `CFrame`, readable in one frame, and no amount of good motion work in Phase 4 hides it.

**Two more reasons this is Phase 2 and not Phase 7.** Phase 5 replaces these rigs with meshes good
enough that a player looks at them, and a well-made floating goat is more conspicuous than a floating
box. And the sinking is worse for tall forms, so the Humanoid villagers Phase 6 introduces would
inherit the largest error in the set.

#### Step 2.1: Write `tests/ambient-rig.test.luau` against a module that does not exist

**File:** `tests/ambient-rig.test.luau`
**Verify:** `test -f tests/ambient-rig.test.luau`

**Gated on the file existing, not on it passing, and the weakness is deliberate.** This step's whole
point is that the suite is written **before** the module and **fails** — so a check demanding exit 0
would be asking this step to do Step 2.2's work. `test -f` proves the deliverable; Step 2.2 proves it
green. Watch the red yourself: it is the only evidence the suite discriminates.

The property is an **equality between two functions**, which is why it belongs in Lune rather than in a
screenshot: given the same ground, a free rig and a puppeted rig of the same form put their feet at the
same Y, for every form height and every root height.

```diff
+--!strict
+--[[
+	tests/ambient-rig.test.luau
+
+	THE PROPERTY: A DISGUISED ANIMAL AND A REAL ONE STAND ON THE SAME GROUND.
+
+	`AmbientService` seats a free rig from its spawn pad and a CLAIMED rig from the monster's
+	HumanoidRootPart. Those are two different reference points — the pad's centre is at y = 0.4 and a
+	character's root centre is about 3 studs above its own feet — so before this module the disguised
+	cat floated roughly 2.6 studs above every real cat, permanently, for every client.
+
+	THAT IS NOT THE TELL §4.5 DESIGNED. The intended deduction is "which cat is behaving oddly", which
+	costs a survivor attention and time and can be wrong. An elevation offset costs nothing, is
+	readable in a single frame without the monster moving, and is never wrong.
+	`.claude/lessons/absence-is-observable.md`: the leak is a DIFFERENCE between entities, and
+	`check:secrecy` — a text tripwire over role tokens — cannot see a number.
+
+	WHY A PURE MODULE FOR TWO DIVISIONS. Because the property is an EQUALITY BETWEEN TWO CALL SITES in
+	two different files, and that is exactly the shape no screenshot and no analyzer checks. A test can
+	state "these agree for all inputs" once; a reader cannot.
+
+	THE INPUTS ARE PLAIN NUMBERS AND NOTHING HERE KNOWS WHAT A PLAYER IS. Feeding it a UserId would be
+	the only way to make it leak, and there is no parameter for one.
+]]
+
+local AmbientRig = require("../src/shared/pure/AmbientRig")
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
+local EPSILON = 1e-6
+
+local function near(a: number, b: number): boolean
+	return math.abs(a - b) < EPSILON
+end
+
+-- The six forms' body heights, from `AmbientService.FORM_LOOKS`. Copied rather than required, because
+-- that file requires `ReplicatedStorage` and Lune has no `game`; the range is what matters here and
+-- it deliberately spans the smallest form and the largest.
+local HEIGHTS = { 1.1, 1.2, 1.9, 1.8, 2.2, 5.0 }
+local GROUNDS = { -4, 0, 0.1, 3.5, 18 }
+-- A character's foot-to-root distance. R15 default is about 3; the transform SCALES the avatar, so
+-- this is a range rather than a constant and that is the whole reason it is a parameter.
+local FOOT_OFFSETS = { 1.65, 2.0, 3.0, 4.2 }
+
+--[[
+	THE ONE THAT MATTERS. Over every combination, a claimed rig and a free rig of the same form on the
+	same ground occupy the SAME Y. This is the assertion that would have caught the shipped defect.
+]]
+for _, height in HEIGHTS do
+	for _, ground in GROUNDS do
+		local free = AmbientRig.restingY(ground, height)
+
+		for _, footOffset in FOOT_OFFSETS do
+			-- A monster standing on that same ground has its root `footOffset` above it.
+			local puppeted = AmbientRig.puppetY(ground + footOffset, footOffset, height)
+
+			check(
+				`h={height} ground={ground} foot={footOffset}: claimed and free rigs share a Y`,
+				near(free, puppeted),
+				`free={free}, puppeted={puppeted}, delta={puppeted - free}`
+			)
+		end
+	end
+end
+
+-- And the half that fixes the OTHER defect: a free rig rests ON the ground, not buried in it.
+for _, height in HEIGHTS do
+	for _, ground in GROUNDS do
+		check(
+			`h={height} ground={ground}: the rig's feet are on the ground, not under it`,
+			near(AmbientRig.restingY(ground, height) - height / 2, ground),
+			`bottom={AmbientRig.restingY(ground, height) - height / 2}, ground={ground}`
+		)
+	end
+end
+
+--[[
+	MONOTONIC IN THE ROOT, so a monster walking up a ramp carries its disguise up with it. A function
+	that clamped or floored would satisfy every equality above and freeze the cat at ground level while
+	the monster climbed — a disguise that detaches on a slope, which is worse than one that floats.
+]]
+local previous = AmbientRig.puppetY(0, 3, 1.2)
+
+for rootY = 1, 40 do
+	local current = AmbientRig.puppetY(rootY, 3, 1.2)
+
+	check(`puppetY rises with the root at rootY={rootY}`, current > previous)
+	previous = current
+end
+
+if failures > 0 then
+	error(`{failures} ambient-rig assertion(s) failed`, 0)
+end
+
+print(`  PASS  ambient-rig: {checked} assertions over {#HEIGHTS} forms x {#GROUNDS} grounds`)
```

#### Step 2.2: `src/shared/pure/AmbientRig.luau`

**File:** `src/shared/pure/AmbientRig.luau`
**Verify:** `lune run tests/ambient-rig.test.luau`

```diff
+--!strict
+--[[
+	AmbientRig — where an ambient body sits, so that a disguised one sits in the same place.
+
+		restingY(groundY, bodyHeight)            -> the Y a FREE rig's centre takes
+		puppetY(rootY, footOffset, bodyHeight)   -> the Y a CLAIMED rig's centre takes
+
+	TWO FUNCTIONS THAT MUST AGREE, WHICH IS THE ENTIRE REASON THIS FILE EXISTS. `AmbientService` seats
+	free rigs from a spawn pad and `MonsterService` drives claimed ones from a HumanoidRootPart. Those
+	are different reference points in different files, and before this module they disagreed by about
+	2.6 studs — so the camouflaged animal FLOATED above every real one of its form, permanently and
+	visibly, with nothing in the game or in `npm run verify` reporting it.
+
+	`check:secrecy` CANNOT SEE THIS AND NEVER COULD. It is a text tripwire over role tokens in tag
+	names, attributes and payload fields. The leak here is a NUMBER that differs between two entities,
+	which is `.claude/lessons/absence-is-observable.md` in its purest form: the difference is the leak,
+	and it does not need a name to be readable.
+
+	CALLABLE BY ANY CLIENT AND THAT IS FINE. `src/shared` maps wholesale into `ReplicatedStorage`, so a
+	LocalScript can require and RUN this. What it learns is that a body's centre is half its height
+	above the ground, which is arithmetic every client can already perform on parts it can see. There
+	is no seed here, no draw, and no client-suppliable input — the two conditions CLAUDE.md names for a
+	pure module to become a leak.
+
+	NO `script.Parent` REQUIRES — Lune has no `script`, and a module that reached for `Types` would
+	stop being runnable from a terminal, which is the whole point of putting it here.
+]]
+
+local AmbientRig = {}
+
+--[[
+	WHERE A FREE RIG'S CENTRE GOES. Half its own height above the ground it stands on.
+
+	`groundY` IS THE GROUND, NOT THE SPAWN PAD. The pad is a 0.8-tall marker whose CENTRE sits at 0.4,
+	so using its CFrame directly buried every rig by half its own height — 0.2 studs for a cat and 2.1
+	for a villager. Taller forms sank further, which is why the fault was easiest to see on exactly the
+	form Phase 6 rebuilds as a Humanoid.
+]]
+function AmbientRig.restingY(groundY: number, bodyHeight: number): number
+	return groundY + bodyHeight / 2
+end
+
+--[[
+	WHERE A CLAIMED RIG'S CENTRE GOES, given the monster's root.
+
+	`footOffset` IS PASSED IN RATHER THAN ASSUMED, and that is the parameter this whole module turns
+	on. The transform SCALES the avatar (§4.3), so the distance from a monster's root to its feet is
+	not the R15 default and is not a constant. Hard-coding 3 here would put the disguise back in the
+	air for exactly the state the monster is in whenever it is allowed to camouflage — which is to say,
+	always.
+
+	IT IS ALGEBRAICALLY `restingY` WITH THE GROUND RECOVERED FROM THE ROOT, and it is written that way
+	on purpose: the ground is `rootY - footOffset`, and everything after that is the free rig's own
+	rule. Two expressions that must agree are one expression called twice.
+]]
+function AmbientRig.puppetY(rootY: number, footOffset: number, bodyHeight: number): number
+	return AmbientRig.restingY(rootY - footOffset, bodyHeight)
+end
+
+return AmbientRig
```

#### Step 2.3: Seat free rigs on the ground in `buildEntity`

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run check:config`

Gated on `check:config` rather than on `analyze`, because the failure this step can actually produce is
the three probe numbers being typed into the service instead of into `Config` — which typechecks
perfectly and is exactly what `check:config` exists to catch.

The ground under a pad is found by raycast rather than assumed to be zero, because the barrio is not
flat and the kubo floors Phase 7 fills are not at y = 0. The pad's own underside is the fallback.

```diff
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local AmbientRoster = require(Shared.pure.AmbientRoster)
+local AmbientRig = require(Shared.pure.AmbientRig)
 local Config = require(Shared.Config)
 local Types = require(Shared.Types)
```

```diff
+--[[
+	THE GROUND UNDER A SPAWN POINT, MEASURED RATHER THAN ASSUMED.
+
+	The pad is a marker, not a floor: `anchor()` builds it 0.8 tall with its CENTRE at y = 0.4, and it
+	is `CanCollide = false`, so the surface a rig actually stands on is whatever is beneath it. Seating
+	a body at the pad's own CFrame buried it by half its height, which is what shipped.
+
+	THE RAYCAST IGNORES `AmbientLife` so a rig cannot land on another rig — sixteen entities spawning
+	in sequence would otherwise stack wherever two pads overlap, and the second one's ground would be
+	the first one's back.
+
+	A MISS FALLS BACK TO THE PAD'S UNDERSIDE, not to zero. A pad floating over a hole in the map is a
+	map bug; putting the rig at the origin's height would move it across the barrio, which turns a
+	visible local error into an invisible global one.
+]]
+local function groundYUnder(at: CFrame): number
+	local parameters = RaycastParams.new()
+
+	parameters.FilterType = Enum.RaycastFilterType.Exclude
+	parameters.FilterDescendantsInstances = if entities ~= nil then { entities :: Folder } else {}
+
+	local hit = workspace:Raycast(
+		at.Position + Vector3.new(0, Config.Ambient.GroundProbeUp, 0),
+		Vector3.new(0, -Config.Ambient.GroundProbeDown, 0),
+		parameters
+	)
+
+	if hit ~= nil then
+		return hit.Position.Y
+	end
+
+	return at.Position.Y - Config.Ambient.SpawnPadHalfHeight
+end
+
 local function buildEntity(form: Types.CamouflageForm, index: number, at: CFrame): Model
```

```diff
 	body.Name = "Body"
 	body.Size = look.Size
 	body.Anchored = true
 	body.CanCollide = false
 	body.CanQuery = false
 	body.CanTouch = false
-	body.CFrame = at
+	--[[
+		SEATED ON THE GROUND, NOT ON THE PAD. See `AmbientRig`'s header: this expression and
+		`PuppetSlot`'s below are the two that must agree, and `tests/ambient-rig.test.luau` is where
+		that agreement is stated over every form height rather than left to a reader.
+	]]
+	body.CFrame = CFrame.new(
+		at.Position.X,
+		AmbientRig.restingY(groundYUnder(at), look.Size.Y),
+		at.Position.Z
+	) * (at - at.Position)
 	body.Parent = model
```

And the three probe numbers, which are tunables and therefore `Config`'s:

```diff
 	Ambient = {
 		PerForm = 3,
+		--[[
+			THE GROUND PROBE (Phase 2). How far above a spawn pad the ray starts and how far down it
+			looks, in studs, plus the pad's own half-height as the fallback when it hits nothing.
+
+			THESE ARE MAP-SHAPED NUMBERS, NOT BALANCE ONES, and they are here anyway because
+			`check:config` does not distinguish and a literal in a service is a literal nobody finds.
+			`SpawnPadHalfHeight` MUST TRACK `anchor()` in `tools/greybox/barrio.luau`, which builds the
+			pad 0.8 tall — the two files cannot import each other, so this is the seam, and it is only
+			the FALLBACK path, which is the path nothing exercises until the map has a hole in it.
+		]]
+		GroundProbeUp = 6,
+		GroundProbeDown = 24,
+		SpawnPadHalfHeight = 0.4,
```

#### Step 2.4: Seat the puppeted rig on the ground in `PuppetSlot`

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run check:secrecy`

```diff
 --[[
 	DRIVE A CLAIMED ENTITY TO WHERE THE MONSTER IS. (V07, §4.3) Called every Heartbeat by
 	`MonsterService` for each camouflaged Aswang.
+
+	IT TAKES A FOOT OFFSET NOW, AND THAT ARGUMENT CLOSED A LEAK THAT NEEDED NO MOTION TO READ.
+
+	This function used to pivot the model straight onto the monster's HumanoidRootPart CFrame. A root
+	centre stands about 3 studs above its own feet and a free rig's centre sat at its pad's 0.4, so
+	the disguised animal FLOATED roughly 2.6 studs above every real one of its form — a static
+	difference in a replicated `CFrame`, readable in one frame by any client, and never wrong.
+
+	THAT IS A DIFFERENT KIND OF SIGNAL FROM THE ONE §4.5 INTENDS. "Which cat is behaving oddly" costs
+	a survivor attention and can mislead them. "Which cat is in the air" costs nothing and cannot.
+	`.claude/lessons/absence-is-observable.md`, and `check:secrecy` is a text tripwire that will report
+	green over every version of this function.
 ]]
-function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame)
+function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame, footOffset: number)
 	if slotIndex == nil then
 		return
 	end
 
 	local slot = roster[slotIndex]
 	local model = models[slotIndex]
 
 	if slot == nil or not slot.Claimed or model == nil then
 		return
 	end
 
-	model:PivotTo(cframe)
+	local body = model.PrimaryPart
+
+	if body == nil then
+		return
+	end
+
+	--[[
+		THE ROTATION IS THE MONSTER'S AND THE HEIGHT IS THE RIG'S. Taking the whole CFrame gave the
+		right facing and the wrong elevation; taking only the position would lose the facing, and a cat
+		that always points north is a second tell for the price of fixing the first.
+	]]
+	model:PivotTo(
+		CFrame.new(
+			cframe.Position.X,
+			AmbientRig.puppetY(cframe.Position.Y, footOffset, body.Size.Y),
+			cframe.Position.Z
+		) * (cframe - cframe.Position)
+	)
 end
```

#### Step 2.5: Pass the monster's own foot offset from `MonsterService`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

```diff
+--[[
+	HOW FAR THIS CHARACTER'S ROOT IS ABOVE ITS OWN FEET (Phase 2).
+
+	MEASURED, NOT CONSTANT, BECAUSE THE TRANSFORM SCALES THE AVATAR (§4.3). The R15 default is about
+	3 studs and a scaled monster's is not, so a hard-coded 3 would put the disguise back in the air for
+	exactly the state the monster is always in when it is allowed to camouflage.
+
+	`Humanoid.HipHeight` IS THE UNVERIFIED HALF OF THIS AND IT IS IN FOLLOW UPS. This plan has NOT
+	confirmed in this codebase whether HipHeight measures from the root's centre or from its underside
+	for an R15 rig, and the two answers differ by `root.Size.Y / 2`. The expression below assumes the
+	underside. IT IS WRITTEN TO FAIL VISIBLY RATHER THAN SUBTLY: Step 2.6 photographs a puppeted rig
+	beside a free one, and if the offset is wrong the rig sits a consistent one-root-half high or low
+	in every capture. Confirm it there and correct the sign here; do not infer it from the docs.
+]]
+local function footOffsetOf(character: Model): number
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+	local root = rootOf(character)
+
+	if humanoid == nil or root == nil then
+		return Config.Monster.DefaultFootOffset
+	end
+
+	return humanoid.HipHeight + root.Size.Y / 2
+end
```

```diff
 	RunService.Heartbeat:Connect(function()
 		for userId, monster in monsters do
 			if not monster.Camouflaged then
 				continue
 			end
 
 			local player = Players:GetPlayerByUserId(userId)
 			local character = if player ~= nil then player.Character else nil
 			local root = if character ~= nil then rootOf(character) else nil
 
-			if root ~= nil then
-				AmbientService.PuppetSlot(monster.AmbientSlot, root.CFrame)
+			if root ~= nil and character ~= nil then
+				AmbientService.PuppetSlot(
+					monster.AmbientSlot,
+					root.CFrame,
+					footOffsetOf(character)
+				)
 			end
 		end
 	end)
```

```diff
 		CorpseDuration = 45,
+		--[[
+			THE FALLBACK FOOT OFFSET (Phase 2), used only when a camouflaged monster's character has
+			no Humanoid or no root — which is a character mid-respawn, and a frame or two long.
+
+			ROUGHLY THE R15 DEFAULT, so the one frame it covers looks like every other frame. A zero
+			here would drop the disguised animal to the monster's root height for that frame, which is
+			the exact flicker this whole phase removes.
+		]]
+		DefaultFootOffset = 3,
```

#### Step 2.6: Confirm the fix in the running game

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/rig-height.md`

Two rigs of one form standing side by side, one puppeted and one free, in one capture at eye level.
Then the same for VILLAGER, which is the tallest form and therefore where a wrong `HipHeight` reading
shows most.

**This step deliberately carries no `Verify:` line.** Its real proof is a screenshot, and inventing a
`grep` here would report green over a rig floating exactly one root-half above its neighbour —
which is the failure mode Step 2.5's `HipHeight` note predicts. `verify-plan` reports this as
`unverifiable` and `next-phase.mjs` marks the phase `needs-human`, which is the accurate outcome.

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

- **`Humanoid.HipHeight`'s reference point is not verified in this codebase.** Nothing in `src/`
  reads it today. The two possible readings differ by `root.Size.Y / 2` ≈ 1 stud, which is small enough
  to look like a modelling choice and large enough to be a tell. Step 2.6 is the only thing that can
  settle it. In Follow Ups.
- **`workspace:Raycast` runs once per rig at boot, not per frame.** 18 casts inside `Start`. If it ever
  moves into the wander tick it becomes 18 casts a frame on a phone, which §5's budget refuses.
- **`groundYUnder` reads `entities`, which is `nil` until `Start` creates the folder.** The nil branch
  is written and is the boot-order case, not a defensive nicety — `buildEntity` is called from inside
  `spawnForm` after the folder exists, but the guard costs nothing and the ordering is not this
  function's to depend on.
- **`PuppetSlot`'s signature changed and it has exactly one caller** (`MonsterService.luau:3256`). A
  third argument added to a two-argument call site is an analyzer error rather than a silent nil, which
  is why the parameter is not optional.
- **Nothing here is keyed by player and no new instance is created.** The claim still moves nothing and
  reparents nothing, so V07's `ChildRemoved` Critical stays closed.

---

### Phase 3: Territories — and the constraint on the Aswang, made mutual

**Territories close a teleport that is live today, and that is the real reason this phase exists.**

A claim moves nothing in the instance tree — that is V07's fix and it holds. But the next Heartbeat
after a claim, `PuppetSlot` pivots the claimed model onto the monster's CFrame
(`MonsterService.luau:3256`). The monster is wherever it is standing; the rig was at its spawn point.
**So camouflaging jerks an ambient animal across the barrio in one frame** — a pig vanishes from the
well and reappears two hundred studs away beside nothing.

Today that reads as "a pig appeared", because all sixteen entities look alike and are scattered.
**With territories it reads as an answer**, because a pig on the road is categorically wrong. Adding
territories without addressing the jump would make a tell sharper, not blunter.

**The fix is the mechanic the user asked for, made mechanical rather than aspirational.** A claim is
refused unless the monster is standing inside a territory of that form. Then the entity never travels
far, the constraint the user accepted is *enforced* rather than merely signalled, and the plumbing for
it already exists: `AmbientRoster.claim` takes a `preferIndex` hint precisely so the server can choose
which slot without putting a draw in a replicated module (`AmbientRoster.luau:75-88`).

**The Aswang is told nothing new by this.** The refusal verdict `CAMO_NO_SLOT` already exists and is
sent to exactly one player about themselves (`Types.CamouflageUpdatePayload`). What it now encodes is
"there is no pig territory where *you* are standing" — a fact about the requester's own position,
which that client already has.

#### Step 3.1: The territory suite, before the territories

**File:** `tests/ambient-territory.test.luau`
**Verify:** `test -f tests/ambient-territory.test.luau`

**Gated on existence, not on exit 0**, for Step 2.1's reason: the suite is written against a module
that does not exist yet, so demanding green here would be demanding Step 3.2's work. Step 3.2 proves it
passes.

Two properties, and both are fairness properties rather than correctness ones — which is exactly why
they need writing down. A form whose three territories are all in one corner is a form the monster can
only wear in that corner; a form with fewer territories than `PerForm` puts two rigs on one point.

```diff
+--!strict
+--[[
+	tests/ambient-territory.test.luau
+
+	WHICH FORM MAY STAND WHERE, AND THE TWO PROPERTIES THAT KEEP THAT FAIR.
+
+	Per-form territories are a real constraint on the ASWANG, not only on the scenery: a pig on the
+	basketball court is wrong, so the monster can only wear a pig near mud. That is deliberate and it
+	is good counterplay — but it is only fair if the territories are SPREAD. Three pig territories all
+	in the south-east is a rule that says "you may not hide as a pig anywhere you are likely to be",
+	and nothing in the game would ever say so.
+
+	SO THE TWO ASSERTIONS ARE COVERAGE AND SPREAD, and both are about the monster's options rather
+	than about the animals. The animals are fine wherever they are put.
+
+	IT ALSO PINS THE CLAIM RADIUS AGAINST THE WANDER RADIUS, which is the invariant that decides
+	whether the constraint has any teeth. See the check's own comment.
+]]
+
+local AmbientTerritory = require("../src/shared/pure/AmbientTerritory")
+local Config = require("../src/shared/Config")
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
+local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }
+
+--[[
+	The eighteen points, mirroring `AMBIENT_POINTS` in `tools/greybox/barrio.luau`. Duplicated rather
+	than parsed, because THIS suite is about the RULE and `tests/barrio-ambient.test.luau` is about the
+	MAP — and that suite asserts the two lists agree, so the duplication is checked rather than trusted.
+]]
+local POINTS = {
+	{ Form = "CAT", X = 34, Z = -100 },
+	{ Form = "CAT", X = -100, Z = 34 },
+	{ Form = "CAT", X = 96, Z = 100 },
+	{ Form = "DOG", X = 0, Z = -76 },
+	{ Form = "DOG", X = -130, Z = -44 },
+	{ Form = "DOG", X = 62, Z = 130 },
+	{ Form = "PIG", X = -64, Z = 44 },
+	{ Form = "PIG", X = -70, Z = -104 },
+	{ Form = "PIG", X = 108, Z = 108 },
+	{ Form = "GOAT", X = 146, Z = -70 },
+	{ Form = "GOAT", X = -124, Z = 118 },
+	{ Form = "GOAT", X = 128, Z = 148 },
+	{ Form = "CHICKEN", X = -92, Z = -78 },
+	{ Form = "CHICKEN", X = 92, Z = -78 },
+	{ Form = "CHICKEN", X = 78, Z = 92 },
+	{ Form = "VILLAGER", X = -78, Z = -64 },
+	{ Form = "VILLAGER", X = 78, Z = 64 },
+	{ Form = "VILLAGER", X = -42, Z = 30 },
+}
+
+-- 1. COVERAGE. Every form has at least `PerForm` territories, or two rigs share one point and stand
+-- inside each other — which looks like a rendering bug and is the one placement fault a player
+-- reports as "the game is broken" rather than as "that pig is odd".
+for _, form in FORMS do
+	local owned = AmbientTerritory.pointsFor(POINTS, form)
+
+	check(
+		`{form} has at least PerForm ({Config.Ambient.PerForm}) territories`,
+		#owned >= Config.Ambient.PerForm,
+		`{#owned} territories`
+	)
+end
+
+-- 2. SPREAD. No form's territories are all in one quadrant. This is the fairness half: it bounds how
+-- much of the map a given disguise is unavailable in.
+for _, form in FORMS do
+	local owned = AmbientTerritory.pointsFor(POINTS, form)
+	local quadrants: { [string]: boolean } = {}
+	local distinct = 0
+
+	for _, point in owned do
+		local key = (if point.Z < 0 then "N" else "S") .. (if point.X < 0 then "W" else "E")
+
+		if not quadrants[key] then
+			quadrants[key] = true
+			distinct += 1
+		end
+	end
+
+	check(
+		`{form}'s territories span at least 3 quadrants`,
+		distinct >= 3,
+		`{distinct} quadrant(s) for {#owned} territories`
+	)
+end
+
+--[[
+	3. THE CLAIM RADIUS HAS TO BE SMALLER THAN THE WANDER RADIUS, and this is the invariant that
+	decides whether the constraint means anything at all.
+
+	A free rig roams `WanderRadius` from its point. If the monster may claim from FURTHER than that, it
+	can hide as a pig standing somewhere no real pig has ever been — the territory becomes advisory and
+	the whole tactical constraint the design bought evaporates, silently, with every test still green.
+
+	IT IS ALSO THE TELEPORT BOUND. On claim the entity is driven to the monster, so this number IS how
+	far an ambient animal can be seen to jump. Smaller is a tighter constraint and a smaller jump; the
+	cost is that camouflage is refused more often, which is a V16 balance question and not a
+	correctness one.
+]]
+check(
+	"Ambient.ClaimRadius < Ambient.WanderRadius — or the territory is advisory",
+	Config.Ambient.ClaimRadius < Config.Ambient.WanderRadius,
+	`claim={Config.Ambient.ClaimRadius}, wander={Config.Ambient.WanderRadius}`
+)
+
+-- 4. THE LOOKUP ITSELF. `nearestFreeIndex` must refuse rather than return a far one, because the
+-- refusal IS the mechanic — a version that fell back to the nearest at any distance would pass every
+-- assertion above and restore the map-wide teleport.
+local free = { true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
+
+check(
+	"a monster standing on a PIG territory may claim it",
+	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", -64, 44, 20) == 7
+)
+check(
+	"a monster far from every PIG territory is refused",
+	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", 0, 0, 20) == nil
+)
+check(
+	"a claimed slot is skipped and the next nearest is refused if out of range",
+	AmbientTerritory.nearestFreeIndex(
+		POINTS,
+		{ true, true, true, true, true, true, false, true, true, true, true, true, true, true, true, true, true, true },
+		"PIG",
+		-64,
+		44,
+		20
+	) == nil
+)
+check(
+	"form is respected — a CAT territory does not satisfy a PIG request",
+	AmbientTerritory.nearestFreeIndex(POINTS, free, "PIG", 34, -100, 20) == nil
+)
+
+if failures > 0 then
+	error(`{failures} ambient-territory assertion(s) failed`, 0)
+end
+
+print(`  PASS  ambient-territory: {checked} assertions over {#POINTS} territories`)
```

#### Step 3.2: `src/shared/pure/AmbientTerritory.luau`

**File:** `src/shared/pure/AmbientTerritory.luau`
**Verify:** `lune run tests/ambient-territory.test.luau`

```diff
+--!strict
+--[[
+	AmbientTerritory — which form belongs where, and which slot a monster standing HERE may take.
+
+		pointsFor(points, form)                              -> the territories of one form
+		nearestFreeIndex(points, free, form, x, z, radius)   -> a claimable slot, or nil
+
+	WHY FORMS HAVE TERRITORIES AT ALL. §5 asks for a barrio, and a barrio is not a field of randomly
+	scattered animals: a pig is penned or tethered in mud, chickens forage a household yard, a goat is
+	staked at a field edge and moved every day or two, cats work the alleys, dogs hold the road, people
+	sit on porches and at the store. All six of those are how the animals are actually kept — see
+	`references/research-01-barrio-animals.md`, where the tethering and yard-keeping are sourced.
+
+	AND WHY THAT IS A MECHANIC RATHER THAN DRESSING. It constrains the ASWANG. A pig on the basketball
+	court is now wrong, so the monster can only wear a pig near mud. That is a deliberate tactical cost
+	and it is the counterplay §4.5 wants — camouflage stops being "hide anywhere" and becomes "hide
+	where this animal would be", which is a decision a survivor can learn to read.
+
+	THE REFUSAL IS THE POINT, AND IT ALSO CLOSED A JUMP. On claim, `MonsterService` drives the entity
+	to the monster. Without a bound the entity crossed the whole barrio in one frame — a pig
+	disappearing from the well and reappearing on the ring road, which under territories reads as an
+	answer rather than as an oddity. Bounding the claim to `radius` bounds the jump to `radius`.
+
+	NO SEED, NO DRAW, AND NO CLIENT-SUPPLIABLE INPUT. `x` and `z` are the SERVER's copy of the
+	monster's own root position. This module is replicated and any client may run it, which is fine for
+	the reason `CamouflageRules`' header gives at length: what it computes is a rule the map states in
+	public — the pig pens are visible — and the inputs it would need to be interesting are server-only.
+
+	NO `script.Parent` REQUIRES — Lune has no `script`. `Form` is plain `string` here on purpose: this
+	module never returns a form, only an index, so there is no literal union to widen on the way out
+	and `.claude/lessons/pure-module-unions-widen-in-lists.md` does not apply.
+]]
+
+export type Point = {
+	Form: string,
+	X: number,
+	Z: number,
+}
+
+local AmbientTerritory = {}
+
+-- Every territory of one form, in declaration order. Used by the map contract's coverage and spread
+-- assertions rather than by the game, which asks the sharper question below.
+function AmbientTerritory.pointsFor(points: { Point }, form: string): { Point }
+	local owned: { Point } = {}
+
+	for _, point in points do
+		if point.Form == form then
+			table.insert(owned, point)
+		end
+	end
+
+	return owned
+end
+
+--[[
+	THE NEAREST FREE SLOT OF THIS FORM WITHIN `radius`, OR nil.
+
+	`free` IS INDEXED IN LOCKSTEP WITH `points`, which is the contract that lets this module answer
+	without knowing what a roster is. `AmbientService` spawns one rig per point in point order, so slot
+	index and point index are the same number — and that identity is asserted in
+	`tests/barrio-ambient.test.luau` rather than assumed here.
+
+	NEAREST RATHER THAN FIRST, and the reason is an exploit audit's finding one level along. V07 found
+	that a first-free pick made every hide in every round the same slot, so a survivor could camp it;
+	`AmbientService` answered with a random pick. Under territories, random is wrong again for a new
+	reason — a random slot within radius is a longer jump than the nearest one, and the jump is the
+	visible artefact. Nearest minimises what a bystander sees, and the radius bound is what keeps the
+	choice from being campable: which of the three territories the monster uses is decided by where it
+	chose to walk, which is not something a survivor can camp without following it.
+
+	SQUARED DISTANCE, NO SQUARE ROOT. Monotonic, so the ordering is identical, and the caller's radius
+	is squared once rather than a root taken per candidate.
+]]
+function AmbientTerritory.nearestFreeIndex(
+	points: { Point },
+	free: { boolean },
+	form: string,
+	x: number,
+	z: number,
+	radius: number
+): number?
+	local bestIndex: number? = nil
+	local bestDistance = radius * radius
+
+	for index, point in points do
+		if point.Form ~= form or free[index] ~= true then
+			continue
+		end
+
+		local dx = point.X - x
+		local dz = point.Z - z
+		local distance = dx * dx + dz * dz
+
+		--[[
+			`<` RATHER THAN `<=`, so a tie keeps the earlier index. Deterministic ordering matters
+			here: two territories at exactly equal distance would otherwise resolve by table order,
+			which is the same thing, but writing it down stops a later "optimisation" from making the
+			answer depend on iteration order.
+		]]
+		if distance < bestDistance then
+			bestDistance = distance
+			bestIndex = index
+		end
+	end
+
+	return bestIndex
+end
+
+return AmbientTerritory
```

#### Step 3.3: The builder sites eighteen points, each naming its form

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-receipt.test.luau`

Gated on `barrio-receipt`, which reconciles the builder's hand-copied `assert` literals against
`Config.luau` **as text** — so it is the suite that fails if `count("AmbientSpawn") == 16` is left
behind while `PerForm` says otherwise. `barrio-ambient` cannot be the check here: it still expects four
forms until Step 3.4 rewrites it, so it is red across this step by design.

The eighteen coordinates are chosen against the map's real features — the three alleys at
`ALLEYS` (`barrio.luau:771-775`), the ring and radial roads, the seven kubo, the well at (−70, 32),
the stalls, and the rice field edge. **Every territory must carry the prop that justifies it**, which
is Phase 8's obligation and is named here so it is not forgotten: a pig territory with no wallow is a
hidden rule, and a hidden rule is not counterplay.

```diff
 --[[
 	WHERE THE AMBIENT POPULATION STANDS. `AmbientService` spawns the rigs; this only sites them.
 
-	§5 is explicit that the COUNT is what matters — "if there is one pig in the barrio, the disguise is
-	meaningless" — and `Config.Ambient.PerForm` (4) x 4 forms is sixteen. Sixteen points, so no two
-	entities start inside each other.
+	§5 is explicit that the COUNT is what matters — "if there is one pig in the barrio, the disguise is
+	meaningless" — and `Config.Ambient.PerForm` (3) x 6 forms is eighteen. Eighteen points, so no two
+	entities start inside each other.
+
+	EACH POINT NOW NAMES ITS FORM, AND THAT IS A MECHANIC RATHER THAN TIDINESS. A rig wanders
+	`WanderRadius` from its own point and no further, so siting all the pigs at mud and all the goats
+	at field edges means a pig on the basketball court is WRONG — and since the Aswang can only claim
+	a slot it is standing near, it can only wear a pig near mud. That is a deliberate tactical
+	constraint on the monster and it is the counterplay §4.5 asks for.
+
+	THE PLACEMENTS ARE RESEARCHED, NOT INVENTED (`references/research-01-barrio-animals.md`):
+	backyard pigs are tethered or penned rather than free-roaming; goats are tethered at field edges
+	and under plantation trees and brought in at night; native chickens are free-range within a
+	household yard; street cats work alleys and market corners; dogs roam the neighbourhood and are
+	home by dusk; and people sit on the bench in front of the sari-sari store.
+
+	EVERY TERRITORY OWES ITS PROP. A pig point with no wallow, a goat point with no stake, a chicken
+	point with no yard is a rule the player cannot see — and an invisible rule is not counterplay, it
+	is a trap. Phase 8's dressing pass is where that debt is paid, and it is the reason these
+	coordinates are chosen against real map features rather than spread evenly.
 ]]
-local AMBIENT_POINTS = {
-	-- The plaza and its approaches, where villagers and dogs plausibly gather.
-	{ -30, 30 },
-	{ 30, 24 },
-	{ 26, -34 },
-	{ -18, -30 },
-	-- The four stall corners.
-	{ -58, -58 },
-	{ 58, -58 },
-	{ 58, 58 },
-	{ -58, 58 },
-	-- The civic and outlying zones, so no quarter of the map is animal-dead.
-	{ -76, 44 },
-	{ 0, -104 },
-	{ -14, -146 },
-	{ 120, 148 },
-	{ -100, 60 },
-	{ 100, -60 },
-	{ -40, 100 },
-	{ 40, -100 },
-}
+local AMBIENT_POINTS = {
+	-- CAT — the three alleys. `ALLEYS` above puts Alley_NE along z = -100, Alley_SW along x = -100
+	-- and Alley_SE along z = 100, each spanning 9..121 on its other axis. Cats work alleys, market
+	-- corners and the spaces between buildings.
+	{ Form = "CAT", X = 34, Z = -100 },
+	{ Form = "CAT", X = -100, Z = 34 },
+	{ Form = "CAT", X = 96, Z = 100 },
+
+	-- DOG — the roads. A radial, a ring corner and the southern ring. Aspins roam the neighbourhood
+	-- and lie in the street; they are the one form whose territory is a THOROUGHFARE, which makes DOG
+	-- the most permissive disguise in the game and PIG the most restrictive. That spread is deliberate.
+	{ Form = "DOG", X = 0, Z = -76 },
+	{ Form = "DOG", X = -130, Z = -44 },
+	{ Form = "DOG", X = 62, Z = 130 },
+
+	-- PIG — mud. The well's runoff at (-70, 32), the north field's low ground, and the paddy edge in
+	-- the south-east. Backyard pigs are tethered under a tree or penned in a kulungan, not roaming.
+	{ Form = "PIG", X = -64, Z = 44 },
+	{ Form = "PIG", X = -70, Z = -104 },
+	{ Form = "PIG", X = 108, Z = 108 },
+
+	-- GOAT — field edges, outside the ring where the ground is open. Kambing are tethered on a rope
+	-- and moved to fresh grazing; the rope is the prop that has to exist for this rule to be visible.
+	{ Form = "GOAT", X = 146, Z = -70 },
+	{ Form = "GOAT", X = -124, Z = 118 },
+	{ Form = "GOAT", X = 128, Z = 148 },
+
+	-- CHICKEN — house yards, one beside each of three kubo. Native chickens are free-range within a
+	-- household's ground and roost off the ground at night.
+	{ Form = "CHICKEN", X = -92, Z = -78 },
+	{ Form = "CHICKEN", X = 92, Z = -78 },
+	{ Form = "CHICKEN", X = 78, Z = 92 },
+
+	-- VILLAGER — two kubo porches and the bench in front of the stalls. The sari-sari store's bench is
+	-- the sourced evening gathering place; the inuman happens there rather than in a separate shed.
+	{ Form = "VILLAGER", X = -78, Z = -64 },
+	{ Form = "VILLAGER", X = 78, Z = 64 },
+	{ Form = "VILLAGER", X = -42, Z = 30 },
+}
 
-for index, at in AMBIENT_POINTS do
-	anchor(`AmbientSpawn_{index}`, "AmbientSpawn", at[1], at[2], anchors)
-end
+for index, at in AMBIENT_POINTS do
+	--[[
+		THE FORM RIDES AS AN ATTRIBUTE, and `AmbientService` reads it. An attribute REPLICATES to every
+		client, which is correct and not a leak: it says a pig belongs here, which the wallow beside it
+		says louder. Nothing about who is camouflaged, or whether anyone is, is written anywhere on
+		these parts — see `AmbientService.buildEntity`'s header for why that absence is the guarantee.
+
+		THE NAME CARRIES THE FORM TOO, for a human opening the place file in Studio. The SERVICE reads
+		the attribute, never the name: a name is edited by hand and an attribute is edited in a panel
+		that shows its key, so parsing the name would make a typo silently re-form the barrio.
+	]]
+	local pad = anchor(`AmbientSpawn_{index}_{at.Form}`, "AmbientSpawn", at.X, at.Z, anchors)
+
+	pad:SetAttribute("Form", at.Form)
+end
```

And the build-failing assert at the foot of the file, which counts sixteen today:

```diff
 assert(
-	count("AmbientSpawn") == 16,
-	`[barrio] {count("AmbientSpawn")} AmbientSpawn parts, expected 16 — AmbientService will fall back to a ring at the origin`
+	count("AmbientSpawn") == 18,
+	`[barrio] {count("AmbientSpawn")} AmbientSpawn parts, expected 18 — AmbientService will fall back to a ring at the origin`
 )
```

#### Step 3.4: Rewrite `tests/barrio-ambient.test.luau` for six forms

**File:** `tests/barrio-ambient.test.luau`
**Verify:** `lune run tests/barrio-ambient.test.luau`

The suite parses bare `{ x, z }` pairs (`:77`) and hard-codes four forms (`:48`). Both change, and it
gains the assertion that makes `AmbientTerritory`'s lockstep contract real rather than a comment.

```diff
-local FORMS = { "CAT", "DOG", "PIG", "VILLAGER" }
+local FORMS = { "CAT", "DOG", "PIG", "GOAT", "CHICKEN", "VILLAGER" }
```

```diff
-for x, z in string.gmatch(block :: string, "{ (%-?%d+), (%-?%d+) }") do
-	table.insert(points, { tonumber(x) :: number, tonumber(z) :: number })
-end
+for form, x, z in
+	string.gmatch(block :: string, `{ Form = "([A-Z_]+)", X = (%-?%d+), Z = (%-?%d+) }`)
+do
+	table.insert(points, { Form = form, X = tonumber(x) :: number, Z = tonumber(z) :: number })
+end
+
+--[[
+	EVERY POINT NAMES A FORM, AND EXACTLY `PerForm` OF THEM NAME EACH.
+
+	This is the assertion that keeps `AmbientTerritory`'s lockstep contract honest: the service spawns
+	one rig per point in point order, so slot index and point index are the same number, and
+	`nearestFreeIndex` returns a POINT index that `AmbientService` uses as a SLOT index. A form with
+	four points and three rigs breaks that identity silently — the fourth point is never occupied, and
+	a monster standing on it is refused a claim for a form whose territory it is visibly inside.
+]]
+local perFormCount: { [string]: number } = {}
+
+for _, form in FORMS do
+	perFormCount[form] = 0
+end
+
+for _, point in points do
+	check(`{point.Form} is a declared form`, perFormCount[point.Form] ~= nil, point.Form)
+
+	if perFormCount[point.Form] ~= nil then
+		perFormCount[point.Form] += 1
+	end
+end
+
+for _, form in FORMS do
+	check(
+		`{form} has exactly PerForm ({perForm}) territories`,
+		perFormCount[form] == perForm,
+		`{perFormCount[form]} sited`
+	)
+end
+
+-- And the attribute the service actually reads. The NAME carrying the form is for a human in Studio;
+-- the ATTRIBUTE is the contract, and a builder that stopped setting it would leave every rig
+-- formless with the point count still correct.
+check(
+	"the builder writes the Form attribute onto each pad",
+	string.find(builder, `pad:SetAttribute("Form", at.Form)`, 1, true) ~= nil
+)
```

The overlap and quadrant loops below need their field access updated from `a[1]`/`a[2]` to
`a.X`/`a.Z`; the 8-stud minimum and the "every quadrant carries ambient life" rule are unchanged and
still hold for the eighteen points above.

#### Step 3.5: `spawnPoints()` partitions by form, and `ClaimSlot` bounds the claim

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run analyze`

```diff
 local function spawnPoints(): { CFrame }
```

becomes a partition, and `spawnForm` walks its form's own list rather than a shared running index:

```diff
+--[[
+	THE POINTS, PARTITIONED BY THE FORM THEY NAME.
+
+	A PART TAGGED `AmbientSpawn` WITH NO `Form` ATTRIBUTE IS SKIPPED WITH A WARNING, not defaulted.
+	That is what a half-updated place file looks like — someone added a marker in Studio and did not
+	set the attribute — and defaulting it to CAT would put a cat in a rice paddy and make the
+	territory rule quietly untrue for one entity. A skipped point produces a form short of its
+	`PerForm`, which is visible in Studio and in the builder's own assert.
+]]
+local function spawnPointsByForm(): { [string]: { CFrame } }
+	local byForm: { [string]: { CFrame } } = {}
+
+	for _, tagged in CollectionService:GetTagged(SPAWN_TAG) do
+		if not tagged:IsA("BasePart") then
+			continue
+		end
+
+		local form = tagged:GetAttribute("Form")
+
+		if type(form) ~= "string" then
+			warn(
+				`[AmbientService] {tagged:GetFullName()} is tagged {SPAWN_TAG} with no Form attribute `
+					.. `— skipped. The map contract in this file's header names the six valid values.`
+			)
+			continue
+		end
+
+		local list = byForm[form]
+
+		if list == nil then
+			list = {}
+			byForm[form] = list
+		end
+
+		table.insert(list, tagged.CFrame)
+	end
+
+	return byForm
+end
```

`ClaimSlot` gains the monster's position and consults the territory module. `AmbientRoster.claim`'s
`preferIndex` hint is what carries the answer, so the pure roster module is unchanged:

```diff
-function AmbientService.ClaimSlot(form: Types.CamouflageForm): number?
-	local free = AmbientRoster.freeSlots(roster, form)
-	local prefer = if #free > 0 then free[rng:NextInteger(1, #free)] else nil
-
-	local claimed, slotIndex = AmbientRoster.claim(roster, form, prefer)
-
-	roster = claimed
-
-	return slotIndex
-end
+function AmbientService.ClaimSlot(form: Types.CamouflageForm, at: Vector3): number?
+	--[[
+		THE NEAREST FREE SLOT OF THIS FORM WITHIN `ClaimRadius`, AND nil IF THERE IS NONE.
+
+		THE RANDOM PICK IS GONE AND ITS REASON IS SATISFIED ANOTHER WAY. V07 replaced a first-free pick
+		with a random one because an exploit audit found every hide landing on the same slot, so a
+		survivor could camp it. Under territories the choice is made by WHERE THE MONSTER WALKED, which
+		is not campable — and nearest is strictly better than random here, because on claim the entity
+		is driven to the monster and a random in-range slot is a longer visible jump than the nearest.
+
+		NO SEED CROSSES ANYTHING. `at` is the server's own copy of the monster's root position and the
+		module it is handed to returns an index. `rng` survives for nothing else in this file and is
+		removed with this change.
+	]]
+	local slotIndex = AmbientTerritory.nearestFreeIndex(
+		territories,
+		freeFlags(),
+		form,
+		at.X,
+		at.Z,
+		Config.Ambient.ClaimRadius
+	)
+
+	local claimed, granted = AmbientRoster.claim(roster, form, slotIndex)
+
+	roster = claimed
+
+	--[[
+		AND IF THE ROSTER DISAGREED, REFUSE RATHER THAN FALL BACK. `AmbientRoster.claim` honours a
+		hint and otherwise scans for the first free slot of that form — which is correct for its own
+		contract and WRONG here, because that fallback slot could be anywhere in the barrio and would
+		restore the map-wide jump this phase exists to close. So a granted index that is not the one
+		asked for is released and refused.
+	]]
+	if granted ~= slotIndex then
+		roster = AmbientRoster.release(roster, granted)
+		return nil
+	end
+
+	return granted
+end
```

`PickAvailableForm` takes the same position and asks the same question, so a refusal and a pick can
never disagree:

```diff
-function AmbientService.PickAvailableForm(): Types.CamouflageForm?
+function AmbientService.PickAvailableFormNear(at: Vector3): Types.CamouflageForm?
```

and `MonsterService`'s two call sites (`:1652`, `:1736`) pass `root.Position`, with `:1786`'s
`enterCamouflage` passing it through to `ClaimSlot`.

#### Step 3.6: The map contract in `AmbientService`'s header, rewritten

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run check:config`

```diff
 	  - TAG: `AmbientSpawn`, applied with CollectionService (Studio's Tag Editor) to a BasePart.
 	    Anything tagged that is not a BasePart is SKIPPED rather than erroring.
-	  - COUNT: at least `Config.Ambient.PerForm * 4` — sixteen at the shipped value. Fewer works;
-	    points are reused in order, which looks visibly wrong in Studio and is therefore fixable.
-	    ZERO triggers the code fallback ring below, which is scaffolding and not a map.
-	  - PLACEMENT: spread across the bahay kubo, the chapel and the well area, matching §5's
-	    sightline rule — "you should almost always be able to see *something*". Entities wander
-	    `Config.Ambient.WanderRadius` from their point and no further, so THE POINTS DETERMINE THE
-	    DISTRIBUTION and the distribution is half the disguise: four pigs clustered in the plaza
-	    means the pig by the chapel is the monster.
+	  - ATTRIBUTE: `Form`, a string, one of CAT / DOG / PIG / GOAT / CHICKEN / VILLAGER. A tagged
+	    part WITHOUT it is skipped with a warning rather than defaulted — see `spawnPointsByForm`.
+	  - COUNT: `Config.Ambient.PerForm` points PER FORM — three each, eighteen in total. A form with
+	    fewer gets rigs stacked on shared points; a form with more gets a territory no rig occupies,
+	    which refuses a claim to a monster standing visibly inside it.
+	  - PLACEMENT IS NOW A GAMEPLAY CONTRACT, NOT ONLY A DISTRIBUTION ONE. Entities wander
+	    `Config.Ambient.WanderRadius` from their point and no further, and the Aswang may only claim
+	    a slot within `Config.Ambient.ClaimRadius` of where it stands. So THE POINTS DECIDE WHERE EACH
+	    DISGUISE IS AVAILABLE: pigs at mud, chickens in house yards, goats at field edges, cats in
+	    alleys, dogs on roads, villagers on porches and at the store bench.
+	  - EVERY POINT OWES ITS PROP. A pig territory with no wallow beside it is a rule a player cannot
+	    see, and an invisible rule is a trap rather than counterplay. Whoever moves a point moves the
+	    prop with it; neither this file nor `npm run verify` can check that, which is why it is
+	    written here.
```

Plus the two new `Config.Ambient` numbers:

```diff
 		WanderRadius = 24,
+		--[[
+			HOW CLOSE THE ASWANG MUST BE TO A TERRITORY TO WEAR ITS FORM (Phase 3).
+
+			THIS NUMBER IS THE WHOLE TACTICAL CONSTRAINT. Large, and camouflage is "hide anywhere" with
+			extra steps; small, and the monster is refused so often that the ability is unreliable and
+			§4.3's escape stops working. It is the first thing to move at V16 and the reason it is
+			here rather than in `AmbientService`.
+
+			`tests/ambient-territory.test.luau` PINS IT BELOW `WanderRadius`, and that bound is not
+			cosmetic: above it the monster can claim a slot from further than the real animal ever
+			roams, so it can stand as a pig where no pig has been — the constraint becomes advisory
+			with every test still green. It is also the bound on how far an entity visibly JUMPS when
+			a claim happens, since the rig is driven to the monster.
+		]]
+		ClaimRadius = 18,
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

- **The `Form` attribute replicates, and that is correct.** It says a pig belongs here, which the
  wallow beside it says louder. What must never appear on these parts is anything that varies with
  whether a slot is claimed — `AmbientService`'s header already states that absence is the guarantee,
  and this phase adds the first attribute the file has ever written. **Re-read that header before
  adding a second one.**
- **`PickAvailableFormNear` is a narrower oracle than `PickAvailableForm` was.** It is called only for
  the requesting player, from the server's own copy of their position, and its answer reaches only
  them. But it now encodes map information — "which forms are available at this point" — so if a future
  chunk ever calls it for a player other than the requester, that is a leak. Named here because the
  rename is the only warning.
- **`AmbientRoster.claim`'s fallback scan is now wrong for this caller** and is defended against at the
  call site rather than changed. The module's own contract — honour the hint, else first free — is
  correct for its tests and for any other caller; `ClaimSlot` releasing a mismatched grant is the
  narrower rule living where it applies.
- **`rng` becomes unused in `AmbientService`.** Remove it with this change; selene flags it, and a
  `Random.new()` left in a file that no longer draws invites someone to seed it.
- **`CAMO_NO_SLOT` will fire far more often now** and it is the only feedback the Aswang gets. Whether
  a player can tell "no pigs left" from "no pig territory here" is a HUD question, not a server one —
  V15, and in Follow Ups.
- **Player leaving mid-round is unchanged.** `ReleaseSlot` is still idempotent and total, and nothing
  in this phase keys anything by player.

---

### Phase 4: One motion driver, because two drivers is two behaviours

**The architectural claim of this phase, in one sentence:** today a free rig and a claimed rig are
moved by **two different functions in two different files**, and every difference between those two
functions is a client-readable tell. `wanderTick` skips claimed slots (`AmbientService.luau:450`) and
`PuppetSlot` writes them (`:330`). Adding bob, sway and a head-turn to `wanderTick` alone would mean
**the disguised animal is the one that does not breathe** — a better animation system producing a
worse leak, which is the trap this phase is shaped to avoid.

So the motion is added **once**, to a single step function that both paths call, and a claim changes
exactly one thing: where the target comes from, and how fast the rig is allowed to travel toward it.

**Motion is driven by MEASURED displacement, never by the parameter that caused it.** A free rig knows
it is walking because its position changed; a claimed rig knows the same way. That is what makes the
two identical in kind — a claimed rig moving at 16 studs/s simply bobs faster than a free one at 4,
which is the speed tell §4.5 already designed and licenses.

#### Step 4.1: The motion suite

**File:** `tests/ambient-motion.test.luau`
**Verify:** `test -f tests/ambient-motion.test.luau`

**Existence, not exit 0** — same reason as Steps 2.1 and 3.1. The module arrives in Step 4.2, which is
where the suite goes green.

```diff
+--!strict
+--[[
+	tests/ambient-motion.test.luau
+
+	THE PROPERTIES THAT MAKE PROCEDURAL MOTION SAFE TO ADD TO A DISGUISE.
+
+	Motion is the half of camouflage §4.5 hangs on — "which cat is behaving oddly" — so the moment
+	ambient rigs start bobbing and swaying, HOW they bob becomes a secrecy surface. The rule is that a
+	claimed rig and a free rig run the SAME function over the SAME kind of input, and the only
+	difference is the input's value.
+
+	SO EVERY ASSERTION HERE IS ABOUT THE FUNCTION BEING TOTAL AND CONTINUOUS. A function with a
+	discontinuity, a clamp, or a special case at some speed is a function that behaves differently for
+	a monster than for a pig, and the special case is exactly what a careful implementer adds when the
+	fast case "looks wrong".
+
+	SEEDLESS AND DETERMINISTIC. There is no `Random` here and no `os.clock()`: the caller passes time
+	in. That is what makes it testable and it is also why it is safe in `src/shared` — CLAUDE.md's rule
+	is that a published algorithm is fine and a published algorithm with client-suppliable INPUTS is
+	not, and every input here is a number the client can already read off the part it is watching.
+]]
+
+local AmbientMotion = require("../src/shared/pure/AmbientMotion")
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
+local TUNING = { BobStuds = 0.12, BobHz = 1.4, SwayDegrees = 4, SwayHz = 0.9, IdleHz = 0.25 }
+
+--[[
+	1. PHASE OFFSETS ARE DISTINCT ACROSS THE POPULATION.
+
+	Eighteen rigs bobbing in lockstep is not scenery, it is a chorus line — and it is worse than
+	static, because a viewer reads the synchronised set as one system and the monster's rig as the
+	only one out of step the moment its speed differs. Distinct offsets mean the population never had
+	a phase to be out of.
+]]
+local seen: { [number]: boolean } = {}
+
+for index = 1, 18 do
+	local phase = AmbientMotion.phaseFor(index)
+
+	check(`phaseFor({index}) is inside one period`, phase >= 0 and phase < math.pi * 2, `{phase}`)
+	check(`phaseFor({index}) is distinct`, seen[phase] ~= true, `{phase}`)
+	seen[phase] = true
+end
+
+check("phaseFor is deterministic across calls", AmbientMotion.phaseFor(7) == AmbientMotion.phaseFor(7))
+
+--[[
+	2. BOUNDED, AND THE BOUND IS THE TUNING RATHER THAN A CONSTANT INSIDE THE MODULE.
+
+	An unbounded bob at high speed is a rig launching itself off the ground — which for a CLAIMED rig
+	means the disguise leaves the floor exactly when the monster sprints. Phase 2 spent the whole phase
+	putting these bodies on the ground; an unbounded vertical term would undo it under motion only,
+	which is far harder to notice than a static offset.
+]]
+for _, speed in { 0, 0.5, 4, 16, 40, 1000 } do
+	for step = 0, 40 do
+		local t = step * 0.137
+		local bob = AmbientMotion.bobOffset(t, 1.1, speed, TUNING)
+
+		check(
+			`bob is bounded at speed={speed}`,
+			math.abs(bob) <= TUNING.BobStuds + 1e-9,
+			`{bob} at t={t}`
+		)
+	end
+end
+
+--[[
+	3. CONTINUOUS IN SPEED — no threshold, no "walking vs idle" switch.
+
+	A discrete idle/walk switch is the single most likely thing to be written here, and it is the leak:
+	a claimed rig crosses the threshold whenever the monster moves and a free rig at wander speed may
+	sit near it, so the two visibly switch modes at different moments. A continuous blend has no mode
+	to be in.
+]]
+local previous = AmbientMotion.amplitudeFor(0, TUNING)
+
+for tenths = 1, 200 do
+	local speed = tenths / 10
+	local current = AmbientMotion.amplitudeFor(speed, TUNING)
+
+	check(
+		`amplitude does not jump between {(tenths - 1) / 10} and {speed}`,
+		math.abs(current - previous) < 0.05,
+		`{previous} -> {current}`
+	)
+	previous = current
+end
+
+check("a still rig still idles rather than freezing", AmbientMotion.amplitudeFor(0, TUNING) > 0)
+
+--[[
+	4. THE SPEED THE MOTION READS IS THE MEASURED ONE, and this is the parity assertion.
+
+	`speedFrom` takes a displacement and a delta time. It is the ONLY way either path learns how fast
+	its rig is going — neither passes in `WanderSpeed`, and neither passes in the monster's WalkSpeed —
+	so a free rig and a claimed rig that happen to move at the same rate animate identically, and the
+	one that moves faster differs only in degree.
+]]
+check("speedFrom is displacement over time", AmbientMotion.speedFrom(8, 0.5) == 16)
+check("a zero delta does not divide by zero", AmbientMotion.speedFrom(8, 0) == 0)
+check("a negative delta is refused rather than inverted", AmbientMotion.speedFrom(8, -0.5) == 0)
+
+if failures > 0 then
+	error(`{failures} ambient-motion assertion(s) failed`, 0)
+end
+
+print(`  PASS  ambient-motion: {checked} assertions`)
```

#### Step 4.2: `src/shared/pure/AmbientMotion.luau`

**File:** `src/shared/pure/AmbientMotion.luau`
**Verify:** `lune run tests/ambient-motion.test.luau`

```diff
+--!strict
+--[[
+	AmbientMotion — the bob, the sway and the idle, as arithmetic over time and measured speed.
+
+		phaseFor(index)                        -> a per-entity offset, so eighteen rigs are not a chorus
+		speedFrom(distance, deltaTime)         -> how fast this rig ACTUALLY moved
+		amplitudeFor(speed, tuning)            -> how much motion that speed earns, continuously
+		bobOffset(t, phase, speed, tuning)     -> vertical, in studs
+		swayDegrees(t, phase, speed, tuning)   -> roll, in degrees
+
+	THIS MODULE IS THE PARITY MECHANISM, not a decoration. `AmbientService` used to move free rigs in
+	`wanderTick` and claimed rigs in `PuppetSlot` — two functions, two files — and adding motion to one
+	of them would have made the disguised animal THE ONE THAT DOES NOT BREATHE. So the motion lives
+	here, both paths call it, and a claim changes only the target and the speed cap.
+
+	EVERY TERM READS `speed`, AND `speed` IS ALWAYS MEASURED. Neither caller passes in the number that
+	caused the movement — not `Config.Ambient.WanderSpeed`, not the monster's WalkSpeed. A rig learns
+	how fast it is going by how far it went, so two rigs travelling at the same rate animate
+	identically no matter what is driving them, and one travelling faster differs only in degree. That
+	degree IS §4.5's designed tell: "which cat is behaving oddly".
+
+	CONTINUOUS, WITH NO IDLE/WALK THRESHOLD. A discrete switch is the obvious implementation and it is
+	a leak: the claimed rig crosses the threshold on the monster's movement and a free rig near wander
+	speed crosses it on its own schedule, so the two visibly change mode at different moments. There is
+	no mode here to change.
+
+	SEEDLESS. Time and index in, numbers out. `phaseFor` is a hash of the index rather than a draw, so
+	two servers agree and there is nothing to replay — and there is nothing worth replaying, because a
+	slot index is not a secret (`AmbientRoster`'s header).
+
+	NO `script.Parent` REQUIRES; the tuning is passed in as a table so `Config` never reaches this file.
+]]
+
+export type Tuning = {
+	BobStuds: number,
+	BobHz: number,
+	SwayDegrees: number,
+	SwayHz: number,
+	IdleHz: number,
+}
+
+local AmbientMotion = {}
+
+local TAU = math.pi * 2
+
+--[[
+	A STABLE OFFSET PER ENTITY. The golden-ratio conjugate as the step gives a low-discrepancy sequence
+	— consecutive indices land far apart on the circle — so neighbouring rigs are maximally out of
+	phase rather than merely different. Eighteen rigs on a shared phase read as one animated object.
+]]
+function AmbientMotion.phaseFor(index: number): number
+	return (index * 0.61803398875) % 1 * TAU
+end
+
+--[[
+	HOW FAST THIS RIG ACTUALLY MOVED. The only speed input either caller has.
+
+	A NON-POSITIVE DELTA ANSWERS ZERO RATHER THAN DIVIDING. Heartbeat can hand back a zero delta on the
+	first frame after a resume, and `distance / 0` is `inf`, which would put the amplitude at its cap
+	for one frame — a single-frame twitch on every rig at once, at the moment a player's game unpauses.
+]]
+function AmbientMotion.speedFrom(distance: number, deltaTime: number): number
+	if deltaTime <= 0 then
+		return 0
+	end
+
+	return distance / deltaTime
+end
+
+--[[
+	HOW MUCH MOTION A SPEED EARNS, IN 0..1, CONTINUOUSLY AND WITH NO THRESHOLD.
+
+	`speed / (speed + k)` saturates smoothly: zero at rest, half at k, asymptotic to one. That shape is
+	chosen over a clamp because a clamp has a corner, and a corner is a speed at which the animation
+	visibly stops changing — which a survivor can learn to read as "that one is at the cap".
+
+	THE FLOOR IS WHY A STANDING ANIMAL IS NOT A STATUE. `IdleHz`'s amplitude never reaches zero, so a
+	resting rig still breathes. A rig that froze when still would make STILLNESS the tell, and a
+	camouflaged monster standing perfectly still is precisely what a player does when hiding.
+]]
+function AmbientMotion.amplitudeFor(speed: number, tuning: Tuning): number
+	local half = 1 / math.max(tuning.BobHz, 1e-6)
+	local moving = speed / (speed + half)
+
+	return 0.25 + 0.75 * moving
+end
+
+-- Vertical, in studs. Bounded by `BobStuds` for every input, which is what keeps a fast-moving
+-- disguise on the ground that Phase 2 put it on.
+function AmbientMotion.bobOffset(t: number, phase: number, speed: number, tuning: Tuning): number
+	local rate = tuning.BobHz * (0.5 + speed / (speed + 8))
+
+	return math.sin(t * rate * TAU + phase)
+		* tuning.BobStuds
+		* AmbientMotion.amplitudeFor(speed, tuning)
+end
+
+-- Roll, in degrees. Slower than the bob and offset from it, so the two never align into a single
+-- pendulum — an animal that rolls exactly in time with its own bounce reads as a toy.
+function AmbientMotion.swayDegrees(t: number, phase: number, speed: number, tuning: Tuning): number
+	return math.sin(t * tuning.SwayHz * TAU + phase * 1.7)
+		* tuning.SwayDegrees
+		* AmbientMotion.amplitudeFor(speed, tuning)
+end
+
+return AmbientMotion
```

#### Step 4.3: Motion tunables into `Config.Ambient`

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

```diff
 		WanderInterval = 6,
 		IdleSeconds = 3,
+		--[[
+			THE PROCEDURAL MOTION (Phase 4). §5 asks for "a wander loop and an idle"; this is that,
+			plus enough life that a standing animal is not a statue.
+
+			THEY ARE HERE RATHER THAN IN THE SERVICE BECAUSE THEY ARE A SECRECY SURFACE, not because
+			`check:config` insists. Motion is what §4.5's deduction reads — "which cat is behaving
+			oddly" — so these five numbers set how loud the ONE permitted difference between a
+			disguised rig and a real one is. A larger `BobStuds` makes a running monster's disguise
+			more obviously running.
+
+			`BobStuds` IS THE ONE TO WATCH ON A PHONE AND THE ONE TO WATCH FOR SECRECY, for opposite
+			reasons. Small enough and nobody sees the life; large enough and a fast rig visibly leaves
+			the ground that Phase 2 spent a whole phase seating it on.
+		]]
+		BobStuds = 0.12,
+		BobHz = 1.4,
+		SwayDegrees = 4,
+		SwayHz = 0.9,
+		IdleHz = 0.25,
```

#### Step 4.4: Collapse `wanderTick` and `PuppetSlot` into one step function

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run analyze`

`PuppetSlot` stops writing a CFrame and starts recording a **target**. One tick moves everything.

```diff
+--[[
+	ONE STEP FUNCTION FOR EVERY RIG, FREE OR CLAIMED, AND THAT IS THE SECRECY MECHANISM.
+
+	Before this, `wanderTick` moved free rigs and `PuppetSlot` moved claimed ones — two functions in
+	two files over one visible object. Every difference between them was a client-readable tell, and
+	adding a bob to one of them would have made the disguised animal the only one that does not
+	breathe: a better animation system producing a worse leak.
+
+	NOW A CLAIM CHANGES TWO VALUES AND NO CODE. The target, and the cap on how far the rig may travel
+	toward it this frame. Everything after that line is shared.
+
+	THE SPEED THE MOTION READS IS MEASURED, NOT PASSED. `moved` below is the actual displacement, so a
+	claimed rig keeping up with a sprinting monster animates like a fast animal and a free rig
+	animates like a slow one — a difference of DEGREE in one function, which is §4.5's intended tell,
+	rather than a difference of KIND, which is a free answer.
+]]
+local function stepEntity(index: number, model: Model, target: CFrame, maxStep: number, dt: number)
+	local body = model.PrimaryPart
+
+	if body == nil then
+		return
+	end
+
+	local current = model:GetPivot()
+	local offset = target.Position - current.Position
+	local distance = offset.Magnitude
+	local travel = math.min(distance, maxStep)
+	local position = if distance > 1e-4
+		then current.Position + offset.Unit * travel
+		else current.Position
+
+	--[[
+		FACING FOLLOWS TRAVEL, AND A STATIONARY RIG KEEPS THE FACING IT HAD. `CFrame.lookAt` with a
+		zero direction errors; more importantly, a rig that snapped to a default facing whenever it
+		stopped would make STOPPING the tell, and a camouflaged monster standing still is exactly what
+		a hiding player does.
+	]]
+	local facing = if travel > 1e-4
+		then CFrame.lookAt(position, position + offset.Unit)
+		else CFrame.new(position) * (current - current.Position)
+
+	elapsed[index] = (elapsed[index] or 0) + dt
+
+	local t = elapsed[index] :: number
+	local phase = AmbientMotion.phaseFor(index)
+	local speed = AmbientMotion.speedFrom(travel, dt)
+
+	model:PivotTo(
+		facing
+			* CFrame.new(0, AmbientMotion.bobOffset(t, phase, speed, Config.Ambient), 0)
+			* CFrame.Angles(0, 0, math.rad(AmbientMotion.swayDegrees(t, phase, speed, Config.Ambient)))
+	)
+end
```

```diff
-function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame, footOffset: number)
+--[[
+	RECORD WHERE A CLAIMED RIG SHOULD BE. IT NO LONGER MOVES ANYTHING ITSELF.
+
+	That is the change: this function used to `PivotTo` directly, which made it the second of two
+	writers on one CFrame and the second of two motion behaviours in the barrio. It now sets the same
+	`targets[index]` a wander sets, and `tick` moves every rig through `stepEntity`.
+]]
+function AmbientService.PuppetSlot(slotIndex: number?, cframe: CFrame, footOffset: number)
 	...
-	model:PivotTo(...)
+	local body = model.PrimaryPart
+
+	if body == nil then
+		return
+	end
+
+	targets[slotIndex] = CFrame.new(
+		cframe.Position.X,
+		AmbientRig.puppetY(cframe.Position.Y, footOffset, body.Size.Y),
+		cframe.Position.Z
+	) * (cframe - cframe.Position)
 end
```

and the tick, which no longer skips claimed slots:

```diff
 local function wanderTick(deltaTime: number)
 	local now = os.clock()
 
 	for index, model in models do
 		local slot = roster[index]
 
-		if model == nil or slot == nil or slot.Claimed then
+		if model == nil or slot == nil then
 			continue
 		end
 
+		--[[
+			A CLAIMED SLOT IS NOT SKIPPED ANY MORE. It skips only the RETARGET — the monster decides
+			where a claimed rig goes and `PuppetSlot` has already written it — and then falls through
+			to the same `stepEntity` every free rig uses.
+
+			THE CAP IS THE ONLY OTHER DIFFERENCE. A claimed rig may travel as far as it needs to keep
+			up with a player; a free one is held to `WanderSpeed`. Two numbers, one code path.
+		]]
+		if slot.Claimed then
+			local target = targets[index]
+
+			if target ~= nil then
+				stepEntity(index, model, target, math.huge, deltaTime)
+			end
+
+			continue
+		end
+
 		local home = homes[index]
```

The wander branch keeps its retarget logic and ends by calling the same function:

```diff
-		local direction = offset.Unit
-		local moved = current.Position + direction * step
-
-		model:PivotTo(CFrame.lookAt(moved, moved + direction))
+		stepEntity(index, model, target, Config.Ambient.WanderSpeed * deltaTime, deltaTime)
```

#### Step 4.5: Confirm a puppeted rig and a free rig animate identically

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/motion-parity.md`

Two rigs of one form, one claimed and one free, **both held stationary**, captured over several
seconds. Stationary is the case that matters: at equal speed the two must be indistinguishable, and a
hiding player stands still. Then the same pair with the monster walking, to confirm the difference that
appears is speed and nothing else.

**No `Verify:` line, deliberately.** The property is "these look the same", and every mechanical check
available here would pass over a rig that idles at a different rate. `verify-plan` reports
`unverifiable`, which is the accurate answer.

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

- **A stale `targets[index]` on release is now visible.** `ReleaseSlot` documents that the entity
  resumes wandering from where the monster left it, which was free when `PuppetSlot` wrote directly.
  Now the released rig has the monster's last position as its target and will walk to it before
  retargeting. Clear `targets[index]` in `ReleaseSlot` — and note that the existing comment forbidding
  a `PivotTo(home)` there still stands; clearing a target is not teleporting.
- **`Config.Ambient` is passed where a `Tuning` is expected.** It structurally satisfies the type
  because it carries the five fields, which is why the tuning is a table rather than five arguments.
  Adding a sixth field to `Config.Ambient` is safe; renaming one of the five is an analyze error.
- **18 rigs × one `PivotTo` per Heartbeat is the per-frame cost §5 cares about**, and it is unchanged
  in count — the same loop ran before. What is new is the trigonometry: four `math.sin` per rig per
  frame, 72 a frame. Cheap, but it is the first per-frame arithmetic this file has had, and it is the
  number to look at if the phone drops frames.
- **`math.huge` as the claimed rig's cap means the rig teleports to the target on the first frame after
  a claim.** Phase 3 bounded that jump to `ClaimRadius`, which is why this is acceptable rather than a
  regression — but if `ClaimRadius` is ever raised, this line is the reason the jump is visible.
- **The `elapsed` table is a new per-index store** and must be cleared in `Init` alongside the other
  five, or a restarted round resumes each rig's animation mid-phase.

---

### Phase 5: Two new meshes, and the rig budget brought inside the ceiling

**All six rigs are regenerated, not two.** The four existing rig meshes carry no recorded triangle
count anywhere — `FORM_LOOKS` holds a `Mesh` and a `Texture` id and nothing else — so they cannot be
brought inside a budget without knowing what they cost, and this plan has **not** confirmed any API
that reads a `MeshPart`'s triangle count at runtime. Regenerating all six at a stated request makes the
registry honest **by construction** rather than by a measurement nobody can reproduce, and it upgrades
the four old rigs, which is the thing the parity rule makes free: the disguise is one of these rigs, so
a better rig is a better disguise with no second appearance path to drift.

**The budget, stated and kept separate from the props':**

| | Requested | Instances | Drawn |
| --- | --- | --- | --- |
| Props (`ASSETS.Meshes`) | 21,000 over 8 rows, ceiling **27,000** | ~37 | unchanged |
| Rigs (`ASSETS.RigMeshes`) | CAT 1200 · DOG 1400 · PIG 1400 · GOAT 1200 · CHICKEN 800 · VILLAGER 1800 = **7,800**, ceiling **9,000** | 18 | ~23,400 |

The chicken is deliberately the cheapest and the villager the dearest: a 1.1-stud bird needs no detail
to read, and the villager is the one silhouette that must read as a *person* at distance.

#### Step 5.1: Regenerate all six rig meshes from researched prompts

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/rig-meshes.md`

The prompts come from `references/research-01-barrio-animals.md`, and the corrections in it are the
point of having done the research. The failure mode is Western defaults:

- **DOG** is an *aspin* — light-boned, short rough coat, **tail held high**, mixed ear carriage,
  semi-circular spotting at the back and tail base. Not a Labrador.
- **PIG** is a native backyard pig — **black, sway-backed, belly low, small ears**, a bristle crest
  down the spine, tail tassel, 60–85 kg. Not a pink straight-backed Landrace.
- **CAT** is a *puspin* — short-coated, and the **kinked or stumpy tail** is the single detail that
  reads as not-Western for one bone.
- **GOAT** is the Philippine native — **small and low-set, 10.5–24.4 kg, erect ears, straight horns**,
  black-brown. Long pendulous ears would make it an upgraded crossbreed.
- **CHICKEN** is a native breed — single comb, whitish earlobe, **grey/slate shanks**, hen ~1.0 kg.
- **VILLAGER** wears *sando* and *tsinelas*, or a *daster*. **Not a malong** — that is Bangsamoro and
  mainland Mindanao dress, and putting it on a generic lowland barrio villager is a real geographic
  error, flagged as such in the research.

`generate_mesh` works; `generate_material` is **intermittent** and was wrongly written off as broken
after four identical failures before thirteen of fourteen succeeded in a later session. **Retry before
concluding failure.** Two mechanical facts from the realism pass apply unchanged: `MeshPart.MeshId` is
not script-writable and fails *silently*, so `AssetService:CreateMeshPartAsync` is the only route; and
the ids recorded in the registry are the **only durable record**, because the meshes live in the
gitignored place file and `git log` will never have them.

#### Step 5.2: Register the six rig meshes, and teach the budget suite to count them

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-assets.test.luau`

The registry lives in the builder even though the rigs are spawned by a service, because that block is
what `tests/barrio-assets.test.luau` parses and what the triangle ceiling is asserted over. Splitting
the record across two files would put half the mesh budget outside the only check that counts it —
which is the defect being fixed.

```diff
 		{ Id = "Chapel", Asset = "rbxassetid://72865002641738", ... },
 	},
+
+	--[[
+		THE AMBIENT RIG MESHES — SIX FORMS, EIGHTEEN INSTANCES, AND UNTIL NOW UNBUDGETED.
+
+		These are spawned by `src/server/Services/AmbientService.luau`, not by this file, and they were
+		recorded ONLY as two asset ids per form inside `FORM_LOOKS`. So four generated meshes at
+		sixteen instances were spent against §5's non-negotiable mobile budget and counted by nothing —
+		`tests/barrio-assets.test.luau` sums `Meshes` and never knew these existed.
+
+		THEY ARE REGISTERED HERE RATHER THAN NEXT TO THE SERVICE for exactly that reason: this block is
+		what the budget suite parses. A registry the check cannot see is a comment.
+
+		ALL SIX WERE REGENERATED AT A STATED REQUEST, and that was the only honest way to bring them
+		inside a ceiling. The original four carried no recorded triangle count, and nothing in this
+		toolchain reads a MeshPart's triangle count back — so the choice was a budget built on a number
+		nobody could reproduce, or six new meshes at a number written down before they were made.
+
+		`Instances` IS `Config.Ambient.PerForm`, AND IT IS THE NUMBER THAT ACTUALLY COSTS FRAMES.
+		`Tris` is what one mesh requested; `Tris x Instances` is what the phone draws. The suite checks
+		both, because a 6,000-triangle hero at one instance and an 800-triangle bird at three are very
+		different spends that a single sum would report identically.
+	]]
+	RigMeshes = {
+		{ Id = "CAT", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 1200, Instances = 3, Prompt = "Philippine puspin street cat, short coat, lean, kinked stumpy tail, tabby-and-white" },
+		{ Id = "DOG", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 1400, Instances = 3, Prompt = "Philippine aspin street dog, light-boned, short rough coat, tail held high, one ear up one folded, semi-circular spots at tail base" },
+		{ Id = "PIG", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 1400, Instances = 3, Prompt = "Philippine native backyard pig, black, sway back, low belly, small ears, bristle crest along the spine, tufted tail" },
+		{ Id = "GOAT", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 1200, Instances = 3, Prompt = "Philippine native goat, small and low-set, erect ears, short straight horns, black-brown, rope collar" },
+		{ Id = "CHICKEN", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 800, Instances = 3, Prompt = "Philippine native chicken hen, brown and gold barred plumage, single comb, slate grey shanks, head low and pecking" },
+		{ Id = "VILLAGER", Asset = "rbxassetid://TBD", Texture = "rbxassetid://TBD", Tris = 1800, Instances = 3, Prompt = "rural Filipino villager standing, white sleeveless sando, work trousers, tsinelas sandals, straw salakot hat, weathered" },
+	},
 }
```

And the suite that counts it, in the same step — because a registry and the check that reads it are one
change, not two. A registry added alone would pass `barrio-assets` **without the suite ever looking at
it**, which is the self-satisfying shape this plan is trying to avoid.

**File:** `tests/barrio-assets.test.luau`

**The prop ceiling stays at 27,000 and is not raised to fit.** The rigs get their own ceiling because
they are a different kind of spend — few meshes, many instances, always on screen — and folding them
into one number would let a prop budget absorb a rig regression without anything failing.

```diff
 local TRI_CEILING = 27000
+
+--[[
+	THE RIGS' OWN CEILING, SEPARATE FROM THE PROPS' ON PURPOSE.
+
+	A prop mesh is placed once or twice and sits in fog at 200 studs. A rig mesh is placed THREE times
+	and one of them is standing next to the player, at night, being stared at because §4.5's whole
+	deduction is "which cat". They are not interchangeable triangles, and one sum would let a cheap
+	prop pass pay for an expensive rig.
+
+	1,500 PER RIG IS THE asset-pipeline SKILL'S LOWER PROP BAND, and rigs are held to the bottom of it
+	rather than the top because there are eighteen of them on screen at once.
+]]
+local RIG_TRI_CEILING = 9000
+local RIG_DRAWN_CEILING = 27000
```

```diff
+local rigTris = 0
+local rigDrawn = 0
+
+check("the registry carries a RigMeshes list", type(assets.RigMeshes) == "table")
+check(
+	"all six camouflage forms have a rig mesh",
+	#assets.RigMeshes == 6,
+	`{#assets.RigMeshes} row(s); Types.CamouflageForm names six`
+)
+
+for _, entry in assets.RigMeshes do
+	check(`{entry.Id} records an asset id`, string.match(tostring(entry.Asset), "^rbxassetid://%d+") ~= nil, tostring(entry.Asset))
+	check(`{entry.Id} records a texture id`, string.match(tostring(entry.Texture), "^rbxassetid://%d+") ~= nil, tostring(entry.Texture))
+	check(
+		`{entry.Id} is within the per-rig budget`,
+		type(entry.Tris) == "number" and entry.Tris >= 12 and entry.Tris <= 2000,
+		`Tris = {tostring(entry.Tris)}; eighteen rigs are on screen at once`
+	)
+	check(
+		`{entry.Id} records how many are spawned`,
+		entry.Instances == perForm,
+		`Instances = {tostring(entry.Instances)}, Config.Ambient.PerForm = {perForm}`
+	)
+
+	rigTris += (if type(entry.Tris) == "number" then entry.Tris else 0)
+	rigDrawn += (if type(entry.Tris) == "number" then entry.Tris * entry.Instances else 0)
+end
+
+check(`the six rig meshes total under {RIG_TRI_CEILING}`, rigTris <= RIG_TRI_CEILING, `{rigTris} requested`)
+check(
+	`the eighteen rig INSTANCES draw under {RIG_DRAWN_CEILING}`,
+	rigDrawn <= RIG_DRAWN_CEILING,
+	`{rigDrawn} triangles across {perForm} of each form — this is the number a phone pays`
+)
+
+--[[
+	AND THE IDS MUST MATCH THE SERVICE. The registry is the durable RECORD; `FORM_LOOKS` is what
+	actually loads. Two copies of an asset id is one copy too many, and the failure is silent: the
+	budget suite would happily certify a mesh the game never loads.
+]]
+local service = fs.readFile("src/server/Services/AmbientService.luau")
+
+for _, entry in assets.RigMeshes do
+	check(
+		`AmbientService loads the registered {entry.Id} mesh`,
+		string.find(service, tostring(entry.Asset), 1, true) ~= nil,
+		tostring(entry.Asset)
+	)
+end
```

#### Step 5.3: `FORM_LOOKS` gains the six regenerated ids

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run check:config`

The two Phase 1 placeholder rows get real ids and the four existing rows get their regenerated ones.
The `Size` values stay as Phase 1 set them — the mesh is scaled into that bounding box, so the
silhouettes stay the sizes the research and the budget were argued from.

Gated on `check:config` because that is what this step can actually break: twelve string literals go
into a service file, and every one needs its `-- config-ok:` waiver with a reason. Step 5.2's
cross-file id match is what proves the ids are *right*; this proves they were added the way this repo
requires, and the two failures are different.

#### Step 5.4: Photograph six forms side by side at distance

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/six-forms.md`

Six rigs in one frame at 40 studs and again at 120, at `ClockTime 0` under the shipped fog. §4.5's
deduction is "which cat", never "is that a cat" — **six silhouettes have to stay tellable apart, and
that is the requirement going from four to six actually puts at risk.** CAT (1.4 × 1.2 × 2.6) against
CHICKEN (0.8 × 1.1 × 1.4) at distance is the pair to check first; GOAT against DOG is the second.

No `Verify:` line. If two forms are confusable the fix is a `Size` change or a re-prompt, and no
command can tell you which.

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

- **Regenerating the four existing rigs changes the disguise the game already shipped.** That is the
  intent, and it is also the one thing in this phase that could go backwards: if a new CAT reads worse
  at distance than the old one, §4.5's deduction gets harder for everybody. Step 5.4 is the only gate,
  and the old ids stay in `git log` for this plan document even though they will not be in the place.
- **`Placed`/`Replaces` do not apply to rigs and `Instances` replaces them.** A rig mesh replaces no
  parts — it *is* the entity — so borrowing the props' columns would report a saving that does not
  exist.
- **The `-- config-ok:` waivers must be carried onto every new literal.** `check:config` sees a service
  file and does not know a mesh id from a balance number.
- **A failed `CreateMeshPartAsync` still falls back to the coloured box** and the slot survives. That
  path is now load-bearing for six forms rather than four, and it is the reason `Colour` stays on every
  row even after the mesh lands.

---

### Phase 6: Humanoid villagers, and the property-by-property parity audit

**Why this phase is last among the mechanics phases, and why it may end by undoing itself.**

A `Humanoid` replicates far more than a `Part`: `WalkSpeed`, `MoveDirection`, `HipHeight`, `Health`,
`MaxHealth`, `HumanoidStateType`, `DisplayDistanceType`, `RigType`, plus every `AnimationTrack` an
`Animator` is playing and every `Motor6D` transform those tracks drive. **Each one of those is a row in
the parity table**, and a puppeted villager whose Humanoid differs from a free one in any of them is a
free identity leak — the loudest of which is the obvious one: a free villager plays a walk cycle
because Roblox's locomotion drives it from `MoveDirection`, and a puppeted villager driven by `PivotTo`
has `MoveDirection` of zero and **slides across the ground in an idle pose at 16 studs/s.**

**That is not a subtle tell; it is a floodlight.** Which is why Step 6.1 writes the table before any
rig is built, and why Step 6.6 — reverting VILLAGER to the mesh built in Phase 5 — is a **documented
outcome of this phase rather than a failure of it.**

#### Step 6.1: Enumerate every replicated Humanoid property, and answer each one

**File:** `.claude/plans/feature-barrio-population-plan/references/humanoid-parity.md`
**Verify:** `test -f .claude/plans/feature-barrio-population-plan/references/humanoid-parity.md`

One row per replicated property, each answering: *what is its value on a free villager, what is its
value on a puppeted one, and what makes them equal?* The rule from the preamble decides every row —
speed may differ, nothing else may.

**If any row cannot be answered, the phase ends at Step 6.6.** The table is the gate, and it is written
first so that the answer is reached before the sunk cost of a rig.

`test -f` proves only that the file exists, which is weak and is the honest ceiling here: no command
can grade a design argument. It is paired with Step 6.5, which is the capture that can actually falsify
the table.

#### Step 6.2: The animation driver is displacement-driven, for free and claimed alike

**File:** `src/shared/pure/AmbientMotion.luau`
**Verify:** `lune run tests/ambient-motion.test.luau`

The fix for the sliding-villager leak is the same architectural move Phase 4 made for the animals:
**never let Roblox's Humanoid locomotion drive the animation, because it cannot see a `PivotTo`.**

```diff
+--[[
+	HOW FAST TO PLAY A WALK CYCLE, GIVEN HOW FAR THE RIG ACTUALLY MOVED (Phase 6).
+
+	THIS FUNCTION EXISTS BECAUSE `Humanoid.MoveDirection` CANNOT SEE A `PivotTo`. A free villager
+	walked by Roblox's locomotion has a non-zero MoveDirection and plays its walk; a PUPPETED villager
+	is pivoted every frame and has MoveDirection of ZERO, so it slides across the barrio in an idle
+	pose at the monster's running speed. That is the single loudest tell available in this game and it
+	arrives free with any naive Humanoid rig.
+
+	SO NEITHER RIG USES THE HUMANOID'S LOCOMOTION AT ALL. Both play a walk track whose `Speed` comes
+	from measured displacement through this function — the same source `bobOffset` and `swayDegrees`
+	already read. One driver, two targets, and the only difference is the number.
+
+	THE FLOOR IS NOT ZERO. A track at Speed 0 is a frozen pose, and a villager frozen mid-stride is as
+	readable as one sliding. A stationary rig plays its walk at the idle floor, which reads as weight
+	shifting rather than as walking.
+]]
+function AmbientMotion.strideRate(speed: number, tuning: Tuning): number
+	return tuning.IdleHz + speed * tuning.StrideHzPerStud
+end
```

with the matching assertions: monotonic in speed, never zero, continuous, and equal for equal speeds
regardless of caller.

#### Step 6.3: Build the villager rig with its state machine disabled

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `npm run analyze`

Every property the table settles, set **identically for all three villagers**, free or claimed. The
rig is a Humanoid for its `Animator` and for nothing else.

```diff
+--[[
+	A VILLAGER IS AN R15 HUMANOID, AND EVERY PROPERTY BELOW IS SET THE SAME WAY ON ALL THREE.
+
+	`EvaluateStateMachine = false` AND AN ANCHORED ROOT, so Roblox never runs physics, never fires
+	`Died`, never changes `HumanoidStateType`, and never drives locomotion. That is not an
+	optimisation — a state machine is a source of REPLICATED STATE THAT VARIES WITH WHAT THE RIG IS
+	DOING, and a puppeted rig does different things from a free one. Turning it off removes the whole
+	category rather than matching it property by property.
+
+	`DisplayDistanceType = None`, because a Humanoid draws a name plate by default and the model is
+	named `Ambient_VILLAGER_2`. `MonsterService.hideCharacter` already sets this on the PLAYER for the
+	same reason; a rig that announced itself would be the mirror of that bug.
+
+	`MaxHealth = 0` RATHER THAN A LARGE NUMBER. Zero disables the health bar outright; any positive
+	value is a bar that can be shown, and a bar is a per-rig visible property. Nothing damages these.
+
+	THE ANIMATION IS DRIVEN FROM DISPLACEMENT AND NEVER FROM THE HUMANOID. See `AmbientMotion
+	.strideRate` — this is the seam where a sliding puppeted villager would come from.
+]]
```

#### Step 6.4: Config for the villager rig's animation ids and stride

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

Roblox's built-in R15 walk and idle animation asset ids, plus `StrideHzPerStud`. **The ids are a
Roblox-platform fact this plan has not verified** — whether the default catalogue animations load on a
non-player Humanoid through an `Animator` is exactly the class of thing CLAUDE.md forbids guessing, and
it is in Follow Ups rather than asserted here.

#### Step 6.5: Two villagers side by side, one puppeted, in the running game

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/villager-parity.md`

The capture that can actually falsify Step 6.1's table: two villagers, one claimed and one free, **both
stationary**, then the monster walks. Watch for a pose difference at rest, a name plate, a health bar,
a foot-slide, and a stride that starts or stops at a different moment.

No `Verify:` line, and this is the step the whole phase turns on.

#### Step 6.6: The fallback, if any row of 6.1 could not be answered

**File:** `src/server/Services/AmbientService.luau`
**Verify:** `lune run tests/barrio-assets.test.luau`

Reverting VILLAGER to the mesh rig is **one row of `FORM_LOOKS` and the deletion of the Humanoid
branch** — which is why Phase 5 generated a VILLAGER mesh even though Phase 6 intended to replace it.
The fallback costs nothing to keep available and everything to reconstruct later.

**Take this exit if any of these is true after Step 6.5:** a free and a puppeted villager differ at
rest in any capture; the built-in animations do not load on a non-player Humanoid; or three Humanoids
measurably cost frames on the phone that `artifacts/final-population-perf.md` will report.

**A mesh villager is not a downgrade to the mechanic, only to the art.** The disguise is whatever rig
the barrio is standing in, and a mesh villager that is *indistinguishable* is worth more than a
Humanoid villager that is *better and tellable*.

#### Phase 6 — Potential Issues

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

- **Three R15 Humanoids replace three MeshParts: roughly +45 instances.** That is the single largest
  instance cost in this plan and it is spent on the form least likely to survive Step 6.6. Counted in
  Phase 8's ceiling either way.
- **`AmbientService.luau`'s own header says "NO HUMANOID, NO PATHFINDING, NO PHYSICS"** and gives the
  reason: sixteen Humanoids on a phone. This phase adds three and must **rewrite that paragraph rather
  than leave it contradicted** — a header that describes a rule the file below it breaks is worse than
  no header. The reason it is now acceptable is that the state machine is off and physics never runs,
  which is a different thing from what the paragraph refused.
- **A Humanoid is the one rig type whose body height is not a single `Size.Y`**, so Phase 2's
  `AmbientRig` needs the villager's foot-to-centre distance supplied from the rig rather than from
  `body.Size.Y / 2`. Getting this wrong reintroduces exactly the floating-rig leak Phase 2 closed, on
  the tallest form.
- **`Humanoid.Died` cannot fire with the state machine disabled** — but if a later change re-enables
  it, `Died` on a rig standing where the monster is would be a broadcastable event. Nothing subscribes
  to it today and nothing should.
- **`check:secrecy` will report green throughout this phase.** It matches role tokens in tag names,
  attributes and payload fields, and every leak considered here is a property value on a public model.

---

### Phase 7: Seven interiors, and cladding that cannot move the navmesh

#### Step 7.1: Open `Kubo_E` and `Kubo_W` with a single inward door each

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-contract.test.luau`

```diff
-	{ Name = "Kubo_E", X = 158, Z = -30, Doors = {}, Enterable = false },
-	{ Name = "Kubo_W", X = -158, Z = 40, Doors = {}, Enterable = false },
+	--[[
+		OPENED, AND WITH ONE DOOR EACH ON THE INWARD FACE. Both now carry interiors, so all seven kubo
+		are enterable against §5's "at least 5".
+
+		ONE DOOR, NOT TWO, AND THAT IS THE WHOLE SIGHTLINE ARGUMENT. See Step 7.2: a single doorway in
+		one face of a 24 x 20 building removes no occlusion, because what breaks a sightline is the
+		building's MASS and the mass is unchanged. Two opposed doors would cut a window through the
+		house and would need the compensation the brief asked about.
+
+		INWARD, like the other five, for the reason the SW/N pair already records: an outward door puts
+		its threshold in the dead band between the ring and the perimeter, where nobody walks.
+	]]
+	{ Name = "Kubo_E", X = 158, Z = -30, Doors = { W = true }, Enterable = true },
+	{ Name = "Kubo_W", X = -158, Z = 40, Doors = { E = true }, Enterable = true },
```

#### Step 7.2: Answer the sightline question from the geometry rather than from the comment

**File:** `.claude/plans/feature-barrio-population-plan/references/sightline-compensation.md`
**Verify:** `test -f .claude/plans/feature-barrio-population-plan/references/sightline-compensation.md`

**The brief asked for the compensation, and the honest finding is that none is needed.** The reasoning
belongs in a reference rather than in a comment, because it is an argument someone will want to
re-check:

The builder's own comment says the two sealed kubo "exist to BREAK SIGHTLINES so the sightline rule can
be partial rather than absent" (`barrio.luau:944-947`). But `building()` constructs a side with a door
as **two wall segments with a gap between them** (`:388-391`); the other three sides stay solid slabs
and the roof is unchanged. So after this step each house is still a closed 24 × 20 × 9 volume with one
10-stud gap in one face.

**Occlusion comes from the mass, and the mass does not move.** You cannot see through the house on any
axis, because no two doors are opposite. What changes is that a player may now stand *inside*, which is
a gameplay change and not a sightline one — and §5's rule ("almost always see *something*, almost never
everything") is about what is visible from outdoors.

The reference records this with the line cites, states what would invalidate it (**a second door on any
of these two houses**), and names the check that would catch the real risk instead: `measure.luau`'s
loop test, which seals each corridor in turn and re-checks reachability, and which is Step 7.6.

#### Step 7.3: The cladding rule — mesh for looks, greybox for collision

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-assets.test.luau`

Gated on `barrio-assets` because this step moves two numbers in the mesh registry — `KuboShell`'s
`Placed` from 2 to 7 and `Chapel`'s from 0 to 1 — and that suite is what reconciles the registry against
what the builder actually places.

**The brief offered two options — retire the `KuboShell` or split it into shell-plus-interior — and the
answer is neither.** Both assume the mesh must do the collision. It must not, and the rule that says so
is already the load-bearing rule of the entire dressing pass:

> Nothing in `Dressing` collides. PathfindingService builds its navmesh from collision geometry, so a
> non-collidable prop cannot move a route, cannot lengthen a walk, and cannot change the number
> `measure.luau` reports. (`barrio.luau`, C30 RULE 1, asserted at build time)

So the shell becomes **cladding**: the mesh is placed `CanCollide = false` over the greybox walls,
which stay exactly where they are and keep their doorway, and are made invisible rather than deleted.
The player collides with the box; the camera sees the mesh.

**Three things fall out of that, and they are why this is the better answer:**

1. **All seven kubo get the good geometry**, not the two that happened to be sealed. `Placed` goes
   2 → 7 and `Tris` does not move, because `Tris` is per mesh and not per instance.
2. **The chapel mesh can finally be placed.** It is recorded at `Placed = 0` with a comment explaining
   that a solid shell would bury the two search containers inside it — which was true of a *collidable*
   shell. Cladding occludes nothing that the greybox chapel's own walls did not already occlude, and
   the doorways stay. That is 6,000 triangles already spent and currently drawing nothing.
3. **The crossing time is unchanged by construction**, not by measurement. Step 7.6 confirms rather
   than discovers, which is the only way a navmesh claim is ever safe.

The cladding must sit **outside** the greybox walls by the wall thickness so the interior is not
z-fighting against it, and the doorway gap in the mesh must line up with the gap in the boxes — which
is a `generate_mesh` prompt requirement (an open doorway on one face) and the reason the kubo mesh is
re-generated rather than reused as-is.

#### Step 7.4: The interiors suite

**File:** `tests/barrio-interiors.test.luau`
**Verify:** `test -f tests/barrio-interiors.test.luau`

Written BEFORE the kit it checks, and gated on existence rather than exit 0 — the same red-then-green
shape as Steps 2.1, 3.1 and 4.1. Step 7.5 is where it turns green.

Written as a Lune suite and **not as greps**, for the reason the realism plan learned the hard way: the
helper writes `{name}_Banggera` and a literal `grep -c Kubo_NW_Banggera` cannot match an interpolation.
Anything built in a loop needs a suite.

What it asserts, all of which are structural and can fail:

- All seven kubo appear in the interior table, and their coordinates match the `KUBO` table — the same
  class of bug as `Container_KuboN_Drum` being authored forty studs outside `Kubo_N`.
- Every kubo the `KUBO` table marks `Enterable` has at least one door in its `Doors` set, and there are
  now seven of them. This is the assertion that would catch a re-sealed house.
- **No kubo has two opposed doors** — the invariant Step 7.2's argument rests on, pinned so that the
  sightline reasoning cannot be invalidated silently.
- The cladding is `CanCollide = false` and the greybox walls survive rather than being deleted; the
  builder's own zero-dressing-collider assert covers the first half, and this covers the second.
- Every `SearchContainer` sited inside a kubo is inside one that is `Enterable`.

#### Step 7.5: The interior kit

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-interiors.test.luau`

Gated on Step 7.4's suite, which was written first and is red until this step lands. It is the
strongest check available here: it asserts every kubo's interior by name against the `KUBO` table,
which is what a helper writing `{name}_Banggera` in a loop needs and what a literal grep cannot do.

A single `interior(name, cx, cz, tier)` helper, so seven houses are one edit rather than seven, and so
the instance cost is a number in one place. Contents from
`references/research-03-kubo-interiors.md`, ranked by how unmistakably each reads:

| Prop | Why it earns its parts |
| --- | --- |
| **Banggera** | The slatted counter projecting out of a window — cups inverted on upright sticks, plates edge-on between slats, a clay jar at one end. The single most "this is Filipino" object available, and it reads from *outside* the house |
| **Altar** | Santo Niño, candles, and framed photographs of the dead standing beside the saints. `Neon` candles, never a `PointLight` |
| **Tampipi** | Woven lidded trunk. The vernacular storage chest — a carved hardwood `baul` is a *bahay na bato* object and would be wrong in six of these seven houses |
| **Banga / tapayan** | Clay jar, 30–100 cm sourced range, unglazed |
| **Papag + banig** | Bamboo platform bed, rolled sleeping mat |
| **Kalan** | Earthenware charcoal stove on its packed-earth `abuhan` |
| **Tabo in a timba** | A dipper floating in a pail by the door. Two objects, zero cost |
| **Tukod window** | The awning panel propped open on a stick — the traditional window, and a physical affordance a horror game can use |

**Three tiers, and the tiers are where the instance budget is repaid.** `Kubo_E` and `Kubo_W` sit
outside the ring, hold no `SearchContainer`, and therefore have no gameplay reason to be entered —
they get the **sparse** tier: a papag, a jar, a window. The five inside the ring hold containers and
get the **full** tier. One house gets the **rich** tier with capiz sliding panes and a *ventanilla*,
which is the sourced way to say "this family has money" and gives the barrio a captain's house.

**Not one new `PointLight`.** Every lit-looking thing is `Neon`, exactly as the container glow bands
and banderitas bulbs already are. Fourteen `MapLight` before this phase and fourteen after.

#### Step 7.6: Re-measure the crossing time

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/crossing-after-interiors.md`
**Verify:** `test -f .claude/plans/feature-barrio-population-plan/artifacts/crossing-after-interiors.md`

`measure.luau` in Edit mode through the README's HTTP-serve pattern. All ten lines, not just the
crossing — the loop test is what proves the two new doorways did not create a dead end, and the reach
test is what proves no container ended up behind a wall.

**34.8s must stay inside 30–40s.** It should be unchanged, because cladding does not collide and the
new doorways are outside the ring on houses no route passes through. **If it moved, the cladding
collided somewhere** — that is the first thing to check, and the builder's `dressColliders == 0` assert
should have failed first.

`test -f` proves the artifact exists, not that it says 34.8. That gap is why the artifact must paste
`measure.luau`'s ten lines verbatim rather than summarise them.

#### Phase 7 — Potential Issues

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

- **Opening both remaining kubo means every house is now enterable, which §5 does not ask for.** Five
  is the floor; seven is a choice, and its real cost is that two houses now have interiors nobody has a
  reason to visit. The sparse tier is the mitigation, and if the instance ceiling is tight at Phase 8
  these two interiors are the first thing to cut.
- **The bamboo `sahig` you can see through is an inference, not a source.** Airflow through slats
  implies gaps; no source says the floor is see-through. Build it, and know which it is.
- **The roof should probably be rusted GI, not nipa.** 85.9% of Philippine dwellings have galvanised
  iron roofs against 4.7% cogon/nipa. The map is all-nipa. That is a defensible period/remote-barrio
  choice but it should be a **deliberate** one — flagged in Follow Ups rather than changed here, since
  the realism plan already tuned nipa ageing and this plan should not relitigate its palette.
- **`measure.luau` is the only thing standing between this phase and a silent navmesh change**, and the
  realism plan's Phase 2 records exactly what a broken `measure.luau` costs: `GetTagged` on a dead tag
  returns an empty list, so the script walked a fraction of the map and printed a healthy crossing time
  over it. Check the tag counts in its output, not only the `ok`s.

---

### Phase 8: Lanterns, the power line, and a budget that fails the build

#### Step 8.1: The twelve street lanterns

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-lighting.test.luau`

24 parts, and they are the light sources a player looks at all night — the highest value-per-part in
the map. The research gives a specific, cheap and genuinely Filipino answer:

**Two eras on the same street, and the fixture silhouette is the era signal.** A **cobra head** — a
curved tapered housing on a bracket arm — is the old sodium fixture: 1900–2200 K, **CRI ~22**, which
means the pool is near-monochrome amber and colours *die* in it rather than merely being tinted. A
**flat wedge** sitting horizontally at the top of the arm is an integrated solar LED at 4000–6500 K
with a hard-edged pool. Mixing them is what a real barangay looks like today.

**And roughly one in four should be dark** — barangay streetlight budgets lose to education, health and
waste, and broken fixtures are documented and normal. That is not decay-dressing: **a dark lantern
costs no light slot**, so the ratio is where this step pays for its own parts, and it sharpens §5's
"partial information" rule better than any amount of fog.

Gated on `barrio-lighting`, which already pins which properties the builder owns and caps `Ambient` at
rgb ≤ 30 per channel; it gains the fixture-count and dark-ratio assertions.

**The `MapLight` tag rule is unchanged and is the one thing here that must not slip.** A lantern's
`PointLight` is tagged so `PerformanceController` may cull it. The Aswang's eye glow and a salt pouch's
glow must **never** carry that tag — they are §4.3's warning and §4.6's counterplay, and the culler
would obediently switch off the only warning a survivor gets.

#### Step 8.2: The power line

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-budget.test.luau`

92 parts, and it dominates the skyline. Five corrections from the research, in descending value:

1. **Two conductors, not six.** A rural single-phase feeder is phase-plus-neutral on one short
   crossarm. The builder already draws two wires per span — that is correct and should stay correct;
   the six-wire three-phase rack a Western reference photo gives reads as suburban America.
2. **The telecom bundle is a separate, lower, messier zone.** "Spaghetti wires" is the established
   Philippine term. Power is few, taut, high, evenly spaced; telecom is many, sagging, low, chaotic.
   **The vertical separation between the two zones is the whole visual grammar**, and the barrio has
   only the top zone today.
3. **Concrete, not wood.** The builder paints poles `WOOD` with `Enum.Material.Wood`. Philippine
   distribution poles are commonly prestressed concrete in a tapered **rectangular I-section** with a
   visible longitudinal flute — `RustedSteel` and `HollowBlock` are already in the material registry.
4. **Yellow guy guards.** An 8 ft high-visibility plastic sleeve on the down-guy at ~45°. It is a
   saturated yellow in an otherwise grey-brown scene, it catches a torch beam, and it silhouettes —
   the best cost-per-read prop in this step.
5. **One transformer can per rural pole, not a bank of three.** ~0.5 m diameter × 0.9 m, two porcelain
   bushings on the lid, mounted to the pole face below the crossarm. Three cans is a three-phase town
   centre. Plus **fibre slack loops** — a flattened black coil hanging below the telecom bundle — and
   2 × 3 ft campaign tarpaulins cable-tied at 1.5–2.5 m, which are illegal to post there and therefore
   posted there constantly.

#### Step 8.3: Planting, house clutter and plaza dressing

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-materials.test.luau`

Gated on `barrio-materials`, which asserts every registered surface actually has a variant and guards
the four texture-map ids per row — the check that fails when new sawali, bamboo and cloth geometry is
painted with a material id that does not resolve, which is this file's favourite silent failure.

Planting (135), house clutter (109) and plaza dressing (111). The bamboo is already clumping rather
than running, which the realism plan fixed and which is the biggest single thing to get right — so the
work here is the **fence**, and the research names the one nobody builds:

**A living kakawate fence.** *Gliricidia sepium*'s English common name is literally "Fence Post Tree",
and the sourced propagation method is to cut hardwood stakes 1.5–2 m long and 5–8 cm across and plant
them **as the fence posts**, where they sprout. So the posts carry leaves and thin new branches at
irregular heights, with wire or bamboo strung between — and some sprout vigorously while some do not,
so the line is ragged. It is a distinctive silhouette from a variation on posts the map already has.

Plus **sawali panels in a twill/diagonal weave** — the diagonal is the identity, and a plain
over-one-under-one checkerboard reads as a generic basket — and, for the plaza, the flagpole, the
banderitas wire and the court lines the brief names.

**This step also pays the territory debt from Phase 3.** Every one of the eighteen ambient points owes
the prop that justifies it: a wallow at each pig territory, a stake and rope at each goat territory, a
yard boundary at each chicken territory. **A territory with no prop is a rule the player cannot see**,
and an invisible rule is a trap rather than counterplay — which is the whole argument for per-form
territories being good design.

#### Step 8.4: The fourth build-failing assert — total instances

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-receipt.test.luau`

```diff
+--[[
+	THE INSTANCE CEILING, AS A BUILD FAILURE RATHER THAN A PRINTED NUMBER.
+
+	Colliders and lights already fail the build; the instance count was only ever printed, and it is
+	the budget line THIS plan spends hardest — seven interiors, six upgraded rig meshes and a detailed
+	power line, against §5's non-negotiable mobile budget with 60% of players on a phone.
+
+	A PRINTED NUMBER IS A NUMBER NOBODY READS, and the realism plan proved that from the other side:
+	its Phase 7 deleted the fence runs, the banana table and the scarecrow loop by miscounting `end`
+	lines, and the instance count went DOWN — which is exactly what that phase was trying to do, so
+	the loss read as the saving working. Every gate was green. It was caught by hand-counting MeshParts
+	in the live map.
+
+	SO THE CEILING IS A BAND, NOT A MAXIMUM. Too many parts is a phone dropping frames; too FEW is a
+	deletion wearing the costume of an optimisation.
+]]
+local instanceCount = #root:GetDescendants()
+
+assert(
+	instanceCount <= 1450,
+	`[barrio] {instanceCount} instances, ceiling 1450 — §5's mobile budget, and 60% of players are on a phone`
+)
+assert(
+	instanceCount >= 1250,
+	`[barrio] only {instanceCount} instances — something was DELETED. A count that falls is not a saving; check the fence runs, BANANA_AT and the scarecrow loop first`
+)
```

#### Step 8.5: Final measure and the perf receipt

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/final-population-perf.md`
**Verify:** `test -f .claude/plans/feature-barrio-population-plan/artifacts/final-population-perf.md`

The preamble's budget table with the "After" column filled in from the running place: instance count,
`MapLight` count, dressing colliders, dressing lights, `measure.luau`'s ten lines, the rig triangle
totals, and **FPS on a real phone** — the one number the realism plan finished without and the only
one §5 actually specifies.

#### Step 8.6: Publish the place

**File:** `.claude/plans/feature-barrio-population-plan/artifacts/final-population-perf.md`

`File → Publish to Roblox`. Neither script can do it and the place file is the only copy of the map:
seven interiors, six rig meshes and eighteen re-sited spawn points exist in exactly one binary that is
not in git. **Until this is done, the whole plan is one unsaved Studio session from gone.**

No `Verify:` line, because no command can prove a human did it — and inventing one here would be the
worst possible false green, since the thing it would falsely certify is the backup.

#### Phase 8 — Potential Issues

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

- **The dark-lantern ratio is unsourced.** That broken barangay streetlights are common *is* sourced;
  "one in four" is convention. It is also a gameplay lever rather than only a look, so it belongs in
  V16's balance questions and not in a builder constant nobody revisits.
- **The whole-barangay brownout is sourced, mechanically interesting, and out of scope.** Rural
  single-feeder topology means the barrio goes dark *at once*, and the lights that survive are exactly
  the solar ones that were never on the wire. That is a §3 question, not an art one — the realism plan
  deferred the identical finding for the identical reason, and this plan defers it again rather than
  quietly building half of it.
- **`instanceCount >= 1250` will be the assert that fires**, and it will look like a bug in the assert.
  It is not. Read the realism plan's Phase 7 before weakening it.
- **The territory props are the coupling between Phase 3 and this phase**, and they are the one thing
  here that is not merely decoration. If Phase 8 is run as a separate session from Phases 1–6, this is
  the debt to carry across — it is named in `AmbientService`'s map-contract header for that reason.
- **`HttpEnabled` must go back to `false`** when the HTTP-serve pattern is finished with. It is a
  published place setting, not a local one.

---

## 3. Related Files

**Changed by this plan**

| File | Phases | What changes |
| --- | --- | --- |
| `src/shared/Types.luau` | 1 | `CamouflageForm` widens to six literals |
| `src/shared/Enums.luau` | 1 | two members, each with its `:: Types.CamouflageForm` cast |
| `src/shared/pure/AmbientRoster.luau` | 1 | the re-declared union only; **no logic changes** |
| `src/shared/pure/CamouflageRules.luau` | 1 | the re-declared union only; **no logic changes** |
| `src/shared/Config.luau` | 1, 2, 3, 4, 6 | `PerForm` 4→3; ground probe; `ClaimRadius`; five motion numbers; villager stride |
| `src/shared/pure/AmbientRig.luau` | 2 | **new** — resting and puppeted height, the two that must agree |
| `src/shared/pure/AmbientTerritory.luau` | 3 | **new** — which form belongs where, and which slot is claimable |
| `src/shared/pure/AmbientMotion.luau` | 4, 6 | **new** — bob, sway, phase offset, stride rate |
| `src/server/Services/AmbientService.luau` | 1–6 | forms, ground seating, territories, one motion driver, Humanoid villagers |
| `src/server/Services/MonsterService.luau` | 2, 3 | foot offset measured and passed; position passed to the claim |
| `tools/greybox/barrio.luau` | 3, 5, 7, 8 | 18 form-tagged spawns; rig registry; interiors and cladding; dressing; instance assert |
| `tests/camouflage-forms.test.luau` | 1 | **new** — the six-form set across seven declaration sites |
| `tests/ambient-rig.test.luau` | 2 | **new** |
| `tests/ambient-territory.test.luau` | 3 | **new** |
| `tests/ambient-motion.test.luau` | 4, 6 | **new** |
| `tests/barrio-interiors.test.luau` | 7 | **new** |
| `tests/config.test.luau` | 1 | a `PerForm` ceiling to match the existing floor |
| `tests/barrio-ambient.test.luau` | 3 | six forms, form-tagged points, per-form counts |
| `tests/barrio-assets.test.luau` | 5 | the rig registry, its own ceiling, and the cross-file id match |
| `tests/barrio-budget.test.luau` · `tests/barrio-lighting.test.luau` · `tests/barrio-contract.test.luau` · `tests/barrio-receipt.test.luau` | 7, 8 | extended for cladding, lanterns, seven interiors, the instance band |

**Read but not changed** — reviewed in `references/`: `src/server/Services/QuickChatService.luau`,
`src/shared/pure/QuickChatPhrases.luau`, `src/shared/Remotes.luau`, `tools/greybox/measure.luau`,
`docs/MVP-SPEC.md` §4.3/§4.5/§5/§6.2, `docs/BUILD-PLAN.md`,
`.claude/plans/feature-barrio-realism-plan/implementation-log.md`.

**Untouched, deliberately:** `src/shared/Remotes.luau`. This plan adds no remote and widens no payload.

---

## 4. Follow Ups

### Questions / Clarifications

**1. The `"It's the [animal]!"` phrase does not exist, and it cannot be built the way the brief
assumed.** This is the most important finding in the plan and it changes the brief's premise.

The brief said two new animals mean two new phrases. In fact:

- **There is no animal accusation phrase at all.** The shipped `ACCUSE` is `"It's {name}!"` and names a
  **player**, resolved server-side by range and a 60° FOV cone (`QuickChatPhrases.luau:108-117`).
- **The wheel is eight phrases in eight sectors, closed**, and `tests/quick-chat-phrases.test.luau`
  hard-asserts `#All == 8` with one sector per phrase. **Per-animal phrases are structurally
  impossible**: six forms would need six of the eight sectors.
- **The shipped set is v1.3's.** §4.5's v2.0 list drops `ACCUSE` and `TRUST_ME` and adds
  `"It's the [animal]!"` and `"I have the buntot pagi"`. Nothing has done that rewrite, and
  `docs/BUILD-PLAN.md` lists quick-chat plumbing under "survives untouched" — so it is genuinely
  unowned work rather than something a V-chunk is holding.

**The right design is one phrase parameterised by form**, resolved server-side the way `ACCUSE` already
resolves a player: the nearest ambient entity in the sender's view cone, its form carried as an id on
`QuickChatBroadcastPayload` and rendered locally. Adding forms then costs zero phrases, forever.

**It is deferred, and the deferral is a decision rather than an omission.** It drops two shipped
phrases (a design decision with playtest consequences), adds a field to `QuickChatBroadcast` (a 🔒
remote), and would be the second new risk class in a plan already carrying Humanoids. **It should be
the very next chunk**, because until it lands, doubling the form count makes camouflage *harder to
counter*: §4.5 calls the animal phrase the thing "without which camouflage is unbeatable", and this
plan raises the number of things it cannot name from four to six. That is a real, accepted balance
regression for the duration.

**2. `Humanoid.HipHeight`'s reference point is unverified.** Nothing in `src/` reads it. Whether it
measures from the root's centre or its underside changes Phase 2's offset by ~1 stud — small enough to
look like a modelling choice, large enough to be a tell. Step 2.6's capture is the only thing that
settles it; do not infer it from documentation.

**3. Whether Roblox's built-in R15 walk and idle animations load on a non-player Humanoid through an
`Animator`, at a scripted `Speed`, is unverified.** Phase 6 depends on it entirely and Step 6.6 is the
exit if it does not hold.

**4. Nothing in this toolchain reads a `MeshPart`'s triangle count back**, which is why Phase 5
regenerates all six rigs rather than measuring the four that exist. If such an API is confirmed later,
the four could have been kept.

**5. The Aswang is not told where its form's territory is.** It learns its form from
`CamouflageUpdatePayload.Form` and learns "not here" from a `CAMO_NO_SLOT` refusal, by trial. Whether
a player can distinguish "no pigs left" from "no pig territory here" is a HUD question — **V15**, and
it is the difference between a tactical constraint and an opaque one.

**6. `Config.Ambient.ClaimRadius = 18` is a guess and V16 should move it.** It is the whole strength of
the territory constraint and the bound on the visible jump on claim. It has no playtest behind it.

**7. The roof material is probably wrong across the whole map.** 85.9% of Philippine dwellings have
galvanised-iron roofs against 4.7% cogon/nipa; the barrio is all-nipa. That is a defensible
remote-barrio choice but it should be deliberate. Raised rather than changed, because the realism plan
tuned the nipa palette and this plan should not relitigate it.

**8. Whole-barangay brownouts are sourced and out of scope.** Rural single-feeder topology means the
barrio goes dark at once, and the surviving lights are exactly the solar ones never on the wire. That
is a **mechanic**, and mechanics come from §3. The realism plan deferred the identical finding for the
identical reason.

**9. Ambient animal audio is deferred to V14, deliberately, and the brief asked which.** Eighteen rigs
with a `Sound` each is a fourth parity surface — a puppeted pig that stops grunting, or grunts while
gliding, is the same class of leak as a villager that slides. V14 owns atmosphere, is a hard gate on
V16, and is the right place. **The rule it must obey is in this plan's preamble**: one driver, and the
claim changes only the input. The pig sound effect the brief asked for should be sourced then, via
`search_asset` with `assetType: "Audio"` and `priceFilter: "free"`.

**10. Six silhouettes may not stay tellable apart, and that is the design risk of decision 1.** §4.5's
deduction is "which cat", never "is that a cat". CAT against CHICKEN at distance in fog is the pair
most likely to collapse. Step 5.4 is the gate and the fix is a `Size` change, not a re-plan.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| — (pre-existing) | **The camouflaged Aswang's character is invisible but still present.** `hideCharacter` sets `Transparency = 1` on every descendant (`MonsterService.luau:978-992`). Part transparency replicates, so a client can scan `Players` for the one character whose parts are *all* fully transparent. That is `absence-is-observable` exactly, and `check:secrecy` cannot see it. **Pre-existing from V07 and out of scope here**, but this plan touches the camouflage path and must not leave it unrecorded | **High** | For `exploit-auditor` to confirm and for its own fix |
| 2 (pre-existing) | **The disguised rig floats ~2.6 studs above every real one of its form**, and every free rig is sunk into the ground by half its own height. A static, one-frame-readable difference. Found by reading `buildEntity:278` against `PuppetSlot:330` and `anchor()` | **High** | Fixed in Phase 2 |
| 3 (pre-existing) | **A claim jerks an ambient animal across the barrio in one frame**, because `PuppetSlot` drives the claimed rig onto the monster's CFrame wherever it stands. Harmless-looking today; an answer once territories exist | **Medium** | Fixed in Phase 3 by bounding the claim to `ClaimRadius` |
| 4 (pre-existing) | **Free and claimed rigs are moved by two different functions in two files.** Any motion added to one and not the other makes the disguise the only thing that does not move like the others | **Medium** | Fixed in Phase 4 by one step function |
| 5 (pre-existing) | **The four ambient rig meshes are in no registry and no triangle budget.** `tests/barrio-assets.test.luau` sums only `ASSETS.Meshes`; four meshes at sixteen instances were spent against §5 and counted by nothing | **Medium** | Fixed in Phase 5 |
| 6 | **A puppeted R15 villager slides in an idle pose at the monster's speed**, because `Humanoid.MoveDirection` cannot see a `PivotTo`. The loudest tell available in this game, and it arrives free with any naive Humanoid rig | **High** | Designed against in 6.2; Step 6.6 is the exit if it cannot be closed |
| 1 | **`check:scope` arms `pets?`** and two new animals is the shape it exists to catch. The defence is `Types.luau`'s existing sentence — forms the Aswang wears, owned by nobody, purchasable never (§8.3) | **Low** | Waiver with that reason if it fires; not a rename |
| 1 | **`tests/barrio-ambient.test.luau` goes red at Step 1.4 and stays red until Phase 3.** Expected and named so it is not "fixed" by weakening the suite | **Low** | By design |
| — | **The quick-chat wheel cannot name six forms, or four.** See Questions 1 | **High** | Deferred to its own chunk; recommended next |
| 7 | **All seven kubo enterable exceeds §5's floor of five**, and two of them hold no container so nobody has a reason to enter. The sparse tier is the mitigation and these two interiors are the first cut if the instance ceiling binds | **Low** | Accepted, per decision 4 |
