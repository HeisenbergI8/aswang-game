# Plan: C13–C16 — Salt and Ghosts

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M4 (docs/MVP-SPEC.md §12) — chunks C13, C14, C15, C16 of docs/BUILD-PLAN.md
- **Description:** The salt counterplay loop (spawn → carry → throw → stun → forced revert → reveal) and
  the ghost loop (death → ghost body → ghost-only chat → 25% contribution → one spook). Plus the two
  policy decisions C15 was told to close: whether death is public, and what a rejoining survivor becomes.
- **Date:** 2026-08-13
- **C17 is NOT in this plan.** The greybox is a human-runner task. Phases 2 and 6 place *disposable*
  Studio rigs so C13/C14/C15 are provable before it exists, exactly as C07 Step 2.1 did.
- **What the client is told:** this plan **removes** one field and **narrows** one broadcast. After it,
  a client learns about a death from: the corpse standing in the world (local, discovery-latency, and
  subject to `StreamingEnabled`), `SaltEffect` (a public world event), and — if it is the victim —
  `PlayerKilled`, fired to that one player. It no longer learns a death from `AlivePlayerCount` (dropped)
  or from a `PlayerKilled` broadcast (narrowed to the victim). Ghosts additionally receive
  `GhostRoster`, which carries UserIds of dead players and no role. Nothing new carries a role.

### The two decisions, closed

**DECISION 1 — death is NOT public, and `AlivePlayerCount` goes.** I agree with dropping it rather than
delaying it, and the reason a delay fails is the one you gave: a fixed delay is a constant an attacker
subtracts, so it converts a zero-latency oracle into a zero-latency oracle with an offset.

**But dropping it alone does not achieve the goal, and this is the finding that changes the shape of
Phase 1.** `MonsterService.luau:610` fires `PlayerKilled` with **`FireAllClients`**, carrying
`VictimUserId` *and* `Position`. That is a strictly worse death oracle than `AlivePlayerCount`: it does
not merely timestamp the kill, it hands over who died and exactly where, so the attacker skips the
position-logging step of the attack BUILD-PLAN §C15 describes. Removing the snapshot field while that
broadcast stands would be theatre. The payload's own comment in `Types.luau:196-199` defends `Position`
on the grounds that "the corpse model stands at that position and replicates to every client on its own"
— which C17 makes false, because §5 requires `StreamingEnabled`, under which a corpse 200 studs away
does not replicate and this remote does.

So Phase 1 does both: drop the field (Step 1.4) **and** narrow `PlayerKilled` to `FireClient(victim, …)`
(Step 1.5). The victim is the only client with a use for it — `CameraFXController.luau:61-75` plays a
death effect off it, which is a first-person effect that was, until now, being played on seven screens
belonging to people who did not die. Verified consumers: `CameraFXController` is the only one.

The corpse survives untouched as the intended local signal, and `SaltEffect` remains loud and public
because it is a world event anyone standing there sees anyway.

**C18 loses its HUD "alive count" element** (BUILD-PLAN ~line 456). That is a spec-visible change, so
Step 1.6 records **Amendment A3** in `docs/MVP-SPEC.md` in Amendment A1's style, and C18 gets a
survivor-count-shaped hole it must fill with something that is not a death oracle, or leave empty.

**DECISION 2 — GHOST-on-rejoin ships here; the disconnect husk does not.** Recommendation: **(a) in
C15, (b) as its own chunk after GATE 1.** Reasoning and cost are in Phase 5's preamble. The floor is
taken regardless, and all three of BUILD-PLAN's completeness conditions are carried into Steps 5.3–5.5.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The two decisions on record — Config, Types, and Amendment A3

Nothing in this phase is salt or ghosts. It is the state both later halves stand on: the knobs, the
snapshot contract after `AlivePlayerCount` leaves it, the narrowed kill broadcast, and the spec sentence
that authorises the removal. It leaves the game runnable — the only observable change is that the debug
HUD line stops printing an alive count.

#### Step 1.1: The C13–C16 knobs in `Config.luau`

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

Add the knobs C13–C16 need to `Salt` and `Ghost`, all as plain numbers and RGB triples — never `Color3`,
which fails every balance test at once under Lune with an error naming `Config` rather than the edit that
broke it (`Config.luau:92-101`).

**`AntiCheat.Budgets` needs nothing.** `RequestThrowSalt` and `RequestGhostSpook` already have budgets
(`Config.luau:373,375`), and `tests/anti-cheat-budgets.test.luau` already pins that every name in
`Remotes.EVENTS_UP` has one. Only Phase 6's new *down*-remote touches that surface, and down-remotes have
no budget by construction.

```diff
 	Salt = {
 		SpawnCount = 4,
 		StunDuration = 4,
 		RevealDuration = 10,
 		ThrowRange = 25,
 		CarryLimit = 1,
+
+		--[[
+			How close a player must be to a pouch for the server to hand it over (C13).
+
+			THERE IS NO PICKUP REMOTE, and this number is why. `RequestTaskProgress` established the
+			shape: the server resolves what you are standing at from your own character's position, and
+			the client names nothing. A pickup that took an argument would be a free "give me salt"
+			handler needing its own budget, its own validation and its own verdict union; a proximity
+			tick needs none of those and cannot be spammed, because there is nothing to spam.
+
+			Deliberately smaller than `Tasks.PresenceRangeStuds` (9). Presence is a thing you do on
+			purpose and should tolerate standing near; a pickup is a thing that happens TO you as you
+			walk past, and one that fires from nine studs away picks pouches up through walls.
+		]]
+		PickupRangeStuds = 6,
+
+		--[[
+			The half-angle, in degrees, of the cone a throw sweeps (C14). The server picks the nearest
+			valid target inside it; the client sends only a direction.
+
+			IT IS A CONE RATHER THAN A RAYCAST ON PURPOSE. A ray demands the accuracy of a shooter from
+			a player on a phone (§5: ~60% of players), and §4.6 is buying counterplay, not aim. It is
+			also why the throw cannot be a probe: widening it does not make salt tell you MORE, because
+			a miss and a hit on a survivor are the same silent outcome (Step 3.1).
+
+			`tests/config.test.luau` pins it under 90. At 90 the cone is a hemisphere and at more than
+			90 you hit things behind you, which is not a throw.
+		]]
+		ThrowConeDegrees = 20,
+
+		--[[
+			How many `SaltSpawn` points the map is expected to carry, against which `SpawnCount` pouches
+			are placed. The analogue of `Tasks.PoolSize`, and it feeds the SAME verdict module —
+			`server/pure/TaskPool.evaluate` — rather than a second copy of it (Step 2.2).
+
+			It must be at least `SpawnCount` or the round cannot place its pouches; the test pins that.
+			C17 owns the actual count in the map.
+		]]
+		PouchPoolSize = 6,
+
+		-- The pouch, and the reveal glow. RGB TRIPLES, NEVER Color3 — same reason as Monster's palette
+		-- and Tasks' markers. `RevealGlow*` is a Highlight's two colours; see Step 4.2 for why a
+		-- Highlight rather than an attribute, a tag or a name colour.
+		PouchRgb = { 240, 238, 225 },
+		RevealGlowFillRgb = { 255, 250, 235 },
+		RevealGlowOutlineRgb = { 190, 235, 255 },
 	},
 
 	Ghost = {
 		TaskContributionMult = 0.25, -- ghosts progress tasks at 25% speed
 		SpooksPerRound = 1,
 		FlySpeed = 24,
+
+		--[[
+			How often the server tells each ghost who the other ghosts are (C15, Step 6.5).
+
+			It must not be FASTER than `Round.SnapshotInterval`. A ghost already receives a snapshot
+			twice a second on the same connection, and §5's mobile budget counts sends per player per
+			tick — a roster arriving faster than the HUD does is a cost with nothing behind it, because
+			the roster only changes when somebody dies. `tests/config.test.luau` pins the relation.
+		]]
+		RosterInterval = 1,
+
+		--[[
+			The spook (§4.7, C16). `SpookRangeStuds` is how far from the ghost the server looks for
+			something to flicker; `SpookDuration` is how long the flicker lasts.
+
+			IT CARRIES NO INFORMATION AND THAT IS A CONSTRAINT ON THESE TWO NUMBERS, not a description
+			of them. A range small enough to pinpoint the ghost's position would tell a living player
+			where a dead one is standing, and a dead player standing beside the Aswang is the leak
+			§4.7's last bullet is about. Thirty studs is comfortably larger than `Monster.KillRange` (8)
+			and than `Tasks.PresenceRangeStuds` (9), so "a light flickered near me" narrows nothing.
+		]]
+		SpookRangeStuds = 30,
+		SpookDuration = 2,
 	},
```

#### Step 1.2: The new relationships in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `npm run test:unit`

Pin the relationships C13–C16 introduce, beside the two that already exist at `tests/config.test.luau:69-82`
(`ThrowRange > KillRange`, `RevealDuration > StunDuration`), **neither of which this plan touches** —
`Config.Salt.ThrowRange`, `StunDuration`, `RevealDuration` and `Monster.KillRange` keep their committed
values throughout.

Inserted after the existing ghost-contribution check at line 90, so the salt block and the ghost block
each stay contiguous.

```diff
 check(
 	"ghosts contribute, but less than the living",
 	Config.Ghost.TaskContributionMult > 0 and Config.Ghost.TaskContributionMult < 1,
 	`TaskContributionMult={Config.Ghost.TaskContributionMult}`
 )
 
+-- Spec §4.6, C13: four pouches cannot be placed at three points. This is the relation that turns a
+-- map defect into a startable round with less salt than the design assumes, and the only symptom
+-- otherwise is "salt feels rarer than it should" six playtests later.
+check(
+	"there are at least as many salt spawn points as pouches",
+	Config.Salt.PouchPoolSize >= Config.Salt.SpawnCount,
+	`PouchPoolSize={Config.Salt.PouchPoolSize}, SpawnCount={Config.Salt.SpawnCount}`
+)
+
+--[[
+	Spec §4.6: "Recharge: none in MVP. Once used, it's gone. SCARCITY MAKES IT A DECISION."
+
+	At `SpawnCount >= MaxPlayers` every player can hold one and the decision disappears — salt stops
+	being a resource and becomes a button. This is the numeric form of the sentence, and it is the
+	first thing an M12 balance pass will be tempted to break.
+]]
+check(
+	"salt is scarcer than the roster",
+	Config.Salt.SpawnCount < Config.Round.MaxPlayers,
+	`SpawnCount={Config.Salt.SpawnCount}, MaxPlayers={Config.Round.MaxPlayers}`
+)
+
+-- Spec §4.6, C14: a half-angle of 90 degrees is a hemisphere and anything above it hits what is
+-- BEHIND the thrower. Zero is a raycast, which §5's mobile audience cannot aim.
+check(
+	"the throw cone is a cone",
+	Config.Salt.ThrowConeDegrees > 0 and Config.Salt.ThrowConeDegrees < 90,
+	`ThrowConeDegrees={Config.Salt.ThrowConeDegrees}`
+)
+
+-- C13: a pickup radius wider than the presence radius picks pouches up through walls and from across
+-- a task point. See Config.Salt.PickupRangeStuds.
+check(
+	"a pouch is picked up closer than a task is held",
+	Config.Salt.PickupRangeStuds < Config.Tasks.PresenceRangeStuds,
+	`PickupRangeStuds={Config.Salt.PickupRangeStuds}, `
+		.. `PresenceRangeStuds={Config.Tasks.PresenceRangeStuds}`
+)
+
+-- Spec §5's mobile budget, C15: the ghost roster only changes when somebody dies, so pushing it
+-- faster than the HUD snapshot is a per-player per-tick cost with nothing behind it.
+check(
+	"the ghost roster is not pushed faster than the snapshot",
+	Config.Ghost.RosterInterval >= Config.Round.SnapshotInterval,
+	`RosterInterval={Config.Ghost.RosterInterval}, SnapshotInterval={Config.Round.SnapshotInterval}`
+)
+
+-- Spec §4.7, C16: "one spook per round". At zero the feature is silently off, and the symptom is a
+-- dead player pressing a button that does nothing — which reads as a bug, not as a balance choice.
+check(
+	"a ghost gets at least one spook",
+	Config.Ghost.SpooksPerRound >= 1,
+	`SpooksPerRound={Config.Ghost.SpooksPerRound}`
+)
+
+-- Spec §4.7, C16: the spook must not localise the ghost. Larger than both the Aswang's reach and the
+-- task presence radius, so "a light flickered near me" narrows nothing a player could act on.
+check(
+	"a spook does not point at the ghost that caused it",
+	Config.Ghost.SpookRangeStuds > Config.Monster.KillRange
+		and Config.Ghost.SpookRangeStuds > Config.Tasks.PresenceRangeStuds,
+	`SpookRangeStuds={Config.Ghost.SpookRangeStuds}, KillRange={Config.Monster.KillRange}, `
+		.. `PresenceRangeStuds={Config.Tasks.PresenceRangeStuds}`
+)
+
 -- Spec §4.1: total cycle ≈ 7.5 min, and §2 demands "under 8 minutes, back in within 30 seconds".
```

**Verify uses `npm run test:unit` rather than `lune run tests/config.test.luau`** — that command is Step
1.1's, and a check shared between two steps in one phase makes `verify-plan` report the second on the
first's evidence. `test:unit` runs this file among all the others and is strictly stronger here anyway:
adding a `Config` field that breaks a *different* suite is exactly the mistake this step could make.

#### Step 1.3: `Types.luau` — drop `AlivePlayerCount`, add the four new payloads

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

Remove `AlivePlayerCount` from `ClientRoundSnapshot` and add `SaltVerdict`, `SaltEffectPayload`,
`GhostRosterPayload` and `SpookVerdict`, each with the field-discipline comment this file's existing
payloads carry.

```diff
+--[[
+	Why the server refused (or failed) a RequestThrowSalt (§4.6, C14). Same shape and same rule as
+	KillVerdict: a union so the server can log WHY, and NEVER echoed to any client.
+
+	MISS IS THE ONE THAT CARRIES THE DESIGN, and it is deliberately a single value covering four
+	different worlds:
+
+	  · the cone was empty
+	  · the cone held a survivor
+	  · the cone held the Aswang, untransformed
+	  · the cone held the Aswang, transformed, but past ThrowRange
+
+	Splitting them is the obvious refactor and it is a role oracle. `MISS_NOT_ASWANG` versus
+	`MISS_OUT_OF_RANGE` would let a compromised client stand in front of each player in turn, throw,
+	and read the monster off the refusal — and it would do it for the price of one pouch, which is
+	the price §4.6 already charges for a legitimate reveal. There is no safe subset to return, so the
+	handler returns NOTHING on every value including OK; what the world does is the only answer.
+
+	NO_POUCH is the C13 half: you are not carrying salt. It is also never echoed, because the client
+	already knows what it is carrying — the server told it (Step 4.3) and it can count its own
+	pickups.
+]]
+export type SaltVerdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"
+
+--[[
+	The salt throw, broadcast to every client (§4.6, C14). THREE FIELDS, ALL ABOUT A TRAJECTORY AND
+	NONE ABOUT A PLAYER.
+
+	It does NOT carry the thrower, the target, or a UserId of any kind. A throw is a thing that
+	happens in the world — a white burst at a place — and every client standing there sees it whether
+	or not this remote exists.
+
+	`Hit` IS SAFE AND IS NOT THE REVEAL. It says "the salt struck something the salt can strike",
+	which given SaltVerdict above means "a transformed Aswang", and a transformed Aswang is ALREADY
+	public: `MonsterTransformed` broadcast it, by design (see MonsterTransformedPayload). This field
+	is what lets a client play a hit sound instead of a fizzle. The information that is genuinely new
+	— WHO it was, once they revert — arrives as a Highlight on a character in the workspace, not on
+	this payload. See Step 4.2.
+
+	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
+	table is accepted silently by the typechecker, and `SaltEffect` is not on check-secrecy.mjs's
+	REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, catching a field named `role`
+	or `aswang` or `killer` and catching nothing else. A field named `TargetUserId` would pass every
+	check in this repo and would name the monster to eight clients.
+]]
+export type SaltEffectPayload = {
+	Origin: Vector3,
+	Impact: Vector3,
+	Hit: boolean,
+}
+
+--[[
+	Who the other ghosts are (§4.7, C15). Fired ONLY to players whose own state is GHOST.
+
+	IT CARRIES UserIds AND THAT IS SAFE, for one reason that must stay true: being dead is not a
+	role. A ghost is a player the Aswang has already killed, or one who died some other way, and
+	`PlayerKilled` used to broadcast exactly this fact to every client until Step 1.5 stopped it.
+	What makes this payload safe is not its contents but its RECIPIENTS — the server fires it per
+	player and never with FireAllClients, and the one thing a living client must not learn is which
+	of the eight are dead, because that is the death oracle Amendment A3 exists to close.
+
+	So the rule for this remote is the mirror of RoleAssigned's: RoleAssigned is safe because its
+	payload is minimal, this is safe because its audience is. Widening the audience is the leak, and
+	no check in this repo would see it — `check-secrecy.mjs` reads payload fields and call shapes,
+	and `FireClient(player, roster)` inside a loop over the wrong list looks identical to the right
+	one. Step 6.5 puts the state test at the fire site for that reason.
+]]
+export type GhostRosterPayload = {
+	UserIds: { number },
+}
+
+--[[
+	Why the server refused a RequestGhostSpook (§4.7, C16). Same shape and same rule as every other
+	verdict here: a union so the server can log WHY, and never echoed.
+
+	NOT_GHOST is a refusal and not an accusation — a living player's client has no spook button, so
+	reaching this value means either a stale button on a player who was just revived by a round
+	ending, or a compromised client. Both look the same from here, which is why C41 reads the log
+	rather than this function.
+]]
+export type SpookVerdict = "OK" | "WRONG_PHASE" | "NOT_GHOST" | "NO_SPOOKS_LEFT" | "NOTHING_IN_RANGE"
+
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

And the removal itself:

```diff
 -- What the client is allowed to know. Note the absence of AswangUserId.
 export type ClientRoundSnapshot = {
 	Phase: RoundPhase,
 	SecondsRemaining: number,
 	RoundNumber: number,
 	TasksCompleted: number,
 	TasksRequired: number,
 	GateOpen: boolean,
-	AlivePlayerCount: number,
 	YourRole: Role?, -- only ever the receiving player's OWN role
 	YourState: PlayerState,
 }
+
+--[[
+	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).
+
+	`AlivePlayerCount: number` sat between GateOpen and YourRole and was pushed to every client every
+	`Round.SnapshotInterval` (0.5s), plus an immediate extra push from `MarkKilled` the instant a
+	death landed. That made it a sub-second global death signal, and a death signal is an input to an
+	attack this game cannot survive: record replicated character positions, timestamp each kill from
+	the decrement, then ask who was within `Monster.KillRange` (8 studs) of the victim's last known
+	position at that instant. In the open that is often one candidate. In a group it narrows the
+	field, which is damaging on its own.
+
+	DELAYING IT WAS CONSIDERED AND REJECTED. A fixed delay is a constant, and a constant is something
+	an attacker subtracts; it converts a zero-latency oracle into a zero-latency oracle with an
+	offset. A jittered delay is worse, because it is a claim of safety that is only ever statistical.
+
+	WHAT A CLIENT LEARNS ABOUT A DEATH NOW, in full:
+	  · the corpse, standing where the victim fell for `Monster.CorpseDuration` — LOCAL, discovery
+	    latency, and under §5's StreamingEnabled it does not replicate at all from far away. This is
+	    the signal the design wants and the only one the design wants.
+	  · `SaltEffect` — a public world event that names nobody.
+	  · `PlayerKilled` — fired to the victim alone since Step 1.5.
+
+	DO NOT REINTRODUCE IT UNDER ANOTHER NAME. `SurvivorsRemaining`, `DeadCount`, `RosterSize` and a
+	`YourState`-derived tally over a roster field are the same oracle wearing different words, and
+	none of them contains a token `check-secrecy.mjs` matches. C18 wants an alive count on the HUD
+	(BUILD-PLAN ~line 456) and this is the field it would reach for; Amendment A3 is the sentence
+	that says no.
+]]
```

#### Step 1.4: `RoundService` and `init.client.luau` — remove the producer and the consumer

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run verify:fast`

Drop the field from `buildSnapshot`, keep `aliveCount()` for the server's own bookkeeping, and strip the
count from the client's debug snapshot line so the tree typechecks.

**`aliveCount()` stays.** It is read at `RoundService.luau:795` in a `VerboseLogging` print that never
crosses to a client, and deleting it would leave `livingSurvivorCount()` as the only headcount in the
file — which is derived from `state.AswangUserId` and therefore cannot be used for anything the log line
does. The function is not the leak; the send was.

```diff
 local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
 	return {
 		Phase = state.Phase,
 		SecondsRemaining = RoundService.GetSecondsRemaining(),
 		RoundNumber = state.RoundNumber,
 		TasksCompleted = state.TasksCompleted,
 		TasksRequired = Config.Tasks.TotalRequired,
 		GateOpen = state.GateOpen,
-		AlivePlayerCount = aliveCount(),
 		YourState = RoundService.GetPlayerState(player),
 	}
 end
```

`MarkKilled`'s immediate push stays, and its comment has to stop claiming a reason that no longer
exists — half of it was always about the victim, and that half is still true:

```diff
-	-- Immediately, rather than waiting up to SnapshotInterval: AlivePlayerCount and the victim's own
-	-- YourState both just changed, and the victim's HUD is the one screen guaranteed to be looked at.
+	--[[
+		Immediately, rather than waiting up to SnapshotInterval: the VICTIM's own `YourState` just
+		became GHOST, and the victim's HUD is the one screen guaranteed to be looked at.
+
+		This used to be justified by `AlivePlayerCount` too, and that half is gone with the field
+		(Amendment A3). What remains is deliberately a per-player fact: `broadcastSnapshot` builds a
+		payload per player, so the seven other clients receive a snapshot identical to the one they
+		would have received on the next tick anyway. If a future change ever makes this push carry
+		something that differs for a bystander, it becomes a death oracle again — timing alone is
+		enough, and an extra send half a second early IS timing.
+	]]
 	broadcastSnapshot()
```

> **A note on what this push still costs, recorded rather than fixed.** An out-of-cadence snapshot is
> itself weakly observable: a client measuring the interval between its own snapshots sees one arrive
> early. It carries no *contents* that differ, so it is far weaker than the field it replaces, and
> removing it would delay the victim's own death screen by up to half a second. Flagged in Follow Ups
> as the residue of this decision, not resolved here.

The client's smoke-test line loses the count:

```diff
 Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
 	local gate = if snapshot.GateOpen then "OPEN" else "shut"
 	local tasks = `{snapshot.TasksCompleted}/{snapshot.TasksRequired}`
 	local line = `{snapshot.Phase} round #{snapshot.RoundNumber} · tasks {tasks} · gate {gate}`
-		.. ` · alive {snapshot.AlivePlayerCount} · you: {snapshot.YourState}`
+		.. ` · you: {snapshot.YourState}`
```

**`npm run verify:fast` is the check** because this step's failure mode is a dangling reference in a file
this step did not open. `verify:fast` is `analyze + remotes + secrecy + toolchain`, and `analyze` over the
whole tree is what finds a consumer nobody grepped for. (The two consumers that exist —
`RoundService.luau:493` and `init.client.luau:80` — were found by grep and are both edited here.)

#### Step 1.5: `PlayerKilled` becomes `FireClient(victim, …)`

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

One call site changes direction. The payload shape is unchanged; what changes is that six other clients
stop being told that a death happened, at a position, at a moment.

```diff
-	-- TWO FIELDS. See Types.PlayerKilledPayload: the killer appears nowhere in it, in any form, and
-	-- nothing in this repo would catch it if it did. Built as a typed local rather than an inline table
-	-- because FireAllClients takes `...any` and an inline literal is checked against nothing at all.
+	--[[
+		TWO FIELDS AND ONE RECIPIENT. See Types.PlayerKilledPayload: the killer appears nowhere in it,
+		in any form, and nothing in this repo would catch it if it did. Built as a typed local rather
+		than an inline table because FireClient takes `...any` and an inline literal is checked against
+		nothing at all.
+
+		FireClient, NOT FireAllClients, SINCE AMENDMENT A3 — and the change is not cosmetic.
+
+		Broadcast, this was a stronger death oracle than the `AlivePlayerCount` field that A3 removed:
+		that field made an attacker infer the position from replicated character logs, and this handed
+		it over directly, timestamped, with the victim named. Removing one while keeping the other
+		would have been theatre.
+
+		THE OLD DEFENCE WAS "THE CORPSE REPLICATES ANYWAY", AND §5 MAKES IT FALSE. The corpse is a
+		Model in `workspace.Corpses`, and C17 turns `StreamingEnabled` on from the start — under which
+		a corpse 200 studs away does not reach a client and this remote did. The two were never
+		equivalent; they only looked it on an unstreamed baseplate.
+
+		The victim keeps it because the victim is the one client with a use for it:
+		`CameraFXController.onPlayerKilled` plays a first-person death reaction, which was until now
+		firing on seven screens belonging to people who had not died. That controller needs no change —
+		its `isMine` branch simply becomes the only branch it ever takes.
+	]]
 	local payload: Types.PlayerKilledPayload = { VictimUserId = victim.UserId, Position = position }
 
-	killedRemote:FireAllClients(payload)
+	killedRemote:FireClient(victim, payload)
 end
