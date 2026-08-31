--!strict
--[[
	Remotes — single place where every RemoteEvent/RemoteFunction is declared.

	The server creates them; the client waits for them. Declaring them in one
	file means you can audit your entire network surface at a glance, which
	matters a lot in a game where one secret (who is the Aswang) decides
	everything.

	RULE: every remote listed here must be rate-limited and fully validated in
	AntiCheatService / the owning service. The client only ever *requests*.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

-- Server -> Client (the server tells you things)
local EVENTS_DOWN = {
	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
	"PhaseChanged",
	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
	"PlayerKilled",
	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
	"SaltEffect",
	"RoundEnded", -- includes the reveal
	"QuickChatBroadcast",
	--[[
		C32/C33. STILL UNWIRED, AND THE PAYLOAD IS THE TRAP. `Types.PlayerProfile` contains
		`Stats.AswangRounds` and `AswangWins` — a per-player history of drawing the role — so the
		obvious implementation, "send the player their profile", ships role history to a client.

		`check-secrecy.mjs` enforces its payload rule ONLY on the two allowlisted remotes (`RoundEnded`,
		`RoleAssigned`), so a whole-profile payload here would pass `npm run verify` GREEN. Nothing
		mechanical stops it; this comment is the stop.

		Send an explicit field list — XP, Level, Coins, Equipped. If a whole profile is ever genuinely
		wanted, add this remote to `check-secrecy.mjs`'s allowlist WITH a reason first, so the decision
		appears in a diff instead of in a payload. (Raised by `exploit-auditor` during C31.)

		WIRED AT C32/C33/C34, AND THE FIELD LIST ABOVE WAS FOLLOWED. `Types.ProfileSnapshot` is the
		payload: XP, Level, Coins, the level bar's two spans, the equipped ids, the OWNED set, the
		daily preview, and the last round's award breakdown. `Stats` is absent in full — not trimmed,
		absent — so `AswangRounds` and `AswangWins` have no field to leak through.

		FireClient TO ONE PLAYER, ALWAYS, carrying only that player's own profile. There is no
		FireAllClients path for this remote and there must not be: every field in it is per-player, so
		a broadcast would hand eight clients eight players' inventories, and `Owned` plus a level is
		enough to fingerprint who is who across rounds.
	]]
	"ProfileUpdated",
	--[[
		C21. FireClient to the ONE player in a Solo Trial. Never FireAllClients.

		THE INTERESTING PROPERTY IS THAT THERE IS NO SECRET HERE AT ALL, and saying so is the point:
		the trial's Aswang is a scripted rig, so no role exists to leak inside a trial. The risk runs
		the other way — a trial remote that could be confused with a round one, or fired at a player
		who is in a round. `Types.TrialSnapshot` shares no field name with `ClientRoundSnapshot`
		precisely so that confusion is a type error rather than a subtle bug, and the server refuses
		to open a session at all unless RoundService is IDLE.

		WHAT A SECOND PLAYER LEARNS: nothing from this remote, which they never receive. They can of
		course SEE a trial player walk to the trial corner and see the rig, and that is harmless by
		construction — a trial only runs while no round is running, so there is no round-secret to
		correlate it against. `.claude/lessons/absence-is-observable.md` applies in its mild direction
		and resolves the same way OnboardingController's waypoint does.
	]]
	"TrialSnapshot",
	--[[
		C23. FireClient to ONE player, carrying a `Types.TeachingCueId` and nothing else.

		WHAT IT REVEALS, stated in full rather than pointed at a neighbour — V01 deleted the entry
		this used to inherit from. It reveals that the RECEIVER is new, and it names nobody else. The
		recipient list is never sent anywhere; the payload is a cue id, not a player, a place or a
		role. The events it fires on are already public (a transform, the sunrise) or already the
		receiver's own (their own salt pickup, their own death).

		Being new is not a role, and the asymmetry runs the safe way: an Aswang learning that some
		unnamed player is a beginner learns nothing they could not get by watching them play, and no
		survivor learns anything about the Aswang from it.

		An id rather than a string so the copy has one home, and so player-facing text never crosses
		the wire — `shared/pure/TeachingLines` is replicated and the client resolves it.
	]]
	"TeachingCue",
	--[[
		V03, §4.4. FireClient to the ONE player whose search it is. Never FireAllClients — there is no
		broadcast form of this payload and adding one would be a redesign, not an optimisation.

		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The
		public half of searching is NOISE, and noise is V04's chunk — it will be a broadcast that
		names a position and no player, and it is deliberately not this remote.

		THE PAYLOAD NAMES NO CONTAINER. `Types.SearchUpdatePayload` carries a verdict, a duration and
		an optional item, and the reasoning for each absent field is written there. The property worth
		repeating here is the structural one: with no container id in the payload there is no key on
		which two colluding clients could difference their updates to reconstruct the layout. The
		layout exists only in a server-side table and in `server/pure/ContainerLayout`, which does not
		replicate.

		IT IS NOT A ROLE ORACLE. §4.4 has the Aswang searching on identical rules, so both roles
		receive this remote with the same verdicts at the same rate for the same reasons.
	]]
	"SearchUpdate",
	--[[
		V04, §4.4. FireClient, to every player the SERVER has decided is close enough to hear it —
		never FireAllClients. `Types.NoiseCuePayload` is the payload.

		THE BROADCAST FORM IS THE WHOLE RISK AND IT IS REFUSED. A FireAllClients carrying a position
		would hand every client a live index of where everybody in the barrio is acting, readable
		from a compromised client with no exploit beyond listening. §4.6 allows the Aswang an AREA on
		a 90s-to-30s pulse (V13); a broadcast noise feed is a live map, which is strictly more than
		the tracker will ever give it and would obsolete the balance-critical chunk of the rewrite.
		The distance test happens on the server, and a player out of earshot receives NOTHING.

		WHAT A SECOND CLIENT LEARNS: that something loud happened, roughly where, and what kind of
		action it was. Not who did it — the payload has no player field of any kind, and the position
		is quantised to Config.Noise.CueGridStuds before it is sent.

		IT IS NOT A ROLE ORACLE, and the reasoning is §4.4's rather than this remote's: the Aswang
		searches and throws on identical rules, emits identical noise, and receives this cue on
		identical terms. There is no branch anywhere in the send path that reads a role. The
		asymmetry that WOULD leak — one player never producing a cue, or never receiving one — is
		`.claude/lessons/absence-is-observable.md`, and it is why no exemption exists here.

		THE `Mine` FLAG IS NOT A LEAK: a client only ever sees its own payloads, so a boolean about
		the receiver is the same shape as every field on `ProfileSnapshot`.
	]]
	"NoiseCue",
	--[[
		V06, §4.3. FireClient to the ONE player whose feed it is. Never FireAllClients — there is no
		broadcast form of this payload and adding one would be a redesign, not an optimisation.

		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The public
		half of a feed is that a monster is standing on a body in the open for five seconds, which is
		§4.3's entire design — "a corpse becomes bait… survivors now know exactly where the monster is
		and exactly how long it will be there" — and it needs no remote at all. It replicates as
		geometry and it is meant to be seen.

		IT IS NOT A ROLE ORACLE, AND THE ARGUMENT IS `RoleAssigned`'S. Only the Aswang can ever receive
		this, which is exactly the property that makes it safe rather than dangerous: it is fired to a
		single player and carries only that player's own business, so the set of clients that learn
		anything from it is the set of clients that already knew. `check-secrecy.mjs` allowlists
		`RoleAssigned` on that reasoning and this remote does not need allowlisting at all, because
		`Types.FeedUpdatePayload` contains no role, no UserId and no health.

		THE PAYLOAD NAMES NO VICTIM AND NO BODY. Deliberate, and for `SearchUpdate`'s structural reason:
		with no id in the payload there is nothing for a compromised client to log, difference or
		accumulate. The feeder is standing on the corpse — a field naming it would be the server
		telling a client what it is looking at.

		AND NO HEALTH, IN ANY FORM. §4.6: "a health value attached to a player is the reveal." A feed
		changes the Aswang's health by FeedHeal and this remote still says nothing about it; the only
		licensed readout is the Exposed glow's brightness, which exists only while the licence does.

		FEEDING EMITS NO `NoiseCue`, EITHER, AND THAT IS A REFUSAL RATHER THAN AN OMISSION. §4.4's four
		noisy actions are SEARCH, ITEM_USE, DOOR and SPRINT. A fifth for feeding would be the first
		mechanic in this game whose noise ONLY ONE ROLE CAN PRODUCE — a cue no survivor could ever have
		caused, delivered to every listener in radius. That is `.claude/lessons/absence-is-observable.md`
		inverted into a presence, and `check:secrecy` would be green over it.
	]]
	"FeedUpdate",
	--[[
		V07, §4.3. FireClient to the ONE player whose disguise it is. Never FireAllClients — there is
		no broadcast form of this payload and adding one would be a redesign, not an optimisation.

		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The
		public half of camouflage needs no remote at all — a player avatar is gone and a pig is
		standing where it was, and both of those replicate as geometry. That is the whole of what the
		barrio is told, and §4.3 is content with it: the monster is already revealed by the time it
		can do this, so there is no secret left for the geometry to give away.

		THE PAYLOAD CARRIES NO CHARGE COUNT. `Types.CamouflageUpdatePayload` is a verdict and an
		optional form. The charge is a boolean on the server-only `monsters` table and it has no
		field, no attribute and no tag anywhere — a client that knew its own charge could not leak it
		(it is the Aswang's own business), but the field would be the obvious place for a later
		broadcast to grow one, and there is no reason to build the socket.

		AND NO REVEAL FLAG. `HasBeenRevealed` never crosses in any form. A `CAMO_NOT_REVEALED` verdict
		does reach the requester, and that is safe on `RoleAssigned`'s reasoning: it is fired to a
		single player, about that player, telling them a fact they already have — they know whether
		they have been salted, because they were standing inside the glow.
	]]
	"CamouflageUpdate",
	--[[
		V07, §4.3. FireClient to every player the SERVER decides is within `Config.Monster
		.SmokeCueRadius` of the burst — NEVER FireAllClients. `Types.SmokeBurstPayload` is the payload.

		THE BROADCAST FORM IS THE WHOLE RISK AND IT IS REFUSED, for `NoiseCue`'s reason exactly. A
		FireAllClients carrying a position hands every client the monster's live location the instant
		it tries to escape — readable from a compromised client with no exploit beyond listening, and
		strictly more than V13's 90s-to-30s tracker will ever give the survivors. The distance test
		happens on the server and a player out of radius receives NOTHING.

		THE POSITION IS EXACT RATHER THAN QUANTISED, AND THAT IS A DELIBERATE DIFFERENCE FROM
		`NoiseCue`. Noise is heard at 60 studs — far beyond what a listener can see — so its position
		is quantised to a grid because the payload would otherwise state more than the world does.
		Smoke's send radius is 40 and the cloud itself is 18: everyone who receives this is close
		enough to WATCH the cloud form, so an exact centre states nothing they will not see rendered a
		frame later. If `SmokeCueRadius` is ever raised well past visual range, this reasoning expires
		and the position must be quantised — that dependency is stated in Config beside the number.

		THE PAYLOAD HAS NO PLAYER FIELD OF ANY KIND. No UserId, no Character, no name. A cloud is a
		fact about a place; "the Aswang is inside it" is an inference a client is welcome to make from
		looking, and the server never states it. This matters more than it looks: smoke is fired only
		by the Aswang, so a UserId here would be a role broadcast with a position attached — the
		single worst payload in the game — and `check:secrecy` matches `killer\w*` and the enumerated
		role tokens, not a field called `Source`.
	]]
	"SmokeBurst",
}

-- Client -> Server (the client asks; the server decides)
local EVENTS_UP = {
	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	--[[
		C34. Carries a cosmetic id and nothing else — no slot, no price, no "and equip it".

		THE SLOT IS NOT AN ARGUMENT, deliberately: it is a property of the item in
		`Config.Cosmetics.Catalogue`, so a client cannot name an id in one slot and a slot in another
		and see which of the two the server believes. `pure/Cosmetics.evaluateEquip` re-checks
		ownership on every call, because the lobby only OFFERS what it thinks is owned and an offer is
		a hint rather than a permission (§6.2).
	]]
	"RequestEquipCosmetic",
	--[[
		C34. Also carries an id alone, and the ABSENT argument is the security design.

		There is no price in this request. `pure/Cosmetics.evaluatePurchase` returns the cost out of
		the catalogue and the server spends exactly that, so there is no number here for a compromised
		client to shrink and no path where a client's arithmetic decides what a cosmetic costs.
	]]
	"RequestBuyCosmetic",
	--[[
		C33. NO ARGUMENTS. The day is `os.time()` on the server, the streak is in the profile, and
		`pure/DailyStreak.evaluate` decides — there is nothing a client could legitimately name, and a
		claimed timestamp is precisely the field that would make the streak forgeable.
	]]
	"RequestClaimDaily",
	--[[
		C39, §9.2. NO ARGUMENTS, for the same reason `RequestClaimDaily` above has none — everything
		the decision needs is server-side already.

		THE GROUP ID IS NOT AN ARGUMENT, and that is the security design. `Config.Community.GroupId`
		names the one group this reward is for, and `Player:IsInGroup` is asked about that id on the
		server. A client-supplied id would let a player name any group they happen to belong to and
		collect 250 coins for membership of somebody else's.

		Nor is there a "claimed" flag in the request: `Profile.GroupRewardClaimed` is the authority,
		and a client that could assert its own claim state could re-claim forever.
	]]
	"RequestClaimGroupReward",
	--[[
		C21. NO ARGUMENTS, deliberately — the same rule every request in this list follows.

		There is nothing a client could legitimately name here: which trial, where, and whether it is
		allowed are all server facts. The handler re-runs `shared/pure/TrialAdmission` on every call
		rather than trusting that C24's button was only shown when a trial was actually available —
		the button is a hint to an honest player, never a permission.
	]]
	"RequestStartTrial",
	-- C22. Also argument-free: it means "I am done", and the server already knows whose session it is.
	"RequestEndTrial",
	--[[
		C22. A throw INSIDE a trial, and it is a separate remote from `RequestThrowSalt` on purpose.

		§9.1 asks that the player "learn to throw salt", and they could not: `ItemService` resolves
		every throw through `pure/ItemThrow` against `RoundService.GetPhase()`, and a trial runs while
		the phase is IDLE — so the real remote answers WRONG_PHASE and the tutorial taught an action
		the player could not perform.

		THE TWO WAYS TO FIX IT WERE A NEW REMOTE OR A LOOSER `ItemService`, AND THE LOOSER SERVICE IS
		THE ONE THAT WOULD HAVE HURT. Relaxing the phase gate means the salt system starts consulting
		trial state to decide a live round's throws — coupling the two services this entire feature
		exists to keep apart, on the 🔒 surface, for a tutorial. This remote costs one budget entry and
		couples nothing.

		It carries a direction and nothing else, exactly as `RequestThrowSalt` does. The server owns
		the range, the cone, the target and the outcome — and both remotes resolve through the SAME
		`ItemThrow.inCone`, so the throw a player learns here is the throw that works in a round.
	]]
	"RequestTrialThrow",
	--[[
		V03, §4.4. NO ARGUMENTS, and the absent argument is the entire security design.

		THE CONTAINER IS NOT NAMED BY THE CLIENT. The server resolves the nearest `SearchContainer`
		part within `Config.Search.RangeStuds` of that player's OWN character position — the rule
		`ItemService`'s header states for pickups, applied to the one interaction that has a remote:
		"the server resolves what a player is standing at from that player's own character position,
		and the client names nothing."

		A `RequestSearch(containerName)` would have been strictly worse in three ways, and the third
		is the one that matters. It needs a verdict for "that container is not near you"; it needs
		validation that the named part is the one you are standing at, which is the distance
		comparison the server was already positioned to make; and it hands a compromised client a
		PROBE — name every tagged part in turn, read the verdicts, and learn which containers are
		spent and which are occupied without walking anywhere. The map's part names are readable by
		any client (Workspace replicates), so the probe would have been trivial to write.
	]]
	"RequestSearch",
	--[[
		V03. Also argument-free: it means "I let go", and the server already knows whose hold it is.

		SEPARATE FROM `RequestSearch` RATHER THAN A TOGGLE ON IT. A toggle desynchronises the moment a
		packet is dropped or a token is refused — the client believes it stopped, the server believes
		it started again — and the failure is a search that silently never completes. Two remotes make
		each message idempotent: a duplicate cancel releases nothing, a duplicate start hits
		SEARCH_BUSY.

		THE SERVER DOES NOT DEPEND ON THIS ARRIVING. Five other release paths exist (distance, death,
		leave, completion, phase change), so a cancel lost to the rate limiter costs at most the
		remainder of one hold. That is why its budget is the more generous of the two.
	]]
	"RequestCancelSearch",
	--[[
		V08, §4.6. NO ARGUMENTS, and the absent argument is the entire security design.

		THE ITEM IS NOT NAMED BY THE CLIENT. `Config.Items.CarryLimit` is 1, so there is exactly one
		thing a player can be holding and the server already knows what it is. This is
		`RequestClaimDaily`'s and `RequestCamouflage`'s rule — everything the decision needs is
		server-side already — and `RequestSearch`'s: the server resolves what a player has from that
		player's own state, and the client names nothing.

		A `RequestDropItem(itemType)` WOULD HAVE BEEN A FREE PROBE AND A FREE DUPLICATOR. It needs a
		verdict for "you are not holding that", which is the comparison the server was already going
		to make; and a client naming `BUNTOT_PAGI` while holding salt is a request the server must
		refuse rather than one it can simply not be asked. There is exactly one buntot pagi per round
		(§4.6) and it IS the second win condition, so a handler that spawns an item the client named
		is the sharpest exploit surface this chunk has. It has no argument, so it cannot be asked.

		NOR IS THERE A POSITION. A drop lands `Config.Items.DropForwardStuds` in front of the
		player's OWN character, read on the server. A client-supplied position drops the win
		condition through a wall, inside the map, or at a teammate's feet across the barrio.

		IT IS NOT A ROLE ORACLE IN EITHER DIRECTION. §4.4 has the Aswang searching on identical
		rules, so the monster can hold and drop items exactly as a survivor can, and must — see
		`Types.ClientRoundSnapshot.YourCarriedItem`: an empty-handed survivor and the Aswang are
		indistinguishable only if the monster genuinely fills slots. Nothing is returned to the
		caller on any path, including OK.
	]]
	"RequestDropItem",
	--[[
		V07, §4.3. NO ARGUMENTS, and the absent argument is the security design.

		THE FORM IS NOT NAMED BY THE CLIENT. The server picks it from whatever `AmbientRoster.claim`
		can actually supply, from the population it owns — the rule `SearchService` already applies to
		containers: "the server resolves what a player is standing at from that player's own character
		position, and the client names nothing."

		A `RequestCamouflage(form)` would have been strictly worse in the way that matters. It needs a
		verdict for "there is no cat left", which is the roster query the server was already going to
		make; and it hands a compromised client a PROBE — ask for each of the four forms in turn, read
		the verdicts, and learn the live ambient population without walking anywhere. That is a map of
		which corners of the barrio have been depopulated, which is exactly the information a hunting
		survivor pays attention for.
	]]
	"RequestCamouflage",
	--[[
		V07, §4.3. Also argument-free. The burst happens at the requester's OWN character position,
		which the server reads; a position argument would be a "put a cloud anywhere" primitive, and
		the first thing to do with it is drop one on a survivor's face across the map.

		THERE IS NO `RequestExitCamouflage`, AND THAT IS THE THIRD REMOTE THIS CHUNK DID NOT ADD.
		Stepping out of the disguise is `RequestTransform`, which already exists, is already budgeted
		and already means "become the monster" — a camouflaged Aswang firing it exits the form and
		transforms, which is the only reason it would ever want out. A dedicated exit remote would be
		a second entry point into the same state change, and `RequestSearch`/`RequestCancelSearch`'s
		header is right that two messages for one state are how a client and a server come to
		disagree about it.
	]]
	"RequestSmoke",
}

local Remotes = {}

local function getFolder(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local folder = getFolder()

local function getEvent(name: string): RemoteEvent
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Eagerly create on the server so the client's WaitForChild always resolves.
if IS_SERVER then
	for _, name in EVENTS_DOWN do
		getEvent(name)
	end
	for _, name in EVENTS_UP do
		getEvent(name)
	end
end

-- Usage: Remotes.Get("RequestKill"):FireServer(targetUserId)
function Remotes.Get(name: string): RemoteEvent
	return getEvent(name)
end

Remotes.Down = EVENTS_DOWN
Remotes.Up = EVENTS_UP

return Remotes
