# Plan: C09–C12 — Timing, Fetch, Two-person, the escape gate, and the Aswang's fake list

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M3 (C09, C10, C11, C12 — the second half)
- **Description:** Seven phases. Phase 1 is terminal-only groundwork: types, Config knobs, three new
  remotes and their budgets. Phases 2–3 build **C09's Timing** task — a bar whose phase the SERVER owns
  and whose hit the SERVER decides, with the client extrapolating a rendering from a published phase.
  Phase 4 builds **C09's Fetch** — a carried item, server-tracked, dropped where its carrier dies.
  Phase 5 builds **C10's Two-person**, whose participant count is derived from `TaskWeight` so it
  inherits the anti-oracle property rather than restating it. Phase 6 builds **C11** — `GateOpen`
  written for the first time, a `GateService`, and §4.8's survivor win landing on the reveal. Phase 7
  builds **C12** — the Aswang is *told* a task list that is not the real five, while its hands keep
  doing exactly what everyone else's do.
- **Date:** 2026-08-12
- **What the client is told:** two new remotes, one existing field that finally moves, and two public
  changes to the world. Enumerated in §1.1.

### 1.1 The wire, enumerated

1. **`TimingBarChanged`** (DOWN, new) — `FireClient`, only to the player standing at a `TIMING` point:
   `{ TaskId, Phase, Period, ZoneCenter, ZoneHalfWidth, Hits, HitsRequired }`. Every field describes a
   task point. None names a player, a role, or a count of who is present.
2. **`TaskListAssigned`** (DOWN, new) — `FireClient`, to **every** player at `STARTING`:
   `{ TaskIds: { string } }`. Survivors receive this round's real five. The Aswang receives a decoy
   five drawn from the same pool. **Identical shape, identical size, identical moment, sent to
   everyone** — see §1.3 for why uniformity is the security property here and secrecy is not.
3. **`ClientRoundSnapshot.GateOpen`** — the field already exists and C01 shipped the client rendering
   for it (`init.client.luau:77` prints `gate OPEN` / `gate shut`). Phase 6 is the first code that ever
   sets it `true`.
4. **The world gains two public objects.** Fetch items are unanchored-looking parts in `Workspace`, and
   the escape gate part changes appearance when it opens. Both replicate; neither carries a role.

`ClientRoundSnapshot` gains **no field**. `RoundEnded` gains no field. `RoleAssigned` gains no field.
`check-secrecy.mjs`'s `REVEAL_ALLOWLIST` and `PAYLOAD_FIELDS` are **not touched**.

### 1.2 Amendment A2 is the spine of this plan, and it points the other way from BUILD-PLAN.md

`docs/MVP-SPEC.md` §4.4 carries **Amendment A2**, dated today. `docs/BUILD-PLAN.md`'s C12 entry
predates it and says *"its progress does not count"* and *"the global bar does not move"*. **That entry
is stale and this plan deliberately contradicts it**, on the spec's authority and per CLAUDE.md's
precedence rule (spec → CLAUDE.md → code). Recorded in §4 rather than resolved quietly.

Three consequences bind every phase below:

- **No code path anywhere in this plan may branch on role to decide a contribution.** Not the timing
  hit, not the fetch carry, not the two-person participant count. `src/server/pure/TaskWeight.luau`
  and `tests/task-weight.test.luau` hold that as an enumerated `PlayerState × Role` grid, and C10's
  count is *derived from those same weights* (Phase 5) so it cannot drift from the property.
- **C12 is an information-channel lie and nothing else.** What the Aswang is told is false; what its
  hands do is real, counted in full, and indistinguishable from a survivor's.
- **The one legitimate role branch in the whole plan is C11's win check** (Phase 6): §4.8 says a
  *survivor* reaching the gate wins. §1.4 states what that leaks and why it is accepted.

### 1.3 The fake list is a UX affordance, not a mechanic — and its ceiling is already known

`ActiveTaskPoint` tags **replicate**. A compromised client reads the true five in one line of Luau, and
no amount of care in Phase 7 changes that. So:

- The fake list costs an **honest** Aswang real travel time and real position, which is exactly the
  trade A2 describes ("it can be sent to points nobody needs").
- It costs a **dishonest** Aswang nothing. **No balance decision in this game may depend on it.**
- Its honest-client ceiling is also real and worth stating: `attachPrompt` sets
  `MaxActivationDistance = Config.Tasks.PresenceRangeStuds` (9 studs), so a prompt is only visible
  once you are effectively standing on the point. An Aswang walking to a decoy learns it is a decoy
  **on arrival**, having already paid the walk. That is the whole mechanic and it is enough.

**Uniformity, not secrecy, is what Phase 7 protects.** The remote is fired to every player, in one
loop, at one moment, with one payload shape. A remote fired *only* to the Aswang would be a wire
asymmetry — and this repo already rejected that class of design at `InputController.luau:152-168`,
which refuses to gate the task bind on role for the same reason.

### 1.4 🔒 C11 leaks one bit, the spec requires it, and here is the accounting

§4.8: *"Survivors win: 5/5 tasks done AND at least 1 survivor reaches the escape gate."* The Aswang
reaching an open gate must not end the round. So a bystander who watches a player stand in an open
gate while the round does **not** end has learned that player is the Aswang.

This is inherent to the rule, not to the implementation. What this plan does about it:

- **No feedback of any kind is sent to the player at the gate.** No refusal, no verdict, no sound, no
  prompt. The Aswang's client is told exactly what a survivor's client is told: nothing. The only
  observable is the round ending, which is a fact about the round.
- **The window is small.** The gate is inert until 5/5, and at 5/5 the round ends within seconds of
  any survivor arriving.
- It is raised in §4 as an accepted, spec-mandated cost rather than buried.

### 1.5 What is deliberately NOT in this plan

- **C13–C16** (salt, ghosts, quick chat, the trial). The five remotes those chunks own stay declared
  and unwired.
- **C17 — the greybox.** Phases 4 and 6 add **disposable** anchors to `workspace.TaskRig_TEMP`, exactly
  as plan 1 did for `TaskPoint`. C17 deletes the rig wholesale and replaces every anchor in it.
- **C18 — the HUD.** The timing bar, the task list and the gate-open moment all get a cache and a
  `VerboseLogging` print on the client, matching `TaskController`'s existing shape. M7 draws them.
  BUILD-PLAN asks that the gate opening be "an event worth seeing and hearing"; the *hearing* is
  `AudioController`'s at C18 and the place file's, and this plan says so rather than faking it.
- **A `WeldConstraint` carry rig.** The fetch item is repositioned on the existing 4 Hz server tick.
  See Step 4.5 — this is a deliberate, named quality compromise, not an oversight.
- **Nothing from spec §3's OUT list.**

## 2. Comprehensive Plan by Phases

### Phase 1: Types, Config, remotes, budgets

Terminal-only. No Roblox API is touched and no behaviour changes; every later phase depends on this one.

#### Step 1.1: Declare the four new types

**File:** `src/shared/Types.luau`
**Verify:** `npm run verify:fast`

`TimingVerdict`, `TimingBarPayload`, `TaskListPayload` and `FetchAction`, following the
`TaskProgressVerdict` / `TaskProgressPayload` precedent — a literal union so a refusal can be logged
with a reason and never echoed, and a typed payload local for each thing that crosses the wire.

Inserted directly above `-- SERVER ONLY. Never send this table to a client.`, where plan 1 put its
three.

