--!strict
--[[
	GateEscape — did this player just win the round for the survivors? (§4.8, C11)

		escapes(request) -> boolean

	THE ONE MODULE IN M3 THAT READS A ROLE, AND IT IS ISOLATED FOR EXACTLY THAT REASON.

	Every other rule in this milestone is role-blind by construction — `TaskWeight` proves it,
	`FetchCarry` and `TaskParticipants` inherit it, and Amendment A2 explains at length why a rule
	that varies by role tends to become an oracle. §4.8 nevertheless says *"at least 1 SURVIVOR
	reaches the escape gate"*, and the Aswang walking into an open gate must not end the round in the
	survivors' favour. So one branch is required, and this is it: six lines, one file, one exhaustive
	test, rather than a condition inside a service loop where nobody enumerates it.

	WHAT IT LEAKS, STATED RATHER THAN HOPED AWAY. A bystander who watches a player stand in an open
	gate while the round does NOT end has learned that player is the Aswang. That inference is a
	property of §4.8's rule and no implementation removes it. What the implementation controls is that
	NOTHING ELSE distinguishes the two cases: no refusal is returned, no verdict is sent, no sound is
	played to one player, and the gate looks and behaves identically for everyone. The only observable
	is whether the round ends, which is a fact about the round.

	ALL FOUR CONDITIONS, NOT THREE. Dropping any one of them is a real bug with a plausible cause:

	  · GateOpen  — 5/5 is half of §4.8's rule; without it the gate wins the round at 0/5
	  · Role      — the Aswang wins by kills or by the clock, never by walking out
	  · State     — a GHOST is not "at least 1 survivor". §4.7's ghosts fly, and a flying dead player
	                ending the round is the shape C15 would otherwise ship
	  · Distance  — §4.8 says survivors "must physically reach it"

	NO `script.Parent` REQUIRES and no Vector3 — a scalar distance, computed at the call site, so Lune
	runs this. The two unions are re-declared locally; Luau unions are structural.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"
export type Role = "SURVIVOR" | "ASWANG"

export type Request = {
	GateOpen: boolean,
	PlayerState: PlayerState,
	Role: Role,
	Distance: number,
	Range: number,
}

local GateEscape = {}

function GateEscape.escapes(request: Request): boolean
	return request.GateOpen
		and request.Role == "SURVIVOR"
		and request.PlayerState == "ALIVE"
		and request.Distance <= request.Range
end

return GateEscape
