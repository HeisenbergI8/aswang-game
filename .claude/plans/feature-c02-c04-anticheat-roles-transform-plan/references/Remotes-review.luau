--!strict
--[[
	REVIEW — src/shared/Remotes.luau

	VERIFIED BY READING, which is the point of this review: the request said "all four needed
	(RoleAssigned, RequestTransform, MonsterTransformed) already exist there — verify before assuming."

	Result: THREE names were listed, and all three exist, in the correct direction list. This plan adds
	NO remote. (`RequestKill` also exists and belongs to C05.)
]]

-- Server -> Client
local EVENTS_DOWN = {
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned", -- ✅ present, DOWN. Phase 5 fires it with :FireClient to one player.
	"TaskProgressChanged",
	"PlayerKilled",
	"MonsterTransformed", -- ✅ present, DOWN. Phase 6/7 broadcasts it with :FireAllClients.
	"SaltEffect",
	"RoundEnded",
	"QuickChatBroadcast",
	"ProfileUpdated",
}

-- Client -> Server
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTransform", -- ✅ present, UP. Phase 6 connects .OnServerEvent to it.
	"RequestKill", -- present, C05's. Left unwired by this plan.
	"RequestThrowSalt",
	"RequestQuickChat",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
}
-- IMPORTANT: EIGHT names. `Config.AntiCheat.Budgets` (Step 1.1) must carry exactly these eight, and
-- `tests/anti-cheat-budgets.test.luau` pins both directions.

--[[
	IMPORTANT — why the budget list cannot simply require this file:

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local RunService = game:GetService("RunService")

	Both run at MODULE SCOPE. Lune has no `game`, so `require("../src/shared/Remotes")` errors before
	reaching the lists. That is the whole reason Step 1.1's test hand-copies the eight names, and it is
	recorded as a Medium Follow Up.
]]

--[[
	NOTE — the hang that check:remotes exists to prevent, from the header:

		"RULE: every remote listed here must be rate-limited and fully validated in AntiCheatService /
		 the owning service. The client only ever *requests*."

	and from check-remotes.mjs: on the client `Remotes.Get(name)` resolves through `WaitForChild`, so a
	name the server never created HANGS FOREVER — no error, no output, no stack trace.
]]

-- Usage shape both new handlers follow. NOTE check-remotes.mjs only inspects the 40 characters after
-- `Remotes.Get("Name")`, so the Fire/On call must be chained inline for the direction check to see it.
function Remotes.Get(name: string): RemoteEvent end
