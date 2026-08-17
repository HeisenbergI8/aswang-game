--!strict
--[[
	TrialTimeline — what the Solo Trial fires at second N, as a pure function.

		dueBeats(elapsed, schedule, fired) -> { TrialBeat }   -- beats owed RIGHT NOW, in order
		phaseAt(elapsed, schedule, tasksDone) -> TrialPhase

	WHY A TABLE AND NOT SIX `task.delay` CALLS
	------------------------------------------
	A `task.delay` chain cannot be inspected, cannot be tested from a terminal, and — the part that
	actually bites — cannot be CANCELLED coherently when a round starts under a player mid-trial.
	Six pending delays firing into a session that no longer exists is the shape of a trial reaching
	into a live round, which is the one failure this whole plan is organised against.

	Driven instead off the session's own elapsed time: TrialService ticks, asks what it owes, and
	fires it. A cancelled session simply stops asking, and there is nothing left pending anywhere.

	FIRE-ONCE IS THE CALLER'S SET, NOT THIS MODULE'S STATE. `fired` is passed in and this module holds
	nothing, which is what keeps it pure and what lets the test drive a whole 90 seconds in a loop.

	NO `script.Parent` REQUIRES (tests/README.md). Both unions re-declared; structurally identical to
	their `Types.luau` counterparts.
]]

export type TrialBeat =
	"BEAT_WELCOME"
	| "BEAT_TASKS"
	| "BEAT_SALT_GIVEN"
	| "BEAT_TRANSFORM"
	| "BEAT_SALT_TAUGHT"
	| "BEAT_HANDOFF"

export type TrialPhase = "TRIAL_OFF" | "TRIAL_TASKS" | "TRIAL_CHASE" | "TRIAL_HANDOFF"

-- Mirrors the seconds in Config.Trial. Passed in rather than read, so the test can drive schedules
-- the shipped config does not contain and prove the ordering rules hold for all of them.
export type Schedule = {
	SaltGivenAt: number,
	ScriptedChaseAt: number,
	SaltTaughtAt: number,
	HandoffAt: number,
	Duration: number,
}

local TrialTimeline = {}

--[[
	Beat → the field naming its second. BEAT_WELCOME and BEAT_TASKS are at zero: the trial opens by
	telling you what to do, which is §10's whole complaint about arriving with nothing to do.

	EVERY `beat` CARRIES ITS `:: TrialBeat` AND ALL SIX ARE LOAD-BEARING. Without them Luau infers
	each field as plain `string` from the table literal — the outer annotation does not push the
	literal type inward — and `dueBeats` then returns `{ string }`. The failure lands nowhere near
	here: TrialService's call sites reject it with "none of the union options are compatible", which
	reads as a mismatch between two identical unions rather than as a widening in this file. Same
	bite CLAUDE.md documents for `Enums.RoundPhase.Idle`, one level of nesting deeper.
]]
type Entry = { beat: TrialBeat, at: string? }

local AT: { Entry } = {
	{ beat = "BEAT_WELCOME" } :: Entry,
	{ beat = "BEAT_TASKS" } :: Entry,
	{ beat = "BEAT_SALT_GIVEN", at = "SaltGivenAt" } :: Entry,
	{ beat = "BEAT_TRANSFORM", at = "ScriptedChaseAt" } :: Entry,
	{ beat = "BEAT_SALT_TAUGHT", at = "SaltTaughtAt" } :: Entry,
	{ beat = "BEAT_HANDOFF", at = "HandoffAt" } :: Entry,
}

--[[
	Every beat whose moment has passed and which has not already fired, in schedule order.

	RETURNS A LIST RATHER THAN ONE BEAT, and that is the hitch-tolerance property. A server hitch, or
	a tick interval longer than the gap between two beats, would otherwise silently DROP one — a
	player who never sees BEAT_SALT_GIVEN reaches the chase with no pouch and the tutorial teaches the
	opposite of what §10 asks. Owing two at once is recoverable; losing one is not.
]]
--[[
	RETURNS `{ string }` AND NOT `{ TrialBeat }`, WHICH IS A DELIBERATE WIDENING AT THE BOUNDARY.

	Measured rather than assumed. Inside this module the list genuinely is `{ TrialBeat }` with its
	literals intact — but a LIST of a literal union does not survive `require` across the sourcemap
	the way a scalar does. `phaseAt`'s single `TrialPhase` arrives at TrialService castable in one
	step; this list arrives as a union of six plain `string`s, which Luau then refuses to narrow
	back ("none of the union options are compatible") because no single `string` option is a subtype
	of the literal union. Two-step casts do not rescue it either.

	So the contract says `string` and the caller narrows each element with the ordinary one-step
	`:: Types.TrialBeat` every other pure module in this repo uses. The honesty is in stating the
	widening here rather than in a cast at the call site that looks like a formality and is not.

	What is NOT lost: `AT` below is still typed `{ Entry }`, so a typo in a beat name is still a
	compile error in this file, which is where a beat name is actually written.
]]
function TrialTimeline.dueBeats(
	elapsed: number,
	schedule: Schedule,
	fired: { [string]: boolean }
): { string }
	-- `{ string }` rather than `{ TrialBeat }` because Luau arrays are INVARIANT: the latter is not
	-- assignable to this function's declared return even though every element would be valid.
	local due: { string } = {}

	for _, entry in AT do
		if fired[entry.beat] then
			continue
		end

		local moment = if entry.at == nil then 0 else (schedule :: any)[entry.at] :: number

		-- `>=` so a beat scheduled at 0 fires on the first tick rather than never.
		if elapsed >= moment then
			table.insert(due, entry.beat)
		end
	end

	return due
end

--[[
	The session's own phase, derived rather than stored. Derived for the same reason RoundService
	derives `GateOpen` from the task count (RoundService.luau:629-638): a second piece of state with
	its own writer is a second piece of state that can disagree with the first.

	TASKS DONE BEATS THE CLOCK INTO HANDOFF. A player who finishes both tasks and survives the chase
	is done; making them watch a timer they have already beaten is the static screen §9 item 3 says
	reads as broken.
]]
function TrialTimeline.phaseAt(elapsed: number, schedule: Schedule, tasksDone: boolean): TrialPhase
	if elapsed >= schedule.Duration then
		return "TRIAL_OFF"
	end

	if elapsed >= schedule.HandoffAt then
		return "TRIAL_HANDOFF"
	end

	if elapsed >= schedule.ScriptedChaseAt then
		return "TRIAL_CHASE"
	end

	return if tasksDone then "TRIAL_HANDOFF" else "TRIAL_TASKS"
end

return TrialTimeline
