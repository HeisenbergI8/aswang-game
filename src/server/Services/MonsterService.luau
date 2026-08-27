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

	V05 ADDS A NUMBER AND SENDS NOTHING. The Aswang's health is a field on the server-only `monsters`
	table and it has no remote, no attribute, no tag and no field on any payload. §6.2: "the Aswang's
	health is server-only state, readable by others only while `Exposed`." The one channel it uses is
	the brightness of a Highlight that EXISTS only during the Exposed window — so the permission and
	the mechanism are the same fact, and there is no state in which the readout outlives the licence.

	IT IS NOT ON THE HUMANOID, AND THAT IS THE WHOLE POINT. `Humanoid.Health` and `Humanoid.MaxHealth`
	replicate. One character reading 75 while four read 100 is a permanent, map-wide, remote-free role
	oracle — the same shape as C04's revert bug and C14's WalkSpeed brand, both of which shipped with
	`verify` and `check:secrecy` green over them. See `.claude/lessons/absence-is-observable.md`: the
	leak is a DIFFERENCE between players, not a piece of data.

	THE FOUR SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:

	  · `ApplySaltHit(player)` — V08. Revert, -SaltDamage floored at WeakenedThreshold, Exposed for
	    SaltRevealDuration. The ONLY entry point for a salt hit; there is no bare `ForceRevert` any
	    more, precisely so a caller cannot revert without damaging.
	  · `HealFromFeed(userId) -> boolean` — V06, on a COMPLETED feed. Returns whether state existed,
	    never the health. Does not restore camouflage; that is V07's half of §4.3's reward.
	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
	    Aswang that is BOTH. AND them with `RoundService.GetAswangUserId()` on the server and hand a
	    single boolean to the pure module, exactly as `ItemService` does for `IsTransformed`.

	NONE OF THE FOUR ENUMERATES, and none returns the health value. Every one takes a UserId the
	caller already holds and answers false for a player with no monster state — which is every
	survivor, every round, so none of them is usable as a probe.

	`MonsterTransformed` carries a Character and a boolean. It does NOT carry a role: "this character
	transformed" is a fact about the world; "this player is the Aswang" is an inference the client is
	welcome to make and the server never states. The distinction becomes load-bearing at C14, where
	salt forces a revert on someone who is still the Aswang.

	The refusal verdict is likewise never echoed back. It exists so the server can log WHY, and handing
	a client `NOT_ASWANG` would be a free role oracle for anyone willing to spam the remote.

	`PlayerKilled` (C05) carries a victim and a position, and NOTHING ELSE — no killer, no name, no
	direction, no distance, no "you were seen". SINCE AMENDMENT A3 IT ALSO GOES TO ONE CLIENT: the
	victim, via FireClient. Broadcast, it was the strongest death oracle in the game — see the comment
	at the fire site. Three things about the payload are worth knowing before anyone adds a field:

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
local TeachingService = require(script.Parent.TeachingService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local KillValidation = require(Shared.pure.KillValidation)
local MonsterHealth = require(Shared.pure.MonsterHealth)
local Remotes = require(Shared.Remotes)
local TransformRules = require(Shared.pure.TransformRules)
local Types = require(Shared.Types)

local MonsterService = {}

--[[
	THE HEALTH TUNING (V05, §4.6), ASSEMBLED ONCE FROM TWO CONFIG BLOCKS.

	`MaxHealth`, `WeakenedThreshold` and `FeedHeal` live under `Config.Monster`; `SaltDamage` lives
	under `Config.Items`, which is §6.5's canonical item block and where V02 put the four salt
	numbers. `pure/MonsterHealth` takes one table rather than reaching for either, so it stays a
	function over plain numbers and `tests/monster-health.test.luau` can hand it a synthetic tuning.

	READ THROUGH `Config.Items`, NOT THROUGH `Config.Salt`. The `Salt` block is a set of aliases V02
	kept alive for five v1.3 readers (Config.luau:326-342) and it dies with the chunk that renames
	its last one.
]]
local HEALTH_TUNING: MonsterHealth.Tuning = {
	MaxHealth = Config.Monster.MaxHealth,
	WeakenedThreshold = Config.Monster.WeakenedThreshold,
	SaltDamage = Config.Items.SaltDamage,
	FeedHeal = Config.Monster.FeedHeal,
}

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
	--[[
		THE ASWANG'S HEALTH (V05, §4.6). SERVER-ONLY, AND THIS FIELD IS THE ONLY COPY OF IT.

		NOT `Humanoid.Health` AND NOT `Humanoid.MaxHealth`. Both are replicated properties: writing
		this number onto the humanoid lets any client walk `workspace`, find the one character
		reading 75 while four others read 100, and know the monster — permanently, for free, with no
		remote to intercept and nothing for `check:secrecy` to see. That is the same shape as C04's
		revert bug and C14's WalkSpeed brand, both of which shipped green (see ItemService's
		`applyHit` header and `.claude/lessons/absence-is-observable.md`).

		Not an attribute and not a tag either; both replicate to every client and there is no private
		one.

		SURVIVES A TRANSFORM CYCLE, DIES WITH THE ROUND. It is deliberately not reset by `revert()` —
		§4.6's tug-of-war is a round-long resource, so three salt hits across three separate
		transforms still weaken. `onPhaseChanged`'s existing `table.clear(monsters)` on the way out
		of ACTIVE is the reset, and it is the only one.
	]]
	Health: number,
	-- V05, §4.6. EXPOSED IS THE TRUTH; the Highlight below is its presentation. Two fields rather
	-- than one because `IsExposed` is V08's strike gate and must not depend on whether an Instance
	-- happened to survive a respawn. Every exit clears both, together, in `clearExposed`.
	Exposed: boolean,
	ExposedGlow: Highlight?,
	-- The same `os.clock()` generation trick `revert()` uses, for the same reason: a second salt hit
	-- landing during the first one's window must not have its expiry cut short by the first timer.
	ExposedGeneration: number,
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
		Health = Config.Monster.MaxHealth,
		Exposed = false,
		ExposedGlow = nil,
		ExposedGeneration = 0,
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
--[[
	TAKES A UserId, NOT A Player, SINCE C15. A husk — the body of a player who disconnected mid-round —
	has no `Player` object at all, and it is a legitimate kill target. The only thing this function ever
	wanted from the Player was the id for the corpse's name.

	DETACHING IS THE CALLER'S JOB for the same reason. A live victim's character must be taken from them
	(`player.Character = nil`) before it becomes a corpse, or Roblox removes it with its owner; a husk
	was detached when it was created. `commitKill` does the detach; this function does the body.
]]
local function makeCorpse(victimUserId: number, character: Model)
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

	character.Name = `Corpse_{victimUserId}`
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

		--[[
			IT FADES BUT IS NOT DESTROYED. §4.3's "corpse remains for 45s, then fades" is honoured
			visually; the Model itself survives until `clearCorpses` takes it at the end of the round.

			WHY: since C15's redesign the corpse IS the dead player's `player.Character`, and that is
			what keeps `Character ~= nil` true for everybody. Destroying it here would set that property
			to nil for exactly the dead, and `Character == nil` is one line for any client to enumerate —
			the death oracle Amendment A3 removed two other channels to close. The body going invisible
			is the intended §4.3 behaviour; the body ceasing to exist is a leak with a 45-second fuse.

			`clearCorpses` runs on the way into INTERMISSION and IDLE, at which point every player's
			state is being rewritten anyway and the distinction carries nothing.
		]]
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
-- Health (V05, §4.6). The tug-of-war: salt takes it down, feeding pulls it back.
--------------------------------------------------------------------------------