```

**`npm run check:secrecy` is the check, and it is genuinely discriminating here** rather than incidental.
`check-secrecy.mjs`'s broadcast rule resolves a payload to its declaration and matches `killer\w*` and the
role tokens (line ~185, and the ALLOW/BLOCK pairs at ~503). It runs over this call whether the fire is to
one client or to all, so the step cannot pass by making the payload richer on the way past — which is the
mistake available here, because "the recipient is only the victim, so anything is safe now" is a plausible
and wrong reading. It is not safe: a compromised victim client is still a client.

What `check:secrecy` does **not** prove is the direction change itself — a text tripwire cannot tell
`FireClient` from `FireAllClients` as a *policy*. That half is proven by the playtester (three clients,
one dies, the other two consoles silent) and is named in Follow Ups as the one claim in Phase 1 that no
check in this repo can make.

#### Step 1.6: Amendment A3 in `docs/MVP-SPEC.md`

**File:** `docs/MVP-SPEC.md`

Record the removal as a numbered amendment beside A1 (§4.8) and A2 (§4.4), in their style: the design
intent is unchanged, what is written down is how it is *measured* — or here, what is *told*. It goes in
**§4.7**, because §4.7 is the section about what dead players are and this is a rule about what a death
is allowed to broadcast. The version line at the top of the file moves with it, exactly as A1 moved it.

```diff
 **Working title:** `ASWANG: Survive the Night` (Filipino folklore co-op horror)
-**Version:** MVP v1.1 spec — v1.0 plus Amendment A1 (§4.8)
+**Version:** MVP v1.2 spec — v1.0 plus Amendments A1 (§4.8), A2 (§4.4) and A3 (§4.7)
 **Date:** August 2026 · last amended 2026-08-13
```

```diff
 - **Cannot** reveal the Aswang's identity to living players. Enforce server-side; ghost chat must be a separate channel.
 
+> **Amendment A3 — 2026-08-13 · spec v1.1 → v1.2 · C15**
+>
+> §4.7 stands unchanged. What follows is a rule about **what a death is allowed to tell a living
+> client**, added here because C15 is the chunk that makes deaths common enough for it to matter.
+>
+> **Death is not public. There is no global death signal, and the round snapshot no longer carries a
+> live player count.** A client learns that someone died by *finding the body* — a corpse standing
+> where the victim fell, for `Monster.CorpseDuration`, discovered by walking into it.
+>
+> **Why.** `ClientRoundSnapshot.AlivePlayerCount` was pushed to every client twice a second, plus an
+> immediate extra push the instant a kill landed. That is a sub-second global death signal, and a
+> death signal is the missing input to an attack this genre does not survive: record replicated
+> character positions, timestamp each kill from the decrement, then ask who was within
+> `Monster.KillRange` of the victim's last position at that instant. In the open that is frequently a
+> single candidate — the Aswang, identified without anybody witnessing a transform. In a group it
+> narrows the field, which is damaging enough on its own. The same reasoning removed the
+> `PlayerKilled` broadcast, which was strictly worse: it handed over the victim and the position
+> directly rather than requiring the attacker to infer them.
+>
+> **Delaying the count was considered and rejected.** A fixed delay is a constant an attacker
+> subtracts. A jittered one is a statistical claim of safety, which is not a claim this document is
+> willing to make about the one secret the whole design rests on (§6.2).
+>
+> **What this costs.** A survivor cannot see at a glance how many of them are left, and neither can
+> the Aswang. That is the intended trade: §2's pillars ask for paranoia, and a HUD number that
+> answers "is it getting bad?" for free is the opposite of it. **C18's planned HUD alive-count
+> element has no data source and must not be given one** — not under this name and not under another
+> (`SurvivorsRemaining`, `DeadCount`, a roster the client can count). If the playtest at C19 says
+> players are lost without it, the answer to reach for is a *diegetic*, latency-bearing one — a
+> tally the quick-chat wheel can assert, a board in the plaza someone has to walk to — and it is a
+> design decision for GATE 1, not a field.
+>
+> **Where it lives.** The absent field is documented in place in `src/shared/Types.luau`'s
+> `ClientRoundSnapshot`, with the list of names it must not come back under. The narrowed broadcast
+> is `MonsterService.commitKill`.
+
 ### 4.8 Win / lose conditions
```

There is one line in **§11's risk table** that A3 makes stale and it is worth a second look during
implementation rather than a silent edit: `| Dead players quit | 🟠 High | Ghost system (§4.7) |` is
unaffected, but any later row or Appendix B analytics event that assumes a client-visible alive count
should be raised in Follow Ups rather than patched here. A grep at implementation time is cheap; a spec
that quietly disagrees with itself is not.

**This step deliberately has no `**Verify:**` line.** Its deliverable is prose, and every mechanical
check available here would be a grep for text this step is what writes. `verify-plan` reports it as
`unverifiable`, which is the accurate answer, and a human reads the paragraph.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — this phase REMOVES two, and introduces the temptation to restore them.** The named
  substitutes (`SurvivorsRemaining`, `DeadCount`, a countable roster) are recorded in `Types.luau` and in
  Amendment A3 because no check in this repo can catch one.
- **The out-of-cadence snapshot push in `MarkKilled` survives as a weak timing signal.** Its contents no
  longer differ for a bystander, so it is far weaker than the field it replaces; it is not zero. Follow
  Ups, not fixed here.
- **`check:secrecy` cannot prove the direction change.** It proves the payload; the playtester proves the
  audience. Named in Step 1.5.
- **Player leaving mid-round** — untouched by this phase. `onPlayerRemoving` is Phase 5's business.
- **Strict Luau** — the four new type declarations use `Vector3` and `{ number }`; none is an enum field,
  so no `:: Types.X` casts are needed. `SaltVerdict` and `SpookVerdict` will need them at their *call*
  sites in Phases 3 and 8, exactly as `TaskProgressVerdict` does.
- **Mobile budget** — Config's `RosterInterval` is pinned at or above `SnapshotInterval` specifically so
  Phase 6 cannot double the per-player send rate. Nothing else in this phase sends anything.
- **Scope** — nothing from §3's OUT list. Amendment A3 explicitly declines to add a HUD element.

---

### Phase 2: C13 — salt spawn and pickup

Four pouches at `SaltSpawn`-tagged points, one carried per player, no recharge. No new remote: pickup is
resolved by a server tick from the player's own position, which is the same shape `TaskService` already
uses for presence and the reason C13 adds nothing to the network surface.

#### Step 2.1: Place the disposable `SaltSpawn` rig in Studio

**File:** `.claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/salt-rig.md`
**Verify:** `test -f .claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/salt-rig.md`

Six grey anchored pads tagged `SaltSpawn` under one `SaltRig_TEMP` folder, plus the empty-pool proof.
Disposable, not C17, deleted wholesale by one `Destroy`.

**This is how C13 and C14 are provable with no greybox**, and it is C07 Step 2.1's pattern verbatim
because that pattern already survived a chunk: the rig is twelve grey pads, it lives in one folder, it is
executed through `execute_luau` rather than written as a script inside Studio (`guard-studio-sync.mjs`
refuses that, and Rojo would overwrite it), and **the deliverable is the artifact, not the rig**, because
the place file is gitignored. C17 replaces it wholesale and deleting `workspace.SaltRig_TEMP` deletes
everything this step made and nothing else.

Six pads rather than four, to match `Config.Salt.PouchPoolSize` and so the round genuinely *chooses*
four of them — a rig with exactly `SpawnCount` pads would never exercise the selection.

```luau
local CollectionService = game:GetService("CollectionService")

local existing = workspace:FindFirstChild("SaltRig_TEMP")

if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "SaltRig_TEMP"
folder.Parent = workspace

-- Deliberately NOT co-located with TaskRig_TEMP's 4x3 grid. Salt that spawns on top of a task point
-- makes the two systems' proximity ticks indistinguishable in a playtest — "I picked up salt" and "I
-- started a hold" would fire from the same standing position, and the first bug report of the chunk
-- would be unreadable. These sit on their own row, 60 studs clear of it.
local X = { -50, -30, -10, 10, 30, 50 }

for index, x in X do
	local pad = Instance.new("Part")
	pad.Name = string.format("SaltSpawn_%02d", index)
	pad.Size = Vector3.new(3, 1, 3)
	pad.Position = Vector3.new(x, 0.5, 60)
	pad.Anchored = true
	pad.BrickColor = BrickColor.new("Institutional white")
	pad.Material = Enum.Material.Sand
	pad.Parent = folder

	CollectionService:AddTag(pad, "SaltSpawn")
end

print(`[Rig] {#X} SaltSpawn pads under {folder:GetFullName()}`)
```

**Three things go in the artifact:**

1. The output of the snippet and a `screen_capture` of the six pads.
2. **The empty-pool proof.** Delete `SaltRig_TEMP`, restart, record the console verbatim. `ItemService`
   must say — loudly, unconditionally, by name — that there are no `SaltSpawn` parts. A silent output
   window is a **failed** step, not a clean one. This is the only place the EMPTY path is observable in
   the real engine rather than in Lune, and C07's equivalent proof is the reason `TaskService`'s warning
   is known to reach an operator rather than believed to.
3. **The duplicate-name proof.** Rename `SaltSpawn_05` to `SaltSpawn_04`, restart, record the warning,
   rename it back. Thirty seconds, and it exercises the `DUPLICATE_ID` branch Step 2.2 inherits.

**The `SaltSpawn` tag contract C17 must satisfy**, stated here so the map task has something to build to
and so no step in this plan says "build the barrio": *anchored `BasePart`s, tagged `SaltSpawn` via
`CollectionService`, each with a unique `Name`, at least `Config.Salt.SpawnCount` of them, spread so that
two are not reachable from one standing position.* That sentence is the whole interface, and it is
verifiable by `search_game_tree` without any of this plan's code.

#### Step 2.2: `ItemService` — discovery and the pool verdict, reusing `TaskPool.evaluate`

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run analyze`

`CollectionService:GetTagged("SaltSpawn")`, sorted, name-unique, evaluated by the **existing**
`server/pure/TaskPool.luau` rather than a second near-identical module.

**The reuse is the point of this step and it is not a shortcut.** `TaskPool.evaluate(names, required,
expected)` takes plain strings and two numbers; nothing in it mentions tasks, and its own header
(`TaskPool.luau:3-27`) already argues for `server/pure/` on grounds that apply unchanged to salt — the
client has no use for a pool verdict, and the pool contents are the exact thing to keep off the wire. A
`SaltPool.luau` would be the same forty lines with `SaltSpawn` in the strings, and it would be the second
place a precedence bug has to be fixed. The verdict names read correctly for salt as they stand: `SHORT`
means fewer points than pouches, `OVERSIZED` means the map and Config disagree.

Replace the stub's body, keeping its header and its `Milestone: M4` line.

```diff
 --!strict
 --[[
 	ItemService — Salt: spawning, pickup, throwing, stun and reveal.
 
 	Milestone: M4
 	Spec: docs/MVP-SPEC.md
+
+	SALT IS THE ONLY COUNTERPLAY IN THE GAME (§4.6), and this file is deliberately the least clever one
+	in the repo. Four things happen here and each is server-decided:
+
+	  · pouches spawn at `SaltSpawn` points at STARTING          (C13)
+	  · a player walking within PickupRangeStuds picks one up    (C13, no remote — see below)
+	  · RequestThrowSalt(direction) is resolved into a hit       (C14, pure/SaltThrow)
+	  · a hit stuns, forces a revert, and glows for RevealDuration (C14)
+
+	THERE IS NO PICKUP REMOTE AND THAT IS A SECURITY DECISION, not an omission. `RequestTaskProgress`
+	set the shape at C08: the server resolves what a player is standing at from that player's own
+	character position, and the client names nothing. A `RequestPickup(pouchId)` would need a budget,
+	a verdict union, and validation that the named pouch is the one you are standing on — three
+	surfaces bought to replace a distance comparison the server is already positioned to make.
+
+	The pool verdict is `server/pure/TaskPool.evaluate`, shared with TaskService rather than copied.
+	It is generic over (names, required, expected) and mentions tasks nowhere.
 ]]
+
+local CollectionService = game:GetService("CollectionService")
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local AntiCheatService = require(script.Parent.AntiCheatService)
+local RoundService = require(script.Parent.RoundService)
+local TaskPool = require(script.Parent.Parent.pure.TaskPool)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local Remotes = require(Shared.Remotes)
+local SaltCarry = require(Shared.pure.SaltCarry)
+local Types = require(Shared.Types)
 
 local ItemService = {}
 
-- TODO(M4): spawn Config.Salt.SpawnCount pouches at random fixed points.
-- TODO(M4): on hit — force revert, stun, apply a visible reveal glow.
+local TAG_SPAWN = "SaltSpawn"
+
+-- Every `SaltSpawn` part in the map, keyed by Name. Rebuilt on every draw rather than cached, for the
+-- reason TaskService gives at its own `discoverPool`: C17 will add, move and delete these parts while a
+-- server is running, and a cached point is one that can stop existing.
+local pointsByName: { [string]: BasePart } = {}
+
+-- The pouches actually in the world right now. One parent so a phase change clears them with a single
+-- Destroy, exactly as MonsterService's `Corpses` folder does.
+local pouches: Folder? = nil
+
+-- SERVER-ONLY. How many pouches each player is carrying, keyed by UserId. Never replicated as a table;
+-- the count reaches its own player on SaltEffect (Step 4.3) and nowhere else.
+local carried: { [number]: number } = {}
+
+local function discoverPool(): TaskPool.Report
+	local names: { string } = {}
+
+	table.clear(pointsByName)
+
+	for _, instance in CollectionService:GetTagged(TAG_SPAWN) do
+		if not instance:IsA("BasePart") then
+			warn(
+				`[ItemService] {instance:GetFullName()} is tagged {TAG_SPAWN} but is a `
+					.. `{instance.ClassName}, not a BasePart — skipped.`
+			)
+			continue
+		end
+
+		table.insert(names, instance.Name)
+
+		-- The `: BasePart?` is load-bearing under --!strict, same as TaskService's: indexing a
+		-- `{ [string]: BasePart }` yields a non-optional value, so comparing it to nil is a type error
+		-- rather than a lookup.
+		local existing: BasePart? = pointsByName[instance.Name]
+
+		if existing == nil then
+			pointsByName[instance.Name] = instance
+		end
+	end
+
+	-- Sorted for the same reason TaskService sorts: `GetTagged`'s order is engine-defined and must not
+	-- become a hidden input to a random selection.
+	table.sort(names)
+
+	return TaskPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize)
+end
+
+--[[
+	THE LOUD HALF, ungated by VerboseLogging for the reason TaskService's `reportPool` states: this repo
+	gates routine tracing and warns unconditionally for faults, and a map with no salt in it is a fault
+	whose only player-visible symptom is that the game is unwinnable and nobody knows why.
+]]
+local function reportPool(report: TaskPool.Report)
+	if #report.Duplicates > 0 then
+		warn(
+			`[ItemService] {TAG_SPAWN} parts share a Name and were skipped: `
+				.. `{table.concat(report.Duplicates, ", ")}. Every tagged part needs a unique one.`
+		)
+	end
+
+	if report.Verdict == "EMPTY" then
+		warn(
+			`[ItemService] NO "{TAG_SPAWN}" PARTS IN THE MAP. Tag {Config.Salt.PouchPoolSize} anchored `
+				.. `parts with "{TAG_SPAWN}" via CollectionService, or no salt can ever spawn and §4.6's `
+				.. `counterplay does not exist — survivors have no answer to the Aswang at all.`
+		)
+	elseif report.Verdict == "SHORT" then
+		warn(
+			`[ItemService] Only {#report.Unique} "{TAG_SPAWN}" part(s) found; `
+				.. `{Config.Salt.SpawnCount} pouches are meant to spawn. Fewer will.`
+		)
+	elseif report.Verdict == "OVERSIZED" then
+		warn(
+			`[ItemService] {#report.Unique} "{TAG_SPAWN}" parts found, but Config.Salt.PouchPoolSize `
+				.. `says {Config.Salt.PouchPoolSize}. Spawning still works; the map and Config disagree.`
+		)
+	elseif Config.Debug.VerboseLogging then
+		print(`[ItemService] Salt pool OK — {#report.Unique} spawn points.`)
+	end
+end
 
 function ItemService.Init() end
 
 function ItemService.Start() end
 
 return ItemService
```

`npm run analyze` is the check: this step's failure modes are all typecheck-shaped — the `BasePart?`
annotation above, `TaskPool.Report` resolving across the `server/pure` boundary, and the requires
themselves. `analyze` is graded against an empty `analyze-baseline.json`, so any new diagnostic fails it.

#### Step 2.3: `src/shared/pure/SaltCarry.luau` — may this player pick this up

**File:** `src/shared/pure/SaltCarry.luau`
**Verify:** `npm run lint`

A pure verdict over `(phase, playerState, carried, limit)`. No `script.Parent` requires, unions
re-declared locally.

**`src/shared/pure/` and not `src/server/pure/`**, deliberately, and the test is the one CLAUDE.md sets:
are the INPUTS client-suppliable, and is there a seed. There is no seed, and the inputs are the phase
(already on the snapshot), the caller's own state (already on the snapshot as `YourState`) and a Config
number (already replicated). A client that requires and runs this module learns that it may not carry two
pouches, which it can also learn by trying. `TaskPool` is on the server side because its inputs are the
map's pool contents; this one has nothing of the sort.

```luau
--!strict
--[[
	SaltCarry — may this player pick up a salt pouch right now? (§4.6, C13)

		(request) -> verdict

	§4.6 IN THREE LINES: "4 salt pouches spawn at random fixed points per round. One per player carried.
	Recharge: none in MVP. Once used, it's gone. Scarcity makes it a decision."

	The scarcity half is enforced by `Config.Salt.SpawnCount`; THIS module enforces the carry half, and
	it is a separate rule because the two fail differently. A map with too few pouches is a balance
	problem you notice. A carry limit that does not hold is an exploit: walk the six spawn points, hold
	six pouches, and the one counterplay item in the game stops being a decision and becomes an arsenal.

	WHY A VERDICT RATHER THAN A BOOLEAN — the same argument TransformRules and KillValidation make. The
	server logs WHY it declined, and "you are a ghost standing on a pouch" and "you already have one"
	send a reader to two different places. C41 reads those lines.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. The weight rule in `pure/TaskWeight` had
	to earn its role-blindness with a grid; this module never takes a role at all, and it must not start.
	A carry limit that differed for the Aswang would be a role oracle readable by standing on a pouch.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural, so these and
	the ones in Types.luau are the same types and pass to each other without a cast.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "NOT_ALIVE" | "AT_LIMIT" | "NO_LIMIT_SET"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Carried: number,
	Limit: number,
}

local SaltCarry = {}

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in KillValidation: world facts first, then
	the player, then the count. A log full of AT_LIMIT is a UX finding — players walking over pouches
	they cannot take — and a log full of anything above it is a correctness finding.

	NOT_ALIVE is an ALLOWLIST of ALIVE, never `~= "SPECTATOR"`. A GHOST must not pick up salt: §4.7
	gives ghosts contribution and a spook, not the counterplay item, and C15 makes GHOST a state that a
	body walks around in — so the denylist form starts admitting them the moment Phase 6 lands. This is
	`pure/PlayerBody`'s warning in a second file, and it is the specific mistake that file predicted.
]]
function SaltCarry.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	if request.PlayerState ~= "ALIVE" then
		return "NOT_ALIVE"
	end

	--[[
		FAIL CLOSED ON THE LIMIT, and test it for positive-and-finite rather than for zero.

		`Limit` arrives from Config. A `CarryLimit` typo of `0` reads as "carry nothing" and would be
		caught by the comparison below; `-1` and `0/0` would not. `Carried < NaN` is false, so a NaN
		limit refuses — but `math.huge` is worse than either, because `Carried < inf` is always true
		and the limit silently stops existing. KillValidation's cooldown took three attempts to get
		this right (see its header); this is the fourth version of that lesson, applied first time.
	]]
	if not (request.Limit > 0 and request.Limit < math.huge) then
		return "NO_LIMIT_SET"
	end

	if request.Carried >= request.Limit then
		return "AT_LIMIT"
	end

	return "OK"
end

return SaltCarry
```

`npm run lint` (selene) is the check for a step whose deliverable is a new pure module with no caller
yet: `analyze` is Step 2.2's and `test:unit` cannot see a file that has no test until Step 2.4. selene
catches the shadowing, unused-local and shape defects that a module written in one sitting produces.

#### Step 2.4: `tests/salt-carry.test.luau` — the carry limit and the phase gate

**File:** `tests/salt-carry.test.luau`
**Verify:** `lune run tests/salt-carry.test.luau`

The full `PlayerState × carried` grid, including the second-pickup refusal C13's own Verify line names.

**This is the step that converts C13's acceptance criterion into a terminal check.** BUILD-PLAN's C13
says *"Verify: playtester picks up two in a row and is refused the second"* — a human observation that
needs a running place, two pouches and a screenshot. The rule underneath it is arithmetic, and once it is
a pure function that observation becomes a regression test that runs in milliseconds. The playtest still
happens; it just stops being the only evidence.

```luau
--!strict
--[[
	The salt carry rule (§4.6, C13), over every player state and both sides of the limit.

	The cell this file exists for is GHOST. `SaltCarry.evaluate` uses an allowlist of ALIVE, and the
	denylist form (`~= "SPECTATOR"`) is identical in behaviour TODAY and wrong the moment C15 gives a
	ghost a body to walk over a pouch with. That is `pure/PlayerBody`'s warning arriving in a second
	file, and this grid is what makes it fail here rather than in a playtest six chunks later.
]]

local SaltCarry = require("../src/shared/pure/SaltCarry")

type PlayerState = SaltCarry.PlayerState
type RoundPhase = SaltCarry.RoundPhase

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

local function request(overrides: {
	Phase: RoundPhase?,
	PlayerState: PlayerState?,
	Carried: number?,
	Limit: number?,
}): SaltCarry.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		PlayerState = overrides.PlayerState or "ALIVE",
		Carried = overrides.Carried or 0,
		Limit = overrides.Limit or 1,
	}
end

--------------------------------------------------------------------------------
-- Phase × state — twenty cells, every one stated
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local expected: SaltCarry.Verdict = if phase ~= "ACTIVE"
			then "WRONG_PHASE"
			elseif state ~= "ALIVE" then "NOT_ALIVE"
			else "OK"

		check(
			`evaluate({phase}, {state})`,
			SaltCarry.evaluate(request({ Phase = phase, PlayerState = state })) == expected,
			`expected {expected}, got {SaltCarry.evaluate(request({ Phase = phase, PlayerState = state }))}`
		)
	end
end

--------------------------------------------------------------------------------
-- C13's own acceptance criterion, as arithmetic
--------------------------------------------------------------------------------

-- "picks up two in a row and is refused the second"
check("the first pouch is granted", SaltCarry.evaluate(request({ Carried = 0 })) == "OK")
check("the second is refused", SaltCarry.evaluate(request({ Carried = 1 })) == "AT_LIMIT")

-- Above the limit, not merely at it. A pouch handed out by a bug must not open the door to a third.
check("carrying more than the limit still refuses", SaltCarry.evaluate(request({ Carried = 9 })) == "AT_LIMIT")

--------------------------------------------------------------------------------
-- Fail-closed on the limit itself
--------------------------------------------------------------------------------

for _, limit in { 0, -1, 0 / 0, math.huge } do
	check(
		`a limit of {limit} refuses rather than disabling the rule`,
		SaltCarry.evaluate(request({ Limit = limit })) == "NO_LIMIT_SET",
		`got {SaltCarry.evaluate(request({ Limit = limit }))}`
	)
end

-- The one that is easy to get wrong: math.huge is not NaN, passes every "is it a number" test, and
-- makes `Carried < Limit` true forever. See KillValidation's header for the three attempts this took
-- the first time it came up in this repo.
check(
	"an infinite limit is not a limit",
	SaltCarry.evaluate(request({ Carried = 1000, Limit = math.huge })) == "NO_LIMIT_SET"
)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  salt-carry: 20 cells + 3 limit properties + 5 fail-closed")
```

#### Step 2.5: The spawn, the pickup tick, and the teardown

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:config`

Spawn `Config.Salt.SpawnCount` pouches at `STARTING`, poll pickup during `ACTIVE`, clear everything on
the way to `INTERMISSION`/`IDLE`, and drop a departing player's carry.

