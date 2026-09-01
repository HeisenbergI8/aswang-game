--!strict
--[[
	REVIEW — src/server/Services/ItemService.luau (1721 lines)
	Read for V10 planning: the handler shape `RequestStrike` copies, the spend ordering that decides
	Decision B, and the drop path V10 must NOT rebuild.
]]

-- src/server/Services/ItemService.luau:1499-1510 — the handler shape, copied verbatim by Step 3.3
	--[[
		THE RATE LIMIT IS INLINE AND FIRST, copying the throw and drop handlers exactly.
		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`, by its own admission a proximity tripwire —
		so a handler that IS limited but does it elsewhere reads as unguarded and fails the build.
		Consume FIRST, before anything is read.
	]]
	Remotes.Get("RequestPlaceGarlic").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestPlaceGarlic") then
			return
		end
-- IMPORTANT THE 1200-CHARACTER WINDOW IS A REAL CONSTRAINT ON V10'S HANDLER, which is longer than
--           this one. Keep the Consume as the first statement and keep the block comments that
--           follow it short enough that the check still sees the pair, or `check:ratelimit` reds a
--           handler that is correctly guarded.

-- src/server/Services/ItemService.luau:1518-1530 — the log rule, and the echo rule
		--[[
			NOTHING IS RETURNED TO THE CALLER ON ANY PATH, including OK — the throw handler's rule and
			the drop handler's, inherited. `GARLIC_DOORWAY_TAKEN` echoed back would be a free map
			probe ...
		]]
		if verdict ~= "GARLIC_OK" or doorway == nil then
			if Config.Debug.VerboseLogging then
				-- A UserId and a verdict. NEVER the doorway, and never the item: a doorway id beside
				-- a UserId in the log is a record of where a player was standing, written to disk.
				print(`[ItemService] Garlic placement refused for {player.UserId}: {verdict}`)
			end
			return
		end
-- IMPORTANT V10'S SHARPER VERSION OF THE SAME RULE. A strike log that printed the resolved
--           `targetUserId` beside the striker's would be a record of WHO WAS NEAR WHOM, written to
--           disk — and the resolved target is always the Aswang, so it is a role log. The plan's
--           handler prints the striker and the verdict only.

-- src/server/Services/ItemService.luau:1613-1625 — the spend ordering, and Decision B's precedent
			--[[
				§4.6: "Once used, it's gone." THE SALT IS SPENT ON A MISS TOO, and this line sits
				above the hit branch so that no future early-return can skip it. A miss that cost
				nothing would make salt a probe you throw at everyone, which is the thing
				`pure/ItemThrow`'s header refuses.
			]]
			slot[player.UserId] = nil
-- IMPORTANT THIS IS THE ARGUMENT V10 INHERITS, WITH HIGHER STAKES. There is one buntot pagi and it
--           IS the second win condition; and unlike salt, whether the item survived is directly
--           readable off the striker's own HUD (`ClientRoundSnapshot.YourCarriedItem`). So a
--           conditional spend is not merely a probe, it is a probe with a UI.
-- NOTE      V09 CORRECTED THIS ORDERING FOR GARLIC (line 1536-1543): the spend moved BELOW
--           `placeGarlic` because that function had its own early return, so an unconditional spend
--           destroyed a bawang with no barrier. THE CORRECTION DOES NOT APPLY TO V10 — nothing below
--           the strike's spend line can fail. Do not copy the garlic ordering by reflex.

-- src/server/Services/ItemService.luau:1638-1655 — the noise rule
			--[[
				A THROW IS LOUD, AND IT IS EQUALLY LOUD ON A MISS. ... A noise that only fired on OK
				would be an identity probe with a sound instead of a return value: throw a pouch at
				somebody, listen, learn what the verdict refuses to tell you.
			]]
			NoiseService.Emit(player, "ITEM_USE", throwerRoot.Position)
-- IMPORTANT V10 emits the same cue on every SPENT swing. Placed below the spend and above the kill,
--           so a refused swing and a landed one sound alike.

-- src/server/Services/ItemService.luau:679-697 — DECISION C: the drop path already exists
--[[
	⚠️ THE SILENT RETURN ON A MISSING CHARACTER IS THE BUNTOT PAGI'S LAST PATH OUT OF THE SLOT, so it
	WARNS rather than vanishing quietly. `RoundService.onPlayerRemoving` sets `player.Character = nil`
	... this service's `PlayerRemoving` handler runs FIRST — and only because `init.server.luau` lists
	`ItemService` before `RoundService`. That ordering is load-bearing and was undocumented until an
	exploit audit found it.
]]
local function spillItem(player: Player, item: Types.ItemType?)
	-- ... placeItem(item, root.Position)   -- at the root, NO forward offset
end
-- IMPORTANT §4.6'S "DROPS WHERE THE CARRIER FALLS" IS ALREADY BUILT AND IS ITEM-AGNOSTIC. Called
--           from `Humanoid.Died` inside `watchCharacter` (line ~1400) and from
--           `Players.PlayerRemoving` (line ~1468). V10 WRITES NO SECOND DROP PATH — see the plan's
--           Decision C. A second one would be the duplication surface this header warns about, over
--           the one item where duplication is the whole game.
-- NOTE      `placeItem(item, root.Position)` with no forward offset is deliberate and is quoted in
--           the comment above it: "offsetting this one forward would put the item somewhere the
--           carrier was heading rather than where they died, which is the whole beat." That is
--           §4.6's "a corpse in the open with the win condition next to it", already shipped.
-- IMPORTANT THE BOOTSTRAP ORDER IS LOAD-BEARING. If a later chunk reorders `init.server.luau`, every
--           disconnect-while-carrying deletes the buntot pagi and the `warn` is the only report.
--           Worth naming to the exploit auditor as an existing fragility V10 now depends on.
