--!strict
--[[
	AudioController — ambient loops, stingers, the heartbeat.

	Milestone: M8 owns the real audio pass (C29), where §14.3's point stands: audio is half of horror
	and it is free. Today this file owns one cue — the transform stinger (§4.3).

	NO ASSET ID YET, AND THAT IS DELIBERATE. Sourcing audio is C29 with the `asset-pipeline` skill, and
	inventing an ID here would either 404 at runtime or ship somebody else's sound with no licence
	trail. So the Sound instance is created, positioned and RANGED correctly, and its SoundId is left
	empty: the spatial behaviour that C04 cares about is testable now, and C29 fills in one field.

	WHY THE SOUND IS PARENTED TO THE TRANSFORMING CHARACTER'S HEAD
	--------------------------------------------------------------
	`Config.Monster.TransformAudioRange` (40 studs) is a fact about WHERE the transform can be heard,
	and Roblox's own rolloff is what enforces it. A sound played at the listener with a manual distance
	check would be a second, wrong answer to a question the engine already answers — and it would be
	wrong in the direction that matters, since it would ignore the geometry between the two players.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local AudioController = {}

local STINGER_NAME = "AswangTransformStinger"

local function playStinger(character: Model)
	local head = character:FindFirstChild("Head")

	if head == nil or not head:IsA("BasePart") then
		return
	end

	local existing = head:FindFirstChild(STINGER_NAME)

	if existing ~= nil then
		existing:Destroy()
	end

	local sound = Instance.new("Sound")
	sound.Name = STINGER_NAME
	-- TODO(C29): a Creator Store transform stinger. Empty until then — see the header.
	sound.SoundId = ""
	sound.RollOffMaxDistance = Config.Monster.TransformAudioRange
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = head

	sound:Play()

	-- Local-only instance on a replicated character, so it is cleaned up here rather than left for the
	-- server's FX folder teardown to find.
	task.delay(Config.Monster.TransformTime + Config.Monster.RevertTime, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

local function onTransformed(payload: Types.MonsterTransformedPayload)
	-- Only the transform, not the revert. A revert stinger would tell every client the exact moment a
	-- monster became a person again, which is information a witness should get by looking.
	if payload.Transformed then
		playStinger(payload.Character)
	end
end

function AudioController.Init() end

function AudioController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
end

return AudioController
