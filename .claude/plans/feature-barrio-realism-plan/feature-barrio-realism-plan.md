# Plan: Barrio Realism — a hyper-realistic art pass over the whole map

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** none. This is not a numbered V-chunk. It is an art pass over C30's dressing, bound by
  `docs/MVP-SPEC.md` §5 (the map) and §3 (the scope line), and it carries a v1.3 cleanup that V01
  missed because V01 only demolished `src/`.
- **Description:** Make the barrio read as a real rural Philippine barrio at night — PBR
  `MaterialVariant`s on essentially every surface, corrected proportions, and ~8 AI-generated hero
  meshes — without moving the layout, without breaking the ~35-second crossing, and without spending
  the mobile budget. Along the way, bring `tools/greybox/barrio.luau` in line with v2.0 and put it
  under `npm run verify` for the first time.
- **Date:** 2026-08-28
- **What the client is told:** **nothing new.** No phase in this plan adds a remote, an attribute, a
  tag read by a client, or any per-player difference. See "The secrecy position" below — it is short,
  and it is the reason this plan needs no `check:secrecy` argument in any phase.

---

### The one file, and why that is the whole architecture

Everything visual in this plan lands in **`tools/greybox/barrio.luau`** (2,216 lines). That file builds
the entire barrio, is idempotent — it destroys `workspace.Barrio` and rebuilds it — and runs from
Studio's command bar or MCP `execute_luau` **in EDIT mode, never Play**.

**A change made by hand in Studio and not in the script is deleted the next time anyone runs the
builder.** `tools/greybox/README.md` says so outright: *"the next `barrio.luau` run destroys it. Port
anything worth keeping back into the generator, or accept that it is temporary."* That is not a style
preference here — it is the only reason the map is reviewable at all, because the `.rbxl` is gitignored
and binary. Every step below that changes a pixel changes that file.

Two categories legitimately cannot live in the script, because they are IDs minted by Studio:

| Thing | Where it is recorded | Enforced by |
| --- | --- | --- |
| Generated mesh asset IDs (`rbxassetid://…`) | the `ASSETS` sentinel block in `barrio.luau` | `tests/barrio-assets.test.luau` |
| `MaterialVariant` definitions (name + base material) | the same `ASSETS` block | `tests/barrio-materials.test.luau` |

Phase 3 builds that block. It exists because the asset-pipeline skill's warning is exact: *"Record every
asset ID you insert somewhere durable — the place file is not searchable and `git log` will not have
it."* A registry nothing checks is a registry that drifts, so both are read back by Lune tests.

### The builder is outside every existing check, and this plan changes that

I verified this rather than assuming it, because the brief asked me to:

| Gate | Actual scope | Covers `tools/`? |
| --- | --- | --- |
| `npm run lint` | `selene src` | **no** |
| `npm run fmt:check` | `stylua --check src tests` | **no** |
| `npm run analyze` | `luau-lsp analyze` over `src/` | **no** |
| `check:config` | `CONFIG_FILE = 'src/shared/Config.luau'`, sources under `src/` | **no** |
| `check:scope` / `check:secrecy` / `check:ratelimit` | scoped to `src/` by construction | **no** |

**So `check:config`'s no-magic-numbers rule does not bind this file, and must not.** The builder is
nothing *but* coordinates; `SCALE`, `HALF`, `PLAZA` and every position are properties of the place, not
balance knobs. `Config.luau` is required under Lune by `tests/config.test.luau` and has no Roblox
datatypes at all, so map geometry could not move there even if it should.

What *is* available is `npm run test:unit`, which runs **every** `tests/*.test.luau` under Lune and is
inside `npm run verify`. I confirmed empirically that Lune 0.10.5's `@lune/fs` reads
`tools/greybox/barrio.luau` from the repo root (75,592 bytes) and that `loadstring` evaluates a sliced
table literal out of it. **That is this plan's verification backbone**: five new Lune suites read the
builder as text and as data, and from Phase 2 onward the builder is inside the gate that everything else
in this repo already lives behind.

### The secrecy position, in full, so no phase has to re-argue it

The Aswang's identity is server-only state (§6.2). This plan touches **no** `src/` game code, adds **no**
remote, and reads **no** player. The map is identical on every client by construction — it is one folder
of anchored parts, built once in Edit mode, replicated to everyone the same way.

The one shape that *could* leak is the one C30 already fenced and this plan inherits: **`MapLight` marks
a light as scenery, which is the client's permission to switch it off.** The Aswang's eye glow and a
salt pouch's glow are deliberately never tagged, because `PerformanceController` would obediently darken
the only warning a survivor gets. **No step below tags anything new `MapLight` except a lantern**, and
the builder's own third assertion (`mapLights == totalLights`) fails the build if a light escapes the
tag. Phase 8 is where that matters most and it says so again there.

### The layout must not move, and `measure.luau` is how that is proven

§5 sets a **~35-second crossing**, "loops, never dead ends", and the sightline rule. C30 set the
precedent — *dress the barrio without moving it* — and encoded it as three assertions at the foot of the
builder that fail the build rather than warn:

```
assert(dressColliders == 0, "...the navmesh, and therefore the crossing time, has moved")
assert(dressLights == 0,    "...Config.Performance.MaxVisibleLights is being overspent")
assert(mapLights == totalLights, "...PerformanceController cannot cull what it cannot see")
```

**Those three assertions are inherited by every phase in this plan and are never relaxed.** A realism
pass is exactly the pressure that breaks them: a "solid" concrete bench wants `CanCollide = true`, a
covered court wants a light under it. Both are refused. The bench reads as solid because of its material
and silhouette, not because you can bump into it.

`SCALE = 1.55` is a **measured** value — 1.0 gave 25.1s, 1.35 gave 30.2s, and the scaling is sub-linear
because widening the map widens every doorway and the navmesh finds straighter routes. **No step in this
plan changes `SCALE`.** If a re-measure moves, something collided that should not have.

### The mobile budget, as numbers rather than as an intention

§5's budget is non-negotiable and 60% of players are on mobile. This plan commits to:

| Budget | Now | Ceiling after this plan | Why |
| --- | --- | --- | --- |
| Total `Barrio` parts | 1,098 | **≤ 1,250** | +14% headroom for detail, and Phase 7 must *spend* some of it by deleting rather than adding |
| `Dressing.Planting` parts | 456 (42% of the map) | **≤ 400** | a perf hotspot, not a detail opportunity — Phase 7 reduces it |
| MeshParts | 0 | **8** | the hero props, and only those |
| Triangles per prop mesh | — | **1,500–3,000** | asset-pipeline skill; a 20k-tri house you cannot see through fog costs the same frame time as one you can |
| Triangles, chapel hero only | — | **≤ 6,000** | the one exception the skill allows |
| Total added triangles | 0 | **≤ 27,000** | 7 × 3,000 + 6,000 |
| Dynamic lights in `Barrio` | 14, all `MapLight` | **14, all `MapLight`** | unchanged. `Config.Performance.MaxVisibleLights = 8` is what is actually spent |
| Dressing colliders | 0 | **0** | C30 rule 1, asserted |

`MaterialVariant`s are the cheapest item on this list: they cost no parts, no lights and no triangles,
which is exactly why this plan leans on them for most of its realism and on meshes for very little.

### The lighting trap, stated once and repeated in Phase 8

`SkyController` does **not** blindly overwrite the builder's lighting — it is subtler and better than
that, and getting it wrong in either direction breaks the round clock.

**It captures the barrio's night ONCE at startup and treats it as the baseline it lerps away from and
back to.** `Config.Sky` holds only multipliers and the dawn destination. The five captured properties
are `Brightness`, `FogEnd`, `Ambient`, `OutdoorAmbient` and the `Atmosphere`'s `Density`.

So the rule is a split, not a prohibition:

- **The builder still authors the night, and retuning those five in `barrio.luau` is correct and
  supported.** The controller will pick the new values up as its baseline. C28's comment says so:
  *"C30's art pass retunes it here without touching `Config` or any controller."*
- **`ClockTime` belongs to the round** (`Config.Sky.StartClockTime = 3.0`). The builder's `0` is what a
  map author sees in Studio, never what a player sees. Do not treat it as an art value.
- **Properties `SkyController` never touches are free for the builder to own outright** —
  `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `GlobalShadows`, `FogColor`, and the
  Atmosphere's `Color`, `Decay`, `Glare` and `Haze`. Phase 8 spends most of its budget here for exactly
  that reason: these are the levers with no runtime owner to fight.

---

## 2. Comprehensive Plan by Phases

### Phase 1: Research — the reference library

Gathers what a rural Philippine barrio actually looks like, per component, with sources, and turns each
finding into the *specific* change it implies. Nothing in the builder changes in this phase. The value
is that Phases 4–7 can be executed without re-doing the research.

#### Step 1.1: Write the eight component research documents

**File:** `.claude/plans/feature-barrio-realism-plan/references/research-01-bahay-kubo.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/research-01-bahay-kubo.md`

Sourced physical facts on bamboo/nipa construction — stilt height, the silong, sawali walls, roof pitch
and why, weathering — each paired with the concrete builder change it implies.

#### Step 1.2: Write the basketball court and street furniture research

**File:** `.claude/plans/feature-barrio-realism-plan/references/research-02-court-and-street.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/research-02-court-and-street.md`

The barangay court is the single most characteristic feature of a Philippine barrio and the current one
is three painted stripes. Also benches, banderitas, power posts, tricycles.

#### Step 1.3: Write the buildings, graves and planting research

**File:** `.claude/plans/feature-barrio-realism-plan/references/research-03-buildings-graves-planting.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/research-03-buildings-graves-planting.md`

Sari-sari store, chapel/visita, the above-ground grave markers, and the real silhouettes of rice,
bamboo and banana.

#### Step 1.4: Write the night-lighting research

**File:** `.claude/plans/feature-barrio-realism-plan/references/research-04-night-lighting.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/research-04-night-lighting.md`

What actually lights a barrio at night, as colour temperatures and spacing, feeding Phase 8.

#### Step 1.5: Write the material manifest — every surface, and the variant it gets

**File:** `.claude/plans/feature-barrio-realism-plan/references/material-manifest.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/material-manifest.md`

The full list of `MaterialVariant`s to generate, each with its `materialPattern`, `baseMaterial`,
`materialDescription` and the exact parts it lands on. This is Phase 3's input.

#### Step 1.6: Write the hero-mesh shortlist and triangle budget

**File:** `.claude/plans/feature-barrio-realism-plan/references/hero-mesh-shortlist.md`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/references/hero-mesh-shortlist.md`

Exactly eight props, each with its prompt, size in studs, `maxTriangles`, and what it replaces.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** / **Remote direction** / **Rate limiting** / **Phase ownership** — none apply.
  Phase 1 writes documentation only and touches no code.
- **Magic numbers** — none; the research documents record real-world measurements, which are findings
  rather than tunables.
- **Player leaving mid-round** — not applicable.
- **Strict Luau** — no Luau written.
- **Mobile budget** — the manifest and shortlist are where the budget is *committed to*, so the check
  here is that they add up: twelve variants at zero cost, eight meshes at ≤27,000 triangles.
- **Scope** — the research must not smuggle in a mechanic. Anything sourced that implies gameplay goes
  to Follow Ups, not into a later phase.

**Issues identified:**

- **The `test -f` verifies in this phase prove a file exists and nothing more, and that is deliberate.**
  A research document's value is whether its findings are specific and sourced, which no command can
  judge. They are included rather than omitted because a missing document *is* mechanically detectable
  and would silently gut Phases 4–7. **Read the documents; do not treat six green ticks as a reviewed
  reference library.**

- **Four findings came back ❌ unsourced and are built anyway.** Nipa greying, basketball backboard
  material / bent rims / slab cracking, GI roof rust streaking, and grave moss/tilt. Each is
  visually true and undocumented. **They are labelled convention in the research docs and must be
  labelled convention in the implementation log** — because at V16 a Filipino playtester's note on any
  of them should simply be taken, with no source to argue back with.

- **The research contradicted the plan in two places, and the plan was corrected rather than the
  research discounted.** Both corrections are already applied above:
  1. **Banderitas are faded, not saturated.** Step 4.2 originally said to expect "saturated primaries".
     The source describes the default state of barrio bunting as bruised pink, sickly cream and ghostly
     grey — hung weeks early and left up for a year. That is both more accurate *and* a better fit for
     the existing muted palette and a horror night.
  2. **Roof variation belongs *within* a roof, not between houses.** Step 7.1 originally varied roof
     age across the seven kubo. Ageing-to-grey is unsourced; frequent *partial* replacement is sourced.
     So each roof should be multi-toned — fresh brown patches against older material.

- **One finding is a genuine design idea and is deliberately NOT built.** Whole-barangay blackouts are
  sourced as ordinary events caused by single-feeder rural networks. That is a mechanic, and mechanics
  come from §3, not from an art pass. It is in Follow Ups for the user to accept or reject.

- **One finding inverts a horror-game instinct and needs a human decision.** Warm amber window light is
  unsourced; the available evidence (CFL/LED prevalence) argues for **cool fluorescent white** interior
  light. Cool white is arguably better here — it contrasts against the sodium streetlights instead of
  blending into them. **Step 4.5's approval gate must ask this explicitly** rather than defaulting.

---

### Phase 2: Demolition — the stale builder, and the v2.0 map contract

The builder still emits v1.3 geometry that V01 deleted from the code. It also fails to emit two things
v2.0 requires. This phase fixes both and ends by putting the file under `npm run verify`.

**The v2.0 map contract, established by reading the services rather than the builder's header.** The
header is the stale thing, so it is not evidence. What the code actually calls `GetTagged` on today:

| Tag | Read by | Count required | In the builder now? |
| --- | --- | --- | --- |
| `SearchContainer` | `SearchService.discoverPool` → `Config.Search.ContainerCount = 15` | 15 | **NO — zero** |
| `SaltSpawn` | `ItemService.discoverPool` → `Config.Items.PouchPoolSize = 6` | 6 | yes, 6 |
| `AmbientSpawn` | `AmbientService.spawnPoints` → `Config.Ambient.PerForm × 4` | 16 | **NO — zero** |
| `TaskPoint` | **`TrialService.trialPoints` only** | 2, both `TrialOnly` | yes, 14 (12 stale) |
| `TrialSpawn` | `TrialService.trialSpawn` | 1 | yes |
| `TrialChase` | `TrialService` (C22 rig) | 1 | yes |
| `MapLight` | `PerformanceController` | 14 | yes |
| `EscapeGate` | **nobody. `GateService` does not exist** | 0 | yes, 1 — **delete** |
| `FetchSource` | **nobody. `TaskService` does not exist** | 0 | yes, 4 — **delete** |

