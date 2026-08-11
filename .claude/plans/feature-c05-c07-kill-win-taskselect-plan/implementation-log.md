# Implementation Log — C05–C07

Run `2026-08-11T12-00-31-501Z-chunk` · plan hash `23e56d93d2af` · base `35ea83244f6c`

---

## Phase 1 — Spectator body containment (the C04 remnant)

**Status:** complete. All four steps pass `npm run verify:plan`; `npm run verify` green.

### Step 1.1 — the Studio probe

`artifacts/spectator-premise.md`. **The premise holds:** `Players.CharacterAutoLoads` reads `true` in
this place file, so the gitignored place was not quietly doing containment. One `SpawnLocation`, enabled
and neutral, so `LoadCharacterAsync` has a destination. `PlayerState` attribute `nil` and zero tags on
the player — the negative control passed, no secrecy leak.

I also exercised the plan's **highest-risk unverified assumption** (Follow-up #1) live before writing any
code, rather than after: `CharacterAutoLoads = false` genuinely suppresses the automatic respawn
(`Character` still `nil` six seconds after destruction, at double `RespawnTime`), and `LoadCharacterAsync`
spawns at the `SpawnLocation`. Both confirmed. That was the line that would have made the game unplayable
if the documentation had been wrong about this place.

**One correction to the plan's reasoning, recorded in the artifact.** Step 1.4's comment claims the
`player.Character == nil` guard is "load bearing rather than an optimisation", implying a second
`LoadCharacter` on an embodied player is unsafe. It is not — probed directly, it succeeds and respawns
them. The guard is still required, but for a different reason: without it every `setAllPlayerStates`
call teleports every already-embodied player back to spawn, including no-op LOBBY→LOBBY transitions.
Stated accurately so nobody later removes it believing it guards nothing.

### Steps 1.2 / 1.3 — `pure/PlayerBody.luau` and its test

Built as written in the plan. Two allowlists, not one: `mayHaveBody` admits LOBBY and ALIVE,
`mayBeKilled` admits ALIVE alone. Eight cells plus three properties, all passing —
`PASS player-body: 8 cells + 3 properties`.

### Step 1.4 — `RoundService` owns every character load

Built as written **except for one forced deviation and its two consequences.**

**1. `LoadCharacter` is deprecated; the analyzer refuses it.** `luau-lsp` reports
`DeprecatedApi: Member 'LoadCharacter' is deprecated, use 'Player:LoadCharacterAsync' instead`, and
`analyze-baseline.json` is empty — this repo blesses no diagnostics, so the deprecated call cannot land
and widening the baseline for it would be the wrong trade. Switched to `LoadCharacterAsync`.

**2. The Async form yields, and `applyBodyRule` must not.** This is not a style preference.
`enterStarting` calls `setAllPlayerStates` and then reads `dealtInUserIds()` **before** `setPhase`,
deliberately — `RoundService.luau:304-307` says why: no subscriber may observe a STARTING round with no
Aswang. A yield inside the loop would put the role draw on the far side of every player's character load,
and a player disconnecting in that window would change the roster mid-transition. Wrapped the load in
`task.spawn` + `pcall`, which keeps every caller synchronous and leaves C01's transition ordering exactly
as it was.

**3. The async call cost an invariant the synchronous version had for free, so I restored it.**
`applyBodyRule` was no longer idempotent: `Start()`'s backfill loop calls `onPlayerAdded` for players who
joined in the connect window — and its comment at `RoundService.luau:504-507` *promises* that repeat is
safe — but two calls in the same frame both see `Character == nil`, because the first load has not landed,
and both fire. Added a `pendingLoads` table keyed by UserId, cleared on completion and on
`onPlayerRemoving`. The spawned closure also **re-applies the rule after the yield**: a player who was
LOBBY when the load started and SPECTATOR when it finished would otherwise keep the body this rule exists
to deny them — the C04 hole, reopened by my own deviation.

Call sites: `onPlayerAdded` (join, and the `Start()` backfill reaches it), and `setAllPlayerStates` after
the whole table is written. Step 4.1's `MarkKilled` adds the fourth.

### Verification

- `lune run tests/player-body.test.luau` — PASS
- `npm run verify:plan` — Steps 1.1–1.4 all PASS
- `npm run verify` — green: analyze, selene, StyLua, all five repo checks, `check:debug`, 7 Lune suites
- **Live Studio, `artifacts/console-phase1-body-rule.txt`** — `CharacterAutoLoads = false` set by
  `RoundService.Start`; the lone player keeps a body across two full round cycles and seven phase
  transitions; **position constant at (3,4,-2) throughout**, which is the `Character == nil` guard
  working — without it each `setAllPlayerStates` would have teleported them to the SpawnLocation at
  (4,4,2). Zero warnings, no pcall trip.

