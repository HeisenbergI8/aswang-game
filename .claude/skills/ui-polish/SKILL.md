---
name: ui-polish
description: How to make this game's HUD read, feel, and survive a phone — motion vocabulary, mobile thumb zones and scaling, the secrecy rules that apply to UI specifically, and the polish checklist. Load before any change to UIController or a Controller that draws, before C26 (full HUD) and C27 (mobile), and whenever asked to "make the UI better", "add juice", or "polish this".
---

# UI Polish

The HUD already exists — `src/client/Controllers/UIController.luau`, 1600 lines, built at C18 as
*"ugly, functional, keyboard-first"* on purpose (BUILD-PLAN §2). This skill is about the pass that comes
after: **C26 — full HUD and the end screen**, and **C27 — mobile input and performance**.

The goal is not "make it pretty". It is three things, in this order:

1. **Readable in a dark, foggy map on a 6-inch screen.** §5's audience is ~60% mobile.
2. **Fast enough that it never costs a frame during a chase.** 30fps on mid-range Android is a
   non-negotiable in §5, and the chase is the worst case, not the lobby.
3. **Felt, not noticed.** A number that changes should move. A panel that appears should arrive. Nothing
   should dance.

**Polish is subtraction more often than addition.** In horror specifically, every panel you add costs
tension — see "The horror rules" below.

## The three constraints that outrank taste

Settle these before arguing about a colour.

### 1. Secrecy — where role-conditional UI is allowed

`PlayerGui` is **per-client**. A HUD that differs by role is safe there, and only there.

| Where it is drawn | Who sees it | Role-conditional? |
| --- | --- | --- |
| `PlayerGui` ScreenGui | only that player | ✅ safe |
| `BillboardGui` / `SurfaceGui` in Workspace | **everyone** | ❌ never |
| `Highlight`, `ParticleEmitter`, `Beam` on a character | **everyone** | ❌ never |
| A sound parented to a part | everyone in range | ❌ never — use a local `SoundService` play |

**Structural identity is the subtler half.** §4.4 gives the Aswang a *fake task list* precisely so its
screen looks like everyone else's. So role-conditional UI must differ in **content, never in shape**:
same panels, same positions, same sizes, same animations. A survivor's task bar that fills smoothly and
an Aswang's that stutters is a tell to anyone watching a stream or a shoulder.

The repo lesson `absence-is-observable` is the general form: **a leak here is a DIFFERENCE between
players, not a piece of data.** `check:secrecy` is a text tripwire and will not catch a shape difference.
If a UI change reads role state at all, `exploit-auditor` is the check that matters.

### 2. The mobile budget

- **Nothing interactive in the bottom-left or bottom-right corners.** Roblox draws the thumbstick and the
  jump button there. `LAYOUT.PromptLift` (36) and `LAYOUT.TouchBottomInset` exist for this reason —
  respect them, do not re-derive them.
- **Touch targets ≥ 44px after scaling**, and ≥ 48px clear of any screen edge (notches, Dynamic Island,
  gesture bars).
- **The top is not yours either.** The CoreGui logo/menu/chat cluster draws *on top* of an
  `IgnoreGuiInset` ScreenGui. `LAYOUT.TopInset = 76` clears it and the header comment records that the
  placeholder learned this the hard way. For anything hugging an edge that is not deliberately in the
  CoreGui's space, prefer `ScreenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` instead.
- **Test on a real phone.** C27's Verify line is `🧍 you, with a phone in your hand`. Studio's emulator
  gets the layout right and the framerate wrong.

### 3. Every number is already governed

`check:config` flags bare numbers in `src/`. The HUD's numbers live in three tables at the top of
`UIController.luau` — `LAYOUT` (pixels), `MOTION` (seconds), `COLOUR` (RGB triples) — each entry carrying
`-- config-ok: <why>`. **Add to those tables; never inline a literal at the call site.** A duration that
must agree with a balance value is not `config-ok` at all — `MOTION.TaskBar = Config.Round.SnapshotInterval`
is the pattern to copy.

Colours are **RGB triples, never `Color3` constants**, matching `Config`'s convention.

## Scaling — design at one size, scale once

The HUD is built in **offsets**, which the general Roblox advice ("always prefer Scale") calls a mistake.
It is not, for a HUD, *provided* one `UIScale` sits at the root of each ScreenGui and is driven from the
viewport. That is the standard reference-resolution approach and it keeps a 12px pad reading as 12px
rather than as a fraction of a phone.

```
scale = clamp(viewport.X / 1920, MinScale, MaxScale)
```

