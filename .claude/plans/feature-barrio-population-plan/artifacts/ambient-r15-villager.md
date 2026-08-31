# Artifact — R15 villager + camouflage-parity verification session

**Date:** 2026-08-29
**Studio session:** `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode throughout, `rojo:status` verdict `ok`
(blessed session `fc42e0d0-2cc1-429d-a8e2-bb667acb90bc`), Config debug values as briefed
(Intermission 8 / Duration 20 / EndScreen 6, SoloTesting / VerboseLogging / ForceAswangWhenSolo all
`true` — confirmed live via `require(ReplicatedStorage.Shared.Config)`, not assumed).

This file is additive. It does not overwrite `verification.md` or any existing artifact in this
directory, per instruction. Every claim below is marked **OBSERVED** (with the probe that produced it)
or **NOT OBSERVED** (with why).

---

## Q1 — Villager walks, not bounces — **OBSERVED**

Server-side probe sampling `HumanoidRootPart.CFrame:PointToObjectSpace(RightLowerLeg.Position).Z` at
0.3s intervals for 9s across all three `Ambient_VILLAGER_*`, restricted to samples where horizontal
speed > 1 stud/s:

```
Ambient_VILLAGER_16: swingZ[-0.7781..0.6222] range=1.4003 maxSpeed=4.46
Ambient_VILLAGER_17: swingZ[-0.7744..0.6273] range=1.4017 maxSpeed=4.46
Ambient_VILLAGER_18: swingZ[-0.7778..0.5179] range=1.2957 maxSpeed=4.46
```

**Confirms** the coordinator's 1.406-stud figure (1.2957–1.4017 measured, same order, small
per-sample variance expected from sampling phase).

Both tracks are present simultaneously on `Animator:GetPlayingAnimationTracks()` and their weights
move in the way a blend implies (idle 0.5→1.0, walk 0.001→0.5, inversely correlated over the same
window; walk `Speed` scaled 0.35–0.44 with measured travel speed, idle `Speed` pinned at 1.0):

```
idleW=0.500..1.000 (n=30) walkW=0.001..0.500 (n=30) idleSpd=1.000..1.000 (n=30) walkSpd=0.350..0.444 (n=30)
```
(identical shape on all three villagers)

## Q2 — No rig is sunk or floating — **OBSERVED**

First pass (long-range downward raycast) produced three nonsense outliers (−9.96, −12.94, −12.88)
that turned out to be the ray hitting a stilt-house floor/well ring **above** the rig rather than the
true ground beneath it — a probe-methodology artifact, not a game defect. Corrected to a short-range
probe (origin = rig's own bounding-box bottom + 3 studs, cast 10 studs down), then further refined to
only record samples during a run of **4+ consecutive frames of near-zero horizontal speed**, to
exclude the documented (Phase 4, carried forward) linear-interpolation Y-drift that occurs mid-travel
between two ground-correct endpoints — that drift is real, is not new, and is not what Q2 asks about.

Result, 12s / 48 samples per rig, confirmed-still frames only:

```
Ambient_CAT_1..PIG_9 (15 mesh-form rigs): avg within [-0.015,+0.018], range within ±0.13 studs
  — consistent with the documented breathing bob (~0.12-0.25 stud span, motion-parity.md)
Ambient_VILLAGER_16   avg=-0.1787 range=[-0.1801,-0.1774]
Ambient_VILLAGER_17   avg=-0.1788 range=[-0.1800,-0.1778]
Ambient_VILLAGER_18   avg=-0.1786 range=[-0.1798,-0.1774]
WORST CONFIRMED-STILL: Ambient_VILLAGER_16 err=-0.1801
```

**Confirms** the coordinator's claim precisely: 15/18 within ~0.1–0.13 studs (bob envelope, expected),
3/18 (all VILLAGER) at a tight, reproducible **−0.179 ± 0.002 studs** — a real, small, consistent
under-seating specific to the R15 rig path, distinguishable from bob/travel noise by the methodology
above. Not diagnosed to a root cause (candidate: `buildRigBody`'s `lift` is computed from
`GetBoundingBox()` against a rig built with a blank `HumanoidDescription` before any animation has
played a frame — if the idle/walk clips shift the rest pose's lowest point even slightly, the
bounding-box-derived lift would carry that as a constant bias). No screenshot taken of this
specifically; the numeric methodology above is the evidence.

## Q3 — Camouflage parity — **NOT OBSERVED, but the blocker is now root-caused (not a mystery)**

**Update: the six-attempts-of-total-silence mystery below is SOLVED.** Root cause found and confirmed
live, not inferred:

`validateAndCamouflage` reads the monster record with a bare table lookup —
`local monster = monsters[player.UserId]` — and returns **silently** (no print, no `CamouflageUpdate`)
if that is `nil`. `validateAndTransform`, by contrast, calls `stateFor(player.UserId)`
(`MonsterService.luau:1378`), which **creates** the record on first use. And `onPhaseChanged` calls
`table.clear(monsters)` on the way out of every ACTIVE phase (`MonsterService.luau:2767`), wiping every
player's record at round end.

So: in any round where the Aswang has not yet fired `RequestTransform` (or another action that
auto-creates the record), `monsters[player.UserId]` is `nil` for that whole round, and
`RequestCamouflage` produces **zero observable effect of any kind** — not a bug in camouflage itself,
just an unlogged early return that looks identical to "nothing happened" from every angle a client
(or a playtester) can see. All six of my earlier attempts happened either before ever transforming, or
in a later round after the transform+auto-revert had already cleared the table — hence total silence
every time, with `RequestTransform` (which auto-vivifies its own record) working perfectly the whole
time as a red herring that the remote pipeline was fine.

**Confirmed live, this session:** fired `RequestTransform` first, waited 1s, then teleported to
`AmbientSpawn_16_VILLAGER`'s pad (`-120.9, 0.4, -99.2`, well inside `ClaimRadius`=18) and fired
`RequestCamouflage`, **in the same round**. Result, captured via a direct
`CamouflageUpdate.OnClientEvent` listener:

```
captured=1
  [1] Verdict=CAMO_NOT_REVEALED
