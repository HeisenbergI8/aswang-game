# Verification: C18 (HUD) and C20 (guaranteed first objective)

**Date:** 2026-08-16
**Scope:** Working tree diff — `src/client/Controllers/UIController.luau`, `src/client/init.client.luau`,
`src/server/Services/TaskService.luau`, `src/shared/Config.luau`, `src/shared/Remotes.luau`,
new `src/client/Controllers/OnboardingController.luau`. No plan directory existed for this chunk pair;
created this one to hold the report.
**Rojo serving:** yes (`npm run preflight -- --studio` confirms `rojo-serve: ok`)
**Studio reachable:** yes — studio_id `d9a7ddea-522d-4910-82ae-4cab25f3b0f6`, place `aswang.rbxl`
**SoloTesting:** on, set by the coordinator before this run. Debug block confirmed on disk:
`Round.Intermission=8, Duration=90, EndScreen=6, Debug.SoloTesting=true, Debug.VerboseLogging=true,
Debug.ForceAswangWhenSolo=true`. I did not edit `Config.luau` and will not revert it — the coordinator owns
that.

_This file is being written incrementally during the run. Sections below fill in as evidence is gathered._

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` → "0 errors, 0 warnings, 0 parse errors" |
| lint + format | PASS | `npm run lint` and `npm run fmt:check` both exit 0, 0 errors/warnings |
| repo checks | PASS (4/5), 1 EXPECTED-RED | remotes/secrecy/config/scope/ratelimit all `ok`; `check:debug` fails on exactly the 3 debug switches the coordinator set on purpose (`SoloTesting`, `VerboseLogging`, `ForceAswangWhenSolo`) — this is `npm run verify`'s documented behaviour while those are on, not a defect |
| unit (Lune) | PASS (24/25) | `npm run test:unit` → 24 suites PASS; the one failure is `tests/config.test.luau` asserting `SoloTesting == false`, `ForceAswangWhenSolo == false`, `Duration` not left at a testing value — all 3 are the coordinator's intentional debug values, not a code defect |
| behavioural | IN PROGRESS | see below |

Full `npm run verify` chain halts at `check:debug` before reaching `test:unit`/harness because the checks
run in sequence and it exits non-zero — ran `lint`, `fmt:check`, `test:unit` individually above to get past
it. `check:guards` (harness self-test) not yet run — will run if time allows since it does not touch
Config.

## Notes in progress

- Working tree is dirty by design (debug Config values + uncommitted C17/C18/C20 work), so
  `npm run preflight -- --studio` reports `FAIL clean-tree` — expected, not a defect, since the
  coordinator asked me to test uncommitted work with uncommitted debug values.
- **Trap caught during setup**: `get_console_output` on first connection returned a full 7-round session
  history that pre-dated this run (it read "7 controllers loaded"). Starting a fresh Play session showed
  "8 controllers loaded" and the C20 print immediately — so the stale history was from before
  `OnboardingController` was wired into `init.client.luau`. Recorded so nobody trusts that old log as
  evidence of a live bug (it briefly looked like C20 was never firing across 7 rounds, which would have
  been a false finding).

### 1. HUD render across phases

**STARTING**: not separately screenshotted (4s phase, went by inside tool latency) — inferred present from
console (`[Client] Phase -> STARTING (4s)`) but not visually confirmed. Will mark NOT OBSERVED if I don't
catch it in a later round.

**ACTIVE** (round #1, artifacts/round1_active.png-equivalent — see screenshot in this turn, not yet saved
to disk since the tool returns inline images only): sunrise timer top-centre reads "UNTIL SUNRISE 0:51"
then "0:16" in red (confirms `UrgentSeconds=30` recolour works); task bar reads "TASKS 0/5"; bottom-left
status block reads "ASWANG / ALIVE salt ~0 / gate shut"; bottom-centre prompt reads "E hold a task · R
time it · Q throw salt · walk over a pouch to take it"; TRANSFORM (T) and KILL (F) buttons visible bottom
right. All five HUD regions the brief asked about are present and legible simultaneously.

**ENDING** (round #1): timer panel now reads "ENDING 0:03" (phase label swaps off "UNTIL SUNRISE"
correctly), task bar still "TASKS 0/5" behind the end-screen overlay, status block still shows
"ASWANG / ALIVE" (role has NOT cleared yet — correct, `myRole` only clears on Intermission/Idle), prompt
reads "waiting for the round to start". End screen (full-screen) reads "SUNRISE — NOBODY FINISHED" / "The
aswang was Demiurgos_18" — this doubles as the answer to item 6.

**INTERMISSION**: not yet captured cleanly — my first screenshot attempt landed 12+ seconds after
`start_stop_play`, by which point the round had already advanced past Intermission/Starting into Active
(tool round-trip latency ate the 8s+4s window). Will retry at the next Intermission.

### C20 (item 2) — waypoint within 15s of ACTIVE

Console, round #1: `[TaskService] C20 first objective for 11461085874: Task_PlazaNotice (35 studs)` —
fired in the same tick as `[RoundService] -> ACTIVE (90s)`, i.e. effectively t=0, well inside the 15s
budget.

Round #1's drawn tasks (`[TaskService] Round tasks: Task_KuboNWHearth, Task_WellPump, Task_PlazaNotice,
Task_ChapelBell, Task_KuboNELoom`) include `Task_PlazaNotice` — confirmed genuine, not invented.
Plausibility of "nearest to plaza spawn": the chosen task is literally named `Task_PlazaNotice`, which
reads as a task point in/near the Plaza where the spawn is — consistent with "nearest".

`search_game_tree` on the Client datamodel found `Players.Demiurgos_18.PlayerGui.FirstObjective`
(BillboardGui). `inspect_instance` on it confirmed `Adornee = "Workspace.Barrio.Anchors.Task_PlazaNotice"`
— the waypoint is adorned to the exact task the console named, not a different one. This is structural
confirmation; I did not get the marker inside camera frame before round #1 ended (character was still
35 studs out when ENDING hit), so the "YOUR TASK" label has not yet been visually screenshotted — retrying
in round #2/#3 below.

### 3. C20's teaching line + task completion (item 3)

Round #2 drew `Task_PlazaNotice` again, 2 studs from spawn this time. `inspect_instance` on
`Players.Demiurgos_18.PlayerGui.Onboarding.Teach` found the label already built with the exact text
`"Hold <b>E</b> to complete the task."` but `Visible:false` at the moment I checked. Given the tool
round-trip latency observed throughout this run (a nominal 4s `wait` action correlated with ~35s of
in-round clock movement — see the Known Issues section), the most likely explanation is that the line
had already appeared and auto-hidden under its own `HintSeconds=6` timer by the time I inspected it,
since the Teach label is only ever created inside `watch()`'s hintShown branch. **I was not able to
capture a screenshot of the line in its `Visible:true` state** — the 6-second window is short relative to
this tool's per-call latency. Marking the *visual* confirmation of the teach line as NOT OBSERVED, while
noting the structural evidence (correct text, correct object lifecycle) is strong circumstantial support
that it does fire.

Task completion: held E for 9s on `Task_PlazaNotice` (`HoldTime=8`) in round #3. Console:
```
[TaskService] Task complete: Task_PlazaNotice
[Task] 1/5 · here: 100%
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
```
Task bar updated to 1/5. Re-ran `search_game_tree` for `FirstObjective` immediately after completion —
**no `PlayerGui.FirstObjective` billboard exists any more** (only the `Remotes.FirstObjectiveAssigned`
RemoteEvent definition matched). This confirms the waypoint clears on completion, per `watch()`'s
`CollectionService:HasTag(point, TAG_DONE)` branch calling `clearObjective()`.

### 4. `everCompleted` sticks across rounds (item 4) — PASS, this is the core of the chunk

Round #3: player (UserId `11461085874`, Demiurgos_18) completed `Task_PlazaNotice`, which calls
`markEverCompleted` for every contributor.

Round #4 started (`[RoundService] -> ACTIVE (90s)` → `[Client] Phase -> ROUND LIVE (90s)`) and **the
`[TaskService] C20 first objective for 11461085874: ...` line that appeared at the top of every one of
rounds #1–#3 is absent from round #4's console output.** Confirmed with a second check:
`search_game_tree` for `FirstObjective` on the Client datamodel during round #4 ACTIVE returned only the
`Remotes.FirstObjectiveAssigned` definition — **no waypoint billboard was created**. This is exactly the
behaviour item 4 asks for: a veteran (someone who has ever completed a task) is not re-onboarded, even
though round #4 drew `Task_PlazaNotice` again (visible in the round's task list) and the player was
right next to it. No bug found here.

### 5. Aswang buttons (item 5)

Visible bottom-right, labelled `TRANSFORM  (T)` and `KILL  (F)`, in every ACTIVE-phase screenshot taken
(rounds #1, #2, #3, #4) while `YourState: ALIVE`. Absent from the round #1 end-screen screenshot (ENDING
phase) — the end screen fully overlays the HUD but neither button drew before/behind it, consistent with
`actions.Visible` gating on `Phase == Active`. INTERMISSION visibility not yet independently confirmed —
see Not Verified.

Clicked TRANSFORM with the mouse during round #4 ACTIVE
(`moveTo LocalPlayer.PlayerGui.Hud.Actions.Transform` → `mouseButtonClick left`). No
`[MonsterService] Refused transform for Demiurgos_18: ...` line appeared (that is the only server-side
print for a transform — a successful one is silent by design, per the comment at
`src/server/Services/MonsterService.luau:524-531`), and the client's `CameraFXController` printed
`[Client] TRANSFORM witnessed (yours)` — that print only fires on receiving the server's own transform
broadcast about this player (`src/client/Controllers/CameraFXController.luau:43`), so it is end-to-end
confirmation the click reached the server and the server actually transformed the player, not just that
the button was clickable.

### 6. End screen (item 6) — PASS

Round #1's end screen, full-screen overlay: headline **"SUNRISE — NOBODY FINISHED"** (correct — no gate
opened, matches `Enums.RoundResult.Timeout` → `describeResult`), and **"The aswang was Demiurgos_18"**
underneath, matching `nameOfAswang`'s bold-name format. Screenshotted this turn (see the ENDING/end-screen
capture in this transcript). Text is quoted verbatim above.
