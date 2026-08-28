# V07 — Camouflage and smoke · implementation log

Plan: `feature-v07-camouflage-smoke-plan.md` · run `2026-08-28T12-38-54-894Z-V07` · base `64d0cfa`

---

## Phase 1 — The gate, proven before anything can call it

**Status:** complete. 5/5 steps.

### Step 1.1 — Create `CamouflageRules` with the four-input gate
`src/shared/pure/CamouflageRules.luau:1-172`. `evaluate(request) -> Verdict` over
`(HasBeenRevealed, HasCharge, MonsterState, Phase, SlotAvailable)`, reveal test first and
unconditional. No `script.Parent` requires; the three unions are re-declared locally.
**Verify:** `test -f src/shared/pure/CamouflageRules.luau` — passes.

### Step 1.2 — Reveal and charge transition functions
`CamouflageRules.luau:174-232`. `revealedAfter` (only `SALT_HIT` reveals, one-way) and `chargeAfter`
(only `FEED_COMPLETED` restores, `CAMOUFLAGE_ENTERED` spends) over the eight-value `MonsterEvent`
enum.
**Verify:** `npm run analyze` — `analyze: ok`.

### Step 1.3 — Smoke gate and the segment/sphere predicate
`CamouflageRules.luau:234-314`. `evaluateSmoke` behind the same reveal flag with a separate prefixed
verdict union; `smokeBlocks` as clamped closest-approach geometry over plain `{X,Y,Z}` tables.
**Verify:** `npm run lint` — 0 errors, 0 warnings, 0 parse errors.

### Step 1.4 — The exhaustive grid test
`tests/camouflage-rules.test.luau`. **385 assertions, all passing.** The count reconciles exactly
against the intended domain, which is how the grid is known to have actually run rather than
short-circuited:

| Block | Cells |
|---|---|
| `evaluate` grid — 2 × 2 × 5 × 5 × 2 | 200 |
| pre-reveal exact-verdict assertion (the `revealed = false` half) | 100 |
| `revealedAfter` + `chargeAfter` — 8 events × 2 starting values × 2 functions | 32 |
| one-way property — no event un-reveals | 8 |
| `evaluateSmoke` — 2 × 5 phases × 3 clock positions | 30 |
| smoke pre-reveal gate, named as itself | 5 |
| NaN elapsed fails closed | 1 |
| `smokeBlocks` geometry — through/tangent/clear/behind/past/degenerate/zero-radius | 7 |
| Config cross-check | 2 |
| **total** | **385** |

The oracle `isOk` is §4.3 written as one conjunction, not a copy of the module's branch order.
**Verify:** `lune run tests/camouflage-rules.test.luau` — `385/385 checks passed`.

### Step 1.5 — Fold into the unit run
**Verify:** `npm run test:unit` — `34 file(s) ok`. `feed-rules` still green, so its existing
assertion that a camouflaged monster may not feed did not move.

### Deviation from the plan — one, deliberate

The plan's Step 1.4 listing cross-checks `Config.Monster.SmokeCooldown`. **That value does not exist
until Step 2.1**, so asserting it in Phase 1 would red the suite on a number the next phase owns.
Phase 1 asserted `SmokeRadius` and `SmokeDuration` only (both already in `Config.luau:346-347`).

> **CORRECTED after the plan audit — the deviation note above was half wrong.** It claimed the
> `SmokeCooldown` invariant "lands in Step 2.6 where the plan already places it". The plan does not
> place it there: Step 2.6 pins three relationships (`Ambient.PerForm`, `CamouflageWitnessRadius`,
> `SmokeDuration`) and none of them mentions the cooldown. So the check the plan asked for in Step
> 1.4 **never landed anywhere** — `grep SmokeCooldown tests/` returned only the comment explaining
> its own absence.
>
> The deferral was correct; the claim about where it resumed was invented, and it read as confident
> enough that neither the gate nor I re-checked it. `tests/camouflage-rules.test.luau` now asserts
> all three smoke numbers (**386 assertions**, up from 385) and the comment there records why it was
> missing. Found by the `auditor` agent, not by any mechanical check — no verify line covers "a
> deviation note is telling the truth".

