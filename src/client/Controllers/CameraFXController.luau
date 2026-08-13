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

--[[
	The client's reaction to a kill (C05). Deliberately almost nothing, on the same test the transform
	reaction is held to: the corpse is a real anchored model in the workspace and replicates by itself,
	so if this file were deleted a player would still walk around a corner and find a body.

	IT DOES NOT GUESS THE KILLER, and it must never start. The payload does not name one, and the
	nearest-player inference a client COULD compute is exactly the accusation the game asks a human to
	make out loud through the quick-chat wheel (§4.5). Computing it here would hand every player a
	perfect answer and delete the social half of the game — and it would look like a feature in review.
]]
local function onPlayerKilled(payload: Types.PlayerKilledPayload)
	local isMine = payload.VictimUserId == Players.LocalPlayer.UserId

	print(`[Client] Kill witnessed{if isMine then " (you died)" else ""}`)

	-- TODO(M7): a low thud and a brief vignette when payload.Position is within
	-- Config.Monster.TransformAudioRange of the camera. Distance-gated on THIS side is fine — the
	-- position is already here, so gating buys atmosphere, not secrecy.
end

--[[
	A throw happened somewhere (C14). Renders a burst; concludes nothing.

	`payload.Hit` says salt struck something salt can strike. It does NOT name who, and this handler
	must never start inferring it — the nearest-character-to-Impact computation is one line away and
	would hand every player the answer that §4.6 charges a pouch for. The same warning is on
	`onPlayerKilled` above, for the same reason, and it has held so far.
]]
local function onSaltEffect(payload: Types.SaltEffectPayload)
	print(`[Client] Salt {if payload.Hit then "HIT" else "thrown"} at {payload.Impact}`)

	-- TODO(M7): a white particle burst along Origin -> Impact, and a distinct crackle on Hit.
end

function CameraFXController.Init() end

function CameraFXController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
	Remotes.Get("PlayerKilled").OnClientEvent:Connect(onPlayerKilled)
	Remotes.Get("SaltEffect").OnClientEvent:Connect(onSaltEffect)
end

return CameraFXController
