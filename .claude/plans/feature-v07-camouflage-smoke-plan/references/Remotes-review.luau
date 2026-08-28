--!strict
--[[
	REVIEW — src/shared/Remotes.luau (324 lines)

	Read for the two directions V07 adds to and for the payload precedents that decide what its two
	new down-remotes may carry.
]]

-- src/shared/Remotes.luau:20-30
local EVENTS_DOWN = {
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned", -- FireClient ONLY, to the one player it concerns. Never FireAllClients
	"PlayerKilled",
	"MonsterTransformed", -- public by design: this is the tell, and broadcasting it is correct
	"SaltEffect",
	"RoundEnded", -- includes the reveal
}
-- IMPORTANT: `RoundEnded` and `RoleAssigned` are the ONLY two remotes allowlisted in
-- `check-secrecy.mjs` to carry the role, each with a written reason. Adding a third requires editing
-- that file, which shows up in review. V07 adds neither — `CamouflageUpdate` and `SmokeBurst` need no
-- allowlisting because neither contains a role, a UserId or a health value.

-- src/shared/Remotes.luau:121-135 (NoiseCue)
-- V04. FireClient, to every player the SERVER has decided is close enough — never FireAllClients.
-- IMPORTANT: THIS IS THE PATTERN `SmokeBurst` COPIES, and the reasoning transfers exactly: "a
-- FireAllClients carrying a position would hand every client a live index of where everybody in the
-- barrio is acting, readable from a compromised client with no exploit beyond listening… a broadcast
-- noise feed is a live map, which is strictly more than the tracker will ever give it".
-- NOTE: the position is quantised to `Config.Noise.CueGridStuds` before it is sent, because noise
-- carries 60 studs — far past what a listener can SEE. V07's smoke send radius (40) is close to its
-- visual radius (18), so an exact centre states nothing the receiver will not watch render. That
-- reasoning EXPIRES if `SmokeCueRadius` is ever raised past visual range; the plan records the
-- dependency at both the Config value and the send site.
-- IMPORTANT: "The payload has no player field of any kind." `SmokeBurstPayload` must not either, and
-- the stakes are higher: smoke is fired ONLY by the Aswang, so a UserId here would be a role
-- broadcast with a location attached.

-- src/shared/Remotes.luau:136-165 (FeedUpdate)
-- V06. FireClient to the ONE player whose feed it is. No broadcast form.
-- IMPORTANT: THIS IS THE PATTERN `CamouflageUpdate` COPIES. Its safety argument is `RoleAssigned`'s —
-- "it is fired to a single player and carries only that player's own business, so the set of clients
-- that learn anything from it is the set of clients that already knew".
-- NOTE: "AND NO HEALTH, IN ANY FORM. §4.6: a health value attached to a player is the reveal." The
-- generalisation V07 needs: no charge count and no reveal flag on `CamouflageUpdatePayload` either.
-- NOTE: the payload deliberately "names no victim and no body" so there is "nothing for a compromised
-- client to log, difference or accumulate". `CamouflageUpdatePayload` carries a verdict and a form —
-- the form is the receiver's own appearance, which every client can see on the model anyway.

-- src/shared/Remotes.luau:167-260 (EVENTS_UP)
local EVENTS_UP = {
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	-- ...
	"RequestSearch", -- V03. NO ARGUMENTS, and the absent argument is the entire security design
	"RequestCancelSearch",
}
-- IMPORTANT: the house rule, stated at `RequestSearch` and worth quoting because V07's two remotes
-- follow it: "the server resolves what a player is standing at from that player's own character
-- position, and the client names nothing". A `RequestCamouflage(form)` would hand a compromised
-- client a PROBE — ask for each of the four forms in turn and read the live ambient population
-- without walking anywhere. A `RequestSmoke(position)` would be a "drop a cloud anywhere" primitive.
-- NOTE: `RequestSearch`/`RequestCancelSearch` are TWO remotes rather than a toggle, because "a toggle
-- desynchronises the moment a packet is dropped". V07 has no exit remote at all: stepping out of the
-- disguise is `RequestTransform`, which already exists and already means "become the monster".

-- src/shared/Remotes.luau:280-300
local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
		-- FindFirstChild, else Instance.new
	end
	return folder:WaitForChild(name) :: RemoteEvent
end
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end
-- IMPORTANT: the server creates every remote EAGERLY at boot so the client's `WaitForChild` always
-- resolves. This is why V07 declares its four remotes in Phase 2, before any handler exists: a client
-- waiting on a name the server never created HANGS FOREVER — no error, no output, no stack trace.
-- NOTE: `Remotes.Up` and `Remotes.Down` are exported, but Lune cannot require this module at all
-- (`game:GetService` at module scope), which is why `tests/anti-cheat-budgets.test.luau` keeps a hand
-- copy of `EVENTS_UP`. V07 must edit both or that suite reds in one direction or the other.
