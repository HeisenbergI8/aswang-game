--!strict
--[[
	tests/transform-rules.test.luau

	Every precondition §4.3 puts on the transform, including the two that are easy to get subtly wrong
	and impossible to notice in a playtest: the cooldown BOUNDARY, and the fact that the cooldown is
	measured from the REVERT rather than from the transform.

	The other thing pinned here is the ORDER of the checks. It is contract, not implementation: when
	more than one precondition fails, the verdict decides which reason a C41 log line carries, and
	"a spectator who is also on cooldown" should read as NOT_ALIVE.
]]

local Config = require("../src/shared/Config")
local TransformRules = require("../src/shared/pure/TransformRules")

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

-- A request that is allowed, so each case below can change exactly one thing and attribute the result
-- to that change. A test whose baseline is already failing proves nothing about the field it varies.
local function allowed(): TransformRules.Request
	return {
		IsAswang = true,
		Phase = "ACTIVE",
		PlayerState = "ALIVE",
		Transformed = false,
		Now = 1000,
		LastRevertedAt = nil,
		Cooldown = Config.Monster.KillCooldown,
	}
end

local function verdictWith(mutate: (TransformRules.Request) -> ()): TransformRules.Verdict
	local request = allowed()

	mutate(request)

	return TransformRules.evaluate(request)
end

--------------------------------------------------------------------------------
-- The happy path, and all five refusals
--------------------------------------------------------------------------------

check("a live Aswang in ACTIVE may transform", TransformRules.evaluate(allowed()) == "OK")

check("a survivor may not transform", verdictWith(function(r)
	r.IsAswang = false
end) == "NOT_ASWANG")

check("already transformed is refused", verdictWith(function(r)
	r.Transformed = true
end) == "ALREADY_TRANSFORMED")

--------------------------------------------------------------------------------
-- Phase: exactly one of the five allows it
--------------------------------------------------------------------------------

for _, phase: TransformRules.RoundPhase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } do
	check(`the transform is refused during {phase}`, verdictWith(function(r)
		r.Phase = phase
	end) == "WRONG_PHASE", phase)
end

--------------------------------------------------------------------------------
-- PlayerState: the allowlist, proven over all four values
--
-- This is C04's carried-over warning from C01. `~= "SPECTATOR"` would pass every other assertion in
-- this file and would admit LOBBY and DEAD — and C15 makes DEAD real, at which point a dead player
-- transforms. A denylist fails open on exactly the states that do not exist yet.
--------------------------------------------------------------------------------

for _, state: TransformRules.PlayerState in { "LOBBY", "DEAD", "SPECTATOR" } do
	check(`a {state} player may not transform`, verdictWith(function(r)
		r.PlayerState = state
	end) == "NOT_ALIVE", state)
end

check("ALIVE is the only state that may act", verdictWith(function(r)
	r.PlayerState = "ALIVE"
end) == "OK")

--------------------------------------------------------------------------------
-- The cooldown, and its boundary
--------------------------------------------------------------------------------

do
	local cooldown = Config.Monster.KillCooldown

	check("a first transform is never on cooldown", verdictWith(function(r)
		r.LastRevertedAt = nil
	end) == "OK")

	check("one second into the cooldown is refused", verdictWith(function(r)
		r.Now = 1000
		r.LastRevertedAt = 999
	end) == "ON_COOLDOWN")

	-- The boundary itself. `<` rather than `<=` means the cooldown is INCLUSIVE of its final instant:
	-- at exactly Cooldown seconds the transform is allowed. Off by one comparison operator and the
	-- Aswang waits an extra frame forever, which nobody would ever notice or be able to report.
	check("at exactly the cooldown, the transform is allowed", verdictWith(function(r)
		r.Now = 1000
		r.LastRevertedAt = 1000 - cooldown
	end) == "OK", `cooldown={cooldown}`)

	check("a hair inside the cooldown is still refused", verdictWith(function(r)
		r.Now = 1000
		r.LastRevertedAt = 1000 - cooldown + 0.01
	end) == "ON_COOLDOWN")

	--[[
		MEASURED FROM REVERT, NOT FROM THE TRANSFORM (§4.3 step 5).

		Simulated: an Aswang transforms, holds the form for its full MaxTransformTime, then reverts.
		If the cooldown ran from the TRANSFORM, it would already be MaxTransformTime + RevertTime
		served the moment it reverted — most of the punishment for a failed hunt paid while still
		being a monster, and the "every kill is a gamble" pillar collapses.

		Here the clock starts at the revert, so immediately afterwards it is still refused.
	]]
	local transformedAt = 1000
	local revertedAt = transformedAt + Config.Monster.MaxTransformTime + Config.Monster.RevertTime

	check(
		"the cooldown starts at the revert, so a full-duration transform earns no credit",
		verdictWith(function(r)
			r.Now = revertedAt + 0.1
			r.LastRevertedAt = revertedAt
		end) == "ON_COOLDOWN",
		`held for {Config.Monster.MaxTransformTime}s, cooldown={cooldown}s`
	)
end

--------------------------------------------------------------------------------
-- Precedence, when more than one precondition fails
--------------------------------------------------------------------------------

check(
	"phase outranks everything — a survivor in the lobby reads as WRONG_PHASE",
	verdictWith(function(r)
		r.Phase = "INTERMISSION"
		r.IsAswang = false
		r.PlayerState = "DEAD"
	end) == "WRONG_PHASE"
)

check("liveness outranks role — a spectator survivor reads as NOT_ALIVE", verdictWith(function(r)
	r.PlayerState = "SPECTATOR"
	r.IsAswang = false
end) == "NOT_ALIVE")

check(
	"a spectator on cooldown reads as NOT_ALIVE, the fact worth acting on",
	verdictWith(function(r)
		r.PlayerState = "SPECTATOR"
		r.Now = 1000
		r.LastRevertedAt = 999
	end) == "NOT_ALIVE"
)

if failures > 0 then
	error(`{failures} transform-rule failure(s)`, 0)
end

print(
	`  PASS  transform-rules: {checked} assertions over verdicts, phases, states, cooldown and precedence`
)
