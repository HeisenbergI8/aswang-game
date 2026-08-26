--!strict
--[[
	What a mid-round arrival becomes (§6.4, C15) — the full grid.

	THE CELL THIS FILE EXISTS FOR is `ACTIVE x dealt-in x ALIVE -> ALIVE`. Before C15 that case returned
	SPECTATOR, and a SPECTATOR is uncounted, bodiless and — since C05 — unkillable. So hearing the
	transform and pulling the plug made you invulnerable for the rest of the round, which is a hard
	counter to the entire monster. It is one cell in a table and it deleted the game.

	The second thing asserted here is that the rule is "stay as you were" and NOT "come back a dead player":
	a surviving husk returns its owner to ALIVE. Those two outcomes are one `if` apart in the service
	and the difference is the whole design decision, so it is pinned rather than assumed.
]]

local RejoinResolve = require("../src/shared/pure/RejoinResolve")

type PlayerState = RejoinResolve.PlayerState
type RoundPhase = RejoinResolve.RoundPhase

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
local STATES: { PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }

local function resolve(phase: RoundPhase, wasDealtIn: boolean, stored: PlayerState?): PlayerState
	return RejoinResolve.evaluate({
		Phase = phase,
		WasDealtIn = wasDealtIn,
		StoredState = stored,
	})
end

--------------------------------------------------------------------------------
-- THE EXPLOIT, and the cell that closes it.
--------------------------------------------------------------------------------

check(
	"a dealt-in ALIVE player who reconnects mid-round is ALIVE again, not SPECTATOR",
	resolve("ACTIVE", true, "ALIVE") == "ALIVE",
	`got {resolve("ACTIVE", true, "ALIVE")}`
)

check(
	"...and specifically NOT a dead player — quitting does not convert a survivor into a dead player",
	resolve("ACTIVE", true, "ALIVE") ~= "DEAD"
)

check(
	"a dealt-in player whose husk was killed while away comes back a DEAD",
	resolve("ACTIVE", true, "DEAD") == "DEAD"
)

check(
	"a genuinely new mid-round arrival is still a SPECTATOR",
	resolve("ACTIVE", false, nil) == "SPECTATOR"
)

--------------------------------------------------------------------------------
-- The full PHASE x DEALT-IN x STORED grid. 5 x 2 x 5 = 50 cells.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, wasDealtIn in { true, false } do
		--[[
			WRAPPED IN A TABLE, and this is not style. Written as
			`{ nil, "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }` the leading `nil` is not iterated by a
			generic `for`, so the "server has no stored state" column silently never ran — the grid
			reported 40 cells while claiming 50, and the one case that fails CLOSED was the one missing.
			Caught by counting the assertions rather than by reading the loop.
		]]
		local storedOptions: { { Value: PlayerState? } } = {
			{ Value = nil },
			{ Value = "LOBBY" },
			{ Value = "ALIVE" },
			{ Value = "DEAD" },
			{ Value = "SPECTATOR" },
		}

		for _, option in storedOptions do
			local stored = option.Value
			local got = resolve(phase, wasDealtIn, stored)

			local expected: PlayerState
			if phase == "IDLE" or phase == "INTERMISSION" then
				expected = "LOBBY"
			elseif not wasDealtIn then
				expected = "SPECTATOR"
			elseif stored == nil or stored == "LOBBY" then
				expected = "SPECTATOR"
			else
				expected = stored
			end

			check(
				`{phase} / dealtIn={wasDealtIn} / stored={stored or "nil"} -> {expected}`,
				got == expected,
				`got {got}`
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Properties that survive a rewrite of the grid's expectations.
--------------------------------------------------------------------------------

--[[
	BETWEEN ROUNDS, NOTHING ELSE MATTERS. Whatever the server remembers, an arrival during IDLE or
	INTERMISSION is a lobby player — they are about to be dealt in by `setAllPlayerStates` anyway, and
	returning a stale ALIVE would put them in `aliveCount()` before the draw.
]]
do
	local violations = 0

	for _, phase in { "IDLE", "INTERMISSION" } :: { RoundPhase } do
		for _, wasDealtIn in { true, false } do
			for _, stored in STATES do
				if resolve(phase, wasDealtIn, stored) ~= "LOBBY" then
					violations += 1
				end
			end
		end
	end

	check("every arrival between rounds is LOBBY", violations == 0, `{violations} violations`)
end

--[[
	ENDING IS UNDERWAY, and this is the easy one to get wrong. The round is still resolving, the reveal
	is on screen, and `setAllPlayerStates` has not run. An arrival here becoming LOBBY would hand them a
	body among the corpses and put them in the next headcount a phase early.
]]
check("ENDING is treated as underway, not as a lobby", resolve("ENDING", false, nil) == "SPECTATOR")

check(
	"a dealt-in ALIVE player arriving during ENDING is still ALIVE",
	resolve("ENDING", true, "ALIVE") == "ALIVE"
)

--[[
	NEVER INVENT A BODY. `mayHaveBody` admits LOBBY and ALIVE; during a live round, a player the server
	cannot account for must not resolve to either. This is the fail-closed direction stated as a
	property, so a future edit that "helpfully" defaults an unknown player to ALIVE fails here.
]]
do
	local violations = 0

	for _, phase in { "STARTING", "ACTIVE", "ENDING" } :: { RoundPhase } do
		-- Not dealt in, or dealt in with nothing stored: both are "the server cannot account for you".
		if resolve(phase, false, nil) ~= "SPECTATOR" then
			violations += 1
		end

		if resolve(phase, true, nil) ~= "SPECTATOR" then
			violations += 1
		end
	end

	check(
		"an unaccountable player never resolves to a state that has a body",
		violations == 0,
		`{violations} violations`
	)
end

--[[
	THE ANTI-LAUNDERING PROPERTY. Reconnecting must never IMPROVE your standing. A dead player may not come
	back alive, a spectator may not come back alive, and nothing may come back as anything it was not.
]]
do
	local violations = 0

	for _, phase in { "STARTING", "ACTIVE", "ENDING" } :: { RoundPhase } do
		for _, stored in STATES do
			local got = resolve(phase, true, stored)

			if got == "ALIVE" and stored ~= "ALIVE" then
				violations += 1
			end
		end
	end

	check(
		"reconnecting never upgrades a player to ALIVE they were not",
		violations == 0,
		`{violations} violations`
	)
end

--------------------------------------------------------------------------------
-- Purity.
--------------------------------------------------------------------------------

do
	local input =
		{ Phase = "ACTIVE" :: RoundPhase, WasDealtIn = true, StoredState = "ALIVE" :: PlayerState? }
	local first = RejoinResolve.evaluate(input)
	local second = RejoinResolve.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check(
		"evaluate does not mutate its request",
		input.WasDealtIn == true and input.StoredState == "ALIVE"
	)
end

if failures > 0 then
	error(`{failures} rejoin-resolve assertion(s) failed`, 0)
end

print(`  PASS  rejoin-resolve: {checked} assertions over the full phase x dealt-in x stored grid`)
