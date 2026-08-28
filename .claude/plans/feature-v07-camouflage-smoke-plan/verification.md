# Verification: V07 — Camouflage and smoke

**Date:** 2026-08-28 (two sessions: an initial pass, then a scoped re-run after the coordinator added
`Config.Debug.ForceAswangWhenSolo = true`)
**Scope:** `.claude/plans/feature-v07-camouflage-smoke-plan/` — all six phases, as implemented on
`v2-rewrite` (base `64d0cfa`). Files: `src/shared/pure/CamouflageRules.luau`,
`src/shared/pure/AmbientRoster.luau`, `src/server/Services/AmbientService.luau`,
`src/server/Services/MonsterService.luau`, `src/server/Services/ItemService.luau`,
`src/client/Controllers/SmokeController.luau`, `src/client/Controllers/InputController.luau`,
`src/client/init.client.luau`, `src/server/init.server.luau`, `src/shared/Config.luau`,
`src/shared/Remotes.luau`, `src/shared/Types.luau`.
**Rojo serving:** yes — `preflight -- --studio` reported `rojo-serve` ok, `rojo-attached` ok,
`rojo-synced` ok (session blessed). The only preflight failure was `clean-tree`, expected because
this run's own changes are what's being verified.
**Studio reachable:** yes — one Studio instance (`aswang.rbxl`), driven through Play mode.
**SoloTesting:** on (`Config.Debug.SoloTesting = true`, `VerboseLogging = true`,
`Round.Intermission = 8`, `Duration = 20`, `EndScreen = 6`, and — added mid-task by the coordinator —
`ForceAswangWhenSolo = true`) — set by the coordinator before/during this run, per the brief. Before
relying on the sixth value I confirmed it live in the running DataModel (`execute_luau`, Server,
reading the required `Config` module directly) rather than trusting the file on disk; see
`artifacts/aswang-pre-reveal-gate.log`. **Not reverted by me** — `Config.luau` is out of my write
scope (`guard-agent-write.mjs`); the coordinator confirms the revert of all six with
`git diff src/shared/Config.luau`.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `analyze: ok` — 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | `check:remotes` ok, part of `npm run verify` output below |
| repo checks | 6/7 PASS, 1 expected FAIL | `remotes: ok (31 declared, 31 wired)`, `secrecy: ok`, `config: ok`, `scope: ok`, `ratelimit: ok`; `debug: 2 finding(s)` — `Debug.SoloTesting`/`Debug.VerboseLogging` both `true`, which is the coordinator-set state this brief asked me to verify against, not a regression |
| unit (Lune) | 34/35 PASS | `test:unit` reports `1/35 file(s) failed` — the failure is `tests/config.test.luau`, and it fails for the same reason as `check:debug`: `SoloTesting` must be `false`, `Duration=20s` is a testing value. This is `check:debug`'s own companion assertion firing, not a defect |
| unit — V07-specific | PASS | `lune run tests/camouflage-rules.test.luau` → `385/385 checks passed`; `lune run tests/ambient-roster.test.luau` → `78/78 checks passed` — both match the implementation log's claimed counts exactly |
| behavioural — ambient population | PASS | `artifacts/ambient-population-console.log` |
| behavioural — camouflage refused pre-reveal (survivor negative) | PASS | `artifacts/survivor-remote-gate-negative.log` |
| behavioural — camouflage refused pre-reveal (**Aswang positive**) | PASS | `artifacts/aswang-pre-reveal-gate.log` |
| behavioural — smoke refused pre-reveal (**Aswang positive**) | PASS | `artifacts/aswang-pre-reveal-gate.log` |
| behavioural — smoke draws/expires (post-reveal) | **NOT RUN** — needs a real salt hit, needs a second client | see Not Verified |
| behavioural — head count invariant under a real camouflage swap | **NOT RUN** — same blocker | see Not Verified |

## Static verification detail

