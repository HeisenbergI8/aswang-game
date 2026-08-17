--!strict
--[[
	QuickChatTarget — who does `"It's [nearest player]!"` actually name? (§4.5, C25)

		({ Candidate }, maxRangeStuds) -> userId?

	THE CLIENT SUPPLIES NO PART OF THIS. C25's row says a client-supplied name is a free
	impersonation exploit, and it is: `FireServer("RequestQuickChat", "ACCUSE", "Bob")` lets any
	player put any name in every other player's HUD, attributed to themselves, from anywhere on the
	map. The remote therefore carries a phrase id and nothing else, and the target is resolved here
	from positions the SERVER owns.

	WHY LINE OF SIGHT IS REQUIRED AND NOT JUST RANGE — THE PROXIMITY ORACLE
	----------------------------------------------------------------------
	Range alone turns this phrase into a radar. Fire it repeatedly and the server answers "who is
	within 40 studs of me", through walls, roughly every two seconds at the C25 budget (Capacity 4,
	RefillPerSecond 0.5). The player with the most to gain from that is the Aswang mid-hunt, and it
	would be a hunting tool handed over by the communication feature.

	Requiring line of sight collapses the oracle to nothing: a hit names somebody the sender can
	already see, and — this is the half that is easy to miss — so does a MISS. `NO_TARGET_IN_SIGHT`
	tells the sender "nobody is visible near you", which their eyes said first. Both outcomes are
	information the sender already had, which is the property that makes the phrase safe to spam.

	The service does the raycast, because a raycast is a DataModel call. This module takes the
	ANSWER, so the rule stays enumerable from a terminal.

	NO `Vector3`, DELIBERATELY. Lune has no `Vector3` and no raycast, so a module that took positions
	would not be runnable from a terminal and the whole point of putting it in `pure/` is lost. The
	caller measures; this decides.

	NO `script.Parent` REQUIRES.
]]

export type Candidate = {
	UserId: number,
	-- Studs from the SENDER, measured server-side by the caller.
	DistanceStuds: number,
	-- `GhostChat.isLivingSide` of this candidate, computed by the caller. A candidate the sender
	-- cannot see because they are dead is not a candidate.
	IsAliveSide: boolean,
	-- The result of the caller's raycast. See the header: this is the whole anti-oracle defence.
	HasLineOfSight: boolean,
}

local QuickChatTarget = {}

--[[
	The nearest eligible candidate, or nil.

	AN ALLOWLIST OF CONDITIONS, in the discipline `pure/GhostChat` and `pure/PlayerBody` both use: a
	candidate must pass EVERY test to be eligible, so a field added to `Candidate` later defaults to
	"does not qualify anybody" rather than to "silently admits a new class".

	THE CALLER MUST NOT PUT THE SENDER IN THE LIST, and this module does not know who the sender is
	so it cannot check. That is a real seam and it is why `tests/quick-chat-target.test.luau`
	includes a case asserting the caller's own exclusion, and why the service builds the list by
	iterating `Players:GetPlayers()` with an explicit `player ~= sender` rather than by filtering
	afterwards.

	TIES BREAK TO THE LOWEST USERID. Two players at identical distance is vanishingly rare and
	completely possible, and an unstable answer there means the same situation names different people
	on different frames — which reads to players as the feature being broken, and to an auditor as
	nondeterminism on the 🔒 surface. Lowest UserId is arbitrary but it is STABLE, which is the
	property that matters.
]]
function QuickChatTarget.nearest(candidates: { Candidate }, maxRangeStuds: number): number?
	--[[
		THE RANGE IS GUARDED BEFORE ANY CANDIDATE IS LOOKED AT, and this test was written before the
		guard existed and failed — which is the reason it is here rather than assumed.

		`distance > maxRangeStuds` is FALSE when `maxRangeStuds` is NaN, so a NaN range does not
		refuse everybody as you would expect. It admits EVERYBODY: every candidate sails past the
		range test and the nearest visible player is named regardless of how far away they are. The
		safe-looking comparison fails open, on the one phrase in the game that names another player.

		Refusing outright rather than clamping: a range this module cannot make sense of means the
		caller is broken, and naming somebody on a broken input is worse than naming nobody.
	]]
	if not (maxRangeStuds >= 0 and maxRangeStuds < math.huge) then
		return nil
	end

	local bestUserId: number? = nil
	local bestDistance = math.huge

	for _, candidate in candidates do
		if not candidate.IsAliveSide then
			continue
		end

		if not candidate.HasLineOfSight then
			continue
		end

		--[[
			Guard against a NaN distance BEFORE the range test rather than after. `NaN > x` is false,
			so a NaN slips past a range comparison — it would then lose every distance comparison
			below and be excluded anyway, but only by accident. An accident is not a guarantee, and
			the next edit to the comparison order would silently admit it.
		]]
		if candidate.DistanceStuds ~= candidate.DistanceStuds then
			continue
		end

		if candidate.DistanceStuds > maxRangeStuds then
			continue
		end

		local closer = candidate.DistanceStuds < bestDistance
		local tiedButLower = candidate.DistanceStuds == bestDistance
			and bestUserId ~= nil
			and candidate.UserId < bestUserId

		if closer or tiedButLower then
			bestDistance = candidate.DistanceStuds
			bestUserId = candidate.UserId
		end
	end

	return bestUserId
end

return QuickChatTarget
