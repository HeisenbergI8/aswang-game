--!strict
--[[
	REVIEW — src/server/Services/GhostService.luau:137-158, 694-716

	The closest existing model for QuickChatService: a service that takes a rate-limited request,
	decides server-side, and delivers to a FILTERED audience. Both halves are worth copying, and one
	comment in it corrected a mistake in this plan's first draft.
]]

--------------------------------------------------------------------------------
-- GhostService.luau:137-156 — the filtered broadcast
--------------------------------------------------------------------------------

local function broadcastRoster()
	local userIds: { number } = {}

	for _, player in Players:GetPlayers() do
		if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
			table.insert(userIds, player.UserId)
		end
	end

	local payload: Types.GhostRosterPayload = { UserIds = userIds }

	for _, player in Players:GetPlayers() do
		-- THE TEST THAT MATTERS, and it is re-read per recipient rather than cached from the loop
		-- above: a player who died between building the list and sending it must still be excluded
		-- from neither, and one who is alive must receive nothing at all.
		if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
			rosterRemote:FireClient(player, payload)
		end
	end
end

-- IMPORTANT: this is the exact shape QuickChatService.broadcast copies — a `FireClient` loop with the
-- state test AT THE FIRE SITE, never `FireAllClients`. The reason is in Remotes.luau:57-70:
-- `check:secrecy` reads payload fields and call shapes, and a loop over the wrong list is textually
-- identical to a loop over the right one. The check script is not what keeps this correct.
--
-- NOTE the re-read per recipient. C25 inherits this: `broadcast` calls `GetPlayerState` inside the
-- loop rather than caching it, which is what makes "the sender died in the same frame" resolve in the
-- safe direction instead of the cached one.

--------------------------------------------------------------------------------
-- GhostService.luau:694-716 — the guarded handler, and the verdict rule
--------------------------------------------------------------------------------

--[[
	THE RATE LIMIT IS INLINE AND FIRST, the shape MonsterService's handlers established and the one
	`check-ratelimit.mjs` looks for — it matches an `AntiCheat*.Consume` within 1200 characters of
	the `.OnServerEvent:Connect(`, so a handler limited somewhere else reads as unguarded.
]]
Remotes.Get("RequestGhostSpook").OnServerEvent:Connect(function(player: Player)
	if not AntiCheatService.Consume(player, "RequestGhostSpook") then
		return
	end

	-- NO ARGUMENTS, and that is the security design — the same shape `RequestTimingStop` uses. The
	-- server resolves the position from the caller's own character and the budget from its own
	-- table. There is no argument in which a client could name a place, a light, or a count.

	if verdict ~= "OK" then
		-- LOGGED, NEVER ECHOED. `NOT_GHOST` returned to a client is a state oracle: fire it as a
		-- living player and the refusal confirms you are alive, fire it after a suspected death
		-- ...

-- IMPORTANT — THIS COMMENT CORRECTED THIS PLAN. An early draft had QuickChatService return
-- `NO_TARGET_IN_SIGHT` to the sender so the client could show "nobody in sight". That is precisely
-- the state oracle described here: a verdict a client can read is a probe, and
-- `NOT_ALLOWED_FOR_STATE` echoed back would let a player read their own aliveness off an error code
-- — Amendment A3's death signal rebuilt out of a refusal.
--
-- The plan now echoes NOTHING. The sender learns the result by receiving their own broadcast like
-- everyone else: a message that appears succeeded, one that does not, did not. No remote needed, and
-- an absence carries no detail to probe with.
--
-- NOTE — "there is no argument in which a client could name a place, a light, or a count" is the
-- sentence C25's one-argument remote is modelled on. `RequestQuickChat` carries a phrase id and
-- nothing else for the same reason.
