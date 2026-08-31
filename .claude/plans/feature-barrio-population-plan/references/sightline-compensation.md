# Phase 7 reference — the sightline question, answered from the geometry

**The brief asked what compensates for opening the two sealed kubo. The finding is that nothing needs
to.**

## What the builder's own comment claimed

`tools/greybox/barrio.luau`, in the `KUBO` table's header, defended `Kubo_E` and `Kubo_W` staying
sealed:

> "Their job is to BREAK SIGHTLINES so the sightline rule can be partial rather than absent: you can
> almost always see something, and almost never everything."

That is §5's rule and it is a real constraint. The question is whether a **door** costs any of it.

## What a door actually is, in this builder

`building()` constructs a side that has a door as **two wall segments with a gap between them**
(`tools/greybox/barrio.luau:388-391`). It does not remove the wall; it splits it. The other three sides
remain solid slabs, and the roof is untouched.

So after Step 7.1, each of these two houses is still a **closed 24 × 20 × 9 volume with one 10-stud gap
in one face**.

## Therefore

**Occlusion comes from the mass, and the mass does not move.** There is no axis along which a player
can now see through either house, because:

- Only one face of each has a gap.
- No two doors are opposite — `Kubo_E` has `W` alone, `Kubo_W` has `E` alone.
- The roof, which is what blocks a diagonal downward line, is unchanged.

What changes is that a player may now stand **inside**. That is a gameplay change, not a sightline one:
§5's rule concerns what is visible **from outdoors**, and from outdoors these houses present the same
silhouette they did before.

## What would invalidate this

**A second door on either of these two houses.** Two opposed doors cut a genuine window through the
building and the argument above collapses immediately.

That is why it is not left to a reader. `tests/barrio-interiors.test.luau` asserts **no kubo has two
opposed doors**, so this reasoning cannot be broken silently by someone adding a door for convenience.

## The risk that IS real, and where it is checked

Not sightlines — **routing**. Two new interior volumes and two new thresholds are two new places a
navmesh can behave differently. That is checked by `tools/greybox/measure.luau`'s loop test, which
seals each corridor in turn and re-checks reachability, and by its crossing time, which must stay inside
30–40 seconds.

That check has its own trap, recorded by the realism pass: `CollectionService:GetTagged` on a **dead
tag returns an empty list rather than erroring**, so a stale `measure.luau` once walked a fraction of
the map and printed a healthy crossing time over it. **Read its tag counts, not only its `ok`s.**
