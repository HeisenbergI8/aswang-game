# Plan: V02 — The v2 vocabulary (Enums, Types, Config)

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** chunk **V02** in `docs/BUILD-PLAN.md` (Track V1; deps: V01)
- **Description:** Add the words the rest of Track V1 needs — four literal-union enums, a carry slot on
  the client contract, and spec §6.5's v2 Config block with a comment on every number. **No behaviour.**
  Three files change: `src/shared/Types.luau`, `src/shared/Enums.luau`, `src/shared/Config.luau`.
- **Date:** 2026-08-27
- **What the client is told:** exactly one new thing — `ClientRoundSnapshot.YourCarriedItem: ItemType?`,
  an optional saying what the **receiving** player is carrying. Nothing else crosses. No alive count, no
  role field, no roster, no other player's carry. `RoundSnapshot` is `FireClient` per player
  (`RoundService.luau:639`), which is what makes the slot safe; see §Q4 below and the
  `RoundService-review.luau` reference. V02 adds no producer for the field, so no service changes.

---

## Preamble — read this before Phase 1, and it applies to every phase

### How to read `npm run verify` at each gate

**Measured on a clean tree on 2026-08-27, before any V02 edit:**

| Command | State today | After V02 |
| --- | --- | --- |
| `npm run analyze` | green | **must stay green** — this is V02's Done criterion |
| `npm run lint` | green | must stay green |
| `npm run check:scope` | green (19 shapes watched) | must stay green |
| `npm run check:secrecy` | green | must stay green |
| `npm run check:config` | green | must stay green |
| `lune run tests/config.test.luau` | **PASS — 82 balance invariants** | **still expected to PASS** |

**`docs/BUILD-PLAN.md:191-192` predicts `tests/config.test.luau` will go RED after V02.** Under the
design in this plan **it does not**, and that is deliberate rather than an oversight. The build plan's
prediction assumes V02 hard-renames `Config.Salt.*` to §6.5's `Config.Items.Salt*` names. That rename
also turns **`npm run analyze` red**, because five live modules read `Config.Salt.*`
(`ItemService`, `TrialService`, `UIController`, `InputController`, `shared/pure/SaltCarry`) — and a
missing Config key is a hard analyzer error, not a warning. Measured directly:

```
t.luau(3,19): TypeError: Key 'SpawnCount' not found in table '{| CarryLimit: number |}'
```

A red `analyze` contradicts V02's own **Done** line ("analyze clean"), so this plan takes the other
branch: `Config.Items` is added complete and canonical, and `Config.Salt`'s four renamed keys become
**aliases into it** (Step 3.4). One number, one home, zero call-site edits, `analyze` green.

**Consequences for the implementer, stated so nobody chases the wrong thing:**

1. **Do not edit `tests/config.test.luau`.** V11 owns it and writes §6.5's six invariants there. If it
   goes red during V02, you broke something — investigate, do not "fix" the test.
2. **No `**Verify:**` line in this plan runs `npm run test:unit` or `lune run tests/config.test.luau`.**
   That is on purpose. The gates here are `analyze`, `lint`, the four repo checks, and symbol-specific
   greps.
3. `npm run verify` at the end of Phase 3 should be **fully green**. If it is not, the failure is real.

### The one arithmetic fact V11 will need, and V02 must not break

At §6.5's shipped values, invariant 1 holds **with exactly zero margin**:

```
SaltDamage × (SaltSpawnCount − 1)  ≥  MaxHealth − WeakenedThreshold
        25 × (          4 − 1)     ≥        100 −              25
                        75         ≥        75            ✓ (equality)
```

Survivors can weaken the Aswang **only if every pouch but one connects**. Tighten `SaltDamage` or
`SaltSpawnCount`, or raise `MaxHealth` or lower `WeakenedThreshold`, and the second win condition
becomes unreachable **silently** — nothing in the game says so. Every one of those four numbers carries
a comment about this in Phase 3. The other five invariants all hold with slack (checked in §4).

### Naming conventions this plan obeys

- **`Types.luau` fields are PascalCase.** The carry slot is `YourCarriedItem`, not `carriedItem` — the
  `Your*` prefix is this file's existing convention for "about the receiver only" (`YourRole`,
  `YourState`).
- **Every enum value carries its `:: Types.X` cast.** Without it a literal infers as plain `string` and
  fails to satisfy a parameter typed as the literal union. Six of the scaffold's seven original analyze
  errors were exactly this. Match `Enums.luau`'s existing `table.freeze({ ... })` shape.
- **RGB is a `{ r, g, b }` triple, never `Color3`.** `tests/config.test.luau` requires `Config.luau`
  under Lune, which has no Roblox datatypes. V02 adds no colours, but do not add one.
- Tabs, `--!strict`, double quotes, 100 columns, `stylua.toml`.

---

## 2. Comprehensive Plan by Phases

### Phase 1: Types — the four unions, the carry slot, and Amendment A3 held in place

#### Step 1.1: Declare the four v2 literal unions beside the existing four

**File:** `src/shared/Types.luau`
**Verify:** `grep -qE '^export type MonsterState = ' src/shared/Types.luau`

Add `ItemType`, `MonsterState`, `BodyKind` and `CamouflageForm` as exported literal unions immediately
after the existing `RoundResult` line, so `Enums.luau` has something for its casts to point at.

Current state — `src/shared/Types.luau:11-14`:

```diff
  export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
  export type Role = "SURVIVOR" | "ASWANG"
  export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
  export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"
+
+ --[[
+ 	THE v2.0 VOCABULARY (V02). Declared here rather than in `Enums.luau` because Enums requires this
+ 	module for its `:: Types.X` casts, and a union that lives beside its consumer cannot be cast to.
+
+ 	All four are UPPER_SNAKE string literals, matching the four above: readable in a log line, readable
+ 	in analytics, and — unlike a number — impossible to confuse with an unrelated enum of the same
+ 	arity. Luau unions are structural, so none of these is assignable to `RoundPhase` or to each other.
+ ]]
+
+ -- §4.4/§4.6. The three things folklore says stop an aswang, and the entire item vocabulary of v2.0.
+ -- §3's OUT list forbids a fourth; `check:scope` watches `weapons?` for the day someone adds one.
+ export type ItemType = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+ --[[
+ 	§4.3. What the Aswang is doing right now.
+
+ 	NORMAL and TRANSFORMED are the v1.3 pair. FEEDING (§4.3) is the 5-second lock on a corpse that
+ 	replaced the kill cooldown. CAMOUFLAGED (§4.3) is the ambient-animal form. EXPOSED is the odd one
+ 	out and it is a QUESTION for the chunk that builds the state machine, not for V02 — see Follow Ups:
+ 	§4.3 says camouflage is locked "until it has taken a salt hit", which reads as a LATCH that persists
+ 	across transforms and feeds, while the other four read as mutually-exclusive activities. V02
+ 	declares the five values the build plan asks for and takes no position on exclusivity.
+ ]]
+ export type MonsterState = "NORMAL" | "TRANSFORMED" | "EXPOSED" | "FEEDING" | "CAMOUFLAGED"
+
+ --[[
+ 	§4.7. A body on the ground is one of two things, and telling them apart is a DESIGN GOAL rather
+ 	than a leak: §4.7 requires husk state to be "publicly obvious", because a husk that differed from a
+ 	live body in some replicated-but-subtle way would let a client enumerate exactly which bodies are
+ 	husks — and since the Aswang can never be one, every husk is provably innocent. Public information
+ 	cannot be exploited; half-hidden information can.
+
+ 	Neither literal contains the word `ghost`, which `check:scope` arms as of V01. That is not luck —
+ 	`check-scope.mjs` names corpse and husk as its two ALLOW cases.
+ ]]
+ export type BodyKind = "CORPSE" | "HUSK"
+
+ --[[
+ 	§4.3. What a revealed Aswang can turn into. Four ambient forms so the barrio's scenery is a place
+ 	the monster can hide IN rather than a backdrop, and so §4.5's "It's the [animal]!" phrase has a
+ 	closed set of things it can name.
+
+ 	NOT A PET SYSTEM, and the distance matters because `check:scope` arms `pets?`. These are forms the
+ 	Aswang wears, owned by nobody, purchasable never (§8.3).
+ ]]
+ export type CamouflageForm = "CAT" | "DOG" | "PIG" | "VILLAGER"
```

