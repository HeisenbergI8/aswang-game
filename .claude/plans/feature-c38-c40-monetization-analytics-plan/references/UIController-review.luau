--!strict
--[[
	REVIEW — src/client/Controllers/UIController.luau:323, :1083-1253, :2157-2170

	Read only for where the end screen is built and how remotes are wired, because Phase 4 Step 4.4
	adds one subscription and one button. 2286 lines; this plan touches a handful and MUST NOT
	restyle any of them — C26 owns the end screen's design and `.claude/skills/ui-polish` is the
	authority on motion, thumb zones and scaling.
]]

-- src/client/Controllers/UIController.luau:323
function UIController.GetMyRole(): Types.Role?
-- IMPORTANT: THE CLIENT HOLDS ITS OWN ROLE IN THIS MODULE. That is legitimate — `RoleAssigned` is
--            FireClient to one player carrying only that player's own role — but it means this file
--            is one of the few client files holding the secret, and the C02-C04 audit asked
--            specifically whether `UIController.myRole` reaches any replicated container.
--
--            THE SHOP MUST NOT READ IT. There is no cosmetic, price or offer in §8.2 that varies by
--            role, so a shop panel branching on `GetMyRole()` would be inventing a role-visible
--            difference on the end screen — after the reveal, admittedly, but on a code path that
--            will later be reused. Keep the shop role-blind.

-- src/client/Controllers/UIController.luau:1083
local function showEndScreen(payload: Types.RoundEndedPayload)
-- NOTE: the end screen already exists and already runs on `RoundEnded`. §8.4's shop belongs here —
--       "when the player just had a great round and is waiting anyway".
-- IMPORTANT: THE SHOP IS NOT DRAWN FROM THIS PAYLOAD. `RoundEnded` is one of the two remotes on
--            check-secrecy's REVEAL_ALLOWLIST, and its permitted fields are pinned to exactly
--            `{ Result, AswangUserId, RoundNumber }` (check-secrecy.mjs:89). Adding offer data to
--            it would be a stray field and correctly refused — which is why the plan uses a
--            separate `ShopOffer` remote rather than widening the reveal.
-- NOTE: `Config.Round.EndScreen = 12` seconds is the whole window the shop has to appear in. See
--       the Phase 4 issue about `OwnsGamepass` latency eating into it.

-- src/client/Controllers/UIController.luau:2157-2170
function UIController.Init() end

function UIController.Start()
	Remotes.Get("RoleAssigned").OnClientEvent:Connect(function(payload: Types.RoleAssignedPayload)
	...
-- NOTE: the wiring convention Phase 4 follows — `Remotes.Get(name).OnClientEvent:Connect` inside
--       `Start`, with the payload annotated. The plan's `ShopOffer` handler is one of these and
--       does nothing but hand the list to a render function.
-- IMPORTANT: `Remotes.Get` on the client does a `WaitForChild`. If `ShopOffer` were used here but
--            not declared in `Remotes.luau`'s EVENTS_DOWN, this line WOULD HANG FOREVER — no error,
--            no output, no stack trace. That is the exact failure `check:remotes` exists to catch
--            and why Step 4.1's verify line is `npm run check:remotes`.

-- IMPORTANT: THE BUY BUTTON FIRES THE REMOTE AND DOES NOTHING ELSE. No `MarketplaceService` call on
--            the client, no price arithmetic, no "you can afford this" inference. The server sent
--            `Price` for display and `Owned` as a fact. This is mechanism 1 of Q4, and it is the
--            line most likely to be "simplified" later by someone who notices the client COULD
--            prompt directly — which would delete the server-side ENDING gate's reason to exist.

-- NOTE: with every catalogue id at 0 the server never fires `ShopOffer`, so this handler never runs
--       and no panel appears. Correct behaviour before C37, and the thing most likely to be
--       reported as a defect by anyone who has not read the plan's §1.2.
