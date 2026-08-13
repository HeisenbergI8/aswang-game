--!strict
--[[
	REVIEW — src/shared/pure/WinConditions.luau
	Read 2026-08-12 for the C09-C12 plan. The file is 81 lines. Unmodified by this plan.

	Phase 6 adds §4.8's OTHER win. This file owns the Aswang's, and C11's Done condition is "BOTH win
	conditions in §4.8 fire correctly" — so this is the half that must not break while the other is
	added.
]]

-- src/shared/pure/WinConditions.luau:7-8 (header)
-- "IT COUNTS KILLS, NOT SURVIVORS PRESENT. That is an amendment to §4.8's wording, made deliberately
--  and with the user's approval, and it is the fourth version of this rule."
-- IMPORTANT: this is Amendment A1, and it means BOTH rows of §4.8's table now differ from the spec's
-- original wording — A1 for the Aswang, A2's knock-on for the survivors' side. Phase 6 implements the
-- survivor row as literally written (5/5 AND a survivor reaches the gate), which is unamended.

-- src/shared/pure/WinConditions.luau:10-25 (the three failed patches)
--   1. freeze DealtInSurvivors at STARTING   — livingSurvivorCount() is computed LIVE
--   2. decrement it on a non-kill death      — closed reset-then-reset and nothing else
--   3. decrement it on disconnect too        — ARITHMETICALLY INERT above four survivors
-- IMPORTANT — THE LESSON PHASE 6 HAS TO INHERIT: "No amount of bookkeeping on the denominator fixes a
-- numerator that is measuring the wrong thing." Three patches passed every check and the rule stayed
-- broken, because presence cannot tell a kill from a quit.
-- NOTE: the gate win has no equivalent hazard, and it is worth saying why rather than assuming: it
-- reads no counter at all. It is a live geometric fact (this player, this distance, this instant) that
-- can only become true through a deliberate act. There is nothing to keep balanced.

-- src/shared/pure/WinConditions.luau:60-62
function WinConditions.killsRequired(dealtInSurvivors: number, threshold: number): number
	return math.max(1, dealtInSurvivors - threshold)
end
-- NOTE: the floor is what keeps a round from being won with no kills at all — at MinPlayers = 3 the
-- subtraction gives zero. Phase 6's `GateEscape` has the analogous degenerate case and handles it
-- structurally rather than with a floor: at 5/5 with no living survivors, nobody can be ALIVE and a
-- SURVIVOR at the gate, so the round runs to TIMEOUT. Correct, and no clamp needed.

-- src/shared/pure/WinConditions.luau:64-79
function WinConditions.aswangWinsByKills(request: Request): boolean
	if request.DealtInSurvivors <= 0 then
		return false
	end
	return request.AswangKills >= WinConditions.killsRequired(...)
end
-- IMPORTANT FOR EVERY PLAYTEST STEP IN THIS PLAN: "This is the solo Studio round (Debug.SoloTesting
-- plus Debug.ForceAswangWhenSolo, which makes the lone player the Aswang). Zero survivors dealt in,
-- so no kill count can be legitimate, and an agent driving a solo round would otherwise see it end
-- before ACTIVE was a second old — which would make every later chunk unverifiable in the only
-- environment an agent can drive."
-- CONSEQUENCE: a solo round with `ForceAswangWhenSolo` on runs to the sunrise timer, which is what
-- makes Phases 3, 4 and 7 observable solo. But Phase 6's SURVIVOR win is NOT observable that way —
-- the lone player is the Aswang, so `GateEscape` refuses them at the gate, correctly and silently.
-- IMPORTANT: Step 6.5's end-to-end proof therefore needs `ForceAswangWhenSolo = FALSE` so the solo
-- player draws SURVIVOR. That is the opposite of what Phases 5 and 7 want, and it is a real
-- configuration conflict inside one plan. Whoever briefs the playtester must set it per phase, not
-- once — and both settings are pinned false by `check:debug`, so the coordinator sets and reverts.

-- src/shared/pure/WinConditions.luau:27-34
-- "What changed in practice: [...] a player LEAVING no longer advances the Aswang. If enough
--  survivors quit that the required kills can no longer be reached, the round simply runs to sunrise,
--  and §4.8 already scores TIMEOUT as an Aswang win."
-- NOTE: the gate win interacts with this cleanly. A round where every survivor quits ends on the
-- timer as an Aswang win; a round where the last survivor reaches the gate ends as SURVIVORS_ESCAPED.
-- `enterEnding`'s guard decides a genuine tie by first-caller, and warns about the loser UNGATED — so
-- a race between the sunrise timer and a gate arrival is visible in a published server's log rather
-- than silent. That warn firing during Step 6.5 is the guard working, not a defect.

-- src/shared/pure/WinConditions.luau:36-38
-- "the threshold arrives as a parameter rather than being read from Config — same rule as every other
--  pure module here."
-- NOTE: all five of this plan's new pure modules follow it. `GateEscape` takes `Range` rather than
-- reading `Config.Tasks.GateRangeStuds`; `TaskParticipants` takes `fullWeight`; `TimingWindow` takes
-- every one of its five. It is also what keeps them clean of `check:config`, which governs
-- `src/server/pure/` where four of the five live.
return nil
