--!strict
-- REVIEW: docs/BUILD-PLAN.md:258-296 (C07, C08, and the first lines of C09)
--
-- The two chunks in scope, verbatim, with what each line binds.

-- ### C07 — TaskService: pick 5 of 12    Tier Medium · Runner robot · Deps C01
-- §4.4's one load-bearing decision — the reason a single map stays fresh (Appendix C.4 cause #2).
-- NOTE: the pure half is DONE. src/shared/pure/TaskSelection.luau + tests/task-selection.test.luau,
-- 10,000 draws. This plan builds only the three bullets below it.

-- · Task points discovered in the map by CollectionService tag (`TaskPoint`), not hardcoded — the
--   greybox at C25 places them and this reads them.
-- IMPORTANT: the chunk says C25, TaskService.luau's stub header says C17, and the user's brief says
-- C17. Immaterial to this plan — the greybox is out of scope either way and the disposable rig stands
-- in for it — but worth a line so nobody reconciles them by building one. Flagged, not resolved.

-- · Selection happens in `STARTING`; the set is server state.
-- IMPORTANT and it needed unpacking, because "server state" is doing two different jobs. §1.3 of the
-- plan is the written answer: the SERVER decides and no client can predict or extend it (that is the
-- Random.new() rule), but the selection is not a SECRET — five prompts appear on five parts and hiding
-- that would hide the objective from the people who have to complete it. The `ActiveTaskPoint` tag
-- replicating is therefore correct rather than tolerated.

-- **Verify** `lune run tests/task-selection.test.luau` — no duplicates over 10,000 seeded draws
-- NOTE: already green. This plan's C07 steps get their OWN checks (tests/task-pool.test.luau,
-- npm run analyze, npm run check:config), because a step verified by a test that passed before the
-- step existed proves nothing about the step.

-- ### C08 — Task type: Hold    Tier Medium · Runner robot · Deps C07, C02 · LOCK
-- The first of four, and the one that establishes the shape the other three copy.
-- IMPORTANT: this sentence is the actual deliverable, and it is what made the max-vs-sum decision a
-- design question rather than an implementation detail. C09 and C10 differ only in what produces a
-- contribution weight; the accumulation, the boundary, the clamp and the payload are settled here once.

-- · ProximityPrompt, `HoldTime` seconds, server-timed. **The client cannot report completion** — it
--   reports *presence*, and the server accumulates.
-- IMPORTANT: ProximityPrompt appears ZERO times in src/ today. Hard Rule 1 forbids guessing the API,
-- so Phase 6 isolates it behind a Studio probe and Phases 1-5 build the mechanic on ContextActionService,
-- which InputController already uses. A run that halts at Phase 5 has still shipped C08.
-- NOTE "server-timed" is what rules out HoldDuration = HoldTime on the prompt: that fills on the
-- CLIENT's clock and finishes at a different moment from the server's bar.

-- · `RequestTaskProgress` rate-limited via C02.
-- NOTE: the remote and its budget both already exist. Step 4.1 is the handler, guard inline.

-- · Progress is per-task-point on the *world*, not per-player (§4.4 anti-frustration).
-- IMPORTANT: this is why TaskProgress.tick FREEZES rather than decaying when nobody is present. A
-- survivor who dies at 90% leaves 90% for whoever arrives; decay would recreate exactly the "a dead
-- player's task is unwinnable" class §4.4 deletes.

-- · `TaskProgressChanged` broadcast — the global bar only. Never who did what.
-- QUESTION → resolved, and it is the one place this plan reads the chunk more strictly than it is
-- written. "Broadcast" is not taken literally: the payload is fired PER PLAYER, because the global bar
-- is identical for everyone anyway and the per-task fill must reach only the person standing on it.
-- Broadcasting the fill would hand a bystander a role oracle the moment C12 zeroes the Aswang's weight.
-- "Never who did what" is honoured exactly — no UserId, no name, no count of who is present.

-- **Done** a hold completes in `HoldTime`; walking away mid-hold stops accumulation; a client spamming
-- `RequestTaskProgress` gains nothing.
-- IMPORTANT: the third clause is true by CONSTRUCTION here, not by rate limit. `elapsed` is measured on
-- the server tick and the request count appears nowhere in the accumulation, so 1000/s and 4/s produce
-- identical progress. The rate limit is the second, independent mechanism.
-- NOTE this is the playtester's brief verbatim, and the artifact the plan is judged on. LOCK mandatory.