```
npm run verify
- analyze: ok (0 errors, 0 warnings, 0 parse errors)
- remotes: ok (31 declared, 31 wired)
- secrecy: ok (the Aswang stays server-side)
- config: ok (balance stays data-driven)
- scope: ok (19 out-of-scope shapes watched)
- ratelimit: ok (every OnServerEvent consults AntiCheat)
  FAIL  src/shared/Config.luau — Debug.SoloTesting = true, must be false
  FAIL  src/shared/Config.luau — Debug.VerboseLogging = true, must be false
- debug: 2 finding(s)
```
`verify` stops at `check:debug` by design (the pipeline is `&&`-chained), so `check:testcount`,
`test:unit` and `verify:harness` did not run inside that single invocation. I ran them separately:

```
npm run test:unit    → 34/35 files ok; failure is tests/config.test.luau (3 invariants violated,
                        all three naming the same coordinator-set debug values: SoloTesting,
                        Duration=20s, session-retry timing). Every other file, including
                        camouflage-rules and ambient-roster, passed.
lune run tests/camouflage-rules.test.luau → 385/385 checks passed
lune run tests/ambient-roster.test.luau   → 78/78 checks passed
lune run tests/config.test.luau           → 3 balance invariant(s) violated (the expected debug-value
                                             failures above)
```

This matches the implementation log's Phase 6 gate exactly, modulo the two findings this brief's own
debug values are expected to produce. Static verification is otherwise fully green; nothing in this
diff introduced an analyzer, lint, format, remote, secrecy, config, scope or rate-limit regression.

## Behavioural verification

### 1. The ambient population exists and wanders — PASS

`Workspace.AmbientLife` holds exactly 16 `Model` children, named `Ambient_CAT_1`…`Ambient_CAT_4`,
`Ambient_DOG_5`…`Ambient_DOG_8`, `Ambient_PIG_9`…`Ambient_PIG_12`, `Ambient_VILLAGER_13`…
`Ambient_VILLAGER_16` — exactly `Config.Ambient.PerForm * 4 = 16`, exactly the naming scheme the
implementation log describes.

Confirmed the map has no `AmbientSpawn`-tagged parts (`search_game_tree` in Edit mode, before
Play, found zero matches for `AmbientSpawn`/`AmbientLife`), so the 16 models in Play mode are
provably the fallback ring, not a map-authored placement — the code path the plan says is scaffolding
until Step 3.5 (a human tagging job) happens.

Wander confirmed by reading `Ambient_CAT_1.Body`'s `CFrame.Position` twice, ~90 seconds of wall
clock apart, with no player input directed at it: `(60.78, 3, 18.83)` → `(51.61, 3, 17.57)`, a ~9.4
stud move. The Heartbeat wander loop is running.

**Evidence:** `artifacts/ambient-population-console.log`

### 2. Camouflage refused before a salt hit — PASS

Originally blocked in the first session for a reason that turned out to be the brief's own gap, not a
defect: `RoleService.luau:178-185` only draws the lone solo player as the Aswang when
`Config.Debug.SoloTesting AND Config.Debug.ForceAswangWhenSolo AND #candidates <= MinPlayers`, and the
initial five coordinator-set values omitted the sixth. The coordinator added
`Config.Debug.ForceAswangWhenSolo = true` and I confirmed it live in the running DataModel before
relying on it (see `artifacts/aswang-pre-reveal-gate.log`) — `RoleService`'s own console line
(`DEBUG — Aswang FORCED to Demiurgos_18 (roster 1 <= MinPlayers 3)`) then confirmed it on every one
of five subsequent round draws, not just the first.

With that in place: transformed with **T**, pressed **C**. Result, captured in a `screen_capture`
while still transformed:
- HUD panel reads **"ASWANG"**, **"ALIVE"**
- the exact on-screen line **"They have to see you first."**
- the server verdict, recorded by a client-side `OnClientEvent` listener on `CamouflageUpdate`:
  **`CAMO_NOT_REVEALED`**
- `RequestCamouflage` fired with **zero arguments**, confirmed by a server-side recorder
  (`argCount=0`)

**The two negatives the coordinator called "the actual point" both held**, read via `execute_luau`
within the same few hundred milliseconds as the screenshot: `workspace.AmbientLife` still held
**16** models, and the player's own `Character` was still parented to `workspace`
(`playerCharacterInWorkspace=true`). No avatar vanished, no head count moved. This is the outcome
that matters most in this chunk, and it held.