**NOT verified, and it is the phase's own subject:** an actual mid-round joiner becoming `SPECTATOR` and
being denied a body. Studio's player count is a UI action no agent can drive. What is proven is the
mechanism (the flag is respected, the allowlist is exhaustively tested, the rule runs at every state
change) and not the end-to-end scenario. This belongs on the same NOT VERIFIED list as C05's success path.

### Note for whoever reads the cursor (Phase 1)

`npm run verify:plan` already reports **PASS for Steps 4.1–4.6, 5.1, 5.3 and 6.1**, none of which are
built. Their `**Verify:**` lines are `npm run analyze` / `npm run verify:fast`, which pass on a tree where
the step's file does not exist. The plan lints as "0 self-satisfying" because each command *can* fail in
principle, but they do not discriminate on these steps. The genuine gates are the five still failing —
2.1, 3.2, 5.2, 6.2 and 6.3 — and 6.3 is `npm run verify`, so the plan cannot report done dishonestly.
The per-phase progress signal for Phases 4 and 5 is mushy; the whole-plan one is not.

---

## Phase 2 — Foundation: the tunables, the invariants, and the kill's types

**Status:** complete. Both steps pass; `npm run verify` green.

**The driver named Phase 3 for this iteration, and I built Phase 2 first.** Phase 2 is the *earlier*
phase, so this is not pulling work forward — it is the dependency the cursor skipped. Step 2.1 was still
failing, and Phase 3's module is specified against `Config.Monster.KillRange`/`KillCooldown` and the
`KillVerdict` union Step 2.2 declares. Building Phase 3 onto an unbuilt Phase 2 would have been building
onto types that do not exist.

The cursor most likely skipped it because Phase 2 and Phase 3 both read "1/2 steps passing" — Step 2.2's
and Step 3.1's verify lines are both `npm run analyze`, which passes whether or not the file exists. Same
root cause as the Phase 1 note below.

### Step 2.1 — three Config keys, four invariants (21 → 25)

`Round.AswangWinSurvivorThreshold = 2`, `Monster.CorpseFadeTime = 1.5`, `Tasks.MinSpacingStuds = 20`,
each arriving with a *relationship* pinned in `tests/config.test.luau` rather than a value:

