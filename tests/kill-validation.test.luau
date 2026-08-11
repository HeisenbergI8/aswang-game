--!strict
--[[
	The kill's preconditions, proven from a terminal.

	This is C05's stated Verify line — "at range, past range, on cooldown, wrong phase" — plus the two
	things that line does not ask for and that this game cannot afford to get wrong: the 4×4 grid of
	player states, and the exact boundary of each numeric comparison.

	BOUNDARIES ARE TESTED FROM BOTH SIDES, always. `<` and `<=` are one character apart and the
	difference is invisible in play — a kill at exactly 8.0 studs that silently fails once in fifty is
	indistinguishable from lag, and nobody files it.
]]

local KillValidation = require("../src/shared/pure/KillValidation")

type PlayerState = KillValidation.PlayerState
type Verdict = KillValidation.Verdict

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- A request that passes everything. Every case below is this table with ONE field changed, so a
-- failure names the field that caused it and nothing else.
local function valid(): KillValidation.Request
	return {
		Phase = "ACTIVE",
		KillerUserId = 1,
		TargetUserId = 2,
		KillerIsAswang = true,
		TargetIsAswang = false,
		KillerState = "ALIVE",
		TargetState = "ALIVE",
		Transformed = true,
		KillerPos = { X = 0, Y = 0, Z = 0 },
		TargetPos = { X = 0, Y = 0, Z = 0 },
		Range = 8,
		Now = 100,
		LastRevertedAt = nil,
		Cooldown = 30,
	}
end

local function verdictWith(mutate: (KillValidation.Request) -> ()): Verdict
	local request = valid()

	mutate(request)

	return KillValidation.evaluate(request)
end

check("the happy path is OK", KillValidation.evaluate(valid()) == "OK")

--------------------------------------------------------------------------------
-- Phase (§4.3: "round ACTIVE")
--------------------------------------------------------------------------------

for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } do
	check(`no kill during {phase}`, verdictWith(function(request)
		request.Phase = phase :: any
	end) == "WRONG_PHASE")
end

--------------------------------------------------------------------------------
-- Range — the boundary from both sides, on each axis and on a diagonal
--------------------------------------------------------------------------------

check("a target at exactly the range is within it", verdictWith(function(request)
	request.TargetPos = { X = 8, Y = 0, Z = 0 }
end) == "OK")

check("one stud past the range is refused", verdictWith(function(request)
	request.TargetPos = { X = 9, Y = 0, Z = 0 }
end) == "OUT_OF_RANGE")

-- C05's Done line names 40 studs through a wall. The wall is the raycast's job; the 40 is this one's.
check("the 40-stud exploit case is refused", verdictWith(function(request)
	request.TargetPos = { X = 40, Y = 0, Z = 0 }
end) == "OUT_OF_RANGE")

-- HEIGHT COUNTS. A flat XZ distance would let the Aswang kill through a floor from the storey above,
-- with a clean raycast straight down and every other condition satisfied.
check("a target directly overhead, out of range, is refused", verdictWith(function(request)
	request.TargetPos = { X = 0, Y = 20, Z = 0 }
end) == "OUT_OF_RANGE")

-- 3-4-5: exactly 5 studs away using all three axes, which a per-axis comparison would get wrong.
check("a diagonal inside the range is allowed", verdictWith(function(request)
	request.TargetPos = { X = 3, Y = 4, Z = 0 }
end) == "OK")

--------------------------------------------------------------------------------
-- Cooldown (§4.3 step 5) — from the REVERT
--------------------------------------------------------------------------------

check("a first kill of the round is never on cooldown", verdictWith(function(request)
	request.LastRevertedAt = nil
end) == "OK")

check("one second before the cooldown elapses is refused", verdictWith(function(request)
	request.LastRevertedAt = request.Now - 29
end) == "ON_COOLDOWN")

check("exactly at the cooldown is allowed", verdictWith(function(request)
	request.LastRevertedAt = request.Now - 30
end) == "OK")

--------------------------------------------------------------------------------
-- DEGENERATE TUNABLES FAIL CLOSED.
--
-- Range and Cooldown arrive from Config, so no client supplies them and none of this is an exploit.
-- It is an M12 trap: `range * range` maps -8 onto the same 64 as 8, so a typo'd minus sign used to
-- keep working silently, and a NaN cooldown made `elapsed < NaN` false so the gate never tripped.
-- A knob that cannot be honoured must refuse the kill, never grant it.
--------------------------------------------------------------------------------

check(
	"a negative range refuses rather than behaving like its positive twin",
	verdictWith(function(request)
		request.Range = -8
		request.TargetPos = { X = 3, Y = 0, Z = 0 }
	end) == "OUT_OF_RANGE"
)

check("a zero range refuses", verdictWith(function(request)
	request.Range = 0
end) == "OUT_OF_RANGE")

check("an infinite range refuses rather than reaching the whole map", verdictWith(function(request)
	request.Range = math.huge
	request.TargetPos = { X = 5000, Y = 0, Z = 0 }
end) == "OUT_OF_RANGE")

check("a NaN range refuses", verdictWith(function(request)
	request.Range = 0 / 0
end) == "OUT_OF_RANGE")

check(
	"a NaN cooldown is treated as still on cooldown, not as elapsed",
	verdictWith(function(request)
		request.Cooldown = 0 / 0
		request.LastRevertedAt = request.Now - 1000
	end) == "ON_COOLDOWN"
)