**NOTE on `RoundResult`:** it is left alone, and it is stale. `"SURVIVORS_ESCAPED"` names the v1.3
escape gate, which v2.0 retired, and there is no member for "survivors killed the Aswang" — the second
win condition (§4.6). Changing it touches `RoundService`, `XPCurve`, `BadgeService` and
`RoundEndedPayload`, which is a behaviour change and therefore not V02. Raised in Follow Ups.

#### Step 1.2: Add the carry slot to `ClientRoundSnapshot`

**File:** `src/shared/Types.luau`
**Verify:** `npm run check:secrecy`

One optional field, `YourCarriedItem: ItemType?`, describing the receiving player and nobody else. No
field is removed; the type still has no alive count and no role field.

`src/shared/Types.luau:382-389`:

```diff
  -- What the client is allowed to know. Note the absence of AswangUserId.
  export type ClientRoundSnapshot = {
  	Phase: RoundPhase,
  	SecondsRemaining: number,
  	RoundNumber: number,
  	YourRole: Role?, -- only ever the receiving player's OWN role
  	YourState: PlayerState,
+ 	--[[
+ 		V02, §4.4. WHAT THE RECEIVING PLAYER IS CARRYING, AND THE `Your` PREFIX IS THE WHOLE CONTRACT.
+
+ 		Safe for a reason that is structural rather than argued: `RoundSnapshot` is built per player and
+ 		sent with `:FireClient` (RoundService.luau:626 and :639) precisely because `YourState` already
+ 		differs between a survivor and a mid-round spectator. There is no broadcast form of this payload
+ 		to accidentally put someone else's inventory on.
+
+ 		IT IS NOT A ROLE ORACLE. The Aswang carries nothing — the three items are the survivors' (§4.6)
+ 		— so its slot is `nil`, which is also what an empty-handed survivor's slot is. The two are
+ 		indistinguishable, and they must stay that way: do not add a "cannot carry" or "carry denied"
+ 		value to `ItemType` for the monster's benefit.
+
+ 		IT IS NOT A DEATH SIGNAL. It is not a count, it does not move when another player dies, and it
+ 		says nothing about the roster. Amendment A3 (§4.7) is untouched by it.
+
+ 		CARRY IS DELIBERATELY NOT PUBLIC. §4.5's v2 phrase list includes "I have the buntot pagi" —
+ 		announcing what you hold is a CHOICE with a cost, and that is what turns the single buntot pagi
+ 		into a protection problem. A field that told every client who held it would delete that phrase's
+ 		reason to exist. So: never widen this to another player's carry, and never mirror it onto an
+ 		attribute or a tag, both of which replicate to everyone.
+
+ 		OPTIONAL BECAUSE `Config.Items.*SpawnCount` PLUS `Config.Salt.CarryLimit = 1` MEAN ONE SLOT.
+ 		If the carry limit ever rises this becomes a list, and that is a contract change to argue in a
+ 		plan rather than a field to widen quietly.
+
+ 		V02 ADDS NO PRODUCER. `buildSnapshot` does not set it, exactly as it deliberately does not set
+ 		`YourRole` (RoundService.luau:620-624), so no service changes and `analyze` stays clean.
+ 	]]
+ 	YourCarriedItem: ItemType?,
  }
```

**IMPORTANT — what `check:secrecy` does and does not prove here.** `RoundSnapshot` is *not* on
`check-secrecy.mjs`'s `REVEAL_ALLOWLIST`, so its broadcast rule genuinely runs over this payload and
matches `role`, `aswang` and `killer\w*` tokens. `YourCarriedItem` matches none, so the check goes
green — but it is a text tripwire that cannot follow data flow, and the argument above is the actual
defence. Read `Types.luau:326-353` (the `RoundEndedPayload` comment): an **extra** field on an annotated
table is accepted by the typechecker **silently**, measured against this repo's own analyzer.

#### Step 1.3: Leave Amendment A3's block byte-identical and say so

**File:** `src/shared/Types.luau`
**Verify:** `grep -q 'SurvivorsRemaining' src/shared/Types.luau`

The forbidden-name list below `ClientRoundSnapshot` is carried into v2 verbatim, in place. This step's
check is a **preservation** assertion — nothing in V02 types that token, so it fails if the block is
rewritten or dropped.

**This step is mostly a "do not touch" instruction, and it is a real step because the block sits
directly under the field Step 1.2 edits.** The comment at `src/shared/Types.luau:391-417` — the one
opening `THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7)` —
stays **byte-identical**. In particular its forbidden-name list:

> `SurvivorsRemaining`, `DeadCount`, `RosterSize` and a `YourState`-derived tally over a roster field
> are the same oracle wearing different words, and none of them contains a token `check-secrecy.mjs`
> matches.

Spec line 52 confirms it survives the rewrite: *"Amendment A3 survives intact (§4.7): death is not
public, there is no global death signal, and `ClientRoundSnapshot` still carries no alive-count."*

The only permitted edit in that region is **appending** one v2 sentence after the existing text, and it
is optional:

```diff
  	`YourState`-derived tally over a roster field are the same oracle wearing different words, and
  	none of them contains a token `check-secrecy.mjs` matches. C18 wants an alive count on the HUD
  	(BUILD-PLAN ~line 456) and this is the field it would reach for; Amendment A3 is the sentence
  	that says no.
+
+ 	V02: STILL NO, AND v2.0 MAKES IT WORSE RATHER THAN BETTER. `Round.MaxPlayers` drops from 8 to 5
+ 	(§C, spec line 873), so every survivor is a fifth of the field instead of an eighth and a count
+ 	narrows it twice as fast. The Aswang must now kill EVERYONE (§4.1), which means the count would
+ 	also be a live progress bar on the monster's own win condition — for both sides, for free.
  ]]
```

**QUESTION for the implementer:** the block above is the one thing in these three files that has been
"rediscovered the hard way twice" (§4.7). If you find yourself editing anything inside it other than
appending the paragraph above, stop and ask.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — the one field that crosses is argued in Step 1.2, not waved through.**
  `YourCarriedItem` is per-receiver by construction (`FireClient`, `RoundService.luau:639`), is `nil`
  for the Aswang and for an empty-handed survivor alike, and is never mirrored to an attribute or a
  CollectionService tag. Both of those replicate to every client and there is no private one.
- **Extra fields are accepted silently.** `Types.luau:326-353` records the measurement: the analyzer
  catches a wrong-typed field and a missing field, and **does not** catch an extra one. So the type is
  documentation plus two-thirds of a guard, and adding a second field to `ClientRoundSnapshot` in this
  phase is a decision to argue, not a detail.
- **Remote direction / rate limiting — N/A.** V02 declares no remote and no `OnServerEvent` handler.
  `Remotes.luau` is not in scope.
- **Magic numbers — N/A.** `check:config` governs `src/server/` and `src/client/` only
  (`check-config.mjs:36`), so `src/shared/Types.luau` is not scanned. V02 adds no numbers here anyway.
- **Phase ownership — N/A.** Nothing here touches `setPhase`.
- **Player leaving mid-round.** `BodyKind = "HUSK"` is the word for exactly this case, but declaring the
  union creates no husk. §6.4's five edge cases land on the chunk that builds `BodyService`.
- **Strict Luau — the live risk in this phase.** Every one of the four unions must be `export type`; a
  plain `type` compiles here and then fails from `Enums.luau` with `Unknown type 'ItemType'`. Step 2.3's
  `npm run analyze` is what catches it.
