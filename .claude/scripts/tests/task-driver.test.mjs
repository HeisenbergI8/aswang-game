#!/usr/bin/env node
// Regression suite for the driver's DECISION — the one part of the loop that must be right.
//
//   node .claude/scripts/tests/task-driver.test.mjs
//
// `decide()` is a pure function of (state, signals, treeGreen, now), which is why it is the thing
// under test rather than the hook plumbing around it. The plumbing is exercised by running the harness
// for real; the decision is exercised here, cheaply, in both directions.
//
// ── THE FOUR CASES THAT JUSTIFY THE WHOLE SUITE ────────────────────────────────
//
// A driver written as ONE ordered list with `tree red -> release` above the halt conditions silently
// abandons runs. A run that is red AND stuck — or red and plan-drifted, red and needing a human, red
// and out of budget — releases every turn forever: the repair loop eventually steps aside, the tree
// stays red, the driver keeps releasing, the pointer stays active, and NO HALT REPORT IS EVER WRITTEN.
//
// The four `red and …` cases below fail against that structure and pass against this one. They are the
// reason halt checks are evaluated unconditionally, before the tree is consulted at all.

import { DEFAULT_BUDGET, PHASE_STUCK_AT, PLANLESS_CEILING, RED_CEILING, decide } from '../task-driver.mjs'

let failures = 0
let ran = 0

const NOW = 1_754_000_000_000

// A run that is healthy in every respect. Each case below perturbs exactly one field, so a failure
// names the condition rather than a soup of them.
const healthy = () => ({
  runId: 'r1',
  objective: 'Build M3',
  planPath: '.claude/plans/feature-tasks-plan/feature-tasks-plan.md',
  iteration: 1,
  phaseIteration: 0,
  redIterations: 0,
  planlessIterations: 0,
  startedAt: new Date(NOW - 10 * 60 * 1000).toISOString(),
  lastBeatAt: new Date(NOW - 60 * 1000).toISOString(),
  budget: DEFAULT_BUDGET,
  paused: false,
  phaseCursor: { phase: '2', passed: 1 }
})

const signals = (patch = {}) => ({
  verdict: { next: { phase: '2', title: 'tasks', passed: 1, total: 4 }, blockedBecause: null },
  goalDone: false,
  unfalsifiable: false,
  ...patch
})

const check = (label, actual, expected) => {
  ran += 1
  if (actual === expected) return

  failures += 1
  console.log(`  FAIL  ${label} — expected ${expected}, got ${actual}`)
}

const action = (state, options = {}) => decide(state, { now: NOW, signals: signals(), ...options }).action

// ── Fast path ──────────────────────────────────────────────────────────────────
check('no active run releases', decide(null, { now: NOW }).action, 'release')
check('an already-active stop hook releases', action(healthy(), { payload: { stop_hook_active: true } }), 'release')

// ── Halts, each on its own ─────────────────────────────────────────────────────
check('the iteration budget halts', action({ ...healthy(), iteration: DEFAULT_BUDGET.iterations }), 'halt')
check(
  'the run wall clock halts',
  action({ ...healthy(), startedAt: new Date(NOW - DEFAULT_BUDGET.runMs - 1000).toISOString() }),
  'halt'
)
check(
  'the iteration wall clock halts',
  action({ ...healthy(), lastBeatAt: new Date(NOW - DEFAULT_BUDGET.iterationMs - 1000).toISOString() }),
  'halt'
)
check('a stuck phase halts', action({ ...healthy(), phaseIteration: PHASE_STUCK_AT }), 'halt')
check(
  'plan drift halts',
  action(healthy(), { signals: signals({ verdict: { next: null, blockedBecause: 'plan-changed' } }) }),
  'halt'
)
check('an unfalsifiable plan halts', action(healthy(), { signals: signals({ unfalsifiable: true }) }), 'halt')
check(
  'a phase needing a human halts',
  action(healthy(), { signals: signals({ verdict: { next: null, blockedBecause: 'needs-human', needsHuman: 'phase 3' } }) }),
  'halt'
)
check(
  'a low-confidence phase halts',
  action(healthy(), {
    signals: signals({ verdict: { next: null, blockedBecause: 'low-confidence', needsHuman: 'phase 3' } })
  }),
  'halt'
)
check(
  'no plan after the ceiling halts',
  action({ ...healthy(), planPath: null, planlessIterations: PLANLESS_CEILING }),
  'halt'
)
check('goal-check reporting done halts', action(healthy(), { signals: signals({ goalDone: true }) }), 'halt')

