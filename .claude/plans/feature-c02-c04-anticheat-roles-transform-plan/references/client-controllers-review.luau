--!strict
--[[
	REVIEW — the client side, read in full:
	  src/client/init.client.luau
	  src/client/Controllers/{UIController, CameraFXController, AudioController, InputController,
	                          QuickChatController}.luau

	All five controllers are ~18-line stubs with an Init/Start pair and TODOs. No logic to preserve.
]]

-- init.client.luau — IMPORTANT: no change is needed here. It already requires and starts every name in
-- CONTROLLER_ORDER, and all three controllers this plan touches are in it, in a usable order:
local CONTROLLER_ORDER = {
	"AudioController",
	"CameraFXController",
	"UIController", -- before InputController, which requires it for GetMyRole()
	"QuickChatController",
	"InputController",
}

-- NOTE the same pcall-and-warn pattern as the server bootstrap, with the same consequence: a
-- controller that errors in Start() produces one warn line and silently never runs.

--[[
	IMPORTANT — the existing C01 smoke-test listeners at the bottom of init.client.luau are the model
	for how this plan's listeners are written, and one of them shows the pattern worth copying:

		local lastSnapshotLine: string? = nil
		Remotes.Get("RoundSnapshot").OnClientEvent:Connect(function(snapshot: Types.ClientRoundSnapshot)
			...
			if line == lastSnapshotLine then return end   -- log only on change
		end)

	"The snapshot arrives several times a second, so log only when something a player would notice has
	 actually changed. A per-tick print buries every other line in the output window, which is where you
	 will be looking when something breaks."

	MonsterTransformed fires at most twice per transform, so no throttling is needed for it.
]]

-- NOTE the C01 listener already reads `snapshot.YourState`, so the client is told its OWN PlayerState.
-- That is not a leak (it is the receiver's own state) and it is NOT what InputController gates on —
-- the transform bind gates on UIController.GetMyRole(), from the client's own RoleAssigned.

-- UIController.luau, in full apart from boilerplate:
--   TODO(M7): mobile-first layout. Readable one-handed on a phone.
--   TODO(M7): end screen is where the cosmetic shop is offered (spec §8.4).
-- IMPORTANT: this plan puts the role intro here and adds GetMyRole(). It is now the ONLY place on any
-- client where a role is stored. The header the plan writes says so, because the next person to open
-- this file will be building a HUD and will need to know.

-- CameraFXController.luau:
--   TODO(M7): heartbeat intensity scales with monster proximity.
--   -- Partial information is scary; total darkness is just confusing.

-- AudioController.luau:
--   TODO(M8): use Roblox Creator Store audio (licensed, free to use in experiences).
--   -- Audio is half of horror and costs nothing.
-- NOTE this is why the transform stinger ships with no SoundId: there is no audio in this project
-- until C29, which loads the asset-pipeline skill first.

-- InputController.luau:
--   TODO(M7): on-screen buttons for mobile (~60% of players).
-- NOTE this plan adds a KEYBOARD bind only, because C04's verification needs a human able to press
-- something on one of two clients. The mobile button is C18's, and gating it on the client's own
-- RoleAssigned is called out explicitly in BUILD-PLAN's C18 entry.
