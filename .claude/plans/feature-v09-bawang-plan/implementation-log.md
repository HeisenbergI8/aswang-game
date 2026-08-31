# Implementation Log: V09 — Bawang, the silent doorway

Plan: `.claude/plans/feature-v09-bawang-plan/feature-v09-bawang-plan.md`
Run: `2026-08-31T02-21-40-285Z-V09`

---

## Phase 1: The contract — a doorway, the numbers, and two pure decisions — 2026-08-31

**Steps completed:** 1.1, 1.2, 1.3, 1.4, 1.5, 1.6

**Files changed:**

- `src/shared/Config.luau` — five garlic tunables added to `Config.Items`
- `tests/config.test.luau` — §6.5 invariant 4 pinned, plus the breach-tolerance sanity bound
- `src/shared/Types.luau` — `USE_PLACE`, `GarlicPlaceVerdict`, `GarlicBarrierSpec`, `GarlicBarriersPayload`
- `src/shared/pure/GarlicPlacement.luau` — **new**, the placement verdict
- `src/shared/pure/GarlicBarrier.luau` — **new**, the burn-out clock and the crossing predicate
- `tests/garlic-placement.test.luau` — **new**, 29 assertions
- `tests/garlic-barrier.test.luau` — **new**, 42 assertions
- `tests/barrio-doorways.test.luau` — **new**, 25 assertions
- `tools/greybox/barrio.luau` — `doorway()` helper, nine call sites, receipt assertion, `anchor()` comment

**Gate:** `npm run verify` EXIT 0 — analyze ok (0 errors, 0 parse errors) · remotes 32/32 ·
secrecy ok · config ok · scope ok · ratelimit ok · debug ok · testcount ok · **test:unit 57 files ok**.
Per-step: `check:config` ok (1.1) · `config.test` 125 invariants, up from 123 (1.2) · `analyze` ok (1.3) ·
`garlic-placement` 29 assertions (1.4) · `garlic-barrier` 42 assertions (1.5) · `barrio-doorways`
25 assertions (1.6).

### Deviations from plan

1. **The plan's reference review has `box()` backwards, and the conclusion survives it.**
   `references/barrio-review.luau` states "`box()` multiplies POSITIONS by SCALE and leaves SIZES
   alone". Read from source: `box()` **does** scale X/Z sizes
   (`p.Size = Vector3.new(math.max(sx * SCALE, 0.2), sy, math.max(sz * SCALE, 0.2))`) and `v()` scales
   X/Z positions. `anchor()`'s own `6 / SCALE` argument — commented "the `/ SCALE` cancels the one
   `box` applies" — confirms it. **`Width = 6 * SCALE` is still correct**, because the door gap is the
   space between two wall segments whose *positions* scale. No code change; recorded so the next
   reader does not re-derive it from a wrong premise.

2. **The reference's open QUESTION about `building()`'s half-extents is settled from source, not
   deferred to Studio.** It reads `local hw, hd = w / 2, d / 2` at `tools/greybox/barrio.luau:531`.
   So the chapel (46 x 36) is 23/18 and the kubo (24 x 20) are 12/10, exactly as the plan assumed. The
   playtester still owes a screenshot of a `Doorway` pad sitting in an actual doorway — reading the
   arithmetic proves the offsets are consistent, not that the pads land where a player walks.

3. **`anchor()`'s comment got a four-line addition rather than a one-sentence one.** The plan's
   identified issue asked for a sentence; the exception needed naming in both directions, so the note
   sits in `anchor()` (where a reader is misled) *and* in `doorway()`'s header (where the exception is
   used).

4. **`tests/barrio-doorways.test.luau` asserts the chapel's offsets by their written spelling**
   (`-152 + 18`, not the collapsed `-134`). Pinning the sum is what keeps the two literals
   reconcilable against `d / 2` at all — a collapsed constant would parse and would have destroyed the
   only evidence of where it came from. Noted because it makes the suite sensitive to a
   *reformatting* of that line, which is a deliberate trade.

5. **The KUBO loop parents pads via `root:FindFirstChild(kubo.Name)`, as the plan wrote it**, rather
   than capturing `building()`'s return. It matches the file's existing idiom — the same lookup runs
   twice more in the same loop (lines 1764, 1839) — and `building()` parents the folder to `root`
   before returning, so the lookup cannot be nil.

### Notes for the playtester and the auditors

