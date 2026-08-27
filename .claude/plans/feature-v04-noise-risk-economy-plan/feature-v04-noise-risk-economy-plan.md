# Plan: V04 — Noise, the Risk Economy

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V04 (`docs/BUILD-PLAN.md` §4, Track V1). Depends on V03, which is shipped.
- **Description:** Searching is loud, and loud is how you die (§4.4). This chunk builds the noise
  *system*: a pure model that prices every noisy action, a server-only bounded history that V13's
  tracker will be the sole reader of, the emit call sites in the two services that own an action the
  game actually has, and the cue that tells the actor they were loud.
- **Date:** 2026-08-27
- **What the client is told:** one new down remote, `NoiseCue`, carrying `{ Action, Loudness,
  Position, Mine }`. `Position` is **quantised** to `Config.Noise.CueGridStuds` and the payload
  **carries no player identity of any kind** — not the actor's, not the listener's. It is sent by
  `FireClient` only to players the server has already decided are within the noise's radius, and
  never by `FireAllClients`. Nothing about roles, health, the container layout or the noise history
  crosses the wire. `ClientRoundSnapshot` is not widened.

### The three questions, answered up front

**1. Is the cue a leak?** No, and the reason is that it is *uniform*, not that it is targeted.
Being fired to one player is the same shape as `RoleAssigned`, which is safe only because the payload
concerns that player alone. The leak the shape does not defend against is a **difference between
players**, so this plan pins three uniformities and never relaxes them:

- **The Aswang emits and is cued exactly like a survivor.** No branch in `NoiseModel`,
  `NoiseService`, `SearchService` or `ItemService` may read `RoundService.GetAswangUserId()`. §4.4:
  *the monster must be able to do everything a survivor does, sincerely*, and any activity it cannot
  perform sincerely becomes an oracle. `SearchService`'s header already carries this rule for the
  search itself; V04 inherits it and must not break it at the noise layer.
- **No `Sound` is ever created by the server, and none is parented to a character by anybody but its
  own client.** A server-made `Sound` in a character replicates and every client hears it, which
  turns "you were loud" into a public per-player broadcast. `AudioController.playStinger` is the
  precedent for the safe form (`src/client/Controllers/AudioController.luau:393-440`): a
  client-created, client-parented `Sound`, explicitly noted there as local-only.
- **The absence of a cue is as observable as its presence** (`.claude/lessons/absence-is-observable`).
  So there is no per-role, per-form or per-state exemption from *emitting*, and the only exemptions
  from *hearing* are the two `AudioCues` already applies to every cue: LOBBY and SPECTATOR are
  outside the round. That rule is a constant across everyone in the round, which is what makes it
  safe.

**2. Who owns emission?** The server, in every case that ships. **V04 adds no client → server
remote at all**, which is a stronger answer than adding one with a rate-limit bucket:

| Action | Emitter in V04 | Why |
| --- | --- | --- |
| `SEARCH` | `SearchService.beginHold` | Already fully server-validated (phase, liveness, distance, occupancy). The server knows the position, because it resolved the container itself. |
| `ITEM_USE` | `ItemService`, on a throw the server has already resolved | Same: `RequestThrowSalt` is validated by `pure/SaltThrow` on the server before anything happens. |
| `DOOR` | **none — no door exists in `src/`** | `grep -rni door src --include="*.luau"` returns only prose in comments. Priced in the model; wired by whichever chunk adds a door. |
| `SPRINT` | **none, deliberately, and this is a secrecy finding** | There is no sprint or crouch verb in this game (`grep -rn "Sprint\|WalkSpeed\|Crouch" src`). The **only** thing that moves above the 16-stud baseline is `Config.Monster.TransformedSpeedMult = 1.25`. A speed-threshold emitter would therefore fire for exactly one player, and the noise history — V13's only input — would become a monster tracker pointed at the monster. Priced in the model, wired by nothing. |

Because nothing new arrives from a client, `check:ratelimit` has nothing to guard here and no bucket
is added to `Config.AntiCheat`. **If a later chunk gives the client a request remote for a door or a
sprint, it needs a bucket in the same commit** — the check is a proximity tripwire around
`.OnServerEvent:Connect(`, so `AntiCheatService.Consume` must be the first statement in the handler.

**3. What shape does V13 need?** A flat, anonymous, time-ordered record and one query:

```lua
-- src/server/pure/NoiseLog.luau
export type Record = {
	Action: string, -- a Types.NoiseAction id, plain here; narrow by lookup, never by cast
	Loudness: number, -- 0..1, so a search can outweigh a footstep
	Radius: number, -- studs it carried, kept rather than re-derived
	Position: { X: number, Y: number, Z: number }, -- plain: V13's curve is a pure module too
	At: number, -- os.clock() on the server
}

-- src/server/Services/NoiseService.luau
NoiseService.GetRecent(withinSeconds: number): { NoiseLog.Record } -- copies, server-only
NoiseService.RecordCount(): number
```

**There is no actor field, and its absence is the design.** V13's pulse cannot leak an identity it
was never given, and no future edit to `TrackerService` can accidentally put one in a payload.
Per-actor throttling still happens — it lives in a transient table inside `NoiseService`, keyed by
`UserId`, that is never written into a record and never read by anything else. V13 builds
`TrackerCurve` and everything downstream of it; V04 builds nothing tracker-shaped.

## 2. Comprehensive Plan by Phases

### Preamble — the constraints every phase is bound by

These are repeated inside the phases that depend on them, because `npm run plan:phase` hands a
reader one phase at a time and a rule stated only in Phase 1's prose does not exist for whoever
implements Phase 4.

**P1 — `src/shared/pure/NoiseModel.luau` goes in `shared/pure/`, and V03's `ContainerLayout` went in
`server/pure/`, for opposite reasons.** The rule is not about the folder, it is about **inputs**.
`ContainerLayout` is a *draw*: hand a client the module and a seed it can guess and it replays the
round's layout before the round starts. `NoiseModel` is a *table lookup* over numbers that
`Config.luau` already replicates to every client — there is nothing to replay, no seed, and no input
a client supplies. The build plan says `shared/pure/` explicitly and this is why. `NoiseLog` (Phase 2)
goes in `server/pure/` on the same logic run the other way: no client caller exists or should, so the
smaller surface is free.

**P2 — a pure module may not `require(script.Parent.X)` and may not touch a Roblox datatype.** Lune
has no `script`, no `game` and no `Vector3`. Re-declare literal unions locally (Luau unions are
structural, so the local type and `Types.NoiseAction` are the same type), and pass positions as
`{ X: number, Y: number, Z: number }` — `src/shared/pure/SaltThrow.luau:49` is the established
`Vec3` convention and the call site converts.

**P3 — `check:config` governs `src/server/` and `src/client/` only** (`GOVERNED` in
`.claude/scripts/check-config.mjs:36`). `src/shared/pure/NoiseModel.luau` is *not* scanned, so the
check will not catch a number hardcoded there — the module takes its tuning as a **parameter** so
that every number still lives in `Config.Noise`. `src/server/pure/NoiseLog.luau` **is** scanned, and
so is `NoiseService`.

**P4 — a literal union does not survive `require` inside a list.**
`.claude/lessons/pure-module-unions-widen-in-lists.md`. Anything a pure module returns inside a table
comes back as plain `string`; narrow it with a **lookup function**, never with `::`. Scalars are
fine. `NoiseModel.evaluate` returns numbers, so this bites only if someone puts an `Action` field on
its result — do not.

**P5 — `RoundService` owns the phase (§6.4).** `NoiseService` subscribes to
`RoundService.PhaseChanged` and never calls `setPhase`. History is cleared on the way down
(`INTERMISSION`/`IDLE`), not at `ENDING`, matching `SearchService.onPhaseChanged` — the end screen
runs for `Config.Round.EndScreen` seconds and there is no reason to tear state down while it does.

### Phase 1: The model and the numbers

Everything a terminal can check about noise, before a single Roblox object is involved.

#### Step 1.1: Add the `Config.Noise` block and alias `Search.NoiseRadius` into it

**File:** `src/shared/Config.luau`
**Verify:** `npm run analyze`

Per-action loudness, radius and throttle interval; the two bound numbers; the cue grid. The spec's
`Search.NoiseRadius = 60` becomes an alias into the new canonical block, using V02's hoisted-local
pattern so one number keeps one home.

`Config.Noise` is canonical and `Search.NoiseRadius` is the alias — the reverse of V02's choice, and
deliberately. V02 made the *spec-named* key canonical because five modules read the old one. Here
the old key has **no readers at all** (`grep -rn "NoiseRadius" src` finds only its own declaration),
and splitting one action's radius into `Search` while three live in `Noise` is exactly the
fragmentation §6.5 exists to prevent. The spec's name is kept as an alias so a reader of §6.5's table
still finds it.

`SprintSpeedStuds` is the interesting number and it is a **guard rather than a knob**. It sits above
the fastest thing this game can currently produce — `Trial.PlayerBaselineWalkSpeed` (16) ×
`Monster.TransformedSpeedMult` (1.25) = 20 — so a naive movement emitter wired later emits *nothing*
rather than emitting for the transformed Aswang alone. Step 1.4 pins that as an invariant.

```diff
 	BuntotPagiSpawnCount = 1,
 }
 
+--[[
+	V04's NOISE BLOCK, HOISTED INTO A LOCAL SO `Search.NoiseRadius` CAN ALIAS IT (§4.4).
+
+	Spec §6.5's committed table has exactly one noise number in it, `Search.NoiseRadius = 60`, and
+	§4.4 needs a price for every noisy action. This block is CANONICAL and that one key below is an
+	ALIAS into it — the same one-number-one-home move V02 made for `Config.Salt`, pointed the other
+	way because the spec-named key here has no readers to break.
+
+	LOUDNESS IS A 0..1 SCALAR and RADIUS IS STUDS. Nothing in V04 reads Loudness except the cue's
+	volume; it exists because V13's tracker needs to weigh a search against a footstep when it picks
+	an area, and a field added later is a field every record written before it is missing.
+
+	MININTERVAL IS THE PER-ACTOR THROTTLE, and it is doing two jobs. It keeps the history bounded by
+	a provable margin (see MaxRecords), and it is the anti-spam guard that replaces a rate limit —
+	V04 adds no client remote, so `check:ratelimit` has nothing to see here, and start/cancel search
+	spam is answered by this number rather than by AntiCheatService.
+]]
+local Noise = {
+	--[[
+		How long a noise stays in the server's history. MUST NOT DROP BELOW `Tracker.EarlyInterval`
+		(90): V13's first pulse fires at 90 seconds and reads this history and nothing else, so a
+		shorter window means the first pulse of every round reads an empty table and the Aswang is
+		told nothing at the exact moment §4.6 says the pressure begins. tests/config.test.luau pins it.
+	]]
+	HistorySeconds = 120,
+	--[[
+		THE HARD CAP, and it is a safety net rather than the bound. Age is the real bound; this stops
+		a pathological emit rate from growing memory inside the window. It is pinned ABOVE the worst
+		case the throttles allow — MaxPlayers (5) x HistorySeconds (120) / the smallest MinInterval
+		(2) = 300 — so the cap can never truncate the window and silently blind the tracker.
+	]]
+	MaxRecords = 512,
+	--[[
+		The cue's position is rounded to this grid before it is sent (§4.6's "vague, never live").
+		Without it a client's audio engine localises a searcher to within a stud THROUGH A WALL,
+		which is strictly better information than V13's late-round 15-stud pulse — V04 would obsolete
+		the balance-critical chunk of the whole rewrite. Pinned below `Tracker.LateRadius`.
+	]]
+	CueGridStuds = 8,
+	--[[
+		THE SPRINT THRESHOLD, AND IT IS A SECRECY GUARD RATHER THAN A BALANCE KNOB.
+
+		There is no sprint verb in this game. The only thing that moves above the 16-stud baseline is
+		a TRANSFORMED ASWANG (Monster.TransformedSpeedMult = 1.25 -> 20 studs/s), so a movement
+		emitter with a threshold below 20 fires for exactly one player and turns V13's only input
+		into a monster tracker pointed at the monster. This sits above that, so a naive emitter wired
+		later emits nothing rather than an oracle. tests/config.test.luau pins the relationship.
+	]]
+	SprintSpeedStuds = 22,
+	--[[
+		SEARCH IS THE LOUDEST AND THE FURTHEST, and that is §4.4 rather than taste: "it is the loudest
+		thing a survivor does, and it is the thing they must do". Every other row is priced under it,
+		and tests/config.test.luau pins the ordering so a V16 tune cannot quietly invert it.
+
+		DOOR AND SPRINT HAVE NO EMITTER IN V04 — neither verb exists in src/. They are priced here
+		because the model must answer for them (build plan V04) and because a number decided at the
+		same time as its siblings is a number in the same units.
+	]]
+	Actions = {
+		-- MinInterval matches Search.SearchTime: one search, one noise, however often the key is
+		-- tapped.
+		SEARCH = { Loudness = 1, Radius = 60, MinInterval = 6 },
+		ITEM_USE = { Loudness = 0.7, Radius = 40, MinInterval = 2 },
+		DOOR = { Loudness = 0.5, Radius = 30, MinInterval = 2 },
+		SPRINT = { Loudness = 0.6, Radius = 35, MinInterval = 2 },
+	},
+}
+
 local Config = {
 	Round = {
 		Intermission = 25, -- seconds in lobby before a round starts
```

