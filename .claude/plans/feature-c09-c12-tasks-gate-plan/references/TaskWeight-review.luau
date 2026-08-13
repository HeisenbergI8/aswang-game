--!strict
--[[
	REVIEW — src/server/pure/TaskWeight.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 68 lines.

	The load-bearing module for this entire plan. Amendment A2 names it as "the enforceable form" of
	its rule, and Phases 4 and 5 are designed to INHERIT its property rather than restate it.
	Unmodified by this plan — which is the point.
]]

-- src/server/pure/TaskWeight.luau:7-11 (header)
-- "For any given PlayerState, the weight MUST NOT vary by Role.
--  That sentence is the entire contract. `tests/task-weight.test.luau` enumerates the full
--  `PlayerState × Role` domain — eight cells, every one asserted."
-- IMPORTANT: eight cells is a small grid guarding a large claim, and `check-secrecy.mjs`'s new rule 5
-- exists precisely because of that gap: "a grid guarantees exactly ONE function, and an exploit audit
-- made the consequence concrete: the oracle's natural home moved to TaskWeight's CALLERS."
-- See `references/check-secrecy-review.luau`.

-- src/server/pure/TaskWeight.luau:57-67
function TaskWeight.forPlayer(playerState: PlayerState, _role: Role, ghostMult: number): number
	if playerState == "ALIVE" then
		return 1
	end

	if playerState == "GHOST" then
		return math.max(0, ghostMult)
	end

	return 0
end
-- IMPORTANT — THE THREE NUMBERS THIS PLAN BUILDS ON, and all three are load-bearing:
--   ALIVE  -> 1     both roles. This is what makes a survivor+Aswang pair satisfy C10's two-person
--                   requirement, and what makes an Aswang able to carry C09's fetch item.
--   GHOST  -> 0.25  below `FullContributionWeight`, so a ghost neither carries nor counts as a
--                   participant. C15's answer, arrived at for free.
--   else   -> 0     LOBBY and SPECTATOR are not in the round.
-- Phase 4's `FetchCarry` and Phase 5's `TaskParticipants` both take these NUMBERS as input and never
-- see a role. That is the inheritance A2 asks for, stated structurally.

-- src/server/pure/TaskWeight.luau:40-47
-- "`role` is accepted and deliberately NOT read. It would be simpler to leave the parameter out. It
--  is here because its presence is what makes the test meaningful: the grid can only assert 'weight
--  does not vary by role' if a role can actually be passed in."
-- NOTE: this is the pattern Phase 4's and Phase 5's tests copy from the other end — they compose
-- THROUGH `forPlayer` rather than writing weights by hand, so a role branch introduced HERE turns
-- three test files red instead of one.

-- src/server/pure/TaskWeight.luau:17-27 (the A2 rationale)
-- "§4.4 assigns progress to the WORLD, not to the player, so a task's fill is legible to anyone
--  standing at that point — and standing at a point costs one keypress. If the Aswang's holds
--  contributed nothing, a survivor could walk up to whoever is holding, tap interact, watch the bar
--  sit frozen, and read the monster's identity directly."
-- IMPORTANT: this is the argument the whole plan rests on, and it generalises to every new surface
-- C09-C12 adds. Applied to each:
--   TIMING      a bar whose hits never advanced would name the Aswang to anyone who stood beside it
--   FETCH       an item that refused to be picked up would name it to anyone watching it not move
--   TWO_PERSON  A2 calls this "the sharpest case" — a pair producing nothing is an INSTANT reveal
--               with nothing to deduce
-- The plan refuses all three, and each refusal is enforced by an exhaustive grid rather than a
-- comment. That is the single most important structural property of this plan.

-- src/server/pure/TaskWeight.luau:29-32
-- "NO `script.Parent` REQUIRES and no Roblox datatypes [...] The two unions are re-declared locally;
--  Luau unions are structural, so these and the ones in Types.luau are the same types."
-- NOTE: every new pure module in this plan copies this exactly — `FetchCarry`, `TaskParticipants`,
-- `GateEscape`, `TaskListView` and `TimingWindow` all re-declare rather than require. It is what
-- makes them runnable from a terminal, which is what makes their steps gateable on a Lune test that
-- fails when the file is missing.
return nil
