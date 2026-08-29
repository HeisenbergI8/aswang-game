# Research 02 — the barangay court, and street furniture

Feeds **Step 4.1** (the court), **Step 4.2** (benches, flagpole, banderitas) and **Step 7.4** (the power
line). ✅ authoritative · ⚠️ weak or motivated · ❌ could not source.

---

## The court is not a sports facility. It is the plaza. ✅

This is the finding that should change how the court is built, more than any dimension.

Sourced uses, verbatim from headlines and features: covered courts **"host wakes, pageants, circumcision
rites"**, plus funerals, concerts, vaccination drives, solemn masses, fiestas and dancing. The framing
one source uses directly: **"the basketball court as the modern-day plaza."**

> **IMPORTANT — this is a gift for this map, because the barrio's plaza IS the spawn zone.** §5 wants the
> plaza to be the "safe-ish social hub" and to feel different from the alleys. The court is already
> there. What it lacks is **residue of non-basketball use**, which is cheap in parts and enormously
> characterful:
>
> - stacked monobloc chairs against one edge (2–3 parts, reused shape)
> - a low stage or platform at one end
> - tarpaulin banners tied to whatever is upright
> - bunting — which the banderitas already provide, and they are strung over the plaza already
>
> **Recommend adding the stacked-chairs cluster to Step 4.2.** It is the single most "this is a real
> barangay" object available for under five parts, and monobloc chairs are ✅ well documented
> (polypropylene, usually white, single-piece moulded, globally ubiquitous since the 1980s).

## Dimensions ✅ — and undersized courts are legitimate, not a compromise

- FIBA regulation: **28 × 15 m**. Backboard **1.80 × 1.05 m**. Rim **3.05 m** to the top of the ring.
  Free-throw line **4.60 m** from the backboard.
- ⚠️ The Philippine covered-court design spec permits scaling: standard **28 × 15 m**, *"but it can be
  scaled down proportionally to a minimum of **12 m × 7 m**."* Also: spectators at least **5 m** from the
  boundary line. *(Scribd-hosted; original issuing body unverified — I could not find the DILG original.)*

> **This directly answers the question Step 4.1 was guessing at.** Real barangay courts are routinely
> undersized — down to ~43% of FIBA length — but **scaled proportionally**. So the *ratio* is what must
> be right, not the size.
>
> **28:15 = 1.87:1.** The greybox slab is 30 × 18 = **1.67:1**, which is too square. Step 4.1's change
> to 30 × 16 gives **1.875:1** — correct, and confirmed by this source rather than by eye. Keep it.

## Equipment and decay ❌ — the honest gap

⚠️ Rappler describes shooting *"at makeshift rings made of spare car parts attached to old, wooden
backboards,"* and *"the rusty rim nailed on top of a coconut tree or the rickety rim screwed on top of a
barangay building."* Journalistic, not technical.

❌ **UNSOURCED, all of it: plywood vs steel vs concrete backboards, bent rims, absent nets, hand-painted
line quality, and slab cracking.** These are true to photographic reality and I could find no document
stating them.

> **The plan builds them anyway, and this note is why that is defensible.** Step 4.1's cracked slab, bent
> netless rim and plywood backboard are **observed convention, unsourced** — that is what they should be
> labelled in the implementation log. The one adjacent sourced fact that supports the general direction:
> courts are built on **"uneven terrain"** and demand improvisation.
>
> ❌ Covered-hall roof structure, clearance height and slab thickness are also unsourced — which is a
> second, independent reason Step 4.1 refuses to build the covered court. The plan's stated reasons are
> budget and sightline; add "and nobody could tell us what it looks like."

## Banderitas ✅ — the best-sourced thing in this document

- Material: **incredibly thin, translucent plastic**, "unapologetically cheap," sometimes heavily branded
  by **politicians or commercial sponsors**. Commercial listings: taffeta-like plastic flags on a **white
  cord**, sold in 3–25 m lengths.
