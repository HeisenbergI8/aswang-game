# Plan: C05–C07 — the kill, the Aswang's win, and the task draw

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M2 (C05, C06) and M3 (C07, pure half), plus one carried-over C04 remnant
- **Description:** Six phases. Phase 1 closes C04's deferred spectator-body finding before a kill
  exists. Phases 2–4 build C05 — `RequestKill`, six server-side conditions, the corpse, and a
  `PlayerKilled` broadcast that never names the killer. Phase 5 builds C06's attrition win as a pure
  predicate. Phase 6 builds only the pure half of C07: `TaskSelection` and its Lune test.
- **Date:** 2026-08-11
- **What the client is told:** two new facts, both already public in the world.
  1. `PlayerKilled` — `{ VictimUserId, Position }`. The victim's character is gone and a corpse model
     is standing at that position; both replicate on their own. The payload states nothing a client
     could not read off the workspace one frame later. **It does not carry the killer, in any form —
     not a UserId, not a name, not a distance, not a direction.**
  2. `RoundSnapshot.AlivePlayerCount` already exists and now moves when someone is killed. It was
     always going to; C01 built it that way.
  `ClientRoundSnapshot` gains **no** field. `RoundEnded` gains no field. `check-secrecy.mjs`'s
  `REVEAL_ALLOWLIST` is not touched.

### 1.1 What is deliberately NOT in this plan

- **C07's map half.** No CollectionService `TaskPoint` discovery, no `TaskService` selection wiring, no
  `ActiveTask` construction. `TaskPoint` appears **zero times** in `src/` today (checked), and the
  greybox that places those tags is C17. Building the discovery half now ships code whose only possible
  verification is "it found nothing, as expected", which is indistinguishable from broken. Phase 6
  builds the decision — the 5-of-12 draw — and stops at the boundary where the map begins.
- **No debug-only fake-victim harness**, and no test scaffolding of any kind inside game code. See §5.
- **No change to `check-secrecy.mjs`.** Phase 4 finds a real gap in it (§4, Issues Found row 2); the
  fix is a harness change with its own self-test obligations and belongs in its own chunk.
- **Nothing from spec §3's OUT list.** No second monster, no weapons, no meetings, no sabotage.

### 1.2 The two things this plan changes about existing behaviour

Both are called out here because a reader skimming phases will otherwise meet them as surprises.

1. **A player's character is no longer unconditionally theirs to keep.** Phase 1 makes `RoundService`
   the single owner of "may this player have a body", gating on `PlayerState`. This is what containment
   requires, and it is the same mechanism C15 needs for ghosts.
2. **A killed player becomes `GHOST`, not a fifth `PlayerState`.** `Types.PlayerState` has exactly four
   values and this plan adds none. `GHOST` means "was dealt in, is dead" — which is what §4.7 says it
   means — and C15 gives it flight, spooks and a chat channel. The immediate consequence is the one the
   C04 warning asked for: the kill's allowlist is `== ALIVE`, so a ghost is not killable.

## 2. Comprehensive Plan by Phases

### Phase 1: Spectator body containment (the C04 remnant)

C04 shipped the *rule* (`TransformRules` returns `NOT_ALIVE` for a spectator) and deferred the *body*.
The finding is row 7 of that plan's table, marked High and "Must be resolved before C05". This phase
resolves it, and it goes first because C05 is the chunk that makes it exploitable.

#### Step 1.1: Confirm in Studio whether a mid-round joiner actually spawns

**File:** `.claude/plans/feature-c05-c07-kill-win-taskselect-plan/artifacts/spectator-premise.md`
**Verify:** `test -f .claude/plans/feature-c05-c07-kill-win-taskselect-plan/artifacts/spectator-premise.md`

Establish the premise before building the fix. Nothing in `src/` prevents a spectator spawning, but the
place file is gitignored and a `SpawnLocation` property could already handle it. Record the outcome,
either way, as a file — that file is this step's deliverable.

**This step writes no game code.** It is the only step in the plan whose check is a `test -f`, and that
is honest rather than lazy: the deliverable genuinely is a written finding, and no command in this repo
can read a property out of a place file.

**The probe.** With `Config.Debug.SoloTesting = true` and a round in `ACTIVE`, run this through
`execute_luau` and record the output verbatim:

```luau
local Players = game:GetService("Players")

print("CharacterAutoLoads =", Players.CharacterAutoLoads)

for _, player in Players:GetPlayers() do
	print(player.Name, "Character =", player.Character, "state =", player:GetAttribute("PlayerState"))
end

for _, spawn in workspace:GetDescendants() do
	if spawn:IsA("SpawnLocation") then
		print("SpawnLocation", spawn:GetFullName(), "Enabled =", spawn.Enabled, "Neutral =", spawn.Neutral)
	end
end
```

`player:GetAttribute("PlayerState")` is expected to print `nil` for everyone — RoundService keeps player
state in a server-side table and deliberately does not attribute it (attributes replicate). It is in the
probe as a negative control: if it ever prints a value, that is a leak and it outranks this whole phase.

**Both branches have a stated outcome, and neither is "skip the phase":**

| Finding | What Steps 1.2–1.4 do |
| --- | --- |
| A mid-round joiner **does** get a character (expected) | Build the phase exactly as written. |
| A mid-round joiner **does not** get a character — the place file already handles it | Build the phase exactly as written **anyway**, and record in the artifact that the place file is doing it too. The place file is gitignored, one Studio session away from being wrong, and invisible to `git status`. A containment rule that lives only in a binary nobody can diff is not a containment rule. The code becomes belt-and-braces, which is the correct cost. |
| `Players.CharacterAutoLoads` already reads `false` | Step 1.4 keeps the line that sets it (idempotent, and it states the intent where a reader will look) and the artifact records that the place file agrees. |

#### Step 1.2: `src/shared/pure/PlayerBody.luau` — may this player have a body

**File:** `src/shared/pure/PlayerBody.luau`
**Verify:** `npm run analyze`

A four-value mapping from `PlayerState` to "spawn a character", written as an allowlist so that adding
a fifth state later is a compile-visible decision rather than a silent `false`.

```diff
+--!strict
+--[[
+	PlayerBody — may this player have a character right now.
+
+		(playerState) -> boolean
+
+	THE C04 REMNANT, AS A FUNCTION. C01 marks a mid-round joiner SPECTATOR and excludes them from the
+	alive count; it gives them no body, so they spawn, walk the Barrio and collide with it. That was
+	harmless until C05: once "both alive" gates the kill, an alt account joining mid-round is uncounted
+	AND unkillable, standing next to the Aswang taking notes.
+
+	TWO ALLOWLISTS, NOT ONE, AND THEY ARE DIFFERENT SETS. This is the part that is easy to get wrong.
+
+	  · mayHaveBody  — LOBBY and ALIVE. A player waiting in the lobby needs a body to walk around in.
+	  · mayBeKilled  — ALIVE, and nothing else. That is C05's "both alive" rule.
+
+	Both are ALLOWLISTS. `state ~= "SPECTATOR"` reads identically today for either one and admits LOBBY
+	and GHOST — and C15 makes GHOST real, at which point a dead player is killable again. PlayerState has
+	four values; each function names the ones it permits and returns false for everything else, so a
+	fifth value added later defaults to the safe answer and shows up in this file's test as a hole.
+
+	NO `script.Parent` REQUIRES. PlayerState is re-declared; Luau literal unions are structural, so this
+	type and `Types.PlayerState` are the same type and pass to each other without a cast.
+
+	This module is callable by any client and that is fine — it is a four-row lookup table over a value
+	the client already holds about itself (`ClientRoundSnapshot.YourState`). Logic is not secret.
+]]
+
+export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+
+local PlayerBody = {}
+
+--[[
+	Whether the server should load a character for this player.
+
+	GHOST returns false and that is deliberate for C05 rather than final: a killed player's character
+	becomes the corpse (Step 4.2), so re-spawning them would put two bodies in the world. C15 gives
+	ghosts their own body and will change this row — in this file, with this test, which is the point.
+]]
+function PlayerBody.mayHaveBody(state: PlayerState): boolean
+	return state == "LOBBY" or state == "ALIVE"
+end
+
+--[[
+	Whether this player may be the TARGET of a kill (§4.3, "both alive").
+
+	Strictly narrower than mayHaveBody, and the two must never be merged into one predicate. A LOBBY
+	player has a body and must not be killable; that is not an edge case, it is every player between
+	rounds standing in the plaza.
+]]
+function PlayerBody.mayBeKilled(state: PlayerState): boolean
+	return state == "ALIVE"
+end
+
+return PlayerBody
```

#### Step 1.3: `tests/player-body.test.luau` — all four states, exhaustively

**File:** `tests/player-body.test.luau`
**Verify:** `lune run tests/player-body.test.luau`

Four cases plus the property the C04 warning is actually about: the set of states that may hold a body
and the set that may be killed are both allowlists, and neither admits `SPECTATOR` or `GHOST`.

```diff
+--!strict
+--[[
+	The body rule and the kill-target rule, over all four player states.
+
+	Eight cells, written out in full. That is worth more than a spot check because the failure this
+	file exists to catch is a DENYLIST — `state ~= "SPECTATOR"` — which passes every spot check anyone
+	would think to write and fails exactly on the two rows nobody tests.
+]]
+
+local PlayerBody = require("../src/shared/pure/PlayerBody")
+
+type PlayerState = PlayerBody.PlayerState
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local ALL: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+
+--------------------------------------------------------------------------------
+-- mayHaveBody — every state, stated
+--------------------------------------------------------------------------------
+
+local BODY: { [PlayerState]: boolean } = {
+	LOBBY = true, -- waiting between rounds, walking around the plaza
+	ALIVE = true, -- dealt into the round
+	GHOST = false, -- dead; their old character is the corpse (Step 4.2). C15 revisits this row.
+	SPECTATOR = false, -- joined mid-round. THE C04 REMNANT.
+}
+
+for _, state in ALL do
+	check(
+		`mayHaveBody({state})`,
+		PlayerBody.mayHaveBody(state) == BODY[state],
+		`expected {BODY[state]}, got {PlayerBody.mayHaveBody(state)}`
+	)
+end
+
+--------------------------------------------------------------------------------
+-- mayBeKilled — §4.3's "both alive", as an allowlist of exactly one
+--------------------------------------------------------------------------------
+
+for _, state in ALL do
+	check(
+		`mayBeKilled({state})`,
+		PlayerBody.mayBeKilled(state) == (state == "ALIVE"),
+		`state={state}`
+	)
+end
+
+--------------------------------------------------------------------------------
+-- The properties the cells exist to express
+--------------------------------------------------------------------------------
+
+-- The C04 warning, verbatim: a mid-round joiner is uncounted, and must therefore also be bodiless and
+-- unkillable. Uncounted AND present is the alt-account exploit.
+check(
+	"a spectator has neither a body nor a kill target on it",
+	not PlayerBody.mayHaveBody("SPECTATOR") and not PlayerBody.mayBeKilled("SPECTATOR")
+)
+
+-- The row a denylist gets wrong. C15 makes GHOST real; a ghost that can be killed again is a ghost
+-- that can be farmed for kill credit.
+check("a ghost cannot be killed", not PlayerBody.mayBeKilled("GHOST"))
+
+-- mayBeKilled must stay strictly narrower than mayHaveBody. If they ever coincide, someone has merged
+-- them, and the LOBBY row is where that shows up: a lobby player has a body and is not a target.
+check(
+	"the kill allowlist is strictly narrower than the body allowlist",
+	PlayerBody.mayHaveBody("LOBBY") and not PlayerBody.mayBeKilled("LOBBY")
+)
+
+if failures > 0 then
+	error(`{failures} failure(s)`, 0)
+end
+
+print("  PASS  player-body: 8 cells + 3 properties")
```

#### Step 1.4: `RoundService` owns every character load

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run verify:fast`

`Players.CharacterAutoLoads = false`, and `RoundService` calls `LoadCharacter()` exactly when
`PlayerBody.mayHaveBody(state)` says so — on join, on every state change, and at every phase boundary
that changes states wholesale.

```diff
 local RoleService = require(script.Parent.RoleService)
+local PlayerBody = require(Shared.pure.PlayerBody)
 local RoundTransitions = require(Shared.pure.RoundTransitions)
 local Types = require(Shared.Types)
```

```diff
 function RoundService.GetPlayerState(player: Player): PlayerState
 	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
 end
+
+--[[
+	THE BODY RULE, applied. C04's carried-over warning from C01 (BUILD-PLAN lines ~203–219).
+
+	`Players.CharacterAutoLoads` is a SERVICE-level property, not a per-player one, so containment
+	cannot be expressed by "do not auto-load for this player". Turning it off globally and loading
+	explicitly is the only shape that admits a per-player rule at all, and it has the side benefit of
+	putting every spawn in this game through one function that a reader can find.
+
+	Called from four places, all in this file: on join, on the two wholesale state changes
+	(setAllPlayerStates), and on MarkKilled at Step 4.1. Idempotent in both directions — loading a
+	character for someone who has one is a respawn, which is why the `Character == nil` guard is load
+	bearing rather than an optimisation.
+]]
+local function applyBodyRule(player: Player)
+	local allowed = PlayerBody.mayHaveBody(RoundService.GetPlayerState(player))
+
+	if allowed then
+		if player.Character == nil then
+			player:LoadCharacter()
+		end
+
+		return
+	end
+
+	--[[
+		DETACH, THEN DESTROY, AND ONLY WHAT WE STILL OWN.
+
+		Step 4.2 takes a killed player's character AWAY from the player (`player.Character = nil`) and
+		keeps it in the workspace as the corpse. By the time MarkKilled reaches here, `player.Character`
+		is already nil, so this branch finds nothing and the corpse survives. That ordering is the whole
+		reason MarkKilled hands the body to MonsterService before it changes the state.
+	]]
+	local character = player.Character
+
+	player.Character = nil
+
+	if character ~= nil then
+		character:Destroy()
+	end
+end
```

```diff
 local function setAllPlayerStates(newState: PlayerState)
 	table.clear(state.PlayerStates)
 	for _, player in Players:GetPlayers() do
 		state.PlayerStates[player.UserId] = newState
 	end
+
+	-- After the whole table is written, not inside the loop: applyBodyRule reads GetPlayerState, and a
+	-- half-written table would answer LOBBY (the default) for everyone not yet assigned.
+	for _, player in Players:GetPlayers() do
+		applyBodyRule(player)
+	end
 end
```

```diff
 local function onPlayerAdded(player: Player)
 	-- Joined mid-round → spectator until the next round is drawn. Without this a late arrival is
 	-- indistinguishable from a survivor and would be counted alive by every win check from C06 on.
 	state.PlayerStates[player.UserId] = if isRoundUnderway()
 		then Enums.PlayerState.Spectator
 		else Enums.PlayerState.Lobby
 