```

This confirms, end to end, live: `FireServer` → `AntiCheatService.Consume` → `RoleService.IsAswang` →
`monsters[userId]` (now populated) → `CamouflageRules.evaluate` → `CamouflageUpdate` back to the
client, all working correctly. It also confirms the reveal gate is real and is exactly what
`src/shared/pure/CamouflageRules.luau` documents: "Camouflage is locked until the Aswang has been
publicly revealed — that is, until it has taken a salt hit." `MonsterService.luau:413` sets
`HasBeenRevealed = false` on every fresh record and the **only** place it flips true is line 3096, on
a survivor's salt hit landing.

**This is a genuine, hard, solo-testing wall, structurally identical to the already-documented
`RequestKill` trap (V06) — one level deeper.** `ForceAswangWhenSolo` picks who the Aswang is; it does
nothing to manufacture a second player who can throw salt. With one client there is no path to
`HasBeenRevealed = true` at any `Config` value, so `CAMO_NOT_REVEALED` is not a bug and not something
retrying will get past. **A successful hide — and therefore the actual Q3 comparison (resting height,
animation-track weights/speeds, Humanoid properties, part count, name, tags, attributes on a puppeted
vs. a free villager) — needs a second connected client to land one salt throw first.** That is a
Test → Clients and Servers ≥ 2 session, not something this single-client run can produce at any
`Config` value.

**Net: Q3's underlying question is still unanswered, but for a fully understood, structural reason
now — not an unexplained silence.** I did not observe a puppeted villager, so I have no resting-height
or animation-state comparison to report; reporting one would be fabricated. Recommend: re-run this one
check with 2 clients (one throws salt at the forced Aswang, then the Aswang camouflages as VILLAGER),
which should take under a minute once multi-client is available — everything else needed (the pad
coordinates, the teleport, the transform-then-camouflage sequencing, the `CamouflageUpdate` listener
pattern) is proven above and ready to reuse.

## Q4 — Lighting — **NOT OBSERVED**
No screenshots were captured this session before context ran low. Needs a `screen_capture` from
behind the player in the plaza, and one street away from any lantern.

## Q5 — Kubo_NW house — **NOT OBSERVED**
No screenshots were captured this session. Needs `screen_capture` at the south face (door,
`z ≈ -105.4`) and west face (`x ≈ -139.5`) from ~20 studs, per the brief's coordinates.

## Q6 — Console: warnings/errors — **OBSERVED**

Across 17+ full round cycles (boot through many INTERMISSION→STARTING→ACTIVE→ENDING transitions),
the only console lines were:
- `[ProfileStore]: Roblox API services unavailable` — expected, Studio-only (no published place)
- `[Progression] DataStoreState is "NoAccess"` — expected, Studio-only
- `[Badges] 5 of 5 badge ids are unset` — expected, unset Creator Hub ids, unrelated to this change
- `[Community] Config.Community.GroupId is 0` — expected, unrelated to this change
- `[Bootstrap] SoloTesting is ENABLED — do not ship with this on.` — expected, the debug flag itself
- `[RoleService] DEBUG — Aswang FORCED to ...` — expected, `ForceAswangWhenSolo`

**No `[AmbientService]` warning ever appeared** — no rig or mesh failed to load, no form warned
missing a spawn point, across the entire session. **No error of any kind appeared.** This is a clean
result specific to the ambient-life population; it does not cover Q3/Q4/Q5 since those paths were not
exercised to completion.

---

## Known issues named by the coordinator (not re-derived here, recorded per instruction)

- **`wanderTick` steps a CLAIMED rig with `maxStep = math.huge`** (`AmbientService.luau:1186`) while a
  free rig is capped at `WanderSpeed * dt` ≈ 0.067 studs/frame (`:1247`). Per-frame displacement alone
  separates a puppeted rig from every free one, on any frame where the monster itself moved further
  than a free rig could in that frame. This is an open design question the coordinator is putting to
  the user, not something I re-verified or changed.
- **`ClaimSlot` now clears `targets[slotIndex]`** so a rig no longer snaps to its old wander target on
  the claim frame. **This session's Studio was running code from before that fix.** If a large
  one-frame jump at the moment of claim had been observed, it would be this already-fixed bug, not a
  new one — moot here since no claim was ever observed to succeed (see Q3).

## Not verified, stated plainly

- Q3's actual comparison (puppeted vs. free villager), Q4, Q5 in full (see above). Q3's *blocker* is
  now understood and confirmed live (`CAMO_NOT_REVEALED`, structural, needs a second client); it is
  the comparison itself that is still outstanding.
- No screenshot artifact accompanies this file. Every claim above is either a numeric probe result or
  a real remote-payload capture (both quoted verbatim), or an explicit "not observed."
