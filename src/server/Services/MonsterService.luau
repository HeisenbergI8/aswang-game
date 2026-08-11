--!strict
--[[
	MonsterService — the transform (C04, §4.3 steps 1–3 and 5).

	THE TRANSFORM IS PUBLIC BY DESIGN. It is the one thing in this game that legitimately reveals the
	Aswang, it is the signature clippable moment, and it gives survivors real information with no UI at
	all — which is what makes grouping up genuinely protective. Broadcasting it is correct, not a
	compromise.

	Read that alongside RoleService's header and the asymmetry is the design: the identity never leaves
	the server, and the ACT of transforming is shouted to everybody. A player who witnesses it learns
	who the Aswang is by seeing, which is exactly the game.

	NO CUSTOM MESH (§4.3, and §3's OUT list). The avatar is reused with a scale change, a colour and
	material shift, glowing eyes and a particle emitter.

	WHAT THIS SERVICE DOES NOT SEND
	-------------------------------
	`MonsterTransformed` carries a Character and a boolean. It does NOT carry a role: "this character
	transformed" is a fact about the world; "this player is the Aswang" is an inference the client is
	welcome to make and the server never states. The distinction becomes load-bearing at C14, where
	salt forces a revert on someone who is still the Aswang.

	The refusal verdict is likewise never echoed back. It exists so the server can log WHY, and handing
	a client `NOT_ASWANG` would be a free role oracle for anyone willing to spam the remote.

	`PlayerKilled` (C05) carries a victim and a position, and NOTHING ELSE — no killer, no name, no
	direction, no distance, no "you were seen". Three things about that are worth knowing before anyone
	adds a field:

	  · A killer field here IS now caught — `check-secrecy.mjs` was repaired after an audit found this
	    exact hole. Two things were wrong: its broadcast rule read the ARGUMENT TEXT, so a typed local
	    (`FireAllClients(payload)`) reduced the scan to seven characters and the payload's contents were
	    never seen; and its SECRET regex enumerated `aswanguserid` by hand and matched no `Killer*`
	    token at all. It now resolves the payload back to its declaration and matches `killer\w*`.
	    Proven by injecting `KillerUserId = killer.UserId` into the payload below and watching the check
	    go red. Do not take that as licence — the check is a text tripwire and a determined leak can
	    still walk around it; it is a backstop under the rule, not the rule.
	  · The position is safe on its own terms, not by permission: an anchored corpse is standing at that
	    position and replicates to every client one frame later. The payload states nothing new.
	  · What IS inferable, and cannot be fixed here, is proximity — a client reading replicated character
	    positions at the instant of the broadcast can see who was within eight studs. That is inherent
	    to a proximity kill in a replicated world; the counter is design, not code (§4.3: the killer is
	    standing there in monster form, having just been announced). Recorded in Follow Ups rather than
	    papered over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AntiCheatService = require(script.Parent.AntiCheatService)
local RoleService = require(script.Parent.RoleService)
local RoundService = require(script.Parent.RoundService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local KillValidation = require(Shared.pure.KillValidation)
local Remotes = require(Shared.Remotes)
local TransformRules = require(Shared.pure.TransformRules)
local Types = require(Shared.Types)

local MonsterService = {}

-- One part's appearance as it was BEFORE the transform touched it. See restoreLook().
type PartLook = {
	Part: BasePart,
	Color: Color3,
	Material: Enum.Material,
}

type MonsterState = {
	-- A transform has been requested and not yet reverted. Set BEFORE the windup, so it also closes
	-- the same-instant spam race — the second request sees ALREADY_TRANSFORMED.
	Transformed: boolean,
	-- The look is physically on a character and needs undoing. Distinct from Transformed because a
	-- revert during the windup must not run a cleanup for changes that were never applied.
	Applied: boolean,
	-- MonsterTransformed(true) was broadcast. A revert broadcasts false ONLY if this is set; otherwise
	-- clients receive a revert for a transform they never saw, which at C14 is a free identity leak.
	Announced: boolean,
	-- The character the look was applied TO. Resolving player.Character at revert time can land on a
	-- freshly respawned character that never transformed, and whiten it.
	AppliedTo: Model?,
	OriginalParts: { PartLook },
	OriginalScales: { [string]: number },
	Effects: { Instance }, -- exactly what this service created, so the revert removes nothing else
	LastRevertedAt: number?, -- nil until the first revert of the round; drives the cooldown
	BaseWalkSpeed: number?,
	Generation: number, -- invalidates an in-flight forced revert; see revert()
}

-- SERVER-ONLY. Keyed by UserId. Never replicated — the only thing that crosses is the broadcast.
local monsters: { [number]: MonsterState } = {}

local transformedRemote = Remotes.Get("MonsterTransformed")
local killedRemote = Remotes.Get("PlayerKilled")

-- One parent for every corpse, so the raycast can exclude them wholesale and a phase change can clear
-- them with a single Destroy. Created on Start, never destroyed.
local corpses: Folder? = nil

local function stateFor(userId: number): MonsterState
	local existing = monsters[userId]

	if existing ~= nil then
		return existing
	end

	local created: MonsterState = {
		Transformed = false,
		Applied = false,
		Announced = false,
		AppliedTo = nil,
		OriginalParts = {},
		OriginalScales = {},
		Effects = {},
		LastRevertedAt = nil,
		BaseWalkSpeed = nil,
		Generation = 0,
	}

	monsters[userId] = created

	return created
end

--------------------------------------------------------------------------------
-- The look. Everything added lives under one folder, so reverting is a Destroy.
--------------------------------------------------------------------------------

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: RGB channel indices, not knobs
end

--[[
	Scale the avatar. R15 exposes these as NumberValues under the Humanoid; R6 has no equivalent and
	the loop simply finds nothing.

	RIG TYPE IS A PLACE-FILE SETTING AND THE PLACE FILE IS NOT IN GIT, so nothing in this repository
	can tell you which one is in use. The FindFirstChild guards make this correct either way: on R6 the
	Aswang gets the colour, material, eyes, particles and speed, and does not grow. That is a weaker
	tell, not a broken one, and it is a thing to LOOK AT during the two-client test rather than assume.
]]
local SCALE_VALUES = { "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }

local function applyScale(humanoid: Humanoid, scale: number)
	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)

		if value ~= nil and value:IsA("NumberValue") then
			value.Value = scale
		end
	end
end

--[[
	CAPTURE BEFORE MUTATING. This is the whole of the fix for the worst bug C04 shipped in review.

	The first version restored hardcoded defaults on revert — every part to white Plastic, every scale
	to 1.0. That is not what was there before, and the consequence is not cosmetic: after any revert
	the ex-Aswang becomes the ONLY character in the game whose parts are pure white Plastic at scale
	1.0. An exploiter reads that off the replicated properties from across the map, retroactively, with
	no remote traffic to intercept and no need to have witnessed anything.

	It also breaks the mechanic with no exploit at all. §4.3's revert exists so the Aswang blends back
	into the crowd; a survivor walking past a white plastic avatar a minute later gets the reveal free.

	Note the asymmetry that made this easy to miss: `BaseWalkSpeed` was already captured and restored
	correctly. The same discipline simply was not applied to colour, material and scale.
]]
local function captureLook(state: MonsterState, character: Model, humanoid: Humanoid)
	table.clear(state.OriginalParts)
	table.clear(state.OriginalScales)

	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(
				state.OriginalParts,
				{ Part = part, Color = part.Color, Material = part.Material }
			)
		end
	end

	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)

		if value ~= nil and value:IsA("NumberValue") then
			state.OriginalScales[name] = value.Value
		end
	end

	state.BaseWalkSpeed = humanoid.WalkSpeed
end

local function restoreLook(state: MonsterState)
	for _, look in state.OriginalParts do
		-- The character may have been destroyed under us (respawn, disconnect). A destroyed Instance
		-- still answers property writes harmlessly, but Parent is the cheap liveness test.
		if look.Part.Parent ~= nil then
			look.Part.Color = look.Color
			look.Part.Material = look.Material
		end
	end

	table.clear(state.OriginalParts)
	table.clear(state.OriginalScales)
end

-- Every Instance this service adds, tracked so the revert removes exactly what it created and nothing
-- else. The previous version destroyed EVERY PointLight and ParticleEmitter on the Head, which would
-- have deleted a lamp effect or a cosmetic from C34 that happened to live there.
local function trackedEffect(state: MonsterState, instance: Instance)
	table.insert(state.Effects, instance)
end

local function clearEffects(state: MonsterState)
	for _, effect in state.Effects do
		effect:Destroy()
	end

	table.clear(state.Effects)
end

--[[
	THE WINDUP'S TELL, applied at the START of the 1.2s rather than after it.

	§4.3 step 2 calls the windup "visible to anyone with line of sight", and the original code applied
	nothing until `task.wait(TransformTime)` had already returned — so the Aswang went from ordinary to
	monster in a single frame after a silent pause, and the entire risk half of the risk/reward was
	missing. An Aswang could fire the request in a crowd, walk into cover during 1.2s of nothing, and
	emerge already transformed.

	Particles first, then the full look. It escalates, which is what makes it a tell you can react to.
]]
local function applyWindupLook(state: MonsterState, character: Model)
	local head = character:FindFirstChild("Head")

	if head == nil or not head:IsA("BasePart") then
		return
	end

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(rgb(Config.Monster.EyeGlowRgb))
	particles.Rate = Config.Monster.TransformParticleRate
	particles.Lifetime = NumberRange.new(1)
	particles.Speed = NumberRange.new(1)
	particles.Parent = head

	trackedEffect(state, particles)
end

local function applyFullLook(state: MonsterState, character: Model, humanoid: Humanoid)
	for _, look in state.OriginalParts do
		if look.Part.Parent ~= nil then
			look.Part.Color = rgb(Config.Monster.TransformedTintRgb)
			look.Part.Material = Enum.Material.Slate
		end
	end

	applyScale(humanoid, Config.Monster.TransformedScale)

	local head = character:FindFirstChild("Head")

	if head ~= nil and head:IsA("BasePart") then
		local glow = Instance.new("PointLight")
		glow.Color = rgb(Config.Monster.EyeGlowRgb)
		glow.Range = Config.Monster.EyeGlowRange
		glow.Brightness = Config.Monster.EyeGlowBrightness
		glow.Parent = head

		trackedEffect(state, glow)
	end
end

--------------------------------------------------------------------------------
-- The corpse (§4.3 step 4). "Corpse remains for 45s, then fades."
--------------------------------------------------------------------------------

--[[
	THE CORPSE IS THE VICTIM'S OWN CHARACTER, DETACHED — not a clone.

	A clone would need Archivable to be true, would duplicate every accessory and its meshes, and would
	arrive at a client as a brand-new model at the same instant the original disappeared. Detaching
	keeps the body that was already replicated and already being looked at, which is the difference
	between "someone died here" and "a prop appeared".

	`player.Character = nil` is what makes it a prop: the player no longer owns it, so nothing the
	client sends moves it. Anchoring every part is the belt to that braces — it also stops the body
	sliding down a hill for 45 seconds, which is comic rather than frightening (§4.9).

	NO BLOOD, NO RAGDOLL, NO DISMEMBERMENT. §4.9 is a business constraint, not a taste one: gore pushes
	the age rating to 13+ and cuts off the audience that plays and spends the most. A body that lies
	there and fades is the whole effect.
]]
local function makeCorpse(victim: Player, character: Model)
	victim.Character = nil

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid ~= nil then
		-- Stop it standing up, walking, or being steered. WalkSpeed 0 is not a balance number.
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			-- A body should not be a wall. It also should not be a raycast blocker; the kill's line of
			-- sight excludes this whole folder for the same reason.
			part.CanCollide = false
		end
	end

	character.Name = `Corpse_{victim.UserId}`
	character.Parent = corpses

	--[[
		The fade, then the removal. Registered as one delayed closure rather than a loop: a corpse that
		is Destroyed early — by a phase change, or by the server closing — leaves a tween pointed at a
		destroyed instance, which is harmless, whereas a running loop is a live coroutine per corpse.
	]]
	task.delay(Config.Monster.CorpseDuration, function()
		if character.Parent == nil then
			return
		end

		local info = TweenInfo.new(Config.Monster.CorpseFadeTime)

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				TweenService:Create(part, info, { Transparency = 1 }):Play()
			end
		end

		task.delay(Config.Monster.CorpseFadeTime, function()
			character:Destroy()
		end)
	end)
end

-- Every corpse goes when the round does. Bodies from the last round standing in the plaza during
-- INTERMISSION is the kind of thing that reads as a bug in a clip, and clips are the marketing.
local function clearCorpses()
	local folder = corpses

	if folder == nil then
		return
	end

	for _, corpse in folder:GetChildren() do
		corpse:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Transform and revert
--------------------------------------------------------------------------------

local function revert(player: Player)
	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId every time a
	-- stale forced-revert timer fired, growing `monsters` unbounded inside a single ACTIVE phase.
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false
	monster.LastRevertedAt = os.clock()
	-- Any forced-revert timer still in flight for the PREVIOUS transform now belongs to a stale
	-- generation and will decline to act. Without this, a salt-forced revert at C14 followed by a
	-- fresh transform would be cut short by the first transform's expiry timer.
	monster.Generation += 1

	--[[
		THE CHARACTER THE LOOK WAS APPLIED TO, not player.Character.

		Resolving the character at revert time lands on whatever the player is wearing NOW, which after
		a respawn is a fresh body that never transformed — and the revert would then strip it and
		announce it. Cleanup belongs to the thing that was changed.
	]]
	local character = monster.AppliedTo

	if monster.Applied and character ~= nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if humanoid ~= nil then
			for name, value in monster.OriginalScales do
				local scaleValue = humanoid:FindFirstChild(name)

				if scaleValue ~= nil and scaleValue:IsA("NumberValue") then
					scaleValue.Value = value
				end
			end

			if monster.BaseWalkSpeed ~= nil then
				humanoid.WalkSpeed = monster.BaseWalkSpeed
			end
		end

		restoreLook(monster)
	end

	clearEffects(monster)

	--[[
		ANNOUNCE ONLY WHAT WAS ANNOUNCED. `Transformed` is set before the windup so the spam race is
		closed, which means a revert during the windup reaches here for a player NO CLIENT EVER SAW
		TRANSFORM. Broadcasting a revert for them is an unconditional identity broadcast — inert today,
		and at C14 it is "throw salt at a suspect mid-windup and be told whether you were right".
	]]
	if monster.Announced and character ~= nil then
		local payload: Types.MonsterTransformedPayload =
			{ Character = character, Transformed = false }

		transformedRemote:FireAllClients(payload)
	end

	monster.Applied = false
	monster.Announced = false
	monster.AppliedTo = nil
end

local function transform(player: Player)
	local monster = stateFor(player.UserId)
	local character = player.Character

	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return
	end

	monster.Transformed = true
	monster.Generation += 1
	monster.AppliedTo = character

	local generation = monster.Generation

	-- Capture BEFORE anything is mutated. Everything the revert restores is read here and nowhere else.
	captureLook(monster, character, humanoid)

	-- The windup (§4.3 step 2), and its tell starts NOW rather than when it ends. `Applied` is set
	-- with it, so a revert during the windup cleans up exactly these particles and nothing more.
	monster.Applied = true
	applyWindupLook(monster, character)

	task.wait(Config.Monster.TransformTime)

	-- Still the same transform? A revert during the windup (a disconnect, a phase change, salt at
	-- C14) invalidates it, and applying the look afterwards would leave a permanent monster.
	if monster.Generation ~= generation or not monster.Transformed then
		return
	end

	humanoid.WalkSpeed = humanoid.WalkSpeed * Config.Monster.TransformedSpeedMult

	applyFullLook(monster, character, humanoid)

	--[[
		THE GUARANTEE BEFORE THE ANNOUNCEMENT.

		Registered before the broadcast, deliberately. If FireAllClients throws — and its payload
		carries a Model that can be destroyed under it — the coroutine dies, and with the ordering
		reversed the forced-revert timer would never have been registered, leaving a permanent monster
		clearable only by a phase change.
	]]
	task.delay(Config.Monster.MaxTransformTime, function()
		if monster.Generation == generation and monster.Transformed then
			revert(player)
		end
	end)

	monster.Announced = true

	local payload: Types.MonsterTransformedPayload = { Character = character, Transformed = true }

	transformedRemote:FireAllClients(payload)
end

--------------------------------------------------------------------------------
-- The remote. AntiCheat FIRST, validation SECOND.
--------------------------------------------------------------------------------

local function validateAndTransform(player: Player)
	local monster = stateFor(player.UserId)

	local verdict = TransformRules.evaluate({
		IsAswang = RoleService.IsAswang(player),
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Transformed = monster.Transformed,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		-- Logged, never echoed. Returning the verdict would hand any client a free role oracle: fire
		-- the remote, read NOT_ASWANG or ON_COOLDOWN, and you know who the monster is without seeing it.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused transform for {player.Name}: {verdict}`)
		end

		return
	end

	transform(player)
end

--------------------------------------------------------------------------------
-- The kill (§4.3 steps 3–5, C05)
--------------------------------------------------------------------------------

-- Vector3 -> the plain table pure/KillValidation takes. The pure module cannot mention Vector3: Lune
-- has no Roblox datatypes and the whole module would stop being runnable from a terminal.
local function vec(position: Vector3): KillValidation.Vec3
	return { X = position.X, Y = position.Y, Z = position.Z }
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")

	return if root ~= nil and root:IsA("BasePart") then root :: BasePart else nil
end

--[[
	THE ONE CONDITION THAT CANNOT BE PURE (§4.3, "raycast line-of-sight").

	Killing through a wall is the difference between a stalking game and a lag-compensated murder
	simulator, and it is the single most valuable exploit in this game after knowing the role: an
	exploiter who can kill through geometry never has to be seen, which deletes the transform's entire
	risk half.

	The filter excludes both characters — otherwise the ray hits the killer's own torso at zero distance
	and every kill is refused — and the corpse folder, because a body is not cover. Note that a raycast
	hits parts regardless of CanCollide unless RespectCanCollide is set, so making corpses
	non-collidable is NOT enough on its own.

	`workspace:Raycast(origin, direction, params)` returns nil when nothing was hit, which is the
	"clear line" case. This API is not used anywhere else in this repository yet — see Follow Ups; the
	Phase 4 playtest is where it is confirmed rather than assumed, and the failure mode if
	`Enum.RaycastFilterType.Exclude` is wrong for this engine version is that EVERY kill is refused,
	which is loud rather than silent.
]]
local function hasLineOfSight(killerRoot: BasePart, targetRoot: BasePart): boolean
	local params = RaycastParams.new()

	--[[
		BUILT AS A LIST, not as a literal with a `corpses :: Instance` cast in it. The plan proposed the
		cast and flagged it for confirmation; the analyzer answered first — `Folder?` does not cast to
		`Instance`, because the optional is a union and the two are unrelated types.

		Doing it this way is also the honest reading of the nil case: if Start() has not run there is no
		corpse folder, and therefore nothing to exclude. An excluded nil would have been silently
		tolerated at runtime and silently wrong the day the folder mattered.
	]]
	local filter: { Instance } = { killerRoot.Parent :: Instance, targetRoot.Parent :: Instance }
	local folder = corpses

	if folder ~= nil then
		table.insert(filter, folder)
	end

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true

	local origin = killerRoot.Position
	local result = workspace:Raycast(origin, targetRoot.Position - origin, params)

	return result == nil
end

--[[
	The commit, in the ONE order that works. Every line here depends on the one above it.

	  1. The corpse first, because it steals the character from the player. RoundService.MarkKilled
	     applies the body rule, which destroys a character the victim still owns — so if this ran second
	     there would be no body left to make a corpse out of.
	  2. The state change, which is what makes the victim uncounted, bodiless and unkillable.
	  3. The revert (§4.3 step 4, "after a kill it must revert"). This is ALSO what starts the cooldown,
	     because revert() stamps LastRevertedAt — §4.3 step 5's "30s from revert" is not implemented as
	     a separate timer anywhere, it is this line.
	  4. The broadcast, last, so no client is told about a kill the server has not finished committing.
]]
local function commitKill(killer: Player, victim: Player, victimCharacter: Model, position: Vector3)
	makeCorpse(victim, victimCharacter)

	-- `true` = this death was a validated kill, so it counts towards §4.8's attrition win. Every other
	-- caller passes nothing: a reset or a fall makes the player a GHOST but must NOT credit the Aswang,
	-- or one survivor pressing the stock reset button ends a 3-player round as ASWANG_WINS.
	RoundService.MarkKilled(victim, true)

	revert(killer)

	-- TWO FIELDS. See Types.PlayerKilledPayload: the killer appears nowhere in it, in any form, and
	-- nothing in this repo would catch it if it did. Built as a typed local rather than an inline table
	-- because FireAllClients takes `...any` and an inline literal is checked against nothing at all.
	local payload: Types.PlayerKilledPayload = { VictimUserId = victim.UserId, Position = position }

	killedRemote:FireAllClients(payload)
end

local function validateAndKill(killer: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)

	if target == nil then
		return
	end

	local killerCharacter = killer.Character
	local targetCharacter = target.Character

	if killerCharacter == nil or targetCharacter == nil then
		return
	end

	local killerRoot = rootOf(killerCharacter)
	local targetRoot = rootOf(targetCharacter)

	if killerRoot == nil or targetRoot == nil then
		return
	end

	local monster = stateFor(killer.UserId)

	local verdict = KillValidation.evaluate({
		Phase = RoundService.GetPhase(),
		KillerUserId = killer.UserId,
		TargetUserId = target.UserId,
		KillerIsAswang = RoleService.IsAswang(killer),
		TargetIsAswang = RoleService.IsAswang(target),
		KillerState = RoundService.GetPlayerState(killer),
		TargetState = RoundService.GetPlayerState(target),
		--[[
			`Announced`, NOT `Transformed`, and the difference is a whole mechanic.

			`Transformed` is set BEFORE the 1.2s windup (to close the spam race), so using it here would
			let the Aswang fire RequestTransform and RequestKill back to back and kill during the windup
			— before anyone with line of sight has seen anything. §4.3 step 2 calls that windup "visible
			to anyone with line of sight" and it is the entire risk half of the risk/reward. `Announced`
			is set only after MonsterTransformed(true) has gone out, so the kill unlocks exactly when the
			warning does.
		]]
		Transformed = monster.Announced,
		KillerPos = vec(killerRoot.Position),
		TargetPos = vec(targetRoot.Position),
		Range = Config.Monster.KillRange,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		-- LOGGED, NEVER ECHOED, and the stakes are higher than they are for the transform. Returning
		-- TARGET_IS_ASWANG or NOT_ASWANG to a client is a role oracle you can walk through the whole
		-- server with: fire at each player in turn and read which answer comes back.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused kill by {killer.Name}: {verdict}`)
		end

		return
	end

	-- LAST, because it is the only check that touches the physics engine. Everything cheap has already
	-- said yes, so the expensive one runs at most once per legitimate attempt — which is what makes an
	-- unauthorised spam of this remote cost the server nothing beyond a table lookup.
	if not hasLineOfSight(killerRoot, targetRoot) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused kill by {killer.Name}: NO_LINE_OF_SIGHT`)
		end

		return
	end

	commitKill(killer, target, targetCharacter, targetRoot.Position)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPhaseChanged(phase: Types.RoundPhase)
	--[[
		CORPSES ARE CLEARED ON THE WAY INTO THE LOBBY, NOT ON THE WAY OUT OF ACTIVE.

		Clearing on "any phase that is not ACTIVE" destroyed the winning kill's body within a frame of
		creating it: MarkKilled calls EndRound, which sets ENDING, which fires PhaseChanged, which
		landed here — while `commitKill` was still on the stack that made the corpse. §4.3 step 4 says
		the body remains 45s, and §4.8 calls the end screen "the screenshot people share", so the one
		round where the bodies matter most was the one round that had none.

		ENDING keeps them. INTERMISSION and IDLE clear them, which still satisfies the original reason
		for clearing at all — no bodies from last round standing in the plaza while people wait.
	]]
	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearCorpses()
	end

	if phase == Enums.RoundPhase.Active then
		return
	end

	-- Leaving ACTIVE ends every transform and clears the cooldowns, so a new round never begins with
	-- a monster still standing or an Aswang serving the last round's penalty.
	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)

		if player ~= nil then
			revert(player)
		end
	end

	table.clear(monsters)
end

--[[
	A TRANSFORMED ASWANG THAT DIES MUST REVERT. C04's deferred finding, marked "a required input to
	C05" because until this chunk there was no way to die at all.

	Note what this is NOT: the kill path does not go through Humanoid.Died — the victim's character is
	detached and anchored, never killed, because §4.9 wants a fade rather than a death animation. This
	connection covers everything else that can end a character mid-transform: falling out of the world,
	a Studio-side reset, and whatever C14's salt does to a monster standing in a bad place.

	Reverting on death also charges the cooldown, because revert() stamps LastRevertedAt. That is the
	right answer rather than a side effect: dying while transformed should cost the Aswang the same 30
	seconds a completed hunt does, or falling off a roof becomes a free reset.
]]
local function watchCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return
	end

	humanoid.Died:Connect(function()
		revert(player)
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)

	-- RoundService turns CharacterAutoLoads off and loads explicitly (Step 1.4), so a character can
	-- already exist by the time this service's Start() runs on a live server.
	local character = player.Character

	if character ~= nil then
		watchCharacter(player, character)
	end
end

local function onPlayerRemoving(player: Player)
	monsters[player.UserId] = nil
end

function MonsterService.Init()
	table.clear(monsters)
end

function MonsterService.Start()
	local folder = Instance.new("Folder")

	folder.Name = "Corpses"
	folder.Parent = workspace
	corpses = folder

	--[[
		THE RATE LIMIT LIVES HERE, INLINE, and not inside validateAndTransform — deliberately.

		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`. It is a proximity tripwire, by its own
		admission, so a handler that IS rate-limited but does it 250 lines away reads as unguarded and
		fails the build. That is the check being blunt rather than wrong: a reader skimming the connect
		site should be able to see the guard without following a call, and every later handler in this
		game will copy whatever shape this one sets.

		Consume FIRST, before any state is read. A handler that validates first has already done the
		expensive work by the time it refuses, which is what makes a remote worth spamming.
	]]
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

		validateAndTransform(player)
	end)

	-- Same shape as the handler above, for the same reason: `check-ratelimit.mjs` matches the Consume
	-- call within 1200 characters of the connect site, so the guard is visible to a reader skimming the
	-- file and to the gate. Consume FIRST, before the UserId is even looked at.
	Remotes.Get("RequestKill").OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
		if not AntiCheatService.Consume(player, "RequestKill") then
			return
		end

		-- A remote argument is whatever the client sent. `targetUserId` is typed `unknown` rather than
		-- `number` precisely so this line cannot be skipped: without it a table or a function reaches
		-- GetPlayerByUserId and throws inside a connection, which Roblox swallows into one warn.
		if typeof(targetUserId) ~= "number" then
			return
		end

		validateAndKill(player, targetUserId)
	end)

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Anyone already here. Same reasoning as RoundService.Start's backfill: connect first, then sweep,
	-- and accept that a player arriving in the window is handled twice. watchCharacter is idempotent
	-- only in the sense that a second Died connection calls revert() twice, and revert() early-returns
	-- when the player is not transformed — so the double is harmless.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MonsterService
