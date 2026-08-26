# Plan: V01 — Remove the Task Game

## 1. Plan Overview

- **Plan Type:** refactor
- **Milestone:** V01 (`docs/BUILD-PLAN.md` §3, Track V0 — demolition). Not an M-number; v2.0 renumbers.
- **Description:** Delete the v1.3 task system, the escape gate and the ghost system; strip their
  remotes, Config blocks, Types fields and Lune suites; leave the round cycling IDLE→ACTIVE→ENDING on
  the sunrise timer alone; and re-arm `check-scope.mjs`'s `ghosts?` word in the same diff.
- **Date:** 2026-08-26
- **What the client is told:** **Strictly less than today, and nothing new.** Three fields leave
  `ClientRoundSnapshot` — `TasksCompleted`, `TasksRequired`, `GateOpen` — and six remotes leave the
  wire (`TaskProgressChanged`, `TimingBarChanged`, `TaskListAssigned`, `GhostRoster`,
  `FirstObjectiveAssigned` down; `RequestTaskProgress`, `RequestTimingStop`, `ReportGhostPosition`,
  `RequestGhostSpook` up). Nothing is added. `RoleAssigned` and `RoundEnded` remain the only two
  allowlisted carriers of a role in `check-secrecy.mjs`, untouched by this plan.

---

### Read this before Phase 1 — the four constraints that govern every phase

These are repeated here rather than cross-referenced because each phase is loaded on its own via
`npm run plan:phase`, and a constraint stated only inside another phase does not exist for this one.

**(a) `WaitForChild` hangs forever, so the client is demolished BEFORE the wire.** `Remotes.Get(name)`
resolves through `folder:WaitForChild(name)` on the client. A name the server never creates does not
error — it hangs with no output and no stack trace (`.claude/scripts/check-remotes.mjs:9-13`). Phase 1
is therefore client-only and touches `Remotes.luau` not at all; `Remotes.luau` is edited in **Phase 4**,
after every client listener for those names is already gone. Declared-but-unused is reported by
`check:remotes` as a **NOTE, never a failure** (`check-remotes.mjs:142`), so the intermediate states
between Phase 1 and Phase 4 are green by design rather than by luck.

**(b) A dead player's state is renamed, not collapsed.** `PlayerState`'s `"GHOST"` member is a
string literal and the armed scope word `/^ghosts?$/i` matches string literals (comments are stripped,
strings are not — `check-scope.mjs:87-90`). So the member has to go. **It is renamed to `"DEAD"`, and
it must NOT be collapsed into `"SPECTATOR"`.** `BodyTransitions.actionFor` short-circuits `GHOST` to
`KEEP` *above* `mayHaveBody` (`src/shared/pure/BodyTransitions.luau:127-129`), and that short-circuit is
what keeps the corpse attached and `player.Character ~= nil` true for the dead set. `SPECTATOR` falls
through to `REVOKE` — which would destroy the corpse and make `Character == nil` enumerate exactly the
dead players, reintroducing the absence-is-observable leak two prior audits already found
(`BodyTransitions.luau:113-125`, `PlayerBody.luau:36-46`). **Phase 5 is a pure rename: every row's
behaviour is identical and the existing Lune suites are the proof.**

**(c) The round ends on the sunrise timer alone, and on nothing else.** After this chunk there are
exactly two routes into `ENDING`, both already in `RoundService`:
`step()` → `RoundTransitions.next` → `enterEnding(Enums.RoundResult.Timeout)` at
`src/server/Services/RoundService.luau:1073-1075`, and the two abort paths
`enterEnding(Enums.RoundResult.Aborted)` at `:967` and `:1226` when the roster falls below
`Config.Round.MinPlayers`. The two attrition routes (`RoundService.luau:1042-1048` and `:1349-1355`) and
the escape route (`GateService.luau:164`) are removed by this plan. `Types.RoundResult` keeps its
`SURVIVORS_ESCAPED` member — **V02 owns the v2.0 vocabulary**, and widening this chunk into `Enums`
churn would collide with it. The member simply becomes unreachable, which is stated in Follow Ups.

**(d) `git grep -i task src/` cannot literally return only `task.wait`.** The build plan's Done line
assumes the deletion clears every `task` token. It does not: `Stats.TasksDone` is a persisted profile
field, `BadgeRules.FirstTask` is an awarded badge id, and `TrialSnapshot.TrialTasksDone` /
`Config.Trial.TasksToComplete` belong to the Solo Trial. All four sit in the **business layer the build
plan lists as "Reworked" later**, and removing them here is a profile-schema migration and a badge-id
change — V4 work, not V01 work. So the Done criterion is implemented in **Step 5.7** as a grep with a
named deferral list rather than as a bare token count, and the deferral is recorded in Follow Ups.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The client stops asking

Client-only, purely subtractive, `Remotes.luau` untouched. When this phase ends, no LocalScript
listens for or fires any task/ghost remote, and no client reads a snapshot field this plan will later
remove — but every remote still exists on the wire, so nothing can hang.

#### Step 1.1: Delete `TaskController.luau` and `GhostController.luau`

**File:** `src/client/Controllers/TaskController.luau`
**Verify:** `npm run analyze`

`git rm src/client/Controllers/TaskController.luau src/client/Controllers/GhostController.luau`.

Between them they own every client-side listener for `TaskProgressChanged`, `TimingBarChanged`,
`TaskListAssigned` and `GhostRoster`, and the only client that fires `ReportGhostPosition` and
`RequestGhostSpook`. **Do Steps 1.2, 1.3 and 1.5 in the same phase** — `InputController.luau:34`,
`UIController.luau:72` and `init.client.luau:38,42` all name them, and `npm run analyze` stays red
until all three are done. That is the phase boundary doing its job: the tree is green at the end of
the phase, not after every keystroke inside it.

#### Step 1.2: Strip the task and timing binds out of `InputController`

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `grep -rL "TaskController" src/client/Controllers/InputController.luau`

```diff
-local TaskController = require(script.Parent.TaskController)
 local TrialController = require(script.Parent.TrialController)
 local UIController = require(script.Parent.UIController)
```

```diff
 local TRANSFORM_ACTION = "AswangTransform"
 local KILL_ACTION = "AswangKill"
-local TASK_ACTION = "TaskHold"
-local TIMING_ACTION = "TaskTimingStop"
 local THROW_ACTION = "SaltThrow"
```

Then delete, by range: `performAct` and `onTaskAction` (`:215-246`), `performTimingStop` and
`onTimingAction` (`:248-265`), and both `BindAction` calls with their comment blocks (`:361-375`).

```diff
 		Act = performAct,
 		Throw = function()
 			performThrow()
 		end,
-		TimingStop = performTimingStop,
 	})
```

`Act` goes with `performAct`, because `TaskController.SetHolding` was its entire body
(`InputController.luau:215-217`) — the hold verb has nothing left to hold. **`RequestSearch` in V03
takes this slot back**; leaving a `performAct` that calls nothing would be a stub V03 has to notice.

#### Step 1.3: Strip the task bar, the gate and the timing button out of `UIController`

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `grep -rL "TasksRequired" src/client/Controllers/UIController.luau`

```diff
-	C27 requires `TaskController` for one question — `IsTimingBarLive` — and the arrow points this way
-	on purpose. `TaskController` requires nothing from this file, so it cannot point back; the STOP
-	button needs to know whether there is a bar to stop, and the alternative (TaskController reaching
-	into this one) is the cycle.
-]]
-local TaskController = require(script.Parent.TaskController)
```

```diff
 local MOTION = {
-	-- Matches Config.Round.SnapshotInterval; see above. Not a literal, so not a config-ok case.
-	TaskBar = Config.Round.SnapshotInterval,
-
 	Colour = 0.25, -- config-ok: HUD motion, not balance
```

```diff
 	Survivor = Color3.fromRGB(136, 221, 255), -- config-ok: HUD palette
 	Ghost = Color3.fromRGB(170, 170, 255), -- config-ok: HUD palette
 	Progress = Color3.fromRGB(96, 220, 120), -- config-ok: HUD palette
-	GateOpen = Color3.fromRGB(255, 214, 92), -- config-ok: HUD palette
 	Panel = Color3.fromRGB(0, 0, 0), -- config-ok: HUD palette
```

Then delete, by range and each with its comment block: the `TimingStop` handler field (`:279-292`),
its dispatch (`:700`), the `barPanel` construction (`:842`ff), the ratio/fill/count render block
(`:1982-2013`), the `gate` half of the status format string (`:2046,2052-2053`), the `lastGateOpen`
local (`:360`) and its flash block (`:2073-2079`), the STOP touch button (`:2153`), and the
`lastGateOpen = nil` reset (`:2221`).

Two things **stay** and Phase 5 renames them, not this step: `COLOUR.Ghost` (`:223`) and the
`snapshot.YourState == Enums.PlayerState.Ghost` branches (`:1729`, `:2039`). `COLOUR.Progress` also
stays — V03's search bar is the next thing that needs a green fill, and the swatch is a colour rather
than a task.

`"SUNRISE — NOBODY FINISHED"` at `:995` returns `COLOUR.GateOpen`; retarget it to `COLOUR.Urgent`
rather than deleting the branch. `TIMEOUT` is now the **usual** way a round ends, not the sad one.

**Four player-facing copy strings in this file also name tasks** — `:974`, `:1750`, `:1753`, `:1770`.
They are handled in **Step 5.8** with the rest of the residue sweep, not here, because rewriting copy
is a different judgement from deleting a widget. This step's verify does not cover them.

