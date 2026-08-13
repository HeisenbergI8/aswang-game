# Implementation Log — C13–C16 Salt and Ghosts

## Phase 1: The two decisions on record — Config, Types, and Amendment A3

**Status:** complete. `npm run verify` green.

### Step 1.1 — `Config.luau` knobs
`Salt` gained `PickupRangeStuds = 6`, `ThrowConeDegrees = 20`, `PouchPoolSize = 6`, `PouchRgb`,
`RevealGlowFillRgb`, `RevealGlowOutlineRgb`. `Ghost` gained `RosterInterval = 1`,
`SpookRangeStuds = 30`, `SpookDuration = 2`. All plain numbers and RGB triples — no `Color3`.
`AntiCheat.Budgets` untouched: `RequestThrowSalt` and `RequestGhostSpook` already had budgets.

**Verify:** `lune run tests/config.test.luau` — PASS.

### Step 1.2 — `tests/config.test.luau` relationships
Seven new invariants: pool ≥ spawn count, salt scarcer than the roster, the cone is a cone, pickup
tighter than presence, roster not faster than the snapshot, at least one spook, spook range wider than
both kill and presence range.

**Verify:** `npm run test:unit` — PASS, 20 files.

**Deviation from plan — a defect found while verifying this step.** The suite's final line was
`print("  PASS  config: 34 balance invariants")` with **34 as a string literal**. It printed 34 both
before and after seven checks were added, so the PASS line could not distinguish a suite with seven new
invariants from one that had silently dropped seven. Added a `checked` counter incremented inside
`check` and made the figure a measurement. It now reads 41, which is `grep -c "^check("`.

Before fixing it, the new checks were proven to discriminate rather than assumed to: setting
`ThrowConeDegrees = 95` errored the suite at the failure exit; `Config.luau` was restored from a
scratchpad copy and re-confirmed at 20.

### Step 1.3 — `Types.luau`
`AlivePlayerCount` removed from `ClientRoundSnapshot`, with a block comment in its place naming the
attack it enabled, why a delay was rejected, what a client learns about a death now, and the four names
it must not return under. Added `SaltVerdict`, `SaltEffectPayload`, `GhostRosterPayload`, `SpookVerdict`.

Also corrected `PlayerKilledPayload`'s defence of its `Position` field, which read "the corpse model
stands at that position and replicates to every client on its own". That is false under §5's
`StreamingEnabled` — a distant corpse does not replicate and the remote did.

**Verify:** `npm run analyze` — one expected failure at `init.client.luau:80`, the consumer Step 1.4
removes. Green after 1.4.

### Step 1.4 — `RoundService` and `init.client.luau`
Field dropped from `buildSnapshot`; debug line in `init.client.luau` loses the count. `aliveCount()`
kept — still read by the `VerboseLogging` print at `RoundService.luau:794`.

Two comments were asserting things that had stopped being true and were corrected rather than left:
`livingSurvivorCount`'s header described `aliveCount()` as "what the client snapshot carries", and
`MarkKilled`'s immediate-push comment justified itself partly by `AlivePlayerCount`. The surviving
justification — the victim's own `YourState` — is stated on its own, with a note that the push remains a
weak timing signal because its *contents* no longer differ for a bystander.

**Verify:** `npm run verify:fast` — analyze ok, remotes ok (21 declared, 13 wired), secrecy ok.

### Step 1.5 — `PlayerKilled` narrowed
`killedRemote:FireAllClients(payload)` → `killedRemote:FireClient(victim, payload)` in
`MonsterService.commitKill`. Payload shape unchanged. The file header's description of the remote was
updated too — it documented the payload but not the audience.

**Verify:** `npm run check:secrecy` — ok. Note this check proves the *payload*, not the *direction*; a
text tripwire cannot tell `FireClient` from `FireAllClients` as policy. The audience claim is the
playtester's to prove (three clients, one dies, two consoles silent) and is unproven as of this entry.

### Step 1.6 — Amendment A3
Added to §4.7. No `**Verify:**` line by design — the deliverable is prose.

**Deviation from plan.** The plan's diff made A3 `spec v1.1 → v1.2` and set the header to `v1.2`. That
collides: **A2 already exists** at `MVP-SPEC.md:145` declaring `v1.1 → v1.2`, but the header was never
updated for it and still read `v1.1 — v1.0 plus Amendment A1`. Following the plan verbatim would have
produced two amendments both claiming the same version bump. A3 is therefore `v1.2 → v1.3`, and the
header now reads `v1.3 — v1.0 plus Amendments A1 (§4.8), A2 (§4.4) and A3 (§4.7)`, which also repairs
the pre-existing omission of A2.

Grepped `docs/MVP-SPEC.md` for `AlivePlayerCount` / `alive count`: no other references, so no stale rows
elsewhere in the spec. §11's `| Dead players quit |` row is unaffected, as the plan predicted.

### Phase 1 — issues identified

- **`check:secrecy` cannot prove the direction change in Step 1.5.** Playtester evidence required.
- **The out-of-cadence snapshot push in `MarkKilled` survives as a weak timing signal.** Contents no
  longer differ per bystander, so it is far weaker than the removed field, but it is not zero.
- **The `config.test.luau` count literal was a live blind spot** and is the kind of thing that hides a
  dropped invariant. Fixed here; worth checking whether other suites hardcode their totals.
- **Scope:** nothing from §3's OUT list. A3 explicitly declines to add a HUD element.

### Decision recorded outside the plan

