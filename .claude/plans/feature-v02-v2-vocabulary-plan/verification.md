# V02 — verification

## Read this first: who wrote this file, and what that costs

**This was written by the implementing session, not by the `playtester` agent, and there is no runtime
evidence in it.** Normally `verification.md` is the playtester's artifact and its value comes from being
produced by something that did not write the code. That is not what happened here, and the reason is
structural rather than a shortcut:

**V02 adds no behaviour.** It declares four literal unions, four frozen enum tables and a block of
Config numbers. Nothing is wired: no service reads the new enums, no remote carries them, and
`ClientRoundSnapshot.YourCarriedItem` has **no producer** — `buildSnapshot` does not set it, deliberately.
There is no round to drive, no state to observe and no screenshot that would show anything but a HUD
identical to V01's. A playtester launched against this chunk would have returned a screenshot of an
unchanged game, which is worse than no artifact: it would look like evidence.

**So treat this as a static gate record.** It proves the vocabulary exists, typechecks, and does not
break the 28 suites that were passing before. It proves nothing about whether the words are the *right*
words — that is answered when V03–V11 build on them, and finally at V16 with real players.

## Evidence

`artifacts/verify-output.txt` — full captured output of both gates, 84 lines.

| Gate | Result | Line in artifact |
| --- | --- | --- |
| `analyze` | ok | 9 |
| `remotes` | ok (22 declared, 22 wired) | 14 |
| `secrecy` | ok (the Aswang stays server-side) | 15 |
| `config` | ok (balance stays data-driven) | 16 |
| `scope` | ok (19 out-of-scope shapes watched) | 17 |
| `ratelimit` | ok (every OnServerEvent consults AntiCheat) | 18 |
| `config.test` | **86 balance invariants** (was 82) | 27 |
| `test:unit` | 28 file(s) ok | 52 |
| `verify:plan` | **12 passed, 0 failed, 0 unverifiable** | 83 |

`lint` reported 0 warnings and 0 parse errors; `fmt:check` passed as part of `verify`.

## The two numbers worth checking by hand

**1. `86`, not 82.** Step 3.6 added exactly four assertions pinning `Config.Salt`'s aliases to their
canonical `Config.Items` source. That count is a *measurement* rather than a literal — see the comment
at the foot of `tests/config.test.luau`, which explains that a hardcoded total once hid seven dropped
checks. Reaching exactly 86 is what proves all four `check(...)` calls registered rather than being
silently malformed.

**2. `337s/round`, printed by `xp-curve`.** Independently confirms Step 3.1's `Duration` 420 -> 300:
25 (Intermission) + 300 + 12 (EndScreen) = 337, matching the plan's predicted table exactly.

## What a green `test:unit` means here, since the build plan said otherwise

`docs/BUILD-PLAN.md:191` predicted this suite would FAIL until V11. **That prediction was measured wrong
before V02 began** — the suite passed at 82 invariants, exit 0, on a clean tree. It was describing a
hard rename of `Config.Salt.*` that was not taken (that branch reds `analyze`, which V02's Done line
forbids). The line has been corrected in this chunk. **A red `test:unit` in V02 would be a real failure.**

## What is NOT verified, and who verifies it

| Claim | Status |
| --- | --- |
| The vocabulary typechecks and nothing regressed | **verified**, above |
| All 14 enum values carry a `:: Types.X` cast | **read by eye**, and re-checked by the `auditor` — an uncast value is NOT an analyzer error, so no gate covers this |
| The four aliases stay pinned to canonical | **verified** by the four new assertions |
| `YourCarriedItem` never leaks | **argued, not proven.** `check:secrecy` passes trivially — the field contains no role token. The real defence is that the snapshot is per-player via `FireClient` and the field is `nil` for the Aswang and an empty-handed survivor alike. **Re-audit at V08**, when a producer first exists |
| §6.5 invariant 1 holds | **holds with ZERO margin** (25x3 = 75 >= 75). Guarded only by a comment until V11 pins it |
| The words are the right words | **not verified and not verifiable here.** V03–V11 are the test; V16 is the verdict |
