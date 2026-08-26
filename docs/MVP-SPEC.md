# ASWANG — MVP Specification

**Working title:** `ASWANG: Survive the Night` (Filipino folklore co-op horror)
**Version:** MVP **v2.0** — the mechanics rewrite. Supersedes v1.3 (v1.0 + Amendments A1–A3)
**Date:** August 2026 · v2.0 written 2026-08-26
**Author's context:** Solo developer. Strong software engineer, zero game-dev experience, no art budget, no deadline. Goal is profit.

---

## What changed in v2.0, and why

v1.3 described a **task game**: survivors completed 5 of 12 randomized objectives, the escape gate
opened, and they ran for it. The Aswang won on kills or on the clock.

That design had a problem the author named directly: **the tasks did not make sense as survival.**
Lighting candles and pumping water are chores a person does in a village, not things a person does
while something is hunting them. The objective and the danger were two separate systems bolted
together, and the seam showed.

v2.0 replaces it with a single loop borrowed from the survival-horror shape that already works:

> **You are unarmed and it is dark. Everything that makes you safer also makes noise.**

Survivors search the bahay kubo for three folklore items. Searching is loud. Loud brings the monster.
There is no second objective layer, because the search *is* the objective, and nobody needs to be told
why they are doing it.

### The five structural changes

| | v1.3 | v2.0 |
|---|---|---|
| **Survivor objective** | 5 of 12 tasks, then the escape gate | Search containers for salt, garlic, buntot pagi |
| **Survivor win** | Finish tasks + reach the gate | Survive to sunrise, **or kill the Aswang** |
| **Aswang win** | Kills ≥ roster − 2, or the clock | Kill **everyone** before sunrise |
| **Counterplay** | Salt only | Three items, each with a different verb |
| **After a kill** | 30s cooldown | **Feed on the corpse** — heals, and restores camouflage |
| **Dead players** | Ghosts | Spectate + immediate requeue |

### What did NOT change, and this is the important half

**§2's five design pillars are untouched, and all five still hold.** The monster still risks exposure
to kill. Rounds are still short. Every round still produces a story. It still has to read on a phone.
Paranoia is still the product.

**Appendix C is untouched and still the reason for every line of §3.** The competitor teardown that
justified the scope line applies exactly as it did before — with **one deliberate exception, argued
in §C.5**, where v2.0 knowingly does something that appendix forbids.

**Amendment A1's mechanism survives** in a new form (§4.8): the roster is still frozen at `STARTING`,
because absence still has four causes and only one of them is the Aswang's doing.

**Amendment A3 survives intact** (§4.7): death is not public, there is no global death signal, and
`ClientRoundSnapshot` still carries no alive-count. Removing ghosts must not remove the body — the
reasoning is in §4.7 and it was rediscovered the hard way twice.

**Amendment A2 is retired**, along with the task system it governed.

---

## 0. How to use this document

This is your **single source of truth**. Rules:

1. If a feature is not in this document, **it does not go in the MVP.** Write it in `ROADMAP.md` instead.
2. Every number in here is a **starting value to tune**, not a truth. Balance comes from playtesting.
3. Build in the order given in §12. Do not jump ahead to art or monetization.

**The MVP's one job:** prove that the core loop is fun with real players. Everything else is secondary.

---

## 1. The game in one paragraph

3–5 players spawn in a Filipino barrio at night. Most are **Survivors**, unarmed, who must search the
bahay kubo for the three things folklore says stop an aswang — **salt**, **bawang** (garlic), and a
**buntot pagi**. Searching takes time and **makes noise**, and noise is how the monster finds you.
One player is secretly the **Aswang**. It looks exactly like a normal survivor, and to kill it must
briefly **transform** into its monstrous form, which anyone nearby can see. After a kill it must
**feed on the corpse** — which heals it, and is the only way it can disappear again once exposed.
Survivors win by living until sunrise, or by killing it. The Aswang wins only by killing everyone.

**The hook in 3 seconds:** *"One of your friends is the monster. Find the salt before it finds you."*

---

## 2. Design pillars (use these to settle every argument)

| Pillar | Meaning | What it kills |
|---|---|---|
| **Paranoia over jumpscares** | The fear comes from not trusting people, not from loud noises | No cheap screamers, no gore |
| **The monster must risk exposure to kill** | Every kill is a gamble | No invisible/instant kills |
| **Short rounds, fast restart** | Under 6 minutes, back in within 30 seconds | No long lobbies, no long cutscenes |
| **Every round produces a story** | "I saw him transform behind you!" | No mechanic that makes rounds identical |
| **Readable on a phone in one hand** | 60% of players are mobile | No tiny text, no complex controls |

**A sixth pillar, new in v2.0, and it is the one that settles most arguments now:**

| **Safety and progress must never be the same action** | Everything that arms you exposes you | No safe grinding, no permanent safe room |

---

## 3. MVP scope — the hard line

### ✅ IN (build these)

- 1 map: **Barrio (village at night)**
- 1 monster: **Aswang** (a hidden player)
- **3–5 player servers**, minimum 3 to start a round
- Round state machine + lobby + intermission
- **Searching** — ~15 containers across the bahay kubo, a randomized subset seeded each round
- Transform-to-kill, and **feeding** on the corpse
- **Camouflage** — post-reveal only (§4.3), into an ambient animal or villager
- **Smoke escape** — the Aswang's counter to being salted
- **Three items:** salt (reveal + damage), bawang (deny a doorway), buntot pagi (the kill)
- **The sharpening tracker** — the Aswang's sense of where people are gets better as the night goes on
- Death → spectate + immediate requeue
- Win/lose end screen with the reveal
- Quick-chat wheel (non-verbal communication)
- Progression: XP, level, soft currency, daily reward, ~6 unlockable cosmetics
- Monetization: 3 gamepasses, 2 dev products, private servers — **live on launch day, not "later"**
- Mobile-first UI + performance budget
- Analytics events + basic anti-exploit
- **Solo Trial** — a 90-second single-player practice run (tutorial *and* low-population fallback) — §9.1
- **5 funnel badges** mirroring the retention funnel — Appendix B
- **Community capture** — Roblox group + social links + a group-join reward — §9.2

### ❌ OUT (v2+, write them in ROADMAP.md and stop thinking about them)

- Manananggal, Tiktik, Kapre, Tiyanak — **all other monsters**
- All other maps (church, hospital, palengke, balete forest)
- **Emergency meetings / voting** — see §4.5, a deliberate design cut
- **An NPC / AI monster** — the monster being a *person* is the heart of the game (§C.5)
- **Any objective system beyond searching** — no tasks, no missions, no chores. This is what v2.0
  exists to remove; re-adding it rebuilds the seam
- **A campaign, zones, or a climb** — Appendix C's root cause
- **Weapons beyond the three named items.** Buntot pagi is the *only* thing that damages the Aswang,
  it is one per round, and it breaks on use. A second weapon, a respawning weapon, or a purchasable
  one is out (§C.5)
- **Microphone-driven mechanics** — voice needs age verification most of the audience lacks, Roblox
  exposes no input amplitude to build on, and gating survival on silence excludes players with no mic,
  no quiet room, or no voice (§4.5)
- **Permanent safe rooms** — garlic buys seconds, never safety (§4.6, pillar six)
- Trading, guilds, pets, leaderboard seasons
- Custom **character** animations, custom monster mesh, voice acting
- Multiple Aswangs per round
- Sabotage / power systems

> **Why so small?** Two reasons. First, unfinished games earn zero. Second, every monster and map you
> *withhold* becomes a free TikTok video, a hype spike, and a reason lapsed players return. **Your
> roadmap is your marketing calendar.** Do not spend it all at launch.

---

## 4. Game design detail

### 4.1 Round flow & timings

| Phase | Duration | What happens |
|---|---|---|
| `IDLE` | until 3+ players | Lobby. Players walk around, see cosmetics, read tips, can enter the Solo Trial. |
| `INTERMISSION` | 25s | Countdown. Shows map name + tip of the round. |
| `STARTING` | 4s | Roles assigned server-side, container layout seeded, players teleported, screen fade. |
| `ACTIVE` | **300s (5 min)** | The round. Sunrise timer visible to all. |
| `ENDING` | 12s | Reveal the Aswang, show stats, award XP/coins. |
| → back to `INTERMISSION` | | |

