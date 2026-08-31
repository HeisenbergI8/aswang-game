# Implementation log — feature-barrio-population-plan

## Phase 1: Six forms, and one literal union declared in five places

**Status:** complete. `tests/camouflage-forms.test.luau` — 94 assertions, green.

### What landed

| Step | File | What |
| --- | --- | --- |
| 1.1 | `tests/camouflage-forms.test.luau` | New suite over all 7 declaration sites. Written first, went RED on 22 assertions |
| 1.2 | `src/shared/Types.luau:71`, `src/shared/Enums.luau:81-91` | Union widened to six; `Goat`/`Chicken` added with their `:: Types.CamouflageForm` casts |
| 1.3 | `src/shared/pure/AmbientRoster.luau:29`, `src/shared/pure/CamouflageRules.luau:43` | The two re-declared copies |
| 1.4 | `src/shared/Config.luau:697`, `tests/config.test.luau` | `PerForm` 4 → 3; new `<= 4` ceiling assertion |
| 1.5 | `src/server/Services/AmbientService.luau` | `FORM_LOOKS` +2 rows, `formFromId` +2 branches, `Start` +2 calls, fallback ring `* 4` → `* 6` |

### The red that proved the suite discriminates

Step 1.1's suite failed **22 assertions across all six sites** before any source was touched, then went
green at 1.5 with every site widened. That is the phase's evidence that it can see anything at all.

The analyzer confirmed the lesson the suite exists for, live: widening `Types.luau` alone produced four
`TypeError`s **in `AmbientService.luau`** — a file the edit never touched. `.claude/lessons/
pure-module-unions-widen-in-lists.md`, exactly as written.

### Deviation from the plan — the `formFromId` scan could never pass

The plan's suite scanned that function with two `gmatch` patterns:

```
`if id == "([A-Z_]+)" then`      -- and
`elseif id == "([A-Z_]+)" then`
```

`if id == "` is a **substring** of `elseif id == "`, so every `elseif` branch matched both patterns.
Four forms scanned as **seven** members; six would scan as eleven. `#found == #FORMS` was unsatisfiable
regardless of how the source was written.

Fixed by anchoring the opening pattern to `\n\tif id == "`, which keeps the two disjoint. Deduping into
a set was the other option and was rejected: it would make the count assertion pass unconditionally,
destroying its ability to catch a form listed twice.

### Verification

- `npm run analyze` — ok
- `lune run tests/camouflage-forms.test.luau` — PASS, 94 assertions over 6 forms in 7 sites
- `lune run tests/config.test.luau` — PASS, 123 balance invariants
- `lune run tests/ambient-roster.test.luau` — 118/118, **unedited**
- `lune run tests/camouflage-rules.test.luau` — 386/386, **unedited**
- `npm run verify:fast` — analyze ok, remotes 32/32, secrecy ok
- `npm run lint` / `fmt` / `check:config` / `check:scope` — all ok

The last two matter as a check on Step 1.3: the plan says neither pure module's *logic* may change, and
neither suite needed an edit to stay green. No form got enumerated where it should not have been.

`check:scope` passing also settles the `pets?` question the plan raised — no waiver was needed.

### Known red, carried deliberately into Phase 3

- `tests/barrio-ambient.test.luau` — "the builder sites exactly 12 ambient spawns — 16 parsed"
- `tests/barrio-receipt.test.luau` — "builder asserts 16, Config implies 12"

The plan predicted the first. The second is **not in the plan** and is the same defect: both multiply
`PerForm` by a hard-coded 4. This is the map contract correctly noticing the population changed from
16 to 18, and Phase 3 is where the builder answers. Do not weaken either suite to clear them.

---

## Phase 2: The resting height, as a pure function

