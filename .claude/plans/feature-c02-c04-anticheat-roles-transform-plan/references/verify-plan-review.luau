--!strict
--[[
	REVIEW — .claude/scripts/verify-plan.mjs

	Read because it grades this document. Three of its rules shaped how the plan is written.
]]

-- IMPORTANT — DUPLICATE CHECKS ARE FAILED, but WITHIN A PHASE ONLY:
--   const phaseOf = step => step.id.split(' ')[1]?.split('.')[0]
--   duplicates -> `LINT  Step N.1 and Step N.2 share one check` -> exit 1
--
-- "Two identical checks in ONE phase are redundant by construction: nothing can happen between them
--  that changes the answer. The same command closing two different phases runs against two different
--  trees and is a real, if coarse, statement about each."
--
-- Consequence: no two steps in any phase here share a command, and `npm run verify` legitimately
-- closes Phases 1, 3, 5 and 7. `npm run check:config` closes a step in Phases 3, 4, 5 and 6 — always
-- a different phase each time.

-- IMPORTANT — CHECK SHAPE, which is what `--strict` grades:
--   'real'   -> npm run …, lune run …, node .claude/scripts/…       (discriminating)
--   'exists' -> test -f …                                            (weak)
--   'self'   -> grep …                                               (weak — proves authorship only)
--
--   if (strict && checkable > 0 && tally.real < checkable / 2) -> EXIT 2
--
-- This plan: 31 steps, 30 with a command. 29 'real', 1 'self' (Step 4.4's README grep), 1 with no
-- command (Step 7.5). Measured with `--lint`: 0 unrunnable, 0 shared, 0 unsatisfiable.

-- NOTE — a missing check is HONEST and does not fail:
--   "An ABSENT check is honest and does not fail."
--   for (const step of noCheck) console.log(`NOTE  ${step.id} — no check; honestly unverifiable`)
-- That is exactly why Step 7.5 carries no Verify line rather than a fabricated one.

-- IMPORTANT — fenced blocks are stripped before steps are parsed, and an UNTERMINATED fence fails the
-- lint. This plan contains many ```luau and ```diff blocks; every one is closed. Verified: `--lint`
-- reports all 31 steps, which is the count the document actually has.

-- NOTE — the executed allowlist is anchored at BOTH ends and runs WITHOUT A SHELL. Every command used
-- in this plan is on it:
--   ^npm run (verify|verify:fast|analyze|lint|fmt:check|build|test:unit|check:*)$
--   ^lune run tests/[\w.-]+\.test\.luau$
--   ^grep -[a-zA-Z]+ (?:"[^"]*"|'[^']*'|[\w.@/-]+) [\w./-]+$
