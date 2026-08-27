--!strict
--[[
	NoiseModel — what an action costs in noise. (V04, §4.4)

		evaluate(action, state, tuning) -> { Loudness, Radius } | nil
		quantise(position, gridStuds) -> position rounded to a grid cell

	§4.4: "The noise is the entire risk economy. It is the loudest thing a survivor does, and it is
	the thing they must do." This module is the price list. It owns no history, no clock, no Instance
	and no decision about WHEN a noise happens — `NoiseService` decides that, and `server/pure/
	NoiseLog` owns the history.

	WHY `src/shared/pure/` IS SAFE HERE, which is a fair question after V03 put `ContainerLayout` in
	`server/pure/` for the opposite reason. The rule is about INPUTS, not folders. `ContainerLayout`
	is a draw: a client that can guess the seed replays it and knows where the buntot pagi is before
	the round starts. This is a table lookup over numbers `Config.luau` already replicates to every
	client, with no seed and no input a client supplies. A client that requires this module learns
	that searching is loud, which it learns in one round of play. Logic is not secret; inputs are.

	THERE IS NO ROLE PARAMETER AND NO FORM PARAMETER, and that is structural rather than careful:
	with no player and no role in the signature there is no arrangement of this module in which two
	players doing the same thing make different noise. §4.4 requires the Aswang to do everything a
	survivor does sincerely; `.claude/lessons/absence-is-observable.md` is the long version.

	NO `script.Parent` REQUIRES and no Roblox datatypes — `Vec3` is a plain table, converted at the
	call site exactly as `SaltThrow`'s and `KillValidation`'s are.
]]

export type Vec3 = { X: number, Y: number, Z: number }

-- Re-declared rather than imported (no `script` under Lune). Luau unions are structural, so this and
-- `Types.NoiseAction` are the same type and pass to each other without a cast.
export type NoiseAction = "SEARCH" | "ITEM_USE" | "DOOR" | "SPRINT"

export type ActionTuning = {
	Loudness: number,
	Radius: number,
	-- Read by NoiseService's throttle, not by this module. Present so one row describes one action.
	MinInterval: number,
}

-- `Config.Noise` satisfies this structurally. Keyed by plain `string` because a literal union in a
-- table-KEY annotation resolves to plain `string` anyway — the C21 lesson's sixth failed fix.
export type Tuning = {
	Actions: { [string]: ActionTuning },
	SprintSpeedStuds: number,
	CueGridStuds: number,
}

--[[
	THE STATE AXIS, AND IT IS ONE FIELD ON PURPOSE. See the plan's Step 1.3 note: crouch, sneak and
	indoors do not exist in this game, and this field exists only because SPRINT needs a threshold.
	Nil is a legal value and means "not moving, or the caller does not care" — every non-movement
	action ignores it entirely, which the test asserts rather than assumes.
]]
export type State = {
	SpeedStuds: number?,
}

export type Emission = {
	Loudness: number,
	Radius: number,
}

local NoiseModel = {}

-- NaN fails every comparison it is given, so `speed < threshold` would be FALSE for NaN and a NaN
-- speed would emit. Normalised here once rather than guarded at three comparison sites.
local function finiteSpeed(value: number?): number
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end

	return math.max(value, 0)
end

--[[
	WHAT THIS ACTION COSTS, or nil for "no noise at all".

	NIL IS A LEGITIMATE ANSWER AND FAILS CLOSED. An action id with no row is silent rather than
	loud, the same way `AudioCues.isCuePermitted` refuses a cue nobody assigned phases to. The
	parameter is `string` rather than `NoiseAction` so an unknown id is a normal call with a normal
	answer, instead of a type error at a call site that got its id off the wire.
]]
function NoiseModel.evaluate(action: string, state: State, tuning: Tuning): Emission?
	-- `: ActionTuning?` is load-bearing under --!strict: indexing a `{ [string]: ActionTuning }`
	-- yields a NON-optional value, so comparing it to nil is a type error rather than a lookup.
	local entry: ActionTuning? = tuning.Actions[action]

	if entry == nil then
		return nil
	end

	--[[
		THE ONLY BRANCH THAT READS STATE. Movement below the threshold is silent; everything else
		ignores speed completely, so a player who searches while walking makes exactly the noise a
		player who searches standing still makes.

		NO SCALING ABOVE THE THRESHOLD, deliberately: a scaled loudness needs a second number (the
		speed it saturates at) to feed a verb this game does not have. Flat until there is one.
	]]
	if action == "SPRINT" and finiteSpeed(state.SpeedStuds) < tuning.SprintSpeedStuds then
		return nil
	end

	-- Clamped rather than trusted. Config is hand-edited during M12/V16 and a negative radius would
	-- otherwise mean "audible to nobody" in one place and "audible to everybody" in another.
	return {
		Loudness = math.clamp(entry.Loudness, 0, 1),
		Radius = math.max(entry.Radius, 0),
	}
end

--[[
	ROUND A POSITION TO A GRID CELL. What the CUE sends; never what the history stores.

	§4.6 requires the Aswang's information to be an area rather than an address. Without this, a
	client's audio engine localises a searching survivor to within a stud THROUGH A WALL — strictly
	better than V13's late-round 15-stud pulse, which would make V04 obsolete the balance-critical
	chunk of the rewrite before it is written.

	A GRID OF ZERO OR LESS RETURNS THE POSITION UNCHANGED rather than dividing by it. That is the
	unsafe direction, so `tests/config.test.luau` pins CueGridStuds below Tracker.LateRadius and this
	returns something usable instead of erroring inside a dispatch loop.
]]
function NoiseModel.quantise(position: Vec3, gridStuds: number): Vec3
	if gridStuds <= 0 then
		return { X = position.X, Y = position.Y, Z = position.Z }
	end

	return {
		X = math.round(position.X / gridStuds) * gridStuds,
		Y = math.round(position.Y / gridStuds) * gridStuds,
		Z = math.round(position.Z / gridStuds) * gridStuds,
	}
end

return NoiseModel
