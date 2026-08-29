# Implementation log — barrio realism pass

## Phase 1: Research — the reference library

**Status: complete.** All six reference documents were written by the architect during planning and
`verify:plan` passes all six `test -f` checks. No code changed.

The plan's own warning applies and is recorded here rather than assumed away: **six green ticks are not
a reviewed reference library.** The checks prove the files exist. Their findings were read, and three
are carried forward as decisions rather than facts:

- **Four findings are ❌ unsourced and are being built anyway** — nipa greying, basketball backboard
  material / bent rims / slab cracking, GI roof rust streaking, and grave moss and tilt. Each is
  visually true and undocumented. **They are convention, not evidence**, and at V16 a Filipino
  playtester's correction on any of them should simply be taken.
- **Two research findings overrode the plan** and the plan was corrected: banderitas are faded (bruised
  pink, sickly cream, ghostly grey), not saturated primaries; and roof variation belongs *within* one
  roof (sourced: frequent partial replacement) rather than across houses (unsourced: uniform ageing).
- **One finding is deferred, deliberately.** Whole-barangay blackouts are sourced as ordinary events on
  single-feeder rural networks. That is a mechanic, and mechanics come from §3, not an art pass.
- **One question goes to the Phase 4 gate:** warm amber window light is unsourced; CFL/LED prevalence
  argues for cool fluorescent white, which would also contrast against the sodium streetlights rather
  than blending into them. Step 4.5 must ask rather than default.

---

## Phase 2: Demolition — the stale builder, and the v2.0 map contract

**Status: complete.** `npm run verify` green (exit 0). All six steps PASS under `verify:plan`. The
builder and `measure.luau` were run in Studio Edit mode against the real place, and all ten
`measure.luau` lines report `ok`.

### What changed

| File | Change |
| --- | --- |
| `tests/barrio-legacy.test.luau` | **new.** Bans v1.3 tokens across both greybox scripts |
| `tests/barrio-contract.test.luau` | **new.** The fifteen containers — count, uniqueness, spacing, kubo pairing, enterable floor |
| `tests/barrio-ambient.test.luau` | **new.** The sixteen spawn points — count, overlap, quadrant spread |
| `tests/barrio-receipt.test.luau` | **new.** The builder's header contract table and its build receipt |
| `tests/barrio-measure.test.luau` | **new.** `measure.luau`'s reachability set against the live tags |
| `tools/greybox/barrio.luau` | gate + 12 task points + 4 fetch sources deleted; 15 containers + 16 ambient spawns added; header and receipt rewritten with three build-failing asserts; two kubo opened |
| `tools/greybox/measure.luau` | reachability set rewired onto the live v2.0 tags |

**`tools/greybox/` is now behind `npm run verify` for the first time.** It sits outside `src/`, so
`lint`, `fmt:check`, `analyze` and all five repo checks skip it — until these five suites it was the
only executable artefact in the repo behind no gate at all, and it was emitting deleted v1.3 geometry
into a place file that is not in git.

### Step 2.1 — the guard, watched failing first

Written before the deletions and **observed red**: 8 assertions failed, naming 5 `EscapeGate`,
15 `FetchSource`, 5 `TaskService` and 5 `GateService` occurrences in the builder plus 7 in
`measure.luau`. The `TrialOnly` assertion passed in the same run, which is what proves the suite
discriminates rather than failing everything.

Deviation from the plan's diff: it ended with `process.exit(1)`, which needs `@lune/process`. Every
existing suite in `tests/` uses `error(...)` instead, so this one does too — matching the surrounding
code over the plan.

### Step 2.2 — the deletions

Gate, 12 `Task_` anchors, 4 `FetchSource` anchors, and four blocks of prose that referenced them.
The guard went **red → green over real deletions**, which is the point of having written it first.

The plan predicted the builder's stale prose. It did not predict that `measure.luau` also mentioned
`TaskService`, or that `GateService` appeared 5 times in the builder — the guard found both.

**The guard also caught my own writing.** The replacement comment on the arko used the literal token
`EscapeGate` to explain why the gate was gone, and the suite refused it. Reworded.

