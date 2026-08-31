--!strict
--[[
	REVIEW — src/server/Services/ItemService.luau (745 lines)

	The file V08 reworks. Half of it is deleted (the SaltSpawn pool, the pouches, the pickup tick) and
	half survives with one input changed (the throw, the stun, the effect broadcast).

	Excerpts below are cited by line range against the file as read on 2026-08-29.
]]

-- src/server/Services/ItemService.luau:14-22
--[[
	  · pouches spawn at `SaltSpawn` points at STARTING          (C13)
	  · a player walking within PickupRangeStuds picks one up    (C13, no remote — see below)

	THERE IS NO PICKUP REMOTE AND THAT IS A SECURITY DECISION, not an omission. The rule: the server
	resolves what a player is standing at from that player's own character position, and the client
	names nothing.
]]
-- IMPORTANT: the first two bullets describe the economy V08 DELETES. Items come from V03 containers
-- now. The RULE in the third paragraph survives and is quoted by `RequestSearch`'s and
-- `RequestCamouflage`'s declarations in Remotes.luau — V08's `RequestDropItem` inherits it.
-- IMPORTANT: both economies are live in the tree TODAY. `SearchService` seeds 4 salt into containers
-- AND this file spawns 4 pouches at spawn points. Shipping both = 8 pouches, which breaks §6.5
-- invariant 1 with no Config change and nothing to report it.

-- src/server/Services/ItemService.luau:56-59
local carried: { [number]: number } = {}
-- NOTE: a COUNT. V08 replaces it with `slot: { [number]: Types.ItemType }` — §4.6's three items are
-- different mechanics and a count cannot say which one you hold.
-- IMPORTANT: its comment ("a roster of who is holding salt is a roster of who can answer the Aswang")
-- gets SHARPER at V08, not weaker: one entry in the new table is the buntot pagi, and §4.6 makes its
-- carrier a target. Carry the comment across and strengthen it.

-- src/server/Services/ItemService.luau:261-330 — pickupTick, abridged
local function pickupTick()
	-- ...
	local verdict = SaltCarry.evaluate({
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Carried = carried[player.UserId] or 0,
		Limit = Config.Salt.CarryLimit,
	})
	-- ...
	-- ONE PER TICK PER PLAYER. Breaking here rather than continuing means two pouches lying in the
	-- same spot cannot both be taken in one frame by a player whose limit is 1.
end
-- NOTE: this whole function goes. The `SaltCarry.evaluate` CALL SHAPE is what survives, moved into
-- `onItemFound` where `SearchService.ItemFound` fires. The one-per-tick break has no analogue —
-- ItemFound fires once per completed search.
-- IMPORTANT: the `task.wait(0.25)` loop that drives this (:735-741) runs for the life of the server.
-- Nothing in V08 replaces it; Step 4.3's pickup is a `Touched` connection instead.

-- src/server/Services/ItemService.luau:420-448 — applyHit's header, abridged
--[[
	V05 MOVED THE REVERT AND THE REVEAL INTO `MonsterService.ApplySaltHit` ...

	THE ORDER IS THE WHOLE CORRECTNESS OF THIS FUNCTION AND IT SHIPPED WRONG ONCE. The first version
	ran `applyStun` before `ForceRevert` ... `clearStun` restored the CAPTURED value — the TRANSFORMED
	speed, 20 — onto a player who was no longer transformed ... A permanent role brand, readable
	map-wide, with no remote to intercept, with `check:secrecy` green over it.

	THE INVARIANT: no path through this file may leave a living player's WalkSpeed different from
	every other living player's.
]]
local function applyHit(target: Player)
	MonsterService.ApplySaltHit(target)
	applyStun(target)
end
-- IMPORTANT: V08 CHANGES NEITHER LINE. This is the C14 bug story and the invariant it produced, and
-- both are the reason Phase 5's Step 5.4 exists as its own step: static green over this surface
-- meant nothing, and only exploit-auditor found it.
-- NOTE: the stun is salt's alone and stays here. Everything else moved to MonsterService at V05/V06.

