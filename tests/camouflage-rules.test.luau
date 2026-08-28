--!strict
--[[
	May the Aswang hide, over the whole domain. (V07, §4.3)

	THE PRE-REVEAL HALF IS THE POINT OF THIS FILE. 2 x 2 x 5 x 5 x 2 is 200 cells and half of them
	share one expected answer — `NOT_REVEALED`, unconditionally, for every phase, every state, every
	charge and every slot. That half is not a sample and must never become one: the failure it exists
	to catch is a future input added ABOVE the reveal test, which would look like a tidy refactor and
	would silently hand the deduction layer away (see the module header, and `.claude/lessons/
	absence-is-observable.md`).

	THE ORACLE IS THE SPEC SENTENCE, NOT THE MODULE'S BRANCHES. `isOk` below is §4.3 written as one
	conjunction. Computing the expectation from the module's own `if` order would prove only that the
	module agrees with itself; PRECEDENCE — which refusal is reported when two apply — is a separate,
	much smaller claim and it gets its own explicit table at the bottom.

	SYNTHETIC NUMBERS, NOT CONFIG'S. These assertions are about the MODULE's rules; V16 retunes
	balance and must not be able to red this file. The live Config values are cross-checked at the
	bottom, as `monster-health` and `feed-rules` both do.
]]

