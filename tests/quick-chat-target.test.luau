--!strict
--[[
	tests/quick-chat-target.test.luau

	Who `"It's [nearest player]!"` names, over the full grid of eligibility.

	THIS IS THE 🔒 SURFACE OF C25 IN ONE FUNCTION. A client-supplied name would be a free
	impersonation exploit, so the server resolves the target — and every way that resolution can be
	wrong is a way one player puts another player's name in everyone's HUD without cause.

	Two properties carry the security argument and both are asserted below rather than described:

	  · LINE OF SIGHT IS REQUIRED. Without it the phrase is a through-wall proximity radar the sender
	    can poll, and the player who gains most from "who is near me" is the Aswang mid-hunt.
	  · THE ANSWER IS STABLE. Two candidates at identical distance must always produce the same name,
	    or the same situation accuses different people on different frames.
]]

local QuickChatTarget = require("../src/shared/pure/QuickChatTarget")

type Candidate = QuickChatTarget.Candidate

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

local RANGE = 40

-- A candidate that qualifies on every axis, so each case below can spoil exactly one thing.
local function candidate(over: {
	UserId: number?,
	DistanceStuds: number?,
	IsAliveSide: boolean?,
	HasLineOfSight: boolean?,
}): Candidate
	return {
		UserId = over.UserId or 100,
		DistanceStuds = over.DistanceStuds or 10,
		IsAliveSide = if over.IsAliveSide == nil then true else over.IsAliveSide,
		HasLineOfSight = if over.HasLineOfSight == nil then true else over.HasLineOfSight,
	}
end

--------------------------------------------------------------------------------
-- The full eligibility grid: alive-side x line-of-sight x in-range
--------------------------------------------------------------------------------

local BOOLS = { true, false }

for _, alive in BOOLS do
	for _, sight in BOOLS do
		for _, inRange in BOOLS do
			local one = candidate({
				UserId = 7,
				DistanceStuds = if inRange then RANGE - 1 else RANGE + 1,
				IsAliveSide = alive,
				HasLineOfSight = sight,
			})

			local eligible = alive and sight and inRange
			local got = QuickChatTarget.nearest({ one }, RANGE)

			check(
				`alive={alive} sight={sight} inRange={inRange} -> {if eligible then "7" else "nil"}`,
				got == (if eligible then 7 else nil),
				`got {tostring(got)}`
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Nearest wins, and only among the eligible
--------------------------------------------------------------------------------

check("the nearer of two eligible candidates wins", QuickChatTarget.nearest({
	candidate({ UserId = 1, DistanceStuds = 30 }),
	candidate({ UserId = 2, DistanceStuds = 5 }),
}, RANGE) == 2)

check("list order does not decide it", QuickChatTarget.nearest({
	candidate({ UserId = 2, DistanceStuds = 5 }),
	candidate({ UserId = 1, DistanceStuds = 30 }),
}, RANGE) == 2)

--[[
	THE ONE THAT MATTERS MOST. A closer candidate behind a wall must NOT beat a further one in the
	open — it must be skipped entirely, not merely lose. If proximity could override sight, the
	phrase would name people through walls and the oracle is back.
]]
check(
	"a nearer candidate with no line of sight loses to a further visible one",
	QuickChatTarget.nearest({
		candidate({ UserId = 1, DistanceStuds = 2, HasLineOfSight = false }),
		candidate({ UserId = 2, DistanceStuds = 35 }),
	}, RANGE) == 2
)

check("a nearer DEAD candidate loses to a further living one", QuickChatTarget.nearest({
	candidate({ UserId = 1, DistanceStuds = 2, IsAliveSide = false }),
	candidate({ UserId = 2, DistanceStuds = 35 }),
}, RANGE) == 2)

check("nobody eligible answers nil, however many candidates", QuickChatTarget.nearest({
	candidate({ UserId = 1, DistanceStuds = 2, HasLineOfSight = false }),
	candidate({ UserId = 2, DistanceStuds = 3, IsAliveSide = false }),
	candidate({ UserId = 3, DistanceStuds = RANGE + 100 }),
}, RANGE) == nil)

check("an empty candidate list answers nil", QuickChatTarget.nearest({}, RANGE) == nil)

--------------------------------------------------------------------------------
-- The range boundary, exactly
--------------------------------------------------------------------------------

check(
	"exactly at the range is in",
	QuickChatTarget.nearest({ candidate({ UserId = 5, DistanceStuds = RANGE }) }, RANGE) == 5
)

check(
	"a hair beyond the range is out",
	QuickChatTarget.nearest({ candidate({ UserId = 5, DistanceStuds = RANGE + 0.001 }) }, RANGE)
		== nil
)

check(
	"distance zero is in — standing inside somebody still names them",
	QuickChatTarget.nearest({ candidate({ UserId = 5, DistanceStuds = 0 }) }, RANGE) == 5
)

--------------------------------------------------------------------------------
-- STABILITY. A tie must always resolve the same way.
--------------------------------------------------------------------------------

local tieA = {
	candidate({ UserId = 9, DistanceStuds = 12 }),
	candidate({ UserId = 4, DistanceStuds = 12 }),
}

local tieB = {
	candidate({ UserId = 4, DistanceStuds = 12 }),
	candidate({ UserId = 9, DistanceStuds = 12 }),
}

check("a tie breaks to the lowest UserId", QuickChatTarget.nearest(tieA, RANGE) == 4)
check("...regardless of list order", QuickChatTarget.nearest(tieB, RANGE) == 4)
check(
	"...so the same situation always names the same player",
	QuickChatTarget.nearest(tieA, RANGE) == QuickChatTarget.nearest(tieB, RANGE)
)

--------------------------------------------------------------------------------
-- Degenerate numbers. None may name anybody by accident.
--------------------------------------------------------------------------------

local NAN = 0 / 0

check(
	"a NaN distance never wins",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = NAN }) }, RANGE) == nil
)

