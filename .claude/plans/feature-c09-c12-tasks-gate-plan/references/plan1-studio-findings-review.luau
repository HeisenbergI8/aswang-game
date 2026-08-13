--!strict
--[[
	REVIEW — .claude/plans/feature-c07-map-c08-hold-plan/ (verification.md, implementation-log.md,
	and all eight files in artifacts/)
	Read 2026-08-12 for the C09-C12 plan.

	Plan 1 is complete, verified in Studio and green. This review carries only what CHANGES HOW
	C09-C12 IS BUILT OR VERIFIED — the traps, not the results. Anyone driving a playtester step in
	this plan should read this file first.
]]

-- artifacts/keyboard-swallow-bug-and-fix.md — THE MOST EXPENSIVE FINDING IN THE REPO SO FAR
-- "standing 3.5 studs from an active `TaskPrompt`, `E` held continuously (confirmed down at the
--  engine level via `UserInputService:IsKeyDown`) for a full 90-second ACTIVE phase produced ZERO
--  console output of any kind — not even a refusal."
-- Root cause: `ProximityPrompt`'s default `KeyboardKeyCode = E` consumed the keypress before the
-- ContextActionService bind on the same key ever saw it.
-- IMPORTANT FOR PHASE 3: this is why `R` is the plan's #1 open question. THE FAILURE MODE IS SILENCE.
-- A playtest that presses `R`, sees nothing, and concludes "the timing task is not wired yet" is
-- indistinguishable from one where the bind is being swallowed. The diagnostic that worked was the
-- differential: firing the same mechanism from OFF a task point produced a correct stream of
-- `NO_TASK_IN_RANGE` refusals, proving the input pipeline worked everywhere except on a pad.
-- NOTE: run that differential for `R` FIRST, before concluding anything about the timing task.

-- artifacts/proximity-prompt-probe.md + TaskService:256-273
-- Measured defaults: `MaxActivationDistance` = 10 against `PresenceRangeStuds` = 9;
-- `RequiresLineOfSight` = true. Both DISAGREE with what the server accepts, so both are set
-- explicitly. Server-created prompts DO replicate to clients (all five, read from the Client
-- datamodel).
-- NOTE: any prompt C09/C10 adds inherits all of this. The plan adds none — the timing stop reuses the
-- existing prompt's presence and the fetch pickup is pure proximity — which sidesteps the whole area.
-- IMPORTANT: `Enum.KeyCode.None`, never `Unknown`. Same runtime value; `Unknown` is absent from the
-- analyzer's Enum.KeyCode type and fails `npm run analyze`.
-- NOTE: side effect still open (C18) — the CoreScript logs "unsupported keycode for rendering UI" on
-- every prompt and the `[E]` hint may not render. Expect that line in every Studio log for this plan
-- and do not chase it.

-- artifacts/task-rig.md §5 + implementation-log Phase 6 — THE STUDIO TRAP, TWICE
-- "`RoundService.GetPhase()` called from `execute_luau` returned `"IDLE"` while the console showed
--  `ACTIVE`. `require` from the executor yields a fresh copy of the module with its own `state`
--  local, not the live service."
-- "It reported `Config.Tasks` holding only the six original scaffold keys — missing `MinSpacingStuds`,
--  committed since `c15aafc` — while `.Source` on the same ModuleScript contained the new ones."
-- IMPORTANT: TWO incidents, one root cause. THE RULE: measure through datamodel state
-- (CollectionService tags, instance properties) or `get_console_output`. NEVER through a module the
-- executor required.
-- CONSEQUENCE FOR THIS PLAN, concretely — every verification step must be expressible as a tag count,
-- an instance property, or a console line:
--   Phase 3  the bar     -> console (`[Task] bar ... hits`), NOT `TaskService.timingState`
--   Phase 4  the carry   -> the `FetchItem_*` part's `Position` and `Parent`, NOT `fetchState`
--   Phase 6  the gate    -> the gate part's `Transparency`/`CanCollide` and the console chain,
--                           NOT `RoundService.IsGateOpen()`
--   Phase 7  the list    -> the client console print vs the `ActiveTaskPoint` tag list
-- NOTE: this is a strong `/lessons-review` candidate per plan 1's own log and may already be a lesson.

-- artifacts/task-rig.md §1 — the rig this plan extends
-- `workspace.TaskRig_TEMP`, twelve anchored Parts, 4x3 grid, `X = {-45,-15,15,45}` by
-- `Z = {-30,0,30}`, 30-stud pitch. Measured closest pair 30 studs against `MinSpacingStuds = 20`, so
-- the spacing filter never has to fall back in-game. `TaskType = "HOLD"` on pad 01 ONLY.
-- IMPORTANT: "a rig where every pad stated it would never exercise the default the whole map is going
-- to rely on." Steps 4.5 and 6.5 must preserve that — set `FETCH` on two pads and `TIMING` on one,
-- and LEAVE THE REST ABSENT.
-- NOTE: deleting `workspace.TaskRig_TEMP` deletes the entire rig and nothing else. That is the whole
-- reason it is one folder, and C17 replaces it wholesale.
-- IMPORTANT: the place was NOT published — "the rig is disposable and publishing it would put it in
-- the cloud version history that C17's real greybox needs." Keep that true for the new anchors.

-- artifacts/task-rig.md §4 — a misreading worth not repeating
-- A three-point phase sample read as the teardown firing on the wrong phase; it was a LABELLING
-- error, because `execute_luau` starts several seconds into a session so each sample landed one phase
-- later than its name. Re-run at 1s resolution over a full round boundary, needing no labels.
-- NOTE: same technique applies to Phase 4's "item exists during ACTIVE, gone during INTERMISSION".
-- Sample at 1s and read the run lengths; do not label samples by assumed phase.

-- verification.md — screen_capture and the multi-client hole
-- "`screen_capture` excludes CoreGui, so ProximityPrompt UI never appears in a capture."
-- "Multi-client behaviour. Everything here is one Solo-Testing survivor. [...] needs a second live
--  client — a Studio UI action no agent can drive."
-- IMPORTANT: the second one is a HARD LIMIT on Phase 5. C10's Done condition ("one player alone makes
-- no progress; two do") and its Verify ("playtester with two clients") are both multi-client. The
-- Lune grid proves the RULE; only a human proves the wiring. Phase 5's issues say so.

-- artifacts/delta-2-nearest-incomplete-overlap.md, delta-3-spacing-warning-both-cases.md (NEW since
-- this plan was drafted)
-- The resolver delta was verified live: the soft-lock was reproduced by FORCING an overlap — a
-- completed point at ~0 studs did not mask an incomplete one at ~4 — and the spacing warning was
-- proven in BOTH directions (fires when packed, silent when spread).
-- NOTE: this raises confidence in the one behaviour every phase of this plan leans on. It also
-- demonstrates the technique the 🔒 steps should copy: force the adversarial state deliberately
-- rather than waiting for it, and prove the negative case too.

-- Config handling during a playtest, from verification.md's handoff section
-- IMPORTANT: the coordinator sets and reverts the five debug values; the playtester cannot edit
-- Config and will correctly refuse. `npm run verify` HALTS at `check:debug` while they are set —
-- that is the harness working, not a defect. Expect `config.test.luau` to fail on exactly the two
-- debug assertions during a playtest and on nothing else.
return nil
