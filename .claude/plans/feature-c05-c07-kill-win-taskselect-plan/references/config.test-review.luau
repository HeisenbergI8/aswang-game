--!strict
-- Review of tests/config.test.luau — the invariant style Phase 2 extends.
-- Excerpts only.

-- tests/config.test.luau:3-9
--[[
	These are not tests of Config's VALUES — every number in there is explicitly "a starting value to
	tune" (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and silent:
	nothing tells you when two numbers that must agree have stopped agreeing, and the symptom shows up
	as a design failure rather than a bug.
]]
-- IMPORTANT: this is why all four of Phase 2's new checks are relationships and none is an equality
-- against a literal. `AswangWinSurvivorThreshold == 2` would fail the moment M12 tunes it and would
-- teach nothing; `threshold < MaxPlayers - AswangCount` stays true across every value that is sane.

-- tests/config.test.luau:11
local Config = require("../src/shared/Config")
-- NOTE: the ONLY require. That is what makes the Lune-has-no-Roblox-datatypes trap bite here rather
-- than at analyze time — see Config.luau:66-69 on the RGB triples.

-- tests/config.test.luau:15-23
local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end
-- NOTE: the house shape, copied by every test in this directory. All four new tests in this plan use
-- it verbatim: no assertion library, no format to keep in sync, and a non-zero exit is the whole
-- protocol (tests/README.md).

-- tests/config.test.luau:69-75 — the invariant C05 depends on and does NOT need to add.
-- Spec §4.6: salt is thrown from outside kill range, or it is not counterplay — it is a suicide button.
check(
	"salt reaches further than the Aswang kills",
	Config.Salt.ThrowRange > Config.Monster.KillRange,
	`ThrowRange={Config.Salt.ThrowRange}, KillRange={Config.Monster.KillRange}`
)
-- IMPORTANT: already present as invariant #7. The task brief asks whether "salt range must exceed kill
-- range" needs adding — it does not. `KillCooldown > TransformTime + RevertTime` is likewise already
-- there (:53-59). C05 reads KillRange and KillCooldown; it introduces neither.

-- tests/config.test.luau, the tail
if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end

print("  PASS  config: 21 balance invariants")
-- IMPORTANT: this count is PROSE. Nothing asserts it, which is exactly why it gets missed — the
-- C02–C04 implementation log records having to bump it 13 -> 19 by hand. Phase 2 bumps it 21 -> 25.

-- tests/config.test.luau — the ForceAswangWhenSolo pin (near the tail)
check(
	"the solo forced-Aswang override is off",
	Config.Debug.ForceAswangWhenSolo == false,
	"this rigs the draw and must never ship"
)
-- IMPORTANT for the playtest: the coordinator must set this true before launching the playtester and
-- revert it afterwards. It is pinned in TWO places — here and check-debug.mjs — and the note above this
-- block records that only check-debug.mjs actually blocks a commit, because guard-commit.mjs runs
-- verify:fast, which does not include test:unit. So a debug value left on WILL be caught at commit
-- time, but not by this file.
