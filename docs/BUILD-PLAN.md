# ASWANG — Build Plan (chunked)

**What this is:** `docs/MVP-SPEC.md` broken into **45 sequenced chunks**, each sized to *one background
agent run*. The spec says WHAT to build; this says **what to build next, in what order, and how you know
it's done**.

**Precedence is unchanged:** `MVP-SPEC.md` → `CLAUDE.md` → this file → the code. If a chunk here
contradicts the spec, the spec wins and the chunk is wrong.

---

## 0. How to use this

### One chunk = one run

A chunk is scoped so you can hand it to the pipeline, walk away, and come back to something either
finished or halted with a written reason. Not a "day" — a *unit of delegable work*. On a good day you
might land three; on a debugging day, none.

Each chunk carries five fields:

| Field | Meaning |
| --- | --- |
| **Tier** | Trivial / Small / Medium / Large, per `CLAUDE.md`'s routing table. Decides which agents run. |
| **Runner** | 🤖 agent · 🧍 you · 🤝 both (agent writes code, you do the Studio/dashboard half) |
| **Deps** | Chunks that must be green first. Nothing else is ordered. |
| **Done** | The definition of done, stated so it can be checked rather than felt. |
| **Verify** | The actual command or evidence. `verify` always means `npm run verify`. |

### How to start one

```bash
rojo serve                         # always, first
npm run preflight -- --studio      # entry conditions
```

- **Large** → `/build` (the supervised loop). It only drives Large-tier plan-backed work — that is why
  chunks are sized up to Large wherever the loop should own them.
- **Medium** → say the tier out loud, then `implement-plan`, then run `playtester` + `change-auditor`
  concurrently in one message with `run_in_background: true`.
- **Small** → do it, then `playtester` + `change-auditor`.
- **Trivial** → do it, then `npm run verify`. No agents.

`exploit-auditor` runs **in addition, at any tier**, on every chunk marked 🔒. That marker means the diff
touches `src/server/**`, `Remotes.luau`, `RoleService`, `MonsterService`, or `AntiCheatService`.

### The rule that makes chunks agent-shaped

> **Every gameplay decision that can be a pure function must be one.**

Lune can't see `game`. So each chunk that contains a real decision — the role draw, the 5-of-12
selection, the rate-limit bucket, the XP curve, the win check — puts that decision in
`src/shared/pure/` as a pure function over plain tables, and leaves a thin Roblox wrapper around it.

That is what turns "an agent says it works" into "a test says it works". Chunks below name the pure
module explicitly where one is required. It is not optional — it is the difference between a chunk you
can verify from a terminal and one you have to take on faith.

---

## 1. Three deviations from spec §12 — read before starting

I am flagging these rather than quietly resolving them, per `CLAUDE.md`.

**1. M5 needs a map, but §12 puts the map at M8.**
You cannot playtest with 6 humans on a baseplate — they can't hide, can't get isolated, can't loop a
chase, and every note they give you will be about the empty map instead of the game. So the map is
**split**: a **greybox** (C25, parts only, correct layout and scale) lands *before* M5, and M8 becomes
the **art and atmosphere pass** on top of geometry that has already been proven to play well.
This is strictly cheaper — you dress a layout you know works, instead of dressing one you then rebuild.

**2. M5 needs a HUD, but §12 puts UI at M7.**
Same logic. Testers need to see the task bar, the sunrise timer, and a transform button, or they cannot
play at all. So UI is **split**: a **minimum playable HUD** (C26 — ugly, functional, keyboard-first)
before M5, and M7 stays what it is — the polish pass, quick chat, and the mobile pass.

**3. Marketing is not a milestone, it is a parallel track from today.**
§14.1 says start posting during the build; §13 lists marketing under launch prep. §14.1 is right and §13
is just where the checklist lives. **Track M** below runs alongside everything from C01 onward. It is the
only track that does not wait for a dependency, and it is the one with the longest lead time.

---

## 2. The tracks

```
Track A — gameplay   C01 ─▶ C16     M1–M4. The loop. Agent-heavy. This is the game.
Track B — world      C17, C18       greybox map + minimum HUD. Yours, in Studio.
       ══ GATE 1 ══  C19            M5 playtest — 6 humans. Everything can change here.
Track C — FTUE       C20 ─▶ C24     M6. The 80% hole. The competitor died here.
Track D — polish     C25 ─▶ C30     M7–M8. Quick chat, UI, mobile, art, audio.
Track E — business   C31 ─▶ C41     M9–M11. Data, money, community, analytics, anti-cheat.
       ══ GATE 2 ══  C42            M12 playtest — 8 humans, balance to <60% either side.
Track F — launch     C43 ─▶ C45     M13.
Track M — marketing  from today, in parallel, never blocked by anything.
```

Chunks are numbered in **execution order**. Where two adjacent chunks have no dependency between them,
order is a suggestion; where `Deps` names a chunk, it is not.

---

## 3. Track A — the gameplay loop

> **Where you actually are:** M0 is done. M1 is ~80% done — `RoundService.luau` has the state machine,
> the tick loop, `setPhase`, the phase broadcast, and the Aswang-leaves case. The other 12 services and
> all 5 controllers are ~20-line stubs. C01 finishes M1; C02 is the first genuinely new system.

