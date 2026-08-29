# Hero mesh shortlist — eight props, and the triangle budget

Input to **Phase 5**. Eight `generate_mesh` calls, eight `ASSETS.Meshes` rows, and a hard ceiling
enforced by `tests/barrio-assets.test.luau`.

---

## The budget, and why it is this shape

| Rule | Value | Source |
| --- | --- | --- |
| Props | **1,500–3,000** triangles | asset-pipeline skill |
| One hero | up to **6,000** | asset-pipeline skill, "a hero object like the chapel" |
| Total added | **≤ 27,000** | 7 × 3,000 + 6,000, enforced by the suite |
| Planned total | **21,500** | leaves room for one regeneration coming back heavy |

**Prompt for the silhouette, not the detail.** The skill is explicit: darkness and fog erase surface
detail and keep outline, so *"tall thin bamboo grove, dense"* beats a photorealistic prompt on cost,
speed, **and** how it reads. Every prompt below is written to that rule.

**Every mesh is non-collidable, without exception.** `mesh()` guarantees it. A MeshPart defaults to a mesh
collision hull, which PathfindingService reads and the crossing time answers for — C30 rule 1 is asserted
at the foot of the builder and this is the easiest way in the whole plan to break it.

**Every mesh REPLACES box props.** A generated tricycle standing next to the six boxes it was meant to
replace is six wasted parts and a doubled silhouette. The `Replaces` column is not documentation — it is
the deletion list, and it is also what lets a moderated-away asset be reverted to boxes.

---

## The eight

### 1. Chapel — the one hero, 6,000 tris

**Replaces:** `Chapel` walls + `Chapel_Steeple` (~6 of 8 parts; the candles light and the cross stay)
**Size:** 24 × 22 × 30 studs

> `small rural Philippine barangay chapel, concrete hollow block walls, steeply pitched corrugated metal
> roof, simple bell tower, plain rectangular plan, weathered and rust-streaked`

Research-03 supports: CHB walls ✅, corrugated GI roof ✅ (cogon-roofed chapels are documented as
*singular*, so metal is right), plain plan ⚠️ convention. **Keep the `Chapel_Candles` PointLight and its
`MapLight` tag exactly where they are** — the builder asserts `mapLights == totalLights` and this mesh
must not bring a light of its own.

### 2. Tricycle — 3,000 tris

**Replaces:** `Tricycle1` and `Tricycle2` bodies (~6 parts each, ×2)
**Size:** 6 × 5 × 9 studs

> `Philippine tricycle, motorcycle with welded steel sidecar, mismatched corrugated metal roof over the
> sidecar, boxy, worn paint`

Research-02 ✅: welded metal pipe/sheet sidecar; **"usually covered, though not always by the same roof
structure"** — the mismatch between bike roof and sidecar roof *is* the silhouette, so the prompt says so.
❌ Route signage is unsourced and unbuildable (no image generation) — omitted rather than faked.

**The tricycle is the correct vehicle for a rural barrio and the jeepney is not** — sourced: tricycles
serve *"narrow roads or barangay pathways where larger vehicles cannot pass."* There is deliberately no
jeepney in this list.

### 3. Sari-sari store front — 2,500 tris

**Replaces:** `Stall_*` counter, roof and tarp (~7 of 10 parts, ×4 reused)
**Size:** 12 × 10 × 8 studs

> `Philippine sari-sari store front, metal barred window grille over a counter, low corrugated roof,
> goods stacked behind the bars, attached to a house wall`

Research-03 ✅: the **metal-barred window is the defining element** and the transaction happens through it.
✅ It is *part of the house*, which the prompt says. **The grille is also built as separate box parts in
Step 6.2** — decide at Phase 5 whether the mesh's grille supersedes them, and delete one or the other.

### 4. Bahay kubo shell — 3,000 tris

**Replaces:** nothing structural — **dressing over the existing `building()` output**
**Size:** 20 × 16 × 20 studs

> `Filipino bahay kubo, bamboo house raised on posts, steeply pitched nipa thatch roof with wide
> overhanging eaves, woven bamboo walls, open slatted undercroft`

