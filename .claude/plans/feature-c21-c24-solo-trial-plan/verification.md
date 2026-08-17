# Verification: C21–C24 Solo Trial

**Date:** 2026-08-17
**Scope:** Working tree diff (uncommitted) — `TrialService`, `TrialController`, `TeachingService`,
`TrialAdmission`, `TrialTimeline`, `TeachingLines`, `TaskService` (TrialOnly filter), `UIController`
(C24 lobby), `OnboardingController` (ShowLine), plus `tools/greybox/barrio.luau` (trial corner geometry).
Plan: `.claude/plans/feature-c21-c24-solo-trial-plan/feature-c21-c24-solo-trial-plan.md`.
**Rojo serving:** yes — confirmed via `preflight -- --studio` (`ok rojo-serve`) and by finding
`TrialAdmission`/`TrialTimeline`/`TeachingLines` synced into `ReplicatedStorage.Shared.pure` in Studio.
**Studio reachable:** yes — `d9a7ddea-522d-4910-82ae-4cab25f3b0f6`, place `aswang.rbxl`, Play mode entered.
**SoloTesting:** off, unchanged — confirmed `false` on disk (`src/shared/Config.luau:535`) both before
and after this session. `VerboseLogging = true` was already set for me and left as-is; `Config.luau` was
not edited.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | 0 errors / 0 warnings / 0 parse errors |
| lint (selene) | PASS | 0 errors / 0 warnings / 0 parse errors |
| fmt:check | PASS | exit 0 |
| check:remotes | PASS | 28 declared, 23 wired (5 unrelated C25/later remotes declared-not-wired) |
| check:secrecy | PASS | "the Aswang stays server-side" |
| check:config | PASS | "balance stays data-driven" |
| check:scope | PASS | 17 out-of-scope shapes watched, none found |
| check:ratelimit | PASS | every OnServerEvent consults AntiCheat |
| check:debug | **FAIL (expected, not a defect)** | `Debug.VerboseLogging = true` — the coordinator's own setup for this session. `SoloTesting` is correctly `false`. Not reverted, per instruction not to touch `Config.luau`. |
| check:testcount | PASS | "suite summaries count what ran" |
| test:unit (Lune) | PASS | 28/28 files — includes `trial-admission` (147 assertions), `trial-timeline` (40), `teaching-lines` (38), `config` (50 invariants, all pass as currently written) |
| verify:harness | PASS (cached) | "harness self-tests skipped (scripts, lessons and settings unchanged since last green run)" |
| behavioural | **PASS with two confirmed defects** | artifacts below |

`npm run preflight -- --studio` also reported `FAIL clean-tree` — expected, since this plan's diff is
uncommitted working-tree state at this stage, not a defect.

## Behavioural verification

Six solo-trial sessions were run against the live place in Studio Play mode, one player, round pinned at
IDLE (`WAITING FOR PLAYERS · 2 more`, `TASKS 0/5`, `gate shut` throughout — never changed across any
session). Evidence: `artifacts/console-trial-runs.txt` (full console dump across all six runs),
`artifacts/rig-movement-log.txt` (raw position data proving the two defects below and the working stun),
`artifacts/trial-corner-inventory.txt` (pre-existing, the map geometry). Screenshots are OBSERVED NOT
ARTIFACTED throughout — `screen_capture` returns inline image data with no path to cite, the same
limitation the C17 verification in this plan directory already noted; described in prose instead.

### 1. Does a trial open at all? YES.

- One player, IDLE, below `MinPlayers`. Lobby showed a `TrialDoor` TextButton bottom-centre reading "try
  the solo run" (`Players.<name>.PlayerGui.Hud.Lobby.TrialDoor`).
- Clicking it (real `user_mouse_input` click on the actual instance) produced, in order:
  `[TrialService] <id> entered the trial` → `beat BEAT_WELCOME` → `beat BEAT_TASKS`.
- Player's `HumanoidRootPart` moved from the lobby to `(-511.5, 3.5, 465)`, inside the walled
  `TrialCorner` (floor centred at `(-465, 0, 465)` per the geometry artifact), at `TrialSpawn_Entry`.
- A `TrialSnapshot`-driven panel appeared **top-left** (`PlayerGui.Trial.TrialPanel`): "SOLO TRIAL", a
  `M:SS` countdown, "tasks 0/2", "leave the trial". Matches spec exactly.
