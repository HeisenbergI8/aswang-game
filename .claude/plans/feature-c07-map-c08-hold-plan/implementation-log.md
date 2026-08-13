# Implementation log — C07's map half and C08, the Hold task

Run `2026-08-12T04-47-59-486Z-M3`, driven by `/build M3 --tier large`.

---

## Phase 1: The types, the pool verdict, and the Config knobs

**Status:** complete. Four steps, four checks, all green from a terminal. No Roblox API touched.

### Step 1.1 — three new types

`src/shared/Types.luau`, inserted directly above the `-- SERVER ONLY` marker on `RoundState`, exactly
where the plan placed them: `TaskPoolVerdict`, `TaskProgressVerdict`, `TaskProgressPayload`.

`ActiveTask` was **not** changed, per the plan's reasoning — the position lives on the anchor part, and a
second copy of it goes stale the moment C17 moves the greybox.

**Verify:** `npm run verify:fast` → analyze ok · remotes ok (18 declared, 8 wired) · secrecy ok.

Worth recording from that run: `check:remotes` lists both `TaskProgressChanged` and
`RequestTaskProgress` as **declared but not yet wired**. That is the correct state at the end of Phase 1
and it is the line that should change in Phase 4. If it still reads the same after Phase 4, Phase 4 did
not happen.

### Step 1.2 — `src/server/pure/TaskPool.luau`

New file. `evaluate(names, required, expected) -> Report`, blocking-first precedence
(`EMPTY` → `SHORT` → `DUPLICATE_ID` → `OVERSIZED` → `OK`).

Placed under `src/server/pure/` rather than `src/shared/pure/`, which is deliberately the opposite of
`TaskSelection` next door. `TaskSelection` earns its client-callable position over twenty header lines;
nothing here needs that argument re-run, and this module's inputs are the pool contents themselves — the
thing `TaskService`'s seed warning says to keep off the wire.

The `local verdict: Verdict = "OK"` annotation is load-bearing and the plan flagged it in advance: without
it the local infers as plain `string` and fails to satisfy `Report.Verdict`. That is the `Enums.luau`
failure shape that produced six of the scaffold's seven original analyze errors.

**Verify:** `npm run analyze` → ok.

### Step 1.3 — `tests/task-pool.test.luau`

14 assertions across 8 pools. The empty-pool assertion is first in the file because it is the reason the
module exists — `Workspace` is an empty baseplate today, so this is not a hypothetical boundary.

The last pair is the one with teeth: a pool of three identical names has three entries and one usable
point. An implementation counting `#names` where `#unique` was meant reports `OK` on a map with a single
anchor in it, and only this assertion catches it.

**Verify:** `lune run tests/task-pool.test.luau` → `PASS task-pool: 14 assertions across 8 pools`.

### Step 1.4 — three presence knobs, three pinned invariants

`src/shared/Config.luau` gains `PresenceRangeStuds = 9`, `PresenceGraceSeconds = 0.75`,
`HeartbeatInterval = 0.25` under `Config.Tasks`. `tests/config.test.luau` gains the three relationships
that bind them, and its final `print` moved 26 → 29.

The first invariant is the one that matters beyond balance:

> `PresenceRangeStuds * 2 < MinSpacingStuds` — 18 < 20.

That is what makes Phase 4's zero-argument `RequestTaskProgress` **correct** rather than merely tidy. The
server resolves which task point a player is at from their position alone; if two selected points could
be in range at once, "which one" stops having an answer and the only way back is letting the client name
it. It converts `MinSpacingStuds` from a pure balance knob into a correctness constraint, and its comment
in `Config.luau` now says so — otherwise M12 tunes it away without knowing what it was holding up.

Headroom on the other two: grace 0.75 against a heartbeat window of 0.5 (2× interval); a holding client
sends 4/s against `RequestTaskProgress`'s refill of 6/s.

**Verify:** `lune run tests/config.test.luau` → `PASS config: 29 balance invariants`.

### Phase 1 — issues found

None beyond the three the plan predicted, and all three stand as written:

- A type cannot enforce a send shape. `TaskProgressPayload` is only per-player because Phase 4 fires it
  with `FireClient`; nothing in `Types.luau` prevents a later `FireAllClients` with the same annotated
  table, and `check-secrecy.mjs` would not object — none of the three field names carries a secret token.
  This is risk **R1** and it remains prose-only. `exploit-auditor` is the only real defence.