local Config = require("../src/shared/Config")
local CamouflageRules = require("../src/shared/pure/CamouflageRules")

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local REVEALED = { false, true }
local CHARGED = { false, true }
local SLOTS = { false, true }
local STATES = { "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
local PHASES = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

--[[
	§4.3 AS ONE CONJUNCTION. "The Aswang can take the form of an ambient cat, dog, pig or villager
	NPC… camouflage is locked until the Aswang has been publicly revealed… spent on use and only a
	feed restores it", plus §6.4's rule that every round activity belongs to ACTIVE, plus the build
	plan's swap-not-spawn rule as the slot term.
]]
local function isOk(
	revealed: boolean,
	charged: boolean,
	state: string,
	phase: string,
	slot: boolean
): boolean
	return revealed and charged and slot and state == "TRANSFORMED" and phase == "ACTIVE"
end

for _, revealed in REVEALED do
	for _, charged in CHARGED do
		for _, state in STATES do
			for _, phase in PHASES do
				for _, slot in SLOTS do
					local verdict = CamouflageRules.evaluate({
						HasBeenRevealed = revealed,
						HasCharge = charged,
						MonsterState = state :: any,
						Phase = phase :: any,
						SlotAvailable = slot,
					})

					local label =
						`evaluate revealed={revealed} charge={charged} {state}/{phase} slot={slot}`

					check(
						label,
						(verdict == "OK") == isOk(revealed, charged, state, phase, slot),
						verdict
					)

					--[[
						THE ASSERTION THE BUILD PLAN NAMES, AND IT IS SEPARATE FROM THE ONE ABOVE.
						`(verdict == "OK") == isOk(...)` would already fail on a leaked grant — but it
						would ALSO pass if an unrevealed monster were refused for the wrong reason,
						which is the state a half-finished refactor leaves behind. Asserting the exact
						verdict pins the ORDER as well as the outcome.
					]]
					if not revealed then
						check(`pre-reveal denied: {label}`, verdict == "NOT_REVEALED", verdict)
					end
				end
			end
		end
	end
end

--[[
	THE TWO TRANSITION TABLES, over every event x every starting value. Eight events, two booleans,
	two functions: 32 cells, and every one of them has a stated answer in §4.3.
]]
local EVENTS = {
	"SALT_HIT",
	"FEED_COMPLETED",
	"FEED_INTERRUPTED",
	"CAMOUFLAGE_ENTERED",
	"CAMOUFLAGE_EXITED",
	"TRANSFORMED",
	"REVERTED",
	"KILLED",
}

for _, event in EVENTS do
	for _, before in { false, true } do
		local revealedAfter = CamouflageRules.revealedAfter(before, event :: any)
		local expectedRevealed = before or event == "SALT_HIT"

		check(
			`revealedAfter {before}/{event}`,
			revealedAfter == expectedRevealed,
			tostring(revealedAfter)
		)

		local chargeAfter = CamouflageRules.chargeAfter(before, event :: any)
		local expectedCharge = if event == "FEED_COMPLETED"
			then true
			elseif event == "CAMOUFLAGE_ENTERED" then false
			else before

		check(`chargeAfter {before}/{event}`, chargeAfter == expectedCharge, tostring(chargeAfter))
	end
end

--[[
	THE ONE-WAY PROPERTY, STATED AS ITSELF rather than left to fall out of the grid: no event in the
	game un-reveals a monster mid-round. The reset is a new round, and a new round is a new record.
]]
for _, event in EVENTS do
	check(`{event} never un-reveals`, CamouflageRules.revealedAfter(true, event :: any) == true)
end

--[[
	THE SMOKE GRID. Revealed x phase x three clock positions — never burst, exactly at the cooldown,
	and a hair inside it. The boundary is `>=`, so "exactly at the cooldown" must GRANT; a `>` there
	is the off-by-one that makes smoke feel unresponsive and that no playtester could name.
]]
local COOLDOWN = 10

local CLOCKS: { { Label: string, LastBurstAt: number?, Expected: string } } = {
	{ Label = "never burst", LastBurstAt = nil, Expected = "OK" },
	{ Label = "exactly at cooldown", LastBurstAt = 100 - COOLDOWN, Expected = "OK" },
	{ Label = "a hair inside", LastBurstAt = 100 - COOLDOWN + 0.01, Expected = "SMOKE_COOLING" },
}

for _, revealed in REVEALED do
	for _, phase in PHASES do
		for _, clock in CLOCKS do
			local verdict = CamouflageRules.evaluateSmoke({
				HasBeenRevealed = revealed,
				Phase = phase :: any,
				Now = 100,
				LastBurstAt = clock.LastBurstAt,
				Cooldown = COOLDOWN,
			})

			local expected = if not revealed
				then "SMOKE_NOT_REVEALED"
				elseif phase ~= "ACTIVE" then "SMOKE_WRONG_PHASE"
				else clock.Expected

			check(
				`evaluateSmoke revealed={revealed} {phase} {clock.Label}`,
				verdict == expected,
				verdict
			)
		end
	end
end

--[[
	THE SAME GATE, ASSERTED AS ITSELF. Smoke sits behind `HasBeenRevealed` too — a decision this
	chunk made rather than a spec reading (plan Follow Ups Q2), so it gets an assertion that names it
	instead of relying on the grid above to imply it.
]]
for _, phase in PHASES do
	check(`smoke pre-reveal denied in {phase}`, CamouflageRules.evaluateSmoke({
		HasBeenRevealed = false,
		Phase = phase :: any,
		Now = 100,
		LastBurstAt = nil,
		Cooldown = COOLDOWN,
	}) == "SMOKE_NOT_REVEALED")
end

--[[
	A CLOCK THAT WENT BACKWARDS REFUSES. `not (elapsed >= cooldown)` is written that way so a NaN
	elapsed fails closed; this asserts the polarity, because the naive `elapsed < cooldown` would let
	a NaN straight through and nothing in a round would show it.
]]
check("NaN elapsed refuses", CamouflageRules.evaluateSmoke({
	HasBeenRevealed = true,
	Phase = "ACTIVE",
	Now = 0 / 0,
	LastBurstAt = 0,
	Cooldown = COOLDOWN,
}) == "SMOKE_COOLING")

--[[
	`smokeBlocks` — THE FOUR CASES THAT MATTER. The clamp case is the one geometry bug that reads as
	balance: a cloud BEHIND the thrower must not block a throw away from it.
]]
local function v(x: number, y: number, z: number)
	return { X = x, Y = y, Z = z }
end

check(
	"through the centre blocks",
	CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(10, 0, 0), 5)
)
check(
	"tangent at the radius blocks",
	CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(10, 5, 0), 5)
)
check(
	"clear of the radius does not block",
	not CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(10, 6, 0), 5)
)
check(
	"behind the shooter does not block",
	not CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(-10, 0, 0), 5)
)
check(
	"past the far end does not block",
	not CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(30, 0, 0), 5)
)
check(
	"degenerate segment is a point test",
	CamouflageRules.smokeBlocks(v(0, 0, 0), v(0, 0, 0), v(1, 0, 0), 5)
)
check(
	"zero radius never blocks",
	not CamouflageRules.smokeBlocks(v(0, 0, 0), v(20, 0, 0), v(10, 0, 0), 0)
)

--[[
	AND THE CONFIG CROSS-CHECK. The grid above runs on synthetic values; this is the one place the
	live numbers are asserted to be usable at all.

	ALL THREE SMOKE NUMBERS, INCLUDING THE COOLDOWN. `SmokeCooldown` was omitted when this file was
	first written, on the reasoning that it did not exist until Step 2.1 and that its invariant would
	land with the others in Step 2.6. The first half was true and the second was not: Step 2.6 pins
	three relationships and none of them mentions this number, so the check the plan asked for here
	simply never landed anywhere. A plan audit caught it. Restored to where it was always meant to be.
]]
check(
	"SmokeRadius is a positive finite number",
	Config.Monster.SmokeRadius > 0 and Config.Monster.SmokeRadius < math.huge
)
check(
	"SmokeDuration is a positive finite number",
	Config.Monster.SmokeDuration > 0 and Config.Monster.SmokeDuration < math.huge
)
check(
	"SmokeCooldown is a positive finite number",
	Config.Monster.SmokeCooldown > 0 and Config.Monster.SmokeCooldown < math.huge
)

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} CamouflageRules check(s) failed`, 0)
end
