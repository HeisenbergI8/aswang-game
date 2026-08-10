# Verification: C02–C04 (AntiCheat, RoleService/RoleDraw, MonsterService transform) — behavioural pass

**Date:** 2026-08-10
**Scope:** `feature-c02-c04-anticheat-roles-transform-plan` — Phases 2–7 (AntiCheatService/TokenBucket,
RoleService/RoleDraw, MonsterService/TransformRules, InputController, AudioController). Static
verification (analyze/lint/tests) was already green per the plan; this pass is behavioural only, driven
live in Roblox Studio.
**Rojo serving:** yes — `rojo serve` on localhost:34872, live-synced throughout.
**Studio reachable:** yes — Place3 (`7107daa3-2aac-4437-a1cf-546ecae82ce7`), Play mode, single client
`Demiurgos_18`.
**SoloTesting:** on — set by the coordinator before this session (`Round.Intermission=8, Duration=45,
EndScreen=6, Debug.SoloTesting=true, Debug.VerboseLogging=true`). I did not touch `Config.luau` (writes
there are refused by `guard-agent-write.mjs` for this agent anyway). Left as-is for the coordinator to
revert.

I stopped and restarted Play once, mid-session, after `InputController.luau`/`AudioController.luau`
appeared on disk (Rojo-synced live) — StarterPlayerScripts are cloned into the client only at Play
start, so the running client would not otherwise have picked up the new controller. This reset the round
counter from #10 back to #1; nothing else changed.

## The single most important finding

**A 1-player SoloTesting round can never draw an Aswang, and this is deterministic, not unlucky.**
`src/server/pure/RoleDraw.luau`:

```
local picks = math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))
```

With exactly one real candidate, `#candidates - 1 = 0`, so `picks = clamp(1, 0, 0) = 0` on every single
round, forever — the guard exists to stop a round drawing 100% of its candidates as Aswang, and one
player is that case. I confirmed this empirically, not just by reading the clamp: **every** ACTIVE-phase
transform attempt across the session (round 4, round 6, and round 1 of the post-restart session) came
back `NOT_ASWANG`. Waiting longer or restarting Play does not change it.

**Consequence: C04's visual transform (avatar scale/colour/eyes/particles, the windup, the forced
revert) could not be reached or verified behaviourally in this session at all**, not with any amount of
patience. Reaching that code path needs a second real candidate — either Studio's Test tab → Players set
to 2+ before Play starts, or a second live client. I did not do this myself: it requires a Studio setting
change outside any MCP tool available to me, and changing it would mean stopping the session you started.
Say the word and I'll do a follow-up pass with 2 players.

Everything else below — the guard chain, the rate limiter, the secrecy boundary, the new client-side
input gate — **was** reachable and verified with a single player, and all of it passed.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Bootstrap: 13 services, no warn, no require-cycle, `RoleDraw` resolves | PASS | `artifacts/console-01-bootstrap-roles-anticheat.txt`, reconfirmed post-restart in `artifacts/console-02-role-intro-secrecy-tkey.txt` §3 |
| RoleService draws every round, count-only | PASS | `artifacts/console-01-bootstrap-roles-anticheat.txt` (`[RoleService] Drew 1 roles.` × 10 rounds, never a name/UserId) |
| Role intro UI renders, private, correct copy | PASS (survivor variant only) | `artifacts/console-02-role-intro-secrecy-tkey.txt` §1 — screenshot viewed in-session, **not persisted to a file**; see Not Verified |
| Aswang variant of the role intro | NOT VERIFIED | see finding above — never assigned in this session |
| TransformRules check order (phase → alive → role → …) | PASS | `WRONG_PHASE` during INTERMISSION, `NOT_ASWANG` during ACTIVE, in that priority — `artifacts/console-01-bootstrap-roles-anticheat.txt` |
| Verdict never echoed to client | PASS | client fired `RequestTransform` and received no reply remote of any kind on every probe; confirmed by design in `MonsterService.luau`/`TransformRules.luau` |
| AntiCheat rate limiter (Capacity 3, refill 0.2/s) | PASS | `artifacts/console-01-bootstrap-roles-anticheat.txt` — 8-call burst: 3 pass through to `NOT_ASWANG`, then `[AntiCheat] Rate limit refused Demiurgos_18 (11461085874) on RequestTransform` |
| `Consume()` runs before role/phase validation | PASS | same burst — refusal counting is exact against `Capacity=3` regardless of round state |
| The transform itself (visual, windup, forced revert) | NOT VERIFIED | structurally unreachable solo — see finding above |
| Secrecy: no attribute/tag leak on Player/Character/Humanoid | PASS | `artifacts/console-02-role-intro-secrecy-tkey.txt` §2 — all `GetAttributes()` empty, all `GetTags()` empty, all CollectionService-tagged instances in the client's game view are stock Roblox CoreGui, none game-authored |
| InputController's T-key client-side role gate | PASS | `artifacts/console-02-role-intro-secrecy-tkey.txt` §3 — T pressed as a survivor produced **zero** server-side activity (no remote fired at all, not even a refusal), matching `if GetMyRole() ~= Aswang then return Pass end` |
| static (analyze/lint/tests) | not re-run this pass | plan states these were already green; out of scope for this behavioural-only pass |

## Failures

None. Everything reachable with one player behaved exactly as designed.

## Not Verified

- **The transform's visuals** — avatar scale, colour/material shift, eye glow, particles, the 1.2s
  windup, and the forced revert at `MaxTransformTime = 8s`. Unreachable with one player; needs a second
  candidate (Studio Test → Players ≥ 2, or a second client). This is the one gap that matters for C04.
- **The Aswang variant of the role intro card** ("YOU ARE THE ASWANG. Do not get seen.") — same reason.
  I read it in source; I did not see it render.
- **Salt-forced revert interaction, kill cooldown timing, spectator containment** — out of scope for
  this pass (later chunks) and also gated behind having a live Aswang.
- **Screenshot artifact files.** `screen_capture` returned images I viewed directly in the tool
  transcript (baseline avatar, the survivor role-intro card, two attempted-transform frames showing no
  visual change), but this environment does not write them to any discoverable path on disk — I searched
  `/tmp`, `/private/tmp`, and Roblox's own cache/log directories and found nothing. I'm reporting this
  plainly rather than citing a path that doesn't exist. The two console-text artifacts are real files and
  carry the exact text/behavioural evidence; the role-intro screenshot claim is downgraded from PASS to
  "observed, not persisted" for that reason.
- **`implementation-log.md` covers Phase 1 only** (Config/Types/remote-surface audit), even though
  Phases 2–7's code is clearly present and behaving correctly live (RoleService, MonsterService,
  AntiCheatService, InputController, AudioController all ran and were exercised this session). That's a
  documentation gap in the plan directory, not a functional defect — flagging it since the log is one of
  the four proxies `goal-check.mjs` reads for "is this plan done."
- **Two-client secrecy check** — I confirmed no leak reaches *this* client's own DataModel view, but
  couldn't confirm from a genuinely separate client's perspective (only one was available).
- Static gate (`npm run verify`) was not re-run in this pass; taking the plan's word that it was green
  before this session.
