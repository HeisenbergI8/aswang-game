# Verification: V03 — SearchService, containers and the layout seed

**Date:** 2026-08-27
**Scope:** `.claude/plans/feature-v03-search-containers-layout-plan/` — all 4 phases (`ContainerLayout`,
the network surface, `SearchService`, and the client's `SearchController`/`InputController` wiring).
Diff: `src/server/pure/ContainerLayout.luau` (new), `src/server/Services/SearchService.luau` (new),
`src/client/Controllers/SearchController.luau` (new), `tests/container-layout.test.luau` (new), plus
edits to `Types.luau`, `Remotes.luau`, `Config.luau`, `InputController.luau`, `UIController.luau`,
`init.server.luau`, `init.client.luau`, `anti-cheat-budgets.test.luau`, `config.test.luau`.
**Rojo serving:** yes. `npm run preflight -- --studio` reported `rojo-serve` ok, `rojo-attached` ok,
`rojo-synced` ok (the only `clean-tree` line failed, and that is the plan's own uncommitted work,
named as expected in the brief — not a sync problem).
**Studio reachable:** yes. `aswang.rbxl` (studio id `ab384d6d-f33b-419a-bb40-4a49c27fa039`), driven
live through Play mode for this entire session.
**SoloTesting:** on, set by the coordinator before this run (`Round.Intermission=8`, `Duration=20`,
`EndScreen=6`, `Debug.SoloTesting=true`, `Debug.VerboseLogging=true`). Confirmed unchanged at the end
of this session — `git diff --stat src/shared/Config.luau` still shows only the plan's own diff, no
edits from this run. Not reverted by me; the coordinator owns that step.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` — 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | part of `npm run verify`, both `ok` |
| repo checks | PASS (4/5), 1 expected-red | `remotes: ok (25/25)`, `secrecy: ok`, `config: ok`, `scope: ok`, `ratelimit: ok`; `check:debug` reports 2 findings (`SoloTesting`, `VerboseLogging`) — the debug values the coordinator set on purpose, not a regression |
| unit (Lune) | PASS (28/29 files), 1 expected-red | `npm run test:unit`: `container-layout` PASS (13 assertions), `search-pool` PASS (14 assertions), all other 26 pure-module suites PASS; `config.test.luau` fails 3 checks (`SoloTesting`, round `Duration`, session-retry timing) — the same debug values, not a code defect |
| behavioural | PASS | `artifacts/01-seed-and-tags.txt`, `artifacts/02-search-remote-hook.txt`, `artifacts/03-interruption.txt`, `artifacts/04-already-searched.txt`, `artifacts/05-secrecy.txt` |

## The five claims

**1. The layout seeds at STARTING — PROVEN.** `artifacts/01-seed-and-tags.txt`. Confirmed the 15
`SearchContainer`-tagged parts are actually present in the *running* DataModel (queried live via
`CollectionService:GetTagged`, not just read off disk), then captured the console line on every one
of 7 observed round cycles:
```
[SearchService] Container pool OK — 15 containers.
[SearchService] Seeded 7 item(s) across 15 containers.
```
The `NO "SearchContainer" PARTS IN THE MAP` warn never appeared in any of the 7 rounds — the tags
reached the running game.

**2. Searching yields items — PROVEN, for both required outcomes.** `artifacts/02-search-remote-hook.txt`.
`SearchController.luau` only prints for refusal verdicts — `SEARCH_STARTED` and `SEARCH_OK` are
silent by design (they route to `OnboardingController.ShowLine`, not `print`), and round-cycle log
volume evicts the console buffer inside a couple of round lengths. Per the lesson
`prove-input-at-the-remote-not-the-outcome`, I injected a persistent listener on
`Remotes.Get("SearchUpdate").OnClientEvent` via `execute_luau` that appends every payload to a global
table — test-only instrumentation added at runtime through the MCP bridge, nothing under `src/`
touched. A real held `E` keypress was then driven through `user_keyboard_input` against the live
Client datamodel (the actual `ContextActionService:BindAction` path, not a direct remote call).
Captured, in order:
```
SEARCH_STARTED (Hold=6)  ->  +6.13s  ->  SEARCH_OK (Found=nil)      -- an empty container
SEARCH_STARTED (Hold=6)  ->  +6.22s  ->  SEARCH_OK (Found="BAWANG") -- an item-yielding container
```
Both completions land ~6.1-6.2s after start, matching `Config.Search.SearchTime = 6` plus the 0.25s
server tick and MCP call slack. A screenshot of the "Empty." result rendering live via
`OnboardingController` was viewed during the session but could not be saved to `artifacts/` — the
`screen_capture` tool returns the image inline with no filesystem path this session could recover, so
it is not cited as a file. The remote-hook capture above is the artifact of record for this claim and
is more precise than a screenshot would have been.

**3. Interruption releases the hold — PROVEN (live capture + source corroboration).**
`artifacts/03-interruption.txt`. A live capture caught a genuine mid-hold release:
```
SEARCH_STARTED (Hold=6)  ->  +0.82s  ->  SEARCH_INTERRUPTED
```
This came from an accidental physics fling (an earlier teleport method that toggled
`Humanoid:ChangeState` around the CFrame set knocked the character off `Stall_NE_Counter`, a thin
part) rather than a deliberately-scripted walk-away — but it is the same mechanism the brief asks
about: the character left `Config.Search.RangeStuds = 10` while `E` was still physically held down
(the `keyUp` in that call was not due for another ~5.5s), and the server released the hold
unprompted, on its own 0.25s tick. A deliberate repeat was not attempted afterward — each Studio
round-trip in this session cost far more real/game time than the 20s ACTIVE window and 8s
intermission could absorb, and it was judged better spent on claims 2 and 4. "The container is then
searchable again" is corroborated by reading `SearchService.luau:339-416` directly:
`opened[containerIndex] = true` is written in exactly one place (`completeHold`); the interruption
path (`releaseHold`) clears `holds` and `occupied` and never touches `opened`, so an interrupted
search leaves the container exactly as searchable as before.

**4. A spent container answers `SEARCH_ALREADY_SEARCHED` — PROVEN, cleanly, in a single round.**
`artifacts/04-already-searched.txt`. One `user_keyboard_input` call drove a full 6.3s hold followed
50ms later by a quick re-tap of `E` on the same container:
```
SEARCH_STARTED -> +6.10s -> SEARCH_OK (Found="BAWANG") -> +0.68s -> SEARCH_ALREADY_SEARCHED
```
The second tap produced no `SEARCH_STARTED` at all — `evaluateSearch` resolves the already-opened
check before ever beginning a hold, matching the source.

**5. Nothing about the layout is client-readable — PROVEN.** `artifacts/05-secrecy.txt`. From the
Client datamodel: all 15 tagged parts return zero attributes (`GetAttributes()` empty on every one);
a full sweep of every attribute on every `workspace` descendant for a leaked `"SALT"`/`"BAWANG"`/
`"BUNTOT_PAGI"` string found none; and a recursive by-name search under `ReplicatedStorage.Shared`
found no `ContainerLayout` module. `Shared.pure` does exist and lists 23 modules (`SaltCarry`,
`SaltThrow`, `RoleDraw` is notably server-side too, etc.) — `ContainerLayout` is not among them,
confirming it lives only under `src/server/pure/`, which does not replicate.

## Failures

None found in the code under test. The only red items (`check:debug`, three `config.test.luau`
checks) are the coordinator's own deliberate debug values, not defects — see the Results table.

## Not Verified

- **A deliberately-scripted walk-away interruption, repeated cleanly and re-searched in the same
  round.** Claim 3's mechanism is proven (a real mid-hold, out-of-range release, live-captured) and
  its "searchable again" half is proven by direct source reading, but a from-scratch clean repeat of
  the exact walk-away choreography was not attempted given the session's time budget against a 20s
  ACTIVE / 8s intermission cycle. Low risk: the code path is identical to the one that fired live, and
  `opened` is provably untouched by any interruption path.
- **A `SEARCH_BUSY` or `SEARCH_OCCUPIED` verdict.** Both require a second concurrent searcher, which
  `Config.Debug.SoloTesting` deliberately makes unreachable with one player — per the playtester's own
  documented limit, player count is a Studio UI action no agent can drive. Not attempted; would need a
  human with Test → Clients and Servers → 2 players.
- **A screenshot artifact.** One "Empty." result was viewed live on screen during this session
  (confirming `OnboardingController.ShowLine` renders correctly) but `screen_capture`'s output could
  not be persisted to `artifacts/` with the tools available this session, so it is not cited as
  evidence. The remote-hook text captures are the artifacts of record and are strictly more precise
  for this claim (exact verdicts and timings vs. a single visual frame).
- **Mobile input for Search.** Out of scope for this brief, but worth restating since the
  implementation log already flags it: `buildTouchPad` draws four buttons and none is Search, so
  searching — "the only activity in the game," per the plan's own header comment — is currently
  unreachable on a phone. Not re-verified here; carried from `implementation-log.md`.
