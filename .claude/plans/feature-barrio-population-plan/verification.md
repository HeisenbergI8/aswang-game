# Verification — feature-barrio-population-plan

All eight phases implemented. `npm run verify` green: **54 test files, all eight checks**.

## What was verified in the running game, not only in the tree

| Claim | Evidence | Artifact |
| --- | --- | --- |
| A disguised animal stands on the same ground as a real one | free-vs-puppeted delta **+2.6 studs → −0.0051** across all six forms | `artifacts/rig-height.md` |
| `HipHeight + root.Size.Y/2` is the right foot offset | measured **2.9980 vs a true 2.9929**; `HipHeight` alone off by 0.99 | `artifacts/rig-height.md` |
| Free rigs rest on the ground | worst vertical error **2.200 → 0.003 studs**, 18 rigs | `artifacts/rig-height.md` |
| Every rig is inside its own form's territory | 3 per form, worst leash 20.7 of 24 | `artifacts/territories.md` |
| No rig freezes when it stops moving | **0 of 18** with no vertical motion | `artifacts/motion-parity.md` |
| Sway does not accumulate | tilt **5.98° → 2.50°**, uniform, against a 4° cap | `artifacts/motion-parity.md` |
| All six rig meshes load | **0 of 18 fell back to a box** | `artifacts/rig-meshes.md` |
| Six silhouettes are tellable apart | `ScreenCapture_5`, 14 studs, shipped fog | `artifacts/six-forms.md` |
| A Humanoid villager was properly evaluated, not assumed | walk animation loads, drives joints 2.58 studs, survives `PivotTo` | `artifacts/villager-parity.md` |
| The layout still holds | `measure.luau` **10/10**, 34.8s, 39/39 reachable | `artifacts/crossing-after-interiors.md` |
| The budget | 1127 measured, ~1377 computed, band 1250–1450 | `artifacts/final-population-perf.md` |

## Four defects runtime found that the tree could not

1. **`wanderTick` was a third site deciding a rig's Y.** Phase 2's fix had *no effect* — all 18 rigs
   still sat at pad height. Every static check was green over a fix that did nothing.
2. **`stepEntity` compounded its own sway.** It read the base orientation back off the model, which
   already contained the previous frame's roll, so a still animal slowly rolled onto its side. The
   pure suite was green and correct throughout — the bug was in the caller's accumulation.
3. **`Enum.Material.Porcelain` does not exist.** `tools/greybox/` is outside `src/`, so `analyze`,
   `lint` and `fmt` never read it; this would have thrown at build time in Studio.
4. **A Roblox cylinder's axis is X.** The rolled `banig` and the `kalan` were both sized as if it were
   Y. No test in this repo looks at a shape.

## Two defects the suites found before runtime

- **`amplitudeFor`'s knee was an inverse frequency used as a speed** — 0.71 studs/s, below walking
  pace, so every rig saturated and a sprinting monster looked like a strolling pig. That is §4.5's one
  licensed tell, flattened, with the analyzer perfectly happy.
- **The plan's own `formFromId` scan could never pass.** `if id == "` is a substring of
  `elseif id == "`, so every branch matched twice.

## What is NOT verified, stated plainly

- **No end-to-end camouflage was driven.** `ClaimSlot` is unreachable through `execute_luau` —
  `require` returns a fresh module with an empty roster — and a real hide needs a reveal and a second
  player. Parity rests on the two paths provably calling one `stepEntity`, plus 487 pure assertions.
- **Phases 7 and 8 are not in the place file.** The builder has not been re-run, so the interiors,
  cladding, lanterns and territory props exist in `tools/greybox/barrio.luau` and in the suites only.
  The navmesh claim for them is structural — `prop()` and `mesh()` force `CanCollide = false` and the
  build asserts `dressColliders == 0` — rather than measured.
- **No FPS on a phone.** §5's budget is specified in frames on a handset and nothing here could
  measure that.
- **The place is not published.** `artifacts/final-population-perf.md` names this as the outstanding
  risk: the map exists in one binary that is not in git.
