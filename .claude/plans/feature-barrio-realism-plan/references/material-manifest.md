# Material manifest — every surface, and the variant it gets

Input to **Phase 3**. Each row becomes one `generate_material` call and one `ASSETS.Materials` entry.

**The rule that makes this work at all:** a `MaterialVariant` needs **both** `Material` and
`MaterialVariant` set on the part, or it silently does nothing — no error, no warning, indistinguishable
from a typo. `paint()` exists so the pair cannot be half-applied, and
`tests/barrio-materials.test.luau` fails the tree on any hand-written assignment outside it.

**`Regular` for man-made surfaces, `Organic` for natural ones** (asset-pipeline skill).

---

## The twelve

| # | `materialId` | `baseMaterial` | Pattern | `materialDescription` | Lands on |
| --- | --- | --- | --- | --- | --- |
| 1 | `BarrioMud` | `Mud` | Organic | wet packed dirt road, tyre ruts, puddled hollows, dark and uneven | 18 `Roads` parts, 3 alleys |
| 2 | `BarrioNipa` | `Grass` | Organic | dried nipa palm thatch roof, layered shingled bundles, **patched in stages so fresh brown sections sit against older grey-brown ones** | every `*_Roof` via `building()` — 7 kubo + chapel |
| 3 | `BarrioSawali` | `WoodPlanks` | Regular | flattened split bamboo woven in a tight diagonal herringbone, semi-opaque, sun-bleached | kubo walls |
| 4 | `BarrioBamboo` | `Wood` | Organic | green bamboo culm, hard glossy nodes every 30 cm, slightly arched, weathering to straw | stilts, posts, fences, kubo floors |
| 5 | `BarrioCourtSlab` | `Concrete` | Regular | painted outdoor concrete basketball court, worn green-grey paint over cement, **cracked and patched, faded hand-painted white lines** | `Court_Slab` |
| 6 | `BarrioHollowBlock` | `Concrete` | Regular | unrendered concrete hollow block wall, visible block courses and mortar joints, damp-stained at the base | chapel, arko, waiting-shed-style walls |
| 7 | `BarrioGIRoof` | `CorrodedMetal` | Regular | corrugated galvanised iron sheet roofing, **red-brown rust streaking downslope from nail lines**, dented | chapel roof, stall roofs, lean-tos |
| 8 | `BarrioTarp` | `Fabric` | Regular | cheap woven polypropylene tarpaulin, creased from folding, sun-faded, frayed grommet edges | stall tarps, `Flag` |
| 9 | `BarrioWetEarth` | `Ground` | Organic | bare compacted earth yard, damp, scattered with leaf litter and gravel | `Ground` plane |
| 10 | `BarrioPaddy` | `Grass` | Organic | rice paddy stalks, **mixed green and golden-straw as the crop ripens unevenly**, dense and fine | `RiceField` wedges |
| 11 | `BarrioWhitewash` | `Concrete` | Regular | whitewashed painted concrete, **freshly repainted in patches over older chalky flaking paint** | graves, chapel exterior |
| 12 | `BarrioRustedSteel` | `CorrodedMetal` | Regular | rusted mild steel bar and pipe, flaking orange scale over dark metal | stall grilles, hoop poles, rims |

---

## Notes that change how these are prompted

**Three descriptions above carry a research finding rather than a colour.** They are bolded in the table
and they are the difference between a generic texture and a Filipino one:

- **#2 `BarrioNipa` — "patched in stages."** research-01 found that "nipa greys with age" is
  ❌ **unsourced** — the only evidence is synthetic-thatch vendors selling a "weathered grey" colourway.
  What *is* sourced is that nipa needs total replacement every few years and is patched continuously. So
  the accurate variation is **within one roof**, not between houses. Prompt for the patchwork, not for age.
- **#5 `BarrioCourtSlab` — painted, not bare cement.** research-02: the court is repainted for every
  fiesta. A bare-cement slab reads as a car park.
- **#10 `BarrioPaddy` — mixed green and straw.** research-03/FAO: neighbouring basins are planted at
  different times, so uniform green is the giveaway.

**#7 `BarrioGIRoof`'s rust streaking is ❌ unsourced and should be built anyway.** Every source on GI sheet
is a vendor claiming it resists rust, so the visible reality is undocumented. It is the most recognisable
feature of a Philippine rural roofline and its absence would read as wrong — but log it as convention, and
if a Filipino playtester at V16 says it is overdone, take the note without arguing.

**#1 and #9 are the two largest surfaces in the map** — the ground plane and the whole road network. They
are also the cheapest to change and the most visible at every moment of play. **If only two variants are
ever generated, generate these two.**

---

## What is deliberately NOT in this list

**No character, skin, or item materials.** Everything here lands on anchored map geometry. The Aswang's
appearance is `MonsterService`'s and is a secrecy surface; nothing in this manifest may touch it.

**No `Neon` variant.** Neon is used for the banderitas bulbs and the grave candles precisely because it
is emissive geometry that costs **no light slot** against `Config.Performance.MaxVisibleLights = 8`.
A MaterialVariant over Neon would risk making it read as a surface rather than a source.

**No water material.** The puddles and the paddy water plane use low `Reflectance` on a flat dark part,
which is what the builder already does and calls "the highest ratio of atmosphere to parts in the whole
file." A generated water material would not improve a 0.15-stud-thick slab seen at a glancing angle.

---

## Two open questions for Phase 3

1. **⚠️ I have not confirmed `generate_material` accepts every `baseMaterial` above.** `Mud`, `Ground`,
   `CorrodedMetal` and `Fabric` are all real `Enum.Material` values, but the tool documents its parameter
   only as "a BaseMaterial." **Record what comes back, not what was asked for** — a registry row whose
   `Base` disagrees with the generated variant is exactly the silent-nothing case.

2. **Twelve is a guess at the right number.** Too few and every surface reads the same; too many and the
   barrio stops reading as one village built by one community from three materials. **Step 4.5's approval
   gate asks this as an explicit question.** If the answer is "patchwork," the fix is to drop #6 and #11
   into a single concrete variant and #3 into #4 — nine, not twelve.