#### Step 1.4: Reduce `OnboardingController` to `ShowLine`

**File:** `src/client/Controllers/OnboardingController.luau`
**Verify:** `grep -rL "FirstObjectiveAssigned" src/client/Controllers/OnboardingController.luau`

**Do not delete this controller.** `TrialController` requires it directly for `ShowLine`
(`init.client.luau:50-54`), so deleting it takes the Solo Trial's copy layer with it, and the Solo
Trial survives V01 untouched.

Delete `TAG_POINT` / `TAG_DONE` (`:47-48`), `findPoint` (`:96`), `clearObjective` (`:106`),
`showMarker` (`:225`), `watch` (`:262`), the streaming-retry listener local (`:91-95`) and the
`FirstObjectiveAssigned` connection in `Start` (`:320`). Keep `ensureHint` (`:131`) and `ShowLine`
(`:182`) exactly as they are — they are the whole of what `TrialController` uses.

`Config.Tasks.PresenceRangeStuds` at `:307` leaves with `watch`. That matters for Phase 4: it is one of
the two surviving readers of `Config.Tasks` outside the doomed files.

#### Step 1.5: Drop the two controllers from the client bootstrap

**File:** `src/client/init.client.luau`
**Verify:** `grep -rL "GhostController" src/client/init.client.luau`

```diff
 	"UIController",
 	"QuickChatController",
-	-- Before InputController, deliberately. The order governs Init/Start rather than requires — the
-	-- require is direct — but InputController.Start binds a key that calls into this controller, and a
-	-- bind that can fire before Init has run is a race worth not having.
-	"TaskController",
-	-- C15. Owns the ghost's LOCAL body — ghosts have no server character, because a replicated body
-	-- per dead player named the dead set to every client. Before InputController for the same reason
-	-- TaskController is: it reacts to snapshots and should be listening before any bind can fire.
-	"GhostController",
 	--[[
-		C20. After TaskController, because both react to the same `TaskPoint` tags and the objective
-		marker should sit on top of the affordance TaskController draws rather than race it. Before
-		InputController for the same reason everything else here is: it listens for a remote that can
-		arrive the instant the round goes ACTIVE.
+		C21/V01. Before InputController for the same reason everything else here is, and it now exists
+		only for `ShowLine` — the objective waypoint went with the task system (V01).
 	]]
 	"OnboardingController",
```

The debug snapshot printer at `:124-142` still reads `GateOpen`, `TasksCompleted` and `TasksRequired`.
Leave it for **Step 3.5**: those fields are still on `ClientRoundSnapshot` until Phase 3, and editing it
here would be editing it twice.

#### Step 1.6: Remove the gate cue from `AudioController`

**File:** `src/client/Controllers/AudioController.luau`
**Verify:** `grep -rL "onGateChanged" src/client/Controllers/AudioController.luau`

**This is the client task/gate reader that is easiest to miss**, because it is neither a HUD element nor
a remote listener — it is an edge detector on a snapshot field, sitting inside an audio controller
(`:553-566` for the rationale block, `:568` for `gateWasOpen`, `:570`ff for `onGateChanged`, `:660` for
the call in `onSnapshot`).

Delete the rationale block, the `gateWasOpen` local, `onGateChanged` and its call site, and any
`AudioCues` id it plays that no other cue path uses. Leave `onSunriseProgress(snapshot)` at `:661`
alone — the sunrise clock is the round, and after this chunk it is the **only** thing the round is.

```diff
 	onGateChanged(snapshot.GateOpen)
 	onSunriseProgress(snapshot)
 end
```

becomes

```diff
 	onSunriseProgress(snapshot)
 end
```

The header comment at `:67` lists `snapshot.GateOpen` among this controller's inputs; drop it from that
list. `:150`'s reference to "GateService's untagged-gate warn is the precedent" is a comment about a
file that is about to not exist — reword it to name the rule (faults are ungated) rather than the file.

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

- **Remote direction — the mid-phase state is the point.** After Step 1.1 the server still fires
  `TaskProgressChanged`, `TimingBarChanged`, `TaskListAssigned`, `GhostRoster` and
  `FirstObjectiveAssigned` at clients that no longer listen. That is not a leak and not a hang: a
  `FireClient` with no `OnClientEvent` connection is a discarded packet. `check:remotes` reports the
  now-unused UP remotes as a **NOTE** (`check-remotes.mjs:142-145`), not a failure. Do not "fix" it by
  reaching into `Remotes.luau` — that is Phase 4, and doing it here is exactly the hang in constraint (a).
- **Player leaving mid-round (§6.4).** Untouched by this phase. Every death, husk and rejoin decision
  is server-side; this phase deletes presentation only.
- **Mobile budget (§5).** Improves. The STOP touch button, the objective billboard and the ghost body
  are all per-frame client work that stops existing. Nothing is added.
- **Secret leakage.** Strictly reduced: `GhostController` is the client half of `GhostRoster`, the
  remote whose safety came from its audience rather than its payload (`Remotes.luau:64-76`). With no
  client listener the audience question has one fewer place to go wrong.
- **Strict Luau.** Removing `TimingStop` from the handlers table type (`:292`) and from the call site
  must happen together; a table literal missing a declared field is caught, an extra one is not
  (`Types.luau:97-100` records that asymmetry).

---

### Phase 2: The server stops answering

Deletes the three services and every pure module that only they used, with one survivor that must be
renamed rather than deleted. `RoundService`, `Types`, `Config` and `Remotes.luau` are untouched here.

#### Step 2.1: Rename `server/pure/TaskPool.luau` to `SearchPool.luau`

**File:** `src/server/pure/SearchPool.luau`
**Verify:** `lune run tests/search-pool.test.luau`

**This module is not deletable and the build plan's delete list is wrong about it.** `ItemService`
requires it and calls it (`ItemService.luau:34, 62, 92, 134`) — the pouch-pool verdict is the *same*
"is this map's tagged pool usable" rule, shared rather than copied, and `ItemService` survives V01 to
become V03's container service. Deleting it would either break `ItemService` or produce a second copy
of an algorithm this repo deliberately keeps single (`TaskPool.luau:22`, `ItemService.luau:22`).

`git mv src/server/pure/TaskPool.luau src/server/pure/SearchPool.luau` and
`git mv tests/task-pool.test.luau tests/search-pool.test.luau`, then rename the identifier throughout:

```diff
 --!strict
 --[[
-	TaskPool — is this map's TaskPoint pool usable, and which names are actually distinct? (C07)
+	SearchPool — is this map's tagged pool usable, and which names are actually distinct? (C07, V01)
 
 		(names, required, expected) -> report
```

```diff
-function TaskPool.evaluate(names: { string }, required: number, expected: number): Report
+function SearchPool.evaluate(names: { string }, required: number, expected: number): Report
```

The header's "WHY `src/server/pure/` AND NOT `src/shared/pure/`" paragraph (`:16-26`) argues from
`TaskSelection` and `TaskService`, both of which this plan deletes. Rewrite it to argue from the
**inputs** — the pool contents are map facts the client has no use for — which is the half of the
argument that survives. The `Types.TaskPoolVerdict` sentence in it becomes `Types.SearchPoolVerdict`.

In the test file, `require("../src/server/pure/TaskPool")` becomes
`require("../src/server/pure/SearchPool")`, and the PASS line at `:116` becomes
`` `  PASS  search-pool: {checked} assertions across the pool set` `` — keeping `{checked}`
interpolated, because a bare digit there is exactly what `check:testcount` refuses. Line `:49`'s
comment cites "the gate's requirement"; reword to "the round's requirement". **Change no assertion.**
The suite passing unchanged is the proof that this is a rename and not a rewrite.

#### Step 2.2: Point `ItemService` and `Types` at the renamed module

**File:** `src/server/Services/ItemService.luau`
**Verify:** `grep -rL "TaskPool" src/server/Services/ItemService.luau`

```diff
-local TaskPool = require(script.Parent.Parent.pure.TaskPool)
+local SearchPool = require(script.Parent.Parent.pure.SearchPool)
```

```diff
-local function discoverPool(): TaskPool.Report
+local function discoverPool(): SearchPool.Report
```

```diff
-	return TaskPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize)
+	return SearchPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize)
```

```diff
-function ItemService.EvaluatePool(): TaskPool.Report
+function ItemService.EvaluatePool(): SearchPool.Report
```

And in `Types.luau`:

```diff
 --[[
-	The verdict from `server/pure/TaskPool.luau` (C07) — is the map's TaskPoint pool usable.
+	The verdict from `server/pure/SearchPool.luau` (C07, V01) — is the map's tagged pool usable.
```

```diff
-export type TaskPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"
+export type SearchPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"
```

`ItemService`'s remaining comment references to `TaskService` (`:16, 22, 49, 78, 88, 96, 177`) are prose
about a file that will no longer exist. Reword each to name the rule rather than the dead file — e.g.
`:177`'s seed warning becomes "`Random.new(os.time())` is client-observable to the second", which is
the whole content of it. They are comments, so `check:scope` never sees them, but Step 5.8's `task`
sweep does.

#### Step 2.3: Delete `TaskService`, `GateService` and `GhostService`, and unregister them

**File:** `src/server/init.server.luau`
**Verify:** `grep -rL "GhostService" src/server/init.server.luau`

