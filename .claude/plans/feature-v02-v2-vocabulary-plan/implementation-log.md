# V02 — The v2 vocabulary: implementation log

Plan: `feature-v02-v2-vocabulary-plan.md` (3 phases, 12 steps)
Run: `2026-08-27T05-57-31-820Z-V02`

## Two decisions taken before Phase 1, both by the user

**1. `Config.Salt` is aliased, not renamed** (plan Follow Ups Q2). Spec §6.5 names the salt tunables
`Items.Salt*`, but `Config.Salt.*` has live readers in `ItemService`, `TrialService`, `UIController`,
`InputController` and `shared/pure/SaltCarry`. A hard rename reds `analyze`, which V02's own **Done**
line forbids. So `Config.Items` becomes canonical and the four renamed keys become references into it.
The aliases are deleted by whichever chunk rewrites each last reader.

**2. `docs/BUILD-PLAN.md:191` was corrected, not planned around** (Follow Ups Q1). It predicted that
`tests/config.test.luau` would FAIL until V11. Measured before any edit: it PASSED, 82 invariants,
exit 0. The prediction described the hard-rename branch that was not taken. The line now reads
`verify` green, `test:unit` included, with the reasoning kept inline so the next reader does not
re-derive it. **A red `test:unit` in V02 is a real failure, not an expected one.**

**One step was added to the plan before binding:** Step 3.6, pinning each alias to its canonical
source. It is the condition attached to decision 1 — see that step for the drift it closes.

---

## Phase 1 — Types: the four unions, the carry slot, Amendment A3 held in place

**Status: complete, gates green.**

| Step | Change | Check | Result |
| --- | --- | --- | --- |
| 1.1 | `ItemType`, `MonsterState`, `BodyKind`, `CamouflageForm` added after `RoundResult` | `grep -qE '^export type MonsterState = '` | exit 0 |
| 1.2 | `YourCarriedItem: ItemType?` added to `ClientRoundSnapshot` | `npm run check:secrecy` | ok |
| 1.3 | Amendment A3 block preserved; one v2 paragraph appended | `grep -q 'SurvivorsRemaining'` | exit 0 |

Phase gate: `npm run verify:fast` — analyze ok, remotes ok (22 declared, 22 wired), secrecy ok.

**All four unions are `export type`.** A plain `type` compiles here and fails from `Enums.luau` with
`Unknown type 'X'`; Phase 2 is where that would surface.

**On Step 1.3.** The A3 comment was edited by *appending only* — the forbidden-name list
(`SurvivorsRemaining`, `DeadCount`, `RosterSize`) is untouched. The appended paragraph records why v2.0
strengthens the prohibition rather than relaxing it: `MaxPlayers` 8 -> 5 makes a count narrow the field
twice as fast, and since the Aswang must now kill everyone (§4.1), an alive count would double as a
live progress bar on its win condition.

**What Step 1.2's green check does NOT prove.** `check:secrecy` matches role tokens in payload fields;
`YourCarriedItem` contains none, so it passes trivially. The real defence is structural: the snapshot is
built per player and sent with `:FireClient`, and the field is `nil` for the Aswang and for an
empty-handed survivor alike — indistinguishable. Also noted at `Types.luau`: the analyzer accepts an
**extra** field on an annotated table silently, so the type is documentation plus two-thirds of a guard.

---

## Phase 2 — Enums: the four frozen tables, every value cast

**Status: complete, gates green.**

| Step | Change | Check | Result |
| --- | --- | --- | --- |
| 2.1 | `Enums.ItemType` (3), `Enums.BodyKind` (2) | `npm run check:scope` | ok, 19 shapes watched |
| 2.2 | `Enums.MonsterState` (5), `Enums.CamouflageForm` (4) | `grep -qE '"CAMOUFLAGED" :: Types\.MonsterState'` | exit 0 |
| 2.3 | none — proves every cast resolves | `npm run analyze` | ok |

**All 14 values were read by eye, as the step demands.** The plan says "nine"; the actual count is
**14** (3 + 2 + 5 + 4). Every one carries a `:: Types.X` cast and every cast target matches its own
table — checked by listing all 14 value lines together rather than by scanning the diff, because an
uncast `Salt = "SALT"` inside `table.freeze` is **not** an analyzer error. It infers as plain `string`
and detonates later at the first call site in V03+, which is precisely the class of defect neither
Step 2.2's grep nor Step 2.3's analyze catches on its own.

`Weakened` was deliberately NOT added to `MonsterState`. It is a health predicate
(`health <= Monster.WeakenedThreshold`), and duplicating it as an enum member creates two sources of
truth for one fact.

---

## Phase 3 — Config: spec §6.5's v2 block, one comment per number

**Status: complete, gates green.**

