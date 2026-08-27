#!/usr/bin/env node
// Stop gate: refuses to let a turn end by STALLING a live `/build` run.
//
// THE FAILURE THIS EXISTS FOR, observed on run 2026-08-27T08-26-34-722Z-V03.
//
// `/build` is a supervised loop: code decides whether to continue, the model does the work. The skill
// says it stops for a problem and for nothing else. But `implement-plan`'s Checkpoint step says to
// "pause for confirmation" after a phase with a deviation — and a type annotation in a test file is a
// deviation. Read literally, the two instructions contradict, and the literal reading wins because it
// is the more specific one.
//
// So the turn ended on "Phase 1 landed. Next is Phase 2." The user read that as a request for
// permission, answered it, and THAT MESSAGE PAUSED THE RUN — any message that is not `/build …` does.
// The loop never took an iteration. It sat paused until its wall-clock budget expired and halted with
// `iterations: 0`, having driven nothing, while the work was done by hand on the main thread.
//
// The cost is not the stall itself; it is that a paused run and a working run look identical from the
// outside. Nothing was red, nothing failed, no guard fired. The run simply never started.
//
// WHY A LIVE RUN IS ENOUGH, with no check for remaining phases. `task-driver.mjs` halts the run the
// moment its four `done` proxies are satisfied, and `activeRun` returns null for a halted run. So a
// run that is still live is a run with work left in it, by construction. Asking that question a second
// way here would give a second answer that could disagree with the driver's, which is worse than not
// asking.
//
// WHAT THIS DOES NOT TOUCH, because these are the half that matters:
//
//   · NO RUN LIVE. Ordinary work outside the loop pauses to ask all the time and should.
//   · ALREADY PAUSED. The user paused it deliberately; blocking would argue with them.
//   · A SUBSTANTIVE QUESTION. "Which of these three approaches", "may I mutate the place file" — a
//     decision that is genuinely the user's is not a stall, and the patterns below do not match one.
//     Only asking to CONTINUE, or announcing the next phase and stopping, is a stall.
//
// It also cannot trap a session: MAX_BLOCKS is a ladder, and after it the gate stands aside.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

import { beat } from './hook-heartbeat.mjs'
import { activeRun } from './run-state.mjs'

const STATE = '.claude/.loop-pause-state.json'
const MAX_BLOCKS = 2

// ── USE vs MENTION ─────────────────────────────────────────────────────────────
//
// Lifted from `claim-check.mjs`, and load-bearing for the same reason: this gate's subject IS a
// sentence, so any message DOCUMENTING it — a halt report, a commit body, this file's own header
// quoted back — would trip it forever. Fenced and quoted spans are stripped before matching.
//
// Bold is NOT stripped: a real stall is usually written in bold ("Next is **Phase 2**"), so stripping
// it would let the exact shape this gate exists for walk straight through.
export const stripQuoted = text =>
  text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/"[^"\n]{0,200}"/g, ' ')
    .replace(/[“”][^“”\n]{0,200}[“”]/g, ' ')

// Asking to be allowed to carry on. Every one of these is a question whose answer, inside a live run,
// is already yes — the run IS the answer.
export const PERMISSION_PATTERNS = [
  /\b(shall|should|can|may)\s+I\s+(now\s+)?(continue|proceed|carry\s+on|go\s+ahead|move\s+on|start|begin)\b/i,
  /\b(let\s+me\s+know|tell\s+me|say\s+the\s+word)\b[^.\n]{0,70}\b(continue|proceed|carry\s+on|go\s+ahead|next\s+phase)\b/i,
  /\bwait(ing)?\s+for\s+(your\s+)?(confirmation|approval|go[-\s]?ahead|sign[-\s]?off|the\s+word)\b/i,
  /\b(pausing|paused|stopping|holding)\s+(here\s+)?for\s+(your\s+)?(confirmation|approval|input|go[-\s]?ahead)\b/i,
  /\b(ready|happy)\s+to\s+(continue|proceed|move\s+on)\b[^.\n]{0,40}\?/i,
  /\bconfirm\b[^.\n]{0,50}\b(and\s+I(\s+will|'ll)|then\s+I(\s+will|'ll)|before\s+I)\b/i,
  /\b(want|would\s+you\s+like)\s+me\s+to\s+(continue|proceed|carry\s+on|keep\s+going|start\s+phase)\b/i
]