- `check:config` does not govern `src/shared/`, so nothing yet forces a service to read the three new
  knobs rather than retype `0.25`. Phases 2–5 are where that gets enforced, on the files that use them.
- No §6.4 edge case applies. Nothing in this phase observes a player.

---

## Phase 2: The test rig, pool discovery, and the draw

**Status:** complete, plus one step pulled forward from Phase 3 out of necessity. C07's map half is done:
five parts carry `ActiveTaskPoint` at `STARTING` and a different five every round.

### A plan ordering defect, and what I did about it

**Step 2.3's `clearTasks()` calls `RoundService.SetTasksCompleted`, which Step 3.4 creates.** Phase 2
cannot typecheck without it. I built the setter and retired the stale TODO — all of Step 3.4's content —
as part of this phase.

I did **not** edit the plan to fix the ordering: `run-state.mjs` stamps the plan's hash and an edit halts
the run with `plan changed mid-run`. So Step 3.4 is already done when Phase 3 is reached, and its check
(`npm run test:unit`) was run here and passed. Phase 3 has three steps of real work left, not four.

### Step 2.1 — the disposable rig

`workspace.TaskRig_TEMP`, 12 anchored grey pads, 4×3 grid at 30-stud pitch, all tagged `TaskPoint`,
`TaskType` on pad 01 only so the absent-attribute default is genuinely exercised. Placed through
`execute_luau`; no Script or LocalScript was created in Studio.

Full record, including all three console captures verbatim: `artifacts/task-rig.md`.

**Verify:** `test -f .../artifacts/task-rig.md` → present.

The empty-pool proof is the one this step owed constraint 4, and it behaves as designed: the warn fires
**above** `[Bootstrap] Ready`, unconditionally with `VerboseLogging = false`, naming the tag and the
count. The duplicate-name proof fires too, and `TaskPool.evaluate` over the live pool returned
`DUPLICATE_ID` / `Unique: 11` before the rename was undone and `OK` / `Unique: 12` after.

### Step 2.2 — discovery, the verdict, and the one `Random.new()`

`src/server/Services/TaskService.luau`. Stub body replaced; the header's seed section kept, its two TODOs
discharged and replaced with C09/C10 and C12 markers.

`Random.new()` is a **module local**, a deliberate deviation from the header's "create it at `Start()`".
Every property the header asks for survives and one is strengthened: a module local cannot be created
twice, whereas a `Start()` local is one stray second call from a fresh stream — and a fresh stream is not
a bug anyone would notice. It also types as `Random` rather than `Random?`, deleting a nil branch whose
only honest behaviour would be to error inside a phase handler.

**Verify:** `npm run analyze` → ok.

**Three analyze failures the plan did not predict**, all the same shape and worth recording because the
plan predicted a *different* strict-Luau trap (the `IsA("BasePart")` narrowing, which was correct as
written):

> `TypeError: Types BasePart and nil cannot be compared with ==`

Indexing a `{ [string]: BasePart }` yields a **non-optional** `BasePart`, so comparing the result to
`nil` is a type error rather than a lookup. The fix is an explicit `local part: BasePart? = …` at each of
the three lookups, which restores the optional the runtime actually returns. Commented at the first site.

### Step 2.3 — the draw, the tag, the teardown

Subscribes to `RoundService.PhaseChanged` rather than being called from `enterStarting`, which is the
reversal §1.2 of the plan argues for. Confirmed in-engine: every boot logs `13 services loaded`, so there
is no require cycle.

**Verify:** `npm run check:config` → ok (balance stays data-driven).

**That check cannot see whether the subscription works** — it passes on a service that never fires. So
the draw was proven separately in Studio, with debug values set and reverted:

```
[RoundService] -> STARTING (4s)
[TaskService] Round tasks: TaskPoint_03, TaskPoint_04, TaskPoint_05, TaskPoint_08, TaskPoint_11
```

Three consecutive rounds drew three different fives. Closest chosen pair 30 studs against a 20-stud
minimum.

**Teardown, and a misreading I corrected rather than shipped.** A three-sample probe returned
`active=5 ending=0 intermission=5`, which reads as the teardown firing on the wrong phase. It was my
labelling: `execute_luau` starts several seconds into the run, so each sample landed one phase later than
its name. A 1s time series needs no labels and settles it — `5x11 0x9 5x30 0x2`, where the 30-sample run
is exactly `STARTING(4) + ACTIVE(20) + ENDING(6)`. Tags survive ENDING and clear into INTERMISSION, which
is what `clearTasks`'s comment claims and what the end screen needs.

