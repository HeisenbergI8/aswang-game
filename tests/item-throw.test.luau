--!strict
--[[
	The item throw (§4.6, V08) — the cone, the range, and the FIVE worlds that are all MISS.

	MIGRATED FROM `tests/salt-throw.test.luau` (C14, 70 assertions). The geometry sections are that
	file unchanged: `ItemThrow.inCone` is `SaltThrow.inCone` byte-for-byte, so every cone, range and
	degenerate-input assertion applies to the same code it was written against.

	THE ASSERTION THIS FILE EXISTS FOR is the worlds table: that every geometric and identity refusal
	collapses to the SAME verdict. `ItemThrow` returning `MISS_NOT_ASWANG` beside `MISS_OUT_OF_RANGE`
	would be a free role oracle — stand in front of each player in turn, throw, read the monster off
	the refusal — and it is a refactor somebody will reach for the first time they debug a miss. A
	test that only checked "an untransformed Aswang is not a hit" would pass happily while that
	shipped.

	V08 ADDS THE FIFTH WORLD — the thrower is holding a bawang or the buntot pagi — TO THAT SAME
	COLLAPSE, and it is the row most likely to be argued out. It looks harmless: you already know
	what you are holding, so a `MISS_WRONG_ITEM` seems to tell the thrower nothing new. The leak is
	in the NEGATIVE. Throw while holding salt, and a refusal that is NOT `MISS_WRONG_ITEM` is a
	refusal about the TARGET. The assertion below is therefore not "a bawang cannot hit" — that would
	pass while `MISS_WRONG_ITEM` shipped — but that all six rows produce the same value.
]]

local ItemThrow = require("../src/shared/pure/ItemThrow")

type Vec3 = ItemThrow.Vec3
type PlayerState = ItemThrow.PlayerState
type RoundPhase = ItemThrow.RoundPhase
type ItemType = ItemThrow.ItemType

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

local function v(x: number, y: number, z: number): Vec3
	return { X = x, Y = y, Z = z }
end

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }
local PHASES: { RoundPhase } = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

-- Annotated for the reason `.claude/lessons/pure-module-unions-widen-in-lists.md` gives: a literal
-- union widens to `string` inside a list, and the comparisons would still compile.
local NOT_SALT: { ItemType } = { "BAWANG", "BUNTOT_PAGI" }

--[[
	A throw that hits: thrower at the origin looking down +X, holding salt, a transformed Aswang ten
	studs along it. Every case below is this, with one thing changed.
]]
local function request(overrides: {
	Phase: RoundPhase?,
	ThrowerState: PlayerState?,
	Held: ItemType?,
	ThrowerPos: Vec3?,
	Direction: Vec3?,
	TargetPos: Vec3?,
	TargetIsTransformedAswang: boolean?,
	Range: number?,
	ConeDegrees: number?,
}): ItemThrow.Request
	return {
		Phase = overrides.Phase or "ACTIVE",
		ThrowerState = overrides.ThrowerState or "ALIVE",
		-- `or "SALT"` would make an empty hand untestable: nil is a meaningful value here, and the
		-- fallback would silently rewrite it to the one value that can produce OK.
		Held = if overrides.Held == nil then "SALT" else overrides.Held,
		ThrowerPos = overrides.ThrowerPos or v(0, 0, 0),
		Direction = overrides.Direction or v(1, 0, 0),
		TargetPos = overrides.TargetPos or v(10, 0, 0),
		TargetIsTransformedAswang = if overrides.TargetIsTransformedAswang == nil
			then true
			else overrides.TargetIsTransformedAswang,
		Range = overrides.Range or 25,
		ConeDegrees = overrides.ConeDegrees or 20,
	}
end

-- The empty hand cannot go through `request` — see the comment on `Held` above. Built explicitly.
local function emptyHandedRequest(): ItemThrow.Request
	local base = request({})
	base.Held = nil
	return base
end

check("the baseline throw hits", ItemThrow.evaluate(request({})) == "OK")

--------------------------------------------------------------------------------
-- Phase and thrower state: the full grid, one OK cell.
--------------------------------------------------------------------------------

