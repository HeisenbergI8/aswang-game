# V08 — ItemService: the three items — implementation log

Plan: `.claude/plans/feature-v08-three-items-plan/feature-v08-three-items-plan.md` (5 phases, 21 steps)
Run: `2026-08-29T04-09-21-218Z-V08`

---

## Phase 1: The pure modules generalise — 2026-08-29

**Steps completed:** 1.1, 1.2, 1.3, 1.4 (1.4 partially — see Deviations)

**Files changed:**
- `src/shared/pure/ItemCarry.luau` (new, 135 lines) — migrated from `pure/SaltCarry`
- `src/shared/pure/ItemThrow.luau` (new, 252 lines) — migrated from `pure/SaltThrow`
- `tests/item-carry.test.luau` (new) — migrated from `tests/salt-carry.test.luau`
- `tests/item-throw.test.luau` (new) — migrated from `tests/salt-throw.test.luau`
- `src/server/Services/TrialService.luau` — retargeted at `ItemThrow` (require, `Vec3` type, `inCone`
  call at the throw handler, three comment references)
- `tests/salt-carry.test.luau`, `tests/salt-throw.test.luau` — DELETED

**Gate:** `npm run verify` EXIT 0 — analyze ok · lint ok · fmt ok · remotes ok (31/31) · secrecy ok ·
config ok · scope ok · ratelimit ok · test:unit 47 files ok

### The assertion count, which the plan makes the contract

| Suite | Before | After |
| --- | --- | --- |
| carry | `salt-carry` 38 | `item-carry` **49** |
| throw | `salt-throw` 70 | `item-throw` **78** |
| total | 108 | **127** |

> ⚠️ **These are Phase 1's numbers and `item-throw` does not stop here.** Phase 4 adds the paired
> verb-gate assertions and takes it to **81** (final total **130**). Flagged by the auditor as a
> navigability gap: a reader checking Step 1.4's contract against this table alone would believe the
> migration shipped 78 and could wrongly conclude a later edit dropped assertions.

Both migrated suites print a total GREATER than the suite they replaced, which is Step 1.4's stated
requirement. The new assertions are the item-type dimension: the 12-cell HELD × INCOMING matrix, the
two blindness properties, the six-row worlds table (was four), and the wrong-item × geometry grid.

### The geometry was proven identical, not assumed

Step 1.2 requires `inCone` to move across byte-for-byte. Verified mechanically rather than by eye:
stripped block comments and line comments from `SaltThrow.luau:67-164` and the corresponding
`ItemThrow.luau:96-194`, applied only the `SaltThrow.inCone` -> `ItemThrow.inCone` rename, and diffed.
**Zero executable-line differences.** Every difference in the raw diff was a comment.

That is what licenses deleting `tests/salt-throw.test.luau` while `SaltThrow.luau` is still the module
`ItemService` calls in production (see Deviation 1): the 78 assertions now on `ItemThrow` cover
executable code that is character-identical to the live path.

**Deviations from plan:**

1. **`SaltCarry.luau` and `SaltThrow.luau` are NOT deleted yet.** Step 1.4 anticipated this and stated
   the escape hatch itself: `ItemService` still requires both (`ItemService.luau:41-42`, `:289`,
   `:331`, `:540`), so deleting them now is a hard analyzer error and a red gate, and
   `implement-plan` forbids starting Phase 2 on one. The deletions move to Phase 3 (`SaltCarry`, with
   `pickupTick`) and Phase 4 (`SaltThrow`, with `resolveThrow`). The TEST retirement half of Step 1.4
   was done here as written.

2. **`TrialService`'s Config reads still say `Config.Salt.*`.** The plan's own Phase 1 "Issues
   identified" names this and recommends exactly this ordering: `Config.Items.ThrowConeDegrees` does
   not exist until Step 2.1, so the reads are re-pointed there rather than here. Every step leaves a
   green tree.

3. **`TrialService`'s two long comments at ~555 and ~634 were NOT rewritten.** The plan asks Step 1.3
   to rewrite them because they describe `ItemService.discoverPool` and `pickupTick`, which Step 3.1
   deletes. Those functions still exist right now, so rewriting them here would make a comment that is
   wrong today and right later. Moved to Phase 3, where the functions actually die. Only the module
   NAME references in them were updated (`pure/SaltThrow` -> `pure/ItemThrow`).

4. **The plan's literal `worlds` table diff had two identical rows** — "not the Aswang" and "the
   Aswang, untransformed" were both `TargetIsTransformedAswang = false` with the same position, so one
   was a duplicate rather than a distinct world. Used the ORIGINAL suite's version, which distinguishes
   them by `TargetPos` (`v(10,0,0)` vs `v(5,0,0)`), and appended the two new V08 rows. Six rows, six
   distinct worlds.

