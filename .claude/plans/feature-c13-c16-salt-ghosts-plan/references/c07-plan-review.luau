--!strict
--[[
	REVIEW — .claude/plans/feature-c07-map-c08-hold-plan/feature-c07-map-c08-hold-plan.md (2241+ lines)

	Excerpted ranges:
	  · feature-c07-map-c08-hold-plan.md:42-43      the one-line statement of the disposable-rig policy
	  · feature-c07-map-c08-hold-plan.md:518-596    Step 2.1, the rig step this plan copies twice
	  · feature-c07-map-c08-hold-plan.md:2039-2048  Phase 6, the unverified-API spike pattern

	This is the reference for HOW C13/C14/C15 are provable with no greybox, which the brief asked for
	explicitly. C07 faced the identical problem — a map task it did not own, and gameplay that could not
	be observed without one — and the answer it found is copied wholesale by Steps 2.1 and 6.1.
]]

-- feature-c07-map-c08-hold-plan.md:42-43
--	**C17 — the greybox.** Phase 2.1 places a **disposable** test rig so C08 is verifiable at all. It is
--	not the greybox, it is not a deliverable, and C17 deletes it wholesale.
-- IMPORTANT THE WHOLE ANSWER IN TWO SENTENCES. A plan step that says "build the chapel" is not verifiable
--      and does not belong in a plan document; a step that places six grey pads and writes down what
--      happened is. Steps 2.1 and 6.1 are both this shape.

-- feature-c07-map-c08-hold-plan.md:518-521
--	#### Step 2.1: Place the disposable `TaskPoint` rig in Studio
--	**File:** `.claude/plans/feature-c07-map-c08-hold-plan/artifacts/task-rig.md`
--	**Verify:** `test -f .claude/plans/feature-c07-map-c08-hold-plan/artifacts/task-rig.md`
-- NOTE THE DELIVERABLE IS THE ARTIFACT, NOT THE RIG, and the Verify line follows from that: the place
--      file is gitignored, so the rig itself cannot be checked by anything. Step 2.1 and Step 6.1 of this
--      plan use the identical `test -f` shape for the identical reason.
-- NOTE `test -f` is the weakest useful check in verify-plan's ordering (proves a deliverable exists, not
--      that it says anything). This plan uses it exactly three times — 2.1, 6.1, 7.1 — all of them Studio
--      probes whose real evidence is a human reading the file.

-- feature-c07-map-c08-hold-plan.md:527-535
--	**THIS RIG IS DISPOSABLE AND IT IS NOT C17.** ... Everything below lives in one folder for exactly
--	that reason: deleting `workspace.TaskRig_TEMP` deletes the entire rig and nothing else.
--	**No Script or LocalScript is created inside Studio.** `guard-studio-sync.mjs` refuses that and is
--	right to — Rojo would overwrite it on the next sync with no error and nothing on disk to recover.
-- IMPORTANT TWO CONSTRAINTS THIS PLAN INHERITS. One folder (`SaltRig_TEMP`, and Phase 6 needs no rig of
--      its own), and parts/attributes/tags only, applied by EXECUTING code through `execute_luau` rather
--      than by storing a script.

-- feature-c07-map-c08-hold-plan.md:586-595
--	**Three things go in the artifact, and the second is the one this plan owes constraint 4:**
--	1. The output of the snippet above, and a `screen_capture` of the twelve pads.
--	2. **The empty-pool proof.** Delete `TaskRig_TEMP`, restart the server, and record the console
--	   verbatim... A run where the output window is silent is a failed step, not a clean one
--	3. **The duplicate-name proof.** Rename `TaskPoint_07` to `TaskPoint_06`, restart, record the warning
-- IMPORTANT THE EMPTY-POOL PROOF IS THE PART WORTH COPYING AND THE PART MOST LIKELY TO BE SKIPPED. It is
--      the only place in either plan where the EMPTY verdict is observable in the real engine rather than
--      in Lune, and it is what turns "TaskService warns loudly" from a belief into an observation. Step
--      2.1 requires the same three items for salt.
-- NOTE "A silent output window is a FAILED step, not a clean one" is the sentence that makes this a real
--      check rather than a box to tick.

-- feature-c07-map-c08-hold-plan.md:552-556
--	-- A 4x3 grid at a 30-stud pitch. Every pair is at least 30 apart, comfortably clear of
--	-- Config.Tasks.MinSpacingStuds (20), so the draw's spacing filter never has to fall back in-game.
--	-- The REJECTION path is already proven purely — tests/task-selection.test.luau draws from twelve
--	-- points stacked in one room and asserts the fallback fills the round anyway
-- NOTE THE DIVISION OF LABOUR BETWEEN A RIG AND A LUNE TEST. The rig exercises the HAPPY path in the real
--      engine; the pure test exercises the boundaries. A rig that tried to reproduce the rejection cases
--      would make every other observation harder to read. Step 2.1's six pads follow this: six rather
--      than four so the draw genuinely chooses, and nothing more elaborate than that.

-- feature-c07-map-c08-hold-plan.md:2039-2048
--	### Phase 6: The ProximityPrompt affordance — unconfirmed API, isolated on purpose
--	#### Step 6.1: Confirm ProximityPrompt's hold events in Studio
--	**Verify:** `test -f .claude/plans/feature-c07-map-c08-hold-plan/artifacts/proximity-prompt-probe.md`
-- IMPORTANT THE PRECEDENT FOR STEPS 6.1 AND 7.1, AND IT PAID OFF. That probe found Roblox's CoreScript
--      refuses to render a prompt with `KeyboardKeyCode = None` — which invalidated the affordance the
--      plan had specified, and cost one step instead of one chunk. `Config.luau:252-258` records the
--      outcome. This is the concrete evidence for Hard Rule 1 and the reason ghost flight, ghost
--      invisibility and TextChatService each get a probe rather than a paragraph of recalled API.
-- NOTE C07 put the unverified API in a LATE, ISOLATED phase. This plan does the same: Phase 6's flight
--      mechanism and Phase 7's chat are the last two phases, and everything ahead of them is runnable
--      without either.
