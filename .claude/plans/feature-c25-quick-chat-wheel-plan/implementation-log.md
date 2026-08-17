# Implementation Log — C25 Quick Chat Wheel

Plan: `feature-c25-quick-chat-wheel-plan.md`, 5 phases, 21 steps.

## The decision taken before Phase 1 — the `TextService` conflict

The plan's Follow Up 1 raised a genuine conflict: BUILD-PLAN's C25 row says the broadcast is
"`TextService`-filtered", and the design ships no filter call. **Put to the user, who chose to ship
without the filter.** Recorded here rather than by editing the architect's plan.

The argument, which the user accepted: there is nothing left to filter. The eight phrases are
author-written game copy that never travels — the receiver renders them from an id. The one
user-generated string in the neighbourhood is the accused player's display name, and it is never
transmitted either; the payload carries `TargetUserId` and each client resolves the name locally. A
filter call would be a yielding web request inside an `OnServerEvent` handler on the 🔒 surface,
sanitising a string that was already ours, with a hang as its failure mode.

**This removes a category rather than answering a question**, which is why it is the stronger position.
It also leaves Follow Up 3 (Roblox's policy on display names in custom UI) open and unverified — if
that policy turns out to demand filtering, this is the decision to revisit, and the payload shape
changes with it.

---

## Phase 1: Config, types, and the phrase table — 2026-08-17

**Steps completed:** 1.1, 1.2, 1.3, 1.4

**Files:** `src/shared/Config.luau` (new `QuickChat` block), `src/shared/Types.luau`
(`QuickChatPhraseId`, `QuickChatVerdict`, `QuickChatBroadcastPayload`),
`src/shared/pure/QuickChatPhrases.luau` (new), `tests/quick-chat-phrases.test.luau` (new, 121
assertions).

**Deviations:** none.

**Gate:** `check:config` ok, `analyze` ok, `lint` 0/0/0,
`lune run tests/quick-chat-phrases.test.luau` PASS.

**Notes:** the `{name}` iff assertion is the one worth knowing about — a template carrying `{name}`
for a phrase the server never resolves a target for renders the literal text "It's {name}!" to every
player, and a phrase that needs a target without a slot silently drops the accusation. Neither throws
and neither shows in `analyze`.

---

## Phase 2: The target rule — 2026-08-17

**Steps completed:** 2.1, 2.2, 2.3, 2.4

**Files:** `src/shared/pure/QuickChatTarget.luau` (new), `tests/quick-chat-target.test.luau` (new, 31
assertions), `tests/ghost-chat.test.luau` (+5 C25 cases), `tests/anti-cheat-budgets.test.luau`
(annotation only — C25 adds no up-remote).

**Deviations:**

1. **`QuickChatTarget.nearest` gained a range guard the plan did not specify, because the test I wrote
   for it failed.** With a NaN `maxRangeStuds`, `distance > maxRangeStuds` is false — so a NaN range
   does not refuse everybody as you would expect, it **admits everybody**, and the nearest visible
   player is named regardless of distance. The safe-looking comparison fails open on the one phrase in
   the game that names another player. The guard refuses outright rather than clamping: a range the
   module cannot make sense of means the caller is broken, and naming somebody on a broken input is
   worse than naming nobody.

**Gate:** both Lune suites PASS, `analyze` ok.

**Notes:** the C25 cases live in `tests/ghost-chat.test.luau` deliberately, not in a quick-chat file.
They are not testing quick chat — they pin that quick chat's audience rule IS that sixteen-cell grid
and not a second, subtly different wall. The value is in where they fail: an edit to `shouldDeliver`
for a text-chat reason now names quick chat as the other caller, in the same run.

---

## Phase 3: `QuickChatService` — 2026-08-17

**Steps completed:** 3.1, 3.2, 3.3, 3.4, 3.5

**Files:** `src/server/Services/QuickChatService.luau` (new), `src/server/init.server.luau`
(registration).

**Deviations:**

1. **The raycast filter list is built from the characters that actually exist, rather than cast
   through `:: Instance`.** The plan's sketch passed `sender.Character :: Instance` directly;
   `Player.Character` is `Model?` and is nil for a ghost and during a respawn, and a nil inside
   `FilterDescendantsInstances` throws inside a connection — which Roblox swallows into one warn, and
   the accusation silently stops working for everybody. The analyzer caught the cast.

**Gate:** `analyze` ok, `check:ratelimit` ok, `check:secrecy` ok, `check:remotes` ok (29 declared, 26
wired — both quick-chat remotes now live).

**⚠ For `exploit-auditor`, in priority order:**

- **The `FireClient` loop in `broadcast` is the whole audience rule, and `check:secrecy` structurally
  cannot see it** — a loop over the wrong list is textually identical to one over the right list. The
  state test lives at the fire site, same as `GhostRoster`.
- **`resolveTarget` excludes the sender in the loop, not afterwards.** A sender left in the list is at
  distance 0 with perfect line of sight to themselves and wins every accusation — "It's me!", for
  everyone, always. It throws nothing and `analyze` cannot see it.
- **Line of sight is the anti-oracle defence.** Range alone makes the accusation phrase a through-wall
  proximity radar pollable roughly every two seconds at the shipped budget, and the player who gains
  most is the Aswang mid-hunt. Worth attacking directly.
- Ghosts are refused the accusation because they have no server character, so "nearest" could only
  resolve from the client-reported position `ReportGhostPosition`'s header says the server cannot
  verify.

---

## Phase 4: The wheel — 2026-08-17

**Steps completed:** 4.1, 4.2, 4.3, 4.4

**Files:** `src/client/Controllers/QuickChatController.luau` (the 19-line stub became the controller).
`CONTROLLER_ORDER` needed no change — the stub already sat before `InputController`.

**Deviations:**

1. **The drag is read from `Heartbeat` rather than `InputChanged`.** Touch and mouse then take one
   path, and a drag that leaves the button's own region still tracks. Costs one vector subtraction per
   frame while the wheel is open and nothing while it is closed.

**Gate:** `analyze` ok, `lint` 0/0/0.

**Notes:** the sectors are positioned from `sectorFor`'s own geometry rather than a hand-written table
of offsets, so the hit region and the selection derive from one definition of "where is sector N". A
wheel whose buttons sit where the angle maths does not agree is a wheel that selects the phrase next
to the one you touched — which here means accusing the wrong person.

---

## Phase 5: Edges and the gate — 2026-08-17

**Steps completed:** 5.1, 5.2, 5.4. **5.3 deviated — see below.**

**Files:** `src/server/Services/QuickChatService.luau` (verdict logging at round end, §6.4 edge-case
block), plus the `DeadZonePx` → `DeadRadiusPx` rename across three files.

**Deviations:**

1. **Step 5.3 asked for the `TextService` decision to sit behind a `Config.QuickChat.FilterDisplayNames`
   flag. I did not add the flag.** The user's decision was to ship without filtering, and a Config flag
   that nothing reads is worse than a comment — it advertises a switch that does not exist and invites
   somebody to flip it expecting an effect. The decision is documented at length in the service header
   instead, including what would have to change if the policy answer overrules it.
2. **`DeadZonePx` renamed to `DeadRadiusPx`.** `check:scope` refuses "Zone" — zone-based progression is
   on §3's OUT list because of the competitor's seven zones. `DeadRadiusPx` is also the more accurate
   name: it is a radius.

**Gate:** `npm run verify` **green end to end** — analyze, lint, format, all five checks, `check:debug`,
`check:testcount`, `test:unit` **30 files**, harness.

---

## Not verified, and what would settle it

Nothing in C25 has run in Studio. Six Roblox behaviours the plan flagged as unconfirmed are still
unconfirmed, each with a fallback already named in the code:

| Unconfirmed | Fallback if wrong |
| --- | --- |
| `B` is free of a CoreScript claim (C08 shipped unreachable for exactly this) | rebind |
| A second `createTouchButton` stacks predictably above the salt throw's | hand-placed button in this controller's own ScreenGui |
| A client-created `Part` in `workspace` stays local under `StreamingEnabled` | parent the ping anchor to `Camera` |
| The raycast filter list is sufficient against greybox props and husks | widen the filter |
| Roblox policy on display names in custom UI | the filter path, and a per-recipient payload |
| The wheel is actually thumb-reachable one-handed | Step 5.1 is the plan's one honestly-unverifiable step |

The last one is why Step 5.1 has no `Verify:` line: "is this reachable with one thumb" is answered by
holding a phone, not by running a command.

---

## Review round — 2026-08-17

Three reviewers: `playtester` (live Studio, 3 artifacts), `exploit-auditor` (84/100),
`auditor` (75/100). All findings fixed in one pass.

### Corrections to what this log previously claimed

1. **Phase 1 said "Deviations: none". It was wrong.** Step 1.1's own "Issues identified" block asked
   for `AccuseRangeStuds`'s two bounds to be pinned in `tests/config.test.luau`. I wrote them in prose
   in Config's comment and enforced neither. Prose does not fail a build, and this is exactly the
   silent-invariant failure that file exists for. Now pinned.
2. **I reported `verify:plan` as 20 passed / 0 failed.** A later run gave 18/2, because the debug
   values I set for the playtest made Steps 5.2 and 5.4 fail. True when run, stale within the hour —
   the same mistake as the previous chunk, and I should have caveated the figure rather than repeating it.

### Findings fixed

| # | Finding | Found by | Fix |
| --- | --- | --- | --- |
| 1 | Wheel opened at `{0,0}` for keyboard input — unusable on desktop | playtester, live | `originFor` falls back to `GetMouseLocation()` when the input carries no position |
| 2 | Raycast ignored corpses and husks | exploit | Excluded both, reusing what `MonsterService` settled two milestones ago |
| 3 | A failed accusation was a free silent "is anyone watching me" probe | exploit | Added `AccuseHalfAngleDegrees = 60` and a dot-product facing term |
| 4 | Three comments asserted ghosts have no server character — false since C15 | exploit | Corrected; a ghost's ping now documented as pinging their corpse, deliberately |
| 5 | `LOBBY` was an eligible accusation target but a refused sender | exploit | Target eligibility narrowed to `ALIVE` |
| 6 | `%` in a display name would crash the message render | exploit | `gsub` function-form replacement |
| 7 | `AccuseRangeStuds` bounds unpinned | auditor | Three invariants in `tests/config.test.luau` |
| 8 | Quick-chat budget relationships unpinned | auditor | Two invariants in `tests/anti-cheat-budgets.test.luau` |
| 9 | Header claimed positions were server-*owned* | exploit | Corrected to HOLDS, with the teleport-accuse limit written out |

### The one finding NOT fixed, and why

**A client can accuse anyone by teleporting next to them, accusing, and teleporting back.** Roblox gives
a client network ownership of its own character, so the server's copy of the sender's position is
whatever that client replicated, and nothing in this repo validates character movement.

Not fixed here because **it is not C25's hole**: `RequestKill` and `RequestThrowSalt` already measure
from the same unvalidated position, so a client that can do this can already kill anyone from anywhere.
The real fix is one server-side movement-plausibility gate per character that every distance rule
consults — a cross-cutting change on the 🔒 surface that deserves its own chunk and its own review, not
a corner of C25. The limit is now written out in the service header rather than contradicted by it.

### Also raised, and outside this chunk entirely

`MonsterService` names corpses `Corpse_<userId>` in a public `workspace.Corpses` folder. **Any client
can list that folder and read exactly who is dead**, including bodies nobody has found and bodies that
faded invisible but are deliberately never destroyed. Since the Aswang can never die, every entry
eliminates a suspect. That is the death oracle Amendment A3 deleted a HUD element to close, arriving
through a folder that did not exist when the rule was written. **It deserves its own pass.**

**Gate after all fixes:** `npm run verify` green end to end — analyze, lint, format, all five checks,
`check:debug` (debug values reverted), `check:testcount`, `test:unit` **30 files**, harness.
`tests/config.test.luau` now pins 54 invariants.

### Still unverified in Studio

The review-round fixes changed the wheel origin, the raycast filter and the target allowlist, so the
playtester's session is stale for everything except what it already proved: `B` reaches the handler, the
angle maths is correct, and the round-end verdict log fires. Message rendering, the world ping, the
touch button and the accusation refusal all need a fresh run.
