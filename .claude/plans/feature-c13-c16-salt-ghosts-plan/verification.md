# Verification — first runtime evidence for C13–C16

**Run:** 2026-08-14, Studio Play (solo), Rojo connected, `Config.Debug` set to
`SoloTesting/VerboseLogging/ForceAswangWhenSolo = true` and round timings 8/20/6.
**All six reverted afterwards** — `git diff src/shared/Config.luau` is empty and `check:debug` passes.

Artifacts: `artifacts/salt-rig.md`, `artifacts/textchat-probe.md`, this file.

---

## 1. CRITICAL FOUND AND FIXED — ghost chat was entirely unenforced

First Play of the session, verbatim:

```
[GhostService] ⚠️ NO TextChannels UNDER TextChatService — GHOST CHAT IS NOT ENFORCED.
```

Then, from the same running server moments later:

```
ChatVersion = Enum.ChatVersion.TextChatService
TextChannels exists NOW (post-startup) = true
  channels: RBXSystem, RBXGeneral
  Ghosts channel created by GhostService = false
```

**The arrival race is the normal path, not a corner case.** `TextChannels` is created shortly AFTER
services start, every time. `configureChannels` did `FindFirstChild`, found nil, warned, and RETURNED —
so no `Ghosts` channel and no `ShouldDeliverCallback` on anything. Every ghost message would have
reached every living player.

**The `ChildAdded` guard added for this exact race was placed AFTER the early return**, so it never ran
in the case it was written for. `npm run verify` was green throughout.

The warn was also misleading: it blamed `ChatVersion`, which was correct.

**Fixed** — `configureChannels` now `WaitForChild`s in a `task.spawn` (so `Start()` does not yield) with
a 30s timeout. Re-run, verbatim:

```
[GhostService] Chat wall attached over 3 channel(s).
```

Three channels: `RBXSystem`, `RBXGeneral`, `Ghosts`.

## 2. `ShouldDeliverCallback` SUPPRESSES — proven with a control

The milestone's biggest unknown. Same channel, same message, only the return value differs:

| callback returns | messages received by the client |
| --- | --- |
| `false` | **0** |
| `true`  | **1** (`PROBE_ALLOWED_MESSAGE`) |

Layer 3's mechanism is real. What this does NOT prove is the ghost→living ROUTING, which needs two
clients.

## 3. C13 salt — spawns correctly, every round

```
[ItemService] Salt pool OK — 6 spawn points.
[ItemService] 4 pouch(es) placed of 4 wanted.
```

```
workspace.SaltPouches exists = true
  pouches in world = 4
    SaltPouch_SaltSpawn_01 at -50, 1.5, 60 tagged=true
    SaltPouch_SaltSpawn_05 at  30, 1.5, 60 tagged=true
    SaltPouch_SaltSpawn_04 at  10, 1.5, 60 tagged=true
    SaltPouch_SaltSpawn_02 at -30, 1.5, 60 tagged=true
```

Four pouches (= `SpawnCount`) at four of six pads, **non-sequential**, so the Fisher-Yates shuffle is
genuinely shuffling. Tagged `SaltPouch`, sitting 1 stud above the pads. Repeated identically across six
consecutive rounds.

## 4. The round machine cycles cleanly

Six full rounds observed: INTERMISSION → STARTING → ACTIVE → ENDING → INTERMISSION, with role draw,
task selection (5 of 12, varying each round) and salt spawn on every one. `workspace.Husks` and
`workspace.Corpses` are both created at Start.

---

## NOT PROVEN — and one earlier result retracted

**RETRACTED: an earlier check that appeared to confirm Option A was invalid.** `execute_luau`'s
`require` returns a **fresh module instance**, not the running service — the documented Studio trap in
CLAUDE.md. The first attempt read `state=LOBBY phase=IDLE` from an empty copy while the real server was
mid-round, and its "OPTION A HOLDS = true" meant nothing. Recorded because the output looked like a pass.

**The corpse-as-Character claim is still unproven.** It only happens on a validated Aswang kill
(`commitKill` → `makeCorpse`), and solo the single player IS the Aswang, who cannot kill themselves.
A `Humanoid.Health = 0` death exercises a different branch — `Corpses` stayed empty and no
`[RoundService] Killed` line appeared. **Needs 2+ players.**

### Genuinely blocked on a second human

Studio's *Test → Clients and Servers* is a ribbon UI action MCP cannot drive. These need it:

1. **Ghost → living chat routing.** Suppression is proven; that the WALL routes correctly is not.
   Needs: ghost sends, two living chats screenshotted without it, one ghost chat with it.
2. **C14's glow from a third client** — the bystander view is the claim, and the thrower's own screen
   cannot make it.
3. **Corpse-as-Character** after a real kill (§1 above).
4. **Salt pickup and the carry limit** — "picks up two in a row and is refused the second" needs a
   player who is not the forced Aswang.
5. **The ghost's client-local flying body**, which has never been instantiated.
