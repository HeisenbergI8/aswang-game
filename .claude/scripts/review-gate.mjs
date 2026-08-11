#!/usr/bin/env node
// Stop gate: the review agents are what CLAUDE.md's routing table says run on every tier above
// Trivial, and the only thing that has ever made them run is remembering to launch them.
//
// WHAT THIS IS NOT. It does not spawn anything. A hook is a shell command; it cannot call the Agent
// tool. All it can do is refuse the turn and name what to launch — the same primitive verify-gate and
// task-driver run on. This is a reminder with a blocking backstop, not an executor.
//
// ── THE PREDICATE IS THE WHOLE DESIGN ──────────────────────────────────────────
//
// `Stop` fires at the end of EVERY turn, including "what does this file do?". There is no
// "task finished" event to hang this on, so it needs a proxy — and a bad proxy is expensive: a gate
// that nags wrongly gets switched off, and then it protects nothing.
//
// The proxy is the signal the model ALREADY emits when it believes it is done: a full `npm run
// verify`. CLAUDE.md directs `verify:fast` mid-task and `verify` as the closing gate, and
// `record-activity.mjs` records them as two distinct kinds — the `(?!:)` lookahead is what separates
// them. So "still working" and "wrapping up" are already distinguishable in the ledger, at no cost.
//
// Consequence, stated plainly: a turn that ends on `verify:fast` does not fire this. That is a MISS,
// accepted deliberately. Misses are the cheap failure here; false fires are the expensive one.
//
// ── ONE BLOCK, EVER ────────────────────────────────────────────────────────────
//
// Not two. verify-gate escalates because a red tree is a defect; this is a judgement call, and
// "that was trivial, skip it" is a legitimate answer that must cost three words.

