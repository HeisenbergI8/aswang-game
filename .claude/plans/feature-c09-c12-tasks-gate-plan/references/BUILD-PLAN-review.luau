--!strict
--[[
	REVIEW — docs/BUILD-PLAN.md §3, lines ~293-344
	Read 2026-08-12 for the C09-C12 plan. The chunk definitions this plan implements.

	*** ONE OF THESE FOUR ENTRIES IS STALE AND ITS VERIFY LINE NOW DESCRIBES A FAILING STATE. ***
]]

-- docs/BUILD-PLAN.md — C09, Task types: Timing and Fetch (Tier Medium, Deps C08)
-- "Timing — moving bar, 3 attempts, green zone. The client renders the bar; the SERVER owns the bar's
--  position and decides the hit. A client-decided timing minigame is a free task for any exploiter."
-- "Fetch — pick up an item elsewhere, carry it back. Server tracks the carry; dropping on death is
--  correct and creates good moments."
-- Done: both playable, both server-decided.
-- Verify: playtester completes one of each; the timing hit is refused when fired outside the window.
-- NOTE: "the timing hit is refused when fired outside the window" is a MECHANICAL, agent-drivable
-- check — fire `RequestTimingStop` from `execute_luau` at a known bad moment and read the console.
-- It is the strongest verification line of the four and should be run as written.
-- IMPORTANT: "the SERVER owns the bar's position" is why the plan sends `Phase` (a server clock
-- derivative) rather than accepting any client-supplied timestamp, and why `RequestTimingStop` takes
-- no arguments at all — there is no parameter a moment could arrive in.

-- docs/BUILD-PLAN.md — C10, Task type: Two-person (Tier Medium, Deps C09)
-- "Requires 2 survivors present for `TwoPersonTime`. The best task in the game — the Aswang can
--  'help' you and then be alone with you. Server validates both are alive, present, and distinct."
-- Done: one player alone makes no progress; two do; progress stops when one leaves.
-- Verify: playtester with two clients, screenshot of the bar moving only with both present.
-- IMPORTANT — THE VERIFY LINE REQUIRES SOMETHING NO AGENT CAN DO. Plan 1's `verification.md` names
-- this exact limit: multi-client behaviour needs "a second live client — a Studio UI action no agent
-- can drive". So C10's Done condition is a HUMAN playtest, and a green Lune grid must not be reported
-- as satisfying it. The plan says so in Phase 5's issues.
-- NOTE: "Server validates both are alive, present, and distinct" — the plan gets all three from the
-- weight bucket for free: the bucket is keyed per task and built one entry per present player from
-- `RoundService.GetPlayerState`, so distinctness is structural (one entry per UserId) and aliveness
-- is what produces a weight of 1.
-- IMPORTANT: "2 SURVIVORS" here is superseded by Amendment A2, which makes the Aswang a full
-- participant. The chunk's prose and the spec's amendment disagree; the spec wins.

-- docs/BUILD-PLAN.md — C11, The escape gate and the survivors' win (Tier Medium, Deps C10/C06, LOCKED)
-- "§4.8. At 5/5 the gate opens; a survivor reaching it wins the round. This is the finale and the best
--  clip in the game — treat the gate opening as an event worth seeing and hearing, not a boolean."
-- Done: both win conditions in §4.8 fire correctly and land on the reveal.
-- Verify: playtester drives a full survivor win end-to-end; console log of the transition chain.
-- IMPORTANT: "BOTH win conditions", so Phase 6's verification must re-prove the ATTRITION win (C06)
-- and the sunrise TIMEOUT still land, not only the new gate win. `enterEnding`'s double-reveal guard
-- is the line at risk and its own comment predicted this collision by name.
-- NOTE: "an event worth seeing and hearing" — the HEARING is not code this repo can write. Sound and
-- VFX live in the place file, which is gitignored and outside Git entirely. The plan does the visible
-- minimum in code (a captured-state look change plus the snapshot flag) and assigns the rest to
-- C18/C17 rather than writing an unverifiable step that says "make it dramatic".

-- docs/BUILD-PLAN.md — C12, The Aswang's fake task list (Tier Small, Deps C11, LOCKED)
-- "§4.4. The Aswang sees a task list and can play the animation; its progress does not count."
-- "The trap: the fake progress must look identical to the Aswang's own client, while contributing
--  nothing to the global bar."
-- Done: the Aswang can fake-perform every task type; the global bar does not move.
-- Verify: playtester as the Aswang completes a hold; the global count is unchanged. LOCKED mandatory.
-- IMPORTANT — THIS ENTIRE ENTRY IS SUPERSEDED BY SPEC AMENDMENT A2 AND IS NOW ACTIVELY MISLEADING.
-- Under A2 the Aswang's progress COUNTS IN FULL, so:
--   · "its progress does not count"        -> false
--   · "contributing nothing to the global bar" -> false
--   · Done: "the global bar does not move"  -> describes a FAILING state
--   · Verify: "the global count is unchanged" -> would PASS only if C12 were built wrong
-- CLAUDE.md's precedence is `docs/MVP-SPEC.md` -> CLAUDE.md -> the code, so the plan follows A2 and
-- contradicts this entry deliberately. The CORRECT verification is the mirror image: the Aswang's
-- hold advances the global bar exactly like a survivor's, AND the list it was shown differs from the
-- `ActiveTaskPoint` tags in the world.
-- IMPORTANT: an auditor grading Phase 7 against BUILD-PLAN.md rather than against the spec will score
-- correct work as a failure. A one-paragraph amendment to this file is recommended in the plan's §4
-- and is outside the plan's scope to make.
-- NOTE: "the fake progress must look identical to the Aswang's own client" survives A2 intact and is
-- satisfied trivially now — the progress IS identical, because it is the same progress.

-- docs/BUILD-PLAN.md — C13 (next), and C17
-- NOTE: C13 is salt spawn/pickup, "tagged `SaltSpawn`, same discovery pattern as C07". Phase 4's
-- `FetchSource` discovery is that same pattern a third time. If a fourth appears, the three should
-- probably become one helper — flagged as an observation, not planned.
return nil
