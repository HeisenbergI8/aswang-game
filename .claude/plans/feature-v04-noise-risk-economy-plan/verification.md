# Verification: V04 — the noise system

**Date:** 2026-08-27
**Scope:** V04 diff — `NoiseModel.luau`, `NoiseLog.luau`, `NoiseService.luau`, `SearchService.luau`,
`ItemService.luau`, `AudioController.luau`, `Config.luau`, `Types.luau`, `Remotes.luau`,
`init.server.luau`, `tests/noise-model.test.luau`, `tests/noise-log.test.luau`,
`tests/audio-cues.test.luau`, `tests/config.test.luau`.
**Rojo serving:** yes — `preflight -- --studio` reported `rojo-serve`, `rojo-attached` and
`rojo-synced` all ok before this run started (checked by the coordinator, not re-run here).
**Studio reachable:** yes — `aswang.rbxl`, studio_id `ab384d6d-f33b-419a-bb40-4a49c27fa039`,
confirmed via `get_studio_state` before touching anything.
**SoloTesting:** on — set by the coordinator (`Round.Intermission=8`, `Duration=20`, `EndScreen=6`,
`Debug.SoloTesting=true`, `Debug.VerboseLogging=true`). Not changed by this agent; the coordinator
reverts all five.

## Headline answer to the build plan's V04 Verify line

**"playtester confirms the cue fires on a search and not on a walk" — CONFIRMED, both halves,
with the remote payload captured directly and console evidence from a sustained, non-adversarial
test window.**

- A search fires the cue immediately at the start of the hold (before the 6s hold completes), on
  both the server (`[NoiseService] SEARCH recorded — 1 in history.`) and the client
  (`[AudioController] cue CUE_NOISE_SELF — own noise`, since this is a solo test — see the Not
  Verified note on the non-self path).
