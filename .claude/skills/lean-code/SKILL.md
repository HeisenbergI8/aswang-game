---
name: lean-code
description: Discipline for writing the minimum Luau that solves the problem — search for what exists before adding anything, and resist premature abstraction. Load BEFORE writing a new module, service, type or helper, and whenever a task smells like it will produce a lot of code.
---

# Lean Code

The cheapest code to maintain is the code you did not write. This skill runs **before** you type. For
cleanup of code that already exists, use `/simplify`.

There is a second reason it matters here specifically: this is a solo project with no deadline and a hard
scope line. Every module you add is a module you maintain alone, forever, and the spec's §3 boundary
exists because the closest competitor drowned in exactly that.

## The Search-First Rule

Before writing any new helper, type, service or controller, spend one search proving it does not already
exist:

```bash
grep -rn "TransformTime\|KillRange" src/           # is this number already named?
grep -rn "function .*Service\." src/server/Services/
ls src/shared/ src/server/Services/ src/client/Controllers/
```

Known shared ground worth checking every time:

- **`src/shared/Config.luau`** — every tunable number. If you are about to type a number, it belongs here
  or it is already here. `check:config` enforces this.
- **`src/shared/Types.luau`** — the domain models. `RoundState`, `ClientRoundSnapshot`, `PlayerProfile`,
  `ActiveTask`. A new type that is an existing type plus one field is usually a field.
- **`src/shared/Enums.luau`** — the string constants. Never write `"ACTIVE"` inline; the literal types are
  what make the analyzer catch a typo.
- **`src/shared/Remotes.luau`** — the entire network surface, in one auditable place. A new remote goes
  here, in the right direction list, or it hangs forever at runtime.
- **`src/server/Services/RoundService.luau`** — the reference service shape: `Init()`, `Start()`, a
  private `state` table, phase subscription. Follow it rather than inventing a second shape.

If something similar exists but does not quite fit, prefer extending it over cloning it — but say so,
since widening a shared helper affects its other callers.

## Questions to Pass Before Adding Code

**Does this need to exist?** Not "is it nice" — does removing it break something in `docs/MVP-SPEC.md`?
Speculative flexibility for a future that was never specified is the most common source of bulk, and in
this project it has a name: §3's OUT list is entirely made of things that felt obviously worth building.

**Is this the third time?** Two similar call sites do not justify an abstraction. Duplication is cheaper
than the wrong abstraction, and the right shape is usually only visible on the third use.

**Could this be a pure function?** This is the highest-leverage question in this repo. A decision written
as a pure function over plain tables — role weighting, task selection, XP curves, win conditions — can
live in `src/shared/pure/` and be **proven by a Lune test**. The same decision written inline in a
service touching `Players` and `Instance` can only ever be verified by a human pressing Play.

That is the difference between a plan step gated on `lune run tests/roles.test.luau` and one gated on a
`grep`. Prefer the first, always.

**Is this layer the right one?** Bulk often comes from code in the wrong place — validation done on the
client, phase logic done outside `RoundService`. Code in the correct layer is usually shorter because the
layer already provides half of it.

## Shapes That Bloat This Codebase

- **A number typed twice.** It belongs in `Config`, read from there. This is not style: at M12 you will
  be tuning balance constantly and a stray literal is a bug you find at 2am.
- **A second state machine.** `RoundService` owns the phase. A service that tracks "am I in a round" with
  its own boolean will disagree with it eventually, and the disagreement will be intermittent.
- **Client-side validation that the server repeats.** The server's copy is the only one that counts. The
  client's copy is a UX affordance at best and a false sense of safety at worst.
- **Defensive `nil` checks for values the type system already guarantees.** `--!strict` is on. If you
  need the check, the type is wrong.
- **A wrapper that only forwards.** If it adds no behaviour, delete it and call the thing.
- **A new service for one function.** Services carry a lifecycle, a bootstrap entry, and a place in the
  ordering. One function belongs on an existing service.
- **`any` to escape a type problem.** It usually means a type in `Types.luau` is missing a field. The one
  legitimate use in this repo so far is documented at its call site with the reason.
- **Comments restating the code.** Comment the *why*. The surrounding code is sparse; match it.

## What Lean Does Not Mean

Do not compress at the cost of clarity. Lean is about *quantity of concepts*, not character count:

- Keep meaningful names. `transformStartedAt`, not `t`.
- Keep guard clauses and early returns.
- Keep genuine error handling. Removing a real failure path is not simplification.
- Keep the server/client boundary. Collapsing a validation into the client makes a file shorter and the
  game exploitable.
- Keep the Lune tests. They are the only mechanically provable thing in the repo.

A clever one-liner that takes three reads is not lean. Fewer moving parts is lean.

## Before You Say You Are Done

Reread what you wrote and ask: what here could be deleted without breaking something the spec asks for?
Delete that. If a file you created is under ~20 lines and has one caller, ask whether it should just live
in the caller.