The user overrode the plan's DECISION 2 after it was written and bound. They want the **disconnect
husk**, not GHOST-on-rejoin, and defined it as *"stay as is"*: a disconnect during ACTIVE leaves the
player's state untouched and their character standing in the world as a killable AFK body; on rejoin
they resume whatever state they now hold — killed while away → GHOST, untouched → ALIVE.

This does **not** affect Phases 1–4 and the bound plan was not edited (editing it halts the run). It
rewrites Phase 5, and the Phase 5–8 plan must be authored against this decision rather than against the
bound plan's DECISION 2.

Note that this framing likely avoids the fifth-`PlayerState` cost the plan priced, because the state
never changes and `PlayerStates` is keyed by UserId. The real cost moves to **a husk being a character
with no `Player` object** — `MonsterService.validateAndKill` opens with `Players:GetPlayerByUserId`,
which returns nil for a departed player. Server-hopping still defeats the husk entirely and cannot be
fixed here.

---

## Interlude: `check:testcount` (user-requested guard, not a plan step)

Prompted by the Step 1.2 finding. `.claude/scripts/check-testcount.mjs` flags a digit in a `PASS`
summary that sits outside a `{...}` interpolation, with `-- count-ok: <reason>` as the waiver.

**Self-test: 20/20, both directions.** Registered in `harness-selftest.mjs` `SUITES` (27 suites now)
and wired into `npm run verify` between `check:debug` and `test:unit`.

**14 suites were affected.** Twelve now compute their total from a `checked` counter; two keep a
literal under a waiver, because `512` and `64` state the size of the input domain those suites
enumerate rather than a tally of work.

**Three of the literals were already wrong** — the drift this guard exists to catch had happened and
nothing had noticed. The unambiguous one is `task-resolve`, which claimed `33 assertions` and counts
**34**; `task-weight` and `task-selection` also disagreed with their new counts, though their wording
changed too so they are not strict like-for-like comparisons.

**The guard's own first version was broken, and the bug is instructive.** It matched
`/print\s*\(([^\n]*PASS[^\n]*)\)/` — call and argument on one line. StyLua wraps long calls across
lines, and `npm run fmt` runs *inside* `npm run verify`, so the formatter would have blinded the check
on exactly the files it had just reformatted. Measured at **0 findings** against a wrapped print
carrying a hardcoded `34`. Rewritten to key on the string literal instead of the call.

That fix immediately caught `tests/transform-rules.test.luau:176`, which the first version never saw
because its print was *already* wrapped — so the blind spot was live in the repo before this guard
existed, not just theoretical. Three wrapped-form cases are now in the self-test.

---

## Phase 2: C13 — salt spawn and pickup

**Status:** Steps 2.2, 2.3, 2.4 complete and green. Steps 2.1 and 2.5 outstanding.

Built out of plan order: 2.3 before 2.2, because `ItemService` requires `SaltCarry` and `analyze`
cannot pass on a require to a file that does not exist yet. Each step still carries its own check.

### Step 2.3 — `src/shared/pure/SaltCarry.luau`
`(phase, playerState, carried, limit) -> verdict`, allowlist of ALIVE, fails closed on a limit that is
not positive-and-finite.

**Deviation from plan — a hole in the plan's own snippet.** The prescribed body guarded a degenerate
LIMIT but not a degenerate `Carried`. `NaN >= 1` is false, so a NaN carried count falls straight
through the `AT_LIMIT` comparison and returns **OK** — a pouch handed out on corrupt state. The two
guards are not symmetric and the plan's comment implied they were. Added a second guard for
`Carried`, ordered last so a legitimate refusal still reports as itself, and asserted in the test.

**Verify:** `npm run lint` — 0 errors, 0 warnings.

### Step 2.2 — `ItemService` discovery
`CollectionService:GetTagged("SaltSpawn")`, sorted, name-unique, graded by the existing
`server/pure/TaskPool.evaluate` rather than a copied `SaltPool`. Pool faults warn unconditionally;
only the OK line is gated behind `VerboseLogging`. Exposed as `ItemService.EvaluatePool()` so Step 2.5
gets the verdict without `pointsByName` becoming public.

**Deviation from plan.** The plan's diff adds requires for `Players`, `AntiCheatService`,
`RoundService`, `Enums`, `Remotes`, `SaltCarry` and `Types` at this step. None is used until Step 2.5
or Phase 3, and selene fails an unused local, so they arrive with their first caller instead.

**Verify:** `npm run analyze` — ok. `npm run lint` — clean.

### Step 2.4 — `tests/salt-carry.test.luau`
38 assertions: the full 20-cell `RoundPhase × PlayerState` grid, the carry boundary, degenerate limits
(`0`, `-1`, `inf`, `NaN`), degenerate carried counts, precedence, and purity.

Two assertions are properties rather than cells, deliberately. *"Exactly one PlayerState may pick up
salt"* would survive someone rewriting the allowlist as a denylist and then editing the grid's
expectations to match — the count would go to two and only this line would notice.

**Verify:** `lune run tests/salt-carry.test.luau` — PASS, 38 assertions. Full `npm run verify` green,
21 test files.

### Outstanding

- **Step 2.1** — the disposable `SaltSpawn` rig. Needs Studio in **Edit** mode; Studio is currently in
  Play, and the open place is `Template_95206881_AutoRecovery_0.rbxl`, an autorecovery file. Not
  touched pending the user's confirmation of which place is real. This step gates the RUNTIME proofs
  (pouches spawning, the empty-pool warning, the duplicate-name warning), not the code.