```diff
+--[[
+	THE POUCH. A part, a tag, and nothing else.
+
+	No ProximityPrompt: C08 already found that Roblox's CoreScript refuses to render a prompt with
+	`KeyboardKeyCode = None`, and a pickup that costs a keypress is a pickup a player walks past. This
+	is a thing you collect by touching, resolved server-side on a tick.
+
+	`SaltPouch` IS A REPLICATED TAG AND THAT IS FINE, on the same argument `ActiveTaskPoint` won at
+	C07: it describes an object in the world that every client can already see, it names no player, and
+	the client needs it to draw the pickup affordance at all. `check:secrecy` inspects tags and this one
+	passes because it carries nothing.
+]]
+local TAG_POUCH = "SaltPouch"
+
+local rng = Random.new()
+
+local function spawnPouches()
+	local folder = pouches
+
+	if folder == nil then
+		return
+	end
+
+	local report = discoverPool()
+
+	reportPool(report)
+
+	-- Fisher-Yates over a COPY, so the pool order is not mutated under the caller. `Random.new()` with
+	-- no argument, deliberately: a seeded draw is reproducible by anyone who can guess the seed, and
+	-- `Random.new(os.time())` is client-observable to the second. See TaskService's identical note.
+	local names = table.clone(report.Unique)
+
+	for index = #names, 2, -1 do
+		local swap = rng:NextInteger(1, index)
+
+		names[index], names[swap] = names[swap], names[index]
+	end
+
+	local wanted = math.min(Config.Salt.SpawnCount, #names)
+
+	for index = 1, wanted do
+		local point: BasePart? = pointsByName[names[index]]
+
+		if point == nil then
+			continue
+		end
+
+		local pouch = Instance.new("Part")
+
+		pouch.Name = `SaltPouch_{names[index]}`
+		pouch.Size = Vector3.new(1, 1, 1) -- config-ok: the pouch's own size, not a balance knob
+		pouch.Position = point.Position + Vector3.new(0, 1, 0)
+		pouch.Anchored = true
+		pouch.CanCollide = false
+		pouch.Color = rgb(Config.Salt.PouchRgb)
+		pouch.Material = Enum.Material.Sand
+		pouch.Parent = folder
+
+		CollectionService:AddTag(pouch, TAG_POUCH)
+	end
+
+	if Config.Debug.VerboseLogging then
+		print(`[ItemService] {wanted} pouch(es) placed of {Config.Salt.SpawnCount} wanted.`)
+	end
+end
+
+-- Everything this service put in the world, and everything it remembers. Called on the way into
+-- INTERMISSION and IDLE, mirroring MonsterService.clearCorpses — NOT on "any phase that is not ACTIVE",
+-- which is the mistake that destroyed the winning kill's corpse within a frame of creating it.
+local function clearPouches()
+	local folder = pouches
+
+	if folder ~= nil then
+		for _, pouch in folder:GetChildren() do
+			pouch:Destroy()
+		end
+	end
+
+	table.clear(carried)
+end
+
+--[[
+	THE PICKUP TICK. Distance re-measured on the server every tick from the player's own character,
+	which is C08 Step 3.3's rule: a stamp a client sent is a stamp a client chose.
+
+	O(players x pouches) is at most 8 x 4 per tick and there is no cheaper shape worth writing. A
+	spatial query would be `workspace:GetPartBoundsInRadius`, which allocates per call and is the
+	wrong trade at this size — §5's budget is about frame cost on a phone, and this loop runs on the
+	server.
+]]
+local function pickupTick()
+	local folder = pouches
+
+	if folder == nil or RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return
+	end
+
+	for _, player in Players:GetPlayers() do
+		local character = player.Character
+		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+		if root == nil or not root:IsA("BasePart") then
+			continue
+		end
+
+		local verdict = SaltCarry.evaluate({
+			Phase = RoundService.GetPhase(),
+			PlayerState = RoundService.GetPlayerState(player),
+			Carried = carried[player.UserId] or 0,
+			Limit = Config.Salt.CarryLimit,
+		})
+
+		if verdict ~= "OK" then
+			continue
+		end
+
+		for _, pouch in folder:GetChildren() do
+			if not pouch:IsA("BasePart") then
+				continue
+			end
+
+			if (pouch.Position - root.Position).Magnitude > Config.Salt.PickupRangeStuds then
+				continue
+			end
+
+			carried[player.UserId] = (carried[player.UserId] or 0) + 1
+			pouch:Destroy()
+
+			-- ONE PER TICK PER PLAYER. Breaking here rather than continuing means two pouches lying in
+			-- the same spot cannot both be taken in one frame by a player whose limit is 1 — the
+			-- SaltCarry call above is outside this loop and would not have seen the first pickup.
+			break
+		end
+	end
+end
+
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase == Enums.RoundPhase.Starting then
+		spawnPouches()
+	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
+		clearPouches()
+	end
+end
+
 function ItemService.Init() end
 
 function ItemService.Start() end
```

with `Init`/`Start` becoming:

```diff
-function ItemService.Init() end
+function ItemService.Init()
+	table.clear(carried)
+	table.clear(pointsByName)
+end
 
-function ItemService.Start() end
+function ItemService.Start()
+	local folder = Instance.new("Folder")
+
+	folder.Name = "SaltPouches"
+	folder.Parent = workspace
+	pouches = folder
+
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	-- A departing player's carry goes with them. Without this the table grows for the life of the
+	-- server and, worse, a returning player under Phase 5's rejoin rule would inherit their own old
+	-- pouch count — which is a free pouch for anyone willing to reconnect.
+	Players.PlayerRemoving:Connect(function(player: Player)
+		carried[player.UserId] = nil
+	end)
+
+	task.spawn(function()
+		while true do
+			pickupTick()
+			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
+		end
+	end)
+end
```

`npm run check:config` is the check, and it can fail here for a real reason rather than a formal one:
this step writes five numbers into a service file (`1, 1, 0, 2, 0.25` in the snippets above) and each one
is a place the check either accepts with its waiver or refuses. `1` for the pouch size and the tick's
`0.25` carry `-- config-ok:` reasons; a sixth number typed without one — a hardcoded pickup radius, a
hardcoded pouch count — is exactly the drift M12 cannot find, and this check refuses it.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`rgb()` does not exist in `ItemService`.** Step 2.5's snippet calls it. `MonsterService.luau:133` has
  a private one and it is four lines; copy it with its `-- config-ok: RGB channel indices` waiver rather
  than exporting MonsterService's, which would make a colour helper a cross-service dependency.
- **Secret leakage** — none. The `SaltPouch` tag replicates and describes an object, not a player; the
  `carried` table is server-only and its count is not sent anywhere in this phase.
- **Rate limiting** — no `OnServerEvent` handler exists yet in this file, which is why `check:ratelimit`
  is Phase 3's check and not this one's.
- **Phase ownership** — `ItemService` subscribes to `PhaseChanged` and calls nothing on `RoundService`
  except `GetPhase`/`GetPlayerState`. It never calls `setPhase`, which is private anyway.
- **Player leaving mid-round** — handled: `PlayerRemoving` drops the carry, and the reason it matters is
  Phase 5's rejoin rule, which would otherwise hand a reconnecting player their old pouch.
- **A pouch spawned inside geometry is invisible and unreachable**, and on a greybox that will happen. The
  `+ Vector3.new(0, 1, 0)` offset is a guess about pad height, not a fix. It is a C17 interface problem —
  the tag contract in Step 2.1 says "anchored parts" and C17 owns where their tops are.
- **Mobile budget** — the pickup tick is server-side; the client draws nothing new in this phase.
- **Scope** — salt is explicitly IN (§3). Nothing here approaches "weapons or combat beyond salt".

---

### Phase 3: C14 — the throw, resolved entirely on the server

`RequestThrowSalt(direction)` carries a direction and nothing else — no target, no hit, no distance. The
server picks the target itself, exactly as `RequestTaskProgress` resolves its task point from position.

#### Step 3.1: `src/shared/pure/SaltThrow.luau` — the hit verdict

**File:** `src/shared/pure/SaltThrow.luau`
**Verify:** `npm run lint`

`(request) -> SaltVerdict`, ordered world-facts-first exactly as `KillValidation.evaluate` is, and
fail-closed on every geometry input in the same idiom.

**THE DESIGN DECISION THIS MODULE ENCODES, stated before the code because it is the whole of C14's
secrecy argument.** Salt affects **only a transformed Aswang**. Every other outcome — an empty cone, a
survivor in the cone, an *untransformed* Aswang in the cone, a transformed Aswang beyond `ThrowRange` —
is `MISS`, and `MISS` produces exactly one observable thing: a white burst at a point in the air
(`SaltEffect`, Step 4.3), identical in every case, plus one pouch gone.

The alternative — salt that affects the Aswang whether or not it is transformed — is a **free detector**.
Four pouches against seven survivors, thrown at the four people you suspect, and the hidden-role game is
over by minute two. §4.6's own sentence is "throw at the Aswang → stuns it, **forces revert**", and a
revert is something only a transformed player can be forced into; the spec is already describing the
transformed case and this module says so out loud.

What salt buys, therefore, is precisely the thing §4.6 promises and nothing more: when the monster is
*already visible and coming for you*, you can stop it, and the ten-second glow keeps it identified for
ten seconds after it reverts and looks human again. That is the reveal, and it is paid for.

```luau
--!strict
--[[
	SaltThrow — did this throw hit? (§4.6, C14)

		(request) -> verdict

	THE CLIENT NEVER DECIDES A HIT. It sends a direction; this module, called on the server, decides.
	That sentence is C14's whole brief and it is why there is no `Hit: boolean` anywhere in the request.

	WHAT COUNTS AS A HIT, AND THE FOUR THINGS THAT DO NOT
	----------------------------------------------------
	A hit requires a TRANSFORMED Aswang, inside `Range`, inside the cone. Everything else is MISS, and
	MISS IS ONE VALUE ON PURPOSE:

	  · nothing in the cone
	  · a survivor in the cone
	  · the Aswang in the cone, NOT transformed
	  · the Aswang in the cone, transformed, past Range

	Splitting them is the obvious refactor and it hands over the game. `MISS_NOT_ASWANG` beside
	`MISS_OUT_OF_RANGE` lets a compromised client stand in front of each player in turn and read the
	monster off the refusal shape — for the price of one pouch, which is what §4.6 charges for an
	HONEST reveal. See Types.SaltVerdict; the handler echoes nothing regardless, but a verdict that
	could be echoed safely is the property worth having, and this one has it.

	WHY UNTRANSFORMED IS A MISS RATHER THAN A WEAKER HIT. §4.6 says salt "forces revert", which only
	means something for a transformed target. Making salt work on a human-shaped Aswang turns four
	pouches into four free identity probes, and the closest thing this repo has to a rule about that is
	`pure/TaskWeight`'s: no mechanic's OBSERVABLE OUTCOME may vary by role. Here it varies by FORM, and
	the form is already public — `MonsterTransformed` broadcasts it to everyone by design.

	WHY `src/shared/pure/` IS SAFE FOR THIS, which is a fair question given the above. The module is
	callable by any client and reading it teaches an attacker the rule — but the rule is in the spec, in
	this comment, and visible in one round of play. What a client cannot obtain is the INPUT
	`TargetIsTransformedAswang`, which exists only in server memory (`monsters[userId].Transformed` and
	`RoundService.GetAswangUserId()`). Logic is not secret; inputs are. There is no seed here at all.

	NO `script.Parent` REQUIRES and no Roblox datatypes — Vec3 is a plain table, converted at the call
	site exactly as KillValidation's is.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "THROWER_NOT_ALIVE" | "NO_POUCH" | "MISS"

export type Vec3 = { X: number, Y: number, Z: number }

export type Request = {
	Phase: RoundPhase,
	ThrowerState: PlayerState,
	Carried: number,
	ThrowerPos: Vec3,
	-- Unit-length in the caller's intent, NOT trusted to be. `normalise` below handles any magnitude
	-- and refuses a zero vector, because a client sends this and a client can send Vector3.zero.
	Direction: Vec3,
	TargetPos: Vec3,
	-- The one input a client cannot obtain. True only when the target IS the Aswang AND is currently
	-- in the transformed form; the caller ANDs those two, so this module never sees a role.
	TargetIsTransformedAswang: boolean,
	Range: number,
	ConeDegrees: number,
}

local SaltThrow = {}

local function sub(a: Vec3, b: Vec3): Vec3
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function magnitude(v: Vec3): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local function dot(a: Vec3, b: Vec3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

--[[
	Returns nil for a zero-length or non-finite vector rather than dividing by it.

	A NaN component reaches this from one place only — a client's `Direction` — and every comparison
	against NaN is false, so an un-normalised NaN direction would sail past the cone test as "not
	outside it". Refusing here is the same fail-closed shape KillValidation's cooldown arrived at after
	three attempts, applied to geometry.
]]
local function normalise(v: Vec3): Vec3?
	local length = magnitude(v)

	if not (length > 0 and length < math.huge) then
		return nil
	end

	return { X = v.X / length, Y = v.Y / length, Z = v.Z / length }
end

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT. World facts, then the thrower, then the pouch, then
	geometry — the identical ordering KillValidation uses and for the identical reason: geometry is the
	only condition an honest player hits routinely, so a log full of MISS is a UX finding and a log full
	of anything above it is a security finding.

	NOTE WHAT IS NOT IN THE ORDER: there is no cooldown. §4.6 gives salt no recharge and no cadence —
	scarcity IS the limiter, and `Config.AntiCheat.Budgets.RequestThrowSalt` bounds the request rate
	regardless. A cooldown here would be a fifth number nobody tuned.
]]
function SaltThrow.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	-- ALLOWLIST of ALIVE. A ghost throwing salt is C15's shape of this bug, and the denylist form
	-- admits them the moment Phase 6 gives a ghost a body and a position.
	if request.ThrowerState ~= "ALIVE" then
		return "THROWER_NOT_ALIVE"
	end

	if request.Carried < 1 then
		return "NO_POUCH"
	end

	--[[
		EVERYTHING BELOW THIS LINE RETURNS MISS. Not "returns one of several geometric refusals" — MISS,
		one value, for four different worlds. See the header. A future edit that wants to know WHY a
		throw missed should add a second, server-only return value; it must not widen this union.
	]]
	if not request.TargetIsTransformedAswang then
		return "MISS"
	end

	if not (request.Range > 0 and request.Range < math.huge) then
		return "MISS"
	end

	local toTarget = sub(request.TargetPos, request.ThrowerPos)
	local distance = magnitude(toTarget)

	if not (distance >= 0 and distance < math.huge) or distance > request.Range then
		return "MISS"
	end

	local aim = normalise(request.Direction)
	local bearing = normalise(toTarget)

	if aim == nil or bearing == nil then
		return "MISS"
	end

	--[[
		A HALF-ANGLE IN DEGREES, COMPARED AS A COSINE. `math.cos` is monotonically decreasing over
		[0, pi], so "inside the cone" is `dot >= cos(halfAngle)` — no `math.acos`, which is the call
		that would need its own domain guard for a dot product that floating-point error pushed to
		1.0000001.

		Clamped to (0, 90) rather than trusted: `tests/config.test.luau` pins the Config value in that
		range, and this module is called with numbers rather than with Config, so it re-checks. A
		half-angle of 90 or more means a throw hits what is behind you.
	]]
	if not (request.ConeDegrees > 0 and request.ConeDegrees < 90) then
		return "MISS"
	end

	if dot(aim, bearing) < math.cos(math.rad(request.ConeDegrees)) then
		return "MISS"
	end

	return "OK"
end

return SaltThrow
```

#### Step 3.2: `tests/salt-throw.test.luau` — the cone, the range, and the untransformed case

**File:** `tests/salt-throw.test.luau`
**Verify:** `lune run tests/salt-throw.test.luau`

Boundary cases at `ThrowRange`, behind the thrower, and the one that decides the whole secrecy argument:
an untransformed Aswang is a MISS and produces nothing observable.

```luau
--!strict
--[[
	The salt hit rule (§4.6, C14) — the cone, the range, and the four worlds that must be one verdict.

	THE PROPERTY THIS FILE EXISTS TO PIN is the last section: every refusal below the pouch check must
	be indistinguishable. If a future edit splits MISS into MISS_NOT_ASWANG and MISS_OUT_OF_RANGE, the
	last three checks here fail — which is the only mechanism in this repo that would notice a change
	that reads, in review, like a helpful improvement to logging.
]]

local SaltThrow = require("../src/shared/pure/SaltThrow")

type Verdict = SaltThrow.Verdict

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local ORIGIN: SaltThrow.Vec3 = { X = 0, Y = 0, Z = 0 }
local FORWARD: SaltThrow.Vec3 = { X = 0, Y = 0, Z = 1 }

local function at(x: number, z: number): SaltThrow.Vec3
	return { X = x, Y = 0, Z = z }
end

local function request(overrides: {
	Phase: SaltThrow.RoundPhase?,
	ThrowerState: SaltThrow.PlayerState?,
	Carried: number?,
	Direction: SaltThrow.Vec3?,
	TargetPos: SaltThrow.Vec3?,
	TargetIsTransformedAswang: boolean?,
	Range: number?,
	ConeDegrees: number?,
}): SaltThrow.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		ThrowerState = overrides.ThrowerState or "ALIVE",
		Carried = if overrides.Carried ~= nil then overrides.Carried else 1,
		ThrowerPos = ORIGIN,
		Direction = overrides.Direction or FORWARD,
		TargetPos = overrides.TargetPos or at(0, 10),
		TargetIsTransformedAswang = if overrides.TargetIsTransformedAswang ~= nil
			then overrides.TargetIsTransformedAswang
			else true,
		Range = overrides.Range or 25,
		ConeDegrees = overrides.ConeDegrees or 20,
	}
end

local function verdict(overrides): Verdict
	return SaltThrow.evaluate(request(overrides))
end

--------------------------------------------------------------------------------
-- The happy path, and the three gates above geometry
--------------------------------------------------------------------------------

check("a transformed Aswang straight ahead is a hit", verdict({}) == "OK")

for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } do
	check(`{phase} refuses`, verdict({ Phase = phase :: any }) == "WRONG_PHASE")
end

for _, state in { "LOBBY", "GHOST", "SPECTATOR" } do
	check(`a {state} thrower refuses`, verdict({ ThrowerState = state :: any }) == "THROWER_NOT_ALIVE")
end

check("no pouch, no throw", verdict({ Carried = 0 }) == "NO_POUCH")

-- The pouch check sits ABOVE geometry, so an empty-handed player aiming at nothing still gets NO_POUCH
-- rather than MISS. That ordering is what lets the handler skip the whole hit resolution.
check("no pouch outranks a miss", verdict({ Carried = 0, TargetPos = at(0, 900) }) == "NO_POUCH")

--------------------------------------------------------------------------------
-- Range — the boundary, both sides
--------------------------------------------------------------------------------

check("exactly at range hits", verdict({ TargetPos = at(0, 25), Range = 25 }) == "OK")
check("one stud past range misses", verdict({ TargetPos = at(0, 26), Range = 25 }) == "MISS")

-- §4.6 via tests/config.test.luau: ThrowRange (25) > KillRange (8). A target at 20 studs is inside
-- salt's reach and outside the Aswang's, which is the entire point of the relation.
check("salt reaches where the Aswang cannot", verdict({ TargetPos = at(0, 20), Range = 25 }) == "OK")

--------------------------------------------------------------------------------
-- The cone
--------------------------------------------------------------------------------

-- 20 degrees half-angle at 10 studs: a target 3 studs off-axis is ~16.7 degrees, inside; 5 studs is
-- ~26.6 degrees, outside.
check("just inside the cone hits", verdict({ TargetPos = at(3, 10) }) == "OK")
check("just outside the cone misses", verdict({ TargetPos = at(5, 10) }) == "MISS")
check("directly behind the thrower misses", verdict({ TargetPos = at(0, -10) }) == "MISS")

check("a zero direction misses rather than dividing by zero", verdict({ Direction = ORIGIN }) == "MISS")
check("a NaN direction misses", verdict({ Direction = at(0 / 0, 1) }) == "MISS")
check("an un-normalised direction still hits", verdict({ Direction = at(0, 100) }) == "OK")

for _, cone in { 0, -5, 90, 180, 0 / 0 } do
	check(`a cone of {cone} misses rather than opening up`, verdict({ ConeDegrees = cone }) == "MISS")
end

for _, range in { 0, -1, math.huge, 0 / 0 } do
	check(`a range of {range} misses rather than reaching forever`, verdict({ Range = range }) == "MISS")
end

--------------------------------------------------------------------------------
-- THE SECRECY PROPERTY. If these three fail, salt has become a role detector.
--------------------------------------------------------------------------------

local empty = verdict({ TargetIsTransformedAswang = false, TargetPos = at(0, 10) })
local survivor = verdict({ TargetIsTransformedAswang = false, TargetPos = at(0, 3) })
local untransformed = verdict({ TargetIsTransformedAswang = false, TargetPos = at(0, 1) })
local farMonster = verdict({ TargetIsTransformedAswang = true, TargetPos = at(0, 400) })

check("an untransformed Aswang at point-blank range is a MISS", untransformed == "MISS")
check(
	"every non-hit is the SAME verdict",
	empty == "MISS" and survivor == "MISS" and untransformed == "MISS" and farMonster == "MISS",
	`empty={empty}, survivor={survivor}, untransformed={untransformed}, far={farMonster}`
)

-- The inverse, stated so the property cannot be satisfied by returning MISS for everything.
check("a transformed Aswang in range and on-axis is NOT a miss", verdict({}) ~= "MISS")

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  salt-throw: gates, range, cone, fail-closed, and the indistinguishable-miss property")
```

#### Step 3.3: `MonsterService` — `IsTransformed` and `ForceRevert`, the two seams C14 needs

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

Two query/command functions over the existing `monsters` table so `ItemService` reuses the transform
path rather than building a second one. `revert()` already handles the generation bump C14 needs.

**This is deliberately a seam and not a copy, and `MonsterService.revert` is already written for it.**
Three things in that function were put there *for C14* and reusing it is how they pay off:

- `monster.Generation += 1` (line ~377) — its own comment says "without this, a salt-forced revert at C14
  followed by a fresh transform would be cut short by the first transform's expiry timer".
- `monster.Announced` gating the revert broadcast (line ~416) — "at C14 it is *throw salt at a suspect
  mid-windup and be told whether you were right*". A second revert path would reintroduce exactly that.
- `LastRevertedAt` stamped on every revert — a salt-forced revert charges the full `KillCooldown`, which
  is what makes salt a real setback rather than an inconvenience.

Re-implementing revert inside `ItemService` would lose all three silently.

```diff
 local function onPlayerRemoving(player: Player)
 	monsters[player.UserId] = nil
 end
 
+--------------------------------------------------------------------------------
+-- The C14 seam. Two functions, and the reason they are here rather than in ItemService.
+--------------------------------------------------------------------------------
+
+--[[
+	Is this player currently in the monster form? (C14)
+
+	SERVER ONLY, AND IT IS NOT A ROLE QUERY. It answers a question about a FORM, and the form is
+	already public — `MonsterTransformed` broadcasts it to every client by design. What makes it safe
+	to expose is that the caller must already hold a UserId it got from somewhere else; this function
+	never enumerates, never returns the Aswang, and returns false for every player who is not
+	transformed including the Aswang.
+
+	ItemService ANDs this with `RoundService.GetAswangUserId()` before handing a single boolean to
+	`pure/SaltThrow`, so the role never enters the pure module at all.
+]]
+function MonsterService.IsTransformed(userId: number): boolean
+	local monster = monsters[userId]
+
+	return monster ~= nil and monster.Transformed
+end
+
+--[[
+	Salt forces a revert (§4.6, C14). A thin wrapper over the private `revert`, and thin ON PURPOSE.
+
+	Everything C14 needs from a revert already happens in there: the generation bump that invalidates
+	the in-flight forced-revert timer, the Announced gate that stops a mid-windup revert broadcasting a
+	transform nobody saw, the LastRevertedAt stamp that charges the kill cooldown, and the look
+	restoration that resolves `AppliedTo` rather than `player.Character`. A second implementation in
+	ItemService would have to get all four right and would silently get at least one wrong — C04's own
+	audit found the revert restoring hardcoded defaults instead of captured state, which is precisely
+	the class of bug a duplicate path reintroduces.
+
+	NO GUARD ON WHO CALLS THIS, deliberately: `revert` early-returns for a player who is not
+	transformed, so a mistaken call is a no-op rather than a state change. The validation that a hit
+	happened at all lives in ItemService, next to the request that claimed it.
+]]
+function MonsterService.ForceRevert(player: Player)
+	revert(player)
+end
+
 function MonsterService.Init()
```

**`npm run analyze` is the check and it is doing real work**: `MonsterService.IsTransformed` and
`ForceRevert` are declared after `revert` and `monsters` but before `Init`, and Luau's strict mode will
reject an ordering mistake (a call to `revert` from above its definition) that a reader skimming a
830-line file would not. It also catches the `MonsterState?` indexing that `monsters[userId]` returns,
which is the same `: BasePart?` class of annotation error Step 2.2 warns about.

**Require direction:** `ItemService` → `MonsterService` → `RoundService`/`RoleService`. No cycle:
`MonsterService` requires nothing from `ItemService`, and `init.server.luau`'s `SERVICE_ORDER` already
loads `MonsterService` before `ItemService` (`init.server.luau:31-32`). Deviating from the "services
subscribe rather than call" pattern needs a reason and the reason is above — this is a *command to the
owner of a resource*, not a phase notification, and `TaskService`→`RoundService.SetTasksCompleted` is the
same shape already in the tree.

