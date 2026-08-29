# Research 03 — sari-sari store, chapel, graves, and the planting

Feeds **Step 6.1** (chapel), **Step 6.2** (stalls), **Step 7.2** (planting), **Step 7.3** (graves) and
**Step 7.4** (rice field). ✅ authoritative · ⚠️ weak or motivated · ❌ could not source.

---

## 1. Sari-sari store ✅ — the barred window is confirmed

- **The defining element, sourced:** commodities are displayed in *"a large screen-covered or **metal-barred
  window** in front of the shop."* **The transaction happens through the grille — customers do not enter.**
- **It is part of the house, not a separate building.** Family-run, *"operating within the shopkeeper's
  residence,"* using *"a portion of its home as storage and display space."*
- Stock layout is spatially specific and free to build: **candies in recycled jars, canned goods and
  cigarettes at the front window**; cooking oil, salt and sugar at the back. Prepaid phone load sold. Some
  have a fridge for soft drinks and beer.
- **Tingi**: customers buy single units rather than packages — this is what produces the sachet strips.
  Credit to regulars (**suki**), tracked by hand **in school notebooks**, collected on paydays.
- **"Benches provided in front of the store are usually occupied by local people."** ✅ Sourced — the
  seating is real and it is a loitering point.

**Signage ✅ conceptually, ⚠️ materially.** The correct term is a **privilege sign**: a retailer's sign
supplied free by a manufacturer carrying that manufacturer's branding, in exchange for advertising space.
Philippine sponsors named: **soft drinks, telecommunications, soap, tobacco** (Coca-Cola named). The
pattern is **store name + manufacturer logo together on one sign**.
⚠️ Tarpaulin as the medium is confirmed only by commercial print-shop listings, not an authority.

❌ **Unsourced:** store size in m²; the physical hanging sachet strips (the *practice* is very well
sourced, the *visual* is not); monobloc stools as a specifically sari-sari pairing (the chair itself is
well documented — see research-02 — but the association is inference).

> **IMPORTANT — this reorders Step 6.2's priorities.** The plan builds the grille first, and that is
> correct and now confirmed. But the plan's second item, the tarpaulin sign, **cannot carry the branding
> that makes a privilege sign recognisable** — there is no image generation in this toolchain. A blank
> coloured tarp is a weak use of parts.
>
> **Spend those parts on the sourced items instead: the bench out front, and the jars at the window.**
> Both are sourced, both are silhouettes rather than textures, and neither needs a decal. The bench also
> gives the stall a reason for players to stand near it, which matters because each stall now holds a
> `SearchContainer`.

## 2. Barangay chapel / visita ⚠️❌ — **the weakest topic in the whole reference set**

I could not find a single authoritative source describing the physical fabric of a modern barangay
chapel. **Treat this section as convention-led and say so in the implementation log.**

**What is sourced:**
- **Terminology:** *visita* and *ermita* are used interchangeably for *"small church-like structures
  located in barangays and distant villages"*; the term designates *"a blessed site housing the **patron
  saint of the place** and other icons."* **The chapel is defined by housing one named patron image.**
- **Siting ✅ and useful:** chapels are positioned with *"their backs against vast rice fields or banks of
  rivers."*
- Interior elements named: **main altar**, the patron image, other icons.
- One documented exception proves the norm: Chavayan, Batanes has *"the only kapilya with traditional
  **cogon roof** in the entire province."* **So cogon-roofed chapels are singular and metal/concrete is
  standard.**
- ⚠️ Generic Philippine rural construction: **concrete hollow blocks (CHB)** are *"a cornerstone of
  Philippine construction"*; **corrugated GI sheet ("yero")** is the standard cheap roof, sold in **0.4 /
  0.5 / 0.6 mm**, nominally lasting 30–50 years, faster in salt air.

❌ **Unsourced for the chapel:** dimensions, seating capacity, the bell (presence, mounting, material),
painted statuary and its colours, wall paint colour, plan form, **and how GI roofing actually rusts** —
every source on GI is a vendor claiming it *resists* rust, so the visible red-streaking reality is
undocumented.

