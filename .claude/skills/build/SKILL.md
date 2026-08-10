---
name: build
description: Start or steer a supervised task-loop run. Use when the user types /build, or asks to build a milestone autonomously and have the loop keep going until it is done or a cap is hit.
---

# Build

`/build` starts a **supervised loop**: code decides whether to continue and what is next, you do the
work. The run record is created by `build-trigger.mjs` on `UserPromptSubmit` — **not by you**. If this
skill were the thing that created it, a turn where you forgot would produce no run at all, and the driver
would release forever, which looks exactly like the loop working correctly.

So your job here is the judgement, not the bookkeeping.

```
/build <milestone> [--tier small|medium|large]
/build --status | --halt | --resume
```

## What has already happened before you read this

The hook has created the run and told you the objective. What it has **not** done is decide the tier or
produce a plan, because neither is mechanical.

## The loop only drives Large-tier work

This is a consequence of what the tiers produce, not a limitation to route around. The cursor advances
through `#### Step N.M` headings in a plan document, and CLAUDE.md's routing table gives an architect —
and therefore a plan — to **Large only**. Small and Medium go straight to implementation, so there is no
plan, no phases, and nothing for the cursor to read.

So `/build <x> --tier small` and `--tier medium` are **refused outright**, with an explanation. A run
that appeared to start and then drove nothing would look exactly like the loop working, which is the
failure this whole system exists to prevent.

If the work is genuinely Small or Medium, do it directly — implement, then `playtester` +
`change-auditor`. That is what the routing table already prescribes and it is cheaper than a plan.

**For a first run, prefer a deliberately narrow Large:** a scope that yields two or three phases rather
than seven. One mechanic end-to-end, one service against a contract already proven. Real plan, real
cursor advancement, bounded blast radius.

## Your first move: size it

Use CLAUDE.md's routing table, and **say the tier out loud in one line**. That announcement is the
enforcement — a tier stated is a claim the user can correct in three words; a tier never stated cannot be
challenged.

**Large** — state the tier and the agents you intend to run, then **wait for confirmation**. The hook
deliberately refuses to guess Large for you, because that tier is expensive.

A run with no plan bound **releases** for three turns while you produce one, then halts with
`no plan bound`. That patience is bounded on purpose: an earlier design drove instead, blocking every
turn to say "re-read the plan and the cursor" while pointing at a document that did not exist.

## Before the first phase: check the entry conditions

```bash
npm run preflight            # toolchain, green tree, clean tree
npm run preflight -- --studio  # add this when the milestone needs Studio
```

A dirty tree is refused deliberately. Once a run is live, "what did this run change" has to have an
answer, and it does not if the tree was already modified when it started.

## Binding a plan

The loop's cursor reads a plan. Without one it has nothing to advance through, so once a plan exists:

```bash
node .claude/scripts/run-state.mjs plan .claude/plans/<type>-<name>-plan/<file>-plan.md
```

This stamps the plan's hash. Editing the plan afterwards halts the run with `plan changed mid-run` —
deliberately, because every phase number and step id the cursor reports would otherwise describe a
document that no longer exists.

Before starting, check the plan can actually prove itself:

```bash
npm run verify:plan .claude/plans/<...>/ -- --lint     # unrunnable, shared and absent checks
```

A step whose check is shared with a sibling in the same phase proves nothing about itself, and a phase
containing one reports `needs-human`. Fix those in the plan before the first iteration, not at phase
four.

## Then: one phase per iteration

Follow `implement-plan`. Implement, gate with `npm run verify:fast`, append to `implementation-log.md`.
**Do not pull work forward from a later phase** — the cursor measures progress per phase, and a phase
that quietly absorbed the next one's work reads as stuck.

When the turn ends, the driver decides. If it blocks, the reason names the next phase and lists what this
run has already tried. Read that list: repeating a failed hypothesis is the specific failure the attempts
ledger exists to prevent.

## What stops it

Halts are unconditional and evaluated before anything else — budget, preflight failing twice, plan drift,
a plan whose checks cannot fail, a phase stuck for three iterations, a tree red for four, a phase needing
a human, or `goal-check` reporting done.

Every halt writes `.claude/.run/<id>/halt-report.md` and blocks once. **When that happens, tell the
user** — what stopped it, what changed, and which of the two paths in the report you recommend. The run
does not restart.

## Talking while it runs

Any message that is not `/build …` **pauses** the run. A user message pauses; it does not amend the
objective. Resume with `/build --resume`.

A live run **claims exclusive ownership of the working tree** — `/build --status` makes that visible. Do
not start unrelated edits while one is live.

## The honest limit

A halt reporting `done` means **four proxies were satisfied**: the plan's steps passed, `npm run verify`
is green, `implementation-log.md` exists, and `verification.md` cites a file in `artifacts/`.

The artifact check is the strongest of the four and it is still a proxy — it proves a screenshot or a
console log EXISTS and was cited, never that it shows the right thing. A person still has to open it.

And none of the four can tell you whether the round is fun. That is what M5 and M12 are for, and the
`playtest` skill covers them. Say this when you report a completed run rather than presenting `done` as a
verdict on the work.
