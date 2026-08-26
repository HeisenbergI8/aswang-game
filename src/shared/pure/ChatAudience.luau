--!strict
--[[
	ChatAudience — may this player's message reach that player? (§4.7, C15, V01)

		(senderState, recipientState) -> boolean

	THIS IS THE MOST DANGEROUS RULE IN THE GAME AND IT IS FOUR WORDS LONG: a dead player's words must
	never reach a living one. A dead player watched their own death from eight studs away and usually knows
	exactly who did it. One sentence in a channel a survivor can read does not degrade the round, it
	ENDS it — and it ends every subsequent round too, because the fastest way to win as a survivor
	becomes "wait for someone to die".

	§4.7: "Cannot reveal the Aswang's identity to living players. Enforce server-side; the dead must
	be a separate channel."

	THE ASYMMETRY IS DELIBERATE. The living CAN be heard by the dead. That is not an oversight and it is
	not a leak: the dead hearing the living is the entire reason a dead player stays in the room, which
	is what §4.7 exists to buy. Information flows one way — downward, to the dead — and never back up.

	SPECTATOR IS TREATED AS DEAD-SIDE, and this is a decision rather than a reading of the spec. §4.7
	names the dead. But a SPECTATOR is a mid-round arrival who is not playing and CAN observe: they can
	watch a transform and say a name. Their risk profile is a dead player's, so they get that channel.
	Erring the other way would mean a spectator who witnessed a transform could tell the whole server.

	WHY THIS IS A PREDICATE OVER A BOUNDED DOMAIN AND NOT AN `if` IN A HANDLER. Four states by four
	states is sixteen cells, all enumerable, and `tests/chat-audience.test.luau` enumerates them. A rule
	written inline in a callback gets the case somebody thought of; a grid gets the ones nobody did.
	This repo has already paid for that lesson twice on `KillValidation`.

	NO `script.Parent` REQUIRES. The union is re-declared; Luau unions are structural.

	It is callable by any client and that is fine — it is a sixteen-cell truth table over states the
	client already knows about itself, and the rule is in the spec. Logic is not secret. What a client
	cannot do is APPLY it, because delivery happens on the server.
]]

export type PlayerState = "LOBBY" | "ALIVE" | "DEAD" | "SPECTATOR"

local ChatAudience = {}

--[[
	Whether this player speaks on the living side of the wall.

	AN ALLOWLIST, and the same discipline `pure/PlayerBody` uses: `PlayerState` has four values and a
	denylist (`~= "DEAD"`) would silently admit SPECTATOR, which is the exact cell this module was
	written to close. A fifth state added later defaults to dead-side, which is the safe direction —
	it can hear everything and be heard by nobody who matters.
]]
function ChatAudience.isLivingSide(state: PlayerState): boolean
	return state == "ALIVE" or state == "LOBBY"
end

--[[
	THE RULE. Delivered when the sender is living-side, OR sender and recipient are in the SAME state.

	AN EARLIER VERSION WAS `isLivingSide(sender) or not isLivingSide(recipient)` — a single wall with
	the dead on one side — and an audit caught that it delivered DEAD -> SPECTATOR, which the plan had
	explicitly refused by name. The reasoning it refused it for is worth keeping: a SPECTATOR is a
	mid-round arrival who is not accountable to the round, so handing them the dead channel gives an
	ALT ACCOUNT a live feed from inside it. That is the same exploit `pure/RejoinResolve` closes from
	the other direction, and a rule that closes one and opens the other has not understood either.

	So the dead do not form one bloc. The dead talk to the dead, spectators talk to spectators, and
	neither reaches the living:

	  · ALIVE / LOBBY  -> everyone. Information flows DOWN to the dead, always. This is what keeps a
	    dead player in the room, and §4.7's retention argument is the whole reason the channel exists.
	  · DEAD           -> DEAD only.
	  · SPECTATOR      -> SPECTATOR only.

	The equality term is doing real work rather than being a tidy way to write the same thing: it means
	a fifth PlayerState added later gets its own island by default, reaching nobody it is not identical
	to. That is the safe direction — a new state can be heard by nobody until somebody decides it
	should be.

	The order of the operands is not arbitrary either. `isLivingSide(sender)` first means the common
	case — a living player talking — short-circuits without consulting the recipient at all.
]]
function ChatAudience.shouldDeliver(senderState: PlayerState, recipientState: PlayerState): boolean
	return ChatAudience.isLivingSide(senderState) or senderState == recipientState
end

return ChatAudience
