# Research 01 — the bahay kubo

Feeds **Step 4.3** (rebuild `Kubo_NW` as the template) and **Step 7.1** (the six remaining houses).

**How to read the confidence marks.** Every fact below is marked, because several of the most
visually important ones turned out to be unsourceable and a plan that hides that will get them wrong
with confidence. ✅ authoritative · ⚠️ secondary or commercially motivated · ❌ could not source.

---

## Structure and framing ✅

The frame is named and the names describe the build order: **haligi** (vertical posts) → **yawi**
(horizontal beams) → **patukuran** (secondary beams) → **soleras** (bamboo floor joists) → bamboo slat
floor.

**The one hard number worth building to: soleras are laid 30–38 cm (12–15 in) apart.**

> **NOTE — this is the rhythm of the silong ceiling, and the silong is the part a player looks up into.**
> At this game's scale (1 stud ≈ 0.28 m at `SCALE = 1.55`), 30–38 cm is roughly **1.1–1.4 studs**. That
> is too fine to model as individual joists without spending 20+ parts per house. **Do not model the
> joists.** Use `BarrioBamboo` on the floor underside and let the material's grain carry it — this is
> exactly the case the asset-pipeline skill describes, where a correct material beats geometry.

The vertical division is explicit in the sources and is a three-part silhouette: **silong** (undercroft)
/ living floor / **bubungan** (roof space).

## The silong ✅ — and it is a gameplay volume, not decoration

Sourced uses: storing harvested crops and tools, and housing livestock — chickens, pigs, goats.

**Enclosed by loosely-spaced bamboo or wooden latticework, not a solid wall.** So the silong reads as a
shadowed, semi-transparent cage.

> **IMPORTANT — this is the single most valuable finding in this document for *this* game.** A slatted,
> shadowed undercroft is a real hiding volume with partial sightlines, which is §5's sightline rule
> ("fear comes from *partial* information") expressed as architecture rather than as fog. It is also
> where §5 says livestock live — and §4.5's camouflage needs pigs to be somewhere plausible.
>
> **QUESTION for the user:** should the silong be *enterable*? Enterable means collidable geometry and a
> navmesh change, which Step 4.3 refuses on the layout rule. Non-enterable means it is a lit-through
> screen, which is still worth building. **This plan assumes non-enterable.** Revisit at V16 if hiding
> turns out to be too weak.

## Stilt height ⚠️

**1–2 m** average floor height. Source is ArchitectureCourses.org — an educational-content site, not a
primary architectural source.

**Use 1.2–1.5 m**, which is ~4.3–5.4 studs at this scale. Step 4.3's diff uses `STILT = 3.2` studs
(≈0.9 m), which is **short against this finding** — raise it toward 4.5 unless the floor-height decision
in Step 4.3 forces otherwise.

## Walls ✅ — three named panel types that look different from each other

| Panel | What it is | Reads as |
| --- | --- | --- |
| **Amakan / sawali** | flattened split bamboo, tight diagonal or herringbone weave | semi-opaque, patterned |
| **Pawid** | thatched panels of cogon grass, anahaw or nipa | fibrous, matches the roof |
| **Sala-sala** | *loosely* woven bamboo lattice | see-through |

Windows are large and operable; ⚠️ one secondary source claims **over 50% of wall area** is openable.

> **NOTE — this is why Step 7.1's per-house variation axis is "wall material mix" rather than colour.**
> Three genuinely different weave densities across seven houses is more convincing than seven tints of
> brown, and `BarrioSawali` plus a second looser variant covers it.
>
> The push-out **tukod** window prop is a strong silhouette feature but the name did not appear in an
> authoritative source — treat as convention.

## Roof ✅ reasoning, ⚠️ angle

Sourced Philippine reasoning: the roof is tall and steeply pitched; the volume lets warm air rise above
the living space; **"the steep pitch allows water to flow down quickly at the height of the monsoon
season"**; and **long eaves give people space to move around the outside of the house when it rains.**

