--!strict
--[[
	BodyTransitions — what happens to a player's BODY, given their state and what just happened.

		(playerState, cause) -> action

	WHY THIS EXISTS, AND WHY IT IS A TABLE
	--------------------------------------
	`RoundService` was patched five times across four review rounds, and every defect was the same
	shape: one entry point handled and its twin not.

	  · a death by reset was fixed; a death by disconnect was not
	  · a respawn throttle was added that re-stranded the player the previous fix had rescued
	  · a failed load had no retry, because only one caller could ever reach that path

	None of those was a hard problem. They happened because "may this player have a body" lived in
	`pure/PlayerBody` as a RULE, while the TRANSITIONS — grant it, take it away, try again later — were
	scattered across seven call sites of one imperative function, where no reader could see the whole
	set and no test could enumerate it.

	This is the body-side analogue of `pure/RoundTransitions.luau`, which has the same shape (state ×
	event, every cell stated) and has never had a bug. Four states × five causes is twenty cells; the
	test enumerates all twenty, so a combination nobody has hit yet still has a stated answer instead
	of falling through to whatever the last `if` happened to do.

	NO `script.Parent` REQUIRES — Lune has no `script`. PlayerState is re-declared; Luau literal unions
	are structural, so this and `Types.PlayerState` are the same type.

	THIS MODULE DECIDES, IT DOES NOT ACT. It returns a word. `RoundService` owns `LoadCharacterAsync`,
	the `pendingLoads` bookkeeping and the respawn cooldown, because all three touch the DataModel and
	none of them can be tested from a terminal. The decision is the part that kept being wrong, so the
	decision is the part that moved.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

--[[
	The five ways a body's correctness can change. `LOAD_FAILED` is one of them and that is the
	non-obvious entry: a load that throws leaves the player exactly as bodiless as never having asked,
	and treating it as an ordinary cause is what stops it being silently dropped — which it was, for a
	full review round, leaving an ALIVE player unkillable-but-counted for the rest of the round.
]]
export type Cause = "JOINED" | "PHASE_CHANGE" | "KILLED" | "DIED" | "LOAD_FAILED"

--[[
	GRANT   load a character if they do not have one
	REVOKE  take the body away and destroy it
	KEEP    leave whatever they have alone
	DEFER   they should have a body but not yet — schedule it and try again

	DEFER is the rung that did not exist before, and its absence was the permanent-strand bug: a
	throttled respawn returned having neither granted nor revoked, so the player kept a DEAD character,
	and `applyBodyRule`'s load branch is gated on `Character == nil` and therefore never repaired it.
	"Not now" and "not ever" must not be the same answer.
]]
export type Action = "GRANT" | "REVOKE" | "KEEP" | "DEFER"

local BodyTransitions = {}

--[[
	LOBBY and ALIVE only. An allowlist, never `~= "SPECTATOR"`: PlayerState has four values, a denylist
	also admits GHOST.

	GHOST WAS ADMITTED HERE AND HAS BEEN TAKEN BACK OUT. That is worth recording rather than reverting
	quietly, because the reason it was admitted is still true and the reason it was removed is stronger.

	It was admitted because §4.7 needs a ghost to have a POSITION — a ghost flies and holds task points
	at 25%, and `TaskService` measured presence from `player.Character`. Giving them a real character
	was the shortest path to a position.

	It was removed because a server character REPLICATES. Hidden with `Transparency = 1` it is still a
	player-named Model in `workspace` that any client can enumerate, and since the Aswang can never be
	a ghost — their death aborts the round — every ghost body ELIMINATES A CANDIDATE. That is the same
	death oracle Amendment A3 deleted `AlivePlayerCount` to close, in a stronger form: named, and
	timestamped to the frame the body appears. Three separate patch rounds tried to hide the body
	better and each one found new leaks, because hiding a replicated object is not a thing you can win.

	SO THE DEAD KEEP A BODY, AND IT IS THE CORPSE. `MonsterService.makeCorpse` already turns a victim's
	character into an anchored body in the world; it now stays attached as `player.Character` for the rest
	of the round instead of being detached. Every player therefore has a Character at all times, and the
	thing an exploiter can enumerate is a constant.

	What a client CAN still learn is what §4.7 and Amendment A3 always intended: a body lying in the
	Barrio is a dead player, and finding it requires looking at it. Under §5's `StreamingEnabled` (C17) a
	distant corpse does not replicate at all, which is what makes "you learn about a death by finding the
	body" literally true rather than merely intended. **Before C17 it is partial** — everything
	replicates, so a property scan still distinguishes a corpse from a walker. That is a known and stated
	limitation, not a claim of closure.

	A GHOST'S POSITION DOES NOT COME FROM THAT BODY. The corpse stays where they died; the ghost flies.
	The client renders a local body and reports where it is, and `TaskService` reads that for a GHOST.

	`mayBeKilled` never moved through any of this, which is why it was a separate allowlist from C05.
]]
function BodyTransitions.mayHaveBody(state: PlayerState): boolean
	return state == "LOBBY" or state == "ALIVE"
end

--[[
	THE TABLE. Read it as a grid, not as a sequence of conditions.

	The two rows that carry the history:

	  ALIVE/DIED    -> REVOKE. A death inside a round is a death. RoundService then makes them a GHOST,
	                  which also closes reset-to-escape: without it, a cornered survivor could press
	                  Escape and teleport to spawn for free.
	  ALIVE/LOAD_FAILED -> DEFER. The worst cell in the table. An ALIVE player with no body is
	                  unkillable (MonsterService returns early on a nil character) AND still counted by
	                  livingSurvivorCount, which puts §4.8's attrition win permanently out of reach.
]]
function BodyTransitions.actionFor(state: PlayerState, cause: Cause): Action
	--[[
		A GHOST'S BODY IS NOT THIS FUNCTION'S BUSINESS, on any cause. KEEP, always, and the short-circuit
		is above `mayHaveBody` deliberately.

		A dead player's character IS THE CORPSE, and `MonsterService` owns it — it anchored it, it fades
		it, and `clearCorpses` destroys it when the round ends. Every other action here would break that:
		REVOKE would destroy the corpse (deleting the one signal §4.7 and A3 rely on), GRANT would spawn
		a fresh WALKING body for a dead player if the corpse were ever missing, and DEFER would retry
		that spawn forever.

		This is also what keeps `player.Character ~= nil` true for everybody. An audit found that
		removing a ghost's body did not remove the tell, it inverted it: `Character == nil` is one line
		to enumerate and names the dead set exactly, and the Aswang is never in it. Absence is as
		observable as presence, so the fix is that there is no absence.
	]]
	if state == "GHOST" then
		return "KEEP"
	end

	if not BodyTransitions.mayHaveBody(state) then
		-- SPECTATOR is owed nothing. A failed load needs no retry — retrying would loop forever against
		-- a rule that will never say yes.
		return if cause == "LOAD_FAILED" then "KEEP" else "REVOKE"
	end

	if cause == "LOAD_FAILED" then
		return "DEFER"
	end

	-- KILLED and, for ALIVE, DIED both end the body. LOBBY/DIED is the lobby respawn.
	if cause == "KILLED" then
		return "REVOKE"
	end

	if cause == "DIED" then
		return if state == "ALIVE" then "REVOKE" else "GRANT"
	end

	return "GRANT"
end

return BodyTransitions
