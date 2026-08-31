# Artifact — item 6: no observable feedback to the blocked Aswang

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode.

## Static check (re-run independently, not taken on the implementation log's word)

```
grep -nE "WalkSpeed|SetAttribute|AddTag|Highlight|Sound|Animation|Humanoid|Camera|BodyVelocity|AlignPosition|ShowLine|FireAllClients" src/client/Controllers/GarlicController.luau
```

Returns 6 matches, all inside the header comment block (lines 23-34 and 58 — prose explaining what the
file must never do). Zero matches inside executable code, which starts after the header.

## Runtime check — the character's actual properties

Taken after the yaw-90 collision test in `artifacts/yaw90-collision-block.md` (character had just been
stopped by a collidable barrier):

```lua
-- execute_luau, Client
{
  WalkSpeed = humanoid.WalkSpeed,           -- 16 (Roblox default, unmodified)
  tags = CollectionService:GetTags(character),   -- {}
  rootAttributes = root:GetAttributes(),          -- {}
  characterAttributes = character:GetAttributes(), -- {}
  humanoidAttributes = humanoid:GetAttributes(),   -- {}
}
```

All empty; `WalkSpeed` at its unmodified default. No tag, no attribute, on the character, the root part,
or the humanoid.

## What this does and does not prove

**Confirmed:** the character carries no persistent marker (attribute, tag, or WalkSpeed change) either
during or after being physically stopped by a barrier. Combined with the static grep (no code path that
could write a `Highlight`, play a `Sound`, fire a camera effect, or call `OnboardingController.ShowLine`
for this controller), this covers every category the brief named.

**Not directly re-verified this session:** the placed-garlic bulb and its noise cue are *public* by
design (every client, including the Aswang, sees the same geometry and hears the same
`ITEM_USE` cue anyone would from a salt throw) — that is correct per the plan and is not a leak, since it
carries no player-specific information. `check:secrecy` also passed over the whole diff (see the main
report), which is a text-tripwire check rather than behavioural evidence, but it is one more layer in
agreement with what was observed directly here.