> **Two consequences for the plan.**
>
> **The siting finding is a free win and the map already has it.** The chapel sits near the rice field
> edge. That is sourced-correct; do not move it, and note it in Step 6.1 as validation rather than
> changing anything.
>
> **`BarrioGIRoof`'s rust streaking is unsourced and should still be built.** It is the single most
> recognisable feature of a Philippine rural roofline and its absence would read as wrong. But it goes in
> the log as convention, not as research — which matters because if a Filipino playtester at V16 says the
> rust is overdone, there is no source to defend it with and the note should just be taken.

## 3. Grave markers ✅ — **the core question is confirmed: above-ground concrete**

- **Apartment tombs are real and dominant for lower-income families.** Verbatim: each niche is *"a
  **box-like enclosure**… each about the size of a **small refrigerator tipped on its side**."* That gives
  roughly **1.7–1.8 m deep × ~0.6 m wide × ~0.6 m high**, opening on the short end.
- **Stacking:** *"four burial niches on top of"* another — **four to five per column** documented. Walls
  *"stretch for tens of metres, down a gravel lane that gradually narrows into a footpath."*
- Some niches carry **wrought-iron gates**.
- Ground condition, verbatim: *"cluttered with mausoleums and **raised concrete tombs**"*; *"some are
  **cracked and crumbling**, others near immaculate."*
- **Tenure drives decay:** niches are **rented on five-year terms**, after which remains are removed;
  unclaimed remains kept in **rice sacks**.

**Paint and offerings ✅ — the load-bearing finding:**
- *"In the Philippines, putting a **fresh coat of paint** on a gravesite is one of the most common ways to
  honour the family's dead."* Families *"clean the grave, **repaint the lettering**, lay flowers and light
  candles,"* and *"**repaint names that are already fading**."*
- Offerings: **candles, fresh flowers, food containers**; at Undas also chairs, coolers, stoves,
  **tarpaulins**, speakers.
- Marker materials vary: **marble, stone, even wooden markers.** Inscriptions carry three-letter
  abbreviations: **R.I.P., D.O.M., PAX** (Latin), **D.E.P., E.P.D.** (Spanish), **S.L.N.** (Tagalog),
  **P.S.K.** (Cebuano).

**Why above ground — partly sourced.** High water table and flooding is a real documented pressure: Tondo's
old cemetery became infamous for odours from *"frequent flooding and… **groundwater being near the
surface**"*, and in Hagonoy cemeteries are *"sealed off under permanent water, with only mausoleums
remaining visible."*
⚠️ **No source links Spanish colonial practice to the tradition. Do not assert that causation.**

❌ **Unsourced:** specific whitewash/paint colours, **moss and biological growth**, and **tilt/subsidence**.

> **IMPORTANT — this substantially changes Step 7.3 and improves it.**
>
> The plan builds "carved concrete cross, tilt, moss, candle stubs." Three of those four are now
> supported differently than assumed:
>
> 1. ✅ **The above-ground tomb slab is confirmed and is the biggest correction** — it changes the
>    silhouette from headstone to tomb. The plan already has this; it is now sourced.
> 2. ✅ **Repainting is the real variation axis, and it is far better than "age."** Graves are repainted
>    *annually by families*, so a real cemetery is **freshly-repainted and long-neglected tombs side by
>    side** — and **faded lettering specifically means "this family stopped coming."** For a horror game
>    that is a genuinely eerie, sourced detail. **Vary the eight graves by paint freshness, not by age.**
> 3. ❌ **Moss and tilt are both unsourced.** Keep the existing `lean` — it is plausible and already
>    built — but label it convention. Same for moss.
> 4. ✅ **Candles are sourced** as offerings. Keep them (as `Neon`, never `PointLight` — C30 rule 2).
>
> The **R.I.P. / D.O.M. / PAX / S.L.N.** abbreviations are a cheap, highly specific authenticity detail —
> but they are lettering, and **there is no image generation.** Out of reach; noted in the plan's Follow
> Ups alongside the sari-sari signage for the same reason.

## 4. Rice paddies ✅ — FAO gives exact figures

- **Temporary bunds:** base **60–120 cm**, height **1.5–30 cm**, **10 cm freeboard**, irrigation depth
  **5–20 cm**. Rebuilt each season.
- **Permanent bunds:** base **130–160 cm**, built **60–90 cm** high, **settling to 40–50 cm**. FAO states
  permanent bunds **"serve as field pathways."**
