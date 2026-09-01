# V10 — Buntot pagi: the only kill — implementation log

## Phase 1: The contract — the range, the invariants, the verdict union, and the verb — 2026-09-01

**Steps completed:** 1.1, 1.2, 1.3, 1.4, 1.5

**Files changed:** `src/shared/Config.luau`, `tests/config.test.luau`, `src/shared/Types.luau`,
`src/shared/pure/ItemUse.luau`, `tests/item-use.test.luau`

**Deviations from plan:**

- **Step 1.2 uses the file's `check(label, ok, detail)` helper, not the raw `assert(cond, msg)` the
  plan's diff showed.** `tests/config.test.luau:17` defines `check` and every one of its 129
  invariants goes through it, because it is what increments the count the closing `PASS` line
  prints. A raw `assert` would have passed silently and understated the count — the same class of
  quiet failure the suite exists to catch. The plan's own reference review anticipated this
  ("match whatever helper the file already uses at that point").
- **Step 1.2 also names `Monster.KillRange` as a four-way anchor** in the new comment, rather than
  adding a separate comment at the `Config.luau` site as `config.test-review.luau` suggested. One
  statement of the fact, in the file that enforces it, beats two that can drift apart.
- **Step 1.3 rewrote `ItemUseVerdict`'s header**, which the plan's diff did not mention. The
  existing paragraph described `USE_NOT_IMPLEMENTED` as "the V09/V10 boundary ... deliberately a
  value rather than a gap" — prose that becomes a lie the moment the value is deleted. It now
  records the boundary closing and states the routing property that replaced it.
- **Step 1.5 strengthened "salt and bawang have different verbs" into all three pairwise checks.**
  The plan asked only that the exhaustiveness loop assert a real verb for every item (it already
  did). But deleting `USE_NOT_IMPLEMENTED` removed the union's ability to express a verb collision:
  while it existed, an item that lost its verb collapsed to a value nothing else returned. Now every
  value is a real verb, so two items answering identically routes two mechanics to one remote and
  typechecks perfectly. Three checks, one per pair.
- **`tests/item-use.test.luau`'s exhaustiveness comment was corrected on a point of fact.** It said a
  fourth item type would "silently inherit `USE_NOT_IMPLEMENTED`". `verbFor`'s if-chain has no
  BUNTOT_PAGI branch — it falls through to `return "USE_STRIKE"` — so a fourth item now inherits the
  STRIKE verb, routes to `RequestStrike`, and is refused server-side at `STRIKE_NOT_HELD`, which
  looks exactly like a mechanic nobody built yet. Sharper trap than before; the comment says so.

**Gate:** `check:config` PASS · `lune run tests/config.test.luau` PASS (129 invariants, was 127) ·
`lune run tests/item-use.test.luau` PASS (12 assertions, was 10) · `npm run verify:fast` PASS
(analyze ok, remotes 34/34, secrecy ok)

**Known-red, expected:** `tests/anti-cheat-budgets.test.luau` fails with "the budget for
RequestStrike names a remote that exists". Step 1.1 lands the budget; Step 2.3 lands the
declaration. The plan calls this window out in Phase 1's issues — the suite asserts in both
directions, so budget-without-remote and remote-without-budget both fail, and they cannot land in
the same step without splitting the Config commit. `npm run verify` is therefore not green until the
remote is declared.

**Notes for the auditor and playtester:**

- Nothing in this phase is reachable from the game. No remote, no handler, no client path.
- `grep -r USE_NOT_IMPLEMENTED src/ tests/` returns only prose in comments; there were no code
  readers besides the `return` itself, which is what Step 1.4's `verify:fast` was there to prove.
- `ItemService`'s throw handler still compares `verbFor(...) == "USE_THROW"` positively and was not
  touched. That comparison is the thing standing between a mis-pressed throw key and the destruction
  of the round's only win condition; it survives this phase unchanged and by design.

---

## Phase 2: The decision — `pure/StrikeValidation` and the grid that proves it — 2026-09-01

