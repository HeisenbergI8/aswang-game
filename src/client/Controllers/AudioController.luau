--!strict
--[[
	AudioController — every sound in the game. (C29, §5 and §14.3)

	§14.3's point is the whole reason this file is large: audio is half of horror and it is free.
	Every cue in §5's list lives here — the night bed, wind and distant dogs, footsteps, the
	heartbeat, the transform stinger, the gate, and the sunrise.

	═══ THIS CONTROLLER ADDS NOTHING TO THE NETWORK SURFACE ════════════════════

	No remote is declared, fired or widened for C29. Every cue is derived from data this client
	already receives:

	  · the bed, the one-shots, the gate and the sunrise ← `RoundSnapshot`, already sent every
	    `Config.Round.SnapshotInterval` for the HUD
	  · the stinger and the heartbeat ← `MonsterTransformed`, already `FireAllClients` and public by
	    design (§4.3 — the tell IS the mechanic)
	  · footsteps ← the character's own Humanoid, on this client

	That is C28's shape and it is deliberate: `SkyController` renders the round clock as a sunrise off
	the same snapshot and adds no remote either. `check:remotes` has no new name to learn here and
	`check:secrecy` no new payload to argue with.

	═══ WHAT A COMPROMISED CLIENT LEARNS FROM THIS FILE ════════════════════════

	Nothing it did not already have. Stated per cue at the SECRECY STATEMENT further down, because
	🔒 `exploit-auditor` gates this chunk and the answer belongs at a file:line rather than in a plan
	document nobody re-reads.

	The short version: no cue takes a role as an input, no cue is fired at one player and not
	another, and no Sound this file creates is ever created by the server — every instance here is
	LOCAL to the client that made it, so no other client can read it out of the workspace. The one
	cue §5 asks for that CANNOT be built safely is a heartbeat keyed to an UNTRANSFORMED Aswang; see
	the heartbeat's own comment for why, and the plan's Follow Ups for the spec deviation it implies.

	═══ A BLANK ASSET ID IS A SUPPORTED STATE ═════════════════════════════════

	The sounds are sourced from the Creator Store and APPROVED BY A PERSON — "does this sound scary"
	is not something any check answers. So the ids arrive after this code does, and until they do,
	every cue must create, position, range, log and destroy its Sound exactly as it will in the end
	and simply play nothing. That is the precedent the transform stinger set at C04 and it is now the
	rule for all ten cues: the spatial and lifecycle behaviour is testable today, and sourcing fills
	in one table.

	WHY THE SOUND IS PARENTED TO THE TRANSFORMING CHARACTER'S HEAD
	--------------------------------------------------------------
	`Config.Monster.TransformAudioRange` (40 studs) is a fact about WHERE the transform can be heard,
	and Roblox's own rolloff is what enforces it. A sound played at the listener with a manual distance
	check would be a second, wrong answer to a question the engine already answers, and it would need
	the monster's position on the client to ask it — which is the leak this whole file is arranged to
	avoid. Every ranged cue below follows this precedent.

	(An earlier version of this paragraph also claimed the engine accounts for the GEOMETRY between
	the two players. That claim is unverified and is believed to be false for a classic `Sound`, which
	attenuates by distance only. It is struck rather than relied on — the parenting decision stands on
	the distance and the position alone. See the plan's Follow Ups.)
]]

--[[
	═══ THE SECRECY STATEMENT ═════════════════════════════════════════════════

	Every cue in this file, its audience, and what a compromised client learns from it. 🔒
	`exploit-auditor` gates C29; these are its four questions, answered here rather than in a plan
	document.

	1. DOES ANY CUE TAKE A ROLE AS AN INPUT?  No. Grep this file for `YourRole` and `Role` — there is
	   no hit. The only inputs are `snapshot.Phase`, `snapshot.YourState`, `snapshot.SecondsRemaining`
	   and the Character on `MonsterTransformed`. `ClientRoundSnapshot`
	   carries `YourRole`, and this file does not read it.

	2. IS ANY CUE FIRED TO ONE PLAYER AND NOT ANOTHER?  No cue is FIRED at all — nothing here is a
	   remote. Every decision is made on each client from a payload every client received, through
	   `shared/pure/AudioCues`, which has no player parameter. Two clients reach identical answers FOR
	   IDENTICAL INPUTS — which is not the same as reaching them at the same instant: `phase` is
	   written from a per-player snapshot every `Round.SnapshotInterval`, so within one tick of a
	   phase change two clients can hold different values and answer differently. That difference is
	   driven by network arrival order and never by role. The one deliberate asymmetry is the STATE
	   gate:
	   a player in LOBBY or SPECTATOR hears no monster cue, which withholds information from someone
	   outside the round rather than granting it to someone inside it.

	3. DOES ANY Sound REPLICATE?  No. Every Sound in this file is created by `Instance.new` on the
	   CLIENT, so it exists in no other client's tree and on no server. This is why the heartbeat is
	   safe and why a server-created one would not be: an Instance the server parents to a character
	   is readable by every client with `workspace.<Name>.Head` and the volume at zero.

	4. CAN A CUE OUTLIVE THE STATE IT ANNOUNCES?  This is the live risk and it is the reason the
	   heartbeat has three stop conditions. A looping monster cue left running is a permanent audible
	   brand on an ex-Aswang — C04's revert bug in sound, which had `verify` and all five checks green
	   over it. One-shots are bounded by `Config.Audio.CueCleanupSeconds`; the bed is not a monster
	   cue; the heartbeat stops on the revert, on the phase leaving ACTIVE, and on a hard timeout.

	WHAT AN OBSERVER ON A COMPROMISED CLIENT CAN INFER FROM ALL OF IT: that a character they can
	already see is a monster is a monster. Nothing else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCues = require(Shared.pure.AudioCues)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SkyCycle = require(Shared.pure.SkyCycle)
local Types = require(Shared.Types)

local AudioController = {}

local STINGER_NAME = "AswangTransformStinger"

-- The receiver's own phase and state, off the snapshot every client gets. Neither is a secret and
-- neither describes anybody else.
local phase: Types.RoundPhase = "IDLE"
local state: Types.PlayerState = "LOBBY"

--[[
	THE NARROWING FUNCTION, and it is a function rather than a cast on purpose.

	`AudioCues.oneShotsFor` returns `{ string }` because a literal union does not survive `require`
	inside a list — `.claude/lessons/pure-module-unions-widen-in-lists.md`, eight failed fixes at C21.
	So ids arrive here as plain strings and this lookup is what narrows them: an id with no Assets
	entry returns nil and is dropped with a warn, where a cast would have waved it onward into a
	Sound that silently never plays.

	AN EMPTY STRING IS NOT AN ERROR. It is the pre-sourcing state and returns normally.
]]
local function assetFor(cueId: string): string?
	local assetId = Config.Audio.Assets[cueId]

	if assetId == nil then
		warn(`[AudioController] no Config.Audio.Assets entry for cue "{cueId}" — nothing played.`)
		return nil
	end

	return assetId
end

--[[
	THE CUE LOG, AND WHY IT FIRES ON A BLANK ID.

	C29's verification is "the playtester captures console confirmation of each cue". That has to
	work BEFORE the sounds exist, or the only build anybody can verify is the last one. So this logs
	that the cue FIRED — which a console can prove — and says nothing about what it sounded like,
	which is the human step and stays the human step.

	Behind `Debug.VerboseLogging` like every other non-fault line in this codebase; the playtester
	turns it on. A missing ASSET is a warn above and is never gated, because a cue with no sound is a
	fault and faults are ungated here — the rule is that faults are never gated behind a debug flag.
]]
local function logCue(cueId: string, detail: string)
	if Config.Debug.VerboseLogging then
		print(`[AudioController] cue {cueId} — {detail}`)
	end
end

--[[
	Creates a Sound for a cue, or nil if the cue id is unknown. Never returns nil for a BLANK id:
	the instance is still created, parented and ranged, so the lifecycle this file is responsible for
	is exercised identically before and after the sourcing pass.
]]
local function newSound(cueId: string, volume: number, parent: Instance): Sound?
	local assetId = assetFor(cueId)

	if assetId == nil then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = cueId
	sound.SoundId = assetId
	sound.Volume = volume
	sound.Parent = parent

	return sound
end

--[[
	A one-shot, cleaned up by the client that made it.

	`Sound.Ended` is the obvious lifetime and it is the wrong one: A BLANK SoundId NEVER ENDS, so
	every cue would leak an instance for the whole of development. `Config.Audio.CueCleanupSeconds`
	is pinned below `OneShotMinSeconds` in `tests/config.test.luau` so cleanup always beats the next
	schedule and instances cannot accumulate — §5's budget counts Sounds too.

	The nil check inside the delay is not defensive noise: under §5's StreamingEnabled a character can
	stream out mid-cue and take its parent with it.
]]
local function playOneShot(cueId: string, volume: number, parent: Instance, detail: string)
	local sound = newSound(cueId, volume, parent)

	if sound == nil then
		return
	end

	logCue(cueId, detail)
	sound:Play()

	task.delay(Config.Audio.CueCleanupSeconds, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

--[[
	THE BED. Exactly one looping Sound exists on this client at a time, parented to SoundService so
	it is non-positional — the night is everywhere, not at a point.

	IDENTICAL ON EVERY SCREEN, and that is load-bearing rather than incidental, for the reason
	`SkyController`'s header gives about the sky: it is driven from a snapshot every client receives
	through a pure rule with no role input and no player input, so there is no arrangement of this
	code in which one player's ambience differs from another's. A bed that changed when the monster
	was near would be `absence-is-observable` played out loud.
]]
local bed: Sound? = nil
local bedCueId: string? = nil

local function setBed(cueId: string?)
	if cueId == bedCueId then
		return
	end

	local previous = bed
	bedCueId = cueId
	bed = nil

	if previous ~= nil then
		local fadeOut = TweenService:Create(
			previous,
			TweenInfo.new(Config.Audio.BedFadeSeconds),
			{ Volume = 0 }
		)

		fadeOut.Completed:Connect(function()
			previous:Destroy()
		end)

		fadeOut:Play()
	end

	if cueId == nil then
		return
	end

	local sound = newSound(cueId, 0, SoundService)

	if sound == nil then
		return
	end

	sound.Looped = true
	bed = sound

	logCue(cueId, "bed")
	sound:Play()

	TweenService:Create(sound, TweenInfo.new(Config.Audio.BedFadeSeconds), {
		Volume = Config.Audio.BedVolume,
	}):Play()
end

--[[
	FOOTSTEPS — IDENTICAL FOR EVERY CHARACTER, WITH NO EXCEPTIONS ANYWHERE.

	There is no per-role, per-state or transformed variant of this cue and there must not be. A
	constant across all players is safe; a DIFFERENCE is the leak, in either direction
	(`.claude/lessons/absence-is-observable.md`). A louder step for the Aswang carries no role token,
	so `check:secrecy` would pass it, and any player could find the monster by listening.

	It retargets the sound Roblox already creates rather than adding one per character: §5's budget
	counts instances, and eight extra looping Sounds is eight for nothing.

	IF THERE IS NOTHING TO RETARGET, THIS DOES NOTHING, and that is a correct outcome rather than a
	failure — the default footstep is already identical for everybody, which is the property that
	matters here. The engine's default character-sound arrangement is not established anywhere in
	this repo, so this code asserts nothing about it.
]]
local FOOTSTEP_SOUND_NAME = "Running"

--[[
	IT WAITS, AND THE WAIT IS THE WHOLE FIX.

	This ran synchronously on `CharacterAdded` and used `FindFirstChild`, and a C29 playtest measured
	the result: `HumanoidRootPart.Running` IS a `Sound` — the open question this repo never settled —
	but its `SoundId` stayed at Roblox's stock `action_footsteps_plastic.mp3` on every character
	tested, including after a forced respawn. Roblox attaches the default character sounds
	asynchronously, so the child does not exist yet at the instant the character does.

	That mattered more than one silent cue. The safety argument for footsteps is that they are a
	CONSTANT across every player, and a retarget that wins the race for some characters and loses it
	for others is not a constant — it is a per-character difference, which is the shape
	`.claude/lessons/absence-is-observable` warns about, waiting for a future change to correlate it
	with role.

	It also logs both outcomes now. Silence in both branches is what let this sit undetected: nothing
	in a console distinguished "retargeted" from "no-opped".
]]
local function applyFootsteps(character: Model)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", Config.Audio.FootstepWaitSeconds)

		if root == nil then
			return
		end

		local running = root:WaitForChild(FOOTSTEP_SOUND_NAME, Config.Audio.FootstepWaitSeconds)

		if running == nil or not running:IsA("Sound") then
			logCue(
				"CUE_FOOTSTEP",
				`no {FOOTSTEP_SOUND_NAME} sound on {character.Name} — left as the engine set it`
			)
			return
		end

		local assetId = assetFor("CUE_FOOTSTEP")

		if assetId == nil or assetId == "" then
			return
		end

		running.SoundId = assetId
		running.Volume = Config.Audio.FootstepVolume
		logCue("CUE_FOOTSTEP", `retargeted on {character.Name}`)
	end)
end

--[[
	EVERY player, including this one, through one function. The uniformity IS the security property,
	so there is deliberately no branch here to add a condition to later.

	The connection is STORED AND DROPPED when the player leaves. Eight players cycling through a
	long-lived server would otherwise accumulate `CharacterAdded` connections to dead Player
	instances, and the symptom is a slow client-side memory climb that no check in this repo reports.
]]
local characterConnections: { [Player]: RBXScriptConnection? } = {}

local function watchCharacters(player: Player)
	if player.Character ~= nil then
		applyFootsteps(player.Character)
	end

	characterConnections[player] = player.CharacterAdded:Connect(applyFootsteps)
end

local function forgetPlayer(player: Player)
	local connection = characterConnections[player]

	if connection ~= nil then
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

--[[
	WIND AND DISTANT DOGS. Scheduled locally at a random interval, per client, so two players standing
	together do not hear the same dog at the same instant — the barrio should not sound synchronised.

	`AudioCues.oneShotsFor` owns WHICH cues are eligible in a phase and is tested in Lune; this loop
	owns only WHEN, and both its bounds are in `Config.Audio`. ENDING returns an empty list on
	purpose: the reveal is §4.8's "screenshot people share" and a dog barking over it is a joke.

	NON-POSITIONAL, parented to SoundService like the bed. Placing these in the world would need map
	geometry, and the map lives in the place file rather than in Git — C30 dresses the barrio, and
	this run does not touch it.

	`Random.new()` with NO ARGUMENT. Nothing secret rides on this schedule, but a seed derived from a
	round number or `os.time()` is client-reproducible (CLAUDE.md, "Inputs and seeds are") and it is
	not a habit worth forming in a file that also handles the monster's cues.
]]
local rng = Random.new()

local function oneShotLoop()
	while true do
		task.wait(rng:NextNumber(Config.Audio.OneShotMinSeconds, Config.Audio.OneShotMaxSeconds))

		local eligible = AudioCues.oneShotsFor(phase)

		if #eligible > 0 then
			local cueId = eligible[rng:NextInteger(1, #eligible)]
			playOneShot(
				cueId,
				Config.Audio.OneShotVolume,
				SoundService,
				`ambient one-shot in {phase}`
			)
		end
	end
end

local function playStinger(character: Model)
	--[[
		THE STATE GATE, WHICH THIS FUNCTION DID NOT CONSULT UNTIL THE C29 EXPLOIT AUDIT.

		`AudioCues` declares `CUE_TRANSFORM` a MONSTER_CUE, refused to LOBBY and SPECTATOR, and both
		this file's secrecy statement and `AudioCues`' own header stated that as implemented fact —
		while `isCuePermitted` had exactly two call sites, neither of them here. The rule was written,
		tested and never called: a green test over a false comment, which is the shape
		`.claude/lessons/green-after-each-patch-hides-a-loop` describes.

		It leaked nothing, because `MonsterTransformed` is FireAllClients and the transform's visuals
		replicate to spectators anyway. The cost was that the next monster cue would have been routed
		through a gate that does not fire.
	]]
	if not AudioCues.isCuePermitted("CUE_TRANSFORM", phase, state) then
		return
	end

	local head = character:FindFirstChild("Head")

	if head == nil or not head:IsA("BasePart") then
		return
	end

	local existing = head:FindFirstChild(STINGER_NAME)

	if existing ~= nil then
		existing:Destroy()
	end

	local sound = newSound("CUE_TRANSFORM", Config.Audio.StingerVolume, head)

	if sound == nil then
		return
	end

	-- AFTER `newSound`, which names the instance for its cue id. `STINGER_NAME` is the sentinel the
	-- duplicate check three lines above looks for, so the two must agree or a re-transform stacks two
	-- stingers on one Head.
	sound.Name = STINGER_NAME
	sound.RollOffMaxDistance = Config.Monster.TransformAudioRange
	sound.RollOffMode = Enum.RollOffMode.Linear

	logCue("CUE_TRANSFORM", `at {character.Name}, {Config.Monster.TransformAudioRange} studs`)
	sound:Play()

	-- Local-only instance on a replicated character, so it is cleaned up here rather than left for the
	-- server's FX folder teardown to find.
	task.delay(Config.Monster.TransformTime + Config.Monster.RevertTime, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

--[[
	THE HEARTBEAT. Read this whole comment before changing any of it.

	WHAT IT IS: a looping Sound, created BY THIS CLIENT, on a character every client already knows is
	a monster. `MonsterTransformed` is FireAllClients and public by design (§4.3 — the tell IS the
	mechanic), and the character is wearing a scale change, a red tint and a head PointLight while
	this plays. So the cue publishes nothing that is not already on screen.

	WHAT §5 ASKED FOR AND WHY THIS IS NOT IT: "heartbeat when the Aswang is near". For an
	UNTRANSFORMED Aswang that cue is unbuildable. A client-side proximity check needs the Aswang's
	position on the client. A server-sent "you are near" flag is a per-player DIFFERENCE derived from
	the secret, which `check:secrecy` is a text tripwire and cannot see
	(`.claude/lessons/absence-is-observable.md`). And a Sound the SERVER parents to a character
	REPLICATES — `workspace.<Name>.Head.Heartbeat` names the Aswang to anyone reading the instance
	tree, with the volume at zero. The deviation is recorded in the C29 plan's Follow Ups.

	WHY IT STOPS THREE WAYS. A heartbeat that outlives its transform is a permanent audible brand on
	an ex-Aswang — C04's revert bug, in sound. `MonsterService.luau:435` only broadcasts the revert
	`if monster.Announced and character ~= nil`, so the false payload is not guaranteed to arrive:
	  1. the revert broadcast, the normal path;
	  2. the phase leaving ACTIVE, so a round ending mid-transform cannot leave one playing under the
	     reveal;
	  3. a hard timeout at the longest a transform can physically last, as the backstop for any path
	     that sends neither.
	The Sound is parented to the character, so a character destroyed or streamed out takes it with it.
]]
local HEARTBEAT_NAME = "AswangHeartbeat"

-- `Sound?`, not `Sound`. Under strict Luau a `{ [Model]: Sound }` lookup is typed non-optional, so
-- `heartbeats[character] == nil` fails to compile — and the nil compare is how every stop condition
-- here decides whether there is anything to stop.
local heartbeats: { [Model]: Sound? } = {}

local function stopHeartbeat(character: Model)
	local sound = heartbeats[character]

	if sound == nil then
		return
	end

	heartbeats[character] = nil
	logCue("CUE_HEARTBEAT", `stopped on {character.Name}`)

	if sound.Parent ~= nil then
		sound:Destroy()
	end
end

--[[
	THE KEYS ARE COLLECTED BEFORE ANY OF THEM IS CLEARED. `stopHeartbeat` removes from the table this
	would otherwise be iterating; removal during traversal is defined in Lua, but the failure mode if
	it were not is one heartbeat surviving the round — which is the precise leak this cue's three stop
	conditions exist to prevent, so it is not worth resting on a subtlety.
]]
local function stopAllHeartbeats()
	local characters: { Model } = {}

	for character in heartbeats do
		table.insert(characters, character)
	end

	for _, character in characters do
		stopHeartbeat(character)
	end
end

local function startHeartbeat(character: Model)
	if not AudioCues.isCuePermitted("CUE_HEARTBEAT", phase, state) then
		return
	end

	local head = character:FindFirstChild("Head")

	if head == nil or not head:IsA("BasePart") then
		return
	end

	stopHeartbeat(character)

	local sound = newSound("CUE_HEARTBEAT", Config.Audio.HeartbeatVolume, head)

	if sound == nil then
		return
	end

	sound.Name = HEARTBEAT_NAME
	sound.Looped = true
	-- Pinned <= Monster.TransformAudioRange by tests/config.test.luau. The heartbeat must never carry
	-- further than the tell §4.3 specifies.
	sound.RollOffMaxDistance = Config.Audio.HeartbeatRange
	sound.RollOffMode = Enum.RollOffMode.Linear

	heartbeats[character] = sound
	logCue("CUE_HEARTBEAT", `on {character.Name}, {Config.Audio.HeartbeatRange} studs`)
	sound:Play()

	-- STOP CONDITION 3. Longer than any legitimate transform: the forced revert fires at
	-- MaxTransformTime and the revert itself takes RevertTime.
	task.delay(Config.Monster.MaxTransformTime + Config.Monster.RevertTime, function()
		if heartbeats[character] == sound then
			stopHeartbeat(character)
		end
	end)
end

--[[
	THE SUNRISE. Appendix C.3's diegetic clock, given a sound.

	SAME PURE FUNCTION AS THE SKY, deliberately. `SkyController` renders the round clock as a sunrise
	from `SkyCycle.progressFor` over the same snapshot; if this cue derived "how far through the
	night are we" its own way, the sound and the sky would drift apart and no check would say so.

	FIRE-ONCE PER ROUND, reset on the round number changing rather than on a phase, because an
	ABORTED round (§6.4's edge cases) can leave ENDING without ever passing through the threshold.

	`SkyCycle.progressFor` PINS ENDING TO 1 unconditionally (`SkyCycle.luau:136-138`), so a round that
	ends early — every survivor dead — jumps past the threshold and this fires on the reveal. That is
	allowed deliberately: the SKY makes the same jump, and a dawn that arrives without its sound would
	be the two systems disagreeing about the same moment. Flagged for the headphone listen.
]]
local sunriseFiredFor: number? = nil

local function onSunriseProgress(snapshot: Types.ClientRoundSnapshot)
	if sunriseFiredFor == snapshot.RoundNumber then
		return
	end

	local progress = SkyCycle.progressFor({
		Phase = snapshot.Phase,
		SecondsRemaining = snapshot.SecondsRemaining,
		Duration = Config.Round.Duration,
	})

	if progress < Config.Audio.SunriseAtProgress then
		return
	end

	if not AudioCues.isCuePermitted("CUE_SUNRISE", snapshot.Phase, snapshot.YourState) then
		return
	end

	sunriseFiredFor = snapshot.RoundNumber
	playOneShot("CUE_SUNRISE", Config.Audio.SunriseVolume, SoundService, "dawn")
end

local function onTransformed(payload: Types.MonsterTransformedPayload)
	--[[
		TYPED `Model`, ARRIVES `nil`. Under §5's StreamingEnabled (live since C17) a character far
		enough away is not replicated to this client at all, and an Instance reference that does not
		resolve comes across as nil regardless of what `Types.MonsterTransformedPayload` declares.
		Without this the handler's coroutine dies on the first index and the client silently gets no
		heartbeat for the whole of that transform — failing safe, but by accident.
	]]
	local character = payload.Character :: Model?

	if character == nil then
		return
	end

	if payload.Transformed then
		playStinger(character)
		startHeartbeat(character)
	else
		-- STOP CONDITION 1. Still NO revert STINGER — a revert sound would announce the exact moment
		-- a monster became a person again, which is information a witness should get by looking. The
		-- heartbeat merely CEASES, which is the absence of a cue rather than a cue.
		stopHeartbeat(character)
	end
end

local function onSnapshot(snapshot: Types.ClientRoundSnapshot)
	phase = snapshot.Phase
	state = snapshot.YourState

	setBed(AudioCues.ambienceFor(phase))

	-- STOP CONDITION 2. A round ending mid-transform must not leave a heartbeat playing under the
	-- reveal, and `AudioCues` permits this cue in ACTIVE only.
	if phase ~= "ACTIVE" then
		stopAllHeartbeats()
	end

	onSunriseProgress(snapshot)
end

function AudioController.Init() end

function AudioController.Start()
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end

	Players.PlayerAdded:Connect(watchCharacters)
	Players.PlayerRemoving:Connect(forgetPlayer)

	Remotes.Get("RoundSnapshot").OnClientEvent:Connect(onSnapshot)
	Remotes.Get("MonsterTransformed").OnClientEvent:Connect(onTransformed)

	-- One loop for the session. It reads `phase` rather than being restarted per phase, so a phase
	-- change can never leave two schedulers running against the same SoundService.
	task.spawn(oneShotLoop)
end

return AudioController
