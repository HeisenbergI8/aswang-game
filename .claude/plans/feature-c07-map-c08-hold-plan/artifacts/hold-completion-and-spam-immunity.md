# C08 Done condition: an 8-second hold completes, and spamming the remote gains nothing

Captured 2026-08-12, Studio place `Place3`, `rojo serve` live, fresh Play session started **after** the
coordinator's `KeyboardKeyCode` fix (see `keyboard-swallow-bug-and-fix.md`). Config debug values as set
by the coordinator: `Round.Intermission=8`, `Duration=90`, `EndScreen=6`,
`Debug.SoloTesting`/`VerboseLogging=true`. Solo survivor (`ForceAswangWhenSolo=false`).

All console excerpts below are **verbatim** from `get_console_output`, trimmed to the relevant window.
Character position was read every time via `(HumanoidRootPart.Position - pad.Position).Magnitude` in the
same `execute_luau` call that fired the remote, so distance and firing are from the same moment — no
cross-call gap to cast doubt on "was I actually on the pad".

## Part A — off the pad, spamming gains nothing (500 fires)

Teleported to `(200, 3, 200)`, nowhere near any of the round's five `ActiveTaskPoint` parts. Fired
`Remotes.Get("RequestTaskProgress"):FireServer()` **500 times** in a single `execute_luau` call (a tight
Luau `for` loop, no yields — as fast as the VM could dispatch):

```
{"CharPos":"199.498046875, 2.9980244636535645, 199.43734741210938","Fired":500}
```

Server console:

```
[TaskService] Refused progress for Demiurgos_18: NO_TASK_IN_RANGE
[TaskService] Refused progress for Demiurgos_18: NO_TASK_IN_RANGE
... (12 total)
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTaskProgress
```

Only 12 of the 500 requests even reached `TaskService` — `AntiCheat.Budgets.RequestTaskProgress.Capacity
= 12` — and every one of those 12 was refused `NO_TASK_IN_RANGE`. The other 488 were silently dropped by
`AntiCheatService.Consume` before `notePresence` was ever called. No `[Task]` progress line, no
`TasksCompleted` change, nothing. **500 requests, zero effect**, exactly as `TaskProgress.tick`'s design
(elapsed real time, not request count) predicts.

## Part B — on the pad, spamming produces the identical rate as normal holding

Standing on `TaskPoint_05` (confirmed `Dist≈3.5`, well inside `PresenceRangeStuds=9`), fired the remote
continuously — **once per rendered frame** (`task.wait()` with no argument, ≈60 Hz) — for a sustained
~9–9.5 second burst per call, several calls back to back on the same pad across round boundaries:

```
{"Elapsed":8.516,"Fires":511,"Dist":3.498}   -- burst 1
{"Elapsed":9.016,"Fires":541,"Dist":3.498}   -- burst 2, same pad, resumed
{"Elapsed":9.516,"Fires":571,"Dist":3.498}   -- burst 3, fresh round, 0% start
```

That is roughly **15x** the 4 Hz rate `TaskController`'s own heartbeat uses, and roughly **10x** the
anti-cheat's 6/s sustained refill. Server console (burst 3, the clean 0%-to-completion run):

```
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTaskProgress
[Task] 0/5 · here: 3%
[Task] 0/5 · here: 6%
[Task] 0/5 · here: 9%
[Task] 0/5 · here: 12%
[Task] 0/5 · here: 16%
[Task] 0/5 · here: 19%
[Task] 0/5 · here: 22%
[Task] 0/5 · here: 25%
[Task] 0/5 · here: 28%
[Task] 0/5 · here: 32%
[Task] 0/5 · here: 35%
[Task] 0/5 · here: 38%
[Task] 0/5 · here: 41%
[Task] 0/5 · here: 45%
[Task] 0/5 · here: 48%
[Task] 0/5 · here: 51%
[Task] 0/5 · here: 55%
[Task] 0/5 · here: 58%
[Task] 0/5 · here: 61%
[Task] 0/5 · here: 64%
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTaskProgress
[Task] 0/5 · here: 67%
[Task] 0/5 · here: 71%
[Task] 0/5 · here: 74%
[Task] 0/5 · here: 77%
[Task] 0/5 · here: 80%
[Task] 0/5 · here: 83%
[Task] 0/5 · here: 87%
[Task] 0/5 · here: 90%
[Task] 0/5 · here: 93%
[Task] 0/5 · here: 97%
[TaskService] Task complete: TaskPoint_05
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Task] 1/5 · here: 100%
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Client] Snapshot — ACTIVE round #4 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (23s left)
```

The per-tick delta is ~3.1–3.5 percentage points throughout — the same step size a **normal single
`E`-hold** produced in an earlier probe on this same build (`3%, 6%, 9%, 12%, 16%, 19%, 22%` — see
`keyboard-swallow-bug-and-fix.md`'s root-cause confirmation). Counting the 30 print steps from 3% to
complete against the 4 Hz server tick (`task.wait(0.25)` in `TaskService.tick`'s loop) gives ≈7.5–8
seconds of accumulated hold — matching `Config.Tasks.HoldTime = 8` — **despite the remote having been
fired roughly 15x more often than a normal client would.** Spam and a normal hold complete in the same
wall-clock time because `TaskProgress.tick` only ever consumes `elapsed = os.clock() - lastTickAt`; the
request count never enters the calculation. This is the mandatory Done-condition proof: **a client
spamming `RequestTaskProgress` gains nothing over an honest client holding normally — proven by
construction and confirmed live.**

`[TaskService] Task complete: TaskPoint_05` also demonstrates the completion side: `TasksCompleted`
correctly ticked to `1/5` in the very next `[Client] Snapshot` line, and every further request after
completion was correctly refused `ALREADY_COMPLETE` rather than allowed to double-count.