**Steps completed:** 2.1, 2.2, 2.3

**Files changed:** `src/shared/pure/StrikeValidation.luau` (new),
`tests/strike-validation.test.luau` (new), `src/shared/Remotes.luau`

**Deviations from plan:**

- **The test uses the repo's `check(label, ok, detail)` + `failures` counter, not bare `assert`.**
  The plan's diff used `assert`, which aborts on the first mismatch. Over a 46,080-cell product that
  reports one bad cell and hides the shape of the failure; `tests/kill-validation.test.luau` — the
  suite this one is modelled on — uses `check` for exactly that reason and errors once at the end.
- **Added `check("the grid reaches STRIKE_KILL somewhere", kills > 0)`.** Not in the plan. Every
  other assertion in the product is satisfied by a module that returns `STRIKE_NO_EFFECT`
  unconditionally *if `expected` shares the misreading* — and `expected` is a hand-written second
  statement of the same rule, so a shared misreading is the one failure the duplication cannot
  catch. This is the cheap guard against §6.5 invariant 1's silent failure. It reports 15 kill cells
  (3 in-reach distances × 5 non-nil monster states), which is the arithmetic the rule predicts.
- **Added the indistinguishability property and the spend-line assertions as named checks** at the
  end of the file. The plan schedules the indistinguishability property as Step 4.2, so this is
  partly Phase 4 work arriving early — see the note below. What landed here is the *five-worlds*
  comparison (nobody in reach / out of reach / a survivor / not Exposed / not Weakened all returning
  one value) plus the converse: that the three striker-side verdicts DO differ, because
  `ItemService` reads them by name to decide not to spend and three worlds sharing one value would
  burn the round's only buntot pagi on a lobby keypress. **Step 4.2 still landed in full in Phase 4**
  (`tests/strike-validation.test.luau:350-389`): what arrived early here is a different, smaller
  mechanism — five hand-picked worlds — and Step 4.2's own exhaustive cardinality loop is separate.
  The file signposts the relationship at line 342.

  > **CORRECTED after the plan audit.** This note originally said Step 4.2 "asks for the property
  > stated against the wired server path, not the pure module". That is wrong: Step 4.2's plan text
  > is explicitly about the PURE MODULE's cardinality property, and it landed as written. The true
  > gap — indistinguishability *at the service, to a second observer* — is real but belongs to
  > `exploit-auditor` and the playtester, not to Step 4.2. It is stated correctly in
  > "What is NOT proven" below.

**Gate:** `npm run analyze` PASS · `lune run tests/strike-validation.test.luau` PASS (46,111 checks:
46,080 grid cells + 15 kill assertions + 16 named properties) · `npm run check:remotes` PASS
(35 declared, 34 wired — `RequestStrike` declared but not yet wired, which is Step 3.3) ·
`npm run fmt:check` PASS · `npm run verify:fast` PASS

**Cell count sanity check:** 5 × 4 × 4 × 6 × 6 × 4 × 2 × 2 = 46,080, matching the plan's arithmetic
exactly. This is the number the plan asked to be checked — a count of 30,720 would have meant one of
the three axes with a leading `nil` (`HELD`, `MONSTER_STATES`, `DISTANCES`) had silently lost it to
`#`. It did not; the explicit `HELD_N, MONSTER_N, DIST_N` counts are why.

**Known-red, expected:** `tests/anti-cheat-budgets.test.luau` still fails on "the budget for
RequestStrike names a remote that exists". Confirmed the cause is `UP_REMOTES`, a hand-maintained
list *inside the test file* mirroring `Remotes.luau`'s `EVENTS_UP` — declaring the remote does not
clear it. Step 3.4 owns that list, so the window closes there exactly as the plan says. It was not
pulled forward.

**Notes for the auditor and playtester:**

