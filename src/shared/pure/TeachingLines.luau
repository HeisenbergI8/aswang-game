--!strict
--[[
	TeachingLines — which one-liner, and has this player already seen it (C23, §10).

		resolve(cueId, seen) -> string?     -- nil means "already taught, or not a cue"

	C23's DONE CONDITION IS A PROPERTY, NOT A FEATURE: "every first-time interaction has exactly one
	line; none repeat." Exactly-one and never-again are the two things a hand-rolled `if seen then`
	in four different services would get subtly wrong in at least one of them, and the symptom — a
	line that repeats every round — is the "wall of text" §10 names as the failure, arriving by
	accretion rather than by design.

	NO `script.Parent` REQUIRES (tests/README.md); the cue union is re-declared and is structurally
	identical to `Types.TeachingCueId`.

	COPY LIVES HERE, WITH THE RULE THAT SELECTS IT. §10 gives one of these verbatim ("Salt burns the
	aswang — throw it to reveal and stun"), and keeping the four in one table is what makes "exactly
	one line per interaction" something a reader can check by looking rather than by grepping four
	services.

	FOUR ENTRIES, AND THE TABLE IS CLOSED. C23's row lists exactly four moments. A fifth is a design
	decision, not a copy edit — every line added past the point of need is the wall of text arriving
	one sentence at a time, which is the specific way this failure mode actually happens.
]]

export type TeachingCueId =
	"CUE_FIRST_SALT"
	| "CUE_FIRST_GHOST_DEATH"
	| "CUE_FIRST_TRANSFORM_SEEN"
	| "CUE_FIRST_TWO_PERSON"

local TeachingLines = {}

local COPY: { [string]: string } = {
	-- §10, verbatim: "Do not assume players know salt stops an aswang."
	CUE_FIRST_SALT = "Salt burns the aswang — throw it to reveal and stun.",
	-- §4.7: a ghost can still contribute. Without this, dying reads as the round being over for you,
	-- and a player who thinks they are done alt-tabs instead of helping.
	CUE_FIRST_GHOST_DEATH = "You can still help — haunt the tasks your friends are working on.",
	-- THE TELL, and the one line here that must not say who. "That" is doing load-bearing work:
	-- MonsterTransformed is public by design and names the transformed character to every client, but
	-- this line is shown to a player who is ALREADY WATCHING it happen. It teaches what they are
	-- seeing; it must never become a sentence that reports a transform they missed.
	CUE_FIRST_TRANSFORM_SEEN = "That is the tell. Run, or salt it.",
	CUE_FIRST_TWO_PERSON = "This one needs two. Wait for someone.",
}

--[[
	`seen` is passed in and this module holds nothing — the same shape as TrialTimeline's `fired`, and
	for the same reason. The set lives in TeachingService, which is where it can survive a rejoin and
	where C40 will move it into the profile.

	AN UNKNOWN ID RETURNS nil RATHER THAN ERRORING. A caller passing a cue that no longer exists —
	a service kept after a line was cut — should teach nothing, not crash a service on the 🔒 surface.
]]
function TeachingLines.resolve(cueId: string, seen: { [string]: boolean }): string?
	if seen[cueId] then
		return nil
	end

	return COPY[cueId]
end

-- The closed set, exposed so the test can assert the table's size rather than trusting a hand count,
-- and so a service can validate an id before sending it.
function TeachingLines.ids(): { string }
	local out: { string } = {}

	for id in COPY do
		table.insert(out, id)
	end

	table.sort(out)

	return out
end

return TeachingLines
