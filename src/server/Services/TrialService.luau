--!strict
--[[
	TrialService — The Solo Trial: 90s single-player practice run.

	Milestone: M6
	Spec: docs/MVP-SPEC.md

	═══ HOW THIS RUNS WITHOUT TOUCHING A ROUND ═══════════════════════════════════

	C21's build-plan row names the risk in one sentence: "TrialService and RoundService sharing state
	is how you get a trial that ends a live round." Nothing in this file shares state with that one.
	What it does, in full:

	  · READS  RoundService.GetPhase()          — one query, to decide admission
	  · LISTENS RoundService.PhaseChanged       — to end sessions when the phase leaves IDLE
	  · WRITES nothing in RoundService, ever

	It does NOT call setPhase (a file-local in RoundService and unreachable from here by construction),
	EndRound, MarkKilled, GetAswangUserId, or touch state.PlayerStates. The trial's
	two tasks are counted in `sessions` below and never reach the round's task bar.

	ONE DIRECTION ONLY, and for the exact reason RoundService's own header gives about RoleService: a
	require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
	in IDLE forever looking precisely like "nobody has joined yet". RoundService must NEVER require
	this file back. If it ever needs something from here, invert it — expose a registration on this
	side rather than a require on that one.

	═══ THE ROUND WINS EVERY CONFLICT ════════════════════════════════════════════

	A round starting under a player mid-trial ABORTS THE TRIAL. It does not hold the round. Holding it
	would freeze up to two other players on a countdown for up to 90 seconds so one player's tutorial
	could finish, which is §9 item 3's "reads as broken, not as waiting" — the exact failure C24 in
	this same plan exists to delete. §9.1 is also explicit that the Trial's job is to get people INTO
	the multiplayer loop, so a real round starting is this feature succeeding.

	The abort lands on the transition into INTERMISSION, which Config.Round.Intermission gives 25
	seconds of runway before STARTING — enough to deliver the handoff line and walk back.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SaltThrow = require(Shared.pure.SaltThrow)
local TrialAdmission = require(Shared.pure.TrialAdmission)
local TrialTimeline = require(Shared.pure.TrialTimeline)
local Types = require(Shared.Types)
local AntiCheatService = require(script.Parent.AntiCheatService)
local RoundService = require(script.Parent.RoundService)

local TrialService = {}

-- WHY THIS EXISTS: the closest competitor lost 79.9% of players before their
-- first objective, and their game at least worked solo. Ours does not function
-- below MinPlayers. The Trial is both the tutorial and the low-population
-- fallback. See spec §9.1 and Appendix C.
--
-- SCOPE GUARD: this must never grow into a PvE campaign. Consumable content is
-- exactly what killed the competitor.

local TAG_POINT = "TaskPoint"
local ATTR_TRIAL_ONLY = "TrialOnly"
local TAG_TRIAL_SPAWN = "TrialSpawn"
local TAG_TRIAL_CHASE = "TrialChase"

--[[
	THE SESSION. Private to this file, keyed by UserId, and there is never more than one per player.

	`Fired` is the beat set TrialTimeline needs passed in — it is held HERE rather than in the pure
	module, which is what keeps that module pure and lets its test drive a whole 90 seconds in a loop.
]]
type Session = {
	StartedAt: number,
	TrialPhase: Types.TrialPhase,
	Fired: { [string]: boolean },
	TasksDone: number,
	Rig: Model?,
	ReturnCFrame: CFrame,
	-- Which trial points this session has already completed, and how long the player has been stood
	-- on the current one. Per-session rather than per-part: two players in separate trials must not
	-- share progress, and the parts themselves are shared map geometry.
	DonePoints: { [string]: boolean },
	HoldingPoint: string?,
	HeldFor: number,
	-- An `os.clock()` deadline, not a countdown, so a hitch cannot stretch a stun. 0 means "not
	-- stunned" rather than nil, which keeps every read a plain comparison.
	StunnedUntil: number,
	--[[
		THE POUCH IS OWNED BY THE SESSION, NOT LOOKED UP BY NAME.

		It used to be found with `workspace:FindFirstChild("TrialSaltPouch")`, which returns an
		arbitrary one when two exist — and `Trial.OfferBelowPlayerCount = 3` permits two concurrent
		sessions. Ending one trial destroyed whichever pouch the lookup happened to return, possibly
		the other player's, so their chase could never be stunned and their tutorial taught the
		opposite of C22's lesson. The reverse was worse: one player's pouch could stun the other
		player's rig from across the corner, because `stepRig` measured the FOUND pouch against ITS
		OWN rig with no ownership check.
	]]
	Pouch: BasePart?,
}

local sessions: { [number]: Session } = {}

local snapshotRemote = Remotes.Get("TrialSnapshot")

-- The Schedule shape TrialTimeline takes, built once. Read from Config so `check:config` stays happy
-- and so M12 can retune the trial without touching this file.
local function schedule(): TrialTimeline.Schedule
	return {
		SaltGivenAt = Config.Trial.SaltGivenAt,
		ScriptedChaseAt = Config.Trial.ScriptedChaseAt,
		SaltTaughtAt = Config.Trial.SaltTaughtAt,
		HandoffAt = Config.Trial.HandoffAt,
		Duration = Config.Trial.Duration,
	}
end

function TrialService.IsInTrial(userId: number): boolean
	return sessions[userId] ~= nil
end

--[[
	The trial zone's parts, rediscovered on every call for the same reason any tag-driven pool
	is: C17's generator adds, moves and deletes these while a server is running, and a cached part is
	one that may no longer exist.

	Returns empty until the greybox step has built the zone, and every caller tolerates that — a trial
	with no points is a trial whose tasks cannot be completed, which expires harmlessly at Duration
	rather than erroring.
]]
local function trialPoints(): { BasePart }
	local points: { BasePart } = {}

	for _, instance in CollectionService:GetTagged(TAG_POINT) do
		if instance:IsA("BasePart") and instance:GetAttribute(ATTR_TRIAL_ONLY) == true then
			table.insert(points, instance)
		end
	end

	return points
end

local function taggedPart(tag: string): BasePart?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			return instance
		end
	end

	return nil
end

local function trialSpawn(): BasePart?
	return taggedPart(TAG_TRIAL_SPAWN)
end

-- Where the rig appears at ScriptedChaseAt. The far end of the corner, so the player watches it
-- arrive — C22's tell is only learnable if it is seen coming rather than found already beside you.
local function trialChaseSpot(): BasePart?
	return taggedPart(TAG_TRIAL_CHASE)
end

-- Vector3 -> the plain table `pure/SaltThrow` takes. That module cannot mention Vector3: Lune has no
-- Roblox datatypes, and the whole module would stop being runnable from a terminal. Same helper
-- ItemService keeps for the same reason.
local function vec3(v: Vector3): SaltThrow.Vec3
	return { X = v.X, Y = v.Y, Z = v.Z }
end

local function rootOf(player: Player): BasePart?
	local character = player.Character

	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

--[[
	BEAT ID BACK INTO ITS LITERAL TYPE, as six `if`s rather than a cast. `attempts.md` in this plan
	directory records the eight things that do not work and the measurements behind them; the short
	version is that `TrialTimeline.dueBeats` returns `{ string }` — a LIST of a literal union does not
	survive `require`, though the SCALAR `phaseAt` returns does — and `id :: Types.TrialBeat` does not
	narrow a plain `string` back, it distributes across the union and yields six widened `string`s
	that cannot be narrowed at all.

	A literal written directly in a `return`, checked against an annotated return type, is narrowing
	the analyzer will do. Returning `nil` for an unknown id and dropping it loudly at the call site is
	also strictly better than a cast, which would have waved a bad id straight into the payload.
]]
local function asBeat(id: string?): Types.TrialBeat?
	if id == "BEAT_WELCOME" then
		return "BEAT_WELCOME"
	elseif id == "BEAT_TASKS" then
		return "BEAT_TASKS"
	elseif id == "BEAT_SALT_GIVEN" then
		return "BEAT_SALT_GIVEN"
	elseif id == "BEAT_TRANSFORM" then
		return "BEAT_TRANSFORM"
	elseif id == "BEAT_SALT_TAUGHT" then
		return "BEAT_SALT_TAUGHT"
	elseif id == "BEAT_HANDOFF" then
		return "BEAT_HANDOFF"
	end

	return nil
end

--[[
	THE PUSH, AND THE THREE RULES IT KEEPS.

	1. FireClient, never FireAllClients. Not because the payload is dangerous — it is not; a trial has
	   no secret in it — but because a broadcast would be RECEIVED BY PLAYERS NOT IN A TRIAL, and a
	   client that receives trial state has to decide whether to render it. That decision is a bug
	   waiting to happen and there is no reason to create it.

	2. It iterates `sessions`, not `Players:GetPlayers()`. A player with no session gets nothing at
	   all, which is what makes rule 1 true by construction rather than by a condition someone could
	   later invert.

	3. The payload is `Types.TrialSnapshot` and shares no field name with `ClientRoundSnapshot`. That
	   is the answer to the semantic overlap `check:remotes` and `check:secrecy` structurally cannot
	   see: both are text tripwires, and a trial payload shaped like a round payload would pass both
	   while letting UIController render a trial timer as a sunrise timer.
]]
local function pushSnapshot(userId: number, beat: string?)
	local session = sessions[userId]
	local player = Players:GetPlayerByUserId(userId)

	if session == nil or player == nil then
		return
	end

	local elapsed = os.clock() - session.StartedAt

	local payload: Types.TrialSnapshot = {
		TrialPhase = session.TrialPhase,
		Beat = asBeat(beat),
		TrialSecondsLeft = math.max(0, Config.Trial.Duration - elapsed),
		TrialTasksDone = session.TasksDone,
		TrialTasksRequired = Config.Trial.TasksToComplete,
	}

	snapshotRemote:FireClient(player, payload)
end

--[[
	ONE EXIT, FIVE REASONS (Types.TrialEndReason). Every path out of a session goes through here so
	that teardown cannot be partially done: the rig is destroyed, the character goes back where it
	came from, and the entry leaves the table.

	IDEMPOTENT ON PURPOSE. `endSession` is reachable from the timer, the remote, PlayerRemoving and
	the phase change, and at least two of those can land in the same frame — a player pressing "leave"
	as a round starts. A second call must be a no-op rather than a second teleport.
]]
local function endSession(userId: number, reason: Types.TrialEndReason)
	local session = sessions[userId]

	if session == nil then
		return
	end

	--[[
		THE TEARDOWN PUSH, AND IT MUST HAPPEN BEFORE THE ENTRY IS CLEARED.

		This is Step 4.4's central promise and the first version of this file simply did not have it.
		`pushSnapshot` early-returns once `sessions[userId]` is nil, and `tick` calls `endSession` and
		`continue`s BEFORE `phaseAt` is ever asked about `elapsed >= Duration` — so `TRIAL_OFF` was
		unreachable on the wire by every one of the five exit paths, and `TrialController`'s teardown
		branch could never run. The symptom was a frozen "SOLO TRIAL" panel with a live leave button
		sitting on the player's screen for the rest of their session: exactly the static-screen
		failure C24 exists to delete, reproduced by the trial's own UI.

		Two independent audits found this, one by tracing the wire and one by tracing the plan, and a
		playtest then observed it across six live sessions. No plan check caught it — Step 4.4's gate
		is `check:scope`, a vocabulary tripwire with nothing to say about a missing remote call.
	]]
	session.TrialPhase = "TRIAL_OFF" :: Types.TrialPhase

	pushSnapshot(userId, nil)

	sessions[userId] = nil

	if session.Rig ~= nil then
		session.Rig:Destroy()
	end

	-- The pouch goes with the SESSION that created it. One left in the world would be a part
	-- `ItemService` could find on the next round — a trial prop promoted into real gameplay.
	if session.Pouch ~= nil then
		session.Pouch:Destroy()
		session.Pouch = nil
	end

	--[[
		PUT THE PLAYER BACK. Skipped when they have left — `PlayerRemoving` fires with the character
		already going away, and writing a CFrame onto it is both pointless and a source of errors in
		a path that must never throw, because it is the same path a phase change runs over every
		session at once.
	]]
	if reason ~= "PLAYER_LEFT" then
		local root = rootOf(Players:GetPlayerByUserId(userId) or (nil :: any))

		if root ~= nil then
			root.CFrame = session.ReturnCFrame
		end
	end

	if Config.Debug.VerboseLogging then
		-- A UserId and a reason. There is no role anywhere near this feature to leak.
		print(`[TrialService] {userId} left the trial: {reason}`)
	end
end

--[[
	THE TRIAL'S TASKS ARE NOT THE ROUND'S TASKS, AND THIS IS WHERE THAT IS TRUE OR NOT.

	The tempting shortcut was to reuse the round's task system: it already had hold-to-complete,
	presence range, a progress bar and a completion path. Rejected, and the reason is the whole plan.
	Its completion path called `RoundService.SetTasksCompleted` — the number the round's HUD rendered and
	the escape gate derives from. A trial task routed through it would increment a live round's task
	bar and, at TotalRequired, OPEN THE ESCAPE GATE. That is C21's row made literal: a trial that ends
	a live round.

	It could not happen even then, because a trial only opens while the phase is IDLE and that setter
	only opens the gate during ACTIVE. But "it is safe because two conditions happen not to overlap"
	is the kind of safety that survives exactly until someone relaxes one of them, and the relaxation
	would look harmless in review. The trial counts its own tasks in its own session and shares no
	code path with the round's counter.

	WHAT IS SHARED IS THE MAP, and only by tag. The trial's task points are TaskPoint parts inside the
	TrialZone, discovered the same way any tagged pool is but kept out of every other service's draw —
	`discoverPool` excludes anything carrying the zone attribute.

	V01 DELETED THE ROUND'S TASK SYSTEM ENTIRELY, so the collision this argues against can no longer
	happen. The separation is kept because V03's container search will occupy exactly the slot the
	task system did, and the argument applies to it unchanged.
]]
local function noteTrialTaskComplete(userId: number)
	local session = sessions[userId]

	if session == nil then
		return
	end

	session.TasksDone = math.min(session.TasksDone + 1, Config.Trial.TasksToComplete)

	pushSnapshot(userId, nil)
end

--[[
	Hold-to-complete, and the numbers behind it are the trial's OWN since V01 (`Config.Trial`). They
	began as the round task system's `PresenceRangeStuds` and `HoldTime`, borrowed on purpose: a
	tutorial that teaches an eight-second hold and then hands the player a six-second one has taught
	them the wrong thing, which is the failure §10 exists to delete.

	V01 deleted the block they were borrowed from, so they moved rather than died — the argument was
	never about WHERE the number lived, it was about the trial and the round agreeing. From V03 the
	thing this must agree with is the container search, so both values are worth revisiting when
	`Config.Search` lands rather than being treated as settled.
]]
local function advanceTrialTask(userId: number, session: Session, delta: number)
	local player = Players:GetPlayerByUserId(userId)
	local root = if player then rootOf(player) else nil

	if root == nil then
		session.HoldingPoint = nil
		session.HeldFor = 0

		return
	end

	local nearest: BasePart? = nil
	local nearestDistance = math.huge

	for _, point in trialPoints() do
		if session.DonePoints[point.Name] then
			continue
		end

		local distance = (point.Position - root.Position).Magnitude

		if distance <= Config.Trial.PresenceRangeStuds and distance < nearestDistance then
			nearest = point
			nearestDistance = distance
		end
	end

	if nearest == nil then
		-- Stepping off resets the hold, matching what the round's own bar does. A trial that let you
		-- accumulate eight seconds across three visits would teach a mechanic the game does not have.
		session.HoldingPoint = nil
		session.HeldFor = 0

		return
	end

	if session.HoldingPoint ~= nearest.Name then
		session.HoldingPoint = nearest.Name
		session.HeldFor = 0
	end

	session.HeldFor += delta

	if session.HeldFor < Config.Trial.HoldTime then
		return
	end

	session.DonePoints[nearest.Name] = true
	session.HoldingPoint = nil
	session.HeldFor = 0

	noteTrialTaskComplete(userId)
end

--[[
	The beats, as scripted actions. Phase 4 fills these in — the rig, the salt and the handoff. Until
	then a beat is a log line, which is enough for the clock, the phase and the task count to be live
	on one client.
]]
--[[
	THE SCRIPTED ASWANG IS A RIG, NOT A ROLE. It has no Player, no UserId, and no entry in any role
	table. That is what makes C22 possible without touching the secret at all: there is nothing here
	for `check:secrecy` to protect, because the thing being revealed is a prop.

	IT DOES NOT GO THROUGH MonsterService, and that is a deliberate refusal of the obvious reuse.
	`MonsterService`'s transform is built around a PLAYER who holds the role — it consults
	`RoleService`, writes transform state keyed by UserId, and broadcasts `MonsterTransformed` with a
	payload naming a character. Driving it with a fake identity would mean either inventing a UserId
	or loosening a service on the 🔒 surface so it accepts a non-player. Both are worse than the forty
	lines of tint-and-scale below, and the C04 audit finding CLAUDE.md records — a revert that restored
	hardcoded defaults and permanently branded the ex-Aswang — is what a "small" change to that file
	actually costs.

	WHAT IS REUSED IS THE LOOK, read from the same `Config.Monster` fields `MonsterService` reads:
	`TransformedScale`, `TransformedTintRgb` and `EyeGlowRgb`. The tell a player learns in the trial is
	then the tell they will see in a real round, which is the entire point of C22. Those are READ,
	never written.

	NO `MonsterTransformed` BROADCAST. That remote means "a player's character transformed" and every
	client branches on it; firing it for a prop in a corner would put a monster in the HUD of players
	who are in no round at all.
]]
--[[
	THE RIG'S GEOMETRY, in one block for the reason `OnboardingController`'s header gives: these are
	the numbers `check:config` flags, and scattering six waivers through the builder makes them
	invisible in a diff. Every one is a MODEL DIMENSION rather than a tunable — moving them to
	`Config.luau` would put a prop's proportions in the file M12 retunes balance from, and the trial's
	only balance numbers (`ChaseWalkSpeed`, `ChaseStopStuds`, `ChaseStunSeconds`) are already there.

	The scale and the colours are NOT here: those are read from `Config.Monster` so the tell learned
	in the trial is the tell seen in a round.
]]
local RIG = {
	TorsoSize = Vector3.new(2, 4, 1), -- config-ok: rig proportions, not balance
	HeadSize = Vector3.new(1.6, 1.6, 1.6), -- config-ok: rig proportions
	HeadLift = 2.6, -- config-ok: where the head sits on the torso
	EyeSize = Vector3.new(0.3, 0.3, 0.3), -- config-ok: rig proportions
	EyeSpread = 0.5, -- config-ok: eye placement across the face
	EyeLift = 2.8, -- config-ok: eye placement up the head
	EyeForward = -0.8, -- config-ok: eye placement out of the face
}

local function buildRig(at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "TrialAswangRig"

	local tint = Config.Monster.TransformedTintRgb
	local glow = Config.Monster.EyeGlowRgb

	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = RIG.TorsoSize * Config.Monster.TransformedScale
	torso.Color = Color3.fromRGB(tint[1], tint[2], tint[3]) -- config-ok: RGB triple indices, not a tunable
	torso.Material = Enum.Material.SmoothPlastic
	-- ANCHORED, and moved by CFrame rather than by pathfinding. The trial corner is an empty walled
	-- box with nothing to path around, so PathfindingService here would be a dependency bought for a
	-- straight line — and an unanchored rig would be shovable by the player it is meant to menace.
	torso.Anchored = true
	torso.CanCollide = false
	torso.CFrame = at
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = RIG.HeadSize * Config.Monster.TransformedScale
	head.Color = Color3.fromRGB(tint[1], tint[2], tint[3]) -- config-ok: RGB triple indices
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = at * CFrame.new(0, RIG.HeadLift, 0)
	head.Parent = model

	for _, side in { -RIG.EyeSpread, RIG.EyeSpread } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = RIG.EyeSize
		eye.Color = Color3.fromRGB(glow[1], glow[2], glow[3]) -- config-ok: RGB triple indices
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.CFrame = at * CFrame.new(side, RIG.EyeLift, RIG.EyeForward)
		eye.Parent = model
	end

	model.PrimaryPart = torso

	return model
end

--[[
	SALT IS GIVEN BEFORE THE THING IT DEFENDS AGAINST ARRIVES (`SaltGivenAt < ScriptedChaseAt`, pinned
	in tests/config.test.luau). §10 is explicit that the folklore must not be assumed: many players do
	not know salt stops an aswang. A pouch that appears mid-chase is taught by panic.

	THE LINE FIRES AT `SaltTaughtAt`, AFTER THE TRANSFORM RATHER THAN DURING IT. A sentence delivered
	on the same frame as a monster appearing is a sentence nobody reads — §10's "wall of text" failure
	wearing a different hat.

	The copy lives on the CLIENT (`TrialController`), keyed by the beat id this service sends. The
	payload carries an id and never a string, which is the same rule `TeachingCue` follows.
]]
local function grantSalt(player: Player)
	--[[
		WHY NOT ItemService: the same argument as MonsterService above. Its throw resolution is built
		around a round — it consults phase, thrower state and the Aswang's identity to decide a reveal,
		none of which has a meaning inside a trial where the phase is IDLE, the thrower is in no round
		and the target has no role. The trial hands over a pouch and watches its own rig for a hit.
	]]
	local pouch = Instance.new("Part")

	pouch.Name = "TrialSaltPouch"
	pouch.Size = Vector3.new(1.4, 1.4, 1.4) -- config-ok: prop dimensions, not balance
	pouch.Color = Color3.fromRGB(200, 198, 188) -- config-ok: matches the barrio generator's pouch colour
	pouch.Material = Enum.Material.SmoothPlastic
	pouch.Anchored = true
	pouch.CanCollide = false

	local root = rootOf(player)

	if root == nil then
		pouch:Destroy()
		return
	end

	pouch.CFrame = root.CFrame * CFrame.new(0, 0, -4) -- config-ok: drops the pouch just in front of the player
	pouch.Parent = workspace

	--[[
		DELIBERATELY NOT TAGGED `SaltSpawn`. An earlier version tagged it, which was the tag
		`ItemService.discoverPool` uses to find the map's real salt spawn POINTS — a live gameplay tag
		on a trial prop, for no benefit: nothing in the trial path ever read it, because
		`ItemService.pickupTick` iterates its own pouches folder and this part is not in it. It bought
		nothing and left the prop one missed teardown away from being discovered by a real round.
	]]
	local session = sessions[player.UserId]

	if session == nil then
		pouch:Destroy()
		return
	end

	session.Pouch = pouch

	-- Cleared with the session rather than left in the world: a pouch outliving its trial is a prop
	-- a round player could walk into, tagged as something ItemService discovers.
	-- A backstop only. `endSession` is the real owner and runs on all five exits; this catches the
	-- case where the session table is somehow lost without one.
	task.delay(Config.Trial.Duration, function()
		if pouch.Parent ~= nil then
			pouch:Destroy()
		end
	end)
end

local function handleBeat(userId: number, beat: string)
	local session = sessions[userId]
	local player = Players:GetPlayerByUserId(userId)

	if session == nil or player == nil then
		return
	end

	if beat == "BEAT_SALT_GIVEN" then
		grantSalt(player)
	elseif beat == "BEAT_TRANSFORM" then
		local spot = trialChaseSpot()

		if spot ~= nil then
			local rig = buildRig(spot.CFrame)

			rig.Parent = workspace
			session.Rig = rig
		end
	end

	if Config.Debug.VerboseLogging then
		print(`[TrialService] {userId} beat {beat}`)
	end
end

--[[
	THE CHASE. It walks toward the player, stops at `Config.Trial.ChaseStopStuds`, and holds. It never
	touches the player's Humanoid.

	NO KILL PATH, AND THAT IS A DESIGN DECISION RATHER THAN AN OMISSION. `Trial.ChaseWalkSpeed` is
	pinned below the player's baseline in tests/config.test.luau, so it cannot catch anyone. A trial
	that could kill you needs a death, a respawn, a re-entry and a decision about what a failed trial
	MEANS — and "what does failing mean" is the question whose answer is levels, retries and scores.
	C22's row forbids that in bold. The rig menaces and is stunned; that is the encounter.
]]
local function stepRig(session: Session, player: Player, delta: number)
	local rig = session.Rig

	if rig == nil then
		return
	end

	local primary = rig.PrimaryPart
	local root = rootOf(player)

	if primary == nil or root == nil then
		return
	end

	--[[
		THE STUN, TRIGGERED BY THE POUCH REACHING THE RIG.

		⚠️ THE THROW ITSELF IS NOT TAUGHT HERE, AND THIS IS A KNOWN C22 GAP RATHER THAN AN OVERSIGHT.
		`ItemService` resolves `RequestThrowSalt` through `pure/SaltThrow` with
		`Phase = RoundService.GetPhase()`, and a trial runs while the phase is IDLE — so the verdict is
		WRONG_PHASE and a trial player's throw is refused by the existing path. §9.1 asks that the
		player "learn to throw salt", and what this delivers is that salt STOPS the aswang, learned by
		bringing the pouch to it.

		The two ways to close it properly are a trial-local throw remote (a fifth remote this plan did
		not declare) or relaxing ItemService's phase gate for players in a trial (a change on the 🔒
		surface, coupling the two services the whole plan exists to keep apart). Both are decisions
		rather than details, and neither is made here. Recorded in the implementation log.
	]]
	local pouch = session.Pouch

	if pouch ~= nil and pouch.Parent ~= nil then
		if (pouch.Position - primary.Position).Magnitude <= Config.Salt.PickupRangeStuds then
			session.StunnedUntil = os.clock() + Config.Trial.ChaseStunSeconds
			pouch:Destroy()
			session.Pouch = nil
		end
	end

	if session.StunnedUntil > os.clock() then
		return
	end

	local toPlayer = root.Position - primary.Position
	local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)

	if flat.Magnitude <= Config.Trial.ChaseStopStuds then
		-- Holding station, still facing the player: the tell stays legible while it waits.
		primary.CFrame = CFrame.lookAt(
			primary.Position,
			Vector3.new(root.Position.X, primary.Position.Y, root.Position.Z)
		)
		return
	end

	--[[
		THE STEP IS CLAMPED SO IT CANNOT WALK THROUGH THE HOLD ZONE, and this is a shape fix rather
		than a tuning one.

		The first version stepped a fixed `ChaseWalkSpeed * delta` after checking the stop distance,
		which is correct only while one tick's travel is smaller than the whole stop radius. At the
		shipped numbers it is not: 13 studs/s x 0.5s = 6.5 studs per tick against a 6-stud radius, so
		the rig stepped straight over the zone the check was guarding. A playtest measured it landing
		at 1.70 studs from the player, every run, deterministically — near enough to read as the
		monster standing inside you.

		Clamping means the rig approaches and stops AT the radius for any values of the two numbers,
		rather than only for values where the arithmetic happens to work out. `tests/config.test.luau`
		pins the relationship as a second line of defence, but the clamp is what makes it correct.
	]]
	local travel =
		math.min(Config.Trial.ChaseWalkSpeed * delta, flat.Magnitude - Config.Trial.ChaseStopStuds)
	local nextPos = primary.Position + flat.Unit * travel

	rig:PivotTo(CFrame.lookAt(nextPos, Vector3.new(root.Position.X, nextPos.Y, root.Position.Z)))
end

--[[
	THE TICK. One loop for every session, driven off the timeline rather than off a chain of
	`task.delay` calls — see `shared/pure/TrialTimeline`'s header for why that mattered enough to
	shape the module.

	`dueBeats` returns a LIST, so a hitch that skips past two beats fires both rather than dropping
	one. Each is marked in `session.Fired` at the moment it is handled, which is what makes the
	fire-once guarantee hold across a hitch as well as across a normal tick.
]]
local function tick(delta: number)
	for userId, session in sessions do
		local elapsed = os.clock() - session.StartedAt

		if elapsed >= Config.Trial.Duration then
			--[[
				`COMPLETED` vs `EXPIRED`, and this resolves a plan ambiguity rather than inheriting
				one. The plan declared five end reasons and never said where `COMPLETED` fires; the
				first version of this file therefore never fired it, leaving a dead enum member that
				an audit found by grep.

				It now means what a reader would assume: the clock ran out AND the player did
				everything the trial asked. It changes no behaviour — both reasons run the identical
				teardown — but it makes the log line answer "did this tutorial work?", which is the
				only question the reason field exists to answer.
			]]
			local done = session.TasksDone >= Config.Trial.TasksToComplete

			endSession(userId, if done then "COMPLETED" else "EXPIRED")
			continue
		end

		session.TrialPhase = TrialTimeline.phaseAt(
			elapsed,
			schedule(),
			session.TasksDone >= Config.Trial.TasksToComplete
		) :: Types.TrialPhase

		-- `beat` is a plain `string` here and stays one until `pushSnapshot` narrows it through
		-- `asBeat` at the payload. See that function's header for why it is not a cast.
		for _, beat in TrialTimeline.dueBeats(elapsed, schedule(), session.Fired) do
			session.Fired[beat] = true
			handleBeat(userId, beat)
			pushSnapshot(userId, beat)
		end

		local chasePlayer = Players:GetPlayerByUserId(userId)

		if chasePlayer ~= nil then
			stepRig(session, chasePlayer, delta)
		end

		advanceTrialTask(userId, session, delta)

		pushSnapshot(userId, nil)
	end
end

--[[
	Opens a session and moves the player into the zone. The return CFrame is captured BEFORE the move,
	because it is the only record of where they were — `endSession` is the sole reader and every exit
	path runs through it.
]]
local function beginSession(player: Player)
	local root = rootOf(player)

	if root == nil then
		return
	end

	local session: Session = {
		StartedAt = os.clock(),
		TrialPhase = "TRIAL_TASKS" :: Types.TrialPhase,
		Fired = {},
		TasksDone = 0,
		Rig = nil,
		ReturnCFrame = root.CFrame,
		DonePoints = {},
		HoldingPoint = nil,
		HeldFor = 0,
		StunnedUntil = 0,
	}

	sessions[player.UserId] = session

	local spawnPart = trialSpawn()

	if spawnPart ~= nil then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, Config.Trial.SpawnLiftStuds, 0)
	end

	if Config.Debug.VerboseLogging then
		print(`[TrialService] {player.UserId} entered the trial`)
	end

	pushSnapshot(player.UserId, nil)
