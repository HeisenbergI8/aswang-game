# Implementation Log — V06 Feeding

## Phase 1: The rules, the numbers, and the invariant — 2026-08-28

**Steps completed:** 1.1, 1.2, 1.3, 1.4, 1.5, 1.6

**Files changed:**
- `src/shared/Config.luau` — `Monster.FeedLeashStuds = 6` added after `FeedHeal`; the `KillCooldown`
  comment rewritten to record that V06 did NOT retire it, with the six-reader count and the note that
  V06 changed *when* the countdown starts (the revert now happens at feed end).
- `src/shared/pure/FeedRules.luau` — new. `evaluate` / `mayContinue` over a named-field `Request`,
  six-value scalar `Verdict`, `withinRange` failing closed on NaN / infinite / negative.
- `tests/feed-rules.test.luau` — new. The full grid twice plus precedence, boundary and degenerates.
- `src/shared/Types.luau` — `FeedVerdict` (three values) and `FeedUpdatePayload` added after
  `SearchUpdatePayload`.
- `tests/config.test.luau` — three new invariants: §6.5 invariant 2 (feed outlasts a 15-stud crossing
  plus a swing), feed < MaxTransformTime, leash < KillRange.

**Deviations from plan:** none. StyLua reflowed `isOk`'s parameter list and three `check(...)` call
sites in `tests/feed-rules.test.luau` onto different lines than the plan's diff showed; content
identical.

**Gate:** `npm run verify` exit 0 — analyze ok · remotes ok (26/26) · secrecy ok · config ok · scope
ok · ratelimit ok · debug ok · testcount ok · 33 suites. `lune run tests/feed-rules.test.luau`
**777/777**. `lune run tests/config.test.luau` **119 invariants**.

**Notes for the playtester and auditors:**
- 777 = 750 grid cells (5 states × 3 bodies × 5 distances × 5 phases × 2 functions) + 16 precedence
  rows + 1 boundary + 4 degenerate distances + 4 degenerate ranges + 2 live-Config cross-checks.
- `BODIES` carries a trailing `nil` and is iterated `for bodyIndex = 1, #BODIES + 1`. A generic-for
  here silently drops a third of the grid. Do not "tidy" it.
- Nothing in `src/server/` changed in this phase, by design — everything provable from a terminal
  lands before anything that is not.
- `FeedLeashStuds = 6` is a guess with no playtest behind it. The invariant pins it below `KillRange`;
  the value is V16's to tune.

## Phase 2: The feed lifecycle in `MonsterService` — 2026-08-28

**Steps completed:** 2.1, 2.2, 2.3, 2.4, 2.5

**Files changed:** `src/server/Services/MonsterService.luau` only.

- `MonsterState` record gained `Feeding: boolean`, `FeedBody: Model?`, `FeedEndsAt: number?`;
  `stateFor` initialises all three.
- `monsterStateOf` added after `stateFor` — returns `Feeding and Transformed` → `FEEDING`, else
  `Transformed` → `TRANSFORMED`, else `NORMAL`. Never `EXPOSED` (a latch) or `CAMOUFLAGED` (no
  producer until V07).
- `MonsterService.FeedCompleted` BindableEvent declared beside the service table — the V07 seam.
  No listener in V06.
- New feed section immediately before `commitKill`: `bodyKindOf`, `feedDistance`, `endFeed`,
  `completeFeed`, `beginFeed`, `feedTick`.
- `commitKill`: `revert(killer)` → `beginFeed(killer, victimCharacter)`; header step 3 rewritten.
- `transform`'s forced-revert timer gained `and not monster.Feeding`.
- `Start` spawns the 0.25s `feedTick` loop with the mandatory `-- config-ok:` waiver.
- `FeedRules` added to the requires.

**Deviations from plan:** none in code. Two observations recorded below.

**Gate:** `npm run verify` exit 0. `npm run build` exit 0. analyze ok · remotes ok (26/26, unchanged
— this phase adds no remote) · secrecy ok · lint 0/0/0 · `tests/transform-rules.test.luau` 19
assertions.

**Notes for the playtester and auditors:**

1. **`validateAndKillHusk` still reverts immediately and does NOT start a feed.** The plan's Step 2.5
   names only `commitKill`, and I implemented it as written rather than extending it. The conservative
   reading is defensible on anti-farming grounds — a husk is a zero-risk kill on a disconnected
   player, so feeding on one would be a free heal engine — but the build plan's sentence "a husk is
   not feedable until it has been killed, at which point it is a corpse" can also be read as intending
   the opposite. **This is the one open design question in the chunk and it wants an explicit answer
   before V07.** Consequence today: `bodyKindOf`'s `HUSK` branch is defensive-only, since the only
   body ever handed to `beginFeed` is a fresh corpse.
2. **An Aswang mid-feed can still kill a nearby husk**, and `validateAndKillHusk`'s `revert(killer)`
   then breaks its own feed through the `NOT_TRANSFORMED` backstop within one tick (≤0.25s). It loses
   the heal, `WalkSpeed` is restored by `endFeed`, and both writes agree — so this self-heals rather
   than stranding state. Worth a look in Studio anyway.
