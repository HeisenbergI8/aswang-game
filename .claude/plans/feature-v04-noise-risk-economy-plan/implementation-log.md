# V04 — Noise: the risk economy — implementation log

Plan: `feature-v04-noise-risk-economy-plan.md`, bound to run `2026-08-27T13-40-11-951Z-V04`.

---

## Phase 1 — The model and the numbers

**Status:** complete. All four step checks green.

### Step 1.1 — `Config.Noise`, and `Search.NoiseRadius` aliased into it

`src/shared/Config.luau:88-155` — the hoisted `Noise` local, added between the `Items` block and
`local Config = {`. `src/shared/Config.luau:414-431` — `Search.NoiseRadius` is now
`Noise.Actions.SEARCH.Radius` rather than a second literal `60`, and `Noise = Noise` joins the
returned table beside `Search`.

**Verify:** `npm run analyze` → `- analyze: ok`

The analyzer caught the half-done state on the first write: with the local declared but neither the
alias nor the table entry in place, `gate-luau-analyze.mjs` blocked on
`LocalUnused: Variable 'Noise' is never used`. That is the plan's own second Phase 1 issue —
*"`Noise` must be added to the returned table, not just declared as a local"* — firing as an analyze
error at write time rather than as a runtime nil in Phase 2.

### Step 1.2 — `NoiseAction` in `Types.luau`

`src/shared/Types.luau:581-590` — the four-id literal union, declared after `SearchUpdatePayload`.
The record shape deliberately does **not** go here; `NoiseLog.Record` (Step 2.1) will be its single
definition, following V03's `ContainerLayout.Layout` precedent.

**Verify:** `npm run verify:fast` → analyze ok · remotes ok (25 declared, 25 wired) · secrecy ok

### Step 1.3 — `NoiseModel` and the action × state grid

New: `src/shared/pure/NoiseModel.luau`, `tests/noise-model.test.luau`.

`evaluate(action, state, tuning) -> Emission?` and `quantise(position, gridStuds)`. No `script.Parent`
require, no Roblox datatype, no role or form parameter.

**Verify:** `lune run tests/noise-model.test.luau` → **172/172 checks passed**

The grid walks 4 actions × 12 speeds, including the four values a naive comparison waves through.
`finiteSpeed` normalises NaN and ±inf to 0 before the threshold comparison — without it
`nan < threshold` is `false` and a NaN speed would emit.

### Step 1.4 — eight invariants pinned in `tests/config.test.luau`

`tests/config.test.luau:768-856`, appended before the `if failures > 0` guard.

**Verify:** `lune run tests/config.test.luau` → **PASS config: 107 balance invariants** (was 99)

At committed values: worst case `5 × 120/2 = 300` ≤ `MaxRecords 512`; `SprintSpeedStuds 22` >
`16 × 1.25 = 20`; `CueGridStuds 8` < `LateRadius 15`; `HistorySeconds 120` ≥ `EarlyInterval 90`;
`SEARCH.MinInterval 6` ≥ `SearchTime 6`; `SEARCH.Radius 60` > `EarlyRadius 40`.

**The anti-oracle guard was proven falsifiable, not assumed.** `SprintSpeedStuds` was temporarily set
to 19 and the suite went red with the exact diagnostic —
`FAIL no speed this game can produce crosses the sprint threshold — SprintSpeedStuds=19, fastest=20`
— then reverted to 22 and re-run green. This is the one invariant standing between a later movement
emitter and a noise history that fires for exactly one player, so a vacuous check here would be worse
than no check.

### Notes carried forward

- **StyLua rewrapped both test files** after writing, as the plan's Phase 1 issue note predicted.
  `npm run fmt` was run at the end of the phase; `fmt:check` is clean.
- **Nothing was pulled forward.** No emitter, no service, no remote — SPRINT and DOOR are priced in
  `Config.Noise.Actions` and wired by nothing, which is Phase 1's intent and the Overview's answer to
  question 2.
- **Stale comment spotted, not fixed** (out of scope): `src/shared/Config.luau:572` says
  "At `Round.MaxPlayers = 8` a maximal round is five" while `Round.MaxPlayers` is 5. Pre-existing,
  in the `Economy` block, untouched by V04.

---

## Phase 2 — The recorder

**Status:** complete.

### Step 2.1 — `NoiseLog` and its bound

New: `src/server/pure/NoiseLog.luau`, `tests/noise-log.test.luau`.

`shouldRecord` / `append` / `recentSince` / `withinRadius`. In `server/pure/` — the mirror of
`NoiseModel`'s placement: no client caller now or ever, so the smaller surface is free.

**Verify:** `lune run tests/noise-log.test.luau` → **24/24 checks passed**

The flood case is the one that matters: 6000 appends at ten a second for ten simulated minutes, an
emit rate the throttles make impossible. Peak length stayed at or under the 512 cap and the oldest
survivor stayed inside the 120s window, so "bounded" is arithmetic here rather than a comment.

