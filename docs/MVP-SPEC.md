# ASWANG — MVP Specification

**Working title:** `ASWANG: Survive the Night` (Filipino folklore co-op horror)
**Version:** MVP v1.1 spec — v1.0 plus Amendment A1 (§4.8)
**Date:** August 2026 · last amended 2026-08-12
**Author's context:** Solo developer. Strong software engineer, zero game-dev experience, no art budget, no deadline. Goal is profit.

---

## 0. How to use this document

This is your **single source of truth for v1**. Rules:

1. If a feature is not in this document, **it does not go in the MVP.** Write it in `ROADMAP.md` instead.
2. Every number in here is a **starting value to tune**, not a truth. Balance comes from playtesting.
3. Build in the order given in §12. Do not jump ahead to art or monetization.

**The MVP's one job:** prove that the core loop is fun with 6 real players. Everything else is secondary.

---

## 1. The game in one paragraph

6–8 players spawn in a Filipino barrio at night. Most are **Survivors** who must complete randomized tasks around the map and escape before sunrise. One player is secretly the **Aswang** — it looks exactly like a normal survivor. To kill, the Aswang must briefly **transform** into its monstrous form, which anyone nearby can see. So it must catch people alone. Survivors can find **salt** to stun and reveal it. Dead players become **ghosts** who can still help. The round ends when survivors escape or the Aswang kills enough of them.

**The hook in 3 seconds:** *"One of your friends is the monster. Find out before it eats you."*

---

## 2. Design pillars (use these to settle every argument)

| Pillar | Meaning | What it kills |
|---|---|---|
| **Paranoia over jumpscares** | The fear comes from not trusting people, not from loud noises | No cheap screamers, no gore |
| **The monster must risk exposure to kill** | Every kill is a gamble | No invisible/instant kills |
| **Short rounds, fast restart** | Under 8 minutes, back in within 30 seconds | No long lobbies, no long cutscenes |
| **Every round produces a story** | "I saw him transform behind you!" | No mechanic that makes rounds identical |
| **Readable on a phone in one hand** | 60% of players are mobile | No tiny text, no complex controls |

---

## 3. MVP scope — the hard line

### ✅ IN (build these)

- 1 map: **Barrio (village at night)**
- 1 monster: **Aswang** (mimic/imposter)
- 6–8 player servers, minimum 3 to start a round
- Round state machine + lobby + intermission
- **5 randomized tasks** drawn from a pool of ~12 spawn points, **4 task types**
- Transform-to-kill mechanic
- **Salt** (the one counterplay item)
- Ghost mode for dead players
- Win/lose end screen with the reveal
- Quick-chat wheel (non-verbal communication)
- Progression: XP, level, soft currency, daily reward, ~6 unlockable cosmetics
- Monetization: 3 gamepasses, 2 dev products, private servers — **live on launch day, not "later"**
- Mobile-first UI + performance budget
- Analytics events + basic anti-exploit
- **Solo Trial** — a 90-second single-player practice run (doubles as tutorial *and* low-population fallback) — see §9.1
- **5 funnel badges** mirroring the retention funnel — see Appendix B
- **Community capture** — Roblox group + social links + a group-join reward — see §9.2

> The last three were added after tearing down a competitor that got **2.5M visits and earned $0**. See **Appendix C**. They are not nice-to-haves; each one plugs a hole that provably killed a game with this exact theme.

### ❌ OUT (v2+, write them in ROADMAP.md and stop thinking about them)

- Manananggal, Tiktik, Kapre, Tiyanak — **all other monsters**
- All other maps (church, hospital, palengke, balete forest)
- **Emergency meetings / voting** — see §4.5, this is a deliberate design cut
- Trading, guilds, pets, leaderboard seasons
- Custom animations, custom monster mesh, voice acting
- Multiple Aswangs per round
- Sabotage / power systems
- Weapons or combat beyond salt

> **Why so small?** Two reasons. First, unfinished games earn zero. Second, every monster and map you *withhold* becomes a free TikTok video, a hype spike, and a reason lapsed players return. **Your roadmap is your marketing calendar.** Do not spend it all at launch.

---

## 4. Game design detail

### 4.1 Round flow & timings

| Phase | Duration | What happens |
|---|---|---|
| `IDLE` | until 3+ players | Lobby. Players walk around, see cosmetics, read tips. |
| `INTERMISSION` | 25s | Countdown. Shows map name + tip of the round. |
| `STARTING` | 4s | Roles assigned server-side, players teleported, screen fade. |
| `ACTIVE` | 420s (7 min) | The round. Sunrise timer visible to all. |
| `ENDING` | 12s | Reveal the Aswang, show stats, award XP/coins. |
| → back to `INTERMISSION` | | |

**Total cycle ≈ 7.5 min.** A player joining mid-round becomes a spectator/ghost until the next round — they must not wait more than ~4 minutes to actually play. If a joining player would wait more than half the round, consider showing a "next round in Xs" prompt so it doesn't feel dead.

### 4.2 Roles

| Role | Count (8 players) | Goal |
|---|---|---|
| Survivor | 7 | Complete 5 tasks → escape gate opens → reach it |
| Aswang | 1 | Kill until survivors ≤ 2, or run out the clock with tasks unfinished — *counted as kills; see Amendment A1, §4.8* |

