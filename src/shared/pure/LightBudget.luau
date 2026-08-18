--!strict
--[[
	LightBudget — which map lights stay lit, as a pure function. (C27, §5)

		choose(input) -> { boolean }   -- parallel to input.Candidates

	§5's mobile budget is the one part of the spec called NON-NEGOTIABLE, and its sharpest line is
	"cap dynamic lights to ~8 visible at once — many point lights are the #1 mobile FPS killer".
	`Config.Performance.MaxVisibleLights` has held that 8 since the scaffold and nothing spent it.
	This module spends it: given how far each map light is from the camera, it returns which ones a
	client keeps lit.

	WHY A SORT IS NOT ENOUGH, WHICH IS THE WHOLE REASON THIS IS A TESTED MODULE
	---------------------------------------------------------------------------
	Take the nearest N by distance and a player standing still between two equidistant lanterns makes
	them TRADE the last slot on every pass — a strobing street lamp, which is a worse artifact than
	the frame it saved. `HysteresisStuds` is the fix: a lantern that is already lit keeps its slot
	until a rival is that much closer. It costs one subtraction and it is invisible until it is
	missing, which is exactly the kind of rule that belongs where a test can see it.

	The second trap is ties. Two lanterns at an identical distance must resolve the same way every
	pass or they flicker for a different reason, so the sort falls back to the candidate's index and
	the answer is total and deterministic over any input.

	WHAT THIS MODULE IS NOT ALLOWED TO KNOW ABOUT
	----------------------------------------------
	It never sees a gameplay light. The Aswang's eye glow (`Monster.EyeGlowRgb`) and a salt pouch's
	glow are TELLS — the things a player is straining to see — and a culler that could switch one off
	would be deciding what a player is allowed to notice. So the caller only ever hands it lights the
	greybox tagged as scenery, and `Reserved` subtracts the slots those tells need from the allowance.
	The budget is shared; the decision is not.

	NO SECRET REACHES THIS. Distances from a camera to a lantern, on the client that owns the camera.
	Every client runs the same rule over its own view, nothing goes on the wire, and a lit lantern is
	lit for whoever is standing next to it regardless of who they are — see
	`.claude/lessons/absence-is-observable.md` for why that last clause is the one worth stating.

	NO `script.Parent` REQUIRES (tests/README.md): no Config, no Types, no Instances. A `Light` is
	reduced to a distance and a boolean before it gets here.
]]

export type Candidate = {
	Distance: number, -- studs, camera to light
	WasOn: boolean, -- whether this light is lit RIGHT NOW, for the hysteresis term
}

export type Input = {
	Candidates: { Candidate },
	Budget: number, -- Config.Performance.MaxVisibleLights
	Reserved: number, -- Config.Performance.ReservedGameplayLights
	CullRadiusStuds: number, -- past this, off regardless of the budget
	HysteresisStuds: number, -- how much closer a rival must be to take a lit slot
}

local LightBudget = {}

--[[
	The allowance the MAP may spend, which is the budget minus what the gameplay lights need.

	Floored at zero rather than allowed to go negative: a `Reserved` larger than `Budget` is a config
	error, and the honest failure is a dark map rather than an arithmetic one.
	`tests/config.test.luau` pins the two apart so the dark map never ships.
]]
local function allowanceFor(budget: number, reserved: number): number
	return math.max(0, math.floor(budget) - math.floor(reserved))
end

--[[
	WHICH LIGHTS STAY ON.

	Returns a boolean per candidate, in the same order, so the caller can apply it by index without
	holding a key for each light. The input is never mutated — the caller's list is the live one it
	built from the map, and a sort in place would reorder the thing it is indexed against.
]]
function LightBudget.choose(input: Input): { boolean }
	local count = #input.Candidates
	local decisions = table.create(count, false)

	for index = 1, count do
		decisions[index] = false
	end

	local allowance = allowanceFor(input.Budget, input.Reserved)

	if allowance == 0 or count == 0 then
		return decisions
	end

	--[[
		Rank over a COPY, and rank by an effective distance rather than the real one.

		A lit light is ranked as though it were `HysteresisStuds` closer than it is. That is the
		anti-flicker rule in one line: it wins its own slot back against anything not decisively
		nearer, and loses it cleanly to something that is.
	]]
	local order = table.create(count)

	for index = 1, count do
		local candidate = input.Candidates[index]

		order[index] = {
			Index = index,
			Effective = candidate.Distance - (if candidate.WasOn then input.HysteresisStuds else 0),
		}
	end

	-- Index breaks ties, so the same input always produces the same answer. Two lanterns at an equal
	-- distance that swapped between passes would flicker for a different reason than hysteresis fixes.
	table.sort(order, function(a, b): boolean
		if a.Effective == b.Effective then
			return a.Index < b.Index
		end

		return a.Effective < b.Effective
	end)

	local lit = 0

	for _, entry in order do
		if lit >= allowance then
			break
		end

		-- The RAW distance, not the effective one: hysteresis decides who wins a slot, never whether
		-- a light 200 studs away is worth one at all.
		if input.Candidates[entry.Index].Distance <= input.CullRadiusStuds then
			decisions[entry.Index] = true
			lit += 1
		end
	end

	return decisions
end

return LightBudget