- the attrition win is reachable but not free on a full server (and deliberately does **not** pin the
  MinPlayers end — at 3 players §4.8 is degenerate for any threshold ≥ 1, which is Phase 5's clamp to fix)
- the corpse fades inside its own lifetime
- a body outlives the cooldown, so two kills can be evidence at once
- selected task points are spread further apart than the Aswang can reach

`PASS config: 25 balance invariants`. `Monster.KillRange`, `KillCooldown` and `CorpseDuration` were
already present from the scaffold and were not re-added, as the plan specifies.

### Step 2.2 — `KillVerdict` and `PlayerKilledPayload`

Built as written. The payload is two fields and the comment records why the third is absent, including
the `check-secrecy.mjs` gap: `PlayerKilled` is not on `REVEAL_ALLOWLIST`, so the field check never runs
on it, and the SECRET regex does not match `KillerUserId`. That gap is Issues Found row 1 and is why
`exploit-auditor` gates Phase 4.

---

## Phase 3 — `pure/KillValidation.luau`

**Status:** complete. Both steps pass; `npm run verify` green.

Built exactly as the plan specifies — no deviations. Seven conditions in a fixed order (phase → killer
alive → self → role → form → cooldown → target alive → target role → geometry), squared-distance
comparison, positions as plain `{X,Y,Z}` tables because Lune has no `Vector3`, `Range` and `Cooldown`
passed in rather than read so the knobs stay in `Config.luau`.

`PASS kill-validation: 16 grid cells + 21 cases`.

### The test was mutation-checked rather than trusted

It passed on the first run, which is exactly when a test deserves suspicion, so I broke the module twice
and confirmed the suite noticed:

| Mutation | Result |
| --- | --- |
| `<=` → `<` in `withinRange` | `FAIL  a target at exactly the range is within it` — 1 failure |
| `TargetState ~= "ALIVE"` → `TargetState == "SPECTATOR"` (allowlist → denylist) | 3 failures, on the `LOBBY` and `GHOST` rows and the ghost property |

The second mutation is the C04 bug in its exact original shape, and the 4×4 grid caught it on the two
rows a spot check would never have written. Module restored and re-run green after both.

### What Phase 3 does NOT establish

Every kill **refusal** is now proven from a terminal. Nothing about whether a kill **works** — the
raycast, the corpse, the broadcast and `MarkKilled` are all Phase 4, none of them reachable from Lune. A
green Phase 3 must not be reported as "the kill works"; the plan's §5 hands that to a human with a
second client.

---

## Phase 4 — MonsterService: the kill, the corpse, and the broadcast

**Status:** complete. All six steps pass. 🔒 — `exploit-auditor` is mandatory on this phase.

Built as the plan specifies, with **one forced deviation**.

### Deviation: the raycast filter could not be built as written

The plan's `hasLineOfSight` sets `FilterDescendantsInstances` to a literal containing
`corpses :: Instance`. That does not typecheck — `Folder?` does not cast to `Instance`, because the
optional is a union and the two are unrelated types. The plan's own Issues list flagged this exact line
("confirm this in the Phase 4 playtest rather than assuming, **or hoist the folder into Init()**"); the
analyzer answered before the playtest could.

Taken the third way: build the filter as a `{ Instance }` list and append the folder only when it exists.
That is also the honest reading of the nil case — if `Start()` has not run there is no corpse folder and
nothing to exclude, where an excluded `nil` would have been tolerated at runtime and silently wrong the
day it mattered.

### The rest, as written

`MarkKilled` in `RoundService` (GHOST, not a fifth state; guarded on ACTIVE and on the victim being
ALIVE so a duplicate request is a no-op). The corpse is the victim's **detached** character, anchored and
non-collidable, faded over `CorpseFadeTime` at the end of `CorpseDuration`. `commitKill` in the one order
that works — corpse first, then state, then revert (which is what starts the cooldown), then broadcast.
`Humanoid.Died` now forces a revert, closing C04's deferred finding. The client hook logs and does not
guess the killer.

`PlayerKilled` carries `{ VictimUserId, Position }` and nothing else.

---

## Phase 5 — The Aswang's win condition

**Status:** complete. All three steps pass. Built as written, no deviations.

`pure/WinConditions.luau` with the dealt-in clamp, `PASS win-conditions: 14 cases + 22 properties`, and
the predicate evaluated at the end of `MarkKilled` and nowhere else — not in `step()`, not on
`PlayerRemoving`. `DealtInSurvivors` is snapshotted after the draw in `enterStarting` and frozen, so a
disconnect moves neither side of the comparison and a losing survivor cannot void a round by quitting.

**The solo guard was verified live, not just in Lune.** Three consecutive solo rounds ran their full 60s
to sunrise. A solo round has zero survivors dealt in; had the guard been wrong, every round would have
ended within a tick of ACTIVE and every future chunk would have become unverifiable in the only
environment an agent can drive.

---

## Phase 6 — `pure/TaskSelection.luau`, the pure half of C07

**Status:** complete. All three steps pass. Built as written, no deviations.

Partial Fisher-Yates over a copy with a spacing filter and a mandatory fallback pass.
`PASS task-selection: 10000 draws, 12 distribution bands, spacing + 6 edge cases`.

The RNG is **injected**, deviating from C07's written `(pool, count, seed)` signature. That deviation is
the plan's and is the conforming choice against CLAUDE.md: this module replicates, so a `seed` parameter
would put a reproducible generator on the client's side of the wire and the Aswang would know every task
location before STARTING ended. `TaskService`'s header now records where the seed must come from at C17.

No discovery, no wiring, no `TaskService` behaviour — deliberately. `TaskPoint` appears nowhere in `src/`
until C17's greybox places the tags.

---

## Live verification — what three Studio sessions established

Artifacts: `artifacts/spectator-premise.md`, `artifacts/console-phase1-body-rule.txt`,
`artifacts/console-phase4-kill-refusals.txt`.

| Claim | Evidence |
| --- | --- |
| `WRONG_PHASE` vs `SELF` tracks the phase exactly, flipping at both boundaries | shot 4 in ENDING and 5-6 in INTERMISSION answer WRONG_PHASE; 1-3 and 7-14 in ACTIVE answer SELF |
| `SELF` precedes the role and form checks | refused identically transformed and untransformed |
| The rate limit on `RequestKill` | 8-call burst -> exactly 3 verdicts, then `[AntiCheat] Rate limit refused` |
| The verdict never reaches a client | every refusal is a server log line; no reply remote on any probe |
| C04's forced revert fires | `[Client] revert witnessed (yours)` at `MaxTransformTime` |
| The solo attrition guard | three rounds ran full-length to sunrise |
| `CharacterAutoLoads = false`, body retained across every transition | Phase 1 artifact, position constant across seven transitions |

### A probe design error, recorded rather than quietly fixed

PROBE-1 and PROBE-2 were aimed at `me.UserId + 1` — a UserId no player has — so `validateAndKill`
returned at its `target == nil` guard **before** `KillValidation` ran. They proved the nil-target early
return and nothing about `WRONG_PHASE` or `NOT_TRANSFORMED`. PROBE-1b re-ran the phase case correctly by
targeting self, which reaches validation because the phase check precedes the self check.

`NOT_TRANSFORMED` stays unreachable solo: it sits after `SELF` in the check order, so it needs a second
player. That is a fact about the check order, not a gap in the implementation.

---

## A harness bug found while verifying Phase 4 — NOT fixed, needs its own chunk

`check:remotes` reported `PlayerKilled` as "declared but not yet wired" while it was demonstrably fired
(server, `FireAllClients`) and listened to (client, `OnClientEvent`). The cause is a real hole rather
than a miscount:

```js
/Remotes\.Get\(\s*["']([\w]+)["']\s*\)([\s\S]{0,40})/g
```

The trailing context group is **consumed** by `matchAll`, so any `Remotes.Get(...)` within 40 characters
of a preceding one never yields its own match — and the direction checks (`isDown && isClient` fires,
`OnServerEvent` on a DOWN event, and the undeclared-remote check) all run off that same loop. Measured:

| Input | Names seen |
| --- | --- |
| two `Remotes.Get` declarations on adjacent lines | only the first |
| the same two, 43 blank lines apart | both |
| `Remotes.Get("MonsterTransformed").OnClientEvent...` then `Remotes.Get("PhaseChanged"):FireAllClients(x)` on the next line | **only the first — the direction violation is invisible** |

The fix is one character class turned into a lookahead — `(?=([\s\S]{0,40}))` — plus both-direction
self-tests in `harness-selftest.mjs`. **Deliberately not done here:** it is a harness change with its own
`SUITES` obligations, it is outside this plan's bound scope, and CLAUDE.md routes harness scripts to
`check:guards` + `change-auditor` rather than to this plan's reviewers.

`PlayerKilled`'s direction was verified by hand instead: declared in `EVENTS_DOWN`, fired from
`src/server/` with `FireAllClients`, listened to in `src/client/` with `OnClientEvent`.

---

## Post-plan work — the review round, and the four fixes that came out of it

Everything below happened **after** the six phases were complete and `goal-check` reported DONE. It is
recorded here because an `auditor` correctly found that this log and `verification.md` had stopped being
a complete account of the diff: both were written before this work, and the section above still said the
harness bug was "deliberately not done here", which the first request below made false.

### 1. `check:remotes` was blind to adjacent remotes — FIXED

The scan matched `Remotes\.Get\(...\)([\s\S]{0,40})`, and `matchAll` **consumes** that trailing context.
Any `Remotes.Get(...)` within 40 characters of a preceding one produced no match of its own — and every
direction check runs off that loop, so a client firing a DOWN event, a wrong-direction listener, or an
undeclared remote name went unflagged whenever it followed a nearby `Get`. Found because `PlayerKilled`
reported "declared but not yet wired" while being demonstrably fired and listened to.

Fixed with a lookahead, `\)(?=([\s\S]{0,40}))`. Four self-tests added — two BLOCK, one ALLOW, one direct
assertion on the `used` set — and they are the first cases in that file to use **two** `Remotes.Get`
calls, which is why the bug survived there for so long. Verified in both directions: reverting the
lookahead in a scratch copy gives `14/17` with the two BLOCK cases reporting `expected BLOCK, got ALLOW`.

### 2. The kill had no input — FIXED

`RequestKill` had no button, key, touch handler or prompt anywhere in the tree; it was reachable only
from a console. `InputController` now binds `F` → `AswangKill`, gated on the client's own role, selecting
the nearest other player within `Config.Monster.KillRange`. `createTouchButton` is `false`, matching the
existing `T` bind, so **mobile still cannot kill or transform** — that is C27's subject and it is stated
in the file header rather than left to be rediscovered.

### 3. Four bugs from the review round — ALL FIXED AND RE-TESTED

Evidence: `artifacts/console-fixes-retest.txt`, plus `artifacts/console-finding2-no-respawn.txt` for the
before-state of the first one.

| # | Severity | What was wrong | Fix |
| --- | --- | --- | --- |
| 1 | **High** | Turning `CharacterAutoLoads` off made RoundService the only thing that can spawn a body, but nothing was wired to **death**. A player who reset or fell out of the map stayed a corpse for the rest of the server session AND stayed `ALIVE` in PlayerStates, so `livingSurvivorCount` kept counting them and §4.8's attrition win could never fire. Reproduced live: 64s, three rounds, `alive 1 · you: ALIVE` throughout | `watchForDeath` on every `CharacterAdded`. A death in ACTIVE routes through `MarkKilled` → GHOST (which also closes reset-to-escape); a death outside a round respawns |
| 6 | Low | `clearCorpses` ran on every non-ACTIVE phase, so `MarkKilled → EndRound → ENDING` destroyed the winning kill's corpse while `commitKill` was still on the stack — the one round where bodies matter most had none | clear on INTERMISSION/IDLE instead |
| 7 | Low | `range * range` maps `-8` onto the same 64 as `8`, and a NaN cooldown made the gate never trip. Degenerate Config values failed **open** | `range > 0 and range < math.huge`, plus a NaN cooldown test, both fail closed. Five new test cases |
| 5 | Medium | `check:secrecy`'s broadcast rule read the **argument text**, so the typed-local payload idiom this repo's own comments recommend reduced the scan to the word `payload`. Its SECRET regex also matched no `Killer*` token. A killer field on `PlayerKilled` would have typechecked, scanned clean and shipped green | rule 1 now resolves the payload via `payloadFieldsAt` (which rule 2 already used); SECRET matches `killer\w*` and `aswang\w*` as prefixes. Three new self-tests |

**Fix 7 caught a hole in its own first attempt.** `not (range > 0)` let `math.huge` through — `25000000
<= inf` granted a kill from 5000 studs — and the test found it before it landed. The guard became
`range > 0 and range < math.huge`, written as one negated conjunction so NaN fails it too.

**Fix 5 was verified by injecting the real leak into the real file**: adding `KillerUserId = killer.UserId`
to the live `PlayerKilled` payload now turns `check:secrecy` red. Before the fix it scanned clean. The
file was restored afterwards and the comments in `Types.luau` and `MonsterService`'s header that claimed
this was *un*catchable have been corrected — they were true when written and are not now.

### Reported, deliberately NOT fixed

**The kill's geometry comes from a position the killer's client owns** (High, `exploit-auditor` finding 3).
`killerRoot.Position` feeds both the range check and the raycast origin, and the killer has network
ownership of that part. Teleport beside a victim, fire, teleport back — both of §4.3's geometric rules
pass. Bounded to once per 30s while visibly transformed, because the kill is gated on `Announced`.

This is spec §6.3's "speed/teleport sanity checks", scheduled to **C41**, and it needs position sampling
over time with a tolerance — a subsystem, not a patch. `Config.luau`'s own guidance argues against
bolting it on now: *"Tune these LOOSER than legitimate play, never tighter. A limiter that refuses a real
player is a gameplay bug that presents as lag."* An untuned teleport check shipped before M5 would refuse
legitimate kills on a bad connection and be indistinguishable from the mechanic being broken.

---

## Second fix round — three High findings, two fixes (they shared a cause)

The review round that followed the first fixes found that **Fix A had introduced three new problems**,
two of them worse than the bug it closed. Routing non-kill deaths through `MarkKilled` made "died" and
"was killed" the same event, and neither the role check nor the win-credit rule was ready for that.

Evidence: `artifacts/console-exploit-retest.txt`.

| # | Severity | What Fix A broke | Fix |
| --- | --- | --- | --- |
| 1 | **High** | **The Aswang could delete the round by pressing Reset.** `MarkKilled` had no role branch, so the Aswang became a GHOST, `KillValidation` then refused every kill on `KILLER_NOT_ALIVE`, and six players walked a monster-free Barrio for the remaining 420s. Repeatable every round drawn, without leaving the server. `onPlayerRemoving` **already** ends the round when the Aswang disconnects — Fix A opened a second door straight past that defence | `MarkKilled` mirrors it: dead Aswang → `enterEnding(ABORTED)` |
| 3a | **High** | **One survivor pressing Reset ended the round as ASWANG_WINS.** At MinPlayers = 3 the effective threshold is `min(2, 2-1) = 1`, so a single self-removal satisfied `1 <= 1`. `MarkKilled`'s own comment already said a *disconnect* must move neither side of the comparison; Fix A let a *reset* move one side and not the other | `MarkKilled(player, causedByKill)`. `commitKill` passes `true`; the death watcher passes nothing, and a non-kill death decrements `DealtInSurvivors` so both sides fall together |
| 4 | Medium | **Unrate-limited character rebuilds.** The respawn branch calls `LoadCharacterAsync` on a trigger any client can fire as fast as it can press Reset. Not a remote, so `AntiCheatService` never sees it and `check:ratelimit` structurally cannot cover it | `Config.Round.RespawnCooldown = 3`, enforced in the death watcher, with a new invariant pinning it well under `Intermission` |
| 6 | Low | The clock guards from round one covered `Cooldown` only. `LastRevertedAt = NaN` and `Now = inf, LastRevertedAt = inf` (`inf - inf = NaN`) both still failed **open** | Test the subtraction's RESULT, which subsumes a NaN in either operand |
| 5 | Low | `check:secrecy` rule 1 matched `:FireAllClients` only, and a per-player `:FireClient` loop reaches every client just as surely — `broadcastSnapshot` is written that way | rule 1 matches both; the remaining evasions are now written into the file header |

**I got Finding 6 wrong twice.** The first attempt guarded `Cooldown` alone; the second guarded each
operand individually and still missed `inf - inf`, because each operand passes an `x ~= x` test on its
own. Only testing the result works. Both misses were caught by tests written before the guard was
trusted, which is the argument for writing them in that order.

### What Finding 3a's fix cannot prove from a terminal

A solo round has no survivor to reset — only the Aswang — so the exploit is not reproducible in the one
environment an agent can drive. `tests/win-conditions.test.luau` pins the **arithmetic** (7 new cases:
a self-removal at any roster size must not win). That the *service* decrements is code, verified by
reading, not by observation. It needs two clients. Stated here rather than rounded up.

### The auditor's evasion table, kept rather than buried

The `exploit-auditor` defeated the repaired `check:secrecy` with **16 of 19** payload shapes. Two were
worth fixing (`:FireClient`, and the header's honesty). The rest — a field assigned after the
constructor, a helper-built payload, a bracket-string key, a nested table, a declaration more than 1200
characters away, a field named `Murderer` or `Attacker` — **still get through, by design**. The check
raises the cost of a mistake and does nothing against intent. That list now lives in
`check-secrecy.mjs`'s header so a green tick is never read as coverage.

---

## Third fix round — the throttle strand, the disconnect asymmetry, and the clock guards

The review of the second round found that **Fix 4 had reintroduced the bug Fix A closed**, in a worse
form, and that a second instance of the Fix 3a bug was living on the neighbouring code path with a
comment I had just written asserting it did not exist.

Evidence: `artifacts/console-throttle-strand-repro.txt` (the bug, reproduced live by an independent
playtester) and `artifacts/console-throttle-fix-retest.txt` (the fix, re-tested against that repro).

| # | Severity | What was wrong | Fix |
| --- | --- | --- | --- |
| 1 | **High** | **The respawn throttle stranded players permanently.** Its `return` fired ABOVE `player.Character = nil`, leaving a DEAD character attached — and `applyBodyRule`'s load branch is gated on `Character == nil`, so nothing ever repaired it. Not for 3 seconds: for the server session. STARTING still dealt the corpse in as ALIVE, so it stayed **eligible for the Aswang draw**, and if drawn, neither round-abort path could fire because `MarkKilled` never runs for it — a monster-free round, repeatable, no executor | Detach and destroy ALWAYS; throttle only the `LoadCharacterAsync` and **defer** it via `task.delay` rather than dropping it |
| 2 | **High** | **A disconnect still moved one side of the attrition comparison.** `DealtInSurvivors` is frozen but `livingSurvivorCount()` is computed live, and `onPlayerRemoving` nils the key. In an 8-player round, three alts quitting at ACTIVE turned a five-kill win into a two-kill win. Predates this round — but the second round's own comment claimed it was already handled | `onPlayerRemoving` decrements `DealtInSurvivors` for a departing survivor, mirroring the reset path. No win check there, deliberately: §6.4 says a round that loses players finishes |
| 3 | Low | The clock guard still failed **open** on a non-NaN INFINITE elapsed time (`inf < 30` is false) and on `Cooldown = -1`, which silently disabled the gate — one minus sign during M12 | Positive-and-finite on both, as one negated conjunction — the same idiom `withinRange` already uses |
| 4 | Low | My `killer\w*` widening made `check:secrecy` **false-positive on `FireClient(killer, …)`** — scanning the recipient, not the payload. The only escape is a waiver, which would permanently silence the most dangerous call site in the game | Drop the recipient argument before scanning, at depth zero so nested commas are safe |
| 5 | Info | The header's stated limits were understated — they listed only table-field shapes | Added the four structural classes: positional arguments, helper returns, replicated Instances, and **no RemoteFunction rule exists at all** |

### The pattern, stated plainly

**Three consecutive rounds of fixes each introduced a new defect on this surface**, and every one was
caught by an adversarial review rather than by the gate or by my own testing:

- Round 1 (`watchForDeath`) → three High findings, including a round-deleting exploit. The table above
  has two High rows rather than three because findings 1 and 2 shared a single fix: once a dead Aswang
  ends the round, the window in which a client could compute "the Aswang is already dead" from the
  replicated snapshot never lasts a tick. An audit flagged the mismatch between the prose and the
  table, which is fair — a section whose whole point is counting failures honestly should not make a
  reader reconcile two numbers.
- Round 2 (the throttle) → reintroduced round 1's bug, worse
- Round 3 (the clock guard) → **third** attempt at the same guard; the first two both shipped

The static gate was green at every step. The failures were never in a single line — they were in the
interaction between a new code path and an existing guard (`applyBodyRule`'s `Character == nil`), or
between a fixed path and its unfixed twin (`MarkKilled` vs `onPlayerRemoving`). That is exactly the
class a text check cannot see and a test suite does not think to cover.

### What is still NOT verified

- **The disconnect fix.** A solo round has no survivor to disconnect, so only the arithmetic is pinned
  in Lune. The `onPlayerRemoving` → `livingSurvivorCount()` sequence is verified by reading.
- **A kill succeeding at all**, and everything downstream of it — unchanged from the start.
- Both need two clients in Studio. Given this round's history, that session is the real gate.

---

## Fourth review — the disconnect fix DID NOT WORK, and the arithmetic needs a redesign

An `exploit-auditor` replayed event sequences through the **shipped** `WinConditions.luau` under Lune,
before and after the third round's fix, and the outcomes are identical for the case the fix targeted.

| Scenario | Without the fix | With the fix |
| --- | --- | --- |
| 8p, 3 alts quit at ACTIVE, then kills | ASWANG_WINS after **2** kills | ASWANG_WINS after **2** kills |
| 8p, nobody quits | 5 kills | 5 kills |
| 8p, 5 quit, then 1 kill | 1 kill | 1 kill |
| 8p, 5 quit then a survivor RESETS, no kills | ASWANG_WINS after 0 kills | no attrition win ← the only row that changed |

**Why it is inert.** `effective = math.min(Threshold, DealtInSurvivors - 1)`. With `Threshold = 2` the
`DealtInSurvivors - 1` term only binds when `DealtInSurvivors <= 3`. Above that, decrementing the
denominator moves `effective` not at all — while `livingSurvivorCount()` drops regardless. So the kills
required still fall one-for-one with every survivor who leaves. The fix closed exactly one shape,
disconnect-then-reset, and two comments in the tree now assert an exploit is closed while it is live.

### Not patched a fourth time — this is a rule-shape problem

Three hand-fixes have now been applied to this arithmetic and all three were wrong in a different way.
The rule is written as an absolute — "living survivors ≤ 2" — so ANY removal is worth a kill, and no
amount of bookkeeping on the denominator changes that while the numerator counts absence rather than
kills.

**The shape that works:** count what the Aswang actually did. Carry an `AswangKills` counter incremented
only by `commitKill`, and win when `AswangKills >= DealtInSurvivors - Threshold` (clamped for small
rosters). Then a quit, a reset, a fall and a disconnect all move neither side, which is what both
existing comments already claim.

That is a change to what §4.8 MEANS, not a repair — the spec's sentence and this predicate stop being
the same statement — so it is raised rather than quietly resolved, per CLAUDE.md's precedence rule. It
also wants its own exhaustive test over (kills × resets × disconnects × roster), which is the thing that
would have caught all three failed attempts.

### Fixed in this pass (small, isolated, verified)

| # | What | Verification |
| --- | --- | --- |
| 2 | **The deferred load had no retry**, and during ACTIVE it is the ONLY path that can restore a body. One throw left a player ALIVE with no character for the round — unkillable, but still counted, putting the attrition win out of reach. Same shape as round 1's bug via a different route | Re-arms on failure, guarded on presence and on the rule still wanting a body |
| 5 | `FireClient(killer)` with no payload still false-positived — `dropFirstArgument` returned the whole string when there was no comma | Returns `''`; self-test added |
| 6 | The finding message said `:FireAllClients` at a `:FireClient` site | Uses `match[0]` |
| 7 | The clock guard read `>= 0` while its comment claimed positive — `Cooldown = 0` silently disabled the gate | `> 0`, comment and code now agree |
| 4 | The `dropFirstArgument` self-tests could not tell the depth-aware split from a naive `indexOf(',')` — an audit swapped in the naive version and still got 29/29 | Added a case a naive split fails: a recipient whose own arguments look secret. Naive now scores 31/33 |
| 3 | "At most one deferred can be outstanding" was false — a phase change during the window loads without stamping | Comment weakened to what actually holds. Harmless in practice; `pendingLoads` is the real bound |

`check-secrecy` self-tests: 29 → 33. The clock guard now passes 22 of 23 degenerate cells and the audit
could not break it on NaN, ±inf, `inf - inf`, or a backwards clock — the first version of this guard
that survived a full grid.

---

## HALT report — every fix attempted on the two looped files, and the shape question

`guard-fix-rounds.mjs` halted on `RoundService.luau` (5 rounds) and `pure/KillValidation.luau` (4).
This is the report it demands, and the reason neither file is edited again until it is answered.

### 1. KillValidation's cooldown guard — five attempts, and the shape is RIGHT

| # | What was written | What it was wrong about |
| --- | --- | --- |
| 1 | `Cooldown ~= Cooldown` | Covered one input of three. `LastRevertedAt = NaN` and `Now = NaN` both returned OK |
| 2 | each operand tested individually | `inf - inf` is NaN even though NEITHER operand is. Missed entirely |
| 3 | `elapsed ~= elapsed` on the result | Subsumed every NaN — but a non-NaN INFINITE result still passed: `Now = inf, Last = 99` gives `elapsed = inf`, and `inf < 30` is false |
| 4 | `elapsed >= 0 and elapsed < math.huge`, same for `Cooldown` | 22 of 23 degenerate cells. `Cooldown = 0` passed, because it was written `>= 0` while the comment claimed positive |
| 5 | `Cooldown > 0` | Currently believed correct: 23/23 |

**What it measures:** has `Cooldown` elapsed since the last revert. §4.3 step 5 says the cooldown runs
from the revert, so this is exactly the right quantity, and the right three inputs.

**Verdict: do not redesign.** Every failure was DOMAIN COVERAGE, not shape — five attempts to enumerate
`{finite±, 0, ±inf, NaN}` across three inputs one bug at a time. The fix was never a different rule, it
was the grid, and the grid now exists (35 cases). Nothing here changes what the spec means.

### 2. RoundService — five rounds, and they were five DIFFERENT mechanisms

| # | Fix | What it was wrong about |
| --- | --- | --- |
| 1 | `watchForDeath` added | Before it, a death that was not a kill never respawned AND stayed ALIVE — 64s and three rounds measured, dealt into later rounds as a corpse |
| 2 | `MarkKilled` aborts on a dead Aswang | The Aswang could delete a round with the stock reset button; `onPlayerRemoving` already handled the disconnect twin, and round 1 walked past it |
| 3 | `RespawnCooldown` throttle | Its `return` fired above `Character = nil`, so it STRANDED players permanently — worse than the bug round 1 closed |
| 4 | throttle rewritten: detach always, defer the load | — believed correct |
| 5 | deferred load re-arms on failure | One throw left a player ALIVE with no body for the round: unkillable, still counted, attrition win unreachable |

**What it measures / does:** it owns four things at once — the phase, player round-state, player BODIES,
and the win check. The recurring failure is not one expression. It is that **"does this player have a
body" and "what is this player's round state" are two state machines with four entry points (kill,
death, phase change, disconnect) and no single place that reconciles them.** Every defect above was one
entry point being handled and its twin not.

**Verdict: the shape is wrong, and the fix is the one this repo already knows.** `pure/PlayerBody`
encodes the RULE (which states may hold a body) but nothing encodes the TRANSITIONS. The missing piece
is the body-side analogue of `pure/RoundTransitions.luau`: a table over
`(PlayerState × cause) -> action`, exhaustive over all four states and all four causes — sixteen cells
somebody can argue with, in a terminal, instead of four scattered call sites.

**Cost:** moderate, and internal. It changes no spec sentence: every behaviour is already specified,
just not in one place. It is the same move that made `RoundTransitions` and `KillValidation` the two most
reliable things in the repo.

### 3. The attrition rule — three attempts, all wrong, and this one IS a spec question

| # | Fix | What it was wrong about |
| --- | --- | --- |
| 1 | freeze `DealtInSurvivors` at STARTING | `livingSurvivorCount()` is computed LIVE, so a disconnect dropped one side of the comparison and not the other |
| 2 | decrement it on a non-kill death | Closed reset-then-reset only |
| 3 | decrement it on disconnect too | **Arithmetically INERT.** `effective = min(Threshold, DealtIn - 1)`; with `Threshold = 2` that term only binds at `DealtIn <= 3`, so above four survivors the denominator does nothing while the numerator falls anyway. Proven by replaying the shipped module: 8p with three alts quitting wins after 2 kills, with and without the fix |

**What it measures:** how many survivors are *currently alive*. **That is the wrong quantity.** §4.8's
intent is that the Aswang has KILLED most of them, and counting absence cannot tell a kill from a quit,
a reset, or a fall out of the map. No amount of bookkeeping on the denominator fixes a numerator that is
measuring the wrong thing — which is why three fixes in a row failed differently.

**The shape that works:** count the kills. An `AswangKills` counter incremented only by `commitKill`,
winning when `AswangKills >= DealtInSurvivors - Threshold`, clamped for small rosters. Then a quit, a
reset, a fall and a disconnect all move neither side — which is what two comments in the tree already
claim, falsely.

**Cost, and why it is not mine to decide:** §4.8 says *"Aswang wins when living survivors ≤ 2"* — a
statement about PRESENCE. The replacement is a statement about KILLS. They give different outcomes
whenever a player leaves, so this is not a repair, it is an amendment, and CLAUDE.md's precedence rule
puts it with the user. It also wants an exhaustive grid over
`(kills × resets × disconnects × roster)` — the test that would have caught all three failed attempts
on the first day.

**Until it is answered the exploit is live:** in an 8-player round, three alt accounts quitting as
ACTIVE begins turns a five-kill win into a two-kill win.
