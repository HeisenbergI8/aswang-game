--!strict
-- Review of src/shared/pure/RoundTransitions.luau — why Phase 5 is a SIBLING and not a row here.
-- Excerpts only.

-- src/shared/pure/RoundTransitions.luau:7-13
--[[
	WHY THIS IS A MODULE AND NOT AN `if` CHAIN INSIDE RoundService
	Spec §6.4 lists five edge cases and says outright that they will bite you. Every one of them is a
	question about this table ... Pulled out here it is twenty lines with no dependencies, and
	`tests/round-transitions.test.luau` can walk all 5 phases × expired × enoughPlayers exhaustively.
]]
-- IMPORTANT: 5 × 2 × 2 = 20 cells, and the exhaustiveness IS the value. C06's rule is a comparison over
-- a roster count; threading it in as a third input would multiply that table by the roster size and the
-- exhaustive property would be gone. That is the argument for `pure/WinConditions.luau` as a sibling —
-- BUILD-PLAN explicitly permits "or a sibling", so this is not a deviation.

-- src/shared/pure/RoundTransitions.luau:33-37
function RoundTransitions.next(
	phase: RoundPhase,
	expired: boolean,
	enoughPlayers: boolean
): RoundPhase?
-- NOTE: three scalars in, one optional phase out. WinConditions keeps the same character — a request
-- table of numbers in, a boolean out — so both remain trivially exhaustible from a terminal.

-- src/shared/pure/RoundTransitions.luau:53-61 — the paragraph Phase 5 cites.
	elseif phase == "ACTIVE" then
		-- DELIBERATE, AND THE ONE TO NOT "FIX": `enoughPlayers` is not consulted.
		--
		-- Spec §6.4 — "player count drops below minimum mid-round → FINISH the round, then return
		-- to IDLE." Cutting ACTIVE short on a disconnect would hand the Aswang a free win every time
		-- a survivor's connection dropped, and would give any losing player a way to void a round by
		-- quitting.
		return if expired then "ENDING" else nil
-- IMPORTANT: this is the precedent for Phase 5 evaluating the attrition win ONLY on a kill. A survivor
-- disconnecting lowers the living count exactly as a kill does; letting that end the round would
-- reintroduce, through a different door, precisely the exploit this comment refuses. It is also why
-- `DealtInSurvivors` is a frozen snapshot: a disconnect must move NEITHER side of the comparison.

-- src/shared/pure/RoundTransitions.luau:62-68
	elseif phase == "ENDING" then
		-- The reveal has had its full EndScreen duration. NOW the headcount matters again.
		if not expired then
			return nil
		end

		return if enoughPlayers then "INTERMISSION" else "IDLE"
-- NOTE: the sunrise timeout path — the half of §4.8 that already works — routes through
-- `RoundService.step`'s `enterEnding(Enums.RoundResult.Timeout)` rather than through here. This module
-- decides the PHASE; the result string is chosen at the call site. Phase 5 changes neither.

-- src/shared/pure/RoundTransitions.luau:15-19
--[[
	NO `script.Parent` REQUIRES — that is the rule for everything under `pure/` (tests/README.md).
	... Luau literal unions are structural, so this type and `Types.RoundPhase` ARE the same type: they
	pass to each other without a cast, and the only cost of the duplication is keeping the two lists in
	step.
]]
-- NOTE: WinConditions needs no phase type at all — RoundService already guards on ACTIVE inside
-- EndRound, so the predicate takes three numbers and nothing else.
