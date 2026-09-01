---
name: visual-pass
description: Improve how something in the game LOOKS or MOVES — assess it in Studio first, fix everything the toolchain can fix, and hand back only the images a human must supply. Also the path for matching a target image the user provides. Load when asked to "enhance", "improve the look of", "make X look better", "make it realistic", "hyper realistic", "make it bigger"; when handed a reference or target image; and on any complaint about appearance or motion — "looks off", "looks small", "looks floating", "doesn't look right", "looks like blocks", "fix the shadow", "bouncing instead of walking", "it should be wandering".
---

# Visual Pass

The user has no art experience and no art budget. That is not a limitation to work around — it decides
the shape of this routine. **They should never have to describe a look in words.** They point at
pictures; the technical work is yours.

This skill exists because the default failure mode is real and was diagnosed here: research a thing on
the web, feed the prose to a generator, never look at the result, ship something the user did not want.
Prose is a lossy format for a look. Pixels are not.

Read `asset-pipeline` alongside this for what the tools can actually produce. That skill answers *what
exists*; this one answers *how a visual request is run*.

## Two directions

| Mode | Trigger | What happens |
| --- | --- | --- |
| **Request** | "enhance the bahay kubo" | You assess, fix what you can, and ask for the few images you cannot make |
| **Target** | user drops an image: "make it look like this" | You match it, then compare your result against it and iterate |

**Target mode wins any conflict.** You can judge readability in fog, silhouette legibility and the
mobile budget. You cannot judge taste. When the user supplies a target, your assessment of what "looks
good" is no longer the question — matching is.

## The routine

### 1. Look before you touch

Never start a visual pass from memory or from the code alone.

- `screen_capture` the subject from **at least three angles**, at night-lighting values, from a player's
  eye height. A thing that reads at editor-camera height in full light is a different object in play.
- Read the geometry that built it — the barrio is authored in `tools/greybox/barrio.luau`, not by hand.
- Name what is actually wrong in concrete terms: flat-shaded plastic, single-box where six parts belong,
  silhouette invisible against fog, no material variant.

**A pass that skipped the capture is a guess.** Say so if you skipped it rather than presenting the
output as assessed.

### 2. Fix everything in your own lanes first

Most of a visual improvement is not an image problem. Sort every gap into a lane and clear yours before
asking the user for anything.

| Need | Source | Whose lane |
| --- | --- | --- |
| Tileable surface — nipa, bamboo, mud, plaster, rust | `generate_material` | **Yours** |
| Geometry, proportion, part count, silhouette | Luau in `tools/greybox/` | **Yours** |
| Lighting, fog, `ColorCorrection`, `Bloom`, `DepthOfField` | `Lighting` properties | **Yours** |
| UI icons, panels, bars | `Frame` + `UICorner` + `UIGradient` + `UIStroke` | **Yours** |
| Existing models, meshes, decals | `search_asset` free + `insert_asset` | **Yours** |
| Reference — "what does a real nipa roof do at the eave?" | a real photo the user downloads | **Theirs** |
| Non-tileable artwork — signage, a santo painting, a poster, a notice | image generation | **Theirs** |
| Store icon and thumbnails | image generation, high effort | **Theirs** (§13) |

Two of those rows are load-bearing and get gotten wrong:

- **Generated reference is worse than real reference.** An AI render of a bahay kubo is a hallucination
  you would then copy. For the reference lane, tell the user **what to search for and download**, never
  what to prompt.
- **Image generators are bad at seamless tiling**, and `generate_material` is purpose-built for it. A
  texture request should almost never leave your lane.

### 3. Report in three buckets, always in this order

```
Done      — what changed, with a screenshot
Download  — real photos to fetch, with the exact search terms and destination folder
Generate  — image prompts, each with an exact destination filename
```

**"Done" must not be empty.** A pass that returns five prompts and an unchanged game did the wrong
thing — it moved the work to the person who cannot do it. If genuinely nothing was fixable without new
art, say that explicitly as a finding rather than letting an empty bucket imply it.

Keep "Generate" short. One or two prompts is a healthy pass; five is a signal you misclassified
textures or reference as artwork.

### 4. Wire in, then prove it

When the user says files have landed in `assets/incoming/`:

1. Move and rename to the right folder (below), and record the row in `docs/IMAGE-ASSETS.md`.
2. `upload_image` → `rbxassetid://…`. **Write that id into the manifest immediately** — it exists
   nowhere on disk otherwise, and the place file is not searchable.
