--!strict
--[[
	MonsterService — Transform, kill validation, cooldowns.

	Milestone: M2
	Spec: docs/MVP-SPEC.md
]]

local MonsterService = {}

-- TODO(M2): transform (Config.Monster.TransformTime) — visible to everyone by design.
-- TODO(M2): validate kills SERVER-SIDE: distance <= KillRange, raycast line of
--           sight, cooldown elapsed, both alive, phase == ACTIVE.
-- The client only requests. The server decides.

function MonsterService.Init() end

function MonsterService.Start() end

return MonsterService