### Step 2.2 — `NoiseService` and the bootstrap entry

New: `src/server/Services/NoiseService.luau`. `src/server/init.server.luau:29-40` — registered
between `MonsterService` and `ItemService`, before `RoundService` starts last.

**Verify:** `npm run check:config` → `- config: ok (balance stays data-driven)`

**The plan's named most-likely defect is not present.** It warned that `NoiseLog.append(history, …)`
without reassigning would typecheck, run, and silently record nothing.
`src/server/Services/NoiseService.luau:137` is `history = NoiseLog.append(...)`.

### Step 2.3 — the V13 seam

`NoiseService.GetRecent` and `RecordCount`, returning copies. Two functions and no tracker logic —
no curve, no interval, no pulse.

**Verify:** `npm run verify:fast` → analyze ok · remotes ok · secrecy ok

**The no-role-branch rule was checked mechanically, not just asserted.** Grepping
`GetAswangUserId|Aswang|Role|Transformed` across `NoiseService`, `NoiseLog` and `NoiseModel` returns
hits only inside comments forbidding them — no code branch in the noise system reads a role.

---

## Phase 3 — The emitters

**Status:** complete.

### Step 3.1 — `SEARCH` at the start of a hold

`src/server/Services/SearchService.luau:325-345`, plus the require at line 41.

Emitted in `beginHold` **at the start, not at completion** — a search cancelled at 5.9s has still
happened, and a noise waiting for `SEARCH_OK` would make start/cancel free silent reconnaissance.
Positioned at the container, which the server resolved itself.

**Verify:** `npm run analyze` → ok

The analyzer caught the missing require immediately (`Unknown global 'NoiseService'`).

### Step 3.2 — `ITEM_USE` on a resolved throw

`src/server/Services/ItemService.luau:777-795`, plus the require at line 32.

Placed below the line that spends the pouch and **above the hit branch**, so it fires identically on
`OK` and on `MISS`. A noise that fired only on `OK` would rebuild the identity oracle
`pure/SaltThrow`'s single `MISS` verdict exists to prevent — throw a pouch, listen, learn what the
return value refuses to say.

**Verify:** `npm run verify` → **full gate green**, 31 test files, all five repo checks ok.

---

## Phase 4 — The cue

**Status:** complete.

### Step 4.1 — `NoiseCue` declared

`src/shared/Remotes.luau:107-131` (EVENTS_DOWN), `src/shared/Types.luau:592-621`
(`NoiseCuePayload`).

**Verify:** `npm run verify:fast` → `remotes: ok (26 declared, 25 wired) — 1 declared but not yet
wired: NoiseCue`

That is the step's predicted state: `check:remotes` flags a declaration with no use but passes, which
is exactly why the plan made Step 4.2 the first checkable direction rather than this one.

### Step 4.2 — dispatch

`src/server/Services/NoiseService.luau:79-160` (`dispatchCue`, `rootOf`), called at line 219.

Per-listener `FireClient` after a server-side radius test — never `FireAllClients`. Position
quantised **once** before the loop, so two colluding clients cannot average their copies back toward
the truth. The radius test runs against the **true** position, not the quantised one, so the audible
edge does not move by half a cell.

**Verify:** `npm run check:secrecy` → ok. `check:remotes` now **26 declared, 26 wired**.

### Step 4.3 — the phase rule and the asset slots

`src/shared/pure/AudioCues.luau` — `CUE_NOISE` / `CUE_NOISE_SELF` in `PERMITTED_PHASES`, and
`MONSTER_CUES` renamed to `ROUND_ONLY_CUES` with both ids added. `src/shared/Config.luau` — two blank
asset slots and `NoiseVolume` / `NoiseSelfVolume`.

**Verify:** `lune run tests/audio-cues.test.luau` → **46/46**

`tests/config.test.luau` went **107 → 111 invariants** without being edited, because its existing
bidirectional `Config.Audio.Assets` ↔ `AudioCues` cross-check picked up the new slots. That is the
plan's "both edits must land together" note proving itself.

### Step 4.4 — the client

`src/client/Controllers/AudioController.luau` — `playNoiseCue` (positional, at the quantised cell,
rolloff re-derived from `NoiseModel`) and `onNoiseCue` (branches on `Mine`), wired in `Start`.

**Verify:** `grep -q playNoiseCue src/client/Controllers/AudioController.luau` → exit 0

**That check proves the symbol exists, not that a sound came out**, and the plan says so in the step
itself. The assets are deliberately blank — `AudioController.logCue` is how the cue is proven to FIRE
before anything is sourced. The real evidence is the playtester's.

### Notes carried forward

