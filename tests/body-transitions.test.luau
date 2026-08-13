--!strict
--[[
	THE BODY TRANSITION TABLE, EXHAUSTIVELY — every state against every cause.

	Written BEFORE the module it tests, which is the whole point. `RoundService` was patched five times
	over four review rounds and every single defect was the same shape: one entry point handled and its
	twin not. A reset was fixed while a disconnect was not; a throttle was added that re-stranded the
	player the previous fix had rescued; a failed load had no retry because only one caller could ever
	reach it. Each fix passed the tests I wrote for it, because I wrote the tests from the bug I had
	just seen.

	Four states × five causes is TWENTY CELLS. Twenty cells enumerated once cost less than five patches,
	and unlike the patches they say what the answer is for the combinations nobody has hit yet.

	The shape is copied deliberately from `tests/round-transitions.test.luau`, which has never had a
	bug: state × event, every cell stated, no case list.
]]

local BodyTransitions = require("../src/shared/pure/BodyTransitions")

type PlayerState = BodyTransitions.PlayerState
type Cause = BodyTransitions.Cause
type Action = BodyTransitions.Action

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

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local CAUSES: { Cause } = { "JOINED", "PHASE_CHANGE", "KILLED", "DIED", "LOAD_FAILED" }

--[[
	THE TABLE. Each cell is the action the server must take, and each is arguable on its own line —
	which is the property a case list can never have.

	  GRANT    load a character if they do not have one
	  REVOKE   take the body away and destroy it
	  KEEP     leave whatever they have alone
	  DEFER    they should have a body but not yet — schedule the load and try again

	`KILLED` is REVOKE for a target and KEEP for everyone else, but the CORPSE is not this module's
	business: MonsterService detaches the character before RoundService is told, so by the time this
	table is consulted there is nothing left to revoke. The cell still reads REVOKE because that is the
	INTENT — "this player does not keep a body" — and stating it here is what stops a future caller
	reversing the order and deleting the corpse, which is a bug this repo has already had.
]]
local EXPECTED: { [string]: Action } = {
	-- LOBBY: between rounds, walking the plaza. Always embodied.
	["LOBBY/JOINED"] = "GRANT",
	["LOBBY/PHASE_CHANGE"] = "GRANT",
	["LOBBY/KILLED"] = "REVOKE", -- unreachable today (kills need ALIVE) and stated anyway
	["LOBBY/DIED"] = "GRANT", -- died in the lobby: give it straight back
	["LOBBY/LOAD_FAILED"] = "DEFER", -- the round-4 bug: no retry meant no body, ever

	-- ALIVE: dealt into a round.
	["ALIVE/JOINED"] = "GRANT",
	["ALIVE/PHASE_CHANGE"] = "GRANT",
	["ALIVE/KILLED"] = "REVOKE",
	["ALIVE/DIED"] = "REVOKE", -- a round death is a death; RoundService then makes them a GHOST
	["ALIVE/LOAD_FAILED"] = "DEFER", -- ALIVE with no body is unkillable AND counted: the worst cell

	--[[
		GHOST: dead, and KEEP ON EVERY CAUSE. Their body is the CORPSE, and MonsterService owns it.

		This row has now moved three times and the history is the point. It was REVOKE (C05, no ghost body),
		then GRANT (C15, ghosts got real characters so they had a position), then REVOKE again (an audit
		found a replicated hidden body names the dead set), and now KEEP — because removing the body did not
		remove the tell, it INVERTED it. `Character == nil` enumerates the dead exactly as well as a tagged
		body did, and the Aswang is never in that set.

		KEEP is what makes `player.Character ~= nil` true for everyone. REVOKE would destroy the corpse that
		§4.7 and Amendment A3 both rely on as the death signal; GRANT would spawn a fresh WALKING body for a
		dead player; DEFER would retry that forever.
	]]
	["GHOST/JOINED"] = "KEEP",
	["GHOST/PHASE_CHANGE"] = "KEEP",
	["GHOST/KILLED"] = "KEEP",
	["GHOST/DIED"] = "KEEP",
	["GHOST/LOAD_FAILED"] = "KEEP", -- the corpse is not a load that can fail

	-- SPECTATOR: joined mid-round. THE C04 REMNANT — uncounted, so it must also be bodiless.
	["SPECTATOR/JOINED"] = "REVOKE",
	["SPECTATOR/PHASE_CHANGE"] = "REVOKE",
	["SPECTATOR/KILLED"] = "REVOKE",
	["SPECTATOR/DIED"] = "REVOKE",
	["SPECTATOR/LOAD_FAILED"] = "KEEP",
}

for _, state in STATES do
	for _, cause in CAUSES do
		local key = `{state}/{cause}`
		local actual = BodyTransitions.actionFor(state, cause)

		check(key, actual == EXPECTED[key], `expected {EXPECTED[key]}, got {actual}`)
	end
end

--------------------------------------------------------------------------------
-- The properties the cells exist to express. A future edit must not satisfy the table by accident
-- while breaking the rule underneath it.
--------------------------------------------------------------------------------

-- THE C04 REMNANT, as a property rather than four cells. A spectator is uncounted by the alive count,
-- so a spectator WITH a body is an alt account watching the round from ten studs away.
for _, cause in CAUSES do
	check(
		`a spectator is never granted a body ({cause})`,
		BodyTransitions.actionFor("SPECTATOR", cause) ~= "GRANT",
		"uncounted and present is the exploit"
	)
end

--[[
	A GHOST'S BODY IS NEVER TOUCHED, on any cause — asserted as a property over every cause rather than
	as five cells, so a future edit that acts on one of them fails here.

	GRANT would give a dead player a walking body. REVOKE would destroy the corpse, which is the ONLY
	thing a living player is supposed to learn a death from (§4.7, Amendment A3) — and destroying it
	would also make `Character == nil`, which is the enumerable death oracle this whole row exists to
	avoid. Both directions are wrong, so the answer is neither.
]]
for _, cause in CAUSES do
	check(
		`a ghost's body is left alone ({cause})`,
		BodyTransitions.actionFor("GHOST", cause) == "KEEP",
		"the corpse IS their character; MonsterService owns it"
	)
end

check(
	"a failed load for a GHOST is NOT retried",
	BodyTransitions.actionFor("GHOST", "LOAD_FAILED") == "KEEP"
)

-- And must NOT be retried for someone owed nothing, or the retry loops forever on a spectator.
check(
	"a failed load for a SPECTATOR is not retried",
	BodyTransitions.actionFor("SPECTATOR", "LOAD_FAILED") == "KEEP"
)

-- The table must be TOTAL. An unknown cell returning nil is how a fifth state or a sixth cause would
-- silently do nothing at all — which is how this whole class of bug started.
check(
	"every state/cause pair has an action",
	(function()
		for _, state in STATES do
			for _, cause in CAUSES do
				if BodyTransitions.actionFor(state, cause) == nil then
					return false
				end
			end
		end

		return true
	end)()
)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print(`  PASS  body-transitions: {checked} cells and properties`)