- **Step 2.5** — spawn at STARTING, pickup poll during ACTIVE, teardown to INTERMISSION/IDLE, drop a
  departing player's carry. Code only; `npm run check:config`. No Studio dependency.

### Step 2.5 — spawn, pickup tick, teardown
Pouches spawn at STARTING (Fisher-Yates over a copy of the pool, `Random.new()` unseeded), a 0.25s
server tick resolves pickups from each player's own `HumanoidRootPart`, `clearPouches` runs on the way
into INTERMISSION and IDLE only, and `PlayerRemoving` drops a departing player's carry.

`pouches` and `carried` were declared here rather than at Step 2.2 — the plan put them in 2.2's diff,
where they have no callers and selene fails an unused local. Same reason the requires moved.

A private `rgb()` was copied from `MonsterService.luau:133` with its waiver, per the plan's own Phase 2
issue list, rather than exporting MonsterService's and making a colour helper a cross-service
dependency.

**Verify:** `npm run check:config` — ok. Full `npm run verify` green.

**Checked beyond the plan:** `ItemService` is already in `init.server.luau`'s service list (line 32),
so `Start()` actually runs. A service that is written but never bootstrapped passes every static check
in this repo and does nothing at runtime, and the plan does not verify this anywhere.

**Open question raised for Phase 5, not resolved here.** `PlayerRemoving` clears the carry. Under the
user's disconnect-husk rule the player's state survives a reconnect, and it is genuinely unclear
whether their pouch should too — the husk is meant to be the same body standing in the same place,
which argues the salt is still in its hand. Dropping it is the conservative choice: a rejoining player
can never GAIN salt, and it is correct if the husk never ships. Flagged in a comment at the call site
so Phase 5 revisits it rather than inheriting it silently.

### Phase 2 — status

Steps 2.2, 2.3, 2.4 and 2.5 complete and green. **Step 2.1 (the Studio rig) remains**, and with it the
three runtime proofs: pouches visibly spawning, the empty-pool warning reaching a console, and the
duplicate-name warning. None of the code above has been exercised against a running DataModel.

---

## Phase 3: C14 — the throw

**Status:** complete. `pure/SaltThrow` + 56-assertion test, the two `MonsterService` seams, the handler.

- **3.1 `pure/SaltThrow`** — `(request) -> verdict`. One `MISS` for four worlds (empty cone, survivor,
  untransformed Aswang, out of range). Added a guard the plan's snippet lacked: `Carried < 1` admits a
  NaN carry because `NaN < 1` is false, so the finite range is checked explicitly.
- **3.2 test** — 56 assertions. The load-bearing one is a *property*: all four failing worlds are
  collected and their distinct verdict count asserted to be exactly 1. A future edit splitting `MISS`
  into `MISS_NOT_ASWANG` / `MISS_OUT_OF_RANGE` fails here rather than shipping a role oracle.
  Cone boundary cases computed from `math.tan(math.rad(19|21)) * 10` so they genuinely straddle 20°.
- **3.3 `MonsterService.IsTransformed` / `ForceRevert`** — seams, not copies, so the generation bump,
  the `Announced` gate and the `LastRevertedAt` stamp are reused rather than reimplemented.
- **3.4 the handler** — `Consume` first, `direction` typed `unknown` and `typeof`-checked, pouch spent
  on hit AND miss, nothing returned to the caller on any path.

**Deviation:** the plan's `resolveThrow` miss branch computes `origin + direction.Unit * ThrowRange`.
`.Unit` on a zero or non-finite vector yields NaN rather than throwing, so the burst would render at a
NaN point. Guarded on magnitude first.

## Phase 4: C14 — stun, reveal, effect, client

