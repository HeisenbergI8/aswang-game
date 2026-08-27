# Verification: V05 — the Aswang's server-only health and the Exposed glow

**Date:** 2026-08-27
**Scope:** V05 only. Files: `src/server/Services/MonsterService.luau`,
`src/server/Services/ItemService.luau`, `src/shared/pure/MonsterHealth.luau`,
`src/shared/Config.luau`. Plan phases loaded: Phase 4 (`applyExposed`/`clearExposed`/
`ApplySaltHit`/`IsExposed`) and Phase 5 (seams doc + Step 5.3's Studio ask).
**Rojo serving:** yes — `preflight -- --studio` reported `rojo-serve` / `rojo-attached` /
`rojo-synced` all green this session. Only `clean-tree` failed, expected (uncommitted V05 work).
**Studio reachable:** yes — `aswang.rbxl` open, confirmed via `get_studio_state` before trusting
any observation.
**SoloTesting:** on, set by the coordinator before this run (`Round.Intermission=8`,
`Duration=20`, `EndScreen=6`, `Debug.SoloTesting=true`, `VerboseLogging=true`,
`ForceAswangWhenSolo=true`). Not reverted by me — the coordinator owns the revert, per brief.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` — 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | `npm run lint` exit 0, `npm run fmt:check` exit 0 |
| repo checks | PASS (4/5) | `check:remotes` ok (26/26), `check:secrecy` ok, `check:config` ok, `check:scope` ok, `check:ratelimit` ok. `check:debug` FAILS on exactly the 3 coordinator-set switches (SoloTesting, VerboseLogging, ForceAswangWhenSolo) — expected, not reverted by me |
| unit (Lune) | PASS (31/32 files) | `npm run test:unit` — `tests/monster-health.test.luau`: **243/243** checks passed. The one failing file is `tests/config.test.luau`, which fails on the same 3 debug values above plus a 4th derived assertion (round-too-short) and a 5th (session-retry timing) — all a direct, expected consequence of the coordinator's debug Config, not a defect |
| behavioural | PARTIAL — see per-question breakdown below | `artifacts/console-full-round-cycle.txt`, `artifacts/config-and-math-check.txt`, `artifacts/salt-self-target-blocked.txt`, `artifacts/synthetic-glow-visual-check.txt`, `artifacts/static-checks.txt` |

## Behavioural verification, against the four questions in priority order

### 1. Does the glow brighten across successive salt hits?

**NOT VERIFIED through real gameplay.** I could not land a real `ApplySaltHit` on the Aswang at
all this session. Solo, `Config.Debug.ForceAswangWhenSolo` forces the only player present to be
the Aswang, and `ItemService.luau:528` (`resolveThrow`) unconditionally excludes
`candidate == thrower` — a thrower can never target themself, with no debug override. There is no
bot/dummy/NPC anywhere in this codebase to substitute a second body (grepped and confirmed empty
in `artifacts/salt-self-target-blocked.txt`), and driving a second Studio client is a UI action
(Test > Clients and Servers) this agent cannot perform. I did **not** attempt to route around this
by calling `MonsterService.ApplySaltHit` through a fresh `execute_luau`-required copy of the
module, because that copy's `monsters` table is empty (un-`Init()`'d) and the call would silently
no-op rather than exercise anything real — and calling `Init()`/`Start()` on a fresh copy first
risked double-registering the live session's remote connections for the rest of the run. Both
reasoned through explicitly in `artifacts/salt-self-target-blocked.txt` rather than tried and
walked back.

What I did establish, as secondary/partial evidence, **not a substitute for the above**:

- The real pure-module math (`ReplicatedStorage.Shared.pure.MonsterHealth.weakenedFraction`),
  evaluated live in Studio against this tree's actual Config values, produces
  `FillTransparency` 0.583 -> 0.417 -> 0.250 across hits 1/2/3 — monotonically more opaque
  (brighter). See `artifacts/config-and-math-check.txt`. This is the same math
  `tests/monster-health.test.luau` already covers 243/243 in Lune.
- A **synthetic** Highlight (not created via `ApplySaltHit` — manually built with the exact
  production property values: same colors, same `DepthMode`) at 0.583 then 0.417 on the real,
  live Aswang character, viewed directly in two `screen_capture` calls: the 0.417 shot read
  visibly brighter/whiter than the 0.583 shot on the same character. Described in detail (values,
  camera, what was seen) in `artifacts/synthetic-glow-visual-check.txt`, since the image bytes
  themselves cannot be persisted to disk in this environment (confirmed by filesystem search; a
  prior session, `c26-verification`, hit and documented the same limitation).

**Confidence: low.** The math is right (Lune-proven) and a manual reproduction of the two lower
transparency values was visibly distinguishable, but the actual `ApplySaltHit` control flow —
does a real hit really decrement Health, really call `refreshExposedGlow`, really update the
*same* Highlight instance the player is looking at — was never exercised.

### 2. Does the glow disappear ~10s after the last hit?

**NOT VERIFIED.** Same root cause: no real hit landed, so the real generation-guarded
`task.delay(Config.Items.SaltRevealDuration, ...)` in `applyExposed`
(MonsterService.luau:583-596) was never scheduled. My synthetic Highlight was created directly
(no `task.delay` attached to it at all), so letting it "expire" would prove nothing about the
real timer or the generation guard that protects it from a second hit landing mid-window.

### 3. Does a full round cycle produce no error from the expiry `task.delay` firing after a phase change cleared the state?

**PARTIALLY VERIFIED, with the specific scenario NOT covered.** I captured console output across
**9 consecutive round transitions** (INTERMISSION -> STARTING -> ACTIVE -> ENDING ->
INTERMISSION, repeated 9 times) plus one full transform+revert cycle, with **zero errors,
warnings, or stack traces** — full transcript in `artifacts/console-full-round-cycle.txt`. This is
real evidence that `MonsterService.onPhaseChanged`'s `table.clear(monsters)` and the general
phase-transition machinery are stable under repeated cycling.

What it does **not** cover: since no real salt hit occurred, `MonsterService`'s own Exposed
expiry `task.delay` was never actually scheduled during these 9 cycles, so the specific race this
question asks about — the timer firing *after* a phase change already cleared `monsters[userId]`
— was not exercised. The code's own guard against it
(`if current == nil or current.ExposedGeneration ~= generation then return end`,
MonsterService.luau:591) was read and is structurally sound, but reading a guard is not the same
as watching it fire correctly against a live race.

**Confidence: medium** for general round-cycle stability (directly observed, repeated 9 times,
zero errors); **not verified** for the specific expiry-after-clear scenario.

### 4. Does the glow render through walls?

**Static: PASS. Live-visual: NOT ESTABLISHED (inconclusive attempt, not a negative finding).**
`MonsterService.luau:571` in the shipped file (read directly, not the plan's diff) sets
`glow.DepthMode = Enum.HighlightDepthMode.Occluded`, matching Step 4.1 exactly — see
`artifacts/static-checks.txt`. The coordinator additionally reports `exploit-auditor` already
confirmed this at the code level.

I attempted an independent visual confirmation in Edit mode (a Part+Highlight at
`FillTransparency = 0.25` behind a constructed wall vs. in clear line of sight) and it was
**inconclusive**: neither shot showed any visible glow at all, including the clear-line-of-sight
control, whereas the earlier Play-mode shots on the real character clearly did render the
Highlight. The simplest explanation is that this Studio session's Edit-mode capture does not
composite Highlight adornments the way Play-mode rendering does — not a code defect. Full
description and both temporary test instances' cleanup confirmation in
`artifacts/synthetic-glow-visual-check.txt`. I am not counting this attempt for or against the
through-walls behaviour; the static source read is the evidence for question 4.

## Cross-reference (not a new finding — coordinator-supplied, independently re-traced)

While reading `MonsterService.luau` for the above, I re-traced the defect the coordinator says
`exploit-auditor` already found and is fixing: `onPlayerRemoving`
(`MonsterService.luau:1241-1243`) sets `monsters[player.UserId] = nil` without calling
`clearExposed` first, unlike the correct `CharacterRemoving` handler six lines above it
(`MonsterService.luau:1228-1230`). Traced consequence: a disconnecting Exposed Aswang's Highlight
is neither destroyed immediately nor later by the expiry timer (which declines once
`monsters[userId]` is `nil`), leaving a glowing Husk for the rest of the round. Full trace in
`artifacts/static-checks.txt`. Not independently verified live (would need a second client to
disconnect while Exposed) — offered only as a file:line cross-check of the coordinator's report.

## Not Verified

- **Real `ApplySaltHit` control flow** (revert -> damage -> expose, in order) — blocked by solo
  self-targeting exclusion; needs a second Studio client (Test > Clients and Servers, a human
  action) or a non-solo playtest.
- **The Exposed glow's 10s expiry timer**, and specifically the generation guard protecting a
  second hit's window from an earlier hit's timer — same blocker.
- **The phase-change-clears-mid-expiry race** named in question 3 — same blocker; general
  round-cycle stability is verified, this specific interleaving is not.
- **Through-walls occlusion, visually** — code-level confirmed (static read + coordinator's
  exploit-auditor report); my own visual attempt was inconclusive due to an apparent Edit-mode
  capture limitation, not retried in Play mode before this report was prioritized.
- **The `onPlayerRemoving` leak's live behaviour** — traced statically, not reproduced (needs a
  second client disconnecting mid-Exposed).

All four gaps above share one root cause: this is a 3-5 player game verified with exactly one
Studio client, and the salt-hit mechanic specifically requires a second body to throw at that
this session had no way to produce.
