--!strict
--[[
	TaskService — Picks 5 of 12 task spawns per round and validates progress.

	Milestone: M3
	Spec: docs/MVP-SPEC.md

	THE SEED IS THE PART TO GET RIGHT
	---------------------------------
	`TaskSelection` lives under src/shared/, so a client can require it AND call it. The algorithm being
	public costs nothing; a reproducible STREAM costs the round, because the Aswang would know where
	every task is before STARTING ends.

		local rng = Random.new()            -- correct: server-only entropy, no argument
		local rng = Random.new(roundNumber) -- FATAL: the client has the round number in every snapshot
		local rng = Random.new(os.time())   -- FATAL: client-observable to the second

	The Random is created ONCE, as a server-side local, and `nextFloat` is what reaches the pure module.
	Never send the seed, the stream position, or the unselected pool to a client.

	Selection happens in STARTING and the chosen set is server state — in the sense that the server
	decides it and no client can predict or extend it. The chosen parts DO carry a replicated
	`ActiveTaskPoint` tag, and that is correct rather than tolerated: players must be able to find the
	objective. What must never leak is the ability to know the selection before it is made.
]]

-- TODO(C09/C10): Timing, Fetch and TwoPerson. `taskTypeOf` reads the TaskType attribute and warns on
-- anything that is not HOLD, so an anchor asking for one is visible rather than silently mishandled.
-- TODO(C12): the Aswang sees a FAKE TASK LIST. Its progress still counts, in full — Amendment A2 in
-- docs/MVP-SPEC.md, which reverses §4.4's original wording after an exploit audit showed the original
-- mechanism BUILDS the oracle it was meant to prevent. C12 changes what the Aswang is TOLD (which five
-- points its HUD names), never what its holds do. `pure/TaskWeight.luau` and its grid are what keep
-- that honest; do not add a role branch to `weightFor`.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
-- ONE DIRECTION ONLY, and this is the direction. RoundService must NEVER require TaskService back:
-- a require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
-- in IDLE forever looking exactly like "nobody has joined yet". MonsterService already sits on this
-- side of the same rule.
local AntiCheatService = require(script.Parent.AntiCheatService)
-- C15: ghosts have no server character, so a ghost's position comes from GhostService rather than from
-- `player.Character`. One direction only — GhostService requires RoundService and AntiCheatService and
-- must never require this file back, for the same load-order reason the comment above gives.
local GhostService = require(script.Parent.GhostService)
local RoundService = require(script.Parent.RoundService)
local FetchCarry = require(script.Parent.Parent.pure.FetchCarry)
local TaskListView = require(script.Parent.Parent.pure.TaskListView)
local TaskParticipants = require(script.Parent.Parent.pure.TaskParticipants)
local TaskPool = require(script.Parent.Parent.pure.TaskPool)
local TaskProgress = require(script.Parent.Parent.pure.TaskProgress)
local TaskResolve = require(script.Parent.Parent.pure.TaskResolve)
local TimingWindow = require(script.Parent.Parent.pure.TimingWindow)
local TaskWeight = require(script.Parent.Parent.pure.TaskWeight)
local TaskSelection = require(Shared.pure.TaskSelection)
local Types = require(Shared.Types)

local TaskService = {}

local TAG_POINT = "TaskPoint"
local TAG_ACTIVE = "ActiveTaskPoint"
--[[
	Set the moment a point reaches 5/5-worthy completion, cleared with the round in `clearTasks`.

	IT EXISTS BECAUSE COMPLETION HAD NO REPLICATED FORM AT ALL. `ActiveTaskPoint` is added at the draw
	and removed only at teardown, so a finished point and an untouched one were indistinguishable from
	any client — the state a manual playtest reported as "no changes on its design when done".

	Same secrecy argument as TAG_ACTIVE and it is not a new one: `server/pure/TaskListView.luau`'s
	header already records that the real five replicate and that C12 is "an information-channel lie",
	explicitly NOT a secret. This names a place and a state, never a person: no role, no UserId.
]]
local TAG_DONE = "CompletedTaskPoint"
local TAG_SOURCE = "FetchSource"
-- On the item itself, so a human looking at the workspace can tell a fetch item from set dressing,
-- and so C17 can find and delete every one the rig left behind. It names an object, not a person:
-- `check:secrecy` inspects tag names and this one carries no role and no UserId.
local TAG_ITEM = "FetchItem"

-- Where a carried fetch item floats relative to the carrier's root part. Purely visual, and it is a
-- placeholder: C18 replaces this with a WeldConstraint to a real prop, at which point the offset
-- becomes the model's own pivot and this constant disappears.
local CARRY_OFFSET = Vector3.new(0, 3, 0) -- config-ok: placeholder carry visual, replaced at C18

--[[
	THE ONE Random, AND IT IS A MODULE LOCAL RATHER THAN A Start() LOCAL.

	Every property the seed section above asks for is preserved and one is strengthened:

	  · no argument                  — unchanged, and it is the whole point
	  · server-side, never sent      — unchanged
	  · created exactly ONCE         — STRONGER. A module local cannot be created twice; a Start()
	                                   local is one stray second call away from a fresh stream, and a
	                                   fresh stream is not a bug anyone would notice.

	It also makes the type `Random` rather than `Random?`, which deletes the nil branch that `nextFloat`
	would otherwise need — and the only honest thing that branch could do is error, inside a phase
	handler, where errors go to one swallowed warn.
]]
local rng = Random.new()

-- SERVER-ONLY state. pointsByName is the discovered pool, keyed by the part Name that IS the task Id.
local pointsByName: { [string]: BasePart } = {}

-- This round's five, and the parts they stand on. Server state; `activeParts` is what every distance
-- check measures against, so nothing anywhere caches a position.
local activeTasks: { Types.ActiveTask } = {}
local activeParts: { [string]: BasePart } = {}

-- One player's most recent claim to be holding something. SERVER-ONLY, never replicated, never
-- attributed. `At` is an os.clock() stamp; `TaskId` is what the SERVER resolved at the moment the
-- request arrived, never anything the client named.
type Presence = {
	TaskId: string,
	At: number,
}

local presence: { [number]: Presence } = {}

--[[
	C20. WHO HAS EVER FINISHED A TASK, and it is the single highest-leverage table in this file.

	Appendix C is a teardown of the nearest competitor: 2.5M visits, 1.43M players, $0 earned, and
	**79.9% of those players never completed a single objective**. §10 answers that one number by
	guaranteeing a brand-new player's first round hands them a task NEAR THEM with a waypoint, instead
	of dropping them into a dark map and hoping.

	IN MEMORY AND DELIBERATELY SO. C40 moves this into the persisted profile; until then it resets with
	the server, which means a returning player may be offered a first objective twice. That is the
	correct way round to be wrong — a veteran seeing one redundant waypoint costs a moment of mild
	irritation, and a beginner NOT seeing one costs the player.

	SERVER-ONLY, and it never goes on the wire as a set. `FirstObjectiveAssigned` is fired to one
	player at a time carrying a task Id; the roster of who is new is exactly the shape `GhostRoster`'s
	comment warns about and it stays here.
]]
local everCompleted: { [number]: boolean } = {}

-- The last YourTaskProgress each client was sent, so a bar that has not moved costs nothing. nil is a
-- meaningful value here: "this player is not standing on anything", and it must be SENT once so the
-- client can clear its bar.
--
-- The value type is `number?` rather than `number` BECAUSE of that: storing nil is how "I told them
-- the bar is empty" is recorded, and a non-optional value type makes the assignment in publishProgress
-- an analyze error. Reading a missing key and reading a stored nil are indistinguishable here, which
-- is exactly what the dedupe wants — both mean "the last thing this client heard was nothing".
local lastSentProgress: { [number]: number? } = {}

--[[
	THE TIMING BAR'S STATE (§4.4, C09). SERVER-ONLY, keyed by task Id.

	`BarStartAt` is seeded once, at the draw, and never reseeded. The bar therefore runs continuously
	for the whole round and every player standing at that point sees the SAME bar in the same place —
	which is what §4.4's world-owned progress means applied to a moving object, and what makes two
	players at one timing point a coherent thing to watch rather than two private minigames.

	`Hits` is the count of successful stops. A miss puts it back to zero — see Config's
	`TimingHitsRequired` for why that does not contradict §4.4's anti-frustration rule.

	It is a PARALLEL SERVER-ONLY TABLE rather than a widening of `Types.ActiveTask`. `ActiveTask` is a
	shared type; these two numbers are round state with no reason to be describable on a client, and
	putting them on the shared type would leave them one `FireClient` away from the wire.
]]
type TimingState = {
	BarStartAt: number,
	Hits: number,
}

