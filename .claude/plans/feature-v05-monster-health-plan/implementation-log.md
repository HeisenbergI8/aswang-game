# Implementation Log — V05: Monster Health, Exposed and Weakened

## Phase 1: The health model as a pure function — 2026-08-27

**Steps completed:** 1.1, 1.2, 1.3
**Files changed:** `src/shared/pure/MonsterHealth.luau` (new), `tests/monster-health.test.luau` (new)
**Deviations from plan:** none. Both files written as specified in the plan's diffs; StyLua reflowed
two `check(...)` calls onto one line (the `salt hit {hit} never breaks the floor` call and the
`twenty salt hits` call), which is formatting only.
**Gate:** `lune run tests/monster-health.test.luau` 243/243 · `npm run fmt:check` PASS ·
`npm run test:unit` 32 files ok · `npm run verify:fast` analyze/remotes/secrecy ok
**Notes:** The four Config numbers the cross-check reads all exist and are where the plan said —
`Config.Monster.MaxHealth/WeakenedThreshold/FeedHeal` and `Config.Items.SaltDamage` (the canonical
block, not the `Config.Salt` alias). Nothing in this phase touches an Instance or a remote.

## Phase 2: Config, and the invariant that goes silent — 2026-08-27

**Steps completed:** 2.1, 2.2, 2.3
**Files changed:** `src/shared/Config.luau`, `tests/config.test.luau`
**Deviations from plan:** none in content. Step 2.1's Config addition and Step 2.3's three pins are
the same three checks — the plan describes them in both places, so they were written once. Five new
checks total, matching the plan's own count in Phase 2's Potential Issues.
**Gate:** `lune run tests/config.test.luau` PASS, 116 balance invariants (was 111) ·
`npm run fmt:check` PASS · `npm run verify:fast` analyze/remotes/secrecy ok
**Notes:** §6.5 invariant 1 is now asserted rather than commented. It holds with **zero margin** at
the shipped numbers (25 x 3 = 75 = 100 - 25), so any balance pass that moves `MaxHealth`,
`WeakenedThreshold`, `SaltDamage` or `SaltSpawnCount` will red this check — that is the intent.
`FeedHeal <= SaltDamage` is an inference from §4.6's "heals away one salt hit", not a quoted §6.5
line; the plan flags it for argument rather than inheritance.

## Phase 3: Health lives in `MonsterState`, server-only — 2026-08-27

**Steps completed:** 3.1, 3.2, 3.3
**Files changed:** `src/server/Services/MonsterService.luau`
**Deviations from plan:** none. `IsWeakened` and `HealFromFeed` were written in the opposite order to
the plan's step numbering (both land in the same block beside `IsTransformed`); no content differs.
**Gate:** `npm run analyze` ok · `npm run check:secrecy` ok · `npm run verify:fast` all green
**Notes:**
- `MonsterHealth.HealthEvent` as a scalar parameter type passed `analyze` with no cast, as the plan
  predicted from `pure-module-unions-widen-in-lists`. No fallback to `string` was needed.
- Step 3.1's check-only item is confirmed: `onPlayerRemoving` (line ~1053) does
  `monsters[player.UserId] = nil`, so `Health` leaves with the entry. No edit made.
- Two `table.clear(monsters)` calls exist — `onPhaseChanged` (~1011) and `Init` (~1172) — matching
  the plan's note. No third reset added.
- `HealFromFeed` is deliberately unwired until V06 and `IsWeakened` until V08. Neither reds the tree.
- Mid-phase the analyze hook fired three times on incomplete state (`HEALTH_TUNING` unused, then
  `MonsterState` missing `Health`, then `applyHealthEvent` unused). All were the phase in flight and
  all cleared as the consumers landed; the phase gate is green.

## Phase 4: `Exposed` — the latch, the expiry, and the glow that reads health — 2026-08-27

**Steps completed:** 4.1, 4.2, 4.3, 4.4
**Files changed:** `src/server/Services/MonsterService.luau`, `src/server/Services/ItemService.luau`
**Deviations from plan:** none.
**Gate:** `npm run verify` FULL GREEN — analyze ok · remotes ok (26/26) · secrecy ok · config ok ·
scope ok · ratelimit ok · test:unit 32 files ok · lint/fmt clean
**Notes:**
- `ForceRevert` deleted and replaced by `ApplySaltHit`, as the plan directed. Its only caller
  (`ItemService.applyHit`) now calls the new seam. `grep -rn ForceRevert src/` returns **one** hit and
  it is prose inside `ItemService.applyHit`'s C14 history comment, not a call.
- All five `clearReveal`/`applyReveal`/`RevealState` code sites are gone; the one surviving grep hit
  is prose in `MonsterService`'s `applyExposed` header crediting where the code came from.
- The `FillTransparency = 0.6 -- config-ok` waiver is deleted rather than moved; `check:config` is
  green with the ramp read from `Config.Monster.ExposedGlowTransparency*` instead.
- `ItemService`'s `rgb` helper still has two pouch callers (lines ~203, ~237), so deleting
  `applyReveal` did not orphan it — the plan flagged this to confirm rather than assume. Confirmed.
