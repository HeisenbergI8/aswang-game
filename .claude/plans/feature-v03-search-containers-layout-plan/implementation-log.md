# Implementation Log — V03: SearchService, containers and the layout seed

## Phase 1: The draw, its proof, and the two numbers it needs — 2026-08-27

**Steps completed:** 1.1, 1.2, 1.3

**Files changed:**
- `src/server/pure/ContainerLayout.luau` (new)
- `tests/container-layout.test.luau` (new)
- `src/shared/Config.luau` (added `Search.RangeStuds = 10`)
- `tests/config.test.luau` (added 3 relationship checks)

**Deviations from plan:** one, and it is a type annotation rather than a behaviour change.
The plan's suite diff declared the per-draw tallies as bare constructors —
`local tally = { SALT = 0, BAWANG = 0, BUNTOT_PAGI = 0 }` — and then indexed them with
`tally[id]` where `id` is a plain `string` off `layout.Contents`. Under `--!strict` that is
indexing a sealed table with a non-literal key. Both tallies are annotated
`{ [string]: number }` instead. `tests/` is outside `npm run analyze`'s scope (it walks `src/`),
so this did not show up as a gate failure — it is corrected because it was wrong, not because
something caught it. No assertion changed.

**Gate:**
- `lune run tests/container-layout.test.luau` — PASS, 13 assertions
- `lune run tests/config.test.luau` — PASS, 89 balance invariants (was 86)
- `npm run verify` — analyze ok · lint ok · fmt ok · remotes 22/22 · secrecy ok · config ok ·
  scope ok · ratelimit ok · debug ok · testcount ok · test:unit 29 files ok

**Notes for the playtester and the auditors:**
- **Nothing requires `ContainerLayout` yet.** This phase is byte-for-byte inert at runtime by
  design; the only observable change is `Config.Search.RangeStuds` existing. There is nothing to
  play here — the first drivable behaviour arrives in Phase 3.
- **The path is the point.** `src/server/pure/ContainerLayout.luau`, not `src/shared/pure/`.
  `src/shared` maps wholesale into `ReplicatedStorage`, so a shared placement would let a
  LocalScript `require()` and *call* the draw. Confirm the path in the diff first — a move to
  `shared/` would defeat the whole chunk with every check still green.
- **The RNG is injected and this module never creates one.** The `Random.new()`-with-no-argument
  rule is enforced at the call site, which lands in Phase 3.
- **`Contents` holds plain `string`, deliberately**, per
  `.claude/lessons/pure-module-unions-widen-in-lists.md`. Narrowing goes through
  `ContainerLayout.itemAt`, which returns `nil` for an unrecognised id rather than casting it
  onward. If a later phase's `analyze` reports "none of the union options are compatible" at a
  call site, the fix belongs in this module, not at the call site.
- **The distribution bands are hermetic**, driven by a fixed-seed xorshift32 rather than
  `math.random`, so a failure means the algorithm changed rather than that a run got unlucky.
  Bands are ±5% (±4.68σ) on occupancy and ±15% (±4.01σ) on the buntot pagi specifically. Do not
  widen them to make a failure pass.

## Phase 2: The network surface, its types, and its budgets — 2026-08-27

**Steps completed:** 2.1, 2.2, 2.3

**Files changed:**
- `src/shared/Types.luau` (`SearchVerdict`, `SearchUpdatePayload`)
- `src/shared/Remotes.luau` (`SearchUpdate` down; `RequestSearch`, `RequestCancelSearch` up)
- `src/shared/Config.luau` (`AntiCheat.Budgets.RequestSearch`, `.RequestCancelSearch`)
- `tests/anti-cheat-budgets.test.luau` (both names added to the `UP_REMOTES` hand copy)

**Deviations from plan:** none.

**Gate:**
- `lune run tests/anti-cheat-budgets.test.luau` — PASS, 13 remotes budgeted, 59 assertions
- `npm run verify:fast` — analyze ok · remotes ok (25 declared, 22 wired) · secrecy ok

**Notes for the playtester and the auditors:**
- **`check:remotes` reports 3 declared but not yet wired** — `SearchUpdate`, `RequestSearch`,
  `RequestCancelSearch`. This is the expected state at this phase boundary and the plan says so:
  the check fails on a remote *used* but not declared, not the reverse. Phase 3 wires all three.
- **The budgets land before the handlers on purpose.** `AntiCheatService.Consume` **fails closed**
  (`src/server/Services/AntiCheatService.luau:112-119`), so a handler written before its budget
  exists would refuse every request from every player, silently. A missing budget here is not
  "unlimited searching", it is "searching does not work at all".
- **`SearchUpdate` is deliberately NOT in `check-secrecy.mjs`'s `REVEAL_ALLOWLIST`.** It carries no
  role, so it needs no exemption. If a future change makes the scanner flag it, the payload has
  grown a field it should not have — read `Types.SearchUpdatePayload`'s absent-field list before
  adding anything to it.
- **Both up-remotes are argument-free.** The client never names a container; the server resolves it
  from that player's own character position. That is what removes the probe an exploiter would
  otherwise get by naming every tagged part in turn and reading the verdicts.

## Phase 3: SearchService — the pool, the seed, the lock and the two handlers — 2026-08-27

**Steps completed:** 3.1, 3.2, 3.3

