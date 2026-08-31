# Artifact — Phase 5: six regenerated rig meshes

Generated in Studio session `ab384d6d` via `generate_mesh`. `generate_material` was not needed —
`generate_mesh` returns a texture with the mesh.

| Form | Mesh | Texture | Tris requested | Generated bounding box |
| --- | --- | --- | --- | --- |
| CAT | `96211506575053` | `130634110713517` | 1200 | 0.46 × 1.20 × 1.22 |
| DOG | `95323271856112` | `80047444313330` | 1400 | 0.74 × 1.90 × 2.14 |
| PIG | `108005880380762` | `120673320204813` | 1400 | 1.18 × 1.80 × 2.73 |
| GOAT | `100545159776343` | `104493613437573` | 1200 | 1.20 × 1.71 × 1.54 |
| CHICKEN | `115234736069936` | `113527179344004` | 800 | 0.61 × 1.10 × 1.23 |
| VILLAGER | `124492172741324` | `119550214494630` | 1800 | 1.42 × 3.64 × 1.20 |

All six succeeded first try. **These ids are the only durable record** — the meshes live in the
gitignored place file, so `git log` will never have them. They are written into
`tools/greybox/barrio.luau`'s `ASSETS.RigMeshes` alongside the prompts that made them.

## The prompts carry the research, not Western defaults

- **DOG** — *aspin*: light-boned, short rough coat, **tail held high**, one ear up one folded. Not a
  Labrador.
- **PIG** — native backyard pig: **black, sway-backed, low belly, small ears**, bristle crest, tufted
  tail. Not a pink straight-backed Landrace.
- **CAT** — *puspin*: short coat, **kinked stumpy tail**, tabby-and-white.
- **GOAT** — Philippine native: **small and low-set, erect ears, short straight horns**, rope collar.
- **CHICKEN** — native hen: single comb, whitish earlobe, **slate grey shanks**, head low.
- **VILLAGER** — **sando, work trousers, tsinelas, salakot**. Explicitly *not* a malong, which is
  Bangsamoro dress and would be a real geographic error on a lowland barrio villager.

## The sizing deviation, and why it was necessary

`buildEntity` assigns `body.Size = look.Size` outright, and a MeshPart **stretches** to fill whatever
it is given. The plan said to keep Phase 1's `Size` values — but those were the boxes the meshes were
*requested* in, and the generator fits inside a request while preserving aspect ratio:

```
CAT requested 1.4 x 1.2 x 2.6   ->   generated 0.46 x 1.20 x 1.22
```

Applying the requested box would have made the cat **three times too wide and twice too long**. Six
animals each distorted on a different axis, and nothing in `npm run verify` looks at a shape.

So each `Size` is now the mesh's **own** bounding box, uniformly scaled where the height needed
correcting. Only two needed it:

| Form | Generated height | Shipped height | Why |
| --- | --- | --- | --- |
| GOAT | 1.71 | **2.20** | 1.71 sat below the dog's 1.90 — wrong for a standing goat, and DOG/GOAT is the pair §4.5 is most likely to confuse |
| VILLAGER | 3.64 | **5.00** | child-height beside a 5-stud player |

The other four already matched their researched heights.

## The budget, now counted for the first time

```
PASS  barrio-assets: 117 assertions over 8 props (21000 tris) and 6 rigs (23400 drawn)
```

| | Requested | Instances | Drawn | Ceiling |
| --- | --- | --- | --- | --- |
| Props | 21,000 over 8 rows | ~37 | unchanged | 27,000 |
| Rigs | 7,800 over 6 rows | 18 | **23,400** | 9,000 / 27,000 |

**Before this phase the rigs were spent and invisible.** Four generated meshes at sixteen instances
existed only as asset ids inside `AmbientService.FORM_LOOKS`, which no check reads — so half of what
the phone drew was outside a budget §5 calls non-negotiable.

The ceilings are separate on purpose. A prop sits in fog at 200 studs; a rig is one of eighteen on
screen and one of them is being stared at, because §4.5's deduction is "which cat". One shared sum
would let a cheap prop pass pay for an expensive rig.

## Runtime — every mesh loads

```
0 of 18 rigs fell back to a plain box
Ambient_CAT_1        class=MeshPart  mesh=rbxassetid://96211506575053 size=0.46/1.20/1.22
Ambient_GOAT_10      class=MeshPart  mesh=rbxassetid://100545159776343 size=1.54/2.20/1.98
Ambient_VILLAGER_16  class=MeshPart  mesh=rbxassetid://124492172741324 size=1.95/5.00/1.65
...
```

`buildEntity`'s box fallback did not fire once, which is the check that the ids are real and loadable
rather than merely well-formed.

## Silhouettes — `ScreenCapture_5`

Six forms in one row at 4-stud spacing, viewed from 14 studs at `ClockTime 0` under shipped fog,
smallest to largest: **chicken, cat, dog, pig, goat, villager**.

All six are distinguishable. The pairs the plan flagged both separate cleanly:

- **CAT vs CHICKEN** — both small, but the cat is longer and lower with a visible tail; the chicken is
  upright and rounder.
- **DOG vs GOAT** — the goat's **horns** and the dog's **upright ears** are the tell, and the goat's
  raised height (2.20 vs 1.90) now helps rather than hurts.

The villager reads unambiguously as a person: salakot brim, sando, and a human stance.

**At 40 studs (`ScreenCapture_3`) the animals are near-indistinguishable from each other** — small dark
shapes in fog. That is worth knowing and is arguably correct for a horror game: §4.5 asks a survivor to
*approach* and study the population, not to solve it from across the plaza. It is a V16 question, not a
defect.