### Step 2.3 / 2.4 — the two missing populations

15 `SearchContainer` and 16 `AmbientSpawn` anchors, replacing the deleted v1.3 block.

**Plan correction — `Config.Search.ProximityStuds` does not exist.** The plan named it as the spacing
constraint. The real key is `Config.Search.RangeStuds = 10`. The spacing rule implemented is
`> 2 x RangeStuds` = 20 studs; the closest pair is 22.8 studs.

**Plan correction — `Config.Items` does not exist.** The plan's header rewrite named
`Config.Items.PouchPoolSize` and `Config.Items.PickupRangeStuds`. Both live under `Config.Salt`, which
is what `ItemService` actually reads. Propagated into both greybox files before being caught by
reading `ItemService`; fixed in both.

### Step 2.5 / 2.6 — the self-audit and the false green

Header contract table and receipt rewritten, plus **three asserts that fail the build** rather than
printing a number nobody reads: container count, ambient count, and the Solo Trial's two points.

`measure.luau`'s reachability set was `TaskPoint` / `FetchSource` / `SaltSpawn` / `EscapeGate`, two of
which this phase deletes. **`GetTagged` on a dead tag returns an empty list rather than erroring**, so
the script would have walked a fraction of the map and printed a healthy crossing time over it — a
false green that every later phase of this plan would have cited as proof the layout held.

### Three defects found by the work, none of which were in the plan

**1. `Kubo_SW` was a sealed box.** Four full-width walls, no doorway — 6 parts where the other kubo
have 7. Step 2.3 put a container at its centre and `measure.luau` immediately reported the part
unreachable plus **seven loop failures**, because sealing any corridor cannot connect what was never
connected. `Kubo_SW` is the one kubo v1.3 never placed a task point in, so nothing had ever asked
whether you could get inside it.

**2. §5's enterable floor was never raised for v2.0.** The greybox had **three** enterable kubo and its
comment cited "§5 asks for 6–8 with at least 3 interiors" — the v1.3 text. v2.0 §5 says **"at least 5
enterable — up from 3, because searching is now the whole game and the containers live inside them."**
`Kubo_SW` and `Kubo_N` were opened with inward-facing doors; `Kubo_E` and `Kubo_W` stay sealed to keep
breaking sightlines. Now 5 of 7.

**3. `Container_KuboN_Drum` was not inside `Kubo_N`.** Authored at (0, -104); `Kubo_N` stands at
(35, -75). Forty studs of open ground away, so `measure.luau` passed it as perfectly reachable — the
only thing wrong was the one thing no command was checking, which is that the name means what it says.
Moved to the kubo's own coordinates.

All three are now pinned by `tests/barrio-contract.test.luau`, which grew from 6 assertions to 18.

### Both directions proven, not assumed

Each new suite was mutated and watched failing before being trusted:

| Mutation | Result |
| --- | --- |
| Move a container 8 studs from its neighbour | `FAIL — closest pair is Container_Well_Crate <-> Container_StallSW_Goods at 8.0 studs, needs > 20` |
| Duplicate a container name | `FAIL — 1 duplicate name(s)` |
| Add a second `TaskPoint ×12` header row naming a *renamed* service | `barrio-legacy` **passes blind**; `barrio-receipt` catches it |

That third one is the argument for the ninth suite, demonstrated rather than asserted: the two suites
guard different things, and `barrio-legacy` cannot see a stale contract row that avoids a banned name.

**One self-inflicted false green, caught and recorded.** The first version of the kubo-pairing block
reported 8 assertions where 18 were intended: container names read `Container_KuboNW_Chest` while the
KUBO table keys read `Kubo_NW`, so every lookup missed and the loop silently checked nothing. **The
assertion count still went up.** Fixed by reinserting the underscore; the comment in the suite records
why, because a check that quietly matches zero rows is worse than no check at all.

### Measured in the real place

Builder and `measure.luau` run in Edit mode via the README's HTTP-serve pattern (~200 tokens per run
instead of ~20k inline).

