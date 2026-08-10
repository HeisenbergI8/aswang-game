--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau (C01, commit dc06307)

	The reference implementation of the service shape, and the only thing that sets the phase. Every
	line below is one this plan reads from, writes to, or must not disturb.
]]

-- The service-shape contract every new service copies: a module table, module-local state, Init(),
-- Start(). init.server.luau runs every Init() before any Start().
local RoundService = {}

-- SERVER-ONLY state. Never replicate this table.
local state = {
	Phase = Enums.RoundPhase.Idle :: RoundPhase,
	PhaseEndsAt = 0,
	RoundNumber = 0,
	AswangUserId = nil :: number?,
	-- IMPORTANT: this is where C03 writes the drawn Aswang. The plan does NOT introduce a second home
	-- for the secret — `enterEnding`'s reveal and `onPlayerRemoving`'s abort already read this field,
	-- and a second copy would be a second thing to keep in step.
	PlayerStates = {} :: { [number]: PlayerState },
}

-- IMPORTANT: a BindableEvent, so subscribers connect to `.Event` and NOT to the object itself.
-- `RoundService.PhaseChanged:Connect(...)` is the natural thing to type, errors at runtime, and is
-- swallowed by init.server.luau's pcall into one warn line — a service that silently never reacts.
-- MonsterService (Phase 7) is this plan's first subscriber.
RoundService.PhaseChanged = Instance.new("BindableEvent")

-- Queries MonsterService calls per RequestTransform. Both are plain reads with no side effects.
function RoundService.GetPhase(): RoundPhase
	return state.Phase
end

-- NOTE: defaults an unknown UserId to LOBBY. C04's warning block calls this belt-and-braces after
-- C01's Start() ordering, and it is why TransformRules gates on `== ALIVE` (an allowlist) rather than
-- `~= SPECTATOR`: LOBBY and GHOST would both pass a denylist.
function RoundService.GetPlayerState(player: Player): PlayerState
	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
end

-- Deliberately NOT exposed to any client-facing code path.
function RoundService.GetAswangUserId(): number?
	return state.AswangUserId
end

--[[
	IMPORTANT — the comment C01 left here is the reason this plan does NOT add a role to the snapshot:

		"`YourRole` is deliberately left unset. The snapshot is built per player, so a role here would
		be *technically* safe — but RoleAssigned (fired to exactly one player) is the single allowlisted
		carrier of a role in `check-secrecy.mjs`, and one carrier is auditable in a way that two are not.
		C03 puts the role on RoleAssigned and the client caches it locally."

	This plan follows that instruction exactly. `Types.ClientRoundSnapshot.YourRole` stays unset.
]]
local function buildSnapshot(player: Player): Types.ClientRoundSnapshot

-- The one place the phase changes. NOTHING outside this module calls it (spec §6.4).
local function setPhase(newPhase: RoundPhase, duration: number?)
	-- NOTE: fires PhaseChanged and broadcasts a snapshot to every client. This is why Phase 5 draws
	-- roles BEFORE calling setPhase in enterStarting — so no subscriber can observe a STARTING round
	-- that has no Aswang yet.
end

local function enterStarting()
	state.RoundNumber += 1
	-- IMPORTANT: this runs first, so every connected player is ALIVE. Phase 5's `dealtInUserIds()`
	-- reads PlayerStates immediately after and sorts, which is what makes RoleDraw reproducible.
	setAllPlayerStates(Enums.PlayerState.Alive)
	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
	-- TODO(C03): RoleService.AssignRoles()   <- Phase 5 Step 5.3 replaces this line
	-- TODO(C07): TaskService.SelectTasksForRound()
end

-- IMPORTANT — the payload comment here is the pattern Phase 5 copies for RoleAssigned:
--   "Built as a TYPED LOCAL, not an inline table: `FireAllClients` takes `...any`, so an inline
--    literal is checked against nothing at all. The annotation catches a wrong type and a missing
--    field — but NOT an extra one, which is the leak shape."
local payload: Types.RoundEndedPayload = {
	Result = result,
	AswangUserId = state.AswangUserId, -- safe: the round is over
	RoundNumber = state.RoundNumber,
}

Remotes.Get("RoundEnded"):FireAllClients(payload)

-- The Aswang disconnecting aborts the round. Phase 5 changes nothing here; it only fills in the field
-- this reads.
local function onPlayerRemoving(player: Player)
	state.PlayerStates[player.UserId] = nil
	if state.AswangUserId == player.UserId then
		enterEnding(Enums.RoundResult.Aborted)
	end
end

--[[
	IMPORTANT — the Start() ordering comment, quoted because it names the failure shape this plan must
	not reintroduce with a require cycle:

		"init.server.luau wraps Start() in a pcall that only warns, so anything throwing part-way
		through leaves a server with whatever had been registered so far — and a server with no tick
		loop, no snapshot loop and no close handler sits in IDLE forever behind one warn line, which
		looks exactly like 'nobody has joined yet'."

	RoundService requires RoleService (Phase 5). RoleService must NEVER require RoundService back: the
	cycle errors at require time and produces exactly that symptom.
]]
function RoundService.Start() end

-- config-ok precedent this plan reuses for placeholder styling:
--   task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