--[[
	THE GLOW'S BRIGHTNESS IS THE HEALTH READOUT (§4.6). "The intended presentation is diegetic and
	needs no UI at all: the glow gets brighter as it weakens."

	THIS IS THE ONE CHANNEL HEALTH IS ALLOWED TO USE, and it is legal for a reason that is structural
	rather than permitted: §6.2 says health is "readable by others only while `Exposed`", and this
	Highlight EXISTS only while Exposed. There is no arrangement in which it publishes health outside
	the window, because outside the window there is no instance to read.

	THE COLOURS STAY UNDER `Config.Salt` and the RAMP under `Config.Monster`, which is not an
	oversight: salt paints the glow, health decides how bright it burns. See Config.luau's comment on
	`ExposedGlowTransparency*`.

	DECLARED ABOVE `applyHealthEvent` BECAUSE THAT FUNCTION CALLS IT. Lua resolves a `local function`
	only from its declaration onward, so the reverse order made this a nil GLOBAL — a runtime error on
	the first salt hit, which `analyze` caught and no test would have.
]]
local function refreshExposedGlow(monster: MonsterState)
	local glow = monster.ExposedGlow

	if glow == nil then
		return
	end

	local full = Config.Monster.ExposedGlowTransparencyFull
	local weakened = Config.Monster.ExposedGlowTransparencyWeakened
	local fraction = MonsterHealth.weakenedFraction(monster.Health, HEALTH_TUNING)

	glow.FillTransparency = full + (weakened - full) * fraction
