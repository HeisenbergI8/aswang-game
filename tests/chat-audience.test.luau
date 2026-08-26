--!strict
--[[
	The dead-chat wall (§4.7, C15, V01) — all sixteen sender x recipient cells.

	ONE CELL IS THE GAME: DEAD -> ALIVE must be false. A dead player watched their own death and usually
	knows who did it; one sentence reaching a survivor ends the round and every round after it, because
	"wait for someone to die" becomes the optimal survivor strategy.

	The rest of the grid exists so that the one cell cannot be fixed into place while a neighbour
	quietly opens. SPECTATOR -> ALIVE is the neighbour: a mid-round arrival who is not playing can still
	watch a transform and say a name, and a denylist written as `~= "DEAD"` admits them while keeping
	the headline cell passing.
]]

local ChatAudience = require("../src/shared/pure/ChatAudience")

type PlayerState = ChatAudience.PlayerState

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "DEAD", "SPECTATOR" }

--------------------------------------------------------------------------------
-- THE CELL THAT ENDS ROUNDS.
--------------------------------------------------------------------------------

check(
	"a DEAD player is never heard by an ALIVE player",
	ChatAudience.shouldDeliver("DEAD", "ALIVE") == false,
	"this is the whole of §4.7's server-side enforcement"
)

check(
	"a SPECTATOR is never heard by an ALIVE player",
	ChatAudience.shouldDeliver("SPECTATOR", "ALIVE") == false,
	"a mid-round arrival can watch a transform too"
)

--------------------------------------------------------------------------------
-- The full 16-cell grid.
--------------------------------------------------------------------------------

local function livingSide(state: PlayerState): boolean
	return state == "ALIVE" or state == "LOBBY"
end

for _, sender in STATES do
	for _, recipient in STATES do
		-- Mirrors the module: living-side reaches everyone, everyone else reaches only their own kind.
		-- The equality term is what keeps DEAD and SPECTATOR from forming one bloc — see the module
		-- header for why an alt-account spectator inside the dead channel is the exploit.
		local expected = livingSide(sender) or sender == recipient
		local got = ChatAudience.shouldDeliver(sender, recipient)

		check(`{sender} -> {recipient} is {expected}`, got == expected, `got {got}`)
	end
end

--------------------------------------------------------------------------------
-- Properties. These survive somebody rewriting the grid's expectations to match a bug.
--------------------------------------------------------------------------------

--[[
	THE WALL, stated as a property: NOTHING that is not living-side may reach ANYTHING that is. Written
	over the state list rather than over the two known-bad pairs, so a fifth PlayerState added later is
	covered the moment it appears in STATES.
]]
do
	local leaks = 0

	for _, sender in STATES do
		for _, recipient in STATES do
			if not livingSide(sender) and livingSide(recipient) then
				if ChatAudience.shouldDeliver(sender, recipient) then
					leaks += 1
				end
			end
		end
	end

	check("no dead-side sender reaches any living-side recipient", leaks == 0, `{leaks} leaks`)
end

--[[
	THE ASYMMETRY, also a property. The living must be heard by the dead — this is the half that keeps
	a dead player in the room, and a "fix" that walls the channel in both directions would pass the
	leak property above while deleting §4.7's entire retention argument.
]]
do
	local blocked = 0

	for _, sender in STATES do
		for _, recipient in STATES do
			if livingSide(sender) and not ChatAudience.shouldDeliver(sender, recipient) then
				blocked += 1
			end
		end
	end

	check("a living-side sender always reaches everybody", blocked == 0, `{blocked} blocked`)
end

-- The dead talk among themselves, or the dead channel is not a channel.
check("a dead player hears another dead player", ChatAudience.shouldDeliver("DEAD", "DEAD") == true)

--[[
	AND A SPECTATOR DOES NOT HEAR THE DEAD. This pair is the cell the plan refused by name and an
	earlier single-wall rule delivered: a SPECTATOR is a mid-round arrival with no stake in the round,
	so a live feed from the dead channel is an alt account watching from inside it. `RejoinResolve`
	closes that exploit from the joining side; this closes it from the listening side.
]]
check(
	"a spectator does NOT hear the dead",
	ChatAudience.shouldDeliver("DEAD", "SPECTATOR") == false
)
check(
	"a dead player does NOT hear a spectator",
	ChatAudience.shouldDeliver("SPECTATOR", "DEAD") == false
)
check(
	"a spectator hears another spectator",
	ChatAudience.shouldDeliver("SPECTATOR", "SPECTATOR") == true
)

-- And the living hear the living, or the general channel is broken.
check("the living hear the living", ChatAudience.shouldDeliver("ALIVE", "ALIVE") == true)
check("a dead player hears the living", ChatAudience.shouldDeliver("ALIVE", "DEAD") == true)

--------------------------------------------------------------------------------
-- isLivingSide is an allowlist, not a denylist.
--------------------------------------------------------------------------------

do
	local permitted = 0

	for _, state in STATES do
		if ChatAudience.isLivingSide(state) then
			permitted += 1
		end
	end

	check(
		"exactly two states are living-side",
		permitted == 2,
		`{permitted} — if this is 3, SPECTATOR was admitted by a denylist`
	)
end

check("DEAD is not living-side", ChatAudience.isLivingSide("DEAD") == false)
check("SPECTATOR is not living-side", ChatAudience.isLivingSide("SPECTATOR") == false)

--------------------------------------------------------------------------------
-- C25. The quick-chat wheel reuses this predicate rather than growing its own.
--------------------------------------------------------------------------------

--[[
	WHY THESE ASSERTIONS ARE HERE AND NOT IN A quick-chat FILE.

	They are not testing quick chat. They are pinning that quick chat's audience rule IS this
	sixteen-cell grid and not a second, subtly different wall — which is the whole reason
	`QuickChatService` calls `shouldDeliver` instead of writing its own condition.

	The value is in WHERE THEY FAIL. If someone edits `shouldDeliver` for a text-chat reason, these
	four lines fail in this file and name quick chat as the other caller, in the same run. A separate
	quick-chat suite would fail too, but a chunk later and without saying why.

	C15's dead-chat rule and C25's are the same rule because they answer the same question — can this
	dead player be heard by that living one — and the answer must not depend on which button was
	pressed. A dead player whose typed message is walled but whose wheel is not has no wall at all.
]]

check(
	"C25: a living player's quick chat reaches the living",
	ChatAudience.shouldDeliver("ALIVE", "ALIVE") == true
)

check(
	"C25: a living player's quick chat also reaches the dead",
	ChatAudience.shouldDeliver("ALIVE", "DEAD") == true
)

check(
	"C25: a dead player's quick chat reaches other dead players",
	ChatAudience.shouldDeliver("DEAD", "DEAD") == true
)

--[[
	THE ONE THAT ENDS ROUNDS IF IT INVERTS. A dead player watched their own death and usually knows who did
	it; one phrase reaching a living player makes "wait for someone to die" the optimal strategy.
	Quick chat makes that cheaper than typing, so this cell matters MORE here than it did at C15.
]]
check(
	"C25: a dead player's quick chat NEVER reaches the living",
	ChatAudience.shouldDeliver("DEAD", "ALIVE") == false
)

-- SPECTATOR is dead-side, so a mid-round arrival cannot relay a transform they watched.
check(
	"C25: a spectator's quick chat never reaches the living",
	ChatAudience.shouldDeliver("SPECTATOR", "ALIVE") == false
)

if failures > 0 then
	error(`{failures} chat-audience assertion(s) failed`, 0)
end

print(`  PASS  chat-audience: {checked} assertions over the full sender x recipient grid`)