- **Two shapes only: sharply cut triangles, or fringed rectangles.**
- Colours: **primary — reds, yellows, blues** (plus white).
- **The fade sequence, verbatim, and it is the finding to build to:** *"the vibrant, screaming reds break
  into a **bruised, muted pink**. The sharp yellows fade into a **sickly cream**, and the deep blues turn
  into **ghostly, translucent gray**."*
- Stringing is opportunistic: lines tied to **a sloping telephone pole**, stretched over the asphalt,
  anchored to a **rusty second-storey grill**; or from a **mango tree** to the **wooden awning of a
  sari-sari store**. Uneven heights, sagging across the road.
- Timing: hung **weeks before** the event, left up **long after**, deteriorating over months or a year.

> **IMPORTANT — this contradicts Step 4.2's diff and the plan should be corrected.** Step 4.2 says
> "expect saturated primaries, not the muted map palette." **That is wrong.** The sourced default state of
> banderitas in a barrio is **faded and partly torn** — bruised pink, sickly cream, ghostly grey.
>
> That is *better* for this game on every count: it fits the existing muted palette, it fits a horror
> night, and it is what the source actually describes. **`FIESTA_COLOURS` should be the faded triple, not
> the fresh one.** A few fresh flags mixed in reads as "recently patched," which is also true.
>
> **Also worth taking:** anchor the runs at **uneven heights** to opportunistic points, not symmetrically
> to four lantern tops. The current four-corner square is too tidy against this source.

## Overhead wires ✅ — model the mechanism, not the look

- The Philippine term is **"spaghetti wires."**
- Four separate systems share one pole: **electric distribution, fibre-optic, internet, cable TV.**
- **The formation mechanism is sourced and is what to build:** *"additional lines are attached while
  unused or outdated cables are left in place, resulting in thick bundles of hanging wires."* Manila's
  cleanup removed **two million kilos** of "unnecessary, unutilized and unusable" wire. **The bundles are
  mostly dead cable.**
- Sourced hazard: they risk accidents and outages **especially in rain**, and can topple poles.

> **This validates Step 7.4's multi-strand change and gives it a rule.** Strands should be **unevenly
> bundled and visibly redundant** — several running parallel with slack, not one tidy catenary. `droop`
> already does the shape; the change is count and offset, which is a loop bound.

## Poles ⚠️ / ❌

⚠️ One LGU ordinance: **12 m poles** in CBD/Poblacion areas with **7.5 m clearance** from the top. NEA
standards for 13.2 kV and 24 kV lines specify pole-top assemblies for single-phase, vee-phase and
three-phase — so **the cross-arm silhouette varies by phase count**, a real and cheap variation axis.

❌ **Concrete vs wood pole material for rural barangays is UNSOURCED.** Do not assert either.
❌ **Pole-mounted transformer cans are UNSOURCED** — Wikipedia's spaghetti-wires article has nothing on
transformers.

> The builder already has 3 transformer cans across 12 posts. **Keep them — they are convention, and the
> ratio is plausible — but label them unsourced.** Vary cross-arm counts across the 12 posts instead;
> that variation *is* sourced.

## Tricycle ✅ construction, ⚠️ dimensions

- Sidecar built from **welded metal pipes, bars, and/or sheet metal**, locally made, affixed to an
  imported motorcycle.
- Capacity **four passengers up to six or more**, excluding the driver, with extras hanging on outside.
- **"Usually covered, though not always by the same roof structure."** ← the sidecar roof and the bike
  roof are separate, mismatched pieces. That mismatch is the silhouette.
- **"In rainy weather, a tricycle will be completely enclosed in a heavy plastic covering."**
- **"Often painted colourfully, like jeepneys,"** and **styles differ city to city.**
- Variants: **motorela** (enclosed four-wheel cabin), **garong / kulong kulong** (flat-bed, no roof, for
  market cargo).
- ⚠️ Sidecar ~**1.2–1.5 m long × ~1.0 m wide** — from an Alibaba product-insights page. **Low confidence.**
- ❌ Route/destination signage is unsourced.

