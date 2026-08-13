--!strict
-- REVIEW: tests/config.test.luau:15-24, 220-232, and the final print
--
-- Read for the assertion idiom Step 1.4 extends, and for the one invariant this plan gives a second job.

local function check(label: string, ok: boolean, detail: string?)                 -- :15
	if ok then return end
	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end
-- NOTE: the shape copied into both new test files. The `detail` argument is what makes a failure
-- actionable — it prints the actual numbers, so a red line names the two values that disagree rather
-- than only the rule they broke.

-- Spec §4.4. Two selected task points within kill range of each other are one location wearing two
-- hats: the Aswang covers both from a standstill and the "spread" in the draw buys nothing.
check(
	"selected task points are spread further apart than the Aswang can reach",
	Config.Tasks.MinSpacingStuds > Config.Monster.KillRange,                       -- :224
	`MinSpacingStuds={Config.Tasks.MinSpacingStuds}, KillRange={Config.Monster.KillRange}`
)
-- IMPORTANT: MinSpacingStuds already has one pinned relationship, and this plan adds a second that is
-- STRICTER and of a different kind. The existing one is balance (spread must beat the Aswang's reach).
-- The new one — PresenceRangeStuds * 2 < MinSpacingStuds — is CORRECTNESS: it is what makes "which task
-- point is this player at" have a single answer, which is what lets RequestTaskProgress take no
-- arguments at all. A knob with a correctness constraint on it must say so in its own comment, or M12
-- tunes it as pure balance. Risk R6.

check(
	"a lobby death always recovers well before the next round starts",
	Config.Round.RespawnCooldown > 0
		and Config.Round.RespawnCooldown * 2 < Config.Round.Intermission,
	...
)
-- NOTE: the `x * 2 < y` shape with a headroom factor is already the house style for "must not merely
-- exceed, must exceed with room". Both of the new timing invariants use it — grace > heartbeat * 2,
-- and the reciprocal of the heartbeat under the refill rate.

if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end

print("  PASS  config: 26 balance invariants")
-- IMPORTANT and easy to miss: the count in this print is HARDCODED. It is the only thing in the file
-- that would notice an assertion silently deleted in a merge, and leaving it at 26 while adding three
-- is the small lie that makes it useless. Step 1.4 bumps it to 29.

-- QUESTION → answered by reading: does this file run under Lune with no Roblox datatypes? Yes, and it
-- is why Config stores colours as RGB triples (Config.luau:95-100). Both new test files require Config
-- directly for the same reason — tests/task-progress.test.luau asserts against the SHIPPING HoldTime
-- and Ghost.TaskContributionMult rather than against copies that can drift.
