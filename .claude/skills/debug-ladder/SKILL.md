---
name: debug-ladder
description: Escape a repeated-failure loop. Load when the same analyzer error, check, test or in-game behaviour has survived two or more fix attempts, or when you notice you are trying variations of a solution that already failed. Enforces an attempt budget, a written ledger, and escalation to the user.
---

# Debug Ladder

You are here because something failed more than once. The purpose of this skill is to stop you from
spending the next hour producing variations of a fix that has already been proven wrong.

The core failure mode: an attempt fails, you adjust a detail and retry, it fails again, and because each
attempt *feels* new you never notice the shape is identical. **The ledger is what breaks that**, because
you have to read your own history before attempting again.

## Step 1: Write the Ledger First

Before the next attempt, open `attempts.md` — in the plan directory if one exists, otherwise the
scratchpad — and record what has happened:

```markdown
# Attempt ledger: [one-line problem statement]

**Symptom (verbatim):**
```
[the exact output, not a paraphrase]
```

**Reproduction:** [exact command, or the click path in Studio]

| # | Hypothesis | Change made | Result |
| --- | --- | --- | --- |
| 1 | [what you believed was wrong] | [what you changed] | [what actually happened] |
```

Writing down the **hypothesis** is the point. Two attempts with different code but the same hypothesis
are the same attempt, and you can only see that once it is written.

## Step 2: Climb the Ladder

Each rung must differ from the last in *kind*, not in detail. If your next move is the same kind as the
previous one, skip up a rung.

**Rung 1 — Read the error properly.** Read the full output, not the last line. Open the file at the exact
line and column cited. Check whether the error is even about what you assume — a strict-Luau error in a
service is often caused by a type in `Types.luau` or an enum field in `Enums.luau`.

**Rung 2 — Verify your assumptions.** Do not reason about what the code does; run it and observe. In this
repo that has a specific meaning: **is Studio even looking at your code?** `rojo serve` running, the
plugin connected, the right place open. A change with no effect is far more often a sync problem than a
logic problem, and `studio-sync` lists the three checks in order.

**Rung 3 — Shrink the surface.** Reproduce with the smallest possible input. If the failing thing is
logic, extract it as a pure function into `src/shared/pure/` and write a Lune test that fails. That
converts an intermittent in-game symptom into a deterministic one you can run in 200ms, and it is the
single most effective move available in this project.

**Rung 4 — Bisect.** Did this ever work? `git stash`, or check out an earlier commit and run the same
command. Establish whether your change caused it before spending more time on your change.

**Rung 5 — Question the target.** Consider that the test, the plan step, or your understanding of the
requirement is what is wrong. This rung is frequently correct and almost always reached too late. In this
repo it has a common shape: the spec section you are implementing says something slightly different from
what you remember it saying. Re-read it.

## Step 3: The Hard Threshold

**After three attempts on the same symptom, stop and escalate.** This is not a suggestion to weigh
against how close you feel you are — feeling close is the characteristic sensation of being stuck.

The threshold is enforced mechanically, not left to your judgement. `loop-breaker.mjs` counts consecutive
failures of the same command: at 2 it injects this skill, at 3 it blocks the call outright, and a second
block halts. `verify-gate.mjs` does the same for a red tree, keyed on the failure's *signature* rather
than on a retry count — so three DIFFERENT failures is progress and resets it, while the same one three
times halts.

If you are reading this because one of them fired, the count is already spent. Do not attempt a fourth
variation.

Escalating means reporting to the user:

- The symptom, verbatim.
- The ledger — every hypothesis tried and why each was wrong.
- What you now believe the real cause is, with your confidence.
- The two or three paths forward you can see, and which you would choose.
- The specific thing you would need in order to be sure — a second player, a look at the place file, a
  decision about intended behaviour.

Leave the code in a clean state. Revert speculative changes that did not help; do not leave a trail of
half-fixes.

## Rules

- **Never repeat an attempt already in the ledger.** If it is written down, it is spent.
- **One variable at a time.** Changing three things and getting a pass teaches you nothing about which
  mattered — and in a game with tuned numbers, that is how balance becomes unreproducible.
- **Never weaken a check to make it pass.** Adding a `secrecy-ok:` or `config-ok:` waiver to silence a
  finding you do not understand converts a visible failure into an invisible one. Waivers need a reason
  that would convince a reviewer, and `--update` on the analyze baseline refuses to run under an agent
  for exactly this reason.
- **Never widen scope to escape.** Refactoring the surrounding service to avoid a bug you do not
  understand buries it.
- **Timebox rather than grind.** If a rung is taking long enough that you have stopped forming new
  hypotheses, climb.

## Recognizing You Are Looping

Watch for: rerunning an unchanged command expecting a different result; changing formatting or ordering
rather than behaviour; adding `print` statements without a specific question; "let me try X again, maybe
with…"; a growing pile of small edits none of which you can explain the reason for; pressing Play in
Studio a fourth time hoping the round behaves differently.

Any of these means you are already past the point of escalation.
