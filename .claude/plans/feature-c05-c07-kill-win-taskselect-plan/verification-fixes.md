# Verification — four bug fixes (C05–C07), independent re-check

**Date:** 2026-08-11
**Scope:** the four fixes named in the brief — a death that isn't a kill (Fix A, all three
branches + two edge cases), corpse persistence across ENDING/INTERMISSION (Fix B), degenerate
range/cooldown fail-closed (Fix C), and `check:secrecy` on a typed-local payload (Fix D). This is a
re-run by someone who did not write the fixes, independent of `verification.md` and
`verification-playtest.md`, neither of which is overwritten here.
**Rojo serving:** yes — confirmed via `npm run preflight -- --studio` (`rojo-serve: ok`). The same
preflight run FAILed `clean-tree`; that is expected and correct — this whole plan's diff plus the
coordinator's five debug values are uncommitted in the working tree, exactly as described in the
brief. Not a defect.
**Studio reachable:** yes — `Place3`, confirmed via `get_studio_state` before and repeatedly during
Play.
**SoloTesting:** on. `Round.Intermission/Duration/EndScreen = 8/45/6`,
`Debug.SoloTesting/VerboseLogging/ForceAswangWhenSolo = true`. Set by the coordinator before this
session. **I did not edit `Config.luau`** — confirmed with `git diff --stat -- src/shared/Config.luau`
after the session, which shows only the coordinator's original change (47 insertions / 6 deletions,
one file). The coordinator owns reverting it.

Static checks (`npm run verify`, full `test:unit`) were not re-run in this pass beyond the two
named in the brief (Fix C, Fix D) — the tree is intentionally dirty with debug config, so a full
`npm run verify` would FAIL on `check:debug`/`config.test.luau` by design, not because anything is
broken. That is consistent with `verification.md`'s own static pass over this diff.

## Results

| Claim | Verdict | Evidence |
| --- | --- | --- |
| **Fix A branch 1** — death during ACTIVE: `[RoundService] Killed <id>; 0 alive.`, snapshot flips to `alive 0 · you: GHOST`, `player.Character` becomes nil | PASS | `artifacts/console-fixA-branch1-death-during-active.txt` |
| **Fix A branch 2** — a GHOST gets a body back when the round ends and everyone returns to LOBBY | PASS | `artifacts/console-fixA-branch2-ghost-to-lobby.txt` — reproduced 3 independent times (rounds 1, 3, 5), `you: GHOST` → `you: LOBBY` exactly at the ENDING→INTERMISSION transition, `you: ALIVE` again next round |
| **Fix A branch 3** — death outside a round (INTERMISSION/LOBBY) respawns with a **different character instance**, not GHOST | PASS | `artifacts/console-fixA-branch3-outside-round-respawn.txt` — `GetDebugId()` before (`0_8025072`) ≠ after (`0_8026220`); no `[RoundService] Killed...` line and no `you: GHOST` ever printed for this death; new character at full health (100) |
| **Fix A edge case** — die twice in quick succession | PASS | `artifacts/console-fixA-quick-succession.txt` — three rapid `Health = 0` writes on the same corpse produced no error, exactly one `Killed` line, `alive` never went negative |
| **Fix A edge case** — die right at a phase boundary | **NOT VERIFIED (precise timing) — see note** | see below |
| **Fix B** — corpse survives ENDING, cleared at INTERMISSION | PASS | `artifacts/console-fixB-corpse-persistence.txt` — `Corpse_TEST` present at ENDING round #7, absent by STARTING/ACTIVE round #8, console phase lines cited alongside each presence check |
| **Fix C** — `lune run tests/kill-validation.test.luau` | PASS | exit 0, output `PASS  kill-validation: 16 grid cells + 26 cases` — exact match to the brief's expectation |
| **Fix D** — `node .claude/scripts/check-secrecy.mjs --self-test` | PASS | exit 0, output `PASS  check-secrecy: 25/25 cases` |
| **Fix D** — `npm run check:guards` | PASS | exit 0, `- harness: 25 suite(s) ok` (25 named suites, all PASS, including `check-secrecy: 25/25`) |
| Round cycles cleanly, zero warnings | PASS | `artifacts/regression-transform-and-full-session.txt` — 11 consecutive full round cycles, zero warnings/errors from any game service (one self-inflicted Studio-Assistant script error is called out and is not a game line) |
| `T` still transforms; forced revert still fires at `MaxTransformTime` | PASS | `artifacts/regression-transform-and-full-session.txt` — live mechanical read: WalkSpeed 16→20→16, RootPart 2,2,1→2.3,2.3,1.15→2,2,1, torso color exactly `TransformedTintRgb` mid-transform and exactly default after revert; console shows `TRANSFORM witnessed` / `revert witnessed` twice |
| `F` still bound to `AswangKill` | PASS | `artifacts/keybind-regression.txt` — `ContextActionService:GetAllBoundActionInfo()` |
| `Players.CharacterAutoLoads == false` | PASS | `artifacts/secrecy-and-autoloads-regression.txt` |
| `GetAttributes()` / `GetTags()` empty on Player, Character, Humanoid | PASS | `artifacts/secrecy-and-autoloads-regression.txt` — `{}`/`[]` on all three, both calls |

