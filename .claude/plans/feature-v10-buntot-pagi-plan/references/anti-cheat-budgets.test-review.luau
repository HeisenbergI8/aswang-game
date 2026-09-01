--!strict
--[[
	REVIEW — tests/anti-cheat-budgets.test.luau
	Read for V10 planning to answer one operational question: when is the tree red, and why. This
	suite is the reason `npm run verify` cannot be green between Step 1.1 and Step 3.4.
]]

-- tests/anti-cheat-budgets.test.luau:10-16 — the two-directional assertion
--[[
	... assertion below fails on any budget naming a remote this list does not carry.
]]
local UP_REMOTES = {
	-- ... a HAND-MAINTAINED mirror of `Remotes.Up`
	"RequestPlaceGarlic",
}
-- IMPORTANT BOTH DIRECTIONS FAIL, WHICH IS THE WHOLE VALUE AND ALSO THE SCHEDULING CONSTRAINT.
--           Step 1.1 adds `Budgets.RequestStrike` -> RED (a budget naming a remote the list does not
--           carry). Step 2.3 adds the remote to `Remotes.Up` -> STILL RED (the list is hand-
--           maintained and does not know). Step 3.4 adds it here -> GREEN.
-- IMPORTANT SO NO STEP BEFORE 4.3 MAY USE `npm run verify` AS ITS VERIFY LINE, and none does. If a
--           green tree at every step is wanted instead, move Step 1.1's budget half down into Step
--           3.4; the plan keeps them apart so every tunable lands in one Config commit.

-- tests/anti-cheat-budgets.test.luau:88-95 — the per-remote coverage check
	local budget = Config.AntiCheat.Budgets[name]
	-- ... asserts every UP remote HAS a budget
-- NOTE This is the half that catches "declared but unbudgeted". Combined with
--      `AllowUnbudgetedRemote = false` in Config, a missing entry would REFUSE at runtime — safe,
--      but the symptom would be "the buntot pagi does nothing", which is indistinguishable from the
--      mechanic working correctly on a refused swing. That is why the suite matters more for this
--      remote than for most.

-- tests/anti-cheat-budgets.test.luau:115-120 — the reverse sweep
for name in Config.AntiCheat.Budgets do
	-- ... asserts every budget names a real UP remote
end
-- NOTE This is the half that goes red at Step 1.1.

-- tests/anti-cheat-budgets.test.luau:135-150 — the relationship precedents V10 copies
assert(Config.AntiCheat.Budgets.RequestThrowSalt.Capacity >= Config.Items.CarryLimit)
assert(
	Config.AntiCheat.Budgets.RequestDropItem.Capacity >= Config.Items.CarryLimit,
	`DropCapacity={Config.AntiCheat.Budgets.RequestDropItem.Capacity}, `
)
-- IMPORTANT THESE ARE RELATIONSHIPS, NOT LITERALS, AND V10'S SHOULD BE TOO. The plan pins
--           `RequestStrike.Capacity >= Items.CarryLimit + 1` rather than `>= 2`: raising
--           `CarryLimit` — which `Config.Items`' own comment names as a real change rather than a
--           typo — then moves this with it instead of silently under-provisioning the one remote
--           whose refusal is indistinguishable from the mechanic.
-- NOTE      The `+ 1` is the double-click and the reconnect retry. An honest client fires
--           `RequestStrike` at most ONCE per round, because the swing consumes the only buntot pagi
--           and the second press hits `STRIKE_NOT_HELD` above the spend line.

-- tests/anti-cheat-budgets.test.luau:127-133 — the refill-vs-cooldown precedent
assert(1 / Config.AntiCheat.Budgets.RequestTransform.RefillPerSecond <= Config.Monster.KillCooldown)
-- QUESTION IS THERE AN ANALOGOUS RELATIONSHIP FOR THE STRIKE? A refill of 0.1 is 10s per token,
--          which is shorter than `Items.SaltRevealDuration` (10s) by exactly nothing — so a striker
--          who burns both tokens on refused swings inside one reveal window has none left for the
--          next. That is arguably correct (they also have no buntot pagi left) and arguably worth
--          pinning. The plan does not pin it; raise it if the auditor wants a sixth invariant.

print(`  PASS  anti-cheat-budgets: {#UP_REMOTES} remotes budgeted, {checked} assertions`)
-- NOTE The printed remote count moves from N to N+1 at Step 3.4. A cheap sanity check that the list
--      edit actually landed.
