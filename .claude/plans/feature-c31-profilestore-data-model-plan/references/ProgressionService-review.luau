--!strict
--[[
	REVIEW — src/server/Services/ProgressionService.luau:1-20 (the WHOLE file; it is 20 lines)
	Read for: what C31 is filling in, and whether the stub commits us to anything.
]]

-- The whole service, verbatim. It is a placeholder with a correct lifecycle and no behaviour.
local ProgressionService = {}

-- IMPORTANT: these four TODOs are C31's brief, written by C01, and they line up exactly with §6.6's
-- four rules. Nothing here is wrong or needs undoing — the plan ADDS to an empty shape rather than
-- reworking a wrong one, which is why C31 is a feature plan and not a refactor.
-- TODO(M9): integrate a session-locked datastore wrapper (ProfileStore).
--            Do NOT hand-roll DataStore access — data loss and duplication bugs.
-- TODO(M9): schema versioning + migration on read (Types.PlayerProfile).
-- TODO(M9): save on meaningful change, on leave, and in game:BindToClose().

-- NOTE: both lifecycle hooks already exist and are already wired — `init.server.luau:23` lists
-- "ProgressionService" THIRD in SERVICE_ORDER, ahead of every gameplay service. So the store is
-- constructed before RoleService, TaskService or RoundService start, and any of them can call
-- GetProfile from their own Start() without a load-order question. That ordering was chosen before
-- C31 existed and it happens to be exactly right.
function ProgressionService.Init() end

function ProgressionService.Start() end

-- NOTE: the module returns a plain table with free functions — no `self`, no metatable, no `.new`.
-- That is the shape every service in this repo uses (RoundService, TaskService, MonsterService), and
-- it is what makes `pcall(service.Start)` in the bootstrap work. C31 does not deviate.
return ProgressionService

-- QUESTION (answered in the plan, §1.1c): nothing here references RoundService, and nothing in
-- RoundService references this. C31 introduces the FIRST edge between them, and the direction it
-- points is a decision that outlives this chunk — C32 will want to award XP at round end, and if the
-- edge already points ProgressionService -> RoundService, C32 must subscribe rather than be called.
-- The plan settles it that way, matching the seven services that already subscribe to PhaseChanged.