Two findings in that table are bugs rather than tidiness, and both are silent:

**`SearchContainer` is zero and searching is the entire v2.0 game.** `SearchService` warns
unconditionally on an empty pool — the comment says *"A barrio with no containers in it is a fault whose
only player-visible symptom is that there is nothing to do and nobody knows why."* Building the fifteen
is the highest-value step in this plan and it happens to also be an art step, because §5 requires they be
*"visually obvious as searchable at a glance, on a phone, in the dark."*

**`AmbientSpawn` is zero, so `AmbientService` is using its fallback ring** — sixteen animals in a circle
at the origin, overlapping the plaza. The service's own comment says the fallback *"fires only on ZERO
tagged parts"*, which is exactly today's state.

**`TaskPoint` must NOT be deleted wholesale.** `TrialService` still holds `local TAG_POINT = "TaskPoint"`
and reads it for the Solo Trial's two practice points. Delete the tag name entirely and the Solo Trial —
§9.1's answer to the cold-start problem — silently stops having anything to do. The twelve round points
go; the two `TrialOnly` ones stay, tag and all.

#### Step 2.1: Add the legacy-token guard test

**File:** `tests/barrio-legacy.test.luau`
**Verify:** `test -f tests/barrio-legacy.test.luau`

Written **first**, so it goes red and then green — the point of a guard is that you watched it fail. It
reads the builder and `measure.luau` as text and fails on any surviving v1.3 token.

> **Why an existence check here, and why that is the honest one.** At this step the suite is *supposed*
> to fail: the tokens are still in the file and Step 2.2 is what removes them. Gating on
> `lune run tests/barrio-legacy.test.luau` would demand the guard pass before the thing it guards has
> been done, so the step could only go green by writing a guard that does not guard. The deliverable of
> *this* step is the suite itself, and `test -f` is exactly the strength of claim that supports —
> **it proves the file exists, not that it is a good guard.** Step 2.2 is where the suite has to earn
> its keep by going green over real deletions.
>
> Two things a reader should check by eye, because no command here can: that the `PASS` line **counts**
> what it ran rather than printing a literal (this repo's `check:testcount` rule, born from
> `config.test.luau` printing a hardcoded `34` forever), and that the suite was actually **observed
> failing** before 2.2 was started.

```diff
+--!strict
+--[[
+	The builder must not resurrect v1.3.
+
+	`tools/greybox/barrio.luau` is not under `src/`, so `lint`, `fmt:check`, `analyze` and all five
+	repo checks skip it — I verified each one's scope rather than assuming. Until this suite it was
+	the only executable artefact in the repo behind no gate at all, and it still emitted the escape
+	gate and twelve task anchors that V01 deleted from the code. Re-running it resurrected them into
+	the place file, where nothing would ever have shown it: the map is not in git.
+
+	Lune has no `game`, so this cannot run the builder. It reads it as TEXT, which is enough for the
+	class of fault that actually happened here — a name that should no longer appear anywhere.
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
+local function occurrences(haystack: string, needle: string): number
+	local _, n = string.gsub(haystack, needle, "")
+
+	return n
+end
+
+local builder = fs.readFile("tools/greybox/barrio.luau")
+local measure = fs.readFile("tools/greybox/measure.luau")
+
+-- V01 demolished tasks, the escape gate and ghosts. No service reads either tag now.
+for _, dead in { "EscapeGate", "FetchSource", "TaskService", "GateService" } do
+	check(
+		`the builder no longer mentions {dead}`,
+		occurrences(builder, dead) == 0,
+		`{occurrences(builder, dead)} occurrence(s) in barrio.luau`
+	)
+	check(
+		`measure.luau no longer mentions {dead}`,
+		occurrences(measure, dead) == 0,
+		`{occurrences(measure, dead)} occurrence(s) in measure.luau`
+	)
+end
+
+--[[
+	`TaskPoint` IS THE EXCEPTION AND IT IS THE WHOLE REASON THIS IS A TEST RATHER THAN A GREP.
+
+	`TrialService` still holds `local TAG_POINT = "TaskPoint"` and reads it for the Solo Trial's two
+	practice points. A blanket ban on the token would be wrong and would break §9.1's cold-start
+	answer silently. What is banned is the ROUND's twelve, which all carried the `Task_` name prefix.
+]]
+check(
+	"the round's twelve Task_ anchors are gone",
+	occurrences(builder, "\"Task_") == 0,
+	`{occurrences(builder, "\"Task_")} Task_ anchor name(s) remain`
+)
+check(
+	"the Solo Trial's two TaskPoint anchors survive",
+	occurrences(builder, "TrialOnly") >= 2,
+	`{occurrences(builder, "TrialOnly")} TrialOnly reference(s) — TrialService.trialPoints needs both`
+)
+
+print(
+	if failures > 0
+		then `  FAIL  barrio-legacy: {checked - failures}/{checked}`
+		else `  PASS  barrio-legacy: {checked}/{checked} checks`
+)
+
+if failures > 0 then
+	process.exit(1)
+end
```

> **`process` needs `local process = require("@lune/process")` at the top.** Every existing suite in
> `tests/` already does this; copy the exact preamble from `tests/search-pool.test.luau` rather than
> reproducing it from this diff, which elides it for length.

#### Step 2.2: Strip the escape gate, the twelve round TaskPoints and the four FetchSources

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-legacy.test.luau`

**The three deletions are one step because they share one proof.** The suite from 2.1 goes green exactly
when all of them are done, and there is no way to prove any one of them in isolation:
`grep` cannot assert *absence* here — the runner executes argv with no shell, so `!`, pipes and `test`
are unavailable, and `grep -L` inverts (exit 1 when the token is gone, which is backwards). A Lune suite
reading the file as text is the only thing that proves a removal, and it proves all three at once.

**First, the gate:**

```diff
-local gate = box("EscapeGate", 0, 3, -32, 18, 6, 1.5, Color3.fromRGB(148, 128, 92), arko)
-
-gate.Material = Enum.Material.WoodPlanks
-CollectionService:AddTag(gate, "EscapeGate")
```

> **The arko itself stays.** It is the village gate arch and a good landmark; only the gameplay part
> parented under it dies. Phase 6 re-dresses the arko. Check the four surrounding lines when applying
> this — `gate` may be referenced again below the excerpt.

**Then the round's task pool and its fetch sources:**

```diff
-local TASKS = {
-	{ Name = "Task_KuboNWHearth", X = -78, Z = -78, Type = "FETCH", Source = "FetchSource_Rice" },
-	-- ... all twelve entries
-	{ Name = "Task_KuboSEStore", X = 78, Z = 78, Type = "FETCH", Source = "FetchSource_Chapel" },
-}
-
-for _, point in TASKS do
-	local attributes = { TaskType = point.Type }
-
-	if point.Source then
-		attributes.FetchSourceName = point.Source
-	end
-
-	anchor(point.Name, "TaskPoint", point.X, point.Z, anchors, attributes)
-end
-
-local SOURCES = {
-	{ Name = "FetchSource_Rice", X = 130, Z = 150 },
-	{ Name = "FetchSource_Chapel", X = -14, Z = -146 },
-	{ Name = "FetchSource_Well", X = -76, Z = 44 },
-	{ Name = "FetchSource_Plaza", X = 22, Z = 30 },
-}
-
-for _, source in SOURCES do
-	local p = anchor(source.Name, "FetchSource", source.X, source.Z, anchors)
-end
```

> **Two comments elsewhere in the file reference these coordinates as obstacles** — line ~1824 says
> *"clear of the north road and `FetchSource_Chapel`"*, and the power-line and planting tables mention
> `SaltSpawn` positions they were moved off. The `SaltSpawn` ones are still live and must not be
> touched. The `FetchSource` ones become stale prose and must be reworded, or Step 2.2's own verify
> fails on the leftover token — which is the guard working correctly.

#### Step 2.3: Add the fifteen SearchContainer anchors

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-contract.test.luau`

The highest-value step in the plan. §5 requires the fifteen be *"spread so that no single house is worth
camping and no two are close enough that one search covers two"*, and
`Config.Search.ProximityStuds` is the distance that makes "one search covers two" concrete — read it and
space the anchors at **more than twice** that value.

```diff
+--[[
+	THE FIFTEEN SEARCHABLE CONTAINERS — §5's "~15 searchable containers", and the reason the map
+	exists at all in v2.0. `SearchService.discoverPool` reads this tag and evaluates the pool against
+	`Config.Search.ContainerCount`; a short pool warns unconditionally and a zero pool is a barrio
+	with nothing to do in it.
+
+	NAMES MUST BE UNIQUE. `discoverPool` keys by Name and reports duplicates as skipped, so two
+	`Container_Kubo` parts are one container and a silent short pool.
+
+	SPREAD IS A DESIGN CONSTRAINT, NOT A LAYOUT PREFERENCE. §5: "no single house is worth camping and
+	no two are close enough that one search covers two." At least five of the seven kubo carry one,
+	because §5 also asks for "at least 5 enterable" and the containers are why you enter.
+]]
+local CONTAINERS = {
+	-- house interiors — five kubo, one each, so no house is the obvious first stop
+	{ Name = "Container_KuboNW_Chest", X = -78, Z = -78 },
+	{ Name = "Container_KuboNE_Sack", X = 78, Z = -78 },
+	{ Name = "Container_KuboSE_Chest", X = 78, Z = 78 },
+	{ Name = "Container_KuboSW_Basket", X = -78, Z = 78 },
+	{ Name = "Container_KuboN_Drum", X = 0, Z = -104 },
+	-- the civic buildings
+	{ Name = "Container_Chapel_Pew", X = -14, Z = -146 },
+	{ Name = "Container_Chapel_Vestry", X = 10, Z = -152 },
+	{ Name = "Container_Well_Crate", X = -76, Z = 44 },
+	-- the four sari-sari stalls, which are literally shops and read as searchable instantly
+	{ Name = "Container_StallNW_Goods", X = -58, Z = -58 },
+	{ Name = "Container_StallNE_Goods", X = 58, Z = -58 },
+	{ Name = "Container_StallSE_Goods", X = 58, Z = 58 },
+	{ Name = "Container_StallSW_Goods", X = -58, Z = 58 },
+	-- the edges, so the rice field and the alleys are worth walking into
+	{ Name = "Container_Rice_Rack", X = 120, Z = 148 },
+	{ Name = "Container_AlleySW_Crate", X = -100, Z = 60 },
+	{ Name = "Container_Plaza_Bench", X = 22, Z = 30 },
+}
+
+for _, container in CONTAINERS do
+	anchor(container.Name, "SearchContainer", container.X, container.Z, anchors)
+end
```

> **QUESTION — these fifteen coordinates are placeholders and must be checked against the real map
> before the phase closes.** I took them from positions the builder already proved walkable (the dead
> `Task_`/`FetchSource` anchors and live `SaltSpawn` points sat at most of them), which makes them
> reachable but does **not** make them well-spread. `measure.luau` reports reachability per tagged
> point; Step 2.6 rewires it onto `SearchContainer` precisely so this is checkable rather than assumed.
>
> **IMPORTANT — the anchor pads are placeholders in a second sense.** `anchor()` builds a flat 6-stud
> blue pad. §5 demands containers be *"visually obvious as searchable at a glance, on a phone, in the
> dark"*, and a flat pad is not. Phases 4, 6 and 7 replace each pad's *appearance* — a rice sack, a
> chest, a stall crate — while leaving the tagged part exactly where it is.

#### Step 2.4: Add the sixteen AmbientSpawn points

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-ambient.test.luau`

**Answering the brief's question directly: ambient life is service-spawned at runtime, not
map-authored.** `AmbientService.Start` creates sixteen single-part placeholder rigs into
`workspace.AmbientLife` from `FORM_LOOKS`, four each of CAT/DOG/PIG/VILLAGER. The map's only job is to
say *where*, via `AmbientSpawn`, and today it does not — so the ring fallback is running.

```diff
+--[[
+	WHERE THE AMBIENT POPULATION STANDS. `AmbientService` spawns the animals; this only sites them.
+
+	§5 is explicit that the COUNT is what matters — "if there is one pig in the barrio, the disguise is
+	meaningless" — and `Config.Ambient.PerForm` (4) x 4 forms is sixteen. Sixteen points, so no two
+	entities start on top of each other.
+
+	WITHOUT THESE THE SERVICE FALLS BACK TO A RING AT THE ORIGIN, which is what the barrio does today:
+	sixteen animals in a circle through the middle of the plaza. The fallback fires only on ZERO
+	tagged parts, so adding even one changes the behaviour — add all sixteen.
+
+	SPREAD ACROSS ZONES, NOT CLUSTERED. §4.5's deduction is "which cat", never "is that a cat", so an
+	Aswang wearing a cat needs OTHER cats plausibly nearby wherever it hides.
+]]
+local AMBIENT_POINTS = {
+	{ -30, 30 }, { 30, 24 }, { 26, -34 }, { -18, -30 },
+	{ -58, -58 }, { 58, -58 }, { 58, 58 }, { -58, 58 },
+	{ -76, 44 }, { 0, -104 }, { -14, -146 }, { 120, 148 },
+	{ -100, 60 }, { 100, -60 }, { -40, 100 }, { 40, -100 },
+}
+
+for index, at in AMBIENT_POINTS do
+	anchor(`AmbientSpawn_{index}`, "AmbientSpawn", at[1], at[2], anchors)
+end
```

> **NOTE — the ambient rigs' *appearance* is out of this plan's reach and that is deliberate.**
> `FORM_LOOKS` lives in `src/server/Services/AmbientService.luau`, which is game code under the five
> repo checks. Turning four coloured blocks into four believable animals is a real gap in a realism
> pass and it is raised in Follow Ups rather than smuggled into a builder plan.

#### Step 2.5: Rewrite the header contract block and the receipt

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-receipt.test.luau`