- **Mobile budget — N/A.** No lights, particles or per-frame work.
- **Scope.** `CAT`/`DOG`/`PIG` are near `pets?`, `BUNTOT_PAGI` is near `weapons?`, and `CORPSE`/`HUSK`
  are near `ghosts?` — all three rules are armed. `check-scope.mjs` reads code **and string literals**
  (`withStrings`) but strips comments, so the literals are what matter. Step 2.1 is the gate; measured
  green today with 19 shapes watched.

---

### Phase 2: Enums — the four frozen tables, every value cast

#### Step 2.1: `Enums.ItemType` and `Enums.BodyKind`

**File:** `src/shared/Enums.luau`
**Verify:** `npm run check:scope`

The three items and the two body kinds. `check:scope` is the right gate here rather than a formality:
`corpse` and `husk` are named in `check-scope.mjs` as the deliberate near-misses of the armed `ghosts?`
rule, and `BuntotPagi` is the near-miss of the armed `weapons?` rule.

Append after `Enums.RoundResult`, `src/shared/Config.luau` untouched. Existing file shape at
`src/shared/Enums.luau:35-42`:

```diff
  Enums.RoundResult = table.freeze({
  	SurvivorsEscaped = "SURVIVORS_ESCAPED" :: Types.RoundResult,
  	AswangWins = "ASWANG_WINS" :: Types.RoundResult,
  	Timeout = "TIMEOUT" :: Types.RoundResult,
  	Aborted = "ABORTED" :: Types.RoundResult, -- e.g. the Aswang disconnected
  })
+
+ -- V02, §4.4/§4.6. The three items, and the only three there will ever be — §3's OUT list is explicit
+ -- that nothing else damages the Aswang, and §8.3 adds that a SECOND buntot pagi would be selling the
+ -- win condition. `BuntotPagi` splits to Buntot + Pagi under check:scope's word splitter and matches
+ -- neither `weapons?` nor anything else on the list; that is by design, not by luck.
+ Enums.ItemType = table.freeze({
+ 	Salt = "SALT" :: Types.ItemType,
+ 	Bawang = "BAWANG" :: Types.ItemType,
+ 	BuntotPagi = "BUNTOT_PAGI" :: Types.ItemType,
+ })
+
+ -- V02, §4.7. A corpse is a killed player; a husk is one who left or went AFK. `PlayerState.Dead`
+ -- already spells the state, so this names the BODY rather than the player — a husk's owner is not
+ -- dead, they are gone, and §4.7's roster deliberately does not shrink for either.
+ Enums.BodyKind = table.freeze({
+ 	Corpse = "CORPSE" :: Types.BodyKind,
+ 	Husk = "HUSK" :: Types.BodyKind,
+ })
  
  return Enums
```

**IMPORTANT — the casts are the entire point of this step, and nothing catches a missing one here.**
Inside a `table.freeze({ ... })` literal an uncast `Salt = "SALT"` is *not* an analyzer error; it infers
as plain `string` and only fails later, at the first call site that passes it to a parameter typed
`Types.ItemType`. That is why Step 2.2's verify greps the cast text directly, and why Step 2.3's
`analyze` proves the complementary half (the cast *target* exists and is spelled right). Neither check
subsumes the other.

#### Step 2.2: `Enums.MonsterState` and `Enums.CamouflageForm`

**File:** `src/shared/Enums.luau`
**Verify:** `grep -qE '"CAMOUFLAGED" :: Types\.MonsterState' src/shared/Enums.luau`

Five monster states and four camouflage forms, each with its cast.

```diff
  Enums.BodyKind = table.freeze({
  	Corpse = "CORPSE" :: Types.BodyKind,
  	Husk = "HUSK" :: Types.BodyKind,
  })
+
+ --[[
+ 	V02, §4.3. What the Aswang is doing.
+
+ 	V02 DECLARES THESE AND WIRES NONE OF THEM. Read `Types.MonsterState`'s comment before building the
+ 	state machine: `Exposed` reads as a LATCH (§4.3 — camouflage is locked "until it has taken a salt
+ 	hit", and §4.6 — the buntot pagi kills an Aswang that is Exposed AND weakened) while the other four
+ 	read as mutually-exclusive activities. Whether this is one field or a field plus a flag is that
+ 	chunk's decision, and V02 must not pre-empt it by wiring a `setState`.
+
+ 	`Weakened` is deliberately absent. It is a HEALTH PREDICATE — `health <= Config.Monster
+ 	.WeakenedThreshold` — not a state, and duplicating it as an enum member is how two sources of truth
+ 	for one fact get out of step.
+ ]]
+ Enums.MonsterState = table.freeze({
+ 	Normal = "NORMAL" :: Types.MonsterState,
+ 	Transformed = "TRANSFORMED" :: Types.MonsterState,
+ 	Exposed = "EXPOSED" :: Types.MonsterState,
+ 	Feeding = "FEEDING" :: Types.MonsterState,
+ 	Camouflaged = "CAMOUFLAGED" :: Types.MonsterState,
+ })
+
+ -- V02, §4.3. The four forms a REVEALED Aswang may wear. §4.5's "It's the [animal]!" phrase names one
+ -- of these, which is what stops camouflage being unbeatable — a barrio full of scenery becomes a
+ -- barrio with one monster in it. Villager is in the set because three animals in an empty street is
+ -- a tell; a fourth option that looks like a person is what makes the guess cost something.
+ Enums.CamouflageForm = table.freeze({
+ 	Cat = "CAT" :: Types.CamouflageForm,
+ 	Dog = "DOG" :: Types.CamouflageForm,
+ 	Pig = "PIG" :: Types.CamouflageForm,
+ 	Villager = "VILLAGER" :: Types.CamouflageForm,
+ })
  
  return Enums
```

**NOTE — the form set is closed, and closing it is a secrecy property, not tidiness.** §4.3 gates
camouflage behind a salt hit specifically so an *unrevealed* Aswang can never vanish; §4.5 then needs a
finite set to name. A fifth form added later without a matching quick-chat phrase makes the monster
nameable-in-principle and unnameable-in-practice.

#### Step 2.3: Prove every cast resolves

**File:** `src/shared/Enums.luau`
**Verify:** `npm run analyze`

A cast to a union that does not exist, or whose name is misspelled, is an analyzer error
(`Unknown type 'ItemTyp'`). This is what binds Phase 2 to Phase 1.

No diff. Run `npm run analyze` and confirm it is graded green against `analyze-baseline.json`.

**If it is red, do NOT reach for `check-analyze.mjs --update`.** The baseline is tracked at the repo
root so widening the gate shows up in a diff, and `--update` refuses to run under an agent. A V02
analyze failure means one of exactly three things:

1. a union in Step 1.1 was declared `type` instead of `export type`;
2. a cast in Step 2.1/2.2 names a union that does not exist or is misspelled;
3. something in Phase 3 removed a `Config` key that a service still reads — which is the failure mode
   the preamble measured, and the reason Step 3.4 aliases rather than renames.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Scope — this is the phase where a scope breach would actually appear, and it is handled.** Nine new
  string literals enter `src/`, and `check-scope.mjs` reads string literals (it strips comments, not
  strings). Three near-misses of armed rules: `CORPSE`/`HUSK` against `ghosts?` (armed at V01),
  `BUNTOT_PAGI` against `weapons?`, `CAT`/`DOG`/`PIG` against `pets?`. All three miss because the
  splitter tokenises on case and digit boundaries and every rule is `^…$`-anchored. Step 2.1's
  `npm run check:scope` is the proof, not this paragraph.
- **Strict Luau — the cast on every value, and nothing local catches a missing one.** An uncast literal
  inside `table.freeze` is legal and infers as `string`; it fails at the first typed call site, which
  in V02 does not exist yet. So a missed cast ships silently and detonates in V03+. Step 2.2's grep is
  the only mechanical check on the cast text; re-read all nine lines by eye before closing the phase.
- **Secret leakage — none, and one shape to refuse.** These are shared constants and
  `src/shared/pure/` plus `ReplicatedStorage.Shared` are readable AND callable by any LocalScript, so
  every literal here is public by construction. That is fine: logic is not secret. What is not fine is
  a later chunk deriving a form from a seed a client can supply — `Random.new(roundNumber)` or
  `Random.new(os.time())` replays locally. Seed camouflage from server-only entropy.
