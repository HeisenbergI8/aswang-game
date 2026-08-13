--!strict
--[[
	REVIEW — src/shared/Types.luau
	Read 2026-08-12 for the C09-C12 plan. Cited ranges below; the file is 295 lines.

	The contract file. Phase 1 adds four types here; Phase 6 writes a field that has existed unused
	since C01.
]]

-- src/shared/Types.luau:14
export type TaskType = "HOLD" | "TIMING" | "FETCH" | "TWO_PERSON"
-- All four already exist. C09 and C10 add no TaskType — they add the BEHAVIOUR behind three that have
-- been declared since the scaffold. NOTE: `Enums.TaskType` (Enums.luau:35-40) carries the matching
-- literal casts, so `Enums.TaskType.Timing` satisfies this union without a cast at the use site.

-- src/shared/Types.luau:49-55
export type ActiveTask = {
	Id: string,
	Type: TaskType,
	SpawnPointName: string,
	Progress: number, -- 0..1
	Completed: boolean,
}
-- IMPORTANT: this plan does NOT widen it. Timing's `BarStartAt`/`Hits` and Fetch's carrier live in
-- parallel server-only tables inside TaskService instead. `ActiveTask` is a SHARED type; adding
-- server-only round state to it would put that state one FireClient away from the wire, and the
-- Aswang's carrier identity is exactly the kind of field that would ride along unnoticed.

-- src/shared/Types.luau:57-80
export type RoundEndedPayload = { Result: RoundResult, AswangUserId: number?, RoundNumber: number }
-- IMPORTANT, and it governs all four of the plan's new payload types:
--   a field of the WRONG TYPE -> caught. A MISSING field -> caught. An EXTRA field -> NOT CAUGHT.
-- That last line is the leak shape. Every new payload in this plan is therefore documented with the
-- fields that must never appear, because the typechecker will not object to them.
-- NOTE: this plan adds NOTHING to this payload. §4.8's survivor win reuses `SURVIVORS_ESCAPED`,
-- which `RoundResult` (:15) already carries.

-- src/shared/Types.luau:218-238
export type TaskProgressVerdict =
	"OK" | "WRONG_PHASE" | "NOT_ALIVE" | "NO_TASK_IN_RANGE" | "ALREADY_COMPLETE"
-- The template Phase 1's `TimingVerdict` copies: a union so the server can log WHY, NEVER echoed to
-- any client, and no safe subset to return.
-- NOTE: its comment has ALREADY been corrected for Amendment A2 ("no verdict names a role") — plan 1
-- did that. Step 7.4 should re-read it and remove any surviving "C12 adds a value meaning you are the
-- Aswang" wording rather than assume it is clean.

-- src/shared/Types.luau:239-268
export type TaskProgressPayload = {
	TasksCompleted: number,
	TasksRequired: number,
	YourTaskProgress: number?,
}
-- IMPORTANT — the sentence that governs Phase 5 more than any other in the repo:
--   "no task's fill is a function of anyone's role, so a frozen bar says 'nobody is holding' and
--    never 'the holder is the Aswang'. Keep it that way."
-- And the specific warning this plan must not trip: "A field named `PresentPlayerCount` would pass
-- every check in this repo and would still be the oracle above." C10 computes a participant count and
-- must NOT put it on this payload. It does not.

-- src/shared/Types.luau:270-280
export type RoundState = {
	Phase: RoundPhase,
	TasksCompleted: number,
	AswangUserId: number?, -- THE SECRET
	GateOpen: boolean,
}
-- IMPORTANT: `GateOpen` has existed since C01 and NOTHING HAS EVER WRITTEN IT TRUE. Phase 6 owns it.
-- NOTE: RoundService's `state` local (RoundService:41-58) mirrors this shape but is not annotated
-- with it — it carries three extra fields (`DealtInSurvivors`, `AswangKills`, `PhaseEndsAt`). So
-- editing this type does not change RoundService, and vice versa. Neither is the other's guard.

-- src/shared/Types.luau:282-293
export type ClientRoundSnapshot = {
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	AlivePlayerCount: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}
-- IMPORTANT: this plan adds NO FIELD here. `GateOpen` is already on it and already rendered by the
-- client (init.client.luau:77 prints "gate OPEN" / "gate shut"), so C11's entire client-facing change
-- is one boolean that finally moves. That is the cheapest possible shape for it and it is not an
-- accident — C01 built the field.
-- NOTE: `YourRole` is deliberately never set by `buildSnapshot`; RoleAssigned is the single
-- allowlisted carrier. Do not start using it for C12's list.
return nil
