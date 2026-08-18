# Verification: C27 (mobile input + light budget) and C28 (diegetic sunrise)

**Date:** 2026-08-18
**Scope:** the C27/C28 diff — two new pure modules, two new client controllers, the touch pad in
`UIController`, the verb extraction in `InputController`, `QuickChatController`'s registration,
`TaskController.IsTimingBarLive`, `Config.Performance`/`Config.Sky`, and `barrio.luau`.
**Studio:** `aswang.rbxl`, Play mode, `rojo serve` running (PID 78052).
**Config at capture time:** `Round.Intermission=8, Duration=40, EndScreen=6`,
`Debug.SoloTesting=true`, `Debug.VerboseLogging=true` — set by the coordinator for testing and
reverted afterwards.

## Provenance, stated up front

This file was **assembled by the coordinator**, not written by the `playtester` agent. The agent
produced the two console artifacts cited below and then stopped twice without writing a report — once
returning no text, once returning a mid-work note. Rather than pay for a third resume, the coordinator
read its artifacts and ran the three remaining checks directly through Studio MCP.

Every row below names where its evidence came from. Nothing here is inferred from reading source.

## Results

| # | Question | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Client boots clean | **PASS** | `artifacts/sky-cycle-console.txt` — `[Client] Ready. 11 controllers loaded.`, no controller error |
| 2 | Does the sky move? | **PASS** | `artifacts/sky-cycle-console.txt` — per-second samples over two rounds |
| 3 | Is the night recovered EXACTLY? | **PASS** | `artifacts/sky-cycle-console.txt` — bit-for-bit against the Edit-mode capture |
| 4 | Does the light cull work? | **PASS** | `artifacts/light-cull-console.txt` — 6 passes, 13 tagged, 5 lit |
| 5 | Are the gameplay tells safe? | **PASS** | coordinator, Server datamodel, output inline below |
| 6 | Desktop regression on E/R/Q/B | **PASS** | `artifacts/desktop-keys-console.txt` — all four keys driven for real |
| 7 | Pad correctly absent on desktop | **PASS** | coordinator, Client datamodel, output inline below |
| — | Touch pad's on-screen behaviour | **UNVERIFIED** | requires a real phone; the user owns this |

## Q2 — the sky is the countdown

`ClockTime` climbs monotonically 3.0 → 6.4 across each 40s ACTIVE round and never dips. Alongside it:
brightness 1.0 → 2.4, `FogEnd` 341 → 886.6 (the fog lifts), `Atmosphere.Density` 0.42 → 0.231, and both
ambients warm and brighten. `ENDING` pins the frame at dawn unconditionally, which is
`SkyCycle.progressFor`'s documented behaviour for an aborted round as much as a completed one.

Rounds #2 and #3 reached **identical** dawn values, which is the stronger claim: it composes two
independent capture-and-restore cycles rather than measuring one.

## Q3 — the night comes back exactly

This is the claim the design most needed proven, because its failure mode is silent and cumulative:
`MonsterService`'s C04 revert restored hardcoded defaults instead of captured state and permanently
branded the ex-Aswang. A sky that returned to a hardcoded night would do the same to the whole map, one
shade per round, with nothing on screen naming it.

After `RestoreSeconds` (~3s) the lobby settles at `ClockTime=3.000, Brightness=1.000, FogEnd=341.0,
Atmosphere.Density=0.4200, Ambient=(0.054902, 0.0627451, 0.101961), OutdoorAmbient=(0.101961, 0.117647,
0.180392)` — **bit-for-bit identical** to the Edit-mode values captured before Play was pressed.

## Q4 — the light budget is actually spent

