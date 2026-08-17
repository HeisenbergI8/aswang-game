--!strict
--[[
	REVIEW — src/shared/Types.luau:11-13, 444-450, 464-500

	Read for two things: where C25's new types go, and what Amendment A3's absent field obliges C25 to
	avoid. The second turned out to be the more useful half.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

-- NOTE: `PlayerState` here and `GhostChat.PlayerState` in the pure module are the same structural
-- union declared twice, because a pure module may not require Types. C25's QuickChatService crosses
-- that boundary with a cast, exactly as GhostService already does at GhostService.luau:293-299.

--------------------------------------------------------------------------------
-- Types.luau:444-450 — the verdict shape C25's QuickChatVerdict copies
--------------------------------------------------------------------------------

export type SpookVerdict = "OK" | "WRONG_PHASE" | "NOT_GHOST" | "NO_SPOOKS_LEFT" | "NOTHING_IN_RANGE"

-- NOTE the header above it: "a union so the server can log WHY, and never echoed." C25's
-- QuickChatVerdict follows both halves — and the "never echoed" half is load-bearing, not stylistic.
-- See GhostService-review.luau for the state-oracle argument that made this plan drop an early
-- design where the sender was told why their accusation failed.

--------------------------------------------------------------------------------
-- Types.luau:464-473 — the contract for what may cross
--------------------------------------------------------------------------------

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

-- IMPORTANT: C25 does NOT widen this. The wheel needs nothing from the snapshot that is not already
-- here — `Phase` gates the client-side wheel, `YourState` is the client's own. Had it needed a
-- roster or a count, that would have been a Follow Up decision rather than a field.

--[[
	Types.luau:475-500 — THE ABSENT FIELD, quoted because it is the constraint C25 inherits.

	  "`AlivePlayerCount: number` sat between GateOpen and YourRole ... That made it a sub-second
	   global death signal, and a death signal is an input to an attack this game cannot survive:
	   record replicated character positions, timestamp each kill from the decrement, then ask who was
	   within `Monster.KillRange` (8 studs) of the victim's last known position at that instant."

	  "DO NOT REINTRODUCE IT UNDER ANOTHER NAME. `SurvivorsRemaining`, `DeadCount`, `RosterSize` and a
	   `YourState`-derived tally over a roster field are the same oracle wearing different words, and
	   none of them contains a token `check-secrecy.mjs` matches."

	IMPORTANT — HOW C25 STAYS ON THE RIGHT SIDE OF THIS. Three specific refusals, all of which look
	like reasonable features from the outside:

	  1. NO `SenderState` FIELD on QuickChatBroadcastPayload. A client that wants to render a ghost's
	     message in a different colour already knows: it received the message, and the audience rule
	     is what let it through. Adding the field would state aloud what the routing implies, to
	     recipients who are entitled to it — which sounds harmless until a SPECTATOR receives one.
	  2. NO VERDICT ECHOED to the sender. See above.
	  3. THE ACCUSATION IS THE ONE PLACE C25 TOUCHES THIS REASONING AT ALL, and it is raised in the
	     plan's Follow Up 8 rather than resolved here. `TargetUserId` does attest that a third party
	     was alive at time T. The distinction from A3 is that this signal is VOLUNTARY, ATTRIBUTABLE,
	     and correlated with no death — the sender pays for it with their own position. A3's objection
	     was to an automatic, unattributable signal correlated with a kill.

	QUESTION — for GATE 1, not for implementation: the A3 note says C18's alive-count HUD element
	"has no data source and must not be given one", and points at a diegetic alternative — "a tally
	the quick-chat wheel can assert". THAT IS THIS CHUNK, named in the amendment. C25 as planned does
	NOT build such a tally (there is no "3 of us left" phrase in §4.5's eight). Worth asking whether
	the amendment intended one, because adding a ninth phrase is a design decision and §C22's scope
	warning says the phrase set is fixed at eight.
]]
