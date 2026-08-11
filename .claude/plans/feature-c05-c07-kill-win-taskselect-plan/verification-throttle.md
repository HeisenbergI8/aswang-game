# Verification: respawn-throttle stranding bug (RoundService.watchForDeath)

**Date:** 2026-08-11
**Scope:** `src/server/Services/RoundService.luau`, `watchForDeath`'s non-round-death branch
(lines ~246–259 on disk), specifically the `Config.Round.RespawnCooldown` throttle added on top of it.
**Rojo serving:** yes — `preflight -- --studio` reported `ok rojo-serve` (it also reported
`FAIL clean-tree`, expected on a feature branch with in-progress work; not a blocker for this check).
**Studio reachable:** yes — Place3, confirmed via `get_studio_state` before trusting any observation.
**SoloTesting:** on (set by the coordinator before this run) — `Debug.SoloTesting` /
`Debug.VerboseLogging` / `Debug.ForceAswangWhenSolo` = true, `Round.Intermission/Duration/EndScreen` =
8/45/6, `Round.RespawnCooldown` = 3. I did not change `Config.luau` and made no edits to it.

## Verdict

**CONFIRMED.** The suspected bug is real: a player who dies a second time within
`Config.Round.RespawnCooldown` (3s) of their previous non-round death is left permanently holding a
dead character. The throttle's `return` at `RoundService.luau:250` fires before
`player.Character = nil`, `character:Destroy()`, and `applyBodyRule(player)` on line 258, so none of
that cleanup runs, and nothing else in the codebase clears or reloads a non-nil `player.Character` —
`applyBodyRule`'s load branch is gated on `Character == nil` (line 123). Confirmed live in Studio, not
just by reading the code.

## What was reproduced

1. In INTERMISSION/LOBBY (`state.Phase` outside ACTIVE, so `watchForDeath` takes the non-round-death
   branch), killed the player's Humanoid (`Health = 0`). Unthrottled — `lastRespawnAt` was nil — so the
   character was correctly nil'd and destroyed, and RoundService's own `LoadCharacterAsync` respawned
   them.
2. The **instant** the new character instance appeared (no manual override — this was the player's own
   natural respawn, to avoid racing a stray in-flight `LoadCharacterAsync` coroutine from an earlier
   test that had produced a false "recovery" in an earlier, discarded attempt — see
   `artifacts/console-throttle-strand-repro.txt` for that methodology note), killed it again.
   Measured via `os.clock()` on the server: **0.626s after the first death** — inside the 3s cooldown.
   A locally-attached `Died` listener confirmed the Humanoid genuinely died (`diedFired = true`).
3. Checked `player.Character` immediately, then again ~9s later, then again ~71s later (spanning more
   than one full round cycle: INTERMISSION 8s → STARTING 4s → ACTIVE 45s → ENDING 6s, repeated).

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Second kill lands inside the 3s cooldown | PASS (0.626s measured) | `artifacts/console-throttle-strand-repro.txt`, "CLEAN TRIAL" section |
| `player.Character` immediately after throttled death | **STUCK** — same instance (`GetDebugId` `0_9193757`), `Health=0`, `GetState()=Dead` | `artifacts/console-throttle-strand-repro.txt`, "OBSERVED STATE IMMEDIATELY AFTER" |
| `player.Character` ~70s later (>1 full round cycle) | **STILL STUCK** — identical instance, still `Health=0`/`Dead` | `artifacts/console-throttle-strand-repro.txt`, "OBSERVED STATE ~70s LATER" and the final checkpoint |
| Client snapshot during the stranded window | `you: ALIVE`, `alive 1`, repeated across rounds #4/#5/#6 in the same window | console tail in `artifacts/console-throttle-strand-repro.txt` |
| Dealt into later rounds as ALIVE while dead | **YES** — PlayerState stayed Alive and the (single, forced-Aswang) roster kept including them every round while their real Character was the dead corpse | same console tail |
| Visual confirmation | Screenshot taken showing the "YOU ARE THE ASWANG" role card over a collapsed ragdoll on the spawn platform | captured via `screen_capture`, **not persisted to a file path** — the tool returns inline image data with no filesystem path available to this session; not citing a path for it, noted honestly in the artifact file instead |

**PASS/FAIL per the original ask:** FAIL — the player did **not** recover a body on their own. They held
the dead character for the full observed window (>1 round cycle) with no sign of self-healing.

## Why this is worse than "just" a stuck player

The console shows `PlayerState` stayed `Alive` and the solo roster kept dealing them into every
subsequent round (`alive 1`, `you: ALIVE`) while `player.Character` never changed. In this repo's own
words (§6.2/§6.4), the round state machine is exactly where this genre's bugs live, and a stranded
"alive" player is uncounted-for in only one direction — they still count toward `aliveCount`/roster and
remain eligible for future Aswang draws, but cannot act, see their surroundings move, or be interacted
with normally. This is consistent with what the exploit-auditor reportedly traced independently
(permanent-for-session strand, later rounds still deal them in as ALIVE, still Aswang-draw-eligible) —
this run adds live confirmation of exactly that from a running server, not just a second code read.

## Not Verified

The regression sweep requested in the original brief (Aswang-death-ends-round-immediately, normal
untimed respawn, transform/revert/keybind/secrecy checks) was **not run** in this pass — the coordinator
asked to stop after confirming/refuting the throttle bug and report immediately rather than continue
into the sweep. One incidental data point from the console tail: normal (non-throttled, >3s-apart)
deaths respawned correctly and repeatedly throughout this session (new `GetDebugId()` each time,
`Health` back to 100), so the un-throttled path itself is not implicated.

If a regression sweep is still wanted, it should be run as a separate pass — the Config debug values are
still in place (unchanged by this run) so it can proceed directly.
