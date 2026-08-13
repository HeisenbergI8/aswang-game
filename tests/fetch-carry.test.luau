--!strict
--[[
	tests/fetch-carry.test.luau

	`server/pure/FetchCarry.luau` over its ENTIRE domain — 512 cells, enumerated.

	THE ASSERTION THAT MATTERS IS THE SECOND ONE. The first says each cell returns what the rule says
	it should. The second says the answer NEVER CHANGES WHEN A ROLE CHANGES, which is Amendment A2's
	requirement stated as a property rather than as prose, and is the one that fails if somebody
	teaches either this module or TaskWeight to care who is carrying.

	The weights come from `TaskWeight.forPlayer` rather than from literals, so the two modules are
	tested as the composition they are used as.
]]

local FetchCarry = require("../src/server/pure/FetchCarry")
local TaskWeight = require("../src/server/pure/TaskWeight")

local STATES: { TaskWeight.PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
local ROLES: { TaskWeight.Role } = { "SURVIVOR", "ASWANG" }
local BOOLS = { false, true }

local GHOST_MULT = 0.25
local FULL = 1

local failures = 0
local assertions = 0

local function check(label: string, ok: boolean, detail: string?)
	assertions += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function expected(
	hasCarrier: boolean,
	carrierWeight: number,
	atDestination: boolean,
	candidateWeight: number,
	atSource: boolean
): string
	if hasCarrier then
		if carrierWeight < FULL then
			return "DROP"
		end

		return if atDestination then "DELIVER" else "NONE"
	end

	return if atSource and candidateWeight >= FULL then "PICK_UP" else "NONE"
end

for _, hasCarrier in BOOLS do
	for _, carrierState in STATES do
		for _, carrierRole in ROLES do
			for _, atDestination in BOOLS do
				for _, candidateState in STATES do
					for _, candidateRole in ROLES do
						for _, atSource in BOOLS do
							local carrierWeight =
								TaskWeight.forPlayer(carrierState, carrierRole, GHOST_MULT)
							local candidateWeight =
								TaskWeight.forPlayer(candidateState, candidateRole, GHOST_MULT)

							local action = FetchCarry.decide({
								HasCarrier = hasCarrier,
								CarrierWeight = carrierWeight,
								CarrierAtDestination = atDestination,
								CandidateWeight = candidateWeight,
								CandidateAtSource = atSource,
								FullWeight = FULL,
							})

							check(
								`{carrierState}/{carrierRole} carrying={hasCarrier} dest={atDestination} `
									.. `+ {candidateState}/{candidateRole} src={atSource}`,
								action
									== expected(
										hasCarrier,
										carrierWeight,
										atDestination,
										candidateWeight,
										atSource
									),
								`got {action}`
							)
						end
					end
				end
			end
		end
	end
end

--[[
	AMENDMENT A2, AS A PROPERTY. For every cell, swapping either player's role changes nothing.

	This is the assertion a future "the Aswang cannot carry the item" change has to fight. Note what
	it would cost if it won: a fetch item that refuses to be picked up names the monster to anyone
	watching it not move, which is the same oracle A2 removed from the hold bar.
]]
for _, hasCarrier in BOOLS do
	for _, carrierState in STATES do
		for _, atDestination in BOOLS do
			for _, candidateState in STATES do
				for _, atSource in BOOLS do
					local seen: { [string]: boolean } = {}

					for _, carrierRole in ROLES do
						for _, candidateRole in ROLES do
							seen[FetchCarry.decide({
								HasCarrier = hasCarrier,
								CarrierWeight = TaskWeight.forPlayer(
									carrierState,
									carrierRole,
									GHOST_MULT
								),
								CarrierAtDestination = atDestination,
								CandidateWeight = TaskWeight.forPlayer(
									candidateState,
									candidateRole,
									GHOST_MULT
								),
								CandidateAtSource = atSource,
								FullWeight = FULL,
							})] =
								true
						end
					end

					local distinct = 0

					for _ in seen do
						distinct += 1
					end

					check(
						`role does not change the action ({carrierState}/{candidateState}, `
							.. `carrying={hasCarrier}, dest={atDestination}, src={atSource})`,
						distinct == 1,
						`{distinct} distinct actions across the four role pairings`
					)
				end
			end
		end
	end
end

-- §4.7 forward case, stated once explicitly so it is findable by name at C15 rather than only
-- implied by 512 cells: a ghost cannot pick the item up.
check("a ghost cannot carry a fetch item", FetchCarry.decide({
	HasCarrier = false,
	CarrierWeight = 0,
	CarrierAtDestination = false,
	CandidateWeight = TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
	CandidateAtSource = true,
	FullWeight = FULL,
}) == "NONE")

--[[
	DROP OUTRANKS DELIVER, stated once by name. The 512 cells contain it, but this is the sentence
	C09's brief actually asks for — "dropping on death is correct and creates good moments" — and the
	moment only exists if a carrier killed ON the destination drops rather than completing.
]]
check(
	"a carrier who stops being a full contributor ON the destination drops rather than delivering",
	FetchCarry.decide({
		HasCarrier = true,
		CarrierWeight = TaskWeight.forPlayer("GHOST", "SURVIVOR", GHOST_MULT),
		CarrierAtDestination = true,
		CandidateWeight = 0,
		CandidateAtSource = false,
		FullWeight = FULL,
	}) == "DROP"
)

if failures > 0 then
	error(`{failures} fetch-carry failure(s)`, 0)
end

print(`  PASS  fetch-carry: {assertions} assertions over the full 512-cell grid`) -- count-ok: 512 is the size of the input domain this suite enumerates, not a tally of work