```diff
+--[[
+	Why the server refused (or failed) a RequestTimingStop (§4.4, C09). Same shape and same rule as
+	TaskProgressVerdict: a union so the server can log WHY, and NEVER echoed to any client.
+
+	MISS IS A VERDICT AND NOT AN ERROR, and it is the one worth reading twice. A miss is a legitimate
+	outcome of a legitimate request — the player pressed at the wrong moment — so unlike every other
+	value here it corresponds to a state change (the hit count resets). It is still never echoed: the
+	client learns it missed from the bar it is already being sent, which carries `Hits` and moves
+	whether the stop landed or not. Sending a verdict would add a second, differently-timed channel
+	saying the same thing, and two channels that can disagree is how a desync becomes a bug report.
+
+	NOT_A_TIMING_TASK exists because `RequestTimingStop` resolves its task from the player's position
+	exactly as `RequestTaskProgress` does, so a player standing on a HOLD point can reach this handler
+	honestly. It is a refusal, not an accusation.
+]]
+export type TimingVerdict =
+	"OK"
+	| "MISS"
+	| "WRONG_PHASE"
+	| "NOT_ALIVE"
+	| "NO_TASK_IN_RANGE"
+	| "ALREADY_COMPLETE"
+	| "NOT_A_TIMING_TASK"
+
+--[[
+	The moving bar (§4.4, C09). SEVEN FIELDS, ALL OF THEM ABOUT A TASK POINT AND NONE ABOUT A PLAYER.
+
+	`Phase` is the bar's position in its sweep at the moment the server sent this, in 0..1, NOT the
+	rendered bar position — the rendered position is a triangle fold of it, and the client computes
+	that with `TimingWindow.positionFromPhase`. Sending the phase rather than the position is what
+	makes a single send sufficient: position alone is ambiguous (the bar passes every value twice per
+	sweep) and would need a direction flag beside it, which is a second field that can disagree with
+	the first.
+
+	THE CLIENT EXTRAPOLATES BETWEEN SENDS AND THE SERVER DOES NOT CARE. The server re-derives the
+	phase from its own `os.clock()` at the instant a stop arrives; nothing the client renders is an
+	input to that. A client that renders the bar frozen, doubled, or backwards gets exactly the same
+	hit decision as one that renders it perfectly. That is the C09 brief's "a client-decided timing
+	minigame is a free task for any exploiter", answered structurally.
+
+	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
+	table is accepted silently by the typechecker, and `TimingBarChanged` is not on
+	check-secrecy.mjs's REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, catching a
+	field named `role` or `aswang` and catching nothing else. A field named `LastStopByUserId` would
+	pass every check in this repo and would name who is standing where.
+]]
+export type TimingBarPayload = {
+	TaskId: string,
+	Phase: number, -- 0..1 through one sweep, at send time
+	Period: number,
+	ZoneCenter: number,
+	ZoneHalfWidth: number,
+	Hits: number,
+	HitsRequired: number,
+}
+
+--[[
+	The task list one player is shown (§4.4 + Amendment A2, C12). ONE FIELD, AND THE LIE IS WHICH
+	VALUE IT HOLDS RATHER THAN WHAT SHAPE IT IS.
+
+	Every player receives this, at STARTING, in one loop, with one payload shape. Survivors receive
+	this round's real five; the Aswang receives a decoy five drawn from the same pool. Nothing about
+	the send distinguishes them — same moment, same field, same count — which is the property that
+	survives a compromised client reading its own traffic.
+
+	IT IS NOT A SECRET AND MUST NEVER BE TREATED AS ONE. `ActiveTaskPoint` tags replicate, so a
+	compromised client reads the true five directly off CollectionService and the decoy is defeated in
+	one line. This is a UX affordance for honest clients and a cost in walking distance for an honest
+	Aswang. No balance decision may depend on it. See the plan's §1.3.
+]]
+export type TaskListPayload = {
+	TaskIds: { string },
+}
+
+--[[
+	What should happen to one fetch item this tick (§4.4, C09) — the verdict from
+	`server/pure/FetchCarry.luau`.
+
+	SAFE TO LOG AND SAFE TO ACT ON IN THE OPEN, unlike every other verdict in this file. It describes
+	an object in the workspace that every client can already see, and the object's own position states
+	the outcome one tick later regardless.
+
+	DROP is the interesting one and it is deliberately not called "death". A carrier stops carrying
+	when they stop being a full contributor, and being killed is only one of the four ways that
+	happens — disconnecting, being reset, and joining as a spectator are the others. Naming the action
+	after the cause would have meant a branch per cause, and three of them would have been missed.
+]]
+export type FetchAction = "NONE" | "PICK_UP" | "DELIVER" | "DROP"
+
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

#### Step 1.2: Add the C09–C11 knobs to `Config.Tasks`

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

The timing bar's period and green zone, the latency grace, the fetch deliver hold, the two-person
participant count, the full-contribution weight, and the gate's reach.

**`TimingAttempts` is RENAMED to `TimingHitsRequired`, not reinterpreted in place.** Grepped before
planning: `src/shared/Config.luau:114` is its only occurrence in the entire tree, so the rename is
free today and will never be free again. §4.4's table says *"Stop a moving bar in a green zone, 3
attempts"*, and this plan reads that as **three successful stops, with a miss resetting the count** —
which is what produces the *"~10s"* the same row asks for (three sweeps plus reaction) and what makes
*"failure is funny"* true. Under the other reading — one hit needed, three misses allowed — the task
takes two seconds and the third miss has to do something the spec never says. §4 records the judgement.

```diff
 	Tasks = {
 		TotalRequired = 5, -- how many must be completed to open the gate
 		PoolSize = 12, -- how many possible spawn points exist on the map
 		HoldTime = 8,
-		TimingAttempts = 3,
-		FetchTime = 25,
-		TwoPersonTime = 12,
+
+		--[[
+			THE TIMING TASK (§4.4, C09). Three successful stops in the green zone, and a miss puts you
+			back to zero.
+
+			`TimingHitsRequired` was called `TimingAttempts` until C09 and the rename is the honest
+			half of a decision, not tidying. §4.4 says "3 attempts" against a "~10s" duration; three
+			REQUIRED HITS at a 1.8s sweep is roughly ten seconds, and three ALLOWED MISSES is roughly
+			two. The row's own duration column picks the reading, and a knob named for the wrong one
+			is a knob M12 tunes in the wrong direction.
+
+			A MISS RESETS PROGRESS AND THAT DOES NOT CONTRADICT §4.4's ANTI-FRUSTRATION RULE. That
+			rule ("progress belongs to the world") is about ABSENCE — a survivor who dies at 90% leaves
+			90% behind, and `TaskProgress.tick` freezes rather than decays for exactly that reason. A
+			miss is an ACTION, taken by a present player, and the whole of what makes the bar a skill
+			moment is that it can be failed. The task never becomes unwinnable: the next stop is
+			always available.
+		]]
+		TimingHitsRequired = 3,
+
+		--[[
+			The bar's sweep, its green zone, and the allowance for the trip the keypress makes.
+
+			`TimingZoneCenter` and `TimingZoneHalfWidth` are in BAR UNITS (0..1 across the visible
+			track), not seconds, because that is what a player is aiming at. The centre is deliberately
+			0.5 — a zone anywhere else makes one sweep direction easier than the other, and the bar
+			passes every position twice.
+
+			`TimingGraceSeconds` IS THE LATENCY ALLOWANCE AND IT IS THE ONLY HONEST PLACE TO PUT ONE.
+			The server decides the hit from its own clock at the instant the request lands, so a
+			player on a 90 ms connection is judged ~90 ms after they pressed. The alternatives are both
+			worse: trusting a client-supplied timestamp hands the task away outright, and no allowance
+			at all makes the task a ping test. `tests/config.test.luau` pins the grace SMALLER than the
+			zone it widens, so it stays an allowance rather than becoming the mechanic.
+		]]
+		TimingBarPeriod = 1.8,
+		TimingZoneCenter = 0.5,
+		TimingZoneHalfWidth = 0.1,
+		TimingGraceSeconds = 0.05,
+
+		--[[
+			THE FETCH TASK (§4.4, C09). `FetchTime` is the budget for the WHOLE errand — walk to the
+			source, carry the item back — and no line of code reads it, which is why this comment
+			exists. It is the number M12 tunes when the errand feels long, and what it actually tunes
+			is the distance between a source anchor and its task point in the map. C17 owns that
+			distance.
+
+			`FetchDeliverTime` is the part the server can time: how long a carrier stands at the
+			destination once they have arrived. It is short on purpose — the cost of a fetch is the
+			TRAVEL, which is what §4.4's "forces travel across the map — creates isolation" is buying.
+			A long deliver hold would just be a Hold task with extra steps.
+		]]
+		FetchTime = 25,
+		FetchDeliverTime = 3,
+
+		--[[
+			THE TWO-PERSON TASK (§4.4, C10) — and per Amendment A2, the Aswang is a full participant.
+
+			`TwoPersonParticipants` is a COUNT OF FULL CONTRIBUTORS, and `FullContributionWeight` is
+			what "full" means, measured against what `server/pure/TaskWeight.luau` returns. Deriving
+			the count from the weights is the entire design: an ALIVE survivor and an ALIVE Aswang both
+			weigh 1, so a survivor-plus-Aswang pair satisfies the requirement and the task completes
+			normally — not because a rule says so, but because there is nowhere for a rule to say
+			otherwise. See A2's own words: "C10's participant count must be derived from the same
+			weights, so that it inherits the property instead of restating it."
+
+			It also settles C15 in advance without a second decision: a ghost weighs
+			`Ghost.TaskContributionMult` (0.25), so two ghosts do not open a two-person task. §4.4 says
+			"2 survivors present", and §4.7 says ghosts "still matter", not that they substitute.
+		]]
+		TwoPersonTime = 12,
+		TwoPersonParticipants = 2,
+		FullContributionWeight = 1,
+
+		--[[
+			How close a survivor must get to the open escape gate to win the round (§4.8, C11).
+
+			IT MUST NOT EXCEED `Monster.KillRange`, and `tests/config.test.luau` pins that. The finale
+			§4.8 is describing is a survivor running for a gate with the Aswang between them and it; if
+			the gate could be triggered from further away than the Aswang can reach, camping it would
+			stop working and the last thirty seconds of every round would lose its only tension. The
+			relation is a design constraint, not a safety margin — tune the gate down or the kill range
+			up, never past each other.
+		]]
+		GateRangeStuds = 6,
```

#### Step 1.3: Pin the new relationships in `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

Five invariants, each one a silent failure otherwise: the green zone must be reachable, the grace must
not swallow the zone, the deliver hold must fit inside the fetch budget, a ghost must not count as a
two-person participant, and the gate's reach must not exceed the Aswang's kill range.

Appended above the closing `if failures > 0 then` block, and the final `print` count moves 29 → 34.

```diff
+--[[
+	§4.4, C09. A green zone that runs off either end of the track is not a skill moment, it is a
+	button — and it fails invisibly, because the bar still sweeps and stops still land.
+]]
+check(
+	"the timing green zone sits inside the bar",
+	Config.Tasks.TimingZoneCenter - Config.Tasks.TimingZoneHalfWidth > 0
+		and Config.Tasks.TimingZoneCenter + Config.Tasks.TimingZoneHalfWidth < 1,
+	`center={Config.Tasks.TimingZoneCenter}, half={Config.Tasks.TimingZoneHalfWidth}`
+)
+
+--[[
+	THE LATENCY ALLOWANCE MUST STAY SMALLER THAN THE ZONE IT WIDENS.
+
+	The grace is in SECONDS and the zone is in BAR UNITS, so they are not comparable until the sweep
+	speed converts one to the other: the bar crosses the whole 0..1 track twice per period, so it
+	moves at `2 / TimingBarPeriod` bar units per second. This is exactly the conversion inside
+	`server/pure/TimingWindow.luau`, restated here against Config's own numbers — which is the point.
+	Lower the period at M12 and the same grace in seconds silently becomes a much wider window; this
+	is the line that notices.
+]]
+check(
+	"the timing grace widens the zone rather than replacing it",
+	Config.Tasks.TimingBarPeriod > 0
+		and Config.Tasks.TimingGraceSeconds * (2 / Config.Tasks.TimingBarPeriod)
+			< Config.Tasks.TimingZoneHalfWidth,
+	`grace={Config.Tasks.TimingGraceSeconds * (2 / Config.Tasks.TimingBarPeriod)} bar units `
+		.. `vs half={Config.Tasks.TimingZoneHalfWidth}`
+)
+
+-- §4.4, C09: the cost of a fetch is the TRAVEL. A deliver hold approaching the whole errand budget
+-- has quietly turned the task into a Hold with a walk in front of it.
+check(
+	"the fetch deliver hold is a small part of the errand",
+	Config.Tasks.FetchDeliverTime > 0
+		and Config.Tasks.FetchDeliverTime * 2 < Config.Tasks.FetchTime,
+	`deliver={Config.Tasks.FetchDeliverTime}, errand={Config.Tasks.FetchTime}`
+)
+
+--[[
+	§4.4 asks a two-person task for "2 survivors present"; §4.7 asks ghosts to "still matter", not to
+	substitute. C10 derives its participant count from TaskWeight, so what separates those two
+	sentences is this single relation between two numbers in this file — and nothing else. If a ghost
+	ever weighed a full contribution, two dead players would open the game's most social task and
+	nobody would see a test go red.
+]]
+check(
+	"a ghost is not a two-person participant",
+	Config.Ghost.TaskContributionMult < Config.Tasks.FullContributionWeight
+		and Config.Tasks.TwoPersonParticipants >= 2,
+	`ghost={Config.Ghost.TaskContributionMult}, full={Config.Tasks.FullContributionWeight}, `
+		.. `required={Config.Tasks.TwoPersonParticipants}`
+)
+
+--[[
+	§4.8's finale (C11). The Aswang camping an open gate is the last thirty seconds of a good round;
+	a gate that triggers from beyond the monster's reach deletes it, and the symptom is "the endings
+	feel flat" rather than anything a log would show.
+]]
+check(
+	"the escape gate stays inside the Aswang's reach",
+	Config.Tasks.GateRangeStuds > 0
+		and Config.Tasks.GateRangeStuds <= Config.Monster.KillRange,
+	`gate={Config.Tasks.GateRangeStuds}, kill={Config.Monster.KillRange}`
+)
+
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end

-print("  PASS  config: 29 balance invariants")
+print("  PASS  config: 34 balance invariants")
```

#### Step 1.4: Declare three remotes and their rate-limit budgets

**Files:** `src/shared/Remotes.luau`, `src/shared/Config.luau`, `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

`TimingBarChanged` and `TaskListAssigned` DOWN, `RequestTimingStop` UP, plus the budget
`RequestTimingStop` in `Config.AntiCheat.Budgets`. The budget test pins **both** directions, so this
check goes red if either half is missing — which is exactly why it is the check on this step rather
than `check:remotes`. `check:remotes` reports an undeclared remote as an error and an unwired one as a
*note*, so it passes on a step that declares nothing at all.

**Three new remotes is three more than this plan wanted.** Eight are already declared and unwired, and
every one is spoken for: `SaltEffect` and `RequestThrowSalt` are C14's, `QuickChatBroadcast` and
`RequestQuickChat` are C16's, `RequestGhostSpook` is C15's, and `ProfileUpdated`,
`RequestEquipCosmetic` and `RequestClaimDaily` are M8–M9's. Reusing one would mean two chunks sharing
a name with two payload shapes, which is how a `WaitForChild` starts resolving to the wrong contract.

```diff
 -- Server -> Client (the server tells you things)
 local EVENTS_DOWN = {
 	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
 	"PhaseChanged",
 	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
 	"TaskProgressChanged",
+	-- C09. FireClient to the ONE player standing at a TIMING point. Carries a task point's bar, never
+	-- a player: the server owns the phase and re-derives it on every stop, so this is a rendering
+	-- hint and not an input to any decision.
+	"TimingBarChanged",
+	-- C12. FireClient to EVERY player, at STARTING, one loop, one payload shape. Survivors get this
+	-- round's real five; the Aswang gets a decoy five. The uniformity is the design — see
+	-- Types.TaskListPayload. Deliberately NOT on check-secrecy's REVEAL_ALLOWLIST: it carries no role,
+	-- so it must keep being scanned like any other remote.
+	"TaskListAssigned",
 	"PlayerKilled",
 	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
 	"SaltEffect",
 	"RoundEnded", -- includes the reveal
 	"QuickChatBroadcast",
 	"ProfileUpdated",
 }
 
 -- Client -> Server (the client asks; the server decides)
 local EVENTS_UP = {
 	"RequestTaskProgress",
+	-- C09. NO ARGUMENTS, and that is the whole security design: the server resolves which task from
+	-- the player's own position and reads the bar's phase off its own clock at the moment this lands.
+	-- There is no argument in which a client could name a moment, a position or an outcome.
+	"RequestTimingStop",
 	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
```

Then the budget, in `Config.AntiCheat.Budgets`, directly under `RequestTaskProgress`:

```diff
 			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },
+			--[[
+				A deliberate keypress at a moving bar (C09). Looser than legitimate play, as this
+				table's header requires: an honest player fires once per sweep — about 0.55/s at a
+				1.8s period — against a sustained 1/s, and the burst covers a player mashing at the
+				zone through one sweep plus a reconnect retry.
+
+				It is deliberately far tighter than RequestTaskProgress next door, because the shapes
+				are opposite. A presence heartbeat is CONTINUOUS and idempotent; a stop is DISCRETE and
+				changes state every time it lands. Spamming it is the closest thing C09 has to an
+				exploit — enough stops per sweep and one of them is inside the zone by arithmetic
+				rather than by skill — so the limiter is the second line here and the first is that a
+				miss resets the hit count.
+			]]
+			RequestTimingStop = { Capacity = 5, RefillPerSecond = 1 },
 			-- Deliberate, rare acts. Capacity covers a double-tap and a reconnect retry; nothing more.
 			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
```

Then the test's hand copy, and one cadence invariant beside the ones already there:

```diff
 local UP_REMOTES = {
 	"RequestTaskProgress",
+	"RequestTimingStop",
 	"RequestTransform",
```

```diff
+--[[
+	§4.4, C09. The honest cadence at a timing bar is one stop per sweep, so a refill slower than that
+	throttles a player for playing the minigame at the only rate the minigame allows. This is the same
+	failure the RequestTaskProgress budget's comment warns about, one remote over.
+]]
+check(
+	"an honest timing player out-paces nothing but the bar",
+	Config.Tasks.TimingBarPeriod > 0
+		and 1 / Config.Tasks.TimingBarPeriod
+			< Config.AntiCheat.Budgets.RequestTimingStop.RefillPerSecond,
+	`{1 / Config.Tasks.TimingBarPeriod}/s vs refill=`
+		.. `{Config.AntiCheat.Budgets.RequestTimingStop.RefillPerSecond}/s`
+)
+
 --------------------------------------------------------------------------------
 -- The policy switches
 --------------------------------------------------------------------------------
```

The final `print` moves `+ 7 invariants` → `+ 8 invariants`.

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

- **`TaskListAssigned` is one edit away from being a role oracle, and no check in this repo would
  see it.** Its payload field is `TaskIds`; `check-secrecy.mjs`'s `SECRET` and `ROLE_TOKEN` regexes
  match neither, so a field named `IsDecoy: boolean` — the natural thing to add while debugging Phase
  7 — would reach the Aswang's client, scan clean, typecheck, and name the monster to any compromised
  client that logged its own traffic. The type's comment says so; there is no mechanical guard.
- **The rename in Step 1.2 is safe today only.** `TimingAttempts` has exactly one occurrence in the
  tree (grepped: `src/shared/Config.luau:114`). If Phase 1 lands after anything else starts reading
  it, the rename stops being free.
- **`check:config` does not govern `src/shared/`**, so the numbers Phase 2's pure module handles are
  only kept honest by taking every tunable as a parameter. `src/server/pure/` **is** governed
  (`GOVERNED = /(^|\/)src\/(server|client)\//`), which is where four of this plan's five new pure
  modules live — literals other than `0, 1, 2, -1, 0.5, 100` will be flagged there.
- **No player-leaving case applies yet.** Nothing in this phase holds per-player state. Phases 3, 4
  and 6 each add one, and each names its own.

### Phase 2: The timing decision, purely

#### Step 2.1: `src/server/pure/TimingWindow.luau`

**File:** `src/server/pure/TimingWindow.luau`
**Verify:** `npm run analyze`

`phaseAt`, `positionFromPhase`, `positionAt`, `effectiveHalfWidth` and `isHit` over plain numbers. The
bar is a triangle wave; the hit is decided from the SERVER's elapsed time, widened by a latency grace
expressed in seconds and converted to bar units inside the module.

New file, entire contents:

```diff
+--!strict
+--[[
+	TimingWindow — where is the bar, and did that stop land in the green? (§4.4, C09)
+
+		phaseAt(elapsed, period)          -> 0..1 through one sweep
+		positionFromPhase(phase)          -> 0..1 across the visible track
+		positionAt(elapsed, period)       -> the two composed
+		effectiveHalfWidth(request)       -> the zone, widened by the latency allowance
+		isHit(request)                    -> boolean
+
+	THE SERVER OWNS THE BAR AND THIS MODULE IS WHY THAT COSTS NOTHING TO SAY.
+
+	C09's brief: "the client renders the bar; the SERVER owns the bar's position and decides the hit.
+	A client-decided timing minigame is a free task for any exploiter." The shape that delivers it is
+	that `elapsed` is the only input describing time, and TaskService computes it as
+	`os.clock() - task.BarStartAt` at the instant a request lands. No client timestamp, no client
+	position, no client-reported outcome reaches here — there is no parameter one could arrive in.
+
+	PHASE AND POSITION ARE DIFFERENT THINGS AND THE WIRE CARRIES THE PHASE.
+
+	`phase` runs 0..1 once per sweep and is monotonic; `position` is the triangle fold of it and is
+	what a player sees. The bar passes every position TWICE per sweep, so a position on its own does
+	not say where the bar is going — it would need a direction flag beside it, a second field that can
+	disagree with the first. Types.TimingBarPayload carries `Phase` for exactly this reason.
+
+	THE GRACE IS SYMMETRIC AND THAT IS A DELIBERATE SIMPLIFICATION WITH A NAMED COST.
+
+	The player pressed; the request travelled; the server evaluates a bar that has moved on. The
+	error is therefore one-directional — the true press was always BEHIND the evaluated position, by
+	the latency, in the direction of travel. A correct allowance would widen the window only backwards
+	along that direction.
+
+	This widens it both ways, which additionally accepts a press that was genuinely early by up to the
+	grace. The cost is a slightly more generous zone, bounded by `tests/config.test.luau` pinning the
+	grace smaller than the half-width it widens. The benefit is that the rule stays a function of
+	position alone, so `tests/timing-window.test.luau` can enumerate it. Directional grace needs the
+	sweep direction as an input and doubles the grid; it is in the plan's Follow Ups.
+
+	NO `script.Parent` REQUIRES, no Roblox datatypes, and every tunable arrives as a PARAMETER rather
+	than being read from Config — the same rule as every other pure module here, and the reason
+	`check:config` (which governs `src/server/`, this directory included) has nothing to flag.
+]]
+
+export type Request = {
+	-- SERVER seconds since this task's bar started. Never a client-supplied value.
+	Elapsed: number,
+	Period: number,
+	-- Both in BAR UNITS, 0..1 across the visible track.
+	ZoneCenter: number,
+	ZoneHalfWidth: number,
+	-- In SECONDS. Converted to bar units here, using the sweep speed, and nowhere else.
+	GraceSeconds: number,
+}
+
+local TimingWindow = {}
+
+--[[
+	A NON-POSITIVE PERIOD RETURNS A STOPPED BAR RATHER THAN ERRORING.
+
+	It cannot arrive through Config — `tests/config.test.luau` pins `TimingBarPeriod > 0` as part of
+	the grace invariant — and "cannot happen" is precisely how a nan reaches a client and renders a
+	bar that never moves again. `TaskProgress.tick` carries the same guard for the same reason.
+
+	Lua's `%` with a positive divisor already returns a value in [0, period), including for a negative
+	`elapsed`, so there is no second branch to write here.
+]]
+function TimingWindow.phaseAt(elapsed: number, period: number): number
+	if period <= 0 then
+		return 0
+	end
+
+	return (elapsed % period) / period
+end
+
+-- The triangle fold: phase 0 -> 0, 0.5 -> 1, 1 -> 0. `% 1` because the CLIENT extrapolates a phase
+-- forward from the last one it was sent and will hand this values well above 1.
+function TimingWindow.positionFromPhase(phase: number): number
+	local wrapped = phase % 1
+
+	return if wrapped <= 0.5 then wrapped * 2 else 2 - wrapped * 2
+end
+
+function TimingWindow.positionAt(elapsed: number, period: number): number
+	return TimingWindow.positionFromPhase(TimingWindow.phaseAt(elapsed, period))
+end
+
+--[[
+	The zone the server will actually accept, in bar units.
+
+	The conversion is the whole content: the bar crosses the 0..1 track twice per period, so it moves
+	at `2 / Period` bar units per second and a grace of `g` seconds is worth `g * 2 / Period` bar
+	units. `tests/config.test.luau` restates this arithmetic against Config's own numbers, so lowering
+	the period at M12 cannot silently widen the window.
+
+	`math.max(0, ...)` because a negative grace would NARROW the zone, which is a knob nobody meant to
+	build and which would present as "the timing task got hard after a Config edit".
+]]
+function TimingWindow.effectiveHalfWidth(request: Request): number
+	if request.Period <= 0 then
+		return request.ZoneHalfWidth
+	end
+
+	return request.ZoneHalfWidth + math.max(0, request.GraceSeconds) * (2 / request.Period)
+end
+
+function TimingWindow.isHit(request: Request): boolean
+	local position = TimingWindow.positionAt(request.Elapsed, request.Period)
+
+	return math.abs(position - request.ZoneCenter) <= TimingWindow.effectiveHalfWidth(request)
+end
+
+return TimingWindow
```

#### Step 2.2: `tests/timing-window.test.luau`

**File:** `tests/timing-window.test.luau`
**Verify:** `lune run tests/timing-window.test.luau`

A **grid, not a sample** — the domain is bounded, so it is enumerated, per
`.claude/lessons/green-after-each-patch-hides-a-loop.md`. 192 sample points (64 per sweep, three
sweeps) against 3 zone half-widths and 3 grace values: 1,728 cells, every one asserted.

The assertion with teeth is the **last** one. Properties 1–5 would all still hold if `isHit` returned
`true` everywhere; property 6 pins the fraction of a sweep that accepts a stop to `2 × effective half
width`, which is the sentence M12 will actually tune and the only one that fails when the window is
silently wrong.

New file, structure and the six properties (assertion bodies elided only where they repeat):

```diff
+--!strict
+--[[
+	tests/timing-window.test.luau
+
+	`server/pure/TimingWindow.luau` over its WHOLE domain rather than a sample of it.
+
+	Enumerable, so enumerated. The bar is periodic and the zone is a closed interval, so "every 64th
+	of a sweep, across three sweeps, at three widths and three graces" is not a sampling strategy —
+	it is the domain, at a resolution finer than any decision the module makes.
+]]
+
+local TimingWindow = require("../src/server/pure/TimingWindow")
+
+local PERIOD = 1.8
+local CENTER = 0.5
+local SAMPLES_PER_SWEEP = 64
+local SWEEPS = 3
+local EPSILON = 1e-9
+
+local HALF_WIDTHS = { 0, 0.1, 0.25 }
+local GRACES = { 0, 0.05, 0.2 }
+
+local failures = 0
+local assertions = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	assertions += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+--  1. The bar never leaves the track. A position outside 0..1 renders off the end of the UI at C18
+--     and is the failure a triangle fold written with the wrong constant produces.
+for step = 0, SAMPLES_PER_SWEEP * SWEEPS - 1 do
+	local elapsed = step * PERIOD / SAMPLES_PER_SWEEP
+	local position = TimingWindow.positionAt(elapsed, PERIOD)
+
+	check(
+		`position stays on the track at step {step}`,
+		position >= -EPSILON and position <= 1 + EPSILON,
+		`position={position}`
+	)
+end
+
+--  2. Periodic. positionAt(e) == positionAt(e + period), which is what lets the client extrapolate
+--     from one sent phase for the rest of the task instead of being fed the bar continuously.
+
+--  3. Symmetric about the midpoint of the sweep: positionFromPhase(p) == positionFromPhase(1 - p).
+--     A zone at CENTER = 0.5 is therefore equally hittable on the way out and the way back, which is
+--     the reason Config pins the centre there.
+
+--  4. Grace is monotone: if a stop lands with grace g, it lands with any grace >= g. This is what
+--     makes the knob safe to tune in one direction at M12 — raising it can only ever make the task
+--     easier, never differently hard.
+for _, halfWidth in HALF_WIDTHS do
+	for step = 0, SAMPLES_PER_SWEEP * SWEEPS - 1 do
+		local elapsed = step * PERIOD / SAMPLES_PER_SWEEP
+		local previous = false
+
+		for _, grace in GRACES do
+			local hit = TimingWindow.isHit({
+				Elapsed = elapsed,
+				Period = PERIOD,
+				ZoneCenter = CENTER,
+				ZoneHalfWidth = halfWidth,
+				GraceSeconds = grace,
+			})
+
+			check(
+				`grace only ever widens (half={halfWidth}, step={step}, grace={grace})`,
+				not previous or hit
+			)
+
+			previous = previous or hit
+		end
+	end
+end
+
+--  5. A zero-width zone with zero grace accepts a stop only where the bar is exactly on the centre.
+--     At CENTER = 0.5 that is one phase per half-sweep and the sampling hits it exactly, so this is
+--     an equality test rather than a tolerance test — and it is the case that catches an `isHit`
+--     written with `<` where `<=` was meant.
+
+--  6. THE ONE WITH TEETH. Across a full sweep, the fraction of sampled moments that accept a stop
+--     equals 2 * effectiveHalfWidth, to within one sample. The bar sweeps the track linearly and
+--     covers it twice per period, so a window of half-width h around the centre is open for exactly
+--     that fraction of the time.
+--
+--     Properties 1-5 are all satisfied by an `isHit` that returns true unconditionally. This one is
+--     not. It is also the sentence M12 tunes: "a timing stop lands about a fifth of the time" is a
+--     balance statement, and this is where it is written down.
+for _, halfWidth in HALF_WIDTHS do
+	for _, grace in GRACES do
+		local hits = 0
+		local total = SAMPLES_PER_SWEEP * SWEEPS
+
+		for step = 0, total - 1 do
+			if
+				TimingWindow.isHit({
+					Elapsed = step * PERIOD / SAMPLES_PER_SWEEP,
+					Period = PERIOD,
+					ZoneCenter = CENTER,
+					ZoneHalfWidth = halfWidth,
+					GraceSeconds = grace,
+				})
+			then
+				hits += 1
+			end
+		end
+
+		local expected = math.min(1, 2 * TimingWindow.effectiveHalfWidth({
+			Elapsed = 0,
+			Period = PERIOD,
+			ZoneCenter = CENTER,
+			ZoneHalfWidth = halfWidth,
+			GraceSeconds = grace,
+		}))
+		local measured = hits / total
+
+		check(
+			`the open fraction matches the zone (half={halfWidth}, grace={grace})`,
+			math.abs(measured - expected) <= 2 / SAMPLES_PER_SWEEP,
+			`measured={measured}, expected={expected}`
+		)
+	end
+end
+
+if failures > 0 then
+	error(`{failures} timing-window failure(s)`, 0)
+end
+
+print(`  PASS  timing-window: {assertions} assertions over {#HALF_WIDTHS * #GRACES} configurations`)
```

**Note for the implementer:** properties 2, 3 and 5 are written out in the same `check` shape as 1, 4
and 6 above and are elided here only because they repeat the loop verbatim with a different predicate.
Do not skip them — property 5 is the one that catches `<` where `<=` was meant, which is a
one-character bug that every other property in this file accepts.

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

- **The symmetric grace is a real, quantified generosity.** At committed values it accepts a press up
  to 0.05s *early* as well as 0.05s late, widening the zone from 0.10 to ~0.156 bar units — a stop
  lands ~31% of the time rather than ~20%. That is a balance fact, not a bug, and it belongs in M12's
  notes. Directional grace is in Follow Ups.
- **This module publishes the bar's algorithm to every client, and that is fine.** It is under
  `src/server/pure/` so a LocalScript cannot require it — but even if it were shared, CLAUDE.md's rule
  is that *logic is not secret, inputs and seeds are*. The bar's inputs are `Config` (already
  replicated) and `os.clock()` on the server. A client that reimplements this module perfectly can
  render a perfect bar and still cannot decide a hit, because the decision reads the server's clock at
  the moment the request lands.
- **`Elapsed` is `os.clock()`-derived and `os.clock()` is not guaranteed monotonic** across a Roblox
  server's lifetime — `TokenBucket` and `TaskProgress` both carry that warning. Here a backwards jump
  produces a bar that skips, never an error: `%` is total over the reals and `phaseAt` clamps nothing.
  Worth knowing rather than guarding.
- **`check:config` governs this directory.** Every literal in the module is inside
  `IDIOMATIC = {0, 1, 2, -1, 0.5, 100}` by construction, because every tunable arrives as a parameter.
  A future edit that inlines `1.8` here goes red, which is the intended outcome.

### Phase 3: Timing, wired

#### Step 3.1: Teach `taskTypeOf` the other three types

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run verify:fast`

`taskTypeOf` currently warns and returns `HOLD` for anything that is not `HOLD`
(`TaskService.luau:216-227`). It becomes a lookup over an explicit list that still warns — loudly,
unconditionally, naming the part — for an attribute matching nothing, because a map asking for a
mechanic that does not exist must stay visible rather than silently become a Hold.

```diff
+-- Written out rather than iterating `Enums.TaskType`, which is a frozen record and not an array. An
+-- explicit list is what makes the loop below typecheck as `{ Types.TaskType }` under --!strict, and
+-- it puts the map's whole vocabulary on four legible lines.
+local TASK_TYPES: { Types.TaskType } = {
+	Enums.TaskType.Hold,
+	Enums.TaskType.Timing,
+	Enums.TaskType.Fetch,
+	Enums.TaskType.TwoPerson,
+}
+
 --[[
 	The map's half of the type contract, and the one line C09 does not have to revisit discovery for.
 
-	An absent attribute means HOLD. A present one that is not HOLD is a map asking for a mechanic that
-	does not exist yet, and it gets a HOLD plus a warning naming the part — visible, rather than
-	silently mishandled, which is what C09 will want when it starts placing Timing anchors.
+	An absent attribute still means HOLD, and that default is now load-bearing rather than a
+	placeholder: the rig has twelve pads and only a few of them will ever name a type.
+
+	An attribute matching NOTHING is a map defect and stays loud. The warning is unconditional — this
+	file's `reportPool` explains why the routine tracing is gated and the faults are not, and a task
+	point silently demoted to HOLD is exactly the fault where the only symptom a player reports is
+	"the game is boring".
 ]]
 local function taskTypeOf(part: BasePart): Types.TaskType
 	local requested = part:GetAttribute("TaskType")
 
-	if requested ~= nil and requested ~= Enums.TaskType.Hold then
-		warn(
-			`[TaskService] {part.Name} asks for TaskType "{requested}", which is not built yet `
-				.. `(C09/C10). Using {Enums.TaskType.Hold}.`
-		)
-	end
-
-	return Enums.TaskType.Hold
+	if requested == nil then
+		return Enums.TaskType.Hold
+	end
+
+	for _, value in TASK_TYPES do
+		if requested == value then
+			return value
+		end
+	end
+
+	warn(
+		`[TaskService] {part.Name} asks for TaskType "{requested}", which is not a TaskType. `
+			.. `Using {Enums.TaskType.Hold}. Valid: {table.concat(TASK_TYPES, ", ")}.`
+	)
+
+	return Enums.TaskType.Hold
 end
```

**The pool must stay mostly HOLD.** All four types are drawn from one 12-point pool, so a round can
legitimately draw five `TWO_PERSON` points and become unfinishable below four living players. That is
a **map** constraint, not a code one — C17 owns the mix — and it is raised in §4 rather than defended
against here, because the defence would be a draw that special-cases type and §4.4's whole design is
that the five are drawn at random.

#### Step 3.2: The per-task timing state and the `RequestTimingStop` handler

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:ratelimit`

Per-task `BarStartAt` and `Hits`, server-side, seeded at the draw. The handler takes **no arguments**,
consumes a token first, resolves the task from the player's own position, and decides the hit from
`os.clock()`. Every refusal returns nothing at all.

**The state is a parallel server-only table, not a widening of `Types.ActiveTask`.** `ActiveTask` is a
shared type; `BarStartAt` and `Hits` are server-only round state with no reason to be describable on
the client. Adding them to the shared type would put them one `FireClient` away from the wire.

```diff
+--[[
+	THE TIMING BAR'S STATE (§4.4, C09). SERVER-ONLY, keyed by task Id.
+
+	`BarStartAt` is seeded once, at the draw, and never reseeded. The bar therefore runs continuously
+	for the whole round and every player standing at that point sees the SAME bar in the same place —
+	which is what §4.4's world-owned progress means applied to a moving object, and what makes two
+	players at one timing point a coherent thing to watch rather than two private minigames.
+
+	`Hits` is the count of successful stops. A miss puts it back to zero — see Config's
+	`TimingHitsRequired` for why that does not contradict §4.4's anti-frustration rule.
+]]
+type TimingState = {
+	BarStartAt: number,
+	Hits: number,
+}
+
+local timingState: { [string]: TimingState } = {}
```

Cleared alongside the rest of the round's state, in `clearTasks`:

```diff
 	table.clear(presence)
 	table.clear(lastSentProgress)
+	table.clear(timingState)
+	table.clear(lastSentBar)
```

Seeded in `selectForRound`, inside the loop that already builds `activeTasks`:

```diff
 		activeParts[point.Id] = part
 		CollectionService:AddTag(part, TAG_ACTIVE)
 		attachPrompt(part)
+
+		-- Every task gets a bar, not only the TIMING ones. It costs two numbers, and it means a map
+		-- edit that flips a pad to TIMING mid-round cannot land on a task with no bar to read.
+		timingState[point.Id] = { BarStartAt = os.clock(), Hits = 0 }
 	end
```

The validation, mirroring `evaluatePresence` line for line so the two cannot drift:

```diff
+local function taskById(id: string): Types.ActiveTask?
+	for _, task in activeTasks do
+		if task.Id == id then
+			return task
+		end
+	end
+
+	return nil
+end
+
+--[[
+	Everything the server checks before it believes a timing stop.
+
+	DELIBERATELY THE SAME SHAPE AND THE SAME ORDER AS `evaluatePresence`, including returning the
+	resolved Id alongside the verdict. Two validators over one surface that check the same things in
+	different orders is how one of them acquires a hole nobody can see by reading either.
+
+	The verdict is for the LOG ONLY and is never echoed — read Types.TimingVerdict. MISS in particular
+	looks harmless and is not: it is the one value that would let a client distinguish "I was refused"
+	from "I was wrong", and a client that can tell those apart can binary-search the green zone
+	without ever rendering a bar.
+]]
+local function evaluateTimingStop(player: Player): (Types.TimingVerdict, string?)
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return "WRONG_PHASE", nil
+	end
+
+	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+		return "NOT_ALIVE", nil
+	end
+
+	local id, anyInRange = taskPointAt(player)
+
+	if id == nil then
+		return (if anyInRange then "ALREADY_COMPLETE" else "NO_TASK_IN_RANGE"), nil
+	end
+
+	local task = taskById(id)
+
+	if task == nil or task.Type ~= Enums.TaskType.Timing then
+		return "NOT_A_TIMING_TASK", nil
+	end
+
+	return "OK", id
+end
+
+--[[
+	THE STOP. The server reads its own clock; nothing a client sent is an input to the decision.
+
+	`os.clock()` is sampled ONCE, at the top, and reused. Sampling it again inside the hit test would
+	make the decision and the bar the player is subsequently sent describe two different moments —
+	microseconds apart, and therefore a bug that appears only under load.
+]]
+local function noteTimingStop(player: Player)
+	local now = os.clock()
+	local verdict, id = evaluateTimingStop(player)
+
+	if verdict ~= "OK" or id == nil then
+		if Config.Debug.VerboseLogging then
+			print(`[TaskService] Refused timing stop for {player.Name}: {verdict}`)
+		end
+
+		return
+	end
+
+	local state = timingState[id]
+	local task = taskById(id)
+
+	if state == nil or task == nil or task.Completed then
+		return
+	end
+
+	local hit = TimingWindow.isHit({
+		Elapsed = now - state.BarStartAt,
+		Period = Config.Tasks.TimingBarPeriod,
+		ZoneCenter = Config.Tasks.TimingZoneCenter,
+		ZoneHalfWidth = Config.Tasks.TimingZoneHalfWidth,
+		GraceSeconds = Config.Tasks.TimingGraceSeconds,
+	})
+
+	state.Hits = if hit then state.Hits + 1 else 0
+	task.Progress = math.clamp(state.Hits / Config.Tasks.TimingHitsRequired, 0, 1)
+
+	local completed = false
+
+	if state.Hits >= Config.Tasks.TimingHitsRequired then
+		task.Completed = true
+		task.Progress = 1
+		completed = true
+
+		RoundService.SetTasksCompleted(completedCount())
+
+		if Config.Debug.VerboseLogging then
+			print(`[TaskService] Task complete: {task.Id}`)
+		end
+	end
+
+	publishBar(player, task.Id)
+	publishProgress(completed)
+end
```

And the tick must stop advancing a `TIMING` task by presence — without this, standing at a timing
point completes it in `HoldTime` and the minigame is decoration:

```diff
 	for _, task in activeTasks do
 		if task.Completed then
 			continue
 		end
 
+		-- A TIMING task advances ONLY through `noteTimingStop`. Presence at one buys the bar and
+		-- nothing else. Without this line the task has two independent progress sources and the
+		-- faster one wins, which would be the hold.
+		if task.Type == Enums.TaskType.Timing then
+			continue
+		end
+
 		local weight = TaskProgress.strongestWeight(weights[task.Id] or {})
```

The handler, beside the existing `RequestTaskProgress` one so `check-ratelimit`'s 1200-character
window sees the `Consume` call from the connect site:

```diff
+	--[[
+		Consume FIRST, before any state is read, for the reason the handler above states. This remote
+		is the one in the game where spamming has a theoretical payoff — enough stops per sweep and
+		one lands inside the zone by arithmetic rather than by skill — so the limiter is doing real
+		work here rather than only bounding cost. The miss-resets-to-zero rule is the other half:
+		a burst of five stops that contains one hit and four misses ends at zero hits.
+
+		NO `typeof` GUARD, BECAUSE THERE IS NO ARGUMENT. Anything a modified client sends is discarded
+		by the argument list itself.
+	]]
+	Remotes.Get("RequestTimingStop").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestTimingStop") then
+			return
+		end
+
+		noteTimingStop(player)
+	end)
```

#### Step 3.3: Publish the bar to the one player standing at it

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:remotes`

`TimingBarChanged`, `FireClient`, on becoming present and on every stop. Between those the client
extrapolates from `Period`, so the send rate is bounded by player **actions** rather than by the tick —
which is the §5 mobile budget answer: a player at a timing point costs about one packet per second,
against the presence heartbeat's four.

```diff
+local barRemote = Remotes.Get("TimingBarChanged")
+
+-- `"{taskId}:{hits}"` for the last bar each client was sent, so a player standing at a timing point
+-- doing nothing costs nothing. Same idea and the same lifecycle as `lastSentProgress`, and cleared
+-- in the same place — a stale entry here would suppress the FIRST bar of the next round.
+local lastSentBar: { [number]: string? } = {}
+
+--[[
+	One task point's bar, to one player. Never FireAllClients.
+
+	Per-player for the same reason `publishProgress` is, and the reason is a leak rather than a
+	saving: `Hits` is a per-point fact that a bystander could read to infer who is standing where.
+	Nobody needs it but the person aiming at the bar.
+
+	Built as a TYPED LOCAL, not an inline table: FireClient takes `...any`, so an inline literal is
+	checked against nothing at all. See Types.TimingBarPayload — the annotation catches a wrong type
+	and a missing field, and NOT an extra one, which is the leak shape.
+]]
+local function publishBar(player: Player, taskId: string)
+	local state = timingState[taskId]
+
+	if state == nil then
+		return
+	end
+
+	local key = `{taskId}:{state.Hits}`
+
+	if lastSentBar[player.UserId] == key then
+		return
+	end
+
+	lastSentBar[player.UserId] = key
+
+	local payload: Types.TimingBarPayload = {
+		TaskId = taskId,
+		Phase = TimingWindow.phaseAt(os.clock() - state.BarStartAt, Config.Tasks.TimingBarPeriod),
+		Period = Config.Tasks.TimingBarPeriod,
+		ZoneCenter = Config.Tasks.TimingZoneCenter,
+		ZoneHalfWidth = Config.Tasks.TimingZoneHalfWidth,
+		Hits = state.Hits,
+		HitsRequired = Config.Tasks.TimingHitsRequired,
+	}
+
+	barRemote:FireClient(player, payload)
+end
```

Fired from the tick's existing per-player pass, so arriving at a timing point sends a bar without a
second loop over the roster:

```diff
 	for _, player in Players:GetPlayers() do
 		local entry = presence[player.UserId]
 		local yours: number? = nil
 
 		if entry ~= nil then
 			for _, task in activeTasks do
 				if task.Id == entry.TaskId then
 					yours = task.Progress
+
+					if task.Type == Enums.TaskType.Timing and not task.Completed then
+						publishBar(player, task.Id)
+					end
+
 					break
 				end
 			end
+		else
+			-- Walked away from a timing point. Forget what they were last sent so that coming back
+			-- re-sends the bar rather than being deduped into silence.
+			lastSentBar[player.UserId] = nil
 		end
```

`onPlayerRemoving` clears the third table beside the two it already clears:

```diff
 local function onPlayerRemoving(player: Player)
 	presence[player.UserId] = nil
 	lastSentProgress[player.UserId] = nil
+	lastSentBar[player.UserId] = nil
 end
```

#### Step 3.4: The client renders the bar it is told about

**Files:** `src/client/Controllers/TaskController.luau`, `src/client/Controllers/InputController.luau`
**Verify:** `npm run analyze`

A cache and a `VerboseLogging` print, plus `InputController` binding the stop to `R`. Delete both
additions and no outcome the server produces changes — the test `TaskController`'s header sets for
itself, applied to the new code.

```diff
 local latest: Types.TaskProgressPayload? = nil
+local latestBar: Types.TimingBarPayload? = nil
 local holding = false
 
 function TaskController.GetLatest(): Types.TaskProgressPayload?
 	return latest
 end
+
+--[[
+	The seam C18 draws the moving bar from.
+
+	`Phase` in the cached payload is where the bar was WHEN THE SERVER SENT IT. C18 renders the live
+	position by advancing it — `(Phase + sinceReceived / Period) % 1` through
+	`TimingWindow.positionFromPhase` — and that extrapolation is a RENDERING and nothing more. The
+	server re-derives the phase from its own clock on every stop, so a client whose bar drifts,
+	freezes or runs backwards gets exactly the same hit decision as one that renders it perfectly.
+]]
+function TaskController.GetLatestBar(): Types.TimingBarPayload?
+	return latestBar
+end
```

```diff
 function TaskController.Init()
 	latest = nil
+	latestBar = nil
 	holding = false
 end
```

```diff
+	Remotes.Get("TimingBarChanged").OnClientEvent:Connect(function(payload: Types.TimingBarPayload)
+		latestBar = payload
+
+		if Config.Debug.VerboseLogging then
+			print(`[Task] bar {payload.TaskId} · {payload.Hits}/{payload.HitsRequired} hits`)
+		end
+	end)
```

And the bind. `R`, not `E` — `E` is already the presence hold, and a timing point wants both: you
stand at it (which is what buys you the bar) and you stop it.

```diff
 local TASK_ACTION = "TaskHold"
+local TIMING_ACTION = "TaskTimingStop"
```

```diff
+--[[
+	NO ROLE GATE, for the reason the hold bind above spells out at length: a client that behaves
+	differently depending on who it is, is a confession waiting to be recorded. Under Amendment A2
+	there is not even a server-side difference left to hide — the Aswang's stops count exactly like
+	anyone else's — but the rule stands on its own and this bind obeys it.
+
+	Unconditional `FireServer` on Begin, with no local check of any kind. There is deliberately no
+	client-side "am I at a timing task" test: the client would have to know which of the five points
+	are TIMING to run one, and the honest cost of not running it is a rate-limit token.
+]]
+local function onTimingAction(
+	_actionName: string,
+	inputState: Enum.UserInputState
+): Enum.ContextActionResult
+	if inputState ~= Enum.UserInputState.Begin then
+		return Enum.ContextActionResult.Pass
+	end
+
+	Remotes.Get("RequestTimingStop"):FireServer()
+
+	return Enum.ContextActionResult.Sink
+end
```

```diff
 	ContextActionService:BindAction(TASK_ACTION, onTaskAction, false, Enum.KeyCode.E)
+	-- `R`, because `E` is the hold and a timing point needs both. `false` for createTouchButton
+	-- matches every other bind in this file: mobile is C27's subject, and this is the fourth known
+	-- hole rather than a new one.
+	ContextActionService:BindAction(TIMING_ACTION, onTimingAction, false, Enum.KeyCode.R)
```

**⚠ `R` is not confirmed free of a CoreScript or ProximityPrompt claim.** C08 shipped unreachable
because `ProximityPrompt`'s default `KeyboardKeyCode = E` silently swallowed the identical bind, and
nothing in the tree proves `R` is not similarly claimed. `attachPrompt` already sets
`Enum.KeyCode.None`, which removes the known collision — but "the known one" is the whole of what can
be claimed statically. This is a **playtester** question, and it is in §4.

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

- **🔑 `check:ratelimit` and `check:remotes` both pass vacuously if Step 3.2's handler is never
  written.** An audit of plan 1 found exactly this shape, and it applies here: neither check can
  detect its own step being deleted. Step 3.2's real proof is the playtester firing
  `RequestTimingStop` from outside the window and being refused; the static check is a floor, not the
  evidence. Named here so the phase is not mistaken for proven by green.
- **Forward declaration order.** `noteTimingStop` calls `publishBar`, which calls `publishProgress`'s
  neighbours, and Luau resolves locals in declaration order — the same constraint plan 1 hit with
  `presence` and `lastSentProgress`. `lastSentBar` and `publishBar` must be declared **above**
  `noteTimingStop`, and `taskById` above `evaluateTimingStop`.
- **Player leaving mid-round (§6.4).** Two cases apply and both are handled: `onPlayerRemoving` clears
  `lastSentBar`, and a task whose bar a departed player was watching keeps its `Hits` — because the
  hits belong to the **point**, not the player, exactly as `Progress` does. A player who lands two
  hits and disconnects leaves those two hits for whoever arrives next. That is §4.4's anti-frustration
  rule applied consistently, and it is worth a playtest note: it is also mildly exploitable as a way
  to bank progress, which is only a problem if timing points become the fast route.
- **Mobile (§5).** No new lights, no particles, no per-frame work. One extra packet per stop, and the
  bar's rendering is C18's. `R` has no touch button, which is the fourth instance of C27's known hole.
- **A `TIMING` task now has two code paths that can complete it** — `noteTimingStop` and, if the
  `continue` in the tick is ever removed, `TaskProgress.tick`. `RoundService.SetTasksCompleted` is
  idempotent and clamped, so the failure mode is a task completing early rather than a corrupt count.
  Still worth an assertion at C41.

### Phase 4: Fetch

#### Step 4.1: `src/server/pure/FetchCarry.luau`

**File:** `src/server/pure/FetchCarry.luau`
**Verify:** `npm run analyze`

`decide(request) -> FetchAction` over a bounded domain. **It takes WEIGHTS, not players and not
roles** — the same structural choice as Phase 5's `TaskParticipants`, and for the same reason: a
module that cannot name a role cannot branch on one, so Amendment A2's rule is inherited rather than
restated.

New file, entire contents:

```diff
+--!strict
+--[[
+	FetchCarry — what should happen to one fetch item this tick? (§4.4, C09)
+
+		decide(request) -> "NONE" | "PICK_UP" | "DELIVER" | "DROP"
+
+	IT TAKES WEIGHTS, NOT PLAYERS, AND THAT IS THE WHOLE SECURITY DESIGN.
+
+	Amendment A2 requires that no code path special-case the Aswang's contribution. The enforceable
+	form of that is `server/pure/TaskWeight.luau` and its `PlayerState × Role` grid; this module
+	inherits the property instead of restating it, because it never sees a role. There is nowhere in
+	this file for a role branch to be written, which is a stronger statement than a comment asking
+	nobody to write one.
+
+	`FullWeight` arrives as a parameter — `Config.Tasks.FullContributionWeight` — so "who may carry"
+	is one number in one file. A GHOST weighs `Config.Ghost.TaskContributionMult` (0.25) and therefore
+	cannot pick an item up, which is C15's answer arrived at for free: §4.7 asks a ghost to contribute
+	to a task, not to move objects through the world.
+
+	DROP OUTRANKS DELIVER, AND THE ORDER IS A DECISION.
+
+	A carrier who is killed while standing on the destination drops the item; they do not complete the
+	errand with their last frame. C09's brief calls dropping on death "correct, and creates good
+	moments" — the moment is the item lying beside the corpse where the next survivor finds it, and it
+	only exists if death beats delivery.
+
+	DROP IS NOT NAMED "DEATH", DELIBERATELY. A carrier stops carrying when they stop being a full
+	contributor, and being killed is one of four ways that happens: disconnecting, being reset, and
+	joining mid-round as a SPECTATOR are the others. A branch per cause would have missed three.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — booleans and numbers only, so Lune runs it.
+]]
+
+export type Action = "NONE" | "PICK_UP" | "DELIVER" | "DROP"
+
+export type Request = {
+	HasCarrier: boolean,
+	-- The carrier's TaskWeight. Meaningless, and ignored, when HasCarrier is false.
+	CarrierWeight: number,
+	CarrierAtDestination: boolean,
+	-- The nearest player standing at the SOURCE, and their TaskWeight. Zero when nobody is there.
+	CandidateWeight: number,
+	CandidateAtSource: boolean,
+	FullWeight: number,
+}
+
+local FetchCarry = {}
+
+function FetchCarry.decide(request: Request): Action
+	if request.HasCarrier then
+		if request.CarrierWeight < request.FullWeight then
+			return "DROP"
+		end
+
+		if request.CarrierAtDestination then
+			return "DELIVER"
+		end
+
+		return "NONE"
+	end
+
+	if request.CandidateAtSource and request.CandidateWeight >= request.FullWeight then
+		return "PICK_UP"
+	end
+
+	return "NONE"
+end
+
+return FetchCarry
```

#### Step 4.2: `tests/fetch-carry.test.luau`

**File:** `tests/fetch-carry.test.luau`
**Verify:** `lune run tests/fetch-carry.test.luau`

The whole grid: `HasCarrier × (PlayerState × Role for the carrier) × CarrierAtDestination ×
(PlayerState × Role for the candidate) × CandidateAtSource` — 2 × 8 × 2 × 8 × 2 = **512 cells, every
one enumerated**, per `.claude/lessons/green-after-each-patch-hides-a-loop.md`.

**The weights are composed through `TaskWeight.forPlayer`, not written by hand.** That is what makes
the role-invariance assertion mean something: if a future edit puts a role branch in `TaskWeight`,
this test goes red too, from the other end.

```diff
+--!strict
+--[[
+	tests/fetch-carry.test.luau
+
+	`server/pure/FetchCarry.luau` over its ENTIRE domain — 512 cells, enumerated.
+
+	THE ASSERTION THAT MATTERS IS THE SECOND ONE. The first says each cell returns what the rule says
+	it should. The second says the answer NEVER CHANGES WHEN A ROLE CHANGES, which is Amendment A2's
+	requirement stated as a property rather than as prose, and is the one that fails if somebody
+	teaches either this module or TaskWeight to care who is carrying.
+
+	The weights come from `TaskWeight.forPlayer` rather than from literals, so the two modules are
+	tested as the composition they are used as.
+]]
+
+local FetchCarry = require("../src/server/pure/FetchCarry")
+local TaskWeight = require("../src/server/pure/TaskWeight")
+
+local STATES = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+local ROLES = { "SURVIVOR", "ASWANG" }
+local BOOLS = { false, true }
+
+local GHOST_MULT = 0.25
+local FULL = 1
+
+local failures = 0
+local assertions = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	assertions += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local function expected(
+	hasCarrier: boolean,
+	carrierWeight: number,
+	atDestination: boolean,
+	candidateWeight: number,
+	atSource: boolean
+): string
+	if hasCarrier then
+		if carrierWeight < FULL then
+			return "DROP"
+		end
+
+		return if atDestination then "DELIVER" else "NONE"
+	end
+
+	return if atSource and candidateWeight >= FULL then "PICK_UP" else "NONE"
+end
+
+for _, hasCarrier in BOOLS do
+	for _, carrierState in STATES do
+		for _, carrierRole in ROLES do
+			for _, atDestination in BOOLS do
+				for _, candidateState in STATES do
+					for _, candidateRole in ROLES do
+						for _, atSource in BOOLS do
+							local carrierWeight =
+								TaskWeight.forPlayer(carrierState, carrierRole, GHOST_MULT)
+							local candidateWeight =
+								TaskWeight.forPlayer(candidateState, candidateRole, GHOST_MULT)
+
+							local action = FetchCarry.decide({
+								HasCarrier = hasCarrier,
+								CarrierWeight = carrierWeight,
+								CarrierAtDestination = atDestination,
+								CandidateWeight = candidateWeight,
+								CandidateAtSource = atSource,
+								FullWeight = FULL,
+							})
+
+							check(
+								`{carrierState}/{carrierRole} carrying={hasCarrier} dest={atDestination} `
+									.. `+ {candidateState}/{candidateRole} src={atSource}`,
+								action
+									== expected(
+										hasCarrier,
+										carrierWeight,
+										atDestination,
+										candidateWeight,
+										atSource
+									),
+								`got {action}`
+							)
+						end
+					end
+				end
+			end
+		end
+	end
+end
+
+--[[
+	AMENDMENT A2, AS A PROPERTY. For every cell, swapping either player's role changes nothing.
+
+	This is the assertion a future "the Aswang cannot carry the item" change has to fight. Note what
+	it would cost if it won: a fetch item that refuses to be picked up names the monster to anyone
+	watching it not move, which is the same oracle A2 removed from the hold bar.
+]]
+for _, hasCarrier in BOOLS do
+	for _, carrierState in STATES do
+		for _, atDestination in BOOLS do
+			for _, candidateState in STATES do
+				for _, atSource in BOOLS do
+					local seen: { [string]: boolean } = {}
+
+					for _, carrierRole in ROLES do
+						for _, candidateRole in ROLES do
+							seen[FetchCarry.decide({
+								HasCarrier = hasCarrier,
+								CarrierWeight = TaskWeight.forPlayer(
+									carrierState,
+									carrierRole,
+									GHOST_MULT
+								),
+								CarrierAtDestination = atDestination,
+								CandidateWeight = TaskWeight.forPlayer(
+									candidateState,
+									candidateRole,
+									GHOST_MULT
+								),
+								CandidateAtSource = atSource,
+								FullWeight = FULL,
+							})] = true
+						end
+					end
+
+					local distinct = 0
+
+					for _ in seen do
+						distinct += 1
+					end
+
+					check(
+						`role does not change the action ({carrierState}/{candidateState}, `
+							.. `carrying={hasCarrier}, dest={atDestination}, src={atSource})`,
+						distinct == 1,
+						`{distinct} distinct actions across the four role pairings`
+					)
+				end
+			end
+		end
+	end
+end
+
+-- §4.7 forward case, stated once explicitly so it is findable by name at C15 rather than only
+-- implied by 512 cells: a ghost cannot pick the item up.
+check(
+	"a ghost cannot carry a fetch item",
+	FetchCarry.decide({
+		HasCarrier = false,
+		CarrierWeight = 0,
+		CarrierAtDestination = false,
+		CandidateWeight = TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
+		CandidateAtSource = true,
+		FullWeight = FULL,
+	}) == "NONE"
+)
+
+if failures > 0 then
+	error(`{failures} fetch-carry failure(s)`, 0)
+end
+
+print(`  PASS  fetch-carry: {assertions} assertions over the full 512-cell grid`)
```

#### Step 4.3: Discover the fetch sources and spawn the items

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run verify:fast`

A `FetchSource` tag, discovered exactly as `TaskPoint` is, paired to a `FETCH` task by a
`FetchSourceName` attribute on the task point with **furthest-unused** as the fallback. Items are
created at `STARTING` and destroyed by `clearTasks`.

**Furthest, not nearest.** §4.4 buys one thing with the fetch task — *"forces travel across the map —
creates isolation"* — and pairing a task point with the source nearest to it buys none of it. When the
map does not state a pairing, the fallback should produce the errand, not the shortest walk. C17 will
state pairings explicitly; until then the fallback is what the rig exercises.

```diff
 local TAG_POINT = "TaskPoint"
 local TAG_ACTIVE = "ActiveTaskPoint"
+local TAG_SOURCE = "FetchSource"
+-- On the item itself, so a human looking at the workspace can tell a fetch item from set dressing,
+-- and so C17 can find and delete every one the rig left behind. It names an object, not a person:
+-- `check:secrecy` inspects tag names and this one carries no role and no UserId.
+local TAG_ITEM = "FetchItem"
```

```diff
+--[[
+	FETCH state (§4.4, C09). SERVER-ONLY, keyed by task Id.
+
+	`CarrierUserId` is the one piece of this that is genuinely private, and it is nil far more often
+	than not. It is never attributed, never tagged and never sent: the ITEM's position states who is
+	carrying it, one tick later, to everybody — which is the game working, and is why nothing here
+	needs to cross the wire.
+]]
+type FetchState = {
+	SourceName: string,
+	Item: BasePart,
+	CarrierUserId: number?,
+}
+
+local fetchState: { [string]: FetchState } = {}
+local sourcesByName: { [string]: BasePart } = {}
```

Discovery, beside `discoverPool` and rebuilt on every call for the same reason it gives — C17 will add
and move these parts while a server is running:

```diff
+local function discoverSources()
+	table.clear(sourcesByName)
+
+	for _, instance in CollectionService:GetTagged(TAG_SOURCE) do
+		if not instance:IsA("BasePart") then
+			warn(
+				`[TaskService] {instance:GetFullName()} is tagged {TAG_SOURCE} but is a `
+					.. `{instance.ClassName}, not a BasePart — skipped.`
+			)
+			continue
+		end
+
+		if sourcesByName[instance.Name] == nil then
+			sourcesByName[instance.Name] = instance
+		end
+	end
+end
```

The pairing and the item, run from `selectForRound` after the loop that builds `activeTasks`:

```diff
+--[[
+	One fetch item per FETCH task drawn this round.
+
+	A `FETCH` task with no source available is DEMOTED TO HOLD and says so, loudly. The alternative —
+	a task that can never be started — is a round stuck at 4/5 with no symptom, which is the exact
+	failure class `taskPointAt`'s nearest-incomplete fix was written to delete. A demoted task is
+	playable and wrong; an unstartable one is unplayable and silent.
+]]
+local function setUpFetchTasks()
+	discoverSources()
+
+	local used: { [string]: boolean } = {}
+
+	for _, task in activeTasks do
+		if task.Type ~= Enums.TaskType.Fetch then
+			continue
+		end
+
+		local point = activeParts[task.Id]
+
+		if point == nil then
+			continue
+		end
+
+		local named = point:GetAttribute("FetchSourceName")
+		local source: BasePart? = if typeof(named) == "string" then sourcesByName[named] else nil
+
+		if source == nil then
+			-- FURTHEST unused, because the travel IS the task (§4.4).
+			local bestDistance = -1
+
+			for name, candidate in sourcesByName do
+				local distance = (candidate.Position - point.Position).Magnitude
+
+				if not used[name] and distance > bestDistance then
+					source = candidate
+					bestDistance = distance
+				end
+			end
+		end
+
+		if source == nil then
+			warn(
+				`[TaskService] {task.Id} asks for {Enums.TaskType.Fetch} but no unused "{TAG_SOURCE}" `
+					.. `part is available. Demoting it to {Enums.TaskType.Hold} — tag more source `
+					.. `anchors, or the round is one task harder than it looks.`
+			)
+
+			task.Type = Enums.TaskType.Hold
+			continue
+		end
+
+		used[source.Name] = true
+
+		local item = Instance.new("Part")
+
+		item.Name = `FetchItem_{task.Id}`
+		item.Size = Vector3.one -- config-ok: placeholder prop dimensions, replaced by a model at C17
+		item.Anchored = true
+		item.CanCollide = false
+		item.CFrame = source.CFrame
+		item.Parent = workspace
+
+		CollectionService:AddTag(item, TAG_ITEM)
+
+		fetchState[task.Id] = { SourceName = source.Name, Item = item, CarrierUserId = nil }
+	end
+end
```

Torn down with everything else, in `clearTasks`:

```diff
+	for _, state in fetchState do
+		state.Item:Destroy()
+	end
+
+	table.clear(fetchState)
 	table.clear(presence)
```

#### Step 4.4: Pick up, carry, deliver, and drop where you die

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:config`

Presence at the source picks the item up; presence at the destination while carrying accumulates over
`FetchDeliverTime`. A carrier who stops being a full contributor — killed, disconnected, spectating —
drops it, and because the tick has been moving the item with them, it is already lying where they fell.

**No new remote and no new client input.** Picking up is *proximity*, evaluated on the server tick, so
the entire fetch mechanic is unreachable from a client except by walking. That is the cheapest possible
answer to "the server tracks the carry" and it is why C09 needs only one new UP remote rather than two.

**How the drop finds the death position.** It does not look one up. The tick has been re-anchoring the
item to the carrier every 250 ms, so at the moment they die the item is already within a quarter-second
of where they fell; dropping is nothing but *ceasing to move it*. This also sidesteps a real trap:
`MonsterService` sets `player.Character = nil` to build the corpse **before** `RoundService.MarkKilled`
runs (`RoundService.luau:680-683`), so a drop handler asking for the carrier's position would find
none.

```diff
+--[[
+	THE CARRY (§4.4, C09). One pass, on the same 4 Hz tick as everything else.
+
+	IT DERIVES EVERY DECISION FROM A WEIGHT, never from a role or a state directly, so the rule
+	`server/pure/FetchCarry.luau` implements is the rule that runs. `weightFor` is the same function
+	the hold uses — see its comment for why the role it passes is a constant.
+
+	`item.CFrame` IS ASSIGNED AT 4 Hz AND THAT IS A KNOWN, ACCEPTED ROUGHNESS. A carried item visibly
+	steps rather than glides. The smooth version is a WeldConstraint to the carrier's root part, which
+	needs the part unanchored and hands physics ownership to the carrying client — a change with a
+	replication story this plan has not verified, on the one object in the round a player might want to
+	desync. It is in Follow Ups for C18, where the item stops being a grey cube anyway.
+]]
+local function tickFetch()
+	for taskId, state in fetchState do
+		local task = taskById(taskId)
+
+		if task == nil or task.Completed then
+			continue
+		end
+
+		local carrier = if state.CarrierUserId ~= nil
+			then Players:GetPlayerByUserId(state.CarrierUserId)
+			else nil
+		local source = sourcesByName[state.SourceName]
+		local point = activeParts[taskId]
+
+		-- The nearest full-weight player standing at the source, if any. Nearest so that two players
+		-- arriving together resolve deterministically rather than by hash order — the same argument
+		-- `TaskResolve` makes at length.
+		local candidate: Player? = nil
+		local candidateWeight = 0
+
+		if source ~= nil and carrier == nil then
+			local bestDistance = Config.Tasks.PresenceRangeStuds
+
+			for _, player in Players:GetPlayers() do
+				local position = positionOf(player)
+
+				if position ~= nil then
+					local distance = (position - source.Position).Magnitude
+
+					if distance <= bestDistance then
+						candidate = player
+						candidateWeight = weightFor(player)
+						bestDistance = distance
+					end
+				end
+			end
+		end
+
+		local carrierPosition = if carrier ~= nil then positionOf(carrier) else nil
+		local atDestination = carrierPosition ~= nil
+			and point ~= nil
+			and (carrierPosition - point.Position).Magnitude <= Config.Tasks.PresenceRangeStuds
+
+		local action = FetchCarry.decide({
+			HasCarrier = carrier ~= nil,
+			CarrierWeight = if carrier ~= nil then weightFor(carrier) else 0,
+			CarrierAtDestination = atDestination,
+			CandidateWeight = candidateWeight,
+			CandidateAtSource = candidate ~= nil,
+			FullWeight = Config.Tasks.FullContributionWeight,
+		})
+
+		if action == "PICK_UP" and candidate ~= nil then
+			state.CarrierUserId = candidate.UserId
+		elseif action == "DROP" then
+			-- Nothing is moved. The item is already lying wherever the tick last put it, which is
+			-- within 250 ms of where the carrier stopped being one. That IS the drop.
+			state.CarrierUserId = nil
+		end
+
+		-- Re-read: PICK_UP set it this tick, and the item should follow immediately rather than
+		-- staying at the source for one more frame.
+		local holder = if state.CarrierUserId ~= nil
+			then Players:GetPlayerByUserId(state.CarrierUserId)
+			else nil
+		local holderPosition = if holder ~= nil then positionOf(holder) else nil
+
+		if holderPosition ~= nil then
+			-- config-ok: carry visual offset above the root part, replaced by a weld at C18
+			state.Item.CFrame = CFrame.new(holderPosition + Vector3.new(0, 3, 0))
+		end
+	end
+end
```

The tick's weight pass learns one rule — **only the carrier advances a fetch task**:

```diff
 		local resolved = taskPointAt(player)
 
 		if resolved ~= entry.TaskId then
 			continue
 		end
 
+		--[[
+			A FETCH task advances only for the player carrying its item. Standing at the destination
+			empty-handed is not the task; walking to the source and back is.
+
+			This reads `fetchState` rather than a role or a name, so it is the same rule for everyone.
+		]]
+		local fetch = fetchState[entry.TaskId]
+
+		if fetch ~= nil and fetch.CarrierUserId ~= userId then
+			continue
+		end
+
 		local bucket = weights[entry.TaskId]
```

The duration is now per type rather than always `HoldTime`:

```diff
+--[[
+	How long this task takes at full contribution. ONE FUNCTION, so a fifth task type at some later
+	chunk has exactly one place to be wrong.
+
+	TIMING never reaches here — the tick skips it — but it is listed rather than omitted, because an
+	unlisted type falls through to HoldTime silently and that is the shape of a balance bug nobody
+	reports.
+]]
+local function durationFor(task: Types.ActiveTask): number
+	if task.Type == Enums.TaskType.Fetch then
+		return Config.Tasks.FetchDeliverTime
+	elseif task.Type == Enums.TaskType.TwoPerson then
+		return Config.Tasks.TwoPersonTime
+	end
+
+	return Config.Tasks.HoldTime
+end
```

```diff
 		local weight = TaskProgress.strongestWeight(weights[task.Id] or {})
-		local result = TaskProgress.tick(task.Progress, elapsed, weight, Config.Tasks.HoldTime)
+		local result = TaskProgress.tick(task.Progress, elapsed, weight, durationFor(task))
 
 		task.Progress = result.Progress
 
 		if result.Completed then
 			task.Completed = true
 			anyCompleted = true
+
+			-- The errand is over, so the prop goes. Leaving it welded to a survivor for the rest of
+			-- the round is a permanent, replicated marker on one player, which is a thing this game
+			-- should never grow casually.
+			local fetch = fetchState[task.Id]
+
+			if fetch ~= nil then
+				fetch.Item:Destroy()
+				fetchState[task.Id] = nil
+			end
```

`tickFetch()` is called from `tick()` **before** the weight pass, so a pickup this tick is visible to
it, and after the ACTIVE/`#activeTasks` early return so it cannot run outside a round.

#### Step 4.5: The disposable `FetchSource` anchors

**File:** `.claude/plans/feature-c09-c12-tasks-gate-plan/artifacts/fetch-rig.md`
**Verify:** `test -f .claude/plans/feature-c09-c12-tasks-gate-plan/artifacts/fetch-rig.md`

Four anchors added to `workspace.TaskRig_TEMP`, and two task pads given `TaskType = "FETCH"`. Not a
deliverable, not the greybox; C17 replaces it. The written record is the step's output because **the
place file is not in Git** — a missing prop never shows up in `git status`.

Follow `artifacts/task-rig.md` exactly; it is the template and it is good.

- Four `Part`s in `workspace.TaskRig_TEMP`, tagged `FetchSource`, named `FetchSource_01`…`_04`, placed
  **outside** the 4×3 pad grid (`X = {-45, -15, 15, 45}` by `Z = {-30, 0, 30}`, 30-stud pitch) so the
  furthest-unused fallback produces a walk worth timing against `Config.Tasks.FetchTime = 25`.
- `TaskType = "FETCH"` set on **two** pads, and `TaskType = "TIMING"` on **one** — Phase 3 has no rig
  of its own and this is where it gets one. Leave the rest absent, so the `nil → HOLD` default that
  the whole map relies on keeps being exercised (`task-rig.md` §1 makes this argument for pad 01).
- Record: the measured distance from each `FETCH` pad to the source the fallback actually chose, the
  console line from a round that drew a `FETCH` task, and one `FetchItem_*` part existing in
  `Workspace` during `ACTIVE` and **gone** during `INTERMISSION`.
- **Measure through datamodel state or `get_console_output` only.** `execute_luau`'s `require` returns
  a fresh, separately stale copy of a module — it read `IDLE` from a live `ACTIVE` service and a
  `Config.Tasks` missing a committed knob. Both incidents are in plan 1's artifacts. Tag counts and
  instance properties do not have this problem, which is why every measurement above is one.
- `screen_capture` excludes CoreGui, so no ProximityPrompt UI will appear in any capture. Do not
  spend a turn trying.

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

- **🔒 The fetch item is a tracking device and it is meant to be.** A part that follows one player at
  4 Hz is a replicated marker on that player, readable by everyone, and this is the largest new
  information surface in the plan. It is *safe* only because it is role-blind: any full-weight player
  can pick it up, and the item says "this player is doing the fetch task", never "this player is the
  Aswang". **The moment anything makes carrying role-dependent, this becomes a live oracle in the
  workspace with no remote to intercept and nothing for `check:secrecy` to see.** `FetchCarry`'s
  weights-not-roles signature and its 512-cell grid are what hold that line.
- **The item survives its carrier's disconnect, deliberately.** `tickFetch` reads
  `Players:GetPlayerByUserId`, which returns nil for a departed player, so `weightFor` is never
  called on them and the action is `DROP`. The item stays where it was. §6.4 says "finish the round";
  an errand whose item vanished with a phone losing signal would be a task that cannot be finished.
- **Two `FETCH` tasks can compete for one source.** `used` prevents it within a round's setup, but a
  pool with fewer `FetchSource` anchors than `FETCH` tasks drawn demotes the surplus to `HOLD` with a
  warning. That is a map defect and belongs to C17; the code stays playable rather than correct.
- **`Vector3.one` and the `(0, 3, 0)` offset are placeholders carrying waivers.** Both are visual, both
  are C17/C18's, and both would fail `check:config` unwaived. A waiver with a reason shows up in a
  diff, which is the point.
- **§5 mobile budget.** `tickFetch` is `#fetchState × #players` distance comparisons at 4 Hz — at most
  two items and eight players, so sixteen per tick, on top of the forty the hold already does. No
  lights, no particles, no client per-frame work.
- **A player carrying an item into `ENDING` keeps it visible on the end screen.** `clearTasks` runs on
  the way into `INTERMISSION`, not out of `ACTIVE` — the rule plan 1 established so a round that
  finished 4/5 can still show it. The item hanging over a survivor for twelve seconds of end screen is
  a cosmetic oddity worth a playtest note, not a fix.

### Phase 5: Two-person

#### Step 5.1: `src/server/pure/TaskParticipants.luau`

**File:** `src/server/pure/TaskParticipants.luau`
**Verify:** `npm run analyze`

`count(weights, fullWeight)` and `meets(weights, required, fullWeight)`. It takes the **weights**
`TaskWeight` already produced — not players, not roles, not states — so "the Aswang counts as a full
participant" is not a rule this module implements, it is a rule it cannot express the opposite of.

New file, entire contents:

```diff
+--!strict
+--[[
+	TaskParticipants — how many people are really doing this task? (§4.4 + Amendment A2, C10)
+
+		count(weights, fullWeight)            -> how many are contributing in full
+		meets(weights, required, fullWeight)  -> is that enough
+
+	THIS MODULE EXISTS TO INHERIT A PROPERTY RATHER THAN TO RESTATE ONE.
+
+	Amendment A2, in its own words: *"C10's participant count must be derived from the same weights,
+	so that it inherits the property instead of restating it."* The property is
+	`server/pure/TaskWeight.luau`'s — for any given PlayerState, weight does not vary by Role — and
+	the way this module inherits it is by taking NUMBERS. A role cannot reach here. There is no
+	parameter for one, no branch that could read one, and `tests/task-participants.test.luau`
+	composes the two modules so a role branch introduced in either goes red in this one.
+
+	WHY IT MATTERS MORE HERE THAN ANYWHERE ELSE. A2 calls the two-person task "the sharpest case": a
+	survivor and the Aswang standing at a task that produces nothing is an INSTANT reveal with nothing
+	to deduce — strictly worse than the frozen hold bar the amendment was written to delete. §4.4's
+	own description of this task ("the Aswang can 'help' you and then betray you") only works if the
+	help is real, and this file is where "real" is defined.
+
+	FULL CONTRIBUTORS ONLY, AND THAT SETTLES C15 IN ADVANCE. A GHOST weighs
+	Config.Ghost.TaskContributionMult (0.25) against a FullContributionWeight of 1, so two ghosts do
+	not open a two-person task. §4.4 asks for "2 survivors present"; §4.7 asks ghosts to "still
+	matter", not to substitute for the living. `tests/config.test.luau` pins the relation between
+	those two numbers, because it is the whole of what separates those two sentences.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — a list of numbers, so Lune runs it.
+]]
+
+local TaskParticipants = {}
+
+-- `>=`, not `==`. A weight above full is not a state this game produces today, and a future one that
+-- did (a buff, a two-handed prop) should count as a participant rather than silently stop counting.
+function TaskParticipants.count(weights: { number }, fullWeight: number): number
+	local total = 0
+
+	for _, weight in weights do
+		if weight >= fullWeight then
+			total += 1
+		end
+	end
+
+	return total
+end
+
+function TaskParticipants.meets(weights: { number }, required: number, fullWeight: number): boolean
+	return TaskParticipants.count(weights, fullWeight) >= required
+end
+
+return TaskParticipants
```

#### Step 5.2: `tests/task-participants.test.luau`

**File:** `tests/task-participants.test.luau`
**Verify:** `lune run tests/task-participants.test.luau`

The grid A2 asks for, composed through `TaskWeight`: every **pair** of `PlayerState × Role` — 8 × 8 =
64 cells — mapped to weights and then to a participant count, asserting the count never varies by role,
plus the C15 forward case and the named case A2 calls the sharpest.

```diff
+--!strict
+--[[
+	tests/task-participants.test.luau
+
+	`server/pure/TaskParticipants.luau` composed with `TaskWeight`, over every pair of players.
+
+	THE NAMED CASE IS THE LAST ASSERTION IN THIS FILE and it is the reason the file exists:
+	an ALIVE survivor beside an ALIVE Aswang satisfies a two-person task. Amendment A2 requires it,
+	§4.4's "the Aswang can 'help' you and then betray you" depends on it, and a pair producing no
+	progress would be an instantaneous reveal with nothing to deduce.
+]]
+
+local TaskParticipants = require("../src/server/pure/TaskParticipants")
+local TaskWeight = require("../src/server/pure/TaskWeight")
+
+local STATES = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+local ROLES = { "SURVIVOR", "ASWANG" }
+
+local GHOST_MULT = 0.25
+local FULL = 1
+local REQUIRED = 2
+
+local failures = 0
+local assertions = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	assertions += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+-- Every pair, both roles on both sides. The expected count is derived from the STATES alone, which
+-- is the assertion: if the roles mattered, this expectation would be unwriteable.
+for _, stateA in STATES do
+	for _, stateB in STATES do
+		local expected = (if stateA == "ALIVE" then 1 else 0) + (if stateB == "ALIVE" then 1 else 0)
+
+		for _, roleA in ROLES do
+			for _, roleB in ROLES do
+				local weights = {
+					TaskWeight.forPlayer(stateA, roleA, GHOST_MULT),
+					TaskWeight.forPlayer(stateB, roleB, GHOST_MULT),
+				}
+
+				check(
+					`{stateA}/{roleA} + {stateB}/{roleB} counts {expected}`,
+					TaskParticipants.count(weights, FULL) == expected,
+					`got {TaskParticipants.count(weights, FULL)}`
+				)
+
+				check(
+					`{stateA}/{roleA} + {stateB}/{roleB} meets {REQUIRED} iff {expected} >= {REQUIRED}`,
+					TaskParticipants.meets(weights, REQUIRED, FULL) == (expected >= REQUIRED)
+				)
+			end
+		end
+	end
+end
+
+-- An empty task point. Not a hypothetical: it is the normal state of four of the five.
+check("nobody present is nobody participating", TaskParticipants.count({}, FULL) == 0)
+
+-- §4.7 forward case (C15): ghosts help, ghosts do not substitute.
+check(
+	"two ghosts do not open a two-person task",
+	not TaskParticipants.meets({
+		TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
+		TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
+	}, REQUIRED, FULL)
+)
+
+--[[
+	AMENDMENT A2's SHARPEST CASE, ASSERTED BY NAME.
+
+	It is already covered by the grid above. It is written out again because the grid proves it as one
+	cell among 256, and this is the sentence somebody will come looking for when they are about to
+	make the Aswang not count. A2: "A pair that stood there producing nothing would be an
+	instantaneous reveal with nothing to deduce."
+]]
+check(
+	"a survivor and the Aswang together complete a two-person task",
+	TaskParticipants.meets({
+		TaskWeight.forPlayer("ALIVE", "SURVIVOR", GHOST_MULT),
+		TaskWeight.forPlayer("ALIVE", "ASWANG", GHOST_MULT),
+	}, REQUIRED, FULL)
+)
+
+if failures > 0 then
+	error(`{failures} task-participants failure(s)`, 0)
+end
+
+print(`  PASS  task-participants: {assertions} assertions over every PlayerState x Role pair`)
```

#### Step 5.3: Wire `TWO_PERSON` into the tick

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run verify:fast`

The tick already collects a weight bucket per task. A `TWO_PERSON` task advances only when that bucket
meets the participant requirement, over `Config.Tasks.TwoPersonTime` (already wired by Step 4.4's
`durationFor`). One player alone contributes a bucket of one and the bar does not move.

**Three lines of service code**, because Phases 4 and 5 built the parts. That is the whole point of
having done them in that order.

```diff
 		local weight = TaskProgress.strongestWeight(weights[task.Id] or {})
+
+		--[[
+			§4.4's two-person task (C10). "Requires 2 survivors present at once."
+
+			The requirement is checked against the WEIGHTS the pass above already collected, so the
+			answer comes from `TaskWeight` and cannot depend on who anybody is — see
+			`server/pure/TaskParticipants.luau`'s header, and Amendment A2, which makes the Aswang a
+			full participant deliberately. A survivor-and-Aswang pair completes this task normally.
+
+			Zeroing the weight rather than skipping the task is what makes the bar FREEZE instead of
+			resetting when the second person walks away — §4.4's anti-frustration rule, delivered by
+			`TaskProgress.tick`'s existing `weight <= 0` guard rather than by new code here.
+		]]
+		if
+			task.Type == Enums.TaskType.TwoPerson
+			and not TaskParticipants.meets(
+				weights[task.Id] or {},
+				Config.Tasks.TwoPersonParticipants,
+				Config.Tasks.FullContributionWeight
+			)
+		then
+			weight = 0
+		end
+
 		local result = TaskProgress.tick(task.Progress, elapsed, weight, durationFor(task))
```

**One consequence worth stating plainly, because it is the opposite of what `strongestWeight` does
elsewhere:** a two-person task does not go *faster* with three people. The max rule still governs the
rate; the participant count only governs whether the rate is nonzero. §4.4 asks for "requires 2", not
"scales with N", and the max rule's own header explains why any per-player difference showing up in a
bar's *speed* is arithmetic a bystander can read.

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

- **🔒 This is the phase Amendment A2 was written for, and static green proves almost none of it.**
  `check:secrecy` cannot see a participant count; the Lune grid proves the *rule*, and the
  **playtester with two live clients** proves the wiring. C10's own Done condition is explicitly
  multi-client ("one player alone makes no progress; two do"), and plan 1's verification named
  multi-client behaviour as its single largest untested area — *"a Studio UI action no agent can
  drive"*. This phase inherits that gap whole. **Do not report C10 as verified on a Lune pass.**
- **A round can draw five `TWO_PERSON` points.** At `Round.MinPlayers = 3` — one Aswang, two survivors
  — that is completable only if both survivors move together all round, and one death makes the round
  unwinnable at 0/5. The draw is type-blind by design (§4.4), so the fix is the **map's mix**, which
  is C17's. Raised in §4; it is a genuine cold-start risk against §9.
- **`Config.Round.MinPlayers = 3` is the floor, and two-person tasks are the reason to re-read it at
  M12.** The task is designed for a group; at three players it is a coin flip on whether the two
  survivors happen to be together.
- **Player leaving mid-round (§6.4).** Handled by construction and worth stating: the second person
  leaving drops the bucket to one, `meets` goes false, the weight becomes 0 and `TaskProgress.tick`
  freezes. Nothing resets, nothing is lost, and whoever arrives next resumes from where it stopped.
- **No new remote, no new handler, no new client input.** `check:remotes` and `check:ratelimit` have
  nothing to say about this phase in either direction, which is why `verify:fast` is the check and
  the Lune grid is the evidence.

### Phase 6: 🔒 The escape gate and the survivors' win

#### Step 6.1: `src/server/pure/GateEscape.luau`

**File:** `src/server/pure/GateEscape.luau`
**Verify:** `npm run analyze`

`escapes(request) -> boolean`. The one place in this plan where a role legitimately changes an outcome,
isolated into six lines so the rule is a grid a terminal can fail rather than a branch buried in a
service loop.

New file, entire contents:

```diff
+--!strict
+--[[
+	GateEscape — did this player just win the round for the survivors? (§4.8, C11)
+
+		escapes(request) -> boolean
+
+	THE ONE MODULE IN M3 THAT READS A ROLE, AND IT IS ISOLATED FOR EXACTLY THAT REASON.
+
+	Every other rule in this milestone is role-blind by construction — `TaskWeight` proves it,
+	`FetchCarry` and `TaskParticipants` inherit it, and Amendment A2 explains at length why a rule
+	that varies by role tends to become an oracle. §4.8 nevertheless says *"at least 1 SURVIVOR
+	reaches the escape gate"*, and the Aswang walking into an open gate must not end the round in the
+	survivors' favour. So one branch is required, and this is it: six lines, one file, one exhaustive
+	test, rather than a condition inside a service loop where nobody enumerates it.
+
+	WHAT IT LEAKS, STATED RATHER THAN HOPED AWAY. A bystander who watches a player stand in an open
+	gate while the round does NOT end has learned that player is the Aswang. That inference is a
+	property of §4.8's rule and no implementation removes it. What the implementation controls is that
+	NOTHING ELSE distinguishes the two cases: no refusal is returned, no verdict is sent, no sound is
+	played to one player, and the gate looks and behaves identically for everyone. The only observable
+	is whether the round ends, which is a fact about the round. See the plan's §1.4.
+
+	ALL FOUR CONDITIONS, NOT THREE. Dropping any one of them is a real bug with a plausible cause:
+
+	  · GateOpen  — 5/5 is half of §4.8's rule; without it the gate wins the round at 0/5
+	  · Role      — the Aswang wins by kills or by the clock, never by walking out
+	  · State     — a GHOST is not "at least 1 survivor". §4.7's ghosts fly, and a flying dead player
+	                ending the round is the shape C15 would otherwise ship
+	  · Distance  — §4.8 says survivors "must physically reach it"
+
+	NO `script.Parent` REQUIRES and no Vector3 — a scalar distance, computed at the call site, so Lune
+	runs this. The two unions are re-declared locally; Luau unions are structural.
+]]
+
+export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+export type Role = "SURVIVOR" | "ASWANG"
+
+export type Request = {
+	GateOpen: boolean,
+	PlayerState: PlayerState,
+	Role: Role,
+	-- Studs from the player to the gate, measured by the caller against the server's own copy of the
+	-- world. Never a client-supplied number.
+	Distance: number,
+	Range: number,
+}
+
+local GateEscape = {}
+
+-- `<=` so the boundary counts, matching every other distance rule in this game (`KillValidation`
+-- and `TaskResolve` both). A player standing exactly at the range has reached it.
+function GateEscape.escapes(request: Request): boolean
+	return request.GateOpen
+		and request.Role == "SURVIVOR"
+		and request.PlayerState == "ALIVE"
+		and request.Distance <= request.Range
+end
+
+return GateEscape
```

#### Step 6.2: `tests/gate-escape.test.luau`

**File:** `tests/gate-escape.test.luau`
**Verify:** `lune run tests/gate-escape.test.luau`

Exhaustive over `gateOpen × PlayerState × Role × (inside, on the boundary, outside, far)` — 2 × 4 × 2
× 4 = **64 cells**. The assertion with teeth: **no cell where the role is `ASWANG` ever returns
true**, including at zero distance through a wide-open gate.

```diff
+--!strict
+--[[
+	tests/gate-escape.test.luau
+
+	`server/pure/GateEscape.luau` over its entire domain — 64 cells.
+
+	TWO ASSERTIONS PER CELL, AND THE SECOND IS THE 🔒 ONE. The first checks the cell against the rule.
+	The second is a standing property: the Aswang never escapes, in any state, at any distance,
+	through any gate. It is separated out because it is the sentence a future edit will be arguing
+	with, and a property stated once is easier to defend than one implied by a table.
+]]
+
+local GateEscape = require("../src/server/pure/GateEscape")
+
+local STATES = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+local ROLES = { "SURVIVOR", "ASWANG" }
+local OPENS = { false, true }
+
+local RANGE = 6
+-- Inside, exactly on the boundary, one stud past it, and nowhere near. The boundary case is the one
+-- that catches `<` where `<=` was meant.
+local DISTANCES = { 0, RANGE, RANGE + 1, 400 }
+
+local failures = 0
+local assertions = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	assertions += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+for _, open in OPENS do
+	for _, state in STATES do
+		for _, role in ROLES do
+			for _, distance in DISTANCES do
+				local request = {
+					GateOpen = open,
+					PlayerState = state,
+					Role = role,
+					Distance = distance,
+					Range = RANGE,
+				}
+				local expected = open and role == "SURVIVOR" and state == "ALIVE" and distance <= RANGE
+
+				check(
+					`open={open} {state}/{role} at {distance} studs`,
+					GateEscape.escapes(request) == expected,
+					`got {GateEscape.escapes(request)}`
+				)
+
+				--[[
+					🔒 §4.8. The Aswang wins by kills or by the clock — never by walking out of the
+					map. Asserted in EVERY cell rather than once, so there is no combination of state,
+					distance and gate condition where it holds only by accident.
+				]]
+				if role == "ASWANG" then
+					check(
+						`the Aswang never escapes (open={open}, {state}, {distance} studs)`,
+						not GateEscape.escapes(request)
+					)
+				end
+			end
+		end
+	end
+end
+
+-- §4.7 forward case (C15). A ghost can fly (Config.Ghost.FlySpeed), so "reaching" the gate is the
+-- one thing a dead player finds easiest. It must not end the round.
+check(
+	"a ghost standing in an open gate does not win the round",
+	not GateEscape.escapes({
+		GateOpen = true,
+		PlayerState = "GHOST",
+		Role = "SURVIVOR",
+		Distance = 0,
+		Range = RANGE,
+	})
+)
+
+-- Half of §4.8 is the 5/5. A gate that has not opened cannot be walked through, however close you
+-- stand and whoever you are.
+check(
+	"a shut gate ends nothing",
+	not GateEscape.escapes({
+		GateOpen = false,
+		PlayerState = "ALIVE",
+		Role = "SURVIVOR",
+		Distance = 0,
+		Range = RANGE,
+	})
+)
+
+if failures > 0 then
+	error(`{failures} gate-escape failure(s)`, 0)
+end
+
+print(`  PASS  gate-escape: {assertions} assertions over the full 64-cell grid`)
```

#### Step 6.3: `RoundService` writes `GateOpen` for the first time

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run check:secrecy`

`SetTasksCompleted` derives `GateOpen` from the count and the phase, and pushes a snapshot immediately
when the flag flips. `IsGateOpen()` joins the query block. **`setPhase` stays private and untouched**,
and `GateService` never writes any of this — it reads.

**`RoundService.SetTasksCompleted` MOVES**, from the Queries block (`RoundService.luau:107`) to
directly below `broadcastSnapshot` (`:519`). It has to: Luau resolves locals in declaration order, and
`broadcastSnapshot` is a local declared 400 lines after the function that now needs to call it. This is
the same constraint plan 1 hit with `presence` and `lastSentProgress`. Moving it is safe — it is a
field on the `RoundService` table, called at runtime by `TaskService`, so only the *declaration* order
matters — and it is a pure move with the additions below layered on top.

```diff
+function RoundService.IsGateOpen(): boolean
+	return state.GateOpen
+end
```

```diff
+--[[
+	How many of this round's tasks are done (§4.4, C08) AND, since C11, whether the gate is open.
+	WRITTEN BY TaskService, READ BY THE SNAPSHOT.
+
+	[... the existing comment is kept verbatim; the paragraphs below are added ...]
+
+	THE GATE IS DERIVED HERE AND NOWHERE ELSE (§4.8, C11). It is not a second piece of state anybody
+	sets — it is a function of the count and the phase, computed at the one moment the count can
+	change. That is deliberate: a `GateOpen` with its own writer is a `GateOpen` that can disagree
+	with the task bar, and "the HUD says 5/5 but the gate is shut" is a bug report with no thread to
+	pull.
+
+	THE PHASE CONDITION IS NOT DECORATION. `clearTasks` calls this with 0 on the way into both
+	INTERMISSION and IDLE, so the count alone would already close the gate — but `enterEnding` does
+	not touch the count, and a gate left open across ENDING would be visibly open on the end screen of
+	a round the Aswang won on the clock.
+
+	THIS FUNCTION MOVED for C11: it now calls `broadcastSnapshot`, a local declared several hundred
+	lines below where it used to sit, and Luau resolves locals in declaration order.
+]]
 function RoundService.SetTasksCompleted(count: number)
 	state.TasksCompleted = math.clamp(count, 0, Config.Tasks.TotalRequired)
+
+	local open = state.Phase == Enums.RoundPhase.Active
+		and state.TasksCompleted >= Config.Tasks.TotalRequired
+
+	if open == state.GateOpen then
+		return
+	end
+
+	state.GateOpen = open
+
+	-- Immediately, rather than waiting up to SnapshotInterval. This is the single most dramatic
+	-- moment in a round (§4.8, "the finale, and the best clip moment in the game") and half a second
+	-- of every HUD lagging the world is half a second nobody gets back. MarkKilled pushes for the
+	-- same reason.
+	broadcastSnapshot()
+
+	if Config.Debug.VerboseLogging then
+		-- Safe to log: it names a round, never a player.
+		print(`[RoundService] Escape gate {if open then "OPEN" else "shut"}.`)
+	end
 end
```

`enterIntermission` gains the reset `enterIdle` already has, so the gate does not depend on
`TaskService` having run:

```diff
 local function enterIntermission()
 	RoleService.ClearRoles()
+	-- Belt and braces. `clearTasks` closes the gate via SetTasksCompleted(0) on this same transition,
+	-- but that is TaskService's PhaseChanged subscription doing it — and this service should not need
+	-- another service to have run in order to be in a correct state.
+	state.GateOpen = false
 	setAllPlayerStates(Enums.PlayerState.Lobby)
```

And the stale TODO goes, since this is the chunk it named:

```diff
 -- TODO(C03): assign roles via RoleService in STARTING
--- TODO(C11): win conditions in ACTIVE
+-- C11 lands the SURVIVOR win, and it lands in GateService rather than here: this service owns the
+-- phase and the result, and GateService asks it to end the round exactly as MonsterService asks it
+-- to mark a kill. §4.8's other three outcomes are already here (attrition in MarkKilled, TIMEOUT in
+-- step, ABORTED on the Aswang leaving).
 -- TODO(C15): convert dead players to ghosts via GhostService
```

#### Step 6.4: `GateService`

**Files:** `src/server/Services/GateService.luau`, `src/server/init.server.luau`
**Verify:** `npm run verify:fast`

A new service on the `RoundService` shape: `Init`/`Start`, subscribes to `PhaseChanged`, requires
`RoundService` **one-directionally**, discovers `EscapeGate` by tag, and polls at the same 4 Hz the
task tick uses. It calls `EndRound`; it never calls `setPhase`, and it learns nothing about a player it
did not ask `RoundService` for.

**Why a new service rather than a branch in `TaskService` or `RoundService`.** `TaskService` owns task
anchors and a gate is not a task. `RoundService` is 972 lines, owns the phase, and adding
CollectionService discovery plus a second polling loop to it would put map-shaped code in the one file
that must stay about the state machine. The service shape exists for this; `RoundService.luau` is the
reference and this follows it.

```diff
+--!strict
+--[[
+	GateService — the escape gate, and the survivors' win. (§4.8, C11)
+
+	🔒 THE ONE SERVICE IN THIS MILESTONE THAT READS THE SECRET, and it reads it to REFUSE a win rather
+	than to grant one. §4.8: "Survivors win: 5/5 tasks done AND at least 1 survivor reaches the escape
+	gate." The Aswang reaching an open gate must do nothing at all, and "nothing at all" is literal —
+	no refusal, no verdict, no remote, no sound, no prompt. Read `server/pure/GateEscape.luau`'s header
+	for what that does and does not conceal.
+
+	IT DOES NOT OWN GateOpen. RoundService derives it from the task count (§6.4: RoundService owns the
+	phase and everything that hangs off it), and this service reads `IsGateOpen()`. There is exactly
+	one writer, and it is not here.
+
+	ONE DIRECTION ONLY, and this is the direction. RoundService must NEVER require GateService back: a
+	require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
+	in IDLE forever looking exactly like "nobody has joined yet". TaskService and MonsterService both
+	sit on this side of the same rule.
+
+	NO REMOTE. The gate is reached by walking, and the server measures the walk. There is no
+	`RequestEscape` and there must not be: a client-callable escape is a free win behind whatever
+	validation somebody remembers to write, and proximity needs none.
+]]
+
+local CollectionService = game:GetService("CollectionService")
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local RoundService = require(script.Parent.RoundService)
+local GateEscape = require(script.Parent.Parent.pure.GateEscape)
+local Types = require(Shared.Types)
+
+local GateService = {}
+
+local TAG_GATE = "EscapeGate"
+
+-- SERVER-ONLY. Rebuilt at every STARTING rather than cached forever, for the reason TaskService's
+-- `discoverPool` gives: C17 will add, move and delete these parts while a server is running.
+local gates: { BasePart } = {}
+
+-- What the gate looked like before it opened, so closing it puts back what was there rather than a
+-- guessed default. MonsterService shipped a Critical bug doing exactly the opposite — its revert
+-- restored hardcoded values instead of captured state, permanently branding the ex-Aswang.
+local closedLook: { [BasePart]: { Transparency: number, CanCollide: boolean } } = {}
+
+local function discoverGates()
+	table.clear(gates)
+
+	for _, instance in CollectionService:GetTagged(TAG_GATE) do
+		if not instance:IsA("BasePart") then
+			warn(
+				`[GateService] {instance:GetFullName()} is tagged {TAG_GATE} but is a `
+					.. `{instance.ClassName}, not a BasePart — skipped.`
+			)
+			continue
+		end
+
+		table.insert(gates, instance)
+
+		if closedLook[instance] == nil then
+			closedLook[instance] =
+				{ Transparency = instance.Transparency, CanCollide = instance.CanCollide }
+		end
+	end
+
+	--[[
+		UNGATED BY VerboseLogging, like every other fault in this codebase. A round can reach 5/5 and
+		then be unwinnable because nothing in the map is tagged, and the only symptom a player reports
+		is "we finished everything and nothing happened".
+	]]
+	if #gates == 0 then
+		warn(
+			`[GateService] NO "{TAG_GATE}" PART IN THE MAP. Tag one anchored part with "{TAG_GATE}" `
+				.. `via CollectionService, or survivors can never win (spec §4.8).`
+		)
+	end
+end
+
+--[[
+	The gate's LOOK, and it is the minimum. C11's brief asks that the opening be "an event worth
+	seeing and hearing, not a boolean" — the SEEING starts here and the HEARING is not code this repo
+	can write: sound and VFX live in the place file and in AudioController's C18 work. A plan step
+	that said "make the gate dramatic" would not be verifiable and does not belong in a plan.
+
+	Restores captured state rather than defaults. See `closedLook`.
+]]
+local function setGateLook(open: boolean)
+	for _, gate in gates do
+		local look = closedLook[gate]
+
+		if open then
+			gate.Transparency = 0.6 -- config-ok: placeholder gate visual, replaced at C17/C18
+			gate.CanCollide = false
+		elseif look ~= nil then
+			gate.Transparency = look.Transparency
+			gate.CanCollide = look.CanCollide
+		end
+	end
+end
+
+local function positionOf(player: Player): Vector3?
+	local character = player.Character
+
+	if character == nil then
+		return nil
+	end
+
+	local root = character:FindFirstChild("HumanoidRootPart")
+
+	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
+end
+
+--[[
+	🔒 THE WIN CHECK. Everything it reads, it reads from RoundService or from the workspace.
+
+	The role is derived here and used immediately; it is never stored, never attributed, never tagged
+	and never sent. Compare TaskService's `weightFor`, which deliberately does NOT fetch the secret
+	because the pure module is proven to ignore it — here the pure module genuinely needs it, which is
+	the whole reason `GateEscape` exists as a separate file with its own exhaustive grid.
+
+	EndRound is guarded on ACTIVE inside RoundService and `enterEnding` refuses a second reveal, so
+	several survivors arriving in the same tick end the round once.
+]]
+local function step()
+	if not RoundService.IsActive() or #gates == 0 then
+		return
+	end
+
+	local gateOpen = RoundService.IsGateOpen()
+	local aswangUserId = RoundService.GetAswangUserId()
+
+	for _, player in Players:GetPlayers() do
+		local position = positionOf(player)
+
+		if position == nil then
+			continue
+		end
+
+		local role: Types.Role = if player.UserId == aswangUserId
+			then Enums.Role.Aswang
+			else Enums.Role.Survivor
+
+		for _, gate in gates do
+			if
+				GateEscape.escapes({
+					GateOpen = gateOpen,
+					PlayerState = RoundService.GetPlayerState(player),
+					Role = role,
+					Distance = (position - gate.Position).Magnitude,
+					Range = Config.Tasks.GateRangeStuds,
+				})
+			then
+				if Config.Debug.VerboseLogging then
+					-- A UserId, never a role, and never "who did not escape". This line is read while
+					-- a round is still running.
+					print(`[GateService] {player.UserId} reached the gate.`)
+				end
+
+				RoundService.EndRound(Enums.RoundResult.SurvivorsEscaped)
+
+				return
+			end
+		end
+	end
+end
+
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase == Enums.RoundPhase.Starting then
+		discoverGates()
+		setGateLook(false)
+	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
+		setGateLook(false)
+	end
+end
+
+function GateService.Init() end
+
+function GateService.Start()
+	-- At boot, not only at STARTING, so an operator learns the map has no gate while they are still
+	-- looking at the output window. TaskService's `Start` makes the same argument for the same reason.
+	discoverGates()
+
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	--[[
+		§5's mobile budget, counted: one server-side loop at 4 Hz doing at most `#players × #gates`
+		distance comparisons — eight subtractions a tick with one gate. No lights, no particles, no
+		client-side per-frame work. It is also the whole reason the gate's look is polled rather than
+		event-driven: one boolean read per tick is cheaper than a second BindableEvent.
+	]]
+	task.spawn(function()
+		local wasOpen = false
+
+		while true do
+			local open = RoundService.IsGateOpen()
+
+			if open ~= wasOpen then
+				wasOpen = open
+				setGateLook(open)
+			end
+
+			step()
+			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
+		end
+	end)
+end
+
+return GateService
```

And the bootstrap, which is ordered and where a new service must be listed by hand:

```diff
 	-- Gameplay
 	"RoleService",
 	"TaskService",