end

--[[
	APPLY ONE HEALTH EVENT TO A PLAYER'S SERVER STATE. Returns true if the state existed.

	READ, DO NOT CONSTRUCT — `stateFor` here would re-insert a departed player's UserId every time a
	stale timer fired, which is the exact bug `revert()`'s first line was written to avoid. Every
	caller reaches this function only after the server has already established that this player is a
	transformed Aswang, so the entry exists; a missing entry means the round moved on and the answer
	is to do nothing.

	IT RETURNS A BOOLEAN AND NEVER THE HEALTH. The value has exactly one home (see MonsterState) and
	handing it back is how a second copy starts existing — in a payload, in a log line, in an
	attribute somebody added to debug it. Callers that need a decision ask `IsWeakened`.

	THE FLOOR IS NOT ENFORCED HERE. `MonsterHealth.apply` owns it, gated on
	`lune run tests/monster-health.test.luau`, so there is one implementation of §4.6's most
	consequential rule and it is the tested one.
]]
local function applyHealthEvent(userId: number, event: MonsterHealth.HealthEvent): boolean
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return false
	end

	monster.Health = MonsterHealth.apply(monster.Health, event, HEALTH_TUNING)

	--[[
		AND REPAINT THE GLOW, because the brightness IS the health readout and a stale one is a lie.

		Every health change goes through here, so this is the one place that cannot be forgotten.
		`ApplySaltHit` would work without it — it calls `applyExposed`, which repaints on the way in —
		but V06's `HealFromFeed` will not: a feed completed inside a live Exposed window would restore
		25 health and leave the glow reading the pre-feed value for the rest of the ten seconds.
		Survivors would see a monster that looks one hit from death and is not.

		`refreshExposedGlow` early-returns when there is no glow, so this costs a nil check on every
		non-Exposed health change and nothing else.
	]]
	refreshExposedGlow(monster)

	return true
end

--[[
	END THE EXPOSED WINDOW. Idempotent, and safe to call for a player who was never exposed.

	THE BOOLEAN AND THE INSTANCE ALWAYS DIE TOGETHER. A `clearExposed` that destroyed the glow and
	left `Exposed = true` would leave V08 able to kill a monster nobody can see glowing; one that did
	the reverse would leave a permanent mark on one character in the workspace, which is the C04/C14
	failure exactly.
]]
local function clearExposed(userId: number)
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return
	end

	local glow = monster.ExposedGlow

	monster.Exposed = false
	monster.ExposedGlow = nil

	if glow ~= nil then
		glow:Destroy()
	end
end

--[[
	BEGIN THE EXPOSED WINDOW (§4.6): "a hit forces the revert, applies a visible glow for 10s".

	Moved here from `ItemService.applyReveal` at V05 with its reasoning intact, because the
	brightness is now a function of health. A Highlight AND NOT: an attribute (replicates, and
	`check:secrecy` refuses role-named ones for exactly this reason), a CollectionService tag (same),
	a name colour (`TeamColor` and `Team` both replicate and are the classic version of this
	mistake), or a per-client effect (a "hidden" reveal is one a compromised client reads and an
	honest one does not — the worst of both).

	`DepthMode = Occluded` IS A DESIGN DECISION HIDING IN AN ENUM VALUE. `AlwaysOnTop` renders the
	glow THROUGH WALLS, turning a ten-second reveal into a ten-second wallhack on the monster.

	NOTHING HERE IS NAMED FOR A ROLE, and there is no role in this call chain to name: the decision
	that this player was a transformed Aswang was made and discarded back in `ItemService`'s
	`resolveThrow`.
]]
local function applyExposed(player: Player)
	local monster: MonsterState? = monsters[player.UserId]
	local character = player.Character

	if monster == nil or character == nil then
		return
	end

	clearExposed(player.UserId)

	local glow = Instance.new("Highlight")
	local generation = os.clock()

	glow.Name = "SaltReveal"
	glow.FillColor = rgb(Config.Salt.RevealGlowFillRgb)
	glow.OutlineColor = rgb(Config.Salt.RevealGlowOutlineRgb)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = character

	monster.Exposed = true
	monster.ExposedGlow = glow
	monster.ExposedGeneration = generation

	refreshExposedGlow(monster)

	task.delay(Config.Items.SaltRevealDuration, function()
		local current: MonsterState? = monsters[player.UserId]

		-- A NEW ENTRY OR A NEWER HIT BOTH DECLINE. `table.clear(monsters)` on the way out of ACTIVE
		-- can drop this player's state entirely and `stateFor` can rebuild it next round with
		-- `ExposedGeneration = 0`, which no live generation ever equals.
		if current == nil or current.ExposedGeneration ~= generation then
			return
		end

		clearExposed(player.UserId)
	end)
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

