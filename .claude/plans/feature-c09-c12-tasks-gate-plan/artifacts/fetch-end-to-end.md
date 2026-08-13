# Priority 2 — Fetch, end to end (pickup, carry, deliver)

Captured 2026-08-12, Studio place `Place3`, round with `TaskPoint_03` (FETCH) drawn.

## Pickup at the source, hands-free

Teleported to `FetchSource` for `TaskPoint_03` at `(-110, 0.5, 70)`. `FetchItem_TaskPoint_03` was
`Anchored=true` at `(-110, 0.5, 70)` before arrival. ~1.5s after arrival (one 4 Hz tick plus margin), its
`CFrame.Position` read `(-109.9997, 6.998, 69.999)` — jumped ~6.5 studs up, tracking the player's
`HumanoidRootPart` plus the carry offset. **No button press needed** — `tickFetch`'s proximity check
(`PresenceRangeStuds = 9`) picked it up automatically, matching `TaskService.luau`'s design.

## The item follows across a 125-stud teleport

Teleported carrying the item from the source to `TaskPoint_03` at `(15, 0.5, -30)`. ~1s later,
`FetchItem_TaskPoint_03` read `(15.0002, 6.998, -29.99997)` — it followed the full jump, confirming the
4 Hz re-anchor tick (`tickFetch`) is still running and not source-bound.

## Delivery over `FetchDeliverTime = 3`

Held `E` at the pad for 5s. Progress climbed cleanly and completed in the expected window:

```
[Task] 0/5 · here: 8%
[Task] 0/5 · here: 17%
[Task] 0/5 · here: 26%
[Task] 0/5 · here: 35%
[Task] 0/5 · here: 43%
[Task] 0/5 · here: 52%
[Task] 0/5 · here: 61%
[Task] 0/5 · here: 70%
[Task] 0/5 · here: 79%
[Task] 0/5 · here: 88%
[Task] 0/5 · here: 97%
[TaskService] Task complete: TaskPoint_03
[Task] 1/5 · here: 100%
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Client] Snapshot — ACTIVE round #1 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (84s left)
```

11 steps to 100% over a ~5s hold, consistent with `FetchDeliverTime = 3` (the delivery reads the
destination weight exactly like a HOLD task, per `TaskService.luau`'s `durationFor`). Once complete,
further presence correctly refuses with `ALREADY_COMPLETE`.

## What is NOT covered here

**Dying mid-carry and the drop.** I did not reach this test — see `verification.md`'s Not Verified
section. This record proves pickup, cross-map tracking, and delivery only.