```
[barrio] built — 15 SearchContainer, 6 SaltSpawn, 16 AmbientSpawn, 2 TrialOnly TaskPoint,
                 1 TrialSpawn, 1 TrialChase, 1157 instances, scale 1.55
[barrio] dressing — 859 props, 0 colliders, 0 own lights; 14 lights, 14 tagged MapLight

[measure] barrio
  ok    crossing: 34.8s worst (chapel -> riceSE) — §5 target 30-40s at WalkSpeed 16
  ok    reach: 37/37 tagged parts have a walkable spot inside their own range
  ok    loop: sealing Alley_NE / Alley_SW / Alley_SE / Road_N / Road_S / Road_E / Road_W
        each leaves all 37 tagged parts reachable
  ok    lights: 2 overlapping at worst of 324 sampled points — §5 mobile cap ~8
```

Live tag counts read back from the DataModel: `SearchContainer=15`, `SaltSpawn=6`, `AmbientSpawn=16`,
`TaskPoint=2` (both `TrialOnly`), `EscapeGate=0`, `FetchSource=0`, stray v1.3 instances in `workspace`: 0.

Part count 1098 → 1114. The arithmetic is exact: −1 gate, −12 task points, −4 fetch sources,
+15 containers, +16 ambient spawns, +2 wall splits for the two new doorways.

**Crossing time is unchanged at 34.8s**, which is the claim §5 cares about and the reason `measure.luau`
had to be repaired before it could be believed.

### Not done, and outside this phase

- **The container pads are flat blue rectangles.** §5 requires them "visually obvious as searchable at
  a glance, on a phone, in the dark". Phases 4, 6 and 7 replace each pad's *appearance* while leaving
  the tagged part where it is. Until then the map is mechanically correct and visually a placeholder.
- **The ambient rigs are still four coloured blocks.** `FORM_LOOKS` lives in `AmbientService.luau`,
  which is game code under the five repo checks and outside a builder plan. In Follow Ups.
- **Two settings are not scriptable from this context and need a hand in Studio** — `Lighting.Technology`
  cannot even be *read* here (`lacking capability RobloxScript`), and `StreamingTargetRadius` /
  `StreamingMinRadius` have left the scriptable API. The builder warns with the values to set:
  `StreamingTargetRadius = 341`, `StreamingMinRadius = 170`, and `Technology = Future`. **§5 requires
  Future lighting**, so this matters to the realism pass and not only to perf.
- **The place file is not published.** Neither script can publish, and the place file is the only copy
  of the map. Until `File → Publish to Roblox`, this whole phase is one unsaved session from gone.

---

## Phase 3: The material library

**Status: complete, with a tool failure that changed the phase.** `npm run verify` green.

### `generate_material` is broken in this Studio build

Every call fails identically: `MaterialGenTool:649: invalid argument #2 to 'assert' (string expected,
got table)`. Both patterns, long and short descriptions, Edit mode and Play mode — four attempts, one
error. It is the tool, not the arguments, and the repo's own debug-ladder rule says change the kind of
fix rather than retry a fifth time.

**What survived is the architecture.** `Instance.new("MaterialVariant")` *does* work here (probed), but
a variant with no texture maps is only its base material wearing a name, and nothing in this toolchain
generates images. So the fourteen registry rows resolve to stock `Enum.Material` values, and **the
upgrade path is one field**: adding `Variant = "..."` to a row re-materials every part that asks for
that id, with no other edit anywhere. Each row keeps its `Pattern` and `Prompt` so the generation can be
re-attempted without re-deriving what the surface was supposed to look like.

**Be honest about the size of the gain.** The map already used stock materials sensibly, so several
assignments were no-ops — roads were already `Ground`, the plaza already `Concrete`. The visible
change is bamboo floors, hollow-block chapel walls and whitewashed perimeter and arko. Phase 3 was
planned as the largest quality-per-budget win in the plan and it was not.

### Two self-inflicted faults, both recorded in the code

- **The registry's own doc comment quoted the closing sentinel**, so the non-greedy slice stopped inside
  the comment and handed `loadstring` an unfinished comment. A sentinel must not appear in the region it
  delimits.
