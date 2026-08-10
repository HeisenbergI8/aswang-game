--!strict
--[[
	CommunityService — Group join reward and social link prompts.

	Milestone: M10
	Spec: docs/MVP-SPEC.md
]]

local CommunityService = {}

-- The competitor had 1.43M unique players, no group and no social links, so
-- every update shipped into silence. See Appendix C.
--
-- TODO(M10): detect group membership, grant a one-time cosmetic/coin reward.
-- TODO(M10): in-lobby panel linking the TikTok and Discord.
-- Every group member is a player you can re-activate on every update, free.

function CommunityService.Init() end

function CommunityService.Start() end

return CommunityService
