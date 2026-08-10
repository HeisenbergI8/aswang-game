--!strict
--[[
	RoleService — Secret role assignment with anti-repeat weighting.

	Milestone: M2
	Spec: docs/MVP-SPEC.md
]]

local RoleService = {}

-- TODO(M2): assign 1 Aswang from the player list.
-- TODO(M2): track last 2 rounds; heavily reduce weight for recent Aswangs.
-- SECURITY: the role is server-only state. Fire "RoleAssigned" to the ONE
-- player it concerns via FireClient — never FireAllClients.

function RoleService.Init() end

function RoleService.Start() end

return RoleService