- Basin sizes **35 m² to 6,000 m²**; **basin width capped around 20 m at 1% slope.**
- Water depth: **~3 cm** just after transplanting → **5–10 cm** as plants grow → **drained 7–10 days
  before harvest.**

**Colour by stage ✅:** grain *"changes colour from green to gold or straw colour at maturity"*; fields
mid-transition show *"a mixture of green and golden yellow."*

> **Two findings change Step 7.4 materially.**
>
> **The bunds are walkable, ~1.5 m wide and knee-high, and FAO says so explicitly.** That is a *path
> network through the rice field* — and §5 calls the rice field "the killing field." A knee-high walkable
> dike grid is far better horror geometry than an undifferentiated green mass, and it is non-collidable
> flat parts, so it costs the navmesh nothing.
>
> **A paddy at harvest is DRY, not flooded.** The plan's water plane is only correct for a growing field.
> **Correct move: mixed states.** Neighbouring paddies are planted at different times, so a real landscape
> shows **green, green-gold, straw, and drained bare-mud basins adjacent.** That is sourced, it is more
> visually interesting than uniform green, and the bare-mud basins cost fewer parts than stalks — which
> helps Step 7.2's budget.
>
> Basins capped at ~20 m across means the field should read as **a patchwork of irregular basins**, not
> one field. At `SCALE = 1.55`, 20 m ≈ 46 studs.

## 5. Bamboo ✅ — *Bambusa blumeana*, "kawayan tinik"

**The clumping question is answered definitively: sympodial (clumping), not running.** *"Densely
tufted"*, with the clump base reaching **2–3 m high** before culms rise.

- Culms **15–25 m tall**, up to **~20 cm** diameter, walls **0.5–3 cm**, internodes **25–60 cm**
  (Philippine average **34 cm**). Green, *"slightly arched."*
- **Branches arise from nearly all nodes; the lower ones spread horizontally**, and basal branches carry
  *"stout straight or curved spines in groups of (1–)3(–5)"* — hence *tinik*, thorn.
- **Leaf blades are small: 15–20 cm × 1.5–2 cm.**
- Distribution: *"throughout the settled areas at low and medium altitudes."*

> **IMPORTANT — this confirms Step 7.2's part reduction and gives it the right shape.**
>
> The silhouette is: **a dense spiny skirt in the lower 2–3 m, bare arching mid-culms, and a high feathery
> crown.** The greybox builds one leaf per culm scattered up its length, which is the opposite
> distribution and is both wrong and expensive.
>
> **Leaf blades at 15–20 cm are far too small to model individually** — that is ~0.6 studs. They must be a
> *mass*, which is what Step 7.2's "one cluster per clump" change does. Sourced, cheaper, and better.
>
> **Bamboo belongs against the houses, not in a wilderness band** — "throughout the settled areas." Worth
> checking the current placement against that.

## 6. Banana ✅ — use Saba, and the leaves must be shredded

- **Saba / Cardava** pseudostems **6–9 m**; the dwarf **Saging Mondo** is **2.5–3.5 m** and is
  specifically *"grown in backyard farms."* **For a barrio yard the dwarf is the sourced choice.**
- Leaves up to **2.5 m long × 0.5–1 m wide**, spirally arranged, light green, smooth and glossy.
- **The pseudostem is not a trunk** — *"formed by tightly packed overlapping leaf sheaths."* Model it as a
  smooth, slightly tapering, layered column, **not bark**.
- **Wind shredding is explicitly sourced:** *"Leaf blades are often **torn by the wind and hang in ribbons
  from the midrib**."* Continuous wind causes leaf shredding, drying, and *"plant crown distortion."*
- Height varies with shelter: **4 m on open plains vs 8 m in sheltered valleys.**

> **An intact banana leaf is WRONG for a barrio.** The default is a midrib with ragged strips hanging off
> it. This matters for hero mesh #6 — **the `generate_mesh` prompt must say "torn, shredded leaves hanging
> in ribbons from the midrib"**, or it will produce the clean botanical-illustration banana that reads as
> a video-game plant.
>
> The current builder uses 12 trunks + 48 leaves = 4 leaves each. Real Saba carries more, but shredded.
> **The mesh replaces this entirely, which is where Phase 5's part saving comes from.**

---

## Sources

