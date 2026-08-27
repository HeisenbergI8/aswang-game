--!strict
--[[
	SearchService — the container layout, and the six seconds it costs to open one. (V03, §4.4)

	Milestone: V03. Spec: docs/MVP-SPEC.md §4.4, §6.2.

	SEARCHING IS THE ONLY ACTIVITY IN THE GAME (§4.4). There are no tasks; V01 deleted them. Four
	things happen in this file and each is server-decided:

	  · the tagged pool is discovered and judged at STARTING       (SearchPool.evaluate)
	  · a layout is drawn from server-only entropy                 (server/pure/ContainerLayout)
	  · RequestSearch is resolved into a hold on one container     (nearest, from the player's own
	                                                                position — the client names nothing)
	  · the hold completes after Config.Search.SearchTime and the finder alone is told what was in it

	THE LAYOUT NEVER CROSSES THE WIRE, AND NEVER REACHES A LOG. Not as a payload, not as an attribute,
	not as a tag — attributes and CollectionService tags replicate to EVERY client and there is no
	private one. The log rule is the less obvious half: in a Studio solo test the server and client
	share one output window, so `print`ing where the buntot pagi is puts it in front of the person
	playing. Log COUNTS and VERDICTS, never contents.

	THE ASWANG SEARCHES ON IDENTICAL RULES, AND NO BRANCH IN THIS FILE READS ITS IDENTITY. §4.4 wants
	it that way — rummaging inside a house is blending justified by mechanics rather than performed,
	and denying survivors the buntot pagi is a real strategy that looks exactly like survival. It is
	also Amendment A2's generalisation: any activity the monster cannot perform sincerely becomes an
	oracle that identifies it. `RoundService.GetAswangUserId` must not appear in this file. If a future
	change wants a role-dependent search, that is a spec conversation, not an implementation detail.

	ROUNDSERVICE OWNS THE PHASE (§6.4). This service subscribes and never calls setPhase, and it never
	blocks or delays a transition — an EMPTY map produces a round with nothing to find and a loud warn,
	not a round that will not start.

	V03 GRANTS NOTHING. `ItemFound` below is the seam V08 connects; see its comment.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local NoiseService = require(script.Parent.NoiseService)
local RoundService = require(script.Parent.RoundService)
-- The one verdict module every tag-driven pool in this game shares. Generic over
-- (names, required, expected) and naming no mechanic, so this is a second CALLER rather than a second
-- copy — ItemService's salt pool is the first.
local SearchPool = require(script.Parent.Parent.pure.SearchPool)
local ContainerLayout = require(script.Parent.Parent.pure.ContainerLayout)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local SearchService = {}

local TAG_CONTAINER = "SearchContainer"

--[[
	THE SEAM TO V08, and V03 connects nothing to it.

	V03's Done line is "searching yields items". V08 owns ItemService, the three items and the carry
	slot, so this chunk stops at telling the finder and recording the find. It creates no Tool, touches
	no carry count and produces no `ClientRoundSnapshot.YourCarriedItem` — V02 left that field without
	a producer deliberately and V08 is the chunk that adds one.

	Fires (player, itemId) where itemId is a PLAIN STRING. A BindableEvent's arguments are `...any`, so
	the connector must narrow it — `ContainerLayout.itemAt`-style, with a function and not a cast, for
	the reason in that module's header.

	A BindableEvent rather than a direct call for `RoundService.PhaseChanged`'s reason: it lets V08
	depend on this service without this service depending on V08, so the arrow cannot become a cycle.
	A require cycle errors at load, init.server.luau swallows it into one warn, and the server sits
	looking exactly like "nobody has joined yet".
]]
SearchService.ItemFound = Instance.new("BindableEvent")

--------------------------------------------------------------------------------
-- SERVER-ONLY state. None of this replicates. None of it is logged in full.
--------------------------------------------------------------------------------

-- Every `SearchContainer` part, keyed by Name. Rebuilt on every seed rather than cached, for the
-- reason any tag-driven pool is: the map author will add, move and delete these parts while a server
-- is running, and a cached part is one that can stop existing.
local containersByName: { [string]: BasePart } = {}

--[[
	Container index -> Name, and its inverse. THE INDEX IS THE POSITION IN THE SORTED NAME LIST, which
	is what ties `ContainerLayout`'s abstract 1..n to actual parts in the world.

	A CLIENT CAN DERIVE THIS ORDERING AND IT DOES NOT MATTER. Workspace replicates, so any client can
	read every tagged part's Name and sort them. What it cannot derive is the CONTENTS, which come from
	`Random.new()` on this machine and exist only in `layout` below. Publishing an ordering is not
	publishing a layout — the same distinction `RoleDraw`'s header draws between an algorithm and a
	reproducible draw.
]]
local orderedNames: { string } = {}
local indexByName: { [string]: number } = {}

-- THE SECRET. Nil outside a round and whenever the map has no usable pool.
local layout: ContainerLayout.Layout? = nil

-- Container index -> true once opened. Server-only: a client that could read this would know which
-- containers are still worth walking to, which is exactly the walk §4.4 wants to cost something.
local opened: { [number]: boolean } = {}

--------------------------------------------------------------------------------
-- Pool discovery. Lifted almost verbatim from ItemService.discoverPool, which is
-- the established shape for a tag-driven pool in this repo.
--------------------------------------------------------------------------------

--[[
	How many items the round places. SUMMED FROM CONFIG rather than typed, so a V16 tune of any
	*SpawnCount* moves the pool requirement with it and `check:config` has no literal to flag.
]]
function SearchService.TotalItems(): number
	return Config.Items.SaltSpawnCount
		+ Config.Items.GarlicSpawnCount
		+ Config.Items.BuntotPagiSpawnCount
end

local function discoverPool(): SearchPool.Report
	local names: { string } = {}

	table.clear(containersByName)

	for _, instance in CollectionService:GetTagged(TAG_CONTAINER) do
		if not instance:IsA("BasePart") then
			warn(
				`[SearchService] {instance:GetFullName()} is tagged {TAG_CONTAINER} but is a `
					.. `{instance.ClassName}, not a BasePart — skipped.`
			)
			continue
		end

		table.insert(names, instance.Name)

		-- The `: BasePart?` is load-bearing under --!strict: indexing a `{ [string]: BasePart }` yields
		-- a non-optional value, so comparing it to nil is a type error rather than a lookup.
		local existing: BasePart? = containersByName[instance.Name]

		if existing == nil then
			containersByName[instance.Name] = instance
		end
	end

	--[[
		SORTED, AND THIS LINE IS SECURITY RATHER THAN TIDINESS. `GetTagged`'s order is engine-defined
		and can differ between servers and between runs. Feeding it into a random draw makes the draw
		depend on a hidden input — which does not leak anything by itself, but it makes the layout
		irreproducible for anyone debugging it and, worse, makes "same entropy, same layout" false, so
		no test could ever pin the wiring. ItemService sorts for the same reason.
	]]
	table.sort(names)

	return SearchPool.evaluate(names, SearchService.TotalItems(), Config.Search.ContainerCount)
end

--[[
	THE LOUD HALF, ungated by VerboseLogging, on this repo's rule that routine tracing is gated and
	faults warn unconditionally. A barrio with no containers in it is a fault whose only player-visible
	symptom is that there is nothing to do and nobody knows why.

	NOT ONE OF THESE LINES NAMES A CONTENT. Counts and verdicts only.
]]
local function reportPool(report: SearchPool.Report)
	local required = SearchService.TotalItems()

	if #report.Duplicates > 0 then
		warn(
			`[SearchService] {TAG_CONTAINER} parts share a Name and were skipped: `
				.. `{table.concat(report.Duplicates, ", ")}. Every tagged part needs a unique one.`
		)
	end

	if report.Verdict == "EMPTY" then
		warn(
			`[SearchService] NO "{TAG_CONTAINER}" PARTS IN THE MAP. Tag {Config.Search.ContainerCount} `
				.. `anchored parts with "{TAG_CONTAINER}" via CollectionService, or nothing can ever be `
				.. `found and §4.4's entire loop does not exist — survivors have no activity at all.`
		)
	elseif report.Verdict == "SHORT" then
		warn(
			`[SearchService] Only {#report.Unique} "{TAG_CONTAINER}" part(s) found; {required} items `
				.. `are meant to be placed. Fewer will be, buntot pagi and salt first.`
		)
	elseif report.Verdict == "OVERSIZED" then
		warn(
			`[SearchService] {#report.Unique} "{TAG_CONTAINER}" parts found, but `
				.. `Config.Search.ContainerCount says {Config.Search.ContainerCount}. Seeding still `
				.. `works; the map and Config disagree.`
		)
	elseif Config.Debug.VerboseLogging then
		print(`[SearchService] Container pool OK — {#report.Unique} containers.`)
	end
end

--------------------------------------------------------------------------------
-- The seed. This is the function §6.2 names as server-only state.
--------------------------------------------------------------------------------

local function seedLayout()
	local report = discoverPool()

	reportPool(report)

	table.clear(orderedNames)
	table.clear(indexByName)
	table.clear(opened)

	if report.Verdict == "EMPTY" then
		-- No pool, no layout, and the round still starts. Every RequestSearch answers
		-- SEARCH_NO_CONTAINER, which is the truth.
		layout = nil
		return
	end

	for index, name in report.Unique do
		orderedNames[index] = name
		indexByName[name] = index
	end

	--[[
		`Random.new()` WITH NO ARGUMENT. THIS IS THE LINE THE WHOLE CHUNK IS ABOUT.

		`Random.new(state.RoundNumber)` and `Random.new(os.time())` are both fatal: a client knows the
		round number and can read the clock to the second, so either one lets it replay this draw
		locally and know where the buntot pagi is BEFORE the round starts — with no remote to
		intercept and nothing for `check:secrecy` to see. §4.4 and §6.2 both say so explicitly. The
		no-argument constructor seeds from server-only entropy.

		The adapter below matches `ContainerLayout.draw`'s `nextInt(lo, hi)` contract, which was
		written to match `Random:NextInteger` so nothing has to be remembered at the call site.
	]]
	local rng = Random.new()

	layout = ContainerLayout.draw(#orderedNames, {
		Salt = Config.Items.SaltSpawnCount,
		Bawang = Config.Items.GarlicSpawnCount,
		BuntotPagi = Config.Items.BuntotPagiSpawnCount,
	}, function(lo: number, hi: number): number
		return rng:NextInteger(lo, hi)
	end)

	if Config.Debug.VerboseLogging then
		-- COUNTS, NEVER CONTENTS. See the header: in a Studio solo test this window is in front of the
		-- player. `Placed` and the pool size are safe — both are derivable from Config and the map.
		local placed = if layout then layout.Placed else 0

		print(`[SearchService] Seeded {placed} item(s) across {#orderedNames} containers.`)
	end
end

local function clearLayout()
	layout = nil

	table.clear(opened)
	table.clear(orderedNames)
	table.clear(indexByName)
	table.clear(containersByName)
end

--------------------------------------------------------------------------------
-- The hold. ONE AUTHORITY AND ONE REVERSE INDEX.
--
-- `holds` is the truth: a player either has a hold or does not. `occupied` exists
-- only so that "is anybody on this container" is a lookup rather than a scan of
-- every player, and it is written by beginHold and releaseHold and by nothing
-- else. If the two ever disagree, `holds` wins — but the point of confining the
-- writes to two functions is that they cannot.
--------------------------------------------------------------------------------

type Hold = {
	ContainerIndex: number,
	-- Cached so the tick does not re-resolve the part every pass, and so a container deleted from the
	-- map mid-hold releases cleanly instead of erroring.
	Name: string,
	EndsAt: number,
}

local holds: { [number]: Hold } = {}
local occupied: { [number]: number } = {}

--[[
	WHAT THIS PLAYER HAS FOUND THIS ROUND. Server-only, keyed by UserId, never replicated as a table.

	V03 RECORDS AND GRANTS NOTHING — see `SearchService.ItemFound`. This exists so that V08 has
	somewhere truthful to read from, and so that a playtester can confirm "searching yields items"
	from the server side rather than from a client's word for it.

	A ROSTER OF WHO HOLDS WHAT IS A ROSTER OF WHO CAN ANSWER THE ASWANG, which is `ItemService`'s
	stated reason for keeping `carried` server-side, and §4.5's reason the buntot pagi's carrier
	announces themselves by CHOICE. Never broadcast this, never mirror it onto an attribute.
]]
local foundByPlayer: { [number]: { string } } = {}

local updateRemote = Remotes.Get("SearchUpdate")

--[[
	FireClient to ONE player, and this is the only function in the file that sends anything.

	Built as a TYPED LOCAL rather than an inline table for `ItemService.broadcastEffect`'s reason:
	`FireClient` takes `...any`, so an inline literal is unchecked and a typo'd field name would ship.
	The annotation is what makes `Types.SearchUpdatePayload`'s absent-field argument enforceable.
]]
local function sendUpdate(player: Player, verdict: Types.SearchVerdict, found: Types.ItemType?)
	local payload: Types.SearchUpdatePayload = {
		Verdict = verdict,
		-- Only a live hold has a duration. Every refusal and every ending sends 0, so a client cannot
		-- read a timing difference off a refusal.
		HoldSeconds = if verdict == "SEARCH_STARTED" then Config.Search.SearchTime else 0,
		Found = found,
	}

	updateRemote:FireClient(player, payload)
end

local function beginHold(player: Player, containerIndex: number, name: string)
	holds[player.UserId] = {
		ContainerIndex = containerIndex,
		Name = name,
		EndsAt = os.clock() + Config.Search.SearchTime,
	}
	occupied[containerIndex] = player.UserId

	--[[
		V04, §4.4. THE PRICE, PAID UP FRONT. "The noise is the entire risk economy… you cannot be
		safe and productive at the same time."

		AT THE START RATHER THAN AT COMPLETION, deliberately: a search cancelled at 5.9 seconds has
		still happened, and a noise that waited for SEARCH_OK would make start/cancel a free, silent
		way to learn which containers are still worth walking to.

		AT THE CONTAINER rather than at the player — the server resolved which container this is, so
		the position is already known and does not wobble with where inside RangeStuds the searcher
		stands. Nil when a map author deleted the part between the resolve and here; the hold is
		still valid and the tick will release it, so this skips the noise rather than erroring.

		NO ROLE BRANCH, AND THERE MUST NOT BE ONE. See this file's header: the Aswang searches on
		identical rules, so it makes identical noise. A silent monster is identified by the container
		nobody heard.
	]]
	local container: BasePart? = containersByName[name]

	if container ~= nil then
		NoiseService.Emit(player, "SEARCH", container.Position)
	end

	sendUpdate(player, "SEARCH_STARTED", nil)
end

--[[
	THE ONLY WAY A HOLD ENDS. Every one of the six paths goes through here, and that is the entire
	design of this section: a release path that clears `holds` without clearing `occupied` locks a
	container for the rest of the round, with no symptom except that nobody can search it.

	`verdict` is nil when the caller has already sent its own message — `completeHold` sends SEARCH_OK
	with the item and must not be followed by an INTERRUPTED. Every other caller passes one.

	SAFE TO CALL FOR A PLAYER WITH NO HOLD. Three of the six paths (leaving, dying, a phase change)
	fire for players who were not searching, and an early return is cheaper than six callers checking.
]]
local function releaseHold(userId: number, verdict: Types.SearchVerdict?)
	local hold = holds[userId]

	if hold == nil then
		return
	end

	holds[userId] = nil

	-- Guarded rather than assigned blindly: if two holds ever raced onto one container, clearing the
	-- index unconditionally would release the OTHER player's lock. beginHold's SEARCH_OCCUPIED check
	-- makes that unreachable; this makes it harmless if it ever stops being.
	if occupied[hold.ContainerIndex] == userId then
		occupied[hold.ContainerIndex] = nil
	end

	if verdict == nil then
		return
	end

	local player = Players:GetPlayerByUserId(userId)

	if player ~= nil then
		sendUpdate(player, verdict, nil)
	end
end

-- Path 6: every phase that is not ACTIVE.
local function releaseAllHolds(verdict: Types.SearchVerdict)
	for userId in holds do
		releaseHold(userId, verdict)
	end
end

--[[
	Path 1: the hold ran its course. The ONLY path that yields an item.

	`opened` is marked BEFORE the item is read, so that no early return below can leave a container
	both spent and re-searchable. Items belong to the world (§4.4's anti-frustration rule), so a
	container empties for everyone, not per player.
]]
local function completeHold(player: Player, hold: Hold)
	local current = layout

	opened[hold.ContainerIndex] = true

	releaseHold(player.UserId, nil)

	if current == nil then
		sendUpdate(player, "SEARCH_OK", nil)
		return
	end

	-- Narrowed by a FUNCTION, not a cast. An id the module does not recognise arrives as nil and is
	-- reported as an empty container rather than waved into the payload — see ContainerLayout's
	-- header and `.claude/lessons/pure-module-unions-widen-in-lists.md`.
	local item: Types.ItemType? = ContainerLayout.itemAt(current, hold.ContainerIndex)

	if item == nil then
		-- §4.4: "You will open empty ones, and that is the point." This is the common case.
		sendUpdate(player, "SEARCH_OK", nil)
		return
	end

	local pocket = foundByPlayer[player.UserId]

	if pocket == nil then
		pocket = {}
		foundByPlayer[player.UserId] = pocket
	end

	table.insert(pocket, item)

	sendUpdate(player, "SEARCH_OK", item)

	-- V08 connects here. V03 connects nothing; see SearchService.ItemFound.
	SearchService.ItemFound:Fire(player, item)
end

--[[
	Resolve the part a hold is on, and how far the searcher has strayed from it.

	Returns nil when the container has stopped existing — a map author deleting a tagged part mid-round
	is a real thing and it must release the hold rather than error inside the tick.
]]
local function holdDistance(player: Player, hold: Hold): number?
	local container: BasePart? = containersByName[hold.Name]
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if container == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end

	return (container.Position - root.Position).Magnitude
end

--[[
	THE TICK. Paths 2 (moved out of range) and 3 (no longer ALIVE), plus path 1's trigger.

	Assigning nil to an existing key during a generalised-for traversal is defined behaviour in Luau,
	so releasing a hold from inside this loop is safe. `releaseHold` writes a DIFFERENT table
	(`occupied`), which is not being traversed.
]]
local function searchTick()
	local now = os.clock()

	for userId, hold in holds do
		local player = Players:GetPlayerByUserId(userId)

		-- Path 4's backstop. PlayerRemoving normally gets there first; this covers the window where it
		-- has not fired yet.
		if player == nil then
			releaseHold(userId, nil)
			continue
		end

		-- Path 3. DEAD or SPECTATOR, or a character that has gone away underneath them.
		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
			releaseHold(userId, "SEARCH_INTERRUPTED")
			continue
		end

		local distance = holdDistance(player, hold)

		-- Path 2. Walked away, or the container stopped existing. §4.4's six seconds are only a cost
		-- if they must be spent standing still — this line is what makes them one.
		if distance == nil or distance > Config.Search.RangeStuds then
			releaseHold(userId, "SEARCH_INTERRUPTED")
			continue
		end

		if now >= hold.EndsAt then
			completeHold(player, hold)
		end
	end
end

--------------------------------------------------------------------------------
-- Resolution. The client names nothing; the server decides everything.
--------------------------------------------------------------------------------

--[[
	THE NEAREST CONTAINER THIS PLAYER IS STANDING AT, or nil.

	Resolved from the player's OWN character position — `ItemService`'s stated rule, and the reason
	`RequestSearch` carries no argument. A client that could name a container could probe every one of
	them from across the map and read the verdicts back as a map index.

	Nearest rather than first-found because two containers can overlap within RangeStuds — under a
	papag beside a sack — and "the one I am closest to" is the only answer a player will not call a bug.
]]
local function nearestContainer(player: Player): (number?, string?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end

	local bestIndex: number? = nil
	local bestName: string? = nil
	local bestDistance = Config.Search.RangeStuds

	for name, container in containersByName do
		local distance = (container.Position - root.Position).Magnitude

		if distance <= bestDistance then
			bestDistance = distance
			bestName = name
			bestIndex = indexByName[name]
		end
	end

	return bestIndex, bestName
end

--[[
	THE GATE, IN BLOCKING-FIRST ORDER, and the order is most of the content.

	Phase and liveness come before anything positional, so a player searching in the lobby is told the
	true reason rather than "no container near you". Container identity comes last, because it is the
	only branch that reveals anything about the world, and a player who fails an earlier gate has not
	earned an answer about the world.

	NO BRANCH HERE READS THE ASWANG'S IDENTITY, and none may. §4.4 and Amendment A2: the monster
	searches on identical rules, and any activity it cannot perform sincerely becomes an oracle.
]]
local function evaluateSearch(player: Player): (Types.SearchVerdict, number?, string?)
	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return "SEARCH_WRONG_PHASE", nil, nil
	end

	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
		return "SEARCH_NOT_ALIVE", nil, nil
	end

	if holds[player.UserId] ~= nil then
		return "SEARCH_BUSY", nil, nil
	end

	local index, name = nearestContainer(player)

	-- Covers both "nothing within RangeStuds" and "this map has no pool at all" — the EMPTY verdict
	-- leaves containersByName cleared, so the loop above finds nothing and the player is told the
	-- same true thing either way.
	if index == nil or name == nil then
		return "SEARCH_NO_CONTAINER", nil, nil
	end

	if opened[index] then
		-- §4.4: items belong to the world, not to individuals. A container someone else emptied is
		-- empty for you too, and telling you so beats six seconds spent finding out.
		return "SEARCH_ALREADY_SEARCHED", nil, nil
	end

	if occupied[index] ~= nil then
		return "SEARCH_OCCUPIED", nil, nil
	end

	return "SEARCH_STARTED", index, name
end

--------------------------------------------------------------------------------
-- Phase subscription. RoundService owns the phase; this only reacts to it.
--------------------------------------------------------------------------------

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Starting then
		seedLayout()
	end

	--[[
		EVERY PHASE THAT IS NOT ACTIVE releases every hold — including STARTING, which is why this sits
		BELOW the seed above rather than beside it. A hold surviving into the next round would be a
		player searching a container whose contents have just been redrawn.

		The layout itself is cleared only on the way DOWN (INTERMISSION/IDLE), not at ENDING: §4.8's
		end screen runs for Config.Round.EndScreen seconds and there is no reason to tear state down
		while it does.
	]]
	if phase ~= Enums.RoundPhase.Active then
		releaseAllHolds("SEARCH_INTERRUPTED")
	end

	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearLayout()
	end
end

function SearchService.Init()
	clearLayout()
end

function SearchService.Start()
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		CONSUME FIRST. `check-ratelimit.mjs` is a proximity tripwire around `.OnServerEvent:Connect(`,
		so a handler that limits itself further down reads as unguarded and fails the build. It is also
		simply correct: the cheapest possible refusal is the one that happens before any work.

		NO ARGUMENT IS ACCEPTED, so there is nothing to type-check after it. Every other handler in
		this repo validates `unknown` here; this one has nothing to validate, which is the point of
		the remote carrying no container id.
	]]
	Remotes.Get("RequestSearch").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestSearch") then
			return
		end

		local verdict: Types.SearchVerdict, index, name = evaluateSearch(player)

		if verdict ~= "SEARCH_STARTED" or index == nil or name == nil then
			sendUpdate(player, verdict, nil)
			return
		end

		beginHold(player, index, name)
	end)

	--[[
		Path 5: the player let go. Also argument-free, also Consume first.

		IDEMPOTENT BY CONSTRUCTION — `releaseHold` returns early for a player with no hold — so a
		duplicate cancel is free and a cancel that arrives after the hold already completed cannot
		un-find an item.
	]]
	Remotes.Get("RequestCancelSearch").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestCancelSearch") then
			return
		end

		releaseHold(player.UserId, "SEARCH_INTERRUPTED")
	end)

	-- Path 4. A departing player's hold goes with them, and their pocket with it. Without this both
	-- tables grow for the life of the server.
	Players.PlayerRemoving:Connect(function(player: Player)
		releaseHold(player.UserId, nil)

		foundByPlayer[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			searchTick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
end

return SearchService