Reproduced across three separate requests in three different rounds (two earlier, slightly mistimed
attempts where the request landed just after an automatic round-end revert, and the clean round-4
capture described above) — same verdict every time, which rules out a race rather than raising one.

**Evidence:** `artifacts/aswang-pre-reveal-gate.log`

### 3. The reveal opens the gate — PASS for the pre-reveal half; post-reveal remains NOT RUN

The remote-wiring probe now has both directions on record. **Negative (Survivor):** pressing C and G
as a Survivor produced zero calls to either `OnServerEvent` — `InputController`'s local role gate
(`InputController.luau:88-109`) never lets a non-Aswang's client send either up-remote, matching Step
5.1's "no verdict on the wire for a player who is not the monster" design.
**Positive (Aswang, unrevealed):** covered under item 2 above for Camouflage
(`RequestCamouflage` fires with 0 args, server replies `CAMO_NOT_REVEALED`). For **Smoke**: pressed
**G** while transformed and unrevealed. `RequestSmoke` fired with **zero arguments**
(server recorder: `argCount=0`), but — correctly — **nothing came back**: the client's
`SmokeBurst.OnClientEvent` listener received **zero** payloads. Reading
`MonsterService.luau:1603-1650` (`validateAndSmoke`) confirms this is by design: unlike Camouflage,
a refused smoke request just `return`s with no reply at all, so "fired but silent" is the correct
positive-case signature for an unrevealed Aswang, not a missing feature. A `search_game_tree` sweep
for "smoke"/"cloud" after the attempt found no gameplay instance anywhere in the tree — only unrelated
Roblox engine/debugger items and the two `Remotes` objects — confirming no cloud was ever drawn.

**What remains NOT RUN, and why it cannot be reached from this session at all:** the reveal itself.
`HasBeenRevealed` is set in exactly one place (`MonsterService.ApplySaltHit`), which fires only when
a **salt throw lands on the Aswang** — and that requires a second connected client to throw the salt.
`ForceAswangWhenSolo` does not help here; it only changes who gets drawn as the monster, and does not
manufacture a second player. I also confirmed I cannot fake this through `execute_luau`: a fresh
`Server`-datamodel `require(MonsterService)` returns an un-`Init()`'d copy with its own private
`monsters` table, so calling `ApplySaltHit` there would mutate a throwaway copy, not the live monster
record the real handlers read from. So the reveal-gated behaviours — a successful camouflage, a real
smoke cloud, the swap-not-spawn head count under an actual claim — stay genuinely out of reach without
a human on Test → Clients and Servers → 2 players.

**Evidence:** `artifacts/survivor-remote-gate-negative.log` (negative/Survivor case),
`artifacts/aswang-pre-reveal-gate.log` (positive/Aswang, both abilities, pre-reveal)

### 4. Smoke draws and expires — NOT RUN

Requires a **revealed** Aswang (`evaluateSmoke` sits behind the same reveal flag per Step 1.3), which
requires a real salt hit landing, which requires a second connected client to throw it. Confirmed the
*pre*-reveal half instead (item 3): `RequestSmoke` fires correctly and is correctly refused with total
silence — no `SmokeBurst`, no cloud instance anywhere in the tree. Out of reach beyond that in this
solo session, regardless of `ForceAswangWhenSolo`. No screenshot of an actual cloud taken because that
state was never reached.

### 5. The head count does not move — PASS for the unclaimed state; NOT RUN for a real claim

Confirmed twice over, in both sessions: `workspace.AmbientLife` held exactly 16 models continuously
across the first session's four round boundaries and ~90 seconds of wander, and again across the
second session's five round boundaries including three refused Camouflage attempts as the (forced,
transformed, unrevealed) Aswang — the count was re-read via `execute_luau` within the same round as
the refusal each time and never moved from 16.

What remains unproven is the actual swap-not-spawn invariant this item names — the count holding
**through a successful claim**, i.e. one entity parked into `ServerStorage` while the other 15 stay
in `workspace.AmbientLife`, count still 16. That needs a revealed Aswang, same blocker as item 4.

