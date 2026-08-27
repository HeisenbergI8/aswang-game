--!strict
--[[
	REVIEW — docs/MVP-SPEC.md §6.5 (lines 722-761), §4.7 (490-535), line 52, and the §4.3/§4.6
	fragments that supplied the per-number comments (lines 226-302, 375-417, 434-460, 542).
	Read for: V02 Phase 3, whose entire content is copied from §6.5.

	This is a .luau file by naming convention only; the source is markdown.
]]

--[[
	§6.5 FIELD CENSUS — the answer to "what is genuinely new". Thirty-six keys in the block.

	GENUINELY NEW (17):
	  Monster.MaxHealth, WeakenedThreshold, FeedDuration, FeedHeal, SmokeDuration, SmokeRadius
	  Search.ContainerCount, SearchTime, NoiseRadius                         (new table)
	  Tracker.EarlyInterval, LateInterval, EarlyRadius, LateRadius           (new table)
	  Bodies.AfkSeconds, HuskRelocateAfter                                   (new table)
	  Items.SaltDamage, GarlicSpawnCount, GarlicDuration, BuntotPagiSpawnCount

	RENAMED FROM AN EXISTING v1.3 KEY (4) — Step 3.4 aliases these rather than renaming:
	  Items.SaltSpawnCount     <- Salt.SpawnCount
	  Items.SaltStunDuration   <- Salt.StunDuration
	  Items.SaltRevealDuration <- Salt.RevealDuration
	  Items.SaltThrowRange     <- Salt.ThrowRange

	MOVED TABLE, SAME NAME (1) — Step 3.3 leaves it where it is:
	  Bodies.CorpseDuration    <- Monster.CorpseDuration

	VALUE CHANGE ONLY (2) — Step 3.1:
	  Round.Duration   420 -> 300   (also §4.1 line 170: "a flat 300s")
	  Round.MaxPlayers   8 -> 5     (also §C line 873: "Set MaxPlayers to 5, not 20")

	ALREADY CORRECT, NO CHANGE (12):
	  Round.Intermission 25, EndScreen 12, MinPlayers 3
	  Roles.AswangCount 1, RepeatCooldownRounds 2
	  Monster.TransformTime 1.2, RevertTime 1.0, KillRange 8, MaxTransformTime 8,
	         TransformedSpeedMult 1.25
	  Economy.XPPerRound 50, XPWinBonus 40, CoinsPerRound 25

	IMPORTANT §6.5's block is NOT exhaustive of what the game needs. Config.luau holds ~200 tunables
	across QuickChat, Cosmetics, Daily, Profile, Trial, Community, Badges, Performance, Sky, Audio,
	AntiCheat and Debug, none of which §6.5 mentions and none of which V02 touches. "Present" in V02's
	Done means §6.5's block is all there, not that Config.luau equals §6.5.
]]

--[[
	§6.5's SIX INVARIANTS, EVALUATED AT THE SHIPPED VALUES. V11 writes these into
	tests/config.test.luau; V02 must not, and V02 must not break them.

	1. SaltDamage x (SaltSpawnCount - 1) >= MaxHealth - WeakenedThreshold
	   25 x 3 = 75  >=  100 - 25 = 75          <- EQUALITY. ZERO MARGIN.
	2. FeedDuration > time to cross ~15 studs + a strike
	   5 > 15/16 = 0.94s + swing                ✓ ~4s of slack
	3. SaltThrowRange > KillRange     25 > 8    ✓
	4. GarlicDuration < Round.Duration / 4      15 < 75   ✓
	5. LateInterval < EarlyInterval (30 < 90) and LateRadius < EarlyRadius (15 < 40)   ✓
	6. SaltRevealDuration > SaltStunDuration    10 > 4    ✓

	IMPORTANT INVARIANT 1 IS THE ONE TO FEAR. Equality means survivors weaken the Aswang only if every
	pouch but one connects. §6.5's own framing — "the second win condition survives one missed throw" —
	is satisfied exactly and not one point more. Nothing guards it until V11, so the comment on
	Items.SaltSpawnCount is the entire defence in the interim.

	NOTE invariant 2's right-hand side is not a Config number. 15 studs is a spec phrase and ~16
	studs/sec comes from Config.Trial.PlayerBaselineWalkSpeed. V11 will have to decide whether to pin
	it against that constant or introduce one; that is a real design question, not a formality.
]]

--[[
	§4.7 + spec line 52 — AMENDMENT A3, AND WHAT V02 OWES IT.

	Line 52, verbatim: "Amendment A3 survives intact (§4.7): death is not public, there is no global
	death signal, and ClientRoundSnapshot still carries no alive-count. Removing ghosts must not remove
	the body — the reasoning is in §4.7 and it was rediscovered the hard way twice."

	IMPORTANT the attack it closes, restated because Step 1.2 adds a field to the same type: record
	replicated character positions, timestamp each kill from a global death signal, then ask who was
	within KillRange of the victim's last position at that instant. In the open that is often ONE
	candidate. §4.7 notes v2.0 makes this WORSE — MaxPlayers drops to 5, so each survivor is a fifth of
	the field rather than an eighth.

	`YourCarriedItem` is not that signal: it is not a count, it does not change when someone else dies,
	and it is FireClient to the player it describes.

	NOTE §4.7 also governs husks, and the rule is counter-intuitive enough to record: a husk must be
	PUBLICLY OBVIOUS, not hidden. A husk that differed from a live body in any replicated-but-subtle
	way would let a client enumerate which bodies are husks — and since the Aswang can never be one,
	every husk is provably innocent. Public information cannot be exploited; half-hidden information
	can. This is why Bodies.AfkSeconds is generous (120s) rather than aggressive.
]]

--[[
	§3's IN LIST (spec lines 111-115) — every v2 word V02 introduces is on it:
	  transform-to-kill and FEEDING; CAMOUFLAGE (post-reveal only); SMOKE escape; the THREE ITEMS
	  (salt, bawang, buntot pagi); the SHARPENING TRACKER.

	§3's OUT list, and §8.3 — the two constraints V02's vocabulary must not quietly widen:
	  · a second monster (manananggal, tiktik, kapre, tiyanak, tikbalang) — CamouflageForm is FORMS the
	    one monster wears, not additional monsters. Keep it that way.
	  · a second buntot pagi. §8.3 line 843: "selling a second one sells the win condition", named as
	    the sharpest monetisation temptation in the game. BuntotPagiSpawnCount = 1 is a design
	    constant, not a knob.
]]
