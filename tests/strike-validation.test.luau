--!strict
--[[
	tests/strike-validation.test.luau — the two-condition grid, exhaustively. (V10, §4.6)

	`docs/BUILD-PLAN.md`'s V10 Verify line asks for exactly this: "over state × health × distance ×
	phase, asserting every non-Exposed-or-non-Weakened cell is a refusal." The grid below is that
	product plus the striker's own three facts, because the SPEND LINE runs between the two groups and
	a test that only covered the target half would prove the mechanic and miss the exploit.

	IT IS A PRODUCT RATHER THAN A LIST OF CASES, for `tests/kill-validation.test.luau`'s reason: a
	hand-written case list grows a hole every time the union does, and nothing reports it.

	HEALTH APPEARS AS THE `TargetWeakened` BOOLEAN RATHER THAN AS A NUMBER. That is the module's
	signature and the reason is in its header — `MonsterService.IsWeakened` is the one source of the
	predicate, and a health number in a second caller's local is where a log line grows. The axis is
	the same two-valued axis a number would collapse to.
]]

local StrikeValidation = require("../src/shared/pure/StrikeValidation")

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1
	if not ok then
		failures += 1
		print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
	end
end

--[[
	THE AXES. Every annotation here is load-bearing: without `: { StrikeValidation.ItemType? }` the
	list widens to `{ string }`, `evaluate`'s parameter rejects it, and the fix a hurried author
	reaches for is a cast that deletes the checking.
	(`.claude/lessons/pure-module-unions-widen-in-lists.md`.)
]]
local PHASES: { StrikeValidation.RoundPhase } =
	{ "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }
local PLAYER_STATES: { StrikeValidation.PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }
local HELD: { StrikeValidation.ItemType? } = { nil, "SALT", "BAWANG", "BUNTOT_PAGI" }
local MONSTER_STATES: { StrikeValidation.MonsterState? } =
	{ nil, "NORMAL", "TRANSFORMED", "EXPOSED", "FEEDING", "CAMOUFLAGED" }
local BOOLS: { boolean } = { false, true }

-- Inside, exactly at the boundary, just outside, far outside, and absent. `RANGE` matches nothing in
-- Config on purpose: this suite proves the RULE, and `tests/config.test.luau` proves the number.
local RANGE = 8
local DISTANCES: { number? } = { nil, 0, 4, RANGE, RANGE + 0.001, 40 }

--[[
	A LEADING nil IN A LUAU LIST IS INVISIBLE TO `#`, AND THREE OF THESE AXES HAVE ONE.

	`HELD[1]`, `MONSTER_STATES[1]` and `DISTANCES[1]` are nil — which is "empty hand", "the target is
	not the monster" and "the server resolved nobody", the three most important cells in this file.
	`for _, x in HELD` starts at the first non-nil entry and the suite still prints PASS having never
	tested them. So the three loops below count explicitly.

	SANITY-CHECK THE PRINTED CELL COUNT. The product is 5 × 4 × 4 × 6 × 6 × 4 × 2 × 2 = 46,080. A
	count of 30,720 means an axis lost its nil.
]]
local HELD_N, MONSTER_N, DIST_N = 4, 6, 6

--[[
	A SECOND, INDEPENDENT STATEMENT OF THE RULE, in the order the module fixes. Written out rather
	than calling the module, or the test proves only that the module equals itself —
	`tests/kill-validation.test.luau` makes the same choice for the same reason. An auditor reading
	this as duplication is reading it correctly; the duplication is the test.
]]
local function expected(
	phase: StrikeValidation.RoundPhase,
	strikerState: StrikeValidation.PlayerState,
	held: StrikeValidation.ItemType?,
	distance: number?,
	targetState: StrikeValidation.MonsterState?,
	targetPlayerState: StrikeValidation.PlayerState?,
	exposed: boolean,
	weakened: boolean
): StrikeValidation.Verdict
	if phase ~= "ACTIVE" then
		return "STRIKE_WRONG_PHASE"
	end
	if strikerState ~= "ALIVE" then
		return "STRIKE_NOT_ALIVE"
	end
	if held ~= "BUNTOT_PAGI" then
		return "STRIKE_NOT_HELD"
	end
	if distance == nil or distance > RANGE then
		return "STRIKE_NO_EFFECT"
	end
	if targetState == nil or targetPlayerState ~= "ALIVE" then
		return "STRIKE_NO_EFFECT"
	end
	if not (exposed and weakened) then
		return "STRIKE_NO_EFFECT"
	end
	return "STRIKE_KILL"
end

local kills = 0

for _, phase in PHASES do
	for _, strikerState in PLAYER_STATES do
		for h = 1, HELD_N do
			local held = HELD[h]
			for d = 1, DIST_N do
				local distance = DISTANCES[d]
				for m = 1, MONSTER_N do
					local targetState = MONSTER_STATES[m]
					for _, targetPlayerState in PLAYER_STATES do
						for _, exposed in BOOLS do
							for _, weakened in BOOLS do
								local verdict = StrikeValidation.evaluate({
									Phase = phase,
									StrikerState = strikerState,
									Held = held,
									TargetDistance = distance,
									TargetState = targetState,
									TargetPlayerState = targetPlayerState,
									TargetExposed = exposed,
									TargetWeakened = weakened,
									Range = RANGE,
								})

								local want = expected(
									phase,
									strikerState,
									held,
									distance,
									targetState,
									targetPlayerState,
									exposed,
									weakened
								)

								check(
									"grid cell",
									verdict == want,
									`{phase}/{strikerState}/{held}/{distance}/{targetState}/`
										.. `{targetPlayerState}/exposed={exposed}/weakened={weakened}: `
										.. `got {verdict}, want {want}`
								)

								--[[
									THE DONE LINE'S OWN SENTENCE, ASSERTED SEPARATELY FROM THE TABLE
									ABOVE. "Kills ONLY if Exposed AND Weakened" is a claim about the
									whole product, not about one cell, and stating it here means a
									future edit to `expected` cannot quietly widen it.
								]]
								if verdict == "STRIKE_KILL" then
									kills += 1
									check(
										"a kill requires both conditions",
										exposed and weakened,
										`STRIKE_KILL with exposed={exposed} weakened={weakened}`
									)
								end
							end
						end
					end
				end
			end
		end
	end
end

--[[
	AND THE GRID MUST CONTAIN KILLS AT ALL.

	Every assertion above is satisfied by a module that returns `STRIKE_NO_EFFECT` unconditionally —
	`expected` would agree with it in 46,000-odd cells and disagree in the rest, so that is caught;
	but a shared misreading of the rule between the module and this file would not be. This is the
	cheap guard against the exact failure §6.5 invariant 1 describes: a second win condition that
	silently does not exist. One kill cell per (phase=ACTIVE, striker=ALIVE, held=BUNTOT_PAGI,
	in-reach distance, non-nil monster state, target ALIVE, both booleans true).
]]
check("the grid reaches STRIKE_KILL somewhere", kills > 0, `kills={kills}`)

--[[
	THE FAIL-CLOSED RANGE CASES, WHICH THE PRODUCT ABOVE CANNOT REACH because it holds `Range` fixed.

	`pure/KillValidation`'s header records that this guard took three attempts and that the first two
	both SHIPPED — a negative range mapping onto the same square, and an infinite one sailing past a
	`> 0` test. This module compares scalars rather than squares so the negative case differs, but the
	infinity and NaN cases are identical and are the reason the guard is a negated conjunction.

	EVERY ONE MUST REFUSE. A degenerate range that GRANTED would let a Config typo kill the Aswang
	from across the barrio; one that refuses produces a buntot pagi that never kills, which
	`tests/config.test.luau` reports loudly.
]]
for _, badRange in { 0, -8, math.huge, 0 / 0 } do
	check("a degenerate range refuses", StrikeValidation.evaluate({
		Phase = "ACTIVE",
		StrikerState = "ALIVE",
		Held = "BUNTOT_PAGI",
		TargetDistance = 1,
		TargetState = "TRANSFORMED",
		TargetPlayerState = "ALIVE",
		TargetExposed = true,
		TargetWeakened = true,
		Range = badRange,
	}) == "STRIKE_NO_EFFECT", `a range of {badRange} granted a strike`)
end

-- A NaN DISTANCE, which `<=` answers false for and which no Config value produces — the distance is
-- measured from two live positions, and a character mid-teleport can hand `.Magnitude` a NaN.
check("a NaN distance refuses", StrikeValidation.evaluate({
	Phase = "ACTIVE",
	StrikerState = "ALIVE",
	Held = "BUNTOT_PAGI",
	TargetDistance = 0 / 0,
	TargetState = "TRANSFORMED",
	TargetPlayerState = "ALIVE",
	TargetExposed = true,
	TargetWeakened = true,
	Range = RANGE,
}) == "STRIKE_NO_EFFECT", "a NaN distance granted a strike")

--[[
	THE INDISTINGUISHABILITY PROPERTY, STATED AS ITSELF RATHER THAN INFERRED FROM THE GRID.

	This is the assertion Phase 1's `Types.StrikeVerdict` header points at when it says adding
	`STRIKE_NOT_EXPOSED` "reds the indistinguishability property". Four worlds involve a target and
	the module must not be able to tell them apart: nobody in reach, a survivor in reach, an Aswang in
	reach that is not Exposed, an Aswang in reach that is Exposed but not Weakened. Every one of them
	returns the SAME value, from an otherwise identical request.

	The grid above would catch a fifth verdict as a mismatch against `expected`. This catches the case
	where someone adds a verdict to BOTH files together — which is exactly how a well-meaning
	afternoon's work removes the mechanic.
]]
local function base(): StrikeValidation.Request
	return {
		Phase = "ACTIVE",
		StrikerState = "ALIVE",
		Held = "BUNTOT_PAGI",
		TargetDistance = 1,
		TargetState = "TRANSFORMED",
		TargetPlayerState = "ALIVE",
		TargetExposed = true,
		TargetWeakened = true,
		Range = RANGE,
	}
end

local nobodyInReach = base()
nobodyInReach.TargetDistance = nil

local survivorInReach = base()
survivorInReach.TargetState = nil
survivorInReach.TargetExposed = false
survivorInReach.TargetWeakened = false

local notExposed = base()
notExposed.TargetExposed = false

local notWeakened = base()
notWeakened.TargetWeakened = false

local outOfReach = base()
outOfReach.TargetDistance = RANGE + 0.001

local worlds: { { Label: string, Request: StrikeValidation.Request } } = {
	{ Label = "nobody in reach", Request = nobodyInReach },
	{ Label = "an Aswang just out of reach", Request = outOfReach },
	{ Label = "a survivor in reach", Request = survivorInReach },
	{ Label = "an Aswang in reach, not Exposed", Request = notExposed },
	{ Label = "an Aswang in reach, Exposed but not Weakened", Request = notWeakened },
}

for _, world in worlds do
	check(
		`{world.Label} is indistinguishable from every other refusal`,
		StrikeValidation.evaluate(world.Request) == "STRIKE_NO_EFFECT",
		`got {StrikeValidation.evaluate(world.Request)}`
	)
end

--[[
	AND THE SPEND LINE IS WHERE THE MODULE SAYS IT IS.

	The three striker-side verdicts are ALLOWED to differ — they describe facts the striker already
	holds. This asserts they actually do, because a module that collapsed THEM too would be safe and
	useless: `ItemService` reads these three by name to decide not to spend, and three worlds sharing
	one value would burn the round's only buntot pagi on a keypress in the lobby.
]]
local wrongPhase = base()
wrongPhase.Phase = "INTERMISSION"
check(
	"wrong phase is its own verdict",
	StrikeValidation.evaluate(wrongPhase) == "STRIKE_WRONG_PHASE"
)

local dead = base()
dead.StrikerState = "DEAD"
check("a dead striker is its own verdict", StrikeValidation.evaluate(dead) == "STRIKE_NOT_ALIVE")

local emptyHanded = base()
emptyHanded.Held = nil
check(
	"an empty hand is its own verdict",
	StrikeValidation.evaluate(emptyHanded) == "STRIKE_NOT_HELD"
)

local holdingSalt = base()
holdingSalt.Held = "SALT"
check(
	"holding the wrong item is its own verdict",
	StrikeValidation.evaluate(holdingSalt) == "STRIKE_NOT_HELD"
)

--[[
	THE STRIKER-SIDE REFUSALS ARE CHECKED BEFORE THE TARGET IS LOOKED AT, which is the ordering that
	makes them safe to distinguish. A `STRIKE_WRONG_PHASE` fired from the lobby must not depend on
	whether anybody happened to be standing nearby, or the three "safe" verdicts become a probe with
	extra steps.
]]
local lobbyNextToTheMonster = base()
lobbyNextToTheMonster.Phase = "INTERMISSION"
local lobbyNextToNobody = base()
lobbyNextToNobody.Phase = "INTERMISSION"
lobbyNextToNobody.TargetDistance = nil
lobbyNextToNobody.TargetState = nil
lobbyNextToNobody.TargetExposed = false
lobbyNextToNobody.TargetWeakened = false
check(
	"a striker-side refusal says nothing about who was nearby",
	StrikeValidation.evaluate(lobbyNextToTheMonster) == StrikeValidation.evaluate(lobbyNextToNobody)
)

--[[
	THE PROPERTY THE CELL-BY-CELL GRID ABOVE CANNOT STATE, AND IT IS THE ONE §4.6 ACTUALLY ASKS FOR.

	"Against anything else it does nothing" is a claim about INDISTINGUISHABILITY, not about a set of
	return values. The grid above proves each cell equals what this file expects; it would keep
	passing if somebody split `STRIKE_NO_EFFECT` into four honest, accurate, correctly-tested
	verdicts — updating `expected` in the same commit — and that change ships an oracle. So the
	property is asserted as a property: over the whole target-side grid, with the striker entitled,
	the set of non-kill outcomes has CARDINALITY ONE.

	The named five-worlds check earlier in this file is the readable version; this is the exhaustive
	one. A future author who adds `STRIKE_TARGET_NOT_WEAKENED` for a good reason turns this red.

	WHY THIS IS NOT PARANOIA. `.claude/lessons/absence-is-observable.md`: "a secrecy leak is a
	DIFFERENCE between players, not a piece of data." A distinct refusal per world IS that difference,
	delivered to whoever asks, once per round for free. The verdict is never echoed today — but the
	union is what a future `FireClient` would carry, and a union that cannot express the difference is
	a union no future author can leak through by accident.
]]
local seen: { [string]: boolean } = {}
local distinct = 0

for d = 1, DIST_N do
	for m = 1, MONSTER_N do
		for _, targetPlayerState in PLAYER_STATES do
			for _, exposed in BOOLS do
				for _, weakened in BOOLS do
					local verdict = StrikeValidation.evaluate({
						Phase = "ACTIVE",
						StrikerState = "ALIVE",
						Held = "BUNTOT_PAGI",
						TargetDistance = DISTANCES[d],
						TargetState = MONSTER_STATES[m],
						TargetPlayerState = targetPlayerState,
						TargetExposed = exposed,
						TargetWeakened = weakened,
						Range = RANGE,
					})

					-- The kill is the one outcome that is SUPPOSED to be distinguishable: the monster
					-- falls over in front of everybody. Every other cell must be one value.
					if verdict ~= "STRIKE_KILL" then
						if not seen[verdict] then
							seen[verdict] = true
							distinct += 1
						end
					end
				end
			end
		end
	end
end

check(
	"a refused strike has exactly one distinguishable outcome",
	distinct == 1 and seen.STRIKE_NO_EFFECT == true,
	`{distinct} distinguishable outcomes; §4.6 allows exactly 1`
)

if failures > 0 then
	error(`{failures} strike-validation failure(s)`)
end

print(`  PASS  strike-validation: {checked} cells`)
