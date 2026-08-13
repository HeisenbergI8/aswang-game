--!strict
--[[
	REVIEW — docs/MVP-SPEC.md
	Read 2026-08-12 for the C09-C12 plan. §3, §4.2-4.8, §6.4, Appendix C, and Amendment A2.

	The authority on WHAT to build. Where an instinct and this document conflicted while planning, this
	document won and the conflict is in the plan's §4.
]]

-- docs/MVP-SPEC.md:133-137 (§4.4, the four task types)
-- | Hold       | Hold a ProximityPrompt        | 8s     | Forces you to stand still and vulnerable |
-- | Timing     | Stop a moving bar, 3 attempts | ~10s   | Small skill moment; failure is funny     |
-- | Fetch      | Pick up an item elsewhere     | 20-30s | Forces travel — creates isolation        |
-- | Two-person | Requires 2 survivors present  | 12s    | Forces trust; the Aswang can "help"      |
-- IMPORTANT: the DURATION column is what settles the plan's reading of "3 attempts". Three REQUIRED
-- HITS at a 1.8s sweep is ~10s; three ALLOWED MISSES is ~2s and leaves the third miss undefined. The
-- plan renames `TimingAttempts` -> `TimingHitsRequired` on that basis and raises it in §4 as a
-- judgement rather than a quotation.
-- NOTE: "20-30s" for Fetch is the whole ERRAND, most of which is travel. `Config.Tasks.FetchTime = 25`
-- is therefore read by no code — what the server can time is the deliver hold, and the travel is a
-- property of the MAP. C17 owns the distance; the plan says so rather than inventing a knob for it.

-- docs/MVP-SPEC.md:139-141 (§4.4, progression and anti-frustration)
-- "a global task bar shows overall progress (not who did what). At 5/5, the escape gate opens and
--  survivors must physically reach it — the finale, and the best clip moment in the game."
-- "tasks are assigned to the *world*, not to individuals. Anyone can do any task."
-- IMPORTANT: the world-ownership rule is why a walk-away FREEZES rather than decays, and Phase 5
-- relies on it directly — the second person leaving a two-person task freezes the bar through
-- `TaskProgress.tick`'s existing `weight <= 0` guard.
-- QUESTION resolved: does a TIMING miss resetting to zero violate this? No. The rule is about
-- ABSENCE; a miss is an ACTION by a present player, and "failure is funny" requires that it can fail.
-- The task never becomes unwinnable — the next stop is always available.

-- docs/MVP-SPEC.md:143 (§4.4, the ORIGINAL Aswang rule — SUPERSEDED)
-- "the Aswang sees a fake task list and can fake-perform the animation, but its progress does not
--  count. This is essential — otherwise 'who is standing at tasks' trivially identifies it."
-- IMPORTANT: THE SECOND CLAUSE IS REVERSED BY AMENDMENT A2 DIRECTLY BELOW IT IN THE SAME FILE. The
-- sentence survives in the document; A2 explains that following it would PRODUCE the outcome it fears.

-- docs/MVP-SPEC.md:145-184 (Amendment A2 — 2026-08-12, spec v1.1 -> v1.2)
-- "The goal of the paragraph above is kept and its mechanism is reversed. The Aswang's task progress
--  now counts, in full, exactly like a survivor's. Only what the Aswang is *shown* is deceptive."
-- "task progress belongs to the world [...] so its fill is legible to anyone standing at the point —
--  and standing at a point costs one keypress, which is not a privilege."
-- "The Two-person task (C10) follows the same rule, and it is the sharpest case. The Aswang counts as
--  a full participant [...] A pair that stood there producing nothing would be an instantaneous
--  reveal with nothing to deduce."
-- "The enforceable form of this rule is `src/server/pure/TaskWeight.luau` and its exhaustive
--  PlayerState × Role grid [...] C10's participant count must be derived from the same weights, so
--  that it inherits the property instead of restating it."
-- IMPORTANT: the last sentence is a direct instruction about IMPLEMENTATION SHAPE, not just about
-- behaviour, and the plan follows it literally — `TaskParticipants` and `FetchCarry` both take
-- WEIGHTS, never roles or states, so there is nowhere in either file for a role branch to be written.
-- NOTE: A2 also states the cost plainly — "an Aswang that ignores its fake list and helps sincerely
-- does advance the survivors' win. That is a real strategic concession and it is the intended trade."
-- That is a BALANCE fact for M12, not a bug to be patched later.

-- docs/MVP-SPEC.md:219-225 (§4.8, win/lose)
-- | Survivors win | 5/5 tasks done AND at least 1 survivor reaches the escape gate |
-- | Aswang wins   | Living survivors <= 2, or sunrise timer hits 0 with tasks incomplete |
-- IMPORTANT for Phase 6: "at least 1 SURVIVOR" is why `GateEscape` reads a role at all — the one
-- legitimate role branch in the plan. And "must physically reach it" (§4.4) is why the check is a
-- distance and not a button.
-- NOTE: the Aswang half is already amended — Amendment A1 makes it count KILLS, not presence (see
-- `pure/WinConditions.luau`). Both §4.8 rows now differ from their original wording, in this
-- document, for reasons recorded in it. Phase 6 must not break the A1 path while adding the A2-era
-- survivor path: `enterEnding`'s double-reveal guard is what holds both.

-- docs/MVP-SPEC.md:209-217 (§4.7, ghosts)
-- "Can contribute: hold a task point to add a small amount of progress (say 25% speed)."
-- NOTE: C15's, not this plan's — but three of this plan's modules price it in for free because the
-- weight is already 0.25: a ghost cannot carry a fetch item, cannot be a two-person participant, and
-- cannot win at the gate. Each falls out of a threshold rather than a branch. §4.7 asks for "they
-- still matter", not "they substitute", and that distinction is now enforced in three test files.

-- docs/MVP-SPEC.md:42 (§3, the hard line) and :751-755 (Appendix C.5)
-- ❌ Climb / escape / campaign structure · ❌ Zone-based progression · ❌ Weapons and combat
-- ❌ NPC monsters as the threat · ❌ 20-player servers
-- NOTE: nothing in C09-C12 approaches this list. The fetch item is a carried objective, not a weapon
-- or an inventory system; the escape gate is §4.8's win condition, not "escape structure" in C.5's
-- sense (which means consumable level content — the 16 months and 79.9% first-objective failure). The
-- plan states this in §1.5 rather than leaving it to `check:scope`'s token match.
return nil
