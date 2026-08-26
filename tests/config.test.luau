--!strict
--[[
	Balance invariants.

	These are not tests of Config's VALUES — every number in there is explicitly "a starting value to
	tune" (spec §0). They test the RELATIONSHIPS between values, which are load-bearing and silent:
	nothing tells you when two numbers that must agree have stopped agreeing, and the symptom shows up
	as a design failure rather than a bug.
]]

local Config = require("../src/shared/Config")
local AudioCues = require("../src/shared/pure/AudioCues")

local failures = 0
local checked = 0

local function check(label: string, ok: boolean, detail: string?)
	checked += 1

	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- Spec §9.1: the Solo Trial exists to cover the population hole below MinPlayers. If these two drift
-- apart, the Trial either never offers itself during a dead hour, or offers itself during a live one.
check(
	"the Solo Trial offers itself exactly below the minimum player count",
	Config.Trial.OfferBelowPlayerCount == Config.Round.MinPlayers,
	`Trial.OfferBelowPlayerCount={Config.Trial.OfferBelowPlayerCount}, Round.MinPlayers={Config.Round.MinPlayers}`
)

-- Spec §9: small servers fill faster and feel full sooner. Max below min is unstartable.
check(
	"the server can actually reach the minimum",
	Config.Round.MaxPlayers >= Config.Round.MinPlayers
)

-- Spec §C.5 rejects 20-player servers outright: intimacy and paranoia both die at that scale.
check(
	"servers stay small enough for paranoia",
	Config.Round.MaxPlayers <= 8,
	`MaxPlayers={Config.Round.MaxPlayers}`
)

-- Spec §4.3: the transform is forced to revert after MaxTransformTime. If the kill cooldown were
-- shorter than a full transform cycle, the Aswang could chain kills and the "every kill is a gamble"
-- pillar collapses.
check(
	"the kill cooldown outlasts a full transform cycle",
	Config.Monster.KillCooldown > Config.Monster.TransformTime + Config.Monster.RevertTime,
	`KillCooldown={Config.Monster.KillCooldown}`
)

-- Spec §4.3: the transform must be witnessable. A windup shorter than a frame is an invisible kill,
-- which §2 lists as the thing the design pillar explicitly kills.
check(
	"the transform is long enough to be seen",
	Config.Monster.TransformTime >= 1,
	`TransformTime={Config.Monster.TransformTime}`
)

-- Spec §4.6: salt is thrown from outside kill range, or it is not counterplay — it is a suicide button.
check(
	"salt reaches further than the Aswang kills",
	Config.Salt.ThrowRange > Config.Monster.KillRange,
	`ThrowRange={Config.Salt.ThrowRange}, KillRange={Config.Monster.KillRange}`
)

-- Spec §4.6: the reveal must outlast the stun, or the Aswang is revealed only while it cannot move —
-- information nobody can act on.
check(
	"the salt reveal outlasts the stun",
	Config.Salt.RevealDuration > Config.Salt.StunDuration,
	`RevealDuration={Config.Salt.RevealDuration}, StunDuration={Config.Salt.StunDuration}`
)

-- Spec §4.6, C13: four pouches cannot be placed at three points. This is the relation that turns a
-- map defect into a startable round with less salt than the design assumes, and the only symptom
-- otherwise is "salt feels rarer than it should" six playtests later.
check(
	"there are at least as many salt spawn points as pouches",
	Config.Salt.PouchPoolSize >= Config.Salt.SpawnCount,
	`PouchPoolSize={Config.Salt.PouchPoolSize}, SpawnCount={Config.Salt.SpawnCount}`
)

--[[
	Spec §4.6: "Recharge: none in MVP. Once used, it's gone. SCARCITY MAKES IT A DECISION."

	At `SpawnCount >= MaxPlayers` every player can hold one and the decision disappears — salt stops
	being a resource and becomes a button. This is the numeric form of the sentence, and it is the
	first thing an M12 balance pass will be tempted to break.
]]
check(
	"salt is scarcer than the roster",
	Config.Salt.SpawnCount < Config.Round.MaxPlayers,
	`SpawnCount={Config.Salt.SpawnCount}, MaxPlayers={Config.Round.MaxPlayers}`
)