**Status:** complete, **and verified in the running game**. `tests/ambient-rig.test.luau` — 190
assertions, green. Artifact: `artifacts/rig-height.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 2.1 | `tests/ambient-rig.test.luau` | New suite. Went RED on a missing module, as designed |
| 2.2 | `src/shared/pure/AmbientRig.luau` | `restingY` / `puppetY`, the second written as the first |
| 2.3 | `AmbientService.luau` | `groundYUnder` raycast; free rigs seated on measured ground |
| 2.3 | `Config.luau` | `GroundProbeUp` / `GroundProbeDown` / `SpawnPadHalfHeight` |
| 2.4 | `AmbientService.luau` | `PuppetSlot` takes a `footOffset`; height from the rig, rotation from the monster |
| 2.5 | `MonsterService.luau`, `Config.luau` | `footOffsetOf`; `Monster.DefaultFootOffset` |
| 2.6 | `artifacts/rig-height.md` | Three runtime measurements |

### Deviation — the plan named two sites that decide a rig's Y. There are three.

The plan fixed `buildEntity` and `PuppetSlot`. **Runtime showed the fix had no effect**: all 18 rigs
still sat with their centre at exactly 0.4 — the spawn pad's height — regardless of form height or of
the ground beneath them, worst error **−2.200 studs**.

`wanderTick` retargets from `home * CFrame.new(dx, 0, dz)` where `home` is the pad's CFrame, so every
target inherited y = 0.4 and each rig walked back to pad height **within one Heartbeat of spawning**.
It is the site that outlives the other two, and it is the one the plan did not name.

Fixed by seating the retarget on its own ground. Cost is one raycast per retarget — about two a second
across the whole population, well inside the "not eighteen a frame" rule `groundYUnder`'s own header
sets. Also flattened the facing vector: now that targets carry real ground heights, `offset` has a Y
component wherever the barrio is not flat, and feeding that to `CFrame.lookAt` pitches the model — a
cat crossing a kerb would tilt nose-down, which is precisely the "that one is behaving oddly" tell this
phase spends its whole budget avoiding.

**This is why Step 2.6 exists.** Every static check was green over a fix that did nothing.

### The Follow Up Step 2.5 opened, closed empirically

`HipHeight`'s reference point was unverified. Measured on a live R15 rig: `HipHeight + root.Size.Y/2`
= 2.9980 against a true root-to-feet distance of 2.9929 — **accurate to 0.005 studs**. `HipHeight`
alone would have been wrong by 0.99. The underside reading is correct; no sign correction needed.

### Result

Free rigs: worst vertical error **2.200 → 0.003 studs**.
Free vs puppeted: **+2.6 studs → −0.0051**, uniform across all six forms, and that residual is
entirely the HipHeight measurement error above.

### Honest limit

`ClaimSlot` returned `nil` through `execute_luau` — `require` from the MCP console returns a **fresh
module with an empty roster**, not the live service. So the puppet measurement evaluates
`AmbientRig.puppetY` against real geometry rather than driving `PuppetSlot` end to end. The wiring is
covered by `analyze` (the third argument is required, so a stale call site errors rather than passing
`nil`); an end-to-end camouflage needs a real reveal and a second player. Carried to Phase 6.

### Verification

- `lune run tests/ambient-rig.test.luau` — PASS, 190 assertions over 6 forms x 5 grounds
- `npm run analyze` / `check:config` / `check:secrecy` / `lint` / `fmt` — all ok
- Runtime: three probes in Play mode, recorded in `artifacts/rig-height.md`

---

## Phase 3: Territories — and the constraint on the Aswang, made mutual

**Status:** complete, and observed in the running game. `tests/ambient-territory.test.luau` — 17
assertions, green. Artifact: `artifacts/territories.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 3.1 | `tests/ambient-territory.test.luau` | Coverage, spread, the ClaimRadius < WanderRadius bound, four lookup cases |
| 3.2 | `src/shared/pure/AmbientTerritory.luau`, `Config.luau` | `pointsFor` / `nearestFreeIndex`; `Ambient.ClaimRadius = 18` |
| 3.3 | `tools/greybox/barrio.luau` | 18 points, each naming its form; the build-failing assert 16 → 18 |
| 3.4 | `tests/barrio-ambient.test.luau` | Six forms, `Form`-keyed parse, the per-form count, the attribute check |
| 3.5 | `AmbientService.luau`, `MonsterService.luau` | `spawnPointsByForm`, bounded `ClaimSlot`, `PickAvailableFormNear` |
| 3.6 | `AmbientService.luau` | The map contract header rewritten |

### Deviations from the plan

**1. The form attribute goes through `anchor()`'s sixth parameter, not a separate `SetAttribute`.**
The plan wrote `pad:SetAttribute("Form", at.Form)`; `anchor()` already takes an attributes table and
every other tagged pad in the builder uses it. The test assertion was written to match what shipped.

