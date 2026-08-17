--!strict
--[[
	GhostService — Dead players become contributing ghosts (§4.7, C15/C16).

	Milestone: M4
	Spec: docs/MVP-SPEC.md

	§4.7 IS A RETENTION FIX, NOT A FEATURE. "In elimination games, the first person to die is bored for
	6 minutes and leaves." Appendix C's teardown of the closest competitor puts a number on what that
	costs. So a ghost flies, sees other ghosts, holds task points at 25%, and gets one spook — all of
	which exist to keep a dead player in the room rather than in the game.

	THE ONE THING A GHOST MUST NOT DO IS NAME THE ASWANG TO THE LIVING. A ghost watched their own death
	and frequently knows exactly who did it; one sentence in a channel a living player can read ends the
	round instantly. That is enforced server-side in Phase 7, never by a client-side filter.

	NO SERVER BODY FOR GHOSTS, AND THAT IS THE LOAD-BEARING DECISION IN THIS FILE.

	C15 first gave ghosts real characters, because §4.7 needs a ghost to have a position and
	`TaskService` measured presence from `player.Character`. An exploit audit killed that: a server
	character replicates, so a player-named Model per dead player let any client enumerate the dead —
	and since the Aswang can never be a ghost, each one eliminated a candidate. Amendment A3's death
	oracle, wearing a body.

	So the ghost's own CLIENT owns the body. Client-created Instances do not replicate, so a living
	player's machine has no ghost object on it at all — there is nothing to enumerate, nothing to
	fingerprint by transparency, and no raycast question. The client reports its position on
	`ReportGhostPosition`; the server keeps it in `positions` for the two consumers that need it.

	THE HONEST COST: the server is no longer authoritative over where a dead player is. A ghost can
	claim to stand at a task point it is not at and contribute 25% of one player's rate from anywhere.
	It cannot claim to be alive, be seen, kill, be killed, or make the claim at all unless the server
	already believes it is a ghost — and continuity against `FlySpeed` means the lie must be walked
	rather than teleported. Weighed against leaking the identity of the monster, this is not close.

	═══ STILL UNVERIFIED: TEXT CHAT ═══════════════════════════════════════════════

	Plan Step 7.1 specifies a `TextChatService` spike. IT HAS NOT BEEN RUN. The chat wall below is
	written against documented behaviour nobody in this repo has observed, and CLAUDE.md's Hard Rule 1
	is "never guess a Roblox API's behaviour".

	The precedent for why that matters: C07's ProximityPrompt probe found the CoreScript REFUSES to
	render a prompt with no keycode, which invalidated an affordance the plan had already specified.
	That cost one step because it was probed. Unprobed, it would have cost a chunk.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local AntiCheatService = require(script.Parent.AntiCheatService)
local RoundService = require(script.Parent.RoundService)
local TeachingService = require(script.Parent.TeachingService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local GhostChat = require(Shared.pure.GhostChat)
local Remotes = require(Shared.Remotes)
local SpookBudget = require(Shared.pure.SpookBudget)
local Types = require(Shared.Types)

local GhostService = {}

local rosterRemote = Remotes.Get("GhostRoster")

--[[
	WHERE EACH GHOST SAYS IT IS. SERVER-ONLY, keyed by UserId, never sent to any client.

	This table replaces the ghost's server CHARACTER, and the replacement is the whole of the C15
	redesign. A server character replicates: `Transparency = 1` hides pixels, not existence, so a
	player-named Model per dead player let any client enumerate the dead — and because the Aswang can
	never be a ghost, each one eliminated a candidate. That is the death oracle Amendment A3 removed
	`AlivePlayerCount` to close, wearing a body.

	The ghost's own client now builds a LOCAL body (client-created Instances do not replicate to the
	server or to other clients) and reports its position here. The two consumers that ever needed a
	ghost's position — `TaskService`'s presence check and the spook's origin — read this instead.

	`At` is an `os.clock()` stamp, used to bound how far a report may move from the last one and to
	expire a stale entry. A ghost who stops reporting stops contributing, which is correct: no report,
	no claim to be anywhere.
]]
type GhostPosition = {
	Position: Vector3,
	At: number,
}

local positions: { [number]: GhostPosition } = {}

--[[
	Spooks spent this round, keyed by UserId. SERVER-ONLY and never sent anywhere: how many spooks a
	player has left is a fact about a DEAD player, and the set of dead players is precisely the death
	oracle Amendment A3 removed `AlivePlayerCount` to close. The client hides its own button by
	counting its own presses.

	Cleared with the ghosts on every non-ACTIVE phase, so "one per round" means per round rather than
	per server.
]]
local spooksUsed: { [number]: number } = {}

--[[
	THE BODY MACHINERY THAT USED TO LIVE HERE IS GONE, and this note is deliberately left in its place.

	Removed: `applyFlight`, `hideDescendant`, `applyInvisibility`, `makeGhost`, the `ghosted` table and
	the `GhostBody` tag — roughly 130 lines, plus ASSUMPTIONS 1 through 4, which were four unverified
	guesses about Roblox behaviour that the whole feature rested on.

	They existed to give a ghost a POSITION, because `TaskService` measured presence from
	`player.Character`. The cost was that a server character REPLICATES: hidden with `Transparency = 1`
	it was still a player-named Model in `workspace`, enumerable by any client, and since the Aswang can
	never be a ghost, every one of them eliminated a candidate. Three rounds of patching tried to hide
	it better — the tag came off, the root part got its collision back, late-loading accessories got
	caught — and each round found new leaks, because hiding a replicated object is not winnable.

	What replaces it: the ghost's own client builds a LOCAL body and reports its position on
	`ReportGhostPosition`. Client-created Instances do not replicate, so a living client has nothing to
	enumerate — there is no ghost object on their machine at all.

	Deleted along with it: the invisible-collidable-root problem, the floating-name-tag risk, the
	fall-into-the-void respawn loop, and the question of whether `CanQuery = false` keeps a ghost out of
	the kill raycast. None of those can happen to an object that does not exist on the server.
]]

--[[
	THE ROSTER (Step 6.5). Fired to ghosts, and ONLY to ghosts.

	The state test is at the fire site rather than at the payload, because the payload is not what makes
	this safe. A roster of dead UserIds reaching a LIVING client is the death oracle Amendment A3
	removed `AlivePlayerCount` to close — worse, in fact, because it names them rather than counting
	them. `check-secrecy.mjs` cannot see the difference between this loop and one over `GetPlayers()`.

	BUILT ONCE, SENT MANY. Every ghost receives the identical list, so there is no per-recipient payload
	to get wrong — and a ghost seeing itself in its own roster is correct rather than sloppy: the client
	needs to know which body is its own to skip applying a transparency modifier to it.
]]
local function broadcastRoster()
	local userIds: { number } = {}

	for _, player in Players:GetPlayers() do
		if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
			table.insert(userIds, player.UserId)
		end
	end

	local payload: Types.GhostRosterPayload = { UserIds = userIds }

	for _, player in Players:GetPlayers() do
		-- THE TEST THAT MATTERS, and it is re-read per recipient rather than cached from the loop
		-- above: a player who died between building the list and sending it must still be excluded
		-- from neither, and one who is alive must receive nothing at all.
		if RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost then
			rosterRemote:FireClient(player, payload)
		end
	end
end

--[[
	Both tables are round-scoped. A position from last round is a claim about a place a dead player no
	longer is, and a spent spook must not follow its owner into the next round.
]]
local function clearGhosts()
	table.clear(positions)
	table.clear(spooksUsed)
end

--------------------------------------------------------------------------------
-- The spook (§4.7, C16). One per round, and it carries no information.
--------------------------------------------------------------------------------

--[[
	WHERE THE SPOOK HAPPENS IS THE SECURITY DECISION, not whether it happens.

	The obvious implementation — flicker the light NEAREST the ghost — is a leak. A living player who
	sees a light flicker learns roughly where a dead player is standing, and a dead player standing
	beside the Aswang is exactly the leak §4.7's last bullet is about. §4.7 says the spook carries "no
	information", and that sentence has to be enforced here or it is decoration.

	So: a uniformly random point on a circle of radius up to `Config.Ghost.SpookRangeStuds` (30) around
	the ghost, which is comfortably larger than both `Monster.KillRange` (8) and
	`Tasks.PresenceRangeStuds` (9). "Something rustled near me" therefore narrows nothing a living
	player could act on, and `tests/config.test.luau` pins that relationship so a balance pass cannot
	quietly shrink it into a locator.

	`Random.new()` UNSEEDED, deliberately, for the reason CLAUDE.md gives: a seeded draw is reproducible
	by anyone who can guess the seed, and `os.time()` is client-observable to the second.
]]
local spookRng = Random.new()

local function spookOrigin(userId: number): Vector3?
	--[[
		READS THE REPORTED POSITION, not a character — ghosts no longer have one on the server.

		STALENESS IS CHECKED rather than assumed. A ghost who stopped reporting (alt-tabbed, dropped,
		or stopped running the controller) has no current claim to be anywhere, and spooking from a
		position they left thirty seconds ago would put the effect somewhere nobody is. Two report
		intervals is the tolerance; beyond that the spook is refused and the budget is not spent.
	]]
	local entry = positions[userId]

	if entry == nil or os.clock() - entry.At > Config.Ghost.RosterInterval * 2 then
		return nil
	end

	local angle = spookRng:NextNumber() * math.pi * 2 -- config-ok: a full circle, not a knob
	local distance = spookRng:NextNumber() * Config.Ghost.SpookRangeStuds

	return entry.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

--------------------------------------------------------------------------------
-- Ghost chat (§4.7, C15). THE SECRECY SURFACE.
--------------------------------------------------------------------------------

--[[
	═══ THIS IS THE PART OF THE MILESTONE MOST LIKELY TO BE WRONG ═══════════════

	Plan Step 7.1 specifies a five-question `TextChatService` spike. IT HAS NOT BEEN RUN. Everything
	below is written against DOCUMENTED behaviour that nobody here has observed, and a wrong assumption
	does not degrade this feature — it ends rounds. Treat every `ASSUMPTION` as unproven.

	THREE LAYERS, ALL NOW IMPLEMENTED. A previous version of this comment described only two and said
	the whisper hole was open; both were true when written and are false now, and the block is replaced
	rather than edited because a stale claim on a secrecy surface is worse than no claim. (This repo has
	done this before — commit 2175339, "correct three comments the exploit audit found false".)

	  1. `removeFromLivingChannels` destroys the ghost's TextSource in every non-ghost channel. This is
	     the half that leaks BY DEFAULT: Roblox auto-adds everyone to `RBXGeneral`, so its absence is not
	     a bug that has to happen.
	  2. A dedicated `Ghosts` channel, so the dead have somewhere to talk.
	  3. `ShouldDeliverCallback` on EVERY channel — existing ones plus `TextChannels.ChildAdded`, which
	     covers whispers (`RBXWhisper:<id>` is created on demand) and closes the attachment race. It
	     consults live `PlayerState` rather than channel membership, because membership is a cache of
	     state and the bug class here is the two disagreeing.

	⚠️ AN OPEN QUESTION LAYER 1 RAISES, not yet answered: if `TextSource` children are replicated, then
	destroying a ghost's source makes `RBXGeneral:GetTextSource(userId)` return nil for exactly the dead
	— which would publish the dead set through the very mechanism meant to protect it. That is spike
	question 6 and it is UNRUN. If it turns out to be visible, layer 1 must become "revoke CanSend"
	rather than "remove the source": same enforcement, no observable delta.

	DO NOT TREAT GHOST CHAT AS ENFORCED UNTIL THESE ARE CLOSED AND STEP 7.1's SPIKE HAS RUN.

	WHY THE CALLBACK READS STATE RATHER THAN MEMBERSHIP. Membership is a cache of state. The whole
	class of bug here is the two disagreeing, so the enforcement point must consult the source.

	A LIVING PLAYER'S MESSAGE STILL REACHES GHOSTS, deliberately — §4.7's asymmetry. Information flows
	down to the dead and never back up. See `pure/GhostChat`'s header.

	WHAT NO CHECK IN THIS REPO PROVES. `check:secrecy` is a text tripwire on attributes, tags and
	remote payloads; chat delivery is none of those. `tests/ghost-chat.test.luau` proves the PREDICATE
	over all sixteen cells and proves nothing about whether this file calls it correctly, whether the
	callback fires, or whether Roblox honours its return value. That claim needs three clients: a ghost
	sends, and TWO living clients' chats are screenshotted NOT containing it, plus one ghost client's
	chat screenshotted CONTAINING it. Two negatives and a positive — a negative alone is also what a
	broken chat system looks like.
]]
local GHOST_CHANNEL_NAME = "Ghosts"

local ghostChannel: TextChannel? = nil

local function stateOfSpeaker(textSource: TextSource?): Types.PlayerState?
	if textSource == nil then
		return nil
	end

	local player = Players:GetPlayerByUserId(textSource.UserId)

	if player == nil then
		return nil
	end

	return RoundService.GetPlayerState(player)
end

--[[
	ASSUMPTION — `ShouldDeliverCallback` is invoked per (message, recipient TextSource) and returning
	false suppresses delivery to that one recipient. Spike question: confirm the signature and that a
	`false` return is honoured rather than logged.

	FAILS CLOSED. Any state it cannot resolve — a speaker who left, a recipient with no Player, a nil
	TextSource — returns false, so an unresolvable message is dropped rather than broadcast. A dropped
	message is a confused player; a wrongly delivered one is a finished round.
]]
local function shouldDeliverToRecipient(message: TextChatMessage, recipient: TextSource): boolean
	local senderState = stateOfSpeaker(message.TextSource)
	local recipientState = stateOfSpeaker(recipient)

	if senderState == nil or recipientState == nil then
		return false
	end

	-- The casts cross a pure-module boundary: `Types.PlayerState` and `GhostChat.PlayerState` are the
	-- same structural union, but the analyzer widens the values to plain `string` in transit. Same bite
	-- CLAUDE.md documents for `Enums.RoundPhase.Idle`.
	return GhostChat.shouldDeliver(
		senderState :: GhostChat.PlayerState,
		recipientState :: GhostChat.PlayerState
	)
end

--[[
	EVERY CHANNEL, NOT JUST `RBXGeneral` — and this closes the whisper hole.

	The first version attached the guard to `RBXGeneral` alone. Default `TextChatService` creates
	`RBXWhisper:<userId>` channels ON DEMAND, so a ghost typing `/w SomeSurvivor <the Aswang's name>`
	routed through a channel this file had never seen. That needed no exploit at all — it is a slash
	command every Roblox player already knows.

	The ghost channel is skipped: everyone in it is dead by construction, and `shouldDeliverToRecipient`
	would deliver anyway. Skipping it keeps the callback off the hot path for the channel that carries
	the most traffic from the dead.
]]
local function guardChannel(instance: Instance)
	if not instance:IsA("TextChannel") then
		return
	end

	--[[
		EVERY CHANNEL, INCLUDING THE GHOST ONE. An earlier version skipped `Ghosts` as a
		micro-optimisation — `shouldDeliver` answers true for GHOST→GHOST anyway — and that exempted
		the exactly one channel where MEMBERSHIP is the only control.

		Layer 3's whole argument is that membership is a cache of state and the bug class is the two
		disagreeing. Two ways they disagree here, and neither needs an exploit: if a `TextSource` is
		not named the UserId string then `syncChannelMembership`'s removal silently no-ops and last
		round's ghost stays enrolled while ALIVE; and `AddUserAsync` yields, so a call in flight when
		the round ends can enrol a now-LOBBY player. In both cases a living player sits in the ghost
		channel reading the dead — and with the skip, nothing downstream would have stopped it.

		The saving was one callback invocation per ghost message. The cost was the fail-safe.
	]]
	instance.ShouldDeliverCallback = shouldDeliverToRecipient
end

--[[
	Attach the guard and create the ghost channel, given the TextChannels folder.

	Split out from `configureChannels` so the folder can arrive LATE — see below, where a live run
	proved it does.
]]
local function configureWith(channels: Instance)
	-- LAYER 3, over every existing channel and every channel created later.
	for _, child in channels:GetChildren() do
		guardChannel(child)
	end

	channels.ChildAdded:Connect(guardChannel)

	local existing = channels:FindFirstChild(GHOST_CHANNEL_NAME)

	if existing ~= nil and existing:IsA("TextChannel") then
		ghostChannel = existing
		return
	end

	-- LAYER 2.
	local channel = Instance.new("TextChannel")

	channel.Name = GHOST_CHANNEL_NAME
	channel.Parent = channels

	ghostChannel = channel

	if Config.Debug.VerboseLogging then
		print(`[GhostService] Chat wall attached over {#channels:GetChildren()} channel(s).`)
	end
end

--[[
	═══ THIS FUNCTION SHIPPED BROKEN AND A LIVE RUN CAUGHT IT ═══════════════════

	The first version did `FindFirstChild("TextChannels")`, and on nil it warned and RETURNED. A guard
	for the arrival race was added later — `channels.ChildAdded:Connect(guardChannel)` — but it was
	placed AFTER that early return, so in the exact case it was written for it never ran.

	Measured, first Play of the session:

	    [GhostService] ⚠️ NO TextChannels UNDER TextChatService — GHOST CHAT IS NOT ENFORCED.

	and a moment later, from the same server: `TextChannels exists NOW = true`, children
	`RBXSystem, RBXGeneral`, `Ghosts channel created by GhostService = false`. So the folder is created
	shortly AFTER services start, every time — the race is not a corner case, it is the normal path.
	The result was no ghost channel and no delivery callback on anything: ghost chat entirely
	unenforced, with `npm run verify` green over it and one warn line as the only symptom.

	The warn was also misleading. It blamed `ChatVersion = LegacyChatService`, and `ChatVersion` was
	correct — the cause was timing, so anyone reading that line would have gone and checked the one
	setting that was fine.

	NOW IT WAITS. `WaitForChild` in a `task.spawn` so `Start()` does not yield (init.server.luau calls
	every Start in sequence and a yield there delays every service after this one). A timeout rather
	than an indefinite wait, so a genuinely absent folder still produces a diagnosis instead of a
	silent hang.
]]
local CHANNELS_WAIT_SECONDS = 30 -- config-ok: a startup timeout, not a balance knob

local function configureChannels()
	local immediate = TextChatService:FindFirstChild("TextChannels")

	if immediate ~= nil then
		configureWith(immediate)
		return
	end

	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", CHANNELS_WAIT_SECONDS)

		if channels ~= nil then
			configureWith(channels)
			return
		end

		warn(
			"[GhostService] ⚠️ NO TextChannels AFTER "
				.. CHANNELS_WAIT_SECONDS
				.. "s — GHOST CHAT IS NOT ENFORCED. Every message a dead player sends reaches the "
				.. "living, which ends every round. Check TextChatService.ChatVersion is "
				.. "TextChatService (not LegacyChatService) and that CreateDefaultTextChannels is on. "
				.. "Neither setting is in Git, so no check in this repo can see them."
		)
	end)
end

--[[
	LAYER 1 — membership follows state. Called whenever a player's state may have changed.

	`TextChannel:AddUserAsync` and `TextSource:Destroy` are the documented add/remove pair; removing is
	done by destroying the `TextSource` the channel holds for that user, which is the part most likely
	to be wrong and is spike question 4.
]]
--[[
	LAYER 1 — a ghost is REMOVED from every living channel. This was specified, claimed in a comment,
	and never written; two audits found it independently.

	It is the layer that matters most because its absence is not a bug that has to HAPPEN. Roblox
	auto-adds every player to `RBXGeneral`, so doing nothing leaves a ghost typing into the living's
	channel by default — no race, no edge case, no exploit. Layers 2 and 3 are both conditional on
	Roblox behaving as documented; this one is just a `Destroy`.

	Removing means destroying the `TextSource` the channel holds for that user, which is the documented
	pair to `AddUserAsync`. Whether that is sufficient — and whether Roblox re-adds them on respawn —
	is spike question 4 and is UNVERIFIED. That is exactly why layer 3 exists underneath it.
]]
local function removeFromLivingChannels(player: Player)
	local channels = TextChatService:FindFirstChild("TextChannels")

	if channels == nil then
		return
	end

	for _, child in channels:GetChildren() do
		if child:IsA("TextChannel") and child.Name ~= GHOST_CHANNEL_NAME then
			local source: Instance? = child:FindFirstChild(tostring(player.UserId))

			if source then
				source:Destroy()
			end
		end
	end
end

local function syncChannelMembership(player: Player)
	local channel = ghostChannel

	if channel == nil then
		return
	end

	local isGhost = RoundService.GetPlayerState(player) == Enums.PlayerState.Ghost

	-- LAYER 1. Only ever removes; a player who stops being a ghost is re-added to the general channel
	-- by Roblox's own auto-join on the next round's character load, and re-adding here would race it.
	if isGhost then
		removeFromLivingChannels(player)

		--[[
			C23. §4.7's retention fix in one sentence, at the moment it lands. Without it, dying reads
			as the round being over for you — and a player who thinks they are done alt-tabs instead
			of contributing, which is the six-minute boredom Appendix C puts a number on.

			Fired to the player about their OWN death. It says nothing about who killed them, which is
			the thing Amendment A3 spent a whole remote removing.
		]]
		TeachingService.Cue(player, "CUE_FIRST_GHOST_DEATH")
	end
	-- The `: Instance?` is load-bearing under --!strict, the same annotation ItemService's pool lookup
	-- needs: without it the analyzer treats the result as non-optional and the nil comparison is a type
	-- error rather than a lookup.
	local existing: Instance? = channel:FindFirstChild(tostring(player.UserId))

	if isGhost and existing == nil then
		-- Wrapped: AddUserAsync yields and throws for a player who left mid-call, and an error inside a
		-- connection is swallowed by Roblox into a single warn that nobody reads.
		task.spawn(function()
			local ok, err = pcall(function()
				channel:AddUserAsync(player.UserId)
			end)

			if not ok then
				if Config.Debug.VerboseLogging then
					print(
						`[GhostService] Could not add {player.UserId} to the ghost channel: {err}`
					)
				end

				return
			end

			--[[
				RE-CHECK AFTER THE YIELD. `AddUserAsync` yields, and a call still in flight when the
				round ends enrols a player who is now LOBBY into the ghost channel — where they read
				the dead for the rest of the server's life, because the un-ghosting branch already ran
				and found nothing to remove.

				Narrow (the yield has to straddle the whole ENDING phase) but it needs no wrong
				assumption to fire, unlike the naming question above it.
			]]
			if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Ghost then
				local stale: Instance? = channel:FindFirstChild(tostring(player.UserId))

				if stale then
					stale:Destroy()
				end
			end
		end)
	elseif not isGhost and existing then
		existing:Destroy()
	end
end

local function onPhaseChanged(phase: Types.RoundPhase)
	if phase ~= Enums.RoundPhase.Active then
		clearGhosts()
	end

	broadcastRoster()

	-- Membership follows state, and a phase change is the one moment EVERY player's state can move at
	-- once — `setAllPlayerStates` rewrites the whole table. Re-syncing per player here is what stops a
	-- ghost from last round still sitting in the ghost channel during the next one.
	for _, player in Players:GetPlayers() do
		syncChannelMembership(player)
	end
end

--[[
	Where a ghost says it is, for `TaskService`'s presence check. Returns nil for a player who is not a
	ghost, or whose last report is stale.

	SERVER-ONLY ACCESSOR. The position never goes back out to any client: a roster of who is dead is
	already restricted to ghosts, and WHERE each dead player is standing is strictly more than that.
]]
function GhostService.GetGhostPosition(userId: number): Vector3?
	local entry = positions[userId]

	if entry == nil or os.clock() - entry.At > Config.Ghost.RosterInterval * 2 then
		return nil
	end

	return entry.Position
end

function GhostService.Init()
	table.clear(positions)
	table.clear(spooksUsed)
end

function GhostService.Start()
	configureChannels()

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		A DEATH IS WATCHED THROUGH CharacterRemoving, NOT CharacterAdded.

		Ghosts have no server character, so there is no ghost body to wait for — the OLD body going
		away is the observable event. `applyBodyRule` REVOKEs it the moment `MarkKilled` writes GHOST,
		and this fires on that removal.

		The state is re-read at that moment rather than assumed, because a player can be revived by a
		round ending between the death and this callback.
	]]
	local function watch(player: Player)
		local function onStateMayHaveChanged()
			if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Ghost then
				return
			end

			broadcastRoster()

			--[[
				HERE, NOT ONLY ON THE PHASE CHANGE. A player who dies mid-round becomes a GHOST
				immediately, and waiting for the next phase to move them into the ghost channel would
				leave them in the GENERAL one — able to name the Aswang to the living — for the rest of
				ACTIVE. That is the whole failure this feature exists to prevent, and it would be
				invisible in any test that only checks a fresh round.

				Layer 3's delivery callback would still catch it, which is why there are three layers.
			]]
			syncChannelMembership(player)
		end

		player.CharacterRemoving:Connect(onStateMayHaveChanged)

		-- A player who is ALREADY a ghost when this service starts, or who reconnects into one under
		-- the husk rule, never fires CharacterRemoving here.
		onStateMayHaveChanged()
	end

	Players.PlayerAdded:Connect(function(player: Player)
		watch(player)
		broadcastRoster()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		positions[player.UserId] = nil
		spooksUsed[player.UserId] = nil
		broadcastRoster()
	end)

	-- THE BACKFILL. `init.server.luau` may run after players are already in, and a service that only
	-- connects PlayerAdded covers nobody in a Studio session where the player joined first. RoundService
	-- and MonsterService both do this; the exploit audit flagged ItemService for omitting it.
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	--[[
		THE POSITION REPORT. The one place in this game where a client owns a position, and the only
		reason it is acceptable is that the subject is already dead.

		FOUR GATES, in the order a hostile call meets them:

		  1. `Consume` first and inline, as `check-ratelimit.mjs` requires.
		  2. `typeof(position) ~= "Vector3"` — a remote argument is whatever the client sent, and a
		     table reaching arithmetic throws inside a connection, which Roblox swallows into one warn.
		  3. NOT A GHOST, NO CLAIM. A living player calling this gets nothing stored, so the table can
		     never contain a living player's position — which matters because `TaskService` will trust
		     whatever is in it.
		  4. CONTINUITY. A report more than `FlySpeed` × elapsed away from the last one is refused, so
		     a ghost has to WALK to a lie rather than teleport to it. First report of a round is
		     accepted unconditionally; there is nothing to be continuous with, and refusing it would
		     mean a ghost could never start reporting.

		NaN AND INFINITY ARE REFUSED by the finite check, not by the distance comparison — every
		comparison against NaN is false, so `distance > limit` would ADMIT a NaN position and put it
		straight into the table for `TaskService` to measure against.
	]]
	Remotes.Get("ReportGhostPosition").OnServerEvent
		:Connect(function(player: Player, position: unknown)
			if not AntiCheatService.Consume(player, "ReportGhostPosition") then
				return
			end

			if typeof(position) ~= "Vector3" then
				return
			end

			if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Ghost then
				return
			end

			local magnitude = position.Magnitude

			if not (magnitude >= 0 and magnitude < math.huge) then
				return
			end

			local now = os.clock()
			local previous = positions[player.UserId]

			if previous ~= nil then
				local elapsed = math.max(now - previous.At, 0)
				-- One extra second of slack for a hitching client. The bound is about refusing teleports,
				-- not about policing frame times.
				local limit = Config.Ghost.FlySpeed * (elapsed + 1)

				if (position - previous.Position).Magnitude > limit then
					if Config.Debug.VerboseLogging then
						print(
							`[GhostService] Refused a discontinuous position from {player.UserId}.`
						)
					end

					return
				end
			end

			positions[player.UserId] = { Position = position, At = now }
		end)

	--[[
		THE RATE LIMIT IS INLINE AND FIRST, the shape MonsterService's handlers established and the one
		`check-ratelimit.mjs` looks for — it matches an `AntiCheat*.Consume` within 1200 characters of
		the `.OnServerEvent:Connect(`, so a handler limited somewhere else reads as unguarded.
	]]
	Remotes.Get("RequestGhostSpook").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestGhostSpook") then
			return
		end

		-- NO ARGUMENTS, and that is the security design — the same shape `RequestTimingStop` uses. The
		-- server resolves the position from the caller's own character and the budget from its own
		-- table. There is no argument in which a client could name a place, a light, or a count.
		local verdict = SpookBudget.evaluate({
			Phase = RoundService.GetPhase(),
			PlayerState = RoundService.GetPlayerState(player),
			Used = spooksUsed[player.UserId] or 0,
			Allowance = Config.Ghost.SpooksPerRound,
		})

		if verdict ~= "OK" then
			-- LOGGED, NEVER ECHOED. `NOT_GHOST` returned to a client is a state oracle: fire it as a
			-- living player and the refusal confirms you are alive, fire it after a suspected death
			-- and the change tells you the server agrees. Cheap to leak, pointless to.
			if Config.Debug.VerboseLogging then
				print(`[GhostService] Spook refused for {player.UserId}: {verdict}`)
			end

			return
		end

		local origin = spookOrigin(player.UserId)

		if origin == nil then
			-- No current position, no place to put the effect. Deliberately does NOT spend the budget:
			-- a ghost whose report is stale did nothing wrong and got nothing, and charging them would
			-- cost their only spook of the round to a dropped packet.
			return
		end

		spooksUsed[player.UserId] = (spooksUsed[player.UserId] or 0) + 1

		--[[
			TODO(M7): the actual effect — flicker a light or rustle a bush within SpookDuration at
			`origin`. It is deliberately not a new remote: whatever renders it must be driven by
			something already public in the world, because a down-remote carrying a position fired to
			the living is a channel that did not exist before and would need its own secrecy argument.

			The budget, the gate and the randomised origin are the parts that had to be right, and they
			are here. The visual is C34's.
		]]
		if Config.Debug.VerboseLogging then
			print(`[GhostService] Spook by {player.UserId} at {origin}.`)
		end
	end)

	--[[
		The roster is re-sent on a slow cadence as well as on events. `Config.Ghost.RosterInterval` is
		pinned at or above `Round.SnapshotInterval` by `tests/config.test.luau`, because the roster
		changes only when somebody dies and a send faster than the HUD's is a per-player cost with
		nothing behind it (§5's mobile budget counts sends per player per tick).
	]]
	task.spawn(function()
		while true do
			task.wait(Config.Ghost.RosterInterval)
			broadcastRoster()
		end
	end)
end

return GhostService
