# Hero zone — Phase 4 approval gate

Captured from the live place in Edit mode after running `barrio.luau` then `measure.luau`.

## The four numbers (Step 4.4)

| Number | Reading | Pass condition | Verdict |
| --- | --- | --- | --- |
| Crossing time | **34.8s** (chapel → riceSE) | 30–40s band, and unchanged from pre-phase | ✅ **identical** to the pre-phase 34.8s |
| Total `Barrio` instances | **1,259** (1,216 parts) | ≤ 1,250 | ⚠️ **9 over** — see below |
| Dressing colliders / own lights | **0 / 0** | 0 / 0 or the build fails | ✅ asserted by the builder |
| FPS on a real phone | **not taken** | ≥ 30 | ❌ **cannot be taken by an agent** |

**The instance overage is 9 and it is scheduled to be repaid.** Phase 4 was always the plan's largest
single budget movement (+102 parts here: 6 cracks, 4 bench backs, 8 hoop braces, 40 banderitas
triangles, 28 stilts, 16 roof pitch panels). The plan's own remedy is Phase 7 reducing `Planting`,
which is 456 parts — 37% of the map — so the headroom exists. **Re-check the receipt at the end of
Phase 7 and treat 1,250 as binding there.** If it is still over, cut the banderitas triangles first:
they are 40 of the 102 and the bulbs already carry that read.

**The FPS number is a real gap, not an oversight.** It needs `Config.Debug.VerboseLogging` and a
physical phone. No agent in this pipeline can hold one. It stays open until a human takes it.

## Screenshots

**These could not be written to files.** `screen_capture` returns an image inline and no tool in this
session persists it to disk — the same limitation C17's verification recorded. They were looked at
directly and are described precisely enough to be re-taken and disagreed with.

| Capture | Camera | What is on screen |
| --- | --- | --- |
| `hero_court_from_plaza` | (0, 6, 34) → (-40, 4, -12) | Night plaza at player eye height. Both hoops read clearly as hoops — pole, backboard, rim — in silhouette. Four banderitas runs cross the frame at visibly UNEVEN heights with warm bulbs, and the dark triangles hang between them as intended. Court paint lines are faintly visible on the slab. Power-line poles recede left and right; the arko frames the right edge; one sari-sari stall is lit warm in the middle distance. Reads as a barrio plaza at night. |
| `hero_kubo_silhouette` | (-60, 8, -80) → (-121, 8, -121) | **The strongest shot of the phase.** `Kubo_NW` at ~40 studs. The pitched roof reads unmistakably as a bahay kubo rather than a shed — a proper ridge with the eave slab under it. Two warm-lit windows, the doorway gap between them, stilts visible at the right-hand corner, a bench in the foreground, the stall behind at left. This is the treatment Phase 7 copies. |
| `hero_container_interior` | (-105, 5, -108) → (-121, 1, -121) | **A failure, and the most useful capture of the four.** Looking into the kubo interior toward `Container_KuboNW_Chest`. The container is **not visible at all** — the frame is black but for one lit window. See below. |

## The three questions

### 1. Does this read as a Philippine barrio, or as a generic village?

**Closer to a barrio than before, and not yet unmistakably one.** The pitched nipa roofline, the
uneven banderitas, the netless bent rims and the tangle of power poles are all specifically Filipino
cues and they land. What is missing is at the material level, and it is missing for a reason recorded
below: `generate_material` is broken in this Studio build, so nothing has the surface detail the plan
budgeted for. The barrio currently reads as *well-composed dark geometry*, which §5 explicitly says is
enough — *"darkness, fog and lighting hide low-poly geometry"* — but it is not "hyper realistic", and
saying otherwise would be false.

### 2. Is the material density right — do twelve variants make one village, or a patchwork?

**Unanswerable as asked, because the twelve variants do not exist.** `generate_material` fails on every
input. The fourteen registry rows resolve to stock `Enum.Material` values only. Density is therefore
*low* rather than patchy — several surfaces that should differ currently do not.

### 3. Is the container obvious at a glance, in the dark, on a phone?

**No. It is not visible at all.** This is a hard fail against §5's "visually obvious as searchable at a
glance, on a phone, in the dark", and it is a **playability** problem rather than an art one: v2.0's
entire loop is searching, and a player standing four studs from a container in an unlit interior cannot
see that it is there.

**The fix is already a planned step** — Step 6.3, "the container pads that are still blue rectangles" —
and the correct mechanism is `Neon`, not a light. The map already asserts zero dressing lights (C30
rule 2) and `PerformanceController` caps `MapLight`; fifteen new PointLights would break both. Neon is
emissive, costs no light slot, and is exactly the trick the banderitas bulbs already use.

## The unresolved conflict, decided and logged

**Stilts vs. the layout rule.** Research-01 wants a raised floor over an open silong; §5 wants the
crossing time unmoved and the container reachable. **The layout rule won.** The posts are decorative
and stand around a floor that stays at ground level, because raising it with collidable walls needs a
ramp, a ramp is a navmesh change, and a navmesh change moves the number §5 measures and would put the
container behind a step. At night, under the roof overhang, the difference is not visible — the
`hero_kubo_silhouette` capture is the evidence that the read survives the compromise.

## What a human still has to decide

1. **Warm vs cool window light.** Research-04 says warm amber is unsourced and CFL/LED prevalence
   argues for cool fluorescent white, which would also contrast against the sodium streetlights
   instead of blending in. **The captures above are all warm** — that is the current state, not a
   decision. My recommendation is cool white for the interiors, warm for the street.
2. **Whether the overall look is worth continuing.** The honest position is in question 1 above.
