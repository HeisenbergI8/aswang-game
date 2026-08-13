# Delta check 1 — `taskPointAt` via `TaskResolve.at`, and #4 (weightFor via TaskWeight)

Captured 2026-08-12, Studio place `Place3`, Play mode, SoloTesting on, `Config.Round` set to
Intermission=8/Duration=90/EndScreen=6 by the coordinator.

Character navigated to `Workspace.TaskRig_TEMP.TaskPoint_10` (`CFrame.Position = -15, 0.5, 30`), one of
this round's drawn tasks (`Round tasks: TaskPoint_10, TaskPoint_09, TaskPoint_11, TaskPoint_12,
TaskPoint_07`). `E` held continuously via `keyDown` -> `wait 9500ms` -> `keyUp` (`Config.Tasks.HoldTime =
8`).

Full console transcript (verbatim, only the CoreGui keycode-rendering warning elided from the middle
since it is the already-known, non-regression `KeyboardKeyCode = None` warning):

```
[TaskService] Pool OK — 12 task points.
[RoundService] -> INTERMISSION (8s)
[Bootstrap] Ready. 13 services loaded.
[Bootstrap] SoloTesting is ENABLED — do not ship with this on.
[Client] Ready. 6 controllers loaded.
[Client] Snapshot — INTERMISSION round #0 · tasks 0/5 · gate shut · alive 0 · you: LOBBY (7s left)
[RoleService] Drew 1 roles.
[RoundService] -> STARTING (4s)
[TaskService] Pool OK — 12 task points.
[TaskService] Round tasks: TaskPoint_10, TaskPoint_09, TaskPoint_11, TaskPoint_12, TaskPoint_07
[Client] Phase -> STARTING (4s)
[Client] Snapshot — STARTING round #1 · tasks 0/5 · gate shut · alive 1 · you: ALIVE (3s left)
[RoundService] -> ACTIVE (90s)
[Client] Phase -> ROUND LIVE (90s)
[Client] Snapshot — ACTIVE round #1 · tasks 0/5 · gate shut · alive 1 · you: ALIVE (89s left)
CoreGui.RobloxGui.CoreScripts/ProximityPrompt:385: ProximityPrompt 'TaskPrompt' has an unsupported keycode for rendering UI: Enum.KeyCode.None
[Task] 0/5 · here: 3%
[Task] 0/5 · here: 6%
[Task] 0/5 · here: 9%
[Task] 0/5 · here: 13%
[Task] 0/5 · here: 16%
[Task] 0/5 · here: 19%
[Task] 0/5 · here: 22%
[Task] 0/5 · here: 26%
[Task] 0/5 · here: 29%
[Task] 0/5 · here: 32%
[Task] 0/5 · here: 36%
[Task] 0/5 · here: 39%
[Task] 0/5 · here: 42%
[Task] 0/5 · here: 46%
[Task] 0/5 · here: 49%
[Task] 0/5 · here: 52%
[Task] 0/5 · here: 55%
[Task] 0/5 · here: 58%
[Task] 0/5 · here: 62%
[Task] 0/5 · here: 65%
[Task] 0/5 · here: 68%
[Task] 0/5 · here: 71%
[Task] 0/5 · here: 74%
[Task] 0/5 · here: 78%
[Task] 0/5 · here: 81%
[Task] 0/5 · here: 84%
[Task] 0/5 · here: 88%
[Task] 0/5 · here: 91%
[Task] 0/5 · here: 94%
[Task] 0/5 · here: 98%
[TaskService] Task complete: TaskPoint_10
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Task] 1/5 · here: 100%
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Client] Snapshot — ACTIVE round #1 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (49s left)
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Task] 1/5 · here: -
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
```

## Reading

- The client bar climbed monotonically 3% -> 98%, a clean ~30 ticks at the server's 4Hz cadence, and
  `[TaskService] Task complete: TaskPoint_10` fired — the same shape as the prior session's Part 2
  evidence. This is the proof requested: if the `Vector3` -> `{X,Y,Z}` conversion at the `taskPointAt`
  call site (`toVec(part.Position)`, `toVec(position)`) or the hand-off into `TaskResolve.at` were wrong,
  presence would resolve to `nil` every tick and this bar would never move past 0% (`NO_TASK_IN_RANGE`
  refusals instead). It did not — the conversion is correct end to end, driven through the real engine
  and the real service, not a mock.
- `1/5` went into the round snapshot (`tasks 1/5`), so `completedCount()` and the global bar agree with
  the per-player bar — no drift introduced by the new call shape.
- Post-completion spam is still refused `ALREADY_COMPLETE`, matching the prior session's spam-immunity
  finding — unaffected by this delta, reconfirmed as a side effect of this run.
- **Check #4 (regression on `weightFor` via `TaskWeight.forPlayer`) is proven by the same transcript**: a
  solo ALIVE, non-Aswang (`ForceAswangWhenSolo = false`) survivor's ticks moved the bar 0->100 in the
  expected ~8s window at the expected per-tick size (~3.1-3.5%, i.e. `100/(HoldTime*TickRate)` with no
  attenuation) — full weight, not a partial or zero contribution. If `TaskWeight.forPlayer` had regressed
  to return a partial or zero weight for an ALIVE player, the hold would take longer than 8s or never
  complete; it did neither.
- No `[TaskService] Task points are packed too tightly...` warning appears anywhere in this transcript —
  the negative case for delta check #3, over a real draw against the 30-stud-pitch rig. See
  `delta-3-spacing-warning-absent.md` for the isolated confirmation and reasoning.

## Verdict

PASS. Command/session: Studio Play mode via MCP (`start_stop_play`, `character_navigation`,
`user_keyboard_input`), console captured via `get_console_output` immediately after the hold.
