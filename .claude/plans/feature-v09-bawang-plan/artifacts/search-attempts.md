# Artifact — the search methodology, a bug in it, and the eventual bawang draws

Studio session `ab384d6d-f33b-419a-bb40-4a49c27fa039`, Play mode. **This artifact supersedes its own
first draft** — the initial round of container sweeps concluded "9/15 containers empty", and that
conclusion was wrong. Recorded here because the correction is itself worth keeping: it is a lesson about
testing methodology, not about the game.

## The bug in the first pass

Early attempts taught a `root.CFrame = ...` then `task.wait(0.2)` then immediately
`RequestSearch:FireServer()`. The console showed the real cause of most "empty" results:

```
[SearchController] SEARCH_NO_CONTAINER
[SearchController] SEARCH_NO_CONTAINER
[SearchController] SEARCH_NO_CONTAINER
...
```

`SEARCH_NO_CONTAINER` is a **server verdict**, echoed by the client
(`src/client/Controllers/SearchController.luau`'s `onUpdate`, printed under `VerboseLogging`) — it means
the server found no `SearchContainer` within `Config.Search.RangeStuds` (10 studs) of the player's
position **as the server saw it at the moment the request arrived**. With only 0.2s between teleporting
and firing, the server's copy of the character's position had not caught up before the request landed,
so most "searches" never actually engaged a container at all — they were not empty-container results,
they were range-refusals caused by a too-short settle time. One clean counter-example makes this
diagnosis certain: a server-side position read (`execute_luau`, `Server`) taken 1.0s after an identical
teleport showed the position correctly synced and well within range, and a search fired at that point
succeeded (recorded by `NoiseService`).

**The corrected method** uses a 1.0-1.2s settle wait after every teleport before firing `RequestSearch`.
Every attempt after that point either completed for real (`NoiseService` logged `SEARCH recorded`) or was
cleanly interrupted by a genuine round-boundary (`SEARCH_INTERRUPTED`) — never `SEARCH_NO_CONTAINER`
again once the settle time was long enough.

## What the corrected sweeps actually found

Across the session's later rounds (numbering continues from the same Play session):

| Round | Container | Result |
| --- | --- | --- |
| ~11 | (first of that round's batch) | SALT |
| ~11 | (second) | refused — `ITEM_SLOT_FULL` (still holding the salt) |
| ~12 | (four containers) | one more item found, refused pickup (slot full again) |
| ~13 | — | placement attempted, refused `GARLIC_NOT_HELD` (slot had cleared across a round boundary before the request landed — an artifact of tool round-trip latency against the debug-shortened round, not a game defect) |
| **14** | **Container_Chapel_Vestry** | **BAWANG** — see `artifacts/placement-and-barrier.md` for the full placement that followed |
| later rounds | several more containers | mostly empty or `ITEM_SLOT_FULL` refusals while already holding an item; no second bawang draw was pursued once round 14 succeeded |

The takeaway: **searching and item pickup work correctly** — the pool seeds, containers resolve by
server-side proximity, the hold takes the full `SearchTime`, `ITEM_SLOT_FULL` correctly refuses a second
pickup, and `YourCarriedItem` reflects the result — once the test methodology gave the server's position
read enough time to catch up with a teleport. The original "9 empty containers" conclusion in this
artifact's first draft should be disregarded; most of those were never real searches.

## What remains genuinely unknown

Whether every one of the 15 containers can hold bawang (only `Container_Chapel_Vestry` and
`Container_KuboNW_Chest` were directly observed producing it, across different rounds' re-seeds) is not
established either way, and does not need to be — `pure/ContainerLayout`'s draw is covered by
`tests/container-layout.test.luau` under Lune, which is the right layer for that property.