+	"GateService",
 	"MonsterService",
```

#### Step 6.5: The disposable `EscapeGate` anchor

**File:** `.claude/plans/feature-c09-c12-tasks-gate-plan/artifacts/gate-rig.md`
**Verify:** `test -f .claude/plans/feature-c09-c12-tasks-gate-plan/artifacts/gate-rig.md`

One tagged anchor added to `workspace.TaskRig_TEMP`, placed outside the 4×3 pad grid so reaching it is
a walk. C17 replaces it with the real gate; this exists so C11 is verifiable at all.

- One anchored `Part` in `workspace.TaskRig_TEMP`, named `EscapeGate_TEMP`, tagged `EscapeGate`,
  placed well clear of the pad grid (`X = {-45..45}` by `Z = {-30..30}`) — far enough that a survivor
  finishing the last task has to *run* for it, which is the §4.8 moment being tested.
- Record the round that proves the chain end-to-end: `tasks 5/5` → `[RoundService] Escape gate OPEN`
  → `gate OPEN` in the client snapshot line → `[GateService] <userId> reached the gate.` →
  `[RoundService] -> ENDING` → `RoundEnded` carrying `SURVIVORS_ESCAPED`. C11's stated Verify is
  exactly this console transcript.
- **Both §4.8 outcomes, not just the new one.** The attrition win (C06) and the sunrise `TIMEOUT`
  must still land on the reveal after this change. `enterEnding`'s guard against a second reveal is
  the line at risk, and the coordinator's own comment at `RoundService.luau:634` predicted this exact
  collision: *"C11 raising SURVIVORS_ESCAPED one tick after the sunrise timeout already ended the
  round."* If that warn fires during the playtest, it is the guard working — record it either way.
- Measure through datamodel state and `get_console_output` only. See Step 4.5.

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

- **🔒 The one-bit leak in §1.4 is real and is not fixed by this phase.** A bystander watching a
  player stand in an open gate while the round does not end has identified the Aswang. It is
  §4.8's rule, not this implementation, and the accounting is in §1.4. It goes to `exploit-auditor`
  by name rather than being treated as closed.
- **🔒 `GateService` reads `GetAswangUserId()` on a 4 Hz loop.** That is a live reference to the
  secret in a polling loop, which is the shape `TaskService.weightFor` deliberately avoided. It is
  justified here — the rule genuinely needs the role — but it means this file is on the
  `exploit-auditor` surface permanently, and any future `FireClient` added to it starts from a
  variable that holds the secret two lines up.
- **`check:secrecy` passes vacuously on Step 6.3 and 6.4.** Neither `GateOpen` nor the role
  comparison matches `SECRET` or `ROLE_TOKEN` in a scanned position, so the check would pass on a
  `GateService` that did not exist. The Lune grid (Step 6.2) is the check that fails on absent work;
  `verify:fast` at 6.4 catches a service that does not compile. **The behavioural proof is the
  playtester's** and C11's Done condition says so: *"both win conditions in §4.8 fire correctly and
  land on the reveal."*
- **A survivor could stand in the gate area before 5/5 and win the instant the last task completes.**
  That is correct — §4.8 says "5/5 AND at least 1 survivor reaches the gate", not "reaches it after".
  It is worth an M12 balance note: camping the gate is a viable and slightly anticlimactic strategy,
  and the counter is that the Aswang can camp it too, which is what `GateRangeStuds <= KillRange`
  protects.
- **Player leaving mid-round (§6.4).** A departed player is not in `Players:GetPlayers()`, so they
  cannot escape. The Aswang disconnecting already routes to `ABORTED` in `onPlayerRemoving`. If every
  survivor leaves, the gate simply never triggers and the round runs to `TIMEOUT` — §6.4's "finish the
  round, then return to IDLE".
- **`Types` is required by `GateService` for two annotations only** (`Types.Role`, `Types.RoundPhase`).
  Worth keeping rather than dropping: the `Types.Role` annotation on the derived role is what stops it
  inferring as plain `string` and failing to satisfy `GateEscape.Request` — the exact `Enums.luau`
  failure shape that produced six of the scaffold's seven original analyze errors.

### Phase 7: 🔒 The Aswang's fake task list

#### Step 7.1: `src/server/pure/TaskListView.luau`

**File:** `src/server/pure/TaskListView.luau`
**Verify:** `npm run analyze`

`forPlayer(realIds, decoyIds, role) -> { string }`. The property worth proving is that **both branches
return a list of the same length**, and a property is only assertable where it can be called — which is
the whole reason this is a module and not an `if` inside `TaskService`.

New file, entire contents:

```diff
+--!strict
+--[[
+	TaskListView — which five task points is this player TOLD about? (§4.4 + Amendment A2, C12)
+
+		forPlayer(realIds, decoyIds, role) -> { string }
+
+	C12 IS AN INFORMATION-CHANNEL LIE AND NOTHING ELSE.
+
+	§4.4's original wording had the Aswang's task progress not count. Amendment A2 reversed that
+	mechanism while keeping its goal, because the original BUILDS the oracle it was meant to prevent:
+	task progress belongs to the world, a task's fill is legible to anyone standing at the point, and
+	standing at a point costs one keypress. A frozen bar names the monster in two seconds, repeatably.
+
+	So: the Aswang's hands do exactly what everyone else's do, counted in full
+	(`server/pure/TaskWeight.luau`). What it is TOLD is false, and this file is the whole of the lie.
+
+	IT IS NOT A SECRET AND IT MUST NEVER BE TREATED AS ONE. `ActiveTaskPoint` tags replicate, so a
+	compromised client reads the true five straight off CollectionService and defeats this in one
+	line. An exploit audit recorded that limit and it is not fixable at this layer. What this buys is
+	an HONEST Aswang paying real walking time and real position for a list it cannot trust — A2's
+	"it can be sent to points nobody needs" — and no balance decision may depend on more than that.
+
+	THE LENGTH IS THE PART THAT NEEDS CODE.
+
+	A three-line `if` would be enough if the decoy draw always returned as many points as the real
+	one. It does not have to: `TaskSelection.select` returns fewer points when the POOL is genuinely
+	smaller, and a shown list of four against a real five is a role oracle measurable with `#` — no
+	inference, no timing, just a number the client already has. So the decoy is truncated or padded to
+	the real list's length here, once, where a test can enumerate it.
+
+	PADDING USES REAL IDS, and that is the least-bad option rather than a good one. It means a
+	degenerate map (a pool too small to draw a distinct decoy) shows the Aswang some genuine points.
+	The alternatives are worse: padding with repeats puts a duplicate in the list, which is itself a
+	tell, and padding with invented names sends the Aswang to a point that does not exist. A pool that
+	small is already warned about loudly by TaskService and is already an unwinnable round.
+
+	`table.clone` on the way out, both branches, so a caller cannot mutate this round's real task list
+	by editing what it was handed.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes — strings, so Lune runs it. The union is
+	re-declared locally; Luau unions are structural.
+]]
+
+export type Role = "SURVIVOR" | "ASWANG"
+
+local TaskListView = {}
+
+function TaskListView.forPlayer(
+	realIds: { string },
+	decoyIds: { string },
+	role: Role
+): { string }
+	if role ~= "ASWANG" then
+		return table.clone(realIds)
+	end
+
+	local shown = table.clone(decoyIds)
+
+	-- Truncate. A longer decoy is the ordinary case only if somebody tunes the draw counts apart.
+	while #shown > #realIds do
+		table.remove(shown)
+	end
+
+	-- Pad. See the header: real ids, deliberately, in a case that only a broken map reaches.
+	local index = 1
+
+	while #shown < #realIds do
+		table.insert(shown, realIds[index])
+		index += 1
+	end
+
+	return shown
+end
+
+return TaskListView
```

#### Step 7.2: `tests/task-list-view.test.luau`

**File:** `tests/task-list-view.test.luau`
**Verify:** `lune run tests/task-list-view.test.luau`

The survivor gets the real list; the Aswang gets the decoy; **both lists have identical length in every
enumerated case**, including the degenerate ones where the decoy draw came back short. A length
difference is a role oracle measurable with `#`.