- `StrikeValidation` has no seed, no `os.time()`, no `Random`, and no field a client supplies: both
  booleans come off `MonsterService`'s server-only table, the distance is measured between the
  server's copies of two characters, `Phase` is `RoundService.GetPhase()` and `Held` is the server's
  own slot. `src/shared/pure/` is the right home on CLAUDE.md's inputs-and-seeds test.
- The module has **no health number and no role field**. `Exposed AND Weakened` implies the role
  rather than asking about it, since only the Aswang can be either — which is a genuine improvement
  on `pure/KillValidation`, whose header has to warn that `TARGET_IS_ASWANG` is a role oracle in one
  word.
- The `TargetState == nil` branch is redundant against the two booleans and is kept deliberately: the
  field exists so the Done line's grid is literal, and a field the function never reads is a field
  the analyzer cannot tell from a mistake.

---

## Phase 3: The server — one resolver, one kill path, one handler that spends — 2026-09-01

**Steps completed:** 3.1, 3.2, 3.3, 3.4

**Files changed:** `src/server/Services/MonsterService.luau`,
`src/server/Services/ItemService.luau`, `tests/anti-cheat-budgets.test.luau`

**Deviations from plan — the first one is a correctness fix, not a preference:**

- **`StrikeDown`'s teardown order is `ApplySaltHit`'s, NOT the plan's.** The plan specified
  `endFeed → exitCamouflage → revert → clearExposed`. That is wrong and would have shipped a visible
  bug. `endFeed` calls `revert(player)` itself (`MonsterService.luau:2162`), and `revert` restores
  from `OriginalParts`, which `applyCamouflageLook` overwrites on top of. So ending the feed while
  the disguise is still on runs a revert against a character in a state none of `revert`'s comments
  were written about — `ApplySaltHit`'s header names the outcome exactly: "a player-shaped nothing
  wearing a cat". A monster struck mid-feed while camouflaged would have died wearing a broken
  character, in the open, as a permanent artifact. The landed order is
  `exitCamouflage → endFeed → revert → clearExposed`, which is the order `ApplySaltHit` already had
  to discover for the identical reason.
- **`endFeed` takes the literal `"FEED_INTERRUPTED"`, not `Enums.FeedVerdict.Interrupted`.** The plan
  flagged this for confirmation and asked that it be checked against the existing callers rather
  than against the diff. There is no `FeedVerdict` table in `Enums.luau` at all — only a
  `Types.FeedVerdict` type declaration (`Types.luau:764`). The plan said "six existing callers"; there
  are in fact **nine** call sites before V10 (several are branches within one function), and all nine
  pass the bare string or `nil`. Confirmed `nil` is used only by `feedTick`'s completion paths, so the
  interrupted verdict is correct here — a struck feeder did not complete a feed.
- **`ResolveStrikeTarget` returns the monster state as a third value.** The plan left this as an
  explicit choice between that and a public `GetMonsterState` wrapper, and asked which be recorded.
  Chose the third return value: `monsterStateOf` is a file-local, and a public seam answering for any
  UserId would be a fifth entry on the header's list of four non-enumerating seams — a probe, where
  this answers only about the candidate the function itself resolved. Two new seams for V10, not
  three.
- **`ResolveStrikeTarget` also reads `monsters[aswangUserId]` and returns nil if absent.** Needed to
  produce the state without calling `stateFor`, which would re-insert a departed player's UserId —
  the bug `revert()` and `applyHealthEvent` both open by avoiding. It also tightens the resolver: a
  round whose Aswang has no monster state resolves nobody.
- **The handler's three unpacked locals carry explicit type annotations.** Not in the plan, and the
  analyzer rejected the code without them. `.claude/lessons/pure-module-unions-widen-in-lists.md`
  records that a literal union survives `require` as a scalar but not inside a list — **a
  multi-return is a list**. `Types.MonsterState?` widened to
  `(string | string | string | string | string)?` across the unpacking, and
  `StrikeValidation.evaluate` then rejected the entire request table with an error naming the field
  but not the cause. Worth noting as a new instance of a known lesson.