And the alias, in the `Search` block:

```diff
 		RangeStuds = 10,
 
-		-- Studs the noise carries. DELIBERATELY LARGER THAN ANY OTHER RANGE IN THIS FILE — the point is
-		-- that searching summons the monster, not that it might. Compare Tracker.EarlyRadius = 40: a
-		-- searching survivor is louder than the tracker is sharp, for the whole first half of the night.
-		NoiseRadius = 60,
+		--[[
+			V04. AN ALIAS. Tune `Noise.Actions.SEARCH.Radius`; this is §6.5's name for the same number,
+			kept so a reader of the spec's committed Config table still finds it here.
+
+			Studs the noise carries. DELIBERATELY LARGER THAN ANY OTHER RANGE IN THIS FILE — the point
+			is that searching summons the monster, not that it might. Compare Tracker.EarlyRadius = 40:
+			a searching survivor is louder than the tracker is sharp, for the whole first half of the
+			night. That comparison is now an invariant rather than a comment.
+		]]
+		NoiseRadius = Noise.Actions.SEARCH.Radius,
 	},
```

And the block itself joins the returned table, beside `Search`:

```diff
 	Tracker = {
 		EarlyInterval = 90, -- seconds between pings in the first half of the round
```

```diff
+	Noise = Noise,
+
 	--[[
 		V02, §4.6. THE SHARPENING TRACKER — why hiding does not win.
```

#### Step 1.2: Declare `NoiseAction` in `Types.luau`

**File:** `src/shared/Types.luau`
**Verify:** `npm run verify:fast`

The four action ids as a literal union, declared beside `SearchUpdatePayload` — V03's types, and
noise is V03's other half.

**The record shape does NOT go here, and that is a decision rather than an omission.** V03 put
`ContainerLayout.Layout` in the pure module that owns it and had `SearchService` annotate against
`ContainerLayout.Layout?`; the noise record follows that precedent, so `NoiseLog.Record` (Step 2.1)
is the single definition and `Types.luau` holds no second copy to drift from it. It also settles the
`Vector3` question by construction: the record is held by a service **and** by two pure modules
(V04's `NoiseLog`, V13's `TrackerCurve`), and **a pure module cannot see `Vector3` at all** (preamble
P2), so `Position` is `SaltThrow`'s plain `{ X, Y, Z }` and the only conversions are the two inside
`NoiseService`. `NoiseAction` stays here because it is the type of a remote payload field and of a
public service parameter, which is `Types.luau`'s job.

```diff
 	Found: ItemType?,
 }
 
+--[[
+	V04, §4.4. THE FOUR NOISY ACTIONS.
+
+	Only two of them have an emitter in V04, and that is a statement about the GAME rather than about
+	this chunk: `grep -rni door src --include="*.luau"` finds no door, and `grep -rn "Sprint\|Crouch"`
+	finds no movement verb. `NoiseModel` prices all four so the model is decided in one place; the
+	chunk that adds a door adds the call, not the price.
+]]
+export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"
+
 -- What the timeline fires, in order. FIRE-ONCE per session — see `shared/pure/TrialTimeline`.
 export type TrialBeat =
```

#### Step 1.3: Write `NoiseModel` and its action × state grid test

**File:** `src/shared/pure/NoiseModel.luau`
**Verify:** `lune run tests/noise-model.test.luau`

`(action, state, tuning) -> { Loudness, Radius }?`, plus the quantiser the cue needs. The test walks
every action against every speed band and every degenerate input, because that is what the build
plan's Verify line asks for and a smoke test would not survive V16's tuning.

**Two deviations, both deliberate.** (1) The build plan writes the signature as `(action, state)`;
this takes a third `tuning` parameter because a pure module may not `require` `Config` (preamble
P2) and hardcoding the numbers inside it would put them somewhere `check:config` cannot even see
(preamble P3). The caller passes `Config.Noise`. (2) `state` has exactly one field. Every other
candidate — crouching, sneaking, indoors — is a mechanic that does not exist in `src/`, and a flag
nothing can ever set is the speculative generality `lean-code` refuses. **`state` has no role field
and no transformed field, and must never grow one**: a monster whose noise is priced differently is
an oracle with no role token in it for `check:secrecy` to find.

```diff
+--!strict
+--[[
+	NoiseModel — what an action costs in noise. (V04, §4.4)
+
+		evaluate(action, state, tuning) -> { Loudness, Radius } | nil
+		quantise(position, gridStuds) -> position rounded to a grid cell
+
+	§4.4: "The noise is the entire risk economy. It is the loudest thing a survivor does, and it is
+	the thing they must do." This module is the price list. It owns no history, no clock, no Instance
+	and no decision about WHEN a noise happens — `NoiseService` decides that, and `server/pure/
+	NoiseLog` owns the history.
+
+	WHY `src/shared/pure/` IS SAFE HERE, which is a fair question after V03 put `ContainerLayout` in
+	`server/pure/` for the opposite reason. The rule is about INPUTS, not folders. `ContainerLayout`
+	is a draw: a client that can guess the seed replays it and knows where the buntot pagi is before
+	the round starts. This is a table lookup over numbers `Config.luau` already replicates to every
+	client, with no seed and no input a client supplies. A client that requires this module learns
+	that searching is loud, which it learns in one round of play. Logic is not secret; inputs are.
+
+	THERE IS NO ROLE PARAMETER AND NO FORM PARAMETER, and that is structural rather than careful:
+	with no player and no role in the signature there is no arrangement of this module in which two
+	players doing the same thing make different noise. §4.4 requires the Aswang to do everything a
+	survivor does sincerely; `.claude/lessons/absence-is-observable.md` is the long version.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table, converted at the
+	call site exactly as `SaltThrow`'s and `KillValidation`'s are.
+]]
+
+export type Vec3 = { X: number, Y: number, Z: number }
+
+-- Re-declared rather than imported (no `script` under Lune). Luau unions are structural, so this and
+-- `Types.NoiseAction` are the same type and pass to each other without a cast.
+export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"
+
+export type ActionTuning = {
+	Loudness: number,
+	Radius: number,
+	-- Read by NoiseService's throttle, not by this module. Present so one row describes one action.
+	MinInterval: number,
+}
+
+-- `Config.Noise` satisfies this structurally. Keyed by plain `string` because a literal union in a
+-- table-KEY annotation resolves to plain `string` anyway — the C21 lesson's sixth failed fix.
+export type Tuning = {
+	Actions: { [string]: ActionTuning },
+	SprintSpeedStuds: number,
+	CueGridStuds: number,
+}
+
+--[[
+	THE STATE AXIS, AND IT IS ONE FIELD ON PURPOSE. See the plan's Step 1.3 note: crouch, sneak and
+	indoors do not exist in this game, and this field exists only because SPRINT needs a threshold.
+	Nil is a legal value and means "not moving, or the caller does not care" — every non-movement
+	action ignores it entirely, which the test asserts rather than assumes.
+]]
+export type State = {
+	SpeedStuds: number?,
+}
+
+export type Emission = {
+	Loudness: number,
+	Radius: number,
+}
+
+local NoiseModel = {}
+
+-- NaN fails every comparison it is given, so `speed < threshold` would be FALSE for NaN and a NaN
+-- speed would emit. Normalised here once rather than guarded at three comparison sites.
+local function finiteSpeed(value: number?): number
+	if value == nil or value ~= value or value == math.huge or value == -math.huge then
+		return 0
+	end
+
+	return math.max(value, 0)
+end
+
+--[[
+	WHAT THIS ACTION COSTS, or nil for "no noise at all".
+
+	NIL IS A LEGITIMATE ANSWER AND FAILS CLOSED. An action id with no row is silent rather than
+	loud, the same way `AudioCues.isCuePermitted` refuses a cue nobody assigned phases to. The
+	parameter is `string` rather than `NoiseAction` so an unknown id is a normal call with a normal
+	answer, instead of a type error at a call site that got its id off the wire.
+]]
+function NoiseModel.evaluate(action: string, state: State, tuning: Tuning): Emission?
+	-- `: ActionTuning?` is load-bearing under --!strict: indexing a `{ [string]: ActionTuning }`
+	-- yields a NON-optional value, so comparing it to nil is a type error rather than a lookup.
+	local entry: ActionTuning? = tuning.Actions[action]
+
+	if entry == nil then
+		return nil
+	end
+
+	--[[
+		THE ONLY BRANCH THAT READS STATE. Movement below the threshold is silent; everything else
+		ignores speed completely, so a player who searches while walking makes exactly the noise a
+		player who searches standing still makes.
+
+		NO SCALING ABOVE THE THRESHOLD, deliberately: a scaled loudness needs a second number (the
+		speed it saturates at) to feed a verb this game does not have. Flat until there is one.
+	]]
+	if action == "SPRINT" and finiteSpeed(state.SpeedStuds) < tuning.SprintSpeedStuds then
+		return nil
+	end
+
+	-- Clamped rather than trusted. Config is hand-edited during M12/V16 and a negative radius would
+	-- otherwise mean "audible to nobody" in one place and "audible to everybody" in another.
+	return {
+		Loudness = math.clamp(entry.Loudness, 0, 1),
+		Radius = math.max(entry.Radius, 0),
+	}
+end
+
+--[[
+	ROUND A POSITION TO A GRID CELL. What the CUE sends; never what the history stores.
+
+	§4.6 requires the Aswang's information to be an area rather than an address. Without this, a
+	client's audio engine localises a searching survivor to within a stud THROUGH A WALL — strictly
+	better than V13's late-round 15-stud pulse, which would make V04 obsolete the balance-critical
+	chunk of the rewrite before it is written.
+
+	A GRID OF ZERO OR LESS RETURNS THE POSITION UNCHANGED rather than dividing by it. That is the
+	unsafe direction, so `tests/config.test.luau` pins CueGridStuds below Tracker.LateRadius and this
+	returns something usable instead of erroring inside a dispatch loop.
+]]
+function NoiseModel.quantise(position: Vec3, gridStuds: number): Vec3
+	if gridStuds <= 0 then
+		return { X = position.X, Y = position.Y, Z = position.Z }
+	end
+
+	return {
+		X = math.round(position.X / gridStuds) * gridStuds,
+		Y = math.round(position.Y / gridStuds) * gridStuds,
+		Z = math.round(position.Z / gridStuds) * gridStuds,
+	}
+end
+
+return NoiseModel
```

And the grid the build plan's Verify line asks for. `tests/noise-model.test.luau` is new:

```diff
+--!strict
+--[[
+	The noise price list, over its whole domain. (V04, §4.4)
+
+	The build plan asks for "the action x state grid", not a smoke test, and the reason is the same
+	one `monster-health` will have at V05: this module is a small pure function over a BOUNDED
+	domain, which is the one shape where enumerating beats writing a case per bug. There are four
+	actions, one state field and a handful of degenerate values, so the grid is small enough to walk
+	completely — and the two properties that matter (search is the loudest; the sprint threshold
+	holds) are exactly the ones a playtest cannot see.
+]]
+
+local Config = require("../src/shared/Config")
+local NoiseModel = require("../src/shared/pure/NoiseModel")
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+-- A SYNTHETIC tuning, not Config's. These assertions are about the MODEL's rules; V16 will retune
+-- Config and must not be able to red this file. The real block is cross-checked at the bottom.
+local TUNING = {
+	Actions = {
+		SEARCH = { Loudness = 1, Radius = 60, MinInterval = 6 },
+		ITEM_USE = { Loudness = 0.7, Radius = 40, MinInterval = 2 },
+		DOOR = { Loudness = 0.5, Radius = 30, MinInterval = 2 },
+		SPRINT = { Loudness = 0.6, Radius = 35, MinInterval = 2 },
+	},
+	SprintSpeedStuds = 22,
+	CueGridStuds = 8,
+}
+
+local ACTIONS = { "SEARCH", "ITEM_USE", "DOOR", "SPRINT" }
+local STILL = { "SEARCH", "ITEM_USE", "DOOR" }
+-- Zero, a walk, the baseline, a transformed Aswang's 20, either side of the threshold, and the four
+-- values that break a naive comparison.
+local SPEEDS = { 0, 4, 16, 20, 21.9, 22, 22.1, 400, -5, 0 / 0, math.huge, -math.huge }
+
+print("NoiseModel")
+
+-- THE GRID. Every action against every speed, asserting the one invariant that must hold across all
+-- of it: an emission is either nil or a pair of finite, in-range numbers.
+for _, action in ACTIONS do
+	for _, speed in SPEEDS do
+		local result = NoiseModel.evaluate(action, { SpeedStuds = speed }, TUNING)
+
+		if result ~= nil then
+			check(
+				`{action} at {speed}: loudness in 0..1`,
+				result.Loudness >= 0 and result.Loudness <= 1,
+				`{result.Loudness}`
+			)
+			check(`{action} at {speed}: radius not negative`, result.Radius >= 0, `{result.Radius}`)
+		end
+	end
+end
+
+-- SPEED IS IGNORED BY EVERY NON-MOVEMENT ACTION. A search is a search at any speed, and the day this
+-- stops being true is the day "who searched while standing still" becomes a thing to read off noise.
+for _, action in STILL do
+	local base = NoiseModel.evaluate(action, {}, TUNING)
+
+	check(`{action} emits with no state at all`, base ~= nil)
+
+	if base ~= nil then
+		for _, speed in SPEEDS do
+			local moving = NoiseModel.evaluate(action, { SpeedStuds = speed }, TUNING)
+
+			check(
+				`{action} is unchanged at {speed}`,
+				moving ~= nil and moving.Loudness == base.Loudness and moving.Radius == base.Radius
+			)
+		end
+	end
+end
+
+-- THE SPRINT THRESHOLD, at the boundary and on both sides of it, including the values a naive
+-- comparison waves through: NaN fails every comparison, so `nan < threshold` is FALSE and an
+-- unguarded model would emit for it.
+check("sprint is silent below the threshold", NoiseModel.evaluate("SPRINT", { SpeedStuds = 21.9 }, TUNING) == nil)
+check("sprint is silent at a walk", NoiseModel.evaluate("SPRINT", { SpeedStuds = 16 }, TUNING) == nil)
+check("sprint is silent for a transformed monster's speed", NoiseModel.evaluate("SPRINT", { SpeedStuds = 20 }, TUNING) == nil)
+check("sprint is silent with no speed given", NoiseModel.evaluate("SPRINT", {}, TUNING) == nil)
+check("sprint is silent for NaN", NoiseModel.evaluate("SPRINT", { SpeedStuds = 0 / 0 }, TUNING) == nil)
+check("sprint is silent for -inf", NoiseModel.evaluate("SPRINT", { SpeedStuds = -math.huge }, TUNING) == nil)
+check("sprint is silent for a negative speed", NoiseModel.evaluate("SPRINT", { SpeedStuds = -5 }, TUNING) == nil)
+check("sprint emits at the threshold", NoiseModel.evaluate("SPRINT", { SpeedStuds = 22 }, TUNING) ~= nil)
+check("sprint emits above it", NoiseModel.evaluate("SPRINT", { SpeedStuds = 400 }, TUNING) ~= nil)
+
+-- FAILS CLOSED. An id with no row is silent, not loud.
+check("an unknown action is silent", NoiseModel.evaluate("SHOUT", { SpeedStuds = 0 }, TUNING) == nil)
+check("an empty action is silent", NoiseModel.evaluate("", { SpeedStuds = 0 }, TUNING) == nil)
+
+-- §4.4: searching is the loudest thing a survivor does. Asserted here over the MODEL's output as
+-- well as over Config, because the model is what a caller sees.
+local search = NoiseModel.evaluate("SEARCH", {}, TUNING)
+
+check("SEARCH emits", search ~= nil)
+
+if search ~= nil then
+	for _, action in ACTIONS do
+		local other = NoiseModel.evaluate(action, { SpeedStuds = 400 }, TUNING)
+
+		if other ~= nil then
+			check(`SEARCH is at least as loud as {action}`, search.Loudness >= other.Loudness)
+			check(`SEARCH carries at least as far as {action}`, search.Radius >= other.Radius)
+		end
+	end
+end
+
+-- Clamping, proven with a tuning nobody would write on purpose but M12 could typo.
+local absurd = {
+	Actions = { SEARCH = { Loudness = 9, Radius = -3, MinInterval = 1 } },
+	SprintSpeedStuds = 22,
+	CueGridStuds = 8,
+}
+local clamped = NoiseModel.evaluate("SEARCH", {}, absurd)
+
+check("loudness is clamped to 1", clamped ~= nil and clamped.Loudness == 1)
+check("a negative radius clamps to 0", clamped ~= nil and clamped.Radius == 0)
+
+-- THE QUANTISER. Every output lands on a grid cell, within half a cell of the truth, and two points
+-- inside one cell are indistinguishable — which is the property §4.6 is actually asking for.
+local POINTS = { 0, 0.1, 3.9, 4, 4.1, 12, -3.9, -4.1, 137.25 }
+
+for _, x in POINTS do
+	local q = NoiseModel.quantise({ X = x, Y = x, Z = x }, TUNING.CueGridStuds)
+
+	check(`{x} lands on the grid`, q.X % TUNING.CueGridStuds == 0, `{q.X}`)
+	check(
+		`{x} moves less than a cell`,
+		math.abs(q.X - x) <= TUNING.CueGridStuds / 2,
+		`{q.X}`
+	)
+	check(`{x} quantises all three axes alike`, q.X == q.Y and q.Y == q.Z)
+end
+
+local a = NoiseModel.quantise({ X = 1, Y = 1, Z = 1 }, 8)
+local b = NoiseModel.quantise({ X = 2.5, Y = 2.5, Z = 2.5 }, 8)
+
+check("two points in one cell are indistinguishable", a.X == b.X and a.Z == b.Z)
+
+local ungridded = NoiseModel.quantise({ X = 3, Y = 3, Z = 3 }, 0)
+
+check("a zero grid returns the position unchanged", ungridded.X == 3)
+
+--[[
+	THE CROSS-CHECK. Everything above runs on a synthetic tuning so V16 can retune freely — but a
+	MISSING ROW in the real block would then go unnoticed until a live search made no noise, which is
+	a silent failure with no symptom except that the game got easier.
+]]
+for _, action in ACTIONS do
+	check(
+		`Config.Noise prices {action}`,
+		NoiseModel.evaluate(action, { SpeedStuds = 999 }, Config.Noise) ~= nil
+	)
+end
+
+print(`  {checked - failures}/{checked} checks passed`)
+
+if failures > 0 then
+	error(`{failures} NoiseModel check(s) failed`, 0)
+end
```

#### Step 1.4: Pin the noise invariants in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

Eight relationships that fail silently: searching is the loudest thing a survivor does, the history
outlives the first tracker pulse, the cap can never truncate the window, earshot always beats a
pulse, and no speed this game can currently produce crosses the sprint threshold.

