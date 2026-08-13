# Verification: C09–C12 — Timing, Fetch, Two-person, the escape gate, and the fake task list

**Date:** 2026-08-12
**Scope:** the whole uncommitted diff for this plan (`git diff --stat` — 13 modified files, ~15 new
files: `TimingWindow`, `FetchCarry`, `TaskParticipants`, `GateEscape`, `TaskListView` pure modules,
`GateService`, `TaskController`, and their tests)
**Rojo serving:** yes — confirmed via `npm run preflight -- --studio` (`rojo-serve: ok`) before any
Studio observation
**Studio reachable:** yes — Place3, one Studio instance, confirmed via `get_studio_state` before testing
**SoloTesting:** on (coordinator-set, coordinator will revert) — `ForceAswangWhenSolo` off, so the solo
player is a SURVIVOR throughout this report

**This report was interrupted twice mid-session by the coordinator to force it onto disk before more
testing.** What follows is everything gathered up to that point, written immediately rather than after
finishing the remaining priorities. The unfinished items are named explicitly in **Not Verified** below
— I did not continue testing after writing this, per the coordinator's explicit instruction.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `artifacts/static-verify.md` |
| lint + format | PASS | `artifacts/static-verify.md` (no FAIL lines between analyze and remotes) |
| check:remotes / secrecy / config / scope / ratelimit | PASS (all 5) | `artifacts/static-verify.md` |
| check:debug | FAIL (expected — coordinator's live debug values, not a defect) | `artifacts/static-verify.md` |
| unit (Lune) | 19/20 files (1 expected failure: `config.test.luau`, same debug-value cause) | `artifacts/static-verify.md` |
| harness self-tests | 26/26 suites PASS | `artifacts/static-verify.md` |
| **Priority 1 — `R` reaches the server** | **PASS** | `artifacts/timing-r-press-and-spam.md` |
| **Priority 1 — spam vs. deliberate** | PASS in outcome, with an important caveat — see below | `artifacts/timing-r-press-and-spam.md` |
| **Priority 2 — Fetch pickup + carry + deliver** | **PASS** | `artifacts/fetch-end-to-end.md` |
| **Priority 2 — die mid-carry, item left behind** | **NOT VERIFIED** | see Not Verified |
| **Priority 3 — 4 HOLD tasks completed solo** | **PASS** | `artifacts/four-of-five-hold-tasks.md` |
| **Priority 3 — gate opens, survivor escapes** | **NOT VERIFIED — never observed, in any session** | see Not Verified |
| **Priority 4 — two-person alone = no progress** | **PASS** | `artifacts/two-person-solo.md` |
| **Priority 4 — two survivors opens it** | **NOT VERIFIABLE by this agent** (needs a second client) | see Not Verified |

## The highest-value fact first: `R` is reachable

Pressing `R` at a drawn `TaskPoint_04` produces `[Task] bar TaskPoint_04 · 0/3 hits` immediately, and
repeated deliberate presses show hits climbing to 1/3 and resetting to 0/3 on a miss — proof the server
is deciding per press, not echoing a static value. **C09 is not a repeat of C08's `E`-swallowed-by-
ProximityPrompt bug.** Full console excerpt: `artifacts/timing-r-press-and-spam.md`.

## The exploit test, and the coordinator's audit finding

I ran two independent 5-call `RequestTimingStop` bursts (`FireServer` looped with ~0 client-side elapsed
time between calls). Both times, `AntiCheatService`'s budget (`Capacity=5, RefillPerSecond=1`) let
exactly 5 through and rate-limited the rest (one `warn` line only — `AntiCheatService` throttles its own
logging per remote per player, confirmed by reading the source, not a gap in my evidence). **Both bursts
came back as all-misses**, so net progress from spamming was zero in both trials.

**The coordinator reports an exploit audit found `RequestTimingStop` has no spacing rule: 5 stops in one
frame are evaluated against a bar that has not moved, so they share a verdict, and a burst landing in the
zone completes 3 hits in one shot.** My two bursts corroborate the *mechanism* exactly — 5 near-
simultaneous calls, one frozen bar position, one shared verdict (miss, both times) rather than 5
independent rolls. **I did not personally observe a burst landing in the zone and completing the task.**
I want to be precise about that distinction: my evidence shows spamming gained nothing in the two trials
I ran, and it separately shows *why* the audit's finding is real (the correlated-verdict mechanism is
directly visible in the data) — but I have not witnessed the positive case (an instant free completion)
myself. Treat the audit's finding as the authoritative statement on whether this is exploitable; treat my
data as confirming the mechanism without demonstrating the exploit's success case.

