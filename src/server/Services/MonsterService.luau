--!strict
--[[
	MonsterService — the transform (C04, §4.3 steps 1–3 and 5).

	THE TRANSFORM IS PUBLIC BY DESIGN. It is the one thing in this game that legitimately reveals the
	Aswang, it is the signature clippable moment, and it gives survivors real information with no UI at
	all — which is what makes grouping up genuinely protective. Broadcasting it is correct, not a
	compromise.

	Read that alongside RoleService's header and the asymmetry is the design: the identity never leaves
	the server, and the ACT of transforming is shouted to everybody. A player who witnesses it learns
	who the Aswang is by seeing, which is exactly the game.

	NO CUSTOM MESH (§4.3, and §3's OUT list). The avatar is reused with a scale change, a colour and
	material shift, glowing eyes and a particle emitter.

	WHAT THIS SERVICE DOES NOT SEND
	-------------------------------

	V05 ADDS A NUMBER AND SENDS NOTHING. The Aswang's health is a field on the server-only `monsters`
	table and it has no remote, no attribute, no tag and no field on any payload. §6.2: "the Aswang's
	health is server-only state, readable by others only while `Exposed`." The one channel it uses is
	the brightness of a Highlight that EXISTS only during the Exposed window — so the permission and
	the mechanism are the same fact, and there is no state in which the readout outlives the licence.

	IT IS NOT ON THE HUMANOID, AND THAT IS THE WHOLE POINT. `Humanoid.Health` and `Humanoid.MaxHealth`
	replicate. One character reading 75 while four read 100 is a permanent, map-wide, remote-free role
	oracle — the same shape as C04's revert bug and C14's WalkSpeed brand, both of which shipped with
	`verify` and `check:secrecy` green over them. See `.claude/lessons/absence-is-observable.md`: the
	leak is a DIFFERENCE between players, not a piece of data.

	V06 ADDS ONE REMOTE AND IT GOES TO ONE PLAYER. `FeedUpdate` is FireClient to the feeder, carrying
	a three-value verdict and a duration the client already had from replicated Config. There is no
	broadcast form. The PUBLIC half of a feed needs no remote at all and never gets one: a transformed
	monster standing on a body for five seconds is §4.3's "corpse becomes bait" rendering itself, and
	it replicates as geometry.

	FEEDING EMITS NO NOISE CUE, AND THAT IS A REFUSAL. §4.4 names four noisy actions and feeding is
	not one. A fifth would be the first cue in this game only one role can cause — see `Remotes.luau`'s
	`FeedUpdate` entry for the full argument. `check:secrecy` would be green over it.

	THE ONE REPLICATED DIFFERENCE A FEED CREATES IS `WalkSpeed = 0`, on a character already in monster
	form and already announced, for exactly FeedDuration seconds. `endFeed` is the single restore path
	and all six exits go through it; a seventh exit that does not is the C04/C14 brand again.

	THE FIVE SEAMS THE NEXT THREE CHUNKS CALL, so nobody has to guess which one to reach for:

	  · `ApplySaltHit(player)` — V08. Revert, -SaltDamage floored at WeakenedThreshold, Exposed for
	    SaltRevealDuration. The ONLY entry point for a salt hit; there is no bare `ForceRevert` any
	    more, precisely so a caller cannot revert without damaging.
	  · `HealFromFeed(userId) -> boolean` — WIRED AT V06, called by `completeFeed` and by nothing else.
	    Returns whether state existed, never the health. Does not restore camouflage.
	  · `FeedCompleted` (BindableEvent) — V07'S SEAM, ADDED AT V06 AND CONNECTED TO BY NOTHING. Fires
	    with the feeding Player on a COMPLETED feed and never on an interrupted one. §4.3 gives a
	    completed feed two rewards and V06 pays one: this event is where V07 hangs the other. The
	    reason the heal and the camouflage refresh cannot come apart is that `completeFeed` is the only
	    caller of `HealFromFeed` AND the only firer of this event, and `endFeed` — which all six
	    interruption paths go through — does neither.
	  · `IsExposed(userId) -> boolean` — V08's strike gate, half one.
	  · `IsWeakened(userId) -> boolean` — V08's strike gate, half two. §4.6: the buntot pagi kills an
	    Aswang that is BOTH. AND them with `RoundService.GetAswangUserId()` on the server and hand a
	    single boolean to the pure module, exactly as `ItemService` does for `IsTransformed`.

	NONE OF THE FOUR ENUMERATES, and none returns the health value. Every one takes a UserId the
	caller already holds and answers false for a player with no monster state — which is every
	survivor, every round, so none of them is usable as a probe.

	`MonsterTransformed` carries a Character and a boolean. It does NOT carry a role: "this character
	transformed" is a fact about the world; "this player is the Aswang" is an inference the client is
	welcome to make and the server never states. The distinction becomes load-bearing at C14, where
	salt forces a revert on someone who is still the Aswang.

	The refusal verdict is likewise never echoed back. It exists so the server can log WHY, and handing
	a client `NOT_ASWANG` would be a free role oracle for anyone willing to spam the remote.

	`PlayerKilled` (C05) carries a victim and a position, and NOTHING ELSE — no killer, no name, no
	direction, no distance, no "you were seen". SINCE AMENDMENT A3 IT ALSO GOES TO ONE CLIENT: the
	victim, via FireClient. Broadcast, it was the strongest death oracle in the game — see the comment
	at the fire site. Three things about the payload are worth knowing before anyone adds a field:

	  · A killer field here IS now caught — `check-secrecy.mjs` was repaired after an audit found this
	    exact hole. Two things were wrong: its broadcast rule read the ARGUMENT TEXT, so a typed local
	    (`FireAllClients(payload)`) reduced the scan to seven characters and the payload's contents were
	    never seen; and its SECRET regex enumerated `aswanguserid` by hand and matched no `Killer*`
	    token at all. It now resolves the payload back to its declaration and matches `killer\w*`.
	    Proven by injecting `KillerUserId = killer.UserId` into the payload below and watching the check
	    go red. Do not take that as licence — the check is a text tripwire and a determined leak can
	    still walk around it; it is a backstop under the rule, not the rule.
	  · The position is safe on its own terms, not by permission: an anchored corpse is standing at that
	    position and replicates to every client one frame later. The payload states nothing new.
	  · What IS inferable, and cannot be fixed here, is proximity — a client reading replicated character
	    positions at the instant of the broadcast can see who was within eight studs. That is inherent
	    to a proximity kill in a replicated world; the counter is design, not code (§4.3: the killer is
	    standing there in monster form, having just been announced). Recorded in Follow Ups rather than
	    papered over.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AmbientService = require(script.Parent.AmbientService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local RoleService = require(script.Parent.RoleService)
local RoundService = require(script.Parent.RoundService)
local TeachingService = require(script.Parent.TeachingService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local CamouflageRules = require(Shared.pure.CamouflageRules)
local FeedRules = require(Shared.pure.FeedRules)
local KillValidation = require(Shared.pure.KillValidation)
local MonsterHealth = require(Shared.pure.MonsterHealth)
local Remotes = require(Shared.Remotes)
local TransformRules = require(Shared.pure.TransformRules)
local Types = require(Shared.Types)

local MonsterService = {}

--[[
	THE V07 SEAM, AND V06 CONNECTS NOTHING TO IT (V06, §4.3).

	§4.3 gives a completed feed two rewards: `+FeedHeal` health, and — "once the Aswang has been
	revealed" — its camouflage back. V06 owns the first and V07 owns the second, and this event is the
	joint. It fires with the feeding Player, from `completeFeed`, on a COMPLETED feed and never on an
	interrupted one.

	THAT IS WHAT MAKES §4.3'S "INTERRUPTING A FEED IS A REAL VICTORY" TRUE STRUCTURALLY RATHER THAN
	CAREFULLY. The heal and this event have exactly one caller between them; every interruption path
	goes through `endFeed`, which calls neither. Nobody has to remember to withhold the camouflage
	refresh on a salt hit, because there is no code that could grant it.

	IT CARRIES A PLAYER AND NOTHING ELSE. No health, no victim, no charge count, no body. A listener
	that needs more should take a UserId and ask this service, the way `ItemService` already ANDs
	`IsTransformed` with `RoundService.GetAswangUserId()` — the seams answer questions, they do not
	volunteer state.

	A BindableEvent RATHER THAN A REMOTE, and the distinction is the secrecy one: this never leaves the
	server. The client half of a feed is `FeedUpdate`, fired to the feeder alone, and it deliberately
	carries no camouflage field — see `Types.FeedUpdatePayload`.
]]
MonsterService.FeedCompleted = Instance.new("BindableEvent")

--[[
	THE HEALTH TUNING (V05, §4.6), ASSEMBLED ONCE FROM TWO CONFIG BLOCKS.

	`MaxHealth`, `WeakenedThreshold` and `FeedHeal` live under `Config.Monster`; `SaltDamage` lives
	under `Config.Items`, which is §6.5's canonical item block and where V02 put the four salt
	numbers. `pure/MonsterHealth` takes one table rather than reaching for either, so it stays a
	function over plain numbers and `tests/monster-health.test.luau` can hand it a synthetic tuning.

	READ THROUGH `Config.Items`, NOT THROUGH `Config.Salt`. The `Salt` block is a set of aliases V02
	kept alive for five v1.3 readers (Config.luau:326-342) and it dies with the chunk that renames
	its last one.
]]
local HEALTH_TUNING: MonsterHealth.Tuning = {
	MaxHealth = Config.Monster.MaxHealth,
	WeakenedThreshold = Config.Monster.WeakenedThreshold,
	SaltDamage = Config.Items.SaltDamage,
	FeedHeal = Config.Monster.FeedHeal,
}

-- One part's appearance as it was BEFORE the transform touched it. See restoreLook().
type PartLook = {
	Part: BasePart,
	Color: Color3,
	Material: Enum.Material,
}

--[[
	V07, §4.3. WHAT CAMOUFLAGE CAPTURES, AND WHY IT IS NOT `PartLook`.

	Hiding the character is a SEPARATE capture from the transform's, deliberately. `PartLook` is
	`captureLook`'s struct and `restoreLook` is its only reader; widening it so camouflage could ride
	along would put two features on one restore path, and C04's map-wide branding bug is what that
	costs when the two disagree about what "original" means. One capture, one owner, one restore.

	IT WALKS DESCENDANTS RATHER THAN DIRECT CHILDREN, which `captureLook` does not — so accessory
	handles are hidden too. A disguise that leaves the player's hat floating over a cat is not a
	disguise, and an exploit audit named exactly that.
]]
type HiddenPart = {
	Part: BasePart,
	Transparency: number,
}

type MonsterState = {
	-- A transform has been requested and not yet reverted. Set BEFORE the windup, so it also closes
	-- the same-instant spam race — the second request sees ALREADY_TRANSFORMED.
	Transformed: boolean,
	-- The look is physically on a character and needs undoing. Distinct from Transformed because a
	-- revert during the windup must not run a cleanup for changes that were never applied.
	Applied: boolean,
	-- MonsterTransformed(true) was broadcast. A revert broadcasts false ONLY if this is set; otherwise
	-- clients receive a revert for a transform they never saw, which at C14 is a free identity leak.
	Announced: boolean,
	-- The character the look was applied TO. Resolving player.Character at revert time can land on a
	-- freshly respawned character that never transformed, and whiten it.
	AppliedTo: Model?,
	OriginalParts: { PartLook },
	OriginalScales: { [string]: number },
	Effects: { Instance }, -- exactly what this service created, so the revert removes nothing else
	LastRevertedAt: number?, -- nil until the first revert of the round; drives the cooldown
	BaseWalkSpeed: number?,
	Generation: number, -- invalidates an in-flight forced revert; see revert()
	--[[
		THE ASWANG'S HEALTH (V05, §4.6). SERVER-ONLY, AND THIS FIELD IS THE ONLY COPY OF IT.

		NOT `Humanoid.Health` AND NOT `Humanoid.MaxHealth`. Both are replicated properties: writing
		this number onto the humanoid lets any client walk `workspace`, find the one character
		reading 75 while four others read 100, and know the monster — permanently, for free, with no
		remote to intercept and nothing for `check:secrecy` to see. That is the same shape as C04's
		revert bug and C14's WalkSpeed brand, both of which shipped green (see ItemService's
		`applyHit` header and `.claude/lessons/absence-is-observable.md`).

		Not an attribute and not a tag either; both replicate to every client and there is no private
		one.

		SURVIVES A TRANSFORM CYCLE, DIES WITH THE ROUND. It is deliberately not reset by `revert()` —
		§4.6's tug-of-war is a round-long resource, so three salt hits across three separate
		transforms still weaken. `onPhaseChanged`'s existing `table.clear(monsters)` on the way out
		of ACTIVE is the reset, and it is the only one.
	]]
	Health: number,
	-- V05, §4.6. EXPOSED IS THE TRUTH; the Highlight below is its presentation. Two fields rather
	-- than one because `IsExposed` is V08's strike gate and must not depend on whether an Instance
	-- happened to survive a respawn. Every exit clears both, together, in `clearExposed`.
	Exposed: boolean,
	ExposedGlow: Highlight?,
	-- The same `os.clock()` generation trick `revert()` uses, for the same reason: a second salt hit
	-- landing during the first one's window must not have its expiry cut short by the first timer.
	ExposedGeneration: number,
	--[[
		FEEDING (V06, §4.3). SERVER-ONLY, LIKE EVERY OTHER FIELD IN THIS TABLE.

		Three facts and no fourth. `Feeding` is the state, `FeedBody` is the corpse it is pinned to,
		`FeedEndsAt` is the `os.clock()` deadline. There is no generation counter here and that is
		deliberate: `revert()` and `applyExposed` both need one because both arm a `task.delay` whose
		callback can outlive the thing that armed it, and a feed has no delayed callback at all — it
		is driven by a tick that reads this table fresh every pass, so a stale one cannot exist.

		`FeedBody` IS A MODEL REFERENCE, NOT A POSITION. A corpse is anchored and cannot move, so a
		cached position would be correct — but a cached position cannot tell the tick that the body
		was DESTROYED, which is what `clearCorpses` does on the way into INTERMISSION. Holding the
		Model lets `bodyKindOf` re-answer every tick and lets a destroyed body end the feed through
		the same path a husk would.

		NOT A `MonsterState` ENUM VALUE. `Enums.luau:62-72` defers "one field or a field plus a flag"
		to the chunk that builds the state machine, and V06 is not it: `Transformed` has four readers
		outside this file and `Exposed` is a LATCH that coexists with the form. V06 adds one boolean
		and derives the enum on demand. V07 decides the final shape.
	]]
	Feeding: boolean,
	FeedBody: Model?,
	FeedEndsAt: number?,
	--[[
		THE LOCK'S CAPTURED STATE (V06, §4.3). Added in Phase 3 rather than Phase 2 so that the feed
		lifecycle landed with no Humanoid write in it at all — the two halves are separable and the
		dangerous one is this one.

		C04'S LESSON, APPLIED TO TWO MORE FIELDS: capture what you are about to change, restore what
		you captured, never a hardcoded default. C04 restored every part to white Plastic at scale 1.0
		and branded the ex-Aswang map-wide; the same mistake here is `JumpPower = 50` on revert, which
		is right for almost every player and wrong for whoever the game gave a different value.

		BOTH PROPERTIES, NOT ONE. `Humanoid.UseJumpPower` decides which of JumpPower and JumpHeight is
		live, and nothing in this repo sets it. Writing and restoring both means the lock holds and the
		restore is correct without this file having to know which mode is in use.

		WALKSPEED IS NOT HERE, DELIBERATELY. `BaseWalkSpeed` above already holds the honest
		pre-transform speed, captured by `captureLook`, and that is what the feed restores — not the
		transformed speed, which is C14's bug spelled out.
	]]
	FeedBaseJumpPower: number?,
	FeedBaseJumpHeight: number?,
	--[[
		CAMOUFLAGE AND THE REVEAL GATE (V07, §4.3). SERVER-ONLY, LIKE EVERY OTHER FIELD HERE, and
		`HasBeenRevealed` is the single most dangerous boolean in this table.

		A FIELD PLUS TWO FLAGS, which is the shape `Enums.luau:62-72` deferred to "the chunk that
		builds the state machine" and V06's header deferred again to V07. This is that chunk, and the
		answer matches what V06 did for `Feeding`: `Camouflaged` is the state, `CamouflageForm` is
		which of the four it wears, and the enum is derived on demand by `monsterStateOf` rather than
		stored. One boolean per fact, no second source of truth.

		`HasBeenRevealed` IS THE GATE AND IT IS ONE-WAY. False on a fresh record — which is what makes
		camouflage impossible by DEFAULT rather than by remembering to refuse it — and set true by
		exactly one caller, `ApplySaltHit`, through `CamouflageRules.revealedAfter`. It is never
		cleared mid-round; the reset is `onPhaseChanged`'s `table.clear(monsters)` on the way out of
		ACTIVE, exactly as it is for `Health`.

		WHY IT IS NOT `Exposed`. Exposed expires after `Items.SaltRevealDuration` and this does not.
		The glow is a ten-second window; having been salted is a fact about the round. Reusing
		`Exposed` as the gate would mean camouflage re-locks itself ten seconds after every hit, which
		reads as a bug and is a total inversion of §4.3's pressure loop.

		`HasCamouflageCharge` STARTS TRUE and is spent on entry, restored ONLY by a completed feed —
		`CamouflageRules.chargeAfter` is the only function that moves it. Starting true costs nothing
		while `HasBeenRevealed` is false, because the gate is checked first and unconditionally.

		NEITHER FIELD HAS AN ATTRIBUTE, A TAG OR A PAYLOAD FIELD ANYWHERE. `CamouflageUpdatePayload`
		carries a verdict and a form and nothing else; see its header in `Types.luau`.
	]]
	HasBeenRevealed: boolean,
	HasCamouflageCharge: boolean,
	Camouflaged: boolean,
	CamouflageForm: Types.CamouflageForm?,
	--[[
		THE CLAIMED AMBIENT SLOT, held so every exit path can hand it back.

		AN INDEX, NOT A MODEL — the opposite of `FeedBody`, and deliberately so. `AmbientService` owns
		the Instances and `AmbientRoster` deals in indices; a Model reference here would be a second
		handle on an object this file does not own, and the release path would have two ways to
		disagree about which slot is free.
	]]
	AmbientSlot: number?,
	--[[
		V07, §4.3. THE HIDDEN CHARACTER'S CAPTURED STATE.

		Camouflage hides the PLAYER and shows the ambient entity — the inverse of the first
		implementation, which hid the entity and showed a re-skinned player. See `AmbientService`'s
		header for the measured reason. So these two fields hold what has to be put back: every
		descendant BasePart's Transparency, and the Humanoid's name-display setting.

		CAPTURED, NEVER DEFAULTED. C04 restored hardcoded defaults instead of captured state and
		branded the ex-Aswang for the rest of the round; `Transparency = 0` on revert is that same
		mistake for anyone whose avatar legitimately has a translucent part.
	]]
	CamouflageHiddenParts: { HiddenPart }?,
	CamouflageNameDisplay: Enum.HumanoidDisplayDistanceType?,
	-- `os.clock()` of the last granted burst, or nil until the first one this round. Read by
	-- `CamouflageRules.evaluateSmoke`, which takes it as a field so the cooldown stays testable.
	LastSmokeBurstAt: number?,
}

-- SERVER-ONLY. Keyed by UserId. Never replicated — the only thing that crosses is the broadcast.
local monsters: { [number]: MonsterState } = {}

--[[
	THE LIVE SMOKE FIELD (V07, §4.3). SERVER-ONLY, and it is the MECHANIC rather than the effect.

	"Breaks line of sight" has to mean something the server enforces, or it is a decoration a client
	can switch off. So a burst is three numbers and a deadline here, `pure/CamouflageRules.smokeBlocks`
	answers whether a given segment passes through one, and the two places in this game that ask a
	line-of-sight question — `hasLineOfSight` for a kill, `ItemService`'s throw resolution — consult
	it. A player who deletes the emitter, drops to minimum graphics, or never receives the payload
	plays under identical rules.

	A LIST RATHER THAN ONE ENTRY, even though `SmokeCooldown` means one Aswang can have only one live
	at a time. Bursts outlive the requester's state — a monster that dies inside its own cloud leaves
	it standing for the remainder of `SmokeDuration`, which is correct: the cloud is a thing in the
	world, not a property of a player.

	NO PLAYER FIELD, HERE EITHER. The table holds no UserId and no character. Nothing needs one — the
	cooldown lives on the monster record with the rest of that player's state — and its absence means
	there is no field for a later payload to grow one from.
]]
type SmokeBurst = {
	Centre: Vector3,
	Radius: number,
	ExpiresAt: number,
}

local smokeBursts: { SmokeBurst } = {}

local transformedRemote = Remotes.Get("MonsterTransformed")
local killedRemote = Remotes.Get("PlayerKilled")
local feedRemote = Remotes.Get("FeedUpdate")
-- V07. Both FireClient-only: one to the disguise's owner, one to whoever is close enough to see the
-- cloud. Neither has a FireAllClients call site anywhere in this file, deliberately.
local camouflageRemote = Remotes.Get("CamouflageUpdate")
local smokeRemote = Remotes.Get("SmokeBurst")

-- One parent for every corpse, so the raycast can exclude them wholesale and a phase change can clear
-- them with a single Destroy. Created on Start, never destroyed.
local corpses: Folder? = nil

local function stateFor(userId: number): MonsterState
	local existing = monsters[userId]

	if existing ~= nil then
		return existing
	end

	local created: MonsterState = {
		Transformed = false,
		Applied = false,
		Announced = false,
		AppliedTo = nil,
		OriginalParts = {},
		OriginalScales = {},
		Effects = {},
		LastRevertedAt = nil,
		BaseWalkSpeed = nil,
		Generation = 0,
		Health = Config.Monster.MaxHealth,
		Exposed = false,
		ExposedGlow = nil,
		ExposedGeneration = 0,
		Feeding = false,
		FeedBody = nil,
		FeedEndsAt = nil,
		FeedBaseJumpPower = nil,
		FeedBaseJumpHeight = nil,
		--[[
			V07, §4.3. `HasBeenRevealed = false` IS THE GATE'S DEFAULT AND THE WHOLE CHUNK RESTS ON
			THIS LINE. A fresh record cannot camouflage, so camouflage is impossible until something
			explicitly opens it — and exactly one caller does (`ApplySaltHit`). Delete that caller and
			the ability is provably unreachable rather than accidentally unavailable.
		]]
		HasBeenRevealed = false,
		-- True from the start, which costs nothing: the gate above is checked first and
		-- unconditionally, so a charge on an unrevealed monster is a number nobody can spend.
		HasCamouflageCharge = true,
		Camouflaged = false,
		CamouflageForm = nil,
		AmbientSlot = nil,
		CamouflageHiddenParts = nil,
		CamouflageNameDisplay = nil,
		LastSmokeBurstAt = nil,
	}

	monsters[userId] = created

	return created
end

--[[
	THE MONSTER'S STATE AS `pure/FeedRules` WANTS IT (V06, §4.3).

	`Enums.MonsterState` has five members and this function produces three. The two it never produces
	are the whole content of the decision, so they are stated rather than omitted:

	  · `EXPOSED` IS A LATCH, NOT AN ACTIVITY. §4.6's reveal coexists with whatever form the monster
	    is in — a salted Aswang is Exposed AND still an Aswang. Returning EXPOSED here would shadow
	    TRANSFORMED, and `FeedRules` would answer NOT_TRANSFORMED for a glowing monster standing on
	    a body it is entitled to feed on. That is not a hypothetical: §4.3 makes salt the thing that
	    INTERRUPTS a feed, so a salted feeder is the common case, not the edge one.
	  · `CAMOUFLAGED` has no producer until V07. `FeedRules` still answers for it and the grid still
	    covers it, because `pure/BodyTransitions`'s header is right that a state with no stated answer
	    is where these tables acquire bugs.

	`FEEDING` REQUIRES BOTH FLAGS, AND THAT IS LOAD-BEARING FOR THE TICK. `Feeding and Transformed`,
	never `Feeding` alone: `FeedRules.mayContinue` reads a non-FEEDING state as "the form went away
	under the feed" and ends it, which is exactly the backstop that catches a revert from a source
	nobody has thought of. Written as `if Feeding then return "FEEDING"`, a reverted-but-still-flagged
	monster would report FEEDING forever and the backstop would never fire.
]]
local function monsterStateOf(monster: MonsterState): Types.MonsterState
	--[[
		CAMOUFLAGED FIRST, ABOVE FEEDING AND ABOVE TRANSFORMED (V07, §4.3). ORDER IS THE CONTRACT.

		A camouflaged Aswang is still `Transformed` underneath — camouflage is an appearance layer over
		the monster form, not a revert — so checking `Transformed` first would report TRANSFORMED for a
		monster standing in the barrio as a pig. `FeedRules.evaluate` would then grant it a feed, and
		`CamouflageRules.evaluate` would never see ALREADY_CAMOUFLAGED, so a second hide would claim a
		second slot and the first one would leak for the rest of the round.

		FEEDING AND CAMOUFLAGED ARE MUTUALLY EXCLUSIVE BY CONSTRUCTION, not by this ordering: the
		rules module refuses a hide while FEEDING, and `beginFeed` is reached only from `commitKill`,
		which needs a kill, which needs monster form. The order here decides what is REPORTED if they
		ever both become true, and reporting CAMOUFLAGED is the safer of the two — it refuses the feed
		rather than granting a hide.

		BOTH FLAGS, NEVER `Camouflaged` ALONE — V06's rule for `Feeding`, load-bearing for the same
		reason: written as `if Camouflaged then`, a camouflaged monster whose transform was reverted
		by a path nobody thought of would report CAMOUFLAGED forever, and every backstop that reads
		"the form went away" would stop firing.
	]]
	if monster.Camouflaged and monster.Transformed then
		return Enums.MonsterState.Camouflaged
	end

	if monster.Feeding and monster.Transformed then
		return Enums.MonsterState.Feeding
	end

	if monster.Transformed then
		return Enums.MonsterState.Transformed
	end

	return Enums.MonsterState.Normal
end

--------------------------------------------------------------------------------
-- The look. Everything added lives under one folder, so reverting is a Destroy.
--------------------------------------------------------------------------------

local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3]) -- config-ok: RGB channel indices, not knobs
end

--[[
	Scale the avatar. R15 exposes these as NumberValues under the Humanoid; R6 has no equivalent and
	the loop simply finds nothing.

	RIG TYPE IS A PLACE-FILE SETTING AND THE PLACE FILE IS NOT IN GIT, so nothing in this repository
	can tell you which one is in use. The FindFirstChild guards make this correct either way: on R6 the
	Aswang gets the colour, material, eyes, particles and speed, and does not grow. That is a weaker
	tell, not a broken one, and it is a thing to LOOK AT during the two-client test rather than assume.
]]
local SCALE_VALUES = { "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }

local function applyScale(humanoid: Humanoid, scale: number)
	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)

		if value ~= nil and value:IsA("NumberValue") then
			value.Value = scale
		end
	end
end

--[[
	CAPTURE BEFORE MUTATING. This is the whole of the fix for the worst bug C04 shipped in review.

	The first version restored hardcoded defaults on revert — every part to white Plastic, every scale
	to 1.0. That is not what was there before, and the consequence is not cosmetic: after any revert
	the ex-Aswang becomes the ONLY character in the game whose parts are pure white Plastic at scale
	1.0. An exploiter reads that off the replicated properties from across the map, retroactively, with
	no remote traffic to intercept and no need to have witnessed anything.

	It also breaks the mechanic with no exploit at all. §4.3's revert exists so the Aswang blends back
	into the crowd; a survivor walking past a white plastic avatar a minute later gets the reveal free.

	Note the asymmetry that made this easy to miss: `BaseWalkSpeed` was already captured and restored
	correctly. The same discipline simply was not applied to colour, material and scale.
]]
local function captureLook(state: MonsterState, character: Model, humanoid: Humanoid)
	table.clear(state.OriginalParts)
	table.clear(state.OriginalScales)

	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(
				state.OriginalParts,
				{ Part = part, Color = part.Color, Material = part.Material }
			)
		end
	end

	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)

		if value ~= nil and value:IsA("NumberValue") then
			state.OriginalScales[name] = value.Value
		end
	end

	state.BaseWalkSpeed = humanoid.WalkSpeed
end

local function restoreLook(state: MonsterState)
	for _, look in state.OriginalParts do
		-- The character may have been destroyed under us (respawn, disconnect). A destroyed Instance
		-- still answers property writes harmlessly, but Parent is the cheap liveness test.
		if look.Part.Parent ~= nil then
			look.Part.Color = look.Color
			look.Part.Material = look.Material
		end
	end

	table.clear(state.OriginalParts)
	table.clear(state.OriginalScales)
end

-- Every Instance this service adds, tracked so the revert removes exactly what it created and nothing
-- else. The previous version destroyed EVERY PointLight and ParticleEmitter on the Head, which would
-- have deleted a lamp effect or a cosmetic from C34 that happened to live there.
local function trackedEffect(state: MonsterState, instance: Instance)
	table.insert(state.Effects, instance)
end

local function clearEffects(state: MonsterState)
	for _, effect in state.Effects do
		effect:Destroy()
	end

	table.clear(state.Effects)
end

--[[
	THE WINDUP'S TELL, applied at the START of the 1.2s rather than after it.

	§4.3 step 2 calls the windup "visible to anyone with line of sight", and the original code applied
	nothing until `task.wait(TransformTime)` had already returned — so the Aswang went from ordinary to
	monster in a single frame after a silent pause, and the entire risk half of the risk/reward was
	missing. An Aswang could fire the request in a crowd, walk into cover during 1.2s of nothing, and
	emerge already transformed.

	Particles first, then the full look. It escalates, which is what makes it a tell you can react to.
]]
local function applyWindupLook(state: MonsterState, character: Model)
	local head = character:FindFirstChild("Head")

	if head == nil or not head:IsA("BasePart") then
		return
	end

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(rgb(Config.Monster.EyeGlowRgb))
	particles.Rate = Config.Monster.TransformParticleRate
	particles.Lifetime = NumberRange.new(1)
	particles.Speed = NumberRange.new(1)
	particles.Parent = head

	trackedEffect(state, particles)
end

local function applyFullLook(state: MonsterState, character: Model, humanoid: Humanoid)
	for _, look in state.OriginalParts do
		if look.Part.Parent ~= nil then
			look.Part.Color = rgb(Config.Monster.TransformedTintRgb)
			look.Part.Material = Enum.Material.Slate
		end
	end

	applyScale(humanoid, Config.Monster.TransformedScale)

	local head = character:FindFirstChild("Head")

	if head ~= nil and head:IsA("BasePart") then
		local glow = Instance.new("PointLight")
		glow.Color = rgb(Config.Monster.EyeGlowRgb)
		glow.Range = Config.Monster.EyeGlowRange
		glow.Brightness = Config.Monster.EyeGlowBrightness
		glow.Parent = head

		trackedEffect(state, glow)
	end
end

--------------------------------------------------------------------------------
-- The corpse (§4.3 step 4). "Corpse remains for 45s, then fades."
--------------------------------------------------------------------------------

--[[
	THE CORPSE IS THE VICTIM'S OWN CHARACTER, DETACHED — not a clone.

	A clone would need Archivable to be true, would duplicate every accessory and its meshes, and would
	arrive at a client as a brand-new model at the same instant the original disappeared. Detaching
	keeps the body that was already replicated and already being looked at, which is the difference
	between "someone died here" and "a prop appeared".

	`player.Character = nil` is what makes it a prop: the player no longer owns it, so nothing the
	client sends moves it. Anchoring every part is the belt to that braces — it also stops the body
	sliding down a hill for 45 seconds, which is comic rather than frightening (§4.9).

	NO BLOOD, NO RAGDOLL, NO DISMEMBERMENT. §4.9 is a business constraint, not a taste one: gore pushes
	the age rating to 13+ and cuts off the audience that plays and spends the most. A body that lies
	there and fades is the whole effect.
]]
--[[
	TAKES A UserId, NOT A Player, SINCE C15. A husk — the body of a player who disconnected mid-round —
	has no `Player` object at all, and it is a legitimate kill target. The only thing this function ever
	wanted from the Player was the id for the corpse's name.

	DETACHING IS THE CALLER'S JOB for the same reason. A live victim's character must be taken from them
	(`player.Character = nil`) before it becomes a corpse, or Roblox removes it with its owner; a husk
	was detached when it was created. `commitKill` does the detach; this function does the body.
]]
local function makeCorpse(victimUserId: number, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid ~= nil then
		-- Stop it standing up, walking, or being steered. WalkSpeed 0 is not a balance number.
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			-- A body should not be a wall. It also should not be a raycast blocker; the kill's line of
			-- sight excludes this whole folder for the same reason.
			part.CanCollide = false
		end
	end

	character.Name = `Corpse_{victimUserId}`
	character.Parent = corpses

	--[[
		The fade, then the removal. Registered as one delayed closure rather than a loop: a corpse that
		is Destroyed early — by a phase change, or by the server closing — leaves a tween pointed at a
		destroyed instance, which is harmless, whereas a running loop is a live coroutine per corpse.
	]]
	task.delay(Config.Monster.CorpseDuration, function()
		if character.Parent == nil then
			return
		end

		local info = TweenInfo.new(Config.Monster.CorpseFadeTime)

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				TweenService:Create(part, info, { Transparency = 1 }):Play()
			end
		end

		--[[
			IT FADES BUT IS NOT DESTROYED. §4.3's "corpse remains for 45s, then fades" is honoured
			visually; the Model itself survives until `clearCorpses` takes it at the end of the round.

			WHY: since C15's redesign the corpse IS the dead player's `player.Character`, and that is
			what keeps `Character ~= nil` true for everybody. Destroying it here would set that property
			to nil for exactly the dead, and `Character == nil` is one line for any client to enumerate —
			the death oracle Amendment A3 removed two other channels to close. The body going invisible
			is the intended §4.3 behaviour; the body ceasing to exist is a leak with a 45-second fuse.

			`clearCorpses` runs on the way into INTERMISSION and IDLE, at which point every player's
			state is being rewritten anyway and the distinction carries nothing.
		]]
	end)
end

-- Every corpse goes when the round does. Bodies from the last round standing in the plaza during
-- INTERMISSION is the kind of thing that reads as a bug in a clip, and clips are the marketing.
local function clearCorpses()
	local folder = corpses

	if folder == nil then
		return
	end

	for _, corpse in folder:GetChildren() do
		corpse:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Health (V05, §4.6). The tug-of-war: salt takes it down, feeding pulls it back.
--------------------------------------------------------------------------------

--[[
	THE GLOW'S BRIGHTNESS IS THE HEALTH READOUT (§4.6). "The intended presentation is diegetic and
	needs no UI at all: the glow gets brighter as it weakens."

	THIS IS THE ONE CHANNEL HEALTH IS ALLOWED TO USE, and it is legal for a reason that is structural
	rather than permitted: §6.2 says health is "readable by others only while `Exposed`", and this
	Highlight EXISTS only while Exposed. There is no arrangement in which it publishes health outside
	the window, because outside the window there is no instance to read.

	THE COLOURS AND THE RAMP ARE BOTH UNDER `Config.Monster` AS OF V08, AND THEY DID NOT USED TO BE.
	This comment previously said they were deliberately split — colours under `Config.Salt` because
	salt paints the glow, the ramp under `Config.Monster` because health decides how bright it burns.
	That split stopped being available when V08 deleted `Config.Salt` entirely, so the colours moved
	to `Monster.ExposedGlowFillRgb`/`OutlineRgb`, beside the ramp `applyExposed` reads them with. See
	Config.luau's comment on `ExposedGlowTransparency*` for the full argument.

	DECLARED ABOVE `applyHealthEvent` BECAUSE THAT FUNCTION CALLS IT. Lua resolves a `local function`
	only from its declaration onward, so the reverse order made this a nil GLOBAL — a runtime error on
	the first salt hit, which `analyze` caught and no test would have.
]]
local function refreshExposedGlow(monster: MonsterState)
	local glow = monster.ExposedGlow

	if glow == nil then
		return
	end

	local full = Config.Monster.ExposedGlowTransparencyFull
	local weakened = Config.Monster.ExposedGlowTransparencyWeakened
	local fraction = MonsterHealth.weakenedFraction(monster.Health, HEALTH_TUNING)

	glow.FillTransparency = full + (weakened - full) * fraction
end

--[[
	APPLY ONE HEALTH EVENT TO A PLAYER'S SERVER STATE. Returns true if the state existed.

	READ, DO NOT CONSTRUCT — `stateFor` here would re-insert a departed player's UserId every time a
	stale timer fired, which is the exact bug `revert()`'s first line was written to avoid. Every
	caller reaches this function only after the server has already established that this player is a
	transformed Aswang, so the entry exists; a missing entry means the round moved on and the answer
	is to do nothing.

	IT RETURNS A BOOLEAN AND NEVER THE HEALTH. The value has exactly one home (see MonsterState) and
	handing it back is how a second copy starts existing — in a payload, in a log line, in an
	attribute somebody added to debug it. Callers that need a decision ask `IsWeakened`.

	THE FLOOR IS NOT ENFORCED HERE. `MonsterHealth.apply` owns it, gated on
	`lune run tests/monster-health.test.luau`, so there is one implementation of §4.6's most
	consequential rule and it is the tested one.
]]
local function applyHealthEvent(userId: number, event: MonsterHealth.HealthEvent): boolean
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return false
	end

	monster.Health = MonsterHealth.apply(monster.Health, event, HEALTH_TUNING)

	--[[
		AND REPAINT THE GLOW, because the brightness IS the health readout and a stale one is a lie.

		Every health change goes through here, so this is the one place that cannot be forgotten.
		`ApplySaltHit` would work without it — it calls `applyExposed`, which repaints on the way in —
		but V06's `HealFromFeed` will not: a feed completed inside a live Exposed window would restore
		25 health and leave the glow reading the pre-feed value for the rest of the ten seconds.
		Survivors would see a monster that looks one hit from death and is not.

		`refreshExposedGlow` early-returns when there is no glow, so this costs a nil check on every
		non-Exposed health change and nothing else.
	]]
	refreshExposedGlow(monster)

	return true
end

--[[
	END THE EXPOSED WINDOW. Idempotent, and safe to call for a player who was never exposed.

	THE BOOLEAN AND THE INSTANCE ALWAYS DIE TOGETHER. A `clearExposed` that destroyed the glow and
	left `Exposed = true` would leave V08 able to kill a monster nobody can see glowing; one that did
	the reverse would leave a permanent mark on one character in the workspace, which is the C04/C14
	failure exactly.
]]
local function clearExposed(userId: number)
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return
	end

	local glow = monster.ExposedGlow

	monster.Exposed = false
	monster.ExposedGlow = nil

	if glow ~= nil then
		glow:Destroy()
	end
end

--[[
	BEGIN THE EXPOSED WINDOW (§4.6): "a hit forces the revert, applies a visible glow for 10s".

	Moved here from `ItemService.applyReveal` at V05 with its reasoning intact, because the
	brightness is now a function of health. A Highlight AND NOT: an attribute (replicates, and
	`check:secrecy` refuses role-named ones for exactly this reason), a CollectionService tag (same),
	a name colour (`TeamColor` and `Team` both replicate and are the classic version of this
	mistake), or a per-client effect (a "hidden" reveal is one a compromised client reads and an
	honest one does not — the worst of both).

	`DepthMode = Occluded` IS A DESIGN DECISION HIDING IN AN ENUM VALUE. `AlwaysOnTop` renders the
	glow THROUGH WALLS, turning a ten-second reveal into a ten-second wallhack on the monster.

	NOTHING HERE IS NAMED FOR A ROLE, and there is no role in this call chain to name: the decision
	that this player was a transformed Aswang was made and discarded back in `ItemService`'s
	`resolveThrow`.
]]
local function applyExposed(player: Player)
	local monster: MonsterState? = monsters[player.UserId]
	local character = player.Character

	if monster == nil or character == nil then
		return
	end

	clearExposed(player.UserId)

	local glow = Instance.new("Highlight")
	local generation = os.clock()

	glow.Name = "SaltReveal"
	glow.FillColor = rgb(Config.Monster.ExposedGlowFillRgb)
	glow.OutlineColor = rgb(Config.Monster.ExposedGlowOutlineRgb)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = character

	monster.Exposed = true
	monster.ExposedGlow = glow
	monster.ExposedGeneration = generation

	refreshExposedGlow(monster)

	task.delay(Config.Items.SaltRevealDuration, function()
		local current: MonsterState? = monsters[player.UserId]

		-- A NEW ENTRY OR A NEWER HIT BOTH DECLINE. `table.clear(monsters)` on the way out of ACTIVE
		-- can drop this player's state entirely and `stateFor` can rebuild it next round with
		-- `ExposedGeneration = 0`, which no live generation ever equals.
		if current == nil or current.ExposedGeneration ~= generation then
			return
		end

		clearExposed(player.UserId)
	end)
end

--------------------------------------------------------------------------------
-- Transform and revert
--------------------------------------------------------------------------------
-- Camouflage and smoke (V07, §4.3).
--------------------------------------------------------------------------------

--[[
	THE PURE MODULE'S VERDICT, MAPPED ONTO THE ONE THAT CROSSES THE WIRE.

	TWO UNIONS RATHER THAN ONE, AND THE PREFIX IS WHY. `CamouflageRules.Verdict` and
	`Types.CamouflageVerdict` contain the same distinctions but not the same strings, so under
	`--!strict` neither can be passed to the other's handler by accident. `Types.luau` records the
	same reasoning for `FeedVerdict`. The two the server owns — CAMO_EXITED and CAMO_WITNESSED — have
	no counterpart here because the pure module never sees a position or a state change.
]]
local function camouflageVerdictFor(verdict: CamouflageRules.Verdict): Types.CamouflageVerdict
	if verdict == "OK" then
		return "CAMO_OK"
	elseif verdict == "NOT_REVEALED" then
		return "CAMO_NOT_REVEALED"
	elseif verdict == "WRONG_PHASE" then
		return "CAMO_WRONG_PHASE"
	elseif verdict == "NO_CHARGE" then
		return "CAMO_NO_CHARGE"
	elseif verdict == "ALREADY_CAMOUFLAGED" then
		return "CAMO_ALREADY"
	elseif verdict == "NOT_TRANSFORMED" then
		return "CAMO_NOT_TRANSFORMED"
	end

	return "CAMO_NO_SLOT"
end

--[[
	TO THE ONE PLAYER WHOSE DISGUISE IT IS. `FireClient`, never `FireAllClients`.

	`Remotes.luau`'s `CamouflageUpdate` entry carries the full argument; the short version is that the
	public half of camouflage needs no remote at all, because an avatar vanishing and a pig appearing
	both replicate as geometry.
]]
local function sendCamouflageUpdate(
	player: Player,
	verdict: Types.CamouflageVerdict,
	form: Types.CamouflageForm?
)
	local payload: Types.CamouflageUpdatePayload = {
		Verdict = verdict,
		Form = form,
	}

	camouflageRemote:FireClient(player, payload)
end

--------------------------------------------------------------------------------
-- Camouflage (V07, §4.3). Enter and exit.
--------------------------------------------------------------------------------

--[[
	HIDE THE PLAYER. (V07, §4.3) The disguise is the ambient entity; this is the half that gets out of
	its way.

	THIS IS THE INVERSION THAT FIXES THE V07 CRITICAL. The first implementation hid the ENTITY (moved
	it to `ServerStorage`) and re-skinned the player to look like it. Measured in Studio, that removed
	an instance from `workspace.AmbientLife` on every client and handed any listener the monster's
	exact position through `ChildRemoved`. Now the entity never moves in the tree and the player is
	what stops being drawn — so the barrio's visible population is identical whether or not anyone is
	hidden, and there is no event to subscribe to.

	NO TINT AND NO SCALE ANY MORE. The old version recoloured and shrank the character toward
	`Config.Monster.CamouflageTintRgb` / `CamouflageAnimalScale`, both of which replicate — one loop
	over `Players` looking for a Humanoid at scale 0.55 named the Aswang outright. An invisible
	character has no such value to read, so deleting that code removed a second finding rather than
	patching it.

	DESCENDANTS, NOT CHILDREN, so accessory handles go too. `captureLook` walks direct children only
	and that is correct for ITS job; leaving a hat and hair at full size floating over a cat is not.

	AND THE NAMETAG. `Humanoid.DisplayDistanceType = None` — without it the disguised cat has the
	player's username printed over it for everyone, which is the loudest possible tell and costs one
	line to remove.
]]
local function hideCharacter(state: MonsterState, character: Model, humanoid: Humanoid)
	local hidden: { HiddenPart } = {}

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(hidden, { Part = descendant, Transparency = descendant.Transparency })
			descendant.Transparency = 1
		end
	end

	state.CamouflageHiddenParts = hidden
	state.CamouflageNameDisplay = humanoid.DisplayDistanceType
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

--[[
	PUT THE PLAYER BACK. Restores exactly what `hideCharacter` captured and nothing else.

	TOTAL, AND SAFE ON A DESTROYED CHARACTER. Death and leaving both reach this, and a part whose
	Parent has gone still answers a property write harmlessly — but the capture list is cleared either
	way, so a second call cannot restore a stale value onto a respawned body.
]]
local function showCharacter(state: MonsterState, humanoid: Humanoid?)
	local hidden = state.CamouflageHiddenParts

	if hidden ~= nil then
		for _, entry in hidden do
			if entry.Part.Parent ~= nil then
				entry.Part.Transparency = entry.Transparency
			end
		end
	end

	local display = state.CamouflageNameDisplay

	if humanoid ~= nil and display ~= nil then
		humanoid.DisplayDistanceType = display
	end

	state.CamouflageHiddenParts = nil
	state.CamouflageNameDisplay = nil
end

--[[
	BECOME THE CAT. (V07, §4.3) One caller: Phase 5's `RequestCamouflage` handler, on a request
	`CamouflageRules.evaluate` has already granted.

	THE ORDER IS: CLAIM, THEN SPEND, THEN CHANGE THE LOOK. A claim that fails must cost nothing — the
	rules module answers NO_SLOT and the charge is still there — so the claim happens first and the
	spend happens only once a slot index is in hand. Reversed, an Aswang in a barrio with no cats left
	would lose its charge to a hide that never happened, and would have to kill again to get it back
	for reasons invisible from inside the game.

	THE MONSTER STAYS TRANSFORMED UNDERNEATH. `Transformed` is not cleared: camouflage is a second
	appearance layer over the monster form, not a revert. That is why `monsterStateOf` checks
	`Camouflaged` BEFORE `Transformed`, and why stepping out returns to the monster rather than to the
	player.

	NO BROADCAST. `MonsterTransformed` is not fired and no new down-remote is either. §4.3's public
	half is that a player avatar is gone and an animal is standing there, and both replicate as
	geometry. A broadcast would be the server STATING what the world already shows — the difference
	between `MonsterTransformed` (a moment nobody may miss) and this (a thing you either saw or did
	not).
]]
--[[
	`at` IS PASSED IN RATHER THAN READ HERE, AND THAT IS A FORWARD-REFERENCE CONSTRAINT, NOT A STYLE
	CHOICE. `rootOf` is declared ~370 lines below this function; calling it here COMPILES and dies at
	runtime with "attempt to call a nil value", which is the trap this file has fallen into three
	times. The caller has already resolved the root — it needs it to pick the form — so handing the
	position down costs nothing and cannot be nil by the time it arrives.
]]
local function enterCamouflage(player: Player, form: Types.CamouflageForm, at: Vector3): boolean
	local monster = monsters[player.UserId]
	local character = player.Character

	if monster == nil or character == nil then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return false
	end

	--[[
		THE CLAIM IS BOUNDED BY WHERE THE MONSTER IS STANDING (Phase 3). `ClaimSlot` refuses unless a
		free territory of this form is within `Config.Ambient.ClaimRadius`, which is what makes the
		territory rule a constraint on the ASWANG rather than a note about the scenery — and what
		bounds how far the claimed entity visibly JUMPS when it is driven onto the monster.

		`at` IS THE SERVER'S OWN COPY of the monster's root position, never a client-supplied one.
		Nothing about this reaches a second player: the refusal goes back to the requester as
		`CAMO_NO_SLOT`, which is a fact about where they themselves are standing.
	]]
	local slotIndex = AmbientService.ClaimSlot(form, at)

	if slotIndex == nil then
		return false
	end

	monster.AmbientSlot = slotIndex
	monster.Camouflaged = true
	monster.CamouflageForm = form
	monster.HasCamouflageCharge =
		CamouflageRules.chargeAfter(monster.HasCamouflageCharge, "CAMOUFLAGE_ENTERED")

	--[[
		HIDE THE PLAYER, DO NOT RE-SKIN THEM. The ambient entity is already standing in the barrio
		looking like a cat; the disguise is achieved by getting the player's own body out of the way
		and walking that entity around instead (`camouflageTick` -> `AmbientService.PuppetSlot`).

		NO `captureLook` CALL HERE, AND THAT IS DELIBERATE. The transform's capture belongs to the
		transform; camouflage captures its own Transparency list in `hideCharacter` and restores it in
		`showCharacter`. Two features sharing one restore path is C04's bug waiting to happen, and the
		old version of this function reached into `captureLook`/`Applied` to do exactly that.

		THE CHARACTER DOES NOT MOVE. The old version pivoted the player to the entity's position; now
		the entity comes to the player, so there is no teleport, nothing to rubber-band against client
		network ownership, and no dependence on a Roblox behaviour this plan never verified.
	]]
	hideCharacter(monster, character, humanoid)

	return true
end

--[[
	STOP BEING THE CAT. (V07, §4.3) FIVE CALLERS, which is why it is idempotent and total: a transform
	request, a salt hit, death, leaving, and the round ending. At least two of them can fire for the
	same player in the same frame — `ApplySaltHit` walks `endFeed` -> `revert`, on a path
	`onPhaseChanged` may also be walking.

	THE SLOT GOES BACK FIRST, so the entity stops being driven before anything else can fail. It is no
	longer a head-count question — nothing was ever removed — but a slot left claimed is an entity
	frozen wherever the monster abandoned it, permanently excluded from the wander loop, which is a
	visible oddity accumulating one per occurrence.

	THE CHARGE DOES NOT COME BACK. `CamouflageRules.chargeAfter` answers CAMOUFLAGE_EXITED with the
	current value, and the grid asserts it: stepping out of a cat is not a feed.
]]
local function exitCamouflage(player: Player)
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Camouflaged then
		return
	end

	AmbientService.ReleaseSlot(monster.AmbientSlot)

	monster.AmbientSlot = nil
	monster.Camouflaged = false
	monster.CamouflageForm = nil

	--[[
		BACK TO THE MONSTER, NOT TO THE PLAYER. `Transformed` was never cleared, so the correct
		restore is the transform's full look — reverting to the player's own appearance here would
		hand a still-transformed Aswang an ordinary-looking body, which is a free permanent disguise
		and a far worse bug than the one this branch prevents.

		A PLAYER WHOSE CHARACTER DIED OR RESPAWNED MID-HIDE gets the state cleared and no look
		written. `AppliedTo` is the character the look went ON, never `player.Character`, for the
		reason `revert` documents at length.
	]]
	--[[
		THEN PUT THE PLAYER BACK, and this touches ONLY what `hideCharacter` captured.

		NO `applyFullLook` AND NO `restoreLook` HERE. Camouflage never changed a colour, a material or
		a scale — it only set Transparency — so the transform's look is still on the character exactly
		as it was, and re-applying it would be a second writer on `revert`'s restore path. Whether the
		monster is still transformed is therefore not this function's business at all, which is why
		the branch that used to ask has gone.

		`AppliedTo` RATHER THAN `player.Character`: the body the disguise went ON, for the reason
		`revert` documents at length — after a respawn the live character is a fresh one that was
		never hidden.
	]]
	local character = monster.AppliedTo or player.Character

	if character == nil then
		return
	end

	showCharacter(monster, character:FindFirstChildOfClass("Humanoid"))
end

--------------------------------------------------------------------------------

local function revert(player: Player)
	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId every time a
	-- stale forced-revert timer fired, growing `monsters` unbounded inside a single ACTIVE phase.
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false
	--[[
		AND THE DISGUISE GOES WITH THE FORM (V07, §4.3). THE FIFTH AND LAST EXIT.

		AFTER `Transformed = false`, deliberately. `exitCamouflage` re-applies the monster look when
		the monster is still transformed; called before this line it would paint the full monster look
		onto a character that the next twenty lines are about to restore to the player. Called here it
		does the one thing that actually has to happen — hands the ambient slot back — and leaves the
		look entirely to this function.

		THIS IS THE EXIT `RequestTransform` USES. There is no `RequestExitCamouflage`: §4.3's only
		reason to leave the disguise is to become the monster again, so a camouflaged Aswang firing
		the transform remote lands here through `validateAndTransform`. One remote, one state change.
	]]
	exitCamouflage(player)
	monster.LastRevertedAt = os.clock()
	-- Any forced-revert timer still in flight for the PREVIOUS transform now belongs to a stale
	-- generation and will decline to act. Without this, a salt-forced revert at C14 followed by a
	-- fresh transform would be cut short by the first transform's expiry timer.
	monster.Generation += 1

	--[[
		THE CHARACTER THE LOOK WAS APPLIED TO, not player.Character.

		Resolving the character at revert time lands on whatever the player is wearing NOW, which after
		a respawn is a fresh body that never transformed — and the revert would then strip it and
		announce it. Cleanup belongs to the thing that was changed.
	]]
	local character = monster.AppliedTo

	if monster.Applied and character ~= nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if humanoid ~= nil then
			for name, value in monster.OriginalScales do
				local scaleValue = humanoid:FindFirstChild(name)

				if scaleValue ~= nil and scaleValue:IsA("NumberValue") then
					scaleValue.Value = value
				end
			end

			if monster.BaseWalkSpeed ~= nil then
				humanoid.WalkSpeed = monster.BaseWalkSpeed
			end

			--[[
				AND THE FEED'S JUMP LOCK (V06), RESTORED HERE SO NO CALLER CAN GET ONE WITHOUT THE OTHER.

				`endFeed` restores all three properties and is the path every feed exit is SUPPOSED to
				take — but two callers reach `revert` with a feed still live: `beginFeed`'s refusal
				branch and `validateAndKillHusk`. Both used to leave `JumpPower = 0` on a character
				that had just been publicly reverted, until the next `feedTick` pass caught it up to a
				quarter-second later. One character reading 0 while everyone else reads 50 is the
				C04/C14 brand, and "it is only 250ms" is the argument that shipped it twice.

				Putting the restore next to the WalkSpeed one makes the class of bug impossible rather
				than absent: a future caller cannot restore the speed and forget the jump, because
				there is no longer a version of this code that does one and not the other. `endFeed`
				still does its own restore for the paths where `revert` early-returns.
			]]
			if monster.FeedBaseJumpPower ~= nil then
				humanoid.JumpPower = monster.FeedBaseJumpPower
			end

			if monster.FeedBaseJumpHeight ~= nil then
				humanoid.JumpHeight = monster.FeedBaseJumpHeight
			end
		end

		restoreLook(monster)
	end

	clearEffects(monster)

	--[[
		ANNOUNCE ONLY WHAT WAS ANNOUNCED. `Transformed` is set before the windup so the spam race is
		closed, which means a revert during the windup reaches here for a player NO CLIENT EVER SAW
		TRANSFORM. Broadcasting a revert for them is an unconditional identity broadcast — inert today,
		and at C14 it is "throw salt at a suspect mid-windup and be told whether you were right".
	]]
	if monster.Announced and character ~= nil then
		local payload: Types.MonsterTransformedPayload =
			{ Character = character, Transformed = false }

		transformedRemote:FireAllClients(payload)
	end

	monster.Applied = false
	monster.Announced = false
	monster.AppliedTo = nil
end

--[[
	THE BROADCAST AND ITS TEACHING CUE, IN ONE PLACE, SO THEIR AUDIENCES CANNOT DIVERGE.

	`MonsterTransformed` is public by design — the tell is the point (§4.3) — and it is
	`FireAllClients`. C23 cues every player about it, and that is safe for two independent reasons:
	the audiences are identical, and the cue's payload is a constant id resolving to "That is the
	tell. Run, or salt it." — no character, no UserId, no position. It would be safe even if the
	broadcast did not exist.

	NARROWING THE CUE BY PROXIMITY IS THE MISTAKE AVAILABLE HERE, and it would look like an
	improvement: only tell players who can actually see it. That subset is computed from the ASWANG'S
	POSITION and delivered per-player — and because the cue is FIRE-ONCE, it would leave a permanent
	per-client mark of "I was near the first transform", outliving the broadcast that justified it.

	An exploit audit made the point that decided this shape: the equality was previously held only by
	two adjacent lines and a comment, and nothing would fail if someone later narrowed one and not the
	other. `check:secrecy` structurally cannot see it. Here, the audience is ONE expression — a change
	to it is a change to both, and shows up as such in a diff. §4.3's "visible to anyone with line of
	sight" is exactly the phrase that will one day invite a filter on the broadcast; when it does, this
	function is where both halves move together.
]]
local function announceTransform(payload: Types.MonsterTransformedPayload)
	local audience = Players:GetPlayers()

	transformedRemote:FireAllClients(payload)

	for _, witness in audience do
		TeachingService.Cue(witness, "CUE_FIRST_TRANSFORM_SEEN")
	end
end

local function transform(player: Player)
	local monster = stateFor(player.UserId)
	local character = player.Character

	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return
	end

	monster.Transformed = true
	monster.Generation += 1
	monster.AppliedTo = character

	local generation = monster.Generation

	-- Capture BEFORE anything is mutated. Everything the revert restores is read here and nowhere else.
	captureLook(monster, character, humanoid)

	-- The windup (§4.3 step 2), and its tell starts NOW rather than when it ends. `Applied` is set
	-- with it, so a revert during the windup cleans up exactly these particles and nothing more.
	monster.Applied = true
	applyWindupLook(monster, character)

	task.wait(Config.Monster.TransformTime)

	-- Still the same transform? A revert during the windup (a disconnect, a phase change, salt at
	-- C14) invalidates it, and applying the look afterwards would leave a permanent monster.
	if monster.Generation ~= generation or not monster.Transformed then
		return
	end

	humanoid.WalkSpeed = humanoid.WalkSpeed * Config.Monster.TransformedSpeedMult

	applyFullLook(monster, character, humanoid)

	--[[
		THE GUARANTEE BEFORE THE ANNOUNCEMENT.

		Registered before the broadcast, deliberately. If FireAllClients throws — and its payload
		carries a Model that can be destroyed under it — the coroutine dies, and with the ordering
		reversed the forced-revert timer would never have been registered, leaving a permanent monster
		clearable only by a phase change.
	]]
	task.delay(Config.Monster.MaxTransformTime, function()
		--[[
			`not monster.Feeding` IS V06'S ADDITION AND IT IS NOT COSMETIC.

			Transform at t=0, kill at t=7, feed until t=12 — and without this clause the 8-second
			forced revert fires at t=8, in the middle of a feed, reverting a monster that §4.3 requires
			to stay "transformed, locked in place, visible" for five full seconds. The feed would then
			be broken by the game's own timer rather than by a survivor, which is the mechanic failing
			silently in the Aswang's favour's opposite direction.

			NOTHING RE-ARMS THIS TIMER, and nothing needs to: `endFeed` reverts on every one of its six
			paths, so a declined forced revert is a revert deferred to the feed's end, not one skipped.
			The form is therefore held for at most MaxTransformTime + FeedDuration, and
			`tests/config.test.luau` pins FeedDuration below MaxTransformTime so that bound stays a
			transform with a feed on the end rather than a feed with a transform on the front.
		]]
		if monster.Generation == generation and monster.Transformed and not monster.Feeding then
			revert(player)
		end
	end)

	monster.Announced = true

	local payload: Types.MonsterTransformedPayload = { Character = character, Transformed = true }

	announceTransform(payload)
end

--------------------------------------------------------------------------------
-- The remote. AntiCheat FIRST, validation SECOND.
--------------------------------------------------------------------------------

local function validateAndTransform(player: Player)
	local monster = stateFor(player.UserId)

	local verdict = TransformRules.evaluate({
		IsAswang = RoleService.IsAswang(player),
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Transformed = monster.Transformed,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		-- Logged, never echoed. Returning the verdict would hand any client a free role oracle: fire
		-- the remote, read NOT_ASWANG or ON_COOLDOWN, and you know who the monster is without seeing it.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused transform for {player.Name}: {verdict}`)
		end

		return
	end

	transform(player)
end

--------------------------------------------------------------------------------
-- The kill (§4.3 steps 3–5, C05)
--------------------------------------------------------------------------------

-- Vector3 -> the plain table pure/KillValidation takes. The pure module cannot mention Vector3: Lune
-- has no Roblox datatypes and the whole module would stop being runnable from a terminal.
local function vec(position: Vector3): KillValidation.Vec3
	return { X = position.X, Y = position.Y, Z = position.Z }
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")

	return if root ~= nil and root:IsA("BasePart") then root :: BasePart else nil
end

--[[
	HOW FAR THIS CHARACTER'S ROOT IS ABOVE ITS OWN FEET (Phase 2).

	MEASURED, NOT CONSTANT, BECAUSE THE TRANSFORM SCALES THE AVATAR (§4.3). The R15 default is about
	3 studs and a scaled monster's is not, so a hard-coded 3 would put the disguise back in the air for
	exactly the state the monster is always in when it is allowed to camouflage.

	`Humanoid.HipHeight` IS THE UNVERIFIED HALF OF THIS AND IT IS IN FOLLOW UPS. This plan has NOT
	confirmed in this codebase whether HipHeight measures from the root's centre or from its underside
	for an R15 rig, and the two answers differ by `root.Size.Y / 2`. The expression below assumes the
	underside. IT IS WRITTEN TO FAIL VISIBLY RATHER THAN SUBTLY: Step 2.6 photographs a puppeted rig
	beside a free one, and if the offset is wrong the rig sits a consistent one-root-half high or low
	in every capture. Confirm it there and correct the sign here; do not infer it from the docs.
]]
local function footOffsetOf(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)

	if humanoid == nil or root == nil then
		return Config.Monster.DefaultFootOffset
	end

	return humanoid.HipHeight + root.Size.Y / 2
end

--[[
	THE ONE CONDITION THAT CANNOT BE PURE (§4.3, "raycast line-of-sight").

	Killing through a wall is the difference between a stalking game and a lag-compensated murder
	simulator, and it is the single most valuable exploit in this game after knowing the role: an
	exploiter who can kill through geometry never has to be seen, which deletes the transform's entire
	risk half.

	The filter excludes both characters — otherwise the ray hits the killer's own torso at zero distance
	and every kill is refused — and the corpse folder, because a body is not cover. Note that a raycast
	hits parts regardless of CanCollide unless RespectCanCollide is set, so making corpses
	non-collidable is NOT enough on its own.

	`workspace:Raycast(origin, direction, params)` returns nil when nothing was hit, which is the
	"clear line" case. This API is not used anywhere else in this repository yet — see Follow Ups; the
	Phase 4 playtest is where it is confirmed rather than assumed, and the failure mode if
	`Enum.RaycastFilterType.Exclude` is wrong for this engine version is that EVERY kill is refused,
	which is loud rather than silent.
]]
--[[
	DROP EXPIRED BURSTS AND ASK WHETHER ANY LIVE ONE CROSSES THIS SEGMENT. (V07, §4.3)

	SWEPT LAZILY, INSIDE THE READER, rather than by a seventh `task.spawn` tick. There is at most one
	live burst per Aswang and the readers already run per-kill and per-throw, so a dedicated timer
	would be a thread that exists to delete one table entry a minute. Back-to-front so `table.remove`
	does not skip the element after the one it removes.

	THE ADAPTER IS THE ONLY ROBLOX-SHAPED PART. `vec()` already converts a Vector3 into the plain
	`{X,Y,Z}` the pure modules take — it exists for `KillValidation` and does exactly this job — so
	the geometry itself stays in `CamouflageRules.smokeBlocks`, where the test can enumerate it.
]]
--[[
	IS ANYONE CLOSE ENOUGH TO WATCH THIS HAPPEN? (V07, §4.3)

	THE SERVER'S CHECK, NOT THE PURE MODULE'S, and the split is the same one `FeedRules` makes with
	the leash: `CamouflageWitnessRadius` needs the positions of other characters, which is a DataModel
	read, and the pure module deals only in the four inputs §4.3 names.

	WHY THE RULE EXISTS: watching a player become a pig from four studs away is not a disguise, it is
	a magic trick with a witness. `CamouflageWitnessRadius` is pinned above `KillRange` in
	`tests/config.test.luau` so the monster must be further from everyone than it could kill them
	from — otherwise it could kill a survivor and vanish before that survivor's partner, standing at
	kill range watching, had anything to report.

	THE REQUESTER IS SKIPPED AND THE DEAD ARE NOT COUNTED. A husk or a corpse has no live root in
	`Players`, so a monster hiding beside the body it just made is unwitnessed — which is right, and
	is exactly the corpse-as-bait play §4.3 built the feed for.
]]
local function isUnwitnessed(player: Player): boolean
	local character = player.Character
	local root = if character ~= nil then rootOf(character) else nil

	if root == nil then
		return false
	end

	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end

		local otherCharacter = other.Character
		local otherRoot = if otherCharacter ~= nil then rootOf(otherCharacter) else nil

		if
			otherRoot ~= nil
			and (otherRoot.Position - root.Position).Magnitude
				<= Config.Monster.CamouflageWitnessRadius
		then
			return false
		end
	end

	return true
end

local function smokeBlocksSegment(from: Vector3, to: Vector3): boolean
	local now = os.clock()

	for index = #smokeBursts, 1, -1 do
		local burst = smokeBursts[index]

		if now >= burst.ExpiresAt then
			table.remove(smokeBursts, index)
			continue
		end

		if CamouflageRules.smokeBlocks(vec(from), vec(to), vec(burst.Centre), burst.Radius) then
			return true
		end
	end

	return false
end

--[[
	TELL THE PEOPLE WHO CAN SEE IT (V07, §4.3), AND NOBODY ELSE.

	THE AUDIENCE IS ONE EXPRESSION, deliberately rather than tidily — `announceTransform`'s header
	records why. When someone later wants to narrow or widen this, a change to the audience is a
	change to the whole send, visible as such in a diff, rather than two adjacent loops that drift.

	NEVER `FireAllClients`. `NoiseCue`'s pattern, for `NoiseCue`'s reason: a broadcast carrying a
	position hands every client a live index of where the monster is the instant it tries to escape —
	readable from a compromised client with no exploit beyond listening, and strictly more than V13's
	90s-to-30s tracker will ever give the survivors. The distance test happens HERE, on the server;
	there is no client-side filter and there must not be one.

	THE POSITION IS EXACT RATHER THAN QUANTISED, unlike `NoiseCue`'s. Noise carries 60 studs, far past
	what a listener can see, so its position is quantised because the payload would otherwise state
	more than the world does. Smoke's send radius is 40 and the cloud is 18: everyone who receives
	this is close enough to WATCH it form, so an exact centre states nothing they will not see
	rendered a frame later. IF `SmokeCueRadius` IS EVER RAISED WELL PAST VISUAL RANGE, THIS REASONING
	EXPIRES and the position must be quantised to `Config.Noise.CueGridStuds`.

	NO PLAYER FIELD. `Types.SmokeBurstPayload` is a position, a duration and a radius. Smoke is fired
	only by the Aswang, so a UserId here would be a role broadcast with a location attached — the
	single worst payload this game could produce, and `check:secrecy` matches `killer\w*` and the
	enumerated role tokens rather than a field called `Source`.

	THE REQUESTER IS IN THE AUDIENCE by the same distance test as everyone else, not by a special
	case. It is standing at the centre so it passes trivially — and writing it as a special case would
	be the first line of a version of this that treats the Aswang differently, which is the shape
	`.claude/lessons/absence-is-observable.md` is about.
]]
--[[
	CAN THIS PLAYER ACTUALLY SEE THE BURST? (V07, §4.3) THE FIX FOR THE SMOKE-CUE LEAK.

	The first version selected the audience on straight-line distance ALONE, and an exploit audit was
	right about what that costs. Only the Aswang can fire smoke, so RECEIVING this payload is the
	statement "an Aswang is at this exact coordinate". A survivor thirty-nine studs away behind a wall
	renders nothing — an occluded emitter draws nothing — but a compromised client logs the position
	and narrows the field to whoever is standing there. That is the shape `revert`'s header already
	names: a "hidden" reveal a compromised client reads and an honest one does not, which is the worst
	of both.

	SO THE COMMENT'S CLAIM IS NOW ENFORCED RATHER THAN ASSERTED. `Remotes.luau` justifies sending an
	exact, unquantised position on the grounds that "everyone who receives this is close enough to
	WATCH the cloud form". That was true of an honest client with line of sight and false of the
	audience the code actually selected. With this test the two agree, and the exact position stays
	honest because every receiver can see the thing it describes.

	NOT `hasLineOfSight`, DELIBERATELY. That function now consults `smokeBlocksSegment`, so a live
	cloud would block the cue announcing itself — and worse, the FIRST burst would suppress its own
	message. This is a plain geometry raycast with the same exclusions and none of the smoke logic.

	BOTH CHARACTERS ARE EXCLUDED. The ray starts inside the Aswang's own body, so without excluding
	it every cast would stop at zero distance and nobody would ever be told.
]]
local function canSeeBurst(centre: Vector3, witnessRoot: BasePart, source: Model?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filter: { Instance } = { witnessRoot.Parent :: Instance }

	if source ~= nil then
		table.insert(filter, source)
	end

	-- Bodies are not cover, exactly as the kill path already rules.
	local folder = corpses

	if folder ~= nil then
		table.insert(filter, folder)
	end

	local husks = RoundService.GetHusksFolder()

	if husks ~= nil then
		table.insert(filter, husks)
	end

	params.FilterDescendantsInstances = filter

	local offset = witnessRoot.Position - centre

	-- A zero-length cast is the requester standing at the centre. Trivially visible.
	if offset.Magnitude <= 0 then
		return true
	end

	return workspace:Raycast(centre, offset, params) == nil
end

local function sendSmokeBurst(centre: Vector3, source: Model?)
	local payload: Types.SmokeBurstPayload = {
		Position = centre,
		Duration = Config.Monster.SmokeDuration,
		Radius = Config.Monster.SmokeRadius,
	}

	for _, witness in Players:GetPlayers() do
		local character = witness.Character
		local root = if character ~= nil then rootOf(character) else nil

		if
			root ~= nil
			and (root.Position - centre).Magnitude <= Config.Monster.SmokeCueRadius
			and canSeeBurst(centre, root, source)
		then
			smokeRemote:FireClient(witness, payload)
		end
	end
end

--[[
	MAY THIS PLAYER HIDE, AND IF SO, AS WHAT? (V07, §4.3)

	THE ROLE CHECK IS FIRST AND IT IS `RoleService`'S ANSWER, NOT AN INFERENCE FROM `monsters`. A
	player with no monster state is not the Aswang, but the converse is what matters: `stateFor` is
	called from several paths and an entry existing is not a role.

	A NON-ASWANG IS TOLD NOTHING AT ALL — no `CamouflageUpdate`, not even a refusal. That is the one
	place this differs from `validateAndTransform`'s shape, and it is deliberate: any verdict on the
	wire for a player who is not the monster is a free role oracle for anyone willing to spam a
	remote. An Aswang gets its real verdict, because every value in `CamouflageVerdict` concerns the
	receiver's own business.
]]
local function validateAndCamouflage(player: Player)
	if not RoleService.IsAswang(player) then
		return
	end

	local monster = monsters[player.UserId]

	if monster == nil then
		return
	end

	--[[
		ALREADY HIDING MEANS "STOP", AND IT IS RESOLVED BEFORE THE RULES MODULE IS ASKED.

		`CamouflageRules.evaluate` would answer ALREADY_CAMOUFLAGED, correctly — it is a refusal to
		START a second hide, which is what that function is about. Exiting is a different verb and it
		is unconditional: a monster that could not get out of a cat because the phase changed
		underneath it would be stuck as scenery for the rest of the round.
	]]
	if monster.Camouflaged then
		exitCamouflage(player)
		sendCamouflageUpdate(player, "CAMO_EXITED", nil)
		return
	end

	--[[
		WHERE THE MONSTER IS STANDING IS NOW PART OF THE QUESTION (Phase 3). Which forms are available
		depends on which territories are within `ClaimRadius`, so the pick needs a position — and a
		character that has not loaded has no answer rather than a default one.

		NO `CamouflageUpdate` ON THIS PATH, matching the role check above. A missing character is a
		frame of respawn, not a refusal worth naming, and every verdict on the wire is a thing an
		attacker can time.
	]]
	local requesterCharacter = player.Character
	local requesterRoot = if requesterCharacter ~= nil then rootOf(requesterCharacter) else nil

	if requesterRoot == nil then
		return
	end

	--[[
		ANNOTATED AT THE ASSIGNMENT. Without the annotation the value arrives inferred as plain
		`string` and every downstream use of it rejects — the same widening
		`.claude/lessons/pure-module-unions-widen-in-lists.md` describes, reaching this file through
		`AmbientRoster.Roster`'s element type. Declaring the local re-imposes the union here, once,
		instead of at each of the three places it is used.
	]]
	local form: Types.CamouflageForm? = AmbientService.PickAvailableFormNear(requesterRoot.Position)

	-- Annotated for the reason `form` is, one screen up: the union widens on the way out otherwise.
	local verdict: CamouflageRules.Verdict = CamouflageRules.evaluate({
		HasBeenRevealed = monster.HasBeenRevealed,
		HasCharge = monster.HasCamouflageCharge,
		MonsterState = monsterStateOf(monster),
		Phase = RoundService.GetPhase(),
		SlotAvailable = form ~= nil,
	})

	--[[
		TWO CHECKS RATHER THAN ONE `or`, AND NOT FOR STYLE. A compound refinement — `verdict ~= "OK"
		or form == nil` — does not narrow `form` past the branch: it comes out as plain `string` and
		the literal union rejects it. Split, the second `if` narrows properly.

		The verdict is reported from the first branch either way, because NO_SLOT is precisely what
		the rules module answers when `SlotAvailable` was false.
	]]
	if verdict ~= "OK" then
		-- V07. The transform path logs its refusals and this did not, which made a whole Studio
		-- session unreadable: the only camouflage line in Output was the rate limiter's.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused camouflage for {player.Name}: {verdict}`)
		end

		sendCamouflageUpdate(player, camouflageVerdictFor(verdict), nil)
		return
	end

	if form == nil then
		sendCamouflageUpdate(player, "CAMO_NO_SLOT", nil)
		return
	end

	--[[
		THE WITNESS CHECK IS LAST, AFTER THE RULES MODULE HAS SAID YES. It is the only refusal that
		walks `Players` and measures distances, so it runs once per otherwise-legal request rather
		than on every spammed one — `hasLineOfSight`'s placement in the kill path, for its reason.
	]]
	if not isUnwitnessed(player) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused camouflage for {player.Name}: WITNESSED`)
		end

		sendCamouflageUpdate(player, "CAMO_WITNESSED", nil)
		return
	end

	--[[
		THE WINDUP (V07, §4.3). `Config.Monster.CamouflageEnterTime`, and it is the counterplay.

		§4.3's whole design is that risky acts are VISIBLE while they happen, and Config's own comment
		beside this number says so: "a hide that is instant is a hide with no counterplay". The number
		shipped and the behaviour did not — an audit found it declared and never read — so for a while
		this game had the sentence without the mechanic. During these 0.8s the Aswang is still fully
		visible, still its own body, and still killable and saltable.

		NOTHING HAS BEEN SPENT YET, WHICH IS WHAT MAKES AN INTERRUPTION A REAL VICTORY. The charge is
		spent and the slot claimed inside `enterCamouflage`, below and after the wait, so a hide
		broken here costs the monster the attempt and nothing else — there is no unwind path to get
		wrong, and no way for an interrupted windup to leak a claimed slot.

		THE GENERATION IS `revert`'s, NOT A NEW ONE. Every path that invalidates a hide in flight —
		a salt hit, death, the round ending, a forced revert — funnels through `revert`, which bumps
		`monster.Generation`. Capturing it here and comparing after the wait means all four abort this
		for free, and a second counter would be a second thing to remember to bump.

		AND THE WHOLE VERDICT IS RE-ASKED, not just the generation. The phase can end, the charge can
		be spent by a path nobody has written yet, and the roster can be exhausted by another claim.
		Re-running `evaluate` is cheap and is the only way this cannot grant on stale inputs.
	]]
	local generation = monster.Generation

	task.wait(Config.Monster.CamouflageEnterTime)

	if monsters[player.UserId] ~= monster or monster.Generation ~= generation then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Camouflage windup interrupted for {player.Name}`)
		end

		return
	end

	--[[
		RE-READ AFTER THE WINDUP, NOT REUSED FROM BEFORE IT. `CamouflageEnterTime` has elapsed and the
		monster has been walking the whole time, so the territories in range are not the ones that
		were in range when it pressed the key. Reusing the earlier position would let a monster start
		the windup on a pig pen and finish it on the basketball court, which is the constraint
		defeated by a timer.
	]]
	local recheckCharacter = player.Character
	local recheckRoot = if recheckCharacter ~= nil then rootOf(recheckCharacter) else nil

	if recheckRoot == nil then
		return
	end

	local stillForm: Types.CamouflageForm? =
		AmbientService.PickAvailableFormNear(recheckRoot.Position)

	local recheck: CamouflageRules.Verdict = CamouflageRules.evaluate({
		HasBeenRevealed = monster.HasBeenRevealed,
		HasCharge = monster.HasCamouflageCharge,
		MonsterState = monsterStateOf(monster),
		Phase = RoundService.GetPhase(),
		SlotAvailable = stillForm ~= nil,
	})

	--[[
		SPLIT, NOT ONE COMPOUND `or` — a combined condition does not narrow `stillForm` past the
		branch and it comes out as plain `string`, which the literal union then rejects. The same
		widening cost several rounds earlier in this chunk; see `AmbientService`'s FORM_IDS header.
	]]
	if recheck ~= "OK" then
		if Config.Debug.VerboseLogging then
			print(
				`[MonsterService] Camouflage windup failed revalidation for {player.Name}: {recheck}`
			)
		end

		return
	end

	if stillForm == nil then
		return
	end

	--[[
		THE WITNESS CHECK RUNS AGAIN, and this is the half that makes the windup worth having. Someone
		can WALK INTO RANGE during those 0.8 seconds — that is the counterplay §4.3 asks for, and
		checking only before the wait would make the window decorative.
	]]
	if not isUnwitnessed(player) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Camouflage windup witnessed for {player.Name}`)
		end

		sendCamouflageUpdate(player, "CAMO_WITNESSED", nil)
		return
	end

	--[[
		CAPTURED BEFORE THE BRANCH. Luau's nil-refinement on `form` does not survive into the `if`
		body below, so `form` reads as plain `string` there and the payload's optional-union field
		rejects it. Binding it here is the same fix `AmbientService.Start` needed for the same reason.
	]]
	local wearing: Types.CamouflageForm = stillForm

	if enterCamouflage(player, wearing, recheckRoot.Position) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] {player.Name} camouflaged as {wearing}`)
		end

		sendCamouflageUpdate(player, "CAMO_OK", wearing)
	end
end

--[[
	MAY THIS PLAYER DROP A CLOUD? (V07, §4.3)

	SAME GATE AS CAMOUFLAGE, AND THAT IS A DECISION RATHER THAN A SPEC READING. §4.3 frames smoke
	entirely as the answer to a salt hit — "taking a salt hit forces a revert and leaves the Aswang
	glowing… to stop that from being a death sentence, it has one smoke ability" — so the gate costs
	the mechanic nothing: you are revealed exactly when you want it. What it buys is that an
	unrevealed Aswang cannot plant a cloud on its own head in the middle of a group, and that both
	abilities in this chunk live behind one flag with one setter. A V16 balance question.

	NO VERDICT REACHES A NON-ASWANG, for `validateAndCamouflage`'s reason. Smoke has no down-remote
	for refusals at all — the only thing it ever sends is the burst itself, to the people who can see
	it — so a refused request is silent by construction rather than by care.
]]
local function validateAndSmoke(player: Player)
	if not RoleService.IsAswang(player) then
		return
	end

	local monster = monsters[player.UserId]

	if monster == nil then
		return
	end

	local character = player.Character
	local root = if character ~= nil then rootOf(character) else nil

	if root == nil then
		return
	end

	local now = os.clock()

	local verdict: CamouflageRules.SmokeVerdict = CamouflageRules.evaluateSmoke({
		HasBeenRevealed = monster.HasBeenRevealed,
		Phase = RoundService.GetPhase(),
		Now = now,
		LastBurstAt = monster.LastSmokeBurstAt,
		Cooldown = Config.Monster.SmokeCooldown,
	})

	if verdict ~= "OK" then
		return
	end

	monster.LastSmokeBurstAt = now

	--[[
		THE CLOUD IS RECORDED BEFORE IT IS DRAWN. `smokeBursts` is what `hasLineOfSight` and
		`ItemService` consult; the `FireClient` below is presentation. Written in this order so that
		there is no frame in which a client has been told about a cloud the server does not yet
		enforce.
	]]
	table.insert(smokeBursts, {
		Centre = root.Position,
		Radius = Config.Monster.SmokeRadius,
		ExpiresAt = now + Config.Monster.SmokeDuration,
	})

	sendSmokeBurst(root.Position, character)
end

local function hasLineOfSight(killerRoot: BasePart, targetRoot: BasePart): boolean
	--[[
		SMOKE BREAKS IT, AND THIS IS WHERE "BREAKS LINE OF SIGHT" BECOMES A RULE (V07, §4.3).

		ASKED BEFORE THE RAYCAST, because it is cheap arithmetic over at most one live burst and the
		raycast is not — and because the answer does not depend on geometry the map author controls.

		THE SAME FUNCTION FOR BOTH DIRECTIONS, WHICH IS THE PROPERTY WORTH KEEPING. A cloud that
		stopped the monster killing but not the survivors throwing would make smoke a gift to the
		survivors; the reverse would make it a free kill button. `smokeBlocks` is symmetric in its two
		points, so there is no version of this that is asymmetric by accident.

		IT DOES NOT CARE WHO PLANTED IT. The monster is blinded by its own cloud, which is §4.3's
		design — smoke "covers a disengage", and a disengage is not a kill.
	]]
	if smokeBlocksSegment(killerRoot.Position, targetRoot.Position) then
		return false
	end

	local params = RaycastParams.new()

	--[[
		BUILT AS A LIST, not as a literal with a `corpses :: Instance` cast in it. The plan proposed the
		cast and flagged it for confirmation; the analyzer answered first — `Folder?` does not cast to
		`Instance`, because the optional is a union and the two are unrelated types.

		Doing it this way is also the honest reading of the nil case: if Start() has not run there is no
		corpse folder, and therefore nothing to exclude. An excluded nil would have been silently
		tolerated at runtime and silently wrong the day the folder mattered.
	]]
	local filter: { Instance } = { killerRoot.Parent :: Instance, targetRoot.Parent :: Instance }
	local folder = corpses

	if folder ~= nil then
		table.insert(filter, folder)
	end

	--[[
		HUSKS TOO, SINCE C15, AND FOR THE IDENTICAL REASON THE CORPSE FOLDER IS HERE: a body is not
		cover. The comment above already states that a raycast hits parts regardless of CanCollide —
		which is why anchoring husks and clearing their collision (`RoundService.onPlayerRemoving`) is
		NOT sufficient on its own and this exclusion is still required.

		Without this, quitting while standing in a doorway leaves permanent cover for every survivor
		for the rest of the round — the ray stops on your abandoned body — and two alts turn a
		chokepoint into a safe room. A disconnected player affecting a live fight is precisely what
		the corpse exclusion exists to prevent, arriving through a folder that did not exist when that
		rule was written.
	]]
	local husks = RoundService.GetHusksFolder()

	if husks ~= nil then
		table.insert(filter, husks)
	end

	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true

	local origin = killerRoot.Position
	local result = workspace:Raycast(origin, targetRoot.Position - origin, params)

	return result == nil
end

--------------------------------------------------------------------------------
-- The feed (§4.3, V06). What replaced the kill cooldown.
--------------------------------------------------------------------------------

--[[
	THE ONLY FUNCTION IN THIS FILE THAT SENDS ANYTHING ABOUT A FEED. FireClient, to one player.

	A TYPED LOCAL RATHER THAN AN INLINE TABLE, for `SearchService.sendUpdate`'s reason: `FireClient`
	takes `...any`, so an inline literal is checked against nothing and a typo'd field name ships. The
	annotation is what makes `Types.FeedUpdatePayload`'s absent-field argument enforceable rather than
	aspirational, and it is what `check-secrecy.mjs` resolves the payload back to when it scans the
	fire site.

	`HoldSeconds` IS ZERO ON EVERY ENDING. Only a live feed has a duration; a completion and an
	interruption both send 0, so a client cannot read a timing difference off which one it got.
	`SearchUpdatePayload` sets the same rule for the same reason.
]]
local function sendFeedUpdate(player: Player, verdict: Types.FeedVerdict)
	local payload: Types.FeedUpdatePayload = {
		Verdict = verdict,
		HoldSeconds = if verdict == "FEED_STARTED" then Config.Monster.FeedDuration else 0,
	}

	feedRemote:FireClient(player, payload)
end

--[[
	WHAT KIND OF BODY IS THIS? (V06, §4.7) The first live use of `Enums.BodyKind`, which V02 declared
	and deliberately wired nowhere.

	ANSWERED BY PARENT FOLDER, and that is not a shortcut — it is where the distinction actually
	lives. `makeCorpse` reparents a body into `workspace.Corpses` and renames it `Corpse_{userId}`;
	`RoundService.onPlayerRemoving` reparents a departing character into `workspace.Husks` as
	`Husk_{userId}`. The two folders ARE the two kinds.

	AND IT IS WHY `FeedRules` DOES NOT MODEL THE HUSK -> CORPSE TRANSITION. That transition already
	exists, one screen down: `validateAndKillHusk` marks the husk killed in `RoundService` and calls
	`makeCorpse` on the same Model, which moves it between these two folders. A husk that has been
	killed IS a corpse by the time anything asks, so the rule "a husk is not feedable until it has
	been killed" needs no clock and no second state — it is this function returning a different word.

	NAME MATCHING IS DELIBERATELY NOT USED. `Corpse_{userId}` would work today and would silently
	start lying the moment anything renames a body; the parent is what the rest of this file already
	treats as authoritative (`clearCorpses` iterates it, the kill's raycast excludes it wholesale).

	nil FOR ANYTHING ELSE, INCLUDING A DESTROYED MODEL. `clearCorpses` Destroys bodies on the way into
	INTERMISSION, which sets `Parent` to nil — and `FeedRules` reads nil as NOT_A_CORPSE and ends the
	feed. That is the corpse-destroyed exit, and it costs no extra code.
]]
local function bodyKindOf(body: Model): Types.BodyKind?
	local parent = body.Parent

	if parent == nil then
		return nil
	end

	if parent == corpses then
		return Enums.BodyKind.Corpse
	end

	if parent == RoundService.GetHusksFolder() then
		return Enums.BodyKind.Husk
	end

	return nil
end

--[[
	HOW FAR THE FEEDER HAS STRAYED FROM THE BODY. `SearchService.holdDistance` with a corpse in place
	of a container, and the nil case means the same thing: something stopped existing, so break the
	hold rather than error inside the tick.

	RESOLVED FROM BOTH SIDES EVERY TICK, not cached. The corpse is anchored and cannot move, so a
	cached corpse position would be correct — but the FEEDER moves, which is the entire point of the
	leash, and a character that is replaced underneath a feed (a respawn, a `LoadCharacterAsync` from
	`RoundService`) must read as nil rather than as a stale distance of zero.
]]
local function feedDistance(player: Player, body: Model): number?
	local bodyRoot = rootOf(body)
	local character = player.Character
	local root = if character ~= nil then rootOf(character) else nil

	if bodyRoot == nil or root == nil then
		return nil
	end

	return (bodyRoot.Position - root.Position).Magnitude
end

--[[
	THE ONLY WAY A FEED ENDS. Six paths reach here and every one of them must:

	  1. the tick's deadline (via completeFeed, which calls this first)
	  2. salt — `ApplySaltHit`
	  3. walking past the leash, or the body ceasing to be a corpse — the tick
	  4. dying, or the character going away — `watchCharacter`
	  5. the round leaving ACTIVE — `onPhaseChanged`
	  6. disconnecting — `onPlayerRemoving`

	`verdict` IS nil WHEN THE CALLER SENDS ITS OWN MESSAGE. `completeFeed` sends FEED_OK and must not
	be followed by a FEED_INTERRUPTED; every other caller passes FEED_INTERRUPTED. This is
	`SearchService.releaseHold`'s contract verbatim, and it is copied rather than reinvented because
	the failure it prevents — two contradictory messages for one ending — is the same failure.

	SAFE TO CALL FOR A PLAYER WHO IS NOT FEEDING. Three of the six paths fire for players who were
	not, and an early return is cheaper than six callers checking.

	IT CALLS `revert`, AND THAT IS §4.3 STEP 4 ARRIVING LATE ON PURPOSE. Under v1.3 `commitKill`
	reverted immediately; V06 moved that here, because §4.3 requires the feed to happen "transformed
	… and visible" and a monster that reverted a frame after the kill is neither. Every feed therefore
	ends in a revert, whichever of the six paths got here — which is also what stops a broken feed
	leaving a permanent monster standing in the barrio.
]]
local function endFeed(userId: number, verdict: Types.FeedVerdict?)
	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId, which is
	-- the bug `revert()`'s first line and `applyHealthEvent`'s first line were both written to avoid.
	local monster: MonsterState? = monsters[userId]

	if monster == nil or not monster.Feeding then
		return
	end

	-- STATE FIRST, THEN THE WORLD. `revert` below can reach code that asks whether this player is
	-- feeding; it must already read false by then, or a re-entrant path finds a half-ended feed.
	monster.Feeding = false
	monster.FeedBody = nil
	monster.FeedEndsAt = nil

	local player = Players:GetPlayerByUserId(userId)

	if player ~= nil then
		--[[
			UNLOCK FIRST, THEN REVERT, AND BOTH WRITE THE SAME WALKSPEED.

			`revert()` restores `BaseWalkSpeed` too — but only when the player is still `Transformed`,
			and it early-returns otherwise. At least one path reaches here with that already false: the
			tick's NOT_TRANSFORMED branch fires BECAUSE a revert has happened. Leaving the unlock to
			`revert` would therefore strand WalkSpeed at 0 on exactly the path a salt hit takes, which
			is the most common interruption in the game.

			BaseWalkSpeed, NOT THE TRANSFORMED SPEED. C14 restored the captured transformed value onto
			an un-transformed player and left one character in the barrio reading 20 while everyone
			else read 16 — a permanent role brand with the full gate green over it.
		]]
		local character = player.Character
		local humanoid = if character ~= nil
			then character:FindFirstChildOfClass("Humanoid")
			else nil

		if humanoid ~= nil then
			if monster.BaseWalkSpeed ~= nil then
				humanoid.WalkSpeed = monster.BaseWalkSpeed
			end

			if monster.FeedBaseJumpPower ~= nil then
				humanoid.JumpPower = monster.FeedBaseJumpPower
			end

			if monster.FeedBaseJumpHeight ~= nil then
				humanoid.JumpHeight = monster.FeedBaseJumpHeight
			end
		end

		monster.FeedBaseJumpPower = nil
		monster.FeedBaseJumpHeight = nil

		revert(player)
	end

	if verdict == nil then
		return
	end

	-- The player may have left between the top of this function and here; `endFeed`'s nil-verdict
	-- callers are the ones who know that, but a re-check costs a comparison and a departing player is
	-- a warn in the log otherwise.
	if player ~= nil then
		sendFeedUpdate(player, verdict)
	end
end

--[[
	THE FEED RAN ITS COURSE. THE ONLY PATH THAT PAYS ANYTHING (§4.3, §4.6).

	`endFeed` FIRST, so the state is already clean before the rewards land. `HealFromFeed` reads
	`monsters[userId]` and `FeedCompleted`'s listener may too; both should see a monster that has
	finished feeding, not one mid-teardown.

	THE HEAL GOES THROUGH `MonsterService.HealFromFeed`, WHICH GOES THROUGH `pure/MonsterHealth`. Not
	`monster.Health += Config.Monster.FeedHeal`, which would be a second implementation of §4.6's
	arithmetic — one that does not cap at MaxHealth, does not repaint the Exposed glow, and is not
	covered by `tests/monster-health.test.luau`. V05 built that seam and wrote "V06, on a COMPLETED
	feed" on it; this is the call it was written for.

	THE GLOW REPAINT IS NOT OPTIONAL AND IT IS ALREADY HANDLED. `applyHealthEvent` calls
	`refreshExposedGlow` on every health change, and V05's comment there names this exact case: a feed
	completed inside a live Exposed window would otherwise restore 25 health and leave the glow reading
	the pre-feed value for the rest of the ten seconds — survivors looking at a monster that appears
	one hit from death and is not. Nothing to add here; do not add a second repaint.
]]
local function completeFeed(player: Player)
	endFeed(player.UserId, nil)

	MonsterService.HealFromFeed(player.UserId)

	--[[
		AND V07'S HALF. Fired here and nowhere else, so an interrupted feed cannot pay it — see the
		event's own comment. V06 connects no listener; `FeedCompleted` has no subscriber until V07,
		which is the same state `SearchService.ItemFound` shipped in at V03.
	]]
	MonsterService.FeedCompleted:Fire(player)

	--[[
		FEED_OK LAST, after the heal and after V07's seam. The client is being told a thing that has
		already fully happened server-side — it draws no conclusion the server has not already reached,
		and it cannot be raced by a listener that errors.

		`endFeed` ABOVE WAS PASSED nil PRECISELY SO THIS LINE IS THE ONLY MESSAGE. Two messages for one
		ending — FEED_INTERRUPTED then FEED_OK — is `SearchService.releaseHold`'s stated failure mode.
	]]
	sendFeedUpdate(player, "FEED_OK")
end

--[[
	START A FEED. ONE CALLER: `commitKill`, on a kill the server has already validated (§4.3).

	THERE IS NO `RequestFeed` AND THERE MUST NOT BE. §4.3: "After a kill, the Aswang MUST feed on the
	corpse for 5 seconds." An opt-in feed is a feed the Aswang declines, and declining costs nothing
	once the kill cooldown has stopped being the gate — which is the whole point of the chunk. §4.3's
	own bullet says the mechanic exists so the monster "cannot chain-kill, because it is pinned to the
	body it just made"; a remote a client can simply not fire deletes that property. It also means this
	chunk adds no `OnServerEvent` handler, no `AntiCheatService.Consume` site and no `Config.AntiCheat
	.Budgets` entry — the strongest anti-cheat property available here is the absence of an entry point.

	THE VALIDATION STILL RUNS, EVEN THOUGH THE SERVER IS THE ONLY CALLER. `FeedRules.evaluate` is not
	guarding against a client here; it is guarding against the server having changed its mind between
	`makeCorpse` and this line — a phase that ended, a body that failed to parent, a killer whose
	character went away inside `commitKill`. Refusing on those is how a feed that cannot work becomes
	a log line instead of a monster locked in place forever.

	AND A REFUSED FEED STILL OWES A REVERT. §4.3 step 4 says the transform ends after a kill; V06 moved
	that revert into `endFeed`, so a feed that never starts has to do it here or the killer stays a
	monster until `MaxTransformTime` — which, because the forced-revert timer learns to decline while
	feeding (Step 2.5), it might not even do. This is the single easiest line in the chunk to omit and
	the hardest to notice: the symptom is a monster that occasionally never reverts.
]]
local function beginFeed(player: Player, body: Model)
	local monster: MonsterState? = monsters[player.UserId]

	if monster == nil then
		return
	end

	local distance = feedDistance(player, body)

	local verdict = FeedRules.evaluate({
		MonsterState = monsterStateOf(monster),
		BodyKind = bodyKindOf(body),
		-- nil means the killer or the body has no root part any more. `math.huge` rather than a
		-- sentinel number: FeedRules refuses a non-finite distance by the same guard that refuses a
		-- NaN one, so "we could not measure" and "too far" resolve to one OUT_OF_RANGE.
		Distance = if distance ~= nil then distance else math.huge,
		Phase = RoundService.GetPhase(),
		Range = Config.Monster.FeedLeashStuds,
	})

	if verdict ~= "OK" then
		-- LOGGED, NEVER ECHOED, on the same terms as the transform and the kill refusals above. There
		-- is no client to echo to here, and the property is kept anyway: a verdict that could safely
		-- be echoed is the one worth having.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused feed for {player.Name}: {verdict}`)
		end

		revert(player)

		return
	end

	monster.Feeding = true
	monster.FeedBody = body
	monster.FeedEndsAt = os.clock() + Config.Monster.FeedDuration

	--[[
		THE LOCK (§4.3, "locked in place"). AN AFFORDANCE, NOT THE AUTHORITY — `feedTick`'s leash is
		what actually holds a feed to a body, because a client owns its own character's physics and can
		ignore every line below. This is what makes an honest client stand still.

		GUARDED ON `BaseWalkSpeed`, SO THE RESTORE CANNOT FAIL. Do not lock what you cannot unlock: one
		character reading WalkSpeed 0 for the rest of the round is a map-wide role brand that
		`check:secrecy` cannot see. The nil case is unreachable — `captureLook` sets it at the start of
		every transform and FeedRules refuses a feed by anyone untransformed — and it is guarded anyway,
		because "unreachable" is what C04 and C14 both were.
	]]
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil

	if humanoid ~= nil and monster.BaseWalkSpeed ~= nil then
		monster.FeedBaseJumpPower = humanoid.JumpPower
		monster.FeedBaseJumpHeight = humanoid.JumpHeight

		-- 0 is on `check-config.mjs`'s IDIOMATIC list; these are not knobs. "Cannot move" has one
		-- value and it is not a balance number, exactly as `makeCorpse`'s own `WalkSpeed = 0` says.
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	sendFeedUpdate(player, "FEED_STARTED")
end

--[[
	THE TICK. Four exits and one completion, four times a second.

	IT ITERATES `monsters`, NOT A SEPARATE FEED TABLE, and that is the one-authority decision from
	Step 2.1 paying off: there is nothing here that can disagree with the state, and nothing that
	`onPhaseChanged`'s `table.clear` could leave behind. The table holds at most one entry per player
	who has ever fired RequestTransform this round — realistically one — so the skip is free.

	ASSIGNING TO FIELDS OF A VALUE DURING A GENERALISED-FOR IS DEFINED BEHAVIOUR IN LUAU, and unlike
	`SearchService.searchTick` this loop never removes a KEY: `endFeed` clears three fields on an
	entry and leaves the entry in place. Strictly safer than the precedent it copies.

	`mayContinue`, NOT `evaluate`. The state here IS `FEEDING`, which `evaluate` refuses with
	ALREADY_FEEDING by design — see `pure/FeedRules`'s header for why these are two functions and not
	one with a flag.
]]
local function feedTick()
	local now = os.clock()

	for userId, monster in monsters do
		if not monster.Feeding then
			continue
		end

		local player = Players:GetPlayerByUserId(userId)

		-- Path 6's backstop. `onPlayerRemoving` normally gets here first; this covers the window
		-- where it has not fired yet. No verdict — there is nobody left to send one to.
		if player == nil then
			endFeed(userId, nil)
			continue
		end

		--[[
			DEAD, or a mid-round SPECTATOR. An allowlist against `Enums.PlayerState.Alive`, never
			`~= Dead`: `PlayerState` has four values and exactly one of them may be feeding. This is
			`pure/PlayerBody`'s rule and C01's bug wearing its fourth hat.

			IT IS NOT REDUNDANT WITH THE FORM CHECK BELOW. A killed Aswang aborts the round (§4.8), so
			today an Aswang cannot be DEAD mid-feed — but V08 builds the buntot pagi strike, which is
			a second way for a feeding monster to stop being alive, and this line is what makes that
			end the feed rather than leave a tick running against a corpse's corpse.
		]]
		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
			endFeed(userId, "FEED_INTERRUPTED")
			continue
		end

		local body = monster.FeedBody

		if body == nil then
			endFeed(userId, "FEED_INTERRUPTED")
			continue
		end

		local distance = feedDistance(player, body)

		--[[
			THE LEASH, THE FORM AND THE BODY, ALL THREE THROUGH THE PURE MODULE.

			  · past FeedLeashStuds        -> OUT_OF_RANGE     the monster walked off its meal
			  · the form went away         -> NOT_TRANSFORMED  a salt hit, or any revert
			  · the body left the folder   -> NOT_A_CORPSE     `clearCorpses` destroyed it
			  · the round left ACTIVE      -> WRONG_PHASE      `onPhaseChanged` normally gets here first

			ALL FOUR COLLAPSE TO ONE `FEED_INTERRUPTED` ON THE WIRE. `Types.FeedVerdict`'s comment says
			why: telling the Aswang WHICH of these broke its feed hands it "was that salt, or did I
			drift?" for free, and that is a fact about a survivor's aim it should have to work out by
			looking.
		]]
		local verdict = FeedRules.mayContinue({
			MonsterState = monsterStateOf(monster),
			BodyKind = bodyKindOf(body),
			Distance = if distance ~= nil then distance else math.huge,
			Phase = RoundService.GetPhase(),
			Range = Config.Monster.FeedLeashStuds,
		})

		if verdict ~= "OK" then
			if Config.Debug.VerboseLogging then
				print(`[MonsterService] Feed broken for {player.Name}: {verdict}`)
			end

			endFeed(userId, "FEED_INTERRUPTED")
			continue
		end

		local endsAt = monster.FeedEndsAt

		if endsAt ~= nil and now >= endsAt then
			completeFeed(player)
		end
	end
end

--[[
	The commit, in the ONE order that works. Every line here depends on the one above it.

	  1. The corpse first, because it steals the character from the player. RoundService.MarkKilled
	     applies the body rule, which destroys a character the victim still owns — so if this ran second
	     there would be no body left to make a corpse out of.
	  2. The state change, which is what makes the victim uncounted, bodiless and unkillable.
	  3. The revert (§4.3 step 4, "after a kill it must revert"). This is ALSO what starts the cooldown,
	     because revert() stamps LastRevertedAt — §4.3 step 5's "30s from revert" is not implemented as
	     a separate timer anywhere, it is this line.
	     V06 REPLACED THIS LINE WITH `beginFeed`, AND THE REVERT MOVED TO THE END OF THE FEED. §4.3's
	     "Feeding — what replaced the kill cooldown" requires the feed to happen "transformed, locked
	     in place, visible": a monster that reverted a frame after the kill is none of those, and there
	     would be nothing for a survivor to walk up to. `endFeed` now calls `revert` on all six of its
	     paths, so the transform still always ends — FeedDuration seconds later than it used to, which
	     also moves the start of the KillCooldown countdown by the same amount. That is a BALANCE
	     change for V16 to judge and it is recorded in Config's KillCooldown comment.
	     A REFUSED FEED STILL REVERTS, inside `beginFeed`. Without that line a feed that cannot start
	     leaves a permanent monster, because the forced-revert timer below now declines while feeding.
	  4. The broadcast, last, so no client is told about a kill the server has not finished committing.
]]
local function commitKill(killer: Player, victim: Player, victimCharacter: Model, position: Vector3)
	--[[
		THE CHARACTER IS **NOT** DETACHED, AND THAT IS THE C15 REDESIGN IN ONE LINE.

		This used to read `victim.Character = nil`, so a dead player had no character for the rest of
		the round. An exploit audit found that `Character == nil` is itself the death oracle — one line
		to enumerate, a `GetPropertyChangedSignal` away from a timestamped death alert, and since the
		Aswang is never a ghost, each nil eliminates a candidate. Amendment A3 deleted two channels to
		close exactly that.

		So the corpse STAYS as `victim.Character`. Every player has a character at all times, and what a
		client can still learn is what §4.7 and A3 always intended: a body lying in the Barrio is a dead
		player, and you have to look at it. Under §5's `StreamingEnabled` (C17) a distant corpse does not
		replicate at all, which makes that literally true. Before C17 it is PARTIAL — everything
		replicates, so a property scan still tells a corpse from a walker.

		`RoundService.MarkKilled` is safe with the body attached because `BodyTransitions` answers KEEP
		for every GHOST cause: nothing downstream revokes or replaces it.
	]]
	makeCorpse(victim.UserId, victimCharacter)

	-- `true` = this death was a validated kill, so it counts towards §4.8's attrition win. Every other
	-- caller passes nothing: a reset or a fall makes the player a GHOST but must NOT credit the Aswang,
	-- or one survivor pressing the stock reset button ends a 3-player round as ASWANG_WINS.
	RoundService.MarkKilled(victim, true)

	--[[
		§4.3 STEP 4, VIA THE FEED (V06). `victimCharacter` is the corpse by this line — `makeCorpse`
		above mutated it in place and reparented it into `workspace.Corpses` — so this is the body the
		Aswang is pinned to, handed over directly rather than looked up. There is no corpse registry
		precisely because this line already holds the Model.
	]]
	beginFeed(killer, victimCharacter)

	--[[
		TWO FIELDS AND ONE RECIPIENT. See Types.PlayerKilledPayload: the killer appears nowhere in it,
		in any form, and nothing in this repo would catch it if it did. Built as a typed local rather
		than an inline table because FireClient takes `...any` and an inline literal is checked against
		nothing at all.

		FireClient, NOT FireAllClients, SINCE AMENDMENT A3 — and the change is not cosmetic.

		Broadcast, this was a stronger death oracle than the `AlivePlayerCount` field that A3 removed:
		that field made an attacker infer the position from replicated character logs, and this handed
		it over directly, timestamped, with the victim named. Removing one while keeping the other
		would have been theatre.

		THE OLD DEFENCE WAS "THE CORPSE REPLICATES ANYWAY", AND §5 MAKES IT FALSE. The corpse is a
		Model in `workspace.Corpses`, and C17 turns `StreamingEnabled` on from the start — under which
		a corpse 200 studs away does not reach a client and this remote did. The two were never
		equivalent; they only looked it on an unstreamed baseplate.

		The victim keeps it because the victim is the one client with a use for it:
		`CameraFXController.onPlayerKilled` plays a first-person death reaction, which was until now
		firing on seven screens belonging to people who had not died. That controller needs no change —
		its `isMine` branch simply becomes the only branch it ever takes.
	]]
	local payload: Types.PlayerKilledPayload = { VictimUserId = victim.UserId, Position = position }

	killedRemote:FireClient(victim, payload)
end

--[[
	KILLING A HUSK (§6.4, C15) — a body whose owner disconnected mid-round.

	Separate from `validateAndKill` because a husk has no `Player`, and every input that function
	reaches for through one — `RoleService.IsAswang(target)`, `RoundService.GetPlayerState(target)`,
	`target.Character` — has to come from somewhere else. Sharing the path would mean threading a
	`Player?` through all of it and nil-checking at five sites, which is how the target half of the
	rule quietly stops being validated.

	WHAT IS GUARANTEED RATHER THAN CHECKED, and why:

	  · `TargetIsAswang = false`. `RoundService.onPlayerRemoving` ABORTS the round when the Aswang
	    leaves, so the Aswang never has a husk. This is the one assumption here and it is enforced
	    somewhere a reader can go and look at.
	  · `TargetState = ALIVE`. `RoundService` only creates a husk for a player whose stored state was
	    ALIVE at the moment they left.

	Everything else — phase, killer role, transform, cooldown, range, line of sight — runs through the
	SAME `KillValidation.evaluate` and the SAME raycast a live kill does. A husk is not an easier
	target, it is the same target with nobody watching the screen.
]]
local function validateAndKillHusk(
	killer: Player,
	targetUserId: number,
	huskCharacter: Model
): boolean
	local killerCharacter = killer.Character

	if killerCharacter == nil then
		return false
	end

	local killerRoot = rootOf(killerCharacter)
	local targetRoot = rootOf(huskCharacter)

	if killerRoot == nil or targetRoot == nil then
		return false
	end

	local monster = stateFor(killer.UserId)

	local verdict = KillValidation.evaluate({
		Phase = RoundService.GetPhase(),
		KillerUserId = killer.UserId,
		TargetUserId = targetUserId,
		KillerIsAswang = RoleService.IsAswang(killer),
		TargetIsAswang = false,
		KillerState = RoundService.GetPlayerState(killer),
		TargetState = Enums.PlayerState.Alive,
		Transformed = monster.Announced,
		-- V06, §4.3: a monster pinned to a corpse may not take a second body. The husk path is the
		-- SECOND entrance to that window, so it is gated identically to validateAndKill.
		Feeding = monster.Feeding,
		KillerPos = vec(killerRoot.Position),
		TargetPos = vec(targetRoot.Position),
		Range = Config.Monster.KillRange,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused husk kill by {killer.Name}: {verdict}`)
		end

		return false
	end

	if not hasLineOfSight(killerRoot, targetRoot) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused husk kill by {killer.Name}: NO_LINE_OF_SIGHT`)
		end

		return false
	end

	--[[
		STATE FIRST, THEN THE BODY. `MarkHuskKilled` drops the husk entry and stamps the owner's stored
		state to GHOST — so a player reconnecting one frame later is resolved as dead, which is what
		happened to them. It deliberately does NOT destroy the Model, because the next line turns that
		same Model into the corpse.

		No `PlayerKilled` remote fires. Since Amendment A3 that remote goes to the VICTIM alone, and the
		victim is not connected — there is nobody to send it to. The corpse is the signal, exactly as it
		is for everyone else.
	]]
	RoundService.MarkHuskKilled(targetUserId)

	--[[
		THE REVERT, and it is not optional garnish. §4.3 step 4 reverts after a kill, and `revert()` is
		what stamps `LastRevertedAt` — which IS the kill cooldown, per KillValidation's inputs above.
		Omitting it here would let the Aswang clear a plaza full of husks with no cooldown between them,
		which is the exact opposite of what the husk is for.
	]]
	revert(killer)

	makeCorpse(targetUserId, huskCharacter)

	return true
end

local function validateAndKill(killer: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)

	--[[
		NO PLAYER? IT MAY STILL BE A HUSK. Falling straight out here is what made a disconnect a free
		escape: the body stood in the Barrio and nothing could touch it.
	]]
	if target == nil then
		local husk = RoundService.GetHuskCharacter(targetUserId)

		if husk ~= nil then
			validateAndKillHusk(killer, targetUserId, husk)
		end

		return
	end

	local killerCharacter = killer.Character
	local targetCharacter = target.Character

	if killerCharacter == nil or targetCharacter == nil then
		return
	end

	local killerRoot = rootOf(killerCharacter)
	local targetRoot = rootOf(targetCharacter)

	if killerRoot == nil or targetRoot == nil then
		return
	end

	local monster = stateFor(killer.UserId)

	local verdict = KillValidation.evaluate({
		Phase = RoundService.GetPhase(),
		KillerUserId = killer.UserId,
		TargetUserId = target.UserId,
		KillerIsAswang = RoleService.IsAswang(killer),
		TargetIsAswang = RoleService.IsAswang(target),
		KillerState = RoundService.GetPlayerState(killer),
		TargetState = RoundService.GetPlayerState(target),
		--[[
			`Announced`, NOT `Transformed`, and the difference is a whole mechanic.

			`Transformed` is set BEFORE the 1.2s windup (to close the spam race), so using it here would
			let the Aswang fire RequestTransform and RequestKill back to back and kill during the windup
			— before anyone with line of sight has seen anything. §4.3 step 2 calls that windup "visible
			to anyone with line of sight" and it is the entire risk half of the risk/reward. `Announced`
			is set only after MonsterTransformed(true) has gone out, so the kill unlocks exactly when the
			warning does.
		]]
		Transformed = monster.Announced,
		--[[
			V06, §4.3: "it cannot chain-kill, because it is pinned to the body it just made."

			WITHOUT THIS FIELD THAT SENTENCE IS FALSE. V06 defers the post-kill revert to the end of
			the feed, and `revert()` is what stamps `LastRevertedAt` — so through the whole feed the
			killer is Announced with a stale timestamp and `ON_COOLDOWN` cannot fire. See the field's
			own comment in `pure/KillValidation`.
		]]
		Feeding = monster.Feeding,
		KillerPos = vec(killerRoot.Position),
		TargetPos = vec(targetRoot.Position),
		Range = Config.Monster.KillRange,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if verdict ~= "OK" then
		-- LOGGED, NEVER ECHOED, and the stakes are higher than they are for the transform. Returning
		-- TARGET_IS_ASWANG or NOT_ASWANG to a client is a role oracle you can walk through the whole
		-- server with: fire at each player in turn and read which answer comes back.
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused kill by {killer.Name}: {verdict}`)
		end

		return
	end

	-- LAST, because it is the only check that touches the physics engine. Everything cheap has already
	-- said yes, so the expensive one runs at most once per legitimate attempt — which is what makes an
	-- unauthorised spam of this remote cost the server nothing beyond a table lookup.
	if not hasLineOfSight(killerRoot, targetRoot) then
		if Config.Debug.VerboseLogging then
			print(`[MonsterService] Refused kill by {killer.Name}: NO_LINE_OF_SIGHT`)
		end

		return
	end

	commitKill(killer, target, targetCharacter, targetRoot.Position)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPhaseChanged(phase: Types.RoundPhase)
	--[[
		CORPSES ARE CLEARED ON THE WAY INTO THE LOBBY, NOT ON THE WAY OUT OF ACTIVE.

		Clearing on "any phase that is not ACTIVE" destroyed the winning kill's body within a frame of
		creating it: MarkKilled calls EndRound, which sets ENDING, which fires PhaseChanged, which
		landed here — while `commitKill` was still on the stack that made the corpse. §4.3 step 4 says
		the body remains 45s, and §4.8 calls the end screen "the screenshot people share", so the one
		round where the bodies matter most was the one round that had none.

		ENDING keeps them. INTERMISSION and IDLE clear them, which still satisfies the original reason
		for clearing at all — no bodies from last round standing in the plaza while people wait.
	]]
	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
		clearCorpses()
	end

	if phase == Enums.RoundPhase.Active then
		return
	end

	-- Leaving ACTIVE ends every transform and clears the cooldowns, so a new round never begins with
	-- a monster still standing or an Aswang serving the last round's penalty.
	for userId in monsters do
		local player = Players:GetPlayerByUserId(userId)

		--[[
			AND EVERY LIVE FEED (V06, §4.3), BEFORE THE REVERT BELOW AND BEFORE `table.clear`.

			`endFeed` restores the movement lock and then reverts, so this line does the loop's revert
			for a feeder and the one below early-returns. Ordered this way rather than after, because a
			revert that ran first would leave `Feeding` true on an entry `table.clear` is about to drop
			— and with it a character whose WalkSpeed is 0 and whose owner is standing in the lobby.

			`FEED_INTERRUPTED` RATHER THAN nil: the player is still here and their client is still
			drawing a feed bar. The round ending is exactly the case where a client left holding a
			stale bar looks like the game froze.
		]]
		endFeed(userId, "FEED_INTERRUPTED")

		--[[
			AND EVERY LIVE DISGUISE (V07, §4.3), BEFORE THE REVERT AND BEFORE `table.clear`.

			`table.clear` below drops the handle, and with it `AmbientSlot` — the only record that a
			pig somewhere in the barrio is parked in ServerStorage with the monster standing in its
			place. Nothing else knows the entity exists, so a slot missed here is claimed for the rest
			of the SERVER's life, not merely the round: the population shrinks by one every time a
			round ends on a camouflaged Aswang, silently, until the disguise stops working.

			That is `clearExposed`'s argument two lines down, with a worse object at the end of it —
			an orphaned Highlight is visible, and an unclaimed slot is arithmetic nobody can see.
		]]
		if player ~= nil then
			exitCamouflage(player)
		end

		if player ~= nil then
			revert(player)
		end

		--[[
			AND EVERY EXPOSED WINDOW (V05, §4.6), BEFORE `table.clear` BELOW DROPS THE HANDLE.

			`table.clear(monsters)` on its own would orphan the Highlight: the state that knows the
			instance is gone, the instance is still parented to a living character, and nothing will
			ever destroy it. A player hit at second 419 of a 420-second round would then glow in the
			lobby permanently — where the glow is no longer an event anybody witnessed and is simply
			a mark on one of the five people standing there.

			CLEARED ON `ENDING` TOO, not just on INTERMISSION/IDLE. The split that keeps corpses
			through ENDING (see above) is about scenery; this is about a mark on a player, and §4.8
			calls the end screen "the screenshot people share".

			This clear runs for a player still PRESENT but not yet reverted; it does NOT cover a
			player who has already left, because `onPlayerRemoving` removed them from `monsters`
			before this loop could see them. That exit is closed in `onPlayerRemoving` itself, which
			calls `clearExposed` before nilling the entry — see the comment there for what nilling
			alone leaves behind.
		]]
		clearExposed(userId)
	end

	table.clear(monsters)