-- Spec §4.6, C14: a half-angle of 90 degrees is a hemisphere and anything above it hits what is
-- BEHIND the thrower. Zero is a raycast, which §5's mobile audience cannot aim.
check(
	"the throw cone is a cone",
	Config.Salt.ThrowConeDegrees > 0 and Config.Salt.ThrowConeDegrees < 90,
	`ThrowConeDegrees={Config.Salt.ThrowConeDegrees}`
)

--[[
	C14/C15, and this relationship became load-bearing for a SECRECY invariant rather than for balance.

	An exploit audit traced the one path that would reproduce the permanent-WalkSpeed brand: transform
	while stunned, so the transform captures `BaseWalkSpeed = 0`. It is closed only because `revert()`
	stamps `LastRevertedAt` and the kill cooldown outlasts the stun, so a salted Aswang cannot
	re-transform before the stun has lifted. Nothing pinned that, and the two numbers are exactly the
	kind an M12 balance pass moves independently.
]]
check(
	"the kill cooldown outlasts the salt stun",
	Config.Monster.KillCooldown > Config.Salt.StunDuration,
	`KillCooldown={Config.Monster.KillCooldown}, StunDuration={Config.Salt.StunDuration}`
)

-- Spec §4.1: total cycle ≈ 7.5 min, and §2 demands "under 8 minutes, back in within 30 seconds".
local cycle = Config.Round.Intermission
	+ Config.Round.StartingDelay
	+ Config.Round.Duration
	+ Config.Round.EndScreen

check("a full round cycle stays under eight minutes", cycle <= 480, `cycle={cycle}s`)

-- Spec §10: the launch gate. Below this first-objective conversion, everything else stops.
check(
	"the FTUE conversion gate is still set to the spec's threshold",
	Config.Badges.FirstTaskConversionGate >= 0.5,
	`gate={Config.Badges.FirstTaskConversionGate} — the competitor's number was 0.201`
)

-- Spec §5: many dynamic lights is the #1 mobile FPS killer, and 60% of players are on mobile.
check("the mobile light budget is still capped", Config.Performance.MaxVisibleLights <= 8)

-- Spec §4.2: the anti-repeat weighting must be MONOTONIC in recency — more recent means less likely —
-- and never zero. Three numbers in the wrong order still draw an Aswang every round, so nothing about
-- the game looks broken; the only symptom is players quietly being the monster twice in a row.
check(
	"a more recent Aswang is less likely than an older one",
	Config.Roles.RecentAswangWeight < Config.Roles.OlderAswangWeight,
	`recent={Config.Roles.RecentAswangWeight}, older={Config.Roles.OlderAswangWeight}`
)

check(
	"any recent Aswang is less likely than someone who has never been one",
	Config.Roles.OlderAswangWeight < Config.Roles.BaseWeight,
	`older={Config.Roles.OlderAswangWeight}, base={Config.Roles.BaseWeight}`
)

-- Zero is a ban, not a discount. See the Config comment.
check(
	"nobody is ever excluded from the draw outright",
	Config.Roles.RecentAswangWeight > 0,
	`recent={Config.Roles.RecentAswangWeight}`
)

-- Spec §4.2: history covers the last 2 rounds. A history as long as the server is large would give
-- every player a reduced weight at once, which is the same as no weighting at all.
check(
	"the anti-repeat history is shorter than a full server",
	Config.Roles.RepeatCooldownRounds >= 1
		and Config.Roles.RepeatCooldownRounds < Config.Round.MaxPlayers,
	`RepeatCooldownRounds={Config.Roles.RepeatCooldownRounds}`
)

