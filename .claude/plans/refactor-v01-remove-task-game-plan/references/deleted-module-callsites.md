# Inventory — every inbound reference to every module V01 deletes or renames

Tree at `79e5fb5` (v2-rewrite). Compiled from `grep -rn` over `src/` and `tests/`, then split by hand
into **CODE** (a `require`, a call, a type reference, a bootstrap list entry — breaks the build or the
game if left) and **PROSE** (a mention inside a comment — invisible to `analyze` and to every check,
but caught by Step 5.8's residue sweep and by any reader trying to understand the file).

The distinction matters for phasing: CODE decides which step a file belongs to; PROSE decides how much
rewriting that step actually contains. Several files here are 100% PROSE and are still edits.

---

## Legend

| | |
|---|---|
| **CODE** | must change or the tree is red / the game is wrong |
| **PROSE** | comment only; `analyze`, `lint` and the five checks are all blind to it |
| †  | the referencing file is itself deleted by this plan — no action beyond its own deletion |

---

## 1. `src/server/Services/TaskService.luau` (1806 lines) — DELETED, Step 2.3

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/init.server.luau:29` | `"TaskService"` in `SERVICE_ORDER` |

That is the **entire** inbound code surface. No surviving module `require`s it — the bootstrap resolves
services by `servicesFolder:FindFirstChild(name)` (`init.server.luau:80`) and only `warn`s on a miss, so
a stale entry is invisible to `analyze`. That is why Step 2.3 binds the deletion and the list edit into
one step.

### CODE — outbound (calls INTO surviving modules that stop happening)

| Site | Call | Consequence |
|---|---|---|
| `TaskService.luau:1095` | `ProgressionService.BumpStat(player, "TasksDone", 1)` | `Stats.TasksDone` stops incrementing — see Follow Up 4 |
| `TaskService.luau:1448` | `ProgressionService.BumpStat(player, "TasksDone", 1)` | same, second guard site |
| `TaskService.luau:1171` | `TeachingService.Cue(standing, "CUE_FIRST_TWO_PERSON")` | last firer of that cue id — Step 5.6 |
| `TaskService.luau:1666` | `Remotes.Get("FirstObjectiveAssigned")` | last producer of that remote — Step 4.4 |
| — | `RoundService.SetTasksCompleted` / `GetPlayerState` / `GetPhase` | `SetTasksCompleted` loses its only caller — Step 3.2 |

### PROSE — inbound (comment mentions in files that survive)

`src/server/Services/BadgeService.luau:242` · `ProgressionService.luau:80, 887` ·
`TeachingService.luau:9, 49` · `ItemService.luau:16, 22, 49, 78, 88, 96, 177` ·
`TrialService.luau:126, 324, 325, 338, 339` · `RoundService.luau:657, 661, 664, 742, 822, 823, 824` ·
`Config.luau:216, 225, 247, 290, 319` · `Remotes.luau:154` ·
`UIController.luau:66, 67, 68, 284` · `QuickChatService.luau:59`

`ItemService`'s eleven are the largest cluster and Step 2.2 rewrites them; `RoundService`'s go with the
blocks Steps 3.1–3.2 delete.

---

## 2. `src/server/Services/GateService.luau` (213 lines) — DELETED, Step 2.3

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/init.server.luau:30` | `"GateService"` in `SERVICE_ORDER` |

Nothing requires it. It is a leaf: it reads from `RoundService` and calls back in, and no other module
reads from it.

### CODE — outbound (the round-ending route this plan removes)

| Site | Call |
|---|---|
| `GateService.luau:164` | **`RoundService.EndRound(Enums.RoundResult.SurvivorsEscaped)`** — the only producer of `SURVIVORS_ESCAPED` in the tree |
| `GateService.luau:134, 200` | `RoundService.IsGateOpen()` — deleted in Step 3.2 |
| `GateService.luau:135` | `RoundService.GetAswangUserId()` |
| `GateService.luau:152` | `RoundService.GetPlayerState(player)` |
| `GateService.luau:188` | `RoundService.PhaseChanged.Event:Connect(onPhaseChanged)` — a phase **subscriber**, never a writer |

`:164` is the load-bearing line: after Step 2.3 nothing raises `SURVIVORS_ESCAPED`, which is why the
plan's constraint (c) can claim the round ends on the sunrise timer alone.

### PROSE — inbound

`RoundService.luau:135` · `AudioController.luau:150, 558, 559, 562`

`AudioController`'s four are all inside the gate-cue block that Step 1.6 deletes, so they leave on
their own.

---

## 3. `src/server/Services/GhostService.luau` (763 lines) — DELETED, Step 2.3

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/init.server.luau:33` | `"GhostService"` in `SERVICE_ORDER` |
| `src/server/init.server.luau:36-37` | named in the comment justifying `TeachingService`'s position — rewritten in Step 2.3's diff |

### CODE — outbound

| Site | Call | Consequence |
|---|---|---|
| `GhostService.luau:485` | `TeachingService.Cue(player, "CUE_FIRST_GHOST_DEATH")` | last firer of that cue id — Step 5.6 |
| — | `Remotes.Get("GhostRoster")`, `"ReportGhostPosition"`, `"RequestGhostSpook"` | last user of all three — Step 4.4 |

### PROSE — inbound

`DailyService.luau:124` · `TrialService.luau:824, 825` · `QuickChatService.luau:313, 356, 455` ·
`Remotes.luau:74`

`Remotes.luau:74` sits inside the `GhostRoster` block deleted in Step 4.4. The three in
`QuickChatService` are cited as precedent for its own fire-site state test and must be reworded rather
than deleted — the precedent is still true, the file naming it will not exist.

---

## 4. `src/client/Controllers/TaskController.luau` (371 lines) — DELETED, Step 1.1

### CODE — inbound

| Site | Reference |
|---|---|
| `src/client/Controllers/InputController.luau:34` | `local TaskController = require(script.Parent.TaskController)` |
| `src/client/Controllers/InputController.luau:216` | `TaskController.SetHolding(pressed)` — the entire body of `performAct` |
| `src/client/Controllers/UIController.luau:72` | `local TaskController = require(script.Parent.TaskController)` |
| `src/client/Controllers/UIController.luau:2153` | `touchButtons.Stop.Visible = inRound and TaskController.IsTimingBarLive()` |
| `src/client/init.client.luau:38` | `"TaskController"` in `CONTROLLER_ORDER` |

**Two hard requires, so `npm run analyze` stays red from the moment the file is deleted until Steps 1.2
and 1.3 land.** That is the whole reason Phase 1 groups them.

`UIController.luau:66-68` is the comment arguing that the `UIController → TaskController` arrow points
one way on purpose; it is deleted with the require in Step 1.3.

### PROSE — inbound

`OnboardingController.luau:259` · `Config.luau:257` · `Remotes.luau:85, 91` · `UIController.luau:2148`

All four of those sites are inside blocks other steps delete.

---

## 5. `src/client/Controllers/GhostController.luau` (286 lines) — DELETED, Step 1.1

### CODE — inbound

| Site | Reference |
|---|---|
| `src/client/init.client.luau:42` | `"GhostController"` in `CONTROLLER_ORDER` |
| `src/client/init.client.luau:39-41` | the comment justifying its position |

**No module requires it.** Unlike `TaskController` it is a pure leaf, so deleting it alone leaves the
tree green — only the bootstrap list names it.

---

## 6. `src/shared/pure/TaskSelection.luau` (160 lines) — DELETED, Step 2.5

### CODE — inbound

**None outside deleted files.** `TaskService` was its only caller.

### PROSE — inbound

`src/server/pure/TaskResolve.luau:15, 32` † · `src/server/pure/TaskListView.luau:26` † ·
`src/server/pure/TaskPool.luau:16-17` (→ `SearchPool`, Step 2.1 rewrites the paragraph) ·
`Config.luau:221`

`TaskPool.luau:16-17` is the one that matters: its "WHY `src/server/pure/` AND NOT `src/shared/pure/`"
argument is built by contrast with `TaskSelection` next door. Step 2.1 has to rebuild that argument
from the inputs instead, because the module it contrasts against is about to not exist.

### Test

`tests/task-selection.test.luau:15` — `require("../src/shared/pure/TaskSelection")`. Deleted, Step 2.6.

---

## 7. `src/shared/pure/SpookBudget.luau` (93 lines) — DELETED, Step 2.5

### CODE — inbound

**None outside deleted files.** `GhostService` was its only caller.

### PROSE — inbound

`SpookBudget.luau:19` cites `Config.Ghost.SpookRangeStuds`, deleted in Step 4.2 — self-contained.

### Test

`tests/spook-budget.test.luau:10` — `require("../src/shared/pure/SpookBudget")`. Deleted, Step 2.6.

---

## 8. `src/shared/pure/WinConditions.luau` (81 lines) — DELETED, Step 3.3

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/Services/RoundService.luau:37` | `local WinConditions = require(Shared.pure.WinConditions)` |
| `src/server/Services/RoundService.luau:1042-1047` | `WinConditions.aswangWinsByKills({ AswangKills, DealtInSurvivors, Threshold })` in `MarkKilled`, → `EndRound(AswangWins)` at `:1048` |
| `src/server/Services/RoundService.luau:1349-1354` | the same call in the husk-kill path, → `EndRound(AswangWins)` at `:1355` |
| `tests/win-conditions.test.luau:25` | `require("../src/shared/pure/WinConditions")` — **the suite is KEPT and emptied**, Step 3.3 |

Exactly one requiring module and two call sites. Both call sites read `Config.Round.AswangWinSurvivorThreshold`
(`:1045`, `:1352`), which is why Step 4.2 deletes that tunable too — those are its only readers.

### PROSE — inbound

`Config.luau:24` — the `AswangWinSurvivorThreshold` comment, deleted with the key.

### State that stays behind, deliberately

`state.AswangKills` (`RoundService.luau:63`, written at `:988` and `:1324`, read by
`ProgressionService.luau:857` via `GetAswangKills()`) and `state.DealtInSurvivors`
(`RoundService.luau:59`, written at `:818`, reset at `:752`) both **survive**. V11's kill-everyone rule
needs both, and `ProgressionService` reads one of them today.

---

## 9. `src/shared/pure/GhostChat.luau` (83 lines) — **RENAMED** to `ChatAudience.luau`, Step 5.1

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/Services/QuickChatService.luau:68` | `local GhostChat = require(Shared.pure.GhostChat)` |
| `src/server/Services/QuickChatService.luau:335` | `GhostChat.shouldDeliver(` |
| `src/server/Services/QuickChatService.luau:336` | `senderState :: GhostChat.PlayerState` |
| `src/server/Services/QuickChatService.luau:337` | `recipientState :: GhostChat.PlayerState` |
| `tests/ghost-chat.test.luau:15` | `require("../src/shared/pure/GhostChat")` — renamed with it |

**This is why the module is renamed rather than deleted.** The build plan lists it for deletion; a live
surviving service calls it, and what it decides is the dead/living chat wall — `shouldDeliver` returns
`isLivingSide(sender) or sender == recipient` (`:79-81`). Deleting it either breaks `QuickChatService`
or, worse, gets replaced by an inline condition that silently admits `SPECTATOR`.

### PROSE — inbound

`src/shared/pure/QuickChatTarget.luau:39, 51` · `src/shared/pure/QuickChatPhrases.luau:16` ·
`QuickChatService.luau:136, 308, 325, 330`

`QuickChatTarget.luau:39` describes its own `IsLivingSide` input as "`GhostChat.isLivingSide` of this
candidate, computed by the caller" — a **cross-module contract stated in a comment**. Rename it in the
same step or the two files disagree about who computes what.

---

## 10. `src/server/pure/TaskPool.luau` (86 lines) — **RENAMED** to `SearchPool.luau`, Step 2.1

### CODE — inbound

| Site | Reference |
|---|---|
| `src/server/Services/ItemService.luau:34` | `local TaskPool = require(script.Parent.Parent.pure.TaskPool)` |
| `src/server/Services/ItemService.luau:62` | `local function discoverPool(): TaskPool.Report` |
| `src/server/Services/ItemService.luau:92` | `return TaskPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize)` |
| `src/server/Services/ItemService.luau:134` | `function ItemService.EvaluatePool(): TaskPool.Report` |
| `src/shared/Types.luau:257` | `export type TaskPoolVerdict = "OK" \| "EMPTY" \| "SHORT" \| "DUPLICATE_ID" \| "OVERSIZED"` |
| `tests/task-pool.test.luau:14` | `require("../src/server/pure/TaskPool")` — renamed with it |

**Four live call sites in a service that survives V01.** `ItemService` uses it for the salt-pouch pool
verdict, shared with `TaskService` rather than copied (`ItemService.luau:22`). With `TaskService` gone
`ItemService` is its sole owner, so it takes the name.

`Types.luau:247` is the doc block above the verdict union and cites the old path; both change in
Step 2.2.

### PROSE — inbound

`src/shared/pure/SaltCarry.luau:27` — cites `TaskPool` as the example of a server-side pure module.
The argument survives the rename; the name in it does not.

---

## 11. The seven other `src/server/pure/` deletions — Step 2.4

`TaskWeight.luau` · `TaskListView.luau` · `TaskParticipants.luau` · `TaskProgress.luau` ·
`TaskResolve.luau` · `TimingWindow.luau` · `GateEscape.luau`

### CODE — inbound

**None, for any of the seven.** Every caller is `TaskService` or `GateService`, both deleted in
Step 2.3, plus their own suites deleted in Step 2.6:

`tests/task-weight.test.luau` · `task-list-view.test.luau:14` · `task-participants.test.luau:13` ·
`task-progress.test.luau` · `task-resolve.test.luau:15` · `timing-window.test.luau:17` ·
`gate-escape.test.luau:13` · `fetch-carry.test.luau:16`

(`task-weight` and `task-progress` require `Config` on their first require line and their module
second; both are deleted whole.)

### PROSE — inbound, in files that SURVIVE

| Module | Surviving mentions |
|---|---|
| `TaskWeight` | `SaltCarry.luau:19` · `SaltThrow.luau:29` |
| `TimingWindow` | `Types.luau:340` (inside the `TimingBarPayload` block, deleted Step 3.4) |
| `FetchCarry` | `Types.luau:387` (inside the `FetchAction` block, deleted Step 3.4) |
| `TaskListView` | `Remotes.luau:92` (inside the `FirstObjectiveAssigned` block, deleted Step 4.4) · `Config.luau:266` |
| `TaskProgress` | `Config.luau:127` |

`SaltCarry.luau:19` and `SaltThrow.luau:29` are the two that need an actual rewrite rather than
falling out with a block: both argue their own role-blindness *by citing `TaskWeight`'s grid* as the
enforceable form of it. The rule they inherit is still true; the file they inherit it from is not.
Restate the rule in place. Both files are already being edited in Step 5.3 for the `PlayerState` union,
so the rewrite lands there.

### `FetchCarry` — a note on the build plan's uncertainty

The brief asked whether `fetch-carry` and `timing-window` are task suites. Both are. `FetchCarry` takes
`Config.Tasks.FullContributionWeight` as its `FullWeight` parameter (`FetchCarry.luau:17-19`) and its
header describes the FETCH task's carry rule; `TimingWindow`'s header states that `TaskService` computes
its only time input as `os.clock() - task.BarStartAt` (`TimingWindow.luau:15-16`). Neither has a caller
outside the deleted services.

---

## 12. Summary — where the CODE references actually are

Nine deleted modules produce inbound **code** references in exactly **six** surviving files:

| File | References | Step |
|---|---|---|
| `src/client/Controllers/InputController.luau` | 2 (`TaskController`) | 1.2 |
| `src/client/Controllers/UIController.luau` | 2 (`TaskController`) | 1.3 |
| `src/client/init.client.luau` | 2 (bootstrap list) | 1.5 |
| `src/server/init.server.luau` | 3 (bootstrap list) | 2.3 |
| `src/server/Services/ItemService.luau` | 4 (`TaskPool`) | 2.2 |
| `src/server/Services/RoundService.luau` | 3 (`WinConditions`) | 3.1 |
| `src/server/Services/QuickChatService.luau` | 4 (`GhostChat`) | 5.1 / 5.5 |

Seven files, twenty code references. **Everything else in this document is prose** — which is the
finding worth carrying into implementation: the dangling-reference risk is small and enumerable, and the
bulk of the diff is comments describing a game that no longer exists.
