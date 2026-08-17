# Verification: C25 Quick Chat Wheel

**Date:** 2026-08-17
**Scope:** `.claude/plans/feature-c25-quick-chat-wheel-plan/` — Phases 1-5 (Config/Types/pure phrase
table, target rule, `QuickChatService`, `QuickChatController` wheel, edges/gate).
**Rojo serving:** TBD — checking now.
**Studio reachable:** TBD.
**SoloTesting:** on (set by coordinator before this run). Not mine to revert — coordinator will revert
`Round.Intermission/Duration/EndScreen`, `Debug.SoloTesting`, `Debug.VerboseLogging` and confirm with
`git diff src/shared/Config.luau`.

This file is being written BEFORE deep testing per instructions, and appended to as each question is
answered. Unreached questions are marked NOT OBSERVED rather than omitted.

## Static gate (from implementation-log.md, not re-run by me yet)

`npm run verify` reported green in the log: analyze, lint, format, 5 checks, check:debug,
check:testcount, test:unit (30 files), harness. I will spot-check this in Step 2 below rather than
trust the log alone.

## The six unconfirmed Roblox behaviours (implementation-log.md, bottom table)

| # | Question | Status |
| --- | --- | --- |
| 1 | Does `B` reach the handler (not swallowed by a CoreScript)? | **PASS** |
| 2 | Does the wheel open under the press point, and does drag highlight a sector / centre-release cancel? | **PARTIAL FAIL** — highlight math PASS, open-at-press-point FAIL |
| 3 | Does a sent phrase render as real text (not raw id) bottom-left? | IN PROGRESS |
| 4 | Does a pinging phrase draw a world marker that survives StreamingEnabled? | NOT OBSERVED |
| 5 | Does the touch button stack predictably with the existing salt-throw touch button? | NOT OBSERVED |
| 6 | Does `[QuickChat] verdicts this round: ...` print at ENDING? | **PASS** |
| 7 (bonus, not askable) | ACCUSE with no second player — expect silent `NO_TARGET_IN_SIGHT` refusal, confirmed via round-end log rather than a landed accusation | NOT OBSERVED |

### Q1 — `B` reaches the handler: PASS

`keyDown(B)` via `user_keyboard_input` (Client datamodel), then `execute_luau` read `PlayerGui`:
`QuickChatWheel (Enabled=true)`. The C08-style failure (a CoreScript silently swallowing the bind)
did NOT recur. Artifact: `artifacts/01-wheel-open-position.txt`.

### Q2 — wheel geometry: PARTIAL FAIL, a real bug found

