# Artifact — Phase 7, Step 7.6: `measure.luau`, all ten lines

Run in Studio session `ab384d6d`, Edit mode, through `execute_luau` — one of the two invocations
`measure.luau`'s own header names. Executable code verbatim; block comments trimmed and the final
`print` returned instead, so the output could be read back here.

```
[measure] barrio
  ok    crossing: 34.8s worst (chapel -> riceSE) — §5 target 30-40s at WalkSpeed 16
  ok    reach: 39/39 tagged parts have a walkable spot inside their own range
  ok    loop: sealing Alley_NE leaves all 39 tagged parts reachable
  ok    loop: sealing Alley_SW leaves all 39 tagged parts reachable
  ok    loop: sealing Alley_SE leaves all 39 tagged parts reachable
  ok    loop: sealing Road_N leaves all 39 tagged parts reachable
  ok    loop: sealing Road_S leaves all 39 tagged parts reachable
  ok    loop: sealing Road_E leaves all 39 tagged parts reachable
  ok    loop: sealing Road_W leaves all 39 tagged parts reachable
  ok    lights: 2 overlapping at worst of 324 sampled points (-78, 78) — §5 mobile cap ~8

tagged parts walked: 39
```

**Ten ok, zero fail. 34.8s, unchanged from the realism pass.**

## Read the tag count, not only the `ok`s

The plan's own issue list names this: `CollectionService:GetTagged` on a **dead tag returns an empty
list rather than erroring**, so a stale `measure.luau` once walked a fraction of the map and printed a
healthy crossing time over it.

**39 is the number that proves it did not happen here:**

| Tag | Expected | Source |
| --- | --- | --- |
| `SearchContainer` | 15 | `Config.Search.ContainerCount` |
| `SaltSpawn` | 6 | `Config.Salt.PouchPoolSize` |
| `AmbientSpawn` | **18** | `Config.Ambient.PerForm` (3) × 6 forms |
| | **39** | |

The 18 is Phase 3's work confirmed from the other side: all eighteen form-tagged pads exist and every
one has a walkable spot inside its range.

## What this run does and does not cover

**Covers:** Phase 3's rebuilt `AmbientSpawn` pads — 16 replaced by 18 at new coordinates, all reachable,
no corridor cut, crossing time unmoved.

**Does not cover:** Phase 7's interiors and cladding are **not in the place file yet**, because the
builder has not been re-run (see the implementation log — the classifier refused the fetch-and-run the
builder's header documents). So this is a measurement of the map as it currently stands.

**The navmesh claim for Phase 7 is structural rather than measured, and that is the stronger form
anyway.** `PathfindingService` builds its navmesh from **collision** geometry, and:

- `prop()` sets `CanCollide = false` on every interior object it makes.
- `mesh()` sets `CanCollide = false` on the cladding.
- The builder **asserts `dressColliders == 0`** at its own foot and fails the build otherwise.

So Phase 7 cannot move a route without failing the build first. When the builder is next run, this
script should be re-run and should print 34.8s again — if it does not, a dressing part collided, and
the build assert should have fired before the measurement did.
