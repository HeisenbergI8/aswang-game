--!strict
--[[
	REVIEW — src/server/Services/MonsterService.luau (1500 lines)

	The service V06 rewrites the middle of. Excerpts only; every block below carries an annotation and
	a line citation. Read the live file for anything not here.
]]

-- src/server/Services/MonsterService.luau:34-43
-- The seams V05 left for this chunk. `HealFromFeed` is declared, documented and UNWIRED — V06 is the
-- caller it was written for.
--   · `HealFromFeed(userId) -> boolean` — V06, on a COMPLETED feed. Returns whether state existed,
--     never the health. Does not restore camouflage; that is V07's half of §4.3's reward.
-- NOTE  "Returns whether state existed, never the health" is the contract V06 must not widen. A feed
--       that wanted to report "you healed to 75" would need a second copy of the number, which is what
--       this signature exists to prevent.
-- IMPORTANT  V05 wrote "Does not restore camouflage; that is V07's half". V06's job is to make that
--       split STRUCTURAL — one completion path pays both or neither — rather than a note.

-- src/server/Services/MonsterService.luau:143-170
-- The server-only per-Aswang record. V06 adds `Feeding`, `FeedBody`, `FeedEndsAt` and two captured
-- jump values here.
--   Health: number,
--   Exposed: boolean,
--   ExposedGlow: Highlight?,
--   ExposedGeneration: number,
-- IMPORTANT  The header above these fields is the whole secrecy argument for the chunk: "NOT
--       `Humanoid.Health` AND NOT `Humanoid.MaxHealth`. Both are replicated properties… That is the
--       same shape as C04's revert bug and C14's WalkSpeed brand, both of which shipped green."
--       V06 writes `WalkSpeed = 0` onto a living character. It is the same class of property and the
--       same invariant applies, which is why the lock and its restore are their own phase.
-- NOTE  `Health` "SURVIVES A TRANSFORM CYCLE, DIES WITH THE ROUND" — deliberately not reset by
--       `revert()`. V06's deferred revert does not disturb that; the reset is still
--       `onPhaseChanged`'s `table.clear(monsters)` and it is still the only one.

-- src/server/Services/MonsterService.luau:180
local corpses: Folder? = nil
-- IMPORTANT  `bodyKindOf` compares a body's parent against this upvalue, so it must be declared below
--       this line. Combined with `feedDistance` needing `rootOf` (line 818) and `commitKill` needing
--       `beginFeed` (line 902), the whole feed block has exactly one legal position in the file.

-- src/server/Services/MonsterService.luau:510-535
-- The private health mutator every health change goes through.
--   monster.Health = MonsterHealth.apply(monster.Health, event, HEALTH_TUNING)
--   refreshExposedGlow(monster)
-- IMPORTANT  V05's comment on the repaint names V06 by name: "`ApplySaltHit` would work without it —
--       it calls `applyExposed`, which repaints on the way in — but V06's `HealFromFeed` will not: a
--       feed completed inside a live Exposed window would restore 25 health and leave the glow reading
--       the pre-feed value." So the glow is ALREADY handled. V06 adds no repaint of its own.
-- NOTE  "READ, DO NOT CONSTRUCT" — `monsters[userId]`, never `stateFor`. `endFeed` copies this rule
--       for the same reason: a stale timer that constructs re-inserts a departed player's UserId.

-- src/server/Services/MonsterService.luau:621-640
local function revert(player: Player)
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false
	monster.LastRevertedAt = os.clock()
	monster.Generation += 1
