# Verification: V10 — the buntot pagi strike

**Date:** 2026-09-01
**Scope:** `.claude/plans/feature-v10-buntot-pagi-plan/` (all 4 phases, per `implementation-log.md`) —
`src/shared/pure/StrikeValidation.luau` (new), `tests/strike-validation.test.luau` (new),
`src/shared/Config.luau`, `src/shared/Types.luau`, `src/shared/Remotes.luau`,
`src/shared/pure/ItemUse.luau`, `src/server/Services/MonsterService.luau`,
`src/server/Services/ItemService.luau`, `src/client/Controllers/InputController.luau`,
`tests/config.test.luau`, `tests/item-use.test.luau`, `tests/anti-cheat-budgets.test.luau`.
**Rojo serving:** yes — `npm run rojo:status` verdict `ok`, session `fc42e0d0`, BLESSED (proven-syncing).
Confirmed `ReplicatedStorage.Shared.pure.StrikeValidation` exists in the live Studio tree before
trusting anything (`search_game_tree`, Edit datamodel).
**Studio reachable:** yes — one Studio instance (`aswang.rbxl`), attached, Play mode driven via MCP.
**SoloTesting:** on (coordinator-set, coordinator owns revert) — `Config.Debug.SoloTesting = true`,
`Config.Debug.VerboseLogging = true`, `Config.Round.Intermission = 15`, `Duration = 90`,
`EndScreen = 6`, `Config.Items.SaltDamage = 75`. **`Config.Debug.ForceAswangWhenSolo` was left at its
committed value (`false`).** That turned out to be load-bearing — see Q1 below.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | part of `npm run verify`, exit clean before the two known-red debug findings |
| remotes | PASS | 35 declared, 35 wired |
| secrecy | PASS | "the Aswang stays server-side" |
| config | PASS | "balance stays data-driven" |
| scope | PASS | 19 out-of-scope shapes watched |
| ratelimit | PASS | every `OnServerEvent` consults `AntiCheatService` |
| debug | **FAIL (expected)** | `Debug.SoloTesting = true`, `Debug.VerboseLogging = true` — both are the
  coordinator-set values for this session, not a defect. Coordinator owns the revert. |
| unit (Lune) | 57/58 files PASS | `tests/strike-validation.test.luau` PASS, 46,112 checks. The one
  failing file is `tests/config.test.luau`, and it fails on exactly the two checks the brief predicted:
  "solo testing is off" and "a round is long enough to actually be played" (Duration=90 vs a 300s
  floor). Both are the debug values doing their job, not a finding. |
| behavioural | **PARTIAL** | see below — artifacts in `artifacts/` |

## Behavioural verification

**Round state confirmed via console** (`Debug.VerboseLogging` lines), not via `execute_luau` reading a
live service — per the known `execute_luau` limitation, `require(...)`-ing a running service from a
fresh script context returns an un-`Init()`'d copy. `[RoundService] -> ACTIVE (90s)` and the client's
own `Snapshot` lines are what the phase claims below rest on.

### Q1 — Does the strike kill? **NOT REACHABLE this session, and it is a Config gap, not a code defect.**

**Finding: with only `Debug.SoloTesting = true` (and `ForceAswangWhenSolo` left `false`), a solo round
draws ZERO Aswangs, every round, deterministically — not randomly.** Confirmed two ways:

1. **By reading the code.** `src/server/pure/RoleDraw.luau:108`:
   `local picks = math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))`. With exactly one candidate,
   `#candidates - 1 == 0`, so `picks = clamp(1, 0, 0) = 0`. The comment above it states the intent
   directly: "Never draw every candidate as the Aswang: a round with no survivors is over before it
   starts." `RoleService.luau:178-184` only overrides this when
   `RunService:IsStudio() and Config.Debug.SoloTesting and Config.Debug.ForceAswangWhenSolo and
   #candidates <= Config.Round.MinPlayers` — the third condition is the flag that was NOT set for this
   session.
2. **By observing three consecutive solo rounds.** Every round's HUD read `SURVIVOR` (screenshots
   `v10_round_start.png`, and the search screenshots below), never `ASWANG`, and the console never
   printed `[RoleService] DEBUG — Aswang FORCED to ...` — the warn line that fires ONLY on the forced
   path (`RoleService.luau:221-224`). Its absence across every round is the confirming negative.

This makes Q1 unreachable **regardless of how long the session runs** — every subsequent solo round
draws the same way, deterministically zero Aswangs, until either `Config.Debug.ForceAswangWhenSolo` is
set to `true` (which the implementation log's own Phase 3 note says is deliberately supported: "The
Aswang can strike itself, and that is deliberate" — `ResolveStrikeTarget`'s header) or a second Studio
client joins as a real second player.

**What is needed to close Q1:** `Config.Debug.ForceAswangWhenSolo = true` for one more session (self-
strike path), or a two-client Test session (Test → Clients and Servers → 2) for a strike on a second
player. Neither is something I can set or drive — the first is a `Config.luau` edit I am blocked from
making, the second is a Studio UI action no agent can drive (per `playtester.md`).

**Not filed as a Critical finding** because the mechanism `RoleDraw.draw` implements ("never draw every
candidate as the Aswang") is correct and load-bearing in production, where `#candidates >= MinPlayers`
so the branch it changes behaviour on cannot occur outside `IsStudio()`. It is purely a solo-testing
config gap for THIS chunk's verification, not a shipped-code defect.

### Q2 — Does a second swing (after the item is gone) do nothing?

NOT YET ESTABLISHED — depends on first landing Q3 (below), which was still in progress (searching for
the one buntot pagi in the barrio, `Config.Items.BuntotPagiSpawnCount = 1`) when this file was written.
Six of fifteen containers tried across two Play sessions so far, all salt/bawang/empty:
`Container_Plaza_Crate` (salt), `Container_StallNW_Goods` (empty), `Container_KuboNW_Chest` (salt),
`Container_KuboNE_Sack` (bawang), `Container_StallNE_Goods` (salt), `Container_KuboN_Drum` (empty).
Continuing.

### Q3 — Does a refused swing (nothing in reach) still spend the item?

NOT YET ESTABLISHED — same blocker as Q2: no buntot pagi in hand yet.

### Q4 — Does it drop where the carrier falls?

NOT YET ESTABLISHED.

## Not Verified

- **Q1 (kill).** Blocked on `Config.Debug.ForceAswangWhenSolo` (or a second client). See above — this is
  the primary finding of this pass.
- **Q2, Q3, Q4** — in progress; this file will be updated as the search continues.
- **That a refused strike is indistinguishable to a SECOND observer.** Cannot be established solo,
  regardless of any Config value — needs a second connected client. Named explicitly so it is not
  mistaken for something this pass covered.