+	-- The other half of that sentence, and the half C01 left out. A SPECTATOR with a body is uncounted
+	-- AND, from C05 on, unkillable — an alt account that watches the whole round from ten studs away.
+	applyBodyRule(player)
+
 	snapshotRemote:FireClient(player, buildSnapshot(player))
 end
```

```diff
 function RoundService.Start()
+	--[[
+		BEFORE any PlayerAdded connection, and before the backfill loop below.
+
+		Roblox loads a character as soon as a player joins while this is true, so a connection made after
+		the flag is flipped can still be racing a spawn that has already been requested. Setting it here,
+		at the top of Start(), is the earliest point this service runs. Step 1.1's Studio probe is what
+		confirms the flag is actually respected in this place file rather than overridden by it.
+	]]
+	Players.CharacterAutoLoads = false
+
 	-- ORDER MATTERS. init.server.luau wraps Start() in a pcall that only warns, so anything throwing
 	-- part-way through leaves a server with whatever had been registered so far — and a server with
 	-- no tick loop, no snapshot loop and no close handler sits in IDLE forever behind one warn line,
 	-- which looks exactly like "nobody has joined yet". Connections and loops go first; the player
 	-- backfill, which is the part that touches remotes and could throw, goes last.
 	Players.PlayerAdded:Connect(onPlayerAdded)
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read?
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`Players.CharacterAutoLoads = false` is the highest-risk line in this plan.** If it does not behave
  as expected in this place file, nobody spawns and the game is unplayable in the most obvious possible
  way — which is the good failure mode, because it is immediate and total rather than subtle. It is
  still an unverified Roblox behaviour in this repo; Step 1.1 exists to look at it first, and it is in
  Follow Ups.
- **A LOBBY player has a body and is not killable, and those are different predicates.** Merging them
  is the natural simplification and it is wrong. Step 1.3 pins the LOBBY row precisely to catch it.
- **`applyBodyRule` destroys a character.** The one case where that would destroy something we no
  longer own is the corpse, and the ordering in Step 4.1 (`player.Character = nil` before the state
  changes) is what prevents it. If those two steps are implemented out of order the corpse vanishes
  instantly and the bug looks like "the corpse code does not work".