**Files changed:** `src/server/Services/SearchService.luau` (new, ~640 lines)

**Deviations from plan:** two, both forced by the analyzer, both the same root cause.

1. **`local item: Types.ItemType? = ContainerLayout.itemAt(...)`** — the plan wrote this
   unannotated. `ContainerLayout.itemAt`'s declared return `Item?` widened to plain `string`
   across the `require` boundary, and `sendUpdate`'s `Types.ItemType?` parameter rejected it:
   `Expected '("BAWANG" | "BUNTOT_PAGI" | "SALT")?', but got 'string'`.
2. **`local verdict: Types.SearchVerdict, index, name = evaluateSearch(player)`** — also
   unannotated in the plan. `evaluateSearch` is annotated `(Types.SearchVerdict, number?,
   string?)`, but the first element widened when destructured out of the **multi-return tuple**,
   arriving as `"SEARCH_STARTED" | string`. Refining with `verdict ~= "SEARCH_STARTED"` kept the
   widened half, so the call below failed with `none of the union options are compatible`.

   **This extends `.claude/lessons/pure-module-unions-widen-in-lists.md` rather than contradicting
   it.** The lesson names lists; these are a cross-`require` *optional return* and a *multi-return
   tuple*. Same failure, same signature, two more positions — and in both the fix was an explicit
   annotation on the receiving local, not a `::` cast. Worth folding into the lesson.

   The plan predicted this class of failure and said the fix belongs in `ContainerLayout`, not at
   the call site. It does not, in this case: the module's own annotation is already correct and
   `analyze` is clean inside it. The widening happens on the way out, so the receiving local is
   where it has to be re-stated. Flagged for the auditor as a deliberate departure from the plan's
   stated remedy.

**Gate:**
- `npm run analyze` — ok
- `npm run check:config` — ok (the one literal is the 0.25 tick, waived with `ItemService`'s text)
- `npm run check:ratelimit` — ok (both handlers `Consume` on their first line)
- `npm run verify:fast` — analyze ok · remotes ok (**25 declared, 25 wired**) · secrecy ok

**Notes for the playtester and the auditors:**
- **`Random.new()` — no argument, at `seedLayout`.** This is the single line the chunk exists for.
  Grep the diff for `Random.new(` and confirm the parentheses are empty.
- **`SearchService` is not registered in `init.server.luau` yet** — that is Step 4.3. Nothing
  calls `Init`/`Start`, so at this phase boundary the service is inert in a running game.
- **Nothing logs `layout.Contents`.** `seedLayout` prints `Placed` and a pool count under
  `VerboseLogging`; `reportPool` prints verdicts and counts. Both are derivable from Config and
  the map. In a Studio solo test the server and client share one output window, which is why the
  rule is counts-never-contents rather than a matter of taste.
- **`GetAswangUserId` appears nowhere in this file**, by design — §4.4 and Amendment A2. The
  Aswang searches on identical rules.
- **`foundByPlayer` is written and read by nothing in V03** and will look like dead code. It is
  the V08 seam's data and the playtester's server-side evidence surface. Do not delete it.
- **The residual the exploit-auditor should weigh:** `SEARCH_OCCUPIED` and
  `SEARCH_ALREADY_SEARCHED` tell a player something about a container they are already standing
  at. No container id is in any payload in either direction, so there is no key on which two
  clients could difference their updates.

## Phase 4: The client asks, and the seam is written down — 2026-08-27

**Steps completed:** 4.1, 4.2, 4.3

**Files changed:**
- `src/client/Controllers/SearchController.luau` (new)
- `src/client/Controllers/UIController.luau` (`ActionHandlers` widened by `Search`, `CancelSearch`)
- `src/client/Controllers/InputController.luau` (`performSearch`, `performCancelSearch`,
  `onSearchAction`, the `E` bind, both registrations)
- `src/server/init.server.luau` (`SearchService` into `SERVICE_ORDER`, before `TrialService`)
- `src/client/init.client.luau` (`SearchController` into `CONTROLLER_ORDER`, after
  `OnboardingController`)

**Deviations from plan:** none in substance. Ordering note: the plan presented the `ActionHandlers`
widening as an aside to Step 4.2, and `gate-luau-analyze.mjs` typechecks each write as it lands, so
the type, the two verbs, the handler and the binds had to arrive in dependency order rather than in
the order the plan's diffs are printed. Same end state.

**Gate:** `npm run verify` — analyze ok · lint ok · fmt ok · **remotes 25 declared, 25 wired** ·
secrecy ok · config ok · scope ok · ratelimit ok · debug ok · testcount ok · test:unit 29 files ok

**Notes for the playtester and the auditors:**
- **`E` is the search key**, held. Begin fires `RequestSearch`, End *and* Cancel fire
  `RequestCancelSearch`.
- **Mobile cannot search.** Both actions are registered with `UIController.BindActions`, but
  `buildTouchPad` draws four buttons and none is Search. Searching is the only activity in the game
  and §5 puts ~60% of players on a phone. **High severity**, and it must close before V16 or that
  playtest cannot answer its third question for most of its players.
- **The client stores a deadline and nothing else.** No find list, no positions, no attribute — not
  because storing them would leak, but because that is the data structure an exploit would want and
  there is no reason to build it.
