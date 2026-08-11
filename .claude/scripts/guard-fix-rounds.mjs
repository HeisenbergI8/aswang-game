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
// A LADDER, NOT A BRAKE — the correction that matters
// ---------------------------------------------------
// The first version of this file blocked ONCE per file and then stood aside forever. That is exactly
// the shape `verify-gate.mjs`'s own header describes as the broken version it replaced: "block twice
// saying 'fix it', then delete the counter and stand aside … the two blocks it did issue carried no
// more information the second time than the first". A single advisory block does not stop a loop; the
// fourth and fifth patch walk straight through it.
//
// So this follows the same three-rung ladder every other escalating gate here uses:
//
//   BLOCK     at FIX_ROUND_LIMIT      → name the count, ask the three questions
//   ESCALATE  one round later         → you patched it again after being told; name every round and
//                                       require the redesign to go to the USER, not into another patch
//   HALT      one round after that    → a final report, then permanently silent for that file
//
// EACH RUNG CARRIES MORE THAN THE LAST, which is the other half of the same lesson: a block whose text
// is identical to the previous one is noise, and noise gets a gate switched off.
//
// FAILS OPEN on anything it cannot read. A gate that traps a session protects nothing.
//
// READ-ONLY AGENTS ARE EXEMPT. `auditor`, `change-auditor` and `exploit-auditor` ship with no Edit or
// Write tool at all, so they cannot have caused a fix round and cannot act on this advice. Blocking
// them replays their whole accumulated context to demand a repair they are structurally incapable of
// making — the same reasoning `verify-gate.mjs` documents for the identical set.
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

// Read-only by construction: no Edit or Write tool, so they cannot have caused a fix round.
const READ_ONLY_AGENTS = new Set(['auditor', 'change-auditor', 'exploit-auditor'])

export const RUNGS = ['block', 'escalate', 'halt']