- **The `paint()` call-site scan was wrong twice in opposite directions.** Enumerating the characters a
  part expression may contain missed `paint(wall :: Part, "Whitewash")` — a cast is not in
  `[%w_%.%[%]"]`. Broadening the first argument to `.-` then paired a `paint(` on one line with
  `AddTag(p, "MapLight")` forty lines below. It is now a line walk that counts paren depth, because a
  Lua pattern cannot express "within one call".

---

## Phase 4: The hero zone, and the approval gate

**Status: complete.** All steps pass. Full detail in `artifacts/hero-zone.md`.

Court narrowed to the real FIBA-ish proportion with six seeded cracks; rims bent by different amounts
and braced; bench backs; banderitas in the **faded** palette at uneven run heights with paper triangles;
`Kubo_NW` given stilts and a pitched roof.

**The stilt/layout conflict, decided consciously: the layout rule won.** Stilts are decorative and the
floor stays at ground level. Raising it with collidable walls needs a ramp, a ramp is a navmesh change,
and that moves the crossing time §5 measures and would put the container behind a step. The
`hero_kubo_silhouette` capture is the evidence the read survives the compromise — it is the strongest
image in the plan.

**The gate found a real failure.** `hero_container_interior` showed `Container_KuboNW_Chest` **not
visible at all** in an unlit room. §5 requires containers be obvious "at a glance, on a phone, in the
dark" and v2.0's whole loop is searching, so this was playability, not art. Fixed in Phase 6.3.

**Two grep checks in this plan could not pass**, and the reason is the same both times: `grep -c
Bench1_Back` against a loop writing `Bench{index}_Back`. A literal cannot match an interpolation. The
plan named this "the grep trap" and then fell into it — not by proving too little, but by being unable
to see the thing it was pointed at. Replaced with `tests/barrio-budget.test.luau` and
`tests/barrio-plaza.test.luau`, split so the two steps do not share one check.

---

## Phase 5: The eight hero meshes

**Status: complete.** 21,000 triangles against a 27,000 ceiling.

`generate_mesh` works, unlike `generate_material`. Probed and settled before building:
`MeshPart.MeshId` is **not** script-writable (fails silently, leaves `""`); `CreateMeshPartAsync` works
with and without an options table; `Size`, `TextureID` and `Material` are all settable afterwards.

Placed: banana ×12 (replacing 60 parts), graves ×8 (16), scarecrows ×2 (10), tricycles ×2 (8),
well pump ×1, sari-sari shopfronts ×4, kubo shells ×2. **Net −159 parts.**

**Two meshes were deliberately not placed as planned.** The chapel generated well and is recorded at
`Placed = 0`: it is an enterable interior holding two search containers, and a solid shell over it
buries them. The kubo shell went only on the two **sealed** kubo for the same reason — `Kubo_E` and
`Kubo_W` have no interior to occlude and are the two most often seen at distance.

---

## Phase 6: Chapel, well, stalls, arko — and the container fix

**Status: complete.**

Chapel and steeple repainted as a visita (hollow block, whitewash) rather than castle stone; arko the
same; stall grilles and hanging sachet strips added.

**The container fix is the important part of this phase.** Fifteen crate/sack bodies with an emissive
band, and the mechanism matters: **`Neon`, not `PointLight`.** Fifteen lights would break two rules at
once — the builder asserts zero dressing lights and `PerformanceController` caps visible lights — so it
would fail the build rather than degrade the map. Neon glows for no light slot, exactly as the
banderitas bulbs do.

**The first attempt failed in a way that looked like something else.** The band was authored at y=0.65
while the body spans 0.1–2.5, so it was sealed inside the crate emitting into it. The re-test capture
showed the crate silhouette appear and the glow still absent — indistinguishable from Neon simply being
too dim. Moved to the lid at 2.45 and transparency cut from 0.35 to 0.15 (on `Neon`, transparency scales
emission). The second capture shows it clearly. `tests/barrio-civic.test.luau` now pins the height.

---

## Phase 7: The remaining zones — and a silent deletion

**Status: complete.** `Planting` 456 → 253, comfortably inside the ≤400 target.