-- Spec §4.2 / §3: exactly one Aswang, and at least two survivors at the minimum player count — a
-- round drawn with AswangCount >= MinPlayers is over before ACTIVE begins.
check(
	"a minimum-sized round still has survivors in it",
	Config.Roles.AswangCount < Config.Round.MinPlayers,
	`AswangCount={Config.Roles.AswangCount}, MinPlayers={Config.Round.MinPlayers}`
)

-- Spec §4.2: the 3-second private intro plays during STARTING. If it outlasts StartingDelay it is
-- still on screen when ACTIVE begins, and the Aswang spends the opening seconds of the round reading
-- a card instead of moving — the one moment when standing still is most conspicuous.
check(
	"the Aswang intro finishes before the round goes live",
	Config.Roles.IntroDuration < Config.Round.StartingDelay,
	`IntroDuration={Config.Roles.IntroDuration}, StartingDelay={Config.Round.StartingDelay}`
)

-- Spec §6.5 / README: shipping with SoloTesting on skips MinPlayers for everyone.
check(
	"solo testing is off",
	Config.Debug.SoloTesting == false,
	"this must never be true on a published place"
)

-- The solo testing override rigs the draw. RoleService also gates it on RunService:IsStudio() and on
-- there being exactly one candidate, so this is the third of three guards rather than the only one.
--
-- NOTE it is `check:debug` and not this assertion that stops a commit: guard-commit.mjs runs
-- `verify:fast`, which does not include `test:unit`, so nothing in this file is consulted at commit
-- time. That was believed otherwise for a while and an audit disproved it. This check remains because
-- it is where the REASON lives; check-debug.mjs is where the enforcement does.
check(
	"the solo forced-Aswang override is off",
	Config.Debug.ForceAswangWhenSolo == false,
	"this rigs the draw and must never ship"
)

-- Spec §4.1: a round is ~7 minutes. Nothing pinned a FLOOR, so a 60-second duration left over from a
-- Studio session passed every check — including this file — and would have shipped silently. Five
-- tasks cannot be found and completed across a village in under five minutes.
check(
	"a round is long enough to actually be played",
	Config.Round.Duration >= 300,
	`Duration={Config.Round.Duration}s — a testing value left in?`
)

--------------------------------------------------------------------------------
-- C05 / C06 / C07 (this plan)
--------------------------------------------------------------------------------

-- Spec §4.3 step 4: the corpse "remains for 45s, then fades". A fade longer than the lifetime means
-- the body is translucent for its whole existence and never reads as a body at all.
check(
	"the corpse fades inside its own lifetime",
	Config.Monster.CorpseFadeTime < Config.Monster.CorpseDuration,
	`CorpseFadeTime={Config.Monster.CorpseFadeTime}, CorpseDuration={Config.Monster.CorpseDuration}`
)

-- Spec §4.3 step 5. The corpse is the evidence, and the cooldown is how long until there could be a
-- second one. If a body faded before the Aswang could kill again, the map would never show two at
-- once — and "bodies are piling up" is the pressure that makes survivors group and finish tasks.
check(
	"a body outlives the cooldown, so two kills can be evidence at once",
	Config.Monster.CorpseDuration > Config.Monster.KillCooldown,
	`CorpseDuration={Config.Monster.CorpseDuration}, KillCooldown={Config.Monster.KillCooldown}`
)

-- The respawn cooldown throttles a CLIENT-CONTROLLED trigger (Humanoid.Died, reachable from the stock
-- reset button), so it must be positive or the throttle does not exist. It must also stay well under
-- Intermission, or a player who dies in the lobby is still bodiless when STARTING deals them in —
-- which would hand them a round as an ALIVE player with no character, the exact shape of the bug the
-- death watcher was written to fix.
check(
	"a lobby death always recovers well before the next round starts",
	Config.Round.RespawnCooldown > 0
		and Config.Round.RespawnCooldown * 2 < Config.Round.Intermission,
	`RespawnCooldown={Config.Round.RespawnCooldown}, Intermission={Config.Round.Intermission}`
)

