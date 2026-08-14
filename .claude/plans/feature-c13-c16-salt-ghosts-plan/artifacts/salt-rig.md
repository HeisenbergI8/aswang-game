# Step 2.1 — the disposable `SaltSpawn` rig

**Run:** 2026-08-14, Studio Edit mode, place `Template_95206881_AutoRecovery_0.rbxl`, Rojo connected
(`ReplicatedStorage.Shared` present with Config/Enums/Remotes/Types + 13 pure modules).

**⚠️ PLACE CAVEAT.** This is the autorecovery file, not a deliberately opened place. The user was told
three times and chose to proceed. The rig is additive and `workspace.SaltRig_TEMP:Destroy()` removes it
entirely. **Nothing was published.** If the real place is a different file, this rig does not exist there
and Step 2.1 must be re-run against it.

## What was placed

Six anchored `Part`s tagged `SaltSpawn`, under one folder `workspace.SaltRig_TEMP`:

- `SaltSpawn_01` … `SaltSpawn_06`, size `3×1×3`, at `x ∈ {-50,-30,-10,10,30,50}`, `y = 0.5`, `z = 60`
- Institutional white, Sand material

Six rather than four (`Config.Salt.SpawnCount`), so the round genuinely *chooses* four of them —
a rig with exactly `SpawnCount` pads would never exercise the selection.

**Console output:**

```
[Rig] 6 pads under Workspace.SaltRig_TEMP; GetTagged sees 6
```

`GetTagged` seeing 6 is the part that matters: it proves the tag applied, which is the contract
`ItemService.discoverPool` depends on.

## The pool proofs

`server/pure/TaskPool.evaluate` was called directly against the live rig, with real `Config` values.
This is the same function `ItemService.discoverPool` feeds, so the verdicts are the ones the service
will produce.

```
RIG:   verdict=OK           unique=6  dupes=0
EMPTY: verdict=EMPTY        unique=0
DUPE:  verdict=DUPLICATE_ID unique=5  dupes=SaltSpawn_01
SHORT: verdict=SHORT        unique=2
Config: SpawnCount=4 PouchPoolSize=6
```

All four verdicts confirmed:

- **OK** — the rig as built is a valid pool.
- **EMPTY** — the plan required this be observable in the real engine rather than only in Lune. It is.
  `ItemService.reportPool` warns unconditionally on this verdict, which is what stops "no salt in the
  map" being a silent, unwinnable round.
- **DUPLICATE_ID** — two pads sharing a Name are detected and the duplicate is named.
- **SHORT** — fewer points than pouches.

## Screenshot

Captured from `(0, 40, 110)` looking at `(0, 0.5, 60)`. The six salt pads are the front row; the grid
behind them is C07's `TaskRig_TEMP`. **They are visibly separate**, which was the design requirement —
salt spawning on a task point would make the pickup tick and the presence tick indistinguishable in a
playtest, and the first bug report of the chunk would be unreadable.

## What this does NOT establish

- No pouch has spawned. That needs a running server (`ItemService.Start` → `spawnPouches` at STARTING).
- No pickup has happened. C13's acceptance criterion — "picks up two in a row and is refused the
  second" — is proven as arithmetic in `tests/salt-carry.test.luau` (38 assertions) and NOT in the
  engine.
- The `SaltSpawn` tag contract C17 must satisfy is unchanged: anchored BaseParts, unique Names, at
  least `Config.Salt.SpawnCount` of them, spread so two are not reachable from one standing position.