- **Remote direction / rate limiting — N/A.** No remote, no handler.
- **Magic numbers — N/A.** `check:config` does not scan `src/shared/`, and this phase adds no numbers.
- **Phase ownership — N/A.**
- **Player leaving mid-round.** `Enums.BodyKind.Husk` exists now; nothing produces one. §6.4's edge
  cases belong to the chunk that does.
- **Mobile budget — N/A.** No lights, particles or per-frame work. Note for later: four camouflage
  forms means four rigs, and §5's limits apply to whoever loads them.

---

### Phase 3: Config — spec §6.5's v2 block, one comment per number

#### Step 3.1: `Round` — the two v2 value changes

**File:** `src/shared/Config.luau`
**Verify:** `grep -qE 'MaxPlayers = 5,' src/shared/Config.luau`

`Duration` 420 → 300 and `MaxPlayers` 8 → 5. No keys added or removed.

`src/shared/Config.luau:12-18`:

```diff
  	Round = {
  		Intermission = 25, -- seconds in lobby before a round starts
- 		Duration = 420, -- 7 minutes of "night" before sunrise
+ 		-- §6.5 and §4.1 (spec line 170): a flat 300s of "night" before sunrise. v2.0 shortens the
+ 		-- round from v1.3's 420 because the Aswang must now kill EVERYONE (§4.1) rather than race a
+ 		-- gate, and the sharpening tracker (§4.6) is what makes 5 minutes enough to find them.
+ 		-- §4.1 flags the flat value as an assumption to overrule in one line if it does not hold.
+ 		Duration = 300,
  		EndScreen = 12, -- reveal + stats screen
  		StartingDelay = 4, -- role assignment + teleport fade
  		MinPlayers = 3, -- MUST be playable at this count (see spec §9 cold start)
- 		MaxPlayers = 8,
+ 		-- §6.5 and §C (spec line 873): 5, not 8 and emphatically not 20. §4.1 (spec line 193) argues it
+ 		-- as arithmetic rather than taste — every kill costs a transform, an approach, a revert and a
+ 		-- 5-second feed, and at 7 survivors that bill exceeds the night. Small servers also fill faster
+ 		-- and feel full sooner.
+ 		MaxPlayers = 5,
```

**NOTE — nothing in `src/` reads `Round.MaxPlayers`.** Grepped: the only references are
`tests/config.test.luau` (lines 39, 45, 99, 171, 634) and a prose comment at `Config.luau:242`. So this
is a safe value change today and a landmine tomorrow — the number that *should* read it is Roblox's own
`Players.MaxPlayers`, which lives in the place file, not in Git. Raised in Follow Ups.

**Both changes were checked against every assertion that consumes them, and none goes red:**

| Assertion | Before | After |
| --- | --- | --- |
| `config.test:132` cycle `<= 480` | 25+420+12 = 457 | 25+300+12 = **337** ✓ |
| `config.test:217` `Duration >= 300` | 420 | **300** ✓ (now exactly on the floor) |
| `config.test:39` `MaxPlayers >= MinPlayers` | 8 ≥ 3 | **5 ≥ 3** ✓ |
| `config.test:45` `MaxPlayers <= 8` | 8 | **5** ✓ |
| `config.test:99` `Salt.SpawnCount < MaxPlayers` | 4 < 8 | **4 < 5** ✓ |
| `config.test:171` `RepeatCooldownRounds < MaxPlayers` | 2 < 8 | **2 < 5** ✓ |
| `config.test:634` Aswang vs survivor XP ceiling | 8 → maxKills 7 | **maxKills 4**: 150 vs 115 ✓ both bounds |
| `tests/xp-curve.test.luau:439` `roundSeconds` | 457 | **337** — used only in a printed string ✓ |

**IMPORTANT: `Duration = 300` lands exactly on `config.test:217`'s floor.** That assertion exists
because a 60-second Studio leftover once passed every other check. It now has zero margin, so a debug
session that drops `Duration` at all turns it red — which is the correct behaviour and worth knowing
before someone reports it as a V02 regression. `Config.Debug` values and `guard-commit.mjs`'s
`check:debug` are the separate mechanism for playtest tuning; do not lower `Duration` for testing.

#### Step 3.2: `Monster` — the six numbers v2 adds

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

`MaxHealth`, `WeakenedThreshold`, `FeedDuration`, `FeedHeal`, `SmokeDuration`, `SmokeRadius`. Nothing
existing is touched, including the two tunables v2 retires (see Follow Ups).

Insert after `TransformAudioRange`, `src/shared/Config.luau:72`:

```diff
  		TransformAudioRange = 40, -- how far the transform sound carries
+
+ 		--[[
+ 			THE ASWANG'S HEALTH (§4.6), AND THE SECOND WIN CONDITION LIVES IN THESE TWO NUMBERS.
+
+ 			v1.3 had no monster health at all — survivors escaped or died. v2.0's second win condition is
+ 			"salt it down, then land the buntot pagi", and §4.6 (spec line 415) gates the kill on the
+ 			Aswang being BOTH Exposed and below WeakenedThreshold. So these are not flavour: raise
+ 			MaxHealth or lower WeakenedThreshold and survivors stop being able to win that way, with
+ 			nothing in the game to tell you. Read the plan's preamble before touching either.
+
+ 			WeakenedThreshold is a HEALTH PREDICATE, not a `MonsterState` member — see Enums.MonsterState.
+ 		]]
+ 		MaxHealth = 100,
+ 		WeakenedThreshold = 25,
+
+ 		--[[
+ 			FEEDING (§4.3) — WHAT REPLACED THE KILL COOLDOWN, and the design's most deliberate window.
+
+ 			After a kill the Aswang must feed on the corpse, transformed and locked in place, for
+ 			FeedDuration seconds. That is the ONLY reliably predictable moment in the round: the monster
+ 			is stationary, visible, and at a location survivors already know because there is a body
+ 			there. §4.6 says this is the window the buntot pagi needs — without it, killing the Aswang
+ 			is a coin flip against a faster player.
+
+ 			So FeedDuration is load-bearing rather than cosmetic. §6.5 invariant 2 requires it to exceed
+ 			the time to cross ~15 studs and land a swing; at Trial.PlayerBaselineWalkSpeed = 16 that
+ 			crossing is ~0.94s, leaving ~4s for the approach and the swing. V11 pins the RELATIONSHIP.
+
+ 			FeedHeal is the other half. It restores health (§4.6's table) and, once the Aswang has been
+ 			revealed, restores its ability to camouflage (§4.3) — which is why interrupting a feed with
+ 			salt is a real victory rather than a nuisance: the monster loses both at once.
+ 		]]
+ 		FeedDuration = 5,
+ 		FeedHeal = 25,
+
+ 		--[[
+ 			SMOKE (§4.3) — the Aswang's escape, and it belongs to the monster on purpose.
+
+ 			A burst that breaks line of sight and covers a retreat, so that being salted is a setback
+ 			rather than a death sentence. An early v2 draft attached the smoke to SALT instead, which
+ 			meant the survivor who landed the counterplay was the one blinded by it — a counterplay item
+ 			that punishes its user is a dead item. This is that fix, and it is why the numbers sit under
+ 			Monster rather than under Items.
+
+ 			SmokeRadius is a VISUAL and LOS radius, not a damage radius. Nothing takes damage from smoke.
+ 			Counted against §5's mobile particle budget by whoever builds the effect.
+ 		]]
+ 		SmokeDuration = 4,
+ 		SmokeRadius = 18,
+
  		CorpseDuration = 45,
```

**IMPORTANT — two numbers already in this table are dead under v2.0 and V02 must not delete them.**

