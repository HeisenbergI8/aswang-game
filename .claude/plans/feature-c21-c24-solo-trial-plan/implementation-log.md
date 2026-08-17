# Implementation Log — C21–C24 Solo Trial

Plan: `feature-c21-c24-solo-trial-plan.md`, bound to run `2026-08-16T15-20-51-352Z-C21-C25`.

Scope note recorded at bind time: the run was requested as C21–C25. C25 (quick chat wheel) was split
off into a separate run before planning, so this plan and this log cover **C21–C24 only**.

---

## Phase 1: The isolation contract — types, config, and the remote surface — 2026-08-16

**Steps completed:** 1.1, 1.2, 1.3

**Files changed:**
- `src/shared/Types.luau` — added `TrialPhase`, `TrialBeat`, `TrialEndReason`, `TrialStartVerdict`,
  `TrialSnapshot`, `TeachingCueId`
- `src/shared/Config.luau` — extended the existing `Trial` block (beats, rig speeds,
  `PlayerBaselineWalkSpeed`, `SnapshotInterval`); added `RequestStartTrial` / `RequestEndTrial` to
  `AntiCheat.Budgets`; added `Community.LobbyTipSeconds`
- `src/shared/Remotes.luau` — `TrialSnapshot` and `TeachingCue` into `EVENTS_DOWN`;
  `RequestStartTrial` and `RequestEndTrial` into `EVENTS_UP`
- `tests/anti-cheat-budgets.test.luau` — **deviation, see below**

**Deviations from plan:**

1. **`tests/anti-cheat-budgets.test.luau` needed syncing, and the plan does not mention it.** That file
   carries a hand copy of `EVENTS_UP` — necessary because `Remotes.luau` calls `game:GetService` at
   module scope and Lune cannot require it — and its own header says the copy can drift and was "last
   synced at C15". Adding two up-remote budgets in Step 1.2 tripped the reverse assertion (*the budget
   for X names a remote that exists*) for both. Added both names to `UP_REMOTES` and moved the sync
   marker to C21. This keeps **both** directions of the invariant live rather than relaxing either: the
   two new remotes must now also carry budgets, which they do. The plan's own Follow Ups already name
   the clean fix — a check script parsing both files — and it is still not built here.

2. **`TrialEndReason` is wrapped across six lines, not the plan's one.** The plan's literal diff is 103
   columns and StyLua enforces 100. Mechanical; `npm run fmt` produced it.

**Gate:**
- `npm run analyze` — ok, 0 errors / 0 warnings / 0 parse errors
- `npm run check:remotes` — ok (28 declared, 19 wired; the 4 new ones are declared-not-yet-wired, which
  is correct at this phase — they are wired in Phases 3, 5 and 6)
- `npm run check:secrecy` — ok
- `npm run check:config` — ok
- `npm run fmt:check` — ok
- `npm run verify` — **green end to end, `test:unit` 25/25 files**

**Notes for the playtester and auditors:**

- Phase 1's real deliverable is what was **not** changed. `Types.RoundPhase` and `Types.PlayerState`
  both stayed shut — they were approaches A and B in the plan's §1.1 and both were rejected. If a later
  phase adds a member to either, the design has drifted back into the shape C21's row warns about.
- `TrialPhase`'s literals (`TRIAL_OFF` / `TRIAL_TASKS` / `TRIAL_CHASE` / `TRIAL_HANDOFF`) intersect
  `RoundPhase`'s (`IDLE` / `INTERMISSION` / `STARTING` / `ACTIVE` / `ENDING`) in nothing, and
  `TrialSnapshot` shares no field name with `ClientRoundSnapshot`. Luau unions are structural, so this
  is the compile-time half of the isolation guarantee — worth re-checking by eye in review, because
  neither `check:remotes` nor `check:secrecy` can see a semantic mix-up.
- No `config-ok:` waiver appears in this phase, which the plan predicted: every number added is balance
  and belongs in `Config`.
- Nothing here is wired to a handler yet, so `check:ratelimit` has nothing to say about the two new
  up-remotes until Phase 3.2. That is the phase to check the `AntiCheatService`-first ordering, not
  this one.

---

## Phase 2: The decisions, as pure modules with terminal tests — 2026-08-17

**Steps completed:** 2.1, 2.2, 2.3

**Files changed:**
- `src/shared/pure/TrialAdmission.luau` — new. `evaluate` (may a session open) and `mustEnd` (must a
  live session close)
- `tests/trial-admission.test.luau` — new. 147 assertions over 16 cells and 4 properties
- `src/shared/pure/TrialTimeline.luau` — new. `dueBeats` and `phaseAt`
- `tests/trial-timeline.test.luau` — new. 40 assertions over a full 90-second walk
- `tests/config.test.luau` — 7 trial invariants appended