--[[
	THE BROADCAST AND ITS TEACHING CUE, IN ONE PLACE, SO THEIR AUDIENCES CANNOT DIVERGE.

	`MonsterTransformed` is public by design — the tell is the point (§4.3) — and it is
	`FireAllClients`. C23 cues every player about it, and that is safe for two independent reasons:
	the audiences are identical, and the cue's payload is a constant id resolving to "That is the
	tell. Run, or salt it." — no character, no UserId, no position. It would be safe even if the
	broadcast did not exist.

	NARROWING THE CUE BY PROXIMITY IS THE MISTAKE AVAILABLE HERE, and it would look like an
	improvement: only tell players who can actually see it. That subset is computed from the ASWANG'S
	POSITION and delivered per-player — and because the cue is FIRE-ONCE, it would leave a permanent
	per-client mark of "I was near the first transform", outliving the broadcast that justified it.

	An exploit audit made the point that decided this shape: the equality was previously held only by
	two adjacent lines and a comment, and nothing would fail if someone later narrowed one and not the
	other. `check:secrecy` structurally cannot see it. Here, the audience is ONE expression — a change
	to it is a change to both, and shows up as such in a diff. §4.3's "visible to anyone with line of
	sight" is exactly the phrase that will one day invite a filter on the broadcast; when it does, this
	function is where both halves move together.
]]
local function announceTransform(payload: Types.MonsterTransformedPayload)
	local audience = Players:GetPlayers()

	transformedRemote:FireAllClients(payload)

	for _, witness in audience do
		TeachingService.Cue(witness, "CUE_FIRST_TRANSFORM_SEEN")
	end
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

	announceTransform(payload)
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

	--[[
		HUSKS TOO, SINCE C15, AND FOR THE IDENTICAL REASON THE CORPSE FOLDER IS HERE: a body is not
		cover. The comment above already states that a raycast hits parts regardless of CanCollide —
		which is why anchoring husks and clearing their collision (`RoundService.onPlayerRemoving`) is
		NOT sufficient on its own and this exclusion is still required.

		Without this, quitting while standing in a doorway leaves permanent cover for every survivor
		for the rest of the round — the ray stops on your abandoned body — and two alts turn a
		chokepoint into a safe room. A disconnected player affecting a live fight is precisely what
		the corpse exclusion exists to prevent, arriving through a folder that did not exist when that
		rule was written.
	]]
	local husks = RoundService.GetHusksFolder()

	if husks ~= nil then
		table.insert(filter, husks)
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
	--[[
		THE CHARACTER IS **NOT** DETACHED, AND THAT IS THE C15 REDESIGN IN ONE LINE.

		This used to read `victim.Character = nil`, so a dead player had no character for the rest of
		the round. An exploit audit found that `Character == nil` is itself the death oracle — one line
		to enumerate, a `GetPropertyChangedSignal` away from a timestamped death alert, and since the
		Aswang is never a ghost, each nil eliminates a candidate. Amendment A3 deleted two channels to
		close exactly that.

		So the corpse STAYS as `victim.Character`. Every player has a character at all times, and what a
		client can still learn is what §4.7 and A3 always intended: a body lying in the Barrio is a dead
		player, and you have to look at it. Under §5's `StreamingEnabled` (C17) a distant corpse does not
		replicate at all, which makes that literally true. Before C17 it is PARTIAL — everything
		replicates, so a property scan still tells a corpse from a walker.

		`RoundService.MarkKilled` is safe with the body attached because `BodyTransitions` answers KEEP
		for every GHOST cause: nothing downstream revokes or replaces it.
	]]
	makeCorpse(victim.UserId, victimCharacter)

	-- `true` = this death was a validated kill, so it counts towards §4.8's attrition win. Every other
	-- caller passes nothing: a reset or a fall makes the player a GHOST but must NOT credit the Aswang,
	-- or one survivor pressing the stock reset button ends a 3-player round as ASWANG_WINS.
	RoundService.MarkKilled(victim, true)

	revert(killer)

	--[[
		TWO FIELDS AND ONE RECIPIENT. See Types.PlayerKilledPayload: the killer appears nowhere in it,
		in any form, and nothing in this repo would catch it if it did. Built as a typed local rather
		than an inline table because FireClient takes `...any` and an inline literal is checked against
		nothing at all.

		FireClient, NOT FireAllClients, SINCE AMENDMENT A3 — and the change is not cosmetic.

		Broadcast, this was a stronger death oracle than the `AlivePlayerCount` field that A3 removed:
		that field made an attacker infer the position from replicated character logs, and this handed
		it over directly, timestamped, with the victim named. Removing one while keeping the other
		would have been theatre.

		THE OLD DEFENCE WAS "THE CORPSE REPLICATES ANYWAY", AND §5 MAKES IT FALSE. The corpse is a
		Model in `workspace.Corpses`, and C17 turns `StreamingEnabled` on from the start — under which
		a corpse 200 studs away does not reach a client and this remote did. The two were never
		equivalent; they only looked it on an unstreamed baseplate.

		The victim keeps it because the victim is the one client with a use for it:
		`CameraFXController.onPlayerKilled` plays a first-person death reaction, which was until now
		firing on seven screens belonging to people who had not died. That controller needs no change —
		its `isMine` branch simply becomes the only branch it ever takes.
	]]
	local payload: Types.PlayerKilledPayload = { VictimUserId = victim.UserId, Position = position }

	killedRemote:FireClient(victim, payload)