#### Step 3.4: The `RequestThrowSalt` handler

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:ratelimit`

`Consume` first, argument typed `unknown` and validated, the pouch consumed on hit **and** on miss, and
nothing returned to the caller on any refusal.

```diff
+--[[
+	The target the server picks for a throw. The CLIENT NAMES NOBODY — it sends a direction, and this
+	function walks every candidate and returns the nearest one the cone accepts.
+
+	IT EVALUATES EVERY PLAYER RATHER THAN SHORT-CIRCUITING ON THE ASWANG, and that is not wasted work:
+	short-circuiting would make the loop's COST vary with whether the Aswang was in the cone, and
+	server-side timing is not something a compromised client can measure — but the shape is also how
+	the "one verdict for four worlds" property survives a future edit. There are at most eight players.
+]]
+local function resolveThrow(thrower: Player, direction: Vector3): (Types.SaltVerdict, Player?, Vector3)
+	local character = thrower.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+	if root == nil or not root:IsA("BasePart") then
+		return "THROWER_NOT_ALIVE", nil, Vector3.zero
+	end
+
+	local origin = root.Position
+	local aswangUserId = RoundService.GetAswangUserId()
+
+	local best: Player? = nil
+	local bestDistance = math.huge
+
+	for _, candidate in Players:GetPlayers() do
+		local candidateCharacter = candidate.Character
+		local candidateRoot = if candidateCharacter
+			then candidateCharacter:FindFirstChild("HumanoidRootPart")
+			else nil
+
+		if candidate == thrower or candidateRoot == nil or not candidateRoot:IsA("BasePart") then
+			continue
+		end
+
+		--[[
+			THE ROLE AND THE FORM ARE ANDed HERE AND NOWHERE ELSE. `pure/SaltThrow` receives one
+			boolean and never learns that a role exists — which is what lets that module live in
+			`shared/pure/` and be callable by any client without leaking anything.
+		]]
+		local isTransformedAswang = aswangUserId == candidate.UserId
+			and MonsterService.IsTransformed(candidate.UserId)
+
+		local verdict = SaltThrow.evaluate({
+			Phase = RoundService.GetPhase(),
+			ThrowerState = RoundService.GetPlayerState(thrower),
+			Carried = carried[thrower.UserId] or 0,
+			ThrowerPos = vec(origin),
+			Direction = vec(direction),
+			TargetPos = vec(candidateRoot.Position),
+			TargetIsTransformedAswang = isTransformedAswang,
+			Range = Config.Salt.ThrowRange,
+			ConeDegrees = Config.Salt.ThrowConeDegrees,
+		})
+
+		--[[
+			A NON-GEOMETRIC REFUSAL IS THE SAME FOR EVERY CANDIDATE, so returning it from inside the
+			loop is correct rather than sloppy: WRONG_PHASE, THROWER_NOT_ALIVE and NO_POUCH depend only
+			on the thrower, and re-deriving them per candidate is what keeps ONE call site for the whole
+			rule instead of a pre-check that can drift from it.
+		]]
+		if verdict ~= "OK" and verdict ~= "MISS" then
+			return verdict, nil, origin
+		end
+
+		if verdict == "OK" then
+			local distance = (candidateRoot.Position - origin).Magnitude
+
+			if distance < bestDistance then
+				best = candidate
+				bestDistance = distance
+			end
+		end
+	end
+
+	if best == nil then
+		-- The thrower is ALIVE, in ACTIVE, holding a pouch, and hit nothing. The pouch is still spent.
+		return "MISS", nil, origin + direction.Unit * Config.Salt.ThrowRange
+	end
+
+	local bestCharacter = (best :: Player).Character
+	local bestRoot = if bestCharacter then bestCharacter:FindFirstChild("HumanoidRootPart") else nil
+	local impact = if bestRoot and bestRoot:IsA("BasePart") then bestRoot.Position else origin
+
+	return "OK", best, impact
+end
```

and the handler itself, in `Start()`, in the shape `MonsterService.luau:793-817` established:

```diff
+	--[[
+		THE RATE LIMIT IS INLINE AND FIRST, copying MonsterService's two handlers exactly.
+		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
+		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire — so
+		a handler that IS limited but does it elsewhere reads as unguarded and fails the build. Consume
+		FIRST, before the argument is even looked at.
+	]]
+	Remotes.Get("RequestThrowSalt").OnServerEvent:Connect(function(player: Player, direction: unknown)
+		if not AntiCheatService.Consume(player, "RequestThrowSalt") then
+			return
+		end
+
+		-- A remote argument is whatever the client sent. Typed `unknown` rather than `Vector3` so this
+		-- line cannot be skipped: without it a table reaches `.Unit` and throws inside a connection,
+		-- which Roblox swallows into a single warn.
+		if typeof(direction) ~= "Vector3" then
+			return
+		end
+
+		local verdict, target, impact = resolveThrow(player, direction)
+
+		--[[
+			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK. The client learns what happened
+			the way everyone else does — from SaltEffect and from the world. See Types.SaltVerdict: a
+			verdict echoed back is a role oracle for the price of one pouch.
+		]]
+		if verdict ~= "OK" and verdict ~= "MISS" then
+			if Config.Debug.VerboseLogging then
+				-- A UserId and a verdict. Never the target, and never a role.
+				print(`[ItemService] Throw refused for {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		-- §4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO, and this line sits above the
+		-- hit branch so that no future early-return can skip it. A miss that cost nothing would make
+		-- salt a probe you throw at everyone, which is the thing pure/SaltThrow's header refuses.
+		carried[player.UserId] = math.max(0, (carried[player.UserId] or 0) - 1)
+
+		if verdict == "OK" and target ~= nil then
+			applyHit(target)
+		end
+
+		broadcastEffect(player, impact, verdict == "OK")
+	end)
```

`applyHit` and `broadcastEffect` are Phase 4's, declared there. This step's `check:ratelimit` proves the
`Consume` is present and adjacent; what it cannot prove is that the *validation* behind it is right, which
is what Step 3.2's grid is for.

`vec()` is the `Vector3` → `SaltThrow.Vec3` converter, copied from `MonsterService.luau:525` where it does
the same job for `KillValidation` — three lines, and Lune-compatibility is why both exist.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — this is the phase where it would happen, and the design answer is "one verdict for
  four worlds".** `pure/SaltThrow`'s MISS collapses empty-cone, survivor-hit, untransformed-Aswang and
  out-of-range into one indistinguishable outcome, `tests/salt-throw.test.luau` asserts it, and the
  handler echoes nothing at all. The next author's instinct will be to split MISS for better logs; the
  test is what stops them.
- **`MonsterService.IsTransformed` is a new public query on a secrecy surface.** It answers about a FORM,
  which `MonsterTransformed` already broadcasts, and it never enumerates. Still worth `exploit-auditor`'s
  attention at implementation time — CLAUDE.md's 🔒 row names `MonsterService` explicitly.
- **Rate limiting** — present and inline. Note the budget is already `{ Capacity = 3, RefillPerSecond =
  0.2 }` (`Config.luau:373`) and no step changes it: with `CarryLimit = 1` a player can legitimately
  throw at most four times in a round, so this budget is far looser than legitimate play, which is the
  direction Config's own header requires.
- **Magic numbers** — `Range` and `ConeDegrees` are passed from Config into the pure module rather than
  read inside it, which is the pattern every other pure module here follows.
- **Player leaving mid-round** — a thrower who disconnects mid-flight has no character, so `resolveThrow`
  returns `THROWER_NOT_ALIVE`; a *target* who disconnects between resolution and `applyHit` is Phase 4's
  problem and is called out there.
- **Strict Luau** — `resolveThrow` returns a three-tuple with a `Player?`; the `(best :: Player)` cast
  after the nil check is required, and `Vector3.zero` needs the Roblox datatype (this file is not pure).
- **Scope** — salt is §3 IN. There is no second item, no ammo, and no recharge.

---

### Phase 4: C14 — the stun, the reveal, and the client's one job

The reveal glow is visible to everyone by design and is **not** a third role-carrying remote. See this
phase's Step 4.2 for why, and for how the glow is bounded so it never becomes a derived hint outside its
ten seconds.

#### Step 4.1: The stun — four seconds, server-applied, server-cleared

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:config`

`WalkSpeed`/`JumpPower` zeroed and restored from captured values, with the restore surviving a revert, a
respawn and a round end.

**Restore from CAPTURED state, never from a default.** This is C04's Critical finding replayed: its
revert restored hardcoded defaults instead of the values it had captured, permanently branding the
ex-Aswang in a way readable map-wide, and `analyze` plus all five checks plus six Lune suites were green
over it. The stun touches the same two properties on the same character while `MonsterService` is also
touching them (`TransformedSpeedMult`, and `revert` restoring `BaseWalkSpeed`), so the interleaving is the
hazard, not the zeroing.

```diff
+-- Who is stunned, and what their movement was before salt touched it. SERVER-ONLY. The generation
+-- number is MonsterService.revert's trick, borrowed for the same reason: a second hit landing during
+-- the first hit's window must invalidate the first timer, or the earlier restore fires mid-stun.
+type StunState = {
+	WalkSpeed: number,
+	JumpPower: number,
+	Generation: number,
+}
+
+local stunned: { [number]: StunState } = {}
+
+local function clearStun(player: Player)
+	local state = stunned[player.UserId]
+
+	if state == nil then
+		return
+	end
+
+	stunned[player.UserId] = nil
+
+	local character = player.Character
+	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
+
+	if humanoid == nil then
+		return
+	end
+
+	--[[
+		RESTORE WHAT WAS CAPTURED. Not 16, not `Humanoid.WalkSpeed`'s default, and NOT
+		`Config.Monster.TransformedSpeedMult * 16` — the target may have reverted during the stun, so
+		neither the transformed nor the untransformed value is knowable from here. C04's audit found
+		exactly this restored-from-default bug and nothing static caught it.
+	]]
+	humanoid.WalkSpeed = state.WalkSpeed
+	humanoid.JumpPower = state.JumpPower
+end
+
+local function applyStun(player: Player)
+	local character = player.Character
+	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
+
+	if humanoid == nil then
+		return
+	end
+
+	local previous = stunned[player.UserId]
+	local generation = (if previous then previous.Generation else 0) + 1
+
+	--[[
+		CAPTURE ONLY ON THE FIRST HIT. A second hit landing mid-stun would otherwise capture 0/0 as
+		"what they had before", and the restore would leave a player frozen for the rest of the round.
+		The generation bump still fires, so the second hit extends the window; only the captured values
+		are kept from the first.
+	]]
+	stunned[player.UserId] = {
+		WalkSpeed = if previous then previous.WalkSpeed else humanoid.WalkSpeed,
+		JumpPower = if previous then previous.JumpPower else humanoid.JumpPower,
+		Generation = generation,
+	}
+
+	humanoid.WalkSpeed = 0 -- config-ok: a stun is total; 0 is the mechanic, not a knob
+	humanoid.JumpPower = 0 -- config-ok: same
+
+	task.delay(Config.Salt.StunDuration, function()
+		local current = stunned[player.UserId]
+
+		-- A stale timer from an earlier hit declines to act, exactly as MonsterService's forced-revert
+		-- timer does. Without this, hit-at-t and hit-at-t+2 would both restore at t+4 and t+6, and the
+		-- FIRST would end the second hit's stun two seconds early.
+		if current == nil or current.Generation ~= generation then
+			return
+		end
+
+		clearStun(player)
+	end)
+end
+
+--[[
+	A SALT HIT, in the order §4.6 states it: stun, force the revert, reveal.
+
+	THE REVERT GOES BETWEEN THE STUN AND THE GLOW, not before the stun. `MonsterService.revert` restores
+	`BaseWalkSpeed` onto the humanoid, so reverting first and stunning second is correct — but stunning
+	first and reverting second would have the revert overwrite WalkSpeed 0 with the pre-transform speed
+	and cancel the stun outright. `applyStun` captures BEFORE the revert and `clearStun` writes the
+	captured value after it, so the player ends the stun at the speed they had when salt hit them.
+
+	Deliberately NOT a kill and NOT a MarkKilled: §4.6 is counterplay, not a win condition. Salt never
+	ends a round.
+]]
+local function applyHit(target: Player)
+	applyStun(target)
+	MonsterService.ForceRevert(target)
+	applyReveal(target)
+end
```

Ordering note for the implementer: `applyStun` captures the humanoid's speed *before* `ForceRevert`
restores `BaseWalkSpeed` onto it, so the captured value is the transformed one and the player finishes
the stun moving at transformed speed for as long as the reveal lasts. **That is a balance question, not a
correctness one**, and it is exactly the kind of thing M12 tunes — raised in Follow Ups rather than
decided here, because the alternative (capture after the revert) is one line and neither is obviously
right without a playtest.

`npm run check:config` is the check: this step types `0` twice into a service file, each with a
`-- config-ok:` reason, and `Config.Salt.StunDuration` read rather than repeated. A stun length typed as
`4` here instead of read from Config is precisely what this check exists to refuse, and it is the most
likely mistake in the step.

#### Step 4.2: The reveal glow, and its window

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:secrecy`

One `Highlight` under the character, tracked in a table this service owns, removed on expiry, on death,
on phase change and on disconnect. Nothing named for a role, nothing on an attribute.

### Why a glow everyone can see is not a third role-carrying remote

`check-secrecy.mjs` allows exactly two remotes to carry the role: `RoundEnded` and `RoleAssigned`. The
reveal glow is not a third, and the distinction is the one `Types.MonsterTransformedPayload` already
draws for the transform:

> *"'this character transformed' is a fact about the world, while 'this player is the Aswang' is an
> inference the client is welcome to make and the server never states."*

The glow is the same shape. The server attaches a light to **a character in the workspace** — an object
every client can already see, standing in a place every client can already look at. No remote carries a
role, no payload names a player, no attribute is set, no tag is added. What a witness concludes from
"that person is glowing" is an inference, and it is the inference §4.6 is *selling*: the reveal is the
point, it is paid for with a scarce pouch, and it lasts ten seconds.

The one thing that would make it a leak is **the glow existing outside its window**, because then it
stops being an event and becomes a property of a player. Four exits have to be closed and this step
closes all four:

| Exit | What would leak |
| --- | --- |
| the timer fires but the player respawned | the Highlight is parented to the OLD character; the new one is clean, and the tracked instance must still be destroyed or it leaks memory rather than information |
| the round ends mid-glow | a glowing player on the end screen, beside a reveal that names them anyway — harmless here, ugly, and it becomes a leak the moment the next round starts before the timer fires |
| the player disconnects mid-glow | a stale entry pointing at a destroyed instance |
| **the phase changes to INTERMISSION and the glow survives** | **a player who is still glowing in the lobby of the NEXT round. This is the real one.** |

```diff
+-- Highlights this service created, keyed by UserId, with the same generation trick the stun uses.
+type RevealState = {
+	Instance: Highlight,
+	Generation: number,
+}
+
+local reveals: { [number]: RevealState } = {}
+
+local function clearReveal(userId: number)
+	local state = reveals[userId]
+
+	if state == nil then
+		return
+	end
+
+	reveals[userId] = nil
+	state.Instance:Destroy()
+end
+
+--[[
+	THE REVEAL (§4.6, C14). A Highlight on a character, for RevealDuration, visible to everyone.
+
+	A Highlight AND NOT: an attribute (replicates, and `check:secrecy` refuses role-named ones for
+	exactly this reason), a CollectionService tag (same), a name colour (`TeamColor` and `Team` both
+	replicate and are the classic version of this mistake), or a per-client effect (a "hidden" reveal
+	is a reveal that a compromised client reads and an honest one does not — the worst of both).
+
+	It is parented to the CHARACTER, not to the player, and the state table holds the instance rather
+	than the character — so a respawn cannot leave an orphan behind and cannot brand a fresh body.
+
+	NOTHING HERE IS NAMED FOR A ROLE. The instance is `SaltReveal`, the colours are
+	`Config.Salt.RevealGlow*Rgb`, and neither `check:secrecy`'s SECRET regex nor a human reader finds a
+	role in this code — because there is not one. The server never learns of a role at this point in
+	the call chain either: `applyHit` receives a Player, and the decision that this Player was a
+	transformed Aswang was made and discarded back in `resolveThrow`.
+]]
+local function applyReveal(target: Player)
+	local character = target.Character
+
+	if character == nil then
+		return
+	end
+
+	clearReveal(target.UserId)
+
+	local highlight = Instance.new("Highlight")
+	local generation = os.clock()
+
+	highlight.Name = "SaltReveal"
+	highlight.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
+	highlight.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
+	highlight.FillTransparency = 0.6 -- config-ok: the glow's own opacity, tuned by eye at C34
+	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
+	highlight.Parent = character
+
+	reveals[target.UserId] = { Instance = highlight, Generation = generation }
+
+	task.delay(Config.Salt.RevealDuration, function()
+		local current = reveals[target.UserId]
+
+		if current == nil or current.Generation ~= generation then
+			return
+		end
+
+		clearReveal(target.UserId)
+	end)
+end
+
+-- EVERY reveal and EVERY stun ends when the round does. Called from onPhaseChanged beside
+-- clearPouches, and this is the exit that actually matters: without it a player hit at second 419 of a
+-- 420-second round is still glowing in the lobby, where the glow is no longer an event that anybody
+-- witnessed and is simply a mark on one of the eight people standing there.
+local function clearAllEffects()
+	for userId in reveals do
+		clearReveal(userId)
+	end
+
+	for userId in stunned do
+		local player = Players:GetPlayerByUserId(userId)
+
+		if player ~= nil then
+			clearStun(player)
+		end
+	end
+
+	table.clear(stunned)
+end
```

`onPhaseChanged` calls `clearAllEffects()` on **every** phase that is not `ACTIVE` — unlike
`clearPouches`, which fires only on INTERMISSION/IDLE. The difference is deliberate and mirrors
`MonsterService.onPhaseChanged`'s split: pouches on the ground during ENDING are scenery, a glow during
ENDING is a mark on a player.

`DepthMode = Occluded` is stated because the alternative (`AlwaysOnTop`) would render the glow **through
walls**, turning a ten-second reveal into a ten-second wallhack on the monster. That is a design decision
hiding in an enum value.

**`npm run check:secrecy` is the check and it discriminates**: the scanner inspects `SetAttribute` and
`AddTag` names against its SECRET and ROLE_TOKEN regexes (`check-secrecy.mjs:350-367`), which is exactly
the shape this step is tempted into — `character:SetAttribute("Revealed", true)` is the two-line version
of this whole function and it would let any client poll every player for the flag. The check's own ALLOW
suite includes `SetAttribute("Stunned", true)` as a case it deliberately permits, which is worth knowing:
a *neutrally named* attribute passes the check and would still be a per-frame readable brand. The
Highlight avoids the question entirely by not being data.

#### Step 4.3: `SaltEffect` — the public world event

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run check:remotes`

Already declared in `Remotes.EVENTS_DOWN` (`Remotes.luau:37`), so **this plan adds nothing to the network
surface for salt at all** — `RequestThrowSalt` and `SaltEffect` were both declared at C01 and have sat
unused since. That is worth stating because `check:remotes` fails on a remote *used but not declared*, and
the failure mode on the client is the nastiest in the repo: `WaitForChild` on a name the server never
created hangs forever, with no error, no output and no stack trace.

```diff
+local saltEffectRemote = Remotes.Get("SaltEffect")
+
+--[[
+	The public half of a throw. Fired to EVERY client, with a trajectory and no player.
+
+	Built as a TYPED LOCAL, not an inline table: `FireAllClients` takes `...any`, so an inline literal
+	is checked against nothing at all. The annotation catches a wrong type and a missing field — but
+	NOT an extra one, which is the leak shape. See Types.SaltEffectPayload; the fields that must never
+	appear there are `ThrowerUserId` and `TargetUserId`, and neither contains a token
+	`check-secrecy.mjs` matches.
+
+	FireAllClients IS CORRECT HERE and it is the only broadcast this plan adds. A throw is a white
+	burst in the air at a place; every client standing there sees it whether or not this remote exists,
+	and a client that is nowhere near renders a burst it cannot see. `Hit` says the salt struck
+	something salt can strike — which, per pure/SaltThrow, means a TRANSFORMED Aswang, and a
+	transformed Aswang is already public via MonsterTransformed. It buys a hit sound instead of a
+	fizzle and states nothing new.
+]]
+local function broadcastEffect(thrower: Player, impact: Vector3, hit: boolean)
+	local character = thrower.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+	local origin = if root and root:IsA("BasePart") then root.Position else impact
+
+	local payload: Types.SaltEffectPayload = { Origin = origin, Impact = impact, Hit = hit }
+
+	saltEffectRemote:FireAllClients(payload)
+end
```

**One thing this step must NOT do**, and it is the natural next line: fire a second, private
`SaltEffect` to the thrower carrying their remaining pouch count. That is a per-player payload on a
broadcast remote, and two sends with different shapes on one remote is how `check:secrecy`'s field
allowlist stops being able to describe it. The client tracks its own pouch count from `SaltEffect`'s
arrival (it threw, so it spent one) and from the `SaltPouch` tag disappearing; if C18's HUD needs an
authoritative count, that is a new down-remote declared in `Remotes.luau` with its own reason, not a
second meaning bolted onto this one. Raised in Follow Ups.

`npm run check:remotes` is the check, and it is the right one specifically because this step is where a
name typo would land — `Remotes.Get("SaltEffects")` typechecks fine, returns a freshly created
RemoteEvent on the server, and hangs every client that waits for the real one.

#### Step 4.4: The client throws, and decides nothing

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run analyze`

A bind that fires the camera's look direction and renders `SaltEffect`. It does not know whether it hit,
because the server never tells it.

```diff
+--[[
+	THE SALT THROW (§4.6, C14). The client's entire contribution to this mechanic is a direction.
+
+	It sends `camera.CFrame.LookVector` and stops. It does not raycast, does not pick a target, does
+	not check range, does not check whether anyone is in front of it, and — critically — does not
+	predict a hit and render one optimistically. A client that renders a hit the server refused is a
+	client that has told its player the monster is stunned when it is not, which is worse than latency.
+
+	IT DOES NOT GATE ITSELF ON A POUCH COUNT EITHER, beyond hiding the button. The server owns
+	`carried` and refuses with NO_POUCH; a client-side check here would be a second copy of a rule and
+	the two would disagree the first time a pickup and a throw crossed on the wire.
+]]
+local function throwSalt()
+	local camera = workspace.CurrentCamera
+
+	if camera == nil then
+		return
+	end
+
+	Remotes.Get("RequestThrowSalt"):FireServer(camera.CFrame.LookVector)
+end
```

bound alongside the existing task bind, and — per C08's finding that a `ProximityPrompt` cannot free its
keycode — through `ContextActionService`/`UserInputService` in whatever shape `InputController` already
uses for `E`. **Mobile matters here** (§5: ~60% of players): the bind needs a touch button, and a throw
aimed by the camera is aimable on a phone in a way a raycast is not, which is the reason
`Config.Salt.ThrowConeDegrees` exists at all.

The reception side, in whichever controller owns world effects (`CameraFXController` is the closer fit —
it already handles `MonsterTransformed` and `PlayerKilled`):

```diff
+--[[
+	A throw happened somewhere (C14). Renders a burst; concludes nothing.
+
+	`payload.Hit` says salt struck something salt can strike. It does NOT name who, and this handler
+	must never start inferring it — the nearest-character-to-Impact computation is one line away and
+	would hand every player the answer that §4.6 charges a pouch for. The same warning is on
+	`onPlayerKilled` two functions up, for the same reason, and it has held so far.
+]]
+local function onSaltEffect(payload: Types.SaltEffectPayload)
+	print(`[Client] Salt {if payload.Hit then "HIT" else "thrown"} at {payload.Impact}`)
+
+	-- TODO(M7): a white particle burst along Origin -> Impact, and a distinct crackle on Hit.
+end
```

`npm run analyze` is the check: the client half's failure modes are `workspace.CurrentCamera` being
`Camera?`, `Types.SaltEffectPayload` resolving from `ReplicatedStorage.Shared`, and the controller's
`Init`/`Start` shape — all typecheck-shaped, none of them caught by the four checks already used in this
phase, and `analyze` runs over `src/client` as well as `src/server`.

**This step is the one whose real evidence is a screenshot**, and C14's own Verify line says so:
*"playtester lands a throw, screenshot of the glow from a third client. 🔒 mandatory."* Three clients,
because the glow being visible to a *bystander* is the claim, and the thrower's own screen cannot make it.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **The glow outliving its window is the only real leak in this phase**, and it has four exits. Step 4.2
  closes all four; the INTERMISSION one is the one that would actually ship broken.
- **`DepthMode` is a security-relevant enum value.** `AlwaysOnTop` makes the reveal a wallhack.
- **A target who disconnects between `resolveThrow` and `applyHit`** leaves `player.Character == nil`;
  `applyStun` and `applyReveal` both early-return on it, and `PlayerRemoving` must drop both tables.
- **A target who dies during the stun** — `MonsterService.makeCorpse` detaches the character, so
  `clearStun`'s humanoid lookup finds nothing and the captured speed is never restored. Harmless (the
  body is gone) but the table entry leaks until `clearAllEffects`; the Highlight, parented to that
  character, becomes **a glowing corpse**, which is a striking image and an accidental "this corpse is
  the monster" signal. **The Aswang cannot be killed, so this is only reachable via a reset or a fall** —
  worth a line in `clearStun`/`clearReveal` regardless.
- **Rate limiting** — Phase 3's handler is the only `OnServerEvent` in the file; nothing here adds one.
- **Mobile budget** — one `Highlight` at a time, at most one per round in practice, well under §5's eight
  dynamic lights. A `Highlight` is not a light, but the particle burst the client TODO describes will be.
- **Balance, not correctness** — the stun captures the *transformed* WalkSpeed, so a salted Aswang moves
  at transformed speed once the stun lifts. Follow Ups.
- **Scope** — nothing from §3's OUT list.

---

### Phase 5: C15 — the rejoin hole, the dealt-in set, and the disconnect death

This phase closes the exploit BUILD-PLAN calls "a hard counter to the entire monster" and carries all
three of its completeness conditions.

### DECISION 2 — the husk is the better design, and it does not belong in C15

**Recommendation: ship (a) GHOST-on-rejoin here. Give (b) the disconnect husk its own chunk, after
GATE 1.** Both halves of that sentence are load-bearing, so here is the working.

**Today's hole, precisely.** `onPlayerAdded` (`RoundService.luau:865-871`) marks *every* mid-round arrival
`SPECTATOR`, including a player who was `ALIVE` sixty seconds ago. A `SPECTATOR` is not counted by
`aliveCount()`, gets no body (`BodyTransitions.mayHaveBody` admits LOBBY and ALIVE only) and — since C05 —
cannot be killed (`KillValidation` requires `TargetState == "ALIVE"`). So: hear the transform, Alt-F4,
come back, and you are an invulnerable observer for the rest of the round. Free, repeatable, and it
counters the monster completely.

**(a) GHOST-on-rejoin.** The returning player becomes a `GHOST`. Cost: this phase — one pure module, one
test, a `dealtIn` table with four touch points, and a two-line change in `onPlayerAdded`. It closes the
exploit completely: a ghost is not `ALIVE`, so it is uncounted (correct — they left), unkillable (correct
— they are dead), and it gets a ghost's body from Phase 6.

Its honest weakness is the one BUILD-PLAN names: the quitter lands with the **full ghost feature set** —
ghost chat, `RequestGhostSpook`, 0.25× contribution — without ever having been caught. Quitting is
therefore *less* profitable, not unprofitable. Note the size of what is left, though: what a quitter gains
is the ability to keep playing as a ghost, which is exactly what they would have had if the Aswang had
caught them. The remaining incentive is "avoid being killed on camera", and against that they lose their
body, their salt, their ability to complete tasks at full rate and their ability to win. **That is a small
residue, and it is the same residue any elimination game has.**

**(b) The disconnect husk.** On disconnect during `ACTIVE`, detach the character and leave it standing;
if the player returns within a window, re-attach them as `ALIVE` at that position; if the Aswang kills the
husk meanwhile, they return as `GHOST` with a corpse where they stood. Quitting then gains nothing and
costs nothing, which is strictly the better design — it is the only version where the *decision* to quit
is neutral rather than merely unattractive.

**Costed honestly, it is a chunk and not a step:**

| Piece | Why it is not small |
| --- | --- |
| **The window is a real number nobody has measured.** Roblox rejoin latency is realistically 15–40s — client shutdown, matchmaking, place load, character load — and the server may not even place the returning player on the *same server*. | `Config.Round.HuskWindow` needs a value, and a wrong one is invisible: too short and the husk is pointless, too long and a 7-minute round is mostly husks. There is no test that can pick it; it needs a playtest with real disconnects. |
| **Server-hopping defeats it entirely, and nothing in this plan can detect that.** A player who quits and rejoins is not guaranteed the server they left. | The husk protects against Alt-F4-and-return-here. It does nothing against Alt-F4-and-return-anywhere, which is the same keypress. |
| **Win-condition counting.** Amendment A1 froze `DealtInSurvivors` at STARTING and counts `AswangKills`. A husk that is killed *is* a kill and must increment it; a husk whose owner never returns must not. | The count is correct today precisely because only a validated kill writes it. A husk introduces a body that is killable but whose owner may be absent — a case A1's three failed patches never had to consider. |
| **The husk is a body with no player.** `KillValidation` takes a `TargetState`, `MonsterService` resolves `player.Character`, `TaskService` measures presence from `player.Character`, `applyBodyRule` grants and revokes it, and `PlayerStates` is keyed by UserId. | Every one of those assumes the character belongs to a connected `Player`. A husk is a fifth `PlayerState` in all but name, and `Types.PlayerState` has four — which every allowlist in `pure/` is written against. |
| **Round end, husk standing.** | `enterEnding` → `clearCorpses`, `clearPouches`, `clearAllEffects`; the husk needs its own teardown, and a player returning *after* the round ended must land in LOBBY, not re-attach to a stale body. |

**Rough size: comparable to this entire phase, plus a fifth `PlayerState` rippling through four pure
modules and their tests, plus a Config number only a playtest can set.** Folding that into C15 would make
C15 the largest chunk in the build plan and would put an unmeasurable number on the critical path to
GATE 1.

**So: (a) now, (b) as its own chunk, and the right time for it is after C19.** GATE 1 asks six humans
whether they want a sixth round. If nobody rage-quits, the husk is solving a problem this game does not
have; if several do, C19's notes will say *why*, and the window can be set from observed behaviour instead
of guessed. That ordering also means the fifth-state refactor lands against a design that six people have
already validated. Recorded in Follow Ups as a proposed chunk.

BUILD-PLAN's three completeness conditions for (a) are carried into Steps 5.3, 5.4 and 5.5 respectively.

#### Step 5.1: `src/shared/pure/RejoinResolve.luau` — what a returning player becomes

**File:** `src/shared/pure/RejoinResolve.luau`
**Verify:** `npm run lint`

`(phase, wasDealtIn) -> PlayerState`. Two inputs, three outputs, and the whole decision in a table a test
can enumerate rather than in a nested `if` inside `onPlayerAdded`.

**It is a module for the reason `BodyTransitions` is one**, and that file's header is the argument
verbatim: `RoundService` "was patched five times across four review rounds, and every defect was the same
shape: one entry point handled and its twin not." This decision has exactly the shape those defects had —
a conditional over a phase and a flag, in a function with four other jobs, where the wrong cell is
invisible until somebody exploits it.

```luau
--!strict
--[[
	RejoinResolve — what state does a player who just joined belong in? (§6.4, C15)

		(phase, wasDealtIn) -> playerState

	THE BUG THIS REPLACES WAS A LIVE EXPLOIT, and it is worth stating because the fix is two lines and
	looks like tidying. C01's `onPlayerAdded` marked EVERY mid-round arrival SPECTATOR:

		state.PlayerStates[player.UserId] = if isRoundUnderway() then SPECTATOR else LOBBY

	That is right for a stranger and catastrophic for a returner. A SPECTATOR is uncounted by
	`aliveCount`, bodiless under `BodyTransitions`, and — since C05 — UNKILLABLE, because
	`KillValidation` requires `TargetState == "ALIVE"`. So a survivor who heard the transform, pressed
	Alt-F4 and came back was an invulnerable observer for the rest of the round, at no cost, every
	round. BUILD-PLAN calls it "a hard counter to the entire monster" and it is not an overstatement.

	THE FIX IS TO ASK A SECOND QUESTION: were you DEALT IN to this round? A player who was is a player
	who left a round they were part of, and §4.7 already has a word for someone who is in the round but
	no longer alive. They come back as a GHOST — which is both the correct fiction and the correct
	mechanics: uncounted (they left), unkillable (they are dead), and given ghost's body, chat and 25%
	contribution rather than a free spectator seat.

	WHY GHOST RATHER THAN ALIVE, which is the obvious alternative and is wrong: re-admitting them as
	ALIVE would let a cornered survivor quit, wait out a chase, and return with full health and no
	corpse — a teleport-to-safety with a loading screen. §4.8's win counts kills, so it would also let
	a player deny the Aswang a kill it had already earned. The husk design (see the phase preamble)
	answers this properly and is not this chunk.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

local RejoinResolve = {}

--[[
	`wasDealtIn` is "this UserId was in the set frozen at STARTING", NOT "this UserId has an entry in
	PlayerStates" — a disconnect deletes the PlayerStates entry (`onPlayerRemoving:895`), which is
	exactly why the dealt-in set has to be its own table. See Step 5.3.

	THE CELLS, ALL TEN:

	                    dealt in        not dealt in
	  IDLE              LOBBY           LOBBY
	  INTERMISSION      LOBBY           LOBBY
	  STARTING          GHOST           SPECTATOR
	  ACTIVE            GHOST           SPECTATOR
	  ENDING            GHOST           SPECTATOR

	THE TWO LOBBY ROWS ARE NOT A SHORTCUT. Between rounds nobody is dealt in — `enterIntermission` and
	`enterIdle` both clear the set — so the `wasDealtIn` column is unreachable there in practice. It is
	written as LOBBY anyway rather than left to fall through, because a stale set (a clear that a future
	edit forgets) must produce a harmless answer and not a lobby full of ghosts.

	STARTING IS INCLUDED WITH ACTIVE deliberately. `onPlayerRemoving` already treats STARTING as
	in-round, because the Aswang seeing their role card and quitting inside StartingDelay was a live
	exploit (see its comment). The rejoin side has to agree or the two disagree about who is in the
	round for four seconds every round.

	ENDING TOO: the round is over but the reveal is on screen, and a player who quits at the kill that
	ended it must not come back embodied while their own corpse is still lying there.
]]
function RejoinResolve.stateFor(phase: RoundPhase, wasDealtIn: boolean): PlayerState
	if phase == "IDLE" or phase == "INTERMISSION" then
		return "LOBBY"
	end

	return if wasDealtIn then "GHOST" else "SPECTATOR"
end

return RejoinResolve
```

`npm run lint` is the check for the same reason it was in Step 2.3: `analyze` is Step 5.3's, and a new
pure module with no caller and no test yet has nothing stronger available until Step 5.2 exists.

#### Step 5.2: `tests/rejoin-resolve.test.luau` — the full grid

**File:** `tests/rejoin-resolve.test.luau`
**Verify:** `lune run tests/rejoin-resolve.test.luau`

Five phases × dealt-in/not = ten cells, every one asserted, including the cell that is the exploit.

```luau
--!strict
--[[
	What a joining player becomes (§6.4, C15) — all ten cells.

	The cell this file exists for is ACTIVE × dealt-in. Every other cell is behaviour C01 already had;
	that one was the exploit, and it is asserted twice — once as a cell and once as a named property,
	because a future edit that "simplifies" the function back to `if isRoundUnderway()` passes the
	other nine.
]]

local RejoinResolve = require("../src/shared/pure/RejoinResolve")

type RoundPhase = RejoinResolve.RoundPhase
type PlayerState = RejoinResolve.PlayerState

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

local DEALT_IN: { [RoundPhase]: PlayerState } = {
	IDLE = "LOBBY",
	INTERMISSION = "LOBBY",
	STARTING = "GHOST", -- onPlayerRemoving already treats STARTING as in-round; this agrees with it
	ACTIVE = "GHOST", -- THE EXPLOIT CELL
	ENDING = "GHOST", -- their corpse may still be on screen behind the reveal
}

local STRANGER: { [RoundPhase]: PlayerState } = {
	IDLE = "LOBBY",
	INTERMISSION = "LOBBY",
	STARTING = "SPECTATOR",
	ACTIVE = "SPECTATOR",
	ENDING = "SPECTATOR",
}

for _, phase in PHASES do
	check(
		`stateFor({phase}, dealt in)`,
		RejoinResolve.stateFor(phase, true) == DEALT_IN[phase],
		`expected {DEALT_IN[phase]}, got {RejoinResolve.stateFor(phase, true)}`
	)

	check(
		`stateFor({phase}, stranger)`,
		RejoinResolve.stateFor(phase, false) == STRANGER[phase],
		`expected {STRANGER[phase]}, got {RejoinResolve.stateFor(phase, false)}`
	)
end

--------------------------------------------------------------------------------
-- The properties the cells exist to express
--------------------------------------------------------------------------------

-- THE EXPLOIT, named. A survivor who hears the transform, quits, and returns must NOT come back as a
-- SPECTATOR: uncounted plus unkillable is an invulnerable observer, and it is free.
check(
	"a returning survivor is not laundered into a spectator",
	RejoinResolve.stateFor("ACTIVE", true) ~= "SPECTATOR"
)

-- And not ALIVE either, which is the other wrong answer: that is a teleport to safety with a loading
-- screen, and it denies the Aswang a kill it had already earned.
check("a returning survivor is not restored to ALIVE", RejoinResolve.stateFor("ACTIVE", true) ~= "ALIVE")

-- A genuine stranger is unaffected. C01's containment rule stands for the case it was written for.
check(
	"a mid-round stranger is still contained",
	RejoinResolve.stateFor("ACTIVE", false) == "SPECTATOR"
)

-- NOBODY IS EVER DEALT ALIVE BY THIS FUNCTION. `setAllPlayerStates(Alive)` in enterStarting is the one
-- writer of ALIVE, and a rejoin path that could produce it would be a second one.
for _, phase in PHASES do
	for _, dealtIn in { true, false } do
		check(
			`stateFor({phase}, {dealtIn}) never returns ALIVE`,
			RejoinResolve.stateFor(phase, dealtIn) ~= "ALIVE"
		)
	end
end

-- Between rounds, both columns agree. A stale dealt-in set must be harmless rather than a lobby of
-- ghosts; this is the cell that makes a forgotten `table.clear` a non-event.
check(
	"a stale dealt-in set cannot ghost the lobby",
	RejoinResolve.stateFor("IDLE", true) == "LOBBY"
		and RejoinResolve.stateFor("INTERMISSION", true) == "LOBBY"
)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  rejoin-resolve: 10 cells + 5 properties")
```

#### Step 5.3: `RoundService` — the dealt-in set, its own table, cleared in three places

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run analyze`

Populated in `enterStarting` beside `setAllPlayerStates(Alive)`, cleared in `enterIntermission`,
`enterIdle` and `Init()`. It cannot live in `PlayerStates` because `setAllPlayerStates` opens with
`table.clear` (`RoundService.luau:438`) — **BUILD-PLAN's first completeness condition, verbatim, and it is
a correctness constraint rather than a style note.** Putting a `DealtIn = true` marker inside
`PlayerStates` would survive exactly until the next wholesale state change, which is the transition into
the very round it describes.

It also **cannot** be derived from `PlayerStates` at read time, and that is the subtler half:
`onPlayerRemoving:895` sets `state.PlayerStates[player.UserId] = nil`, so by the time the player comes
back there is no entry to inspect. The set has to be written at STARTING and outlive the departure.

```diff
 	-- Keyed by UserId. LOBBY between rounds, ALIVE for everyone dealt into a round, SPECTATOR for
 	-- anyone who joined after it started (spec §6.4), GHOST once C15 lands.
 	PlayerStates = {} :: { [number]: PlayerState },
 }
 
