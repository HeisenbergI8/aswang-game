# Artifact — Phase 8: the population pass, budgeted

## The budget table, with what is measured and what is computed marked as such

| | Before (measured, live place) | After | Ceiling | How |
| --- | --- | --- | --- | --- |
| Instances in `workspace.Barrio` | **1127** | ~1433 | 1250–1450 | before is measured; after is computed |
| `PointLight` | **14** | 11 | ~8 visible | 9 lit lanterns + trial corner + chapel |
| Dressing colliders | **0** | 0 | 0 | build-failing assert |
| Dressing own lights | **0** | 0 | 0 | build-failing assert |
| Prop mesh triangles | 21,000 | 21,000 | 27,000 | `barrio-assets`, unchanged |
| **Rig mesh triangles drawn** | *uncounted* | **23,400** | 27,000 | `barrio-assets`, counted for the first time |
| Crossing time | **34.8s** | 34.8s | 30–40s | measured; after is structural (see below) |

### Where ~1377 comes from

Computed, not guessed, from the 1127 measured in the live place:

```
1127   measured in workspace.Barrio before this pass
+191   seven kubo interiors (2 sparse @19, 4 full @29, 1 rich @37)
  +5   kubo shells, 2 -> 7 (cladding all seven instead of the two sealed ones)
 +12   one bracket arm per lantern
 +45   eighteen territory props
  -3   PointLights removed by the three dark lanterns
 +32   guy guards, transformer bushings, tarpaulins, telecom bundle
 +24   kakawate sprout foliage
-----
~1433  inside the 1250-1450 band, with ~17 above and 183 below
```

**The ceiling was not raised to make this fit.** At one sprouting fence post in six the count landed
~1443 — seven parts of margin, too thin for the assert to catch anything. The sprout ratio was cut to
one in eight instead. That ceiling stands in for §5's mobile budget, which nobody has measured on a
phone, and moving it to accommodate art would trade an untested limit for a guess.

**The band is a band, not a maximum**, and the floor is the half that matters. The realism pass's
Phase 7 deleted the fence runs, the banana table and the scarecrow loop by miscounting `end` lines,
and **the instance count went down — which was that phase's goal, so the loss read as the saving
working.** Every gate was green. It was caught by hand-counting MeshParts in the live map.

## `measure.luau` — ten of ten

```
  ok    crossing: 34.8s worst (chapel -> riceSE) — §5 target 30-40s at WalkSpeed 16
  ok    reach: 39/39 tagged parts have a walkable spot inside their own range
  ok    loop: sealing Alley_NE / Alley_SW / Alley_SE / Road_N / Road_S / Road_E / Road_W — all ok
  ok    lights: 2 overlapping at worst of 324 sampled points (-78, 78) — §5 mobile cap ~8
```

**39 tagged parts** = 15 containers + 6 salt + **18 ambient**, which is what proves the dead-tag false
green did not fire. Full output in `artifacts/crossing-after-interiors.md`.

## Two numbers this artifact does NOT have, stated plainly

**1. FPS on a real phone.** §5's budget is specified in frames on a phone and nothing in this session
could measure that. The realism pass finished without it too. It remains the one number that would
actually settle whether the mobile budget is met, and it needs a person with a handset.

**2. The post-build instance count and crossing time.** The builder has not been re-run, so ~1377 is
computed and 34.8s describes the map as it stands today rather than the map this plan describes.

**The navmesh claim is structural rather than measured, which is the stronger form:** `prop()` and
`mesh()` both force `CanCollide = false`, and the builder asserts `dressColliders == 0` at its foot.
Phase 7 and 8 cannot move a route without failing the build first.

## Step 8.6 — publish, and it is not done

`File → Publish to Roblox As…`. **Neither script can do it**, and the place file is the only copy of
the map: the six rig meshes, the re-generated kubo shell, eighteen re-sited spawn pads and everything
the builder is about to add exist in exactly one binary that is not in git.

This artifact deliberately carries no check for it. No command can prove a human published, and
inventing one would be the worst possible false green — the thing it would falsely certify is the
backup.

## What the user has to do, in order

1. **Run the builder.** Open `tools/greybox/barrio.luau`, paste it into Studio's command bar in
   **Edit** mode, run it. It is idempotent — it destroys `workspace.Barrio` and rebuilds. Watch for:
   - `[barrio] instances: N (band 1250-1450)` — the new assert. If it fires low, something was deleted.
   - The `dressColliders == 0` and `mapLights == totalLights` asserts.
2. **Re-run `measure.luau`** the same way. Expect 34.8s and 39/39 again; a moved crossing time means a
   dressing part collided.
3. **Publish.**
