--!strict
--[[
	RejoinResolve — what does a player become when they arrive mid-round? (§6.4, C15)

		(request) -> PlayerState

	THE BUG THIS CLOSES. C01's `onPlayerAdded` marked EVERY mid-round arrival `SPECTATOR`, including a
	player who was `ALIVE` sixty seconds ago and disconnected. A SPECTATOR is uncounted, gets no body,
	and — since C05's "both alive" rule — cannot be killed. So: hear the transform, Alt-F4, come back,
	and be an invulnerable observer for the rest of the round. Free, repeatable, and a hard counter to
	the entire monster.

	THE RULE SHIPPED HERE IS "STAY AS YOU WERE", NOT "COME BACK A GHOST".
	----------------------------------------------------------------------
	BUILD-PLAN's C15 prescribes resolving a returning player to GHOST. That closes the exploit but
	still pays the quitter: they land with the full ghost feature set — ghost chat, the spook, 25%
	contribution — having never been caught. The rule here is stricter and simpler. A disconnect during
	a live round changes NOTHING about your state. Your body stays in the world as a husk that the
	Aswang can kill. You come back to whatever is true when you come back:

	  · husk untouched  → you were ALIVE, you are ALIVE, you resume the round
	  · husk killed     → you were ALIVE, you died while away, you are a GHOST
	  · never dealt in  → you genuinely just arrived, SPECTATOR until the next draw

	Quitting therefore gains nothing and costs nothing, which is the only version where the DECISION to
	quit is neutral rather than merely unattractive.

	WHAT THIS MODULE DOES NOT AND CANNOT FIX: server-hopping. Roblox does not guarantee a returning
	player the server they left, so a quitter who lands elsewhere never meets their husk at all. The
	husk deters the player who comes back HERE and does nothing about one who comes back ANYWHERE. That
	is a property of the platform, not of this rule, and it should be stated rather than implied away.

	FAIL CLOSED MEANS SPECTATOR, and it is worth naming why that is the safe direction: a SPECTATOR is
	uncounted and unkillable, which is exactly the exploit above — but it is unkillable and *also*
	unable to act, win, or contribute. Resolving a doubtful case to ALIVE would hand a body and a vote
	to someone the server cannot account for. Doubtful cases are rare and losing a round is cheaper
	than laundering one.

	NO `script.Parent` REQUIRES. Both unions are re-declared; Luau unions are structural.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Request = {
	Phase: RoundPhase,
	-- Was this player dealt into the CURRENT round? Populated at STARTING and cleared between rounds.
	-- A player who has never been in this round is not the same as one whose state was lost.
	WasDealtIn: boolean,
	-- The state the server still holds for them, if it kept one. `nil` means the server has no memory
	-- of this player in this round — either they are new, or something dropped it.
	StoredState: PlayerState?,
}

local RejoinResolve = {}

--[[
	ORDER IS FIXED. The phase decides whether a round is even happening before anything about the
	player is consulted, because between rounds every arrival is simply a lobby player and none of the
	rest of this applies.
]]
function RejoinResolve.evaluate(request: Request): PlayerState
	--[[
		NOT UNDERWAY → LOBBY, and note that ENDING counts as underway.

		A player arriving during ENDING must not become LOBBY: the round is still resolving, the reveal
		is on screen, and `setAllPlayerStates` has not run yet. Making them LOBBY would give them a body
		among the corpses and put them in the next `aliveCount()` a phase early.
	]]
	if request.Phase == "IDLE" or request.Phase == "INTERMISSION" then
		return "LOBBY"
	end

	--[[
		NOT DEALT IN → SPECTATOR. This is C01's original rule, and it was never wrong — it was only ever
		applied too widely. Someone who joined the server thirty seconds ago genuinely is a spectator
		until the next draw, and giving them a body would put an uncounted, unkillable player in the
		Barrio, which is the alt-account case `pure/PlayerBody` was written for.
	]]
	if not request.WasDealtIn then
		return "SPECTATOR"
	end

	--[[
		DEALT IN, BUT THE SERVER LOST THEIR STATE → SPECTATOR, not ALIVE.

		Unreachable if `onPlayerRemoving` preserves the entry as designed, and that is exactly why it is
		handled: this branch is what a future edit deleting the preservation would fall into, and it
		should degrade to "cannot act" rather than to "has a body and cannot be accounted for".
	]]
	local stored = request.StoredState

	if stored == nil then
		return "SPECTATOR"
	end

	--[[
		THE RULE ITSELF: whatever they were, they still are.

		A LOBBY stored state is resolved to SPECTATOR rather than returned as-is. It should not be
		reachable for a dealt-in player during a live round — `setAllPlayerStates(Alive)` runs at
		STARTING — but returning LOBBY here would hand a body to someone the round is not tracking,
		which is the one outcome this module exists to prevent.
	]]
	if stored == "LOBBY" then
		return "SPECTATOR"
	end

	-- The cast is CLAUDE.md's documented Luau bite: narrowing a literal union by excluding members
	-- widens the remainder to plain `string`, which then fails to satisfy the declared return type.
	return stored :: PlayerState
end

return RejoinResolve
