# Research 04 — what actually lights a rural barrio at night

Feeds **Phase 8** entirely, and the lantern colour in **Step 4.2**. ✅ authoritative · ⚠️ weak or
motivated · ❌ could not source.

---

## 1. The barrio is electrified — but not uniformly ✅

DOE EPIRA status reports give household electrification as:

| Report | Period | Figure |
| --- | --- | --- |
| 45th EPIRA | May–Oct 2024 | **91.15%** (25.27 M of 27.73 M households) |
| 44th EPIRA | Nov 2023–Apr 2024 | **93.12%** (over 26 M of ~27.94 M) |

> **⚠️ These two consecutive official reports disagree by ~2 points and the LATER one is LOWER.** Cite the
> range, never a point value. Either way: **roughly 1 in 11 to 1 in 12 Philippine households has no grid
> electricity**, concentrated rurally. Region IV-A hit 100% in 2023 (the only fully electrified region);
> BARMM was lowest.

**Design implication:** a barrio in 2026 has power. The map should not read as pre-electric. But it should
not read as uniformly lit either — **some houses dark is accurate, not a rendering shortcut.**

## 2. Brownouts are normal, and the rural mechanism is sourced ✅

- Rotational brownouts are *"the temporary and alternating loss of electricity in certain areas while
  manual load dropping is being implemented,"* lasting *"from a few minutes to several hours."*
- **The rural mechanism, verbatim, and it is the useful part:** *"Many cooperative systems lack
  redundancy, with large parts of their local networks relying on **single feeder lines** or aging
  equipment, meaning that **even minor maintenance or weather-related damage can interrupt supply to
  entire barangays or towns.**"*

> **IMPORTANT — a whole-barrio blackout is a sourced, ordinary event, not a contrivance.**
>
> This is the most gameplay-relevant finding in the document and it is **deliberately not used in this
> plan.** A lights-out event would be a mechanic, and mechanics come from `docs/MVP-SPEC.md` §3, not from
> an art pass. It is not on the ✅ IN list.
>
> **Raised in the plan's Follow Ups as a design idea with real-world grounding, for the user to accept or
> reject at V16 — not built here.** Recording it because the research turned it up and it would be worse
> to lose it than to note it in the right place.

## 3. Streetlights — mixed colour temperature is the accurate look ✅

- **High-pressure sodium** produces *"warm yellow light between **1900 and 2200 Kelvin**"* with poor colour
  rendering that *"can inhibit vision at night and create **darker shadows**."*
- **LED retrofits** typically use **3000 K or 4000 K**, sometimes warm-specified at **2700–3000 K**, with
  CRI 70–80+.
- **The retrofit is incomplete and proceeds city-by-city:** Davao ordered ~40,000 streetlights converted to
  LED; Iloilo City replaced sodium-vapour on bridges and main thoroughfares; Quezon City proposed
  conversion in **11 barangays**.

> **This is the single best-supported art decision available for Phase 8, and it argues against what the
> map currently does.**
>
> The barrio's twelve street lanterns are all one warm colour (`WARM = 255, 206, 140`, roughly 2700 K).
> **A real barrio in 2026 is mid-retrofit: some poles still sodium at ~2000 K, some already LED at
> 4000 K.** Mixing them is:
>
> - **sourced**, unlike almost every other lighting choice available
> - **free** — it is a `Color3` per lantern, not a new light
> - **better horror.** Two colour temperatures in one street makes the space read as bigger and less
>   uniform, and the cold LED pools make the sodium ones feel warmer by contrast
>
> **Recommend: roughly 8 sodium (~2000 K, deep amber) and 4 LED (~4000 K, blue-white) across the twelve.**
> Keep all twelve tagged `MapLight`; nothing about the count or the culling changes.
>
> The sodium note that HPS *"creates darker shadows"* is worth taking literally — it supports the low
> `Ambient` that Step 8.1 argues for, rather than fighting it.

**⚠️ Sparseness is sourced only to commercial solar-lighting vendors**, who state that *"dark and unlit
streets are a common problem in many barangays and rural areas."* Motivated sources — but the DPWH/LGU
solar streetlight projects they cite are real. Useful spec if needed: **100–200 W solar fixtures on 5–8 m
poles** for main barangay roads, and **integrated solar LED units are the current rural default — a pole
with a panel on top and no wire running to it.**

> The builder's lanterns are 8-stud posts (~2.2 m), which is **short against the 5–8 m sourced figure**.
> Raising them would spread each pool of light wider and increase the dark gaps between — which is what
> §5's sightline rule wants. **But it also changes what the light reaches**, and the lantern spacing was
> tuned at C27 to hold `MaxVisibleLights = 8` by spacing rather than by count. **Do not change post height
> without re-reading the light cull behaviour.** Flagged rather than recommended.

