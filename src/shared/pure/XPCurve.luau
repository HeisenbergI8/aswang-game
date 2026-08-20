--!strict
--[[
	XPCurve — what a level costs, and what a round is worth. (C32, §7, §4.8)

		levelFor(xp, curve)   -> Standing   -- level, and how far into it
		totalForLevel(l, c)   -> number     -- cumulative XP needed to REACH level l
		awardFor(input, rates) -> Award     -- what one finished round pays one player

	WHY BOTH HALVES LIVE IN ONE MODULE. They are one decision read from two ends: the award decides
	how fast the bar fills and the curve decides how far it has to go, and tuning either in isolation
	at M12 is how "level 5 in twenty minutes" and "level 5 in nine hours" both ship. Keeping them
	adjacent means the test suite can walk a plausible session end-to-end and say how long a level
	actually takes, which is the number §7 is really about.

	WHY IT IS PURE. `ProgressionService` is the Roblox-shaped half — profiles, DataStores, player
	lifecycle — and none of that can run under Lune. What CAN be proven from a terminal is the
	arithmetic, and the arithmetic is where this fails silently: a curve that is not monotone shows a
	bar going backwards, a division by zero at the level cap writes NaN into a profile, and neither
	produces an error anybody sees. `tests/xp-curve.test.luau` is C32's Verify line for that reason.

	NO `script.Parent` REQUIRES (tests/README.md). `RoundResult` is re-declared — Luau unions are
	structural, so this and `Types.RoundResult` are the same type — and every tunable arrives as a
	parameter out of `Config.Economy`.

	── THE SECRECY RULE THIS MODULE IS BUILT AROUND ──────────────────────────────

	`ProgressionService`'s C31 award carries a warning worth restating, because C32 is the chunk that
	walks up to it: "the moment the award is role-conditional, the XP number itself becomes a derived
	hint — a player comparing their end-screen total against a friend's would learn something the round
	never told them."

	§4.8's award table IS role-conditional — a win bonus, a survivor's escape bonus, the Aswang's own
	per-kill split — so the warning is not avoided, it is DISCHARGED, and `RoleIsPublic` is where.

	The discharge is that the award lands at ENDING, in the same phase as the reveal: `RoundEnded`
	broadcasts `AswangUserId` to every client, so by the time any XP is written the role is already
	public knowledge and a cross-player comparison learns nothing the screen did not just announce.

	`RoleIsPublic = false` is the branch for a round that reached ENDING with nobody revealed. Every
	role-derived term is then dropped and the award collapses to flat participation, identical for all
	eight players. It is defensive rather than reachable today — `state.AswangUserId` survives both
	abort paths, so a real round always reveals — and it is written anyway, because the cost of being
	wrong about that is the one leak this whole game is about.

	NOTHING SECRET PASSES THROUGH otherwise. `WasAswang` arrives already-public by the rule above; no
	other player's role, name or id is an input, and the output describes exactly one player.
]]

export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"

--[[
	THE CURVE, AS THREE NUMBERS.

	Level 1 -> 2 costs `Base`. Every level after that costs `Growth` more than the one before it, so
	the cumulative cost is triangular rather than linear: early levels arrive fast enough to teach the
	player that the bar means something, and late ones are a long-term goal rather than a treadmill.

	`MaxLevel` is not decoration. It is what makes `levelFor` terminate on a corrupt XP value and what
	stops `totalForLevel` from being asked for level 10^9, where the triangular term overflows into a
	float that cannot be compared usefully. It is also the boundary the division-by-zero lives on —
	see `levelFor`.
]]
export type Curve = {
	Base: number,
	Growth: number,
	MaxLevel: number,
}

export type Standing = {
	Level: number,
	XPIntoLevel: number,
	-- How much more XP this player needs for the NEXT level. Exactly 0 at `MaxLevel`, and every
	-- consumer has to treat that as a terminal state rather than as a divisor.
	XPForNextLevel: number,
	Progress: number, -- 0..1, and 1 at MaxLevel
}

