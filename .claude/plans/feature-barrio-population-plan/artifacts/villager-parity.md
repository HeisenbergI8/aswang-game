# Phase 6 reference — the Humanoid parity table, answered empirically

**Outcome: the phase takes its documented Step 6.6 exit. VILLAGER stays the Phase 5 mesh.**

Everything below was measured in Studio session `ab384d6d`, Play mode, on a rig built with
`Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), Enum.HumanoidRigType.R15)`.
Nothing here is inferred from documentation.

## The technical gate — it PASSES

The plan named three exit conditions. **None of them fired.**

| Question | Answer | Evidence |
| --- | --- | --- |
| Can a non-player R15 rig be built server-side? | **Yes** | 274 descendants, 16 BaseParts |
| Does `EvaluateStateMachine = false` stick? | **Yes** | read back as `false` |
| Does a default catalogue walk animation load on a non-player Animator? | **Yes** | `rbxassetid://507777826`, `IsPlaying = true`, `Length = 0.667` |
| Does it actually drive the joints? | **Yes** | `LeftFoot` moved **2.5756 studs** relative to the root over 0.35s |
| Does `AnimationTrack.Speed` scale it? | **Yes** | at Speed 3, 1.6193 studs in 0.15s vs 2.5756 in 0.35s at Speed 1 |
| Does `PivotTo` interrupt the track? | **No** | still playing after a 6-stud pivot |
| Is `MoveDirection` zero under `PivotTo`? | **Yes, as predicted** | `0, 0, 0` — which is exactly why the animation must be displacement-driven and never locomotion-driven |

**Two mechanical traps found on the way, both of which would have shipped a frozen villager:**

1. **Anchoring every part freezes the animation.** The first probe anchored all 16 BaseParts and read
   `FROZEN POSE` — a Motor6D cannot move a child that is anchored. Only the **root** may be anchored.
2. **The rig has no joints until `Humanoid:BuildRigFromAttachments()` is called.** Before that call the
   model has zero joints and animates nothing. (It reports 0 `Motor6D` even after — R15 from this API
   uses 15 `AnimationConstraint` instances instead. It animates regardless, which is the fact that
   matters.)

So the sliding-villager leak the plan was most afraid of **is solvable**, exactly as Step 6.2 proposed:
drive the track's `Speed` from measured displacement, never from `Humanoid.MoveDirection`.

## The gate the plan did not write down — and it FAILS

**A default `HumanoidDescription` produces a blank, untextured Roblox avatar.** `ScreenCapture_6` shows
the probe rig beside a real player character: a generic dark blocky figure with no clothing, no hat, no
face, and none of the research Phase 5 spent its whole budget encoding.

Against the Phase 5 mesh villager — salakot, sando, work trousers, tsinelas, weathered — it is a
straightforward downgrade in art. And the user's request was specific:

> "I want them to look like a regular human being NPC that is doing something for example drinking in a
> shed, or standing by outside the house or looking at their animals"

Dressing the rig would need catalogue asset ids for shirt, trousers and a salakot accessory, each an
unverified Roblox fact, and the result would still be a blocky avatar rather than a rural Filipino.

## And the cost the plan under-estimated by 6×

| | Plan's estimate | Measured |
| --- | --- | --- |
| Instances per villager rig | ~45 | **274** |
| For three villagers | ~135 | **822** |

Composition of one rig: 69 `Vector3Value`, 53 `Attachment`, 27 `Animation`, 20 `StringValue`, 19
`NoCollisionConstraint`, 18 `NumberValue`, 15 `MeshPart`, 15 `AnimationConstraint`, 15 `WrapTarget`,
14 `BallSocketConstraint`, plus a `LocalScript`, a `HumanoidDescription` and a `FaceControls`.

The barrio is ~1,125 instances. **Three Humanoid villagers would raise that by 73%** — for a villager
that looks worse than the one already shipped.

## The decision

Take Step 6.6. `FORM_LOOKS.VILLAGER` keeps the Phase 5 mesh; no Humanoid branch is added; no
`strideRate` is added to `AmbientMotion`, because a function with no caller is not a deliverable.

The plan's own principle decides it, read in the direction the evidence points:

> "A mesh villager is not a downgrade to the mechanic, only to the art. The disguise is whatever rig
> the barrio is standing in, and a mesh villager that is *indistinguishable* is worth more than a
> Humanoid villager that is *better and tellable*."

Here the Humanoid would have been a downgrade to **the art as well**, at six times the estimated
instance cost, with the mechanic no better off — the mesh villager already gets its life from Phase 4's
`stepEntity`, which every rig shares, so there is no parity surface at all.

## Follow Up this opens

**Three identical mesh villagers is the remaining weakness**, and it is the user's "doing something"
request left unanswered rather than a defect. The fix is pose variety — a standing villager, one seated
with a bottle at the store bench, one leaning on a porch rail — as three separate generated meshes.

It does not fit today's budget: `RigMeshes` is at 7,800 of a 9,000 ceiling, and two more villager poses
at 1,800 each would be 11,400. It needs either a re-argued ceiling or cheaper poses, which is a
decision rather than an oversight. Recorded for the user.