### The phase-boundary edge case, honestly

I attempted to time a kill exactly at a phase transition (fired right as ACTIVE was about to end)
and could not land it: `Bash sleep` calls in this environment are capped well under the ~45s I
needed to reach the end of ACTIVE from a fresh round start, and by the time two chained shorter
sleeps plus the MCP round-trip latency had elapsed, the round had already advanced 1-2 full cycles
past where I intended to be. I will not claim a precise millisecond-level race was reproduced when
it was not — this is genuinely **NOT VERIFIED by direct observation**.

What I can say, from reading `RoundService.luau` directly (not from inference about behaviour, but
from the actual guard code):

- `watchForDeath`'s `Humanoid.Died` handler reads `state.Phase` **live**, not a cached value, at
  the exact moment `Died` fires (line ~218-221).
- `RoundService.MarkKilled` independently re-checks `state.Phase == Active` and
  `PlayerStates[...] == Alive` before doing anything (line ~512-519), and returns as a no-op
  otherwise.
- Luau/Roblox server scripts are single-threaded and cooperative — `setPhase` and the `Died`
  handler cannot interleave mid-write, so there is no window where a stale phase read is possible
  the way there would be in a genuinely concurrent runtime.
- Both branches a boundary kill could land in — the ACTIVE→MarkKilled path and the
  non-ACTIVE→respawn path — are independently confirmed correct above (Fix A branches 1 and 3).

That is a structural argument for why the race class does not exist here, not a live capture of it.
I am marking this **NOT VERIFIED** rather than PASS because the brief asked for it to be tried and I
could not reliably land the timing — a stronger claim would not be earned.

## Not Verified

Consistent with `verification-playtest.md`'s NOT VERIFIED list (not repeated in full) — specific to
this pass:

- **Die right at a phase boundary**, by direct timed observation. See note above; code-based
  reasoning offered instead of a live capture.
- **The kill's success path** (a real MonsterService-mediated kill, its corpse, cooldown-from-revert,
  `PlayerKilled` reaching a second client, `AlivePlayerCount` on another HUD, C06's attrition win).
  Unreachable solo — `ForceAswangWhenSolo` makes the only player the Aswang, so there is nobody to
  kill. Not attempted, as the brief anticipated.
- **A real corpse's persistence** — Fix B was tested with a stand-in `Corpse_TEST` part per the
  brief, not a corpse produced by an actual kill (which needs the unreachable success path above).
- Everything already on `verification.md`'s and `verification-playtest.md`'s NOT VERIFIED lists
  that needs two clients (mid-round join, a second client's view of `PlayerKilled`, the transform
  seen from another camera).

## Summary

**All four fixes hold.** Fix A's three branches all behave exactly as specified, including the
important branch 3 (death outside a round respawns with a genuinely different character instance —
confirmed by `GetDebugId()`, not just non-nil) and the quick-succession edge case (idempotent, no
double-count, no negative alive). Fix B's corpse survives ENDING and is cleared by INTERMISSION.
Fix C and Fix D both match their expected terminal output exactly. The regression sweep found
nothing broken across 11 full round cycles: zero warnings, `T`/`F` bindings intact, `CharacterAutoLoads`
false, no attribute/tag leak on Player/Character/Humanoid.

The only claim I could not independently confirm is the exact-tick phase-boundary race, which I am
reporting as NOT VERIFIED rather than rounding it up to PASS — I could not reliably time it given
this environment's sleep/latency constraints, and a code-level argument for why the race class
cannot occur is not the same evidence as watching it happen.