**2. `tests/barrio-receipt.test.luau` had the same `× 4` defect and the plan never named it.** It went
red alongside `barrio-ambient` at Step 1.4. Rather than retyping `4` as `6` — the same hand-written
count, one version later — it now **counts the members of `Types.CamouflageForm`**, which
`tests/camouflage-forms.test.luau` pins against every other declaration. The class is closed, not the
instance.

**3. `FORM_IDS` is a new, seventh declaration site**, added by `spawnPointsByForm` and the fallback
ring. It is `{ string }` rather than `{ Types.CamouflageForm }` deliberately — nothing is returned
from it, so there is no narrowing to lose. `camouflage-forms` now covers it, and the ring's multiplier
assertion changed from "the literal is 6" to "there is no literal": `PerForm * #FORM_IDS` cannot go
stale.

**4. `spawnForm` lost its `placed` accumulator, and the territory list is built inside the spawn
loop.** `AmbientTerritory.nearestFreeIndex` returns a POINT index that `ClaimSlot` uses as a SLOT
index, so the two lists must agree — and they **cannot** be built by walking
`CollectionService:GetTagged`, which gives no order guarantee. Building both in one loop makes the
identity structural rather than a convention.

**5. `enterCamouflage` takes the position as a parameter rather than calling `rootOf`.** `rootOf` is
declared ~370 lines below it; calling it there compiles and dies at runtime with "attempt to call a
nil value" — the forward-reference trap this file has hit three times. The caller already resolved the
root to pick the form, so handing it down costs nothing.

**6. The windup re-reads the monster's position.** `CamouflageEnterTime` elapses between the pick and
the claim, so reusing the earlier position would let a monster start the windup on a pig pen and
finish it on the basketball court — the constraint defeated by a timer. Both `validateAndCamouflage`
and its recheck now resolve their own root.

### Verification

- `lune run tests/ambient-territory.test.luau` — PASS, 17 assertions
- `lune run tests/barrio-ambient.test.luau` — PASS, 33 assertions over 18 points
- `lune run tests/barrio-receipt.test.luau` — PASS, 22 assertions
- `lune run tests/camouflage-forms.test.luau` — PASS, 108 assertions over 8 sites
- `npm run verify` — **green, 52/52 test files**, all five checks ok
- Runtime: 18 rigs, 3 per form, every one inside its own territory, worst leash 20.7 / 24

### The map was patched rather than rebuilt — and this is owed back

`tools/greybox/barrio.luau` is normally run by fetching its own source over HTTP inside
`execute_luau` (its own header says so at `:289`). **That call was refused by the permission
classifier** — fetch-then-`loadstring` is remote-code-execution shaped, and I did not route around it.

So the Studio map's `AmbientSpawn` pads were replaced by a targeted script that replicates `anchor()`
exactly: SCALE 1.55, `ANCHOR_C`, y = 0.4, 6×0.8×6, SmoothPlastic, `CanCollide = false`, attribute,
then tag. It removed 16 and created 18, all carrying `Form`.

**Every other builder change since — and everything Phases 7 and 8 add — still needs a full builder
run in Studio before publishing.** The file on disk remains the source of truth; the place file is
currently behind it.

---

## Phase 4: One motion driver, because two drivers is two behaviours

