--!strict
--[[
	TrialAdmission — may this player be in a Solo Trial right now, as a pure function.

		evaluate(input) -> TrialStartVerdict        -- may a session OPEN
		mustEnd(input)  -> boolean                  -- must a live session CLOSE

	WHY THE RISK IN C21'S ROW LIVES HERE RATHER THAN IN A COMMENT
	-------------------------------------------------------------
	The build plan says it plainly: "TrialService and RoundService sharing state is how you get a
	trial that ends a live round." The rule that prevents it is a two-line predicate — a trial may
	only exist while RoundService is IDLE and the server is below the offer threshold — and a
	two-line predicate buried in a service is a two-line predicate nobody ever tests. Out here every
	combination of phase × population × existing-session is a cell somebody can argue with.

	NOTE `mustEnd` IS NOT `not evaluate == OK`, AND CONFLATING THEM IS A REAL BUG. Opening and
	staying open have different rules: a session may open only at IDLE, but a session already running
	must survive one more player joining while the phase is still IDLE — otherwise the trial dies on
	a join that changed nothing. Only a phase that is no longer IDLE closes a live session.

	NO `script.Parent` REQUIRES (tests/README.md). The two unions are re-declared; Luau unions are
	structural, so these and `Types.TrialStartVerdict` / `Types.RoundPhase` are the same types.

	SEEDS AND INPUTS: there are none. This module is a predicate over facts the client already has
	(the phase and the headcount both reach every client via RoundSnapshot), so publishing it in
	`shared/` reveals nothing. Compare CLAUDE.md's rule about `Random.new(roundNumber)` — there is no
	draw here and no seed to protect.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"

export type TrialStartVerdict =
	"OK"
	| "DISABLED"
	| "ALREADY_IN_TRIAL"
	| "ROUND_NOT_IDLE"
	| "TOO_MANY_PLAYERS"

export type Input = {
	Enabled: boolean,
	RoundPhase: RoundPhase,
	PlayerCount: number,
	OfferBelowPlayerCount: number,
	AlreadyInTrial: boolean,
}

local TrialAdmission = {}

--[[
	ORDER IS THE DESIGN, not a style choice. The verdicts are checked most-permanent first, so the
	one a player is told is the one that will still be true in a second: "the feature is off" outranks
	"you are already in one" outranks "a round is starting" outranks "there are enough players now".
	A C24 button that reported TOO_MANY_PLAYERS while a round was already STARTING would send a
	player to wait for the server to empty when what they should do is stand still.
]]
function TrialAdmission.evaluate(input: Input): TrialStartVerdict
	if not input.Enabled then
		return "DISABLED"
	end

	if input.AlreadyInTrial then
		return "ALREADY_IN_TRIAL"
	end

	-- THE MUTUAL EXCLUSION, in one line. Every other phase means a round is being set up, is running,
	-- or is showing its reveal, and in all three the answer is no.
	if input.RoundPhase ~= "IDLE" then
		return "ROUND_NOT_IDLE"
	end

	--[[
		§9.1: the trial is the BELOW-MinPlayers fallback. At or above the threshold a real round is
		about to begin, and starting a 90-second solo tutorial in front of it is how the trial ends up
		competing with the game instead of feeding it.

		Strictly below, matching the field's name. `OfferBelowPlayerCount == Round.MinPlayers` is
		pinned in tests/config.test.luau, so this and RoundService's own `>= MinPlayers` gate
		(RoundService.luau:1003) partition the headcount line exactly, with no value on both sides.
	]]
	if input.PlayerCount >= input.OfferBelowPlayerCount then
		return "TOO_MANY_PLAYERS"
	end

	return "OK"
end

--[[
	THE ROUND WINS. See the plan's §1.1: a live session ends the moment the phase leaves IDLE rather
	than the round waiting for it. Population is deliberately NOT consulted — a third player joining
	while the phase is still IDLE does not end anybody's trial; the phase change that follows a
	moment later does, and that is the event with the 25 seconds of INTERMISSION runway behind it.
]]
function TrialAdmission.mustEnd(phase: RoundPhase): boolean
	return phase ~= "IDLE"
end

return TrialAdmission
