--!strict
--[[
	TransformRules — may this player transform right now, and if not, why not.

		(request) -> verdict

	§4.3 lists the transform's preconditions in prose. Every one of them is a comparison over numbers,
	booleans and two string enums — no raycast, no character, no DataModel — so all of it is testable
	from a terminal and none of it needs Studio. (C05's kill validation is the opposite case: the
	raycast is irreducibly Roblox, which is why `pure/KillValidation.luau` will be everything EXCEPT
	the raycast.)

	THIS ONE STAYS IN src/shared/pure/, unlike RoleDraw, and the difference is worth stating because it
	is the rule the next author will have to apply. A client can require and call this. It learns
	nothing: every input is either a value that client already holds (its own role, the phase, its own
	state) or a Config number that already replicates. Calling it locally produces a verdict with no
	authority — the server evaluates its own copy against its own state, which is the only one that
	counts. Logic is not secret; inputs and seeds are.

	THE VERDICT NEVER REACHES A CLIENT. It exists so the server can log WHY it refused: an exploiter
	probing the boundary and a real player mashing a key during INTERMISSION are the same `false` and
	very different events, and telling them apart is what C41 needs. Echoing it back would also hand a
	client a free oracle for `NOT_ASWANG`.

	NO `script.Parent` REQUIRES. The three enums are re-declared; Luau literal unions are structural,
	so these and their Types.luau counterparts are the same types.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict =
	"OK"
	| "NOT_ASWANG"
	| "WRONG_PHASE"
	| "NOT_ALIVE"
	| "ALREADY_TRANSFORMED"
	| "ON_COOLDOWN"

export type Request = {
	IsAswang: boolean,
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Transformed: boolean,
	Now: number,
	LastRevertedAt: number?, -- nil means "has never transformed this round"
	Cooldown: number,
}

local TransformRules = {}

--[[
	The order of these checks is FIXED, and it is part of the contract rather than an implementation
	detail: it decides which reason a log line carries when more than one applies. A spectator who is
	also on cooldown should read as NOT_ALIVE, because that is the fact worth acting on.

	World-level facts first (phase, then liveness), then facts about this player (role), then facts
	about this player's monster state (already transformed, cooldown).
]]
function TransformRules.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	--[[
		AN ALLOWLIST, NEVER A DENYLIST. `PlayerState ~= "SPECTATOR"` would read identically today and
		would admit LOBBY and GHOST — and C15 makes GHOST real, at which point a dead player transforms.
		`PlayerState` has four values and exactly one of them may act.

		This is C04's carried-over warning from C01, and Step 7.2 is where the test proves all four.
	]]
	if request.PlayerState ~= "ALIVE" then
		return "NOT_ALIVE"
	end

	if not request.IsAswang then
		return "NOT_ASWANG"
	end

	if request.Transformed then
		return "ALREADY_TRANSFORMED"
	end

	--[[
		THE COOLDOWN RUNS FROM REVERT, NOT FROM THE TRANSFORM (§4.3 step 5).

		Measured from the transform, an Aswang who holds the form for its full duration serves most of
		the cooldown while still being a monster, and the "every kill is a gamble" pillar collapses:
		the punishment for a failed hunt would be nearly zero. `tests/config.test.luau` already pins
		`KillCooldown > TransformTime + RevertTime` for the same reason.

		A nil LastRevertedAt means this is the round's first transform, which is never on cooldown.
	]]
	local lastRevertedAt = request.LastRevertedAt

	if lastRevertedAt ~= nil and request.Now - lastRevertedAt < request.Cooldown then
		return "ON_COOLDOWN"
	end

	return "OK"
end

return TransformRules