**Notes for the playtester and the auditors:**

- **A bug in my own new test, found and fixed before the gate.** `tests/item-carry.test.luau`'s
  "OK iff the hand is empty" property was first written as
  `for _, held in { nil, "SALT", "BAWANG", "BUNTOT_PAGI" }`. That literal iterates **three** times, not
  four — generalized iteration skips the `nil` at index 1 — so the empty-hand row, the only row that
  can produce OK, never ran and the "if and only if" proved one direction while reading as though it
  proved both. Measured with a probe (`iterations = 3`), not assumed. Rewritten as a list of
  `{ Held: ItemType? }` records, plus a `cells == 12` assertion so a zero-iteration loop can never
  pass the property again. This is `green-after-each-patch-hides-a-loop`'s shape caught early.

- **`Types.SaltVerdict` now has two vocabularies live simultaneously**, deliberately. `ItemService`
  still returns the C14 spellings (`WRONG_PHASE`, `NO_POUCH`) from `resolveThrow` until Step 4.2. The
  plan's Phase 1 issues list says not to tidy this early — the cast at `ItemService.luau:558` is
  load-bearing and Step 4.2 replaces it as a unit.

- **Nothing crossed the client boundary in this phase.** No remote added, changed or removed; no
  attribute, no tag. `check:secrecy` and `check:remotes` both ok, 31 declared / 31 wired unchanged.

---

## Phase 2: Config, Types and the remote surface — 2026-08-29

**Steps completed:** 2.1, 2.2, 2.3, 2.4

**Files changed:**
- `src/shared/Config.luau` — `Items` gains `CarryLimit`, `ThrowConeDegrees`, `DropPickupRangeStuds`,
  `DropForwardStuds`, `TrialPickupRangeStuds`, `SaltRgb`, `BawangRgb`, `BuntotPagiRgb`;
  `Monster` gains `ExposedGlowFillRgb`/`ExposedGlowOutlineRgb`; `AntiCheat.Budgets` gains
  `RequestDropItem`
- `src/shared/Types.luau` — `ItemCarryVerdict`, `ItemThrowVerdict`, `ItemDropVerdict`,
  `ItemUseVerdict`
- `src/shared/Remotes.luau` — `RequestDropItem` in `EVENTS_UP`
- `src/server/Services/MonsterService.luau` — two glow colour reads re-pointed
- `tests/config.test.luau`, `tests/anti-cheat-budgets.test.luau`

**Gate:** `npm run verify` EXIT 0 — remotes ok (32 declared, 31 wired; `RequestDropItem` declared and
not yet wired, which Step 4.3 closes) · config 131 invariants · anti-cheat-budgets 16 remotes, 72
assertions · test:unit 47 files ok

**Deviations from plan:**

1. **`Config.Salt` was NOT deleted.** The plan's own Phase 2 issues list called this the riskiest edit
   in the chunk and recommended exactly this: leave the table through Phase 2 and delete it in Step
   5.2 when its last reader goes. `ItemService` (Phase 3), `UIController` and `InputController`
   (Phase 5) still read it, and a missing Config key is a hard analyzer error. **Choice recorded as
   the plan asks.**

2. **Three more keys became ALIASES rather than staying values.** `CarryLimit`, `ThrowConeDegrees`
   and `PouchRgb` were real values in `Config.Salt`; their canonical home is now `Items`, so they
   point into it exactly as V02's four do. Three new alias guards were added to
   `tests/config.test.luau` for the reason the existing four give — nothing mechanically stops a
   tuning session replacing a reference with a literal, and the two numbers then diverge silently.
   `PouchRgb` is compared by table IDENTITY, which is the strongest available assertion for a table.

3. **The glow colours moved to `Config.Monster`, against a comment that said not to.**
   `Config.luau:288` argued "THE COLOURS ARE NOT HERE… Do not merge them — a tuner opening this block
   is tuning health, not salt." That argument assumed `Config.Salt` would continue to exist. It will
   not, so the choice became `Items` or `Monster` rather than "stay". `Monster` won because the glow
   is a Highlight ON THE MONSTER, `MonsterService.applyExposed` reads the two colours and the two
   transparencies in one breath, and a tuner opening that block now has every number the Exposed glow
   uses. **The stale comment was rewritten to record the reversal and its reason** rather than
   silently deleted. The items' own colours live in `Items.SaltRgb`/`BawangRgb`/`BuntotPagiRgb`.

4. **`SaltVerdict` was not deleted** — the plan offered Step 4.2 as the alternative landing spot and
   the analyzer requires it: `ItemService.resolveThrow` still returns it. Marked with a ⚠️ header
   saying so, so nothing new gets wired to it in the meantime.

