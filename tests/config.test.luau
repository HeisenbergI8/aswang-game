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

--[[
	§6.5 INVARIANT 2, AND §4.3'S "THE FEED DURATION IS LOAD-BEARING, NOT COSMETIC" (V06).

	"It must exceed the time for a survivor to cross ~15 studs and land a buntot pagi swing… otherwise
	someone tunes it to 3 seconds later and silently deletes a win condition."

	WHY IT IS SILENT: the feed is the ONLY reliably predictable moment in the round — the monster is
	stationary, visible, and standing somewhere survivors already know because there is a body there.
	§4.6 says that window is what the buntot pagi needs. Shorten it and nothing errors, nothing warns,
	and the second win condition quietly becomes a coin flip against a faster player. The symptom is
	"the Aswang always wins", which reads as balance and gets fixed by moving a different number.

	THE SWING HAS NO CONFIG NUMBER UNTIL V08. These two locals are the placeholder, and they are
	locals rather than Config entries because they are not knobs — they are this test's model of a
	human. V08 replaces SWING_SECONDS with the strike's real wind-up and deletes this note.
]]
local CROSSING_STUDS = 15 -- §4.3's own figure
local REACTION_SECONDS = 1 -- registering the kill and turning toward it
local SWING_SECONDS = 1 -- placeholder; V08 replaces this with the strike's real wind-up

local crossing = CROSSING_STUDS / Config.Trial.PlayerBaselineWalkSpeed
local window = crossing + REACTION_SECONDS + SWING_SECONDS

check(
	"the feed outlasts a survivor crossing fifteen studs and landing a swing",
	Config.Monster.FeedDuration > window,
	`FeedDuration={Config.Monster.FeedDuration}, needed>{window}`
)

--[[
	AND THE FEED MUST NOT BECOME THE DOMINANT TERM IN HOW LONG A MONSTER IS A MONSTER (V06).

	V06 defers the post-kill revert until the feed ends and makes `transform`'s MaxTransformTime timer
	decline while a feed is live, so the form is held for at most MaxTransformTime + FeedDuration.
	That bound is fine at 8 + 5. It stops being fine the moment FeedDuration passes MaxTransformTime,
	at which point the "8 second" transform is mostly feeding and §4.3 step 4's forced revert has
	stopped meaning anything. Nothing in the game reports that; the transform simply gets long.
]]
check(
	"the feed never outlasts the transform it is holding open",
	Config.Monster.FeedDuration < Config.Monster.MaxTransformTime,
	`FeedDuration={Config.Monster.FeedDuration}, MaxTransformTime={Config.Monster.MaxTransformTime}`
)

--[[
	AND THE LEASH MUST MEAN "LOCKED IN PLACE" (V06, §4.3).

	The leash is the server's authority over the feed — `WalkSpeed = 0` is an affordance a compromised
	client ignores, and the distance test is what actually costs it the heal. A leash at or above
	KillRange would let the monster drift a full kill's worth of distance and still be feeding, at
	which point the corpse has stopped being the fixed, known point §4.3 sells it as.
]]
check(
	"the feed leash keeps the monster on the body",
	Config.Monster.FeedLeashStuds < Config.Monster.KillRange,
	`FeedLeashStuds={Config.Monster.FeedLeashStuds}, KillRange={Config.Monster.KillRange}`
)

-- Spec §4.3: the transform must be witnessable. A windup shorter than a frame is an invisible kill,
-- which §2 lists as the thing the design pillar explicitly kills.
check(
	"the transform is long enough to be seen",
	Config.Monster.TransformTime >= 1,
	`TransformTime={Config.Monster.TransformTime}`
)

--[[
	Spec §4.6: salt is thrown from outside kill range, or it is not counterplay — it is a suicide
	button. §6.5 invariant 3.

	V08 RE-POINTED THIS OFF THE ALIAS TABLE. It used to read `Config.Salt.ThrowRange`, and it is an
	INVARIANT wearing alias clothing rather than one of the alias GUARDS that table carried — so when
	`Config.Salt` was deleted this had to survive rather than go with it. Deleting an invariant while
	deleting a table is the silent way to lose a §6.5 guarantee.
]]
check(
	"salt reaches further than the Aswang kills",
	Config.Items.SaltThrowRange > Config.Monster.KillRange,
	`SaltThrowRange={Config.Items.SaltThrowRange}, KillRange={Config.Monster.KillRange}`
)

