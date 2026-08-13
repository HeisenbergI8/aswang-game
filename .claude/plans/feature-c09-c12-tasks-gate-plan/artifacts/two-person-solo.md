# Priority 4 — Two-person, alone, makes no progress

Captured 2026-08-12, Studio place `Place3`, round with `TaskPoint_05` (TWO_PERSON) drawn.

Teleported to `TaskPoint_05` at `(-45, 0.5, 0)`. Held `E` continuously for 5s (`keyDown` -> `wait 5000ms`
-> `keyUp`).

```
[Task] 0/5 · here: 0%
[Task] 0/5 · here: -
```

Progress read **0%** at the start of the hold and stayed there for the full 5s — it never advanced, and
went back to `-` (not present) on release. This matches `TaskService.luau:981-990`: a `TwoPerson` task's
weight is forced to `0` unless `TaskParticipants.meets(...)` is satisfied, and one player alone cannot
satisfy `TwoPersonParticipants = 2`. The bar FREEZES rather than resets, per the same code path used for
a HOLD task with nobody present — consistent with the "progress belongs to the world" anti-frustration
rule the plan cites.

**C10's actual Done condition — two survivors present opens the task — is unverified and unverifiable by
one agent.** This only proves the negative half (alone = no progress), which is what the brief asked for.
No Studio MCP tool can drive a second client; Test → Clients and Servers → 2 players is a human action.
