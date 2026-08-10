--!strict
--[[
	RoleDraw — who is the Aswang, as a pure function.

		(candidates, history, aswangCount, weights, nextFloat) -> { [userId]: Role }

	WHY THIS FILE IS UNDER src/server/pure/ AND NOT src/shared/pure/
	----------------------------------------------------------------
	`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module there is
	require-able AND CALLABLE by any client. For `TokenBucket` that is harmless — Config.AntiCheat is
	replicated anyway, so the module publishes nothing new.

	For this module it is the security of the entire game. The algorithm being public is fine; a
	REPRODUCIBLE draw is not. Algorithm + inputs + seed = this round's assignment, and an exploiter who
	reproduces all three knows the Aswang BEFORE the round starts — with no remote to intercept and
	nothing for `check:secrecy` to see. It is the only leak in this game that leaves no trace on the
	wire.

	`src/server` maps to ServerScriptService, which does not replicate. So the client cannot call this
	even with a correct guess at every input. Two rules are still enforced at the call site, because
	defence in depth is the point and because the next author may not read this comment:

	  · The RNG is INJECTED, never created here, and RoleService seeds it with `Random.new()` — no
	    argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and
	    both fatal.
	  · `history` is server-only in-memory state. It is a DRAW INPUT, so it is treated as secret even
	    though every past Aswang was already revealed by RoundEnded (§4.8): every input a client holds
	    shrinks the search space for the one it does not.

	Lune resolves test requires by FILE PATH and knows nothing about Rojo, so this location costs no
	testability — `tests/role-draw.test.luau` requires "../src/server/pure/RoleDraw" and runs identically.

	NO `script.Parent` REQUIRES, same rule as every other pure module. The Role type is re-declared
	below; Luau literal unions are structural, so this and `Types.Role` are the same type.

	NOTE `check-config.mjs` governs `src/server/`, so this file — unlike `src/shared/pure/` — may not
	contain a tunable number. That is why `weights` is a parameter. It is the right shape anyway: §4.2's
	"heavily reduced weight" is a balance knob and M12 tunes it.
]]

export type Role = "SURVIVOR" | "ASWANG"

export type Weights = {
	Base: number, -- never been the Aswang, or longer ago than HistoryRounds
	Recent: number, -- the Aswang in the immediately previous round
	Older: number, -- the Aswang within HistoryRounds, but not last round
	HistoryRounds: number, -- how far back the history is consulted
}

-- Most recent round FIRST. history[1] is the UserIds drawn as Aswang last round.
export type History = { { number } }

local RoleDraw = {}

--[[
	How likely this player is to be drawn, relative to everyone else.

	Returns a weight rather than a boolean because §4.2 asks for "heavily reduced", not "excluded". A
	zero would be an exclusion, and with MinPlayers = 3 a rule that excludes two players leaves a round
	with nobody eligible — a fallback firing under a condition nobody tested. `tests/config.test.luau`
	pins the weights positive and ordered.
]]
function RoleDraw.weightFor(userId: number, history: History, weights: Weights): number
	for roundsAgo, aswangs in history do
		if roundsAgo > weights.HistoryRounds then
			break
		end

		for _, id in aswangs do
			if id == userId then
				return if roundsAgo == 1 then weights.Recent else weights.Older
			end
		end
	end

	return weights.Base
end

--[[
	Weighted sampling WITHOUT replacement, then everyone left over is a survivor.

	`nextFloat` must return a value in [0, 1). It is called exactly once per Aswang drawn, so a caller
	can reproduce a draw exactly by replaying the same stream — which is what makes 10,000 seeded rounds
	testable, and which is precisely why the module must not replicate.

	`candidates` must be in a DETERMINISTIC order. `Players:GetPlayers()` is not, so RoleService sorts
	by UserId before calling; without that, "same seed, same result" is false and the test that proves
	this function correct proves nothing about the game.

	Degenerate inputs return a sensible assignment rather than erroring. A live server that reached one
	of these has a bigger problem than the draw, and the draw erroring inside `enterStarting` would
	leave the round stuck in STARTING with no Aswang and no log.
]]
function RoleDraw.draw(
	candidates: { number },
	history: History,
	aswangCount: number,
	weights: Weights,
	nextFloat: () -> number
): { [number]: Role }
	local assignments: { [number]: Role } = {}

	for _, userId in candidates do
		assignments[userId] = "SURVIVOR"
	end

	-- Never draw every candidate as the Aswang: a round with no survivors is over before it starts.
	local picks = math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))

	if picks == 0 then
		return assignments
	end

	-- A working copy, so removing a drawn player does not disturb the caller's list.
	local remaining = table.clone(candidates)

	for _ = 1, picks do
		local total = 0

		for _, userId in remaining do
			total += RoleDraw.weightFor(userId, history, weights)
		end

		-- Every weight is positive by contract (tests/config.test.luau), so this is unreachable. It is
		-- here because the alternative to an unreachable branch is an unreachable crash: a caller
		-- passing zeroed weights would otherwise roll into an empty range and pick nobody.
		local chosenIndex = #remaining

		if total > 0 then
			local roll = nextFloat() * total
			local cumulative = 0

			for index, userId in remaining do
				cumulative += RoleDraw.weightFor(userId, history, weights)

				if roll < cumulative then
					chosenIndex = index
					break
				end
			end
		end

		assignments[remaining[chosenIndex]] = "ASWANG"
		table.remove(remaining, chosenIndex)
	end

	return assignments
end

return RoleDraw
