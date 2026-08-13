--!strict
-- REVIEW: src/shared/Remotes.luau:20-44, 46-77 (excerpts)
--
-- Read to confirm one thing: this plan adds NO remote. Both it needs are already declared, in the right
-- directions. Every addition here widens the audited surface, and the brief asked for a justification
-- if one were needed. None is.

-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"TaskProgressChanged",                                                       -- :26
}
-- NOTE: already declared, already in the DOWN list. Step 4.2 fires it with FireClient — per player,
-- never FireAllClients — and being in EVENTS_DOWN is what `check:remotes` checks about that.
-- IMPORTANT: it is NOT on check-secrecy.mjs's REVEAL_ALLOWLIST, and that is the good outcome. The
-- allowlist causes the scanner to SKIP a call; being off it means the broadcast rule actually runs over
-- the payload. See Types-review for exactly what that rule does and does not catch.

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",                                                       -- :36
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
}
-- NOTE: already declared. Step 4.1 connects OnServerEvent to it. `RequestTransform`'s trailing comment
-- names the precedent this handler follows — including the part that matters most, that it takes no
-- arguments at all.

-- RULE: every remote listed here must be rate-limited and fully validated in
-- AntiCheatService / the owning service. The client only ever *requests*.
-- IMPORTANT: both halves apply to Step 4.1 and they are separate obligations. AntiCheatService's own
-- header is blunt about it: "a handler that consults Consume() and then does no validation of its own
-- is NOT protected, and check:ratelimit will report it as clean." The validation half here is
-- evaluatePresence — phase, aliveness, a server-derived task point, and not-already-complete.

local function getEvent(name: string): RemoteEvent
	if IS_SERVER then ... end
	return folder:WaitForChild(name) :: Folder
end
-- IMPORTANT, and the reason `check:remotes` exists at all: on the client, WaitForChild on a name the
-- server never created HANGS FOREVER — no error, no output, no stack trace. Both names here are
-- eagerly created on the server at :79-86, so TaskController.Start's `Remotes.Get("TaskProgressChanged")`
-- resolves. A typo in either string is the failure with no symptom.

function Remotes.Get(name: string): RemoteEvent
	return getEvent(name)
end
-- NOTE: returns a plain RemoteEvent, so FireClient takes `...any` and NOTHING on the wire is typed
-- unless the caller annotates the local it passes. That is the whole reason Step 4.2 builds
-- `local payload: Types.TaskProgressPayload = { ... }` instead of an inline table.