- Walking fires nothing. Confirmed by a deliberate 8-second W/D walk test producing zero
  `[NoiseService]` lines, and independently reconfirmed by silence across ~450 seconds and 12 full
  round cycles (rounds #4–#15) of incidental movement/idle time with no emitter ever firing.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` → `- analyze: ok` |
| lint (selene) | PASS | `npm run lint` → `0 errors, 0 warnings, 0 parse errors` |
| format (stylua) | PASS | `npm run fmt:check` → clean, no output |
| check:remotes | PASS | `- remotes: ok (26 declared, 26 wired)` |
| check:secrecy | PASS | `- secrecy: ok (the Aswang stays server-side)` |
| check:ratelimit | PASS | `- ratelimit: ok (every OnServerEvent consults AntiCheat)` |
| check:config | PASS | `- config: ok (balance stays data-driven)` |
| check:scope | PASS | `- scope: ok (19 out-of-scope shapes watched)` |
| unit — `tests/noise-model.test.luau` | PASS | `lune run` → `172/172 checks passed` |
| unit — `tests/noise-log.test.luau` | PASS | `lune run` → `24/24 checks passed` |
| unit — full `npm run test:unit` (31 files) | 30/31 files pass | see note below |
| behavioural — search emits | PASS | `artifacts/console-full-session.txt`, `artifacts/noise-cue-remote-payload.json` |
| behavioural — walk does not emit | PASS | `artifacts/console-full-session.txt` |
| behavioural — cancelled search still emitted | PASS | `artifacts/console-full-session.txt` (same capture, round #3) |
| behavioural — history bounded/clears between rounds | NOT ESTABLISHED | see Not Verified |
| behavioural — noise outside ACTIVE does nothing | NOT ESTABLISHED (code-reviewed only) | see Not Verified |

**`npm run test:unit`'s one failing file is `tests/config.test.luau`, and it is EXPECTED, not a
defect.** It fails on exactly the three checks that assert the debug values are *off*
(`SoloTesting == false`, a full-length `Duration`, no short `session retries` window) — those are
the coordinator's deliberate overrides for this run, named in the brief, and I have not touched
`Config.luau`. Every other assertion in that file — including all eight of V04's own new noise
invariants (search-is-loudest, history-outlives-first-pulse, cap-can't-truncate-window,
cue-coarser-than-pulse, sprint-threshold-above-any-real-speed) — is not in the failure list, so V04's
own invariants are green; only the pre-existing debug-value guard is red, on purpose.

## Behavioural evidence, in detail

### 1. A search emits (PRIMARY — build plan's Verify line, half 1)

Round #3, ACTIVE phase, 19s left. Character navigated to
`Workspace.Barrio.Dressing.Stall_SE.Stall_SE_Counter` (a `CollectionService`-tagged
`SearchContainer`, confirmed via `execute_luau` querying `CollectionService:GetTagged("SearchContainer")`
in Edit mode before Play started — 15 tagged containers total), landing 0.92 studs away (well
inside `Config.Search.RangeStuds = 10`). Held `E` for 1 second via `user_keyboard_input`
(`keyDown` → `wait 1000ms` → `keyUp`).

Console, immediately, before the 6-second `SearchTime` could have elapsed:
```
[NoiseService] SEARCH recorded — 1 in history.
[AudioController] cue CUE_NOISE_SELF — own noise
[SearchController] SEARCH_INTERRUPTED
```
Full excerpt: `artifacts/console-full-session.txt`.

**A transient listener was also attached directly to the `NoiseCue` remote** (per
`.claude/lessons/prove-input-at-the-remote-not-the-outcome.md` — measure the boundary that
changed, not a downstream effect) via `execute_luau` in `Client` mode, storing every payload into
`_G.noiseCues`. Captured payload:
```json
{ "Action": "SEARCH", "Loudness": 1, "Position": { "X": 56, "Y": 0, "Z": -48 }, "Mine": true, "At": 18548.24 }
```
Saved as `artifacts/noise-cue-remote-payload.json`, with the quantisation arithmetic checked
against the container's true position (58.9, 2.6, -47.43) at `Config.Noise.CueGridStuds = 8` —
all three axes match exactly (`round(58.9/8)*8=56`, `round(2.6/8)*8=0`, `round(-47.43/8)*8=-48`),
and `Loudness = 1` matches `Config.Noise.Actions.SEARCH.Loudness`. The server-side dispatch,
quantisation and payload shape all check out against real Studio state, not just against the unit
tests.

### 2. Walking does not emit (build plan's Verify line, half 2 — the half most likely to be skipped)

Two separate windows:

- **Deliberate test, round #5:** position confirmed via `execute_luau` before
  (`X=-13.37, Z=-47.05`) and after (`X=13.30, Z=-46.90`) an 8-second `W`(4s)+`D`(4s) hold —
  ~27 studs of genuine movement, all inside the ACTIVE phase. Zero `[NoiseService]` lines in the
  console for that round.
- **Incidental, rounds #4–#15 (12 full round cycles, ~450s):** the character remained present and
  moving/idle through 12 complete Intermission→Starting→Active→Ending cycles after the one
  deliberate search in round #3. Not one further `[NoiseService]` line appears anywhere in that
  span (`artifacts/console-full-session.txt`, full raw dump). `SPRINT` has no emitter wired in V04
  (confirmed by code read of `SearchService.luau` and `ItemService.luau` — the only two `NoiseService.Emit`
  call sites in `src/`), so there is nothing a keyboard could trigger for movement even in
  principle; this run confirms that holds in practice, not just by absence-of-code.

### 3. A cancelled search still emitted

Same round #3 capture as above: `E` was released after 1 second, well before
`Config.Search.SearchTime` (6s). `[NoiseService] SEARCH recorded` and the client cue both appear
**before** `[SearchController] SEARCH_INTERRUPTED` — the noise was recorded at the *start* of the
hold (`SearchService.beginHold`, per the plan's own design note), not at completion, so the
cancelled search is provably as loud as a completed one would have been at that point.

## Not Verified

- **History bounded / clears at end of round (`NoiseService.RecordCount()`) — NOT ESTABLISHED, and
  I stopped trying rather than keep spending the session on it.** Plan was to run a second search
  in a later round and compare the printed count against round #3's baseline of `1 in history`: if
  the history clears on the phase transition, a later search should also print `1`; if it doesn't,
  it should print `2` or more. I made a real attempt at this after writing the first version of
  this report and it failed for an environmental reason worth recording: **Studio MCP round-trip
  latency in this session is large relative to the round cycle.** The round is
  Intermission(8s)+Starting(4s)+Active(20s)=32s end-to-end, and single `get_console_output` /
  `execute_luau` / `character_navigation` calls were each taking long enough that between two
  consecutive calls the console log had advanced by 10-19 *rounds* (observed jumps: round #3 to
  round #15 across three calls; round #18 to round #19 across two more). A `character_navigation`
  call to a container 161 studs from my position also returned `Request timeout` and evidently did
  not complete the move. Under that latency, hitting a ≤20s ACTIVE window with a navigate-then-hold
  sequence is not reliable — I lost the window twice more trying. I did **not** attempt
  `execute_luau` against `NoiseService.RecordCount()` directly as a substitute, because
  `.claude/agents/playtester.md`'s stated trap applies exactly here: `require()`-ing `NoiseService`
  fresh inside `execute_luau` (Server datamodel) gets its own module cache and its own
  `local history = {}`, which was never `Init()`'d by that call — it would read back `0` regardless
  of the real live server's count, which is a false negative I chose not to report as a finding.
  **This is a real gap.** It is the one line item the build plan's Done criteria calls "bounded"
  and I have not proven the bound or the clear behaviourally in Studio — only read the code
  (`NoiseLog.append`'s age+cap prune, `NoiseService.onPhaseChanged` clearing on any non-ACTIVE
  phase) and confirmed both are covered by the Lune suite (`noise-log.test.luau`'s flood test
  proves the cap arithmetic; nothing in Lune can prove the live phase-subscription wiring actually
  fires in Studio). **What would close it:** one more search in any later round, compared against
  the `N in history` count printed for the round #3 search (`1`) — a human or a fresh session with
  better round-trip latency could do this in two tool calls if timed against the console's own
  `[RoundService] -> ACTIVE` line.
- **Noise outside ACTIVE does nothing.** Not deliberately tested. Indirect evidence: my accidental
  round #1 attempt (before understanding the round-timing budget) tried to search after the round
  had already moved to ENDING/INTERMISSION and got `[SearchController] SEARCH_WRONG_PHASE` with
  **no** `[NoiseService]` line — consistent with the design (the `RequestSearch` handler itself
  gates on `RoundPhase.Active` before `beginHold` ever runs, and `NoiseService.Emit` has its own
  independent Active-only gate as a second lock) — but I did not construct this as a deliberate
  test with a clean single-variable capture, so I am reporting it as "consistent with, not proven
  by" this run.
- **The Aswang-vs-survivor symmetry.** Out of scope for this agent per the brief — needs a second
  client, and is `exploit-auditor`'s question, running concurrently.
- **The `CUE_NOISE` (non-self) client path** — the branch that produces the exact log line the
  build plan names, `[AudioController] cue CUE_NOISE — SEARCH, 60 studs` — could not be exercised
  solo. `dispatchCue` only takes that branch for a listener who is NOT the actor; with one player
  in the round, `Mine` is `true` on every capture and the client always takes the `CUE_NOISE_SELF`
  branch instead (both gated by the same server-side dispatch and radius test — see
  `artifacts/noise-cue-remote-payload.json` for the raw payload, which is the same shape either
  way). This needs Test → Clients and Servers → 2 players, which is a human UI action I cannot
  drive, per `.claude/agents/playtester.md`.
- **Whether the cue actually plays audibly** — moot by design this chunk: `Config.Audio.Assets.CUE_NOISE`
  and `CUE_NOISE_SELF` are both `""`. The brief is explicit that console evidence of the cue firing
  is the supported form of proof at this stage, not audio.

## Confidence

- **Search emits, walk does not, cancel still counts:** high. Directly observed console output,
  cross-checked against a raw remote payload capture with correct quantisation arithmetic, over
  both a short deliberate test and a long incidental window with zero false positives.
- **History bound / round-clear:** not established — no confidence claimed either way. This is the
  one item from the brief's priority list I did not finish; it needs one more search in a
  subsequent round to compare the printed count, or a human continuing this session.
- **Outside-ACTIVE gate:** low — consistent with one accidental observation and a code read, not a
  deliberate test.
