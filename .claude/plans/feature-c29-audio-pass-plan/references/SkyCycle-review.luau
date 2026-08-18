--!strict
--[[
	REVIEW — src/shared/pure/SkyCycle.luau (read lines 1-95 and the progressFor signature at 136)

	READ ONLY, but CALLED by the plan: Step 3.4's sunrise cue uses `progressFor`. Also the template
	`shared/pure/AudioCues.luau` is written against — header shape, the no-requires rule, and the
	re-declared union.
]]

-- src/shared/pure/SkyCycle.luau:37-42
--[[
	NO `script.Parent` REQUIRES (tests/README.md), so no Types, no Enums, no Config. `RoundPhase` is
	re-declared — Luau unions are structural, so this and `Types.RoundPhase` are the same type — and
	every tunable arrives as a parameter. There are also NO Color3s anywhere in here ...
]]
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
-- IMPORTANT: `AudioCues` copies this exactly — re-declared `RoundPhase` and `PlayerState`, no
-- requires. Lune has no `script`, so a pure module that reaches for Types is a pure module that
-- cannot be run from a terminal, which is the entire point of putting it here.
-- NOTE: "every tunable arrives as a parameter" is where AudioCues DIVERGES, and deliberately: it
-- holds no numbers at all, so nothing needs to arrive. `src/shared/` is outside `check:config`'s
-- GOVERNED paths (check-config.mjs:33), so a number hidden in a pure module is one the check would
-- never catch — the plan keeps all ten volumes and ranges in `Config.Audio` for that reason.

-- src/shared/pure/SkyCycle.luau:44-49
export type Input = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	Duration: number,
}
-- IMPORTANT: the exact shape the sunrise cue must build (plan Step 3.4). All three fields are already
-- on `ClientRoundSnapshot` or in `Config.Round`, so the cue needs nothing new.

-- src/shared/pure/SkyCycle.luau:136
function SkyCycle.progressFor(input: Input): number
-- Returns 0..1. A SCALAR return, which is the safe kind.
-- NOTE: `.claude/lessons/pure-module-unions-widen-in-lists.md` — a scalar union survives `require`
-- and a LIST of them does not. This module only ever returns numbers and a Frame, so it never met the
-- problem. `AudioCues.oneShotsFor` does return a list, which is why the plan types it `{ string }`
-- and narrows by lookup in the controller.

-- src/shared/pure/SkyCycle.luau:20-26 (behaviour the sunrise cue depends on)
--[[
	  · MONOTONICITY. The sky must never go backwards while a round runs.
	  · THE NIGHT BASELINE IS EXACTLY RECOVERABLE. `frameFor(0, params)` returns the captured night
	    values UNCHANGED — not "close to".
]]
-- src/shared/pure/SkyCycle.luau:135-138 — CONFIRMED, not assumed:
function SkyCycle.progressFor(input: Input): number
	if input.Phase == "ENDING" then
		return 1
	end
-- IMPORTANT: ENDING pins to 1 UNCONDITIONALLY, and IDLE/INTERMISSION/STARTING all return 0
-- (:140-142). Two consequences for the plan's sunrise cue:
--   · a round that ends EARLY (all survivors dead) jumps progress straight past
--     `Config.Audio.SunriseAtProgress` and fires the dawn cue on top of the reveal. The plan allows
--     this by default so the sound agrees with the sky, and flags it for the listen (Step 4.5).
--   · the cue MUST be fire-once keyed on `RoundNumber`, not on the phase: every ENDING snapshot
--     returns 1, so a phase-keyed guard would re-fire on each of the twelve seconds of end screen at
--     `Round.SnapshotInterval` = 0.5s. That is 24 dawn stingers.
-- NOTE: `Duration <= 0` returns 0 rather than dividing (:144-146), so the cue cannot be reached by a
-- NaN. Nothing extra to guard in the controller.