**Role assignment rules:**
- Server-side only. **Never** replicate the Aswang's identity to any other client. Not in a tag, not in a name colour, not in an attribute, not "hidden" in a value the client can read. Assume every client is compromised.
- **Anti-repeat:** track the last 2 rounds; a player who was Aswang last round has heavily reduced weight. Nothing kills a session faster than never being the monster — or being it three times in a row.
- Aswang gets a 3-second private intro ("You are the Aswang. Do not get seen.").

### 4.3 The kill mechanic — the heart of the game

This is the most important system. Get it right.

1. Aswang presses **Transform** (mobile button / key).
2. **1.2s transform animation** — visible to anyone with line of sight. Distinct silhouette, red eye glow, audio cue that carries ~40 studs.
3. While transformed: **+25% move speed**, can kill on touch/prompt within 8 studs.
4. After a kill (or after 8s), it must **revert** (1.0s). Corpse remains for 45s, then fades.
5. **Kill cooldown: 30s** from revert.

**Why this design works:**
- It creates the game's signature clippable moment: *witnessing the transform.*
- It gives survivors real information without any UI — grouping up is genuinely protective.
- It makes the Aswang's decision tense: kill now and risk being seen, or wait.
- It is **cheap to build** — no custom monster model needed. Reuse the player avatar with a scale change, a colour/material shift, glowing eyes, and a particle emitter.

**Rules to enforce server-side:** distance ≤ 8 studs, raycast line-of-sight, cooldown elapsed, both alive, round `ACTIVE`. The client only *requests* a kill; the server decides.

### 4.4 Tasks — variety is the anti-boredom system

**The rule: 12 possible task locations exist on the map. Each round randomly picks 5.** Players cannot memorise a route. This one decision keeps a single map fresh for dozens of plays and costs you almost nothing to build.

Four task types (build each once, reuse across all 12 spawn points):

| Type | Interaction | Duration | Why it's here |
|---|---|---|---|
| **Hold** | Hold a ProximityPrompt (light candles, pump water) | 8s | Forces you to stand still and vulnerable |
| **Timing** | Stop a moving bar in a green zone, 3 attempts | ~10s | Small skill moment; failure is funny |
| **Fetch** | Pick up an item elsewhere, bring it back | 20–30s | Forces travel across the map — creates isolation |
| **Two-person** | Requires 2 survivors present at once | 12s | Forces trust; the Aswang can "help" and betray you |

**Progression rule:** a global task bar shows overall progress (not who did what). At 5/5, the **escape gate opens** and survivors must physically reach it — the finale, and the best clip moment in the game.

**Anti-frustration:** tasks are assigned to the *world*, not to individuals. Anyone can do any task. This prevents a dead player's tasks from becoming unwinnable and removes a whole class of bugs.

**Aswang and tasks:** the Aswang sees a fake task list and can fake-perform the animation, but its progress does not count. This is essential — otherwise "who is standing at tasks" trivially identifies it.

### 4.5 Communication — the piece almost everyone gets wrong

Your accusation gameplay is worthless if players can't communicate. Reality check:

- Roblox **voice chat requires age verification (13+)** — most of your audience won't have it. **Do not design around voice.**
- Text chat exists and is filtered, but **typing on a phone mid-chase is impossible.**

**Therefore the MVP ships a Quick-Chat Wheel** (one button → radial menu, 8 phrases, sends a filtered preset + optional world ping):

`"I saw it transform!"` · `"Body here!"` · `"Follow me"` · `"It's [nearest player]!"` · `"Task here"` · `"Run!"` · `"I'm alone"` · `"Trust me"`

This is a small system with an outsized effect on how fun the game is. **Do not cut it.**

### 4.6 Salt — the counterplay item

If survivors are helpless, the game is not fun; it's just losing.

- 4 salt pouches spawn at random fixed points per round. One per player carried.
- Throw at the Aswang → **stuns it for 4s**, forces revert, and applies a **visible glow for 10s** (a temporary reveal).
- Recharge: none in MVP. Once used, it's gone. Scarcity makes it a decision.

This is the folklore weakness turned into a mechanic — the differentiator you wanted, built cheaply.

### 4.7 Ghosts — the retention fix nobody thinks about

**The problem:** in elimination games, the first person to die is bored for 6 minutes and leaves. That's a retention leak and it's silently fatal.

**The fix:** a dead survivor becomes a **ghost**:
- Can fly slowly around the map, sees other ghosts, has a ghost-only chat.
- Can **contribute**: hold a task point to add a small amount of progress (say 25% speed) — they still matter.
- Can trigger one **spook** per round (flicker a nearby light, rustle a bush) — no information, pure flavour, but it keeps them playing with the living.
- **Cannot** reveal the Aswang's identity to living players. Enforce server-side; ghost chat must be a separate channel.

### 4.8 Win / lose conditions

| Outcome | Condition |
|---|---|
| **Survivors win** | 5/5 tasks done AND at least 1 survivor reaches the escape gate |
| **Aswang wins** | Living survivors ≤ 2, **or** sunrise timer hits 0 with tasks incomplete |

