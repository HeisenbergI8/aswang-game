--!strict
--[[
	QuickChatService — the eight-phrase wheel, server side. (§4.5, C25)

	§4.5 is blunt: "This is a small system with an outsized effect on how fun the game is. Do not cut
	it." Voice needs 13+ verification most of this audience lacks and typing mid-chase on a phone is
	impossible, so this IS the communication system. Accusation gameplay with no way to accuse is not
	gameplay.

	THREE THINGS THIS SERVICE REFUSES TO ACCEPT FROM A CLIENT
	--------------------------------------------------------
	The whole 🔒 surface of C25 is here, and it is best read as a list of what `RequestQuickChat`
	does NOT carry:

	  1. A NAME. C25's row: a client-supplied name is a free impersonation exploit, and it is a total
	     one — `FireServer("ACCUSE", "Bob")` puts any name in every player's HUD, attributed to the
	     sender, from anywhere on the map. The target is resolved here, from `pure/QuickChatTarget`,
	     over positions this server HOLDS.

	     ⚠ "HOLDS", NOT "OWNS", AND THE DIFFERENCE IS A REAL LIMIT. Roblox gives a client network
	     ownership of its own character, so the server's copy of the sender's position is whatever
	     that client replicated, and nothing in this repo validates character movement. A client that
	     can teleport can set itself one stud from anyone, accuse, and teleport back — never seen,
	     from anywhere on the map. An exploit audit found this and rated it High.

	     It is NOT introduced here: `RequestKill` and `RequestThrowSalt` already measure from the same
	     unvalidated position, so a client that can do this can already kill anyone. C25 is a new
	     consumer of an existing hole, and the real fix is one server-side movement-plausibility gate
	     per character that every distance rule consults. Until that exists, the design's stated cost
	     of accusing — that you were adjacent and visible — is not enforced against a modified client.
	  2. A POSITION. The world ping is the SENDER's own root position at the instant the request
	     landed. A client-named position is a "draw an arrow anywhere" primitive — including on top of
	     another player, which accuses by geometry while the phrase says something harmless.
	  3. A STRING. The phrase is an id; the text is rendered by the receiver from
	     `shared/pure/QuickChatPhrases`. See the TextService note below — this is what makes that
	     entire question disappear rather than get answered.

	So the remote's payload is one `Types.QuickChatPhraseId` and nothing else, which puts it in the
	same class as `RequestTimingStop` (C09) and `RequestStartTrial` (C21): remotes deliberately built
	so there is no argument in which a client could name a moment, a place, a person or an outcome.

	WHY THERE IS NO `TextService` CALL IN THIS FILE
	----------------------------------------------
	The C25 build-plan row says "`TextService`-filtered", and this service does not filter. That is a
	deliberate deviation, raised with the user and confirmed by them rather than taken quietly, and
	the argument is that there is nothing left to filter:

	  · The eight phrases are AUTHOR-WRITTEN constants. They are not user-generated content, they are
	    game copy, and they never travel — the receiver renders them from an id it already has.
	  · The one user-generated string in the neighbourhood is the accused player's DISPLAY NAME, and
	    it is never transmitted either. The payload carries `TargetUserId`; each client resolves the
	    name locally through `Players:GetPlayerByUserId`.

	A filter call would therefore be a yielding web request, inside an `OnServerEvent` handler, on
	the 🔒 surface, to sanitise a string that was already ours — and one whose failure mode is a
	handler that hangs. Removing the category beats sanitising it.

	PHASE OWNERSHIP. This service SUBSCRIBES to `RoundService.PhaseChanged` and never calls
	`setPhase` — spec §6.4, and the same shape ItemService and TaskService use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local GhostChat = require(Shared.pure.GhostChat)
local QuickChatPhrases = require(Shared.pure.QuickChatPhrases)
local QuickChatTarget = require(Shared.pure.QuickChatTarget)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local AntiCheatService = require(script.Parent.AntiCheatService)
local RoundService = require(script.Parent.RoundService)

local QuickChatService = {}

local broadcastRemote = Remotes.Get("QuickChatBroadcast")

--[[
	SERVER-ONLY. Nothing here is replicated, attributed or tagged.

	This is a verdict log for C41, not state any client reads. It exists because a refusal that
	produces no record is a refusal nobody can tune the budget against — and `NO_TARGET_IN_SIGHT` in
	particular is the one whose frequency tells you whether `AccuseRangeStuds` is right.
]]
local verdictCounts: { [string]: number } = {}

local function recordVerdict(verdict: Types.QuickChatVerdict)
	verdictCounts[verdict] = (verdictCounts[verdict] or 0) + 1
end

local function onPhaseChanged(phase: Types.RoundPhase)
	--[[
		Nothing to tear down on the server: a quick chat is a fire-and-forget broadcast with no
		lifetime here, and the message and ping lifetimes are the RECEIVER's business.

		The counters reset per round so C41 reads a round's worth of verdicts rather than a server's.
	]]
	if phase == Enums.RoundPhase.Starting then
		table.clear(verdictCounts)
	end

	--[[
		C41 will want to know how often the accusation found nobody: a high `NO_TARGET_IN_SIGHT` rate
		means `AccuseRangeStuds` is too tight or the greybox has too many sight-blockers, and a rate
		near zero across a whole round means it is loose enough to be worth re-examining as an
		oracle. A tuning fact, so it rides `VerboseLogging` rather than shipping to a live server.
	]]
	if phase == Enums.RoundPhase.Ending and Config.Debug.VerboseLogging then
		local parts: { string } = {}

		for verdict, count in verdictCounts do
			table.insert(parts, `{verdict}={count}`)
		end

		table.sort(parts)

		print(`[QuickChat] verdicts this round: {table.concat(parts, " ")}`)
	end
end

--[[
	═══ SPEC §6.4'S EDGE CASES, ANSWERED FOR C25 ════════════════════════════════

	· THE ACCUSED LEAVES BETWEEN RESOLUTION AND RENDER. The client falls back to "someone". This is
	  the reason the payload carries a UserId rather than a name: a name resolved server-side would
	  have frozen a departed player's name into every HUD permanently.
	· THE SENDER DIES IN THE SAME FRAME. `GetPlayerState` is read once at the top of the handler and
	  again in `broadcast` at the fire site. A player who died between the two delivers to ghosts,
	  which is the safe direction — the alternative would put a dead player's words in front of the
	  living.
	· THE ROUND ENDS WITH THE WHEEL OPEN. The wheel is client state. A request arriving after ACTIVE
	  is refused `WRONG_PHASE`, and nothing here holds a lock.
	· A PLAYER JOINS MID-ROUND. They are SPECTATOR, and `GhostChat.shouldDeliver` gives them their
	  own island: they hear the living, and neither side hears them. Identical to text chat since C15.
	· A GHOST REJOINS AS AN ALT. Unchanged by C25 — `pure/RejoinResolve` owns it, and this wheel adds
	  no channel a returning account could read that text chat did not already expose.
]]

--[[
	The sender's own root part, from the SERVER's copy of their character.

	⚠ A GHOST DOES HAVE A CHARACTER, AND IT IS NOT WHERE THEY ARE. Since C15 the corpse stays attached
	as `player.Character` — that is the whole shape `.claude/lessons/absence-is-observable.md` records,
	because a dead player with no character is a one-line roster of the dead. So this returns the
	CORPSE's root for a ghost, not nil, and every caller has to know that.

	It returns nil only for a player mid-respawn or one whose character the body rule has parked.
]]
local function rootPartOf(player: Player): BasePart?
	local character = player.Character

	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

--[[
	Can the sender actually SEE this player? A range-limited raycast, plus a field-of-view term.

	THIS IS THE ANTI-ORACLE DEFENCE and it is why the accusation phrase is not a proximity radar. A
	raycast is a DataModel call, so it cannot be Lune-tested; `pure/QuickChatTarget` takes the ANSWER
	as a boolean. The rule stays enumerable, the physics stays here.

	THE FOV TERM IS NOT DECORATION — an exploit audit found the claim it repairs. Without it the cast
	is root-to-root with no facing and no lighting, so it "sees" players directly BEHIND the sender,
	through fog, in the dark. That made a FAILED accusation a free, silent, server-authoritative
	"nobody has line to me" — worth one token, no broadcast, nobody learns you probed. The Aswang's
	transform is the risk half of §4.4, and this was a way to check it was safe without looking.

	With the dot-product term, a miss means "nobody IN FRONT of me", which is what a player's own eyes
	already told them. That is the property that makes the phrase safe to spam, and it was not true
	before.

	CORPSES AND HUSKS ARE EXCLUDED, and the answer came from this repo rather than a playtest. The C25
	draft flagged the filter "not confirmed sufficient" and deferred to a playtester; `MonsterService`
	had settled it two milestones earlier with the reason stated — a raycast hits parts regardless of
	`CanCollide`, so anchoring a body and clearing its collision is NOT enough, and **a body is not
	cover**. Corpses cluster exactly where accusations happen, and they fade to invisible but are
	deliberately never destroyed — so without this an Aswang can kill in a doorway and stand behind
	their own victim, where accusations against them fail for no visible reason.
]]
local function hasLineOfSight(
	senderRoot: BasePart,
	targetRoot: BasePart,
	senderCharacter: Model?,
	targetCharacter: Model?
): boolean
	local toTarget = targetRoot.Position - senderRoot.Position

	--[[
		FACING FIRST, because it is a dot product and the raycast is not. A candidate behind the
		sender is rejected before any physics work happens, which also keeps the per-call cost flat.
	]]
	local facing = senderRoot.CFrame.LookVector
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)

	if flat.Magnitude > 0 then
		local cosine = facing.Unit:Dot(flat.Unit)

		if cosine < math.cos(math.rad(Config.QuickChat.AccuseHalfAngleDegrees)) then
			return false
		end
	end

	local filter: { Instance } = {}

	if senderCharacter ~= nil then
		table.insert(filter, senderCharacter)
	end

	if targetCharacter ~= nil then
		table.insert(filter, targetCharacter)
	end

	-- Built as a list rather than a literal with casts in it, for the reason MonsterService's
	-- equivalent records: `Folder?` does not cast to `Instance`, and an excluded nil would be
	-- silently tolerated and silently wrong the day the folder mattered.
	local corpses = workspace:FindFirstChild("Corpses")

	if corpses ~= nil then
		table.insert(filter, corpses)
	end

	local husks = RoundService.GetHusksFolder()

	if husks ~= nil then
		table.insert(filter, husks)
	end

	local params = RaycastParams.new()

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true

	-- A hit on ANYTHING is a refusal. Conservative direction: the cost of being wrong is one phrase
	-- that says nothing, and the cost of being wrong the other way is naming someone through a wall.
	return workspace:Raycast(senderRoot.Position, toTarget, params) == nil
end

local function resolveTarget(sender: Player, senderRoot: BasePart): number?
	local candidates: { QuickChatTarget.Candidate } = {}

	for _, other in Players:GetPlayers() do
		if other == sender then
			continue
		end

		local otherRoot = rootPartOf(other)

		if otherRoot == nil then
			continue
		end

		local otherState = RoundService.GetPlayerState(other)

		--[[
			Both characters are excluded from the cast, and they are gathered as a list of the ones
			that actually exist rather than cast through `:: Instance`. `Player.Character` is `Model?`
			— it is nil for a ghost and during a respawn — and a nil in
			`FilterDescendantsInstances` is an error inside a connection, which Roblox swallows into
			one warn and the accusation silently stops working for everybody.
		]]
		table.insert(candidates, {
			UserId = other.UserId,
			DistanceStuds = (otherRoot.Position - senderRoot.Position).Magnitude,
			--[[
				A GHOST OR SPECTATOR IS NOT A CANDIDATE, and the reason is a leak rather than a
				nicety: they are not rendered to the living, so naming one would tell every recipient
				that somebody nobody can see is standing somewhere — a death signal with a position
				attached, which is the exact shape Amendment A3 removed `AlivePlayerCount` to close.
			]]
			--[[
				ALIVE ONLY, not `isLivingSide`. An exploit audit caught the two disagreeing: the
				handler refuses a LOBBY player as a SENDER on the grounds that they are not in the
				round, while `isLivingSide` admitted them as a TARGET. `PlayerBody`'s header warns
				that the "can be killed" allowlist and the "is living-side" allowlist must never be
				merged, and this picked the wider one. A GHOST or SPECTATOR is excluded for a
				stronger reason still: they are not rendered to the living, so naming one announces
				that somebody nobody can see is standing somewhere — a death signal with a position
				attached, which is the shape Amendment A3 removed `AlivePlayerCount` to close.
			]]
			IsAliveSide = otherState == Enums.PlayerState.Alive,
			HasLineOfSight = hasLineOfSight(
				senderRoot,
				otherRoot,
				sender.Character,
				other.Character
			),
		})
	end

	return QuickChatTarget.nearest(candidates, Config.QuickChat.AccuseRangeStuds)
end

--[[
	Deliver to everyone entitled to hear it, and to nobody else.

	`FireClient` IN A LOOP, NEVER `FireAllClients`, and the reason is the same one `GhostRoster`
	gives: what makes this safe is its AUDIENCE, not its contents. A `FireAllClients` here would put
	a ghost's accusation in front of the living, which is the rule `pure/GhostChat`'s header calls
	the most dangerous one in the game.

	AND `check:secrecy` CANNOT POLICE IT. It reads payload fields and call shapes, and
	`FireClient(player, payload)` inside a loop over the wrong list is textually identical to one
	over the right list. So the state test lives HERE, at the fire site, exactly as GhostService's
	roster does — the check script is not the thing keeping this correct, this loop is.
]]
local function broadcast(sender: Player, payload: Types.QuickChatBroadcastPayload)
	local senderState = RoundService.GetPlayerState(sender)

	for _, recipient in Players:GetPlayers() do
		local recipientState = RoundService.GetPlayerState(recipient)

		--[[
			THE SAME PREDICATE TEXT CHAT USES, REUSED RATHER THAN REIMPLEMENTED.

			`pure/GhostChat` is a sixteen-cell grid precisely so a second feature does not get a
			second, subtly different wall — its own header notes that an earlier single-wall version
			delivered GHOST -> SPECTATOR, which an audit caught and a hand-rolled `if` here would
			have reintroduced. `tests/ghost-chat.test.luau` now pins both features against it.

			The casts cross a pure-module boundary: `Types.PlayerState` and `GhostChat.PlayerState`
			are the same structural union, declared twice because a pure module may not require
			`Types`.
		]]
		if
			GhostChat.shouldDeliver(
				senderState :: GhostChat.PlayerState,
				recipientState :: GhostChat.PlayerState
			)
		then
			broadcastRemote:FireClient(recipient, payload)
		end
	end
end

function QuickChatService.Init()
	table.clear(verdictCounts)
end

function QuickChatService.Start()
	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)

	--[[
		`AntiCheatService.Consume` IS THE FIRST STATEMENT IN THE HANDLER, and it must stay inside this
		function body rather than being hoisted into a helper. `check-ratelimit.mjs` matches the
		Consume call within a character window of the `.OnServerEvent:Connect(`, so a handler limited
		somewhere else reads as unguarded — the same note GhostService carries above its spook
		handler.
	]]
	Remotes.Get("RequestQuickChat").OnServerEvent
		:Connect(function(player: Player, phraseId: unknown)
			if not AntiCheatService.Consume(player, "RequestQuickChat") then
				return
			end

			--[[
				TYPE THE ARGUMENT AS `unknown` AND NARROW IT HERE.

				A remote argument annotated `Types.QuickChatPhraseId` is a LIE the typechecker will
				believe: the wire carries whatever the client sent, and a compromised client sends a
				table, a function reference, or nothing at all. Every one of those would sail past a
				declared parameter type and fail several lines later somewhere less obvious.
			]]
			if typeof(phraseId) ~= "string" then
				recordVerdict("UNKNOWN_PHRASE")
				return
			end

			local phrase = QuickChatPhrases.get(phraseId)

			if phrase == nil then
				recordVerdict("UNKNOWN_PHRASE")
				return
			end

			--[[
				PHASE GATE. Quick chat is a round mechanic, so it runs at ACTIVE and nowhere else.

				ENDING is excluded on purpose and it is the interesting exclusion: the reveal has
				already happened by then, so an accusation fired into the end screen is either noise
				or — worse — a player who now KNOWS the answer broadcasting it into a phase where a
				late-joining spectator could read it. There is no version of this that helps.
			]]
			if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
				recordVerdict("WRONG_PHASE")
				return
			end

			local senderState = RoundService.GetPlayerState(player)

			--[[
				GHOSTS MAY SPEAK, BUT NOT ACCUSE, and the refusal is a CONSEQUENCE rather than a
				policy.

				A ghost has no server character (see `ReportGhostPosition`'s header in Remotes.luau),
				so there is no server-owned position to resolve "nearest" from. The only position
				available is the client-reported one that the same header states plainly the server
				cannot verify — and resolving an accusation target from a client-supplied position is
				precisely the impersonation exploit C25's row forbids, with one extra step in front
				of it. The client would not be naming the player; it would be naming the point the
				server picks the player from, which is the same power.

				`GhostMay` lives on the phrase in `pure/QuickChatPhrases` rather than as an `if` here,
				so the rule is enumerable and `tests/quick-chat-phrases.test.luau` pins that the one
				ghost-forbidden phrase is exactly the one that needs a target.
			]]
			if senderState == Enums.PlayerState.Ghost and not phrase.GhostMay then
				recordVerdict("NOT_ALLOWED_FOR_STATE")
				return
			end

			--[[
				A LOBBY PLAYER IS NOT IN THE ROUND. The phase gate above already means a round is
				running, so LOBBY here is somebody between states — a player who joined this second,
				or one whose body rule has not settled. They have nothing to say about a round they
				are not in, and letting them say it would let a spectator-adjacent account inject
				into the living channel.
			]]
			if
				senderState ~= Enums.PlayerState.Alive
				and senderState ~= Enums.PlayerState.Ghost
			then
				recordVerdict("NOT_ALLOWED_FOR_STATE")
				return
			end

			local senderRoot = rootPartOf(player)
			local targetUserId: number? = nil
			local pingPosition: Vector3? = nil

			if phrase.NeedsTarget then
				if senderRoot == nil then
					recordVerdict("NO_SENDER_CHARACTER")
					return
				end

				targetUserId = resolveTarget(player, senderRoot)

				--[[
					NOBODY IN SIGHT IS A SILENT REFUSAL, and every part of that is deliberate.

					NOT BROADCAST: a "nobody there" variant would tell the whole server the sender is
					alone, which is a free position hint about a player who did not choose to give
					one. Rendering the phrase with an empty name gives "It's !" and reads as broken.

					NOT ECHOED TO THE SENDER EITHER, which is the less obvious half. GhostService's
					spook handler refuses to return its verdict for exactly this reason — a refusal a
					client can read is a state oracle. The sender learns it failed by not seeing their
					own message appear, and an absence carries no detail to probe with.

					And what the sender learns from the silence is nothing new: line of sight was
					required, so "nobody visible near you" is what their eyes already said. That is
					the property that makes this phrase safe to spam.
				]]
				if targetUserId == nil then
					recordVerdict("NO_TARGET_IN_SIGHT")
					return
				end
			end

			--[[
				THE PING IS THE SENDER'S OWN POSITION, and it is derived here rather than sent.

				A GHOST PINGS THEIR CORPSE, NOT THEMSELVES, AND THAT IS DELIBERATE.

				`rootPartOf` returns the corpse for a ghost — see its header; the corpse is
				`player.Character` since C15. The alternative is a client-reported flying position
				the server cannot verify, which is the "draw an arrow anywhere" primitive this
				service refuses. Pinging the body is the honest, server-owned answer, it only ever
				reaches other ghosts, and "here is where I died" is a useful thing for a ghost to
				say.
			]]
			if phrase.Pings and senderRoot ~= nil then
				pingPosition = senderRoot.Position
			end

			recordVerdict("OK")

			--[[
				FOUR FIELDS, NO STRINGS, NO PLAYER STATE. See `Types.QuickChatBroadcastPayload` for
				the full argument; the short version is that every field here is either a UserId the
				receiver can already resolve or a position this server derived itself, and there must
				never be a field saying whether anybody is alive.
			]]
			broadcast(player, {
				SenderUserId = player.UserId,
				PhraseId = phrase.Id :: Types.QuickChatPhraseId,
				TargetUserId = targetUserId,
				PingPosition = pingPosition,
			})
		end)
end

return QuickChatService
