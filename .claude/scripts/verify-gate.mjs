#!/usr/bin/env node
// Stop / SubagentStop gate: runs `npm run verify:fast` and refuses to let the turn end on a red tree.
//
// A blocking Stop hook re-invokes the model with `reason` as feedback. That is an iteration
// primitive, and using it only as a BRAKE — block twice saying "fix it", then stand aside — lets
// roughly one red tree in three walk through, with the second block carrying no more information than
// the first.
//
// This is a repair loop instead. Three things differ:
//
//   PREDICATE   "is the tree red?"        → still that, but keyed on WHICH failure
//   REASON      "fix it" (a complaint)    → the next action, plus what was already tried
//   EXHAUSTION  reset-and-allow           → escalate, then HALT with a report
//
// PROGRESS, NOT ATTEMPTS, DRIVES ESCALATION. Counting retries punishes a loop that is converging
// (three different fixes producing three different failures IS progress) and rewards one that thrashes
// with a reworded command. Each iteration fingerprints the failure SET; a changed fingerprint resets
// the counter, an unchanged one escalates.
//
// FAILS OPEN on anything it cannot parse. A gate that traps a session gets switched off, and then it
// protects nothing.

import { execFileSync } from 'node:child_process'
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname } from 'node:path'

import { beat } from './hook-heartbeat.mjs'

const STATE_PATH = '.claude/.verify-state.json'
const LEDGER = '.claude/.run-ledger.json'
const RUN_DIR = '.claude/.run'

// Two attempts against the SAME failure, then halt on the third. This counts repeats of one failure,
// not blocks in a row.
const MAX_SAME_FAILURE = 3

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readState = () => {
  try {
    return JSON.parse(readFileSync(STATE_PATH, 'utf8'))
  } catch {
    return {}
  }
}

const writeState = state => {
  mkdirSync(dirname(STATE_PATH), { recursive: true })
  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`)
}

// ── The fingerprint ────────────────────────────────────────────────────────────
//
// Line and column numbers are stripped deliberately. The same error moving down a file because
// something above it changed is NOT progress — it is the same problem. A different error kind, a
// different file, or a different failing check IS progress, and resets the counter.
export const fingerprint = output => {
  const signatures = output
    .split('\n')
    .map(line => line.trim())
    // The shapes this repo's gate actually emits: luau-lsp diagnostics, selene warnings, and the
    // `FAIL` / `BLOCK` prefixes every check script under .claude/scripts/ uses.
    .filter(line => /TypeError|SyntaxError|^FAIL|^BLOCK|error\[|warning\[|Diff in /i.test(line))
    .map(line =>
      line
        .replace(/\(\d+,\d+\)/g, '')
        .replace(/:\d+:\d+/g, '')
        .replace(/:\d+\b/g, '')
        .replace(/\s+/g, ' ')
        .slice(0, 160)
    )

  const unique = [...new Set(signatures)].sort()

  if (!unique.length) return { hash: 'unparsed', lines: [] }

  return { hash: createHash('sha1').update(unique.join('\n')).digest('hex').slice(0, 12), lines: unique }
}

// Files touched this session, newest last. Read from the activity ledger rather than from git, so it
// reflects what the agent actually edited rather than what happens to be dirty.
const recentEdits = () => {
  try {
    const edits = readFileSync(LEDGER, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map(line => {
        try {
          return JSON.parse(line).edit
        } catch {
          return null
        }
      })
      .filter(Boolean)

    return [...new Set(edits)].slice(-6)
  } catch {
    return []
  }
}

const attemptsPath = key => `${RUN_DIR}/${key.replace(/[^\w.-]/g, '_')}.jsonl`

const recordAttempt = (key, entry) => {
  try {
    mkdirSync(RUN_DIR, { recursive: true })
    appendFileSync(attemptsPath(key), `${JSON.stringify(entry)}\n`)
  } catch {
    /* the ledger is evidence, not a dependency */
  }
}

const priorAttempts = key => {
  try {
    return readFileSync(attemptsPath(key), 'utf8')
      .split('\n')
      .filter(Boolean)
      .map(line => JSON.parse(line))
      .slice(-3)
  } catch {
    return []
  }
}

const clearAttempts = key => {
  try {
    writeFileSync(attemptsPath(key), '')
  } catch {
    /* nothing to clear */
  }
}

const block = reason => {
  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`)
  process.exit(0)
}