// A successful halt must be distinguishable from a failure halt, or the model reports a finished run
// as a breakdown.
check(
  'a done halt is marked successful',
  decide(healthy(), { now: NOW, signals: signals({ goalDone: true }) }).success,
  true
)
check(
  'a budget halt is NOT marked successful',
  decide({ ...healthy(), iteration: 99 }, { now: NOW, signals: signals() }).success,
  false
)

// ── THE FOUR. Halt checks run BEFORE the tree is consulted. ────────────────────
check('red AND stuck halts', action({ ...healthy(), phaseIteration: PHASE_STUCK_AT }, { treeGreen: false }), 'halt')
check(
  'red AND plan-drifted halts',
  action(healthy(), { treeGreen: false, signals: signals({ verdict: { next: null, blockedBecause: 'plan-changed' } }) }),
  'halt'
)
// Was `red AND preflight-failed`. `preflightFailures` was never written by anything, so that case
// pinned the ordering against a condition that could not occur; this one is the shape the C02-C04 run
// actually hit — a phase needing a human while the tree was red.
check(
  'red AND needing a human halts',
  action(healthy(), {
    treeGreen: false,
    signals: signals({ verdict: { next: null, blockedBecause: 'needs-human', needsHuman: 'phase 7' } })
  }),
  'halt'
)
check('red AND out of budget halts', action({ ...healthy(), iteration: 99 }, { treeGreen: false }), 'halt')

// ── Releases ───────────────────────────────────────────────────────────────────
check('a paused run releases', action({ ...healthy(), paused: true }), 'release')
check('a red tree alone releases to the repair loop', action(healthy(), { treeGreen: false }), 'release')
check(
  'a red release is flagged so the counter advances',
  decide(healthy(), { now: NOW, signals: signals(), treeGreen: false }).red,
  true
)
check('a run with no plan yet releases', action({ ...healthy(), planPath: null, planlessIterations: 1 }), 'release')
check(
  'a planless release is flagged so patience is bounded',
  decide({ ...healthy(), planPath: null, planlessIterations: 1 }, { now: NOW, signals: signals() }).planless,
  true
)

// ── Drive ──────────────────────────────────────────────────────────────────────
check('a healthy run drives', action(healthy()), 'drive')
check(
  'the drive verdict carries the next phase',
  decide(healthy(), { now: NOW, signals: signals() }).next?.phase,
  '2'
)

// A run one short of every ceiling must still drive. Off-by-one here means the loop stops a phase
// early and reports a cap that was never reached.
check('one below the iteration cap still drives', action({ ...healthy(), iteration: DEFAULT_BUDGET.iterations - 1 }), 'drive')
check('one below the stuck cap still drives', action({ ...healthy(), phaseIteration: PHASE_STUCK_AT - 1 }), 'drive')
check('one below the red ceiling still drives', action({ ...healthy(), redIterations: RED_CEILING - 1 }), 'drive')
check('at the red ceiling it halts', action({ ...healthy(), redIterations: RED_CEILING }), 'halt')

console.log(failures ? `  FAIL  task-driver: ${ran - failures}/${ran}` : `  PASS  task-driver: ${ran}/${ran} cases`)
process.exit(failures ? 1 : 0)