**Clamp the floor hard — this is the part the generic guides get wrong for HUDs.** A pure ratio puts a
414px phone at 0.22×, which makes a 18px label unreadable. Menus can shrink; a HUD read at a glance
during a chase cannot. Start around `0.6` floor / `1.6` ceiling, then let C27's real-phone test move it.
Whatever you pick goes in `LAYOUT` with a `config-ok` reason.

Corollaries:

- **`TextScaled` only on a full-screen takeover line** (the reveal already uses it). On HUD labels it
  produces a different type size in every panel, which is exactly the amateur tell. Fixed `TextSize` +
  `TextTruncate` + the root `UIScale`.
- **`UIListLayout` + `UIPadding` over hand-computed offsets** wherever a stack of things is being
  positioned. Manual `(Height + Pad) * order` arithmetic is how alignment rots.
- Recheck in Studio's Device Emulator (iPhone, iPad, 1080p) for *layout*; a phone for *framerate*.

## The motion vocabulary

The existing `tweenTo` helper and `EASE = Quad` are the house style. Extend that vocabulary; do not
invent a second one.

| Moment | Duration | Easing | Example here |
| --- | --- | --- | --- |
| Press / hover feedback | 0.10–0.15s | Quad Out | action buttons, quick-chat slices |
| A value changed | ~0.18s | Quad Out, overshoot ×1.35 | `MOTION.Pulse` — the countdown ticking |
| Panel arrives / leaves | 0.20–0.30s | Quad Out | task bar, status panel |
| Colour shift | ~0.25s | Quad Out | `MOTION.Colour` — timer going urgent |
| Full-screen takeover | 0.40–0.50s | Quad InOut | `MOTION.Fade`, `MOTION.RevealFade` |
| Dramatic beat | 1.0s+ | held, not eased | `MOTION.RevealHold` — the pause before the name |

**Rules that come with it:**

- **`Back` (overshoot) is rationed.** It is right for the reveal headline and for the quick-chat wheel
  opening. It is wrong for anything that fires every tick — an overshooting countdown is a twitch.
- **`Elastic` and `Bounce` are banned.** They read comedic. Wrong genre.
- **Never tween on `Heartbeat`.** Drive from the snapshot events; `MOTION.TaskBar` is tied to
  `Config.Round.SnapshotInterval` so the bar's motion and the data's arrival cannot disagree.
- **`TweenService:Create` allocates** — the file already documents this. Hoist `TweenInfo` constants
  rather than constructing one per call in a per-frame path.
- Only one thing should move at a time in a given screen region. Two competing animations read as a bug.

### The reveal is the one place to spend

§4.8 calls the end screen *"the screenshot people share"*, and C26's Done line says *"the reveal has
weight."* Its structure is already right and worth stating as the pattern: **headline lands → the room
holds (`RevealHold`) → the name arrives.** A name that appears at the same instant as the result is
information; the pause is what makes it drama.

## Performance — what actually costs on a phone

- **`Visible = false`, not `Transparency = 1`.** An invisible-but-visible branch is still walked and
  rendered; `Visible = false` lets the engine skip it entirely.
- **`CanvasGroup` is a trap.** It rasterises its children to one texture — great for fading a finished
  panel once, catastrophic for anything whose children change, because every child edit re-renders the
  whole texture. On low graphics levels its animations are throttled outright. Rule: **CanvasGroup only
  for a static panel that fades as a unit.**
- **Prefer `UIStroke` to layered shadow images.** One instance, tweenable (`Thickness`, `Color`,
  `Transparency`), no texture to download.
- **Prefer Roblox primitives to images, always.** `Frame` + `UICorner` + `UIGradient` + `UIStroke` covers
  the entire HUD in the spec, scales cleanly to every screen, and downloads nothing. This is also the
  honest workaround for the fact that **no tool in this project generates images** — see `asset-pipeline`.
- Don't leave dead ScreenGuis parented. Destroy or `Visible = false` on phase change.

## The polish checklist

Run this against a screenshot, not against the source.

- [ ] **One spacing unit.** `LAYOUT.Pad` (12) and multiples of it. Nothing at 7 or 15.
- [ ] **One type ramp.** The existing 18 / 20 / 34 / 44 is a ramp; new sizes must join it, not sit between.
- [ ] **One font family, two weights max.** Gotham / GothamBold is what is there.
- [ ] **Every text run has a scrim behind it.** The map is dark *usually* — a lantern or the sunrise will
      wash out unbacked white text at the worst possible moment. `LAYOUT.Scrim` (0.35) is the floor.
