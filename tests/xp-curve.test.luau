--!strict
--[[
	The level curve and the round award (C32, §7, §4.8).

	C32's Verify line is this file: "monotonic, no division by zero at level 1, sane at level 100".
	Each of those three is a property that fails SILENTLY in a way no screenshot catches:

	  · MONOTONICITY. A bar that goes backwards is a progression system telling a player they lost
	    something. It would take a screenshot at exactly the wrong XP total to see it.
	  · THE DIVISION BY ZERO IS AT THE CAP, NOT AT LEVEL 1, and the brief asks about level 1 — so
	    both ends are pinned here. A NaN written into `Profile.XP` cannot be encoded as JSON, which
	    makes every later DataStore write for that player fail silently and permanently.
	  · SANE AT LEVEL 100. "Sane" is not a feeling: the suite prints what the cap costs in rounds, so
	    the answer is measured against `Config.Economy` rather than imagined.

	The award half is here for the reason `Config.Economy`'s header gives — the curve and the award are
	one decision read from two ends, and tuning either alone is how the same table ships "level 5 in
	twenty minutes" and "level 5 in nine hours".

	AND ONE SECRECY PROPERTY, which is the reason C32 is allowed to have a role-conditional award at
	all: with `RoleIsPublic = false` every player's award must be byte-identical whatever their role,
	their outcome and their kills. See `XPCurve`'s header for why that branch exists.
]]

local Config = require("../src/shared/Config")
local XPCurve = require("../src/shared/pure/XPCurve")

type AwardInput = XPCurve.AwardInput

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

--[[
	A curve that is NOT the shipped one, so an assertion passes because the arithmetic is right rather
	than because it happens to agree with Config. The real values get their own section at the end.
]]
local CURVE: XPCurve.Curve = { Base = 100, Growth = 20, MaxLevel = 10 }

local RATES: XPCurve.Rates = {
	XPPerRound = 10,
	XPWinBonus = 7,
	XPSurvivorEscapeBonus = 5,
	XPPerKill = 3,
	CoinsPerRound = 4,
	CoinsWinBonus = 2,
}

--------------------------------------------------------------------------------
-- The curve's shape
--------------------------------------------------------------------------------

check("level 1 costs nothing to reach", XPCurve.totalForLevel(1, CURVE) == 0)
check("level 2 costs exactly Base", XPCurve.totalForLevel(2, CURVE) == 100)
check("level 3 costs Base twice plus one Growth", XPCurve.totalForLevel(3, CURVE) == 220)

--[[
	BELOW AND ABOVE THE DECLARED RANGE, because a corrupt `Level` field reaches this function and a
	negative cost would make every comparison below it meaningless.
]]
check("level 0 clamps to level 1's cost", XPCurve.totalForLevel(0, CURVE) == 0)
check(
	"past the cap clamps to the cap's cost",
	XPCurve.totalForLevel(9999, CURVE) == XPCurve.totalForLevel(CURVE.MaxLevel, CURVE)
)

--------------------------------------------------------------------------------
-- PROPERTY 1 — monotonicity, walked rather than sampled
--------------------------------------------------------------------------------

--[[
	One XP at a time across the whole curve and past its end. A monotonicity bug introduced by a
	future ease shows up at some interior pair and nowhere else, so sampling the round numbers is
	exactly the test that would miss it.

	`Progress` is deliberately NOT required to be monotone — it resets to 0 on every level-up, which
	is the point of a level bar. What must never fall is the LEVEL and the cumulative XP behind it.
]]
local capXP = XPCurve.totalForLevel(CURVE.MaxLevel, CURVE)
local previousLevel = 0
local monotone = true
local firstBreak = ""

for xp = 0, capXP + 500 do
	local standing = XPCurve.levelFor(xp, CURVE)

	if standing.Level < previousLevel and monotone then
		monotone = false
		firstBreak = `at {xp} xp: level {previousLevel} -> {standing.Level}`
	end

	previousLevel = standing.Level
end

check("the level never goes backwards as XP rises", monotone, firstBreak)

--[[
	AND EVERY BOUNDARY IS EXACT. This is the assertion that rules out the closed-form inverse: the
	quadratic root lands a hair below an exact level, so a player with EXACTLY the cost of level 5
	reads as level 4 with a full bar forever — and only the round numbers break, which is why a test
	written against round numbers is the one that has to exist.
]]
for level = 1, CURVE.MaxLevel do
	local exact = XPCurve.totalForLevel(level, CURVE)
	local standing = XPCurve.levelFor(exact, CURVE)

	check(
		`exactly the cost of level {level} IS level {level}`,
		standing.Level == level,
		`got {standing.Level} at {exact} xp`
	)
	check(`level {level} begins with an empty bar`, standing.XPIntoLevel == 0)

	if level > 1 then
		local justBelow = XPCurve.levelFor(exact - 1, CURVE)

		check(
			`one XP short of level {level} is still level {level - 1}`,
			justBelow.Level == level - 1,
			`got {justBelow.Level}`
		)
	end