5. **Two extra `Config.Items` assertions beyond the plan's three.** The plan specified the drop-radius,
   search-radius and carry-limit checks. I added a cone-bound check (`0 < ThrowConeDegrees < 90`)
   because Step 2.1 moved that number to a new home and the old pin at `tests/config.test.luau:203`
   read it through `Config.Salt`; without a new one, deleting the alias table in Step 5.2 would drop
   a bound that `pure/ItemThrow.inCone` fails closed on.

**Notes for the auditors:**

- **§6.5 invariant 1 was not touched and still holds at zero margin** — `SaltDamage x
  (SaltSpawnCount - 1) >= MaxHealth - WeakenedThreshold` is `25 x 3 = 75 >= 75`. No number this phase
  moved appears in it.
- **Two invariants were re-pointed rather than deleted**, which the plan flagged as the one thing this
  step must not get wrong: invariant 3 (`ThrowRange > KillRange`) and invariant 6 (`RevealDuration >
  StunDuration`) read through `Config.Salt` and now read `Config.Items` directly. They are invariants
  wearing alias clothing, not alias guards, so they must survive the table rather than go with it.
- **`RequestDropItem` is declared and unwired between here and Step 4.3.** `check:remotes` reports
  that explicitly (32 declared, 31 wired) and it is not a failure — the direction is the risk, and
  it is in `EVENTS_UP` only. No `EVENTS_DOWN` entry, no `check-secrecy.mjs` edit: it is client→server
  and carries nothing, so it has no business in `REVEAL_ALLOWLIST`.

---

## Phase 3: `ItemService` — the slot, fed by containers — 2026-08-29

**Steps completed:** 3.1, 3.2, 3.3, 3.4, 3.5

**Files changed:**
- `src/server/Services/ItemService.luau` — 745 lines to 806; the `SaltSpawn` pool, `discoverPool`,
  `reportPool`, `EvaluatePool`, `spawnPouches`, `clearPouches`, `pickupTick`, both tags and the
  `task.spawn` tick all deleted; `slot`, `placeItem`, `spillItem`, `clearDroppedItems`, `colourOf`,
  `onItemFound` and `watchCharacter` added
- `src/server/Services/SearchService.luau` — two comments (no logic)

**Gate:** `npm run verify` EXIT 0 — lint 0 errors / 0 warnings · check:secrecy ok · check:config ok ·
analyze ok · test:unit 47 files ok

### The second salt economy is gone

This was the High finding in the architect's report and it was real: `SearchService` seeds seven items
into containers from `Config.Items.*SpawnCount` AND `ItemService` spawned four pouches at `SaltSpawn`
points, both live. Eight pouches in a round where §4.6 says four — which breaks §6.5 invariant 1
(`SaltDamage x (SaltSpawnCount - 1) >= MaxHealth - WeakenedThreshold`, currently equality at 75) while
`tests/config.test.luau` stays green, because that suite reads Config and not the world. Only the
container economy survives.

**Deviations from plan:**

1. **`placeItem`/`spillItem` landed in Phase 3, not Phase 4.** The plan assigns the world-placement
   helper to Step 4.3, but Steps 3.2 and 3.4 both CALL it — the spill-on-refusal, the drop-on-death and
   the drop-on-disconnect are all Phase 3 and all need an item to reach the floor. Step 4.3 keeps the
   `RequestDropItem` handler and the pick-it-back-up path.

2. **The throw still resolves through `pure/SaltThrow`, behind an explicit transitional bridge.**
   Step 4.2 owns that swap. The bridge is `if slot[uid] == Enums.ItemType.Salt then 1 else 0`, and it
   is deliberately the CONSERVATIVE direction: a player holding a bawang or the buntot pagi reads as
   zero pouches and gets `NO_POUCH`, which returns early and spends nothing. Under `ItemThrow` the same
   player gets `MISS`, which falls THROUGH to the spend line — so leaving the bridge conservative means
   the tree between here and Step 4.2 cannot eat a buntot pagi on a mis-press. Both the bridge and the
   spend line carry ⚠️ comments naming Step 4.2 as the thing that must land.

3. **`ItemCarry` replaced the carry call, so `SaltCarry` lost its last reader here.** `SaltThrow`
   still had one (the bridge) and dies in Step 4.2.

   **CORRECTION, made in Phase 5:** this entry originally claimed `SaltCarry.luau` was DELETED in this
   phase. It was not — only its last reader went. The file sat on disk with zero readers until Phase 5
   noticed it during the `Config.Salt` sweep, and was deleted there. Nothing depended on it in the
   meantime and no gate could have caught it: an unreferenced module is not a lint error, not an
   analyze error, and not a failing test. Recorded rather than quietly fixed because "deleted" in an
   implementation log is exactly the kind of claim an auditor traces.