> **Amendment A1 — 2026-08-12 · spec v1.0 → v1.1 · implemented in `0b46597`**
>
> The row above stands as the design intent and is unchanged. What follows is how it is **measured**,
> because the sentence as written is ambiguous in two situations it was not thinking about.
>
> **The shipped rule counts the Aswang's KILLS, not the survivors present.** The Aswang wins when
> `AswangKills ≥ DealtInSurvivors − 2`, floored at one kill, where `DealtInSurvivors` is frozen at
> `STARTING`. The sunrise-timeout half is unchanged.
>
> **Why.** "Living survivors" counts *absence*, and absence has four causes: killed, disconnected,
> hit the reset button, fell out of the map. Only the first is the Aswang's doing, so the literal
> reading hands it the other three. Measured: an 8-player round where three alt accounts quit as
> `ACTIVE` begins turns a five-kill win into a two-kill win. A second problem is smaller but arrives
> sooner — at `Round.MinPlayers = 3` a round is one Aswang and two survivors, so "survivors ≤ 2" is
> already true on tick one, with nobody dead.
>
> **What this does and does not change.** With a full roster and nobody leaving, the two formulations
> produce **identical outcomes** — 8 players still needs five kills, killing everyone still wins. The
> only behaviour that changed is that a player *leaving* no longer advances the Aswang. If enough quit
> that the bar becomes unreachable the round simply runs to sunrise, which this table already scores as
> an Aswang win, so neither side is rewarded for disconnects.
>
> **Where it lives.** `src/shared/pure/WinConditions.luau`, with the roster × kills grid in
> `tests/win-conditions.test.luau`. Three earlier patches tried to preserve the presence formulation and
> each failed differently; the third was arithmetically inert. That history is in
> `.claude/plans/feature-c05-c07-kill-win-taskselect-plan/implementation-log.md`.

End screen: reveal the Aswang (big dramatic moment — **this is the screenshot people share**), show per-player stats, award XP and coins.

### 4.9 Tone and rating — a business constraint disguised as a design note

Roblox assigns an age rating based on a content questionnaire. **Blood, gore, and intense violence push you to 13+ and cut off a large part of your audience** — the exact audience that plays and spends the most.

**Design for "creepy and tense," not graphic.** Kills should be a grab, a scream, a fade to black — no blood pools, no dismemberment. This is not censorship; **atmosphere scares harder than gore**, and it protects your addressable market. Answer the rating questionnaire honestly; a misrated game gets penalised.

---

## 5. The map — Barrio (v1)

**Size target: small.** A map that takes ~35 seconds to cross end-to-end. New devs build maps far too big; big maps mean players never meet, and empty maps feel dead — especially at low player counts.

**Required zones:**
- Central plaza (spawn + escape gate) — the "safe-ish" social hub
- 6–8 bahay kubo / small houses, at least 3 enterable
- A chapel (one interior, strong lighting moment)
- Rice field edge (tall grass, low visibility — the killing field)
- A well / water pump area
- 2–3 narrow alleys creating **loops, never dead ends** (dead ends are unfair; loops create chases)

**Sightline rule:** you should almost always be able to see *something* — a lantern, a silhouette, a doorway. Total darkness is not scary, it's just confusing. Fear comes from *partial* information.

**Art strategy (zero budget):**
- Build with **parts and free Creator Store assets.** Horror is the most forgiving genre for cheap art — darkness, fog, and lighting hide low-poly geometry. This is a genuine advantage of the genre you chose.
- Use **Future lighting**, heavy `Atmosphere` fog, very low ambient, and a small number of warm point lights.
- **Audio matters more than visuals in horror.** Use Roblox Creator Store audio (licensed and free to use in experiences). Ambient night loop, distant dogs, wind, footsteps, heartbeat when the Aswang is near. Budget real time for this — it's the cheapest fear-per-hour you can buy.

**Mobile performance budget (non-negotiable):**
- Enable `StreamingEnabled`.
- **Cap dynamic lights to ~8 visible at once** — many point lights are the #1 mobile FPS killer.
- Keep part count modest; avoid unions where a part will do.
- Test on an actual phone, not just Studio. Target 30fps on mid-range Android.

---

## 6. Technical architecture (senior engineer lens)

### 6.1 Toolchain — set this up first, you'll thank yourself

You're an engineer; don't work the way hobbyists do.

| Tool | Why |
|---|---|
| **Rojo** | Sync code from the filesystem into Studio. Lets you use real tooling. |
| **VS Code + Luau LSP** | Types, autocomplete, diagnostics |
| **Git** | Version control. Studio's built-in history is not enough. |
| **ProfileStore** (or similar session-locked DataStore wrapper) | Prevents data loss and duplication bugs. Do **not** hand-roll DataStore access. |
| **Selene / StyLua** | Lint + format |

Roblox Studio remains where you build the map, lighting, and physical assets. Code lives in the filesystem.

### 6.2 Server-authoritative model — the one rule

> **The client is an untrusted renderer and input device. Nothing else.**

Specifically for this game:
- The Aswang's identity is **server-only state**. It is never sent to other clients in any form.
- Clients *request* actions (`RequestKill`, `RequestTaskProgress`, `RequestThrowSalt`). The server validates and decides.
- Every RemoteEvent is **rate-limited** and validates types, state, distance, and cooldown.
- The transform *is* public — that's intentional design, so replicating it is correct.

**Exploiters will target this game specifically** because knowing the imposter is so valuable. This is where your engineering background is a genuine competitive advantage over the typical Roblox dev.

### 6.3 Module layout

