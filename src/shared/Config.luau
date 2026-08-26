--!strict
--[[
	Config — every tunable number in the game lives here.

	Rule: no magic numbers anywhere else in the codebase. During playtesting you
	will change these constantly; hunting them across ten files wastes a weekend.

	See docs/MVP-SPEC.md Appendix A for guidance on which knob to turn when.
]]

local Config = {
	Round = {
		Intermission = 25, -- seconds in lobby before a round starts
		Duration = 420, -- 7 minutes of "night" before sunrise
		EndScreen = 12, -- reveal + stats screen
		StartingDelay = 4, -- role assignment + teleport fade
		MinPlayers = 3, -- MUST be playable at this count (see spec §9 cold start)
		MaxPlayers = 8,

		--[[
			The floor between one player-triggered respawn and the next.

			`Humanoid.Died` is a state-machine trigger that ANY client can fire at will — the stock
			Escape → Reset button is enough — and outside a round it costs the server a full character
			rebuild plus appearance fetch, replicated to everyone. It is not a remote, so AntiCheat
			never sees it and `check:ratelimit` structurally cannot cover it. Eight clients looping
			reset would otherwise sustain eight rig builds a second for the whole lobby.

			Must stay well under `Intermission` so that a player who dies in the lobby always has a
			body back before STARTING deals them in. tests/config.test.luau pins that.
		]]
		RespawnCooldown = 3,
		-- How often the server pushes a RoundSnapshot to each client. This is a network cost paid
		-- per player per tick, and 60% of players are on a phone — raise it if the HUD stutters,
		-- lower it only with the mobile budget in mind.
		SnapshotInterval = 0.5,
	},

	Roles = {
		AswangCount = 1,
		-- A player who was Aswang recently gets reduced weight in the draw.
		-- Nothing kills a session faster than never being the monster.
		RepeatCooldownRounds = 2,
		IntroDuration = 3,

		--[[
			The anti-repeat weights (§4.2 "heavily reduced weight"). A player's draw weight is picked by
			how many rounds ago they were last the Aswang:

				1 round ago                        -> RecentAswangWeight
				2..RepeatCooldownRounds rounds ago -> OlderAswangWeight
				never, or longer ago               -> BaseWeight

			NONE OF THESE MAY BE ZERO. A zero weight is not "unlikely", it is "impossible", and with
			MinPlayers = 3 a zero-weight rule can leave a round with no eligible Aswang at all. The draw
			would then have to fall back to something, and a fallback that fires under a condition
			nobody tested is worse than a small number. `tests/role-draw.test.luau` proves no player
			starves; `tests/config.test.luau` proves the numbers stay ordered and positive.
		]]
		BaseWeight = 1,
		RecentAswangWeight = 0.1,
		OlderAswangWeight = 0.4,
	},

	Monster = {
		TransformTime = 1.2, -- visible windup — the core risk/reward moment
		RevertTime = 1.0,
		MaxTransformTime = 8, -- forced revert if no kill
		KillRange = 8, -- studs
		KillCooldown = 30, -- seconds after revert
		TransformedSpeedMult = 1.25,
		TransformAudioRange = 40, -- how far the transform sound carries
		CorpseDuration = 45,
		-- How long the corpse takes to fade once CorpseDuration is up. Long enough that a survivor
		-- walking in on the tail of it still registers a body was there; short enough that it is not a
		-- second, softer corpse with its own lifetime. §4.9: a fade, not a gore effect.
		CorpseFadeTime = 1.5,

		--[[
			The transform's LOOK (§4.3). No custom mesh — avatar scale, a colour and material shift,
			glowing eyes and a particle emitter. That is why this mechanic is cheap, and cheap is
			load-bearing for a project with no art budget.

			STORED AS RGB TRIPLES, NEVER AS Color3. `tests/config.test.luau` requires this file under
			LUNE, which has no Roblox datatypes at all. A `Color3.fromRGB(...)` here does not fail to
			typecheck — it fails at TEST time, in every balance test at once, with an error naming
			Config rather than the edit that broke it. MonsterService builds the Color3.
		]]
		TransformedScale = 1.15,
		TransformedTintRgb = { 90, 20, 20 },
		EyeGlowRgb = { 255, 45, 45 },
		EyeGlowRange = 6,
		EyeGlowBrightness = 3,
		TransformParticleRate = 12,
	},

	Salt = {
		SpawnCount = 4,
		StunDuration = 4,
		RevealDuration = 10,
		ThrowRange = 25,
		CarryLimit = 1,

		--[[
			How close a player must be to a pouch for the server to hand it over (C13).

			THERE IS NO PICKUP REMOTE, and this number is why. The shape is the rule: the server
			resolves what you are standing at from your own character's position, and the client names
			nothing. A pickup that took an argument would be a free "give me salt"
			handler needing its own budget, its own validation and its own verdict union; a proximity
			tick needs none of those and cannot be spammed, because there is nothing to spam.

			DELIBERATELY SMALL, and V01 removed the number it used to be measured against — the task
			system's nine-stud presence range. Presence was a thing you did on purpose and could
			tolerate standing near; a pickup is a thing that happens TO you as you walk past, and one
			that fires from nine studs away picks pouches up through walls. **V03 owes this a new
			right-hand side**: the container search range is what it must sit under once that lands,
			and until then nothing in `tests/config.test.luau` pins it at all.
		]]
		PickupRangeStuds = 6,

		--[[
			The half-angle, in degrees, of the cone a throw sweeps (C14). The server picks the nearest
			valid target inside it; the client sends only a direction.

			IT IS A CONE RATHER THAN A RAYCAST ON PURPOSE. A ray demands the accuracy of a shooter from
			a player on a phone (§5: ~60% of players), and §4.6 is buying counterplay, not aim. It is
			also why the throw cannot be a probe: widening it does not make salt tell you MORE, because
			a miss and a hit on a survivor are the same silent outcome.

			`tests/config.test.luau` pins it under 90. At 90 the cone is a hemisphere and at more than
			90 you hit things behind you, which is not a throw.
		]]
		ThrowConeDegrees = 20,

		--[[
			How many `SaltSpawn` points the map is expected to carry, against which `SpawnCount` pouches
			are placed. It feeds `server/pure/SearchPool.evaluate` — the one verdict module every
			tag-driven pool in this game shares, rather than a second copy of it.

			It must be at least `SpawnCount` or the round cannot place its pouches; the test pins that.
			C17 owns the actual count in the map.
		]]
		PouchPoolSize = 6,

		-- The pouch, and the reveal glow. RGB TRIPLES, NEVER Color3 — same reason as Monster's palette
		-- as Monster's palette. `RevealGlow*` is a Highlight's two colours.
		PouchRgb = { 240, 238, 225 },
		RevealGlowFillRgb = { 255, 250, 235 },
		RevealGlowOutlineRgb = { 190, 235, 255 },
	},

	--[[
		§4.5, C25. The quick-chat wheel.

		THE LAYOUT NUMBERS ARE HERE RATHER THAN IN THE CONTROLLER ON PURPOSE, and they are the ones
		most likely to move: §5 puts ~60% of players on a phone, and "is this reachable with one
		thumb" is a question answered by holding a phone, not by reading code. A wheel radius baked
		into a controller is a wheel radius nobody re-tunes after the first playtest.
	]]
	QuickChat = {
		--[[
			How far the `"It's [nearest player]!"` phrase will look for a target, in studs.

			BOUNDED ON BOTH SIDES BY `tests/config.test.luau`, and both bounds are security rather
			than feel:

			  · It MUST exceed `Monster.KillRange` (8). The moment §4.5 exists for is the one where
			    something is close enough to kill you and you have no time to type. A range that
			    cannot name the thing standing on top of you has no reason to exist.
			  · It MUST stay far below map scale. This is the half that matters for §6.2. The phrase
			    resolves its target from the sender's own position, so a large range turns it into a
			    map-wide proximity radar the sender can poll — and the player with the most to gain
			    from "who is near me, through walls" is the Aswang hunting. Line of sight is the
			    primary defence (see QuickChatService); this is the second.

			    **V01 REMOVED THE UPPER BOUND'S OTHER OPERAND** — it used to be pinned under the task
			    system's 220-stud marker range, and `tests/config.test.luau` enforced it. Nothing
			    pins it now. V03 owes this a new right-hand side.
		]]
		AccuseRangeStuds = 40,

		--[[
			THE FIELD OF VIEW THE ACCUSATION NEEDS, as a half-angle in degrees.

			Added after an exploit audit deflated the original claim. Range and a raycast alone see
			BEHIND the sender, through fog and darkness, so a failed accusation was a free silent
			"nobody has line to me" — a transform-safety check bought for one token without looking.
			With this term a miss means "nobody in FRONT of me", which is what the player's own eyes
			already said, and that equivalence is the whole reason the phrase is safe to spam.

			60 is a little narrower than a typical third-person camera frustum, so the phrase names
			people the player can actually see on screen rather than people technically unoccluded.
			`tests/config.test.luau` pins it inside (0, 90): at or past 90 it includes what is beside
			and behind you, which is the property being removed.
		]]
		AccuseHalfAngleDegrees = 60,

		-- How long a world ping marker lives on a receiving client, in seconds. Long enough to walk
		-- toward, short enough that a plaza full of stale pings is not the HUD.
		PingLifetimeSeconds = 8,
		-- How long a received phrase stays on screen, and how many stack before the oldest is dropped.
		MessageLifetimeSeconds = 6,
		MaxVisibleMessages = 4,

		-- The wheel's radius in pixels, measured from the press point to the middle of a sector.
		WheelRadiusPx = 150,
		--[[
			THE ACCESSIBILITY FLOOR FOR A TOUCH TARGET, and the number the mobile argument rests on.
			44px is the long-standing minimum for a reliable thumb press; a sector whose narrowest
			dimension falls below it is a sector that gets mis-hit mid-chase, which for this feature
			means accusing the wrong person. Pinned in `tests/config.test.luau` against
			`WheelRadiusPx` so shrinking the wheel cannot silently shrink the targets below it.
		]]
		MinTouchTargetPx = 44,
		-- A drag shorter than this radius from the press point is a CANCEL, not a selection. Without it,
		-- opening the wheel and thinking better of it sends whichever sector the thumb was resting on.
		DeadRadiusPx = 30,
	},

	--[[
		XP, LEVELS AND COINS (C32, §7). The award table of §4.8's end screen, and the curve it fills.

		THE TWO HALVES MUST BE TUNED TOGETHER, which is why they share a block. The award decides how
		fast the bar fills and the curve decides how far it has to go; changing one alone is how
		"level 5 in twenty minutes" and "level 5 in nine hours" both ship from the same table.
		`tests/xp-curve.test.luau` walks a plausible session end-to-end and prints what a level costs
		in rounds, so the number is measured rather than imagined.

		The award is applied by `shared/pure/XPCurve.awardFor`, which is also where the reason every
		role-conditional term below is SAFE is written down. Read that header before adding one.
	]]
	Economy = {
		-- Paid to everyone dealt into the round, whatever happened. §7's argument is that a session
		-- should end near a milestone; a losing round paying nothing ends it where it started.
		XPPerRound = 50,
		-- Your side won. Role-conditional, and safe only because it lands at ENDING, after the reveal.
		XPWinBonus = 40,
		-- You were a survivor and you were still alive at ENDING. Not paid to the Aswang, which is
		-- alive at the end of every round it does not abort.
		XPSurvivorEscapeBonus = 25,
		-- The Aswang's split, per validated kill. At `Round.MaxPlayers = 8` a maximal round is five
		-- kills, so this caps the Aswang's outcome bonus near the survivors' win-plus-escape total.
		XPPerKill = 15,

		CoinsPerRound = 25,
		CoinsWinBonus = 15,

		--[[
			THE LEVEL CURVE, AS `XPCurve.Curve`. Level 1 -> 2 costs `XPPerLevel`; every level after
			costs `XPPerLevelGrowth` more than the one before, so the cumulative cost is triangular.

			Why not flat: a flat curve makes level 40 and level 4 feel identical, and §7 wants the bar
			to mean something at both ends. Why not exponential: an exponential curve makes the second
			half unreachable, which is the "burn your content" failure §7 opens with.

			`MaxLevel` is load-bearing rather than flavour. It bounds `XPCurve.levelFor`'s walk against
			a corrupt XP value, and it is where the next level costs nothing — the division by zero
			that `XPCurve` pins to a full bar instead.
		]]
		XPPerLevel = 150,
		XPPerLevelGrowth = 60,
		MaxLevel = 100,
	},

	--[[
		THE DAILY LOGIN STREAK (C33, §7) — "the single highest-ROI retention feature you can build".

		SEVEN ENTRIES, AND THE SEVENTH IS THE POINT. §7 asks for "escalating rewards with a meaningful
		day-7 payoff", so the table escalates gently for six days and then steps hard, which is what
		makes day 7 a thing to come back FOR rather than the last of seven equal days. The cycle
		length IS `#Rewards` — `shared/pure/DailyStreak` reads no separate number, so the two cannot
		disagree — and it WRAPS, so day 7 recurs weekly.

		PRICED SO THAT LOGGING IN NEVER BEATS PLAYING, which is the failure this table falls into on its
		own. The first version of it paid 580 coins a week — more than `lantern_dugo` costs outright —
		so the optimal play was to open the game and close it, seven times. `tests/config.test.luau`
		pins the week's total against the cheapest coin unlockable, because nothing about the table
		looks wrong when you read it; you have to add it up.

		Day 7 is a STEP rather than a nudge: about four rounds' worth of coins, and more than triple day
		six. That is what makes it a day to come back FOR instead of the last of seven equal ones.
	]]
	Daily = {
		Rewards = {
			{ XP = 10, Coins = 10 },
			{ XP = 15, Coins = 12 },
			{ XP = 20, Coins = 15 },
			{ XP = 25, Coins = 20 },
			{ XP = 30, Coins = 25 },
			{ XP = 40, Coins = 30 },
			{ XP = 100, Coins = 100 },
		},
	},

	--[[
		THE SIX COSMETICS (C34, §7, §8.2).

		§7: "~6 unlockable cosmetics at launch — enough to see progress, not enough to burn your
		content." §8.2 names the kinds worth having: "sell what appears in clips — death effects,
		transform auras, lantern colours."

		THREE SLOTS, TWO ITEMS EACH, AND NO SCHEMA CHANGE. `Skin`, `Lantern` and `DeathFX` are the
		field names `ProfileMigration`'s `Cosmetics.Equipped` has carried since C31, and `Slot` below
		is spelled to match them exactly because that is what `CosmeticsService` assigns into. A
		transform aura would be a fourth slot and therefore a v2 migration, so §8.2's third example is
		deliberately deferred rather than smuggled in.

		THE MIX IS §7's: two earned by level, three bought with coins, one behind a gamepass. The
		gamepass one is LISTED AND LOCKED — `pure/Cosmetics.evaluatePurchase` refuses it with
		NOT_FOR_SALE until C37 supplies a real product id. C37 depends on C34 and not the reverse, so
		the alternative was a purchase wired to gamepass id 0, which succeeds silently for everybody.

		`Rgb` is a triple, matching how `Config.Monster` stores every colour, so a
		value stays data rather than a constructed Color3.
	]]
	Cosmetics = {
		--[[
			The lantern light's reach and strength, shared by every lantern in the catalogue so the
			COLOUR is the only thing an item changes. A lantern that also changed brightness would be
			a gameplay advantage sold for coins, which §8.1's "no pay-to-win" line refuses.
		]]
		LanternRange = 14,
		LanternBrightness = 1.4,

		-- The death burst (§4.9: "creepy and tense", not graphic — a puff and a fade, no blood).
		DeathFXParticles = 24,
		DeathFXLifetime = 1.6,
		DeathFXSpeed = 7,

		Catalogue = {
			-- The three defaults. Always owned, never for sale, and present in the list so the lobby
			-- can cycle back to them and `Cosmetics.find` answers for what a fresh profile wears.
			{
				Id = "default",
				Slot = "Skin",
				Name = "Barrio kid",
				Source = "DEFAULT",
				Level = 0,
				Price = 0,
				Rgb = { 204, 190, 170 },
			},
			{
				Id = "lantern_default",
				Slot = "Lantern",
				Name = "Gasera",
				Source = "DEFAULT",
				Level = 0,
				Price = 0,
				Rgb = { 255, 190, 120 },
			},
			{
				Id = "deathfx_default",
				Slot = "DeathFX",
				Name = "Hangin",
				Source = "DEFAULT",
				Level = 0,
				Price = 0,
				Rgb = { 190, 190, 200 },
			},

			-- The six. Levels are early enough that a first session reaches one of them.
			{
				Id = "lantern_asul",
				Slot = "Lantern",
				Name = "Asul",
				Source = "LEVEL",
				Level = 2,
				Price = 0,
				Rgb = { 120, 190, 255 },
			},
			{
				Id = "skin_abo",
				Slot = "Skin",
				Name = "Abo",
				Source = "LEVEL",
				Level = 4,
				Price = 0,
				Rgb = { 122, 122, 130 },
			},
			{
				Id = "lantern_dugo",
				Slot = "Lantern",
				Name = "Dugo",
				Source = "COINS",
				Level = 0,
				Price = 450,
				Rgb = { 255, 96, 84 },
			},
			{
				Id = "deathfx_alikabok",
				Slot = "DeathFX",
				Name = "Alikabok",
				Source = "COINS",
				Level = 0,
				Price = 600,
				Rgb = { 226, 206, 172 },
			},
			{
				Id = "skin_ginto",
				Slot = "Skin",
				Name = "Ginto",
				Source = "COINS",
				Level = 0,
				Price = 750,
				Rgb = { 236, 190, 92 },
			},
			{
				Id = "deathfx_apoy",
				Slot = "DeathFX",
				Name = "Apoy",
				Source = "GAMEPASS",
				Level = 0,
				Price = 0,
				Rgb = { 255, 132, 48 },
			},
		},
	},

	--[[
		Profile persistence (C31, §6.6).

		THE SCHEMA VERSION IS NOT HERE, AND THAT IS DELIBERATE. It lives in
		`shared/pure/ProfileMigration.luau` as `CURRENT_VERSION`, because that module must run under
		Lune and cannot require this file — Lune has no `script`. Duplicating it here would create two
		sources of truth for the one number where disagreement means data loss, and the copy the
		migration actually reads would be the one nobody edited.
	]]
	Profile = {
		--[[
			The DataStore name. CHANGING THIS ORPHANS EVERY EXISTING PLAYER — it is a new namespace,
			not a rename, and there is no migration path back. It carries no version suffix on
			purpose: `ProfileMigration` is how the schema moves, and a name bump would make that
			module dead code the first time it was needed.
		]]
		StoreName = "PlayerProfile",

		-- How many times to retry `StartSessionAsync` before giving up on a player. A failed session
		-- is not fatal — they play, nothing saves, and the warn says so — but it should be rare.
		SessionStartAttempts = 3,
		SessionStartRetryDelay = 4,

		--[[
			The wall-clock budget `ShutdownFlush.flushAll()` may spend inside `game:BindToClose`.
			ROBLOX GIVES ABOUT 30 SECONDS AND THEN KILLS THE PROCESS MID-WRITE, so this must stay
			under it with room to spare — pinned in `tests/config.test.luau` rather than trusted.
		]]
		ShutdownFlushBudget = 25,
	},

	-- The Solo Trial: tutorial + low-population fallback. See spec §9.1.
	-- Exists because the closest competitor lost 79.9% of players before their
	-- first objective (Appendix C). Must never grow into a PvE campaign.
	Trial = {
		Enabled = true,
		Duration = 90,
		TasksToComplete = 2,
		-- V01. Was `Config.Tasks.PresenceRangeStuds` / `HoldTime`, which the round's task system owned
		-- until V01 deleted it. The trial kept the VALUES because its own header's argument is about
		-- teaching a consistent hold — and from V03 the thing it must stay consistent with is the
		-- container search, so revisit both when `Config.Search` lands.
		PresenceRangeStuds = 9,
		HoldTime = 8,
		ScriptedChaseAt = 55, -- seconds in: the Aswang reveals itself
		OfferBelowPlayerCount = 3, -- == Round.MinPlayers

		-- The remaining beats, all measured in seconds from the session's start so the timeline is
		-- readable as a single column. `tests/config.test.luau` pins their ordering (Phase 2.3),
		-- because a chase scheduled after the trial ends teaches nothing and produces no symptom.
		SaltGivenAt = 40, -- pouch appears BEFORE the transform, so the tell lands with a tool in hand
		SaltTaughtAt = 58, -- §10's folklore line, 3s after the transform: after the fright, not during
		HandoffAt = 84, -- the closing line, with time left to read it

		--[[
			THE SCRIPTED RIG. It is not a Player, has no Role and never goes through MonsterService —
			see the plan's §1.1. These are its own numbers because reusing `Config.Monster`'s would
			couple a tutorial to live balance: retuning the real Aswang's speed at M12 would silently
			retune the tutorial, and the tutorial's job is to be survivable.

			DELIBERATELY SLOWER THAN THE PLAYER. The trial's Aswang must never catch anyone: a death
			here needs a death path, a respawn and a re-entry, and all three are how a 90-second
			tutorial becomes a PvE level. It menaces and it is stunned. That is the whole encounter.
		]]
		--[[
			13 UNTIL A PLAYTEST MEASURED WHAT IT ACTUALLY DID. At 13 studs/s against
			`SnapshotInterval = 0.5`, one tick moved the rig 6.5 studs — larger than the entire
			`ChaseStopStuds = 6` hold zone — so it stepped straight through and came to rest 1.70
			studs from the player, deterministically, every run. `stepRig` now clamps its step so the
			stop is correct at any values; 12 is the largest speed that also keeps a single tick from
			crossing the whole zone, which `tests/config.test.luau` now pins.

			Still comfortably under `PlayerBaselineWalkSpeed = 16`: the trial's Aswang must never
			catch anyone, because a death here needs a death path, a respawn and a re-entry.
		]]
		ChaseWalkSpeed = 12,
		ChaseStopStuds = 6, -- how close it gets before holding station
		ChaseStunSeconds = 6, -- how long a salt hit holds it, ending the chase beat

		--[[
			Roblox's stock `Humanoid.WalkSpeed`, mirrored here for ONE reason: it is the number
			`ChaseWalkSpeed` has to stay under, and an invariant cannot be pinned in
			tests/config.test.luau against a constant that lives inside the engine. There is no
			`Config.Player` block in this repo (checked at plan time — nothing anywhere sets a walk
			speed), so survivors run at the engine default and this records it.

			IF THE GAME EVER SETS A REAL WALK SPEED, this stops being the right comparison and the
			invariant becomes a lie that still passes. Delete this field and point the test at the
			real one; do not update the number here to match.
		]]
		PlayerBaselineWalkSpeed = 16,

		-- How often the server pushes a TrialSnapshot to the one player in a session. Matches
		-- Round.SnapshotInterval's job without reading it: these are different features and a shared
		-- number is a coupling nobody documented.
		SnapshotInterval = 0.5,

		-- How far above the TrialSpawn anchor a player is placed. Here rather than hardcoded because
		-- it depends on the zone's floor geometry: too low and the character spawns inside the floor
		-- and is ejected, too high and they take a visible drop on entering the tutorial.
		SpawnLiftStuds = 5,
	},

	Community = {
		GroupId = 0, -- TODO(M10): set once the Roblox group exists
		GroupJoinRewardCoins = 250,

		--[[
			HOW LONG A "NOT IN THE GROUP" ANSWER IS TRUSTED BEFORE ASKING ROBLOX AGAIN (C39).

			`IsInGroupAsync` is a web call against a quota this server shares across every player on
			it, and the claim button is pressable by someone who is not a member — so without this,
			eight clients auto-firing the remote sustain a steady drip of group-API calls forever, and
			the failure that produces is the bad one: the API throttles, the check throws, and honest
			members get refused.

			ONLY NEGATIVE ANSWERS ARE CACHED, never positive ones — a positive is consumed
			immediately and the claim is over. Thirty seconds is the trade: long enough that a held
			button costs one call rather than dozens, short enough that a player who alt-tabs to join
			the group and comes straight back does not sit at a stale refusal long enough to give up.
		]]
		GroupCheckNegativeCacheSeconds = 30,

		-- C24, §9 item 3. A waiting player must never see a static screen.
		LobbyTipSeconds = 7, -- how long each tip holds before the next
	},

	-- Award thresholds mirror the public funnel we can read back via the API.
	Badges = {
		Welcome = 0, -- TODO(M9): fill in badge IDs after creating them
		FirstTask = 0,
		FirstRound = 0,
		FirstBlood = 0,
		BalikBalik = 0,
		-- LAUNCH GATE: FirstTask / Welcome must exceed this or FTUE is broken.
		FirstTaskConversionGate = 0.50,
	},

	--[[
		THE MOBILE BUDGET (§5, C27), AND THE SPEC CALLS IT NON-NEGOTIABLE.

		~60% of this game's players are on a phone. Every number in this block is spent on one thing:
		holding 30fps on a mid-range Android DURING A CHASE, which is the worst case rather than the
		lobby. Until C27 the block was two numbers nothing read.
	]]
	Performance = {
		--[[
			§5: "Cap dynamic lights to ~8 visible at once — many point lights are the #1 mobile FPS
			killer." `shared/pure/LightBudget` now spends this: `PerformanceController` keeps the
			nearest few MAP lights lit on each client and switches off the ones behind that client's
			camera or across the barrio.

			CLIENT-SIDE, ROLE-BLIND, AND NOTHING CROSSES THE WIRE. It is a rendering decision over a
			distance from a camera, so every client runs the same rule over its own view.
		]]
		MaxVisibleLights = 8,

		--[[
			HOW MANY OF THE EIGHT ARE NOT THE MAP'S TO SPEND.

			A transformed Aswang carries one PointLight on its head (`Monster.EyeGlowRgb`) and every
			salt pouch in view carries another (`ItemService`). Those are TELLS — the eye glow is the
			warning §4.3 is built around and the pouch glow is how §4.6's counterplay is found — so
			the culler is never shown them: it only ever sees lights the greybox tagged `MapLight`,
			and these slots are subtracted from its allowance so the scenery cannot crowd them out.

			Three: one monster, and up to two pouches close enough to matter at once.

			`tests/config.test.luau` pins this BELOW `MaxVisibleLights`. At or above it the barrio
			goes fully dark, which does not cost frames — it breaks §5's sightline rule ("you should
			almost always be able to see *something*"), and total darkness is confusing, not scary.
		]]
		ReservedGameplayLights = 3,

		-- Past this many studs a lantern contributes nothing a player can see, so it is off whatever
		-- the budget says. Comfortably beyond the barrio's own lantern Range (26 studs).
		LightCullRadiusStuds = 140,

		--[[
			THE ANTI-FLICKER MARGIN, and the reason the cull is a tested pure module rather than a
			sort. A lit lantern keeps its slot until a rival is this many studs closer; without it,
			two lanterns at an equal distance trade the last slot on every pass while a player stands
			still between them, and a strobing street lamp is worse than the frame it saved.
		]]
		LightHysteresisStuds = 12,

		-- How often the cull runs. Lights do not move and the camera does not teleport, so a rate
		-- near the snapshot's would be spending frames re-deciding something that did not change.
		LightCullIntervalSeconds = 1,

		--[[
			§5's target, and C27's done condition measures against it: "30fps sustained on a real
			phone during a chase". Read by the on-screen FPS readout that `PerformanceController`
			draws when `Debug.VerboseLogging` is on — the phone test needs a number visible ON the
			phone, and Studio's frame rate means nothing here.
		]]
		TargetFPSMobile = 30,
	},

	--[[
		C28 — THE SKY IS THE COUNTDOWN (Appendix C.3, §5).

		Appendix C.3 is the teardown of the competitor's one genuinely good feature, a "dynamic
		sunset-to-night" cycle that decorated their round and did nothing for it. The instruction is
		to steal it and point it at something: **the sky visibly progressing toward sunrise IS the
		timer.** Diegetic, no UI, free tension — a player being chased is looking at the world, not at
		the corner of their screen where the clock is.

		WHAT IS HERE AND WHAT IS DELIBERATELY NOT. The NIGHT is not in this block. It is authored in
		`tools/greybox/barrio.luau` — ambient, fog, the Atmosphere — because that is art direction and
		C30 will retune it. `SkyController` CAPTURES those values from the place at startup and treats
		them as the baseline, so what lives here is only the destination and the shape of the trip.

		THAT CAPTURE IS THE C04 LESSON RESTATED. MonsterService's revert once restored hardcoded
		defaults instead of captured state and permanently branded the ex-Aswang; a lobby that comes
		back one shade warmer after every round is the same bug running slower. `SkyCycle.frameFor(0)`
		returns the captured night EXACTLY, and `tests/sky-cycle.test.luau` pins it.

		THE MULTIPLIERS ARE MULTIPLIERS ON PURPOSE. Fog distance is a fraction of the map — barrio
		scales it by `SCALE` — so "2.6x the authored fog" survives a map resize that an absolute
		number would silently break.
	]]
	Sky = {
		--[[
			WHERE THE NIGHT STARTS AND ENDS, in Roblox `ClockTime` hours (0-24, 6 is sunrise).

			3.0 rather than the barrio's authored 0 (midnight), and that is the one number here worth
			arguing about. Linear from 0 the sky would be visually identical for the first two thirds
			of a round — Roblox's horizon does nothing between midnight and about 4 — so the clock
			would be a countdown that reads as static for four minutes and then dawns all at once.
			Starting at 3 puts the whole round inside the part of the cycle the eye can actually
			follow.

			IT IS ALSO THE LOBBY'S SKY, because `SkyCycle` maps every non-round phase to progress 0.
			The place file's own midnight is what a map author sees in Studio; a joining player sees
			this. One night, one starting point, and no jump at the moment a round begins.

			6.4 rather than 6.0: the sun is a little above the horizon rather than exactly on it, so
			the last thirty seconds are unmistakably morning rather than ambiguously grey.
		]]
		StartClockTime = 3.0,
		EndClockTime = 6.4,

		-- Dawn as multiples of whatever the place authored for the night. See the block header.
		DawnBrightnessMult = 2.4,
		DawnFogEndMult = 2.6,
		-- Below 1 because fog LIFTS at dawn. This is also the term that quietly gives back sightlines
		-- in the last minute of a round, which is when the gate rush happens.
		DawnAtmosphereDensityMult = 0.55,

		--[[
			The two ambients are absolute RGB triples rather than multipliers, because dawn is a
			COLOUR SHIFT and not a brightening: the night is blue (14,16,26) and the morning is warm.
			Multiplying a blue by 2.4 gives a brighter blue, which reads as moonlight turned up.

			RGB TRIPLES, NEVER Color3, for the reason `Config.Monster`'s block gives at length: this
			file is required under LUNE by `tests/config.test.luau`, which has no Roblox datatypes at
			all. `SkyController` builds the Color3.
		]]
		DawnAmbientRgb = { 74, 66, 62 },
		DawnOutdoorAmbientRgb = { 138, 122, 110 },

		--[[
			How long the sky takes to fall back to the authored night when a round ends.

			Not instant, because the end screen sits over a lit world for `Round.EndScreen` seconds
			and a hard cut to midnight underneath the reveal is a flicker at the exact moment §4.8
			calls "the screenshot people share". Comfortably shorter than `Round.Intermission`, so the
			next round always begins from a settled night — pinned in `tests/config.test.luau`.
		]]
		RestoreSeconds = 3,

		--[[
			THE LINE BETWEEN A STEP AND A TWEEN, as a fraction of the whole night.

			A running round advances the sky by `SnapshotInterval / Duration` per push — about a
			thousandth — which is invisible as an assignment and would cost two Tween objects twice a
			second for seven minutes to smooth something no eye can resolve. So small moves are
			assigned and only JUMPS are tweened, over `RestoreSeconds` above.

			There are exactly two jumps in a round's life: ENDING pins the sky to dawn (a leap, if the
			round was aborted early), and the lobby afterwards drops it back to night. This number
			only has to sit above the per-snapshot step and below those two, which is two orders of
			magnitude of room — it is a threshold, not a knob to tune.
		]]
		TweenAboveProgressDelta = 0.05,
	},

	--[[
		AUDIO (C29, §5 and §14.3: "audio matters more than visuals in horror… the cheapest
		fear-per-hour you can buy").

		EVERY ASSET ID IN THE GAME IS IN ONE TABLE, and that is the point of putting them here rather
		than beside the code that plays them. The sounds are sourced and APPROVED BY A PERSON — "does
		this sound scary" is not something any check can answer — so the ids arrive after the code
		does, and when they arrive it must be one edit to this table and not a hunt through a
		controller. `docs/AUDIO-ASSETS.md` carries the other half: creator, duration and date, which
		a bare id cannot record and which is what you need when a Creator Store asset is moderated
		away and leaves a hole.

		A BLANK ID IS A VALID, SUPPORTED STATE, not a placeholder to be tidied up. `AudioController`
		creates, positions, ranges and destroys the Sound either way and simply plays nothing — the
		precedent the transform stinger set at C04 (see that controller's header). So the game is
		fully playable with this table exactly as it ships below, and every phase of C29 before the
		sourcing pass is verifiable with it empty.

		KEYS MATCH `shared/pure/AudioCues`, and `tests/config.test.luau` pins BOTH directions through
		that module's public API: every bed and one-shot it names has a slot here, and every slot
		here is reachable by some rule of its. So a rename in either file reds the balance suite
		rather than becoming a silent nothing at 3am in a playtest.

		The one case that enumeration cannot reach is a NEW event cue id added to `AudioCues` with no
		slot here — `PERMITTED_PHASES` is private and the API cannot list it. That case surfaces at
		runtime instead, as the controller's `warn` for a cue id with no asset, which is weaker and
		is the reason this note exists rather than a claim that the check is total.
	]]
	Audio = {
		Assets = {
			CUE_BED_LOBBY = "rbxassetid://9112764040",
			CUE_BED_NIGHT = "rbxassetid://9112764573",
			CUE_BED_DAWN = "rbxassetid://9112831284",
			CUE_WIND = "rbxassetid://125270272833477",
			CUE_DOGS = "rbxassetid://9120051478",
			CUE_FOOTSTEP = "rbxassetid://132221529613537",
			CUE_TRANSFORM = "rbxassetid://9125474505",
			CUE_HEARTBEAT = "rbxassetid://139459003161851",
			CUE_SUNRISE = "rbxassetid://4501062448",
		},

		-- The bed sits UNDER everything. A night ambience loud enough to notice is a night ambience
		-- competing with the one sound in the game that has to be heard through a wall (§4.3's tell).
		BedVolume = 0.35,
		BedFadeSeconds = 2,

		-- Wind and dogs, scheduled locally at a random interval in this band. Random per client and
		-- per phase, so two players do not hear the same dog — a shared schedule would be a clock
		-- every client agrees on, and this game has enough of those.
		OneShotVolume = 0.5,
		OneShotMinSeconds = 25,
		OneShotMaxSeconds = 70,

		-- IDENTICAL FOR EVERY CHARACTER IN THE GAME. There is no per-role, per-state or transformed
		-- variant of this number and there must not be: a louder footstep for one player is a role
		-- broadcast with no role token in it, which `check:secrecy` cannot see. See
		-- `.claude/lessons/absence-is-observable.md`.
		FootstepVolume = 0.4,

		--[[
			How long the footstep retarget waits for Roblox to attach its default character sounds.

			It used to not wait at all, and a C29 playtest measured the consequence: the retarget lost
			the race on every character tested. The engine creates `HumanoidRootPart.Running`
			asynchronously after the character Model exists, so a synchronous `FindFirstChild` on
			`CharacterAdded` reliably finds nothing.

			Generous on purpose. Losing this race is not a missing sound, it is a per-character
			DIFFERENCE in a cue whose whole safety argument is that it is a constant across every
			player (`.claude/lessons/absence-is-observable.md`).
		]]
		FootstepWaitSeconds = 10,

		StingerVolume = 0.9,

		--[[
			THE HEARTBEAT, AND THE ONE RELATIONSHIP THAT MATTERS ABOUT IT.

			It plays only while a monster is TRANSFORMED — a state every client already knows about,
			since `MonsterTransformed` is FireAllClients and the character wears a scale change, a red
			tint and a head PointLight. It is created by the local client on a replicated character,
			so it exists in no other client's instance tree.

			`HeartbeatRange` MUST NOT EXCEED `Monster.TransformAudioRange` (40 studs), and
			`tests/config.test.luau` pins that. §4.3 specifies exactly how far the transform carries;
			a heartbeat audible past it would quietly rewrite the tell's range without anyone editing
			the number that documents it.
		]]
		HeartbeatVolume = 0.7,
		HeartbeatRange = 28,

		-- Fired once per round when `SkyCycle.progressFor` crosses this. Before 1.0 deliberately: the
		-- sound should land while the sky is still moving, not as a stamp on the reveal.
		SunriseVolume = 0.6,
		SunriseAtProgress = 0.92,

		--[[
			How long a one-shot Sound survives before the client destroys it. A `Sound.Ended` signal
			would be the obvious answer and it is the wrong one: A BLANK SoundId NEVER ENDS, so every
			cue would leak an instance for the whole of development, which is exactly the state §5's
			budget cannot afford and exactly the state this project is in until the sourcing pass.
			Longer than any stinger the `asset-pipeline` skill's 0.2-4s band can produce, and
			`tests/config.test.luau` pins it BELOW `OneShotMinSeconds` so cleanup always beats the
			next schedule and instances cannot accumulate.
		]]
		CueCleanupSeconds = 6,
	},

	--[[
		Rate limits, one budget per client->server remote (C02).

		A budget is a token bucket: `Capacity` tokens, refilling at `RefillPerSecond`, one token per
		request. Capacity is the BURST a legitimate player may produce in one moment; RefillPerSecond is
		the SUSTAINED rate they may hold.

		Tune these LOOSER than legitimate play, never tighter. A limiter that refuses a real player is a
		gameplay bug that presents as lag, and it is far more expensive than an exploiter getting three
		extra requests through — the validation behind the limiter is what actually refuses them.
		`tests/anti-cheat-budgets.test.luau` pins that relationship for the remotes where a legitimate
		cadence is known.
	]]
	AntiCheat = {
		-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
		-- The test pins BOTH directions, because a budget for a remote that no longer exists is a
		-- rename nobody noticed and a remote with no budget is refused outright (see UnknownRemote).
		Budgets = {
			-- Deliberate, rare acts. Capacity covers a double-tap and a reconnect retry; nothing more.
			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
			--[[
				C34. Priced like the equip next door rather than tighter, even though it SPENDS: the
				limiter is not what stops a double purchase — `evaluatePurchase` returning
				ALREADY_OWNED is — and a player browsing a six-item shop presses buy more than once.
			]]
			RequestBuyCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
			RequestClaimDaily = { Capacity = 2, RefillPerSecond = 0.1 },
			--[[
				C39. Tighter than the daily claim next door, and it is the tightest budget in this
				table for a reason: the handler makes a WEB CALL. `Player:IsInGroup` hits Roblox's
				membership API, so an unbudgeted firehose here is not just server CPU — it is this
				server's group-API quota, and exhausting it makes the check fail for every honest
				player at once.

				One claim per player, ever. A capacity of 2 covers a double-click and a reconnect
				retry; the refill is slow enough that a rejected claim cannot be retried in a loop.
			]]
			RequestClaimGroupReward = { Capacity = 2, RefillPerSecond = 0.05 },
			--[[
				Both trial remotes are BUTTON PRESSES — one per session, at most, from an honest
				client. Priced like a deliberate, rare act rather than like a heartbeat.

				`RequestStartTrial` is the more interesting of the two: it is the only remote in this
				game whose handler SPAWNS AN NPC AND TELEPORTS A CHARACTER, so an unbudgeted one is a
				rig-spawn firehose. `AllowUnbudgetedRemote = false` below means a missing entry here
				refuses rather than allows, but relying on that would leave the refusal undocumented.
			]]
			RequestStartTrial = { Capacity = 2, RefillPerSecond = 0.1 },
			RequestEndTrial = { Capacity = 3, RefillPerSecond = 0.2 },
			-- Priced like `RequestThrowSalt` next door rather than like the two button presses above:
			-- it is the same action, and a player learning it will press it more than once.
			RequestTrialThrow = { Capacity = 3, RefillPerSecond = 0.2 },
		},

		-- One request costs one token. Here rather than in the service so C41 can price an expensive
		-- handler higher without touching code.
		DefaultCost = 1,

		-- FAIL CLOSED. A remote with no budget is refused, not allowed. The alternative — allowing the
		-- unknown — means a new remote added without a budget is silently unlimited, which is exactly
		-- the state C02 exists to make impossible.
		AllowUnbudgetedRemote = false,

		-- C02 LOGS. C41 ENFORCES. Kicking on a rate limit before there is real data behind the numbers
		-- kicks real players on bad connections, and a false kick is unrecoverable.
		LogOnly = true,
		-- One log line per player per remote per this many seconds. An exploiter firing 1000/s would
		-- otherwise produce 1000 warn() calls per second, which is its own denial of service.
		LogThrottleSeconds = 5,
	},

	Debug = {
		-- Set true in Studio to allow solo testing without MinPlayers.
		SoloTesting = false,
		VerboseLogging = false,
		-- Studio only, and only with SoloTesting on, at MinPlayers or fewer. Forces the LOWEST UserId
		-- to be the Aswang: solo, because a lone player is otherwise ALWAYS a survivor by
		-- construction; at 2-3 local clients, because the other windows are idle and a survivor draw
		-- means no transform and no kill ever happens. A real team test is past the ceiling and
		-- cannot be rigged by it. Pinned false by check:debug — see RoleService for all four locks.
		ForceAswangWhenSolo = false,
	},
}

return Config