---

### C01 — Finish the round state machine
**Tier** Medium · **Runner** 🤖 · **Deps** — · 🔒

The remaining §6.4 edge cases, and the snapshot the whole client will read.

- Mid-round join → `SPECTATOR` (the enum already exists, nothing sets it).
- Player count drops below `MinPlayers` mid-round → finish the round, *then* `IDLE`. Today `step()` only
  checks player count in `INTERMISSION` and `ENDING`; `ACTIVE` ignores it, which is correct behaviour and
  currently accidental — make it deliberate and comment it.
- `game:BindToClose()` hook, empty for now, with the flush point marked for C40.
- Broadcast `RoundSnapshot` (`Types.ClientRoundSnapshot`) on a timer — phase, seconds left, task count,
  gate state, alive count. **No role field, ever.**
- Extract the transition table to `src/shared/pure/RoundTransitions.luau` — `(phase, expired,
  enoughPlayers) → nextPhase?`. This is the single most bug-prone function in the game and it is pure.

**Done** every §6.4 bullet handled; snapshot broadcasting; pure transition module extracted.
**Verify** `lune run tests/round-transitions.test.luau` covers all 5 phases × expired × player-count;
`verify` green; playtester watches two full cycles in Studio with `Debug.SoloTesting = true`.

---

### C02 — AntiCheatService: the rate-limit core
**Tier** Medium · **Runner** 🤖 · **Deps** C01 · 🔒

**Do this before any other remote handler exists.** `check:ratelimit` fails any `OnServerEvent` that
doesn't consult `AntiCheatService`, so building it now means every later chunk is born compliant instead
of retrofitted. It is also the cheapest chunk in the plan that stays load-bearing to launch.

- `src/shared/pure/TokenBucket.luau` — pure `(bucket, now, cost) → (allowed, newBucket)`.
- `AntiCheatService.Consume(player, remoteName)` over per-player, per-remote buckets.
- Per-remote budgets in `Config.AntiCheat` (new section — every number, `check:config` enforces it).
- Log-only on rejection for now. Kicking comes at C47 with real data behind it.

**Done** every `Remotes.Up` name has a declared budget; a burst is refused; the refusal is logged.
**Verify** `lune run tests/token-bucket.test.luau` — steady state, burst, refill, clock jump backwards.

---

### C03 — RoleService: the secret
**Tier** Large · **Runner** 🤖 · **Deps** C02 · 🔒

The one piece of state the whole game rests on. Plan-backed — use `/build`.

- `src/shared/pure/RoleDraw.luau` — `(players, historyLast2Rounds, aswangCount) → assignments`, with
  §4.2's anti-repeat weighting. Pure, deterministic given a seed.
- `RoleService` calls it during `STARTING`, stores server-side, fires `RoleAssigned` to **exactly one
  player**, carrying only their own role.
- Round history persists across rounds in-memory (survives to disk at C40, not before).
- The 3-second private Aswang intro.

**Done** roles assigned; a player who was Aswang last round is measurably less likely to draw it again;
nothing about the assignment is readable from another client.
**Verify** `lune run tests/role-draw.test.luau` — over 10,000 seeded draws, back-to-back Aswang rate is
below the unweighted baseline, and every player is eventually eligible (no starvation).
`npm run check:secrecy` clean. **`exploit-auditor` is mandatory on this chunk** — if it finds one leak
here, the chunk is not done regardless of what the tests say.

---

### C04 — MonsterService: transform
**Tier** Medium · **Runner** 🤖 · **Deps** C03 · 🔒

§4.3 steps 1–3. The transform is **public by design** — replicating it is correct, and it is the only
thing in this game that legitimately reveals the Aswang.

- `RequestTransform` → validate: is Aswang, `ACTIVE`, not already transformed, cooldown elapsed.
- 1.2s windup → `MonsterTransformed` to all clients. Avatar scale, colour/material shift, glowing eyes,
  particle emitter. **No custom mesh** (§4.3 — this is why the mechanic is cheap).
- `+25%` walkspeed while transformed, server-set.
- Forced revert at `MaxTransformTime`, 1.0s revert animation.

**Done** any player with line of sight sees the transform; the Aswang cannot stay transformed past 8s.
**Verify** playtester: two clients in Studio, one transforms, screenshot from the *other* client's
camera showing the silhouette. That screenshot is the artifact.

---

### C05 — MonsterService: the kill
**Tier** Medium · **Runner** 🤖 · **Deps** C04 · 🔒

§4.3 steps 3–5, and the five server-side rules in §4.3 verbatim.

- `RequestKill(targetUserId)` → distance ≤ 8, **raycast line of sight**, cooldown elapsed, both alive,
  phase `ACTIVE`, killer is Aswang, target is not.
- `src/shared/pure/KillValidation.luau` — `(killerPos, targetPos, config, now, lastKillAt) → verdict`.
  Everything except the raycast, which needs the DataModel.
- Corpse persists `CorpseDuration`, then fades. `PlayerKilled` broadcast (position and victim — **never**
  the killer).
- Kill cooldown starts from *revert*, not from the kill.

