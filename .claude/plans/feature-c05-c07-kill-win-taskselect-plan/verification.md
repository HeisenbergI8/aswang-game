# Verification — C05–C07

Run `2026-08-11T12-00-31-501Z-chunk` · plan hash `23e56d93d2af` · 2026-08-11

> **SUPERSEDED IN PART — read this first.** This file records the implementing session's own pass. A
> review round afterwards found four bugs, all since fixed. For the current state read, in this order:
>
> - `implementation-log.md` § "Post-plan work" — the four fixes, what each was, and one deferral
> - `artifacts/console-fixes-retest.txt` — the live re-test of each fix against its own reproduction
> - `artifacts/console-finding2-no-respawn.txt` — the before-state of the worst one
> - `verification-playtest.md` and `verification-fixes.md` — independent `playtester` passes
>
> **The reviewers themselves left nothing on disk** — CLAUDE.md has the auditors report in chat, scored
> /100, and write no files. So any count of how many ran, or what they scored, is unverifiable from this
> repository and is deliberately not asserted here. What IS checkable is above: the fixes are in the
> diff and the evidence is in `artifacts/`.
>
> The NOT VERIFIED list below is still accurate and is the part that matters most. The review **added**
> one item to it: the kill's range check and raycast both originate from a position the killer's client
> owns, so a teleport executor satisfies both of §4.3's geometric rules. That is spec §6.3's work,
> scheduled to C41, and it is NOT fixed.

**This was verified by the implementing session, not by an independent `playtester` agent.** That is a
weaker form of evidence and it is stated first rather than buried: the same reasoning that wrote the code
chose the probes. `exploit-auditor` has not yet run, and Phase 4 is 🔒.

## Static

| Gate | Result |
| --- | --- |
| `npm run verify` | green — analyze, selene, StyLua, all five repo checks, `check:debug` |
| `npm run verify:plan` | **20 passed, 0 failed, 0 unverifiable** · 19 discriminating checks, 1 file-exists |
| `lune run tests/*` | 10 suites: config 25 invariants, kill-validation 16 grid cells + 21 cases, player-body 8+3, win-conditions 14+22, task-selection 10,000 draws, plus the five that pre-date this plan |

The kill-validation suite was **mutation-tested** rather than trusted: `<=` → `<` at the range boundary
produced 1 failure, and turning the target allowlist into a denylist produced 3 — on the `LOBBY` and
`GHOST` rows, which is the C04 bug in its exact original shape.

## Live, in Roblox Studio

Artifacts: `artifacts/spectator-premise.md`, `artifacts/console-phase1-body-rule.txt`,
`artifacts/console-phase4-kill-refusals.txt`.

| Claim | Verdict | Evidence |
| --- | --- | --- |
| `Players.CharacterAutoLoads` is `true` in this place — the premise for Phase 1 | PASS | `spectator-premise.md` probe 1 |
| `CharacterAutoLoads = false` suppresses the auto-respawn; `LoadCharacterAsync` spawns at the SpawnLocation | PASS | `spectator-premise.md` probe 2 — both were unverified Roblox behaviour in this repo |
| `RoundService.Start` sets the flag; a player keeps a body across every phase transition | PASS | `console-phase1-body-rule.txt` — 2 rounds, 7 transitions, position constant at (3,4,-2) |
| The phase check runs first, and flips at both boundaries | PASS | shots 4-6 in ENDING/INTERMISSION → `WRONG_PHASE`; 1-3 and 7-14 in ACTIVE → `SELF` |
| `SELF` precedes the role and form checks | PASS | refused identically transformed and untransformed |
| Rate limit on `RequestKill`, Capacity 3 | PASS | 8-call burst → exactly 3 verdicts, then `[AntiCheat] Rate limit refused` |
| The verdict is never echoed to a client | PASS | every refusal is a server log line; no reply remote on any probe |
| C04's forced revert at `MaxTransformTime` | PASS | `[Client] revert witnessed (yours)` — the gap C04's own pass could not reach |
| A solo round is never won by attrition on tick one | PASS | three consecutive rounds ran their full 60s to sunrise |
| `PlayerKilled` direction (DOWN, server-fired, client-listened) | PASS, **by hand** | `check:remotes` could not confirm it — see the harness bug below |

## NOT VERIFIED — a human with a second client is required

None of the following is reachable by any agent: Studio's player count is a UI action, and the solo
forced-Aswang path gives a killer with nobody to kill.

- **A kill succeeding at all.** Every refusal is proven; the success path is not.
- **`NOT_TRANSFORMED`.** It sits after `SELF` in the check order, so reaching it needs a real second
  target. Unreachable solo as a matter of the check order, not of the implementation.
- **`NOT_ASWANG`, `TARGET_NOT_ALIVE`, `TARGET_IS_ASWANG`, `OUT_OF_RANGE`** — same reason. All are proven
  in Lune against the pure module; none is proven through the live remote.
- **The line-of-sight raycast.** `workspace:Raycast` and `Enum.RaycastFilterType.Exclude` are first uses
  in this repo and remain **unexercised**. If `Exclude` were wrong for this engine version every kill
  would be refused — loud rather than silent, but still unobserved.
- **The corpse** persisting `CorpseDuration` and fading over `CorpseFadeTime`.
- **The kill cooldown starting from the revert** rather than from the kill.
- **`PlayerKilled` reaching a second client**, and that client's view containing no hint of the killer.
- **`AlivePlayerCount` dropping** on another player's HUD.
- **C06's attrition win firing**, which needs enough real survivors to kill.
- **An actual mid-round joiner** becoming `SPECTATOR` and being denied a body. Phase 1 proves the
  mechanism; it does not prove the scenario.

The gate for all of these is **two clients in Studio, or the M5 six-human playtest**.

## A probe design error in this session, recorded rather than hidden

PROBE-1 and PROBE-2 were aimed at `me.UserId + 1`, a UserId no player has. `validateAndKill` returns at
its `target == nil` guard **before** `KillValidation` runs, so those probes established the nil-target
early return and nothing about `WRONG_PHASE` or `NOT_TRANSFORMED`. PROBE-1b re-ran the phase case
correctly. The `NOT_TRANSFORMED` claim was **not** re-run by proxy — it is on the NOT VERIFIED list above.

## Harness bug found during this run — open, not fixed

`check:remotes` cannot see a `Remotes.Get(...)` that sits within 40 characters of a preceding one,
because its trailing context group is consumed by `matchAll`. The **direction checks run off that same
loop**, so a DOWN event fired from the client is invisible whenever it follows a nearby `Remotes.Get`.
Measured in three cases, written up in `implementation-log.md`. One-character fix (`(?=(...))`) plus
both-direction self-tests; deliberately left for its own chunk.

## What none of this can tell you

Whether the kill feels good — whether the windup is long enough to be fair and short enough to be
tense, whether 8 studs is the right reach, whether a 45-second corpse is menace or clutter. That is M5
and M12, and the `playtest` skill covers it.