**Total cycle ≈ 5.7 min**, down from 7.5. Smaller lobbies and a kill-everyone win condition mean the
round should be shorter, and pillar three got stricter to match.

> **Flagged assumption — overrule in one line.** `Duration` is a flat 300s. Scaling it with survivor
> count (`180 + 45 × survivors`, so a 3-player round is shorter than a 5-player one) is the **first
> thing to try** if 3-player rounds feel padded. It is deliberately not the launch value, because
> §0.2 says numbers are tuned from playtests and a formula guessed now is a formula defended later.

A player joining mid-round becomes a spectator until the next round. At this cycle length nobody waits
more than ~5 minutes, and the requeue button (§4.7) means they usually do not wait at all.

### 4.2 Roles

| Role | Count (5 players) | Goal |
|---|---|---|
| Survivor | 4 | Live until sunrise, **or** kill the Aswang |
| Aswang | 1 | Kill **every** survivor before sunrise |

**Role assignment rules:**
- Server-side only. **Never** replicate the Aswang's identity to any other client. Not in a tag, not
  in a name colour, not in an attribute, not "hidden" in a value the client can read. Assume every
  client is compromised.
- **Anti-repeat:** track the last 2 rounds; a player who was Aswang last round has heavily reduced
  weight. Nothing kills a session faster than never being the monster — or being it three times running.
- Aswang gets a 3-second private intro ("You are the Aswang. Do not get seen.").

**Why 3–5 and not 6–8.** This is arithmetic, not taste. The Aswang must now kill *everyone*, and each
kill costs a transform, an approach, a revert and a 5-second feed. At 7 survivors that is more time
than the round contains even if every single hunt succeeds instantly — the win becomes unreachable and
the monster is just a nuisance. At 4 survivors it is demanding but achievable, with room to fail twice.

Small lobbies also fill faster at low CCU, which §9 names as the single biggest business risk, and
§C.4's fifth cause is a game that put 20 players in a horror server and lost all its intimacy.

**4–5 players is the target.** 3 is the floor where the round still functions; deduction is thin there
because there are only two suspects.

### 4.3 The kill mechanic — the heart of the game

This is the most important system. Get it right.

**The transform, unchanged from v1.3 and still the signature moment:**

1. Aswang presses **Transform** (mobile button / key).
2. **1.2s transform animation** — visible to anyone with line of sight. Distinct silhouette, red eye
   glow, audio cue that carries ~40 studs.
3. While transformed: **+25% move speed**, can kill on touch/prompt within 8 studs.
4. After a kill, or after 8s, it must **revert** (1.0s).

**Why this design works:**
- It creates the game's signature clippable moment: *witnessing the transform.*
- It gives survivors real information without any UI — grouping up is genuinely protective.
- It makes the Aswang's decision tense: kill now and risk being seen, or wait.
- It is **cheap to build** — no custom monster model. Reuse the player avatar with a scale change, a
  colour/material shift, glowing eyes, and a particle emitter.

**Rules to enforce server-side:** distance ≤ 8 studs, raycast line-of-sight, both alive, round
`ACTIVE`. The client only *requests* a kill; the server decides.

#### Feeding — what replaced the kill cooldown

v1.3 gated kills behind a 30-second cooldown. v2.0 replaces the timer with an action:

> **After a kill, the Aswang must feed on the corpse for 5 seconds** — transformed, locked in place,
> visible, and interruptible.

**Feeding restores 25 health** (§4.6) and, once the Aswang has been revealed, **restores its ability
to camouflage**.

**Why this is better than a cooldown, stated so it does not get "simplified" back:**

- **The monster is never on a countdown.** It is always live, always dangerous. The cost of a kill is
  a commitment, not a wait — which is what the design wanted the cooldown to mean in the first place.
- **It cannot chain-kill**, because it is pinned to the body it just made. A pair of survivors is
  still safer than a lone one, and that is the property the whole social layer rests on.
- **A corpse becomes bait.** Survivors now know exactly where the monster is and exactly how long it
  will be there. **This is the reliable window the buntot pagi needs** — without it, killing the
  Aswang depends entirely on a lucky salt hit, and a win condition that requires luck is decoration.
- **Interrupting a feed is a real victory.** Salt it mid-meal and it loses the heal and the camouflage
  refresh, and has to leave the body.
- **It is folklore.** The aswang eats. That is the creature.

> **The feed duration is load-bearing, not cosmetic.** It must exceed the time for a survivor to cross
> ~15 studs and land a buntot pagi swing. `tests/config.test.luau` pins that **relationship**, not the
> number — otherwise someone tunes it to 3 seconds later and silently deletes a win condition.

#### Camouflage — and the rule that makes it safe

The Aswang can take the form of an ambient **cat, dog, pig, or villager NPC**. There are three or four
of each wandering the barrio (§5), so no single one is conspicuous.

> **Camouflage is locked until the Aswang has been publicly revealed** — that is, until it has taken
> a salt hit. Before that, it cannot camouflage at all.

**This gate is not a balance dial. Removing it breaks the game, and here is exactly how:**

Camouflage removes a player avatar from the world. In a 5-player round, the first time an *unrevealed*
Aswang turns into a cat there are four players visible and one missing. **Anyone who counts heads knows
who it is** — permanently, with no transform witnessed, no risk taken, and no evidence to argue about.
The disguise would not add a layer of mystery; it would *perform the reveal*, for free.

Gated the way it is, camouflage does what it was meant to do:

- **Before the reveal**, the disguise is *being a normal player*. That is already perfect and costs
  nothing to build.
- **After the reveal**, everyone already knows who it is, so a head count tells them nothing new — and
  the monster gets to vanish back into the barrio and keep hunting.

And it produces the best pressure loop in the design: **once revealed, the Aswang must kill to hide.**
Camouflage is spent on use and only a feed restores it. Being salted does not make the monster
cautious — it makes it desperate. The survivors who exposed it have started a clock, and they know it.

#### Smoke — the Aswang's escape

Taking a salt hit forces a revert and leaves the Aswang glowing (§4.6). To stop that from being a
death sentence, it has one **smoke** ability: a burst that breaks line of sight and covers a
disengage.

Smoke is the Aswang's, not the survivors'. An early v2 draft gave the smoke to salt itself — so
throwing salt cost you your only item, blinded you, and let the monster re-hide next to you inside
the cloud. **A counterplay item that punishes its user is a dead item.** Smoke belongs to the party
that wants to escape.

### 4.4 Searching — the risk economy

**This replaces v1.3's task system entirely.** There are no tasks, no objectives, no chores. There is
one activity, and it is the reason you die.

**~15 searchable containers** are placed across the bahay kubo, the chapel and the well area — sacks,
cabinets, under the papag. Each round seeds a **random subset** with the items:

| Item | Count per round |
|---|---|
| Salt | 4 |
| Bawang (garlic) | 2 |
| Buntot pagi | **1** |

Seven items across fifteen containers. You will open empty ones, and that is the point.

**Searching takes ~6 seconds and makes noise.** Both halves matter:

- **The 6 seconds** are why the layout being random costs something. If searching were instant, players
  would sweep every container and randomization would just be a longer walk.
- **The noise** is the entire risk economy. It is the loudest thing a survivor does, and it is the
  thing they must do. You cannot arm yourself quietly, you cannot be safe and productive at the same
  time, and every search is a decision you made.

**Anti-frustration:** items belong to the *world*, not to individuals. Anyone can search anything.
A dead player's progress is never stranded, which removes a whole class of bugs.

**The Aswang searches too, and does not know the layout either.** This is deliberate:
- It gives the monster a legitimate reason to be rummaging inside a house — blending is *justified by
  mechanics* rather than performed.
- Denying survivors the buntot pagi becomes a real strategy that looks exactly like survival.
- And it means "who is searching" says nothing about who anyone is. (This is the same trap Amendment
  A2 was written to close in v1.3: any activity the Aswang cannot perform honestly becomes an oracle
  that identifies it. The rule generalises — **the monster must be able to do everything a survivor
  does, sincerely.**)

