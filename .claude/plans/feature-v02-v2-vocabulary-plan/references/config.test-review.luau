--!strict
--[[
	REVIEW — tests/config.test.luau (691 lines, 82 assertions). Excerpted.
	Ranges cited: :37-46, :97-101, :126-132, :168-172, :212-218, :225-239, :625-640.
	Read for: V02, to establish EXACTLY which assertions the Step 3.1 value changes touch.

	IMPORTANT V02 MUST NOT EDIT THIS FILE. V11 owns it and writes §6.5's six invariants into it.
	Weakening an assertion here to make a V02 change fit would pre-empt V11 and destroy the invariant
	work — which is the point of the whole exercise.
]]

--[[
	MEASURED ON A CLEAN TREE, 2026-08-27, BEFORE ANY V02 EDIT:

		lune run tests/config.test.luau
		PASS  config: 82 balance invariants     (exit 0)

	This CONTRADICTS docs/BUILD-PLAN.md:191-192, which predicts V02 leaves this suite red. The
	prediction assumes V02 hard-renames Config.Salt.* — which also reds `analyze`, violating V02's own
	Done line. Under this plan's alias design the suite stays green. See the plan preamble.
]]

-- tests/config.test.luau:37-46
-- Step 3.1 changes MaxPlayers 8 -> 5. Both assertions still hold: 5 >= 3, and 5 <= 8.
-- NOTE the second one's comment cites §C.5's rejection of 20-player servers. Its bound is an upper
-- one, so tightening MaxPlayers can never trip it — only raising it can.
check("max is at or above min", Config.Round.MaxPlayers >= Config.Round.MinPlayers)
check("servers stay small", Config.Round.MaxPlayers <= 8)

-- tests/config.test.luau:97-101
-- IMPORTANT THE TIGHTEST OF THE MaxPlayers CONSUMERS. 4 < 8 becomes 4 < 5 — still true, with a margin
-- of exactly one. If a later chunk raises SaltSpawnCount to 5 (tempting, since §6.5 invariant 1 has
-- zero slack) this assertion goes red before the invariant does. Worth knowing which red appears first.
check(
	"there is less salt than there are players",
	Config.Salt.SpawnCount < Config.Round.MaxPlayers
)

-- tests/config.test.luau:126-132
-- Duration 420 -> 300 moves the cycle from 457s to 337s. Comfortably under. NOTE the comment cites §2's
-- "under 8 minutes"; v2.0's §4.1 (spec line 176) tightens the intent to ~5 minutes, so this bound is
-- now loose rather than wrong. V11's territory, not V02's.
local cycle = Config.Round.Intermission + Config.Round.Duration + Config.Round.EndScreen
check("a full round cycle stays under eight minutes", cycle <= 480)

-- tests/config.test.luau:212-218
-- IMPORTANT DURATION = 300 LANDS EXACTLY ON THIS FLOOR. Zero margin after Step 3.1.
-- The comment records why the floor exists: a 60-second value left over from a Studio session once
-- passed every check including this file. So any debug tweak to Duration now reds this suite — which
-- is correct behaviour, and worth flagging so nobody reports it as a V02 regression. Use Config.Debug
-- for playtest pacing, never Duration.
check(
	"a round is long enough to be a round",
	Config.Round.Duration >= 300,
	`Duration={Config.Round.Duration}s — a testing value left in?`
)

-- tests/config.test.luau:225-239
-- IMPORTANT THE TWO ASSERTIONS THAT PIN THE TUNABLES V02 WANTS TO MOVE OR RETIRE.
-- The first pins CorpseFadeTime < CorpseDuration; the second pins CorpseDuration > KillCooldown.
-- Moving CorpseDuration to `Bodies` (§6.5) or deleting KillCooldown (§4.3 retires it) reds BOTH, on
-- top of reddening `analyze`. This is the concrete reason Step 3.3 builds `Bodies` without
-- CorpseDuration and Step 3.2 leaves KillCooldown in place.
check("the fade is shorter than the body's life", Config.Monster.CorpseFadeTime < Config.Monster.CorpseDuration)
check("a body outlives the cooldown", Config.Monster.CorpseDuration > Config.Monster.KillCooldown)

-- tests/config.test.luau:625-640
-- MaxPlayers 8 -> 5 changes maxKills 7 -> 4. Recomputed by hand:
--   aswangCeiling   = 50 + 40 + 15*4 = 150
--   survivorCeiling = 50 + 40 + 25   = 115
-- Both bounds hold: 150 > 115, and 150 < 230. NOTE the margin on the upper bound was much tighter at
-- MaxPlayers = 8 (50+40+105 = 195 vs 230), so this change makes the economy assertion SAFER, not
-- riskier. NOTE also that survivorCeiling is built from XPSurvivorEscapeBonus — a v1.3 escape-gate
-- number that v2.0 retires — so this assertion is itself owed a rewrite by the win-conditions chunk.
local maxKills = Config.Round.MaxPlayers - 1

--[[
	NOT AFFECTED, CHECKED: tests/xp-curve.test.luau:439 builds `roundSeconds` from Round.Duration, but
	uses it only inside a printed string (:481). Its pinned assertion is `roundsTo(2) <= 4`, which is
	driven by the XP award table and Config.Economy, neither of which V02 touches.
]]