- **Minor UX gap, not a functional bug:** the `TrialDoor` button stays visible/active/clickable while a
  trial is already running. Clicking it again is **correctly refused server-side**
  (`refused <id> a trial: ALREADY_IN_TRIAL`), so no double session is possible — but nothing tells the
  player their second click did anything, and the button doesn't reflect the state change.

### 2. Does the round stay untouched throughout? YES, on every signal I can check.

- Across all six sessions and every screenshot, the round HUD read identically:
  `WAITING FOR PLAYERS` / `2 more` / `TASKS 0/5`. The client's round-snapshot log line printed exactly
  once, at boot, and never again — consistent with the round never changing (the client logs on change).
- `Workspace.Barrio.Arko.EscapeGate` inspected mid-trial: `CanCollide = true`, `Transparency = 0` —
  physically shut, matching the HUD's "gate shut" label.
- Static confirmation: `TrialService.luau` calls exactly `RoundService.GetPhase()` and subscribes to
  `PhaseChanged`. Grepping the file for `setPhase`, `SetTasksCompleted`, `EndRound`, `MarkKilled`,
  `GetAswangUserId` — zero matches. The isolation the plan promises is real in the code, not just in
  observed behaviour.
- **Caveat:** I did not get a live server-side read of `RoundService`'s internal phase during an active
  trial. `execute_luau` on the Server datamodel re-`require()`s modules into a fresh copy with no `Init()`
  run (the documented Studio trap), so a direct read would misreport `IDLE` regardless of the real state
  and would be worthless evidence either way. The HUD, the gate's physical state, and the static code
  read are the evidence; a genuinely independent live read was not possible with the tools available.

### 3. The timeline. Beats fire, in the correct order, every run.

All six runs that reached completion fired beats in the same order:
`BEAT_WELCOME → BEAT_TASKS → BEAT_SALT_GIVEN → BEAT_TRANSFORM → BEAT_SALT_TAUGHT → BEAT_HANDOFF →
left the trial: EXPIRED`, matching `Config.Trial`'s ordering
(`SaltGivenAt=40 < ScriptedChaseAt=55 < SaltTaughtAt=58 < HandoffAt=84 < Duration=90`). Teaching lines
rendered bottom-centre via `OnboardingController.ShowLine`, e.g. "Salt burns the aswang — throw it to
reveal and stun." at `BEAT_SALT_TAUGHT`. **Not independently confirmed:** tight per-second timing
against a wall clock — ordering is solid, but tool round-trip latency (multiple seconds per call) made
sub-second timing impractical to verify precisely. One screenshot showed two teaching-line strings
overlapping at the same position, possibly a crossfade caught mid-transition; inconclusive, not reported
as a confirmed defect.

### 4. The rig — three unconfirmed behaviours, now settled.

**(a) Visible under StreamingEnabled: YES**, though dim. Two small red glowing `Eye` parts were visible
on screen against the dark trial-corner backdrop in two separate sessions (OBSERVED NOT ARTIFACTED).

**(b) Reads as moving under `PivotTo`: YES, confirmed with exact position data**
(`artifacts/rig-movement-log.txt`, "RUN A"). Polling the rig's `PrimaryPart.Position` every ~0.6s while
it approached the player showed **exactly 6.5 studs of movement per tick**, every tick — matching
`ChaseWalkSpeed (13) × SnapshotInterval (0.5) = 6.5` precisely. It does move, visibly and measurably. It
moves in discrete ~6.5-stud jumps rather than a continuous walk cycle (no Humanoid, no animation,
`PivotTo` snaps the CFrame directly) — worth knowing for feel, not a functional defect.

**(c) Stops at `ChaseStopStuds = 6` without touching the player: NO — confirmed broken, not a one-off.**
The same run showed the rig closing in and then holding perfectly steady, tick after tick (14
consecutive ticks, ~8.4s, zero drift) at:

```
rig = (-509.8, 0.4, 465.0)   player = (-511.5, 3.5, 465.0)   horizontal distance = 1.70 studs
```

**Root cause, read directly from `stepRig` (`src/server/Services/TrialService.luau` ~line 555):** the
stop check (`if flat.Magnitude <= ChaseStopStuds then hold`) only runs *before* each step. The step size
itself, `ChaseWalkSpeed * delta` with `delta = SnapshotInterval = 0.5`, is **6.5 studs — larger than the
entire 6-stud stop radius.** A rig approaching from beyond 6 studs can single-step straight through the
hold zone. Given the fixed spawn anchors (`TrialSpawn_Entry` to `TrialChase_Far`, ≈86.2 studs apart) and
a fixed 6.5-stud step, the landing distance is deterministic: `86.2 mod 6.5 = 1.70`. This is not sampling
noise — under the current committed Config values, the rig will land at 1.70 studs from the player
**every time**, not "sometimes." `tests/config.test.luau` pins `ChaseWalkSpeed < PlayerBaselineWalkSpeed`
but has no invariant relating `ChaseWalkSpeed × SnapshotInterval` to `ChaseStopStuds`, so `verify` cannot
catch this. See Failures below.

