#!/usr/bin/env node
// The typecheck gate. `luau-lsp analyze` over `src/`, graded against a tracked baseline.
//
//   npm run analyze
//   node .claude/scripts/check-analyze.mjs [--json]
//   node .claude/scripts/check-analyze.mjs --update      re-bless the baseline (humans only)
//   node .claude/scripts/check-analyze.mjs --self-test
//
// This is the highest-value correctness check in the repo — the equivalent of `tsc --noEmit` — and it
// is the reason `.luaurc` sets `languageMode: "strict"`. It found seven real errors in the scaffold
// the first time it ran, including a phase enum that could never satisfy its own type.
//
// ── WHY IT DOES NOT TRUST THE EXIT CODE ────────────────────────────────────────
//
// `luau-lsp analyze` prints diagnostics on stderr and its exit code has not been stable across
// versions. Parsing the diagnostic lines is the signal; the exit code is a hint. A gate whose meaning
// depends on an unpinned convention in someone else's tool is a gate that will one day report green
// on a broken tree and nobody will notice.
//
// ── WHY THERE IS A BASELINE, AND WHY IT IS TRACKED ─────────────────────────────
//
// globalTypes.d.luau is regenerated from Roblox's live API. A Roblox release can therefore introduce
// diagnostics in code nobody touched, which would leave the tree red and the loop unable to start —
// a gate blocked by something no step can fix. The baseline absorbs exactly that.
//
// `analyze-baseline.json` sits at the repository ROOT, tracked, deliberately. It is the single input
// that decides whether the gate can be satisfied at all, so widening it must appear in a diff.
// `--update` refuses to run when CLAUDE_AGENT_TYPE is set: re-blessing is a human act.

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'

import { DEFS_PATH, SOURCEMAP, regenerateSourcemap, sourcemapStale } from './check-toolchain.mjs'

const BASELINE = 'analyze-baseline.json'

// `path (line,col): Kind: message`
const DIAGNOSTIC = /^(\S.*?\.luau?)\s*(?:\[[^\]]*\])?\s*\((\d+),(\d+)\):\s*(\w+):\s*(.+)$/

// The identity of a diagnostic, for baseline comparison. Line and column are DELIBERATELY EXCLUDED:
// the same error sliding down a file because something above it changed is the same error, and a
// baseline keyed on position would go stale on every unrelated edit and have to be re-blessed —
// which is how a baseline becomes a rubber stamp.
export const fingerprint = diagnostic => `${diagnostic.file}::${diagnostic.kind}::${diagnostic.message}`

export const parse = output => {
  const diagnostics = []

  for (const line of output.split('\n')) {
    const match = DIAGNOSTIC.exec(line.trim())

    if (!match) continue

    const [, file, row, col, kind, message] = match

    diagnostics.push({
      file: file.replace(`${process.cwd()}/`, ''),
      line: Number(row),
      column: Number(col),
      kind,
      message: message.trim()
    })
  }

  return diagnostics
}

const readBaseline = () => {
  try {
    const parsed = JSON.parse(readFileSync(BASELINE, 'utf8'))

    return new Set(parsed.known ?? [])
  } catch {
    return new Set()
  }
}

export const grade = (diagnostics, baseline) => {
  const fresh = diagnostics.filter(diagnostic => !baseline.has(fingerprint(diagnostic)))
  const seen = new Set(diagnostics.map(fingerprint))
  const fixed = [...baseline].filter(entry => !seen.has(entry))

  return { fresh, fixed }
}