> **A ninth suite, and why it is not suite-sprawl.** `barrio-legacy` is Step 2.2's gate; reusing it here
> would give two steps in one phase the same check, which proves nothing about either. More to the
> point, this step guards a genuinely different thing: **the builder's own self-audit** — the header
> table that tells a reader what the map owes the services, and the receipt that counts it at build
> time. `tests/barrio-receipt.test.luau` asserts:
>
> - the header names **no** `TaskService` or `GateService` — the exact defect described below
> - the header table lists `SearchContainer` and `AmbientSpawn`
> - the receipt `print` counts both, plus `TrialOnly`
> - the three new `assert(` literals **equal the values in `Config.luau`** — the reconciliation that
>   makes the builder's hand-copied `15` and `16` safe to hand-copy at all

The header's contract table names `TaskService` and `GateService` and is the single most misleading
thing in the file — the brief was right not to trust it. The receipt at the foot counts `TaskPoint`,
`FetchSource` and `EscapeGate`, so after 2.2–2.4 it would print zeros for two of them and never mention
the fifteen containers that now matter.

```diff
-	  TaskPoint    ×12  TaskService.discoverPool      unique Names; Config.Tasks.PoolSize
-	                    attribute `TaskType`          HOLD | TIMING | FETCH | TWO_PERSON, absent = HOLD
-	                    attribute `FetchSourceName`   names a FetchSource; absent = furthest unused
-	  FetchSource  × 4  TaskService.discoverSources   one per FETCH task drawn in a round
-	  SaltSpawn    × 6  ItemService.discoverPool      Config.Salt.PouchPoolSize
-	  EscapeGate   × 1  GateService.discoverGates     proximity win, Config.Tasks.GateRangeStuds = 6
+	  SearchContainer ×15  SearchService.discoverPool   unique Names; Config.Search.ContainerCount
+	  SaltSpawn    × 6  ItemService.discoverPool      Config.Items.PouchPoolSize
+	  AmbientSpawn ×16  AmbientService.spawnPoints    Config.Ambient.PerForm x 4; ZERO = ring fallback
 	  TrialSpawn   × 1  TrialService.trialSpawn       where a trial player is placed
 	  TrialChase   × 1  TrialService (C22 rig)        where the scripted rig appears
 	  MapLight     ×14  PerformanceController         SCENERY lights only — never a gameplay tell
 	  TaskPoint    × 2  TrialService.trialPoints      attribute `TrialOnly = true` — see the corner
```

> **THE TWO `TaskPoint` LINES ARE NOT THE SAME LINE AND EXACTLY ONE OF THEM GOES.**
>
> **Deleted:** `TaskPoint ×12 TaskService.discoverPool` — it names a service V01 removed, and it is the
> single most misleading line in the file. This is the line Step 2.5 exists to delete.
>
> **Kept, unchanged:** `TaskPoint × 2 TrialService.trialPoints` — the Solo Trial's two practice points
> still carry that tag and `TrialService` still reads it. Deleting this one would describe the map as
> having no trial points while it still has two.
>
> They sit six lines apart, differ only in count and service, and an earlier draft of this plan left the
> ×12 line in as unchanged context by mistake — proof that the confusion is real rather than theoretical.
> `tests/barrio-receipt.test.luau` asserts the token `TaskService` is absent from the whole file, which
> is what catches this class of miss.

And the receipt:

```diff
 print(
-	`[barrio] built — {count("TaskPoint") - countTrialOnly()} TaskPoint (+{countTrialOnly()} TrialOnly), `
-		.. `{count("FetchSource")} FetchSource, {count("SaltSpawn")} SaltSpawn, `
-		.. `{count("EscapeGate")} EscapeGate, {count("TrialSpawn")} TrialSpawn, `
+	`[barrio] built — {count("SearchContainer")} SearchContainer, {count("SaltSpawn")} SaltSpawn, `
+		.. `{count("AmbientSpawn")} AmbientSpawn, {countTrialOnly()} TrialOnly TaskPoint, `
+		.. `{count("TrialSpawn")} TrialSpawn, `
 		.. `{count("TrialChase")} TrialChase, {#root:GetDescendants()} instances, scale {SCALE}`
 )
+
+--[[
+	THE CONTRACT ASSERTED, NOT MERELY PRINTED — the same upgrade C30 made for colliders and lights.
+
+	A receipt you have to read is a receipt nobody reads. Each of these three fails the build, because
+	each one's player-visible symptom is "the game is boring" with nothing in the log.
+]]
+assert(
+	count("SearchContainer") == 15,
+	`[barrio] {count("SearchContainer")} SearchContainer parts, expected 15 — SearchService's pool will be short`
+)
+assert(
+	count("AmbientSpawn") == 16,
+	`[barrio] {count("AmbientSpawn")} AmbientSpawn parts, expected 16 — AmbientService will fall back to a ring at the origin`
+)
+assert(
+	countTrialOnly() == 2,
+	`[barrio] {countTrialOnly()} TrialOnly TaskPoint parts, expected 2 — the Solo Trial has nothing to do`
+)
```

> **IMPORTANT — the asserted counts are typed literals here and that is correct.** `barrio.luau` cannot
> `require` `Config.luau`: it runs through `loadstring` in Studio with no `script` and no
> `ReplicatedStorage` path at build time. So the 15 and the 16 are duplicated from Config by hand, and
> the duplication is exactly what `tests/barrio-contract.test.luau` exists to police — that suite reads
> **both** files and fails when they disagree. Do not "fix" this by deleting the assert.

#### Step 2.6: Repair `measure.luau`'s stale reachability set

**File:** `tools/greybox/measure.luau`
**Verify:** `lune run tests/barrio-measure.test.luau`

`measure.luau` is stale in the same way and the brief did not flag it, so it is worth naming loudly:
**it builds its reachability set from `TaskPoint`, `FetchSource` and `EscapeGate`.** After Step 2.2
those return 4, 0 and 0 parts, so it would report a healthy crossing time over almost nothing and the
loop test would seal corridors against an empty set. This plan's central claim — *the layout did not
move* — rests on this file, so it must be repaired in the same phase that breaks it.

```diff
 local RANGES = {
-	TaskPoint = 9, -- Config.Tasks.PresenceRangeStuds
-	EscapeGate = 6, -- Config.Tasks.GateRangeStuds
+	-- Config.Search.ProximityStuds — how close you must be to start a search AND STAY.
+	SearchContainer = 6,
+	SaltSpawn = 6, -- Config.Items.PickupRangeStuds
 }