```diff
+--!strict
+--[[
+	tests/task-list-view.test.luau
+
+	`server/pure/TaskListView.luau` over every decoy length from 0 to 7 against a real list of 5, both
+	roles: 16 cells, enumerated.
+
+	🔒 THE ASSERTION THAT MATTERS IS THE LENGTH ONE. Everything else here checks that the right list
+	comes back; that one checks that the WRONG list is indistinguishable in the one property a client
+	can measure without knowing anything. `#myTaskList` is one token of Luau on a compromised client,
+	and if it ever differs by role, C12 has built a cheaper oracle than the one A2 removed.
+]]
+
+local TaskListView = require("../src/server/pure/TaskListView")
+
+local REAL = { "TaskPoint_01", "TaskPoint_02", "TaskPoint_03", "TaskPoint_04", "TaskPoint_05" }
+
+local failures = 0
+local assertions = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	assertions += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local function decoyOfLength(count: number): { string }
+	local ids = {}
+
+	for index = 1, count do
+		table.insert(ids, `TaskPoint_{index + 5}`)
+	end
+
+	return ids
+end
+
+-- 🔒 The length property, over every decoy size a draw could produce — including zero, which is what
+-- an empty pool returns.
+for count = 0, 7 do
+	local decoy = decoyOfLength(count)
+
+	for _, role in { "SURVIVOR", "ASWANG" } do
+		local shown = TaskListView.forPlayer(REAL, decoy, role)
+
+		check(
+			`{role} is shown exactly {#REAL} points (decoy had {count})`,
+			#shown == #REAL,
+			`got {#shown}`
+		)
+	end
+end
+
+-- The survivor's list is the real one, element for element.
+for count = 0, 7 do
+	local shown = TaskListView.forPlayer(REAL, decoyOfLength(count), "SURVIVOR")
+	local same = true
+
+	for index, id in REAL do
+		same = same and shown[index] == id
+	end
+
+	check(`a survivor sees the real five (decoy had {count})`, same)
+end
+
+--[[
+	A full decoy reaches the Aswang unaltered — no truncation, no padding, no reordering.
+
+	This is the normal case and it is the one that would silently stop working if the pad/truncate
+	loops were written with the wrong comparison. The length assertion above would still pass.
+]]
+local FULL_DECOY = decoyOfLength(5)
+local shownToAswang = TaskListView.forPlayer(REAL, FULL_DECOY, "ASWANG")
+local matchesDecoy = true
+
+for index, id in FULL_DECOY do
+	matchesDecoy = matchesDecoy and shownToAswang[index] == id
+end
+
+check("the Aswang sees the decoy five, unaltered", matchesDecoy)
+
+-- The caller cannot be made to corrupt this round's real task list by editing what it was handed.
+local handed = TaskListView.forPlayer(REAL, FULL_DECOY, "SURVIVOR")
+handed[1] = "MUTATED"
+
+check("the returned list is a copy", REAL[1] == "TaskPoint_01")
+
+if failures > 0 then
+	error(`{failures} task-list-view failure(s)`, 0)
+end
+
+print(`  PASS  task-list-view: {assertions} assertions over 8 decoy lengths`)
```

#### Step 7.3: Draw the decoy set and publish one list per player

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:secrecy`