- **`tests/barrio-doorways.test.luau` was negative-controlled.** With `Width = 6 * SCALE` mutated to a
  bare `6`, the suite fails on exactly that assertion; reverted and re-confirmed green. Worth knowing
  because a source-parsing suite is the kind that passes vacuously, and this one does not.
  Two further assertions were proven to bite by failing for real during authoring (a `-` treated as a
  pattern quantifier rather than a literal, now a plain `string.find`).
- **Nothing is wired yet.** No remote, no service, no client. `check:scope` has not yet seen the words
  `Garlic`/`Bawang`/`Barrier` in a *wired* path — Step 2.1 is the first step that runs it against one.
- **The nine doorways do not exist in the place file yet.** `tools/greybox/barrio.luau` is a builder
  that must be re-run in Studio's command bar before any of this is visible, and the map is not in
  git. The receipt now `assert`s `count("Doorway") == 9`, so a re-run either produces nine pads or
  fails the build.
- **The map's real door gap is 9.3 studs** (6 pre-scale units × `SCALE` 1.55). `GarlicBarrierPadStuds`
  (1.5) widens the barrier past each jamb, so the built barrier is 12.3 studs wide.

---

## Phase 2: The server — placing bawang, and the item that finally has a verb — 2026-08-31

**Steps completed:** 2.1, 2.2, 2.3, 2.4, 2.5

**Files changed:**

- `src/shared/Remotes.luau` — `RequestPlaceGarlic` declared in `EVENTS_UP`, argument-free
- `src/shared/Config.luau` — `AntiCheat.Budgets.RequestPlaceGarlic = { Capacity = 3, RefillPerSecond = 0.25 }`
- `tests/anti-cheat-budgets.test.luau` — the matching `UP_REMOTES` entry
- `src/shared/pure/ItemUse.luau` — `BAWANG` → `USE_PLACE`; header rewritten, it described the old boundary
- `tests/item-use.test.luau` — bawang's asserted cell flipped; the "two unimplemented items are
  indistinguishable" check replaced with "salt and bawang have different verbs"
- `src/server/Services/ItemService.luau` — `nearestDoorway`, `doorwayOccupied`, `placeGarlic`,
  `expireGarlic`, `clearBarriers`, the `RequestPlaceGarlic` handler, the phase sweep, and the
  `droppedItems` folder comment
- `src/client/Controllers/InputController.luau` — `carriedItem` tracked off `RoundSnapshot`; `Q` routes
  to `RequestPlaceGarlic` when `ItemUse.verbFor` says `USE_PLACE`

**Gate:** `npm run verify` EXIT 0 — analyze ok · **remotes 33 declared / 33 wired** · secrecy ok ·
config ok · scope ok · **ratelimit ok** · debug ok · test:unit 57 files ok. Per-step: `check:remotes`
(2.1) · `anti-cheat-budgets` 17 remotes, 76 assertions (2.2) · `item-use` 10 assertions (2.3) ·
`check:ratelimit` (2.4) · `analyze` (2.5).

### Deviations from plan

1. **`UIController.GetCarriedItem()` does not exist, and the plan said to confirm before writing it.**
   Confirmed: it does not. `UIController.luau:322` says the HUD "reads `snapshot.YourCarriedItem`
   directly and keeps nothing". Took the plan's own stated fallback — `InputController` now holds the
   last snapshot's `YourCarriedItem` in a file-local `carriedItem` and subscribes to `RoundSnapshot`
   itself. `SkyController` already does exactly this for its own two fields, so it is the established
   shape, adds no remote, and avoids giving the HUD state it deliberately refuses to keep.

2. **`placeGarlic` lost its `player` parameter.** The plan's signature was
   `placeGarlic(player, doorway)`, but the body never reads `player` — deliberately, since the part
   must carry no placer. An unused parameter would have been an analyze failure and, worse, an
   invitation to start using it. Signature is `placeGarlic(doorway)`; the noise emit that *does* need
   the player stayed in the handler.

3. **`local part: BasePart = Instance.new("Part")` is annotated, not inferred.** `ActiveBarrier.Part`
   is typed `BasePart` and Luau table fields are invariant, so an inferred `Part` is not "exactly" a
   `BasePart` and `table.insert` failed to typecheck. Every property set here is a `BasePart`
   property, so the annotation is honest rather than a cast.

