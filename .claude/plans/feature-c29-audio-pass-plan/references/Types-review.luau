--!strict
--[[
	REVIEW — src/shared/Types.luau (641 lines; read 11-16, 129-148, 398-414, 537-590)

	READ ONLY. C29 adds no type and widens no payload. Reviewed because two payload shapes are the
	entire input surface of the audio controller, and because one comment in here is a standing
	instruction that constrains the plan.
]]

-- src/shared/Types.luau:11-13
export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type Role = "SURVIVOR" | "ASWANG"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
-- NOTE: `AudioCues` re-declares RoundPhase and PlayerState locally (structural unions, same type) and
-- deliberately does NOT know `Role` exists. A pure module with no role parameter cannot produce a
-- per-role difference, which is the security property stated rather than merely intended.

-- src/shared/Types.luau:537-546
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}
-- The contract for what may cross. C29 reads FOUR of these fields — Phase, SecondsRemaining,
-- GateOpen, YourState — and widens nothing.
-- IMPORTANT: `YourRole` is present and the audio controller must never read it. A cue conditioned on
-- the receiver's own role is safe in isolation (they already know), but it is the one line that turns
-- this file from role-blind into role-aware, and every later cue would be written against the
-- precedent. Follow Up 5 records the one case (the Aswang's own heartbeat) worth reopening it for,
-- deliberately, later, with an argument.

-- src/shared/Types.luau:548-575
--[[
	THE FIELD THAT USED TO BE HERE, AND WHY ITS ABSENCE IS LOAD BEARING (Amendment A3, §4.7).
	`AlivePlayerCount: number` ... made it a sub-second global death signal ...
	DO NOT REINTRODUCE IT UNDER ANOTHER NAME. `SurvivorsRemaining`, `DeadCount`, `RosterSize` and a
	`YourState`-derived tally over a roster field are the same oracle wearing different words ...
]]
-- IMPORTANT: a standing instruction, and audio is a plausible way to violate it. A death STINGER
-- audible to everyone would be a zero-latency global death signal in exactly the form this amendment
-- removed — and it would be a natural thing to add during a mix pass ("the kill needs weight").
-- THE PLAN CONTAINS NO DEATH CUE, and that is deliberate rather than an oversight. §4.9's design is
-- that a death is discovered by finding the corpse.

-- src/shared/Types.luau:129-132
export type MonsterTransformedPayload = {
	Character: Model,
	Transformed: boolean, -- true on transform, false on revert
}
-- The heartbeat's and the stinger's entire input. Two fields, no UserId, no position, no role.
-- IMPORTANT: `Character` is a Model reference, so the client already has the object to parent to —
-- no position crosses the wire and none needs to. This is why a ranged cue on the monster costs
-- nothing in secrecy terms while a "you are near" boolean would cost everything.

-- src/shared/Types.luau:403-407
--[[
	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
	table is accepted silently by the typechecker ... A field named `TargetUserId` would pass every
	check in this repo and would name the monster to eight clients.
]]
-- NOTE: not directly in C29's path (no payload is constructed by this plan) but it is the reason the
-- plan's "no new remote, no widened payload" claim is worth stating explicitly in the overview: the
-- typechecker would not have caught a widening, so the absence has to be asserted and reviewed.