4. **Drop-on-death is a `Humanoid.Died` connection, not a corpse-folder watch.** The plan suggested
   anchoring on `MonsterService.GetCorpsesFolder`. `Died` is strictly better for the stated requirement
   — the plan itself says to read the position BEFORE a ragdoll settles, and a corpse-creation hook
   runs after. It also avoids `ItemService` reaching into another service's folder for a fact it can
   read from the character it already has.

**Notes for the auditors — and one for `exploit-auditor` in particular:**

- **The full-handed-search hole is closed, and it is the highest-consequence one in the chunk.**
  `SearchService.completeSearch` marks the container opened, reads the item and fires `ItemFound`
  BEFORE `ItemService` has any say. If `ItemCarry` then refuses, the item has left the world and is in
  nobody's slot. With one buntot pagi per round, a survivor searching its container while holding a
  pouch would delete the second win condition, silently, by honest play. `onItemFound` now calls
  `spillItem` on every non-OK verdict, so the item lands at the searcher's feet instead.
  **This is reachable without an attacker and deserves a direct look.**

- **A Luau typing trap worth recording.** `local item = itemId :: Types.ItemType` after three `~=`
  tests COMPILES and is wrong: `itemId` is `unknown`, Luau refines it to `string | string | string`,
  and the `ItemCarry.Request` then fails on `Incoming`. The fix is to assign the frozen `Enums`
  constant in each branch, which carries `Enums.luau`'s own `:: Types.ItemType`. This is
  `pure-module-unions-widen-in-lists` arriving through a second door — a literal union does not survive
  being reconstructed from a value that lost it.

- **No tick replaced the deleted one.** The service is now entirely event-driven: `ItemFound`, two
  `OnServerEvent` handlers, `PhaseChanged`, `Humanoid.Died`, `PlayerRemoving`. The comment where the
  `task.spawn` loop used to be says so and points at Step 4.3's `Touched` approach for the floor
  pickup, so the sweep does not come back by default.

- **`SearchService.foundByPlayer` is now labelled a debugging aid, not state**, with `ItemService.slot`
  named as authoritative. Follow Up 2 resolved by narrowing rather than by deleting, because deleting
  it touches V03's verification story.

- **Nothing new crosses the client boundary in this phase.** No remote wired yet, no attribute, no tag.
  The `DroppedItems` folder is in `workspace` and is public by nature — it holds objects every client
  can already see, and it names no player.

---

## Phase 4: The verbs — throw, drop, and the V09/V10 boundary — 2026-08-29

**Steps completed:** 4.1, 4.2, 4.3, 4.4

**Files changed:**
- `src/shared/pure/ItemUse.luau` (new) + `tests/item-use.test.luau` (new, 10 assertions)
- `src/shared/pure/ItemDrop.luau` (new) + `tests/item-drop.test.luau` (new, 26 assertions)
- `src/shared/pure/SaltThrow.luau` — DELETED (last reader retargeted)
- `src/server/Services/ItemService.luau` — `resolveThrow` on `ItemThrow`, the verb gate, the
  `RequestDropItem` handler, `TAG_DROPPED`, the `Touched` pickup
- `src/server/Services/MonsterService.luau` — the `ApplySaltHit` V08 comment (no logic)
- `tests/item-throw.test.luau` — the paired guard assertion (78 to 81)
- comment-only retargets in `Remotes.luau`, `FeedRules.luau`, `NoiseModel.luau`, `MonsterService.luau`

**Gate:** `npm run verify` EXIT 0 — remotes ok (**32 declared, 32 wired**) · ratelimit ok · secrecy ok ·
test:unit 49 files ok

### The bug this phase existed to not ship

Step 4.2's verb gate is the architect's second Critical finding and it is real. Under `pure/ItemThrow`,
a player holding a bawang or the buntot pagi who presses throw gets `MISS` — correctly, the fifth world
is collapsed on purpose so a refusal shape cannot be differenced into a role oracle. But `MISS` falls
THROUGH to the spend line, and the spend line clears the slot. **Pressing the throw key while holding
the round's only buntot pagi would have destroyed the second win condition, with a symptom
indistinguishable from an honest miss.**

The guard is `if ItemUse.verbFor(slot[player.UserId]) ~= "USE_THROW" then return end`, and its position
is load-bearing in both directions: BELOW the refusal branch so a wrong-item press still burns an
AntiCheat token, and ABOVE `NoiseService.Emit` so it makes no sound — a noise fired for a non-throw
would be a free "I am holding something that is not salt" broadcast to everyone in radius.

`tests/item-throw.test.luau` now asserts the two halves TOGETHER, because either alone looks sufficient
and is not: the throw must MISS **and** the verb must refuse the spend.

