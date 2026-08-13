--!strict
-- REVIEW: docs/MVP-SPEC.md:126-143 (§4.4), 168-176 (§4.7), 178-183 (§4.8), §5, §6.4
--
-- §4.4 is the section this whole plan implements. Four sentences in it are binding.

-- **The rule: 12 possible task locations exist on the map. Each round randomly picks 5.** Players
-- cannot memorise a route.                                                          -- :128
-- NOTE: already satisfied by TaskSelection. This plan supplies the pool it draws from. IMPORTANT that
-- the anti-memorisation property depends on the RNG being unpredictable to a CLIENT, not merely random
-- — hence Random.new() with no argument, and hence the pool and the stream never leaving the server.

-- | **Hold** | Hold a ProximityPrompt (light candles, pump water) | 8s | Forces you to stand still and
-- vulnerable |                                                                      -- :134
-- IMPORTANT: "forces you to stand still and vulnerable" is the design reason the rate is a MAX rather
-- than a sum. With a sum, four survivors clear a task in two seconds and the vulnerability window this
-- row is named for disappears. The max keeps it at a fixed, predictable, ambushable eight seconds
-- regardless of how many people are on it — which is also what makes C12's zeroed weight invisible.

-- **Progression rule:** a global task bar shows overall progress (not who did what). At 5/5, the
-- **escape gate opens**                                                             -- :139
-- IMPORTANT, both halves. "Not who did what" is the payload contract — no UserId, no name, no
-- contributor count. "At 5/5 the escape gate opens" is C11 and is explicitly OUT of this plan:
-- RoundState.GateOpen is not written here. At 5/5 the counter reads 5/5 and nothing else happens, which
-- is honest and leaves the round runnable on the sunrise timer.

-- **Anti-frustration:** tasks are assigned to the *world*, not to individuals. Anyone can do any task.
-- This prevents a dead player's tasks from becoming unwinnable and removes a whole class of bugs.  -- :141
-- IMPORTANT: this is the sentence behind TaskProgress freezing instead of decaying, and behind presence
-- being keyed by task point rather than by player. It is also why `ActiveTask.Progress` lives on the
-- task and not in a per-player table — there is no per-player progress anywhere in this design.

-- **Aswang and tasks:** the Aswang sees a fake task list and can fake-perform the animation, but its
-- progress does not count. This is essential — otherwise "who is standing at tasks" trivially
-- identifies it.                                                                    -- :143
-- IMPORTANT, and it is C12, which is OUT. Two things follow for this plan and both are already done:
--   1. C08 must not make it expensive. TaskProgressChanged being per-player means C12 can lie to
--      exactly one client without touching anyone else's payload.
--   2. C08 must not make it IMPOSSIBLE. A summed rate would make the Aswang's zeroed contribution
--      visible to bystanders no matter what C12 does, because the arithmetic is public.
-- QUESTION → accepted, not solved (risk R3): "can fake-perform the animation" means a survivor who
-- watches someone stand on a task for 20 seconds with no completion still learns something. That is
-- spec-level and pre-existing; C12 is where the trade is made.

-- §4.7 · Can **contribute**: hold a task point to add a small amount of progress (say 25% speed)  -- :174
-- NOTE: C15, out of scope. It reaches this plan only as a shape test — Config.Ghost.TaskContributionMult
-- exists today, and tests/task-progress.test.luau asserts against it that a quarter-weight helper
-- neither speeds up nor slows down a full one. C15 changes exactly two lines: evaluatePresence's
-- aliveness gate and weightFor. Recorded as Follow Ups Q4 so it is not rediscovered.

-- §4.8 | **Survivors win** | 5/5 tasks done AND at least 1 survivor reaches the escape gate |     -- :182
-- NOTE: C11. This plan supplies the "5/5 tasks done" half and stops there.

-- §5 mobile budget
-- NOTE counted in the plan: one 4 Hz server loop doing at most #presence x #activeTasks distance
-- comparisons (40 subtractions a tick at 8 players), five ProximityPrompts, zero lights, zero
-- particles, zero client per-frame work. TaskProgressChanged sends ~4/s total against RoundSnapshot's
-- existing 16/s for eight players, because unchanged values are skipped.
-- IMPORTANT: mobile cannot complete a task at all until C27 — createTouchButton is false on the new
-- bind, matching the existing two. 60% of the audience. Named as risk R8 rather than left to surface.

-- §6.4 edge cases — which apply
-- NOTE: a player leaving mid-hold (presence entry dropped two ways), dying mid-hold (weightFor reads
-- GetPlayerState, so it stops on the next tick with no bookkeeping), joining mid-round (SPECTATOR, so
-- evaluatePresence returns NOT_ALIVE). A fourth, not in §6.4 and specific to this chunk: a TaskPoint
-- part DELETED from the map mid-round while C17 is being built in a live Studio session — taskPointAt
-- guards on `part.Parent ~= nil`, because a destroyed part answers .Position forever.