## Fetch — pickup, 125-stud carry, and delivery all observed

Standing near a `FetchSource` picks the item up automatically (no button) within one ~250ms tick; it
tracks a 125-stud teleport; holding `E` at the destination delivers it over `FetchDeliverTime`-scale
progress and prints `[TaskService] Task complete: TaskPoint_03`. Full excerpt:
`artifacts/fetch-end-to-end.md`. **Dying mid-carry was not reached — see Not Verified.**

## Four of five tasks, solo, in one round — the fifth (TIMING) ran out of round

`TaskPoint_06`, `07`, `08`, `12` (all HOLD) completed cleanly back-to-back in one round, each showing
identical clean progression to 100% and a `[TaskService] Task complete:` line, with `ClientRoundSnapshot`
correctly reporting `gate shut` at every count below 5. The fifth task in that draw was `TaskPoint_04`
(TIMING); I could not land 3 hits without a rendered bar (C18 is out of scope for this plan) before the
round's `Duration=150s` elapsed, so **the round ended at 4/5 and the gate never opened**. Full excerpt:
`artifacts/four-of-five-hold-tasks.md`.

**This means the single most-wanted observation in the brief — the gate opening, `[GateService] <userid>
reached the gate`, and `SURVIVORS_ESCAPED` — was not reached in this session.** `gate-rig.md` (the prior
session's artifact) already established the negative case (gate correctly stays shut at 0/5); this
session adds a second negative case at 4/5, which is consistent but still not the positive case.

## Two-person, alone: confirmed frozen at 0%

Holding `E` continuously at `TaskPoint_05` (TWO_PERSON) for 5s produced `here: 0%` for the entire hold —
never advanced. Matches `TaskService.luau:981-990`'s `weight = 0` when `TaskParticipants.meets(...)`
fails solo. Full excerpt: `artifacts/two-person-solo.md`.

## Not Verified

- **The gate opening, `[GateService] <userid> reached the gate`, and `SURVIVORS_ESCAPED`.** Reached 4/5
  in one round (TIMING task not landed before the round timer elapsed) and 0/5 in earlier rounds. A round
  whose 5-of-12 draw avoids both TIMING and TWO_PERSON pads (~58% chance per draw, and independent of
  that, enough real wall-clock time to clear it before `Duration=150s` elapses) would let this be
  attempted again. This is the single largest gap in this report and the one item I would prioritize if
  continuing.
- **Dying mid-carry and the item being left behind.** Fetch was proven pickup-to-delivery, but I did not
  reach the death case (Escape → Reset while carrying, then confirming the item stays put rather than
  vanishing or following the corpse).
- **TIMING task actually completing (3/3 hits reached).** `R` is reachable and hits genuinely climb/reset
  (proven), but no session — this one or the prior one — has completed a TIMING task. Without a rendered
  bar (C18), landing 3 deliberate hits requires either luck or a phase-prediction approach I did not
  finish building before being redirected to write this report.
- **Two survivors opening a TWO_PERSON task.** Confirmed solo = no progress; the positive case is
  multi-client by definition and no Studio MCP tool can drive a second client. Needs a human on
  Test → Clients and Servers → 2 players.
- 🔒 **An Aswang standing in an open gate and the round NOT ending.** Needs `ForceAswangWhenSolo` on,
  which the coordinator asked me not to set, and also needs 5/5 first, which was not reached.
- **The exploit's positive case** (a spam burst actually completing a task in one frame). See above —
  mechanism corroborated, success case not personally witnessed.

## Nothing surprised me structurally beyond what's above

The one thing worth flagging even though it wasn't asked: **real wall-clock time during this session
consistently outpaced my expectations** — several rounds (`Duration=150s`) elapsed and reset while I was
still reading/inspecting between actions, costing at least two full round-cycles' worth of evidence
before I adjusted to teleport-and-act without intermediate inspection calls. That is a testing-process
observation about how much real time a multi-tool-call agent session burns per Studio round, not a defect
in the game.