**The layout seed is server-only.** `Random.new(roundNumber)` or anything seeded from `os.time()` lets
a client compute where the buntot pagi is before the round starts — no remote to intercept, nothing
for `check:secrecy` to see. Seed from server entropy and keep the layout off the wire.

### 4.5 Communication — the piece almost everyone gets wrong

Your accusation gameplay is worthless if players can't communicate. Reality check:

- Roblox **voice chat requires age verification (13+)** — most of your audience won't have it. **Do
  not design around voice.**
- Text chat exists and is filtered, but **typing on a phone mid-chase is impossible.**

**Therefore the MVP ships a Quick-Chat Wheel** (one button → radial menu, 8 phrases, sends a filtered
preset + optional world ping):

`"I saw it transform!"` · `"It's the [animal]!"` · `"Body here!"` · `"Follow me"` · `"Searching — cover me"` · `"Run!"` · `"I'm alone"` · `"I have the buntot pagi"`

Two of these are new in v2.0 and both are load-bearing. **`"It's the [animal]!"`** is how a barrio
full of scenery becomes a barrio with one monster in it — without it, camouflage is unbeatable.
**`"I have the buntot pagi"`** makes the carrier findable, which is what turns the single weapon into
a group decision instead of one person's secret.

This is a small system with an outsized effect on how fun the game is. **Do not cut it.**

#### The microphone, explicitly rejected

A mic-driven "be quiet or it hears you" mechanic has been proposed and is **out**, for three
independent reasons, any one of which is sufficient:

1. **Roblox voice chat requires ID-based age verification.** Most of this audience cannot use it.
2. **Roblox exposes no raw input amplitude to developers for gameplay.** There is no supported way to
   read how loud a player is being and drive a mechanic from it. It cannot be built.
3. **It would be an accessibility failure even if it could.** Players with no mic, no quiet room, or
   no voice would simply lose. Difficulty must never depend on someone's hardware or living room —
   the same reason §4.3's tell is behavioural rather than a subtle emissive difference.

**The feeling it was reaching for is fully delivered by §4.4's noise**, which comes from *actions* —
sprinting, searching, doors, items. "Be quiet" means "move carefully", it works for everyone, and
every number in it is yours to tune.

### 4.6 The three items

If survivors are helpless, the game is not fun; it's just losing. v1.3 had one item. v2.0 has three,
each with a different verb, and together they form the survivors' entire arsenal.

#### Salt — reveal and damage

- **4 pouches** seeded per round (§4.4). One carried at a time. **No recharge** — once thrown, gone.
- A hit **forces the revert**, applies a **visible glow for 10s**, and deals **25 damage**.
- It **interrupts a feed** — the Aswang loses the heal and the camouflage refresh.
- The first hit is what **unlocks the Aswang's camouflage** (§4.3). Revealing it is not free.

#### Bawang (garlic) — deny a doorway

- **2 per round.** Placed on a doorway; the Aswang cannot pass for **15 seconds**, then it burns out.
- **It buys time. It never buys safety.** A permanent safe room plus a survive-to-win condition makes
  hiding the winning strategy, which is pillar six's whole concern.
- **A garlic barrier is silent and invisible in its effect on the Aswang.** No knockback, no VFX, no
  sound — its movement simply does not carry it through.

> **That last bullet is a mechanic, not a rendering note, and it is the most easily-lost rule in this
> document.** Garlic on a doorway invites a loyalty test: place it, ask everyone to walk inside, and
> whoever cannot enter is the Aswang. That test *should* exist — it is the kind of emergent social
> moment this genre is famous for. But it only stays a game if **refusing is indistinguishable from
> being unable.** A survivor can decline to walk in, for any reason, including to be funny; the best
> possible outcome is the Aswang refusing too and three people standing outside having learned
> nothing. The moment the barrier plays *any* effect on the monster, bluffing dies and the test
> becomes a perfect oracle. Build it silent.

#### Buntot pagi — the only thing that kills

- **Exactly one per round.** It **breaks on use**. It can be dropped, passed, and picked up from a body.
- It kills **only** an Aswang that is both **`Exposed`** (glowing from a salt hit) **and `Weakened`**
  (at or below 25 health). Against anything else it does nothing.

**One, not two or three, and not one each.** One creates a **carrier** — a single person holding the
barrio's only chance. That is a role, a story, and a target. The Aswang knows there is exactly one and
will hunt whoever has it, so **the weapon makes you prey**. And when the carrier dies it drops where
they fell, which means there is a corpse in the open with the win condition lying next to it and a
monster that knows you have to come back for it. None of that happens with three of them.

#### The health system — why salt finally matters

The Aswang has **100 health**. This exists so that the two items work together rather than in parallel:

| Event | Effect |
|---|---|
| Salt hit | −25 health, **floored at 25** — salt alone can never kill |
| Feeding on a corpse | +25 health |
| Buntot pagi, on an `Exposed` **and** `Weakened` Aswang | Kill |

So the survivors' path to the second win condition is: **land three salt hits, then land the buntot
pagi during a reveal window.** They have four pouches, so exactly one may miss.

And every kill the Aswang makes **heals away one salt hit.** That is the tug-of-war the whole design
turns on: the survivors' progress toward killing it and the Aswang's progress toward killing them are
the *same resource*, pulling in opposite directions.

> **The invariant to pin in `tests/config.test.luau`:**
> `SaltDamage × (SaltSpawnCount − 1) ≥ MaxHealth − WeakenedThreshold`
> — survivors must still be able to reach `Weakened` after one miss. At the starting values that is
> `25 × 3 ≥ 75`, satisfied exactly. Tightening any of those four numbers without checking this makes
> the second win condition quietly unreachable, with no symptom to tell you.

**Secrecy rule:** the Aswang's health is server-only state and must never be readable by another
client **except while `Exposed`**. A health value attached to a player is the reveal. The intended
presentation is diegetic and needs no UI at all: **the glow gets brighter as it weakens.**

#### The sharpening tracker — why hiding does not win

Survivors win by surviving, so something must make hiding lose. That something is the monster's senses
getting better as the night goes on.

The Aswang receives a periodic **pulse** — a rough directional read on where the noise has been.

| | Early round | Late round |
|---|---|---|
| Interval | ~90s | ~30s |
| Precision | ~40-stud area | ~15-stud area |

Interpolated linearly across `ACTIVE`.

**This is the pressure that replaces the escape gate.** Hiding buys you two minutes and kills you at
minute five, so everyone is pushed to arm themselves *early*, while it is still quiet — which is
exactly when you want them out in the dark.

Two constraints on it:

- **It is vague and slow, never a live feed.** The Aswang is a player, not an AI. Give a player
  reliable tracking and it stops needing to blend in — it just walks to the pings, and the entire
  social layer drains out of the game.
- **Survivors must know when they made noise.** A sound you cannot perceive is not tension, it is a
  dice roll. If the player sees *"that was loud"*, the dread is theirs to own.

### 4.7 Death — corpses, husks, and getting back in

**Ghosts are removed.** v1.3 made dead players into flying ghosts who could contribute to tasks and
trigger spooks. There are no tasks to contribute to, and the author did not want the concept.

**What that costs, stated honestly:** §4.7 of v1.3 existed because in elimination games the first
person to die gets bored and leaves, and it called that *"a retention leak and silently fatal."* That
is an Appendix C concern and removing ghosts does not make it untrue.

**What replaces it, and why it is better than ghosts were:** death drops you into **spectate, with an
immediate "find another round" button.** Lobbies are 3–5 players and the cycle is under six minutes,
so a dead player is in a *fresh* round in under a minute rather than haunting this one. That addresses
the leak more directly than ghosts did — ghosts gave you something to do in a round you had already
lost; requeue gives you a round you have not.

#### Two kinds of body, and they are not the same thing

| | **Corpse** | **Husk** |
|---|---|---|
| Made by | Being killed | Disconnecting, or 120s idle during `ACTIVE` |
| Can be fed on | **Yes** | No — until it is killed, which makes it a corpse |
| Can be killed | n/a | **Yes**, and it counts as a kill |
| Duration | 45s, then fades | Until killed or the round ends |

