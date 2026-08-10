--!strict
--[[
	ProgressionService — XP, levels, coins, daily streak, ProfileStore persistence.

	Milestone: M9
	Spec: docs/MVP-SPEC.md
]]

local ProgressionService = {}

-- TODO(M9): integrate a session-locked datastore wrapper (ProfileStore).
--            Do NOT hand-roll DataStore access — data loss and duplication bugs.
-- TODO(M9): schema versioning + migration on read (Types.PlayerProfile).
-- TODO(M9): save on meaningful change, on leave, and in game:BindToClose().

function ProgressionService.Init() end

function ProgressionService.Start() end

return ProgressionService
