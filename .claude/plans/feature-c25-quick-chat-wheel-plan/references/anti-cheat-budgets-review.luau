--!strict
--[[
	REVIEW — tests/anti-cheat-budgets.test.luau:1-24, 26-50

	Read to answer: does C25 have to touch the hand-copied up-remote list? ANSWER: no — and that is a
	conclusion reached by reading the list, not by assuming, because this is the file the task brief
	says has bitten twice.
]]

--[[
	WHY THE NAME LIST IS DUPLICATED HERE, AND WHY THAT IS THE LEAST-BAD OPTION
	--------------------------------------------------------------------------
	`src/shared/Remotes.luau` calls `game:GetService` at module scope, so Lune cannot require it —
	there is no DataModel. The list below is therefore a hand copy, and a hand copy can drift.

	It is still worth having, because drift in the direction that matters is caught from the other
	side: `check:remotes` fails on any remote used but not declared in Remotes.luau, and the
	EXTRA_BUDGETS assertion below fails on any budget naming a remote this list does not carry. What
	survives both is the narrow case of a remote added to Remotes.luau and to nothing else ...

	The clean fix is a check script that parses both files. It is named in the plan's Follow Ups
	rather than built here, because C02 is not the chunk that should be growing the harness.
]]

-- Hand copy of Remotes.EVENTS_UP, last synced at C22. See the header for why.
local UP_REMOTES = {
	"RequestTaskProgress",
	"RequestTimingStop",
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",   -- NOTE: already present. C25 adds nothing to this list.
	"ReportGhostPosition",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
	"RequestStartTrial",
	"RequestEndTrial",
	"RequestTrialThrow",
}

--[[
	IMPORTANT — THIS IS WHY C25 DECIDED AGAINST A THIRD REMOTE FOR THE WORLD PING, in part.

	The gap this file's header describes exactly — "a remote added to Remotes.luau and to nothing
	else" — is the failure mode a ping remote would have walked into. It would be declared correctly,
	pass `check:remotes`, need a Config budget, and then fail this suite only if somebody remembered
	to add it here. The header says the extra-budget assertion catches a budget with no list entry;
	it does NOT catch a list with no entry for a declared remote, because nothing here reads
	Remotes.luau.

	So a third remote costs a Config entry, a line here, and a real chance of an unbudgeted handler
	that `AllowUnbudgetedRemote = false` refuses silently at runtime. The ping being a derived field
	costs none of that. The security argument in Remotes-review.luau is the primary reason; this is
	the maintenance one, and they point the same way.

	NOTE — C25's plan adds two RELATIONSHIP assertions to this file rather than a name:
	  · the burst must cover a short exchange (Capacity >= 3), because a limiter that refuses the
	    third message in a conversation has throttled communication rather than an exploiter;
	  · a refilled token must arrive no faster than a message expires, so a player cannot hold the
	    HUD full.
	Both are in the spirit of the section this file already calls "The relationships. A limiter
	tighter than legitimate play is a gameplay bug."

	IMPORTANT — the C25 comment added to the `RequestQuickChat` entry must say that the LIMITER IS THE
	SECOND LINE OF DEFENCE for the accusation phrase and not the first. Somebody tuning this budget at
	C41 will otherwise reasonably conclude that loosening it is a pure UX win. It is not: line of
	sight is what stops the phrase being a proximity radar, and if that ever changes, this number
	becomes load-bearing in a way it is not today.

	QUESTION — for lessons-review, not for this chunk: this is the THIRD chunk to read the header's
	"the clean fix is a check script that parses both files" and route around it. C02 deferred it, C22
	re-synced by hand, C25 verified by hand. That is a recurring cost now rather than a hypothetical
	one. In the plan's Follow Up 9.
]]
