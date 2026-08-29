# Final measurement — the finished barrio

Taken in Edit mode after running `barrio.luau` then `measure.luau` on the completed map.

## The numbers

| Number | Start of plan | Final | Condition | Verdict |
| --- | --- | --- | --- | --- |
| Crossing time | 34.8s | **34.8s** | 30–40s, unchanged | ✅ **identical across all eight phases** |
| `Barrio` instances | 1,155 | **1,133** | ≤ 1,250 | ✅ under, and *below* where it started |
| Parts | 1,098 boxes | **1,045 boxes + 31 MeshParts = 1,076** | — | ✅ −22 net, with far more detail |
| Dressing colliders | 0 | **0** | 0 or the build fails | ✅ asserted by the builder |
| Dressing own lights | 0 | **0** | 0 or the build fails | ✅ asserted by the builder |
| `MapLight` total | 14 | **14** | == total lights in the barrio | ✅ asserted |
| Overlapping lights | 2 | **2** | ≤ ~8 (§5 mobile cap) | ✅ |
| Reachability | 36/37 | **37/37** | all tagged parts | ✅ |
| Loop tests | 7 fail | **7/7 ok** | every corridor | ✅ |
| Generated triangles | 0 | **21,000** | ≤ 27,000 | ✅ |
| **FPS on a real phone** | — | **not taken** | ≥ 30 | ❌ **cannot be taken by an agent** |

**Phase 4 peaked at 1,259 instances — 9 over the ceiling — and Phase 7 repaid it.** The planting
reduction and the mesh replacements together took `Planting` from 456 parts to 253 and removed ~90 box
props, which is why the finished map is smaller than the one this plan started with despite adding
cracks, bench backs, hoop braces, stilts, roof pitches, banderitas triangles, grilles, sachets, tomb
slabs, candles and fifteen container props.

## `measure.luau`, final run

```
ok    crossing: 34.8s worst (chapel -> riceSE) — §5 target 30-40s at WalkSpeed 16
ok    reach: 37/37 tagged parts have a walkable spot inside their own range
ok    loop: sealing Alley_NE / Alley_SW / Alley_SE / Road_N / Road_S / Road_E / Road_W
      each leaves all 37 tagged parts reachable
ok    lights: 2 overlapping at worst of 324 sampled points — §5 mobile cap ~8
```

## Authored lighting, final

```
Brightness 1.00 · Ambient rgb(15,15,22) · OutdoorAmbient rgb(34,30,34)
EnvironmentDiffuseScale 0.12 · EnvironmentSpecularScale 0.28 · FogEnd 341
Atmosphere: Density 0.42 · Color rgb(158,154,156) · Decay rgb(74,68,66) · Glare 0.16 · Haze 2.6
```

Warmed off blue rather than brightened. §5's sightline rule wants partial information, and raising
`Ambient` flattens the map and erases the deep shadow research-04 says is the actual look of a rural
barrio at night. `tests/barrio-lighting.test.luau` pins the ceiling at rgb ≤ 30 per channel so a later
"the map is too dark" edit has to argue with a test.

## What is NOT measured, and cannot be here

**FPS on a physical phone.** It needs `Config.Debug.VerboseLogging` and a real device; no agent in this
pipeline can hold one. §5 calls the mobile budget non-negotiable and 60% of players are on a phone, so
this is the one number in the table that still matters and is still missing. **The proxies are good but
they are proxies:** part count is down, triangles are inside budget, colliders and dressing lights are
zero and asserted, overlapping lights are 2 against a cap of ~8.

**Two Studio settings the builder cannot write**, both warned about on every run:

| Setting | Value | Why it cannot be scripted |
| --- | --- | --- |
| `Lighting.Technology` | `Future` | needs `RobloxScript` — it cannot even be READ from this context |
| `Workspace.StreamingTargetRadius` | `341` | left the scriptable API entirely |
| `Workspace.StreamingMinRadius` | `170` | same |

**`Future` lighting is a §5 requirement, not a nicety.** Every capture in this plan was taken without
it. The map will look materially different — better — once it is on, and the lighting values above were
tuned without being able to see that.

## And the honest limit

None of this says the barrio is *frightening*, or that searching it feels like survival rather than a
chore. That is V16's question and it needs real players. `verify` being green and ten `ok` lines from
`measure.luau` mean the map is correct and affordable, not that it works.
