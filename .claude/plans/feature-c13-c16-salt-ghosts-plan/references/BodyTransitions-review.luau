--!strict
--[[
	REVIEW — src/shared/pure/BodyTransitions.luau (101 lines)

	THE FULL ANNOTATED REVIEW OF THIS FILE IS IN `PlayerBody-review.luau`, which covers both modules
	together because that pairing IS the finding: two files define `mayHaveBody`, with identical bodies,
	tested separately, and the brief named only one of them.

	Excerpted here is the single annotation that decides which file Phase 6 must not miss.
]]

-- src/shared/pure/BodyTransitions.luau:60-64
-- LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
-- also admits GHOST, and C15 makes GHOST real.
function BodyTransitions.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end
-- IMPORTANT THIS IS THE ONE `RoundService.applyBodyRule` ACTUALLY CALLS, via `actionFor` five lines
--      below. `pure/PlayerBody.mayHaveBody` is its twin and is called by nothing but its own test.
--      Editing only PlayerBody — which is the file the brief named — produces a plan that reads correct
--      and a game where ghosts stay bodiless, and every downstream claim in Phases 6 and 8 (flight,
--      visibility, 25% contribution, the spook's position lookup) fails silently as a consequence.
-- NOTE Steps 6.2 and 6.3 change both, and `tests/body-transitions.test.luau` (twenty cells) and
--      `tests/player-body.test.luau` (eight cells) both change with them. Neither test can see the other
--      module, so neither would catch a half-done edit.
