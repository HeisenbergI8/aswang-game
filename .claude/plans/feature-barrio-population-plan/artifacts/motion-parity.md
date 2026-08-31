# Artifact — Phase 4: one motion driver, measured

Studio session `ab384d6d`, Play mode, 18 rigs, sampled per Heartbeat.

## The bug runtime found that the suite could not

`stepEntity`'s first version took a stationary rig's base orientation from `model:GetPivot()` — which
**already contained the previous frame's sway**. So the roll compounded every Heartbeat:

```
Ambient_CAT_1        max tilt=4.92 deg   roll span over 4s = 359.93 deg
Ambient_GOAT_10      max tilt=5.98 deg   roll span over 4s = 359.96 deg
...
worst tilt 5.98 deg  vs Config.Ambient.SwayDegrees = 4
```

A still animal was slowly **rolling onto its side**, and the 4-degree cap was being exceeded by 50%.

`tests/ambient-motion.test.luau` is green over this, and correctly so — the module is pure and its
sway is bounded. The defect was in how the service *composed* that output, frame over frame. No pure
test can see an accumulator in its caller.

**Fixed** by storing a rotation-only base per index (`facings`), written only when the rig actually
turns, and composing `position → base → sway` from scratch each frame.

## After the fix

```
Ambient_CAT_1        tilt<=2.50 deg  travelled  18.19 studs  MOVING
Ambient_DOG_5        tilt<=2.50 deg  travelled  14.22 studs  MOVING
Ambient_GOAT_10      tilt<=2.50 deg  travelled   4.21 studs  MOVING
Ambient_VILLAGER_18  tilt<=2.50 deg  travelled   5.40 studs  MOVING
... all 18 identical ...

worst tilt 2.50 deg  vs Config.Ambient.SwayDegrees = 4
```

**2.50 degrees, uniform across all eighteen.** No accumulation, comfortably inside the cap.

## No rig is frozen — the property the whole phase is for

An earlier 4-second sample, classifying by movement:

```
rigs with NO vertical motion at all: 0 of 18   (BobStuds 0.12 -> max span 0.24)

Ambient_CAT_1        bob span=0.1720 studs   still
Ambient_CAT_3        bob span=0.2416 studs   still
Ambient_PIG_9        bob span=0.2113 studs   still
Ambient_VILLAGER_16  bob span=0.2353 studs   still
```

Still rigs sit at 0.16–0.25 studs of vertical span against a 0.24 theoretical maximum. **A stationary
animal still breathes**, which is the case that matters: a hiding player stands still, and a
camouflaged rig that froze while its neighbours breathed would be a free answer.

## The tuning fault the suite caught before runtime

`amplitudeFor`'s first version used `half = 1 / BobHz` — an inverse **frequency** used as a **speed**,
numerically 0.71 studs/s. The continuity assertion failed:

```
FAIL  amplitude does not jump between 0 and 0.1 — 0.25 -> 0.342
```

The function was continuous; its knee was in the wrong place. At 0.71, a rig ambling at
`WanderSpeed = 4` already sat at 85% amplitude and a sprinting monster looked barely different from a
strolling pig — **§4.5's one licensed tell, flattened, with the analyzer perfectly happy**. The knee is
now `Config.Ambient.MotionKneeStuds = 4`, tracking `WanderSpeed`.

## Known and carried forward — vertical drift while travelling

```
Ambient_VILLAGER_16  clearance -0.427 .. +1.577 studs
Ambient_PIG_8        clearance -0.499 .. +1.561 studs
worst deviation from ground: +1.577 studs
```

A rig's Y is interpolated **linearly** between two endpoints that are each ground-correct, so crossing
raised ground it drifts up to ~1.5 studs high and ~0.5 low before arriving.

**This is not a secrecy leak.** Free and claimed rigs run the same interpolation in the same function,
so there is no difference between them to read — which is exactly what Phase 4 was built to guarantee.
It is a polish defect, bounded by how uneven this map is.

**Not fixed here, deliberately.** The obvious fix — re-seat Y on the ground beneath the rig each frame
— would raycast from a claimed rig's position straight through **the monster's own character**, and
`stepEntity` has no handle on which character to exclude. Doing it properly means threading that
through, which is a change to the puppet contract rather than to the motion. Filed rather than rushed.

## What this does NOT prove

Both rigs sampled here are **free**. A claimed rig could not be produced: `ClaimSlot` is unreachable
through `execute_luau` (fresh module, empty roster) and a real camouflage needs a reveal and a second
player. Parity therefore rests on the two paths **provably calling the same function** — one
`stepEntity`, one `PivotTo`, `AmbientService.luau` — plus `tests/ambient-motion.test.luau`'s 487
assertions on that function's totality and continuity.
