# Implementation Log — V01: Remove the Task Game

## Phase 1: The client stops asking — 2026-08-26

**Steps completed:** 1.1, 1.2, 1.3, 1.4, 1.5, 1.6

**Files changed:**
- `src/client/Controllers/TaskController.luau` (deleted)
- `src/client/Controllers/GhostController.luau` (deleted)
- `src/client/Controllers/InputController.luau`
- `src/client/Controllers/UIController.luau`
- `src/client/Controllers/OnboardingController.luau`
- `src/client/Controllers/AudioController.luau`
- `src/client/init.client.luau`
- `src/shared/pure/AudioCues.luau` (one permission row — see Deviations)
- `src/shared/Config.luau` (two audio values — see Deviations)

**Deviations from plan:**

1. **The ACT touch button and its whole hold-input apparatus were removed from `UIController`,
   and Step 1.3 does not list them.** Step 1.2 removes `Act = performAct` from the registration
   and the `Act` field from `ActionHandlers`, so `handlers.Act(true)` / `handlers.Act(false)` in
   `beginAct` / `endAct` no longer typecheck. Removed with them: the `act` button construction, its
   `touchButtons.Act` entry, the `actInput` identity local, `beginAct`, `endAct`, the two
   `act.InputBegan/InputEnded` connects, the `UserInputService.InputEnded` backstop (which exists
   only to call `endAct`), and the `touchButtons.Act.Visible` row. V03's `RequestSearch` takes this
   slot back, per Step 1.2's own note.

2. **`promptFor`'s `elseif snapshot.GateOpen` branch was removed** (`UIController`). Step 1.3 names
   the gate half of the *status format string* but not this branch. Left standing it would have
   failed Phase 3's `ClientRoundSnapshot` trim. The two player-facing copy strings in the same
   function (`hold ACT at a task...` / `E hold a task...`) were deliberately LEFT — Step 1.3 assigns
   copy rewriting to Step 5.8.

3. **`CUE_GATE_OPEN` was removed from `src/shared/pure/AudioCues.luau` and `Config.Audio`**
   (the `CUE_GATE_OPEN` asset id and `GateVolume`). Step 1.6 instructs "any `AudioCues` id it plays
   that no other cue path uses"; after the `onGateChanged` deletion nothing plays it. No test
   asserted on either — `tests/audio-cues.test.luau` and `tests/config.test.luau` were both silent
   on this cue, so no suite changed.

4. **Three comments were reworded rather than deleted**, because they described files that are about
   to not exist: `AudioController`'s `logCue` rationale cited "GateService's untagged-gate warn is
   the precedent" (now states the rule directly); `InputController`'s touch-pad block said "C27
   REGISTERS THE OTHER THREE" (now names what actually remains); `UIController`'s palette comment
   explained `Progress` green against `GateOpen` gold (now stands on its own).

5. **`OnboardingController`'s file header was rewritten.** It opened by describing the waypoint as
   the controller's purpose. With the waypoint gone the header described a file that no longer
   exists; it now states what survives (`ShowLine`), why the copy layer is worth keeping alone, and
   explicitly defers "does a searcher need a marker" to V16/V17 rather than carrying the assumption
   over. `LAYOUT` lost its four waypoint values and `COLOUR` lost `Marker`.

**Gate:** `npm run verify` **exit 0** — analyze ok · lint ok · fmt:check ok · remotes ok (31 declared,
31 wired) · secrecy ok · config ok · scope ok (18 shapes) · ratelimit ok · debug ok · testcount ok ·
test:unit ok · harness ok.

Per-step verifies, all passing:
- 1.1 `npm run analyze` → ok
- 1.2 `grep -rL "TaskController" src/client/Controllers/InputController.luau` → absent
- 1.3 `grep -rL "TasksRequired" src/client/Controllers/UIController.luau` → absent
- 1.4 `grep -rL "FirstObjectiveAssigned" src/client/Controllers/OnboardingController.luau` → absent
- 1.5 `grep -rL "GhostController" src/client/init.client.luau` → absent
- 1.6 `grep -rL "onGateChanged" src/client/Controllers/AudioController.luau` → absent

