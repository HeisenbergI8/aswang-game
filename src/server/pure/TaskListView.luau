--!strict
--[[
	TaskListView — which five task points is this player TOLD about? (§4.4 + Amendment A2, C12)

		forPlayer(realIds, decoyIds, role) -> { string }

	C12 IS AN INFORMATION-CHANNEL LIE AND NOTHING ELSE.

	§4.4's original wording had the Aswang's task progress not count. Amendment A2 reversed that
	mechanism while keeping its goal, because the original BUILDS the oracle it was meant to prevent:
	task progress belongs to the world, a task's fill is legible to anyone standing at the point, and
	standing at a point costs one keypress. A frozen bar names the monster in two seconds, repeatably.

	So: the Aswang's hands do exactly what everyone else's do, counted in full
	(`server/pure/TaskWeight.luau`). What it is TOLD is false, and this file is the whole of the lie.

	IT IS NOT A SECRET AND IT MUST NEVER BE TREATED AS ONE. `ActiveTaskPoint` tags replicate, so a
	compromised client reads the true five straight off CollectionService and defeats this in one
	line. An exploit audit recorded that limit and it is not fixable at this layer. What this buys is
	an HONEST Aswang paying real walking time and real position for a list it cannot trust — A2's
	"it can be sent to points nobody needs" — and no balance decision may depend on more than that.

	THE LENGTH IS THE PART THAT NEEDS CODE.

	A three-line `if` would be enough if the decoy draw always returned as many points as the real
	one. It does not have to: `TaskSelection.select` returns fewer points when the POOL is genuinely
	smaller, and a shown list of four against a real five is a role oracle measurable with `#` — no
	inference, no timing, just a number the client already has. So the decoy is truncated or padded to
	the real list's length here, once, where a test can enumerate it.

	PADDING USES REAL IDS, and that is the least-bad option rather than a good one. It means a
	degenerate map (a pool too small to draw a distinct decoy) shows the Aswang some genuine points.
	The alternatives are worse: padding with repeats puts a duplicate in the list, which is itself a
	tell, and padding with invented names sends the Aswang to a point that does not exist. A pool that
	small is already warned about loudly by TaskService and is already an unwinnable round.

	`table.clone` on the way out, both branches, so a caller cannot mutate this round's real task list
	by editing what it was handed.

	NO `script.Parent` REQUIRES and no Roblox datatypes — strings, so Lune runs it. The union is
	re-declared locally; Luau unions are structural.
]]

export type Role = "SURVIVOR" | "ASWANG"

local TaskListView = {}

function TaskListView.forPlayer(realIds: { string }, decoyIds: { string }, role: Role): { string }
	if role ~= "ASWANG" then
		return table.clone(realIds)
	end

	local shown = table.clone(decoyIds)

	-- Truncate. A longer decoy is the ordinary case only if somebody tunes the draw counts apart.
	while #shown > #realIds do
		table.remove(shown)
	end

	-- Pad. See the header: real ids, deliberately, in a case that only a broken map reaches.
	local index = 1

	while #shown < #realIds do
		table.insert(shown, realIds[index])
		index += 1
	end

	return shown
end

return TaskListView
