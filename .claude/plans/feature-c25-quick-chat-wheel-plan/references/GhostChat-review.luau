--!strict
--[[
	REVIEW — src/shared/pure/GhostChat.luau:43-91

	THE SINGLE MOST IMPORTANT FILE FOR C25, and the conclusion is that C25 must add nothing to it.
	This module already answers "who may hear this" for text chat, and quick chat is the same
	question with a different transport.
]]

-- The four states a speaker or listener can be in. C25 needs no fifth.
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

function GhostChat.isLivingSide(state: PlayerState): boolean
	return state == "ALIVE" or state == "LOBBY"
end

-- IMPORTANT: this is the function QuickChatService's broadcast loop calls, unchanged. Reusing it is
-- the plan's Phase 2 in one line, and the alternative — a `shouldDeliverQuickChat` beside it — is the
-- exact failure the module's own header describes: an earlier single-wall version of this rule
-- delivered GHOST -> SPECTATOR and only an audit caught it. A hand-rolled `if` in a new service
-- would have reintroduced that cell with nothing watching.
function GhostChat.shouldDeliver(senderState: PlayerState, recipientState: PlayerState): boolean
	return GhostChat.isLivingSide(senderState) or senderState == recipientState
end

--[[
	NOTE — the equality term answers C25's ghost question for free.

	  GHOST -> GHOST      true    a ghost gets a wheel among the other ghosts
	  GHOST -> ALIVE      false   the four-word rule; the dead never reach the living
	  ALIVE -> GHOST      true    information flows DOWN, always. §4.7's retention argument
	  GHOST -> SPECTATOR  false   a spectator is a mid-round arrival, so the ghost channel stays shut

	No new rule was needed. That is the return on having written this as a sixteen-cell predicate.

	IMPORTANT — C25 must NOT confuse "may a ghost be HEARD" with "may a ghost ACCUSE". This module
	answers only the first. The second is refused in `pure/QuickChatPhrases` via `GhostMay = false`,
	and for an unrelated reason: a ghost has no server character, so there is no server-owned position
	to resolve "nearest" from. Two different questions, two different modules, deliberately.

	NOTE — the header's "It is callable by any client and that is fine" argument transfers verbatim to
	`pure/QuickChatPhrases`: eight author-written strings and a division, over inputs no client
	supplies. There is no seed here and none there.

	QUESTION — resolved during planning, recorded because it is the obvious objection: does quick
	chat make "who has sent recently" a denser liveness signal than text chat, and does that cross
	Amendment A3's line? Answer: it is the same signal this predicate has permitted since C15, and it
	is denser only in the sense that a thumb press is faster than typing. C25 does not widen the
	channel. The genuinely NEW assertion is the accusation naming a third party as alive, which is in
	the plan's Follow Up 8 as a GATE 1 question rather than a code change.
]]
