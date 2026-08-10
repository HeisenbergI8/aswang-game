--!strict
--[[
	Enums — shared string constants.

	Using string literals (not numbers) so they're readable in logs and analytics.
]]

local Enums = {}

Enums.RoundPhase = table.freeze({
	Idle = "IDLE",
	Intermission = "INTERMISSION",
	Starting = "STARTING",
	Active = "ACTIVE",
	Ending = "ENDING",
})

Enums.Role = table.freeze({
	Survivor = "SURVIVOR",
	Aswang = "ASWANG",
})

Enums.PlayerState = table.freeze({
	Lobby = "LOBBY",
	Alive = "ALIVE",
	Ghost = "GHOST",
	Spectator = "SPECTATOR", -- joined mid-round
})

Enums.TaskType = table.freeze({
	Hold = "HOLD",
	Timing = "TIMING",
	Fetch = "FETCH",
	TwoPerson = "TWO_PERSON",
})

Enums.RoundResult = table.freeze({
	SurvivorsEscaped = "SURVIVORS_ESCAPED",
	AswangWins = "ASWANG_WINS",
	Timeout = "TIMEOUT",
	Aborted = "ABORTED", -- e.g. the Aswang disconnected
})

return Enums
