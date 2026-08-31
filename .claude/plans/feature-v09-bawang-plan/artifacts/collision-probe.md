# Artifact — does a client-local collidable part stop the local character?

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode. The second foundational behaviour
V09's mechanism rests on: if this is false, the block does not work at all regardless of secrecy.

## Probe

```lua
-- execute_luau, datamodel_type = "Client"
local root = Players.LocalPlayer.Character.HumanoidRootPart
local humanoid = character.Humanoid

root.CFrame = CFrame.new(0, 5, 0)          -- clean start
task.wait(0.2)

local wall = Instance.new("Part")           -- collidable wall 6 studs ahead on +X
wall.Anchored = true
wall.CanCollide = true
wall.Size = Vector3.new(1, 12, 12)
wall.CFrame = CFrame.new(6, 5, 0)
wall.Parent = workspace
task.wait(0.2)

local startPos = root.Position
humanoid:MoveTo(Vector3.new(40, 5, 0))      -- walk toward and past the wall
task.wait(2.5)
local endPos = root.Position
```

## Result

```json
{
  "startPos": "0, 2.998018741607666, 0",
  "endPos": "4.944921970367432, 2.99642276763916, -0.08913438767194748",
  "wallX": 6,
  "crossedWall": false
}
```

The character walked from X=0 toward X=40 (2.5 seconds of `MoveTo`, which at default `WalkSpeed` would
easily reach X=40 with nothing in the way) and stopped at **X=4.94**, short of the wall's near face
(wall centre X=6, half-width 0.5, so face at X=5.5 — the character's own collision radius accounts for
the remaining ~0.5 studs). `crossedWall = false`: the character's physics visibly refused to carry it
past the part.

## Verdict

**CONFIRMED.** An anchored, `CanCollide = true` part created client-side genuinely stops the local
character's own simulated movement — the mechanism `GarlicController.rebuild` depends on
(`part.Anchored = true`, `part.CanCollide = true`, built the same way) works as designed.
