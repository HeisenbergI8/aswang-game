# Step 2.1 — the disposable `TaskPoint` rig, and the three proofs it exists to make possible

Captured 2026-08-12, Studio place `Place3`, `rojo serve` live on `default.project.json`.

> **THIS RIG IS NOT C17 AND IT IS NOT A DELIVERABLE.** It is twelve grey pads on a baseplate so that
> C08 has something to stand on. The barrio, the chapel and the treeline remain the user's job, and C17
> replaces this wholesale. Everything lives in one folder for exactly that reason: deleting
> `workspace.TaskRig_TEMP` deletes the entire rig and nothing else.
>
> None of it is in Git — the place file is gitignored, which is why this written record, and not the
> rig, is the step's deliverable.

## 1. What was placed

`workspace.TaskRig_TEMP`, twelve anchored `Part`s, `Medium stone grey`, `Concrete`, 4×1×4 studs, named
`TaskPoint_01` … `TaskPoint_12`, each tagged `TaskPoint` via `CollectionService`.

A 4×3 grid, `X = {-45, -15, 15, 45}` by `Z = {-30, 0, 30}`, 30-stud pitch, index z-outer / x-inner.

```
{"Placed":12,"Tagged":12,"ClosestPairStuds":30,"ClosestPair":"TaskPoint_03<->TaskPoint_07",
 "AttributeOnPad01":"HOLD","Folder":"Workspace.TaskRig_TEMP"}
```

**Measured** closest pair: **30 studs**, against `Config.Tasks.MinSpacingStuds = 20`. So the spacing
filter is satisfiable by every pair and never has to fall back in-game. That is deliberate — the
rejection path is already proven purely (`tests/task-selection.test.luau` draws from twelve points
stacked in one room and asserts the fallback still fills the round), and a rig that reproduced it would
make every other observation here harder to read.

`TaskType = "HOLD"` is set on **pad 01 only**. `AttributeOnPad02` came back absent, which is the point:
`taskTypeOf` defaults an absent attribute to `HOLD`, and a rig where every pad stated it would never
exercise the default the whole map is going to rely on.

Screenshot: 12 pads in a 4×3 grid on the baseplate, camera at `(0, 95, 105)` looking at origin. Captured
in-session; the grid and the count are legible, the centre pad partially overlaps the stock
`SpawnLocation` decal.

## 2. The empty-pool proof — the one constraint 4 owes

`TaskRig_TEMP` deleted (`RemainingTagged: 0`), server started. Console, **verbatim**:

```
[TaskService] NO "TaskPoint" PARTS IN THE MAP. Tag 12 anchored parts with "TaskPoint" via CollectionService, or no task can ever be completed and the escape gate can never open.
[Bootstrap] Ready. 13 services loaded.
[Client] Ready. 5 controllers loaded.
[Client] Snapshot — IDLE round #0 · tasks 0/5 · gate shut · alive 0 · you: LOBBY (0s left)
```

Three things this shows that a silent run would not:

- It fires **at boot**, not at the first `STARTING` — the line appears *above* `[Bootstrap] Ready`. An
  operator learns while still looking at the output window, rather than 45 seconds later when nobody is
  watching.
- It is **unconditional**. `Config.Debug.VerboseLogging` was `false` for this capture.
- It names the **tag** and the **count**, so the reader looking at an empty baseplate knows what to do
  rather than merely that something is wrong.

This is the failure the stub refused to ship blind, and it is now observable in the real engine rather
than only in Lune.

## 3. The duplicate-name proof

Rig rebuilt, then `TaskPoint_07` renamed to `TaskPoint_06`, so two tagged parts answer to one Name.
Server started. Console, **verbatim**:

```
[TaskService] TaskPoint parts share a Name and were skipped: TaskPoint_06. The server identifies a task point BY its Name, so every tagged part must have a unique one.
[Bootstrap] Ready. 13 services loaded.
```

`TaskPool.evaluate` over the same live pool returned `{"Verdict":"DUPLICATE_ID","Unique":11,"Duplicates":1}`.

Restored to `TaskPoint_07`; re-evaluated: `{"Verdict":"OK","Unique":12,"Duplicates":0,"ClosestPairStuds":30}`.

The `OK` verdict was read by calling `server/pure/TaskPool` directly against the live tag list, rather
than by switching `VerboseLogging` on for a screenshot and having to revert `Config.luau` again.

## 4. The draw, in the engine (Step 2.3's real proof)

`check:config` — Step 2.3's stated check — passes whether or not the `PhaseChanged` subscription works,
so this was run separately. Debug values set for the run and **reverted afterwards**
(`SoloTesting`/`VerboseLogging` on, `Intermission` 25→8, `Duration` 420→20, `EndScreen` 12→6).

```
[TaskService] Pool OK — 12 task points.
[RoundService] -> INTERMISSION (8s)
[RoleService] Drew 1 roles.
[RoundService] -> STARTING (4s)
[TaskService] Pool OK — 12 task points.
[TaskService] Round tasks: TaskPoint_03, TaskPoint_04, TaskPoint_05, TaskPoint_08, TaskPoint_11
[RoundService] -> ACTIVE (420s)
```

Five drawn at `STARTING`, five parts carrying `ActiveTaskPoint`, closest **chosen** pair 30 studs.
A second round drew `TaskPoint_07, 04, 12, 05, 11` and a third `TaskPoint_12, 04, 07, 03, 06` — a
different five each round, which is §4.4's entire purpose and Appendix C.4's cause #2.

No require-cycle warning: `13 services loaded` on every boot.

### The teardown, and a misreading corrected

A three-point sample first returned `active=5 ending=0 intermission=5`, which reads as the teardown
firing on the wrong phase. It was a **labelling error, not a defect** — the sample labels assumed the
script began at play `t=0`, but `execute_luau` starts several seconds in, so each sample landed one
phase later than its name.

Re-run at 1s resolution over a full round boundary, which needs no phase labels at all:

```
Runs: 5x11 0x9 5x30 0x2
Raw:  5555555555500000000055555555555555555555555555555500
```

The 30-sample run of five tags is exactly `STARTING(4) + ACTIVE(20) + ENDING(6) = 30`, and the 9-sample
zero run is `INTERMISSION(8)` plus one sample of slop. So **the tags survive ENDING and clear on the way
into the lobby** — the rule `clearTasks`'s comment states, and the reason is the end screen: a round that
finished 4/5 can still show it.

## 5. A Studio trap worth recording

`RoundService.GetPhase()` called from `execute_luau` returned `"IDLE"` while the console showed `ACTIVE`.
`require` from the executor yields a **fresh copy of the module** with its own `state` local, not the
live service — exactly the trap `.claude/agents/playtester.md` documents.

CollectionService tag counts do **not** have this problem: they are datamodel state. That is why every
measurement above is a tag count or a console line, and none is a service query.

## 6. State left behind

`workspace.TaskRig_TEMP` exists, 12 correctly-named tagged pads, `TaskType` on pad 01 only. The place
was **not** published — the rig is disposable and publishing it would put it in the cloud version
history that C17's real greybox needs.

`Config.luau` debug and timing values are back at their committed values, confirmed by
`git diff` (no debug or timing line differs from HEAD) and by `npm run check:debug` → ok.
