#!/usr/bin/env node
// Runs every `tests/*.test.luau` under Lune and fails on the first non-zero exit.
//
//   npm run test:unit
//   node .claude/scripts/run-luau-tests.mjs [--json]
//   node .claude/scripts/run-luau-tests.mjs --self-test
//
// ── WHY LUNE AND NOT A ROBLOX TEST FRAMEWORK ───────────────────────────────────
//
// TestEZ and its descendants run INSIDE Roblox, which means a test run needs Studio open, a place
// loaded, and a human to press Play. That is not a gate — it is a ritual, and a gate nobody can run
// unattended cannot be wired into `verify`, cannot be a plan step's `**Verify:**` line, and cannot
// stop the task loop advancing over broken work.
//
// Lune runs Luau on the command line in milliseconds. The price is that it is not Roblox: no `game`,
// no `Instance`, no DataModel. So this covers pure modules only, and `tests/README.md` says so out
// loud rather than letting the coverage gap be discovered later.
//
// The protocol is the exit code and nothing else. No format to parse, no reporter to keep in sync
// with the runner — the failure mode where a test harness reports green because its own parser
// stopped matching is not available here.

import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const TESTS_DIR = 'tests'

export const discover = (dir = TESTS_DIR) => {
  if (!existsSync(dir)) return []

  return readdirSync(dir)
    .filter(name => name.endsWith('.test.luau'))
    .sort()
    .map(name => join(dir, name))
}

const runOne = file => {
  try {
    return { file, ok: true, out: execFileSync('lune', ['run', file], { encoding: 'utf8', stdio: 'pipe' }) }
  } catch (error) {
    return { file, ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` }
  }
}

const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const names = ['config.test.luau', 'README.md', 'helper.luau', 'roles.test.luau', 'notes.txt']
  const picked = names.filter(name => name.endsWith('.test.luau'))

  check('only .test.luau files are discovered', picked, ['config.test.luau', 'roles.test.luau'])
  check('a missing tests directory is not a failure', discover('does-not-exist'), [])

  // AN EMPTY SUITE MUST NOT REPORT GREEN. A glob that silently matches nothing is the classic way a
  // test gate stops testing: it keeps exiting 0 while proving nothing, and the change that broke it
  // is invisible because green is what you expected to see.
  const verdict = files => (files.length === 0 ? 'fail' : 'run')

  check('an empty suite fails rather than passing vacuously', verdict([]), 'fail')
  check('a populated suite runs', verdict(['tests/config.test.luau']), 'run')

  console.log(failures ? `  FAIL  run-luau-tests: ${ran - failures}/${ran}` : `  PASS  run-luau-tests: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('run-luau-tests.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const files = discover()

  if (files.length === 0) {
    console.error(`  FAIL  test:unit found no ${TESTS_DIR}/*.test.luau files.`)
    console.error('        An empty suite exiting 0 is how a test gate quietly stops testing.')
    process.exit(1)
  }

  const results = files.map(runOne)
  const failed = results.filter(result => !result.ok)

  for (const result of results) {
    const text = result.out.trim()

    if (text) console.log(text.split('\n').map(line => (line.startsWith('  ') ? line : `  ${line}`)).join('\n'))
  }

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ total: files.length, failed: failed.map(result => result.file) }, null, 2))
  }

  if (failed.length) {
    console.error(`- test:unit: ${failed.length}/${files.length} file(s) failed`)
    process.exit(1)
  }

  console.log(`- test:unit: ${files.length} file(s) ok`)
  process.exit(0)
}