- **`check("the strike budget covers a double-press", ...)` uses the suite's `check` helper**, same
  reasoning as Phase 1's Step 1.2 deviation.

**Gate:** `npm run analyze` PASS · `npm run check:secrecy` PASS · `npm run check:ratelimit` PASS
(every OnServerEvent consults AntiCheat) · `lune run tests/anti-cheat-budgets.test.luau` PASS (18
remotes budgeted, 81 assertions) · **`npm run verify` PASS, exit 0** — remotes 35 declared / 35
wired, scope ok, config ok, debug ok, test:unit 58 files ok. The red window opened at Step 1.1 is
closed.

**Notes for the auditor and playtester — three things V10 ships knowingly:**

1. **A successful kill ends the round as `RoundResult.Aborted`.** `RoundService.MarkKilled` routes
   any Aswang death through `enterEnding(Enums.RoundResult.Aborted)` (`RoundService.luau:934`), on
   the disconnect path's reasoning. That is the wrong result for a strike — the survivors did not
   abort, they won the second win condition — and **V11 owns replacing it**, together with §6.5's six
   invariants and the roster freeze. A playtester will see "Round aborted" on the end screen after a
   successful kill. **That is the expected output of this chunk, not a bug to file.**
2. **`RoundService.luau:926`'s comment is now stale.** It reads "A kill can never reach this branch —
   `TARGET_IS_ASWANG` refuses it". True of `RequestKill`; false as of this chunk, because
   `StrikeDown` reaches `MarkKilled` for the Aswang by design. Step 4.3 hands this to V11.
3. **The Aswang can strike itself, and that is deliberate**, argued in `ResolveStrikeTarget`'s
   header. It resolves to itself at distance 0 with trivial line of sight, and the pure module then
   answers on its own Exposed/Weakened state. A guard would make the monster's buntot pagi behave
   differently from everyone else's — a role oracle readable by pressing a key. **Flag to
   `exploit-auditor` as a decision, not an oversight.**

**Secrecy checks done by reading the landed code, as Phase 3's issues list asked:**

- No `Debug.VerboseLogging` line prints `targetUserId`. Both log lines carry the striker's own UserId
  and a verdict, and the verdict below the spend line is one of two values neither of which names a
  world.
- `StrikeDown` calls `clearExposed(userId)` before `MarkKilled`, so no Highlight is orphaned onto a
  body. This is C04's bug shape and the reason the ordering is written out in the header.
- `ResolveStrikeTarget`'s return value crosses no wire. It is consumed by `IsExposed`/`IsWeakened`,
  by the pure module (which has no role field), and by `StrikeDown`.
- Nothing is returned to the caller on any path, including `STRIKE_KILL`.

---

## Phase 4: The client's request, the indistinguishability property, and the gate — 2026-09-01

**Steps completed:** 4.1, 4.2, 4.3

**Files changed:** `src/client/Controllers/InputController.luau`,
`tests/strike-validation.test.luau`, `docs/BUILD-PLAN.md`

**Deviations from plan:**

- **Step 4.2's property uses `check`, not `assert`,** and folds into the suite's `checked` count as
  the plan asked. Also placed after the named five-worlds check written in Phase 2 — the two are the
  readable and the exhaustive statements of one property, and both are kept: the named one names the
  worlds, this one proves no fifth exists.
- **Step 4.3 did not "tick V10's Done line".** `docs/BUILD-PLAN.md` has no completion-marking
  convention — V01–V09 are all shipped and none carries a tick — so inventing one for V10 would be a
  format nobody else follows. The two substantive edits landed instead:
  - **V10's signature line was CORRECTED**, which is the architect's Follow Up 1 and the most
    important documentation change in this chunk. It read `(monsterState, monsterHealth, distance,
    phase) → verdict`; that signature cannot be implemented, and building it literally ships a buntot
    pagi that never kills. The note explains why, so the next reader does not "fix" the module back.
  - **V11's entry gained the handoff**, including the stale-comment warning.