check("a NaN distance does not shadow a real candidate", QuickChatTarget.nearest({
	candidate({ UserId = 1, DistanceStuds = NAN }),
	candidate({ UserId = 2, DistanceStuds = 20 }),
}, RANGE) == 2)

check(
	"an infinite distance never wins",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = math.huge }) }, RANGE) == nil
)

check(
	"a negative distance still resolves rather than erroring",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = -5 }) }, RANGE) == 1
)

-- A zero or negative range admits nobody but the coincident, which is the safe direction.
check(
	"a zero range admits only distance zero",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = 0 }) }, 0) == 1
)

check(
	"a zero range excludes anyone at all distant",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = 0.5 }) }, 0) == nil
)

check(
	"a NaN range admits nobody",
	QuickChatTarget.nearest({ candidate({ UserId = 1, DistanceStuds = 5 }) }, NAN) == nil
)

--------------------------------------------------------------------------------
-- THE CALLER'S SEAM. This module cannot know who the sender is, so it cannot
-- exclude them — the service must. Asserted here so the contract is written down
-- somewhere that fails if the service ever stops honouring it.
--------------------------------------------------------------------------------

local SENDER = 42

check(
	"a list containing the sender WILL name the sender — the caller must exclude them",
	QuickChatTarget.nearest({ candidate({ UserId = SENDER, DistanceStuds = 0 }) }, RANGE) == SENDER
)

-- And the shape the service must actually produce: the sender filtered out beforehand.
local others = {}

for _, id in { SENDER, 1, 2 } do
	if id ~= SENDER then
		table.insert(others, candidate({ UserId = id, DistanceStuds = 10 }))
	end
end

check(
	"with the sender excluded, the nearest OTHER player is named",
	QuickChatTarget.nearest(others, RANGE) == 1
)

--------------------------------------------------------------------------------
-- Purity
--------------------------------------------------------------------------------

local probe = { candidate({ UserId = 3, DistanceStuds = 11 }) }
local first = QuickChatTarget.nearest(probe, RANGE)
local second = QuickChatTarget.nearest(probe, RANGE)

check("nearest is deterministic", first == second)
check("nearest does not mutate its input", #probe == 1 and probe[1].DistanceStuds == 11)

if failures > 0 then
	error(`{failures} quick-chat-target failure(s)`, 0)
end

print(`  PASS  quick-chat-target: {checked} assertions over the eligibility grid and the tie rule`)
