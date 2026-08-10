---
name: lesson-keeper
description: Record, consolidate, and prune the hard-won lessons in .claude/lessons/. Use when a non-obvious failure has just been resolved, when the lessons audit reports warnings, or when asked what has been learned in this repo.
---

# Lesson Keeper

The store in `.claude/lessons/` exists so a mistake costs its debugging time **once**. It is capped at 40
files and injected into context automatically, which means every entry is paid for in tokens on every
matching prompt. That budget is the discipline: this skill is mostly about **refusing** to write things
down.

The expected rate is **about one lesson per session, frequently zero.** If you are recording more than
that, the bar has slipped.

## The bar — all four, or it does not get written

**1. Recurrence.** Will this plausibly happen again in *this* repo, on *this* stack? A one-off typo, a
transient network failure, or a mistake made through carelessness rather than missing knowledge fails
here.

**2. Non-obviousness.** Would a competent developer reading the code already know? If it is stated in
`CLAUDE.md`, in `docs/MVP-SPEC.md`, in a type signature, or in the error message itself — it fails.
**Check `CLAUDE.md` before writing.** Duplicating it is the most common way this store bloats.

**3. Behaviour change.** Does it change what you would *do*, not merely what you would know? "Remotes are
declared in Remotes.luau" is a fact and it is already documented. "When a client script does nothing at
all with no error, check for an undeclared remote before anything else — `WaitForChild` hangs silently"
is a lesson: it changes the first thing you reach for.

**4. Cost.** Did getting this wrong actually cost something — an hour, a lost map, a wrong deliverable?
Cheap mistakes that self-correct in seconds are not worth a permanent slot.

## Never record

- Anything already in `CLAUDE.md` or `docs/MVP-SPEC.md` — link to it instead
- Anything git history answers ("we changed X to Y in commit Z")
- Generic engineering advice — "write tests", "read the error"
- A restatement of a Roblox API's signature — that belongs in the code and its types
- Balance values or design opinions — those are `Config.luau` and the spec, and they change every
  playtest
- "Remember to run `npm run verify`" — that is a hook's job, and it already has one

## Writing one

```markdown
---
id: kebab-case-slug          # unique; matches the filename
trigger: five, to, eight, terms    # retrieval keys — this is what makes it findable
scope: harness | studio | gameplay | process | assets
learned: YYYY-MM-DD
evidence: the concrete incident, one line
---

**Lesson:** One sentence, imperative. This is the index line — it must stand alone.

**Why:** The mechanism. What actually happened and what made it non-obvious.

**Do:**
- Specific, checkable actions
- Name the file, command, or flag involved
```

Keep the body **under 25 lines** — `audit` warns past that. A lesson needing more room is usually two
lessons, or belongs in `CLAUDE.md`.

**Triggers are the highest-leverage field.** A lesson that never matches a prompt was never written. Use
the words that appear in a *request* or an *error message*, not the words you would use to categorise it
afterwards — "hang", "nothing happens", "no error" rather than "networking". `audit` reports lessons that
have never matched; that is a trigger bug, not on its own a reason to delete.

## Keeping it sharp

Growth is not the goal. `node .claude/scripts/lessons.mjs audit` is wired into `npm run verify` — act on
what it says:

**Consolidate** when two lessons share three or more triggers. They will always inject together, so they
are one lesson filed twice.

**Promote** when a lesson has hardened into a rule. This is the most important move and the most often
skipped:

| Lesson has become | Move it to | Then |
| --- | --- | --- |
| A standing convention | `CLAUDE.md` | delete the lesson |
| A mechanically checkable rule | a check script in `.claude/scripts/` | delete the lesson |
| A design decision | `docs/MVP-SPEC.md` or a decision record | delete the lesson |

Add `encoded: <path>` to the frontmatter when you promote it, with `encodedAtHits: <current hit count>`.
`audit` then watches whether the lesson goes quiet, and tells you when it has earned deletion.

**A promoted lesson is deleted, not archived.** In a repo built on mechanical enforcement, the best
outcome is that a lesson stops being a lesson and becomes code. `.claude/lessons/` stages what is not yet
enforceable. The store getting *smaller* because three entries became one check script is the system
working as designed.

**Prune** when the lesson is obsolete: it names a file that no longer exists, a tool version that has been
upgraded past, or a Roblox behaviour that has changed. Verify before deleting — `git log` and the actual
file, not memory.

## At the cap

At 40, `audit` fails the build. Do not raise `MAX_LESSONS`. Consolidate, promote, or prune — the cap is
what forces the store to stay high-signal, and raising it is how a curated set becomes a log.

## Consulting

Automatic. `lessons.mjs inject` runs on `UserPromptSubmit`: the index once per session, and the full text
of any lesson whose triggers match. You do not need to remember to read them.

What you **do** need to do is act on one when it appears. An injected lesson is a prior decision by
someone with more context than you have right now — the incident is in the `evidence:` line. Override it
if you have a reason, but say that you are.
