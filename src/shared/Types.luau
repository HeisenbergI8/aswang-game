--!strict
--[[
	Types — shared Luau type definitions.

	SECURITY NOTE: PlayerProfile and RoundState live on the SERVER ONLY.
	The Aswang's identity must never be replicated to another client in any
	form — not a tag, not an attribute, not a "hidden" value. Assume every
	client is compromised. See docs/MVP-SPEC.md §6.2.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type Role = "SURVIVOR" | "ASWANG"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
export type TaskType = "HOLD" | "TIMING" | "FETCH" | "TWO_PERSON"
export type RoundResult = "SURVIVORS_ESCAPED" | "ASWANG_WINS" | "TIMEOUT" | "ABORTED"

export type PlayerStats = {
	Rounds: number,
	Survived: number,
	AswangRounds: number,
	AswangWins: number,
	Kills: number,
	TasksDone: number,
}

export type Cosmetics = {
	Owned: { [string]: boolean },
	Equipped: {
		Skin: string,
		Lantern: string,
		DeathFX: string,
	},
}

export type PlayerProfile = {
	SchemaVersion: number, -- versioned from day one; write the migration path
	XP: number,
	Level: number,
	Coins: number,
	Stats: PlayerStats,
	Cosmetics: Cosmetics,
	Daily: {
		LastClaimUTC: number,
		Streak: number,
	},
}

-- A task instance selected for the current round.
export type ActiveTask = {
	Id: string,
	Type: TaskType,
	SpawnPointName: string,
	Progress: number, -- 0..1
	Completed: boolean,
}

-- SERVER ONLY. Never send this table to a client.
export type RoundState = {
	Phase: RoundPhase,
	PhaseEndsAt: number, -- os.clock() timestamp
	RoundNumber: number,
	AswangUserId: number?, -- THE SECRET
	Tasks: { ActiveTask },
	TasksCompleted: number,
	PlayerStates: { [number]: PlayerState }, -- keyed by UserId
	GateOpen: boolean,
}

-- What the client is allowed to know. Note the absence of AswangUserId.
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	AlivePlayerCount: number,
	YourRole: Role?, -- only ever the receiving player's OWN role
	YourState: PlayerState,
}

return {}
