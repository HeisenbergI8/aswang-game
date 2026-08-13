--!strict
--[[
	REVIEW — src/shared/pure/PlayerBody.luau (55 lines) and src/shared/pure/BodyTransitions.luau (101)

	Excerpted ranges:
	  · src/shared/pure/PlayerBody.luau:12-26        the two-allowlist rule and its C15 prediction
	  · src/shared/pure/PlayerBody.luau:33-53        both functions
	  · src/shared/pure/BodyTransitions.luau:60-64   THE OTHER mayHaveBody — the one that is called
	  · src/shared/pure/BodyTransitions.luau:66-99   the twenty-cell table

	Reviewed together because THE BRIEF NAMED ONLY ONE OF THEM and they must change together. Both files
	define `mayHaveBody`, with identical bodies, tested separately.
]]

-- src/shared/pure/PlayerBody.luau:12-20
--	TWO ALLOWLISTS, NOT ONE, AND THEY ARE DIFFERENT SETS. This is the part that is easy to get wrong.
--	  · mayHaveBody  — LOBBY and ALIVE. A player waiting in the lobby needs a body to walk around in.
--	  · mayBeKilled  — ALIVE, and nothing else. That is C05's "both alive" rule.
--	Both are ALLOWLISTS. `state ~= "SPECTATOR"` reads identically today for either one and admits LOBBY
--	and GHOST — and C15 makes GHOST real, at which point a dead player is killable again.
-- IMPORTANT THAT MOMENT HAS ARRIVED. After Phase 6 the two functions genuinely diverge for the first
--      time, and mayBeKilled's allowlist is the ONLY thing keeping a ghost unkillable — before C15 it was
--      guaranteed incidentally, because a ghost had no body to kill.
-- NOTE A denylist in either function would now hand the Aswang a farmable target. Step 6.3 adds a
--      property check asserting both facts about GHOST in one line, so a merge of the two functions fails
--      a terminal test.

-- src/shared/pure/PlayerBody.luau:33-42
--	GHOST returns false and that is deliberate for C05 rather than final: a killed player's character
--	becomes the corpse (Step 4.2), so re-spawning them would put two bodies in the world. C15 gives
--	ghosts their own body and will change this row — in this file, with this test, which is the point.
function PlayerBody.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end
-- IMPORTANT THIS FILE PREDICTED THIS EDIT AND NAMED THE TEST. Step 6.3 honours it.
-- NOTE The two-bodies concern has not gone away; it has moved. What answers it is BodyTransitions'
--      GHOST/KILLED cell staying REVOKE — the death path takes the body, the ghost body arrives on the
--      next transition. "May a ghost have a body" and "what happens to a ghost's body at the moment of
--      death" are different questions, and separating them is what lets this row move.
-- QUESTION Is this function called by anything? Grep says no — only its own test. `applyBodyRule` calls
--      BodyTransitions.actionFor, which calls BodyTransitions' own copy. It is a documented rule with a
--      test and no caller, which is worth knowing but is not a reason to skip editing it: leaving it
--      behind means the repo states two different rules in two pure modules.

-- src/shared/pure/BodyTransitions.luau:60-64
-- LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
-- also admits GHOST, and C15 makes GHOST real.
function BodyTransitions.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end
-- IMPORTANT THIS IS THE ONE `applyBodyRule` ACTUALLY CALLS, and the brief did not name it. Changing
--      PlayerBody alone would produce a plan that reads correct and a game where ghosts stay bodiless —
--      and every downstream claim (flight, 25% contribution, C16 entirely) would silently fail.

-- src/shared/pure/BodyTransitions.luau:78-98
function BodyTransitions.actionFor(state: PlayerState, cause: Cause): Action
	if not BodyTransitions.mayHaveBody(state) then
		return if cause == "LOAD_FAILED" then "KEEP" else "REVOKE"
	end

	if cause == "LOAD_FAILED" then
		return "DEFER"
	end

	if cause == "KILLED" then
		return "REVOKE"
	end

	if cause == "DIED" then
		return if state == "ALIVE" then "REVOKE" else "GRANT"
	end

	return "GRANT"
end
-- IMPORTANT ALL FIVE GHOST CELLS MOVE AT ONCE because the function branches on mayHaveBody first:
--        JOINED        REVOKE -> GRANT   (a returning dealt-in player gets a ghost body on arrival)
--        PHASE_CHANGE  REVOKE -> GRANT
--        KILLED        REVOKE -> REVOKE  (unchanged, and it MUST be — the corpse depends on it)
--        DIED          REVOKE -> GRANT   (this is what actually spawns the ghost)
--        LOAD_FAILED   KEEP   -> DEFER   (a ghost is now owed a body, so a failed load retries)
-- NOTE GHOST/DIED becoming GRANT is the cell that makes Phase 6 work at all, and GHOST/KILLED staying
--      REVOKE is the cell that stops two bodies existing. They are the same row and different causes,
--      which is precisely the distinction a boolean `mayHaveBody` alone could not express.

-- src/shared/pure/BodyTransitions.luau:7-19
--	`RoundService` was patched five times across four review rounds, and every defect was the same
--	shape: one entry point handled and its twin not.
-- IMPORTANT THE ARGUMENT FOR pure/RejoinResolve (Step 5.1), stated by a module that already won it. The
--      rejoin decision has exactly this shape — a conditional over a phase and a flag, inside a function
--      with four other jobs, where the wrong cell is invisible until somebody exploits it.
-- NOTE It is also the argument for changing BOTH mayHaveBody functions rather than the one the brief
--      named. "One entry point handled and its twin not" is this review's whole finding.
