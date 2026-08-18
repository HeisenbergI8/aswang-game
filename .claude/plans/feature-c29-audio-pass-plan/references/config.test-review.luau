--!strict
--[[
	REVIEW — tests/config.test.luau (686 lines; read 1-45 and the index of its 18 `check(` calls)

	EDITED BY THIS PLAN: Step 1.4 appends the audio relationships, and Step 4.2's asset-id format
	assertion is what makes the sourcing pass verifiable at all.
]]

-- tests/config.test.luau:1-9
--[[
	Balance invariants.

	These are not tests of Config's VALUES — every number in there is explicitly "a starting value to
	tune" (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and silent:
	nothing tells you when two numbers that must agree have stopped agreeing, and the symptom shows up
	as a design failure rather than a bug.
]]
-- IMPORTANT: the standard every audio assertion must meet. "HeartbeatVolume is 0.7" would be a test of
-- a value and does not belong; "HeartbeatRange <= Monster.TransformAudioRange" is a relationship whose
-- violation has no symptom — the heartbeat would simply carry further than §4.3's documented tell,
-- and nobody would ever be told.

-- tests/config.test.luau:11
local Config = require("../src/shared/Config")
-- IMPORTANT: the ONLY require in this file today. Step 1.4 adds `AudioCues`, so that a cue with a
-- rule and no asset slot is a red test rather than silence during a playtest. Safe — AudioCues
-- requires nothing — but it does mean a syntax error in the pure module now reds the balance suite
-- too. Accepted deliberately; recorded in Phase 1's Issues.

-- tests/config.test.luau:16-25
local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end
-- The helper the plan's diffs call. Same shape in tests/sky-cycle.test.luau, so
-- tests/audio-cues.test.luau copies it rather than inventing a third convention.
-- NOTE: `detail` is optional and every good existing call passes it with the actual numbers
-- interpolated (`PoolSize={...}, TotalRequired={...}`). The audio assertions should do the same — a
-- failure that names the two numbers is a failure someone can fix without opening Config.

-- tests/config.test.luau:27-33 (the template to follow)
-- Spec §9.1: the Solo Trial exists to cover the population hole below MinPlayers. If these two drift
-- apart, the Trial either never offers itself during a dead hour, or offers itself during a live one.
check(
	"the Solo Trial offers itself exactly below the minimum player count",
	Config.Trial.OfferBelowPlayerCount == Config.Round.MinPlayers,
	`Trial.OfferBelowPlayerCount={Config.Trial.OfferBelowPlayerCount}, Round.MinPlayers={Config.Round.MinPlayers}`
)
-- NOTE: every check carries a SPEC CITATION and a consequence in prose. The audio ones must too —
-- §4.3 for the heartbeat range, §5's budget for the one-shot cleanup ordering, Appendix C.3 for the
-- sunrise threshold.

-- tests/config.test.luau:195
check("a full round cycle stays under eight minutes", cycle <= 480, `cycle={cycle}s`)
-- NOTE: an example of a derived quantity being checked rather than a raw field. The audio equivalent
-- worth considering later: total simultaneous Sound streams implied by the config, against §5's
-- budget. Not in this plan — the instance count is bounded by construction (one bed, one bounded
-- one-shot, one heartbeat) rather than by arithmetic over Config.