### Gate at end of phase
`npm run analyze` ok · `npm run lint` 0/0/0 · `npm run fmt:check` clean (after one `npm run fmt`
pass over the new test's call formatting) · `npm run test:unit` 34 files ok · `npm run verify:fast`
— analyze ok, remotes ok (27 declared, 27 wired), secrecy ok.

**Not yet done and not claimed:** nothing in this phase touches a DataModel, a remote or an
Instance, so there is nothing here a playtester could drive. Phase 1 is a pure module and its grid.

---

## Phase 2 — Tunables, types and the declared network surface

**Status:** complete. 6/6 steps.

### Step 2.1 — Camouflage and smoke tunables
`src/shared/Config.luau` — four new `Monster` numbers after the existing `SmokeDuration`/`SmokeRadius`
pair (which were already there and were not moved): `CamouflageCharges = 1`,
`CamouflageEnterTime = 0.8`, `CamouflageWitnessRadius = 12`, `SmokeCooldown = 45`,
`SmokeCueRadius = 40`. The **gate is deliberately not a Config value** — a `CamouflageRequiresReveal`
here would be one character from deleting the deduction layer, on a line a tuner would read as a knob.
**Verify:** `npm run check:config` — `config: ok (balance stays data-driven)`.

### Step 2.2 — `Config.Ambient`
New top-level block beside `Bodies`: `PerForm = 4`, wander/idle numbers, and a fallback scatter used
only when the map supplies no tagged spawn points.
**Verify:** `npm run fmt:check` — clean.

### Step 2.3 — Four remote declarations
`src/shared/Remotes.luau` — `CamouflageUpdate` and `SmokeBurst` down, `RequestCamouflage` and
`RequestSmoke` up. Both up-remotes are **argument-free**, which is the security design: the server
picks the form from the population it owns, so a client cannot probe the live ambient roster by asking
for each form in turn.
**Verify:** `npm run check:remotes` — `31 declared, 27 wired`, with the four correctly reported as
declared-but-not-yet-wired. Phase 5 wires them.

### Step 2.4 — Budgets, both halves
`Config.AntiCheat` gains `RequestCamouflage = {3, 0.2}` and `RequestSmoke = {2, 0.1}`;
`tests/anti-cheat-budgets.test.luau`'s hand copy of `EVENTS_UP` gains the same two names. Both edits
or neither — the suite asserts in both directions, and `Consume` fails closed.
**Verify:** `lune run tests/anti-cheat-budgets.test.luau` — `15 remotes budgeted, 67 assertions`.

### Step 2.5 — Payload types and the widened server record
`src/shared/Types.luau` — `CamouflageVerdict`, `CamouflageUpdatePayload` (verdict + optional form, no
charge, no reveal flag), `SmokeBurstPayload` (position/duration/radius, **no player field of any
kind**). `src/server/Services/MonsterService.luau` — six new fields on the server-only record, and the
constructor initialises `HasBeenRevealed = false`.

**The analyze gate caught the constructor**, which is the useful half of this step: adding the fields
to the type without initialising them failed at `MonsterService.luau:317` with the three missing names.
That is the fail-closed default becoming a typechecked requirement rather than a convention.
**Verify:** `npm run verify:fast` — analyze ok, remotes ok, secrecy ok.

### Step 2.6 — Three balance invariants
`tests/config.test.luau` — `Ambient.PerForm >= 2` (below it, the lone entity of a form IS the monster),
`CamouflageWitnessRadius > KillRange`, `SmokeDuration < SaltRevealDuration`.
**Verify:** `lune run tests/config.test.luau` — `122 balance invariants`, up from 119.

### Gate at end of phase
`fmt:check` clean · `test:unit` 34 files ok · `verify:fast` green.

**Not yet claimed:** the four remotes exist and nothing listens. That is the intermediate state
`SearchService.ItemFound` and `FeedCompleted` both shipped in, and `check:remotes` reports it
explicitly rather than silently.

---

## Phase 3 — The ambient population, and the slot that gets swapped

**Status:** code complete, 4/5 steps. **Step 3.5 is a human step and is NOT done** — see below.

### Step 3.1 — `src/shared/pure/AmbientRoster.luau`
`claim(roster, form) -> (roster', slotIndex?)`, `release(roster, slot)`, `visibleCount(roster, form)`.
Claim returns **nil rather than appending** when a form is exhausted — that refusal is the whole of
swap-not-spawn. Mutates a clone, never the argument.
**Verify:** `test -f src/shared/pure/AmbientRoster.luau` — passes.

### Step 3.2 — Head-count invariance test
`tests/ambient-roster.test.luau` — **78/78**. Asserts `visibleCount` is invariant across every claim
at every occupancy, that claiming one form does not touch the other three, that claiming past
exhaustion refuses, that a refused claim spawns nothing, and that release is idempotent and total over
nil and stale indices.
**Verify:** `lune run tests/ambient-roster.test.luau` — `78/78 checks passed`.

### Step 3.3 — `src/server/Services/AmbientService.luau`
Server-owned population: sixteen anchored part rigs, one Heartbeat wander loop for all of them, no
Humanoids and no pathfinding. `ClaimSlot` parks the real entity **into `ServerStorage`, not into a
hidden spot in `workspace`** — a claimed model left in the workspace tree still replicates and would
be a client-readable index of where the monster is. `ReleaseSlot` does not reposition, so the entity
returns where it vanished rather than teleporting home.
**Verify:** `npm run analyze` — ok.

**Four strict-Luau fights, and one of them was a lesson firing verbatim:**

1. `{ [number]: Model }` indexed and compared to `nil` — Roblox class types cannot, unlike table
   types. Declared the maps `{ [number]: Model? }`.
2. `for _, form in Enums.CamouflageForm` yields `unknown`; a frozen table's iteration loses the
   `:: Types.CamouflageForm` casts its values carry.
3. `local FORMS: { Types.CamouflageForm }` then yielded `string | string | string | string` — **this
   is `.claude/lessons/pure-module-unions-widen-in-lists.md` exactly.** A literal union survives a
   require as a scalar and does not survive it inside a list.
4. The lesson's own prescription (narrow with a function, not a cast) did not survive either — the
   nil-refinement does not carry across the nested loop body that needed it.

**What worked is a parameter.** `spawnForm(form: Types.CamouflageForm, placed)` called four times
with four literals; a literal checked against an annotated parameter is narrowing the analyzer
actually performs. The reasoning is written into the file above `FORM_LOOKS` so the next person does
not re-walk all four.

`check:config` flagged the 24 placeholder rig dimensions and colours. Waived same-line with reasons —
they are presentation that V15 replaces, and `SkyController`'s Color3 channel waivers are the
precedent. Same-line matters: a waiver on the preceding line does not count.

### Step 3.4 — Bootstrap registration
`src/server/init.server.luau` — `AmbientService` before `MonsterService`, which requires it. No
`PhaseChanged` subscription, deliberately: a population that appeared when a round started would be a
round-state readout in the geometry.
**Verify:** `npm run build` — `Built project to aswang.rbxl`.

### Step 3.5 — The map's spawn-point contract — **NOT DONE, needs a human**
The contract is written into `AmbientService`'s header in full (tag, count, placement, part
properties, publish). **The step itself is a person opening Studio**, tagging sixteen invisible
anchored parts `AmbientSpawn` across the bahay kubo, the chapel and the well area, and publishing.

