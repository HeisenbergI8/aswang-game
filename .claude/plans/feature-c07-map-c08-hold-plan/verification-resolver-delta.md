# Verification: the resolver/weight delta to C08 (post-verification refactor)

**Date:** 2026-08-12
**Scope:** three behavioural changes made to `TaskService.luau` since C08's own verification.md was
written — (1) `taskPointAt` delegating to `src/server/pure/TaskResolve.luau` via a `Vector3 -> {X,Y,Z}`
conversion at the call site, (2) nearest-INCOMPLETE task resolution replacing first-match (the soft-lock
fix), (3) an unconditional warning when the draw cannot honour `Config.Tasks.MinSpacingStuds`, and (4) a
regression check that `weightFor`'s delegation to `src/server/pure/TaskWeight.luau` still gives an ALIVE
player full weight. C08's Done condition itself (hold completes in ~8s, spam gains nothing, walking away
freezes) was already verified end-to-end in the previous session and is **not re-derived here** — see
`verification.md` and its `artifacts/`.
**Rojo serving:** yes.
**Studio reachable:** yes — single Studio instance `Place3`, `Edit`/`Client`/`Server` datamodels all used.
**SoloTesting:** on, set by the coordinator before I started (`Round.Intermission=8`, `Duration=90`,
`EndScreen=6`, `Debug.SoloTesting`/`VerboseLogging=true`). I did not touch `Config.luau`. `git diff
src/shared/Config.luau` shows only those five lines as testing overrides; everything else in that file's
diff (`PresenceRangeStuds`, `PresenceGraceSeconds`, etc.) is pre-existing feature work from before this
session, not something I added.

## Summary

**All four checks PASS, with live runtime evidence for all four — including the one the brief called
optional and best-effort (nearest-incomplete overlap).** No regression found. One pre-existing, already-
known non-blocker (the `KeyboardKeyCode=None` CoreGui warning) recurs, unchanged.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `- analyze: ok` |
| unit (Lune), pure modules under test | 14/15 files PASS | `task-resolve` (33 assertions), `task-weight` (8-cell grid + 10 assertions), `task-pool`, `task-progress`, and 10 others all PASS. Only `config.test.luau` fails, and only its two debug-value assertions (`SoloTesting`, `Duration`) — expected, the same pattern the prior C08 session recorded |
| #1 — `taskPointAt` conversion, end to end | PASS | `artifacts/delta-1-hold-end-to-end.md` — full console transcript, hold 0%→100%, `[TaskService] Task complete: TaskPoint_10` |
| #2 — nearest-INCOMPLETE resolution | PASS (forced live, not skipped) | `artifacts/delta-2-nearest-incomplete-overlap.md` — a completed point at distance ≈0 did not mask an incomplete point at distance ≈4; the bar restarted 0%→100% on the second point immediately, zero `ALREADY_COMPLETE` refusals |
| #3 — spacing warning, negative case | PASS | absent in both delta-1 and delta-2's transcripts, over a real draw against the unmodified 30-stud rig |
| #3 — spacing warning, positive case | PASS (done anyway, not skipped) | `artifacts/delta-3-spacing-warning-both-cases.md` — all 12 pads clustered under 20 studs, warning fired verbatim on the next draw |
| #4 — `weightFor` / `TaskWeight` regression | PASS | same transcript as #1 — an ALIVE solo survivor completed the hold in the expected ~8s at the expected ~3.1–3.5%/tick, i.e. full, unattenuated weight |

## Detail

### #1 — the one I was most worried about