**Deviations from plan:**

1. **`pure/ItemDrop` got its own Lune suite (26 assertions), which the plan did not specify.** Step
   4.3's Verify is `check:ratelimit`, which says nothing about the drop RULE. CLAUDE.md requires a pure
   decision module to have one, and the drop is the only way a living player empties a slot without
   using the item — a rule wrong here either strands the buntot pagi in a dead player's hand or lets it
   be dropped twice, and one of those duplicates the win condition.

2. **The transitional bridge from Phase 3 is gone**, as planned. `resolveThrow` now calls
   `ItemThrow.evaluate` with `Held = slot[...]`, and `Types.SaltVerdict`'s last reader went with it.

3. **Four comments outside the plan's file list were retargeted** — `MonsterService`, `Remotes.luau`
   (x2), `FeedRules`, `NoiseModel` all named `pure/SaltThrow`, which no longer exists. Step 3.5's own
   objection applies: a comment naming a deleted module is worse than no comment, because it reads as
   current.

4. **`Types.SaltVerdict` still exists in `Types.luau`.** It now has zero readers. Deleting it is a
   one-line edit but `Types.SaltEffectPayload` and the `SaltEffect` remote legitimately survive beside
   it, and removing a public type is the kind of edit worth doing in its own diff. **Flagged as a
   follow-up rather than done here.**

**Notes for `exploit-auditor`:**

- **The `Touched` pickup is the one unverified Roblox behaviour in this chunk.** The plan flagged it:
  `Touched` on an anchored `CanCollide = false` part has no precedent in this repo. The handler
  re-checks distance **on the server** from the player's own character
  (`<= Config.Items.DropPickupRangeStuds`), so a `Touched` that fires spuriously cannot grant an item
  outside the radius — but whether it fires at all is a runtime question the playtester must answer.
  If it does not fire, dropped items become unpickupable and the fallback is a tick.
- **`Touched` fires for any BasePart** — corpses, other dropped items, map geometry. The handler
  narrows to a Model with a resolvable `Player` and a `HumanoidRootPart` before doing anything, and
  `ItemCarry` re-checks phase and ALIVE regardless.
- **The dropped part carries the item type and nothing else.** No UserId in the Name, no attribute, no
  child value. The comment in `placeItem` says why: "who dropped this" is a per-player fact, and a part
  named `Dropped_12345` lying in the barrio is readable by every client with no check in this repo
  reporting it.
- **`ApplySaltHit` was not modified** — Step 4.4 is a comment. All six jobs were verified present and
  in the claimed order by reading the function, not by trusting the plan's table.

---

## Phase 5: The client, and the tell that must not exist — 2026-08-29

**Steps completed:** 5.1, 5.2, 5.3, 5.4

**Files changed:**
- `src/server/Services/RoundService.luau` — `SetCarriedItemProvider` + `YourCarriedItem` in
  `buildSnapshot`
- `src/server/Services/ItemService.luau` — provider registration in `Start`
- `src/client/Controllers/UIController.luau` — the `saltSeen` estimate, the `ChildRemoved` listener,
  the `~` prefix and `UIController.NoteThrow` all DELETED; `render` reads `snapshot.YourCarriedItem`;
  `ActionHandlers` gains `Drop`
- `src/client/Controllers/InputController.luau` — `NoteThrow()` call removed, `performDrop`,
  `onDropAction`, `DROP_ACTION` bound to `X`
- `src/shared/Config.luau` — **`Config.Salt` DELETED**; the `Items` header rewritten
- `src/server/Services/TrialService.luau` — last three `Config.Salt` reads re-pointed
- `src/shared/pure/SaltCarry.luau` — DELETED (see the Phase 3 correction)
- `tests/config.test.luau` — seven alias guards removed with the table; two invariants re-pointed; the
  dead `PouchPoolSize` check retired

**Gate:** `npm run verify` EXIT 0 — analyze · lint 0/0 · fmt · remotes 32/32 · secrecy · config ·
scope · ratelimit · test:unit 49 files. `verify:plan`: **20 passed, 0 failed, 1 unverifiable** (Step
4.4, deliberately).

### Step 5.4's actual finding, measured rather than asserted

The plan's key assertion is that `GetAswangUserId` appears **exactly once** in `ItemService`. It does —
line 286, inside `resolveThrow`, ANDed at line 306 into one boolean about a *target* and handed to
`pure/ItemThrow` as `TargetIsTransformedAswang`. `onItemFound`, the drop handler, the `Touched` pickup
and the snapshot provider contain **no role read at all**.

