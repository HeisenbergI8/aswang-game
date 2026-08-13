--!strict
--[[
	Server-timed hold accumulation. C08's boundary, its freeze, and its one secrecy property.

	THE LAST ASSERTION IS THE REASON THIS FILE EXISTS. "Four people do not finish a task faster than
	one" reads like a balance choice and is a secrecy one: a summed rate makes the bar's speed a
	function of how many people are contributing, so ANY per-player difference in weight becomes
	arithmetic a bystander can read off a bar.

	Under Amendment A2 the Aswang is no longer one of those differences — it contributes in full, and
	`tests/task-weight.test.luau` holds that as an enumerated grid. C15's ghosts are the live case now
	(§4.7's 0.25). Pinned here, in a terminal, because the day somebody "fixes" the max into a sum it
	will look like an improvement and no other check in this repo will object.
]]

local Config = require("../src/shared/Config")
local TaskProgress = require("../src/server/pure/TaskProgress")

local HOLD = Config.Tasks.HoldTime
local TICK = 0.25

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- Run a hold at a fixed tick rate and answer: how many seconds until it completed?
local function secondsToComplete(weights: { number }): number?
	local progress = 0
	local elapsedTotal = 0
	local weight = TaskProgress.strongestWeight(weights)

	for _ = 1, math.ceil((HOLD * 4) / TICK) do
		local result = TaskProgress.tick(progress, TICK, weight, HOLD)

		progress = result.Progress
		elapsedTotal += TICK

		if result.Completed then
			return elapsedTotal
		end
	end

	return nil
end

-- strongestWeight, including the empty case that is the normal state of four of the five task points.
check("nobody present is weight zero", TaskProgress.strongestWeight({}) == 0)
check("one contributor is their own weight", TaskProgress.strongestWeight({ 0.25 }) == 0.25)
check("the strongest wins, not the sum", TaskProgress.strongestWeight({ 0.25, 1, 0.25 }) == 1)
check("order does not matter", TaskProgress.strongestWeight({ 1, 0.25 }) == 1)

-- The boundary. A single full-weight contributor finishes in HoldTime, not HoldTime plus a tick.
local alone = secondsToComplete({ 1 })

check("one survivor completes a hold", alone ~= nil)
check(
	"and does it in HoldTime",
	alone ~= nil and alone <= HOLD + TICK,
	`{alone}s vs HoldTime={HOLD}s`
)
check("not sooner", alone ~= nil and alone >= HOLD, `{alone}s vs HoldTime={HOLD}s`)

--[[
	THE NON-SCALING PROPERTY, PINNED. Four contributors take the same time as one. If this ever fails,
	the rate has become a sum, and every weight difference on the path — C15's ghosts at 0.25 today,
	anything a later chunk adds — becomes visible to any bystander watching a bar.
]]
local crowd = secondsToComplete({ 1, 1, 1, 1 })

check(
	"four contributors finish no faster than one",
	crowd == alone,
	`crowd={crowd}s, alone={alone}s`
)

-- A ghost alone (C15's 25%) is slow but not stuck, and a ghost alongside a survivor is neither faster
-- nor slower than the survivor alone. §4.7 asks for "they still matter", not "they stack".
local ghostAlone = secondsToComplete({ Config.Ghost.TaskContributionMult })

check("a quarter-weight contributor still finishes", ghostAlone ~= nil)
check(
	"and takes about four times as long",
	ghostAlone ~= nil and alone ~= nil and ghostAlone > alone * 3,
	`ghost={ghostAlone}s, alive={alone}s`
)
check(
	"a quarter-weight helper neither speeds up nor slows down a full one",
	secondsToComplete({ 1, Config.Ghost.TaskContributionMult }) == alone
)

-- FREEZE, NOT DECAY. §4.4 assigns progress to the world; a survivor who dies at 90% must leave 90%
-- behind, or a dead player's task becomes the unwinnable case that rule exists to delete.
local abandoned = TaskProgress.tick(0.9, 30, 0, HOLD)

check("walking away stops accumulation", abandoned.Progress == 0.9, `{abandoned.Progress}`)
check("and does not complete it", not abandoned.Completed)

-- The four guards.
local completed = TaskProgress.tick(1, TICK, 1, HOLD)

check("a completed task stays completed", completed.Completed and completed.Progress == 1)

local clamped = TaskProgress.tick(0.99, HOLD * 10, 1, HOLD)

check("progress never exceeds 1", clamped.Progress == 1, `{clamped.Progress}`)
check("and reports completion", clamped.Completed)

local backwards = TaskProgress.tick(0.5, -5, 1, HOLD)

check("a clock that ran backwards moves nothing", backwards.Progress == 0.5, `{backwards.Progress}`)

local zeroHold = TaskProgress.tick(0, TICK, 1, 0)

check("a zero HoldTime completes rather than dividing by zero", zeroHold.Completed)
check("and produces a real number", zeroHold.Progress == zeroHold.Progress, `{zeroHold.Progress}`)

local negative = TaskProgress.tick(-1, TICK, 1, HOLD)

check("a negative progress is clamped up, not accumulated from", negative.Progress > 0)

if failures > 0 then
	error(`{failures} task-progress assertion(s) failed`, 0)
end

print("  PASS  task-progress: 20 assertions, incl. the non-scaling property")
