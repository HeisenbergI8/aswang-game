# Delta check 3 — the new `spacingRespected` warning, both the negative and positive case

## Negative case — the normal rig, warning must be ABSENT

Round #1 and round #2 of `delta-1-hold-end-to-end.md` and `delta-2-nearest-incomplete-overlap.md` both
drew against the rig's committed 30-stud-pitch grid (`MinSpacingStuds = 20`). Full console transcripts
for both rounds are in those two files. Searched for the warning text in both: it does not appear.
`[TaskService] Pool OK — 12 task points.` and `[TaskService] Round tasks: ...` are the only
`[TaskService]` lines around each draw. Confirms `spacingRespected` is not inverted — it does not fire
when spacing is actually satisfiable.

## Positive case — pads clustered, warning must APPEAR

The brief flagged this as optional. Done anyway since it is the sharper test of the two (a warning that
never fires cannot be told apart from one that is wired backwards without seeing it fire at least once).

All 12 `TaskPoint` pads temporarily moved (Edit-mode `execute_luau`, a datamodel edit — not a script
write, so it does not touch `src/`) into a tight 4x3 cluster, 4 studs between columns / 6 studs between
rows, so every pairwise distance is well under `Config.Tasks.MinSpacingStuds = 20`.

Play started. Console, verbatim, around the draw:

```
[TaskService] Pool OK — 12 task points.
[RoundService] -> INTERMISSION (8s)
...
[RoleService] Drew 1 roles.
[RoundService] -> STARTING (4s)
[TaskService] Pool OK — 12 task points.
[TaskService] Task points are packed too tightly to honour Config.Tasks.MinSpacingStuds (20 studs); this round's tasks are not spread. Move the TaskPoint anchors further apart, or lower the setting.
[TaskService] Round tasks: TaskPoint_11, TaskPoint_01, TaskPoint_10, TaskPoint_04, TaskPoint_03
[Client] Phase -> STARTING (4s)
```

The warning fired, unconditionally (`Config.Debug.VerboseLogging` does not gate it — same property the
prior C08 session confirmed for the empty-pool warning), immediately after the draw and before
`STARTING` even finished, naming the exact config value (`20 studs`) and telling the reader what to do
about it. `spacingRespected` is wired the right way round.

## Rig restored

Play stopped, all 12 pads moved back to the exact original grid (`xs = {-45,-15,15,45}`,
`zs = {-30,0,30}`, `TaskPoint_(row*4+col+1)`). Verified by closest-pair scan afterward:

```
{"ClosestPairStuds":30,"ClosestPair":"TaskPoint_01<->TaskPoint_02","Count":12}
```

Matches `task-rig.md`'s original `"ClosestPairStuds":30` exactly (the pair name differs only because the
original scan happened to report `TaskPoint_03<->TaskPoint_07`, a different one of the many equally-close
30-stud pairs in the same grid — every adjacent pair in a 30-stud-pitch grid is 30 studs apart).

## Verdict

PASS on both the negative and the positive case — stronger evidence than the brief required.