```
ServerScriptService/
  Services/
    RoundService.lua        -- state machine, timers, phase transitions
    RoleService.lua         -- secret role assignment, anti-repeat weighting
    TaskService.lua         -- pick 5 of 12, validate progress, global bar
    MonsterService.lua      -- transform, kill validation, cooldowns
    ItemService.lua         -- salt spawn, pickup, throw, stun/reveal
    GhostService.lua        -- death → ghost, ghost abilities, ghost chat channel
    ProgressionService.lua  -- XP, level, coins, daily streak
    MonetizationService.lua -- gamepasses, ProcessReceipt, private servers
    AnalyticsService.lua    -- event emission
    AntiCheatService.lua    -- rate limits, speed/teleport sanity checks
  init.server.lua

ReplicatedStorage/
  Shared/
    Config.lua              -- ALL tunable numbers (see 6.5)
    Types.lua               -- Luau type definitions
    Enums.lua               -- RoundPhase, Role, TaskType
    Remotes/                -- RemoteEvent/Function definitions

StarterPlayer/StarterPlayerScripts/
  Controllers/
    UIController.lua        -- HUD, task bar, sunrise timer, end screen
    InputController.lua     -- mobile buttons, keyboard binds
    QuickChatController.lua -- the radial wheel
    CameraFXController.lua  -- vignette, shake, proximity heartbeat
    AudioController.lua
```

### 6.4 Round state machine

```
IDLE ──(players ≥ 3)──> INTERMISSION ──(25s)──> STARTING ──(4s)──> ACTIVE
  ^                                                                    │
  └────────────(players < 3)──── ENDING <──(win/lose/timeout)─────────┘
```

Implement as an explicit enum + single `SetPhase()` function that fires one `PhaseChanged` remote. **Never** let gameplay code mutate phase directly. Every service subscribes to phase changes. This keeps a notoriously bug-prone area debuggable.

**Edge cases to handle explicitly (these will bite you):**
- The Aswang **leaves mid-round** → end round immediately, no XP penalty for survivors, brief "the Aswang fled" message.
- Player count drops below minimum mid-round → finish the round, then return to `IDLE`.
- A player joins mid-round → spectator until `ENDING`.
- Last survivor and Aswang both alive at timer end → Aswang wins (tasks incomplete).
- Server shutdown → `game:BindToClose()` must flush all player data.

### 6.5 Config module — make balance data-driven

Put **every** tunable number in one `Config.lua`. You will change these constantly during playtesting, and hunting magic numbers across 10 files is how a weekend disappears.

```lua
return {
  Round = { Intermission = 25, Duration = 420, EndScreen = 12, MinPlayers = 3, MaxPlayers = 8 },
  Roles = { AswangCount = 1, RepeatCooldownRounds = 2 },
  Monster = {
    TransformTime = 1.2, RevertTime = 1.0, KillRange = 8,
    KillCooldown = 30, TransformedSpeedMult = 1.25, MaxTransformTime = 8,
  },
  Tasks = { TotalRequired = 5, PoolSize = 12, HoldTime = 8, FetchTime = 25, TwoPersonTime = 12 },
  Salt = { SpawnCount = 4, StunDuration = 4, RevealDuration = 10, ThrowRange = 25 },
  Ghost = { TaskContributionMult = 0.25, SpooksPerRound = 1 },
  Economy = { XPPerRound = 50, XPWinBonus = 40, CoinsPerRound = 25 },
}
```

### 6.6 Data model (per player, session-locked)

```lua
Profile = {
  SchemaVersion = 1,           -- migrate on read; you WILL change this
  XP = 0, Level = 1, Coins = 0,
  Stats = { Rounds=0, Survived=0, AswangRounds=0, AswangWins=0, Kills=0, TasksDone=0 },
  Cosmetics = { Owned = {}, Equipped = { Skin="default", Lantern="default", DeathFX="default" } },
  Daily = { LastClaimUTC = 0, Streak = 0 },
  Purchases = { GamepassCacheUTC = 0 },
}
```

Rules: version from day one and write the migration path. Save on meaningful change + on leave + on `BindToClose`. Never trust a client-supplied value into this table.

---

## 7. Progression & retention (the money is here, not in the shop)

Monetization follows retention. Ship these:

- **XP + Levels** — visible bar, levels unlock cosmetics. Cheap to build, strong pull.
- **Daily login streak** — escalating rewards with a meaningful day-7 payoff. The single highest-ROI retention feature you can build.
- **Soft currency (coins)** — earned per round, spends on cosmetics. Gives non-payers a goal and makes paid cosmetics legible in value.
- **Unfinished business** — end the session near a milestone ("2 rounds to level 5") so there's a reason to come back.
- **~6 unlockable cosmetics at launch** — enough to see progress, not enough to burn your content.

**Targets to hold yourself to:**

| Metric | Red | OK | Good |
|---|---|---|---|
| Day-1 retention | <20% | 25–30% | 35%+ |
| Day-7 retention | <8% | 10–15% | 18%+ |
| Avg session | <6 min | 10–15 min | 20 min+ |
| Rounds per session | <2 | 3 | 4+ |
| Paying conversion | <0.5% | 1–2% | 3%+ |

> **If Day-1 retention is under 30%, do not spend a single peso on ads or a single hour on monetization. Fix the first five minutes instead.** Marketing a leaky game just burns money faster.

---

## 8. Monetization (business lens)

### 8.1 The rule for *this* genre

Horror can't sell "2x speed" the way a simulator can — there's no grind to skip, and any in-round advantage **breaks the fairness that makes an asymmetric game fun.** So you sell three things:

**Social access · Identity · Convenience — never advantage.**

### 8.2 What to sell

