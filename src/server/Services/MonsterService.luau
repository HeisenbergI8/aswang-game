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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local RoleService = require(script.Parent.RoleService)
local RoundService = require(script.Parent.RoundService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
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
-- Lifecycle
--------------------------------------------------------------------------------

local function onPhaseChanged(phase: Types.RoundPhase)
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

local function onPlayerRemoving(player: Player)
	monsters[player.UserId] = nil
end

function MonsterService.Init()
	table.clear(monsters)
end

function MonsterService.Start()
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
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return MonsterService