const analyze = () => {
  if (sourcemapStale()) regenerateSourcemap()

  if (!existsSync(DEFS_PATH)) {
    console.error(`  FAIL  analyze: ${DEFS_PATH} is missing — run \`npm run check:toolchain\` first.`)
    console.error('        Without it the analyzer knows nothing about Roblox and reports a confident green.')
    process.exit(1)
  }

  const args = [
    'analyze',
    `--sourcemap=${SOURCEMAP}`,
    '--base-luaurc=.luaurc',
    `--definitions=${DEFS_PATH}`,
    // Instance types from the sourcemap are structural guesses about a DataModel this analyzer cannot
    // see. Enforcing them strictly reports errors about the MAP, which lives in Studio and not in
    // Git — findings no code change can resolve.
    '--no-strict-dm-types',
    'src'
  ]

  try {
    return execFileSync('luau-lsp', args, { encoding: 'utf8', stdio: 'pipe' })
  } catch (error) {
    return `${error.stdout ?? ''}${error.stderr ?? ''}`
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

  const sample = [
    '[INFO] Loading definitions file: @roblox - .luau-defs/globalTypes.d.luau',
    '/repo/src/server/init.server.luau [game/ServerScriptService/Server](78,3): TypeError: Function only returns 1 value, but 2 are required here',
    '/repo/src/shared/Enums.luau [game/ReplicatedStorage/Shared/Enums](12,4): TypeError: Unknown type \'Folder\'',
    'Total: 2 errors'
  ].join('\n')

  const parsed = parse(sample)

  check('info lines are not diagnostics', parsed.length, 2)
  check('the file is captured', parsed[0].file.endsWith('init.server.luau'), true)
  check('the line is captured', parsed[0].line, 78)
  check('the kind is captured', parsed[0].kind, 'TypeError')

  // The property the whole baseline design rests on.
  const moved = { file: 'a.luau', line: 99, column: 1, kind: 'TypeError', message: 'boom' }
  const original = { file: 'a.luau', line: 12, column: 4, kind: 'TypeError', message: 'boom' }

  check('a diagnostic that only moved keeps its identity', fingerprint(moved), fingerprint(original))

  const different = { file: 'a.luau', line: 12, column: 4, kind: 'TypeError', message: 'other' }

  check('a different message is a different diagnostic', fingerprint(different) !== fingerprint(original), true)

  const baseline = new Set([fingerprint(original)])

  check('a baselined diagnostic is not fresh', grade([original], baseline).fresh.length, 0)
  check('a baselined diagnostic that moved is still not fresh', grade([moved], baseline).fresh.length, 0)
  check('a new diagnostic is fresh', grade([different], baseline).fresh.length, 1)
  check('a resolved diagnostic is reported as fixed', grade([], baseline).fixed.length, 1)
  check('a clean tree with an empty baseline passes', grade([], new Set()).fresh.length, 0)

  console.log(failures ? `  FAIL  check-analyze: ${ran - failures}/${ran}` : `  PASS  check-analyze: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-analyze.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const diagnostics = parse(analyze())

  if (process.argv.includes('--update')) {
    // Widening the definition of "passing" is a deliberate human act. An agent that can re-bless the
    // baseline can make any red tree green, which makes every gate downstream meaningless.
    if (process.env.CLAUDE_AGENT_TYPE) {
      console.error('  FAIL  --update refuses to run under an agent. Re-blessing the baseline is a human decision.')
      process.exit(1)
    }

    writeFileSync(
      BASELINE,
      `${JSON.stringify(
        {
          note: 'Diagnostics allowed to fail. Keyed on file+kind+message, never on line, so unrelated edits do not force a re-bless. Shrinking this list is progress; growing it needs a reason in the commit.',
          blessedAt: new Date().toISOString().slice(0, 10),
          known: [...new Set(diagnostics.map(fingerprint))].sort()
        },
        null,
        2
      )}\n`
    )
    console.log(`- analyze: baseline re-blessed with ${diagnostics.length} known diagnostic(s)`)
    process.exit(0)
  }

  const { fresh, fixed } = grade(diagnostics, readBaseline())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ fresh, fixed, total: diagnostics.length }, null, 2))
    process.exit(fresh.length ? 1 : 0)
  }

  for (const diagnostic of fresh) {
    console.error(`  FAIL  ${diagnostic.file}:${diagnostic.line}:${diagnostic.column} — ${diagnostic.kind}: ${diagnostic.message}`)
  }

  if (fresh.length) {
    console.error(`- analyze: ${fresh.length} new diagnostic(s)`)
    process.exit(1)
  }

  if (fixed.length) {
    console.log(`- analyze: ok — ${fixed.length} baselined diagnostic(s) no longer occur; re-bless with --update`)
    process.exit(0)
  }

  console.log(`- analyze: ok${diagnostics.length ? ` (${diagnostics.length} baselined)` : ''}`)
  process.exit(0)
}