- **`ItemUse.verbFor(carriedItem)` is now called twice in the if-chain** and was not hoisted. The
  plan allowed either; leaving both calls positive and inline keeps the two branches reading
  identically, which is what makes the routing rule legible.

**Gate:** `npm run analyze` PASS · `lune run tests/strike-validation.test.luau` PASS (46,112
checks) · **`npm run verify` PASS, exit 0** · `npm run verify:plan` — **15 passed, 0 failed, 0
unverifiable; 15 discriminating checks, 0 file-exists, 0 self-satisfying.**

**Confirmed by reading, as Phase 4's issues list asked:**

- `UIController` renders `"   buntot pagi"` for the carried item and nothing else — no strike
  outcome, no toast, no failure indicator. A "your strike failed" message would be the exact oracle
  this plan is shaped to prevent, through the one surface `check:secrecy` cannot see. There is none.
- The client branch sends no argument and receives no reply.
- No new key, no seventh mobile button, no new `ContextActionService` binding. `Q` was chosen over
  `F` because `KILL_ACTION` is bound unconditionally for every player so the bind itself is not a
  tell, and a second role-shaped meaning on it would break that.

---

## Plan steps NOT implemented

None. All 15 steps across 4 phases landed, and `npm run verify:plan` grades all 15 checks as
discriminating (none file-exists, none self-satisfying).

## What is NOT proven by any of the above