3. Apply it, `screen_capture`, and show the result. An applied asset nobody looked at is not done.

## Writing prompts for game assets, not for pictures

A beautiful three-quarter render with its own baked shadows is **useless** as a decal. Every prompt you
hand the user carries these constraints explicitly:

- **Flat-on, orthographic, no perspective.** The game supplies the angle.
- **No baked lighting or shadow.** The game supplies the light. A shadow painted into the texture fights
  the scene and reads as dirt.
- **Transparent background** where the asset is not a full rectangle.
- **Tileable / seamless, edges wrap** — only if it genuinely must repeat, and expect it to fail; prefer
  `generate_material`.
- **Name the wear.** "Weathered", "rust stains", "faded", "sun-bleached" do more for this game's look
  than any amount of detail. The barrio is poor and it is night.
- **Silhouette over detail.** Fog and darkness erase surface detail and keep outline (`asset-pipeline`).

Always give the destination filename in the same line as the prompt, so there is nothing to decide:

```
→ assets/incoming/sign-sari-sari.png
  "Weathered hand-painted Filipino sari-sari store sign, faded red and yellow
   lettering on plywood, rust stains, flat-on orthographic view, no perspective,
   no shadows, transparent background"
```

## Target mode — matching an image the user gives you

State the **fidelity ceiling before you start work**, not after an hour of it:

| What they hand you | How close you can get |
| --- | --- |
| **Screenshot of a real Roblox build** | Closest. Everything in it is reproducible by definition |
| Concept art or an AI render | Palette, silhouette and mood — not literal |
| Photo of the real thing | Reference only; reality holds detail Roblox cannot |

So **ask for a Roblox screenshot** when the user is choosing what to send. It is free, it beats any
generated image, and it removes the "is this even possible" question entirely.

From a target, read off and write down: palette (name approximate hex), proportions, part count, roof
pitch, spacing, material families. Then build to those numbers and run the compare loop — capture from
the same angle as the target, put them side by side, name the largest remaining difference, fix that one
thing. Repeat. **One difference per round**, largest first; a round that changes five things cannot tell
you which one helped.

## Motion counts as look

"The villager is bouncing instead of walking" and "the pig looks floating" arrived as visual complaints
and they are handled here, not somewhere else. The user does not distinguish between a thing that looks
wrong and a thing that moves wrong, and neither should this routine.

Custom animation is out of scope (§3) and unauthorable by an agent (`asset-pipeline`). Everything below
is reachable without it:

| Complaint | Usually is | Fix |
| --- | --- | --- |
| "bouncing instead of walking" | a `CFrame` lerp with a sine on Y, or no ground clamp | drive it along the path and raycast to the ground each step |
| "looks floating" | pivot origin is the model centre, not its feet | offset by half the bounding box, or clamp to the terrain hit |
| "moves like a robot" | linear tween between waypoints | `Enum.EasingStyle.Sine`, vary the pause, jitter the heading a few degrees |
| "the walk looks wrong" | default R15 animation | insert a free Creator Store animation pack by asset id and swap the `Animate` values |

The last row is the one most often forgotten: Roblox publishes free R15 animation packs, and swapping
one in is an `insert_asset` and a handful of lines. It is the cheapest motion upgrade available and it
needs no authoring.

## Folders and the manifest

```
assets/
  references/   real photos, downloaded. NEVER generated. Input to your eyes only
  textures/     tileable, destined for a SurfaceAppearance or Texture
  decals/       non-tileable artwork — signage, paintings, posters
  ui/           icons that Roblox primitives genuinely could not do
  incoming/     the drop zone. The user saves here; you file and rename out of it
docs/IMAGE-ASSETS.md    the manifest — file, what it is, where applied, rbxassetid
```

Rojo maps only `src/` and `vendor/`, so `assets/` is **not synced into Studio** — it is a source folder
on disk, and it is committed. Unlike the map, these files are small and they are the *input* to it.

`docs/IMAGE-ASSETS.md` mirrors `docs/AUDIO-ASSETS.md` and exists for the same reason: an asset that
Roblox moderation pulls leaves a hole with no error and nothing in `git status`. The manifest row is how
anyone knows what used to be there.

## The budget still applies

Everything in `asset-pipeline`'s closing section binds here — `StreamingEnabled`, **~8 visible dynamic
lights**, modest part count, 30fps on a mid-range Android. A visual pass is exactly where those get
broken, because every fix is tempting and each one is individually cheap. Check the light count after
any pass that added atmosphere.
