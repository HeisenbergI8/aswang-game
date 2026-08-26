--!strict
--[[
	ItemService — Salt: spawning, pickup, throwing, stun and reveal.

	Milestone: M4
	Spec: docs/MVP-SPEC.md

	SALT IS THE ONLY COUNTERPLAY IN THE GAME (§4.6), and this file is deliberately the least clever one
	in the repo. Four things happen here and each is server-decided:

	  · pouches spawn at `SaltSpawn` points at STARTING          (C13)
	  · a player walking within PickupRangeStuds picks one up    (C13, no remote — see below)
	  · RequestThrowSalt(direction) is resolved into a hit       (C14, pure/SaltThrow)
	  · a hit stuns, forces a revert, and glows for RevealDuration (C14)

	THERE IS NO PICKUP REMOTE AND THAT IS A SECURITY DECISION, not an omission. The rule: the server
	resolves what a player is standing at from that player's own character position, and the client
	names nothing. A `RequestPickup(pouchId)` would need a budget,
	a verdict union, and validation that the named pouch is the one you are standing on — three
	surfaces bought to replace a distance comparison the server is already positioned to make.

	The pool verdict is `server/pure/SearchPool.evaluate`, shared rather than copied. It is generic
	over (names, required, expected) and names no mechanic at all.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local MonsterService = require(script.Parent.MonsterService)
local RoundService = require(script.Parent.RoundService)
local TeachingService = require(script.Parent.TeachingService)
local SearchPool = require(script.Parent.Parent.pure.SearchPool)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local SaltCarry = require(Shared.pure.SaltCarry)
local SaltThrow = require(Shared.pure.SaltThrow)
local Types = require(Shared.Types)

local ItemService = {}

local TAG_SPAWN = "SaltSpawn"

-- Every `SaltSpawn` part in the map, keyed by Name. Rebuilt on every draw rather than cached, for the
-- reason any tag-driven pool is: C17 will add, move and delete these parts while a server is running,
-- and a cached point is one that can stop existing.
local pointsByName: { [string]: BasePart } = {}

-- The pouches actually in the world right now. One parent so a phase change clears them with a single
-- pass, exactly as MonsterService's `Corpses` folder does.
local pouches: Folder? = nil

-- SERVER-ONLY. How many pouches each player is carrying, keyed by UserId. Never replicated as a table:
-- a roster of who is holding salt is a roster of who can answer the Aswang, and Amendment A3's whole
-- argument is that per-player facts about the living do not go out to everyone.
local carried: { [number]: number } = {}

local function discoverPool(): SearchPool.Report
	local names: { string } = {}

	table.clear(pointsByName)

	for _, instance in CollectionService:GetTagged(TAG_SPAWN) do
		if not instance:IsA("BasePart") then
			warn(
				`[ItemService] {instance:GetFullName()} is tagged {TAG_SPAWN} but is a `
					.. `{instance.ClassName}, not a BasePart — skipped.`
			)
			continue
		end

		table.insert(names, instance.Name)

		-- The `: BasePart?` is load-bearing under --!strict: indexing a
		-- `{ [string]: BasePart }` yields a non-optional value, so comparing it to nil is a type error
		-- rather than a lookup.
		local existing: BasePart? = pointsByName[instance.Name]

		if existing == nil then
			pointsByName[instance.Name] = instance
		end
	end

	-- Sorted because `GetTagged`'s order is engine-defined and must not become a hidden input to a
	-- random selection.
	table.sort(names)

	return SearchPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize)
end

--[[
	THE LOUD HALF, ungated by VerboseLogging because the rule in this repo is that routine tracing is
	gated and faults warn unconditionally — and a map with no salt in it is a fault
	whose only player-visible symptom is that the game is unwinnable and nobody knows why.
]]
local function reportPool(report: SearchPool.Report)
	if #report.Duplicates > 0 then
		warn(
			`[ItemService] {TAG_SPAWN} parts share a Name and were skipped: `
				.. `{table.concat(report.Duplicates, ", ")}. Every tagged part needs a unique one.`
		)
	end

	if report.Verdict == "EMPTY" then
		warn(
			`[ItemService] NO "{TAG_SPAWN}" PARTS IN THE MAP. Tag {Config.Salt.PouchPoolSize} anchored `
				.. `parts with "{TAG_SPAWN}" via CollectionService, or no salt can ever spawn and §4.6's `
				.. `counterplay does not exist — survivors have no answer to the Aswang at all.`
		)
	elseif report.Verdict == "SHORT" then
		warn(
			`[ItemService] Only {#report.Unique} "{TAG_SPAWN}" part(s) found; `
				.. `{Config.Salt.SpawnCount} pouches are meant to spawn. Fewer will.`
		)
	elseif report.Verdict == "OVERSIZED" then
		warn(
			`[ItemService] {#report.Unique} "{TAG_SPAWN}" parts found, but Config.Salt.PouchPoolSize `
				.. `says {Config.Salt.PouchPoolSize}. Spawning still works; the map and Config disagree.`
		)
	elseif Config.Debug.VerboseLogging then
		print(`[ItemService] Salt pool OK — {#report.Unique} spawn points.`)
	end
end

--[[
	Exposed for Step 2.5's spawn, which needs both the verdict and the parts behind it. Returning the
	report rather than the table keeps `pointsByName` private: a caller that wanted the parts would have
	to ask for a name it already got from the report.
]]
function ItemService.EvaluatePool(): SearchPool.Report
	local report = discoverPool()

	reportPool(report)

	return report
end

-- Copied from MonsterService rather than exported from it: a four-line colour helper is not worth a
-- cross-service dependency, and the alternative is ItemService requiring MonsterService for a Color3.
local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: RGB channel indices, not knobs
end

--[[
	THE POUCH. A part, a tag, and nothing else.

	No ProximityPrompt: C08 already found that Roblox's CoreScript refuses to render a prompt with
	`KeyboardKeyCode = None`, and a pickup that costs a keypress is a pickup a player walks past. This
	is a thing you collect by touching, resolved server-side on a tick.

	`SaltPouch` IS A REPLICATED TAG AND THAT IS FINE, on the same argument `ActiveTaskPoint` won at
	C07: it describes an object in the world that every client can already see, it names no player, and
	the client needs it to draw the pickup affordance at all. `check:secrecy` inspects tags and this one
	passes because it carries nothing.
]]
local TAG_POUCH = "SaltPouch"

local rng = Random.new()

local function spawnPouches()
	local folder = pouches

	if folder == nil then
		return
	end

	local report = discoverPool()

	reportPool(report)

	-- Fisher-Yates over a COPY, so the pool order is not mutated under the caller. `Random.new()` with
	-- no argument, deliberately: a seeded draw is reproducible by anyone who can guess the seed, and
	-- `Random.new(os.time())` is client-observable to the second.
	local names = table.clone(report.Unique)

	for index = #names, 2, -1 do
		local swap = rng:NextInteger(1, index)

		names[index], names[swap] = names[swap], names[index]
	end

	local wanted = math.min(Config.Salt.SpawnCount, #names)

	for index = 1, wanted do
		local point: BasePart? = pointsByName[names[index]]

		if point == nil then
			continue
		end

		local pouch = Instance.new("Part")

		pouch.Name = `SaltPouch_{names[index]}`
		pouch.Size = Vector3.new(1, 1, 1) -- config-ok: the pouch's own size, not a balance knob
		pouch.Position = point.Position + Vector3.new(0, 1, 0) -- config-ok: sits on the pad, not a knob
		pouch.Anchored = true
		pouch.CanCollide = false
		pouch.Color = rgb(Config.Salt.PouchRgb)
		pouch.Material = Enum.Material.Sand
		pouch.Parent = folder

		--[[
			A LABEL AND A GLOW, so a pouch reads as salt rather than as a white cube.

			This is presentation, and it is here rather than on the client for one reason: the pouch is
			ALREADY a fully public replicated object, so a BillboardGui on it tells nobody anything they
			could not see by walking over. Nothing about it is per-player, so there is no secrecy question
			— compare the reveal Highlight, which is deliberately server-owned for the opposite reason.

			C34 replaces this with an actual model. Until then a tester needs to be able to find the one
			mechanic that answers the monster.
		]]
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PouchLabel"
		billboard.Size = UDim2.fromOffset(60, 20) -- config-ok: placeholder label size, replaced at C34
		billboard.StudsOffset = Vector3.new(0, 1.5, 0) -- config-ok: sits above the pouch
		billboard.AlwaysOnTop = true
		billboard.Parent = pouch

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = "SALT"
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.Parent = billboard

		local glow = Instance.new("PointLight")
		glow.Name = "PouchGlow"
		glow.Color = rgb(Config.Salt.PouchRgb)
		glow.Brightness = 2 -- config-ok: placeholder pickup affordance, replaced at C34
		glow.Range = 8 -- config-ok: same
		glow.Parent = pouch

		CollectionService:AddTag(pouch, TAG_POUCH)
	end

	if Config.Debug.VerboseLogging then
		print(`[ItemService] {wanted} pouch(es) placed of {Config.Salt.SpawnCount} wanted.`)
	end
end

-- Everything this service put in the world, and everything it remembers. Called on the way into
-- INTERMISSION and IDLE, mirroring MonsterService.clearCorpses — NOT on "any phase that is not ACTIVE",
-- which is the mistake that destroyed the winning kill's corpse within a frame of creating it.
local function clearPouches()
	local folder = pouches

	if folder ~= nil then
		for _, pouch in folder:GetChildren() do
			pouch:Destroy()
		end
	end

	table.clear(carried)
end

--[[
	THE PICKUP TICK. Distance re-measured on the server every tick from the player's own character,
	which is C08 Step 3.3's rule: a stamp a client sent is a stamp a client chose.

	O(players x pouches) is at most 8 x 4 per tick and there is no cheaper shape worth writing. A
	spatial query would be `workspace:GetPartBoundsInRadius`, which allocates per call and is the
	wrong trade at this size — §5's budget is about frame cost on a phone, and this loop runs on the
	server.
]]
local function pickupTick()
	local folder = pouches

	if folder == nil or RoundService.GetPhase() ~= Enums.RoundPhase.Active then
		return
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

		if root == nil or not root:IsA("BasePart") then
			continue
		end

		local verdict = SaltCarry.evaluate({
			Phase = RoundService.GetPhase(),
			PlayerState = RoundService.GetPlayerState(player),
			Carried = carried[player.UserId] or 0,
			Limit = Config.Salt.CarryLimit,
		})

		if verdict ~= "OK" then
			continue
		end

		for _, pouch in folder:GetChildren() do
			if not pouch:IsA("BasePart") then
				continue
			end

			if (pouch.Position - root.Position).Magnitude > Config.Salt.PickupRangeStuds then
				continue
			end

			carried[player.UserId] = (carried[player.UserId] or 0) + 1
			pouch:Destroy()

			-- C23. The first pouch a player ever takes explains what it is for. §10 is explicit that
			-- the folklore must not be assumed. Fired to the player who did it, about a thing they
			-- did themselves — no audience question here.
			TeachingService.Cue(player, "CUE_FIRST_SALT")

			-- ONE PER TICK PER PLAYER. Breaking here rather than continuing means two pouches lying in
			-- the same spot cannot both be taken in one frame by a player whose limit is 1 — the
			-- SaltCarry call above is outside this loop and would not have seen the first pickup.
			break
		end
	end
end

--------------------------------------------------------------------------------
-- C14 — the throw, the stun, the reveal
--------------------------------------------------------------------------------

-- Vector3 -> the plain table pure/SaltThrow takes. The pure module cannot mention Vector3: Lune has no
-- Roblox datatypes and the whole module would stop being runnable from a terminal.
local function vec(position: Vector3): SaltThrow.Vec3
	return { X = position.X, Y = position.Y, Z = position.Z }
end

-- Who is stunned, and what their movement was before salt touched it. SERVER-ONLY. The generation
-- number is MonsterService.revert's trick, borrowed for the same reason: a second hit landing during
-- the first hit's window must invalidate the first timer, or the earlier restore fires mid-stun.
type StunState = {
	WalkSpeed: number,
	JumpPower: number,
	Generation: number,
}

local stunned: { [number]: StunState } = {}

local function clearStun(player: Player)
	local state = stunned[player.UserId]

	if state == nil then
		return
	end

	stunned[player.UserId] = nil

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if humanoid == nil then
		return
	end

	--[[
		RESTORE WHAT WAS CAPTURED. Not 16, not `Humanoid.WalkSpeed`'s default, and NOT
		`Config.Monster.TransformedSpeedMult * 16` — the target may have reverted during the stun, so
		neither the transformed nor the untransformed value is knowable from here. C04's audit found
		exactly this restored-from-default bug and nothing static caught it.
	]]
	humanoid.WalkSpeed = state.WalkSpeed
	humanoid.JumpPower = state.JumpPower
end

local function applyStun(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if humanoid == nil then
		return
	end

	local previous = stunned[player.UserId]
	local generation = (if previous then previous.Generation else 0) + 1

	--[[
		CAPTURE ONLY ON THE FIRST HIT. A second hit landing mid-stun would otherwise capture 0/0 as
		"what they had before", and the restore would leave a player frozen for the rest of the round.
		The generation bump still fires, so the second hit extends the window; only the captured values
		are kept from the first.
	]]
	stunned[player.UserId] = {
		WalkSpeed = if previous then previous.WalkSpeed else humanoid.WalkSpeed,
		JumpPower = if previous then previous.JumpPower else humanoid.JumpPower,
		Generation = generation,
	}

	humanoid.WalkSpeed = 0 -- config-ok: a stun is total; 0 is the mechanic, not a knob
	humanoid.JumpPower = 0 -- config-ok: same

	task.delay(Config.Salt.StunDuration, function()
		local current = stunned[player.UserId]

		-- A stale timer from an earlier hit declines to act, exactly as MonsterService's forced-revert
		-- timer does. Without this, hit-at-t and hit-at-t+2 would both restore at t+4 and t+6, and the
		-- FIRST would end the second hit's stun two seconds early.
		if current == nil or current.Generation ~= generation then
			return
		end

		clearStun(player)
	end)
end

-- Highlights this service created, keyed by UserId, with the same generation trick the stun uses.
type RevealState = {
	Instance: Highlight,
	Generation: number,
}

local reveals: { [number]: RevealState } = {}

local function clearReveal(userId: number)
	local state = reveals[userId]

	if state == nil then
		return
	end

	reveals[userId] = nil
	state.Instance:Destroy()
end

--[[
	THE REVEAL (§4.6, C14). A Highlight on a character, for RevealDuration, visible to everyone.

	A Highlight AND NOT: an attribute (replicates, and `check:secrecy` refuses role-named ones for
	exactly this reason), a CollectionService tag (same), a name colour (`TeamColor` and `Team` both
	replicate and are the classic version of this mistake), or a per-client effect (a "hidden" reveal
	is a reveal that a compromised client reads and an honest one does not — the worst of both).

	It is parented to the CHARACTER, not to the player, and the state table holds the instance rather
	than the character — so a respawn cannot leave an orphan behind and cannot brand a fresh body.

	NOTHING HERE IS NAMED FOR A ROLE. The instance is `SaltReveal`, the colours are
	`Config.Salt.RevealGlow*Rgb`, and neither `check:secrecy`'s SECRET regex nor a human reader finds a
	role in this code — because there is not one. The server never learns of a role at this point in
	the call chain either: `applyHit` receives a Player, and the decision that this Player was a
	transformed Aswang was made and discarded back in `resolveThrow`.

	`DepthMode = Occluded` is a design decision hiding in an enum value. `AlwaysOnTop` would render the
	glow THROUGH WALLS, turning a ten-second reveal into a ten-second wallhack on the monster.
]]
local function applyReveal(target: Player)
	local character = target.Character

	if character == nil then
		return
	end

	clearReveal(target.UserId)

	local highlight = Instance.new("Highlight")
	local generation = os.clock()

	highlight.Name = "SaltReveal"
	highlight.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
	highlight.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
	highlight.FillTransparency = 0.6 -- config-ok: the glow's own opacity, tuned by eye at C34
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	reveals[target.UserId] = { Instance = highlight, Generation = generation }

	task.delay(Config.Salt.RevealDuration, function()
		local current = reveals[target.UserId]

		if current == nil or current.Generation ~= generation then
			return
		end

		clearReveal(target.UserId)
	end)
end

--[[
	A SALT HIT: revert FIRST, then stun, then reveal.

	THE ORDER IS THE WHOLE CORRECTNESS OF THIS FUNCTION AND IT SHIPPED WRONG ONCE. The first version
	ran `applyStun` before `ForceRevert`, on the reasoning that capturing before the revert preserved
	"the speed they had when salt hit them". Both halves of that failed, and an exploit audit caught it:

	  1. `revert()` writes `monster.BaseWalkSpeed` (16) straight onto the humanoid, overwriting the
	     stun's WalkSpeed 0 in the same frame. THE STUN NEVER HAPPENED. §4.6's four seconds were a
	     no-op on movement.
	  2. Four seconds later `clearStun` restored the CAPTURED value — the TRANSFORMED speed, 20 — onto
	     a player who was no longer transformed. `applyBodyRule` only reloads a character when there
	     isn't one, so nothing ever wrote 16 back: the ex-Aswang kept +25% movement for the rest of the
	     round AND across the next one. `Humanoid.WalkSpeed` is a replicated property, so any client
	     could poll every character and find the single one reading 20. A permanent role brand,
	     readable map-wide, with no remote to intercept — the same shape as C04's revert bug, in the
	     same pair of services, with `check:secrecy` green over it.

	Reverting first means `applyStun` captures the HONEST post-revert speed, so the stun holds for its
	duration and restores a value indistinguishable from every other living player's.

	THE INVARIANT, stated so the next edit has something to violate: no path through this file may
	leave a living player's WalkSpeed different from every other living player's.

	Deliberately NOT a kill and NOT a MarkKilled: §4.6 is counterplay, not a win condition. Salt never
	ends a round.
]]
local function applyHit(target: Player)
	MonsterService.ForceRevert(target)
	applyStun(target)
	applyReveal(target)
end

-- EVERY reveal and EVERY stun ends when the round does. Called from onPhaseChanged beside
-- clearPouches, and this is the exit that actually matters: without it a player hit at second 419 of a
-- 420-second round is still glowing in the lobby, where the glow is no longer an event that anybody
-- witnessed and is simply a mark on one of the eight people standing there.
local function clearAllEffects()
	for userId in reveals do
		clearReveal(userId)
	end

	for userId in stunned do
		local player = Players:GetPlayerByUserId(userId)

		if player ~= nil then
			clearStun(player)
		end
	end

	table.clear(stunned)
end

local saltEffectRemote = Remotes.Get("SaltEffect")

--[[
	The public half of a throw. Fired to EVERY client, with a trajectory and no player.

	Built as a TYPED LOCAL, not an inline table: `FireAllClients` takes `...any`, so an inline literal
	is checked against nothing at all. The annotation catches a wrong type and a missing field — but
	NOT an extra one, which is the leak shape. See Types.SaltEffectPayload; the fields that must never
	appear there are `ThrowerUserId` and `TargetUserId`, and neither contains a token
	`check-secrecy.mjs` matches.

	FireAllClients IS CORRECT HERE and it is the only broadcast this plan adds. A throw is a white
	burst in the air at a place; every client standing there sees it whether or not this remote exists,
	and a client that is nowhere near renders a burst it cannot see. `Hit` says the salt struck
	something salt can strike — which, per pure/SaltThrow, means a TRANSFORMED Aswang, and a
	transformed Aswang is already public via MonsterTransformed. It buys a hit sound instead of a
	fizzle and states nothing new.
]]
local function broadcastEffect(thrower: Player, impact: Vector3, hit: boolean)
	local character = thrower.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local origin = if root and root:IsA("BasePart") then root.Position else impact

	local payload: Types.SaltEffectPayload = { Origin = origin, Impact = impact, Hit = hit }

	saltEffectRemote:FireAllClients(payload)
end

--[[
	The target the server picks for a throw. The CLIENT NAMES NOBODY — it sends a direction, and this
	function walks every candidate and returns the nearest one the cone accepts.

	IT EVALUATES EVERY PLAYER RATHER THAN SHORT-CIRCUITING ON THE ASWANG, and that is not wasted work:
	short-circuiting would make the loop's COST vary with whether the Aswang was in the cone, and
	server-side timing is not something a compromised client can measure — but the shape is also how
	the "one verdict for four worlds" property survives a future edit. There are at most eight players.
]]
local function resolveThrow(
	thrower: Player,
	direction: Vector3
): (Types.SaltVerdict, Player?, Vector3)
	local character = thrower.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		return "THROWER_NOT_ALIVE", nil, Vector3.zero
	end

	local origin = root.Position
	local aswangUserId = RoundService.GetAswangUserId()

	local best: Player? = nil
	local bestDistance = math.huge

	for _, candidate in Players:GetPlayers() do
		local candidateCharacter = candidate.Character
		local candidateRoot = if candidateCharacter
			then candidateCharacter:FindFirstChild("HumanoidRootPart")
			else nil

		if candidate == thrower or candidateRoot == nil or not candidateRoot:IsA("BasePart") then
			continue
		end

		--[[
			THE ROLE AND THE FORM ARE ANDed HERE AND NOWHERE ELSE. `pure/SaltThrow` receives one
			boolean and never learns that a role exists — which is what lets that module live in
			`shared/pure/` and be callable by any client without leaking anything.
		]]
		local isTransformedAswang = aswangUserId == candidate.UserId
			and MonsterService.IsTransformed(candidate.UserId)

		local verdict = SaltThrow.evaluate({
			Phase = RoundService.GetPhase(),
			ThrowerState = RoundService.GetPlayerState(thrower),
			Carried = carried[thrower.UserId] or 0,
			ThrowerPos = vec(origin),
			Direction = vec(direction),
			TargetPos = vec(candidateRoot.Position),
			TargetIsTransformedAswang = isTransformedAswang,
			Range = Config.Salt.ThrowRange,
			ConeDegrees = Config.Salt.ThrowConeDegrees,
		})

		--[[
			A NON-GEOMETRIC REFUSAL IS THE SAME FOR EVERY CANDIDATE, so returning it from inside the
			loop is correct rather than sloppy: WRONG_PHASE, THROWER_NOT_ALIVE and NO_POUCH depend only
			on the thrower, and re-deriving them per candidate is what keeps ONE call site for the whole
			rule instead of a pre-check that can drift from it.
		]]
		if verdict ~= "OK" and verdict ~= "MISS" then
			-- The cast is load-bearing and is CLAUDE.md's documented Luau bite: refining a literal
			-- union by excluding two of its members widens the remainder to plain `string`, which then
			-- fails to satisfy the declared return type. Six of the scaffold's seven original analyze
			-- errors were this exact shape.
			return verdict :: Types.SaltVerdict, nil, origin
		end

		if verdict == "OK" then
			local distance = (candidateRoot.Position - origin).Magnitude

			if distance < bestDistance then
				best = candidate
				bestDistance = distance
			end
		end
	end

	if best == nil then
		--[[
			The thrower is ALIVE, in ACTIVE, holding a pouch, and hit nothing. The pouch is still spent.

			`direction.Unit` on a zero or non-finite vector yields NaN rather than throwing, so the
			impact point would be NaN and the burst would render nowhere. Guarded rather than trusted —
			this is the one place a client's raw vector reaches arithmetic, and `pure/SaltThrow` has
			already refused the throw by this point but does not hand back a sanitised direction.
		]]
		local magnitude = direction.Magnitude
		local aim = if magnitude > 0 and magnitude < math.huge then direction.Unit else Vector3.zero

		return "MISS", nil, origin + aim * Config.Salt.ThrowRange
	end

	local bestCharacter = (best :: Player).Character
	local bestRoot = if bestCharacter then bestCharacter:FindFirstChild("HumanoidRootPart") else nil
	local impact = if bestRoot and bestRoot:IsA("BasePart") then bestRoot.Position else origin

	return "OK", best, impact
end

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase == Enums.RoundPhase.Starting then
		spawnPouches()
	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearPouches()
	end

	--[[
		EVERY phase that is not ACTIVE, unlike clearPouches which fires only on INTERMISSION/IDLE. The
		difference mirrors MonsterService.onPhaseChanged's split and it is deliberate: pouches lying on
		the ground during ENDING are scenery, a glow during ENDING is a mark on a player.
	]]
	if phase ~= Enums.RoundPhase.Active then
		clearAllEffects()
	end
end

function ItemService.Init()
	table.clear(carried)
	table.clear(pointsByName)
end

function ItemService.Start()
	local folder = Instance.new("Folder")

	folder.Name = "SaltPouches"
	folder.Parent = workspace
	pouches = folder

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		A departing player's carry goes with them. Without this the table grows for the life of the
		server and, worse, a returning player would inherit their own old pouch count.

		NOTE FOR PHASE 5. The user's disconnect-husk rule preserves a player's STATE across a
		reconnect, and it is an open question whether their CARRY should travel with it — the husk is
		meant to be the same body standing in the same place, which argues the pouch is still in its
		hand. Dropping it here is the conservative choice (a rejoining player never gains salt) and it
		is the one that is safe if the husk never ships. Revisit when Phase 5 lands rather than
		assuming this line is settled.
	]]
	Players.PlayerRemoving:Connect(function(player: Player)
		carried[player.UserId] = nil

		-- Both effect tables too, or a disconnect mid-stun leaves an entry pointing at a destroyed
		-- character and a Highlight this service still believes it owns. `clearReveal` destroys the
		-- instance it holds rather than looking it up through the character, so it works after the
		-- character is gone; `stunned` is dropped directly because there is no humanoid left to restore.
		clearReveal(player.UserId)
		stunned[player.UserId] = nil
	end)

	--[[
		THE GLOWING CORPSE, closed here rather than left to the timer.

		`MonsterService.makeCorpse` DETACHES the victim's character and keeps it in the workspace for
		`CorpseDuration`. A Highlight parented to that character goes with it — so a player revealed by
		salt and then killed leaves a glowing body lying in the Barrio, which reads to every passer-by
		as "this corpse was the monster". The reveal is supposed to be an event that expires, not a
		label on a body.

		The Aswang cannot be killed, so the reachable paths are a reset or a fall while revealed. Cheap
		to close and ugly if it ever shows up in a playtest video.
	]]
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			clearReveal(player.UserId)
		end)
	end)

	--[[
		THE RATE LIMIT IS INLINE AND FIRST, copying MonsterService's two handlers exactly.
		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire — so
		a handler that IS limited but does it elsewhere reads as unguarded and fails the build. Consume
		FIRST, before the argument is even looked at.
	]]
	Remotes.Get("RequestThrowSalt").OnServerEvent
		:Connect(function(player: Player, direction: unknown)
			if not AntiCheatService.Consume(player, "RequestThrowSalt") then
				return
			end

			-- A remote argument is whatever the client sent. Typed `unknown` rather than `Vector3` so this
			-- line cannot be skipped: without it a table reaches `.Unit` and throws inside a connection,
			-- which Roblox swallows into a single warn.
			if typeof(direction) ~= "Vector3" then
				return
			end

			local verdict, target, impact = resolveThrow(player, direction)

			--[[
			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK. The client learns what happened
			the way everyone else does — from SaltEffect and from the world. See Types.SaltVerdict: a
			verdict echoed back is a role oracle for the price of one pouch.
		]]
			if verdict ~= "OK" and verdict ~= "MISS" then
				if Config.Debug.VerboseLogging then
					-- A UserId and a verdict. Never the target, and never a role.
					print(`[ItemService] Throw refused for {player.UserId}: {verdict}`)
				end

				return
			end

			-- §4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO, and this line sits above the
			-- hit branch so that no future early-return can skip it. A miss that cost nothing would make
			-- salt a probe you throw at everyone, which is the thing pure/SaltThrow's header refuses.
			carried[player.UserId] = math.max(0, (carried[player.UserId] or 0) - 1)

			if verdict == "OK" and target ~= nil then
				applyHit(target)
			end

			broadcastEffect(player, impact, verdict == "OK")
		end)

	task.spawn(function()
		while true do
			pickupTick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
end

return ItemService