### Step 3.4 (pulled forward) — `SetTasksCompleted` and the retired seam

`src/server/Services/RoundService.luau` gains one clamped setter and loses the
`TODO(C07): TaskService.SelectTasksForRound()` comment, which was an instruction to build a require
cycle. Both TODO sites replaced with a comment stating what happens instead and why.

**Verify:** `npm run test:unit` → 12 files ok, including `task-pool` and the 29 config invariants.

### Phase 2 — issues found

- **A Studio trap worth knowing before Phase 3.** `RoundService.GetPhase()` called through
  `execute_luau` returned `IDLE` while the console showed `ACTIVE` — `require` from the executor yields a
  fresh copy of the module with its own `state` local. Tag counts are datamodel state and do not have
  this problem, which is why every measurement in the artifact is a tag count or a console line and none
  is a service query. This is the trap `.claude/agents/playtester.md` documents; it cost me one wrong
  reading before I recognised it.
- **`ActiveTaskPoint` replicates, deliberately** — §1.3 of the plan is the written answer, and
  `check:secrecy` passes it. It carries no role and no UserId; it is named for a place, not a person.
- **The require-cycle invitation is now gone**, which was the phase's own listed risk.
- **The rig is not published.** The place file is gitignored and Roblox's cloud history is its only
  backup, but publishing a disposable rig would put it in the history C17's real greybox needs.

---

## Phase 3: Server-timed accumulation

**Status:** complete. Step 3.4 was already done in Phase 2 (see above), so this phase was three steps.

### Step 3.1 — `src/server/pure/TaskProgress.luau`

`strongestWeight` + `tick`, four guards. The max-not-sum rule lives here and nowhere else.

**Verify:** `npm run lint` → 0 errors, 0 warnings.

### Step 3.2 — `tests/task-progress.test.luau`

**Verify:** `lune run tests/task-progress.test.luau` → `PASS task-progress: 20 assertions`.

The assertion the file exists for is `four contributors finish no faster than one`. It reads as balance
and is secrecy: a summed rate makes the bar's speed a function of how many people contribute, and C12
zeroes the Aswang's. No other check in this repo would object to "fixing" the max into a sum.

### Step 3.3 — the tick loop

`src/server/Services/TaskService.luau`. Presence is an intent stamp with a grace window; **distance is
re-measured against the live character every tick** rather than trusted from the stamp, which is what
turns the grace window from a teleport-and-idle exploit into a network-jitter allowance.

**Verify:** `npm run check:config` → ok. The `0.25` scheduler interval carries `-- config-ok`.

---

## Phase 4: The remote surface (🔒)

**Status:** complete. No remote was added — both were already declared. `check:remotes` moved from
8 wired to **10 wired**, which is the line Phase 1's log predicted would have to change.

### Step 4.1 — `RequestTaskProgress`

**Verify:** `npm run check:ratelimit` → ok.

The handler takes **no arguments at all**. There is no `typeof` guard because there is nothing to guard:
a table, a function or a 4 MB string is discarded by the argument list itself. `AntiCheatService.Consume`
is the first line, inline at the connect site. Every refusal returns nothing — no verdict, no `false`.

### Step 4.2 — `TaskProgressChanged`

**Verify:** `npm run check:remotes` → ok (18 declared, 10 wired).

`FireClient` per player, never `FireAllClients`, built as a typed `Types.TaskProgressPayload` local.

**A defect in the plan, corrected.** It declares `lastSentProgress: { [number]: number }` and then
assigns `yours`, which is `number?` — an analyze error, and the comment directly above the declaration
says nil is a meaningful value. The annotation contradicted the design. Changed to `{ [number]: number? }`
and the reasoning recorded in the comment.

**A second ordering problem, same family as Phase 2's.** `clearTasks` resets `presence` and
`lastSentProgress`, but the plan declares both far below it, and Luau resolves locals in declaration
order. Both moved up into the round-state block with a comment saying why they live there.

### Step 4.3 — the send budget and the secrecy pass

**Verify:** `npm run check:secrecy` → ok.

`clearTasks` also clears both tables, which the plan's diffs did not do: leaving `lastSentProgress`
populated across a round boundary would suppress the first send of the NEXT round for any player whose
new fill happened to equal their old one — a bar that starts the round refusing to move.

