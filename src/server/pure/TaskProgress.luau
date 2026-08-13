--!strict
--[[
	TaskProgress — how far did one task point get in the last server tick? (§4.4, C08)

		strongestWeight(weights)                     -> weight
		tick(progress, elapsed, weight, holdTime)    -> { Progress, Completed }

	THE SHAPE THE OTHER THREE TASK TYPES COPY. C09 and C10 differ in what produces a `weight` and in
	nothing else; the accumulation, the boundary and the clamp are here once.

	WHY THE RATE IS A MAXIMUM AND NOT A SUM — the single decision in this file that is not obvious.

	A summed rate is the natural design: three survivors on one task, three times the speed. It also
	makes the bar's speed a function of HOW MANY people are contributing, which turns any per-player
	difference in weight into arithmetic a bystander can read off a bar.

	Under Amendment A2 the Aswang's weight is no longer one of those differences — it contributes in
	full, and `pure/TaskWeight.luau` holds that as an enumerated grid. So the max rule is no longer the
	thing standing between this game and a role oracle; it stands between the game and the NEXT such
	difference, and C15's ghosts are already one (§4.7's 0.25). A ghost helping a survivor changes
	nothing observable under a max and would be plainly visible under a sum.

	§4.4 also gets what it asked for on its own terms — the task takes HoldTime whether one person or
	four is doing it, so it "forces you to stand still and vulnerable" for a fixed, predictable,
	ambushable eight seconds.

	C15's ghosts fall out of the same rule for free: a ghost's weight is Config.Ghost.TaskContributionMult
	(0.25), so a ghost alone is slow and a ghost helping a survivor is neither faster nor slower than the
	survivor alone. §4.7 asks for "they still matter", not "they stack".

	NO `script.Parent` REQUIRES and no Roblox datatypes: plain numbers only, so Lune can run this.
]]

export type Result = {
	Progress: number,
	Completed: boolean,
}

local TaskProgress = {}

-- The strongest contributor present, or 0 when nobody is. An EMPTY list must return 0 rather than
-- erroring: "nobody is standing here" is the normal state of four of the five task points.
function TaskProgress.strongestWeight(weights: { number }): number
	local best = 0

	for _, weight in weights do
		if weight > best then
			best = weight
		end
	end

	return best
end

--[[
	One tick. `elapsed` is SERVER seconds since the last tick — not a count of requests, not a client
	timestamp — which is the whole of why spamming RequestTaskProgress gains nothing (C08's stated Done
	condition). A thousand requests a second and one request a second accumulate identically.

	FOUR GUARDS, and each one is a real state rather than defensive padding:

	  · already complete   — a completed task never moves again, and never re-fires completion
	  · weight <= 0        — nobody eligible is present. FREEZE, do not decay: progress belongs to the
	                         WORLD, not to the player (§4.4 anti-frustration), so a survivor who dies
	                         at 90% leaves 90% for whoever arrives next. Decay would recreate exactly
	                         the "a dead player's task is now unwinnable" class §4.4 deletes.
	  · elapsed <= 0       — os.clock() is not guaranteed monotonic across a server's lifetime;
	                         TokenBucket carries the same guard for the same reason
	  · holdTime <= 0      — a division by zero. It cannot happen through Config, and "cannot happen"
	                         is how a nan reaches a client and a bar renders empty forever.
]]
function TaskProgress.tick(
	progress: number,
	elapsed: number,
	weight: number,
	holdTime: number
): Result
	local current = math.clamp(progress, 0, 1)

	if current >= 1 then
		return { Progress = 1, Completed = true }
	end

	if weight <= 0 or elapsed <= 0 then
		return { Progress = current, Completed = false }
	end

	if holdTime <= 0 then
		return { Progress = 1, Completed = true }
	end

	local updated = math.clamp(current + (elapsed * weight) / holdTime, 0, 1)

	return { Progress = updated, Completed = updated >= 1 }
end

return TaskProgress
