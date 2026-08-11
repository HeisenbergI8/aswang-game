--!strict
--[[
	WinConditions — has the Aswang won by attrition? (§4.8, C06)

		(request) -> boolean

	IT COUNTS KILLS, NOT SURVIVORS PRESENT. That is an amendment to §4.8's wording, made deliberately
	and with the user's approval, and it is the fourth version of this rule.

	WHY THE WORDING HAD TO CHANGE
	-----------------------------
	§4.8 says "Aswang wins when living survivors ≤ 2" — a statement about PRESENCE. Presence cannot
	tell a kill from a quit, a reset, or a fall out of the world, and three separate attempts to patch
	around that failed differently:

	  1. freeze DealtInSurvivors at STARTING   — livingSurvivorCount() is computed LIVE, so a
	                                             disconnect moved one side of the comparison only
	  2. decrement it on a non-kill death      — closed reset-then-reset and nothing else
	  3. decrement it on disconnect too        — ARITHMETICALLY INERT: effective = min(2, dealt - 1)
	                                             only binds at dealt <= 3, so above four survivors the
	                                             denominator never moved while the numerator did

	Under the old rule, three alt accounts quitting an 8-player round turned a five-kill win into a
	two-kill win, and five turned it into one. No amount of bookkeeping on the denominator fixes a
	numerator that is measuring the wrong thing.

	WHAT CHANGED IN PRACTICE
	------------------------
	Killing every survivor still wins, and at a full roster the kill count is identical to the old
	rule's — 8 players, 7 survivors, threshold 2, five kills either way. What changed is that a player
	LEAVING no longer advances the Aswang. If enough survivors quit that the required kills can no
	longer be reached, the round simply runs to sunrise, and §4.8 already scores TIMEOUT as an Aswang
	win — so the Aswang is not punished for other people's disconnects either. Neither direction is
	rewarded, which is what both of this rule's previous comments falsely claimed.

	NO `script.Parent` REQUIRES, and the threshold arrives as a parameter rather than being read from
	Config — same rule as every other pure module here.
]]

export type Request = {
	-- Kills the Aswang has actually committed this round. Incremented ONLY by a validated kill, never
	-- by a death the Aswang did not cause. That distinction is the entire fix.
	AswangKills: number,
	-- Survivors dealt into the round at STARTING. A frozen snapshot, and it must stay frozen: this is
	-- the denominator that three previous versions tried to adjust, and adjusting it is what let a
	-- departure substitute for a kill.
	DealtInSurvivors: number,
	Threshold: number,
}

local WinConditions = {}

--[[
	Kills required: enough that only `Threshold` survivors could still be standing, floored at one.

	The floor is what keeps a round from being won with no kills at all — at MinPlayers = 3 the
	subtraction gives zero, and "zero kills wins" was the old rule's worst failure once enough
	survivors had removed themselves.
]]
function WinConditions.killsRequired(dealtInSurvivors: number, threshold: number): number
	return math.max(1, dealtInSurvivors - threshold)
end

function WinConditions.aswangWinsByKills(request: Request): boolean
	--[[
		NOBODY TO KILL, SO NOTHING TO WIN.

		This is the solo Studio round (Debug.SoloTesting plus Debug.ForceAswangWhenSolo, which makes
		the lone player the Aswang). Zero survivors dealt in, so no kill count can be legitimate, and
		an agent driving a solo round would otherwise see it end before ACTIVE was a second old — which
		would make every later chunk unverifiable in the only environment an agent can drive.
	]]
	if request.DealtInSurvivors <= 0 then
		return false
	end

	return request.AswangKills
		>= WinConditions.killsRequired(request.DealtInSurvivors, request.Threshold)
end

return WinConditions
