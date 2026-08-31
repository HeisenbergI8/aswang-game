--!strict
--[[
	REVIEW — src/shared/Remotes.luau (429 lines at time of reading)

	V09 adds one entry to each list. The conventions below are what the two new entries must satisfy,
	and each one is a decision that was argued somewhere in this file already.
]]

-- src/shared/Remotes.luau:9-11
-- The file's own rule, and the one V09's up-remote must satisfy at Step 2.4.
--[[
	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]

-- src/shared/Remotes.luau:~250-268 (the `RequestSearch` entry)
-- THE ARGUMENT-FREE CONVENTION, STATED IN FULL. `RequestPlaceGarlic` is this entry with "container"
-- replaced by "doorway", and the third reason is the one that matters.
--
-- IMPORTANT: "it hands a compromised client a PROBE — name every tagged part in turn, read the
-- verdicts, and learn which containers are spent". For garlic the probe reads which DOORWAYS ARE
-- SEALED, delivered to whoever asks — including the one player who most wants to know where the
-- survivors are fortifying. The map's part names are readable by any client because Workspace
-- replicates, so the probe would be trivial to write.
--
-- IMPORTANT: this is also why nothing is returned to the caller on ANY path, including OK.
-- `GARLIC_DOORWAY_TAKEN` echoed back is the probe with a shorter script.
--[[
	THE CONTAINER IS NOT NAMED BY THE CLIENT. The server resolves the nearest `SearchContainer` part
	within `Config.Search.RangeStuds` of that player's OWN character position.
]]
"RequestSearch",

-- src/shared/Remotes.luau:~292-318 (the `RequestDropItem` entry)
-- The same rule for an item rather than a place, and the sharpest statement of the stakes.
--
-- NOTE: "A `RequestDropItem(itemType)` WOULD HAVE BEEN A FREE PROBE AND A FREE DUPLICATOR."
-- `RequestPlaceGarlic` inherits both halves: no item argument (CarryLimit is 1, the server knows what
-- you hold) and no position argument (a client-supplied position would put a barrier anywhere,
-- including across a corridor with no doorway in it).
--
-- IMPORTANT: the closing paragraph — "IT IS NOT A ROLE ORACLE IN EITHER DIRECTION… Nothing is
-- returned to the caller on any path, including OK" — is the one V09's entry restates verbatim.
"RequestDropItem",

-- src/shared/Remotes.luau:~180-205 (the `CamouflageUpdate` entry)
-- THE PRECEDENT FOR AN ASWANG-ONLY DOWN-REMOTE, and the closest thing in the repo to `GarlicBarriers`.
--
-- IMPORTANT: the safety argument is `RoleAssigned`'s — fired to a single player, carrying only that
-- player's own business, so "the set of clients that learn anything from it is the set of clients
-- that already knew". `check-secrecy.mjs` allowlists `RoleAssigned` on that reasoning and
-- `CamouflageUpdate` needs no allowlisting at all because its payload contains no role, no UserId and
-- no health. `GarlicBarriers` is in the same position and for the same reason.
--
-- IMPORTANT: the DIFFERENCE, which V09's entry must name rather than gloss. `FeedUpdate` and
-- `CamouflageUpdate` are REPLIES to that player's own request. `GarlicBarriers` is fired UNPROMPTED,
-- triggered by a survivor's placement. It is the only remote in the game whose recipient is chosen by
-- role rather than by action. The argument still holds — no other client receives it — but it is a
-- new shape and an auditor should be told so explicitly rather than left to notice.
--
-- NOTE: "THE PAYLOAD CARRIES NO CHARGE COUNT… the field would be the obvious place for a later
-- broadcast to grow one, and there is no reason to build the socket." Same reasoning kills a
-- `PlacedBy` or a `DoorwayId` on `GarlicBarrierSpec`.
"CamouflageUpdate",

-- src/shared/Remotes.luau:~207-232 (the `SmokeBurst` entry)
-- The refusal of a broadcast form, and the one condition under which an exact position is safe.
--
-- NOTE: relevant because `GarlicBarriers` also carries positions. It is safe on a STRONGER argument
-- than SmokeBurst's: the recipient can walk to the doorway and look at the garlic bulb, which every
-- client can see. The position states nothing the world does not already replicate.
--
-- IMPORTANT: "a FireAllClients carrying a position hands every client the monster's live location".
-- The inverse applies here — a broadcast `GarlicBarriers` would hand every client, including the
-- Aswang, a live index of where the survivors are fortifying. There is no broadcast form and there
-- must not be.
"SmokeBurst",