+--[[
+	EVERYONE DEALT INTO THE CURRENT ROUND, frozen at STARTING and keyed by UserId (§6.4, C15).
+
+	ITS OWN TABLE, AND NOT A FIELD IN PlayerStates, for a mechanical reason: `setAllPlayerStates` opens
+	with `table.clear(state.PlayerStates)`, so a marker living in there would be erased by the very
+	transition that should be setting it.
+
+	IT ALSO CANNOT BE DERIVED AT READ TIME. `onPlayerRemoving` deletes the departing player's
+	PlayerStates entry, which is the whole reason this exists: at the moment we need to ask "were you
+	in this round?", every trace of them in PlayerStates is already gone.
+
+	SERVER-ONLY, and it never reaches the snapshot. It is a roster of who started, which — combined
+	with who is currently connected — is a survivor count, which is the oracle Amendment A3 removed.
+	Nothing may send this table, its size, or a boolean derived from it.
+
+	Cleared in exactly three places: enterIntermission, enterIdle and Init. Not in enterEnding: a
+	player who quits at the killing blow and returns during the twelve-second end screen must still
+	resolve to GHOST, and clearing here would hand them a SPECTATOR seat for the reveal.
+]]
+local dealtIn: { [number]: boolean } = {}
+
 RoundService.PhaseChanged = Instance.new("BindableEvent")
```

```diff
 local function enterIdle()
 	state.AswangUserId = nil
 	state.TasksCompleted = 0
 	state.GateOpen = false
 	state.DealtInSurvivors = 0
 	state.AswangKills = 0
+	table.clear(dealtIn)
 	RoleService.ClearRoles()
```

```diff
 local function enterIntermission()
 	RoleService.ClearRoles()
+	table.clear(dealtIn)
 	RoundService.SetTasksCompleted(0)
```

```diff
 local function enterStarting()
 	state.RoundNumber += 1
 	-- Everyone present when the round is drawn is dealt in. Anyone arriving from here until the
 	-- next INTERMISSION becomes a SPECTATOR in onPlayerAdded.
 	setAllPlayerStates(Enums.PlayerState.Alive)
 
+	--[[
+		THE DEALT-IN SET, frozen here and not touched again this round. Written AFTER
+		setAllPlayerStates so it reads the table that call just built, and BEFORE the role draw so
+		nothing about it can depend on who the Aswang is.
+
+		Note this is the same roster `dealtInUserIds()` returns and deliberately not the same table:
+		that one is a sorted array built for RoleDraw and rebuilt from PlayerStates on demand, which
+		is precisely the thing that stops working the moment somebody disconnects.
+	]]
+	table.clear(dealtIn)
+
+	for userId, playerState in state.PlayerStates do
+		if playerState == Enums.PlayerState.Alive then
+			dealtIn[userId] = true
+		end
+	end
+
 	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())
```

```diff
 function RoundService.Init()
 	state.Phase = Enums.RoundPhase.Idle
 	table.clear(state.PlayerStates)
+	table.clear(dealtIn)
 end
```

`npm run analyze` is the check: a `{ [number]: boolean }` declared above `RoundService.PhaseChanged` and
read from a function 800 lines below is exactly the ordering that strict Luau catches and a reader does
not, and this step touches five separate locations in a 1017-line file.

#### Step 5.4: `onPlayerAdded` resolves a returning dealt-in player

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run verify:fast`

Replace the two-way `isRoundUnderway()` conditional with a call to `RejoinResolve`, so a survivor who
quit and came back is a `GHOST` rather than an unkillable, uncounted `SPECTATOR`.

```diff
 local function onPlayerAdded(player: Player)
-	-- Joined mid-round → spectator until the next round is drawn. Without this a late arrival is
-	-- indistinguishable from a survivor and would be counted alive by every win check from C06 on.
-	state.PlayerStates[player.UserId] = if isRoundUnderway()
-		then Enums.PlayerState.Spectator
-		else Enums.PlayerState.Lobby
+	--[[
+		WHO IS THIS, AND WERE THEY HERE? Two questions, because C01 asked only the first.
+
+		A stranger arriving mid-round is still contained as a SPECTATOR — that rule is C01's and it is
+		correct: a late arrival is otherwise indistinguishable from a survivor and would be counted
+		alive by every win check from C06 on.
+
+		A RETURNING PLAYER IS A DIFFERENT PERSON TO THE RULE, and treating them the same was a live
+		exploit: SPECTATOR is uncounted AND, since C05, unkillable, so hearing the transform and
+		pressing Alt-F4 bought an invulnerable seat for the rest of the round. They come back as a
+		GHOST — the correct fiction and the correct mechanics.
+
+		The decision is in `pure/RejoinResolve` with all ten cells enumerated in its test, because this
+		is a conditional over a phase and a flag inside a function with four other jobs, which is the
+		exact shape of the five defects `pure/BodyTransitions` was extracted to stop.
+	]]
+	state.PlayerStates[player.UserId] =
+		RejoinResolve.stateFor(state.Phase, dealtIn[player.UserId] == true)
```

with the require alongside the other pure modules at the top of the file:

```diff
 local BodyTransitions = require(Shared.pure.BodyTransitions)
+local RejoinResolve = require(Shared.pure.RejoinResolve)
 local RoundTransitions = require(Shared.pure.RoundTransitions)
```

**`applyBodyRule(player, "JOINED")` below is unchanged and now does more work than it used to.** With
`BodyTransitions.mayHaveBody` admitting GHOST from Phase 6, `JOINED` for a GHOST resolves to `GRANT` and
the returning player is given a ghost body on arrival, through the same path every other spawn in this
game goes through. **Phase ordering matters here:** land Phase 5 before Phase 6 and a returning player is
a bodiless GHOST for one phase, which is the current behaviour for a dead player and therefore not a
regression. Land them the other way round and nothing breaks either. Neither ordering leaves the game
unrunnable, which is the property this plan's phasing is trying to preserve.

**`isRoundUnderway()` keeps its other caller** and must not be deleted — it is not used anywhere else in
`onPlayerAdded` after this change, so `analyze` may report it unused; check before removing, because a
future win-condition edit is the kind of thing that reaches for it.

`npm run verify:fast` is the check: this is a behavioural edit to the most-patched function in the repo,
and the failure it is most likely to produce is a *secrecy* one rather than a type one — a returning
player receiving a snapshot built before their state was resolved. `verify:fast` runs `analyze`,
`check:remotes`, `check:secrecy` and the toolchain, which covers the type edit and the send at
`onPlayerAdded:891` together.

#### Step 5.5: A disconnect during ACTIVE is a death for scoring

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run test:unit`

Record it now, in the one place that sees it, so C32's XP numbers are explainable. It is explicitly
**not** a kill: `state.AswangKills` is untouched, and Amendment A1's whole point is that only a
validated kill writes it.

**BUILD-PLAN's third completeness condition**, and its reasoning is worth repeating because the cost of
skipping it is deferred rather than absent: *"record a disconnect during ACTIVE as a death for scoring
and XP, or it resurfaces at C32 as XP numbers nobody can explain."* At C32 the question will be "why did
this player get a survival bonus for a round they left", and the answer will be four chunks upstream in a
function nobody is looking at.

```diff
 	local inRound = state.Phase == Enums.RoundPhase.Active
 		or state.Phase == Enums.RoundPhase.Starting
 
 	if not inRound then
 		return
 	end
 
+	--[[
+		A DISCONNECT DURING A ROUND IS A DEATH FOR SCORING, AND NOT A KILL (§4.8 + Amendment A1, C15).
+
+		Two different books, and conflating them is what A1's three failed patches did:
+
+		  · SCORING asks "did this player survive the round?" — no. They are not owed a survival
+		    bonus, and at C32 that has to already be true or the numbers are unexplainable.
+		  · THE WIN asks "how many people did the Aswang kill?" — not this one. `state.AswangKills`
+		    is untouched here, deliberately and permanently: it is written by `commitKill` and by
+		    nothing else, which is the structural property that finally made §4.8 correct after three
+		    arithmetic patches failed.
+
+		Recorded via the dealt-in set rather than a new table: the player is leaving, their
+		PlayerStates entry is already gone, and `dealtIn[userId]` is the only surviving evidence they
+		were ever in this round. C32 reads it at ENDING.
+
+		ProgressionService is a stub (C31/C32), so this is a marker and a log rather than an award.
+		The alternative — leaving it entirely to C32 — means C32 has to reconstruct who left from
+		nothing, and there is nothing to reconstruct it from.
+	]]
+	if dealtIn[player.UserId] == true then
+		leftDuringRound[player.UserId] = true
+
+		if Config.Debug.VerboseLogging then
+			-- A UserId and a fact. Never a role: this line is read while the round is still running.
+			print(`[RoundService] {player.UserId} left during {state.Phase} — scored as not surviving.`)
+		end
+	end
+
 	-- The Aswang rage-quits / disconnects: end cleanly rather than leaving
 	-- survivors wandering a monster-free map for six minutes.
 	if state.AswangUserId == player.UserId then
```

**Placement above the Aswang branch is deliberate.** That branch `return`s, so a departing Aswang would
otherwise never be recorded — and "the Aswang left" is exactly the round C32 needs to score differently
from a round the Aswang lost.

`leftDuringRound` is a fourth server-only table beside `dealtIn`, cleared in the same three places, with
the same "never send this, its size, or a boolean derived from it" warning — it is a live count of who has
quit, which combined with the roster is the survivor count Amendment A3 removed.

```diff
+-- UserIds who were dealt into the current round and disconnected before it ended (§4.8, C15). Cleared
+-- alongside `dealtIn`, sent nowhere, and read by ProgressionService at C32. SERVER-ONLY, and for the
+-- same reason `dealtIn` is: roster minus departures is a survivor count.
+local leftDuringRound: { [number]: boolean } = {}
```

`npm run test:unit` is the check. It is not a direct test of this edit — nothing in `tests/` can see
`onPlayerRemoving`, which touches the DataModel — and it is chosen because this step's realistic failure
is *breaking something else*: `tests/win-conditions.test.luau` pins that a departure does not advance the
Aswang, and the most likely mistake here is incrementing `AswangKills` or decrementing `DealtInSurvivors`
"to keep the books straight", which is precisely what A1's three failed patches did and what that suite
now refuses. The direct evidence is the playtester's — a survivor quits, the round does not end, and the
Aswang's required kill count is unchanged.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — two new server-only tables that must never be sent.** `dealtIn` is a roster of who
  started; `leftDuringRound` is who has quit. Either alone is harmless; roster minus departures minus
  ghosts is the survivor count Amendment A3 just removed, and no check in this repo would see it.
- **The Aswang has no rejoin case, and BUILD-PLAN says so** — `onPlayerRemoving` aborts the round on a
  match, so a returning Aswang always lands in a round that has already ended. `RejoinResolve` would
  answer GHOST for them, which is harmless and unreachable. Worth not "fixing".
- **C11 must not double-handle the count** (BUILD-PLAN's third bullet, discharged): a disconnect already
  deletes the `PlayerStates` entry, so `livingSurvivorCount()` already treats a quitter as gone.
  GHOST-on-rejoin makes the returning body *consistent* with that; it does not change it. No count is
  adjusted anywhere in this phase.
- **`isRoundUnderway()` may become unused.** Check before deleting; `analyze` will say.
- **Player leaving mid-round** — this phase is entirely about that edge case, and it closes three of §6.4's
  five. The two it does not touch are the shutdown flush (C31) and dropping below `MinPlayers`, both
  deliberately unchanged.
- **Strict Luau** — `dealtIn[player.UserId] == true` rather than a bare truthiness test, because indexing
  a `{ [number]: boolean }` yields `boolean?` and `if dealtIn[id] then` typechecks while reading worse.
- **Ordering with Phase 6** — a returning GHOST is bodiless until Phase 6 lands. Not a regression (that
  is today's behaviour for any dead player) and either phase order leaves the game runnable.
- **Scope** — the husk is explicitly deferred, with reasons, in this phase's preamble and in Follow Ups.

---

### Phase 6: C15 — the ghost body, flight, and who can see it

A ghost needs a server-known position, because C16's contribution runs through `TaskService`'s existing
presence machinery, which measures from `player.Character`. That single requirement decides the whole
shape of this phase.

#### Step 6.1: Studio probe — flight and invisibility

**File:** `.claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/ghost-body-probe.md`
**Verify:** `test -f .claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/ghost-body-probe.md`

Four questions this plan will not guess the answers to, probed in a running place and written down
before Step 6.4 is coded against them.

**Why a probe rather than a plan.** Hard Rule 1: never guess a Roblox API's behaviour. This repo has
never made a character fly, never made one invisible to some clients and not others, and the C07
`ProximityPrompt` step is the precedent — that probe found that the CoreScript *refuses to render a prompt
with no keycode*, which invalidated the affordance the plan had specified and cost one step instead of one
chunk.

**The four questions, each with what the answer changes:**

1. **Does a `Humanoid` with `PlatformStand = true` and gravity removed hold a position, or does it fall?**
   The intended mechanism is a bodiless-feeling flight built on a real character, because C16 needs
   `player.Character` to exist for `TaskService`'s presence check to measure from. Record what actually
   holds a character in the air — `AlignPosition`, `LinearVelocity`, `BodyVelocity`, `Humanoid.Sit`, or
   setting `workspace.Gravity` per-part, which is not a thing. *If none of these is clean, the fallback is
   a character anchored to a client-driven CFrame, which costs server authority over ghost position and
   forces C16's contribution to be re-derived — flag it and stop.*

2. **Does `LocalTransparencyModifier` on another player's character parts work, client-side, for parts the
   client does not own?** This is the mechanism that lets a ghost see other ghosts while the living see
   nothing. *If it does not, ghosts get client-created proxy models driven by the roster, which is more
   code and a better design anyway.*

3. **Does setting `Transparency = 1` on every part server-side actually hide the name tag?** The
   `Humanoid`'s `DisplayName` billboard is rendered by a CoreScript and is not a part. Probe
   `Humanoid.DisplayDistanceType = None` and `NameDisplayDistance = 0`. *A floating name over an invisible
   ghost is the entire feature failing loudly, and it is the most likely thing to be missed.*

4. **Does a transparent, `CanCollide = false` character still block a raycast?** `MonsterService`'s
   line-of-sight check (`hasLineOfSight`, line ~554) excludes the corpse folder wholesale; ghosts are not
   in it. *A ghost that blocks line of sight is a ghost that can body-block a kill, which is a dead player
   affecting a living fight — the exact thing §4.7 is careful not to allow.*

**The artifact records the answer to each, verbatim console output, and a `screen_capture` from two
clients** — one living, one ghost, looking at the same place. That pair of screenshots is what C15's
"ghosts cannot be seen by the living" claim rests on, and neither client's view proves it alone.

Run through `execute_luau` against a live server; no `Script` or `LocalScript` is created inside Studio.

#### Step 6.2: `pure/BodyTransitions` — the GHOST row

**File:** `src/shared/pure/BodyTransitions.luau`
**Verify:** `lune run tests/body-transitions.test.luau`

`mayHaveBody` admits GHOST. **This is the module `applyBodyRule` actually calls**, and it is the one the
brief did not name — `pure/PlayerBody.mayHaveBody` is the twin, has the same body, is separately tested,
and is currently called by nothing. Both must change or the two disagree; Step 6.3 is the other half.

```diff
 -- LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
 -- also admits GHOST, and C15 makes GHOST real.
 function BodyTransitions.mayHaveBody(state: PlayerState): boolean