## 4. The two things everyone assumes, and neither is sourced ❌

**Warm interior light spilling from windows — UNSOURCED, and the evidence points the other way.**

I could find nothing on Philippine domestic lamp colour temperature. What is available: **CFL and LED are
widely marketed for efficiency**, which argues for **cool/neutral interior light — fluorescent tube white
— not warm tungsten.**

> **This is worth a deliberate decision rather than a default, and it is genuinely counter-intuitive.**
>
> The instinctive horror-game choice is warm amber windows against a blue night. The available evidence
> suggests a real barrio house at night glows **cool white** from a bare CFL tube.
>
> **The cool-white version is arguably better here anyway:** it is more specific, it contrasts against the
> sodium streetlights instead of blending into them, and a hard cold rectangle of window light in a warm
> street is more unsettling than another amber glow.
>
> **This is an art decision for Step 4.5's approval gate**, not something the plan should settle silently.
> Recorded here so the question actually gets asked.

**Wet-ground reflection — UNSOURCED. Pure rendering choice.**

The builder already leans on this hard: ten puddles, described in its own comment as *"the highest ratio
of atmosphere to parts in the whole file."* That judgement stands on its own merits — it just has no
research behind it, and should not be presented as if it does.

**Candles or gas lamps as rural lighting — searched, found nothing.** The sourced modern brownout response
is **rechargeable emergency lights (10–15 h backup)**, not candles.

> So: **candles belong on the graves** (✅ sourced as offerings — see research-03) **and in the chapel**
> (✅ sourced as an interior element). **They do not belong in houses as general lighting.** The map's
> existing `Chapel_Candles` light is on the right side of that line.

---

## Summary of what Phase 8 should actually do

| Change | Confidence | Cost |
| --- | --- | --- |
| Mix sodium (~2000 K) and LED (~4000 K) across the twelve lanterns | ✅ sourced | free — a `Color3` each |
| Keep `Ambient` low; deep shadow between lights is accurate | ✅ HPS "darker shadows" | free |
| Cool-white rather than warm interior window light | ❌ inferred, counter-intuitive | free — **ask at 4.5** |
| Some houses unlit entirely | ✅ 91–93% electrification | free |
| Wet ground / puddle reflection | ❌ unsourced, keep anyway | already built |
| Raise lantern posts toward 5–8 m | ⚠️ vendor-sourced | **risks the C27 light spacing — flagged, not recommended** |
| A barrio-wide blackout event | ✅ sourced as ordinary | **out of scope — §3. Follow Ups only** |

---

## Sources

- [DOE EPIRA Status Reports (45th and 44th)](https://doe.gov.ph/site/epimb/articles/group/reports?category=Status+Report+on+EPIRA+Implementation&display_type=Card)
  — 91.15% and 93.12% household electrification, consecutive periods
- [2023–2032 National Total Electrification Roadmap — DOE](https://legacy.doe.gov.ph/announcements/2023-2032-national-total-electrification-roadmap)
- [Electricity Supply Interruptions in the Philippines — PIDS (PDF)](https://pidswebs.pids.gov.ph/CDN/document/pidsdps2248.pdf)
- [Rotational Power Outages in the Philippines — Solaren](https://solaren-power.com/power-outages-philippines-rotational-guide/)
  — single-feeder rural fragility *(vendor, but the mechanism is specific)*
- [EXPLAINER: Why rotational brownouts occur — GMA News](https://www.gmanetwork.com/news/topstories/nation/987827/explainer-why-rotational-brownouts-occur/story/)
- [HPS Color Temperature — Access Fixtures](https://www.accessfixtures.com/leds-that-look-like-hps/) — HPS 1900–2200 K
- [LED vs High-Pressure Sodium Street Lights — OAK LED](https://www.oakled.com/blogs/comparison-between-led-street-lights-and-high-pressure-sodium-lights/)
- [4,000 sodium streetlights turned to LED — SunStar Davao](https://www.sunstar.com.ph/davao/local-news/4000-sodium-streetlights-turned-to-led) ·
  [Iloilo City street lights go LED](https://www.iloilotoday.com/iloilo-city-street-lights-go-led/) ·
  [QC dads see the 'lights' — Inquirer](https://newsinfo.inquirer.net/488977/qc-dads-see-the-lights-want-p27m-deal-inked/amp)
- [Solar Street Lights for Barangay and Subdivisions — Grand Philippines](https://grandphilippines.com/blog/solar-street-lights-for-barangay-subdivisions/) *(vendor)*
- [How Solar Street Lights Improve Safety in Dark Roads and Barangays](https://iwatchyou.ph/blog/?bmode=view&idx=167970012) *(vendor, motivated)*