3. Nothing in this phase sends anything to any client. `check:remotes` still reports 26/26.

## Phase 3: The lock, and every way a feed ends — 2026-08-28

**Steps completed:** 3.1, 3.2, 3.3

**Files changed:** `src/server/Services/MonsterService.luau` only.

- `MonsterState` gained `FeedBaseJumpPower: number?` and `FeedBaseJumpHeight: number?`; `stateFor`
  initialises both.
- `beginFeed` captures both jump properties then writes `WalkSpeed = 0`, `JumpPower = 0`,
  `JumpHeight = 0`, guarded on `humanoid ~= nil and monster.BaseWalkSpeed ~= nil`.
- `endFeed` restores `BaseWalkSpeed` and both captured jump values, clears the two capture fields,
  then calls `revert`.
- `ApplySaltHit` calls `endFeed(userId, "FEED_INTERRUPTED")` first, before its own `revert`.
- `onPhaseChanged`'s teardown loop, `watchCharacter`'s `Died` handler and `onPlayerRemoving` each end
  a live feed first. `onPlayerRemoving` passes a nil verdict (nobody left to send to).

**Deviations from plan:** none.

**Gate:** `npm run verify` exit 0. `npm run test:unit` 33 files ok · `tests/monster-health.test.luau`
243/243 · `tests/body-transitions.test.luau` 33 cells.

**Verified by reading, as the plan asked:** `revert` (line 727) guards on
`monster == nil or not monster.Transformed`, so `ApplySaltHit`'s second `revert` call after `endFeed`
is a clean early return. The redundancy is intentional and costs nothing.

**Notes for the playtester and auditors:**

- **Six exits, one restore.** Every path that ends a feed goes through `endFeed`, and `endFeed`
  restores the Humanoid unconditionally. That is the property to check — not the six paths
  individually. A seventh exit that does not go through `endFeed` is a bug by construction.
  `exploit-auditor` should be asked this directly.
- **THE JUMP LOCK IS UNVERIFIED ROBLOX BEHAVIOUR.** Nothing in this repo touched `JumpPower`,
  `JumpHeight`, `UseJumpPower` or `SetStateEnabled` before this chunk. Three things are assumed and
  need Studio to settle: (1) whether zeroing both jump properties actually prevents a jump under this
  game's Humanoid config, or whether `SetStateEnabled(Jumping, false)` is also needed; (2) whether an
  already-queued jump still fires after the write lands; (3) whether the server's `WalkSpeed = 0` is
  honoured promptly given client network ownership, or whether there is a visible slide.
- **The lock is the affordance; the leash is the authority.** A compromised client can ignore
  `WalkSpeed = 0` and drive its root part directly. `feedTick`'s server-side distance test against
  `FeedLeashStuds` is what actually holds the feed, and walking out of it costs the heal and the
  camouflage refresh — the same price a salt hit charges. Anchoring `HumanoidRootPart` was rejected,
  not deferred: no precedent in this codebase and it fights the client's character controller.

## Phase 4: The remote surface and the client — 2026-08-28

**Steps completed:** 4.1, 4.2, 4.3

**Files changed:**
- `src/shared/Remotes.luau` — `"FeedUpdate"` added to `EVENTS_DOWN`.
- `src/server/Services/MonsterService.luau` — `feedRemote` handle; `sendFeedUpdate` at the head of
  the feed block; three call sites (`endFeed` on a non-nil verdict, `completeFeed` → `FEED_OK`,
  `beginFeed` → `FEED_STARTED`).
- `src/client/Controllers/FeedController.luau` — new.
- `src/client/init.client.luau` — `"FeedController"` registered after `SearchController`, which is
  after `OnboardingController` (a real require dependency, for `ShowLine`).

**Deviations from plan:** none.

**Gate:** `npm run verify` exit 0. `check:remotes` **27 declared, 27 wired** (was 26/26).
`check:ratelimit` ok.

**Notes for the playtester and auditors:**

- **The no-up-remote claim is now mechanical, not asserted.** V06 adds zero `OnServerEvent` handlers,
  zero `AntiCheatService.Consume` sites and zero `Config.AntiCheat.Budgets` entries. `check:ratelimit`
  passing over a diff that grew the remote surface by exactly one DOWN remote is the statement of it.
  There is no entry point for a client to spam, because the feed is a consequence of a kill the server
  already validated.
- **One send site.** `sendFeedUpdate` is the only function in `MonsterService` that sends anything
  about a feed, and it uses `FireClient(player, payload)` — never `FireAllClients`. That is the line
  to check; there is exactly one.
- `HoldSeconds` is `FeedDuration` on `FEED_STARTED` and 0 on both endings, so a client cannot read a
  timing difference off which ending it received.
- **The visual half of the feed is not in this chunk at all** — no animation, no eating effect, no
  sound. §4.3 wants the feed visible and the transform already is; a feeding pose is a place-file and
  asset question. It is in the plan's Follow Ups rather than as a step nobody could verify.

## Phase 5: The gate, the scope sweep, and the evidence — 2026-08-28