-	return state == "LOBBY" or state == "ALIVE"
+	return state == "LOBBY" or state == "ALIVE" or state == "GHOST"
 end
```

with the comment above it replaced, because it now says the opposite of what the code does:

```diff
-- LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
-- also admits GHOST, and C15 makes GHOST real.
+--[[
+	LOBBY, ALIVE and — since C15 — GHOST. STILL AN ALLOWLIST, never `~= "SPECTATOR"`, and the
+	distinction is now doing visible work rather than theoretical work: the two forms were
+	indistinguishable until this edit and are now genuinely different, because SPECTATOR is the only
+	state left that gets nothing.
+
+	GHOST GETS A BODY BECAUSE §4.7 NEEDS IT TO HAVE A POSITION, not because a ghost is alive. A ghost
+	flies (`Config.Ghost.FlySpeed`) and holds task points at 25% (`Config.Ghost.TaskContributionMult`),
+	and `TaskService` measures presence from `player.Character` — so a bodiless ghost cannot contribute,
+	which is the retention fix §4.7 exists to deliver.
+
+	THIS DOES NOT MAKE A GHOST KILLABLE. That is `pure/PlayerBody.mayBeKilled` and `KillValidation`,
+	both of which allowlist ALIVE alone. The two allowlists were deliberately separated at C05 for
+	exactly this moment; see PlayerBody's header, which predicted this edit and named the cell.
+]]
 function BodyTransitions.mayHaveBody(state: PlayerState): boolean
```

**What moves in the twenty-cell grid.** `actionFor` branches on `mayHaveBody` first, so all five GHOST
cells change at once:

| cause | before | after |
| --- | --- | --- |
| `JOINED` | REVOKE | **GRANT** — a returning dealt-in player (Step 5.4) gets a ghost body on arrival |
| `PHASE_CHANGE` | REVOKE | **GRANT** |
| `KILLED` | REVOKE | **REVOKE** — unchanged, and it must stay: the victim's character becomes the corpse |
| `DIED` | REVOKE | **GRANT** — the ghost body is loaded after the death |
| `LOAD_FAILED` | KEEP | **DEFER** — a ghost is now owed a body, so a failed load retries |

Two of those are the interesting ones. **`GHOST/KILLED` staying REVOKE is what stops two bodies existing**
— `MarkKilled` writes GHOST and *then* calls `applyBodyRule`, and `MonsterService.makeCorpse` has already
detached the character, so REVOKE finds nothing to destroy and the corpse survives. **`GHOST/DIED` becoming
GRANT is what actually spawns the ghost**, via the same path every other spawn goes through.

`tests/body-transitions.test.luau` enumerates all twenty cells, so this step's check fails until the
expectation table is updated with it — which is the point: the grid is the specification, and changing
the code without changing the grid is the failure mode this module was extracted to make impossible.

**One ordering hazard worth stating.** `MarkKilled` writes GHOST, then calls `applyBodyRule(player)` with
the default cause `PHASE_CHANGE` — which, after this edit, is **GRANT**. The corpse is already detached, so
the victim would be respawned as a ghost *immediately*, in the same frame the corpse is made. That may be
exactly right (the ghost appears at once) or may need the death to pass `"KILLED"` explicitly so the spawn
is deliberate rather than incidental. **Read `MarkKilled`'s call before implementing** — its comment at
line ~144 pins the convention that the state passed is the post-transition one — and if the cause needs to
change, that is a `RoundService` edit belonging to this step, not to Phase 5.

#### Step 6.3: `pure/PlayerBody` — the same row, and the row that must NOT move

**File:** `src/shared/pure/PlayerBody.luau`
**Verify:** `lune run tests/player-body.test.luau`

`mayHaveBody` admits GHOST; `mayBeKilled` does not, and the two staying different is what keeps a ghost
unkillable.

**This module predicted this edit and named the file it would happen in** (`PlayerBody.luau:33-39`):
*"C15 gives ghosts their own body and will change this row — in this file, with this test, which is the
point."* It is right, and the plan honours it.

```diff
 --[[
 	Whether the server should load a character for this player.
 
-	GHOST returns false and that is deliberate for C05 rather than final: a killed player's character
-	becomes the corpse (Step 4.2), so re-spawning them would put two bodies in the world. C15 gives
-	ghosts their own body and will change this row — in this file, with this test, which is the point.
+	GHOST RETURNS TRUE AS OF C15, and the reason the C05 comment gave for it being false has not gone
+	away — it has been answered somewhere else. The concern was two bodies: a killed player's character
+	becomes the corpse, so re-spawning them would leave a corpse and a live rig in the same place.
+	What resolves it is `pure/BodyTransitions`' GHOST/KILLED cell, which is REVOKE — the death path
+	takes the body, and the ghost body arrives on the next transition. The rule "may a ghost have a
+	body" and the rule "what happens to a ghost's body at the moment of death" are different questions,
+	and separating them is what let this row move without touching the corpse.
+
+	§4.7 IS WHY IT HAD TO MOVE. A ghost flies and holds task points at 25%, and `TaskService` measures
+	presence from `player.Character`. No character, no position, no contribution, and §4.7's retention
+	fix is a spectator camera with extra steps.
 ]]
 function PlayerBody.mayHaveBody(state: PlayerState): boolean
-	return state == "LOBBY" or state == "ALIVE"
+	return state == "LOBBY" or state == "ALIVE" or state == "GHOST"
 end
```

`mayBeKilled` is **unchanged**, and this file's header already explains why in a sentence that is now
doing real work rather than anticipatory work:

> *"Both are ALLOWLISTS. `state ~= "SPECTATOR"` reads identically today for either one and admits LOBBY
> and GHOST — and C15 makes GHOST real, at which point a dead player is killable again."*

That moment has arrived. A denylist in either function would now hand the Aswang a farmable target: kill
a ghost, and — depending on which path credited it — either increment `AswangKills` toward a win that
required no living victims, or simply produce a second corpse for a player who is already dead. Neither is
reachable, because both functions name the states they permit.

The test's expectation table changes in one cell and gains one property:

```diff
 local BODY: { [PlayerState]: boolean } = {
 	LOBBY = true, -- waiting between rounds, walking around the plaza
 	ALIVE = true, -- dealt into the round
-	GHOST = false, -- dead; their old character is the corpse (Step 4.2). C15 revisits this row.
+	GHOST = true, -- C15. Dead, but flying and holding task points at 25% — §4.7 needs a position.
 	SPECTATOR = false, -- joined mid-round. THE C04 REMNANT.
 }
```

```diff
+--[[
+	THE C15 PROPERTY, and the reason both functions exist separately.
+
+	A ghost now HAS a body and must still NOT be a kill target. Before C15 this was guaranteed
+	incidentally — no body, nothing to kill — and it is now guaranteed only by mayBeKilled's allowlist.
+	If someone merges these two functions, or rewrites either as `~= "SPECTATOR"`, this is the check
+	that fails.
+]]
+check(
+	"a ghost has a body and is still not killable",
+	PlayerBody.mayHaveBody("GHOST") and not PlayerBody.mayBeKilled("GHOST")
+)
```

The existing property at line 75 — *"the kill allowlist is strictly narrower than the body allowlist"* —
keeps passing and gets stronger: it is now narrower by two states rather than one.

`lune run tests/player-body.test.luau` is the check, distinct from Step 6.2's
`tests/body-transitions.test.luau`, and the two are genuinely different files proving different things.

#### Step 6.4: `GhostService` — embodiment, invisibility, flight

**File:** `src/server/Services/GhostService.luau`
**Verify:** `npm run analyze`

Subscribe to phase changes, own the ghost body's appearance and physics, and clean up on every exit.

**`RoundService` grants the body; `GhostService` dresses it.** That split is not arbitrary —
`applyBodyRule` is the single owner of `LoadCharacterAsync` and its comment counts its call sites
precisely because two owners of a player's body is how this file got its five patches. `GhostService`
watches `CharacterAdded`, asks `RoundService.GetPlayerState`, and if the answer is GHOST it makes the rig
a ghost. It never loads or destroys a character.

```diff
 --!strict
 --[[
 	GhostService — Dead players become contributing ghosts.
 
 	Milestone: M4
 	Spec: docs/MVP-SPEC.md
+
+	§4.7 IS THE RETENTION FIX, and §11 rates "dead players quit" as a 🟠 High risk with this system as
+	its only mitigation. The first person to die is otherwise bored for six minutes and leaves.
+
+	THIS SERVICE DOES NOT OWN BODIES. `RoundService.applyBodyRule` is the single owner of
+	LoadCharacterAsync in this game — read its header, which counts its six call sites and explains why
+	the count is written down. GhostService watches CharacterAdded, asks whose it is, and DRESSES it.
+	It never loads and never destroys.
+
+	WHAT "INVISIBLE TO THE LIVING" ACTUALLY MEANS HERE, stated honestly because the naive reading is
+	wrong: the server sets every part Transparency = 1, so no client renders the ghost. A GHOST client
+	then makes other ghosts visible again LOCALLY, off the roster it alone receives (Step 6.5).
+
+	A COMPROMISED LIVING CLIENT CAN STILL READ A GHOST'S POSITION off the replicated character, because
+	replication is not visibility and Roblox has no per-client instance filtering for a server-owned
+	model. That is a real limit and it is recorded rather than papered over. What it costs: a cheating
+	living player learns where dead players are hovering, which names no role and wins no round. What
+	would fix it: ghosts with no replicated character at all, and client-side proxy avatars driven
+	entirely by the roster — more code, and it breaks C16's presence measurement, which is why it is a
+	post-GATE-1 item rather than this chunk.
 ]]
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local AntiCheatService = require(script.Parent.AntiCheatService)
+local RoundService = require(script.Parent.RoundService)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
 
 local GhostService = {}
 
-- TODO(M4): convert dead survivors to ghosts (fly, ghost-only chat).
-- TODO(M4): ghosts progress tasks at Config.Ghost.TaskContributionMult.
-- SECURITY: ghosts must NOT be able to leak the Aswang identity to the living.
--           Use a separate chat channel, enforced server-side.
+--[[
+	Make this character a ghost's. Called from CharacterAdded when the owner's state is GHOST.
+
+	THE MECHANISM BELOW IS WHAT STEP 6.1's PROBE CONFIRMED. If the artifact says otherwise, the
+	artifact wins and this function changes — that is what the probe is for, and none of the four
+	questions is answered by guessing here.
+]]
+local function makeGhost(player: Player, character: Model)
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+
+	if humanoid == nil then
+		return
+	end
+
+	-- Probe question 3: the name billboard is a CoreScript render, not a part, so Transparency does
+	-- not touch it. A floating name over an invisible ghost is the whole feature failing loudly.
+	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
+	humanoid.NameDisplayDistance = 0
+	humanoid.HealthDisplayDistance = 0
+	humanoid.WalkSpeed = Config.Ghost.FlySpeed
+
+	for _, part in character:GetDescendants() do
+		if part:IsA("BasePart") then
+			part.Transparency = 1 -- config-ok: fully hidden is the mechanic, not a knob
+			part.CanCollide = false
+			-- Probe question 4: a ghost must not block MonsterService's line-of-sight raycast, or a
+			-- dead player can body-block a kill between two living ones.
+			part.CanQuery = false
+			part.CanTouch = false
+			part.Massless = true
+		elseif part:IsA("Decal") or part:IsA("Texture") then
+			part.Transparency = 1 -- config-ok: same
+		end
+	end
+
+	-- Flight. THE MECHANISM IS PROBE QUESTION 1 and this line is a placeholder for its answer, not a
+	-- claim: whatever holds a character in the air on this engine version goes here, applied to the
+	-- HumanoidRootPart and tracked so it can be destroyed with the character.
+end
+
+local function onCharacterAdded(player: Player, character: Model)
+	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Ghost then
+		return
+	end
+
+	makeGhost(player, character)
+end
```

with the lifecycle:

```diff
-function GhostService.Init() end
+function GhostService.Init()
+	table.clear(spooksUsed)
+end
 
-function GhostService.Start() end
+function GhostService.Start()
+	Players.PlayerAdded:Connect(function(player: Player)
+		player.CharacterAdded:Connect(function(character: Model)
+			onCharacterAdded(player, character)
+		end)
+
+		-- RoundService turns CharacterAutoLoads off and loads explicitly, so a character can already
+		-- exist by the time this runs on a live server. Same reasoning as MonsterService.onPlayerAdded.
+		local existing = player.Character
+
+		if existing ~= nil then
+			onCharacterAdded(player, existing)
+		end
+	end)
+
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	-- Connect first, then sweep. A player arriving in the window is handled twice and both handlers
+	-- are idempotent.
+	for _, player in Players:GetPlayers() do
+		-- ...same two steps as above
+	end
+end
```

**A ghost that is `ALIVE` again next round must stop being a ghost**, and this service must not be the
thing that remembers to undo it: `setAllPlayerStates(Lobby)` at INTERMISSION calls `applyBodyRule`, which
loads a **fresh character** for everyone — so the ghost rig is destroyed and replaced by an ordinary one
with no ghost properties on it. Nothing to revert, because nothing was mutated that outlives the rig.
That is the same property `MonsterService.revert` has to work hard for (it mutates a character that
survives), and it is free here.

`npm run analyze` is the check: `HumanoidDisplayDistanceType`, `CanQuery`, `Massless` and the
`Decal`/`Texture` branch are all API surface this repo has never touched, and a wrong member name on a
Roblox class is a typecheck error rather than a runtime one — which is precisely the class of mistake a
plan written from memory produces.

#### Step 6.5: `GhostRoster` — fired to ghosts, and only to ghosts

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

One new down-remote so a ghost client can render the other ghosts. It carries UserIds of dead players
and no role, and a living client never receives it.

**This is the only remote this plan adds**, and it is the one place `check:remotes` can fail for a real
reason: a client `WaitForChild`ing a name the server never declared hangs forever with no error, no
output and no stack trace, which is the failure this check exists for.

```diff
 	"TaskListAssigned",
 	"PlayerKilled",
 	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
 	"SaltEffect",
+	--[[
+		C15. FireClient to each GHOST only, carrying the UserIds of the other ghosts so a ghost client
+		can render them. NEVER FireAllClients, and never to a living player.
+
+		ITS SAFETY IS ITS AUDIENCE, NOT ITS PAYLOAD, which makes it the opposite of RoleAssigned and
+		worth reading twice. RoleAssigned may go to one player because its payload is one field about
+		that player. This carries a LIST OF WHO IS DEAD — which, subtracted from the roster, is the
+		live survivor count that Amendment A3 removed from the snapshot for being a death oracle.
+		Sending it to a living client would restore that oracle exactly, with better resolution.
+
+		So it is deliberately NOT on check-secrecy's REVEAL_ALLOWLIST: it carries no role, and it must
+		keep being scanned like any other remote. What no check can see is the recipient list, which is
+		why the state test lives at the fire site.
+	]]
+	"GhostRoster",
 	"RoundEnded", -- includes the reveal
