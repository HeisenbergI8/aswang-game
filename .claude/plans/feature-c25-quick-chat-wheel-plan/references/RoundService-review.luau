--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau:61-89, 780

	READ-ONLY for C25. Three queries and one event are the entire surface QuickChatService touches;
	nothing in this plan writes to RoundService.
]]

RoundService.PhaseChanged = Instance.new("BindableEvent")

function RoundService.GetPhase(): RoundPhase
	return state.Phase
end

-- Deliberately NOT exposed to any client-facing code path.
function RoundService.GetAswangUserId(): number?
	return state.AswangUserId
end

function RoundService.GetPlayerState(player: Player): PlayerState
	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
end

--[[
	IMPORTANT — `GetAswangUserId` IS THE FUNCTION C25 MUST NEVER CALL, and it is worth naming the
	temptation rather than trusting that nobody feels it. There is a plausible-sounding feature here:
	suppress the accusation phrase, or alter it, when the accused IS the Aswang. Any such branch is a
	timing oracle — the server behaving differently for one target than another is observable, and it
	is observable to the accuser, who is the person best placed to exploit it. QuickChatService
	requires this module for three functions and this is not one of them.

	NOTE — `GetPlayerState` DEFAULTS TO LOBBY for an unknown UserId. That is the safe direction for
	C25: an unknown player is not ALIVE and not GHOST, so the plan's Step 3.2 state gate refuses them
	with NOT_ALLOWED_FOR_STATE rather than falling through. The gate is written as an allowlist of two
	states for exactly this reason.

	IMPORTANT — LOBBY is `isLivingSide` per `pure/GhostChat`, so a LOBBY player would RECEIVE a living
	player's quick chat if one were somehow sent during ACTIVE. That is correct and matches text chat.
	It is the SENDING side C25 closes: the plan refuses a LOBBY sender explicitly, because a phase
	gate alone would admit a player who joined mid-round and has not yet been marked SPECTATOR.

	NOTE — `PhaseChanged` is a BindableEvent, subscribed with `RoundService.PhaseChanged.Event:Connect`
	(TaskService.luau:1683, ItemService.luau:694). QuickChatService uses the same idiom and, per spec
	§6.4, never calls setPhase. There is no setPhase in this file's public surface to call.
]]

--------------------------------------------------------------------------------
-- RoundService.luau:780 — the cycle warning
--------------------------------------------------------------------------------

	-- ... it is a require cycle: TaskService needs GetPlayerState, GetPhase and SetTasksCompleted
	-- from ...

-- IMPORTANT: a require cycle has already been hit once in this repo, between RoundService and
-- TaskService. QuickChatService requires RoundService, and RoundService must never require it back.
-- The arrow is safe as planned — nothing in RoundService needs anything from the wheel — but it is
-- worth re-checking at implementation time rather than assuming, which is why it is in the plan's
-- Phase 3 issues.

--[[
	NOTE — SERVICE_ORDER in init.server.luau puts RoundService LAST, "the state machine drives
	everything, so it starts last". QuickChatService is placed before it, which means the handler is
	attached before any phase transition can occur. That ordering is not decorative for this chunk: a
	quick chat arriving in the window between `Start` and the first phase change would find
	`GetPhase()` at IDLE and be refused, which is correct but would look like a broken button to the
	first player who pressed it.

	QUESTION — resolved: does QuickChatService need `GetSecondsRemaining` or `IsGateOpen`? No. The
	wheel has no timing element and no gate interaction. Three functions and one event is the whole
	dependency, and keeping it that small is what makes the read-only claim checkable.
]]
