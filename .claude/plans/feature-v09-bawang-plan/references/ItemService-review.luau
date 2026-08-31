--!strict
--[[
	REVIEW — src/server/Services/ItemService.luau (1074 lines at time of reading)

	Excerpts only. Every block below carries an annotation; open the real file for the rest.
	V09 extends this service rather than paralleling it — the carry slot, the placement path and the
	two remote handlers are all here already.
]]

-- src/server/Services/ItemService.luau:26-31
-- The header's own statement of where V08 stopped and V09 begins.
--
-- IMPORTANT: this paragraph becomes FALSE the moment V09 lands, and it is the first thing anyone
-- reads. Step 4.3 rewrites it. A header that describes a service two chunks ago is how a reader
-- concludes bawang is unimplemented and re-implements it.
--[[
	ONE SLOT, THREE ITEM TYPES, NO RECHARGE. `pure/ItemCarry` owns whether a pickup is allowed and
	`pure/ItemThrow` owns whether a throw connects. Bawang and the buntot pagi are CARRIED AND
	DROPPED ONLY in V08 — the doorway block is V09 and the strike is V10, and neither is half-built
	here.
]]

-- src/server/Services/ItemService.luau:68-84
-- The slot. V09 reads it (via pure/GarlicPlacement) and clears it on a successful placement.
--
-- IMPORTANT: the paragraph about the Aswang is the one that binds the whole chunk. The monster
-- fills this table like everybody else, so it can find and place bawang — and is then blocked by
-- its own garlic. A `if isAswang then return end` anywhere in the placement path would be the same
-- bug this comment refuses.
local slot: { [number]: Types.ItemType } = {}

-- src/server/Services/ItemService.luau:454-465
-- `placeItem`'s header, and it names V09 by name.
--
-- IMPORTANT: "must not block a doorway — V09 owns the only thing that is allowed to do that". The
-- VISIBLE garlic part V09 adds must therefore stay `CanCollide = false` like every other item part.
-- A collidable bulb would block EVERYONE, which is a wall rather than a barrier and makes the
-- loyalty test impossible to fail honestly.
--
-- NOTE: V09 does not reuse `placeItem`. It attaches a `Touched` pickup to everything it creates, and
-- placed garlic must not be pickup-able or the placer takes it straight back off the threshold.
-- Hence a separate `placeGarlic` and a separate `PlacedGarlic` tag.
--[[
	ANCHORED AND NON-COLLIDING. It must not be pushed around by characters, must not fall through the
	barrio's greybox floor, and must not block a doorway — V09 owns the only thing that is allowed to
	do that, and doing it accidentally here would half-build garlic with none of its rules.
]]

-- src/server/Services/ItemService.luau:492-503
-- What must never go on an item part.
--
-- IMPORTANT: V09's garlic bulb inherits this verbatim and it is SHARPER here. A dropped item is a
-- thing lying where somebody was; a placed one is a thing placed at a MOMENT, so a `PlacedBy`
-- attribute would be a timestamped record of one player's position, readable by every client, for
-- fifteen seconds.
part.Name = item

-- src/server/Services/ItemService.luau:545-560
-- The Touched pickup's server-side distance re-check, and its own admission of what it does not buy.
--
-- NOTE: V09 inherits this exposure and does not widen it. The client-authoritative-position problem
-- named here is the SAME problem the garlic block faces from the other direction — the server cannot
-- trust a position, which is why Phase 4's breach test compares two positions rather than trusting
-- one, and why it corrects to a position the server SAW rather than to a computed one.
if (part.Position - root.Position).Magnitude > Config.Items.DropPickupRangeStuds then

-- src/server/Services/ItemService.luau:766-790
-- `onPhaseChanged`, and the split V09's barrier sweep copies.
--
-- IMPORTANT: two different sweeps on two different conditions, and the file is explicit that
-- collapsing them is "the mistake that destroyed the winning kill's corpse within a frame of
-- creating it". V09 puts the BARRIERS on the `phase ~= Active` side (a rule still being applied to a
-- player after the round) and the garlic PARTS on the Intermission/Idle side (scenery).
local function onPhaseChanged(phase: Types.RoundPhase)

-- src/server/Services/ItemService.luau:911-925
-- The rate-limit convention, stated as a constraint on where the Consume goes.
--
-- IMPORTANT: `check-ratelimit.mjs` matches within 1200 characters of the `:Connect(`, so
-- `RequestPlaceGarlic`'s Consume must be the FIRST statement inside the connection. A handler that
-- is limited but does it elsewhere reads as unguarded and fails the build.
if not AntiCheatService.Consume(player, "RequestThrowSalt") then

-- src/server/Services/ItemService.luau:968-980
-- The guard that asks `pure/ItemUse` before spending the slot.
--
-- IMPORTANT: this is the line V09's Step 2.3 changes the meaning of. Today `USE_NOT_IMPLEMENTED`
-- catches a bawang mis-press and stops it burning the item. Once bawang returns `USE_PLACE` this
-- guard still refuses (it tests `~= "USE_THROW"`), so the ordering survives the change — but a
-- future edit to `== "USE_NOT_IMPLEMENTED"` would silently start destroying bawang on a mis-press.
if ItemUse.verbFor(slot[player.UserId]) ~= "USE_THROW" then

-- src/server/Services/ItemService.luau:1060-1073
-- The closing rule: there is no tick, and nothing should bring one back.
--
-- IMPORTANT: V09 adds a loop. It is bounded — started by the first placement, stopped when the last
-- barrier expires, so at most `GarlicDuration` seconds sampling ONE player against at most two
-- planes — and the plan states that bound as an exception to be argued rather than assumed. The
-- burn-out itself is `task.delay`, not a poll, precisely because of this paragraph.
--
-- QUESTION: is a bounded loop acceptable under this rule, or should the breach test be driven off
-- `Humanoid.Changed`? The plan takes the position that a 15-second bounded loop is the honest
-- option; an auditor is welcome to disagree, and the alternative is cheap to swap in.
--[[
	THERE IS NO TICK ANY MORE, AND NOTHING SHOULD BRING ONE BACK.
]]
