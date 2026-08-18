---
id: prove-input-at-the-remote-not-the-outcome
trigger: does the key work, keypress, nothing happens when I press, verify in studio, playtester, input bind, did it fire, prove it works
scope: studio
learned: 2026-08-18
evidence: C27 — a playtester spent ~500k tokens and stopped twice trying to prove E/R/Q/B still worked; four transient OnServerEvent listeners settled it in three calls
---

**Lesson:** To prove an input still works, record the REMOTE it fires — attach a transient
`OnServerEvent` listener, press the key, read what arrived. Do not drive the gameplay outcome.

**Why:** C27 extracted the keyboard verbs into `performAct` / `performTimingStop` / `performThrow`.
The obvious verification is "hold E and watch a task complete", and it needs a live round, a walk to
a drawn task point, 8 seconds of hold, and a console line — a chain where any link failing looks
identical to a broken bind. A playtester agent burned ~500k tokens on it and returned no result
twice. Four recording listeners on `RequestTaskProgress` / `RequestTimingStop` / `RequestThrowSalt` /
`RequestTrialThrow` answered it in three tool calls, and answered MORE: five heartbeats 0.26s apart
(matching `HeartbeatInterval`) that **stopped dead on key-up**, which is the release edge — the thing
a completed task would never have shown. It also cleared three `⚠ UNCONFIRMED` CoreScript-claim notes
standing since C08.

The general shape: **the boundary you changed is the thing to measure.** C27 changed key → wire, not
wire → outcome, so the outcome adds latency, flakiness and other people's bugs to the reading.

**Do:**
- Attach the probe on the SERVER, recording only, and disconnect it after: it is additive, changes no
  game logic, and Studio discards it on Stop. Log the arg COUNT — that is how the C18 missing-target
  bug would have been caught (`RequestKill` with 0 args instead of 1).
- Drive keys with `user_keyboard_input`, not by simulating what a key would have called.
- Assert the NEGATIVE too — which remote stayed silent. `RequestTrialThrow` not firing is what proved
  C22's routing survived.
- A remote firing is not the mechanic working. Say which one you measured.