-- IMPORTANT  THE EARLY RETURN IS WHY `endFeed` MUST RESTORE THE WALKSPEED ITSELF. At least one exit
--       path reaches `endFeed` after a revert has already happened (the tick's NOT_TRANSFORMED
--       branch, which fires BECAUSE of one) — and on that path this function does nothing at all,
--       including nothing to WalkSpeed.
-- IMPORTANT  `LastRevertedAt` is what both `TransformRules` and `KillValidation` measure KillCooldown
--       from. V06 defers this line by FeedDuration, so the cooldown starts five seconds later than it
--       used to. A balance change, recorded in Config's comment rather than absorbed silently.
-- NOTE  `Generation += 1` is what invalidates the in-flight forced-revert timer. After a feed ends
--       via this function, the 8s timer's generation check fails and it declines — so the
--       `not monster.Feeding` clause V06 adds is only ever load-bearing DURING a feed.

-- src/server/Services/MonsterService.luau:762-772
	task.delay(Config.Monster.MaxTransformTime, function()
		if monster.Generation == generation and monster.Transformed then
			revert(player)
		end
	end)
-- IMPORTANT  THE BUG V06 MUST CLOSE, AND IT IS NOT OBVIOUS FROM THE FEED'S OWN CODE. Transform at
--       t=0, kill at t=7, feed until t=12 — this fires at t=8 and reverts a monster §4.3 requires to
--       stay transformed for five full seconds. Any kill made after t=3 of a transform hits it.
--       V06 adds `and not monster.Feeding`.
-- QUESTION  Should the timer instead be RE-ARMED after a feed ends, so a monster that feeds still
--       gets its full remaining transform? Decided no: `endFeed` reverts unconditionally, so there is
--       no remaining transform to protect. Stated here because "why is nothing re-armed" is the first
--       question a reader will have.