const main = async () => {
  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  beat('verify-gate', payload)

  // Also beat under an EVENT-SCOPED name. This hook is registered on Stop AND SubagentStop, and the
  // heartbeat keys by hook name — so the two payloads' key sets merge and neither can be read on its
  // own. That defeats the heartbeat's second purpose ("what did the payload actually carry"), which is
  // precisely the question to answer before building anything that reads a SubagentStop field.
  beat(`verify-gate:${payload.hook_event_name ?? 'unknown'}`, payload)

  if (payload.stop_hook_active === true) process.exit(0)
  if (!existsSync('package.json')) process.exit(0)

  const key = `${payload.session_id ?? 'unknown'}:${payload.agent_id ?? 'main'}`
  const state = readState()
  const previous = typeof state[key] === 'number' ? { count: state[key] } : (state[key] ?? {})

  try {
    execFileSync('npm', ['run', '--silent', 'verify:fast'], { encoding: 'utf8', stdio: 'pipe' })

    // GREEN. The run is over — clear the counter and the attempt log so the next objective starts from
    // nothing rather than inheriting a stale fingerprint.
    if (state[key]) {
      delete state[key]
      writeState(state)
      clearAttempts(key)
    }

    process.exit(0)
  } catch (error) {
    const output = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim()
    const print = output.split('\n').slice(-15).join('\n')
    const { hash, lines } = fingerprint(output)

    // Already halted on this run: say nothing further. The model was told to stop and report; blocking
    // again would be the trap this gate exists to avoid.
    if (previous.halted) process.exit(0)

    const sameFailure = previous.hash === hash
    const count = sameFailure ? (previous.count ?? 0) + 1 : 1
    const edits = recentEdits()

    recordAttempt(key, { at: new Date().toISOString(), hash, count, files: edits, failing: lines.slice(0, 4) })

    // ── HALT ────────────────────────────────────────────────────────────────
    //
    // Three passes at one failure with no change in it. Blocking again produces variations of
    // something that has already failed three times.
    if (count >= MAX_SAME_FAILURE) {
      state[key] = { hash, count, halted: true }
      writeState(state)

      const report = [
        `# Repair loop halted — ${new Date().toISOString()}`,
        '',
        `Failure signature \`${hash}\` survived ${count} attempts unchanged.`,
        '',
        '## What is failing',
        '',
        '```',
        ...lines.slice(0, 8),
        '```',
        '',
        '## What was tried',
        '',
        ...priorAttempts(key).map(
          (attempt, index) => `${index + 1}. ${attempt.at} — touched ${attempt.files.join(', ') || '(nothing recorded)'}`
        ),
        '',
        'The loop stopped rather than continue producing variations of a failed fix.'
      ].join('\n')

      try {
        mkdirSync(RUN_DIR, { recursive: true })
        writeFileSync(`${RUN_DIR}/halt-report.md`, `${report}\n`)
      } catch {
        /* the message below still carries the essentials */
      }

      block(
        `HALT — the same failure has survived ${count} attempts and the loop is stopping.\n\n` +
          `Signature \`${hash}\`:\n${lines.slice(0, 6).join('\n')}\n\n` +
          `DO NOT attempt another fix. Tell the user plainly: the tree is red, what is failing, and what ` +
          `you tried. The full record is at \`${RUN_DIR}/halt-report.md\`.`
      )
    }

    state[key] = { hash, count, halted: false }
    writeState(state)

    // ── ESCALATE ────────────────────────────────────────────────────────────
    //
    // Same failure again. Repeating "fix it" produces a variation of the fix that already failed, so
    // the directive changes: the KIND of fix must change.
    if (sameFailure) {
      const tried = priorAttempts(key)
        .map(attempt => `  · ${attempt.files.join(', ') || '(no source edits recorded)'}`)
        .join('\n')

      block(
        `SAME FAILURE, attempt ${count} of ${MAX_SAME_FAILURE}. The signature has not changed, so the last ` +
          `fix did not address the cause.\n\n${print}\n\n` +
          `Already tried:\n${tried || '  · (nothing recorded)'}\n\n` +
          `Change the KIND of fix, not its details. Load \`.claude/skills/debug-ladder/SKILL.md\` and work ` +
          `it — reproduce it smaller, or question an assumption you have not tested yet. One more repeat ` +
          `and this halts.`
      )
    }

    // ── FIRST SIGHT, or a DIFFERENT failure ─────────────────────────────────
    //
    // A changed fingerprint means the last change moved the problem — that is progress, and the counter
    // resets. The reason names the next action rather than complaining.
    block(
      `\`npm run verify:fast\` is red, so this turn is not complete.\n\n${print}\n\n` +
        `Next: fix the failure above, then let this gate re-run. If it turns out you cannot, say so to ` +
        `the user plainly rather than reporting success.`
    )
  }
}

if (process.argv[1]?.endsWith('verify-gate.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const check = (label, actual, expected) => {
      ran += 1
      if (JSON.stringify(actual) === JSON.stringify(expected)) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
    }

    const typeError = 'src/a.luau [game/X](12,4): TypeError: Unknown type Folder'
    const movedError = 'src/a.luau [game/X](88,2): TypeError: Unknown type Folder'
    const otherError = 'src/b.luau [game/Y](12,4): TypeError: Unknown global warn'

    check('the same error at a new line is the SAME failure', fingerprint(typeError).hash, fingerprint(movedError).hash)
    check('a different error is a DIFFERENT failure', fingerprint(typeError).hash !== fingerprint(otherError).hash, true)
    check('order does not change the fingerprint', fingerprint(`${typeError}\n${otherError}`).hash, fingerprint(`${otherError}\n${typeError}`).hash)
    check('a selene warning is captured', fingerprint('warning[unused_variable]: x is never used').lines.length, 1)
    check('a stylua diff is captured', fingerprint('Diff in src/a.luau:').lines.length, 1)
    check('a check-script FAIL is captured', fingerprint('  FAIL  src/x.luau:3 — magic number 8').lines.length, 1)
    check('unparseable output is named, not guessed at', fingerprint('something went wrong').hash, 'unparsed')

    // The property escalation rests on. Three DIFFERENT failures in a row must never look like one
    // failure repeated — that is a converging loop, and punishing it is the failure mode.
    const three = [typeError, otherError, 'src/c.luau [game/Z](1,1): SyntaxError: unexpected end'].map(
      line => fingerprint(line).hash
    )

    check('three different failures produce three fingerprints', new Set(three).size, 3)

    console.log(failures ? `  FAIL  verify-gate: ${ran - failures}/${ran}` : `  PASS  verify-gate: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  main()
}
