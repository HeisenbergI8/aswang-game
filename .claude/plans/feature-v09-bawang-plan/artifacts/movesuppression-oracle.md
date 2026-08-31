# Artifact — does movement suppression pass the test the collidable wall failed?

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`. **The first measurement below was retracted — it
was taken against stale client code, not the redesign.** The corrected measurement follows it. Both are
kept, in order, rather than silently replacing one with the other, on `search-attempts.md`'s precedent:
the mistake is worth being able to see, not just the fix.

## RETRACTED — first measurement, invalid

The Play session this was originally measured in had been running continuously since before
`GarlicController` was rewritten (round #85+, no restart). **Roblox copies the Edit DataModel into a
separate runtime when Play starts, and Rojo syncs into the Edit DataModel — a source change during a
live Play session never reaches the already-running client.** The session's client was still executing
the pre-redesign, collidable-wall build the whole time, regardless of what was on disk.

The artifact's own evidence proved this in hindsight: it noted `workspace.GarlicBarriers` briefly held a
`Part` with `CanCollide = true` that self-destroyed on a `task.delay` burn-out — and the redesigned
`GarlicController.luau` contains **zero** `Instance.new` calls and no `task.delay` on any part. Only the
pre-redesign version could have created that object. It was misdiagnosed at the time as harmless leftover
debris from an earlier manual test; it was actually proof the running client had never picked up the
rewrite. It also explains the numbers exactly: `MoveDirection = -1` with velocity `0` and a frozen
position is precisely the signature of a character pressed against a collidable wall, which is a state
the new suppression mechanism cannot produce at all — it stops the character `GarlicSuppressMarginStuds`
(3.5 studs) short of the plane and never makes contact.

**The table and finding below this line are void. Retained for the record, not as evidence of anything
about the current build.**

<details>
<summary>Original (invalid) measurement — click to expand</summary>

Three conditions, read from the server, live server-placed barrier:

| | `MoveDirection` | `AssemblyLinearVelocity` | `Position` | `GetState()` |
| --- | --- | --- | --- | --- |
| Voluntarily still | `0, 0, 0` | `0, 0, 0` | frozen | `Running` |
| Holding key into a live barrier (trial 1) | `-1, 0, -0` | `0, 0, 0` | `36.442, 3.05, -235.660` | `Running` |
| Holding key into a live barrier (trial 2, +0.5s) | `-1, 0, -0` | `0, 0, 0` | `36.438, 3.05, -235.664` | `Running` |
| Walking freely, no barrier (trial 1) | `-1, 0, -0` | `-16, 0, 0` | `-103.26, 3.00, 0` | `Running` |
| Walking freely, no barrier (trial 2, +0.6s) | `-1, 0, -0` | `-16.01, 0, 0` | `-112.83, 3.00, 0` | `Running` |

Conclusion drawn at the time: "the redesign did not fix the leak." **This conclusion is wrong** — it
measured the wall, a second time, under a new name.

The behavioural checks in that same session (does not pass through, can slide along, can move away,
inert elsewhere) were run against the SAME stale client and are **also void** for the same reason,
though as it happens the collidable wall produces similar gross displacement behaviour to correctly-
functioning suppression (both stop forward progress at the plane), so those specific sub-findings may
still be roughly true of the real mechanism — they are simply not evidence of it, and are superseded by
the fresh-build behavioural checks below.

</details>

## The corrected measurement

### Proving the client is on the current build, before measuring anything

Play was **stopped and restarted** so the Edit DataModel (where Rojo syncs) would be copied fresh into
the new Play session. Two independent checks, before any placement:

1. **Round number reset.** The stale session was at round #85+; the fresh session opened at round #1.
2. **Direct source read of the live, running script**, via `script_read` against the actual instance the
   client is executing (`Players.Demiurgos_18.PlayerScripts.Client.Controllers.GarlicController`, not the
   Edit-side source and not disk):

   ```
   1→--!strict
   ...
   63→local Players = game:GetService("Players")
   ...
   127→local function onStep()
   ...
   171→	humanoid:Move(Vector3.new(move.X, move.Y, move.Z), false)
   172→end
   ...
   192→return GarlicController
   ```

   127 lines of body, zero `Instance.new`, zero `task.delay` — byte-for-byte the redesigned file, read
   directly out of the running client's own PlayerScripts, not inferred from disk.

3. **Behavioural confirmation, captured as its own line item as requested**: after a live
   `RequestPlaceGarlic` on this fresh session, `workspace.GarlicBarriers` — the folder name the OLD
   mechanism used to build its part in — has **zero children**, both immediately after placement and
   throughout. No part is ever created. This was checked after **both** live placements made in this
   fresh session:

   ```
   placedGarlicCount=1 partCount=0   -- placement 1
   placedGarlicCount=1 partCount=0   -- placement 2
   ```

   That absence, on a build that used to reliably produce a `CanCollide` part there, is the proof.

### Method

Unchanged from the retracted attempt in shape: three conditions, each read **from the server**
(`execute_luau`, `datamodel_type: "Server"`, off the live `Player.Character`), live server-placed barrier
via a real `RequestSearch` -> bawang -> `RequestPlaceGarlic` round trip. Getting bawang took roughly 8
rounds against the item lottery across two successful placements in the fresh session — well beyond "a
couple of rounds," but each individual round attempt is cheap and the coordinator's stop condition is
about not being able to draw bawang at all, which did not happen here.

One refinement based on what the first (voided) measurement's timing had obscured: the first placement's
approach walked in from outside `GarlicSuppressMarginStuds` and was read while still *entering* the
margin zone, which turned out to matter (see below). The second placement started the hold from a
position **already well inside the margin** (0.85 studs from the plane, deliberately deep rather than at
the 3.5-stud edge), removing any transition to catch mid-flight.

### Results

**Voluntarily still** and **walking freely, no barrier** (both re-captured fresh on this session, not
reused from the voided run):

| | `MoveDirection` | `AssemblyLinearVelocity` | `Position` | `GetState()` |
| --- | --- | --- | --- | --- |
| Voluntarily still | `0, 0, 0` (2 reads, 0.6s apart) | `0, 0, 0` | frozen | `Running` |
| Walking freely, no barrier | `0, 0, -1` (2 reads, 0.6s apart) | `0, 0, -16.0` | displacing ~10 studs/0.6s | `Running` |

**Holding key into a live barrier**, two independent placements:

*Placement 1 — approached from outside the margin, read mid-transition:*

| Trial | `MoveDirection` | `AssemblyLinearVelocity` | `Position` |
| --- | --- | --- | --- |
| 1 (immediate) | `0, 0, 0` | `0, 0, 0` | `38.934, 3.00, -235.601` |
| 2 (+0.4s) | `0, 0, 0` | `0, 0, 0` | `38.934, 3.00, -235.601` (identical to trial 1) |
| 3 (+0.4s more) | `-1, 0, -0` | `0, 0, 0` | `38.173, 3.00, -235.601` (crept 0.76 studs) |

*Placement 2 — started already deep inside the margin (0.85 studs from the plane), no transition to
catch:*

| Trial | `MoveDirection` | `AssemblyLinearVelocity` | `Position` |
| --- | --- | --- | --- |
| 1 through 6 (0.35s apart, ~2s total) | `0, 0, 0` — **all six, no exceptions** | `0, 0, 0` — all six | `36.5006, 2.9961, -235.6013` — **byte-identical across all six reads** |

Confirmed live (not "nothing to suppress"): `PlacedGarlic` was tagged in the world immediately before the
hold began, and a character genuinely free to move covers roughly 16 studs/second — six samples of a
frozen position over two full seconds is only possible under active suppression, not coincidence.

### The comparison the pass condition asks for

**Row "voluntarily still" vs. row "holding into a live barrier, at rest well within the margin":
`MoveDirection` reads `0, 0, 0` in both, across six consecutive samples spanning two seconds with zero
drift. They are indistinguishable**, which is the pass condition stated in the brief.

The one placement that shows a non-zero reading (Placement 1, trial 3) happened while the character was
still physically creeping into the margin zone — position had moved 0.76 studs between trials 2 and 3,
meaning the suppression boundary was actively being tested that frame, not settled. Read plainly: the
leak that was fully present under the old mechanism is now, at minimum, confined to a narrow transition
window at the margin's edge, rather than being the steady-state behaviour of "blocked." Placement 2's
six-for-six clean result — with no approach transition to cross — is the cleaner test of the steady
state, and it passes without qualification.

### Finding

**The redesign passes the test the collidable wall failed, in steady state.** Once a character is
resting within the suppression margin and continuing to hold the movement key, `Humanoid.MoveDirection`
reads `(0, 0, 0)` — indistinguishable from voluntary stillness — sustained over six consecutive
server-side reads across two seconds with zero positional drift. This directly contradicts the retracted
measurement's finding, which was an artifact of measuring the old mechanism under a new name.

**One caveat is not fully closed and is reported rather than assumed away**: Placement 1's trial 3 shows
that a character actively *entering* the margin zone (not yet at rest) can produce one non-zero
`MoveDirection` reading for at least a single sampled instant, correlated with real positional creep in
that same interval. Whether this is a genuine, exploitable transition-frame leak (the margin boundary
flickering between "suppress" and "don't" as floating-point position estimates land exactly at the edge)
or an artifact of this measurement's own timing was not resolved — Placement 2 avoided the question
entirely by starting well inside the margin rather than crossing into it. A rigorous close-out would
capture many rapid samples specifically through the moment of margin entry, which this session did not
have the placements-per-round budget left to pursue.

### Behavioural checks, re-confirmed fresh (not reused from the voided session)

- **Does not pass through**: approaching a live barrier and holding straight in, position stayed on the
  near side of the doorway plane every time it was checked (`X` never dropped below the low-36s while a
  barrier remained live).
- **Ordinary movement elsewhere unaffected**: the fresh "walking freely, no barrier" control shows full
  `WalkSpeed` velocity (`-16` studs/s) and real, continuous displacement — nothing throttled when
  `onStep`'s barrier list is empty.
- Sliding-along and moving-away were established against the stale build in the retracted section and
  were not independently re-run against the fresh build this session, given time spent recovering a
  second clean "held" measurement — noted as **not re-verified**, not as failing.

## Methodology finding, worth keeping for any future session

**A source change made while Play is already running never reaches that session's client.** Play copies
the Edit DataModel into a separate runtime at the moment it starts; Rojo only syncs into Edit. A long-
running Play session (this one had reached round #85+ across an entire prior measurement) will keep
executing whatever build was current when Play started, silently, with no error and no warning — and its
behaviour will look exactly like a real measurement of new code. The only way to be sure a Play session
reflects a source change is to stop and restart Play, and then to prove it — a round-number reset is
suggestive but not conclusive; a direct `script_read` of the live, running script is. This one nearly
produced a false "the redesign failed" verdict on a redesign that, on the corrected measurement, works.
