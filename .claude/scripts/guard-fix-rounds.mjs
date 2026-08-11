#!/usr/bin/env node
// Stop hook: count FIX ROUNDS per source file, and block once when one file has been patched in
// response to three separate review rounds.
//
// WHY THIS EXISTS
// ---------------
// Every loop guard in this harness keys on FAILURE. `loop-breaker` needs a Bash command to fail,
// `verify-gate` needs a red tree, `debug-ladder` needs an error that survives a fix. None of them
// fired while `pure/KillValidation`'s cooldown guard was written WRONG FOUR TIMES and the attrition
// rule three, because every patch turned the tree green — and `verify-gate` CLEARS its attempt log on
// green, so each round started from a blank slate.
//
// The loop was: patch -> green -> an adversarial review finds a different hole in the same line ->
// patch again. Four review rounds, roughly half a million subagent tokens, largely re-covering ground.
// See `.claude/lessons/green-after-each-patch-hides-a-loop.md`, which this guard is the encoded half
// of — delete the lesson once this has proven itself.
//
// WHAT COUNTS AS A FIX ROUND, AND WHY NOT JUST "EDITS"
// ---------------------------------------------------
// Editing one file many times is NORMAL — `RoundService.luau` was legitimately touched in four plan
// phases. A raw edit count would fire on ordinary work and be switched off within a day.
//
// The signal is an edit that lands AFTER a review agent ran. `record-activity.mjs` already writes both
// into one ledger: `{turn, edit}` rows and `{turn, agent}` rows, in order. So a fix round is an edit to
// file X occurring after at least one review launch, and the count is how many DISTINCT review
// generations have been followed by an edit to that same file.
//
// THE WINDOW IS THE LEDGER'S, NOT THE SESSION'S
// ---------------------------------------------
// `record-activity.mjs` keeps only the last `MAX_TURNS_KEPT` (20) turns, so this counts fix rounds
// inside a rolling window rather than over all history. That is the right scope and it is worth
// knowing: a patch loop happens inside one working stretch, and a file that stops being patched ages
// out by itself. It also means this can never accumulate into a permanent accusation about work from
// last week — the failure mode that would get it switched off.
//
// WHY IT BLOCKS ONCE, AND ONLY ADVISES
// ------------------------------------
// It cannot know that the third patch is wrong — only that the shape of the work has been wrong three
// times. So it blocks a single time, states the count, and hands the judgement over. A gate that fires
// every turn is a gate that gets disabled.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const LEDGER = '.claude/.run-ledger.json'
const STATE = '.claude/.fix-rounds-state.json'

// Three, matching the ladder everywhere else in this harness. Two is a coincidence; three is a shape.
export const FIX_ROUND_LIMIT = 3

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readJson = (path, fallback) => {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return fallback
  }
}

const parseRows = text =>
  text
    .trim()
    .split('\n')
    .filter(Boolean)
    .map(line => {
      try {
        return JSON.parse(line)
      } catch {
        return null
      }
    })
    .filter(Boolean)