end

--[[
	KILLING A HUSK (§6.4, C15) — a body whose owner disconnected mid-round.

	Separate from `validateAndKill` because a husk has no `Player`, and every input that function
	reaches for through one — `RoleService.IsAswang(target)`, `RoundService.GetPlayerState(target)`,
	`target.Character` — has to come from somewhere else. Sharing the path would mean threading a
	`Player?` through all of it and nil-checking at five sites, which is how the target half of the
	rule quietly stops being validated.

	WHAT IS GUARANTEED RATHER THAN CHECKED, and why:

	  · `TargetIsAswang = false`. `RoundService.onPlayerRemoving` ABORTS the round when the Aswang
	    leaves, so the Aswang never has a husk. This is the one assumption here and it is enforced
	    somewhere a reader can go and look at.
	  · `TargetState = ALIVE`. `RoundService` only creates a husk for a player whose stored state was
	    ALIVE at the moment they left.

	Everything else — phase, killer role, transform, cooldown, range, line of sight — runs through the
	SAME `KillValidation.evaluate` and the SAME raycast a live kill does. A husk is not an easier
	target, it is the same target with nobody watching the screen.
]]
local function validateAndKillHusk(
	killer: Player,
	targetUserId: number,
	huskCharacter: Model
): boolean
	local killerCharacter = killer.Character

	if killerCharacter == nil then
		return false
	end

	local killerRoot = rootOf(killerCharacter)
	local targetRoot = rootOf(huskCharacter)

	if killerRoot == nil or targetRoot == nil then
		return false
	end

	local monster = stateFor(killer.UserId)

	local verdict = KillValidation.evaluate({
		Phase = RoundService.GetPhase(),
		KillerUserId = killer.UserId,
		TargetUserId = targetUserId,
		KillerIsAswang = RoleService.IsAswang(killer),
		TargetIsAswang = false,
		KillerState = RoundService.GetPlayerState(killer),
		TargetState = Enums.PlayerState.Alive,
		Transformed = monster.Announced,
		KillerPos = vec(killerRoot.Position),
		TargetPos = vec(targetRoot.Position),
		Range = Config.Monster.KillRange,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused husk kill by {killer.Name}: {verdict}`)
		end

		return false
	end

	if not hasLineOfSight(killerRoot, targetRoot) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused husk kill by {killer.Name}: NO_LINE_OF_SIGHT`)
		end

		return false
	end

	--[[
		STATE FIRST, THEN THE BODY. `MarkHuskKilled` drops the husk entry and stamps the owner's stored
		state to GHOST — so a player reconnecting one frame later is resolved as dead, which is what
		happened to them. It deliberately does NOT destroy the Model, because the next line turns that
		same Model into the corpse.

		No `PlayerKilled` remote fires. Since Amendment A3 that remote goes to the VICTIM alone, and the
		victim is not connected — there is nobody to send it to. The corpse is the signal, exactly as it
		is for everyone else.
	]]
	RoundService.MarkHuskKilled(targetUserId)

	--[[
		THE REVERT, and it is not optional garnish. §4.3 step 4 reverts after a kill, and `revert()` is
		what stamps `LastRevertedAt` — which IS the kill cooldown, per KillValidation's inputs above.
		Omitting it here would let the Aswang clear a plaza full of husks with no cooldown between them,
		which is the exact opposite of what the husk is for.
	]]
	revert(killer)

	makeCorpse(targetUserId, huskCharacter)

	return true
end

local function validateAndKill(killer: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)

	--[[
		NO PLAYER? IT MAY STILL BE A HUSK. Falling straight out here is what made a disconnect a free
		escape: the body stood in the Barrio and nothing could touch it.
	]]
	if target == nil then
		local husk = RoundService.GetHuskCharacter(targetUserId)

		if husk ~= nil then
			validateAndKillHusk(killer, targetUserId, husk)
		end

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

		--[[
			AND EVERY EXPOSED WINDOW (V05, §4.6), BEFORE `table.clear` BELOW DROPS THE HANDLE.

			`table.clear(monsters)` on its own would orphan the Highlight: the state that knows the
			instance is gone, the instance is still parented to a living character, and nothing will
			ever destroy it. A player hit at second 419 of a 420-second round would then glow in the
			lobby permanently — where the glow is no longer an event anybody witnessed and is simply
			a mark on one of the five people standing there.

			CLEARED ON `ENDING` TOO, not just on INTERMISSION/IDLE. The split that keeps corpses
			through ENDING (see above) is about scenery; this is about a mark on a player, and §4.8
			calls the end screen "the screenshot people share".

			This clear runs for a player still PRESENT but not yet reverted; it does NOT cover a
			player who has already left, because `onPlayerRemoving` removed them from `monsters`
			before this loop could see them. That exit is closed in `onPlayerRemoving` itself, which
			calls `clearExposed` before nilling the entry — see the comment there for what nilling
			alone leaves behind.
		]]
		clearExposed(userId)
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

--[[
	THE GLOWING CORPSE, closed here rather than left to the ten-second timer. Moved from
	`ItemService`'s `PlayerAdded` handler at V05, with its reasoning, because the Highlight moved.

	`makeCorpse` DETACHES the victim's character and keeps it in the workspace for `CorpseDuration`.
	A Highlight parented to that character goes with it — so a player revealed by salt and then
	killed leaves a glowing body lying in the Barrio, which reads to every passer-by as "this corpse
	was the monster". The reveal is supposed to be an event that expires, not a label on a body.

	The Aswang cannot be killed, so the reachable paths are a reset or a fall while revealed. Cheap
	to close and ugly if it ever shows up in a playtest video.

	NOT FOLDED INTO `revert()`. A revert and an expiry are different events: §4.6 gives the glow ten
	seconds and the revert is instant, so a revert that also cleared the glow would delete nine of
	those seconds and with them the window the buntot pagi needs.
]]
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function()
		clearExposed(player.UserId)
	end)

	-- RoundService turns CharacterAutoLoads off and loads explicitly (Step 1.4), so a character can
	-- already exist by the time this service's Start() runs on a live server.
	local character = player.Character

	if character ~= nil then
		watchCharacter(player, character)
	end
