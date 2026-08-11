--!strict
-- Review of src/client/Controllers/CameraFXController.luau — where Step 4.6 lands.
-- Excerpts only.

-- src/client/Controllers/CameraFXController.luau:7-15
--[[
	WHY THE REACTION IS HERE AND NOT IN MonsterService
	The server already did the part that matters ... and all of that REPLICATES on its own. Nothing on
	this side is required for another player to see the monster, which is the property C04 has to have.

	So this controller adds only what is genuinely local ... If this file were deleted the transform
	would still be fully visible to everyone. That is the test for whether something belongs here.
]]
-- IMPORTANT: the kill passes the same test. The corpse is an anchored model in the workspace and
-- replicates by itself, so deleting this file would still leave a player walking round a corner into a
-- body. That is why Step 4.6 adds a log line and a TODO and nothing else.

-- src/client/Controllers/CameraFXController.luau:17-19
--[[
	IT LEARNS NOTHING IT SHOULD NOT. `MonsterTransformed` carries a Character and a boolean — a fact
	about the world, not a role. A client watching this broadcast can INFER who the Aswang is, which is
	the entire point of a public transform; the server never states it.
]]
-- IMPORTANT: PlayerKilled is the OPPOSITE case and the distinction has to be kept. The transform is
-- public by design; the kill's author is not. The inference a client could compute here — "who was
-- within KillRange of Position when this fired" — is exactly the accusation §4.5's quick-chat wheel
-- asks a human to make out loud. Computing it in this file would look like a feature in review and
-- would delete the social half of the game.

-- src/client/Controllers/CameraFXController.luau:34-49
local function onTransformed(payload: Types.MonsterTransformedPayload)
	local character = payload.Character

	-- Deliberately does NOT name the player. The character is right there in the world for anyone with
	-- line of sight; printing a name would put into every client's log something the game asks players
	-- to work out by looking, including for players who were nowhere near it.
	local isMine = character == Players.LocalPlayer.Character
	-- NOTE: Step 4.6's onPlayerKilled copies this shape exactly — compare against LocalPlayer, print a
	-- bare fact, name nobody. The victim IS named in the payload (VictimUserId), and that is fine: the
	-- victim's own body is missing from the world a frame later.

	print(
		`[Client] {if payload.Transformed then "TRANSFORM" else "revert"} witnessed{if isMine
			then " (yours)"
			else ""}`
	)

	-- TODO(M7): shake the camera and swell the heartbeat when this fires within TransformAudioRange.
end

-- src/client/Controllers/CameraFXController.luau:51-55
function CameraFXController.Init() end

function CameraFXController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
	-- NOTE: Step 4.6 adds one line here. `.OnClientEvent` on a DOWN event from client code is the
	-- direction check-remotes.mjs requires (its self-test case at :170); getting it backwards on the
	-- client does not error, it hangs on WaitForChild forever.
end
