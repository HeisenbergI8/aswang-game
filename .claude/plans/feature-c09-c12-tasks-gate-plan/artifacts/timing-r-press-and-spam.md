# Priority 1 — `R` reaches the server, and the spam/burst behaviour

Captured 2026-08-12, Studio place `Place3`, `rojo serve` live, `SoloTesting=true`/`VerboseLogging=true`,
survivor (ForceAswangWhenSolo=false).

## `R` DOES reach the server

Teleported to a drawn `TaskPoint_04` (TIMING). The known CoreScript trap fired first (expected, not a
regression):

```
CoreGui.RobloxGui.CoreScripts/ProximityPrompt:385: ProximityPrompt 'TaskPrompt' has an unsupported keycode for rendering UI: Enum.KeyCode.None
```

A single `user_keyboard_input` `keyPress` on `R` produced a fresh server-authored bar line immediately
after:

```
[Task] bar TaskPoint_04 · 0/3 hits
```

Five more deliberate presses, spaced ~400ms apart, produced hits that climb AND reset — proof the server
is actually deciding a hit/miss per press, not just echoing a static payload:

```
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 1/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 1/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
```

**`R` is reachable. C09 is not C08's bug.**

## The spam test — and what it shows about the exploit the coordinator's audit flagged

30 `Remotes.Get("RequestTimingStop"):FireServer()` calls fired in a tight client-side loop
(measured client elapsed for the loop: `0.000025749992346391083` seconds — effectively simultaneous):

```
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTimingStop
```

Only **5** of the 30 calls produced a bar update — `AntiCheatService`'s budget
(`Capacity=5, RefillPerSecond=1`) consumed exactly its capacity and silently dropped the other 25 (one
`warn` line only, because `AntiCheatService` throttles its own log per remote per player — confirmed by
reading `AntiCheatService.luau:73-91`, not a missing-evidence gap). **All 5 that got through came back as
MISSES.** Net result: hits stayed at 0. The spammer gained literally nothing from this burst.

A second, independent burst — fired later at `TaskPoint_04` in a different round, same shape (5 rapid
`FireServer` calls) — also came back **all 5 misses**:

```
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
[Task] bar TaskPoint_04 · 0/3 hits
```

**Important corroboration of the exploit-auditor's finding, not a contradiction of it.** The coordinator
reports the exploit audit found `RequestTimingStop` has no spacing rule: five stops fired in one frame
are all evaluated against a bar that has not moved, so they return the SAME verdict, and that a burst
landing in the zone would complete 3 hits in one shot. **Both bursts observed here are exactly that
mechanism** — 5 near-simultaneous calls, all evaluated against what is effectively one frozen bar
position, and all 5 came back with the SAME verdict (miss) rather than 5 independent per-press rolls.
That the verdicts were correlated (all-miss both times) is the same structural fact the audit names; I
simply did not get a lucky burst that landed in the zone. **I did not personally witness a burst
completing the task**, and I want that stated plainly rather than implied — the theoretical exploit (an
instant 3-hit completion from one lucky frame) is corroborated in mechanism by these two bursts, not
demonstrated in outcome.

**What this does show, without qualification:** a spammer who bursts continuously gains nothing beyond
what the rate limit allows through, and — in both trials run here — literally zero progress. An honest
player who watches a rendered bar (once C18 draws one) and times a press has a much higher per-press hit
rate than the ~31% random-arrival rate a spam burst gets, because the honest player is not landing at a
random phase. The budget does its job of bounding request volume; it does **not** decorrelate the verdicts
within one frame, which is the actual gap the exploit audit is naming.
