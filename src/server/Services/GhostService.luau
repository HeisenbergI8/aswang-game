--!strict
--[[
	GhostService — Dead players become contributing ghosts.

	Milestone: M4
	Spec: docs/MVP-SPEC.md
]]

local GhostService = {}

-- TODO(M4): convert dead survivors to ghosts (fly, ghost-only chat).
-- TODO(M4): ghosts progress tasks at Config.Ghost.TaskContributionMult.
-- SECURITY: ghosts must NOT be able to leak the Aswang identity to the living.
--           Use a separate chat channel, enforced server-side.

function GhostService.Init() end

function GhostService.Start() end

return GhostService
