# The C02–C04 plan directory — review

Read: the plan's findings table, `implementation-log.md`, and `verification.md`. This is where this
plan's Phase 1 comes from, and where its §5 verification ceiling was learned rather than guessed.

## Finding row 7 — the reason Phase 1 exists

`feature-c02-c04-anticheat-roles-transform-plan.md:3424`

```
| 7 | **Spectator BODY containment is not delivered.** C04's warning asks for no character / observer
camera; this plan delivers only the rule (a spectator cannot transform). Premise unverified — nothing
in `src/` prevents a spawn, but the place file could already handle it. **Must be resolved before
C05**, when an uncounted spectator also becomes unkillable | High | Deferred — verify in Studio first,
then a small chunk before C05 |
```

**IMPORTANT** — the status line names the order explicitly: *verify in Studio first, then a small
chunk*. Phase 1 follows it — Step 1.1 is the probe, Steps 1.2–1.4 are the chunk — rather than
collapsing them, and both branches of the probe have a stated outcome so the phase cannot stall on it.

**IMPORTANT** — "this plan delivers only the rule" is the trap for anyone reading
`src/shared/pure/TransformRules.luau:65-74`. That file's `NOT_ALIVE` comment reads exactly like a
finished containment. It is half of one.

## Finding row 10 — a required input to C05, now due

`feature-c02-c04-anticheat-roles-transform-plan.md:3433`

```
| 7 | `Humanoid.Died` does not revert a transformed Aswang. There is no way to die until C05 | Low |
Deferred — a required input to C05 |
```

**NOTE** — closed by plan Step 4.5. Worth noting the kill path does **not** go through `Humanoid.Died`
(§4.9 wants a fade, not a death animation), so this connection covers falling out of the world, a
Studio reset, and whatever C14's salt does — not the kill itself.

## `verification.md` — the ceiling, learned the expensive way

`verification.md:21-41`

```
**A 1-player SoloTesting round can never draw an Aswang, and this is deterministic, not unlucky.**
...
**Consequence: C04's visual transform ... could not be reached or verified behaviourally in this
session at all**, not with any amount of patience.
```

**IMPORTANT** — this is the precedent that shaped this plan's §5. Commit `3c70cfc`
(`Config.Debug.ForceAswangWhenSolo`) fixed the *first* half — a solo round now has a live Aswang, which
is what makes the six refusal probes reachable. It does **not** fix the second half: there is still no
victim, and there is no config flag that can create one. C05's success path is bounded by a Studio UI
action (`Test` → `Players` ≥ 2) that no agent can drive.

`verification.md:39-41`

```
I did not do this myself: it requires a Studio setting change outside any MCP tool available to me, and
changing it would mean stopping the session you started.
```

**IMPORTANT** — confirmed by an agent that tried. Planning a workaround here would be planning against
measured evidence. The plan's answer is to prove every refusal and to write the success path down as
NOT VERIFIED, with the two gates that could close it named.

`verification.md:76-82`

```
**Screenshot artifact files.** `screen_capture` returned images I viewed directly in the tool
transcript ... but this environment does not write them to any discoverable path on disk
```

**IMPORTANT** — `goal-check.mjs` requires `verification.md` to cite a file that exists in `artifacts/`.
Screenshots did not land on disk last time; **console text did**. The plan's playtest brief is
therefore built entirely on `execute_luau` output and server console lines, which are the artifacts
that demonstrably persist here.

## `implementation-log.md` — the phase-budget lesson

`verification.md:83-87`

```
**`implementation-log.md` covers Phase 1 only** (Config/Types/remote-surface audit), even though
Phases 2–7's code is clearly present and behaving correctly live
```

**IMPORTANT** — the previous run had **7 phases** and its log covered one. The loop caps at 8
iterations (`task-driver.mjs`, `DEFAULT_BUDGET.iterations = 8`) and drives roughly one phase each, so a
7-phase plan has no slack for a repair loop. This plan uses **6**, with the two largest concerns
(Phase 4's six steps) deliberately in one phase rather than split into two.

**NOTE** — the log's own format is worth copying: per step, what changed, why, and the Verify line with
its actual output (`implementation-log.md:30, 47, 60`). That is what makes an `auditor` able to trace a
step to a file and a result.

## What the log confirms about the C05 surface

`implementation-log.md:53-58` records `Config.AntiCheat` shipping with a budget for **all eight**
`EVENTS_UP` remotes, and `tests/anti-cheat-budgets.test.luau` pinning the correspondence in both
directions.

**NOTE** — so `RequestKill`'s budget is not merely present, it is *asserted* present. Phase 4 adds no
`Config` entry and needs no new assertion in that test.
