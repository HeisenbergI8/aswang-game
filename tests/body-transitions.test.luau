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

local function check(label: string, ok: boolean, detail: string?)
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

	-- GHOST: dead. Their old character is the corpse; a second body would be two bodies.
	["GHOST/JOINED"] = "REVOKE",
	["GHOST/PHASE_CHANGE"] = "REVOKE",
	["GHOST/KILLED"] = "REVOKE",
	["GHOST/DIED"] = "REVOKE",
	["GHOST/LOAD_FAILED"] = "KEEP", -- nothing was owed, so nothing to retry

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

-- A ghost must never get a second body: their first one is standing in the world as the corpse.
for _, cause in CAUSES do
	check(
		`a ghost is never granted a body ({cause})`,
		BodyTransitions.actionFor("GHOST", cause) ~= "GRANT"
	)
end

--[[
	THE FIVE-ROUND BUG, STATED AS A PROPERTY.

	Every state that MAY hold a body must eventually get one, whatever the cause. The permanent-strand
	bug was exactly this property failing for one cell: a throttled respawn returned without granting
	or deferring, so LOBBY/DIED silently became "nothing", and no later phase change repaired it
	because the dead character was still attached.

	`KEEP` is not an acceptable answer for a state that may hold a body and currently does not — that
	is the hole. Only GRANT or DEFER discharge the obligation.
]]
for _, state in STATES do
	for _, cause in CAUSES do
		if not BodyTransitions.mayHaveBody(state) then
			continue
		end

		local action = BodyTransitions.actionFor(state, cause)

		check(
			`an embodied state is never left stranded ({state}/{cause})`,
			action == "GRANT" or action == "DEFER" or action == "REVOKE",
			`got {action} — a state that may hold a body must be granted, deferred or explicitly revoked`
		)
	end
end

-- A load failure must never be silently dropped for someone owed a body. This is the round-4 defect.
check(
	"a failed load for an ALIVE player is retried",
	BodyTransitions.actionFor("ALIVE", "LOAD_FAILED") == "DEFER"
)
check(
	"a failed load for a LOBBY player is retried",
	BodyTransitions.actionFor("LOBBY", "LOAD_FAILED") == "DEFER"
)

-- And must NOT be retried for someone owed nothing, or the retry loops forever on a spectator.
check(
	"a failed load for a GHOST is not retried",
	BodyTransitions.actionFor("GHOST", "LOAD_FAILED") == "KEEP"
)
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

print("  PASS  body-transitions: 20 cells + 4 properties")