**Status:** complete, and two real defects were caught — one by the suite, one only by runtime.
`tests/ambient-motion.test.luau` — 487 assertions, green. Artifact: `artifacts/motion-parity.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 4.1 | `tests/ambient-motion.test.luau` | Distinct phases, bounded bob, continuity in speed, measured speed |
| 4.2 | `src/shared/pure/AmbientMotion.luau` | `phaseFor` / `speedFrom` / `amplitudeFor` / `bobOffset` / `swayDegrees` |
| 4.3 | `src/shared/Config.luau` | Six motion tunables under `Ambient` |
| 4.4 | `AmbientService.luau` | `stepEntity`; `PuppetSlot` records a target instead of moving; the tick drives claimed slots |
| 4.5 | `artifacts/motion-parity.md` | Three runtime probes |

### Deviation — `amplitudeFor`'s knee was dimensionally wrong

The plan's `local half = 1 / math.max(tuning.BobHz, 1e-6)` uses an **inverse frequency as a speed**.
At `BobHz = 1.4` that puts the half-amplitude point at 0.71 studs/s, below walking pace, so a rig
ambling at `WanderSpeed = 4` already sat at 85% amplitude — and a sprinting monster's disguise looked
barely different from a strolling pig. **That is §4.5's one licensed tell, flattened**, and `analyze`
would never have said a word.

The suite's continuity assertion caught it (`0.25 -> 0.342` across a 0.1 speed step). Fixed by adding
`MotionKneeStuds` to `Tuning` and to `Config.Ambient`, set to 4 to track `WanderSpeed`.

The same change gave `IdleHz` a job — the plan declared it in `Tuning` and never read it. The bob rate
now blends `IdleHz → BobHz` along the same saturation the amplitude uses, so a resting animal breathes
slowly and shallowly and a moving one steps quickly and deeply: one curve, no second threshold to fall
out of step with the first. The plan's `speed / (speed + 8)` magic 8 is gone with it.

### Deviation — the plan's `stepEntity` accumulated its own sway

**This one only runtime could show.** The plan's stationary branch is:

```
else CFrame.new(position) * (current - current.Position)
```

`current` is `model:GetPivot()`, which **already carries the previous frame's sway**. Multiplying a new
roll onto it compounds every Heartbeat. Measured: 5.98 degrees of tilt against a 4-degree cap, and a
roll span of 359.9 degrees over four seconds — a still animal slowly rolling onto its side.

`tests/ambient-motion.test.luau` was green throughout, correctly: the module is pure and its output
bounded. The bug was in how the caller composed that output over time, which no pure test can see.

Fixed with a `facings` store — rotation only, written only when the rig actually turns — and each frame
composes `position → base → sway` from scratch. Tilt is now 2.50 degrees, uniform across all 18.

### Deviation — the wander branch's early exit had to go

The old loop `continue`d when a rig was within one step of its target. Harmless when arriving meant
stopping; **a leak now that it means "stop breathing"**. A rig parked at its target through three idle
seconds would freeze while its neighbours breathed, and a camouflaged monster standing still is exactly
the case that must not stand out. `stepEntity` handles a zero-distance step.

### The plan's own issue list, all addressed

- **Stale `targets[index]` on release** — cleared in `ReleaseSlot`. Left alone, a released rig would
  set off walking toward the monster's last position: a pointer at the Aswang, drawn by the animal it
  just stopped being.
- **`elapsed` cleared in `Init`** — plus `facings`, which the plan did not have.
- **`Config.Ambient` satisfies `Tuning` structurally** — now six fields, not five.

### Verification

- `lune run tests/ambient-motion.test.luau` — PASS, 487 assertions
- `npm run analyze` / `lint` / `fmt` / `check:config` / `check:secrecy` — all ok
- `npm run test:unit` — 53/53 files
- Runtime: 0 of 18 rigs frozen; still rigs span 0.16–0.25 studs against a 0.24 maximum; tilt 2.50 deg
  uniform against a 4 deg cap

### Carried forward — vertical drift while travelling

Rigs interpolate Y linearly between two ground-correct endpoints, so crossing raised ground they drift
to +1.58 / −0.50 studs before arriving. **Not a leak** — free and claimed run the identical
interpolation in the identical function — but it is visible. Not fixed here because the obvious remedy,
re-seating Y from a per-frame ground probe, would raycast from a claimed rig straight through the
monster's own character, and `stepEntity` has no handle on which character to exclude. That is a change
to the puppet contract, not to the motion.

---

## Phase 5: Two new meshes, and the rig budget brought inside the ceiling

**Status:** complete. Six meshes generated and loading; `tests/barrio-assets.test.luau` counts them for
the first time. Artifacts: `artifacts/rig-meshes.md`, `artifacts/six-forms.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 5.1 | `artifacts/rig-meshes.md` | Six meshes generated, all first try. `generate_material` not needed |
| 5.2 | `tools/greybox/barrio.luau`, `tests/barrio-assets.test.luau` | `ASSETS.RigMeshes`; separate rig ceilings; the cross-file id match |
| 5.3 | `AmbientService.luau` | Twelve ids into `FORM_LOOKS`, each waived |
| 5.4 | `artifacts/six-forms.md` | Silhouette captures at 14 and 40 studs |

### Deviation — the plan said keep Phase 1's `Size` values. That would have deformed every rig.

`buildEntity` assigns `body.Size = look.Size` and a MeshPart **stretches** to fill it. Phase 1's sizes
were the boxes the meshes were *requested* in; the generator fits inside a request while preserving
aspect. The cat came back **0.46 wide against a requested 1.4** — applying the plan's value would have
made it three times too broad and twice too long, and nothing in `npm run verify` inspects a shape.

