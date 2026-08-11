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

	GHOST returns false and that is deliberate for C05 rather than final: a killed player's character
	becomes the corpse (Step 4.2), so re-spawning them would put two bodies in the world. C15 gives
	ghosts their own body and will change this row — in this file, with this test, which is the point.
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
