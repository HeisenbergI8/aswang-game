--!strict
--[[
	REVIEW — src/shared/Remotes.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 96 lines; the whole network surface.

	Phase 1 adds three names. That is three more than the plan wanted, and the justification is that
	all eight currently-unwired remotes are spoken for by other chunks.
]]

-- src/shared/Remotes.luau:20-32
local EVENTS_DOWN = {
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"TaskProgressChanged",
	"PlayerKilled",
	"MonsterTransformed",
	"SaltEffect",
	"RoundEnded",
	"QuickChatBroadcast",
	"ProfileUpdated",
}
-- Phase 1 inserts `TimingBarChanged` and `TaskListAssigned` after `TaskProgressChanged`.
-- NOTE on the three unwired DOWN names and why none was reused:
--   SaltEffect         C14's, and its payload is a stun/glow, not a list
--   QuickChatBroadcast C16's, and it is the one genuinely public broadcast in the game
--   ProfileUpdated     M8/M9's, per-player profile data
-- IMPORTANT: reusing one would mean two chunks sharing a name with two payload shapes. The client
-- does `WaitForChild(name)` and gets ONE RemoteEvent; two contracts on it is a desync with no error.

-- src/shared/Remotes.luau:34-44
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
}
-- Phase 1 inserts `RequestTimingStop` after `RequestTaskProgress`.
-- IMPORTANT: five unwired UP names, all earmarked (C14, C16, C15, M8, M9). None is a timing stop.
-- IMPORTANT: every name here must have a `Config.AntiCheat.Budgets` entry — `AntiCheatService.Consume`
-- FAILS CLOSED (`AllowUnbudgetedRemote = false`), so a remote added here and nowhere else is refused
-- outright at runtime. That is a silent-looking failure: the handler simply never runs.

-- src/shared/Remotes.luau:78-86
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end
-- IMPORTANT: "Eagerly create on the server so the client's WaitForChild always resolves." This is the
-- mechanism behind CLAUDE.md's warning that a client `WaitForChild` on a name the server never created
-- HANGS FOREVER — no error, no output, no stack trace. Declaring the three new names in this file is
-- therefore not bookkeeping; it is the thing that makes Phase 3 and Phase 7's client listeners return.

-- src/shared/Remotes.luau:88-91
function Remotes.Get(name: string): RemoteEvent
	return getEvent(name)
end
-- NOTE: returns a PLAIN RemoteEvent, so `FireClient`/`FireAllClients` take `...any` and an inline
-- payload literal is typechecked against NOTHING. That is why every publisher in this codebase builds
-- a typed local first, and why Phases 3 and 7 do too.
-- IMPORTANT: `check-secrecy.mjs` resolves a remote's NAME by looking backwards from the fire call for
-- `Remotes.Get("...")`. A remote held in a variable defeats that — the finding text says so
-- explicitly: "The remote is held in a variable, so its name cannot be checked here." The plan's
-- `local barRemote = Remotes.Get("TimingBarChanged")` and `local listRemote = ...` follow the
-- existing `progressRemote` / `phaseChangedRemote` / `snapshotRemote` pattern, which check-remotes
-- handles (its self-test at :185 covers `local ev = Remotes.Get(...)` then `ev:FireAllClients`) —
-- but note the two checks differ here, and secrecy's variable case is the CONSERVATIVE direction: an
-- unknown name is NOT allowlisted, so it is flagged rather than skipped.

-- .claude/scripts/check-remotes.mjs:99-133 (read alongside)
-- DOWN events may be fired only with :FireClient / :FireAllClients, on the SERVER, and listened to
-- with .OnClientEvent on the CLIENT. UP is the mirror.
-- IMPORTANT for Step 3.3's Verify: `check:remotes` reports an UNDECLARED remote as an ERROR and an
-- unwired one as a NOTE ("N declared but not yet wired"). So it passes on a step that declares
-- nothing at all, which is exactly the vacuity the plan's brief warned about. It is the right check
-- for 3.3 (which wires a DOWN event and could get the direction wrong) and the wrong one for 1.4
-- (which declares), and the plan splits them accordingly.
return nil