- **4.1 stun** — captured WalkSpeed/JumpPower restored, never defaults (C04's Critical replayed).
  Generation counter so a second hit's timer cannot be ended early by the first. Capture happens only
  on the first hit, so a mid-stun second hit cannot capture 0/0 as "before".
- **4.2 reveal** — one `Highlight` named `SaltReveal`, `DepthMode = Occluded` (`AlwaysOnTop` would make
  the reveal a wallhack). All four exits closed; `clearAllEffects` runs on every phase that is not
  ACTIVE, unlike `clearPouches`.
- **4.3 `SaltEffect`** — typed local, `FireAllClients`, trajectory only, no UserId of any kind.
- **4.4 client** — `InputController` sends `camera.CFrame.LookVector` and nothing else;
  `CameraFXController` renders and concludes nothing.

**Two additions beyond the plan, both from its own issue list:**
- `PlayerRemoving` now clears `stunned` and `reveals`, not just `carried`.
- `CharacterRemoving` clears the reveal, closing the **glowing corpse**: `makeCorpse` detaches the
  character and keeps it in the world, so a revealed player who then dies leaves a glowing body that
  reads as "this corpse was the monster".

**The throw bind is `Q` with `createTouchButton = true`** — the first bind in `InputController` to ask
for one. The other four pass `false` and defer mobile to C27. Salt is where that stops being
defensible: §5 puts ~60% of players on a phone and §4.6 is the only counterplay in the game. Like `R`,
`Q` is not proven free of a CoreScript claim; that needs a playtest.

## Phase 5: C15 — the disconnect husk (USER'S DESIGN, NOT THE PLAN'S)

The plan recommended GHOST-on-rejoin and deferred the husk to a post-GATE-1 chunk. The user chose the
husk and defined it as "stay as is". Built to that.

- **`pure/RejoinResolve`** + 61-assertion test. Rule: not underway → LOBBY; not dealt in → SPECTATOR;
  dealt in with no stored state → SPECTATOR (fail closed); otherwise **whatever they were, they still
  are**.
- **`dealtIn`** — its own table, populated in `enterStarting` AFTER `setAllPlayerStates` (which opens
  with `table.clear`), cleared in `enterIntermission`, `enterIdle` and `Init`.
- **`onPlayerRemoving`** no longer deletes the `PlayerStates` entry for a dealt-in ALIVE player during
  a live round. It detaches their character and re-parents it to a `Husks` folder.
- **`onPlayerAdded`** resolves through `RejoinResolve` and consumes the husk.
- **The husk is killable**, which is the half that makes it a deterrent instead of scenery.
  `MonsterService.validateAndKillHusk` runs the SAME `KillValidation.evaluate` and the SAME line-of-
  sight raycast; only `TargetIsAswang = false` and `TargetState = ALIVE` are supplied as guarantees
  rather than lookups, because `onPlayerRemoving` aborts the round if the Aswang leaves.
- `makeCorpse` refactored to take a UserId instead of a Player; the detach moved to `commitKill`.
- A husk kill increments `AswangKills` and runs the same attrition check — a husk was counted in
  `DealtInSurvivors`, so not counting its death would make the round unwinnable by the number of
  quitters.

**The test grid had a hole I caught by counting.** `{ nil, "LOBBY", ... }` — a leading `nil` in a Luau
array literal is not iterated, so the "server has no stored state" column silently never ran: 40 cells
reported against 50 claimed, and the missing column was the fail-closed one. Wrapped in `{ Value = ... }`.

**Server-hopping still defeats the husk and cannot be fixed here.** Documented in the module header
rather than implied away.

## Outstanding

Phases 6 (ghost body/flight/roster), 7 (ghost chat) and 8 (contribution/spook) not started.
Step 2.1's Studio rig and every runtime proof still outstanding.

---

## Audit fixes (two Criticals, before Phases 6–8)

**Critical 1 — salt branded the Aswang permanently and did not stun.** `applyHit` ran
`applyStun` before `ForceRevert`. `applyStun` captured the TRANSFORMED WalkSpeed (20), wrote 0;
`revert()` overwrote that 0 with `BaseWalkSpeed` (16) in the same frame, so the stun never happened;
4s later `clearStun` wrote the captured 20 onto an untransformed player, permanently — `applyBodyRule`
only reloads a character when there isn't one, so it survived across rounds. `Humanoid.WalkSpeed` is
replicated, so exactly one character read 20 and every other read 16: a map-wide role brand with no
remote to intercept. Same class as C04's revert bug, in the same service pair, `check:secrecy` green
over it. **Fixed by reverting first, then stunning.**

**Critical 2 — Amendment A3 deleted the payload and left the trigger.** The out-of-cadence
`broadcastSnapshot()` in `MarkKilled` was logged as a "weak timing signal"; it is not weak. Every
OTHER off-cadence trigger is self-identifying (a phase change ships `PhaseChanged`, a gate flip changes
`GateOpen`, a task completion changes `TasksCompleted`), so "early snapshot with none of those changed"
means a death, to the millisecond, delivered to all eight clients. **Fixed:** `FireClient(victim, …)`
in `MarkKilled`, and no push at all in `MarkHuskKilled` (its owner is disconnected).

## Phase 6: C15 — the ghost body

- **6.2 / 6.3** — `mayHaveBody` admits GHOST in BOTH `pure/BodyTransitions` and `pure/PlayerBody`.
  The 20-cell grid moved exactly where the plan predicted: JOINED/PHASE_CHANGE/DIED → GRANT,
  LOAD_FAILED → DEFER, and **KILLED stays REVOKE**, which is what stops two bodies existing.
  `mayBeKilled` did NOT move — the two allowlists were separated at C05 for this moment.
  The property assertions were inverted rather than deleted: the old "a ghost is never granted a body"
  became "a ghost IS granted a body except on the kill that made them one".
- **6.4 / 6.5** — `GhostService` embodiment, invisibility, flight, and `GhostRoster` (new down-remote,
  fired per-ghost with the state re-read at the fire site).

**Step 6.1's Studio probe was NOT run.** Four assumptions are labelled `ASSUMPTION` in the file with
what changes if each is wrong: flight mechanism, `LocalTransparencyModifier` on unowned parts, the
DisplayName billboard, and whether `CanQuery = false` keeps a ghost out of the kill raycast. The last
is a gameplay bug if wrong — a ghost could body-block a kill.

## Phase 7: C15 — ghost chat

`pure/GhostChat` + 28-assertion grid, and three independent enforcement layers in `GhostService`:
removal from `RBXGeneral` (the half that leaks by DEFAULT), a `Ghosts` channel, and a
`ShouldDeliverCallback` that reads LIVE `PlayerState` rather than channel membership — because
membership is a cache of state and the whole bug class is the two disagreeing.

Rule: delivered when the sender is living-side OR the recipient is not. **SPECTATOR is treated as
dead-side** — a decision beyond §4.7's text, because a mid-round arrival can watch a transform and say
a name. Membership syncs on death as well as on phase change; without that a player who died mid-round
would stay in the general channel for the rest of ACTIVE.

**Step 7.1's spike was NOT run.** `TextChatService` behaviour is assumed from documentation. The
callback fails closed on any unresolvable state.

## Phase 8: C16 — contribution and the spook

- **8.1** — both `TaskService` gates became ALIVE-and-GHOST allowlists. `TaskWeight` was untouched: the
  25% has been wired since C08 and merely unreachable. selene caught a `timingState` shadow of a
  module-level table; renamed to `stopperState`.
- **8.3 / 8.4** — `pure/SpookBudget` + 37 assertions, and the `RequestGhostSpook` handler.
  The spook's ORIGIN is uniformly random within `SpookRangeStuds` and deliberately NOT the nearest
  light — that would make it a locator for a dead player, and a dead player standing beside the Aswang
  is the leak §4.7's last bullet is about. No budget is spent when the ghost has no body.

## Still outstanding

- **Step 2.1** — the Studio rig. No pouch has ever spawned.
- **Steps 6.1, 7.1** — the two Studio probes. Everything coded against them is labelled.
- **Four open audit findings**: `SaltEffect` broadcasts the monster's exact position and
  `IsTransformed` reads `Transformed` rather than `Announced` (High); `RequestThrowSalt` fails open
  when no other player has a body (Medium); the Aswang DOES briefly get a husk (Medium); quitting is
  still a positional escape because the husk is destroyed and the owner respawns at a spawn point
  (Medium, design call).
- **Step 5.5** — disconnect-as-death for scoring, dropped without a note.
- `Config.Ghost.SpookDuration` has no invariant.

---

## Audit round 2 — fixes applied

Two audits (auditor 72/100, exploit-auditor 79/100) over Phases 6–8. Everything below was fixed; the
one thing NOT fixed is at the end, because it is a design decision the user has to make.

### Regressions this milestone introduced, now closed

**A ghost body was never destroyed and survived into the next round.** `mayHaveBody("GHOST")` becoming
true removed the REVOKE that had been cleaning ghost bodies up, and `applyBodyRule`'s GRANT branch is
gated on `player.Character == nil`, so it no-ops on an attached body. Shipped behaviour: die in round
N, and in round N+1 you are ALIVE, invisible and non-collidable — **and an invisible Aswang if drawn**,
because `applyFullLook` writes Colour and Material and never Transparency. Fixed in
`setAllPlayerStates`, which is the single place every player's state is rewritten at once: a player
leaving GHOST has their body detached and destroyed BEFORE `applyBodyRule` runs, so GRANT builds a
fresh visible one.

**`"KILLED"` was passed by nobody**, so the `GHOST/KILLED → REVOKE` cell was tested and unreachable.
`MarkKilled` now passes it explicitly — and then calls `applyBodyRule` again, because `KILLED` only
REVOKEs and a ghost with no body breaks §4.7's flight and C16's contribution. Before this, a reset or
fall death left a player a GHOST wearing a permanently visible corpse.

**A non-collidable `HumanoidRootPart` had no floor.** Every part was `CanCollide = false`, so a ghost
fell past `FallenPartsDestroyHeight`, died, respawned and fell again — an unbounded
`LoadCharacterAsync` loop. The root part now keeps its collision; the body is transparent so it looks
identical, and living players can bump into it, which is the honest cost until Step 6.1's probe runs.

### Ghost chat — the missing layer and three bypasses

**Layer 1 now exists.** `removeFromLivingChannels` destroys a ghost's `TextSource` in every non-ghost
channel. Its absence was not a bug that had to happen — Roblox auto-adds everyone to `RBXGeneral`, so
doing nothing leaked by default.

**Whispers.** The guard was attached to `RBXGeneral` only; default `TextChatService` creates
`RBXWhisper:<id>` channels on demand, so `/w <survivor> <the Aswang>` bypassed it entirely — a slash
command, not an exploit. Now attached to every channel, plus `ChildAdded` for ones created later, which
also closes the attachment race.

**`LegacyChatService` now fails LOUD.** It was a `warn` and a `return`, leaving every ghost talking to
every living player for the life of the server. `ChatVersion` lives in the place file, which is not in
Git, so no check here can see it. Now warns AND errors.

**The false comment is corrected.** The header claimed three enforcement layers when only two existed.
That was worse than the missing code: it would have stopped a reviewer looking.

### Other fixes

- **Husks excluded from the kill raycast** via a new `RoundService.GetHusksFolder`, and made anchored
  and non-collidable. Quitting in a doorway was permanent cover for the rest of the round.
- **`GhostChat`'s rule changed** from a single living/dead wall to `living-side OR same state`. The
  wall delivered GHOST → SPECTATOR, which the plan had refused by name: a spectator is a mid-round
  arrival with no stake, so a ghost-channel feed is an alt account listening from inside it.
- **Ghost timing stops are weighted.** `state.Hits + 1` became `state.Hits + weightFor(player)`; the
  presence path was correctly weighted and only timing routed around §4.7's 25%.
- **Late-loading accessories are hidden.** `CharacterAdded` is not `CharacterAppearanceLoaded`;
  `DescendantAdded` now covers hats and layered clothing that arrived after the one-shot pass.
- **Two new config invariants**: `SpookDuration` bounded above by `RevealDuration`, and
  `KillCooldown > StunDuration` — the latter is now load-bearing for a SECRECY invariant, since it is
  the only thing preventing a transform-while-stunned from re-creating the WalkSpeed brand.
- **Step 8.2's assertions finally added** to `tests/task-weight.test.luau`: a ghost contributes more
  than nothing, less than the living, and three ghosts fall short of one survivor.

`npm run verify` green: 25 test files, config at 43 invariants, ghost-chat 29, task-weight 21.

### NOT fixed — needs a decision

**Ghost bodies replicate to living clients, which is a death oracle.** Any client runs
`CollectionService:GetTagged("GhostBody")` and gets the exact dead set by name, live, with
`GetInstanceAddedSignal` giving the death timestamp to the frame. A GHOST is provably never the
Aswang, so every death eliminates a candidate. This is strictly stronger than the `AlivePlayerCount`
field Amendment A3 removed, and it contradicts A3 directly. Removing the tag does not fix it —
`Transparency == 1 and not CanCollide` fingerprints the bodies in one loop.

Three options, all requiring either a Studio probe or a spec change:
1. No server character for ghosts; client renders locally, server keeps a reported position for the
   25% contribution. Costs server authority over ghost position. **Recommended** — the only one that
   needs no unverified Roblox behaviour and keeps A3 intact.
2. `ModelStreamingMode = PersistentPerPlayer` + `AddPersistentPlayer`. Needs `StreamingEnabled` (C17)
   and a probe.
3. Amend A3 to accept that death becomes public once ghosts exist.

**Also outstanding, pre-existing and larger than anything above:** `MonsterTransformed` fires
`FireAllClients` with the Aswang's `Character` — every client, any distance, through walls.
`payload.Character.Name` ends the round. That is C04, not this milestone, but it makes the ghost-chat
wall a lock beside an open door.

---

## Audit round 3 — fixes to the fixes

Re-audit of the nine round-2 fixes scored 80/100. Seven held. **Three of my own fixes opened new
problems**, which is the shape of this repo's `green-after-each-patch-hides-a-loop` lesson.

### Fixes that were themselves wrong

**`error()` in `configureChannels` was a REGRESSION and is reverted.** `init.server.luau` wraps every
`Start` in a pcall that only warns, so the error reached an operator no more loudly than the warn — and
because `configureChannels()` is the FIRST line of `Start()`, it aborted everything after it. Under
`ChatVersion = LegacyChatService` the result was: ghost chat still unenforced, PLUS `PhaseChanged`
never connected, PLUS the `CharacterAdded` watchers never connected, so `makeGhost` never ran and every
dead player walked the Barrio fully visible, normally named, at default speed and unkillable. Strictly
worse than the warn it replaced. Loudness cannot be bought upstream of your own service.

**Fractional `Hits` put a death bit on the wire.** Weighting timing stops made `state.Hits` fractional,
and `Hits` is a field on `TimingBarPayload`. Any non-integral value told a living player at that task
point that a GHOST had contributed — someone is dead, and within `PresenceRangeStuds` of me. Now
`math.ceil`ed for the payload; the bar only ever rendered lit segments, so the ceiling is the honest
field and the accumulator stays server-side.

**Skipping the ghost channel exempted the one channel where membership is the only control.** Layer 3's
own argument is that membership is a cache of state; the skip removed the fail-safe from the exactly
one place that had nothing else. Two routes in, neither needing an exploit: a `TextSource` not named
the UserId string makes both removals silently no-op, and `AddUserAsync` yields so an in-flight call
can enrol a now-LOBBY player. Guard now attached to every channel, and the post-yield state is
re-checked.

### Other fixes this round

- **A ghost could hold any TIMING task at zero indefinitely.** `state.Hits` is per TASK and shared, and
  the miss branch zeroed it for everyone. A ghost pressing stop ~once a second — inside the sustained
  budget, no exploit — misses at least once per 1.8s sweep and the bar can never complete. Invisible,
  unkillable, untargetable, denying the escape win for the whole round. A ghost's miss is now a no-op:
  zero is the penalty for failing the window as a participant who can be punished, and a ghost cannot be.
- **The `GhostBody` tag is deleted.** Nothing ever read it (Step 6.5's client renderer was never
  built), and CollectionService tags replicate — `GetTagged("GhostBody")` returned the exact dead set
  by name and `GetInstanceAddedSignal` gave each death to the frame. `check:secrecy` was green because
  it matches tag NAMES against role tokens; a tag does not have to say "aswang" to name them by
  elimination.
- **`MarkKilled`'s GRANT now stamps `lastRespawnAt`**, so the ghost body's load is throttled like every
  other.
- **A stale comment corrected** — `hasLineOfSight` claimed husks are "not anchored or made
  non-collidable", which the previous round made untrue in the same change.

`npm run verify` green: 25 test files, all eight checks.

### STILL OPEN — and this is now a redesign, not a patch

**Finding 1 (Critical) is unchanged: ghost bodies are fingerprintable by any client.** Deleting the tag
removed the easy enumeration; `Transparency == 1` on a replicated character still identifies the dead
set to anyone who iterates characters, and `WalkSpeed = 24` marks them a second time.

The exploit auditor independently reached the same recommendation already in this log — **option (a),
no server character for ghosts** — and added the argument that makes it decisive: the body buys exactly
two things, `spookOrigin` and `TaskService`'s presence check, and BOTH are positions. A server-side
`{ [userId]: Vector3 }` fed by a ghost-only position remote serves both consumers and deletes, in one
change: the fingerprint, the WalkSpeed hint, ASSUMPTIONS 1–4, the `hideDescendant` surface, and the
collidable-root problem below.

It also rated option (b) the weakest of the three — `PersistentPerPlayer` is a DISTANCE-based guarantee
being asked to carry a SECRECY guarantee, which is the same "statistical claim of safety" A3 explicitly
refused when it rejected a jittered delay. And option (c) it called "not a fix, a decision to lose".

**Also open, and dissolved by the same redesign:** the collidable ghost root stops the fall/respawn loop
but is an invisible wall — a ghost can body-block the Aswang or a fleeing survivor, and any living
player who walks into thin air has located a ghost. The auditor's fix if the redesign is not taken is a
`PhysicsService` collision group, not a name comparison (`humanoid.RootPart` is the correct test
anyway; the string defeats a custom rig silently).

**THREE FIX ROUNDS ON THIS FILE. Per `.claude/lessons/green-after-each-patch-hides-a-loop.md`, that is
the point to change the shape rather than patch again.** No further patching of Phase 6 until the
design decision is made.

---

## Phase 6 REBUILT — ghosts have no server character

Proceeded with option (a), the recommendation both I and the exploit auditor reached independently.
This is a redesign rather than a fourth patch round, per
`.claude/lessons/green-after-each-patch-hides-a-loop.md`.

### What was deleted

`mayHaveBody("GHOST")` is false again in BOTH pure modules, so `applyBodyRule` REVOKEs a ghost's body
the moment `MarkKilled` writes GHOST. With no server body, roughly 130 lines of `GhostService` went
with it: `applyFlight`, `hideDescendant`, `applyInvisibility`, `makeGhost`, the `ghosted` table, the
`GhostBody` tag, and **ASSUMPTIONS 1 through 4** — four unverified guesses about Roblox behaviour that
the whole feature rested on.

Deleted along with them, without needing a fix each: the invisible-collidable-root problem, the
floating-name-tag risk, the fall-into-the-void respawn loop, and the question of whether
`CanQuery = false` keeps a ghost out of the kill raycast. **None of those can happen to an object that
does not exist on the server.** That is the argument for the redesign in one sentence — three patch
rounds each closed one leak; this closed the class.

### What replaces it

- **`GhostController`** (new, client). Builds a LOCAL body — client-created Instances do not
  replicate, so a living player's machine has no ghost object on it at all — flies it from camera-
  relative input, drives the camera, and reports its position.
- **`ReportGhostPosition`** (new up-remote, budget `{10, 5}`). Four gates in order: `Consume` first,
  `typeof == "Vector3"`, caller must already be a GHOST server-side, and continuity against
  `FlySpeed × elapsed` so a lie has to be walked rather than teleported. Non-finite refused explicitly,
  because every comparison against NaN is false and `distance > limit` would ADMIT a NaN.
- **`GhostService.positions`** — server-only, never sent anywhere, with staleness expiry. A ghost who
  stops reporting stops contributing.
- **`TaskService.positionOf`** is the single choke point and now has two sources: a living player's
  replicated root part, or — for a GHOST only — the reported position. The comment there is explicit
  that this is where the trust boundary moves, and that routing a LIVING player through it would make
  kills and task completion client-claimed.
- The spook reads the reported position, and refuses (without spending the budget) when it is stale.

### The honest cost, recorded rather than glossed

The server is no longer authoritative over where a dead player is. A ghost can claim to stand at a
task point it is not at and collect `TaskWeight`'s 0.25 from anywhere. It cannot claim to be alive, be
seen, kill, be killed, or make the claim at all unless the server already believes it is a ghost.
Against leaking the identity of the monster to every client, that is not a close trade.

### Not delivered, and stated so it is not mistaken for done

- **Peer ghost bodies are not rendered.** `GhostRoster` carries UserIds and NOT positions, deliberately
  — so the client can draw THAT a peer exists, not WHERE. §4.7's "sees other ghosts" is half delivered,
  and closing it needs a ghost-to-ghost position channel with its own secrecy argument. Recorded in
  `GhostController`'s header rather than rendered wrong.
- Flight has never been run with a real player. No ghost HUD, no spook button (C18).
- Step 7.1's `TextChatService` spike is still unrun; that half of the file is unchanged and still
  labelled.

`npm run verify` green: 25 test files, 23 remotes declared / 18 wired, all eight checks.

---

## Audit of the rebuild — THE ORACLE IS NOT CLOSED

Scored 79/100. The redesign's central claim is **false**, and three file headers assert it.

### Finding 1 (Critical): `Player.Character == nil` IS the death oracle

Removing the ghost's server body did not remove the distinction — it inverted it. A living player has a
`Character`; a ghost has none, for the rest of the round. `Player.Character` is an unsecured replicated
property, and `for _, p in Players:GetPlayers() do dead[p] = (p.Character == nil) end` is one line.
`GetPropertyChangedSignal("Character")` turns it into a timestamped event.

That is the same sub-second global death signal Amendment A3 deleted `AlivePlayerCount` and the
`PlayerKilled` broadcast to remove, and since the Aswang is never a ghost, each nil eliminates a
candidate. **Worse today than it will be at C17**, because `StreamingEnabled` is off, so the signal is
noiseless and global.

**The auditor's structural point, which is the one that matters:** the oracle is "living players have a
body, dead ones do not", and that survives every choice about WHERE the body lives. *Absence is
observable.* No arrangement of "no server object" can close it.

So the option space was wrong from the start. The real choice is:

1. **Dead players keep a server body** — the corpse persists for the round, or a decoy `Character` the
   player does not control. This is the HUSK move (`RoundService.onPlayerRemoving`) applied to death,
   and it is the only shape where `Character ~= nil` holds for everyone. Ghost position then comes from
   that body again, and the client-reported position can go away.
2. **Amend A3** to accept that death is public once ghosts exist.

**No further patching until this is decided.** Three headers currently claim closure and must be
corrected or made true; they are named in the finding.

### Finding 2 (Critical, UNVERIFIED): layer 1 may publish the dead set itself

`removeFromLivingChannels` destroys a ghost's `TextSource` in `RBXGeneral`. If `TextSource` children
are client-visible — and `TextChannel:GetTextSource(userId)` is client-callable — then that returns nil
for exactly the dead. The protection would BE the leak. Added as spike question 6; unrun. If true,
layer 1 becomes "revoke `CanSend`" instead: same enforcement, no observable delta.

### Fixed this round — three regressions independent of the design question

**A ghost could make the FETCH task uncompletable for the whole round.** `tickFetch` picks ONE
candidate — the nearest — and `FetchCarry.decide` then refuses it unless the weight is full, with no
fallback to the next-nearest. Safe while `positionOf` returned nil for the bodiless; C16 admitted
ghosts, and a ghost reporting the source's own position wins at distance 0 (beating any real HRP, which
sits studs off the part centre). Result: item never picked up, 5/5 unreachable, gate never opens,
survivors' win gone. Also fired **by accident** whenever an honest ghost drifted near the source. The
weight filter now lives in the selection rather than two functions downstream.

