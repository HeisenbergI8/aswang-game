---
name: lessons-review
description: Distil the raw candidate log into lessons, or decide that nothing in it qualifies. Use when `npm run verify` reports "REVIEW DUE", when the user asks what has gone wrong lately, or when the lessons audit reports consolidation or graduation warnings.
---

# Lessons Review

`.claude/.candidates.jsonl` captures generously and costs nothing — it is never injected into context.
`.claude/lessons/` is capped at 40 and is paid for on every matching prompt. This skill is the filter
between them, and **its normal output is "nothing qualifies"**.

## When it is due

`npm run verify` prints `- candidates: N/15`. At 15 a review is due. That threshold is not a deadline —
below it there is nothing to cluster, since a review of four entries finds four one-offs.

## The review

```bash
npm run candidates                      # newest first; ** marks high confidence
node .claude/scripts/lessons.mjs list    # what is already on file, with hit counts
node .claude/scripts/lessons.mjs audit   # cap, duplicates, graduation, prune candidates
```

Work **newest first**. Recent incidents are the ones you can still reconstruct, and the value of a
candidate decays fast — a line reading `[user-correction] why is there no playtester` means something
today and nothing in three weeks.

### 1. Cluster before judging

Read the whole list once before deciding anything. The signal is **repetition**, not severity: three
entries about the same confusion are one lesson, and one dramatic entry is usually a one-off.

Three candidates saying "nothing happened in Studio" is a lesson. One saying "the analyzer crashed" is a
Tuesday.

### 2. Apply the four-test bar

For each cluster, `lesson-keeper`'s bar: recurrence, non-obviousness, behaviour change, real cost. All
four, or it does not get written. Most clusters fail on non-obviousness — the answer is already in
`CLAUDE.md` and the incident was someone not reading it, which is not a lesson.

### 3. Prefer a check script to a lesson

Before writing a lesson, ask whether the thing could be **enforced instead of remembered**. This repo
already has seven check scripts, and each one started as something a person kept getting wrong.

| The lesson would say | The check that replaces it |
| --- | --- |
| "declare every remote before using it" | `check-remotes.mjs` |
| "never put the role on an attribute" | `check-secrecy.mjs` |
| "keep tunables in Config" | `check-config.mjs` |
| "don't build a second monster" | `check-scope.mjs` |
| "rate-limit every handler" | `check-ratelimit.mjs` |

A check is strictly better than a lesson: it fires on the code rather than on the prompt, it costs no
tokens, and it cannot be forgotten. **A lesson is what you write when a check is not possible** — when
the thing is a judgement, a sequencing habit, or knowledge about a tool's behaviour.

If you write a check instead, say so in the review and clear the candidates it covers.

### 4. Write, or write nothing

Write at most one or two lessons per review. If you are writing five, you have stopped filtering.

Then clear only what you actually read:

```bash
node .claude/scripts/candidates.mjs clear --before 2026-08-10
```

`--before` rather than a bare `clear`. A review rarely finishes the whole backlog, and dropping an unread
tail means the next review starts from a false baseline with the incidents gone.

### 5. Act on the audit warnings

`audit` reports three things worth acting on immediately:

- **GRADUATED** — a lesson names a guard in `encoded:`, the guard exists, and the lesson has not matched a
  prompt since. It has done its job. Verify the guard has both-direction tests, then **delete the
  lesson**. The store shrinking is the system working.
- **Shared triggers** — two lessons sharing three or more terms always inject together, which means they
  are one lesson filed twice. Merge into the better-named one, keep the union of triggers.
- **Never matched** — a lesson with zero hits after 25 sessions has the wrong triggers, not the wrong
  content. Fix the triggers before considering deletion; the words in the frontmatter should be the words
  that appear in a *request* or an *error*, not the category you filed it under.

## Report back in three lines

```
Reviewed N candidates (M high-confidence).
Wrote: <lesson id>, or "nothing — all N failed the bar on <which test>".
Also: <check script written / lesson graduated / triggers fixed>, or "nothing".
```

Then say plainly what the candidates were *about*, even when none qualified. That summary is often the
most useful output of the whole exercise — a pattern of corrections about the same thing is worth knowing
even when no single one earns a permanent slot.