The deletion and the bootstrap edit are **one step deliberately**. `init.server.luau` resolves services
by `servicesFolder:FindFirstChild(name)` and merely `warn`s on a miss (`:80-84`), so a stale name is
invisible to `analyze` and to every check — it costs one warn line at startup and nothing else. Binding
the two together is what makes the miss impossible.

```diff
 	"RoleService",
-	"TaskService",
-	"GateService",
 	"MonsterService",
 	"ItemService",
-	"GhostService",
 	"TrialService",
 	--[[
-		C23. After the four services that CALL it — ItemService, GhostService, MonsterService and
-		TaskService — because those hold a module reference from their own `require` at load, and this
-		list only governs Init/Start. It is placed here so `Start` has run before any gameplay can
-		produce a cue, not because the require needs it.
+		C23/V01. After the two services that still CALL it — ItemService and MonsterService — because
+		those hold a module reference from their own `require` at load, and this list only governs
+		Init/Start. It is placed here so `Start` has run before any gameplay can produce a cue.
 	]]
 	"TeachingService",
```

The final `log()` counts `#SERVICE_ORDER`, so "Ready. N services loaded." moves on its own. Then
`git rm` all three (1806 + 213 + 763 lines). Everything they own goes with them: the task draw and
heartbeat, the escape-gate poll and its `EndRound(SurvivorsEscaped)` at `GateService.luau:164`, the
ghost body, the spook, the ghost roster push, and the `FirstObjectiveAssigned` fire at
`TaskService.luau:1666`.

Two `TeachingService.Cue` call sites die with them — `"CUE_FIRST_TWO_PERSON"`
(`TaskService.luau:1171`) and `"CUE_FIRST_GHOST_DEATH"` (`GhostService.luau:485`). The cue **ids**
survive in `Types.TeachingCueId` until Step 5.6; nothing breaks in between, because an id nobody fires
is still a valid member of a union.

`ProgressionService.BumpStat(player, "TasksDone", 1)` dies here too (`TaskService.luau:1095, 1448`).
`Stats.TasksDone` and the `BadgeRules.FirstTask` badge that reads it **stay** — see constraint (d).
After this step `TasksDone` is a stat nothing increments, which is a V4 problem stated in Follow Ups
rather than a V01 one.

#### Step 2.4: Delete the task and gate pure modules

**File:** `src/server/pure/TaskWeight.luau`
**Verify:** `npm run analyze`

`git rm` eight files from `src/server/pure/`: `TaskWeight.luau`, `TaskListView.luau`,
`TaskParticipants.luau`, `TaskProgress.luau`, `TaskResolve.luau`, `TimingWindow.luau`,
`FetchCarry.luau`, `GateEscape.luau`.

**The build plan lists `src/shared/pure/TaskWeight.luau`; there is no such file.** It is at
`src/server/pure/TaskWeight.luau` and always was — its own header explains the placement
(`TaskWeight.luau:3-8`), and `TaskPool.luau:16` contrasts the two directories deliberately. Deleting
the shared-path file is a no-op that would leave the real one standing.

`FetchCarry` and `TimingWindow` were flagged as uncertain in the brief. Both are task mechanics and both
go: `FetchCarry.decide` is the FETCH task's carry rule and takes `Config.Tasks.FullContributionWeight`
as a parameter (`FetchCarry.luau:17-19`); `TimingWindow` is the TIMING task's bar, and its header states
that `TaskService` computes its only time input (`TimingWindow.luau:15-16`). Neither has a caller
outside the three deleted services.

#### Step 2.5: Delete `TaskSelection` and `SpookBudget` from `src/shared/pure/`

**File:** `src/shared/pure/TaskSelection.luau`
**Verify:** `npm run check:config`

`git rm src/shared/pure/TaskSelection.luau src/shared/pure/SpookBudget.luau`.

`GhostChat.luau` is **not** deleted here despite being on the build plan's list — `QuickChatService`
requires it at `:68` and calls `shouldDeliver` at `:335-337`, and that call is the audience filter that
keeps a dead player's accusation away from the living. Deleting it silently widens that audience.
Step 5.1 renames it to `ChatAudience.luau` instead.

`check:config` is the verify here because `TaskSelection` and `SpookBudget` are the two deleted modules
that read tunables through parameters rather than through `Config` directly; the check proves nothing
new was inlined on the way out.

#### Step 2.6: Delete the ten orphaned Lune suites

**File:** `tests/task-selection.test.luau`
**Verify:** `npm run test:unit`

`git rm` exactly these ten:

`tests/task-selection.test.luau`, `task-weight.test.luau`, `task-list-view.test.luau`,
`task-participants.test.luau`, `task-progress.test.luau`, `task-resolve.test.luau`,
`timing-window.test.luau`, `fetch-carry.test.luau`, `gate-escape.test.luau`,
`spook-budget.test.luau`.

Not deleted, and each for its own reason: `task-pool` was renamed in Step 2.1; `ghost-chat` is renamed
in Step 5.1; `win-conditions` is emptied to a skeleton in Step 3.3. That is the whole of the brief's
candidate list, resolved.

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

- **Phase ownership.** `GateService.luau:188` subscribes to `RoundService.PhaseChanged`; deleting the
  service removes a subscriber, never a writer. Confirm after this phase that `setPhase` still has
  exactly one caller and it is `RoundService` itself — the spec makes that §6.4's rule and this is the
  phase most likely to disturb it by accident.
- **Player leaving mid-round (§6.4).** `TaskService` held per-player presence state keyed by UserId; it
  goes with the file. `GhostService` held ghost bodies keyed by UserId; likewise. Neither leaves a
  `Players.PlayerRemoving` connection behind, because both connected from inside their own module.
  **Verify no `PlayerRemoving` handler in a surviving service refers to a deleted service's state.**
- **Rate limiting.** Three `OnServerEvent` handlers disappear (`RequestTaskProgress`,
  `RequestTimingStop` in `TaskService`; `ReportGhostPosition`, `RequestGhostSpook` in `GhostService`).
  `AntiCheatService` keeps its budgets for them until Step 4.3 — a budget for a remote nobody handles is
  inert, and `tests/anti-cheat-budgets.test.luau` pins **both** directions (`Config.luau:1039-1041`), so
  the two must be removed together in Phase 4 and not split.
- **Secret leakage.** `TaskListView.forPlayer` was the one module in the repo that deliberately told the
  Aswang a lie (`TaskListView.luau:15`). Deleting it removes a *role-branching* code path, which is a
  strict reduction in surface. Nothing in this phase adds a branch on role.
- **Magic numbers.** `TaskPool.evaluate`'s parameters come from `Config.Salt.SpawnCount` and
  `Config.Salt.PouchPoolSize` at the `ItemService` call site (`:92`). The rename must not inline either;
  `check:config` in Step 2.5 is the guard on that.
- **Scope.** `SpookBudget` and `GhostChat` are the two ghost-named modules in `src/shared/pure/` and only
  one of them is deleted here. That asymmetry is deliberate and Step 2.5 states why.

---

### Phase 3: The round ends on sunrise alone

The one phase where this chunk removes a *decision* rather than a feature. `RoundService` loses the
attrition rule and the gate; `Types` loses the fields that described them.

#### Step 3.1: Remove the attrition win from `RoundService`

**File:** `src/server/Services/RoundService.luau`
**Verify:** `grep -rL "WinConditions" src/server/Services/RoundService.luau`

**This is the decision this chunk removes, and it is the one thing V01 changes rather than deletes.**
v1.3's Aswang won at `AswangKills >= DealtInSurvivors - 2`. v2.0's Aswang wins by killing **everyone**
(spec, "the five structural changes"), and that rule arrives at V11. Between here and there the Aswang
has **no win condition at all** — the round runs to sunrise. That is deliberate, it is what makes V01
verifiable in Studio ("the round still cycles with nothing to do in it"), and it must be stated in the
implementation log rather than discovered by a playtester.

```diff
 local RoundTransitions = require(Shared.pure.RoundTransitions)
 local Types = require(Shared.Types)
-local WinConditions = require(Shared.pure.WinConditions)
```

Delete both call sites verbatim — `:1041-1049` in `MarkKilled` and `:1348-1356` in the husk-kill path —
along with the comment blocks that argue for them (`:1017-1040` and `:1341-1347`). Those comments are a
four-attempt history of a rule that no longer exists; the history worth keeping is in
`tests/win-conditions.test.luau`, which Step 3.3 preserves for exactly that reason.

**Keep `state.AswangKills`, `state.DealtInSurvivors` and `RoundService.GetAswangKills()`.**
`ProgressionService.luau:857` reads `GetAswangKills()` to price the round's XP award, and the business
layer survives V01 untouched. `DealtInSurvivors` keeps its writer at `:818` and its reset at `:752`;
V11's kill-everyone rule needs exactly that number, so deleting it now buys nothing and costs V11 a
re-derivation.

**After this step, exactly three calls can reach `enterEnding`, and this is the list:**

| Route | Site | Result |
| --- | --- | --- |
| The sunrise timer expiring | `RoundService.luau:1073-1075` (via `RoundTransitions.next`) | `TIMEOUT` |
| Roster falls below `MinPlayers` during a round | `RoundService.luau:967` | `ABORTED` |
| Roster falls below `MinPlayers` on a leave | `RoundService.luau:1226` | `ABORTED` |

`RoundService.EndRound` (`:893`) survives as public API with **no caller left in the tree** — V03's
kill path and V11's win rule are its future callers. Leave it; a public function with no caller is not
dead code in a repo mid-transplant, and deleting it would make V11 re-derive its ACTIVE guard.