## Failures

None found. Everything I was able to run — static checks, both V07 unit suites, the ambient
population's existence/naming/wander, and the client-side role gate in both directions (Survivor
negative, Aswang positive for both abilities, pre-reveal) — passed exactly as the implementation log
and the plan's §4.3 design describe.

## Not Verified

- **Smoke drawing/expiring visually, and the head-count invariant across a real camouflage swap**
  (post-reveal halves of items 4 and 5). Both require a **revealed** Aswang, which requires a real
  salt hit landing on the monster, which requires a second connected client throwing it —
  `ForceAswangWhenSolo` does not unblock this, per the trap named in my own agent brief (it changes
  who is drawn as Aswang, it does not add a second player, and nothing here is reachable by faking
  state through `execute_luau` since a fresh Server-datamodel require does not touch the live
  `MonsterService` record — confirmed directly this session). This needs
  Test → Clients and Servers → 2 players, driven by a human.
- **`MinPlayers` behaviour, mid-round join/leave, and anything else needing a second client** — out of
  scope for this solo session for the same reason, named up front rather than approximated.
- **The particle look of the smoke cloud (Step 6.5)** — explicitly a human step per the plan, no
  `**Verify:**` line, `verify-plan` reports it `needs-human`. Not attempted here.
- **The map's `AmbientSpawn` tagging (Step 3.5)** — also explicitly a human step; confirmed its
  absence (see item 1) rather than attempting it.

---

## CRITICAL CONFIRMED AT RUNTIME — the camouflage swap is client-observable

**Date:** 2026-08-28, driven directly via Studio MCP against the live Play session.
**Question:** does `AmbientService.ClaimSlot`'s reparent to `ServerStorage` produce a client-visible
removal? This was the load-bearing premise of the `exploit-auditor`'s Critical, reasoned from
replication rules but **not previously observed**.

**It does. Observed, not inferred.**

### Method

`require` from `execute_luau` returns a **fresh module copy**, not the live service — proven first:

```
AmbientService reached. VisibleCount CAT=0 DOG=0   (4 each = live instance, 0 = fresh copy)
```

So `ClaimSlot` could not be called directly. Instead the **exact operation the shipped code performs**
(`model.Parent = parked`, `AmbientService.luau:226-232`, parked folder at `:417`) was applied to the
**real** Model the live service spawned.

### Baseline

```
SERVER count=16 first=Ambient_CAT_1
CLIENT count=16 Ambient_CAT_1 present=true pos=58.286, 3, 23.188
```

### The exploit, armed on the client exactly as an attacker would write it

```lua
workspace.AmbientLife.ChildRemoved:Connect(function(m)
    -- m:GetPivot().Position
end)
```

### Result after the reparent

```
SERVER: reparented Ambient_CAT_1 to ServerStorage.AmbientParked | AmbientLife 16 -> 15
CLIENT count=15 | Ambient_CAT_1 present=false | events captured=1
  REMOVED Ambient_CAT_1 at 46.014, 3, 20.102 (count now 15)
```

**The client received the removal and the position.** In the shipped flow `enterCamouflage` then pivots
the Aswang's character to that same CFrame (`MonsterService.luau:333-337`), so the leaked coordinate is
where the monster is standing.

Two separate leaks, both from one event:
- **Position** — exact, to the stud, map-wide, at the instant of the hide. New information in every
  case, including after the reveal.
- **A hiding bit** — `#workspace.AmbientLife:GetChildren()` dropping below 16 means "someone is
  camouflaged right now", readable with no event hook at all.

`tests/ambient-roster.test.luau` asserts `visibleCount` is invariant across a claim — 78 assertions,
all passing, over the **roster** count. The number a client reads is
`#workspace.AmbientLife:GetChildren()`. The suite is thorough about a quantity no attacker observes.

### State restored

`Ambient_CAT_1` returned to `workspace.AmbientLife`; count back to 16. The `_G` listener dies with the
play session.

### Still NOT established

The full camouflage flow end-to-end — the reveal via a real salt hit, a successful hide, and whether
`PivotTo` holds against client network ownership. Those need two connected clients and remain open.
