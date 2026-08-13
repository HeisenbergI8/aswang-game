--!strict
--[[
	The body rule and the kill-target rule, over all four player states.

	Eight cells, written out in full. That is worth more than a spot check because the failure this
	file exists to catch is a DENYLIST — `state ~= "SPECTATOR"` — which passes every spot check anyone
	would think to write and fails exactly on the two rows nobody tests.
]]

local PlayerBody = require("../src/shared/pure/PlayerBody")

type PlayerState = PlayerBody.PlayerState

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

local ALL: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }

--------------------------------------------------------------------------------
-- mayHaveBody — every state, stated
--------------------------------------------------------------------------------

local BODY: { [PlayerState]: boolean } = {
	LOBBY = true, -- waiting between rounds, walking around the plaza
	ALIVE = true, -- dealt into the round
	-- C15 flipped this row to true and an exploit audit flipped it back. A SERVER body replicates, and
	-- a player-named Model per dead player names the dead set to every client — the Aswang is never a
	-- ghost, so each one eliminates a candidate. The position §4.7 needs comes from the ghost's own
	-- client instead. `mayBeKilled(GHOST)` stayed false through both flips; that is the assertion below.
	GHOST = false,
	SPECTATOR = false, -- joined mid-round. THE C04 REMNANT.
}

for _, state in ALL do
	check(
		`mayHaveBody({state})`,
		PlayerBody.mayHaveBody(state) == BODY[state],
		`expected {BODY[state]}, got {PlayerBody.mayHaveBody(state)}`
	)
end

--------------------------------------------------------------------------------
-- mayBeKilled — §4.3's "both alive", as an allowlist of exactly one
--------------------------------------------------------------------------------

for _, state in ALL do
	check(
		`mayBeKilled({state})`,
		PlayerBody.mayBeKilled(state) == (state == "ALIVE"),
		`state={state}`
	)
end

--------------------------------------------------------------------------------
-- The properties the cells exist to express
--------------------------------------------------------------------------------

-- The C04 warning, verbatim: a mid-round joiner is uncounted, and must therefore also be bodiless and
-- unkillable. Uncounted AND present is the alt-account exploit.
check(
	"a spectator has neither a body nor a kill target on it",
	not PlayerBody.mayHaveBody("SPECTATOR") and not PlayerBody.mayBeKilled("SPECTATOR")
)

-- The row a denylist gets wrong. C15 makes GHOST real; a ghost that can be killed again is a ghost
-- that can be farmed for kill credit.
check("a ghost cannot be killed", not PlayerBody.mayBeKilled("GHOST"))

-- mayBeKilled must stay strictly narrower than mayHaveBody. If they ever coincide, someone has merged
-- them, and the LOBBY row is where that shows up: a lobby player has a body and is not a target.
check(
	"the kill allowlist is strictly narrower than the body allowlist",
	PlayerBody.mayHaveBody("LOBBY") and not PlayerBody.mayBeKilled("LOBBY")
)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print(`  PASS  player-body: {checked} cells and properties`)
