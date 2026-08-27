--!strict
--[[
	The Aswang's health, over its whole domain. (V05, §4.6)

	The build plan asks for the health x event GRID rather than a case per bug, and the reason is the
	one `noise-model` states: this is a small pure function over a BOUNDED domain, which is the one
	shape where enumerating beats reacting. Seven health values against four events is 28 cells, and
	the three properties that matter — the floor holds, a feed never overfills, and `isWeakened`
	agrees with `apply` — are exactly the ones a playtest cannot see. A monster that cannot be
	weakened has no symptom; it just never dies, and that reads as balance.
]]

local Config = require("../src/shared/Config")
local MonsterHealth = require("../src/shared/pure/MonsterHealth")

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

-- SYNTHETIC, not Config's. These assertions are about the MODEL's rules; V16 will retune Config and
-- must not be able to red this file. The real block is cross-checked at the bottom.
local TUNING = {
	MaxHealth = 100,
	WeakenedThreshold = 25,
	SaltDamage = 25,
	FeedHeal = 25,
}

-- Full, mid, at the floor, below it, zero, and the four values that break a naive comparison.
local HEALTHS = { 100, 60, 25, 10, 0, -40, 0 / 0, math.huge, -math.huge }
local EVENTS = { "SALT", "FEED", "NONE", "SHOUT", "" }

print("MonsterHealth")

--[[
	THE GRID. Every health against every event, asserting the invariant that must hold across all of
	it: the answer is always a finite number inside [WeakenedThreshold, MaxHealth]. Nothing in this
	game reduces health below the floor, so a result outside that band is a bug wherever it came
	from.
]]
for _, health in HEALTHS do
	for _, event in EVENTS do
		local result = MonsterHealth.apply(health, event, TUNING)

		check(`{event} on {health}: not NaN`, result == result, `{result}`)
		check(
			`{event} on {health}: inside the band`,
			result >= TUNING.WeakenedThreshold and result <= TUNING.MaxHealth,
			`{result}`
		)
		check(
			`{event} on {health}: isWeakened agrees with the band`,
			MonsterHealth.isWeakened(result, TUNING) == (result <= TUNING.WeakenedThreshold),
			`{result}`
		)
	end
end

--[[
	THE FLOOR IS THE MECHANIC (§4.6). Salt alone must never kill, so no chain of salt hits of any
	length reaches below WeakenedThreshold — asserted by iterating rather than by trusting one call,
	because the failure mode is a floor that holds for one hit and drifts over many.
]]
local chained = TUNING.MaxHealth

for hit = 1, 20 do
	chained = MonsterHealth.apply(chained, "SALT", TUNING)

	check(`salt hit {hit} never breaks the floor`, chained >= TUNING.WeakenedThreshold, `{chained}`)
	check(`salt hit {hit} never kills`, chained > 0, `{chained}`)
end

check(
	"twenty salt hits land exactly on the floor",
	chained == TUNING.WeakenedThreshold,
	`{chained}`
)

-- §4.6's table, at the shipped shape: three hits reach the floor and the third is the one that
-- makes it killable. This is the survivors' path to the second win condition, spelled out.
local after1 = MonsterHealth.apply(TUNING.MaxHealth, "SALT", TUNING)
local after2 = MonsterHealth.apply(after1, "SALT", TUNING)
local after3 = MonsterHealth.apply(after2, "SALT", TUNING)

check("one salt hit does not weaken", not MonsterHealth.isWeakened(after1, TUNING), `{after1}`)
check("two salt hits do not weaken", not MonsterHealth.isWeakened(after2, TUNING), `{after2}`)
check("three salt hits weaken", MonsterHealth.isWeakened(after3, TUNING), `{after3}`)

-- THE TUG-OF-WAR (§4.6): "every kill the Aswang makes heals away one salt hit."
check(
	"a feed undoes exactly one salt hit",
	MonsterHealth.apply(after3, "FEED", TUNING) == after2,
	`{MonsterHealth.apply(after3, "FEED", TUNING)} vs {after2}`
)

local overfed = MonsterHealth.apply(TUNING.MaxHealth, "FEED", TUNING)

check("a feed at full health does not overfill", overfed == TUNING.MaxHealth, `{overfed}`)

-- THE BOUNDARY. §4.6 says "at or below 25 health", so the threshold itself is weakened.
check("the threshold itself is weakened", MonsterHealth.isWeakened(25, TUNING))
check("one point above the threshold is not", not MonsterHealth.isWeakened(25.1, TUNING))
check("full health is not weakened", not MonsterHealth.isWeakened(TUNING.MaxHealth, TUNING))

