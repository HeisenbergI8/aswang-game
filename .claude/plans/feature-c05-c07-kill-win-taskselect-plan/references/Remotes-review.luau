--!strict
-- Review of src/shared/Remotes.luau — checked to confirm this plan adds NO remote.
-- Excerpts only.

-- src/shared/Remotes.luau:20-32
-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned",
	"TaskProgressChanged",
	-- IMPORTANT: ALREADY DECLARED, in the correct direction. Phase 4 fires it with :FireAllClients from
	-- the server and listens with .OnClientEvent in CameraFXController — both directions check:remotes
	-- enforces (.claude/scripts/check-remotes.mjs:17-19). No Remotes.luau change is needed for C05.
	"PlayerKilled",
	"MonsterTransformed",
	"SaltEffect",
	"RoundEnded",
	"QuickChatBroadcast",
	"ProfileUpdated",
}

-- src/shared/Remotes.luau:35-44
-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTransform",
	-- IMPORTANT: also already declared, and Config.AntiCheat.Budgets already carries a budget for it
	-- (Config.luau:166). Phase 4 adds a handler and nothing else.
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
}

-- src/shared/Remotes.luau:78-86
-- Eagerly create on the server so the client's WaitForChild always resolves.
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end
-- IMPORTANT: this is why an UNDECLARED remote hangs a client forever rather than erroring — the
-- client's `folder:WaitForChild(name)` (line 75) never resolves for a name the server never created.
-- No error, no output, no stack trace. Both of C05's remotes are in the lists above, so this plan
-- cannot produce that failure; a later chunk adding one must edit this file first.

-- src/shared/Remotes.luau:8-11
--[[
	RULE: every remote listed here must be rate-limited and fully validated in AntiCheatService / the
	owning service. The client only ever *requests*.
]]
-- NOTE: `PlayerKilled` is a DOWN event, so it has no budget and needs none — budgets are per UP remote
-- (Config.AntiCheat.Budgets, and tests/anti-cheat-budgets.test.luau pins the correspondence in BOTH
-- directions). Nothing in this plan changes that correspondence.