4. **`ItemUse`'s module header was rewritten, which the plan did not ask for.** Four of its paragraphs
   asserted that bawang has no verb — including "a client that requires and runs this learns that
   bawang has no verb yet". Leaving them would have made the file's own documentation the most
   confidently wrong thing about it. The V09/V10 boundary argument is preserved, now naming one
   unimplemented item instead of two.

5. **`tests/item-use.test.luau` lost the "two unimplemented items answer identically" assertion.**
   With bawang implemented there is only one such item, so the property has nothing to hold between.
   Replaced with "salt and bawang have different verbs", which is the property `InputController`'s
   new routing actually depends on.

### Notes for the playtester and the auditors

- **`check:scope` was run against the wired path and passes.** The plan asked to confirm rather than
  assume that `Doorway`, `Bawang`, `Garlic`, `Barrier` and `PlacedGarlic` split into no token on §3's
  OUT list. They do not.
- **`PlayerRemoving` has no garlic branch, and that is deliberate** (the plan's own note). A placer who
  disconnects leaves a live barrier; garlic belongs to the world once placed and burns out on its own
  clock. Worth asserting rather than assuming, so: asserted here.
- **The barrier does nothing yet.** Phase 2 builds the placement, the public bulb, the burn-out and
  the server-side table. Nothing is sent to the Aswang and nothing blocks anybody — that is Phase 3.
  A playtest at this commit should show a garlic bulb appearing on a doorway and vanishing after 15s,
  and no movement effect on anyone.
- **Placing garlic on a doorway you are standing behind seals you in with the Aswang outside, and
  produces nothing at all for you.** First thing a tester will try; it must be a non-event.
- **`nearestDoorway` sweeps `GetTagged` on every call including refusals** — uncached on purpose, with
  the reason in the function header so a later reader does not "optimise" it into a staleness bug.

---

## Phase 3: The silent block — one remote, one client, one invisible part — 2026-08-31

**Steps completed:** 3.1, 3.2, 3.3

**Files changed:**

- `src/shared/Remotes.luau` — `GarlicBarriers` declared in `EVENTS_DOWN`
- `src/server/Services/ItemService.luau` — `garlicRemote`, `pushBarriers`, and its four call sites
  (placement, burn-out, `clearBarriers`, `watchCharacter`)
- `src/client/Controllers/GarlicController.luau` — **new**, the client-local barrier
- `src/client/init.client.luau` — `"GarlicController"` added to the ordered load list

**Gate:** `npm run verify` EXIT 0 — analyze ok · **remotes 34 declared / 34 wired** · secrecy ok ·
config ok · scope ok · ratelimit ok · debug ok · test:unit 57 files ok. Per-step: `check:remotes`
(3.1) · `check:secrecy` (3.2) · `analyze` (3.3).

### Deviations from plan

1. **`pushBarriers` had to be defined ABOVE `expireGarlic`, not below it.** The plan's diff ordering
   put the definition after `expireGarlic`, whose body calls it — in Luau that resolves to a nil
   global and dies at run time with "attempt to call a nil value", the exact trap
   `barrio.luau:1717`'s own comment records from an earlier chunk. `analyze` does not catch it
   (an unknown global in a function body is not a type error). Caught by reading the resulting line
   numbers; `garlicRemote` and `pushBarriers` now sit immediately before the burn-out block.

2. **`placeGarlic(doorway)` at the call site, not `placeGarlic(player, doorway)`** — carried over from
   the Phase 2 signature deviation.

3. **`part.Size`'s `0.5` thickness carries an explicit `config-ok` waiver**, as the plan's Potential
   Issues asked. Nothing else in the file needed one: width, height and yaw all arrive in the payload.

### Notes for the playtester and the auditors

- **The two unconfirmed Roblox behaviours are still unconfirmed, and they are the whole mechanism.**
  Nothing in this repo exercises either today, and neither is provable from source:
  1. *A part created by a `LocalScript` under `workspace` is never replicated to the server or to
     other clients.* If false, **this is a secrecy failure and must not ship.**
  2. *Such a part collides with the local player's own character.* If false, the mechanism does not
     work at all and the fallback in Follow Ups applies.
  Both are standard client-network-ownership behaviour, but "standard" is not evidence. **These are
  the playtester's first two artifacts**, ahead of anything about gameplay feel.
- **The `must never do` list was checked mechanically, not asserted.** `grep -E
  "WalkSpeed|SetAttribute|AddTag|Highlight|Sound|Animation|Humanoid|Camera|BodyVelocity|AlignPosition|ShowLine|FireAllClients"`
  over `GarlicController.luau` returns six hits and **all six are inside the header prose** — zero in
  code. On the server, the only `FireAllClients` in `ItemService` is C14's pre-existing salt
  broadcast at line 270, and no `pushBarriers` call site is wrapped in a role branch.
- **Yaw is converted exactly once**, in `placeGarlic` (`math.rad` on the pad's degrees attribute).
  `CFrame.Angles` and `pure/GarlicBarrier` both take radians. A doubled or missing conversion is
  **invisible at yaw 0** — the seven kubo — and only shows at the chapel's east door. The playtester
  needs a blocked Aswang at an **E or W** doorway, not just an N or S one.
- **A modified client still walks through, and Phase 3 does not stop it.** By construction. Phase 4
  is the backstop and this phase must not ship without it.
- **A rejoining Aswang has a one-round-trip gap** between `CharacterAdded` and the payload arriving,
  during which it can pass garlic. Bounded, not chooseable by the player, and closing it would need
  holding the character still — which is an observable effect. Accepted, not a bug to rediscover.

---

## Phase 4: The server's authority — a breach is the only thing allowed to show — 2026-08-31

**Steps completed:** 4.1, 4.2, 4.3

**Files changed:**

- `src/server/Services/ItemService.luau` — `checkBreach`, `sampleBreaches`, the call site after
  `pushBarriers()`, and the module header

**Gate:** `npm run verify` EXIT 0 — analyze ok · remotes 34/34 · secrecy ok · config ok · scope ok ·
ratelimit ok · debug ok · testcount ok · test:unit 57 files ok.
`npm run verify:plan` — **17 passed, 0 failed, 0 unverifiable; 17 discriminating checks, 0
file-exists, 0 self-satisfying.**

### Deviations from plan

1. **Step 4.1's test half was already complete.** Its `**File:**` is `tests/garlic-barrier.test.luau`
   and it asks for the crossing grid — every case it names (both samples one side, exactly on the
   plane, inside tolerance, lateral past `HalfWidth`, above `Height`, below the floor, and the single
   `true` shape, at yaw 0 **and** yaw 90) was already written in Step 1.5. No new assertions were
   needed; the suite runs 42 and is unchanged. Recorded so the auditor does not read an untouched
   file as a skipped step.

2. **`checkBreach` reuses the existing `vec()` helper** rather than building `GarlicBarrier.Vec3`
   literals inline, as the plan's Potential Issues asked. `vec` returns `ItemThrow.Vec3`; Luau is
   structural, so it satisfies `GarlicBarrier.Vec3` without a cast or a second helper.

3. **The header rewrite went further than "name the four things".** Two of its paragraphs were
   actively false after V09 — "Bawang and the buntot pagi are CARRIED AND DROPPED ONLY" and the
   four-item bullet list. It now names six server-decided things and states plainly that this service
   is *not* the authority on the block, with a pointer to `checkBreach` before anyone touches it.

### Notes for the playtester and the auditors

- **The breach path writes exactly one property.** Verified by grepping every assignment inside
  `checkBreach`: the only one is `root.CFrame = CFrame.new(from) * root.CFrame.Rotation`. No
  `WalkSpeed`, no `Anchored`, no `SetNetworkOwner`, no `Humanoid` state, no attribute.
- **The verbose log in the breach path prints no UserId, deliberately.** This is the one code path in
  the game reachable by exactly one player, so any identifier in it writes the round's secret to the
  server log.
- **The respawn false-positive guard is the `else` branch of the sampler.** No character means
  `lastSample = nil`, so a respawn on the far side of a doorway cannot read as a crossing. That is
  the single most likely way this loop would brand an honest player — check it explicitly.
- **A patient exploiter beats the sampler by moving slowly**, under `GarlicBreachToleranceStuds` per
  0.25s. Left open deliberately: closing it needs a swept-volume test, which raises the
  false-positive risk this chunk is most afraid of, and the prize is fifteen seconds of a doorway.
- **Analytics (`garlic_placed`, `garlic_blocked`) are NOT in this chunk** — they are V19's, and
  `AnalyticsService` is still a stub. The finding V19 must not rediscover: `garlic_placed` is one
  line server-side, but **`garlic_blocked` is not observable to the server at all** — an honest block
  happens inside the Aswang's client's physics and produces no event, no message and no state change.
  That is this chunk's central property, not an oversight. The closest honest proxy counts
  *approaches*, not blocks, and must be labelled as such.
- **For V16:** the question to bring is "did anyone ever see a monster snap backwards", not "does
  garlic work". If it happens even once, raise `GarlicBreachToleranceStuds` or delete the correction
  and accept the bypass — **never** add feedback to make the snap look intentional.

---

## Post-review: the block was rebuilt after the collidable wall was measured and rejected — 2026-08-31

**Not a plan phase.** Three reviews ran against the 4 completed phases; this records what they found
and what changed. The plan's Phase 3 mechanism (a collidable part on the Aswang's own client) **shipped
a measured role oracle and has been replaced.**

### What the reviews found

| Review | Score | Outcome |
| --- | --- | --- |
| `auditor` | 78/100 | All 17 steps traced, **no undocumented deviations**. Independently re-derived `Width = 6 * SCALE`; mutation-tested three `barrio-doorways` assertions beyond the one already controlled. Scored its own behavioural evidence 9/20 — correctly, it could not observe a client-local mechanism from a terminal. |
| `exploit-auditor` | 76/100 | Two Criticals, one High, one Low. Verified the probe surfaces genuinely closed: no client-supplied geometry, nothing echoed on any refusal path, no placer on the bulb, `pushBarriers` unconditional in the shared path, secrecy allowlist untouched. |
| `playtester` | — | 8 artifacts. Confirmed the two load-bearing Roblox behaviours, then **measured the oracle that killed the mechanism.** |

### The finding that changed the design

`artifacts/movedirection-oracle.md`. Read from the SERVER off a live character:

| Value | Voluntarily still | Blocked, holding key |
| --- | --- | --- |
| `Humanoid.MoveDirection` | `0, 0, 0` | **`-1, 0, -0`** |
| `AssemblyLinearVelocity` | `0, 0, 0` | `0, 0, 0` |
| `Position` | frozen | frozen (< 0.005 drift) |
| `Humanoid:GetState()` | `Running` | `Running` |

Three reads over ~2s, reproduced from a second approach angle. Only `MoveDirection` distinguishes.
It is an ordinarily replicated Humanoid property, so any client reads it off a peer — §4.6's loyalty
test becomes a perfect oracle. **Nothing in `GarlicController` could have suppressed it**: the engine
computes it from held input, not from whether the motion succeeded.

### What replaced it

**The block is no longer a wall the Aswang walks into. It is a movement that is never issued.**

- `pure/GarlicBarrier.suppress(barrier, point, move, margin)` — removes the component of a movement
  that would carry the character through a live doorway, and only that component. Movement along the
  wall and away from it are untouched, because a dead stop at a threshold is its own tell.
- `GarlicController` now binds at `Enum.RenderPriority.Input.Value + 1` and re-issues the reduced
  vector via `Humanoid:Move(v, false)` — the same call with the same signature the default control
  module makes. **It creates no part at all**; there is no `Instance.new` left in the file.
- `Config.Items.GarlicSuppressMarginStuds = 3.5`, which must exceed a character's hull radius (~2) or
  contact happens anyway and both signatures return.

This is §4.6's own sentence read literally — *"its movement simply does not carry it through."*

### The other four fixes

1. **`GarlicBreachGraceSeconds = 1` + `GarlicBarrier.isAuthoritative`** (Critical). A barrier was live
   on the server the instant placement resolved, but on the client one round trip later. In between
   the server enforced a wall the monster had nothing to be stopped by — so a survivor could gather
   everyone at a doorway, wait for someone to walk through, place garlic, and watch the Aswang snap
   backwards. §4.6's forbidden rubber-band, produced by the game against an honest player, two free
   attempts per round.
2. **Sticky correction after a confirmed crossing** (High). One lucky sample used to buy the rest of
   the barrier's life. **The auditor proposed keying stickiness on which side of the plane the Aswang
   stands; that was rejected and would have been catastrophic** — the plane is infinite, so an Aswang
   inside the chapel via its EAST door sits on the far side of the SOUTH door's plane and would have
   been restored forever, at the map's only two-door building. Gated on a confirmed crossing through
   the opening instead, and it clears itself when walked back. **This closes the one-lucky-sample
   bypass. It does NOT close the slow-walk bypass** the audit also claimed for it — an undetected
   crossing produces nothing to make sticky. That one remains open, as the plan accepted.
3. **`lastSample` dropped on every `sampleBreaches` call, including when a loop is already running.**
   It sat below the `breachRunning` early return, so the second bawang inherited a baseline taken
   before its barrier existed.
4. **The slot is spent only on a successful placement.** `placeGarlic` returns a boolean; the spend
   used to sit above a function that had an early return.

Also corrected: two comments claiming the breach tolerance protects against "a shove from a corpse".
Corpses are `Anchored = true, CanCollide = false` (`MonsterService.makeCorpse`) and cannot push
anybody. The vector those comments named was never real.

### Gate

`npm run verify` EXIT 0 — analyze ok · remotes 34/34 · secrecy ok · config ok · scope ok · ratelimit
ok · debug ok · test:unit 57 files. `garlic-barrier` is now **89 assertions**.

Both new predicates were negative-controlled, not just written: stubbing `isAuthoritative` to `return
true` (the pre-fix behaviour) fails 3 assertions; stubbing `suppress` to a no-op fails 5+.

### Still open

- **The suppression mechanism is UNVERIFIED at runtime.** It replaced a mechanism that passed every
  static check and was then killed by one measurement — so it earns the same measurement before
  anyone calls V09 done: does `MoveDirection` now read `0, 0, 0` while walking into a barrier?
- **Peer-to-peer observation remains human-gated** and always was: it needs a second Studio client,
  which no agent can open. The two-client doorway comparison from a third player's camera is V09's
  headline spec requirement and has never been performed.
- The slow-walk bypass of the server backstop, deliberately.

### Runtime verification of the redesign — closed

The suppression mechanism replaced one that passed every static check and was killed by a single
measurement, so it was held to the same measurement. `verification.md` Addenda 2–5.

| Condition | Frames sampled | Non-zero `MoveDirection` frames |
| --- | --- | --- |
| Voluntarily still | 300 (5s @ 60fps) | **0** |
| Holding into a live barrier, settled | 300 (5s @ 60fps) | **0** |

Sampled server-side in a single `RunService.Heartbeat` loop rather than by discrete round trips, with
the barrier confirmed alive at both ends and the position byte-identical across every frame. The old
mechanism's `(-1, 0, -0)` is gone. Also confirmed: the Aswang does not cross the doorway, can still
slide along the wall and walk away, and movement elsewhere in the barrio is unaffected when no barrier
is live.

**Two false starts on the way there, both worth keeping:**

1. **A whole measurement cycle was spent testing stale client code.** Studio copies the Edit DataModel
   into a separate runtime at Play start, and Rojo syncs into the *Edit* DataModel — so a source
   change during a live Play session **never reaches the running client, silently, with no error**.
   The session had run continuously since before the rewrite, so it measured the old wall a second
   time and reported the redesign as failed. It was caught only because the artifact noted a
   `CanCollide` part with a `task.delay` burn-out, which the current source cannot produce.
   **This nearly discarded a correct design.** Every later run proved the reload first, by
   `script_read` against the live instance in `PlayerScripts` and by confirming zero parts are created.
2. **The first frame-resolution attempt could not be established** because tool-call latency had grown
   past `GarlicDuration`'s 15 seconds and the barrier expired before the sampler started. Fixed by
   raising `GarlicDuration` to 120 and `Round.Duration` to 600 for the test — coordinator-side Config
   values the playtester cannot set. All seven test values have since been reverted and confirmed with
   `git diff src/shared/Config.luau`.

### Still not established, and it is the spec's headline requirement

**The two-client comparison has never been performed by anyone.** `BUILD-PLAN` §V09 asks the
playtester to record the doorway *from a third player's camera* and show nothing distinguishable
between a blocked Aswang and a player standing still. Player count is a Studio UI action no agent can
drive. Everything measured here reads the property server-side, which is the necessary precondition
for that oracle to exist — **it is not a substitute for observing it from a peer.** This goes to the
human gate with V16.

Also open, deliberately: the slow-walk bypass of the server backstop, and condition (c) — whether the
approach transition into the suppression margin has a frame where `MoveDirection` is non-zero while
the position is unchanged. The approach completes in under 0.6s of in-game walking, which was shorter
than the gap before a sampler could start.

---

## Second exploit re-audit, and the third and final shape of the block — 2026-08-31

`ItemService` and `GarlicController` were both rewritten after the first audit, and this is the 🔒
surface, so the delta earned a focused re-audit. **79/100, one Critical, two High.** It found the same
class of leak one layer down.

### The Critical: subtracting a component is itself a signature

`suppress` used to return `move - normal * into` — keep the slide, drop the inward part. The auditor
executed the module and printed the output: **the component along the doorway normal is identically
zero, and the magnitude is `|cos t|` for a unit input.** A keyboard emits `MoveDirection` of magnitude
0 or 1 and nothing between, and a refusing player's normal component varies continuously with their
camera. An Aswang inside the margin was publishing, every frame, a vector no ordinary input can
produce. The axis-pinning survives renormalisation, so it did not depend on what `Humanoid:Move` does
to the magnitude.

**And the 0/300 measurement did not cover it.** That was the head-on case, where suppression yielded
the zero vector and read as stillness. *Sliding* — the one case that wrote a non-zero value into a
replicated property — was never measured, and `artifacts/movesuppression-oracle.md` says so in its own
closing bullet.

### The fix: a full stop, which was the measured-silent state all along

`suppress` now returns **either the input unchanged, or exactly `(0, 0, 0)`**. Both are values an
ordinary keyboard produces, which is the criterion the audit set. Consequences:

- A diagonal into a doorway now yields the same zero vector as head-on, so **the existing 300-frame
  measurement covers it** rather than leaving a gap.
- Pure-lateral movement is still passed through untouched at magnitude 1 — walking along a wall is
  indistinguishable from any player walking that way.
- Moving away is untouched, so the monster can always leave.

**The "a dead stop is its own tell" argument that produced the slide was wrong on its own terms.**
§4.6's design is that a survivor may decline to walk in for any reason, so a character that stops at a
threshold reads as one that chose not to enter. Stopping is the indistinguishable behaviour.

`tests/garlic-barrier.test.luau` now asserts the **whole output vector**, not just its normal part —
the old assertions only checked `normalPart < 1e-9`, which is the presence of the signature and never
looked at the rest. Plus a magnitude grid at 15/30/45/60/75 degrees pinning that no fraction is ever
returned. **99 assertions.**

### The two High findings, both fixed

1. **Below 10 studs/s the backstop could never fire.** `crossed` required the destination more than
   `GarlicBreachToleranceStuds` past the plane within one `GarlicBreachSampleInterval` — a threshold
   of exactly `2.5 / 0.25 = 10` studs per second. `WalkSpeed = 9` deleted garlic permanently at zero
   risk. Arming now takes **no distance tolerance**; the tolerance gates a far-side *streak* instead,
   which accumulates over successive samples, so a slow crosser is still caught a quarter-second
   later. Two consecutive far-side samples are required before correcting, which replaces the
   tolerance's old job of protecting a threshold-stander.
2. **The grace window was amnesic.** `checkBreach` skipped a non-authoritative barrier entirely, so a
   crossing made in the first second was never *observed* — and once on the far side, no later sample
   can produce the sign change. One second of blindness bought the whole remaining fourteen, and the
   window opens at a moment every client can see. Observation now runs always; **only the correction
   is deferred.**
3. **`lastSample` was written pre-correction**, handing the next call a segment nothing traversed.
   `checkBreach` now returns the restored position and the sampler uses it as the baseline.

### Also fixed

- `tests/config.test.luau` pins `GarlicBreachToleranceStuds < GarlicBreachSampleInterval ×
  Trial.PlayerBaselineWalkSpeed` — the relationship that decides whether the backstop can fire at
  walking pace, and which nothing was watching. Plus a pin that the suppression margin clears a
  character's hull. **127 invariants.**
- Two headers still described the rejected collidable wall in the present tense, in the two files most
  likely to be edited next by someone tuning these numbers. Rewritten, with the wall kept as history.
- `GarlicController`'s header claimed the vector "is still `Move`d" on the unchanged path; the code
  returns before any `Move`. The code was right and the comment was wrong.

### Gate

`npm run verify` EXIT 0 — analyze ok · remotes 34/34 · secrecy ok · config ok · scope ok · ratelimit
ok · debug ok · test:unit 57 files. `garlic-barrier` 99 assertions, `config` 127 invariants.

### What a future run should re-measure

The block's *output* is now provably inside the set an ordinary player produces, and that set was
measured silent. What has **not** been re-observed since this change is the behaviour: that the Aswang
still cannot pass, can still walk away, and that a dead stop at a threshold does not read oddly to a
human watching. None of that is a secrecy question, but it is the kind of thing V16 should watch for.