**Done** all six conditions enforced server-side; a client firing `RequestKill` at a target 40 studs
away through a wall is refused.
**Verify** `lune run tests/kill-validation.test.luau` — at range, past range, on cooldown, wrong phase.
Playtester attempts an out-of-range kill via `execute_luau` and captures the refusal. 🔒 mandatory.

---

### C06 — Win condition: the Aswang's
**Tier** Small · **Runner** 🤖 · **Deps** C05 · 🔒

Living survivors ≤ 2 → `RoundService.EndRound(AswangWin)`. The timeout half already works.
Add to `pure/RoundTransitions.luau` or a sibling; do not scatter the check.

**Done** both Aswang win paths fire and reach the reveal.
**Verify** unit test on the win predicate; playtester drives a solo round to the ≤2 condition.

---

### C07 — TaskService: pick 5 of 12
**Tier** Medium · **Runner** 🤖 · **Deps** C01

§4.4's one load-bearing decision — the reason a single map stays fresh (Appendix C.4 cause #2).

- `src/shared/pure/TaskSelection.luau` — `(pool, count, seed) → chosen`, no duplicates, uniform over
  the pool, spatially spread if the pool carries positions.
- Task points discovered in the map by CollectionService tag (`TaskPoint`), not hardcoded — the greybox
  at C25 places them and this reads them.
- Selection happens in `STARTING`; the set is server state.

**Done** every round draws a different 5; the same point never appears twice in one round.
**Verify** `lune run tests/task-selection.test.luau` — no duplicates over 10,000 seeded draws,
distribution across the 12 is within tolerance, graceful when the pool is smaller than 5.

---

### C08 — Task type: Hold
**Tier** Medium · **Runner** 🤖 · **Deps** C07, C02 · 🔒

The first of four, and the one that establishes the shape the other three copy.

- ProximityPrompt, `HoldTime` seconds, server-timed. **The client cannot report completion** — it
  reports *presence*, and the server accumulates.
- `RequestTaskProgress` rate-limited via C02.
- Progress is per-task-point on the *world*, not per-player (§4.4 anti-frustration).
- `TaskProgressChanged` broadcast — the global bar only. Never who did what.

**Done** a hold completes in `HoldTime`; walking away mid-hold stops accumulation; a client spamming
`RequestTaskProgress` gains nothing.
**Verify** playtester holds a task to completion, then attempts to complete one by firing the remote in a
loop from `execute_luau` and shows it refused. 🔒 mandatory.

---

### C09 — Task types: Timing and Fetch
**Tier** Medium · **Runner** 🤖 · **Deps** C08

Both reuse C08's server-authority shape.

- **Timing** — moving bar, 3 attempts, green zone. The client renders the bar; the **server** owns the
  bar's position and decides the hit. A client-decided timing minigame is a free task for any exploiter.
- **Fetch** — pick up an item elsewhere, carry it back. Server tracks the carry; dropping on death is
  correct and creates good moments.

**Done** both playable, both server-decided.
**Verify** playtester completes one of each; the timing hit is refused when fired outside the window.

---

### C10 — Task type: Two-person
**Tier** Medium · **Runner** 🤖 · **Deps** C09

Requires 2 survivors present for `TwoPersonTime`. The best task in the game — the Aswang can "help" you
and then be alone with you. Server validates both are alive, present, and distinct.

**Done** one player alone makes no progress; two do; progress stops when one leaves.
**Verify** playtester with two clients, screenshot of the bar moving only with both present.

---

### C11 — The escape gate and the survivors' win
**Tier** Medium · **Runner** 🤖 · **Deps** C10, C06 · 🔒

§4.8. At 5/5 the gate opens; a survivor reaching it wins the round. This is the finale and the best clip
in the game — treat the gate opening as an event worth seeing and hearing, not a boolean.

**Done** both win conditions in §4.8 fire correctly and land on the reveal.
**Verify** playtester drives a full survivor win end-to-end; console log of the transition chain.

---

### C12 — The Aswang's fake task list
**Tier** Small · **Runner** 🤖 · **Deps** C11 · 🔒

§4.4. The Aswang sees a task list and can play the animation; its progress does not count. **Essential** —
without it, "who is standing at tasks" identifies the monster in thirty seconds and the game is over.

The trap: the fake progress must look identical *to the Aswang's own client*, while contributing nothing
to the global bar. If the Aswang's bar and everyone else's ever disagree visibly, that is the tell.

**Done** the Aswang can fake-perform every task type; the global bar does not move.
**Verify** playtester as the Aswang completes a hold; the global count is unchanged. 🔒 mandatory.

---

### C13 — ItemService: salt spawn and pickup
**Tier** Medium · **Runner** 🤖 · **Deps** C07

4 pouches at random fixed points (tagged `SaltSpawn`, same discovery pattern as C07). One carried per
player. No recharge — §4.6, scarcity is the point.

**Done** 4 spawn per round at different points; carry limit enforced server-side.
**Verify** playtester picks up two in a row and is refused the second.

---

### C14 — ItemService: throw, stun, reveal
**Tier** Medium · **Runner** 🤖 · **Deps** C13, C04 · 🔒

The counterplay. Without it the game is just losing (§4.6).