**Deviations from plan:** none.

**Gate:**
- `lune run tests/trial-admission.test.luau` — PASS, 147 assertions
- `lune run tests/trial-timeline.test.luau` — PASS, 40 assertions
- `lune run tests/config.test.luau` — PASS, 50 invariants (was 43)
- `npm run verify:fast` — analyze / remotes / secrecy all ok

**Notes for the playtester and auditors:**

- The plan named `mustEnd` implemented as `evaluate(...) ~= "OK"` as the single most likely wrong turn
  in this phase, because it produces a plausible service that fails only under a specific join timing —
  a third player joining at IDLE would kill a running trial before any round started. It is implemented
  as a separate predicate over the phase alone, and `tests/trial-admission.test.luau` property 3 pins
  the distinguishing cell: at IDLE with population at the threshold, `evaluate` is `TOO_MANY_PLAYERS`
  while `mustEnd` is false.
- `TrialTimeline.dueBeats` returns a LIST, and the hitch test is the reason. A tick that jumps 39→60
  owes `BEAT_SALT_GIVEN`, `BEAT_TRANSFORM` and `BEAT_SALT_TAUGHT` together; dropping any of them has no
  runtime symptom, it just teaches the tutorial wrong once for one player.
- Neither pure module requires `script.Parent.X`. Both re-declare their unions locally, which is what
  keeps the two Lune verify lines runnable at all.
- Both modules sit in `src/shared/pure/` and are therefore requirable and runnable by any client. Safe
  here on the plan's argument: neither takes a seed or a draw input, and both of `TrialAdmission`'s
  inputs (phase, headcount) already reach every client via `RoundSnapshot`.
- `AT` in `TrialTimeline` has exactly six entries. A seventh beat is where a PvE campaign would start,
  and this is the cheapest file in the plan to add one to.

---

## Phase 3: `TrialService` — sessions, mutual exclusion, and the remote surface — 2026-08-17

**Steps completed:** 3.1, 3.2, 3.3, 3.4

**Files changed:**
- `src/server/Services/TrialService.luau` — the 28-line stub became the service: session table,
  `PhaseChanged` abort, `PlayerRemoving`/`CharacterAdded` teardown, both up-handlers, the snapshot push,
  the tick, and hold-to-complete over trial-only points
- `src/server/Services/TaskService.luau` — `discoverPool` now skips parts attributed `TrialOnly`
- `src/shared/Config.luau` — added `Trial.SpawnLiftStuds`
- `src/shared/pure/TrialTimeline.luau` — `dueBeats` return widened to `{ string }` (see deviations)
- `tests/trial-admission.test.luau` — summary line no longer hardcodes a count

**Deviations from plan:**

1. **`dueBeats` returns `{ string }`, not `{ TrialBeat }`, and `TrialService.asBeat` narrows.** The plan
   assumed a one-step `:: Types.TrialBeat` at the call site, matching `RejoinResolve`'s precedent. That
   does not work for a LIST: the literals do not survive `require`, and `::` on the resulting plain
   `string` distributes across the union rather than narrowing it. Full ledger, three measurements and
   the eight failed attempts are in `attempts.md` beside this log. The replacement is a six-branch
   narrowing function that also rejects unknown ids, which the cast would not have done.
2. **The map attribute is `TrialOnly`, not the plan's `TrialZone`.** `check:scope` refuses "Zone" —
   it is on §3's OUT list because of the competitor's seven zones (Appendix C.5) — and four waivers to
   keep a name would have been worse than a rename. `TrialOnly` also states the actual contract:
   exclude this point from the round's draw. **`tools/greybox/barrio.luau` must set `TrialOnly`.**
3. **`Trial.SpawnLiftStuds` added.** `check:config` caught the hardcoded lift on the spawn teleport.
   Config rather than a `config-ok:` waiver, because it genuinely needs tuning against zone geometry.
4. **A mid-trial respawn ends the session.** Phase 3's own review flagged this and the plan deferred it
   to Phase 4; it is implemented here because leaving it out means a player who presses Escape → Reset
   is teleported to the lobby with a trial still ticking. `CharacterAdded` ends the session.

**Gate:**
- `npm run analyze` — ok
- `npm run check:ratelimit` — ok (every OnServerEvent consults AntiCheat)
- `npm run check:secrecy` / `check:config` / `check:scope` / `check:debug` / `check:testcount` — all ok
- `npm run check:remotes` — ok (28 declared, 22 wired)
- `npm run verify` — **green end to end, `test:unit` 27 files**