-- Spec §4.6: the reveal must outlast the stun, or the Aswang is revealed only while it cannot move —
-- information nobody can act on. §6.5 invariant 6. V08 re-pointed it off the alias table for the
-- same reason as the check above.
check(
	"the salt reveal outlasts the stun",
	Config.Items.SaltRevealDuration > Config.Items.SaltStunDuration,
	`SaltRevealDuration={Config.Items.SaltRevealDuration}, `
		.. `SaltStunDuration={Config.Items.SaltStunDuration}`
)

--[[
	V02'S SEVEN SALT ALIASES ARE GONE, AND SO IS THE TABLE THEY GUARDED.

	`Config.Salt` was a shrinking alias table whose four spec-renamed keys pointed into `Config.Items`,
	and these checks existed because nothing mechanically stops a tuning session replacing a reference
	with a literal — it typechecks, `check:config` exempts `Config.luau` itself, and `analyze` and
	`lint` stay green while the two numbers silently diverge.

	V08 renamed the last reader of every one of them, so the table was deleted and its guards went
	with it, exactly as V02's instruction said they should ("DELETE EACH ONE with the alias it
	guards"). What did NOT go with it: the two §6.5 invariants that happened to read through the
	alias. Those are re-pointed at `Config.Items` above.
]]

--------------------------------------------------------------------------------
-- V08 — the item slot, the drop, and the two-number agreements behind them.
--------------------------------------------------------------------------------

--[[
	V08. THE DROP CANNOT LAND INSIDE ITS OWN PICKUP RADIUS.

	A silent invariant of exactly the kind §6.5 collects. Drop an item within `DropPickupRangeStuds`
	of where you are standing and the pickup pass takes it straight back — the item never reaches the
	floor, the slot never empties, and the player sees a drop button that does nothing. No error, no
	warning, and the only symptom is a control that appears broken.
]]
check(
	"a dropped item lands outside the radius that would re-take it",
	Config.Items.DropForwardStuds >= Config.Items.DropPickupRangeStuds,
	`DropForwardStuds={Config.Items.DropForwardStuds}, `
		.. `DropPickupRangeStuds={Config.Items.DropPickupRangeStuds}`
)

--[[
	V08. A DROPPED ITEM IS NOT SWEPT UP FROM A CONTAINER.

	`Search.RangeStuds` (10) is how far you may stand from a container and still search it. If the
	drop pickup radius reached that far, a player at a container would collect whatever was on the
	floor beside it without moving — and the one-slot choice §4.6 is built on becomes "hold both,
	one frame apart".
]]
check(
	"the drop pickup radius is tighter than the search radius",
	Config.Items.DropPickupRangeStuds < Config.Search.RangeStuds,
	`DropPickupRangeStuds={Config.Items.DropPickupRangeStuds}, `
		.. `SearchRangeStuds={Config.Search.RangeStuds}`
)

-- V08. `pure/ItemCarry` fails closed on a limit that is not positive-and-finite, so a typo here is
-- a game in which nobody can carry anything. One is the design (§4.6); this pins the range.
check(
	"the carry limit is a positive finite number",
	Config.Items.CarryLimit > 0 and Config.Items.CarryLimit < math.huge,
	`CarryLimit={Config.Items.CarryLimit}`
)

--[[
	V08. THE THROW CONE STAYS A CONE. At 90 degrees the half-angle makes a hemisphere and past 90 a
	throw hits what is behind the thrower, which is not a throw. `pure/ItemThrow.inCone` re-checks
	this bound because it is called with numbers rather than with Config; this pins the number the
	game actually ships.
]]
check(
	"the throw cone is a half-angle under 90 degrees",
	Config.Items.ThrowConeDegrees > 0 and Config.Items.ThrowConeDegrees < 90,
	`ThrowConeDegrees={Config.Items.ThrowConeDegrees}`
)

--[[
	V08 DELETED "there are at least as many salt spawn points as pouches" WITH THE POOL IT GUARDED.

	C13 placed four pouches at `SaltSpawn` points and this pinned the map against the count. V08
	deleted that second salt economy: items come from V03's containers, seeded by `SearchService`
	from `Config.Items.*SpawnCount`, and there are no spawn points left to be short of.

	THE EQUIVALENT GUARD FOR THE NEW WORLD IS `Config.Search.ContainerCount` AGAINST THE SEVEN ITEMS,
	and it already exists in this file where the container numbers are pinned — see the Search block.
]]

