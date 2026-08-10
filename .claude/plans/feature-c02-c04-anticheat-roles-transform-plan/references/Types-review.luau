--!strict
--[[
	REVIEW — src/shared/Types.luau

	The four types this plan adds go next to these. Two existing declarations are load-bearing for it.
]]

export type Role = "SURVIVOR" | "ASWANG"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
-- IMPORTANT: FOUR values. This is why Step 6.1/7.2 gates on `== "ALIVE"` (an allowlist) and not on
-- `~= "SPECTATOR"` — a denylist admits LOBBY and GHOST, and C15 makes GHOST real.

--[[
	IMPORTANT — the single most useful thing in this file for this plan. Measured against this repo's
	own analyzer, quoted verbatim:

		· a field of the WRONG TYPE      -> caught
		· a MISSING field                -> caught
		· an EXTRA field                 -> NOT CAUGHT. Silently accepted.

		"That last line is the one that matters, because an extra field is exactly the leak shape...
		 Nothing catches it — `Remotes.Get` returns a plain RemoteEvent so `FireAllClients` takes
		 `...any`, and `RoundEnded` sits on `check-secrecy.mjs`'s REVEAL_ALLOWLIST, so the scanner skips
		 the entire call rather than inspecting its fields."

	`RoleAssigned` is ALSO on that allowlist. So `Types.RoleAssignedPayload` (added in Step 1.3) buys
	exactly the same two thirds of a guard, and the third that is missing is the leak. This is recorded
	as a High-severity Follow Up; C41 is chartered to add the field allowlist that closes it.
]]
export type RoundEndedPayload = {
	Result: RoundResult,
	AswangUserId: number?, -- safe ONLY here: the round is over
	RoundNumber: number,
}

--[[
	NOTE — the contract for what may reach a client. This plan adds NOTHING to it. `YourRole` already
	exists and stays unset; see the RoundService review for C01's reasoning about keeping the number of
	role carriers at one.
]]
export type ClientRoundSnapshot = {
	Phase: RoundPhase,
	SecondsRemaining: number,
	RoundNumber: number,
	TasksCompleted: number,
	TasksRequired: number,
	GateOpen: boolean,
	AlivePlayerCount: number,
	YourRole: Role?, -- only ever the receiving player's OWN role — left unset by RoundService
	YourState: PlayerState,
}

-- QUESTION: `AlivePlayerCount` becomes a death oracle once C15 makes a kill decrement it (BUILD-PLAN's
-- C15 warning). Out of scope for this plan — nothing here changes the alive count — but worth knowing
-- that the snapshot is already carrying a field with a known future problem.