// Announcing the next phase and then stopping. This is the shape that actually fired — it contains no
// question mark at all, which is exactly why a naive interrogative check would have missed it.
export const STALL_PATTERNS = [
  /\bnext\s+(is|up|comes)\b[^.\n]{0,90}\bphase\s*\d/i,
  /\bphase\s*\d[^.\n]{0,60}\bis\s+next\b/i,
  /\b(on|moving|onto|next)\s+to\s+phase\s*\d/i,
  /\bthat\s+leaves\s+phase\s*\d/i,
  /\bremaining\s*:\s*phase\s*\d/i
]

// THE VERDICT, as a pure function so the self-test can drive both directions without a payload, a
// filesystem or a live run. `runLive` and `paused` are facts the caller reads off `activeRun`.
export const verdict = ({ message, runLive, paused }) => {
  if (!runLive) return null
  if (paused) return null
  if (typeof message !== 'string' || message.trim() === '') return null

  const text = stripQuoted(message)

  if (PERMISSION_PATTERNS.some(pattern => pattern.test(text))) return 'permission'
  if (STALL_PATTERNS.some(pattern => pattern.test(text))) return 'stall'

  return null
}

const REASONS = {
  permission: [
    'LOOP STALLED — you asked permission to continue a live `/build` run.',
    '',
    'The run IS the permission. `/build` stops for a problem and for nothing else, and a message',
    'from the user is not how you get told to carry on — it PAUSES the run, which is what turns a',
    'working loop into one that halts at `iterations: 0` having driven nothing.',
    '',
    'If this is a real blocker — a decision only the user can make, a destructive action, a red tree',
    'you cannot repair — say so plainly and name it as a blocker. Otherwise continue into the next',
    'phase now: `npm run plan:phase -- <plan> <N>`, implement, gate, log.'
  ].join('\n'),
  stall: [
    'LOOP STALLED — you announced the next phase and ended the turn instead of doing it.',
    '',
    'A live `/build` run means the work is not finished: `task-driver.mjs` halts the moment its four',
    '`done` proxies are satisfied, so a run that is still live has a phase left in it.',
    '',
    '`implement-plan` says to pause for confirmation on a deviation. That applies to a deviation that',
    'changes the plan\'s REMAINING phases — not to a type annotation or a reordered diff. Log the small',
    'ones under Deviations and keep going.',
    '',
    'Continue into the next phase now: `npm run plan:phase -- <plan> <N>`, implement, gate, log.'
  ].join('\n')
}

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

const writeState = state => {
  mkdirSync(dirname(STATE), { recursive: true })
  writeFileSync(STATE, `${JSON.stringify(state)}\n`)
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

  beat('guard-loop-pause', payload)

  if (payload.stop_hook_active === true) process.exit(0)

  // `last_assistant_message` is not guaranteed on every build. Absent, this gate does nothing — it
  // has no second signal to fall back on, and a gate that guesses is worse than one that abstains.
  const message = payload.last_assistant_message

  if (typeof message !== 'string') process.exit(0)

  const run = activeRun(payload.session_id)
  const call = verdict({ message, runLive: run !== null, paused: run?.paused === true })

  if (call === null) process.exit(0)

  const key = `${payload.session_id ?? 'unknown'}:${run?.runId ?? 'run'}`
  const state = readJson(STATE, {})

  // Stand aside rather than trap the session. The model has been told twice.
  if ((state[key] ?? 0) >= MAX_BLOCKS) {
    delete state[key]
    writeState(state)
    process.exit(0)
  }

  state[key] = (state[key] ?? 0) + 1
  writeState(state)

  block(REASONS[call])
}