Against the plan's seven leak shapes, grepped in the finished file: no `SetAttribute`, no `Backpack`,
no `Instance.new("Tool")`, no `Highlight` (the only mentions are comments about `MonsterService`'s
Exposed glow), no new `FireAllClients`. The single `AddTag` is on the dropped PART, never on a player.
`WalkSpeed` appears only in C14's stun, which applies to whoever was hit and reads no role.

**Deviations from plan:**

1. **`carriedItem` is not mirrored into a local at all.** The plan's diff kept a module-level local
   updated from the snapshot. `render` already receives the snapshot, so a local would be a second
   source of truth for a value that has one — and the phase-change reset it would then need is exactly
   the drift Step 5.2 exists to remove. Reading `snapshot.YourCarriedItem` directly deleted the
   `PhaseChanged` clear too, and with it an empty `if` block selene flagged.

2. **`ActionHandlers` gained a declared `Drop` field.** Not in the plan, and it is not cosmetic: the
   type is a closed record, and **an extra field on an annotated table is accepted silently by the
   Luau typechecker** — the same trap `Types.SaltEffectPayload`'s comment names. Passing `Drop` to
   `BindActions` without declaring it typechecks, stores fine, and is invisible to the touch pad, so
   mobile would silently have no drop. Caught by reading the type, not by a gate.

3. **`Config.Salt` deleted here, as the plan's Phase 2 issues list recommended**, once its last reader
   went. Seven alias guards went with it; the two §6.5 invariants that read *through* it were
   re-pointed at `Config.Items` and survive. The `PouchPoolSize >= SpawnCount` check was retired
   because the `SaltSpawn` pool it guarded no longer exists, with a comment saying where the
   equivalent guard for containers lives. The duplicate cone-bound check was removed in favour of the
   V08 one added in Phase 2. `tests/config.test.luau`: 131 -> 122 invariants, and the drop is
   accounted for line by line above.

### The trial-HUD risk the plan flagged is a non-issue, and here is the evidence

The plan called this "the most likely missed consequence of Step 5.2": deleting `saltSeen` might leave
the Solo Trial teaching a throw while the HUD shows an empty hand.

It cannot. `saltSeen` only ever incremented from `ChildRemoved` on the `SaltPouches` **folder**, and
`TrialService` parents its scripted pouch to `workspace` directly with the name `TrialSaltPouch` and no
`SaltPouch` tag. That event never fired for the trial's pouch, so the trial never displayed a count.
`Types.TrialSnapshot` carries no item field either, and `TrialController` renders beat text only.
Nothing was lost. **Checked rather than assumed** — the plan was right to flag it and wrong about the
outcome.

**Notes for the playtester and `exploit-auditor`:**

- **The provider seam is the first injected reader in this repo.** `RoundService.SetCarriedItemProvider`
  exists because `ItemService` requires `RoundService` and the reverse is a cycle, which Luau answers
  with a half-built table rather than an error. A BindableEvent cannot do this job — events push and
  `buildSnapshot` needs to pull synchronously. Flagged for evaluation, per the plan.
- **The provider returns `nil` until `ItemService.Start` runs.** A snapshot built during bootstrap
  carries no item, which is also the truth. No warn, deliberately — this runs every
  `Round.SnapshotInterval` and a warn would flood a Studio session.
- **`X` is the drop key**, bound for everyone. A bind that existed for only one role would be a role
  oracle in the keymap.
- **The mobile drop button does not exist yet.** `ActionHandlers.Drop` is declared and registered but
  `buildTouchPad` does not draw it, exactly as `Search`/`CancelSearch` are still undrawn. With ~60% of
  players on a phone and a one-slot rule that makes swapping items drop-then-pickup, this is a real
  gap rather than a rounding error. Recorded here and in the type's own comment.

---

## Review round 1 — 2026-08-29

Three reviewers ran. `auditor` **80/100**, `exploit-auditor` **83/100**, `playtester` still running.
Both auditors re-derived their evidence rather than trusting this log — the exploit-auditor ran the
real `pure/ItemThrow` under Lune inside a transcription of `resolveThrow`'s loop, and the auditor
recovered the deleted suites from git and re-ran them. **Four real defects came out of it, two of them
mine and shipped, and all four are fixed below.**

### FIXED — `Config.Items.DropForwardStuds` had no reader (exploit-auditor, High)

**The worst finding in the round, and a green invariant was asserting it was fine.** The drop is
supposed to place an item `DropForwardStuds` (6) in front of the dropper. `placeItem(item,
root.Position)` placed it at the dropper's own root + 1 stud of Y. Grep across `src/` returned exactly
two hits for `DropForwardStuds`, both prose: the Config declaration and a `Remotes.luau` comment
describing the behaviour. **Zero code readers.**

