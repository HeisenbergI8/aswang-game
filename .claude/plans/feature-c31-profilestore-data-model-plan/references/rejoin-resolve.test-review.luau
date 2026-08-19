--!strict
--[[
	REVIEW — tests/rejoin-resolve.test.luau:15-31, 128-141 (tail)
	Read for: the suite conventions tests/profile-migration.test.luau must follow. Every one of these
	is enforced by something — the runner, check:testcount, or Lune itself.
]]

local RejoinResolve = require("../src/shared/pure/RejoinResolve")
-- IMPORTANT: RELATIVE FILE PATH, not a Roblox instance path. Lune resolves by path and knows nothing
-- about Rojo — which is also why a pure module may live under src/server/pure/ just as happily as
-- src/shared/pure/. C31's module is fixed at src/shared/pure/ by BUILD-PLAN.md:947, not by Lune.

type PlayerState = RejoinResolve.PlayerState
-- NOTE: types are consumed FROM the module. This is why ProfileMigration exports Profile, Outcome and
-- Result rather than keeping them local — the test needs them to annotate its fixtures.

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1
	-- ... increments failures and prints on false
end
-- IMPORTANT: `checked` is incremented by `check` itself, not by the caller. That is what makes the
-- PASS line below a measurement.

--------------------------------------------------------------------------------
-- the tail — the two conventions with teeth
--------------------------------------------------------------------------------

if failures > 0 then
	error(`{failures} rejoin-resolve assertion(s) failed`, 0)
end
-- IMPORTANT: `error(..., 0)` is the whole protocol. run-luau-tests.mjs reads the EXIT CODE and nothing
-- else — no output format to parse, no reporter to keep in sync. A suite that prints FAIL and exits 0
-- is a suite that reports green.

print(`  PASS  rejoin-resolve: {checked} assertions over the full phase x dealt-in x stored grid`)
-- IMPORTANT: the count is INTERPOLATED. check:testcount fails any digit in a PASS literal that sits
-- outside `{...}`, because a typed number reports the same total whatever the suite contains — it
-- caught `34 balance invariants` surviving seven added checks. C31's PASS line must use {checked}.
-- NOTE: the description after the count names the INPUT SPACE covered, not the feature. C31's says
-- "fresh, v0, current, corrupt and future", which is the grid the migration actually has to survive.