local timingState: { [string]: TimingState } = {}

--[[
	FETCH state (§4.4, C09). SERVER-ONLY, keyed by task Id.

	`CarrierUserId` is the one piece of this that is genuinely private, and it is nil far more often
	than not. It is never attributed, never tagged and never sent: the ITEM's position states who is
	carrying it, one tick later, to everybody — which is the game working, and is why nothing here
	needs to cross the wire.
]]
type FetchState = {
	SourceName: string,
	Item: BasePart,
	CarrierUserId: number?,
}

local fetchState: { [string]: FetchState } = {}
local sourcesByName: { [string]: BasePart } = {}

-- `"{taskId}:{hits}"` for the last bar each client was sent, so a player standing at a timing point
-- doing nothing costs nothing. Same idea and the same lifecycle as `lastSentProgress`, and cleared in
-- the same place — a stale entry here would suppress the FIRST bar of the next round.
local lastSentBar: { [number]: string? } = {}

-- `presence` and `lastSentProgress` live up here with the rest of the round's state rather than beside
-- the code that uses them, because `clearTasks` below resets them and Luau resolves locals in
-- declaration order.
--
-- `lastTickAt` is NOT one of them and `clearTasks` does not touch it — an earlier version of this
-- comment said it did. It does not need clearing: `tick` reassigns it unconditionally before every
-- early return, so no elapsed time can accumulate across a phase gap.
local lastTickAt = os.clock()

local function nextFloat(): number
	return rng:NextNumber()
end

-- Vector3 -> the plain table pure/TaskSelection takes. The pure module cannot mention Vector3: Lune
-- has no Roblox datatypes. Converted at the call site, exactly as MonsterService does for
-- KillValidation.
local function toVec(position: Vector3): TaskSelection.Vec3
	return { X = position.X, Y = position.Y, Z = position.Z }
end

--[[
	Discovery. Rebuilt from scratch on every call rather than cached, because C17 will add, move and
	delete these parts while a server is running and a cached pool would hand out a point that no
	longer exists.

	SORTED BEFORE THE DRAW. `GetTagged` returns instances in an order this code does not control and
	should not inherit — RoleDraw's header makes the same argument for candidates. The draw here is
	seeded from server entropy so reproducibility is not the reason; removing a hidden, engine-defined
	input to a random selection is.
]]
local function discoverPool(): TaskPool.Report
	local names: { string } = {}

	table.clear(pointsByName)

	for _, instance in CollectionService:GetTagged(TAG_POINT) do
		if not instance:IsA("BasePart") then
			warn(
				`[TaskService] {instance:GetFullName()} is tagged {TAG_POINT} but is a `
					.. `{instance.ClassName}, not a BasePart — skipped.`
			)
			continue
		end

		table.insert(names, instance.Name)

		-- The `: BasePart?` is load-bearing under --!strict. Indexing a `{ [string]: BasePart }` yields
		-- a non-optional `BasePart`, and comparing THAT to nil is a type error rather than a lookup —
		-- the annotation is what restores the optional the runtime actually returns. Same at both
		-- lookups in `selectForRound`.
		local existing: BasePart? = pointsByName[instance.Name]

		if existing == nil then
			pointsByName[instance.Name] = instance
		end
	end

	table.sort(names)

	return TaskPool.evaluate(names, Config.Tasks.TotalRequired, Config.Tasks.PoolSize)
end

-- Rebuilt on every call for the same reason `discoverPool` is: C17 will add, move and delete these
-- parts while a server is running, and a cached source would hand out one that no longer exists.
local function discoverSources()
	table.clear(sourcesByName)

	for _, instance in CollectionService:GetTagged(TAG_SOURCE) do
		if not instance:IsA("BasePart") then
			warn(
				`[TaskService] {instance:GetFullName()} is tagged {TAG_SOURCE} but is a `
					.. `{instance.ClassName}, not a BasePart — skipped.`
			)
			continue
		end

		local existing: BasePart? = sourcesByName[instance.Name]

		if existing == nil then
			sourcesByName[instance.Name] = instance
		end
	end
end

--[[
	THE LOUD HALF, and the reason every warn here is UNGATED by VerboseLogging.

	This repo gates routine tracing and warns unconditionally for faults — RoundService's dropped round
	result and AntiCheatService's refusal both say so. An unusable task pool is a fault: the round runs,
	nobody can finish it, and the only symptom a player reports is "the game is boring". VerboseLogging
	is false on a published place, which is exactly where that report comes from.

	The EMPTY message names the tag and the count, because the person reading it is looking at an empty
	baseplate and needs to know what to do, not that something went wrong.
]]
local function reportPool(report: TaskPool.Report)
	if #report.Duplicates > 0 then
		warn(
			`[TaskService] TaskPoint parts share a Name and were skipped: `
				.. `{table.concat(report.Duplicates, ", ")}. The server identifies a task point BY its `
				.. `Name, so every tagged part must have a unique one.`
		)
	end

	if report.Verdict == "EMPTY" then
		warn(
			`[TaskService] NO "{TAG_POINT}" PARTS IN THE MAP. Tag {Config.Tasks.PoolSize} anchored `
				.. `parts with "{TAG_POINT}" via CollectionService, or no task can ever be completed `
				.. `and the escape gate can never open.`
		)
	elseif report.Verdict == "SHORT" then
		warn(
			`[TaskService] Only {#report.Unique} "{TAG_POINT}" part(s) found; `
				.. `{Config.Tasks.TotalRequired} are needed to open the gate. Rounds are unwinnable.`
		)
	elseif report.Verdict == "OVERSIZED" then
		warn(
			`[TaskService] {#report.Unique} "{TAG_POINT}" parts found, but Config.Tasks.PoolSize says `
				.. `{Config.Tasks.PoolSize}. The draw still works; the map and Config disagree.`
		)
	elseif Config.Debug.VerboseLogging then
		print(`[TaskService] Pool OK — {#report.Unique} task points.`)
	end
end

-- Written out rather than iterating `Enums.TaskType`, which is a frozen record and not an array. An
-- explicit list is what makes the loop below typecheck as `{ Types.TaskType }` under --!strict, and
-- it puts the map's whole vocabulary on four legible lines.
local TASK_TYPES: { Types.TaskType } = {
	Enums.TaskType.Hold,
	Enums.TaskType.Timing,
	Enums.TaskType.Fetch,
	Enums.TaskType.TwoPerson,
}

--[[
	The map's half of the type contract, and the one line C09 does not have to revisit discovery for.

	An absent attribute still means HOLD, and that default is now load-bearing rather than a
	placeholder: the rig has twelve pads and only a few of them will ever name a type.

	An attribute matching NOTHING is a map defect and stays loud. The warning is unconditional — this
	file's `reportPool` explains why the routine tracing is gated and the faults are not, and a task
	point silently demoted to HOLD is exactly the fault where the only symptom a player reports is
	"the game is boring".
]]
local function taskTypeOf(part: BasePart): Types.TaskType
	local requested = part:GetAttribute("TaskType")

	if requested == nil then
		return Enums.TaskType.Hold
	end

	--[[
		RETURNED BY INDEX, NOT BY THE LOOP VARIABLE, and that is a --!strict requirement rather than a
		style choice. `GetAttribute` returns `any`, so `requested == value` REFINES `value` to the type
		of `requested` — plain `string` — and returning it then fails to satisfy `Types.TaskType`.
		Reading the element back out of the annotated table gives the union again, with no cast.
	]]
	for index, value in TASK_TYPES do
		if requested == value then
			return TASK_TYPES[index]
		end
	end

	warn(
		`[TaskService] {part.Name} asks for TaskType "{requested}", which is not a TaskType. `
			.. `Using {Enums.TaskType.Hold}. Valid: {table.concat(TASK_TYPES, ", ")}.`
	)

	return Enums.TaskType.Hold
end

