--!strict
--[[
	REVIEW — src/shared/Remotes.luau (109 lines)

	Excerpted ranges:
	  · src/shared/Remotes.luau:20-41   EVENTS_DOWN
	  · src/shared/Remotes.luau:43-57   EVENTS_UP
	  · src/shared/Remotes.luau:77-99   getEvent and the eager server-side creation

	This plan adds exactly ONE entry to this file. Everything else it needs was declared at C01.
]]

-- src/shared/Remotes.luau:20-41
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"PlayerKilled",
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"SaltEffect",
	"RoundEnded", -- includes the reveal
}
-- NOTE `SaltEffect` HAS BEEN DECLARED AND UNUSED SINCE C01. Step 4.3 is the first thing to fire it, so
--      this plan adds nothing to the network surface for salt at all.
-- IMPORTANT `PlayerKilled` is declared here with no direction annotation, and `check:remotes` cannot tell
--      FireAllClients from FireClient as a POLICY — both are legal for a down-remote. Step 1.5's change
--      therefore passes every check in this repo whether it is made or not, which is why the plan names
--      the playtester as its evidence.
-- NOTE Step 6.5 inserts `GhostRoster` here, between SaltEffect and RoundEnded, with the longest comment
--      in the list — because its safety is its AUDIENCE rather than its payload, which is the opposite of
--      RoleAssigned's argument two lines up and is the thing a reader will get backwards.

-- src/shared/Remotes.luau:44-57
local EVENTS_UP = {
	"RequestTaskProgress",
	"RequestTimingStop",
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	"RequestKill",
	"RequestThrowSalt",
	"RequestGhostSpook",
}
-- NOTE BOTH HANDLERS THIS PLAN WRITES ARE ALREADY DECLARED, with budgets already in Config. Steps 3.4
--      and 8.4 add code, not surface.
-- IMPORTANT `RequestTimingStop`'s comment (line 46-48) is the design Step 8.4 copies: "NO ARGUMENTS, and
--      that is the whole security design: the server resolves which task from the player's own position...
--      There is no argument in which a client could name a moment, a position or an outcome."
--      `RequestGhostSpook` takes no arguments for the identical reason — the ghost must not name the light.
-- NOTE `RequestThrowSalt` DOES take an argument (a direction) and that is the exception worth
--      understanding: a direction is not a target, a moment or an outcome. The server picks the target
--      from the cone itself, so the client is naming an intent rather than a result.

-- src/shared/Remotes.luau:77-89
local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
		-- ...creates it
	end
	return folder:WaitForChild(name) :: RemoteEvent
end
-- IMPORTANT THE FAILURE `check:remotes` EXISTS FOR, and Step 6.5 is the only place in this plan where it
--      could happen: on the client, `WaitForChild` on a name the server never created HANGS FOREVER — no
--      error, no output, no stack trace, no timeout. A typo like `Remotes.Get("GhostRosters")` typechecks
--      fine and creates a second RemoteEvent on the server, so the server looks healthy while every ghost
--      client is frozen in `Start()`.

-- src/shared/Remotes.luau:91-98
-- Eagerly create on the server so the client's WaitForChild always resolves.
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
end
-- NOTE This is why a declared-but-unused remote costs nothing and why `SaltEffect` sitting idle since C01
--      was harmless. It is also why adding `GhostRoster` to the list is sufficient — no service has to
--      remember to create it.
