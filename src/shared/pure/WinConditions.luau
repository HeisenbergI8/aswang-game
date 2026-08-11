--!strict
--[[
	WinConditions — has the Aswang won by attrition? (§4.8, C06)

		(request) -> boolean

	A SIBLING OF RoundTransitions RATHER THAN A ROW IN IT, and the split is on purpose. That module
	answers "what happens next given a phase and a timer" and its exhaustive 5×2×2 table is its whole
	value; a headcount rule threaded through it would multiply that table by the roster. This one
	answers a different question, over different inputs, and C11's survivor win becomes a second
	function in this same file rather than a third place to look.

	§4.8 IN ONE LINE IS WRONG, AND THIS IS THE POINT OF THE MODULE
	--------------------------------------------------------------
	"Aswang wins when living survivors ≤ 2" is right for the 6–8 player round the spec pictures and
	degenerate below it. Config.Round.MinPlayers is 3 — one Aswang and two survivors — so the literal
	rule is TRUE BEFORE ANYONE MOVES. A three-player round would end the instant it began, on the exact
	server population §9 calls the cold-start risk and the exact one the Solo Trial exists to cover.

	The fix is to read the threshold as what it means: MOST OF THEM ARE DEAD. So the effective
	threshold is clamped to one below however many survivors were dealt in, and a round that started at
	or under the threshold uses "one fewer than we started with" instead of a number that was already
	satisfied.

		dealt in  threshold  effective  wins when living survivors reach
		--------  ---------  ---------  --------------------------------
		7 (8p)    2          2          2
		5 (6p)    2          2          2
		2 (3p)    2          1          1
		1         2          0          0
		0 (solo)  2          —          never; see the guard below

	NO `script.Parent` REQUIRES, and the threshold arrives as a parameter rather than being read from
	Config — same rule as every other pure module here.
]]

export type Request = {
	-- Survivors (NOT players) currently ALIVE. The Aswang is excluded by the caller; a count that
	-- included it would be off by one at exactly the boundary that matters.
	LivingSurvivors: number,
	-- Survivors dealt into the round at STARTING. A snapshot, not a live count: it must not move when
	-- someone disconnects, or the rule quietly re-scales itself mid-round.
	DealtInSurvivors: number,
	Threshold: number,
}

local WinConditions = {}

function WinConditions.aswangWinsByAttrition(request: Request): boolean
	--[[
		NOBODY TO KILL, SO NOTHING TO WIN.

		This is the solo Studio round (Debug.SoloTesting plus Debug.ForceAswangWhenSolo, which since
		commit 3c70cfc makes the lone player the Aswang). Zero survivors satisfies every threshold on
		tick one, and an agent driving a solo round would see it end before ACTIVE was a second old.

		It is also the honest answer for a live server: a round with no survivors in it was never a
		contest, so there is no attrition to measure. Such a round still ends — the sunrise timer takes
		it to ENDING with TIMEOUT, which §4.8 already scores as an Aswang win. Nothing hangs.
	]]
	if request.DealtInSurvivors <= 0 then
		return false
	end

	local effective = math.min(request.Threshold, request.DealtInSurvivors - 1)

	return request.LivingSurvivors <= effective
end

return WinConditions