**Sari-sari** — [Sari-sari store — Wikipedia](https://en.wikipedia.org/wiki/Sari-sari_store) ·
[Privilege sign — Wikipedia](https://en.wikipedia.org/wiki/Privilege_sign) ·
[Small Portions, Big Impact: Tingi Culture and Sachet Marketing (ResearchGate, 2024)](https://www.researchgate.net/publication/387130710_Small_Portions_Big_Impact_The_Economic_Cultural_and_Environmental_Dimensions_of_Sari-Sari_Store's_Tingi_Culture_and_Sachet_Marketing) ·
[Experiences of Women Sari-sari Store Owners — PIDS (PDF)](https://pidswebs.pids.gov.ph/CDN/document/pidsdps2450.pdf)

**Chapel** — [From Caves to Chapels: The Evolving Ermita — Bicol Mail](https://www.bicolmail.net/single-post/from-caves-to-chapels-the-evolving-ermita) ·
[Pistang Chavayan, Sabtang — Asian Studies Journal, UP Diliman (PDF)](https://www.asj.upd.edu.ph/mediabox/archive/ASJ_56_1_2020/Performing_Traditional_Fiesta_Batanes_Pistang_Chavayan_Sabtang_Philippines_Tiatco.pdf) ·
[Construction Materials for Philippine Projects — Mackun Hardware](https://mackunhardware.com/blogs/mh-articles/the-ultimate-checklist-of-construction-materials-for-philippine-projects) *(commercial)* ·
[Yero Price List — Pinas Hardware](https://pinashardware.com/yero-price/) *(commercial)*

**Graves** — [Manila's 'apartment tombs' — SCMP](https://www.scmp.com/magazines/post-magazine/long-reads/article/2108198/manilas-apartment-tombs-where-poor-bury-their) ·
[Apartment tombs to mansion graves — Rappler](https://www.rappler.com/voices/new-school/opinion-apartment-tombs-mansion-graves-reflections-inequality-death/) ·
[Streamers, paint, vendors: Filipinos prepare graves for 'Undas' — NCR](https://www.ncronline.org/news/world/streamers-paint-vendors-filipinos-prepare-graves-undas) ·
[In Cebu, cemetery work and Undas 'rites' — Rappler](https://www.rappler.com/philippines/visayas/cebu-graveyard-work-undas-rites-carreta-cemetery-november-2024/) ·
[A Visual Tour of Philippine Lapidas and Tombstones — The Visual Traveler](https://www.thevisualtraveler.net/2019/10/a-visual-tour-of-philippine-lapidas-and.html) ·
[Dead and drowned: Cemeteries vanish as seas, floods rise — Inquirer](https://newsinfo.inquirer.net/2132215/dead-and-drowned-cemeteries-vanish-as-seas-floods-rise) ·
[Funeral practices and burial customs in the Philippines — Wikipedia](https://en.wikipedia.org/wiki/Funeral_practices_and_burial_customs_in_the_Philippines)

**Landscape** — [Chapter 2: Basin Irrigation — FAO](https://www.fao.org/4/s8684e/s8684e03.htm) ·
[Water management — IRRI Rice Knowledge Bank](http://www.knowledgebank.irri.org/step-by-step-production/growth/water-management) ·
[Rice Growth Stages — EOS](https://eos.com/crop-management-guide/rice-growth-stages/) ·
[Bambusa blumeana (PROSEA) — PlantNet PlantUse](https://plantuse.plantnet.org/en/Bambusa_blumeana_(PROSEA)) ·
[Bambusa blumeana — Wikipedia](https://en.wikipedia.org/wiki/Bambusa_blumeana) ·
['Kawayan tinik' shoot and pole production — Agriculture Monthly](https://agriculture.com.ph/2019/08/05/kawayan-tinik-shoot-and-pole-production/) ·
[Saba banana — Wikipedia](https://en.wikipedia.org/wiki/Saba_banana) ·
[Saging Mondo Banana — Slow Food Foundation](https://www.fondazioneslowfood.com/en/ark-of-taste-slow-food/saging-mondo-banana/) ·
[Banana pseudostem — ProMusa](https://www.promusa.org/Banana+pseudostem) ·
[Banana Growing in the Florida Home Landscape — UF/IFAS EDIS](https://edis.ifas.ufl.edu/mg040)