//  Walk the ledger IN ORDER. A review launch opens a new "generation"; the first edit to a file in a
//  generation is that file's next fix round. Later edits in the same generation are the same round —
//  a fix is usually several edits, and counting them separately would fire on one honest repair.
export const fixRounds = rows => {
  const counts = new Map()
  const seenThisGeneration = new Set()
  let reviewed = false

  for (const row of rows) {
    if (row.agent) {
      reviewed = true
      seenThisGeneration.clear()
      continue
    }

    if (!row.edit || !reviewed) continue
    if (seenThisGeneration.has(row.edit)) continue

    seenThisGeneration.add(row.edit)
    counts.set(row.edit, (counts.get(row.edit) ?? 0) + 1)
  }

  return counts
}

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  if (!existsSync(LEDGER)) process.exit(0)

  const counts = fixRounds(parseRows(readFileSync(LEDGER, 'utf8')))
  const over = [...counts.entries()]
    .filter(([, count]) => count >= FIX_ROUND_LIMIT)
    .sort((a, b) => b[1] - a[1])

  if (over.length === 0) process.exit(0)

  const session = payload?.session_id ?? 'unknown'
  const state = readJson(STATE, {})
  const already = new Set(state.session === session ? (state.reported ?? []) : [])
  const fresh = over.filter(([file]) => !already.has(file))

  if (fresh.length === 0) process.exit(0)

  mkdirSync(dirname(STATE), { recursive: true })
  writeFileSync(STATE, `${JSON.stringify({ session, reported: [...already, ...fresh.map(([file]) => file)] })}\n`)

  const list = fresh.map(([file, count]) => `  · ${file} — ${count} fix rounds`).join('\n')

  const reason =
    `STOP PATCHING — a file has been fixed in response to ${FIX_ROUND_LIMIT} separate review rounds:\n${list}\n\n` +
    `A green tree after each patch is exactly what hides this loop: verify-gate clears its attempt log ` +
    `on green, so every round starts from a blank slate and the next review arrives as a brand-new ` +
    `finding on the same line.\n\n` +
    `Before editing it again:\n` +
    `  1. If it is a pure predicate over a bounded domain, ENUMERATE THE DOMAIN in one test rather ` +
    `than adding a case per bug. A 23-cell grid once found what four reactive patches missed.\n` +
    `  2. Ask whether the RULE'S SHAPE is wrong rather than its edge cases. Three failed fixes on one ` +
    `expression usually means the expression is measuring the wrong thing.\n` +
    `  3. If the shape is wrong and changing it changes what the SPEC means, put that to the user ` +
    `instead of deciding it — docs/MVP-SPEC.md wins over an instinct.\n\n` +
    `This fires once per file per session. See .claude/lessons/green-after-each-patch-hides-a-loop.md.`

  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`)
  process.exit(0)
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

  const rounds = (rows, file) => fixRounds(rows).get(file) ?? 0
  const A = 'src/server/Services/RoundService.luau'
  const B = 'src/shared/pure/KillValidation.luau'

  //  BLOCK — the loop this exists to catch. Edit, review, edit, review, edit.
  check(
    'three fix rounds are counted',
    rounds(
      [
        { agent: 'exploit-auditor' },
        { edit: A },
        { agent: 'exploit-auditor' },
        { edit: A },
        { agent: 'auditor' },
        { edit: A }
      ],
      A
    ),
    3
  )

  //  ALLOW — the half that matters. Ordinary work edits one file constantly and must never trip this.
  check('edits with no review at all are not fix rounds', rounds([{ edit: A }, { edit: A }, { edit: A }], A), 0)
  check(
    'many edits inside ONE review generation are one round',
    rounds([{ agent: 'auditor' }, { edit: A }, { edit: A }, { edit: A }, { edit: A }], A),
    1
  )
  check(
    'edits BEFORE the first review do not count',
    rounds([{ edit: A }, { edit: A }, { agent: 'auditor' }, { edit: A }], A),
    1
  )
  check(
    'rounds are counted per file, not shared',
    rounds([{ agent: 'auditor' }, { edit: A }, { edit: B }, { agent: 'auditor' }, { edit: B }], A),
    1
  )
  check(
    'a second file accumulates independently',
    rounds([{ agent: 'auditor' }, { edit: A }, { edit: B }, { agent: 'auditor' }, { edit: B }], B),
    2
  )
  check('an empty ledger is silent', rounds([], A), 0)
  check('reviews with no edits are silent', rounds([{ agent: 'auditor' }, { agent: 'auditor' }], A), 0)

  console.log(failures ? `  FAIL  guard-fix-rounds: ${ran - failures}/${ran}` : `  PASS  guard-fix-rounds: ${ran}/${ran} cases`)

  return failures === 0
}

if (process.argv[1] && process.argv[1].endsWith('guard-fix-rounds.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest() ? 0 : 1)
  else await main()
}
