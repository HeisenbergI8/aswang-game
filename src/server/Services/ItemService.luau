--!strict
--[[
	ItemService — the three items: the carry slot, dropping, throwing, placing, stun and reveal.

	Milestone: V09
	Spec: docs/MVP-SPEC.md §4.6

	THE ITEMS ARE THE ONLY COUNTERPLAY IN THE GAME (§4.6), and this file is deliberately the least
	clever one in the repo. Six things happen here and each is server-decided:

	  · a completed search yields an item into ONE carry slot     (V08, SearchService.ItemFound)
	  · RequestDropItem() puts it back on the floor               (V08, argument-free)
	  · RequestThrowSalt(direction) is resolved into a hit        (C14, pure/ItemThrow)
	  · a hit stuns, forces a revert, and glows for RevealDuration (C14)
	  · RequestPlaceGarlic() denies one doorway for 15 seconds    (V09, pure/GarlicPlacement)
	  · the Aswang's crossings are sampled against live barriers  (V09, pure/GarlicBarrier)

	ITEMS COME FROM CONTAINERS, NEVER FROM A SPAWN POINT. V08 deleted the `SaltSpawn` pool, the pouch
	parts and the walk-over pickup tick that C13 shipped. V03 had already built the replacement —
	`SearchService` seeds all seven items into containers from `Config.Items.*SpawnCount` and fires
	`ItemFound` on a completed search — and the two economies were live at once, which put eight
	pouches in a round where §4.6 says four and broke §6.5 invariant 1 without touching a number.

	THERE IS STILL NO PICKUP REMOTE AND THAT IS STILL A SECURITY DECISION. The rule is unchanged and
	is now enforced in two places: the server resolves what a player is standing at from that
	player's own character position, and the client names nothing. `RequestDropItem` therefore takes
	NO ARGUMENT — with `Config.Items.CarryLimit = 1` there is exactly one thing you can be holding
	and the server already knows what it is. A `RequestDropItem(itemType)` would be a handler that
	spawns an item the client named, and one of the three items is the round's only win condition.

	ONE SLOT, THREE ITEM TYPES, NO RECHARGE. `pure/ItemCarry` owns whether a pickup is allowed,
	`pure/ItemThrow` owns whether a throw connects, and `pure/GarlicPlacement` owns whether bawang may
	be placed. The buntot pagi is CARRIED AND DROPPED ONLY — the strike is V10 and is not half-built
	here; `pure/ItemUse` is where that boundary is written down.

	V09 ADDED THE DOORWAY BLOCK, AND THE HALF OF IT THAT IS NOT IN THIS FILE IS THE HALF THAT MATTERS.
	This service places the public garlic bulb, owns the burn-out clock, and pushes the live barrier
	list to exactly the Aswang. It does NOT block anybody: §4.6 requires the block to be silent and
	invisible in its effect — no knockback, no VFX, no sound — because garlic invites a loyalty test
	and that test only stays a game if REFUSING is indistinguishable from BEING UNABLE. So the
	collidable part exists in the Aswang's own client's workspace (`client/GarlicController`), where
	its own physics stops it and nothing replicates outward but a position.

	WHICH MEANS THIS SERVICE IS NOT THE AUTHORITY ON THE BLOCK, AND `sampleBreaches` IS THE ANSWER TO
	THAT. A client that deletes its barrier walks through; the server cannot see the part, so it
	compares positions it DID see against a plane it owns. That correction is the only observable this
	chunk permits, and it is reachable only by cheating — read `checkBreach`'s header before touching
	any of it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local MonsterService = require(script.Parent.MonsterService)
local NoiseService = require(script.Parent.NoiseService)
local RoundService = require(script.Parent.RoundService)
local SearchService = require(script.Parent.SearchService)
local TeachingService = require(script.Parent.TeachingService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local ItemCarry = require(Shared.pure.ItemCarry)
local ItemDrop = require(Shared.pure.ItemDrop)
local ItemUse = require(Shared.pure.ItemUse)
local ItemThrow = require(Shared.pure.ItemThrow)
local GarlicBarrier = require(Shared.pure.GarlicBarrier)
local GarlicPlacement = require(Shared.pure.GarlicPlacement)
local Types = require(Shared.Types)

local ItemService = {}

--[[
	The items lying on the ground right now. One parent so a phase change clears them with a single
	pass, exactly as MonsterService's `Corpses` folder does.

	IT REPLACES THE `SaltPouches` FOLDER AND IT IS NOT THE SAME THING. `SaltPouches` held items the
	round SPAWNED; this holds items a player PUT DOWN — on purpose, on death, or on a disconnect.
	Nothing seeds it at STARTING, because containers are where items come from now.

	AND SINCE V09 THE NAME UNDERSTATES IT: placed bawang lives here too, tagged `PlacedGarlic` rather
	than `DroppedItem` so nothing tries to pick it back up off a threshold. It is not a dropped item —
	it is a placed one, with a clock. A SECOND FOLDER WOULD BE WORSE: the phase sweep being a single
	pass over a single parent is what makes it correct, and two parents means two sweeps that can
	disagree. The name is the cost of that, and this sentence is the fix.
]]
local droppedItems: Folder? = nil

--[[
	SERVER-ONLY. THE SLOT. What each player is holding, keyed by UserId, or absent for an empty hand.

	NEVER REPLICATED AS A TABLE. A roster of who holds what is a roster of who can answer the Aswang
	— C13 said it about a salt count and it is sharper now, because one entry in this table is the
	buntot pagi and §4.6 makes its carrier a target. `SearchService.foundByPlayer` carries the same
	warning for the same reason.

	THE ASWANG IS IN THIS TABLE LIKE EVERYONE ELSE. §4.4 has the monster searching on identical
	rules, so it finds items, fills this slot and drops things. That is not an oversight to be
	optimised away: `Types.ClientRoundSnapshot.YourCarriedItem` is safe precisely because an
	empty-handed survivor and the Aswang are indistinguishable, and they only are if the monster can
	genuinely hold things. A `if isAswang then return end` here would make an empty slot a tell.

	ONE ENTRY PER PLAYER, NOT A LIST, and `Config.Items.CarryLimit = 1` is why. `pure/ItemCarry`
	compares an occupancy against that number so the rule has one home; this table's SHAPE is the
	second enforcement, and it is the one that cannot drift.
]]
local slot: { [number]: Types.ItemType } = {}

-- Copied from MonsterService rather than exported from it: a four-line colour helper is not worth a
-- cross-service dependency, and the alternative is ItemService requiring MonsterService for a Color3.
local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: RGB channel indices, not knobs
end

--------------------------------------------------------------------------------
-- C14 — the throw, the stun, the reveal
--------------------------------------------------------------------------------

-- Vector3 -> the plain table pure/ItemThrow takes. The pure module cannot mention Vector3: Lune has no
-- Roblox datatypes and the whole module would stop being runnable from a terminal.
local function vec(position: Vector3): ItemThrow.Vec3
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

	task.delay(Config.Items.SaltStunDuration, function()
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

--[[
	A SALT HIT: revert FIRST, then stun, then reveal.

	V05 MOVED THE REVERT AND THE REVEAL INTO `MonsterService.ApplySaltHit`, because §4.6's reveal now
	carries the health readout — the glow brightens as the Aswang weakens — and health is server
	state that has exactly one home. What stays here is the STUN, which is salt's alone.

	THE ORDERING RULE SURVIVES THE MOVE UNCHANGED AND IS THE WHOLE CORRECTNESS OF THIS FUNCTION.
	`ApplySaltHit` reverts first; `applyStun` therefore captures the HONEST post-revert speed. The
	first version of this file ran the stun before the revert and produced a permanent, map-readable
	role brand — the story is below and it is worth reading before reordering these two lines.

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
	MonsterService.ApplySaltHit(target)
	applyStun(target)
end

-- EVERY stun ends when the round does. Called from onPhaseChanged beside clearPouches. The REVEAL's
-- half of this moved to `MonsterService.onPhaseChanged` at V05 along with the Highlight; the reason
-- it exists is repeated there, because it is the exit that actually matters.
local function clearAllEffects()
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
	something salt can strike — which, per pure/ItemThrow, means a TRANSFORMED Aswang, and a
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
): (Types.ItemThrowVerdict, Player?, Vector3)
	local character = thrower.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		return "ITEM_THROWER_NOT_ALIVE", nil, Vector3.zero
	end

	local origin = root.Position
	local aswangUserId = RoundService.GetAswangUserId()

	--[[
		THE THROWER-ONLY GATES, ANSWERED ONCE, BEFORE ANY CANDIDATE IS CONSIDERED.

		THIS SHIPPED WRONG AND AN EXPLOIT AUDIT PROVED IT BY RUNNING THE REAL MODULE. `ITEM_WRONG_PHASE`,
		`ITEM_THROWER_NOT_ALIVE` and `ITEM_NO_ITEM` depend only on the thrower — but they were produced
		only INSIDE the candidate loop below, past a `continue` that skips the thrower and anyone
		without a HumanoidRootPart. With zero surviving iterations the function fell through to the
		`best == nil` branch and returned MISS, so:

		    ENDING, holding salt, one candidate    -> ITEM_WRONG_PHASE   (refused, correctly)
		    ENDING, holding salt, ZERO candidates  -> MISS               (accepted, and SPENT)

		MISS reaches the spend line, so a solo player in ENDING or a dead player alone in the barrio
		burned their salt and fired a `SaltEffect` burst. Narrow in a live 3-5 player round — the C15
		redesign keeps a dead player's character attached, so they still count as candidates — and
		wide open in a solo session, which `Debug.SoloTesting` permits.

		A SENTINEL TARGET RATHER THAN A SECOND COPY OF THE RULES. The call below uses the thrower's own
		position and `TargetIsTransformedAswang = false`, which can only ever produce a thrower-gate
		verdict or MISS — never OK. So this asks `pure/ItemThrow` the thrower question using
		`pure/ItemThrow`'s own answers, and there is no second predicate here to drift from the first.
	]]
	local throwerVerdict = ItemThrow.evaluate({
		Phase = RoundService.GetPhase(),
		ThrowerState = RoundService.GetPlayerState(thrower),
		Held = slot[thrower.UserId],
		ThrowerPos = vec(origin),
		Direction = vec(direction),
		TargetPos = vec(origin),
		TargetIsTransformedAswang = false,
		Range = Config.Items.SaltThrowRange,
		ConeDegrees = Config.Items.ThrowConeDegrees,
	})

	if throwerVerdict ~= "OK" and throwerVerdict ~= "MISS" then
		return throwerVerdict :: Types.ItemThrowVerdict, nil, origin
	end

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
			THE ROLE AND THE FORM ARE ANDed HERE AND NOWHERE ELSE. `pure/ItemThrow` receives one
			boolean and never learns that a role exists — which is what lets that module live in
			`shared/pure/` and be callable by any client without leaking anything.
		]]
		local isTransformedAswang = aswangUserId == candidate.UserId
			and MonsterService.IsTransformed(candidate.UserId)

		local verdict = ItemThrow.evaluate({
			Phase = RoundService.GetPhase(),
			ThrowerState = RoundService.GetPlayerState(thrower),
			-- V08. The slot, not a count. `pure/ItemThrow` collapses "holding a bawang" into MISS
			-- with the four geometric worlds; see its header for why that fifth world may not be
			-- split out even though the thrower already knows what they are holding.
			Held = slot[thrower.UserId],
			ThrowerPos = vec(origin),
			Direction = vec(direction),
			TargetPos = vec(candidateRoot.Position),
			TargetIsTransformedAswang = isTransformedAswang,
			Range = Config.Items.SaltThrowRange,
			ConeDegrees = Config.Items.ThrowConeDegrees,
		})

		--[[
			A NON-GEOMETRIC REFUSAL IS THE SAME FOR EVERY CANDIDATE, so returning it from inside the
			loop is correct rather than sloppy: ITEM_WRONG_PHASE, ITEM_THROWER_NOT_ALIVE and
			ITEM_NO_ITEM depend only
			on the thrower, and re-deriving them per candidate is what keeps ONE call site for the whole
			rule instead of a pre-check that can drift from it.
		]]
		if verdict ~= "OK" and verdict ~= "MISS" then
			-- The cast is load-bearing and is CLAUDE.md's documented Luau bite: refining a literal
			-- union by excluding two of its members widens the remainder to plain `string`, which then
			-- fails to satisfy the declared return type. Six of the scaffold's seven original analyze
			-- errors were this exact shape.
			return verdict :: Types.ItemThrowVerdict, nil, origin
		end

		if verdict == "OK" then
			--[[
				AND SMOKE BREAKS THE THROW, THE SAME WAY IT BREAKS A KILL (V07, §4.3).

				THE OTHER HALF OF THE SYMMETRY. `MonsterService.hasLineOfSight` already refuses a kill
				through a cloud; without this line the cloud would stop the monster killing but not
				the survivors throwing, which turns the Aswang's escape tool into a gift to the people
				chasing it. `CamouflageRules.smokeBlocks` is symmetric in its two points, so there is
				no version of this that is asymmetric by accident.

				COLLAPSED INTO THE EXISTING `MISS`, AND A `MISS_SMOKE` WOULD BE A ROLE ORACLE.
				`pure/ItemThrow` reports one MISS for every failure reason precisely because a throw
				is a request a SURVIVOR makes about ANOTHER PLAYER — a split verdict lets a client
				stand in front of each player in turn and read the monster off the refusal shape. A
				smoke-specific value would be worse than most: it is produced only when the Aswang has
				planted a cloud, delivered to a survivor, naming a direction.
			]]
			if MonsterService.SmokeBlocks(origin, candidateRoot.Position) then
				continue
			end

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
			this is the one place a client's raw vector reaches arithmetic, and `pure/ItemThrow` has
			already refused the throw by this point but does not hand back a sanitised direction.
		]]
		local magnitude = direction.Magnitude
		local aim = if magnitude > 0 and magnitude < math.huge then direction.Unit else Vector3.zero

		return "MISS", nil, origin + aim * Config.Items.SaltThrowRange
	end

	local bestCharacter = (best :: Player).Character
	local bestRoot = if bestCharacter then bestCharacter:FindFirstChild("HumanoidRootPart") else nil
	local impact = if bestRoot and bestRoot:IsA("BasePart") then bestRoot.Position else origin

	return "OK", best, impact
end

--------------------------------------------------------------------------------
-- V08 — the slot, the world, and the four ways a slot empties
--------------------------------------------------------------------------------

-- The tag every item lying on the floor carries. Replicated, and carries nothing — see the AddTag
-- call in `placeItem` for the argument, which is C13's `SaltPouch` argument unchanged.
local TAG_DROPPED = "DroppedItem"

--[[
	V09, §4.6. THE DOORWAYS, AND THE LIVE BARRIERS STANDING IN THEM.

	DISCOVERED BY TAG, NOT BY NAME, exactly as `SearchService.discoverPool` finds containers. The map
	is not in git and the builder is outside `src/`, so a tag is the only contract the two can share;
	a name pattern would silently stop matching the day a house is renamed.

	`barriers` IS SERVER-ONLY AND IS NOT THE SAME KIND OF SECRET AS `slot`. A roster of who holds what
	is a roster of who can answer the Aswang; a list of which doorways have garlic on them is public
	by construction — every client can see the bulbs. It is server-owned because the BURN-OUT CLOCK
	and the breach test must have one home, not because the contents are private.

	AT MOST `Config.Items.GarlicSpawnCount` ENTRIES — two. A list rather than a map keyed by doorway,
	because two is not a lookup problem and a list is what `Types.GarlicBarriersPayload` sends.
]]
local TAG_DOORWAY = "Doorway"
local TAG_GARLIC = "PlacedGarlic"

--[[
	`Breached` AND `RestoreTo` ARE THE STICKY CORRECTION, AND STICKINESS IS GATED ON A CONFIRMED
	CROSSING RATHER THAN ON WHICH SIDE THE ASWANG IS STANDING.

	The distinction is the whole safety of it. `GarlicBarrier.crossed` fires only when the destination
	is past the plane by more than the tolerance in ONE sample interval, so at walking speed it catches
	a walk-through roughly a third of the time — and once both samples are on the far side it can never
	fire again, which made a single lucky sample a permanent bypass. Stickiness closes that: once a
	crossing IS confirmed, the server keeps restoring until the Aswang is back where it came from.

	IT IS NOT DRIVEN BY `sideOf` ALONE, AND THAT WOULD HAVE BEEN A CATASTROPHIC FALSE POSITIVE. The
	plane is infinite. An Aswang standing inside the chapel, having walked in through its EAST door, is
	on the far side of the SOUTH door's plane — so a side-driven correction would restore that player
	continuously, for a barrier they never touched, at the map's only two-door building. A confirmed
	crossing through the opening is the only thing that may start this.
]]
type ActiveBarrier = {
	Doorway: BasePart,
	Part: BasePart,
	Spec: GarlicBarrier.Barrier,
	Breached: boolean,
	HomeSign: number,
	RestoreTo: Vector3?,
	FarSideStreak: number,
}

local barriers: { ActiveBarrier } = {}

--[[
	THE COLOUR OF A DROPPED ITEM. Placeholder presentation, replaced at V15 with real models.

	IT MUST DISTINGUISH THE THREE, because from the drop handler onward all three can be lying on the
	ground at once and one of them is the round's only win condition. A tester has to be able to tell
	the buntot pagi from a pouch at ten paces without walking to it.
]]
local function colourOf(item: Types.ItemType): Color3
	if item == Enums.ItemType.Bawang then
		return rgb(Config.Items.BawangRgb)
	elseif item == Enums.ItemType.BuntotPagi then
		return rgb(Config.Items.BuntotPagiRgb)
	end

	return rgb(Config.Items.SaltRgb)
end

--[[
	PUT AN ITEM IN THE WORLD AT A POSITION. The one place an item part is created.

	ANCHORED AND NON-COLLIDING. It must not be pushed around by characters, must not fall through the
	barrio's greybox floor, and must not block a doorway — V09 owns the only thing that is allowed to
	do that, and doing it accidentally here would half-build garlic with none of its rules.

	THE POSITION IS ALWAYS SERVER-DERIVED. Every caller passes a position the SERVER read: a
	searcher's own character, a dying player's own character, a husk's own character. No path lets a
	client name where an item lands, which matters most for the buntot pagi — a client-supplied
	position drops the win condition through a wall or across the barrio.
]]
local function placeItem(item: Types.ItemType, position: Vector3)
	local folder = droppedItems

	if folder == nil then
		return
	end

	local part = Instance.new("Part")

	--[[
		THE NAME IS THE ITEM TYPE AND NOTHING ELSE.

		WHAT MUST NOT GO ON IT: the UserId of whoever dropped it — not in the Name, not in an
		attribute, not in a child value. "Who dropped this" is a fact about a player. A dropped item
		named `Dropped_12345` is a per-player fact lying on the floor of the barrio, readable by
		every client, and no check in this repo would report it.

		The ITEM TYPE is public and has to be: a player must be able to tell salt from the round's
		only win condition before walking over it, which is also why `colourOf` exists.
	]]
	part.Name = item
	part.Size = Vector3.new(1, 1, 1) -- config-ok: the item's own size, not a balance knob
	part.Anchored = true
	part.CanCollide = false
	part.Color = colourOf(item)
	part.Material = Enum.Material.SmoothPlastic
	-- config-ok: sits on the ground where it was dropped, not a knob
	part.Position = position + Vector3.new(0, 1, 0)

	--[[
		THE `DroppedItem` TAG IS REPLICATED AND THAT IS FINE, on the argument C13's `SaltPouch` tag
		won: it describes an object in the world every client can already see, it names no player,
		and the client needs it to draw a pickup affordance at all. `check:secrecy` inspects tags and
		this one passes because it carries nothing.
	]]
	CollectionService:AddTag(part, TAG_DROPPED)

	--[[
		PICKUP RESOLVES ON `Touched`, NOT ON A TICK, and the distance is re-checked on the server.

		C13 swept O(players x pouches) every quarter second for the life of the server. `Touched` is
		a hint that something is nearby; the AUTHORITY is the same comparison `pickupTick` made —
		measured from the player's own character, on the server — so C13's rule survives ("the server
		resolves what a player is standing at from that player's own character position") without the
		per-tick cost.

		`Touched` FIRES FOR ANY BasePart, including a corpse, another dropped item and the map
		itself. The narrowing below is to avoid resolving a player for every leaf that brushes it;
		`ItemCarry` re-checks the state regardless.
	]]
	part.Touched:Connect(function(hit: BasePart)
		if part.Parent == nil then
			return
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		local player = if character then Players:GetPlayerFromCharacter(character) else nil

		if player == nil then
			return
		end

		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root == nil or not root:IsA("BasePart") then
			return
		end

		--[[
			THE SERVER-SIDE RE-CHECK, AND IT NARROWS THE ATTACK RATHER THAN CLOSING IT.

			A `Touched` event is the client's physics telling the server something happened; this is
			the server measuring the distance for itself, which is C13's rule and is worth keeping.

			WHAT IT DOES NOT BUY, stated plainly because the previous comment here overstated it: the
			position it measures is the CHARACTER'S, and Roblox gives the client network ownership of
			its own character. An executor enumerates `workspace.DroppedItems` — the parts are public,
			tagged, named by item type and colour-coded, because a player has to be able to tell the
			win condition from a pouch — teleports to the buntot pagi, takes it, and teleports back.
			There is no remote on this path, so `RequestDropItem`'s token bucket does not apply and
			the pickup rate is unbounded.

			THIS IS THE STANDARD ROBLOX OWNERSHIP MODEL AND IS NOT NEW TO V08 — `RequestSearch` has
			the same exposure. What IS new is that V08 puts the round's only win condition on the
			floor in a self-labelling part. Closing it properly needs a displacement sanity check
			against the last replicated position, or a rate-limited pickup remote; neither is in this
			chunk's scope, and pretending a distance test substitutes for one is how it stays open.
		]]
		if (part.Position - root.Position).Magnitude > Config.Items.DropPickupRangeStuds then
			return
		end

		local verdict = ItemCarry.evaluate({
			Phase = RoundService.GetPhase(),
			PlayerState = RoundService.GetPlayerState(player),
			Held = slot[player.UserId],
			Incoming = item,
			Limit = Config.Items.CarryLimit,
		})

		--[[
			ON ANY REFUSAL THE ITEM STAYS ON THE FLOOR, and there is nothing to spill — it never left
			the world. That is the correct §4.4 outcome: items belong to the world, not to
			individuals, so a full-handed player walking over the buntot pagi leaves it for whoever
			comes next rather than destroying it.
		]]
		if verdict ~= "OK" then
			return
		end

		slot[player.UserId] = item
		part:Destroy()
	end)

	part.Parent = folder
end

--[[
	SPILL WHAT A PLAYER WAS HOLDING, AT THE BODY. Death, disconnect, and a search their hand was too
	full to accept. Nil-safe in both directions: a player holding nothing spills nothing, and a
	player with no character spills nothing.

	AT THE BODY IS THE POINT, AND IT IS NOT THE SAME AS A DELIBERATE DROP. §4.6: when the carrier
	dies the buntot pagi "drops where they fell… a corpse in the open with the win condition lying
	next to it". Offsetting this one forward would put the item somewhere the carrier was heading
	rather than where they died, which is the whole beat. `dropItemInFront` below is the other case.

	THE `item` ARGUMENT IS PASSED RATHER THAN READ FROM THE SLOT so that a caller which has already
	cleared the slot can still spill correctly, and so that the order of "clear then spill" versus
	"spill then clear" cannot silently drop an item on the floor of a table nobody reads.

	IT DOES NOT CLEAR THE SLOT. Every caller does that itself, deliberately: the disconnect path
	nils the whole entry, the death path nils it, and the drop handler nils it. A helper that did
	both would make "spill without clearing" — which no caller wants — impossible to notice.

	⚠️ THE SILENT RETURN ON A MISSING CHARACTER IS THE BUNTOT PAGI'S LAST PATH OUT OF THE SLOT, so it
	WARNS rather than vanishing quietly. `RoundService.onPlayerRemoving` sets `player.Character = nil`
	and reparents the body into `workspace.Husks`; this service's `PlayerRemoving` handler runs
	FIRST — and only because `init.server.luau` lists `ItemService` before `RoundService`. That
	ordering is load-bearing and was undocumented until an exploit audit found it. If it ever
	changes, every disconnect-while-carrying deletes the item, and the warn below is the only thing
	that would say so.
]]
local function spillItem(player: Player, item: Types.ItemType?)
	if item == nil then
		return
	end

	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		warn(
			`[ItemService] Could not spill an item for {player.UserId}: no character. `
				.. `If this fires on a disconnect, ItemService.Start now runs AFTER RoundService.`
		)
		return
	end

	placeItem(item, root.Position)
end

--[[
	A DELIBERATE DROP, LANDING `Config.Items.DropForwardStuds` IN FRONT OF THE DROPPER.

	THE FORWARD OFFSET IS THE MECHANIC, NOT A FLOURISH, and it shipped missing: V08 first placed a
	dropped item at the dropper's own root, one stud up, while `Config.Items.DropForwardStuds` had a
	declaration, a `Remotes.luau` comment describing it, and a `tests/config.test.luau` invariant
	pinning it against `DropPickupRangeStuds` — and no reader anywhere in `src/`. The invariant was
	green over a rule the code did not apply. Found by an exploit audit, not by a gate.

	WHY IT MATTERS: the drop radius is 6 studs and the item was landing 1 stud away, INSIDE the
	radius that takes it straight back. Either the pickup fires on the spawn overlap and the drop is
	instantly undone — so §4.6's "dropped, passed, and picked up from a body" is unimplemented for
	the buntot pagi — or it does not fire and the item is unpickupable until somebody walks out of
	the radius and back in. Both are bugs and neither shows up in a check.

	`LookVector` IS READ FROM THE SERVER'S COPY OF THE CHARACTER, like every other position in this
	file. The client sends no argument and names no direction; `RequestDropItem` has no parameters
	precisely so this cannot be aimed.
]]
local function dropItemInFront(player: Player, item: Types.ItemType?)
	if item == nil then
		return
	end

	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		-- Falls back to nothing rather than to the origin: an item at (0,0,0) is worse than a
		-- refused drop, because it is somewhere a player can reach and did not choose.
		return
	end

	placeItem(item, root.Position + root.CFrame.LookVector * Config.Items.DropForwardStuds)
end

--[[
	V09, §4.6. THE NEAREST DOORWAY TO THIS PLAYER, MEASURED FROM THE SERVER'S COPY OF THEIR CHARACTER.

	`RequestPlaceGarlic` HAS NO ARGUMENT, so this is the whole of how a doorway is chosen. It returns
	the part AND the distance rather than a boolean, because `pure/GarlicPlacement` wants the distance
	and the service wants the part, and computing it twice is how the two come to disagree.

	NIL FOR NO CHARACTER, NOT (0,0,0). A player with no root has no position, and the origin is a
	place in the barrio somebody can stand.

	IT SWEEPS `GetTagged` ON EVERY CALL, INCLUDING REFUSED ONES, AND THAT IS DELIBERATE. Nine doorways
	against a budget of three tokens is trivially cheap, and caching the pool at STARTING the way
	`SearchService` does would add a discovery path that can go stale when nothing in this chunk ever
	moves a doorway. Left uncached on purpose — do not "fix" it.
]]
local function nearestDoorway(player: Player): (BasePart?, number?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil

	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end

	local best: BasePart? = nil
	local bestDistance = math.huge

	for _, part in CollectionService:GetTagged(TAG_DOORWAY) do
		if not part:IsA("BasePart") then
			continue
		end

		local distance = (part.Position - root.Position).Magnitude

		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end

	if best == nil then
		return nil, nil
	end

	return best, bestDistance
end

-- Compared by INSTANCE, never by name. Two houses could carry the same door side and the pad names
-- are interpolated in the builder; the instance is the identity the tag actually hands us.
local function doorwayOccupied(doorway: BasePart): boolean
	for _, active in barriers do
		if active.Doorway == doorway then
			return true
		end
	end

	return false
end

--[[
	V09, §4.6. PUT BAWANG ON A DOORWAY.

	THE VISIBLE HALF IS PUBLIC AND MUST BE. §4.6's blockquote builds the loyalty test on everyone
	being able to see the garlic and see it burn out — "place it, ask everyone to walk inside" is not
	playable if only the placer knows where it is. So this part is a normal replicated part, painted
	`Items.BawangRgb` like the dropped item, and its disappearance is the public clock.

	IT CARRIES NO PLACER, in the Name, in an attribute or in a child value — `placeItem`'s rule, and
	sharper here: a garlic bulb is placed at a moment, so a `PlacedBy` attribute would be a timestamped
	record of one player's position lying on the floor of the barrio for fifteen seconds.

	NON-COLLIDING, AND THAT IS THE WHOLE DESIGN IN ONE PROPERTY. If the visible part collided it would
	block EVERYONE, which is a wall rather than a barrier and would make the loyalty test impossible to
	fail honestly. The thing that stops the Aswang exists on the Aswang's own client and nowhere else.

	THE BARRIER'S FLOOR IS THE DOORWAY PAD'S OWN `Position.Y`, read rather than assumed, so the
	barrier follows the map if a future pass ever raises a floor.
]]
--[[
	RETURNS WHETHER IT ACTUALLY PLACED. The handler spends the slot on `true` and only then, because
	this function has an early return and the spend used to sit above the call: a placement that hit
	the `droppedItems == nil` branch destroyed one of the round's two bawang with no barrier, no bulb
	and no feedback. Unreachable today (the folder exists from `Init`), but the spend-first ordering
	comment made it a trap for the next early return anybody adds here.
]]
local function placeGarlic(doorway: BasePart): boolean
	local folder = droppedItems

	if folder == nil then
		return false
	end

	-- ANNOTATED `BasePart`, NOT INFERRED `Part`. `ActiveBarrier.Part` is typed `BasePart` and a table
	-- field is invariant, so an inferred `Part` is not "exactly" a `BasePart` and the insert below
	-- fails to typecheck. Every property set here belongs to `BasePart`.
	local part: BasePart = Instance.new("Part")

	part.Name = Enums.ItemType.Bawang
	part.Size = Vector3.new(1, 1, 1) -- config-ok: the item's own size, not a balance knob
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = rgb(Config.Items.BawangRgb)
	part.Material = Enum.Material.SmoothPlastic
	-- config-ok: sits on the doorway's threshold where it was placed, not a knob
	part.Position = doorway.Position + Vector3.new(0, 1, 0)

	--[[
		A DIFFERENT TAG FROM `DroppedItem`, AND THE DIFFERENCE IS LOAD-BEARING. `placeItem` connects a
		`Touched` pickup to everything it tags `DroppedItem`; placed garlic must NOT be pickup-able,
		or a survivor walks through their own barrier's doorway and takes it straight back off the
		threshold. `PlacedGarlic` carries no player and no round state, so it passes `check:secrecy`
		on `DroppedItem`'s argument.
	]]
	CollectionService:AddTag(part, TAG_GARLIC)
	part.Parent = folder

	local now = os.clock()

	table.insert(barriers, {
		Doorway = doorway,
		Part = part,
		Spec = {
			X = doorway.Position.X,
			Y = doorway.Position.Y,
			Z = doorway.Position.Z,
			Yaw = math.rad((doorway:GetAttribute("Yaw") :: number?) or 0),
			HalfWidth = (((doorway:GetAttribute("Width") :: number?) or 0) / 2)
				+ Config.Items.GarlicBarrierPadStuds,
			Height = Config.Items.GarlicBarrierHeight,
			CreatedAt = now,
			ExpiresAt = now + Config.Items.GarlicDuration,
		},
		Breached = false,
		HomeSign = 0,
		RestoreTo = nil,
		FarSideStreak = 0,
	})

	return true
end

local garlicRemote = Remotes.Get("GarlicBarriers")

--[[
	V09, §4.6. SEND THE ASWANG THE LIST OF LIVE BARRIERS, AND SEND IT TO NOBODY ELSE.

	ONE `FireClient`, NEVER `FireAllClients`. `check-secrecy.mjs` allowlists two remotes to carry the
	secret and this is not one of them, which is correct — the PAYLOAD carries no role. What is
	role-derived is the RECIPIENT, and that is `FeedUpdate`'s and `CamouflageUpdate`'s arrangement
	exactly: the server resolves who from `RoundService.GetAswangUserId()` and the wire says nothing.

	EVERY CALLER IS A STATE CHANGE, NOT A CLOCK. Placement, burn-out, the phase sweep, and the
	Aswang's own `CharacterAdded`. There is no periodic push: the Aswang's client owns its barriers'
	countdowns from `SecondsRemaining` and re-syncs whenever the server's list actually moves. A
	periodic push would be a fixed-rate signal arriving at exactly one client for the whole round,
	which is a shape worth not building even though nobody else can observe it.

	NIL-SAFE IN BOTH DIRECTIONS. No Aswang assigned (IDLE, INTERMISSION) sends nothing; an Aswang who
	has left the server resolves to no Player and sends nothing. Neither is an error — `RoundService`
	owns the roster and this function is a renderer for it.

	IT SENDS AN EMPTY LIST RATHER THAN SKIPPING. `clearBarriers` must reach the client or the last
	round's walls stand in the next one, and "no barriers" is a state the snapshot has to be able to
	express. That is the half a delta protocol would have got wrong.
]]
local function pushBarriers()
	local aswangUserId = RoundService.GetAswangUserId()

	if aswangUserId == nil then
		return
	end

	local player = Players:GetPlayerByUserId(aswangUserId)

	if player == nil then
		return
	end

	local now = os.clock()
	local specs: { Types.GarlicBarrierSpec } = {}

	for _, active in barriers do
		table.insert(specs, {
			Position = Vector3.new(active.Spec.X, active.Spec.Y, active.Spec.Z),
			Yaw = active.Spec.Yaw,
			Width = active.Spec.HalfWidth * 2,
			Height = active.Spec.Height,
			SecondsRemaining = GarlicBarrier.secondsRemaining(active.Spec, now),
		})
	end

	local payload: Types.GarlicBarriersPayload = { Barriers = specs }

	garlicRemote:FireClient(player, payload)
end

--[[
	V09, §4.6. THE ONE THING IN THIS CHUNK THAT IS ALLOWED TO BE SEEN, AND ONLY BY CHEATING.

	READ THE BLOCKQUOTE BEFORE CHANGING THIS FUNCTION. §4.6: "The moment the barrier plays any effect
	on the monster, bluffing dies and the test becomes a perfect oracle." A server correction that
	snaps a character back IS an effect, and a third player watching a doorway would read it exactly
	as the oracle the spec forbids.

	THE ASYMMETRY THAT MAKES IT SAFE ANYWAY: that sentence binds the HONEST case. An honest client is
	stopped by its own barrier and never crosses the plane, so this function never runs for it. The
	only way to be corrected here is to have ignored a barrier, which no honest client does.

	SO EVERY LINE IS WRITTEN TO FAIL TOWARD DOING NOTHING:

	  · `crossed` needs a STRICT sign change, so a character standing in the threshold is not a breach.
	  · It needs the destination more than `GarlicBreachToleranceStuds` PAST the plane, so lag,
	    a corpse's physics or a shove is not a breach.
	  · It needs the crossing point inside the doorway's width and under the barrier's height.
	  · The restore uses `from` — a position the server SAW on its previous sample — never a computed
	    one. It cannot put the Aswang somewhere it has never been, which is the failure mode that
	    would turn a false positive from an annoyance into a report.

	IT WRITES `CFrame` AND NOTHING ELSE. No WalkSpeed, no anchor, no network-ownership change, no
	Humanoid state. C14's WalkSpeed brand and C04's revert bug are what a "while we are here" property
	write becomes six weeks later, and both shipped with `check:secrecy` green.

	`SetNetworkOwner(nil)` WAS CONSIDERED AND REJECTED. Server-simulating the Aswang's character would
	make the block authoritative — and it would make ONE character in the round move differently for
	the whole round, felt by its owner as input lag and plausibly readable by others in its motion.
	That trades a fifteen-second observable for a five-minute one.
]]
--[[
	V09, §4.6. THE ONE THING IN THIS CHUNK THAT IS ALLOWED TO BE SEEN, AND ONLY BY CHEATING.

	READ THE BLOCKQUOTE BEFORE CHANGING THIS FUNCTION. §4.6: "The moment the barrier plays any effect
	on the monster, bluffing dies and the test becomes a perfect oracle." A server correction that
	snaps a character back IS an effect, and a third player watching a doorway would read it exactly
	as the oracle the spec forbids. It is permitted here because an honest client stops itself and
	never crosses, so this never runs for one.

	THREE SEPARATE THINGS HAPPEN HERE AND THEY ARE DELIBERATELY NOT THE SAME THING:

	  1. OBSERVING a crossing. Runs ALWAYS, including inside the grace window.
	  2. ACCUMULATING far-side samples, which is what makes the detection speed-independent.
	  3. CORRECTING, which is the only step the grace window defers.

	SPLITTING 1 FROM 3 IS A BUG FIX. The grace used to `continue` past a non-authoritative barrier
	entirely, so a crossing made in the first second was never SEEN — and once the Aswang is on the far
	side no later sample can produce the sign change `crossed` needs. One second of blindness bought
	the whole remaining fourteen, and the window opens at a moment every client can see (a bulb appears
	on a doorway), which is exactly when the loyalty test is happening.

	ARMING TAKES NO DISTANCE TOLERANCE, AND THAT FIX IS THE IMPORTANT ONE. It used to require the
	destination be `GarlicBreachToleranceStuds` past the plane within ONE `GarlicBreachSampleInterval`,
	which is a threshold of `2.5 / 0.25` = **10 studs per second** — below that, `crossed` could never
	fire at all, so setting `WalkSpeed = 9` defeated garlic permanently at no risk. The tolerance now
	gates the STREAK instead of the arm, so a slow crosser still accumulates far-side samples and is
	still caught; it just takes another quarter second.

	TWO CONSECUTIVE FAR-SIDE SAMPLES BEFORE CORRECTING is what replaced the tolerance's old job of
	protecting a threshold-stander. Somebody jittering across the plane under lag does not produce two
	in a row; somebody who walked through does.

	IT RETURNS THE POSITION IT RESTORED TO, so the sampler can use it as the next baseline. Writing the
	pre-correction sample there instead would hand the next call a segment nothing traversed.
]]
local function checkBreach(root: BasePart, from: Vector3, to: Vector3): Vector3?
	local a = vec(from)
	local b = vec(to)
	local now = os.clock()
	local grace = Config.Items.GarlicBreachGraceSeconds
	local tolerance = Config.Items.GarlicBreachToleranceStuds

	for _, active in barriers do
		if not GarlicBarrier.isLive(active.Spec, now) then
			continue
		end

		-- 1. OBSERVE. No tolerance, and not gated on the grace — see the header for both.
		if not active.Breached and GarlicBarrier.crossed(active.Spec, a, b, 0) then
			active.Breached = true
			active.HomeSign = if GarlicBarrier.sideOf(active.Spec, a) < 0 then -1 else 1
			active.RestoreTo = from
			active.FarSideStreak = 0
		end

		if not active.Breached then
			continue
		end

		--[[
			2. ACCUMULATE. Back on the home side is the breach walked back — disarm, and the barrier
			returns to ordinary crossing detection rather than staying armed for the rest of the round.
			A sample within the tolerance of the plane counts as neither: that is the threshold-stander,
			and it must neither disarm nor advance.
		]]
		local side = GarlicBarrier.sideOf(active.Spec, b)

		if (side < 0 and active.HomeSign < 0) or (side > 0 and active.HomeSign > 0) then
			active.Breached = false
			active.RestoreTo = nil
			active.FarSideStreak = 0
			continue
		end

		if math.abs(side) <= tolerance then
			continue
		end

		active.FarSideStreak += 1

		-- 3. CORRECT. The ONLY step the grace defers: an honest client never reaches it, and a cheater
		-- who crossed inside the window is still on the far side when the grace ends.
		if active.FarSideStreak < 2 then
			continue
		end

		if not GarlicBarrier.isAuthoritative(active.Spec, now, grace) then
			continue
		end

		local restoreTo = active.RestoreTo

		if restoreTo ~= nil then
			--[[
				BACK TO WHERE IT WAS, ORIENTED AS IT IS. Position only: taking the character's current
				`CFrame.Rotation` keeps the camera and the facing untouched, so the correction is a
				position restore rather than a re-aim. A re-aim would be a second observable on top of
				the first, and this function is already spending the only one it is allowed.

				IT WRITES `CFrame` AND NOTHING ELSE. No WalkSpeed, no anchor, no network-ownership
				change, no Humanoid state. C14's WalkSpeed brand and C04's revert bug are what a "while
				we are here" property write becomes six weeks later, and both shipped green.
			]]
			root.CFrame = CFrame.new(restoreTo) * root.CFrame.Rotation

			if Config.Debug.VerboseLogging then
				-- No UserId. There is exactly one player this can ever be, so printing the id would
				-- write the round's secret into the server log for anything that reads it later.
				print("[ItemService] Garlic breach corrected")
			end

			return restoreTo
		end
	end

	return nil
end

--[[
	V09, §4.6. THE BREACH SAMPLER, AND ITS ONLY JOB IS TO NOT FIRE ON HONEST PLAYERS.

	IT IS A BOUNDED LOOP, NOT A TICK, AND `ItemService`'S OWN RULE IS WHY. This file deleted C13's
	quarter-second sweep and its closing comment says nothing should bring one back. This runs only
	while at least one barrier is live — started by the first placement, stopped when the list empties
	— so its worst case is `Config.Items.GarlicDuration` seconds of sampling ONE player's root
	position against at most two planes. That is a bound on the exception rather than an exception to
	the rule, and if it ever becomes unbounded the rule has been broken.

	IT SAMPLES ONE PLAYER. Survivors are not blocked by garlic and are never tested against it; there
	is no per-player state here and no roster.

	`lastSample` IS A POSITION THE SERVER SAW, WHICH IS WHY THE CORRECTION CANNOT TELEPORT ANYONE
	SOMEWHERE THEY HAVE NEVER BEEN. `checkBreach` restores it verbatim.
]]
local breachRunning = false
local lastSample: Vector3? = nil

local function sampleBreaches()
	--[[
		`lastSample` IS DROPPED ON EVERY CALL, INCLUDING WHEN A LOOP IS ALREADY RUNNING, and the
		"including" is a bug fix. This used to sit below the `breachRunning` early return, so the SECOND
		bawang of a round inherited a sample taken before its barrier existed — and a stale baseline
		straddling a brand-new plane is a crossing the Aswang never made. `GarlicBreachGraceSeconds`
		covers the same window from the other side; this covers it even if the grace is ever shortened.

		The cost of dropping a baseline is one sample interval of not watching. The cost of keeping a
		stale one is correcting an honest player.
	]]
	lastSample = nil

	if breachRunning then
		return
	end

	breachRunning = true

	task.spawn(function()
		while #barriers > 0 do
			local aswangUserId = RoundService.GetAswangUserId()
			local player = if aswangUserId ~= nil
				then Players:GetPlayerByUserId(aswangUserId)
				else nil
			local character = if player ~= nil then player.Character else nil
			local root = if character ~= nil
				then character:FindFirstChild("HumanoidRootPart")
				else nil

			if root ~= nil and root:IsA("BasePart") then
				local from = lastSample
				local to = root.Position

				--[[
					THE BASELINE IS WHERE THE CHARACTER ACTUALLY ENDED UP. On a correction that is the
					RESTORED position, not the sampled one — writing the sample would hand the next
					call a segment the character never traversed, and `crossed` would evaluate a
					fabricated four-stud jump against every other live barrier.
				]]
				if from ~= nil then
					to = checkBreach(root, from, to) or to
				end

				lastSample = to
			else
				--[[
					NO CHARACTER MEANS NO BASELINE. Dropping the sample rather than keeping a stale one
					is what stops a respawn on the far side of a doorway reading as a crossing — the
					single most likely way this loop would brand an honest player.
				]]
				lastSample = nil
			end

			task.wait(Config.Items.GarlicBreachSampleInterval)
		end

		breachRunning = false
		lastSample = nil
	end)
end

--[[
	BURN-OUT. §4.6: fifteen seconds, then it is gone.

	`task.delay` RATHER THAN A TICK, AND THE FILE'S OWN RULE IS WHY. `ItemService` deleted C13's
	quarter-second sweep and its closing comment says nothing should bring one back. A burn-out is an
	event at a known time, so it is scheduled rather than polled — and the sweep re-checks `isLive`
	rather than trusting the timer, so a barrier cleared early by a phase change cannot be cleared
	twice.
]]
local function expireGarlic()
	local now = os.clock()
	local kept: { ActiveBarrier } = {}

	for _, active in barriers do
		if GarlicBarrier.isLive(active.Spec, now) then
			table.insert(kept, active)
		else
			active.Part:Destroy()
		end
	end

	barriers = kept
	pushBarriers()
end

--[[
	EVERY BARRIER GONE AT ONCE, for a phase change rather than for a clock. Separate from
	`expireGarlic` because they answer different questions — "which of these has run out" versus
	"none of these applies any more" — and a single function taking a flag would be one function with
	two meanings, which is the argument `ItemDrop` makes for not being folded into `ItemCarry`.

	IT DESTROYS THE PARTS TOO, even though `clearDroppedItems` will sweep the folder at INTERMISSION.
	`ENDING` reaches here and does not reach that sweep, and a garlic bulb still sitting on a doorway
	with no barrier behind it is the one thing in this chunk that would be a visible lie.
]]
local function clearBarriers()
	for _, active in barriers do
		active.Part:Destroy()
	end

	table.clear(barriers)
	pushBarriers()
end

-- Everything this service put in the world. Called on the way into INTERMISSION and IDLE, mirroring
-- MonsterService.clearCorpses — NOT on "any phase that is not ACTIVE", which is the mistake that
-- destroyed the winning kill's corpse within a frame of creating it.
local function clearDroppedItems()
	local folder = droppedItems

	if folder == nil then
		return
	end

	for _, item in folder:GetChildren() do
		item:Destroy()
	end
end

--[[
	V08. A CONTAINER YIELDED AN ITEM (§4.4, §4.6). THE ONLY WAY AN ITEM ENTERS A SLOT FROM THE WORLD
	that is not a deliberate pick-up-off-the-floor.

	`SearchService.ItemFound` fires from the ONE path that yields an item, AFTER the container is
	marked opened. So by the time this runs, the item has already left the world and the container is
	already spent.

	WHICH IS WHY A REFUSAL HERE HAS TO PUT THE ITEM BACK, AND THAT IS THE HARD PART OF THIS FUNCTION.
	§4.4's anti-frustration rule says items belong to the world, not to individuals; a player whose
	hand is full completes a six-second search, makes noise, and would otherwise DESTROY the item.
	With seven items in the round and one of them the win condition, a full-handed search on the
	buntot pagi's container would delete the second win condition silently — no error, no warning,
	and no way to tell afterwards that it had happened.

	A BindableEvent's arguments are `...any`, so this NARROWS rather than casts — V03's own
	instruction where `ItemFound` is declared. The narrowing is defensive rather than necessary
	today (`Enums.ItemType` is frozen and `SearchService` seeds from it), and it stays that way.
]]
local function onItemFound(player: unknown, itemId: unknown)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	--[[
		NARROWED BY ASSIGNMENT FROM `Enums`, NOT BY A CAST ON THE INCOMING VALUE, and the difference
		is load-bearing rather than stylistic.

		`local item = itemId :: Types.ItemType` COMPILES AND IS WRONG. `itemId` is `unknown`; after
		three `~=` tests Luau refines it to `string | string | string`, the cast widens rather than
		narrows, and the `ItemCarry.Request` below then fails to typecheck on `Incoming`. This is
		`.claude/lessons/pure-module-unions-widen-in-lists.md` arriving through a second door — a
		literal union does not survive being reconstructed from a value that lost it.

		Assigning the frozen `Enums` constant instead gives back the `:: Types.ItemType` cast that
		`Enums.luau` already carries on each member, which is the one place that cast belongs. It is
		also V03's own instruction where `ItemFound` is declared: narrow with a function, not a cast.
	]]
	local item: Types.ItemType

	if itemId == Enums.ItemType.Salt then
		item = Enums.ItemType.Salt
	elseif itemId == Enums.ItemType.Bawang then
		item = Enums.ItemType.Bawang
	elseif itemId == Enums.ItemType.BuntotPagi then
		item = Enums.ItemType.BuntotPagi
	else
		warn(`[ItemService] SearchService.ItemFound fired with an unknown item: {tostring(itemId)}`)
		return
	end

	local verdict = ItemCarry.evaluate({
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Held = slot[player.UserId],
		Incoming = item,
		Limit = Config.Items.CarryLimit,
	})

	if verdict ~= "OK" then
		--[[
			THE ITEM GOES TO THE FLOOR, NOT TO NOTHING. See the header. It lands at the searcher's own
			position, which is where the container was — which is where a player who could not carry
			it would expect to find it when they come back with an empty hand.
		]]
		spillItem(player, item)

		if Config.Debug.VerboseLogging then
			-- A UserId and a verdict. Never the item, and never a role: an item id in the log beside
			-- a UserId is the roster the slot table's comment refuses to build, written to disk.
			print(`[ItemService] Pickup refused for {player.UserId}: {verdict}`)
		end

		return
	end

	slot[player.UserId] = item

	-- C23. The first pouch a player ever takes explains what it is for; §10 is explicit that the
	-- folklore must not be assumed. Fired to the player who did it, about a thing they did
	-- themselves — no audience question here. SALT ONLY: the cue's copy is about salt, and V09/V10
	-- own whether their items deserve one.
	if item == Enums.ItemType.Salt then
		TeachingService.Cue(player, "CUE_FIRST_SALT")
	end
end

local function onPhaseChanged(phase: Types.RoundPhase)
	--[[
		INTERMISSION AND IDLE ONLY, mirroring what `clearPouches` did and what
		`MonsterService.clearCorpses` does — NOT "any phase that is not ACTIVE", which is the mistake
		that destroyed the winning kill's corpse within a frame of creating it.

		Items lying on the ground during ENDING are scenery, and a slot during ENDING is a fact about
		a round that has finished. Neither is a mark on a player, which is the distinction the split
		below draws for effects.
	]]
	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearDroppedItems()
		table.clear(slot)
	end

	--[[
		EVERY phase that is not ACTIVE, unlike the sweep above which fires only on INTERMISSION/IDLE.
		The difference mirrors MonsterService.onPhaseChanged's split and it is deliberate: items lying
		on the ground during ENDING are scenery, a glow during ENDING is a mark on a player.
	]]
	if phase ~= Enums.RoundPhase.Active then
		clearAllEffects()
		--[[
			V09. BARRIERS DIE THE MOMENT THE ROUND STOPS BEING ACTIVE, on the same side of this split
			as the glow rather than the same side as the dropped items — and the file's own
			distinction is the reason. Items lying on the ground during ENDING are scenery; a live
			barrier is a rule still being applied to one player after the round it belonged to has
			finished. The garlic PARTS are scenery and are swept above with everything else at
			INTERMISSION, but `clearBarriers` destroys them too because ENDING never reaches that
			sweep and a bulb with no barrier behind it would be a visible lie.
		]]
		clearBarriers()
	end
end

function ItemService.Init()
	table.clear(slot)
end

--[[
	V08, §4.6/§6.4. THE FOUR WAYS A SLOT EMPTIES WITHOUT THE ITEM BEING USED, AND THREE OF THEM PUT
	IT ON THE FLOOR.

	  1. DEATH — it drops where they fell. §4.6 requires this by name and builds a whole beat on it.
	  2. DISCONNECT — it drops where the husk stands. See `PlayerRemoving` below; it is a decision.
	  3. THE ROUND LEAVING ACTIVE — the slot clears and the world is swept. Nothing to preserve.
	  4. A DELIBERATE DROP — Step 4.3's handler.

	ONLY (3) DESTROYS THE ITEM, and only because the round it belonged to is over.
]]

--[[
	DROP ON DEATH, AT THE POSITION THE PLAYER DIED AT.

	§4.6 requires this by name: the buntot pagi "can be dropped, passed, and picked up from a body",
	and when the carrier dies it drops where they fell — "a corpse in the open with the win condition
	lying next to it and a monster that knows you have to come back for it". A slot that were simply
	cleared on death would delete the second win condition the first time the carrier is caught, and
	nothing in the game would report it.

	READ THE POSITION BEFORE ANYTHING MOVES OR DESTROYS THE CHARACTER. `spillItem` reads the
	HumanoidRootPart, and a `Died` handler that runs after a ragdoll settles drops the win condition
	somewhere nobody watched them die. Connecting on `Died` rather than on the corpse's creation is
	what keeps the read early.

	AND IT MUST NOT BE A ROLE TELL. Every player who dies drops what they were holding, and a player
	holding nothing drops nothing — which is the same observable for a survivor and for the Aswang.
	There is no branch on role here and there must never be one.
]]
local function watchCharacter(player: Player, character: Model)
	--[[
		V09. A RESPAWN OR A REJOIN REBUILDS THE ASWANG'S BARRIERS FROM THE SERVER'S LIST.

		The barrier parts live in the Aswang's own client's workspace and are destroyed with its
		character's session; without this line an Aswang who respawns mid-round walks through garlic
		with nothing anywhere reporting a fault, and the symptom is "bawang stopped working" in one
		round out of ten.

		CALLED UNCONDITIONALLY, AND THAT IS THE POINT. `pushBarriers` resolves the recipient by role
		itself, so this does nothing for the four players it does not concern. A
		`if player.UserId == RoundService.GetAswangUserId()` guard HERE would be a role-shaped branch
		in the character-spawn path of a service every player reaches — the exact shape `ItemCarry`'s
		header refuses for the slot table. The role test belongs in one function.
	]]
	pushBarriers()

	-- A character that has not produced a Humanoid in ten seconds is not going to; the nil branch
	-- below is the whole handling.
	local humanoid = character:WaitForChild("Humanoid", 10) -- config-ok: a load timeout, not a knob

	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.Died:Connect(function()
		spillItem(player, slot[player.UserId])
		slot[player.UserId] = nil
	end)
end

function ItemService.Start()
	local folder = Instance.new("Folder")

	folder.Name = "DroppedItems"
	folder.Parent = workspace
	droppedItems = folder

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		V08. The snapshot's producer for `YourCarriedItem`. REGISTERED RATHER THAN REQUIRED, because
		this service requires RoundService and the reverse would be a cycle; the reasoning is written
		at `RoundService.SetCarriedItemProvider`.

		THE CLOSURE READS ONE KEY AND RETURNS ONE VALUE. It takes the Player `buildSnapshot` is
		already building for, so there is no path by which it can be asked about somebody else, and
		it reads no role — a branch on the Aswang here is what would turn an empty slot into a tell.
	]]
	RoundService.SetCarriedItemProvider(function(player: Player): Types.ItemType?
		return slot[player.UserId]
	end)

	--[[
		THE SEAM V03 LEFT UNCONNECTED. `SearchService.ItemFound` is a BindableEvent created at MODULE
		scope, not inside `Start`, which is why connecting here is safe even though
		`init.server.luau` starts `ItemService` BEFORE `SearchService`. V03 built it that way
		deliberately; do not move it, and do not reorder the bootstrap to "fix" a problem that the
		module-scope construction already solved.
	]]
	SearchService.ItemFound.Event:Connect(onItemFound)

	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			watchCharacter(player, player.Character)
		end

		player.CharacterAdded:Connect(function(character: Model)
			watchCharacter(player, character)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			watchCharacter(player, character)
		end)
	end)

	--[[
		V08 ANSWERS C13's OPEN QUESTION: THE ITEM DOES NOT TRAVEL WITH THE HUSK.

		C13 left this as a "conservative choice, revisit when Phase 5 lands". §4.6 settles it. Three
		reasons, and the first is the one that decides it:

		  · §4.6's death rule already says the buntot pagi lands where its carrier fell. A disconnect
		    that made it VANISH would be strictly worse than dying with it — which hands players an
		    incentive to alt-F4 while holding the win condition.
		  · The husk is a body standing in the barrio that other players can see and that
		    `RoundService.MarkHuskKilled` can kill. An item on the floor beside it is consistent with
		    everything else about the husk.
		  · A carry preserved across a reconnect is a DUPLICATION surface: the slot table survives,
		    the husk survives, and the reconnect path would have to prove it does not hand back an
		    item that was also dropped. Dropping unconditionally makes that unprovable state
		    unreachable. There is exactly one buntot pagi and it IS the second win condition.
	]]
	Players.PlayerRemoving:Connect(function(player: Player)
		spillItem(player, slot[player.UserId])
		slot[player.UserId] = nil

		-- `stunned` is dropped directly because there is no humanoid left to restore. The reveal's
		-- half of this is `MonsterService.onPlayerRemoving`, which since V05 calls `clearExposed`
		-- BEFORE nilling the entry — nilling alone orphans the Highlight onto the husk.
		stunned[player.UserId] = nil
	end)

	--[[
		V09, §4.6. PUT BAWANG ON A DOORWAY.

		THE RATE LIMIT IS INLINE AND FIRST, copying the throw and drop handlers exactly.
		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire —
		so a handler that IS limited but does it elsewhere reads as unguarded and fails the build.
		Consume FIRST, before anything is read.

		THERE IS NO ARGUMENT TO VALIDATE. See the declaration in `Remotes.luau`: the doorway is
		resolved from the player's own character position and the item from the server's own slot.

		PLACING MAKES NOISE, AND THAT IS A DECISION RATHER THAN AN INHERITANCE. §4.4's four noisy
		actions include ITEM_USE and the salt throw already emits it — on a MISS as well as a hit,
		precisely so a throw sounds the same either way. Garlic is the second item use in the game and
		a silent one would be the only item use that makes no sound, which is
		`.claude/lessons/absence-is-observable.md` in miniature: a survivor who hears nothing when
		somebody uses an item learns something about which item it was. Both roles place bawang, both
		emit the same cue, from the placer's own position.
	]]
	Remotes.Get("RequestPlaceGarlic").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestPlaceGarlic") then
			return
		end

		local doorway, distance = nearestDoorway(player)

		local verdict = GarlicPlacement.evaluate({
			Phase = RoundService.GetPhase(),
			PlayerState = RoundService.GetPlayerState(player),
			Held = slot[player.UserId],
			DoorwayDistance = distance,
			Range = Config.Items.GarlicPlaceRangeStuds,
			DoorwayOccupied = doorway ~= nil and doorwayOccupied(doorway),
		})

		--[[
			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK — the throw handler's rule and
			the drop handler's, inherited. `GARLIC_DOORWAY_TAKEN` echoed back would be a free map
			probe; see the union's comment in `Types.luau`.
		]]
		if verdict ~= "GARLIC_OK" or doorway == nil then
			if Config.Debug.VerboseLogging then
				-- A UserId and a verdict. NEVER the doorway, and never the item: a doorway id beside
				-- a UserId in the log is a record of where a player was standing, written to disk.
				print(`[ItemService] Garlic placement refused for {player.UserId}: {verdict}`)
			end

			return
		end

		--[[
			§4.6: "Once used, it's gone." THE SLOT IS SPENT ABOVE THE PLACEMENT so no future early
			return can skip it, which is the throw handler's ordering and the reason it has it.
		]]
		--[[
			§4.6: "Once used, it's gone." SPENT ONLY IF IT WAS ACTUALLY PLACED. The spend used to sit
			ABOVE the call, on the reasoning that no future early return could then skip it — but
			`placeGarlic` already had one, so a placement that hit it destroyed one of the round's two
			bawang with no barrier, no bulb and no feedback. The ordering that was supposed to make the
			spend un-skippable is what made it unconditional.
		]]
		if not placeGarlic(doorway) then
			return
		end

		slot[player.UserId] = nil
		pushBarriers()
		-- Returns instantly when a loop is already running, so two barriers never start two loops.
		sampleBreaches()

		local placerRoot = if player.Character
			then player.Character:FindFirstChild("HumanoidRootPart")
			else nil

		if placerRoot ~= nil and placerRoot:IsA("BasePart") then
			NoiseService.Emit(player, "ITEM_USE", placerRoot.Position)
		end

		task.delay(Config.Items.GarlicDuration, expireGarlic)
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
			the way everyone else does — from SaltEffect and from the world. See Types.ItemThrowVerdict: a
			verdict echoed back is a role oracle for the price of one pouch.
		]]
			if verdict ~= "OK" and verdict ~= "MISS" then
				if Config.Debug.VerboseLogging then
					-- A UserId and a verdict. Never the target, and never a role.
					print(`[ItemService] Throw refused for {player.UserId}: {verdict}`)
				end

				return
			end

			--[[
				THE WRONG ITEM IS NOT A THROW, AND THIS GUARD IS THE BUG STEP 4.2 EXISTS TO NOT SHIP.

				`pure/ItemThrow` returns MISS for a player holding a BAWANG or the BUNTOT_PAGI — the
				fifth world, collapsed into MISS deliberately so a refusal shape cannot be
				differenced into a role oracle. MISS reaches the spend line below. So without this
				guard, pressing the throw key while holding the round's ONLY buntot pagi destroys the
				second win condition, and the symptom is indistinguishable from an honest miss.

				IT ASKS `pure/ItemUse` RATHER THAN COMPARING TO "SALT" INLINE, so the V09/V10 boundary
				that `tests/item-use.test.luau` pins is the boundary this service enforces. When V09
				gives bawang a verb, this line stops being the place that decides bawang does nothing.

				ITS POSITION IS LOAD-BEARING IN BOTH DIRECTIONS. It sits BELOW the refusal branch, so
				a wrong-item press still burns an AntiCheat token and still returns silently; and
				ABOVE the noise emit, so a press with a bawang in hand makes no sound. That second
				half matters — `NoiseService.Emit` fires on a miss precisely so a throw sounds the
				same whether or not it hit, and a noise that fired for a non-throw would be a free
				"I am holding something that is not salt" broadcast to everyone in radius.
			]]
			if ItemUse.verbFor(slot[player.UserId]) ~= "USE_THROW" then
				return
			end

			--[[
				§4.6: "Once used, it's gone." THE SALT IS SPENT ON A MISS TOO, and this line sits
				above the hit branch so that no future early-return can skip it. A miss that cost
				nothing would make salt a probe you throw at everyone, which is the thing
				`pure/ItemThrow`'s header refuses.

				CLEARED RATHER THAN DECREMENTED: reaching here means the slot held SALT and the slot
				holds one thing.
			]]
			slot[player.UserId] = nil

			--[[
				V04, §4.4. A THROW IS LOUD, AND IT IS EQUALLY LOUD ON A MISS.

				THE SAME ARGUMENT AS THE LINE ABOVE, AND THE SAME ONE pure/ItemThrow MAKES ABOUT ITS
				SINGLE MISS VERDICT. A noise that only fired on OK would be an identity probe with a
				sound instead of a return value: throw a pouch at somebody, listen, learn what the
				verdict refuses to tell you. Both verdicts reach this line, so both sound alike.

				From the THROWER's position, which the server has because it resolved the throw from
				it (broadcastEffect derives its origin the same way). The impact point is where the
				salt landed, not where the noise was made.
			]]
			local throwerRoot = if player.Character
				then player.Character:FindFirstChild("HumanoidRootPart")
				else nil

			if throwerRoot ~= nil and throwerRoot:IsA("BasePart") then
				NoiseService.Emit(player, "ITEM_USE", throwerRoot.Position)
			end

			if verdict == "OK" and target ~= nil then
				applyHit(target)
			end

			broadcastEffect(player, impact, verdict == "OK")
		end)

	--[[
		THE RATE LIMIT IS INLINE AND FIRST, copying the throw handler above it and MonsterService's
		two exactly. `check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|
		Permit)` within 1200 characters of an `.OnServerEvent:Connect(`, by its own admission a
		proximity tripwire — so a handler that IS limited but does it elsewhere reads as unguarded
		and fails the build. Consume FIRST, before anything is read.

		THERE IS NO ARGUMENT TO VALIDATE, which is the point of the declaration in `Remotes.luau`.
		The throw handler needs a `typeof(direction) ~= "Vector3"` guard because a client sends a
		vector; this one reads a server table and a server position and nothing else.

		DROPPING MAKES NO NOISE, AND THAT IS A REFUSAL RATHER THAN AN OMISSION. §4.4 names the noisy
		actions and dropping is not one of them. More sharply: a drop cue would let anyone within
		noise radius hear the buntot pagi's carrier decide to put it down — which converts §4.5's
		"I have the buntot pagi" phrase, a CHOICE with a cost, into an automatic broadcast.
	]]
	Remotes.Get("RequestDropItem").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestDropItem") then
			return
		end

		local verdict = ItemDrop.evaluate({
			Phase = RoundService.GetPhase(),
			PlayerState = RoundService.GetPlayerState(player),
			Held = slot[player.UserId],
		})

		--[[
			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK — the throw handler's rule,
			inherited. The client learns its hand is empty from its own next snapshot, which is a
			per-player `FireClient` it was going to receive anyway.
		]]
		if verdict ~= "OK" then
			if Config.Debug.VerboseLogging then
				-- A UserId and a verdict. NEVER the item: an item id beside a UserId in the log is
				-- the roster `slot`'s comment refuses to build, written to disk.
				print(`[ItemService] Drop refused for {player.UserId}: {verdict}`)
			end

			return
		end

		-- FORWARD, not at the feet — see `dropItemInFront`. A drop that landed inside the pickup
		-- radius would be taken straight back, which is the bug this call site shipped with.
		dropItemInFront(player, slot[player.UserId])
		slot[player.UserId] = nil
	end)

	--[[
		THERE IS NO TICK ANY MORE, AND NOTHING SHOULD BRING ONE BACK.

		C13 ran a `task.wait(0.25)` pickup loop on the server for the life of the server, sweeping
		O(players x pouches) every quarter second. V08 deleted it with the pouches: this service is
		now entirely event-driven — `SearchService.ItemFound`, the two `OnServerEvent` handlers,
		`RoundService.PhaseChanged`, `Humanoid.Died` and `Players.PlayerRemoving`.

		The one thing that plausibly wants a tick is picking a dropped item back up off the floor,
		and Step 4.3 resolves that on a `Touched` connection on the dropped part itself, with a
		server-side distance re-check, rather than by re-introducing the sweep.
	]]
end

return ItemService
