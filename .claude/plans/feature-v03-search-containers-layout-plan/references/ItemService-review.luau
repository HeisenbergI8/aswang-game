--!strict
--[[
	REVIEW — src/server/Services/ItemService.luau:14-22, 46-92, 665-694, 736-747, 784-789
	Read for V03 as the closest existing service: it already owns a tag-driven pool, a phase
	subscription, a tick loop and a rate-limited handler. SearchService is this file's shape applied to
	§4.4. 800+ lines; only what V03 copies or deliberately diverges from is excerpted.
]]

--[[
	IMPORTANT — THE RULE V03'S REMOTE DESIGN IS BUILT ON (ItemService.luau:14-20):

	  "THERE IS NO PICKUP REMOTE AND THAT IS A SECURITY DECISION, not an omission. The rule: the server
	   resolves what a player is standing at from that player's own character position, and the client
	   names nothing. A `RequestPickup(pouchId)` would need a budget, a verdict union, and validation
	   that the named pouch is the one you are standing on — three surfaces bought to replace a distance
	   comparison the server is already positioned to make."

	V03 DOES need a remote — searching is an explicit action with a start and a stop, where pickup is
	a proximity consequence — but it keeps the second half of the rule: RequestSearch carries NO
	container id and the server resolves the nearest tagged part itself. That is what makes the answer
	to "can a client difference the payloads into a layout" structural rather than argued: there is no
	container key in any message, in either direction.
]]

local TAG_SPAWN = "SaltSpawn" -- :46
-- NOTE V03's tag is "SearchContainer", a separate pool. The two must not be merged: salt SPAWNS at
-- SaltSpawn points (V08 will revisit that under the new item economy), and containers are searched.

-- NOTE Rebuilt on every draw rather than cached, "for the reason any tag-driven pool is: C17 will
-- add, move and delete these parts while a server is running, and a cached point is one that can stop
-- existing." V03 copies this AND adds a mid-hold guard: holdDistance returns nil when the part has
-- gone, which releases the hold instead of erroring inside the tick.
local pointsByName: { [string]: BasePart } = {} -- :49

	-- IMPORTANT The `: BasePart?` annotation is load-bearing under --!strict: indexing a
	-- `{ [string]: BasePart }` yields a NON-optional value, so comparing it to nil is a type error
	-- rather than a lookup. V03 hits this twice (discoverPool and holdDistance).
	local existing: BasePart? = pointsByName[instance.Name] -- :80

	-- IMPORTANT "Sorted because `GetTagged`'s order is engine-defined and must not become a hidden
	-- input to a random selection." V03 depends on this MORE than ItemService does: the sort defines
	-- container index -> Name, so without it the index means a different container on every server and
	-- nothing about the layout is reproducible for anyone debugging it.
	table.sort(names) -- :90

	return SearchPool.evaluate(names, Config.Salt.SpawnCount, Config.Salt.PouchPoolSize) -- :92
-- NOTE The precedent for V03's call: evaluate(names, required, expected), both numbers from Config.

--[[
	NOTE — THE PHASE SUBSCRIPTION SHAPE (ItemService.luau:665-680), and the SPLIT V03 copies.

		local function onPhaseChanged(phase: Types.RoundPhase)
			if phase == Enums.RoundPhase.Starting then
				spawnPouches()
			elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
				clearPouches()
			end

			if phase ~= Enums.RoundPhase.Active then
				clearAllEffects()
			end
		end

	The two-tier split is the interesting part and its stated reason transfers exactly: "pouches lying
	on the ground during ENDING are scenery, a glow during ENDING is a mark on a player."

	V03's equivalent: the LAYOUT is torn down only on the way to INTERMISSION/IDLE (it is inert state,
	harmless during ENDING), while HOLDS release on every phase that is not ACTIVE (a hold surviving
	into ENDING would hand someone an item after the round resolved).
]]

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged) -- :694

--[[
	IMPORTANT — CONSUME FIRST, AND WHY IT IS POSITIONAL (ItemService.luau:736-747):

	  "[check-ratelimit matches] within 1200 characters of an `.OnServerEvent:Connect(`, by its own
	   admission a proximity tripwire — so a handler that IS limited but does it elsewhere reads as
	   unguarded and fails the build. Consume FIRST, before the argument is even looked at."

		Remotes.Get("RequestThrowSalt").OnServerEvent
			:Connect(function(player: Player, direction: unknown)
				if not AntiCheatService.Consume(player, "RequestThrowSalt") then
					return
				end

				-- "A remote argument is whatever the client sent. Typed `unknown` rather than `Vector3`
				-- so this line cannot be skipped"
				if typeof(direction) ~= "Vector3" then
					return
				end

	NOTE V03's two handlers take NO argument, so the `unknown` half does not apply — there is nothing
	to validate, which is the point of the remote carrying no container id. The Consume line is
	identical and is Step 3.3's Verify.
]]

	task.spawn(function() -- :784
		while true do
			pickupTick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)
-- NOTE V03's searchTick copies this block and its waiver text verbatim. Three services agreeing on
-- 0.25 is better than a fourth Config key for a scheduler interval that is not a balance knob.

--[[
	QUESTION — V08 OVERLAP. This file already owns salt spawning at SaltSpawn points and a `carried`
	count. V03 finds salt in a CONTAINER and grants nothing, so for one chunk there are two salt
	stories in the tree: pouches on the ground (v1.3, still live) and salt found by searching (v2.0,
	inert). That is a real inconsistency and it is V08's to resolve, not V03's — flagged in the plan's
	Follow Ups. V03 must not start deleting spawnPouches: V01 was the demolition chunk and V08 is the
	rebuild, and a service half-rewritten by a chunk that does not own it is the worst of both.
]]