**`task.Progress` leaked what `Hits` no longer did.** The previous round ceiled `Hits` on the bar and
missed its sibling: `state.Hits / 3` with a ghost's 0.25 yields 0.0833…, where living hits give
multiples of 1/3. Reading a non-multiple off `YourTaskProgress` proved someone was dead and within
`PresenceRangeStuds`. Now ceiled before dividing.

**The stale chat-layer comment is replaced.** It still said two layers existed and whispers leaked —
true when written, false since. Replaced rather than edited, and the open `TextSource` question is
recorded in its place.

### Known and NOT fixed, pending the finding-1 decision

- **The continuity check is worth ~1/6th of its comment.** `FlySpeed * (elapsed + 1)` has a per-report
  constant while the client picks the rate: back-to-back reports allow 24 studs each, so the 10-token
  burst permits ~240 studs instantly and ~144 studs/s sustained against an intended 24. Harmless alone
  now that the fetch hole is closed, but the header's "must be walked rather than teleported" is not
  what the code enforces. Fix: clamp `elapsed` to the report interval, and drop `Capacity` to ~3.
- **The spook is now a client-placed, client-timed pointer.** Origin derives from a position the ghost
  CHOOSES, offset randomly by ≤30 studs. A ghost can claim the Aswang's position and spook: a one-bit
  channel from the dead to the living, localised to a 30-stud disc — the exact thing §4.7's last bullet
  forbids, routed around the chat wall. Medium now (it renders nothing), **Critical at C34**. Fix is to
  place it from a server-chosen point, not the ghost's.