for _, phase in PHASES do
	for _, state in STATES do
		local verdict = ItemThrow.evaluate(request({ Phase = phase, ThrowerState = state }))

		local expected: ItemThrow.Verdict = if phase ~= "ACTIVE"
			then "ITEM_WRONG_PHASE"
			elseif state ~= "ALIVE" then "ITEM_THROWER_NOT_ALIVE"
			else "OK"

		check(`{phase} x {state} is {expected}`, verdict == expected, `got {verdict}`)
	end
end

do
	local permitted = 0

	for _, state in STATES do
		if ItemThrow.evaluate(request({ ThrowerState = state })) == "OK" then
			permitted += 1
		end
	end

	check("exactly one PlayerState may throw", permitted == 1, `{permitted} permitted`)
end

--------------------------------------------------------------------------------
-- The slot. C14's five pouch assertions become four item ones: the arithmetic
-- guards (negative, NaN, infinite) died with the number they guarded, and the
-- wrong-item worlds took their place.
--------------------------------------------------------------------------------

check("an empty hand, no throw", ItemThrow.evaluate(emptyHandedRequest()) == "ITEM_NO_ITEM")

check("holding salt throws", ItemThrow.evaluate(request({ Held = "SALT" })) == "OK")

for _, item in NOT_SALT do
	check(
		`holding {item} on a perfect line is MISS, not a hit`,
		ItemThrow.evaluate(request({ Held = item })) == "MISS"
	)
end

--------------------------------------------------------------------------------
-- Range.
--------------------------------------------------------------------------------

check(
	"a target exactly at range hits",
	ItemThrow.evaluate(request({ TargetPos = v(25, 0, 0), Range = 25 })) == "OK"
)

check(
	"a target one stud past range misses",
	ItemThrow.evaluate(request({ TargetPos = v(26, 0, 0), Range = 25 })) == "MISS"
)

check(
	"a zero range misses rather than hitting everything",
	ItemThrow.evaluate(request({ Range = 0 })) == "MISS"
)

check(
	"an infinite range misses rather than reaching the whole map",
	ItemThrow.evaluate(request({ Range = math.huge })) == "MISS"
)

check("a NaN range misses", ItemThrow.evaluate(request({ Range = 0 / 0 })) == "MISS")

--------------------------------------------------------------------------------
-- The cone. 20 degrees half-angle around +X.
--------------------------------------------------------------------------------

check(
	"dead ahead hits",
	ItemThrow.evaluate(request({ TargetPos = v(10, 0, 0), Direction = v(1, 0, 0) })) == "OK"
)

--[[
	tan(19 deg) * 10 ~= 3.44 studs of lateral offset at ten studs out — inside a 20-degree half-angle.
	tan(21 deg) * 10 ~= 3.84 — outside it. Computed rather than eyeballed so the two cases genuinely
	straddle the boundary rather than both sitting comfortably on one side of it.
]]
check(
	"just inside the cone hits",
	ItemThrow.evaluate(request({ TargetPos = v(10, 0, math.tan(math.rad(19)) * 10) })) == "OK"
)

check(
	"just outside the cone misses",
	ItemThrow.evaluate(request({ TargetPos = v(10, 0, math.tan(math.rad(21)) * 10) })) == "MISS"
)

check("directly behind misses", ItemThrow.evaluate(request({ TargetPos = v(-10, 0, 0) })) == "MISS")

check("perpendicular misses", ItemThrow.evaluate(request({ TargetPos = v(0, 0, 10) })) == "MISS")

check(
	"a zero direction misses rather than dividing by zero",
	ItemThrow.evaluate(request({ Direction = v(0, 0, 0) })) == "MISS"
)

check(
	"a NaN direction misses",
	ItemThrow.evaluate(request({ Direction = v(0 / 0, 0, 0) })) == "MISS"
)

check(
	"an infinite direction misses",
	ItemThrow.evaluate(request({ Direction = v(math.huge, 0, 0) })) == "MISS"
)

check(
	"an unnormalised direction still hits — magnitude is not trusted either way",
	ItemThrow.evaluate(request({ Direction = v(500, 0, 0) })) == "OK"
)

check("a cone of zero degrees misses", ItemThrow.evaluate(request({ ConeDegrees = 0 })) == "MISS")