--------------------------------------------------------------------------------
-- The Solo Trial (C21/C22, §9.1)
--
-- Every one of these is silent. A trial with its beats out of order does not error, does not fail to
-- typecheck and does not warn — it just runs a 90-second tutorial that teaches the wrong thing, and
-- the only symptom is a playtester saying it "felt confusing".
--------------------------------------------------------------------------------

check(
	"the chase starts before the trial ends",
	Config.Trial.ScriptedChaseAt < Config.Trial.Duration,
	"a transform scheduled at or after Duration never fires; the trial teaches tasks and nothing else"
)

check(
	"salt is in hand before the thing it defends against arrives",
	Config.Trial.SaltGivenAt < Config.Trial.ScriptedChaseAt,
	"§10 asks that the folklore be taught by doing; a pouch that arrives mid-chase is taught by panic"
)

check(
	"the folklore line lands after the transform, not before",
	Config.Trial.SaltTaughtAt > Config.Trial.ScriptedChaseAt,
	"'salt burns the aswang' means nothing until there is an aswang on screen"
)

check(
	"the handoff has room to be read",
	Config.Trial.HandoffAt < Config.Trial.Duration
		and Config.Trial.HandoffAt > Config.Trial.SaltTaughtAt,
	"the closing line is the one sentence §9.1 specifies verbatim; it cannot be the last frame"
)

--[[
	THE PARTITION. RoundService leaves IDLE at `>= MinPlayers` (RoundService.luau:1003) and
	TrialAdmission refuses at `>= OfferBelowPlayerCount`. Equal, those two split the headcount line
	with no value on both sides. If OfferBelowPlayerCount were the larger, there would be a count at
	which a round starts AND a trial is still offered — and the trial would open and be aborted in the
	same second, which presents as a button that flickers.
]]
check(
	"the trial's offer threshold and the round's floor are the same line",
	Config.Trial.OfferBelowPlayerCount == Config.Round.MinPlayers,
	"a gap or an overlap here means a count where both a round and a trial believe they may start"
)

--[[
	The rig must be survivable. Compared against `Trial.PlayerBaselineWalkSpeed` rather than against
	anything in Config.Monster, because the trial's Aswang never goes through MonsterService — see the
	plan's §1.1 — and because retuning the real Aswang at M12 must not retune the tutorial. If this
	ever fails, the tutorial has grown a death path, and a death path is the first step toward the PvE
	campaign C22's row forbids in bold.
]]
check(
	"the trial's scripted Aswang cannot catch the player",
	Config.Trial.ChaseWalkSpeed < Config.Trial.PlayerBaselineWalkSpeed,
	"a trial Aswang that catches you needs a death, a respawn and a re-entry — none of which exist"
)

--[[
	ONE TICK OF CHASE MUST NOT CROSS THE WHOLE HOLD ZONE.

	This one was found by a playtest, not by reading. `stepRig` checks the stop distance and THEN
	moves, so if a single tick's travel exceeds `ChaseStopStuds` the rig steps straight over the zone
	the check guards. At the shipped numbers it did: 13 studs/s x 0.5s = 6.5 studs per tick against a
	6-stud radius, and the rig landed at 1.70 studs from the player every single run — close enough
	to read as the monster standing inside you.

	`stepRig` now CLAMPS its step, so the behaviour is correct regardless of these two numbers. This
	invariant is the second line of defence and the documentation of the relationship: if someone
	raises `ChaseWalkSpeed` or `SnapshotInterval` far enough, the clamp keeps the stop correct but
	the approach becomes one visible jump per tick, which is a different bug with no error attached.
]]
check(
	"one chase tick cannot cross the rig's whole hold zone",
	Config.Trial.ChaseWalkSpeed * Config.Trial.SnapshotInterval <= Config.Trial.ChaseStopStuds,
	`travel={Config.Trial.ChaseWalkSpeed * Config.Trial.SnapshotInterval}, stop={Config.Trial.ChaseStopStuds}`
)

--------------------------------------------------------------------------------
-- The quick-chat wheel (C25, §4.5)
--
-- Step 1.1 of the C25 plan asked for these and the first implementation shipped without them: the
-- bounds were written in prose in Config's comment and enforced nowhere. A plan audit caught it.
-- Prose does not fail a build.
--------------------------------------------------------------------------------