| Step | Change | Check | Result |
| --- | --- | --- | --- |
| 3.1 | `Duration` 420 -> 300, `MaxPlayers` 8 -> 5 | `grep -qE 'MaxPlayers = 5,'` | exit 0 |
| 3.2 | `MaxHealth`, `WeakenedThreshold`, `FeedDuration`, `FeedHeal`, `SmokeDuration`, `SmokeRadius` | `npm run check:config` | ok |
| 3.3 | `Search`, `Tracker`, `Bodies` — 8 numbers | `npm run lint` | 0 warnings, 0 parse errors |
| 3.4 | `local Items` canonical + 4 `Config.Salt` aliases | `grep -qE 'BuntotPagiSpawnCount = 1,'` | exit 0 |
| 3.5 | none — whole-file gate | `npm run verify` | fully green |
| 3.6 | 4 alias-pin assertions | `grep -c "is still an alias of"` | 4, exit 0 |

### The closing gate, in full

`npm run verify`: analyze ok · remotes ok (22/22) · secrecy ok · config ok · scope ok (19 shapes) ·
ratelimit ok · **test:unit 28 files ok** · lint 0 warnings.

**`config: 86 balance invariants`, up from 82.** That is the four Step 3.6 assertions, and the count is
the plan's own detector for a malformed `check(...)` silently not registering — it is a measurement
rather than a literal (see the comment at the foot of `tests/config.test.luau`). Reaching exactly 86
proves all four registered. `xp-curve` independently reports `337s/round`, matching Step 3.1's predicted
25 + 300 + 12.

**A green `test:unit` here is the correct outcome, not a skipped gate.** `docs/BUILD-PLAN.md:191`
predicted a red, was measured wrong before V02 started, and was corrected — see the decisions at the top
of this log. An auditor reading the old prediction should read the corrected line instead.

### One transient failure, and why it was expected

Adding `local Items` before wiring it in tripped the PostToolUse analyze gate:
`LocalUnused: Variable 'Items' is never used`. That is Step 3.4 observed mid-step — the local is
declared in the first half and consumed in the second. Resolved by the alias wiring, no fix required.

### Three things V02 deliberately did NOT do

- **`Monster.KillCooldown = 30` kept**, with a tombstone comment. §4.3 supersedes it outright, but
  `MonsterService` reads it and `config.test:238` pins it; deleting it reds analyze AND test:unit.
- **`Monster.CorpseDuration = 45` left in place**, with a comment saying §6.5 files it under `Bodies`.
  The name does not change, so no alias is warranted and a reader finds it either way. Moving it reds
  analyze (`MonsterService.luau:335`, `Types.luau:406`).
- **`Bodies` built without `CorpseDuration`**, following from the above.

### Zero-margin numbers, both flagged at the number itself

1. **§6.5 invariant 1 holds with EQUALITY**: `SaltDamage x (SaltSpawnCount - 1) = 25 x 3 = 75`, and
   `MaxHealth - WeakenedThreshold = 100 - 25 = 75`. Survivors can weaken the Aswang only if every pouch
   but one connects. Tightening either number silently makes the second win condition unreachable.
   **Nothing guards this until V11** — the comment in `Items` is the only guard today.
2. **`Duration = 300` sits exactly on `config.test:217`'s `>= 300` floor.** Any debug lowering of
   `Duration` turns the suite red, which is correct behaviour. Use `Config.Debug` for playtest pacing,
   never `Duration`.

### Plan gate

`npm run verify:plan` — **12 passed, 0 failed, 0 unverifiable.** Checks: 6 discriminating,
0 file-exists, 6 self-satisfying.

---

## Audit response

`auditor` ran static-only (no runtime path exists for this chunk). **12/12 steps traced to a
`file:line`; no undocumented deviations.** It independently re-ran `verify`, `verify:plan` and
`verify:plan --lint` rather than quoting this log, and independently counted the 14 enum casts,
confirming each targets its own table with none cross-wired.

**Its score is internally inconsistent and both figures are recorded here rather than one being
chosen:** the heading says **62/100**, the scoring table totals **75/100**. The gap is not material to
the findings — both land in the band CLAUDE.md predicts for an audit with no runtime evidence — but the
report contradicts itself and should not be cited as a single number.

**One finding acted on.** `GarlicSpawnCount = 2` carried no number-specific justification, while its
sibling `GarlicDuration` carried invariant 4. V02's Done line requires a comment for every number, so
this was a real gap rather than a style note. Fixed at `Config.luau:57-64`: two is the middle term of
the item economy (4 salt / 2 bawang / 1 buntot pagi across 15 containers), and the count is what keeps
garlic a choice rather than a supply — one would make finding it decisive, three approaches the safe
room §3 forbids. **No §6.5 invariant pins it**, which is stated in the comment so V16 can re-open it.

Re-ran after the fix: `verify` fully green, `config: 86 balance invariants`, `verify:plan` 12/12.
`artifacts/verify-output.txt` recaptured. **No re-review was requested for this change** — it adds a
comment and no code, so a second full review round would cost 150-250k tokens to re-read an unchanged
implementation.

**One finding recorded, not acted on.** Six of twelve plan checks are `[self]` — a grep for text the
step itself writes. The auditor closed that gap by reading every diff hunk directly, and flags it so a
future auditor does not over-trust a green `verify:plan` on those six steps. `--lint` independently
reports 0 shared and 0 unsatisfiable, so the checks are weak in isolation rather than degenerate.