check(
	"a cone of 90 degrees or more misses rather than hitting behind you",
	ItemThrow.evaluate(request({ ConeDegrees = 90 })) == "MISS"
)

check("a NaN cone misses", ItemThrow.evaluate(request({ ConeDegrees = 0 / 0 })) == "MISS")

check(
	"the thrower standing on the target misses rather than dividing by zero",
	ItemThrow.evaluate(request({ TargetPos = v(0, 0, 0) })) == "MISS"
)

--------------------------------------------------------------------------------
-- THE ONE THAT MATTERS: every failing world collapses to the same verdict.
--------------------------------------------------------------------------------

check(
	"an untransformed Aswang in the cone is a MISS, not a weaker hit",
	ItemThrow.evaluate(request({ TargetIsTransformedAswang = false })) == "MISS"
)

do
	--[[
		The FIVE worlds §4.6's secrecy argument turns on, as six rows. If any future edit splits
		these, this assertion fails and the role oracle is caught here rather than in a playtest —
		or worse, never, because a compromised client is the only party who would notice.

		THE ANNOTATION IS LOAD-BEARING. Without `: { { label: string, verdict: ItemThrow.Verdict } }`
		the field infers as plain `string`, the comparisons still compile, and this file passes while
		asserting nothing about the union.
	]]
	local worlds: { { label: string, verdict: ItemThrow.Verdict } } = {
		{
			label = "nothing / a survivor in the cone",
			verdict = ItemThrow.evaluate(request({ TargetIsTransformedAswang = false })),
		},
		{
			label = "the Aswang, untransformed, dead ahead",
			verdict = ItemThrow.evaluate(
				request({ TargetIsTransformedAswang = false, TargetPos = v(5, 0, 0) })
			),
		},
		{
			label = "the Aswang, transformed, past range",
			verdict = ItemThrow.evaluate(request({ TargetPos = v(100, 0, 0) })),
		},
		{
			label = "the Aswang, transformed, in range, outside the cone",
			verdict = ItemThrow.evaluate(request({ TargetPos = v(0, 0, 10) })),
		},
		{
			label = "V08 — a perfect throw while holding a bawang",
			verdict = ItemThrow.evaluate(request({ Held = "BAWANG" })),
		},
		{
			label = "V08 — a perfect throw while holding the buntot pagi",
			verdict = ItemThrow.evaluate(request({ Held = "BUNTOT_PAGI" })),
		},
	}

	local distinct: { [string]: boolean } = {}

	for _, world in worlds do
		distinct[world.verdict] = true
		check(`{world.label} is MISS`, world.verdict == "MISS", `got {world.verdict}`)
	end

	local count = 0

	for _ in distinct do
		count += 1
	end

	check(
		"all six failing worlds return ONE verdict — no refusal shape to read a role off",
		count == 1,
		`{count} distinct verdicts across the six worlds`
	)
end

--[[
	THE WRONG ITEM IS INDISTINGUISHABLE FROM A GEOMETRIC MISS ACROSS THE WHOLE GEOMETRY, not just on
	the perfect line above. This is the negative-oracle argument as a grid: if `MISS` for a bawang
	ever differed from `MISS` for salt-aimed-badly in ANY cell, a client could difference the two.
]]
do
	local geometries: { { label: string, target: Vec3 } } = {
		{ label = "dead ahead", target = v(10, 0, 0) },
		{ label = "past range", target = v(100, 0, 0) },
		{ label = "outside the cone", target = v(0, 0, 10) },
	}

	for _, item in NOT_SALT do
		for _, geometry in geometries do
			check(
				`holding {item}, {geometry.label}, is MISS`,
				ItemThrow.evaluate(request({ Held = item, TargetPos = geometry.target })) == "MISS"
			)
		end
	end
end