**Husks are why the roster never shrinks.** A player who quits leaves a body standing where they were,
and the Aswang still has to find and kill it to complete a kill-everyone win. This is deliberate and it
solves the problem Amendment A1 was written for, from the other direction: **quitting no longer helps
the Aswang.** In v1.3 three alt accounts leaving turned a five-kill win into a two-kill win. Here,
leaving makes the monster's job *harder*, and griefing the monster is a far smaller problem than
farming wins off it.

Two rules keep husks from breaking the round:

- **A husk cannot benefit from garlic**, and one that has been unreachable for 60 seconds is relocated
  to the nearest walkable point. If someone quits inside a shielded house or falls out of the map,
  kill-everyone must not become unwinnable.
- **Husk state is publicly obvious** — an unmistakably slumped, idle body that everyone can see. See
  the secrecy note below for why this is not optional.

#### Amendment A3 survives, and removing ghosts must not remove the body

> §4.7's shape changed. **The rule about what a death may tell a living client did not.**
>
> **Death is not public. There is no global death signal, and the round snapshot carries no live
> player count.** A client learns that someone died by *finding the body*.
>
> **Why.** A sub-second global death signal is the missing input to an attack this genre does not
> survive: record replicated character positions, timestamp each kill from the decrement, then ask who
> was within kill range of the victim's last position at that instant. In the open that is frequently
> a single candidate — the Aswang, identified with nobody having witnessed a transform. In a group it
> narrows the field, which is damaging enough on its own.
>
> **What this costs.** Nobody can see at a glance how many survivors are left — not the survivors, and
> not the Aswang. That is the intended trade. Pillar one asks for paranoia, and a HUD number that
> answers *"is it getting bad?"* for free is the opposite of it. **No HUD alive-count element may be
> given a data source** — not under that name and not under another (`SurvivorsRemaining`, `DeadCount`,
> a roster the client can count). If a playtest says players are lost without it, the answer is a
> *diegetic, latency-bearing* one — a tally the quick-chat wheel can assert, a board in the plaza
> someone has to walk to.
>
> **And this is why the corpse stays attached as the dead player's `Character`.** Removing ghosts is
> not a licence to delete the body. `dead[p] = (p.Character == nil)` is one line, and
> `GetPropertyChangedSignal("Character")` turns it into a timestamped death alert. A hidden body is no
> better: `Transparency = 1` hides pixels, not existence. **Prefer making the dead
> indistinguishable over making them hidden** — every player has a `Character`, and you learn a death
> by looking at it. This exact hole was reopened twice by code written to protect it, with `verify`
> and `check:secrecy` green over both.
>
> **The same reasoning governs husks.** A husk that differs from a live body in any replicated way —
> no `Humanoid`, a frozen animation, a different network owner — lets a client enumerate exactly which
> bodies are husks. And since the Aswang cannot be one (its disconnect ends the round, §6.4), **every
> husk is provably innocent.** In a 5-player lobby that narrows the field by a fifth, for free. The
> defence is to make husk state *plainly visible to everyone* — public information cannot be exploited
> asymmetrically.

### 4.8 Win / lose conditions

| Outcome | Condition |
|---|---|
| **Survivors win** | The sunrise timer reaches 0 with **at least one survivor alive**, **or** the Aswang is killed |
| **Aswang wins** | **Every** survivor is dead before sunrise |