--[[
	THERE IS NO ProximityPrompt HERE ANY MORE, AND THE REASON IS WORTH KEEPING.

	C08 attached one for the affordance §4.4 names, then discovered its `KeyboardKeyCode` defaults to
	`E` — the key InputController binds through ContextActionService — and that the prompt WINS, so the
	hold never started. The fix set `KeyboardKeyCode = Enum.KeyCode.None`, which did free the key.

	IT ALSO STOPPED THE PROMPT RENDERING ENTIRELY, and nothing caught it because the fix was verified
	for the property it was aimed at (`E` reaches the server) rather than the one it was protecting
	(the player can see a task is here). Roblox's CoreScript refuses a prompt with no keycode:

	    ProximityPrompt 'TaskPrompt' has an unsupported keycode for rendering UI: Enum.KeyCode.None
	    CoreScripts/ProximityPrompt:385 - function createPrompt

	It throws inside `createPrompt`, so no UI is ever built. A manual playtest spent three rounds
	hunting for unmarked pads and logged `NO_TASK_IN_RANGE` 68 times. The old comment here claimed the
	prompt "keeps its label and its range and gives up its input" — it gave up all three.

	So the affordance moves to the client, where it can be drawn without asking a CoreScript for
	permission and without competing for a keypress: `client/Controllers/TaskController.luau` renders
	`ActiveTaskPoint` and `CompletedTaskPoint`. Both tags already replicate by design. The server's
	only job is to keep them true, which is what it was always for.
]]
--[[
	Torn down on the way into the LOBBY, not on the way out of ACTIVE — the same rule, for the same
	reason, as MonsterService's corpses. ENDING keeps this round's tasks so the end screen can show a
	round that finished 4/5, which is the screenshot §4.8 is about.
]]
local function clearTasks()
	for _, part in activeParts do
		CollectionService:RemoveTag(part, TAG_ACTIVE)
		CollectionService:RemoveTag(part, TAG_DONE)
	end

	-- The props go with the round. An item left parented to the workspace would be a grey cube that
	-- outlives its errand and that C17 would eventually find and wonder about.
	for _, state in fetchState do
		state.Item:Destroy()
	end

	table.clear(fetchState)
	table.clear(activeTasks)
	table.clear(activeParts)

	-- Presence and the send-dedupe both key off a round that no longer exists. Leaving lastSentProgress
	-- populated would suppress the first send of the NEXT round for any player whose new fill happened
	-- to equal their old one — a bar that starts the round refusing to move.
	table.clear(presence)
	table.clear(lastSentProgress)
	table.clear(timingState)
	table.clear(lastSentBar)

	-- Also resets the HUD's 5/5 during INTERMISSION, which enterIdle already did and
	-- enterIntermission never has.
	RoundService.SetTasksCompleted(0)
end

--[[
	THE DRAW (§4.4, C07). Five of twelve, at STARTING, from a pool discovered a line earlier.

	The chosen parts get the `ActiveTaskPoint` tag, WHICH REPLICATES TO EVERY CLIENT, and that is
	correct rather than tolerated. Players have to be able to find the objective; five ProximityPrompts
	appear on five parts and hiding that would be hiding the game from the people playing it. The line
	is this: what must never leak is the ability to know or derive the selection BEFORE it is made, and
	that is a property of `Random.new()` having no argument, not of the tag.

	`check:secrecy` inspects CollectionService tags, and this one passes because it carries no role and
	no UserId. It is named for a place, not for a person.
]]
local function selectForRound()
	local report = discoverPool()

	reportPool(report)

	local pool: { TaskSelection.Point } = {}

	for _, name in report.Unique do
		local part: BasePart? = pointsByName[name]

		if part ~= nil then
			table.insert(pool, { Id = name, Position = toVec(part.Position) })
		end
	end

	local chosen, spacingRespected = TaskSelection.select(
		pool,
		Config.Tasks.TotalRequired,
		Config.Tasks.MinSpacingStuds,
		nextFloat
	)

	--[[
		A map defect, and until now an invisible one. The draw asked for MinSpacingStuds between the
		chosen points and could not get it, so it fell back to an unspaced selection rather than run a
		short round. That is the right call — a 3/5 round can never open the gate — but it means the
		spread §4.4 asks for is gone this round, and two selected points may sit inside one presence
		radius.

		`taskPointAt` handles that safely now (nearest incomplete wins), so this is a warning about the
		MAP rather than a fault in the round. It belongs with the other pool defects: unconditional,
		naming the number to change.
	]]
	if not spacingRespected then
		warn(
			`[TaskService] Task points are packed too tightly to honour `
				.. `Config.Tasks.MinSpacingStuds ({Config.Tasks.MinSpacingStuds} studs); this round's `
				.. `tasks are not spread. Move the {TAG_POINT} anchors further apart, or lower the setting.`
		)
	end

	for _, point in chosen do
		local part: BasePart? = pointsByName[point.Id]

		if part == nil then
			continue
		end

		table.insert(activeTasks, {
			Id = point.Id,
			Type = taskTypeOf(part),
			SpawnPointName = part.Name,
			Progress = 0,
			Completed = false,
		})

		activeParts[point.Id] = part
		CollectionService:AddTag(part, TAG_ACTIVE)

		-- Every task gets a bar, not only the TIMING ones. It costs two numbers, and it means a map
		-- edit that flips a pad to TIMING mid-round cannot land on a task with no bar to read.
		timingState[point.Id] = { BarStartAt = os.clock(), Hits = 0 }
	end

	--[[
		A round that drew fewer than TotalRequired can never reach 5/5, so it can never open the gate.
		It is still a playable round — the sunrise timer and C06's attrition win both still work — and
		saying so is more useful than aborting it, because the person who needs to know is the one
		reading the console, not the eight players in the lobby.
	]]
	if #activeTasks < Config.Tasks.TotalRequired then
		warn(
			`[TaskService] Round drew {#activeTasks} of {Config.Tasks.TotalRequired} tasks. The escape `
				.. `gate cannot open this round.`
		)
	elseif Config.Debug.VerboseLogging then
		local ids = {}

		for _, entry in activeTasks do
			table.insert(ids, entry.Id)
		end

		print(`[TaskService] Round tasks: {table.concat(ids, ", ")}`)
	end
end

--[[
	THE ONE PLACE A CONTRIBUTION RATE IS DECIDED, and it delegates the decision to a pure module so the
	rule is a grid a terminal can fail rather than a claim in a comment.

	THE ASWANG CONTRIBUTES IN FULL, EXACTLY LIKE A SURVIVOR — Amendment A2 in docs/MVP-SPEC.md, which
	reverses §4.4's original "its progress does not count". An earlier version of this comment promised
	that C12 would make this return 0 for the Aswang; doing that would BUILD the role oracle §4.4 was
	trying to avoid. Task progress belongs to the world, so a task's fill is legible to anyone standing
	at it, and standing at it costs one keypress: a survivor taps interact beside whoever is holding,
	watches the bar sit frozen, and knows. C12's deception is what the Aswang is SHOWN, never what its
	hands do.

	`TaskWeight.forPlayer` takes the role and deliberately ignores it. Passing it is what lets
	`tests/task-weight.test.luau` assert the property across the whole PlayerState × Role domain.

	It asks RoundService for the player's state rather than keeping its own copy, exactly as
	MonsterService does. There is one owner of PlayerStates and this is not it.
]]
local function weightFor(player: Player): number
	--[[
		The role passed here is deliberately the SURVIVOR constant for every player, not a lookup.

		Reading the real role would mean this service asking RoundService.GetAswangUserId() on a hot
		path, four times a second, to feed a parameter the pure module is proven to ignore — a live
		reference to the secret with no purpose. The grid guarantees the answer cannot depend on it,
		so the honest thing is not to fetch it.
	]]
	return TaskWeight.forPlayer(
		RoundService.GetPlayerState(player),
		Enums.Role.Survivor,
		Config.Ghost.TaskContributionMult
	)
end

--[[
	WHERE A PLAYER IS, FROM WHICHEVER SOURCE OWNS IT — and there are two, because ghosts have no server
	character.

	A living player's position comes from their replicated `HumanoidRootPart`, which the server owns
	and a client cannot lie about. A GHOST's comes from `GhostService`, which holds what that ghost's
	own client last reported — because C15 removed server bodies for ghosts once an audit showed a
	replicated body per dead player names the dead set to every client.

	THE TRUST BOUNDARY MOVES FOR GHOSTS AND ONLY FOR GHOSTS, and it is worth being explicit that this
	function is where it moves. A ghost can claim to stand at a task point it is not at, and collect
	`TaskWeight`'s 0.25 from anywhere. `GhostService` bounds the lie — the report is refused unless the
	caller is a ghost, and refused again if it jumped further than `FlySpeed` allows — but it cannot
	eliminate it, and no design that keeps a ghost's position off the wire can.

	The living path is unchanged and must stay that way: if a future edit ever routes a LIVING player
	through a reported position, kills, task completion and the escape gate all become client-claimed.
]]
local function positionOf(player: Player): Vector3?
	local character = player.Character

	if character ~= nil then
		local root = character:FindFirstChild("HumanoidRootPart")

		if root ~= nil and root:IsA("BasePart") then
			return root.Position
		end
	end

	if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
		return GhostService.GetGhostPosition(player.UserId)
	end

	return nil
