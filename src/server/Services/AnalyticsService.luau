--!strict
--[[
	AnalyticsService — Emits the gameplay funnel events.

	Milestone: M10
	Spec: docs/MVP-SPEC.md
]]

local AnalyticsService = {}

-- TODO(M10): emit the events listed in docs/MVP-SPEC.md Appendix B.
-- The funnel that matters: joined -> reached ACTIVE round -> completed a round
-- -> returned on day 2. Track win rate per side from day one or you cannot balance.

function AnalyticsService.Init() end

function AnalyticsService.Start() end

return AnalyticsService