Bamboo rebuilt as clumping rather than running — one wide crown per clump instead of a three-blade crown
per culm — which is both the accurate shape and the cheap one. Per-house roof variation by index (with
the sourced correction applied: variation *within* a roof as fresher patches, not uniform ageing across
houses). Graves given above-ground tomb slabs and `Neon` candle stubs, detailed in place with **no
cemetery zone**, per the user's explicit scope choice.

### The worst failure of this session, and it stayed green throughout

The bamboo rewrite located the end of the block it was replacing by **counting `end` lines**, miscounted
the nesting, and deleted the fence runs, the `BANANA_AT` coordinate table, the `FieldDressing` folder
and the scarecrow loop along with it.

**Every downstream signal reported success.** The build ran clean. `measure.luau` returned all ten lines
`ok` with the crossing time unchanged at 34.8s. The part count went **down** — which is precisely what
Phase 7 exists to do, so the loss read as the saving working. `local field` silently became `nil` and
the drying racks reparented themselves to `dress`. The plan had specifically named the 72 fence parts as
the one thing in `Planting` that must **not** be thinned, because they are the only planting doing
layout work for §5's sightline rule.

It was caught by counting MeshParts in the live map and finding fourteen missing — not by any gate.

**Recovered from git and re-applied with exact-string edits only.** `tests/barrio-budget.test.luau` now
asserts every structure in that region by name, and that all six fence runs survive, because the failure
mode here is a *deletion that lowers a number the phase was trying to lower*.

---

## Phase 8: Lighting, and the final numbers

**Status: complete.** Full numbers in `artifacts/final-perf.md`.

**The brief's lighting warning was backwards and the plan corrected it.** `SkyController` does not
overwrite the builder — it *captures* five properties once at startup as the baseline it lerps from. So
retuning them here is correct and supported. The real trap is that the capture happens once at `Start`,
so a lighting change is invisible until the play session restarts.

Night warmed rather than brightened: `OutdoorAmbient` off blue toward a dim warm grey, atmosphere
`Decay` toward brown-grey, `EnvironmentDiffuseScale` down to 0.12 (it is the flat skybox fill that makes
a Roblox night read evenly grey) with specular up to 0.28 so wet ground and tin still catch a highlight.

`tests/barrio-lighting.test.luau` pins the split — which properties the builder owns, which the
controller does — and caps `Ambient` at rgb ≤ 30 per channel, so a future "the map is too dark" edit has
to argue with a test rather than quietly flattening §5's shadow.

---

## Final state

`npm run verify` green. `verify:plan`: **28 passed, 0 failed, 5 unverifiable, 0 self-satisfying.**
The five unverifiable steps are the genuinely visual ones and are reported as such rather than given
invented checks.

**Nine new Lune suites put `tools/greybox/` behind `npm run verify` for the first time** — it sits
outside `src/`, so `lint`, `analyze`, `fmt:check` and all five repo checks skip it, and it was the only
executable artefact in the repo behind no gate at all.

### Still open, and all of it needs a human

1. **Publish the place.** The map is not in git. Nothing here is backed up until `File → Publish to Roblox`.
2. **`Lighting.Technology = Future`** — a §5 requirement, not scriptable, cannot even be read from MCP.
   Every capture in this plan was taken without it.
3. **`StreamingTargetRadius = 341`, `StreamingMinRadius = 170`** on Workspace — no longer scriptable.
4. **FPS on a real phone.** The one number in `final-perf.md` that is still missing.
5. **Warm vs cool interior window light** — research argues for cool fluorescent white; everything
   built is warm. A deliberate open question, not an oversight.
6. **Whether it is frightening.** V16's question, and no gate here answers it.

---

## Follow-up: cool fluorescent interiors (user decision, taken)

The open question from Phase 8 — warm amber vs cool fluorescent window light — was decided in favour of
**cool**, and implemented.

`FLUORO` rgb(198,222,226) on the house windows; two of the seven houses keep an `OLD_BULB`
rgb(244,206,152), by index rather than randomly, so the barrio reads as a place people re-fit one tube
at a time rather than a set dressed in one pass. Live counts after rebuild: **15 fluorescent panes, 6
old-bulb, 4 chapel warm.**

