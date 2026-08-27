--!strict
--[[
	REVIEW — tests/noise-model.test.luau
	Excerpts only. Ranges as of 2026-08-27, branch v2-rewrite (UNTRACKED — V04 has not committed).
	This is the grid idiom `tests/monster-health.test.luau` copies, and V04's own header says so.
]]

-- tests/noise-model.test.luau:2-11
--[[
	The build plan asks for "the action x state grid", not a smoke test, and the reason is the same
	one `monster-health` will have at V05: this module is a small pure function over a BOUNDED
	domain, which is the one shape where enumerating beats writing a case per bug.
]]
-- NOTE: V04 named V05 in advance. The plan takes it literally.

-- tests/noise-model.test.luau:13-27
local Config = require("../src/shared/Config")
local NoiseModel = require("../src/shared/pure/NoiseModel")
local failures = 0
local checked = 0
local function check(label: string, ok: boolean, detail: string?)
-- NOTE: copy this preamble verbatim. Two requires, two counters, one `check`, and a
-- `print`-then-`error` tail. Every suite in `tests/` shares it.

-- tests/noise-model.test.luau:29-43
-- A SYNTHETIC tuning, not Config's. These assertions are about the MODEL's rules; V16 will retune
-- Config and must not be able to red this file. The real block is cross-checked at the bottom.
local TUNING = { ... }
-- IMPORTANT: the single most important structural decision in this file, and the one the health
-- suite must copy. A test written against `Config.Monster.MaxHealth` reds the tree the first time
-- V16 tunes health — which trains everyone to edit the test instead of thinking about the change.

-- tests/noise-model.test.luau:45-49
local ACTIONS = { "SEARCH", "ITEM_USE", "DOOR", "SPRINT" }
-- Zero, a walk, the baseline, a transformed Aswang's 20, either side of the threshold, and the four
-- values that break a naive comparison.
local SPEEDS = { 0, 4, 16, 20, 21.9, 22, 22.1, 400, -5, 0 / 0, math.huge, -math.huge }
-- NOTE: the domain declared as two lists at the top, then walked with a nested loop. The health
-- suite's equivalent is `HEALTHS = { 100, 60, 25, 10, 0, -40, 0/0, math.huge, -math.huge }` and
-- `EVENTS = { "SALT", "FEED", "NONE", "SHOUT", "" }` — the build plan's enumeration plus an unknown
-- id and an empty string, because both are reachable from a table lookup.

-- tests/noise-model.test.luau:53-70
for _, action in ACTIONS do
	for _, speed in SPEEDS do
		local result = NoiseModel.evaluate(action, { SpeedStuds = speed }, TUNING)
		if result ~= nil then
			check(`{action} at {speed}: loudness in 0..1`, ...)
-- NOTE: the grid asserts ONE invariant across every cell (the answer is well-formed), and the
-- specific properties get their own named checks below it. That split is what keeps the grid
-- readable. The health suite's grid invariant is "finite, and inside [WeakenedThreshold, MaxHealth]".

-- tests/noise-model.test.luau:88-119
check("sprint is silent below the threshold", ...)
check("sprint is silent for NaN", ...)
check("sprint emits at the threshold", ...)
-- IMPORTANT: the boundary asserted on BOTH sides and AT it, plus the degenerate values called out by
-- name with the reason attached. The health suite does the same for `WeakenedThreshold`: 25 is
-- weakened, 25.1 is not, and NaN is weakened rather than immortal.

-- tests/noise-model.test.luau:150-160
local absurd = { Actions = { SEARCH = { Loudness = 9, Radius = -3, MinInterval = 1 } }, ... }
-- Clamping, proven with a tuning nobody would write on purpose but M12 could typo.
-- NOTE: the precedent for the health suite's `perverse` and `inverted` tunings — a negative
-- SaltDamage and a WeakenedThreshold above MaxHealth.

-- tests/noise-model.test.luau:180-193
--[[
	THE CROSS-CHECK. Everything above runs on a synthetic tuning so V16 can retune freely — but a
	MISSING ROW in the real block would then go unnoticed until a live search made no noise, which is
	a silent failure with no symptom except that the game got easier.
]]
for _, action in ACTIONS do
	check(`Config.Noise prices {action}`, NoiseModel.evaluate(action, ..., Config.Noise) ~= nil)
end
print(`  {checked - failures}/{checked} checks passed`)
if failures > 0 then
	error(`{failures} NoiseModel check(s) failed`, 0)
end
-- IMPORTANT: the cross-check catches a RENAMED or MISSING Config field, which the synthetic tuning
-- structurally cannot. The health suite's version asserts that Config's salt actually removes health
-- and Config's feed actually restores it — the BALANCE relationship stays in `config.test.luau`.