**The timeout flipped from v1.3, and the tracker is what pays for it.** In v1.3 the clock running out
was an Aswang win, because otherwise survivors could hide and do nothing. v2.0 makes survival a win
and makes hiding *lose over time* instead (§4.6's sharpening tracker). That is a better mechanism —
it pressures players rather than punishing them — but **it means the tracker curve is now load-bearing
balance.** If it is tuned too gently the game breaks in the boring direction, and the symptom is a
round where nothing happens.

#### How the Aswang's win is measured — Amendment A1's mechanism, kept

The rule is "kill everyone", but *everyone* has to be counted against something stable:

> **`RequiredKills` is frozen at `STARTING`** and equals the survivor count at that moment. The Aswang
> wins when `AswangKills == RequiredKills`. **It never decrements.**

A1's original reasoning still holds: absence has four causes — killed, disconnected, reset, fell out
of the map — and only the first is the Aswang's doing. v1.3 solved that with a `−2` buffer. v2.0 does
not need one, because **§4.7's husks keep every departed player on the board as a killable body.**
Nobody leaves the roster, so nothing needs subtracting, and no combination of disconnects advances
either side.

**Edge case that must be handled:** the Aswang disconnecting ends the round immediately with a brief
*"the Aswang fled"* message, no XP penalty for survivors (§6.4). It is not a survivor win — there was
nothing to beat.

**End screen:** reveal the Aswang (big dramatic moment — **this is the screenshot people share**),
show per-player stats, award XP and coins. If the Aswang was killed, show *that*, because it is rarer
and it is the better story.

### 4.9 Tone and rating — a business constraint disguised as a design note

Roblox assigns an age rating from a content questionnaire. **Blood, gore, and intense violence push
you to 13+ and cut off a large part of your audience** — the exact audience that plays and spends the
most.

**Design for "creepy and tense," not graphic.** Kills should be a grab, a scream, a fade to black — no
blood pools, no dismemberment. **Feeding in particular must be suggestion, not depiction**: the
monster hunched over a body, an audio cue, a particle effect, camera turned away. It is v2.0's most
rating-sensitive addition and the cheapest to get wrong. Atmosphere scares harder than gore, and it
protects your addressable market.

---

## 5. The map — Barrio (v1)

**Size target: small.** A map that takes ~35 seconds to cross end-to-end. New devs build maps far too
big; big maps mean players never meet, and empty maps feel dead — especially at low player counts.
With 3–5 players this matters more in v2.0, not less.

**Required zones:**
- Central plaza (spawn) — the "safe-ish" social hub
- **6–8 bahay kubo / small houses, at least 5 enterable** — up from 3, because searching is now the
  whole game and the containers live inside them
- A chapel (one interior, strong lighting moment)
- Rice field edge (tall grass, low visibility — the killing field)
- A well / water pump area
- 2–3 narrow alleys creating **loops, never dead ends.** Dead ends are unfair; loops create chases —
  and with a monster that must feed after every kill, a loop is what lets a survivor come back for the
  body

**New in v2.0 — two populations the map must carry:**

**~15 searchable containers**, spread so that no single house is worth camping and no two are close
enough that one search covers two. They must be visually obvious as searchable at a glance, on a phone,
in the dark.

**Ambient life, for camouflage to mean anything:** **3–4 each of cats, dogs, pigs and villager NPCs**,
wandering. If there is one pig in the barrio, the disguise is meaningless. They need no AI worth the
name — a wander loop and an idle is enough. What matters is the *count*.

**Sightline rule:** you should almost always be able to see *something* — a lantern, a silhouette, a
doorway. Total darkness is not scary, it's just confusing. Fear comes from *partial* information.

**Art strategy (zero budget):**
- Build with **parts and free Creator Store assets.** Horror is the most forgiving genre for cheap art
  — darkness, fog, and lighting hide low-poly geometry. This is a genuine advantage of the genre.
- Use **Future lighting**, heavy `Atmosphere` fog, very low ambient, and a small number of warm point
  lights.
- **Audio matters more than visuals in horror.** Ambient night loop, distant dogs, wind, footsteps,
  heartbeat when the Aswang is near. Budget real time for this — it's the cheapest fear-per-hour you
  can buy. In v2.0 it is also **mechanically load-bearing**: §4.4's noise needs to be *heard*, and
  §4.6's "that was loud" feedback is an audio problem before it is a UI one.

**Mobile performance budget (non-negotiable):** as v1.3 — light cap, `StreamingEnabled`, tested on a
real phone at 30fps.

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

Roblox Studio remains where you build the map, lighting, and physical assets. Code lives in the
filesystem.

### 6.2 Server-authoritative model — the one rule

> **The client is an untrusted renderer and input device. Nothing else.**

Specifically for this game:
- The Aswang's identity is **server-only state**. It is never sent to other clients in any form.
- **The Aswang's health is server-only state**, readable by others only while `Exposed` (§4.6).
- **The container layout seed is server-only** (§4.4). A client that can replay the draw knows where
  the buntot pagi is before the round starts.
- Clients *request* actions (`RequestKill`, `RequestSearch`, `RequestThrowSalt`, `RequestPlaceGarlic`,
  `RequestStrike`, `RequestCamouflage`, `RequestSmoke`). The server validates and decides.
- Every RemoteEvent is **rate-limited** and validates types, state, distance, and cooldown.
- The transform *is* public — that's intentional design, so replicating it is correct.

**Exploiters will target this game specifically** because knowing the imposter is so valuable. This is
where your engineering background is a genuine competitive advantage over the typical Roblox dev.

### 6.3 Module layout

```
ServerScriptService/
  Services/
    RoundService.lua        -- state machine, timers, phase transitions
    RoleService.lua         -- secret role assignment, anti-repeat weighting
    SearchService.lua       -- container layout seed, search validation, noise emission
    MonsterService.lua      -- transform, kill, feed, camouflage, smoke, health
    TrackerService.lua      -- the sharpening pulse
    ItemService.lua         -- salt / bawang / buntot pagi: spawn, carry, use
    BodyService.lua         -- corpses and husks, AFK detection, relocation
    ProgressionService.lua  -- XP, level, coins, daily streak
    MonetizationService.lua -- gamepasses, ProcessReceipt, private servers
    AnalyticsService.lua    -- event emission
    AntiCheatService.lua    -- rate limits, speed/teleport sanity checks
  init.server.lua

ReplicatedStorage/
  Shared/
    Config.lua              -- ALL tunable numbers (see 6.5)
    Types.lua               -- Luau type definitions
    Enums.lua               -- RoundPhase, Role, ItemType, MonsterState, BodyKind
    Remotes/                -- RemoteEvent/RemoteFunction definitions
    pure/                   -- every gameplay decision that can be a pure function

StarterPlayer/StarterPlayerScripts/
  Controllers/
    UIController.lua        -- HUD, sunrise timer, carry slot, end screen
    InputController.lua     -- mobile buttons, keyboard binds
    QuickChatController.lua -- the radial wheel
    CameraFXController.lua  -- vignette, shake, proximity heartbeat
    AudioController.lua     -- ambience, noise cues, the "that was loud" feedback
```

### 6.4 Round state machine

```
IDLE ──(players ≥ 3)──> INTERMISSION ──(25s)──> STARTING ──(4s)──> ACTIVE
  ^                                                                    │
  └────────────(players < 3)──── ENDING <──(win/lose/timeout)─────────┘
```

Implement as an explicit enum + a single `SetPhase()` function that fires one `PhaseChanged` remote.
**Never** let gameplay code mutate phase directly. Every service subscribes to phase changes. This
keeps a notoriously bug-prone area debuggable.

**Edge cases to handle explicitly (these will bite you):**
- The Aswang **leaves mid-round** → end round immediately, no XP penalty for survivors, brief "the
  Aswang fled" message.
- A **survivor** leaves mid-round → they become a **husk** (§4.7). The round continues and
  `RequiredKills` does not change.
- A survivor is **idle for 120s** during `ACTIVE` → husk, same treatment.
- Player count drops below minimum mid-round → finish the round, *then* return to `IDLE`.
- A player joins mid-round → spectator until `ENDING`.
- **Timer reaches 0 with ≥1 survivor alive** → survivors win (§4.8). *This is inverted from v1.3 —
  the most likely place for stale logic to survive the rewrite.*
- Server shutdown → `game:BindToClose()` must flush all player data.

### 6.5 Config module — make balance data-driven

Put **every** tunable number in one `Config.lua`. You will change these constantly during playtesting,
and hunting magic numbers across ten files is how a weekend disappears.

```lua
return {
  Round   = { Intermission = 25, Duration = 300, EndScreen = 12, MinPlayers = 3, MaxPlayers = 5 },
  Roles   = { AswangCount = 1, RepeatCooldownRounds = 2 },
  Monster = {
    TransformTime = 1.2, RevertTime = 1.0, KillRange = 8, MaxTransformTime = 8,
    TransformedSpeedMult = 1.25,
    MaxHealth = 100, WeakenedThreshold = 25,
    FeedDuration = 5, FeedHeal = 25,
    SmokeDuration = 4, SmokeRadius = 18,
  },
  Search  = { ContainerCount = 15, SearchTime = 6, NoiseRadius = 60 },
  Items   = {
    SaltSpawnCount = 4, SaltDamage = 25, SaltStunDuration = 4,
    SaltRevealDuration = 10, SaltThrowRange = 25,
    GarlicSpawnCount = 2, GarlicDuration = 15,
    BuntotPagiSpawnCount = 1,
  },
  Tracker = { EarlyInterval = 90, LateInterval = 30, EarlyRadius = 40, LateRadius = 15 },
  Bodies  = { CorpseDuration = 45, AfkSeconds = 120, HuskRelocateAfter = 60 },
  Economy = { XPPerRound = 50, XPWinBonus = 40, CoinsPerRound = 25 },
}
```

**The relationships that must be pinned in `tests/config.test.luau`** — these are silent invariants;
no symptom tells you when two numbers that must agree have stopped agreeing:

1. `SaltDamage × (SaltSpawnCount − 1) ≥ MaxHealth − WeakenedThreshold` — the second win condition
   survives one missed throw (§4.6).
2. `FeedDuration` > time to cross ~15 studs + a strike — the corpse-as-bait window is real (§4.3).
3. `SaltThrowRange` > `KillRange` — you can salt it before it can reach you.
4. `GarlicDuration` < `Round.Duration ÷ 4` — garlic buys time, never safety (pillar six).
5. `LateInterval` < `EarlyInterval` and `LateRadius` < `EarlyRadius` — the tracker sharpens, never dulls.
6. `SaltRevealDuration` > `SaltStunDuration` — the reveal outlasts the stun, so salting creates a
   chase rather than a freeze.

### 6.6 Data model (per player, session-locked)

```lua
Profile = {
  SchemaVersion = 2,           -- migrate on read; you WILL change this
  XP = 0, Level = 1, Coins = 0,
  Stats = {
    Rounds=0, Survived=0, AswangRounds=0, AswangWins=0,
    Kills=0, ItemsFound=0, AswangKilled=0,
  },
  Cosmetics = { Owned = {}, Equipped = { Skin="default", Lantern="default", DeathFX="default" } },
  Daily = { LastClaimUTC = 0, Streak = 0 },
  Purchases = { GamepassCacheUTC = 0 },
}
```

Rules: version from day one and write the migration path. `Stats.TasksDone` becomes `Stats.ItemsFound`
in the v1→v2 migration; `Stats.AswangKilled` is new. Save on meaningful change, on leave, and on
`BindToClose`. Never trust a client-supplied value into this table.

---

## 7. Progression & retention (the money is here, not in the shop)

Monetization follows retention. Ship these:

- **XP + Levels** — visible bar, levels unlock cosmetics. Cheap to build, strong pull.
- **Daily login streak** — escalating rewards with a meaningful day-7 payoff. The single highest-ROI
  retention feature you can build.
- **Soft currency (coins)** — earned per round, spends on cosmetics. Gives non-payers a goal and makes
  paid cosmetics legible in value.
- **Unfinished business** — end the session near a milestone ("2 rounds to level 5") so there's a
  reason to come back.
- **~6 unlockable cosmetics at launch** — enough to see progress, not enough to burn your content.

**Targets to hold yourself to:**

| Metric | Red | OK | Good |
|---|---|---|---|
| Day-1 retention | <20% | 25–30% | 35%+ |
| Day-7 retention | <8% | 10–15% | 18%+ |
| Avg session | <6 min | 10–15 min | 20 min+ |
| Rounds per session | <2 | 3 | 4+ |
| Paying conversion | <0.5% | 1–2% | 3%+ |

> **If Day-1 retention is under 30%, do not spend a single peso on ads or a single hour on
> monetization. Fix the first five minutes instead.** Marketing a leaky game just burns money faster.

---

## 8. Monetization (business lens)

### 8.1 The rule for *this* genre

Horror can't sell "2x speed" the way a simulator can — there's no grind to skip, and any in-round
advantage **breaks the fairness that makes an asymmetric game fun.** So you sell three things:

**Social access · Identity · Convenience — never advantage.**

### 8.2 What to sell

| Product | Type | Price (R$) | Why it works |
|---|---|---|---|
| **Private Server** | Roblox private server | ~100/mo | **Your #1 earner.** Friend groups will pay to play without randoms. Recurring revenue, perfect fit for co-op horror — and at 3–5 players a private server is a group of actual friends, which is the ideal buyer. |
| **Starter Pack** (1 skin + 1 emote) | Gamepass | 79 | Breaks the first-purchase barrier. Once a player buys *anything*, they're 3–4x likelier to buy again. |
| **Survivor Pack** (2 exclusive skins + lantern skin) | Gamepass | 249 | Mid-tier identity purchase |
| **VIP** (exclusive aura, 2x XP, VIP lobby area, name colour) | Gamepass | 799 | Top of ladder. 2x XP is cosmetic progression, **not** round advantage — this stays fair. |
| **Coin Pack (small / large)** | Dev product | 99 / 399 | Repeatable revenue from loyal players |

**Ladder logic:** a tiered set of 3+ passes materially outperforms one big pass. The entry tier exists
to convert first-time buyers, not to earn.

**Sell cosmetics that appear in clips** — death effects, transform auras, lantern colours, emotes.
Your game manufactures screenshots; players pay to look good in them. **The clippable moment is also
the sales engine.** v2.0 adds two new ones: the **feed** and the **buntot pagi kill**.

### 8.3 Explicitly do NOT sell (in MVP)

- ❌ Extra salt, extra garlic, **a second buntot pagi**, revives, see-through-walls, longer transform,
  a better tracker — all break asymmetric fairness. The buntot pagi is the sharpest temptation here
  and the most damaging: selling a second one sells the win condition.
- ❌ **"Higher chance to be the Aswang"** — common on Roblox, but in a 1-imposter game it directly
  takes the fun role from non-payers and breeds resentment. At 3–5 players it is worse than at 8,
  because each player's share of the role is already larger and more visible. **Skip it.**

### 8.4 Placement

Contextual offers convert far better than a passive shop button. Show the cosmetic shop **on the end
screen** (when the player just had a great round and is waiting anyway), never mid-round.

### 8.5 The honest revenue math

Roblox takes ~30% of a gamepass sale, then DevEx converts earned Robux at roughly **$0.0038** each,
with a **30,000 Robux (~$114) minimum cashout**. Practically: **~100 R$ of sales nets you around
$0.25.**

**Expect your first game to earn near zero.** ~85% of Roblox developers earn under $100/month. Treat
v1 as the asset that builds an audience and teaches you the platform. That is not pessimism — it's the
correct baseline to plan against so you don't quit at week six.

---

## 9. The cold-start problem — your single biggest business risk

**A multiplayer-only game with no players is unplayable.** Not "less fun" — literally cannot be
played. This kills more multiplayer indie games than bad design does, and it's the risk most
first-time devs never see coming.

Mitigations, all of which belong in the MVP:

1. **Set `MaxPlayers` to 5, not 20.** Small servers fill faster and feel full sooner. v2.0's ceiling
   is lower than v1.3's for gameplay reasons (§4.2), and the cold-start benefit is a free consequence.
2. **`MinPlayers = 3`.** The game must be playable, even if imperfect, with 3 people. Test that it is.
3. **Make the lobby not-dead time** — a small activity, cosmetic preview, and a visible countdown so
   waiting doesn't read as "broken game."
4. **Launch at a scheduled time to a concentrated audience.** Announce "we play at 7PM" to your TikTok
   following. Concentration beats trickle. A steady 20 players at one hour is worth more than 200
   spread across a day.
5. **Track "% of joins that reached an ACTIVE round."** If it's low, players are bouncing off an empty
   lobby and your retention numbers are lying to you.

### 9.1 Solo Trial — borrowed from the competitor's one real strength

Takbo Aswang was PvE, so it **always worked with one player**. Yours does not — below 3 players there
is no game at all. When your traffic arrives in TikTok waves, anyone who lands during a dead hour
currently gets *nothing*, and they never come back.

**The fix — a Solo Trial in the lobby.** A ~90-second single-player run in a corner of the map:

- **Search two containers** to learn the interaction, and hear how loud it is.
- A scripted Aswang is **drawn by the noise**, transforms, and chases you. You learn the tell, and you
  learn to throw salt.
- Ends with: *"Now do it when the monster is one of your friends."* → drops you into the lobby queue.

It does three jobs at once:

| Job | Why it matters |
|---|---|
| **Tutorial** | Teaches search → noise → tell → salt, by doing — fixes the FTUE hole in §10 |
| **Cold-start fallback** | Below `MinPlayers`, players have something real to do instead of a countdown |
| **Retention insurance** | A player arriving at 3am still experiences the game instead of bouncing |

**This does not change the heart of the game.** The multiplayer social loop is still the whole point;
the Trial exists only to get people *into* it. **Do not let it grow into a PvE campaign** — that is
exactly the trap that killed the competitor, and v2.0's items and searching make it *more* tempting
than v1.3's did, not less.

### 9.2 Community capture — the hole that cost them everything

Takbo Aswang had **1.43M unique players, zero social links, and no group.** All of that traffic passed
through and left no way to ever reach those people again. When they shipped updates, they had nobody
to tell.

**Build the funnel from traffic → owned audience on day one:**

- A **Roblox group** for the game, linked on the store page. Give a small in-game reward for joining
  (a cosmetic, a coin bonus) — group members can be notified of updates for free.
- **Social links** on the store page: TikTok, Discord, YouTube. They cost nothing and they were absent
  from a game with 2.5M visits.
- An in-lobby **"Join the group / follow the TikTok"** panel with the reward attached.

Every player who joins your group or follows the TikTok is a player you can **re-activate on every
update, for free, forever.** That is the difference between a game that spikes once and a game that
compounds.

---

## 10. First-time user experience (FTUE) — where the competitor actually died

This is no longer a matter of opinion. Takbo Aswang's public badge counts give the exact funnel:

| Stage | Players | Conversion |
|---|---|---|
| Entered the game | **1,429,383** | — |
| Completed their **first objective** | **287,147** | **20.1%** |
| Survived **one round** | **62,206** | **4.4%** of joiners |

**Roughly 4 out of 5 people who opened that game never finished a single task.** Not "didn't come
back" — never completed one objective, ever. The theme delivered 1.4M people to the door and the first
five minutes threw away 80% of them.

**That is the failure to design against.** Everything below is aimed at that one number.

### Hard rules

- **Player must be doing something meaningful within 60 seconds of joining** — either a live round or
  the Solo Trial (§9.1). Never a countdown on an empty lobby.
- **Guarantee the first item find.** A brand-new player's first round seeds a **guaranteed-full
  container near their spawn**, with a clear waypoint. Do not let their first experience be wandering
  a dark map opening empty sacks — an empty search is correct design for a returning player and
  actively hostile as a first impression.
- **Teach by doing, not by reading.** No wall of text. Contextual one-liners at the moment they're
  needed: *"Hold to search."* · *"Searching is loud."*
- **Teach the folklore.** Do not assume players know salt stops an aswang. On first pickup: *"Salt
  burns the aswang — throw it to reveal and weaken."* On the buntot pagi: *"The stingray tail. The
  only thing that can kill it — and it breaks."*
- Every second of non-gameplay costs you players. No splash screens, no long cutscenes.

### The gate — treat this as a launch blocker

> **If fewer than 50% of joiners find a first item, stop everything and fix the FTUE.** Not the art,
> not the shop, not marketing. Their equivalent number was 20%. Yours must clear 50%, and you will
> know within a day of launch because the badge tells you.

---

## 11. Risks & mitigations

Rows marked **⚑** are confirmed kills — they are what actually destroyed Takbo Aswang (Appendix C),
not hypotheticals.

| Risk | Severity | Mitigation |
|---|---|---|
| **⚑ FTUE drop-off — players quit before their first find** | 🔴 Critical | §10 — guaranteed first container, Solo Trial, 50% badge gate. *Their number was 20%.* |
| **⚑ Traffic arrives and is never captured** | 🔴 Critical | §9.2 — group + social links + join reward, live at launch. *They had 1.43M players and no way to reach any of them.* |
| **⚑ Monetization never ships** | 🟠 High | Private servers + 1 gamepass are a launch blocker (§13). *They monetized 2.5M visits at exactly $0.* |
| **⚑ Content runs out** | 🔴 Critical | Randomized container layout + human monster. Never add a "campaign." *Their 7 hand-built zones were consumed and that was that.* |
| **Hiding becomes the winning strategy** | 🔴 Critical | **New in v2.0.** §4.6's sharpening tracker is the only thing preventing it, and the timeout now favours survivors. Tune this first, at every playtest. |
| **The second win condition is unreachable** | 🟠 High | **New in v2.0.** One buntot pagi, a health floor and a heal-on-feed interact multiplicatively. §6.5's invariants 1 and 2 are the guard; if nobody ever kills the Aswang, check those before touching anything else. |
| Empty servers (cold start) | 🔴 Critical | §9 — small servers, low minimum, Solo Trial fallback, scheduled launch |
| Asymmetric balance is hard | 🔴 High | Config-driven numbers, 3+ structured playtests before launch, tune on data |
| Exploiters revealing the Aswang | 🔴 High | Strict server authority, role never leaves server, rate limits. v2.0 adds two surfaces: the health value and the layout seed (§6.2) |
| Players can't communicate | 🟠 High | Quick-chat wheel (§4.5) — do not cut it |
| **Dead players quit** | 🟠 High | **Changed in v2.0.** Ghosts are gone; spectate + immediate requeue (§4.7). Watch this metric — if it degrades, ghosts were doing more work than assumed |
| Scope creep → never ships | 🔴 Critical | §3 hard line. Everything else goes in `ROADMAP.md` |
| Mobile performance | 🟠 Medium | Light cap, `StreamingEnabled`, test on a real phone. v2.0's ambient animals are a new draw cost — budget them |
| Rating hits 13+ | 🟠 Medium | No gore, creepy-not-graphic (§4.9). **Feeding is the new risk here** |
| Data loss / duplication | 🟠 Medium | ProfileStore session locking, schema versioning, `BindToClose` |
| Genre is heavily cloned | 🟠 Medium | Win on theme + the transform mechanic + Filipino folklore niche |

---

## 12. Build order (do it in this sequence)

Each milestone should end in something **playable**. Never build two systems deep without testing.

| # | Milestone | Definition of done |
|---|---|---|
| **M0** | Toolchain | Rojo syncing, Git repo, Luau LSP working, empty place publishes |
| **M1** | Round skeleton | State machine cycles IDLE→…→ENDING with no gameplay. Timers correct. Handles players leaving. |
| **M2** | Roles + kill | Roles assigned secretly. Transform, kill, corpse, **feed** all server-validated. |
| **M3** | **Search + noise** | ~15 containers, randomized seeding, 6s search, noise emission and the "that was loud" cue. |
| **M4** | **Items + win** | Salt (reveal/damage), bawang (silent doorway), buntot pagi (the kill). Health, `Weakened`, both win conditions fire. |
| **M5** | **Tracker + camouflage** | The sharpening pulse; camouflage gated on reveal and restored by feeding; smoke. |
| **M6** | **The feel pass** | Lighting, fog, ambient audio, transform and feed VFX. **Before any playtest** — see the note below. |
| **M7** | **First playtest** | Real humans, 5 rounds. **Is it fun?** Write down what they said. |
| **M8** | Solo Trial + FTUE | 90-second practice run works with 1 player. New player finds a first item in under 60s. |
| **M9** | UI + quick chat + mobile | Full HUD, radial wheel, tested on an actual phone at 30fps |
| **M10** | Map art + full audio | Barrio dressed, ambient life populated, stingers. |
| **M11** | Progression + data + badges | XP, levels, coins, daily streak, ProfileStore with migration, 5 funnel badges awarding |
| **M12** | Monetization + community | 3 gamepasses, 2 dev products, private servers ON, group + social links + join reward |
| **M13** | Analytics + anti-cheat | Events firing, funnel visible, rate limits on every remote |
| **M14** | Playtest #2 + balance | Full lobby, tune Config until neither side wins >60% |
| **M15** | Launch prep | §13 checklist complete |

> **M6 is new in v2.0 and it is a deliberate reordering.** v1.3 put all art at M8, after the playtest,
> on the correct principle that you should not dress a game you have not proved. That principle still
> holds for *art* — but **horror is 80% lighting and sound**, and a greybox with default lighting does
> not test the game you are building; it tests a different, less frightening one. M6 is one chunk of
> atmosphere, not an art pass: fog, darkness, warm point lights, ambient audio, and the two VFX the
> mechanics depend on. Props, textures and dressing still wait for M10.

> **M7 is the real gate.** If people don't want a 6th round, no amount of art, monetization, or
> marketing will save it — **change the design then, not after launch.** This is the cheapest moment
> in the entire project to be wrong.

> **M8 is the second gate, and it's the one the competitor failed.** They had a game people wanted to
> play and lost 80% of them before the first objective. Do not skip past M8 because the multiplayer
> already "works for you" — you already know how to play it. New players don't.

---

## 13. Launch checklist

**Store page (this is 80% of whether anyone clicks):**
- [ ] **Icon** — readable at thumbnail size, one clear focal image, high contrast
- [ ] **Thumbnails** — show the transform moment and a group of survivors; faces/reactions outperform scenery
- [ ] **Title with searchable keywords** — include both "Aswang" (Filipino search) and an English hook. *Copy the competitor's bracket-tagging pattern — `Takbo Aswang [Pinoy Horror: Mount Luntian]` stuffs "Pinoy," "Horror," and the location into one searchable line. That part of their execution worked: 2.5M visits.*
- [ ] **Description leads with the folklore.** Theirs named Aswang, Tikbalang, and Tiyanak up front and used emoji-bulleted feature lists. It got the clicks — the game behind it is what failed. **Yours leads with salt, bawang and buntot pagi**, which no competitor is using and every Filipino player recognises.
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
- [ ] Tested a full server (5)
- [ ] **Tested a round where a player disconnects mid-round** — husks are new and they gate the Aswang's win
- [ ] **Tested a round where the Aswang is killed** — the rarer win condition is the easier one to ship broken
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

1. **The game is 20% of the work. Distribution is 80%.** Your reference creator (@bossramzcpm)
   succeeded because he built a 308K-follower audience *before* the game. **Start posting now, during
   the build** — not at launch. The devlog is the marketing.
2. **Playtesting is not optional for asymmetric games.** You cannot balance 1-vs-4 alone in Studio.
   Recruit real testers early — your TikTok audience is also your test group.
3. **Audio is half of horror and it's free.** In v2.0 it is also *mechanically load-bearing* — §4.4's
   noise has to be audible for the risk economy to read. Highest fear-per-hour in the project.
4. **Name and icon decide clicks before anyone plays.** Treat them as features, not afterthoughts.
5. **Ship, then update relentlessly.** Abandoned games collapse fast; updating games get re-promoted
   by the algorithm and by returning players. Each new monster from your roadmap is an update *and* a
   video *and* a retention spike.
6. **Instrument everything and trust the numbers over your feelings.** This is your unfair advantage
   as an engineer — most Roblox devs iterate on vibes. You don't have to.
7. **Your first game's real product is the audience and the skill.** The second or third game is where
   money realistically shows up. Plan a career, not a lottery ticket.

---

## Appendix A — Balance starting values (tune, don't trust)

| Knob | Start | Raise if… | Lower if… |
|---|---|---|---|
| Round duration | 300s | Aswang can never finish everyone | Rounds drag / players idle |
| Feed duration | 5s | Aswang chain-kills too easily | Nobody ever punishes a feed |
| Kill range | 8 studs | Kills feel unreliable | Kills feel unfair/ranged |
| Transform time | 1.2s | Aswang too sneaky | Aswang always caught |
| Aswang max health | 100 | Aswang dies too easily | Aswang is never killable |
| Salt damage | 25 | Nobody reaches `Weakened` | Aswang dies without a buntot pagi |
| Salt spawns | 4 | Aswang dominates | Aswang never lands a kill |
| Garlic duration | 15s | Chases are hopeless | Players turtle behind doorways |
| Container count | 15 | Items found too fast | Players find nothing and die unarmed |
| Search time | 6s | Searching carries no risk | Arming up is too slow to matter |
| Tracker late interval | 30s | Hiding still wins | Survivors never get a quiet moment |

**Target: neither side wins more than ~60% of rounds.** Track win rate per side in analytics from day
one — you cannot tune what you don't measure.

**Track the second win condition separately.** "Aswang killed" should be **rare but real** — a rough
target is 10–20% of survivor wins. At 0% the buntot pagi is decoration and §6.5's invariants are the
first place to look. Above ~35% the monster is a piñata and the horror is gone.

---

## Appendix B — Analytics events to emit from day one

`player_joined` · `round_started` (playerCount) · `role_assigned` (role) · `container_searched` (foundType, secondsIntoRound) · `item_found` (type, secondsIntoRound) · `player_killed` (secondsIntoRound, wasIsolated) · `feed_completed` · `feed_interrupted` · `transform_witnessed` · `salt_used` (hit/miss) · `garlic_placed` · `garlic_blocked` (the loyalty test, and how often it happens) · `camouflage_used` (form) · `aswang_killed` · `round_ended` (winner, winCondition, duration) · `player_left` (phase, secondsInSession) · `husk_created` (reason) · `shop_opened` · `purchase_completed` (productId) · `daily_claimed` (streak) · `trial_started` · `trial_completed` · `group_join_reward_claimed`

**The funnel that matters most:** `joined → reached an ACTIVE round → completed a round → returned on
day 2`.

### The 5 funnel badges (ship all of these)

Badges are permanent, free, and their award counts are **publicly readable via the Roblox API** —
which is exactly how the competitor's failure was diagnosed. Mirror your funnel in badges and you get
a durable, tamper-proof retention dashboard for free.

| Badge | Awarded when | Reads as |
|---|---|---|
| `Welcome` | First join | Denominator — total unique players |
| `First Find` | First item found **ever** | **The number that killed them (20.1%). Target >50%.** |
| `First Round` | Survived or lost a full round | Did they get the actual game? |
| `First Blood` | First round as the Aswang | Are people reaching the fun role? |
| `Balik-Balik` ("came back") | Played on a second, separate day | **Day-2 retention, measured directly** |

`First Task` from v1.3 becomes `First Find` — same position in the funnel, same 50% gate, same
diagnostic value. **A sixth badge for killing the Aswang is tempting and should wait**: it measures a
rare event, not a funnel stage, and five badges that map cleanly to five funnel steps is worth more
than six that don't.

Two caveats: your competitors can read these too, and badge counts are unique-player lifetime totals,
not daily rates — so use them as a coarse funnel, and use in-game analytics for anything
time-sensitive.

---

## Appendix C — Competitive teardown: *Takbo Aswang [Pinoy Horror: Mount Luntian]*

**This appendix is carried forward from v1.3 unchanged, except §C.5's fourth bullet.** It is the
evidence behind §3's scope line and it did not stop being true when the mechanics changed.

### C.1 The numbers

| Metric | Value |
|---|---|
| Visits | ~2,500,000 |
| Unique players | 1,429,383 |
| Revenue | **$0** |
| Gamepasses | none |
| Private servers | disabled |
| Group / socials | none |
| Development | ~16 months |
| Server size | 20 |

### C.2 The funnel — this is the whole story

| Stage | Players | Conversion |
|---|---|---|
| Entered | 1,429,383 | — |
| First objective | 287,147 | 20.1% |
| Survived a round | 62,206 | 4.4% |

**80% never completed one objective.** The theme delivered 1.4M people and the first five minutes
threw away four out of five of them.

### C.3 What they got right — adopt these

- **The theme pulls.** 1.4M unique players is proof the Filipino folklore niche is real and underserved.
- **The store page works.** Bracket-tagged searchable title, folklore roster in the description,
  emoji-bulleted features. Copy this (§13).
- **PvE always works with one player.** This is the single strength v2.0 still borrows, as the Solo
  Trial and nothing more (§9.1).

### C.4 Why they failed — five causes, five fixes

**1. FTUE collapse.** 80% never finished an objective.
→ **Fix:** §10 in full, plus the badge gate: below 50% first-find conversion, everything else stops.

**2. Content exhaustion.** Seven hand-built zones, a mountain to climb, unlockable weapons — all
consumable. Beat it once and there is no reason to return. This is why 2.5M visits became 0 CCU.
→ **Fix:** structural, already in the design. A randomized container layout and a *human* monster mean
the content regenerates every round. **Never add a campaign.**

**3. Zero monetization.** No gamepasses. Private servers switched off. 1.43M unique players converted
at exactly **$0**. Sixteen months of work, no revenue path at all.
→ **Fix:** private servers + at least one gamepass are **launch blockers** (§13). Ship them on day one,
not "once we have players" — the players came and left while they waited.

**4. Zero community capture.** No group, no Discord, no social links. 1.43M people passed through and
not one could be reached again. Every update shipped into silence.
→ **Fix:** §9.2 — group + social links + a join reward, live at launch.

**5. Wrong server size.** 20 players in a horror game. Intimacy and paranoia both die at that scale,
and with low CCU the servers read as empty.
→ **Fix:** v2.0 is at **5 max / 3 min** (§4.2), tighter than v1.3's 8.

### C.5 Explicitly reject — the trap that killed them

Do **not** adopt any of these, no matter how tempting they look:

- ❌ **Climb / escape / campaign structure** — consumable content, the root cause of their 0 CCU
- ❌ **Zone-based progression** (7 areas) — scope death for a solo dev; took them 16 months
- ⚠️ **Weapons and combat against monsters** — **v2.0 deliberately crosses this line. See below.**
- ❌ **NPC monsters as the threat** — the monster being a *person* is the entire heart of our game
- ❌ **20-player servers**

#### The one deliberate exception, and the argument for it

v1.3 rejected weapons outright on the grounds that they *"kill fear and destroy the asymmetric
tension."* v2.0 ships the **buntot pagi**, which kills the monster. That is a direct contradiction of
this appendix and it is recorded here rather than quietly deleted, because a scope line you can edit
without noticing is not a scope line.

**Why this is not what killed them.** Their weapons were a *progression system* — unlockable, plural,
permanent, and earned by grinding consumable content. Ours is:

- **One per round.** Not unlockable, not purchasable (§8.3), not persistent.
- **It breaks on use.** There is no armoury, no upgrade path, nothing to grind toward.
- **It only works on an already-exposed, already-weakened monster.** It cannot be used to *hunt*; it
  can only *finish*. The survivors still have to survive first.
- **It makes the carrier prey, not powerful.** The Aswang knows there is exactly one and hunts whoever
  holds it (§4.6).

So it does not create content to consume, it does not let survivors go on the offensive, and it does
not make the monster less frightening — it gives a desperate group one terrifying option. That is the
argument. **If any future change weakens one of those four bullets — a second buntot pagi, a
respawning one, one that works on a healthy Aswang, one that can be bought — the exception no longer
holds and this appendix wins.**

> **The scope-creep alarm:** if you ever find yourself building "more zones," "a mountain,"
> "unlockable weapons," or "a campaign," you have started rebuilding Takbo Aswang. Stop and re-read
> this appendix.

### C.6 The lesson in one line

> **They proved the theme works and that a game with this theme can pull 1.4 million people. They also
> proved that pull means nothing without a first five minutes, a reason to return, a way to be paid,
> and a way to reach your players again.**

We inherit the proof. We fix the four holes.
