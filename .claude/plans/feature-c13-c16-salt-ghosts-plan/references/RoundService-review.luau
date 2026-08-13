--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau (1017 lines)

	Excerpted ranges:
	  · src/server/Services/RoundService.luau:40-58     the server-only state table
	  · src/server/Services/RoundService.luau:104-123   applyBodyRule's six call sites
	  · src/server/Services/RoundService.luau:396-404   aliveCount — the snapshot's source
	  · src/server/Services/RoundService.luau:437-448   setAllPlayerStates, and why dealtIn cannot live in it
	  · src/server/Services/RoundService.luau:485-504   buildSnapshot and broadcastSnapshot
	  · src/server/Services/RoundService.luau:623-644   enterStarting — where the dealt-in set is frozen
	  · src/server/Services/RoundService.luau:734-796   MarkKilled
	  · src/server/Services/RoundService.luau:865-951   onPlayerAdded and onPlayerRemoving

	Phase 1 and Phase 5 both cut into this file. It is the most-patched file in the repo — its own
	comments say five patches across four review rounds — so every edit below is placed against an
	existing comment that explains why the surrounding code is shaped as it is.
]]

-- src/server/Services/RoundService.luau:55-57
	-- Keyed by UserId. LOBBY between rounds, ALIVE for everyone dealt into a round, SPECTATOR for
	-- anyone who joined after it started (spec §6.4), GHOST once C15 lands.
	PlayerStates = {} :: { [number]: PlayerState },
-- NOTE "GHOST once C15 lands" — this plan is that chunk. GHOST already occurs (MarkKilled writes it at
--      C05); what C15 adds is a ghost who can DO anything.

-- src/server/Services/RoundService.luau:104-112
--	SIX CALL SITES, all in this file. The count is spelled out because this comment claimed three for
--	two rounds after it had stopped being true, and stale comments about who touches a player's body
--	have already caused two real bugs on this surface
-- IMPORTANT `applyBodyRule` is THE single owner of LoadCharacterAsync. Phase 6's GhostService must not
--      become a seventh call site — it watches CharacterAdded and DRESSES the rig; it never loads and
--      never destroys. Two owners of a player's body is how this file earned its five patches.

-- src/server/Services/RoundService.luau:396-404
local function aliveCount(): number -- counts PlayerStates == ALIVE
-- NOTE Step 1.4 KEEPS this function and removes only its use in buildSnapshot. It is still read at line
--      ~795 in a VerboseLogging print that never crosses to a client. The function is not the leak; the
--      send was.

-- src/server/Services/RoundService.luau:437-438
local function setAllPlayerStates(newState: PlayerState)
	table.clear(state.PlayerStates)
-- IMPORTANT THIS `table.clear` IS WHY THE DEALT-IN SET NEEDS ITS OWN TABLE (Step 5.3, and BUILD-PLAN's
--      first completeness condition). A `DealtIn = true` marker living inside PlayerStates would be
--      erased by the very transition that should be setting it — enterStarting calls this immediately
--      before freezing the roster.

-- src/server/Services/RoundService.luau:485-496
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
	return {
		-- ...
		AlivePlayerCount = aliveCount(),
		YourState = RoundService.GetPlayerState(player),
	}
end
-- IMPORTANT DECISION 1's target. Pushed every SnapshotInterval (0.5s) plus an immediate extra push from
--      MarkKilled — a sub-second global death signal. Step 1.3 removes the field from the type and Step
--      1.4 removes it here.
-- NOTE `check:secrecy` cannot see this. The field carries no role token and no player name; it is a
--      count, and a count is the shape no text tripwire in this repo matches.

-- src/server/Services/RoundService.luau:498-499
-- Per player, not FireAllClients: YourState differs between a survivor and a mid-round spectator,
-- and a broadcast could only ever carry one of them.
-- NOTE Per-player construction is what makes the MarkKilled push weak rather than harmless after Phase 1:
--      the six other clients receive a payload identical to their next scheduled one. Only the TIMING
--      differs, and timing alone is a much weaker signal than contents. Recorded in Follow Up 3.

-- src/server/Services/RoundService.luau:623-643
local function enterStarting()
	setAllPlayerStates(Enums.PlayerState.Alive)
	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())
	state.DealtInSurvivors = livingSurvivorCount()