Each `Size` is now the mesh's own bounding box. The only freedom taken is a **uniform** scale where the
height was wrong: GOAT 1.71 → 2.20 (it sat below the dog's 1.90, and DOG/GOAT is the pair the plan
itself flagged as most confusable) and VILLAGER 3.64 → 5.00 (child-height beside a 5-stud player). The
other four already matched.

This also matters beyond looks: `Size.Y` is what `AmbientRig.restingY` reads, so these are the numbers
that put each form's feet on the ground.

### The finding the phase was really for

**The rigs were spent and unbudgeted.** Four generated meshes at sixteen instances existed only as
asset ids inside `FORM_LOOKS` — a file no check reads — so roughly half of what a phone actually drew
sat outside a budget §5 calls non-negotiable. `barrio-assets` summed `ASSETS.Meshes` and had no idea
they existed.

Now: props 21,000 requested over 8 rows; rigs 7,800 requested over 6 rows and **23,400 drawn** across
18 instances. Two ceilings, not one, because a prop in fog at 200 studs and a rig being stared at from
five are not interchangeable triangles.

The suite also cross-checks every registered id against `AmbientService`'s source, because the registry
is the *record* and `FORM_LOOKS` is what *loads* — two copies of an id is one too many, and the failure
is silent: the budget would certify a mesh the game never loads.

### Verification

- `lune run tests/barrio-assets.test.luau` — PASS, 117 assertions over 8 props and 6 rigs
- `lune run tests/camouflage-forms.test.luau` — PASS, 108 assertions
- `npm run analyze` / `check:config` — ok (twelve new literals, each with a `-- config-ok:` reason)
- Runtime: **0 of 18 rigs fell back to a box**, which is what proves the ids are loadable rather than
  merely well-formed
- `ScreenCapture_5`: all six silhouettes distinguishable at 14 studs; CAT/CHICKEN and DOG/GOAT both
  separate cleanly

### Noted, not fixed

At **40 studs the animals are near-indistinguishable** from one another in the shipped fog — small dark
shapes. Arguably correct for a horror game (§4.5 asks a survivor to approach and study the population,
not solve it from across the plaza), and a V16 balance question rather than a defect. Recorded so it is
a decision rather than an oversight.

---

## Phase 6: Humanoid villagers — the phase took its documented exit

**Status:** complete, **by taking Step 6.6**. VILLAGER keeps the Phase 5 mesh. No Humanoid branch, no
`strideRate`. References: `references/humanoid-parity.md`, `artifacts/villager-parity.md`.

The plan wrote this outcome in as "a documented outcome of this phase rather than a failure of it", and
gated it on a parity table filled in **before** any rig was built. That is what happened, except that
the table was filled in from measurement rather than from argument.

### The technical gate passed — none of the plan's three exit conditions fired

Measured on a real `CreateHumanoidModelFromDescription` R15 rig, not inferred:

- Default catalogue walk `rbxassetid://507777826` **loads and plays** on a non-player Animator
- It **drives the joints**: `LeftFoot` moved 2.5756 studs relative to the root over 0.35s
- `AnimationTrack.Speed` **scales it**, so Step 6.2's displacement-driven stride would have worked
- `PivotTo` **does not interrupt** the track, and `MoveDirection` is `0,0,0` as predicted
- `EvaluateStateMachine = false` sticks

Two traps found that would each have shipped a frozen villager: **anchoring every part freezes the
animation** (a joint cannot move an anchored child — only the root may be anchored), and the rig has
**no joints at all until `Humanoid:BuildRigFromAttachments()`** is called.

### The gate that failed is one the plan did not write down

**A default `HumanoidDescription` is a blank, untextured Roblox avatar.** `ScreenCapture_6` puts the
probe rig beside a real player: a generic dark blocky figure, no clothing, no salakot, none of the
research Phase 5 encoded. The user asked for villagers who look like rural Filipinos; the Phase 5 mesh
already is one and this is visibly worse.

### And the instance cost was under-estimated by six times

| | Plan | Measured |
| --- | --- | --- |
| Per villager rig | ~45 instances | **274** |
| Three villagers | ~135 | **822** |

Against a ~1,125-instance barrio that is a **73% increase** — for a worse-looking villager.

### Why the exit is right rather than merely cheaper

The plan's principle, read in the direction the evidence actually points:

> "a mesh villager that is *indistinguishable* is worth more than a Humanoid villager that is *better
> and tellable*"

