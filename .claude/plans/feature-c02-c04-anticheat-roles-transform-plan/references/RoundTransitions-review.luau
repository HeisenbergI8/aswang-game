--!strict
--[[
	REVIEW — src/shared/pure/RoundTransitions.luau (C01)

	The template every pure module in this plan copies. Read for its RULES, not its logic.
]]

--[[
	IMPORTANT — the header states the rule that decides where TokenBucket, RoleDraw and TransformRules
	each live and how they are written. Quoted in full because all three follow it:

		"NO `script.Parent` REQUIRES — that is the rule for everything under `pure/` (tests/README.md).
		 Lune has no DataModel, so a pure module that requires Types or Enums stops being runnable from
		 a terminal and the whole point is lost. The phase type is therefore re-declared below. Luau
		 literal unions are structural, so this type and `Types.RoundPhase` ARE the same type: they pass
		 to each other without a cast, and the only cost of the duplication is keeping the two lists in
		 step."

	NOTE `Enums.luau` requires `script.Parent.Types`, so requiring Enums from a pure module is the same
	violation wearing a different hat. TransformRules re-declares RoundPhase and PlayerState for exactly
	this reason.
]]
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"

local RoundTransitions = {}

-- The signature shape this plan imitates: plain tables and scalars in, a decision out, nil for "no
-- change". No Roblox types anywhere in the boundary.
function RoundTransitions.next(
	phase: RoundPhase,
	expired: boolean,
	enoughPlayers: boolean
): RoundPhase?
	-- NOTE — STARTING is deliberately uninterruptible: "a player leaving between the draw and ACTIVE
	-- must not rewind a round that has already picked its Aswang." That comment was written for C03,
	-- and Phase 5 is what makes it true: AssignRoles runs inside enterStarting.
	if phase == "STARTING" then
		return if expired then "ACTIVE" else nil
	end

	-- NOTE — ACTIVE ignores the player count on purpose (spec §6.4). MonsterService's phase
	-- subscription in Phase 7 therefore only ever sees ACTIVE -> ENDING, never a mid-round bounce.
	return nil
end

return RoundTransitions
