--!strict
--[[
	REVIEW — src/shared/Enums.luau:1-42 (the whole file; it is 42 lines)
	Read for: V02, which appends four tables to it.
]]

-- The header states the convention V02 must follow: string literals, not numbers.
-- NOTE the file is 42 lines and has exactly four tables. V02 doubles it. The shape below is the
-- shape to copy — a `table.freeze` call, PascalCase keys, UPPER_SNAKE values, a cast on every value.

-- src/shared/Enums.luau:8-11
-- IMPORTANT This comment is the whole reason Phase 2 exists as a separate phase. The casts are not
-- decoration and they are not caught locally — see the note at the bottom of this review.
local Types = require(script.Parent.Types)

-- src/shared/Enums.luau:15-21
-- The reference shape. Note: `table.freeze`, one cast per line, no trailing helper.
Enums.RoundPhase = table.freeze({
	Idle = "IDLE" :: Types.RoundPhase,
	Intermission = "INTERMISSION" :: Types.RoundPhase,
	Starting = "STARTING" :: Types.RoundPhase,
	Active = "ACTIVE" :: Types.RoundPhase,
	Ending = "ENDING" :: Types.RoundPhase,
})

-- src/shared/Enums.luau:28-33
-- NOTE the trailing `--` comments on individual members. V01 used them as tombstones
-- ("V01: killed in-round"), which is the precedent for V02 annotating `MonsterState.Exposed`.
Enums.PlayerState = table.freeze({
	Lobby = "LOBBY" :: Types.PlayerState,
	Alive = "ALIVE" :: Types.PlayerState,
	Dead = "DEAD" :: Types.PlayerState, -- V01: killed in-round. Spectates; the corpse is the body
	Spectator = "SPECTATOR" :: Types.PlayerState, -- joined mid-round
})

-- src/shared/Enums.luau:35-40
-- IMPORTANT STALE UNDER v2.0, AND V02 LEAVES IT ALONE. `SurvivorsEscaped` names the escape gate that
-- §4.6 retired, and there is no member for "survivors killed the Aswang" — the second win condition.
-- §4.7 also flips TIMEOUT's meaning: under v2.0 the clock running out is a survivor WIN.
-- Changing it touches RoundService, XPCurve, BadgeService and RoundEndedPayload, so it is behaviour.
-- See the plan's Follow Ups Q4.
Enums.RoundResult = table.freeze({
	SurvivorsEscaped = "SURVIVORS_ESCAPED" :: Types.RoundResult,
	AswangWins = "ASWANG_WINS" :: Types.RoundResult,
	Timeout = "TIMEOUT" :: Types.RoundResult,
	Aborted = "ABORTED" :: Types.RoundResult, -- e.g. the Aswang disconnected
})

--[[
	IMPORTANT — MEASURED, AND IT IS WHY STEP 2.2'S CHECK IS A GREP RATHER THAN `analyze`.

	An UNCAST literal inside `table.freeze({ ... })` is NOT an analyzer error. `Salt = "SALT"` infers
	as plain `string`, the file compiles, `npm run analyze` stays green, and the failure appears only
	at the first call site that passes it to a parameter typed `Types.ItemType` — which in V02 does
	not exist yet. So a missed cast in this chunk ships silently and detonates in V03+.

	`analyze` proves the complementary half: that `:: Types.ItemType` names a union that EXISTS and is
	spelled right (`Unknown type 'ItemTyp'`). Neither check subsumes the other, which is why Phase 2
	has both.

	QUESTION worth confirming at implementation: does StyLua reflow a `table.freeze({...})` whose
	member line exceeds 100 columns with its cast? The longest V02 line is
	`	BuntotPagi = "BUNTOT_PAGI" :: Types.ItemType,` at ~45 columns, so no — but the MonsterState
	members with trailing comments could approach it.
]]