The Humanoid would have been worse on **art as well**, at six times the estimated cost, with the
mechanic no better off — the mesh villager already gets its life from Phase 4's `stepEntity`, which
every rig shares, so there is **no parity surface to defend at all**. The whole class of Humanoid leaks
the phase existed to audit simply does not exist now.

`AmbientService`'s header paragraph ("NO HUMANOID, NO PATHFINDING, NO PHYSICS") therefore stands as
written and needed no rewrite.

### Verification

- `npm run verify` — green, 53/53 test files, all checks ok (nothing in `src/` changed this phase)
- The probe rig and its folder were removed from the place; nothing was left behind

### Follow Up opened, for the user to decide

**Three identical mesh villagers** is the user's "doing something" request left unanswered. The fix is
pose variety — standing, seated with a bottle at the store bench, leaning on a porch rail — as separate
generated meshes. It does **not** fit today's budget: `RigMeshes` sits at 7,800 of a 9,000 ceiling and
two more villager poses at 1,800 each would be 11,400. That needs a re-argued ceiling, which is a
decision rather than an oversight.

---

## Phase 7: Seven interiors, and cladding that cannot move the navmesh

**Status:** complete in the builder; **not yet applied to the place file** — see the handoff note.
`tests/barrio-interiors.test.luau` — 49 assertions, green. Artifacts:
`references/sightline-compensation.md`, `artifacts/crossing-after-interiors.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 7.1 | `tools/greybox/barrio.luau` | `Kubo_E` and `Kubo_W` opened, one inward door each. All seven enterable |
| 7.2 | `references/sightline-compensation.md` | The compensation question, answered from the geometry |
| 7.3 | `tools/greybox/barrio.luau` | Cladding: re-generated shell with a doorway, placed on all seven, yawed to the door |
| 7.4 | `tests/barrio-interiors.test.luau` | Written first, red on a missing `KUBO_INTERIORS` |
| 7.5 | `tools/greybox/barrio.luau` | The `interior()` kit — banggera, altar, tampipi, banga, papag, banig, kalan, tabo, tukod |
| 7.6 | `artifacts/crossing-after-interiors.md` | `measure.luau`, ten lines, 34.8s |

### Step 7.2's answer: no compensation is needed, and here is why

`building()` cuts a door as a **gap between two wall segments in one face**
(`barrio.luau:388-391`). The other three faces stay solid and the roof is untouched, so each house is
still a closed volume with one 10-stud gap. **Occlusion comes from the mass, and the mass does not
move.** What changes is that a player can stand inside — a gameplay change, not a sightline one.

The invariant that argument rests on is "no kubo has two opposed doors", and it is **pinned by the
suite** rather than left to a reader, so nobody can invalidate the reasoning by adding a convenient
second door.

### Step 7.3: the brief's two options were both wrong, and the mesh had to be re-generated

The brief offered *retire the shell* or *split it into shell-plus-interior*. Both assume the mesh must
do the collision. It must not — `mesh()` sets `CanCollide = false`, and `PathfindingService` builds its
navmesh from collision geometry, so a non-collidable prop **cannot** move a route. The greybox keeps
the collision and the doorway; the mesh is what you see.

**But the existing shell could not be used as cladding**, and this is the deviation. It was sized
26 × 16 × 22 — *smaller* than the 37 × 12 × 31 greybox — so it sat **inside** the two sealed houses as
an ornament. Stretched over an enterable house it would have painted a solid sawali wall across the
doorway, and the player would walk through what looks like a wall. Worse than the box it replaced.

So the shell was re-generated **with an open doorway** (`128724254335456`), and the placement yaws it so
the mesh opening lands on the same face as the greybox gap. The **size swaps with the yaw** — `Size` is
local, so a 90-degree turn exchanges which local axis spans world X, and an east- or west-doored house
needs its width and depth written the other way round or its eaves end up inside its own walls.

Verified visually before being written into the builder: prototyped on `Kubo_NW` alone, captured under
raised lighting (`ScreenCapture_9`), doorway confirmed centred on the local +Z face.

`Placed` went **2 → 7 and `Tris` did not move**, because `Tris` is per mesh and not per instance.

### The chapel stays at `Placed = 0`, for a sharper reason than before

The plan expected cladding to make it placeable. It does not: **the chapel has two doors, on S and E**,
and one mesh cannot present an opening on two faces. Whichever it missed would be a doorway the player
walks through what looks like a solid whitewashed wall. The registry comment now says that instead of
the old "a solid shell would bury the containers", which cladding had genuinely answered.

### Two bugs the builder would have hit at run time, caught by probing rather than by reading

`tools/greybox/` is outside `src/`, so `analyze`, `lint` and `fmt` never read it. Both of these were
found by probing Studio directly:

1. **`Enum.Material.Porcelain` does not exist.** It is a plausible name and it is not in the enum;
   indexing it throws. Confirmed absent, replaced with `CeramicTiles`.
2. **A Roblox cylinder's axis is X**, not Y and not Z. The rolled `banig` was sized `(0.9, 0.9, 3.6)`,
   which is a 3.6-wide disc rather than a 3.6-long roll. Same fault on the `kalan`. **No test in this
   repo looks at a shape.**

### Verification

- `lune run tests/barrio-interiors.test.luau` — PASS, 49 assertions over 7 kubo
- `lune run tests/barrio-contract.test.luau` — PASS, 18 assertions
- `lune run tests/barrio-assets.test.luau` — PASS, 117 assertions
- `npm run verify` — green, 54/54 test files
- `measure.luau`, all ten lines: **34.8s, 39/39 reachable, 7/7 loops, 2 lights worst**

**39 is the number that matters** — 15 containers + 6 salt + **18 ambient**. The plan's own issue list
warns that a dead tag returns an empty list and prints a healthy crossing over a fraction of the map;
39 is what proves that did not happen, and it confirms Phase 3's pads from the other side.

### Handoff — the place file is behind the builder

The interiors and cladding exist in `tools/greybox/barrio.luau` and in the suites. They are **not in
the place file**, because running the builder requires either its documented fetch-and-run (refused by
the permission classifier) or transcribing 127KB through a tool call.

`measure.luau`'s 34.8s therefore describes the map as it stands today. **The Phase 7 navmesh claim is
structural rather than measured, which is the stronger form:** `prop()` and `mesh()` both force
`CanCollide = false`, and the builder asserts `dressColliders == 0` at its own foot — so Phase 7
cannot move a route without failing the build first.

---

## Phase 8: Lanterns, the power line, and a budget that fails the build

**Status:** complete for 8.1, the territory-prop half of 8.3, 8.4 and 8.5. **8.2 and the rest of 8.3
were deliberately not done** — see the scope note. Artifact: `artifacts/final-population-perf.md`.

### What landed

| Step | File | What |
| --- | --- | --- |
| 8.1 | `tools/greybox/barrio.luau`, `tests/barrio-lighting.test.luau` | Two fixture eras, three dark lanterns, concrete poles |
| 8.3 (part) | `tools/greybox/barrio.luau`, `tests/barrio-ambient.test.luau` | The territory props — Phase 3's debt |
| 8.4 | `tools/greybox/barrio.luau`, `tests/barrio-receipt.test.luau` | The instance band, as a build failure |
| 8.5 | `artifacts/final-population-perf.md` | The budget table |
| 8.6 | — | **Publish. Not done, and cannot be done by a script.** |

### 8.1 — the dark lanterns are the mechanic, not the decay

A cobra head is the old sodium fixture at **CRI ~22**, where the pool is near-monochrome amber and
colours *die* rather than tint — a real horror-game property. A wedge is an integrated solar LED. Both
now exist on the same street, which is what a barangay actually looks like.

**Three of twelve are dark**, and that is where the step pays for the arm part it added to the other
nine: a dead fixture costs **no light slot**. `MapLight` goes 14 → 11. The three are sited at an alley
mouth, a ring corner and the rice-field edge — places a player has reason to be — and the plaza keeps
all four, because §5 wants the plaza to feel like the safe place.

The suite now pins the mix and the ratio, **and cross-checks the builder's own header** against the
placement table: a lantern going dark changes a number the contract table promises, and a header
naming a count the file no longer produces is the most expensive stale comment in this repo.

### 8.3 — the territory props are the only part of that step that is not decoration

Phase 3 made a rule: the Aswang can only wear a pig near mud. **A rule the player cannot see is a trap
rather than counterplay**, and that is the whole argument for per-form territories being good design.
So all eighteen points now carry the prop that explains them — a wallow and a pen post at the pigs, a
stake, tether and grazed circle at the goats, a swept yard and a roost at the chickens, alley clutter
at the cats, a cardboard scrap and a feeding tin at the dogs.

**The villager points get a stool, a crate table and a bottle**, which is the half of the user's
"villagers doing something" request the mesh rigs cannot answer: Phase 6 kept the mesh villager, and a
mesh has one pose, so the scene around it has to do the work.

`tests/barrio-ambient.test.luau` asserts a branch exists per form — the props are built in a loop, so
a literal grep cannot match `{name}_Wallow`, and a form with no branch would silently get no prop while
all eighteen points stayed correctly sited.

### 8.4 — the band, and the floor is the half that matters

`instanceCount <= 1450` **and `>= 1250`**. The floor exists because of a real incident: the realism
pass's Phase 7 deleted the fence runs, `BANANA_AT` and the scarecrow loop by miscounting `end` lines,
and the instance count **went down — which was that phase's goal, so the loss read as the saving
working.** Every gate was green.

The expected value is **~1377, computed from a measurement rather than guessed**: 1127 counted live,
plus 191 interiors, 5 shells, 12 lantern arms and 45 territory props, less 3 PointLights.

### Correction — 8.2 and the kakawate fence WERE built, after the reason for skipping them failed

They were first deferred on the grounds that the builder cannot be run from this session, so the
result could not be looked at. **That reasoning does not survive.** The cladding in Phase 7 was
prototyped with a fifty-line standalone `execute_luau` script, captured under raised lighting, and only
then written into the builder. Running the whole builder is needed to APPLY the map; it was never
needed to DESIGN a prop. The same method works for a power line or a fence.

So both were prototyped, photographed, corrected and then written in.

**8.2, and one defect the prototype caught.** The first pass rotated the down-guy and its yellow guard
independently, and they **diverged** — the sleeve floated beside the wire instead of sheathing it.
Obvious in `ScreenCapture_12`, invisible to every check in this repo. Both are now built from the same
two endpoints, so they are collinear by construction (`ScreenCapture_13`).

What landed: concrete poles via `paint(pole, "HollowBlock")` — a brown wooden pole is the single most
common way a Philippine street scene goes wrong; a down-guy and yellow guard on each run's end pole;
two porcelain bushings per transformer can, which is what makes a grey cylinder read as a transformer;
a campaign tarpaulin at chest height; and the **telecom bundle**.

**The telecom bundle is the highest-value item in the phase.** Power is few, taut and high; telecom is
many, sagging and low, and **the vertical separation between the two bands is the whole visual
grammar**. The barrio had only the top zone. It is drawn as ONE thick line rather than six thin ones,
which is both the cheap choice and the accurate one — a real bundle is lashed into a single dark mass
at any distance you would see it from. On two runs only, because spaghetti clusters where the
households are.

**8.3's kakawate fence, and a second defect the prototype caught.** `Gliricidia sepium`'s English name
is literally "Fence Post Tree" — the sourced propagation is to plant hardwood cuttings AS the posts,
where they sprout. So a sprouting post is an **existing picket made taller**, and only the foliage is
new geometry.

The first foliage was a near-cubic clump and read as **a green box on a stick** — the exact "lego" look
this whole pass exists to remove (`ScreenCapture_15`). Replaced with two crossed flat slabs: one wide
leaned slab reads as a spray of pinnate leaves, and the second stops it vanishing edge-on
(`ScreenCapture_16`).

### The budget decision, recorded as one

At one in six sprouting posts this phase landed **~1443 against the 1450 ceiling — seven parts of
margin**, which is too thin for the assert to mean anything: the next prop anyone added would fail the
build.

**The ceiling was not raised to fit.** It stands in for §5's mobile budget, which nobody has measured
on a phone, so moving it to accommodate my own art would trade an untested limit for a guess. The
sprout ratio went to one in eight instead, landing at **~1433 with ~17 spare**.

### Still not built

The six-wire → two-wire rework (already correct — the builder draws two conductors on one crossarm,
which the research confirms is right for a rural feeder), the sawali twill re-weave (a texture
question, not geometry), and the plaza dressing (the plaza is already the best-dressed zone).

### Verification

- `lune run tests/barrio-lighting.test.luau` — PASS, 34 assertions
- `lune run tests/barrio-ambient.test.luau` — PASS, 39 assertions over 18 spawn points
- `lune run tests/barrio-receipt.test.luau` — PASS, 22 assertions
- `npm run verify` — green, 54/54 test files, all eight checks ok