---

## Phase 5: The client reports presence, and nothing else

**Status:** complete.

- **Step 5.1** `src/client/Controllers/TaskController.luau`, registered in `CONTROLLER_ORDER` before
  `InputController`. **Verify:** `npm run analyze` → ok.
- **Step 5.2** the `E` bind via `ContextActionService`, `Begin`/`End`/`Cancel`. **Verify:**
  `npm run lint` → 0 errors.
- **Step 5.3** the role-gate audit. **Verify:** `npm run check:secrecy` → ok.

Step 5.3's audit, run rather than asserted: `GetMyRole` appears at `InputController.luau:51` and `:133` —
the transform and kill binds — and nowhere on the task path. `TaskController` contains **no role
reference of any kind**. That absence is the security property: the Aswang's client sends exactly what a
survivor's sends, and C12 makes the server value it at zero.

---

## Phase 6: The ProximityPrompt affordance

**Status:** 6.1 and 6.2 complete. **6.3 is `needs-human` by design** and is the correct place for this
run to hand back.

### Step 6.1 — the probe

Full record: `artifacts/proximity-prompt-probe.md`.

**Verify:** `test -f .../artifacts/proximity-prompt-probe.md` → present.

The answer that changed the code is question 3: `MaxActivationDistance` defaults to **10** against a
`PresenceRangeStuds` of **9**, and `RequiresLineOfSight` defaults to **true**. Both defaults disagree
with what the server accepts, so setting them explicitly is required rather than cosmetic — a prompt
visible at 10 studs on a task refused at 9 gives the player a stud of "holding does nothing", which is
indistinguishable from a broken game.

Server-created prompts **do** replicate to clients (all five, read from the Client datamodel), so the
plan's fallback of client-side creation is not needed.

### Step 6.2 — the server creates and destroys the prompts

**Verify:** `npm run verify` → **exit 0**, 13 Lune suites, all five checks, analyze, lint, format.

Confirmed in a live round: 5 chosen pads, 5 prompts, every one `dist=9, hold=0, los=false`, and
**0 prompts on unselected pads** — the unchosen seven leak nothing.

### Step 6.3 — deliberately unverifiable

Left for a human. Only one question survives the probe: whether the prompt's own default `E` swallows the
`ContextActionService` bind. Both branches are one line and no `grep` in this repo can tell them apart,
which is why the plan gave this step no `**Verify:**` line and why the phase reports `needs-human`.

### Phase 6 — issues found

- **`execute_luau`'s `require` cache is stale and is NOT the running game's.** It reported
  `Config.Tasks` holding only the six original scaffold keys — missing `MinSpacingStuds`, committed since
  `c15aafc` — while `.Source` on the same ModuleScript contained the new ones. It produced a false
  "the prompt refuses the Config value" reading before I recognised it. The server was never affected and
  there are two independent proofs, both recorded in the probe artifact.

  Together with Phase 2's `GetPhase()` misread this is now **two incidents of the same root cause**, and
  the rule that covers both is: measure through datamodel state or the console, never through a module
  the executor required. Strong `/lessons-review` candidate.
- **Mobile still cannot do tasks.** `createTouchButton` is `false`, matching the transform and kill binds.
  C27's subject, and a bigger hole here than for the other two — 60% of the audience per §5, and tasks are
  what all eight players do all round.

---

## Post-review round — what happened AFTER the plan's six phases closed

**Read this before trusting anything above it.** The plan document is hash-stamped and unedited by
design, so it still describes a C12 mechanism that will now never be built. Everything in this section
happened after `verification.md` was captured.

### ⚠ `verification.md` is STALE relative to this tree

`verification.md` and its three artifacts were captured against a tree that predates `TaskWeight`,
`TaskResolve`, the `TaskSelection` signature change and Amendment A2 by 8–16 minutes. Its three findings
— hold completes in `HoldTime`, spam gains nothing, walk-away freezes — were proven while `taskPointAt`
was still first-match and `weightFor` still contained the pre-A2 logic. **They do not cover the current
code.** `verification-resolver-delta.md` is the pass that does; if it is absent, this delta has no
runtime evidence at all.

### Step 6.3 was resolved, and it was a real bug