Character navigated to `TaskPoint_10` (one of round #1's five drawn points), `E` held continuously for
9.5s. Client bar climbed `3% → 98%` in clean ~3% steps at the server's 4Hz tick, then
`[TaskService] Task complete: TaskPoint_10` fired and the round snapshot updated to `tasks 1/5`. Had the
`Vector3 -> {X,Y,Z}` conversion at the `taskPointAt` call site been wrong, `TaskResolve.at` would have
compared against garbage coordinates and every tick would have resolved to `nil` — the bar would never
have left 0%, and the console would show a stream of `NO_TASK_IN_RANGE` refusals instead. It did not.
Full transcript: `artifacts/delta-1-hold-end-to-end.md`.

### #2 — the soft-lock fix, actually reproduced

The brief flagged this as unreproducible with the rig as built (30-stud pitch, 9-stud presence range)
and offered moving a spare pad as optional, best-effort. Rather than settle for that, one of the round's
**own drawn points** was moved live via a server-authoritative `CFrame` write (`execute_luau` against the
`Server` datamodel — an instance-property change, not a script write, so `guard-studio-sync.mjs`'s
concern about Rojo clobbering it does not apply and nothing under `src/` was touched) to sit 4 studs from
another drawn point that was about to be completed.

After completing the nearer point, the player kept holding `E` in the same spot. The bar immediately
restarted `0% → 100%` on the second point rather than sticking on `ALREADY_COMPLETE` — the exact soft-lock
`TaskResolve.luau`'s docstring names, forced to happen and observed not happening. Full transcript,
including the exact moves and the restore: `artifacts/delta-2-nearest-incomplete-overlap.md`.

### #3 — the packed-spacing warning, both directions

**Negative (must be silent):** searched both delta-1's and delta-2's full transcripts — the warning text
never appears, over two real draws against the rig's unmodified 30-stud grid. `spacingRespected` is not
inverted.

**Positive (must fire):** all 12 rig pads temporarily clustered into a 4-stud-by-6-stud grid (well under
`MinSpacingStuds = 20`), Play started, and the very next draw logged:

```
[TaskService] Task points are packed too tightly to honour Config.Tasks.MinSpacingStuds (20 studs); this round's tasks are not spread. Move the TaskPoint anchors further apart, or lower the setting.
```

Rig restored to the exact original grid afterward and reconfirmed by a closest-pair scan
(`ClosestPairStuds: 30`, matching `task-rig.md`'s original measurement). Full detail:
`artifacts/delta-3-spacing-warning-both-cases.md`.

### #4 — `weightFor` regression

Not independently exercised — as the brief noted, nothing role-specific is observable solo. Instead,
confirmed by the same evidence as #1: `TaskWeight.forPlayer`'s Lune grid (`task-weight.test.luau`, 8-cell
`PlayerState × Role` grid) passes under `npm run test:unit`, and the live hold in delta-1 completed in the
expected ~8s at the expected per-tick size with no attenuation — consistent with an ALIVE player getting
full weight, not a partial or zero one. If the delegation had broken full-weight contribution, the hold
would have taken longer than `HoldTime=8` or never completed; it did neither.

## Not Verified

- **Multi-client behaviour** — everything here is one SoloTesting survivor, per the brief. Not attempted;
  needs a second live client (a Studio UI action no agent can drive), same limit the prior C08 session
  named.
- **The Aswang's weight specifically** (`RoleService.Aswang` branch of `TaskWeight`) — not observable
  solo with `ForceAswangWhenSolo = false`, per the brief. `task-weight.test.luau`'s 8-cell grid is the
  only coverage of that branch right now.
- **Visual rendering of the ProximityPrompt hint** — unchanged from the prior session's finding
  (`screen_capture` excludes CoreGui); the same `KeyboardKeyCode=None` CoreGui warning recurred in every
  transcript here, expected and not a regression.

## Config.luau state at handoff

Unchanged by me. Coordinator to revert (unchanged from the prior C08 session's handoff):

```
Round.Intermission = 8   (committed: 25)
Round.Duration = 90      (committed: 420)
Round.EndScreen = 6      (committed: 12)
Debug.SoloTesting = true       (committed: false)
Debug.VerboseLogging = true    (committed: false)
```

## Rig state at handoff

`workspace.TaskRig_TEMP` — all 12 pads confirmed back at their original grid positions
(`xs = {-45,-15,15,45}`, `zs = {-30,0,30}`), closest pair 30 studs, matching `task-rig.md`. Not
published, per that file's original note.