-- The other three clock inputs, which the first version of the guard left failing OPEN.
check("a NaN LastRevertedAt refuses rather than reading as elapsed", verdictWith(function(request)
	request.LastRevertedAt = 0 / 0
end) == "ON_COOLDOWN")

check("a NaN Now refuses", verdictWith(function(request)
	request.Now = 0 / 0
	request.LastRevertedAt = 0
end) == "ON_COOLDOWN")

-- inf - inf is NaN, so this reached the comparison and passed before the fix.
check(
	"an infinite Now and LastRevertedAt refuse rather than cancelling to NaN",
	verdictWith(function(request)
		request.Now = math.huge
		request.LastRevertedAt = math.huge
	end) == "ON_COOLDOWN"
)

-- The residuals the NaN-only guard still let through: an elapsed time that is INFINITE rather than
-- NaN, and a negative cooldown. `inf < 30` is false and `1 < -1` is false, so both read as elapsed.
check("an infinite elapsed time refuses", verdictWith(function(request)
	request.Now = math.huge
	request.LastRevertedAt = 99
end) == "ON_COOLDOWN")

check("a negatively infinite LastRevertedAt refuses", verdictWith(function(request)
	request.Now = 100
	request.LastRevertedAt = -math.huge
end) == "ON_COOLDOWN")

-- One minus sign in Config during M12 would otherwise disable the kill cooldown outright.
check("a negative cooldown refuses rather than disabling the gate", verdictWith(function(request)
	request.Cooldown = -1
	request.LastRevertedAt = request.Now - 0.5
end) == "ON_COOLDOWN")

check("an infinite cooldown refuses", verdictWith(function(request)
	request.Cooldown = math.huge
	request.LastRevertedAt = request.Now - 1000
end) == "ON_COOLDOWN")

--[[
	ZERO IS DEGENERATE, NOT "no cooldown". The guard read `>= 0` for a round while its own comment
	claimed positive-and-finite, so zero slipped through and disabled the gate entirely — the same
	failure direction it closes for -1, reached by the value most likely to be typed on purpose.
	§4.3 step 5 makes the post-revert cooldown the whole cost of a kill: a round without one is not a
	tuning choice, it is §2's risk/reward pillar switched off.
]]
check("a zero cooldown refuses rather than disabling the gate", verdictWith(function(request)
	request.Cooldown = 0
	request.LastRevertedAt = request.Now - 0.001
end) == "ON_COOLDOWN")

-- The clock running backwards must refuse, not read as a very large elapsed time.
check("a LastRevertedAt in the future refuses", verdictWith(function(request)
	request.LastRevertedAt = request.Now + 60
end) == "ON_COOLDOWN")

--------------------------------------------------------------------------------
-- Role and form
--------------------------------------------------------------------------------

check("a survivor cannot kill", verdictWith(function(request)
	request.KillerIsAswang = false
end) == "NOT_ASWANG")

-- §4.3 step 3. The seventh condition, and the one C05's bullet list does not name.
check("an untransformed Aswang cannot kill", verdictWith(function(request)
	request.Transformed = false
end) == "NOT_TRANSFORMED")

check("the Aswang cannot kill itself", verdictWith(function(request)
	request.TargetUserId = request.KillerUserId
end) == "SELF")

-- Unreachable at AswangCount = 1, and pinned anyway: §3's OUT list bans multiple Aswangs, so if that
-- knob ever moves the failure must be a refusal rather than monsters eating each other.
check("the Aswang cannot kill another Aswang", verdictWith(function(request)
	request.TargetIsAswang = true
end) == "TARGET_IS_ASWANG")

--------------------------------------------------------------------------------
-- THE 4×4 GRID. The C04 warning's actual subject: PlayerState has four values, exactly one may kill
-- and exactly one may be killed, and a denylist passes every case except the two nobody writes.
--------------------------------------------------------------------------------

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }

for _, killerState in STATES do
	for _, targetState in STATES do
		local verdict = verdictWith(function(request)
			request.KillerState = killerState
			request.TargetState = targetState
		end)

		local expected: Verdict = if killerState ~= "ALIVE"
			then "KILLER_NOT_ALIVE"
			elseif targetState ~= "ALIVE" then "TARGET_NOT_ALIVE"
			else "OK"

		check(
			`killer={killerState} target={targetState}`,
			verdict == expected,
			`expected {expected}, got {verdict}`
		)
	end
end

-- Stated as a property as well as a grid, so a future edit cannot satisfy the cells by accident while
-- breaking the rule they exist to express.
check("a mid-round joiner cannot be killed", verdictWith(function(request)
	request.TargetState = "SPECTATOR"
end) == "TARGET_NOT_ALIVE")

check("a ghost cannot be killed", verdictWith(function(request)
	request.TargetState = "GHOST"
end) == "TARGET_NOT_ALIVE")

--------------------------------------------------------------------------------
-- Check ORDER is part of the contract: it decides which reason the log carries.
--------------------------------------------------------------------------------

check("a wrong phase outranks everything else", verdictWith(function(request)
	request.Phase = "INTERMISSION"
	request.KillerIsAswang = false
	request.TargetPos = { X = 999, Y = 0, Z = 0 }
end) == "WRONG_PHASE")

check("the killer's own state outranks the target's", verdictWith(function(request)
	request.KillerState = "GHOST"
	request.TargetState = "SPECTATOR"
end) == "KILLER_NOT_ALIVE")

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end

print("  PASS  kill-validation: 16 grid cells + 35 cases")
