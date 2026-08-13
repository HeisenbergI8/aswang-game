--!strict
--[[
	TaskParticipants — how many people are really doing this task? (§4.4 + Amendment A2, C10)

		count(weights, fullWeight)            -> how many are contributing in full
		meets(weights, required, fullWeight)  -> is that enough

	THIS MODULE EXISTS TO INHERIT A PROPERTY RATHER THAN TO RESTATE ONE.

	Amendment A2, in its own words: *"C10's participant count must be derived from the same weights,
	so that it inherits the property instead of restating it."* The property is
	`server/pure/TaskWeight.luau`'s — for any given PlayerState, weight does not vary by Role — and
	the way this module inherits it is by taking NUMBERS. A role cannot reach here. There is no
	parameter for one, no branch that could read one, and `tests/task-participants.test.luau`
	composes the two modules so a role branch introduced in either goes red in this one.

	WHY IT MATTERS MORE HERE THAN ANYWHERE ELSE. A2 calls the two-person task "the sharpest case": a
	survivor and the Aswang standing at a task that produces nothing is an INSTANT reveal with nothing
	to deduce — strictly worse than the frozen hold bar the amendment was written to delete. §4.4's
	own description of this task ("the Aswang can 'help' you and then betray you") only works if the
	help is real, and this file is where "real" is defined.

	FULL CONTRIBUTORS ONLY, AND THAT SETTLES C15 IN ADVANCE. A GHOST weighs
	Config.Ghost.TaskContributionMult (0.25) against a FullContributionWeight of 1, so two ghosts do
	not open a two-person task. §4.4 asks for "2 survivors present"; §4.7 asks ghosts to "still
	matter", not to substitute for the living. `tests/config.test.luau` pins the relation between
	those two numbers, because it is the whole of what separates those two sentences.

	NO `script.Parent` REQUIRES and no Roblox datatypes — a list of numbers, so Lune runs it.
]]

local TaskParticipants = {}

-- `>=`, not `==`. A weight above full is not a state this game produces today, and a future one that
-- did (a buff, a two-handed prop) should count as a participant rather than silently stop counting.
function TaskParticipants.count(weights: { number }, fullWeight: number): number
	local total = 0

	for _, weight in weights do
		if weight >= fullWeight then
			total += 1
		end
	end

	return total
end

function TaskParticipants.meets(weights: { number }, required: number, fullWeight: number): boolean
	return TaskParticipants.count(weights, fullWeight) >= required
end

return TaskParticipants