13 scenery lights tagged at runtime (see the artifact's note on why the map was not rebuilt);
`lit=5` on every pass, which is exactly `MaxVisibleLights(8) − ReservedGameplayLights(3)`. The five lit
are the five nearest to the camera (64, 77, 98, 106, 114 studs) and the next nearest at 162 studs is
dark. The same five stayed lit across 6 passes over 9 real seconds spanning an ACTIVE → ENDING →
INTERMISSION transition, with the camera stationary — the anti-flicker property holding.

## Q5 — the tells cannot be culled

Run by the coordinator on the Server datamodel during a live round:

```
Lights in workspace: 13 tagged MapLight, 4 untagged
Untagged (invisible to the culler, therefore never switched off):
  Workspace.Barrio.TrialCorner.TrialLantern_Head.Glow (Enabled=true, MapLight=false)
  Workspace.SaltPouches.SaltPouch_SaltSpawn_Plaza.PouchGlow (Enabled=true, MapLight=false)
  Workspace.SaltPouches.SaltPouch_SaltSpawn_Rice.PouchGlow (Enabled=true, MapLight=false)
  Workspace.SaltPouches.SaltPouch_SaltSpawn_AlleySW.PouchGlow (Enabled=true, MapLight=false)
SaltPouch-tagged instances: 3
```

Every salt-pouch glow is untagged and still `Enabled`. No transform was live during the sample, so the
Aswang's eye glow was not observed directly; `change-auditor` established structurally that
`MonsterService.luau:268-276` applies no tag at all, and the culler only ever reads
`CollectionService:GetTagged("MapLight")`.

**This check found a real defect in the map contract.** `TrialLantern_Head.Glow` is scenery built by the
same `lantern()` helper, so after a rebuild the tag count is **14**, not the 13 the header claimed
(12 street lanterns + the trial corner's + the chapel glow). `barrio.luau`'s contract row was corrected.
The runtime sample tagged 13 because it enumerated `Workspace.Barrio.Lanterns` and the chapel only.

## Q6 — desktop regression: PASS, driven with real keypresses

Closed after the first pass of this file. Four transient recording listeners were attached on the
server, the keys were driven through Studio MCP, and the listeners were removed afterwards. Full
output in `artifacts/desktop-keys-console.txt`; the four results:

- **E** — five `RequestTaskProgress` heartbeats across a 1.5s hold, 0.26s apart, matching
  `Tasks.HeartbeatInterval = 0.25`. **And they stopped dead on key-up**, which is the release edge
  working: a stuck hold would have kept firing four times a second. That is the keyboard-path proof
  of the property the pad's `actInput` check protects on a phone.
- **R** — one `RequestTimingStop`, zero arguments.
- **Q** — one `RequestThrowSalt` carrying the camera LookVector, with `RequestTrialThrow` silent, so
  C22's trial routing survived the extraction into `performThrow`.
- **B** — the wheel opened with all eight sectors, and its frame sat at exactly (205, 205) =
  `WheelRadiusPx + SectorSize/2`, i.e. C27's new clamp visibly firing rather than merely present.

**Three long-standing ⚠ UNCONFIRMED notes were resolved by this** — `R` and `Q` in `InputController`,
`B` in `QuickChatController` — all descendants of C08 shipping unreachable behind ProximityPrompt's
`E`. No CoreScript claims any of them in this place. Those comments now cite this artifact instead of
repeating the warning.

### The original gap, for the record

All five game binds are registered on the desktop client with the right keys, and none asks for a CAS
touch button any more:

```
BOUND AswangTransform -> [Enum.KeyCode.T]   createTouchButton=nil
BOUND AswangKill      -> [Enum.KeyCode.F]   createTouchButton=nil
BOUND TaskHold        -> [Enum.KeyCode.E]   createTouchButton=nil
BOUND TaskTimingStop  -> [Enum.KeyCode.R]   createTouchButton=nil
BOUND SaltThrow       -> [Enum.KeyCode.Q]   createTouchButton=nil
BOUND QuickChatWheel  -> [Enum.KeyCode.B]   createTouchButton=nil
```

The `playtester` agent spent its budget attempting this and never landed it; the coordinator drove the
keys directly afterwards, which is what the section above records.

**Still not claimed:** that a task runs all the way to `Task complete`, or that a thrown pouch stuns
anything. Those are C08/C14 mechanics that this diff did not touch — what C27 changed is the path from
key to wire, and that is what was measured. Releasing the wheel with no drag sending nothing is also
unclaimed: `RequestQuickChat` was not among the watched remotes.

## Q7 — the pad is correctly absent on desktop

```
TouchEnabled=false KeyboardEnabled=true -> isTouchDevice=false
TouchPad present: false
Hud children: Timer, TaskBar, Status, Prompt, Actions
```

The desktop HUD is exactly what C18/C26 built, with the corner `Actions` frame still present for the
Aswang — which is the intended split: the pad takes those two verbs over only when it exists.

## What the user still owns

1. **Re-run `tools/greybox/barrio.luau` in Studio Edit mode.** Until then the `MapLight` tags and the
   streaming radii do not exist in the place, and `PerformanceController` finds nothing and does
   nothing. It fails safe — lights simply stay as the map left them.
2. **The touch pad on a real phone.** Nothing in this file establishes that any button on it works;
   the desktop client cannot draw it.
3. **C27's actual done condition:** 30fps sustained on a mid-range Android during a chase. Set
   `Debug.VerboseLogging = true` for the on-screen `fps · lit` readout.

## Gates

`npm run verify` was green before the playtest values were set: analyze ok, all five checks ok,
`check:debug` ok, 32/32 Lune files ok — including the two new suites (`sky-cycle` 32 assertions,
`light-budget` 24) and `config.test` at 61 invariants. While the debug values were in place,
`check:debug` and two `config.test` checks failed by design; both were reverted afterwards and the
tree re-confirmed green.
