--!strict
--[[
	AntiCheatService — Rate limiting and sanity checks on every remote.

	Milestone: M10
	Spec: docs/MVP-SPEC.md
]]

local AntiCheatService = {}

-- TODO(M10): per-player token bucket on EVERY remote in Shared/Remotes.
-- TODO(M10): sanity-check movement speed and teleports.
-- Exploiters will specifically target this game because knowing the imposter
-- is so valuable. Server authority is the whole defence.

function AntiCheatService.Init() end

function AntiCheatService.Start() end

return AntiCheatService
