---
name: asset-pipeline
description: How to get 3D models, materials, audio and images into this game with zero art budget — what can be generated, what must be sourced, and what an agent cannot do at all. Load before building any part of the map, before adding sound, and whenever asked to "make an asset".
---

# Asset Pipeline

The spec's art strategy is a real advantage, not a compromise: *"Horror is the most forgiving genre for
cheap art — darkness, fog, and lighting hide low-poly geometry"* (§5). And *"audio matters more than
visuals in horror… the cheapest fear-per-hour you can buy."*

So the goal here is never "make it look good". It is: **get something readable in place, and spend the
saved time on lighting and sound.**

## What is actually available — be honest about this

| Need | Tool | Status |
| --- | --- | --- |
| **3D models** | `generate_mesh` | ✅ generated from a text prompt, textured |
| **Parametric models** | `generate_procedural_model` | ✅ generated, with tunable attributes |
| **Surface materials** | `generate_material` | ✅ generated as a MaterialVariant |
| **Existing models, meshes, images** | `search_asset` + `insert_asset` | ✅ Creator Store + your inventory |
| **Audio** | `search_asset` (assetType `Audio`) | ⚠️ **sourced, never generated** |
| **Images / textures / icons** | — | ❌ **no generation available** |
| **Character animations** | — | ❌ **not scriptable at all** |

The last two are the honest gaps and they are covered at the bottom.

## 3D — generate first, source second

```
generate_mesh({
  textPrompt: "weathered wooden bahay kubo on stilts, thatched nipa roof, Filipino village house",
  size: { x: 12, y: 14, z: 12 },      // studs — approximate the real thing
  maxTriangles: 3000                   // 12–20000; keep it LOW, see below
})
```

**Keep `maxTriangles` low.** 60% of players are on mobile and the performance budget in §5 is
non-negotiable. A 20,000-triangle house you cannot see through fog costs the same frame time as one you
can. Start at 1,500–3,000 for props, up to 6,000 for a hero object like the chapel.

**Prompt for the silhouette, not the detail.** Darkness and fog erase surface detail and keep outline.
"Tall thin bamboo grove, dense" beats "photorealistic bamboo with individual leaf textures" — it is
cheaper, faster, and produces a better-reading shape in a dark scene.

`generate_procedural_model` is the better choice when you want to **tune it afterwards** — it produces a
model whose proportions are editable attributes, so the user can adjust it in Studio without regenerating.
Use it for anything that will need several variants: houses, fences, market stalls.

Pass `segmentation: "explicit"` with `partNames` when the parts matter for gameplay — a door that has to
open, a well you can stand in.

## Materials

```
generate_material({
  materialPattern: "Organic",
  materialId: "BarrioMud",
  baseMaterial: "Mud",
  materialDescription: "wet packed dirt path, tyre ruts, dark and uneven"
})
```

Returns a `BaseMaterial` and a MaterialVariant `Name`. Set **both** on the part: `Material` to the base,
`MaterialVariant` to the name. Setting only one silently does nothing.

`Regular` for man-made surfaces (planks, tiles, concrete), `Organic` for natural ones (mud, grass, rock).

This is the cheapest visual upgrade available: a correct material on a plain Part reads better in fog
than a detailed mesh with the default plastic finish.

## Audio — sourced, not generated

**There is no text-to-audio tool.** Nothing in this toolchain generates sound. What exists is search over
Roblox's Creator Store, which is exactly what the spec recommends — *"Use Roblox Creator Store audio
(licensed and free to use in experiences)"* — and it is genuinely enough.

```
search_asset({
  query: "night ambience crickets",
  assetType: "Audio",
  scope: "creator_store",
  priceFilter: "free",
  audioMinDuration: 30,      // ambience must LOOP, so it needs length
  audioMaxDuration: 180,
  maxResults: 10
})
```

Then `insert_asset({ assetId, assetName: "AmbienceNight", assetType: "Audio" })`.

**Duration filters are the whole trick.** They separate the two kinds of sound this game needs, and
searching without them returns a useless mix:

| Kind | Duration | Examples from the spec |
| --- | --- | --- |
| **Ambience** — loops, sets the room | 30–180s | night crickets, wind, distant dogs |
| **Stingers** — fires once, carries information | 0.2–4s | the transform cue, a scream, salt hitting, the heartbeat |

