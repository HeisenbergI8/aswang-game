--!strict
--[[
	FetchCarry — what should happen to one fetch item this tick? (§4.4, C09)

		decide(request) -> "NONE" | "PICK_UP" | "DELIVER" | "DROP"

	IT TAKES WEIGHTS, NOT PLAYERS, AND THAT IS THE WHOLE SECURITY DESIGN.

	Amendment A2 requires that no code path special-case the Aswang's contribution. The enforceable
	form of that is `server/pure/TaskWeight.luau` and its `PlayerState × Role` grid; this module
	inherits the property instead of restating it, because it never sees a role. There is nowhere in
	this file for a role branch to be written, which is a stronger statement than a comment asking
	nobody to write one.

	`FullWeight` arrives as a parameter — `Config.Tasks.FullContributionWeight` — so "who may carry"
	is one number in one file. A GHOST weighs `Config.Ghost.TaskContributionMult` (0.25) and therefore
	cannot pick an item up, which is C15's answer arrived at for free: §4.7 asks a ghost to contribute
	to a task, not to move objects through the world.

	DROP OUTRANKS DELIVER, AND THE ORDER IS A DECISION.

	A carrier who is killed while standing on the destination drops the item; they do not complete the
	errand with their last frame. C09's brief calls dropping on death "correct, and creates good
	moments" — the moment is the item lying beside the corpse where the next survivor finds it, and it
	only exists if death beats delivery.

	DROP IS NOT NAMED "DEATH", DELIBERATELY. A carrier stops carrying when they stop being a full
	contributor, and being killed is one of four ways that happens: disconnecting, being reset, and
	joining mid-round as a SPECTATOR are the others. A branch per cause would have missed three.

	NO `script.Parent` REQUIRES and no Roblox datatypes — booleans and numbers only, so Lune runs it.
]]

export type Action = "NONE" | "PICK_UP" | "DELIVER" | "DROP"

export type Request = {
	HasCarrier: boolean,
	-- The carrier's TaskWeight. Meaningless, and ignored, when HasCarrier is false.
	CarrierWeight: number,
	CarrierAtDestination: boolean,
	-- The nearest player standing at the SOURCE, and their TaskWeight. Zero when nobody is there.
	CandidateWeight: number,
	CandidateAtSource: boolean,
	FullWeight: number,
}

local FetchCarry = {}

function FetchCarry.decide(request: Request): Action
	if request.HasCarrier then
		if request.CarrierWeight < request.FullWeight then
			return "DROP"
		end

		if request.CarrierAtDestination then
			return "DELIVER"
		end

		return "NONE"
	end

	if request.CandidateAtSource and request.CandidateWeight >= request.FullWeight then
		return "PICK_UP"
	end

	return "NONE"
end

return FetchCarry