This step has **no `**Verify:**` line by design** and `verify-plan` reports the phase `needs-human`.
Until it is done the code falls back to a ring of sixteen entities around the origin — which is
scaffolding that makes `npm run build` and a fresh Studio session work, **not a barrio**. The fallback
fires only on ZERO tagged parts, never on "fewer than we wanted", so a partial map stays visibly
wrong rather than being silently replaced.

### Gate at end of phase
`npm run verify` — **full gate green**: analyze, lint, format, all five checks, `test:unit` 35 files
ok, harness self-tests, 8 hooks alive.

---

## Phase 4 — Server-side camouflage, and the one line that opens the gate

**Status:** complete. 6/6 steps.

### Step 4.1 — Record fields
Landed early, in Step 2.5 — that step's title also said "widen the server-only monster record", so the
fields and their initialisers went in there. **One reconciliation:** I had held the claimed entity as
`CamouflageEntity: Model?`; the plan holds `AmbientSlot: number?`. The plan is right and it is now an
index — `AmbientService` owns the Instances and `AmbientRoster` deals in indices, so a Model handle
here would be a second way to disagree about which slot is free.
**Verify:** `npm run analyze` — ok.

### Step 4.2 — `HasBeenRevealed`, set in `ApplySaltHit` and nowhere else
One line, through `CamouflageRules.revealedAfter(…, "SALT_HIT")` rather than `= true`, so "nothing but
salt reveals" stays asserted over all eight events instead of becoming a property of this call site.
Placed after `applyExposed`: nothing above reads the field, so the order is not load-bearing, but it
means a salt hit that throws part-way leaves the monster **un**-revealed — the failure falls towards
the survivors throwing again, never towards a free camouflage.