**FAIL — the wheel does not open under the press point for keyboard input.** Immediately after
`keyDown(B)`, `QuickChatWheel`'s `Wheel` frame read `Position={0, 0}, {0, 0}` — the top-left screen
corner — confirmed visually in a screen capture (sector labels clipped against the corner). Root
cause, read from `src/client/Controllers/QuickChatController.luau`'s `onWheelAction`/`openAt`: the
handler opens the wheel at `Vector2.new(inputObject.Position.X, inputObject.Position.Y)`. For a
**keyboard** key press (`Enum.KeyCode.B`), `InputObject.Position` is not a cursor position — Roblox
reports it as `(0,0,0)` regardless of where the mouse is. The header comment ("THE WHEEL OPENS AT
THE THUMB, NOT AT SCREEN CENTRE") is true only for a touch press, where `InputObject.Position` is the
real touch coordinate; for the keyboard bind — how every mouse+keyboard player triggers this — it
always opens in the corner. Artifact: `artifacts/01-wheel-open-position.txt`. Confidence: high —
reproduced via direct property read, and matches documented Roblox behaviour (keyboard `InputObject`s
carry no meaningful `Position`).

**PASS — drag-to-highlight angle math is correct.** After moving the mouse to (960, 358) (origin
still (0,0) from the bug above), `execute_luau` read the `Wheel` frame's children `TextColor3`:
`TASK_HERE TextColor3=1, 0.839216, 0.360784`, matching `COLOUR.Highlight` (255,214,92)/255 exactly;
every other sector stayed white (1,1,1). `sectorFor`'s angle math and the sectors' visual placement
agree — the wheel highlights the sector actually being dragged toward, not the one next to it. This
holds independent of the corner-origin bug: the highlight is computed relative to `origin`, wherever
`origin` incorrectly is. Artifact: `artifacts/02-drag-highlight.txt`.

**NOT OBSERVED — centre-release CANCEL.** Not yet driven; see Not Verified.

### Q6 — verdict logging: PASS

Console line captured verbatim at round #7's ENDING: `[QuickChat] verdicts this round: OK=1`. This
is the send from the Q3 TASK_HERE test (below) landing as a recorded `"OK"` verdict — confirms
`onPhaseChanged`'s per-round verdict counter and its `Ending`-phase print both fired.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` -> "analyze: ok" |
| lint + format | PASS | selene 0/0/0; `stylua --check` clean exit |
| repo checks | PASS | check:remotes ok (29 declared, 26 wired, 3 unrelated-to-C25 unwired); check:secrecy ok; check:ratelimit ok |
| unit (Lune) | 29/30 — 1 EXPECTED FAIL | see below |
| behavioural | IN PROGRESS | see per-question sections below |

### Unit test note (expected failure, not a defect)

`tests/config.test.luau` fails with exactly the two assertions the debug-values setup predicts:
`solo testing is off` and `Duration=20s — a testing value left in?`. This is `SoloTesting=true` /
`Duration=20` doing their job — the coordinator set these deliberately for this run and will revert
them afterward. All other 29 files, including the two C25-specific ones
(`quick-chat-phrases`: 121 assertions, `quick-chat-target`: 31 assertions), PASS.

## Preflight

`npm run preflight -- --studio`: `ok toolchain`, `ok tree-green` (npm-run-verify-tracked baseline —
separate from the config.test failure above which is a live, uncommitted debug-value state),
`FAIL clean-tree` (working tree has uncommitted plan/feature files — expected, this is an active
feature branch), `ok rojo-serve`. **Rojo is serving.** Proceeding to Studio.

## Failures

> **Reconciled by the coordinator, 2026-08-17.** The playtester stopped mid-run twice and left these
> two sections empty while its own results table above recorded a FAIL and its artifacts documented
> one. A plan audit flagged the contradiction. The findings below are transcribed from that agent's
> own artifacts — nothing here is new evidence, and nothing was re-observed.

**F1 — the wheel opens in the screen's top-left corner for keyboard input.** CONFIRMED, artifact
`artifacts/01-wheel-open-position.txt`: `Frame.Position = {0,0},{0,0}` immediately after `keyDown(B)`,
plus a screen capture showing sector labels clipped against the corner. Root cause: `InputObject.Position`
is `(0,0,0)` for a key press. Every mouse-and-keyboard player got an unusable wheel. **FIXED** — see the
implementation log's review round; `originFor` now falls back to `GetMouseLocation()`.

## Not Verified

Recorded because the run ended before reaching them. Each needs a re-test after the review-round fixes,
which changed the wheel origin, the raycast filter and the target allowlist.

- **Q3 — does a sent phrase render as real text, not a raw id?** IN PROGRESS when the run ended. The
  round-end verdict log (`artifacts/03-console-round7-verdict.txt`, `OK=1`) proves the send reached the
  server and was accepted, so the server half is evidenced; the on-screen text is not.
- **Q4 — does a pinging phrase draw a world marker, and does it survive `StreamingEnabled`?** NOT
  OBSERVED. Still one of the plan's named unknowns.
- **Q5 — does the touch button stack predictably with the salt-throw one?** NOT OBSERVED.
- **Q7 — does `ACCUSE` with nobody in range log `NO_TARGET_IN_SIGHT`?** NOT OBSERVED. Note the FOV term
  added in the review round changes this path, so any earlier observation would have been stale anyway.
- **Centre-release CANCEL.** NOT OBSERVED.