- **That a kill works end to end in a running game.** Every gate here is static or Lune-level. The
  playtester's artifact is the only evidence for V10's second Verify clause ("playtester records one
  successful kill end to end"), and it has not run yet.
- **That a refused strike is indistinguishable to a SECOND observer.** That is a claim about what
  another client can see, and `tests/strike-validation.test.luau` proves it only at the module.
  `exploit-auditor` is what proves it at the service. A screenshot of a failed swing does not
  substitute for either.
- **That the round scores correctly after a kill.** It does not — see Phase 3's note 1. `ABORTED` is
  the expected, knowingly-shipped output of this chunk and V11 owns it.

---

## Note on a red `tests/config.test.luau` during the review window — 2026-09-01

`npm run verify:plan` currently reports **13 passed, 2 failed**, and both failures are Step 1.2 and
Step 4.3 failing on the SAME check: `lune run tests/config.test.luau`.

**Neither is a V10 defect.** The suite fails exactly two of its 129 invariants:

- `solo testing is off — this must never be true on a published place`
- `a round is long enough to actually be played — Duration=90s`

Both are caused by the playtest debug values set in `src/shared/Config.luau` for the `playtester`
agent (`Round.Intermission=15`, `Round.Duration=90`, `Round.EndScreen=6`, `Debug.SoloTesting=true`,
`Debug.VerboseLogging=true`, `Items.SaltDamage=75`). CLAUDE.md requires these be set by the main
thread before launching a playtester, because the agent cannot edit Config itself.

**Step 1.2's own two invariants PASS.** Neither "the strike reaches no further than the monster's own
kill range" nor "the strike range is a positive finite number" appears in the failure list, and the
suite ran green at **129 invariants** (up from 127) immediately after Step 1.2 landed and before any
debug value was touched. The check is collateral, not a verdict on the step.

**Why the revert is being held rather than done immediately.** `Debug.SoloTesting` is what forces the
lowest UserId to be the Aswang, and `Items.SaltDamage = 75` is what makes one salt throw both reveal
and weaken the monster — together they are the only reason a solo Studio session can reach a live
strike at all. Reverting mid-run would waste the one agent able to produce V10's second Verify
clause ("playtester records one successful kill end to end"). All six values are reverted once it
reports, and `guard-commit.mjs` runs `check:debug` and refuses to commit any of them, so they cannot
reach history either way.

---

## Review findings and disposition — 2026-09-01

`auditor` scored **80/100**, `exploit-auditor` **85/100**. Neither found a secrecy leak. The
exploit-auditor ran its own nine-world probe through `pure/StrikeValidation` under Lune (rather than
quoting `tests/strike-validation.test.luau`) and confirmed the four target-side worlds are one
verdict with no recovery channel; it also enumerated every replicated property `MonsterService`
writes onto an Aswang's character against a restorer reached by `StrikeDown`'s teardown, and found
**no C04-shaped residue**. Both independently confirmed the teardown reorder was necessary rather
than a preference.

### F1 — the spend sits in the middle of the asymmetric region, not above it (Low) — TO FIX

`ItemService`'s handler resolves the target *before* it spends. The raycast, `IsExposed`,
`IsWeakened`, `GetPlayerByUserId` and `GetPlayerState` all execute only on the branch where the
Aswang is in range with line of sight. An uncaught error at any of them aborts the coroutine ABOVE
`slot[player.UserId] = nil`, and **the item survives the swing** — the reusable-detector shape the
spend line exists to close, arriving through the error path instead of a conditional.

The auditor found no reachable error there today and scored it Low for that reason. It becomes real
the day anything fallible is added to `ResolveStrikeTarget`.

**Fix, and it needs no new module entry point:** call `StrikeValidation.evaluate` TWICE. The first
call passes no target data at all — which answers exactly the three striker-side questions, because
the module's fixed order checks phase, aliveness and hand before it looks at anything else. Return
without spending on those three; otherwise spend, THEN resolve the target and evaluate fully. The
spend then sits above the entire asymmetric region, and a non-holder's keypress stops costing a
raycast. One module, one rule, called twice — no second entry point to diverge.

**Held until the playtester reports.** Rojo live-syncs `src/`, so editing `ItemService.luau` under a
running Studio session would swap the server script mid-round and likely waste the run. This changes
no observable behaviour on any non-error path, so the playtester's evidence stays valid across it.

### F2 — the Aswang can destroy the round's only win condition with one keypress (Medium) — RAISED, NOT FIXED

`BuntotPagiSpawnCount = 1`, the item does not respawn, and the spend is unconditional. An Aswang who
picks it up and presses `Q` anywhere removes the second win condition for the rest of the round, and
nobody can tell: the cue is a generic `ITEM_USE`, indistinguishable from a salt throw.

Spec §4.6 sanctions *denial* — line 320: "Denying survivors the buntot pagi becomes a real strategy
that looks exactly like survival." V10 upgrades denial into **destruction**, which is strictly
stronger and cannot be undone by killing the carrier.

**This is a spec conflict and CLAUDE.md says the spec wins and the conflict gets raised, not quietly
resolved.** §4.6 says "It breaks on use" in as many words. The auditor's proposed shape — spend as a
DROP rather than a destroy, item lands at the striker's feet on every swing hit or miss — preserves
the secrecy property exactly (`YourCarriedItem` goes nil identically in both worlds, a part appears
identically in both) while keeping the win condition alive. **It is a spec change and has been put
to the user rather than applied.**

Worth noting against §12's risk row: this is a plausible way for the second win condition to read as
unreachable at V16 for a reason that has nothing to do with the health arithmetic.

### F3 — "there is no path where a swing is silent" is false as written (Low) — TO FIX (comments only)

Two paths produce a spent, silent swing, and I verified both:

- `NoiseService.Emit` throttles per actor per action. `Config.Interest.ITEM_USE.MinInterval = 2`
  (`Config.luau:362`), and `shouldRecord` returns before emitting (`NoiseService.luau:234-241`). A
  player who used an item under two seconds ago and then swings emits nothing.
- The emit is guarded on the striker having a `HumanoidRootPart`. A striker mid-respawn who is still
  `ALIVE` in `PlayerStates` spends the item and makes no sound.

**No leak** — both depend only on the striker's own recent history and own body, never on whether a
target was resolved, so a silent swing is uninformative about anyone else. But the claim as written
in `Remotes.luau`'s `RequestStrike` header ("on every swing that reaches the spend line, hit or
miss") is wrong and must not be carried forward as a proven invariant. The true and sufficient
property is **"a hit and a miss are acoustically identical"**. Correct the comment, change no code.

### F4 — `verify` red on debug values (informational)

Both auditors independently reproduced it and both correctly attributed it to the playtest values.
Reverted once the playtester reports.

### Flagged, not mine, not chased

`exitCamouflage` resolves the `Humanoid` for `showCharacter` from `monster.AppliedTo or
player.Character`. If those ever diverge, `DisplayDistanceType` is restored on the wrong humanoid and
one player's nameplate stays hidden — a permanent, map-wide difference. **V07 code with four
pre-existing callers; `StrikeDown` is the fifth and does nothing new.** The auditor could not
construct the divergence from reading and flagged it rather than asserting it unreachable. Recorded
here so it is not lost.

---

## Debug-value ledger — MUST ALL BE REVERTED — 2026-09-01

Eight values in `src/shared/Config.luau` are set for playtesting and are **not** V10 work. Recorded
here because the count grew across five playtester attempts and a missed revert is exactly the kind
of thing that ships. `guard-commit.mjs` runs `check:debug` and refuses to commit the switches, but it
does **not** guard the five numeric values below.

| Value | Committed | Session | Why |
| --- | --- | --- | --- |
| `Round.Intermission` | 25 | 15 | shorter cycle |
| `Round.Duration` | 300 | 90 | shorter cycle |
| `Round.EndScreen` | 12 | 6 | shorter cycle |
| `Debug.SoloTesting` | false | true | solo Studio session |
| `Debug.VerboseLogging` | false | true | console evidence |
| `Debug.ForceAswangWhenSolo` | false | true | **see below** |
| `Items.SaltDamage` | 25 | 75 | one hit reveals AND weakens |
| `Items.SaltSpawnCount` | 4 | 2 | keeps §6.5 invariant 1 exact at SaltDamage=75 |
| `Items.GarlicSpawnCount` | 2 | 1 | makes room under the container-gamble pin |
| `Items.BuntotPagiSpawnCount` | 1 | 4 | **see below** |

Revert command for the numerics is a plain re-edit; confirm afterwards with
`git diff src/shared/Config.luau` showing ONLY the V10 additions
(`BuntotPagiStrikeRangeStuds`, the `RequestStrike` budget) and no value changes.

### Two blockers found by playtesting, both real and both worth keeping

**1. `ForceAswangWhenSolo = false` means a solo round draws ZERO Aswangs, deterministically.**
Found by a playtester and verified independently: `RoleDraw.luau:108` computes
`math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))`, which is `clamp(1, 0, 0) = 0` with one
candidate — the "never draw every candidate as the Aswang" rule, correct and load-bearing in
production. `RoleService.luau:178-184` overrides it only when
`IsStudio() and SoloTesting and ForceAswangWhenSolo and #candidates <= MinPlayers`. **Not a shipped
defect** — outside Studio `#candidates >= MinPlayers` so the branch cannot occur. It is a
solo-verification gap, and it cost three stalled passes before anyone read the draw.

**This is worth writing into `.claude/agents/playtester.md`** alongside the two traps already
documented there: `SoloTesting` alone is NOT sufficient to be the Aswang, and the confirming signal
is the `[RoleService] DEBUG — Aswang FORCED to ...` warn line, whose *absence* is diagnostic.

**2. One buntot pagi in fifteen containers is not findable in an agent session.** Four passes burned
out searching. Raising `BuntotPagiSpawnCount` for a test session is the shape change; the three
counts are interlocked through `tests/config.test.luau`'s container-gamble pin
(`ContainerCount >= totalItems * 2`) and §6.5 invariant 1, so they must move together. The
combination above (2 / 1 / 4) satisfies both.

### A process note worth keeping

Five playtester passes, roughly 590k subagent tokens, produced one `verification.md` with Q1 answered
as *blocked* and an empty `artifacts/`. Four of the five returned a mid-work sentence as their
result while having written either real work or nothing at all — `.claude/lessons/
a-finished-agent-may-have-finished-nothing.md` exactly. The instruction that finally mattered was
**"write to `verification.md` after EACH question, not at the end"**; batching the report is what
made four passes worth nothing on disk.

---

## Debug values REVERTED · final gate — 2026-09-01

All ten reverted. `git diff --stat src/shared/Config.luau` is **44 insertions, 0 deletions** — purely
the V10 additions (`BuntotPagiStrikeRangeStuds`, the `RequestStrike` budget and their comments), with
no value changes of any kind.

**Final gate:** `npm run verify` **exit 0** — analyze ok · remotes 35/35 · secrecy ok · config ok ·
scope ok · ratelimit ok · debug ok · testcount ok · test:unit **58/58 files ok**.
`npm run verify:plan` — **15 passed, 0 failed, 0 unverifiable; 15 discriminating checks.**

## Runtime verification: NOT ACHIEVED. Stated plainly.

**Five playtester passes, roughly 725k subagent tokens, produced no runtime evidence.** `artifacts/`
is empty. `verification.md` records Q1 as blocked and Q2/Q3/Q4 as not established. I am recording
this as a failure of the verification attempt rather than dressing it up, and V10's own Verify line
— "playtester records one successful kill end to end" — is therefore **unmet**.

Two real blockers were found and removed along the way (the zero-Aswang solo draw, and one buntot
pagi in fifteen containers), and passes four and five still stalled after both were gone. The
remaining cause is context exhaustion: each Studio MCP round trip is expensive, and driving a full
round to a staged kill does not fit in one agent's budget. Four of five passes returned a mid-work
sentence as their result.

**What IS proven, and by what:**

| Claim | Evidence | Strength |
| --- | --- | --- |
| The two-condition rule is correct over its whole domain | `tests/strike-validation.test.luau`, 46,112 checks incl. a 46,080-cell product | Strong — exhaustive over a bounded domain |
| The four refusal worlds are one verdict with no recovery channel | `exploit-auditor` executed its OWN nine-world probe under Lune, not this repo's suite | Strong — independent re-execution |
| No C04-shaped residue survives onto the struck body | every replicated property `MonsterService` writes traced to a restorer reached by `StrikeDown` | Strong for reading; not observed rendering |
| The spend cannot be skipped below the spend line | read of every statement below it; no yields in the whole call chain | Strong |
| `Q` fires `RequestStrike` when the buntot pagi is held, `RequestThrowSalt` otherwise | a playtester's wire-level probe (pass 4) | **Moderate — asserted in a stopped agent's message, never written to `verification.md`. Treat as unconfirmed.** |
| A kill works end to end in a running game | none | **UNPROVEN** |
| A refused strike is indistinguishable to a SECOND observer | structural only (no per-player branching, one cue, one audience) | **Not observed — needs two clients** |

**Recommended next step, and it is not another agent pass.** This needs a human at a keyboard, which
V16 requires anyway. The setup is now known and cheap to reproduce — set the ten values in the ledger
above (especially `ForceAswangWhenSolo = true` and `BuntotPagiSpawnCount = 4`), press Play, search a
few containers, and answer Q3 first: **swing with nothing in reach and confirm the item still
disappears.** That single observation is the one this chunk most needs and the one no static check
can supply.

## Follow-ups for other chunks

1. **`.claude/agents/playtester.md` should gain a third documented trap:** `Debug.SoloTesting` alone
   does NOT make you the Aswang — `ForceAswangWhenSolo` is required, and the confirming signal is the
   `[RoleService] DEBUG — Aswang FORCED to ...` warn line, whose absence is diagnostic. This cost
   three passes.
2. **F1 (spend below the asymmetric region) and F3 (the over-claiming noise comment) are NOT applied**
   — see the findings section above. Both are small, both are held pending the F2 decision so the
   handler is opened once rather than twice.
3. **F2 (the Aswang can destroy the win condition with one keypress) is with the user as a spec
   conflict** and is unresolved. The code today is the spec-faithful reading.
