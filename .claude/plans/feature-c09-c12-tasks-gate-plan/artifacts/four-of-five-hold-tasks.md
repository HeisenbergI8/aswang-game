# Priority 3 — 4/5 tasks completed in one round; the gate did NOT open (correctly, and also not yet proven able to)

Captured 2026-08-12, Studio place `Place3`. Round draw: `TaskPoint_08, TaskPoint_06, TaskPoint_04,
TaskPoint_12, TaskPoint_07` — one TIMING (`04`) and four HOLD (`06, 07, 08, 12`).

## Four HOLD completions, back to back, each ~8s

```
[TaskService] Task complete: TaskPoint_06
[Task] 1/5 · here: 100%
...
[Client] Snapshot — ACTIVE round #1 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (119s left)

[TaskService] Task complete: TaskPoint_07
[Task] 2/5 · here: 100%
[Client] Snapshot — ACTIVE round #1 · tasks 2/5 · gate shut · alive 1 · you: ALIVE (102s left)

[TaskService] Task complete: TaskPoint_08
[Task] 3/5 · here: 100%
[Client] Snapshot — ACTIVE round #1 · tasks 3/5 · gate shut · alive 1 · you: ALIVE (85s left)

[TaskService] Task complete: TaskPoint_12
[Task] 4/5 · here: 100%
[Client] Snapshot — ACTIVE round #1 · tasks 4/5 · gate shut · alive 1 · you: ALIVE (62s left)
```

Each shows the same clean progression (3%, 6%, 9%, ... 97%/98%, complete) as `fetch-end-to-end.md`'s
delivery — a HOLD over `Config.Tasks.HoldTime = 8`. `gate shut` is correctly still reported after each,
since 5 are required.

## The fifth task (TIMING, `TaskPoint_04`) did not land before the round ended

With 62s left, I moved to `TaskPoint_04` and fired a 5-call burst of `RequestTimingStop` (the same shape
recorded in `timing-r-press-and-spam.md`). All 5 came back misses:

```
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[RoundService] -> ENDING (6s)
[Client] Phase -> ENDING (6s)
[Client] Snapshot — ENDING round #1 · tasks 4/5 · gate shut · alive 1 · you: ALIVE (5s left)
```

The round ended at **4/5**, `ACTIVE(150s)` having elapsed while I was working through the other four.
`gate shut` throughout, which is the CORRECT behaviour at 4/5 — but it means **the gate opening and a
survivor escaping are still unobserved**. This is the single biggest gap left in this report.

## What I take from this

- Four of the five task TYPES this plan added are now proven completable in the engine by direct
  observation, not only by the Lune grids: HOLD (x4 here, plus prior M1 evidence) and FETCH
  (`fetch-end-to-end.md`). TIMING is proven *reachable and responsive* (`timing-r-press-and-spam.md`) but
  not proven *completable* — no successful 3-hit run was observed in any session.
- The 12-point pool with only 5 TIMING/FETCH/TWO_PERSON-typed pads and 7 defaulting to HOLD means a draw
  is not guaranteed to be gate-testable within one `Duration=150s` debug round if it includes a TIMING or
  TWO_PERSON pad — TIMING because landing 3 hits without a rendered bar (C18 not built yet) is genuinely
  hard to do deliberately, and TWO_PERSON because it cannot be completed solo at all. Getting a TIMING or
  TWO_PERSON-free draw is a `C(11,5)/C(12,5) ≈ 58%` per-pad-type chance, and I did not get a favorable
  enough combination before running out of report-writing time.
