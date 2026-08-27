--!strict
--[[
	NoiseService — every noisy action, priced, recorded and bounded. (V04, §4.4)

	Milestone: V04. Spec: docs/MVP-SPEC.md §4.4, §4.6, §6.2.

	§4.4: "The noise is the entire risk economy. You cannot arm yourself quietly, you cannot be safe
	and productive at the same time, and every search is a decision you made." Three things happen
	here and each is server-decided:

	  · a caller says an action HAPPENED, and this file prices it        (shared/pure/NoiseModel)
	  · the actor is throttled so one action is one noise                (server/pure/NoiseLog)
	  · the event is appended to a bounded, server-only history          (V13 reads it, nobody else)

	THE HISTORY NEVER CROSSES THE WIRE AND NEVER REACHES A LOG. Not as a payload, not as an
	attribute, not as a tag. The log rule is SearchService's and it is the less obvious half: in a
	Studio solo test the server and client share one output window, so printing where a noise
	happened puts every other player's position in front of the person playing. Log COUNTS and
	ACTIONS, never positions.

	THERE IS NO ACTOR IN A RECORD. `Emit` takes one — to throttle them, and to mark their own cue —
	and it does not survive the call. V13's pulse is built on these records and cannot leak an
	identity that was never written down (§4.6: an area, never an address). Adding a UserId here is a
	spec conversation, not an implementation detail.

	NO BRANCH IN THIS FILE READS A ROLE. `RoundService.GetAswangUserId` must not appear in it. §4.4
	requires the Aswang to search, and be heard searching, on identical terms — any activity it
	cannot perform sincerely becomes an oracle that identifies it, and a noise system with a monster
	exemption is the loudest possible version of that.

	ROUNDSERVICE OWNS THE PHASE (§6.4). This service subscribes and never calls setPhase.

	V13 CONNECTS THROUGH `GetRecent` AND NOTHING ELSE. There is no tracker logic here, no curve, no
	pulse and no timer — see that function's comment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundService = require(script.Parent.RoundService)
local NoiseLog = require(script.Parent.Parent.pure.NoiseLog)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local NoiseModel = require(Shared.pure.NoiseModel)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local NoiseService = {}

--------------------------------------------------------------------------------
-- SERVER-ONLY state. None of this replicates. None of it is logged in full.
--------------------------------------------------------------------------------

-- Ascending by `At`; `NoiseLog.append` is the only writer and rebuilds it pruned every time.
local history: { NoiseLog.Record } = {}

--[[
	UserId -> action -> the os.clock() of their last recorded noise of that action.

	THE ONE PLACE AN ACTOR IS ASSOCIATED WITH A NOISE, and it is transient, per-action, never
	written into a record and never read by anything but the throttle three lines below. Keyed by
	action rather than by player alone so that using an item does not silence a search.
]]
local lastEmitAt: { [number]: { [string]: number } } = {}

local cueRemote = Remotes.Get("NoiseCue")

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	return root
end

--[[
	WHO HEARS THIS, DECIDED HERE AND NOWHERE ELSE.

	ONE FireClient PER LISTENER, NEVER FireAllClients. The distance test is the entire security
	property of this function: a client out of earshot receives nothing at all, so there is no
	broadcast stream to record, difference or triangulate. See the `NoiseCue` comment in Remotes.

	THE POSITION IS QUANTISED BEFORE IT IS SENT, once, so every listener gets the same cell and two
	colluding clients cannot average their copies back toward the truth.

	`action` IS PASSED IN RATHER THAN READ OFF `record`, because `NoiseLog.Record.Action` is a plain
	string and `:: Types.NoiseAction` is the cast that fails with "none of the union options are
	compatible" — `.claude/lessons/pure-module-unions-widen-in-lists.md`. Emit already holds the
	narrow type; handing it through costs an argument and no casts.

	NO BRANCH HERE READS A ROLE, AND THE ACTOR IS NOT EXEMPT FROM ANYTHING. The Aswang hears other
	people's noise and makes its own on identical terms; the only per-player difference in this
	function is `Mine`, which is a fact about the receiver and reaches nobody else.
]]
local function dispatchCue(actor: Player?, action: Types.NoiseAction, record: NoiseLog.Record)
	--[[
		THE GRID IS CLAMPED HERE, NOT TRUSTED. `NoiseModel.quantise` returns the position UNCHANGED
		for a grid of zero or less — a deliberate choice in a pure module that must not error inside
		a dispatch loop, but the wrong direction for the one caller that puts the result on the wire.
		A `CueGridStuds = 0` typed during a V16 balance session would otherwise ship every actor's
		exact position to everyone in earshot.

		`tests/config.test.luau` already pins CueGridStuds above zero, and that check is real — but it
		guards the value in a different file, and this is the line that would leak. The V04 exploit
		audit named the asymmetry: defended by a test rather than by the sender. Now both.
	]]
	local cell = NoiseModel.quantise(record.Position, math.max(Config.Noise.CueGridStuds, 1))
	local at = Vector3.new(cell.X, cell.Y, cell.Z)

	for _, player in Players:GetPlayers() do
		local state = RoundService.GetPlayerState(player)

		--[[
			OUTSIDE THE ROUND HEARS NOTHING. The same rule `AudioCues` applies to monster cues, one
			layer earlier: a cue is information, and information reaching somebody in the lobby is
			information reaching a Discord call. DEAD is allowed — a dead player is in the world and
			can already see people searching, and silence for the dead would make them audibly
			different from the living (`.claude/lessons/absence-is-observable.md`).
		]]
		if state == Enums.PlayerState.Lobby or state == Enums.PlayerState.Spectator then
			continue
		end

		local mine = player == actor

		if not mine then
			local root = rootOf(player)

			if root == nil then
				continue
			end

			local listener = { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z }

			-- AGAINST THE TRUE POSITION, not the quantised one: the cell is what gets SENT, and
			-- testing against it would move the audible edge by up to half a cell per axis.
			if not NoiseLog.withinRadius(record.Position, listener, record.Radius) then
				continue
			end
		end

		-- A TYPED LOCAL rather than an inline table, for `broadcastEffect`'s reason: FireClient takes
		-- `...any`, so an inline literal is unchecked and a typo'd field name would ship. The
		-- annotation is what makes the absent fields listed in Types.NoiseCuePayload enforceable.
		local payload: Types.NoiseCuePayload = {
			Action = action,
			Loudness = record.Loudness,
			Position = at,
			Mine = mine,
		}

		cueRemote:FireClient(player, payload)
	end
end

local function limits(): NoiseLog.Limits
	return {
		HistorySeconds = Config.Noise.HistorySeconds,
		MaxRecords = Config.Noise.MaxRecords,
	}
end

--[[
	AN ACTION HAPPENED. The caller has already decided that it did — this file prices it and records
	it, and refuses nothing except a phase, a silent action and a throttled repeat.

	`actor` IS OPTIONAL because not every noise has one: a door swinging shut behind somebody is the
	obvious future case. A nil actor is unthrottled and gets no `Mine` cue, so a caller passing nil
	for a player-caused noise is handing away both the bound and the feedback — pass the player.

	ACTIVE ONLY. Searching is an ACTIVE-phase activity (SearchService) and a noise recorded during
	INTERMISSION would be a record V13 reads before the round it belongs to has started. The gate is
	here rather than at each caller so a future emitter cannot forget it.

	══════════════════════════════════════════════════════════════════════════════════════════════
	THE PRECONDITION ON EVERY CALLER, AND IT IS THE ONE THAT ACTUALLY PROTECTS THE SECRET:

	  ONLY EMIT AN ACTION THAT EVERY ROLE CAN SINCERELY PERFORM.

	The V04 exploit audit established that this — not the payload's shape — is what keeps the noise
	system from identifying the Aswang. The payload carries no actor, and that is worth having, but
	it is NOT the defence: characters replicate, so any client can match a cue's cell against every
	player's live HumanoidRootPart and attribute the noise. The audit measured the cell as an 8x8x8
	box, which with five players in a barrio is usually a unique attribution, through walls, out to
	the full 60-stud radius.

	That is harmless today because SEARCH and ITEM_USE are things a survivor and the Aswang both do —
	§4.4's rule that "the monster must be able to do everything a survivor does, sincerely". Attribute
	all you like: you learn that player 3 searched, which tells you nothing.

	IT STOPS BEING HARMLESS THE FIRST TIME A MONSTER-ONLY ACTION EMITS. A feed (V06), camouflage or
	smoke (V07) is something only one player in the round can do — so a cue for it is a role oracle
	with no role token anywhere in it, which `check:secrecy` structurally cannot see and which no
	amount of anonymising the payload would fix. If you are here to add an emitter for a monster
	ability, the answer is no, and the place to argue otherwise is the spec.
	══════════════════════════════════════════════════════════════════════════════════════════════
]]
function NoiseService.Emit(
	actor: Player?,
	action: Types.NoiseAction,
	position: Vector3,
	state: NoiseModel.State?
)
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return
	end

	local emission = NoiseModel.evaluate(action, state or {}, Config.Noise)

	-- nil means "this action makes no noise at all" — an unpriced action, or movement below the
	-- sprint threshold. Silent is the fail-closed direction.
	if emission == nil then
		return
	end

	local now = os.clock()

	if actor ~= nil then
		-- `: ActionTuning?` for SearchService's reason: indexing a `{ [string]: T }` yields a
		-- NON-optional value under --!strict, so comparing it to nil is a type error, not a lookup.
		local tuning: NoiseModel.ActionTuning? = Config.Noise.Actions[action]
		local perAction = lastEmitAt[actor.UserId]

		if perAction == nil then
			perAction = {}
			lastEmitAt[actor.UserId] = perAction
		end

		if
			tuning ~= nil
			and not NoiseLog.shouldRecord(perAction[action], now, tuning.MinInterval)
		then
			return
		end

		perAction[action] = now
	end

	local record: NoiseLog.Record = {
		Action = action,
		Loudness = emission.Loudness,
		Radius = emission.Radius,
		-- The one Vector3 -> Vec3 conversion in the system. Everything downstream of here is plain
		-- tables, so both pure modules and V13 can hold it (preamble P2).
		Position = { X = position.X, Y = position.Y, Z = position.Z },
		At = now,
	}

	history = NoiseLog.append(history, record, limits())

	-- §4.6: "Survivors must know when they made noise. A sound you cannot perceive is not tension,
	-- it is a dice roll." AFTER the record, so a cue can never be heard for a noise the history does
	-- not contain.
	dispatchCue(actor, action, record)

	if Config.Debug.VerboseLogging then
		-- COUNTS AND ACTIONS, NEVER POSITIONS. See the header: in a Studio solo test this window is
		-- in front of the player, and a position is somebody else's location.
		print(`[NoiseService] {action} recorded — {#history} in history.`)
	end
end

--------------------------------------------------------------------------------
-- THE V13 SEAM, and V04 connects nothing to it.
--------------------------------------------------------------------------------

--[[
	THE NOISE OF THE LAST `withinSeconds` SECONDS, newest last. COPIES — mutate what you are handed
	and the server's history is unaffected (`AudioCues.oneShotsFor`'s rule, and a tracker is exactly
	the sort of caller that will want to sort its input).

	V13 IS THE ONLY INTENDED CALLER AND THIS IS ITS ONLY INPUT (build plan V13: "Input is ONLY V04's
	noise history. No position feed, no live tracking."). Three properties are being handed over
	deliberately and V13 must not undo any of them:

	  · NO ACTOR. Nothing here says who made a noise, so no pulse can name a player however it is
	    written. §4.6: the pulse reveals an AREA and never an address.
	  · NO ROLE AND NO FORM. The Aswang's own noise is in here on identical terms, so a pulse may
	    well point at the monster's own footsteps. That is CORRECT: it costs the Aswang nothing (it
	    knows where it has been) and it is what lets the history stay identity-free. Filtering it out
	    would require knowing who acted, which is the one field this design refuses.
	  · WINDOW, NOT STREAM. There is no event, no signal and no per-frame push, because "vague and
	    slow, never live" is the constraint that keeps the Aswang blending in rather than walking to
	    pings.

	NEVER FIRE THIS AT A CLIENT. Not the list, not a length, not a filtered copy. `Radius` and
	`Loudness` are already public (they are Config); `Position` and `At` are not, and the pair is a
	live map of where every player has been.

	`{ NoiseLog.Record }` RATHER THAN A LIST OF THE LITERAL UNION, and the annotation is the lesson:
	a literal union does not survive `require` inside a LIST, the element arrives widened to plain
	`string`, and `::` distributes over the union and fails at the CALL SITE with an error that names
	the wrong file. Narrow `Action` with a lookup — `Config.Noise.Actions[record.Action]` returns nil
	for an id nobody priced. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.
]]
function NoiseService.GetRecent(withinSeconds: number): { NoiseLog.Record }
	return NoiseLog.recentSince(history, os.clock(), withinSeconds)
end

-- How many events the history is holding. For a log line and for a playtester who needs to prove
-- "bounded" from the server side; it says nothing about who or where.
function NoiseService.RecordCount(): number
	return #history
end

--------------------------------------------------------------------------------
-- Phase subscription. RoundService owns the phase; this only reacts to it.
--------------------------------------------------------------------------------

local function clearHistory()
	table.clear(history)
	table.clear(lastEmitAt)
end

--[[
	EVERY PHASE THAT IS NOT ACTIVE CLEARS EVERYTHING, and it is one rule with no exceptions on
	purpose. SearchService keeps its layout through ENDING because the end screen runs for
	Config.Round.EndScreen seconds and something might still read it; nothing reads noise at ENDING,
	and a record surviving into the next round is a ghost the tracker would treat as live.
]]
local function onPhaseChanged(phase: Types.RoundPhase)
	if phase ~= Enums.RoundPhase.Active then
		clearHistory()
	end
end

function NoiseService.Init()
	clearHistory()
end

function NoiseService.Start()
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		A departing player's throttle goes with them. Their RECORDS STAY and age out normally: the
		noise happened, and a history that forgot a leaver's noise would make "somebody left" visible
		to whatever reads it.
	]]
	Players.PlayerRemoving:Connect(function(player: Player)
		lastEmitAt[player.UserId] = nil
	end)
end

return NoiseService
