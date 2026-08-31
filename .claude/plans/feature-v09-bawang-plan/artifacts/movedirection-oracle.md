# Artifact — the MoveDirection oracle: is the block actually silent?

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode. Answers the exploit audit's question:
does a character held against a garlic barrier differ, in server-visible replicated state, from a
character voluntarily standing still in the same spot?

## Why this used a manual replica wall, not a freshly-placed live one

Roughly eight rounds were spent trying to draw bawang from the search pool (`Config.Items.CarryLimit=1`,
2 bawang per 7 items across 15 containers, re-seeded every round) and chain a live
`RequestSearch` -> `RequestPlaceGarlic` -> collision test inside one uninterrupted `ACTIVE` window. Every
attempt lost the race against real elapsed time between separate MCP tool calls — sometimes an entire
round cycled (45s ACTIVE + 6s ENDING + 8s INTERMISSION + 4s STARTING) between two consecutive calls, which
this session's turn-to-turn latency apparently exceeds unpredictably. One attempt's outcome is itself
informative and is recorded below as a secondary data point.

Rather than keep burning rounds on the item lottery, this measurement uses the same manual-replica
technique as `artifacts/yaw90-collision-block.md`: a wall built with `GarlicController.rebuild`'s exact
formula (`Anchored`, `CanCollide = true`, `Transparency = 1`, same `Config`-derived size, same
`CFrame.Angles(0, math.rad(90), 0)`) at the chapel's east doorway. This is a legitimate substitute for
this specific question because:

- `GarlicController.luau` has **zero code paths** that touch `Humanoid`, `MoveDirection`, `WalkSpeed`, or
  any character property (confirmed by static grep in `artifacts/no-feedback-to-aswang.md` — the only
  matches are header prose). Whatever `MoveDirection`/velocity/position signature a blocked character
  produces is pure Roblox engine physics and replication, identical regardless of whether the specific
  `CanCollide` part was server-placed or built by hand with the same specification.
- `artifacts/placement-and-barrier.md` already proved the live pipeline's barrier is byte-identical to
  this formula on every recorded property (Position, Size, CanCollide, Transparency).

## Method

1. Built the replica wall at `(35.65, 0.4, -235.6)`, yaw 90 (chapel east doorway).
2. Aimed the client's camera down world -X (`W` maps to camera-relative forward, which the
   ControlModule flattens onto the XZ plane; aiming the camera makes `W` = walking toward the wall).
3. **Held condition**: sent a real `keyDown W` (no `keyUp` — a genuine sustained hold, the same input
   path `ContextActionService`/`PlayerModule` would receive from a human), waited, then read four values
   **from the server** (`execute_luau`, `datamodel_type: "Server"`) off the Aswang's live character —
   not a fresh `require()`, a direct read of the live `Player.Character` Instance.
4. **Still condition**: sent `keyUp W` (releasing the hold — the character was already resting against
   the wall from the approach, so this is "arrived, then stopped trying" rather than "never tried" — see
   Caveats), waited, and read the same four values.
5. Repeated the held condition a second time from a different starting position and approach angle, to
   check whether the resting contact point (signature 2) is a consistent, repeatable offset.

## Results — side by side

| Value | **Still** (key released) | **Held** (key down, pressed against wall) | **Held, 2nd approach** (different start) |
| --- | --- | --- | --- |
| `Humanoid.MoveDirection` | `0, 0, 0` (both trials) | `-1, 0, -0` (all 3 trials, 1s apart) | `-0.999, 0, -0.037` (both trials) |
| `HumanoidRootPart.AssemblyLinearVelocity` | `0, 0, 0` | `0, 0, 0` | `0, 0, 0` |
| `HumanoidRootPart.Position` | `36.461, 3.00, -235.660` (frozen, both trials) | `36.442 -> 36.442 -> 36.438` (drifts <0.004 studs over 2s) | `36.438 -> 36.434` (drifts <0.005 studs) |
| `Humanoid:GetState()` | `Running` | `Running` | `Running` |

(Raw values, unrounded, are in the session's tool-call history; the table above preserves the meaningful
digits.)

## The finding, stated plainly