--[[
	THE TWO HALVES `ItemService` ANDs BEFORE IT SPENDS THE SLOT, ASSERTED TOGETHER.

	The throw handler spends the slot on MISS, because §4.6 says a miss still costs you the pouch.
	A player holding the round's only buntot pagi who presses throw gets MISS from THIS module — the
	fifth world, collapsed on purpose — so the spend would destroy the win condition on a keypress,
	with a symptom identical to an honest miss.

	What stops it is `pure/ItemUse.verbFor`, and the guard is only sound if BOTH of these hold at
	once: the throw misses, AND the verb is not a throw. Asserting them in the same place is what
	makes the pairing visible; asserting either alone would look sufficient and would not be.
]]
do
	local ItemUse = require("../src/shared/pure/ItemUse")

	for _, item in NOT_SALT do
		check(
			`{item}: ItemThrow says MISS and ItemUse refuses the spend`,
			ItemThrow.evaluate(request({ Held = item })) == "MISS"
				and ItemUse.verbFor(item) ~= "USE_THROW"
		)
	end

	check(
		"salt is the one item where both halves permit the spend",
		ItemThrow.evaluate(request({ Held = "SALT" })) == "OK"
			and ItemUse.verbFor("SALT") == "USE_THROW"
	)
end

--[[
	THE THROWER-ONLY GATES ARE THROWER-ONLY, ASSERTED OVER THE WHOLE TARGET DOMAIN.

	AN EXPLOIT AUDIT PROVED THIS WRONG IN THE SERVICE. `ItemService.resolveThrow` evaluated these
	three verdicts only INSIDE its per-candidate loop, so with zero rooted candidates a throw in
	ENDING, or by a dead player, fell through to MISS — and MISS reaches the spend line. The fix was
	a single pre-loop call with a sentinel target.

	THIS ASSERTS THE PROPERTY THAT MAKES THAT FIX SOUND, rather than one case per bug (which is
	`.claude/lessons/green-after-each-patch-hides-a-loop`'s failure shape): a thrower-only refusal
	must be the SAME verdict for every target in the domain, including the sentinel the service
	passes. If any of these depended on the target, the pre-loop call would answer differently from
	the loop and the two would drift.
]]
do
	local targets: { { label: string, target: Vec3, isAswang: boolean } } = {
		{ label = "a transformed Aswang dead ahead", target = v(10, 0, 0), isAswang = true },
		{ label = "a survivor dead ahead", target = v(10, 0, 0), isAswang = false },
		{ label = "nothing in range", target = v(500, 0, 0), isAswang = false },
		-- The sentinel `resolveThrow` actually passes before its loop: the thrower's own position,
		-- with the Aswang flag forced false so the call can never return OK.
		{ label = "the sentinel (own position)", target = v(0, 0, 0), isAswang = false },
	}

	local cases: { { label: string, overrides: any, expected: ItemThrow.Verdict } } = {
		{ label = "ENDING", overrides = { Phase = "ENDING" }, expected = "ITEM_WRONG_PHASE" },
		{
			label = "dead thrower",
			overrides = { ThrowerState = "DEAD" },
			expected = "ITEM_THROWER_NOT_ALIVE",
		},
	}

	for _, case in cases do
		for _, t in targets do
			local req = request(case.overrides)
			req.TargetPos = t.target
			req.TargetIsTransformedAswang = t.isAswang

			check(
				`{case.label} refuses identically against {t.label}`,
				ItemThrow.evaluate(req) == case.expected,
				`got {ItemThrow.evaluate(req)}`
			)
		end
	end

	-- The empty hand, over the same target domain. Built explicitly because `request` cannot
	-- express a nil slot.
	for _, t in targets do
		local req = emptyHandedRequest()
		req.TargetPos = t.target
		req.TargetIsTransformedAswang = t.isAswang

		check(
			`an empty hand refuses identically against {t.label}`,
			ItemThrow.evaluate(req) == "ITEM_NO_ITEM",
			`got {ItemThrow.evaluate(req)}`
		)
	end
end

--------------------------------------------------------------------------------
-- Precedence and purity.
--------------------------------------------------------------------------------

check(
	"phase outranks everything",
	ItemThrow.evaluate(request({ Phase = "ENDING", ThrowerState = "DEAD" })) == "ITEM_WRONG_PHASE"
)

check(
	"thrower state outranks the slot",
	ItemThrow.evaluate(request({ ThrowerState = "DEAD" })) == "ITEM_THROWER_NOT_ALIVE"
)

--[[
	THE EMPTY HAND OUTRANKS GEOMETRY, AND THE WRONG ITEM DOES NOT. This pair is the migration's
	single most important structural assertion. Empty depends only on the thrower, so every candidate
	gets the same answer and there is nothing to difference. The wrong item is only reachable AFTER a
	target was considered, so it must be collapsed into MISS — which the row below proves.
]]
do
	local empty = emptyHandedRequest()
	empty.TargetIsTransformedAswang = false

	check("the empty hand outranks geometry", ItemThrow.evaluate(empty) == "ITEM_NO_ITEM")
end

check(
	"the wrong item does NOT outrank geometry — it joins it",
	ItemThrow.evaluate(request({ Held = "BAWANG", TargetIsTransformedAswang = false })) == "MISS"
)

do
	local input = request({})
	local first = ItemThrow.evaluate(input)
	local second = ItemThrow.evaluate(input)

	check("evaluate is deterministic", first == second, `{first} then {second}`)
	check(
		"evaluate does not mutate its request",
		input.Held == "SALT" and input.Range == 25 and input.TargetPos.X == 10
	)
end

--------------------------------------------------------------------------------
-- `inCone` DIRECTLY (C22). It was extracted from `evaluate` so the Solo Trial could
-- share the real aim without inheriting the round's rules — the trial runs at IDLE
-- against a scripted rig, where phase, thrower state and the slot have no meaning.
--
-- Tested on its own because it has a caller that never goes through `evaluate`, and
-- a geometry function with two callers and one test path is a function whose second
-- caller is unverified. V08 renamed the module and changed nothing about this half.
--------------------------------------------------------------------------------

local ORIGIN: ItemThrow.Vec3 = { X = 0, Y = 0, Z = 0 }
local FORWARD: ItemThrow.Vec3 = { X = 0, Y = 0, Z = 1 }

check(
	"a target dead ahead and in range is in the cone",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 10 }, 20, 30) == true
)