**Notes for the playtester and the auditors:**

- `Remotes.luau` was **not touched**, by design (plan constraint (a)). The server still fires
  `TaskProgressChanged`, `TimingBarChanged`, `TaskListAssigned`, `GhostRoster` and
  `FirstObjectiveAssigned` at clients that no longer listen — a `FireClient` with no
  `OnClientEvent` connection is a discarded packet, and `check:remotes` reports the now-unused UP
  remotes as a NOTE rather than a failure. It still reads 31/31 wired. The wire is Phase 4.
- **The HUD lost its task bar.** During ACTIVE the screen now shows the sunrise clock, the role
  line, the salt count and the prompt — and nothing that counts progress, because there is no
  progress to count until V03. That is correct for this chunk, not a regression to report.
- The status panel's third line (`gate OPEN` / `gate shut`) is gone; the panel is now two lines.
- `Enums.PlayerState.Ghost` reads are still live in `UIController` (`:1554` `promptFor`, and the
  `stateColour` branch). Phase 5 renames them to `Dead`; they are deliberately untouched here.

---

## Phase 2: The server stops answering — 2026-08-26

**Steps completed:** 2.1, 2.2, 2.3, 2.4, 2.5, 2.6

**Files changed:**
- `src/server/pure/TaskPool.luau` → `src/server/pure/SearchPool.luau` (`git mv`, identifiers renamed)
- `tests/task-pool.test.luau` → `tests/search-pool.test.luau` (`git mv`, **no assertion changed**)
- `src/server/Services/ItemService.luau` (require + four type/call sites + seven comments)
- `src/shared/Types.luau` (`TaskPoolVerdict` → `SearchPoolVerdict`)
- `src/server/init.server.luau` (three names out of `SERVICE_ORDER`, TeachingService comment)
- Deleted: `TaskService.luau` (1806 lines), `GateService.luau` (213), `GhostService.luau` (763)
- Deleted from `src/server/pure/`: `TaskWeight`, `TaskListView`, `TaskParticipants`, `TaskProgress`,
  `TaskResolve`, `TimingWindow`, `FetchCarry`, `GateEscape`
- Deleted from `src/shared/pure/`: `TaskSelection`, `SpookBudget`
- Deleted ten suites: `task-selection`, `task-weight`, `task-list-view`, `task-participants`,
  `task-progress`, `task-resolve`, `timing-window`, `fetch-carry`, `gate-escape`, `spook-budget`

**Deviations from plan:** none. Every file the plan named was where it said, including the two it
corrected the build plan on:
- `TaskPool` was **not** deleted — `ItemService` requires and calls it, so it was renamed to
  `SearchPool`, per Step 2.1.
- `TaskWeight` is at `src/server/pure/`, not `src/shared/pure/` as the build plan states. The real
  file was deleted; no no-op delete was attempted.
- `GhostChat` was **not** deleted despite the build plan listing it — `QuickChatService:68` requires
  it and `:335` calls `shouldDeliver`, the audience filter that keeps a dead player's accusation away
  from the living. Step 5.1 renames it.

**Gate:** `npm run verify` **exit 0** — analyze ok · lint ok · fmt:check ok · **remotes ok (31
declared, 22 wired)** · secrecy ok · config ok · scope ok · ratelimit ok · debug ok · testcount ok ·
**test:unit 28 file(s) ok** · harness ok.

Per-step verifies, all passing:
- 2.1 `lune run tests/search-pool.test.luau` → `PASS search-pool: 14 assertions across the pool set`
- 2.2 `grep -rL "TaskPool" src/server/Services/ItemService.luau` → absent
- 2.3 `grep -rL "GhostService" src/server/init.server.luau` → absent
- 2.4 `npm run analyze` → ok
- 2.5 `npm run check:config` → ok (balance stays data-driven)
- 2.6 `npm run test:unit` → 28 file(s) ok

**Phase 2 issue checks, run and answered:**