**Notes for the playtester and auditors:**

- The isolation claim is worth checking by reading rather than by running: `TrialService` calls exactly
  two things on `RoundService` — `GetPhase()` and `PhaseChanged.Event:Connect`. No `setPhase`, no
  `SetTasksCompleted`, no `EndRound`, no `MarkKilled`, no `GetAswangUserId`, no `state.PlayerStates`.
- `TaskService.discoverPool`'s new `TrialOnly` filter is the half of the separation that is easy to
  lose. Without it a real round can draw an objective into the trial corner — a task nobody can find,
  appearing at random every few rounds, with nothing logged.
- The trial has no rig, no salt and no handoff yet; beats only log. That is Phase 4.
- `trialPoints()` returns empty until the greybox zone exists, and every caller tolerates it — the
  trial simply expires at Duration. Nothing errors, so an empty result is NOT evidence the code is wrong.

---

## Phase 4: The scripted chase, the salt, and the handoff (C22) — 2026-08-17

**Steps completed:** 4.1, 4.2, 4.3, 4.4

**Files changed:**
- `tools/greybox/barrio.luau` — the walled `TrialCorner` at (-300, 300): floor, four walls, a
  `TrialSpawn` anchor, two `TaskPoint` anchors attributed `TrialOnly = true`, a `TrialChase` anchor and
  a lantern. Header contract table and the build receipt both extended.
- `src/server/Services/TrialService.luau` — `buildRig`, `stepRig`, `grantSalt`, the `handleBeat` arms
  for `BEAT_SALT_GIVEN` and `BEAT_TRANSFORM`, the stun, and pouch teardown in `endSession`.

**Deviations from plan:**

1. **⚠️ THE THROW IS NOT TAUGHT, AND THIS IS THE ONE THING IN THE PLAN I COULD NOT DELIVER AS WRITTEN.**
   §9.1 asks that the player "learn to throw salt". `ItemService` resolves `RequestThrowSalt` through
   `pure/SaltThrow` with `Phase = RoundService.GetPhase()`, and a trial runs while the phase is IDLE —
   so the verdict is `WRONG_PHASE` and a trial player's throw is refused by the existing path. The plan
   asserted the trial would "watch for a hit on its own rig" without noticing that nothing can produce
   one. What is delivered instead: the pouch is granted at `SaltGivenAt`, and bringing it within
   `Config.Salt.PickupRangeStuds` of the rig stuns the chase for `Trial.ChaseStunSeconds`. **The player
   learns that salt stops the aswang; they do not learn the throw.** The two ways to close it are a
   trial-local throw remote (a fifth remote this plan did not declare) or relaxing ItemService's phase
   gate for players in a trial (a change on the 🔒 surface, coupling the two services this plan exists
   to keep apart). Both are decisions rather than details and neither was taken unilaterally.
2. **The rig is hand-built parts, not a stock R15 dummy.** The plan's `spawnRig` sketch said "built
   from a stock R15 dummy"; there is no dummy asset in this repo and inserting one is an asset-pipeline
   decision. Four anchored parts tinted and scaled from `Config.Monster` deliver the same tell.
3. **`RIG` layout block with `config-ok:` waivers**, following `OnboardingController`'s precedent —
   rig proportions are model dimensions, and putting a prop's proportions in the file M12 retunes
   balance from would be worse. The trial's actual balance numbers are all in `Config.Trial`.

**Gate:** `npm run verify` green end to end — analyze, all five checks, `test:unit` 27 files.

**Notes for the playtester and auditors:**

- **Three Roblox behaviours are unconfirmed and the plan said so in advance:** whether a server-created
  anchored Model streams reliably to a nearby player under `StreamingEnabled`, whether the rig reads as
  *moving* when driven by `PivotTo` rather than a Humanoid, and whether it is visible at all from the
  trial corner. A screenshot at the chase beat is what settles all three.
- The rig never goes near `MonsterService`, `RoleService` or `GetAswangUserId`. It has no UserId and no
  role, and no `MonsterTransformed` broadcast is fired for it — that remote means "a player's character
  transformed" and every client branches on it.
- `barrio.luau` has NOT been run against Studio in this session, so the trial corner exists in the
  generator and not yet in the place file. Until it is run, `trialPoints()` and `trialSpawn()` return
  empty and a started trial expires harmlessly at Duration without teleporting anyone.

---

## Phase 5: The client side of the trial — 2026-08-17

**Steps completed:** 5.1, 5.2, 5.3

