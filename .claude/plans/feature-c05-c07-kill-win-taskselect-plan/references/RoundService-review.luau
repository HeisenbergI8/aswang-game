--!strict
-- Review of src/server/Services/RoundService.luau — touched by Phases 1, 4 and 5.
-- Excerpts only.

-- src/server/Services/RoundService.luau:38-49 — the server-only state table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	-- IMPORTANT: THE SECRET. Phase 5's `livingSurvivorCount()` reads it, which is exactly why that
	-- helper cannot live in a pure module and why its RESULT (a number) is the only thing that crosses
	-- into WinConditions.
	AswangUserId = nil :: number?,
	TasksCompleted = 0,
	GateOpen = false,
	-- NOTE: Phase 5 adds `DealtInSurvivors` here — a snapshot taken in enterStarting, never updated.
	PlayerStates = {} :: { [number]: PlayerState },
}

-- src/server/Services/RoundService.luau:77-96
function RoundService.GetPlayerState(player: Player): PlayerState
	-- IMPORTANT: unknown UserIds default to LOBBY. Combined with an ALLOWLIST (`== ALIVE`) this fails
	-- safe; with a denylist (`~= SPECTATOR`) an unknown player would be treated as killable. This is the
	-- "belt-and-braces" reason the BUILD-PLAN warning gives, and it is real.
	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
end

local function aliveCount(): number
	-- NOTE: counts ALIVE only, and includes the Aswang. This is what the client snapshot carries.
	-- Phase 5 adds a separate `livingSurvivorCount()` that excludes the Aswang; the two differ by
	-- exactly one during a round, which is itself information and is why the survivor count is never
	-- broadcast.
	local count = 0
	for _, playerState in state.PlayerStates do
		if playerState == Enums.PlayerState.Alive then
			count += 1
		end
	end
	return count
end

-- src/server/Services/RoundService.luau:108-113
local function setAllPlayerStates(newState: PlayerState)
	table.clear(state.PlayerStates)
	for _, player in Players:GetPlayers() do
		state.PlayerStates[player.UserId] = newState
	end
	-- IMPORTANT: Phase 1 appends a SECOND loop here rather than calling applyBodyRule inside this one.
	-- applyBodyRule reads GetPlayerState, and a half-written table answers LOBBY (the default above)
	-- for everyone not yet assigned — which would spawn a body for a player about to become SPECTATOR.
end

-- src/server/Services/RoundService.luau:150-161 — the client's entire view.
-- NOTE: `AlivePlayerCount` now MOVES when someone is killed, and `YourState` starts reporting GHOST.
-- Both are existing fields carrying existing meanings; this plan adds no field to the snapshot.

-- src/server/Services/RoundService.luau:223-236 — where the round is dealt.
local function enterStarting()
	state.RoundNumber += 1
	setAllPlayerStates(Enums.PlayerState.Alive)

	-- IMPORTANT: BEFORE setPhase, deliberately. Phase 5's DealtInSurvivors snapshot must go AFTER this
	-- line — "survivors" means "dealt in and not the Aswang", and the Aswang does not exist until here.
	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())

	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
end

-- src/server/Services/RoundService.luau:251-266 — the guard that makes a second win condition safe.
local function enterEnding(result: Types.RoundResult)
	if state.Phase == Enums.RoundPhase.Ending then
		-- IMPORTANT: this is why Phase 5 can add a win path without racing the sunrise timer, and why
		-- C11's survivor win will be safe too. The comment already names C06/C11 as the reason it
		-- exists. An unconditional warn, not gated on VerboseLogging, because a dropped result is a
		-- fault.
		warn(`[RoundService] Discarded a late round result ({result}) — already ENDING.`)
		return
	end

-- src/server/Services/RoundService.luau:286-291
function RoundService.EndRound(result: Types.RoundResult)
	-- IMPORTANT: guarded on ACTIVE here, inside this service. Phase 5 calls this from MarkKilled, which
	-- keeps `setPhase` at exactly one caller and keeps the win check a REQUEST rather than a write.
	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end
	enterEnding(result)
end

-- src/server/Services/RoundService.luau:334-368 — the disconnect handler.
local function onPlayerRemoving(player: Player)
	state.PlayerStates[player.UserId] = nil
	-- IMPORTANT: Phase 4's MarkKilled can re-create this key if the victim disconnects between the
	-- raycast and the commit. Logged as a Medium issue in the plan; the alive count is briefly wrong
	-- until the next setAllPlayerStates.

	-- NOTE the absence of a headcount check here. Spec §6.4: a round that drops below MinPlayers
	-- FINISHES ... Ending the round on a disconnect would make quitting a way to void a round you were
	-- losing, and would read as an Aswang win every time someone's connection dropped.
	-- IMPORTANT: this comment is the precedent for Phase 5's decision to evaluate the attrition win ONLY
	-- on a kill. A disconnect reduces the living survivor count identically to a kill; ending the round
	-- for it reintroduces exactly the exploit this paragraph refuses.
end

-- src/server/Services/RoundService.luau:390-421
function RoundService.Start()
	-- IMPORTANT: Phase 1 puts `Players.CharacterAutoLoads = false` at the TOP of this function, before
	-- the PlayerAdded connection. Roblox spawns a character as soon as a player joins while the flag is
	-- true, so the flag must be off before anyone can arrive.
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onServerClosing)

	-- NOTE: connect-then-backfill, and onPlayerAdded is idempotent. Phase 4's MonsterService copies this
	-- shape for its Humanoid.Died watch.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end
