--!strict
--[[
	SmokeController — the cloud, and the one line the Aswang reads about its own disguise. (V07, §4.3)

	OWNS NO TRUTH, and here that is a security property rather than a slogan. The smoke's line-of-sight
	break is resolved on the SERVER — `MonsterService.SmokeBlocks` over `pure/CamouflageRules
	.smokeBlocks`, consulted by the kill path and the throw path — so a player who deletes this
	emitter, drops to minimum graphics, or never receives the payload plays under exactly the same
	rules as everyone else. The particles are what the decision LOOKS like, never what makes it.

	IT DRAWS A CLOUD FOR EVERYONE WHO RECEIVES ONE, AND THE SERVER DECIDES WHO THAT IS. There is no
	distance filter in this file and there must not be: a client-side filter would mean every client
	received every burst, which is the live monster-position feed `Remotes.luau` refuses.

	THE CAMOUFLAGE HALF IS ONE PLAYER'S, LIKE `FeedController`'S FEED. Every client loads this file and
	connects the handler; four of five never receive a `CamouflageUpdate`, so the branch never runs, and
	nothing about that is observable to anyone but themselves. The asymmetry that WOULD leak is on the
	server side and there is none — `CamouflageUpdate` is FireClient to the requester, never a
	broadcast, so no client can time or count another's hides.

	NO HUD AND NO CHARGE METER, EVEN FOR THE ASWANG. §4.6's rule that "a health value attached to a
	player is the reveal" generalises: the moment a charge counter exists on screen, a screen recording
	of an Aswang's client is a document of the camouflage system, and a streamer's overlay is a
	permanent one. The feedback is `OnboardingController.ShowLine`, which `SearchController`,
	`FeedController` and `TeachingService` all already use this way.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OnboardingController = require(script.Parent.OnboardingController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local SmokeController = {}

--[[
	ONE LINE PER VERDICT, AND THE COPY IS THE DELIVERABLE (V07, §4.3).

	`CAMO_NOT_REVEALED` says what UNLOCKS the ability rather than what refused it, because it is the
	only refusal in this game for a rule the player has never been told — §4.3's gate is invisible from
	inside a round, and "camouflage is locked" would read as a bug.

	THE THREE STATE VERDICTS SHARE A LINE. Wrong phase, already hiding, and not transformed are all
	things the player can see for themselves by looking at their own screen; three distinct lines would
	be three ways of saying "look down".

	`CAMO_NO_SLOT` TELLS THE ASWANG SOMETHING TRUE ABOUT THE WORLD, and that is safe twice over: it is
	fired to the requester alone about its own refused action, and the ambient population it describes
	is standing in the barrio where every player can count it.
]]
local function lineFor(verdict: Types.CamouflageVerdict, form: Types.CamouflageForm?): string
	if verdict == "CAMO_OK" then
		return if form ~= nil then `You are a {string.lower(form)}.` else "You are hidden."
	elseif verdict == "CAMO_EXITED" then
		return "You step out."
	elseif verdict == "CAMO_NOT_REVEALED" then
		return "They have to see you first."
	elseif verdict == "CAMO_NO_CHARGE" then
		return "You need to feed again."
	elseif verdict == "CAMO_WITNESSED" then
		return "Someone is watching."
	elseif verdict == "CAMO_NO_SLOT" then
		return "There is nothing left to hide as."
	end

	return "Not now."
end

local function onCamouflageUpdate(payload: Types.CamouflageUpdatePayload)
	OnboardingController.ShowLine(lineFor(payload.Verdict, payload.Form))
end

--[[
	DRAW THE CLOUD (V07, §4.3). §5'S MOBILE BUDGET, SPENT DELIBERATELY.

	ONE EMITTER AND NO LIGHT. §5's cap is about lights and particles, and `PerformanceController`
	already enforces the light one; a `PointLight` inside smoke is the cheapest-LOOKING and most
	expensive thing available here, so there is none.

	A BURST `:Emit(n)` RATHER THAN A SUSTAINED `Rate`. The cloud is an event, not a fixture — a rate
	would keep spawning particles for the whole lifetime and leave the tail of them alive past the
	`Destroy`. One emission, one lifetime, gone.

	`Debris` RATHER THAN A `task.delay`, so the part is removed even if this script is unloaded
	mid-cloud, and nothing accumulates across a round.

	`Duration` AND `Radius` COME FROM THE PAYLOAD, NOT FROM CONFIG, even though Config replicates. The
	server is the authority on how long ITS burst lasts; a client computing the lifetime from Config
	would draw a stale cloud for four seconds after a Config change the server had already applied.

	WHETHER PARTICLES VISUALLY OCCLUDE ANYTHING IS NOT DEPENDED ON. The mechanic never asks — the
	server decided line of sight before any of this existed. If the cloud looks thin, that is a texture
	and density problem with no gameplay consequence.
]]
local function onSmokeBurst(payload: Types.SmokeBurstPayload)
	local part = Instance.new("Part")
	part.Name = "SmokeBurst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one -- config-ok: an anchor point for the emitter, not a volume
	part.CFrame = CFrame.new(payload.Position)
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0 -- config-ok: burst-only; the emission below is the whole effect
	emitter.Lifetime = NumberRange.new(payload.Duration)
	emitter.Size = NumberSequence.new(payload.Radius)
	emitter.Transparency = NumberSequence.new(Config.Monster.SmokeTransparency)
	emitter.Speed = NumberRange.new(Config.Monster.SmokeDriftSpeed)
	emitter.LightEmission = 0 -- config-ok: §5's budget — smoke does not glow
	emitter.Parent = part

	emitter:Emit(Config.Monster.SmokeParticleCount)

	Debris:AddItem(part, payload.Duration)
end

function SmokeController.Init() end

function SmokeController.Start()
	Remotes.Get("CamouflageUpdate").OnClientEvent:Connect(onCamouflageUpdate)
	Remotes.Get("SmokeBurst").OnClientEvent:Connect(onSmokeBurst)
end

return SmokeController