- **Respawn on state change is a teleport.** `LoadCharacter()` puts the player at a SpawnLocation, so a
  LOBBY→ALIVE transition relocates everyone — which is what `Round.StartingDelay` ("role assignment +
  teleport fade", `Config.luau` line 16) already budgets for. It is a behaviour change for players who
  were mid-walk when INTERMISSION ended, and it is the intended one.
- **§6.4 edge cases that apply:** "a player joins mid-round → spectator until ENDING" is the whole
  phase. "The Aswang leaves mid-round" is untouched. The others belong to Phases 4 and 5.
- **Mobile budget:** no lights, no particles, no per-frame work. `applyBodyRule` runs on join and on
  state changes only.

### Phase 2: Foundation — the tunables, the invariants, and the kill's types

Numbers and types only, so no later phase has to add a `Config` key mid-flight and `check:config` is
satisfiable from the first line of Phase 4's service code. `Remotes.luau` needs **no** change: both
`RequestKill` (UP) and `PlayerKilled` (DOWN) are already declared, and `Config.AntiCheat.Budgets`
already carries `RequestKill = { Capacity = 3, RefillPerSecond = 0.25 }`.

#### Step 2.1: Three new `Config` keys and four new balance invariants

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

`Round.AswangWinSurvivorThreshold`, `Monster.CorpseFadeTime`, `Tasks.MinSpacingStuds`, each pinned by a
relationship in `tests/config.test.luau` rather than by its value. Count goes 21 → 25.

**Already present, and deliberately not re-added:** `Monster.KillRange = 8`, `Monster.KillCooldown = 30`
and `Monster.CorpseDuration = 45` have been in `Config.luau` since the scaffold (lines 55–59), and
`Salt.ThrowRange > Monster.KillRange` is already invariant #7 in `tests/config.test.luau`. C05 reads
those three; it does not introduce them.

```diff
 	Round = {
 		Intermission = 25, -- seconds in lobby before a round starts
 		Duration = 420, -- 7 minutes of "night" before sunrise
 		EndScreen = 12, -- reveal + stats screen
 		StartingDelay = 4, -- role assignment + teleport fade
 		MinPlayers = 3, -- MUST be playable at this count (see spec §9 cold start)
 		MaxPlayers = 8,
+
+		--[[
+			§4.8: "Aswang wins when living survivors ≤ 2". THE NUMBER IS NOT THE WHOLE RULE.
+
+			Read literally against MinPlayers = 3, this fires on tick one of every minimum-size round:
+			three players is one Aswang and two survivors, and two is already ≤ 2. `pure/WinConditions`
+			(Phase 5) clamps the effective threshold by how many survivors were DEALT IN, which is what
+			makes the rule mean "two thirds of them are dead" instead of "the round is small".
+
+			So this knob is the ceiling on the threshold, not the threshold itself. Tune it at M12
+			against 6–8 player rounds, which is the size it actually governs.
+		]]
+		AswangWinSurvivorThreshold = 2,
+
 		-- How often the server pushes a RoundSnapshot to each client. This is a network cost paid
```

```diff
 		KillRange = 8, -- studs
 		KillCooldown = 30, -- seconds after revert
 		TransformedSpeedMult = 1.25,
 		TransformAudioRange = 40, -- how far the transform sound carries
 		CorpseDuration = 45,
+		-- How long the corpse takes to fade once CorpseDuration is up. Long enough that a survivor
+		-- walking in on the tail of it still registers a body was there; short enough that it is not a
+		-- second, softer corpse with its own lifetime. §4.9: a fade, not a gore effect.
+		CorpseFadeTime = 1.5,
```

```diff
 	Tasks = {
 		TotalRequired = 5, -- how many must be completed to open the gate
 		PoolSize = 12, -- how many possible spawn points exist on the map
 		HoldTime = 8,
 		TimingAttempts = 3,
 		FetchTime = 25,
 		TwoPersonTime = 12,
+
+		--[[
+			The minimum distance between two SELECTED task points (§4.4, "spread"). C07's draw honours it
+			when the pool carries positions and ignores it when it does not.
+
+			It must exceed Monster.KillRange or the spread does nothing that matters: two task points
+			closer together than the Aswang's reach are one ambush spot, and §4.4's whole purpose is to
+			stop players (and the monster) memorising a route. tests/config.test.luau pins that.
+		]]
+		MinSpacingStuds = 20,
 	},
```

```diff
 check(
 	"a round is long enough to actually be played",
 	Config.Round.Duration >= 300,
 	`Duration={Config.Round.Duration}s — a testing value left in?`
 )
 
+--------------------------------------------------------------------------------
+-- C05 / C06 / C07 (this plan)
+--------------------------------------------------------------------------------
+
+-- Spec §4.8. On a FULL server the attrition rule must still be a rule: a threshold at or above the
+-- survivor count of an 8-player round would mean the Aswang wins before killing anybody. The
+-- MinPlayers end of the range is NOT pinned here on purpose — at 3 players the literal rule is
+-- degenerate no matter what this number is, and pure/WinConditions' dealt-in clamp is what handles it.
+check(
+	"the attrition win is reachable but not free on a full server",
+	Config.Round.AswangWinSurvivorThreshold >= 1
+		and Config.Round.AswangWinSurvivorThreshold < Config.Round.MaxPlayers - Config.Roles.AswangCount,
+	`threshold={Config.Round.AswangWinSurvivorThreshold}, survivors on a full server={Config.Round.MaxPlayers - Config.Roles.AswangCount}`
+)
+
+-- Spec §4.3 step 4: the corpse "remains for 45s, then fades". A fade longer than the lifetime means
+-- the body is translucent for its whole existence and never reads as a body at all.
+check(
+	"the corpse fades inside its own lifetime",
+	Config.Monster.CorpseFadeTime < Config.Monster.CorpseDuration,
+	`CorpseFadeTime={Config.Monster.CorpseFadeTime}, CorpseDuration={Config.Monster.CorpseDuration}`
+)
+
+-- Spec §4.3 step 5. The corpse is the evidence, and the cooldown is how long until there could be a
+-- second one. If a body faded before the Aswang could kill again, the map would never show two at
+-- once — and "bodies are piling up" is the pressure that makes survivors group and finish tasks.
+check(
+	"a body outlives the cooldown, so two kills can be evidence at once",
+	Config.Monster.CorpseDuration > Config.Monster.KillCooldown,
+	`CorpseDuration={Config.Monster.CorpseDuration}, KillCooldown={Config.Monster.KillCooldown}`
+)
+
+-- Spec §4.4. Two selected task points within kill range of each other are one location wearing two
+-- hats: the Aswang covers both from a standstill and the "spread" in the draw buys nothing.
+check(
+	"selected task points are spread further apart than the Aswang can reach",
+	Config.Tasks.MinSpacingStuds > Config.Monster.KillRange,
+	`MinSpacingStuds={Config.Tasks.MinSpacingStuds}, KillRange={Config.Monster.KillRange}`
+)
+
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end
 
-print("  PASS  config: 21 balance invariants")
+print("  PASS  config: 25 balance invariants")
```

#### Step 2.2: `KillVerdict` and `PlayerKilledPayload`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

The verdict union (nine refusal reasons, never echoed to a client) and the broadcast payload, whose
comment records the one thing that must never appear in it.

```diff
 export type TransformVerdict =
 	"OK"
 	| "NOT_ASWANG"
 	| "WRONG_PHASE"
 	| "NOT_ALIVE"
 	| "ALREADY_TRANSFORMED"
 	| "ON_COOLDOWN"
 
+--[[
+	The verdict from `pure/KillValidation.luau` (C05). Same shape and same rule as TransformVerdict: a
+	union rather than a boolean so the server can log WHY, and NEVER echoed to any client.
+
+	The echo rule is stricter here than it looks. TARGET_IS_ASWANG is a direct role oracle — fire
+	RequestKill at every player in turn and the one that answers differently is the monster — and
+	KILLER_NOT_ASWANG is the same oracle pointed inward. There is no "safe subset" to return, which is
+	why the handler returns nothing at all on every refusal rather than filtering the verdict.
+]]
+export type KillVerdict =
+	"OK"
+	| "WRONG_PHASE"
+	| "KILLER_NOT_ALIVE"
+	| "SELF"
+	| "NOT_ASWANG"
+	| "NOT_TRANSFORMED"
+	| "ON_COOLDOWN"
+	| "TARGET_NOT_ALIVE"
+	| "TARGET_IS_ASWANG"
+	| "OUT_OF_RANGE"
+
+--[[
+	The kill broadcast (§4.3 step 4, C05). TWO FIELDS, AND THE ABSENT ONE IS THE POINT.
+
+	It does NOT carry the killer — not a UserId, not a name, not a direction, not a distance, not a
+	"you were seen" flag. §4.8 says the reveal is the end screen's job, and a kill that named its author
+	would delete the entire accusation game in one field.
+
+	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD HERE, because both of its warnings
+	apply and one extra one does:
+
+	  · Luau accepts an EXTRA field on an annotated table silently. Measured; still true.
+	  · `check-secrecy.mjs` checks payload FIELDS only for remotes on its REVEAL_ALLOWLIST, and
+	    PlayerKilled is deliberately not on that list. So the field check does not run here at all.
+	  · Its SECRET token regex matches `aswang`, `imposter`, `isaswang`, `monsteruserid` and friends —
+	    it does NOT match `KillerUserId`. The most natural wrong field in this game's history would be
+	    added, typechecked, scanned and shipped with `npm run verify` green.
+
+	That gap is recorded in this plan's Issues Found and is why `exploit-auditor` gates Phase 4.
+
+	Position is a Vector3 and that is safe: the corpse model stands at that position and replicates to
+	every client on its own. The payload states nothing the workspace does not state one frame later.
+]]
+export type PlayerKilledPayload = {
+	VictimUserId: number,
+	Position: Vector3,
+}
+
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read?
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **`check:config` does not prove a `Config` key exists.** It only refuses magic numbers in
  `src/server/` and `src/client/`, so adding a key is invisible to it. That is why this step's check is
  `lune run tests/config.test.luau` and why every new key arrives with an invariant — a key with no
  relationship pinned to it is a key that can drift to any value without a symptom.
- **The `AswangWinSurvivorThreshold` invariant deliberately does not pin the MinPlayers end.** Writing
  `threshold < MinPlayers - AswangCount` would be the obvious assertion and it fails today: 2 < 2 is
  false. The rule is degenerate at three players for any threshold ≥ 1, which is a fact about §4.8 and
  not about the number. Phase 5's clamp is the fix; asserting it here would only force the number down
  to 1 and break 8-player rounds.
- **`Vector3` in `Types.luau` is safe; `Vector3` in `pure/` is not.** `tests/config.test.luau` requires
  `Config.luau` under Lune, which has no Roblox datatypes — that is why the transform colours are RGB
  triples. Nothing under Lune requires `Types.luau`, so a `Vector3` field there costs nothing. Phase 3's
  pure module still takes plain `{ X, Y, Z }` tables for exactly the Lune reason.
- **Secret leakage:** the new `KillVerdict` union names the secret in two of its members
  (`TARGET_IS_ASWANG`, `NOT_ASWANG`). Those are server-side log strings and must never reach a client;
  Step 4.3 is where that is enforced, and the type's comment says so at the point of temptation.
- **Scope:** three numbers, two types, no remote, no §3 OUT-list token.

### Phase 3: `pure/KillValidation.luau` — every condition except the raycast

C05's decision, pulled out of the DataModel so a terminal can prove it. §4.3's five verbatim
server-side rules plus the two the same paragraph implies.

#### Step 3.1: The module

**File:** `src/shared/pure/KillValidation.luau`
**Verify:** `npm run analyze`

`(request) -> verdict`, with a fixed check order that is part of the contract, positions as plain
`{ X, Y, Z }` tables because Lune has no `Vector3`, and squared-distance comparison.

```diff
+--!strict
+--[[
+	KillValidation — may this Aswang kill this player right now, and if not, why not.
+
+		(request) -> verdict
+
+	§4.3's five verbatim server-side rules are "distance ≤ 8 studs, raycast line-of-sight, cooldown
+	elapsed, both alive, round ACTIVE". Four of the five are comparisons over numbers and string enums
+	and live here. The fifth — the raycast — is irreducibly Roblox and stays in MonsterService, which is
+	the split TransformRules' header predicted for this module.
+
+	SEVEN CONDITIONS, NOT SIX, and the two extras are not scope creep:
+
+	  · the killer must BE the Aswang and the target must NOT be — C05's own Done line lists these, and
+	    they are the whole of §6.2 applied to one remote.
+	  · the killer must be TRANSFORMED. §4.3 step 3 reads "While transformed: +25% move speed, can kill
+	    on touch/prompt within 8 studs" — the kill is a property of the monster form, not of the role.
+	    Without it an Aswang kills from inside a crowd wearing a survivor's face and the risk/reward
+	    pillar (§2) is gone. It is called out in Follow Ups because C05's bullet list does not say it.
+
+	NO Vector3. Lune has no Roblox datatypes at all, so a Vector3 here would not fail to typecheck — it
+	would fail at TEST time, which is the same trap Config's RGB triples exist to avoid (Config.luau
+	lines 66–69). Positions are plain tables; MonsterService converts at the call site.
+
+	NO `script.Parent` REQUIRES. The two enums are re-declared; Luau literal unions are structural, so
+	these and their Types.luau counterparts are the same types.
+
+	THIS ONE MAY LIVE IN src/shared/pure/, on the same test RoleDraw's header sets. A client can require
+	and call it, and it learns nothing: every input is either a fact that client already holds about
+	itself, a Config number that already replicates, or a position it can read off the workspace. The
+	verdict it computes locally has no authority — the server evaluates its own copy against its own
+	state, which is the only one that counts. Logic is not secret; inputs and seeds are, and this
+	function has neither.
+
+	THE VERDICT NEVER REACHES A CLIENT. TARGET_IS_ASWANG is a role oracle in one word.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+
+-- A position, as plain numbers. See the Vector3 note above.
+export type Vec3 = { X: number, Y: number, Z: number }
+
+export type Verdict =
+	"OK"
+	| "WRONG_PHASE"
+	| "KILLER_NOT_ALIVE"
+	| "SELF"
+	| "NOT_ASWANG"
+	| "NOT_TRANSFORMED"
+	| "ON_COOLDOWN"
+	| "TARGET_NOT_ALIVE"
+	| "TARGET_IS_ASWANG"
+	| "OUT_OF_RANGE"
+
+export type Request = {
+	Phase: RoundPhase,
+	KillerUserId: number,
+	TargetUserId: number,
+	KillerIsAswang: boolean,
+	TargetIsAswang: boolean,
+	KillerState: PlayerState,
+	TargetState: PlayerState,
+	Transformed: boolean,
+	KillerPos: Vec3,
+	TargetPos: Vec3,
+	Range: number,
+	Now: number,
+	LastRevertedAt: number?, -- nil means "has not reverted this round"; never on cooldown
+	Cooldown: number,
+}
+
+local KillValidation = {}
+
+--[[
+	SQUARED, so there is no square root and no float-comparison surprise at the boundary. `<=` rather
+	than `<`: §4.3 says "within 8 studs", and a player standing at exactly the range is within it.
+]]
+local function withinRange(a: Vec3, b: Vec3, range: number): boolean
+	local dx = a.X - b.X
+	local dy = a.Y - b.Y
+	local dz = a.Z - b.Z
+
+	return dx * dx + dy * dy + dz * dz <= range * range
+end
+
+--[[
+	THE ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in TransformRules. It decides which
+	reason a log line carries when more than one applies, and C41 reads those lines to tell an exploiter
+	probing the boundary apart from a real player mashing a button.
+
+	World facts first (phase), then the killer (alive, not itself, role, form, cooldown), then the
+	target (alive, not the Aswang), then geometry last. Geometry is last deliberately: it is the only
+	condition an honest player hits routinely, so a log full of OUT_OF_RANGE is a UX finding and a log
+	full of anything above it is a security finding.
+
+	A NOTE ON THE COOLDOWN CHECK BEING HERE AT ALL. Today it is redundant: a kill requires the
+	transformed form, and TransformRules already refuses to grant that form until Cooldown has elapsed
+	since the last revert, so an on-cooldown Aswang cannot be transformed in the first place. It is kept
+	because C05's own bullet list names it, because the redundancy costs one comparison, and because the
+	day something else grants the form — a C14 salt interaction, a debug path, a bug — this is the only
+	check standing between that and a chain kill.
+]]
+function KillValidation.evaluate(request: Request): Verdict
+	if request.Phase ~= "ACTIVE" then
+		return "WRONG_PHASE"
+	end
+
+	-- AN ALLOWLIST, on both sides, never `~= "SPECTATOR"`. See pure/PlayerBody.luau: PlayerState has
+	-- four values, exactly one of them may kill and exactly one of them may be killed, and C15 makes
+	-- GHOST real. A denylist here is the C01 bug wearing a different hat.
+	if request.KillerState ~= "ALIVE" then
+		return "KILLER_NOT_ALIVE"
+	end
+
+	-- Before the role check, so a compromised client cannot use "kill myself" as a role probe with a
+	-- different refusal shape than "kill someone else".
+	if request.KillerUserId == request.TargetUserId then
+		return "SELF"
+	end
+
+	if not request.KillerIsAswang then
+		return "NOT_ASWANG"
+	end
+
+	-- §4.3 step 3. The kill belongs to the monster form, not to the role.
+	if not request.Transformed then
+		return "NOT_TRANSFORMED"
+	end
+
+	-- §4.3 step 5: FROM THE REVERT, not from the kill. Measured from the kill, an Aswang holding the
+	-- form for its full MaxTransformTime serves most of the penalty while still being a monster.
+	-- tests/config.test.luau already pins KillCooldown > TransformTime + RevertTime for the same reason.
+	local lastRevertedAt = request.LastRevertedAt
+
+	if lastRevertedAt ~= nil and request.Now - lastRevertedAt < request.Cooldown then
+		return "ON_COOLDOWN"
+	end
+
+	if request.TargetState ~= "ALIVE" then
+		return "TARGET_NOT_ALIVE"
+	end
+
+	-- With AswangCount = 1 this is unreachable today. It is here because Config.Roles.AswangCount is a
+	-- knob and §3's OUT list bans MULTIPLE ASWANGS PER ROUND — so the day someone sets it to 2 in a
+	-- Studio session, the failure must be "the kill is refused", not "the monsters eat each other".
+	if request.TargetIsAswang then
+		return "TARGET_IS_ASWANG"
+	end
+
+	if not withinRange(request.KillerPos, request.TargetPos, request.Range) then
+		return "OUT_OF_RANGE"
+	end
+
+	return "OK"
+end
+
+return KillValidation
```

#### Step 3.2: The test

**File:** `tests/kill-validation.test.luau`
**Verify:** `lune run tests/kill-validation.test.luau`

The range boundary from both sides, the cooldown boundary from both sides, the wrong phase, self-kill,
and all sixteen combinations of killer state × target state.

```diff
+--!strict
+--[[
+	The kill's preconditions, proven from a terminal.
+
+	This is C05's stated Verify line — "at range, past range, on cooldown, wrong phase" — plus the two
+	things that line does not ask for and that this game cannot afford to get wrong: the 4×4 grid of
+	player states, and the exact boundary of each numeric comparison.
+
+	BOUNDARIES ARE TESTED FROM BOTH SIDES, always. `<` and `<=` are one character apart and the
+	difference is invisible in play — a kill at exactly 8.0 studs that silently fails once in fifty is
+	indistinguishable from lag, and nobody files it.
+]]
+
+local KillValidation = require("../src/shared/pure/KillValidation")
+
+type PlayerState = KillValidation.PlayerState
+type Verdict = KillValidation.Verdict
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+-- A request that passes everything. Every case below is this table with ONE field changed, so a
+-- failure names the field that caused it and nothing else.
+local function valid(): KillValidation.Request
+	return {
+		Phase = "ACTIVE",
+		KillerUserId = 1,
+		TargetUserId = 2,
+		KillerIsAswang = true,
+		TargetIsAswang = false,
+		KillerState = "ALIVE",
+		TargetState = "ALIVE",
+		Transformed = true,
+		KillerPos = { X = 0, Y = 0, Z = 0 },
+		TargetPos = { X = 0, Y = 0, Z = 0 },
+		Range = 8,
+		Now = 100,
+		LastRevertedAt = nil,
+		Cooldown = 30,
+	}
+end
+
+local function verdictWith(mutate: (KillValidation.Request) -> ()): Verdict
+	local request = valid()
+
+	mutate(request)
+
+	return KillValidation.evaluate(request)
+end
+
+check("the happy path is OK", KillValidation.evaluate(valid()) == "OK")
+
+--------------------------------------------------------------------------------
+-- Phase (§4.3: "round ACTIVE")
+--------------------------------------------------------------------------------
+
+for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } do
+	check(
+		`no kill during {phase}`,
+		verdictWith(function(request)
+			request.Phase = phase :: any
+		end) == "WRONG_PHASE"
+	)
+end
+
+--------------------------------------------------------------------------------
+-- Range — the boundary from both sides, on each axis and on a diagonal
+--------------------------------------------------------------------------------
+
+check(
+	"a target at exactly the range is within it",
+	verdictWith(function(request)
+		request.TargetPos = { X = 8, Y = 0, Z = 0 }
+	end) == "OK"
+)
+
+check(
+	"one stud past the range is refused",
+	verdictWith(function(request)
+		request.TargetPos = { X = 9, Y = 0, Z = 0 }
+	end) == "OUT_OF_RANGE"
+)
+
+-- C05's Done line names 40 studs through a wall. The wall is the raycast's job; the 40 is this one's.
+check(
+	"the 40-stud exploit case is refused",
+	verdictWith(function(request)
+		request.TargetPos = { X = 40, Y = 0, Z = 0 }
+	end) == "OUT_OF_RANGE"
+)
+
+-- HEIGHT COUNTS. A flat XZ distance would let the Aswang kill through a floor from the storey above,
+-- with a clean raycast straight down and every other condition satisfied.
+check(
+	"a target directly overhead, out of range, is refused",
+	verdictWith(function(request)
+		request.TargetPos = { X = 0, Y = 20, Z = 0 }
+	end) == "OUT_OF_RANGE"
+)
+
+-- 3-4-5: exactly 5 studs away using all three axes, which a per-axis comparison would get wrong.
+check(
+	"a diagonal inside the range is allowed",
+	verdictWith(function(request)
+		request.TargetPos = { X = 3, Y = 4, Z = 0 }
+	end) == "OK"
+)
+
+--------------------------------------------------------------------------------
+-- Cooldown (§4.3 step 5) — from the REVERT
+--------------------------------------------------------------------------------
+
+check(
+	"a first kill of the round is never on cooldown",
+	verdictWith(function(request)
+		request.LastRevertedAt = nil
+	end) == "OK"
+)
+
+check(
+	"one second before the cooldown elapses is refused",
+	verdictWith(function(request)
+		request.LastRevertedAt = request.Now - 29
+	end) == "ON_COOLDOWN"
+)
+
+check(
+	"exactly at the cooldown is allowed",
+	verdictWith(function(request)
+		request.LastRevertedAt = request.Now - 30
+	end) == "OK"
+)
+
+--------------------------------------------------------------------------------
+-- Role and form
+--------------------------------------------------------------------------------
+
+check(
+	"a survivor cannot kill",
+	verdictWith(function(request)
+		request.KillerIsAswang = false
+	end) == "NOT_ASWANG"
+)
+
+-- §4.3 step 3. The seventh condition, and the one C05's bullet list does not name.
+check(
+	"an untransformed Aswang cannot kill",
+	verdictWith(function(request)
+		request.Transformed = false
+	end) == "NOT_TRANSFORMED"
+)
+
+check(
+	"the Aswang cannot kill itself",
+	verdictWith(function(request)
+		request.TargetUserId = request.KillerUserId
+	end) == "SELF"
+)
+
+-- Unreachable at AswangCount = 1, and pinned anyway: §3's OUT list bans multiple Aswangs, so if that
+-- knob ever moves the failure must be a refusal rather than monsters eating each other.
+check(
+	"the Aswang cannot kill another Aswang",
+	verdictWith(function(request)
+		request.TargetIsAswang = true
+	end) == "TARGET_IS_ASWANG"
+)
+
+--------------------------------------------------------------------------------
+-- THE 4×4 GRID. The C04 warning's actual subject: PlayerState has four values, exactly one may kill
+-- and exactly one may be killed, and a denylist passes every case except the two nobody writes.
+--------------------------------------------------------------------------------
+
+local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+
+for _, killerState in STATES do
+	for _, targetState in STATES do
+		local verdict = verdictWith(function(request)
+			request.KillerState = killerState
+			request.TargetState = targetState
+		end)
+
+		local expected: Verdict = if killerState ~= "ALIVE"
+			then "KILLER_NOT_ALIVE"
+			elseif targetState ~= "ALIVE" then "TARGET_NOT_ALIVE"
+			else "OK"
+
+		check(
+			`killer={killerState} target={targetState}`,
+			verdict == expected,
+			`expected {expected}, got {verdict}`
+		)
+	end
+end
+
+-- Stated as a property as well as a grid, so a future edit cannot satisfy the cells by accident while
+-- breaking the rule they exist to express.
+check(
+	"a mid-round joiner cannot be killed",
+	verdictWith(function(request)
+		request.TargetState = "SPECTATOR"
+	end) == "TARGET_NOT_ALIVE"
+)
+
+check(
+	"a ghost cannot be killed",
+	verdictWith(function(request)
+		request.TargetState = "GHOST"
+	end) == "TARGET_NOT_ALIVE"
+)
+
+--------------------------------------------------------------------------------
+-- Check ORDER is part of the contract: it decides which reason the log carries.
+--------------------------------------------------------------------------------
+
+check(
+	"a wrong phase outranks everything else",
+	verdictWith(function(request)
+		request.Phase = "INTERMISSION"
+		request.KillerIsAswang = false
+		request.TargetPos = { X = 999, Y = 0, Z = 0 }
+	end) == "WRONG_PHASE"
+)
+
+check(
+	"the killer's own state outranks the target's",
+	verdictWith(function(request)
+		request.KillerState = "GHOST"
+		request.TargetState = "SPECTATOR"
+	end) == "KILLER_NOT_ALIVE"
+)
+
+if failures > 0 then
+	error(`{failures} failure(s)`, 0)
+end
+
+print("  PASS  kill-validation: 16 grid cells + 21 cases")
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read?
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **This module proves the kill is *refused* correctly and says nothing about whether it *works*.** The
  raycast, the corpse and the broadcast are all in Phase 4 and none of them is reachable from Lune.
  That asymmetry is the honest one — every refusal is provable here and the success path is the one §5
  hands to a human — but a green Phase 3 must not be reported as "the kill works".
- **`Range` and `Cooldown` are parameters, not reads.** The module is under `src/shared/pure/`, which
  `check:config` does not govern, so nothing would stop a literal `8` being written here. Passing them
  in keeps the knobs in `Config.luau` where M12 tunes them, and it is what makes the boundary tests able
  to use round numbers instead of importing balance.
- **The seventh condition (`NOT_TRANSFORMED`) is an addition to C05's bullet list.** Justified by §4.3
  step 3, flagged in Follow Ups, and worth a decision rather than an assumption: if the intent were
  "the Aswang can kill in either form", this check is the one line to delete and the risk/reward pillar
  goes with it.
- **`TARGET_IS_ASWANG` is unreachable at `AswangCount = 1`.** Kept deliberately (see the comment), but
  it means one of the ten verdicts has no live code path and will read as dead code to a linter or a
  reviewer who has not read §3's OUT list.
- **Secret leakage:** none on the wire — this module has no wire. The leak available here is the
  verdict being echoed, which is Phase 4's problem and is called out in both files' headers.
- **Strict Luau:** `request.Phase = phase :: any` in the test's loop is the standard escape for
  iterating a literal union as strings; without the cast the array's element type widens to `string`
  and the assignment fails. Same pattern as `tests/transform-rules.test.luau`.

### Phase 4: MonsterService — the kill, the corpse, and the broadcast

The Roblox-shaped half: the raycast, the corpse, the forced revert, and the one broadcast. This is the
🔒 phase; `exploit-auditor` is mandatory on it.

#### Step 4.1: `RoundService.MarkKilled` — the only writer of a death

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run analyze`

`RoundService` owns `PlayerStates`, so `MonsterService` asks rather than writes. `MarkKilled` sets
`GHOST`, drops the body via Phase 1's rule, and pushes a snapshot. It does not touch the phase.

```diff
 -- Exposed so gameplay services can end a round early.
 function RoundService.EndRound(result: Types.RoundResult)
 	if state.Phase ~= Enums.RoundPhase.Active then
 		return
 	end
 	enterEnding(result)
 end
+
+--[[
+	A survivor died (C05). The ONLY writer of a death, and it lives here because this service owns
+	PlayerStates — MonsterService asks rather than writes, exactly as it asks for the phase rather than
+	reading a copy.
+
+	GHOST, NOT A FIFTH STATE. §4.7 already calls a dead survivor a ghost, and Types.PlayerState has
+	four values that this plan does not extend. Two consequences land immediately and both are wanted:
+	pure/PlayerBody says a GHOST has no body, and pure/KillValidation says a GHOST is not a valid
+	target — which is the C04 warning's "a ghost must not be killable", satisfied by construction
+	rather than by a rule someone has to remember at C15.
+
+	THE CALLER HAS ALREADY TAKEN THE BODY. MonsterService detaches the victim's character
+	(`player.Character = nil`) to make it the corpse BEFORE calling this, so applyBodyRule below finds
+	nothing to destroy. Reversing those two steps deletes the corpse in the same frame it is created,
+	and the symptom is "the corpse code does not work" — a full step away from the cause.
+
+	Guarded on ACTIVE and on the victim currently being ALIVE, so a duplicate call — two kill requests
+	landing in the same tick, a retry after a dropped packet — is a no-op rather than a second death.
+	Phase 5 hangs the win check off the end of this function, which is why that idempotence matters.
+]]
+function RoundService.MarkKilled(player: Player)
+	if state.Phase ~= Enums.RoundPhase.Active then
+		return
+	end
+
+	if state.PlayerStates[player.UserId] ~= Enums.PlayerState.Alive then
+		return
+	end
+
+	state.PlayerStates[player.UserId] = Enums.PlayerState.Ghost
+
+	applyBodyRule(player)
+
+	-- Immediately, rather than waiting up to SnapshotInterval: AlivePlayerCount and the victim's own
+	-- YourState both just changed, and the victim's HUD is the one screen guaranteed to be looked at.
+	broadcastSnapshot()
+
+	if Config.Debug.VerboseLogging then
+		-- A UserId and a count. Never a role, and never who did it — this line is read while a round is
+		-- still running, and VerboseLogging is exactly the flag a Studio playtest leaves on.
+		print(`[RoundService] Killed {player.UserId}; {aliveCount()} alive.`)
+	end
+end
```

#### Step 4.2: The corpse — persist `CorpseDuration`, then fade

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:config`

Detach the victim's character from the player, anchor it, strip its controller, park it under one
folder, and fade it out over `CorpseFadeTime` at the end of `CorpseDuration`.

```diff
 local Players = game:GetService("Players")
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local TweenService = game:GetService("TweenService")
 
 local AntiCheatService = require(script.Parent.AntiCheatService)
 local RoleService = require(script.Parent.RoleService)
 local RoundService = require(script.Parent.RoundService)
 
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.Config)
 local Enums = require(Shared.Enums)
+local KillValidation = require(Shared.pure.KillValidation)
 local Remotes = require(Shared.Remotes)
 local TransformRules = require(Shared.pure.TransformRules)
 local Types = require(Shared.Types)
```

```diff
 local transformedRemote = Remotes.Get("MonsterTransformed")
+local killedRemote = Remotes.Get("PlayerKilled")
+
+-- One parent for every corpse, so the raycast can exclude them wholesale and a phase change can clear
+-- them with a single Destroy. Created on Start, never destroyed.
+local corpses: Folder? = nil
```

```diff
+--------------------------------------------------------------------------------
+-- The corpse (§4.3 step 4). "Corpse remains for 45s, then fades."
+--------------------------------------------------------------------------------
+
+--[[
+	THE CORPSE IS THE VICTIM'S OWN CHARACTER, DETACHED — not a clone.
+
+	A clone would need Archivable to be true, would duplicate every accessory and its meshes, and would
+	arrive at a client as a brand-new model at the same instant the original disappeared. Detaching
+	keeps the body that was already replicated and already being looked at, which is the difference
+	between "someone died here" and "a prop appeared".
+
+	`player.Character = nil` is what makes it a prop: the player no longer owns it, so nothing the
+	client sends moves it. Anchoring every part is the belt to that braces — it also stops the body
+	sliding down a hill for 45 seconds, which is comic rather than frightening (§4.9).
+
+	NO BLOOD, NO RAGDOLL, NO DISMEMBERMENT. §4.9 is a business constraint, not a taste one: gore pushes
+	the age rating to 13+ and cuts off the audience that plays and spends the most. A body that lies
+	there and fades is the whole effect.
+]]
+local function makeCorpse(victim: Player, character: Model)
+	victim.Character = nil
+
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+
+	if humanoid ~= nil then
+		-- Stop it standing up, walking, or being steered. WalkSpeed 0 is not a balance number.
+		humanoid.WalkSpeed = 0
+		humanoid.AutoRotate = false
+		humanoid.PlatformStand = true
+	end
+
+	for _, part in character:GetDescendants() do
+		if part:IsA("BasePart") then
+			part.Anchored = true
+			-- A body should not be a wall. It also should not be a raycast blocker; the kill's line of
+			-- sight excludes this whole folder for the same reason.
+			part.CanCollide = false
+		end
+	end
+
+	character.Name = `Corpse_{victim.UserId}`
+	character.Parent = corpses
+
+	--[[
+		The fade, then the removal. Registered as one delayed closure rather than a loop: a corpse that
+		is Destroyed early — by a phase change, or by the server closing — leaves a tween pointed at a
+		destroyed instance, which is harmless, whereas a running loop is a live coroutine per corpse.
+	]]
+	task.delay(Config.Monster.CorpseDuration, function()
+		if character.Parent == nil then
+			return
+		end
+
+		local info = TweenInfo.new(Config.Monster.CorpseFadeTime)
+
+		for _, part in character:GetDescendants() do
+			if part:IsA("BasePart") then
+				TweenService:Create(part, info, { Transparency = 1 }):Play()
+			end
+		end
+
+		task.delay(Config.Monster.CorpseFadeTime, function()
+			character:Destroy()
+		end)
+	end)
+end
+
+-- Every corpse goes when the round does. Bodies from the last round standing in the plaza during
+-- INTERMISSION is the kind of thing that reads as a bug in a clip, and clips are the marketing.
+local function clearCorpses()
+	local folder = corpses
+
+	if folder == nil then
+		return
+	end
+
+	for _, corpse in folder:GetChildren() do
+		corpse:Destroy()
+	end
+end
+
 --------------------------------------------------------------------------------
 -- Transform and revert
 --------------------------------------------------------------------------------
```

```diff
 local function onPhaseChanged(phase: Types.RoundPhase)
 	if phase == Enums.RoundPhase.Active then
 		return
 	end
 
+	clearCorpses()
+
 	-- Leaving ACTIVE ends every transform and clears the cooldowns, so a new round never begins with
 	-- a monster still standing or an Aswang serving the last round's penalty.
 	for userId in monsters do
```

```diff
 function MonsterService.Start()
+	local folder = Instance.new("Folder")
+
+	folder.Name = "Corpses"
+	folder.Parent = workspace
+	corpses = folder
+
 	--[[
 		THE RATE LIMIT LIVES HERE, INLINE, and not inside validateAndTransform — deliberately.
```

#### Step 4.3: The `RequestKill` handler — AntiCheat first, pure verdict second, raycast third

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:ratelimit`

`Consume` inline at the connect site (the shape C04 set), then `KillValidation.evaluate`, then the
raycast, then commit. The verdict is logged and never echoed.

```diff
+--------------------------------------------------------------------------------
+-- The kill (§4.3 steps 3–5, C05)
+--------------------------------------------------------------------------------
+
+-- Vector3 -> the plain table pure/KillValidation takes. The pure module cannot mention Vector3: Lune
+-- has no Roblox datatypes and the whole module would stop being runnable from a terminal.
+local function vec(position: Vector3): KillValidation.Vec3
+	return { X = position.X, Y = position.Y, Z = position.Z }
+end
+
+local function rootOf(character: Model): BasePart?
+	local root = character:FindFirstChild("HumanoidRootPart")
+
+	return if root ~= nil and root:IsA("BasePart") then root :: BasePart else nil
+end
+
+--[[
+	THE ONE CONDITION THAT CANNOT BE PURE (§4.3, "raycast line-of-sight").
+
+	Killing through a wall is the difference between a stalking game and a lag-compensated murder
+	simulator, and it is the single most valuable exploit in this game after knowing the role: an
+	exploiter who can kill through geometry never has to be seen, which deletes the transform's entire
+	risk half.
+
+	The filter excludes both characters — otherwise the ray hits the killer's own torso at zero distance
+	and every kill is refused — and the corpse folder, because a body is not cover. Note that a raycast
+	hits parts regardless of CanCollide unless RespectCanCollide is set, so making corpses
+	non-collidable is NOT enough on its own.
+
+	`workspace:Raycast(origin, direction, params)` returns nil when nothing was hit, which is the
+	"clear line" case. This API is not used anywhere else in this repository yet — see Follow Ups; the
+	Phase 4 playtest is where it is confirmed rather than assumed, and the failure mode if
+	`Enum.RaycastFilterType.Exclude` is wrong for this engine version is that EVERY kill is refused,
+	which is loud rather than silent.
+]]
+local function hasLineOfSight(killerRoot: BasePart, targetRoot: BasePart): boolean
+	local params = RaycastParams.new()
+
+	params.FilterType = Enum.RaycastFilterType.Exclude
+	params.FilterDescendantsInstances = {
+		killerRoot.Parent :: Instance,
+		targetRoot.Parent :: Instance,
+		corpses :: Instance,
+	}
+	params.IgnoreWater = true
+
+	local origin = killerRoot.Position
+	local result = workspace:Raycast(origin, targetRoot.Position - origin, params)
+
+	return result == nil
+end
+
+--[[
+	The commit, in the ONE order that works. Every line here depends on the one above it.
+
+	  1. The corpse first, because it steals the character from the player. RoundService.MarkKilled
+	     applies the body rule, which destroys a character the victim still owns — so if this ran second
+	     there would be no body left to make a corpse out of.
+	  2. The state change, which is what makes the victim uncounted, bodiless and unkillable.
+	  3. The revert (§4.3 step 4, "after a kill it must revert"). This is ALSO what starts the cooldown,
+	     because revert() stamps LastRevertedAt — §4.3 step 5's "30s from revert" is not implemented as
+	     a separate timer anywhere, it is this line.
+	  4. The broadcast, last, so no client is told about a kill the server has not finished committing.
+]]
+local function commitKill(killer: Player, victim: Player, victimCharacter: Model, position: Vector3)
+	makeCorpse(victim, victimCharacter)
+
+	RoundService.MarkKilled(victim)
+
+	revert(killer)
+
+	-- TWO FIELDS. See Types.PlayerKilledPayload: the killer appears nowhere in it, in any form, and
+	-- nothing in this repo would catch it if it did. Built as a typed local rather than an inline table
+	-- because FireAllClients takes `...any` and an inline literal is checked against nothing at all.
+	local payload: Types.PlayerKilledPayload =
+		{ VictimUserId = victim.UserId, Position = position }
+
+	killedRemote:FireAllClients(payload)
+end
+
+local function validateAndKill(killer: Player, targetUserId: number)
+	local target = Players:GetPlayerByUserId(targetUserId)
+
+	if target == nil then
+		return
+	end
+
+	local killerCharacter = killer.Character
+	local targetCharacter = target.Character
+
+	if killerCharacter == nil or targetCharacter == nil then
+		return
+	end
+
+	local killerRoot = rootOf(killerCharacter)
+	local targetRoot = rootOf(targetCharacter)
+
+	if killerRoot == nil or targetRoot == nil then
+		return
+	end
+
+	local monster = stateFor(killer.UserId)
+
+	local verdict = KillValidation.evaluate({
+		Phase = RoundService.GetPhase(),
+		KillerUserId = killer.UserId,
+		TargetUserId = target.UserId,
+		KillerIsAswang = RoleService.IsAswang(killer),
+		TargetIsAswang = RoleService.IsAswang(target),
+		KillerState = RoundService.GetPlayerState(killer),
+		TargetState = RoundService.GetPlayerState(target),
+		--[[
+			`Announced`, NOT `Transformed`, and the difference is a whole mechanic.
+
+			`Transformed` is set BEFORE the 1.2s windup (to close the spam race), so using it here would
+			let the Aswang fire RequestTransform and RequestKill back to back and kill during the windup
+			— before anyone with line of sight has seen anything. §4.3 step 2 calls that windup "visible
+			to anyone with line of sight" and it is the entire risk half of the risk/reward. `Announced`
+			is set only after MonsterTransformed(true) has gone out, so the kill unlocks exactly when the
+			warning does.
+		]]
+		Transformed = monster.Announced,
+		KillerPos = vec(killerRoot.Position),
+		TargetPos = vec(targetRoot.Position),
+		Range = Config.Monster.KillRange,
+		Now = os.clock(),
+		LastRevertedAt = monster.LastRevertedAt,
+		Cooldown = Config.Monster.KillCooldown,
+	})
+
+	if verdict ~= "OK" then
+		-- LOGGED, NEVER ECHOED, and the stakes are higher than they are for the transform. Returning
+		-- TARGET_IS_ASWANG or NOT_ASWANG to a client is a role oracle you can walk through the whole
+		-- server with: fire at each player in turn and read which answer comes back.
+		if Config.Debug.VerboseLogging then
+			print(`[MonsterService] Refused kill by {killer.Name}: {verdict}`)
+		end
+
+		return
+	end
+
+	-- LAST, because it is the only check that touches the physics engine. Everything cheap has already
+	-- said yes, so the expensive one runs at most once per legitimate attempt — which is what makes an
+	-- unauthorised spam of this remote cost the server nothing beyond a table lookup.
+	if not hasLineOfSight(killerRoot, targetRoot) then
+		if Config.Debug.VerboseLogging then
+			print(`[MonsterService] Refused kill by {killer.Name}: NO_LINE_OF_SIGHT`)
+		end
+
+		return
+	end
+
+	commitKill(killer, target, targetCharacter, targetRoot.Position)
+end
```

```diff
 	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
 		if not AntiCheatService.Consume(player, "RequestTransform") then
 			return
 		end
 
 		validateAndTransform(player)
 	end)
