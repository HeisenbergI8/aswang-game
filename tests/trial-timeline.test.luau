--!strict
--[[
	The Solo Trial's scripted timeline, driven second by second.

	Two things are being proven and only one of them is obvious. The obvious one is that six beats fire
	at the right seconds. The other is that none of them can be LOST — a server hitch that jumps
	`elapsed` past two beats at once must owe both, because a player who silently never receives
	BEAT_SALT_GIVEN reaches the chase with no pouch and the tutorial teaches the opposite of §10.

	That failure has no symptom at runtime: the trial simply plays out slightly wrong, once, for one
	player, on a server nobody is watching. It is exactly the kind of thing that only a terminal test
	ever catches.
]]

local TrialTimeline = require("../src/shared/pure/TrialTimeline")

type TrialBeat = TrialTimeline.TrialBeat
type Schedule = TrialTimeline.Schedule

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

-- The shipped schedule, mirroring Config.Trial. Its ORDERING is pinned separately in
-- tests/config.test.luau; here it is the fixture the walk below is driven against.
local SHIPPED: Schedule = {
	SaltGivenAt = 40,
	ScriptedChaseAt = 55,
	SaltTaughtAt = 58,
	HandoffAt = 84,
	Duration = 90,
}

-- The order `dueBeats` must preserve. Not alphabetical and not chronological by accident — this is
-- the teaching order: know what to do, do it, be given the tool, meet the monster, be told what the
-- tool is for, be sent to the real game.
local EXPECTED_ORDER: { TrialBeat } = {
	"BEAT_WELCOME",
	"BEAT_TASKS",
	"BEAT_SALT_GIVEN",
	"BEAT_TRANSFORM",
	"BEAT_SALT_TAUGHT",
	"BEAT_HANDOFF",
}

--------------------------------------------------------------------------------
-- The full walk: 0 to Duration in one-second steps, exactly as the service ticks
--------------------------------------------------------------------------------

local fired: { [string]: boolean } = {}
local order: { TrialBeat } = {}
local firedAt: { [string]: number } = {}

for elapsed = 0, SHIPPED.Duration do
	for _, beat in TrialTimeline.dueBeats(elapsed, SHIPPED, fired) do
		check(`{beat} fires only once (at {elapsed})`, fired[beat] ~= true)

		fired[beat] = true
		firedAt[beat] = elapsed
		table.insert(order, beat)
	end
end

