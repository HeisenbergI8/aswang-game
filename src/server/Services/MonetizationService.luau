--!strict
--[[
	MonetizationService — Gamepasses, developer products, private servers.

	Milestone: M9
	Spec: docs/MVP-SPEC.md
]]

local MonetizationService = {}

-- TODO(M9): MarketplaceService.ProcessReceipt — MUST be idempotent, and must
--            only return PurchaseGranted after the grant is durably saved.
-- TODO(M9): cache gamepass ownership; re-check on join.
-- SELL: cosmetics, identity, private servers. NEVER in-round advantage (spec §8.3).

function MonetizationService.Init() end

function MonetizationService.Start() end

return MonetizationService
