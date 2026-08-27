#!/usr/bin/env node
// Runs the harness's own regression suites — but only when the harness actually changed.
//
//   node .claude/scripts/harness-selftest.mjs [--force]
//
// ── WHY THE SKIP EXISTS ────────────────────────────────────────────────────────
//
// These suites prove the guard and gate scripts behave in BOTH directions, which matters enormously —
// but only when one of them has changed. On a turn that edited `src/`, they re-prove an unchanged fact,
// and `verify` runs many times a session.
//
// ── HOW IT DECIDES — deliberately dumb ─────────────────────────────────────────
//
// A size+mtime fingerprint over the files under test. Not a content hash: a hash is more precise, and
// precision is not what this needs. Every failure mode here must fail toward RUNNING the suite, and a
// stale-but-simple check does that naturally.
//
// It runs the full suite when ANY of these is true:
//   - no fingerprint on file (first run, or cleared)
//   - the fingerprint file is missing / corrupt / unreadable
//   - any watched file's size or mtime differs
//   - a file was added or removed
//   - the previous run FAILED (the pass marker is written only on success)
//   - --force was passed
//
// The only path that skips is a complete, readable, matching fingerprint whose recorded run PASSED.
// Anything ambiguous runs the tests. Being occasionally conservative costs a few seconds; being wrong
// in the other direction ships an unproven guard.
//
// ── EVERY SUITE MUST BE LISTED HERE ────────────────────────────────────────────
//
// A test file outside every gate is documentation, not a test. This list and `npm run check:guards`
// are the only two things that execute them, so a suite added without a line here never runs — and it
// will be reported as green from memory, which is worse than not having written it.
//
// ── AND THE ALLOW HALF OF EVERY SUITE IS THE HALF THAT MATTERS ─────────────────
//
// A guard that only proves it can REFUSE has proven the cheap half. The expensive failure is refusing
// correct work until somebody switches the guard off — and then it protects nothing at all. So each
// suite must pin both directions, and the allow cases should be the shapes a naive version genuinely
// did refuse: `guards.test.mjs` carries 31 allows against 26 blocks, and several of the allows are
// exactly those. `verify-gate`'s `canRepair` cases are written the same way — five agent types that
// must still get the full repair ladder, against the four that provably cannot edit `src/`.

import { execFileSync } from 'node:child_process'
import { readdirSync, readFileSync, statSync, writeFileSync, rmSync, existsSync } from 'node:fs'
import { join } from 'node:path'

const STATE_PATH = '.claude/.harness-selftest.json'

// Directories whose contents these suites exercise. settings.json is included because hook wiring
// changes what the guards are asked to do, even when no script changed.
const WATCHED_DIRS = [
  { dir: '.claude/scripts', match: /\.mjs$/ },
  { dir: '.claude/scripts/lib', match: /\.mjs$/ },
  { dir: '.claude/scripts/tests', match: /\.mjs$/ },
  { dir: '.claude/lessons', match: /\.md$/ }
]
const WATCHED_FILES = ['.claude/settings.json']

export const SUITES = [
  // The loop core. task-driver first: if its decision is wrong nothing downstream matters.
  ['task-driver', ['.claude/scripts/tests/task-driver.test.mjs']],
  ['build-trigger', ['.claude/scripts/build-trigger.mjs', '--self-test']],
  ['verify-plan', ['.claude/scripts/verify-plan.mjs', '--self-test']],
  ['goal-check', ['.claude/scripts/goal-check.mjs', '--self-test']],
  ['check-debug', ['.claude/scripts/check-debug.mjs', '--self-test']],
  ['guard-fix-rounds', ['.claude/scripts/guard-fix-rounds.mjs', '--self-test']],
  // Pins that a live run is never ended by asking to continue it. The failure it encodes halted a run
  // at `iterations: 0` — paused, never driven, and indistinguishable from a working loop.
  ['guard-loop-pause', ['.claude/scripts/guard-loop-pause.mjs', '--self-test']],
  // Pins that a human-only step blocks the LOOP only once the cursor reaches it — the fix for a plan
  // whose last phase needed a person halting the whole run at iteration 0.
  ['next-phase', ['.claude/scripts/next-phase.mjs', '--self-test']],
  // Reads the SAME `### Phase N:` convention next-phase and verify-plan depend on, so the three must
  // agree. It is what `implement-plan` and the auditor load a plan through; a slicer that quietly
  // truncates a phase hands over a short contract that verify-plan still grades green.
  ['plan-phase', ['.claude/scripts/plan-phase.mjs', '--self-test']],
  ['preflight', ['.claude/scripts/preflight.mjs', '--self-test']],
  ['ensure-rojo', ['.claude/scripts/ensure-rojo.mjs', '--self-test']],

  // The accountability layer.
  ['hook-payload', ['.claude/scripts/lib/hook-payload.mjs', '--self-test']],
  ['verify-gate', ['.claude/scripts/verify-gate.mjs', '--self-test']],
  ['claim-check', ['.claude/scripts/claim-check.mjs', '--self-test']],
  ['review-gate', ['.claude/scripts/review-gate.mjs', '--self-test']],
  ['lessons', ['.claude/scripts/lessons.mjs', '--self-test']],
  ['candidates', ['.claude/scripts/candidates.mjs', '--self-test']],

  // The guards.
  ['guards', ['.claude/scripts/tests/guards.test.mjs']],
  ['guard-studio-sync', ['.claude/scripts/guard-studio-sync.mjs', '--self-test']],
  ['guard-inplace-edit', ['.claude/scripts/guard-inplace-edit.mjs', '--self-test']],
  ['guard-commit', ['.claude/scripts/guard-commit.mjs', '--self-test']],
  ['gate-luau-analyze', ['.claude/scripts/gate-luau-analyze.mjs', '--self-test']],

  // The repo-specific checks.
  ['check-secrecy', ['.claude/scripts/check-secrecy.mjs', '--self-test']],
  ['check-remotes', ['.claude/scripts/check-remotes.mjs', '--self-test']],
  ['check-config', ['.claude/scripts/check-config.mjs', '--self-test']],
  ['check-scope', ['.claude/scripts/check-scope.mjs', '--self-test']],
  ['check-ratelimit', ['.claude/scripts/check-ratelimit.mjs', '--self-test']],
  ['check-testcount', ['.claude/scripts/check-testcount.mjs', '--self-test']],
  ['check-toolchain', ['.claude/scripts/check-toolchain.mjs', '--self-test']],
  ['check-analyze', ['.claude/scripts/check-analyze.mjs', '--self-test']],
  ['run-luau-tests', ['.claude/scripts/run-luau-tests.mjs', '--self-test']]
]