- The `RequestTimingStop` budget comment claims a miss resets the count; false for ghosts since the
  sabotage fix.

### Confirmed intact after the surgery

`GhostChat`'s rule (29 assertions), all three chat layers, husks in the raycast filter, weighted timing
hits, the ghost-miss no-op, and — checked explicitly — **`positionOf` never routes a living player
through the reported position**. Client-created Instances genuinely do not replicate, so the local body
premise holds; the camera restores on every exit path. No §4.7 obligation silently broke: `GateService`
reads `player.Character` only, so a ghost cannot escape, and salt and kills both refuse a nil character.

`npm run verify` green: 25 test files, all eight checks.

---

## Phase 6, THIRD design — option A: the dead keep a body

User chose option A. The corpse stays attached as `player.Character` for the round.

### The change, in one line

`MonsterService.commitKill` no longer does `victim.Character = nil`. The corpse remains the dead
player's character, so **`player.Character ~= nil` is true for everybody** and the enumerable
distinction is gone.

Supporting changes:
- **`BodyTransitions.actionFor` short-circuits GHOST to KEEP on every cause**, above the `mayHaveBody`
  branch. The corpse is not the body rule's business: REVOKE would destroy the death signal §4.7 and A3
  both rely on, GRANT would spawn a walking body for a dead player, DEFER would retry that forever.
  The grid moved for the third time and the test records all three moves.
