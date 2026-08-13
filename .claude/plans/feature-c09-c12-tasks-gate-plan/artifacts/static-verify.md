# Static verification — analyze, lint, checks, unit tests, harness

Captured 2026-08-12, before any Studio testing.

## `npm run verify` (chained: analyze && lint && fmt:check && check:remotes && check:secrecy &&
check:config && check:scope && check:ratelimit && check:debug && test:unit && verify:harness)

Stops at `check:debug`, as expected — the coordinator's debug values are deliberately live for this run:

```
- analyze: ok
Results:
0 errors
0 warnings
0 parse errors
- remotes: ok (21 declared, 13 wired)
        8 declared but not yet wired: SaltEffect, QuickChatBroadcast, ProfileUpdated, RequestThrowSalt, RequestQuickChat, RequestGhostSpook, RequestEquipCosmetic, RequestClaimDaily
- secrecy: ok (the Aswang stays server-side)
- config: ok (balance stays data-driven)
- scope: ok (17 out-of-scope shapes watched)
- ratelimit: ok (every OnServerEvent consults AntiCheat)
  FAIL  src/shared/Config.luau — Debug.SoloTesting = true, must be false
  FAIL  src/shared/Config.luau — Debug.VerboseLogging = true, must be false
        A debug switch in a committed tree ships to players. Revert it before committing.
- debug: 2 finding(s)
```

`lint` and `fmt:check` produced no FAIL lines, so both passed silently between `analyze` and `remotes`.
analyze/lint/fmt/remotes/secrecy/config/scope/ratelimit are all **PASS**. `check:debug`'s two findings
are the coordinator's intentional debug values, not a defect — the coordinator is reverting them after
this report.

## `npm run test:unit` (run separately, since `verify` short-circuited at check:debug)

```
  PASS  anti-cheat-budgets: 9 remotes budgeted + 8 invariants
  PASS  body-transitions: 20 cells + 4 properties
  FAIL  solo testing is off — this must never be true on a published place
  FAIL  a round is long enough to actually be played — Duration=150s — a testing value left in?
  2 balance invariant(s) violated
  PASS  fetch-carry: 642 assertions over the full 512-cell grid
  PASS  gate-escape: 99 assertions over the full 64-cell grid
  PASS  kill-validation: 16 grid cells + 35 cases
  PASS  player-body: 8 cells + 3 properties
  PASS  role-draw: shape, determinism, weighting, 10000 rounds, degenerate rosters
  PASS  round-transitions: 20 exhaustive cases + 3 invariants
  PASS  task-list-view: 32 assertions over every decoy length, both roles
  PASS  task-participants: 133 assertions over every PlayerState x Role pair
  PASS  task-pool: 14 assertions across 8 pools
  PASS  task-progress: 20 assertions, incl. the non-scaling property
  PASS  task-resolve: 33 assertions — overlap in both orders, NaN and both infinities
  PASS  task-selection: 10000 draws, 12 distribution bands, spacing + 6 edge cases
  PASS  task-weight: 8-cell PlayerState × Role grid + 10 value assertions
  PASS  timing-window: 2067 assertions over 9 configurations
  PASS  token-bucket: steady state, burst, refill, backwards clock, degenerate cost, purity
  PASS  transform-rules: 6 verdicts, 5 phases, 4 player states, cooldown boundary, precedence
  PASS  win-conditions: exhaustive grid over roster × kills, + departure and boundary properties
- test:unit: 1/20 file(s) failed
```

The one failure is `tests/config.test.luau`, and it fails **exactly because** `SoloTesting`/`Duration`
are the coordinator's intentional debug values — this is the test working correctly, not a regression.
19/20 suites pass, including the two new grids this plan added (`fetch-carry`: 642 assertions,
`gate-escape`: 99 assertions) and `timing-window` (2067 assertions).

## `npm run check:guards` (harness self-tests, unconditional)

```
  PASS  task-driver: 29/29 cases
  PASS  build-trigger: 10/10 cases
  ... (24 more, all PASS)
  PASS  run-luau-tests: 4/4 cases
- harness: 26 suite(s) ok
```

All 26 harness suites pass.

## `npm run preflight -- --studio`

```
  ok    toolchain
  ok    tree-green
  FAIL  clean-tree — dirty tree — cannot attribute the diff
  ok    rojo-serve
```

`rojo-serve: ok` — Studio evidence below is live-synced. `clean-tree` fails because the working tree
carries this plan's whole uncommitted diff plus the coordinator's debug values, which is expected at this
stage and not a defect.