--[[
	Spec §4.6: "Recharge: none in MVP. Once used, it's gone. SCARCITY MAKES IT A DECISION."

	At `SpawnCount >= MaxPlayers` every player can hold one and the decision disappears — salt stops
	being a resource and becomes a button. This is the numeric form of the sentence, and it is the
	first thing an M12 balance pass will be tempted to break.
]]
check(
	"salt is scarcer than the roster",
	Config.Items.SaltSpawnCount < Config.Round.MaxPlayers,
	`SaltSpawnCount={Config.Items.SaltSpawnCount}, MaxPlayers={Config.Round.MaxPlayers}`
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
	Config.Monster.KillCooldown > Config.Items.SaltStunDuration,
	`KillCooldown={Config.Monster.KillCooldown}, SaltStunDuration={Config.Items.SaltStunDuration}`
)

--[[
	§6.5 INVARIANT 1 (V05, §4.6). THE SECOND WIN CONDITION, AND IT HAS NO SYMPTOM.

	"Land three salt hits, then land the buntot pagi during a reveal window. They have four pouches,
	so exactly one may miss." That sentence is four numbers in three Config blocks, and it was a
	comment in two of them and an assertion in none until this chunk.

	IT IS SATISFIED WITH ZERO MARGIN at the shipped values — 25 x 3 = 75 = 100 - 25 — which is what
	makes it dangerous rather than decorative. Raise MaxHealth, lower WeakenedThreshold, soften
	SaltDamage or cut a pouch and survivors can no longer reach `Weakened` after one miss. The game
	does not get harder in any visible way; the Aswang simply stops being killable, and that reads as
	a balance opinion rather than as a broken win condition.

	THE `- 1` IS THE MISS. Removing it is the tempting simplification and it is the bug: it asserts
	that survivors win only if every single throw connects.
]]
check(
	"survivors can still weaken the Aswang after one missed throw",
	Config.Items.SaltDamage * (Config.Items.SaltSpawnCount - 1)
		>= Config.Monster.MaxHealth - Config.Monster.WeakenedThreshold,
	`SaltDamage={Config.Items.SaltDamage}, SaltSpawnCount={Config.Items.SaltSpawnCount}, `
		.. `MaxHealth={Config.Monster.MaxHealth}, WeakenedThreshold={Config.Monster.WeakenedThreshold}`
)

--[[
	THE FEED IS A SETBACK, NOT A RESET (§4.6). "Every kill the Aswang makes heals away one salt hit"
	— ONE. A FeedHeal above SaltDamage means each kill undoes more than a pouch, and since there are
	four pouches and no recharge, the tug-of-war stops being a tug-of-war and becomes arithmetic the
	survivors lose by construction.
]]
check(
	"a feed heals away no more than one salt hit",
	Config.Monster.FeedHeal <= Config.Items.SaltDamage,
	`FeedHeal={Config.Monster.FeedHeal}, SaltDamage={Config.Items.SaltDamage}`
)

-- V05, §4.6. The glow is the ONLY presentation of health, so its direction is the mechanic. Lower
-- transparency is brighter; inverting these two makes a dying Aswang FADE, which is exactly
-- backwards, entirely silent, and findable only by playing it while counting salt hits.
check(
	"the Exposed glow brightens as the Aswang weakens",
	Config.Monster.ExposedGlowTransparencyWeakened < Config.Monster.ExposedGlowTransparencyFull,
	`Weakened={Config.Monster.ExposedGlowTransparencyWeakened}, `
		.. `Full={Config.Monster.ExposedGlowTransparencyFull}`
)

-- A Highlight's FillTransparency is 0..1. Outside it the property clamps silently and the ramp
-- flattens at one end, which looks like "the glow stopped changing" rather than like a bad number.
check(
	"both glow endpoints are legal transparencies",
	Config.Monster.ExposedGlowTransparencyWeakened >= 0
		and Config.Monster.ExposedGlowTransparencyFull <= 1,
	`Weakened={Config.Monster.ExposedGlowTransparencyWeakened}, `
		.. `Full={Config.Monster.ExposedGlowTransparencyFull}`
)