Meanwhile `tests/config.test.luau` asserts `DropForwardStuds >= DropPickupRangeStuds`, and its own
comment states the failure it exists to prevent: an item dropped inside the pickup radius is "instantly
re-taken". The invariant was green over a rule the code never applied — so the pickup radius is 6 and
the item was landing 1 stud away. Either `Touched` fires on the spawn overlap and the drop is instantly
undone (§4.6's "dropped, passed, and picked up from a body" unimplemented for the buntot pagi), or it
does not and the item is unpickupable until someone walks out of the radius and back in.

**Fix:** new `dropItemInFront`, used by the `RequestDropItem` handler only, offsetting by
`root.CFrame.LookVector * Config.Items.DropForwardStuds`. `spillItem` is unchanged and still lands at
the body — death and disconnect must land where the carrier fell, which is the §4.6 beat.

**No check in this repo could have caught this**, and that is the part worth keeping: `check:config`
proves a number is not hardcoded outside Config, never that anything reads it.

### FIXED — the throw's thrower-only gates were evaluated inside the candidate loop (exploit-auditor, Medium)

`ITEM_WRONG_PHASE`, `ITEM_THROWER_NOT_ALIVE` and `ITEM_NO_ITEM` depend only on the thrower, but were
produced only inside `for _, candidate in Players:GetPlayers()`, past a `continue` skipping the thrower
and anyone without a root part. With zero surviving iterations the function fell through to `MISS` —
which reaches the spend line. The auditor proved it by running the real module:

```
ENDING, salt, one candidate    -> ITEM_WRONG_PHASE
ENDING, salt, ZERO candidates  -> MISS        <- accepted, and the salt is SPENT
ACTIVE, salt, DEAD, zero cand. -> MISS
```

Narrow in a live 3–5 player round (the C15 redesign keeps a dead player's character attached, so they
still count as candidates); wide open in a solo session, which `Debug.SoloTesting` permits.

**Fix:** one pre-loop `ItemThrow.evaluate` with a **sentinel target** — the thrower's own position and
`TargetIsTransformedAswang = false`, which can only ever return a thrower-gate verdict or MISS, never
OK. That asks the pure module the thrower question using the pure module's own answers, so there is no
second predicate to drift, which is what the auditor explicitly warned against.

**Regression test, written as a property rather than a case per bug** (`green-after-each-patch-hides-a-loop`):
`tests/item-throw.test.luau` now asserts each thrower-only refusal is the SAME verdict across a
four-target domain **including the sentinel the service actually passes**. 81 -> 93 assertions.

### FIXED — the disconnect spill depended on an undocumented bootstrap order (exploit-auditor, Low)

`RoundService.onPlayerRemoving` sets `player.Character = nil` and reparents the body to
`workspace.Husks`; `spillItem` reads `player.Character` and returned **silently** when it was nil. It
works only because `init.server.luau` lists `ItemService` before `RoundService`, so its connection
fires first. Neither file said so. Reorder the list and every disconnect-while-carrying deletes the
item — including the only buntot pagi — with no error and nothing in `git status`.

Phase 3's log entry called this a decision. It was true by accident of list order.

**Fix:** the ordering is now documented in `init.server.luau` at the `"ItemService"` entry with the
consequence spelled out, and `spillItem` **warns** instead of returning silently — the buntot pagi's
last path out of the slot should not vanish quietly.

### FIXED — the `Touched` distance re-check comment overstated what it buys (exploit-auditor, Medium)

The re-check is real and does bound the exploit, but it measures the **character's** position, and
Roblox gives the client network ownership of its own character. An executor enumerates
`workspace.DroppedItems` (public, tagged, named by item type, colour-coded — all necessary so a player
can tell the win condition from a pouch), teleports to the buntot pagi, takes it, teleports back. There
is no remote on that path, so no token bucket applies and the pickup rate is unbounded.

Not new to V08 — `RequestSearch` has the same exposure — but V08 is the chunk that first puts the win
condition on the floor in a self-labelling part. **Not closed in this chunk.** The comment now says
plainly that the check narrows the attack rather than closing it, and names the two real mitigations
(a displacement sanity check against the last replicated position, or a rate-limited pickup remote).
Carried to Follow Ups rather than silently left.

### FIXED — two more stale `Config.Salt` comments (auditor, Low)

`MonsterService.luau:747` still said the glow colours "STAY UNDER `Config.Salt`" — the exact twin of
the comment I rewrote at `Config.luau:288` in Phase 2, missed. `UIController.luau:194` named
`Config.Salt` in its palette note (and named `Config.Monster` twice by mistake, predating V08). Both
rewritten. This is `green-after-each-patch-hides-a-loop`'s "one path fixed while its twin was not".

### ACKNOWLEDGED — the Phase 1 assertion table is stale (auditor, Low)

Phase 1's table says `item-throw` 78, which was true at the end of Phase 1; Phase 4 took it to 81 and
this round to 93. A reader checking Step 1.4's contract against that table alone would reach the wrong
number. A forward pointer has been added to the Phase 1 table.

### NOT A DEFECT — the debug values (exploit-auditor, filed High)

`Debug.SoloTesting`, `Debug.VerboseLogging` and the shortened round are the five values CLAUDE.md
prescribes setting for a playtester, and a playtester is running. `ForceAswangWhenSolo` is correctly
`false`, so there is no live role oracle. **The auditor was right to flag it and right that my Phase 5
"verify EXIT 0 / 49 files" claim does not hold for the tree as it stands** — that claim was true when
written and stopped being true when I set these. They revert when the playtester finishes.

`Round.Duration` was additionally raised 20 -> 150 mid-round: 20 seconds of ACTIVE against a 6-second
search hold is why the first playtester run could not land a search.

### Still open, carried to Follow Ups

- **`SearchService` sends `SEARCH_OK` with the item before `ItemService` can refuse it** (Low). The
  spill is correct; the premature confirmation is not. The searcher's client is briefly told it has an
  item the next snapshot says it does not. Fixing it properly reverses a V03 dependency and is not a
  V08 change.
- **The `Touched` pickup's client-owned-position exposure**, above.
- **Whether `Touched` fires at all** on an anchored, `CanCollide = false` part — still the one
  unverified Roblox behaviour, and now more sharply posed: with the forward offset fixed, the item no
  longer spawns overlapping the dropper, so a failure to fire is cleanly distinguishable from an
  instant re-take.

---

## Review round 2 — the playtester, and one defect no gate could see — 2026-08-29

`verification.md` is written and cites two artifacts that exist. **Both of the highest-value runtime
questions are answered**; the end-to-end chain is not, and that is stated rather than inferred.

### Established with artifacts

- **`Touched` FIRES on an anchored, `CanCollide = false` part** (`artifacts/touched-pickup-probe.txt`).
  This was the one genuinely unverified Roblox behaviour in the chunk and the whole pickup mechanism
  rested on it. The probe reproduced `placeItem`'s exact part shape, walked a character in with real
  navigation rather than teleporting into overlap, and recorded two hits — both resolving through
  `FindFirstAncestorOfClass("Model")`, the identical lookup the production handler uses. Isolating the
  ENGINE question instead of driving the full chain is what made it answerable.
- **`RequestDropItem` arrives with 0 arguments**, and X does not cross-fire `RequestThrowSalt` or
  `RequestSearch` — 3 events for 3 presses, in press order, probe disconnected and confirmed at
  `finalCount:3` (`artifacts/remote-probe-log.txt`). The negative assertion is the half that matters.

### Not established, and recorded as such

Search → slot → HUD with a real item; drop → floor → walk-back pickup end to end; the full-handed
spill (Q3); the salt hit's five jobs on a live transformed Aswang (Q5). Every link is verified
separately — 178 Lune assertions over the four pure modules, the remotes by probe, `Touched` by
experiment — but **the chain has never run start to finish.** Three Play sessions dropped to Edit mode
unprompted, which is an environmental constraint rather than a code fault.

### FIXED — the HUD taught a mechanic V08 deleted (playtester, found outside the brief)

`UIController.promptFor` still read `"survive until sunrise · Q throw salt · walk over a pouch to take
it"` on both the desktop and touch branches. **"Walk over a pouch to take it" is C13's `pickupTick`**,
which V08 deleted with the second salt economy. The prompt named a verb the game no longer has and
omitted the one it is now built around, and it is the only instruction in the game for those verbs.

**This is worse than any stale comment in this chunk.** A comment misleads a reader; this misled a
PLAYER, on screen, every round. And nothing could catch it: it is a string, so `analyze`, `lint` and
all five checks pass straight over it, and Phase 5's diff never touched this function so no phase gate
looked at it. It took someone reading the HUD.

Now `"survive until sunrise · E search · Q throw salt · X drop"` (and a touch variant), search first
because §4.4 makes it the activity the round is built on and the only way to obtain anything.

### The pattern worth carrying forward

The playtester stopped **three times** across ~500k tokens. What failed every time was driving
gameplay STATE — completing a search to get an item into a hand. What worked, immediately, was the
isolated probe: attach a listener, or build the part shape and ask the engine one question.
`.claude/lessons/prove-input-at-the-remote-not-the-outcome.md` covers inputs; it does not cover
state-dependent chains, and this run is the second time that gap has cost a session. Candidate for
`/lessons-review`.

**Final gate:** `npm run verify` **EXIT 0** — analyze · lint 0/0 · fmt · remotes 32/32 · secrecy ·
config · scope · ratelimit · **debug ok (all five values reverted)** · **test:unit 49/49**.
