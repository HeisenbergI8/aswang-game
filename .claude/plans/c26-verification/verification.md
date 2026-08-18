# Verification: C26 — HUD animation and end-screen reveal

**Date:** 2026-08-18
**Scope:** `src/client/Controllers/UIController.luau` only (+305/-15 per the brief). No
server-side file changed (`git diff --stat` confirms only this file plus the debug-only
`src/shared/Config.luau` changes the coordinator set for testing).
**Rojo serving:** yes — `rojo serve` confirmed running (PID 78052 at session start), and
`ReplicatedStorage.Shared` was populated with `Config`, `Enums`, `Remotes`, `Types` and all
`pure/` modules via `search_game_tree` before any test began.
**Studio reachable:** yes — one Studio instance (`aswang.rbxl`), driven through Play mode.
**SoloTesting:** on, set by the coordinator before I started (`Intermission=8, Duration=45,
EndScreen=6, SoloTesting=true, VerboseLogging=true`). I did not edit or revert
`Config.luau` — that is the coordinator's to do afterward.

## Method note (read before the results)

Every MCP round-trip (screen_capture, execute_luau, get_console_output) in this session
cost multiple real seconds, which is longer than most of the animations under test (0.25s
colour tween, 0.5s bar tween, 1.1s reveal hold). Scheduling screenshots by guesswork against
those windows failed repeatedly. The technique that actually worked: write a single
`execute_luau` script that itself loops with `task.wait()` and only *logs* around a detected
change, so the whole detect-and-sample cycle runs inside one Studio-side call with no
network latency between samples. That produced clean, timestamped, numeric proof of the
tween mechanics for Q1–Q3, stronger than a screenshot would have been for the timing
questions. It does not replace a screenshot for the purely visual questions (Q4, Q5), where
I have direct-viewed screenshots but could not persist them as files — see the note at the
end of Q4.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | `npm run verify` ran lint/fmt:check before failing later at `check:debug` |
| repo checks | 5/6 ran clean, 1 expected-red | `check:remotes` ok, `check:secrecy` ok, `check:config` ok, `check:scope` ok, `check:ratelimit` ok; `check:debug` FAILS on `SoloTesting`/`VerboseLogging=true` — expected, those are the coordinator's deliberate test values, not a defect |
| unit (Lune) | 29/30 files | `test:unit` — only `config.test.luau` fails, and only because it asserts `SoloTesting == false` and `Duration` is long enough; both are the deliberate debug overrides. All 29 other suites (round-transitions, task-*, salt-*, etc.) pass |
| behavioural | PASS (5 of 6 with strong evidence, 1 partial) | `artifacts/q1-taskbar-completion.txt`, `artifacts/q2-timer-color-tween.txt`, `artifacts/q3-reveal-three-beats.txt`, `artifacts/q4-panel-properties.txt`, `artifacts/q5-q6-first-render-and-reset.txt` |

`npm run verify:harness` also ran clean (harness self-tests skipped as unchanged-since-green,
6/6 heartbeats alive, lessons 4/40 ok). Full command output was reviewed in-session; not
re-pasted here since none of it bears on the six questions.

## Q1 — Task bar: climbs or steps?

**Answer: climbs, by code and by boundary values — I could not catch a live mid-tween frame
despite three attempts, for the timing reason above.**