**Files changed:**
- `src/client/Controllers/OnboardingController.luau` — `ensureHint`'s hardcoded text removed; new
  `OnboardingController.ShowLine(text)` with a `lineToken` re-arm guard; the C20 arrival path became
  its first caller
- `src/client/Controllers/TrialController.luau` — new. Renders the trial panel, delegates every word
- `src/client/init.client.luau` — `TrialController` registered after `OnboardingController`

**Deviations from plan:** none.

**Gate:** `npm run lint` 0/0/0, `npm run analyze` ok, `npm run verify:fast` ok.

**Notes:**
- The trial panel is top-LEFT. The sunrise timer is top-centre and the task bar beside it; putting
  trial numbers in either slot is the confusion the separation exists to prevent.
- `TrialController` requires `OnboardingController` — a controller requiring a sibling is a new pattern
  in this codebase. It is one-way by construction: `OnboardingController` knows nothing about trials.
- `BEAT_TRANSFORM` deliberately has no copy. §9.1 says "you learn the tell"; a caption over a transform
  tells you what you are seeing instead of letting you see it.

---

## Phase 6: C23 — the contextual teaching pass — 2026-08-17

**Steps completed:** 6.1, 6.2, 6.3, 6.4

**Files changed:**
- `src/shared/pure/TeachingLines.luau` — new. `resolve(cueId, seen)` plus `ids()`
- `tests/teaching-lines.test.luau` — new. 38 assertions
- `src/server/Services/TeachingService.luau` — new. The per-user seen-set and the `TeachingCue` fire
- `src/server/Services/ItemService.luau` — `CUE_FIRST_SALT` on first pickup
- `src/server/Services/GhostService.luau` — `CUE_FIRST_GHOST_DEATH` on becoming a ghost
- `src/server/Services/MonsterService.luau` — `CUE_FIRST_TRANSFORM_SEEN` after the broadcast
- `src/server/Services/TaskService.luau` — `CUE_FIRST_TWO_PERSON` when a TWO_PERSON point is understaffed
- `src/server/init.server.luau` — `TeachingService` registered
- `src/client/Controllers/OnboardingController.luau` — the `TeachingCue` handler

**Deviations from plan:**

1. **The two-person cue reads `presence`, not `weights`.** The plan implied the participant table was
   iterable by UserId; `weights[task.Id]` is an array of weights with the UserIds already discarded.
   `presence` is keyed by UserId and written only by a player's own `RequestTaskProgress`, so a player
   can still only ever cue themselves — the property the plan cared about is preserved.
2. **`TeachingLines.ids()` added** beyond the plan's `resolve`, so the test can assert the cue table is
   closed at four rather than trusting a hand count. C23's row lists exactly four moments.

**Gate:** `lune run tests/teaching-lines.test.luau` PASS (38), `npm run verify` green, 28 test files.

**⚠️ The one thing for `exploit-auditor` to look at first:**
`MonsterService` cues **every player**, in the same frame as the `MonsterTransformed` broadcast, which
is itself `FireAllClients`. That is deliberate and the audiences match exactly. **Narrowing it by
proximity would look like an improvement and would be a leak** — the subset would be computed from the
Aswang's position and delivered per-player, outliving the broadcast that justified it. The cue names
nobody: it resolves to "That is the tell. Run, or salt it."

---

## Phase 7: C24 — the lobby is not dead — 2026-08-17

**Steps completed:** 7.1, 7.2, 7.3

**Files changed:**
- `src/client/Controllers/UIController.luau` — the IDLE status line, the rotating tips panel, and the
  Trial door

**Deviations from plan:**

1. **§9.3's cosmetic preview stand is not built.** The architect scoped it out (map geometry plus a
   `MonetizationService` equip path, neither in C24's row) and I did not add it. C24's done condition —
   three things to look at and a countdown always visible — is met by the status line, the tips and the
   Trial door. Flagged as a deliberate scope reduction, not a completed item.

**The finding that shaped the phase, and it was a real bug:** `RoundService` leaves `PhaseEndsAt` at 0
during IDLE because IDLE has no duration, so `GetSecondsRemaining` honestly returns 0 — and
`UIController` was rendering `0:00` in the largest type on screen for the entire time a server sat
empty. A stopped clock reads as *broken*, not as *waiting*, which is exactly the §9 item 3 failure C24
exists to delete. IDLE now shows a headcount sentence instead.

**Gate:** `npm run verify` — **green end to end**, analyze + all five checks + 28 test files + harness.

---

## Review round — 2026-08-17

Three reviewers ran: `playtester` (six live trial sessions), `exploit-auditor` (84/100),
`auditor` (74/100). Every finding below is fixed in one pass; nothing was deferred.

### Corrections to what this log previously claimed

