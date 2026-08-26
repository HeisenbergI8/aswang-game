--!strict
--[[
	REVIEW — src/server/Services/MonetizationService.luau:1-20 (the ENTIRE file)

	A C01-era stub. Twenty lines, three TODOs, no implementation. Reviewed in full because the file
	is short enough that the whole thing is the annotation, and because its TODOs are a surprisingly
	accurate brief that this plan should be checked against.
]]

--!strict
--[[
	MonetizationService — Gamepasses, developer products, private servers.

	Milestone: M10
	Spec: docs/MVP-SPEC.md
]]

local MonetizationService = {}

-- TODO(M10): MarketplaceService.ProcessReceipt — MUST be idempotent, and must
--            only return PurchaseGranted after the grant is durably saved.
-- IMPORTANT: "DURABLY SAVED" IS THE WHOLE PROBLEM, and the scaffold author could not have known how
--            hard it is here: `Profile:Save()` does not yield and does not report success
--            (vendor/ProfileStore.luau:1172-1190). So this TODO cannot be satisfied by calling
--            Save and returning — it needs the `OnAfterSave` / `LastSavedData` durability oracle.
--            See ProfileStore-review.luau. This is the finding that shaped Phase 2.

-- TODO(M10): cache gamepass ownership; re-check on join.
-- NOTE: "re-check on join" is looser than what the plan builds. `Types.PlayerProfile.Purchases`
--       stores a TIMESTAMP, so the cache is TTL-based rather than per-join — a player who buys VIP
--       mid-session sees it at the next expiry rather than having to rejoin. Same intent, and the
--       stamp field is what the data model actually offers.

-- SELL: cosmetics, identity, private servers. NEVER in-round advantage (spec §8.3).
-- IMPORTANT: preserved verbatim into the rewritten file, and expanded with §8.3's explicit list.
--            `check:scope` does NOT enforce §8.3 — see MVP-SPEC-review.luau — so this comment is
--            load-bearing rather than decorative.

function MonetizationService.Init() end

function MonetizationService.Start() end

return MonetizationService
-- NOTE: the two-phase `Init`/`Start` lifecycle `init.server.luau` requires. The plan puts the
--       `ProcessReceipt` ASSIGNMENT in `Init` (a receipt can arrive the instant a player is
--       accepted, and every Init runs before any Start) and both remote handlers plus the
--       `PhaseChanged` subscription in `Start` (they call other services).

-- NOTE: `MonetizationService` is already listed in `init.server.luau`'s SERVICE_ORDER, in the
--       "Infrastructure first" block AFTER `ProgressionService` — which is the order this plan
--       needs, since it calls `ApplyReceipt` and `GetProfile`. No bootstrap edit required.
-- IMPORTANT: it sits BEFORE the gameplay block and therefore before `RoundService`, which is last.
--            That is fine — the plan's dependency on RoundService is a `require` (resolved at load,
--            order-independent) plus a `PhaseChanged` subscription made in `Start`, by which time
--            every module has been required.

-- IMPORTANT: NOTHING IN THIS FILE CAN BE OBSERVED WORKING UNTIL A HUMAN DOES C37. Roblox never
--            calls ProcessReceipt for a product that does not exist, and every catalogue id is 0 so
--            UserOwnsGamePassAsync is never reached. An empty shop is this file working correctly.