export type Rates = {
	XPPerRound: number,
	XPWinBonus: number,
	XPSurvivorEscapeBonus: number,
	XPPerKill: number,
	CoinsPerRound: number,
	CoinsWinBonus: number,
}

export type AwardInput = {
	Result: RoundResult,
	--[[
		Whether the reveal has already told every client who the Aswang was. See the header: this is
		the single field that makes a role-conditional award safe, and `false` collapses the award to
		flat participation rather than merely omitting one line.
	]]
	RoleIsPublic: boolean,
	WasAswang: boolean,
	Survived: boolean, -- ALIVE at ENDING, rather than "was never killed"
	Kills: number, -- the Aswang's validated kills this round; 0 for everyone else
}

-- One line of the end screen's breakdown. Plain strings and numbers, so no literal union travels in
-- a list — see `.claude/lessons/pure-module-unions-widen-in-lists.md`.
export type AwardLine = {
	Label: string,
	XP: number,
	Coins: number,
}

export type Award = {
	XP: number,
	Coins: number,
	Lines: { AwardLine },
}

local XPCurve = {}

--[[
	A stored number is attacker-adjacent input in the same sense `ProfileMigration.num` describes: not
	because a client can write it, but because a corrupt save or an arithmetic bug upstream must
	degrade to a floor rather than propagate a NaN into a profile that then fails every DataStore
	write for that player, permanently.

	`value >= 0 and value < math.huge` is the finite test and rejects NaN as well, since NaN fails
	every comparison. `math.huge` specifically is the case a `~= itself` test misses.
]]
local function finite(value: number, fallback: number): number
	if type(value) ~= "number" or not (value >= 0 and value < math.huge) then
		return fallback
	end

	return math.floor(value)
end

--[[
	THE CUMULATIVE XP NEEDED TO REACH `level`, closed form.

	  totalForLevel(1) = 0                            -- everybody starts here
	  totalForLevel(2) = Base
	  totalForLevel(n) = Base*(n-1) + Growth*(n-1)*(n-2)/2

	Clamped to `MaxLevel` at the top and to 1 at the bottom, so a corrupt `Level` field or a caller
	asking for level 0 gets a number rather than a negative cost.
]]
function XPCurve.totalForLevel(level: number, curve: Curve): number
	local maxLevel = math.max(math.floor(curve.MaxLevel), 1)
	local clamped = math.clamp(math.floor(finite(level, 1)), 1, maxLevel)
	local steps = clamped - 1

	return curve.Base * steps + curve.Growth * steps * (steps - 1) / 2
end

--[[
	WHERE A GIVEN XP TOTAL PUTS A PLAYER.

	Walked rather than solved. The closed-form inverse of a triangular series is a quadratic with a
	square root in it, and at the boundaries that root lands a hair below an exact level — so a player
	with EXACTLY `totalForLevel(5)` reads as level 4 with a full bar, forever, and no test written
	against round numbers would catch it because the round numbers are the ones that break. The walk
	is bounded by `MaxLevel` and runs a hundred cheap comparisons at most, on a call made once per
	round and once per HUD update.

	THE DIVISION BY ZERO IS AT THE TOP, NOT AT LEVEL 1, and that is worth naming because C32's Verify
	line asks about level 1. Level 1's span is `Base`, which is a positive tunable; the level CAP is
	where the next level costs nothing at all, and `remaining / span` there is 0/0. So `Progress` is
	pinned to 1 and `XPForNextLevel` to 0 at the cap, before any division happens.
]]
function XPCurve.levelFor(xp: number, curve: Curve): Standing
	local total = finite(xp, 0)
	local maxLevel = math.max(math.floor(curve.MaxLevel), 1)
	local level = 1

	while level < maxLevel and total >= XPCurve.totalForLevel(level + 1, curve) do
		level += 1
	end

	local floorXP = XPCurve.totalForLevel(level, curve)
	local intoLevel = total - floorXP

	if level >= maxLevel then
		return {
			Level = level,
			XPIntoLevel = intoLevel,
			XPForNextLevel = 0,
			Progress = 1,
		}
	end

	local span = XPCurve.totalForLevel(level + 1, curve) - floorXP

	--[[
		A zero or negative span means `Base` and `Growth` have been tuned into a curve where a level
		costs nothing, which is a Config error rather than a player state. Answering "full bar" is the
		degradation that keeps a NaN out of the profile; `tests/config.test.luau` is where the tuning
		itself is pinned.
	]]
	if span <= 0 then
		return {
			Level = level,
			XPIntoLevel = intoLevel,
			XPForNextLevel = 0,
			Progress = 1,
		}
	end

	return {
		Level = level,
		XPIntoLevel = intoLevel,
		XPForNextLevel = span - intoLevel,
		Progress = math.clamp(intoLevel / span, 0, 1),
	}