**IMPORTANT — this one must NOT replace the collidable walls.** The `building()` walls are what the
navmesh reads; swapping a collidable box wall for a MeshPart changes collision from a box to a mesh hull
and moves the crossing time. This mesh is scenery layered over a structure that stays exactly as it is.
Research-01 ✅ on eaves ("long eaves give people space to move around the outside when it rains") and on
the slatted silong.

### 5. Well head and pump — 2,000 tris

**Replaces:** `Well` ring (10 parts) + `Well_Pump`
**Size:** 8 × 7 × 8 studs

> `village hand water pump on a concrete apron, cast iron pitcher pump, low circular block well ring,
> wet and mossy`

### 6. Banana plant — 1,500 tris

**Replaces:** 12 banana trunks + 48 leaves in `Dressing.Planting` (**60 parts — the largest single saving
in Phase 5**)
**Size:** 7 × 12 × 7 studs

> `banana plant, smooth layered pseudostem, broad drooping leaves **torn into ribbons hanging from the
> midrib**, dwarf backyard variety`

**Research-03 ✅ and this is the finding that makes or breaks the mesh:** *"Leaf blades are often torn by
the wind and hang in ribbons from the midrib."* **An intact banana leaf is wrong for a barrio.** Without
that clause the generator returns a clean botanical-illustration banana that reads as a video-game plant.
Dwarf **Saging Mondo** (2.5–3.5 m) is the sourced backyard variety; at `SCALE = 1.55` that is ~9–12 studs.

### 7. Grave marker — 1,500 tris

**Replaces:** `GraveN_H` + `GraveN_V` (2 parts each, ×8 = 16 parts)
**Size:** 2 × 4 × 1.5 studs

> `Philippine grave marker, painted concrete cross on a low above-ground tomb slab, chalky whitewash
> flaking over older paint, slightly tilted`

**Research-05/03 ✅ confirms the core correction: above-ground painted concrete, not carved granite.** The
**above-ground tomb slab is the biggest silhouette change** and it is sourced. ❌ Moss and tilt are both
unsourced — keep the existing `lean` as convention. ✅ Repainting is annual, so **the eight should vary by
paint freshness, not by age** — fresh white against chalky grey, because faded lettering means "this
family stopped coming."

Lettering (R.I.P., D.O.M., PAX, S.L.N.) is ✅ sourced and ❌ unbuildable — no image generation. Follow Ups.

### 8. Scarecrow — 1,500 tris

**Replaces:** 2 scarecrows in `Dressing.FieldDressing` (~4 parts each)
**Size:** 3 × 8 × 3 studs

> `field scarecrow, crossed bamboo frame, ragged cloth shirt hanging loose, straw hat, thin and tall`

The cheapest scare in the map: a human silhouette at distance in a fog-bound rice field, which §5 calls
"the killing field." Thin and tall is the point — it must be mistakable for a player at 40 studs.

---

## Net part effect

| | Parts |
| --- | --- |
| Removed by replacement | ~45 (banana 60 alone, offset by the kubo shell replacing nothing) |
| Added as MeshParts | 8 |
| **Net** | **≈ −37** |

Phase 5 is one of only two phases that *reduce* part count. That is how Phase 4's +74 gets paid back,
alongside Phase 7's planting reduction.

---

## Two open questions

1. **✅ RESOLVED — `MeshPart.MeshId` is NOT script-writable.** Probed in Edit mode: the assignment
   fails with *"cannot write 'MeshId' (lacking capability NotAccessible)"* and the property stays `""`,
   so the failure is **silent** — an invisible zero-size part rather than an error. The phase now uses
   **`AssetService:CreateMeshPartAsync`**, chosen because a `MeshPart` is the only form that can carry a
   `MaterialVariant` from Phase 3's material library. `Part` + `SpecialMesh` is the proven fallback
   (both `MeshId` and `TextureId` writable, no yield) and costs exactly that: PBR materials, not
   collision fidelity — collision is irrelevant here because every mesh is non-collidable. See Phase 5's
   mechanism section for why template-cloning was rejected.

   **Still to confirm:** the exact `CreateMeshPartAsync` parameter shape in this Studio version. Probe
   before writing the helper; do not assume the options table.

2. **`generate_mesh` returns what it returns.** If a mesh comes back visibly heavier or worse than asked,
   **regenerate rather than raise the ceiling.** The suite catches the number; it cannot catch the look.