A second `TaskSelection.select` off the same pool and the same `Random`, run at `STARTING` after the
real draw. `TaskService` reads `RoundService.GetAswangUserId()` **once per round, in one function**,
and never stores it. The send is one loop over every player, one typed local per player.

**This changes `TaskService`'s posture and the change should be deliberate.** `weightFor`'s comment
argues at length for *not* fetching the secret — "a live reference to the secret with no purpose",
four times a second, to feed a parameter the pure module is proven to ignore. That argument does not
apply here: C12's decision genuinely needs the role, once, at `STARTING`. The read is therefore scoped
to one function, one moment, one local that goes out of scope immediately, and the hot path is
untouched.

**The ordering works and it is not luck.** `RoundService.enterStarting` assigns `state.AswangUserId`
at `RoundService.luau:587`, *before* `setPhase` fires `PhaseChanged` at `:611` — with a comment saying
it is deliberate so "no subscriber can observe a STARTING round that has no Aswang yet". This is that
subscriber.

```diff
+local listRemote = Remotes.Get("TaskListAssigned")
+
+--[[
+	🔒 C12. WHAT EACH PLAYER IS TOLD (§4.4 + Amendment A2).
+
+	One loop, every player, one payload shape, one moment. Survivors receive this round's real five;
+	the Aswang receives a decoy five. NOTHING about the send distinguishes them — not the timing, not
+	the field, not the count (`server/pure/TaskListView.luau` guarantees the length) — which is the
+	property that still holds when a client is compromised and logging its own traffic.
+
+	THE DECOY IS DRAWN, NOT CONSTRUCTED. It comes off the same pool through the same
+	`TaskSelection.select` and the same `nextFloat`, so it looks exactly like a real draw: spaced the
+	same way, five points, from the twelve. It is NOT made disjoint from the real five, and that is
+	deliberate — a decoy guaranteed never to overlap is a decoy an Aswang can partially invert by
+	elimination.
+
+	THE SECRET IS READ HERE, ONCE. See this function's step in the plan for why that is a deliberate
+	departure from `weightFor` next door rather than an inconsistency with it. `aswangUserId` is a
+	local in this function and is never stored, attributed, tagged, or sent.
+
+	THE PAYLOAD MUST BE A TYPED LOCAL AND NOT AN INLINE TABLE, for two independent reasons. FireClient
+	takes `...any`, so an inline literal is checked against nothing at all — Types.luau says so in
+	three places. And `check-secrecy.mjs` tests the raw ARGUMENT TEXT of every FireClient against
+	`ROLE_TOKEN = /\b(role|roles)\b/i`: inlining `TaskListView.forPlayer(realIds, decoyIds, role)` into
+	the call puts the word `role` in that text and turns this line red. The typed local resolves to its
+	field names — `TaskIds` — and passes. Both facts point the same way.
+
+	Players who join AFTER this runs get no list. They are SPECTATORs (§6.4) and are not in the round;
+	the next STARTING deals them in and sends them one.
+]]
+local function publishTaskLists()
+	local realIds: { string } = {}
+
+	for _, task in activeTasks do
+		table.insert(realIds, task.Id)
+	end
+
+	-- Rebuilt from `pointsByName`, which `selectForRound` has just populated — NOT by calling
+	-- `discoverPool` again, which would re-emit every pool warning a second time per round.
+	local pool: { TaskSelection.Point } = {}
+
+	for name, part in pointsByName do
+		table.insert(pool, { Id = name, Position = toVec(part.Position) })
+	end
+
+	-- The second return value is the spacing flag. Discarded on purpose: `selectForRound` has already
+	-- warned about an unspaced draw this round, and a decoy that is not spread is a decoy.
+	local decoy = TaskSelection.select(
+		pool,
+		Config.Tasks.TotalRequired,
+		Config.Tasks.MinSpacingStuds,
+		nextFloat
+	)
+
+	local decoyIds: { string } = {}
+
+	for _, point in decoy do
+		table.insert(decoyIds, point.Id)
+	end
+
+	local aswangUserId = RoundService.GetAswangUserId()
+
+	for _, player in Players:GetPlayers() do
+		local shownRole: Types.Role = if player.UserId == aswangUserId
+			then Enums.Role.Aswang
+			else Enums.Role.Survivor
+
+		local payload: Types.TaskListPayload = {
+			TaskIds = TaskListView.forPlayer(realIds, decoyIds, shownRole),
+		}
+
+		listRemote:FireClient(player, payload)
+	end
+end
```