- The four reveal exits are all re-homed: phase-change-out-of-ACTIVE (in the existing `onPhaseChanged`
  revert loop, before `table.clear`), `CharacterRemoving` (new connection in `onPlayerAdded`),
  `PlayerRemoving` (already nils the entry, no edit), and the ten-second `task.delay` expiry.
- `revert()` deliberately received **no** `clearExposed` call — a revert is instant and the glow is
  ten seconds, so folding them would delete the window V08's buntot pagi needs.

## Phase 5: The seams V06 and V08 will call, and the leak sweep — 2026-08-27

**Steps completed:** 5.1, 5.2. **5.3 is the `playtester`'s** — handed off, not implemented here.
**Files changed:** `src/server/Services/MonsterService.luau` (header only)
**Deviations from plan:** none.
**Gate:** `npm run verify` FULL GREEN · `npm run verify:plan` 12 passed, 0 failed, 4 unverifiable
(3 steps share a check with an earlier step, and 5.3 is the Studio confirmation with no automated
gate — both accounted for in the plan itself)
**Notes:**
- `Remotes.luau` has no diff across the entire plan, as Phase 5's Potential Issues required.
  `check:remotes` still reports 26 declared / 26 wired.
- V05 adds a number and sends nothing: no remote, no attribute, no tag, no payload field, and
  nothing written to `Humanoid.Health` or `Humanoid.MaxHealth`.
- Step 5.2 is a handoff, not an edit. The `exploit-auditor` brief it specifies is used verbatim.

## Post-review fixes — 2026-08-27

Applied after `auditor` (86/100), `exploit-auditor` (78/100) and `playtester` reported.

**Files changed:** `src/server/Services/MonsterService.luau`, `src/server/Services/ItemService.luau`,
`src/shared/Config.luau` (debug revert only)

### 1. The `PlayerRemoving` exit was genuinely lost (exploit-auditor, High) — FIXED

`onPlayerRemoving` nilled the entry without destroying the Highlight. I confirmed the exploit path
independently before accepting it: `RoundService.onPlayerRemoving` reparents the character to
`workspace.Husks` as `Husk_{userId}` with the glow attached, and `RoundService` starts last (it is 9th
of the listed services; `MonsterService` is earlier) — so this handler runs first and the husk is built
after the handle is gone. All four exits then miss it.

**CORRECTION, from the exploit-auditor's re-check:** an earlier draft of this entry said
"`MonsterService` is index 29 in `SERVICE_ORDER`". 29 is a LINE NUMBER in `init.server.luau`, not an
index. More importantly the ordering premise is no longer load-bearing: `clearExposed` holds a direct
`Instance` reference and never reads `player.Character`, so **the leak is closed in either handler
order** — if `RoundService` ran first, the husk would be built with the glow and `clearExposed` would
destroy that same instance out of the husk. Order-independent is a stronger property than the one this
fix was designed for, and V06/V08 should rely on that rather than on service order.

**`onPlayerRemoving` now calls `clearExposed(player.UserId)` before nilling.**

**CORRECTION TO PHASE 4'S ENTRY IN THIS LOG.** It claimed all four reveal exits were re-homed and that
`PlayerRemoving` needed no edit. That was false. The plan specified it that way and I implemented it
faithfully, then repeated its claim as verified fact. The old `ItemService.clearReveal` destroyed *the
instance it held*, which works after the character is gone; nilling a table entry does not. Two
comments asserting the non-existent exit are corrected (`ItemService` ~line 643, `MonsterService`'s
`onPhaseChanged` clear block).

### 2. `refreshExposedGlow` was never called on a heal (exploit-auditor, Low) — FIXED

`applyHealthEvent` now repaints the glow after every health write, so V06's `HealFromFeed` cannot
leave a stale brightness for the rest of an Exposed window.

**This fix introduced a second bug, which `analyze` caught before it could ship:** `refreshExposedGlow`
was declared 39 lines *after* `applyHealthEvent`, and Lua resolves a `local function` only from its
declaration onward — so the call was a nil GLOBAL and would have errored on the first salt hit. The
function is moved above `applyHealthEvent` with a comment recording why the order is load-bearing. No
Lune test would have caught this; it is not reachable from a pure module.

### 3. Debug values reverted

All six (`Intermission`, `Duration`, `EndScreen`, `SoloTesting`, `VerboseLogging`,
`ForceAswangWhenSolo`). `git diff src/shared/Config.luau` now shows only the two
`ExposedGlowTransparency*` additions. `check:debug` ok.

**Gate after all fixes:** `npm run verify` FULL GREEN — analyze · remotes 26/26 · secrecy · config ·
scope · ratelimit · debug · test:unit 32/32 · lint · fmt. `verify:plan` 12 passed / 0 failed /
4 unverifiable. `goal-check` DONE, 5 of 5 artifacts cited.

### Not fixed — needs a decision

**The `SaltReveal` Highlight is enumerable by any client via `workspace:GetDescendants()`**
(exploit-auditor, Critical). `DepthMode = Occluded` governs rendering, not replication. The shape
predates V05 (it shipped at C14 in `ItemService.applyReveal`); what V05 added is that
`FillTransparency` now maps one-to-one onto health, so an executor reads the exact moment `IsWeakened`
flips. The structural fix is a remote-driven client-side effect with a server-computed audience —
a design change outside V05's scope. **Raised to the user; not actioned.**