end

--[[
	WHICH selected task point is this player standing at, decided entirely from the server's own copy
	of the world.

	Returns `(nearest incomplete point in range, was anything in range at all)`. The second value is
	what lets the caller tell "you are nowhere near a task" from "everything near you is finished"
	without this function having to know about verdicts.

	NEAREST-INCOMPLETE, NOT FIRST-MATCH, AND THE CHANGE IS A SOFT-LOCK FIX.

	This loop used to return the first in-range point in `activeParts` iteration order, resting on
	`Config.Tasks.PresenceRangeStuds * 2 < MinSpacingStuds` to guarantee that at most one point could
	ever be in range. **That guarantee did not exist.** `MinSpacingStuds` is a REQUEST to
	`TaskSelection.select`, and its fallback pass drops the spacing entirely rather than return a short
	round. An exploit audit measured twelve points in one 30x30 room: 2000 of 2000 draws put two
	selected points inside a single presence radius.

	The old shape's failure was silent and unwinnable. A player standing squarely on an incomplete
	point B, while also overlapping a completed point A that happened to iterate first, resolved to A,
	was refused ALREADY_COMPLETE, and — correctly, for secrecy — was told nothing at all. The round
	sat at 4/5 and the gate never opened.

	Resolving to the nearest INCOMPLETE point makes overlapping selections merely untidy. Ambiguity is
	now decided by distance, which is both deterministic and the answer a player would expect, so the
	Config relation is defence in depth rather than the only thing between this and a dead round.
	`hash` order never decides anything again.

	`part.Parent ~= nil` guards a task point deleted from the map mid-round — a live risk while C17 is
	being built in a running Studio session, and a destroyed part keeps answering `.Position` forever.
]]
local function taskPointAt(player: Player): (string?, boolean)
	local position = positionOf(player)

	if position == nil then
		return nil, false
	end

	local completed: { [string]: boolean } = {}

	for _, task in activeTasks do
		if task.Completed then
			completed[task.Id] = true
		end
	end

	-- Converted at the call site, exactly as MonsterService does for KillValidation: the pure module
	-- cannot mention Vector3 because Lune has no Roblox datatypes.
	local points: { TaskResolve.Point } = {}

	for id, part in activeParts do
		if part.Parent == nil then
			continue
		end

		table.insert(points, {
			Id = id,
			Position = toVec(part.Position),
			Completed = completed[id] == true,
		})
	end

	return TaskResolve.at(points, toVec(position), Config.Tasks.PresenceRangeStuds)
end

local function taskById(id: string): Types.ActiveTask?
	for _, task in activeTasks do
		if task.Id == id then
			return task
		end
	end

	return nil
end

local function completedCount(): number
	local total = 0

	for _, task in activeTasks do
		if task.Completed then
			total += 1
		end
	end

	return total
end

local progressRemote = Remotes.Get("TaskProgressChanged")
local barRemote = Remotes.Get("TimingBarChanged")

--[[
	One task point's bar, to one player. Never FireAllClients.

	Per-player for the same reason `publishProgress` is, and the reason is a leak rather than a
	saving: `Hits` is a per-point fact that a bystander could read to infer who is standing where.
	Nobody needs it but the person aiming at the bar.

	Built as a TYPED LOCAL, not an inline table: FireClient takes `...any`, so an inline literal is
	checked against nothing at all. See Types.TimingBarPayload — the annotation catches a wrong type
	and a missing field, and NOT an extra one, which is the leak shape.
]]
local function publishBar(player: Player, taskId: string)
	local state = timingState[taskId]

	if state == nil then
		return
	end

	local key = `{taskId}:{state.Hits}`

	if lastSentBar[player.UserId] == key then
		return
	end

	lastSentBar[player.UserId] = key

	local payload: Types.TimingBarPayload = {
		TaskId = taskId,
		Phase = TimingWindow.phaseAt(os.clock() - state.BarStartAt, Config.Tasks.TimingBarPeriod),
		Period = Config.Tasks.TimingBarPeriod,
		GreenCenter = Config.Tasks.TimingGreenCenter,
		GreenHalfWidth = Config.Tasks.TimingGreenHalfWidth,
		--[[
			CEILED, AND THE ROUNDING IS A SECRECY FIX RATHER THAN A COSMETIC ONE.

			C16 made `state.Hits` FRACTIONAL, because a ghost's stop counts at `TaskContributionMult`
			(0.25). Sent raw, any non-integral value told a living client standing at this task point
			that a GHOST had contributed — i.e. at least one player is dead, and one of them is within
			`PresenceRangeStuds` of me right now. Amendment A3 says a client learns about a death by
			finding the body; this was a death bit and a ghost locator on a remote, with no body.

			The bar only ever renders "how many segments are lit", so the ceiling is what it wanted all
			along. It is the honest field: it rounds UP so a partial contribution is visible as
			progress rather than vanishing, and it carries no fractional part to read a state off.
		]]
		Hits = math.ceil(state.Hits),
		HitsRequired = Config.Tasks.TimingHitsRequired,
	}

	barRemote:FireClient(player, payload)
end

--[[
	THE TASK BAR (§4.4). FireClient per player, NEVER FireAllClients, and the reason is a leak rather
	than a saving.

	Two facts leave here. `TasksCompleted` / `TasksRequired` are the global bar and are identical for
	every player — §4.4's "overall progress, not who did what". `YourTaskProgress` is the fill of the
	one point the receiving player is standing on, and it reaches nobody else.

	BE PRECISE ABOUT WHAT PER-PLAYER FIRING BUYS, because an earlier version of this comment overstated
	it and pointed the next implementer somewhere dangerous.

	`YourTaskProgress` carries the WORLD's fill for that point, not the receiver's own contribution,
	and becoming "the person standing on it" costs one keypress. So firing per player restricts who
	ASKS, and anyone may ask. It is a bandwidth saving and a narrowing — not a seal.

	What actually makes this safe is Amendment A2: no task's fill is a function of anyone's role, so a
	frozen bar says "nobody is holding" and never "the holder is the Aswang". If a future change makes
	any player's contribution differ by role, this remote becomes a role oracle readable in two seconds
	by any bystander, and per-player firing will not save it. See `pure/TaskWeight.luau`.

	Built as a TYPED LOCAL, not an inline table: FireClient takes `...any`, so an inline literal is
	checked against nothing at all. The annotation catches a wrong type and a missing field but NOT an
	extra one — see Types.TaskProgressPayload, and note that a field named `PresentPlayerCount` would
	satisfy every check in this repo and reinstate the oracle above in one line.
]]
local function publishProgress(completionChanged: boolean)
	local completed = completedCount()

	for _, player in Players:GetPlayers() do
		local entry = presence[player.UserId]
		local yours: number? = nil

		if entry ~= nil then
			for _, task in activeTasks do
				if task.Id == entry.TaskId then
					yours = task.Progress

					if task.Type == Enums.TaskType.Timing and not task.Completed then
						publishBar(player, task.Id)
					end

					break
				end
			end
		else
			-- Walked away from a timing point. Forget what they were last sent so that coming back
			-- re-sends the bar rather than being deduped into silence.
			lastSentBar[player.UserId] = nil
		end

		if not completionChanged and yours == lastSentProgress[player.UserId] then
			continue
		end

		lastSentProgress[player.UserId] = yours

		local payload: Types.TaskProgressPayload = {
			TasksCompleted = completed,
			TasksRequired = Config.Tasks.TotalRequired,
			YourTaskProgress = yours,
		}

		progressRemote:FireClient(player, payload)
	end
end

