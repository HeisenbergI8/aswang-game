--!strict
--[[
	PlayerBody — may this player have a character right now.

		(playerState) -> boolean

	THE C04 REMNANT, AS A FUNCTION. C01 marks a mid-round joiner SPECTATOR and excludes them from the
	alive count; it gives them no body, so they spawn, walk the Barrio and collide with it. That was
	harmless until C05: once "both alive" gates the kill, an alt account joining mid-round is uncounted
	AND unkillable, standing next to the Aswang taking notes.

	TWO ALLOWLISTS, NOT ONE, AND THEY ARE DIFFERENT SETS. This is the part that is easy to get wrong.

	  · mayHaveBody  — LOBBY and ALIVE. A player waiting in the lobby needs a body to walk around in.
	  · mayBeKilled  — ALIVE, and nothing else. That is C05's "both alive" rule.

	Both are ALLOWLISTS. `state ~= "SPECTATOR"` reads identically today for either one and admits LOBBY
	and GHOST — and C15 makes GHOST real, at which point a dead player is killable again. PlayerState has
	four values; each function names the ones it permits and returns false for everything else, so a
	fifth value added later defaults to the safe answer and shows up in this file's test as a hole.

	NO `script.Parent` REQUIRES. PlayerState is re-declared; Luau literal unions are structural, so this
	type and `Types.PlayerState` are the same type and pass to each other without a cast.

	This module is callable by any client and that is fine — it is a four-row lookup table over a value
	the client already holds about itself (`ClientRoundSnapshot.YourState`). Logic is not secret.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

local PlayerBody = {}

--[[
	Whether the server should load a character for this player.

	GHOST RETURNS FALSE, AND THIS ROW HAS NOW MOVED THREE TIMES. The history is the useful part.

	The C05-era comment predicted C15 would flip it: "C15 gives ghosts their own body and will change
	this row." It did — §4.7 needs a ghost to have a position. An exploit audit flipped it back, because
	a hidden server character still replicates and enumerating it named the dead set. Then a SECOND audit
	found that removing the body did not remove the tell, it INVERTED it: `Character == nil` enumerates
	the dead exactly as well, and the Aswang is never among them. Absence is as observable as presence.

	SO THE ANSWER STOPPED BEING ABOUT THIS PREDICATE. A dead player DOES have a character — the corpse,
	kept attached for the round — but it is not GRANTED by the body rule; `MonsterService` made it and
	owns it. `BodyTransitions.actionFor` short-circuits GHOST to KEEP before ever consulting this
	function, so "may the body rule give a ghost a body" is false while "does a ghost have one" is true.
	Those are different questions and this one answers the first.

	`mayBeKilled` DID NOT MOVE through either flip. That is the whole reason these were two allowlists
	rather than one predicate.
]]
function PlayerBody.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end

--[[
	Whether this player may be the TARGET of a kill (§4.3, "both alive").

	Strictly narrower than mayHaveBody, and the two must never be merged into one predicate. A LOBBY
	player has a body and must not be killable; that is not an edge case, it is every player between
	rounds standing in the plaza.
]]
function PlayerBody.mayBeKilled(state: PlayerState): boolean
	return state == "ALIVE"
end

return PlayerBody