**`Humanoid.MoveDirection` is a reliable, server-visible difference between a blocked character actively
holding its movement key and one voluntarily standing still.** `-1, 0, -0` vs `0, 0, 0` is not a one-frame
fluke — it held across three separate reads spanning ~2 seconds in the first trial, and reproduced (at a
slightly different angle, matching the different approach direction) in a second, independent trial from
a different starting position. `AssemblyLinearVelocity`, `Position`, and `Humanoid:GetState()` are **not**
distinguishing — all three are identical (within float noise) between the two conditions, which rules out
signatures 3 and (mostly) the raw `GetState()` reading as the leak, and narrows it to signature 1
specifically.

**Signature 2 (a consistent, repeatable contact offset) is also present, secondarily**: both held trials
rest at X ≈ 36.44 (36.442/36.442/36.438 and 36.438/36.434), a spread of about 0.03 studs across two
different approach paths — a deterministic tangent point, not "anywhere". This alone would need
comparison against several genuinely-voluntary stopping points to be conclusive (a player choosing to
stop near a doorway might also cluster there for mundane reasons — it is a natural place to stand) so it
is reported as corroborating, not as the primary finding.

## What this means for V09's central claim

**`Humanoid.MoveDirection` differing reliably between blocked-and-holding and voluntarily-still is a role
oracle**, exactly as the audit warned, and it does not depend on anything `GarlicController.luau` does —
it is inherent to how any `CanCollide` obstacle interacts with Roblox's Humanoid movement model, which
`GarlicController` cannot suppress from the client side (nothing sets `MoveDirection`; the engine
computes it from the live input state every frame regardless of whether the requested motion succeeds).
It replicates to the server (directly observed here) and, because `MoveDirection` is an ordinarily
[replicated](https://create.roblox.com/docs/reference/engine/classes/Humanoid#MoveDirection) property of
every character, it replicates to **every other client** too — which is exactly the audience the loyalty
test's oracle concern is about. A third player's own client script reading a fellow player's
`Humanoid.MoveDirection` while that player is pressed against a garlic doorway, but not displacing, would
see the same signature captured here.

**This is a real defect in V09's central design claim** ("byte-identical from a third player's client"),
not a theoretical one, and I am not softening it: on the evidence gathered, **the block is not fully
silent**. It is silent in every property `GarlicController.luau` itself controls or could control
(no `WalkSpeed`, no attribute, no tag, no VFX/sound/camera effect — all independently confirmed in
`artifacts/no-feedback-to-aswang.md`), but the underlying Roblox Humanoid model exposes the block anyway
through `MoveDirection`, a property outside this file's control by construction.

## A secondary, informational data point

One earlier attempt (documented in the session but not repeated here as a clean artifact) held `W` while
approaching a barrier that then died mid-approach (a round-transition race, not a game defect) — the
character walked straight through the now-cleared doorway to `X = -33.5`, with the server reading
`MoveDirection = -1, 0, -0` at that point too: further evidence that `MoveDirection` reflects held input
continuously and reliably, independent of whether an obstacle happens to be present.

## Caveats

- The "still" sample here is "arrived at the wall via a hold, then released the key" rather than "walked
  up and stopped by choice, never having pressed into the wall." In practice these are the same terminal
  physical state (an idle character at rest near a doorway) and `MoveDirection` reads identically either
  way once the key is not held — but a fussier control would also test a character that walked up and
  stopped a stud short on purpose, never touching the wall. Given `MoveDirection` is driven purely by
  current input state, not by history, this distinction should not matter, but it is named for
  completeness.
- This uses a manually-built replica of the barrier, not a server-placed live one — reasoned about above,
  but it means the test proves the general Humanoid/replication mechanism rather than proving this
  specific round's server-side `pushBarriers` pipeline in the same breath. `artifacts/placement-and-barrier.md`
  already closes that gap on the geometry side.
- Peer-to-peer confirmation — an actual second client reading the Aswang's `MoveDirection` and correctly
  inferring "blocked" — was not performed and remains human-gated, same as every other two-client item in
  this plan's verification. The claim here is about what replicates and is readable, which is the
  necessary precondition for that oracle to exist; it does not require a second client to establish.