-- NOTE Step 5.3 inserts the dealtIn population between setAllPlayerStates and AssignRoles: AFTER the
--      state table is written (so it reads a complete table) and BEFORE the draw (so nothing about the
--      set can depend on who the Aswang is).
-- IMPORTANT `dealtInUserIds()` is NOT the same thing and cannot be reused. It is a sorted array rebuilt
--      from PlayerStates on demand for RoleDraw — which is exactly what stops working the moment somebody
--      disconnects, because onPlayerRemoving deletes their entry.

-- src/server/Services/RoundService.luau:743-745
	state.PlayerStates[player.UserId] = Enums.PlayerState.Ghost

	applyBodyRule(player)
-- IMPORTANT AFTER PHASE 6 THIS RESOLVES TO GRANT, NOT REVOKE. `applyBodyRule`'s default cause is
--      PHASE_CHANGE, and BodyTransitions.mayHaveBody will admit GHOST — so the victim would be respawned
--      as a ghost in the same frame the corpse is made. That may be exactly right, or may want an
--      explicit "KILLED" cause so the spawn is deliberate.
-- QUESTION Read this call before implementing Step 6.2. Line ~144 pins the convention that the state
--      passed is the POST-transition one, which is why the cell that fires is GHOST's and not ALIVE's.

-- src/server/Services/RoundService.luau:788-790
	-- Immediately, rather than waiting up to SnapshotInterval: AlivePlayerCount and the victim's own
	-- YourState both just changed, and the victim's HUD is the one screen guaranteed to be looked at.
	broadcastSnapshot()
-- NOTE Half of this comment dies with the field. Step 1.4 replaces it; the victim half stays true.

-- src/server/Services/RoundService.luau:823-831
	if
		WinConditions.aswangWinsByKills({
			AswangKills = state.AswangKills,
-- IMPORTANT Amendment A1's structural fix: nothing but a validated kill writes AswangKills. Step 5.5's
--      disconnect record must NOT touch it, and must not decrement DealtInSurvivors either — that was
--      the third of three failed patches and it was arithmetically inert above four survivors.

-- src/server/Services/RoundService.luau:865-871
local function onPlayerAdded(player: Player)
	state.PlayerStates[player.UserId] = if isRoundUnderway()
		then Enums.PlayerState.Spectator
		else Enums.PlayerState.Lobby
-- IMPORTANT DECISION 2's TARGET, AND A LIVE EXPLOIT. Every mid-round arrival is SPECTATOR, including a
--      player who was ALIVE sixty seconds ago. SPECTATOR is uncounted by aliveCount, bodiless under
--      BodyTransitions, and — since C05 — UNKILLABLE (KillValidation requires TargetState == "ALIVE").
--      Hear the transform, Alt-F4, return: invulnerable observer for the rest of the round, free and
--      repeatable. Step 5.4 replaces this with RejoinResolve.stateFor(state.Phase, dealtIn[id] == true).

-- src/server/Services/RoundService.luau:894-899
local function onPlayerRemoving(player: Player)
	state.PlayerStates[player.UserId] = nil
-- IMPORTANT THIS DELETION IS WHY THE DEALT-IN SET CANNOT BE DERIVED AT READ TIME. By the moment the
--      player comes back there is no PlayerStates entry left to inspect. The set has to be written at
--      STARTING and outlive the departure.

-- src/server/Services/RoundService.luau:915-928
	local inRound = state.Phase == Enums.RoundPhase.Active
		or state.Phase == Enums.RoundPhase.Starting
	-- ...
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)
		return
	end
-- NOTE STARTING counts too, and leaving it out was a live exploit (get the role card, quit within four
--      seconds, ACTIVE runs with no monster). `RejoinResolve` treats STARTING as in-round for exactly
--      this reason — the two halves must agree about who is in the round.
-- IMPORTANT Step 5.5's disconnect record goes ABOVE this branch. It returns, so a departing Aswang would
--      otherwise never be recorded — and "the Aswang left" is the round C32 most needs to score
--      differently.
-- NOTE This also means THE ASWANG HAS NO REJOIN CASE: their departure aborts the round, so a returning
--      Aswang always lands in a round that has already ended. RejoinResolve answers GHOST for them, which
--      is harmless and unreachable. Do not "fix" it.
