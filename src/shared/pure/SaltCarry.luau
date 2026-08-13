--!strict
--[[
	SaltCarry — may this player pick up a salt pouch right now? (§4.6, C13)

		(request) -> verdict

	§4.6 IN THREE LINES: "4 salt pouches spawn at random fixed points per round. One per player carried.
	Recharge: none in MVP. Once used, it's gone. Scarcity makes it a decision."

	The scarcity half is enforced by `Config.Salt.SpawnCount`; THIS module enforces the carry half, and
	it is a separate rule because the two fail differently. A map with too few pouches is a balance
	problem you notice. A carry limit that does not hold is an exploit: walk the six spawn points, hold
	six pouches, and the one counterplay item in the game stops being a decision and becomes an arsenal.

	WHY A VERDICT RATHER THAN A BOOLEAN — the same argument TransformRules and KillValidation make. The
	server logs WHY it declined, and "you are a ghost standing on a pouch" and "you already have one"
	send a reader to two different places. C41 reads those lines.

	NOTHING HERE IS SECRET AND NOTHING HERE MAY BECOME SECRET. The weight rule in `pure/TaskWeight` had
	to earn its role-blindness with a grid; this module never takes a role at all, and it must not start.
	A carry limit that differed for the Aswang would be a role oracle readable by standing on a pouch.

	IT LIVES IN `src/shared/pure/` AND NOT `src/server/pure/`, which is CLAUDE.md's test applied rather
	than assumed: are the inputs client-suppliable, and is there a seed? There is no seed, and every
	input is already on the client — the phase and `YourState` ride the snapshot, and `CarryLimit` is in
	the replicated Config. A client that requires and runs this module learns that it may not carry two
	pouches, which it could also learn by trying. `TaskPool` is server-side because its inputs are the
	map's pool contents; this module has nothing of the sort.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural, so these and
	the ones in Types.luau are the same types and pass to each other without a cast.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict = "OK" | "WRONG_PHASE" | "NOT_ALIVE" | "AT_LIMIT" | "NO_LIMIT_SET"

export type Request = {
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Carried: number,
	Limit: number,
}

local SaltCarry = {}

--[[
	ORDER IS FIXED AND IS PART OF THE CONTRACT, exactly as in KillValidation: world facts first, then
	the player, then the count. A log full of AT_LIMIT is a UX finding — players walking over pouches
	they cannot take — and a log full of anything above it is a correctness finding.

	NOT_ALIVE is an ALLOWLIST of ALIVE, never `~= "SPECTATOR"`. A GHOST must not pick up salt: §4.7
	gives ghosts contribution and a spook, not the counterplay item, and C15 makes GHOST a state that a
	body walks around in — so the denylist form starts admitting them the moment Phase 6 lands. This is
	`pure/PlayerBody`'s warning in a second file, and it is the specific mistake that file predicted.
]]
function SaltCarry.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	if request.PlayerState ~= "ALIVE" then
		return "NOT_ALIVE"
	end

	--[[
		FAIL CLOSED ON THE LIMIT, and test it for positive-and-finite rather than for zero.

		`Limit` arrives from Config. A `CarryLimit` typo of `0` reads as "carry nothing" and would be
		caught by the comparison below; `-1` and `0/0` would not. `Carried < NaN` is false, so a NaN
		limit refuses — but `math.huge` is worse than either, because `Carried < inf` is always true
		and the limit silently stops existing. KillValidation's cooldown took three attempts to get
		this right (see its header); this is the fourth version of that lesson, applied first time.
	]]
	if not (request.Limit > 0 and request.Limit < math.huge) then
		return "NO_LIMIT_SET"
	end

	--[[
		`>=`, NOT `>`. With CarryLimit = 1, a player holding one pouch has Carried == Limit and must be
		refused; `>` would admit them and the limit would be off by exactly one, which is the whole
		limit when the limit is one. This is the comparison C13's Verify line exercises — "picks up two
		in a row and is refused the second".

		NaN Carried refuses too: `NaN >= 1` is false, so it would fall through to OK — which is why the
		guard above rejects a non-finite LIMIT, and why the test grid below covers a NaN CARRIED
		explicitly rather than trusting this line to be symmetric. It is not.
	]]
	if request.Carried >= request.Limit then
		return "AT_LIMIT"
	end

	--[[
		The NaN-carried hole the comment above names, closed. `Carried` arrives from a server table
		keyed by UserId; a missing entry should read 0, and any arithmetic that produced NaN upstream
		must not be rewarded with a pouch. Ordered last so a legitimate refusal is reported as itself.
	]]
	if not (request.Carried >= 0 and request.Carried < math.huge) then
		return "AT_LIMIT"
	end

	return "OK"
end

return SaltCarry