// ── SELF-TEST ──────────────────────────────────────────────────────────────────
//
// THE ALLOW CASES ARE THE HALF THAT MATTERS. A gate that blocks every question would make the loop
// unable to ask the one thing it genuinely must — and this repo's V03 run had exactly such a question
// in it (whether to mutate a place file that is not in Git). Those cases are pinned first.
const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1

    if (actual === expected) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const live = message => verdict({ message, runLive: true, paused: false })

  //  BLOCK — the shape that actually fired. No question mark anywhere in it.
  check('announcing the next phase and stopping', live('Phase 1 landed and is green. Next is Phase 2 — the network surface.'), 'stall')
  check('bold next-phase announcement', live('**Next up is Phase 3**, the service itself.'), 'stall')
  check('moving on to phase N', live('That is Phase 2 done. Moving on to Phase 3.'), 'stall')

  //  BLOCK — asking to be allowed to carry on.
  check('shall I continue', live('Phase 2 is green. Shall I continue?'), 'permission')
  check('should I proceed', live('Should I proceed with the next chunk of work?'), 'permission')
  check('want me to continue', live('Do you want me to continue with the remaining phases?'), 'permission')
  check('waiting for confirmation', live('I am waiting for your confirmation before going further.'), 'permission')
  check('let me know to proceed', live('Let me know and I will proceed to the next phase.'), 'permission')
  check('paused for approval', live('Pausing here for your approval.'), 'permission')

  //  ALLOW — no run live. Ordinary work asks for confirmation constantly and must be free to.
  check('no run live, permission ask', verdict({ message: 'Shall I continue?', runLive: false, paused: false }), null)
  check('no run live, phase announcement', verdict({ message: 'Next is Phase 2.', runLive: false, paused: false }), null)

  //  ALLOW — already paused. The user did that on purpose; arguing with them is not this gate's job.
  check('already paused', verdict({ message: 'Shall I continue?', runLive: true, paused: true }), null)

  //  ALLOW — a substantive question only the user can answer. THE CASE THAT MUST NOT REGRESS: this is
  //  close to verbatim the question the V03 run genuinely needed to ask.
  check(
    'a real decision for the user',
    live('The barrio has no tagged containers. Should I tag 15 props myself, or will you do it? The place file is not in Git.'),
    null
  )
  check(
    'a scope question',
    live('The exploit auditor found seven issues. Which of them belong in this chunk rather than a follow-up?'),
    null
  )
  check('reporting a genuine blocker', live('The tree is red and I cannot repair it from a read-only agent. Stopping.'), null)
  check('an ordinary progress report', live('Phase 2 is green: 25 remotes declared, 25 wired, secrecy ok.'), null)
  check('empty message', live(''), null)
  check('a phase mentioned without stalling', live('Phase 2 widened the ActionHandlers contract, which Phase 4 then consumes.'), null)

  //  USE vs MENTION. This file, the halt report and a commit body all DESCRIBE the blocked shape. If
  //  quoting it tripped the gate, the gate could never be written about.
  check('the shape quoted in backticks', live('The guard fires on `Next is Phase 2` and blocks it.'), null)
  check('the shape inside a fence', live('Example:\n```\nNext is Phase 2.\n```\nThat is what it catches.'), null)
  check('the shape in double quotes', live('It matches "Shall I continue?" and refuses the turn.'), null)

  //  Payload robustness — a missing or non-string message must never block.
  check('undefined message', verdict({ message: undefined, runLive: true, paused: false }), null)
  check('non-string message', verdict({ message: 42, runLive: true, paused: false }), null)

  console.log(
    failures > 0
      ? `  FAIL  guard-loop-pause: ${failures} of ${ran} case(s) failed`
      : `  PASS  guard-loop-pause: ${ran} cases — stalls and permission asks blocked, real questions allowed`
  )

  return failures === 0
}

if (process.argv[1] && process.argv[1].endsWith('guard-loop-pause.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest() ? 0 : 1)
  else await main()
}