end

--[[
	CLEAR THE GLOW BEFORE DROPPING THE HANDLE, and the order is the whole point.

	V05 shipped this as a bare nil on the reasoning that "the entry goes and the health goes with it",
	which is true of the NUMBER and false of the INSTANCE. `clearExposed` destroys the Highlight it
	holds; nilling the entry only forgets it. An exploit audit traced what that leaves:
	`RoundService.onPlayerRemoving` reparents the departing character into `workspace.Husks` as
	`Husk_{userId}` WITH THE GLOW STILL ON IT, and MonsterService is index 29 in SERVICE_ORDER while
	RoundService starts last — so this handler runs FIRST and the husk is built after the handle is
	already gone. All four exits then miss it: the phase-change loop iterates `monsters`, which no
	longer contains the UserId, and the ten-second timer reads a nil entry and declines.

	The result is a labelled, glowing body naming the round's Aswang, standing in the barrio for the
	whole of ENDING. Masked today only because an Aswang leaving ACTIVE aborts the round — a mask
	owned by a different service, which V08's strike gate or any second source of exposure removes
	without touching this file.

	This is `.claude/lessons/absence-is-observable.md` in the direction the lesson does not spell out:
	the leak is not the health value, it is one character in `workspace` carrying an instance no other
	character has.
]]
local function onPlayerRemoving(player: Player)
	clearExposed(player.UserId)

	monsters[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- The C14 seam. Two functions, and the reason they are here rather than in ItemService.
--------------------------------------------------------------------------------

--[[
	Is this player currently in the monster form? (C14)

	SERVER ONLY, AND IT IS NOT A ROLE QUERY. It answers a question about a FORM, and the form is
	already public — `MonsterTransformed` broadcasts it to every client by design. What makes it safe
	to expose is that the caller must already hold a UserId it got from somewhere else; this function
	never enumerates, never returns the Aswang, and returns false for every player who is not
	transformed including the Aswang.

	ItemService ANDs this with `RoundService.GetAswangUserId()` before handing a single boolean to
	`pure/SaltThrow`, so the role never enters the pure module at all.
]]
function MonsterService.IsTransformed(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	return monster ~= nil and monster.Transformed
end

--[[
	IS THIS PLAYER AT OR BELOW `WeakenedThreshold`? (V05, §4.6) One half of V08's strike gate.

	§4.6: the buntot pagi "kills only an Aswang that is both Exposed (glowing from a salt hit) and
	Weakened (at or below 25 health). Against anything else it does nothing." V08 ANDs this with
	`IsExposed` and with `RoundService.GetAswangUserId()`, exactly as `ItemService` already ANDs
	`IsTransformed` with the role before handing a single boolean to a pure module — so the role
	never enters the pure layer at all.

	A PLAYER WITH NO MONSTER STATE IS NOT WEAKENED, and that is the safe direction twice over: a
	survivor was never salted, and an Aswang who has not transformed this round has full health. It
	is also the one that cannot be used as a probe — `false` is what every one of the five players
	returns until somebody lands a salt hit.

	`Weakened` IS A PREDICATE, NOT A `MonsterState` MEMBER, and `Enums.luau:69-71` says why: "it is a
	HEALTH PREDICATE — `health <= Config.Monster.WeakenedThreshold` — not a state, and duplicating it
	as an enum member is how two sources of truth for one fact get out of step." Do not add
	`Enums.MonsterState.Weakened`.
]]
function MonsterService.IsWeakened(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return false
	end

	return MonsterHealth.isWeakened(monster.Health, HEALTH_TUNING)
end

--[[
	FEEDING RESTORES HEALTH (V06, §4.3/§4.6). The seam, declared here and UNWIRED BY V05.

	§4.6: "every kill the Aswang makes heals away one salt hit. That is the tug-of-war the whole
	design turns on." V06 builds the five-second locked feed, validates the corpse, the distance and
	the phase through `pure/FeedRules`, and calls this on completion. V05 owns the number; V06 owns
	the ritual.

	NOT A ROLE QUERY AND NOT AN ENUMERATION, on the same terms as `IsTransformed` above: the caller
	must already hold a UserId it got from somewhere else, and a player with no monster state gets
	`false` rather than an entry created for them.

	CAMOUFLAGE IS NOT RESTORED HERE. §4.3 gives a completed feed two rewards — the heal and the
	camouflage refresh — and V07 owns the second. Splitting them is deliberate: `MonsterService`
	should not grow a charge it cannot yet spend.
]]
function MonsterService.HealFromFeed(userId: number): boolean
	return applyHealthEvent(userId, "FEED")
end

--[[
	A SALT HIT (§4.6, V05). Revert, damage, expose — in that order, and the order is the whole
	correctness of this function.

	IT SHIPPED WRONG ONCE, IN THE OTHER SERVICE, AND AN EXPLOIT AUDIT CAUGHT IT. `ItemService`'s
	first version ran its stun before the revert, so `revert()` wrote `BaseWalkSpeed` (16) over the
	stun's 0 in the same frame — the stun never happened — and four seconds later the stun restored
	the captured TRANSFORMED speed (20) onto a player who was no longer transformed. `WalkSpeed` is
	a replicated property, so any client could poll every character and find the single one reading
	20: a permanent role brand, readable map-wide, with `check:secrecy` green over it. The full story
	is in `ItemService.applyHit`'s header, and the invariant it wrote binds this function too: NO
	PATH ADDED HERE MAY LEAVE A LIVING PLAYER'S HUMANOID PROPERTIES DIFFERENT FROM EVERY OTHER
	LIVING PLAYER'S.

	DAMAGE BEFORE EXPOSE, so the glow's first frame already reads the new health. Exposing first and
	damaging after gives one frame at the old brightness, which is not a leak but is a lie.

	THE REVERT IS `revert()` AND NOT A REIMPLEMENTATION. Everything the salt path needs already
	happens in there: the generation bump that invalidates the in-flight forced-revert timer, the
	`Announced` gate that stops a mid-windup revert broadcasting a transform nobody saw, the
	`LastRevertedAt` stamp that charges the kill cooldown, and the look restoration that resolves
	`AppliedTo` rather than `player.Character`. C04's audit found a second implementation getting the
	last of those four wrong.

	NO GUARD ON WHO CALLS THIS, deliberately: `revert` early-returns for a player who is not
	transformed, `applyHealthEvent` returns false for a player with no state, and `applyExposed`
	does nothing without one. A mistaken call is a no-op rather than a state change. The validation
	that a hit happened at all lives in `ItemService`, next to the request that claimed it.

	DELIBERATELY NOT A KILL AND NOT A `MarkKilled`: §4.6 is counterplay, not a win condition. Salt
	never ends a round, which is why `MonsterHealth.apply` floors it at `WeakenedThreshold`.
]]
function MonsterService.ApplySaltHit(player: Player)
	revert(player)
	applyHealthEvent(player.UserId, "SALT")
	applyExposed(player)
end

--[[
	IS THIS PLAYER INSIDE THE EXPOSED WINDOW? (V05, §4.6) The other half of V08's strike gate.

	SAFE TO EXPOSE FOR THE SAME REASON `IsTransformed` IS: being Exposed is ALREADY PUBLIC — there is
	a Highlight on that character that every client with line of sight can see, which is the entire
	point of §4.6's reveal. This function states nothing a player standing there cannot see, it never
	enumerates, and the caller must already hold a UserId it got from somewhere else.

	A PLAYER WITH NO MONSTER STATE IS NOT EXPOSED — false for every survivor, every round, so it is
	useless as a probe.
]]
function MonsterService.IsExposed(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	return monster ~= nil and monster.Exposed
end

--[[
	THE CORPSE FOLDER (C34). Exposed as the FOLDER rather than as an event, mirroring
	`RoundService.GetHusksFolder` and for the same reason: a caller wants to know when a body arrives,
	and `ChildAdded` on a folder that outlives every round is a subscription that cannot go stale
	between a corpse being created and the next one.

	`CosmeticsService` uses it to play the victim's chosen death effect at the body. THAT IS SAFE
	BECAUSE OF WHAT A CORPSE ALREADY IS: it is the victim's own avatar, anchored, in the open, visible
	to anyone with line of sight. An effect on it is seen by exactly the people who can already see the
	body, and it names the victim no more precisely than their own face does.

	IT IS NOT A DEATH BROADCAST, and the difference matters. Since Amendment A3, `PlayerKilled` goes to
	the VICTIM alone — WHICH of the eight are dead is a death oracle the round deliberately does not
	publish. A local burst at a body somebody is looking at publishes nothing; a map-wide sound or a
	global effect would, so `Config.Cosmetics`'s death numbers are a short local puff and there is no
	remote in that path at all.

	Nil before `Start` has run. Callers connect from their own `Start`, which the bootstrap runs after
	every `Init`, and handle nil rather than assuming.
]]
function MonsterService.GetCorpsesFolder(): Folder?
	return corpses
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
