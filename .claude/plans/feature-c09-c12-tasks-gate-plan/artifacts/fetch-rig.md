# Step 4.5 — the disposable `FetchSource` anchors, and the fetch item in a live round

Captured 2026-08-12, Studio place `Place3`, `rojo serve` live.

> **NOT THE GREYBOX.** Four orange pads and some attributes, added to plan 1's disposable
> `workspace.TaskRig_TEMP`. C17 deletes that folder wholesale and places real anchors. The place file
> is gitignored, which is why this written record and not the rig is the deliverable.

## 1. What was placed

Four `Part`s in `workspace.TaskRig_TEMP`, tagged `FetchSource`, named `FetchSource_01`…`_04`, at
`(±110, 0.5, ±70)` — deliberately **outside** the 4×3 task-pad grid (`X = {-45,-15,15,45}` by
`Z = {-30,0,30}`) so the furthest-unused fallback produces a walk worth timing.

```
{"Sources":4,"Gates":1,"TaskPoints":12,
 "FurthestFor_02":"FetchSource_04 @ 160 studs",
 "FurthestFor_03":"FetchSource_03 @ 160 studs"}
```

**160 studs each way**, against `Config.Tasks.FetchTime = 25`. That is the number M12 tunes, and the
thing it actually tunes is this distance — which C17 owns.

## 2. Task types, and the default that stays exercised

```
TaskPoint_01=HOLD   TaskPoint_02=FETCH  TaskPoint_03=FETCH
TaskPoint_04=TIMING TaskPoint_05=TWO_PERSON
TaskPoint_06..12=nil
```

Five pads name a type; **seven are left absent**, so `taskTypeOf`'s `nil → HOLD` default — the one the
whole map relies on — keeps being exercised on every draw. `task-rig.md` §1 makes the same argument for
pad 01 and it still holds.

## 3. A live round drew a FETCH task and the item appeared at its source

Debug values set for the run and **reverted afterwards** (all six, confirmed by `git diff` and
`check:debug`).

```
[TaskService] Pool OK — 12 task points.
[RoundService] -> STARTING (4s)
[TaskService] Round tasks: TaskPoint_07, TaskPoint_04, TaskPoint_10, TaskPoint_12, TaskPoint_03
[RoundService] -> ACTIVE (120s)
```

`TaskPoint_03` is one of the two `FETCH` pads, and sampled during ACTIVE:

```
DuringActive: Items = "FetchItem_TaskPoint_03@-110,70"
```

The item was created at `(-110, 70)` — `FetchSource_03`, the **furthest unused** source from
`TaskPoint_03`, which is the fallback behaving exactly as specified. §4.4 buys travel with this task
and a nearest-source pairing would buy none of it.

`TaskPoint_04` (TIMING) was drawn in the same round, so the tick's `continue` for timing tasks was live
alongside a fetch.

## 4. The item is gone by INTERMISSION

Sampled again after `ACTIVE(120) + ENDING(6)` had elapsed:

```
AfterRound:  Items = "(none)"   Active = ""
```

`clearTasks` destroys every item and clears `fetchState` on the way into the lobby. No orphan grey cube
survives the round — which matters because the place file is not in Git and an orphan would be found by
C17 with no way to tell what left it there.

## 5. No require cycle

```
[Bootstrap] Ready. 14 services loaded.
[Client] Ready. 6 controllers loaded.
```

14, up from 13 — `GateService` (Phase 6) loaded cleanly. A require cycle would have shown as one
swallowed `warn` and a server stuck in IDLE.

## 6. What this does NOT show

- **Nobody picked the item up.** `PICK_UP`, `DELIVER` and `DROP` are proven by
  `tests/fetch-carry.test.luau`'s 512-cell grid and are **not** proven in the engine here. A carry needs
  a player to walk 160 studs to the source and back; that is the playtester's job.
- The 4 Hz carry stepping (the accepted roughness in `tickFetch`'s comment) has never been seen moving.
- **Measured through datamodel state and `get_console_output` only.** `execute_luau`'s `require`
  returns a fresh, separately stale copy of a module — plan 1's artifacts record it reading `IDLE` from
  a live `ACTIVE` service and a `Config.Tasks` missing a committed knob.

## 7. State left behind

`workspace.TaskRig_TEMP` holds 12 `TaskPoint` pads, 4 `FetchSource` pads, 1 `EscapeGate_TEMP`. Not
published — the rig is disposable and publishing it would put it in the cloud history C17's real
greybox needs.
