--!strict
--[[
	TaskResolve — which task point is this player at? (§4.4, C08)

		(points, position, range) -> (id, anyInRange)

	THE FUNCTION THAT DECIDES WHAT `RequestTaskProgress` MEANS. The remote carries no arguments, so
	"which point" is answered here, from the server's own copy of the world, and never by the client.

	WHY NEAREST-INCOMPLETE RATHER THAN FIRST-MATCH — this is a soft-lock fix, and the reasoning it
	replaces was wrong in a way that every check in the repo passed.

	The original resolved to the first in-range point in table order, resting on
	`Config.Tasks.PresenceRangeStuds * 2 < MinSpacingStuds` to guarantee only one point could be in
	range. That guarantee does not exist: `MinSpacingStuds` is a REQUEST to `shared/pure/TaskSelection`,
	whose fallback pass drops spacing rather than return a round with too few tasks. An audit measured
	twelve points in one 30x30 room — 2000 of 2000 draws put two selected points inside one radius.

	The failure was silent and fatal. A player standing on an incomplete point B, while also
	overlapping a completed point A that happened to come first in table order, resolved to A and was
	refused — silently, and correctly so, because naming the refusal would leak. The round stuck at 4/5
	and the gate never opened.

	Distance is deterministic and is the answer a player expects, so overlapping selections became
	untidy instead of unwinnable. Table order now decides nothing.

	`anyInRange` is returned separately so the caller can tell "nowhere near a task" from "everything
	near you is already done" WITHOUT this module knowing what a verdict is. Both are silent to the
	client; the distinction is for the server log.

	NO `script.Parent` REQUIRES and no Vector3 — positions are plain { X, Y, Z } tables so Lune can run
	this. TaskService converts at the call site, exactly as it does for TaskSelection.
]]

export type Vec3 = { X: number, Y: number, Z: number }

export type Point = {
	Id: string,
	Position: Vec3,
	Completed: boolean,
}

local TaskResolve = {}

local function distance(a: Vec3, b: Vec3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z

	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--[[
	TIES GO TO THE LOWER Id, and that matters more than it looks.

	Two points at exactly equal distance is not a hypothetical once a map packs anchors together, and
	`<` alone would let table order decide it again — reintroducing, in a rare case, the whole bug this
	function exists to remove. Sorting the tie by Id makes the answer a pure function of the inputs,
	which is the property the test can actually assert.
]]
function TaskResolve.at(points: { Point }, position: Vec3, range: number): (string?, boolean)
	local bestId: string? = nil
	local bestDistance = math.huge
	local anyInRange = false

	for _, point in points do
		local d = distance(point.Position, position)

		--[[
			`not (d <= range)`, NOT `d > range`, AND THE DIFFERENCE IS NaN.

			Every comparison against NaN is false, so `d > range` lets a NaN distance fall THROUGH the
			guard — past it the point sets `anyInRange`, then fails both distance tests, and the caller
			logs ALREADY_COMPLETE for a player who is nowhere near anything. Inverting the comparison
			makes the guard total: NaN fails `d <= range`, so `not (...)` is true and it is skipped.

			A NaN distance needs a NaN character position, which Roblox generally refuses to replicate
			— so this is a guard against a state that may be unreachable rather than a fixed bug. It
			costs one word, and `tests/task-resolve.test.luau` enumerates NaN and both infinities
			alongside the finite cases rather than trusting that reasoning.
		]]
		if not (d <= range) then
			continue
		end

		anyInRange = true

		if point.Completed then
			continue
		end

		if d < bestDistance or (d == bestDistance and bestId ~= nil and point.Id < bestId) then
			bestId = point.Id
			bestDistance = d
		end
	end

	return bestId, anyInRange
end

return TaskResolve
