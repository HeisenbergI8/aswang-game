# ASWANG — Build Plan v2 (chunked)

**What this is:** `docs/MVP-SPEC.md` **v2.0** broken into **22 sequenced chunks**, each sized to *one
background agent run*. The spec says WHAT to build; this says **what to build next, in what order, and
how you know it's done**.

**Precedence is unchanged:** `MVP-SPEC.md` → `CLAUDE.md` → this file → the code. If a chunk here
contradicts the spec, the spec wins and the chunk is wrong.

**Numbering restarts at `V01`.** The v1.3 plan ran `C01`–`C45` and forty of those chunks are in git
history under those names. Reusing the numbers would make `git log --grep` lie. `V##` chunks are v2.0
work; `C##` references in commit messages, plans and lessons still mean what they meant.

---

## 0. Where you actually are — read this first

**Forty chunks of v1.3 shipped.** `C01`–`C40` are committed: the round state machine, the secret role
draw, transform and kill, salt, ghosts, the greybox barrio, the HUD, the Solo Trial, quick chat,
mobile, lighting, audio, map dressing, profiles, XP, cosmetics, badges, the group reward. The game
works. `C41`–`C45` (anti-cheat sweep, playtest #2, launch) never ran.

**v2.0 does not throw that away — but it is honest about which half it invalidates.**

| | Status under v2.0 |
|---|---|
| **Dies** | Tasks, the escape gate, ghosts, the old win conditions. `TaskService`, `GateService`, `GhostService`, `TaskSelection`, `TaskWeight`, `WinConditions`, `GhostChat`, `SpookBudget` and their suites |
| **Reworked** | `MonsterService` (health, feed, camouflage, smoke), `ItemService` (three items, not one), `TransformRules`, `KillValidation`, `SaltThrow`, `SaltCarry`, `BodyTransitions`, `TrialTimeline`, `BadgeRules`, `ProfileMigration`, the HUD |
| **Survives untouched** | The entire round state machine, `RoleService` and the secrecy layer, quick-chat plumbing, the greybox map, lighting, audio, `AntiCheatService`, progression, monetization, community, analytics transport. **Roughly M0–M2 and the whole business layer** |

**What that means for sequencing:** v2.0 is not a fresh build. It is a **transplant** — Track V0 removes
the old organ, Tracks V1–V2 fit the new one, and Track V4 reconnects the business layer that never
stopped working. The launch track at the end is v1.3's `C41`–`C45`, unchanged in substance.

---

## 1. How to use this

### One chunk = one run

A chunk is scoped so you can hand it to the pipeline, walk away, and come back to something either
finished or halted with a written reason. Not a "day" — a *unit of delegable work*.

Each chunk carries five fields:

| Field | Meaning |
| --- | --- |
| **Tier** | **Large, for every chunk in this plan.** See the deviation note below — this is a deliberate override of `CLAUDE.md`'s routing table, not a sizing judgement. |
| **Runner** | 🤖 agent · 🧍 you · 🤝 both (agent writes code, you do the Studio/asset half) |
| **Deps** | Chunks that must be green first. Nothing else is ordered. |
| **Done** | The definition of done, stated so it can be checked rather than felt. |
| **Verify** | The actual command or evidence. `verify` always means `npm run verify`. |

### How to start one

```bash
rojo serve                         # always, first
npm run preflight -- --studio      # entry conditions
```

**Every chunk here runs the same way:** `/build`, the supervised task loop.

```bash
/build V03                         # the loop owns it from here
```

That means `architect` → plan directory → `implement-plan` → `playtester` + `auditor`, and
`exploit-auditor` **in addition** on every chunk marked 🔒. The loop halts on `done` only when four
proxies are satisfied: plan steps passed, `verify` green, `implementation-log.md` present, and
`verification.md` citing a file that exists in `artifacts/`.

**V16 is the exception and it has no tier.** It is a playtest with real humans. No agent runs it, the
loop cannot drive it, and its output is notes in `docs/playtests/` rather than a diff.

### The rule that makes chunks agent-shaped

> **Every gameplay decision that can be a pure function must be one.**

Lune can't see `game`. So each chunk containing a real decision — the container draw, the health floor,
the feed verdict, the camouflage gate, the win check — puts that decision in `src/shared/pure/` as a
pure function over plain tables, and leaves a thin Roblox wrapper around it.

That is what turns "an agent says it works" into "a test says it works." **v2.0 leans on this harder
than v1.3 did**, because the new mechanics interact multiplicatively: health × salt count × feed heal ×
the buntot pagi's two-condition gate is a space you cannot check by playing, and §6.5's six invariants
are the only thing standing between you and a win condition that is quietly unreachable.

### Two deviations, flagged rather than quietly resolved

**1. Every chunk is Large tier, by author's decision.**

`CLAUDE.md`'s routing table says size the task first and warns that planning a precisely-specified
change costs more than doing it. By that rule V02 (enum values and a Config block) and V17 (one
seeding rule) are Small, and this plan overrides it.

**The reason is mechanical, and it is sound.** `/build` — the supervised loop — only drives Large-tier
work, because its cursor walks `#### Step N.M` headings and only Large gets an `architect`, so only
Large has a plan directory to walk. `/build --tier small|medium` is refused with an explanation rather
than started. **If the loop is to own the whole rewrite, every chunk must be Large.** A uniform tier
also means a uniform artifact trail — one plan directory, one `implementation-log.md`, one
`verification.md` per chunk — which is what makes 22 chunks trackable instead of 22 differently-shaped
piles of evidence.

**The cost, recorded once so nobody rediscovers it as a surprise:** a full Large pass is an architect
plan plus three reviewers, and `CLAUDE.md` prices a three-reviewer pass at 150–250k tokens. Subagents
share no cache, so each one re-reads its material cold. On the small chunks this buys a plan directory
for work that fits in one diff. That is the trade, it was made deliberately, and the counterweight is
real: consistent process, a mechanical `done`, and nothing routed by judgement mid-rewrite.

**2. The feel pass moves before the playtest.**

§12 puts it at M6, before the playtest. This plan agrees and goes further: **V14 is a *hard gate* on
V16.** The reason is in the spec — horror is 80% lighting and sound, and a greybox under default
lighting tests a different, less frightening game. The counter-argument (Appendix C: don't dress what
you haven't proved) is answered by scope: V14 is fog, darkness, four warm lights, ambience and two
VFX. It is not props, textures or dressing, which stay at V21.

---

## 2. The tracks

```
Track V0 — demolition   V01              remove what v2.0 killed. One chunk, one big diff.
Track V1 — the loop     V02 ─▶ V13       searching, noise, health, feed, camouflage, items, win.
Track V2 — feel + read  V14, V15         atmosphere and a HUD that shows the new state.
       ══ GATE 1 ══     V16              playtest. Everything can change here.
Track V3 — FTUE         V17, V18         the guaranteed first find, the Solo Trial rewrite.
Track V4 — reconnect    V19, V20         badges, analytics and profiles, remapped to v2 vocabulary.
Track V5 — art          V21              sprites and the animation pipeline. 🧍 you supply input.
Track V6 — launch       V22 + C41–C45    anti-cheat sweep, balance playtest, store, launch.
```

Chunks are numbered in **execution order**. Where two adjacent chunks have no dependency between them,
order is a suggestion; where `Deps` names a chunk, it is not.

---

## 3. Track V0 — demolition

### V01 — Remove the task game
**Tier** Large · **Runner** 🤖 · **Deps** — · 🔒

One chunk, one large diff, and the tree stops lying about what the game is. Doing this incrementally
was considered and rejected: 38 test files currently include suites for mechanics that no longer exist,
and every agent that reads the repo would be misled for as long as they sit there.

**Delete outright:**
- `src/server/Services/TaskService.luau`, `GateService.luau`, `GhostService.luau`
- `src/client/Controllers/TaskController.luau`, `GhostController.luau`
- `src/shared/pure/TaskSelection.luau`, `TaskWeight.luau`, `GhostChat.luau`, `SpookBudget.luau`
- Their suites in `tests/`, and the task/ghost remotes in `Remotes.luau`
- `Config.Tasks`, `Config.Ghost`, and every task/ghost field in `Types.luau`

**Leave standing:** `WinConditions.luau` is deleted but its **test file is kept and emptied to a
skeleton** — V11 rewrites both, and the grid-first discipline that file encodes is the reason the
attrition rule eventually came out right. Do not lose the habit with the code.

**Also in this diff — re-arm the scope guard.** `check-scope.mjs` carries a commented-out `ghosts?`
entry marked `DEFERRED TO V01`, with its self-test case already written. Uncomment both. It is
deferred because enabling it before the deletion produces 154 findings across nine live modules and a
commit guard that refuses every commit — a guard that blocks the work it protects gets disabled rather
than obeyed. **Uncommenting it is what stops ghosts coming back**, so it is part of the demolition,
not a follow-up.

**Watch for:** `check:remotes` will fail loudly if a client still waits on a deleted remote — that is
the check doing its job, not a problem to work around. On the client, `WaitForChild` on a name the
server never creates **hangs forever** with no error.

**Done** every file above gone; `verify` green; no dangling references; `git grep -i task src/` returns
only Roblox's `task` library.
**Verify** `verify` green from a clean tree; `npm run check:remotes` passes; playtester confirms a
round still cycles IDLE→ACTIVE→ENDING in Studio with nothing to do in it.

---

## 4. Track V1 — the new loop

### V02 — The v2 vocabulary: Enums, Types, Config
**Tier** Large · **Runner** 🤖 · **Deps** V01

Nothing works until the words exist. This chunk adds no behaviour.

- `Enums`: `ItemType` (Salt/Bawang/BuntotPagi), `MonsterState` (Normal/Transformed/Exposed/Feeding/
  Camouflaged), `BodyKind` (Corpse/Husk), `CamouflageForm` (Cat/Dog/Pig/Villager). **Keep the
  `:: Types.X` casts** — a literal union infers as plain `string` without them.
- `Types`: `ClientRoundSnapshot` gains a carry slot and loses nothing. **It still has no alive count
  and no role field** — Amendment A3's list of forbidden names is carried into v2 verbatim, in place.
- `Config`: the full v2 block from spec §6.5.

**Done** spec §6.5's Config block present with the comment for every number; enums cast; analyze clean.
**Verify** `verify` green, **`test:unit` included**.

> **Corrected during V02.** This line used to predict that `lune run tests/config.test.luau` would FAIL
> until V11 wrote the six invariants, and called V02's gate "analyze + lint only". That was wrong on
> both counts: the suite already existed and **passed** (82 invariants, exit 0) before V02 started, so
> there was never a red to expect. The prediction described a hard rename of `Config.Salt.*` to §6.5's
> `Items.Salt*` names — but five live modules read the old keys, so that branch reds `analyze` too,
> which this chunk's own **Done** line forbids. V02 therefore makes `Config.Items` canonical and leaves
> `Config.Salt`'s four renamed keys as aliases into it. **A red `test:unit` here is a real V02 failure,
> not an expected one.** The aliases are deleted by the chunk that rewrites each last reader.

---

### V03 — SearchService: containers and the layout seed
**Tier** Large · **Runner** 🤖 · **Deps** V02 · 🔒

The heart of §4.4. ~15 containers, a randomized subset seeded each round with 4 salt, 2 bawang, 1
buntot pagi.

- Pure module **`src/server/pure/ContainerLayout.luau`** — `(containerCount, itemCounts, rng) →
  layout`. **In `server/pure/`, not `shared/pure/`.** `src/shared` maps wholesale into
  `ReplicatedStorage`, so a LocalScript can `require()` and *run* a shared module. A layout draw whose
  inputs a client can supply is a client that knows where the buntot pagi is before the round starts —
  no remote to intercept, nothing for `check:secrecy` to see. Lune resolves by file path and cares
  nothing for Rojo.
- **Seed from server-only entropy.** `Random.new()` with no argument is fine. `Random.new(roundNumber)`
  and `Random.new(os.time())` are fatal — `os.time()` is client-observable to the second.
- 6-second hold to search, server-validated: distance, phase, one searcher per container at a time.
- The layout never crosses the wire. A client learns a container's contents by opening it.

**Done** layout seeded at `STARTING`; searching yields items; nothing about the layout is client-readable.
**Verify** `lune run tests/container-layout.test.luau` — 10,000 draws asserting every item placed
exactly once, no container double-seeded, and distribution across the pool is not degenerate.
`exploit-auditor` answers: can a client derive the layout from anything it receives?

---

### V04 — Noise: the risk economy
**Tier** Large · **Runner** 🤖 · **Deps** V03

Searching is loud, and loud is how you die. This is §4.4's entire point and it is a *system*, not a
sound effect.

- Pure module **`src/shared/pure/NoiseModel.luau`** — `(action, state) → {loudness, radius}`. Sprint,
  search, door, item use. Publishing this is harmless: it is a table, and `Config` is replicated anyway.
- The server records noise events with position and timestamp. **They are the tracker's only input**
  (V13) and they do not go to clients.
- **The survivor who made the noise is told they made it.** A sound you cannot perceive is not tension,
  it is a dice roll. A brief "that was loud" cue — audio first, UI second.

**Done** every noisy action emits; the actor gets feedback; noise history is server-only and bounded.
**Verify** `lune run tests/noise-model.test.luau` over the action × state grid; playtester confirms
the cue fires on a search and not on a walk.

---

### V05 — MonsterService: health, Exposed, Weakened
**Tier** Large · **Runner** 🤖 · **Deps** V02 · 🔒

The tug-of-war from §4.6. This chunk is small in code and dense in consequence.

- Pure module **`src/shared/pure/MonsterHealth.luau`** — `(health, event) → health'` plus the
  `isWeakened` predicate. **Enumerate the domain rather than writing a case per bug**: health ∈
  {full, mid, at-floor, below-floor, 0, ±inf, NaN} × event ∈ {salt, feed, none}. A pure predicate over
  a bounded domain earns a grid, and this repo has already paid four review rounds for learning that
  the reactive way.
- **The floor is the mechanic:** salt can never reduce below `WeakenedThreshold`. Salt alone must not
  kill, or the buntot pagi is decoration.
- **Health is server-only, readable by others only while `Exposed`** (§6.2). No health bar on a player
  — a health value attached to someone IS the reveal. Presentation is the glow brightening as it weakens.

**Done** health tracked; floor enforced; `Exposed` set by salt and cleared on expiry; nothing leaks.
**Verify** `lune run tests/monster-health.test.luau` over the full grid; `exploit-auditor` answers:
can any client read the Aswang's health outside `Exposed`, by any path including a derived hint?

---

### V06 — Feeding
**Tier** Large · **Runner** 🤖 · **Deps** V05 · 🔒

What replaced the kill cooldown (§4.3). 5 seconds, locked to the corpse, interruptible.

- Pure module **`src/shared/pure/FeedRules.luau`** — `(monsterState, bodyKind, distance, phase) →
  verdict`. A husk is not feedable until it has been killed, at which point it is a corpse.
- Server-validated: proximity to the corpse, `Transformed`, round `ACTIVE`. Movement locked for the
  duration.
- **Salt interrupts it**, and the interruption costs the heal *and* the camouflage refresh.
- On completion: `+FeedHeal` health, and camouflage restored **only if already revealed** (V07).

**Done** feed starts, locks, heals, and is interruptible; a husk cannot be fed on until killed.
**Verify** `lune run tests/feed-rules.test.luau` over the state × body × distance × phase grid;
playtester records a feed and a salt-interrupted feed in Studio.

---

### V07 — Camouflage and smoke
**Tier** Large · **Runner** 🤖 · **Deps** V06 · 🔒

§4.3's most dangerous chunk. Read the spec section before writing a line — the gate is not a balance
dial and getting it wrong is a total secrecy failure, not a bug.

- Pure module **`src/shared/pure/CamouflageRules.luau`** — `(hasBeenRevealed, hasCamouflageCharge,
  monsterState, phase) → verdict`. **`hasBeenRevealed` is the gate and it is set by the first salt
  hit, never by anything else.** "Someone saw it transform" is not knowable server-side; a salt hit is
  a fact the server already owns.
- Forms: cat, dog, pig, villager. **The Aswang swaps with an existing ambient entity** — the real one
  wanders off, the monster takes its slot. It must never *spawn* a new one: two pigs where there was
  one is a head count with extra steps.
- Charge is spent on use and restored only by a feed (V06). Once revealed, **the monster must kill to
  hide**.
- Smoke: one burst, breaks line of sight, covers a disengage. It belongs to the Aswang, never to salt.

> **The failure this chunk exists to prevent:** an unrevealed Aswang that camouflages removes a player
> avatar from the world. Four players visible, one missing, in a five-player lobby. Anyone who counts
> knows — permanently, for free, with nothing to argue about. If a future change lets camouflage fire
> before a reveal, the deduction layer is gone and no test will report it.

**Done** camouflage impossible before a salt hit; spent on use; restored only by feeding; swap-not-spawn;
smoke works.
**Verify** `lune run tests/camouflage-rules.test.luau` — exhaustive over the four-input grid, with the
pre-reveal row asserted as universally denied. `exploit-auditor` answers: (1) can camouflage fire
before a reveal by any path, (2) does the ambient population count change when it fires, (3) is the
charge state readable by a non-Aswang client.

---

### V08 — ItemService: the three items
**Tier** Large · **Runner** 🤖 · **Deps** V03, V05 · 🔒

Salt is a rework of shipped code; the other two are new. One carry slot, no recharge.

- **`SaltCarry`/`SaltThrow` generalise to `ItemCarry`/`ItemThrow`** — the cone, the range and the four
  MISS worlds already have 70 assertions behind them and that work carries over.
- Salt on hit: force revert, `Exposed` for 10s, −25 health, interrupt any feed, **and set
  `hasBeenRevealed`** (the V07 gate).
- Items come from containers (V03), never from a spawn point. One carried at a time; picking up a
  second requires dropping the first.

**Done** three item types carried and used; salt does all five of its jobs; carry slot enforced server-side.
**Verify** `lune run tests/item-throw.test.luau` (the migrated salt suite, extended); playtester lands
a salt hit and confirms the glow, the revert and the health change in console output.

---

### V09 — Bawang: the silent doorway
**Tier** Large · **Runner** 🤖 · **Deps** V08 · 🔒

Small system, one rule that carries all its weight.

- Placed on a doorway; the Aswang cannot pass for 15s; then it burns out.
- **The block is silent and invisible in its effect.** No knockback, no VFX, no sound, no camera hitch.
  Its movement simply does not carry it through.

> **This is a mechanic, not a rendering note.** Garlic invites a loyalty test — place it, ask everyone
> to walk in, whoever cannot enter is the Aswang. That test *should* exist; it is the best emergent
> social moment in the design. It only stays a game if **refusing is indistinguishable from being
> unable**. A survivor can decline for any reason, including to be funny, and the best outcome is the
> Aswang declining too. The moment the barrier plays *any* effect on the monster, bluffing dies and
> the test becomes a perfect oracle.

**Done** placement, block, burn-out; a survivor may walk through freely; no observable difference
between a monster blocked and a player standing still.
**Verify** playtester records the doorway from a *third player's* camera with the Aswang blocked, and
the artifact shows nothing distinguishable. `exploit-auditor` answers: is there any client-observable
signal — property, sound, animation state, network event — that separates blocked from voluntarily idle?

---

### V10 — Buntot pagi: the only kill
**Tier** Large · **Runner** 🤖 · **Deps** V05, V08 · 🔒

One per round. Breaks on use. Two conditions, both required.

- Pure module **`src/shared/pure/StrikeValidation.luau`** — `(request) → verdict`. Kills **only** if
  `Exposed` **and** `Weakened`. Against anything else: nothing.
  > **CORRECTED DURING V10.** This line originally read `(monsterState, monsterHealth, distance,
  > phase) → verdict`, and **that signature cannot be implemented — building it literally ships a
  > buntot pagi that never kills.** `MonsterService.monsterStateOf` has four producers and `EXPOSED`
  > is not one of them; its header says why ("EXPOSED IS A LATCH, NOT AN ACTIVITY — a salted Aswang
  > is Exposed *and* still an Aswang"). A module gating on `monsterState == "EXPOSED"` refuses every
  > cell of the grid forever, and the symptom is that the second win condition silently does not
  > exist — §6.5 invariant 1's exact failure mode. The shipped module takes two booleans from
  > `MonsterService.IsExposed`/`IsWeakened`, which that file already names "V08's strike gate, half
  > one / half two". `monsterHealth` is likewise absent by decision: `IsWeakened` collapses it to a
  > boolean in the one service that owns it, and none of that service's seams returns the health
  > value. `monsterState` *is* still carried, as `TargetState`, so the grid stays literal — but it
  > is not a gate.
- Droppable, passable, and it **drops where the carrier falls**. A corpse in the open with the win
  condition next to it is the design's best clip and it is free if the drop is implemented.
- It is not purchasable and never will be (§8.3). §C.5's exception depends on all four of its
  properties holding.

**Done** strike validated server-side; both conditions required; breaks on use; drops on death.
**Verify** `lune run tests/strike-validation.test.luau` over state × health × distance × phase,
asserting every non-`Exposed`-or-non-`Weakened` cell is a refusal; playtester records one successful
kill end to end.

---

### V11 — Win conditions, rewritten
**Tier** Large · **Runner** 🤖 · **Deps** V10, V12 · 🔒

Both conditions, and the six Config invariants that keep them reachable.

> **V10 LEFT THIS ONE THING FOR YOU AND IT IS OBSERVABLE IN THE GAME TODAY.** A successful buntot
> pagi strike calls `RoundService.MarkKilled`, which routes an Aswang death to
> `RoundResult.Aborted` — the disconnect path's result, inherited because V10 deliberately did not
> touch win conditions. So the second win condition currently FIRES and then SCORES WRONG: the end
> screen says the round was void. That is the line to replace (`RoundService.luau`, the
> `state.AswangUserId == player.UserId` branch of `MarkKilled`), and it is the same line the timeout
> inversion below warns may exist in more than one place.
>
> **That branch's comment is now stale and will mislead you.** It reads "A kill can never reach this
> branch — `TARGET_IS_ASWANG` refuses it." True of `RequestKill`, false as of V10:
> `MonsterService.StrikeDown` reaches `MarkKilled` for the Aswang by design.

- Pure module **`src/shared/pure/WinConditions.luau`**, rewritten: survivors win at sunrise with ≥1
  alive **or** on the Aswang's death; the Aswang wins at `kills == RequiredKills`.
- **`RequiredKills` is frozen at `STARTING` and never decrements.** Husks (V12) keep every departed
  player on the board, so nothing needs subtracting and no combination of disconnects advances either
  side.
- **The timeout is inverted from v1.3.** This is the single most likely place for stale logic to
  survive the rewrite — v1.3 scored a timeout as an *Aswang* win and that line may exist in more than
  one place.
- Write the **six invariants from spec §6.5** into `tests/config.test.luau`. Invariant 1 is the one
  that silently kills the second win condition.

**Done** both conditions fire; roster frozen; timeout favours survivors; six invariants pinned.
**Verify** `lune run tests/win-conditions.test.luau` — exhaustive grid over roster × kills × timer ×
aswang-alive, plus departure properties; `lune run tests/config.test.luau` green.

---

### V12 — BodyService: corpses and husks
**Tier** Large · **Runner** 🤖 · **Deps** V01 · 🔒

§4.7's two body types, and the Amendment A3 rules that removing ghosts must not take with them.

- Pure module **`src/shared/pure/BodyRules.luau`** — `(cause, idleSeconds, reachable) → bodyKind` and
  the relocation predicate.
- **Corpse:** made by a kill, feedable, 45s then fades. **Husk:** made by a disconnect or 120s idle,
  killable, counts as a kill, becomes a corpse when killed.
- Husks cannot benefit from bawang; one unreachable for 60s relocates to the nearest walkable point.
- **The corpse stays attached as the dead player's `Character`.** `dead[p] = (p.Character == nil)` is a
  one-line roster of the dead, and `GetPropertyChangedSignal("Character")` turns it into a timestamped
  death alert. A hidden body is no better — `Transparency = 1` hides pixels, not existence.
- **Husk state must be plainly visible to everyone.** A husk that differs from a live body in any
  replicated way lets a client enumerate husks — and since the Aswang can never be one, every husk is
  provably innocent. In a 5-player lobby that is a fifth of the field, for free. Public information
  cannot be exploited asymmetrically; hidden asymmetry can.

**Done** both body kinds; AFK detection; relocation; no enumerable difference beyond the public one.
**Verify** `lune run tests/body-rules.test.luau` over cause × idle × reachable; `exploit-auditor`
answers the A3 question directly: *what is true of the living and false of the dead, for every
server-owned replicated property?*

---

### V13 — TrackerService: the sharpening pulse
**Tier** Large · **Runner** 🤖 · **Deps** V04 · 🔒

The pressure that replaces the escape gate (§4.6). **This is the balance-critical chunk of the whole
rewrite** — it is the only thing preventing hiding from being the winning strategy, and the symptom of
getting it wrong is a round where nothing happens.

- Pure module **`src/shared/pure/TrackerCurve.luau`** — `(secondsElapsed, duration) → {interval,
  radius}`, interpolating 90s/40 studs → 30s/15 studs.
- Input is **only** V04's noise history. No position feed, no live tracking.
- **Vague and slow, never live.** The Aswang is a player. Give a player reliable tracking and it stops
  needing to blend in — it walks to the pings and the social layer drains out of the game.

**Done** pulse fires on the curve; reads noise only; nothing continuous.
**Verify** `lune run tests/tracker-curve.test.luau` asserting monotonic sharpening across the round and
the endpoint values; `exploit-auditor` answers: does the pulse payload let the Aswang infer more than
an area — a player identity, an exact position, a count?

---

## 5. Track V2 — feel, and a HUD that reads

### V14 — The feel pass
**Tier** Large · **Runner** 🤝 · **Deps** V13

**The gate on V16, and a deliberate reordering of spec §12.** A greybox under default lighting does not
test the game you are building.

Scope is atmosphere, not art: Future lighting, heavy `Atmosphere` fog, very low ambient, four warm
point lights, the night ambience loop, and the **two VFX the mechanics depend on** — the transform
tell and the feed. Props, textures and dressing wait for V21.

**Audio is mechanically load-bearing in v2.0**, not decoration: §4.4's noise must be *heard* for the
risk economy to read at all, and V04's "that was loud" cue is an audio problem before it is a UI one.

**The feed VFX is the rating-sensitive one** (§4.9). Suggestion, not depiction: hunched silhouette, an
audio cue, a particle effect, camera turned away. No blood.

**Done** the barrio is frightening at 30fps on a phone; noise is audible and directional; both VFX read
at distance.
**Verify** playtester screenshots each phase plus a transform and a feed; `LightBudget` still passes;
frame rate measured on a real device.

---

### V15 — HUD v2
**Tier** Large · **Runner** 🤖 · **Deps** V14

The HUD shipped at `C18`/`C26` draws a task bar and an escape gate. Neither exists.

- Remove the task bar and gate elements. Add the **carry slot** (which of the three you hold), the
  sunrise timer, and the search progress ring.
- **No alive count, under any name.** Amendment A3's forbidden-name list applies unchanged:
  `SurvivorsRemaining`, `DeadCount`, a roster the client can count. It has no data source and must not
  be given one.
- **The Aswang's HUD differs in CONTENT, never in SHAPE.** Same panels, same positions, same
  animations. Role-conditional UI lives in `PlayerGui` and nowhere else — a `BillboardGui`, a
  `Highlight` or a `ParticleEmitter` in the world is visible to every client.
- Load the `ui-polish` skill before touching this.

**Done** every v2 state legible on a phone; no task/gate remnants; shapes identical across roles.
**Verify** playtester screenshots both roles at the same moment and the artifact shows no shape
difference; `check:config` green on the `LAYOUT`/`MOTION` tables.

---

## 6. ══ GATE 1 ══

### V16 — The playtest
**Tier** — · **Runner** 🧍 · **Deps** V15

**Real humans, 5 rounds, 3–5 players.** Load the `playtest` skill. This is spec §12's M7 and it is the
cheapest moment in the project to be wrong.

**The three questions v2.0 exists to answer, and they are not "is it fun":**

1. **Does hiding win?** If a round passes where survivors camped and won, the tracker curve (V13) is
   too gentle. This is the redesign's single biggest risk.
2. **Does anyone ever kill the Aswang?** Target is 10–20% of survivor wins. At 0% the buntot pagi is
   decoration — check §6.5's invariants 1 and 2 before touching anything else.
3. **Does searching feel like survival, or like a chore?** This is the whole reason v2.0 exists. If
   players describe searching as a task list, the rewrite did not land and the honest move is to say
   so here rather than at launch.

**Done** 5 rounds played, notes written to `docs/playtests/`, all three questions answered with
evidence rather than impression.
**Verify** the recording sheet is filled in. **Nothing downstream starts until this chunk has a
written answer to question 1.**

---

## 7. Track V3 — FTUE

### V17 — The guaranteed first find
**Tier** Large · **Runner** 🤖 · **Deps** V16

§10's hard rule, remapped. A brand-new player's first round seeds a **guaranteed-full container near
their spawn**, with a waypoint.

An empty search is correct design for a returning player and **actively hostile as a first
impression** — it is precisely the "wandering a dark map with no idea what to do" that 1.1M people quit
over. `C20` did this for tasks; the shape carries over, the target changes.

**Done** a first-time profile always finds an item within 60s; a returning profile does not get the
guarantee.
**Verify** `lune run tests/first-find.test.luau` over first-round × returning × layout; playtester
joins with a wiped profile and finds an item.

---

### V18 — Solo Trial v2
**Tier** Large · **Runner** 🤖 · **Deps** V17

The shipped Trial (`C21`/`C22`) teaches tasks. Rewrite the 90-second timeline to teach the v2 loop:
**search two containers → hear how loud it is → the scripted Aswang is drawn by the noise → learn the
tell → throw salt.**

`TrialTimeline.luau` and `TrialAdmission.luau` survive as shapes; the beats change.

**Do not let it grow into a PvE campaign.** v2.0's items and searching make that temptation stronger
than v1.3's did, not weaker — this is the exact trap that killed the competitor, and 90 seconds is the
cap, not a target.

**Done** 90 seconds, one player, teaches all four beats, hands off to the queue.
**Verify** `lune run tests/trial-timeline.test.luau` over the full 90s walk; playtester completes it
solo with `MinPlayers` unmet.

---

## 8. Track V4 — reconnect the business layer

### V19 — Badges and analytics, remapped
**Tier** Large · **Runner** 🤖 · **Deps** V18

The business layer never stopped working; it is measuring a game that no longer exists.

- `First Task` → **`First Find`**. Same funnel position, same 50% gate, same diagnostic value.
- `task_completed` → `container_searched` / `item_found`. Add `feed_completed`, `feed_interrupted`,
  `garlic_blocked` (the loyalty test, and how often it happens), `camouflage_used`, `aswang_killed`,
  `husk_created`, and `round_ended.winCondition`.
- **No sixth badge for killing the Aswang.** It measures a rare event, not a funnel stage, and five
  badges mapping to five funnel steps is worth more than six that don't.

**Done** every event in Appendix B fires; badges award on the v2 triggers; `BadgeRules` grid updated.
**Verify** `lune run tests/badge-rules.test.luau`; events visible in the Creator Hub dashboard.

---

### V20 — Profile migration v1 → v2
**Tier** Large · **Runner** 🤖 · **Deps** V19

`SchemaVersion` 1 → 2. `Stats.TasksDone` becomes `Stats.ItemsFound`; `Stats.AswangKilled` is new.

Anyone who played the v1.3 build has a profile on disk. Migration is the difference between a returning
player and a support message.

**Done** a v1 profile loads, migrates, and round-trips without loss.
**Verify** `lune run tests/profile-migration.test.luau` — v1 fixture in, v2 out, every field accounted
for, idempotent on a second read.

---

## 9. Track V5 — art and the sprite pipeline

### V21 — Sprites, dressing, and the animation tool
**Tier** Large · **Runner** 🤝 · **Deps** V16

Two halves: the map dressing v1.3 already did once, and a **new sprite pipeline** — the first chunk in
either plan where the agent generates a moving image rather than wiring one you made.

#### What the tool does

A Python script (`tools/spritegen.py`, Pillow — 3.9.6 and Pillow 11.3.0 are present) that accepts
either input:

| You supply | The tool does |
| --- | --- |
| **One still PNG** | Generates the frame strip procedurally — pulse, glow, flicker, drift, shake, rotate, scale, colour-cycle, dissolve, layered parallax |
| **A frame strip you drew** | Slices, reorders, normalises frame sizes, re-packs |

Both paths then: resize under the 1024px cap, emit the sheet, and print the `ImageRectOffset` math and
the Luau `LAYOUT` table ready to paste.

**What it cannot do: draw new content.** A still of a standing aswang cannot be made to walk. That
needs frames drawn by hand — and §3's OUT list bans character animation anyway. The line from `C26`
still holds: *if a sprite sheet ever starts describing a creature performing an action, it has been
crossed.*

#### 🧍 The step that needs you

**This chunk halts until you supply source images.** The shortlist, in value order:

1. **Salt burst** — the reveal moment, the most-seen effect in the game
2. **Smoke** — the Aswang's escape (§4.3)
3. **Feed** — must read as suggestion, not depiction (§4.9)
4. **Lantern glow** — ambient, and it sells the fog
5. **Title flourish** for the end screen — where the shareable screenshot happens

A still PNG each is enough for all five; every one is a procedural-motion case. Say which you want
hand-drawn instead and the tool takes that path for those.

#### Rules, so this does not become a performance bug

- **Sheet ≤ 1024px on its longest side.** §5's mobile budget is non-negotiable; a 4096px sheet is a
  real memory cost on a mid-range Android.
- **12–15 fps is plenty.** 30 costs battery for motion nobody sees through fog.
- **The animator stops itself when the UI is hidden.** A loop ticking during a chase is a frame cost
  with nothing on screen to justify it.
- Frame size, count and fps live in `LAYOUT` with `config-ok` reasons.
- **Upload early.** Assets sit in Roblox's moderation queue for minutes to hours, and publish day is
  not when to discover that.

**Done** the tool handles both input paths; five sheets uploaded and cycling; the barrio dressed;
mobile budget still met.
**Verify** `python3 tools/spritegen.py --self-test`; playtester screenshots each effect in-game;
frame rate measured on a real device after the dressing pass.

---

## 10. Track V6 — launch

### V22 — Anti-cheat sweep for the v2 surface
**Tier** Large · **Runner** 🤖 · **Deps** V21 · 🔒

v1.3's `C41` never ran, and v2.0 added seven remotes and three secrets it did not have.

- Every new remote in a `Config.AntiCheat` budget: `RequestSearch`, `RequestPlaceGarlic`,
  `RequestStrike`, `RequestCamouflage`, `RequestSmoke`, `RequestFeed`, `RequestDropItem`.
- **`check:ratelimit` is a text tripwire on obvious shapes and cannot follow data flow.** It will pass
  over a handler that consults `AntiCheatService` and then ignores the answer. That is what
  `exploit-auditor` is for and neither replaces the other.
- **The three v2 secrets, audited explicitly:** the container layout seed, the Aswang's health outside
  `Exposed`, and the camouflage charge state.

**Done** every remote budgeted; the three secrets confirmed server-only by an adversarial read.
**Verify** `verify` green; `exploit-auditor` on the full v2 server surface, briefed with those three
questions by name.

---

### V23–V26 — Balance, store, launch

These are v1.3's `C42`–`C45` and their substance is unchanged. Read them from git history
(`git show 6edc967:docs/BUILD-PLAN.md`) — they were correct and the rewrite does not touch them.

| | |
|---|---|
| **V23** | Playtest #2 and the balance pass. Tune until neither side wins >60%. **Plus v2's own target: "Aswang killed" lands in 10–20% of survivor wins** |
| **V24** | Store page. §13's list, with the description leading on **salt, bawang and buntot pagi** — no competitor is using them and every Filipino player recognises them |
| **V25** | Technical launch checklist. Two rows are new: a round where someone disconnects mid-round (husks gate the Aswang's win), and a round where the Aswang is killed (the rarer condition is the easier one to ship broken) |
| **V26** | Launch |

---

## 11. Track M — marketing, from today

Unchanged from v1.3 and still the longest-lead item in the project. §14.1 is right: **start posting
during the build, not at launch.** The devlog is the marketing.

v2.0 gives you better material than v1.3 did. "I rebuilt my game's entire objective system because the
missions didn't make sense" is a devlog episode. So is the loyalty-test doorway, and so is the moment
someone kills the aswang with a stingray tail.

---

## 12. Quick reference

| Want to… | Chunk |
| --- | --- |
| Remove the task game | V01 |
| Make searching work | V03, V04 |
| Make the monster feed | V06 |
| Stop camouflage leaking the role | V07 |
| Make salt matter | V05, V08 |
| Let survivors kill it | V10 |
| Stop hiding from winning | V13 |
| Know whether any of it worked | **V16** |
| Give me sprites to animate | **V21** |

**The three chunks that can silently break the game**, in order of how hard they are to notice:

1. **V13** — a gentle tracker curve makes hiding optimal and the symptom is a boring round, not an error
2. **V11 invariant 1** — a tightened number makes the second win condition unreachable, with nothing to tell you
3. **V07** — camouflage firing before a reveal deletes the deduction layer, and no test will report it