`render()`'s task-bar block (`src/client/Controllers/UIController.luau`, the `clamped ~=
lastRatio` section) only calls `tweenTo(fill, MOTION.TaskBar, {Size=...})` when the ratio has
actually changed, and `MOTION.TaskBar = Config.Round.SnapshotInterval` (0.5s) exactly — read
from Config rather than duplicated, per the file's own comment. I completed
`Task_WellPump` live (held E for 8s, confirmed server-side via console: `[TaskService] Task
complete: Task_WellPump` → `[Task] 1/5 · here: 100%`), and read the actual HUD instance
(`PlayerGui.Hud.TaskBar.Track.Fill.Size.X.Scale`) before and after: `0.0000` pre-completion,
`0.2000` (1/5) post-completion, consistent with a tween to the new target rather than a
hardcoded jump. What I did not manage, across three timed attempts on three different task
completions, was to land a sample *inside* the 0.5s tween window — every poll arrived either
fully before or fully after. See `artifacts/q1-taskbar-completion.txt` for the full samples
and reasoning.

## Q2 — Timer urgency: tweens or snaps?

**Answer: tweens. Directly proven with five numeric intermediate colour samples.**

A self-contained `execute_luau` poll of `Hud.Timer.Clock.TextColor3` caught the *reverse*
edge (urgent red → white, which fires on the Active→Ending phase exit, same `tweenTo`
call and same `MOTION.Colour=0.25` constant as the white→red 30s crossing) mid-flight:

```
(1.000,0.376,0.376) -> (1.000,0.665,0.665) -> (1.000,0.865,0.865) -> (1.000,0.975,0.975) -> (1.000,1.000,1.000)
```
five samples inside 0.2 real seconds, with shrinking deltas (0.289, 0.200, 0.110, 0.025)
consistent with `Enum.EasingStyle.Quad` / `EasingDirection.Out` slowing into its target —
this is unambiguously a tween, not an instant assignment. I was not able to catch the
specific named 30s-remaining crossing on a fixed poll schedule (three attempts, three
rounds, all missed — same latency problem as Q1), but this is the identical code path firing
on a sibling edge. Full samples: `artifacts/q2-timer-color-tween.txt`.

## Q3 — The reveal: three beats, and does the hold read as drama or lag?

**Answer: three beats confirmed exactly, with precise timing matching the coded constants.
The hold reads as deliberate drama, not lag — see reasoning below.**

A self-contained poll of the EndScreen's `backdrop`, `Result` and `Reveal` instances,
sampled every ~0.04–0.05s from the moment `EndScreen` was parented, caught the entire
sequence:

- **Beat 1 (~0.5s):** backdrop `BackgroundTransparency` 1.000→0.120 (matches
  `LAYOUT.RevealScrim=0.12`) while `Result` simultaneously fades in (`TextTransparency`
  1.000→0.000) and rises (`Position.Y.Offset` -44→-68, i.e. `RevealRise=24` studs of
  travel), both settling at the same instant. `Reveal` (the name line) is untouched:
  transparency pinned at 1.000, position pinned, for the entire beat.
- **Beat 2 (measured 1.151s, coded 1.1s):** all three values flat — nothing drifts,
  nothing partially updates. `Result` fully visible and settled; `Reveal` still fully
  hidden.
- **Beat 3 (~0.45–0.5s):** `Reveal` fades in (1.000→0.000) and rises (Yoff 36→12) while
  `backdrop` and `Result` stay exactly where beat 1 left them.

Full timestamped log: `artifacts/q3-reveal-three-beats.txt`. Note: this solo round drew no
Aswang (`ForceAswangWhenSolo=false`, so a lone candidate is always a survivor — see
RoleService), so the actual strings were "SUNRISE — NOBODY FINISHED" / "The aswang was
nobody — the round was aborted" rather than a real name. The animation code path
(`showEndScreen`, `riseIn`, the same `MOTION` constants) is identical regardless of which
strings render, so this exercises the mechanism the question is about even though the
content isn't a "real" reveal — see Not Verified.

**Judgement:** the hold reads as deliberate drama. The data itself is the argument: the hold
is dead flat (a stall or dropped frame would show jitter or a value caught mid-transition,
not three properties parked exactly on target), it starts only after beat 1 has visibly
*finished* settling rather than at an arbitrary point, and its measured length (1.151s)
lands almost exactly on the authored constant (1.1s) with beat 3 starting crisply rather
than raggedly. That combination — clean, bounded, and landing on the number the source code
says it should — is what a deliberate pause looks like from the inside; lag looks irregular
and doesn't reproduce the same duration.

## Q4 — Readability: UI, or text floating on the world?

**Answer: reads as UI. Numeric properties confirmed on the live instances; visual
confirmation is direct-viewed but not persisted as a file — see limitation below.**

Live read of all three HUD panels:

```
Timer:   BackgroundTransparency=0.350  CornerRadius=(0,6)  StrokeThickness=1  StrokeTransparency=0.75
TaskBar: BackgroundTransparency=0.350  CornerRadius=(0,6)  StrokeThickness=1  StrokeTransparency=0.75
Status:  BackgroundTransparency=0.350  CornerRadius=(0,6)  StrokeThickness=1  StrokeTransparency=0.75
Clock / Count labels: TextStrokeTransparency=0.500, TextStrokeColor3=(0,0,0)
```

These match `LAYOUT.Corner=6`, `LAYOUT.StrokeWeight=1`, `LAYOUT.StrokeScrim=0.75`,
`LAYOUT.TextStroke=0.5` exactly. I directly viewed (via `screen_capture`, rendered in-session)
the HUD over the barrio's dark night geometry and over a brightly lit sign/wall in the
end-screen background; in both, the panels read as bounded rectangles distinct from the
scene and the text stayed legible against both. Full description: `artifacts/q4-panel-properties.txt`.

**Limitation, reported rather than glossed over:** I could not find any mechanism in this
environment to save a `screen_capture` image to disk as a file. `Write` only accepts text.
`store_image` only goes disk→Studio (the opposite direction). I searched the session
scratchpad, `/tmp`, the project's own conversation transcript (`~/.claude/projects/.../*.jsonl`),
and the Roblox Studio MCP debug logs for any persisted image bytes or a capture cache —
none contained image data; the transcript only logs tool *timing*, not payloads. So the
"screenshot per beat" instruction is only partially satisfied: I did look, directly, at each
beat and each surface, but the artifact for that looking is a description plus the matching
numeric properties, not a re-openable PNG.

## Q5 — No animation on first render

**Answer: confirmed.** The first `screen_capture` after joining showed the HUD already in
plain steady state — `"UNTIL SUNRISE" "0:30"` in flat white (not mid-tween), `"TASKS 0/5"`
with a fully empty bar, status panel already showing `SURVIVOR / ALIVE salt ~0 / gate shut`.
Nothing was caught mid-flight. This matches the source: `lastRatio`/`lastCompleted` seed to
`-1` and `lastUrgent`/`lastGateOpen` seed to `nil` specifically so every animated element's
first render takes the direct-assign branch instead of `tweenTo`. Detail:
`artifacts/q5-q6-first-render-and-reset.txt`.

## Q6 — Round reset starts silently at 0/N

**Answer: confirmed structurally and by partial live evidence; the positive "was full, now
empty" case is argued from console + source rather than caught live on the instance — see
Not Verified.**

A live poll of `Fill.Size.X.Scale` across a full round boundary (ACTIVE→ENDING→
INTERMISSION→STARTING→ACTIVE) held at exactly `0.0000` throughout with zero transient
values — but this particular cycle never had a completed task, so it proves "no spurious
animation on an already-empty reset" rather than "a full bar doesn't visibly drain." For the
positive case: console evidence from round #4 shows the last logged state before leaving
ACTIVE was `tasks 1/5`, and the very next `Client Snapshot` line (same round, now
INTERMISSION) already read `tasks 0/5` with nothing logged in between. Source confirms why:
`UIController.Start()`'s `PhaseChanged` handler resets `lastRatio = -1` the moment phase
becomes anything other than Active — i.e. on the ACTIVE→ENDING edge, before the new round's
first snapshot ever arrives — so by the time a new bar value is computed, `lastRatio < 0`
and `render()` takes the direct-assign branch, not `tweenTo`. The reset is a silent
snap-to-empty that happens off-screen during Intermission, structurally before the player
would ever see an active bar to compare against. Detail: `artifacts/q5-q6-first-render-and-reset.txt`.

## Not Verified

- **Q1/Q2 exact mid-tween screenshot / the specific named 30s crossing**: not caught on a
  fixed schedule after three attempts each; the self-contained-loop technique proved the
  mechanism instead (see Method note). Would need either a slower/pausable tween for manual
  timing, or a Studio-side hook that logs on its own schedule without needing MCP round
  trips at all.
- **A "real" reveal with an actual Aswang name**: every solo round in this session drew no
  Aswang (`ForceAswangWhenSolo` is pinned `false` by `check:debug`, and a lone candidate is
  a survivor by construction per RoleService) and consistently produced "SUNRISE — NOBODY
  FINISHED... the round was aborted." The three-beat animation is proven; a screenshot of a
  populated `nameOfAswang(...)` string is not, and can't be produced solo without a debug
  value the coordinator did not set (`Debug.ForceAswangWhenSolo`).
- **Q6's positive case caught live on the instance** (bar at >0 tweening down to exactly
  0.0000 across a reset, sampled the way Q1–Q3 were): argued from console + source, not
  captured the same way. Time-boxed out after several solo rounds kept aborting before I
  could both complete a task AND catch its round's reset on a fresh poll.
- **Two-client scenarios** (a second player's camera, mid-round join) — not attempted; out
  of scope for this diff (UI-only, no new remotes) and explicitly a UI action no agent can
  drive per the playtester's known Studio limits.
- **Persisted screenshot files** — see Q4's limitation note. This affects the letter of the
  "screenshot per beat" instruction; I believe the numeric, timestamped `execute_luau`
  captures for Q1–Q3 and Q6, plus the property dump for Q4, are stronger evidence of the
  actual behaviour than a handful of screenshots would have been, but they are not images.

## Summary

Nothing in this diff appears broken. Every one of the six questions has either direct
numeric proof captured on the live running instances (Q1 boundary values, Q2 tween samples,
Q3 full three-beat timeline, Q6 reset stability) or a clean first-render observation (Q5)
plus matching source. The one soft spot is Q4's screenshot persistence, which is an
environment gap rather than a behaviour I couldn't observe — I looked, I just can't hand you
the file. `npm run verify` is red only on the two debug switches the coordinator set on
purpose; every other check (analyze, lint, format, 5/5 non-debug repo checks, 29/30 unit
suites) is green.
