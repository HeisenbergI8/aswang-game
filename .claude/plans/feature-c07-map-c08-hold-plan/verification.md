# Verification: C08 — the Hold task

**Date:** 2026-08-12
**Scope:** C08's Done condition (a hold completes in `HoldTime`; walking away freezes rather than resets;
spamming `RequestTaskProgress` gains nothing), against the working tree for the
`feature-c07-map-c08-hold-plan`. Out of scope by the coordinator's brief: C09–C12 (Timing, Fetch,
Two-person, the fake list — none built), the escape gate, survivors' win.
**Rojo serving:** yes — `ReplicatedStorage.Shared` populated, confirmed via `preflight -- --studio`.
**Studio reachable:** yes — single Studio instance `Place3`, `Edit`/`Client`/`Server` datamodels all used.
**SoloTesting:** on, set by the coordinator before I started (`Round.Intermission=8`, `Duration=90`,
`EndScreen=6`, `Debug.SoloTesting`/`VerboseLogging=true`). I did not change these and did not revert them
— the coordinator said they would. `git diff src/shared/Config.luau` at the end of this report shows only
those five lines differing from HEAD.

## Summary

**A real, critical bug was found, reported mid-verification, fixed by the coordinator, and the fix was
then confirmed live.** Before the fix, a normal player pressing `E` while standing on an active task pad
produced **no effect whatsoever** — no client feedback, no server log, no error — because the
`ProximityPrompt`'s default `KeyboardKeyCode = E` silently consumed the keypress before
`ContextActionService`'s `TaskAction` bind (also on `E`) ever saw it. This is exactly the risk
`artifacts/proximity-prompt-probe.md` flagged as unresolved at Step 6.1, and it was real. After the fix
(`attachPrompt` now sets `prompt.KeyboardKeyCode = Enum.KeyCode.None`), all three parts of the Done
condition were re-verified from a fresh Play session and all three hold.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `0 errors, 0 warnings, 0 parse errors` |
| lint (selene) | PASS | part of `npm run verify` chain, no findings before the debug-value halt |
| remotes / secrecy / config / scope / ratelimit | PASS | `remotes: ok`, `secrecy: ok`, `config: ok`, `scope: ok`, `ratelimit: ok` |
| check:debug | FAIL (expected) | `Debug.SoloTesting = true`, `Debug.VerboseLogging = true` — intentional test config, not a defect. See below |
| unit (Lune) | 12/13 files | only `config.test.luau` fails, and only on the two debug-value assertions (see below). `task-pool` (14 assertions/8 pools) and `task-progress` (20 assertions, incl. non-scaling property) both PASS |
| behavioural: hold completes in ~8s | PASS | `artifacts/hold-completion-and-spam-immunity.md` |
| behavioural: spam gains nothing (🔒 mandatory) | PASS | `artifacts/hold-completion-and-spam-immunity.md` |
| behavioural: walk-away freezes, resumes | PASS | `artifacts/walkaway-freeze-and-resume.md` |
| behavioural: keyboard-swallow bug found + fix confirmed | CRITICAL BUG, then FIXED and CONFIRMED | `artifacts/keyboard-swallow-bug-and-fix.md` |

`npm run verify`'s halt at `check:debug` is the harness working as designed — `guard-commit.mjs` and
`tests/config.test.luau` exist specifically so these five testing values can never reach a commit. It is
not a code defect and I did not touch `Config.luau`. The exact failing lines:

```
FAIL  src/shared/Config.luau — Debug.SoloTesting = true, must be false
FAIL  src/shared/Config.luau — Debug.VerboseLogging = true, must be false
```

## The critical finding, in brief (full detail in `artifacts/keyboard-swallow-bug-and-fix.md`)

Before the fix: standing 3.5 studs from an active `TaskPrompt`, `E` held continuously (confirmed down at
the engine level via `UserInputService:IsKeyDown`) for a full 90-second `ACTIVE` phase produced **zero**
console output of any kind — not even a refusal. The identical mechanism fired from off any task point
produced a continuous, correct stream of `NO_TASK_IN_RANGE` refusals, proving the input pipeline worked
everywhere except on a pad. Root cause confirmed by setting one live prompt's `KeyboardKeyCode` to
`Unknown` at runtime (a diagnostic instance-property change, not a source edit) — the hold immediately
started working. This matched Step 6.1's own named risk exactly.