//  Which rung a file is on, given how many rounds it has and how far it has already been pushed.
//  Returns null when it should stay silent — below the limit, or already halted, or the count has not
//  moved since the last rung. THE COUNT MUST ADVANCE to climb: patching a different file, or being
//  told and then stopping, must not escalate anything.
export const rungFor = (count, previous) => {
  if (count < FIX_ROUND_LIMIT) return null

  const rung = Math.min(count - FIX_ROUND_LIMIT, RUNGS.length - 1)
  const priorIndex = previous ? RUNGS.indexOf(previous.rung) : -1

  if (priorIndex >= RUNGS.length - 1) return null
  if (previous && count <= previous.count) return null

  return { rung: RUNGS[Math.max(rung, priorIndex + 1)], count }
}

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  if (READ_ONLY_AGENTS.has(payload?.agent_type)) process.exit(0)

  if (!existsSync(LEDGER)) process.exit(0)

  const counts = fixRounds(parseRows(readFileSync(LEDGER, 'utf8')))

  const session = payload?.session_id ?? 'unknown'
  const state = readJson(STATE, {})
  const seen = state.session === session ? (state.files ?? {}) : {}

  const climbing = [...counts.entries()]
    .map(([file, count]) => ({ file, count, next: rungFor(count, seen[file]) }))
    .filter(entry => entry.next !== null)
    .sort((a, b) => b.count - a.count)

  if (climbing.length === 0) process.exit(0)

  const files = { ...seen }

  for (const entry of climbing) files[entry.file] = { rung: entry.next.rung, count: entry.count }

  mkdirSync(dirname(STATE), { recursive: true })
  writeFileSync(STATE, `${JSON.stringify({ session, files })}\n`)

  const worst = climbing[0]
  const list = climbing.map(entry => `  · ${entry.file} — ${entry.count} fix rounds`).join('\n')

  if (worst.next.rung === 'halt') {
    process.stdout.write(
      `${JSON.stringify({
        decision: 'block',
        reason:
          // Deliberately does NOT claim to have blocked and escalated already. When this guard is
          // installed mid-stream, or a file arrives well past the limit, HALT is the FIRST message it
          // ever sends — and a gate that opens by asserting a history that did not happen is the
          // exact failure the lesson behind it is about.
          `HALT — ${worst.count} fix rounds on one file, which is past the point where another patch ` +
          `is worth attempting:\n${list}\n\n` +
          `This gate stops here and will not block for these files again this session. That is not a ` +
          `verdict that the work is finished — it means this gate has said everything it can.\n\n` +
          `WRITE DOWN, for the user, in this order:\n` +
          `  1. every fix already attempted on this file and what each one turned out to be wrong ` +
          `about — a list, not a summary;\n` +
          `  2. what the rule or function is actually MEASURING, and whether that is the right thing ` +
          `to measure at all;\n` +
          `  3. what changing its shape would cost, INCLUDING whether it changes what docs/MVP-SPEC.md ` +
          `means — if it does, that is the user's decision and not yours.\n\n` +
          `Do not edit this file again before that is written and answered. See ` +
          `.claude/lessons/green-after-each-patch-hides-a-loop.md.`
      })}\n`
    )
    process.exit(0)
  }

  if (worst.next.rung === 'escalate') {
    process.stdout.write(
      `${JSON.stringify({
        decision: 'block',
        reason:
          `ESCALATION — you were told to stop patching this and patched it again:\n${list}\n\n` +
          `Every round so far has ended GREEN, which is why nothing else caught it: verify-gate ` +
          `clears its attempt log on green, so each review arrives as a brand-new finding on the same ` +
          `line with no memory of the last one.\n\n` +
          `A fourth patch is not the answer. Do ONE of these instead:\n` +
          `  · If it is a pure predicate over a bounded domain — ENUMERATE THE DOMAIN in a single ` +
          `test. Not a case per bug. A 23-cell grid once found what four reactive patches missed.\n` +
          `  · If the rule's SHAPE is wrong — say so to the user with the redesign written out, and ` +
          `wait. Three failed fixes on one expression means it is measuring the wrong thing.\n\n` +
          `If you edit it again without doing one of those, this gate halts.`
      })}\n`
    )
    process.exit(0)
  }

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

  //  THE LADDER. The first version of this guard blocked once and stood aside, which is the shape
  //  verify-gate's header calls out as the broken one — the fourth and fifth patch walk through it.
  const rung = (count, previous) => rungFor(count, previous)?.rung ?? null

  check('below the limit is silent', rung(2, undefined), null)
  check('the limit blocks', rung(3, undefined), 'block')
  check('one more round escalates', rung(4, { rung: 'block', count: 3 }), 'escalate')
  check('one after that halts', rung(5, { rung: 'escalate', count: 4 }), 'halt')
  check('after halting it stays silent forever', rung(9, { rung: 'halt', count: 5 }), null)

  //  ALLOW — the half that decides whether this survives contact. A gate that keeps escalating at
  //  someone who has already STOPPED is noise, and noise gets a gate switched off.
  check('no new round does not re-fire the same rung', rung(3, { rung: 'block', count: 3 }), null)
  check('no new round does not escalate an escalation', rung(4, { rung: 'escalate', count: 4 }), null)

  //  A file first SEEN well past the limit opens at the rung its count deserves, not at the bottom.
  //  This is the case when the guard is installed mid-stream — as it was, against a file already on
  //  five rounds. Opening with the gentle "have you considered enumerating the domain" there would be
  //  dishonest about how far gone it already is, and would spend two more rounds getting to the point.
  check('first seen one past the limit opens at escalate', rung(4, undefined), 'escalate')
  check('first seen three past the limit opens at halt', rung(6, undefined), 'halt')

  console.log(failures ? `  FAIL  guard-fix-rounds: ${ran - failures}/${ran}` : `  PASS  guard-fix-rounds: ${ran}/${ran} cases`)

  return failures === 0
}

if (process.argv[1] && process.argv[1].endsWith('guard-fix-rounds.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest() ? 0 : 1)
  else await main()
}
