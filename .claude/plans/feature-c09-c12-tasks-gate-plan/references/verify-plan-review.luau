--!strict
--[[
	REVIEW — .claude/scripts/verify-plan.mjs
	Read 2026-08-12 for the C09-C12 plan. Why each **Verify:** line is the command it is.

	The plan lints clean: 27 steps, 0 unrunnable, 0 unverifiable, 0 shared, 0 unsatisfiable,
	0 phases reporting needs-human.
]]

-- .claude/scripts/verify-plan.mjs:42-57 (ALLOWED)
-- npm run (verify|verify:fast|analyze|lint|fmt:check|build|test:unit|check:*)
-- node .claude/scripts/check-[a-z-]+.mjs
-- lune run tests/<name>.test.luau
-- grep -<flags> <pattern> <path>
-- test -[efd] <path>
-- IMPORTANT: anchored at BOTH ends and executed WITHOUT A SHELL (`execFileSync`), so `;`, `&&`, `|`
-- and `$()` are inert literal arguments by construction. Anything else is reported as blocked rather
-- than run. Every command in this plan is on the list — verified by the clean lint.

-- .claude/scripts/verify-plan.mjs:158-165 (the classifier)
local shape = function(command)
	if command == nil then return "none" end
	if command:match("^%s*test%s+%-[fde]%s") then return "exists" end
	if command:match("^%s*grep%s") then return "self" end
	return "real"
end
-- IMPORTANT: this plan uses **ZERO grep checks**. 25 of its 27 steps classify as `real`; the other two
-- are `test -f` on the two Studio artifact steps (4.5 and 6.5), whose deliverable genuinely IS a file.
-- 25/27 = 93% discriminating against `STRICT_MIN_REAL = 0.5`, so `--strict` cannot halt the run on
-- check quality.
-- NOTE: plan 1 shipped 11 checks that passed whether or not the step's work existed. The specific fix
-- applied here was to pair every new pure module with a Lune test in the NEXT step — `lune run
-- tests/<x>.test.luau` fails when the file is missing, which `npm run analyze` does not.

-- .claude/scripts/verify-plan.mjs:140-147 (why weak checks are reported, not blocked)
-- "Reported, never enforced: some steps genuinely cannot be proven by a command [...] and blocking
--  those pushes an architect to write a fake check instead of an honest `unverifiable`."
-- NOTE: this plan has no `unverifiable` steps, which is worth reading with suspicion rather than
-- pride. Two steps carry only `test -f`, and a `test -f` proves a document was written, not that what
-- it says is true. Steps 4.5 and 6.5 are the Studio steps, and their real evidence is the artifact's
-- CONTENT — which no exit code can grade.

-- .claude/scripts/verify-plan.mjs:172-196 (duplicate checks, WITHIN A PHASE ONLY)
-- "Two steps carrying the IDENTICAL check: the second is unproven no matter what it returns [...]
--  This is a false-PASS generator that survives every other guard here."
-- "WITHIN A PHASE ONLY, and that boundary is the whole design. Comparing across a whole document
--  condemns `npm run verify:fast` used as each phase's closing gate — a correct and deliberate idiom."
-- NOTE: this plan reuses `npm run analyze` in phases 2, 3, 4, 5, 6 and 7 and `verify:fast` in 1, 3, 4,
-- 5 and 6 — legal, because each runs against a different tree. Within every phase the commands are
-- distinct. Lint confirms: `0 shared`.

-- .claude/scripts/verify-plan.mjs:60-72 (UNSATISFIABLE)
-- "A command that is runnable but can never exit 0 on a healthy tree makes its step fail forever:
--  `next-phase.mjs` never sees `passed === list.length`, the phase never reaches `done`, and
--  `task-driver.mjs` eventually halts the run as `phase stuck` — a halt naming work that was finished
--  and correct."
-- IMPORTANT — READ WITH `references/check-secrecy-review.luau`. Step 7.3's check is
-- `npm run check:secrecy`, and check:secrecy gained a RULE 5 after this plan was frozen: TaskService
-- may not read the role without a `-- secrecy-ok:` waiver. Step 7.3's diff writes exactly such a read.
-- So Step 7.3 WILL report red until the waiver is added, and the failure will look like "phase stuck"
-- rather than like a missing comment. The waiver text is in the check-secrecy review.
-- NOTE: this is not an `UNSATISFIABLE` entry — the command CAN pass, once the step is implemented
-- correctly. It is a step whose correct implementation is not fully described by the frozen plan.

-- .claude/scripts/verify-plan.mjs:88-100 (fence stripping)
-- "Returns the stripped text AND whether a fence was left open. An unterminated fence is the failure
--  mode with no symptom: every line after it is blanked, so the steps below it stop existing and the
--  plan reports a smaller, entirely green step count."
-- NOTE: the plan document is heavy with ```diff blocks — this is what makes the step COUNT the thing
-- to sanity-check rather than the pass count. 27 steps is the expected number (4+2+4+5+3+5+4). A lint
-- reporting fewer means a fence was left open somewhere above the missing ones.

-- .claude/scripts/verify-plan.mjs:145-156 (the three thresholds)
--   STRICT_MIN_REAL  0.5   may a LOOP be driven by this plan at all?     — hard gate, exit 2
--   WEAK_WARN_RATIO  0.66  is a green run worth a caveat?                 — advisory
--   next-phase.mjs   LOW_CONFIDENCE   is THIS PHASE proven enough?        — per phase
--   goal-check.mjs   WEAK_EVIDENCE    is "steps passed" weak evidence?    — advisory
-- NOTE: `goal-check.mjs` additionally requires `verification.md` to cite a file that EXISTS in
-- `artifacts/`. The plan creates `artifacts/` empty for exactly that reason, and Steps 4.5 and 6.5 are
-- the two that will put files in it.
return nil
