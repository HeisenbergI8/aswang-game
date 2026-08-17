# Plan: Solo Trial, Contextual Teaching, and a Lobby That Is Not Dead (C21–C24)

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M6 (`TrialService`'s own TODOs name it), delivering BUILD-PLAN chunks C21, C22, C23, C24
- **Description:** A 90-second single-player Solo Trial that runs in a corner of the map when there are
  too few players for a round (§9.1), a scripted Aswang chase inside it that teaches the tell and salt
  (C22), the same teach-by-doing pattern generalised to four first-time moments across the real game
  (C23), and a lobby with a countdown, tips and the Trial's entrance so waiting never reads as broken
  (C24, §9 item 3).
- **Date:** 2026-08-16
- **What the client is told:** Nothing new about any round. The Trial adds a `TrialSnapshot` down-remote
  carrying only the receiving player's own trial timer, beat and task count, and a `TeachingCue`
  down-remote carrying a copy-line id fired to exactly one player. `ClientRoundSnapshot` is **not
  widened**, `Types.RoundPhase` gains **no** new member, and `Types.PlayerState` gains **no** new
  member — see §2 Phase 1 and the decision record below for why all three stayed shut.

### 1.1 The decision this plan exists to make

C21's row names the risk in one sentence: *"`TrialService` and `RoundService` sharing state is how you
get a trial that ends a live round."* CLAUDE.md's "rules that matter" is the other half: `RoundService`
owns the phase and nothing else calls `setPhase`. Three shapes were considered.

**Approach A — a `"TRIAL"` member on `Types.RoundPhase`.** Rejected. `RoundPhase` is a server-global
value: one player entering a trial would change the phase *for all eight*. It also lands in
`shared/pure/RoundTransitions.luau`, whose transition table is exhaustively tested precisely because
this is where the genre's bugs live, and in `ClientRoundSnapshot.Phase`, which every subscriber
branches on — `TaskService`, `ItemService`, `GateService`, `GhostService`, `MonsterService`,
`UIController`, `OnboardingController`. Every one of those becomes a new place a trial can corrupt a
round. This is the failure C21's row describes, expressed as a type.

**Approach B — a `"TRIAL"` member on `Types.PlayerState`, held in `RoundService.state.PlayerStates`.**
Tempting: `applyBodyRule` and `buildSnapshot` already read that table, so the trial would inherit body
management for free. Rejected for three specific reasons found in the code. (1)
`setAllPlayerStates` (`RoundService.luau:501-554`) rewrites the whole table at every transition, so a
round starting would silently erase trial state rather than negotiate with it. (2) `RejoinResolve`
(`RoundService.luau:1042-1051`) would gain an untested cell on the exact surface where an untested cell
was already once a live invulnerability exploit. (3) `applyBodyRule` has six call sites, all in
`RoundService`, and its header comment records that the count being wrong has already caused two real
bugs — adding a seventh branch to a function whose own documentation warns about this is not a cheap
change. Above all it puts trial state *inside* the file the rule says nothing else may touch.

**Approach C — CHOSEN. `TrialService` owns a private per-player session table and subscribes to
`RoundService.PhaseChanged` one-directionally. The round always wins.** The properties that make it
answer the risk:

| Property | How it is enforced |
| --- | --- |
| The trial cannot advance or end a round | `TrialService` never calls `setPhase` (it is a file-local in `RoundService.luau:671`, unreachable), never calls `SetTasksCompleted`, `EndRound` or `MarkKilled` |
| The trial cannot observe a round's secret | `TrialService` requires `RoundService` for `GetPhase()` only. It never calls `GetAswangUserId()`, and the trial's Aswang is a scripted rig with no UserId and no role |
| A round cannot start under a player mid-trial | It can, and it does — see below. The session is aborted on the phase change, not held off |
| No require cycle | `TrialService` → `RoundService` only, mirroring the one-direction rule `RoundService.luau:26-28` states for `RoleService` |
| Admission is testable from a terminal | `shared/pure/TrialAdmission.luau` decides *may this player start a trial* over plain tables, gated on a Lune test (Phase 2) |

**Why the round wins the conflict instead of the trial holding it.** A hold means up to 90 seconds of
two other players watching a frozen countdown so that one player's tutorial can finish — which is
precisely the §9 item 3 failure C24 exists to delete ("a static screen reads as *broken*, not as
*waiting*"). And §9.1 states the Trial's purpose is to get people *into* the multiplayer loop, so a
real round starting is the trial's success condition, not its interruption. The cost is a truncated
tutorial, and it is bounded: the abort fires on the transition into `INTERMISSION`, which
`Config.Round.Intermission` gives 25 seconds of runway before `STARTING`, enough to deliver the handoff
line and walk back. The trial is offered again next time the server empties.

## 2. Comprehensive Plan by Phases

### Phase 1: The isolation contract — types, config, and the remote surface

Nothing in this phase runs; it fixes the boundary the other six phases are held to. The point of doing
it first is that the shape of `TrialSnapshot` is what makes it impossible for the trial to be mistaken
for a round on either side of the wire.

#### Step 1.1: Declare the trial's own types, deliberately disjoint from the round's

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

Adds `TrialPhase`, `TrialBeat`, `TrialSnapshot`, `TrialStartVerdict` and `TeachingCueId` as new
exported types. `TrialPhase`'s literals are chosen to share **no** string with `RoundPhase` so that a
value of one can never satisfy the other structurally, and `TrialSnapshot` is deliberately **not**
shaped like `ClientRoundSnapshot`.

Appended immediately before the closing `return {}` at `src/shared/Types.luau:504`, after the Amendment
A3 comment block:

```diff
+--[[
+	THE SOLO TRIAL'S TYPES (C21, §9.1), AND WHY THEY SHARE NOTHING WITH THE ROUND'S.
+
+	Luau unions are STRUCTURAL. A `TrialPhase` whose literals overlapped `RoundPhase`'s would be
+	assignable to a `RoundPhase` parameter with no cast and no analyzer complaint, which is a compile-
+	time hole underneath the one rule this whole feature exists to keep: the trial cannot advance,
+	end or observe a round. Not one string below appears in `RoundPhase` above.
+
+	`TrialSnapshot` is the other half. It carries no field name `ClientRoundSnapshot` carries — no
+	`Phase`, no `SecondsRemaining`, no `RoundNumber`, no `YourState` — so a handler wired to the wrong
+	remote fails to typecheck rather than rendering trial state as round state. `check:remotes` and
+	`check:secrecy` are text tripwires and would both pass a semantic mix-up like that; the type is
+	what actually catches it.
+]]
+export type TrialPhase = "TRIAL_OFF" | "TRIAL_TASKS" | "TRIAL_CHASE" | "TRIAL_HANDOFF"
+
+-- What the timeline fires, in order. FIRE-ONCE per session — see `shared/pure/TrialTimeline`.
+export type TrialBeat =
+	"BEAT_WELCOME"
+	| "BEAT_TASKS"
+	| "BEAT_SALT_GIVEN"
+	| "BEAT_TRANSFORM"
+	| "BEAT_SALT_TAUGHT"
+	| "BEAT_HANDOFF"
+
+-- Why a session ended. Read by nothing but a log line and the handoff copy, but naming the five
+-- exits is what stops a sixth being added silently.
+export type TrialEndReason = "COMPLETED" | "EXPIRED" | "PLAYER_LEFT" | "PLAYER_ASKED" | "ROUND_STARTED"
+
+-- The answer to "may this player start a trial right now", decided by `shared/pure/TrialAdmission`.
+export type TrialStartVerdict =
+	"OK"
+	| "DISABLED"
+	| "ALREADY_IN_TRIAL"
+	| "ROUND_NOT_IDLE"
+	| "TOO_MANY_PLAYERS"
+
+--[[
+	FireClient to the ONE player in the session. Never FireAllClients, and there is no roster field to
+	make that tempting: everything here describes the receiver's own session and is worthless to
+	anybody else. The trial's Aswang is a scripted rig with no UserId and no role, so unlike every
+	other payload in this file there is no secret in the vicinity of this one.
+]]
+export type TrialSnapshot = {
+	TrialPhase: TrialPhase,
+	Beat: TrialBeat?, -- the beat that just fired, if this push carries one
+	TrialSecondsLeft: number,
+	TrialTasksDone: number,
+	TrialTasksRequired: number,
+}
+
+-- C23. The id of a one-liner, resolved to copy by `shared/pure/TeachingLines`. An ID rather than the
+-- string itself so the copy lives in one place and the seen-set is keyed on something stable.
+export type TeachingCueId =
+	"CUE_FIRST_SALT"
+	| "CUE_FIRST_GHOST_DEATH"
+	| "CUE_FIRST_TRANSFORM_SEEN"
+	| "CUE_FIRST_TWO_PERSON"
+
 return {}
```

#### Step 1.2: Extend the existing `Config.Trial` block, and budget the two new up-remotes

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

Adds the trial's remaining tunables to the `Trial` block that already holds `Enabled`, `Duration`,
`TasksToComplete`, `ScriptedChaseAt` and `OfferBelowPlayerCount`, plus `AntiCheat.Budgets` entries for
`RequestStartTrial` and `RequestEndTrial`, plus the C24 lobby timings.

At `src/shared/Config.luau:379-385`, extending the existing block rather than starting a new one:

```diff
 	Trial = {
 		Enabled = true,
 		Duration = 90,
 		TasksToComplete = 2,
 		ScriptedChaseAt = 55, -- seconds in: the Aswang reveals itself
 		OfferBelowPlayerCount = 3, -- == Round.MinPlayers
+
+		-- The remaining beats, all measured in seconds from the session's start so the timeline is
+		-- readable as a single column. `tests/config.test.luau` pins their ordering (Phase 2.3),
+		-- because a chase scheduled after the trial ends teaches nothing and produces no symptom.
+		SaltGivenAt = 40, -- pouch appears BEFORE the transform, so the tell lands with a tool in hand
+		SaltTaughtAt = 58, -- §10's folklore line, 3s after the transform: after the fright, not during
+		HandoffAt = 84, -- the closing line, with time left to read it
+
+		--[[
+			THE SCRIPTED RIG. It is not a Player, has no Role and never goes through MonsterService —
+			see the plan's §1.1. These are its own numbers because reusing `Config.Monster`'s would
+			couple a tutorial to live balance: retuning the real Aswang's speed at M12 would silently
+			retune the tutorial, and the tutorial's job is to be survivable.
+
+			DELIBERATELY SLOWER THAN THE PLAYER. The trial's Aswang must never catch anyone: a death
+			here needs a death path, a respawn and a re-entry, and all three are how a 90-second
+			tutorial becomes a PvE level. It menaces and it is stunned. That is the whole encounter.
+		]]
+		ChaseWalkSpeed = 13,
+		ChaseStopStuds = 6, -- how close it gets before holding station
+		ChaseStunSeconds = 6, -- how long a salt hit holds it, ending the chase beat
+
+		--[[
+			Roblox's stock `Humanoid.WalkSpeed`, mirrored here for ONE reason: it is the number
+			`ChaseWalkSpeed` has to stay under, and an invariant cannot be pinned in
+			tests/config.test.luau against a constant that lives inside the engine. There is no
+			`Config.Player` block in this repo (checked at plan time — nothing anywhere sets a walk
+			speed), so survivors run at the engine default and this records it.
+
+			IF THE GAME EVER SETS A REAL WALK SPEED, this stops being the right comparison and the
+			invariant becomes a lie that still passes. Delete this field and point the test at the
+			real one; do not update the number here to match.
+		]]
+		PlayerBaselineWalkSpeed = 16,
+
+		-- How often the server pushes a TrialSnapshot to the one player in a session. Matches
+		-- Round.SnapshotInterval's job without reading it: these are different features and a shared
+		-- number is a coupling nobody documented.
+		SnapshotInterval = 0.5,
 	},
```

And in `AntiCheat.Budgets` at `src/shared/Config.luau:455`, before the closing brace:

```diff
 			RequestClaimDaily = { Capacity = 2, RefillPerSecond = 0.1 },
+			--[[
+				Both trial remotes are BUTTON PRESSES — one per session, at most, from an honest
+				client. Priced like `RequestGhostSpook` next door rather than like a heartbeat.
+
+				`RequestStartTrial` is the more interesting of the two: it is the only remote in this
+				game whose handler SPAWNS AN NPC AND TELEPORTS A CHARACTER, so an unbudgeted one is a
+				rig-spawn firehose. `AllowUnbudgetedRemote = false` below means a missing entry here
+				refuses rather than allows, but relying on that would leave the refusal undocumented.
+			]]
+			RequestStartTrial = { Capacity = 2, RefillPerSecond = 0.1 },
+			RequestEndTrial = { Capacity = 3, RefillPerSecond = 0.2 },
 		},
```

The C24 lobby numbers go in their own block next to `Trial`, since they are lobby presentation rather
than trial balance:

```diff
 	Community = {
+		-- C24, §9 item 3. A waiting player must never see a static screen.
+		LobbyTipSeconds = 7, -- how long each tip holds before the next
```

#### Step 1.3: Declare four remotes, two up and two down

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

`RequestStartTrial` and `RequestEndTrial` into `EVENTS_UP`; `TrialSnapshot` and `TeachingCue` into
`EVENTS_DOWN`, each with the comment block this file's existing entries set the standard for.

Into `EVENTS_DOWN` at `src/shared/Remotes.luau:85`, after `FirstObjectiveAssigned`:

```diff
 	"FirstObjectiveAssigned",
+	--[[
+		C21. FireClient to the ONE player in a Solo Trial. Never FireAllClients.
+
+		THE INTERESTING PROPERTY IS THAT THERE IS NO SECRET HERE AT ALL, and saying so is the point:
+		the trial's Aswang is a scripted rig, so no role exists to leak inside a trial. The risk runs
+		the other way — a trial remote that could be confused with a round one, or fired at a player
+		who is in a round. `Types.TrialSnapshot` shares no field name with `ClientRoundSnapshot`
+		precisely so that confusion is a type error rather than a subtle bug, and the server refuses
+		to open a session at all unless RoundService is IDLE.
+
+		WHAT A SECOND PLAYER LEARNS: nothing from this remote, which they never receive. They can of
+		course SEE a trial player walk to the trial corner and see the rig, and that is harmless by
+		construction — a trial only runs while no round is running, so there is no round-secret to
+		correlate it against. `.claude/lessons/absence-is-observable.md` applies in its mild direction
+		and resolves the same way OnboardingController's waypoint does.
+	]]
+	"TrialSnapshot",
+	--[[
+		C23. FireClient to ONE player, carrying a `Types.TeachingCueId` and nothing else.
+
+		The generalisation of `FirstObjectiveAssigned` directly above, and it inherits that entry's
+		argument wholesale: what it reveals is that the RECEIVER is new, it names nobody else, and the
+		events it fires on (a salt pickup, a transform, a ghost death) are already public or already
+		the receiver's own. An id rather than a string so the copy has one home.
+	]]
+	"TeachingCue",
 }
```

Into `EVENTS_UP` at `src/shared/Remotes.luau:119`, after `RequestClaimDaily`:

```diff
 	"RequestClaimDaily",
+	--[[
+		C21. NO ARGUMENTS, deliberately, and for the same reason `RequestTimingStop` above has none.
+
+		There is nothing a client could legitimately name here: which trial, where, and whether it is
+		allowed are all server facts. The handler re-runs `shared/pure/TrialAdmission` on every call
+		rather than trusting that C24's button was only shown when a trial was actually available —
+		the button is a hint to an honest player, never a permission.
+	]]
+	"RequestStartTrial",
+	-- C22. Also argument-free: it means "I am done", and the server already knows whose session it is.
+	"RequestEndTrial",
 }
```

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

- **`Types.RoundPhase` and `Types.PlayerState` are untouched, and that is the phase's real deliverable.**
  Both were candidate homes for the trial (plan §1.1, approaches A and B) and both stayed shut. If the
  implementer finds themselves adding a member to either, the design has drifted back into the shape
  C21's row warns about and the phase should stop.
- **Structural-union hazard, closed by construction.** Luau unions are structural, so a `TrialPhase`
  sharing any literal with `RoundPhase` would be silently assignable to it. Verified by reading:
  `"TRIAL_OFF" | "TRIAL_TASKS" | "TRIAL_CHASE" | "TRIAL_HANDOFF"` intersects
  `"IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"` (`Types.luau:11`) in nothing.
- **Strict-Luau cast, expected in Phase 3.** Per CLAUDE.md, a bare literal infers as `string`. Every
  `TrialPhase` and `TrialBeat` assignment in `TrialService`'s state table will need its `:: Types.X`
  cast, the same bite `RoundService.luau:43` carries for `Enums.RoundPhase.Idle`.
- **Config-check waivers.** The RGB-free numbers added here are all balance and belong in `Config`, so
  no `config-ok:` waiver should appear in this phase. One appearing means a number was typed in a
  service instead.
- **`AllowUnbudgetedRemote = false` is the backstop, not the plan.** Both up-remotes get explicit
  budgets. Without them `AntiCheatService.Consume` fails closed and the trial simply never starts —
  which presents as "the button does nothing", a symptom with no error attached.
- **Scope.** Nothing here is on §3's OUT list. The `Trial` block gains beats and rig speeds; it gains
  no levels, no rewards, no second trial.

### Phase 2: The decisions, as pure modules with terminal tests

Both of the trial's real decisions — *may this player start one* and *what fires at second N* — are
functions over plain tables. Putting them in `src/shared/pure/` converts the two things a reviewer
would otherwise have to take on trust into the best-verified code in this plan.

#### Step 2.1: `TrialAdmission` — may this player start a trial, and must this session end now

**File:** `src/shared/pure/TrialAdmission.luau`
**Verify:** `lune run tests/trial-admission.test.luau`

The mutual-exclusion rule itself, as a pure function. Also ships `tests/trial-admission.test.luau`.

This is the highest-value module in the plan: §1.1's central architectural claim — *the trial cannot
run while a round can* — stops being an assertion in a comment and becomes twenty cells a terminal can
walk in milliseconds. New file:

```diff
+--!strict
+--[[
+	TrialAdmission — may this player be in a Solo Trial right now, as a pure function.
+
+		evaluate(input) -> TrialStartVerdict        -- may a session OPEN
+		mustEnd(input)  -> boolean                  -- must a live session CLOSE
+
+	WHY THE RISK IN C21'S ROW LIVES HERE RATHER THAN IN A COMMENT
+	-------------------------------------------------------------
+	The build plan says it plainly: "TrialService and RoundService sharing state is how you get a
+	trial that ends a live round." The rule that prevents it is a two-line predicate — a trial may
+	only exist while RoundService is IDLE and the server is below the offer threshold — and a
+	two-line predicate buried in a service is a two-line predicate nobody ever tests. Out here every
+	combination of phase × population × existing-session is a cell somebody can argue with.
+
+	NOTE `mustEnd` IS NOT `not evaluate == OK`, AND CONFLATING THEM IS A REAL BUG. Opening and
+	staying open have different rules: a session may open only at IDLE, but a session already running
+	must survive one more player joining while the phase is still IDLE — otherwise the trial dies on
+	a join that changed nothing. Only a phase that is no longer IDLE closes a live session.
+
+	NO `script.Parent` REQUIRES (tests/README.md). The two unions are re-declared; Luau unions are
+	structural, so these and `Types.TrialStartVerdict` / `Types.RoundPhase` are the same types.
+
+	SEEDS AND INPUTS: there are none. This module is a predicate over facts the client already has
+	(the phase and the headcount both reach every client via RoundSnapshot), so publishing it in
+	`shared/` reveals nothing. Compare CLAUDE.md's rule about `Random.new(roundNumber)` — there is no
+	draw here and no seed to protect.
+]]
+
+export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
+
+export type TrialStartVerdict =
+	"OK"
+	| "DISABLED"
+	| "ALREADY_IN_TRIAL"
+	| "ROUND_NOT_IDLE"
+	| "TOO_MANY_PLAYERS"
+
+export type Input = {
+	Enabled: boolean,
+	RoundPhase: RoundPhase,
+	PlayerCount: number,
+	OfferBelowPlayerCount: number,
+	AlreadyInTrial: boolean,
+}
+
+local TrialAdmission = {}
+
+--[[
+	ORDER IS THE DESIGN, not a style choice. The verdicts are checked most-permanent first, so the
+	one a player is told is the one that will still be true in a second: "the feature is off" outranks
+	"you are already in one" outranks "a round is starting" outranks "there are enough players now".
+	A C24 button that reported TOO_MANY_PLAYERS while a round was already STARTING would send a
+	player to wait for the server to empty when what they should do is stand still.
+]]
+function TrialAdmission.evaluate(input: Input): TrialStartVerdict
+	if not input.Enabled then
+		return "DISABLED"
+	end
+
+	if input.AlreadyInTrial then
+		return "ALREADY_IN_TRIAL"
+	end
+
+	-- THE MUTUAL EXCLUSION, in one line. Every other phase means a round is being set up, is running,
+	-- or is showing its reveal, and in all three the answer is no.
+	if input.RoundPhase ~= "IDLE" then
+		return "ROUND_NOT_IDLE"
+	end
+
+	--[[
+		§9.1: the trial is the BELOW-MinPlayers fallback. At or above the threshold a real round is
+		about to begin, and starting a 90-second solo tutorial in front of it is how the trial ends up
+		competing with the game instead of feeding it.
+
+		Strictly below, matching the field's name. `OfferBelowPlayerCount == Round.MinPlayers` is
+		pinned in tests/config.test.luau, so this and RoundService's own `>= MinPlayers` gate
+		(RoundService.luau:1003) partition the headcount line exactly, with no value on both sides.
+	]]
+	if input.PlayerCount >= input.OfferBelowPlayerCount then
+		return "TOO_MANY_PLAYERS"
+	end
+
+	return "OK"
+end
+
+--[[
+	THE ROUND WINS. See the plan's §1.1: a live session ends the moment the phase leaves IDLE rather
+	than the round waiting for it. Population is deliberately NOT consulted — a third player joining
+	while the phase is still IDLE does not end anybody's trial; the phase change that follows a
+	moment later does, and that is the event with the 25 seconds of INTERMISSION runway behind it.
+]]
+function TrialAdmission.mustEnd(phase: RoundPhase): boolean
+	return phase ~= "IDLE"
+end
+
+return TrialAdmission
```

`tests/trial-admission.test.luau` follows `tests/round-transitions.test.luau`'s shape — an explicit
case table, then properties. The cases that must be present:

- All five `RoundPhase` values × in-trial × below/at/above threshold, written out rather than spot-checked.
- `Enabled = false` returns `DISABLED` from every one of those cells.
- The exact boundary: `PlayerCount == OfferBelowPlayerCount` is `TOO_MANY_PLAYERS`, one below is `OK`.
- **The property that is the plan's thesis:** for every input where `RoundPhase ~= "IDLE"`,
  `evaluate` never returns `OK` *and* `mustEnd` returns true. Stated as a property rather than as
  cells so a future edit cannot satisfy the table by accident while breaking the rule.
- The `mustEnd` ≠ `not OK` distinction: at `IDLE` with `PlayerCount` at the threshold, `evaluate` is
  `TOO_MANY_PLAYERS` but `mustEnd` is false — a running trial survives.

#### Step 2.2: `TrialTimeline` — which beats have fired by second N

**File:** `src/shared/pure/TrialTimeline.luau`
**Verify:** `lune run tests/trial-timeline.test.luau`

The scripted script: the beat schedule, fire-once semantics, and the boundary behaviour at
`ScriptedChaseAt` and `Duration`. Also ships `tests/trial-timeline.test.luau`. New file:

```diff
+--!strict
+--[[
+	TrialTimeline — what the Solo Trial fires at second N, as a pure function.
+
+		dueBeats(elapsed, schedule, fired) -> { TrialBeat }   -- beats owed RIGHT NOW, in order
+		phaseAt(elapsed, schedule, tasksDone) -> TrialPhase
+
+	WHY A TABLE AND NOT SIX `task.delay` CALLS
+	------------------------------------------
+	A `task.delay` chain cannot be inspected, cannot be tested from a terminal, and — the part that
+	actually bites — cannot be CANCELLED coherently when a round starts under a player mid-trial.
+	Six pending delays firing into a session that no longer exists is the shape of a trial reaching
+	into a live round, which is the one failure this whole plan is organised against.
+
+	Driven instead off the session's own elapsed time: TrialService ticks, asks what it owes, and
+	fires it. A cancelled session simply stops asking, and there is nothing left pending anywhere.
+
+	FIRE-ONCE IS THE CALLER'S SET, NOT THIS MODULE'S STATE. `fired` is passed in and this module holds
+	nothing, which is what keeps it pure and what lets the test drive a whole 90 seconds in a loop.
+
+	NO `script.Parent` REQUIRES (tests/README.md). Both unions re-declared; structurally identical to
+	their `Types.luau` counterparts.
+]]
+
+export type TrialBeat =
+	"BEAT_WELCOME"
+	| "BEAT_TASKS"
+	| "BEAT_SALT_GIVEN"
+	| "BEAT_TRANSFORM"
+	| "BEAT_SALT_TAUGHT"
+	| "BEAT_HANDOFF"
+
+export type TrialPhase = "TRIAL_OFF" | "TRIAL_TASKS" | "TRIAL_CHASE" | "TRIAL_HANDOFF"
+
+-- Mirrors the seconds in Config.Trial. Passed in rather than read, so the test can drive schedules
+-- the shipped config does not contain and prove the ordering rules hold for all of them.
+export type Schedule = {
+	SaltGivenAt: number,
+	ScriptedChaseAt: number,
+	SaltTaughtAt: number,
+	HandoffAt: number,
+	Duration: number,
+}
+
+local TrialTimeline = {}
+
+-- Beat → the field naming its second. BEAT_WELCOME and BEAT_TASKS are at zero: the trial opens by
+-- telling you what to do, which is §10's whole complaint about arriving with nothing to do.
+local AT: { { beat: TrialBeat, at: string? } } = {
+	{ beat = "BEAT_WELCOME", at = nil },
+	{ beat = "BEAT_TASKS", at = nil },
+	{ beat = "BEAT_SALT_GIVEN", at = "SaltGivenAt" },
+	{ beat = "BEAT_TRANSFORM", at = "ScriptedChaseAt" },
+	{ beat = "BEAT_SALT_TAUGHT", at = "SaltTaughtAt" },
+	{ beat = "BEAT_HANDOFF", at = "HandoffAt" },
+}
+
+--[[
+	Every beat whose moment has passed and which has not already fired, in schedule order.
+
+	RETURNS A LIST RATHER THAN ONE BEAT, and that is the hitch-tolerance property. A server hitch, or
+	a tick interval longer than the gap between two beats, would otherwise silently DROP one — a
+	player who never sees BEAT_SALT_GIVEN reaches the chase with no pouch and the tutorial teaches the
+	opposite of what §10 asks. Owing two at once is recoverable; losing one is not.
+]]
+function TrialTimeline.dueBeats(
+	elapsed: number,
+	schedule: Schedule,
+	fired: { [string]: boolean }
+): { TrialBeat }
+	local due: { TrialBeat } = {}
+
+	for _, entry in AT do
+		if fired[entry.beat] then
+			continue
+		end
+
+		local moment = if entry.at == nil then 0 else (schedule :: any)[entry.at] :: number
+
+		-- `>=` so a beat scheduled at 0 fires on the first tick rather than never.
+		if elapsed >= moment then
+			table.insert(due, entry.beat)
+		end
+	end
+
+	return due
+end
+
+--[[
+	The session's own phase, derived rather than stored. Derived for the same reason RoundService
+	derives `GateOpen` from the task count (RoundService.luau:629-638): a second piece of state with
+	its own writer is a second piece of state that can disagree with the first.
+
+	TASKS DONE BEATS THE CLOCK INTO HANDOFF. A player who finishes both tasks and survives the chase
+	is done; making them watch a timer they have already beaten is the static screen §9 item 3 says
+	reads as broken.
+]]
+function TrialTimeline.phaseAt(elapsed: number, schedule: Schedule, tasksDone: boolean): TrialPhase
+	if elapsed >= schedule.Duration then
+		return "TRIAL_OFF"
+	end
+
+	if elapsed >= schedule.HandoffAt then
+		return "TRIAL_HANDOFF"
+	end
+
+	if elapsed >= schedule.ScriptedChaseAt then
+		return "TRIAL_CHASE"
+	end
+
+	return if tasksDone then "TRIAL_HANDOFF" else "TRIAL_TASKS"
+end
+
+return TrialTimeline
```

`tests/trial-timeline.test.luau` must cover:

- Driving `elapsed` from 0 to `Duration` in one-second steps against the shipped schedule and asserting
  every beat fires **exactly once**, in the `AT` order, with none missing.
- The hitch case: jumping `elapsed` from 39 to 60 in a single step returns `BEAT_SALT_GIVEN`,
  `BEAT_TRANSFORM` and `BEAT_SALT_TAUGHT` together rather than dropping two.
- Boundary equality: at `elapsed == ScriptedChaseAt` exactly, `BEAT_TRANSFORM` is due and `phaseAt` is
  `TRIAL_CHASE` — the off-by-one that would put the transform one tick after the chase visual.
- `phaseAt(0, schedule, true)` is `TRIAL_HANDOFF`: finishing both tasks early skips ahead.
- `phaseAt(Duration, ...)` is `TRIAL_OFF` regardless of `tasksDone`.
- A degenerate schedule with every beat at 0 returns all six on the first call and none on the second.

#### Step 2.3: Pin the trial's config relationships alongside the existing thirteen

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

The trial's numbers have silent invariants of exactly the kind this suite already exists for: a chase
that starts after the trial ends teaches nothing, and an offer threshold above `MinPlayers` offers a
trial to a server that is about to start a round.

Appended to the existing thirteen relationships in `tests/config.test.luau`:

```diff
+--------------------------------------------------------------------------------
+-- The Solo Trial (C21/C22, §9.1)
+--
+-- Every one of these is silent. A trial with its beats out of order does not error, does not fail to
+-- typecheck and does not warn — it just runs a 90-second tutorial that teaches the wrong thing, and
+-- the only symptom is a playtester saying it "felt confusing".
+--------------------------------------------------------------------------------
+
+check(
+	"the chase starts before the trial ends",
+	Config.Trial.ScriptedChaseAt < Config.Trial.Duration,
+	"a transform scheduled at or after Duration never fires; the trial teaches tasks and nothing else"
+)
+
+check(
+	"salt is in hand before the thing it defends against arrives",
+	Config.Trial.SaltGivenAt < Config.Trial.ScriptedChaseAt,
+	"§10 asks that the folklore be taught by doing; a pouch that arrives mid-chase is taught by panic"
+)
+
+check(
+	"the folklore line lands after the transform, not before",
+	Config.Trial.SaltTaughtAt > Config.Trial.ScriptedChaseAt,
+	"'salt burns the aswang' means nothing until there is an aswang on screen"
+)
+
+check(
+	"the handoff has room to be read",
+	Config.Trial.HandoffAt < Config.Trial.Duration
+		and Config.Trial.HandoffAt > Config.Trial.SaltTaughtAt,
+	"the closing line is the one sentence §9.1 specifies verbatim; it cannot be the last frame"
+)
+
+--[[
+	THE PARTITION. RoundService leaves IDLE at `>= MinPlayers` (RoundService.luau:1003) and
+	TrialAdmission refuses at `>= OfferBelowPlayerCount`. Equal, those two split the headcount line
+	with no value on both sides. If OfferBelowPlayerCount were the larger, there would be a count at
+	which a round starts AND a trial is still offered — and the trial would open and be aborted in the
+	same second, which presents as a button that flickers.
+]]
+check(
+	"the trial's offer threshold and the round's floor are the same line",
+	Config.Trial.OfferBelowPlayerCount == Config.Round.MinPlayers,
+	"a gap or an overlap here means a count where both a round and a trial believe they may start"
+)
+
+check(
+	"the trial's two tasks can actually be drawn",
+	Config.Trial.TasksToComplete >= 1 and Config.Trial.TasksToComplete <= Config.Tasks.PoolSize,
+	"a trial asking for more tasks than exist can never be completed and always times out"
+)
+
+--[[
+	The rig must be survivable. Compared against `Trial.PlayerBaselineWalkSpeed` rather than against
+	anything in Config.Monster, because the trial's Aswang never goes through MonsterService — see the
+	plan's §1.1 — and because retuning the real Aswang at M12 must not retune the tutorial. If this
+	ever fails, the tutorial has grown a death path, and a death path is the first step toward the PvE
+	campaign C22's row forbids in bold.
+]]
+check(
+	"the trial's scripted Aswang cannot catch the player",
+	Config.Trial.ChaseWalkSpeed < Config.Trial.PlayerBaselineWalkSpeed,
+	"a trial Aswang that catches you needs a death, a respawn and a re-entry — none of which exist"
+)
```

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

- **`mustEnd` is not the negation of `evaluate`, and the test must say so.** Opening and staying open
  differ by exactly one input: population. Implementing `mustEnd` as `evaluate(...) ~= "OK"` would end
  a running trial the instant a third player joined, before any phase change, deleting the 25 seconds
  of `INTERMISSION` runway the design depends on. This is the single most likely wrong turn in the
  phase and it produces a plausible-looking service that fails only under a specific join timing.
- **`Config.Player.WalkSpeed` does not exist** — checked at plan time, nothing in this repo sets a walk
  speed, so survivors run at the engine default. Phase 1 therefore adds `Trial.PlayerBaselineWalkSpeed`
  purely so the survivability invariant has something to compare against, with a comment saying to
  repoint the test rather than update the mirror if a real walk speed is ever introduced.
- **`Tasks.PoolSize` is the map's total, not a round's draw.** The `TasksToComplete` invariant is
  written against `PoolSize` (12) rather than `TotalRequired` (5) because the trial draws from the map,
  not from the round's five. Comparing against `TotalRequired` would pass today and be meaningless.
- **Pure-module rule.** Neither new module may `require(script.Parent.X)` — both re-declare their
  unions locally per `tests/README.md` and CLAUDE.md. If either reaches for `Types` or `Enums`, the
  Lune verify line for that step stops running and the phase's whole value is gone.
- **`shared/` versus `server/pure/`.** Both modules are placed in `src/shared/pure/`, which
  `default.project.json` maps wholesale into `ReplicatedStorage` — so any client can `require` and
  *run* them. That is deliberate and safe here: neither takes a seed, neither takes a draw input, and
  every input to `TrialAdmission` (phase, headcount) already reaches every client via `RoundSnapshot`.
  CLAUDE.md's `Random.new(roundNumber)` hazard has no analogue in either module.
- **Scope.** `AT` has exactly six entries and the plan adds no mechanism for a seventh. A schedule that
  grows a `BEAT_BOSS` or a second timeline table is the PvE campaign arriving, and it arrives here
  first because this is the cheapest file to add one to.

### Phase 3: `TrialService` — sessions, mutual exclusion, and the remote surface (C21)

The stub at `src/server/Services/TrialService.luau` becomes the service. Its state is a private table
keyed by UserId and nothing outside this file reads or writes it.

#### Step 3.1: The session table, the lifecycle, and the abort that makes the round win

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run analyze`

Replaces the 28-line stub's TODO block with the session record, `Init`/`Start`, the
`RoundService.PhaseChanged` subscription that ends every live session the moment the phase leaves
`IDLE`, and the `Players.PlayerRemoving` teardown. The scope-guard comment survives verbatim.

```diff
 --!strict
 --[[
 	TrialService — The Solo Trial: 90s single-player practice run.
 
 	Milestone: M6
 	Spec: docs/MVP-SPEC.md
+
+	═══ HOW THIS RUNS WITHOUT TOUCHING A ROUND ═══════════════════════════════════
+
+	C21's build-plan row names the risk in one sentence: "TrialService and RoundService sharing state
+	is how you get a trial that ends a live round." Nothing in this file shares state with that one.
+	What it does, in full:
+
+	  · READS  RoundService.GetPhase()          — one query, to decide admission
+	  · LISTENS RoundService.PhaseChanged       — to end sessions when the phase leaves IDLE
+	  · WRITES nothing in RoundService, ever
+
+	It does NOT call setPhase (a file-local in RoundService and unreachable from here by construction),
+	SetTasksCompleted, EndRound, MarkKilled, GetAswangUserId, or touch state.PlayerStates. The trial's
+	two tasks are counted in `sessions` below and never reach the round's task bar.
+
+	ONE DIRECTION ONLY, and for the exact reason RoundService's own header gives about RoleService: a
+	require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
+	in IDLE forever looking precisely like "nobody has joined yet". RoundService must NEVER require
+	this file back. If it ever needs something from here, invert it — expose a registration on this
+	side rather than a require on that one.
+
+	═══ THE ROUND WINS EVERY CONFLICT ════════════════════════════════════════════
+
+	A round starting under a player mid-trial ABORTS THE TRIAL. It does not hold the round. Holding it
+	would freeze up to two other players on a countdown for up to 90 seconds so one player's tutorial
+	could finish, which is §9 item 3's "reads as broken, not as waiting" — the exact failure C24 in
+	this same plan exists to delete. §9.1 is also explicit that the Trial's job is to get people INTO
+	the multiplayer loop, so a real round starting is this feature succeeding.
+
+	The abort lands on the transition into INTERMISSION, which Config.Round.Intermission gives 25
+	seconds of runway before STARTING — enough to deliver the handoff line and walk back.
 ]]
 
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Remotes = require(Shared.Remotes)
+local TrialAdmission = require(Shared.pure.TrialAdmission)
+local TrialTimeline = require(Shared.pure.TrialTimeline)
+local Types = require(Shared.Types)
+local AntiCheatService = require(script.Parent.AntiCheatService)
+local RoundService = require(script.Parent.RoundService)
+
 local TrialService = {}
 
 -- WHY THIS EXISTS: the closest competitor lost 79.9% of players before their
 -- first objective, and their game at least worked solo. Ours does not function
 -- below MinPlayers. The Trial is both the tutorial and the low-population
 -- fallback. See spec §9.1 and Appendix C.
 --
--- TODO(M6): two guided tasks, then a scripted Aswang transform + chase.
--- TODO(M6): teach the transform tell and salt by DOING, never by text wall.
--- TODO(M6): offer it whenever player count < Config.Round.MinPlayers.
--- TODO(M6): exit straight into the lobby queue.
---
 -- SCOPE GUARD: this must never grow into a PvE campaign. Consumable content is
 -- exactly what killed the competitor.
+
+--[[
+	THE SESSION. Private to this file, keyed by UserId, and there is never more than one per player.
+
+	`Fired` is the beat set TrialTimeline needs passed in — it is held HERE rather than in the pure
+	module, which is what keeps that module pure and lets its test drive a whole 90 seconds in a loop.
+]]
+type Session = {
+	StartedAt: number,
+	TrialPhase: Types.TrialPhase,
+	Fired: { [string]: boolean },
+	TasksDone: number,
+	Rig: Model?,
+	ReturnCFrame: CFrame,
+}
+
+local sessions: { [number]: Session } = {}
+
+local snapshotRemote = Remotes.Get("TrialSnapshot")
+
+-- The Schedule shape TrialTimeline takes, built once. Read from Config so `check:config` stays happy
+-- and so M12 can retune the trial without touching this file.
+local function schedule(): TrialTimeline.Schedule
+	return {
+		SaltGivenAt = Config.Trial.SaltGivenAt,
+		ScriptedChaseAt = Config.Trial.ScriptedChaseAt,
+		SaltTaughtAt = Config.Trial.SaltTaughtAt,
+		HandoffAt = Config.Trial.HandoffAt,
+		Duration = Config.Trial.Duration,
+	}
+end
+
+function TrialService.IsInTrial(userId: number): boolean
+	return sessions[userId] ~= nil
+end
+
+--[[
+	ONE EXIT, FIVE REASONS (Types.TrialEndReason). Every path out of a session goes through here so
+	that teardown cannot be partially done: the rig is destroyed, the character goes back where it
+	came from, and the entry leaves the table. Phase 4 fills in the rig and the return.
+
+	IDEMPOTENT ON PURPOSE. `endSession` is reachable from the timer, the remote, PlayerRemoving and
+	the phase change, and at least two of those can land in the same frame — a player pressing "leave"
+	as a round starts. A second call must be a no-op rather than a second teleport.
+]]
+local function endSession(userId: number, reason: Types.TrialEndReason)
+	local session = sessions[userId]
+
+	if session == nil then
+		return
+	end
+
+	sessions[userId] = nil
+
+	if Config.Debug.VerboseLogging then
+		-- A UserId and a reason. There is no role anywhere near this feature to leak.
+		print(`[TrialService] {userId} left the trial: {reason}`)
+	end
+end
+
+function TrialService.Init() end
+
+function TrialService.Start()
+	--[[
+		THE MUTUAL EXCLUSION, and it is four lines because the hard thinking is in the pure module.
+
+		Subscribing to PhaseChanged rather than polling RoundService.GetPhase() matters: a poll can
+		miss a phase that opens and closes between two ticks, and IDLE → INTERMISSION → IDLE (a player
+		joining and leaving inside 25 seconds) is exactly that shape. The BindableEvent fires on every
+		transition, so nothing is missed.
+	]]
+	RoundService.PhaseChanged.Event:Connect(function(phase: Types.RoundPhase)
+		if not TrialAdmission.mustEnd(phase) then
+			return
+		end
+
+		for userId in sessions do
+			endSession(userId, "ROUND_STARTED")
+		end
+	end)
+
+	Players.PlayerRemoving:Connect(function(player: Player)
+		endSession(player.UserId, "PLAYER_LEFT")
+	end)
+end
```

**The connect form is copied, not guessed.** `RoundService.PhaseChanged` is an
`Instance.new("BindableEvent")` (`RoundService.luau:61`), `:Fire()`d at `RoundService.luau:679`, and
three services already subscribe to it in exactly this shape — `TaskService.luau:1632`,
`GhostService.luau:561` and `ItemService.luau:688` all use
`RoundService.PhaseChanged.Event:Connect(...)`, a **dot** before `Event` and a colon before `Connect`.
Matching them makes this the fourth instance of an established pattern rather than a new one.

#### Step 3.2: The two up-handlers, `AntiCheatService` first

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run check:ratelimit`

`RequestStartTrial` and `RequestEndTrial`, both consulting `AntiCheatService.Consume` before touching
any state, both re-deciding admission server-side through `TrialAdmission` rather than trusting that
the client only offered the button when it was legal.

```diff
+--[[
+	THE THREE THINGS A CLIENT COULD TRY, and what refuses each. Worth writing down because C21 is
+	marked 🔒 and the usual answer — "the Aswang's identity" — is not the answer here. The trial's
+	Aswang is a scripted rig, so there is no secret INSIDE a trial. The attacks run the other way:
+
+	  1. Start a trial DURING a live round. Refused by TrialAdmission's `RoundPhase ~= "IDLE"` check,
+	     which is re-run here on every call. This is the one that matters — a client that could open a
+	     session mid-round would get a teleport out of the map and a rig spawned next to a live game.
+	  2. Start a trial they are already in, to double the rig or reset the clock. Refused by
+	     ALREADY_IN_TRIAL, checked from `sessions` rather than from anything the client said.
+	  3. Spam either remote. Refused by AntiCheatService, consulted FIRST in both handlers.
+
+	NEITHER HANDLER TAKES AN ARGUMENT, so there is no fourth attack of the "name a moment, a position
+	or an outcome" kind. The player is the one Roblox gives us; everything else is server state.
+]]
+Remotes.Get("RequestStartTrial").OnServerEvent:Connect(function(player: Player)
+	if not AntiCheatService.Consume(player, "RequestStartTrial") then
+		return
+	end
+
+	--[[
+		RE-DECIDED HERE, NOT TRUSTED FROM THE BUTTON. C24 shows the entrance only when a trial is
+		available, and that is a courtesy to an honest player — never a permission. §6.2: the client
+		requests, the server decides.
+	]]
+	local verdict = TrialAdmission.evaluate({
+		Enabled = Config.Trial.Enabled,
+		RoundPhase = RoundService.GetPhase(),
+		PlayerCount = #Players:GetPlayers(),
+		OfferBelowPlayerCount = Config.Trial.OfferBelowPlayerCount,
+		AlreadyInTrial = sessions[player.UserId] ~= nil,
+	})
+
+	if verdict ~= "OK" then
+		if Config.Debug.VerboseLogging then
+			print(`[TrialService] refused {player.UserId} a trial: {verdict}`)
+		end
+
+		return
+	end
+
+	beginSession(player)
+end)
+
+-- "I am done." The server already knows whose session it is, so there is nothing to pass and nothing
+-- to validate beyond the budget and the session's existence.
+Remotes.Get("RequestEndTrial").OnServerEvent:Connect(function(player: Player)
+	if not AntiCheatService.Consume(player, "RequestEndTrial") then
+		return
+	end
+
+	endSession(player.UserId, "PLAYER_ASKED")
+end)
```

Both handlers are registered inside `TrialService.Start()`, after the `PhaseChanged` subscription from
Step 3.1. `AntiCheatService.Consume(player, remoteName)` is the signature at
`AntiCheatService.luau:106`, and `check:ratelimit` matches
`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of the
`OnServerEvent:Connect` — so the call must stay the **first** statement in each handler, which is also
where it belongs.

#### Step 3.3: The per-player push, and why it is not a snapshot broadcast

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run check:secrecy`

The `TrialSnapshot` fire — `FireClient` to the one player in the session, never `FireAllClients`, and
carrying a payload that shares no field name with `ClientRoundSnapshot`.

```diff
+--[[
+	THE PUSH, AND THE THREE RULES IT KEEPS.
+
+	1. FireClient, never FireAllClients. Not because the payload is dangerous — it is not; a trial has
+	   no secret in it — but because a broadcast would be RECEIVED BY PLAYERS NOT IN A TRIAL, and a
+	   client that receives trial state has to decide whether to render it. That decision is a bug
+	   waiting to happen and there is no reason to create it.
+
+	2. It iterates `sessions`, not `Players:GetPlayers()`. A player with no session gets nothing at
+	   all, which is what makes rule 1 true by construction rather than by a condition someone could
+	   later invert.
+
+	3. The payload is `Types.TrialSnapshot` and shares no field name with `ClientRoundSnapshot`. That
+	   is the answer to the semantic overlap `check:remotes` and `check:secrecy` structurally cannot
+	   see: both are text tripwires, and a trial payload shaped like a round payload would pass both
+	   while letting UIController render a trial timer as a sunrise timer.
+]]
+local function pushSnapshot(userId: number, beat: Types.TrialBeat?)
+	local session = sessions[userId]
+	local player = Players:GetPlayerByUserId(userId)
+
+	if session == nil or player == nil then
+		return
+	end
+
+	local elapsed = os.clock() - session.StartedAt
+
+	local payload: Types.TrialSnapshot = {
+		TrialPhase = session.TrialPhase,
+		Beat = beat,
+		TrialSecondsLeft = math.max(0, Config.Trial.Duration - elapsed),
+		TrialTasksDone = session.TasksDone,
+		TrialTasksRequired = Config.Trial.TasksToComplete,
+	}
+
+	snapshotRemote:FireClient(player, payload)
+end
+
+--[[
+	THE TICK. One loop for every session, driven off the timeline rather than off a chain of
+	`task.delay` calls — see `shared/pure/TrialTimeline`'s header for why that mattered enough to
+	shape the module.
+
+	`dueBeats` returns a LIST, so a hitch that skips past two beats fires both rather than dropping
+	one. Each is marked in `session.Fired` at the moment it is handled, which is what makes the
+	fire-once guarantee hold across a hitch as well as across a normal tick.
+]]
+local function tick()
+	for userId, session in sessions do
+		local elapsed = os.clock() - session.StartedAt
+
+		if elapsed >= Config.Trial.Duration then
+			endSession(userId, "EXPIRED")
+			continue
+		end
+
+		session.TrialPhase = TrialTimeline.phaseAt(
+			elapsed,
+			schedule(),
+			session.TasksDone >= Config.Trial.TasksToComplete
+		) :: Types.TrialPhase
+
+		for _, beat in TrialTimeline.dueBeats(elapsed, schedule(), session.Fired) do
+			session.Fired[beat] = true
+			handleBeat(userId, beat)
+			pushSnapshot(userId, beat)
+		end
+
+		pushSnapshot(userId, nil)
+	end
+end
```

The tick is driven from `Start()` on a `Config.Trial.SnapshotInterval` loop. `handleBeat` is Phase 4's
deliverable — in this step it is a stub that only logs under `VerboseLogging`, so the phase ends with a
trial whose clock, phase and task count are live on one client and whose beats do nothing yet.

Note the `:: Types.TrialPhase` cast on `phaseAt`'s return: it crosses a pure-module boundary and the
analyzer widens the returned literals to plain `string` on the way out, the same bite
`RoundService.luau:1048-1051` documents for `RejoinResolve`.

#### Step 3.4: The two trial tasks, owned here rather than by `TaskService`

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run verify:fast`

The trial's two tasks are counted inside the session and never touch `RoundService.SetTasksCompleted`
or `TaskService`'s round draw. This is the single most important non-obvious separation in the plan.

```diff
+--[[
+	THE TRIAL'S TASKS ARE NOT THE ROUND'S TASKS, AND THIS IS WHERE THAT IS TRUE OR NOT.
+
+	The tempting shortcut is to reuse TaskService: it already has hold-to-complete, presence range, a
+	progress bar and a completion path. Rejected, and the reason is the whole plan. TaskService's
+	completion path calls `RoundService.SetTasksCompleted` (TaskService writes the number the round's
+	HUD renders and the escape gate derives from, RoundService.luau:643-665). A trial task routed
+	through it would increment a live round's task bar and — at TotalRequired — OPEN THE ESCAPE GATE.
+	That is C21's row made literal: a trial that ends a live round.
+
+	It cannot happen today, because a trial only opens while the phase is IDLE and `SetTasksCompleted`
+	only opens the gate during ACTIVE. But "it is safe because two conditions happen not to overlap"
+	is the kind of safety that survives exactly until someone relaxes one of them, and the relaxation
+	would look harmless in review. The trial counts its own tasks in its own session and shares no
+	code path with the round's counter.
+
+	WHAT IS SHARED IS THE MAP, and only by tag. The trial's task points are TaskPoint parts inside the
+	TrialZone (Step 4.1), discovered the same way TaskService discovers its pool but never entered
+	into TaskService's draw — `selectForRound` picks from the map's pool and this zone's points are
+	excluded from it by the zone attribute the greybox step establishes.
+]]
+local function noteTrialTaskComplete(userId: number)
+	local session = sessions[userId]
+
+	if session == nil then
+		return
+	end
+
+	session.TasksDone = math.min(session.TasksDone + 1, Config.Trial.TasksToComplete)
+
+	pushSnapshot(userId, nil)
+end
```

The hold-to-complete loop itself lives in the tick from Step 3.3: for each session, if the player is
within `Config.Tasks.PresenceRangeStuds` of an incomplete trial point for `Config.Tasks.HoldTime`, call
`noteTrialTaskComplete`. It reuses the round's *numbers* — deliberately, so the trial teaches the real
timings — while sharing none of the round's *code path*.

**`TaskService` needs one corresponding change**, and it is the other half of the separation:
`discoverPool` (`TaskService.luau:229-262`) walks every `TaskPoint`-tagged part in the map, so the
trial zone's points would otherwise be drawn into real rounds — putting a live objective in a corner
players are teleported to. `discoverPool` must skip parts carrying the zone attribute from Step 4.1.

**Why `verify:fast` closes this phase.** It runs `analyze`, `check:remotes`, `check:secrecy` and
`check:toolchain` over the whole tree, which is the coarse statement worth making at the point the
service first has state, a remote surface and a tick: the trial compiles, its remotes are declared in
the right directions, and nothing it added trips the secrecy tripwire.

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

- **`init.server.luau` already lists `TrialService`** at `src/server/init.server.luau:34`, so the
  bootstrap needs no change and `Start()` will be called the moment it does something. Verified rather
  than assumed, because a service missing from `SERVICE_ORDER` does nothing and reports nothing.
  Whether line 34 sits late enough in the order to require `RoundService` safely is worth one look —
  the requires resolve at module load, not at `Start`, so the order governs `Init`/`Start` only.
- **The require direction is one-way and load-bearing.** `TrialService` requires `RoundService` and
  `AntiCheatService`. `RoundService` must never require `TrialService` back — per its own header
  (`RoundService.luau:26-28`), a cycle errors at load, `init.server.luau` swallows it into one `warn`,
  and the server sits in IDLE looking exactly like an empty lobby. If a future need runs the other
  way, invert it with a registration on this side.
- **A player dying or resetting mid-trial is unhandled in this phase and must be.** `RoundService`'s
  `watchForDeath` (`RoundService.luau:286-388`) respawns players at the SpawnLocation on `Humanoid.Died`
  — and the stock Escape → Reset button fires it at any time, in any phase. Mid-trial that silently
  teleports the player out of the trial zone while their session keeps ticking, leaving them watching
  a trial timer from the lobby. Phase 4's `endSession` paths must cover it; the honest options are to
  end the session on a mid-trial respawn or to re-place the character, and the plan takes the first.
- **`os.clock()` for elapsed, matching `RoundService`.** `GetSecondsRemaining` uses it
  (`RoundService.luau:78-80`) and `os.time()` is client-observable to the second. Nothing here is a
  seed, so this is consistency rather than secrecy — but mixing the two clocks in one codebase is how
  a drift bug gets written.
- **Rate-limit window.** `check:ratelimit` scans 1200 characters from the `OnServerEvent:Connect`. Both
  handlers are far shorter than that and put `Consume` first, so the check passes on substance rather
  than on luck — but a handler that grows past the window in a later edit would start failing.
- **Secrecy, stated in the direction that actually applies.** There is no role inside a trial. The
  live questions are (a) can a client not in a trial receive `TrialSnapshot` — no, the push iterates
  `sessions`; (b) can a client not in a trial cause trial work — no, both handlers re-run admission;
  (c) does any trial remote reuse a round remote's name or shape — no, and `Types.TrialSnapshot`
  shares no field with `ClientRoundSnapshot` so a mix-up is a type error rather than a rendering bug.
- **Being in a trial is observable to other players, and that is fine.** They can see the player walk
  to the corner and see the rig. A trial only runs while no round is running, so there is no
  round-secret to correlate it against — the same resolution `.claude/lessons/absence-is-observable.md`
  reaches for `OnboardingController`'s waypoint, one step milder.
- **Phase ownership.** Nothing in this file calls `setPhase`, and it structurally cannot: `setPhase`
  is a file-local at `RoundService.luau:671` and is not on the returned table.
- **Scope.** No rewards, no score, no persistence, no second trial. `sessions` holds a clock, a beat
  set and a task count, and nothing in it survives the session.

### Phase 4: The scripted chase, the salt, and the handoff (C22)

C22's row carries the trap in bold: *do not let this grow.* Every step here is written to the minimum
that delivers the three beats §9.1 names, and the phase deliberately ends with `check:scope`.

#### Step 4.1: The trial zone's contract with the map

**File:** `tools/greybox/barrio.luau`

Adds a `TrialZone` corner to the greybox generator and documents the tag/attribute contract in the
header block that already records what the four services demand of the map. **No `Verify:` line**: the
deliverable is geometry in the place file, `selene` covers `src` only, and a grep for a token this step
itself types would prove authorship rather than a zone a player can stand in. `verify-plan` reports
this honestly as unverifiable and `next-phase.mjs` marks the phase `needs-human` — which is correct,
because a person has to look at it.

Extending the contract table in the generator's header (`tools/greybox/barrio.luau:29-34`):

```diff
 	  SaltSpawn    × 6  ItemService.discoverPool     Config.Salt.PouchPoolSize
 	  EscapeGate   × 1  GateService.discoverGates    proximity win, Config.Tasks.GateRangeStuds = 6
+	  TrialSpawn   × 1  TrialService.findZone        where a trial player is placed
+	  TrialChase   × 1  TrialService.spawnRig        where the scripted rig appears at ScriptedChaseAt
+	  TaskPoint    × 2  TrialService (NOT TaskService) attribute `TrialZone = true`
+
+	THE `TrialZone` ATTRIBUTE IS THE WHOLE CONTRACT AND IT IS AN EXCLUSION, NOT AN INCLUSION.
+
+	The trial's two practice points carry the SAME `TaskPoint` tag as the map's twelve, because they
+	are task points and the trial's job is to teach the real interaction. That means TaskService's
+	`discoverPool` (TaskService.luau:229) finds them, and a round could DRAW one — putting a live
+	objective in a corner of the map that trial players get teleported into, and counting toward the
+	escape gate. `discoverPool` therefore skips any part with `TrialZone == true` (Step 3.4), and the
+	generator is what puts the attribute there.
+
+	If a mapper adds a trial point by hand and forgets the attribute, the symptom is a task nobody can
+	find, appearing at random every few rounds. Nothing warns. This is the one map contract in the
+	file whose violation is silent, which is why it is written out at this length.
```

The zone itself is a walled corner outside the Barrio's playable ring: floor, two `TaskPoint` anchors
carrying `TrialZone = true`, a `TrialSpawn` anchor, and a `TrialChase` anchor at the far end. §5's
mobile budget applies — no new lights beyond the Barrio's existing lantern helper.

#### Step 4.2: The scripted Aswang — a rig, not a role

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run analyze`

Spawns a server-side rig at the trial zone's chase waypoint at `ScriptedChaseAt`, plays the same visual
tell `MonsterService` broadcasts for a real transform, walks it along authored waypoints toward the
player, and destroys it on every session end. It goes nowhere near `MonsterService`, `RoleService` or
`RoundService.GetAswangUserId`.

```diff
+--[[
+	THE SCRIPTED ASWANG IS A RIG, NOT A ROLE. It has no Player, no UserId, and no entry in any role
+	table. That is what makes C22 possible without touching the secret at all: there is nothing here
+	for `check:secrecy` to protect, because the thing being revealed is a prop.
+
+	IT DOES NOT GO THROUGH MonsterService, and that is a deliberate refusal of the obvious reuse.
+	MonsterService.RequestTransform is built around a PLAYER who holds the role — it consults
+	RoleService, writes transform state keyed by UserId, and broadcasts MonsterTransformed with a
+	payload naming a player. Driving it with a fake identity would mean either inventing a UserId or
+	loosening a service on the 🔒 surface so it accepts a non-player. Both are worse than duplicating
+	forty lines of tint-and-scale here, and the C04 audit finding CLAUDE.md records — a revert that
+	restored hardcoded defaults and permanently branded the ex-Aswang — is what a "small" change to
+	that file actually costs.
+
+	WHAT IS REUSED IS THE LOOK, read from the same Config.Monster fields MonsterService reads:
+	TransformedScale, TransformedTintRgb, EyeGlowRgb and TransformTime. The tell a player learns in
+	the trial is then the tell they will see in a real round, which is the entire point of C22. Those
+	are read, never written.
+]]
+local function spawnRig(userId: number, at: CFrame): Model?
+	-- Built from a stock R15 dummy in the trial zone, tinted and scaled to Config.Monster's numbers.
+	-- Anchored HumanoidRootPart, moved by CFrame rather than by pathfinding: the zone is an empty
+	-- walled corner with nothing to path around, and PathfindingService here would be a dependency
+	-- bought for a straight line.
+end
+
+--[[
+	The chase, ticked from the same loop as everything else. It walks toward the player, stops at
+	Config.Trial.ChaseStopStuds, and holds. It never touches the player's Humanoid.
+
+	NO KILL PATH, AND THAT IS A DESIGN DECISION RATHER THAN AN OMISSION. `Config.Trial.ChaseWalkSpeed`
+	is pinned below the player's baseline in tests/config.test.luau, so it cannot catch anyone. A
+	trial that could kill you needs a death, a respawn, a re-entry and a decision about what a failed
+	trial means — and "what does failing mean" is the question whose answer is levels, retries and
+	scores. C22's row forbids that in bold. The rig menaces and is stunned; that is the encounter.
+]]
+local function stepRig(session: Session, player: Player, dt: number)
```

`handleBeat` from Step 3.3 gains its `BEAT_TRANSFORM` arm here: play the windup for
`Config.Monster.TransformTime`, apply the tint and scale, then start the chase.

**One Roblox behaviour this plan does not claim to know.** Whether a server-created rig inside a
`StreamingEnabled` world (§5) is reliably streamed to a player standing next to it, and how
`Model:ScaleTo` interacts with an anchored rig, were **not** confirmed against this codebase or a live
Studio session. `MonsterService` scales a real player character, which is a different case. This is
flagged in Follow Ups and is the reason the rig is the last gameplay piece in the plan rather than an
early one — the playtester's screenshot at the chase beat is what settles it.

#### Step 4.3: Salt is given and taught, from `Config` rather than from a literal

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run check:config`

The pouch grant, the stun response when it lands, and §10's exact line: *"Salt burns the aswang — throw
it to reveal and stun."* Every second and every stud in this step reads out of `Config.Trial`.

```diff
+--[[
+	SALT IS GIVEN BEFORE THE THING IT DEFENDS AGAINST ARRIVES (SaltGivenAt < ScriptedChaseAt, pinned
+	in tests/config.test.luau). §10 is explicit that the folklore must not be assumed: "Do not assume
+	players know salt stops an aswang." A pouch that appears mid-chase is taught by panic.
+
+	THE LINE ITSELF FIRES AT SaltTaughtAt, THREE SECONDS AFTER THE TRANSFORM — after the fright, not
+	during it. A sentence delivered on the same frame as a monster appearing is a sentence nobody
+	reads, which is §10's "wall of text" failure wearing a different hat.
+]]
+local TEACH_SALT = "Salt burns the aswang — throw it to reveal and stun."
+
+--[[
+	THE STUN. When a thrown pouch lands on the rig, the chase stops for Config.Trial.ChaseStunSeconds
+	and the trial moves to its handoff.
+
+	WHY NOT ItemService: the same argument as MonsterService one step up. ItemService's throw
+	resolution is built around a round — it consults phase, thrower state and the Aswang's identity to
+	decide a reveal (Types.SaltVerdict carries WRONG_PHASE and THROWER_NOT_ALIVE), none of which has a
+	meaning inside a trial where the phase is IDLE, the thrower is in no round and the target has no
+	role. The trial hands the player a pouch and watches for a hit on its own rig.
+
+	WHAT IS REUSED, AGAIN, IS THE FEEL: Config.Salt's throw arc and range, so the throw a player
+	learns here is the throw that works in a round.
+]]
```

Both the grant and the stun hang off `handleBeat`'s `BEAT_SALT_GIVEN` and `BEAT_SALT_TAUGHT` arms and
off the rig's own hit test.

**Why `check:config` is this step's gate.** It is the step most likely to hardcode a number — a stun
duration, a throw range, a three-second delay — because all three read naturally as "just a constant
in the chase code". `check:config` fails on exactly that, and it is a real failure here rather than a
formality: `Config.Trial`'s ordering invariants from Phase 2.3 are worthless if the service reads a
literal instead of the field they pin.

#### Step 4.4: The handoff, and every path out of a session

**File:** `src/server/Services/TrialService.luau`
**Verify:** `npm run check:scope`

The ending line — *"Now do it when the monster is one of your friends."* — the return to the lobby
spawn, and the four other ways a session can end: the clock, the player asking, the player
disconnecting, and a round starting. There is no reward, no score, no unlock and no second trial.

```diff
+--[[
+	THE HANDOFF, AND THE SENTENCE §9.1 SPECIFIES VERBATIM.
+
+	"Ends with: 'Now do it when the monster is one of your friends.' → drops you into the lobby
+	queue." That is the entire ending. The player is put back at the lobby spawn and is, from that
+	moment, an ordinary player in an ordinary lobby — which is the queue. There is nothing to join,
+	because RoundService's own headcount loop (RoundService.luau:1001-1022) is the queue and it has
+	been running the whole time.
+
+	THIS IS THE STEP WHERE THE TRAP OPENS, so it is worth naming what is deliberately absent:
+
+	  · no XP, no coins, no badge          — a reward makes the trial farmable, and a farmable
+	                                          tutorial is content people replay instead of playing
+	  · no "trial complete" record          — nothing persists, so there is nothing to display,
+	                                          nothing to compare and nothing to level
+	  · no second trial, no difficulty      — C22's row forbids it in bold; Appendix C.5 is the list
+	  · no retry button                     — the trial is offered again whenever the server is empty
+	                                          enough, which is the only re-entry that exists
+
+	The ONE thing that carries forward is C23's teaching-cue set (Phase 6): a player who was taught
+	salt in the trial is not taught it again in their first round. That is a suppression, not a
+	reward — it gives nothing, it only declines to repeat itself.
+]]
+local TEACH_HANDOFF = "Now do it when the monster is one of your friends."
```

`endSession` from Step 3.1 is completed here: destroy the rig, restore the character to
`session.ReturnCFrame`, clear the pouch, and push one final `TrialSnapshot` with `TrialPhase` set to
`TRIAL_OFF` so the client tears its panel down rather than leaving a frozen timer on screen.

The fifth exit — a mid-trial death or Escape → Reset — is wired here too, as the Phase 3 issue list
requires: `Humanoid.Died` during a session calls `endSession(userId, "PLAYER_LEFT")` rather than
fighting `RoundService.watchForDeath` for control of the body. Losing the trial to a stray reset is a
far better outcome than two systems respawning the same player in two places.

**Why `check:scope` is this step's gate.** §3's OUT list is enforced by token match over `src/`, and
this is the step whose natural vocabulary — reward, unlock, level, progress, retry — overlaps it. A
failure here is the plan's own trap closing on it, which is exactly what the check is for.

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

- **UNCONFIRMED ROBLOX BEHAVIOUR — the rig, and it is the reason this phase is late.** Three things
  were not verified against this codebase or a live Studio session: whether a server-created Model is
  reliably streamed to a nearby player under §5's `StreamingEnabled`; how `Model:ScaleTo` behaves on
  an anchored rig; and whether an anchored `HumanoidRootPart` moved by `CFrame` reads as motion to a
  watching client or as teleporting. `MonsterService` scales a real player character, which is a
  different case and does not settle any of them. Per Hard Rule 1 these are declared, not guessed —
  the playtester's chase-beat screenshot is what settles them, and this is why the rig lands in the
  last gameplay phase rather than an early one.
- **The `TrialZone` attribute is a silent contract in both directions.** A trial point without it gets
  drawn into real rounds (an unfindable objective, appearing at random); a `discoverPool` filter that
  is written but never exercised looks identical to one that works. Neither has a symptom that names
  itself. Worth an explicit playtester check that a real round's five points are all in the Barrio.
- **The rig must die with the session, on all five exits.** A rig left standing after
  `ROUND_STARTED` is a monster prop visible in a live round — not a secrecy leak (it has no role) but
  a serious confusion, since the tell it wears is the tell players are trained to read. `endSession`
  is the single teardown path precisely so this cannot be half-done.
- **Mid-trial death is the edge case with two owners.** `RoundService.watchForDeath` respawns at the
  SpawnLocation on `Humanoid.Died` in any phase, and the Escape → Reset button fires it at will. The
  plan ends the session rather than contesting the body. If the implementer instead tries to re-place
  the character, they are racing a `task.delay` inside another service's respawn throttle
  (`RoundService.luau:286-388`) and it will be intermittent.
- **§6.4 edge cases that apply:** a player disconnecting mid-trial (covered, `PLAYER_LEFT`); a player
  reconnecting into a server where their session is gone (covered by construction — sessions are
  in-memory and keyed by UserId, and the entry was removed on leave, so they arrive as an ordinary
  lobby player); and a round starting mid-trial (covered, `ROUND_STARTED`). The two that do not apply
  are both about round roles, which a trial has none of.
- **Mobile budget (§5).** The rig adds one animated Model and the eye-glow `PointLight` pair that
  `Config.Monster.EyeGlowRgb` implies. It exists only between `ScriptedChaseAt` and the session's end
  — under 35 seconds — and only ever one at a time, since only one player can be in a trial per
  session and the trial only runs below `MinPlayers`.
- **Scope, and this is the phase where it is a live risk.** No reward, no persistence, no retry, no
  second trial, no difficulty. If any step here starts to need a "what happens when you fail" answer,
  that is the PvE campaign arriving and the correct move is to cut it and note it here.

### Phase 5: The client's trial surface, and one teaching-line renderer

`OnboardingController` already owns a teaching-line label, its copy, its lift above `UIController`'s
prompt row and its dwell time. C23 needs the same label and so does the trial. Building a second one
puts two labels at the same screen position, so this phase makes the existing one a callable surface
and gives the trial its own controller for *state* only.

#### Step 5.1: `OnboardingController` gains `ShowLine`, and keeps its own line as one caller

**File:** `src/client/Controllers/OnboardingController.luau`
**Verify:** `npm run lint`

`ensureHint`, `LAYOUT.HintSize/HintLift/HintSeconds` and the dwell `task.delay` become
`OnboardingController.ShowLine(text: string)`. The C20 arrival line becomes its first caller with no
behavioural change.

**This is the answer to "does C23 extend `OnboardingController` or add a sibling", and it is: the
renderer is extended, the state lives elsewhere.** The reasoning, in the order it actually matters:

1. **A sibling would collide on screen.** `OnboardingController` positions its label at
   `UDim2.new(0, 0, 1, -LAYOUT.HintLift)` with `HintLift = 120`, chosen — per its own comment — to
   clear `UIController`'s prompt row. A second controller drawing a teaching line would either
   duplicate that constant or pick a different one, and the two labels would overlap the first time a
   trial beat and a C23 cue landed together. There is one teaching-line slot on this screen; it should
   have one owner.
2. **The dwell, the font, the stroke and the copy style are already decided here.** Reproducing them
   is how two teaching lines end up looking like two different features.
3. **What is NOT shared is state.** `OnboardingController` keeps owning the C20 waypoint and its
   `hintShown` flag. The trial's beats live in `TrialController` and C23's fired-set lives on the
   server. `ShowLine` is a rendering primitive with no memory, which is what lets three callers share
   it without sharing anything else.

```diff
+--[[
+	THE TEACHING-LINE SLOT, and after C21/C23 this controller owns it for the whole client.
+
+	Three callers now: this file's own C20 arrival line, TrialController's beats (C21/C22), and the
+	TeachingCue handler (C23). They share a LABEL and nothing else — no state, no timer, no memory of
+	what was shown. `hintShown` below stays private to the C20 objective and is not consulted here.
+
+	Fire-once is deliberately NOT this function's job. C20 tracks its own; C23's "once ever" lives on
+	the server where it survives a rejoin (see TeachingService). A ShowLine that remembered would give
+	those two subtly different meanings of "once" and one of them would be wrong.
+
+	LAST WRITER WINS, on purpose. Two lines within HintSeconds of each other is a real possibility —
+	a trial beat landing on a C23 cue — and the newer one is the one describing what just happened.
+	The pending hide is re-armed on every call rather than left to fire from the older one, which
+	would otherwise blank the newer line early.
+]]
+function OnboardingController.ShowLine(text: string)
+	ensureHint()
+
+	local teach = hint
+
+	if teach == nil then
+		return
+	end
+
+	teach.Text = text
+	teach.Visible = true
+
+	lineToken += 1
+
+	local token = lineToken
+
+	task.delay(LAYOUT.HintSeconds, function()
+		-- The token is what makes re-arming safe: an older timer finds the counter moved on and does
+		-- nothing, instead of hiding a line that replaced the one it was scheduled for.
+		if token == lineToken and teach.Parent ~= nil then
+			teach.Visible = false
+		end
+	end)
+end
```

`ensureHint` loses its hardcoded `label.Text = TEACH_LINE` (the text now arrives per call), a
`lineToken` module local is added beside `hintShown`, and the C20 arrival path in `watch` becomes
`OnboardingController.ShowLine(TEACH_LINE)` — dropping its own `task.delay`, which `ShowLine` now owns.

**Why `npm run lint` gates this step.** It is a pure refactor of existing code with no new types and no
new remote, so `analyze` and the checks have nothing new to say — but selene catches the two things a
refactor like this actually breaks: an unused local left behind when `TEACH_LINE`'s old call site is
rewritten, and a shadowed `teach`.

#### Step 5.2: `TrialController` — renders the trial's own state, delegates its words

**File:** `src/client/Controllers/TrialController.luau`
**Verify:** `npm run analyze`

A new controller that listens to `TrialSnapshot`, draws the trial's timer and task count in a panel
that is visibly not the round HUD, and calls `OnboardingController.ShowLine` for every beat's copy.

```diff
+--!strict
+--[[
+	TrialController — what a player in the Solo Trial sees (C21/C22, §9.1).
+
+	═══ IT RENDERS A DIFFERENT PANEL FROM THE ROUND HUD, DELIBERATELY ════════════
+
+	The trial's timer is not a sunrise timer and its "1/2" is not the round's task bar. Drawing them
+	in UIController's slots would teach a player to read those slots and then change what they mean —
+	and, more practically, would leave the round HUD holding trial numbers if a push arrived out of
+	order. A separate panel with its own position cannot be confused with the thing it is not.
+
+	The types enforce the same separation from the other end: `Types.TrialSnapshot` shares no field
+	name with `ClientRoundSnapshot`, so this controller could not render a round snapshot even if it
+	were wired to the wrong remote — it would fail to typecheck.
+
+	═══ IT OWNS NO WORDS ═════════════════════════════════════════════════════════
+
+	Every teaching line goes through `OnboardingController.ShowLine`. There is one teaching-line slot
+	on this screen and that controller owns it — see its header. This file maps a beat to a string and
+	hands it over.
+]]
+
+local COPY: { [string]: string } = {
+	BEAT_WELCOME = "A quick run-through. Nobody else is here.",
+	BEAT_TASKS = "Find the two glowing points. Hold <b>E</b> at each.",
+	BEAT_SALT_GIVEN = "Take the salt.",
+	-- BEAT_TRANSFORM has no line, and that is the design. §9.1: "You learn the tell." A caption over
+	-- a transform tells you what you are seeing instead of letting you see it, which is precisely
+	-- §10's "teach by doing, not by reading". The tell is the teaching.
+	BEAT_SALT_TAUGHT = "Salt burns the aswang — throw it to reveal and stun.",
+	BEAT_HANDOFF = "Now do it when the monster is one of your friends.",
+}
```

The controller connects `TrialSnapshot`, builds its panel on the first push where `TrialPhase ~=
"TRIAL_OFF"`, tears it down on `TRIAL_OFF`, and calls `ShowLine(COPY[beat])` whenever a push carries a
`Beat`. It fires `RequestEndTrial` from the panel's own leave button.

**Two copies of two strings, and the duplication is deliberate.** `TEACH_SALT` and `TEACH_HANDOFF`
exist on the server (Phase 4.3, 4.4) and here. The server's are what it logs and what drives its
beats; the client's are what a player reads. Sending the text down the wire instead would put player-
facing copy in a payload, which is a localisation and a trust problem for no gain — and §9.1 specifies
the handoff sentence verbatim, so it is spec text rather than a tunable. Noted in Follow Ups.

#### Step 5.3: Register the controller, in the right place in the order

**File:** `src/client/init.client.luau`
**Verify:** `npm run verify:fast`

`TrialController` into `CONTROLLER_ORDER` after `OnboardingController` (which it requires) and before
`InputController` (whose binds can fire immediately), with the comment this list's existing entries set
the standard for.

```diff
 	"OnboardingController",
+	--[[
+		C21. AFTER OnboardingController, because it calls that controller's `ShowLine` and the label
+		should exist before a beat can ask for it. Before InputController for the reason every entry
+		here is: a trial can be in progress the moment this client finishes loading — a rejoin into
+		one's own session is impossible (sessions do not survive a leave), but a snapshot push is
+		driven by a server tick that does not wait for anybody's controllers.
+
+		THE ORDER GOVERNS Init/Start, NOT THE REQUIRE, which is direct and resolves at module load —
+		this list's own header says so. What the position buys is that `ShowLine`'s label has been
+		created by the time a beat arrives, not that the module is loaded.
+	]]
+	"TrialController",
 	"InputController",
```

**A controller requiring a sibling is new in this codebase and is flagged as such** (Hard Rule 4).
Every existing controller requires only `Shared`. The alternative was a third teaching-line label,
which Step 5.1 explains at length is worse. The dependency is one-way and shallow —
`TrialController` → `OnboardingController` → nothing — so it cannot cycle, and it is the same
one-direction discipline `RoundService`'s header applies on the server. If a second sibling dependency
ever appears, that is the moment to extract a small `client/Ui` module instead of growing a web.

**Why `verify:fast` closes this phase.** It runs `analyze`, `check:remotes`, `check:secrecy` and
`check:toolchain` at the point the client half first exists end to end — and `check:remotes` is the one
that matters here, because a controller registered in the order but listening to a remote name the
server never declared would otherwise hang on `WaitForChild` **forever**, with no error and no output.

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

- **New pattern, declared: a controller requiring a controller.** No existing controller does this.
  Justified in Step 5.3 and bounded to one edge; if a second appears, extract a shared UI module
  rather than adding it.
- **`check:config` and client literals.** `UIController` and `OnboardingController` both keep their
  layout numbers in one `LAYOUT` block with `-- config-ok:` waivers, and their headers say why:
  `check:config` flags every literal under `src/client/`, and scattering waivers makes them invisible
  in a diff. `TrialController` must follow that convention, not invent a third one.
- **The C20 refactor must not change C20's behaviour.** `ShowLine` re-arms its hide timer where the
  old code armed one per objective. For the single-caller C20 path the observable behaviour is
  identical; the token exists so the *multi*-caller case does not blank a new line early. Worth a
  playtester check that the first-objective line still appears and still dwells.
- **Secrecy: nothing crosses here.** This phase adds no remote and no payload. `TrialController`
  renders only what `TrialSnapshot` already carried, and that push goes to one player who is in a
  trial, which only exists while no round does.
- **Mobile budget (§5).** One `ScreenGui` with a panel and two labels, built on the first trial push
  and destroyed at `TRIAL_OFF` — not built at load and hidden. No new lights, no particles, no
  per-frame work: the panel updates on the server's `SnapshotInterval` push, not on `Heartbeat`.
- **Scope.** The panel shows a clock and `n/2`. No score, no rating, no "trial complete" screen.

### Phase 6: C23 — one line, once ever, at the four moments that need it

C20's `everCompleted` table and its one-player `FirstObjectiveAssigned` fire are this pattern with a
single trigger. C23 is that generalised: the *decision* moves to a pure module, the *bookkeeping* moves
to one small service so it has a single home to migrate into the profile at C40, and the *rendering*
reuses Phase 5's `ShowLine` rather than adding a sibling controller.

#### Step 6.1: `TeachingLines` — which line, and has this player seen it

**File:** `src/shared/pure/TeachingLines.luau`
**Verify:** `lune run tests/teaching-lines.test.luau`

Copy and fire-once logic over plain tables, plus `tests/teaching-lines.test.luau`. New file:

```diff
+--!strict
+--[[
+	TeachingLines — which one-liner, and has this player already seen it (C23, §10).
+
+		resolve(cueId, seen) -> string?     -- nil means "already taught, or not a cue"
+
+	C23's DONE CONDITION IS A PROPERTY, NOT A FEATURE: "every first-time interaction has exactly one
+	line; none repeat." Exactly-one and never-again are the two things a hand-rolled `if seen then`
+	in four different services would get subtly wrong in at least one of them, and the symptom — a
+	line that repeats every round — is the "wall of text" §10 names as the failure, arriving by
+	accretion rather than by design.
+
+	NO `script.Parent` REQUIRES (tests/README.md); the cue union is re-declared and is structurally
+	identical to `Types.TeachingCueId`.
+
+	COPY LIVES HERE, WITH THE RULE THAT SELECTS IT. §10 gives one of these verbatim ("Salt burns the
+	aswang — throw it to reveal and stun"), and keeping the four in one table is what makes "exactly
+	one line per interaction" something a reader can check by looking rather than by grepping four
+	services.
+
+	FOUR ENTRIES, AND THE TABLE IS CLOSED. C23's row lists exactly four moments. A fifth is a design
+	decision, not a copy edit — every line added past the point of need is the wall of text arriving
+	one sentence at a time, which is the specific way this failure mode actually happens.
+]]
+
+export type TeachingCueId =
+	"CUE_FIRST_SALT"
+	| "CUE_FIRST_GHOST_DEATH"
+	| "CUE_FIRST_TRANSFORM_SEEN"
+	| "CUE_FIRST_TWO_PERSON"
+
+local TeachingLines = {}
+
+local COPY: { [string]: string } = {
+	-- §10, verbatim: "Do not assume players know salt stops an aswang."
+	CUE_FIRST_SALT = "Salt burns the aswang — throw it to reveal and stun.",
+	-- §4.7: a ghost can still contribute. Without this, dying reads as the round being over for you,
+	-- and a player who thinks they are done alt-tabs instead of helping.
+	CUE_FIRST_GHOST_DEATH = "You can still help — haunt the tasks your friends are working on.",
+	-- THE TELL, and the one line here that must not say who. "Someone" is doing load-bearing work:
+	-- MonsterTransformed is public by design (Remotes.luau:36) and names the transformed player to
+	-- every client, but this line is shown to a player who is ALREADY WATCHING it happen. It teaches
+	-- what they are seeing; it must never become a sentence that reports a transform they missed.
+	CUE_FIRST_TRANSFORM_SEEN = "That is the tell. Run, or salt it.",
+	CUE_FIRST_TWO_PERSON = "This one needs two. Wait for someone.",
+}
+
+--[[
+	`seen` is passed in and this module holds nothing — the same shape as TrialTimeline's `fired`, and
+	for the same reason. The set lives in TeachingService, which is where it can survive a rejoin and
+	where C40 will move it into the profile.
+
+	AN UNKNOWN ID RETURNS nil RATHER THAN ERRORING. A caller passing a cue that no longer exists —
+	a service kept after a line was cut — should teach nothing, not crash a service on the 🔒 surface.
+]]
+function TeachingLines.resolve(cueId: string, seen: { [string]: boolean }): string?
+	if seen[cueId] then
+		return nil
+	end
+
+	return COPY[cueId]
+end
+
+-- Every cue this module knows, for the test's exhaustive walk and for TeachingService's validation of
+-- what a caller passed. Deliberately derived from COPY rather than written twice.
+function TeachingLines.all(): { string }
+	local ids: { string } = {}
+
+	for id in COPY do
+		table.insert(ids, id)
+	end
+
+	table.sort(ids)
+
+	return ids
+end
+
+return TeachingLines
```

`tests/teaching-lines.test.luau` must cover:

- **C23's done condition, as a property over `all()`**: for every cue, `resolve(id, {})` returns a
  non-empty string, and `resolve(id, { [id] = true })` returns nil. Written as a loop over `all()` so
  a fifth cue added later is tested automatically rather than silently untested.
- Independence: marking one cue seen does not suppress any other.
- An unknown id returns nil against both an empty and a populated set, and does not error.
- No two cues share copy — two triggers showing the same sentence is a design mistake that reads in
  play as a line repeating, which is the exact thing C23 forbids.

#### Step 6.2: `TeachingService` — the ever-set and the one remote that carries it

**File:** `src/server/Services/TeachingService.luau`
**Verify:** `npm run check:secrecy`

A `TeachingService.Cue(player, triggerId)` other services call, the in-memory seen-set, and the
`TeachingCue` `FireClient`. Server-side because "ever" must survive a client rejoin, and because that
is where C20 already put it.

```diff
+--!strict
+--[[
+	TeachingService — one line, once ever, at the moment it is needed (C23, §10).
+
+	═══ WHY THIS IS SERVER-SIDE AND NOT A CLIENT FLAG ════════════════════════════
+
+	"Once ever" has to survive a rejoin, and a client-side flag does not: leave and come back and the
+	game teaches you salt again, which is exactly the repetition C23's done condition forbids. It is
+	also where the equivalent already lives — TaskService's `everCompleted` (TaskService.luau:143) is
+	this same idea with one trigger, and its comment says the same thing: in-memory now, in the
+	profile at C40.
+
+	═══ WHY IT IS ONE SERVICE AND NOT FOUR SETS ══════════════════════════════════
+
+	The four triggers live in four different services — a salt pickup, a ghost death, a transform, a
+	two-person task. Each could hold its own "have they seen it" table, and then C40 would have four
+	migrations into the profile instead of one, and "none repeat" would be four separate promises.
+	One table, one remote, one place to migrate.
+
+	CALLERS PASS A TRIGGER, NEVER A SENTENCE. `Cue(player, "CUE_FIRST_SALT")` — the copy is in
+	`shared/pure/TeachingLines` and the caller does not know it. A service that passed text would be a
+	service that could show a fifth line without anyone editing the table that is supposed to be
+	closed.
+]]
+
+local seen: { [number]: { [string]: boolean } } = {}
+
+local cueRemote = Remotes.Get("TeachingCue")
+
+--[[
+	IDEMPOTENT AND CHEAP, because the call sites are inside hot paths — a pickup handler, a task tick.
+	Every caller may call this unconditionally on every occurrence of its event, and the second call
+	onward costs a table lookup and returns. That is the point: a caller that had to ask "is this the
+	first time" first would be a caller that could get the answer wrong, which is the bug C23 is.
+
+	IT SENDS THE ID, NOT THE COPY. The client re-resolves through the same pure module. Player-facing
+	text does not belong in a payload — see TrialController's note on the same decision.
+]]
+function TeachingService.Cue(player: Player, cueId: Types.TeachingCueId)
+	local forPlayer = seen[player.UserId]
+
+	if forPlayer == nil then
+		forPlayer = {}
+		seen[player.UserId] = forPlayer
+	end
+
+	-- Resolved rather than merely checked, so an id no longer in the table teaches nothing instead of
+	-- being marked seen and silently swallowed.
+	if TeachingLines.resolve(cueId, forPlayer) == nil then
+		return
+	end
+
+	forPlayer[cueId] = true
+
+	cueRemote:FireClient(player, cueId)
+end
+
+--[[
+	THE TRIAL FEEDS THIS, AND IT IS A SUPPRESSION RATHER THAN A REWARD. A player taught salt in the
+	Solo Trial should not be taught it again in their first real round — that is a line repeating,
+	which C23 forbids. TrialService marks CUE_FIRST_SALT seen at BEAT_SALT_TAUGHT.
+
+	Worth being precise about, since Phase 4.4 promises the trial grants nothing: this gives the
+	player no advantage, no currency and no state anyone can see. It only declines to repeat itself.
+]]
+function TeachingService.MarkSeen(player: Player, cueId: Types.TeachingCueId)
+	local forPlayer = seen[player.UserId] or {}
+
+	forPlayer[cueId] = true
+	seen[player.UserId] = forPlayer
+end
```

`Players.PlayerRemoving` clears the entry — matching `TaskService.luau:1346`'s treatment of
`everCompleted`, so the two tables have the same lifetime and C40 migrates them together.
`TeachingService` goes into `SERVICE_ORDER` in `src/server/init.server.luau`.

**Why `check:secrecy` is this step's gate.** It adds a per-player down-remote, which is the shape the
check exists to scrutinise, and it fires inside `MonsterService`'s and `GhostService`'s neighbourhoods
in the next step. The payload is a cue id and the audience is one player, so it should pass on
substance — and if it does not, the reason will be worth reading.

#### Step 6.3: The four trigger sites, one line each

**File:** `src/server/Services/ItemService.luau`
**Verify:** `npm run analyze`

First salt pickup (`ItemService`), first ghost death (`GhostService`), first transform witnessed
(`MonsterService`), first two-person task (`TaskService`). One `TeachingService.Cue` call each, no
other change to those files.

| Trigger | File | Where | The cue |
| --- | --- | --- | --- |
| First salt pickup | `ItemService.luau` | the pouch-pickup path | `CUE_FIRST_SALT` |
| First ghost death | `GhostService.luau` | where a player becomes a ghost | `CUE_FIRST_GHOST_DEATH` |
| First transform witnessed | `MonsterService.luau` | the `MonsterTransformed` broadcast loop | `CUE_FIRST_TRANSFORM_SEEN` |
| First two-person task | `TaskService.luau` | where a `TWO_PERSON` point is first stood at | `CUE_FIRST_TWO_PERSON` |

**Three of these are trivial. The transform one is not, and it is the only place in this phase where
the 🔒 surface is genuinely live.**

```diff
+--[[
+	C23. Cue the players who can actually SEE this, and nobody else.
+
+	`MonsterTransformed` is public by design (Remotes.luau:36) — the tell is the point and broadcasting
+	it is correct. But "who received a teaching cue about a transform" is a DERIVED signal that the
+	broadcast is not: it fires to a subset, and the subset is "players who were nearby and new".
+
+	THAT SUBSET MUST NOT BE COMPUTED FROM THE ASWANG'S POSITION IN A WAY THAT OUTLIVES THE BROADCAST.
+	It does not here — the cue is fired to the same audience, in the same loop, in the same frame as
+	the broadcast that already told them. A cue sent to a player who did NOT receive the broadcast
+	would be new information about where the Aswang is, delivered to one client. That is the mistake
+	available in this step and it would look like a two-line change.
+
+	The cue also names nobody: `CUE_FIRST_TRANSFORM_SEEN` resolves to "That is the tell. Run, or salt
+	it." A cue that resolved to a sentence naming the transformed player would be a second carrier of
+	a role, and `check-secrecy.mjs`'s allowlist has exactly two entries for a reason.
+]]
```

The other three carry no such hazard: a pickup, one's own death, and standing at a task point are all
things the receiving player did themselves.

**Why `analyze` gates this step.** It touches four services on the 🔒 surface with one call each; what
can go wrong mechanically is a bad require path or a cue id that is not a `Types.TeachingCueId`, and
the typechecker catches both. What it cannot catch is the audience question above — that is
`exploit-auditor`'s, and this step is exactly why the routing table names it for `src/server/**`.

#### Step 6.4: The client side — no new label, no new controller

**File:** `src/client/Controllers/OnboardingController.luau`
**Verify:** `npm run verify:fast`

A `TeachingCue` handler that resolves the id to copy through the shared pure module and calls
`ShowLine`.

```diff
+	--[[
+		C23. Six lines, because Step 5.1 already built the slot and the server already decided.
+
+		`seen` is passed EMPTY on purpose. The server is the authority on "once ever" and has already
+		refused to send this if the player has seen it; a client-side set here would be a second,
+		weaker copy of that rule which could only ever disagree with it. What this call is for is the
+		copy lookup — resolve returns nil for an id this client's build does not know, which is what
+		makes a server ahead of a client a no-op instead of a blank line.
+	]]
+	Remotes.Get("TeachingCue").OnClientEvent:Connect(function(cueId: string)
+		local line = TeachingLines.resolve(cueId, {})
+
+		if line == nil then
+			return
+		end
+
+		OnboardingController.ShowLine(line)
+	end)
```

Added to `OnboardingController.Start()`, next to its existing `FirstObjectiveAssigned` and
`PhaseChanged` handlers. **No new controller, no new label, no new ScreenGui** — which is the whole
argument of Step 5.1 arriving at its payoff: C23's client half is six lines because the slot has one
owner.

**Why `verify:fast` closes this phase.** `check:remotes` is the one that earns it: `TeachingCue` is
consumed here by name, and a client `WaitForChild` on a remote the server never declared hangs forever
with no error, no output and no stack trace. This is the phase's only new client-side remote listener.

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

- **The transform cue's audience is the one real secrecy question in this plan.** It must be fired to
  the same players, in the same loop, in the same frame as the `MonsterTransformed` broadcast they
  already received. A cue reaching a player who did *not* receive the broadcast is new information
  about the Aswang's whereabouts, delivered per-client, and `check:secrecy` cannot see it — the fire
  shape is textually identical either way, exactly as `GhostRoster`'s comment
  (`Remotes.luau:41-53`) records for the same class of mistake. This is `exploit-auditor` work.
- **The cue must never name the transformed player.** `check-secrecy.mjs`'s reveal allowlist has two
  entries, `RoundEnded` and `RoleAssigned`, and adding a third requires editing that file so it shows
  in review. `TeachingCue` must not become one; its payload is a cue id and its copy names nobody.
- **`Types.TeachingCueId` versus the pure module's local union.** Both are declared and are
  structurally identical, so they pass to each other without a cast — but they are two lists that must
  stay in step, the same standing cost every `pure/` module in this repo pays. Adding a fifth cue means
  editing both.
- **No client->server remote in C23, so `check:ratelimit` has nothing to say about it.** Every trigger
  is a server-observed event. If a future edit adds a "the client says it saw a transform" remote, that
  is a client asserting a fact about the Aswang and it must be refused, not rate-limited.
- **§6.4: a player leaving mid-round.** `seen` is cleared on `PlayerRemoving`, matching
  `TaskService.luau:1346`. So "once ever" is really "once per session" until C40 — which is C20's
  existing behaviour and its stated limitation, not a regression this phase introduces.
- **The trial's suppression is a suppression, not a reward.** `MarkSeen` gives no advantage, no
  currency and no observable state. It only declines to repeat a line. This is the one piece of state
  that crosses from the trial into a real round and it is worth re-checking against Phase 4.4's list
  of things the trial deliberately does not grant.
- **Scope.** Four cues, and the table is closed. A fifth line is a design decision, and every line
  added past the point of need is §10's wall of text arriving one sentence at a time.

### Phase 7: C24 — the lobby is not dead

§9 item 3, and C24's row: three things to look at and a countdown that is always visible. The finding
that shapes this phase is that during `IDLE` there is nothing to count down to —
`RoundService.GetSecondsRemaining()` returns 0 because `PhaseEndsAt` is 0 — so the "always visible
countdown" at `IDLE` has to be a different sentence, not a zero.

#### Step 7.1: `IDLE` gets a headcount line, not a frozen `0:00`

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `npm run analyze`

`render` learns to distinguish "waiting for players" from "counting down", so the largest number on
screen is never a stopped clock.

**The finding that shapes this phase, read out of the code rather than assumed.** `PhaseEndsAt` is set
to `0` when a phase carries no duration (`RoundService.luau:677`), and `GetSecondsRemaining` returns
`math.max(0, state.PhaseEndsAt - os.clock())` (`RoundService.luau:78-80`). `enterIdle` passes no
duration. So **during `IDLE`, `SecondsRemaining` is always 0** — and `UIController`'s countdown, which
its own comment calls "the largest thing on screen because it is the one number that matters"
(`UIController.luau:280`), currently renders `0:00` for the entire time a server is empty.

That is C24's problem stated precisely: the lobby's most prominent element is a stopped clock, and a
stopped clock is the single most legible way a game can say *broken*. §9 item 3 exists for this.

```diff
+--[[
+	C24, §9 item 3. WHAT THE BIG NUMBER SAYS WHEN THERE IS NOTHING TO COUNT.
+
+	During IDLE there is no deadline — RoundService leaves PhaseEndsAt at 0 (RoundService.luau:677)
+	because IDLE has no duration, so GetSecondsRemaining honestly returns 0. Rendering that as "0:00"
+	is a stopped clock in the largest type on screen, and a stopped clock does not read as "waiting",
+	it reads as "this game is broken" — which is precisely the §9 item 3 failure and, per Appendix C,
+	the moment a TikTok-wave player leaves and never returns.
+
+	So IDLE gets a SENTENCE rather than a number, and the sentence is about the thing that will
+	actually change: how many more people are needed. It is derived from Config.Round.MinPlayers and
+	the client's own `Players` count — no new remote, and nothing about anybody's state.
+]]
```

`render` gains an `IDLE` branch that swaps the countdown label for the waiting line and hides the
task bar, which has nothing to count during `IDLE` either.

**One honest limitation, recorded rather than papered over.** The waiting line counts
`#Players:GetPlayers()` locally. That is a headcount every client can already see in the player list,
so it leaks nothing — but it is a *second* source for a number the server also knows, and if the two
ever disagree the client's is wrong. It is used because adding a field to `ClientRoundSnapshot` for a
lobby label would widen the round contract for a cosmetic reason, and §1's "what the client is told"
says that contract does not move in this plan.

#### Step 7.2: Tips, and the Trial's entrance

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `npm run check:config`

A rotating tips panel and the button that fires `RequestStartTrial`, shown only when the server says a
trial is available. With 7.1's status line that is the three things to look at.

```diff
+--[[
+	THE THREE THINGS (C24's done condition: "the lobby has three things to look at and a countdown
+	that is always visible").
+
+	  1. the status line   — Step 7.1: a countdown when there is one, a headcount when there is not
+	  2. these tips        — rotating on Config.Community.LobbyTipSeconds
+	  3. the Trial door    — the button below, which is the one that is actually a GAME
+
+	§9.3's "cosmetic preview stand" is deliberately NOT here, and that is a scope call rather than an
+	oversight: a preview stand is map geometry plus a cosmetic-equip path through MonetizationService,
+	and neither is in C24's row. Raised in Follow Ups. Three things exist without it.
+]]
+local TIPS = {
+	"Salt burns the aswang. Throw it to reveal and stun.", -- config-ok: lobby copy, not balance
+	"Tasks go faster with two people standing at them.", -- config-ok: lobby copy
+	"The aswang has to transform to kill. That is your warning.", -- config-ok: lobby copy
+	"Watch who is never around when someone dies.", -- config-ok: lobby copy
+}
```

The tips rotate on a `task.delay` loop at `Config.Community.LobbyTipSeconds`, and the whole lobby panel
is built and torn down off the same `PhaseChanged` handler that already exists at
`UIController.luau:646-651` — which conveniently already branches on `Intermission or Idle`.

**The Trial entrance is shown from the server's answer, not the client's guess.** The button's
availability is `TrialAdmission.evaluate` run client-side for *display* only, over the phase and the
headcount the client already has. Pressing it fires `RequestStartTrial`, and the server re-runs the
same module and decides (Step 3.2). A client that shows the button when it should not gets a refusal;
a client that hides it when it should not merely misses a trial. Neither is a security question,
which is why the display side can afford to be approximate.

**Why `check:config` gates this step.** It adds four copy strings and a rotation interval to
`src/client/`, where `check:config` flags every literal. The interval belongs in `Config` (Phase 1.2
added `Community.LobbyTipSeconds`) and the copy belongs inline with `-- config-ok:` waivers, following
the convention `UIController`'s and `OnboardingController`'s headers both set out. Getting that
backwards — copy in Config, interval inline — is the plausible mistake, and this check catches half of
it while a reader catches the other half in the diff.

#### Step 7.3: The whole gate, once

**File:** `src/shared/Config.luau`
**Verify:** `npm run verify`

The plan's closing run: analyze, lint, format, all five checks, every Lune suite and the harness.

The file named is `src/shared/Config.luau` because this step's only edit is the balance pass over the
numbers Phase 1.2 introduced — the trial's beats sit where they were first written and have never been
played end to end until now. Anything moved here must keep Phase 2.3's invariants green, which is part
of what `npm run verify` runs.

**This is the only step in the plan that runs the full gate**, and it is deliberately last rather than
repeated: `verify` is ~15s and the phases before it use the narrower check that actually discriminates
their step. What it adds at the end is `fmt:check`, `test:unit` across all suites at once, `check:scope`
over the finished tree, and the harness self-test.

**What `verify` cannot tell you, and what to do next.** Every behavioural claim in C21–C24 is about a
running game: whether a solo player gets a real thing to do within 60 seconds of joining, whether the
90-second trial runs end to end, whether every first-time line appears exactly once, and whether the
lobby has three things to look at. None of that is a static check. The four rows' own **Verify** lines
all say "playtester", and the plan is not done until `verification.md` cites screenshots in
`artifacts/`: a trial task, the chase, the salt throw, the handoff, each teaching line, and the lobby
at both `IDLE` and `INTERMISSION`.

**Set the playtester's debug values before launching it** — it cannot edit `Config.luau` and will
correctly refuse. Per CLAUDE.md that means `Round.Intermission/Duration/EndScreen` plus
`Debug.SoloTesting`/`VerboseLogging`, reverted afterwards and confirmed with
`git diff src/shared/Config.luau`. Note for this plan specifically: `Debug.SoloTesting` makes
`eligiblePlayerCount()` return at least `MinPlayers` (`RoundService.luau:390-395`), which drives the
server **out of IDLE** — and a trial cannot start outside IDLE. **`SoloTesting` must be OFF to test the
trial at all**, and ON to test anything about a round. They are mutually exclusive test setups, which
is worth telling the playtester explicitly or it will report the trial button as broken.

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

- **`Config.Debug.SoloTesting` and the Solo Trial are mutually exclusive, and this will confuse
  somebody.** `SoloTesting` makes `eligiblePlayerCount()` return at least `MinPlayers`
  (`RoundService.luau:390-395`), so the server leaves `IDLE` and starts rounds with one player — and
  `TrialAdmission` refuses outside `IDLE`. The flag whose name says "test alone" is the flag that makes
  the solo feature untestable. Not a bug in either, but it must be in the playtester's brief.
- **`ClientRoundSnapshot` is not widened, and Step 7.1 is where it would have been.** The waiting line
  needs a headcount and the obvious move is a snapshot field. Amendment A3's block
  (`Types.luau:474-503`) is the standing answer: `AlivePlayerCount` was removed because a per-tick
  global count is a death oracle, and the comment explicitly names `RosterSize` and `SurvivorsRemaining`
  as the same oracle in different words. A **lobby** headcount at IDLE is genuinely not that — nobody is
  alive or dead during IDLE — but adding a count field to that payload puts a shape one edit away from
  the thing A3 removed. The client's local `#Players:GetPlayers()` costs nothing and moves no contract.
- **The countdown's `IDLE` branch must not resurrect a stopped clock elsewhere.** `ENDING` and
  `STARTING` both carry durations, so only `IDLE` needs the sentence. Check that the branch is on the
  phase and not on `SecondsRemaining == 0`, which would also catch the last second of every phase.
- **The cosmetic preview stand from §9.3 is deliberately out** — map geometry plus a
  `MonetizationService` equip path, neither of which is in C24's row. Three things exist without it and
  it is raised in Follow Ups rather than smuggled in.
- **Mobile budget (§5).** The lobby panel is client-side UI with a `task.delay` rotation, not a
  `Heartbeat` loop. No lights, no particles. It is torn down when the phase leaves the lobby.
- **Secrecy.** Nothing added in this phase crosses the boundary in either direction: no new remote, no
  new payload field, and the only data read is a headcount already in every client's player list.
- **Scope.** Tips, a countdown and a door. No lobby minigame, no shop, no leaderboard — §3's OUT list
  and Appendix C.5 both cover the temptation, and a lobby is where it usually lands.

## 3. Related Files

Every file read while planning has an annotated review in `references/`. Reviews carry only the lines
an annotation is attached to, with a line-range citation so a reader can check the live code for drift.

| File | Role in this plan | Review |
| --- | --- | --- |
| `src/server/Services/RoundService.luau` | The service this plan must not touch. Read for `setPhase`'s privacy, the `PhaseChanged` contract, `step`'s headcount gate, `SecondsRemaining` at IDLE, and the body rule | `RoundService-review.luau` |
| `src/server/Services/TrialService.luau` | The 28-line stub this plan fills in | `TrialService-review.luau` |
| `src/server/Services/TaskService.luau` | C20's `everCompleted` pattern, `discoverPool`'s tag walk (the `TrialZone` exclusion), and the `SetTasksCompleted` path the trial must not use | `TaskService-review.luau` |
| `src/shared/Remotes.luau` | The declaration lists and the comment standard the four new entries follow | `Remotes-review.luau` |
| `src/shared/Types.luau` | `ClientRoundSnapshot`, `RoundPhase`, `PlayerState` — the three contracts that stay shut — and Amendment A3 | `Types-review.luau` |
| `src/shared/Config.luau` | The existing `Trial` block, `AntiCheat.Budgets`, and the absence of any player walk speed | `Config-review.luau` |
| `src/client/Controllers/OnboardingController.luau` | C20's teaching line, which becomes `ShowLine` and the answer to C23's extend-or-sibling question | `OnboardingController-review.luau` |
| `src/shared/pure/RoundTransitions.luau` | The pure-module shape both new modules follow | `RoundTransitions-review.luau` |
| `src/server/Services/AntiCheatService.luau` | `Consume`'s signature and the shape `check:ratelimit` matches | `AntiCheatService-review.luau` |
| `src/server/init.server.luau` | Confirms `TrialService` is already in `SERVICE_ORDER` | `init.server-review.luau` |
| `src/client/init.client.luau` | `CONTROLLER_ORDER`, where `TrialController` is registered | `init.client-review.luau` |
| `tools/greybox/barrio.luau` | The map contract table the `TrialZone` rows extend | `barrio-review.luau` |
| `docs/BUILD-PLAN.md` §C21–C24 | The four rows, read at lines 515–570 | — |
| `docs/MVP-SPEC.md` §9, §9.1, §10 | The cold-start problem, the Solo Trial, and the FTUE funnel | — |

## 4. Follow Ups

### Questions / Clarifications

1. **Is aborting the trial the right call when a round starts, or should the round wait?** The plan
   chooses abort (§1.1) and gives its reasons, but this is a design decision with a real cost: a
   player 50 seconds into a 90-second tutorial loses the chase, which is the half that teaches the
   tell. The alternative — a bounded hold of, say, 15 seconds before `INTERMISSION` begins — would
   save some of those and delay everyone else. **This is a judgement about which player matters more
   and it should be made by a human, not by this plan.** It is cheap to change later: the entire rule
   is `TrialAdmission.mustEnd`, one function with its own test.

2. **The rig's three unconfirmed Roblox behaviours** (Phase 4.2): streaming of a server-created Model
   under `StreamingEnabled`, `Model:ScaleTo` on an anchored rig, and whether CFrame-driven motion on an
   anchored `HumanoidRootPart` reads as movement to a watching client. Per Hard Rule 1 these are
   declared rather than guessed. If any turns out badly, the fallback is an unanchored rig with a
   `Humanoid:MoveTo`, which trades the pathfinding-free simplicity for engine-managed motion.

3. **§9.3's cosmetic preview stand is not in this plan.** C24's row asks for it; it needs map geometry
   plus a `MonetizationService` equip path, and neither is C24-sized. The lobby has three things to
   look at without it. Worth a separate small chunk, or worth cutting.

4. **Teaching copy exists in three places** — `TrialController.COPY`, `pure/TeachingLines.COPY`, and two
   server-side constants in `TrialService` — and this is deliberate (payloads carry ids, not player-
   facing text). It is still three places, and if a fourth appears the right move is one shared copy
   module rather than a fifth. Flagged so the duplication is a decision on the record.

5. **`Config.Trial.PlayerBaselineWalkSpeed` mirrors an engine default.** Nothing in this repo sets a
   walk speed, so survivors run at Roblox's stock 16 and the invariant pinning the rig below it has
   nothing else to compare against. If the game ever sets a real walk speed, repoint the test at it and
   delete the mirror — do not update the mirror's number, which would keep the test green while making
   it meaningless.

6. **"Once ever" is really "once per session" until C40.** `TeachingService`'s set is in-memory and
   cleared on `PlayerRemoving`, matching `TaskService.everCompleted`'s existing limitation rather than
   introducing a new one. C23's done condition ("none repeat") is therefore satisfied within a session
   and not across a rejoin. Both tables should migrate into the profile together at C40.

7. **C25 (quick chat wheel) is explicitly out of this plan** and nothing here lays groundwork for it.
   Noted because `QuickChatController.luau` and `RequestQuickChat` already exist, and the C23 teaching
   pass sits close enough to them that "while we're here" is available. It should be declined.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 4 | Rig streaming, `Model:ScaleTo` on an anchored rig, and CFrame motion legibility are unconfirmed Roblox behaviours | Medium | Open — playtester settles it |
| 4 | `TrialZone` attribute is a silent map contract in both directions; a missed attribute puts a live round objective in the trial corner | Medium | Open — mitigated by `discoverPool` filter, needs a playtest check |
| 6 | The transform cue's audience must match the `MonsterTransformed` broadcast exactly; `check:secrecy` structurally cannot verify it | High | Open — `exploit-auditor` on the finished diff |
| 3 | Mid-trial death/reset contends with `RoundService.watchForDeath` for the body | Medium | Resolved in plan — the session ends rather than contesting |
| 7 | `Debug.SoloTesting` drives the server out of IDLE, making the Solo Trial untestable while it is on | Low | Open — must be in the playtester's brief |
| 5 | A controller requiring a sibling controller is a new pattern in this codebase | Low | Accepted — justified in Step 5.3, bounded to one edge |
| 1 | §1.1's decision (round wins, trial aborts) is defensible but not the only defensible choice | Medium | Open — question 1 above, for a human |