--[[
	THE DEGENERATE INPUTS, ASSERTED IN THE LOUD DIRECTION. NaN fails every comparison, so an
	unguarded `isWeakened` reports a corrupted monster as NOT weakened — unkillable, silently. The
	module resolves NaN and -inf to the floor precisely so the failure is visible instead.
]]
check("NaN health is weakened, not immortal", MonsterHealth.isWeakened(0 / 0, TUNING))
check("-inf health is weakened", MonsterHealth.isWeakened(-math.huge, TUNING))
check("below the floor reads as weakened", MonsterHealth.isWeakened(-40, TUNING))
check("+inf health is not weakened", not MonsterHealth.isWeakened(math.huge, TUNING))

-- FAILS CLOSED. An event id with no rule changes nothing, rather than healing or hitting.
check("an unknown event is a no-op", MonsterHealth.apply(60, "SHOUT", TUNING) == 60)
check("an empty event is a no-op", MonsterHealth.apply(60, "", TUNING) == 60)
check("NONE is a no-op", MonsterHealth.apply(60, "NONE", TUNING) == 60)

--[[
	A TUNING NOBODY WOULD WRITE ON PURPOSE BUT V16 COULD TYPO. A negative SaltDamage must not heal,
	and a threshold above MaxHealth must not invert the clamp into a heal-on-hit.
]]
local perverse = { MaxHealth = 100, WeakenedThreshold = 25, SaltDamage = -50, FeedHeal = 0 / 0 }

check(
	"a negative SaltDamage does not heal",
	MonsterHealth.apply(50, "SALT", perverse) == 50,
	`{MonsterHealth.apply(50, "SALT", perverse)}`
)
check(
	"a NaN FeedHeal does not poison the state",
	MonsterHealth.apply(50, "FEED", perverse) == 50,
	`{MonsterHealth.apply(50, "FEED", perverse)}`
)

local inverted = { MaxHealth = 50, WeakenedThreshold = 90, SaltDamage = 25, FeedHeal = 25 }
local invertedResult = MonsterHealth.apply(50, "SALT", inverted)

check("an inverted threshold does not heal on a hit", invertedResult <= 50, `{invertedResult}`)
check("an inverted threshold reads as weakened", MonsterHealth.isWeakened(50, inverted))

--[[
	THE RAMP. `MonsterService` lerps the two glow endpoints by this, so its monotonicity IS the
	presentation: §4.6's "the glow gets brighter as it weakens" is false the moment this stops
	increasing as health falls, and nothing in the game would report it.
]]
check("full health is 0 along the ramp", MonsterHealth.weakenedFraction(100, TUNING) == 0)
check("the floor is 1 along the ramp", MonsterHealth.weakenedFraction(25, TUNING) == 1)

local previous = -1

for health = 100, 25, -5 do
	local fraction = MonsterHealth.weakenedFraction(health, TUNING)

	check(`the ramp at {health} is in 0..1`, fraction >= 0 and fraction <= 1, `{fraction}`)
	check(`the ramp at {health} did not go backwards`, fraction > previous, `{fraction}`)

	previous = fraction
end

for _, health in HEALTHS do
	local fraction = MonsterHealth.weakenedFraction(health, TUNING)

	check(`the ramp survives {health}`, fraction == fraction and fraction >= 0 and fraction <= 1)
end

-- A zero-width span returns 1 rather than dividing by it.
local flat = { MaxHealth = 25, WeakenedThreshold = 25, SaltDamage = 25, FeedHeal = 25 }

check("a zero-width ramp answers 1", MonsterHealth.weakenedFraction(25, flat) == 1)

--[[
	THE CROSS-CHECK. Everything above runs on a synthetic tuning so V16 can retune freely — but a
	RENAMED OR MISSING number in the real block would then go unnoticed until a live salt hit did
	nothing, which is a silent failure whose only symptom is that the game got harder.

	The balance RELATIONSHIP (§6.5 invariant 1) is pinned in `tests/config.test.luau` where every
	other balance invariant lives, not here.
]]
local live = {
	MaxHealth = Config.Monster.MaxHealth,
	WeakenedThreshold = Config.Monster.WeakenedThreshold,
	SaltDamage = Config.Items.SaltDamage,
	FeedHeal = Config.Monster.FeedHeal,
}

check(
	"Config's salt actually removes health",
	MonsterHealth.apply(live.MaxHealth, "SALT", live) < live.MaxHealth
)
check(
	"Config's feed actually restores health",
	MonsterHealth.apply(live.WeakenedThreshold, "FEED", live) > live.WeakenedThreshold
)
check("Config's full health is not weakened", not MonsterHealth.isWeakened(live.MaxHealth, live))
check(
	"Config's floor is weakened",
	MonsterHealth.isWeakened(MonsterHealth.apply(live.WeakenedThreshold, "SALT", live), live)
)

print(`  {checked - failures}/{checked} checks passed`)

if failures > 0 then
	error(`{failures} MonsterHealth check(s) failed`, 0)
end
