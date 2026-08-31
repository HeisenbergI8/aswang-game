# Artifact — condition (a) resolved, frame-accurate, with the blocker removed

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`. Follows `artifacts/frame-accurate-oracle.md`,
whose four attempts all failed for a structural reason: `GarlicDuration = 15` was shorter than this
session's tool-call latency, so the barrier died before the sampler could start — never the mechanism,
never the item lottery. The coordinator raised `Config.Items.GarlicDuration` to `120` and
`Config.Round.Duration` to `600` specifically to remove that race, and this measurement re-runs condition
(a) under those values.

## Confirming the reload before measuring anything

Play was stopped and restarted (same requirement as the previous two corrections in this run — a Config
edit made while Play is running never reaches the already-running client). Two checks:

1. **Config read directly off the live client**: `require(Shared.Config)` inside the running session
   returned `GarlicDuration = 120`, `Round.Duration = 600` — the new values, not the old `15`/`45`.
2. **Round counter reset** to `#1` (from wherever the prior session had reached), and a direct
   `script_read` of the live, running `GarlicController` (not disk) confirmed lines 127-172 are still the
   redesigned `onStep` — no `Instance.new`, suppression-based, unchanged from the version already proven
   correct in `artifacts/movesuppression-oracle.md`.

## Method

Identical shape to the previous (blocked) attempt: hunt bawang, place a live barrier at the chapel's east
doorway, position well inside `GarlicSuppressMarginStuds` (0.85 studs from the plane — `X = 36.5` against
a plane at `X = 35.65`), hold `W` via real keyboard input (camera pre-aimed down world `-X` so `W` walks
straight at the barrier), then run **one** server-side `RunService.Heartbeat` loop sampling every frame
for 5 seconds, returning aggregate counts only.

One correction from the previous attempt's setup: the placement script this time did not re-aim the
camera before the first `keyDown`, and the first ~1 second of holding `W` walked the character **along**
the doorway (world `-Z`, the "along" axis) rather than **into** it, because the camera was still facing
whatever direction it had been left in. This was caught by checking `Humanoid.MoveDirection` and
`Position` on the client before committing to the 5-second server sample (`MoveDirection` read `0,0,-1`,
`Position.Z` had drifted from `-235.6` to `-239.7`) — the key was released, the camera was explicitly
re-aimed with `CameraType = Scriptable` before restoring `Custom`, and the approach was redone. Recorded
because it is a real way to get a false read in either direction: aim the camera at the wrong axis and
"holding into a live barrier" is quietly testing "sliding along" instead.

## Condition (a): holding into a live barrier, settled inside the margin — RESOLVED

```
totalFrames = 300              (full 5.0 seconds at 60fps)
nonZeroMoveDirFrames = 0
maxMagnitude = 0
nonZeroWhileNotDisplacingFrames = 0
startPos = (36.5006, 2.9961, -235.6013)
endPos   = (36.5006, 2.9961, -235.6013)   -- byte-identical to startPos across all 300 frames
garlicAliveAtEnd = true                   -- the barrier survived the ENTIRE sample; this is not an
                                             absence-of-barrier false negative
```

**Zero non-zero `MoveDirection` frames out of 300, over a full 5 seconds, with the barrier confirmed
alive at both ends of the sample and the position frozen to the byte across every single frame.** This
is the frame-accurate closure the discrete reads in Addendum 3 could not provide on their own — every
frame in the window, not roughly three per second, shows the suppressed value.

Combined with condition (b)'s prior result (`artifacts/frame-accurate-oracle.md`: 300/300 frames, 0
non-zero, voluntarily still), **conditions (a) and (b) are now both closed at full frame resolution and
are identical: 0 out of 300.**

## Condition (c): the approach — attempted, not captured

Reused the same live barrier (still alive, `garlicAliveAtEnd = true`), repositioned to `X = 48`
(12.35 studs from the plane, well outside the 3.5-stud margin), re-aimed the camera, pressed `W`, and
immediately started a second 5-second frame sampler intended to catch the transition from "outside the
margin, walking freely" to "inside the margin, suppressed."

It did not catch the transition — it caught the *already-settled* state a second time:

```
totalFrames = 300, nonZeroMoveDirFrames = 0, startPos = endPos = (38.399, ..., -235.601)
```

`X = 38.399` is already inside the margin (`38.399 - 35.65 = 2.75 < 3.5`), and `startPos` equals
`endPos`, meaning the character had already walked the 9.6 studs from `X = 48` to `X = 38.4` and come to
rest **before this sampling script began running** — the entire approach (roughly 9.6 studs at 16
studs/s, under 0.6 seconds of in-game time) happened inside the real-world gap between issuing `keyDown`
and this session dispatching the next tool call. That gap has consistently been longer than 0.6 seconds
throughout this run, so the transition window — which is only ever a fraction of a second wide — was not
observable through this session's separate-tool-call architecture, independent of `GarlicDuration`.

This is not concerning on its own terms: it is a second, redundant confirmation that the settled state is
clean (0/300 again), just not the specific transition-frame data condition (c) asked for. Per the
coordinator's framing, (c) was explicitly lower priority than (a) and (b), both of which are now closed.

## Bottom line

| Condition | Result | Resolution |
| --- | --- | --- |
| (b) voluntarily still | 0/300 non-zero frames | Closed (prior artifact) |
| (a) holding into a live barrier, settled | 0/300 non-zero frames | **Closed, this artifact** |
| (c) the approach transition specifically | not captured | Attempted once; the transition window (well under 1 second) is narrower than this session could reliably observe via separate tool calls, independent of `GarlicDuration` |

**The redesign is silent at full frame resolution in steady state.** Addendum 3's six clean discrete
reads were not a coincidence of sampling timing — every one of 300 consecutive frames, sampled directly
rather than inferred, agrees with them.
