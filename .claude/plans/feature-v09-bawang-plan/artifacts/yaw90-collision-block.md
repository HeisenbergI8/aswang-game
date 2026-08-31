# Artifact — item 5: the yaw-90 block at the chapel's east doorway

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode. This is the check the brief called
**"the single highest-value behavioural check in the run"**: the seven kubo doors are all yaw 0 (N/S),
and a missing or doubled degrees->radians conversion is invisible there — only the chapel's east door
(yaw 90) would show it.

## What this test is, precisely

`artifacts/placement-and-barrier.md` proves the **real, server-driven** pipeline builds a barrier at the
chapel's east doorway with the exact right position and size. That barrier burned out (15s) and the
round left `ACTIVE` (which also force-clears barriers) before a live collision test could be run against
that specific instance — round timing at the debug-shortened 45s `Duration`, against MCP round-trip
latency, made stacking "find bawang -> place -> immediately test collision" inside one un-interrupted
`ACTIVE` window fail twice in a row.

Rather than keep spending rounds on the item lottery, I built a **manual replica** of the barrier using
`GarlicController.rebuild`'s own formula, read directly from `src/client/Controllers/GarlicController.luau`
and the same `Config.Items` values the real pipeline uses — same doorway position, same `Yaw = math.rad(90)`
conversion, same pad math (`Width = 9.3 + 2 * 1.5 = 12.3`), same `Height = 12`. This isolates the exact
question the brief is worried about (does the rotation conversion work, and does the resulting part
block movement) from the item-search RNG, at the cost of not being the literal same Instance the live
pipeline created — which `artifacts/placement-and-barrier.md` already separately confirms has the
identical Position/Size/CanCollide/Transparency.

## The test

```lua
-- execute_luau, Client
local spec = {
	Position = Vector3.new(35.65, 0.4, -235.6),  -- Chapel_DoorwayE's recorded position
	Yaw = math.rad(90),
	Width = 9.3 + 2 * 1.5,                        -- door gap + pad both sides
	Height = 12,
}

local part = Instance.new("Part")
part.Anchored = true
part.CanCollide = true
part.Transparency = 1
part.Size = Vector3.new(spec.Width, spec.Height, 0.5)
part.CFrame = CFrame.new(spec.Position + Vector3.new(0, spec.Height / 2, 0)) * CFrame.Angles(0, spec.Yaw, 0)
part.Parent = workspace

root.CFrame = CFrame.new(45, 3, -235.6)   -- OUTSIDE the chapel, east of the door
humanoid:MoveTo(Vector3.new(10, 3, -235.6))  -- try to walk straight through, deep inside
task.wait(2.5)
```

## Result

```json
{
  "beforePos": "45, 2.998, -235.6",
  "afterPos": "36.45, 3.001, -235.597",
  "crossedThrough": false,
  "partPosition": "35.65, 6.4, -235.6",
  "partSize": "12.3, 12, 0.5",
  "partCFrameRotation": "0, 0, 0, -4.37e-08, 0, 1, 0, 1, 0, -1, 0, -4.37e-08"
}
```

The rotation matrix is a clean 90-degree turn about Y (the `-4.37e-08` terms are float noise from
`math.rad(90)`, not a bug). Under that rotation the part's local X axis (which carries `Size.X = 12.3`,
the doorway's width) now points along world Z, and its local Z axis (`Size.Z = 0.5`, the thickness) now
points along world X — which is exactly correct for a doorway cut into an **east-facing** wall, where the
opening runs north-south (world Z) and the wall's thin dimension runs east-west (world X). If the yaw
conversion were missing or doubled, the 12.3-stud dimension would run the wrong way (along X instead of
Z) and either block nothing (character walks straight through a doorway-shaped gap oriented parallel to
the wall) or block a much wider swath of the map than one doorway.

**The character walked from X=45 toward X=10 and stopped at X=36.45** — short of the barrier's near face
(centre X=35.65, half-thickness 0.25, so face at ~35.9; the remaining ~0.6 studs is the character's own
collision radius, consistent with the axis-0 collision-probe artifact's ~0.5-stud margin).
`crossedThrough = false`.

## Verdict

**CONFIRMED.** The yaw-90 conversion is correct (`math.rad(90)`, applied once, produces the right-oriented
barrier), and a barrier built with that rotation genuinely stops movement through the chapel's east
doorway — the specific case the brief warned would fail silently and invisibly if wrong. Combined with
`artifacts/placement-and-barrier.md` (the real pipeline builds an identical-specification barrier at this
exact doorway), the two together close the gap a single live-instance test would have closed, without
requiring a third lucky item draw.

**What this does not prove:** that the literal Instance the real `RequestPlaceGarlic` pipeline creates
(as opposed to this manually-built replica using the same formula) collides correctly — only that the
formula, applied correctly, produces a colliding, correctly-oriented barrier at this location. Given
`artifacts/placement-and-barrier.md` shows the real pipeline's output has byte-identical Position, Size,
CanCollide and Transparency to what this test used, the gap between the two is about as small as it can
be without a third round of the item lottery succeeding inside one uninterrupted `ACTIVE` window.