#### Step 3.2: Remove the task counter and the gate from `RoundService`

**File:** `src/server/Services/RoundService.luau`
**Verify:** `grep -rL "GateOpen" src/server/Services/RoundService.luau`

```diff
 	RoundNumber = 0,
 	AswangUserId = nil :: number?,
-	TasksCompleted = 0,
-	GateOpen = false,
 	-- How many SURVIVORS were dealt into this round, snapshotted at STARTING. A snapshot rather than a
 	-- live count on purpose: see enterStarting.
```

```diff
-- §4.8, C11. Read by GateService, which never writes it — the gate is derived in one place, from the
--- task count and the phase. See `SetTasksCompleted`, which moved below `broadcastSnapshot` for C11.
-function RoundService.IsGateOpen(): boolean
-	return state.GateOpen
-end
```

```diff
 	return {
 		Phase = state.Phase,
 		SecondsRemaining = RoundService.GetSecondsRemaining(),
 		RoundNumber = state.RoundNumber,
-		TasksCompleted = state.TasksCompleted,
-		TasksRequired = Config.Tasks.TotalRequired,
-		GateOpen = state.GateOpen,
 		YourState = RoundService.GetPlayerState(player),
 	}
```

```diff
 local function enterIdle()
 	state.AswangUserId = nil
-	state.TasksCompleted = 0
-	state.GateOpen = false
 	state.DealtInSurvivors = 0
 	state.AswangKills = 0
```

```diff
 local function enterIntermission()
 	RoleService.ClearRoles()
-	-- Belt and braces. `clearTasks` closes the gate via SetTasksCompleted(0) on this same transition,
-	-- but that depends on TaskService being loaded and subscribed. A lobby showing an open gate from
-	-- last round is a lie the HUD tells before anybody can act on it, so this service closes it too.
-	RoundService.SetTasksCompleted(0)
```

Then delete `RoundService.SetTasksCompleted` entirely with its 30-line header (`:653-712`), and the two
stale TODOs and the task-draw note at `:741-745`.

**One behaviour genuinely changes and it must be checked in Studio.** `SetTasksCompleted` was the only
caller of `broadcastSnapshot()` outside the `SnapshotInterval` tick and `MarkKilled`. Removing it means
the HUD now refreshes on the 0.5s cadence and on a death, which is the design (`:701-705` explains the
off-cadence push existed for the gate-opening moment, and there is no gate). Nothing else called it.

#### Step 3.3: Delete `WinConditions.luau` and empty its suite to a skeleton

**File:** `tests/win-conditions.test.luau`
**Verify:** `lune run tests/win-conditions.test.luau`

`git rm src/shared/pure/WinConditions.luau`. **Keep `tests/win-conditions.test.luau` and empty it**, per
the build plan: the grid-first discipline that file encodes is why the attrition rule eventually came
out right, and V11 rewrites both halves.

The skeleton must be green under `npm run test:unit` with no module to require. Three constraints
decide its shape, and all three are mechanical:

1. **No `require`.** The module is gone; Lune resolves by file path and would error.
2. **Exit 0.** `run-luau-tests.mjs:38-42` treats a non-zero Lune exit as the entire failure protocol.
3. **No bare digit in the PASS line.** `check-testcount.mjs` refuses a digit outside a `{...}`
   interpolation, and that check runs inside `npm run verify`.

```luau
--!strict
--[[
	WinConditions — DELIBERATELY EMPTY UNTIL V11 (§4.8, V01).

	v1.3's attrition rule (`AswangKills >= DealtInSurvivors - 2`) and the module behind it were deleted
	at V01. v2.0's Aswang wins by killing EVERYONE, and V11 writes that rule and refills this file.

	WHY THIS FILE SURVIVED THE MODULE IT TESTED. The rule it used to pin took FOUR attempts, and the
	first three each passed a suite written from the bug just seen:

	  1. freeze DealtInSurvivors at STARTING   — livingSurvivorCount() was LIVE, so a disconnect moved
	                                             one side of the comparison and not the other
	  2. decrement it on a non-kill death      — closed reset-then-reset and nothing else
	  3. decrement it on disconnect too        — ARITHMETICALLY INERT above four survivors

	What finally worked was not a better expression. It was ENUMERATING the space — roster × kills ×
	resets × disconnects — instead of sampling it. V11's win condition has the same shape and the same
	four dimensions, so it earns the same treatment, and the habit is easier to keep than to rediscover.

	V11: restore `local WinConditions = require("../src/shared/pure/WinConditions")`, fill CASES, and
	delete this note.
]]

local checked = 0

-- The grid goes here. `checked` is incremented by the assertions V11 adds, and the PASS line below
-- interpolates it rather than stating a number — see `.claude/scripts/check-testcount.mjs` for why a
-- literal tally in a summary line is structurally incapable of noticing a deleted assertion.

print(`  PASS  win-conditions: {checked} assertions — skeleton, awaiting V11's rule`)
```

`selene` runs over `src` only (`package.json:13`), so an unused-looking local in `tests/` is not linted;
`stylua` runs over `src tests` (`:14-15`), so this file must be formatted. It is currently green as
written.

#### Step 3.4: Trim the round contract in `Types.luau`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

**`ClientRoundSnapshot` is the network contract and this narrows it. Three fields leave and none
arrive.** `analyze` is the verify because it is the only check that can prove no reader was missed:
a snapshot consumer still indexing `TasksRequired` is a type error the moment the field is gone.

**`RoundState.Tasks` has no implementation and never did.** `RoundService`'s `state` is an inferred
table literal, not annotated `: Types.RoundState` (`RoundService.luau:49`), and it has no `Tasks` key.
The type has been describing a field nothing holds. Deleting it costs nothing; it is recorded in Follow
Ups because a type that is never applied to its own state is a gap V02 should close deliberately.

```diff
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
 	Phase: RoundPhase,
 	PhaseEndsAt: number, -- os.clock() timestamp
 	RoundNumber: number,
 	AswangUserId: number?, -- THE SECRET
-	Tasks: { ActiveTask },
-	TasksCompleted: number,
 	PlayerStates: { [number]: PlayerState }, -- keyed by UserId
-	GateOpen: boolean,
 }
 
 -- What the client is allowed to know. Note the absence of AswangUserId.
 export type ClientRoundSnapshot = {
 	Phase: RoundPhase,
 	SecondsRemaining: number,
 	RoundNumber: number,
-	TasksCompleted: number,
-	TasksRequired: number,
-	GateOpen: boolean,
 	YourRole: Role?, -- only ever the receiving player's OWN role
 	YourState: PlayerState,
 }
```

**Keep the `AlivePlayerCount` block that follows at `:583`+ verbatim.** Amendment A3 survives v2.0
intact (spec, "What did NOT change"), §4.7 restates it, and that comment is the only place the
position-correlation attack is written down. It reads "sat between GateOpen and YourRole"; change that
phrase to "sat between RoundNumber and YourRole" so it still describes a real adjacency, and change
nothing else in it.

Then delete these type declarations with their headers, all of which now have no producer and no
consumer: `TaskType` (`:14`), `ActiveTask` (`:84-90`), `TaskProgressVerdict` (`:273`),
`TaskProgressPayload` (`:305-309`), `TimingVerdict` (`:326`), `TimingBarPayload` (`:357`),
`TaskListPayload` (`:381-383`), `FetchAction` (`:398`), `GhostRosterPayload` (`:466-468`),
`SpookVerdict` (`:479-485`).

`PlayerStats.TasksDone` (`:23`) **stays** — constraint (d). `TrialTasksDone` / `TrialTasksRequired`
(`:664-665`) **stay**: they belong to `TrialSnapshot` and the Solo Trial is untouched by V01.

#### Step 3.5: Drop `Enums.TaskType`

**File:** `src/shared/Enums.luau`
**Verify:** `grep -rL "TaskType" src/shared/Enums.luau`

`Enums.TaskType` is the last thing in the tree that names the four v1.3 task verbs. It is deleted here
rather than in V02 because its literal-type casts point at `Types.TaskType`, which Step 3.4 removed —
leaving it would be an `Enums` entry casting to a type that does not exist.

```diff
-Enums.TaskType = table.freeze({
-	Hold = "HOLD" :: Types.TaskType,
-	Timing = "TIMING" :: Types.TaskType,
-	Fetch = "FETCH" :: Types.TaskType,
-	TwoPerson = "TWO_PERSON" :: Types.TaskType,
-})
```

#### Step 3.6: Strip the task and gate fields out of the client's debug printer

**File:** `src/client/init.client.luau`
**Verify:** `grep -rL "TasksRequired" src/client/init.client.luau`

```diff
 Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
 	if not Config.Debug.VerboseLogging then
 		return
 	end
 
-	local gate = if snapshot.GateOpen then "OPEN" else "shut"
-	local tasks = `{snapshot.TasksCompleted}/{snapshot.TasksRequired}`
 	-- No alive count. Amendment A3 removed the field; see the comment in Types.ClientRoundSnapshot for
 	-- the names it must not come back under.