1. **Phase 7's gate line said `npm run verify` was "green end to end". That stopped being true after
   I wrote it** — I set `Debug.VerboseLogging = true` for the playtester, which fails `check:debug`.
   Both auditors caught the tree red while the log asserted green. The flag is now reverted and the
   gate is genuinely green; the original claim was accurate when made and stale within the hour,
   which is exactly why `claim-check` exists.
2. **Phase 6's deviation #2 called `TeachingLines.ids()` an addition. It is a rename** of the plan's
   own `all()`, not a purely additive function.

### Findings fixed

| # | Finding | Found by | Fix |
| --- | --- | --- | --- |
| 1 | `TRIAL_OFF` unreachable on the wire — Step 4.4's teardown push was never written, so the trial panel never cleared | both auditors, then observed live | `endSession` sets `TrialPhase = "TRIAL_OFF"` and pushes a final snapshot **before** clearing the entry |
| 2 | Respawn handler: no `PlayerAdded` backfill, **and** wrong end reason | exploit + plan auditors | Rewritten, not patched — see below |
| 3 | Rig stopped at 1.70 studs, not 6 | playtester, with measurements | `stepRig` clamps its step; `ChaseWalkSpeed` 13 → 12; new config invariant |
| 4 | Pouch found by global name → concurrent trials cross-destroy | exploit-auditor | Pouch owned by its `Session`; `SaltSpawn` tag dropped |
| 5 | Two-person cue skipped the `taskPointAt` re-check the loop above it does | plan auditor | Re-asks the world before cueing |
| 6 | Transform-cue audience equality held only by adjacency | exploit-auditor | One `announceTransform` helper owns both the broadcast and the cue loop |
| 7 | `TrialEndReason.COMPLETED` was a dead enum member | plan auditor | Fired when the clock expires with all tasks done — a documented decision replacing a silent omission |
| 8 | `teardown` destroyed the Frame, leaking a `ScreenGui` per trial | exploit-auditor | Destroys the `ScreenGui` |

### Why the respawn handler was rewritten rather than patched

Two independent reviewers found **two different defects in the same five lines**. Per
`.claude/lessons/green-after-each-patch-hides-a-loop.md` that is a redesign signal, not two fixes.

- **No backfill.** It connected `PlayerAdded` and stopped, so anyone already in the server when
  `Start()` ran never got a `CharacterAdded` connection — and the Solo Trial's entire target
  population is the first one or two players on a fresh server. `GhostService`'s own comment records
  that a previous exploit audit flagged `ItemService` for this identical omission.
- **The wrong end reason.** `PLAYER_ASKED` rather than `PLAYER_LEFT`, and the reason is a *branch*:
  `endSession` restores the character's CFrame for every reason except `PLAYER_LEFT`, so it wrote
  `ReturnCFrame` onto a character `RoundService.watchForDeath` was repositioning on the same frame.
  That is the body-contention race the design avoided by ending the session in the first place.

### The rig fix is a shape change, not a tuning one

`stepRig` checked the stop distance and then moved a fixed `ChaseWalkSpeed * delta`, which is correct
only while one tick's travel is smaller than the whole stop radius. At 13 studs/s × 0.5 s that is 6.5
studs against a 6-stud radius, so the rig stepped over the zone the check guarded and landed at 1.70
studs — measured, every run, in `artifacts/rig-movement-log.txt`. The step is now clamped, so the stop
is correct for **any** values. `ChaseWalkSpeed` moved to 12 so the new invariant also holds, rather
than weakening the invariant to fit the number.

**Gate after all fixes:** `npm run verify` green end to end — analyze, lint, format, all five checks,
`check:debug`, `check:testcount`, `test:unit` 28 files, harness. `tests/config.test.luau` now pins 51
invariants.

### Still open, and not fixed here

- **The salt THROW is still not taught** (unchanged from Phase 4's deviation 1). The playtester
  confirmed the stun itself works by carrying the pouch to the rig, so C22's lesson lands; the throw
  needs either a fifth remote or an `ItemService` phase-gate change, both of which are decisions.
- **The rig moves at snapshot cadence (2 Hz), so its approach is visibly stepped.** The clamp makes
  the stop correct but not the motion smooth. Moving the rig on `Heartbeat` while leaving snapshots at
  0.5 s is the real answer and is a change the playtester could not re-verify in this round.
- **Round-starting mid-trial was never observed** — it needs a second Studio client, which no agent
  can drive. The abort path is proven only by reading.
- `UIController` hardcodes `AlreadyInTrial = false` for the door's display check. Harmless: the server
  refuses with `ALREADY_IN_TRIAL`.