+
+	-- Same shape as the handler above, for the same reason: `check-ratelimit.mjs` matches the Consume
+	-- call within 1200 characters of the connect site, so the guard is visible to a reader skimming the
+	-- file and to the gate. Consume FIRST, before the UserId is even looked at.
+	Remotes.Get("RequestKill").OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
+		if not AntiCheatService.Consume(player, "RequestKill") then
+			return
+		end
+
+		-- A remote argument is whatever the client sent. `targetUserId` is typed `unknown` rather than
+		-- `number` precisely so this line cannot be skipped: without it a table or a function reaches
+		-- GetPlayerByUserId and throws inside a connection, which Roblox swallows into one warn.
+		if typeof(targetUserId) ~= "number" then
+			return
+		end
+
+		validateAndKill(player, targetUserId)
+	end)
+
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
 	Players.PlayerRemoving:Connect(onPlayerRemoving)
 end
```

#### Step 4.4: Everything the kill puts on the wire, stated in one place

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:secrecy`

Step 4.3 wrote the broadcast. This step writes down what leaves this service and what does not — in the
header, where C04 already keeps that list — and closes the one derived hint the corpse introduces.

```diff
 	WHAT THIS SERVICE DOES NOT SEND
 	-------------------------------
 	`MonsterTransformed` carries a Character and a boolean. It does NOT carry a role: "this character
 	transformed" is a fact about the world; "this player is the Aswang" is an inference the client is
 	welcome to make and the server never states. The distinction becomes load-bearing at C14, where
 	salt forces a revert on someone who is still the Aswang.
 
 	The refusal verdict is likewise never echoed back. It exists so the server can log WHY, and handing
 	a client `NOT_ASWANG` would be a free role oracle for anyone willing to spam the remote.
+
+	`PlayerKilled` (C05) carries a victim and a position, and NOTHING ELSE — no killer, no name, no
+	direction, no distance, no "you were seen". Three things about that are worth knowing before anyone
+	adds a field:
+
+	  · It is not on check-secrecy.mjs's REVEAL_ALLOWLIST, which means the field allowlist does not run
+	    on it at all. Its SECRET regex does not match `KillerUserId` either. A killer field here would
+	    typecheck, scan clean and ship. The type's comment says so; this is the second place it is said.
+	  · The position is safe on its own terms, not by permission: an anchored corpse is standing at that
+	    position and replicates to every client one frame later. The payload states nothing new.
+	  · What IS inferable, and cannot be fixed here, is proximity — a client reading replicated character
+	    positions at the instant of the broadcast can see who was within eight studs. That is inherent
+	    to a proximity kill in a replicated world; the counter is design, not code (§4.3: the killer is
+	    standing there in monster form, having just been announced). Recorded in Follow Ups rather than
+	    papered over.
```