Called from the phase handler, after the draw:

```diff
 local function onPhaseChanged(phase: Types.RoundPhase)
 	if phase == Enums.RoundPhase.Starting then
 		clearTasks()
 		selectForRound()
+		setUpFetchTasks()
+		publishTaskLists()
 	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
 		clearTasks()
 	end
 end
```

**`shownRole`, not `role`.** The local's name is load-bearing in the same way the typed local is:
`check-secrecy.mjs` scans FireClient argument text for `\brole\b`, and while this local does not appear
in that text today, a later refactor that inlines one line would fail loudly rather than quietly. The
name also says the true thing — it is the role this player is being shown a list *as*, which for
exactly one player is a lie.

#### Step 7.4: The client caches the list; three stale comments are corrected

**Files:** `src/client/Controllers/TaskController.luau`, `src/client/Controllers/InputController.luau`
**Verify:** `npm run verify`

`TaskController` gains `GetTaskList()`, the seam C18 draws the HUD list from. Then three comments that
still promise a C12 which zeroes the Aswang's weight are corrected — A2 reversed that, and a comment
promising the oracle is how the oracle gets built by the next reader acting in good faith.

```diff
 local latest: Types.TaskProgressPayload? = nil
 local latestBar: Types.TimingBarPayload? = nil
+local taskList: { string } = {}
 local holding = false
```