**The overhanging eaves are sourced and are a real silhouette feature: the roof is visually wider than
the floor plate.** The builder's `building()` already does this — `roof` is `w + 4` by `d + 4`. That was
right by accident; keep it and consider widening.

⚠️ **The angle is inferred, not Philippine-sourced.** Thatching-trade sources give **45° minimum, 50°+
preferred**, on the physics that water crosses a non-waterproof surface and must shed before it
penetrates — shallower pitch means longer contact, damp thatch, shorter life. Universal to thatch, but
no Philippine document states a degree figure.

> **Use 45–50° and mark it inferred.** The current roof is a **flat 1-stud slab**, which is not a pitch
> at all — anything in this range is a large improvement, so the uncertainty costs nothing.

## Footprint ⚠️

**30–51 m² (320–550 sq ft)**, rectangular — roughly **5 × 6 m to 6 × 8.5 m**. The raised floor is
normally **a single undivided space**, with an optional small enclosed room (**celda**).

> **IMPORTANT — do not subdivide the interior, and do not shrink the houses to match this.** At
> `SCALE = 1.55`, 6 × 8.5 m is about 21 × 30 studs, which is in the region the greybox already builds.
> More importantly, the interiors hold `SearchContainer` anchors and a player has to walk in, stand at
> one, and stay there for `Config.Search.ProximityStuds`. **Playable clearance beats accurate footprint**
> — and §5's "at least 5 enterable" is the binding requirement, not the square metres.

## Weathering ⚠️ / ❌ — read this before choosing roof colours

⚠️ Natural nipa needs **total replacement every 2–4 years** (or 3–5, depending on the page). **Both
figures come from synthetic-thatch vendors who profit from natural thatch sounding bad.** Directionally
right — a nipa roof is short-lived and frequently patched — but not a citable number.

❌ **"Nipa greys with age" is essentially UNSOURCED.** The only evidence is that synthetic-thatch
manufacturers sell "weathered palm" and "weathered grey" colourways alongside a "new palm" colour. That
is the industry modelling aged thatch as grey — indirect evidence, not a source.

> **IMPORTANT — this changes Step 7.1's stated variation axis.** The plan says to vary roof age from
> "straw-gold" to "grey-brown", and the greying half of that is unsourced.
>
> **The defensible version is better anyway: a real roof is patched in stages, so it is multi-toned —
> fresh brown patches against older material on the SAME roof.** That is sourced (frequent partial
> replacement) and it is a stronger visual: variation *within* each roof rather than *between* houses.
> Build that instead.

✅ Also sourced and free: organic roofs are **"nesting grounds for birds, rats, and termites."** A barrio
horror game can use that; it costs nothing to know.

---

## Sources

- [Nipa hut — Wikipedia](https://en.wikipedia.org/wiki/Nipa_hut) — framing names, soleras spacing, silong
  uses and enclosure, wall panel types, roof rationale and eaves, pest note
- [The Many Styles of Bahay Kubo — ArchitectureCourses.org](https://www.architecturecourses.org/design/many-styles-bahay-kubo-traditional-modern-tropical-homes)
  — stilt height, footprint, single-room plan *(secondary)*
- [Lean Interpretations from Philippine Vernacular Architecture — Lean Urbanism](https://leanurbanism.org/lean-interpretations-from-philippine-vernacular-architecture/)
- [A Beginner's Guide — ThatchingInfo.com](https://thatchinginfo.com/beginners-guide/) ·
  [Tech Specs — McGhee & Co Roof Thatchers](https://www.thatching.com/whenever) — 45°/50° pitch physics
  *(general thatching, NOT Philippine)*
- [Beatles Thatch](https://www.beatlesthatch.com/blog/how-to-use-synthetic-nipa-for-bahay-kubo-roof-replacement_b127) ·
  [A-Thatch](https://www.a-thatch.com/synthetic-nipa-roofing-philippines-investment/) — thatch lifespan
  *(COMMERCIALLY BIASED — vendors of the replacement product)*
