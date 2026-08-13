# §4.4 anti-frustration rule: walking away freezes progress, it does not reset it

Captured 2026-08-12, same session as `hold-completion-and-spam-immunity.md`. Standing on `TaskPoint_12`
(active this round), fired the remote for a fixed **4.0-second** burst from 0%:

```
{"Elapsed":4.016,"Fires":241,"Dist":3.578}
```

Server console (round #5's fresh draw):

```
[Task] 0/5 · here: 3%
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTaskProgress
[Task] 0/5 · here: 6%
[Task] 0/5 · here: 9%
[Task] 0/5 · here: 12%
[Task] 0/5 · here: 16%
[Task] 0/5 · here: 19%
[Task] 0/5 · here: 22%
[Task] 0/5 · here: 25%
[Task] 0/5 · here: 28%
[Task] 0/5 · here: 31%
[Task] 0/5 · here: 35%
[Task] 0/5 · here: 38%
[Task] 0/5 · here: 41%
[Task] 0/5 · here: 44%
[Task] 0/5 · here: 48%
[Task] 0/5 · here: 51%
[Task] 0/5 · here: 54%
[Task] 0/5 · here: 57%
[Task] 0/5 · here: -
```

Stopped at **57%**. The trailing `here: -` is the client's own bar going blank once the heartbeat stopped
and `PresenceGraceSeconds` (0.75s) lapsed — `publishProgress` correctly has nothing to report once
`presence[userId]` is evicted, which is a **display** fact, not a server-progress fact.

## Left the radius

`character_navigation` to `(200, 5, 200)` — over 200 studs from every task point, nowhere near
`PresenceRangeStuds = 9`. Waited 5 seconds with **no** requests fired at all (simulating a player who
simply walks away and stops interacting, the literal scenario named in the Done condition).

## Returned and resumed

Navigated back onto `TaskPoint_12` (`Dist≈3.61`), then fired the remote for another 5-second burst:

```
{"Elapsed":5.001,"Fires":300,"Dist":3.608}
```

Console, continuing directly from the `-`:

```
[Task] 0/5 · here: -
[Task] 0/5 · here: 61%
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTaskProgress
[Task] 0/5 · here: 64%
[Task] 0/5 · here: 67%
[Task] 0/5 · here: 70%
[Task] 0/5 · here: 74%
[Task] 0/5 · here: 77%
[Task] 0/5 · here: 80%
[Task] 0/5 · here: 83%
[Task] 0/5 · here: 87%
[Task] 0/5 · here: 90%
[Task] 0/5 · here: 93%
[Task] 0/5 · here: 97%
[TaskService] Task complete: TaskPoint_12
[Task] 1/5 · here: 100%
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[TaskService] Refused progress for Demiurgos_18: ALREADY_COMPLETE
[Client] Snapshot — ACTIVE round #5 · tasks 1/5 · gate shut · alive 1 · you: ALIVE (4s left)
```

**Resumed from 61% — one tick above the 57% it was frozen at — not from 0%.** This is the definitive
proof of §4.4's stated rule: progress belongs to the world, not the player. Walking out of range for a
full 5-second gap (far longer than `PresenceGraceSeconds=0.75s`, so presence genuinely expired rather
than surviving on a technicality) neither decayed the value nor reset it; it simply stopped advancing
until presence was re-established, then picked up exactly where it left off and ran to completion.

This matches `TaskProgress.tick`'s own documented guard exactly: `weight <= 0` → "FREEZE, do not decay:
progress belongs to the WORLD, not to the player" — proven live, not just read in the source.