import { existsSync, readFileSync, readdirSync, mkdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

import { beat } from './hook-heartbeat.mjs'
import { activeRun } from './run-state.mjs'

const LEDGER = '.claude/.run-ledger.json'
const STATE = '.claude/.review-state.json'
const PLANS = '.claude/plans'

// A plan whose implementation log was written within this window is the plan this work belongs to.
// Two hours is loose on purpose: naming the wrong auditor costs a correction, and the reason string
// says how to override it.
const PLAN_RECENT_MS = 2 * 60 * 60 * 1000

// `resumed` is not an agent type — it is what record-activity writes when a reviewer is continued via
// SendMessage, where only the agent's id is known and not its type. Resuming keeps the auditor's own
// prior findings in context and is strictly better than a fresh spawn, so it must not read as nothing.
const REVIEW_AGENTS = new Set(['playtester', 'auditor', 'change-auditor', 'exploit-auditor', 'resumed'])

// ── WHEN THE EXPLOIT AUDITOR IS NOT OPTIONAL ───────────────────────────────────
//
// Spec §6.2 and §11 both name exploiters revealing the Aswang as the top engineering risk, and this is
// a game where knowing the imposter IS the win condition. Any diff touching the server, the remote
// surface, or the role logic changes the attack surface, and `check-secrecy.mjs` is only a tripwire on
// the obvious shapes — it cannot follow data flow.
//
// So the gate names a THIRD agent for those diffs. It still blocks only once.
const SECURITY_SURFACE = /(^|\/)src\/server\/|Remotes\.luau$|RoleService|MonsterService|AntiCheatService/

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

// ── The decision, as a pure function ───────────────────────────────────────────
//
// Exported so the tests can assert both directions without spawning a process or fabricating a hook
// payload. A test that builds the shape the READER wants rather than the shape the WRITER produces is
// how a gate passes its tests for months while never firing once.
export const decide = ({ edits = [], verifyGreen = false, agentsRun = [], buildActive = false, alreadyNudged = false }) => {
  if (alreadyNudged) return { action: 'pass', why: 'already nudged for this turn' }

  // task-driver.mjs owns verification inside a /build run and has its own spawn budget. Two mechanisms
  // independently demanding subagents would exhaust that budget and halt the run with an error that
  // looks unrelated to its cause.
  if (buildActive) return { action: 'pass', why: '/build run active — task-driver owns this' }

  if (!edits.length) return { action: 'pass', why: 'no tracked source edited this turn' }
  if (!verifyGreen) return { action: 'pass', why: 'no green full `verify` — still mid-task' }

  // Filtered HERE as well as in readTurn, and not by accident. Any subagent completion reaches the
  // ledger, so trusting this list unfiltered would let an unrelated Explore agent silence the gate.
  const reviewed = [...new Set(agentsRun)].filter(agent => REVIEW_AGENTS.has(agent))

  if (reviewed.length) return { action: 'pass', why: `already ran: ${reviewed.join(', ')}` }

  return {
    action: 'nudge',
    why: 'source changed, full verify green, no review agent ran',
    security: edits.some(file => SECURITY_SURFACE.test(file))
  }
}

// ── Ledger read ────────────────────────────────────────────────────────────────
export const readTurn = (text, turn) => {
  const edits = []
  const agentsRun = []
  let verifyGreen = false

  for (const line of (text ?? '').split('\n')) {
    if (!line) continue

    let event

    try {
      event = JSON.parse(line)
    } catch {
      continue
    }

    if (event.turn !== turn) continue
    if (event.edit && !edits.includes(event.edit)) edits.push(event.edit)
    // LAST WRITE WINS, not "any green run". This latched `true` on the first green `verify` and stayed
    // there, so a turn that ran verify green, then edited source and ran it RED, still reported the tree
    // as passing — and the gate's own message said "`npm run verify` passed" over a red tree. A gate
    // that misreports the tree state is worse than no gate, because it is the thing everyone else
    // stops looking after.
    if (event.run === 'verify') verifyGreen = event.ok === true
    if (event.agent && REVIEW_AGENTS.has(event.agent)) agentsRun.push(event.agent)
  }

  return { edits, verifyGreen, agentsRun }
}

// Which auditor applies. `auditor` traces a written plan step by step and needs a plan directory;
// `change-auditor` audits the diff against the request. Presence of a plan decides it.
export const pickAuditor = (now = Date.now(), root = PLANS) => {
  try {
    for (const entry of readdirSync(root)) {
      const log = join(root, entry, 'implementation-log.md')

      if (existsSync(log) && now - statSync(log).mtimeMs < PLAN_RECENT_MS) return { agent: 'auditor', plan: entry }
    }
  } catch {
    /* no plans directory is the common case, and it means change-auditor */
  }

  return { agent: 'change-auditor', plan: null }
}

const reason = ({ edits, auditor, security }) => {
  const shown = edits.slice(0, 6).map(file => `  ${file}`).join('\n')
  const more = edits.length > 6 ? `\n  …and ${edits.length - 6} more` : ''

  return (
    `You edited ${edits.length} tracked Luau file(s) and \`npm run verify\` passed, but no review agent ` +
    `has run this turn:\n${shown}${more}\n\n` +
    `Launch these IN ONE MESSAGE with \`run_in_background: true\`:\n` +
    `  · \`playtester\` — does it actually work in Studio\n` +
    `  · \`${auditor.agent}\` — was the request delivered, and nothing else` +
    (auditor.plan ? ` (plan: ${auditor.plan})` : '') +
    (security
      ? `\n  · \`exploit-auditor\` — this diff touches the server, the remote surface, or role logic. ` +
        `\`check-secrecy\` is a tripwire on obvious shapes only; it cannot follow data flow, and the ` +
        `Aswang's identity leaking ends the game rather than degrading it (spec §6.2).`
      : '') +
    `\n\nDEMAND AN ARTIFACT FROM THE PLAYTESTER. A behavioural PASS must carry a screenshot path, a ` +
    `console excerpt, or a command and its exit code — something the user can open. "The round works" ` +
    `with nothing behind it is NOT VERIFIED, and you must relay it to the user as not verified. Studio ` +
    `MCP makes the artifact cheap: \`start_stop_play\`, \`get_console_output\`, \`screen_capture\`. ` +
    `A claim with no artifact is worse than silence, because it stops anyone else looking.` +
    `\n\nConcurrency is not an optimisation. These agents share no data — the playtester drives the ` +
    `running place, the auditors read the diff — so sequencing them only adds the slower one's wall ` +
    `clock to the faster one's.\n\n` +
    `IF THIS DID NOT NEED THEM — a rename, a comment, a doc edit — say so to the user in one line and ` +
    `finish. This gate blocks ONCE and will not ask again.`
  )
}

const main = async () => {
  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  beat('review-gate', payload)

  if (payload.stop_hook_active === true) process.exit(0)
  if (!existsSync('package.json')) process.exit(0)

  const turn = payload.prompt_id ?? payload.session_id ?? 'unknown'
  const key = `${payload.session_id ?? 'unknown'}:${turn}`

  // One slot, not a growing map. The gate blocks at most once per turn and turns are sequential.
  const state = readJson(STATE, {})

  const { edits, verifyGreen, agentsRun } = readTurn(
    (() => {
      try {
        return readFileSync(LEDGER, 'utf8')
      } catch {
        return ''
      }
    })(),
    turn
  )

  let buildActive = false

  try {
    buildActive = Boolean(activeRun(payload.session_id))
  } catch {
    // A driver that cannot be read is not a reason to nag. Fail toward silence.
    buildActive = true
  }

  const verdict = decide({ edits, verifyGreen, agentsRun, buildActive, alreadyNudged: state.lastKey === key })

  if (process.argv.includes('--status')) {
    console.log(JSON.stringify({ turn, edits, verifyGreen, agentsRun, buildActive, verdict }, null, 2))
    process.exit(0)
  }

  if (verdict.action !== 'nudge') process.exit(0)

  mkdirSync(dirname(STATE), { recursive: true })
  writeFileSync(STATE, `${JSON.stringify({ lastKey: key })}\n`)

  process.stdout.write(
    `${JSON.stringify({
      decision: 'block',
      reason: reason({ edits, auditor: pickAuditor(), security: verdict.security })
    })}\n`
  )
  process.exit(0)
}

if (process.argv[1]?.endsWith('review-gate.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const check = (label, actual, expected) => {
      ran += 1
      if (JSON.stringify(actual) === JSON.stringify(expected)) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
    }

    const base = { edits: ['src/server/Services/RoundService.luau'], verifyGreen: true, agentsRun: [], buildActive: false }

    // NUDGE — the one shape worth interrupting for.
    check('source edited, verify green, nothing reviewed', decide(base).action, 'nudge')

    // PASS — every other shape, and there are more of them on purpose.
    check('nothing edited', decide({ ...base, edits: [] }).action, 'pass')
    check('mid-task, no full verify', decide({ ...base, verifyGreen: false }).action, 'pass')
    check('the playtester already ran', decide({ ...base, agentsRun: ['playtester'] }).action, 'pass')
    check('an auditor already ran', decide({ ...base, agentsRun: ['change-auditor'] }).action, 'pass')
    check('a /build run owns this', decide({ ...base, buildActive: true }).action, 'pass')
    check('already nudged this turn', decide({ ...base, alreadyNudged: true }).action, 'pass')

    // An unrelated agent must NOT silence the gate — the ledger records every subagent completion.
    check('an unrelated agent does not count as review', decide({ ...base, agentsRun: ['Explore'] }).action, 'nudge')

    // A REVIEWER RESUMED VIA SendMessage. Continuing an auditor keeps its own prior findings in
    // context and is strictly better than a fresh spawn; before this it read as nothing at all,
    // so doing the better thing looked like doing nothing.
    check('a resumed reviewer counts', decide({ ...base, agentsRun: ['resumed'] }).action, 'pass')

    // LAUNCHES, not only completions. These reviewers are launched in the background and finish two
    // or three turns later, so the turn that edited the source always looked unreviewed. Every nudge
    // during this repo's C02-C04 work was that, fired at reviewers that were already running.
    check('a reviewer launched this turn counts', decide({ ...base, agentsRun: ['exploit-auditor'] }).action, 'pass')

    // The security escalation.
    check('a server diff names the exploit auditor', decide(base).security, true)
    check('a Remotes diff names it too', decide({ ...base, edits: ['src/shared/Remotes.luau'] }).security, true)
    check('a client-only diff does not', decide({ ...base, edits: ['src/client/Controllers/UIController.luau'] }).security, false)

    // The ledger reader, driven with the shape record-activity actually writes.
    const ledger = [
      JSON.stringify({ turn: 't1', edit: 'src/server/Services/RoleService.luau' }),
      JSON.stringify({ turn: 't1', run: 'verify:fast', ok: true }),
      JSON.stringify({ turn: 't1', run: 'verify', ok: true }),
      JSON.stringify({ turn: 't1', agent: 'playtester' }),
      JSON.stringify({ turn: 't2', edit: 'src/client/init.client.luau' }),
      'not json at all'
    ].join('\n')

    const t1 = readTurn(ledger, 't1')

    check('edits are read for this turn only', t1.edits.length, 1)
    check('a full verify is distinguished from verify:fast', t1.verifyGreen, true)
    check('a review agent is recorded', t1.agentsRun, ['playtester'])
    check('a torn line does not crash the read', readTurn(ledger, 't2').edits.length, 1)
    check('verify:fast alone is not a full verify', readTurn(ledger, 't2').verifyGreen, false)

    console.log(failures ? `  FAIL  review-gate: ${ran - failures}/${ran}` : `  PASS  review-gate: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  main()
}
