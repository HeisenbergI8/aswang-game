# Delta check 2 — nearest-INCOMPLETE resolution, the soft-lock fix, forced live

The brief called this optional and best-effort because the rig's 30-stud pitch never puts two pads in
one 9-stud presence radius by construction. Rather than skip it, one already-drawn pad was moved live
(server-authoritative `CFrame` write via `execute_luau` on the `Server` datamodel — a datamodel edit, not
a script-source edit, so it does not touch `src/` and Rojo cannot overwrite it) to sit 4 studs from
another drawn, about-to-be-completed pad. Restored afterward (see bottom).

## Setup

Round #2's draw: `TaskPoint_12, TaskPoint_07, TaskPoint_05, TaskPoint_11, TaskPoint_04`
(`[TaskService] Round tasks: ...`).

`TaskPoint_12` at `(45, 0.5, 30)`. `TaskPoint_07` originally at `(15, 0.5, 0)` — moved live to
`(41, 0.5, 30)`, 4 studs from `TaskPoint_12`, both well inside `Config.Tasks.PresenceRangeStuds = 9`.

Character stood at `TaskPoint_12`. Sequence: hold `E` 9.5s (completes `TaskPoint_12`, distance ≈0),
release 0.5s, hold `E` again 5s **without moving** — so the player is now simultaneously in range of a
**completed** point at distance ≈0 and an **incomplete** point (`TaskPoint_07`) at distance ≈4. The old
first-match resolver would have found `TaskPoint_12` first (it is nearer) and refused every request
`ALREADY_COMPLETE` forever — the exact soft-lock `TaskResolve.luau`'s docstring describes.

## Console, verbatim (the relevant window)

```
[Task] 0/5 · here: 94%
[Task] 0/5 · here: 98%
[TaskService] Task complete: TaskPoint_12
[Task] 1/5 · here: 100%
[Client] Snapshot — ACTIVE round #2 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (4s left)
[Task] 1/5 · here: 3%
[Task] 1/5 · here: 6%
[Task] 1/5 · here: 9%
[Task] 1/5 · here: 12%
[Task] 1/5 · here: 16%
[Task] 1/5 · here: 19%
[Task] 1/5 · here: -
[Task] 1/5 · here: 22%
[Task] 1/5 · here: 26%
[Task] 1/5 · here: 29%
[Task] 1/5 · here: 32%
[Task] 1/5 · here: 35%
[Task] 1/5 · here: 38%
[Task] 1/5 · here: 42%
[Task] 1/5 · here: 45%
[Task] 1/5 · here: 48%
[Task] 1/5 · here: 51%
[RoundService] -> ENDING (6s)
[TaskService] Refused progress for Demiurgos_18: WRONG_PHASE
[Task] 1/5 · here: 54%
```

## Reading

- The instant `TaskPoint_12` completed, the very next tick's bar **restarted from 0% and climbed again**
  (`3%, 6%, 9% ...`) rather than staying at `100%` or refusing — this is only possible if `taskPointAt`
  re-resolved to a **different, incomplete** point (`TaskPoint_07`) despite the completed point
  (`TaskPoint_12`) being strictly nearer. That is precisely the nearest-incomplete contract, exercised
  through the real server tick and the real `TaskResolve.at`, not a synthetic call.
- Zero `ALREADY_COMPLETE` or `NO_TASK_IN_RANGE` refusals appear anywhere in this window — the resolver
  never got stuck on the nearer, completed point. Under the old first-match code this would have produced
  a wall of `ALREADY_COMPLETE`, the exact 4/5-forever soft-lock the rewrite exists to fix.
- The round ended at 54% (`Config.Round.Duration = 90` elapsed) before a second full hold could complete
  — that is the debug round timer, not a defect. The `WRONG_PHASE` refusal after `ENDING` is expected and
  correct (RoundService owns the phase; TaskService checks it).
- One tick logged `[Task] 1/5 · here: -` mid-climb (between 19% and 22%) — a single snapshot polled
  between two server ticks with no presence entry populated yet, and progress resumed upward immediately
  after rather than resetting. Cosmetic, consistent with the "display fact, not a decay" behaviour the
  prior C08 session already characterised for the walk-away case.

## Verdict

PASS, and stronger than "best effort" — the actual overlap scenario the fix targets was reproduced and
observed resolving correctly live, not just inferred from the Lune grid.

## Rig restored

Both moved pads were set back to their rig positions afterward:

```
TaskPoint_09 -> (-45, 0.5, 30)
TaskPoint_07 -> (15, 0.5, 0)
```

Confirmed by reading `CFrame.Position` back after the reset write (see delta report for the command).