--[[
	How long this task takes at full contribution. ONE FUNCTION, so a fifth task type at some later
	chunk has exactly one place to be wrong.

	TIMING never reaches here — the tick skips it — but it is listed rather than omitted, because an
	unlisted type falls through to HoldTime silently and that is the shape of a balance bug nobody
	reports.
]]
local function durationFor(task: Types.ActiveTask): number
	if task.Type == Enums.TaskType.Fetch then
		return Config.Tasks.FetchDeliverTime
	elseif task.Type == Enums.TaskType.TwoPerson then
		return Config.Tasks.TwoPersonTime
	end

	return Config.Tasks.HoldTime
end

--[[
	THE CARRY (§4.4, C09). One pass, on the same 4 Hz tick as everything else.

	IT DERIVES EVERY DECISION FROM A WEIGHT, never from a role or a state directly, so the rule
	`server/pure/FetchCarry.luau` implements is the rule that runs. `weightFor` is the same function
	the hold uses — see its comment for why the role it passes is a constant.

	`item.CFrame` IS ASSIGNED AT 4 Hz AND THAT IS A KNOWN, ACCEPTED ROUGHNESS. A carried item visibly
	steps rather than glides. The smooth version is a WeldConstraint to the carrier's root part, which
	needs the part unanchored and hands physics ownership to the carrying client — a change with a
	replication story this plan has not verified, on the one object in the round a player might want to
	desync. It is in Follow Ups for C18, where the item stops being a grey cube anyway.

	HOW THE DROP FINDS THE DEATH POSITION: it does not look one up. The tick has been re-anchoring the
	item to the carrier every 250 ms, so at the moment they die it is already within a quarter-second
	of where they fell, and dropping is nothing but ceasing to move it. That also sidesteps a real
	trap — `MonsterService` sets `player.Character = nil` to build the corpse BEFORE
	`RoundService.MarkKilled` runs, so a drop handler asking for the carrier's position would find
	none.
]]
local function tickFetch()
	for taskId, state in fetchState do
		local task = taskById(taskId)

		if task == nil or task.Completed then
			continue
		end

		local carrier = if state.CarrierUserId ~= nil
			then Players:GetPlayerByUserId(state.CarrierUserId)
			else nil
		local source: BasePart? = sourcesByName[state.SourceName]
		local point: BasePart? = activeParts[taskId]

		-- The nearest full-weight player standing at the source, if any. Nearest so that two players
		-- arriving together resolve deterministically rather than by hash order — the same argument
		-- `TaskResolve` makes at length.
		local candidate: Player? = nil
		local candidateWeight = 0

		if source ~= nil and carrier == nil then
			local bestDistance = Config.Tasks.PresenceRangeStuds

			for _, player in Players:GetPlayers() do
				local position = positionOf(player)

				--[[
					THE WEIGHT FILTER IS IN THE SELECTION, NOT DOWNSTREAM, AND THAT IS A C16 REGRESSION FIX.

					This loop picks ONE candidate — the nearest — and `FetchCarry.decide` then refuses it
					unless `CandidateWeight >= FullWeight`. There is no fallback to the next-nearest. That
					was safe while `positionOf` returned nil for anyone without a character, because only
					living players could ever enter the loop.

					C16 admitted ghosts to `positionOf`, and a ghost weighs 0.25. So a ghost standing at
					the fetch source won the nearest-candidate comparison and the decision came back NONE
					— **the item could never be picked up, 5/5 was unreachable, the gate never opened, and
					the survivors' win was gone for the round**. Deliberately, by reporting the source's
					own position (distance 0 beats any real HumanoidRootPart, which sits studs off the
					part centre); or by accident, whenever an honest ghost drifted near the source.

					Filtering here means a ghost is simply not a carrier candidate, and the nearest player
					who CAN carry is chosen instead.
				]]
				if position ~= nil and weightFor(player) >= Config.Tasks.FullContributionWeight then
					local distance = (position - source.Position).Magnitude

					if distance <= bestDistance then
						candidate = player
						candidateWeight = weightFor(player)
						bestDistance = distance
					end
				end
			end
		end

		local carrierPosition = if carrier ~= nil then positionOf(carrier) else nil
		local atDestination = carrierPosition ~= nil
			and point ~= nil
			and (carrierPosition - point.Position).Magnitude <= Config.Tasks.PresenceRangeStuds

		local action = FetchCarry.decide({
			HasCarrier = carrier ~= nil,
			CarrierWeight = if carrier ~= nil then weightFor(carrier) else 0,
			CarrierAtDestination = atDestination,
			CandidateWeight = candidateWeight,
			CandidateAtSource = candidate ~= nil,
			FullWeight = Config.Tasks.FullContributionWeight,
		})

		if action == "PICK_UP" and candidate ~= nil then
			state.CarrierUserId = candidate.UserId
		elseif action == "DROP" then
			-- Nothing is moved. The item is already lying wherever the tick last put it, which is
			-- within 250 ms of where the carrier stopped being one. That IS the drop.
			state.CarrierUserId = nil
		end

		-- Re-read: PICK_UP set it this tick, and the item should follow immediately rather than
		-- staying at the source for one more frame.
		local holder = if state.CarrierUserId ~= nil
			then Players:GetPlayerByUserId(state.CarrierUserId)
			else nil
		local holderPosition = if holder ~= nil then positionOf(holder) else nil

		if holderPosition ~= nil then
			local carried = holderPosition + CARRY_OFFSET

			state.Item.CFrame = CFrame.new(carried)
		end
	end
end

--[[
	THE SERVER TICK. C08's "server-timed", literally: `elapsed` is measured here, from the server's own
	clock, and it is the only quantity that moves a bar.

	This is what makes "a client spamming RequestTaskProgress gains nothing" true by CONSTRUCTION
	rather than by a rate limit. The limiter bounds how often a client may ask; this loop makes the
	answer independent of how often it asked. A thousand requests a second and four requests a second
	accumulate exactly the same amount, because neither number appears anywhere below.

	DISTANCE IS RE-MEASURED HERE, not trusted from the stamp. A presence entry says "this player
	asserted, recently, that they are holding task X"; this loop asks the world whether they still are.
	Without it the grace window is a teleport-and-idle exploit worth PresenceGraceSeconds of free
	progress per request, which is small and would never have shown up in a playtest.

	Assigning nil to the key currently being visited is defined behaviour in Lua's `next` traversal;
	inserting a new key during one is not, and nothing here does.
]]
local function tick()
	local now = os.clock()
	local elapsed = now - lastTickAt

	lastTickAt = now

	if RoundService.GetPhase() ~= Enums.RoundPhase.Active or #activeTasks == 0 then
		return
	end

	-- BEFORE the weight pass, so a pickup this tick is visible to it, and after the ACTIVE guard above
	-- so it cannot run outside a round.
	tickFetch()

	local weights: { [string]: { number } } = {}

	for userId, entry in presence do
		local player = Players:GetPlayerByUserId(userId)

		if player == nil or now - entry.At > Config.Tasks.PresenceGraceSeconds then
			presence[userId] = nil
			continue
		end

		-- Explicitly discarding the second return value: at tick time "something was in range but it
		-- was finished" is not different from "nothing was in range" — either way this player is not
		-- advancing the point they claimed.
		local resolved = taskPointAt(player)

		if resolved ~= entry.TaskId then
			continue
		end

		--[[
			A FETCH task advances only for the player carrying its item. Standing at the destination
			empty-handed is not the task; walking to the source and back is.

			This reads `fetchState` rather than a role or a name, so it is the same rule for everyone.
		]]
		local fetch = fetchState[entry.TaskId]

		if fetch ~= nil and fetch.CarrierUserId ~= userId then
			continue
		end

		local bucket = weights[entry.TaskId]

		if bucket == nil then
			bucket = {}
			weights[entry.TaskId] = bucket
		end

		table.insert(bucket, weightFor(player))

		--[[
			C20. MARKED ON CONTRIBUTION, NOT ON COMPLETION, and the difference is the whole finding.

			This first collected a per-tick `contributors` table and marked only whoever happened to be
			standing there on the tick the bar filled. That under-marks systematically rather than
			adversarially: do 95% of an eight-second hold, step off for the last interval, and the
			server never records that you have ever done a task — so you are offered a beginner's
			waypoint every round forever. The adversarial version is the same move done on purpose.

			§10 wants "has ever completed a task" as a proxy for "knows what a task is", and advancing
			one is the moment you learn that. Marking here — in the same pass that decided your presence
			counts for progress — makes the flag mean what the spec meant, and makes it unavoidable
			without also declining to play.

			The inverse stays closed, which is the half that matters for exploitability: `presence` is
			written only by `notePresence` from a player's own `RequestTaskProgress`, so a client can
			still only ever mark ITSELF.
		]]
		everCompleted[userId] = true
	end

	local anyCompleted = false

	for _, task in activeTasks do
		if task.Completed then
			continue
		end

		-- A TIMING task advances ONLY through `noteTimingStop`. Presence at one buys the bar and
		-- nothing else. Without this line the task has two independent progress sources and the
		-- faster one wins, which would be the hold.
		if task.Type == Enums.TaskType.Timing then
			continue
		end

		local weight = TaskProgress.strongestWeight(weights[task.Id] or {})

		--[[
			§4.4's two-person task (C10). "Requires 2 survivors present at once."

			The requirement is checked against the WEIGHTS the pass above already collected, so the
			answer comes from `TaskWeight` and cannot depend on who anybody is — see
			`server/pure/TaskParticipants.luau`'s header, and Amendment A2, which makes the Aswang a
			full participant deliberately. A survivor-and-Aswang pair completes this task normally.

			Zeroing the weight rather than skipping the task is what makes the bar FREEZE instead of
			resetting when the second person walks away — §4.4's anti-frustration rule, delivered by
			`TaskProgress.tick`'s existing `weight <= 0` guard rather than by new code here.

			It does NOT go faster with three people. The max rule still governs the rate; the
			participant count only governs whether the rate is nonzero.
		]]
		if
			task.Type == Enums.TaskType.TwoPerson
			and not TaskParticipants.meets(
				weights[task.Id] or {},
				Config.Tasks.TwoPersonParticipants,
				Config.Tasks.FullContributionWeight
			)
		then
			weight = 0
		end

		local result = TaskProgress.tick(task.Progress, elapsed, weight, durationFor(task))

		task.Progress = result.Progress

		if result.Completed then
			task.Completed = true
			anyCompleted = true

			-- The only replicated evidence that this point is finished. Added here rather than in
			-- `publishProgress` because completion is a one-way edge and this is where it is decided;
			-- a client that joins later reads the tag off CollectionService and renders it correctly
			-- with no catch-up message needed.
			local donePart: BasePart? = activeParts[task.Id]

			if donePart ~= nil then
				CollectionService:AddTag(donePart, TAG_DONE)
			end

			-- The errand is over, so the prop goes. Leaving it welded to a survivor for the rest of
			-- the round is a permanent, replicated marker on one player, which is a thing this game
			-- should never grow casually.
			local fetch = fetchState[task.Id]

			if fetch ~= nil then
				fetch.Item:Destroy()
				fetchState[task.Id] = nil
			end

			if Config.Debug.VerboseLogging then
				print(`[TaskService] Task complete: {task.Id}`)
			end
		end
	end

	if anyCompleted then
		RoundService.SetTasksCompleted(completedCount())
	end

	publishProgress(anyCompleted)
