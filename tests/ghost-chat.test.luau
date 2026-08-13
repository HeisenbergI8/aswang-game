--!strict
--[[
	The ghost chat wall (§4.7, C15) — all sixteen sender x recipient cells.

	ONE CELL IS THE GAME: GHOST -> ALIVE must be false. A ghost watched their own death and usually
	knows who did it; one sentence reaching a survivor ends the round and every round after it, because
	"wait for someone to die" becomes the optimal survivor strategy.

	The rest of the grid exists so that the one cell cannot be fixed into place while a neighbour
	quietly opens. SPECTATOR -> ALIVE is the neighbour: a mid-round arrival who is not playing can still
	watch a transform and say a name, and a denylist written as `~= "GHOST"` admits them while keeping
	the headline cell passing.
]]

local GhostChat = require("../src/shared/pure/GhostChat")

type PlayerState = GhostChat.PlayerState

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

local STATES: { PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }

--------------------------------------------------------------------------------
-- THE CELL THAT ENDS ROUNDS.
--------------------------------------------------------------------------------

check(
	"a GHOST is never heard by an ALIVE player",
	GhostChat.shouldDeliver("GHOST", "ALIVE") == false,
	"this is the whole of §4.7's server-side enforcement"
)

check(
	"a SPECTATOR is never heard by an ALIVE player",
	GhostChat.shouldDeliver("SPECTATOR", "ALIVE") == false,
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
		-- The equality term is what keeps GHOST and SPECTATOR from forming one bloc — see the module
		-- header for why an alt-account spectator inside the ghost channel is the exploit.
		local expected = livingSide(sender) or sender == recipient
		local got = GhostChat.shouldDeliver(sender, recipient)

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
				if GhostChat.shouldDeliver(sender, recipient) then
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
			if livingSide(sender) and not GhostChat.shouldDeliver(sender, recipient) then
				blocked += 1
			end
		end
	end

	check("a living-side sender always reaches everybody", blocked == 0, `{blocked} blocked`)
end

-- Ghosts talk among themselves, or the ghost channel is not a channel.
check("a ghost hears another ghost", GhostChat.shouldDeliver("GHOST", "GHOST") == true)

--[[
	AND A SPECTATOR DOES NOT HEAR A GHOST. This pair is the cell the plan refused by name and an
	earlier single-wall rule delivered: a SPECTATOR is a mid-round arrival with no stake in the round,
	so a live feed from the ghost channel is an alt account watching from inside it. `RejoinResolve`
	closes that exploit from the joining side; this closes it from the listening side.
]]
check("a spectator does NOT hear a ghost", GhostChat.shouldDeliver("GHOST", "SPECTATOR") == false)
check("a ghost does NOT hear a spectator", GhostChat.shouldDeliver("SPECTATOR", "GHOST") == false)
check(
	"a spectator hears another spectator",
	GhostChat.shouldDeliver("SPECTATOR", "SPECTATOR") == true
)

-- And the living hear the living, or the general channel is broken.
check("the living hear the living", GhostChat.shouldDeliver("ALIVE", "ALIVE") == true)
check("a ghost hears the living", GhostChat.shouldDeliver("ALIVE", "GHOST") == true)

--------------------------------------------------------------------------------
-- isLivingSide is an allowlist, not a denylist.
--------------------------------------------------------------------------------

do
	local permitted = 0

	for _, state in STATES do
		if GhostChat.isLivingSide(state) then
			permitted += 1
		end
	end

	check(
		"exactly two states are living-side",
		permitted == 2,
		`{permitted} — if this is 3, SPECTATOR was admitted by a denylist`
	)
end

check("GHOST is not living-side", GhostChat.isLivingSide("GHOST") == false)
check("SPECTATOR is not living-side", GhostChat.isLivingSide("SPECTATOR") == false)

if failures > 0 then
	error(`{failures} ghost-chat assertion(s) failed`, 0)
end

print(`  PASS  ghost-chat: {checked} assertions over the full sender x recipient grid`)
