#!/usr/bin/env node
// A test suite's PASS line must COUNT what it ran, not assert a number somebody typed.
//
//   node .claude/scripts/check-testcount.mjs [--json]
//   node .claude/scripts/check-testcount.mjs --self-test
//
// ── WHY THIS EXISTS ───────────────────────────────────────────────────────────
//
// `tests/config.test.luau` ended with:
//
//     print("  PASS  config: 34 balance invariants")
//
// with 34 as a STRING LITERAL. It printed 34 when the suite held 34 checks and it printed 34 after
// seven more were added for C13–C16. It would have printed 34 with seven DELETED.
//
// That is the specific failure this guard is built from, and the reason it is worth a script rather
// than a habit: the summary line is exactly what you glance at to answer "did all my invariants
// survive that refactor", and a literal makes it structurally incapable of answering. Every other
// signal stayed green throughout — the suite passed, `verify` passed, the count was simply fiction.
//
// It is the same shape as `analyze-baseline.json` being tracked at the repo root: a number that
// describes the tree has to MOVE when the tree moves, or it is decoration.
//
// ── WHAT COUNTS AS A VIOLATION ────────────────────────────────────────────────
//
// A digit in a `PASS` print that sits OUTSIDE a `{...}` interpolation. Inside braces it is computed
// from something — `{checked}`, `{#CASES}`, `{#HALF_WIDTHS * #GRACES}` — and therefore moves with the
// suite. Outside, it is a claim nobody re-checks.
//
// ── THE WAIVER IS EXPECTED HERE, MORE THAN IN THE OTHER CHECKS ────────────────
//
// Some numbers in these lines are claims about the DOMAIN rather than tallies of work: "the full
// 512-cell grid" says the input space has 512 points, which is a fact about the type being tested and
// not about how many asserts ran. Those are legitimate and they take `-- count-ok: <reason>`, which
// puts the justification in the diff where it can be argued with.
//
// The distinction the guard cannot draw — tally vs. domain claim — is exactly the one a human should
// draw once, in writing, per line. That is the design, not a shortcoming.

import { mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, lineOf, readSource, report } from './lib/luau-source.mjs'

const TESTS = 'tests'

