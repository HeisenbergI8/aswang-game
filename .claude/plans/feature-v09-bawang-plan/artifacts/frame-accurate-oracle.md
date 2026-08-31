# Artifact — frame-accurate sampling: does a per-frame window exist between raw and suppressed?

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, same fresh (post-restart, verified) Play session
as Addendum 3. Answers a sharper version of the question Addendum 3 left open: discrete reads 0.3-0.5s
apart cannot rule out that Roblox samples `Humanoid.MoveDirection` for replication *between* the control
module's raw `Move` call (`Input` priority) and `GarlicController`'s corrected one (`Input + 1`) on some
frames. A `RunService.Heartbeat` connection on the server, sampling every frame, can.

## Method

One self-contained server script per condition: connect to `RunService.Heartbeat`, sample
`Humanoid.MoveDirection` and `HumanoidRootPart.Position` every frame for several seconds, accumulate
counts (never the raw per-frame list, per the brief), disconnect, return the aggregate. Counted per
frame: total frames, frames with non-zero `MoveDirection`, max magnitude seen, and — the signature that
actually matters — frames where `MoveDirection` was non-zero **while position did not change**
(displacement < 0.001 studs since the previous frame), which is the combination a genuinely walking
player cannot produce and a suppressed-but-still-pressing one would.

## Condition (b): voluntarily still — clean, frame-accurate

```
totalFrames = 300  (5.0s at 60fps)
nonZeroMoveDirFrames = 0
maxMagnitude = 0
nonZeroWhileNotDisplacingFrames = 0
```

**Zero non-zero frames out of 300.** At full frame resolution, a voluntarily still character never
reports a non-zero `MoveDirection`, not even for one frame. This closes (b) completely.

## Condition (a): holding into a live barrier, settled inside the margin — NOT ESTABLISHED at frame resolution

This is the honest result: **four attempts, none produced a clean frame-accurate sample**, and the
reason is structural rather than the item lottery (bawang was drawn and a barrier placed successfully in
three of the four attempts — the lottery was not the blocker this time).

### What actually blocked it

`GarlicDuration` is 15 seconds. Every attempt requires at minimum two separate tool calls after
placement (start the held-key simulation, then start the server sampling loop), and the real-world gap
between issuing one tool call and the next in this session was, by the second half of this run,
consistently exceeding 15 seconds — sometimes by a wide margin. This was not a timing edge case; it
reproduced across every attempt, including one specifically designed to be immune to it (below).

### Trial log

**Trial 1** — first attempt, before a fast-fail check existed. The 4-second `task.wait` inside the
sampling connection ran to completion, but the barrier had expired partway through:

```
totalFrames = 300, nonZeroMoveDirFrames = 289, maxMagnitude = 1, nonZeroWhileNotDisplacingFrames = 2
startPos = (36.50, 3.00, -235.60)   endPos = (-33.53, 3.30, -235.60)   garlicStillAliveAtEnd = false
```

The end position is deep inside the chapel, well past the doorway and resting against an unrelated
interior wall — the sample spans suppressed-and-still, then expiry, then a free walk-through, then a
second, unrelated collision. The `nonZeroWhileNotDisplacingFrames = 2` cannot be responsibly attributed
to garlic suppression specifically: those two frames could equally be from the settle-in moment at the
start or the unrelated interior-wall stop at the end, and the sample mixes both. Not usable as evidence
either way.

**Trials 2 and 3** — added a fast-fail check (`if #CollectionService:GetTagged("PlacedGarlic") == 0 then
return {aborted = true} end`) so a doomed attempt would cost nothing. Both **aborted immediately**: the
barrier was already gone before the sampling script even started running, meaning the gap between the
prior tool call (starting the hold) and this one alone exceeded the barrier's entire remaining lifetime.

**Trial 4** — anticipating that the *keyboard* tool's round trip was the weak link, this attempt replaced
real key-hold with a self-contained client-side simulation: `Players.LocalPlayer`'s control module was
left engaged, but a `RunService.Heartbeat` connection was started that calls `Humanoid:Move(Vector3.new
(-1,0,0), false)` every frame, independently of any further tool calls — once started, it keeps running
in the background for as long as the connection lives, regardless of gaps in my own tool dispatch. This
should have made the *hold* immune to latency, isolating the barrier's 15-second window as the only
remaining constraint.

It was not enough:

```
totalFrames = 240, nonZeroMoveDirFrames = 240 (100%), maxMagnitude = 1, nonZeroWhileNotDisplacingFrames = 34
startPos = (-33.54, 3.29, -235.55)   endPos = (-33.50, 3.22, -235.57)
```

The **starting** position for this sample was already deep inside the chapel — the barrier had expired
and the character had already walked all the way through and come to rest against the same unrelated
interior wall **before this sampling script even began running**. Every frame in this sample is
post-expiry data: a persistently-held key walking freely, then resting against ordinary geometry that has
nothing to do with V09. The `34` non-zero-while-still frames are the interior wall doing exactly what a
`CanCollide` wall is supposed to do to a held key — irrelevant to the suppression question.

## What this does and does not establish

**Established, cleanly, at full frame resolution: condition (b) is silent.** Zero non-zero frames across
300 samples spanning 5 seconds.

**Not established at frame resolution: whether condition (a) has a per-frame leak.** Every attempt to
capture it was overtaken by real-world latency exceeding the barrier's 15-second lifetime before the
sampling window could even begin, regardless of whether the "held key" was a real keyboard hold or a
latency-immune background loop — the remaining, irreducible constraint was the gap before the *sampling
script itself* could start, which this session could not get under 15 seconds reliably in its second
half.

**The best evidence that exists for condition (a) remains Addendum 3's discrete-read result**: six
separate `execute_luau` reads, roughly 0.3-0.5 seconds apart, spanning two full seconds, all showing
`MoveDirection = (0,0,0)` with a byte-identical frozen position. That is real evidence at a coarser
resolution (roughly 6 samples across ~120 frames, not all 120), obtained earlier in this same session
when tool-call latency was still short enough to land inside the 15-second window. It is not superseded
by this session's frame-accurate attempts — it simply was not reproduced at full frame density, because
the window to attempt that reproduction did not stay open long enough.

## Recommendation

This needs either a much larger `GarlicDuration` for testing purposes (extending the window relative to
whatever latency a given session is running at) or a technique that does not depend on a live server
round trip landing inside a fixed 15-second budget — for instance, driving the entire sequence (hunt,
place, hold, sample) from a single script if a mechanism exists to author and run a temporary server-side
test script rather than orchestrating it through separate tool calls. Neither was available within this
session's constraints.