check(`all six beats fired over a full trial`, #order == 6, `got {#order}`)

for index, beat in EXPECTED_ORDER do
	check(`beat {index} is {beat}`, order[index] == beat, `got {tostring(order[index])}`)
end

-- Each beat landed on its scheduled second, not one tick late.
check(`BEAT_WELCOME at 0`, firedAt["BEAT_WELCOME"] == 0)
check(`BEAT_TASKS at 0`, firedAt["BEAT_TASKS"] == 0)
check(`BEAT_SALT_GIVEN at SaltGivenAt`, firedAt["BEAT_SALT_GIVEN"] == SHIPPED.SaltGivenAt)
check(`BEAT_TRANSFORM at ScriptedChaseAt`, firedAt["BEAT_TRANSFORM"] == SHIPPED.ScriptedChaseAt)
check(`BEAT_SALT_TAUGHT at SaltTaughtAt`, firedAt["BEAT_SALT_TAUGHT"] == SHIPPED.SaltTaughtAt)
check(`BEAT_HANDOFF at HandoffAt`, firedAt["BEAT_HANDOFF"] == SHIPPED.HandoffAt)

--------------------------------------------------------------------------------
-- THE HITCH. A single tick jumping 39 -> 60 must owe three beats, not one.
--------------------------------------------------------------------------------

local hitchFired: { [string]: boolean } = {}

for _, beat in TrialTimeline.dueBeats(39, SHIPPED, hitchFired) do
	hitchFired[beat] = true
end

check(`before the hitch, only the two zero-beats have fired`, hitchFired["BEAT_SALT_GIVEN"] ~= true)

local afterHitch = TrialTimeline.dueBeats(60, SHIPPED, hitchFired)

check(`a 39->60 hitch owes three beats`, #afterHitch == 3, `got {#afterHitch}`)
check(`...including BEAT_SALT_GIVEN`, afterHitch[1] == "BEAT_SALT_GIVEN")
check(`...then BEAT_TRANSFORM`, afterHitch[2] == "BEAT_TRANSFORM")
check(`...then BEAT_SALT_TAUGHT`, afterHitch[3] == "BEAT_SALT_TAUGHT")

--------------------------------------------------------------------------------
-- Boundary equality at ScriptedChaseAt — the off-by-one that would put the transform
-- one tick after the chase visual had already begun.
--------------------------------------------------------------------------------

local atChase: { [string]: boolean } = {
	BEAT_WELCOME = true,
	BEAT_TASKS = true,
	BEAT_SALT_GIVEN = true,
}

local dueAtChase = TrialTimeline.dueBeats(SHIPPED.ScriptedChaseAt, SHIPPED, atChase)

check(`BEAT_TRANSFORM is due at exactly ScriptedChaseAt`, dueAtChase[1] == "BEAT_TRANSFORM")

check(
	`phaseAt is TRIAL_CHASE at exactly ScriptedChaseAt`,
	TrialTimeline.phaseAt(SHIPPED.ScriptedChaseAt, SHIPPED, false) == "TRIAL_CHASE"
)

check(
	`one second earlier is still TRIAL_TASKS`,
	TrialTimeline.phaseAt(SHIPPED.ScriptedChaseAt - 1, SHIPPED, false) == "TRIAL_TASKS"
)

--------------------------------------------------------------------------------
-- phaseAt across the whole session
--------------------------------------------------------------------------------

check(`opens in TRIAL_TASKS`, TrialTimeline.phaseAt(0, SHIPPED, false) == "TRIAL_TASKS")

-- Finishing both tasks early skips the wait. A timer the player has already beaten is the static
-- screen §9 item 3 calls broken rather than waiting.
check(
	`tasks done at 0 goes straight to TRIAL_HANDOFF`,
	TrialTimeline.phaseAt(0, SHIPPED, true) == "TRIAL_HANDOFF"
)

check(
	`TRIAL_HANDOFF at HandoffAt`,
	TrialTimeline.phaseAt(SHIPPED.HandoffAt, SHIPPED, false) == "TRIAL_HANDOFF"
)

-- Duration ends it regardless of what the player achieved.
for _, done in { true, false } do
	check(
		`Duration is TRIAL_OFF (tasksDone={done})`,
		TrialTimeline.phaseAt(SHIPPED.Duration, SHIPPED, done) == "TRIAL_OFF"
	)

	check(
		`past Duration is TRIAL_OFF (tasksDone={done})`,
		TrialTimeline.phaseAt(SHIPPED.Duration + 30, SHIPPED, done) == "TRIAL_OFF"
	)
end

--[[
	The chase outranks an early finish, and this is a real ordering decision rather than a detail.
	A player who completed both tasks at second 20 is in TRIAL_HANDOFF — but once the clock reaches
	ScriptedChaseAt the monster appears anyway, because the chase is the half of the tutorial that
	teaches the tell, and C22's whole point is that they learn it by being chased.
]]
check(
	`the chase overrides an early finish`,
	TrialTimeline.phaseAt(SHIPPED.ScriptedChaseAt, SHIPPED, true) == "TRIAL_CHASE"
)

--------------------------------------------------------------------------------
-- A degenerate schedule: every beat at zero
--------------------------------------------------------------------------------

local ALL_ZERO: Schedule = {
	SaltGivenAt = 0,
	ScriptedChaseAt = 0,
	SaltTaughtAt = 0,
	HandoffAt = 0,
	Duration = 0,
}

local zeroFired: { [string]: boolean } = {}
local zeroDue = TrialTimeline.dueBeats(0, ALL_ZERO, zeroFired)

check(`a degenerate schedule owes all six at once`, #zeroDue == 6, `got {#zeroDue}`)

for _, beat in zeroDue do
	zeroFired[beat] = true
end

check(`...and owes none on the second call`, #TrialTimeline.dueBeats(0, ALL_ZERO, zeroFired) == 0)

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

local pureFired: { [string]: boolean } = { BEAT_WELCOME = true }
local firstCall = TrialTimeline.dueBeats(50, SHIPPED, pureFired)
local secondCall = TrialTimeline.dueBeats(50, SHIPPED, pureFired)

check(`dueBeats is deterministic`, #firstCall == #secondCall)
check(`dueBeats does not mutate the fired set`, pureFired["BEAT_TASKS"] == nil)
check(`dueBeats does not mutate the schedule`, SHIPPED.ScriptedChaseAt == 55)

if failures > 0 then
	error(`{failures} trial-timeline failure(s)`, 0)
end

print(`  PASS  trial-timeline: {checked} assertions over a full {SHIPPED.Duration}s walk`)
