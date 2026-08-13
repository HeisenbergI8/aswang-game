--!strict
-- REVIEW: .claude/scripts/verify-plan.mjs:40-58 (ALLOWED), 60-75 (UNSATISFIABLE), 150-196 (shape and
-- duplicates), 198-250 (--lint)
--
-- Read because the user's brief made the plan's structure load-bearing, and because "give every step
-- its own distinguishing check" has an exact definition in code that is narrower than it sounds.

export const shape = command => {
	if (/^\s*test\s+-[fde]\s/.test(command)) return 'exists'
	if (/^\s*grep\s/.test(command)) return 'self'
	return 'real'
}
const STRICT_MIN_REAL = 0.5
-- IMPORTANT: at least half the checks must be 'real'. This plan is 17 real, 2 'exists', 0 'self',
-- 1 absent — 89% of the commanded steps. NOTE the deliberate zero on 'self': there is not a single
-- grep-gated step, because a grep for a token the step itself types proves authorship, not behaviour.

-- ── DUPLICATE VERIFY LINES ────────────────────────────────────────────────────
-- WITHIN A PHASE ONLY, and that boundary is the whole design. Comparing across a whole document
-- condemns `npm run verify:fast` used as each phase's closing gate — a correct and deliberate idiom.
const phaseOf = step => step.id.split(' ')[1]?.split('.')[0]
const key = `${phaseOf(step)}::${step.command}`
-- IMPORTANT and it changed how the plan's checks were allocated. The constraint is PER PHASE, not per
-- document, so `npm run analyze` legitimately appears in Phases 2, 3 and 5 against three different
-- trees. What is forbidden is two steps in ONE phase sharing a command — "nothing can happen between
-- them that changes the answer".
-- NOTE the consequence for the author: a phase with four steps needs four distinct commands, which is
-- what pushed Phases 3 and 4 towards their most specific gates (check:config on the tick loop,
-- check:ratelimit on the handler, check:remotes on the fire, check:secrecy on the payload) rather than
-- four coarse ones. That is the rule improving the plan rather than constraining it.

const shared = new Set(duplicateChecks(steps).flatMap(([, ids]) => ids.slice(1)))
	? `SKIP  ${step.id} — check is shared with an earlier step, so it proves nothing here  [shared]`
-- NOTE: the SECOND occurrence is skipped, not the first. So a shared check does not merely warn — the
-- step reports as unproven and the phase reports needs-human. Confirmed by running --lint on this
-- plan: `0 shared`.

for (const step of noCheck) {
	console.log(`NOTE  ${step.id} — no check; honestly unverifiable`)
}
return notAllowed.length || unsatisfiable.length || duplicates.length || ... ? 1 : 0
-- IMPORTANT: an ABSENT check is honest and does NOT fail the lint. That is what makes Step 6.3 legal:
-- it changes how a ProximityPrompt looks to a person standing in front of it, no command in this repo
-- can read that, and inventing a grep there would tell the loop that a phase built on an unconfirmed
-- API had been proven. Measured on this plan: `1 unverifiable · 1 phase(s) would report needs-human`,
-- which is Phase 6 and is the intended outcome.

export const UNSATISFIABLE = [ /* empty today */ ]
-- NOTE: every ALLOWED command was measured against a clean tree on 2026-08-10 and all exited 0. So the
-- only way this plan produces an unsatisfiable check is by naming a lune test file that does not exist
-- yet — which is why Steps 1.2 and 1.3, and 3.1 and 3.2, are ordered module-then-test, with the module
-- step gated on analyze/lint and the test step on the lune run.

const REENTRY = 'CLAUDE_VERIFY_PLAN_ACTIVE'
-- NOTE: `npm run verify` as a step's check is safe — the sentinel cuts the recursion. Step 6.2 uses it,
-- once, at the point where every file the plan touches is present.
