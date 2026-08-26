--!strict
--[[
	Enums — shared string constants.

	Using string literals (not numbers) so they're readable in logs and analytics.
]]

-- The `:: Types.X` casts are load-bearing under --!strict. Without them every field
-- infers as plain `string`, and passing one to a parameter typed as the literal union
-- fails to typecheck — which is how the scaffold shipped six analyze errors.
local Types = require(script.Parent.Types)

local Enums = {}

Enums.RoundPhase = table.freeze({
	Idle = "IDLE" :: Types.RoundPhase,
	Intermission = "INTERMISSION" :: Types.RoundPhase,
	Starting = "STARTING" :: Types.RoundPhase,
	Active = "ACTIVE" :: Types.RoundPhase,
	Ending = "ENDING" :: Types.RoundPhase,
})

Enums.Role = table.freeze({
	Survivor = "SURVIVOR" :: Types.Role,
	Aswang = "ASWANG" :: Types.Role,
})

Enums.PlayerState = table.freeze({
	Lobby = "LOBBY" :: Types.PlayerState,
	Alive = "ALIVE" :: Types.PlayerState,
	Dead = "DEAD" :: Types.PlayerState, -- V01: killed in-round. Spectates; the corpse is the body
	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
})

Enums.RoundResult = table.freeze({
	SurvivorsEscaped = "SURVIVORS_ESCAPED" :: Types.RoundResult,
	AswangWins = "ASWANG_WINS" :: Types.RoundResult,
	Timeout = "TIMEOUT" :: Types.RoundResult,
	Aborted = "ABORTED" :: Types.RoundResult, -- e.g. the Aswang disconnected
})

return Enums