end

function TrialService.Init() end

function TrialService.Start()
	--[[
		THE MUTUAL EXCLUSION, and it is four lines because the hard thinking is in the pure module.

		Subscribing to PhaseChanged rather than polling RoundService.GetPhase() matters: a poll can
		miss a phase that opens and closes between two ticks, and IDLE → INTERMISSION → IDLE (a player
		joining and leaving inside 25 seconds) is exactly that shape. The BindableEvent fires on every
		transition, so nothing is missed.
	]]
	RoundService.PhaseChanged.Event:Connect(function(phase: Types.RoundPhase)
		if not TrialAdmission.mustEnd(phase) then
			return
		end

		for userId in sessions do
			endSession(userId, "ROUND_STARTED")
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		endSession(player.UserId, "PLAYER_LEFT")
	end)

	--[[
		A mid-trial respawn ends the session. `RoundService.watchForDeath` respawns at the
		SpawnLocation on `Humanoid.Died`, and the stock Escape → Reset button fires that in any phase.
		Without this the player is teleported out of the zone while their session keeps ticking,
		leaving them watching a trial timer from the lobby.

		═══ THIS BLOCK WAS WRONG IN TWO SEPARATE WAYS AND IS REWRITTEN, NOT PATCHED ══

		Two independent audits found two different defects in the same five lines, which per
		`.claude/lessons/green-after-each-patch-hides-a-loop.md` is a redesign signal rather than two
		fixes. Both are worth naming because both were invisible to every check:

		1. NO BACKFILL. It connected `PlayerAdded` and stopped, so any player already in the server
		   when `Start()` ran never got a `CharacterAdded` connection at all. `init.server.luau`
		   yields twice before starting services, and the Solo Trial's entire target population is
		   the first one or two players on a fresh server — precisely who `PlayerAdded` misses.
		   `RoundService`, `MonsterService` and `GhostService` all connect-then-backfill, and
		   `GhostService`'s own comment records that a previous exploit audit flagged `ItemService`
		   for this exact omission. Connect first, THEN backfill: a player arriving inside the window
		   is wired twice rather than zero times, which is safe because `endSession` is idempotent.

		2. THE WRONG END REASON. It passed `PLAYER_ASKED`, and the reason is not a label — it is a
		   branch. `endSession` restores the character's CFrame for every reason EXCEPT `PLAYER_LEFT`,
		   so `PLAYER_ASKED` made it write `ReturnCFrame` onto a character that `watchForDeath` was
		   repositioning on the same frame. That is the body-contention race the design avoided by
		   choosing "end the session" over "re-place the character" in the first place. `PLAYER_LEFT`
		   is the reason that means "their body is not ours to move".
	]]
	local function watchRespawn(player: Player)
		player.CharacterAdded:Connect(function()
			endSession(player.UserId, "PLAYER_LEFT")
		end)
	end

	Players.PlayerAdded:Connect(watchRespawn)

	for _, player in Players:GetPlayers() do
		watchRespawn(player)
	end

	--[[
		THE THREE THINGS A CLIENT COULD TRY, and what refuses each. Worth writing down because C21 is
		marked 🔒 and the usual answer — "the Aswang's identity" — is not the answer here. The trial's
		Aswang is a scripted rig, so there is no secret INSIDE a trial. The attacks run the other way:

		  1. Start a trial DURING a live round. Refused by TrialAdmission's `RoundPhase ~= "IDLE"`
		     check, which is re-run here on every call. This is the one that matters — a client that
		     could open a session mid-round would get a teleport out of the map and a rig spawned
		     next to a live game.
		  2. Start a trial they are already in, to double the rig or reset the clock. Refused by
		     ALREADY_IN_TRIAL, checked from `sessions` rather than from anything the client said.
		  3. Spam either remote. Refused by AntiCheatService, consulted FIRST in both handlers.

		NEITHER HANDLER TAKES AN ARGUMENT, so there is no fourth attack of the "name a moment, a
		position or an outcome" kind. The player is the one Roblox gives us; everything else is
		server state.
	]]
	Remotes.Get("RequestStartTrial").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestStartTrial") then
			return
		end

		--[[
			RE-DECIDED HERE, NOT TRUSTED FROM THE BUTTON. C24 shows the entrance only when a trial is
			available, and that is a courtesy to an honest player — never a permission. §6.2: the
			client requests, the server decides.
		]]
		local verdict = TrialAdmission.evaluate({
			Enabled = Config.Trial.Enabled,
			RoundPhase = RoundService.GetPhase(),
			PlayerCount = #Players:GetPlayers(),
			OfferBelowPlayerCount = Config.Trial.OfferBelowPlayerCount,
			AlreadyInTrial = sessions[player.UserId] ~= nil,
		})

		if verdict ~= "OK" then
			if Config.Debug.VerboseLogging then
				print(`[TrialService] refused {player.UserId} a trial: {verdict}`)
			end

			return
		end

		beginSession(player)
	end)

	-- "I am done." The server already knows whose session it is, so there is nothing to pass and
	-- nothing to validate beyond the budget and the session's existence.
	Remotes.Get("RequestEndTrial").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestEndTrial") then
			return
		end

		endSession(player.UserId, "PLAYER_ASKED")
	end)

	--[[
		THE THROW, AND IT TEACHES THE REAL ONE.

		§9.1 asks that the player "learn to throw salt". They could not until this existed:
		`ItemService` resolves every throw against `RoundService.GetPhase()`, and a trial runs at
		IDLE, so the real remote answered WRONG_PHASE and the tutorial taught an action the player
		was refused. A playtest confirmed the gap.

		IT SHARES THE AIM WITH THE REAL THROW AND NOTHING ELSE. `SaltThrow.inCone` is the same
		function `ItemService` calls — same range, same cone, one implementation — so what a player
		learns here is what works in a round. A second copy of the geometry would drift, and a
		tutorial that teaches a throw the game does not have is worse than teaching no throw at all.

		WHAT IT DOES NOT SHARE is every round rule: phase, thrower state, carry limit, and whether the
		target is the transformed Aswang. None of those has a meaning in a trial, where the phase is
		IDLE, the thrower is in no round, and the target is a prop with no role. The trial's
		preconditions are its own — you are in a session, you have the pouch, the rig exists — and
		they are checked here.

		The client sends a direction and nothing else, exactly as `RequestThrowSalt` does. It does not
		raycast, pick a target, check range or predict a hit: a client that rendered a hit the server
		refused would tell its player the monster is stunned when it is not.
	]]
	Remotes.Get("RequestTrialThrow").OnServerEvent
		:Connect(function(player: Player, direction: unknown)
			if not AntiCheatService.Consume(player, "RequestTrialThrow") then
				return
			end

			-- Typed `unknown` rather than `Vector3` so this line cannot be skipped: without it a table
			-- reaches `.Unit` and throws inside a connection, which Roblox swallows into one warn.
			if typeof(direction) ~= "Vector3" then
				return
			end

			local session = sessions[player.UserId]

			if session == nil then
				return
			end

			local pouch = session.Pouch

			if pouch == nil or pouch.Parent == nil then
				return
			end

			local rig = session.Rig
			local primary = if rig ~= nil then rig.PrimaryPart else nil
			local root = rootOf(player)

			if primary == nil or root == nil then
				return
			end

			local hit = SaltThrow.inCone(
				vec3(root.Position),
				vec3(direction),
				vec3(primary.Position),
				Config.Salt.ThrowRange,
				Config.Salt.ThrowConeDegrees
			)

			--[[
				THE POUCH IS SPENT EITHER WAY. §4.6 gives salt no recharge, and a throw that only
				costs you when it lands teaches that aiming is free — which is the opposite of the
				decision the real game asks you to make. A miss in the trial costs the pouch, exactly
				as it does in a round.
			]]
			pouch:Destroy()
			session.Pouch = nil

			if hit then
				session.StunnedUntil = os.clock() + Config.Trial.ChaseStunSeconds
			end

			if Config.Debug.VerboseLogging then
				print(`[TrialService] {player.UserId} threw salt: {if hit then "HIT" else "MISS"}`)
			end
		end)

	task.spawn(function()
		while true do
			task.wait(Config.Trial.SnapshotInterval)
			tick(Config.Trial.SnapshotInterval)
		end
	end)
end

return TrialService
