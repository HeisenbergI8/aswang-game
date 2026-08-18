--!strict
--[[
	REVIEW — src/shared/Remotes.luau (228 lines; read 1-120 and the name index)

	UNCHANGED BY THIS PLAN, and that is the finding. C29 declares no remote. This review exists so the
	claim is checkable rather than asserted: below are the two down-events the audio controller
	consumes and the reason each is already safe to consume.
]]

-- src/shared/Remotes.luau:20-22
-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
-- IMPORTANT: the bed, the one-shot scheduler's phase input, the gate cue and the sunrise cue ALL come
-- from this one already-existing remote, fired every `Config.Round.SnapshotInterval` (0.5s). C29
-- consumes it a second time alongside `SkyController` — no new name, no new fire, no new payload.

-- src/shared/Remotes.luau:36
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
-- IMPORTANT: the stinger's and the heartbeat's only input, and the one-line justification for why a
-- monster-scoped audio cue leaks nothing. It is `FireAllClients` (MonsterService.luau:471), so every
-- client already holds the fact the heartbeat renders.

-- src/shared/Remotes.luau:41-53
--[[
	C15. FireClient to ghosts ONLY, one payload per recipient, NEVER FireAllClients.
	It carries the UserIds of dead players, and what makes that safe is its AUDIENCE rather than its
	contents ...
	`check-secrecy.mjs` cannot police that: it reads payload fields and call shapes, and
	`FireClient(player, roster)` inside a loop over the wrong list is textually identical to one
	over the right list. The state test therefore lives at the fire site in GhostService.
]]
-- IMPORTANT: the precedent for how this repo documents a per-audience decision — at the fire site,
-- because no check can see it. C29 has no fire site at all, so the equivalent documentation goes in
-- the controller's SECRECY STATEMENT (plan Step 3.5). The general lesson holds: any audience decision
-- must be written where the code makes it, not in a plan.
-- NOTE: this entry is also the standing argument against a server-gated heartbeat. "Safe because of
-- its AUDIENCE rather than its contents" is precisely what a per-player proximity cue would need to
-- claim, and it is a claim nothing in this repo can verify mechanically.

-- src/shared/Remotes.luau:114-124
-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
}
-- IMPORTANT: C29 adds NOTHING to this list. Consequently `check:ratelimit` has no new handler to
-- inspect and `AntiCheatService` is untouched — not because the plan skipped the rule, but because
-- the client never asks the server for anything to make a sound. If an implementation of this plan
-- finds itself adding an up-event, the design has gone wrong.

-- src/shared/Remotes.luau:9-11
--[[
	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]
-- NOTE: the rule C29 satisfies vacuously. Worth stating in the plan's overview anyway, because "no
-- new remote" is the kind of negative claim that is only checkable if somebody says it out loud —
-- `check:remotes` verifies consistency between declaration and use, not that a list stayed short.