### 5. Every exit path returns the player — confirmed on the two reachable paths.

- **Clock expiry (90s):** confirmed, all six runs. `left the trial: EXPIRED`. Player teleported back to
  `(9.62, 4.0, 20.57)`, matching the original pre-trial lobby position. `Workspace.TrialAswangRig` —
  destroyed (search returns no instances). `Workspace.SaltPouches` — empty. Both teardown paths work.
- **"Leave the trial":** confirmed. The in-Studio click on the real button hit a Studio-automation
  limitation (`VirtualInput::SendMousePosition: ... hits CoreGUI` — the panel's top-left position
  overlaps Studio's own Play-mode toolbar, a tooling artifact, not a game bug). Worked around by firing
  `RequestEndTrial` from the **Client** datamodel via `execute_luau` — the exact call the button's
  `Activated` handler makes (`Remotes.Get("RequestEndTrial"):FireServer()`, no arguments), so this
  exercises the real server path rather than bypassing it. Result: `left the trial: PLAYER_ASKED`, player
  teleported back to the same lobby position. Confirmed working.
- **Round-starts-mid-trial:** NOT OBSERVED. Needs a second/third Studio client to push population past
  `MinPlayers`, which is a UI action (Test → Clients and Servers) I cannot drive. Flagged per the brief
  rather than approximated. Static reading of `endSession`'s five reasons shows `"ROUND_STARTED"` is a
  real, handled case in the code (`endSession(userId, "ROUND_STARTED")` at line 716), just not exercised.
- **Confirmed defect, both reachable paths:** the top-left `TrialSnapshot` panel is **never torn down**
  on exit. `TrialController.Start()` only clears it on receiving a push with
  `snapshot.TrialPhase == "TRIAL_OFF"`, but grepping `TrialService.luau` for the string `"TRIAL_OFF"`
  finds it **only** in the type declaration (`Types.luau`) — never fired. `endSession()` destroys the rig
  and pouch, teleports the player, and logs — it never calls `pushSnapshot` or fires `TrialSnapshot` at
  all. Reproduced on both `EXPIRED` and `PLAYER_ASKED`: the panel is left showing the session's last live
  numbers (e.g. "0:00 tasks 0/2 leave the trial") indefinitely in the lobby, with an inert "leave the
  trial" link. It only clears when a *new* trial's pushes overwrite it. See Failures below.

### The salt/stun mechanic — CONFIRMED WORKING (the specific question asked).

The known gap (the trial cannot teach the *throw* — `ItemService` gates `RequestThrowSalt` on round
phase ACTIVE, refused at IDLE — is already documented in the implementation log and not re-reported here.

**Directly tested: does carrying the pouch into the rig produce a stun? YES, clean confirmation**
(`artifacts/rig-movement-log.txt`, "RUN B"). As soon as the rig spawned (≈93 studs from the player — far
outside any stop-distance effect), the pouch was moved to 2 studs from the rig (inside
`Config.Salt.PickupRangeStuds = 6`). Result over the next four ticks (2.4s):
- the pouch was destroyed within one tick (the proximity check fires correctly), and
- **the rig did not move at all** — 93 studs from the player, where an unstunned rig would have closed
  ≈26 studs in that time (confirmed against the RUN A control, which moved 6.5 studs/tick unattended).

This isolates the stun from the (broken) stop-distance mechanic and shows it is real: reaching the rig
with the pouch genuinely halts the chase. The trial's core lesson — "salt stops the aswang" — is
mechanically true even though the throw itself isn't taught.

### 6. C24's lobby. CONFIRMED.

At IDLE, before any trial: the big number read "2 more" under "WAITING FOR PLAYERS" — never "0:00" —
across every screenshot in this session. A rotating tips panel beneath it showed varying lines (e.g. "The
aswang has to transform to kill. That is your warning.") — rotation observed, the exact 7s interval not
precisely timed. Matches the C24 fix described in the implementation log.

## Failures

### 1. The trial panel never clears after a session ends

- **New or pre-existing:** New, introduced by this plan. `TrialController`'s teardown branch
  (`if snapshot.TrialPhase == "TRIAL_OFF" then teardown()`, ~line 159) is correctly written but
  unreachable — the server never sends that phase.
- **Reproduction:** Enter a trial, then either let it expire or fire `RequestEndTrial`. Observe
  `PlayerGui.Trial.TrialPanel` afterward.
- **Observed:** Panel remains on screen with the session's last numbers and an inert "leave the trial"
  link, indefinitely, until a new trial's pushes overwrite it.
- **Expected:** The panel should disappear (or clearly indicate the session ended) once `endSession` runs.
- **Confidence:** high — reproduced on both exit paths tested (`EXPIRED`, `PLAYER_ASKED`); root cause
  confirmed by reading both sides of the contract (client condition exists and is correct; server never
  satisfies it — `grep -n "TRIAL_OFF" TrialService.luau` returns nothing).

### 2. The chase rig overshoots `ChaseStopStuds` and lands ≈1.7 studs from the player, deterministically

- **New or pre-existing:** New — this plan's `Config.Trial` numbers (`ChaseWalkSpeed = 13`,
  `SnapshotInterval = 0.5`, `ChaseStopStuds = 6`).
- **Reproduction:** Let a solo trial reach `ScriptedChaseAt` (55s) and run un-intercepted; poll
  `Workspace.TrialAswangRig.HumanoidRootPart` and the player's position a few ticks later. Raw data:
  `artifacts/rig-movement-log.txt`, "RUN A".
- **Observed:** Rig held at horizontal distance ≈1.70 studs from the player for 14 consecutive ticks
  (~8.4s) — well inside the intended 6-stud stop radius.
- **Expected:** Per the plan's own design comment ("stops at `ChaseStopStuds`, holds... never touches the
  player"), the rig should never come closer than 6 studs.
- **Why:** `stepRig` advances the rig by `ChaseWalkSpeed × delta` per tick
  (`delta = Config.Trial.SnapshotInterval = 0.5`), i.e. up to 6.5 studs — larger than the 6-stud stop
  radius itself — and the stop check only runs before the step. A rig approaching from just past 6 studs
  steps straight through the hold zone. `tests/config.test.luau` has no invariant relating
  `ChaseWalkSpeed × SnapshotInterval` to `ChaseStopStuds`, so nothing in `verify` catches it.
- **Confidence:** high — both the arithmetic (6.5 > 6, unconditional given the committed numbers) and the
  empirical measurement (exact, reproduced, held steady across many ticks) agree. Given the fixed spawn
  geometry, this isn't occasional — it is the rig's actual landing distance every time under current
  Config.
- **Suggested fix (for the record; not applied — I do not edit source under test):** shrink
  `ChaseWalkSpeed` or `SnapshotInterval` so the per-tick step stays under `ChaseStopStuds`, or clamp the
  step in `stepRig` so it moves to exactly `ChaseStopStuds` away rather than by the full step vector when
  a step would cross the threshold.

## Not Verified

- Fine-grained timing of each beat against its exact configured second (ordering confirmed across six
  runs; sub-second timing not measured due to tool round-trip latency).
- Whether the rig's 6.5-stud discrete jumps *feel* like walking to a player vs. a stutter/snap — motion
  is confirmed to occur, the qualitative "reads as moving" judgment is closer to a playtest call.
- Round-starts-mid-trial (needs 2–3 Studio clients; player count is a UI action I cannot drive). The
  `"ROUND_STARTED"` exit path exists in code and is exercised by nothing in this session.
- Resumption after the 6-second stun window (`Config.Trial.ChaseStunSeconds = 6`) — confirmed the stun
  engages and halts movement for at least 2.4s; did not poll long enough to confirm the chase resumes
  afterward rather than staying frozen permanently.
- The one overlapping-teaching-lines screenshot — inconclusive, not confirmed as a defect.
- Whether a second/third client can ever observe another player's trial state (the design fires
  `TrialSnapshot` via `FireClient` only to session participants, and `TrialService` is read as sound on
  this by static review) — not independently confirmed with a second live client.

## Artifacts

- `artifacts/trial-corner-inventory.txt` — pre-existing, the map geometry structural dump.
- `artifacts/console-trial-runs.txt` — full console output across all six solo-trial sessions in this run.
- `artifacts/rig-movement-log.txt` — raw position-polling data proving both confirmed defects and the
  working salt-stun mechanic.
