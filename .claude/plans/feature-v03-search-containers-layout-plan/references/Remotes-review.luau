--!strict
--[[
	REVIEW — src/shared/Remotes.luau:1-12, 20-27, 92-100, 118-136, 175-200
	Read for V03: three remotes are added, and the file's own conventions decide their shape.
]]

--[[
	IMPORTANT — THE RULE, from the header (Remotes.luau:9-11):

	  "RULE: every remote listed here must be rate-limited and fully validated in AntiCheatService /
	   the owning service. The client only ever *requests*."

	And the reason declaring them here is not bookkeeping: on the client, `WaitForChild` on a name the
	server never created HANGS FOREVER — no error, no output, no stack trace. `check:remotes` is the
	only thing between a typo and a client that silently never finishes loading.
]]

local EVENTS_DOWN = { -- :21
	"RoundSnapshot",
	"PhaseChanged",
	"RoleAssigned", -- :24 "FireClient ONLY, to the one player it concerns. Never FireAllClients."
	"PlayerKilled",
	"MonsterTransformed", -- :26 "Public by design: this is the tell, and broadcasting it is correct."
	-- + "SearchUpdate" (Step 2.2). FireClient only. Joins RoleAssigned's category, not
	--   MonsterTransformed's: it is a private answer to one player's request.
}

local EVENTS_UP = { -- :92
	"RequestTransform", -- :93 "The first handler in this repo to consult AntiCheatService."
	"RequestKill",
	"RequestThrowSalt",
	-- + "RequestSearch", "RequestCancelSearch" (Step 2.2). Both argument-free.
}

--[[
	IMPORTANT — THE ARGUMENT-FREE PATTERN IS THIS FILE'S DOMINANT ONE, and every instance states the
	same reason. V03's two requests join it.

	`RequestClaimDaily` (:118-121): "NO ARGUMENTS. The day is `os.time()` on the server, the streak is
	in the profile [...] there is nothing a client could legitimately name, and a claimed timestamp is
	precisely the field that would make the streak forgeable."

	`RequestClaimGroupReward` (:122-133): "THE GROUP ID IS NOT AN ARGUMENT, and that is the security
	design [...] A client-supplied id would let a player name any group they happen to belong to."

	`RequestStartTrial` (:134-142): "There is nothing a client could legitimately name here [...] The
	handler re-runs `shared/pure/TrialAdmission` on every call rather than trusting that C24's button
	was only shown when a trial was actually available — the button is a hint to an honest player,
	never a permission."

	`RequestBuyCosmetic` (:110-116): "THE ABSENT ARGUMENT IS THE SECURITY DESIGN. There is no price in
	this request [...] no path where a client's arithmetic decides what a cosmetic costs."

	V03's version: THE CONTAINER IS NOT AN ARGUMENT. The server resolves the nearest tagged part from
	the player's own character position. A named container would hand a compromised client a PROBE —
	iterate every tagged part (Workspace replicates their names, so the list is free), read the
	verdicts, and learn which are spent and which are occupied without walking anywhere.
]]

--[[
	NOTE — THE ONE CASE THIS FILE MADE FOR A SEPARATE REMOTE RATHER THAN A FLAG (`RequestTrialThrow`,
	Remotes.luau:146-160): "THE TWO WAYS TO FIX IT WERE A NEW REMOTE OR A LOOSER `ItemService`, AND THE
	LOOSER SERVICE IS THE ONE THAT WOULD HAVE HURT [...] This remote costs one budget entry and couples
	nothing."

	V03 reaches the same conclusion for RequestCancelSearch: a toggle on RequestSearch desynchronises
	the moment a packet drops or a token is refused, and the failure mode is a hold that silently never
	completes. Two remotes make each message idempotent. One budget entry, no coupling.
]]

--[[
	IMPORTANT — THE `ProfileUpdated` COMMENT (Remotes.luau:29-60) IS THE WARNING V03'S PAYLOAD MUST
	HEED, and it is the sharpest sentence in the file:

	  "`check-secrecy.mjs` enforces its payload rule ONLY on the two allowlisted remotes (`RoundEnded`,
	   `RoleAssigned`), so a whole-profile payload here would pass `npm run verify` GREEN. Nothing
	   mechanical stops it; this comment is the stop."

	Exactly true of `SearchUpdate`. A future chunk adding `ContainerIndex` "for the HUD" would ship
	green through every check in the repo. `Types.SearchUpdatePayload`'s absent-field list is the only
	stop, which is why it is written at length there rather than summarised.
]]

-- NOTE Mechanics: the server eagerly creates every declared remote at load (:187-194) so the client's
-- WaitForChild always resolves; `Remotes.Get(name)` works on both sides (:197-200). V03 caches
-- `Remotes.Get("SearchUpdate")` in a file-local as ItemService does with `saltEffectRemote`, and calls
-- `Remotes.Get` inline in the two Connect statements — inline is REQUIRED there, because
-- check-secrecy's remote-name resolution cannot see through a variable (its own note at
-- check-secrecy.mjs:231).