The plan left 6.3 as `needs-human`, and the human answer was a defect. **The `ProximityPrompt`'s default
`KeyboardKeyCode = E` silently swallowed the `ContextActionService` bind**, so a player pressing `E` on a
task pad produced literally nothing — no console output, no progress. C08 was server-correct and
human-unreachable, and every static gate was green over it.

Fixed in `attachPrompt`: `prompt.KeyboardKeyCode = Enum.KeyCode.None`. **`None`, not `Unknown`** — the
same zero value at runtime, but `Unknown` is absent from the analyzer's `Enum.KeyCode` type. Evidence:
`artifacts/keyboard-swallow-bug-and-fix.md`.

Known side effect, open for C18: CoreScript logs `unsupported keycode for rendering UI`, so the `[E]`
hint may not render. The mechanic works; the teaching is degraded, which matters because Appendix C
names FTUE as what killed the competitor.

### Amendment A2 — the exploit audit reversed a spec rule

An `exploit-auditor` pass (82/100) found that §4.4's *"the Aswang's progress does not count"* **builds
the oracle it was written to prevent**: progress belongs to the world, a task's fill is legible to anyone
standing at the point, and standing at a point costs one keypress. A survivor taps interact beside
whoever is holding, sees the bar frozen, and knows — repeatable on every player, no inference.

`docs/MVP-SPEC.md` §4.4 now carries **Amendment A2**: the Aswang's progress counts in full; C12's
deception moves entirely onto the information channel. The user also decided that C10's two-person task
counts the Aswang as a full participant.

New: `src/server/pure/TaskWeight.luau` + `tests/task-weight.test.luau` — an exhaustive 4×2
`PlayerState × Role` grid whose load-bearing assertion is that weight does not vary by role.

**A limit worth knowing:** the grid guarantees exactly one function. A follow-up audit (86/100) noted the
oracle's natural home has moved to `TaskWeight`'s *callers* — `weightFor`, the tick's presence loop,
`notePresence`, `publishProgress` — where nothing checks, and that `check-secrecy.mjs` cannot see a
server-side `RoleService.IsAswang(player)` in `TaskService` at all. The proposed guard is a token check
on role reads inside `TaskService.luau`. **Not built.**

### The spacing soft-lock — fixed by shape, not by tuning

The same audit measured that `Config.Tasks.MinSpacingStuds` is a **request**, not a guarantee:
`TaskSelection.select`'s fallback drops spacing rather than short a round, and 2000/2000 draws violated
it on a pool packed into one room. The old `taskPointAt` rested on that guarantee, so a completed point
could mask an adjacent incomplete one — a silent, unwinnable 4/5 with no client feedback.

- `TaskSelection.select` now returns `(chosen, spacingRespected)`; `TaskService` warns unconditionally
  when the fallback fires. Eight call sites in `tests/task-selection.test.luau` take only the first
  value and are unaffected.
- Resolution moved to `src/server/pure/TaskResolve.luau` — **nearest INCOMPLETE point**, ties broken
  toward the lower Id, so table order decides nothing. `tests/task-resolve.test.luau`: 33 assertions,
  the soft-lock in both list orders, plus NaN and both infinities.
- The NaN row exists because the follow-up audit proved `d > range` let a NaN distance fall *through*
  the guard and set `anyInRange` from nothing. Now `not (d <= range)`, which is NaN-total.
- `Config.luau` and `tests/config.test.luau` comments corrected: both had asserted the guarantee that
  never existed. The invariant is kept as defence in depth, which is what it actually is.

### Still open at the time of writing

- **4 stale A2-contradicting comments in `TaskService.luau`** (lines ~538, ~539, ~708, ~720). One of
  them actively instructs the next implementer to put the role branch in `weightFor` — the exact edit
  A2 exists to prevent, at the one place nothing would catch it. Not fixed: `TaskService.luau` is under
  a fix-round escalation and the edit is awaiting the user's call.
- **The `TaskWeight` caller guard** described above. Not built.
- **Ghost weight is reachable today**, not dormant: a player who stamps presence and then dies keeps a
  valid stamp for up to `PresenceGraceSeconds`, during which `weightFor` now returns 0.25 where the
  pre-delta code returned 0. ~2.3% of one task per death. Behaviour change introduced by this delta,
  named here because no test covers it.
- Audit findings 3 (teleport — position is client-owned, no speed check exists anywhere; spec §6.3
  assigns this to C41) and 4 (nothing asserts `Anchored` on a `TaskPoint`) are **deliberately deferred**.
