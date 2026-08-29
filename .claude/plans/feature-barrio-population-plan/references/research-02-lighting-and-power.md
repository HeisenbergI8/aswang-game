# Research 02 — lanterns, the power line, bamboo and fencing

Sourcing: **✅ sourced** · **⚠️ weakly sourced / snippet-only** · **❌ unsourced convention**.

Covers Phase 8's two biggest part counts — 24 lantern parts and 92 power-line parts — plus the fencing
that Phase 8.3 rebuilds.

---

## 1. Street lighting — two eras on one street

| Era | Source | CCT | CRI | What it does to a scene |
| --- | --- | --- | --- | --- |
| ~1970s–2010s | High-pressure sodium | **1900–2200 K** (~2050 K typical) | **20–25** (≈22) | Orange. **Colours die** — reds and blues go muddy grey-brown |
| Now | LED / solar-LED | **4000–6500 K** | 70+ | Blue-white, **hard-edged** directional pool |

✅ HPS 1900–2200 K, "white" variants 2700–2800 K at CRI 70–80 — [Access
Fixtures](https://www.accessfixtures.com/leds-that-look-like-hps/) · ✅ HPS CRI 20–25 —
[ScienceDirect](https://www.sciencedirect.com/topics/computer-science/pressure-sodium-lamp) · ✅ "by the
late 20th century the orange glow of HPS had become the default look of cities at night" —
[Inlux](https://www.inluxsolar.com/why-are-street-lights-orange/)

**The low CRI is the payload, and it is the thing a Roblox scene usually gets wrong.** Under 2050 K /
CRI 22 the pool should be **near-monochrome amber — desaturate everything inside it**, not merely tint
it orange. The LED pools render colour normally and fall off hard.

### Fixture silhouette is the era signal, and it is free

✅ **Cobra head** — curved tapered housing bulging at the fixture end, on a horizontal bracket arm =
old / HPS / orange. — [LED Lighting
Supply](https://www.ledlightingsupply.com/led-outdoor-lights/led-street-lights/led-cobra-head-lights)

✅ **Flat wedge** — panel, battery and LED in one horizontal slab at the arm's top, no separate panel =
modern integrated solar. Or a **split system**: a tilted blue-black polycrystalline panel bolted at the
pole top with the head on an arm below. — [Grand
Philippines](https://grandphilippines.com/blog/solar-street-lights-for-barangay-subdivisions/)

**Two silhouettes, instantly readable, and mixing them is the authentic look.** ❌ The *ratio* of HPS to
LED in a given barrio is unsourced.

### Sizing and spacing ✅

30–90 W for interior streets, 100–200 W for main barangay roads; pole **3–5 m interior, 5–8 m main**;
100 W every **15–20 m**, 200 W every **20–25 m**; runtime 10–14 h (6PM–6AM). General rule: **spacing ≈
3.5–4× pole height**. — [Grand
Philippines](https://grandphilippines.com/blog/solar-street-lights-for-barangay-subdivisions/),
[Clodesun](https://www.clodesun.com/how-to-design-solar-street-light-pole-height-and-distance/)

The barrio's twelve lanterns over ~360 studs at Range 26 already meet §5's cap **by spacing**, which is
what lets the sightline rule hold at the same time. That arrangement should not change.

### Broken and dark is normal ✅

*"Many streetlights in the area are broken and do not work anymore… many parts of the Sitio become very
dark after sunset"* — root cause is barangay budget, where lighting loses to education, health and
waste. — [change.org petition, Sitio Binarilan](https://www.change.org/p/public-safety-begins-with-proper-street-lighting)

**A dark lantern costs no light slot.** ❌ The 1-in-4 ratio is convention — and it is a *gameplay* lever
(§5's "partial information"), so it belongs in V16's balance questions rather than in a constant.

✅ *Poste ng ilaw* = lamppost. — [Wiktionary](https://en.wiktionary.org/wiki/poste_ng_ilaw)
❌ The hung-bulb-outside-the-house tradition: searched directly, found only retail listings. Convention.

---

## 2. Rural distribution hardware

Best single Philippines-specific source: the [OSM Philippines power-line tagging
guide](https://wiki.openstreetmap.org/wiki/User:TagaSanPedroAko/Philippines_Tagging/Power_lines).

**Poles** ✅ Wood, concrete **or** steel. Distribution (13.8–34.5 kV): **13.5–15 m**. ✅ Prestressed
spun concrete 7.5–9.0 m for domestic distribution. ✅ A PH manufacturer makes **prestressed rectangular
"I"-section** poles for the local market. — OSM PH; [PMW](https://pmw-group.com/2026/03/04/spun-concrete-pole/);
[SPC Pole](https://www.spcpole.com/)

**Build note:** Philippine concrete poles are frequently **not round** — tapered rectangular with a
visible longitudinal flute, grey and weathered, often a painted white band near the base. ❌ Black mould
streaking is convention, and it is what makes a concrete pole read tropical rather than American.

**The barrio currently paints its poles `WOOD` with `Enum.Material.Wood`.** `RustedSteel` and
`HollowBlock` are already in the material registry.

**Conductors — the biggest "not America" tell** ✅ **220 V single-phase: two wires, one used as
neutral.** 13.2 kV / 34.5 kV are standard two- to three-wire lines. ✅ Single-phase primary is "the main
mechanism for rural distribution"; single-phase transformers **5–25 kVA**. — OSM PH; Scribd
distribution-line notes (snippet-only)

**So a rural feeder is TWO conductors on one short crossarm.** The barrio already draws two wires per
span — that is correct and should stay. A six-wire three-phase rack reads as suburban.

**Transformers** ✅ PH pole transformers *"typically two bushings"*. 25 kVA single-phase ≈ **935 mm h ×
560 mm w × 590 mm d**, 180–258 kg, galvanized steel with powder coating. — OSM PH;
[Daelim](https://www.daelimtransformer.com/25-kva-single-phase-pole-mounted-transformer.html)

**One can per rural pole, not a bank of three.** Vertical cylinder ~0.5 m × 0.9 m, two porcelain
bushings on the lid, cooling corrugations, mounted to the pole face below the crossarm. ⚠️ The
one-per-pole placement is inferred from the single-phase sourcing, not directly cited.

**Insulators** ✅ 13.2 kV uses **one- or two-cap pin insulators** on top of the crossarm, and **two-cap
strain insulators** at dead-ends and corners. — OSM PH. ❌ Colour: brown/grey porcelain is convention.

**Service drops** ⚠️ Outside the big cities, houses take a **two-wire 230 V drop** — one load wire, one
neutral. Manila uses a three-wire 120/240 V system. Philippines is 230 V / 60 Hz. — forum/student
sources; indicative rather than authoritative. **So the drop is a twisted pair, not a US triplex.**

**Guy guards** ✅ **Yellow high-impact UV-stabilised plastic, 8 ft (2.44 m) long, 32–38 mm diameter**,
wrapped over the lower down-guy at the anchor, for visibility. —
[3 Star](https://www.3starinc.com/guy-guard-marker-yellow-plastic.html)

**Best cost-per-read prop in the whole step**: a saturated yellow at ~45° in an otherwise grey-brown
night scene. It catches a torch beam and it silhouettes.

---

## 3. What hangs on the poles

✅ **"Spaghetti wires"** is the established Philippine term — *"clusters of tangled and overlapping
overhead utility cables… power, telecommunications, and cable television lines."* Manila's removal
campaign pulled **two million kilos**. — [Wikipedia](https://en.wikipedia.org/wiki/Spaghetti_wires),
[Manila Bulletin](https://mb.com.ph/2025/07/09/no-more-spaghetti-wires-manila-cracks-down-on-unregulated-cabling)

**The rule this gives you, and it is the whole visual grammar:** power is **few, taut, high, evenly
spaced**; telecom is **many, sagging, low, chaotic**, in a thick untidy bundle well below the crossarm.
**The vertical separation between the two zones is the thing.** The barrio has only the top zone today.

✅ **Fibre slack loops** — cable wound between "snowshoe" brackets to limit bend radius, stored looped
and tied to the pole. Visually a flattened black coil, 6–10 turns, ~0.6–1 m across, hanging below the
telecom bundle. Very common, almost never modelled. — [Codidact](https://electrical.codidact.com/posts/280327)

✅ **Campaign tarpaulins.** It is **explicitly illegal** to post material on *"street and lamp posts,
electric posts and wires"*; legal cap **2 ft × 3 ft**; legal only in designated common poster areas;
**"Oplan Baklas"** removal operations run constantly. — [Rappler](https://www.rappler.com/voices/thought-leaders/224291-rules-campaign-posters/),
[Inquirer](https://newsinfo.inquirer.net/1849113/comelec-reminds-barangay-sk-bets-of-poster-tarpaulin-limits)

**The law is the citation for the visual** — they keep having to strip them because they keep going up.
Weatherproof tarpaulin, cable-tied at 1.5–2.5 m. ❌ Sun-bleaching and layering are convention.

❌ Birds: no Philippines-specific citation found.

---

## 4. The brownout — sourced, excellent, and out of scope

✅ *"Large parts of rural cooperative networks rely on **single feeder lines**… even minor maintenance
or weather-related damage can **interrupt supply to entire barangays or towns**."* Scheduled outages run
4–5 h; unplanned ones can exceed 12 h in provincial regions. Filipinos say **"brownout"**. —
[Live Life the Philippines](https://livelifethephilippines.com/posts-retirement/electric-supply/power-outage.html)

**Why it is tempting:** radial topology means the barrio goes dark **at once**, not house by house — no
partial failure, no flicker-down — and **the lights that survive are exactly the solar ones that were
never on the wire.**

**Why it is not in this plan:** that is a mechanic, and mechanics come from §3. The realism plan
deferred the identical finding for the identical reason. Recorded so the next person finds it sourced.

---

## 5. Bamboo and fencing

**Species** ✅ all from PROSEA:

| Species | Local | Height | Culm ⌀ | Internode | Colour |
| --- | --- | --- | --- | --- | --- |
| *B. blumeana* | **kawayan tinik** | 15–25 m | to 20 cm | 25–60 cm | green |
| *G. levis* | **bolo** | to 20 m | to 16 cm | to 45 cm | plain green, dark-hairy base |
| *S. lumampao* | **buho** | 10–15 m | 4–8 cm | 25–50(–80) cm | glabrous green |
| *B. vulgaris* | **kawayan kiling** | 10–20 m | 4–10 cm | 20–45 cm | green, or **yellow with green stripes** |

[PROSEA pages](https://plantuse.plantnet.org/en/Bambusa_blumeana_(PROSEA))

**Habit — the thing to get right** ✅ **All of these are sympodial (clumping), not running.** A mature
clump holds **10–40 culms** and pushes ~30 shoots a year. Kawayan tinik's defining features are its
**large clumps and spiny branches at the basal portion**, a **2–3 m spiny thicket** with spines in
groups of 1–3(–5) and aerial roots. ✅ Used as **living fence, boundary marker and windbreak around
farmhouses**. ✅ Philippine plants have **longer internodes** than Indonesian or Malaysian ones. —
PROSEA; [Agriculture Monthly](https://agriculture.com.ph/2019/08/05/kawayan-tinik-shoot-and-pole-production/)

A clumping bamboo is **a tight fountain from a single base**, culms leaning out and arching, occupying
2–4 m of ground — not the evenly-spaced vertical forest of Japanese *Phyllostachys* that most stock
assets give you. The barrio's bamboo was already rebuilt as clumping by the realism plan; keep it.

❌ The green → straw-yellow → weathered grey-tan drying progression, and longitudinal splitting, are
convention. A real fence mixes ages, so a single flat tan is wrong.

**Sawali** ✅ Made from **buho**, *"woven from thin strips"*, in *"repeating **diagonal, zigzag, or
diamond-like shapes**"* — **"sawali" specifically refers to twilled weaving patterns.** Soaked in
seawater, dried, sometimes varnished, then **affixed to wooden frameworks and battened with bamboo or
coco lumber**. Regional names: *sawali* (north), *sulirap/salirap* (Visayan). —
[Wikipedia — Amakan](https://en.wikipedia.org/wiki/Amakan), PROSEA

**The twill diagonal is the identity.** A plain over-one-under-one checkerboard reads as a generic
basket. The panel edge should show a horizontal batten, not a raw cut edge. ❌ Standard panel
dimensions and strip width: no authoritative source; panels are made to fit the frame bay.

**Living kakawate fence — the one nobody builds** ✅ *Gliricidia sepium*'s English common name is
literally **"Fence Post Tree"**. Grows 2–15 m; bark greyish-brown and much fissured. **The recommended
propagation method is large hardwood stem cuttings planted directly as fence posts, cut 1.5–2 m long
and 5–8 cm in diameter.** *"Kakawate is everywhere in the Philippines… **as living fences in rural
barangays**."* — [World Agroforestry](https://apps.worldagroforestry.org/treedb2/speciesprofile.php?Spid=912),
[Edge Davao](https://edgedavao.net/agri-trends/2021/07/agritrends-this-wonder-tree-called-kakawate/)

**The fence posts are alive.** A driven stake sprouts, so the line carries leaves and thin branches at
irregular heights with wire or bamboo strung between — and some sprout vigorously while some do not, so
the line is ragged. It is a variation on posts the map already has, for a distinctive silhouette.

---

## Honest gaps

Whether barangay streetlights are mostly bracket-mounted on coop poles or on dedicated posts; any
dead-fixture ratio; the hung-bulb tradition; PH rural pole spacing (the NEA 13.2 kV standard and the
NRECA rural design module are PDFs that resisted extraction); sawali panel dimensions; dried-bamboo
colour values; birds.