end

--------------------------------------------------------------------------------
-- PROPERTY 2 — no division by zero, at either end
--------------------------------------------------------------------------------

local fresh = XPCurve.levelFor(0, CURVE)

check("a fresh player is level 1", fresh.Level == 1)
check("level 1 has a real span to fill", fresh.XPForNextLevel == 100)
check("level 1's bar starts empty", fresh.Progress == 0)
check("level 1's progress is a number", fresh.Progress == fresh.Progress)

--[[
	THE CAP IS WHERE THE DIVISION BY ZERO ACTUALLY LIVES. The next level costs nothing, so
	`remaining / span` is 0/0 — and 0/0 is NaN, not an error, so nothing would report it until the
	profile stopped saving.
]]
local capped = XPCurve.levelFor(capXP, CURVE)

check("the cap is reached at its exact cost", capped.Level == CURVE.MaxLevel)
check("at the cap there is nothing left to earn", capped.XPForNextLevel == 0)
check("at the cap the bar is full", capped.Progress == 1)
check("at the cap the progress is a number, not NaN", capped.Progress == capped.Progress)

local past = XPCurve.levelFor(capXP * 100, CURVE)

check("XP past the cap stays at the cap", past.Level == CURVE.MaxLevel)
check("XP past the cap keeps a full bar", past.Progress == 1)

--[[
	A CURVE TUNED INTO A ZERO-COST LEVEL is a Config error, and it must degrade rather than write a
	NaN into eight profiles. `tests/config.test.luau` is where the real tuning is pinned; this is the
	guard for the moment somebody sets `XPPerLevel = 0` to test something and forgets.
]]
local flat = XPCurve.levelFor(0, { Base = 0, Growth = 0, MaxLevel = 5 })

check("a zero-cost curve is a full bar, not a NaN", flat.Progress == flat.Progress)
check("a zero-cost curve reports nothing left to earn", flat.XPForNextLevel == 0)

--------------------------------------------------------------------------------
-- Corrupt XP degrades to a floor rather than propagating
--------------------------------------------------------------------------------

for _, corrupt in { 0 / 0, math.huge, -math.huge, -5000 } do
	local standing = XPCurve.levelFor(corrupt, CURVE)

	check(
		`a corrupt XP value of {corrupt} reads as level 1`,
		standing.Level == 1 and standing.Progress == standing.Progress,
		`got level {standing.Level}, progress {standing.Progress}`
	)
end

--------------------------------------------------------------------------------
-- PROPERTY 3 — the secrecy branch: RoleIsPublic = false is flat for everybody
--------------------------------------------------------------------------------

--[[
	THE ONE ASSERTION THIS WHOLE FEATURE RESTS ON.

	`ProgressionService`'s C31 award carries the warning that a role-conditional award turns the XP
	number itself into a derived hint. C32 discharges it by landing the award at ENDING, after
	`RoundEnded` has already broadcast the reveal — and `RoleIsPublic = false` is the branch for a
	round that somehow reached ENDING with nobody revealed.

	The property is not "the role line is omitted". It is that the whole award is IDENTICAL across
	every combination of role, outcome, survival and kills — because a player who earned 50 while the
	person next to them earned 90 has learned something either way.
]]
local flatAwards: { number } = {}
local flatCoins: { number } = {}

for _, result in
	{ "SURVIVORS_ESCAPED", "ASWANG_WINS", "TIMEOUT", "ABORTED" } :: { XPCurve.RoundResult }
do
	for _, wasAswang in { true, false } do
		for _, survived in { true, false } do
			local award = XPCurve.awardFor({
				Result = result,
				RoleIsPublic = false,
				WasAswang = wasAswang,
				Survived = survived,
				Kills = if wasAswang then 5 else 0,
			}, RATES)

			table.insert(flatAwards, award.XP)
			table.insert(flatCoins, award.Coins)

			check(
				`an unrevealed round shows one line only ({result}, aswang={wasAswang})`,
				#award.Lines == 1,
				`got {#award.Lines} lines`
			)
		end
	end
end

local allSame = true

for _, xp in flatAwards do
	if xp ~= RATES.XPPerRound then
		allSame = false
	end
end

for _, coins in flatCoins do
	if coins ~= RATES.CoinsPerRound then
		allSame = false
	end
end

check(
	`an unrevealed round pays every one of {#flatAwards} role/outcome combinations identically`,
	allSame
)