end

--[[
	A TRANSFORMED ASWANG THAT DIES MUST REVERT. C04's deferred finding, marked "a required input to
	C05" because until this chunk there was no way to die at all.

	Note what this is NOT: the kill path does not go through Humanoid.Died — the victim's character is
	detached and anchored, never killed, because §4.9 wants a fade rather than a death animation. This
	connection covers everything else that can end a character mid-transform: falling out of the world,
	a Studio-side reset, and whatever C14's salt does to a monster standing in a bad place.

	Reverting on death also charges the cooldown, because revert() stamps LastRevertedAt. That is the
	right answer rather than a side effect: dying while transformed should cost the Aswang the same 30
	seconds a completed hunt does, or falling off a roof becomes a free reset.
]]
local function watchCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid == nil then
		return
	end

	humanoid.Died:Connect(function()
		--[[
			V07: AND THE DISGUISE, FIRST. A monster that dies wearing a pig must hand the slot back
			before anything else runs — `revert` below will not, because it knows nothing about the
			ambient roster, and the character is about to stop existing.

			The ordering matches `ApplySaltHit`: out of the cat, then out of the feed, then out of the
			monster. Each step leaves the next one looking at the state its comments were written for.
		]]
		exitCamouflage(player)
		-- V06: a feeding Aswang that dies stops feeding, and gets its Humanoid back to the honest
		-- baseline before anything else looks at it. Today only a fall or a reset reaches here — a
		-- killed Aswang aborts the round — but V08's buntot pagi strike is a second way, and this is
		-- the line that makes the feed end rather than tick on against a body that has no driver.
		endFeed(player.UserId, "FEED_INTERRUPTED")
		revert(player)
	end)