**The chapel's four warm panes are now a distinction rather than an inconsistency.** A barangay visita
is candle-lit — `Chapel_Candles` is the map's one interior `MapLight` and §5's "strong lighting
moment" — so it is the single warm interior in a barrio of cold ones, which points at exactly the
building §5 wants noticed.

**An unplanned benefit worth recording.** The container glow bands are warm and the windows are now
cold, so a searchable container reads as the warm object in a cold room. That contrast was not designed
for and is worth keeping in mind if anyone later retunes either colour.

`npm run verify` green; `verify:plan` unchanged at 28 passed / 0 failed / 5 unverifiable.

---

## Follow-up: Phase 3 delivered after all — `generate_material` was intermittent, not broken

**The Phase 3 failure was wrong, and the correction matters more than the original finding.**

Phase 3 recorded `generate_material` as broken in this Studio build after four attempts all failed with
`MaterialGenTool:649: invalid argument #2 to 'assert' (string expected, got table)`. Retried in a later
session, **thirteen of fourteen succeeded on the first attempt**, and the fourteenth succeeded on one
retry. The tool is **intermittent**, not dead.

Four consecutive failures is a very convincing sample and it was the wrong conclusion. The debug-ladder
rule that says "change the kind of fix rather than retry" is right for a deterministic failure and
wrong for a flaky one, and nothing in the error distinguished the two.

**The architecture is what made recovery cheap.** Phase 3's registry was built with `Variant` as a
single optional field per row and every row carrying its `Prompt`, precisely so a later fix would cost
one edit per row rather than a rewrite. It did: fourteen rows gained a variant and four texture-map ids
each, and every part already calling `paint()` upgraded with no other change.

### What is now in the map

**Fourteen generated PBR materials**, each with its own uploaded Color, Normal, Roughness and Metalness
maps — recorded per row, because the variants live in the place file and `git log` will never have them.

**417 of 1,076 parts (39%) wear a generated material**, all fourteen in use:

```
Bamboo 152 · Paddy 91 · Cloth 36 · Sawali 33 · Nipa 29 · RustedSteel 18
Whitewash 16 · DryEarth 11 · WetEarth 10 · HollowBlock 6 · Sack 5
GIRoof 4 · Tarp 4 · CourtSlab 2
```

Coverage was extended past Phase 3's original five surfaces to reach every generated material — the
walls in `building()` (the largest visible surface in the map, and stock until now), the rice blades,
the stall roofs and tarps, the puddles and the banderitas triangles. Five materials had been generated
and never used.

### Two mechanical facts worth keeping

**The tool returns FOUR variants per request**, nested under `MaterialService.AssistantMaterials`. A
`MaterialVariant` only resolves as a **direct child of MaterialService** — left nested it binds nothing,
silently, with the part keeping its stock base. One of each four was promoted and the spares deleted.

**Painting walls had to happen after `side()` runs, not inside it.** That function creates walls through
three branches — solid, split-for-a-door, and the door segments — so painting in one branch leaves the
others stock. The helper now walks the folder, which also catches anything a later edit adds.

### The honest limit

**At `ClockTime 0` the materials are barely visible.** A daylight preview (taken, then reverted by
rebuild) shows them clearly: the paddy ground gains real directional blade detail, the nipa pitch reads
as thatch, the sawali walls show vertical weave. At night, under heavy Atmosphere, most of that is
swallowed — which is exactly what §5 predicts and relies on.

So the materials are a real upgrade that will mostly show **at dawn**, in **lantern pools**, and once
`LightingStyle` is set to `Realistic`. They are not what makes the barrio read at midnight; the
silhouettes and the emissive geometry do that.

**The wall colour may now be too dark to show the weave** — `WOOD` was chosen when walls were flat
plastic. Worth revisiting, but it is a night-legibility decision rather than a bug.

`npm run verify` green. `barrio-materials` at 133 assertions, now guarding the texture-map ids and
asserting every registered surface actually has a variant.
