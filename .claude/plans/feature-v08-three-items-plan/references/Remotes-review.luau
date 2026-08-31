--!strict
--[[
	REVIEW — src/shared/Remotes.luau (402 lines). Phase 2 Step 2.4 adds one name to EVENTS_UP.

	The argument-free declaration is a house style here with a stated security reason, and
	`RequestDropItem` inherits it directly. Read the four precedents below before writing it.

	Cited against the file as read on 2026-08-29.
]]

-- src/shared/Remotes.luau:3-12
--[[
	The server creates them; the client waits for them. Declaring them in one file means you can audit
	your entire network surface at a glance ...

	RULE: every remote listed here must be rate-limited and fully validated in AntiCheatService / the
	owning service. The client only ever *requests*.
]]
-- NOTE: "the server creates them; the client waits for them" is why `check:remotes` matters so much:
-- a WaitForChild on a name the server never created HANGS FOREVER — no error, no output, no stack.

-- src/shared/Remotes.luau:21-22 — EVENTS_DOWN's opening
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
}
-- IMPORTANT: V08 ADDS NOTHING HERE. The carry rides `RoundSnapshot`, which already exists and is
-- already per-player. A `CarryUpdate` remote would be a second server→client channel for a field
-- ClientRoundSnapshot already declares, and would give the HUD two sources for one value.
-- NOTE: `SaltEffect` (:27) stays as-is and is not renamed — salt is the only item with a throw.

-- src/shared/Remotes.luau:255-268 — RequestClaimGroupReward, abridged
--[[
	NO ARGUMENTS, for the same reason `RequestClaimDaily` above has none — everything the decision
	needs is server-side already.

	THE GROUP ID IS NOT AN ARGUMENT, and that is the security design ... A client-supplied id would
	let a player name any group they happen to belong to and collect 250 coins for membership of
	somebody else's.
]]
-- NOTE: precedent 1. The pattern: name nothing the server already knows, and the whole class of
-- "validate that the named thing is the right thing" disappears with the argument.

-- src/shared/Remotes.luau:288-312 — RequestSearch, abridged
--[[
	V03, §4.4. NO ARGUMENTS, and the absent argument is the entire security design.

	THE CONTAINER IS NOT NAMED BY THE CLIENT. The server resolves the nearest `SearchContainer` part
	within `Config.Search.RangeStuds` of that player's OWN character position — the rule
	`ItemService`'s header states for pickups, applied to the one interaction that has a remote.

	A `RequestSearch(containerName)` would have been strictly worse in three ways, and the third is
	the one that matters. It needs a verdict for "that container is not near you"; it needs validation
	that the named part is the one you are standing at ...; and it hands a compromised client a PROBE
	— name every tagged part in turn, read the verdicts, and learn which containers are spent and
	which are occupied without walking anywhere. The map's part names are readable by any client
	(Workspace replicates), so the probe would have been trivial to write.
]]
-- IMPORTANT: THE MODEL FOR `RequestDropItem`'s DECLARATION, three-part structure included. The V08
-- version's third way is sharper than a probe: there is exactly one buntot pagi and it IS the second
-- win condition, so a handler that spawns an item the client NAMED is the worst exploit surface in
-- the chunk. With no argument it cannot be asked.
-- NOTE: this comment also states the position rule V08 needs — a drop lands DropForwardStuds in
-- front of the player's OWN character, read on the server. A client-supplied position drops the win
-- condition through a wall or at a teammate's feet across the barrio.

-- src/shared/Remotes.luau:313-322 — RequestCancelSearch, abridged
--[[
	V03. Also argument-free: it means "I let go", and the server already knows whose hold it is.

	SEPARATE FROM `RequestSearch` RATHER THAN A TOGGLE ON IT. A toggle desynchronises the moment a
	packet is dropped or a token is refused ... Two remotes make each message idempotent.
]]
-- NOTE: precedent 3, and the budget argument V08's drop copies — a refused CANCEL "reads as the game
-- ignoring their input, the worse of the two failures, and the one a player blames the game for".
-- That is why RequestDropItem is priced at Capacity 6 / 0.5 rather than like the throw's 3 / 0.2.

-- src/shared/Remotes.luau:270-286 — RequestTrialThrow, abridged
--[[
	C22. A throw INSIDE a trial, and it is a separate remote from `RequestThrowSalt` on purpose.

	§9.1 asks that the player "learn to throw salt", and they could not: `ItemService` resolves every
	throw through `pure/SaltThrow` against `RoundService.GetPhase()`, and a trial runs while the phase
	is IDLE.

	THE TWO WAYS TO FIX IT WERE A NEW REMOTE OR A LOOSER `ItemService`, AND THE LOOSER SERVICE IS THE
	ONE THAT WOULD HAVE HURT. Relaxing the phase gate means the salt system starts consulting trial
	state to decide a live round's throws — coupling the two services this entire feature exists to
	keep apart, on the 🔒 surface, for a tutorial. This remote costs one budget entry and couples
	nothing.

	... both remotes resolve through the SAME `SaltThrow.inCone`, so the throw a player learns here is
	the throw that works in a round.
]]
-- IMPORTANT: THE TRIAL-ONLY SIBLING THIS CHUNK'S BRIEF NAMES. V08 must not merge the two, must not
-- relax ItemService's phase gate, and must keep `inCone` shared — Step 1.3 retargets TrialService to
-- `ItemThrow.inCone` and changes nothing about the function.
-- IMPORTANT: "one budget entry and couples nothing" is the standard V08's `RequestDropItem` is
-- measured against, and it meets it.
-- NOTE: this comment mentions `pure/SaltThrow` twice; Step 1.3 must update both spellings or the file
-- describes a module that no longer exists.

-- .claude/scripts/check-secrecy.mjs:70-73
-- export const REVEAL_ALLOWLIST = new Map([
--   ['RoundEnded', 'the round is over — the reveal is the point (spec §4.8)'],
--   ['RoleAssigned', 'fired to exactly one player, carrying only that player\'s OWN role (spec §4.2)']
-- ])
-- IMPORTANT: TWO NAMES, BOTH SERVER→CLIENT. The allowlist exempts a CALL that legitimately carries
-- the role; `RequestDropItem` is client→server and carries nothing, so it has NO business here. What
-- a new up-remote actually costs is a Config.AntiCheat.Budgets entry (pinned both directions by
-- tests/anti-cheat-budgets.test.luau) and an inline AntiCheatService.Consume (check:ratelimit).
-- Neither is enforced by check:secrecy. Stated because the chunk brief raised it the other way round.
