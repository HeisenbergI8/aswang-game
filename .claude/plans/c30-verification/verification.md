# C30 — Map art dressing · verification

**Chunk** C30 (BUILD-PLAN §7, Track D) · **Tier** Medium · **Date** 2026-08-19
**Studio** `aswang.rbxl`, Edit mode · **Evidence** `artifacts/build-receipt-and-measure.txt`

> C30's brief: *"Now dress the greybox — free Creator Store assets and parts. **Do not change the
> layout**; it passed GATE 1 and the layout is the thing that was validated."*
> **Done:** the Barrio reads as a Filipino village at night; crossing time unchanged; FPS unchanged.
> **Verify:** re-measure crossing time and phone FPS — both must match C17 and C27. Publish after.

## The one thing to know before reading this

**GATE 1 has not happened.** C30's brief says the layout "passed GATE 1", and it has not — the M5
recording sheet (`docs/playtests/2026-08-18-m5.md`, committed 25a6f1d) is blank. The user chose to
defer the playtest and continue building; this chunk was done under that instruction.

Nothing here changes the layout, so if M5 sends the layout back for changes, the dressing follows the
geometry it is attached to rather than blocking that change. That was the reason to dress **through
the generator** rather than by hand in Studio.

## How it was built, and why that decision came first

`tools/greybox/README.md` is explicit: *"If you change the map by hand in Studio — fine, but the change
lives only in the place file, and the next `barrio.luau` run destroys it."*

So the dressing is **859 parts added to `barrio.luau`**, not placed in Studio. It is diffable,
idempotent, and survives the next re-run. No Creator Store asset was inserted: everything is stock
parts and stock materials, which also means nothing here can be moderated away later.

## The two rules that make the done condition true by construction

| Rule | Why it is a rule and not a check |
| --- | --- |
| **Nothing in `Dressing` collides** | PathfindingService builds its navmesh from *collision* geometry. A non-collidable prop cannot move a route, so the crossing time cannot move. The re-measure is a confirmation, not a discovery |
| **`Dressing` adds no dynamic light** | Everything that reads as lit — capiz windows, fiesta bulbs — is `Enum.Material.Neon`, which is emissive shading and costs no light slot. `CastShadow = false` on all 859 for the same reason |

Both are **asserted in the generator's own receipt**, so the script aborts rather than shipping a
violation. A third assertion pins every barrio light as `MapLight`-tagged.

## Answers

| Question | Result | Evidence |
| --- | --- | --- |
| 1. Crossing time unchanged? | **Unchanged — identical, not close.** `34.8s worst (chapel -> riceSE)`. C17's `verification.md:138` records `34.8s worst crossing` for the greybox | `artifacts/build-receipt-and-measure.txt`, MEASURE section |
| 2. Layout unchanged? | **Yes.** No coordinate, road, building or anchor moved. Receipt: `12 TaskPoint (+2 TrialOnly), 4 FetchSource, 6 SaltSpawn, 1 EscapeGate, 1 TrialSpawn, 1 TrialChase` — every contract in `barrio.luau`'s header | same, BUILD RECEIPT |
| 3. Loops still hold? | **Yes.** All seven corridors sealed one at a time; every one leaves all 23 tagged parts reachable | same, MEASURE |
| 4. Light budget unchanged? | **Yes.** `0 own lights` from the dressing; `2 overlapping at worst of 324 sampled points` against §5's ~8 cap. That is C28's number, re-measured | same |
| 5. Does it read as a Filipino barrio at night? | **Judgement, and mine is yes** — see the caveat below | 4 screenshots taken in-session |

### On question 5, honestly

I looked at it in Studio at `ClockTime = 0` and it reads: power-post silhouettes with drooping wires,
lit capiz windows that make a dark block read as an inhabited house, fiesta bulbs strung over the
plaza, a lit chapel doorway down a foggy road. §5's claim that darkness and fog hide low-poly geometry
is doing exactly the work it promised.

**But "reads as a Filipino village" is a human judgement and I am not the human.** The screenshots are
in this session's transcript, not saved as files — `screen_capture` returns image data and does not
write to disk, and no playtester ran (the user deferred testing). Treat question 5 as *unverified by
artifact* and look at it yourself in Studio.

I also inspected it under temporary daylight, which is how the defects below were found; darkness
hides construction errors as effectively as it hides polygon counts.

## Defects found and fixed during this chunk

Three were pre-existing and would not have been found without doing this work.

| # | Defect | Severity | Status |
| --- | --- | --- | --- |
| 1 | **Two props stood on salt spawns.** `Wash_NE_PoleB` 3.1 studs from `SaltSpawn_KuboNE`; four 9-stud `Banana4` leaves over `SaltSpawn_AlleySW` | **High** — salt is §4.6's only counterplay; a hidden pouch is a corner of the map with none | **Fixed.** Both moved; sweep now reports 0. Introduced by this chunk |
| 2 | **`barrio.luau` aborted before its own receipt.** `workspace.StreamingTargetRadius` has left the scriptable API and raises "not a valid member" — it was the last statement before the receipt, so the barrio built correctly and then the script died one line before saying so | **Medium** — reads as "the build failed" when nothing failed | **Fixed.** Wrapped in the same `pcall`-and-warn idiom the file already uses for `Lighting.Technology`. **Pre-existing** |
| 3 | **`MapLight` was tagged 0 times in the place.** 14 lights existed, none tagged, so C27's `PerformanceController` culler had nothing to cull and every lantern stayed lit regardless of `MaxVisibleLights` | **Medium** — silent overspend of the mobile light budget | **Fixed** by re-running the generator, which tags all 14. **Pre-existing**; the place file predated the tagging |
| 4 | **`measure.luau` cried wolf on every run since C21.** It collected the Solo Trial's two `TaskPoint`-tagged practice points without the `TrialOnly` exclusion `TaskService.discoverPool` makes. They are sealed in a corner reachable only by teleport, so 1 reach failure and 7 loop failures were reported on a correct map | **Medium** — eight red lines that mean nothing, on a report whose value is that a red line means something | **Fixed.** `measure.luau` now skips `TrialOnly`. **Pre-existing** |
| 5 | **Roblox's stock SpawnLocation decal** sat in the plaza — a 24-stud studio logo, the most "unfinished Roblox place" thing in any screenshot | Low | **Fixed.** Sunk flush and made transparent. It still exists and still collides, because `RoundService` drives `LoadCharacterAsync` and needs it |

## Not verified

- **FPS on a real phone.** C30's verify line asks for it and it needs a physical device. Studio's
  frame rate is not evidence. The *inputs* to FPS are checked (0 new lights, 0 new shadow casters,
  0 new colliders, 859 parts all `CanQuery = false`), but the number itself is unmeasured.
- **That it reads as a Filipino barrio.** Question 5 above — a human call, no artifact.
- **Anything in a running round.** No play session; the map was built and measured in Edit mode.
- **`Lighting.Technology = Future`** could not be set from the MCP script context (`lacking capability
  RobloxScript`) and warns on every run. Unchanged from C17; set by hand if it is not already Future.

## Manual steps this chunk cannot do

1. **Publish.** File → Publish to Roblox. The place file is gitignored and Roblox's cloud version
   history is its only backup — 859 new parts exist nowhere else. C30's verify line says "Publish
   after" for exactly this reason.
2. **Set the two streaming radii by hand** on Workspace: `StreamingTargetRadius = 341`,
   `StreamingMinRadius = 170`. No longer scriptable; the generator warns with the numbers each run.
3. **Confirm `Lighting.Technology = Future`.**