- **`Monster.KillCooldown = 30` (line 70)** is superseded outright: §4.3's heading is literally
  *"Feeding — what replaced the kill cooldown"*. It is still read by `MonsterService.luau` and pinned by
  `config.test:238`. Deleting it turns `analyze` **and** `test:unit` red, which violates V02's Done.
- **`Monster.CorpseDuration = 45` (line 73)** is filed under `Bodies` in §6.5, not under `Monster`. It
  is read at `MonsterService.luau:335` and cited in `Types.luau:406`. Moving it turns `analyze` red for
  the same reason. Step 3.3 therefore builds `Bodies` **without** it.

Both are listed in Follow Ups with an owner. Add a one-line tombstone comment above each if you like;
do not remove the value.

#### Step 3.3: `Search`, `Tracker` and `Bodies` — three new tables

**File:** `src/shared/Config.luau`
**Verify:** `npm run lint`

Eight new numbers across three tables. `Bodies` deliberately does **not** take `CorpseDuration` yet;
the reason is in the step body.

Insert the three tables after the `Salt` table closes (`src/shared/Config.luau:151`), before the
QuickChat block:

```diff
  		RevealGlowOutlineRgb = { 190, 235, 255 },
  	},
+
+ 	--[[
+ 		V02, §4.4. SEARCHING — what replaced the task system, and the trade at the heart of v2.0.
+
+ 		Survivors search containers for the three items. Searching takes TIME and makes NOISE, and noise
+ 		is how the monster finds you (spec line 76). That is the whole loop: every second of progress is
+ 		a second of exposure, which is what tasks never were.
+
+ 		V16's third playtest question is whether this feels like survival or like a chore. These three
+ 		numbers are the ones that decide it, so expect all three to move.
+ 	]]
+ 	Search = {
+ 		-- How many searchable containers the barrio holds. It must comfortably exceed the total items
+ 		-- placed (Items.*SpawnCount sums to 7) or every container is a hit and searching stops being a
+ 		-- gamble. V03 owns the layout draw and the map-side tag contract.
+ 		ContainerCount = 15,
+ 		-- Seconds to search one container, uninterrupted. The exposure window: long enough that being
+ 		-- caught mid-search is a real risk, short enough that a survivor will still take the risk.
+ 		SearchTime = 6,
+ 		-- Studs the noise carries. DELIBERATELY LARGER THAN ANY OTHER RANGE IN THIS FILE — the point is
+ 		-- that searching summons the monster, not that it might. Compare Tracker.EarlyRadius = 40: a
+ 		-- searching survivor is louder than the tracker is sharp, for the whole first half of the night.
+ 		NoiseRadius = 60,
+ 	},
+
+ 	--[[
+ 		V02, §4.6. THE SHARPENING TRACKER — why hiding does not win.
+
+ 		The Aswang's sense of where people are gets better as the night goes on. This is the pressure
+ 		that replaced the escape gate: in v1.3 a survivor who hid in a corner for seven minutes won, and
+ 		spec §4.6 (line 448) is explicit that under v2.0 hiding buys you two minutes and kills you at
+ 		five. §4.7 (line 542) adds that the TIMEOUT FLIPPED from v1.3 — the clock running out is now a
+ 		survivor win — and the tracker is what pays for that flip being fair.
+
+ 		VAGUE AND SLOW, NEVER A LIVE FEED (spec line 454). The Aswang is a player, not an AI; a live
+ 		feed hands a human a wallhack and the round stops being a hunt. Interval is how often a ping
+ 		lands, Radius is how imprecise it is.
+
+ 		§6.5 invariant 5 (V11): the tracker SHARPENS, never dulls. Late < Early on both axes.
+ 	]]
+ 	Tracker = {
+ 		EarlyInterval = 90, -- seconds between pings in the first half of the round
+ 		LateInterval = 30, -- and in the second: three times as often
+ 		EarlyRadius = 40, -- studs of imprecision early — a neighbourhood, not an address
+ 		LateRadius = 15, -- and late: close enough to walk to, still not a marker on a head
+ 	},
+
+ 	--[[
+ 		V02, §4.7. BODIES — corpses and husks.
+
+ 		A corpse is a killed player. A husk is one who quit or went AFK, and husks are why the roster
+ 		never shrinks: the Aswang's win condition is "kill everyone", so a player who leaves must not
+ 		delete their own square from the board.
+
+ 		AMENDMENT A3 GOVERNS BOTH (§4.7, spec line 52). Death is not public; a client learns someone
+ 		died by FINDING the body. Nothing in this table may grow into a count, a roster or a signal.
+ 	]]
+ 	Bodies = {
+ 		-- Seconds of no input before a player is husked. Generous on purpose: a phone that locks (§5
+ 		-- puts ~60% of players on one) must not cost its owner their round in under two minutes.
+ 		AfkSeconds = 120,
+ 		-- §4.7: a husk unreachable for this long is relocated to the nearest walkable point. Someone who
+ 		-- quit inside a garlic-shielded house, or fell out of the map, must not make kill-everyone
+ 		-- unwinnable. A husk also cannot benefit from garlic — that rule is code, not a number.
+ 		HuskRelocateAfter = 60,
+ 	},
```

**NOTE — `Bodies.CorpseDuration` is absent, and that is the deviation from §6.5's literal block.**
§6.5 files `CorpseDuration = 45` under `Bodies`; it currently lives at `Config.Monster.CorpseDuration`
and is read at `MonsterService.luau:335`, cited at `Types.luau:406`, and pinned twice by
`config.test:229` and `:238`. Moving it turns `analyze` red (measured — see the preamble), which
violates V02's Done. Unlike the `Salt` → `Items` renames in Step 3.4, the **name does not change**, so a
reader searching for `CorpseDuration` finds it either way and no alias is warranted. The move belongs to
the chunk that edits `MonsterService`. Recorded in Follow Ups.

**QUESTION for the implementer:** `Search.NoiseRadius = 60` and `Tracker.EarlyRadius = 40` have no
pinned relationship in §6.5's six invariants, yet the comment above asserts one ("louder than the
tracker is sharp"). If V03/V07 finds that reading wrong, the comment is what is wrong, not the number —
fix the comment rather than quietly re-tuning to match it.

#### Step 3.4: `Items` — §6.5's item block, and `Salt` as a compatibility view

**File:** `src/shared/Config.luau`
**Verify:** `grep -qE 'BuntotPagiSpawnCount = 1,' src/shared/Config.luau`

The step that carries the plan's one real design decision. `Items` becomes the canonical, complete §6.5
table; `Config.Salt`'s four renamed keys become aliases into it so the five live readers keep compiling.

**The problem, stated once.** §6.5 renames four numbers that already exist:

| §6.5 name | lives today as | read by |
| --- | --- | --- |
| `Items.SaltSpawnCount` | `Salt.SpawnCount` | `ItemService`, `pure/SaltCarry`, `config.test` |
| `Items.SaltStunDuration` | `Salt.StunDuration` | `ItemService`, `config.test` |
| `Items.SaltRevealDuration` | `Salt.RevealDuration` | `ItemService`, `config.test` |
| `Items.SaltThrowRange` | `Salt.ThrowRange` | `ItemService`, `TrialService`, `config.test` |

Copying them into `Items` and leaving `Salt` intact gives one number two homes — the exact failure
`Config.luau` exists to prevent. Renaming them and deleting the old keys turns `analyze` red across five
modules. **Aliasing is the third option and the only one that satisfies both.**

Add a top-level local **above** `local Config = {`, at `src/shared/Config.luau:11`:

```diff
  	See docs/MVP-SPEC.md Appendix A for guidance on which knob to turn when.
  ]]
  
+ --[[
+ 	§6.5's ITEM BLOCK, HOISTED INTO A LOCAL SO `Config.Salt` CAN ALIAS IT (V02).
+
+ 	This is the file's only local, and it exists to keep ONE number in ONE place across a rename. §6.5
+ 	renames four v1.3 salt tunables (`Salt.SpawnCount` -> `Items.SaltSpawnCount`, and three siblings).
+ 	Five live modules still read the old names — ItemService, TrialService, UIController,
+ 	InputController and shared/pure/SaltCarry — and a missing Config key is a HARD analyzer error, not
+ 	a warning:
+
+ 		TypeError: Key 'SpawnCount' not found in table '{| CarryLimit: number |}'
+
+ 	V02 is a vocabulary chunk that may not touch services, so `Items` below is CANONICAL and the four
+ 	matching fields of `Config.Salt` are ALIASES pointing at it. Tune here. `Config.Salt` shrinks to
+ 	nothing as each consumer is renamed, and disappears with the last one.
+ ]]
+ local Items = {
+ 	--[[
+ 		SALT (§4.6) — reveal and damage. Four pouches, one carried at a time.
+
+ 		READ THIS BEFORE CHANGING SaltDamage OR SaltSpawnCount. §6.5 invariant 1 requires
+ 		`SaltDamage x (SaltSpawnCount - 1) >= Monster.MaxHealth - Monster.WeakenedThreshold`, so that
+ 		the second win condition survives ONE missed throw. At the shipped values that is
+ 		`25 x 3 = 75 >= 100 - 25 = 75` — EQUALITY, with zero margin. Every pouch but one must connect.
+ 		Tighten either number and survivors can no longer weaken the Aswang at all, and nothing in the
+ 		game will say so. V11 pins this; until V11 lands, this comment is the only guard.
+
+ 		The first salt hit is also what UNLOCKS the Aswang's camouflage (§4.3/§4.6) — revealing it is
+ 		not free — and what interrupts a feed, costing the monster both the heal and the camouflage
+ 		refresh. Salt is the game's pivot, which is why it has four numbers and three invariants.
+ 	]]
+ 	SaltSpawnCount = 4,
+ 	SaltDamage = 25,
+ 	-- Invariant 6: RevealDuration > StunDuration, so salting creates a CHASE rather than a freeze. A
+ 	-- reveal that ended with the stun would be information nobody could act on.
+ 	SaltStunDuration = 4,
+ 	SaltRevealDuration = 10,
+ 	-- Invariant 3: > Monster.KillRange (8). You can salt it before it can reach you, or salt is not
+ 	-- counterplay — it is a suicide button.
+ 	SaltThrowRange = 25,
+
+ 	--[[
+ 		BAWANG / GARLIC (§4.6) — deny a doorway, never a room.
+
+ 		A barrier the Aswang will not cross, and its effect is SILENT AND INVISIBLE: no knockback, no
+ 		VFX, nothing that tells the survivors it worked. That is what makes garlic a loyalty test — place
+ 		it, ask everyone to walk inside, and watch who declines — rather than a wall.
+
+ 		Invariant 4: GarlicDuration < Round.Duration / 4 (15 < 75). Garlic buys TIME, never safety
+ 		(pillar six); §3's OUT list forbids permanent safe rooms outright.
+ 	]]
+ 	GarlicSpawnCount = 2,
+ 	GarlicDuration = 15,
+
+ 	--[[
+ 		BUNTOT PAGI (§4.6) — the only thing that kills, and there is exactly ONE per round.
+
+ 		ONE IS A DESIGN CONSTANT, NOT A TUNABLE. Denying survivors the buntot pagi is a real Aswang
+ 		strategy that looks exactly like ordinary survival, and §4.5 gives the carrier a phrase — "I
+ 		have the buntot pagi" — that makes them findable, which is what turns the single item into a
+ 		protection problem. Two would delete both.
+
+ 		§8.3 is blunter: selling a second one sells the win condition, and it is named there as the
+ 		sharpest monetisation temptation in the game. `check:scope` arms `weapons?` for the day someone
+ 		adds a third item.
+
+ 		It kills only an Aswang that is BOTH Exposed and below Monster.WeakenedThreshold (§4.6).
+ 	]]
+ 	BuntotPagiSpawnCount = 1,
+ }
+
  local Config = {
```

Then wire it in and alias the four, `src/shared/Config.luau:97-102`:

```diff
+ 	-- §6.5's canonical item block. Declared above so Config.Salt can alias into it; see that comment.
+ 	Items = Items,
+
  	Salt = {
- 		SpawnCount = 4,
- 		StunDuration = 4,
- 		RevealDuration = 10,
- 		ThrowRange = 25,
+ 		--[[
+ 			V02: THESE FOUR ARE ALIASES, NOT VALUES. §6.5 renames them; the rename cannot land until the
+ 			five modules that read them are edited, and V02 may not edit a service. Tune `Items` above —
+ 			changing a line here does nothing, because there is no value here to change.
+
+ 			DELETE EACH ONE with the chunk that renames its last reader. What remains below is the half
+ 			of this table §6.5 does not mention: real values with no v2 counterpart, which stay.
+ 		]]
+ 		SpawnCount = Items.SaltSpawnCount,
+ 		StunDuration = Items.SaltStunDuration,
+ 		RevealDuration = Items.SaltRevealDuration,
+ 		ThrowRange = Items.SaltThrowRange,
+
  		CarryLimit = 1,
```

`CarryLimit`, `PickupRangeStuds`, `ThrowConeDegrees`, `PouchPoolSize`, `PouchRgb`,
`RevealGlowFillRgb` and `RevealGlowOutlineRgb` are untouched — §6.5 does not name them and they are all
still live.

**Why a hoisted local rather than a post-declaration patch.** `Config.Items = Items` written *after* the
table literal adds a property to an already-sealed inferred table type, which Luau rejects. The four
aliases have the same problem in reverse. Declaring `Items` first is the only ordering that typechecks,
and it costs one local.

**IMPORTANT — verify nothing reads `Config.luau` positionally.** This is the first top-level local the
file has ever had. `tests/config.test.luau` and every service `require()` the module and read the
returned table, so the local is invisible to them, and `check-config.mjs` scans `src/server/` and
`src/client/` only (`check-config.mjs:36`) — `Config.luau` itself is exempt. Step 3.5's
`npm run verify:fast` is the confirmation.

**NOTE — the alias is typed correctly.** `Items.SaltSpawnCount` infers as `number`, so
`Config.Salt.SpawnCount` stays `number` and all five readers are unaffected. Lune resolves this fine;
there is no `require` involved and no Roblox datatype.

#### Step 3.5: The whole-file gate

**File:** `src/shared/Config.luau`
**Verify:** `npm run verify:fast`

Confirms the new top-level `local Items` did not disturb anything that reads `Config.luau`
positionally, and that analyze, `check:remotes`, `check:secrecy` and the toolchain are all still green.

No diff. Run `npm run verify:fast` (~3s), then `npm run verify` (~15s) as the closing gate.

**How to read the closing `npm run verify`:**

- **It should be fully green, `test:unit` included.** Re-read the preamble: this plan does not rename
  `Config.Salt`, so `tests/config.test.luau`'s 82 assertions all still resolve, and every one of them
  was checked by hand against the new values in Step 3.1's table.
- **`docs/BUILD-PLAN.md:191` predicts a red here.** It is predicting the hard-rename branch, which this
  plan did not take because that branch also reds `analyze`. A green `test:unit` is the better outcome,
  not a missed step. Say so in `implementation-log.md` so the auditor does not read it as a skipped gate.
- **If `test:unit` IS red**, the failure is real and belongs to V02. The most likely cause is a typo in
  one of the Step 3.1 values; the second most likely is that `Items` was hoisted below `Config` instead
  of above it, leaving the four aliases `nil`. Do not edit the test.
- `npm run verify` also prints `- candidates: N/15`. That is the lessons ledger, not a V02 failure.

**Manual read-through before closing the phase**, because no command checks it: every number added in
Phase 3 has a comment saying *why it is that value*, not just what it is. That is V02's Done criterion
("§6.5's Config block present with the comment for every number") and the one part of this chunk a
green tree cannot prove.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Magic numbers — the phase's own subject, and `check:config` is a weaker guard than it looks.** It
  scans `src/server/` and `src/client/` only, and it whitelists `0`, `1`, `2`, `-1`, `0.5` and `100` as
  idiomatic. So a v2 number typed into a service as `100` (`Monster.MaxHealth`) or `1`
  (`BuntotPagiSpawnCount`) passes silently. Nothing in V02 does that; V03+ easily could.
