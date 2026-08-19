--!strict
--[[
	REVIEW — src/server/Services/RoundService.luau:1-16, 26-32, 61, 87, 1199-1208, 1300-1339
	Read for: the hook C31 must fill, the dependency direction, and what the plan may and may not touch.
	This is the reference service shape; the plan does not deviate from it.
]]

--------------------------------------------------------------------------------
-- :7-16 — the rule C31 must not break
--------------------------------------------------------------------------------

--	DESIGN RULE: nothing outside this module mutates the phase. Other services
--	subscribe via RoundService.PhaseChanged.
-- IMPORTANT: C31 SUBSCRIBES. ProgressionService connects to PhaseChanged and awards at ENDING; it
-- never calls setPhase or EndRound. That is the whole of its relationship with the round.

--------------------------------------------------------------------------------
-- :26-32 — the require direction, and the warning attached to it
--------------------------------------------------------------------------------

-- One direction only. RoleService must NEVER require RoundService back: a require cycle errors at
-- load, init.server.luau swallows it into a single warn, and the server sits in IDLE forever looking
-- exactly like "nobody has joined yet".
local RoleService = require(script.Parent.RoleService)
-- IMPORTANT: this comment is the precedent the plan's §1.1(c) rests on. RoundService requires exactly
-- ONE service (RoleService) and is required BY seven (TaskService:52, ItemService:32, GateService:33,
-- MonsterService:55, GhostService:52, TrialService:52, QuickChatService:75). The graph is a star with
-- RoundService at the centre. ProgressionService joins as an eighth spoke, so RoundService requiring
-- it back would close the cycle this comment warns about.

--------------------------------------------------------------------------------
-- :61, :87 — what C31 consumes
--------------------------------------------------------------------------------

RoundService.PhaseChanged = Instance.new("BindableEvent")
-- NOTE: fires (newPhase, duration) at :679. All seven subscribers use
-- `RoundService.PhaseChanged.Event:Connect(handler)`; the plan follows that spelling exactly.

function RoundService.GetPlayerState(player: Player): PlayerState
-- NOTE: this is how the plan's award loop decides who played. LOBBY and SPECTATOR are excluded;
-- GHOST is INCLUDED, because someone killed in the third minute played the round.

--------------------------------------------------------------------------------
-- :1199-1208 — THE HOOK. This is what C31 fills.
--------------------------------------------------------------------------------

local function onServerClosing()
	-- Spec §6.4: a shutdown must flush player data before the process dies, and Roblox gives you a
	-- short window to do it. Nothing owns player data yet — ProfileStore lands at C31 — so this is
	-- deliberately empty. It exists NOW so that there is exactly one flush point when there is
	-- something to flush, rather than three services each binding their own and racing.
	-- TODO(C31): flush every loaded profile here, and only here.
	-- IMPORTANT: "exactly one flush point" is a constraint, not an observation. ProgressionService
	-- must NOT bind its own BindToClose; it registers with the plan's ShutdownFlush leaf and this
	-- function calls flushAll(). The comment above is replaced, not deleted — the reasoning still
	-- applies, it just has something to point at now.
	if Config.Debug.VerboseLogging then
		print("[RoundService] Server closing — nothing to flush yet.")
	end
end

--------------------------------------------------------------------------------
-- :1326-1339 — Start()'s ordering discipline, worth copying
--------------------------------------------------------------------------------

	-- ORDER MATTERS. init.server.luau wraps Start() in a pcall that only warns, so anything throwing
	-- part-way through leaves a server with whatever had been registered so far [...] Connections and
	-- loops go first; the player backfill, which is the part that touches remotes and could throw,
	-- goes last.
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onServerClosing)
-- IMPORTANT: the ONLY BindToClose in the tree — confirmed by `grep -rn BindToClose src/`, which
-- returns this line and one TODO in ProgressionService. The plan preserves that: one binding, a
-- registry behind it.
-- NOTE: this ordering argument is why the plan registers ShutdownFlush at the TOP of
-- ProgressionService.Start(), before any player connection — a Start() that throws half-way through
-- should still have registered its flush.

--------------------------------------------------------------------------------
-- :1355-1361 — the backfill pattern the plan reuses
--------------------------------------------------------------------------------

	-- Anyone who joined before this ran. Connecting PlayerAdded FIRST means the window between the
	-- connection and this loop cannot silently drop a player; the price is that someone joining in
	-- that window is handled twice, and onPlayerAdded is idempotent [...]
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
-- IMPORTANT: the plan copies the pattern but NOT the idempotence assumption. `startSession` is not
-- idempotent — a second StartSessionAsync for a key this server already holds is a lock fight with
-- itself — so ProgressionService guards its backfill with `if sessions[player.UserId] == nil`.
