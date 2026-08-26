# ASWANG — Roadmap (everything that is not the MVP)

**What this is:** the place `docs/MVP-SPEC.md` §3 sends things. If a feature is not in the spec, it
lives here, and writing it down is how it stops occupying attention.

**The rule that makes this file work:**

> **Your roadmap is your marketing calendar.** Every monster and map you *withhold* becomes a free
> TikTok video, a hype spike, and a reason lapsed players return. Shipping it all at launch spends the
> whole calendar on day one.

Nothing here is scheduled. Order is a rough guess at value, not a commitment.

---

## Retired from v1.3 — cut by the v2.0 mechanics rewrite

These were **built or specced and then removed.** They are here because they may be worth revisiting,
and because the reason they went is worth keeping.

| Cut | Why it went | Worth revisiting? |
|---|---|---|
| **The task system** — 5 of 12, four task types, the global bar | The objective and the danger were separate systems; lighting candles is not survival. Replaced by searching (§4.4) | **No.** This is the seam v2.0 exists to remove |
| **The escape gate** | Nothing to complete, so nothing to open | No |
| **Ghosts** — flying dead players, task contribution, the spook | Author preference; no tasks left to contribute to. Replaced by spectate + requeue (§4.7) | **Maybe** — if "dead players quit" degrades in analytics, ghosts were doing more work than assumed |
| **Amendment A2** — the Aswang's task progress counting | Died with the task system. Its *principle* survives in §4.4: the monster must be able to do everything a survivor does, sincerely | Principle already carried forward |
| **8-player servers** | The kill-everyone win condition is arithmetically unreachable above ~5 (§4.2) | Only if the win condition changes back |
| **The 30s kill cooldown** | Replaced by feeding (§4.3), which does the same job diegetically | No |

---

## Monsters — the highest-value updates you have

Each one is an update, a video, and a retention spike. **Ship them one at a time, months apart.**

- **Manananggal** — splits at the waist and flies; the lower half is left hidden. Salt the torso and it
  cannot rejoin. This is the strongest single addition on this list: it is a *different hunt*, not a
  reskin, and the counterplay is already folklore
- **Tiktik** — the call is loud when far and quiet when near. An inverted-proximity monster that turns
  audio into the whole mechanic
- **Kapre** — a tree-dweller; verticality and smoke
- **Tiyanak** — appears as something harmless. Directly attacks the trust layer
- **Multiple Aswang per round** — a mode, not a default. Changes the deduction maths completely

## Maps

- **Simbahan** (church) — one large interior, vertical, strong lighting moment
- **Palengke** (market) — daytime-adjacent, dense stalls, sightline chaos
- **Ospital** — corridors and rooms, the closest thing to a Granny layout
- **Balete forest** — no buildings, all fog and tall grass
- **Sakayan / boat crossing** — a map with no loops, which breaks the §5 rule deliberately, once

## Mechanics that were considered and deferred

- **Emergency meetings / voting** — a deliberate cut in v1.3 (§4.5) and still cut. Voting turns a
  survival horror game into a discussion game, and the quick-chat wheel cannot carry a debate
- **Albularyo's oil** — a carried vial that bubbles near the Aswang. A diegetic detector; the cost is
  that you must look down at it instead of around you. **Strong candidate**, held back only for scope
- **The ritual** — assemble salt + garlic + buntot pagi + holy oil + a lit candle at the chapel altar
  as an alternative win. A second win condition is already shipping; a third is scope
- **Aswang camouflage before the reveal** — permanently rejected. It head-counts (§4.3)
- **Microphone-driven silence** — permanently rejected on three independent grounds (§4.5)
- **Permanent safe rooms** — rejected; violates pillar six
- **A second or purchasable buntot pagi** — rejected; §C.5's exception depends on there being exactly one

## Progression and social

- Trading, guilds, pets, leaderboard seasons
- Seasonal events — **Undas** (Nov 1–2) is the obvious one and it is free thematic marketing
- Cosmetic tiers beyond the launch six
- A clan / barangay system

## Production

- Custom character animation and a real monster rig — §3 bans it for the MVP because §4.3 deliberately
  replaced it with a scale-and-colour tween that costs nothing
- Voice acting
- A second language pass (full Tagalog UI)

---

## Where ideas go to be judged

Before anything moves from this file into the spec, it answers four questions:

1. **Does it regenerate, or is it consumed?** Appendix C's root cause was consumable content.
2. **Can the Aswang do it sincerely?** Any action the monster cannot perform honestly becomes an
   oracle that identifies it (§4.4).
3. **Does it make safety and progress the same action?** Pillar six says they must never be.
4. **Does it read on a phone, in the dark, at 30fps?** Pillar five.