- **Nothing was deleted, and four dead tunables remain on purpose.** `Monster.KillCooldown`,
  `Monster.CorpseDuration`'s placement, `Economy.XPSurvivorEscapeBonus` and `Badges.FirstTask` /
  `FirstTaskConversionGate` all describe retired v1.3 systems. Every one has a live reader, so deleting
  any of them reds `analyze` — see the preamble's measurement. All four are in Follow Ups with an owner.
- **Invariant 1 has zero margin.** `25 x 3 = 75 >= 100 - 25 = 75`. This is the single most fragile fact
  V02 introduces and it is unguarded until V11. Commented at `Items.SaltSpawnCount`.
- **Invariants 2-6 all hold with slack**, checked by hand: `FeedDuration 5 > ~0.94s + swing`;
  `SaltThrowRange 25 > KillRange 8`; `GarlicDuration 15 < 300/4 = 75`; `LateInterval 30 < EarlyInterval
  90` and `LateRadius 15 < EarlyRadius 40`; `SaltRevealDuration 10 > SaltStunDuration 4`.
- **Secret leakage — one shape to refuse in a later chunk.** `Config.luau` is in `ReplicatedStorage` and
  is fully readable by any client, which is correct: `ContainerCount`, `SaltSpawnCount` and
  `BuntotPagiSpawnCount` are public facts. What must NOT become public is the container LAYOUT DRAW's
  input. §4.4 (spec line 327) is explicit that a client able to compute where the buntot pagi is before
  the round starts needs no remote to intercept and leaves nothing for `check:secrecy` to see. Seed from
  server-only entropy; `Random.new(roundNumber)` and `Random.new(os.time())` are both fatal.
- **Phase ownership — N/A**, but note for V03+: `Search`, `Tracker` and `Bodies` all imply services that
  must SUBSCRIBE to `RoundService.PhaseChanged` rather than set the phase (§6.4).
- **Player leaving mid-round — named here for the first time.** `Bodies.AfkSeconds` and
  `HuskRelocateAfter` are §6.4's edge cases as numbers. V02 creates no husk; it creates the vocabulary
  the husk chunk needs.
- **Mobile budget.** `Search.ContainerCount = 15` and `Smoke*` are the two entries in this phase with a
  §5 cost attached, and both are paid by a later chunk. `Config.Performance.MaxVisibleLights <= 8` is
  untouched and still pinned by `config.test:142`.
- **Remote direction / rate limiting — N/A.** No remote, no handler.
- **Strict Luau.** The hoisted `local Items` is the only new construct. `stylua.toml` formatting for a
  new top-level local and three new tables is checked by `npm run verify`'s `fmt:check`.
- **Scope.** `bawang`, `buntot pagi`, `camouflage`, `smoke` and `tracker` are all §3 IN-list items
  (spec lines 111-115). Nothing from the OUT list appears.

#### Step 3.6: Pin the four aliases to their canonical source

**File:** `tests/config.test.luau`
**Verify:** `grep -c "is still an alias of" tests/config.test.luau`

**ADDED AFTER THE PLAN WAS WRITTEN, by explicit user decision on Follow Ups Q2.** The alias branch was
chosen over the hard rename, and this step is the condition attached to that choice.

