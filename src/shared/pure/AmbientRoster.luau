--!strict
--[[
	AmbientRoster — who is standing in the barrio, and which slot the monster took. (V07, §4.3/§5)

		claim(roster, form)   -> (roster, slotIndex?)   swap the monster into an existing slot
		release(roster, slot) -> roster                 give it back
		visibleCount(roster, form) -> number            what a survivor counting heads would see

	THE ONE PROPERTY THIS MODULE EXISTS TO MAKE TESTABLE: `visibleCount` is INVARIANT across a claim.
	One entity stops being real and one starts being the monster; the number of things standing in the
	barrio does not move. That is §4.3's swap-not-spawn rule expressed as arithmetic, and it is the
	only form of it a Lune test can check — `AmbientService` owns the Instances, and Lune has no
	DataModel.

	WHY THAT IS WORTH A MODULE RATHER THAN A COMMENT. The failure is silent and permanent. Spawn
	instead of swap and there are five pigs where §5 promised four — nobody counts pigs, so nobody
	notices, and the disguise degrades a little every time it is used until a survivor who DOES count
	has a free monster detector. No error, no log line, and no screenshot shows it.

	A SLOT IS AN INDEX, NEVER AN INSTANCE. This module holds no Model, no Player and no position:
	`AmbientService` maps the index back to the entity it spawned. Keeping Instances out is what lets
	the test run at all, and it is also why nothing in here could leak — there is no UserId in the
	type, so there is no arrangement of it in which one player's answer differs from another's.

	NO `script.Parent` REQUIRES — Lune has no `script`. `CamouflageForm` is re-declared; Luau unions
	are structural.
]]

export type CamouflageForm = "CAT" | "DOG" | "PIG" | "GOAT" | "CHICKEN" | "VILLAGER"

-- One ambient entity. `Claimed` means the monster is wearing this slot; the real entity has wandered
-- off and `AmbientService` has parked its Model out of the world until the slot is released.
export type Slot = {
	Form: CamouflageForm,
	Claimed: boolean,
}

export type Roster = { Slot }

local AmbientRoster = {}

--[[
	WHAT A SURVIVOR COUNTING HEADS WOULD SEE. Every slot of that form, claimed or not — because a
	claimed slot has the monster standing in it, wearing the form, and it looks exactly like the
	entity it replaced.

	THE FUNCTION IS TRIVIAL AND THE TEST OVER IT IS NOT. It is here so `visibleCount(claim(r)) ==
	visibleCount(r)` is a statement that can be written down and asserted over the whole roster space,
	rather than a property a reader has to reconstruct from `AmbientService`'s parenting.
]]
function AmbientRoster.visibleCount(roster: Roster, form: CamouflageForm): number
	local count = 0

	for _, slot in roster do
		if slot.Form == form then
			count += 1
		end
	end

	return count
end

--[[
	TAKE A SLOT OF THIS FORM, IF THERE IS ONE.

	RETURNS nil RATHER THAN CREATING ONE, and that refusal is the whole security of the mechanic.
	`CamouflageRules.evaluate` answers NO_SLOT on it and the hide does not happen. A version of this
	function that appended a slot when none was free would satisfy every test about camouflage
	working and would break the only rule §4.3 wrote in bold.

	MUTATES A COPY, NOT THE ARGUMENT. `AmbientService` holds the authoritative roster and assigns the
	returned one; a pure function that edited its input in place would be indistinguishable from a
	correct one until two callers shared a roster, which is exactly what a rejoin does.

	THE CALLER MAY NAME A PREFERRED SLOT, AND THAT IS HOW RANDOMNESS STAYS OUT OF THIS FILE.

	An exploit audit found the first version fully deterministic: first free slot, every time, so every
	hide in every round was the same form at the same spawn point and survivors could simply camp it.
	§4.5's intended deduction "which cat" collapsed to "the one by the well, always".

	The fix is a random pick — but the randomness lives in `AmbientService`, which is server-only,
	rather than here. THIS MODULE IS REPLICATED AND CALLABLE BY ANY CLIENT (`src/shared` is mapped
	wholesale into `ReplicatedStorage`), so a draw performed here would be a draw a client could
	replay. A preferred INDEX passed in is just a number; the entropy that chose it never crosses.

	`preferIndex` IS A HINT, NOT A COMMAND. It is honoured only when that slot exists, matches the
	form and is free; otherwise the scan falls through to the first free slot, which is what keeps
	this function total and keeps every existing assertion about exhaustion valid.
]]
function AmbientRoster.claim(
	roster: Roster,
	form: CamouflageForm,
	preferIndex: number?
): (Roster, number?)
	local updated: Roster = table.clone(roster)

	if preferIndex ~= nil then
		local preferred = updated[preferIndex]

		if preferred ~= nil and preferred.Form == form and not preferred.Claimed then
			updated[preferIndex] = { Form = preferred.Form, Claimed = true }

			return updated, preferIndex
		end
	end

	for index, slot in updated do
		if slot.Form == form and not slot.Claimed then
			updated[index] = { Form = slot.Form, Claimed = true }

			return updated, index
		end
	end

	return updated, nil
end

--[[
	EVERY FREE SLOT OF THIS FORM, so a caller with server-only entropy can choose one.

	RETURNS INDICES, NOT SLOTS. An index is the only thing `claim` and `release` accept, and handing
	back the table entries would invite a caller to mutate a roster it does not own.
]]
function AmbientRoster.freeSlots(roster: Roster, form: CamouflageForm): { number }
	local free: { number } = {}

	for index, slot in roster do
		if slot.Form == form and not slot.Claimed then
			table.insert(free, index)
		end
	end

	return free
end

--[[
	GIVE IT BACK. IDEMPOTENT, and that is a requirement rather than a nicety: Phase 4 releases from
	five different exits (an exit request, a transform, a salt hit, a death, the round ending) and at
	least two of them can fire for the same slot in the same frame — `ApplySaltHit` calls `endFeed`,
	which calls `revert`, which exits camouflage, on a path `onPhaseChanged` may also be walking.

	AN OUT-OF-RANGE INDEX IS ANSWERED, NOT ERRORED. A stale slot index outliving its roster is what a
	player rejoining into a new round looks like, and throwing inside a `PlayerRemoving` handler is how
	one cleanup failure becomes several.
]]
function AmbientRoster.release(roster: Roster, slotIndex: number?): Roster
	local updated: Roster = table.clone(roster)

	if slotIndex == nil then
		return updated
	end

	local slot = updated[slotIndex]

	if slot == nil then
		return updated
	end

	updated[slotIndex] = { Form = slot.Form, Claimed = false }

	return updated
end

return AmbientRoster
