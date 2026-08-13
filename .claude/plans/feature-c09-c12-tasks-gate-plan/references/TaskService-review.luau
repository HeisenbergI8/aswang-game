--!strict
--[[
	REVIEW — src/server/Services/TaskService.luau
	Read 2026-08-12 for the C09-C12 plan. Cited ranges below; the file is 794 lines.

	The single most important file for this plan. Every C09/C10/C12 phase edits it, and its existing
	shape decides how much of them is new code and how much is a parameter.
]]

-- src/server/Services/TaskService.luau:27-33
-- The TODO block that names this plan, and HALF OF IT IS NOW WRONG.
-- TODO(C09/C10): Timing, Fetch and TwoPerson. `taskTypeOf` reads the TaskType attribute and warns on
-- anything that is not HOLD, so an anchor asking for one is visible rather than silently mishandled.
-- TODO(C12): the Aswang sees a FAKE TASK LIST. Its progress still counts, in full — Amendment A2 [...]
-- IMPORTANT: the A2 half is CORRECT and already updated; it is the C09/C10 half that Step 3.1 fixes.
-- Step 7.4 rewrites the whole block. NOTE: this comment is the only in-tree statement of A2's rule at
-- the point of use, so it must not be deleted, only re-aimed.

-- src/server/Services/TaskService.luau:43-48
-- ONE DIRECTION ONLY [...] RoundService must NEVER require TaskService back
local AntiCheatService = require(script.Parent.AntiCheatService)
local RoundService = require(script.Parent.RoundService)
-- IMPORTANT: GateService (Phase 6) sits on this same side of the rule. It requires RoundService and
-- RoundService must not require it back — the win is raised by calling `EndRound`, exactly as
-- MonsterService raises a kill by calling `MarkKilled`.

-- src/server/Services/TaskService.luau:76
local rng = Random.new()
-- The ONE Random, a module local rather than a Start() local, no argument.
-- IMPORTANT for Phase 7: the decoy draw MUST reuse this same `nextFloat`. A second
-- `Random.new()` would be harmless; `Random.new(anything)` would be fatal for the same reason the
-- header gives — the round number and os.time() are both client-observable.

-- src/server/Services/TaskService.luau:216-227
local function taskTypeOf(part: BasePart): Types.TaskType
	local requested = part:GetAttribute("TaskType")
	if requested ~= nil and requested ~= Enums.TaskType.Hold then
		warn(`[TaskService] {part.Name} asks for TaskType "{requested}", which is not built yet [...]`)
	end
	return Enums.TaskType.Hold
end
-- Step 3.1 replaces this. NOTE: `GetAttribute` returns `any`, so the comparison against a
-- `Types.TaskType` typechecks without a cast — but the LIST it is compared against must be an
-- explicit `{ Types.TaskType }` array, because `Enums.TaskType` is a frozen RECORD and iterating it
-- generically is the shape that produced the scaffold's original analyze errors.

-- src/server/Services/TaskService.luau:246-274
local function attachPrompt(part: BasePart)
	prompt.MaxActivationDistance = Config.Tasks.PresenceRangeStuds
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.None
end
-- IMPORTANT — the hardest-won three lines in the repo. Both properties default WIDER than the server
-- accepts (measured: MaxActivationDistance 10 vs PresenceRangeStuds 9; RequiresLineOfSight true), and
-- the default `KeyboardKeyCode = E` SWALLOWED the ContextActionService bind on the same key, shipping
-- C08 unreachable-by-humans. `None`, not `Unknown` — same runtime value, but `Unknown` is absent from
-- the analyzer's Enum.KeyCode type.
-- QUESTION for Phase 3: does anything claim `R`? Nothing here proves it does not, and the failure is
-- silent in exactly the same way. This is the plan's #1 playtester question.

-- src/server/Services/TaskService.luau:422-436
local function weightFor(player: Player): number
	return TaskWeight.forPlayer(
		RoundService.GetPlayerState(player),
		Enums.Role.Survivor,
		Config.Ghost.TaskContributionMult
	)
end
-- IMPORTANT: the role passed is the SURVIVOR CONSTANT for everyone, deliberately — "a live reference
-- to the secret with no purpose", four times a second, feeding a parameter the grid proves is
-- ignored. Phases 4 and 5 reuse this function unchanged, which is what makes them inherit A2's
-- property rather than restate it.
-- NOTE: Phase 7's `publishTaskLists` DOES read `GetAswangUserId()`. That is a deliberate departure
-- from this posture, scoped to one function called once per round, and it is in Follow Ups.

-- src/server/Services/TaskService.luau:480-512
local function taskPointAt(player: Player): (string?, boolean)
-- Returns (nearest incomplete point in range, was anything in range at all).
-- IMPORTANT: NEAREST-INCOMPLETE, not first-match — a soft-lock fix. `MinSpacingStuds` is a REQUEST to
-- TaskSelection, whose fallback drops spacing rather than run a short round (audit: 2000/2000 draws
-- violated it for a packed pool). Step 3.2's `evaluateTimingStop` reuses this verbatim so the two
-- validators cannot drift, and NO new code may assume selected points are spaced.

-- src/server/Services/TaskService.luau:547-577
local function publishProgress(completionChanged: boolean)
	local payload: Types.TaskProgressPayload = { ... }
	progressRemote:FireClient(player, payload)
-- IMPORTANT: FireClient per player, never FireAllClients, and built as a TYPED LOCAL because
-- FireClient takes `...any`. Phase 3's `publishBar` and Phase 7's `publishTaskLists` copy both rules.
-- The typed local additionally matters for check-secrecy: it resolves the payload to its FIELD names,
-- so an inlined table would instead have its raw argument text scanned — and Phase 7's would contain
-- the word `role`.

-- src/server/Services/TaskService.luau:596-662
local function tick()
	local elapsed = now - lastTickAt
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active or #activeTasks == 0 then return end
	-- [presence pass builds weights[taskId] = { number }]
	-- [progress pass: TaskProgress.tick(task.Progress, elapsed, weight, Config.Tasks.HoldTime)]
-- IMPORTANT: this is the extension point for THREE of the plan's phases. Phase 3 adds a `continue`
-- for TIMING; Phase 4 adds a carrier filter to the presence pass, a `durationFor` in place of the
-- hardcoded HoldTime, and calls `tickFetch()` after the early return; Phase 5 zeroes the weight for
-- an under-staffed TWO_PERSON. `elapsed` being SERVER seconds is what makes spamming worthless, and
-- nothing added may make the rate a function of request count.

-- src/server/Services/TaskService.luau:773-779
	Remotes.Get("RequestTaskProgress").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTaskProgress") then return end
		notePresence(player)
	end)
-- IMPORTANT: `check-ratelimit.mjs` matches the Consume call within 1200 CHARACTERS of the connect
-- site. Step 3.2's `RequestTimingStop` handler must sit beside this one, with Consume first, or a
-- correctly-limited handler reads as unguarded and fails the build.

-- src/server/Services/TaskService.luau:735-742
local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Starting then
		clearTasks()
		selectForRound()
-- NOTE: Phases 4 and 7 append `setUpFetchTasks()` and `publishTaskLists()` here, in that order.
-- IMPORTANT: RoundService assigns `state.AswangUserId` BEFORE firing PhaseChanged (RoundService:587
-- vs :611, deliberately), so `publishTaskLists` can read the secret from this handler and get it.
return nil