The coordinator applied the real fix in `src/server/Services/TaskService.luau`'s `attachPrompt`
(`KeyboardKeyCode = Enum.KeyCode.None`, not `Unknown`, because `Unknown` fails `npm run analyze`). I
restarted Play, confirmed the property on a freshly-created prompt without any runtime override, and
re-ran all three Done-condition checks from scratch — all pass. One minor, non-blocking side effect is
recorded in the artifact: Roblox's own `ProximityPrompt` CoreScript now logs an "unsupported keycode for
rendering UI" warning on every prompt, meaning the prompt's own "Hold [E]" hint text likely does not
render (worth a look at M7, not a C08 blocker — `HoldDuration=0` means the prompt's input handling was
never load-bearing to begin with).

## Part 1 — 🔒 the mandatory one: spam gains nothing

- **Off-pad:** 500 `RequestTaskProgress:FireServer()` calls fired from `(200,3,200)`. Only 12 reached
  `TaskService` before `AntiCheatService`'s token bucket (`Capacity=12`) started refusing the rest
  silently. All 12 that landed were refused `NO_TASK_IN_RANGE`. Zero progress, zero effect from the other
  488.
- **On-pad:** fired continuously at ~60 Hz (≈15x the client's own 4 Hz heartbeat, ≈10x the anti-cheat's
  6/s sustained refill) for a clean 0%→100% run. Completed in ~30 tick-steps of ~3.1–3.5 points each at
  the server's 4 Hz tick — the same per-step size a normal single `E`-hold produced — landing at ≈7.5–8s
  total, matching `Config.Tasks.HoldTime=8` despite far more requests being sent. `TaskProgress.tick`
  consumes only `elapsed = os.clock() - lastTickAt`; request count never enters the calculation, and the
  live behaviour matches that by construction.
- Full console transcript: `artifacts/hold-completion-and-spam-immunity.md`.

## Part 2 — a hold completes in ~8 seconds

`[TaskService] Task complete: TaskPoint_05` fired after a continuous on-pad hold, followed immediately by
`[Task] 1/5 · here: 100%` and the round snapshot updating to `tasks 1/5`. Post-completion requests
correctly refused `ALREADY_COMPLETE`, so no double-counting. Same evidence file as Part 1.

## Part 3 — walking away freezes, does not reset

Held to 57% on `TaskPoint_12`, walked 200+ studs away (character_navigation, no requests fired for 5s —
well past `PresenceGraceSeconds=0.75s`), then returned and resumed. Console shows the bar going silent
(`here: -`) while away — a display fact, not a decay — then **resuming from 61%, one tick above where it
was frozen, not from 0%** — and climbing to `[TaskService] Task complete: TaskPoint_12`. Full transcript:
`artifacts/walkaway-freeze-and-resume.md`.

## Artifacts

- `artifacts/keyboard-swallow-bug-and-fix.md` — the critical bug, its diagnosis, and the confirmed fix
- `artifacts/hold-completion-and-spam-immunity.md` — Parts 1 and 2, full console transcripts
- `artifacts/walkaway-freeze-and-resume.md` — Part 3, full console transcript
- `artifacts/task-rig.md`, `artifacts/proximity-prompt-probe.md` — pre-existing, read and relied on per
  the brief; not modified

## Not Verified

- **Multi-client behaviour.** Everything here is one Solo-Testing survivor. The freeze rule protecting a
  task a *different* player is standing on when the first one dies, or two survivors' contribution
  weights (the `strongestWeight` max-not-sum rule), needs a second live client — a Studio UI action no
  agent can drive. Named per `playtester.md`'s documented limit.
- **Visual rendering of the ProximityPrompt hint.** `screen_capture` excludes CoreGui (established in
  `proximity-prompt-probe.md`, reconfirmed here), and the new `KeyboardKeyCode=None` warning suggests the
  "Hold [E]" hint text may not render correctly even though the underlying mechanic now works. A human at
  the keyboard should look.
- **Mobile / touch input.** `InputController` binds only `Enum.KeyCode.E`, no touch button
  (`createTouchButton=false`), a known, named hole (C27's subject) — not exercised here since it isn't
  C08's Done condition and there's no way to simulate a touch tap through this tool surface.
- **Secrecy surface.** Not applicable — this diff touches no role or Aswang-identity code, and
  `check:secrecy` passed statically. No live secrecy probe was run because none was in scope.

## Config.luau state at handoff

Unchanged by me. Coordinator to revert:

```
Round.Intermission = 8   (committed: 25)
Round.Duration = 90      (committed: 420)
Round.EndScreen = 6      (committed: 12)
Debug.SoloTesting = true       (committed: false)
Debug.VerboseLogging = true    (committed: false)
```