- [ ] **A consistent `UICorner` radius** across sibling panels. Pills use half-height, as the buttons do.
- [ ] **A subtle vertical `UIGradient`** on panels for depth. Subtle: the eye should not find the gradient.
- [ ] **Hierarchy is size and contrast, not colour count.** The countdown is the biggest thing on screen;
      everything else is dimmer (`COLOUR.Dim`).
- [ ] **Colour carries one meaning each.** Urgent red is urgency; it is not also the Aswang's theme
      colour on the same screen.
- [ ] **Nothing within 48px of an edge**, nothing in the two bottom corners.
- [ ] **Every state has a look.** Idle, hover, pressed, disabled, and — the one people forget — *waiting*.
- [ ] **Alignment is exact.** Misaligned by 2px is the single loudest amateur signal.

## The horror rules

Borrowed from the genre's own design literature, and they cut *against* generic UI advice.

- **Diegetic first.** Appendix C.3 already made the sky the round timer — *"a diegetic clock, no UI
  needed"*. Do not add a second prominent countdown competing with it. The on-screen timer is a
  confirmation, not the main event.
- **Information minimalism.** Show a thing at the moment it is needed and fade it when it is not. A task
  bar during the end screen is clutter; the status panel during a chase is a distraction from the map.
- **Let the world say it if the world can.** The heartbeat audio does what a proximity meter would do, and
  does it better, because it does not tell the player the exact number.
- **Partial information is the aesthetic.** §5's sightline rule — *"you should almost always be able to
  see something"* — applies to the HUD too. Fear comes from nearly knowing.
- **Never obscure the play space.** In a chase the player is looking at the world. Anything that grows to
  cover the centre of the screen during `Night` is a bug regardless of how good it looks.

## What cannot be automated here

| Want | Status |
| --- | --- |
| HUD motion, tweens, layout, theming | ✅ all code — this skill |
| Icons, logos, decals, custom fonts | ❌ nothing here generates images — `asset-pipeline`, or Creator Store, or a person |
| Character animations (a monster pose) | ❌ Animation Editor only, and §3 lists them ❌ OUT |
| The store icon and thumbnails | ❌ a real design job; §13 calls them 80% of whether anyone clicks |

## Done, and how it is proved

A polish pass is finished when:

1. `npm run verify` is green — including `check:config`, which will object to any bare number you added.
2. The `playtester` returns **a screenshot per phase plus both win reveals** — that is C26's Verify line
   verbatim, and screenshots are the only evidence a UI claim can have.
3. For anything touching C27: **a real mid-range Android, sustaining 30fps during a chase.** No agent can
   produce this. It is `🤝` in the build plan for that reason.
4. If the change reads role state anywhere: `exploit-auditor`, per CLAUDE.md's 🔒 row.

State which of these actually ran. A UI change that looks right in Studio and has never been on a phone
is unverified, and saying so costs nothing.

---

### Where this came from

- [Designing UI — Tips and Best Practices](https://devforum.roblox.com/t/designing-ui-tips-and-best-practices/3074034) (Roblox staff) — scale vs offset, topbar inset, mobile-first
- [Position and size UI objects](https://create.roblox.com/docs/ui/position-and-size) · [UI animation/tweens](https://create.roblox.com/docs/ui/animation) — official tween properties, CanvasGroup, easing
- [Design for performance](https://create.roblox.com/docs/performance-optimization/design) and the [CanvasGroup beta thread](https://devforum.roblox.com/t/canvasgroup-beta-group-transparency-on-ui-groups/1797885) — rasterisation cost, low-graphics throttling
- [Complete Roblox UI Scaling Guide](https://devforum.roblox.com/t/complete-comprehensive-roblox-ui-scaling-guide/2232510) · [RobloxAutoUIScaler](https://github.com/enc0ded/RobloxAutoUIScaler) — reference-resolution scaling and clamping
- [sentinelcore/roblox-skills — roblox-gui](https://github.com/sentinelcore/roblox-skills/blob/main/roblox-gui/SKILL.md) — the closest existing agent skill; container choice, UDim2 helpers, common gotchas
- [Making a Game Feel "Juicy" with Simple Effects](https://resprawn.medium.com/when-you-play-a-great-game-it-feels-good-d23761b6eccf) — feedback layering, and the too-much-juice failure mode
- [Dead Space: the UI art that disappears](https://medium.com/@lorenzoardeni/dead-space-the-ui-art-that-disappears-in-the-game-world-289718133c29) · [The Minimal HUD Paradox](https://medium.com/@salamatizm/the-minimal-hud-paradox-how-dreams-of-diegetic-game-interfaces-often-lead-to-cluttered-nightmares-e9cf7fae9d73) — diegetic UI, and when minimalism backfires
