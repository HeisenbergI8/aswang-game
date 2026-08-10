--!strict
--[[
	BadgeService — Awards the 5 funnel badges.

	Milestone: M9
	Spec: docs/MVP-SPEC.md
]]

local BadgeService = {}

-- Badge award counts are publicly readable via the Roblox API, which is how
-- the competitor teardown in Appendix C was produced. Mirroring our funnel in
-- badges gives us a free, durable, tamper-proof retention dashboard.
--
-- TODO(M9): Welcome, First Task, First Round, First Blood, Balik-Balik.
-- TODO(M9): award server-side only; never trust a client request.
-- GATE: if "First Task" / "Welcome" < 50%, stop everything and fix FTUE (§10).

function BadgeService.Init() end

function BadgeService.Start() end

return BadgeService
