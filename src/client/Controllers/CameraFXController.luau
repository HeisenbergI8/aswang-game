--!strict
--[[
	CameraFXController — Vignette, shake, proximity heartbeat.

	Milestone: M7. Today it owns one thing: the client's reaction to a transform (C04).

	WHY THE REACTION IS HERE AND NOT IN MonsterService
	--------------------------------------------------
	The server already did the part that matters — it scaled the avatar, tinted it, lit the eyes and
	started the emitter, and all of that REPLICATES on its own. Nothing on this side is required for
	another player to see the monster, which is the property C04 has to have.

	So this controller adds only what is genuinely local: a log line today, and the camera shake and
	heartbeat at M7. If this file were deleted the transform would still be fully visible to everyone.
	That is the test for whether something belongs here.

	IT LEARNS NOTHING IT SHOULD NOT. `MonsterTransformed` carries a Character and a boolean — a fact
	about the world, not a role. A client watching this broadcast can INFER who the Aswang is, which is
	the entire point of a public transform; the server never states it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local CameraFXController = {}

-- TODO(M7): heartbeat intensity scales with monster proximity.
-- Partial information is scary; total darkness is just confusing.

local function onTransformed(payload: Types.MonsterTransformedPayload)
	local character = payload.Character

	-- Deliberately does NOT name the player. The character is right there in the world for anyone with
	-- line of sight; printing a name would put into every client's log something the game asks players
	-- to work out by looking, including for players who were nowhere near it.
	local isMine = character == Players.LocalPlayer.Character

	print(
		`[Client] {if payload.Transformed then "TRANSFORM" else "revert"} witnessed{if isMine
			then " (yours)"
			else ""}`
	)

	-- TODO(M7): shake the camera and swell the heartbeat when this fires within TransformAudioRange.
end

function CameraFXController.Init() end

function CameraFXController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
end

return CameraFXController
