--!strict
--[[
	REVIEW — docs/BUILD-PLAN.md (980 lines)

	Excerpted ranges:
	  · docs/BUILD-PLAN.md:344-352   C13
	  · docs/BUILD-PLAN.md:355-366   C14
	  · docs/BUILD-PLAN.md:369-412   C15, including the two questions C01 left for it
	  · docs/BUILD-PLAN.md:416-423   C16
	  · docs/BUILD-PLAN.md:433-450   C17 — EXCLUDED, excerpted only for the tag contract
	  · docs/BUILD-PLAN.md:454-466   C18 — excerpted for the HUD element Amendment A3 removes

	The requirements. Read alongside §4.6 and §4.7, which are the source of truth where the two disagree.
]]

-- docs/BUILD-PLAN.md:347-351
--	4 pouches at random fixed points (tagged `SaltSpawn`, same discovery pattern as C07). One carried per
--	player. No recharge — §4.6, scarcity is the point.
--	**Verify** playtester picks up two in a row and is refused the second.
-- NOTE "same discovery pattern as C07" is a direct instruction and Step 2.2 follows it literally,
--      including reusing `server/pure/TaskPool.evaluate` rather than writing a salt-shaped copy.
-- NOTE The Verify line is a human observation over a rule that is pure arithmetic. Step 2.4 makes it a
--      terminal test; the playtest still happens and stops being the ONLY evidence.

-- docs/BUILD-PLAN.md:360-362
--	- `RequestThrowSalt(direction)` → server simulates. **The client never decides a hit.**
--	- Hit → 4s stun, forced revert, `RevealDuration` glow visible to everyone.
--	- `ThrowRange` 25 > `KillRange` 8 — `tests/config.test.luau` already pins this relationship.
-- IMPORTANT "forced revert" IS THE SENTENCE THAT SETTLES C14's BIGGEST OPEN QUESTION. A revert can only
--      be forced on a TRANSFORMED player, so the spec is already describing the transformed case — which
--      is what licenses `pure/SaltThrow` treating an untransformed Aswang as a MISS. The alternative
--      (salt works on a human-shaped Aswang) makes four pouches into four free identity probes and ends
--      the hidden-role game by minute two.
-- NOTE Neither BUILD-PLAN nor §4.6 states this explicitly. It is an inference, it is load-bearing, and
--      Step 3.1's header argues it out loud rather than burying it.

-- docs/BUILD-PLAN.md:381-389
--	**1. `AlivePlayerCount` becomes a death oracle the moment a kill sets `GHOST`.** ... An executor
--	recording replicated character positions timestamps each kill from the decrement, then asks who was
--	within `KillRange` (8 studs) of the victim's last position at that instant...
--	**Decide whether death is public.** If it is (a corpse everyone can see, a broadcast), this field is
--	redundant and should be dropped rather than kept as a second, lower-latency channel.
-- IMPORTANT DECISION 1, AND THE BRIEF'S OWN WORDING POINTS AT THE FINDING IT DOES NOT MAKE. It says "a
--      corpse everyone can see, a broadcast" — and there IS a broadcast:
--      `MonsterService.luau:610` fires `PlayerKilled` to every client with the victim AND the position.
--      That is a stronger oracle than the field this paragraph is about, and dropping the field alone
--      would leave the attack fully intact with a better input. Step 1.5 narrows it.
-- NOTE "Don't test it in a crowded room, see three candidates and conclude the warning was hype" is the
--      right instruction for the playtester and is carried into the plan's verification expectations.

-- docs/BUILD-PLAN.md:391-408
--	**2. Rejoin currently launders a survivor into an unkillable body.** ... alt-F4 on hearing the
--	transform is a hard counter to the entire monster. Resolve a returning dealt-in player to `GHOST`
--	here...
--	- **Populate the dealt-in set in `enterStarting`**... It must be its **own table** — it cannot live
--	  inside `PlayerStates`, because `setAllPlayerStates` opens with `table.clear`.
--	- **`GHOST`-on-rejoin makes quitting less profitable, not unprofitable.** ... Ship it anyway... but
--	  record a disconnect during `ACTIVE` as a **death for scoring and XP**, or it resurfaces at C32
--	- **C11 must not double-handle the count.**
-- IMPORTANT ALL THREE CONDITIONS ARE CARRIED: Steps 5.3, 5.5 and (as a no-op, verified) 5.4's note that
--      no count is adjusted anywhere in Phase 5.
-- NOTE The third condition is discharged by doing NOTHING, which is the easiest kind to get wrong: a
--      disconnect already deletes the PlayerStates entry, so `livingSurvivorCount()` already treats a
--      quitter as gone. Adding a correction "to keep the books straight" is precisely what Amendment A1's
--      three failed patches did.
-- NOTE "(The Aswang has no rejoin case — `onPlayerRemoving` aborts the round on a match.)" — confirmed
--      against the code at RoundService.luau:924-928. RejoinResolve answers GHOST for them, harmlessly
--      and unreachably.

-- docs/BUILD-PLAN.md:419-423
--	Ghosts hold task points at `TaskContributionMult` (25%). One spook per round — flicker a light,
--	rustle a bush. **Carries no information**, by design; it is flavour that keeps dead players in the
--	room.
--	**Verify** playtester as a ghost adds progress; second spook attempt refused.
-- IMPORTANT "Carries no information" IS A CONSTRAINT ON WHICH OBJECT FLICKERS, not on the payload. The
--      nearest-light implementation is a beacon saying "a dead player is standing here", repeatable, and
--      living players learn to read it in one session. Step 8.4 picks uniformly at random within
--      `Config.Ghost.SpookRangeStuds` (30) for exactly this reason.

-- docs/BUILD-PLAN.md:445-448
--	- 12 `TaskPoint`-tagged anchors, spread. 4 `SaltSpawn` anchors. 1 `EscapeGate`.
--	**Done** the tags exist and C07/C13 discover them
-- NOTE C17 IS EXCLUDED FROM THIS PLAN. This line is excerpted only to fix the tag contract C13 must be
--      written against, which Step 2.1 states in one sentence: anchored BaseParts, tagged `SaltSpawn`,
--      uniquely named, at least `Config.Salt.SpawnCount` of them, spread.
-- NOTE C17 asks for 4 anchors; `Config.Salt.PouchPoolSize` is 6 so the round genuinely chooses. That is a
--      disagreement the `OVERSIZED`/`SHORT` verdicts will report loudly rather than a conflict to resolve
--      now — and at 4 anchors the pool is exactly `SpawnCount`, which is legal and simply not random.

-- docs/BUILD-PLAN.md:460
--	- Sunrise timer, global task bar, alive count — all from `RoundSnapshot`.
-- IMPORTANT THE ELEMENT AMENDMENT A3 STRANDS. Recorded as Follow Up 2 with the substitute names that must
--      also be refused, because "alive count" will read as a trivially available field to whoever builds
--      C18 and there will be nothing in the type to stop them adding it back.