check(
	"a target dead behind is not, whatever the range",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = -10 }, 20, 30) == false
)

check(
	"a target beyond the range is not, however well aimed",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 30 }, 20, 30) == false
)

check(
	"a target exactly at the range boundary is in",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 20 }, 20, 30) == true
)

-- The degenerate inputs, each of which must answer false rather than error. A zero direction is the
-- one a client can actually send.
check(
	"a zero direction refuses rather than erroring",
	ItemThrow.inCone(ORIGIN, { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 5 }, 20, 30) == false
)

check(
	"a cone at 90 degrees or more refuses — it would hit what is behind you",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 20, 90) == false
)

check(
	"a zero cone refuses",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 20, 0) == false
)

check(
	"an infinite range refuses",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, math.huge, 30) == false
)

check(
	"a zero range refuses",
	ItemThrow.inCone(ORIGIN, FORWARD, { X = 0, Y = 0, Z = 5 }, 0, 30) == false
)

--[[
	THE PROPERTY THAT KEEPS THE TUTORIAL HONEST: `inCone` is what `evaluate` uses, so a throw the
	real game would land is a throw the trial lands, at the same Config numbers. If these two ever
	disagree, the tutorial has started teaching an aim the game does not have — which is the exact
	failure C22 teaches by doing in order to avoid. V08 re-points `TrialService` at this module, so
	this property is what proves the retarget was a rename rather than a rewrite.
]]
for _, distance in { 1, 5, 10, 14, 15 } do
	local target: ItemThrow.Vec3 = { X = 0, Y = 0, Z = distance }

	local geometric = ItemThrow.inCone(ORIGIN, FORWARD, target, 15, 25)

	local full = ItemThrow.evaluate({
		Phase = "ACTIVE" :: ItemThrow.RoundPhase,
		ThrowerState = "ALIVE" :: ItemThrow.PlayerState,
		Held = "SALT" :: ItemThrow.ItemType,
		ThrowerPos = ORIGIN,
		Direction = FORWARD,
		TargetPos = target,
		TargetIsTransformedAswang = true,
		Range = 15,
		ConeDegrees = 25,
	}) == "OK"

	check(`the trial's aim and the round's agree at {distance} studs`, geometric == full)
end

if failures > 0 then
	error(`{failures} item-throw assertion(s) failed`, 0)
end

print(`  PASS  item-throw: {checked} assertions over the cone, the range and the five MISS worlds`)