**Corrected against the plan:** I first wrote `stateFor(player.UserId)`, which would re-insert a
departed player's record. Changed to read-not-construct, which is what `revert()` documents two
screens up.
**Verify:** `npm run check:secrecy` — ok.

### Step 4.3 — Charge restored from the `FeedCompleted` seam
The first and only subscriber to the BindableEvent V06 built and documented for V07. Nobody has to
remember to withhold the refresh on an interrupted feed: `completeFeed` is the only firer, and
`endFeed` — which all six interruption paths go through — does not fire it at all.
**Verify:** `npm run verify:fast` — green.

### Step 4.4 — `enterCamouflage` / `exitCamouflage`
Enter claims **then** spends **then** changes the look, so a failed claim costs nothing. The look goes
through the transform's existing `captureLook`/`OriginalParts`/`trackedEffect` machinery — a parallel
restore path here is C04's map-wide branding bug with a longer fuse. The capture is guarded on
`Applied`, because capturing twice would record the *monster's* colours as the originals.

`exitCamouflage` releases the slot **first**, before any look work can fail, and re-applies the monster
look only when still transformed. **Aligned to the plan:** I had an `else restoreLook` branch; removed,
because `revert` is the caller in exactly the case where `Transformed` is already false and two owners
would race the same restore.
**Verify:** `npm run lint` — 0 errors.

### Step 4.5 — `monsterStateOf` learns the fifth state
**Corrected against the plan twice.** I first put CAMOUFLAGED below FEEDING and on one flag. The plan
puts it **first** and requires **both** flags, and is right on both counts: checked after
`Transformed`, this would report TRANSFORMED for a monster wearing a pig, and `evaluate` would grant a
second hide because ALREADY_CAMOUFLAGED could never fire — leaking the first slot for the round.
**Verify:** `npm run test:unit` — 35 files ok, `feed-rules` still green over the now-producible value.

### Step 4.6 — All five exits closed
Salt (before `endFeed`/`revert`), round end (in the `onPhaseChanged` loop, before `table.clear` drops
the handle), player leaving (before the entry is nilled — the one exit the phase loop *cannot* cover),
death (in the `Humanoid.Died` connection), and `revert` itself (after `Transformed = false`, so it
hands the slot back and leaves the look alone).
**Verify:** `npm run verify` — full gate green.

---

## Phase 5 — The remote surface and the smoke field

**Status:** complete. 5/5 steps.

### Step 5.1 — `RequestCamouflage`
`Consume` first, inline at the connect site. A **non-Aswang receives nothing at all** — not even a
refusal — because any verdict on the wire for a player who is not the monster is a free role oracle.
The witness check runs last, after the rules module has said yes, so the only refusal that walks
`Players` runs once per otherwise-legal request rather than on every spammed one.
**Verify:** `npm run check:ratelimit` — every OnServerEvent consults AntiCheat.

### Step 5.2 — `RequestSmoke` and the live burst field
A burst is a centre, a radius and a deadline in a server table. Recorded **before** the client is told,
so there is no frame in which a client knows about a cloud the server does not yet enforce. Expired
bursts are swept lazily inside the reader, back-to-front.
**Verify:** `npm run check:remotes` — **31 declared, 31 wired**.

### Step 5.3 — Smoke blocks a kill
`smokeBlocksSegment` asked *before* the raycast — cheap arithmetic over at most one burst, and an
answer that does not depend on map geometry. The monster is blinded by its own cloud, which is the
design: smoke covers a disengage, and a disengage is not a kill.
**Verify:** `npm run analyze` — ok.

### Step 5.4 — Smoke blocks a throw
`ItemService` consults `MonsterService.SmokeBlocks` and **collapses into the existing `MISS`**. A
`MISS_SMOKE` value would be produced only when the Aswang has planted a cloud, delivered to a survivor,
naming a direction — a role oracle in the one place where a refusal shape already is one.
**Verify:** `npm run check:secrecy` — ok.

