--!strict
--[[
	ContainerLayout — which container holds which item, as a pure function. (V03, §4.4)

		(containerCount, counts, nextInt) -> Layout

	WHY THIS FILE IS UNDER src/server/pure/ AND NOT src/shared/pure/
	----------------------------------------------------------------
	`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module there is
	require-able AND CALLABLE by any client. That is harmless for logic — logic is never secret — and
	it is the whole game for this one.

	Algorithm + inputs + seed = this round's layout. A client that can call this function AND supply
	its inputs knows where the buntot pagi is before anyone has opened anything: no remote to
	intercept, nothing on the wire, and nothing for `check:secrecy` to see. §6.2 names the layout seed
	as server-only state in the same breath as the Aswang's identity, and for the same reason.

	`src/server` maps to ServerScriptService, which does not replicate. Two rules are still enforced at
	the CALL SITE, because defence in depth is the point and the next author may not read this comment:

	  · The RNG is INJECTED, never created here, and SearchService seeds it with `Random.new()` — no
	    argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and
	    both fatal. §4.4 says so in one sentence and it is the sentence this module exists to obey.
	  · The LAYOUT IS NEVER LOGGED, not even under Config.Debug.VerboseLogging. In a Studio solo test
	    the server and client share one output window, so a print of where the buntot pagi is arrives
	    in front of the person playing.

	Lune resolves test requires by FILE PATH and knows nothing about Rojo, so this location costs no
	testability — `tests/container-layout.test.luau` requires "../src/server/pure/ContainerLayout" and
	runs identically. `RoleDraw` and `SearchPool` are here on exactly this argument.

	NO `script.Parent` REQUIRES and no Roblox datatypes, same rule as every other pure module.

	WHY `Contents` IS `{ [number]: string }` AND NOT `{ [number]: Item }`
	---------------------------------------------------------------------
	Because a literal union survives `require` as a SCALAR and does not survive it inside a container.
	The element arrives at the call site as a union of plain `string`s, `::` fails with "none of the
	union options are compatible" because Luau distributes the cast and widens every option, and the
	analyzer reports it in SearchService — naming the wrong file, which is what cost C21 eight failed
	fixes. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.

	So the container holds plain strings and `itemAt` below does the narrowing, which is the lesson's
	stated remedy: a literal in a `return` checked against an annotated return type is narrowing the
	analyzer performs. It also beats a cast on behaviour — an unknown id returns `nil` for the caller
	to drop with a `warn`, where a cast would wave it into a client payload.

	NOTE `check-config.mjs` governs `src/server/`, so this file may not contain a tunable number. That
	is why `counts` is a parameter. It is the right shape anyway: 4/2/1 are §4.4 balance knobs and V16
	is expected to move them.
]]

-- Structurally identical to `Types.ItemType`; Luau unions are structural, so the two are the same
-- type and pass to each other without a cast. Re-declared rather than required, because a pure module
-- that reaches for `Types` stops being runnable from a terminal and the whole point is lost.
export type Item = "SALT" | "BAWANG" | "BUNTOT_PAGI"

-- How many of each item the round places. Read from `Config.Items.*SpawnCount` by the caller.
export type Counts = {
	Salt: number,
	Bawang: number,
	BuntotPagi: number,
}

export type Layout = {
	ContainerCount: number,
	-- Container index -> item id. ABSENT means empty, and most of them are absent: seven items across
	-- fifteen containers is §4.4's whole risk economy — "you will open empty ones, and that is the
	-- point". PLAIN `string` deliberately; read it through `itemAt`.
	Contents: { [number]: string },
	-- How many items actually landed. Equals the item total on a healthy map and is LOWER on a SHORT
	-- one, which is the number the caller warns on.
	Placed: number,
}

local ContainerLayout = {}

--[[
	PLACEMENT PRIORITY, WHICH ONLY MATTERS ON A BROKEN MAP — and matters completely there.

	On a healthy pool every item is placed and the order is invisible. On a SHORT pool (fewer distinct
	containers than items) something has to be dropped, and dropping the wrong thing makes the round
	unwinnable rather than merely thin:

	  1. BUNTOT_PAGI — the only thing in the game that kills the Aswang (§4.6). Drop it and the
	     survivors' second win condition does not exist at all.
	  2. SALT       — the only counterplay, and the only thing that weakens the Aswang toward the
	     state the buntot pagi requires. Drop it and the buntot pagi can never be used.
	  3. BAWANG     — buys time, never safety (§4.6, invariant 4). The one that can be missing while
	     the round still resolves the way it is meant to.

	This does make a SHORT map's contents partly predictable. That is acceptable and not worth
	defending against: a SHORT map is a fault state the caller warns about loudly, and an exploiter who
	knows the layout of a map that cannot be played has won nothing.
]]
local function buildQueue(counts: Counts): { string }
	local queue: { string } = {}

	for _ = 1, counts.BuntotPagi do
		table.insert(queue, "BUNTOT_PAGI")
	end

	for _ = 1, counts.Salt do
		table.insert(queue, "SALT")
	end

	for _ = 1, counts.Bawang do
		table.insert(queue, "BAWANG")
	end

	return queue
end

--[[
	A PARTIAL FISHER-YATES, which is the whole algorithm and is worth naming rather than reading off.

	`order` starts as 1..containerCount. For each slot we swap in one uniformly-chosen element from the
	untouched tail, so after `placeable` iterations the first `placeable` entries are a uniform random
	SUBSET in uniform random ORDER. Two properties fall out for free, and they are exactly the two the
	test asserts:

	  · no container can be double-seeded — a swapped-out index moves into the tail and is never
	    revisited, so the indices written are distinct by construction rather than by a check
	  · every container is equally likely to receive any particular item, including the buntot pagi

	The alternative — draw a random index and retry on collision — is the same distribution with an
	unbounded loop, and an unbounded loop inside `enterStarting` is a round that hangs in STARTING.

	`nextInt(lo, hi)` returns an integer in [lo, hi] INCLUSIVE. The signature matches
	`Random:NextInteger` so the caller passes a one-line adapter and nothing has to be remembered.

	DEGENERATE INPUTS RETURN A SENSIBLE LAYOUT rather than erroring, for RoleDraw's reason: a live
	server that reached one of these has a bigger problem than the draw, and erroring here would leave
	the round in STARTING with no layout and no log.
]]
function ContainerLayout.draw(
	containerCount: number,
	counts: Counts,
	nextInt: (number, number) -> number
): Layout
	local queue = buildQueue(counts)
	local placeable = math.min(#queue, math.max(containerCount, 0))
	local contents: { [number]: string } = {}
	local order: { number } = {}

	for index = 1, containerCount do
		order[index] = index
	end

	for slot = 1, placeable do
		local pick = nextInt(slot, containerCount)

		order[slot], order[pick] = order[pick], order[slot]
		contents[order[slot]] = queue[slot]
	end

	return {
		ContainerCount = containerCount,
		Contents = contents,
		Placed = placeable,
	}
end

--[[
	THE NARROWING FUNCTION, and it is the reason `Contents` holds plain strings.

	An unrecognised id returns nil, which the caller drops with a warn. A cast would have waved it into
	a client payload instead — see the header, and the lesson it cites.
]]
function ContainerLayout.itemAt(layout: Layout, containerIndex: number): Item?
	local id = layout.Contents[containerIndex]

	if id == "SALT" then
		return "SALT"
	elseif id == "BAWANG" then
		return "BAWANG"
	elseif id == "BUNTOT_PAGI" then
		return "BUNTOT_PAGI"
	end

	return nil
end

return ContainerLayout
