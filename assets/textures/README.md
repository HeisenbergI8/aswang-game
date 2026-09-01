# textures/

Tileable surfaces, applied via `SurfaceAppearance` or `Texture`.

**Most texture needs should never reach this folder.** `generate_material` produces a MaterialVariant
built for seamless tiling, and image generators are notoriously bad at it. Use this folder only when a
surface genuinely could not be done as a material.

Set BOTH `Material` (the base) and `MaterialVariant` (the name) on a part — setting one silently does
nothing (`asset-pipeline`).