end

--[[
	THE GLOWING CORPSE, closed here rather than left to the ten-second timer. Moved from
	`ItemService`'s `PlayerAdded` handler at V05, with its reasoning, because the Highlight moved.

	`makeCorpse` DETACHES the victim's character and keeps it in the workspace for `CorpseDuration`.
	A Highlight parented to that character goes with it — so a player revealed by salt and then
	killed leaves a glowing body lying in the Barrio, which reads to every passer-by as "this corpse
	was the monster". The reveal is supposed to be an event that expires, not a label on a body.

	The Aswang cannot be killed, so the reachable paths are a reset or a fall while revealed. Cheap
	to close and ugly if it ever shows up in a playtest video.

	NOT FOLDED INTO `revert()`. A revert and an expiry are different events: §4.6 gives the glow ten
	seconds and the revert is instant, so a revert that also cleared the glow would delete nine of
	those seconds and with them the window the buntot pagi needs.
]]
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function()
		clearExposed(player.UserId)
	end)

	-- RoundService turns CharacterAutoLoads off and loads explicitly (Step 1.4), so a character can
	-- already exist by the time this service's Start() runs on a live server.
	local character = player.Character

	if character ~= nil then
		watchCharacter(player, character)
	end
end

--[[
	CLEAR THE GLOW BEFORE DROPPING THE HANDLE, and the order is the whole point.

	V05 shipped this as a bare nil on the reasoning that "the entry goes and the health goes with it",
	which is true of the NUMBER and false of the INSTANCE. `clearExposed` destroys the Highlight it
	holds; nilling the entry only forgets it. An exploit audit traced what that leaves:
	`RoundService.onPlayerRemoving` reparents the departing character into `workspace.Husks` as
	`Husk_{userId}` WITH THE GLOW STILL ON IT, and MonsterService is index 29 in SERVICE_ORDER while
	RoundService starts last — so this handler runs FIRST and the husk is built after the handle is
	already gone. All four exits then miss it: the phase-change loop iterates `monsters`, which no
	longer contains the UserId, and the ten-second timer reads a nil entry and declines.

	The result is a labelled, glowing body naming the round's Aswang, standing in the barrio for the
	whole of ENDING. Masked today only because an Aswang leaving ACTIVE aborts the round — a mask
	owned by a different service, which V08's strike gate or any second source of exposure removes
	without touching this file.

	This is `.claude/lessons/absence-is-observable.md` in the direction the lesson does not spell out:
	the leak is not the health value, it is one character in `workspace` carrying an instance no other
	character has.
]]
local function onPlayerRemoving(player: Player)
	--[[
		THE FEED GOES BEFORE THE ENTRY DOES (V06), for the reason the line below this one exists.

		V05's comment here is the whole argument and it applies unchanged: nilling the entry forgets
		the state, it does not undo what the state did to the world. `RoundService.onPlayerRemoving`
		reparents the departing character into `workspace.Husks` as `Husk_{userId}`, and MonsterService
		runs FIRST in SERVICE_ORDER — so a feed left un-ended here becomes a husk standing in the
		barrio with WalkSpeed 0 and jumping disabled, which is one property scan away from naming the
		round's Aswang. `feedTick`'s `player == nil` branch would eventually reach it and find the
		entry already gone.

		nil VERDICT, NOT `FEED_INTERRUPTED`: there is nobody left to send it to, and `FireClient` to a
		departing player is a warn in the log for no benefit. Same contract as
		`SearchService.releaseHold`'s nil case.
	]]
	endFeed(player.UserId, nil)

	--[[
		AND THE DISGUISE, BEFORE THE ENTRY GOES (V07, §4.3). THE ONE EXIT `onPhaseChanged` CANNOT
		COVER, because this handler removes the UserId from `monsters` and the phase loop iterates
		exactly that table — by the time the round ends there is nothing left to find.

		A slot leaked here is permanent and cumulative in the way described in the phase-change loop:
		the parked entity sits in ServerStorage with nothing holding its index. `ReleaseSlot` is total
		and idempotent precisely so it is safe to call from inside a `PlayerRemoving` handler, where
		one cleanup that throws takes the rest of the handler with it.
	]]
	exitCamouflage(player)

	clearExposed(player.UserId)

	monsters[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- The C14 seam. Two functions, and the reason they are here rather than in ItemService.
--------------------------------------------------------------------------------

--[[
	Is this player currently in the monster form? (C14)

	SERVER ONLY, AND IT IS NOT A ROLE QUERY. It answers a question about a FORM, and the form is
	already public — `MonsterTransformed` broadcasts it to every client by design. What makes it safe
	to expose is that the caller must already hold a UserId it got from somewhere else; this function
	never enumerates, never returns the Aswang, and returns false for every player who is not
	transformed including the Aswang.

	ItemService ANDs this with `RoundService.GetAswangUserId()` before handing a single boolean to
	`pure/ItemThrow`, so the role never enters the pure module at all.
]]
function MonsterService.IsTransformed(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	return monster ~= nil and monster.Transformed
end

--[[
	IS THIS PLAYER AT OR BELOW `WeakenedThreshold`? (V05, §4.6) One half of V08's strike gate.

	§4.6: the buntot pagi "kills only an Aswang that is both Exposed (glowing from a salt hit) and
	Weakened (at or below 25 health). Against anything else it does nothing." V08 ANDs this with
	`IsExposed` and with `RoundService.GetAswangUserId()`, exactly as `ItemService` already ANDs
	`IsTransformed` with the role before handing a single boolean to a pure module — so the role
	never enters the pure layer at all.

	A PLAYER WITH NO MONSTER STATE IS NOT WEAKENED, and that is the safe direction twice over: a
	survivor was never salted, and an Aswang who has not transformed this round has full health. It
	is also the one that cannot be used as a probe — `false` is what every one of the five players
	returns until somebody lands a salt hit.

	`Weakened` IS A PREDICATE, NOT A `MonsterState` MEMBER, and `Enums.luau:69-71` says why: "it is a
	HEALTH PREDICATE — `health <= Config.Monster.WeakenedThreshold` — not a state, and duplicating it
	as an enum member is how two sources of truth for one fact get out of step." Do not add
	`Enums.MonsterState.Weakened`.
]]
function MonsterService.IsWeakened(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	if monster == nil then
		return false
	end

	return MonsterHealth.isWeakened(monster.Health, HEALTH_TUNING)
end

--[[
	FEEDING RESTORES HEALTH (V06, §4.3/§4.6). The seam, declared here and UNWIRED BY V05.

	§4.6: "every kill the Aswang makes heals away one salt hit. That is the tug-of-war the whole
	design turns on." V06 builds the five-second locked feed, validates the corpse, the distance and
	the phase through `pure/FeedRules`, and calls this on completion. V05 owns the number; V06 owns
	the ritual.

	NOT A ROLE QUERY AND NOT AN ENUMERATION, on the same terms as `IsTransformed` above: the caller
	must already hold a UserId it got from somewhere else, and a player with no monster state gets
	`false` rather than an entry created for them.

	CAMOUFLAGE IS NOT RESTORED HERE. §4.3 gives a completed feed two rewards — the heal and the
	camouflage refresh — and V07 owns the second. Splitting them is deliberate: `MonsterService`
	should not grow a charge it cannot yet spend.
]]
function MonsterService.HealFromFeed(userId: number): boolean
	return applyHealthEvent(userId, "FEED")
end

--[[
	A SALT HIT (§4.6, V05). Revert, damage, expose — in that order, and the order is the whole
	correctness of this function.

	IT SHIPPED WRONG ONCE, IN THE OTHER SERVICE, AND AN EXPLOIT AUDIT CAUGHT IT. `ItemService`'s
	first version ran its stun before the revert, so `revert()` wrote `BaseWalkSpeed` (16) over the
	stun's 0 in the same frame — the stun never happened — and four seconds later the stun restored
	the captured TRANSFORMED speed (20) onto a player who was no longer transformed. `WalkSpeed` is
	a replicated property, so any client could poll every character and find the single one reading
	20: a permanent role brand, readable map-wide, with `check:secrecy` green over it. The full story
	is in `ItemService.applyHit`'s header, and the invariant it wrote binds this function too: NO
	PATH ADDED HERE MAY LEAVE A LIVING PLAYER'S HUMANOID PROPERTIES DIFFERENT FROM EVERY OTHER
	LIVING PLAYER'S.

	DAMAGE BEFORE EXPOSE, so the glow's first frame already reads the new health. Exposing first and
	damaging after gives one frame at the old brightness, which is not a leak but is a lie.

	THE REVERT IS `revert()` AND NOT A REIMPLEMENTATION. Everything the salt path needs already
	happens in there: the generation bump that invalidates the in-flight forced-revert timer, the
	`Announced` gate that stops a mid-windup revert broadcasting a transform nobody saw, the
	`LastRevertedAt` stamp that charges the kill cooldown, and the look restoration that resolves
	`AppliedTo` rather than `player.Character`. C04's audit found a second implementation getting the
	last of those four wrong.

	NO GUARD ON WHO CALLS THIS, deliberately: `revert` early-returns for a player who is not
	transformed, `applyHealthEvent` returns false for a player with no state, and `applyExposed`
	does nothing without one. A mistaken call is a no-op rather than a state change. The validation
	that a hit happened at all lives in `ItemService`, next to the request that claimed it.

	DELIBERATELY NOT A KILL AND NOT A `MarkKilled`: §4.6 is counterplay, not a win condition. Salt
	never ends a round, which is why `MonsterHealth.apply` floors it at `WeakenedThreshold`.

	V08 CLOSES THE LOOP AND CHANGES NOTHING. V05, V06 and V07 each landed their share of §4.6's five
	jobs as they built the systems behind them; V08 is the chunk that gives salt a way to be thrown
	at containers-sourced items, and it found all five already here.

	SO THIS IS THE FULL LIST, IN ORDER, AND THE ORDER IS THE FUNCTION'S CORRECTNESS:

	  1. exit camouflage    — before revert, or the character reverts into a cat's parts   (V07)
	  2. interrupt the feed — before revert, so the interruption is exact rather than raced (V06)
	  3. force the revert   — §4.6's headline effect                                        (C14)
	  4. −SaltDamage        — through pure/MonsterHealth, floored at WeakenedThreshold      (V05)
	  5. Exposed for SaltRevealDuration — the glow, whose brightness reads the health       (V05)
	  6. HasBeenRevealed    — through CamouflageRules.revealedAfter, the camouflage gate    (V07)

	`ItemService` IS THE ONLY CALLER, and V08 kept it that way. There is no bare `ForceRevert`, no
	bare `Expose` and no way to damage the monster from outside this function — so there is no path
	that reverts without damaging, damages without revealing, or reveals without opening the gate.
	That property is worth more than any of the six individually: each was added by a different
	chunk, and the only thing that stopped them drifting apart is that they share one entry point.

	ADDING A SEVENTH JOB MEANS EDITING THIS LIST. Adding a second CALLER means arguing with this
	paragraph first.
]]
function MonsterService.ApplySaltHit(player: Player)
	--[[
		THE DISGUISE DIES FIRST (V07, §4.3/§4.6). BEFORE `endFeed`, BEFORE `revert`.

		Salt forces a revert, and a revert out of the MONSTER form while the CAT form stayed on would
		leave a player-shaped nothing wearing a cat: `revert` restores from `OriginalParts`, which
		`applyCamouflageLook` overwrote on top of. Exiting first means `revert` finds the character in
		exactly the state it expects — transformed, un-camouflaged — which is the state every one of
		its comments was written about.

		AND IT IS THE COUNTERPLAY. A survivor who lands salt on a suspicious pig gets a monster, in
		the open, glowing. That is §4.6's reveal doing its job on §4.3's disguise, and it is the
		single most satisfying thing this chunk can produce.
	]]
	exitCamouflage(player)

	--[[
		THE FEED DIES NEXT (V06, §4.3). "Salt it mid-meal and it loses the heal and the camouflage
		refresh, and has to leave the body."

		BEFORE `revert`, NOT AFTER, AND NOT LEFT TO THE TICK. `endFeed` is what withholds both rewards
		— it is the path that fires neither `HealFromFeed` nor `FeedCompleted` — and calling it here
		makes the interruption exact. Left to `feedTick`'s NOT_TRANSFORMED backstop, a hit landing in
		the last quarter-second of a feed races the deadline, and the outcome of §4.3's most important
		counterplay would depend on tick alignment.

		`endFeed` CALLS `revert` ITSELF, so the line below runs a second time and early-returns. That
		redundancy is deliberate and cheap: this function's contract is "revert, damage, expose" and
		removing its own revert on the grounds that a callee happens to do it would make the ordering
		depend on `endFeed`'s internals.

		SAFE FOR A PLAYER WHO IS NOT FEEDING, which is most salt hits. `endFeed` early-returns.
	]]
	endFeed(player.UserId, "FEED_INTERRUPTED")
	revert(player)
	applyHealthEvent(player.UserId, "SALT")
	applyExposed(player)

	--[[
		AND THE GATE OPENS HERE — THE ONLY PLACE IN THE REPO IT EVER DOES. (V07, §4.3)

		"`hasBeenRevealed` is the gate and it is set by the first salt hit, never by anything else.
		'Someone saw it transform' is not knowable server-side; a salt hit is a fact the server
		already owns."

		WHY THIS LINE IS STRUCTURAL AND NOT A CONVENTION. V06 made this function "the ONLY entry point
		for a salt hit; there is no bare `ForceRevert` any more, precisely so a caller cannot revert
		without damaging". V07 inherits that property and extends it: THERE IS NO WAY TO SALT A
		MONSTER WITHOUT REVEALING IT, AND NO WAY TO REVEAL ONE WITHOUT SALTING IT. The flag and the
		damage are set three lines apart, inside the one function every salt hit in the game passes
		through.

		THROUGH THE TRANSITION TABLE, NOT `= true`. `CamouflageRules.revealedAfter` is where "only
		SALT_HIT reveals" is written down and where 16 grid cells assert it. Assigning the boolean
		directly here would work identically today and would put the rule in two places, which is how
		the second one stops being true.

		AFTER `applyExposed`, NOT BEFORE. Nothing in the four lines above reads this field, so the
		order is not load-bearing today — but it states the causality, and it means that if any of
		them ever throws, the monster is not left revealed by a salt hit that did not fully land. The
		failure falls towards the survivors having to throw again, never towards a free camouflage.

		IT IS NEVER UNSET. `revert` does not clear it and neither does the Exposed window expiring;
		§4.3's reveal is a fact about the round, not a ten-second state. The reset is
		`onPhaseChanged`'s `table.clear(monsters)` on the way out of ACTIVE.

		READ, DO NOT CONSTRUCT. `stateFor` here would re-insert a departed player's UserId — `revert()`
		above documents the same trap. A player with no monster state cannot have been salted.
	]]
	local monster: MonsterState? = monsters[player.UserId]

	if monster ~= nil then
		monster.HasBeenRevealed = CamouflageRules.revealedAfter(monster.HasBeenRevealed, "SALT_HIT")
	end
end

--[[
	IS THIS SEGMENT INSIDE A LIVE SMOKE CLOUD? (V07, §4.3) V07'S SEAM FOR `ItemService`.

	SAFE TO EXPOSE FOR `IsExposed`'S REASON: a smoke cloud is ALREADY PUBLIC — there is a visible
	burst standing in the world that every client with line of sight can see, which is the entire
	point of it. This function states nothing a player standing there cannot see, it never enumerates,
	and it takes two positions the caller already holds.

	IT NAMES NO PLAYER IN EITHER DIRECTION. It does not say whose cloud, and it does not ask who is
	throwing. A boolean about a line segment is not a fact about a person.
]]
function MonsterService.SmokeBlocks(from: Vector3, to: Vector3): boolean
	return smokeBlocksSegment(from, to)
end

--[[
	IS THIS PLAYER INSIDE THE EXPOSED WINDOW? (V05, §4.6) The other half of V08's strike gate.

	SAFE TO EXPOSE FOR THE SAME REASON `IsTransformed` IS: being Exposed is ALREADY PUBLIC — there is
	a Highlight on that character that every client with line of sight can see, which is the entire
	point of §4.6's reveal. This function states nothing a player standing there cannot see, it never
	enumerates, and the caller must already hold a UserId it got from somewhere else.

	A PLAYER WITH NO MONSTER STATE IS NOT EXPOSED — false for every survivor, every round, so it is
	useless as a probe.
]]
function MonsterService.IsExposed(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	return monster ~= nil and monster.Exposed
end

--[[
	WHO, IF ANYONE, IS THIS STRIKE ABOUT? (V10, §4.6) `ItemService`'s only way to name a target.

	Returns the candidate's UserId and its distance, or `nil, nil`. `pure/GarlicPlacement`'s
	`DoorwayDistance` convention: the caller gets a distance because the pure module wants one, and
	the service gets the identity because it needs to ask `IsExposed`/`IsWeakened` about it — and
	computing the distance twice is how the two come to disagree.

	IT RESOLVES EXACTLY ONE CANDIDATE, AND THAT CANDIDATE IS THE ASWANG. Not "the nearest player."
	The difference is worth stating because "nearest" is the obvious implementation and it is worse in
	both directions: a survivor standing between the striker and the monster would BLOCK a strike that
	§4.6 says should land, and a striker could learn something from being blocked. Resolving the one
	player the strike could ever be about, and then asking the pure module whether it may land, means
	the crowd is irrelevant and there is nothing to infer from it.

	IT LIVES HERE RATHER THAN IN `ItemService` FOR TWO REASONS, AND THE SECOND IS THE ONE THAT DECIDES.
	`RoundService.GetAswangUserId()` is reachable from both. But `hasLineOfSight` is a file-local in
	THIS file, and it is not a raycast with a filter — it excludes the corpse folder AND the husk
	folder AND both characters, and it consults `smokeBlocksSegment` first. Every one of those
	exclusions is a rule somebody was bitten by (a body is not cover; two alts do not make a safe
	room; smoke breaks it symmetrically). Reimplementing the ray in `ItemService` would be a second
	copy that starts correct and drifts, on the surface where drift is an exploit.

	IT NEVER ENUMERATES AND IT IS NOT A ROLE ORACLE, on `IsTransformed`'s terms: it is SERVER ONLY,
	the return value crosses no wire, and `ItemService` hands the UserId straight back into
	`IsExposed`/`IsWeakened` and then into a pure module that has no role field. The role is resolved
	once, here, and never travels.

	NIL FOR NO CHARACTER, NOT (0,0,0) — `nearestDoorway`'s rule. A player with no root has no position,
	and the origin is a place in the barrio somebody can stand.

	IT RETURNS THE MONSTER STATE AS A THIRD VALUE RATHER THAN THE SERVICE GROWING A `GetMonsterState`
	SEAM. `monsterStateOf` is a file-local and the header's list of seams is a list of FOUR things
	callers may ask about a UserId they already hold; a fifth that answers for any UserId would be a
	probe, where this one answers only about the candidate this function itself resolved. Two new
	seams for V10, not three.

	THE STATE IS NOT A GATE — see `pure/StrikeValidation`'s `TargetState` comment. `monsterStateOf`
	never produces EXPOSED (it is a latch, not an activity), so a gate on it would refuse every cell
	of the grid forever. It is carried so the Done line's grid is literal, and a Weakened, Exposed
	Aswang dies whether this said TRANSFORMED, CAMOUFLAGED or FEEDING.

	THE ASWANG STRIKING ITSELF RESOLVES TO ITSELF AND THAT IS DELIBERATE. Distance 0, line of sight
	trivially true, and `pure/StrikeValidation` then answers on its Exposed/Weakened state exactly as
	it would for a survivor's swing. A guard here would make the monster's own buntot pagi behave
	differently from everybody's, which is a role oracle readable by pressing a key. If the Aswang
	wants to salt itself three times and then kill itself, §4.6 does not forbid it and V11 will score
	it; the item was spent either way.
]]
function MonsterService.ResolveStrikeTarget(
	striker: Player,
	range: number
): (number?, number?, Types.MonsterState?)
	local aswangUserId = RoundService.GetAswangUserId()

	if aswangUserId == nil then
		return nil, nil, nil
	end

	local monster: MonsterState? = monsters[aswangUserId]

	if monster == nil then
		return nil, nil, nil
	end

	local target = Players:GetPlayerByUserId(aswangUserId)
	local strikerCharacter = striker.Character
	local targetCharacter = if target ~= nil then target.Character else nil

	if strikerCharacter == nil or targetCharacter == nil then
		return nil, nil, nil
	end

	local strikerRoot = rootOf(strikerCharacter)
	local targetRoot = rootOf(targetCharacter)

	if strikerRoot == nil or targetRoot == nil then
		return nil, nil, nil
	end

	local distance = (strikerRoot.Position - targetRoot.Position).Magnitude

	--[[
		THE RANGE TEST HAPPENS TWICE, HERE AND IN THE PURE MODULE, AND THAT IS NOT REDUNDANCY.
		This one gates the RAYCAST — the only expensive thing in the path — so an unauthorised spam
		of `RequestStrike` costs a subtraction rather than a physics query. The kill handler makes the
		identical trade for the identical reason ("LAST, because it is the only check that touches the
		physics engine").
	]]
	if distance > range then
		return nil, nil, nil
	end

	if not hasLineOfSight(strikerRoot, targetRoot) then
		return nil, nil, nil
	end

	return aswangUserId, distance, monsterStateOf(monster)
end

--[[
	THE ASWANG DIES (V10, §4.6). The ONLY entry point, and the ordering below is the whole function.

	§4.6: the buntot pagi is "the only thing that kills." `ItemService` decides WHETHER — it owns the
	slot, the remote and `pure/StrikeValidation` — and this owns WHAT HAPPENS, exactly as
	`RequestThrowSalt` decides a hit and `ApplySaltHit` performs one. Returns whether monster state
	existed, never anything about it, on `HealFromFeed`'s terms.

	V10 ENDS AT "THE MONSTER IS DEAD" AND SAYS NOTHING ABOUT WHAT THAT MEANS FOR THE ROUND.
	`RoundService.MarkKilled` currently routes an Aswang death to `RoundResult.Aborted`, on the
	disconnect path's reasoning. For a STRIKE that is the wrong result — the survivors did not abort,
	they won the second win condition — and V11 owns replacing it. Do not change `RoundResult` here:
	§6.5's six invariants and the roster-freeze rule land together in that chunk, and a result changed
	without them is a win condition nobody pinned.

	`causedByKill = false`, DELIBERATELY. That flag increments `state.AswangKills`, which is the
	ASWANG's progress toward ITS win. A survivor killing the monster must not advance the monster's
	counter, and `MarkKilled`'s own comment is right that "a departure simply is not a kill" — neither
	is this.

	THE FOUR TEARDOWNS RUN BEFORE THE DEATH, AND THE ORDER IS `ApplySaltHit`'S, NOT THE OBVIOUS ONE.
	Every one of them removes a REPLICATED difference from a character that is about to become a body
	somebody can walk up to and inspect:

	  1. `exitCamouflage` — FIRST, and this is the ordering `ApplySaltHit` had to discover. `revert`
	     restores from `OriginalParts`, which `applyCamouflageLook` OVERWROTE on top of, so a revert
	     that runs while the disguise is still on leaves "a player-shaped nothing wearing a cat". And
	     `endFeed` CALLS `revert` ITSELF — so exiting camouflage after the feed ends is already too
	     late. It also releases the ambient slot, which `enterCamouflage` names as a leak if orphaned.
	  2. `endFeed` — releases `WalkSpeed = 0`, which is "THE ONE REPLICATED DIFFERENCE A FEED CREATES"
	     per this file's own header. `FEED_INTERRUPTED`, never nil: the struck feeder did not complete
	     a feed, and nil is reserved for `completeFeed`, which sends its own FEED_OK.
	  3. `revert` — restores the captured look. C04's bug was a revert that restored HARDCODED
	     DEFAULTS instead of captured state, permanently branding the ex-Aswang; `restoreLook` is the
	     repaired path and this uses it rather than reimplementing a reset. Runs a second time when
	     the monster was feeding, and early-returns — the same deliberate redundancy `ApplySaltHit`
	     documents, because a contract that removed its own revert on the grounds that a callee
	     happens to do it would make the ordering depend on `endFeed`'s internals.
	  4. `clearExposed` — destroys the Highlight and clears the boolean TOGETHER, which is the
	     invariant that function's header states. A glow orphaned onto a corpse is a permanent,
	     map-wide, remote-free answer to "which body was the monster" — readable after the round by
	     anyone who did not watch it die. That is C04's bug shape exactly.

	IT DOES NOT DESTROY THE CHARACTER AND DOES NOT MAKE A CORPSE. `commitKill` does that for a
	survivor; V12 owns what body a dead Aswang leaves. `MarkKilled` calls `applyBodyRule(player,
	"KILLED")`, which `BodyTransitions` answers KEEP for, so the Aswang's own avatar stays where it
	fell — which is the correct v2.0 behaviour and needs no new code.
]]
function MonsterService.StrikeDown(userId: number): boolean
	local monster: MonsterState? = monsters[userId]

	-- READ, do not construct. `stateFor` here would re-insert a departed player's UserId — the bug
	-- `revert()`'s first line and `applyHealthEvent`'s first line were both written to avoid.
	if monster == nil then
		return false
	end

	local player = Players:GetPlayerByUserId(userId)

	if player == nil then
		return false
	end

	exitCamouflage(player)
	endFeed(userId, "FEED_INTERRUPTED")
	revert(player)
	clearExposed(userId)

	RoundService.MarkKilled(player, false)

	return true
end

--[[
	THE CORPSE FOLDER (C34). Exposed as the FOLDER rather than as an event, mirroring
	`RoundService.GetHusksFolder` and for the same reason: a caller wants to know when a body arrives,
	and `ChildAdded` on a folder that outlives every round is a subscription that cannot go stale
	between a corpse being created and the next one.

	`CosmeticsService` uses it to play the victim's chosen death effect at the body. THAT IS SAFE
	BECAUSE OF WHAT A CORPSE ALREADY IS: it is the victim's own avatar, anchored, in the open, visible
	to anyone with line of sight. An effect on it is seen by exactly the people who can already see the
	body, and it names the victim no more precisely than their own face does.

	IT IS NOT A DEATH BROADCAST, and the difference matters. Since Amendment A3, `PlayerKilled` goes to
	the VICTIM alone — WHICH of the eight are dead is a death oracle the round deliberately does not
	publish. A local burst at a body somebody is looking at publishes nothing; a map-wide sound or a
	global effect would, so `Config.Cosmetics`'s death numbers are a short local puff and there is no
	remote in that path at all.

	Nil before `Start` has run. Callers connect from their own `Start`, which the bootstrap runs after
	every `Init`, and handle nil rather than assuming.
]]
function MonsterService.GetCorpsesFolder(): Folder?
	return corpses
end

function MonsterService.Init()
	table.clear(monsters)
end

function MonsterService.Start()
	local folder = Instance.new("Folder")

	folder.Name = "Corpses"
	folder.Parent = workspace
	corpses = folder

	--[[
		THE CHARGE COMES BACK (V07, §4.3). THE FIRST AND ONLY SUBSCRIBER TO `FeedCompleted`.

		§4.3: "Camouflage is spent on use and only a feed restores it. Once revealed, the Aswang must
		kill to hide." That sentence is the best pressure loop in the design — a revealed monster that
		wants to disappear again has to make a corpse and stand on it, in the open, for five seconds,
		at a place the survivors already know about.

		THIS EVENT AND NOT A CALL INSIDE `completeFeed`, even though this service owns both ends. The
		event is the seam V06 built and documented for V07; a direct call would work identically today
		and would make the next listener — V09's, V13's — the one that has to decide whether to use
		the event or copy the call. One joint, one shape.

		WHY NOBODY HAS TO REMEMBER TO WITHHOLD IT ON AN INTERRUPTION. `completeFeed` is the only firer
		of `FeedCompleted`, and `endFeed` — which all six interruption paths go through — does not
		fire it at all. §4.3's "interrupting a feed is a real victory" is therefore structural: there
		is no code that could grant the refresh on a salted feed, rather than code that carefully
		does not.

		THROUGH `CamouflageRules.chargeAfter`, for `ApplySaltHit`'s reason: the transition is asserted
		over all eight events, so "an interrupted feed restores nothing" is a tested fact rather than
		an absence someone has to notice.

		IT DOES NOT CHECK `HasBeenRevealed`. §4.3 gives a completed feed its two rewards
		unconditionally; the gate is on SPENDING the charge, not on holding one. An unrevealed Aswang
		that feeds restores a charge it already had and still cannot use — which is exactly right, and
		a reveal check here would mean a monster salted AFTER a feed found itself with no charge for
		reasons no player could reconstruct.

		READ, DO NOT CONSTRUCT: `stateFor` would re-insert a departed player.
	]]
	MonsterService.FeedCompleted.Event:Connect(function(player: Player)
		local monster: MonsterState? = monsters[player.UserId]

		if monster == nil then
			return
		end

		monster.HasCamouflageCharge =
			CamouflageRules.chargeAfter(monster.HasCamouflageCharge, "FEED_COMPLETED")
	end)

	--[[
		THE RATE LIMIT LIVES HERE, INLINE, and not inside validateAndTransform — deliberately.

		`check-ratelimit.mjs` matches `AntiCheat\w*[.:](Allow|Check|Consume|RateLimit|Permit)` within
		1200 characters of an `.OnServerEvent:Connect(`. It is a proximity tripwire, by its own
		admission, so a handler that IS rate-limited but does it 250 lines away reads as unguarded and
		fails the build. That is the check being blunt rather than wrong: a reader skimming the connect
		site should be able to see the guard without following a call, and every later handler in this
		game will copy whatever shape this one sets.

		Consume FIRST, before any state is read. A handler that validates first has already done the
		expensive work by the time it refuses, which is what makes a remote worth spamming.
	]]
	Remotes.Get("RequestTransform").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

		validateAndTransform(player)
	end)

	--[[
		V07, §4.3. Same shape as the handler above, for the same reason: `check-ratelimit.mjs` matches
		the Consume call within 1200 characters of the connect site, so the guard is inline and first.
		Consume BEFORE any state is read — a handler that validates first has already done the
		expensive work by the time it refuses, which is what makes a remote worth spamming.

		NO ARGUMENTS FROM THE CLIENT, so there is no `typeof` guard here and nothing to validate about
		the payload. The form is the SERVER's choice — see `Remotes.luau` for why a client-named form
		would be a probe for the live ambient population.
	]]
	Remotes.Get("RequestCamouflage").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestCamouflage") then
			return
		end

		validateAndCamouflage(player)
	end)

	-- V07. Same shape and same reason. No arguments — the burst happens at the requester's own
	-- position, and a position argument would be a "drop a cloud anywhere" primitive whose first use
	-- is dropping one on a survivor's face across the map.
	Remotes.Get("RequestSmoke").OnServerEvent:Connect(function(player: Player)
		if not AntiCheatService.Consume(player, "RequestSmoke") then
			return
		end

		validateAndSmoke(player)
	end)

	-- Same shape as the handler above, for the same reason: `check-ratelimit.mjs` matches the Consume
	-- call within 1200 characters of the connect site, so the guard is visible to a reader skimming the
	-- file and to the gate. Consume FIRST, before the UserId is even looked at.
	Remotes.Get("RequestKill").OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
		if not AntiCheatService.Consume(player, "RequestKill") then
			return
		end

		-- A remote argument is whatever the client sent. `targetUserId` is typed `unknown` rather than
		-- `number` precisely so this line cannot be skipped: without it a table or a function reaches
		-- GetPlayerByUserId and throws inside a connection, which Roblox swallows into one warn.
		if typeof(targetUserId) ~= "number" then
			return
		end

		validateAndKill(player, targetUserId)
	end)

	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	--[[
		THE FEED'S CLOCK (V06). Lifted from `SearchService.Start`, quarter-second cadence and all.

		A LOOP RATHER THAN A `task.delay(FeedDuration)`, and the difference is §4.3's "interruptible".
		A delayed callback knows only that five seconds passed; it cannot notice that the monster
		walked away at second two, and a feed that pays out because nobody was watching is not a
		mechanic. Four times a second is `SearchService`'s cadence for the same reason — the leash is
		six studs and a transformed Aswang covers about five in a quarter-second, so the worst-case
		overshoot is roughly one leash.

		RUNS UNCONDITIONALLY, in every phase. `feedTick` skips every entry that is not feeding, and
		`monsters` is empty outside a round; gating the loop on the phase would be a second copy of
		the phase rule with nothing to gain.
	]]
	task.spawn(function()
		while true do
			feedTick()
			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
		end
	end)

	--[[
		WALK THE DISGUISE (V07, §4.3). ON HEARTBEAT, NOT ON THE 0.25s FEED CADENCE.

		The entity has to track the monster every frame. At four updates a second it would visibly lag
		a walking player by up to a fifth of a second and then snap — and "the cat that stutters" is
		precisely the free tell this whole redesign exists to avoid. The feed's cadence is fine for a
		leash check and wrong for a thing being rendered.

		CHEAP BY CONSTRUCTION. `monsters` is empty outside a round and holds one entry inside one, and
		the body runs only for an entry that is actually camouflaged, so the common case is a table
		scan of one and a comparison.

		THE ENTITY IS DRIVEN TO THE CHARACTER, NEVER THE REVERSE. That direction is the fix for the
		Critical: the player keeps network ownership of their own body and nothing teleports, so there
		is no `PivotTo`-against-ownership behaviour to verify and no rubber-banding to explain.
	]]
	RunService.Heartbeat:Connect(function()
		for userId, monster in monsters do
			if not monster.Camouflaged then
				continue
			end

			local player = Players:GetPlayerByUserId(userId)
			local character = if player ~= nil then player.Character else nil
			local root = if character ~= nil then rootOf(character) else nil

			if root ~= nil and character ~= nil then
				AmbientService.PuppetSlot(monster.AmbientSlot, root.CFrame, footOffsetOf(character))
			end
		end
	end)

	-- Anyone already here. Same reasoning as RoundService.Start's backfill: connect first, then sweep,
	-- and accept that a player arriving in the window is handled twice. watchCharacter is idempotent
	-- only in the sense that a second Died connection calls revert() twice, and revert() early-returns
	-- when the player is not transformed — so the double is harmless.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MonsterService