```

> **QUESTION — confirm both range constants against `Config.luau` before applying.** I read
> `Config.Search.ProximityStuds` as the search-start distance (V03) but did not read its literal value,
> and `PickupRangeStuds` moved namespace in the v2.0 rename (`Salt.*` → `Items.*`). These numbers only
> affect how forgiving the path test is, not the crossing time, but a wrong one makes a reachable
> container read as unreachable.

The loop test's comment about *"a corridor that cut off a `SaltSpawn`, a `FetchSource` or the
`EscapeGate`"* needs the same treatment — and the fifteen containers make it a genuinely stronger test
than it was, because they are spread across every zone by design.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none possible. This phase adds three tag names to anchored parts that are
  identical on every client. No UserId, no role, no per-player anything. `check:secrecy` is `src/`-scoped
  and does not read this file, and that is correct rather than a gap.
- **Remote direction** — no remotes touched.
- **Rate limiting** — no `OnServerEvent` handlers touched.
- **Magic numbers** — `check:config` does not scan `tools/`, verified. The 15/16 literals in the new
  asserts are deliberate duplication policed by `tests/barrio-contract.test.luau`; see Step 2.5.
- **Phase ownership** — `RoundService` untouched; nothing here calls `setPhase`.
- **Player leaving mid-round** — not applicable; this phase runs in Edit mode, before any round.
- **Strict Luau** — `analyze` does not cover `tools/`, so a type error here is caught only by Studio at
  run time. Run the builder before closing the phase.
- **Mobile budget** — net part change is **+31 anchors** (15 containers + 16 ambient) **−17**
  (12 tasks + 4 sources + 1 gate) = **+14**. Anchors are non-collidable `SmoothPlastic` pads with no
  lights. Well inside the ≤1,250 ceiling.
- **Scope** — nothing from §3's OUT list. This phase *removes* v1.3 features.

**Issues identified:**

- **The `Anchors` folder's part count changes, and `measure.luau`'s loop test walks it.** The loop test
  seals seven corridors and re-checks reachability of every tagged point. Fifteen containers spread
  across every zone is a **stricter** test than twelve clustered task points, so a corridor that was
  previously "fine" may now legitimately fail. **A failure here is information, not a regression** —
  it means an alley was a dead end for a zone the old anchor set never probed. Do not "fix" it by
  moving a container; fix it by reading which corridor, or raise it.
- **`SearchService` sorts `GetTagged` output before drawing, and duplicate Names are silently skipped.**
  Fifteen unique names is a hard requirement, not a style rule. The contract test asserts uniqueness.
- **The 2.3 deletion leaves stale prose behind.** At least three comments elsewhere reference
  `FetchSource_*` coordinates as obstacles they were moved off. The legacy guard from 2.1 will catch
  them, which is the guard doing its job — reword rather than waive.

---

### Phase 3: The material library

Generates the `MaterialVariant`s, records them durably, and builds the one helper that makes them work
at all.

**Why materials carry most of this plan's realism.** They cost **no parts, no lights and no triangles**
— the only three things §5's budget actually meters. The asset-pipeline skill puts it plainly: *"a
correct material on a plain Part reads better in fog than a detailed mesh with the default plastic
finish."* The barrio has 1,098 parts and **zero** MaterialVariants today, so this is the largest
available quality gain per unit of budget in the entire project.

**The silent failure this phase is built around.** From the skill: *"Set **both** on the part: `Material`
to the base, `MaterialVariant` to the name. Setting only one silently does nothing."* No error, no
warning, no visual difference from a typo — the part just stays plastic. Across ~1,100 parts that is
undetectable by eye. Step 3.1's helper makes the pairing structural and Step 3.1's test makes a
hand-written unpaired assignment a red tree.

#### Step 3.1: Add the ASSETS registry, the `paint()` helper, and the pairing test

**File:** `tools/greybox/barrio.luau`
**Verify:** `test -f tests/barrio-materials.test.luau`

> **An existence check, for the same reason Step 2.1 has one.** At this step the registry is *empty* —
> Step 3.2 is what fills it — so a suite asserting twelve well-formed rows is supposed to be red here.
> Gating on `lune run` would force the step green by writing a suite that asserts nothing. The
> deliverable of *this* step is the registry block, the `paint()` helper and the suite itself, and
> `test -f` is exactly the strength of claim that supports. **Step 3.2 is where the suite earns its
> keep.**

```diff
+--#ASSETS-BEGIN
+--[[
+	THE ASSET REGISTRY — the one thing in this file that is not reproducible by re-running it.
+
+	Every MaterialVariant and every generated mesh is minted by Studio and lives in the PLACE FILE,
+	which is gitignored, binary and unsearchable. The asset-pipeline skill's instruction is exact:
+	"Record every asset ID you insert somewhere durable — the place file is not searchable and
+	`git log` will not have it." This block is that durable place.
+
+	IT IS ALSO A TEST FIXTURE. `tests/barrio-materials.test.luau` and `tests/barrio-assets.test.luau`
+	slice this block out between the two sentinels and `loadstring` it into a real table — verified
+	working under Lune 0.10.5. So the registry cannot drift from the file that uses it without the
+	tree going red, which is the only reason a hand-maintained registry is trustworthy at all.
+
+	DO NOT REFORMAT THE SENTINEL LINES. The slice is `--#ASSETS-BEGIN\n(.-)--#ASSETS-END`.
+]]
+local ASSETS = {
+	--[[
+		Materials. `Variant` is the MaterialVariant's Name as generated; `Base` is the BaseMaterial it
+		was generated against and MUST match what `paint()` assigns, or the variant silently does
+		nothing. `Pattern` is recorded so a lost variant can be regenerated with the same prompt.
+	]]
+	Materials = {
+		-- filled in by Step 3.2, one row per generated variant
+		-- { Id = "BarrioNipa", Variant = "BarrioNipa", Base = "Grass", Pattern = "Organic" },
+	},
+
+	-- Meshes. Filled in by Phase 5. `Tris` is the maxTriangles the mesh was generated at.
+	Meshes = {},
+}
+--#ASSETS-END
+
+--[[
+	PAINT A PART — and the reason this is a function rather than two assignments.
+
+	A MaterialVariant does nothing unless BOTH `Material` and `MaterialVariant` are set, and it fails
+	SILENTLY: no error, no warning, and a plastic-looking part among eleven hundred of them. This
+	helper makes the pair impossible to half-apply, and it warns when asked for a variant the registry
+	has never heard of — which is the typo case, and the one a screenshot would not catch either.
+]]
+local MATERIAL_BY_VARIANT: { [string]: Enum.Material } = {}
+
+for _, entry in ASSETS.Materials do
+	MATERIAL_BY_VARIANT[entry.Variant] = (Enum.Material :: any)[entry.Base]
+end
+
+local function paint(p: BasePart, variant: string): BasePart
+	local base = MATERIAL_BY_VARIANT[variant]
+
+	if base == nil then
+		warn(
+			`[barrio] MaterialVariant "{variant}" is not in the ASSETS registry — {p.Name} keeps its `
+				.. `base material. Generate it and record it, or fix the name.`
+		)
+
+		return p
+	end
+
+	p.Material = base
+	p.MaterialVariant = variant
+
+	return p
+end
```

The test that makes the registry load-bearing:

```diff
+--!strict
+--[[
+	The barrio's material registry, and the silent failure it exists to prevent.
+
+	A MaterialVariant needs BOTH `Material` and `MaterialVariant` set or it does nothing at all — no
+	error, no warning, no visual difference from a typo. Across ~1,100 parts that is not findable by
+	eye, which is why it is findable by this instead.
+]]
+
+local fs = require("@lune/fs")
+local process = require("@lune/process")
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
+local builder = fs.readFile("tools/greybox/barrio.luau")
+
+-- Slice the registry out and evaluate it. Proven working under Lune 0.10.5.
+local block = string.match(builder, "%-%-#ASSETS%-BEGIN\n(.-)%-%-#ASSETS%-END")
+
+check("the ASSETS registry block is present and sentinel-delimited", block ~= nil)
+
+if block == nil then
+	print(`  FAIL  barrio-materials: {checked - failures}/{checked}`)
+	process.exit(1)
+end
+
+local loader = loadstring or load
+local assets = (assert(loader(`{block}\nreturn ASSETS`, "assets")) :: any)()
+
+--[[
+	THE PAIRING RULE, CHECKED STRUCTURALLY.
+
+	`paint()` is the only sanctioned way to set a variant, precisely because it cannot half-apply the
+	pair. A hand-written `.MaterialVariant = ` outside that helper is the shape that fails silently,
+	so it is banned outright rather than reviewed case by case.
+]]
+local handWritten = 0
+
+for line in string.gmatch(builder, "[^\n]+") do
+	if string.match(line, "%.MaterialVariant%s*=") and not string.match(line, "p%.MaterialVariant") then
+		handWritten += 1
+	end
+end
+
+check(
+	"no MaterialVariant is assigned outside the paint() helper",
+	handWritten == 0,
+	`{handWritten} hand-written assignment(s) — each one silently does nothing if Material is unset`
+)
+
+-- Every variant the builder paints with must exist in the registry, or paint() only warns at runtime
+-- in Studio, where nobody is watching the output.
+local unknown = {}
+
+for variant in string.gmatch(builder, "paint%([%w_%.]+,%s*\"([%w_]+)\"%)") do
+	local found = false
+
+	for _, entry in assets.Materials do
+		if entry.Variant == variant then
+			found = true
+			break
+		end
+	end
+
+	if not found then
+		table.insert(unknown, variant)
+	end
+end
+
+check(
+	"every painted variant is in the registry",
+	#unknown == 0,
+	`unregistered: {table.concat(unknown, ", ")}`
+)
+
+-- A registry row with no Base cannot be applied at all; one with no Variant cannot be looked up.
+for index, entry in assets.Materials do
+	check(`registry row {index} names a variant`, type(entry.Variant) == "string" and #entry.Variant > 0)
+	check(`registry row {index} names a base material`, type(entry.Base) == "string" and #entry.Base > 0)
+end
+
+print(
+	if failures > 0
+		then `  FAIL  barrio-materials: {checked - failures}/{checked}`
+		else `  PASS  barrio-materials: {checked}/{checked} checks`
+)
+
+if failures > 0 then
+	process.exit(1)
+end
```

> **NOTE — the hand-written-assignment scan is deliberately crude and will need one tuning pass.** The
> pattern above excludes `p.MaterialVariant` because that is the line *inside* `paint()` itself.
> Confirm the exclusion still matches after writing the helper, or the suite fails on its own helper —
> which is a five-second fix but an alarming first run.

#### Step 3.2: Generate the material variants in Studio and record them

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-materials.test.luau`

Studio work through `generate_material`, one call per row, then the ID recorded back into the registry.
The step is gated on **the registry being complete and consistent**, which is the part that can be
checked; whether the mud looks like mud is Step 4.5's job.

The manifest from Step 1.5 drives this. The shape of each call, per the asset-pipeline skill —
`Regular` for man-made surfaces, `Organic` for natural ones:

```
generate_material({
  materialPattern: "Organic",
  materialId: "BarrioMud",
  baseMaterial: "Mud",
  materialDescription: "wet packed dirt path, tyre ruts, dark and uneven"
})
```

Every row lands in the registry as it is generated:

```diff
 	Materials = {
-		-- filled in by Step 3.2, one row per generated variant
-		-- { Id = "BarrioNipa", Variant = "BarrioNipa", Base = "Grass", Pattern = "Organic" },
+		{ Id = "BarrioMud", Variant = "BarrioMud", Base = "Mud", Pattern = "Organic" },
+		{ Id = "BarrioNipa", Variant = "BarrioNipa", Base = "Grass", Pattern = "Organic" },
+		{ Id = "BarrioSawali", Variant = "BarrioSawali", Base = "WoodPlanks", Pattern = "Regular" },
+		{ Id = "BarrioBamboo", Variant = "BarrioBamboo", Base = "Wood", Pattern = "Organic" },
+		{ Id = "BarrioCourtSlab", Variant = "BarrioCourtSlab", Base = "Concrete", Pattern = "Regular" },
+		{ Id = "BarrioHollowBlock", Variant = "BarrioHollowBlock", Base = "Concrete", Pattern = "Regular" },
+		{ Id = "BarrioGIRoof", Variant = "BarrioGIRoof", Base = "CorrodedMetal", Pattern = "Regular" },
+		{ Id = "BarrioTarp", Variant = "BarrioTarp", Base = "Fabric", Pattern = "Regular" },
+		{ Id = "BarrioWetEarth", Variant = "BarrioWetEarth", Base = "Ground", Pattern = "Organic" },
+		{ Id = "BarrioPaddy", Variant = "BarrioPaddy", Base = "Grass", Pattern = "Organic" },
+		{ Id = "BarrioWhitewash", Variant = "BarrioWhitewash", Base = "Concrete", Pattern = "Regular" },
+		{ Id = "BarrioRustedSteel", Variant = "BarrioRustedSteel", Base = "CorrodedMetal", Pattern = "Regular" },
 	},
```

> **IMPORTANT — the twelve rows above are the *planned* set, not a result.** `generate_material` returns
> the actual `BaseMaterial` and variant `Name` it produced, and it is not obliged to return the one
> requested. **Record what comes back, not what is written here.** A row whose `Base` disagrees with the
> generated variant is precisely the silent-nothing case.
>
> **QUESTION — I have not confirmed that `generate_material` accepts every `baseMaterial` named above.**
> `Mud`, `Ground`, `CorrodedMetal` and `Fabric` are all real `Enum.Material` values, but the tool's
> accepted set is documented only as "a BaseMaterial". If one is rejected, fall back to the nearest
> accepted base and record it — the registry is the thing that must stay true.

#### Step 3.3: Apply materials across ground, roads, perimeter and the palette defaults

**File:** `tools/greybox/barrio.luau`

**No `**Verify:**` line.** The old one was `npm run verify`, and it passed against an untouched tree —
a whole-tree gate is regression protection, not proof that this step painted anything. The mechanical
half of this step (registry well-formed, no half-applied pair) is already gated at 3.2; what is left is
*"does the ground read as wet earth"*, which is an eye. Reported as `unverifiable`, which is accurate.

The five largest surfaces in the map, and the cheapest possible win: `Ground`, the four `Perimeter`
walls, the eighteen `Roads` parts, and the `building()` helper's floor and roof defaults, which alone
reach all seven kubo and the chapel.

```diff
 	local floor = box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
 	local roof = box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)
 
-	-- Nipa thatch has no Roblox material. `Grass` at the THATCH colour is the closest read: it is the
-	-- only stock material with a fibrous, directionless grain, and a roof is seen from below and at
-	-- distance where the grain is all that survives.
-	floor.Material = Enum.Material.WoodPlanks
-	roof.Material = Enum.Material.Grass
+	--[[
+		Nipa thatch has no stock Roblox material, and C17's note that `Grass` is "the closest read" was
+		true only while nothing better existed. `BarrioNipa` is generated against `Grass` precisely so
+		it keeps that fibrous directionless grain — which is all that survives at distance and in fog —
+		while gaining the layered, greyed shingling a real nipa roof has after one wet season.
+	]]
+	paint(floor, "BarrioBamboo")
+	paint(roof, "BarrioNipa")
```

> **This one edit re-materials sixteen roof and floor parts across all seven kubo and the chapel**,
> because every one of them is built through `building()`. Prefer edits at the helper level over
> per-part edits wherever the helper exists — it is fewer lines, it cannot miss one, and it keeps the
> per-zone phases short.

**`npm run verify` is the right gate here rather than a targeted suite**, because this step edits a
helper that every later phase depends on: the whole tree — all five new barrio suites plus the 34
existing ones — is the thing that must still be green.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none. A material is a property of an anchored part, identical on every client.
- **Remote direction** / **Rate limiting** — nothing touched.
- **Magic numbers** — `check:config` does not scan `tools/`. Material names are not balance values.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — not applicable; Edit-mode build step.
- **Strict Luau** — `(Enum.Material :: any)[entry.Base]` is an unavoidable cast: indexing `Enum.Material`
  by a runtime string has no typed form. It is contained to one line in the registry loader.
- **Mobile budget** — **zero cost.** No parts, no lights, no triangles added. This is the phase to spend
  effort on precisely because it is free against every metered budget.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **MaterialVariants live in the place file, not in git.** If the place is rolled back to a version
  before Phase 3, every `paint()` call warns and every part falls back to its base material — the map
  degrades to roughly its current look rather than breaking. That is a deliberately soft failure, and
  the warning names the missing variant so it can be regenerated from the registry's `Pattern`.
- **`MaterialVariant` requires the part's `Material` to match the variant's `BaseMaterial` exactly.**
  Changing a part's `Material` *after* `paint()` silently unbinds the variant. Always `paint()` last.
- **Twelve variants is a guess at the right number.** Too few and surfaces read identically; too many
  and they stop reading as one village. Step 4.5's approval gate is where that judgement gets made,
  which is another reason the hero zone comes before the remaining zones.

---

### Phase 4: The hero zone — plaza, court, benches, one kubo — and the approval gate

The explicit user-approval gate. Everything after this phase reuses the treatment approved here.

**This phase exists to be rejected cheaply.** Everything after it copies the treatment approved here, so
the cost of being wrong about the look is one zone rather than seventeen. Nothing in Phases 5–8 should
begin before Step 4.5 returns a yes.

**What "hero zone" means concretely:** `Dressing.PlazaDressing` (100 parts — court, 4 benches, 4
banderitas runs, flagpole) plus `Kubo_NW` (6–7 parts) plus the plaza ground and roads underneath them.

#### Step 4.1: Rebuild the basketball court

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-budget.test.luau`

The barangay court is the single most characteristic feature of a Philippine barrio and the current one
is **three painted stripes and two rectangles** — a slab, `Court_LineN/S/Mid`, and a pole/board/rim per
end. Research doc 02 drives the rebuild; the changes that matter most are proportion and decay, not
detail.

```diff
-prop(
-	"Court_Slab",
-	COURT_X,
-	0.12,
-	COURT_Z,
-	30 * SCALE,
-	0.14,
-	18 * SCALE,
-	Color3.fromRGB(92, 84, 76),
-	Enum.Material.Concrete,
-	plaza
-)
+--[[
+	THE SLAB. Widened to the real proportion — see research-02: barangay courts are laid out to
+	roughly the FIBA 28x15m ratio even when they are undersized, and the greybox's 30x18 is squarer
+	than any real one. A court that reads WRONG reads as a car park.
+
+	Painted concrete, not bare: a barangay court is repainted for every fiesta and cracks between
+	them, which is why the slab is a green/blue-grey rather than the cement colour it was.
+]]
+paint(
+	prop(
+		"Court_Slab",
+		COURT_X,
+		0.12,
+		COURT_Z,
+		30 * SCALE,
+		0.14,
+		16 * SCALE,
+		Color3.fromRGB(78, 96, 92),
+		Enum.Material.Concrete,
+		plaza
+	),
+	"BarrioCourtSlab"
+)
+
+--[[
+	THE CRACKS. Six thin dark slivers across the slab, seeded from the existing `rng` so two runs
+	produce the same barrio — the same reason the rice field uses it.
+
+	This is the highest realism-per-part item in the phase: a perfectly flat, perfectly clean slab is
+	the single strongest "this is a greybox" signal in the plaza, and six parts fix it.
+]]
+for index = 1, 6 do
+	turn(
+		prop(
+			`Court_Crack{index}`,
+			COURT_X + rng:NextNumber(-13, 13),
+			0.19,
+			COURT_Z + rng:NextNumber(-7, 7),
+			rng:NextNumber(4, 11),
+			0.04,
+			0.25,
+			Color3.fromRGB(44, 48, 46),
+			Enum.Material.Slate,
+			plaza
+		),
+		rng:NextNumber(0, 180)
+	)
+end
```

The hoop is where the barrio reads as a barrio rather than as a gym:

```diff
 	prop(`Hoop{index}_Pole`, x, 5, COURT_Z, 0.9, 10, 0.9, TIN, Enum.Material.CorrodedMetal, plaza)
 	prop(
 		`Hoop{index}_Board`,
 		x - side * 1.6,
 		10.5,
 		COURT_Z,
 		0.4,
 		3.5,
 		5,
 		Color3.fromRGB(186, 182, 170),
 		Enum.Material.WoodPlanks,
 		plaza
 	)
-	prop(
-		`Hoop{index}_Rim`,
-		x - side * 3,
-		9.2,
-		COURT_Z,
-		2.6,
-		0.3,
-		2.6,
-		Color3.fromRGB(196, 96, 48),
-		Enum.Material.CorrodedMetal,
-		plaza
-	)
+	--[[
+		THE BENT, NETLESS RIM — research-02's most repeated observation about real barangay hoops, and
+		a two-line change. `lean` tips it forward a few degrees, which is what a decade of people
+		hanging off it does. No net: nets are consumable and nobody replaces them.
+	]]
+	lean(
+		prop(
+			`Hoop{index}_Rim`,
+			x - side * 3,
+			9.2,
+			COURT_Z,
+			2.6,
+			0.25,
+			2.6,
+			Color3.fromRGB(176, 84, 44),
+			Enum.Material.CorrodedMetal,
+			plaza
+		),
+		if index == 1 then -7 else -4,
+		true
+	)
+
+	-- Plywood backboards warp and delaminate; two braces behind each is what holds them on the pole.
+	for brace = -1, 1, 2 do
+		turn(
+			prop(
+				`Hoop{index}_Brace{if brace < 0 then "L" else "R"}`,
+				x - side * 0.8,
+				9.6,
+				COURT_Z + brace * 1.6,
+				0.25,
+				0.25,
+				2.4,
+				TIN,
+				Enum.Material.CorrodedMetal,
+				plaza
+			),
+			brace * 24
+		)
+	end
```

> **IMPORTANT — the covered multipurpose hall is deliberately NOT built.** Research-02 will show most
> barangay courts are roofed, and a roof over the plaza is the most authentic single addition
> available. It is refused on three counts and this is the place to record why, so nobody re-adds it in
> Phase 6: it would need **collidable** support posts (C30 rule 1, asserted), it would want a light
> underneath (rule 2, asserted), and a roof over the spawn plaza destroys the sightline the plaza
> exists to provide — §5's *"you should almost always be able to see something"* is measured from here.
> Raised in Follow Ups as a deliberate realism sacrifice rather than an oversight.

#### Step 4.2: Rebuild the benches, the flagpole and the banderitas

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-plaza.test.luau`

> **The grep this step originally carried could not pass, and that is worth recording.** It was
> `grep -c Bench1_Back`, and the loop writes `Bench{index}_Back` — an interpolated name the literal can
> never match. The check the plan itself labelled "the grep trap" failed in precisely the way it warned
> about: not by proving too little, but by being unable to see the thing it was pointed at.
>
> It is now gated on `tests/barrio-budget.test.luau`, which asserts the authored structures this step
> delivers — the back rail, the faded palette, the uneven run heights, the paper triangles. That is
> still structure rather than beauty: whether it LOOKS right is Step 4.5's screenshot, and no command
> substitutes for it.

Current benches are three boxes: a plank seat on two concrete legs, no back. Research-02's barrio bench
is a concrete-legged, wood-slatted seat **with a back**, or a bamboo bench under a tree.

```diff
 for index, at in { { -30, 30 }, { 30, 24 }, { 26, -34 }, { -18, -30 } } do
 	prop(`Bench{index}_Seat`, at[1], 2.2, at[2], 7, 0.5, 2, WOOD, Enum.Material.WoodPlanks, plaza)
+	-- The back is what makes a bench read as a bench in silhouette, which is the only way it is read
+	-- at night. Leaned back 12 degrees so it is not a wall.
+	lean(
+		prop(`Bench{index}_Back`, at[1], 3.3, at[2] - 0.8, 7, 2, 0.35, WOOD, Enum.Material.WoodPlanks, plaza),
+		12
+	)
```

The banderitas are already the best thing in the plaza — a `droop` of twelve neon bulbs per run,
costing no light slot. Research-02 will confirm real banderitas are **cut plastic or paper triangles**,
not bulbs. The cheapest correction is to keep the bulbs and add triangles between them:

```diff
 			bulb.Material = Enum.Material.Neon
 			bulb.Color = if index % 2 == 0 then WARM else Color3.fromRGB(255, 168, 132)
 			bulb.Parent = plaza
+
+			-- A paper triangle hung beside each bulb. Non-emissive, so it reads as a silhouette
+			-- against the bulb it hangs next to — which is exactly how banderitas read at night.
+			local flag = prop(
+				`{name}_Flag`,
+				0,
+				0,
+				0,
+				0.9,
+				1.1,
+				0.05,
+				FIESTA_COLOURS[(index - 1) % #FIESTA_COLOURS + 1],
+				Enum.Material.SmoothPlastic,
+				plaza
+			)
+
+			flag.CFrame = CFrame.new(at - Vector3.new(0, 1.1, 0))
```

> **`FIESTA_COLOURS` must be declared alongside the other palette constants** (near line 847, with
> `BAMBOO`/`LEAF`/`RUST`/`TIN`/`TARP`/`WARM`) rather than inside the loop.
>
> **IMPORTANT — use the FADED palette, not the fresh one.** Research-02 is unusually well sourced here
> and it contradicts the obvious choice: banderitas are hung **weeks before** a fiesta and left up
> **for months or a year**, so their default state in a barrio is faded and partly torn. The source
> describes the fade sequence verbatim — *"the vibrant, screaming reds break into a **bruised, muted
> pink**. The sharp yellows fade into a **sickly cream**, and the deep blues turn into **ghostly,
> translucent gray**."* That palette fits the existing muted map colours and a horror night far better
> than fresh primaries would. Mix in one or two fresh flags to read as recently patched.
>
> **Also from research-02: anchor the runs at UNEVEN heights to opportunistic points.** Real banderitas
> are tied to *"a sloping telephone pole"*, a *"rusty second-storey grill"*, a mango tree, a shop
> awning. The current symmetrical square between four lantern tops is too tidy. The `droop` helper
> already takes per-end heights, so this is a data change, not new code.
>
> **NOTE — this adds 40 parts** (4 runs × 10 nodes). Counted against the ≤1,250 ceiling in Step 4.4,
> and Phase 7 must give some of it back from `Planting`.

#### Step 4.3: Rebuild `Kubo_NW` as a real bahay kubo

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-contract.test.luau`

The template every other kubo copies in Phase 7. The contract suite is the right gate because
`Container_KuboNW_Chest` sits **inside** this house — a rebuild that moves a wall into the container's
anchor, or a floor above it, breaks searching in a way no screenshot of the exterior would show.

The `building()` helper currently produces a box with a flat roof slab sitting on the ground. Research-01
gives four changes, in descending order of how much they matter at night:

1. **Stilts and the silong.** A bahay kubo stands on posts with an open undercroft. This is the entire
   silhouette difference and it is also a *gameplay* difference — a raised floor with an open underside
   is a place to hide and a place to see feet from.
2. **Roof pitch.** The current roof is a 1-stud slab. A nipa roof is steeply pitched to shed monsoon
   rain; research-01 gives the angle and why.
3. **Sawali walls.** Woven bamboo, not planks — `BarrioSawali` from Phase 3.
4. **Proportion.** Real footprints are small; the greybox's are generous.

```diff
 	local floor = box(`{name}_Floor`, cx, 0.15, cz, w, 0.3, d, WOOD, folder)
 	local roof = box(`{name}_Roof`, cx, height + 0.5, cz, w + 4, 1, d + 4, THATCH, folder)
+
+	--[[
+		THE STILTS AND THE SILONG — the bahay kubo's whole silhouette, in four parts.
+
+		A house on posts with an open undercroft reads instantly as Filipino and reads at DISTANCE,
+		which is the only way it is read in fog. See research-01 for the real post height.
+
+		THE POSTS ARE NOT COLLIDABLE. `prop()` guarantees that. A collidable post inside a doorway
+		would move the navmesh and break the crossing time — C30 rule 1, asserted at the foot of this
+		file. The house's WALLS still collide, so the building is still a building.
+	]]
+	local STILT = 3.2
+
+	for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
+		paint(
+			prop(
+				`{name}_Stilt{corner[1]}{corner[2]}`,
+				cx + corner[1] * (w / 2 - 1) / SCALE,
+				STILT / 2,
+				cz + corner[2] * (d / 2 - 1) / SCALE,
+				0.7,
+				STILT,
+				0.7,
+				BAMBOO,
+				Enum.Material.Wood,
+				folder
+			),
+			"BarrioBamboo"
+		)
+	end
```

> **IMPORTANT — raising the floor changes where a player stands, and that is a layout change.** §5's
> crossing time is measured over the navmesh; a floor at +3.2 studs with collidable walls around it
> makes the interior unreachable unless a ramp or step exists. **Either keep the floor at ground level
> and let the stilts read as decoration around a ground-level interior, or add a non-collidable visual
> stair and keep the collidable floor where it is.** The first is strongly preferred: it is free, it is
> invisible at night, and it cannot move the number Step 4.4 measures. Decide this explicitly and
> record the decision in the implementation log — it is the one place in this plan where realism and
> the layout rule genuinely conflict.

#### Step 4.4: Run the builder, re-measure, and record the numbers

**File:** `tools/greybox/measure.luau`
**Verify:** `test -f .claude/plans/feature-barrio-realism-plan/artifacts/hero-zone.md`

> **The old check here was `npm run verify`, and it passed against a completely untouched tree.** A
> whole-tree gate cannot fail because *this* step did nothing — it fails only if the step broke
> something else. The deliverable of 4.4 is **four recorded numbers**, so the check is that the file
> holding them exists. That is a weak claim honestly scoped: it proves the measurement was written
> down, not that it was taken correctly. Reading whether the crossing time actually sits in the 30–40s
> band is Step 4.5's job, and 4.5 is the human gate.

Run `barrio.luau` in **Edit mode**, then `measure.luau`, then record four numbers into
`artifacts/hero-zone.md`:

| Number | Source | Pass condition |
| --- | --- | --- |
| Crossing time, seconds | `measure.luau` | within the 30–40s band; **compare to the pre-phase reading, not to 35** |
| Total `Barrio` instances | the builder's own receipt | ≤ 1,250 |
| Dressing colliders / lights | the builder's asserts | 0 / 0, or the build failed |
| FPS on a real phone | `PerformanceController`'s readout with `Debug.VerboseLogging` | ≥ 30 |

> **The FPS readout needs `Config.Debug.VerboseLogging = true`, which is a debug value `check:debug`
> refuses to let anyone commit.** Set it, read it, revert it, and confirm with
> `git diff src/shared/Config.luau` before the phase closes.
>
> **`measure.luau` must be re-run after `barrio.luau`, every time.** It reads the live DataModel, so a
> reading taken before the rebuild describes the previous barrio and looks exactly like a passing one.

#### Step 4.5: The approval gate — screenshots and a human decision

**File:** `.claude/plans/feature-barrio-realism-plan/artifacts/hero-zone.md`

**No `**Verify:**` line, deliberately.** This step is a person looking at a picture and saying yes or
no, and there is no command that can stand in for that. `verify-plan.mjs` will report it as
`unverifiable` and `next-phase.mjs` will mark the phase `needs-human`, which is the accurate outcome —
inventing a check here would convert the single most important decision in the plan into a green tick.

Capture, via the `playtester` agent driving Studio, at minimum:

- the plaza and court from a player's eye height, at night, from the spawn pad
- the same view from across the plaza, at the fog boundary, to test whether the court still reads
- `Kubo_NW` in silhouette from ~40 studs, which is how it will actually be seen
- one interior shot showing `Container_KuboNW_Chest` — §5 demands containers be obvious *on a phone, in
  the dark*, and this is the shot that tests it

**The three questions the user is being asked**, which belong in `hero-zone.md` explicitly:

1. Does this read as a Philippine barrio, or as a generic village?
2. Is the material density right — do twelve variants make one village, or a patchwork?
3. Is the container obvious enough at a glance, in the dark, on a phone?

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none. No per-player state; the plaza is identical on every client.
- **Remote direction** / **Rate limiting** — nothing touched.
- **Magic numbers** — `check:config` does not scan `tools/`; court dimensions are place geometry.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — not applicable.
- **Strict Luau** — `analyze` does not cover `tools/`. Run the builder; Studio is the only typechecker
  this file has.
- **Mobile budget** — **this is the phase that spends the most.** +6 cracks, +4 bench backs, +8 hoop
  braces, +16 stilts, +40 banderitas triangles ≈ **+74 parts**. That lands near 1,186 against the
  ≤1,250 ceiling and leaves Phases 5–7 almost nothing, which is why Phase 7 reduces `Planting`.
  **Re-read the receipt at 4.4 and treat the number as binding, not advisory.**
- **Scope** — nothing from §3's OUT list. The covered court is refused above on budget and sightline
  grounds, not scope grounds.

**Issues identified:**

- **The stilt/floor-height conflict is real and unresolved in this document by design.** It is the one
  place where §5's layout rule and research-01's silhouette pull against each other. The recommended
  resolution (decorative stilts, floor stays at ground level) is written into Step 4.3, but it is a
  judgement the implementer must make consciously and log.
- **+74 parts in one phase is the plan's largest single budget movement.** If 4.4's receipt exceeds
  1,250, the correct response is to cut the banderitas triangles first — they are 40 of the 74 and the
  bulbs already carry that read.
- **The court's widened proportion (18 → 16 studs deep) moves painted geometry but not collision.**
  `Court_Slab` is a non-collidable `prop`, so the navmesh cannot notice. Confirmed by construction, but
  worth re-reading the 4.4 crossing time anyway — it is the cheap check that catches a mistyped
  `CanCollide`.

---

### Phase 5: The eight hero meshes

**Eight meshes, and not a ninth.** The user's decision was ~8 hero props with materials and geometry
carrying everything else. That ratio is also what the budget allows: eight meshes at the skill's
ceilings is ~27,000 triangles, and meshes are the only item in this plan that costs triangles at all.

**Every mesh must REPLACE box props, not join them.** A generated tricycle standing next to the six
boxes it was meant to replace is six wasted parts and a doubled silhouette. Step 5.3 deletes as it
places, and the budget test checks the net.

---

#### The mechanism, decided empirically — `MeshPart.MeshId` is NOT script-writable

This was an open question in the first draft of this plan and it has now been probed against the live
Studio in Edit mode, which is the exact context the builder runs in:

```
A. Instance.new("MeshPart").MeshId = "rbxassetid://1"
   -> ok=false  err="The current thread cannot write 'MeshId' (lacking capability NotAccessible)"
   -> value after the attempted set: ''  (unchanged)
B. typeof(AssetService.CreateMeshPartAsync) == "function"   -> true
C. Instance.new("SpecialMesh").MeshId = "rbxassetid://1"    -> ok=true   (writable)
D. typeof(InsertService.LoadAsset) == "function"            -> true
```

**A `mesh()` helper that assigns `MeshId` cannot work and the previous draft of this phase was wrong.**
Worse than wrong, it was *quietly* wrong: the assignment fails, `MeshId` stays `""`, and you get an
invisible zero-size part rather than an error — a build that reports success and silently omits eight
props.

**Chosen: `AssetService:CreateMeshPartAsync`.** It is the supported path, it returns a real `MeshPart`,
and — the deciding factor — **a `MeshPart` is the only one of the three options that can carry a
`MaterialVariant`.** Phase 3's material library is this plan's single largest realism lever, and a mesh
path that cannot take a variant would leave the eight hero props as the only surfaces in the barrio
excluded from it.

**Why `SpecialMesh` lost, and the honest half of that.** Probe C proves it works from any context with
no yield, and it is the fallback if `CreateMeshPartAsync` misbehaves. The usual argument against it —
collision fidelity — **does not apply here at all**, because every mesh in this plan is non-collidable
scenery. The real cost is narrower and it is the material one: `SpecialMesh` is a legacy render path
with `TextureId` rather than PBR, so it cannot bind a `MaterialVariant` or a `SurfaceAppearance`. That
is what loses it, not collision.

**Why template-clone lost.** It would put mesh geometry back into the place file, which is the exact
non-diffable property this entire builder architecture exists to avoid. It also has the worst failure
shape of the three: templates live *outside* `workspace.Barrio`, so the builder's destroy-and-rebuild
would not touch them, and a lost or rolled-back place file would leave the builder happily constructing
a barrio with **eight silent holes in it** and no error. Restoring them would mean re-running
`insert_asset` eight times from the registry by hand — a recovery procedure that exists only in a
document. Rejected.

**The yield is not a blocker, and this repo already proves it.** `CreateMeshPartAsync` yields, and the
builder's own documented run pattern *already* yields: `tools/greybox/README.md` has it fetching its own
source with `HttpService:GetAsync` inside `execute_luau`. Yielding in this execution context is
established practice here, not a new risk.

> **QUESTION — confirm the exact signature before writing Step 5.3.** I have seen
> `CreateMeshPartAsync(meshId, options)` with an options table carrying `CollisionFidelity` and
> `RenderFidelity`, but I have **not** verified the parameter shape in this Studio version, and Hard
> Rule 1 forbids guessing one. Probe it in Edit mode first. If the options table is rejected, call it
> with the id alone and set fidelity on the returned `MeshPart` afterwards.

---

#### Step 5.1: Extend the registry with the mesh schema and its budget test

**File:** `tests/barrio-assets.test.luau`
**Verify:** `test -f tests/barrio-assets.test.luau`

> **Existence only, and deliberately** — same reasoning as Steps 2.1 and 3.1. `Meshes = {}` at this
> point, so a suite asserting eight generated meshes is correctly red until Step 5.2. Writing the
> assertions now and watching them fail is the point; making them pass now would mean writing
> assertions that cannot fail.

Written before any mesh is generated, so the budget is a gate rather than a retrospective count.

**The registry also gains an `Observed` block per mesh — but its assertions live in
`tests/barrio-budget.test.luau`, not here.** `Observed` is a readback from Studio that does not exist
until Step 5.3 places the meshes, so asserting it in *this* suite would make Step 5.2 structurally
unpassable. Splitting them gives each step a check that is red before it and green after:

| Suite | Asserts | Gate for |
| --- | --- | --- |
| `barrio-assets` | eight rows, well-formed non-placeholder ids, declared triangle budget | **5.2** |
| `barrio-budget` | the `Observed` readback, and the net part count | **5.3** |

```diff
+--[[
+	The eight hero meshes, the triangle budget they are held to, and what actually landed.
+
+	60% of players are on mobile and §5's budget is non-negotiable. The asset-pipeline skill's rule is
+	blunt: "A 20,000-triangle house you cannot see through fog costs the same frame time as one you
+	can." So the ceiling is enforced here rather than trusted to whoever typed the maxTriangles.
+]]
+local PROP_MAX = 3000
+local HERO_MAX = 6000
+local MESH_COUNT = 8
+
+check(
+	`exactly {MESH_COUNT} hero meshes are registered`,
+	#assets.Meshes == MESH_COUNT,
+	`{#assets.Meshes} registered`
+)
+
+local heroes = 0
+local total = 0
+
+for _, mesh in assets.Meshes do
+	total += mesh.Tris
+
+	check(
+		`{mesh.Name} has a well-formed asset id`,
+		type(mesh.Asset) == "string" and string.match(mesh.Asset, "^rbxassetid://%d+$") ~= nil,
+		`got {tostring(mesh.Asset)}`
+	)
+
+	--[[
+		NO PLACEHOLDERS AT PHASE END. `rbxassetid://0` is the value a registry row carries before its
+		mesh has been generated, and it MATCHES the pattern above — so without this line a phase that
+		generated nothing at all would pass every id check.
+	]]
+	check(
+		`{mesh.Name} was actually generated`,
+		mesh.Asset ~= "rbxassetid://0",
+		"still the placeholder id"
+	)
+
+	if mesh.Tris > PROP_MAX then
+		heroes += 1
+
+		check(
+			`{mesh.Name} is within the hero ceiling`,
+			mesh.Tris <= HERO_MAX,
+			`{mesh.Tris} triangles, ceiling {HERO_MAX}`
+		)
+	end
+
+end
+
+-- The skill allows ONE hero above the prop ceiling ("up to 6,000 for a hero object like the chapel").
+check(`at most one mesh exceeds the prop ceiling`, heroes <= 1, `{heroes} do`)
+check(`the total added triangle budget holds`, total <= 27000, `{total} triangles`)
```

#### Step 5.2: Generate the eight meshes and record their asset IDs

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-assets.test.luau`

The shortlist from Step 1.6, in `references/hero-mesh-shortlist.md`, which carries the full prompt,
size and budget for each. Prompt **for the silhouette, not the detail** — the skill is explicit that
darkness and fog erase surface detail and keep outline.

| # | Mesh | Replaces | Size (studs) | maxTriangles |
| --- | --- | --- | --- | --- |
| 1 | Chapel — the one hero | `Chapel` walls + steeple, ~6 parts | 24 × 22 × 30 | **6000** |
| 2 | Tricycle (motorcycle + sidecar) | `Tricycle1/2`, ~6 parts each | 6 × 5 × 9 | 3000 |
| 3 | Sari-sari stall front | `Stall_*` counter/roof/tarp, ~7 parts | 12 × 10 × 8 | 2500 |
| 4 | Bahay kubo shell | dressing only — see the warning below | 20 × 16 × 20 | 3000 |
| 5 | Well head and pump | `Well` ring + `Well_Pump`, ~10 parts | 8 × 7 × 8 | 2000 |
| 6 | Banana plant | 12 trunks + 48 leaves — **60 parts** | 7 × 12 × 7 | 1500 |
| 7 | Grave marker | `GraveN_H` + `GraveN_V`, 16 parts | 2 × 4 × 1.5 | 1500 |
| 8 | Scarecrow | 2 scarecrows, ~4 parts each | 3 × 8 × 3 | 1500 |

Total: **21,500** triangles, inside the 27,000 ceiling with room for one regeneration coming back
heavier than asked.

```diff
 	-- Meshes. Filled in by Phase 5. `Tris` is the maxTriangles the mesh was generated at.
-	Meshes = {},
+	Meshes = {
+		{ Name = "Chapel", Asset = "rbxassetid://0", Tris = 6000, Replaces = "Chapel walls + steeple" },
+		{ Name = "Tricycle", Asset = "rbxassetid://0", Tris = 3000, Replaces = "Tricycle1/2" },
+		{ Name = "SariSari", Asset = "rbxassetid://0", Tris = 2500, Replaces = "Stall_* counter/roof" },
+		{ Name = "Kubo", Asset = "rbxassetid://0", Tris = 3000, Replaces = "kubo dressing only" },
+		{ Name = "Well", Asset = "rbxassetid://0", Tris = 2000, Replaces = "Well ring + pump" },
+		{ Name = "Banana", Asset = "rbxassetid://0", Tris = 1500, Replaces = "banana trunk + leaves" },
+		{ Name = "Grave", Asset = "rbxassetid://0", Tris = 1500, Replaces = "GraveN_H + GraveN_V" },
+		{ Name = "Scarecrow", Asset = "rbxassetid://0", Tris = 1500, Replaces = "scarecrow parts" },
+	},
```

> **IMPORTANT — the registry is now the ONLY durable record of this phase's output.** `generate_mesh`
> uploads an asset and hands back an id; the mesh itself lives on Roblox's servers and the place file
> holds nothing but a reference. `git log` will not have the id, the `.rbxl` is gitignored, and a
> moderated-away asset leaves a hole with no name on it. **Record each id the moment it is generated,
> not at the end of the phase.**
>
> **IMPORTANT — mesh #4 must not replace the kubo's collidable walls.** The `building()` walls are what
> PathfindingService reads. Swapping a collidable box wall for a mesh changes collision geometry and
> moves the crossing time. This one is scenery layered over a structure that stays exactly as it is.

#### Step 5.3: Place the meshes through `CreateMeshPartAsync` and delete the boxes they replace

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-budget.test.luau`

```diff
+--[[
+	A hero mesh, placed exactly like a prop and constrained exactly like one.
+
+	`MeshPart.MeshId` IS NOT SCRIPT-WRITABLE — probed in Edit mode, which is the context this file runs
+	in: assigning it fails with "cannot write 'MeshId' (lacking capability NotAccessible)" and the
+	property stays "". That failure is SILENT in the shape that matters — you get an invisible
+	zero-size part, not an error — so the whole barrio would build and simply omit eight props.
+	`AssetService:CreateMeshPartAsync` is the supported path and returns a real MeshPart, which is also
+	the only form that can carry a MaterialVariant from the ASSETS registry.
+
+	IT YIELDS, AND THAT IS FINE HERE. This file already runs in a yielding context — the README's
+	HTTP-serve pattern fetches this very script with HttpService:GetAsync inside execute_luau.
+
+	NON-COLLIDABLE, WITHOUT EXCEPTION. C30 rule 1 is asserted at the foot of this file and a mesh is
+	the easiest way to break it: it defaults to a mesh collision hull, which the navmesh reads and the
+	crossing time answers for. Everything visual in this barrio is scenery.
+
+	pcall'd, warned and SKIPPED rather than fatal, on the pattern this file already uses twice for
+	Lighting.Technology and the streaming radii: attempt it, survive the refusal, and say what a human
+	has to do. A missing mesh should cost one prop, not the whole barrio.
+]]
+type MeshEntry = { Name: string, Asset: string, Tris: number, Replaces: string }
+
+local function meshEntry(assetName: string): MeshEntry?
+	for _, candidate in ASSETS.Meshes do
+		if candidate.Name == assetName then
+			return candidate
+		end
+	end
+
+	return nil
+end
+
+local function mesh(
+	name: string,
+	assetName: string,
+	cx: number,
+	cy: number,
+	cz: number,
+	parent: Instance?
+): MeshPart?
+	local entry = meshEntry(assetName)
+
+	if entry == nil or entry.Asset == "rbxassetid://0" then
+		warn(`[barrio] mesh "{assetName}" is not in the ASSETS registry or was never generated — skipped.`)
+
+		return nil
+	end
+
+	local ok, result = pcall(function()
+		return AssetService:CreateMeshPartAsync(entry.Asset)
+	end)
+
+	if not ok or result == nil then
+		warn(`[barrio] CreateMeshPartAsync failed for {assetName} ({result}) — {name} skipped.`)
+
+		return nil
+	end
+
+	local p = result :: MeshPart
+
+	p.Name = name
+	p.Anchored = true
+	p.CanCollide = false
+	p.CanQuery = false
+	p.CanTouch = false
+	p.CastShadow = false
+	p.Position = v(cx, cy, cz)
+	p.Parent = parent or dress
+
+	return p
+end
```

> **`AssetService` must be added to the service block at the top of the file**, alongside
> `CollectionService` and `Lighting`. It is not required today.
>
> **QUESTION — confirm the signature first.** The call above passes the id alone, which is the
> conservative form. If this version accepts an options table, prefer
> `{ CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Performance }`
> — box collision because these are non-collidable anyway, and performance fidelity because §5's budget
> is a mobile one. **Probe before writing, do not assume the shape.**

**Then record the readback.** For each placed mesh, in Edit mode via `execute_luau`, read the instance
class, its triangle count and its full parent path, and paste them into the registry:

```diff
-		{ Name = "Grave", Asset = "rbxassetid://0", Tris = 1500, Replaces = "GraveN_H + GraveN_V" },
+		{
+			Name = "Grave",
+			Asset = "rbxassetid://1234567890",
+			Tris = 1500,
+			Replaces = "GraveN_H + GraveN_V",
+			Observed = { Class = "MeshPart", Tris = 1412, Parent = "Barrio.Dressing.Details" },
+		},
```

> The assertions that make the readback binding go into `tests/barrio-budget.test.luau`:

```diff
+for _, mesh in assets.Meshes do
+	check(`{mesh.Name} was observed in Studio`, mesh.Observed ~= nil, "no readback recorded")
+
+	if mesh.Observed then
+		check(
+			`{mesh.Name} landed as a MeshPart`,
+			mesh.Observed.Class == "MeshPart",
+			`observed {tostring(mesh.Observed.Class)} — the SpecialMesh fallback cannot take a MaterialVariant`
+		)
+		check(
+			`{mesh.Name} did not come back heavier than requested`,
+			mesh.Observed.Tris <= mesh.Tris,
+			`asked for {mesh.Tris}, got {mesh.Observed.Tris}`
+		)
+		check(
+			`{mesh.Name} is parented inside Dressing so the collider audit walks it`,
+			string.match(mesh.Observed.Parent, "^Barrio%.Dressing") ~= nil,
+			`parented at {mesh.Observed.Parent}`
+		)
+	end
+end
```

**This is the strongest verification available anywhere in this plan, and it is worth saying why.**
> Most steps here are visual and end at a screenshot. This one does not: `Observed.Class` catches a
> silent fall back to `SpecialMesh`, `Observed.Tris` catches a generator that returned heavier
> geometry than requested, and `Observed.Parent` catches a mesh parented to the workspace root where
> the builder's `dressColliders`/`dressLights` audit would never walk it. All three are read from the
> live DataModel and all three fail the tree if they disagree with the plan.

**Finally, delete the box props each mesh replaces**, in the same step. The `Replaces` column is the
deletion list. A mesh that joins its boxes rather than replacing them spends parts twice and doubles
the silhouette — and the budget suite is what notices.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none. Meshes are anchored scenery, identical on every client.
- **Remote direction** / **Rate limiting** / **Phase ownership** — nothing touched.
- **Magic numbers** — triangle ceilings live in the test, which is where they are enforced.
- **Player leaving mid-round** — not applicable; Edit-mode build step.
- **Strict Luau** — `analyze` does not cover `tools/`. The `MeshEntry` type and the `result :: MeshPart`
  cast are both deliberate: `pcall` returns `(boolean, any)`, so without the cast every property
  assignment below it is unchecked.
- **Mobile budget** — the phase that spends the triangle budget, and the only one that does. It should
  **reduce** part count: eight meshes replacing ~45 box props is a net **−37**, which is how Phase 4's
  +74 is partly paid back. Mesh #6 alone removes 60 planting parts.
- **Scope** — §3 lists *"custom monster mesh"* as OUT. **None of these eight is a character, a monster
  or an item.** They are map scenery, which §5 explicitly invites. Worth stating because `check:scope`
  does not scan `tools/` and cannot arbitrate it.

**Issues identified:**

- **The `MeshId` question is CLOSED and the answer changed the phase.** It is not script-writable, from
  any thread, in Edit mode. The previous draft's helper would have produced eight invisible zero-size
  parts and a build that reported success. This is the exact failure Hard Rule 1 exists to prevent, and
  it was only caught because the question was raised rather than guessed.
- **The `CreateMeshPartAsync` signature is still unconfirmed** and is the one remaining guess in this
  phase. Probe it before writing Step 5.3.
- **If `CreateMeshPartAsync` proves unusable, the fallback is `Part` + `SpecialMesh`** (probe C: both
  `MeshId` and `TextureId` writable, no yield, works from any context). **Take it knowingly, not
  silently** — those props leave Phase 3's material library, and `Observed.Class` is what forces the
  decision into a diff.
- **A moderated-away generated asset leaves a hole with no name on it.** The `Replaces` column is the
  mitigation: it records what used to be there, so a missing mesh can be reverted to boxes.
- **`generate_mesh` returns what it returns.** If a mesh comes back visibly worse than asked,
  regenerate rather than raise the ceiling. `Observed.Tris` catches the number; nothing catches the
  look except Step 4.5's eye.

---

### Phase 6: Remaining zones A — chapel, well, stalls, arko

Applies the approved treatment to the civic buildings. **Do not start this phase before Step 4.5 returns
a yes** — every step here is a copy of a decision made there.

#### Step 6.1: The chapel, its steeple and its candle glow

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-contract.test.luau`

The chapel carries **two** `SearchContainer` anchors and one of the fourteen `MapLight`s
(`Chapel_Candles`), which is why the contract suite is the gate: this is the building where a careless
rebuild breaks both the search pool and the light budget at once.

Research-03 gives the corrections: a barangay visita is **hollow-block concrete, painted, under a
corrugated GI roof** — not the stone-and-thatch the greybox implies. So the changes are mostly `paint()`
calls, which is the cheapest possible outcome:

```diff
+paint(chapelWall, "BarrioWhitewash")
+paint(chapelRoof, "BarrioGIRoof")
```

> **IMPORTANT — `Chapel_Candles` keeps its `MapLight` tag and its position, untouched.** §5's "strong
> lighting moment" is this light, `PerformanceController` reserves slots against
> `Config.Performance.MaxVisibleLights = 8`, and the builder asserts `mapLights == totalLights`. Adding
> a second chapel light to "improve" the interior breaks the assertion and the build fails — which is
> the guard working. If the interior genuinely needs more light, the answer is emissive `Neon` geometry
> costing no light slot, exactly as the banderitas do.

#### Step 6.2: The four sari-sari stalls

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-civic.test.luau`

> **The grep this step carried could not pass — the third time in this plan.** It was
> `grep -c Stall_NW_Grille`, and the loop writes `{stall.Name}_Grille{bar}`. Step 4.2 had the identical
> defect with `Bench1_Back` against `Bench{index}_Back`. A literal cannot match an interpolation, so
> both checks failed at the thing they were pointed at rather than at the thing they guarded: anything
> built in a loop needs a reader that understands the loop.
>
> Now gated on `tests/barrio-civic.test.luau`. Whether it READS as a sari-sari store is still a
> screenshot question and no command replaces it.

Each stall is 10 parts — counter, 4 legs, roof, tarp, 3 goods heaps — and each now also carries a
`SearchContainer`. Research-03's sari-sari store is one of the most recognisable objects in the whole
map and the greybox has none of its three signatures:

1. **The barred window.** The grille is *the* silhouette of a sari-sari store, and it is 4 thin parts.
2. **The tarpaulin sign**, with sponsor branding. **No image generation exists in this toolchain** — the
   asset-pipeline skill is explicit. So the sign is a coloured `BarrioTarp` panel reading as a tarp in
   silhouette, and lettering is out of reach. Recorded in Follow Ups rather than faked.
3. **Hanging sachet strips.** `droop` already exists and does this for free.

```diff
+	-- The grille. Four bars across the counter opening, and the entire reason a sari-sari store is
+	-- recognisable at a distance in the dark.
+	for bar = 1, 4 do
+		paint(
+			prop(
+				`{name}_Grille{bar}`,
+				at[1] - 1.5 + bar * 0.8,
+				4.2,
+				at[2],
+				0.12,
+				2.4,
+				0.12,
+				TIN,
+				Enum.Material.CorrodedMetal,
+				stalls
+			),
+			"BarrioRustedSteel"
+		)
+	end
```

#### Step 6.3: The well, the arko, and the container pads that are still blue rectangles

**File:** `tools/greybox/barrio.luau`

**No `**Verify:**` line.** Every mechanical property this step could claim is already gated elsewhere:
the container *tags* by `barrio-contract` at 6.1, the *part budget* by `barrio-budget` at 5.3. What 6.3
actually delivers is §5's *"visually obvious as searchable at a glance, on a phone, in the dark"* — and
that is the one requirement in the whole spec that is defined by what a player can see. It needs the
playtester's phone screenshot, not a command.

The well takes hero mesh #5. The arko loses its escape gate in Phase 2 and needs re-dressing as what it
actually is — a village gate arch, usually concrete with the barangay name on it.

**And the debt from Step 2.3 comes due here.** Fifteen `SearchContainer` anchors are currently flat blue
`ANCHOR_C` pads, and §5 requires they be *"visually obvious as searchable at a glance, on a phone, in
the dark."* Each pad gets a prop **on** it — a rice sack, a crate, a chest — placed at the anchor's
coordinates so the tagged part never moves:

```diff
+--[[
+	WHAT A CONTAINER LOOKS LIKE. The tagged pad stays exactly where `anchor()` put it; this is scenery
+	sitting on top of it, so `SearchService.discoverPool` sees the same part at the same place.
+
+	§5 asks for containers "visually obvious as searchable at a glance, on a phone, in the dark", and
+	that is a SILHOUETTE requirement, not a detail one. Three shapes, reused: a sack, a crate, a jar.
+	One shape would make the barrio look machine-built; a dozen would stop reading as one category,
+	and "is this searchable" is a question a player must never have to ask twice.
+]]
```

> **NOTE — the anchor pad itself should stay visible under the prop, slightly.** It is a 6-stud pad
> matching `Config.Search.ProximityStuds`, so it is also the honest affordance for *how close you must
> get*. C17's comment makes that argument for the task pads and it applies unchanged here.

#### Phase 6 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none. Note that `SaltPouch` is already a replicated tag by deliberate decision
  (`ItemService`, C13); nothing here adds to that surface.
- **Remote direction** / **Rate limiting** / **Phase ownership** — nothing touched.
- **Magic numbers** — `check:config` does not scan `tools/`.
- **Player leaving mid-round** — not applicable.
- **Strict Luau** — run the builder; Studio is this file's only typechecker.
- **Mobile budget** — +16 grille bars, +15 container props, −~45 parts from the meshes placed in 5.3.
  Net roughly flat. Re-read the receipt.
- **Scope** — nothing from §3's OUT list.

**Issues identified:**

- **The chapel light is the single easiest assertion in this plan to break**, because "the chapel
  interior is too dark" is the most natural note to come back from Step 4.5's screenshots. The answer is
  always emissive geometry, never a second `PointLight`.
- **Sari-sari signage cannot carry text.** No image generation exists and no font can be drawn onto a
  part. A `SurfaceGui` with a `TextLabel` is technically possible and is *not* proposed here — it would
  be the first GUI in the map, it costs draw calls on mobile, and it is untested against the streaming
  radius. Raised in Follow Ups.
- **Fifteen container props reusing three shapes is a deliberate readability choice, not laziness.**
  If Step 4.5's answer to question 3 was "not obvious enough", the fix is fewer shapes and more
  contrast, not more variety.

---

### Phase 7: Remaining zones B — the six remaining kubo, planting, field, details

The phase with the part budget in it. `Planting` is 42% of the map and must come **down**.

**This is the phase with the part budget in it.** `Dressing.Planting` is 456 parts — **42% of the entire
map** — and the brief is right that it is a perf hotspot rather than a detail opportunity. Phase 4 spent
+74 parts. This phase must give more than that back.

#### Step 7.1: Apply the approved kubo treatment to the six remaining houses

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-contract.test.luau`

Four of the six carry a `SearchContainer`, which is why the contract suite gates this step and not the
budget one. The work is almost entirely already done: **the changes went into `building()` in Phases 3
and 4, and `building()` builds all seven kubo and the chapel.** What remains is per-house variation, so
the barrio does not read as seven copies of one house.

Research-01's variation axes, in order of how much they show at night: **roof age** (a fresh nipa roof is
straw-gold, a four-year-old one is grey-brown), **wall material mix** (sawali vs. split bamboo vs. a
patched GI sheet), and **whether there is a lean-to**. Vary by house index rather than randomly, so the
map is reproducible — the same argument the seeded `rng` makes.

#### Step 7.2: Reduce and improve the planting

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-budget.test.luau`

Current: 108 bamboo culms + 201 bamboo leaves + 12 banana trunks + 48 banana leaves + 72 fence posts
= **441 of the 456**. The 201 leaf parts are the target: **research-07 will confirm Philippine bamboo is
clumping, not running** — culms grow in dense clumps from a single base, with leaf mass concentrated in
the upper third.

That is a cheaper shape than the greybox builds *and* a more accurate one:

```diff
-	-- one leaf part per culm, scattered up its length
+	--[[
+		LEAF MASS IN THE UPPER THIRD, ONE CLUSTER PER CLUMP — not one leaf per culm.
+
+		Philippine bamboo is CLUMPING (see research-07): culms rise from a shared base and the foliage
+		reads as a single mass, not as individually-leafed poles. So one wider cluster per clump is
+		both more accurate and roughly a third of the parts.
+
+		This is the plan's largest single part saving and it is the reason Phase 4 could afford +74.
+	]]
```

**Target: `Planting` ≤ 400, from 456.** A saving of ~56 parts, which more than covers Phase 4's 74 once
Phase 5's mesh replacements (−37) are counted.

> **IMPORTANT — the fence runs are 72 parts and must NOT be thinned.** Fences are the only thing in
> `Planting` doing layout work: they suggest the alley walls and the field edges that §5's sightline
> rule depends on. Take the saving from leaves.

#### Step 7.3: Detail the eight graves in place

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-graves.test.luau`

> **The fourth grep in this plan that could not pass.** `grep -c Grave1_Candle` against a loop writing
> `Grave{index}_Candle` — the same literal-versus-interpolation defect as Steps 4.2 and 6.2. Now gated
> on `tests/barrio-graves.test.luau`, which also asserts the scope decision: that no cemetery zone was
> added and the eight markers did not move.

**No cemetery zone.** The eight graves stay exactly where they are, in `Dressing.Details`, at their
current coordinates beside the chapel. This was the user's explicit choice of the smaller scope and it is
also the better one — a cemetery is a zone §5 does not list, and adding one would move the layout.

Each grave is currently two grey `Concrete` boxes: a leaning vertical and a horizontal crossbar, heights
jittered 2.4–3.6 from the seeded `rng`. Research-05's correction is significant and cheap: **Philippine
grave markers are typically above-ground painted concrete tombs, not carved granite headstones.** So:

```diff
-			Color3.fromRGB(126, 124, 116),
-			Enum.Material.Concrete,
+			Color3.fromRGB(196, 192, 180),
+			Enum.Material.Concrete,
```

plus, per grave: a low **above-ground tomb slab** the cross stands on (the single biggest correction —
it changes the silhouette from headstone to tomb), `BarrioWhitewash` paint with moss at the base, and a
candle stub. The candles are `Neon` and **not** `PointLight`s — C30 rule 2 is asserted and eight new
lights would be a 57% overspend of the entire map's light budget.

> **The `lean` already applied is correct and research-05 supports it** — tropical subsidence tilts
> markers within a few years. Keep it.

#### Step 7.4: The rice field, the field dressing and the power line

**File:** `tools/greybox/barrio.luau`

**No `**Verify:**` line.** The part-count half is gated at 7.2 by `barrio-budget`, and the
non-collidable rule is enforced by the builder's own `assert(dressColliders == 0)` at build time rather
than by any command a plan runner can call. Whether a bunded paddy reads as a paddy is an eye.

The rice field is 90 angled wedges and it is §5's *"killing field"* — tall grass, low visibility. Two
corrections from research-07, both free:

- **Paddies are flooded and bunded.** A flat green field is a lawn. `BarrioPaddy` on the stalks and a
  low-reflectance water plane between bunds is the whole read, and the water plane is the same trick the
  ten puddles already use — the builder calls them *"the highest ratio of atmosphere to parts in the
  whole file."*
- **Colour by growth stage.** Uniform green is the giveaway; real paddies are patchworked green to
  golden.

The power line is 92 parts and is already the most authentic thing in the map. Research-06 gives one
correction worth its parts: real barangay wire bundles are **tangled and multi-strand**, not single sagging
runs. `droop` already exists; more strands per run at a slight offset is a loop bound, not new code.

#### Phase 7 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none.
- **Remote direction** / **Rate limiting** / **Phase ownership** — nothing touched.
- **Magic numbers** — `check:config` does not scan `tools/`.
- **Player leaving mid-round** — not applicable.
- **Strict Luau** — run the builder.
- **Mobile budget** — **this is the phase where the budget is reconciled or the plan has failed.**
  Target `Planting` ≤ 400 and total ≤ 1,250. If the receipt is over, cut leaves further before cutting
  anything from Phases 4–6, because leaves are the cheapest thing in the map per unit of realism.
- **Scope** — nothing from §3's OUT list. **No cemetery zone**, by explicit decision.

**Issues identified:**

- **Eight candle stubs must be `Neon`, never `PointLight`.** The builder asserts `dressLights == 0` and
  will fail the build. That is the guard working; do not waive it.
- **The rice field's water plane must be non-collidable**, like every other `prop`. A collidable plane
  across the field would reroute the navmesh through §5's killing field and change the crossing time.
- **`Planting` reduction risks the sightline rule in the wrong direction.** Thinning bamboo makes the
  map *more* visible, and §5 wants *partial* information. If the field or the groves stop occluding,
  the fix is fewer, denser clumps rather than restoring the leaf count.

---

### Phase 8: Lighting reconciliation and the final measured perf check

#### Step 8.1: Retune the authored night, respecting the SkyController capture

**File:** `tools/greybox/barrio.luau`

**No `**Verify:**` line.** The old one was `lune run tests/sky-cycle.test.luau`, an existing suite that
passes today and would pass whatever this step typed — it tests the dawn *curve*, not the night's
values. **This step is colour-tuning: it is the most purely visual step in the plan**, and no command
can judge it. The *structural* half — that the builder still authors all five captured properties and
leaves `ClockTime` at 0 — is gated at 8.2. Reported as `unverifiable`.

**Read the "lighting trap" section in the preamble before touching anything here.** The short version,
repeated because a phase must be implementable from its own slice:

`SkyController` reads `Brightness`, `FogEnd`, `Ambient`, `OutdoorAmbient` and the `Atmosphere.Density`
off the place **once at startup** and treats them as the baseline it lerps toward dawn and back.
`Config.Sky` holds only multipliers. So **retuning those five here is correct and supported** — C28's own
comment says C30's art pass *"retunes it here without touching `Config` or any controller"* — and the
existing `tests/sky-cycle.test.luau` is the suite that proves the dawn curve still behaves over whatever
baseline the builder now authors.

**`ClockTime` is the exception.** The builder's `0` is what a map author sees in Studio; the round owns
the real value through `Config.Sky.StartClockTime = 3.0`. **Do not treat `ClockTime` as an art value** —
raising it to "make Studio look nicer" changes nothing a player sees and makes the builder disagree with
the runtime for no gain.

Research-04 drives the values: rural barangay lighting is **sparse warm sodium/CFL with deep shadow
between**, which is a low `Brightness` and a warm `OutdoorAmbient`, not a blue one.

> **IMPORTANT — a brighter night is the most tempting and most damaging change available here.** §5's
> sightline rule is *"you should almost always be able to see something… fear comes from partial
> information"*, and the answer to a too-dark barrio is **more lanterns spaced further apart**, not a
> higher `Ambient`. Raising `Ambient` flattens the whole map at once and removes the deep shadow that
> research-04 says is the actual look of a rural barrio at night.

#### Step 8.2: Spend the properties SkyController never touches

**File:** `tools/greybox/barrio.luau`
**Verify:** `lune run tests/barrio-lighting.test.luau`

These have **no runtime owner**, so the builder owns them outright and they are the safest realism
budget in the whole plan: `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `GlobalShadows`,
`FogColor`, and the Atmosphere's `Color`, `Decay`, `Glare` and `Haze`.

A new suite pins the split so a later edit cannot quietly move a property the controller owns:

```diff
+-- The five properties SkyController captures at startup. The builder may set them; nothing else may
+-- assume a literal value for them, because Config.Sky holds only MULTIPLIERS of whatever is authored.
+local CAPTURED = { "Brightness", "FogEnd", "Ambient", "OutdoorAmbient", "Density" }
+
+-- ClockTime belongs to the ROUND (Config.Sky.StartClockTime). The builder's 0 is a Studio-authoring
+-- convenience and must stay 0, or the file starts disagreeing with the runtime about what night is.
+check(
+	"the builder still authors ClockTime = 0 and leaves the clock to the round",
+	string.match(builder, "Lighting%.ClockTime%s*=%s*0") ~= nil
+)
```

#### Step 8.3: Final measurement — crossing time, part count, FPS on a phone

**File:** `.claude/plans/feature-barrio-realism-plan/artifacts/final-perf.md`
**Verify:** `npm run verify`

> **`npm run verify` is the right check *here* and nowhere else in this plan.** Everywhere else a
> whole-tree gate would be regression protection masquerading as proof. This step's deliverable **is**
> the whole tree: the plan is finished, all nine new suites must be green together, and `verify` is the
> only command that asserts that. It is a final gate, not a step check.
>
> **It still does not prove the three numbers below.** Crossing time, part count and phone FPS are read
> from `measure.luau`, the builder's receipt and a real device, and recorded in `artifacts/final-perf.md`
> by hand. `verify` going green with a 45-second crossing is entirely possible.

The same four numbers as Step 4.4, over the finished map, plus the one that cannot be taken in Studio.

| Number | Pass condition |
| --- | --- |
| Crossing time | 30–40s, and **within ~2s of the pre-plan reading** |
| Total `Barrio` instances | ≤ 1,250 |
| `Dressing` colliders / lights | 0 / 0 (asserted by the build) |
| `MapLight` count | 14, and `mapLights == totalLights` (asserted) |
| **FPS on a real mid-range Android** | **≥ 30** |

> **The phone number is the only one that matters and it is the only one no agent can take.** §5 says
> *"tested on a real phone"*, and Studio's FPS on a desktop is not evidence about a phone. `playtester`
> can capture the in-Studio readout; **a human with an actual Android device closes this step.** Say so
> in `final-perf.md` rather than reporting the desktop number as if it answered the question.
>
> **End with File → Publish to Roblox.** Roblox's cloud place-version history is the map's only backup —
> `.rbxl` is gitignored, `git status` will never show a missing prop, and every generated mesh and
> MaterialVariant in this plan lives only in the place file. An unpublished session of this work is one
> crash from gone.

#### Phase 8 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — **the sky is the largest surface in the game to leak a difference across**, and
  `SkyController`'s header says so: it is driven from a snapshot every client receives, through a pure
  function with no role input. Nothing in this phase adds a per-player lighting path, and nothing in it
  may. A "the Aswang sees better at night" idea is a leak, not a feature.
- **Remote direction** / **Rate limiting** / **Phase ownership** — nothing touched.
- **Magic numbers** — lighting values belong in the builder by C28's explicit design, not in `Config`,
  which holds only the dawn multipliers. This is the one place where "put it in Config" would be wrong.
- **Player leaving mid-round** — not applicable.
- **Strict Luau** — run the builder.
- **Mobile budget** — **no new lights.** 14 `MapLight`s in, 14 out. `Config.Performance.MaxVisibleLights`
  stays 8 and `PerformanceController` keeps culling by distance.
- **Scope** — nothing from §3's OUT list. §C.5 explicitly rejects the competitor's dynamic day/night
  cycle *as atmosphere*; this repo already stole it correctly at C28 by pointing it at the round clock,
  and this phase does not change that relationship.

**Issues identified:**

- **`Lighting.Technology = Future` cannot be set from this context and only warns.** The builder already
  handles this — it attempts, survives the refusal, and prints what to set by hand. §5 asks for Future
  lighting explicitly, so **confirm it is actually Future in the Properties panel** before taking the
  final screenshots. A shadow-quality difference between the approval screenshots and the final ones
  would otherwise be attributed to this plan's material work.
- **The two streaming radii are also unscriptable** and are set by hand: TARGET 341, MIN 170 at
  `SCALE = 1.55`. Confirm them at 8.3; a wrong radius shows up as props popping in, which reads exactly
  like a bad art pass.
- **`SkyController` captures at Start, so a lighting change made while a playtest is running is
  invisible until rejoin.** Re-run the builder, then restart the play session, before judging any
  lighting change.

---

## 3. Related Files

### Changed by this plan

| File | Phases | What changes |
| --- | --- | --- |
| `tools/greybox/barrio.luau` | 2–8 | **Everything visual.** The stale v1.3 emissions, the v2.0 contract, the ASSETS registry, `paint()`, `mesh()`, every zone, the lighting |
| `tools/greybox/measure.luau` | 2 | The stale reachability tag set — `TaskPoint`/`FetchSource`/`EscapeGate` → `SearchContainer`/`SaltSpawn` |
| `tools/greybox/README.md` | 2 | Its "what the services demand" summary inherits the same staleness |

### Created by this plan

| File | Phase | Why it can fail |
| --- | --- | --- |
| `tests/barrio-legacy.test.luau` | 2 | v1.3 tokens resurrected into the map |
| `tests/barrio-contract.test.luau` | 2 | container/ambient counts disagree with `Config.luau`; duplicate Names |
| `tests/barrio-ambient.test.luau` | 2 | fewer than 16 `AmbientSpawn` — the ring fallback silently returns |
| `tests/barrio-measure.test.luau` | 2 | `measure.luau` measuring a tag nothing emits |
| `tests/barrio-materials.test.luau` | 3 | a `MaterialVariant` set without its `Material` — the silent-nothing case |
| `tests/barrio-receipt.test.luau` | 2 | the header still naming a deleted service; receipt literals disagreeing with `Config.luau` |
| `tests/barrio-assets.test.luau` | 5 | triangle budget, malformed or ungenerated asset IDs |
| `tests/barrio-budget.test.luau` | 4–7 | part-count and collider ceilings; the mesh `Observed` readback (class, tris, parent) |
| `tests/barrio-lighting.test.luau` | 8 | the builder writing a property `SkyController` owns |

### Read to write this plan, not changed

`docs/MVP-SPEC.md` §5 · `src/server/Services/SearchService.luau` · `ItemService.luau` ·
`AmbientService.luau` · `TrialService.luau` · `src/server/pure/ContainerLayout.luau` ·
`src/client/Controllers/SkyController.luau` · `PerformanceController.luau` · `src/shared/Config.luau` ·
`tools/greybox/README.md` · `package.json`, `selene.toml`, `stylua.toml` and the five check scripts
(to establish that none of them scan `tools/`).

Annotated excerpts are in `references/`.

---

## 4. Follow Ups

### Questions / Clarifications

1. ~~**`MeshPart.MeshId` scriptability — blocks Phase 5.**~~ **RESOLVED 2026-08-29, empirically, in the
   live place via `execute_luau` in Edit mode.** `MeshPart.MeshId` is **NOT** script-writable:
   `Instance.new("MeshPart").MeshId = "rbxassetid://1"` fails with *"The current thread cannot write
   'MeshId' (lacking capability NotAccessible)"*, and the property is left as `""` — a **silent**
   failure, which is why Phase 5 is built around Hard Rule 1. Confirmed available in the same probe:
   `AssetService:CreateMeshPartAsync` exists, `SpecialMesh.MeshId`/`TextureId` are writable, and
   `MaterialVariant` create-and-bind works (a `Part` read `MaterialVariant` back as the assigned name).
   **Phase 5 was rewritten against this result** and picks `CreateMeshPartAsync`, because a `MeshPart`
   is the only one of the three options that can carry a `MaterialVariant`. Nothing here is open.

   One genuinely open sub-question remains and it is flagged inside Phase 5 rather than here: the exact
   **`CreateMeshPartAsync` parameter shape** in this Studio version. The helper calls it with the id
   alone; probe for the options table before writing it.

2. **`generate_material`'s accepted `baseMaterial` set.** The twelve planned variants name `Mud`,
   `Ground`, `CorrodedMetal` and `Fabric`. All are real `Enum.Material` values but I have not confirmed
   the tool accepts each as a base. Record what comes back, not what was asked for.

3. **The ambient rigs are four coloured blocks and this plan cannot fix them.** `FORM_LOOKS` lives in
   `src/server/Services/AmbientService.luau` — game code, under all five checks, outside this plan's
   scope. In a realism pass over the barrio, sixteen blocks labelled CAT/DOG/PIG/VILLAGER wandering the
   map will be the most obviously unfinished thing in it, and §4.5's camouflage deduction ("which cat",
   never "is that a cat") depends on them reading as animals. **This is the single largest realism gap
   left open and it wants its own small plan.** Four of the eight hero meshes could have gone here
   instead; they did not, because the brief scoped this to the map.

4. **Sari-sari signage cannot carry text.** No image generation exists in this toolchain (asset-pipeline
   skill, explicit) and no lettering can be drawn onto a part. A `SurfaceGui` + `TextLabel` is
   technically possible and deliberately not proposed — first GUI in the map, mobile draw calls,
   untested against the streaming radius. If real signage matters, it is a `search_asset` hunt for a
   decal, or a person making one.

5. **The covered multipurpose court is refused, and it is the most authentic thing being left out.**
   Reasons in Step 4.1: collidable posts (C30 rule 1, asserted), a light underneath (rule 2, asserted),
   and a roof over the spawn plaza breaking §5's sightline rule at the exact place it is measured from.
   Recording it so nobody re-adds it in Phase 6 thinking it was an oversight.

6. **Should the builder join `npm run verify` formally?** After Phase 2 it is covered by eight Lune
   suites inside `test:unit`, but `lint`, `fmt:check` and `analyze` still skip `tools/`. Adding
   `selene tools` and `stylua tools` is a two-word change to `package.json` and would have caught
   nothing in this plan — but it would have caught the stale builder eventually. **Not proposed here**
   because it changes a repo-wide gate on an art plan's authority, which is the wrong place for that
   decision. Raising it for the user.

7. **Does the ~35s crossing target still hold at v2.0's 3–5 players?** §5 says the size question
   *"matters more in v2.0, not less"*, and searching replaced tasks as the thing players cross the map
   to do. This plan explicitly does not move the layout, so the question is untouched by it — but V16's
   playtest is where it gets answered, and if the answer is "too big", that invalidates layout, not art.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 2 | The map emits **zero** `SearchContainer` parts while `Config.Search.ContainerCount = 15`. Searching is the whole v2.0 game; the symptom is "there is nothing to do" | **Critical** | Fixed by Step 2.3 |
| 2 | The map emits **zero** `AmbientSpawn` parts, so `AmbientService` is running its ring fallback — 16 animals in a circle at the origin | **High** | Fixed by Step 2.4 |
| 2 | The builder resurrects `EscapeGate` and 12 `TaskPoint` anchors that V01 deleted, every time it runs | **High** | Fixed by Step 2.2 |
| 2 | `measure.luau` is stale in the same way and nobody flagged it. Its reachability set is built from three tags, two of which this plan deletes — it would report a healthy crossing over almost nothing | **High** | Fixed by Step 2.6 |
| 2 | The builder's header documents a contract with `TaskService`/`GateService`, services that no longer exist. It is the most misleading text in the file | Medium | Fixed by Step 2.5 |
| — | `tools/greybox/` is outside `lint`, `fmt:check`, `analyze` and all five checks. Verified per-script, not assumed | Medium | Mitigated by 8 new Lune suites; see Follow Up 6 |
| 4 | Stilts vs. the layout rule: raising a kubo floor makes the interior unreachable unless the collision changes, and collision changes move the crossing time | Medium | Decision written into Step 4.3; must be logged |
| 5 | `MeshPart.MeshId` is **not** scriptable — silent failure, leaves `""` | Medium | **Resolved** by probe 2026-08-29; Phase 5 rewritten on `CreateMeshPartAsync`; Follow Up 1 |
| 3 | MaterialVariants live only in the place file. A place rollback degrades the map to base materials | Low | Soft failure by design; `paint()` warns by name |
| 4 | +74 parts in one phase, against a +152 total headroom | Low | Reconciled in Phase 7; receipt is binding |
| — | The ambient rigs stay four coloured blocks | Medium | Out of scope; Follow Up 3 |
