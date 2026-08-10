--!strict
--[[
	MonetizationService — Gamepasses, developer products, private servers.

	Milestone: M10
	Spec: docs/MVP-SPEC.md
]]

local MonetizationService = {}

-- TODO(M10): MarketplaceService.ProcessReceipt — MUST be idempotent, and must
--            only return PurchaseGranted after the grant is durably saved.
-- TODO(M10): cache gamepass ownership; re-check on join.
-- SELL: cosmetics, identity, private servers. NEVER in-round advantage (spec §8.3).

function MonetizationService.Init() end

function MonetizationService.Start() end

return MonetizationService