**Steps completed:** 5.1, 5.2. **Step 5.3 NOT completed — see below.**

**Files changed:** `src/server/Services/MonsterService.luau` (header only — the five-seam block, the
V06 paragraphs in "WHAT THIS SERVICE DOES NOT SEND").

**Scope sweep:** `grep -rni "camouflage\|smoke\|disguise" src` returns only comments naming V07 as
owner plus V02's pre-declared `Enums.CamouflageForm`/`Types.CamouflageForm`. The V06 diff adds **no**
camouflage state — no field, no Config number, no remote. `check:scope` ok.

**Gate:** `npm run verify` exit 0 with the debug values reverted. `verify:plan` 19/20 — the one
failure is Step 5.3.

---

## Review round — 2026-08-28

Three reviewers ran concurrently. `auditor` 79/100, `exploit-auditor` 85/100, `playtester` blocked.

### FIXED — chain-kill window (High, found by `exploit-auditor`)

**The plan was wrong.** Its preamble decision 2 called the deferred revert "a BALANCE change, not a
bug". It was a bug. `revert()` stamps `LastRevertedAt`, and `LastRevertedAt` IS the kill cooldown —
so deferring the revert to the end of the feed left the killer `Announced` with a stale timestamp for
the whole 5s window, and `KillValidation` returned `OK` for a second kill. Reproduced independently
under Lune before fixing: `OK` at 1s into a feed where v1.3 gave `ON_COOLDOWN`.

That deletes §4.3's stated reason for the mechanic — "it cannot chain-kill, because it is pinned to
the body it just made". `pure/KillValidation`'s own header predicted it: the cooldown check is kept
for "the day something else grants the form". V06 was that day.

**Fix (user chose the shape):** `Feeding: boolean` added to `KillValidation.Request` with a new
`FEEDING` verdict, refused **after** `Transformed` and **before** the cooldown. Both entrances supply
it — `validateAndKill` and `validateAndKillHusk`. Put in the pure module rather than as a service
guard so the grid covers it: `tests/kill-validation.test.luau` 51 → **55 cells**, including the
shipped bug's exact inputs as a regression row.

### FIXED — jump restore bypass (Low, found by `exploit-auditor`)

`beginFeed`'s refusal branch and `validateAndKillHusk` call `revert` with a feed possibly live, and
`revert` restored `WalkSpeed` but knew nothing about `FeedBaseJumpPower`/`FeedBaseJumpHeight` — so a
character could read `JumpPower = 0` for up to one tick after a public revert.

**Fix (user chose the shape):** the jump restore moved into `revert()` beside the `BaseWalkSpeed`
restore, so no caller can get one without the other. `endFeed` keeps its own restore for the paths
where `revert` early-returns.

### NOT DONE — Step 5.3, behavioural verification

**No `feed-complete.png` exists and none was fabricated.** Two playtester sessions, two blockers:

1. A solo player is deterministically a survivor (`RoleService` clamps the draw to `#candidates - 1`).
   Fixed by setting `Config.Debug.ForceAswangWhenSolo` — my omission, cost 5 wasted rounds.
2. **With one client there is nobody to kill.** `ForceAswangWhenSolo` changes *which* candidate is the
   Aswang; it does not add a second player. `RequestKill` has no valid target, so `beginFeed` is
   unreachable and all seven behavioural questions are unanswerable at any Config value.

**This needs a human-driven multi-client Team Test** (2 clients minimum, 3 for the chain-kill
regression) — a UI action no agent can drive. Artifacts: `solo-role-blocker-console.log`,
`forced-aswang-no-kill-target.log`.

**Still unverified by anyone**, and all three were flagged as unverified Roblox behaviour before a
line was written:
- Whether zeroing `JumpPower` **and** `JumpHeight` actually prevents a jump. `SetStateEnabled(Jumping,
  false)` is confirmed absent by grep. **This is the most likely thing to be wrong.**
- Whether an already-queued jump lands after the write.
- Whether a server `WalkSpeed = 0` is honoured promptly under client network ownership, or slides.
- Whether the feed heal is observable behaviourally.

### OPEN — a shape problem, deliberately not fixed here

`revert()` welds three unrelated jobs together: stamping the cooldown clock, restoring Humanoid
properties, and broadcasting the un-transform — and it early-returns on `not Transformed`, so callers
needing the restore cannot rely on it. **Both findings above and the mid-feed husk-kill note are the
same cause seen from three angles.** `guard-fix-rounds.mjs` escalated on this file at 4 rounds, which
was the correct call.

Proposed split, for a `refactor(monster):` chunk of its own **before V07** — V07 adds camouflage, a
fourth thing that will want to restore character state on the way out:

    restoreHumanoid(monster, player)  -- TOTAL, idempotent, no early return. The only restore path.
    stampCooldown(monster)            -- LastRevertedAt, at the KILL. Not a side effect of a visual.
    revert(player)                    -- Orchestrates; early-returns on the BROADCAST only.

Not done in V06: it would be a fifth edit to this file on a working tree, which is the loop the guard
exists to stop.