- **`npm run verify` is green after all four phases.** 31 test files; analyze, lint, fmt, remotes
  (26/26), secrecy, config, scope, ratelimit and debug all ok.
- **Two of the four priced actions still have no emitter,** and that is the plan working rather than
  an omission: `DOOR` has no door in `src/`, and `SPRINT` has no movement verb — wiring one on a
  speed threshold is the oracle described in the plan's Overview.
- **`npm run verify` reports `candidates: 77 (30 high) — REVIEW DUE`.** Pre-existing and unrelated to
  V04; `/lessons-review` is the follow-up.

---

## Review round — three reviewers, three fixes applied

`auditor` **78/100** · `exploit-auditor` **85/100** · `playtester` — primary objective confirmed.

All 13 steps traced with no undocumented deviations. No client path to the Aswang's identity found
across seven attack questions. The build plan's V04 Verify line — *"the cue fires on a search and not
on a walk"* — is confirmed in both halves; see `verification.md` and `artifacts/`.

### Fix 1 — the bound invariant computed the wrong worst case (real defect, mine)

`tests/config.test.luau`, `src/shared/Config.luau` (`MaxRecords` 512 → 2048).

Step 1.4's check divided `HistorySeconds` by the SMALLEST `MinInterval`. The throttle is keyed
`(UserId, action)` — `NoiseService.lastEmitAt`, whose own comment says so — so a player emits every
action concurrently and the worst case is the **sum across actions**, not the fastest row.

The exploit audit proved it by simulation against the real `NoiseLog.append`:

| Wired actions | old check said | true peak | old cap |
| --- | --- | --- | --- |
| SEARCH + ITEM_USE | 300 | 410 | 512 ok |
| + DOOR | 300 | 512 — **truncating** | 512 red |
| + SPRINT | 300 | 512 — **truncating** | 512 red |

Safe at the time, and reporting 37% of headroom that did not exist. A door emitter would have started
eating the history window with `npm run verify` still green — the exact silent failure the check was
written to prevent.

**The fix sums over every PRICED action, not only the wired ones**, and includes the `+ 1` fencepost
(a window at `MinInterval` spacing holds `floor(H/I) + 1`, which is the 410-vs-400 gap the simulation
measured). Corrected worst case: `5 × ((120/6+1) + (120/2+1)×3)` = **1020**. `MaxRecords` raised to
2048 rather than 1020 — a safety net sized to its exact worst case is one rounding change from being
the binding constraint.

**Proven falsifiable, not assumed:** at `MaxRecords = 900` the suite reds with
`worst case=1020`; at 2048 it passes.

### Fix 2 — `quantise` failed open on a non-positive grid

`src/server/Services/NoiseService.luau` — `math.max(Config.Noise.CueGridStuds, 1)` at the call site.

`NoiseModel.quantise` returns the position UNCHANGED for a grid ≤ 0. That is defensible in a pure
module that must not error inside a dispatch loop, and the wrong direction for the one caller that
puts the result on the wire — `CueGridStuds = 0` would ship exact positions. It was already defended
by a `config.test.luau` check, but that guards the value in a different file while this is the line
that would leak. Clamped at the sender; the pure module's contract is unchanged.

### Fix 3 — the universal-action precondition is now a contract at `Emit`

`src/server/Services/NoiseService.luau` — a boxed rule in `Emit`'s header.

The audit's Medium finding, and it sharpens something V04 under-stated. The payload carries no actor,
but **characters replicate** — any client can match a cue's cell against live `HumanoidRootPart`
positions and attribute the noise (measured: an 8×8×8 box, through walls, to the full 60 studs). So
the real defence is *which actions emit*, not the payload's shape, and that invariant lived only in
prose in `Remotes.luau`.

Harmless today because SEARCH and ITEM_USE are universal. **It stops being harmless the first time a
monster-only action emits** — a feed (V06), camouflage or smoke (V07) would be a role oracle with no
role token in it, invisible to `check:secrecy`. The rule now sits where a caller adding an emitter
will read it.

### What is NOT established

- **Items 4 and 5 of the playtest brief** — history clears between rounds, and the outside-ACTIVE
  gate — were not proven behaviourally. Studio MCP round-trip latency was large relative to the 32s
  debug round cycle, so a second timed search could not reliably be landed inside one ACTIVE window.
  Both are covered by unit tests and by reading; neither was observed.
- **The `Mine = false` path was never exercised.** A solo test has one player, so every captured cue
  had `Mine = true`. The positional `CUE_NOISE` client path and the Aswang/survivor symmetry both
  need a second client.
- **`StreamingEnabled` and the client-created anchor Part** remain `⚠ UNCONFIRMED`, as the code
  comment already says, inherited from `QuickChatController.renderPing`.

### Gate after the fixes

`npm run verify` green: analyze, lint, fmt, remotes 26/26, secrecy, config, scope, ratelimit, debug,
31 test files.