### Step 5.5 — `SmokeBurst` to the players in radius
`FireClient` in a server-side distance loop, never `FireAllClients`. The requester is in the audience
by the same distance test as everyone else, not by a special case — writing it as one would be the
first line of a version that treats the Aswang differently.
**Verify:** `npm run build` — built.

### The type-system fight, recorded because it cost the most time in this chunk

`.claude/lessons/pure-module-unions-widen-in-lists.md` fired **four separate times**, each in a shape
the lesson does not name:

| Where | What widened | What fixed it |
|---|---|---|
| `AmbientService.Start` | `{ Types.CamouflageForm }` list element | a literal passed to an annotated **parameter** (`spawnForm`) |
| `PickAvailableForm` | `Slot.Form` out of `Roster` (a list) | re-narrowing function at the boundary |
| `validateAndCamouflage` | `form` after `verdict ~= "OK" or form == nil` | **splitting the compound `or` refinement** into two `if`s |
| same, and `verdict` | inferred return of a cross-module call | annotating the local at the assignment |

The lesson's own prescription — narrow with a function — was necessary but not sufficient; a
nil-refinement does not survive into a nested loop body or past a compound `or`. That is new
information and worth a lessons-review pass.

### Gate at end of phase
`npm run verify` — analyze, lint (after dropping an unused `character` param from
`applyCamouflageLook` rather than silencing it), format, all five checks, `test:unit` 35 files ok.

---

## Phase 6 — What the two abilities look like

**Status:** code complete, 5/6 steps. **Step 6.5 is a human step and is NOT done** — see below.

### Step 6.1 — `src/client/Controllers/SmokeController.luau`
One controller for both down-remotes. Owns no truth: the LOS break is resolved server-side, so
deleting the emitter or dropping to minimum graphics changes nothing about the rules. **No distance
filter in this file** — a client-side filter would mean every client received every burst, which is
the live monster-position feed `Remotes.luau` refuses.
**Verify:** `test -f src/client/Controllers/SmokeController.luau` — passes.

### Step 6.2 — Client bootstrap
After `OnboardingController` (a real one-way require, for `ShowLine`), before `InputController`
(`SmokeBurst` can arrive the instant any Aswang presses G, before this player has pressed anything).
**Verify:** `npm run analyze` — ok.

### Step 6.3 — `C` and `G` bound
Both unclaimed; T/F/Q/E are the four in use. **Bound unconditionally for every player** — a button
only the Aswang can see is the reveal, on the monster's own screen where a stream makes it permanent.
The role check is local and silent, mirroring `performTransform`, and the server refuses a survivor
independently. **No local cooldown**, deliberately: a client-side timer would mask a server refusal
and the client's copy is the one the player would believe. Registered with `UIController.BindActions`
so the touch pad runs these verbs rather than its own copies.
**Verify:** `npm run check:remotes` — 31 declared, 31 wired.

### Step 6.4 — The verdict copy
`CAMO_NOT_REVEALED` says what *unlocks* the ability rather than what refused it — §4.3's gate is
invisible from inside a round, so "camouflage is locked" would read as a bug. The three state verdicts
share one line, because each is a thing the player can see by looking at their own screen.
`CAMO_NO_SLOT` names a fact about the world, which is safe twice: fired to the requester alone about
its own refused action, and describing a population standing where anyone can count it.
**Verify:** `npm run fmt:check` — clean.

### Step 6.5 — The particle budget — **NOT DONE, needs a human**
The code spends what the plan specified: one emitter, `Rate = 0` with a burst `:Emit()`,
`LightEmission = 0`, `Debris:AddItem` so nothing accumulates, and `Duration`/`Radius` taken from the
**payload** rather than Config so the client cannot draw a stale cloud. Three new Config values carry
the look (`SmokeParticleCount = 60`, `SmokeTransparency`, `SmokeDriftSpeed`).

**The step itself is a person standing in the cloud on a phone.** It has no `**Verify:**` line by
design and `verify-plan` reports the phase `needs-human`. Whether a `ParticleEmitter` visually
occludes anything is explicitly **not** depended on — the server decided line of sight before any
particle existed, so a thin-looking cloud is a texture problem with no gameplay consequence.