-	local line = `{snapshot.Phase} round #{snapshot.RoundNumber} · tasks {tasks} · gate {gate}`
-		.. ` · you: {snapshot.YourState}`
+	local line = `{snapshot.Phase} round #{snapshot.RoundNumber} · you: {snapshot.YourState}`
```

The Amendment A3 comment stays exactly where it is. It is the reason this printer is allowed to exist at
all, and a debug line is precisely where an alive count gets added back by someone who means well.

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

- **Secret leakage — this phase narrows the wire, and the narrowing is the safe direction.** Nothing is
  added to `ClientRoundSnapshot`. Re-read `Types.luau:583`+ after editing and confirm the
  `AlivePlayerCount` block is intact: it is the only written record of the position-correlation attack,
  Amendment A3 survives v2.0 (spec §4.7), and a snapshot with three fewer fields is a snapshot somebody
  will be tempted to "balance out".
- **Phase ownership — the risk peaks here.** `SetTasksCompleted`'s header (`:663-666`) argues at length
  that a *count* is data and not a phase, and that `setPhase` stays private. Deleting the function must
  not disturb that boundary. After this phase, `setPhase` should still have exactly one definition and
  every call to it should be inside `RoundService`.
- **Player leaving mid-round (§6.4) — two of the five edge cases change meaning.** "A survivor leaves
  mid-round" and "the Aswang leaves mid-round" both used to interact with the attrition rule; now they
  interact only with `eligiblePlayerCount()` and the `ABORTED` paths at `:967` and `:1226`. Trace both
  paths after Step 3.1 and confirm neither reads `AswangKills` any more.
- **Strict Luau.** Removing a member from a literal union (`TaskType`) while an `Enums` entry still
  casts to it is an error; Step 3.5 pairs them for that reason. Separately, narrowing a literal union by
  exclusion widens the remainder to plain `string` — `RejoinResolve.luau:108-110` records the bite, and
  Phase 5 walks into it again.
- **Magic numbers.** `buildSnapshot` loses its only `Config.Tasks` read (`:641`). That leaves
  `TrialService` and nothing else, which is what makes Step 4.1 a two-line change instead of a sweep.
- **Unverifiable by any check, and it is the phase's real deliverable:** that a round still reaches
  `ENDING`. `RoundTransitions` is pure and `tests/round-transitions.test.luau` already pins the IDLE →
  INTERMISSION → STARTING → ACTIVE → ENDING walk, so the *transition table* is proven — but that the
  live service still drives it is a Studio question. This is what the playtester's artifact is for.

---

### Phase 4: Config, the wire, and the budgets

The wire is cut last, when nothing on either side is listening. `Config.Tasks` and `Config.Ghost` go,
which breaks eleven balance invariants that must be removed in the same phase.

#### Step 4.1: Rehome the Solo Trial's two borrowed numbers

**File:** `src/server/Services/TrialService.luau`
**Verify:** `grep -rL "Config.Tasks" src/server/Services/TrialService.luau`

`TrialService` is the **last reader of `Config.Tasks` outside the deleted files**, and it borrows two
numbers deliberately: a tutorial that teaches an eight-second hold and then hands the player a
six-second one has taught the wrong thing (`TrialService.luau:353-357`). The Solo Trial survives V01
untouched, so the numbers move rather than die.

```diff
 	Trial = {
 		Enabled = true,
 		Duration = 90,
 		TasksToComplete = 2,
+		-- V01. Was `Config.Tasks.PresenceRangeStuds` / `HoldTime`, which the round's task system owned
+		-- until V01 deleted it. The trial kept the VALUES because its own header's argument is about
+		-- teaching a consistent hold — and from V03 the thing it must stay consistent with is the
+		-- container search, so revisit both when `Config.Search` lands.
+		PresenceRangeStuds = 9,
+		HoldTime = 8,
 		ScriptedChaseAt = 55, -- seconds in: the Aswang reveals itself
```

```diff
-		if distance <= Config.Tasks.PresenceRangeStuds and distance < nearestDistance then
+		if distance <= Config.Trial.PresenceRangeStuds and distance < nearestDistance then
```

```diff
-	if session.HeldFor < Config.Tasks.HoldTime then
+	if session.HeldFor < Config.Trial.HoldTime then
```

And reword the header block at `:353-357` so it no longer cites a deleted Config block.

**Do this step before Step 4.2, in this order.** Deleting `Config.Tasks` first leaves `TrialService`
indexing a nil field — which under `--!strict` is an analyze error, so the tree is red between the two
edits either way, but this order keeps the red confined to one step instead of two.

#### Step 4.2: Delete `Config.Tasks`, `Config.Ghost` and the orphaned attrition threshold

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:config`

Delete `Config.Tasks` in full (`:110-279`) and `Config.Ghost` in full (`:333-375`).

Also delete `Config.Round.AswangWinSurvivorThreshold` (`:31`). Its only reader was
`RoundService.luau:1045`, which Step 3.1 removed, so after Phase 3 it is a tunable nothing reads. v2.0's
Aswang wins by killing everyone, so V11 will not want a threshold either — leaving it is precisely the
tree describing a game that no longer exists.

`check:config` is the verify because the failure mode of this step is **inlining**: a number that was in
`Config.Tasks` reappearing as a literal somewhere it was read. The check catches exactly that, and it
would catch it in `TrialService` if Step 4.1 had pasted `9` and `8` into the service instead of into
`Config`.

#### Step 4.3: Delete the four dead rate-limit budgets

**File:** `src/shared/Config.luau`
**Verify:** `npm run check:ratelimit`

```diff
 		Budgets = {
-			-- A presence heartbeat while standing at a task point. Must out-pace the snapshot tick or
-			-- a player holding a task is throttled while doing exactly what the game asked of them.
-			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },
-			RequestTimingStop = { Capacity = 5, RefillPerSecond = 1 },
 			-- Deliberate, rare acts. Capacity covers a double-tap and a reconnect retry; nothing more.
 			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
 			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
 			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
 			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
-			ReportGhostPosition = { Capacity = 10, RefillPerSecond = 5 },
-			RequestGhostSpook = { Capacity = 2, RefillPerSecond = 0.05 },
 			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
```

(delete `RequestTimingStop`'s 12-line comment block at `:1046-1057` and `ReportGhostPosition`'s at
`:1065-1067` with them.)

**This step and Step 4.4 are a matched pair and must both land before `verify` is run.** The table's own
header says the test pins **both** directions — "a budget for a remote that no longer exists is a rename
nobody noticed and a remote with no budget is refused outright" (`Config.luau:1038-1039`). Removing a
budget without its remote fails; removing a remote without its budget fails.

#### Step 4.4: Remove the nine remotes from `Remotes.luau`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

**This is the wire, and it is cut last for the reason in constraint (a).** By now no client listens for
or fires any of these, so no `WaitForChild` can be left hanging on a name the server stops creating.

From `EVENTS_DOWN`: `"TaskProgressChanged"` (`:25`), `"TimingBarChanged"` (`:26-29` with its comment),
`"TaskListAssigned"` (`:30-34` with its comment), `"GhostRoster"` (`:64-76` with its comment block),
`"FirstObjectiveAssigned"` (`:77-108` with its comment block).

From `EVENTS_UP`: `"RequestTaskProgress"` (`:139`), `"RequestTimingStop"` (`:140-143` with its comment),
`"ReportGhostPosition"` (`:148-165` with its comment block), `"RequestGhostSpook"` (`:166`).

**Keep `"TeachingCue"` (`:126-134`) and reword its comment.** It cites `FirstObjectiveAssigned` as "the
generalisation of the entry directly above" and lists "a ghost death" among its triggers; both
references are about to be false. `TeachingService` survives, so the remote survives — the argument it
inherits (*what it reveals is that the RECEIVER is new; it names nobody else*) has to be restated in
full rather than pointed at a deleted neighbour.

`Config.Tasks.MarkerVisibleStuds` is cited at `:86` inside the `FirstObjectiveAssigned` block, which
goes with it. That is the last mention of `Config.Tasks` anywhere in `src/`.

#### Step 4.5: Remove the nineteen dead invariants from `tests/config.test.luau`

**File:** `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

`Config.Tasks` and `Config.Ghost` are referenced by **nineteen** `check(...)` blocks. The complete
inventory, with line ranges as they stand today, is in
`references/config-test-invariant-inventory.md` — do not re-derive it.

Delete these, each with its leading comment block:

| Lines | Invariant |
| --- | --- |
| 37-41 | "there are more task locations than tasks required" |
| 90-94 | "ghosts contribute, but less than the living" |
| 128-133 | "a pouch is picked up closer than a task is held" |
| 137-141 | "the ghost roster is not pushed faster than the snapshot" |
| 145-149 | "a ghost gets at least one spook" |
| 159-163 | "a spook lasts long enough to notice and not longer than the reveal" |
| 182-188 | "a spook does not point at the ghost that caused it" |
| 293-299 | "the attrition win is reachable but not free on a full server" |
| 320-324 | "selected task points are spread further apart than the Aswang can reach" |
| 350-354 | "a player can only ever be present at one task point at a time" |
| 358-362 | "a continuously held task never lapses between heartbeats" |
| 370-376 | "a holding client stays inside its own rate-limit budget" |
| 382-387 | "the timing green zone sits inside the bar" |
| 399-406 | "the timing grace widens the zone rather than replacing it" |
| 410-414 | "the fetch deliver hold is a small part of the errand" |
| 423-429 | "a ghost is not a two-person participant" |
| 436-440 | "the escape gate stays inside the Aswang's reach" |
| 488-492 | "the trial's two tasks can actually be drawn" |
| 555-560 | "the accusation is not a map-scale radar" |

Two of them are **losses worth recording rather than deletions worth forgetting**, and both go in Follow
Ups: `128-133` was the only thing pinning salt's pickup radius against anything, and `555-560` was the
only thing pinning the quick-chat accusation radius against a map-scale distance. V03 must give both a
new right-hand side when the container search range lands. `293-299` is a third: it pinned that a
full-server round was winnable at all, and V11 owns its replacement.

`488-492` reads `Config.Trial.TasksToComplete` against `Config.Tasks.PoolSize`; after Step 4.1 the trial
draws from its own points, so the invariant has no second operand. Delete it and note it with the others.

**Do not touch the PASS line's shape.** It interpolates its tally, so nineteen deletions move it by
themselves — that is `check:testcount`'s entire reason for existing (`check-testcount.mjs:9-20`), and
this step is the exact refactor it was built from.

#### Step 4.6: Remove the dead budget assertions from `tests/anti-cheat-budgets.test.luau`

**File:** `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

Remove the four names from the up-remote list (`:31-32`, `:40-41`), the `RequestTaskProgress` refill
assertion (`:113-118`), the `RequestGhostSpook` capacity assertion against `Config.Ghost.SpooksPerRound`
(`:136-140`), and the `RequestTimingStop` vs `Config.Tasks.TimingBarPeriod` assertion (`:144-153`).

This suite is what makes Steps 4.3 and 4.4 a matched pair rather than two independent edits: it asserts
the budget table and the declared up-remote list are the **same set**. Run it before running `verify`.

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

- **Remote direction — the one step in this plan that can hang a client.** `check:remotes` is
  bidirectional and its own header names the failure: a client `WaitForChild`ing a name the server never
  creates hangs forever with no error and no stack trace (`check-remotes.mjs:9-13`). Phases 1 and 2
  removed every listener and every fire; this phase removes the declarations. **If Step 4.4 is done
  before Phase 1 is complete, the game boots to a black screen and nothing says why.**
- **Rate limiting.** Four `Budgets` entries and four up-remotes leave together. Confirm every *surviving*
  `OnServerEvent` handler still consults `AntiCheatService` — `check:ratelimit` is a text tripwire on
  obvious shapes and cannot follow data flow, so this is the phase where `exploit-auditor` earns its
  place on the 🔒 surface.
- **Magic numbers.** The risk here is inversion: deleting a Config block and pasting one of its numbers
  into the service that read it. Step 4.1 is the only legitimate move of a number in this plan, and it
  moves it into `Config.Trial` rather than into `TrialService`. `check:config` proves it.
- **Secret leakage.** `GhostRoster` leaves the wire. It was the remote whose safety came from its
  audience rather than its payload (`Remotes.luau:64-76`) — the *only* one of that shape — so removing
  it deletes a class of mistake rather than an instance of one. `check-secrecy.mjs`'s
  `REVEAL_ALLOWLIST` must still contain exactly `RoundEnded` and `RoleAssigned` afterwards, unchanged.
- **Player leaving mid-round (§6.4).** `ReportGhostPosition` was "the one place in the game where the
  client owns a position" (`Remotes.luau:151`). It goes. After this phase no remote carries a
  client-supplied position, which is a strictly stronger property than the tree had before.
- **Scope.** `Config.Ghost` is deleted here and the guard is armed in Phase 5. Between the two, the word
  `Ghost` still appears in `Enums`, `Types` and nine surviving modules — that is expected, and arming
  the guard early is what the build plan explicitly warns produces 154 findings and a commit guard that
  refuses every commit.

---

### Phase 5: Re-arm the scope guard

The word `/^ghosts?$/i` cannot be enabled until the last string literal spelling `GHOST` is gone. 55 of
the 154 findings live in files this chunk does not delete, so this phase is a rename across the
surviving tree, then the guard, then its self-test.

> **Measured, not estimated.** Running the guard with the word enabled against the tree as it stands
> produces **exactly 154 findings**, matching the build plan's number. **99 of them are in files this
> plan deletes. The other 55 are not**, and they are spread across `Types`, `Enums`, `Config`,
> `Remotes`, `RoundService`, `QuickChatService`, `UIController`, `init.client` and **nine surviving pure
> modules**. Phases 1–4 clear the 99. This phase clears the 55, and it is a rename rather than a
> deletion because most of them are the string literal `"GHOST"` in a `PlayerState` union.

#### Step 5.1: Rename `shared/pure/GhostChat.luau` to `ChatAudience.luau`

**File:** `src/shared/pure/ChatAudience.luau`
**Verify:** `lune run tests/chat-audience.test.luau`

**This module is on the build plan's delete list and it must not be deleted.** `QuickChatService`
requires it (`:68`) and calls `shouldDeliver` at `:335-337`. Its own header calls it "the most dangerous
rule in the game and it is four words long: a dead player's words must never reach a living one"
(`GhostChat.luau:7-8`). Ghosts are cut; **dead players are not**, they spectate (spec §4.7), and a
spectating player who watched their own death still knows who did it. Deleting the module either breaks
`QuickChatService` or silently widens that audience to everyone.

`git mv src/shared/pure/GhostChat.luau src/shared/pure/ChatAudience.luau` and
`git mv tests/ghost-chat.test.luau tests/chat-audience.test.luau`, then:

```diff
 --!strict
 --[[
-	GhostChat — may this player's message reach that player? (§4.7, C15)
+	ChatAudience — may this player's message reach that player? (§4.7, C15, V01)
```

```diff
-export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
```

```diff
-function GhostChat.isLivingSide(state: PlayerState): boolean
+function ChatAudience.isLivingSide(state: PlayerState): boolean
 	return state == "ALIVE" or state == "LOBBY"
 end
```

```diff
-function GhostChat.shouldDeliver(senderState: PlayerState, recipientState: PlayerState): boolean
-	return GhostChat.isLivingSide(senderState) or senderState == recipientState
+function ChatAudience.shouldDeliver(senderState: PlayerState, recipientState: PlayerState): boolean
+	return ChatAudience.isLivingSide(senderState) or senderState == recipientState
 end
```

**Change no truth value.** `isLivingSide` is an allowlist of `ALIVE` and `LOBBY` precisely so that a
denylist (`~= "GHOST"`) cannot silently admit `SPECTATOR` (`:44-47`) — the rename must keep it an
allowlist, and the header paragraph that argues for it stays word for word with `"GHOST"` swapped for
`"DEAD"`. In the test file, update the require, swap `"GHOST"` for `"DEAD"` in the grid, and change the
PASS line to `` `  PASS  chat-audience: {checked} assertions over the full sender x recipient grid` ``.
The suite passing with the same cell count is the proof.

#### Step 5.2: Rename the `GHOST` player state to `DEAD` in `Types` and `Enums`

**File:** `src/shared/Types.luau`
**Verify:** `grep -rL "GHOST" src/shared/Types.luau`

```diff
-export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
```

and in `Enums.luau`:

```diff
 Enums.PlayerState = table.freeze({
 	Lobby = "LOBBY" :: Types.PlayerState,
 	Alive = "ALIVE" :: Types.PlayerState,
-	Ghost = "GHOST" :: Types.PlayerState,
+	Dead = "DEAD" :: Types.PlayerState, -- V01: killed in-round. Spectates; the corpse is the body
 	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
 })
```

**A rename, and specifically NOT a collapse into `SPECTATOR`.** This is constraint (b) and it is the
single most dangerous edit in the plan. `BodyTransitions.actionFor` short-circuits this state to `KEEP`
above `mayHaveBody` (`BodyTransitions.luau:127-129`), which is what keeps the corpse attached and
`player.Character ~= nil` true for the dead set. `SPECTATOR` falls through to `REVOKE`, which would
destroy the corpse and make `Character == nil` enumerate exactly the players who have died — the
inverted tell two prior audits already found and fixed (`BodyTransitions.luau:113-125`,
`PlayerBody.luau:36-46`). Four states in, four states out.

Then update the two writers in `RoundService` — `:929` (`MarkKilled`) and `:1316` (the husk-kill path) —
plus the `hadGhostBody` block at `:566-571` and the comment at `:583`. `Enums.PlayerState.Ghost`
becomes `Enums.PlayerState.Dead`; `hadGhostBody` becomes `hadDeadBody`.

#### Step 5.3: Rename the local `PlayerState` unions in the eight surviving pure modules

**File:** `src/shared/pure/BodyTransitions.luau`
**Verify:** `lune run tests/body-transitions.test.luau`

Eight modules re-declare the union locally, because a pure module may not
`require(script.Parent.Types)` — Lune has no `script`, and Luau unions are structural so the local and
`Types.PlayerState` are the same type (CLAUDE.md, "Where testable logic goes"). Every one needs the same
one-line edit:

| File | Line | Also |
| --- | --- | --- |
| `src/shared/pure/AudioCues.luau` | 32 | comment at `:99` |
| `src/shared/pure/BodyTransitions.luau` | 35 | **the `== "GHOST"` branch at `:127`**, comments `:62-64, 90-91, 104, 113` |
| `src/shared/pure/KillValidation.luau` | 39 | comment at `:132` |
| `src/shared/pure/PlayerBody.luau` | 29 | comments `:18, 36, 46` |
| `src/shared/pure/RejoinResolve.luau` | 43 | comments `:13-22` |
| `src/shared/pure/SaltCarry.luau` | 35 | comment at `:53-54` |
| `src/shared/pure/SaltThrow.luau` | 43 | — |
| `src/shared/pure/TransformRules.luau` | 30 | comment at `:67` |

```diff
-export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
+export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"
```

```diff
-	if state == "GHOST" then
+	if state == "DEAD" then
 		return "KEEP"
 	end
```

`BodyTransitions` is the file named on the `**File:**` line because it is the only one of the eight with
an actual branch on the value; the other seven change a type and some prose. Its suite is the verify for
the same reason.

The comments are not optional cleanup: several of them argue from "a ghost flies and the corpse stays"
(`BodyTransitions.luau:90-91`), which is now false. Rewrite them to say what is true — the dead player
spectates and the corpse stays — without changing a single truth value in the code.

#### Step 5.4: Update the eight suites that pass `"GHOST"`

**File:** `tests/player-body.test.luau`
**Verify:** `npm run test:unit`

`tests/body-transitions.test.luau`, `player-body.test.luau`, `rejoin-resolve.test.luau`,
`kill-validation.test.luau`, `salt-carry.test.luau`, `salt-throw.test.luau`,
`transform-rules.test.luau`, `audio-cues.test.luau`.

**Swap the literal and change nothing else — no case added, none removed, no expectation flipped.**
That is what makes this phase provably a rename: eight exhaustive grids that passed before must pass
after, with the same tallies in the same PASS lines. If any suite needs an assertion changed to go
green, the rename has changed behaviour and the change is a bug, not a fix.

`npm run test:unit` rather than a single `lune run` here, because the property being proven is *all
eight together*.

#### Step 5.5: Rename `GhostMay` to `DeadMay` and update its two readers

**File:** `src/shared/pure/QuickChatPhrases.luau`
**Verify:** `lune run tests/quick-chat-phrases.test.luau`

`GhostMay` is a field on all eight phrases (`:60, 77, 85, 93, 101, 111, 119, 127, 135`). Rename it to
`DeadMay` throughout, and in `QuickChatService`:

```diff
-			if senderState == Enums.PlayerState.Ghost and not phrase.GhostMay then
+			if senderState == Enums.PlayerState.Dead and not phrase.DeadMay then
 				recordVerdict("NOT_ALLOWED_FOR_STATE")
 				return
 			end
```

```diff
 			if
 				senderState ~= Enums.PlayerState.Alive
-				and senderState ~= Enums.PlayerState.Ghost
+				and senderState ~= Enums.PlayerState.Dead
 			then
```

Also `QuickChatService:68` (the require, now `ChatAudience`), `:335-337` (the call and its two casts),
and `:416`. In `tests/quick-chat-phrases.test.luau`, `:88` and `:114` — keeping the assertion that
**exactly one phrase** (ACCUSE) is forbidden to the dead, which is the whole point of the field being
data rather than an `if` (`QuickChatService:412-415`).

`UIController` finishes here too: `COLOUR.Ghost` (`:223`) becomes `COLOUR.Dead`, and both
`PlayerState.Ghost` branches (`:1729`, `:2039`) become `PlayerState.Dead`. `:1730`'s copy — "WASD fly ·
Space up · LeftCtrl down · your chat reaches ghosts only" — describes a flying body that no longer
exists; replace it with spectate copy that is true, e.g. `"you are dead — watching · your chat reaches
the dead only"`.

#### Step 5.6: Drop the two orphaned teaching cues

**File:** `src/shared/pure/TeachingLines.luau`
**Verify:** `lune run tests/teaching-lines.test.luau`

```diff
 export type TeachingCueId =
 	"CUE_FIRST_SALT"
-	| "CUE_FIRST_GHOST_DEATH"
 	| "CUE_FIRST_TRANSFORM_SEEN"
-	| "CUE_FIRST_TWO_PERSON"
```

and the two copy entries in `TeachingLines.luau` (`:37-39` and the `CUE_FIRST_TWO_PERSON` line). Their
firing sites went with `GhostService` and `TaskService` in Step 2.3.

`CUE_FIRST_GHOST_DEATH`'s copy is *"You can still help — haunt the tasks your friends are working on."*
Both halves of that sentence are now false. **Do not rewrite it into a spectate line here** — V03 owns
the new onboarding cue for searching, and inventing copy in a demolition chunk is how a chunk grows.
Two cues survive, `CUE_FIRST_SALT` and `CUE_FIRST_TRANSFORM_SEEN`, both still fired by surviving
services (`ItemService.luau:314`, `MonsterService.luau:474`).

Update `tests/teaching-lines.test.luau` to drop the two ids. If that suite asserts a total count, the
count must be interpolated rather than typed — `check:testcount` is in `npm run verify`.

#### Step 5.7: Arm the `ghosts?` word and write its missing self-test case

**File:** `.claude/scripts/check-scope.mjs`
**Verify:** `npm run check:guards`

```diff
 	{ word: /^microphones?$/i, why: 'a mic-driven mechanic', cite: '§4.5 — rejected on three independent grounds' },
-	// DEFERRED TO V01 — `{ word: /^ghosts?$/i, why: 'the ghost system', cite: '§4.7 — cut in v2.0' }`
-	//
-	// §4.7 cuts ghosts, so this belongs here. It is commented out because the ghost code v2.0 deletes is
-	// still standing: enabling it now produces 154 findings across nine live modules, a red tree, and a
-	// commit guard that refuses every commit until the demolition lands. A guard that blocks work it is
-	// meant to protect gets disabled rather than obeyed.
-	//
-	// V01 deletes the ghost system AND uncomments this line, in the same diff. The self-test case below
-	// is already written and will start passing then.
+	// ARMED AT V01, with the ghost system deleted in the same diff. §4.7 cuts ghosts; dead players
+	// spectate. The two ALLOW cases below — a corpse and a husk — are the near misses this must not
+	// catch, and `PlayerState`'s dead member is spelled DEAD for the same reason.
+	{ word: /^ghosts?$/i, why: 'the ghost system', cite: '§4.7 — cut in v2.0' },
 	{ word: /^sabotage[ds]?$/i, why: 'sabotage systems', cite: '§3 OUT' },
```

**The build plan says the self-test case is "already written and commented out". It is not.** There is
no commented-out ghost case anywhere in `check-scope.mjs` or in `harness-selftest.mjs` — the scope
self-test lives inside `check-scope.mjs` itself behind `--self-test` (`:118-173`), and
`harness-selftest.mjs` only invokes it (`:96`). What exists is the two **ALLOW** cases at `:157-158` (a
corpse, a husk), which pass today only because the word is disabled and would pass armed too, since
neither source string contains the bare word. So this step **writes** the missing BLOCK case:

```diff
 	check('a mic-driven mechanic', 'local microphoneLevel = 0', true)
+	check('the ghost system', 'local GhostService = {}', true)
+	check('a ghost in a UI string', 'label.Text = "your chat reaches ghosts only"', true)
```

Two cases rather than one, because the guard scans `withStrings`: an identifier and a UI label are the
two shapes a returning ghost actually takes, and the second is the one the ALLOW/BLOCK boundary is
least obvious for. `npm run check:guards` runs all 28 suites unconditionally and is the verify.

Per CLAUDE.md, harness scripts are reviewed by `change-auditor` plus `check:guards`, **not** by
`exploit-auditor` — no game surface, no Luau.

#### Step 5.8: Clear the task residue and record the deferral list

**File:** `src/server/Services/RoundService.luau`
**Verify:** `grep -rL "Task" src/server/Services/RoundService.luau`

The build plan's Done line — `git grep -i task src/` returns only Roblox's `task` library — is not
literally reachable, for the reasons in constraint (d). This step makes it true of the **round**, which
is what the line was actually protecting, and writes down the rest.

Sweep every surviving file for task-game prose and copy. The ones that are easy to miss because they
are neither identifiers nor remotes, all in `UIController` and all **copy shown to a player**:

| Site | Today | Why it must change |
| --- | --- | --- |
| `:974` | `"You are a survivor.\nFinish five tasks and escape."` | the role intro tells a new player to do something that no longer exists |
| `:1750` | `"hold ACT at a task · STOP on the bar · …"` | mobile prompt |
| `:1753` | `"E hold a task · R time it · …"` | desktop prompt |
| `:1770` | `"Tasks go faster with two people standing at them."` | lobby tip |

Rewrite all four to describe the round V01 leaves behind — survive until sunrise, salt is the
counterplay — and **not** V03's search loop, which does not exist yet. A HUD that promises searching
before searching ships is the same lie in the other direction.

**The deferral list — every `task` token that legitimately survives V01, with the chunk that owns it:**

| Token | Where | Owner |
| --- | --- | --- |
| `task.wait` / `task.spawn` / `task.delay` | throughout | Roblox's library. Never in scope |
| `Stats.TasksDone` | `Types.luau:23`, `ProfileMigration`, `ProgressionService:427` | **V4** — persisted profile field; removing it is a schema migration |
| `BadgeRules.FirstTask` | `BadgeRules.luau:62, 75, 115` | **V4** — an awarded Roblox badge id; §10's launch gate reads it |
| `TrialTasksDone` / `TrialTasksRequired` | `Types.luau:664-665`, `TrialController:200` | Solo Trial, untouched by V01 |
| `Config.Trial.TasksToComplete` | `Config.luau:669` | Solo Trial, untouched by V01 |
| `TAG_POINT = "TaskPoint"` | `TrialService.luau:64` | **The map.** See below |

**`"TaskPoint"` is a CollectionService tag on parts that live in the place file, and the place file is
not in Git.** Renaming the tag in code without re-tagging every part in Studio silently gives the Solo
Trial an empty pool — no error, no diff, and nothing in `git status`. Code cannot re-tag them; that is a
Studio action. So the tag name stays at V01 and the rename belongs to whichever chunk re-dresses the
map, stated in Follow Ups. This is the "the map is not code" rule doing real work rather than
decoratively.

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

- **Secret leakage — Critical if `DEAD` is collapsed into `SPECTATOR` instead of renamed.** Stated three
  times in this plan because it is the one way this phase ships a Critical bug while every check stays
  green: `BodyTransitions.actionFor(SPECTATOR, "DIED")` returns `REVOKE`, which destroys the corpse and
  leaves `player.Character == nil` for exactly the set of players who have died. `check:secrecy` cannot
  see it — it reads payload fields and call shapes, not body lifecycles — and `analyze` cannot either,
  because both spellings typecheck. **This is the finding `exploit-auditor` exists for**, and the brief
  it gets should name `BodyTransitions.actionFor` and `PlayerBody.mayHaveBody` by name.
- **Secret leakage — the chat audience.** `ChatAudience.isLivingSide` must stay an **allowlist** of
  `ALIVE` and `LOBBY`. A denylist written during the rename (`~= "DEAD"`) silently admits `SPECTATOR`,
  which is the exact cell the module was written to close (`GhostChat.luau:44-47`) and would put a dead
  player's accusation in front of the living.
- **Strict Luau.** Narrowing a literal union by excluding members widens the remainder to plain
  `string`, which then fails to satisfy the declared return type — `RejoinResolve.luau:106-110` carries
  the cast that works around it, and that cast is on a line this phase edits. Do not remove it.
- **Player leaving mid-round (§6.4).** `RejoinResolve.evaluate` returns the stored state verbatim for a
  dealt-in player, so "husk killed → you come back DEAD" is a path through the renamed value. Its suite
  covers it exhaustively; Step 5.4 must not weaken a case to make it pass.
- **Phase ownership.** Unchanged. Nothing in this phase touches `setPhase` or its callers.
- **Scope — this is the phase that arms the guard, so `check:scope` must go from "would find 154" to
  "finds 0" here and stay there.** Run it after Step 5.7 and again after Step 5.8; a finding at that
  point names a file Phases 1–4 missed, which is the check doing exactly its job.
- **Harness routing.** `.claude/scripts/**` changes are reviewed by `check:guards` + `change-auditor`,
  **not** `exploit-auditor` (CLAUDE.md's reviewer table). The Luau half of this phase is a 🔒 surface and
  still gets `exploit-auditor`. They are two separate briefs on one diff.

---

## 3. Related Files

**Reviewed while planning, with annotations in `references/`:**

| File | Why it was read |
| --- | --- |
| `src/server/Services/RoundService.luau` | The reference service shape; owns the phase, the snapshot, the task counter and the gate |
| `src/shared/Types.luau` | `RoundState`, `ClientRoundSnapshot`, `PlayerState`, and ten dead payload types |
| `src/shared/Remotes.luau` | The nine remotes that leave the wire, and the two that must not |
| `src/shared/Config.luau` | `Config.Tasks`, `Config.Ghost`, `Config.Trial`, the AntiCheat budget table |
| `src/shared/pure/BodyTransitions.luau` | The `GHOST → KEEP` short-circuit — the reason this is a rename |
| `src/shared/pure/GhostChat.luau` | The audience rule that must survive under a new name |
| `src/server/Services/QuickChatService.luau` | The only surviving caller of that rule |
| `src/server/Services/ItemService.luau` | The only surviving caller of `TaskPool` |
| `src/server/Services/TrialService.luau` | The last reader of `Config.Tasks`, and the `TaskPoint` map tag |
| `src/client/Controllers/UIController.luau` | The task bar, the gate, and four copy strings |
| `src/client/Controllers/AudioController.luau` | The gate cue nobody expects to find in an audio file |
| `src/server/init.server.luau` / `src/client/init.client.luau` | The two bootstrap lists |
| `.claude/scripts/check-scope.mjs` | The deferred word and the self-test that turned out not to exist |
| `tests/config.test.luau` | The nineteen invariants that die with `Config.Tasks` / `Config.Ghost` |
| `tests/win-conditions.test.luau` | The suite that is kept and emptied |

**Inventories, so implementation does not re-derive them:**

- `references/ghost-word-inventory.md` — all 154 armed-guard findings, split by whether the file survives
- `references/config-test-invariant-inventory.md` — every `check(...)` in `tests/config.test.luau` tagged
  by whether it reads `Config.Tasks` or `Config.Ghost`
- `references/deleted-module-callsites.md` — every inbound reference to every deleted module, with
  `file:line`

## 4. Follow Ups

### Questions / Clarifications

1. **The Aswang has no win condition between V01 and V11, and that is a design gap this plan does not
   fill.** Survivors survive to sunrise; the Aswang cannot win at all. Confirm this is the intended
   interim — the alternative (a placeholder kill-everyone rule now) would be V11's work done badly in a
   demolition chunk, and would need a `WinConditions` module the build plan explicitly deletes.
2. **`RoundResult.SURVIVORS_ESCAPED` becomes unreachable.** Kept, because V02 owns the v2.0 vocabulary
   and `UIController`'s end-screen branches on the union. Confirm V02 picks it up rather than V01.
3. **`Config.Round.AswangWinSurvivorThreshold` is deleted by Step 4.2** once its only reader goes. If it
   should instead be kept for V11, say so — this plan's judgement is that an unread tunable is exactly
   what V01 exists to remove.
4. **`Stats.TasksDone` is a stat nothing increments after Phase 2**, and `BadgeRules.FirstTask` reads it.
   §10's launch gate is `FirstTask / Welcome > 0.50`, so **the funnel's headline metric stops moving at
   V01 and stays flat until V4 rebinds it to searching.** That is not a bug this chunk should fix, but it
   is a number that will look catastrophic on a dashboard for several chunks, and somebody should know
   in advance.
5. **`TrialService`'s `"TaskPoint"` CollectionService tag stays.** The parts carrying it live in the
   place file, which is gitignored, and code cannot re-tag them. The rename belongs to a chunk that also
   opens Studio. Which one?
6. **Three balance invariants are deleted with nothing to replace them** (Step 4.5): salt's pickup radius
   vs a hold radius, the accusation radius vs a presence radius, and full-server winnability. All three
   were silent invariants — nothing in the game reports when they stop holding. V03 and V11 must restore
   an equivalent right-hand side, and spec §6.5's six v2.0 invariants are where they should land.
7. **`Types.RoundState` is not applied to `RoundService`'s `state`** (`RoundService.luau:49` is an
   inferred table literal), which is why `RoundState.Tasks` could describe a field nothing held. Worth
   V02 closing deliberately with a `: Types.RoundState` annotation.
8. **No Roblox API behaviour was assumed in this plan.** Every claim about `WaitForChild`,
   CollectionService tag replication and `pcall` arity comes from `CLAUDE.md`, `check-remotes.mjs`'s
   header, or a comment in this repo, each cited at the point of use.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| — | Build plan lists `src/shared/pure/TaskWeight.luau`; the file is at `src/server/pure/TaskWeight.luau`. Deleting the shared path is a no-op that leaves the real module standing | Medium | Resolved in Step 2.4 |
| — | Build plan says `check-scope.mjs`'s ghost self-test case is "already written and commented out". No such case exists, in that file or in `harness-selftest.mjs`. The two ghost-adjacent cases present are ALLOW cases (corpse, husk) that pass either way | **High** — the guard would be armed with no BLOCK coverage at all | Step 5.7 writes two BLOCK cases |
| — | Build plan implies deleting the ghost code clears all 154 scope findings. Measured: **55 of them are in files V01 does not delete**, across `Types`, `Enums`, `Config`, `Remotes`, three services and nine pure modules | **High** — arming the guard after Phase 4 would still produce a red tree and a commit guard that refuses every commit | Phase 5 exists for this |
| — | Build plan lists `src/shared/pure/GhostChat.luau` for deletion. `QuickChatService` requires it and calls `shouldDeliver` for the dead/living audience wall — deleting it either breaks quick chat or silently widens that audience | **High** (secrecy) | Renamed, not deleted, in Step 5.1 |
| — | Build plan's delete list implies every task pure module goes. `server/pure/TaskPool.luau` has a live caller in `ItemService` (the pouch pool verdict) | Medium | Renamed to `SearchPool` in Step 2.1 |
| — | Build plan's Done line (`git grep -i task src/` returns only `task.*`) is not reachable: `Stats.TasksDone`, `BadgeRules.FirstTask`, `TrialTasksDone`, `Config.Trial.TasksToComplete` and the `"TaskPoint"` map tag all legitimately survive V01 | Medium | Step 5.8 replaces it with an enumerated deferral list |
| 1 | `AudioController` reads `snapshot.GateOpen` at `:660` through an edge detector — a task/gate reader in a file nobody thinks to check | Medium | Step 1.6 |
| 1 | Four player-facing copy strings in `UIController` (`:974, 1750, 1753, 1770`) instruct players to do tasks | Medium | Step 5.8 |
| 1 | `OnboardingController` cannot be deleted despite being pure task waypoint — `TrialController` requires it for `ShowLine` | Medium | Step 1.4 reduces rather than deletes |
| 3 | `Types.RoundState.Tasks` describes a field `RoundService`'s `state` never held | Low | Deleted in Step 3.4; annotation gap raised for V02 |
| 5 | Collapsing `PlayerState.GHOST` into `SPECTATOR` rather than renaming it to `DEAD` destroys the corpse and makes `Character == nil` enumerate the dead set | **Critical** if done wrong; no check catches it | Constraint (b); Steps 5.2–5.4; named in the `exploit-auditor` brief |
