# Step 6.5 — the disposable `EscapeGate` anchor, and 🔒 the C12 decoy list proven in a live round

Captured 2026-08-12, Studio place `Place3`.

> **NOT THE GREYBOX.** One green slab in plan 1's disposable `workspace.TaskRig_TEMP`. C17 replaces it.

## 1. The gate anchor

One `Part`, `EscapeGate_TEMP`, `12 × 10 × 2`, at `(0, 5, 90)` — beyond the far edge of the 4×3 pad grid
so reaching it is a run rather than a step. Tagged `EscapeGate`, anchored, `Transparency = 0`,
`CanCollide = true`.

`GateService` found it at boot: no `NO "EscapeGate" PART IN THE MAP` warning appeared in any run below,
and that warning is unconditional, so its absence is the positive result.

## 2. The gate stayed shut, and that is the correct outcome

Sampled during ACTIVE and again after the round, in a round that finished **0/5**:

```
DuringActive: GateTransparency = 0, GateCanCollide = true
AfterRound:   GateTransparency = 0, GateCanCollide = true
```

`RoundService.SetTasksCompleted` derives `GateOpen` from the count and the phase, and the count never
reached 5, so it never flipped. The client agreed on every snapshot:

```
[Client] Snapshot — ACTIVE round #1 · tasks 0/5 · gate shut · alive 1 · you: ALIVE
```

**What this does NOT show:** the gate has never been seen OPENING, and no survivor has ever escaped.
Both need 5/5, which needs a player to complete five tasks. `tests/gate-escape.test.luau` proves the
rule over all 64 cells; the engine has proven only that the shut case is shut. **Do not report C11 as
verified.**

## 3. 🔒 The decoy task list, proven against the real five

This is the evidence Phase 7 exists for, and it needed `Debug.ForceAswangWhenSolo` — set for this run
and reverted with the other five values afterwards.

The **true** five, read off the replicated `ActiveTaskPoint` tag (which is exactly what a compromised
client can read):

```
RealFive: TaskPoint_01, TaskPoint_06, TaskPoint_07, TaskPoint_10, TaskPoint_11
```

The server's own draw log agrees:

```
[TaskService] Round tasks: TaskPoint_11, TaskPoint_07, TaskPoint_10, TaskPoint_06, TaskPoint_01
```

What the **Aswang's client** was told, printed by `TaskController`:

```
[Task] list: TaskPoint_11, TaskPoint_07, TaskPoint_09, TaskPoint_04, TaskPoint_10
```

| | |
| --- | --- |
| Length | **5 and 5** — `TaskListView` guarantees it, and `#myTaskList` is the cheapest oracle a client has |
| Genuine points shown | `11, 07, 10` |
| Decoys shown | **`09, 04`** — neither is a live task this round |
| Real points hidden | `01, 06` |

The overlap is the design, not a leak: `TaskListView`'s header explains that a decoy guaranteed to be
**disjoint** from the real five would be partially invertible by elimination. A partial overlap is not.

### The survivor control, from the previous run

With `ForceAswangWhenSolo` **off**, the same solo player is a survivor, and the list matched the draw
exactly:

```
[TaskService] Round tasks: TaskPoint_07, TaskPoint_04, TaskPoint_10, TaskPoint_12, TaskPoint_03
[Task] list:               TaskPoint_07, TaskPoint_04, TaskPoint_10, TaskPoint_12, TaskPoint_03
```

Two runs, one flag apart: the survivor is told the truth, the Aswang is told a same-shaped lie. That is
the whole of C12.

### The ceiling, restated because it is easy to forget after seeing this work

`ActiveTaskPoint` **replicates**. The "RealFive" line above was read with one call any client can make.
An exploiter defeats this decoy in one line of Luau, and **no balance decision may depend on it**. What
it buys is an honest Aswang paying real walking time — up to 160 studs to a `FETCH` decoy — for a list
it cannot trust.

## 4. What is still unproven

- The gate opening, and a survivor winning (needs 5/5).
- 🔒 An Aswang standing in an **open** gate and the round NOT ending — the one bit §4.8 inherently
  leaks, and the case `GateEscape`'s grid covers but the engine has not.
- Two-person tasks entirely: C10's Done condition is multi-client and no agent can drive a second
  Studio client.
- The `R` timing bind against a possible CoreScript claim. C08 shipped unreachable on exactly this
  class of collision, and `R` has only been established free of the *known* one.