// ── A SUITE THAT IS NOT LISTED IS A SUITE THAT NEVER RUNS ──────────────────────
//
// The list above is hand-maintained, which means it can fall behind the directory. This compares the
// two and fails loudly rather than silently skipping — the exact failure this file exists to prevent,
// applied to itself.
export const unlistedSuites = (dir = '.claude/scripts/tests') => {
  if (!existsSync(dir)) return []

  const listed = new Set(SUITES.flatMap(([, args]) => args.filter(arg => arg.endsWith('.mjs'))))

  return readdirSync(dir)
    .filter(name => name.endsWith('.test.mjs'))
    .map(name => join(dir, name))
    .filter(path => !listed.has(path))
}

// Returns null on ANY problem. A null fingerprint can never match, so the suite runs.
const fingerprint = () => {
  try {
    const entries = []

    for (const { dir, match } of WATCHED_DIRS) {
      if (!existsSync(dir)) continue

      for (const name of readdirSync(dir).sort()) {
        const path = join(dir, name)

        if (!match.test(name) || statSync(path).isDirectory()) continue

        const { size, mtimeMs } = statSync(path)

        entries.push(`${path}:${size}:${Math.round(mtimeMs)}`)
      }
    }

    for (const file of WATCHED_FILES) {
      const { size, mtimeMs } = statSync(file)

      entries.push(`${file}:${size}:${Math.round(mtimeMs)}`)
    }

    return entries.join('|')
  } catch {
    return null
  }
}

const readRecordedPass = () => {
  try {
    const { fingerprint: recorded, passed } = JSON.parse(readFileSync(STATE_PATH, 'utf8'))

    return passed === true && typeof recorded === 'string' ? recorded : null
  } catch {
    return null
  }
}

const main = () => {
  const forced = process.argv.includes('--force')
  const current = fingerprint()
  const recorded = readRecordedPass()

  const orphans = unlistedSuites()

  if (orphans.length) {
    console.error(`  FAIL  harness: ${orphans.length} test file(s) exist but are not in SUITES: ${orphans.join(', ')}`)
    console.error('        A suite outside every gate is documentation, not a test. Add it to harness-selftest.mjs.')

    return 1
  }

  if (!forced && current !== null && recorded !== null && current === recorded) {
    console.log('- harness self-tests skipped (scripts, lessons and settings unchanged since last green run)')

    return 0
  }

  // The marker is dropped BEFORE running, so an interrupted or failed run can never leave a stale pass.
  try {
    rmSync(STATE_PATH, { force: true })
  } catch {
    /* absence is the desired state anyway */
  }

  for (const [name, args] of SUITES) {
    try {
      execFileSync('node', args, { encoding: 'utf8', stdio: 'inherit', env: { ...process.env, CLAUDE_HOOK_TEST: '1' } })
    } catch {
      console.error(`\n${name} FAILED — harness self-tests will re-run on the next verify.`)

      return 1
    }
  }

  if (current !== null) {
    try {
      writeFileSync(STATE_PATH, JSON.stringify({ fingerprint: current, passed: true }))
    } catch {
      /* not recording it only means running the suite again next time */
    }
  }

  console.log(`- harness: ${SUITES.length} suite(s) ok`)

  return 0
}

process.exit(main())