// A STRING LITERAL carrying the PASS banner — quoted or backticked.
//
// THIS DELIBERATELY DOES NOT MATCH `print(`, AND THAT IS THE SECOND BUG THIS FILE WAS BUILT FROM.
// The first version was `/print\s*\(([^\n]*PASS[^\n]*)\)/`, which requires the call and its argument
// to share a line. StyLua wraps a long call to
//
//     print(
//         `  PASS  role-draw: {checked} assertions — shape, determinism, weighting`
//     )
//
// and the guard silently found nothing — measured at 0 findings against a wrapped print holding a
// hardcoded 34. `npm run fmt` runs inside `npm run verify`, so the repo's own formatter would have
// switched this check off for precisely the files it had just reformatted, and a check with nothing
// to say is indistinguishable from a check with nothing to find.
//
// Keying on the literal instead makes the layout irrelevant. Comments are already blanked by
// `stripComments`, so a number in prose above the print is not a claim.
const PASS_LITERAL = /(["`])((?:(?!\1)[^\n])*PASS(?:(?!\1)[^\n])*)\1/g

// `{...}` spans are computed. Removing them first is what makes the digit test meaningful.
const INTERPOLATION = /\{[^{}]*\}/g

export const listTests = (root = TESTS) => {
  let entries = []

  try {
    entries = readdirSync(root, { withFileTypes: true })
  } catch {
    return []
  }

  return entries
    .filter(entry => entry.isFile() && entry.name.endsWith('.test.luau'))
    .map(entry => join(root, entry.name))
    .sort()
}

export const scan = files => {
  const findings = []

  for (const file of files) {
    // `withStrings`, not `code`: this guard reads the CONTENTS of a string literal, which is exactly
    // what `stripNonCode` removes. Comments are still blanked (a number in a comment above the print
    // is not a claim), and blanking preserves offsets, so `lineOf` stays true to the raw file.
    const { raw, withStrings } = readSource(file)
    const rawLines = raw.split('\n')

    for (const match of withStrings.matchAll(PASS_LITERAL)) {
      const argument = match[2]
      const computedRemoved = argument.replace(INTERPOLATION, '')

      const literal = computedRemoved.match(/\d+(?:\.\d+)?/)

      if (!literal) continue

      const line = lineOf(withStrings, match.index)

      if (hasWaiver(rawLines, line, 'count')) continue

      findings.push({
        file,
        line,
        why: `hardcoded ${literal[0]} in a PASS summary`,
        detail:
          'A summary number must be computed from the suite (a counter, `#CASES`, a product of the ' +
          'grid dimensions) so it moves when the suite does. If it states a fact about the input ' +
          'domain rather than a tally, waive it with `-- count-ok: <reason>`.'
      })
    }
  }

  return findings
}

const selfTest = () => {
  const dir = mkdtempSync(join(tmpdir(), 'testcount-'))
  const testsDir = join(dir, 'tests')

  mkdirSync(testsDir, { recursive: true })

  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag) => {
    ran += 1

    const path = join(testsDir, 'sample.test.luau')

    writeFileSync(path, source)

    const flagged = scan([path]).length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
  }

  // BLOCK — the bug this guard was built from, and its neighbours.
  check('the literal that started this', 'print("  PASS  config: 34 balance invariants")', true)
  check('a literal in a backtick string', 'print(`  PASS  config: 34 balance invariants`)', true)
  check('a literal beside a computed value', 'print(`  PASS  x: {n} draws, 12 bands`)', true)
  check('a literal in a multi-part summary', 'print("  PASS  kill: 16 grid cells + 35 cases")', true)
  check('a decimal literal', 'print("  PASS  x: 1.5 seconds covered")', true)

  // BLOCK — the StyLua-wrapped forms. `npm run fmt` produces these, and the first version of this
  // guard scored 0 findings against them, which would have made `npm run verify` disable the check on
  // the very files it had just reformatted.
  check('a wrapped print, quoted', 'print(\n\t"  PASS  wrapped: 34 balance invariants"\n)', true)
  check('a wrapped print, backticked', 'print(\n\t`  PASS  wrapped: 34 invariants`\n)', true)
  check('a wrapped print mixing computed and literal', 'print(\n\t`  PASS  x: {n} draws, 12 bands`\n)', true)

  // ALLOW — the half that matters. A guard nobody can satisfy is a guard that gets deleted.
  check('a counter', 'print(`  PASS  config: {checked} balance invariants`)', false)
  check('a length operator', 'print(`  PASS  round: {#CASES} exhaustive cases`)', false)
  check('an expression over grid dimensions', 'print(`  PASS  t: {#A * #B} configurations`)', false)
  check('two computed values', 'print(`  PASS  t: {a} over {b} cases`)', false)
  check('prose with no number at all', 'print("  PASS  role-draw: shape, determinism, weighting")', false)
  check(
    'a waived domain claim',
    'print(`  PASS  fetch: {n} assertions over the full 512-cell grid`) -- count-ok: 512 is the size of the input space, not a tally',
    false
  )
  check('a digit in an unrelated print', 'print("seeded with 42")', false)
  check('a digit in a comment above the print', '-- 34 invariants once lived here\nprint(`  PASS  x: {n}`)', false)
  check('a wrapped print with only computed values', 'print(\n\t`  PASS  wrapped: {checked} assertions`\n)', false)
  check(
    'a wrapped print waived on the literal line',
    'print(\n\t`  PASS  x: {n} over the full 512-cell grid` -- count-ok: 512 is the input domain\n)',
    false
  )
  check('a FAIL line with a number', 'print(`  FAIL  x: 3 violated`)', false)
  check('an empty file', '', false)

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-testcount: ${ran - failures}/${ran}` : `  PASS  check-testcount: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-testcount.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(listTests())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(findings, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  process.exit(report('testcount', findings, { note: 'suite summaries count what ran' }))
}
