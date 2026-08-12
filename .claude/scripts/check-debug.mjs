#!/usr/bin/env node
// Every `Config.Debug` switch is off.
//
//   node .claude/scripts/check-debug.mjs [--json]
//   node .claude/scripts/check-debug.mjs --self-test
//
// ── WHY THIS IS A CHECK AND NOT A TEST ─────────────────────────────────────────
//
// `tests/config.test.luau` already asserts `SoloTesting == false`, and for a long time that was
// believed to be what stopped a debug flag reaching history: the tree goes red, and `guard-commit.mjs`
// refuses a red tree.
//
// IT DOES NOT. `guard-commit.mjs` runs `npm run verify:fast`, and `verify:fast` is
// `analyze && check:remotes && check:secrecy && verify:harness:fast` — no `test:unit`. The config test
// runs only under the full `npm run verify`. So a debug flag left on passed the commit guard, and
// `verify-gate.mjs` (the Stop gate) uses `verify:fast` too, so it never blocked a turn either.
//
// An audit found this while reviewing a FORCE-ROLE switch that had been written on the strength of
// that false guarantee. The flag would have shipped, and on a published place it rigs the draw.
//
// So the assertion moved to where the guard can see it. It costs a file read and needs no Lune.
//
// WHERE IT ACTUALLY RUNS, since an earlier version of this line got it wrong and a comment in
// `RoleService.luau` was written on the strength of it: NOT `verify:fast`, which is
// `analyze && check:remotes && check:secrecy && verify:harness:fast`. It runs in the full `npm run
// verify`, and — the part that matters — `guard-commit.mjs` invokes this script DIRECTLY, right after
// `verify:fast`. That direct call is the only thing standing between a debug flag and history.
//
// It is deliberately NOT in `verify:fast`, and `guard-commit.mjs`'s own comment explains why:
// `verify-gate.mjs` runs `verify:fast` on every Stop, so putting it there would block every turn of a
// Studio session for having testing values set — the exact state a Studio session is supposed to be
// in. The guard would make the thing it guards untestable. A commit is where the question belongs.
//
// The Luau test stays. It is not redundant: it pins the same values with the reasons attached, and it
// is what a person reads when they want to know WHY the flag must be off. This one is what stops the
// commit.

import { readFileSync } from 'node:fs'

const CONFIG = 'src/shared/Config.luau'

// Each flag, and the value it must hold in a committed tree. A flag absent from Config is not an
// error — features get removed — but a flag present and set is.
export const DEBUG_DEFAULTS = new Map([
  ['SoloTesting', 'false'],
  ['VerboseLogging', 'false'],
  // Studio-only and solo-only in code, but a rigged draw is worth two independent guards.
  ['ForceAswangWhenSolo', 'false']
])

// Reads the `Debug = { ... }` block only. A `SoloTesting` mentioned in a comment elsewhere, or a
// same-named field in another section, must not be picked up.
export const debugBlock = source => {
  const start = source.indexOf('Debug = {')

  if (start === -1) return null

  const end = source.indexOf('\n\t},', start)

  return source.slice(start, end === -1 ? source.length : end)
}

export const scan = source => {
  const block = debugBlock(source)

  if (block === null) {
    return [{ flag: '(none)', why: `no \`Debug = {}\` block found in ${CONFIG}` }]
  }

  const findings = []

  for (const [flag, expected] of DEBUG_DEFAULTS) {
    // Comments are not stripped, so require the assignment to start a line — a mention inside a
    // comment is indented differently and carries no `=` at line start.
    const match = new RegExp(`^\\s*${flag}\\s*=\\s*([^,\\n]+),`, 'm').exec(block)

    if (!match) continue

    const actual = match[1].trim()

    if (actual !== expected) findings.push({ flag, actual, expected })
  }

  return findings
}

const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (actual === expected) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const wrap = body => `local Config = {\n\tDebug = {\n${body}\n\t},\n}\n`

  check(
    'a clean Debug block passes',
    scan(wrap('\t\tSoloTesting = false,\n\t\tVerboseLogging = false,\n\t\tForceAswangWhenSolo = false,')).length,
    0
  )
  check('SoloTesting left on is caught', scan(wrap('\t\tSoloTesting = true,')).length, 1)
  check('VerboseLogging left on is caught', scan(wrap('\t\tVerboseLogging = true,')).length, 1)
  check('a forced solo Aswang is caught', scan(wrap('\t\tForceAswangWhenSolo = true,')).length, 1)
  check('two flags left on are both caught', scan(wrap('\t\tSoloTesting = true,\n\t\tVerboseLogging = true,')).length, 2)

  // A flag that no longer exists is not a failure — features get removed.
  check('an absent flag is not a finding', scan(wrap('\t\tSoloTesting = false,')).length, 0)

  // THE ALLOW HALF THAT MATTERS. The block is found by name, so a same-named field in another section
  // must not be read, and a comment mentioning the flag must not trip it.
  check(
    'a same-named field outside Debug is ignored',
    scan(`local Config = {\n\tRound = {\n\t\tSoloTesting = true,\n\t},\n\tDebug = {\n\t\tSoloTesting = false,\n\t},\n}\n`).length,
    0
  )
  check(
    'a comment naming a flag is ignored',
    scan(wrap('\t\t-- SoloTesting = true, was left here during C04\n\t\tSoloTesting = false,')).length,
    0
  )

  console.log(failures ? `  FAIL  check-debug: ${ran - failures}/${ran}` : `  PASS  check-debug: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-debug.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(readFileSync(CONFIG, 'utf8'))

  if (process.argv.includes('--json')) console.log(JSON.stringify(findings, null, 2))

  if (findings.length === 0) {
    console.log('- debug: ok (every Config.Debug switch is off)')
    process.exit(0)
  }

  for (const finding of findings) {
    console.error(
      `  FAIL  ${CONFIG} — Debug.${finding.flag} = ${finding.actual ?? '?'}, must be ${finding.expected ?? 'absent'}`
    )
  }

  console.error('        A debug switch in a committed tree ships to players. Revert it before committing.')
  console.error(`- debug: ${findings.length} finding(s)`)
  process.exit(1)
}