-- src/server/Services/ItemService.luau:551-560 — inside resolveThrow
local isTransformedAswang = aswangUserId == candidate.UserId
	and MonsterService.IsTransformed(candidate.UserId)

local verdict = SaltThrow.evaluate({
	-- ...
	Carried = carried[thrower.UserId] or 0,
	TargetIsTransformedAswang = isTransformedAswang,
	Range = Config.Salt.ThrowRange,
	ConeDegrees = Config.Salt.ThrowConeDegrees,
})
-- IMPORTANT: THE ONLY ROLE READ IN THE FILE, and Step 5.4's check is that it stays the only one.
-- The role and the form are ANDed here and nowhere else, so pure/SaltThrow never learns a role
-- exists — which is what lets it live in shared/pure/ and be callable by any client.
-- NOTE: only `Carried` and the two Config paths change at V08.

-- src/server/Services/ItemService.luau:594-612 — the smoke branch
if MonsterService.SmokeBlocks(origin, candidateRoot.Position) then
	continue
end
-- IMPORTANT: DO NOT TOUCH. V07's symmetry — smoke breaks a throw exactly as it breaks a kill, or the
-- Aswang's escape tool becomes a gift to its pursuers. Collapsed into the existing MISS because a
-- `MISS_SMOKE` is produced only when the Aswang has planted a cloud, delivered to a survivor, naming
-- a direction. V08's fifth MISS world joins the same collapse.

-- src/server/Services/ItemService.luau:700-706
-- §4.6: "Once used, it's gone." THE POUCH IS SPENT ON A MISS TOO, and this line sits above the hit
-- branch so that no future early-return can skip it.
carried[player.UserId] = math.max(0, (carried[player.UserId] or 0) - 1)
-- IMPORTANT: THIS LINE IS THE BUG V08 MUST NOT SHIP. At V08 the slot may hold a BAWANG or the
-- BUNTOT_PAGI; pure/ItemThrow returns MISS for both (its fifth world), the guard above lets MISS
-- through, and this line then destroys the round's only win condition on a keypress. The symptom is
-- indistinguishable from an honest miss. Step 4.2 gates it on `ItemUse.verbFor(...) == "USE_THROW"`.

-- src/server/Services/ItemService.luau:715-727 — PlayerRemoving
--[[
	NOTE FOR PHASE 5. The user's disconnect-husk rule preserves a player's STATE across a reconnect,
	and it is an open question whether their CARRY should travel with it ... Revisit when Phase 5
	lands rather than assuming this line is settled.
]]
-- QUESTION → ANSWERED. V08 Step 3.4 settles it: the item goes to the FLOOR at the husk's position.
-- §4.6 already requires that a dead carrier drops the buntot pagi where they fell, so a disconnect
-- that vaporised it would be a better outcome than dying — an incentive to alt-F4. And a carry
-- preserved across a reconnect is a duplication surface on the one item that IS the win condition.

-- src/server/Services/ItemService.luau:728-745 — the throw handler's opening
Remotes.Get("RequestThrowSalt").OnServerEvent:Connect(function(player: Player, direction: unknown)
	if not AntiCheatService.Consume(player, "RequestThrowSalt") then
		return
	end

	if typeof(direction) ~= "Vector3" then
		return
	end
end)
-- IMPORTANT: THE SHAPE Step 4.3's `RequestDropItem` HANDLER COPIES EXACTLY. Consume FIRST, before the
-- argument is even looked at — `check-ratelimit.mjs` matches within 1200 characters of the connect
-- and is by its own admission a proximity tripwire, so a handler limited elsewhere reads as unguarded.
-- NOTE: the `unknown` type on the argument is deliberate and is why the typeof guard cannot be
-- skipped. `RequestDropItem` has no argument at all, so it needs no equivalent.
