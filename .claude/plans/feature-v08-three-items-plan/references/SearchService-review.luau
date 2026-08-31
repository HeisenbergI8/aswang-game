--!strict
--[[
	REVIEW — src/server/Services/SearchService.luau (675 lines). Phase 3 connects to it; V08 changes
	nothing inside it.

	V03 built the seam and left it dangling on purpose, with a comment naming V08 as the connector.
	The one hazard is what happens when the connector REFUSES.

	Cited against the file as read on 2026-08-29.
]]

-- src/server/Services/SearchService.luau:62-76
--[[
	V03's Done line is "searching yields items". V08 owns ItemService, the three items and the carry
	... Fires (player, itemId) where itemId is a PLAIN STRING. A BindableEvent's arguments are
	`...any`, so the connector must narrow it — `ContainerLayout.itemAt`-style, with a function and
	not a cast.

	A BindableEvent rather than a direct call for `RoundService.PhaseChanged`'s reason: it lets V08
	connect without V03 knowing anything about it.
]]
SearchService.ItemFound = Instance.new("BindableEvent")
-- IMPORTANT: CREATED AT MODULE SCOPE, NOT INSIDE `Start`. That is what makes it safe for
-- ItemService to connect in its own `Start` even though init.server.luau starts ItemService BEFORE
-- SearchService (init.server.luau:54-67). Do not move it into Start.
-- IMPORTANT: "narrow it with a function and not a cast" is V03's instruction to V08 and Step 3.2
-- follows it — three equality tests against the frozen `Enums.ItemType` before the `:: Types.ItemType`.

-- src/server/Services/SearchService.luau:113-119
function SearchService.TotalItems(): number
	return Config.Items.SaltSpawnCount
		+ Config.Items.GarlicSpawnCount
		+ Config.Items.BuntotPagiSpawnCount
end
-- NOTE: seven items, summed from Config rather than typed, so a V16 tune of any count moves the pool
-- requirement with it. This is already the canonical item count for the round.
-- IMPORTANT: THE PROOF THAT TWO SALT ECONOMIES ARE LIVE TODAY. This seeds 4 salt into containers
-- while ItemService.spawnPouches independently places 4 at SaltSpawn points. Eight in a round where
-- §4.6 says four — and §6.5 invariant 1's assertion reads Config, not the world, so it stays green.

-- src/server/Services/SearchService.luau:236-241
local remaining = {
	Salt = Config.Items.SaltSpawnCount,
	Bawang = Config.Items.GarlicSpawnCount,
	BuntotPagi = Config.Items.BuntotPagiSpawnCount,
}
-- NOTE: the seeding already handles all three types. V08 adds no seeding work at all — the container
-- side of "items come from containers" was finished at V03.
-- NOTE: the field names here are `Bawang`/`BuntotPagi` while the Config keys are `Garlic*`. The
-- vocabulary split is already inside one function. Follow Up 1.

-- src/server/Services/SearchService.luau:283-293
--[[
	WHAT THIS PLAYER HAS FOUND THIS ROUND. Server-only, keyed by UserId, never replicated as a table.

	V03 RECORDS AND GRANTS NOTHING — see `SearchService.ItemFound`. This exists so that V08 has
	somewhere truthful to read from, and so that a playtester can confirm "searching yields items"
	from the server side rather than from a client's word for it.

	A ROSTER OF WHO HOLDS WHAT IS A ROSTER OF WHO CAN ANSWER THE ASWANG, which is `ItemService`'s
	stated reason for keeping `carried` server-side, and §4.5's reason the buntot pagi's carrier
	announces themselves by CHOICE. Never broadcast this, never mirror it onto an attribute.
]]
local foundByPlayer: { [number]: { string } } = {}
-- QUESTION: does this survive V08? It is CUMULATIVE — everything ever found — while
-- ItemService.slot is what is held NOW. They diverge the first time anything is dropped, and two
-- server tables answering "what does this player have" is how a later reader picks the wrong one.
-- Recommend narrowing the comment to "debugging aid, not state" rather than deleting, since deleting
-- weakens V03's own verification story. Follow Up 2.
-- NOTE: its secrecy paragraph is the one ItemService.slot inherits and strengthens.

-- src/server/Services/SearchService.luau:396-439 — completeSearch, abridged
--[[
	Path 1: the hold ran its course. The ONLY path that yields an item.

	`opened` is marked BEFORE the item is read, so that no early return below can leave a container
	both spent and re-searchable. Items belong to the world (§4.4's anti-frustration rule), so a
	...
]]
local item: Types.ItemType? = ContainerLayout.itemAt(current, hold.ContainerIndex)

if item == nil then
	return
end

table.insert(pocket, item)
sendUpdate(player, "SEARCH_OK", item)

-- V08 connects here. V03 connects nothing; see SearchService.ItemFound.
SearchService.ItemFound:Fire(player, item)
-- IMPORTANT: 🔴 THE CRITICAL HAZARD OF THIS PLAN. By the time `ItemFound` fires, the container is
-- ALREADY marked opened and the item has ALREADY left the world. If ItemService's `ItemCarry.evaluate`
-- then returns ITEM_SLOT_FULL, the item is in nobody's slot and in no container. With
-- BuntotPagiSpawnCount = 1, a survivor who searches its container while holding a pouch DELETES THE
-- SECOND WIN CONDITION, silently, by playing honestly.
-- IMPORTANT: Step 3.2's `spillItem` is the fix chosen because it needs no V03 change. The cleaner fix
-- — SearchService asking ItemService whether the player can carry it BEFORE opening the container —
-- reverses the service dependency and is a V03 edit. Brief exploit-auditor on this path by name.
-- NOTE: `sendUpdate(player, "SEARCH_OK", item)` fires to ONE player and already tells them what they
-- found. A spilled item means that message was true about the world and false about their hand;
-- acceptable, since the next snapshot carries YourCarriedItem and corrects it within 0.5s.

-- src/server/Services/SearchService.luau:570-577
-- §4.4: items belong to the world, not to individuals. A container someone else emptied is
-- ...
-- IMPORTANT: §4.4's ANTI-FRUSTRATION RULE, and it is the argument for `spillItem` rather than for
-- destroying a refused item. A player who cannot carry it should find it on the floor where the
-- container was, not discover the game ate it.
