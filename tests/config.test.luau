--!strict
--[[
	Balance invariants.

	These are not tests of Config's VALUES — every number in there is explicitly "a starting value to
	tune" (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and silent:
	nothing tells you when two numbers that must agree have stopped agreeing, and the symptom shows up
	as a design failure rather than a bug.
]]

local Config = require("../src/shared/Config")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- Spec §9.1: the Solo Trial exists to cover the population hole below MinPlayers. If these two drift
-- apart, the Trial either never offers itself during a dead hour, or offers itself during a live one.
check(
	"the Solo Trial offers itself exactly below the minimum player count",
	Config.Trial.OfferBelowPlayerCount == Config.Round.MinPlayers,
	`Trial.OfferBelowPlayerCount={Config.Trial.OfferBelowPlayerCount}, Round.MinPlayers={Config.Round.MinPlayers}`
)

-- Spec §4.4: five tasks are drawn from twelve locations. Required > pool is unwinnable by construction.
check(
	"there are more task locations than tasks required",
	Config.Tasks.PoolSize > Config.Tasks.TotalRequired,
	`PoolSize={Config.Tasks.PoolSize}, TotalRequired={Config.Tasks.TotalRequired}`
)

-- Spec §9: small servers fill faster and feel full sooner. Max below min is unstartable.
check(
	"the server can actually reach the minimum",
	Config.Round.MaxPlayers >= Config.Round.MinPlayers
)

-- Spec §C.5 rejects 20-player servers outright: intimacy and paranoia both die at that scale.
check(
	"servers stay small enough for paranoia",
	Config.Round.MaxPlayers <= 8,
	`MaxPlayers={Config.Round.MaxPlayers}`
)

-- Spec §4.3: the transform is forced to revert after MaxTransformTime. If the kill cooldown were
-- shorter than a full transform cycle, the Aswang could chain kills and the "every kill is a gamble"
-- pillar collapses.
check(
	"the kill cooldown outlasts a full transform cycle",
	Config.Monster.KillCooldown > Config.Monster.TransformTime + Config.Monster.RevertTime,
	`KillCooldown={Config.Monster.KillCooldown}`
)

-- Spec §4.3: the transform must be witnessable. A windup shorter than a frame is an invisible kill,
-- which §2 lists as the thing the design pillar explicitly kills.
check(
	"the transform is long enough to be seen",
	Config.Monster.TransformTime >= 1,
	`TransformTime={Config.Monster.TransformTime}`
)

-- Spec §4.6: salt is thrown from outside kill range, or it is not counterplay — it is a suicide button.
check(
	"salt reaches further than the Aswang kills",
	Config.Salt.ThrowRange > Config.Monster.KillRange,
	`ThrowRange={Config.Salt.ThrowRange}, KillRange={Config.Monster.KillRange}`
)

-- Spec §4.6: the reveal must outlast the stun, or the Aswang is revealed only while it cannot move —
-- information nobody can act on.
check(
	"the salt reveal outlasts the stun",
	Config.Salt.RevealDuration > Config.Salt.StunDuration,
	`RevealDuration={Config.Salt.RevealDuration}, StunDuration={Config.Salt.StunDuration}`
)

-- Spec §4.7: ghosts contribute at reduced speed. At 0 they are spectators, which is the retention leak
-- the ghost system exists to close; at 1 dying is free.
check(
	"ghosts contribute, but less than the living",
	Config.Ghost.TaskContributionMult > 0 and Config.Ghost.TaskContributionMult < 1,
	`TaskContributionMult={Config.Ghost.TaskContributionMult}`
)

-- Spec §4.1: total cycle ≈ 7.5 min, and §2 demands "under 8 minutes, back in within 30 seconds".
local cycle = Config.Round.Intermission
	+ Config.Round.StartingDelay
	+ Config.Round.Duration
	+ Config.Round.EndScreen

check("a full round cycle stays under eight minutes", cycle <= 480, `cycle={cycle}s`)

-- Spec §10: the launch gate. Below this first-objective conversion, everything else stops.
check(
	"the FTUE conversion gate is still set to the spec's threshold",
	Config.Badges.FirstTaskConversionGate >= 0.5,
	`gate={Config.Badges.FirstTaskConversionGate} — the competitor's number was 0.201`
)

-- Spec §5: many dynamic lights is the #1 mobile FPS killer, and 60% of players are on mobile.
check("the mobile light budget is still capped", Config.Performance.MaxVisibleLights <= 8)

-- Spec §4.2: the anti-repeat weighting must be MONOTONIC in recency — more recent means less likely —
-- and never zero. Three numbers in the wrong order still draw an Aswang every round, so nothing about
-- the game looks broken; the only symptom is players quietly being the monster twice in a row.
check(
	"a more recent Aswang is less likely than an older one",
	Config.Roles.RecentAswangWeight < Config.Roles.OlderAswangWeight,
	`recent={Config.Roles.RecentAswangWeight}, older={Config.Roles.OlderAswangWeight}`
)

check(
	"any recent Aswang is less likely than someone who has never been one",
	Config.Roles.OlderAswangWeight < Config.Roles.BaseWeight,
	`older={Config.Roles.OlderAswangWeight}, base={Config.Roles.BaseWeight}`
)

-- Zero is a ban, not a discount. See the Config comment.
check(
	"nobody is ever excluded from the draw outright",
	Config.Roles.RecentAswangWeight > 0,
	`recent={Config.Roles.RecentAswangWeight}`
)

-- Spec §4.2: history covers the last 2 rounds. A history as long as the server is large would give
-- every player a reduced weight at once, which is the same as no weighting at all.
check(
	"the anti-repeat history is shorter than a full server",
	Config.Roles.RepeatCooldownRounds >= 1
		and Config.Roles.RepeatCooldownRounds < Config.Round.MaxPlayers,
	`RepeatCooldownRounds={Config.Roles.RepeatCooldownRounds}`
)

-- Spec §4.2 / §3: exactly one Aswang, and at least two survivors at the minimum player count — a
-- round drawn with AswangCount >= MinPlayers is over before ACTIVE begins.
check(
	"a minimum-sized round still has survivors in it",
	Config.Roles.AswangCount < Config.Round.MinPlayers,
	`AswangCount={Config.Roles.AswangCount}, MinPlayers={Config.Round.MinPlayers}`
)

-- Spec §4.2: the 3-second private intro plays during STARTING. If it outlasts StartingDelay it is
-- still on screen when ACTIVE begins, and the Aswang spends the opening seconds of the round reading
-- a card instead of moving — the one moment when standing still is most conspicuous.
check(
	"the Aswang intro finishes before the round goes live",
	Config.Roles.IntroDuration < Config.Round.StartingDelay,
	`IntroDuration={Config.Roles.IntroDuration}, StartingDelay={Config.Round.StartingDelay}`
)

-- Spec §6.5 / README: shipping with SoloTesting on skips MinPlayers for everyone.
check(
	"solo testing is off",
	Config.Debug.SoloTesting == false,
	"this must never be true on a published place"
)

if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end

print("  PASS  config: 19 balance invariants")