```diff
 	character.Name = `Corpse_{victim.UserId}`
 	character.Parent = corpses
```

The corpse's name is a deliberate choice and not an oversight: it carries the **victim's** UserId, which
`PlayerKilled` has just broadcast to every client anyway, and it carries nothing about the killer. It is
named at all because a body in the world that nobody can identify makes "Body here!" (§4.5's quick chat)
unanswerable. The rule the next author needs: **anything written onto a corpse replicates, including
attributes and tags** — so a `CollectionService` tag marking "killed by the Aswang" would be a map-wide
role broadcast, which is exactly the C04 shape `exploit-auditor` caught before.

#### Step 4.5: `Humanoid.Died` forces a revert

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run verify:fast`

Closes the C04 finding "`Humanoid.Died` does not revert a transformed Aswang — deferred, a required
input to C05". Now that death exists, so does the case.

```diff
+--[[
+	A TRANSFORMED ASWANG THAT DIES MUST REVERT. C04's deferred finding, marked "a required input to
+	C05" because until this chunk there was no way to die at all.
+
+	Note what this is NOT: the kill path does not go through Humanoid.Died — the victim's character is
+	detached and anchored, never killed, because §4.9 wants a fade rather than a death animation. This
+	connection covers everything else that can end a character mid-transform: falling out of the world,
+	a Studio-side reset, and whatever C14's salt does to a monster standing in a bad place.
+
+	Reverting on death also charges the cooldown, because revert() stamps LastRevertedAt. That is the
+	right answer rather than a side effect: dying while transformed should cost the Aswang the same 30
+	seconds a completed hunt does, or falling off a roof becomes a free reset.
+]]
+local function watchCharacter(player: Player, character: Model)
+	local humanoid = character:FindFirstChildOfClass("Humanoid")
+
+	if humanoid == nil then
+		return
+	end
+
+	humanoid.Died:Connect(function()
+		revert(player)
+	end)
+end
+
+local function onPlayerAdded(player: Player)
+	player.CharacterAdded:Connect(function(character: Model)
+		watchCharacter(player, character)
+	end)
+
+	-- RoundService turns CharacterAutoLoads off and loads explicitly (Step 1.4), so a character can
+	-- already exist by the time this service's Start() runs on a live server.
+	local character = player.Character
+
+	if character ~= nil then
+		watchCharacter(player, character)
+	end
+end
+
 local function onPlayerRemoving(player: Player)
 	monsters[player.UserId] = nil
 end
```

```diff
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+	Players.PlayerAdded:Connect(onPlayerAdded)
 	Players.PlayerRemoving:Connect(onPlayerRemoving)
+
+	-- Anyone already here. Same reasoning as RoundService.Start's backfill: connect first, then sweep,
+	-- and accept that a player arriving in the window is handled twice. watchCharacter is idempotent
+	-- only in the sense that a second Died connection calls revert() twice, and revert() early-returns
+	-- when the player is not transformed — so the double is harmless.
+	for _, player in Players:GetPlayers() do
+		onPlayerAdded(player)
+	end
 end
```

#### Step 4.6: The client's local reaction

**File:** `src/client/Controllers/CameraFXController.luau`
**Verify:** `npm run check:remotes`

A log line today and a proximity hook for M7. If this file were deleted the kill would still be fully
visible to everyone, which is the test for whether something belongs on this side.

```diff
 local function onTransformed(payload: Types.MonsterTransformedPayload)
```

```diff
+--[[
+	The client's reaction to a kill (C05). Deliberately almost nothing, on the same test the transform
+	reaction is held to: the corpse is a real anchored model in the workspace and replicates by itself,
+	so if this file were deleted a player would still walk around a corner and find a body.
+
+	IT DOES NOT GUESS THE KILLER, and it must never start. The payload does not name one, and the
+	nearest-player inference a client COULD compute is exactly the accusation the game asks a human to
+	make out loud through the quick-chat wheel (§4.5). Computing it here would hand every player a
+	perfect answer and delete the social half of the game — and it would look like a feature in review.
+]]
+local function onPlayerKilled(payload: Types.PlayerKilledPayload)
+	local isMine = payload.VictimUserId == Players.LocalPlayer.UserId
+
+	print(`[Client] Kill witnessed{if isMine then " (you died)" else ""}`)
+
+	-- TODO(M7): a low thud and a brief vignette when payload.Position is within
+	-- Config.Monster.TransformAudioRange of the camera. Distance-gated on THIS side is fine — the
+	-- position is already here, so gating buys atmosphere, not secrecy.
+end
+
 function CameraFXController.Init() end
 
 function CameraFXController.Start()
 	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
+	Remotes.Get("PlayerKilled").OnClientEvent:Connect(onPlayerKilled)
 end
```

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

- **Secret leakage — the one that is real and cannot be fixed in code.** A client reading replicated
  character positions at the instant `PlayerKilled` fires can see who was within `KillRange` of the
  victim. Every proximity kill in a replicated world has this property; the corpse gives it away a frame
  later regardless. Recorded in Follow Ups as structural, not scheduled for a fix.
- **Secret leakage — the one that is a real bug waiting to happen.** `check:secrecy` does not check
  `PlayerKilled`'s fields (not on `REVEAL_ALLOWLIST`) and its `SECRET` regex does not match
  `KillerUserId`. A killer field here passes the whole gate. Stated in three places now
  (`Types.luau`, the service header, this list) and it is still only a habit. Issues Found row 2.
- **The verdict must not be echoed, and `TARGET_IS_ASWANG` is why.** A boolean reply — even
  "refused" versus silence — is a role oracle once the attacker controls the target. The handler returns
  nothing on every refusal, including the line-of-sight one.
- **Rate limiting:** the new `OnServerEvent` handler consults `AntiCheatService.Consume` as its first
  statement, at the connect site, inside the 1200-character window `check-ratelimit.mjs` scans.
  `Config.AntiCheat.Budgets.RequestKill` already exists (Capacity 3, RefillPerSecond 0.25).
- **Phase ownership:** `MonsterService` never calls `setPhase`. It calls `RoundService.MarkKilled`,
  which writes a player state and not the phase. `EndRound` is Phase 5's business and is still guarded
  on `ACTIVE` inside `RoundService`.
- **Player leaving mid-round (§6.4):** three cases meet here. (1) The victim disconnects between the
  raycast and `commitKill` — `Players:GetPlayerByUserId` already returned a player, and `MarkKilled`
  writes to a `PlayerStates` entry that `onPlayerRemoving` has cleared, resurrecting a key for a player
  who is gone. It is cleaned at the next `setAllPlayerStates`, and the alive count is briefly wrong.
  **Flagged as Medium, not fixed in this plan** — the fix is a liveness re-check inside `MarkKilled`
  and it wants its own test. (2) The killer disconnects mid-kill: `monsters[userId]` is cleared by
  `onPlayerRemoving`, and `revert()` reads rather than constructs, so the stale timer declines to act
  — C04 already solved this. (3) The Aswang disconnecting still ends the round via `ABORTED`.
- **Corpse cleanup on disconnect:** a victim who leaves after dying leaves a corpse with their UserId in
  its name for up to `CorpseDuration`. Correct — the body should not vanish because someone closed the
  tab, and that is exactly the moment survivors are looking at it.
- **Magic numbers:** `CorpseDuration`, `CorpseFadeTime`, `KillRange` and `KillCooldown` are all read
  from `Config`. `humanoid.WalkSpeed = 0` is on `check-config`'s idiomatic list and is structure, not
  balance — a corpse does not have a walk speed to tune.
- **Mobile budget:** one `Folder`, and up to `MaxPlayers - 1` anchored corpses at once, each with a
  short tween on its parts at end of life. No lights, no particles, no per-frame loop. The corpses are
  anchored and non-collidable, so they cost rendering and nothing else — worth a look on a real phone
  at C27 alongside C04's two `PointLight`s.
- **Strict Luau:** `targetUserId: unknown` forces the `typeof` narrowing. `corpses` is `Folder?` and is
  cast at the raycast filter; if `Start()` has not run there are no corpses to exclude and the cast is
  on a nil the engine tolerates in that array — **confirm this in the Phase 4 playtest** rather than
  assuming, or hoist the folder into `Init()`.
- **Scope:** no weapon, no second monster, no meeting, no sabotage. The kill is the grab-and-fade §4.9
  asks for.

### Phase 5: The Aswang's win condition

§4.8's attrition half, as a pure predicate with one non-obvious clamp. The timeout half already works
and is not touched.

#### Step 5.1: `src/shared/pure/WinConditions.luau`

**File:** `src/shared/pure/WinConditions.luau`
**Verify:** `npm run analyze`

`aswangWinsByAttrition(request) -> boolean`, with the effective threshold clamped by how many survivors
were **dealt in**. This is what stops a 3-player round and a solo Studio round from being won on tick
one.

> **The solo question, answered.** A `Debug.SoloTesting` round has one player, and since commit
> `3c70cfc` that player is forced to be the Aswang — so the round has **zero survivors**, which
> satisfies "≤ 2" on the first tick. **The predicate returns false when no survivors were dealt in**,
> and the solo round therefore runs to sunrise and ends on `TIMEOUT`. That is not a special case for
> Studio bolted onto a game rule; it falls out of the general rule below, and it has to, because solo
> rounds are the only thing an agent can drive. A predicate that ended them instantly would make every
> future chunk unverifiable in exactly the environment the harness has.

```diff
+--!strict
+--[[
+	WinConditions — has the Aswang won by attrition? (§4.8, C06)
+
+		(request) -> boolean
+
+	A SIBLING OF RoundTransitions RATHER THAN A ROW IN IT, and the split is on purpose. That module
+	answers "what happens next given a phase and a timer" and its exhaustive 5×2×2 table is its whole
+	value; a headcount rule threaded through it would multiply that table by the roster. This one
+	answers a different question, over different inputs, and C11's survivor win becomes a second
+	function in this same file rather than a third place to look.
+
+	§4.8 IN ONE LINE IS WRONG, AND THIS IS THE POINT OF THE MODULE
+	--------------------------------------------------------------
+	"Aswang wins when living survivors ≤ 2" is right for the 6–8 player round the spec pictures and
+	degenerate below it. Config.Round.MinPlayers is 3 — one Aswang and two survivors — so the literal
+	rule is TRUE BEFORE ANYONE MOVES. A three-player round would end the instant it began, on the exact
+	server population §9 calls the cold-start risk and the exact one the Solo Trial exists to cover.
+
+	The fix is to read the threshold as what it means: MOST OF THEM ARE DEAD. So the effective
+	threshold is clamped to one below however many survivors were dealt in, and a round that started at
+	or under the threshold uses "one fewer than we started with" instead of a number that was already
+	satisfied.
+
+		dealt in  threshold  effective  wins when living survivors reach
+		--------  ---------  ---------  --------------------------------
+		7 (8p)    2          2          2
+		5 (6p)    2          2          2
+		2 (3p)    2          1          1
+		1         2          0          0
+		0 (solo)  2          —          never; see the guard below
+
+	NO `script.Parent` REQUIRES, and the threshold arrives as a parameter rather than being read from
+	Config — same rule as every other pure module here.
+]]
+
+export type Request = {
+	-- Survivors (NOT players) currently ALIVE. The Aswang is excluded by the caller; a count that
+	-- included it would be off by one at exactly the boundary that matters.
+	LivingSurvivors: number,
+	-- Survivors dealt into the round at STARTING. A snapshot, not a live count: it must not move when
+	-- someone disconnects, or the rule quietly re-scales itself mid-round.
+	DealtInSurvivors: number,
+	Threshold: number,
+}
+
+local WinConditions = {}
+
+function WinConditions.aswangWinsByAttrition(request: Request): boolean
+	--[[
+		NOBODY TO KILL, SO NOTHING TO WIN.
+
+		This is the solo Studio round (Debug.SoloTesting plus Debug.ForceAswangWhenSolo, which since
+		commit 3c70cfc makes the lone player the Aswang). Zero survivors satisfies every threshold on
+		tick one, and an agent driving a solo round would see it end before ACTIVE was a second old.
+
+		It is also the honest answer for a live server: a round with no survivors in it was never a
+		contest, so there is no attrition to measure. Such a round still ends — the sunrise timer takes
+		it to ENDING with TIMEOUT, which §4.8 already scores as an Aswang win. Nothing hangs.
+	]]
+	if request.DealtInSurvivors <= 0 then
+		return false
+	end
+
+	local effective = math.min(request.Threshold, request.DealtInSurvivors - 1)
+
+	return request.LivingSurvivors <= effective
+end
+
+return WinConditions
```

#### Step 5.2: `tests/win-conditions.test.luau`

**File:** `tests/win-conditions.test.luau`
**Verify:** `lune run tests/win-conditions.test.luau`

A full table across dealt-in counts 0 through 7, plus the three properties the cells exist to express.

```diff
+--!strict
+--[[
+	The Aswang's attrition win (§4.8), across every roster size this game can have.
+
+	The cells below are the whole point: the rule is one comparison, and every bug it can have is a bug
+	at a boundary — the round that starts already won, the round that can never be won, the last
+	survivor. Each one is a cell somebody can argue with.
+]]
+
+local WinConditions = require("../src/shared/pure/WinConditions")
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local THRESHOLD = 2 -- Config.Round.AswangWinSurvivorThreshold at time of writing
+
+local function wins(dealtIn: number, living: number): boolean
+	return WinConditions.aswangWinsByAttrition({
+		LivingSurvivors = living,
+		DealtInSurvivors = dealtIn,
+		Threshold = THRESHOLD,
+	})
+end
+
+type Case = { dealtIn: number, living: number, expected: boolean, why: string }
+
+local CASES: { Case } = {
+	-- SOLO (Debug.SoloTesting + ForceAswangWhenSolo). One player, who IS the Aswang, so zero survivors
+	-- were dealt in. Must NEVER win by attrition: solo rounds are the only rounds an agent can drive,
+	-- and a round that ends on tick one cannot verify anything downstream of it.
+	{ dealtIn = 0, living = 0, expected = false, why = "solo Studio round" },
+
+	-- MinPlayers = 3: one Aswang, two survivors. The literal §4.8 rule is satisfied before anyone
+	-- moves, which is the whole reason the clamp exists.
+	{ dealtIn = 2, living = 2, expected = false, why = "3-player round, nobody dead yet" },
+	{ dealtIn = 2, living = 1, expected = true, why = "3-player round, one killed" },
+	{ dealtIn = 2, living = 0, expected = true, why = "3-player round, both killed" },
+
+	-- 4 players: three survivors. One kill takes it to the threshold.
+	{ dealtIn = 3, living = 3, expected = false, why = "4-player round, nobody dead" },
+	{ dealtIn = 3, living = 2, expected = true, why = "4-player round, one killed" },
+
+	-- 6 players — the spec's picture of a round.
+	{ dealtIn = 5, living = 5, expected = false, why = "6-player, full" },
+	{ dealtIn = 5, living = 3, expected = false, why = "6-player, two killed" },
+	{ dealtIn = 5, living = 2, expected = true, why = "6-player, three killed" },
+
+	-- 8 players — MaxPlayers.
+	{ dealtIn = 7, living = 3, expected = false, why = "8-player, four killed" },
+	{ dealtIn = 7, living = 2, expected = true, why = "8-player, five killed" },
+	{ dealtIn = 7, living = 0, expected = true, why = "8-player, wiped out" },
+
+	-- A two-player round: one Aswang, one survivor. Reachable only through SoloTesting or a shutdown
+	-- race, and it must terminate rather than being unwinnable forever.
+	{ dealtIn = 1, living = 1, expected = false, why = "two players, survivor alive" },
+	{ dealtIn = 1, living = 0, expected = true, why = "two players, survivor killed" },
+}
+
+for _, case in CASES do
+	local actual = wins(case.dealtIn, case.living)
+
+	check(
+		`dealtIn={case.dealtIn} living={case.living} ({case.why})`,
+		actual == case.expected,
+		`expected {case.expected}, got {actual}`
+	)
+end
+
+--------------------------------------------------------------------------------
+-- The properties the cells exist to express. A future edit must not satisfy the table by accident
+-- while breaking the rule underneath it.
+--------------------------------------------------------------------------------
+
+-- THE ONE THAT KEEPS THE HARNESS WORKING. Stated separately from its cell because the cell is one
+-- line in a table and this is a constraint on the whole project's ability to verify itself.
+check("a solo round is never won on tick one", not wins(0, 0))
+
+-- No round may be over before it starts, at ANY roster size. This is the general form of the §4.8
+-- degeneracy, and it is what the clamp actually guarantees.
+for dealtIn = 1, 7 do
+	check(
+		`a round of {dealtIn} survivors is not already won at kickoff`,
+		not wins(dealtIn, dealtIn),
+		"the round would end during STARTING"
+	)
+end
+
+-- Every round must be winnable by attrition eventually, or the Aswang has no path but the timer.
+for dealtIn = 1, 7 do
+	check(`a round of {dealtIn} survivors is won when all are dead`, wins(dealtIn, 0))
+end
+
+-- MONOTONIC IN THE DIRECTION THE GAME MOVES. Survivors only ever decrease, so once the round is won
+-- it must stay won. Walking `living` downwards is the same order the round walks it in; a comparison
+-- written with the wrong operator satisfies several cells above and fails here.
+for dealtIn = 1, 7 do
+	local won = false
+
+	for living = dealtIn, 0, -1 do
+		local result = wins(dealtIn, living)
+
+		if won and not result then
+			check(`monotonic at dealtIn={dealtIn}`, false, `un-won at living={living}`)
+		end
+
+		won = won or result
+	end
+end
+
+if failures > 0 then
+	error(`{failures} failure(s)`, 0)
+end
+
+print("  PASS  win-conditions: 14 cases + 22 properties")
```

#### Step 5.3: `RoundService` evaluates it — on a kill, and only on a kill

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run verify:fast`

The dealt-in survivor count is snapshotted in `enterStarting`; the predicate runs at the end of
`MarkKilled` and nowhere else. A disconnect must not end a round.

```diff
 local RoleService = require(script.Parent.RoleService)
 local PlayerBody = require(Shared.pure.PlayerBody)
 local RoundTransitions = require(Shared.pure.RoundTransitions)
 local Types = require(Shared.Types)
+local WinConditions = require(Shared.pure.WinConditions)
```

```diff
 	TasksCompleted = 0,
 	GateOpen = false,
+	-- How many SURVIVORS were dealt into this round, snapshotted at STARTING. A snapshot rather than a
+	-- live count on purpose: see enterStarting.
+	DealtInSurvivors = 0,
 	-- Keyed by UserId. LOBBY between rounds, ALIVE for everyone dealt into a round, SPECTATOR for
 	-- anyone who joined after it started (spec §6.4), GHOST once C15 lands.
 	PlayerStates = {} :: { [number]: PlayerState },
 }
```

```diff
 local function aliveCount(): number
 	local count = 0
 	for _, playerState in state.PlayerStates do
 		if playerState == Enums.PlayerState.Alive then
 			count += 1
 		end
 	end
 	return count
 end
+
+--[[
+	Living SURVIVORS — alive, and not the Aswang. Distinct from aliveCount(), which is what the client
+	snapshot carries, and the difference is exactly one player.
+
+	Reads state.AswangUserId, which is why this cannot live in the pure module: the count is derived
+	from the secret. What crosses to WinConditions is a NUMBER, and a number is not a hint — the
+	snapshot already tells every client how many players are alive, and "one fewer than that" is
+	arithmetic anyone can do. Nothing here is broadcast.
+]]
+local function livingSurvivorCount(): number
+	local count = 0
+
+	for userId, playerState in state.PlayerStates do
+		if playerState == Enums.PlayerState.Alive and userId ~= state.AswangUserId then
+			count += 1
+		end
+	end
+
+	return count
+end
```

```diff
 	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())
 
+	--[[
+		SNAPSHOTTED HERE, AFTER THE DRAW, AND NEVER UPDATED AGAIN THIS ROUND.
+
+		It has to be after the draw, because "survivors" means "dealt in and not the Aswang" and the
+		Aswang does not exist a line earlier. It has to be frozen, because §4.8's rule is about how many
+		of the people who started have died — a count that fell when somebody disconnected would let a
+		losing survivor quit and hand the Aswang the win, which is the same mistake RoundTransitions
+		refuses to make in ACTIVE (see its comment) for the same reason.
+	]]
+	state.DealtInSurvivors = livingSurvivorCount()
+
 	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
```

```diff
 local function enterIdle()
 	state.AswangUserId = nil
 	state.TasksCompleted = 0
 	state.GateOpen = false
+	state.DealtInSurvivors = 0
```

```diff
 	if Config.Debug.VerboseLogging then
 		-- A UserId and a count. Never a role, and never who did it — this line is read while a round is
 		-- still running, and VerboseLogging is exactly the flag a Studio playtest leaves on.
 		print(`[RoundService] Killed {player.UserId}; {aliveCount()} alive.`)
 	end
+
+	--[[
+		§4.8's attrition win (C06). AT THE END OF MarkKilled AND NOWHERE ELSE.
+
+		Not in the step() loop: polling a win condition several times a second means the round can end
+		on a tick that no player action caused, and debugging "why did it end there" starts from a
+		timestamp instead of from an event.
+
+		Not on PlayerRemoving either, and that is the deliberate one. A survivor disconnecting reduces
+		the living count exactly as a kill does, and ending the round for it would (a) hand the Aswang a
+		win every time a phone lost signal and (b) let a losing survivor void a round by quitting. Spec
+		§6.4 already answers this for the headcount — "finish the round, then return to IDLE" — and this
+		is the same answer for the same reason. DealtInSurvivors being a frozen snapshot is the other
+		half of it: a disconnect moves neither side of the comparison.
+
+		EndRound is guarded on ACTIVE inside this service, so this stays a request rather than a second
+		writer of the phase.
+	]]
+	if
+		WinConditions.aswangWinsByAttrition({
+			LivingSurvivors = livingSurvivorCount(),
+			DealtInSurvivors = state.DealtInSurvivors,
+			Threshold = Config.Round.AswangWinSurvivorThreshold,
+		})
+	then
+		RoundService.EndRound(Enums.RoundResult.AswangWins)
+	end
 end
```

```diff
 function RoundService.Init()
 	state.Phase = Enums.RoundPhase.Idle
+	state.DealtInSurvivors = 0
 	table.clear(state.PlayerStates)
 end
```

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read?
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **The solo answer is a game rule, not a debug branch, and that was a decision.** The alternative —
  `if Config.Debug.SoloTesting then return false end` — would have worked in Studio and left the
  3-player round broken on a live server, where nobody would see it because nobody would get past
  STARTING to report it. The dealt-in clamp covers both and reads as a rule.
- **`livingSurvivorCount()` reads the secret, so it can never be exposed.** It stays a local. If a
  future chunk wants it on the snapshot, note that `AlivePlayerCount` minus `LivingSurvivors` is `1`
  during a round and `0` after the Aswang dies — a client holding both learns whether the monster is
  still alive, which is a fact §4.8 keeps until the reveal.
- **The predicate cannot fire without a kill, which means C06 cannot be verified without C05.** That
  is why it is Phase 5 and not Phase 2, and it is also why its playtest evidence is bounded by §5's
  ceiling: solo cannot produce a victim, so the wiring is proven by the Lune suite and the code path
  in `MarkKilled` is proven only by reading.
- **Phase ownership:** `MarkKilled` calls `RoundService.EndRound`, which is this service's own exported
  entry point and is guarded on `ACTIVE`. `setPhase` still has exactly one caller.
- **A second win condition is coming.** C11 adds the survivors' win to this same module. `enterEnding`
  already warns and discards a late second result, so the two racing is handled — a property C01 built
  ahead of exactly this moment.
- **Player leaving mid-round (§6.4):** the disconnect case is answered above, deliberately, in both
  directions. The "Aswang leaves" case still ends with `ABORTED` before any of this runs.
- **Scope:** one predicate, one call site. No end-screen work, no XP, no analytics — those are M8/M9.

### Phase 6: `pure/TaskSelection.luau` — the pure half of C07

The 5-of-12 draw. §4.4's one load-bearing decision and Appendix C.4's cause #2. No map, no tags, no
service wiring.

#### Step 6.1: The module

**File:** `src/shared/pure/TaskSelection.luau`
**Verify:** `npm run analyze`

`(pool, count, minSpacing, nextFloat) -> chosen`. The RNG is injected rather than seeded inside, which
is the same rule `RoleDraw` follows and the reason this module may live in `src/shared/pure/` at all.

> **Deviation from C07's stated signature, and the justification.** `docs/BUILD-PLAN.md` writes
> `(pool, count, seed) -> chosen`. A `seed` parameter forces a generator **inside** the module, and this
> module is under `src/shared/`, which `default.project.json` maps wholesale into `ReplicatedStorage` —
> so a client could require it, guess a seed, and replay the draw. `RoleDraw` already solved this by
> injecting `nextFloat: () -> number`, and taking the same shape here means the generator stays on the
> server, the test supplies its own deterministic stream, and "10,000 seeded draws" is still exactly
> what the test does. This is the conforming choice against `CLAUDE.md`, and a deviation only from a
> line of prose. Flagged in Follow Ups so it is a decision rather than a drift.

```diff
+--!strict
+--[[
+	TaskSelection — which 5 of the 12 task points does this round use? (§4.4, C07)
+
+		(pool, count, nextFloat) -> chosen
+
+	§4.4's ONE LOAD-BEARING DECISION. "12 possible task locations exist on the map. Each round randomly
+	picks 5. Players cannot memorise a route." Appendix C.4 names route memorisation as cause #2 of the
+	competitor's death — 2.5M visits, $0 — and this is the fix that keeps one map fresh for dozens of
+	plays at the cost of one function.
+
+	THE RNG IS INJECTED, NEVER CREATED HERE. Same rule as RoleDraw, and here is why it applies to a
+	module whose output is public within seconds anyway:
+
+	  · This file lives in src/shared/, which replicates. A client can require it AND call it.
+	  · A `seed` parameter would put a reproducible generator on that side of the wire. Guess the seed
+	    and you know every task location before STARTING ends — enough for an Aswang to be standing at
+	    one when the round begins.
+	  · `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and both fatal.
+	    TaskService seeds with `Random.new()` — no argument — at C17.
+
+	The algorithm being public costs nothing. The stream being reproducible costs the round.
+
+	NO `script.Parent` REQUIRES, and no Vector3: positions are plain { X, Y, Z } tables so Lune can run
+	this. TaskService converts at the call site, exactly as MonsterService does for KillValidation.
+]]
+
+export type Vec3 = { X: number, Y: number, Z: number }
+
+-- One candidate task location. `Position` is optional because C17's greybox is what puts positions on
+-- these, and a pool without them must still draw correctly rather than erroring — see spacing below.
+export type Point = {
+	Id: string,
+	Position: Vec3?,
+}
+
+local TaskSelection = {}
+
+local function distanceSquared(a: Vec3, b: Vec3): number
+	local dx = a.X - b.X
+	local dy = a.Y - b.Y
+	local dz = a.Z - b.Z
+
+	return dx * dx + dy * dy + dz * dz
+end
+
+--[[
+	Would adding this point keep every selected pair at least `minSpacing` apart?
+
+	A point with no Position never blocks and is never blocked. That is the graceful half of "spatially
+	spread IF the pool carries positions": a pool discovered before C17 tags anything with a position
+	still draws five distinct points, it just draws them without spacing.
+]]
+local function respectsSpacing(chosen: { Point }, candidate: Point, minSpacing: number): boolean
+	local candidatePosition = candidate.Position
+
+	if candidatePosition == nil or minSpacing <= 0 then
+		return true
+	end
+
+	local floor = minSpacing * minSpacing
+
+	for _, point in chosen do
+		local position = point.Position
+
+		if position ~= nil and distanceSquared(position, candidatePosition) < floor then
+			return false
+		end
+	end
+
+	return true
+end
+
+--[[
+	A PARTIAL FISHER-YATES OVER A COPY, with a spacing filter layered on top.
+
+	Fisher-Yates is the part that has to be right: it is uniform over the pool and it CANNOT produce a
+	duplicate, because a drawn index is swapped out of the live range rather than being re-rolled. The
+	obvious alternative — "pick a random index, retry if already taken" — is uniform too and unbounded
+	in the worst case, which is a hang on a server rather than a wrong answer, and hangs are the failure
+	mode this game can least afford inside STARTING.
+
+	SPACING BIASES THE DISTRIBUTION AND THAT IS ACCEPTED. A point in a crowded corner of the map is
+	drawn slightly less often than an isolated one, because it is more often rejected. §4.4 asks for
+	spread and Appendix C.4 asks for unpredictability; perfect uniformity is neither of those things,
+	and the test measures uniformity on a pool WITHOUT positions so it measures the shuffle rather than
+	the filter.
+
+	THE FALLBACK IS NOT OPTIONAL. If spacing cannot be satisfied — twelve points in one room, or a
+	minSpacing tuned too high at M12 — the second pass takes whatever is left, in the shuffled order,
+	ignoring spacing. Returning fewer than `count` points would open the escape gate at 3/5 forever
+	(Config.Tasks.TotalRequired is what the gate counts), which is an unwinnable round produced by a
+	balance number. Fewer points is only ever returned when the POOL is genuinely smaller.
+]]
+function TaskSelection.select(
+	pool: { Point },
+	count: number,
+	minSpacing: number,
+	nextFloat: () -> number
+): { Point }
+	local shuffled = table.clone(pool)
+
+	-- Fisher-Yates, back to front. nextFloat returns [0, 1), so the index is in [i, #shuffled].
+	for i = #shuffled, 2, -1 do
+		local j = math.floor(nextFloat() * i) + 1
+
+		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
+	end
+
+	local chosen: { Point } = {}
+	local skipped: { Point } = {}
+
+	for _, point in shuffled do
+		if #chosen >= count then
+			break
+		end
+
+		if respectsSpacing(chosen, point, minSpacing) then
+			table.insert(chosen, point)
+		else
+			table.insert(skipped, point)
+		end
+	end
+
+	-- The fallback pass. Still in shuffled order, so it is still a random selection — just an unspaced
+	-- one. Reached only when the pool cannot satisfy the spacing at all.
+	for _, point in skipped do
+		if #chosen >= count then
+			break
+		end
+
+		table.insert(chosen, point)
+	end
+
+	return chosen
+end
+
+return TaskSelection
```

#### Step 6.2: The test

**File:** `tests/task-selection.test.luau`
**Verify:** `lune run tests/task-selection.test.luau`

10,000 seeded draws from the test's own LCG: no duplicates ever, every point drawn within tolerance of
uniform, spacing honoured when the pool carries positions, and graceful when the pool is short.

```diff
+--!strict
+--[[
+	The 5-of-12 draw, over 10,000 rounds.
+
+	This is C07's stated Verify line: no duplicates, distribution within tolerance, graceful on a short
+	pool. Ten thousand draws rather than a handful because the two failures that matter here are
+	statistical — a shuffle that is subtly biased, and a duplicate that appears once in a thousand
+	rounds. Both look perfect in a spot check and both are permanent once shipped.
+
+	THE RNG IS THE TEST'S OWN. Lune has no Roblox `Random` class, and `math.randomseed` mutates global
+	state that every other test in this directory would then inherit. A four-line LCG is deterministic,
+	self-contained, and reproduces a failure exactly from the seed printed with it.
+]]
+
+local TaskSelection = require("../src/shared/pure/TaskSelection")
+
+type Point = TaskSelection.Point
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+-- A textbook 32-bit LCG (Numerical Recipes constants). Its statistical quality does not need to be
+-- good — it needs to be REPRODUCIBLE, so that a failing draw can be replayed from its seed.
+local function lcg(seed: number): () -> number
+	local stateValue = seed % 2147483647
+
+	return function(): number
+		stateValue = (1664525 * stateValue + 1013904223) % 4294967296
+
+		return stateValue / 4294967296
+	end
+end
+
+local POOL_SIZE = 12 -- Config.Tasks.PoolSize
+local DRAW = 5 -- Config.Tasks.TotalRequired
+local DRAWS = 10000
+
+-- Twelve points on a wide grid, far enough apart that spacing never binds. Spacing gets its own pool.
+local function spreadPool(): { Point }
+	local pool: { Point } = {}
+
+	for index = 1, POOL_SIZE do
+		table.insert(pool, {
+			Id = `T{index}`,
+			Position = { X = index * 100, Y = 0, Z = 0 },
+		})
+	end
+
+	return pool
+end
+
+-- The same twelve with no positions at all: this is what a pool looks like before C17 tags anything,
+-- and it is the pool the uniformity assertion uses, because spacing biases distribution by design.
+local function positionlessPool(): { Point }
+	local pool: { Point } = {}
+
+	for index = 1, POOL_SIZE do
+		table.insert(pool, { Id = `T{index}` })
+	end
+
+	return pool
+end
+
+--------------------------------------------------------------------------------
+-- 10,000 draws: no duplicates, ever; correct size; every Id from the pool
+--------------------------------------------------------------------------------
+
+local counts: { [string]: number } = {}
+local duplicateSeed: number? = nil
+local wrongSizeSeed: number? = nil
+
+for seed = 1, DRAWS do
+	local chosen = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(seed))
+
+	if #chosen ~= DRAW then
+		wrongSizeSeed = wrongSizeSeed or seed
+	end
+
+	local seen: { [string]: boolean } = {}
+
+	for _, point in chosen do
+		if seen[point.Id] then
+			duplicateSeed = duplicateSeed or seed
+		end
+
+		seen[point.Id] = true
+		counts[point.Id] = (counts[point.Id] or 0) + 1
+	end
+end
+
+-- §4.4 and C07's Done line: "the same point never appears twice in one round".
+check(
+	`no duplicates across {DRAWS} draws`,
+	duplicateSeed == nil,
+	if duplicateSeed then `first at seed {duplicateSeed}` else nil
+)
+
+check(
+	`every draw returns exactly {DRAW} points`,
+	wrongSizeSeed == nil,
+	if wrongSizeSeed then `first at seed {wrongSizeSeed}` else nil
+)
+
+--------------------------------------------------------------------------------
+-- Distribution. Expected share is DRAW/POOL_SIZE of DRAWS ≈ 4166 appearances each.
+--
+-- ±10% is loose on purpose. A tighter band turns a correct shuffle into a flaky test the first time
+-- the LCG's constants change; a looser one would not catch the bias this exists to catch, which is an
+-- off-by-one in the Fisher-Yates range starving the first or last element.
+--------------------------------------------------------------------------------
+
+local expected = DRAWS * DRAW / POOL_SIZE
+local tolerance = expected * 0.1
+
+for index = 1, POOL_SIZE do
+	local id = `T{index}`
+	local seen = counts[id] or 0
+
+	check(
+		`{id} is drawn about as often as every other point`,
+		math.abs(seen - expected) <= tolerance,
+		`{seen} appearances, expected {expected} ± {tolerance}`
+	)
+end
+
+--------------------------------------------------------------------------------
+-- Spacing (§4.4 "spread"), and the fallback when it cannot be honoured
+--------------------------------------------------------------------------------
+
+local MIN_SPACING = 20 -- Config.Tasks.MinSpacingStuds
+
+local spacingViolations = 0
+
+for seed = 1, 1000 do
+	local chosen = TaskSelection.select(spreadPool(), DRAW, MIN_SPACING, lcg(seed))
+
+	for i = 1, #chosen do
+		for j = i + 1, #chosen do
+			local a = chosen[i].Position
+			local b = chosen[j].Position
+
+			if a ~= nil and b ~= nil then
+				local dx = a.X - b.X
+				local dy = a.Y - b.Y
+				local dz = a.Z - b.Z
+
+				if dx * dx + dy * dy + dz * dz < MIN_SPACING * MIN_SPACING then
+					spacingViolations += 1
+				end
+			end
+		end
+	end
+end
+
+check(
+	"no two selected points are closer than the minimum spacing",
+	spacingViolations == 0,
+	`{spacingViolations} pairs too close`
+)
+
+-- THE FALLBACK. Twelve points stacked in one room cannot satisfy any spacing at all, and the round
+-- must still get five tasks — Config.Tasks.TotalRequired is what the escape gate counts, so returning
+-- three would leave the gate shut forever and produce an unwinnable round from a balance number.
+local crowded: { Point } = {}
+
+for index = 1, POOL_SIZE do
+	table.insert(crowded, { Id = `C{index}`, Position = { X = index, Y = 0, Z = 0 } })
+end
+
+local crowdedDraw = TaskSelection.select(crowded, DRAW, MIN_SPACING, lcg(7))
+local crowdedSeen: { [string]: boolean } = {}
+local crowdedDuplicate = false
+
+for _, point in crowdedDraw do
+	if crowdedSeen[point.Id] then
+		crowdedDuplicate = true
+	end
+
+	crowdedSeen[point.Id] = true
+end
+
+check("an unspaceable pool still yields a full draw", #crowdedDraw == DRAW, `got {#crowdedDraw}`)
+check("the fallback pass introduces no duplicates", not crowdedDuplicate)
+
+--------------------------------------------------------------------------------
+-- Degenerate pools. A live server that reaches one of these has a bigger problem than the draw, and
+-- erroring inside enterStarting would leave the round stuck in STARTING with no log.
+--------------------------------------------------------------------------------
+
+local short = TaskSelection.select({ { Id = "A" }, { Id = "B" } }, DRAW, 0, lcg(1))
+
+check("a pool smaller than the draw returns the whole pool", #short == 2, `got {#short}`)
+
+check("an empty pool returns nothing rather than erroring", #TaskSelection.select({}, DRAW, 0, lcg(1)) == 0)
+
+check("a draw of zero returns nothing", #TaskSelection.select(positionlessPool(), 0, 0, lcg(1)) == 0)
+
+-- Reproducibility, which is what makes every assertion above replayable from its seed — and, on the
+-- server, what makes an unseeded Random.new() the only thing standing between a client and the draw.
+local first = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(42))
+local second = TaskSelection.select(positionlessPool(), DRAW, 0, lcg(42))
+local identical = true
+
+for index, point in first do
+	if second[index].Id ~= point.Id then
+		identical = false
+	end
+end
+
+check("the same stream produces the same draw", identical)
+
+if failures > 0 then
+	error(`{failures} failure(s)`, 0)
+end
+
+print(`  PASS  task-selection: {DRAWS} draws, 12 distribution bands, spacing + 6 edge cases`)
```

#### Step 6.3: `TaskService` records the contract it will consume, and builds nothing

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run verify`

A header stating where the seed comes from, why it may not come from the round number, and that
discovery is C17's. No selection call, no remote, no state.

```diff
 --!strict
 --[[
 	TaskService — Picks 5 of 12 task spawns per round and validates progress.
 
 	Milestone: M3
 	Spec: docs/MVP-SPEC.md
+
+	STILL A STUB, DELIBERATELY, AND HALF OF C07 IS ALREADY DONE ELSEWHERE.
+
+	The DECISION — which five of the twelve — is built and proven: `shared/pure/TaskSelection.luau`
+	plus `tests/task-selection.test.luau`, 10,000 draws. What is missing is the half that needs a map:
+	the pool itself. §4.4's twelve locations are CollectionService-tagged `TaskPoint` parts placed by
+	the greybox at C17, and `TaskPoint` appears nowhere in this repository today. Wiring discovery now
+	would ship a service whose only observable behaviour is finding an empty pool — indistinguishable
+	from a broken one, and unverifiable by anything in this repo.
+
+	WHEN C17 WIRES THIS UP, THE SEED IS THE PART TO GET RIGHT
+	---------------------------------------------------------
+	`TaskSelection` lives under src/shared/, so a client can require it AND call it. The algorithm being
+	public costs nothing; a reproducible STREAM costs the round, because the Aswang would know where
+	every task is before STARTING ends.
+
+		local rng = Random.new()            -- correct: server-only entropy, no argument
+		local rng = Random.new(roundNumber) -- FATAL: the client has the round number in every snapshot
+		local rng = Random.new(os.time())   -- FATAL: client-observable to the second
+
+	Create the Random ONCE at Start(), keep it as a server-side local, and pass
+	`function() return rng:NextNumber() end` as the module's `nextFloat`. Never send the seed, the
+	stream position, or the unselected pool to a client.
+
+	Selection happens in STARTING (C07) and the chosen set is server state. The Aswang sees a fake task
+	list (§4.4) — which is a property of what TaskService SENDS, not of what it draws, and belongs with
+	the task types at C08.
 ]]
 
 local TaskService = {}
 
--- TODO(M3): randomly select Config.Tasks.TotalRequired from PoolSize spawn points.
+-- TODO(C17): discover the pool by CollectionService tag `TaskPoint`, then call
+-- TaskSelection.select(pool, Config.Tasks.TotalRequired, Config.Tasks.MinSpacingStuds, nextFloat)
+-- from RoundService's STARTING handler.
 -- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
 -- TODO(M3): validate progress server-side (proximity + rate). Open the gate at 5/5.
 -- The Aswang sees a fake task list; its progress must never count.
```

#### Phase 6 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? A draw whose inputs a client can supply is replayable locally.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Spacing and uniformity are in tension and the test measures them separately.** The rejection filter
  makes a point in a crowded corner slightly less likely to be drawn. That is a real bias, it is the
  price of §4.4's "spread", and the distribution assertion therefore runs on a position-less pool so it
  measures the shuffle rather than the filter. A future author who moves the uniformity test onto the
  spaced pool will see it fail and conclude the shuffle is broken.
- **`MinSpacingStuds` is a balance number that can make the draw impossible.** Tuned too high at M12 it
  silently falls through to the unspaced pass, and nothing reports it. The fallback is correct — an
  unwinnable round is far worse — but it fails quietly. Follow Ups: a `warn` on the fallback path when
  `Debug.VerboseLogging` is on, once there is a service to warn from.
- **This phase ships no runtime behaviour at all.** `TaskSelection` has zero callers until C17, so
  `npm run verify` going green here proves the module compiles and its test passes, and nothing about
  the game. That is deliberate and is why the phase is last: it cannot break anything Phases 1–5 built.
- **Secret leakage — the shape to watch is a seed, not a payload.** Nothing here crosses the wire. The
  leak this module can have is a caller passing a client-observable seed, which is why the discipline is
  written into `TaskService`'s header at the place the next author will be standing.
- **`check:config` does not govern `src/shared/`**, so the literal `POOL_SIZE`, `DRAW` and
  `MIN_SPACING` in the test are unflagged. They are mirrored from `Config` with a comment naming the
  key; if they drift, `tests/config.test.luau`'s `MinSpacingStuds > KillRange` invariant still holds and
  this test still passes while testing the wrong numbers. Low, but it is the honest failure mode.
- **Scope:** §4.4's draw only. No task types, no ProximityPrompt, no progress, no gate.

## 3. Related Files

### Read while planning — every one has a review in `references/`

| File | Why it was read | Review |
| --- | --- | --- |
| `docs/BUILD-PLAN.md` | C04's ⚠️ block (lines ~203–219) and C05–C07 in full | `BUILD-PLAN-review.md` |
| `docs/MVP-SPEC.md` | §3, §4.3, §4.4, §4.8, §6.2, §6.4 | `MVP-SPEC-review.md` |
| `src/server/Services/MonsterService.luau` | the file Phase 4 extends; the transform's state machine | `MonsterService-review.luau` |
| `src/server/Services/RoundService.luau` | phase ownership, player bookkeeping, the snapshot | `RoundService-review.luau` |
| `src/server/Services/AntiCheatService.luau` | the `Consume` contract and its proximity gate | `AntiCheatService-review.luau` |
| `src/server/Services/TaskService.luau` | the 20-line stub Phase 6 annotates | `TaskService-review.luau` |
| `src/server/pure/RoleDraw.luau` | the injected-RNG pattern Phase 6 copies | `RoleDraw-review.luau` |
| `src/shared/pure/TransformRules.luau` | the verdict shape Phase 3 copies | `TransformRules-review.luau` |
| `src/shared/pure/RoundTransitions.luau` | why Phase 5 is a sibling and not a row | `RoundTransitions-review.luau` |
| `src/shared/Config.luau` | which knobs exist already | `Config-review.luau` |
| `src/shared/Types.luau` | the payload contracts and what the typechecker does not catch | `Types-review.luau` |
| `src/shared/Remotes.luau` | `RequestKill` / `PlayerKilled` already declared | `Remotes-review.luau` |
| `src/shared/Enums.luau` | the literal-type casts | (no annotation needed — see `Types-review.luau`) |
| `src/client/Controllers/CameraFXController.luau` | where Step 4.6 lands | `CameraFXController-review.luau` |
| `tests/config.test.luau` | the invariant style Phase 2 extends | `config.test-review.luau` |
| `.claude/scripts/check-secrecy.mjs` | what the gate does and does not check | `check-secrecy-review.md` |
| `.claude/scripts/verify-plan.mjs` | how the `**Verify:**` lines are graded | `verify-plan-review.md` |
| prior plan + `implementation-log.md` + `verification.md` | finding row 7, and what C02–C04 left unverified | `c02-c04-plan-review.md` |

### Files this plan creates or changes

| File | Phase | Change |
| --- | --- | --- |
| `src/shared/pure/PlayerBody.luau` | 1 | new — the body and kill-target allowlists |
| `tests/player-body.test.luau` | 1 | new — 8 cells + 3 properties |
| `src/server/Services/RoundService.luau` | 1, 4, 5 | `applyBodyRule`, `MarkKilled`, `DealtInSurvivors`, the win check |
| `src/shared/Config.luau` | 2 | `AswangWinSurvivorThreshold`, `CorpseFadeTime`, `MinSpacingStuds` |
| `tests/config.test.luau` | 2 | four new invariants (21 → 25) |
| `src/shared/Types.luau` | 2 | `KillVerdict`, `PlayerKilledPayload` |
| `src/shared/pure/KillValidation.luau` | 3 | new — nine refusal reasons, no raycast |
| `tests/kill-validation.test.luau` | 3 | new — 16 grid cells + 21 cases |
| `src/server/Services/MonsterService.luau` | 4 | the kill, the corpse, the broadcast, `Humanoid.Died` |
| `src/client/Controllers/CameraFXController.luau` | 4 | reacts to `PlayerKilled` |
| `src/shared/pure/WinConditions.luau` | 5 | new — the attrition predicate |
| `tests/win-conditions.test.luau` | 5 | new — 14 cases + 22 properties |
| `src/shared/pure/TaskSelection.luau` | 6 | new — the 5-of-12 draw |
| `tests/task-selection.test.luau` | 6 | new — 10,000 draws |
| `src/server/Services/TaskService.luau` | 6 | header only; the seed contract and the C17 boundary |

`src/shared/Remotes.luau` is **not** changed. `RequestKill` (UP) and `PlayerKilled` (DOWN) are already
declared and `RequestKill` already has an `AntiCheat` budget.

## 4. Follow Ups

### Questions / Clarifications

1. **`Players.CharacterAutoLoads` and `player:LoadCharacter()` are not used anywhere in this repository
   today.** The plan uses both, and Step 1.1's Studio probe exists to look before the code lands. What
   is asserted from documentation and not from this codebase: setting the service property to `false`
   suppresses the automatic spawn, and `LoadCharacter()` spawns at an enabled `SpawnLocation`. If either
   is wrong the symptom is total — nobody spawns — which is the failure mode to prefer.
2. **`workspace:Raycast` and `Enum.RaycastFilterType.Exclude` are likewise first uses.** `Exclude` is the
   current name (it replaced `Blacklist`); if this place's engine version predates that, the enum is
   `nil`, the params object is misconfigured, and every kill is refused. Confirm in the Phase 4
   playtest.
3. **The seventh kill condition — "must be transformed" — is an addition to C05's bullet list**, taken
   from §4.3 step 3 ("While transformed: … can kill on touch/prompt within 8 studs"). It is gated on
   `Announced` rather than `Transformed` so a kill cannot land during the 1.2s windup. If the intent was
   that an Aswang may kill in either form, this is one line to delete and a design pillar to revisit.
4. **`TaskSelection` takes `nextFloat`, not `seed`**, deviating from C07's written signature. Reasoning
   is in Step 6.1; it is the pattern `RoleDraw` already established and the one `CLAUDE.md` mandates.
5. **`PlayerKilled` is broadcast to every client rather than to nearby ones.** That is C05's stated
   contract and it adds no leak the replicated corpse does not already add. If the design later wants a
   quieter world, filtering by `Monster.TransformAudioRange` server-side is the change, and it is a
   design decision rather than a security fix.
6. **A killed player is `GHOST` with no body and no abilities until C15.** They will sit at their death
   camera with nothing to do. This is C15's whole subject (§4.7 calls the dead-player gap "silently
   fatal" for retention), and it is worth knowing that C05 creates the gap C15 closes — a playtest
   between the two will surface it as a complaint.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 4 | **`check:secrecy` cannot see `PlayerKilled`'s fields.** The field allowlist runs only for remotes on `REVEAL_ALLOWLIST`, and the `SECRET` regex matches `aswang`/`isaswang`/`monsteruserid` but **not** `KillerUserId`. A killer field on this payload typechecks, scans clean and ships | High | Open — the fix is to drive the field check off `PAYLOAD_FIELDS` rather than `REVEAL_ALLOWLIST` in `check-secrecy.mjs`, with both-direction self-tests. Out of this plan's scope; `exploit-auditor` is the gate meanwhile |
| 1 | **`Players.CharacterAutoLoads = false` is unverified in this place file.** If the place overrides it, spectators keep their bodies and Phase 1 delivers nothing while appearing green | High | Open — Step 1.1 probes it first and records the outcome in `artifacts/` |
| 4 | **C05's success path cannot be verified by any agent.** Solo has a killer and no victim; the playtester cannot change Studio's player count. Only the six refusals are provable | High | Accepted — see §5. Recorded as NOT VERIFIED, needs a human with a second client |
| 4 | **`MarkKilled` can resurrect a `PlayerStates` key for a player who disconnected between the raycast and the commit.** The alive count is briefly wrong until the next `setAllPlayerStates` | Medium | Open — the fix is a liveness re-check inside `MarkKilled` and it wants its own test; deliberately not folded into an already-large Phase 4 |
| 4 | **An exploiter can identify the killer by reading replicated character positions at the instant `PlayerKilled` fires** — whoever was inside `KillRange` | Medium | Accepted — structural to a proximity kill in a replicated world; the corpse gives the same information one frame later. The design counter is §4.3's announced transform |
| 6 | **`MinSpacingStuds` tuned too high falls silently through to the unspaced pass.** No symptom; the draw just stops being spread | Medium | Open — a `warn` under `Debug.VerboseLogging` once C17 gives it a service to warn from |
| 3 | **`TARGET_IS_ASWANG` is unreachable at `AswangCount = 1`** and will read as dead code to anyone who has not read §3's OUT list | Low | By design — kept so that moving that knob produces a refusal rather than monsters killing each other |
| 6 | **The test mirrors three `Config` values as literals** (`check:config` does not govern `src/shared/`). If `Config` drifts, the test passes while testing the wrong numbers | Low | Accepted — each literal carries a comment naming its key; a Lune require of `Config` here would couple a pure test to balance |
| 2 | **The `AswangWinSurvivorThreshold` invariant pins only the `MaxPlayers` end.** The natural `< MinPlayers - AswangCount` assertion is false today and would force the threshold to 1 | Low | By design — the degeneracy is in §4.8, not in the number, and Phase 5's clamp is the answer |
| 4 | **Up to seven anchored corpses can exist at once**, each tweening on its parts at end of life, on top of C04's two `PointLight`s per transform | Low | Watch — confirm on a real phone at C27, not in Studio |

## 5. Verification and its ceiling

**State this ceiling out loud in the implementation log and in `verification.md`. Do not design around
it, and do not build a debug-only fake-victim harness to get past it** — an honest gap beats scaffolding
that has to be maintained, remembered, and removed before launch.

### What an agent can prove

| Claim | How | Where |
| --- | --- | --- |
| Every kill refusal is correct | `lune run tests/kill-validation.test.luau` | Phase 3 |
| The body and kill allowlists admit exactly one state each | `lune run tests/player-body.test.luau` | Phase 1 |
| The attrition win never fires at kickoff, at any roster size | `lune run tests/win-conditions.test.luau` | Phase 5 |
| The draw never duplicates and is uniform | `lune run tests/task-selection.test.luau` | Phase 6 |
| The balance numbers still agree | `lune run tests/config.test.luau` | Phase 2 |
| Nothing new leaks, nothing is unrate-limited, no remote is undeclared | `npm run verify` | Phase 6 |

### What the playtester must prove, solo, in Studio

This is C05's stated Done line — *"a client firing `RequestKill` at a target 40 studs away through a
wall is refused"* — and it is reachable solo **only because commit `3c70cfc` forces the Aswang in a solo
`Debug.SoloTesting` round.** Without that the lone player is always a survivor and every probe returns
`NOT_ASWANG` for the wrong reason, which is exactly what happened to C04's transform verification.

Set `Round.Intermission/Duration/EndScreen` to 8/20/6 plus `Debug.SoloTesting`, `Debug.VerboseLogging`
and `Debug.ForceAswangWhenSolo` before launching, and revert all six afterwards.

Fire `RequestKill` from `execute_luau` on the client and capture the server console line for each:

1. **Wrong phase** — during `INTERMISSION`. Expect `WRONG_PHASE`.
2. **Not transformed** — during `ACTIVE`, before transforming. Expect `NOT_TRANSFORMED`.
3. **Self** — target is the caller's own UserId. Expect `SELF`.
4. **No such target / not alive** — any UserId not in the round. Expect a silent return (no player) —
   record the silence, and note it is the one refusal with no log line.
5. **Out of range** — transform first, then fire at a UserId whose character is 40 studs away. With one
   player this needs a second character in the world; if none can be produced, record this probe as
   **blocked** rather than passing it by proxy.
6. **Rate limit** — an 8-call burst. Expect three through and then
   `[AntiCheat] Rate limit refused … on RequestKill`, matching `Capacity = 3`.

Also capture, in the same session: the transform's forced revert still fires (C04's gap), a `PlayerKilled`
listener on the client receiving nothing during a solo round, and `GetAttributes()`/`GetTags()` empty on
every Player and Character — the same secrecy sweep C04's pass ran.

### What must be recorded as NOT VERIFIED

Write these into `verification.md` verbatim, under a heading that says a human is needed:

- **The kill succeeding at all.** No agent can produce a victim: the playtester cannot change Studio's
  player count (a UI action), and the solo forced-Aswang path gives a killer with nobody to kill.
- **The corpse persisting `CorpseDuration` and then fading.**
- **The kill cooldown starting from the revert rather than from the kill.**
- **`PlayerKilled` reaching a second client**, and that client's view containing no hint of the killer.
- **The line-of-sight raycast refusing a kill through a wall** while allowing one across open ground.
- **`AlivePlayerCount` dropping on the other players' HUDs.**
- **C06's attrition win firing**, which requires enough real survivors to kill.

The gate for all of these is **two clients in Studio, or the M5 six-human playtest**. Until one of them
happens, C05 is "every refusal is proven and the success path is unproven", and that sentence is the
honest report.
</content>