--[[
	THE ACCUSATION MUST REACH FURTHER THAN THE ASWANG KILLS.

	§4.5 exists for the moment something is close enough to kill you and there is no time to type. A
	range that cannot name the thing standing on top of you has no reason to exist.
]]
check(
	"the accusation reaches further than the Aswang kills",
	Config.QuickChat.AccuseRangeStuds > Config.Monster.KillRange,
	`AccuseRangeStuds={Config.QuickChat.AccuseRangeStuds}, KillRange={Config.Monster.KillRange}`
)

--[[
	THE FIELD OF VIEW IS A CONE, and at or past 90 degrees it stops being one.

	An exploit audit found the accusation's failure was a free silent "is anyone watching me" probe,
	because a raycast with no facing term sees behind the sender. At >= 90 that property returns:
	the miss stops meaning "nobody in front of me" and the equivalence the design rests on breaks.
]]
check(
	"the accusation's field of view is a forward cone",
	Config.QuickChat.AccuseHalfAngleDegrees > 0 and Config.QuickChat.AccuseHalfAngleDegrees < 90,
	`AccuseHalfAngleDegrees={Config.QuickChat.AccuseHalfAngleDegrees}`
)

--------------------------------------------------------------------------------
-- The mobile light budget (C27, §5)
--
-- §5 calls the mobile budget non-negotiable, and until C27 its numbers were read
-- by nothing at all. These pin the two relationships that would turn the cap
-- from a frame-rate rule into a gameplay one.
--------------------------------------------------------------------------------

--[[
	THE MAP MAY NOT SPEND THE MONSTER'S SLOT.

	`ReservedGameplayLights` is subtracted from what the scenery culler may light, and those slots
	belong to the Aswang's eye glow (§4.3's warning) and a salt pouch's (§4.6's counterplay). At or
	above `MaxVisibleLights` the allowance is zero and the barrio goes fully dark — which does not
	cost frames, it breaks §5's sightline rule, and total darkness is confusing rather than scary.
]]
check(
	"the map keeps some of the light budget",
	Config.Performance.ReservedGameplayLights < Config.Performance.MaxVisibleLights,
	`ReservedGameplayLights={Config.Performance.ReservedGameplayLights}, `
		.. `MaxVisibleLights={Config.Performance.MaxVisibleLights}`
)

--[[
	AND THE CULL IS NOT ITSELF A COST. Lights do not move and a camera does not teleport, so
	re-deciding faster than the server pushes a snapshot spends frames on an answer that did not
	change — on the device the whole budget exists to protect.
]]
check(
	"the light cull runs slower than the snapshot it is not driven by",
	Config.Performance.LightCullIntervalSeconds >= Config.Round.SnapshotInterval,
	`LightCullIntervalSeconds={Config.Performance.LightCullIntervalSeconds}, `
		.. `SnapshotInterval={Config.Round.SnapshotInterval}`
)

--------------------------------------------------------------------------------
-- The diegetic sunrise (C28, Appendix C.3)
--
-- The sky IS the countdown, so these are clock invariants wearing lighting
-- names. `tests/sky-cycle.test.luau` proves the mapping; these pin the numbers
-- it is handed.
--------------------------------------------------------------------------------

--[[
	THE NIGHT RUNS FORWARDS. Inverted, the sky would DARKEN as the round ran out — a countdown
	running backwards, and one that no HUD element would contradict because the HUD does not know the
	sky exists.
]]
check(
	"the night ends later than it starts",
	Config.Sky.EndClockTime > Config.Sky.StartClockTime,
	`StartClockTime={Config.Sky.StartClockTime}, EndClockTime={Config.Sky.EndClockTime}`
)