end

--[[
	Everything the server checks before it believes a player is standing on a task.

	Returns a verdict AND the resolved task Id, because the caller needs both and deriving the Id twice
	is how the two answers drift apart. The verdict is for the LOG ONLY — read Types.TaskProgressVerdict
	before echoing any of it anywhere.

	NOT_ALIVE CHANGED AT C16, exactly as this comment predicted it would. §4.7 wants a GHOST to
	contribute at a reduced rate, so the gate is now an ALLOWLIST of ALIVE and GHOST and `weightFor`
	supplies the 25% difference — which it has been able to do since C08, unreachably, because this
	line refused ghosts before `weightFor` was ever consulted.

	AN ALLOWLIST, NOT `~= "SPECTATOR"`. The denylist form reads identically today and admits LOBBY, and
	a lobby player holding a task point between rounds would advance a bar for a round that has not
	been drawn.
]]
local function evaluatePresence(player: Player): (Types.TaskProgressVerdict, string?)
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return "WRONG_PHASE", nil
	end

	local presenceState = RoundService.GetPlayerState(player)

	if presenceState ~= Enums.PlayerState.Alive and presenceState ~= Enums.PlayerState.Ghost then
		return "NOT_ALIVE", nil
	end

	--[[
		`taskPointAt` already skips completed points, so a nil id with something in range means every
		point the player is standing near is finished. The completion re-scan that used to live here is
		gone with it — it could only ever contradict the resolver.

		Both branches are equally silent to the client (`notePresence` returns nothing on any refusal);
		the distinction exists for the server log alone.
	]]
	local id, anyInRange = taskPointAt(player)

	if id == nil then
		return (if anyInRange then "ALREADY_COMPLETE" else "NO_TASK_IN_RANGE"), nil
	end

	return "OK", id
end

--[[
	THE ONLY THING A CLIENT CAN DO TO A TASK: assert that it is present. It cannot report progress and
	it cannot report completion, which is C08's stated rule, and the shape here is what makes that
	structural rather than enforced — there is no argument in which a completion could arrive.

	EVERY REFUSAL RETURNS NOTHING. No verdict, no false, no error. Types.TaskProgressVerdict explains
	why in full; the short version is that no verdict names a role under Amendment A2, but the set
	still describes the round's private state — NO_TASK_IN_RANGE would tell a client which of the
	twelve points are live faster than walking there would. There is no safe subset to send.

	The stamp records the SERVER's resolution of which task point, never anything the client named,
	and the tick re-checks it anyway.
]]
local function notePresence(player: Player)
	local verdict, id = evaluatePresence(player)

	if verdict ~= "OK" or id == nil then
		if Config.Debug.VerboseLogging then
			-- Server console only, and off on a published place. It names the player and the verdict,
			-- neither of which is a role under Amendment A2 — but this window is visible to whoever is
			-- running Play Solo, so keep it that way.
			print(`[TaskService] Refused progress for {player.Name}: {verdict}`)
		end

		return
	end

	presence[player.UserId] = { TaskId = id, At = os.clock() }
end

--[[
	Everything the server checks before it believes a timing stop.

	DELIBERATELY THE SAME SHAPE AND THE SAME ORDER AS `evaluatePresence`, including returning the
	resolved Id alongside the verdict. Two validators over one surface that check the same things in
	different orders is how one of them acquires a hole nobody can see by reading either.

	The verdict is for the LOG ONLY and is never echoed — read Types.TimingVerdict. MISS in particular
	looks harmless and is not: it is the one value that would let a client distinguish "I was refused"
	from "I was wrong", and a client that can tell those apart can binary-search the green zone
	without ever rendering a bar.
]]
local function evaluateTimingStop(player: Player): (Types.TimingVerdict, string?)
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return "WRONG_PHASE", nil
	end

	-- The SAME allowlist as evaluatePresence, changed in the same edit. These two functions are
	-- deliberately the same shape and the same order; a ghost admitted to one and refused by the other
	-- would be able to hold a bar but never stop it, which reads as a broken task rather than a rule.
	-- NOT `timingState` — that name is already a module-level table of TimingState, and selene caught
	-- the shadow. A local that quietly hides a service's own state table is how two things called the
	-- same thing start being edited as though they were one.
	local stopperState = RoundService.GetPlayerState(player)

	if stopperState ~= Enums.PlayerState.Alive and stopperState ~= Enums.PlayerState.Ghost then
		return "NOT_ALIVE", nil
	end

	local id, anyInRange = taskPointAt(player)

	if id == nil then
		return (if anyInRange then "ALREADY_COMPLETE" else "NO_TASK_IN_RANGE"), nil
	end

	local task = taskById(id)

	if task == nil or task.Type ~= Enums.TaskType.Timing then
		return "NOT_A_TIMING_TASK", nil
	end

	return "OK", id
end