-- V05, §4.6. The ramp needs a span to interpolate across, and `Weakened` needs to be a state a
-- healthy monster is not in. Equal values make every Aswang permanently weakened from the first
-- frame of the round; an inverted pair makes it permanently weakened AND unfloorable.
check(
	"there is room between full health and weakened",
	Config.Monster.WeakenedThreshold < Config.Monster.MaxHealth,
	`WeakenedThreshold={Config.Monster.WeakenedThreshold}, MaxHealth={Config.Monster.MaxHealth}`
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

--[[
	V03, §4.4. THE POOL MUST COMFORTABLY EXCEED THE ITEMS IN IT.

	"Seven items across fifteen containers. You will open empty ones, and that is the point." If the
	item counts climb toward the container count, every container becomes a hit, the six seconds stop
	being a gamble and searching degenerates into a walk — which is precisely what §4.4 says the
	randomisation exists to prevent.

	`>= 2 x` is a TIGHT pin: 15 >= 14 passes with one container to spare. That tightness is deliberate
	rather than accidental. A looser `>= total + 1` would pass at 8 containers holding 7 items, where
	the property this protects has already been destroyed — so the loose version could never fire and
	would not be worth the line. If a V16 tune raises an item count and this fails, the fix is to raise
	ContainerCount and tag more parts in the map, not to widen the pin.
]]
local totalItems = Config.Items.SaltSpawnCount
	+ Config.Items.GarlicSpawnCount
	+ Config.Items.BuntotPagiSpawnCount

check(
	"searching is still a gamble — the container pool is at least twice the items placed in it",
	Config.Search.ContainerCount >= totalItems * 2,
	`ContainerCount={Config.Search.ContainerCount}, items={totalItems}`
)

--[[
	V03, §4.4. A SEARCH MUST OUTLAST THE ASWANG'S WHOLE APPROACH OVERHEAD.

	§4.4: the six seconds "are why the layout being random costs something". The cost is only real if
	an Aswang who notices a search starting can transform, close, and still arrive — so the hold must
	exceed the fixed price of a transform and the revert that follows it. Below that, a searcher is
	finished before the monster has finished changing shape and the risk economy is a decoration.

	This is a JUDGEMENT rather than an arithmetic identity — it does not account for distance, which
	the map decides — so it is pinned as a floor and expected to be re-argued at V16 with real players.
]]
check(
	"a search lasts longer than a transform and a revert — the monster can reach you mid-hold",
	Config.Search.SearchTime > Config.Monster.TransformTime + Config.Monster.RevertTime,
	`SearchTime={Config.Search.SearchTime}, Transform+Revert=`
		.. `{Config.Monster.TransformTime + Config.Monster.RevertTime}`
)

-- V03. A radius of zero or less is unsearchable and would read as a dead key bind.
check(
	"a container can actually be reached",
	Config.Search.RangeStuds > 0,
	`RangeStuds={Config.Search.RangeStuds}`
)

--[[
	V04, §4.4. THE NOISE BLOCK. Six of these eight guard things with no symptom: a tracker that reads
	an empty window, a cap that silently truncates one, a cue more precise than the pulse it is meant
	to be worse than, and a movement threshold that would turn V13's only input into a monster
	tracker.
]]

-- §4.4: "it is the loudest thing a survivor does". If a V16 tune inverts this, searching stops being
-- the risk the whole economy is built on and nothing in the game says so.
for action, tuning in Config.Noise.Actions do
	check(
		`searching is at least as loud as {action}`,
		Config.Noise.Actions.SEARCH.Loudness >= tuning.Loudness,
		`SEARCH={Config.Noise.Actions.SEARCH.Loudness}, {action}={tuning.Loudness}`
	)
	check(
		`searching carries at least as far as {action}`,
		Config.Noise.Actions.SEARCH.Radius >= tuning.Radius,
		`SEARCH={Config.Noise.Actions.SEARCH.Radius}, {action}={tuning.Radius}`
	)
end

-- Config.Search's own comment has claimed this since V02 ("a searching survivor is louder than the
-- tracker is sharp, for the whole first half of the night"). A comment is not a check.
check(
	"a search is louder than the early tracker is sharp",
	Config.Noise.Actions.SEARCH.Radius > Config.Tracker.EarlyRadius,
	`Radius={Config.Noise.Actions.SEARCH.Radius}, EarlyRadius={Config.Tracker.EarlyRadius}`
)

-- One search, one noise. Below this, tapping the search key faster than the hold lasts buys extra
-- noise events per search, which is both a history flood and a way to fake activity in a corner.
check(
	"a search cannot be louder than once per search",
	Config.Noise.Actions.SEARCH.MinInterval >= Config.Search.SearchTime,
	`MinInterval={Config.Noise.Actions.SEARCH.MinInterval}, SearchTime={Config.Search.SearchTime}`
)

-- V13's first pulse fires at Tracker.EarlyInterval and reads this history and NOTHING ELSE. A
-- shorter window means the first pulse of every round reads an empty table.
check(
	"the noise history outlives the first tracker pulse",
	Config.Noise.HistorySeconds >= Config.Tracker.EarlyInterval,
	`HistorySeconds={Config.Noise.HistorySeconds}, EarlyInterval={Config.Tracker.EarlyInterval}`
)

--[[
	THE BOUND, PROVEN RATHER THAN ASSERTED. Age is what bounds the history; MaxRecords is a safety
	net. If the net is tighter than the worst case the throttles allow, it silently starts trimming
	the WINDOW instead — the tracker goes blind on the early round and nothing reports it.

	THIS SUMS ACROSS ACTIONS RATHER THAN DIVIDING BY THE SMALLEST INTERVAL, and the first version of
	this check got that wrong. `NoiseService.lastEmitAt` is keyed `(UserId, action)` — its own comment
	says "keyed by action rather than by player alone so that using an item does not silence a
	search" — so one player emits EVERY action concurrently and the worst case is the sum, not the
	single fastest row. The V04 exploit audit proved the difference by simulation against the real
	`NoiseLog.append`: with a third emitter wired, the true peak hits the cap and starts eating the
	window while this check still reported 300.

	IT SUMS OVER EVERY PRICED ACTION, INCLUDING THE TWO WITH NO EMITTER. Pricing an action is the
	commitment; DOOR and SPRINT are priced (Config.Noise.Actions) and the chunk that finally wires one
	must not have to rediscover this relationship. Summing only over wired actions would make this
	check pass today and fail silently on the diff that adds the caller — which is the exact failure
	mode the check exists to prevent.

	THE `+ 1` IS THE FENCEPOST: a window of HistorySeconds at MinInterval spacing holds
	floor(H/I) + 1 records, not H/I. The audit's simulation measured 410 where the naive arithmetic
	said 400, and that gap is exactly one record per player per action.
]]
local worstCaseRecords = 0

for _, tuning in Config.Noise.Actions do
	worstCaseRecords += math.floor(Config.Noise.HistorySeconds / tuning.MinInterval) + 1
end

worstCaseRecords *= Config.Round.MaxPlayers

check(
	"the record cap can never truncate the history window",
	Config.Noise.MaxRecords >= worstCaseRecords,
	`MaxRecords={Config.Noise.MaxRecords}, worst case={worstCaseRecords}`
)

-- Every action needs a throttle for the sum above to be finite. Zero would also let one player fill
-- the history alone.
for action, tuning in Config.Noise.Actions do
	check(`{action} has a throttle`, tuning.MinInterval > 0, `{tuning.MinInterval}`)
end

-- §4.6: the pulse reveals an area, never an address. Being in EARSHOT should always beat the pulse,
-- and the cue's grid is what keeps it from being an address instead.
check(
	"the cue is coarse enough to stay an area",
	Config.Noise.CueGridStuds > 0 and Config.Noise.CueGridStuds < Config.Tracker.LateRadius,
	`CueGridStuds={Config.Noise.CueGridStuds}, LateRadius={Config.Tracker.LateRadius}`
)

--[[
	THE ANTI-ORACLE GUARD. No sprint verb exists; the only thing above the 16-stud baseline is a
	TRANSFORMED ASWANG. If a movement emitter is ever wired with a threshold under that, V13's only
	input becomes a monster tracker pointed at the monster — a leak with no role token in it, which
	`check:secrecy` structurally cannot see.
]]
check(
	"no speed this game can produce crosses the sprint threshold",
	Config.Noise.SprintSpeedStuds
		> Config.Trial.PlayerBaselineWalkSpeed * Config.Monster.TransformedSpeedMult,
	`SprintSpeedStuds={Config.Noise.SprintSpeedStuds}, fastest=`
		.. `{Config.Trial.PlayerBaselineWalkSpeed * Config.Monster.TransformedSpeedMult}`
)

--[[
	V07, §4.3/§5. THE DISGUISE NEEDS A CROWD TO HIDE IN.

	`Ambient.PerForm` must be at least 2. At 1, the moment the Aswang claims the only cat, there is
	exactly one cat in the barrio and it is the monster — §4.5's "It's the cat!" stops being a guess
	and becomes a lookup. This is the camouflage system's equivalent of invariant 1: tune the number
	and a win condition changes with nothing in the game to report it. §5 asks for 3-4; the floor
	pinned here is the point below which the mechanic is not merely weak but INVERTED.
]]
check(
	"Ambient.PerForm >= 2 — a lone entity of a form IS the monster",
	Config.Ambient.PerForm >= 2,
	`PerForm={Config.Ambient.PerForm}`
)

--[[
	AND THE CEILING, WHICH ONLY BECAME BREAKABLE WHEN THE FORM COUNT STOPPED BEING FOUR.

	§5 says "3-4 each" and the floor above says "at least 2". Nothing said "at most 4" — under four
	forms nobody would raise it, because 4 x 4 was already the largest ambient population anyone had
	costed. At six forms, `PerForm = 5` is 30 wandering rigs on a phone, which §5's mobile budget
	refuses and which no error message would ever mention.

	PINNED AGAINST THE SPEC SENTENCE RATHER THAN AGAINST A ROUND NUMBER, so the failure message can
	point at the thing being violated.
]]
check(
	"Ambient.PerForm <= 4 — §5 asks for '3-4 each' and 60% of players are on a phone",
	Config.Ambient.PerForm <= 4,
	`PerForm={Config.Ambient.PerForm}`
)

--[[
	V07, §4.3. THE HIDE MUST NOT BE FASTER THAN THE WITNESS RADIUS IS WIDE.

	`CamouflageWitnessRadius` must exceed `Monster.KillRange`. A monster that may hide from further
	away than it may kill from still has to break contact first; the other way round, it can kill a
	survivor and hide before the survivor's partner — standing at kill range, watching — has anything
	to report. The corpse-as-bait window §4.3 built the feed for depends on the killer being findable.
]]
check(
	"CamouflageWitnessRadius > KillRange",
	Config.Monster.CamouflageWitnessRadius > Config.Monster.KillRange,
	`witness={Config.Monster.CamouflageWitnessRadius}, kill={Config.Monster.KillRange}`
)

--[[
	V07, §4.3. THE ESCAPE MUST NOT OUTLAST THE REVEAL IT IS ESCAPING FROM.

	`SmokeDuration` must be SHORTER than `Items.SaltRevealDuration`. Smoke exists so a salted Aswang
	can disengage, not so it can wait out the glow inside a cloud: if the smoke outlasts the reveal,
	the survivors' counterplay is spent and they never see the thing they paid an item to expose.
	Compare §6.5 invariant 6, which pins the reveal above the stun for the mirror-image reason.
]]
check(
	"SmokeDuration < SaltRevealDuration — smoke covers a retreat, it does not erase the reveal",
	Config.Monster.SmokeDuration < Config.Items.SaltRevealDuration,
	`smoke={Config.Monster.SmokeDuration}, reveal={Config.Items.SaltRevealDuration}`
)

--[[
	V07, §4.3. THE HIDE MUST STAY INTERRUPTIBLE.

	`CamouflageEnterTime` must be greater than zero. At zero the windup vanishes and camouflage becomes
	instantaneous — which is not a weaker mechanic but a DIFFERENT one: §4.3's rule that risky acts are
	visible while they happen stops holding, and the survivor who walks in during the hide has nothing
	to walk in on. This number shipped once already as a declared-but-never-read Config value, so the
	behaviour existed only in a comment; this check is what stops that happening silently again.
]]
check(
	"CamouflageEnterTime > 0 — an instant hide has no counterplay",
	Config.Monster.CamouflageEnterTime > 0,
	`enter={Config.Monster.CamouflageEnterTime}`
)

--[[
	V07, §4.3. AND THE CUE MUST REACH BEYOND THE CLOUD IT ANNOUNCES.

	`SmokeCueRadius` must exceed `SmokeRadius`, or a player standing at the cloud's edge would have it
	appear on top of them rather than watching it form. It is also the assumption `Remotes.luau` leans
	on when it sends an EXACT position: everyone who receives the payload can see the thing it
	describes. Raise the cue radius well past visual range and that reasoning expires.
]]
check(
	"SmokeCueRadius > SmokeRadius — you see the cloud form, it does not appear on you",
	Config.Monster.SmokeCueRadius > Config.Monster.SmokeRadius,
	`cue={Config.Monster.SmokeCueRadius}, cloud={Config.Monster.SmokeRadius}`
)

--[[
	V09, §6.5 INVARIANT 4. GARLIC BUYS TIME, NEVER SAFETY.

	`GarlicDuration < Round.Duration / 4` is written in the spec (line 758) and restated in
	`Config.Items`' own comment, and until this line it was pinned NOWHERE. It is pillar six's
	invariant: §3's OUT list forbids a permanent safe room outright, and a garlic duration that crept
	toward a quarter of the round would build one a doorway at a time, with two bawang in play and no
	symptom anywhere — the round would simply start ending in a locked house.

	A QUARTER RATHER THAN SOME OTHER FRACTION, because two bawang is the whole supply: at the shipped
	values two consecutive placements deny one doorway for 30 of 300 seconds, a tenth of the round.
	The pin is the ceiling on ONE of them.
]]
check(
	"garlic buys time, never safety — one bawang is under a quarter of the round",
	Config.Items.GarlicDuration < Config.Round.Duration / 4,
	`GarlicDuration={Config.Items.GarlicDuration}, Round.Duration={Config.Round.Duration}`
)

--[[
	V09. THE BREACH TOLERANCE IS A SANITY BOUND, NOT A BALANCE RELATIONSHIP, and it is here because
	the failure is silent in the direction that matters.

	Positive-and-finite is `ItemCarry`'s `Limit` guard in a second file: `0` makes every jitter across
	the threshold a breach and rubber-bands an HONEST Aswang, which is the one observable this whole
	chunk exists to prevent, and `math.huge` deletes the backstop with nothing to say so. Under the
	place range because a tolerance wider than the reach that placed the garlic is not a tolerance.
]]
--[[
	V09. THE BREACH BACKSTOP MUST BE ABLE TO FIRE AT WALKING PACE, AND THIS PIN EXISTS BECAUSE IT ONCE
	COULD NOT.

	`GarlicBarrier.crossed` originally needed the destination sample more than
	`GarlicBreachToleranceStuds` past the plane within ONE `GarlicBreachSampleInterval`. That is a
	speed threshold of `tolerance / interval` — at the shipped 2.5 / 0.25 it was exactly 10 studs per
	second, and BELOW it the test could never fire at all. Setting `WalkSpeed = 9` deleted garlic
	permanently, at no risk, with the survivors concluding bawang was broken.

	The arming step no longer takes a tolerance, so the floor is gone — but the tolerance still gates
	the far-side streak, and if it ever grows past one sample interval of ordinary walking the streak
	stops accumulating for a player moving at normal pace and the floor comes back wearing a different
	hat. Pinned against the baseline walk speed rather than against a literal, so re-tuning either
	number is what fails this.
]]
check(
	"the garlic breach tolerance is under one sample interval of ordinary walking",
	Config.Items.GarlicBreachToleranceStuds
		< Config.Items.GarlicBreachSampleInterval * Config.Trial.PlayerBaselineWalkSpeed,
	`tolerance={Config.Items.GarlicBreachToleranceStuds}, interval={Config.Items.GarlicBreachSampleInterval}, walk={Config.Trial.PlayerBaselineWalkSpeed}`
)

--[[
	V09. THE SUPPRESSION MARGIN MUST EXCEED A CHARACTER'S HULL RADIUS, or the Aswang reaches the
	barrier plane and makes contact — restoring the `MoveDirection` signature and the deterministic
	resting offset that the whole suppression design exists to remove.
]]
check(
	"the garlic suppression margin clears a character's hull",
	Config.Items.GarlicSuppressMarginStuds > 2,
	`margin={Config.Items.GarlicSuppressMarginStuds}`
)

check(
	"the garlic breach tolerance is positive, finite, and under the place range",
	Config.Items.GarlicBreachToleranceStuds > 0
		and Config.Items.GarlicBreachToleranceStuds < Config.Items.GarlicPlaceRangeStuds,
	`tolerance={Config.Items.GarlicBreachToleranceStuds}, range={Config.Items.GarlicPlaceRangeStuds}`
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
