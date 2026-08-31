# Artifact — Phase 1, Step 1.6: the barrio builder re-run and the nine doorways

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, place `aswang.rbxl`. Rojo blessed
(`npm run rojo:status` verdict `ok` at task start). Builder re-run in **Edit mode** via the
`tools/greybox` HTTP-serve pattern documented in `tools/greybox/README.md`:

```
python3 -m http.server 8731 --bind 127.0.0.1 --directory tools/greybox
```

```lua
-- execute_luau, Edit mode
game:GetService("HttpService").HttpEnabled = true
local src = game:GetService("HttpService"):GetAsync("http://127.0.0.1:8731/barrio.luau?v=v09test1")
local fn = assert((loadstring or load)(src, "barrio"))
fn()
```

## 1. Why the re-run was necessary

The console's scrollback held an OLDER `[barrio] built —` line from before this task started:

```
[barrio] built — 15 SearchContainer, 6 SaltSpawn, 18 AmbientSpawn, 2 TrialOnly TaskPoint, 1 TrialSpawn, 1 TrialChase, 1611 instances, scale 1.55
```

1611 instances, with no Doorway pads possible at that count (the plan's own math: +9 pads pushes the
total to 1620). This confirmed the place file predated the V09 builder changes and had to be rebuilt
before anything doorway-shaped could be observed.

## 2. The re-run's receipt

```
[barrio] built — 15 SearchContainer, 6 SaltSpawn, 18 AmbientSpawn, 2 TrialOnly TaskPoint, 1 TrialSpawn, 1 TrialChase, 1620 instances, scale 1.55
[barrio] dressing — 1039 props, 0 colliders, 0 own lights; 11 lights in the barrio, 11 tagged MapLight
[barrio] instances: 1620 (band 1450-1750)
```

**1611 -> 1620, exactly +9.** No `Doorway parts, expected 9` assertion failure was thrown — the script
ran to completion and returned normally (`execute_luau` returned `"builder run submitted"` with no
error). The receipt's own `assert(count("Doorway") == 9, ...)` is silent on success (it only prints on
failure), so the absence of that line, combined with the +9 instance delta and the direct tag query
below, is the evidence it passed.

## 3. Direct confirmation — every doorway pad, queried by tag

```lua
local CollectionService = game:GetService("CollectionService")
local doors = CollectionService:GetTagged("Doorway")
-- ... count and dump each
```

Result — **9 pads**, exactly as the receipt asserts:

| Name | Position | Yaw | Width |
| --- | --- | --- | --- |
| Kubo_NW_DoorwayS | (-120.9, 0.4, -105.4) | 0 | 9.3 |
| Chapel_DoorwayS | (0, 0.4, -207.7) | 0 | 9.3 |
| Chapel_DoorwayE | (35.65, 0.4, -235.6) | 90 | 9.3 |
| Kubo_NE_DoorwayW | (102.3, 0.4, -120.9) | 90 | 9.3 |
| Kubo_SW_DoorwayN | (-120.9, 0.4, 105.4) | 0 | 9.3 |
| Kubo_E_DoorwayW | (226.3, 0.4, -46.5) | 90 | 9.3 |
| Kubo_N_DoorwayS | (54.25, 0.4, -100.75) | 0 | 9.3 |
| Kubo_W_DoorwayE | (-226.3, 0.4, 62) | 90 | 9.3 |
| Kubo_SE_DoorwayN | (120.9, 0.4, 105.4) | 0 | 9.3 |

All widths are `9.3` = `6 * SCALE` (`SCALE` = 1.55) as the plan requires, never a bare `6`. Both yaw
values are represented: 0 (five kubo doors + chapel south) and 90 (chapel east + three kubo E/W doors),
which matters directly for item 5 below.

## 4. Geometric placement check — does a pad sit in an actual doorway?

`inspect_instance` on `Workspace.Barrio.Chapel.Chapel_WallE1` and `Chapel_WallE2` (the two wall
segments either side of the chapel's east door):

```
Chapel_WallE1: Position.Z = -251.875, Size.Z = 23.25  -> spans Z [-263.5, -240.25]
Chapel_WallE2: Position.Z = -219.325, Size.Z = 23.25  -> spans Z [-230.95, -207.7]
Gap between the two walls: Z [-240.25, -230.95], width 9.3, centre Z = -235.6
Chapel_DoorwayE pad:       Position = (35.65, 0.4, -235.6), Width attribute = 9.3
```

**The pad's Z-position (-235.6) is exactly the gap's centre, and its Width attribute (9.3) exactly
equals the gap's width.** This is not a screenshot-level "looks about right" — it is the pad's recorded
position and the wall geometry's recorded bounds agreeing to the fifth decimal in the tool's own float
output. `building()`'s half-extents (`hw = w/2`, `hd = d/2`) are confirmed correct by this measurement,
settling the plan's one flagged open question from actual geometry rather than from re-reading source.

A screen capture from (50, 12, -235.6) looking at (35.65, 6, -235.6) — the chapel's east doorway from
outside — shows a clean gap in the wall framing the interior (recorded in the session transcript as
`ScreenCapture v09_doorway_chapel_east`; the image itself is not saved to a file this environment can
write to disk, so the measurement above is the citable artifact for this claim).

## Verdict

**CONFIRMED.** The builder was re-run, produced exactly 9 `Doorway` pads, the assertion passed (no
failure text, and the direct tag query independently confirms the count), and the chapel's east pad is
proven — by wall-gap arithmetic on the live instances, not by inference from source — to sit exactly in
the doorway opening.