-- Roblox ClockTime is 0-24. Outside it the sky is undefined rather than clamped.
check(
	"both ends of the night are real clock times",
	Config.Sky.StartClockTime >= 0 and Config.Sky.EndClockTime <= 24,
	`StartClockTime={Config.Sky.StartClockTime}, EndClockTime={Config.Sky.EndClockTime}`
)

--[[
	DAWN LIFTS THE NIGHT RATHER THAN DEEPENING IT. Three multipliers, one direction each: brighter,
	further, thinner. A sign flip in any of them still typechecks, still tweens smoothly, and gives a
	round that gets darker as sunrise approaches.
]]
check(
	"dawn is brighter, further-seeing and less foggy than night",
	Config.Sky.DawnBrightnessMult > 1
		and Config.Sky.DawnFogEndMult > 1
		and Config.Sky.DawnAtmosphereDensityMult < 1,
	`brightness x{Config.Sky.DawnBrightnessMult}, fog x{Config.Sky.DawnFogEndMult}, `
		.. `atmosphere x{Config.Sky.DawnAtmosphereDensityMult}`
)

--[[
	AND IT IS WARM. The night is blue by construction (§5's art direction); a dawn whose red channel
	did not exceed its blue is moonlight turned up, not morning. Checked on both ambients because
	they are the two the eye reads as colour rather than as brightness.
]]
check(
	"dawn is warmer than the night it replaces",
	Config.Sky.DawnAmbientRgb[1] > Config.Sky.DawnAmbientRgb[3]
		and Config.Sky.DawnOutdoorAmbientRgb[1] > Config.Sky.DawnOutdoorAmbientRgb[3],
	`ambient={Config.Sky.DawnAmbientRgb[1]}/{Config.Sky.DawnAmbientRgb[3]}, `
		.. `outdoor={Config.Sky.DawnOutdoorAmbientRgb[1]}/{Config.Sky.DawnOutdoorAmbientRgb[3]}`
)

--[[
	THE SKY IS BACK TO NIGHT BEFORE THE NEXT ROUND IS DEALT.

	The restore starts when a round ends and the lobby is `Round.Intermission` long. If the fall took
	longer, a round would start part-way through the previous night's sunrise and the sky would spend
	its first minute going the wrong way — the one thing `sky-cycle`'s monotonicity property cannot
	see, because it holds within a round rather than across two.
]]
check(
	"the sky settles back to night before the next round starts",
	Config.Sky.RestoreSeconds < Config.Round.Intermission,
	`RestoreSeconds={Config.Sky.RestoreSeconds}, Intermission={Config.Round.Intermission}`
)

--[[
	══ AUDIO (C29) ══

	Four relationships, and the reason none of them is a test of a VALUE. "HeartbeatVolume is 0.7" is
	taste and belongs in a playtest; "the heartbeat cannot out-reach the tell it belongs to" is a
	relationship whose violation has no symptom at all — the sound simply carries further than §4.3
	documents and nobody is ever told.
]]

--[[
	§4.3 fixes how far a transform is audible, and `Config.Monster.TransformAudioRange` is the number
	that documents it. The heartbeat is the same event heard continuously, so a heartbeat audible past
	that range would rewrite the tell without anyone editing the field that records it — the monster
	would be trackable from outside the distance the design says it can be found at.
]]
check(
	"the heartbeat never carries further than the transform tell",
	Config.Audio.HeartbeatRange <= Config.Monster.TransformAudioRange,
	`HeartbeatRange={Config.Audio.HeartbeatRange}, TransformAudioRange={Config.Monster.TransformAudioRange}`
)

--[[
	Appendix C.3: the sky IS the round timer, and the sunrise cue marks it landing. At 1.0 the cue
	would fire as a stamp on the reveal rather than as the thing that announces it, and at 0 it would
	fire at the top of the round. It has to sit inside the night and near the end of it.
]]
check(
	"the sunrise cue fires inside the round, near its end",
	Config.Audio.SunriseAtProgress > 0.5 and Config.Audio.SunriseAtProgress < 1,
	`SunriseAtProgress={Config.Audio.SunriseAtProgress}`
)

--[[
	§5's budget. A one-shot is destroyed on a timer rather than on `Sound.Ended`, because A BLANK
	SoundId NEVER ENDS and every cue would otherwise leak an instance for the whole of development.
	That timer has to beat the next schedule, or one-shots accumulate one per interval for the length
	of a round — silently, since each is inaudible until the ids arrive.
]]
check(
	"a one-shot is cleaned up before the next one is scheduled",
	Config.Audio.CueCleanupSeconds < Config.Audio.OneShotMinSeconds,
	`CueCleanupSeconds={Config.Audio.CueCleanupSeconds}, OneShotMinSeconds={Config.Audio.OneShotMinSeconds}`
)

check(
	"the one-shot interval band is not inverted",
	Config.Audio.OneShotMinSeconds < Config.Audio.OneShotMaxSeconds,
	`min={Config.Audio.OneShotMinSeconds}, max={Config.Audio.OneShotMaxSeconds}`
)

--[[
	The dawn bed crossfades in when the round ends, and the end screen is all the time it has. A fade
	longer than `Round.EndScreen` would still be arriving when the screen it belongs to is gone.
]]
check(
	"the dawn bed finishes fading in before the end screen is over",
	Config.Audio.BedFadeSeconds < Config.Round.EndScreen,
	`BedFadeSeconds={Config.Audio.BedFadeSeconds}, EndScreen={Config.Round.EndScreen}`
)

--[[
	THE ID FORMAT, AND WHY IT IS HERE BEFORE ANY ID EXISTS.

	Empty is the supported shipping state — `AudioController` builds and ranges the Sound either way —
	so the assertion is "empty OR well-formed", never "present". Without it, C29's sourcing pass would
	be a step whose only evidence is that somebody typed something into a table: `rbxassetid//123`,
	a bare `123`, or a Creator Store URL pasted whole are all silent nothings at runtime, and a Sound
	with a malformed id fails exactly the way a Sound with a blank one does.
]]
for cueId, assetId in Config.Audio.Assets do
	check(
		`asset id for {cueId} is empty or well-formed`,
		assetId == "" or string.match(assetId, "^rbxassetid://%d+$") ~= nil,
		`got "{assetId}"`
	)
end

--[[
	THE TWO TABLES CANNOT DRIFT APART.

	`shared/pure/AudioCues` decides WHICH cue plays WHEN; `Config.Audio.Assets` holds WHAT it sounds
	like. They are two files a rename touches one of, and the failure is silent in both directions: a
	cue with a rule and no slot plays nothing forever, and a slot with no rule is a sound nobody can
	reach. Both directions are checked below, through the module's public API.
]]
local PHASES_FOR_AUDIO = { "IDLE", "INTERMISSION", "STARTING", "ACTIVE", "ENDING" }

-- Forward: every bed and one-shot the rule names has somewhere to put its sound.
for _, phase in PHASES_FOR_AUDIO do
	local bed = AudioCues.ambienceFor(phase)

	check(`the {phase} bed has an asset slot`, bed ~= nil and Config.Audio.Assets[bed] ~= nil)

	for _, cueId in AudioCues.oneShotsFor(phase) do
		check(`the {cueId} one-shot has an asset slot`, Config.Audio.Assets[cueId] ~= nil)
	end
end

--[[
	Reverse: every slot is reachable by some rule — a bed, a one-shot, or an event cue permitted in
	at least one phase. This is the direction that catches a rename inside `AudioCues`, since the
	orphaned key here stops being known to the module.
]]
for cueId in Config.Audio.Assets do
	local known = false

	for _, phase in PHASES_FOR_AUDIO do
		if AudioCues.ambienceFor(phase) == cueId then
			known = true
		end

		for _, oneShot in AudioCues.oneShotsFor(phase) do
			if oneShot == cueId then
				known = true
			end
		end

		if AudioCues.isCuePermitted(cueId, phase, "ALIVE") then
			known = true
		end
	end

	check(`the {cueId} slot is reachable by a rule`, known)
end

--[[
	C31. Roblox's `BindToClose` window is roughly 30 seconds and then the process dies mid-write —
	which is the exact failure the flush exists to prevent, arriving by a different door. A budget at
	or above the window is a budget that has never actually bounded anything.
]]
check(
	"the shutdown flush budget stays inside Roblox's BindToClose window",
	Config.Profile.ShutdownFlushBudget < 30,
	`{Config.Profile.ShutdownFlushBudget}s`
)

--[[
	C31. A player who joins during INTERMISSION must have a profile — or a settled failure — before
	the round they joined for begins, or the first thing C32 awards them lands on a profile that is
	still loading and is thrown away when it arrives.
]]
check(
	"session retries resolve before a round can start",
	Config.Profile.SessionStartAttempts * Config.Profile.SessionStartRetryDelay
		< Config.Round.Intermission + Config.Round.StartingDelay,
	`{Config.Profile.SessionStartAttempts} x {Config.Profile.SessionStartRetryDelay}s`
)

check("at least one session attempt is made", Config.Profile.SessionStartAttempts >= 1)

--[[
	C32. BEING THE MONSTER MUST NOT BE THE ONLY WAY TO PROGRESS.

	§4.2's anti-repeat draw is deliberately biased AGAINST giving a player the role twice in a row, so
	over a session most people are survivors most of the time. If the Aswang's award table paid far
	more, the level bar would be gated behind a draw the game is actively trying not to give you — and
	the symptom would be "progression feels random", which is the hardest kind of complaint to trace
	back to a number.

	Both sides are measured at their CEILING: a survivor who won and survived, against an Aswang who
	won and killed every survivor dealt in. The bound is generous — the monster's round is rarer and
	should pay better — and it is the runaway case it exists to catch.

	The per-kill rate is the knob this actually constrains, and `Config.Economy`'s comment claims the
	relationship; this is what makes the claim checkable.
]]
local maxKills = Config.Round.MaxPlayers - 1
local aswangCeiling = Config.Economy.XPPerRound
	+ Config.Economy.XPWinBonus
	+ Config.Economy.XPPerKill * maxKills
local survivorCeiling = Config.Economy.XPPerRound
	+ Config.Economy.XPWinBonus
	+ Config.Economy.XPSurvivorEscapeBonus

check(
	"a perfect Aswang round pays more than a perfect survivor round",
	aswangCeiling > survivorCeiling,
	`{aswangCeiling} vs {survivorCeiling}`
)
check(
	"a perfect Aswang round does not pay double a perfect survivor round",
	aswangCeiling < survivorCeiling * 2,
	`{aswangCeiling} vs {survivorCeiling} over {maxKills} kills`
)

--[[
	C33/C34. THE DAILY STREAK MUST NOT OUT-EARN THE GAME.

	§7 puts the streak and the coin economy in the same section, and the failure mode when they drift
	is specific: if a week of logging in buys more than a week of playing, the optimal play is to open
	the game and close it. Pinned against the CHEAPEST unlockable, so the streak stays a top-up rather
	than the route.
]]
local weekCoins = 0

for _, reward in Config.Daily.Rewards do
	weekCoins += reward.Coins
end

local cheapest = math.huge

for _, item in Config.Cosmetics.Catalogue do
	if item.Source == "COINS" and item.Price < cheapest then
		cheapest = item.Price
	end
end

check(
	"a week of daily claims does not buy the cheapest cosmetic on its own",
	weekCoins < cheapest,
	`{weekCoins} coins a week vs {cheapest} for the cheapest unlockable`
)

if failures > 0 then
	error(`{failures} balance invariant(s) violated`, 0)
end

--[[
	COUNTED, NOT TYPED. This line read `34 balance invariants` as a literal for long enough that it
	survived the seven checks C13–C16 added without moving, and a suite that reports the same total
	whatever it contains cannot tell you a check was dropped — the number is exactly the thing you
	would glance at to find out. `check` now bumps `checked`, so the figure is a measurement.
]]
print(`  PASS  config: {checked} balance invariants`)