--[[
	THE STOP. The server reads its own clock; nothing a client sent is an input to the decision.

	`os.clock()` is sampled ONCE, at the top, and reused. Sampling it again inside the hit test would
	make the decision and the bar the player is subsequently sent describe two different moments —
	microseconds apart, and therefore a bug that appears only under load.
]]
local function noteTimingStop(player: Player)
	local now = os.clock()
	local verdict, id = evaluateTimingStop(player)

	if verdict ~= "OK" or id == nil then
		if Config.Debug.VerboseLogging then
			print(`[TaskService] Refused timing stop for {player.Name}: {verdict}`)
		end

		return
	end

	local state = timingState[id]
	local task = taskById(id)

	if state == nil or task == nil or task.Completed then
		return
	end

	local hit = TimingWindow.isHit({
		Elapsed = now - state.BarStartAt,
		Period = Config.Tasks.TimingBarPeriod,
		GreenCenter = Config.Tasks.TimingGreenCenter,
		GreenHalfWidth = Config.Tasks.TimingGreenHalfWidth,
		GraceSeconds = Config.Tasks.TimingGraceSeconds,
	})

	--[[
		WEIGHTED, SINCE C16, AND UNWEIGHTED WAS A LIVE BUG.

		This line read `state.Hits + 1`. Step 8.1 opened `evaluateTimingStop` to ghosts, which meant a
		dead player's stop counted at FULL rate — routing around §4.7's 25% entirely, and around
		`pure/TaskWeight`, `TaskParticipants` and the `config.test.luau` pin that all encode it. The
		presence path was correctly weighted (`weightFor` at its accrual); only timing was not, so
		ghosts could complete TIMING tasks at a living player's speed and hand the survivors the
		escape win.

		FRACTIONAL HITS ARE THE POINT. `Hits` is compared against `TimingHitsRequired` and divided by
		it for the bar, so a ghost needs four successful stops where a survivor needs one, and both
		read as a bar that fills at the rate their contribution deserves. A miss still resets to zero
		for everybody — the penalty is not scaled, because failing the window is failing the window.
	]]
	--[[
		A GHOST'S MISS IS A NO-OP, NOT A RESET, AND THIS IS A SABOTAGE FIX.

		`state.Hits` is PER TASK and shared by everyone working it, so `else 0` zeroed the survivors'
		accumulated progress whoever missed. Once Step 8.1 admitted ghosts to this handler, that made
		a dead player a denial-of-service: fly to a timing point, press stop about once a second —
		inside the sustained rate-limit budget, no exploit needed — and at a 1.8s sweep at least one
		press lands outside the green zone every sweep, so the bar can never be completed while the
		ghost stands there. Invisible, unkillable, untargetable, and it denies the escape win for the
		whole round.

		§4.7 gives a ghost the ability to CONTRIBUTE. It does not give them the ability to sabotage,
		and "a dead player affecting a living fight" is the exact line the corpse raycast exclusion and
		the whole `CanQuery` argument exist to hold.

		Zero is the penalty for failing the window as a participant who can be punished for it. A ghost
		cannot be punished — they are already dead — so their miss simply does not count, the same way
		their hit counts for a quarter.
	]]
	local weight = weightFor(player)

	if hit then
		state.Hits += weight
	elseif RoundService.GetPlayerState(player) == Enums.PlayerState.Alive then
		state.Hits = 0
	end
	--[[
		QUANTISED FOR THE SAME REASON `publishBar` CEILS `Hits`, and this is the sibling field that fix
		missed. `task.Progress` rides `YourTaskProgress` to every player standing at this point, and
		`state.Hits / 3` with a ghost's 0.25 in it yields 0.0833… where every living hit yields a
		multiple of 1/3. Reading a non-multiple off that remote proved at least one player was dead AND
		within `PresenceRangeStuds` of you — a death signal and a ghost locator, which A3 forbids.

		Ceil the hits, then divide: the bar renders lit segments, so this is the number it wanted.
	]]
	task.Progress = math.clamp(math.ceil(state.Hits) / Config.Tasks.TimingHitsRequired, 0, 1)

	local completed = false

	if state.Hits >= Config.Tasks.TimingHitsRequired then
		task.Completed = true
		task.Progress = 1
		completed = true

		--[[
			C20. THE ONE PATH THE PRESENCE SWEEP CANNOT SEE.

			A TIMING point advances only through this function — `tick` skips TIMING entirely — and a
			player can press R without ever having held E, in which case they have no `presence` entry
			and the contribution marking in `tick` never runs for them. So the flag is set here too.

			It is set on COMPLETION here rather than on each hit, unlike the hold path, and that
			asymmetry is deliberate: `state.Hits` is shared across everyone stopping the bar, so
			crediting every stopper on every hit would mark players who merely stood nearby and tapped
			once. Landing the final hit is unambiguously having done the task.
		]]
		everCompleted[player.UserId] = true

		RoundService.SetTasksCompleted(completedCount())

		if Config.Debug.VerboseLogging then
			print(`[TaskService] Task complete: {task.Id}`)
		end
	end

	publishBar(player, task.Id)
	publishProgress(completed)
end

local function onPlayerRemoving(player: Player)
	presence[player.UserId] = nil
	lastSentProgress[player.UserId] = nil
	lastSentBar[player.UserId] = nil
end

--[[
	One fetch item per FETCH task drawn this round.

	A `FETCH` task with no source available is DEMOTED TO HOLD and says so, loudly. The alternative —
	a task that can never be started — is a round stuck at 4/5 with no symptom, which is the exact
	failure class `taskPointAt`'s nearest-incomplete fix was written to delete. A demoted task is
	playable and wrong; an unstartable one is unplayable and silent.
]]
local function setUpFetchTasks()
	discoverSources()

	local used: { [string]: boolean } = {}

	for _, task in activeTasks do
		if task.Type ~= Enums.TaskType.Fetch then
			continue
		end

		local point: BasePart? = activeParts[task.Id]

		if point == nil then
			continue
		end

		local named = point:GetAttribute("FetchSourceName")
		local source: BasePart? = if typeof(named) == "string" then sourcesByName[named] else nil

		if source == nil then
			-- FURTHEST unused, because the travel IS the task (§4.4). Pairing a task point with its
			-- NEAREST source would buy none of the isolation the fetch task exists to create.
			local bestDistance = -1

			for name, candidate in sourcesByName do
				local distance = (candidate.Position - point.Position).Magnitude

				if not used[name] and distance > bestDistance then
					source = candidate
					bestDistance = distance
				end
			end
		end

		if source == nil then
			warn(
				`[TaskService] {task.Id} asks for {Enums.TaskType.Fetch} but no unused "{TAG_SOURCE}" `
					.. `part is available. Demoting it to {Enums.TaskType.Hold} — tag more source `
					.. `anchors, or the round is one task harder than it looks.`
			)

			task.Type = Enums.TaskType.Hold
			continue
		end

		used[source.Name] = true

		local item = Instance.new("Part")

		item.Name = `FetchItem_{task.Id}`
		item.Size = Vector3.one -- config-ok: placeholder prop dimensions, replaced by a model at C17
		item.Anchored = true
		item.CanCollide = false
		item.CFrame = source.CFrame
		item.Parent = workspace

		CollectionService:AddTag(item, TAG_ITEM)

		fetchState[task.Id] = { SourceName = source.Name, Item = item, CarrierUserId = nil }
	end
end

local listRemote = Remotes.Get("TaskListAssigned")

