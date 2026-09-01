# assets/

Source images for the game. **Not synced into Studio** — `default.project.json` maps only `src/` and
`vendor/`, so nothing here reaches the DataModel by itself. Files here are inputs; `upload_image` is
what puts one into Roblox, and the resulting `rbxassetid://` is recorded in `docs/IMAGE-ASSETS.md`.

These files ARE committed, unlike the map. They are small, and they are the input the map was built
from — the one part of the art pipeline that can live in a diff.

Run by `.claude/skills/visual-pass/SKILL.md`.

| Folder | Holds | Generated? |
| --- | --- | --- |
| `references/` | real photos, downloaded | **never** — a generated reference is a hallucination you would then copy |
| `textures/` | tileable surfaces, for a `SurfaceAppearance` or `Texture` | rarely — prefer `generate_material` |
| `decals/` | non-tileable artwork: signage, paintings, posters, notices | yes — this is the main generation lane |
| `ui/` | icons Roblox primitives genuinely could not do | rarely — prefer `Frame`+`UIGradient`+`UIStroke` |
| `incoming/` | the drop zone. Save here; Claude files and renames out of it | — |