--------------------------------------------------------------------------------
-- The award table, §4.8
--------------------------------------------------------------------------------

local function award(over: {
	Result: XPCurve.RoundResult,
	WasAswang: boolean?,
	Survived: boolean?,
	Kills: number?,
}): XPCurve.Award
	local input: AwardInput = {
		Result = over.Result,
		RoleIsPublic = true,
		WasAswang = over.WasAswang == true,
		Survived = over.Survived == true,
		Kills = over.Kills or 0,
	}

	return XPCurve.awardFor(input, RATES)
end

check(
	"a survivor who escaped gets round + win + survival",
	award({ Result = "SURVIVORS_ESCAPED", Survived = true }).XP
		== RATES.XPPerRound + RATES.XPWinBonus + RATES.XPSurvivorEscapeBonus
)

check(
	"a survivor who died during a winning round still gets the win",
	award({ Result = "SURVIVORS_ESCAPED", Survived = false }).XP
		== RATES.XPPerRound + RATES.XPWinBonus
)

check(
	"a survivor who survived a lost round still gets the survival bonus",
	award({ Result = "ASWANG_WINS", Survived = true }).XP
		== RATES.XPPerRound + RATES.XPSurvivorEscapeBonus
)

check(
	"a losing survivor who died gets participation only",
	award({ Result = "ASWANG_WINS", Survived = false }).XP == RATES.XPPerRound
)

--[[
	THE ASWANG IS ALIVE AT ENDING IN EVERY ROUND IT DOES NOT ABORT, so an ungated survival bonus would
	pay it for existing — and would pay it on a round it LOST, which inverts what the number teaches.
]]
check(
	"the Aswang never draws the survivor's escape bonus",
	award({ Result = "SURVIVORS_ESCAPED", WasAswang = true, Survived = true }).XP
		== RATES.XPPerRound
)

check(
	"the Aswang's win pays the win bonus and its kills",
	award({ Result = "ASWANG_WINS", WasAswang = true, Survived = true, Kills = 4 }).XP
		== RATES.XPPerRound + RATES.XPWinBonus + RATES.XPPerKill * 4
)

check(
	"a sunrise timeout is an Aswang win",
	award({ Result = "TIMEOUT", WasAswang = true, Survived = true }).XP
		== RATES.XPPerRound + RATES.XPWinBonus
)

check(
	"a sunrise timeout is not a survivor win",
	award({ Result = "TIMEOUT", Survived = true }).XP
		== RATES.XPPerRound + RATES.XPSurvivorEscapeBonus
)

--[[
	AN ABORTED ROUND IS NOBODY'S WIN. The Aswang disconnected or reset into a ghost; neither side
	played it out, and paying the survivors a win for it would make quitting as the monster a way to
	hand your friends a bonus.
]]
check(
	"an aborted round pays no win bonus to the survivors",
	award({ Result = "ABORTED", Survived = true }).XP
		== RATES.XPPerRound + RATES.XPSurvivorEscapeBonus
)

check(
	"an aborted round pays no win bonus to the Aswang either",
	award({ Result = "ABORTED", WasAswang = true, Survived = true, Kills = 3 }).XP
		== RATES.XPPerRound + RATES.XPPerKill * 3
)

check(
	"a kill line is omitted rather than shown as zero",
	#award({ Result = "ASWANG_WINS", WasAswang = true, Kills = 0 }).Lines == 2
)

--[[
	THE BREAKDOWN MUST ADD UP TO THE TOTAL. It is what the end screen renders, and a breakdown that
	disagrees with the number above it is the specific bug that makes a player think they were cheated.
]]
local grid: { AwardInput } = {
	{
		Result = "SURVIVORS_ESCAPED",
		RoleIsPublic = true,
		WasAswang = false,
		Survived = true,
		Kills = 0,
	},
	{
		Result = "SURVIVORS_ESCAPED",
		RoleIsPublic = true,
		WasAswang = true,
		Survived = true,
		Kills = 1,
	},
	{ Result = "ASWANG_WINS", RoleIsPublic = true, WasAswang = true, Survived = true, Kills = 5 },
	{ Result = "TIMEOUT", RoleIsPublic = true, WasAswang = false, Survived = false, Kills = 0 },
	{ Result = "ABORTED", RoleIsPublic = true, WasAswang = false, Survived = true, Kills = 0 },
	{ Result = "ASWANG_WINS", RoleIsPublic = false, WasAswang = true, Survived = true, Kills = 5 },
}

