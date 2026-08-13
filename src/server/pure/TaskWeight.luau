--!strict
--[[
	TaskWeight — how much does this player's presence advance a task? (§4.4 + Amendment A2, C08)

		(playerState, role, ghostMult) -> weight

	THE ANTI-ORACLE RULE, AND IT IS THE WHOLE REASON THIS IS A MODULE RATHER THAN THREE LINES IN
	TaskService.

		For any given PlayerState, the weight MUST NOT vary by Role.

	That sentence is the entire contract. `tests/task-weight.test.luau` enumerates the full
	`PlayerState × Role` domain — eight cells, every one asserted — so a future change that
	special-cases the Aswang fails a terminal test instead of shipping a role oracle. A comment
	asserting the same thing would not, and this repo has already spent commits deleting comments that
	claimed invariants nobody was checking.

	WHY THE ASWANG CONTRIBUTES IN FULL — this reverses §4.4's original mechanism, and the reversal is
	recorded as Amendment A2 in docs/MVP-SPEC.md rather than decided here.

	§4.4 assigns progress to the WORLD, not to the player, so a task's fill is legible to anyone
	standing at that point — and standing at a point costs one keypress. If the Aswang's holds
	contributed nothing, a survivor could walk up to whoever is holding, tap interact, watch the bar
	sit frozen, and read the monster's identity directly. Repeatable on every player, no inference
	required. §4.4's own stated fear — *"otherwise 'who is standing at tasks' trivially identifies
	it"* — is produced BY the rule that was meant to prevent it.

	The deception lives on the information channel instead: the Aswang is shown a fake task list
	(C12). What it is TOLD is a lie; what it DOES is real and identical to everyone else's.

	NO `script.Parent` REQUIRES and no Roblox datatypes — plain strings and numbers, so Lune runs it.
	The two unions are re-declared locally; Luau unions are structural, so these and the ones in
	Types.luau are the same types and pass to each other without a cast.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
export type Role = "SURVIVOR" | "ASWANG"

local TaskWeight = {}

--[[
	`role` is accepted and deliberately NOT read.

	It would be simpler to leave the parameter out. It is here because its presence is what makes the
	test meaningful: the grid can only assert "weight does not vary by role" if a role can actually be
	passed in. An unused parameter that a test proves is unused is a stronger statement than an absent
	one, and it is the shape a future edit would have to fight to add a role branch.

	GHOST is C15's case and is priced in now because the max rule in `TaskProgress` makes it free:
	a ghost alone is slow, a ghost beside a survivor changes nothing. §4.7 asks for "they still
	matter", not "they stack".

	LOBBY and SPECTATOR are zero — they are not in the round. A player who joins mid-round is a
	SPECTATOR (§6.4) and contributes nothing until the next one deals them in.
]]
function TaskWeight.forPlayer(playerState: PlayerState, _role: Role, ghostMult: number): number
	if playerState == "ALIVE" then
		return 1
	end

	if playerState == "GHOST" then
		return math.max(0, ghostMult)
	end

	return 0
end

return TaskWeight