The last one is the anti-oracle guard from Step 1.1 made mechanical. §6.5's list has six numbered
invariants and V04 adds none to the spec — these are the same *kind* of relationship (§6.5: "silent
invariants; no symptom tells you when two numbers that must agree have stopped agreeing") applied to
a block the spec's table does not have. Appended after V03's search invariants, before the
`if failures > 0` guard.

```diff
 -- V03. A radius of zero or less is unsearchable and would read as a dead key bind.
 check(
 	"a container can actually be reached",
 	Config.Search.RangeStuds > 0,
 	`RangeStuds={Config.Search.RangeStuds}`
 )
 
+--[[
+	V04, §4.4. THE NOISE BLOCK. Six of these eight guard things with no symptom: a tracker that reads
+	an empty window, a cap that silently truncates one, a cue more precise than the pulse it is meant
+	to be worse than, and a movement threshold that would turn V13's only input into a monster
+	tracker.
+]]
+
+-- §4.4: "it is the loudest thing a survivor does". If a V16 tune inverts this, searching stops being
+-- the risk the whole economy is built on and nothing in the game says so.
+for action, tuning in Config.Noise.Actions do
+	check(
+		`searching is at least as loud as {action}`,
+		Config.Noise.Actions.SEARCH.Loudness >= tuning.Loudness,
+		`SEARCH={Config.Noise.Actions.SEARCH.Loudness}, {action}={tuning.Loudness}`
+	)
+	check(
+		`searching carries at least as far as {action}`,
+		Config.Noise.Actions.SEARCH.Radius >= tuning.Radius,
+		`SEARCH={Config.Noise.Actions.SEARCH.Radius}, {action}={tuning.Radius}`
+	)
+	-- The bound proof below divides by the smallest of these. Zero would make it meaningless AND
+	-- would let one player fill the history on their own.
+	check(`{action} has a throttle`, tuning.MinInterval > 0, `{tuning.MinInterval}`)
+end
+
+-- Config.Search's own comment has claimed this since V02 ("a searching survivor is louder than the
+-- tracker is sharp, for the whole first half of the night"). A comment is not a check.
+check(
+	"a search is louder than the early tracker is sharp",
+	Config.Noise.Actions.SEARCH.Radius > Config.Tracker.EarlyRadius,
+	`Radius={Config.Noise.Actions.SEARCH.Radius}, EarlyRadius={Config.Tracker.EarlyRadius}`
+)
+
+-- One search, one noise. Below this, tapping the search key faster than the hold lasts buys extra
+-- noise events per search, which is both a history flood and a way to fake activity in a corner.
+check(
+	"a search cannot be louder than once per search",
+	Config.Noise.Actions.SEARCH.MinInterval >= Config.Search.SearchTime,
+	`MinInterval={Config.Noise.Actions.SEARCH.MinInterval}, SearchTime={Config.Search.SearchTime}`
+)
+
+-- V13's first pulse fires at Tracker.EarlyInterval and reads this history and NOTHING ELSE. A
+-- shorter window means the first pulse of every round reads an empty table.
+check(
+	"the noise history outlives the first tracker pulse",
+	Config.Noise.HistorySeconds >= Config.Tracker.EarlyInterval,
+	`HistorySeconds={Config.Noise.HistorySeconds}, EarlyInterval={Config.Tracker.EarlyInterval}`
+)
+
+--[[
+	THE BOUND, PROVEN RATHER THAN ASSERTED. Age is what bounds the history; MaxRecords is a safety
+	net. If the net is tighter than the worst case the throttles allow, it silently starts trimming
+	the WINDOW instead — the tracker goes blind on the early round and nothing reports it.
+]]
+local shortestInterval = math.huge
+
+for _, tuning in Config.Noise.Actions do
+	shortestInterval = math.min(shortestInterval, tuning.MinInterval)
+end
+
+local worstCaseRecords = Config.Round.MaxPlayers * (Config.Noise.HistorySeconds / shortestInterval)
+
+check(
+	"the record cap can never truncate the history window",
+	Config.Noise.MaxRecords >= worstCaseRecords,
+	`MaxRecords={Config.Noise.MaxRecords}, worst case={worstCaseRecords}`
+)
+
+-- §4.6: the pulse reveals an area, never an address. Being in EARSHOT should always beat the pulse,
+-- and the cue's grid is what keeps it from being an address instead.
+check(
+	"the cue is coarse enough to stay an area",
+	Config.Noise.CueGridStuds > 0 and Config.Noise.CueGridStuds < Config.Tracker.LateRadius,
+	`CueGridStuds={Config.Noise.CueGridStuds}, LateRadius={Config.Tracker.LateRadius}`
+)
+
+--[[
+	THE ANTI-ORACLE GUARD. No sprint verb exists; the only thing above the 16-stud baseline is a
+	TRANSFORMED ASWANG. If a movement emitter is ever wired with a threshold under that, V13's only
+	input becomes a monster tracker pointed at the monster — a leak with no role token in it, which
+	`check:secrecy` structurally cannot see.
+]]
+check(
+	"no speed this game can produce crosses the sprint threshold",
+	Config.Noise.SprintSpeedStuds
+		> Config.Trial.PlayerBaselineWalkSpeed * Config.Monster.TransformedSpeedMult,
+	`SprintSpeedStuds={Config.Noise.SprintSpeedStuds}, fastest=`
+		.. `{Config.Trial.PlayerBaselineWalkSpeed * Config.Monster.TransformedSpeedMult}`
+)
+
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing here touches a player. The one thing to refuse is a `Role`, `Aswang`
  or `Transformed` field creeping into `NoiseModel.State` or `Types.NoiseRecord`; both are commented
  against it, and both are the shape `check:secrecy` cannot see.
- **Remote direction / rate limiting** — no remote and no handler in this phase.
- **Magic numbers** — `check:config` does **not** scan `src/shared/` (preamble P3), so nothing
  mechanical stops a number being typed into `NoiseModel.luau`. The `tuning` parameter is what keeps
  them in `Config`; a number appearing in that module is a review failure, not a check failure.
- **Phase ownership** — nothing here reads or sets a phase.
- **Strict Luau** — `tuning.Actions[action]` yields a NON-optional `ActionTuning` under `--!strict`,
  so the `local entry: ActionTuning? =` annotation is required before comparing it to nil.
  `Types.NoiseRecord.Action` is a scalar union and crosses `require` intact; do not put an `Action`
  field on `Emission`, where it would arrive as plain `string` (preamble P4).
- **Mobile budget** — nothing drawn, nothing played, nothing per-frame.
- **Scope** — no §3 OUT token. "Noise" is §4.4's own word.

**Issues identified:**

- **Format after writing.** Several `check(...)` calls in the two test files sit near the 100-column
  limit and StyLua will rewrap them. `lune run` does not care, but `npm run verify` in Phase 3 runs
  `fmt:check` — run `npm run fmt` at the end of this phase rather than debugging a red gate two
  phases later.
- **`Noise` must be added to the returned table, not just declared as a local.** `local Noise = {…}`
  alone type-checks and leaves `Config.Noise` nil at every reader; the failure would surface in
  Phase 2 as a runtime nil rather than as an analyze error. Step 1.4's suite is what catches it here,
  because it reads `Config.Noise.Actions` directly.
- **`math.round` rounds halves away from zero**, so `quantise` maps `4` to `8` and `-4` to `-8` at a
  grid of 8. That is a boundary, not a bug, and the test pins the property that matters (every
  output lands on a cell, no output moves more than half a cell).
- **The sprint threshold has no emitter and must keep none in this chunk.** If implementing Phase 1
  makes a movement emitter look like a two-line addition, re-read the Overview's question 2: it is
  the one addition in V04 that hands the round away.

### Phase 2: The recorder

The server-only history, bounded, with the query V13 will call and nothing that resembles a tracker.

#### Step 2.1: Write `NoiseLog` and its test

**File:** `src/server/pure/NoiseLog.luau`
**Verify:** `lune run tests/noise-log.test.luau`

Append-with-prune, the per-actor throttle predicate, the recency window and the radius test — all
pure, all over plain tables, so "bounded" is a proven property rather than a claim in a comment.

**In `server/pure/`, not `shared/pure/`** — the mirror of `NoiseModel`'s placement (preamble P1).
`NoiseModel` is a price list `Config` already replicates; this is the machinery around server-only
state with no client caller now or ever, so the smaller surface costs nothing. Lune resolves by file
path and cares nothing for Rojo, so the test is unaffected. `ContainerLayout` is the precedent.

**The bound is two mechanisms and only one of them is the bound.** Age is what makes the history
correct — V13 wants recent noise, and a record from four minutes ago is a lie about where anyone is.
The count cap is a safety net against an emit rate the throttles should already have made
impossible, and Step 1.4 pins it above that worst case so it can never be the thing doing the
trimming. Both are needed: age alone is unbounded if a bug removes a throttle, and a cap alone would
hand V13 a window whose length depends on how busy the round is.

```diff
+--!strict
+--[[
+	NoiseLog — the bounded history, and nothing that reads it. (V04, §4.4)
+
+		shouldRecord(lastAt, now, minInterval) -> boolean
+		append(records, record, limits)        -> a NEW pruned list
+		recentSince(records, now, within)      -> a COPY of the recent tail
+		withinRadius(a, b, radius)             -> boolean
+
+	SERVER-ONLY BY PLACEMENT, and that is the mirror image of `shared/pure/NoiseModel`'s. The model
+	is a price list over numbers `Config` already replicates to every client, so publishing it costs
+	nothing. This is the machinery around state that never leaves the server and has no client caller
+	now or ever, so `server/pure/` is free. `ContainerLayout` sits here for the sharper version of the
+	same reason. Lune resolves by file path, so the suite is identical either way.
+
+	IT KNOWS NOTHING ABOUT WHO. There is no UserId in `Record` and no parameter that carries one —
+	the throttle predicate takes a TIMESTAMP, and the caller owns the per-actor table that produced
+	it. V13's tracker reads these records and cannot leak an identity that was never written down.
+
+	ORDER IS AN ASSUMPTION AND IT IS A SAFE ONE: `records` is ascending by `At`, because `append` is
+	the only writer and `os.clock()` is monotonic. Both prunes rely on it.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table (preamble P2).
+]]
+
+export type Vec3 = { X: number, Y: number, Z: number }
+
+-- Structurally `Types.NoiseRecord`. `Action` is a plain `string` here rather than the literal union:
+-- an element of a LIST arrives at the call site widened, so the union belongs at the boundary that
+-- can enforce it — `.claude/lessons/pure-module-unions-widen-in-lists.md`.
+export type Record = {
+	Action: string,
+	Loudness: number,
+	Radius: number,
+	Position: Vec3,
+	At: number,
+}
+
+export type Limits = {
+	HistorySeconds: number,
+	MaxRecords: number,
+}
+
+local NoiseLog = {}
+
+local function copyRecord(record: Record): Record
+	return {
+		Action = record.Action,
+		Loudness = record.Loudness,
+		Radius = record.Radius,
+		Position = { X = record.Position.X, Y = record.Position.Y, Z = record.Position.Z },
+		At = record.At,
+	}
+end
+
+--[[
+	HAS THIS ACTOR BEEN QUIET LONG ENOUGH FOR THIS ACTION TO COUNT AGAIN?
+
+	This is the anti-spam guard, and V04 has no other one: no client remote is added, so
+	AntiCheatService never sees a noise. A player tapping the search key start/cancel/start still
+	makes exactly one search's worth of noise, which is what Step 1.4's SearchTime invariant pins.
+
+	A CLOCK THAT WENT BACKWARDS REFUSES rather than allowing. `os.clock()` will not do that on one
+	server, but the failure direction matters: refusing costs one noise event, allowing costs the
+	bound.
+]]
+function NoiseLog.shouldRecord(lastAt: number?, now: number, minInterval: number): boolean
+	if lastAt == nil then
+		return true
+	end
+
+	local elapsed = now - lastAt
+
+	if elapsed < 0 then
+		return false
+	end
+
+	return elapsed >= minInterval
+end
+
+--[[
+	APPEND, PRUNE BY AGE, THEN CAP. Returns a NEW list; the input is never mutated, so a caller
+	holding the old one holds a consistent snapshot rather than a half-pruned table.
+
+	AGE IS THE BOUND AND THE CAP IS THE NET. If the cap is ever doing the trimming, the window V13
+	reads has silently become shorter than `HistorySeconds` and the tracker goes blind on the early
+	round with no symptom — `tests/config.test.luau` pins the cap above the worst case the throttles
+	allow, precisely so this branch is unreachable in a healthy build.
+
+	THE NEW RECORD IS ALWAYS KEPT. A cap of zero keeps one rather than discarding what it was asked
+	to store, because "you told me to record this and I dropped it" is the harder failure to see.
+]]
+function NoiseLog.append(records: { Record }, record: Record, limits: Limits): { Record }
+	local cutoff = record.At - limits.HistorySeconds
+	local kept: { Record } = {}
+
+	for _, existing in records do
+		if existing.At >= cutoff then
+			table.insert(kept, existing)
+		end
+	end
+
+	table.insert(kept, record)
+
+	local capacity = math.max(limits.MaxRecords, 1)
+	local overflow = #kept - capacity
+
+	if overflow > 0 then
+		-- Shift the survivors down, then clear the tail. Oldest-first is the only defensible drop:
+		-- the newest noise is the one V13 is about to ask about.
+		table.move(kept, overflow + 1, #kept, 1)
+
+		for index = #kept, capacity + 1, -1 do
+			kept[index] = nil
+		end
+	end
+
+	return kept
+end
+
+--[[
+	THE QUERY V13 IS BUILT ON. Returns COPIES, for `AudioCues.oneShotsFor`'s reason: a caller that
+	sorted, cleared or edited the result in place would silently rewrite the server's own history,
+	and a tracker is exactly the kind of consumer that wants to sort what it was handed.
+]]
+function NoiseLog.recentSince(records: { Record }, now: number, withinSeconds: number): { Record }
+	local cutoff = now - withinSeconds
+	local recent: { Record } = {}
+
+	for _, record in records do
+		if record.At >= cutoff then
+			table.insert(recent, copyRecord(record))
+		end
+	end
+
+	return recent
+end
+
+--[[
+	IS `b` INSIDE THE NOISE AT `a`? Squared magnitudes, so no square root runs per listener per
+	noise. INCLUSIVE at the boundary, matching `SearchService.nearestContainer`'s `<=`.
+
+	A RADIUS OF ZERO OR LESS IS AUDIBLE TO NOBODY. Without the guard a negative radius squares to a
+	positive one and a silent action would be heard by everyone standing on top of it.
+]]
+function NoiseLog.withinRadius(a: Vec3, b: Vec3, radius: number): boolean
+	if radius <= 0 then
+		return false
+	end
+
+	local dx = a.X - b.X
+	local dy = a.Y - b.Y
+	local dz = a.Z - b.Z
+
+	return dx * dx + dy * dy + dz * dz <= radius * radius
+end
+
+return NoiseLog
```

`tests/noise-log.test.luau` is new, and the flood case is the one that matters — "bounded" is a
claim until something floods it:

```diff
+--!strict
+--[[
+	The noise history's bound, proven. (V04, §4.4)
+
+	The build plan's Done line says the history is "server-only and bounded". Server-only is a
+	placement and a code review; BOUNDED is arithmetic, and this is where it is checked — including
+	the case the service should never produce, because the reason to have a cap at all is the day
+	something removes a throttle.
+]]
+
+local NoiseLog = require("../src/server/pure/NoiseLog")
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local LIMITS = { HistorySeconds = 120, MaxRecords = 512 }
+
+local function recordAt(at: number, x: number): NoiseLog.Record
+	return {
+		Action = "SEARCH",
+		Loudness = 1,
+		Radius = 60,
+		Position = { X = x, Y = 0, Z = 0 },
+		At = at,
+	}
+end
+
+print("NoiseLog")
+
+-- THE THROTTLE.
+check("a first noise always records", NoiseLog.shouldRecord(nil, 100, 6))
+check("a noise inside the interval is refused", not NoiseLog.shouldRecord(100, 105.9, 6))
+check("a noise exactly at the interval records", NoiseLog.shouldRecord(100, 106, 6))
+check("a noise after the interval records", NoiseLog.shouldRecord(100, 400, 6))
+check("a backwards clock refuses", not NoiseLog.shouldRecord(100, 99, 6))
+check("a zero interval never refuses", NoiseLog.shouldRecord(100, 100, 0))
+
+-- APPEND DOES NOT MUTATE ITS INPUT.
+local original = { recordAt(1, 0) }
+local grown = NoiseLog.append(original, recordAt(2, 0), LIMITS)
+
+check("append leaves the input alone", #original == 1)
+check("append returns the longer list", #grown == 2)
+
+-- AGE PRUNING. A record older than the window is gone; one exactly at the edge is kept.
+local aged = NoiseLog.append({ recordAt(0, 0), recordAt(10, 0) }, recordAt(121, 0), LIMITS)
+
+check("a record past the window is dropped", #aged == 2)
+check("the survivors stay in order", aged[1].At == 10 and aged[2].At == 121)
+
+local edge = NoiseLog.append({ recordAt(1, 0) }, recordAt(121, 0), LIMITS)
+
+check("a record exactly at the window edge is kept", #edge == 2)
+
+--[[
+	THE FLOOD. Ten noises a second for ten minutes — an emit rate the throttles make impossible,
+	which is exactly the case the cap exists for. The history must stay capped AND stay recent.
+]]
+local history: { NoiseLog.Record } = {}
+local ceiling = 0
+
+for step = 1, 6000 do
+	history = NoiseLog.append(history, recordAt(step / 10, 0), LIMITS)
+	ceiling = math.max(ceiling, #history)
+end
+
+check("the flood never exceeds the cap", ceiling <= LIMITS.MaxRecords, `peak={ceiling}`)
+check("the flood keeps the newest record", history[#history].At == 600)
+check(
+	"nothing older than the window survives",
+	history[1].At >= 600 - LIMITS.HistorySeconds,
+	`oldest={history[1].At}`
+)
+
+-- A CAP THAT CANNOT HOLD ANYTHING STILL HOLDS THE NEW RECORD.
+local squeezed = NoiseLog.append({ recordAt(1, 0) }, recordAt(2, 0), {
+	HistorySeconds = 120,
+	MaxRecords = 0,
+})
+
+check("a zero cap still records the newest", #squeezed == 1 and squeezed[1].At == 2)
+
+-- THE WINDOW QUERY, INCLUDING THE COPY. A tracker will sort what it is handed.
+local queried = NoiseLog.recentSince({ recordAt(10, 0), recordAt(90, 0) }, 100, 30)
+
+check("only the recent tail comes back", #queried == 1 and queried[1].At == 90)
+check("an empty window is empty, not nil", #NoiseLog.recentSince({}, 100, 30) == 0)
+
+local source = { recordAt(90, 5) }
+local handed = NoiseLog.recentSince(source, 100, 30)
+
+handed[1].Position.X = 999
+handed[1].At = 0
+
+check("the query returns copies", source[1].Position.X == 5 and source[1].At == 90)
+
+-- EARSHOT. Inclusive at the boundary, and silent for a radius that is not one.
+local here = { X = 0, Y = 0, Z = 0 }
+
+check("a listener on top of it hears", NoiseLog.withinRadius(here, here, 60))
+check("a listener exactly at the radius hears", NoiseLog.withinRadius(here, { X = 60, Y = 0, Z = 0 }, 60))
+check("a listener past it does not", not NoiseLog.withinRadius(here, { X = 60.1, Y = 0, Z = 0 }, 60))
+check("height counts", not NoiseLog.withinRadius(here, { X = 0, Y = 61, Z = 0 }, 60))
+check("a zero radius reaches nobody", not NoiseLog.withinRadius(here, here, 0))
+check("a negative radius reaches nobody", not NoiseLog.withinRadius(here, here, -60))
+
+print(`  {checked - failures}/{checked} checks passed`)
+
+if failures > 0 then
+	error(`{failures} NoiseLog check(s) failed`, 0)
+end
```

#### Step 2.2: Write `NoiseService` and register it in the bootstrap

**File:** `src/server/Services/NoiseService.luau`
**Verify:** `npm run check:config`

`Emit(actor, action, position, state)`, the record table, the throttle table, the phase subscription.
Registered in `SERVICE_ORDER` before `RoundService`, for the reason `SearchService`'s entry gives.

**The actor is a parameter and never a field.** `Emit` needs to know who acted for exactly two
reasons — to throttle them, and (Phase 4) to mark their own cue `Mine` — and neither of those
survives the call. The record it writes has no actor, by construction rather than by discipline.

This service is a leaf: it requires `RoundService` and two pure modules, and nothing requires it back
except its two callers in Phase 3. `check:config` is the verify because every number in a service is
a `check:config` finding, and this file is where the temptation to type `120` lives.

```diff
+--!strict
+--[[
+	NoiseService — every noisy action, priced, recorded and bounded. (V04, §4.4)
+
+	Milestone: V04. Spec: docs/MVP-SPEC.md §4.4, §4.6, §6.2.
+
+	§4.4: "The noise is the entire risk economy. You cannot arm yourself quietly, you cannot be safe
+	and productive at the same time, and every search is a decision you made." Three things happen
+	here and each is server-decided:
+
+	  · a caller says an action HAPPENED, and this file prices it        (shared/pure/NoiseModel)
+	  · the actor is throttled so one action is one noise                (server/pure/NoiseLog)
+	  · the event is appended to a bounded, server-only history          (V13 reads it, nobody else)
+
+	THE HISTORY NEVER CROSSES THE WIRE AND NEVER REACHES A LOG. Not as a payload, not as an
+	attribute, not as a tag. The log rule is SearchService's and it is the less obvious half: in a
+	Studio solo test the server and client share one output window, so printing where a noise
+	happened puts every other player's position in front of the person playing. Log COUNTS and
+	ACTIONS, never positions.
+
+	THERE IS NO ACTOR IN A RECORD. `Emit` takes one — to throttle them, and to mark their own cue —
+	and it does not survive the call. V13's pulse is built on these records and cannot leak an
+	identity that was never written down (§4.6: an area, never an address). Adding a UserId here is a
+	spec conversation, not an implementation detail.
+
+	NO BRANCH IN THIS FILE READS A ROLE. `RoundService.GetAswangUserId` must not appear in it. §4.4
+	requires the Aswang to search, and be heard searching, on identical terms — any activity it
+	cannot perform sincerely becomes an oracle that identifies it, and a noise system with a monster
+	exemption is the loudest possible version of that.
+
+	ROUNDSERVICE OWNS THE PHASE (§6.4). This service subscribes and never calls setPhase.
+
+	V13 CONNECTS THROUGH `GetRecent` AND NOTHING ELSE. There is no tracker logic here, no curve, no
+	pulse and no timer — see that function's comment.
+]]
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local RoundService = require(script.Parent.RoundService)
+local NoiseLog = require(script.Parent.Parent.pure.NoiseLog)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local NoiseModel = require(Shared.pure.NoiseModel)
+local Types = require(Shared.Types)
+
+local NoiseService = {}
+
+--------------------------------------------------------------------------------
+-- SERVER-ONLY state. None of this replicates. None of it is logged in full.
+--------------------------------------------------------------------------------
+
+-- Ascending by `At`; `NoiseLog.append` is the only writer and rebuilds it pruned every time.
+local history: { NoiseLog.Record } = {}
+
+--[[
+	UserId -> action -> the os.clock() of their last recorded noise of that action.
+
+	THE ONE PLACE AN ACTOR IS ASSOCIATED WITH A NOISE, and it is transient, per-action, never
+	written into a record and never read by anything but the throttle three lines below. Keyed by
+	action rather than by player alone so that using an item does not silence a search.
+]]
+local lastEmitAt: { [number]: { [string]: number } } = {}
+
+local function limits(): NoiseLog.Limits
+	return {
+		HistorySeconds = Config.Noise.HistorySeconds,
+		MaxRecords = Config.Noise.MaxRecords,
+	}
+end
+
+--[[
+	AN ACTION HAPPENED. The caller has already decided that it did — this file prices it and records
+	it, and refuses nothing except a phase, a silent action and a throttled repeat.
+
+	`actor` IS OPTIONAL because not every noise has one: a door swinging shut behind somebody is the
+	obvious future case. A nil actor is unthrottled and gets no `Mine` cue, so a caller passing nil
+	for a player-caused noise is handing away both the bound and the feedback — pass the player.
+
+	ACTIVE ONLY. Searching is an ACTIVE-phase activity (SearchService) and a noise recorded during
+	INTERMISSION would be a record V13 reads before the round it belongs to has started. The gate is
+	here rather than at each caller so a future emitter cannot forget it.
+]]
+function NoiseService.Emit(
+	actor: Player?,
+	action: Types.NoiseAction,
+	position: Vector3,
+	state: NoiseModel.State?
+)
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return
+	end
+
+	local emission = NoiseModel.evaluate(action, state or {}, Config.Noise)
+
+	-- nil means "this action makes no noise at all" — an unpriced action, or movement below the
+	-- sprint threshold. Silent is the fail-closed direction.
+	if emission == nil then
+		return
+	end
+
+	local now = os.clock()
+
+	if actor ~= nil then
+		-- `: ActionTuning?` for SearchService's reason: indexing a `{ [string]: T }` yields a
+		-- NON-optional value under --!strict, so comparing it to nil is a type error, not a lookup.
+		local tuning: NoiseModel.ActionTuning? = Config.Noise.Actions[action]
+		local perAction = lastEmitAt[actor.UserId]
+
+		if perAction == nil then
+			perAction = {}
+			lastEmitAt[actor.UserId] = perAction
+		end
+
+		if tuning ~= nil and not NoiseLog.shouldRecord(perAction[action], now, tuning.MinInterval) then
+			return
+		end
+
+		perAction[action] = now
+	end
+
+	local record: NoiseLog.Record = {
+		Action = action,
+		Loudness = emission.Loudness,
+		Radius = emission.Radius,
+		-- The one Vector3 -> Vec3 conversion in the system. Everything downstream of here is plain
+		-- tables, so both pure modules and V13 can hold it (preamble P2).
+		Position = { X = position.X, Y = position.Y, Z = position.Z },
+		At = now,
+	}
+
+	history = NoiseLog.append(history, record, limits())
+
+	if Config.Debug.VerboseLogging then
+		-- COUNTS AND ACTIONS, NEVER POSITIONS. See the header: in a Studio solo test this window is
+		-- in front of the player, and a position is somebody else's location.
+		print(`[NoiseService] {action} recorded — {#history} in history.`)
+	end
+end
+
+--------------------------------------------------------------------------------
+-- Phase subscription. RoundService owns the phase; this only reacts to it.
+--------------------------------------------------------------------------------
+
+local function clearHistory()
+	table.clear(history)
+	table.clear(lastEmitAt)
+end
+
+--[[
+	EVERY PHASE THAT IS NOT ACTIVE CLEARS EVERYTHING, and it is one rule with no exceptions on
+	purpose. SearchService keeps its layout through ENDING because the end screen runs for
+	Config.Round.EndScreen seconds and something might still read it; nothing reads noise at ENDING,
+	and a record surviving into the next round is a ghost the tracker would treat as live.
+]]
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase ~= Enums.RoundPhase.Active then
+		clearHistory()
+	end
+end
+
+function NoiseService.Init()
+	clearHistory()
+end
+
+function NoiseService.Start()
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	--[[
+		A departing player's throttle goes with them. Their RECORDS STAY and age out normally: the
+		noise happened, and a history that forgot a leaver's noise would make "somebody left" visible
+		to whatever reads it.
+	]]
+	Players.PlayerRemoving:Connect(function(player: Player)
+		lastEmitAt[player.UserId] = nil
+	end)
+end
+
+return NoiseService
```

Registered between the two services that call it. The list governs `Init`/`Start` only — both
callers hold a module reference from their own `require` at load — but it must `Start` before
`RoundService` can fire a phase change, for the reason `SearchService`'s own entry gives:

```diff
 	"RoleService",
 	"MonsterService",
+	--[[
+		V04. BEFORE its two callers (ItemService, SearchService) and, like every gameplay service
+		here, before RoundService — which starts last precisely so every subscriber is connected
+		before a phase can change. A NoiseService that started afterwards could miss the transition
+		that clears the previous round's history, and the symptom would be a V13 pulse pointing at
+		where somebody stood last round.
+
+		It requires RoundService and neither of its callers, and nothing requires it back, so no
+		cycle.
+	]]
+	"NoiseService",
 	"ItemService",
```

#### Step 2.3: Expose the V13 consumer API

**File:** `src/server/Services/NoiseService.luau`
**Verify:** `npm run verify:fast`

`GetRecent` and `RecordCount`, returning copies, with the contract V13 is expected to build against
written into the header — including why there is no actor field and why V13 must not add one.

**This is the whole of V04's answer to "what shape does V13 need".** Two functions, one of which is
a count for a log line. Everything the tracker does with what it gets — the 90s/40-stud to
30s/15-stud interpolation, the clustering, the pulse — is V13's, and none of it appears here. A
`GetPulseArea()` on this service would be V13 written early, in the wrong file, without its test.

```diff
 	if Config.Debug.VerboseLogging then
 		print(`[NoiseService] {action} recorded — {#history} in history.`)
 	end
 end
 
+--------------------------------------------------------------------------------
+-- THE V13 SEAM, and V04 connects nothing to it.
+--------------------------------------------------------------------------------
+
+--[[
+	THE NOISE OF THE LAST `withinSeconds` SECONDS, newest last. COPIES — mutate what you are handed
+	and the server's history is unaffected (`AudioCues.oneShotsFor`'s rule, and a tracker is exactly
+	the sort of caller that will want to sort its input).
+
+	V13 IS THE ONLY INTENDED CALLER AND THIS IS ITS ONLY INPUT (build plan V13: "Input is ONLY V04's
+	noise history. No position feed, no live tracking."). Three properties are being handed over
+	deliberately and V13 must not undo any of them:
+
+	  · NO ACTOR. Nothing here says who made a noise, so no pulse can name a player however it is
+	    written. §4.6: the pulse reveals an AREA and never an address.
+	  · NO ROLE AND NO FORM. The Aswang's own noise is in here on identical terms, so a pulse may
+	    well point at the monster's own footsteps. That is CORRECT: it costs the Aswang nothing (it
+	    knows where it has been) and it is what lets the history stay identity-free. Filtering it out
+	    would require knowing who acted, which is the one field this design refuses.
+	  · WINDOW, NOT STREAM. There is no event, no signal and no per-frame push, because "vague and
+	    slow, never live" is the constraint that keeps the Aswang blending in rather than walking to
+	    pings.
+
+	NEVER FIRE THIS AT A CLIENT. Not the list, not a length, not a filtered copy. `Radius` and
+	`Loudness` are already public (they are Config); `Position` and `At` are not, and the pair is a
+	live map of where every player has been.
+
+	`{ NoiseLog.Record }` RATHER THAN A LIST OF THE LITERAL UNION, and the annotation is the lesson:
+	a literal union does not survive `require` inside a LIST, the element arrives widened to plain
+	`string`, and `::` distributes over the union and fails at the CALL SITE with an error that names
+	the wrong file. Narrow `Action` with a lookup — `Config.Noise.Actions[record.Action]` returns nil
+	for an id nobody priced. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.
+]]
+function NoiseService.GetRecent(withinSeconds: number): { NoiseLog.Record }
+	return NoiseLog.recentSince(history, os.clock(), withinSeconds)
+end
+
+-- How many events the history is holding. For a log line and for a playtester who needs to prove
+-- "bounded" from the server side; it says nothing about who or where.
+function NoiseService.RecordCount(): number
+	return #history
+end
+
 --------------------------------------------------------------------------------
 -- Phase subscription. RoundService owns the phase; this only reacts to it.
 --------------------------------------------------------------------------------
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the whole phase is one long answer to this. `NoiseLog.Record` has no actor,
  `lastEmitAt` never reaches a record, `GetRecent` is never fired at a client, and no attribute or
  tag is written anywhere (both replicate to every client; there is no private one). The log line
  prints an action and a count, never a position.
- **Remote direction / rate limiting** — still no remote and no `OnServerEvent` handler, so
  `check:ratelimit` has nothing to see. `MinInterval` is the throttle that replaces one, and it is
  server-side by construction because the client never asks for a noise.
- **Magic numbers** — `check:config` **does** scan `src/server/`, so both new files are covered. The
  `limits()` helper exists so `HistorySeconds`/`MaxRecords` are read rather than repeated.
- **Phase ownership** — `NoiseService` subscribes to `RoundService.PhaseChanged` and never calls
  `setPhase`. `Emit` reads `GetPhase()` and refuses outside `ACTIVE`.
- **Player leaving mid-round** — `PlayerRemoving` clears the leaver's throttle entry; without it
  `lastEmitAt` grows for the life of the server. Their records deliberately stay.
- **Strict Luau** — `Config.Noise.Actions[action]` needs the `: NoiseModel.ActionTuning?` annotation
  before a nil comparison. `GetRecent` returns `{ NoiseLog.Record }` and **must not** be annotated as
  a list of the literal union (preamble P4).
- **Mobile budget** — no Instance, no per-frame work. `append` allocates one array per emit, at most
  a few per second, and `recentSince` allocates once per V13 pulse.
- **Scope** — no §3 OUT token. No tracker logic: if a curve, an interval or a pulse appears in this
  service, V13 has been pulled into V04.

**Issues identified:**

- **`NoiseLog.append` returns a new list; `history` must be reassigned.** `NoiseLog.append(history,
  …)` on its own type-checks, runs, and silently records nothing — the history stays empty and every
  later phase looks broken for the wrong reason. It is the single most likely defect in this phase.
- **`os.clock()` is per-server, not per-round.** It does not reset at `STARTING`; the phase handler
  clearing the history is what makes a round start silent. Do not try to zero the clock.
- **A dead player's noise.** `Emit` does not check `RoundService.GetPlayerState`, and it does not
  need to: the two callers in Phase 3 are both already gated on the actor being `Alive`, and adding
  a liveness branch here would make noise behave differently for a state that is publicly visible
  anyway. If a future caller is not so gated, the gate belongs at that caller.
- **`RecordCount` is one `Debug` print away from being an oracle in a solo Studio test.** It is safe
  because it is a count, but the moment somebody logs `GetRecent()` to inspect it, every position in
  the round is in the output window the player is looking at (`SearchService`'s log rule).

### Phase 3: The emitters

Two call sites, both inside code that has already decided the action really happened.

#### Step 3.1: Emit `SEARCH` when a hold begins

**File:** `src/server/Services/SearchService.luau`
**Verify:** `npm run analyze`

One call in `beginHold`, positioned so that a cancelled search has still been loud — the six seconds
are the reward, the noise is the price, and the price is paid up front.

**At the start, not at completion, and the choice is the mechanic.** §4.4 says the six seconds are
the exposure window; a noise that only landed on a completed search would mean a player who cancels
at 5.9 seconds was never there, and start/cancel would become free, silent reconnaissance of which
containers are still worth walking to. Paying at the start also means the sound arrives while the
searcher is still standing still, which is the only moment it can cost them anything.

**The noise is placed at the container, not at the player.** The server has already resolved which
container this is — the client named nothing — so the container's position is available, stable, and
independent of where within `Config.Search.RangeStuds` the searcher happens to be standing.

**No branch here reads a role, and `SearchService`'s header already forbids it.** §4.4: the Aswang
searches on identical rules, so it emits identical noise and receives the identical cue. A monster
that searched silently would be identified by the one container nobody heard being opened.

```diff
 local function beginHold(player: Player, containerIndex: number, name: string)
 	holds[player.UserId] = {
 		ContainerIndex = containerIndex,
 		Name = name,
 		EndsAt = os.clock() + Config.Search.SearchTime,
 	}
 	occupied[containerIndex] = player.UserId
 
+	--[[
+		V04, §4.4. THE PRICE, PAID UP FRONT. "The noise is the entire risk economy… you cannot be
+		safe and productive at the same time."
+
+		AT THE START RATHER THAN AT COMPLETION, deliberately: a search cancelled at 5.9 seconds has
+		still happened, and a noise that waited for SEARCH_OK would make start/cancel a free, silent
+		way to learn which containers are still worth walking to.
+
+		AT THE CONTAINER rather than at the player — the server resolved which container this is, so
+		the position is already known and does not wobble with where inside RangeStuds the searcher
+		stands. Nil when a map author deleted the part between the resolve and here; the hold is
+		still valid and the tick will release it, so this skips the noise rather than erroring.
+
+		NO ROLE BRANCH, AND THERE MUST NOT BE ONE. See this file's header: the Aswang searches on
+		identical rules, so it makes identical noise. A silent monster is identified by the container
+		nobody heard.
+	]]
+	local container: BasePart? = containersByName[name]
+
+	if container ~= nil then
+		NoiseService.Emit(player, "SEARCH", container.Position)
+	end
+
 	sendUpdate(player, "SEARCH_STARTED", nil)
 end
```

And the require, beside the two services this file already depends on:

```diff
 local AntiCheatService = require(script.Parent.AntiCheatService)
+local NoiseService = require(script.Parent.NoiseService)
 local RoundService = require(script.Parent.RoundService)
```

#### Step 3.2: Emit `ITEM_USE` on a resolved salt throw

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run verify`

Fired where the server has already validated the throw, so a client cannot buy a noise event by
sending a request that will be refused.

**Equally loud on a hit and on a miss, and that is a secrecy requirement rather than a simplification.**
`pure/SaltThrow`'s header explains at length why `MISS` is one value for four different worlds: a
verdict that varied would let a compromised client stand in front of each player in turn and read the
monster off the refusal shape. A noise that fired only on `OK` would rebuild exactly that oracle out
of audio — "the salt I threw at you made a sound, so you are the Aswang" — for the price of one
pouch. The call sits below the line that spends the pouch and above the hit branch, so no future
early return can make it conditional.

**It is placed after `AntiCheatService.Consume` and after the `typeof(direction)` guard**, both of
which are already the first two statements in that handler. V04 adds no new remote, so this is the
only place in the chunk where a client-originated request leads to a noise, and it leads there only
after the server has decided the throw really happened.

```diff
 			-- §4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO, and this line sits above the
 			-- hit branch so that no future early-return can skip it. A miss that cost nothing would make
 			-- salt a probe you throw at everyone, which is the thing pure/SaltThrow's header refuses.
 			carried[player.UserId] = math.max(0, (carried[player.UserId] or 0) - 1)
 
+			--[[
+				V04, §4.4. A THROW IS LOUD, AND IT IS EQUALLY LOUD ON A MISS.
+
+				THE SAME ARGUMENT AS THE LINE ABOVE, AND THE SAME ONE pure/SaltThrow MAKES ABOUT ITS
+				SINGLE MISS VERDICT. A noise that only fired on OK would be an identity probe with a
+				sound instead of a return value: throw a pouch at somebody, listen, learn what the
+				verdict refuses to tell you. Both verdicts reach this line, so both sound alike.
+
+				From the THROWER's position, which the server has because it resolved the throw from
+				it (broadcastEffect derives its origin the same way). The impact point is where the
+				salt landed, not where the noise was made.
+			]]
+			local throwerRoot = if player.Character
+				then player.Character:FindFirstChild("HumanoidRootPart")
+				else nil
+
+			if throwerRoot ~= nil and throwerRoot:IsA("BasePart") then
+				NoiseService.Emit(player, "ITEM_USE", throwerRoot.Position)
+			end
+
 			if verdict == "OK" and target ~= nil then
 				applyHit(target)
 			end
```

```diff
 local AntiCheatService = require(script.Parent.AntiCheatService)
 local MonsterService = require(script.Parent.MonsterService)
+local NoiseService = require(script.Parent.NoiseService)
 local RoundService = require(script.Parent.RoundService)
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the two live questions are *does either emitter branch on a role* (neither
  may; `SearchService`'s header forbids it outright) and *does either emitter fire on one verdict but
  not another* (the salt throw must sound identical on `OK` and `MISS`, or `pure/SaltThrow`'s single
  `MISS` value has been undone with audio).
- **Remote direction** — no remote is added or changed. Both call sites sit inside handlers that
  already exist.
- **Rate limiting** — both handlers already `AntiCheatService.Consume` as their first statement, and
  the emit is far below it. `check:ratelimit` is a proximity tripwire around
  `.OnServerEvent:Connect(`, so do not move a `Consume` call to make room.
- **Magic numbers** — neither emit introduces a number; the position comes from the world and
  everything else from `Config.Noise`.
- **Phase ownership** — unchanged. `Emit` does the `ACTIVE` check itself.
- **Player leaving mid-round** — `SearchService` already releases a leaver's hold, and a noise
  already recorded stays (Phase 2). Nothing new to handle.
- **Strict Luau** — `containersByName[name]` yields a NON-optional `BasePart` under `--!strict`, so
  the `local container: BasePart? =` annotation is required. In `ItemService`, `FindFirstChild`
  returns `Instance?` and needs the `:IsA("BasePart")` narrowing before `.Position`.
- **Mobile budget** — nothing rendered yet; the cue arrives in Phase 4.
- **Scope** — no §3 OUT token.

**Issues identified:**

- **Two of the four priced actions still have no emitter, and this phase does not add one.**
  `DOOR` has no door in `src/`; `SPRINT` has no movement verb, and wiring one on a speed threshold
  is the oracle described in the Overview. If the implementation feels incomplete here, that feeling
  is the plan working — it is recorded in Follow Ups rather than resolved in code.
- **Require cycles.** Both callers now require `NoiseService`, which requires `RoundService` and the
  two pure modules and nothing else. If `NoiseService` ever requires `SearchService` or
  `ItemService`, the cycle errors at load, `init.server.luau` swallows it into one `warn`, and the
  server sits looking exactly like "nobody has joined yet".
- **The `ITEM_USE` throttle is 2s and the salt-throw bucket is more generous than that.** A player
  spamming throws is refused by `AntiCheatService` first and by `MinInterval` second; the two do not
  need to agree, but if a V16 tune makes throwing faster than 2s the noise will silently drop events.
  That is the correct failure direction and worth knowing before it is reported as a bug.
- **`npm run verify` is the step's gate and it runs `fmt:check`.** If Phase 1's `npm run fmt` was
  skipped, this is where it surfaces, two phases from the file that caused it.

### Phase 4: The cue

Audio first, UI second — and the half of §4.4 that makes the actor's own risk perceptible.

#### Step 4.1: Declare `NoiseCue` and its payload

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run verify:fast`

One entry in `EVENTS_DOWN`, with the payload's absent fields written down the way
`SearchUpdatePayload` writes its own, and the matching `Types.NoiseCuePayload`.

`check:remotes` is deliberately **not** this step's gate: it flags a remote *used* in the wrong
direction or *used* without a declaration, so a declaration on its own passes it whatever it says.
Step 4.2 is the first use, and that is where the direction becomes checkable.

```diff
 	]]
 	"SearchUpdate",
+	--[[
+		V04, §4.4. FireClient, to every player the SERVER has decided is close enough to hear it —
+		never FireAllClients. `Types.NoiseCuePayload` is the payload.
+
+		THE BROADCAST FORM IS THE WHOLE RISK AND IT IS REFUSED. A FireAllClients carrying a position
+		would hand every client a live index of where everybody in the barrio is acting, readable
+		from a compromised client with no exploit beyond listening. §4.6 allows the Aswang an AREA on
+		a 90s-to-30s pulse (V13); a broadcast noise feed is a live map, which is strictly more than
+		the tracker will ever give it and would obsolete the balance-critical chunk of the rewrite.
+		The distance test happens on the server, and a player out of earshot receives NOTHING.
+
+		WHAT A SECOND CLIENT LEARNS: that something loud happened, roughly where, and what kind of
+		action it was. Not who did it — the payload has no player field of any kind, and the position
+		is quantised to Config.Noise.CueGridStuds before it is sent.
+
+		IT IS NOT A ROLE ORACLE, and the reasoning is §4.4's rather than this remote's: the Aswang
+		searches and throws on identical rules, emits identical noise, and receives this cue on
+		identical terms. There is no branch anywhere in the send path that reads a role. The
+		asymmetry that WOULD leak — one player never producing a cue, or never receiving one — is
+		`.claude/lessons/absence-is-observable.md`, and it is why no exemption exists here.
+
+		THE `Mine` FLAG IS NOT A LEAK: a client only ever sees its own payloads, so a boolean about
+		the receiver is the same shape as every field on `ProfileSnapshot`.
+	]]
+	"NoiseCue",
 }
```

And the payload, beside `SearchUpdatePayload` in `Types.luau`:

```diff
 export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"
 
+--[[
+	V04, §4.4. `NoiseCue`'s payload. FireClient, to one player at a time, after the server has
+	decided that player is within the noise's radius.
+
+	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:
+
+	  · NO ACTOR, in any form — not a UserId, not a name, not a character reference. §4.4's whole
+	    point is that hearing a search tells you somebody is searching, not who. Adding one would
+	    also be the first place a role could be inferred, since only the receiver knows it was not
+	    them.
+	  · NO RADIUS AND NO DISTANCE. The client reads `Config.Noise.Actions[Action].Radius` for its
+	    rolloff — Config is replicated, so this is a lookup rather than a transfer — and a DISTANCE
+	    would be a solved triangle: three cues and a compromised client has an exact position.
+	  · NO COUNT AND NO HISTORY. The history is server-only (§4.4, build plan V04) and V13 is its
+	    only reader.
+
+	`Position` IS QUANTISED to Config.Noise.CueGridStuds by the sender and is therefore a CELL, not a
+	person. §4.6 requires the Aswang's information to be an area rather than an address.
+]]
+export type NoiseCuePayload = {
+	Action: NoiseAction,
+	-- 0..1, scaling the volume. The receiver already knows this number from Config; it is sent so
+	-- the client never has to guess which action produced the cue it is playing.
+	Loudness: number,
+	Position: Vector3,
+	-- Whether the receiver is the one who made it. TRUE ONLY FOR THE ACTOR, which is why the actor's
+	-- cue can be non-positional and can carry a line of copy: it is the "that was loud" feedback
+	-- §4.6 asks for, and a sound you cannot perceive is not tension, it is a dice roll.
+	Mine: boolean,
+}
+
 -- What the timeline fires, in order. FIRE-ONCE per session — see `shared/pure/TrialTimeline`.
```

#### Step 4.2: Dispatch the cue from `NoiseService`

**File:** `src/server/Services/NoiseService.luau`
**Verify:** `npm run check:secrecy`

Per-listener `FireClient` after a server-side radius test, quantised position, `Mine` for the actor,
and never a `FireAllClients` — a broadcast position feed would hand every client a map of live
activity and obsolete V13 before it is written.

**The action is passed down from `Emit`, not read off the record**, and that is the unions lesson
applied rather than quoted: `NoiseLog.Record.Action` is a plain `string`, and
`record.Action :: Types.NoiseAction` is exactly the cast that fails with *"none of the union options
are compatible"* at a call site in another file. `Emit`'s own parameter is already the union, so
handing it through costs one argument and no casts.

**LOBBY and SPECTATOR hear nothing**, which is `AudioCues`' existing rule for monster cues applied
one layer earlier: information reaching somebody outside the round is information reaching a Discord
call. It is a constant across everyone in the round, so it produces no difference between players.
`DEAD` hears noise — a dead player is in the world spectating and can already see people searching,
and refusing them audio would make the dead audibly different from the living, which is the failure
`absence-is-observable` names.

```diff
 local RoundService = require(script.Parent.RoundService)
 local NoiseLog = require(script.Parent.Parent.pure.NoiseLog)
 
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.Config)
 local Enums = require(Shared.Enums)
 local NoiseModel = require(Shared.pure.NoiseModel)
+local Remotes = require(Shared.Remotes)
 local Types = require(Shared.Types)
```

```diff
 local lastEmitAt: { [number]: { [string]: number } } = {}
 
+local cueRemote = Remotes.Get("NoiseCue")
+
+local function rootOf(player: Player): BasePart?
+	local character = player.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+	if root == nil or not root:IsA("BasePart") then
+		return nil
+	end
+
+	return root
+end
+
+--[[
+	WHO HEARS THIS, DECIDED HERE AND NOWHERE ELSE.
+
+	ONE FireClient PER LISTENER, NEVER FireAllClients. The distance test is the entire security
+	property of this function: a client out of earshot receives nothing at all, so there is no
+	broadcast stream to record, difference or triangulate. See the `NoiseCue` comment in Remotes.
+
+	THE POSITION IS QUANTISED BEFORE IT IS SENT, once, so every listener gets the same cell and two
+	colluding clients cannot average their copies back toward the truth.
+
+	`action` IS PASSED IN RATHER THAN READ OFF `record`, because `NoiseLog.Record.Action` is a plain
+	string and `:: Types.NoiseAction` is the cast that fails with "none of the union options are
+	compatible" — `.claude/lessons/pure-module-unions-widen-in-lists.md`. Emit already holds the
+	narrow type; handing it through costs an argument and no casts.
+
+	NO BRANCH HERE READS A ROLE, AND THE ACTOR IS NOT EXEMPT FROM ANYTHING. The Aswang hears other
+	people's noise and makes its own on identical terms; the only per-player difference in this
+	function is `Mine`, which is a fact about the receiver and reaches nobody else.
+]]
+local function dispatchCue(actor: Player?, action: Types.NoiseAction, record: NoiseLog.Record)
+	local cell = NoiseModel.quantise(record.Position, Config.Noise.CueGridStuds)
+	local at = Vector3.new(cell.X, cell.Y, cell.Z)
+
+	for _, player in Players:GetPlayers() do
+		local state = RoundService.GetPlayerState(player)
+
+		--[[
+			OUTSIDE THE ROUND HEARS NOTHING. The same rule `AudioCues` applies to monster cues, one
+			layer earlier: a cue is information, and information reaching somebody in the lobby is
+			information reaching a Discord call. DEAD is allowed — a dead player is in the world and
+			can already see people searching, and silence for the dead would make them audibly
+			different from the living (`.claude/lessons/absence-is-observable.md`).
+		]]
+		if state == Enums.PlayerState.Lobby or state == Enums.PlayerState.Spectator then
+			continue
+		end
+
+		local mine = player == actor
+
+		if not mine then
+			local root = rootOf(player)
+
+			if root == nil then
+				continue
+			end
+
+			local listener = { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z }
+
+			-- AGAINST THE TRUE POSITION, not the quantised one: the cell is what gets SENT, and
+			-- testing against it would move the audible edge by up to half a cell per axis.
+			if not NoiseLog.withinRadius(record.Position, listener, record.Radius) then
+				continue
+			end
+		end
+
+		-- A TYPED LOCAL rather than an inline table, for `broadcastEffect`'s reason: FireClient takes
+		-- `...any`, so an inline literal is unchecked and a typo'd field name would ship. The
+		-- annotation is what makes the absent fields listed in Types.NoiseCuePayload enforceable.
+		local payload: Types.NoiseCuePayload = {
+			Action = action,
+			Loudness = record.Loudness,
+			Position = at,
+			Mine = mine,
+		}
+
+		cueRemote:FireClient(player, payload)
+	end
+end
+
 local function limits(): NoiseLog.Limits
```

And the one line that calls it, at the end of `Emit`:

```diff
 	history = NoiseLog.append(history, record, limits())
 
+	-- §4.6: "Survivors must know when they made noise. A sound you cannot perceive is not tension,
+	-- it is a dice roll." AFTER the record, so a cue can never be heard for a noise the history does
+	-- not contain.
+	dispatchCue(actor, action, record)
+
 	if Config.Debug.VerboseLogging then
```

#### Step 4.3: Give the two cues a phase rule and an asset slot

**File:** `src/shared/pure/AudioCues.luau`
**Verify:** `lune run tests/audio-cues.test.luau`

`CUE_NOISE` and `CUE_NOISE_SELF` join `PERMITTED_PHASES` with the same uniform-across-players
property `CUE_FOOTSTEP`'s row documents, plus `Config.Audio.Assets` entries and the test rows that
pin them.

**Two ids rather than one**, because the actor's cue is a different sound played a different way:
non-positional and paired with a line of copy, versus positional and attenuated. One id with a
`Mine` branch at the play site would mean one asset for two jobs.

**Deviation: `MONSTER_CUES` is renamed to `ROUND_ONLY_CUES`.** The set's members are not the point
of it — the RULE is "this cue must not reach somebody outside the round", and the noise cues need
exactly that rule for exactly that reason. Adding a second table with the same body would be the
worse answer, and the name would then be lying in two files. It is a file-local `local` with no
external readers, and the existing suite exercises it only through `isCuePermitted`, so no caller
changes.

**Both edits must land together.** `tests/config.test.luau` already cross-checks
`Config.Audio.Assets` against `AudioCues` in both directions, so an asset slot with no rule (or a
rule with no slot) reds Step 1.4's suite as well as this one.

```diff
 local PERMITTED_PHASES: { [string]: { [string]: boolean } } = {
 	CUE_TRANSFORM = { STARTING = true, ACTIVE = true },
 	CUE_HEARTBEAT = { ACTIVE = true },
 	CUE_SUNRISE = { ACTIVE = true, ENDING = true },
+	--[[
+		V04, §4.4. ACTIVE ONLY, because nothing can make noise outside it — `NoiseService.Emit`
+		refuses every other phase, and this row is the second half of that statement rather than a
+		restriction on top of it.
+
+		BOTH IDS ARE PERMITTED ON IDENTICAL TERMS FOR EVERY PLAYER IN THE ROUND. There is no role
+		branch, no form branch and no per-player exception, for `CUE_FOOTSTEP`'s reason two rows
+		down: a rule that can refuse a cue for some players and not others is a difference, and in
+		this game a difference IS the leak (`.claude/lessons/absence-is-observable.md`).
+	]]
+	CUE_NOISE = { ACTIVE = true },
+	CUE_NOISE_SELF = { ACTIVE = true },
 	CUE_FOOTSTEP = {
```

```diff
 --[[
 	THE STATE GATE, AND THE ONE RULE IN IT THAT IS A SECRECY RULE.
 
 	A player in LOBBY or SPECTATOR is not in the round. They must not hear the monster — not the
 	stinger, not the heartbeat — because a cue is information, and information reaching somebody
 	outside the round is information reaching a Discord call. §4.3's tell is for players who are in
 	the barrio and can be killed by it.
 
 	DEAD is allowed. A dead player is still in the world spectating and can already SEE a transformed
 	monster; refusing them the audio would remove nothing and would make dead players audibly
 	different from living ones, which is the failure mode `absence-is-observable` names.
+
+	V04 RENAMED THIS FROM `MONSTER_CUES`, and the rename is the honest version of what it always
+	was: the rule is "must not reach somebody outside the round", and the monster's cues were simply
+	the only members. §4.4's noise cues need the same rule for the same reason — a lobby player
+	hearing a search knows somebody is out there arming themselves, from outside the barrio. The
+	server already refuses them (NoiseService.dispatchCue), so this is the second lock rather than
+	the first.
 ]]
-local MONSTER_CUES: { [string]: boolean } = {
+local ROUND_ONLY_CUES: { [string]: boolean } = {
 	CUE_TRANSFORM = true,
 	CUE_HEARTBEAT = true,
+	CUE_NOISE = true,
+	CUE_NOISE_SELF = true,
 }
```

```diff
-	if MONSTER_CUES[cueId] and OUTSIDE_THE_ROUND[state] then
+	if ROUND_ONLY_CUES[cueId] and OUTSIDE_THE_ROUND[state] then
 		return false
 	end
```

`Config.Audio` gets the slots and the two volumes. Blank ids are the supported pre-sourcing state —
`newSound` builds, parents and ranges the Sound either way, and `tests/config.test.luau` asserts
"empty **or** well-formed" precisely so a sourcing pass is a separate, later, human step:

```diff
 		CUE_HEARTBEAT = "rbxassetid://139459003161851",
 		CUE_SUNRISE = "rbxassetid://4501062448",
+		-- V04. Sourced by hand later (the `asset-pipeline` skill); blank is a supported shipping
+		-- state and `AudioController.logCue` is what proves the cue FIRED before a sound exists.
+		CUE_NOISE = "",
+		CUE_NOISE_SELF = "",
 	},
```

```diff
 	FootstepVolume = 0.4,
+
+	--[[
+		V04, §4.4. Two volumes because the two noise cues do different jobs: CUE_NOISE is a
+		positional sound in the world, scaled further by the action's Loudness at the play site;
+		CUE_NOISE_SELF is your own, non-positional, and wants to be plainly audible — §4.6: "a sound
+		you cannot perceive is not tension, it is a dice roll."
+
+		IDENTICAL FOR EVERY PLAYER AND EVERY ROLE, like FootstepVolume above and for the same reason.
+		A quieter noise for one player is a role broadcast with no role token in it.
+	]]
+	NoiseVolume = 0.55,
+	NoiseSelfVolume = 0.7,
```

And the rows that pin the rule, appended to `tests/audio-cues.test.luau`:

```diff
 for _, phase in PHASES do
 	check(`footsteps in {phase}`, AudioCues.isCuePermitted("CUE_FOOTSTEP", phase, "ALIVE"))
 end
 
+--[[
+	V04, §4.4. THE NOISE CUES. Two properties, and the second is the one no playtest would show you:
+	a cue heard by somebody in the LOBBY is information leaving the round, and the person who has it
+	is not even in the barrio.
+]]
+for _, cueId in { "CUE_NOISE", "CUE_NOISE_SELF" } do
+	check(`{cueId} plays during ACTIVE`, AudioCues.isCuePermitted(cueId, "ACTIVE", "ALIVE"))
+	check(`{cueId} reaches the dead`, AudioCues.isCuePermitted(cueId, "ACTIVE", "DEAD"))
+	check(
+		`{cueId} does not reach the lobby`,
+		not AudioCues.isCuePermitted(cueId, "ACTIVE", "LOBBY")
+	)
+	check(
+		`{cueId} does not reach a spectator`,
+		not AudioCues.isCuePermitted(cueId, "ACTIVE", "SPECTATOR")
+	)
+
+	for _, phase in PHASES do
+		if phase ~= "ACTIVE" then
+			check(
+				`{cueId} is silent in {phase}`,
+				not AudioCues.isCuePermitted(cueId, phase, "ALIVE")
+			)
+		end
+	end
+end
+
 print(`  {checked - failures}/{checked} checks passed`)
```

#### Step 4.4: Play them on the client

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `grep -q playNoiseCue src/client/Controllers/AudioController.luau`

A non-positional one-shot plus one line of copy for the actor; a positional one-shot at the quantised
point for everyone else in earshot. Both client-created, both cleaned up on
`Config.Audio.CueCleanupSeconds`.

**About that `Verify` line, stated plainly.** It proves the symbol was written, not that a sound
came out — which is the honest ceiling for this step, because everything it does lives in the
DataModel and no terminal can hear it. The real evidence is the playtester's: the build plan's own
Verify line for V04 says *"playtester confirms the cue fires on a search and not on a walk"*, and
`AudioController.logCue` exists precisely so that can be proven from console output **before any
asset is sourced** (`Debug.VerboseLogging` on, search a container, read `cue CUE_NOISE_SELF`). A
`npm run verify` here would be worse than a grep, not better: it passes whether or not this step was
ever done.

**`AudioController`, not a new controller.** It already owns `newSound`, `playOneShot`, `logCue`,
`assetFor` and the `phase`/`state` pair that `isCuePermitted` needs; a `NoiseController` would
duplicate all five or reach across for them. Two functions are added and `Start` gains one line.

**The rolloff distance is not in the payload — the client derives it.** `NoiseModel` is in
`shared/pure/`, so a LocalScript can require and *run* it (preamble P1), and
`NoiseModel.evaluate(payload.Action, {}, Config.Noise)` returns the same `Radius` the server used.
That is the narrow-by-function the unions lesson prescribes: an `Action` nobody priced comes back
`nil` and the cue is dropped with a warn, where a cast would have waved it into a `Sound` with a
garbage range. It is also the first client caller `NoiseModel` has, which is the placement decision
in P1 paying for itself.

```diff
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 local SoundService = game:GetService("SoundService")
 local TweenService = game:GetService("TweenService")
 
+--[[
+	V04. A ONE-WAY ARROW, exactly as `SearchController` and `TrialController` already draw it:
+	OnboardingController knows nothing about noise, so this cannot become a cycle. Note that it
+	INVERTS this file's position in CONTROLLER_ORDER — AudioController is first, Onboarding sixth —
+	and that is safe because the list governs Init/Start only, while `require` at load is
+	independent of it. `ShowLine` is called from a remote handler that can only fire during ACTIVE,
+	long after every controller's Init has run.
+]]
+local OnboardingController = require(script.Parent.OnboardingController)
+
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local AudioCues = require(Shared.pure.AudioCues)
 local Config = require(Shared.Config)
+local NoiseModel = require(Shared.pure.NoiseModel)
 local Remotes = require(Shared.Remotes)
 local SkyCycle = require(Shared.pure.SkyCycle)
 local Types = require(Shared.Types)
```

```diff
 local STINGER_NAME = "AswangTransformStinger"
+local NOISE_ANCHOR_NAME = "NoiseCueAnchor"
+
+-- Player-facing copy lives on the client, the rule `SearchController` and `TeachingLines` both
+-- follow: the payload carries an action id, never a sentence, so text never crosses the wire.
+local NOISE_LINE = "That was loud."
```

The positional half. `QuickChatController.renderPing` is the precedent for the anchor and
`playStinger` for the rolloff, so neither is a new mechanism in this repo:

```diff
+--[[
+	SOMEBODY ELSE'S NOISE, AT A CELL IN THE WORLD.
+
+	A CLIENT-CREATED, CLIENT-PARENTED Part and Sound. Nothing here replicates and nothing here is
+	visible to another player — which is the whole reason the cue is safe: a server-made Sound
+	parented into a character would be heard by EVERY client, turning "somebody was loud" into a
+	per-player public broadcast. `playStinger` states the same property for its local-only Sound.
+
+	THE POSITION IS ALREADY QUANTISED by the server (Config.Noise.CueGridStuds). This function must
+	not refine it, offset it, or draw anything at it — §4.6 wants an area, and a marker would make
+	the cell an address on screen.
+
+	RANGE COMES FROM `NoiseModel`, not from the payload. Config is replicated and the module is in
+	shared/pure/, so the client re-derives the same Radius the server used. An unpriced action
+	returns nil and is dropped with a warn — a LOOKUP, not a cast (the C21 lesson).
+
+	⚠ UNCONFIRMED, inherited from `QuickChatController.renderPing`: whether a client-created `Part`
+	in `workspace` stays local under §5's StreamingEnabled is not established anywhere in this repo.
+	Conventionally it does. If a playtest shows otherwise, the fallback named there is to parent the
+	anchor to `Camera`, and the same fallback applies here.
+]]
+local function playNoiseCue(payload: Types.NoiseCuePayload)
+	local emission = NoiseModel.evaluate(payload.Action, {}, Config.Noise)
+
+	if emission == nil then
+		warn(`[AudioController] no Config.Noise price for "{payload.Action}" — nothing played.`)
+		return
+	end
+
+	local anchor = Instance.new("Part")
+
+	anchor.Name = NOISE_ANCHOR_NAME
+	anchor.Size = Vector3.one
+	anchor.Transparency = 1
+	anchor.Anchored = true
+	anchor.CanCollide = false
+	anchor.CanQuery = false
+	anchor.CanTouch = false
+	anchor.Position = payload.Position
+	anchor.Parent = workspace
+
+	local sound = newSound("CUE_NOISE", Config.Audio.NoiseVolume * payload.Loudness, anchor)
+
+	if sound == nil then
+		-- An unknown cue id: `newSound` has already warned. The anchor would otherwise sit in the
+		-- world forever, since the cleanup below never runs.
+		anchor:Destroy()
+		return
+	end
+
+	sound.RollOffMaxDistance = emission.Radius
+	sound.RollOffMode = Enum.RollOffMode.Linear
+
+	logCue("CUE_NOISE", `{payload.Action}, {emission.Radius} studs`)
+	sound:Play()
+
+	--[[
+		THE ANCHOR IS DESTROYED, NOT THE SOUND — destroying the parent takes the Sound with it, and
+		leaving the Part behind would leak one Instance per audible noise for the session.
+		`Sound.Ended` is the wrong lifetime for the same reason `playOneShot` gives: A BLANK SoundId
+		NEVER ENDS, and blank is the supported state until the assets are sourced.
+	]]
+	task.delay(Config.Audio.CueCleanupSeconds, function()
+		if anchor.Parent ~= nil then
+			anchor:Destroy()
+		end
+	end)
+end
+
+--[[
+	THE CUE. One remote, two shapes, and the branch is a fact about the RECEIVER.
+
+	`Mine` IS NON-POSITIONAL, parented to SoundService like the bed and the sunrise: you do not
+	localise your own noise, you just hear that you made it. §4.6 is the requirement — "survivors
+	must know when they made noise; a sound you cannot perceive is not tension, it is a dice roll" —
+	and audio-first-UI-second is the build plan's, so the line of copy follows the sound rather than
+	replacing it.
+
+	THE STATE GATE IS CONSULTED ON BOTH PATHS, and `playStinger`'s comment is the reason to be
+	explicit about it: `isCuePermitted` sat written, tested and never called for a whole chunk, which
+	the C29 exploit audit found. The server already refuses LOBBY and SPECTATOR; this is the second
+	lock, not the first.
+
+	THE ASWANG TAKES THIS PATH UNCHANGED. There is no role branch in this file, none in the sender,
+	and none in `AudioCues` — see the plan's Overview, question 1.
+]]
+local function onNoiseCue(payload: Types.NoiseCuePayload)
+	if payload.Mine then
+		if not AudioCues.isCuePermitted("CUE_NOISE_SELF", phase, state) then
+			return
+		end
+
+		playOneShot("CUE_NOISE_SELF", Config.Audio.NoiseSelfVolume, SoundService, "own noise")
+		OnboardingController.ShowLine(NOISE_LINE)
+
+		return
+	end
+
+	if not AudioCues.isCuePermitted("CUE_NOISE", phase, state) then
+		return
+	end
+
+	playNoiseCue(payload)
+end
+
 function AudioController.Init() end
```

```diff
 	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
 	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
+	Remotes.Get("NoiseCue").OnClientEvent:Connect(onNoiseCue)
```

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the phase that earns the `exploit-auditor` pass. Four things to re-read
  rather than assume: the payload has no player field (`Types.NoiseCuePayload`); the send is
  `FireClient` per listener and never `FireAllClients`; the distance test happens on the SERVER, so
  a client out of earshot receives nothing to record or difference; and every `Sound` and `Part` is
  created by the receiving client, so none of it replicates. A server-created `Sound` parented into
  a character is the one line that would undo the whole design.
- **Remote direction** — `NoiseCue` is in `EVENTS_DOWN`, fired with `:FireClient` on the server,
  listened to with `.OnClientEvent` on the client. `check:remotes` proves all three, and it runs
  inside `npm run verify` at the end of the phase.
- **Rate limiting** — still no `OnServerEvent` handler anywhere in V04. If one appears here, the
  chunk has taken a wrong turn: nothing the client says can cause a noise.
- **Magic numbers** — the volumes, the grid and the cleanup delay are all `Config` reads. The
  rolloff comes from `NoiseModel` rather than a literal.
- **Phase ownership** — unchanged; `AudioController` reads `phase` off the snapshot it already
  receives.
- **Player leaving mid-round** — a leaver's anchors are their own client's and go with their
  session. Nothing server-side holds a reference to them.
- **Strict Luau** — `payload.Action` is a scalar union and survives `require` intact, so it passes
  to `NoiseModel.evaluate` without a cast; do not add one. `Enum.RollOffMode.Linear` and
  `Vector3.one` are both already used in this repo (`playStinger`, `renderPing`).
- **Mobile budget** — §5 counts Instances. Each audible noise costs one `Part` and one `Sound` for
  `Config.Audio.CueCleanupSeconds` (6). With five players and a 6-second search throttle the steady
  state is under ten live anchors, and the delay-based cleanup means a dropped frame cannot leak one.
- **Scope** — no §3 OUT token. No HUD element, no marker, no minimap: `ShowLine` is the existing
  hint label, which is what "UI second" means here.

**Issues identified:**

- **`grep` is the weakest check in this plan and it is on this step.** It proves the symbol exists.
  The phase is not actually verified until the playtester returns an artifact showing `CUE_NOISE_SELF`
  firing on a search and NOT on a walk, and `verification.md` cites it. Do not read a green Phase 4
  as a working cue.
- **The assets are blank on purpose, so the first playtest will be silent.** That is the supported
  pre-sourcing state (`tests/config.test.luau` asserts "empty or well-formed"), and `logCue` is what
  proves the cue fired. Sourcing them is a human pass with the `asset-pipeline` skill, recorded in
  Follow Ups rather than done here.
- **`OnboardingController.ShowLine` overwrites whatever line is on screen.** A noise cue during a
  search will replace "You found a pouch of salt." if the two land within the hint's dwell time.
  Acceptable for V04 — both are transient hints — but it is the first place two systems compete for
  that label, and V14's feel pass should decide who wins.
- **A quantised position can be inside geometry.** The cell centre may land in a wall or under the
  floor; the sound still plays, attenuated by distance only, since Roblox `Sound` does not occlude.
  That is consistent with §4.6 wanting the read to be vague, and it is a thing to notice rather than
  fix.
- **Do not let the anchor become a marker.** A `BillboardGui` on it — which `renderPing` shows is
  three lines away — would turn an area into an address and hand the Aswang exactly what V13 is
  written to withhold.

## 3. Related Files

## 4. Follow Ups

### Questions / Clarifications

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