**The hazard this closes, stated precisely.** Step 3.4's aliases are *references* — `SpawnCount =
Items.SaltSpawnCount` — so tuning `Items` genuinely propagates and the comment there is accurate. But
nothing mechanically prevents someone from replacing that reference with a literal (`SpawnCount = 5`)
during an M12 tuning session. It would typecheck, `check:config` exempts `Config.luau` itself
(`check-config.mjs:36`), `analyze` and `lint` would stay green, and the two numbers would silently
diverge — with `Items` reading as canonical while five live modules quietly used the stale copy. That
is the exact silent-drift shape `tests/config.test.luau` exists to catch, and it is unguarded between
V02 and the chunk that deletes the last alias.

**This step ADDS assertions. It does not weaken any.** Step 3.5's "Do not edit the test" instruction
governs *relaxing* an existing invariant to manufacture a green run — that prohibition stands unchanged
and applies to all 82. Appending a new check is the opposite operation.

Append four checks beside the existing salt invariants, each naming both sides so a failure says which
pair drifted:

```lua
check(
	"Config.Salt.SpawnCount is still an alias of Items.SaltSpawnCount",
	Config.Salt.SpawnCount == Config.Items.SaltSpawnCount,
	`Salt.SpawnCount={Config.Salt.SpawnCount}, Items.SaltSpawnCount={Config.Items.SaltSpawnCount}`
)
```

...and the same shape for `StunDuration`/`SaltStunDuration`, `RevealDuration`/`SaltRevealDuration`
and `ThrowRange`/`SaltThrowRange`. **Only those four.** `CarryLimit`, `PickupRangeStuds`,
`ThrowConeDegrees`, `PouchPoolSize` and the three `*Rgb` entries are real values with no §6.5
counterpart — asserting anything about them would be asserting against a table that does not exist.

**Why the gate is a grep and not the suite.** `lune run tests/config.test.luau` alone cannot fail for
this step's reason — the suite passed *before* the step and passes after it, so a bare run is
self-satisfying and proves nothing about whether the work was done. The grep is discriminating in the
right direction: 0 matches before the step exits 1 (FAIL), 4 matches after exits 0 (PASS). **`grep -c`,
not `grep -L`** — measured in both directions, and the inverted-check trap that cost V01 five phases is
documented at `verify-plan.mjs`'s `UNSATISFIABLE`. `verify:plan`'s allowlist accepts no shell operators,
so the two halves cannot be one command.

**Run `npm run verify` after this step regardless.** The grep proves the assertions were added; only the
suite proves they hold. This step edits `tests/`, which is downstream of Step 3.5's whole-file gate, so
that gate is re-run here rather than replaced. The count in the closing `PASS` line moves 82 -> 86, and
that number is a measurement rather than a literal (see the comment at the foot of the file), so it
moves on its own — **if it does not reach 86, a `check(...)` call was malformed and silently skipped.**

**DELETE THESE FOUR CHECKS with the aliases they guard**, in whichever chunk removes each last reader.
A check pinning a field that no longer exists is a compile error in Lune, which is the correct and
noisy failure mode.

---

## 3. Related Files

**Changed by this plan (three, and only three):**

| File | Phase | What changes |
| --- | --- | --- |
| `src/shared/Types.luau` | 1 | +4 exported unions, +1 optional field, A3 block preserved |
| `src/shared/Enums.luau` | 2 | +4 `table.freeze` tables, every value cast |
| `src/shared/Config.luau` | 3 | +1 hoisted local, +3 tables, +6 Monster numbers, 2 value changes, 4 aliases |

### §6.5 field census — what is genuinely new, and what already exists under a v1.3 name

Thirty-six keys in §6.5's block. Full working in `references/MVP-SPEC-review.luau`.

| Category | Count | Keys |
| --- | --- | --- |
| **Genuinely new** | 17 | `Monster.{MaxHealth, WeakenedThreshold, FeedDuration, FeedHeal, SmokeDuration, SmokeRadius}`; all of `Search`; all of `Tracker`; `Bodies.{AfkSeconds, HuskRelocateAfter}`; `Items.{SaltDamage, GarlicSpawnCount, GarlicDuration, BuntotPagiSpawnCount}` |
| **Renamed from a live v1.3 key** | 4 | `Items.Salt{SpawnCount, StunDuration, RevealDuration, ThrowRange}` <- `Salt.{SpawnCount, StunDuration, RevealDuration, ThrowRange}` — **aliased**, Step 3.4 |
| **Moved table, same name** | 1 | `Bodies.CorpseDuration` <- `Monster.CorpseDuration` — **left in place**, Step 3.3 |
| **Value change only** | 2 | `Round.Duration` 420 -> 300; `Round.MaxPlayers` 8 -> 5 — Step 3.1 |
| **Already correct** | 12 | `Round.{Intermission, EndScreen, MinPlayers}`, `Roles.*`, five `Monster.*`, three `Economy.*` |

**Nothing is deleted.** Four tunables in `Config.luau` are dead under v2.0 — `Monster.KillCooldown`,
`Economy.XPSurvivorEscapeBonus`, `Badges.FirstTask` and `Badges.FirstTaskConversionGate` — and every one
has a live reader, so removing any of them reds `analyze`. All four are in Issues Found with an owner.
V01 already removed `Config.Tasks`, `Config.Gate` and `Config.Ghost`; what looks like a leftover at
`Config.luau:113`, `:177` and `:458` is V01's own tombstone prose, and `Trial.TasksToComplete` survives
by V01's explicit decision rather than by oversight.

**Read while planning, not changed** — each has a review in `references/`:

| File | Why it mattered |
| --- | --- |
| `docs/BUILD-PLAN.md:178-192` | V02's Tier/Deps/Done/Verify, and the config-test prediction this plan contradicts with evidence |
| `docs/MVP-SPEC.md` §6.5 (722-761) | The Config block, copied field by field; the six invariants V11 will pin |
| `docs/MVP-SPEC.md` §4.7 + line 52 | Amendment A3 survives intact; corpses, husks, no alive count |
| `src/server/Services/RoundService.luau:616-641` | `buildSnapshot` is per-player `FireClient` — why the carry slot is safe |
| `tests/config.test.luau` | 82 assertions, all passing today; which ones the Step 3.1 value changes touch |
| `.claude/scripts/check-scope.mjs:37-67` | The armed OUT rules and the corpse/husk ALLOW cases |
| `.claude/scripts/verify-plan.mjs:194-200` | `STRICT_MIN_REAL = 0.5`, and every `grep` counts as self-satisfying |

**Not read, and deliberately so:** `src/server/**` beyond `RoundService`'s snapshot builder,
`Remotes.luau`, and the rest of the spec. V02 changes three shared files and declares no network surface.

---

## 4. Follow Ups

### Questions / Clarifications

**1. `docs/BUILD-PLAN.md:191-192` predicts a red `config.test` that this plan does not produce.** The
build plan's V02 **Verify** line says `lune run tests/config.test.luau` "will FAIL until V11 writes the
six invariants". Measured: it PASSES today (82 invariants) and still passes under this plan, because
this plan aliases `Config.Salt` rather than renaming it. The rename branch reds `analyze` too, which
contradicts V02's own **Done** line. **The build plan's Verify line is factually out of date and should
be corrected to "verify green, including test:unit"** rather than planned around. Flagged rather than
silently fixed, per CLAUDE.md's precedence rule.

**2. Is the `Config.Salt` alias the right call, or should V02 take the file-scope hit and rename?** The
alias keeps V02 to three files and `analyze` green. The alternative — rename `Config.Salt.*` to §6.5's
names and update `ItemService`, `TrialService`, `UIController`, `InputController` and
`shared/pure/SaltCarry` in the same chunk — is a mechanical, behaviour-free rename that would leave the
tree in a cleaner state with no indirection, at the cost of a six-file V02 and a red `config.test` until
V11. **Overrule in one line if you want the rename; the plan is written for the alias.**

**3. `MonsterState.Exposed` — latch or state?** §4.3 gates camouflage on "until it has taken a salt hit"
and §4.6 requires the Aswang to be Exposed **and** weakened for the buntot pagi to kill. Both read as a
persistent latch, while `Transformed`, `Feeding` and `Camouflaged` read as mutually-exclusive
activities. If it is a latch, a single `MonsterState` field cannot represent "Exposed and Feeding" and
the state machine needs a flag beside it. **V02 declares the five values the build plan asks for and
takes no position.** The chunk that builds `MonsterService`'s v2 state machine must answer this first.

**4. `RoundResult` is stale and V02 leaves it stale.** `"SURVIVORS_ESCAPED"` names the retired escape
gate, and there is no member for the second win condition (survivors kill the Aswang, §4.6). §4.7 also
flips the meaning of `"TIMEOUT"` — under v2.0 the clock running out is a survivor WIN. Fixing this
touches `RoundService`, `XPCurve`, `BadgeService` and `RoundEndedPayload`, so it is a behaviour change
and out of V02. **Whichever chunk owns the v2 win conditions owns this union.**

**5. `PlayerStats.TasksDone` and the profile migration are not V02's.** §6.6 mandates
`Stats.TasksDone` -> `Stats.ItemsFound` plus a new `Stats.AswangKilled` in the v1->v2 migration, at
`SchemaVersion = 2`. `Types.luau:22` still says `TasksDone`. That is a Types change with live readers in
`ProfileService`/`BadgeService` **and** a DataStore migration path, which makes it a chunk of its own.

**6. `QuickChatPhraseId` is a v1.3 list.** `Types.luau:311-318` still carries `"TASK_HERE"`; §4.5's v2
list (spec line 341) replaces it with "Searching — cover me" and adds "It's the [animal]!" and "I have
the buntot pagi". The last two are load-bearing — spec line 344 says that without the animal call
camouflage is unbeatable. Owned by the quick-chat chunk.

**7. Nothing in `src/` reads `Round.MaxPlayers`.** Step 3.1 changes it 8 -> 5 and only
`tests/config.test.luau` notices. The number that should enforce it is Roblox's `Players.MaxPlayers`,
which lives in the **place file** and is therefore outside Git — so this is a setting somebody has to
change in Studio and publish. Not a plan step, because it is not verifiable from disk.

**8. `check:scope` does not read comments.** Confirmed by running it: green, while `Types.luau:325` and
`:363` contain `GhostService` and `GhostRoster` and the `ghosts?` rule has been armed since V01. It
scans code and **string literals**. Worth knowing before anyone "fixes" those comments or assumes the
check covers prose.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 3 | §6.5 invariant 1 holds with **zero margin** (`25x3 = 75 >= 75`). Any tightening of `SaltDamage` or `SaltSpawnCount` silently kills the second win condition, and nothing guards it until V11 | **High** | Documented in `Items.SaltSpawnCount`'s comment; V11 must pin it |
| 3 | `Monster.KillCooldown = 30` is dead under v2.0 (§4.3: feeding replaced it) but is read by `MonsterService` and pinned by `config.test:238`. Deleting it reds `analyze` | Medium | Deferred to the feeding chunk |
| 3 | `Monster.CorpseDuration` should live under `Bodies` per §6.5; moving it reds `analyze` (`MonsterService.luau:335`, `Types.luau:406`) | Low | Deferred; name unchanged so no alias needed |
| 3 | `Economy.XPSurvivorEscapeBonus = 25` names the retired escape gate; read by `XPCurve` and `config.test:634` | Low | Deferred to the win-conditions chunk (see Q4) |
| 3 | `Badges.FirstTask` / `FirstTaskConversionGate` name the retired task system; §10's launch gate now measures a first *find* | Low | Deferred to the badges chunk |
| 3 | `Duration = 300` sits exactly on `config.test:217`'s `>= 300` floor — zero margin against a debug tweak | Low | Expected; use `Config.Debug`, never `Duration`, for playtest pacing |
| 1 | `ClientRoundSnapshot` gains a field, and Luau accepts an **extra** field on an annotated table silently (measured, `Types.luau:326-353`) | Medium | Argued in Step 1.2; `check:secrecy` green but is a text tripwire only |
| 2 | A missing `:: Types.X` cast inside `table.freeze` is **not** an analyzer error and detonates at the first call site in V03+ | Medium | Step 2.2 greps the cast text; read all nine lines by eye |
| 3 | `check:config` whitelists `0/1/2/-1/0.5/100` as idiomatic, so `MaxHealth = 100` and `BuntotPagiSpawnCount = 1` could be re-typed into a service undetected | Low | Note for V03+; no action in V02 |
