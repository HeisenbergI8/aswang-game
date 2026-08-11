---
id: green-after-each-patch-hides-a-loop
trigger: fix, fixed, guard, edge case, NaN, boundary, degenerate, still wrong, third attempt, patch, again, audit found
scope: process
learned: 2026-08-12
evidence: KillValidation's clock guard shipped wrong three times and the attrition arithmetic three times; verify was green after every one, so no loop-breaker, repair loop or debug-ladder ever fired
---

**Lesson:** This harness detects repeated *failure*, not repeated *insufficiency*. A patch that turns
the tree green and is then found wrong by the next review is invisible to every loop guard here — so
count fix ROUNDS on a location yourself, and after the second, change the shape instead of patching.

**Why:** `KillValidation`'s cooldown guard was written four times; the attrition rule three, and the
third was arithmetically *inert* — an auditor replayed it through the shipped module and got identical
outcomes with and without it. Nothing caught this, and that is not an oversight in the guards:
`loop-breaker` needs a Bash command to fail (none did), `verify-gate` needs a red tree (it was green
every time), `debug-ladder` needs an error to survive a fix (each fix erased its own symptom). Every
attempt passed the tests I had thought to write — which were the cases I had just thought of. The next
hole arrived in a fresh turn as a new finding, with no memory it was the same line. Four review rounds,
roughly half a million subagent tokens, largely re-covering ground.

**Do:**
- For a **pure predicate over a bounded domain, enumerate the domain.** An auditor found in ONE pass,
  with a 23-cell grid over `Now × LastRevertedAt × Cooldown ∈ {finite±, 0, ±inf, NaN}`, what four
  reactive patches failed to converge on. Write the grid before the guard, not a case per bug.
- Count fix rounds per location. **Two is a signal, three is a redesign** — say so and put the choice to
  the user rather than writing a third patch. The rule's shape is usually what is wrong.
- Distrust any comment asserting an invariant. Three defects came from one path being fixed while its
  twin was not, with a comment claiming otherwise (`MarkKilled` vs `onPlayerRemoving`).
- A fix prescribed by a review is still a fix: it earns the same grid, not more trust.
**Not yet encoded.** The mechanical half is a per-location fix-round ledger — `record-activity.mjs`
already logs edits per turn, so a Stop guard could block at three edits to one file with "change the
shape". Written as a lesson because *which* shape is a judgement. Graduate and delete once that exists.