### Step 6.6 — The whole gate
**Verify:** `npm run verify` — analyze ok · lint 0/0/0 · fmt clean · remotes 31/31 · secrecy ok ·
config ok · scope ok · ratelimit ok · debug ok · testcount ok · `test:unit` 35 files ok · harness ok ·
8 hooks alive.

---

## Where V07 stands

**Six phases implemented; two steps deliberately left for a human** (3.5 the map markers, 6.5 the
particle budget on a phone). Both are `needs-human` by the plan's design, not by omission.

**Nothing here has been run in Studio.** Every claim above is a static check or a Lune suite. The
reviewers and the playtester are what turn that into evidence.

---

## CRITICAL FIX — the swap inverted

**Trigger:** the Critical confirmed at runtime (see `verification.md`). `ClaimSlot` reparented the
claimed entity into `ServerStorage`, which removed it from every client and leaked the monster's exact
position through `workspace.AmbientLife.ChildRemoved`.

### The shape change, not a patch

The old design hid the **entity** and re-skinned the **player**. The new one is the inverse: the entity
stays exactly where it is and the **player's character is hidden**, with the entity puppeted to follow
it. The monster genuinely takes the entity's place — which is what §4.3 describes — and the barrio's
visible population is byte-identical whether or not anyone is camouflaged.

### What changed

| File | Change |
|---|---|
| `AmbientService.luau` | **The parked folder is deleted entirely.** `ClaimSlot` marks the slot and returns; `ReleaseSlot` unmarks. New `PuppetSlot(index, cframe)` drives a claimed entity. `SlotCFrame` removed (dead — the monster no longer moves to the entity). |
| `MonsterService.luau` | `applyCamouflageLook` replaced by `hideCharacter`/`showCharacter` over a **separate** `HiddenPart` capture — the transform's `captureLook` is not shared. New Heartbeat tick puppets the entity. `enterCamouflage` no longer pivots the character. |
| `Config.luau` | `CamouflageTintRgb`, `CamouflageAnimalScale`, `CamouflageVillagerScale` **deleted** — the inversion made them dead, which removed a second finding rather than patching it. |
| `tests/ambient-roster.test.luau` | **104 assertions**, up from 78. New block asserts the roster's LENGTH never changes across any claim or release. |

### The guarantee is structural, not a check

`grep -n "\.Parent = " src/server/Services/AmbientService.luau` returns three hits, all at spawn time:
`body.Parent = model`, the folder into `workspace`, and `model.Parent = entities` inside `Start`.
**There is no holding folder any more, so there is nowhere to reparent TO** — a future regression would
have to create one first, which shows up in a diff.

### Findings this closed as a side effect

- **High — camouflaged avatar readable by Config scan.** Gone: there is no tint and no scale to read,
  because the character is not re-skinned at all. The Config values that leaked are deleted.
- **High — username over the disguise, accessories unscaled.** `hideCharacter` walks **descendants**
  (so accessory handles are hidden) and sets `Humanoid.DisplayDistanceType = None`, capturing and
  restoring the previous value rather than defaulting it.
- **Unverified Roblox behaviour — `PivotTo` vs client network ownership.** No longer depended on: the
  character never moves, the entity comes to it.

### Verified in the live session

```
SERVER AmbientLife=16 | ServerStorage.AmbientParked exists=false
CLIENT total=16 | CAT=4 DOG=4 PIG=4 VILLAGER=4
```

### Gate
`npm run verify` — analyze ok · lint 0/0/0 · fmt clean · remotes 31/31 · secrecy · config · scope ·
ratelimit · debug ok · testcount · **35 suites** · harness · 8 hooks alive. All six debug values
reverted.

### Still open — not fixed by this change

- **Medium — deterministic form and slot.** Every hide is still the first free slot, so the same form
  at the same spawn point every round.
- **`CamouflageEnterTime = 0.8` is still not read.** The windup the plan specified does not exist; the
  hide is instantaneous. Config value kept deliberately so the gap stays visible.
- **`validateAndCamouflage` logs nothing** under `VerboseLogging`, unlike the transform path.
- **Two-client behaviour** — the reveal, a successful hide end-to-end, and whether the puppeted entity
  reads convincingly to another player.
