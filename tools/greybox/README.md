# tools/greybox

The C17 barrio, as two scripts instead of a hand-built place.

Neither file is game code. They are not under `src/`, Rojo does not sync them, nothing `require`s them,
and `npm run verify` does not check them — they run **once per edit**, from Studio's command bar or
through MCP `execute_luau`, **in Edit mode**. Run them in Play and the geometry is discarded when you
press Stop.

## Why the layout is on disk when the map is not

`.rbxl` files are gitignored here: binary, merge-hostile, backed up only by Roblox's cloud version
history. So the map cannot be diffed, reverted, or reviewed.

The *layout* can. `barrio.luau` is the layout — every coordinate, zone and tag — so "we moved the chapel
40 studs south" is a line in a diff rather than something you remember doing.

## Running them

```
1. barrio.luau    in Edit mode. Destroys workspace.Barrio and rebuilds it.
2. measure.luau   in Edit mode, after. Reports crossing time, reachability and loops.
3. File → Publish to Roblox.        ← neither script can do this, and it is the only backup
```

`barrio.luau` is **idempotent**: it destroys `workspace.Barrio`, `TaskRig_TEMP`, `SaltRig_TEMP` and
`Baseplate` before building, so re-running after an edit applies the edit rather than layering a second
barrio on top of the first. Edit the file, re-run it, re-run `measure.luau`, publish.

## The one knob

`SCALE`, at the top of `barrio.luau`. Every coordinate is authored in scale-1 units and multiplied by
it, so re-sizing the whole barrio is one edit.

**It does not scale linearly and the file records why**: widening the map also widens every doorway and
every gap between buildings, so the navmesh finds straighter routes and the walk grows more slowly than
the arithmetic says. 1.0 measured 25.1s and 1.35 measured 30.2s, not the 33.9s that scaling 25.1 would
predict. Change it, re-run both, read the number — do not extrapolate from one reading.

## What `measure.luau` proves that a stopwatch cannot

§5 asks for alleys forming "loops, never dead ends". Walking an alley and coming out the far end shows
it connects two streets; it does not show there is a **second way round**, which is the actual property.

So the loop test seals each corridor with a temporary wall and re-checks that every task point is still
reachable from spawn. Still connected means that corridor was one of at least two ways through. Seven
corridors, one wall at a time, walls destroyed afterwards.

## If you change the map by hand in Studio

Fine — but the change lives only in the place file, and the next `barrio.luau` run destroys it. Port
anything worth keeping back into the generator, or accept that it is temporary.
