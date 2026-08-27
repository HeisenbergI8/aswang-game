--!strict
--[[
	NoiseLog — the bounded history, and nothing that reads it. (V04, §4.4)

		shouldRecord(lastAt, now, minInterval) -> boolean
		append(records, record, limits)        -> a NEW pruned list
		recentSince(records, now, within)      -> a COPY of the recent tail
		withinRadius(a, b, radius)             -> boolean

	SERVER-ONLY BY PLACEMENT, and that is the mirror image of `shared/pure/NoiseModel`'s. The model
	is a price list over numbers `Config` already replicates to every client, so publishing it costs
	nothing. This is the machinery around state that never leaves the server and has no client caller
	now or ever, so `server/pure/` is free. `ContainerLayout` sits here for the sharper version of the
	same reason. Lune resolves by file path, so the suite is identical either way.

	IT KNOWS NOTHING ABOUT WHO. There is no UserId in `Record` and no parameter that carries one —
	the throttle predicate takes a TIMESTAMP, and the caller owns the per-actor table that produced
	it. V13's tracker reads these records and cannot leak an identity that was never written down.

	ORDER IS AN ASSUMPTION AND IT IS A SAFE ONE: `records` is ascending by `At`, because `append` is
	the only writer and `os.clock()` is monotonic. Both prunes rely on it.

	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table (preamble P2).
]]

export type Vec3 = { X: number, Y: number, Z: number }

-- Structurally `Types.NoiseRecord`. `Action` is a plain `string` here rather than the literal union:
-- an element of a LIST arrives at the call site widened, so the union belongs at the boundary that
-- can enforce it — `.claude/lessons/pure-module-unions-widen-in-lists.md`.
export type Record = {
	Action: string,
	Loudness: number,
	Radius: number,
	Position: Vec3,
	At: number,
}

export type Limits = {
	HistorySeconds: number,
	MaxRecords: number,
}

local NoiseLog = {}

local function copyRecord(record: Record): Record
	return {
		Action = record.Action,
		Loudness = record.Loudness,
		Radius = record.Radius,
		Position = { X = record.Position.X, Y = record.Position.Y, Z = record.Position.Z },
		At = record.At,
	}
end

--[[
	HAS THIS ACTOR BEEN QUIET LONG ENOUGH FOR THIS ACTION TO COUNT AGAIN?

	This is the anti-spam guard, and V04 has no other one: no client remote is added, so
	AntiCheatService never sees a noise. A player tapping the search key start/cancel/start still
	makes exactly one search's worth of noise, which is what Step 1.4's SearchTime invariant pins.

	A CLOCK THAT WENT BACKWARDS REFUSES rather than allowing. `os.clock()` will not do that on one
	server, but the failure direction matters: refusing costs one noise event, allowing costs the
	bound.
]]
function NoiseLog.shouldRecord(lastAt: number?, now: number, minInterval: number): boolean
	if lastAt == nil then
		return true
	end

	local elapsed = now - lastAt

	if elapsed < 0 then
		return false
	end

	return elapsed >= minInterval
end

--[[
	APPEND, PRUNE BY AGE, THEN CAP. Returns a NEW list; the input is never mutated, so a caller
	holding the old one holds a consistent snapshot rather than a half-pruned table.

	AGE IS THE BOUND AND THE CAP IS THE NET. If the cap is ever doing the trimming, the window V13
	reads has silently become shorter than `HistorySeconds` and the tracker goes blind on the early
	round with no symptom — `tests/config.test.luau` pins the cap above the worst case the throttles
	allow, precisely so this branch is unreachable in a healthy build.

	THE NEW RECORD IS ALWAYS KEPT. A cap of zero keeps one rather than discarding what it was asked
	to store, because "you told me to record this and I dropped it" is the harder failure to see.
]]
function NoiseLog.append(records: { Record }, record: Record, limits: Limits): { Record }
	local cutoff = record.At - limits.HistorySeconds
	local kept: { Record } = {}

	for _, existing in records do
		if existing.At >= cutoff then
			table.insert(kept, existing)
		end
	end

	table.insert(kept, record)

	local capacity = math.max(limits.MaxRecords, 1)
	local overflow = #kept - capacity

	if overflow > 0 then
		-- Shift the survivors down, then clear the tail. Oldest-first is the only defensible drop:
		-- the newest noise is the one V13 is about to ask about.
		table.move(kept, overflow + 1, #kept, 1)

		for index = #kept, capacity + 1, -1 do
			kept[index] = nil
		end
	end

	return kept
end

--[[
	THE QUERY V13 IS BUILT ON. Returns COPIES, for `AudioCues.oneShotsFor`'s reason: a caller that
	sorted, cleared or edited the result in place would silently rewrite the server's own history,
	and a tracker is exactly the kind of consumer that wants to sort what it was handed.
]]
function NoiseLog.recentSince(records: { Record }, now: number, withinSeconds: number): { Record }
	local cutoff = now - withinSeconds
	local recent: { Record } = {}

	for _, record in records do
		if record.At >= cutoff then
			table.insert(recent, copyRecord(record))
		end
	end

	return recent
end

--[[
	IS `b` INSIDE THE NOISE AT `a`? Squared magnitudes, so no square root runs per listener per
	noise. INCLUSIVE at the boundary, matching `SearchService.nearestContainer`'s `<=`.

	A RADIUS OF ZERO OR LESS IS AUDIBLE TO NOBODY. Without the guard a negative radius squares to a
	positive one and a silent action would be heard by everyone standing on top of it.
]]
function NoiseLog.withinRadius(a: Vec3, b: Vec3, radius: number): boolean
	if radius <= 0 then
		return false
	end

	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z

	return dx * dx + dy * dy + dz * dz <= radius * radius
end

return NoiseLog
