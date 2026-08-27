---
name: implement-plan
description: Execute an architect plan phase by phase with verification gates. Use when implementing a plan from .claude/plans/, or when the user says "implement the plan", "build this", "go ahead" after a plan exists. Also use for any multi-file change large enough to need ordered phases, even without a formal plan.
---

# Implement Plan

Execute an approved plan on the main thread, one phase at a time, proving each phase works before
starting the next.

You run here rather than in a subagent on purpose: you keep the full conversation, you can ask the user a
question mid-flight, and the user watches the work land. Use that. When something in the plan turns out
to be wrong, stop and say so — do not silently improvise around it.

## Before Writing Anything

1. You run in the main thread, so `CLAUDE.md` is already in your context — do not re-read it. Re-read one
   *section* only if you need to check a specific rule.
2. Read the plan's **phase index**, not the whole document:

   ```bash
   npm run plan:phase -- .claude/plans/<type>-<name>-plan/
   ```

   It prints each phase's title, line range, step count, token cost and the `references/` reviews that
   phase actually cites. Add `-- <plan> 1 --with-preamble` to read Phase 1 together with everything above
   it, which is where the plan states its decisions.

   **Do not read the plan document whole, and do not read `references/` wholesale.** A plan runs 100–230KB
   — the c13–c16 plan is ~57k tokens across 8 phases, with another ~22k in 16 reference reviews. You
   implement one phase at a time, so loading all of it costs roughly 8x what the phase in front of you
   needs, and you re-pay it on every turn for the rest of the run. Read the index now; read each phase
   when you reach it.
3. Load the `lean-code` skill. Every line you are about to write should survive its questions.
4. Confirm the phase order still makes sense against the current tree. If the repo moved since the plan
   was written, say so before proceeding.
5. If any phase touches Studio, load `studio-sync` and confirm `rojo serve` is running. Implementing four
   phases against a disconnected Studio produces four phases of unverified work.

## The Loop

For each phase, in order:

### 1. Load the phase
Read the phase you are about to work, and only that phase:

```bash
npm run plan:phase -- .claude/plans/<type>-<name>-plan/ <N>
```

Then read the `references/` reviews the index named for **this** phase — those carry the annotated
reasoning behind its steps, and skipping them is how you re-derive a decision the architect already made
and get it wrong. The ones belonging to other phases are not your business yet.

### 2. Announce
State which phase you are starting and which files it touches. One or two sentences.

### 3. Implement
Work the phase's steps. Stay inside the phase — do not pull work forward from a later phase because you
happen to be in the file. Scope creep is what makes a plan unverifiable, and the loop's cursor reads a
phase that absorbed the next one's work as *stuck*.

Follow the conventions in `CLAUDE.md` as you write, not as a cleanup pass afterwards: `--!strict` at the
top, tabs, double quotes, 100 columns, every tunable read from `Config`, every new remote declared in
`Remotes.luau`, every `OnServerEvent` handler consulting `AntiCheatService` first.

### 4. Gate
Run the phase's verification command before moving on:

```bash
npm run verify:fast   # analyze + remotes + secrecy + toolchain — every phase
npm run verify        # adds lint, format, config, scope, ratelimit, tests — before the final phase closes
```

A `Stop` hook runs `verify:fast` when the turn ends, so a red gate you skipped surfaces anyway. Running
it yourself at the phase boundary is how you find out *before* you have built three phases on top of it.

**A phase is not done until its gate is green.** Do not start phase N+1 on a red gate, and do not tell
the user a phase is complete when it is not.

### 5. Log
Append to `implementation-log.md` in the plan directory:

```markdown
## Phase N: [name] — [YYYY-MM-DD]

**Steps completed:** N.1, N.2, N.3
**Files changed:** `src/server/Services/X.luau`, `src/shared/Config.luau`
**Deviations from plan:** [what differed and why, or "none"]
**Gate:** analyze PASS / check:remotes PASS / tests 13/13
**Notes:** [anything the playtester or auditor needs to know]
```

This log is what the auditor reads. Deviations recorded here are legitimate engineering judgement;
deviations discovered by the auditor in the diff are findings against you.

### 6. Checkpoint
After each phase, tell the user in one or two lines what landed and what is next — then **start the
next phase in the same turn**. A checkpoint is a progress report, not a question.

**Pause for confirmation only when the answer changes what you build next:** a deviation that alters
the plan's REMAINING phases, a step you believe is wrong, a destructive or outward-facing action, or a
decision that is genuinely the user's. A type annotation, a reordered diff, a renamed local — log those
under **Deviations** and keep going.

**Inside a `/build` run this is enforced, not advised.** `guard-loop-pause.mjs` blocks a turn that ends
by asking to continue a live run, because the run *is* the permission: `/build` stops for a problem and
nothing else, and any message from the user — including "yes, continue" — **pauses the run**. That is
how a loop halts at `iterations: 0`, having driven nothing, looking exactly like a working one.

A real blocker is still a real blocker. Say so plainly and name it as one; the guard does not match a
substantive question, and it stands aside after two blocks regardless.

## When a Gate Fails

Fix it — but count your attempts. On the **third** consecutive failed attempt at the same gate, stop and
load the `debug-ladder` skill. You do not have to remember to: `loop-breaker.mjs` counts identical
failing commands, injects the ladder at 2 and blocks at 3. Treat that injection as the instruction it is,
rather than as noise to work around.

## When the Plan Is Wrong

Plans are written before contact with the code, and in this project also before contact with Roblox's
actual behaviour. When a step turns out to be impossible, unnecessary, or based on a wrong assumption:

1. Stop implementing that step.
2. Tell the user what the plan assumed and what is actually true.
3. Propose the correction.
4. Record it under **Deviations** once resolved.

Never implement a step you believe is wrong just because it is written down, and never quietly skip one.

**Do not edit the plan document while a `/build` run is live.** The run stamped its hash at start;
editing it halts the run with `plan changed mid-run`, because every phase number the cursor reports would
otherwise describe a document that no longer exists.

## Definition of Done

The plan is complete when every phase gate is green, `npm run verify` passes across the tree,
`implementation-log.md` covers every phase, and you have told the user plainly which plan steps you did
**not** implement and why.

Then hand off — launch these **in one message** with `run_in_background: true`:

- `playtester` — does it actually work, with an artifact in `<plan>/artifacts/`
- `auditor` — every plan step traced to a `file:line`
- `exploit-auditor` — **if the diff touched `src/server/**` or `Remotes.luau`**

Do not audit your own work. You already believe it is right, which is exactly why someone else should
look.