> **The tricycle is the correct vehicle for this map and the jeepney is not.** Sourced: tricycles serve
> *"narrow roads or barangay pathways where larger vehicles cannot pass"* and are *"the first and last
> ride of the day."* Hero mesh #2 is a tricycle; **there is no jeepney in the shortlist and there should
> not be.**

## Waiting shed ✅ real, ❌ dimensions

Confirmed as a genuine funded barangay infrastructure category (LGU tenders in Iloilo City, Cagayan de
Oro, Tanauan, Binangonan). Sourced construction sequence: **clearing, formworks, concrete, masonry,
rebar, roofing, painting** — a concrete/CHB structure with a metal roof, ~24 days. The **roof and framing
is the dominant cost item.**

❌ Dimensions, bench arrangement, and the near-universal painted barangay/politician name are unsourced.

> **NOT in this plan, and worth saying why:** a waiting shed is a roofed structure, and Step 4.1 already
> refuses the covered court on sightline and collision grounds. The same reasoning applies. **But it is
> the single best candidate for a future addition** if the plaza ever needs one more landmark — it is
> small, it is at a road edge rather than over the spawn, and it is unambiguously Filipino.

---

## Sources

- [Covered Court Design Specifications (Scribd)](https://www.scribd.com/document/595800653/COVERED-COURT)
  — 28×15 standard, 12×7 minimum, 5 m setback *(issuing body unverified)*
- [Basketball court sizes compared — Junckers](https://www.junckers.com/sports-flooring/sports/basketball/basketball-court-sizes-nba-fiba-ncaa-and-high-school-compared)
- [Covered courts host wakes, pageants, circumcision rites — Inquirer](https://newsinfo.inquirer.net/1159100/covered-courts-host-wakes-pageants-circumcision-rites)
- [The basketball court as the modern-day plaza? — Daily Tribune](https://tribune.net.ph/2023/05/16/the-basketball-court-as-the-modern-day-plaza)
- [Shooting hoops, a Filipino passion — Rappler](https://www.rappler.com/sports/palarong-pambansa/4412-slam-dunk-a-love-story/) *(anecdotal)*
- [The Life and Afterlife of Filipino Fiesta Banderitas — Discover Philippines](https://www.discoverphilippines.org/p/the-filipino-banderitas)
- [Spaghetti wires — Wikipedia](https://en.wikipedia.org/wiki/Spaghetti_wires)
- ['No more spaghetti wires' — Manila Bulletin](https://mb.com.ph/2025/07/09/no-more-spaghetti-wires-manila-cracks-down-on-unregulated-cabling) ·
  [Philstar](https://www.philstar.com/nation/2025/07/10/2456925/manila-fights-spaghetti-wires)
- [Motorized tricycle (Philippines) — Wikipedia](https://en.wikipedia.org/wiki/Motorized_tricycle_(Philippines))
- [Sidecar Philippines — Alibaba product insights](https://www.alibaba.com/product-insights/sidecar-philippines.html) *(LOW CONFIDENCE)*
- [Ordinance regulating distribution lines — City of Tabaco](http://tabacocity.com.ph/2019/05/20/an-ordinance-regulating-the-installation-and-maintenance-of-distribution-lines-of-various-utilities-in-the-city-of-tabaco/)
- [NEA Standards for 13.2kV Distribution Lines (Scribd)](https://www.scribd.com/document/425175301/NEA-Standard-13-2kV-Transmission-Line)
- [Monobloc (chair) — Wikipedia](https://en.wikipedia.org/wiki/Monobloc_(chair)) ·
  [The history of the Monobloc — Domus](https://www.domusweb.it/en/design/2025/02/20/monobloc-chair-history.html)
- [Waiting shed in Iloilo City costs P200,000 more — GMA Regional TV](https://www.gmanetwork.com/regionaltv/news/111019/waiting-shed-in-iloilo-city-costs-p200000-more/story/)
- [Construction of Waiting Shed & Concrete Benches — Binangonan LGU (PDF)](https://binangonan.gov.ph/wp-content/uploads/2021/08/Construction-of-Waiting-Shed-Concrete-Benches-Municipal-Cemetery-Brgy.-Kaytome-June-25-2020.pdf)