| Product | Type | Price (R$) | Why it works |
|---|---|---|---|
| **Private Server** | Roblox private server | ~100/mo | **Your #1 earner.** Friend groups will pay to play without randoms. Recurring revenue, perfect fit for co-op horror. Enable it at launch. |
| **Starter Pack** (1 skin + 1 emote) | Gamepass | 79 | Breaks the first-purchase barrier. Once a player buys *anything*, they're 3–4x likelier to buy again. |
| **Survivor Pack** (2 exclusive skins + lantern skin) | Gamepass | 249 | Mid-tier identity purchase |
| **VIP** (exclusive aura, 2x XP, VIP lobby area, name colour) | Gamepass | 799 | Top of ladder. 2x XP is cosmetic progression, **not** round advantage — this stays fair. |
| **Coin Pack (small / large)** | Dev product | 99 / 399 | Repeatable revenue from loyal players |

**Ladder logic:** a tiered set of 3+ passes materially outperforms one big pass. Entry tier exists to convert first-time buyers, not to earn.

**Sell cosmetics that appear in clips** — death effects, transform auras, lantern colours, emotes. Your game manufactures screenshots; players pay to look good in them. **The clippable moment is also the sales engine.**

### 8.3 Explicitly do NOT sell (in MVP)

- ❌ Extra salt, extra lives, revives, see-through-walls, longer transform — all break asymmetric fairness
- ❌ **"Higher chance to be the Aswang"** — common on Roblox, but in a 1-imposter game it directly takes the fun role from non-payers and breeds resentment. If you ever add it, disclose it plainly and cap it hard. My recommendation for MVP: **skip it.**

### 8.4 Placement

Contextual offers convert far better than a passive shop button. Show the cosmetic shop **on the end screen** (when the player just had a great round and is waiting anyway), never mid-round.

### 8.5 The honest revenue math

Roblox takes ~30% of a gamepass sale, then DevEx converts earned Robux at roughly **$0.0038** each, with a **30,000 Robux (~$114) minimum cashout**. Practically: **~100 R$ of sales nets you around $0.25.**

**Expect your first game to earn near zero.** ~85% of Roblox developers earn under $100/month. Treat v1 as the asset that builds an audience and teaches you the platform. That is not pessimism — it's the correct baseline to plan against so you don't quit at week six.

---

## 9. The cold-start problem — your single biggest business risk

**A multiplayer-only game with no players is unplayable.** Not "less fun" — literally cannot be played. This kills more multiplayer indie games than bad design does, and it's the risk most first-time devs never see coming.

Mitigations, all of which belong in the MVP:

1. **Set `MaxPlayers` to 8, not 20.** Small servers fill faster and feel full sooner.
2. **`MinPlayers = 3`.** The game must be playable, even if imperfect, with 3 people. Test that it is.
3. **Make the lobby not-dead time** — a small activity, cosmetic preview, and a visible countdown so waiting doesn't read as "broken game."
4. **Launch at a scheduled time to a concentrated audience.** Announce "we play at 7PM" to your TikTok following. Concentration beats trickle. A steady 20 players at one hour is worth more than 200 spread across a day.
5. **Track "% of joins that reached an ACTIVE round."** If it's low, players are bouncing off an empty lobby and your retention numbers are lying to you.

### 9.1 Solo Trial — borrowed from the competitor's one real strength

Takbo Aswang was PvE, so it **always worked with one player**. Yours does not — below 3 players there is no game at all. When your traffic arrives in TikTok waves, anyone who lands during a dead hour currently gets *nothing*, and they never come back.

**The fix — a Solo Trial in the lobby.** A ~90-second single-player run in a corner of the map:

- Complete two tasks to learn the interaction.
- A scripted Aswang transforms and chases you. You learn the tell, and you learn to throw salt.
- Ends with: *"Now do it when the monster is one of your friends."* → drops you into the lobby queue.

It does three jobs at once:

| Job | Why it matters |
|---|---|
| **Tutorial** | Teaches tasks + the transform tell + salt, by doing — fixes the FTUE hole in §10 |
| **Cold-start fallback** | Below `MinPlayers`, players have something real to do instead of staring at a countdown |
| **Retention insurance** | A player arriving at 3am still experiences the game instead of bouncing forever |

**This does not change the heart of the game.** The multiplayer social loop is still the whole point; the Trial exists only to get people *into* it. Do not let it grow into a PvE campaign — that is exactly the trap that killed the competitor.

### 9.2 Community capture — the hole that cost them everything

Takbo Aswang had **1.43M unique players, zero social links, and no group.** All of that traffic passed through and left no way to ever reach those people again. When they shipped updates, they had nobody to tell.

**Build the funnel from traffic → owned audience on day one:**

- A **Roblox group** for the game, linked on the store page. Give a small in-game reward for joining (a cosmetic, a coin bonus) — group members can be notified of updates for free.
- **Social links** on the store page: TikTok, Discord, YouTube. They cost nothing and they were absent from a game with 2.5M visits.
- An in-lobby **"Join the group / follow the TikTok"** panel with the reward attached.

Every player who joins your group or follows the TikTok is a player you can **re-activate on every update, for free, forever.** That is the difference between a game that spikes once and a game that compounds.

---

## 10. First-time user experience (FTUE) — where the competitor actually died

This is no longer a matter of opinion. Takbo Aswang's public badge counts give the exact funnel:

| Stage | Players | Conversion |
|---|---|---|
| Entered the game | **1,429,383** | — |
| Completed their **first objective** | **287,147** | **20.1%** |
| Survived **one round** | **62,206** | **4.4%** of joiners |