for index, input in grid do
	local result = XPCurve.awardFor(input, RATES)
	local xp = 0
	local coins = 0

	for _, line in result.Lines do
		xp += line.XP
		coins += line.Coins
	end

	check(`breakdown {index} sums to the XP total`, xp == result.XP, `{xp} vs {result.XP}`)
	check(
		`breakdown {index} sums to the coin total`,
		coins == result.Coins,
		`{coins} vs {result.Coins}`
	)
end

--------------------------------------------------------------------------------
-- PROPERTY 4 — purity
--------------------------------------------------------------------------------

local probe: AwardInput = {
	Result = "ASWANG_WINS",
	RoleIsPublic = true,
	WasAswang = true,
	Survived = true,
	Kills = 3,
}

local first = XPCurve.awardFor(probe, RATES)
local second = XPCurve.awardFor(probe, RATES)

check("awardFor is deterministic", first.XP == second.XP and first.Coins == second.Coins)
check("awardFor does not mutate its input", probe.Kills == 3 and probe.WasAswang == true)
check("awardFor does not alias its Lines table", first.Lines ~= second.Lines)
check("awardFor does not mutate its rates", RATES.XPPerRound == 10 and RATES.XPPerKill == 3)

--------------------------------------------------------------------------------
-- The SHIPPED numbers — "sane at level 100" measured, not asserted
--------------------------------------------------------------------------------

local SHIPPED: XPCurve.Curve = {
	Base = Config.Economy.XPPerLevel,
	Growth = Config.Economy.XPPerLevelGrowth,
	MaxLevel = Config.Economy.MaxLevel,
}

local SHIPPED_RATES: XPCurve.Rates = {
	XPPerRound = Config.Economy.XPPerRound,
	XPWinBonus = Config.Economy.XPWinBonus,
	XPSurvivorEscapeBonus = Config.Economy.XPSurvivorEscapeBonus,
	XPPerKill = Config.Economy.XPPerKill,
	CoinsPerRound = Config.Economy.CoinsPerRound,
	CoinsWinBonus = Config.Economy.CoinsWinBonus,
}

--[[
	A TYPICAL ROUND, from the seat most players occupy most of the time: a survivor, on the losing
	side, who died. It is the FLOOR of the award table, so every pace printed below is the slowest
	honest one rather than a best case.
]]
local typicalRound = XPCurve.awardFor({
	Result = "ASWANG_WINS",
	RoleIsPublic = true,
	WasAswang = false,
	Survived = false,
	Kills = 0,
}, SHIPPED_RATES).XP

local roundSeconds = Config.Round.Intermission + Config.Round.Duration + Config.Round.EndScreen
local capCost = XPCurve.totalForLevel(SHIPPED.MaxLevel, SHIPPED)

local function roundsTo(level: number): number
	return math.ceil(XPCurve.totalForLevel(level, SHIPPED) / typicalRound)
end

check("the shipped cap is reachable in finite XP", capCost < math.huge and capCost > 0)
check(
	"the shipped curve reaches its cap at exactly MaxLevel",
	XPCurve.levelFor(capCost, SHIPPED).Level == Config.Economy.MaxLevel
)
check(
	"the shipped cap does not overflow into a NaN",
	XPCurve.levelFor(capCost, SHIPPED).Progress == 1
)

--[[
	THE PACING JUDGEMENT, PINNED RATHER THAN PRINTED AND FORGOTTEN.

	Level 2 is the first cosmetic in `Config.Cosmetics.Catalogue` (`lantern_asul`), and §10's whole
	argument — Appendix C's competitor lost 79.9% of players before their first objective — is that a
	new player must SEE the system pay out inside their FIRST session, not their second. A session is
	three or four rounds; at `Round` durations that is about twenty-five minutes, and the bound below
	is written in rounds rather than minutes so it moves with `Round.Duration` if that is ever tuned.

	The bound is against the FLOOR rate — a survivor who lost and died — so the guarantee holds for the
	unluckiest possible first session rather than for the average one.
]]
check(
	"the first cosmetic level arrives inside a plausible FIRST session",
	roundsTo(2) <= 4,
	`{roundsTo(2)} rounds at the floor rate of {typicalRound} xp`
)

check(
	"the level cap is a long-term goal rather than a weekend",
	roundsTo(Config.Economy.MaxLevel) > 500,
	`{roundsTo(Config.Economy.MaxLevel)} rounds`
)

print(
	`  ....  shipped pace at the floor rate ({typicalRound} xp/round, {roundSeconds}s/round): `
		.. `L2 in {roundsTo(2)} rounds, L5 in {roundsTo(5)}, L10 in {roundsTo(10)}, `
		.. `L{Config.Economy.MaxLevel} in {roundsTo(Config.Economy.MaxLevel)}`
)

if failures > 0 then
	error(`{failures} xp-curve failure(s)`, 0)
end

print(`  PASS  xp-curve: {checked} assertions`)