end

--[[
	DID THIS PLAYER'S SIDE WIN.

	§4.8's table, read from one player's seat. TIMEOUT and ASWANG_WINS are both Aswang wins — the
	sunrise half of the row — and ABORTED is nobody's, which is the honest answer for a round that was
	void: the Aswang disconnected, or reset into a ghost, and neither side played it out.
]]
local function wonTheRound(result: RoundResult, wasAswang: boolean): boolean
	if result == "ABORTED" then
		return false
	end

	if wasAswang then
		return result == "ASWANG_WINS" or result == "TIMEOUT"
	end

	return result == "SURVIVORS_ESCAPED"
end

--[[
	WHAT ONE FINISHED ROUND PAYS ONE PLAYER (§4.8's end screen).

	The participation term is unconditional and comes first, because it is the only term that is
	identical for all eight players — it is what the award collapses to when `RoleIsPublic` is false,
	and it is the floor that makes a round the player lost still worth having played. §7's whole
	argument is that a session ends near a milestone; a losing round paying nothing is a session that
	ends at the same distance it started.

	Every other term reads the role, directly or by implication, and therefore sits behind
	`RoleIsPublic`. See the header for why that is sufficient rather than merely careful.

	`Lines` is the end screen's breakdown, and it exists so the number is legible: "+115 XP" teaches a
	player nothing about what to do differently, and "+50 round / +40 your side won / +25 you survived"
	teaches them the three things the game wants them to want.
]]
function XPCurve.awardFor(input: AwardInput, rates: Rates): Award
	local lines: { AwardLine } = {}

	local xp = finite(rates.XPPerRound, 0)
	local coins = finite(rates.CoinsPerRound, 0)

	table.insert(lines, { Label = "round played", XP = xp, Coins = coins })

	if not input.RoleIsPublic then
		return { XP = xp, Coins = coins, Lines = lines }
	end

	if wonTheRound(input.Result, input.WasAswang) then
		local bonusXP = finite(rates.XPWinBonus, 0)
		local bonusCoins = finite(rates.CoinsWinBonus, 0)

		xp += bonusXP
		coins += bonusCoins

		table.insert(lines, { Label = "your side won", XP = bonusXP, Coins = bonusCoins })
	end

	--[[
		THE ESCAPE BONUS IS A SURVIVOR'S, and gating it on `not WasAswang` is not bookkeeping. The
		Aswang is alive at ENDING in every round it does not abort, so an ungated "you survived" line
		would pay it a bonus for existing — and worse, it would pay the same bonus on a round the
		Aswang LOST, which inverts what §7 wants the number to teach.
	]]
	if not input.WasAswang and input.Survived then
		local bonus = finite(rates.XPSurvivorEscapeBonus, 0)

		xp += bonus

		table.insert(lines, { Label = "you survived the night", XP = bonus, Coins = 0 })
	end

	if input.WasAswang then
		local kills = finite(input.Kills, 0)

		if kills > 0 then
			local perKill = finite(rates.XPPerKill, 0)
			local total = perKill * kills

			xp += total

			table.insert(lines, { Label = `{kills} kill(s)`, XP = total, Coins = 0 })
		end
	end

	return { XP = xp, Coins = coins, Lines = lines }
end

return XPCurve
