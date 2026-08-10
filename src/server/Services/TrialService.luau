--!strict
--[[
	TrialService — The Solo Trial: 90s single-player practice run.

	Milestone: M6
	Spec: docs/MVP-SPEC.md
]]

local TrialService = {}

-- WHY THIS EXISTS: the closest competitor lost 79.9% of players before their
-- first objective, and their game at least worked solo. Ours does not function
-- below MinPlayers. The Trial is both the tutorial and the low-population
-- fallback. See spec §9.1 and Appendix C.
--
-- TODO(M6): two guided tasks, then a scripted Aswang transform + chase.
-- TODO(M6): teach the transform tell and salt by DOING, never by text wall.
-- TODO(M6): offer it whenever player count < Config.Round.MinPlayers.
-- TODO(M6): exit straight into the lobby queue.
--
-- SCOPE GUARD: this must never grow into a PvE campaign. Consumable content is
-- exactly what killed the competitor.

function TrialService.Init() end

function TrialService.Start() end

return TrialService
