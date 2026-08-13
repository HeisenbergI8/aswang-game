--!strict
--[[
	REVIEW — src/client/Controllers/CameraFXController.luau (78 lines)

	Excerpted ranges:
	  · src/client/Controllers/CameraFXController.luau:51-69  onPlayerKilled and its warning
	  · src/client/Controllers/CameraFXController.luau:73-76  Start

	Read for one reason: it is the ONLY consumer of `PlayerKilled` in `src/client/`, which is what makes
	Decision 1's Step 1.5 a one-line change with no client-side follow-on.
]]

-- src/client/Controllers/CameraFXController.luau:51-59
--	The client's reaction to a kill (C05). Deliberately almost nothing, on the same test the transform
--	reaction is held to: the corpse is a real anchored model in the workspace and replicates by itself,
--	so if this file were deleted a player would still walk around a corner and find a body.
--	IT DOES NOT GUESS THE KILLER, and it must never start... Computing it here would hand every player a
--	perfect answer and delete the social half of the game — and it would look like a feature in review.
-- IMPORTANT THE ARGUMENT THAT MAKES STEP 1.5 SAFE, made by this file about itself: the corpse is the
--      real signal and this remote is decoration. If that is true — and it is — then the remote does not
--      need to reach anyone who is not the victim.
-- NOTE It is also the argument Step 4.4's `onSaltEffect` copies almost word for word: the
--      nearest-character-to-Impact computation is one line away and would hand every player the answer
--      §4.6 charges a pouch for.

-- src/client/Controllers/CameraFXController.luau:61-69
local function onPlayerKilled(payload: Types.PlayerKilledPayload)
	local isMine = payload.VictimUserId == Players.LocalPlayer.UserId

	print(`[Client] Kill witnessed{if isMine then " (you died)" else ""}`)

	-- TODO(M7): a low thud and a brief vignette when payload.Position is within
	-- Config.Monster.TransformAudioRange of the camera. Distance-gated on THIS side is fine — the
	-- position is already here, so gating buys atmosphere, not secrecy.
end
-- IMPORTANT NO CHANGE IS NEEDED HERE AFTER STEP 1.5, and that is worth stating rather than assuming.
--      `isMine` simply becomes the only branch this function ever takes, because the only recipient is
--      the victim. Nothing breaks, nothing dangles.
-- IMPORTANT THE M7 TODO IS THE PART THAT CHANGES MEANING. "the position is already here, so gating buys
--      atmosphere, not secrecy" was TRUE while the remote was a broadcast and is now the opposite: the
--      position is here only for the person who died, so there is no bystander to gate. The vignette
--      becomes a first-person death effect, which is what it should have been — but M7 must not read this
--      comment and conclude it may play a thud for a distant witness, because after Step 1.5 there is no
--      distant witness on this remote to play one for.
-- QUESTION Should Step 1.5 rewrite this TODO? It is a client-side comment about a server-side decision
--      that has changed underneath it. Not in scope for Phase 1's diff, but the first M7 reader will be
--      misled by it. Raised here rather than silently left.

-- src/client/Controllers/CameraFXController.luau:73-76
function CameraFXController.Start()
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)
	Remotes.Get("PlayerKilled").OnClientEvent:Connect(onPlayerKilled)
end
-- NOTE THE FILE STEPS 4.4 AND 6.5 EXTEND. It already owns world-effect reception for two remotes, so
--      `SaltEffect` belongs here rather than in a new controller. `GhostRoster` is a judgement call — if
--      ghost visibility grows past a dozen lines it wants its own `GhostController`, and the plan says so
--      rather than deciding for the implementer.
-- IMPORTANT A living client CONNECTS to `GhostRoster` and simply never receives it. That is correct and
--      must stay that way: a controller that renders off its own `YourState` rather than off "I received
--      this" is one that misbehaves visibly, not silently, the day the server's audience logic is wrong.
