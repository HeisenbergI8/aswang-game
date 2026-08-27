--!strict
--[[
	REVIEW — src/shared/Remotes.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite.

	THE HEADLINE: V05 ADDS NO REMOTE AND CHANGES NONE. `Remotes.luau` has an empty diff across the
	whole plan. This review exists to record that as a verified fact rather than an omission, and to
	say why the health readout does not need one.
]]

-- src/shared/Remotes.luau:1-11
--[[
	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]
-- NOTE: V05 adds no `OnServerEvent` handler either, so `check:ratelimit` sees nothing new. Both
-- checks pass by having nothing to check, which is the cheapest way to pass them.

-- src/shared/Remotes.luau:20-28  (the DOWN list, head)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"SaltEffect",
	"RoundEnded", -- includes the reveal
}
-- IMPORTANT: `RoundEnded` and `RoleAssigned` are the ONLY two remotes allowlisted in
-- `check-secrecy.mjs` to carry role information. V05 needs neither, and adding a third would require
-- editing that file — which is the asymmetry CLAUDE.md describes as the design.
-- NOTE: `SaltEffect` is the remote a health readout would most plausibly be bolted onto, and
-- `Types.SaltEffectPayload`'s comment explains why an extra field there passes every check in the
-- repo and still names the monster. V05 does not go near it.

-- src/shared/Remotes.luau:104-131  (NoiseCue — V04, the closest precedent for a per-player cue)
--[[
	THE BROADCAST FORM IS THE WHOLE RISK AND IT IS REFUSED. A FireAllClients carrying a position
	would hand every client a live index of where everybody in the barrio is acting ...
	THE `Mine` FLAG IS NOT A LEAK: a client only ever sees its own payloads, so a boolean about
	the receiver is the same shape as every field on `ProfileSnapshot`.
]]
-- NOTE: worth reading before Follow Ups #1 is decided. It is the model for "tell one player a fact
-- about themselves" done correctly — and note that it still needed the `absence-is-observable`
-- paragraph, because a player who NEVER receives a cue is as identifiable as one who always does.

-- src/shared/Remotes.luau:134-137
local EVENTS_UP = {
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	"RequestKill",
	"RequestThrowSalt",
}
-- NOTE: §6.2's list also names `RequestStrike` for the buntot pagi. That is V08's remote, not V05's.
-- V05 supplies the two server-side predicates (`IsExposed`, `IsWeakened`) its handler will AND
-- together; the remote itself is declared by the chunk that validates it.

-- src/shared/Remotes.luau:262-274
local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
	end
	return folder:WaitForChild(name) :: RemoteEvent
end
-- IMPORTANT: the failure `check:remotes` exists to catch — on the client, `WaitForChild` on a name
-- the server never created HANGS FOREVER, with no error and no stack trace. V05's contribution to
-- that check is an empty diff.
--
-- NOTE: the reason no remote is needed for the health readout: a `Highlight` created on the SERVER
-- and parented into the workspace replicates to every client automatically, and so does a later
-- write to its `FillTransparency`. The presentation of §4.6's health is a property change, not a
-- message.