-- src/server/Services/MonsterService.luau:388-410
local function makeCorpse(victimUserId: number, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid ~= nil then
		-- Stop it standing up, walking, or being steered. WalkSpeed 0 is not a balance number.
		humanoid.WalkSpeed = 0
	-- ...
	character.Name = `Corpse_{victimUserId}`
	character.Parent = corpses
-- NOTE  THE PRECEDENT FOR V06'S LOCK, ON THE SAME PROPERTY: "WalkSpeed 0 is not a balance number."
--       `check:config` treats 0 as idiomatic and this line proves it in practice.
-- IMPORTANT  `character.Parent = corpses` is where a body BECOMES a corpse, and it is what
--       `bodyKindOf` reads. The rename is not — matching on `Corpse_{id}` would work today and start
--       lying the moment anything renames a body.
-- NOTE  The Model is MUTATED IN PLACE, not cloned. So `commitKill`'s `victimCharacter` local IS the
--       corpse by the line after this call, which is why `beginFeed` needs no registry to find it.

-- src/server/Services/MonsterService.luau:900-925
local function commitKill(killer: Player, victim: Player, victimCharacter: Model, position: Vector3)
	makeCorpse(victim.UserId, victimCharacter)
	RoundService.MarkKilled(victim, true)
	revert(killer)
-- IMPORTANT  THE LINE V06 REPLACES, AND THE HEADER ABOVE IT CALLS THE ORDER A CONTRACT: "every line
--       here depends on the one above it". `revert(killer)` becomes `beginFeed(killer,
--       victimCharacter)`. The header's step 3 must be rewritten with it — it currently states that
--       this line is where §4.3 step 5's cooldown starts, which stops being true.
-- IMPORTANT  The corpse is made FIRST, so by the time `beginFeed` runs, `bodyKindOf(victimCharacter)`
--       already answers CORPSE and `feedDistance` already resolves. The feed's validation is
--       therefore checking that the server did what it just did — see `beginFeed`'s header for why
--       that is still worth doing.

-- src/server/Services/MonsterService.luau:1105-1114
		Transformed = monster.Announced,
		-- ...
		Cooldown = Config.Monster.KillCooldown,
-- IMPORTANT  `Announced`, NOT `Transformed`, IS WHY A FEED CAN NEVER PRECEDE THE REVEAL OF THE FORM.
--       A kill is impossible until `MonsterTransformed(true)` has gone out to every client, and
--       `commitKill` is the only feed starter. That is the structural answer to "is a feed a derived
--       hint about role" — there is no state in which one is observable before the broadcast that
--       licensed it.
-- NOTE  One of three live `Config.Monster.KillCooldown` readers in this file (also lines 792, 1013).
--       V06 does not delete any of them.

-- src/server/Services/MonsterService.luau:1146-1200
local function onPhaseChanged(phase: Types.RoundPhase)
	-- ...
	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			revert(player)
		end
		clearExposed(userId)
	end
	table.clear(monsters)
-- IMPORTANT  V06 adds `endFeed(userId, "FEED_INTERRUPTED")` at the TOP of this loop body. After it,
--       the `revert` below early-returns for a feeder — `endFeed` already did it. Ordered the other
--       way, a revert would run first and leave `Feeding` true on an entry `table.clear` is about to
--       drop, stranding WalkSpeed 0 on a player standing in the lobby.
-- NOTE  V05's comment here is the template for the argument: `table.clear` "would orphan the
--       Highlight: the state that knows the instance is gone, the instance is still parented to a
--       living character, and nothing will ever destroy it." WalkSpeed is that failure with no
--       instance at all — nothing to destroy, just a number nobody will ever correct.

-- src/server/Services/MonsterService.luau:1281-1286
local function onPlayerRemoving(player: Player)
	clearExposed(player.UserId)
	monsters[player.UserId] = nil
end
-- IMPORTANT  THE EXACT BUG V05 SHIPPED AND AN AUDIT FOUND, IN THE COMMENT ABOVE THIS FUNCTION:
--       nilling the entry "only forgets" what the state did to the world, and
--       `RoundService.onPlayerRemoving` then reparents the character into `workspace.Husks` WITH THE
--       MARK STILL ON IT. MonsterService is index 29 in SERVICE_ORDER and RoundService starts last,
--       so this handler runs FIRST and the husk is built afterwards.
-- IMPORTANT  V06 inherits it verbatim: a feed not ended here becomes a husk with WalkSpeed 0 and
--       jumping disabled, standing in the barrio. `endFeed(player.UserId, nil)` goes above
--       `clearExposed`.

-- src/server/Services/MonsterService.luau:1385-1392
function MonsterService.ApplySaltHit(player: Player)
	revert(player)
	applyHealthEvent(player.UserId, "SALT")
	applyExposed(player)
end
-- IMPORTANT  V06 prepends `endFeed(player.UserId, "FEED_INTERRUPTED")`. BEFORE the revert, not after
--       and not left to the tick: salt landing at t=4.99 of a 5s feed races the deadline otherwise,
--       and §4.3 calls interrupting a feed "a real victory" — one that must not depend on tick
--       alignment.
-- NOTE  `endFeed` calls `revert` itself, so line 1 above then early-returns. Left in place: this
--       function's contract is "revert, damage, expose" and removing its own revert because a callee
--       happens to do it makes the ordering depend on `endFeed`'s internals.
-- NOTE  The header above this function carries the invariant that binds V06's lock: "NO PATH ADDED
--       HERE MAY LEAVE A LIVING PLAYER'S HUMANOID PROPERTIES DIFFERENT FROM EVERY OTHER LIVING
--       PLAYER'S." C14's version cost a permanent WalkSpeed 20 brand with `check:secrecy` green.

-- src/server/Services/MonsterService.luau:1455-1480
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end
		validateAndTransform(player)
	end)
-- NOTE  The shape every handler in this game copies, and the comment above it explains why the
--       Consume must be INLINE: `check-ratelimit.mjs` matches within 1200 characters of the connect
--       site, so a handler guarded 250 lines away reads as unguarded and fails the build.
-- IMPORTANT  V06 ADDS NO HANDLER HERE. There is no `RequestFeed` — the feed is a consequence of a
--       kill (§4.3, "must feed"), so the chunk adds no Consume site and no budget entry. Step 4.2
--       verifies with `npm run check:ratelimit` precisely to state that mechanically.