- `RequestThrowSalt(direction)` → server simulates. **The client never decides a hit.**
- Hit → 4s stun, forced revert, `RevealDuration` glow visible to everyone.
- `ThrowRange` 25 > `KillRange` 8 — `tests/config.test.luau` already pins this relationship. Don't break it.

**Done** a hit stuns, reverts, and reveals; a miss consumes the pouch anyway.
**Verify** playtester lands a throw, screenshot of the glow from a third client. 🔒 mandatory.

---

### C15 — GhostService: death to ghost
**Tier** Large · **Runner** 🤖 · **Deps** C05 · 🔒

§4.7 — the retention leak that is silently fatal. Plan-backed.

- Dead survivor → ghost. Slow flight at `Ghost.FlySpeed`, sees other ghosts.
- **Ghost-only chat, a genuinely separate channel.** A ghost naming the Aswang in a channel the living
  can read ends every round instantly. Enforce server-side — a client-side filter is not a filter.
- Ghosts cannot be seen or heard by the living.

**Done** death transitions cleanly; ghosts see ghosts; no ghost message reaches a living player.
**Verify** playtester: three clients, one dies, ghost sends a message, screenshot of the two living
clients' chats **not** containing it. 🔒 mandatory — this is a secrecy surface, not just a chat feature.

---

### C16 — GhostService: contribution and the spook
**Tier** Small · **Runner** 🤖 · **Deps** C15

Ghosts hold task points at `TaskContributionMult` (25%). One spook per round — flicker a light, rustle a
bush. **Carries no information**, by design; it is flavour that keeps dead players in the room.

**Done** ghost contribution counts at 25%; the spook fires once and only once per round.
**Verify** playtester as a ghost adds progress; second spook attempt refused.

---

## 4. Track B — enough world to test

> Two chunks, both mostly yours, both deliberately ugly. Their only job is to make GATE 1 possible.

---

### C17 — Greybox the Barrio
**Tier** Large · **Runner** 🧍 (agent assists with tagging scripts) · **Deps** C07, C13

**Parts only. Grey. No textures, no art, no lighting pass.** You are proving a *layout*, and every hour
spent on looks here is an hour you may throw away after GATE 1.

Build to §5:
- ~35 seconds to cross end to end. **Measure it — walk it with a stopwatch.** New devs build maps 3×
  too big and the whole game dies of players never meeting each other.
- Central plaza (spawn + escape gate), 6–8 bahay kubo with ≥3 enterable, chapel interior, rice field
  edge, well/pump area.
- 2–3 alleys forming **loops, never dead ends**. Walk every alley and confirm you can run a circle.
- 12 `TaskPoint`-tagged anchors, spread. 4 `SaltSpawn` anchors. 1 `EscapeGate`.
- `StreamingEnabled` on from the start — retrofitting it later is miserable.

**Done** the tags exist and C07/C13 discover them; the crossing time is 30–40s; every alley loops.
**Verify** press Play, walk the map, `search_game_tree` confirms 12 + 4 + 1 tagged instances.
**Then publish** — the place file is gitignored and Roblox's cloud version history is its only backup.

---

### C18 — Minimum playable HUD
**Tier** Medium · **Runner** 🤖 · **Deps** C17, C11

Ugly and functional. Default fonts, flat rectangles, no theme. Polish is C34 and it happens *after* six
humans have told you what the HUD is missing.