**Roughly 4 out of 5 people who opened that game never finished a single task.** Not "didn't come back" — never completed one objective, ever. The theme delivered 1.4M people to the door and the first five minutes threw away 80% of them.

**That is the failure to design against.** Everything below is aimed at that one number.

### Hard rules

- **Player must be doing something meaningful within 60 seconds of joining** — either a live round or the Solo Trial (§9.1). Never a countdown on an empty lobby.
- **Guarantee the first objective.** A brand-new player's first round spawns a task near them with a clear waypoint. Do not let their first experience be wandering a dark map with no idea what to do — that is precisely what 1.1M people quit over.
- **Teach by doing, not by reading.** No wall of text. Contextual one-liners at the moment they're needed: "Hold to complete the task."
- **Teach the folklore.** Do not assume players know salt stops an aswang. On first pickup: *"Salt burns the aswang — throw it to reveal and stun."*
- Every second of non-gameplay costs you players. No splash screens, no long cutscenes.

### The gate — treat this as a launch blocker

> **If fewer than 50% of joiners complete a first objective, stop everything and fix the FTUE.** Not the art, not the shop, not marketing. Their number was 20%. Yours must clear 50%, and you will know within a day of launch because the badge tells you.

---

## 11. Risks & mitigations

Rows marked **⚑** are confirmed kills — they are what actually destroyed Takbo Aswang (Appendix C), not hypotheticals.

| Risk | Severity | Mitigation |
|---|---|---|
| **⚑ FTUE drop-off — players quit before their first objective** | 🔴 Critical | §10 — guaranteed first task, Solo Trial, 50% badge gate. *Their number was 20%.* |
| **⚑ Traffic arrives and is never captured** | 🔴 Critical | §9.2 — group + social links + join reward, live at launch. *They had 1.43M players and no way to reach any of them.* |
| **⚑ Monetization never ships** | 🟠 High | Private servers + 1 gamepass are a launch blocker (§13). *They monetized 2.5M visits at exactly $0.* |
| **⚑ Content runs out** | 🔴 Critical | Randomized tasks + human monster (§4.4). Never add a "campaign." *Their 7 hand-built zones were consumed and that was that.* |
| Empty servers (cold start) | 🔴 Critical | §9 — small servers, low minimum, Solo Trial fallback, scheduled launch |
| Asymmetric balance is hard | 🔴 High | Config-driven numbers, 3+ structured playtests before launch, tune on data |
| Exploiters revealing the Aswang | 🔴 High | Strict server authority, role never leaves server, rate limits |
| Players can't communicate | 🟠 High | Quick-chat wheel (§4.5) — do not cut it |
| Dead players quit | 🟠 High | Ghost system (§4.7) |
| Scope creep → never ships | 🔴 Critical | §3 hard line. Everything else goes in ROADMAP.md |
| Mobile performance | 🟠 Medium | Light cap, StreamingEnabled, test on a real phone |
| Rating hits 13+ | 🟠 Medium | No gore, creepy-not-graphic (§4.9) |
| Data loss / duplication | 🟠 Medium | ProfileStore session locking, schema versioning, BindToClose |
| Genre is heavily cloned | 🟠 Medium | Win on theme + the transform mechanic + Filipino folklore niche |

---

## 12. Build order (do it in this sequence)

Each milestone should end in something **playable**. Never build two systems deep without testing.

| # | Milestone | Definition of done |
|---|---|---|
| **M0** | Toolchain | Rojo syncing, Git repo, Luau LSP working, empty place publishes |
| **M1** | Round skeleton | State machine cycles IDLE→…→ENDING with no gameplay. Timers correct. Handles players leaving. |
| **M2** | Roles + kill | Roles assigned secretly. Transform, kill, corpse, cooldown all server-validated. |
| **M3** | Tasks + win | 5-of-12 randomization, 4 task types, global bar, escape gate, both win conditions fire. |
| **M4** | Salt + ghosts | Salt stuns/reveals. Dead players become contributing ghosts with separate chat. |
| **M5** | **First playtest** | 6 real humans, 5 rounds. **Is it fun?** Write down what they said. |
| **M6** | **Solo Trial + FTUE** | 90-second practice run works with 1 player. New player reaches a first objective in under 60s. |
| **M7** | UI + quick chat + mobile | Full HUD, radial wheel, tested on an actual phone at 30fps |
| **M8** | Map art + audio + lighting | Barrio dressed, fog/lighting pass, ambient + stingers. The atmosphere pass. |
| **M9** | Progression + data + badges | XP, levels, coins, daily streak, ProfileStore with migration, 5 funnel badges awarding |
| **M10** | Monetization + community | 3 gamepasses, 2 dev products, private servers ON, group + social links + join reward |
| **M11** | Analytics + anti-cheat | Events firing, funnel visible, rate limits on every remote |
| **M12** | **Playtest #2 + balance** | 8 players, tune Config until neither side wins >60% |
| **M13** | Launch prep | §13 checklist complete |

> **M5 is the real gate.** If 6 people don't want a 6th round, no amount of art, monetization, or marketing will save it — **change the design then, not after launch.** This is the cheapest moment in the entire project to be wrong.

> **M6 is the second gate, and it's the one the competitor failed.** They had a game people wanted to play and lost 80% of them before the first objective. Do not skip past M6 because the multiplayer already "works for you" — you already know how to play it. New players don't.

---