```diff
+--[[
+	The five task points this client was told about, and the seam C18 draws the HUD list from.
+
+	THIS CLIENT CANNOT TELL WHETHER ITS LIST IS TRUE, and it is not supposed to be able to. For
+	exactly one player per round it is a decoy (§4.4 + Amendment A2, C12); the payload is identical in
+	shape, length and timing either way, so there is nothing here to compare against and no branch to
+	write. Do not add one.
+
+	It is also not a secret: `ActiveTaskPoint` tags replicate, so any client can read the real five off
+	CollectionService. This is a UX affordance for an honest client, not a mechanic — see the plan's
+	§1.3, and do not let a later feature depend on it.
+]]
+function TaskController.GetTaskList(): { string }
+	return table.clone(taskList)
+end
```

```diff
 function TaskController.Init()
 	latest = nil
 	latestBar = nil
+	taskList = {}
 	holding = false
 end
```

```diff
+	Remotes.Get("TaskListAssigned").OnClientEvent:Connect(function(payload: Types.TaskListPayload)
+		taskList = payload.TaskIds
+
+		if Config.Debug.VerboseLogging then
+			print(`[Task] list: {table.concat(payload.TaskIds, ", ")}`)
+		end
+	end)
```

Then the three stale comments. Every one of them predates Amendment A2 and every one of them tells the
next reader to build the oracle:

```diff
--- TODO(C09/C10): Timing, Fetch and TwoPerson. `taskTypeOf` reads the TaskType attribute and warns on
--- anything that is not HOLD, so an anchor asking for one is visible rather than silently mishandled.
--- TODO(C12): the Aswang sees a FAKE TASK LIST. Its progress still counts, in full — Amendment A2 in
--- docs/MVP-SPEC.md, which reverses §4.4's original wording after an exploit audit showed the original
--- mechanism BUILDS the oracle it was meant to prevent. C12 changes what the Aswang is TOLD (which five
--- points its HUD names), never what its holds do. `pure/TaskWeight.luau` and its grid are what keep
--- that honest; do not add a role branch to `weightFor`.
+-- C09-C12 are built. Four task types, and the Aswang is TOLD a task list that is not the real five
+-- (`pure/TaskListView.luau`) while its hands do exactly what everyone else's do — Amendment A2 in
+-- docs/MVP-SPEC.md, which reverses §4.4's original wording after an exploit audit showed the original
+-- mechanism BUILDS the oracle it was meant to prevent. `pure/TaskWeight.luau` and its grid are what
+-- keep that honest; do not add a role branch to `weightFor`, `FetchCarry` or `TaskParticipants`.
```

`InputController.luau:163-165` is the one that matters most, because it states the reversed rule as
fact on the file where a role gate would be easiest to add:

```diff
--	SO: THE ASWANG'S CLIENT SENDS EXACTLY WHAT A SURVIVOR'S SENDS. C12 makes the server value it at
--	zero. Nothing on this side of the boundary knows the difference, which is the only arrangement that
--	is still true when the client is compromised.
+	SO: THE ASWANG'S CLIENT SENDS EXACTLY WHAT A SURVIVOR'S SENDS, and the server values it exactly the
+	same — Amendment A2 in docs/MVP-SPEC.md. An earlier version of this paragraph said "C12 makes the
+	server value it at zero"; C12 does the opposite, because a hold that produced nothing would name
+	the monster to anyone who tapped interact beside it. What C12 changes is which five points this
+	client is TOLD about. Nothing on either side of the boundary knows the difference, which is the
+	only arrangement that is still true when the client is compromised.
```

The third is `Types.luau`'s `TaskProgressVerdict` comment, which plan 1 already partly corrected —
re-read it and delete the remaining "C12 adds a value meaning you are the Aswang" if any survives.

**`npm run verify` is this step's check** rather than `verify:fast`: it is the last step of the last
phase, and it is the only place in the plan where the full gate — analyze, lint, format, all five
checks, every Lune suite including the five this plan adds, and the harness self-tests — runs over the
finished tree.

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

- **🔒 The decoy is defeated by one line on a compromised client.** `ActiveTaskPoint` tags replicate.
  This is recorded rather than fixed, it is in §1.3 and in three separate file headers, and the
  operative instruction is that **no balance decision may depend on the fake list**. If M12 ever
  reasons "the Aswang is slowed down by having to check points", that reasoning is wrong for any
  player who wants it to be.
- **🔒 The decoy is also weak against an HONEST Aswang, and the cost is bounded rather than zero.**
  Prompts appear only within `PresenceRangeStuds` (9 studs), so a decoy is discovered on arrival, not
  from across the map. The Aswang pays the walk, which is A2's stated trade. It does not pay
  confusion for the rest of the round.
- **🔒 `TaskService` now reads the secret.** One function, one moment, one local. It is a real widening
  of that file's surface and it puts `TaskService` firmly on `exploit-auditor`'s list for this diff —
  which `review-gate.mjs` would name anyway for `src/server/**`, but it should be named in the brief
  too, with `publishTaskLists` called out by name.
- **`check:secrecy` will pass on Step 7.3 whether or not the decoy is real.** Handing every player
  `realIds` scans identically to handing the Aswang a decoy: no field name changes, no remote changes,
  no token appears. The Lune test proves the *view function*; only the **playtester, playing as the
  Aswang and comparing its list against the tagged parts**, proves the wiring. C12's Verify is 🔒
  mandatory in BUILD-PLAN.md and this is why.
- **BUILD-PLAN.md's C12 Verify line is now wrong and cannot be followed.** It reads *"playtester as the
  Aswang completes a hold; the global count is unchanged"* — under A2 the count **must** change. The
  correct verification is: the Aswang's hold advances the global bar exactly like a survivor's, **and**
  the list it was shown differs from the `ActiveTaskPoint` tags. Raised in §4; `docs/BUILD-PLAN.md`
  should be amended, and that is a documentation change outside this plan's scope.
- **A round with no Aswang sends five real lists and that is correct.** Solo Studio rounds without
  `ForceAswangWhenSolo` have `AswangUserId == nil`, so `shownRole` is `SURVIVOR` for everyone. No
  branch, no special case, and the decoy draw still runs — so its cost is paid every round and cannot
  become a timing tell.
- **Player leaving mid-round (§6.4).** Nothing to clean up: the list is client-side cache with no
  server-side per-player state behind it. A player joining mid-round gets no list until the next
  `STARTING`, which is correct — they are a SPECTATOR.

## 3. Related Files

Every file read while planning has an annotated review in `references/`. The reviews carry only the
lines an annotation is attached to, with a line-range citation, so the live file can be diffed against
what was seen.

**Created (10):**

| File | Phase |
| --- | --- |
| `src/server/pure/TimingWindow.luau` | 2 |
| `tests/timing-window.test.luau` | 2 |
| `src/server/pure/FetchCarry.luau` | 4 |
| `tests/fetch-carry.test.luau` | 4 |
| `src/server/pure/TaskParticipants.luau` | 5 |
| `tests/task-participants.test.luau` | 5 |
| `src/server/pure/GateEscape.luau` | 6 |
| `tests/gate-escape.test.luau` | 6 |
| `src/server/Services/GateService.luau` | 6 |
| `src/server/pure/TaskListView.luau` | 7 |
| `tests/task-list-view.test.luau` | 7 |

**Modified (9):** `src/shared/Types.luau` · `src/shared/Config.luau` · `src/shared/Remotes.luau` ·
`tests/config.test.luau` · `tests/anti-cheat-budgets.test.luau` · `src/server/Services/TaskService.luau`
· `src/server/Services/RoundService.luau` · `src/server/init.server.luau` ·
`src/client/Controllers/TaskController.luau` · `src/client/Controllers/InputController.luau`

**Read and relied on, not modified:** `CLAUDE.md` · `docs/MVP-SPEC.md` §3, §4.2–4.8, §6.4 and
Amendment A2 · `docs/BUILD-PLAN.md` §3 · `src/shared/Enums.luau` · `src/shared/pure/TaskSelection.luau`
· `src/shared/pure/WinConditions.luau` · `src/server/pure/TaskWeight.luau` ·
`src/server/pure/TaskProgress.luau` · `src/server/pure/TaskResolve.luau` ·
`src/server/Services/AntiCheatService.luau` · `src/client/Controllers/UIController.luau` ·
`.claude/scripts/check-secrecy.mjs` · `.claude/scripts/check-config.mjs` ·
`.claude/scripts/check-remotes.mjs` · `.claude/scripts/verify-plan.mjs` ·
`.claude/plans/feature-c07-map-c08-hold-plan/` in full.

## 4. Follow Ups

### Questions / Clarifications

1. **`R` for the timing stop is unconfirmed.** C08 shipped unreachable-by-humans because
   `ProximityPrompt`'s default `KeyboardKeyCode = E` silently swallowed the `ContextActionService`
   bind on the same key, and nothing in this tree proves `R` is free of a CoreScript or engine claim.
   `attachPrompt` now sets `Enum.KeyCode.None`, which removes the known collision — but the known one
   is all that can be established statically. **This is a playtester question and it is the highest-
   value single observation in the plan**, because the failure is silent: no error, no log, no client
   feedback, exactly as in `artifacts/keyboard-swallow-bug-and-fix.md`.
2. **`docs/BUILD-PLAN.md`'s C12 entry contradicts the spec and should be amended.** It says the
   Aswang's progress "does not count" and that "the global bar does not move"; Amendment A2 reverses
   both. Its **Verify** line — *"playtester as the Aswang completes a hold; the global count is
   unchanged"* — now describes a failing state. Per CLAUDE.md's precedence rule the spec wins and this
   plan follows the spec, but the stale entry is a live trap for the next reader and for any auditor
   grading against it. **A one-paragraph amendment to BUILD-PLAN.md is recommended and is outside this
   plan's scope.**
3. **Is a survivor camping the open gate acceptable?** Nothing stops a player standing at the gate from
   `ACTIVE`'s first second and winning the instant the fifth task lands. §4.8's wording permits it.
   It is an M12 balance conversation, and the counter already exists — `GateRangeStuds <= KillRange`
   means the camper is inside the Aswang's reach the whole time.
4. **`TimingHitsRequired` is a reading of §4.4, not a quotation of it.** The spec says "3 attempts"
   against a "~10s" duration. This plan reads that as three required hits with a miss resetting the
   count. The alternative reading — one hit, three misses allowed — produces a two-second task and
   leaves the third miss undefined. Worth a sentence in the spec either way.
5. **Directional latency grace.** The grace in `TimingWindow` is symmetric, which additionally accepts
   a press that was genuinely *early*. The correct version widens the window only against the sweep
   direction. It needs direction as an input and doubles the test grid; the symmetric version's cost is
   quantified in Phase 2's issues (a ~31% window instead of ~20% at committed values).
6. **A `WeldConstraint` carry rig for the fetch item.** The 4 Hz re-anchor visibly steps. A weld needs
   the part unanchored and hands physics ownership to the carrying client, which is a replication
   story this plan has not verified — on the one object in a round somebody might want to desync. C18
   is where the item stops being a grey cube anyway.
7. **The pool's task-type MIX is a map constraint with no code guard.** All four types are drawn from
   one 12-point pool at random (§4.4), so a round can legitimately draw five `TWO_PERSON` points and be
   unfinishable at `MinPlayers = 3`. C17 owns the mix. A draw that balanced types would contradict §4.4's
   whole design, so this is deliberately not defended against in code — but somebody has to know.
8. **`tests/anti-cheat-budgets.test.luau` still hand-copies the remote list.** Its own header names the
   clean fix — a check script parsing both files — and defers it. This plan adds a ninth entry to that
   copy, which makes the drift surface slightly larger. Still not the chunk that should grow the
   harness.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 3 | `R` may be swallowed exactly as `E` was in C08 — silent, no error, no log | High | Open — playtester |
| 6 | 🔒 §4.8 leaks one bit: a player standing in an open gate while the round does not end is the Aswang | Medium | Accepted — spec-mandated, accounted for in §1.4 |
| 6 | 🔒 `GateService` holds the secret in a 4 Hz loop; any future `FireClient` there starts two lines from it | Medium | Open — permanent `exploit-auditor` surface |
| 7 | 🔒 The decoy list is defeated by one line on a compromised client (`ActiveTaskPoint` replicates) | Medium | Accepted — never a balance dependency |
| 7 | 🔒 `TaskService` now reads `GetAswangUserId()`, reversing `weightFor`'s stated posture | Medium | Open — scoped to one function; name it in the audit brief |
| 4 | 🔒 The fetch item is a replicated marker following one player; role-blindness is the only thing keeping it safe | Medium | Open — held by `FetchCarry`'s 512-cell grid |
| 4 | Carried item stays visible over a survivor for the whole `ENDING` screen | Low | Open — cosmetic, playtest note |
| 5 | C10's Done condition is multi-client and no agent can drive a second Studio client | High | Open — human playtest required |
| 3, 6, 7 | `check:ratelimit`, `check:remotes` and `check:secrecy` all pass vacuously on absent work | Medium | Mitigated — every phase also carries a Lune test that fails when its file is missing |
| 1 | An `IsDecoy`-shaped field on `TaskListAssigned` would leak the role and pass every check in the repo | Medium | Open — documented in `Types.TaskListPayload`; no mechanical guard exists |
| 3, 5 | A round can draw five `TWO_PERSON` or five `TIMING` points and be unfinishable at low player counts | Medium | Open — C17 owns the map's type mix |
| 2 | Symmetric grace widens the timing window from ~20% to ~31% of a sweep | Low | Accepted — quantified, bounded by a Config invariant |
| — | `docs/BUILD-PLAN.md`'s C12 entry and Verify line contradict spec Amendment A2 | Medium | Open — doc amendment recommended, outside scope |