- **The corpse fades but is not destroyed.** §4.3's "remains 45s, then fades" is honoured visually; the
  Model survives until `clearCorpses` at round end. Destroying it at 45s would set `Character` to nil
  for exactly the dead — a leak with a 45-second fuse.
- `MarkKilled` passes `"KILLED"` and no longer double-calls or stamps `lastRespawnAt`; both existed to
  spawn a ghost body that no longer exists.
- `GhostController` and `ReportGhostPosition` STAY. The corpse marks where you died, not where you are,
  so a ghost's position for task contribution and the spook still comes from the client's local flying
  body.

### What this does and does not buy — stated because the caveat is the whole trade

**Closed:** the enumerable oracle. `Character == nil`, a `GhostBody` tag, and a hidden replicated Model
were each one line for any client to sweep. None of them exists now.

**Not closed until C17:** a corpse is still distinguishable from a walking player by property scan —
`Humanoid.Health == 0`, anchored parts, the `Corpses` parent folder. Fixing the folder alone would not
help, because the other two remain. **§5's `StreamingEnabled` is what makes this real**: a distant
corpse does not replicate at all, so the scan only sees bodies you are near, which is precisely
Amendment A3's "you learn about a death by finding the body". Until C17 turns it on, this is a genuine
improvement and NOT a closed hole, and no file claims otherwise.

`npm run verify` green: 25 test files, 23 remotes / 18 wired, all eight checks.

### Still open on Phase 6/7/8

- Step 6.1 flight probe, Step 7.1 chat spike — plus spike question 6, whether `TextSource` membership
  is client-visible (layer 1 may leak what it protects).
- The ghost continuity check is ~6× looser than its comment claims.
- The spook is a client-PLACED pointer — Medium now, Critical at C34.
- Peer ghosts are not rendered; §4.7's "sees other ghosts" is half built.
- The fetch candidate fix has no test behind it.
