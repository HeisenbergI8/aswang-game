--!strict
--[[
	AmbientTerritory — which form belongs where, and which slot a monster standing HERE may take.

		pointsFor(points, form)                              -> the territories of one form
		nearestFreeIndex(points, free, form, x, z, radius)   -> a claimable slot, or nil

	WHY FORMS HAVE TERRITORIES AT ALL. §5 asks for a barrio, and a barrio is not a field of randomly
	scattered animals: a pig is penned or tethered in mud, chickens forage a household yard, a goat is
	staked at a field edge and moved every day or two, cats work the alleys, dogs hold the road, people
	sit on porches and at the store. All six of those are how the animals are actually kept — see
	`references/research-01-barrio-animals.md`, where the tethering and yard-keeping are sourced.

	AND WHY THAT IS A MECHANIC RATHER THAN DRESSING. It constrains the ASWANG. A pig on the basketball
	court is now wrong, so the monster can only wear a pig near mud. That is a deliberate tactical cost
	and it is the counterplay §4.5 wants — camouflage stops being "hide anywhere" and becomes "hide
	where this animal would be", which is a decision a survivor can learn to read.

	THE REFUSAL IS THE POINT, AND IT ALSO CLOSED A JUMP. On claim, `MonsterService` drives the entity
	to the monster. Without a bound the entity crossed the whole barrio in one frame — a pig
	disappearing from the well and reappearing on the ring road, which under territories reads as an
	answer rather than as an oddity. Bounding the claim to `radius` bounds the jump to `radius`.

	NO SEED, NO DRAW, AND NO CLIENT-SUPPLIABLE INPUT. `x` and `z` are the SERVER's copy of the
	monster's own root position. This module is replicated and any client may run it, which is fine for
	the reason `CamouflageRules`' header gives at length: what it computes is a rule the map states in
	public — the pig pens are visible — and the inputs it would need to be interesting are server-only.

	NO `script.Parent` REQUIRES — Lune has no `script`. `Form` is plain `string` here on purpose: this
	module never returns a form, only an index, so there is no literal union to widen on the way out
	and `.claude/lessons/pure-module-unions-widen-in-lists.md` does not apply.
]]

export type Point = {
	Form: string,
	X: number,
	Z: number,
}

local AmbientTerritory = {}

-- Every territory of one form, in declaration order. Used by the map contract's coverage and spread
-- assertions rather than by the game, which asks the sharper question below.
function AmbientTerritory.pointsFor(points: { Point }, form: string): { Point }
	local owned: { Point } = {}

	for _, point in points do
		if point.Form == form then
			table.insert(owned, point)
		end
	end

	return owned
end

--[[
	THE NEAREST FREE SLOT OF THIS FORM WITHIN `radius`, OR nil.

	`free` IS INDEXED IN LOCKSTEP WITH `points`, which is the contract that lets this module answer
	without knowing what a roster is. `AmbientService` spawns one rig per point in point order, so slot
	index and point index are the same number — and that identity is asserted in
	`tests/barrio-ambient.test.luau` rather than assumed here.

	NEAREST RATHER THAN FIRST, and the reason is an exploit audit's finding one level along. V07 found
	that a first-free pick made every hide in every round the same slot, so a survivor could camp it;
	`AmbientService` answered with a random pick. Under territories, random is wrong again for a new
	reason — a random slot within radius is a longer jump than the nearest one, and the jump is the
	visible artefact. Nearest minimises what a bystander sees, and the radius bound is what keeps the
	choice from being campable: which of the three territories the monster uses is decided by where it
	chose to walk, which is not something a survivor can camp without following it.

	SQUARED DISTANCE, NO SQUARE ROOT. Monotonic, so the ordering is identical, and the caller's radius
	is squared once rather than a root taken per candidate.
]]
function AmbientTerritory.nearestFreeIndex(
	points: { Point },
	free: { boolean },
	form: string,
	x: number,
	z: number,
	radius: number
): number?
	local bestIndex: number? = nil
	local bestDistance = radius * radius

	for index, point in points do
		if point.Form ~= form or free[index] ~= true then
			continue
		end

		local dx = point.X - x
		local dz = point.Z - z
		local distance = dx * dx + dz * dz

		--[[
			`<` RATHER THAN `<=`, so a tie keeps the earlier index. Deterministic ordering matters
			here: two territories at exactly equal distance would otherwise resolve by table order,
			which is the same thing, but writing it down stops a later "optimisation" from making the
			answer depend on iteration order.
		]]
		if distance < bestDistance then
			bestDistance = distance
			bestIndex = index
		end
	end

	return bestIndex
end

return AmbientTerritory