- Sunrise timer, global task bar, alive count — all from `RoundSnapshot`.
- Transform button (Aswang only — **gate it on the client's own `RoleAssigned`, never on a broadcast**).
- Salt indicator, interaction prompts.
- Basic end screen with the reveal.

**Done** a human can play a full round without being told anything about the codebase.
**Verify** playtester plays a full round using only the HUD; screenshot at each phase.

---

## 5. ══ GATE 1 ══

### C19 — M5: first playtest, 6 real humans
**Tier** — · **Runner** 🧍 · **Deps** C18 · Load the `playtest` skill first.

**Five rounds, six people, and one question: do they want a sixth round?**

No agent can run this and no verification substitutes for it. Write down what they *said*, not what you
concluded — you will re-read these notes at C49 and your conclusions will have drifted.

Watch for, specifically:
- Does anyone actually get isolated, or does the group never split? (map too small / too safe)
- Does the Aswang ever get caught transforming? (if never, the tell is too weak; if always, too strong)
- Does salt feel like a decision or a lottery?
- Do dead players stay?

**Done** notes written to `docs/playtests/2026-XX-XX-m5.md`.
**If they do not want a sixth round, stop and change the design here.** §12 is unambiguous about this
being the cheapest moment in the entire project to be wrong. Chunks C20+ assume the loop is fun; if it
isn't, they are all built on sand.

---

## 6. Track C — FTUE, the 80% hole

> Appendix C.2: 79.9% of the competitor's 1.4M players never completed one objective. This track is
> aimed at that single number, and §10's 50% gate is a launch blocker.

---

### C20 — Guaranteed first objective
**Tier** Medium · **Runner** 🤖 · **Deps** C19

§10. A brand-new player's first round spawns a task **near them** with a clear waypoint. This is the
highest-leverage chunk in the plan and it is not a big one.

- Track "has ever completed a task" server-side (in-memory now, in the profile at C40).
- First-round players get one selected task biased to spawn proximity, plus a beam or arrow.
- One contextual line at the moment it's needed: *"Hold to complete the task."* No wall of text.

**Done** a fresh player has a waypointed task within 15 seconds of `ACTIVE`.
**Verify** playtester with a simulated fresh profile; screenshot showing the waypoint.

---

### C21 — Solo Trial: the shell and two tasks
**Tier** Large · **Runner** 🤖 · **Deps** C20 · 🔒 · Plan-backed.

§9.1. Runs in a corner of the map, single-player, 90 seconds, offered below `MinPlayers`.

- Isolated trial state — must not touch or corrupt real round state. This is the actual risk in the
  chunk: `TrialService` and `RoundService` sharing state is how you get a trial that ends a live round.
- Two tasks, teaching the interaction by doing.

**Done** a solo player in an empty server gets a real thing to do within 60s of joining.
**Verify** playtester, one client, empty server, completes both trial tasks. Console shows round state
untouched throughout.

---

### C22 — Solo Trial: the chase and the handoff
**Tier** Medium · **Runner** 🤖 · **Deps** C21

- At `ScriptedChaseAt` (55s) a scripted Aswang transforms and chases. **They learn the tell.**
- Salt is given and taught: *"Salt burns the aswang — throw it to reveal and stun."* (§10 — do not assume
  players know the folklore. Many won't.)
- Ends on *"Now do it when the monster is one of your friends."* → drops into the lobby queue.

**Done** full 90s trial runs end to end and hands off cleanly.
**Verify** playtester runs it start to finish; screenshots at task, chase, salt, handoff.

> ⚠️ **The trap, named in §9.1:** do not let this grow. No second trial, no trial levels, no trial
> rewards beyond the handoff. A PvE campaign is exactly what killed the competitor (C.5).

---

### C23 — Contextual teaching pass
**Tier** Small · **Runner** 🤖 · **Deps** C22

One-liners at the moment of need, everywhere else in the game: first pickup, first ghost death, first
transform witnessed, first two-person task. Each fires once ever, per player.

**Done** every first-time interaction has exactly one line; none repeat.
**Verify** playtester fresh profile through a full round, screenshot each line.

---

### C24 — Lobby is not dead
**Tier** Small · **Runner** 🤖 · **Deps** C23

§9.3. Visible countdown, cosmetic preview stand, tips, and the Solo Trial entrance. A player waiting must
never see a static screen — that reads as *broken*, not as *waiting*, and they leave.

**Done** the lobby has three things to look at and a countdown that is always visible.
**Verify** playtester screenshot of the lobby at `IDLE` and at `INTERMISSION`.

---

## 7. Track D — polish

### C25 — Quick chat wheel
**Tier** Large · **Runner** 🤖 · **Deps** C24 · 🔒 · Plan-backed.

§4.5, and the spec says plainly: **do not cut it.** Accusation gameplay with no way to accuse is not
gameplay. Voice needs 13+ verification most of your audience lacks, and typing mid-chase on a phone is
impossible.

- One button → radial menu, 8 phrases from §4.5, thumb-reachable on a phone.
- `RequestQuickChat` → rate-limited, server-broadcast, **`TextService`-filtered**.
- `"It's [nearest player]!"` resolves the name **server-side**. A client-supplied name is a free
  impersonation exploit.
- Optional world ping.

**Done** all 8 phrases send, filter, and display; the wheel is usable one-handed.
**Verify** playtester on a touch-emulated viewport; screenshot of the wheel and a received message. 🔒.

---

### C26 — Full HUD and the end screen
**Tier** Medium · **Runner** 🤖 · **Deps** C25

Now polish C18, informed by what GATE 1 told you. The end screen is where the reveal lands — §4.8 calls
it the screenshot people share, and §8.4 says the cosmetic shop belongs here and nowhere else.

**Done** every HUD element themed, readable, and animated on change; the reveal has weight.
**Verify** playtester screenshots each phase, plus both win reveals.

---

### C27 — Mobile input and performance
**Tier** Medium · **Runner** 🤝 · **Deps** C26

§5's budget is non-negotiable — 60% of your players are on a phone.

- Touch buttons for transform, interact, throw, quick chat. Thumb zones, not desktop positions scaled down.
- `StreamingEnabled` tuned; dynamic lights capped at `MaxVisibleLights` (8).
- **Test on an actual mid-range Android**, not Studio's emulator. 30fps target.

**Done** 30fps sustained on a real phone during a chase — the worst case, not the lobby.
**Verify** 🧍 you, with a phone in your hand and the stats overlay on. Nothing else counts here.

---

### C28 — Lighting, atmosphere, and the diegetic sunrise
**Tier** Medium · **Runner** 🧍 · **Deps** C19

Future lighting, heavy `Atmosphere` fog, very low ambient, few warm point lights. §5's sightline rule:
you should almost always see *something*. Total darkness is confusing, not scary — fear is *partial*
information.

**The one to actually build:** Appendix C.3 — the competitor's "dynamic sunset-to-night" as **your round
timer**. The sky visibly progressing toward sunrise *is* the countdown. Diegetic, no UI, free tension.
Drive `Lighting.ClockTime` from `RoundSnapshot`'s remaining seconds.

**Done** the sky tracks the round; the map is atmospheric and still readable.
**Verify** screenshots at 0%, 50%, 90% of round duration. Publish after.

---

### C29 — Audio pass
**Tier** Medium · **Runner** 🧍 · **Deps** C28 · Load the `asset-pipeline` skill first.

§5 and §14.3: **audio is half of horror and it's free.** Highest fear-per-hour in the project — budget
real time, not leftovers.

Creator Store audio: ambient night loop, distant dogs, wind, footsteps, heartbeat when the Aswang is
near, transform stinger carrying `TransformAudioRange` (40 studs), the gate opening, the sunrise.

**Done** every listed cue plays at the right moment and range.
**Verify** playtester captures console confirmation of each cue; you listen to a full round with
headphones. There is no automated check for "does this sound scary."

---

### C30 — Map art dressing
**Tier** Medium · **Runner** 🧍 · **Deps** C29

Now dress the greybox — free Creator Store assets and parts. **Do not change the layout**; it passed
GATE 1 and the layout is the thing that was validated. Horror is the most forgiving genre for cheap art:
darkness, fog and lighting hide low-poly geometry. That is a real advantage of the genre you picked.

**Done** the Barrio reads as a Filipino village at night; crossing time unchanged; FPS unchanged.
**Verify** re-measure crossing time and phone FPS — both must match C17 and C27. Publish after.

---

## 8. Track E — the business layer

### C31 — ProfileStore and the data model
**Tier** Large · **Runner** 🤖 · **Deps** C19 · 🔒 · Plan-backed.

§6.6. **Do not hand-roll DataStore access** (§6.1) — session locking and duplication bugs are a solved
problem and solving them again costs you a week.

- ProfileStore (or equivalent session-locked wrapper).
- `SchemaVersion = 1` **and the migration path written on day one**, before you need it. You will change
  the schema; the question is only whether the migration exists when you do.
- Save on meaningful change, on leave, and on `BindToClose` (the hook from C01).
- **Never** trust a client value into the profile.

**Done** data survives rejoin and a server shutdown; a v0 profile migrates to v1 cleanly.
**Verify** `lune run tests/profile-migration.test.luau` on the pure migration function. Playtester:
earn XP, leave, rejoin, XP present. 🔒 mandatory.

---

### C32 — XP, levels, coins
**Tier** Medium · **Runner** 🤖 · **Deps** C31

§7. `src/shared/pure/XPCurve.luau` — `(xp) → (level, progressToNext)`. Awards per §4.8's end screen.

**Done** XP and coins award per round; the level bar fills; both persist.
**Verify** `lune run tests/xp-curve.test.luau` — monotonic, no division by zero at level 1, sane at
level 100.

---

### C33 — Daily login streak
**Tier** Medium · **Runner** 🤖 · **Deps** C32

§7 calls this the single highest-ROI retention feature you can build. Escalating rewards, meaningful
day-7 payoff. UTC day boundaries in a pure function — **timezone bugs here are silent and permanent**,
and a streak that resets wrongly is worse than no streak at all.

**Done** claiming advances the streak; a missed day resets it; day 7 pays out properly.
**Verify** `lune run tests/daily-streak.test.luau` — same day, next day, skipped day, DST, year boundary.

---

### C34 — Six cosmetics
**Tier** Medium · **Runner** 🤝 · **Deps** C33

§7: enough to show progress, not enough to burn your content. §8.2: sell what appears in clips — death
effects, transform auras, lantern colours. Some unlock by level, some by coins, some are gamepass-only
(C37).

**Done** 6 exist, own/equip persists, they render on the avatar.
**Verify** playtester equips each and screenshots it.

---

### C35 — The five funnel badges
**Tier** Medium · **Runner** 🤝 · **Deps** C31

Appendix B. 🧍 create the 5 badges in the Creator Hub, put the IDs in `Config.Badges`. 🤖 wire
`BadgeService` to award them.

`Welcome` · `First Task` · `First Round` · `First Blood` · `Balik-Balik`.

This is your **free, tamper-proof, permanent retention dashboard** — publicly readable via the Roblox API,
which is exactly how Appendix C diagnosed the competitor. `First Task ÷ Welcome` is the number that
killed them (20.1%) and §10's gate says yours must clear **50%**.

**Done** all 5 award correctly; `Config.Badges` has real IDs, not zeros.
**Verify** playtester triggers each condition; confirm the award in the Creator Hub.

---

### C36 — Group, social links, private servers
**Tier** Small · **Runner** 🧍 · **Deps** —

§9.2 — can be done any time, so do it early; it has real-world lead time and it is three launch blockers
in one sitting.

- Create the Roblox group, link it on the store page, set `Config.Community.GroupId`.
- Social links: TikTok, Discord, YouTube.
- **Private servers ENABLED and priced (~100 R$/mo).** §8.2 calls this your #1 earner; the competitor had
  it switched off across 2.5M visits.

**Done** the group exists, links are live, private servers are purchasable.
**Verify** open the store page in a browser and see all four.

---

### C37 — Gamepasses and dev products
**Tier** Small · **Runner** 🧍 · **Deps** C34

§8.2, created in the Creator Hub: Starter Pack (79), Survivor Pack (249), VIP (799), Coin Packs (99/399).

VIP's 2× XP is **cosmetic progression, not round advantage** — that distinction is what keeps an
asymmetric game fair, and §8.3 lists what you must never sell. No extra salt, no revives, no longer
transform, and **no increased Aswang chance**.

**Done** 3 passes + 2 products live and purchasable, IDs in `Config`.
**Verify** buy one yourself from an alt account.

---

### C38 — MonetizationService
**Tier** Large · **Runner** 🤖 · **Deps** C37 · 🔒 · Plan-backed.

- `ProcessReceipt` — **idempotent**, granting before returning `PurchaseGranted`. Getting this wrong
  either double-grants or eats a real purchase; both are unrecoverable and one is a refund request.
- Gamepass ownership cache per `Profile.Purchases.GamepassCacheUTC`.
- Shop **on the end screen only** (§8.4) — never mid-round.

**Done** a purchase grants exactly once and survives a rejoin mid-transaction.
**Verify** playtester buys a dev product in Studio's test mode; confirm single grant and persistence. 🔒.

---

### C39 — Group join reward
**Tier** Small · **Runner** 🤖 · **Deps** C36, C31

§9.2. In-lobby panel, `GroupJoinRewardCoins` (250), claimable once, verified server-side via
`Player:IsInGroup`. Every group member is someone you can re-activate on every update, free, forever.

**Done** reward grants once; re-claim refused; the panel is visible in the lobby.
**Verify** playtester claims, rejoins, is refused the second claim.

---

### C40 — Analytics: every event in Appendix B
**Tier** Medium · **Runner** 🤖 · **Deps** C38

All 15 events, exact names from Appendix B. The funnel that matters:
`joined → reached an ACTIVE round → completed a round → returned on day 2`.

Also track **win rate per side** from day one — Appendix A's tuning target is <60% either way and you
cannot tune what you don't measure. And §9.5's "% of joins that reached an ACTIVE round": if it's low,
players are bouncing off an empty lobby and **every other retention number you have is lying to you**.

**Done** all 15 fire with correct payloads; the funnel is visible in the Creator Hub.
**Verify** playtester plays a round; every expected event appears in the dashboard.

---

### C41 — Anti-cheat sweep
**Tier** Large · **Runner** 🤖 · **Deps** C40 · 🔒 · Plan-backed. **`exploit-auditor` mandatory.**

C02 built the mechanism; this chunk applies it everywhere and turns logging into enforcement.

- Every `OnServerEvent` handler consults `AntiCheatService`. No exceptions, no waivers without a reason.
- Speed and teleport sanity checks.
- Escalation: log → throttle → kick, with thresholds in `Config`.
- **A full re-read of every path the role could leak through** — attributes, tags, sounds played to one
  player, Highlights, backpack contents, speed multipliers. §6.2's *derived hint* problem: none of these
  contain the word "role" and every one is readable by any client.

**Done** `check:ratelimit` and `check:secrecy` clean with no new waivers; `exploit-auditor` finds no
role-leak path.
**Verify** 🔒 mandatory, and its verdict gates the chunk. This is the last structured look at the secret
before real players — some of whom will be actively trying to break it, because knowing the imposter is
worth more here than in almost any other game.

---

## 9. ══ GATE 2 ══

### C42 — M12: playtest #2 and the balance pass
**Tier** — · **Runner** 🧍 · **Deps** C41 · Load the `playtest` skill.

8 players. Tune `Config.luau` until **neither side wins more than ~60%** (Appendix A).

Use Appendix A's table — it already tells you which knob to turn in which direction. Change **one knob at
a time**, commit each with a `balance(...)` prefix so `git log --grep balance` reconstructs what each
session was testing.

`tests/config.test.luau` pins 13 relationships between these numbers (salt reaches further than the
Aswang kills, the reveal outlasts the stun, the kill cooldown outlasts a full transform cycle). If a
tuning change breaks one, that is the test doing its job — **the relationship is the invariant, not the
number.**

**Done** win rate 40–60% either side across ≥10 rounds; notes written.
**Verify** `npm run test:unit` green after every change; win-rate data from C40.

---

## 10. Track F — launch

### C43 — Store page
**Tier** Small · **Runner** 🧍 · **Deps** C42

§13 — 80% of whether anyone clicks.

- **Icon** readable at thumbnail size, one focal image, high contrast.
- **Thumbnails** — the transform moment and a group of survivors. Faces and reactions outperform scenery.
- **Title** stuffed the way theirs was: Tagalog verb + bracket tags. It earned 2.5M visits; that part of
  their execution worked and is free to copy.
- **Description leads with the folklore.** Name the creatures up front, emoji bullets, update promise.

**Done** every §13 store-page box ticked.
**Verify** view the page logged out, on a phone.

---

### C44 — Technical launch checklist
**Tier** Medium · **Runner** 🤝 · **Deps** C43

§13's technical list, every box:
Android + iPhone + PC · exactly 3 players · a full 8 · data across rejoin and shutdown · all remotes
rate-limited · rating questionnaire answered honestly (§4.9 — gore pushes you to 13+ and cuts off the
audience that plays and spends most) · private servers priced · passes purchasable · analytics verified.

**Done** every box ticked with evidence, not memory.
**Verify** `npm run verify` green, plus a written pass over the list.

---

### C45 — Launch
**Tier** — · **Runner** 🧍 · **Deps** C44

§9.4: **a scheduled time announced to a concentrated audience.** A steady 20 players at one hour beats
200 spread across a day — with `MinPlayers = 3` and 8-player servers, concentration is the difference
between full servers and a game that looks dead to everyone who arrives.

3–5 clips ready to post *that day*.

**Then watch one number:** `First Task ÷ Welcome`. If it is under 50%, §10 is unambiguous — stop
everything and fix the FTUE. Not the art, not the shop, not marketing. You will know within a day,
because the badge tells you.

---

## 11. Track M — marketing, from today

> **Not blocked by anything. Do not wait for the game.** §14.1: the game is 20% of the work,
> distribution is 80%. Your reference creator succeeded because he had 308K followers *before* the game
> existed. This track has the longest lead time in the whole plan and it is the one nobody starts on time.

| | Chunk | Cadence |
| --- | --- | --- |
| **M1** | Start the TikTok/Shorts devlog — *"Day N of making my Roblox aswang game"* | Start now, post through the whole build |
| **M2** | Post in Tagalog, target `#robloxphilippines` — underserved, loyal, proven | Every post |
| **M3** | End every post with an engagement question (*"Anong aswang ang idadagdag ko?"*) | Every post |
| **M4** | Recruit your playtest group from the audience (§14.2) | Before C19 — **this gates GATE 1** |
| **M5** | Bank 3–5 launch-day clips | Before C45 |

**M4 is a real dependency.** GATE 1 needs six humans who will show up at an agreed time. If you have not
started building that audience by the time you reach C17, C19 blocks on recruitment, and every chunk
after it blocks on C19.

---

## 12. Quick reference

### Dependency spine

```
C01 ▶ C02 ▶ C03 ▶ C04 ▶ C05 ▶ C06 ─┐
C01 ▶ C07 ▶ C08 ▶ C09 ▶ C10 ▶ C11 ─┼▶ C12
C07 ▶ C13 ▶ C14                    │
C05 ▶ C15 ▶ C16                    │
                                   ▼
              C17 (greybox) ▶ C18 (HUD) ▶ ══ C19 GATE 1 ══
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        ▼                          ▼                          ▼
   C20 ▶ C21 ▶ C22 ▶ C23 ▶ C24   C28 ▶ C29 ▶ C30        C31 ▶ C32 ▶ C33 ▶ C34
        │                                                     │
        ▼                                                     ▼
   C25 ▶ C26 ▶ C27                              C35, C36 ▶ C37 ▶ C38 ▶ C39
                                                              │
                                                    C40 ▶ C41 ▶ ══ C42 GATE 2 ══
                                                              │
                                                    C43 ▶ C44 ▶ C45
```

After GATE 1 the three branches are genuinely independent — FTUE, atmosphere, and the business layer
touch different files. If you ever want to run two agents at once, that is where it is safe.

### Pure modules this plan creates

Each is a decision worth proving, and each makes its chunk verifiable from a terminal instead of by eye.

| Module | Chunk | Test |
| --- | --- | --- |
| `pure/RoundTransitions.luau` | C01 | `tests/round-transitions.test.luau` |
| `pure/TokenBucket.luau` | C02 | `tests/token-bucket.test.luau` |
| `pure/RoleDraw.luau` | C03 | `tests/role-draw.test.luau` |
| `pure/KillValidation.luau` | C05 | `tests/kill-validation.test.luau` |
| `pure/TaskSelection.luau` | C07 | `tests/task-selection.test.luau` |
| `pure/ProfileMigration.luau` | C31 | `tests/profile-migration.test.luau` |
| `pure/XPCurve.luau` | C32 | `tests/xp-curve.test.luau` |
| `pure/DailyStreak.luau` | C33 | `tests/daily-streak.test.luau` |

### Chunks where `exploit-auditor` is mandatory

C01 · C02 · C03 · C04 · C05 · C06 · C08 · C11 · C12 · C14 · C15 · C21 · C25 · C31 · C38 · C41

`review-gate.mjs` names it automatically for those paths — but C03, C12, C15 and C41 are the four where
its verdict should **gate the chunk**, because each is a place the secret can escape.

### Chunks you cannot delegate

**Entirely yours (🧍) — 10:**
C17 greybox · C19 **GATE 1** · C28 lighting · C29 audio · C30 art · C36 group/links/private servers ·
C37 Creator Hub products · C42 **GATE 2** · C43 store page · C45 launch.

**Half yours (🤝) — 4:** C27 (agent writes touch input, you test on a real phone) · C34 (you make the
cosmetics, agent wires them) · C35 (you create the badges, agent awards them) · C44 (agent runs the
gates, you tick the boxes).

Plus all of Track M, which starts before any of them.

**14 of 45 chunks need you at the keyboard.** Two are the gates — and the gates are what decide whether
the other 43 were worth building.
