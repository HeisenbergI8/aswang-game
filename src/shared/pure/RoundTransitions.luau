--!strict
--[[
	RoundTransitions — the round state machine's transition table, as a pure function.

		(phase, expired, enoughPlayers) -> nextPhase?   -- nil means "stay put"

	WHY THIS IS A MODULE AND NOT AN `if` CHAIN INSIDE RoundService
	--------------------------------------------------------------
	Spec §6.4 lists five edge cases and says outright that they will bite you. Every one of them is a
	question about this table — not about Roblox, not about replication, not about timing. Pulled out
	here it is twenty lines with no dependencies, and `tests/round-transitions.test.luau` can walk all
	5 phases × expired × enoughPlayers exhaustively in milliseconds. Left inline it would be verifiable
	only by pressing Play and waiting seven minutes per case.

	NO `script.Parent` REQUIRES — that is the rule for everything under `pure/` (tests/README.md).
	Lune has no DataModel, so a pure module that requires Types or Enums stops being runnable from a
	terminal and the whole point is lost. The phase type is therefore re-declared below. Luau literal
	unions are structural, so this type and `Types.RoundPhase` ARE the same type: they pass to each
	other without a cast, and the only cost of the duplication is keeping the two lists in step.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"

local RoundTransitions = {}

--[[
	The single source of truth for "what happens next".

	`expired` is whether the current phase's timer has run out; `enoughPlayers` is whether the server
	is at or above Config.Round.MinPlayers. Returning nil means no transition — the caller does
	nothing, which is the common case since this is polled several times a second.
]]
function RoundTransitions.next(
	phase: RoundPhase,
	expired: boolean,
	enoughPlayers: boolean
): RoundPhase?
	if phase == "IDLE" then
		-- Waiting for a lobby. Timers are irrelevant here; only headcount opens the door.
		return if enoughPlayers then "INTERMISSION" else nil
	elseif phase == "INTERMISSION" then
		-- Headcount is checked BEFORE the timer: someone leaving during the countdown drops the
		-- server straight back to IDLE rather than starting a round that cannot be played.
		if not enoughPlayers then
			return "IDLE"
		end

		return if expired then "STARTING" else nil
	elseif phase == "STARTING" then
		-- Roles are being drawn (C03). Deliberately uninterruptible: a player leaving between the
		-- draw and ACTIVE must not rewind a round that has already picked its Aswang.
		return if expired then "ACTIVE" else nil
	elseif phase == "ACTIVE" then
		-- DELIBERATE, AND THE ONE TO NOT "FIX": `enoughPlayers` is not consulted.
		--
		-- Spec §6.4 — "player count drops below minimum mid-round → FINISH the round, then return
		-- to IDLE." Cutting ACTIVE short on a disconnect would hand the Aswang a free win every time
		-- a survivor's connection dropped, and would give any losing player a way to void a round by
		-- quitting. The round plays out; the headcount is re-read at ENDING, where it decides
		-- whether there is a next one.
		return if expired then "ENDING" else nil
	elseif phase == "ENDING" then
		-- The reveal has had its full EndScreen duration. NOW the headcount matters again.
		if not expired then
			return nil
		end

		return if enoughPlayers then "INTERMISSION" else "IDLE"
	end

	return nil
end

return RoundTransitions