## 13. Launch checklist

**Store page (this is 80% of whether anyone clicks):**
- [ ] **Icon** — readable at thumbnail size, one clear focal image, high contrast
- [ ] **Thumbnails** — show the transform moment and a group of survivors; faces/reactions outperform scenery
- [ ] **Title with searchable keywords** — include both "Aswang" (Filipino search) and an English hook. *Copy the competitor's bracket-tagging pattern — `Takbo Aswang [Pinoy Horror: Mount Luntian]` stuffs "Pinoy," "Horror," and the location into one searchable line. That part of their execution worked: 2.5M visits.*
- [ ] **Description leads with the folklore roster.** Theirs named Aswang, Tikbalang, and Tiyanak up front and used emoji-bulleted feature lists. It got the clicks — the game behind it is what failed.
- [ ] **Description** with keywords, how to play, and update promise

**🚨 Launch blockers — the competitor shipped without these and earned $0 on 2.5M visits:**
- [ ] **Private servers ENABLED** (they had `createVipServersAllowed: false` — the single best earner for co-op horror, switched off)
- [ ] **At least 1 gamepass live and purchasable** (they had zero, on 1.43M unique players)
- [ ] **Roblox group created, linked, with a join reward** (they had no group)
- [ ] **Social links on the store page** — TikTok, Discord (they had none)
- [ ] **All 5 funnel badges live and awarding** — verify each fires before launch, or you fly blind

**Technical:**
- [ ] Tested on Android phone, iPhone, and PC
- [ ] Tested with exactly 3 players (minimum viable round)
- [ ] Tested a full server (8)
- [ ] Data saves correctly across rejoin and server shutdown
- [ ] All remotes rate-limited
- [ ] Content rating questionnaire answered honestly
- [ ] Private servers enabled and priced
- [ ] Gamepasses and dev products live and purchasable
- [ ] Analytics events verified in the Creator Hub dashboard

**Marketing (start weeks BEFORE launch):**
- [ ] TikTok/Shorts channel posting the build-in-public devlog ("Day N of making my Roblox aswang game")
- [ ] Posting in Tagalog, targeting `#robloxphilippines` — an underserved, loyal, proven niche
- [ ] Every post ends with an engagement question ("Anong aswang ang idadagdag ko?")
- [ ] 3–5 clips **ready to post on launch day** (creators posting within 48h of launch see far higher reach)
- [ ] A scheduled launch time announced to the audience (see §9)

---

## 14. Things you might still be overlooking

1. **The game is 20% of the work. Distribution is 80%.** Your reference creator (@bossramzcpm) succeeded because he built a 308K-follower audience *before* the game. **Start posting now, during the build** — not at launch. The devlog is the marketing.
2. **Playtesting is not optional for asymmetric games.** You cannot balance 1-vs-7 alone in Studio. Recruit real testers early — your TikTok audience is also your test group.
3. **Audio is half of horror and it's free.** Budget real hours for the Creator Store audio pass. Highest fear-per-hour in the project.
4. **Name and icon decide clicks before anyone plays.** Treat them as features, not afterthoughts.
5. **Ship, then update relentlessly.** Abandoned games collapse fast; updating games get re-promoted by the algorithm and by returning players. Each new monster from your roadmap is an update *and* a video *and* a retention spike.
6. **Instrument everything and trust the numbers over your feelings.** This is your unfair advantage as an engineer — most Roblox devs iterate on vibes. You don't have to.
7. **Your first game's real product is the audience and the skill.** The second or third game is where money realistically shows up. Plan a career, not a lottery ticket.

---

## Appendix A — Balance starting values (tune, don't trust)

| Knob | Start | Raise if… | Lower if… |
|---|---|---|---|
| Round duration | 420s | Survivors rarely finish tasks | Rounds drag / players idle |
| Kill cooldown | 30s | Aswang wins too often | Aswang can't get kills |
| Transform time | 1.2s | Aswang too sneaky | Aswang always caught |
| Kill range | 8 studs | Kills feel unreliable | Kills feel unfair/ranged |
| Tasks required | 5 | Survivors win too fast | Tasks never finish |
| Salt spawns | 4 | Aswang dominates | Aswang never lands a kill |

**Target: neither side wins more than ~60% of rounds.** Track win rate per side in analytics from day one — you cannot tune what you don't measure.

---

## Appendix B — Analytics events to emit from day one

`player_joined` · `round_started` (playerCount) · `role_assigned` (role) · `task_completed` (type, secondsIntoRound) · `player_killed` (secondsIntoRound, wasIsolated) · `transform_witnessed` · `salt_used` (hit/miss) · `round_ended` (winner, duration, survivorsAlive) · `player_left` (phase, secondsInSession) · `shop_opened` · `purchase_completed` (productId) · `daily_claimed` (streak) · `trial_started` · `trial_completed` · `group_join_reward_claimed`

**The funnel that matters most:** `joined → reached an ACTIVE round → completed a round → returned on day 2`.

### The 5 funnel badges (ship all of these)

Badges are permanent, free, and their award counts are **publicly readable via the Roblox API** — which is exactly how the competitor's failure was diagnosed. Mirror your funnel in badges and you get a durable, tamper-proof retention dashboard for free.

