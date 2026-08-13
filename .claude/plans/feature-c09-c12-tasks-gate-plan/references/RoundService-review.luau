--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau
	Read 2026-08-12 for the C09-C12 plan. Cited ranges below; the file is 972 lines.

	The reference service shape (CLAUDE.md), the owner of the phase, and the file Phase 6 edits. Phase
	6 is the only phase that touches it, and it touches it in three places.
]]

-- src/server/Services/RoundService.luau:41-58
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	TasksCompleted = 0,
	GateOpen = false,
	AswangUserId = nil :: number?,
	DealtInSurvivors = 0,
	AswangKills = 0,
}
-- IMPORTANT: `GateOpen` is initialised here and, as of the plan's writing, written by exactly two
-- lines — `enterIdle` (:561) and this initialiser. Both set it FALSE. Nothing in the tree has ever
-- set it true; that is Phase 6's whole job and the reason C11 owns it rather than plan 1.
-- NOTE: this local is NOT annotated as `Types.RoundState` and carries three fields that type does not
-- (`PhaseEndsAt`, `DealtInSurvivors`, `AswangKills`). So editing `Types.RoundState` does not change
-- this table and neither guards the other.

-- src/server/Services/RoundService.luau:90-109
function RoundService.SetTasksCompleted(count: number)
	state.TasksCompleted = math.clamp(count, 0, Config.Tasks.TotalRequired)
end
-- IMPORTANT — THE FUNCTION PHASE 6 MOVES, AND IT MUST MOVE. Step 6.3 has it call
-- `broadcastSnapshot`, which is a LOCAL declared at :515 — four hundred lines below this. Luau
-- resolves locals in declaration order, so calling it from here is a nil-call at runtime, not an
-- analyze error. Moving `SetTasksCompleted` to just after `broadcastSnapshot` is safe: it is a field
-- on the RoundService table, called at runtime by TaskService, so only DECLARATION order matters.
-- NOTE: its comment already explains why it is not guarded like a phase — TaskService legitimately
-- writes it in three situations, one of which is the INTERMISSION reset. Keep that comment; Step 6.3
-- adds to it rather than replacing it.

-- src/server/Services/RoundService.luau:500-511
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot
	return {
		TasksCompleted = state.TasksCompleted,
		GateOpen = state.GateOpen,
		AlivePlayerCount = aliveCount(),
		YourState = RoundService.GetPlayerState(player),
	}
end
-- IMPORTANT: `GateOpen` is ALREADY on the wire and already rendered (init.client.luau:77 prints
-- "gate OPEN" / "gate shut"). C11's entire client-facing surface is therefore one existing boolean
-- that finally becomes true. No new remote, no new field, no ClientRoundSnapshot change.
-- NOTE: `YourRole` is deliberately left unset here — RoleAssigned is the single allowlisted carrier
-- of a role. Phase 7 must not be tempted to put the task list on the snapshot for the same reason.

-- src/server/Services/RoundService.luau:525-545
local function setPhase(newPhase: RoundPhase, duration: number?)
	if state.Phase == newPhase then
		return
	end
	RoundService.PhaseChanged:Fire(newPhase, duration)
	broadcastSnapshot()
end
-- IMPORTANT: PRIVATE, and stays private. Spec §6.4 — nothing outside this service sets the phase.
-- GateService (Phase 6) calls `EndRound`, never this. That is the same relationship MonsterService
-- has via `MarkKilled`.

-- src/server/Services/RoundService.luau:578-612 (enterStarting)
	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())
	-- [... 24 lines later ...]
	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
-- IMPORTANT FOR PHASE 7, AND IT IS WHY C12 WORKS AT ALL: the draw happens BEFORE `setPhase` fires
-- PhaseChanged, deliberately — "drawing first means no subscriber can observe a STARTING round that
-- has no Aswang yet". TaskService's `onPhaseChanged(STARTING)` is exactly such a subscriber, so
-- `publishTaskLists` reading the role from there gets a populated value. Verified by reading the
-- ordering, not assumed.

-- src/server/Services/RoundService.luau:627-659 (enterEnding)
	if state.Phase == Enums.RoundPhase.Ending then
		warn(`[RoundService] Discarded a late round result ({result}) — already ENDING.`)
		return
	end
-- IMPORTANT FOR PHASE 6: this guard was written FOR C11. Its own comment predicts the exact
-- collision — "C11 raising SURVIVORS_ESCAPED one tick after the sunrise timeout already ended the
-- round". So several survivors reaching the gate in one tick, or a gate-win racing the timer, ends
-- the round once and warns about the loser. UNGATED by VerboseLogging, so a playtest will see it.
-- NOTE: Step 6.5 should record whether this warn fires. If it does, that is the guard working.

-- src/server/Services/RoundService.luau:662-667
function RoundService.EndRound(result: Types.RoundResult)
	if state.Phase ~= Enums.RoundPhase.Active then
		return
	end
	enterEnding(result)
end
-- IMPORTANT: guarded on ACTIVE INSIDE this service, which is what lets GateService's 4 Hz loop call
-- it as a REQUEST rather than becoming a second writer of the phase. `Types.RoundResult`, not
-- `string`, and :618-626 explains that the union blocks a concat leak but not a `:: any` cast.
-- `Enums.RoundResult.SurvivorsEscaped` (Enums.luau:43) already exists and needs no addition.

-- src/server/Services/RoundService.luau:753-786 (the attrition win, in MarkKilled)
	if WinConditions.aswangWinsByKills({ AswangKills = state.AswangKills, ... }) then
		RoundService.EndRound(Enums.RoundResult.AswangWins)
	end
-- IMPORTANT: "AT THE END OF MarkKilled AND NOWHERE ELSE. Not in the step() loop: polling a win
-- condition several times a second means the round can end on a tick that no player action caused."
-- NOTE — A DELIBERATE DEVIATION IN PHASE 6, and it should be defended rather than glossed: GateService
-- DOES poll its win condition at 4 Hz. The difference is that reaching a gate is a CONTINUOUS state
-- (you are standing there or you are not) with no event to hang off, whereas a kill is discrete and
-- already has one. There is no `PlayerMoved` to subscribe to. The cost is the one this comment warns
-- about — a round can end on a tick no action caused — and it is bounded to 250 ms of ambiguity.

-- src/server/Services/RoundService.luau:547-556
-- TODO(C11): win conditions in ACTIVE
-- NOTE: Step 6.3 removes this TODO. It is the only place in the tree that names C11.
return nil