- **Phase ownership.** `grep -rn "setPhase" src/` outside `RoundService` returns **three hits, all
  comments** (`TrialService:18`, `ProgressionService:825`, `QuickChatService:59`). No caller. The
  §6.4 rule holds.
- **`PlayerRemoving`.** Five handlers survive (`TrialService:804`, `BadgeService:295`,
  `ProgressionService:994`, `AntiCheatService:146`, plus `DailyService`'s explicit "no handler
  needed" note). None refers to state owned by a deleted service — `TaskService`'s presence map and
  `GhostService`'s body map both connected from inside their own modules and went with them.
- **Rate limiting.** Four `OnServerEvent` handlers disappeared with the services
  (`RequestTaskProgress`, `RequestTimingStop`, `ReportGhostPosition`, `RequestGhostSpook`). Their
  `AntiCheatService` budgets are deliberately still standing — `tests/anti-cheat-budgets.test.luau`
  pins both directions, so budget and remote must be removed together in Phase 4. `check:ratelimit`
  is green.
- **Secret leakage.** Strictly reduced. `TaskListView.forPlayer` was the one module in the repo that
  deliberately told the Aswang a lie; deleting it removes a role-branching code path. Nothing added.

**Notes for the playtester and the auditors:**

- **`check:remotes` moved from 31/31 to 31/22.** Nine declared-but-unwired remotes is the expected
  intermediate state and the check reports it as a NOTE, not a failure. Phase 4 removes them from
  `Remotes.luau`. Do not read 22 as a regression.
- The server no longer draws tasks, polls an escape gate, or builds ghost bodies. `RoundService`
  still holds a task counter and a `GateOpen` field feeding the snapshot — Phase 3 removes those.
- `ProgressionService.BumpStat(player, "TasksDone", 1)` died with `TaskService`. `Stats.TasksDone`
  and `BadgeRules.FirstTask` deliberately remain (constraint (d)); the stat is now incremented by
  nothing until V4 rebinds it to searching.
- Prose references to the deleted services survive in comments across `TrialService`,
  `ProgressionService`, `BadgeService`, `TeachingService`, `QuickChatService`, `DailyService` and
  `RoundService`. `check:scope` cannot see comments; Step 5.8's residue sweep owns them.

---

## Phase 3: The round ends on sunrise alone — 2026-08-26

**Steps completed:** 3.1, 3.2, 3.3, 3.4, 3.5, 3.6

**Files changed:**
- `src/server/Services/RoundService.luau` (attrition win, task counter, gate, `SetTasksCompleted`,
  `IsGateOpen`, three comment blocks)
- `src/shared/pure/WinConditions.luau` (deleted)
- `tests/win-conditions.test.luau` (emptied to skeleton, **kept**)
- `src/shared/Types.luau` (10 type declarations + 5 fields)
- `src/shared/Enums.luau` (`Enums.TaskType`)
- `src/client/init.client.luau` (debug printer)

**Deviations from plan:**

1. **The plan's skeleton for `tests/win-conditions.test.luau` is not green as written.** Its PASS line
   ends `awaiting V11's rule`, and `check-testcount.mjs` reads the `11` as a hardcoded tally in a
   summary — `FAIL tests/win-conditions.test.luau:30 — hardcoded 11 in a PASS summary`. Rewording to
   `v2` failed the same way on the `2`. The line now reads
   `skeleton, awaiting the rewritten win rule` — **no digit outside the `{checked}` interpolation**.
   Fixed by rewording rather than by a `-- count-ok:` waiver: the check is right, a summary line
   should carry no bare number, and a waiver here would be waiving a correct finding. Everything else
   in the skeleton is verbatim from the plan, including the four-attempt history.

2. **Step 3.1's verify required rewording a comment the step does not mention.**
   `grep -rL "WinConditions" src/server/Services/RoundService.luau` demands the token be absent from
   the file, and `livingSurvivorCount`'s header (`:460`) said "What crosses to WinConditions is a
   NUMBER". Reworded to state the rule without the dead module's name, and extended with the
   constraint it implies for V11: the win rule may read the survivor count, never the id behind it.

3. **Three further comments in `RoundService` were rewritten, not deleted**, because they argued from
   files that no longer exist:
   - the `STARTING` require-cycle block (`:820`+) argued specifically from `TaskService` needing
     `SetTasksCompleted`; it now states the direction rule generally and names V03's container
     service as the next subscriber.
   - the TODO block above the transitions (`:738`) listed `TODO(C11): win conditions in ACTIVE` and
     `TODO(C15): ghosts`; replaced with a statement of what actually ends a round now.
   - **`MarkKilled`'s Amendment A3 block (`:912`+) — the security-critical one.** It enumerated three
     benign off-cadence snapshot triggers (phase change, gate flip, task count) to argue why a
     broadcast on death was an oracle. Two of the three no longer exist. Reworded to name the one
     remaining trigger, **and extended**: with only one benign push left to hide behind, an
     off-cadence broadcast here would now be *more* legible than it was, not less. Anything V03 adds
     that pushes a snapshot off-cadence has to be read against that paragraph first.

**Gate:** `npm run verify` **exit 0** — analyze ok · lint ok · fmt:check ok · remotes ok (31/22) ·
secrecy ok · config ok · scope ok · ratelimit ok · debug ok · testcount ok · test:unit 28 file(s) ok ·
harness ok.

Per-step verifies, all passing:
- 3.1 `grep -rL "WinConditions" src/server/Services/RoundService.luau` → absent
- 3.2 `grep -rL "GateOpen" src/server/Services/RoundService.luau` → absent
- 3.3 `lune run tests/win-conditions.test.luau` → exit 0, `PASS win-conditions: 0 assertions`
- 3.4 `npm run analyze` → ok
- 3.5 `grep -rL "TaskType" src/shared/Enums.luau` → absent
- 3.6 `grep -rL "TasksRequired" src/client/init.client.luau` → absent

**Phase 3 issue checks, run and answered:**

- **The `AlivePlayerCount` block in `Types.luau` is intact** (`:393`+), verbatim except the adjacency
  phrase, which now reads "sat between RoundNumber and YourRole" so it still describes a real
  neighbour. Amendment A3's position-correlation argument is unchanged and is still the only written
  record of that attack.
- **Phase ownership holds.** `setPhase` outside `RoundService` returns three hits, **all comments**.
  One definition, no external caller.
- **`enterEnding` has exactly the routes the plan predicted:** `:966` TIMEOUT (sunrise), `:888` and
  `:1117` ABORTED (roster below `MinPlayers`), plus `:818` reached only through
  `RoundService.EndRound`.
- **`RoundService.EndRound` now has no caller in the tree** — the only `grep` hits are comments in
  `TrialService`, `MonsterService` and `RoundService` itself. Left standing per the plan: V03's kill
  path and V11's win rule are its future callers, and deleting it would make V11 re-derive the
  ACTIVE guard.
- **`state.AswangKills` / `DealtInSurvivors` kept.** The single external reader is
  `ProgressionService.luau:857` (`GetAswangKills()`), which prices the round's XP award. Neither
  ABORTED path reads either value.

**Notes for the playtester and the auditors:**

- **THE ASWANG NOW HAS NO WIN CONDITION.** Survivors reach sunrise; the monster cannot win a round at
  all. This is the plan's stated interim (V11 writes the kill-everyone rule) and it is what makes
  V01 checkable in Studio — "the round still cycles with nothing to do in it". It is not a bug to
  report.
- **`RoundResult.SURVIVORS_ESCAPED` and `ASWANG_WINS` are now unreachable.** Both stay in the union;
  `UIController`'s end screen still branches on them. V02 owns the v2.0 vocabulary.
- **One real behaviour change to watch in Studio.** `SetTasksCompleted` was the only caller of
  `broadcastSnapshot()` outside the `SnapshotInterval` tick. The HUD now refreshes on the 0.5s
  cadence and on a death, and on nothing else. That is the design, not a dropped push.

---

## Phase 4: Config, the wire, and the budgets — 2026-08-26

**Steps completed:** 4.1, 4.2, 4.3, 4.4, 4.5, 4.6

**Files changed:**
- `src/server/Services/TrialService.luau` (two Config reads rehomed, header rewritten)
- `src/shared/Config.luau` (`Config.Trial` +2 values; `Config.Tasks` and `Config.Ghost` deleted in
  full; `Round.AswangWinSurvivorThreshold` deleted; four `AntiCheat.Budgets` entries deleted; four
  comments rewritten)
- `src/shared/Remotes.luau` (nine remotes + their comment blocks; `TeachingCue` comment rewritten)
- `tests/config.test.luau` (19 invariants + their comment blocks)
- `tests/anti-cheat-budgets.test.luau` (4 up-remote names, 3 assertions)

**Deviations from plan:** none in substance. Four comment rewrites the plan did not enumerate,
all forced by the same cause — a comment arguing from a number this phase deleted:

1. `Config.Salt.PickupRangeStuds`' header measured itself against `Tasks.PresenceRangeStuds` (9).
   Reworded, **and the loss is now stated in the file itself**: nothing pins that radius any more and
   V03 owes it a new right-hand side.
2. `Config.QuickChat.AccuseRangeStuds`' header pinned its upper bound against
   `Tasks.MarkerVisibleStuds` (220). Same treatment, same explicit note — this is the §6.2
   map-scale-radar bound, so its losing an operand is worth flagging loudly rather than quietly.
3. `Config.Salt.PouchPoolSize`' header cited `Tasks.PoolSize` and `TaskPool.evaluate`; now cites
   `SearchPool.evaluate`.
4. The trial budget comment priced itself "like `RequestGhostSpook` next door", which no longer
   exists.

**Gate:** `npm run verify` **exit 0** — analyze ok · lint ok · fmt:check ok · **remotes ok (22
declared, 22 wired)** · secrecy ok · config ok · scope ok · ratelimit ok · debug ok · testcount ok ·
test:unit 28 file(s) ok · harness ok.

Per-step verifies, all passing:
- 4.1 `grep -rL "Config.Tasks" src/server/Services/TrialService.luau` → absent
- 4.2 `npm run check:config` → ok (balance stays data-driven)
- 4.3 `npm run check:ratelimit` → ok
- 4.4 `npm run check:remotes` → **ok (22 declared, 22 wired)** — the wire is closed
- 4.5 `lune run tests/config.test.luau` → `PASS config: 82 balance invariants`
- 4.6 `lune run tests/anti-cheat-budgets.test.luau` → `PASS anti-cheat-budgets: 11 remotes budgeted,
  51 assertions`

**Phase 4 issue checks, run and answered:**

- **`check-secrecy.mjs`'s `REVEAL_ALLOWLIST` is unchanged** and still contains exactly two entries:
  `RoundEnded` and `RoleAssigned`. Verified by reading the file, not inferred from a green check.
- **No remote carries a client-supplied position any more.** `ReportGhostPosition` was, in its own
  words, "the one place in the game where the client owns a position". That is a strictly stronger
  property than the tree had before V01.
- **`GhostRoster` is off the wire** — the only remote in the repo whose safety came from its
  *audience* rather than its payload, and the one shape `check-secrecy.mjs` structurally cannot
  police. Removing it deletes a class of mistake, not an instance.
- **No inlining.** `check:config` is green, which is the specific proof that Step 4.1 moved its two
  numbers into `Config.Trial` rather than pasting `9` and `8` into `TrialService`.
- **No orphaned section headers** in `tests/config.test.luau` after 19 deletions — each surviving
  header still has checks beneath it.

**Notes for the playtester and the auditors — three balance invariants are gone with nothing to
replace them, and this is the phase's real cost:**

1. **Salt's pickup radius is now pinned by nothing.** It was `PickupRangeStuds < Tasks.PresenceRangeStuds`.
2. **The quick-chat accusation radius has lost its upper bound.** It was pinned below
   `Tasks.MarkerVisibleStuds`, and that bound was **security, not feel** — it is what stopped the
   accusation phrase becoming a map-wide through-walls proximity radar the Aswang can poll. Line of
   sight in `QuickChatService` is still the primary defence and is untouched, but the second line of
   defence is now unpinned.
3. **Nothing asserts a full-server round is winnable at all**, since the attrition invariant went.
   V11 owns that one by construction.

Both (1) and (2) need a new right-hand side when V03's container search range lands. The note is
written into `Config.luau` itself at both sites, not only here.

---

## Phase 5: Re-arm the scope guard — 2026-08-26

**Steps completed:** 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8

**Files changed:**
- `src/shared/pure/GhostChat.luau` → `ChatAudience.luau`; `tests/ghost-chat.test.luau` →
  `chat-audience.test.luau` (both `git mv`)
- `src/shared/Types.luau`, `src/shared/Enums.luau` (`PlayerState` GHOST → DEAD; two cue ids)
- Eight pure modules' local unions: `AudioCues`, `BodyTransitions`, `KillValidation`, `PlayerBody`,
  `RejoinResolve`, `SaltCarry`, `SaltThrow`, `TransformRules`
- Eight suites (literal swap only), plus `chat-audience`, `quick-chat-phrases`, `teaching-lines`
- `src/shared/pure/QuickChatPhrases.luau` (`GhostMay` → `DeadMay`; one phrase's TEXT)
- `src/server/Services/QuickChatService.luau`, `RoundService.luau` (`hadGhostBody` → `hadDeadBody`,
  two writers), `TrialService`, `ProgressionService`, `TeachingService`, `BadgeService`
- `src/client/Controllers/UIController.luau` (`COLOUR.Dead`, two state branches, four copy strings)
- `src/shared/pure/TeachingLines.luau` (two cues)
- `.claude/scripts/check-scope.mjs` (**the word is armed**, + two self-test cases)
- `sourcemap.json` regenerated (the module rename)

**Deviations from plan:**

1. **The build plan's claim that the scope self-test case was "already written and commented out" is
   false — confirmed by reading the file.** There is no commented-out ghost case in
   `check-scope.mjs` or `harness-selftest.mjs`; only the two ALLOW cases (a corpse, a husk) exist, and
   both would have passed armed or disarmed since neither source string contains the bare word. Two
   **BLOCK** cases were written, per the plan's own correction:
   `check('the ghost system', 'local GhostService = {}', true)` and
   `check('a ghost in a UI string', 'label.Text = "your chat reaches ghosts only"', true)`.
   `check-scope` went 18/18 → **20/20 cases**.

2. **A fifth player-facing copy string names a dead mechanic, and Step 5.8 does not list it.**
   `QuickChatPhrases.luau:89` is a live quick-chat phrase reading **`Text = "Task here"`** — it is on
   the wheel, every player can send it, and it names a mechanic that no longer exists. The plan
   enumerated only `UIController`'s four. Changed to **`"Over here"`**: mechanic-neutral, true today,
   and deliberately *not* search copy, per the plan's rule against inventing V03's vocabulary in a
   demolition chunk.
   **The ID `TASK_HERE` was deliberately NOT renamed** and the reason is written into the file:
   `QuickChatPhraseId` is a closed union read by `Types`, the wheel layout and analytics, and V03 owns
   the search vocabulary that gives this slot its real name. A player-facing string naming a dead
   mechanic is V01's bug; a stale internal id is V03's rename.

3. **`sourcemap.json` had to be regenerated** after the `GhostChat` → `ChatAudience` move, or
   `analyze` reports `Unknown require` for a file that exists. Not a code change; noted because it is
   an easy step to miss on any `git mv` of a module.

4. **Prose rewrites beyond the eight files the plan tabulates**, all forced by the rename or the
   deletions: `TrialService` (five blocks arguing against colliding with a task system that no longer
   exists — kept, and extended to say the argument now applies to V03's container search),
   `ProgressionService`, `TeachingService`, `QuickChatService`, `BadgeService`, `Config.luau`,
   `SaltThrow`, `SaltCarry`, and `UIController`'s header.

**Gate:** `npm run verify` **exit 0** — analyze ok · lint ok · fmt:check ok · remotes ok (22/22) ·
secrecy ok · config ok · **scope ok (19 out-of-scope shapes watched)** · ratelimit ok · debug ok ·
testcount ok · test:unit 28 file(s) ok · harness 28 suite(s) ok.

Per-step verifies, all passing:
- 5.1 `lune run tests/chat-audience.test.luau` → 34 assertions (**unchanged**)
- 5.2 `grep -rL "GHOST" src/shared/Types.luau` → absent
- 5.3 `lune run tests/body-transitions.test.luau` → 33 cells (**unchanged**)
- 5.4 `npm run test:unit` → 28 file(s) ok
- 5.5 `lune run tests/quick-chat-phrases.test.luau` → 121 assertions (**unchanged**)
- 5.6 `lune run tests/teaching-lines.test.luau` → 18 assertions over the closed cue set
- 5.7 `npm run check:guards` → **28 suite(s) ok**, `check-scope: 20/20 cases`
- 5.8 `grep -rL "Task" src/server/Services/RoundService.luau` → absent

**THE RENAME IS PROVABLY BEHAVIOUR-PRESERVING.** Every one of the eight grids kept its exact tally
across the swap — body-transitions 33, player-body 11, rejoin-resolve 61, kill-validation 51,
salt-carry 38, salt-throw 70, transform-rules 19, audio-cues 30/30 — with no case added, removed or
flipped. Seven of the eight passed *before* the literal swap too, because they are allowlists and an
unknown state falls through to the safe answer; **`body-transitions` was the one that failed**, being
the only file with an actual branch on the value. That is exactly the split the plan predicted, and
it is why `BodyTransitions` was the named file and its suite the named verify.

**Phase 5 critical-path checks, each read in the source rather than inferred from a green gate:**

- **`BodyTransitions.actionFor` short-circuits `state == "DEAD"` → `KEEP` at `:135`, still ABOVE the
  `mayHaveBody` guard at `:139`.** This is the Critical-bug path: collapsing DEAD into SPECTATOR
  instead of renaming it would fall through to `REVOKE`, destroy the corpse, and make
  `Character == nil` enumerate exactly the players who have died — with `analyze` and every check
  green. Four states in, four states out; verified across all ten `PlayerState` declarations.
- **`ChatAudience.isLivingSide` is still an ALLOWLIST** — `state == "ALIVE" or state == "LOBBY"`. Not
  rewritten as `~= "DEAD"`, which would silently admit SPECTATOR and put a dead player's accusation
  in front of the living.
- **`RejoinResolve`'s `stored :: PlayerState` cast at `:111` is intact**, with its comment. It works
  around the documented Luau bite (narrowing a literal union widens the remainder to `string`), and
  it sits on a line this phase edited.
- **`check:scope` went from "would find 154" to `ok (19 shapes watched)`.** Zero findings on an armed
  guard is the whole point of sequencing the demolition ahead of it.

**Notes for the playtester and the auditors:**

- **The dead now spectate; they do not fly.** `UIController`'s prompt for a dead player changed from
  `"WASD fly · Space up · LeftCtrl down · your chat reaches ghosts only"` to
  `"you are dead — watching · your chat reaches the dead only"`. There is no flying body to control
  and no remote that carries one.
- **`"TaskPoint"` (the CollectionService tag) is deliberately unchanged** at `TrialService:64`. The
  parts carrying it live in the place file, which is gitignored; renaming the tag in code without
  re-tagging every part in Studio silently gives the Solo Trial an empty pool — no error, no diff,
  nothing in `git status`. Code cannot re-tag them. The rename belongs to a chunk that also opens
  Studio.
- **`Stats.TasksDone`, `BadgeRules.FirstTask`, `TrialTasksDone`/`TrialTasksRequired` and
  `Config.Trial.TasksToComplete` all survive** and are the full deferral list. The first two are V4's
  (a profile-schema migration and a live Roblox badge id); the last two belong to the Solo Trial,
  which V01 does not touch. A note to that effect is now in `BadgeService`'s header, where somebody
  reading the flat funnel metric will actually find it.
