# Verification: V06 — Feeding

**Date:** 2026-08-28 (two sessions: initial pass, then a follow-up after the coordinator cleared the
first blocker and two review findings landed in the code)
**Scope:** working tree diff — `src/server/Services/MonsterService.luau`, `src/shared/pure/FeedRules.luau`,
`src/shared/pure/KillValidation.luau`, `src/client/Controllers/FeedController.luau`,
`src/shared/Remotes.luau`, `src/shared/Types.luau`, `src/shared/Config.luau`, `tests/config.test.luau`,
`tests/feed-rules.test.luau`, `tests/kill-validation.test.luau`, `src/client/init.client.luau`
**Rojo serving:** yes, both sessions — confirmed by reading live `Config` values (and, in the second
session, the presence of `KillValidation`'s new `FEEDING` verdict) out of
`ReplicatedStorage.Shared` in Studio Edit mode and matching what was expected each time.
**Studio reachable:** yes — one Studio instance (`aswang.rbxl`), Play mode entered and exited cleanly
in both sessions.
**SoloTesting:** on throughout, set by the coordinator, not by me. `Debug.VerboseLogging` also on.
`Debug.ForceAswangWhenSolo` was `false` for session 1, then set to `true` by the coordinator for
session 2 — confirmed live in Studio before trusting anything (see below). I did not edit
`Config.luau` at either point; it remains off-limits to me by design.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` → `0 errors, 0 warnings, 0 parse errors` |
| lint | PASS | `npm run lint` → `0 errors, 0 warnings, 0 parse errors` |
| format | PASS | `npm run fmt:check` → exit 0, no output |
| check:remotes | PASS | `27 declared, 27 wired` |
| check:secrecy | PASS | `the Aswang stays server-side` |
| check:scope | PASS | `19 out-of-scope shapes watched` |
| check:ratelimit | PASS | `every OnServerEvent consults AntiCheat` |
| check:config | PASS | `balance stays data-driven` |
| check:debug | FAIL (expected) | `Debug.SoloTesting`, `Debug.VerboseLogging`, `Debug.ForceAswangWhenSolo` all non-committed values — the coordinator's deliberate debug set, not a defect. `guard-commit.mjs` will refuse to commit while they stand, correctly. |
| test:unit | 32/33 files | Same single failure both sessions: `tests/config.test.luau`, which asserts `SoloTesting == false` plus two other debug-value-contingent invariants — a direct, known consequence of the debug set, not of the V06/kill-validation diff. `tests/kill-validation.test.luau` → `55 grid cells and cases` (was 51; the two new review findings added 4 cells) — confirmed by direct run in session 2. `tests/feed-rules.test.luau` → `777/777 checks passed`, unchanged. |
| behavioural | **BLOCKED — NOT ESTABLISHED, all seven questions** | `artifacts/solo-role-blocker-console.log` (session 1), `artifacts/forced-aswang-no-kill-target.log` (session 2) |

`npm run verify` as one gate is RED in both sessions only because it halts at `check:debug` on the
coordinator's intentional debug values — expected, per CLAUDE.md.

## Session 1's blocker (RESOLVED — recorded for the audit trail)

The sole client was always drawn `SURVIVOR`: `RoleDraw.draw` clamps picks to `#candidates - 1`, so a
1-candidate pool deterministically keeps that candidate a survivor. Five full round cycles produced
zero `[MonsterService]` log lines and an on-screen role card reading "SURVIVOR." The needed override,
`Config.Debug.ForceAswangWhenSolo`, was at its committed default (`false`). Full detail and raw console
in `artifacts/solo-role-blocker-console.log`. The coordinator confirmed this was their miss and set the
flag to `true` for session 2.

## Session 2: the flag fix works, but a second, deeper blocker remains

**Re-verified sync before trusting anything**, live in Studio Edit mode:
`Intermission=8, Duration=20, EndScreen=6, SoloTesting=true, VerboseLogging=true,
ForceAswangWhenSolo=true`, and `ReplicatedStorage.Shared.pure.KillValidation` present and requirable —
so the current code, not a stale sync, is what session 2 tested.

**Statically confirmed both review findings before touching Studio:**

- `src/shared/pure/KillValidation.luau`: `Verdict` gained `"FEEDING"`; `Request` gained
  `Feeding: boolean`; `evaluate` returns `"FEEDING"` for it, placed after `NOT_TRANSFORMED` and before
  the cooldown check — exactly where it has to sit, because a feeding killer's `LastRevertedAt` is
  stale and would otherwise pass the cooldown gate as `OK`.
- `src/server/Services/MonsterService.luau`: both `validateAndKill` (line 1706) and
  `validateAndKillHusk` (line 1596) now pass `Feeding = monster.Feeding` into the request.
- `revert()` (`MonsterService.luau`, starting line 748) now restores `FeedBaseJumpPower`/
  `FeedBaseJumpHeight` alongside `BaseWalkSpeed` (~lines 796–804), closing the quarter-second window
  where `beginFeed`'s refusal branch or `validateAndKillHusk` could leave `JumpPower`/`JumpHeight`
  zeroed on a publicly-reverted character.
- `lune run tests/kill-validation.test.luau` → `PASS kill-validation: 55 grid cells and cases`
  (confirmed by direct run, not taken on the coordinator's word).

**Entered Play mode. The forced-Aswang fix works exactly as intended:**

```
[RoleService] DEBUG — Aswang FORCED to Demiurgos_18 (roster 1 <= MinPlayers 3). Never ship with this set.
[RoleService] Drew 1 roles.
```

A screen capture during the ACTIVE phase showed the role card reading **"ASWANG"** with **"TRANSFORM
(T)"** and **"KILL (F)"** prompts — the client-side role state is correct. (Viewed directly in the tool
output; not persisted to a file — no tool in this session's kit writes a Studio `screen_capture` result
to disk, same limitation as session 1.)

**But there is no one to kill.** `search_game_tree` on the `Server` datamodel during that same ACTIVE
phase found exactly **one** entry under `Players` — `Players.Demiurgos_18`, the Aswang itself — and
both `Workspace.Corpses` and `Workspace.Husks` are empty folders. `RoundService.dealtInUserIds()`
(`RoundService.luau:599-611`) draws candidates only from `state.PlayerStates`, which is populated only
by real connected `Player`s. `ForceAswangWhenSolo` changes **which** candidate is dealt the Aswang
role — it does not add a second candidate. With one real client forced to Aswang, the round has **zero
survivors and zero husks**: a husk is created only when a connected Player disconnects or idles out
mid-round (`RoundService.luau` ~1051–1061), which itself requires a second Player to have connected in
the first place.

Net effect: `RequestKill` has no valid target in this session, in any phase, for as long as the round
runs. `beginFeed` is reachable only from `commitKill`, which is reachable only from a kill that
validated against a live Player or husk (`validateAndKill` / `validateAndKillHusk`) — neither is
reachable with exactly one Studio client connected, **regardless of any Config value**. I ran two
round cycles to confirm this wasn't a one-off; both showed the identical forced-Aswang-with-no-target
pattern. Full detail in `artifacts/forced-aswang-no-kill-target.log`.

This is a genuinely different blocker from session 1's, not a restatement of it: session 1 was "the
Config value stops me from ever being the Aswang." Session 2 is "being the Aswang, correctly, still
leaves nobody to test the feed on, because a kill target does not exist in a single-connection
session." Both `ForceAswangWhenSolo`'s own code comment (`RoleService.luau`, "at 2-3 local clients,
because the other windows are idle and a survivor draw means no transform and no kill ever happens")
and the playtester's own known-limits doc ("Player count is a UI action you cannot drive... needs a
human to set Test → Clients and Servers") point at the same fact: this flag was designed for a
**multi-client Studio Team Test session** (2-3 windows), not for a single `Play` window. I did not
have that available, and starting one is a Studio UI action outside every MCP tool I have.

## The seven questions

All seven need an actual kill (and, for six of them, the feed it triggers) to have happened. None
could be produced in either session, for two different reasons. Verdict for each is **NOT
ESTABLISHED** — not a pass, not a fail:

1. **Does the movement lock hold for an honest client?** NOT ESTABLISHED — no kill occurred.
2. **Does jumping still work?** NOT ESTABLISHED behaviourally. Static read of `beginFeed`
   (`MonsterService.luau:1278-1338`) still shows the code zeroing `Humanoid.WalkSpeed`, `JumpPower`
   and `JumpHeight` only — `grep -n "SetStateEnabled" src/server/Services/MonsterService.luau` still
   returns nothing in the current tree. I am not claiming it is broken; I am confirming the gap the
   plan itself flagged as its riskiest guess is still present and still unverified by a real feed.
3. **Is there a visible slide before the lock lands?** NOT ESTABLISHED — no kill occurred.
4. **Does the feed complete and heal?** NOT ESTABLISHED — no kill occurred, so no feed ever started.
5. **Does salt interrupt it?** NOT ESTABLISHED — no kill/feed existed to interrupt.
6. **Does the killer revert at all?** NOT ESTABLISHED — no kill occurred. (The static fix to `revert()`
   restoring the jump properties is confirmed by reading the code — see above — but a static read is
   not this question's answer; the question is about a live, running character.)
7. **With two survivors near each other, kill one, then immediately try to kill the second while
   pinned to the first corpse — does the server refuse with `FEEDING`?** NOT ESTABLISHED. This needs
   *two* survivors simultaneously, which needs at least three Studio clients in this session's
   configuration (one forced Aswang + two survivors) — a strictly harder version of the same
   single-client limitation that blocked questions 1–6. The `Feeding` field, the verdict, and the two
   call sites that thread it are all confirmed present and correctly wired by static reading (above)
   and by `tests/kill-validation.test.luau`'s 55 passing cells, which is the strongest evidence
   available for this specific rule without a second live target. It is real evidence, but it is not
   the same thing as watching the server print `Refused kill by <name>: FEEDING` against a live second
   victim, which is what was asked for.

No `artifacts/feed-complete.png` or salt-interruption artifact exists. I am not producing a
placeholder or a screenshot of something other than what was asked — that would be a false pass
dressed as a thin artifact, which is worse than reporting the blocker plainly.

## What I could establish statically (both sessions combined)

- `commitKill` no longer calls `revert`; the revert call lives only in `endFeed`
  (`MonsterService.luau:1145-1213`).
- Six call sites reach `endFeed`: the four `feedTick` exits, `completeFeed`, and `beginFeed`'s own
  refusal branch calling `revert` directly (a feed that never started has no jump/walk state saved to
  restore through `endFeed`).
- `endFeed` restores `WalkSpeed`/`JumpPower`/`JumpHeight` from captured values before clearing them,
  then reverts; `completeFeed` calls `endFeed` **before** `HealFromFeed` and firing `FeedCompleted`.
- `revert()` itself now also restores the jump properties (session 2 finding), closing the two-caller
  gap named above.
- `KillValidation.evaluate` now refuses a kill attempted mid-feed with `"FEEDING"`, checked before the
  cooldown gate, and both live kill paths (`validateAndKill`, `validateAndKillHusk`) supply the field.
- `check:secrecy`, `check:remotes`, `check:ratelimit`, `check:scope` all pass over the full diff,
  including the `Feeding` field and verdict — no static red flag on the network or secrecy boundary.
- `tests/feed-rules.test.luau` (777/777) and `tests/kill-validation.test.luau` (55/55 cells) both pass
  — the two parts of this chunk's logic that live in `src/shared/pure/` and are therefore provable from
  a terminal.

This is meaningfully more assurance than session 1 had, and specifically covers the exact regression
the review findings targeted (the chain-kill window, and the jump-restore gap on two callers). It is
still not the same claim as "I watched this happen," which is what the six-plus-one questions ask for.

## Not Verified

- **All seven behavioural questions.** What would unblock them: a Studio **Team Test** session with at
  least two connected clients (three for question 7 specifically — one forced Aswang, two survivors).
  That is a Studio UI action (Test → Clients and Servers) that no MCP tool in this session's kit can
  drive; a human needs to start it. Once running, I can complete Phase 5.3 in one more pass — kill one
  survivor, watch the lock/jump/slide/complete/heal behaviour, attempt the second kill mid-feed for
  question 7, then throw salt at a fresh feed for the interruption case — in a single session.
- The secret-role questions from this agent's own checklist (is the Aswang's identity reachable from a
  second client) — not exercisable with a single connected client either; the static `check:secrecy`
  pass is the only evidence at this tier for both sessions.
- Screenshot artifacts for either session's role-card observations (SURVIVOR in session 1, ASWANG in
  session 2) — both viewed directly in the tool output, neither persisted to disk; no tool available in
  either session writes a Studio screen capture to a file. The two console-log artifacts carry the same
  facts in text form and are the ones actually cited above.