--[[
	🔒 C12. WHAT EACH PLAYER IS TOLD (§4.4 + Amendment A2).

	One loop, every player, one payload shape, one moment. Survivors receive this round's real five;
	the Aswang receives a decoy five. NOTHING about the send distinguishes them — not the timing, not
	the field, not the count (`server/pure/TaskListView.luau` guarantees the length) — which is the
	property that still holds when a client is compromised and logging its own traffic.

	THE DECOY IS DRAWN, NOT CONSTRUCTED. It comes off the same pool through the same
	`TaskSelection.select` and the same `nextFloat`, so it looks exactly like a real draw: spaced the
	same way, five points, from the twelve. It is NOT made disjoint from the real five, and that is
	deliberate — a decoy guaranteed never to overlap is a decoy an Aswang can partially invert by
	elimination.

	THE SECRET IS READ HERE, ONCE, AND THE READ CARRIES A WAIVER. `check-secrecy`'s rule 5 makes this
	file role-blind precisely because `TaskWeight`'s grid only guarantees one function and the oracle's
	natural home is its callers. C12 is the sanctioned exception the rule's own comment names: the
	decision genuinely needs the role, once, at STARTING. Compare `weightFor` next door, which refuses
	to fetch it — that argument ("a live reference to the secret with no purpose", four times a second,
	to feed a parameter proven to be ignored) does not apply here, and the difference is the point.

	THE PAYLOAD MUST BE A TYPED LOCAL AND NOT AN INLINE TABLE, for two independent reasons. FireClient
	takes `...any`, so an inline literal is checked against nothing at all — Types.luau says so in
	three places. And `check-secrecy.mjs` tests the raw ARGUMENT TEXT of every FireClient against a
	role token: inlining `TaskListView.forPlayer(realIds, decoyIds, role)` into the call would put the
	word `role` in that text and turn this line red. Both facts point the same way.

	Players who join AFTER this runs get no list. They are SPECTATORs (§6.4) and are not in the round;
	the next STARTING deals them in and sends them one.
]]
local function publishTaskLists()
	local realIds: { string } = {}

	for _, task in activeTasks do
		table.insert(realIds, task.Id)
	end

	-- Rebuilt from `pointsByName`, which `selectForRound` has just populated — NOT by calling
	-- `discoverPool` again, which would re-emit every pool warning a second time per round.
	local pool: { TaskSelection.Point } = {}

	for name, part in pointsByName do
		table.insert(pool, { Id = name, Position = toVec(part.Position) })
	end

	-- The second return value is the spacing flag. Discarded on purpose: `selectForRound` has already
	-- warned about an unspaced draw this round, and a decoy that is not spread is a decoy.
	local decoy = TaskSelection.select(
		pool,
		Config.Tasks.TotalRequired,
		Config.Tasks.MinSpacingStuds,
		nextFloat
	)

	local decoyIds: { string } = {}

	for _, point in decoy do
		table.insert(decoyIds, point.Id)
	end

	--[[
		Read ONCE per round, into a local that leaves scope with this function. Never stored, never
		attributed, never tagged, never sent. This is the exception `check-secrecy`'s rule 5 sanctions
		by name, and the waiver below is what puts it in a diff where it can be argued with.

		The local is `aswangUserId`, lower-cased, and that is not incidental: rule 5's token list
		includes `AswangUserId`, so a capitalised local would trip the rule a second time on its own
		name and need a second waiver for nothing.
	]]
	local aswangUserId = RoundService.GetAswangUserId() -- secrecy-ok: C12 addresses the decoy list

	for _, player in Players:GetPlayers() do
		--[[
			`shownRole`, not `role`. The name is load-bearing in the same way the typed local is:
			`check-secrecy.mjs` scans FireClient argument text for a role token, and while this local
			does not appear in that text today, a later refactor that inlines one line would fail
			loudly rather than quietly. It also says the true thing — this is the role the player is
			being shown a list AS, which for exactly one player is a lie.
		]]
		local shownRole: Types.Role = if player.UserId == aswangUserId
			then Enums.Role.Aswang
			else Enums.Role.Survivor

		local payload: Types.TaskListPayload = {
			TaskIds = TaskListView.forPlayer(realIds, decoyIds, shownRole),
		}

		listRemote:FireClient(player, payload)
	end
end

--[[
	C20 — THE GUARANTEED FIRST OBJECTIVE (§10).

	Appendix C.2 is the whole argument: 79.9% of a competitor's 1.4M players never completed one
	objective, and that game had seven zones, a mountain and unlockable weapons. It did not fail for
	lack of content. A brand-new player spawns into a dark map with five task points somewhere in it
	and no reason to believe any particular direction is correct, and §10's answer is to remove that
	one decision — pick the nearest live task and point at it.

	BIASED TO SPAWN PROXIMITY, which is the entire mechanism and the reason this runs at ACTIVE rather
	than at STARTING. At STARTING players are mid-teleport and `positionOf` answers with wherever their
	body happens to be, so "nearest" would be nearest to the last round's corpse. By ACTIVE everyone is
	standing on the plaza spawn.

	FIRED TO ONE PLAYER AT A TIME. Never a broadcast, never a roster — see the remote's own comment in
	`Remotes.luau`. The payload is a task Id already public via `TaskListAssigned` and the
	`ActiveTaskPoint` tag; what is private is only that THIS player was sent one.

	THE ASWANG GETS ONE TOO, if they are new. That is deliberate rather than an oversight: skipping
	them would mean the set of players who receive this remote is "new survivors", and a new Aswang
	would notice they alone were dropped in without the help every other beginner describes in chat.
	Amendment A2 already makes the Aswang a full task participant, so the waypoint points at something
	they can genuinely do. It does point at a REAL task while C12 shows them a decoy list — see the
	remote's declaration in `Remotes.luau` for why that costs coherence and not information.

	A PLAYER WHO JOINS MID-ROUND GETS NOTHING THIS ROUND, and that is correct rather than a gap. This
	runs once per ACTIVE transition over the players present at that moment, so a latecomer is not in
	the loop — and they would be skipped anyway, because §6.4 makes a mid-round joiner a SPECTATOR and
	the state check below admits only ALIVE. A spectator cannot advance a task, so a waypoint would be
	pointing them at something they are not allowed to do. They are dealt in at the next round and get
	their first objective then. Recorded because "the new player got no waypoint" is otherwise exactly
	the shape of a bug report.
]]
local function assignFirstObjectives()
	local remote = Remotes.Get("FirstObjectiveAssigned")

	for _, player in Players:GetPlayers() do
		if everCompleted[player.UserId] then
			continue
		end

		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
			continue
		end

		local from = positionOf(player)

		if from == nil then
			continue
		end

		local bestId: string? = nil
		local bestDistance = math.huge

		for _, task in activeTasks do
			if task.Completed then
				continue
			end

			local part: BasePart? = activeParts[task.Id]

			if part == nil then
				continue
			end

			local distance = (part.Position - from).Magnitude

			if distance < bestDistance then
				bestDistance = distance
				bestId = task.Id
			end
		end

		if bestId ~= nil then
			remote:FireClient(player, bestId)

			if Config.Debug.VerboseLogging then
				-- A UserId and a task Id. No role, and no statement about anyone else.
				print(
					`[TaskService] C20 first objective for {player.UserId}: {bestId} `
						.. `({math.floor(bestDistance)} studs)`
				)
			end
		end
	end
end

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Active then
		assignFirstObjectives()
	end

	if phase == Enums.RoundPhase.Starting then
		clearTasks()
		selectForRound()
		-- Called from here rather than from inside `selectForRound`, which is where the plan put it:
		-- `setUpFetchTasks` needs `taskById`/`activeParts` and is declared below `selectForRound`, and
		-- Luau resolves locals in declaration order. Running it on the next line is equivalent — the
		-- draw has finished and `activeTasks` is complete.
		setUpFetchTasks()
		publishTaskLists()
	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearTasks()
	end
end

function TaskService.Init() end

function TaskService.Start()
	--[[
		DISCOVERY RUNS AT BOOT, not only at STARTING, and that is the difference between this service
		and the stub it replaces. On a map with no anchors the operator learns at server start — while
		they are still looking at the output window — rather than 45 seconds later when the first round
		draws nothing and nobody is watching.
	]]
	reportPool(discoverPool())

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	--[[
		THE RATE LIMIT LIVES HERE, INLINE, for the reason MonsterService's two handlers spell out:
		`check-ratelimit.mjs` matches the Consume call within 1200 characters of the connect site, so a
		handler that IS limited but does it 200 lines away reads as unguarded and fails the build. A
		reader skimming the connect site should see the guard without following a call.

		Consume FIRST, before any state is read. This is the highest-frequency remote in the game — an
		honest client sends four a second while holding — so a handler that validated first would be
		doing five reads and a distance sweep per refused request, which is what makes a remote worth
		spamming even when it achieves nothing.

		NO `typeof` GUARD, BECAUSE THERE IS NO ARGUMENT. `RequestKill` needs one precisely because it
		accepts a target; this signature ignores anything a client sends, so a table, a function or a
		4 MB string arrives and is discarded by the argument list itself.
	]]
	Remotes.Get("RequestTaskProgress").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTaskProgress") then
			return
		end

		notePresence(player)
	end)

	--[[
		Consume FIRST, before any state is read, for the reason the handler above states. This remote
		is the one in the game where spamming has a theoretical payoff — enough stops per sweep and
		one lands inside the zone by arithmetic rather than by skill — so the limiter is doing real
		work here rather than only bounding cost. The miss-resets-to-zero rule is the other half:
		a burst of five stops that contains one hit and four misses ends at zero hits.

		NO `typeof` GUARD, BECAUSE THERE IS NO ARGUMENT. Anything a modified client sends is discarded
		by the argument list itself.
	]]
	Remotes.Get("RequestTimingStop").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTimingStop") then
			return
		end

		noteTimingStop(player)
	end)

	--[[
		§5's mobile budget, counted: one server-side loop at 4 Hz doing at most
		`#presence × #activeTasks` distance comparisons — with eight players and five tasks, forty
		subtractions a tick. No lights, no particles, no client-side per-frame work.
	]]
	task.spawn(function()
		while true do
			tick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
end

return TaskService
