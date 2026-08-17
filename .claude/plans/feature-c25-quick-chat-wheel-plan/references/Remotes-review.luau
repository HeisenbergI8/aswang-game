--!strict
--[[
	REVIEW — src/shared/Remotes.luau:20-46 (down), 88-96 (up), 148-176 (up, C21/C22)

	CONCLUSION FOR C25: both remotes already exist, and no third one is needed. The task asked whether
	the world ping needs its own remote; this file is most of the argument that it does not.
]]

-- Server -> Client
local EVENTS_DOWN = {
	-- NOTE: declared since the scaffold, never wired. C25 is the chunk that gives it a handler.
	-- IMPORTANT: it is NOT on `check-secrecy.mjs`'s REVEAL_ALLOWLIST, and it must not be added. Only
	-- RoundEnded and RoleAssigned are on it. That means QuickChatBroadcast's payload keeps being
	-- scanned like any other remote, which is exactly what the plan wants — the payload carries
	-- UserIds and a position, never a role, so it has nothing to be exempted for.
	"QuickChatBroadcast",
}

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	-- NOTE: also already declared, with a budget already in Config. C25 adds NO up-remote.
	"RequestQuickChat",
}

--[[
	IMPORTANT — THE THREE ENTRIES THAT SETTLE THE "DO WE NEED A THIRD REMOTE" QUESTION.

	Remotes.luau:88-90, on `RequestTimingStop`:
	  "NO ARGUMENTS, and that is the whole security design: the server resolves which task from the
	   player's own position ... There is no argument in which a client could name a moment, a
	   position or an outcome."

	Remotes.luau:150-155, on `RequestStartTrial`:
	  "NO ARGUMENTS, deliberately ... There is nothing a client could legitimately name here."

	Remotes.luau:118-136, on `ReportGhostPosition`:
	  "THIS IS THE ONE PLACE IN THE GAME WHERE THE CLIENT OWNS A POSITION, and it is a deliberate
	   trade ... a ghost can claim to stand at a task point it is not at."

	Read together they draw the line C25 sits on. A ping remote carrying a client-named position would
	be the SECOND place a client owns a position — and unlike the ghost case, where the trade bought
	the removal of a replicated body per dead player, this one buys nothing: the sender's position is
	already known to the server. It would purchase a "draw an arrow anywhere" primitive for free,
	including on top of another player, which accuses by geometry while the phrase says something
	innocent.

	So the ping is a DERIVED FIELD on `QuickChatBroadcast`, and `RequestQuickChat` joins the
	argument-light class above with exactly one: a phrase id.
]]

--[[
	NOTE — `GhostRoster`'s entry (Remotes.luau:57-70) is the template for QuickChatBroadcast's own
	comment. Its argument is that what makes a remote safe can be its AUDIENCE rather than its
	contents, and that `check-secrecy.mjs` cannot police an audience because
	`FireClient(player, payload)` in a loop over the wrong list is textually identical to the right
	one. QuickChatBroadcast is in the same position and needs the same sentence.

	NOTE — `TaskListAssigned` (Remotes.luau:31-35) is the precedent for a down-remote whose UNIFORMITY
	is the design: survivors and the Aswang get the same payload shape. QuickChatBroadcast is uniform
	in the same way — every entitled recipient gets the identical table, and the filtering is in who
	receives it, not in what they receive. That matters because a per-recipient payload is what the
	TextService filter path in Step 5.3 would force, and it would break this property.

	QUESTION — resolved: does `QuickChatBroadcast` need a field saying whether the sender is alive, so
	a client can style a ghost's message differently? NO, and it must never get one. See
	Types-review.luau: that is Amendment A3's removed field wearing a different name. A client that
	received the message and is itself a ghost already knows, because the audience rule is what let it
	through.
]]