The transform stinger is the single highest-value sound in the game. Spec §4.3 says it *"carries ~40
studs"* — it is not decoration, it is the tell that makes the kill mechanic fair. Budget real time for it.

**Set `priceFilter: "free"` and prefer `verifiedCreatorsOnly: true`.** Audio licensing on Roblox is
enforced by moderation, and an asset that is pulled takes your ambience with it. Record every asset ID
you insert somewhere durable — the place file is not searchable and `git log` will not have it.

## Images — the honest gap

**No tool here generates images**, and neither Claude Code nor the Claude app can make one either.
`store_image` and `upload_image` both take images that ALREADY EXIST on disk or at a URL and bring them
in:

- `store_image(filePath)` → an `IMAGEID_` URI you can pass to `generate_procedural_model` as a reference.
- `upload_image(imagePaths)` → uploads to Roblox and returns `rbxassetid://…` for use as a Decal or
  `ImageLabel`.

Three ways to need no generated image at all, in order of preference:

1. **Build the UI from Roblox primitives.** `Frame` + `UICorner` + `UIGradient` + `UIStroke` covers
   essentially the whole HUD in the spec — the task bar, the sunrise timer, the quick-chat wheel. This is
   also better for mobile than images: it scales cleanly to every screen and costs no download.
2. **Use `generate_material`** for anything that is a *surface* rather than a *picture*. Wood, plaster,
   corrugated roofing, mud. This covers most texture needs.
3. **`search_asset({ assetType: "Image" })`** for genuine artwork — icons, signage, decals.

When an image genuinely IS needed, `visual-pass` is the routine: it triages what the toolchain can make
itself, then hands the developer a prompt and a destination filename for the remainder.

**The store-page icon and thumbnails are a different problem and are out of this pipeline's scope.** §13
calls them 80% of whether anyone clicks. They are a real design job, they need a person, and they are the
one place in the project where spending money or hours on art is clearly worth it.

## Animation — not available, and already out of scope

Roblox animations are authored in the **Animation Editor**, a Studio GUI plugin. There is no MCP tool for
it and no file format an agent can write. An agent can *play* an animation (`Animator:LoadAnimation`) and
*insert* an existing one by asset ID, but it cannot author one.

This costs nothing here, because the spec already put it out of scope: §3 lists **"Custom animations,
custom monster mesh, voice acting"** under ❌ OUT, and §4.3 explains why the design does not need them —

> *"It is **cheap to build** — no custom monster model needed. Reuse the player avatar with a scale
> change, a colour/material shift, glowing eyes, and a particle emitter."*

So the transform is built from properties an agent CAN set: `Humanoid.BodyDepthScale` and friends,
`BasePart.Color` and `Material`, a `PointLight` in the head, a `ParticleEmitter`, and `TweenService` to
move between the two states over `Config.Monster.TransformTime`. That is a tween, not an animation, and
it is fully scriptable.

If a bespoke animation is genuinely wanted later, the honest answer is: a person opens the Animation
Editor, or you buy one from the Creator Store with `search_asset({ assetType: "Model" })`.

## Where generated assets live, and why that matters

Everything on this page lands in the **place file**, not in Git. `generate_mesh` and
`generate_procedural_model` insert into the workspace; `insert_asset` parents into the DataModel.

That means:

- **`git status` will never show it.** Do not look for it there, and do not report a missing prop as a
  code problem.
- **Publish after an asset pass.** File → Publish to Roblox. Roblox's cloud place-version history is the
  only backup the map has (see `studio-sync`).
- **Record the asset IDs.** A Creator Store asset that gets moderated away leaves a hole, and without the
  ID you cannot tell what used to be there.

## The budget you are actually working against

From §5, all non-negotiable:

- `StreamingEnabled` on.
- **~8 visible dynamic lights maximum.** Many point lights are the #1 mobile FPS killer, and
  `Config.Performance.MaxVisibleLights` pins the number. Every generated prop that ships with a light
  attached counts.
- Modest part count; avoid unions where a part will do.
- 30fps on a mid-range Android, tested on a real phone.

A generated mesh with 18,000 triangles and two point lights is three budget violations in one insert.
Check before you keep it.