```

and the sender, in `GhostService`:

```diff
+local rosterRemote = Remotes.Get("GhostRoster")
+
+--[[
+	Tell each ghost who the other ghosts are (§4.7, "sees other ghosts").
+
+	THE STATE TEST IS AT THE FIRE SITE AND MUST STAY THERE. Building the list and then looping
+	`Players:GetPlayers()` to send it is one keystroke from correct and would broadcast the death
+	roster to every living client — a stronger version of the oracle Amendment A3 just removed. There
+	is no check in this repo that would catch it: `FireClient(player, payload)` inside a loop over the
+	wrong list is textually identical to the right one.
+
+	One list, built once, sent to the members of that same list. The sender IS the audience, which is
+	the shape that makes the mistake above impossible rather than merely discouraged.
+]]
+local function broadcastRoster()
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return
+	end
+
+	local ghosts: { Player } = {}
+	local userIds: { number } = {}
+
+	for _, player in Players:GetPlayers() do
+		if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
+			table.insert(ghosts, player)
+			table.insert(userIds, player.UserId)
+		end
+	end
+
+	if #ghosts == 0 then
+		return
+	end
+
+	-- Typed local, not an inline table: FireClient takes `...any`, so an inline literal is checked
+	-- against nothing. See Types.GhostRosterPayload for the fields that must never appear.
+	local payload: Types.GhostRosterPayload = { UserIds = userIds }
+
+	for _, ghost in ghosts do
+		rosterRemote:FireClient(ghost, payload)
+	end
+end
```

driven from `Start()` on its own loop at `Config.Ghost.RosterInterval`, which `tests/config.test.luau`
pins at or above `Round.SnapshotInterval` so this cannot become a second, faster per-player send.

**The receiving controller** (a new `GhostController`, or `CameraFXController` if it stays this small)
makes the listed characters locally visible via probe question 2's mechanism, and **must not assume it
is a ghost because the remote arrived** — it is, but the client should still render off its own
`YourState`, because a controller that treats "I received this" as "I am dead" is a controller that
misbehaves the frame the server's audience logic is wrong.

`npm run check:remotes` is the check: it fails on a remote used but not declared *and* on one fired in the
wrong direction, and this step is the only place in the plan where either could happen.

#### Phase 6 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`GhostRoster`'s audience is the whole of its security, and no check can see an audience.** The state
  test is at the fire site and the sender is the audience for that reason. This is the single highest-value
  thing for `exploit-auditor` to read in the whole plan.
- **A compromised living client can read ghost positions off the replicated character.** Recorded in the
  service header, not fixed. It names no role and wins no round; the real fix (no replicated ghost
  character, client-side proxies) breaks C16's presence measurement and is a post-GATE-1 item.
- **Two `mayHaveBody` functions, and the brief named only one.** `pure/BodyTransitions.mayHaveBody` is the
  one `applyBodyRule` calls; `pure/PlayerBody.mayHaveBody` is currently called by nothing. Both change,
  both tests change, and leaving either behind means the repo states two different rules.
- **`MarkKilled` → `applyBodyRule(player)` now resolves to GRANT for a GHOST.** May spawn the ghost body in
  the same frame the corpse is made. Read before implementing; it may be correct, it may want an explicit
  `"KILLED"` cause. Called out in Step 6.2.
- **A ghost must not block `MonsterService`'s line-of-sight raycast** — `CanQuery = false`, and probe
  question 4 confirms it. A dead player body-blocking a live kill is §4.7's worst case.
- **Phase ownership** — `GhostService` subscribes to `PhaseChanged` and never writes a phase.
- **Player leaving mid-round** — a ghost disconnecting drops out of the roster on the next tick; nothing
  is retained.
- **Mobile budget** — one extra `FireClient` per ghost per `RosterInterval`, pinned no faster than the
  snapshot. The client-side visibility work is per-ghost per-roster, not per-frame.
- **Scope** — §3 lists "Ghost mode for dead players" as IN. Flight and visibility are §4.7's own bullets.

---

### Phase 7: C15 — ghost chat, which is a secrecy surface

A ghost naming the Aswang in a channel the living can read ends every round instantly. This is the only
part of C15 whose mechanism depends on Roblox API behaviour this repo has never used, so it is a late
phase with a spike in front of it.

#### Step 7.1: The `TextChatService` spike

**File:** `.claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/textchat-probe.md`
**Verify:** `test -f .claude/plans/feature-c13-c16-salt-ghosts-plan/artifacts/textchat-probe.md`

Five questions, answered in a running place, with the fallback that Step 7.4 takes if any answer is no.

**This repo has never used `TextChatService`.** Nothing in `src/` references it, `Chatted`, or a
`TextChannel`; `QuickChatController` is a nineteen-line stub and §4.5's wheel is C20's work. So every
sentence anyone could write about how ghost chat behaves would be recalled rather than observed, and this
is a surface where being wrong is not a bug — a ghost naming the Aswang in a channel the living can read
ends every round instantly, and it would do so silently, because nobody who is alive is going to report
"I received a message I should not have".

**The five questions, each with what the answer changes:**

1. **Does `TextChannel.ShouldDeliverCallback` run on the SERVER, once per (message, recipient) pair, and
   does returning `false` actually suppress delivery?** This is the whole design. *If it runs on the
   client, or is advisory, the entire TextChatService route is dead and Step 7.4 takes the fallback.*

2. **Can the server remove a player from `RBXGeneral` mid-session, and does a message they send then go
   nowhere rather than falling back to it?** Removing ghosts from the default channel is the mandatory
   half regardless of whether a ghost channel works — *a ghost who can still type in general is the
   failure, and it is the default state until something changes it.*

3. **Does `TextChatService.ChatVersion` need to be `TextChatService` rather than `LegacyChatService` in
   this place file, and is that a Studio property or a script-settable one?** *If it is not on the new
   version, none of the above exists and the fallback is the only route.*

4. **Does a `TextChannel` created at runtime replicate to clients, and does the default chat UI render a
   channel it was not told about?** *If not, ghost messages need a client-side window — which is a C18
   HUD task, not this chunk, and Step 7.4 must then ship only the mandatory half plus a remote.*

5. **What does `TextSource.CanSend = false` do to a player who tries anyway — silent drop, or an error the
   client sees?** *A visible error tells a ghost their message was blocked, which is fine; a visible error
   in the LIVING players' logs would be a signal that a ghost is talking, which is not.*

**The fallback, if any of 1–4 is no**, and it is written here so the spike has a landing place rather
than a dead end: a `RequestGhostChat` up-remote plus a `GhostChatBroadcast` down-remote, delivered by the
same `broadcastRoster` shape from Step 6.5 — build the ghost list, send only to its members, and the
sender is the audience. That costs two entries in `Remotes.luau`, one budget in
`Config.AntiCheat.Budgets`, one `Consume` call, **and Roblox text filtering, which
`TextChatService` would have provided for free and which is a policy requirement, not a nicety.**
`TextService:FilterStringAsync` is then mandatory and is itself an unverified API in this repo. Record
that cost in the artifact; do not discover it at implementation time.

**The artifact records each answer verbatim, with console output, and — for question 1 — the observed
callback signature.** Step 7.4 is coded against the artifact, not against this list.

#### Step 7.2: `src/shared/pure/GhostChat.luau` — the delivery predicate

**File:** `src/shared/pure/GhostChat.luau`
**Verify:** `npm run lint`

`(senderState, recipientState) -> boolean`. Sixteen cells, one rule, and no Roblox types anywhere in it.

**Why a pure module for what is arguably one comparison.** Because the rule is *not* one comparison, and
believing it is is how this ships broken. It is a two-sided rule over four states, and three of its
sixteen cells are decisions somebody has to make deliberately: a SPECTATOR is not a ghost and must not
read ghost chat; a LOBBY player between rounds is not a ghost either; and a ghost talking to a ghost must
work in every phase including ENDING, where the reveal is on screen and the round is over. Written as
`if sender == "GHOST" and recipient ~= "GHOST" then return false end` inside a delivery callback, those
three are invisible, untested, and each is a round-ending leak if wrong.

It is also the only part of ghost chat that is testable from a terminal at all. Everything else in this
phase is `TextChatService`, which Lune cannot see.

```luau
--!strict
--[[
	GhostChat — may this message reach this recipient? (§4.7, C15)

		(senderState, recipientState) -> boolean

	§4.7's last bullet: ghosts "cannot reveal the Aswang's identity to living players. Enforce
	server-side; ghost chat must be a separate channel."

	THE THREAT IS ONE SENTENCE FROM ONE DEAD PLAYER. A survivor is killed, watches the reverting
	monster from four studs away, and types a name. Every round after that is decided in its first
	minute, and the accusation game §4.5 is built on stops existing. There is no partial version of
	this failure and no recovery from it inside a round.

	A CLIENT-SIDE FILTER IS NOT A FILTER, which is why this module returns a decision the SERVER acts
	on. If the message reaches a living player's client and is hidden there, it has already been
	delivered — an exploiter reads it out of the message stream, and an honest player reads it the day
	a UI bug renders a hidden channel. The rule has to be applied before the send, on the server, or it
	is decoration.

	THE RULE, IN ONE LINE: a message from a GHOST reaches GHOSTS only. Everything else is ordinary
	chat and is not this module's business — it returns true and lets the caller decide, because
	general chat between living players is §4.5's problem and C20's chunk.

	WHY THE RECIPIENT'S STATE AND NOT "IS THIS THE GHOST CHANNEL": because channel membership is a
	second source of truth that can drift from PlayerStates. A player who dies mid-message, a spectator
	added to a channel by a bug, a ghost who was never removed from general — in each case the CHANNEL
	says one thing and the PLAYER STATE says another, and this rule follows the player state, which is
	the one `RoundService` owns.

	NO `script.Parent` REQUIRES. PlayerState is re-declared; Luau literal unions are structural.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

local GhostChat = {}

--[[
	THE SIXTEEN CELLS, as a grid rather than as a condition:

	              → LOBBY   ALIVE   GHOST   SPECTATOR
	  LOBBY          ✓        ✓       ✓         ✓
	  ALIVE          ✓        ✓       ✓         ✓
	  GHOST          ✗        ✗       ✓         ✗
	  SPECTATOR      ✓        ✓       ✓         ✓

	THE GHOST ROW IS THE ONLY ONE THAT REFUSES, and each of its three ✗ cells is a separate decision:

	  GHOST → ALIVE      the whole point. A dead player naming the monster to a live one.
	  GHOST → SPECTATOR  a spectator is NOT dead — they joined mid-round and are watching. Handing
	                     them ghost chat gives an alt account a feed from inside the round, which is
	                     the same exploit `RejoinResolve` closes from the other direction.
	  GHOST → LOBBY      unreachable during ACTIVE and written out anyway. If a stale state ever puts
	                     a LOBBY player on the server during a round, the safe answer is silence.

	THE GHOST COLUMN IS ALL ✓ AND THAT IS DELIBERATE. A living player's message reaches ghosts, and
	should: §4.7 wants the dead "playing with the living", and a ghost who can hear the survivors argue
	is a ghost still in the round. The information flows one way, which is exactly the asymmetry the
	design wants — the living cannot be told anything by the dead, and the dead can watch.
]]
function GhostChat.mayDeliver(senderState: PlayerState, recipientState: PlayerState): boolean
	if senderState ~= "GHOST" then
		return true
	end

	return recipientState == "GHOST"
end

--[[
	Should this player be in the ghost channel at all?

	Separate from `mayDeliver` on purpose, and both are needed. `mayDeliver` is the per-message rule
	the delivery callback applies; this is the per-player rule the membership sync applies. They agree
	today by construction and are enforced at different moments — a player who dies between the
	membership sync and the message is caught by the first, and a player whose channel membership was
	never updated is caught by the second.

	Two guards on one rule is not redundancy here: the failure of either one alone is a leak, and the
	cost of both is a string comparison.
]]
function GhostChat.isGhostChannelMember(state: PlayerState): boolean
	return state == "GHOST"
end

return GhostChat
```

`npm run lint` is the check for the same reason as Steps 2.3 and 5.1: `analyze` belongs to a later step in
this phase, and a new pure module with no caller has nothing stronger available until Step 7.3 exists.

#### Step 7.3: `tests/ghost-chat.test.luau` — the full grid

**File:** `tests/ghost-chat.test.luau`
**Verify:** `lune run tests/ghost-chat.test.luau`

Every `PlayerState × PlayerState` pair asserted, so a fifth state added later shows up as a hole rather
than as a delivered message.

```luau
--!strict
--[[
	The ghost chat delivery rule (§4.7, C15) — all sixteen sender × recipient pairs.

	THIS IS THE ONLY PART OF GHOST CHAT LUNE CAN SEE. Everything else in the phase is TextChatService,
	which has no existence outside Roblox — so this file is the whole of the terminal evidence that the
	rule is right, and the playtester's three-client screenshot is the whole of the evidence that the
	rule is APPLIED. Neither substitutes for the other and the plan claims both.

	The cell that ends rounds is GHOST → ALIVE. It is asserted as a cell, again as a named property,
	and a third time as a loop over every living-ish recipient — three times, because a rewrite that
	"simplifies" `mayDeliver` to `senderState == recipientState` passes the first two.
]]

local GhostChat = require("../src/shared/pure/GhostChat")

type PlayerState = GhostChat.PlayerState

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local ALL: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }

--------------------------------------------------------------------------------
-- All sixteen cells, stated
--------------------------------------------------------------------------------

local EXPECTED: { [PlayerState]: { [PlayerState]: boolean } } = {
	LOBBY = { LOBBY = true, ALIVE = true, GHOST = true, SPECTATOR = true },
	ALIVE = { LOBBY = true, ALIVE = true, GHOST = true, SPECTATOR = true },
	-- THE ONLY ROW THAT REFUSES. Three separate decisions; see GhostChat's grid comment.
	GHOST = { LOBBY = false, ALIVE = false, GHOST = true, SPECTATOR = false },
	SPECTATOR = { LOBBY = true, ALIVE = true, GHOST = true, SPECTATOR = true },
}

for _, sender in ALL do
	for _, recipient in ALL do
		local expected = EXPECTED[sender][recipient]

		check(
			`mayDeliver({sender} -> {recipient})`,
			GhostChat.mayDeliver(sender, recipient) == expected,
			`expected {expected}, got {GhostChat.mayDeliver(sender, recipient)}`
		)
	end
end

--------------------------------------------------------------------------------
-- The properties the cells exist to express
--------------------------------------------------------------------------------

-- THE ROUND-ENDING LEAK, named. A dead player naming the Aswang to a living one.
check("a ghost cannot speak to the living", not GhostChat.mayDeliver("GHOST", "ALIVE"))

-- Stated as a loop as well, so a rewrite that special-cases ALIVE and forgets the others fails here.
for _, recipient in ALL do
	if recipient ~= "GHOST" then
		check(
			`a ghost reaches no {recipient}`,
			not GhostChat.mayDeliver("GHOST", recipient),
			`recipient={recipient}`
		)
	end
end

-- A SPECTATOR IS NOT DEAD. They joined mid-round and are watching; ghost chat would give an alt
-- account a live feed from inside the round, which is the exploit RejoinResolve closes from the other
-- side. This is the cell most likely to be got wrong by someone thinking "not alive means dead".
check("a spectator is not a ghost", not GhostChat.mayDeliver("GHOST", "SPECTATOR"))

-- Ghosts talk to each other. §4.7 asks for a ghost-only chat, not for silence.
check("ghosts hear ghosts", GhostChat.mayDeliver("GHOST", "GHOST"))

-- THE ASYMMETRY IS THE DESIGN, and it must survive: information flows from the living to the dead and
-- never back. A rewrite to `sender == recipient` satisfies every check above this line and fails here.
check("the living reach ghosts", GhostChat.mayDeliver("ALIVE", "GHOST"))
check("the living reach each other", GhostChat.mayDeliver("ALIVE", "ALIVE"))

--------------------------------------------------------------------------------
-- Channel membership — the second guard, on the same rule
--------------------------------------------------------------------------------

for _, state in ALL do
	check(
		`isGhostChannelMember({state})`,
		GhostChat.isGhostChannelMember(state) == (state == "GHOST"),
		`state={state}`
	)
end

-- The two functions must agree: anyone who may RECEIVE a ghost message is exactly the set who belongs
-- in the channel. They are enforced at different moments and a drift between them is a leak.
for _, state in ALL do
	check(
		`membership and delivery agree for {state}`,
		GhostChat.isGhostChannelMember(state) == GhostChat.mayDeliver("GHOST", state)
	)
end

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  ghost-chat: 16 cells + 7 properties + 8 membership/agreement")
```

#### Step 7.4: `GhostService` — the channel, enforced on the server

**File:** `src/server/Services/GhostService.luau`
**Verify:** `npm run verify`

The ghost channel, the removal of ghosts from the general channel, and the delivery callback that calls
Step 7.2's predicate. No client-side filter anywhere.

### The enforcement, precisely — three layers, and each one alone is sufficient

The claim this step has to support is absolute: **no message from a ghost ever reaches a living player.**
An absolute claim resting on one mechanism is a claim resting on that mechanism having no bugs, so this
ships three, each of which would hold on its own. They are cheap — a callback, a membership sync, and a
removal — and the failure of any one is silent.

**Layer 1 — ghosts are not in the general channel.** On the transition to GHOST, the server removes that
player's `TextSource` from `RBXGeneral`. This is the **mandatory half regardless of anything the spike
found**: it is the default state that leaks, and it leaks the moment a player dies, with no code needed to
cause it. If the spike answered "no" to every other question, this alone still ships.

**Layer 2 — ghosts are in a channel the living are not in.** A `GhostChannel` `TextChannel`, membership
synced from `RoundService.GetPlayerState` via `GhostChat.isGhostChannelMember`, resynced on every phase
change and every death.

**Layer 3 — `ShouldDeliverCallback` refuses per message, per recipient.** Even inside the right channel,
every delivery consults `GhostChat.mayDeliver` against **live player state**, not against channel
membership. This is the layer that catches the window Layers 1 and 2 cannot: a player who dies *between*
the membership sync and the message.

```diff
+local TextChatService = game:GetService("TextChatService")
+
+local GhostChat = require(Shared.pure.GhostChat)
+
+local GHOST_CHANNEL_NAME = "GhostChannel"
+
+local ghostChannel: TextChannel? = nil
+
+--[[
+	Whose TextSource is this? TextSource's parent is the channel and its UserId names the speaker, so
+	resolving a message back to a PlayerState is a UserId lookup and nothing more.
+
+	IT RESOLVES THROUGH RoundService, NOT THROUGH CHANNEL MEMBERSHIP, and that is Layer 3's whole
+	value: membership is a cache of the player state and a cache can be stale. `RoundService` owns
+	PlayerStates; everything else asks it.
+]]
+local function stateOfUserId(userId: number): GhostChat.PlayerState
+	local player = Players:GetPlayerByUserId(userId)
+
+	if player == nil then
+		-- A speaker who has left. Refuse by returning the state whose row refuses everything a ghost
+		-- would be refused; there is nobody to deliver to and nobody to deliver from.
+		return "GHOST"
+	end
+
+	return RoundService.GetPlayerState(player) :: GhostChat.PlayerState
+end
+
+--[[
+	LAYER 3. Runs on the SERVER, once per (message, recipient) pair, and returning false suppresses
+	the delivery. Probe question 1 confirms all three of those clauses; if the artifact says otherwise
+	this function does not exist and the fallback in Step 7.1 ships instead.
+
+	IT CONSULTS THE PURE MODULE AND DECIDES NOTHING ITSELF. The rule is sixteen enumerated cells in
+	`pure/GhostChat` with a terminal test over all of them; this is the wiring that applies it.
+]]
+local function shouldDeliver(message: TextChatMessage, source: TextSource): boolean
+	local speakerId = message.TextSource
+
+	if speakerId == nil then
+		-- A system message with no author. Not a ghost, so not this rule's business.
+		return true
+	end
+
+	return GhostChat.mayDeliver(stateOfUserId(speakerId.UserId), stateOfUserId(source.UserId))
+end
+
+--[[
+	LAYERS 1 AND 2. Called on every phase change and on every death, because both are moments when a
+	player's state changed and their channel membership has not caught up yet.
+
+	THE REMOVAL FROM GENERAL IS THE HALF THAT MUST NEVER BE SKIPPED. A ghost left in RBXGeneral is a
+	ghost typing to seven living players, and it is the DEFAULT — it requires no bug to happen, only
+	the absence of this call.
+]]
+local function syncChannels()
+	local general = TextChatService:FindFirstChild("TextChannels")
+	local channel = ghostChannel
+
+	if channel == nil then
+		return
+	end
+
+	for _, player in Players:GetPlayers() do
+		local state = RoundService.GetPlayerState(player) :: GhostChat.PlayerState
+		local belongs = GhostChat.isGhostChannelMember(state)
+
+		-- ...add or remove this player's TextSource from `channel`, and remove them from the general
+		-- channel when `belongs` is true. The exact API calls come from Step 7.1's artifact.
+	end
+end
```

### What happens to a LIVING player's message while ghosts exist

Nothing changes for them, and that is a deliberate answer rather than an omission. A living player types
in `RBXGeneral`, it reaches every living player, **and it reaches ghosts too** — because ghosts are still
receivers on that channel even after being removed as *senders* from it, and `GhostChat.mayDeliver`'s
whole ALIVE row is `true`.

That asymmetry is §4.7's design, not a compromise: *"it keeps them playing with the living."* A ghost who
can hear the survivors accuse each other is still in the round; a ghost who hears silence has been given a
spectator camera and will leave, which is the retention leak §11 rates 🟠 High and this system exists to
close.

The implementation consequence is worth stating because it is easy to get backwards: **a ghost is removed
from general as a SENDER and retained as a RECEIVER.** If the API only supports whole membership, Layer 3
carries the difference — ghosts stay in general, `CanSend = false` on their `TextSource` there, and
`shouldDeliver` refuses their messages anyway. Probe question 5 asks what a refused send looks like, and
its answer decides which of those two shapes ships.

### What the check does and does not prove

`npm run verify` is the check — the full gate, and the only step in this plan that uses it. It is the
right one here because this step's failure modes are spread across everything the narrower checks each see
a slice of: `analyze` catches a wrong member on `TextChannel`, `TextSource` or `TextChatMessage` (an API
this repo has never touched, where a typo is a typecheck error rather than a runtime one),
`check:secrecy` scans the new code for role tokens and attribute writes, `test:unit` runs Step 7.3's grid,
and `check:guards` proves the harness itself still holds.

**It does not prove the claim.** No mechanical check in this repo can observe a message failing to arrive
on a second client, and pretending otherwise would be exactly the "green check that proves nothing" this
plan is supposed to avoid. C15's own acceptance line says so and it is the strongest evidence available:

> *three clients, one dies, ghost sends a message, screenshot of the two living clients' chats **not**
> containing it. 🔒 mandatory — this is a secrecy surface, not just a chat feature.*

**Two negatives and a positive**, and the playtester must capture all three or the step is not done: the
two living chats without the message, and the *other ghost's* chat with it. A ghost channel that delivers
to nobody passes the first two.

#### Phase 7 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **This phase's central claim has no mechanical proof and must not be given a fake one.** `verify` proves
  the code typechecks and the grid holds; only three clients and two screenshots prove no message arrived.
- **Removal from the general channel is the half that leaks by DEFAULT.** Layers 2 and 3 require a bug to
  fail; Layer 1 requires only the absence of a call. Ship it even if the spike kills everything else.
- **A player who dies mid-message** falls between the membership sync and the send. Layer 3 catches it
  because it reads live `PlayerStates` rather than channel membership.
- **`TextChatService` is entirely unverified in this repo.** Five questions, one artifact, and a costed
  fallback that pulls in `TextService:FilterStringAsync` — itself unverified, and a policy requirement
  rather than a nicety, because the fallback loses Roblox's automatic filtering.
- **The fallback adds two remotes and a budget** (`RequestGhostChat` up, `GhostChatBroadcast` down), which
  changes `check:remotes`, `check:ratelimit` and `tests/anti-cheat-budgets.test.luau` at once. If the spike
  forces it, this phase grows by roughly two steps — flag it rather than absorbing it silently.
- **A spectator is not a ghost**, and "not alive means dead" is the reasoning that would give an alt
  account a live feed from inside the round. One cell, asserted twice.
- **Rate limiting** — no `OnServerEvent` handler in the TextChatService route. The fallback adds one and it
  would need `Consume` first, inline, like every other handler.
- **Scope** — §4.7 asks for exactly this. Nothing here approaches §4.5's quick-chat wheel, which is C20.

---

### Phase 8: C16 — contribution at 25%, and one spook per round

The contribution half is nearly free and the repo already says so: `TaskWeight.forPlayer` prices GHOST at
`Config.Ghost.TaskContributionMult` today, and `TaskService`'s own comment at line ~1020 names the two
gates that refuse a ghost as C15's work. This phase opens those two gates and adds the spook.

#### Step 8.1: `TaskService` — the two gates become ALIVE-and-GHOST allowlists

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run analyze`

`evaluatePresence` and `evaluateTimingStop` stop returning `NOT_ALIVE` for a ghost. `weightFor` already
supplies the 25%, and `TaskWeight`'s grid already forbids the weight varying by role.

**This is a two-line change and C07 wrote the note that says so**, which is the reason C16 is a Small
chunk sitting behind a Large one. `TaskService.luau:1019-1022`, in the comment above `evaluatePresence`:

> *"NOT_ALIVE is where C15 will change: §4.7 wants a GHOST to contribute at a reduced rate, so this line
> becomes an allowlist of ALIVE and GHOST and `weightFor` supplies the difference. Today a ghost is
> refused, which is correct for C08 and wrong for §4.7 — named here so it is found rather than
> rediscovered."*

Everything downstream is already built: `weightFor` (line ~531) calls
`TaskWeight.forPlayer(RoundService.GetPlayerState(player), role, Config.Ghost.TaskContributionMult)`, and
`TaskWeight` prices GHOST at `math.max(0, ghostMult)` today. The 25% has been wired since C08 and has
simply been unreachable, because no ghost could get past the gate to ask.

```diff
 	NOT_ALIVE is where C15 will change: §4.7 wants a GHOST to contribute at a reduced rate, so this line
 	becomes an allowlist of ALIVE and GHOST and `weightFor` supplies the difference. Today a ghost is
 	refused, which is correct for C08 and wrong for §4.7 — named here so it is found rather than
 	rediscovered.
+
+	C15/C16 DID EXACTLY THAT, and the note above is left in place because the shape it describes is now
+	the shape of the code. Two states pass: ALIVE at weight 1 and GHOST at Config.Ghost.
+	TaskContributionMult. LOBBY and SPECTATOR still refuse, and they refuse for different reasons that
+	must not be merged — a LOBBY player is between rounds, a SPECTATOR joined mid-round and is contained
+	on purpose (§6.4, and it is the alt-account case).
+
+	AN ALLOWLIST, NEVER `~= "SPECTATOR"`. That denylist reads identically for these two cells today and
+	admits LOBBY, which would let a player standing in the plaza during INTERMISSION... nothing, because
+	the phase gate above catches it. That is precisely the kind of "it happens to be safe" reasoning
+	that pure/PlayerBody's header refuses, and the phase gate is not a rule about who may contribute.
 ]]
 local function evaluatePresence(player: Player): (Types.TaskProgressVerdict, string?)
 	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
 		return "WRONG_PHASE", nil
 	end
 
-	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+	local playerState = RoundService.GetPlayerState(player)
+
+	if playerState ~= Enums.PlayerState.Alive and playerState ~= Enums.PlayerState.Ghost then
 		return "NOT_ALIVE", nil
 	end
```

and the identical change at `evaluateTimingStop` (line ~1097):

```diff
 local function evaluateTimingStop(player: Player): (Types.TimingVerdict, string?)
 	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
 		return "WRONG_PHASE", nil
 	end
 
-	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+	local playerState = RoundService.GetPlayerState(player)
+
+	if playerState ~= Enums.PlayerState.Alive and playerState ~= Enums.PlayerState.Ghost then
 		return "NOT_ALIVE", nil
 	end
```

**Both, not one.** §4.7 says a ghost may "hold a task point", and the four task types are one system with
two entry points — a ghost admitted to HOLD and refused at TIMING would be a ghost who can contribute to
three of this round's five tasks and is silently useless at the other two, which reads as a bug and is
unattributable.

**`TaskWeight` needs no change and must not get one.** Its header states the contract — *"For any given
PlayerState, the weight MUST NOT vary by Role"* — and its GHOST row was written at C08 specifically for
this moment: *"GHOST is C15's case and is priced in now because the max rule in `TaskProgress` makes it
free: a ghost alone is slow, a ghost beside a survivor changes nothing."*

**Two-person tasks are already settled and this step must not disturb them.** `Config.luau:180-183` records
it: a ghost weighs 0.25, `TwoPersonParticipants` is derived from `FullContributionWeight`, so two ghosts do
not open a two-person task. §4.4 says "2 survivors present" and §4.7 says ghosts "still matter", not that
they substitute. The arithmetic already delivers that and it delivers it because the count is derived from
the weights rather than restated — Amendment A2's own words.

`npm run analyze` is the check: `playerState` is now a local of type `Types.PlayerState`, compared against
two `Enums.PlayerState` fields whose `:: Types.PlayerState` casts are the load-bearing ones CLAUDE.md warns
about. A comparison against a bare string literal here infers as `string` and fails, which is exactly the
scaffold's original six errors.

#### Step 8.2: `tests/task-weight.test.luau` — the ghost row, asserted at both roles

**File:** `tests/task-weight.test.luau`
**Verify:** `lune run tests/task-weight.test.luau`

The grid already covers GHOST; this step makes the 25% assertion explicit rather than incidental, so a
future edit that prices a ghost by role fails a terminal test.

**The grid exists and passes today; what it does not yet assert is the NUMBER.** `tests/task-weight.test.luau`
enumerates all eight `PlayerState × Role` cells and proves the anti-oracle property — weight does not vary
by role. It proves the GHOST row equals `ghostMult` for whatever `ghostMult` it was handed. Until C16, no
test tied that to `Config.Ghost.TaskContributionMult`, because no ghost could reach the code.

```diff
+--------------------------------------------------------------------------------
+-- C16: the ghost's rate is Config's, and it is a REDUCTION
+--------------------------------------------------------------------------------
+
+--[[
+	§4.7: ghosts "hold a task point to add a small amount of progress (say 25% speed) — they still
+	matter". Two halves, and both are asserted, because each fails differently:
+
+	  · the RATE comes from Config and not from a literal here — otherwise M12 tunes
+	    Config.Ghost.TaskContributionMult and nothing moves, which is the silent failure
+	    check:config exists to prevent and which no check can see once the number is a test constant.
+	  · it is a REDUCTION and not zero. At zero a ghost is a spectator and §11's 🟠 High retention
+	    risk is unmitigated; at 1 dying is free. tests/config.test.luau pins the range; this pins
+	    that the FUNCTION honours it.
+]]
+local Config = require("../src/shared/Config")
+
+for _, role in ROLES do
+	check(
+		`a ghost contributes at Config.Ghost.TaskContributionMult as a {role}`,
+		TaskWeight.forPlayer("GHOST", role, Config.Ghost.TaskContributionMult)
+			== Config.Ghost.TaskContributionMult,
+		`got {TaskWeight.forPlayer("GHOST", role, Config.Ghost.TaskContributionMult)}`
+	)
+
+	check(
+		`a ghost contributes strictly less than the living as a {role}`,
+		TaskWeight.forPlayer("GHOST", role, Config.Ghost.TaskContributionMult)
+			< TaskWeight.forPlayer("ALIVE", role, Config.Ghost.TaskContributionMult),
+		`ghost={TaskWeight.forPlayer("GHOST", role, Config.Ghost.TaskContributionMult)}`
+	)
+
+	check(
+		`a ghost contributes more than nothing as a {role}`,
+		TaskWeight.forPlayer("GHOST", role, Config.Ghost.TaskContributionMult) > 0
+	)
+end
+
+--[[
+	TWO GHOSTS DO NOT OPEN A TWO-PERSON TASK (§4.4 + Amendment A2), asserted here rather than left to
+	Config's comment. `TwoPersonParticipants` is a count of FULL contributors and the count is derived
+	from these weights — so this is the arithmetic that makes Config.luau:180-183's claim true, and a
+	future ghostMult of 0.5 would break it silently in a two-ghost round nobody tests.
+]]
+check(
+	"two ghosts fall short of one full contributor",
+	2 * Config.Ghost.TaskContributionMult < Config.Tasks.FullContributionWeight * Config.Tasks.TwoPersonParticipants,
+	`2 x {Config.Ghost.TaskContributionMult} vs {Config.Tasks.TwoPersonParticipants} full`
+)
```

**Requiring `Config` from a `pure/` test is fine and is not the thing the no-`script.Parent` rule
forbids.** `tests/config.test.luau` already does it — Lune resolves by file path, and `Config.luau` is a
plain table with no Roblox datatypes precisely so that it can. What is forbidden is a *pure module*
requiring Config, because the module would then stop being callable with arbitrary inputs; the test may.

`lune run tests/task-weight.test.luau` is the check, distinct from every other Lune file this plan cites.

#### Step 8.3: `src/shared/pure/SpookBudget.luau` and its test

**File:** `src/shared/pure/SpookBudget.luau`
**Verify:** `lune run tests/spook-budget.test.luau`

`(phase, playerState, used, allowance) -> SpookVerdict`. The "second attempt refused" that C16's own
Verify line names becomes a terminal test rather than a playtest observation.

Two files in one step, because the module is twenty lines and its test is the deliverable — gating the
module on `lint` and the test on `lune` would be two steps for one idea.

```luau
--!strict
--[[
	SpookBudget — may this ghost spook right now? (§4.7, C16)

		(request) -> verdict

	§4.7: "Can trigger one spook per round (flicker a nearby light, rustle a bush) — no information,
	pure flavour, but it keeps them playing with the living."

	ONE PER ROUND IS THE WHOLE RULE AND IT IS A SCARCITY RULE, exactly like salt's carry limit. A ghost
	who can spook freely is a ghost with a signalling channel: flicker a light near the Aswang, repeat,
	and "no information" becomes a Morse code the living learn to read in one session. The budget is
	what keeps it flavour, and it is the reason this is a verdict rather than a boolean — the server
	logs WHY it refused, and a ghost hitting NO_SPOOKS_LEFT and a living player reaching NOT_GHOST are
	two very different lines in C41's log.

	IT TAKES NO ROLE AND MUST NEVER TAKE ONE. A spook that behaved differently for the dead Aswang —
	there is no such thing today, since the Aswang's death aborts the round — would be a role oracle
	readable by anyone standing near a flickering light.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau literal unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "NOT_GHOST" | "NO_SPOOKS_LEFT"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Used: number,
	Allowance: number,
}

local SpookBudget = {}

--[[
	ORDER IS FIXED: phase, then who you are, then what you have left. Same contract as every other
	verdict module here, and the same reason — the ordering decides which reason a log line carries.

	`NOTHING_IN_RANGE` is deliberately NOT here even though `Types.SpookVerdict` has it. That value is
	about the WORLD (is there a light near this ghost), it needs the DataModel to answer, and this
	module is the part that can be tested from a terminal. GhostService returns it after this function
	says OK. Splitting them that way is what keeps the budget testable at all.
]]
function SpookBudget.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	-- An allowlist of exactly one state. A living player has no spook button; a SPECTATOR must not
	-- acquire one by joining mid-round, which is the alt-account shape §6.4 keeps closing.
	if request.PlayerState ~= "GHOST" then
		return "NOT_GHOST"
	end

	--[[
		FAIL CLOSED ON THE ALLOWANCE, positive-and-finite, for the reason SaltCarry's limit does: a
		`SpooksPerRound` of `math.huge` passes every "is it a number" test and silently deletes the
		rule, and a negative one disables it. tests/config.test.luau pins the shipped value at >= 1;
		this refuses anything that arrives here broken regardless.
	]]
	if not (request.Allowance > 0 and request.Allowance < math.huge) then
		return "NO_SPOOKS_LEFT"
	end

	if request.Used >= request.Allowance then
		return "NO_SPOOKS_LEFT"
	end

	return "OK"
end

return SpookBudget
```

and the test, which is where C16's acceptance criterion lands:

```luau
--!strict
--[[
	The spook budget (§4.7, C16) — "one spook per round", as arithmetic.

	C16's own Verify line is "playtester as a ghost adds progress; second spook attempt refused". The
	second half of that sentence is a pure rule and is proven here; the first half needs a running
	place and is the playtester's.
]]

local Config = require("../src/shared/Config")
local SpookBudget = require("../src/shared/pure/SpookBudget")

type PlayerState = SpookBudget.PlayerState
type RoundPhase = SpookBudget.RoundPhase

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

local function request(overrides: {
	Phase: RoundPhase?,
	PlayerState: PlayerState?,
	Used: number?,
	Allowance: number?,
}): SpookBudget.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		PlayerState = overrides.PlayerState or "GHOST",
		Used = overrides.Used or 0,
		Allowance = overrides.Allowance or Config.Ghost.SpooksPerRound,
	}
end

-- Twenty cells: every phase against every state.
for _, phase in PHASES do
	for _, state in STATES do
		local expected: SpookBudget.Verdict = if phase ~= "ACTIVE"
			then "WRONG_PHASE"
			elseif state ~= "GHOST" then "NOT_GHOST"
			else "OK"

		check(
			`evaluate({phase}, {state})`,
			SpookBudget.evaluate(request({ Phase = phase, PlayerState = state })) == expected
		)
	end
end

--------------------------------------------------------------------------------
-- C16's acceptance criterion
--------------------------------------------------------------------------------

check("the first spook is allowed", SpookBudget.evaluate(request({ Used = 0 })) == "OK")
check(
	"the second is refused",
	SpookBudget.evaluate(request({ Used = Config.Ghost.SpooksPerRound })) == "NO_SPOOKS_LEFT"
)
check("over budget stays refused", SpookBudget.evaluate(request({ Used = 99 })) == "NO_SPOOKS_LEFT")

-- The allowance comes from Config, not from a literal here: M12 raising SpooksPerRound must move this
-- test's expectations with it, and a hardcoded 1 would keep passing while the game changed.
check(
	"the budget tracks Config rather than a constant",
	SpookBudget.evaluate(request({ Used = Config.Ghost.SpooksPerRound - 1 })) == "OK"
)

for _, allowance in { 0, -1, math.huge, 0 / 0 } do
	check(
		`an allowance of {allowance} refuses rather than disabling the rule`,
		SpookBudget.evaluate(request({ Allowance = allowance })) == "NO_SPOOKS_LEFT"
	)
end

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  spook-budget: 20 cells + 4 budget properties + 4 fail-closed")
```

#### Step 8.4: `GhostService` — the `RequestGhostSpook` handler

**File:** `src/server/Services/GhostService.luau`
**Verify:** `npm run check:ratelimit`

`Consume` first, the budget consulted, the effect chosen server-side and broadcast, and the counter
cleared per round. It carries no information, by design.

### "Carries no information" is a constraint on the CODE, not a description of the feature

§4.7 calls the spook "no information, pure flavour". That is easy to write and easy to violate, and the
violation is not in the payload — it is in **which thing flickers**. The naive implementation picks the
nearest light to the ghost, which makes every spook a beacon saying *a dead player is standing here*.
Living players learn to read it within one session, and a ghost trailing the Aswang then has a signalling
channel that §4.7's last bullet explicitly forbids.

Three rules make it flavour, and all three are about the *choice*, not the send:

1. **Pick uniformly at random from every candidate within `Config.Ghost.SpookRangeStuds`** (30 studs),
   never the nearest. `tests/config.test.luau` pins that range above both `Monster.KillRange` (8) and
   `Tasks.PresenceRangeStuds` (9), so the flickering object does not localise the ghost to anything a
   player could act on.
2. **The server chooses. The client names nothing** — `RequestGhostSpook` takes no arguments at all, which
   is `RequestTimingStop`'s design and its comment says why: *"there is no argument in which a client could
   name a moment, a position or an outcome."*
3. **The effect is identical regardless of who caused it.** No ghost-specific colour, no per-ghost
   variation, nothing a living player could correlate across two spooks.

```diff
+local SpookBudget = require(Shared.pure.SpookBudget)
+
+-- Spooks used this round, keyed by UserId. SERVER-ONLY, cleared on every phase change out of ACTIVE.
+local spooksUsed: { [number]: number } = {}
+
+local spookRng = Random.new()
+
+--[[
+	Pick something to flicker near this ghost — UNIFORMLY AT RANDOM among candidates in range, never
+	the nearest.
+
+	THE NEAREST-LIGHT IMPLEMENTATION IS THE BUG, and it is the one that will be written if this comment
+	is not here. A spook that always picks the closest object is a beacon: it says "a dead player is
+	standing within a few studs of this light", every time, repeatably. §4.7 says the spook carries no
+	information; that version carries a position.
+
+	Returns nil when nothing is in range, which is a legitimate outcome on a map with few lights and is
+	why Types.SpookVerdict has NOTHING_IN_RANGE. The budget is NOT spent in that case — a ghost who
+	presses the button in an empty field has not used their one spook.
+]]
+local function pickSpookTarget(root: BasePart): Instance?
+	local candidates: { Instance } = {}
+
+	for _, instance in workspace:GetDescendants() do
+		if not instance:IsA("Light") then
+			continue
+		end
+
+		local parent = instance.Parent
+
+		if parent == nil or not parent:IsA("BasePart") then
+			continue
+		end
+
+		if (parent.Position - root.Position).Magnitude <= Config.Ghost.SpookRangeStuds then
+			table.insert(candidates, instance)
+		end
+	end
+
+	if #candidates == 0 then
+		return nil
+	end
+
+	return candidates[spookRng:NextInteger(1, #candidates)]
+end
```

and the handler, in `Start()`, in the shape `MonsterService.luau:793-817` set and this plan has used twice:

```diff
+	--[[
+		THE RATE LIMIT IS INLINE AND FIRST, for the third time in this plan and for the reason
+		MonsterService's comment gives: `check-ratelimit.mjs` matches the Consume call within 1200
+		characters of the connect site, so a handler limited 200 lines away reads as unguarded.
+
+		NO ARGUMENTS, and that is the security design rather than a simplification. The server resolves
+		the ghost's position from their own character and picks the target itself; there is no argument
+		in which a client could name a light, a place or an outcome. RequestTimingStop established this
+		shape at C09.
+	]]
+	Remotes.Get("RequestGhostSpook").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestGhostSpook") then
+			return
+		end
+
+		local verdict = SpookBudget.evaluate({
+			Phase = RoundService.GetPhase(),
+			PlayerState = RoundService.GetPlayerState(player) :: SpookBudget.PlayerState,
+			Used = spooksUsed[player.UserId] or 0,
+			Allowance = Config.Ghost.SpooksPerRound,
+		})
+
+		-- NOTHING IS RETURNED TO THE CALLER on any path, including OK — the same rule as the kill, the
+		-- task and the throw. The ghost learns it worked because a light flickered.
+		if verdict ~= "OK" then
+			if Config.Debug.VerboseLogging then
+				print(`[GhostService] Spook refused for {player.UserId}: {verdict}`)
+			end
+
+			return
+		end
+
+		local character = player.Character
+		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+		if root == nil or not root:IsA("BasePart") then
+			return
+		end
+
+		local target = pickSpookTarget(root)
+
+		-- NOTHING_IN_RANGE: the budget is deliberately NOT spent. Pressing the button in an empty field
+		-- must not cost a ghost their one spook of the round.
+		if target == nil then
+			return
+		end
+
+		spooksUsed[player.UserId] = (spooksUsed[player.UserId] or 0) + 1
+
+		flicker(target)
+	end)
```

**`flicker` mutates the world rather than sending a remote**, and that is the cheapest correct answer: a
`Light`'s `Enabled` toggling replicates on its own, every client near it sees it, no client far from it
receives anything, and there is no payload to leak. It also means `check:secrecy` has nothing to inspect,
which is honest rather than convenient — there is genuinely nothing crossing the wire.

```diff
+-- A flicker, for Config.Ghost.SpookDuration, then back. Restores the CAPTURED state, not `true` —
+-- the same rule Step 4.1's stun follows, and for the same reason: a light that was off before the
+-- spook must be off after it, or C17's lighting pass gets silently rewritten by dead players.
+local function flicker(light: Light)
+	local wasEnabled = light.Enabled
+
+	task.spawn(function()
+		local deadline = os.clock() + Config.Ghost.SpookDuration
+
+		while os.clock() < deadline and light.Parent ~= nil do
+			light.Enabled = not light.Enabled
+			task.wait(0.12) -- config-ok: flicker cadence, a feel value tuned by eye at C34
+		end
+
+		if light.Parent ~= nil then
+			light.Enabled = wasEnabled
+		end
+	end)
+end
```

**The counter is cleared in `onPhaseChanged`** on every phase that is not ACTIVE, beside the ghost
teardown — "one per round" means the budget resets with the round, and a ghost carrying an exhausted
budget into the next round they die in would lose a feature to a bookkeeping bug nobody would trace.

`npm run check:ratelimit` is the check: this is the only new `OnServerEvent` handler in Phases 5–8, the
budget already exists at `Config.luau:375` (`{ Capacity = 2, RefillPerSecond = 0.05 }`, which is one spook
per twenty seconds sustained — far looser than the one-per-round the verdict enforces, which is the
direction Config's header requires), and an unguarded handler here is a free firehose into a `workspace`
descendants walk.

**§5's mobile budget deserves one line.** `workspace:GetDescendants()` on every spook is an O(instances)
walk on a phone-facing server; at one spook per ghost per round that is at most seven walks in seven
minutes, which is fine. If C17's greybox makes it slow, the fix is a `CollectionService` tag on
spookable objects — which is also a better interface for the map, and is noted in Follow Ups rather than
built now.

#### Phase 8 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **"Carries no information" is violated by picking the NEAREST light, not by the payload.** Uniform random
  within 30 studs is the rule; the nearest-light version is a beacon and is what will be written if the
  comment is missing.
- **`NOTHING_IN_RANGE` must not spend the budget.** A ghost pressing the button in an empty field losing
  their one spook of the round is a bug they cannot diagnose and will read as the feature being broken.
- **`flicker` must restore the CAPTURED state**, not `true`. C17's lighting pass would otherwise be
  silently rewritten by dead players, one light at a time, across a session.
- **Both task gates, not one.** A ghost admitted to HOLD and refused at TIMING is silently useless at two
  of five tasks.
- **`TaskWeight` needs no change and must not get one** — its role-blindness contract and its GHOST row
  were both written at C08 for this moment.
- **Two ghosts still do not open a two-person task**, and the arithmetic that guarantees it is now
  asserted rather than described in a Config comment.
- **`workspace:GetDescendants()` per spook** is fine at one-per-ghost-per-round and is the first thing to
  bite if C17's greybox is large. A `Spookable` tag is the fix; Follow Ups.
- **Rate limiting** — present and inline; the existing budget is far looser than the one-per-round rule,
  which is the correct direction.
- **Scope** — §4.7 asks for exactly the contribution and exactly one spook. Nothing here grows toward
  §3's OUT list.

---

## 3. Related Files

Everything this plan reads, writes or depends on. Files marked ✎ are edited by a step; the rest are read
for context or are the contracts this plan must not break.

### Rewritten from stubs

| File | Phases | What it becomes |
| --- | --- | --- |
| ✎ `src/server/Services/ItemService.luau` | 2, 3, 4 | Salt: discovery, spawn, pickup tick, throw handler, stun, reveal. ~18 lines → the whole C13/C14 surface |
| ✎ `src/server/Services/GhostService.luau` | 6, 7, 8 | Ghost body, roster, chat channel, spook. ~20 lines → the whole C15/C16 surface |

### Edited

| File | Phases | Why |
| --- | --- | --- |
| ✎ `src/shared/Config.luau` | 1 | Eight new knobs under `Salt` and `Ghost`. No existing value changes |
| ✎ `src/shared/Types.luau` | 1 | `AlivePlayerCount` removed; `SaltVerdict`, `SaltEffectPayload`, `GhostRosterPayload`, `SpookVerdict` added |
| ✎ `src/shared/Remotes.luau` | 6 | One entry: `GhostRoster` in `EVENTS_DOWN`. `RequestThrowSalt`, `SaltEffect` and `RequestGhostSpook` were already declared at C01 |
| ✎ `src/server/Services/RoundService.luau` | 1, 5 | Snapshot field removed; `dealtIn` and `leftDuringRound` tables; `onPlayerAdded` resolves through `RejoinResolve`; `onPlayerRemoving` records a disconnect |
| ✎ `src/server/Services/MonsterService.luau` | 1, 3 | `PlayerKilled` → `FireClient(victim)`; `IsTransformed` and `ForceRevert` exposed |
| ✎ `src/server/Services/TaskService.luau` | 8 | Two gates become ALIVE-and-GHOST allowlists |
| ✎ `src/shared/pure/BodyTransitions.luau` | 6 | `mayHaveBody` admits GHOST — five cells move |
| ✎ `src/shared/pure/PlayerBody.luau` | 6 | `mayHaveBody` admits GHOST; `mayBeKilled` deliberately unchanged |
| ✎ `src/client/init.client.luau` | 1 | Debug snapshot line loses the alive count |
| ✎ `src/client/Controllers/InputController.luau` | 4 | The throw bind |
| ✎ `src/client/Controllers/CameraFXController.luau` | 4, 6 | `SaltEffect` reception; ghost visibility off the roster |
| ✎ `docs/MVP-SPEC.md` | 1 | Amendment A3 in §4.7, version line to v1.2 |

### New

| File | Phase | Kind |
| --- | --- | --- |
| `src/shared/pure/SaltCarry.luau` + `tests/salt-carry.test.luau` | 2 | Carry limit |
| `src/shared/pure/SaltThrow.luau` + `tests/salt-throw.test.luau` | 3 | Hit resolution |
| `src/shared/pure/RejoinResolve.luau` + `tests/rejoin-resolve.test.luau` | 5 | Rejoin state |
| `src/shared/pure/GhostChat.luau` + `tests/ghost-chat.test.luau` | 7 | Delivery predicate |
| `src/shared/pure/SpookBudget.luau` + `tests/spook-budget.test.luau` | 8 | Spook budget |

### Read for context, not edited

| File | Why it mattered |
| --- | --- |
| `docs/BUILD-PLAN.md:344-423` | C13–C16's requirements, and the two decisions C15 was told to close |
| `docs/MVP-SPEC.md` §3, §4.6, §4.7, §5, §6.2, §6.4 | The source of truth for what to build and what not to |
| `src/server/pure/TaskPool.luau` | Reused wholesale by C13's discovery rather than copied |
| `src/server/pure/TaskWeight.luau` | Already prices GHOST at 25%; its role-blindness contract binds Phase 8 |
| `src/shared/pure/KillValidation.luau` | The verdict-ordering and fail-closed idiom every new pure module copies |
| `src/shared/pure/WinConditions.luau` | Amendment A1's rule, which Phase 5 must not disturb |
| `src/server/Services/AntiCheatService.luau` | `Consume(player, remoteName) -> boolean`, called first in every handler |
| `tests/config.test.luau` | The two salt relations already pinned, and the shape new ones follow |
| `.claude/plans/feature-c07-map-c08-hold-plan/` | The disposable-Studio-rig pattern Phases 2 and 6 copy |
| `.claude/scripts/check-secrecy.mjs` | The two-remote allowlist, and what its tripwires can and cannot see |
| `.claude/scripts/verify-plan.mjs` | The allowlisted commands and the shared-check rule this plan is graded by |

---

## 4. Follow Ups

### Questions / Clarifications

**1. The disconnect husk — proposed as its own chunk, after C19.** Decision 2's stronger option, deferred
with reasons. On disconnect during `ACTIVE`, detach the character and leave it standing; re-attach a
returning player as `ALIVE` at that position within a window; if the Aswang kills the husk meanwhile, they
return as `GHOST` with a corpse where they stood. Quitting then gains nothing and costs nothing, which is
the only version where the *decision* to quit is neutral rather than merely unattractive.

The cost table in Phase 5's preamble is the justification for deferring it: a `Config.Round.HuskWindow`
that only a playtest with real disconnects can set (Roblox rejoin latency is realistically 15–40s, and the
returning player may not even land on the same server); win-condition counting that Amendment A1's three
failed patches never had to consider; and a body with no connected `Player`, which is a fifth
`PlayerState` in all but name rippling through four pure modules and their tests. **After C19** is the
right moment because GATE 1's notes will say whether anyone actually rage-quits, and the window can then be
set from observed behaviour instead of guessed.

**2. C18's HUD has a survivor-count-shaped hole and must not fill it with a number.** Amendment A3 removes
the only data source BUILD-PLAN ~line 456 had for its "alive count" element. The names to refuse are in
`Types.luau`: `SurvivorsRemaining`, `DeadCount`, `RosterSize`, or any roster field a client can count.
If C19's playtest says players are lost without it, the answer to reach for is *diegetic and
latency-bearing* — a tally the quick-chat wheel can assert, a board in the plaza someone has to walk to —
and that is a GATE 1 design decision, not a field.

**3. The out-of-cadence snapshot push in `MarkKilled` is a residual timing signal.** Its *contents* no
longer differ for a bystander after Phase 1, so it is far weaker than the field it replaces — but a client
measuring the interval between its own snapshots still sees one arrive early. Removing it would delay the
victim's own death screen by up to `SnapshotInterval`. Left as-is deliberately; worth a look from
`exploit-auditor` and worth revisiting if C41 ever wants a jittered snapshot cadence anyway.

**4. Does the stun capture the transformed WalkSpeed, or the reverted one?** Step 4.1 captures *before*
`ForceRevert`, so a salted Aswang finishes the stun moving at transformed speed for the rest of the reveal.
One line either way. This is an M12 balance question and neither answer is obviously right without a
playtest — flagged rather than decided.

**5. If the `TextChatService` spike fails, Phase 7 grows by roughly two steps.** The fallback
(`RequestGhostChat` + `GhostChatBroadcast`) adds two remotes, one budget, one `Consume`, and — the part
that is easy to miss — **`TextService:FilterStringAsync`, which `TextChatService` provides for free and
which is a policy requirement rather than a nicety.** That API is itself unverified in this repo. Step 7.1
records the cost in its artifact; do not discover it at implementation time.

**6. A `Spookable` CollectionService tag would be a better map interface than `workspace:GetDescendants()`.**
Fine at one spook per ghost per round; the first thing to bite if C17's greybox is large. It would also let
C17 decide what is spookable (a bush, a lantern, a chicken) rather than the code assuming "anything with a
`Light`". Not built now.

**7. If C18's HUD needs an authoritative salt count, it is a new remote and not a second meaning on
`SaltEffect`.** Step 4.3 declines to fire a private per-player payload on a broadcast remote, because two
sends with different shapes on one remote is how `check:secrecy`'s field allowlist stops being able to
describe it.

**8. Eight phases fills the task loop's cap exactly.** `task-driver.mjs` drives roughly one phase per
iteration and caps at 8, so a single `/build` run has no slack for a repair loop. **Recommend two runs:
Phases 1–4 (C13/C14), then Phases 5–8 (C15/C16).** The split is clean — nothing in Phases 5–8 reads salt
state, and nothing in 1–4 reads ghost state.

**9. Phase ordering between 5 and 6 is flexible and both orders leave the game runnable.** Land 5 first and
a returning player is a bodiless GHOST for one phase, which is today's behaviour for any dead player and
therefore not a regression.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 1 | `PlayerKilled` is `FireAllClients` with a victim and a position — a stronger death oracle than the `AlivePlayerCount` field it sits beside. Dropping the field alone would be theatre | **Critical** | Fixed in Step 1.5 |
| 1 | `Types.PlayerKilledPayload`'s defence of `Position` ("the corpse replicates anyway") is false under §5's `StreamingEnabled` | High | Fixed in Step 1.5's replacement comment |
| 1 | Amendment A3 removes C18's only data source for its planned alive-count HUD element | Medium | Recorded, Follow Up 2 |
| 2 | `ItemService` has no `rgb()` helper; Step 2.5's snippet calls one | Low | Copy `MonsterService.luau:133` with its waiver |
| 2 | A pouch spawned inside greybox geometry is unreachable; the `+1 stud` offset is a guess about pad height | Medium | C17 interface; tag contract stated in Step 2.1 |
| 3 | Splitting `MISS` into distinct geometric verdicts would make salt a role detector for the price of one pouch | **Critical** | Prevented by design; asserted in `tests/salt-throw.test.luau` |
| 3 | `MonsterService.IsTransformed` is a new public query on a 🔒 surface | Medium | Answers about a public FORM, never enumerates. `exploit-auditor` at implementation |
| 4 | A reveal glow surviving into `INTERMISSION` marks a player in the next round's lobby | **Critical** | Fixed: `clearAllEffects` on every non-ACTIVE phase |
| 4 | `Highlight.DepthMode = AlwaysOnTop` would render the reveal through walls — a ten-second wallhack | High | Fixed: `Occluded`, stated explicitly |
| 4 | A target killed mid-stun leaves a **glowing corpse** — an accidental "this corpse is the monster" signal | Medium | Only reachable via reset or fall (the Aswang cannot be killed). Guard in `clearReveal` |
| 5 | `SPECTATOR`-on-rejoin makes a returning survivor uncounted AND unkillable — a hard counter to the entire monster | **Critical** | Fixed in Step 5.4 |
| 5 | `dealtIn` cannot live in `PlayerStates` (`setAllPlayerStates` opens with `table.clear`) nor be derived at read time (`onPlayerRemoving` deletes the entry) | High | Its own table, Step 5.3 |
| 5 | `dealtIn` and `leftDuringRound` are together a survivor count — the oracle A3 just removed | High | Server-only, never sent; warned in both declarations |
| 6 | **Two** `mayHaveBody` functions exist (`BodyTransitions` and `PlayerBody`); the brief named one. Changing either alone leaves the repo stating two rules | High | Both changed, Steps 6.2 and 6.3 |
| 6 | `MarkKilled`'s `applyBodyRule(player)` now resolves to GRANT for a GHOST — may spawn the ghost body in the same frame the corpse is made | Medium | Read before implementing; may want an explicit `"KILLED"` cause |
| 6 | A ghost blocking `MonsterService`'s line-of-sight raycast would let a dead player body-block a live kill | High | `CanQuery = false`; probe question 4 |
| 6 | A compromised living client can read ghost positions off the replicated character | Low | Recorded honestly; names no role, wins no round. Real fix breaks C16's presence measurement |
| 6 | `GhostRoster`'s safety is its audience, and no check in this repo can see an audience | High | State test at the fire site; sender IS the audience |
| 7 | A ghost left in `RBXGeneral` is the **default** state and leaks with no bug required | **Critical** | Layer 1, mandatory regardless of what the spike finds |
| 7 | A player who dies between the membership sync and their message | High | Layer 3 reads live `PlayerStates`, not channel membership |
| 7 | A `SPECTATOR` given ghost chat is an alt account with a live feed from inside the round | High | One cell, asserted twice |
| 7 | `TextChatService` is entirely unverified in this repo; the whole phase is coded against a spike | High | Step 7.1; costed fallback recorded |
| 8 | Picking the **nearest** light makes every spook a beacon saying "a dead player is here" | High | Uniform random within `SpookRangeStuds`, stated in the code comment |
| 8 | `NOTHING_IN_RANGE` spending the budget would cost a ghost their one spook for pressing a button in an empty field | Medium | Budget spent only after a target is found |
| 8 | `flicker` restoring `true` rather than the captured state would silently rewrite C17's lighting pass | Medium | Captures `wasEnabled` |
| 8 | Admitting a ghost to `evaluatePresence` but not `evaluateTimingStop` makes them silently useless at two of five tasks | Medium | Both changed |
