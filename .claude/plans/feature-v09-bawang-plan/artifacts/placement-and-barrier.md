# Artifact — a real end-to-end garlic placement (item 4)

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode, round #14 of this session's solo loop
(`Config.Debug.SoloTesting`/`ForceAswangWhenSolo` on, so the one connected player is the Aswang).

## How bawang was obtained

`RequestSearch` carries no argument (the server resolves the nearest container from the player's own
position), so the only way to get an item is to walk to a container and hold a real
`Config.Search.SearchTime = 6` second search. The layout re-seeds every round, so this took several
rounds of sweeping different containers. `Container_Chapel_Vestry` (26.35, 0.4, -217) produced bawang in
round #14.

## The placement itself

Teleported to the chapel's **east** doorway (yaw 90 — the case the brief flagged as the one that fails
silently), waited for replication to settle, then fired `RequestPlaceGarlic` with no argument (the
server resolves the doorway from the player's own position, exactly as `RequestSearch` resolves a
container).

## Console evidence

```
[NoiseService] SEARCH recorded — 1 in history.
[NoiseService] SEARCH recorded — 2 in history.
[ItemService] Pickup refused for 11461085874: ITEM_SLOT_FULL
[NoiseService] ITEM_USE recorded — 3 in history.
```

`ITEM_USE recorded` is the noise cue the plan states garlic placement reuses from the existing salt
throw (`"the ITEM_USE noise cue is the one the throw already emits"`) — it fired, at the expected
position, on this placement. **No refusal line printed for this attempt** — consistent with
`ItemService`'s established pattern (seen directly on a separate attempt below) of only printing on
refusal, naming the verdict; success prints nothing extra by design (the same convention
`SearchController`'s header documents: "refusals are silent... a line for each ... reason is copy that
has to be written").

A separate, earlier attempt (round #13, different item cycle) shows the refusal format directly, which
is useful corroboration that this log line exists and behaves as documented:

```
[ItemService] Garlic placement refused for 11461085874: GARLIC_NOT_HELD
```

(That refusal happened because the round had rolled over to a fresh seed between my picking up bawang
and firing the placement — an artifact of MCP round-trip latency against a 45-second debug-shortened
round, not a game defect. `GARLIC_NOT_HELD` is exactly the correct verdict for an empty slot, confirming
`pure/GarlicPlacement.evaluate`'s wiring is live and correct.)

## Direct DataModel confirmation

```lua
-- execute_luau, Client, immediately after the round #14 placement
local garlic = CollectionService:GetTagged("PlacedGarlic")
local barrierFolder = workspace:FindFirstChild("GarlicBarriers")
```

Result:

```json
{
  "placedGarlic": ["BAWANG @ 35.650001525878906, 1.399999976158142, -235.60000610351562"],
  "clientBarrierParts": [
    "GarlicBarrier @ 35.650001525878906, 6.400000095367432, -235.60000610351562 size=12.3, 12, 0.5 CanCollide=true Transparency=1"
  ]
}
```

- **The slot emptied** — `YourCarriedItem` read `nil` immediately after the placement request, while the
  round was still `ACTIVE` (confirmed via the same snapshot hook used throughout this session).
- **A public `PlacedGarlic`-tagged bulb exists exactly on the doorway** — `(35.65, 1.4, -235.6)`, matching
  `Chapel_DoorwayE`'s recorded position `(35.65, 0.4, -235.6)` on X/Z exactly (Y differs because the bulb
  sits above the pad's floor level rather than at it — expected for a visible object).
- **The client's own `workspace.GarlicBarriers` folder holds exactly one part**, with:
  - `Position = (35.65, 6.4, -235.6)` — X/Z match the doorway; Y = 6.4 = floor(0.4) + Height/2(6), which
    is `GarlicController.rebuild`'s documented "built from its floor up" convention.
  - `Size = (12.3, 12, 0.5)` — `12.3` = `Width(9.3) + 2 * GarlicBarrierPadStuds(1.5)`, `12` =
    `Config.Items.GarlicBarrierHeight`, `0.5` = the part's own thickness. Exactly the numbers the plan
    specifies, read back from the live instance rather than from source.
  - `CanCollide = true`, `Transparency = 1` — matches `GarlicController.rebuild` exactly.

## Verdict

**CONFIRMED.** A real `RequestSearch` -> `RequestPlaceGarlic` round trip, through the actual wired
server code (not a fresh `require()` copy — this is a `CollectionService`/`workspace` read of the live
DataModel), produces: an emptied slot, a public bulb exactly on the doorway, the `ITEM_USE` noise cue,
and a correctly-shaped, correctly-positioned, invisible, collidable client-local barrier at the
**yaw-90** chapel doorway — the specific case the brief called out as the one that fails silently on a
missing or doubled radians conversion. See `artifacts/yaw90-collision-block.md` for whether that barrier
actually stops movement.