| Badge | Awarded when | Reads as |
|---|---|---|
| `Welcome` | First join | Denominator — total unique players |
| `First Task` | First objective completed **ever** | **The number that killed them (20.1%). Target >50%.** |
| `First Round` | Survived or lost a full round | Did they get the actual game? |
| `First Blood` | First round as the Aswang | Are people reaching the fun role? |
| `Balik-Balik` ("came back") | Played on a second, separate day | **Day-2 retention, measured directly** |

Two caveats: your competitors can read these too, and badge counts are unique-player lifetime totals, not daily rates — so use them as a coarse funnel, and use in-game analytics for anything time-sensitive.

---

## Appendix C — Competitive teardown: *Takbo Aswang [Pinoy Horror: Mount Luntian]*

The closest existing game to ours by theme. Studied so we inherit its audience validation without
inheriting its mistakes. **All figures pulled from public Roblox APIs, August 2026.**

`roblox.com/games/111418440586995` · universe `7202870472` · creator `Nasraula`

### C.1 The numbers

| Metric | Value |
|---|---|
| Created → last updated | Feb 2025 → **June 2026** (16 months of active development) |
| Visits | **2,525,750** |
| Unique players (Welcome badge) | **1,429,383** |
| Favourites | **190,427** |
| Likes | **448 👍 / 242 👎 → 65%** |
| Gamepasses | **0** |
| Private servers | **Disabled** |
| Social links / group | **None** |
| Max players | 20 |
| **Concurrent players** | **0** |
| **Live servers** | **0** |

### C.2 The funnel — this is the whole story

| Stage | Players | % of joiners |
|---|---|---|
| Entered the game | 1,429,383 | 100% |
| Completed **first objective** | 287,147 | **20.1%** |
| Survived **one round** | 62,206 | **4.4%** |

**79.9% of players never completed a single objective.** The theme delivered 1.4 million people
to the door; the first five minutes threw away four out of five of them. Visits ÷ unique players
= **1.77 sessions per player** — the overwhelming majority played once and never returned.

### C.3 What they got right — adopt these

| Strength | Evidence | How we adopt it |
|---|---|---|
| **The theme sells** | 2.5M visits, 190K favourites, on a game that plays badly | Validation that Filipino folklore horror pulls. We do not need to gamble on the theme. |
| **Store-page keyword stuffing** | `Takbo Aswang [Pinoy Horror: Mount Luntian]` — Tagalog verb + bracket tags | Copy the pattern in our title (§13) |
| **Folklore-forward description** | Names Aswang, Tikbalang, Tiyanak up front; emoji feature bullets | Same structure. Lead with the creatures. |
| **Evocative Filipino zone names** | Barrio, Graveyard, Bamboo Forest, Ritual Site, Church | Use this naming style for our task locations inside one map |
| **Immediate starter kit** | "Flashlight & bolo starter kit" | Right instinct — give the player a tool in hand immediately. We give a lantern. |
| **"Dynamic sunset-to-night"** | Their atmosphere feature | **Steal and upgrade: make it our round timer.** The sky visibly progressing toward sunrise *is* the countdown — a diegetic clock, no UI needed, and it raises tension for free. |
| **Solo-playable** | PvE, so it worked at any population | The one structural advantage they had over us → **Solo Trial (§9.1)** |

### C.4 Why they failed — five causes, five fixes

**1. FTUE collapse — 80% never finished one objective.** 🔴 *The primary cause of death.*
→ **Fix:** §10. Guaranteed first task near spawn with a waypoint, Solo Trial tutorial, and a hard
gate: below 50% first-objective conversion, everything else stops.

**2. Content exhaustion.** Seven hand-built zones, a mountain to climb, unlockable weapons — all
consumable. Beat it once and there is no reason to return. This is why 2.5M visits became 0 CCU.
→ **Fix:** structural, already in our design. Randomized 5-of-12 tasks and a *human* monster mean
the content regenerates every round. **Never add a campaign.** (§4.4)

**3. Zero monetization.** No gamepasses. Private servers switched off. 1.43M unique players
converted at exactly **$0**. Sixteen months of work, no revenue path at all.
→ **Fix:** private servers + at least one gamepass are **launch blockers** (§13). Ship them on
day one, not "once we have players" — the players came and left while they waited.

**4. Zero community capture.** No group, no Discord, no social links. 1.43M people passed through
and not one could be reached again. Every update shipped into silence.
→ **Fix:** §9.2 — group + social links + a join reward, live at launch.

**5. Wrong server size.** 20 players in a horror game. Intimacy and paranoia both die at that
scale, and with low CCU the servers read as empty.
→ **Fix:** already at 8 max / 3 min (§9).

### C.5 Explicitly reject — the trap that killed them

Do **not** adopt any of these, no matter how tempting they look:

- ❌ **Climb / escape / campaign structure** — consumable content, the root cause of their 0 CCU
- ❌ **Zone-based progression** (7 areas) — scope death for a solo dev; took them 16 months
- ❌ **Weapons and combat against monsters** — kills fear, and destroys the asymmetric tension
- ❌ **NPC monsters as the threat** — the monster being a *person* is the entire heart of our game
- ❌ **20-player servers**

> **The scope-creep alarm:** if you ever find yourself building "more zones," "a mountain,"
> "unlockable weapons," or "a campaign," you have started rebuilding Takbo Aswang. Stop and
> re-read this appendix.

### C.6 The lesson in one line

> **They proved the theme works and that a game with this theme can pull 1.4 million people.
> They also proved that pull means nothing without a first five minutes, a reason to return,
> a way to be paid, and a way to reach your players again.**

We inherit the proof. We fix the four holes.
