--!strict
--[[
	REVIEW — .luau-defs/globalTypes.d.luau:9229-9235, :14069, :14130-14162

	The repo's OWN vendored Roblox API definitions, fetched by `npm run check:toolchain`. Read
	because Hard Rule 1 forbids guessing a Roblox API's behaviour, and these are the only signatures
	this repo can actually point at. Note what they DO and DO NOT establish.
]]

-- .luau-defs/globalTypes.d.luau:9229-9235 — Roblox's OWN AnalyticsService
function LogCustomEvent(self, player: Player, eventName: string, value: number?, customFields: { [string]: any }?): nil
function LogEconomyEvent(self, player: Player, flowType: EnumAnalyticsEconomyFlowType, currencyType: string, amount: number, endingBalance: number, transactionType: string, itemSku: string?, customFields: { [string]: any }?): nil
function LogFunnelStepEvent(self, player: Player, funnelName: string, funnelSessionId: string?, step: number?, stepName: string?, customFields: { [string]: any }?): nil
-- IMPORTANT: THIS IS WHERE C40's EVENTS GO. Roblox ships its own analytics service that writes to
--            the Creator Hub dashboard, which is what BUILD-PLAN's "the funnel is visible in the
--            Creator Hub" means. There is no custom pipe to build.
--
-- IMPORTANT: THE NAME COLLIDES WITH OURS. `src/server/Services/AnalyticsService.luau` and
--            `game:GetService("AnalyticsService")` are different things with the same name. The
--            plan binds the Roblox one to `RobloxAnalytics` so a call site cannot be ambiguous.
--
-- IMPORTANT: these are the emitter's ONLY egress, and they are not remotes — no client subscriber,
--            no replicated container. That is the proof behind Q2: `role_assigned (role)` reaching
--            here is not a leak.
--
-- NOTE: `LogFunnelStepEvent` takes a funnel NAME and a step INDEX, which is why
--       `pure/AnalyticsEvents.Funnel` models steps as contiguous 1-based numbers separately from
--       the fifteen event names.
--
-- QUESTION: these definitions carry no security tags, so whether a LocalScript could call
--           LogCustomEvent is unknown from here. It does not matter for this plan — our emitter is
--           server-only by construction and check-secrecy Rule 6 keeps it that way.

-- .luau-defs/globalTypes.d.luau:14069 — MarketplaceService
ProcessReceipt: (receiptInfo: { [string]: any }) -> EnumProductPurchaseDecision
-- IMPORTANT: A FIELD, NOT A SIGNAL. It is assigned (`MarketplaceService.ProcessReceipt = fn`), not
--            connected. Only one assignment can exist in the whole game; a second silently replaces
--            the first and every purchase afterwards is answered by whichever module loaded last.
--            Nothing in this repo checks for that — it is in the plan's Follow Ups.
--
-- IMPORTANT: THE ARGUMENT IS `{ [string]: any }`. So `receiptInfo.PurchaseId`, `.PlayerId` and
--            `.ProductId` are NOT confirmed by this signature — every field is `any`, and the names
--            come from Roblox's documentation rather than from anything here. The plan's handler
--            type-checks all three and answers NotProcessedYet rather than assuming, so a wrong
--            name degrades to a retry instead of a wrong grant. This is Follow Up #1 and the single
--            most important thing to confirm when C37 is done.

-- .luau-defs/globalTypes.d.luau:4695-4696
NotProcessedYet: EnumProductPurchaseDecision
PurchaseGranted: EnumProductPurchaseDecision
-- IMPORTANT: TWO VALUES, AND THERE IS NO THIRD. There is no way to say "this purchase was invalid".
--            So every path that cannot durably grant — no profile, read-only profile, unknown
--            product id, malformed receipt — must answer NotProcessedYet. Reaching for
--            PurchaseGranted to dispose of an awkward case IS the refund request.

-- .luau-defs/globalTypes.d.luau:14130, :14135
function PromptGamePassPurchase(self, player: Player, gamePassId: number): nil
function PromptProductPurchase(self, player: Player, productId: number, equipIfPurchased: boolean?, currencyType: EnumCurrencyType?): nil
-- NOTE: both take a `Player`, which is what makes the server-initiated prompt in Q4's mechanism 1
--       possible at all.
-- QUESTION: the definitions carry NO security tags, so whether a LocalScript can also call these is
--           unverified. If it can — and Roblox's docs suggest it can — then §8.4's "never mid-round"
--           holds for honest clients only, and the phase gate (mechanism 2) is the structural half.
--           The plan says exactly this rather than claiming airtightness.

-- .luau-defs/globalTypes.d.luau:14162
function UserOwnsGamePassAsync(self, userId: (User | number), gamePassId: number): boolean
-- NOTE: `Async` and web-backed, so it yields and can throw. Phase 2 wraps it in a pcall and treats
--       an error as FALSE — erring toward "does not own" costs an owner a cosmetic briefly, erring
--       the other way gives away a paid item.
