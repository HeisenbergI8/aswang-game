--!strict
-- REVIEW: src/server/Services/RoundService.luau (939 lines; excerpts at 25-33, 41-60, 479-497,
-- 504-528, 530-533, 554-579, 692-700 of MonsterService for contrast, 885-939)
--
-- The reference service shape and the owner of the phase. This plan adds ONE function and deletes ONE
-- comment.

-- One direction only. RoleService must NEVER require RoundService back: a require cycle errors at load,
-- init.server.luau swallows it into a single warn, and the server sits in IDLE forever looking exactly
-- like "nobody has joined yet".                                              -- :26-28
-- IMPORTANT: the single most consequential line I read. It is the reason Step 2.3 subscribes to
-- PhaseChanged instead of following the C07 TODO at :578, and the reason Step 3.4 deletes that TODO
-- rather than leaving it. TaskService needs GetPlayerState, GetPhase and SetTasksCompleted from here;
-- if RoundService also required TaskService the cycle is exactly the one this comment describes, with
-- exactly the symptom it describes.

local state = {
	TasksCompleted = 0,                                                        -- :46
	GateOpen = false,                                                          -- :47
}
-- NOTE: both already exist. This plan writes TasksCompleted (via the new setter) and deliberately does
-- NOT write GateOpen — that belongs to C11, which is out of scope. At 5/5 the counter reads 5/5 and
-- nothing else happens, which is a runnable intermediate state rather than a half-built gate.

function RoundService.GetPlayerState(player: Player): PlayerState                -- :86
	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
end
-- NOTE: this is the whole of what TaskService.weightFor needs. It asks rather than keeping a copy,
-- exactly as MonsterService does. A killed player therefore stops contributing on the next tick with
-- no bookkeeping in TaskService at all, and at C15 the SAME line starts returning GHOST.

local function buildSnapshot(player: Player): Types.ClientRoundSnapshot          -- :479
	return {
		TasksCompleted = state.TasksCompleted,                                 -- :484
		TasksRequired = Config.Tasks.TotalRequired,                            -- :485
		GateOpen = state.GateOpen,                                             -- :486
	}
-- IMPORTANT: ClientRoundSnapshot ALREADY carries everything the global task bar needs, so this plan
-- widens no client contract. TaskProgressChanged exists alongside it for one reason — the snapshot
-- ticks at Config.Round.SnapshotInterval (0.5s), which is too coarse for a fill bar, and it cannot
-- carry YourTaskProgress without becoming a second per-player payload.

local function setPhase(newPhase: RoundPhase, duration: number?)                 -- :504
	RoundService.PhaseChanged:Fire(newPhase, duration)                          -- :513
	phaseChangedRemote:FireAllClients(newPhase, duration or 0)                  -- :516
	broadcastSnapshot()                                                         -- :520
-- IMPORTANT for ordering. Subscribers fire BEFORE the snapshot goes out, so TaskService's STARTING
-- handler has completed its draw by the time any client sees the phase change. TasksCompleted is 0
-- either way, so nothing observes the one-handler window in which a STARTING round has no tasks.
-- NOTE `setPhase` is a private local. Nothing this plan adds can reach it.

-- TODO(C07): pick tasks via TaskService in STARTING; TODO(C11): win conditions in ACTIVE  -- :530
	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)             -- :577
	-- TODO(C07): TaskService.SelectTasksForRound()                             -- :578
-- IMPORTANT: both deleted at Step 3.4. As written they instruct the require cycle the header at :26
-- warns about. Deleting a TODO is a real deliverable here — this is the file whoever builds C09 reads
-- first, and the replacement comment says what happens instead and why.

local function enterIdle()                                                       -- :534
	state.TasksCompleted = 0                                                    -- :536
local function enterIntermission()                                               -- :548
	RoleService.ClearRoles()
	setAllPlayerStates(Enums.PlayerState.Lobby)
-- NOTE, and it is a small real bug this plan happens to close: enterIdle resets TasksCompleted and
-- enterIntermission never has. The path out of a round is ENDING -> INTERMISSION, so the HUD shows
-- last round's 4/5 for the whole intermission. TaskService.clearTasks calls SetTasksCompleted(0) on
-- both transitions, which is why that setter must NOT be phase-guarded.

	task.spawn(function()                                                        -- :917
		while true do
			step()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
-- IMPORTANT: the exact shape and the exact waiver Step 3.3's tick loop copies. `check:config` accepts
-- the literal only because of the inline waiver with its reason, so the deliberate exception is visible
-- in a diff rather than silently disabled. NOTE also the ORDER comment above it at :906-910 —
-- connections and loops before the player backfill, because Start() runs inside a pcall that only warns.
