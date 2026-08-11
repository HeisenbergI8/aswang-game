--!strict
--[[
	BodyTransitions — what happens to a player's BODY, given their state and what just happened.

		(playerState, cause) -> action

	WHY THIS EXISTS, AND WHY IT IS A TABLE
	--------------------------------------
	`RoundService` was patched five times across four review rounds, and every defect was the same
	shape: one entry point handled and its twin not.

	  · a death by reset was fixed; a death by disconnect was not
	  · a respawn throttle was added that re-stranded the player the previous fix had rescued
	  · a failed load had no retry, because only one caller could ever reach that path

	None of those was a hard problem. They happened because "may this player have a body" lived in
	`pure/PlayerBody` as a RULE, while the TRANSITIONS — grant it, take it away, try again later — were
	scattered across seven call sites of one imperative function, where no reader could see the whole
	set and no test could enumerate it.

	This is the body-side analogue of `pure/RoundTransitions.luau`, which has the same shape (state ×
	event, every cell stated) and has never had a bug. Four states × five causes is twenty cells; the
	test enumerates all twenty, so a combination nobody has hit yet still has a stated answer instead
	of falling through to whatever the last `if` happened to do.

	NO `script.Parent` REQUIRES — Lune has no `script`. PlayerState is re-declared; Luau literal unions
	are structural, so this and `Types.PlayerState` are the same type.

	THIS MODULE DECIDES, IT DOES NOT ACT. It returns a word. `RoundService` owns `LoadCharacterAsync`,
	the `pendingLoads` bookkeeping and the respawn cooldown, because all three touch the DataModel and
	none of them can be tested from a terminal. The decision is the part that kept being wrong, so the
	decision is the part that moved.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

--[[
	The five ways a body's correctness can change. `LOAD_FAILED` is one of them and that is the
	non-obvious entry: a load that throws leaves the player exactly as bodiless as never having asked,
	and treating it as an ordinary cause is what stops it being silently dropped — which it was, for a
	full review round, leaving an ALIVE player unkillable-but-counted for the rest of the round.
]]
export type Cause = "JOINED" | "PHASE_CHANGE" | "KILLED" | "DIED" | "LOAD_FAILED"

--[[
	GRANT   load a character if they do not have one
	REVOKE  take the body away and destroy it
	KEEP    leave whatever they have alone
	DEFER   they should have a body but not yet — schedule it and try again

	DEFER is the rung that did not exist before, and its absence was the permanent-strand bug: a
	throttled respawn returned having neither granted nor revoked, so the player kept a DEAD character,
	and `applyBodyRule`'s load branch is gated on `Character == nil` and therefore never repaired it.
	"Not now" and "not ever" must not be the same answer.
]]
export type Action = "GRANT" | "REVOKE" | "KEEP" | "DEFER"

local BodyTransitions = {}

-- LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
-- also admits GHOST, and C15 makes GHOST real.
function BodyTransitions.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end

--[[
	THE TABLE. Read it as a grid, not as a sequence of conditions.

	The two rows that carry the history:

	  ALIVE/DIED    -> REVOKE. A death inside a round is a death. RoundService then makes them a GHOST,
	                  which also closes reset-to-escape: without it, a cornered survivor could press
	                  Escape and teleport to spawn for free.
	  ALIVE/LOAD_FAILED -> DEFER. The worst cell in the table. An ALIVE player with no body is
	                  unkillable (MonsterService returns early on a nil character) AND still counted by
	                  livingSurvivorCount, which puts §4.8's attrition win permanently out of reach.
]]
function BodyTransitions.actionFor(state: PlayerState, cause: Cause): Action
	if not BodyTransitions.mayHaveBody(state) then
		-- GHOST and SPECTATOR are owed nothing. A failed load for them needs no retry — retrying would
		-- loop forever against a rule that will never say yes.
		return if cause == "LOAD_FAILED" then "KEEP" else "REVOKE"
	end

	if cause == "LOAD_FAILED" then
		return "DEFER"
	end

	-- KILLED and, for ALIVE, DIED both end the body. LOBBY/DIED is the lobby respawn.
	if cause == "KILLED" then
		return "REVOKE"
	end

	if cause == "DIED" then
		return if state == "ALIVE" then "REVOKE" else "GRANT"
	end

	return "GRANT"
end

return BodyTransitions
