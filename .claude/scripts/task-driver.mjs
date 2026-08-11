#!/usr/bin/env node
// The task loop's driver. Registered on `Stop`, and on nothing else.
//
// A blocking Stop hook re-invokes the model with `reason` as feedback. That is the iteration
// primitive this whole system is built on: code decides WHETHER to continue and WHAT is next, the
// model does the work.
//
//   node .claude/scripts/task-driver.mjs            reads a hook payload on stdin
//   node .claude/scripts/task-driver.mjs --status   what the driver would do, and whether it beats
//   node .claude/scripts/task-driver.mjs --decide <state.json> [--payload <p.json>]   pure decision
//
// ── STOP ONLY, NEVER SubagentStop ─────────────────────────────────────────────
//
// `verify-gate.mjs` is registered on both, and CLAUDE.md mandates running the playtester and auditor
// CONCURRENTLY. A driver wired the same way would increment the iteration counter on every subagent
// completion — twice, from two processes, racing. The repair loop survives that because it keys on
// `session_id:agent_id`; the driver has no such key, so it is not given the chance.

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

import { beat } from './hook-heartbeat.mjs'
import { RUN_ROOT, activeRun, halt, hashPlan, update } from './run-state.mjs'
// The attempts ledger is verify-gate's, because verify-gate is what writes it. run-state carried a
// second, never-written copy and this file read that one — so "Already tried" was empty on every run.
import { describeAttempts } from './verify-gate.mjs'

// ── Caps ───────────────────────────────────────────────────────────────────────
//
// | Cap                  | Value      | Derived from                                            |
// | Iterations           | 8/session  | below where compaction bites                            |
// | Wall clock/iteration | 35 min     | an agent driving Studio through MCP is slow; headroom    |
// | Wall clock/run       | 4 hours    | architect + phases + verification + fixes               |
// | Tokens               | none       | UNMEASURED — see below                                  |
//
// THE TOKEN CAP IS DELIBERATELY ABSENT. A cap chosen from a guess halts mid-milestone every time.
// `hook-heartbeat.mjs` records which keys each payload carries; add a token cap only once `usage` is
// observed to be among them.
//
// A `spawns: 14` cap and a `preflightFailures >= 2` halt used to sit here too. Both were UNREACHABLE:
// nothing in the harness ever incremented either field, so the two conditions could not fire and the
// two budgets protected nothing while reading — in the docs and in this table — as though they did.
// They are removed rather than wired, because wiring them means new machinery (a spawn event for every
// agent type in record-activity; a third `verify:fast` per turn for preflight) to enforce guessed
// numbers the iteration and wall-clock caps already bound. `preflight.mjs` itself is untouched and
// still runs as the manual entry check that `build/SKILL.md` and the playtester actually use.
export const DEFAULT_BUDGET = {
  iterations: 8,
  runMs: 4 * 60 * 60 * 1000,
  iterationMs: 35 * 60 * 1000
}

// Three, because the repair loop already gets three attempts at one failure before halting — a phase
// with no new step PASS across three DRIVEN iterations has had nine chances at the problem underneath.
export const PHASE_STUCK_AT = 3

// Four, because the repair loop's own halt should fire first. The driver is the backstop here, not
// the primary: the repair loop owns FIXING a red tree, it does not own GIVING UP on one.
export const RED_CEILING = 4

// ── A RUN WITH NO PLAN CANNOT BE DRIVEN ────────────────────────────────────────
//
// `/build` creates the run BEFORE a plan exists — the architect has not run yet — so `planPath` is
// legitimately null for the first few turns and the driver must stand aside while the model plans.
//
// But it cannot stand aside forever. Without a plan the cursor has nothing to read, so `next` is null,
// and a naive driver blocks every turn with "no incomplete phase reported; re-read the plan and the
// cursor" while pointing at a document that does not exist. A loop that burns its whole budget
// instructing the model to re-read nothing is worse than one that refuses.
export const PLANLESS_CEILING = 3

const scriptDir = new URL('.', import.meta.url).pathname

const run = (file, args, options = {}) => {
  try {
    return { ok: true, out: execFileSync(file, args, { stdio: 'pipe', encoding: 'utf8', ...options }) }
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}`, code: error.status ?? 1 }
  }
}

// ── The expensive-signal cache ─────────────────────────────────────────────────
//
// Both the stuck check and goal-check need verify-plan, which executes ONE COMMAND PER STEP. Thirty
// steps means thirty executions on every Stop.
//
// Keyed on (planHash, git tree hash): the answer can only change when the plan or the tree moves.
const treeHash = () => {
  const written = run('git', ['write-tree'])

  if (written.ok) return written.out.trim().slice(0, 12)

  // Not a git tree, or an index that cannot be written. A constant would make the cache permanently
  // valid; a unique value makes it never valid — slow, but never wrong.
  return `nogit-${Date.now()}`
}

const cachePath = runId => join(RUN_ROOT, runId, 'signals.json')

const cachedSignals = (runId, planPath, planHash) => {
  const key = `${planHash}:${treeHash()}`

  try {
    const cached = JSON.parse(readFileSync(cachePath(runId), 'utf8'))

    if (cached.key === key) return cached.value
  } catch {
    /* no cache yet, or unreadable — recompute */
  }

  const cursor = run('node', [join(scriptDir, 'next-phase.mjs'), planPath, '--json'])

  let verdict = null

  try {
    verdict = JSON.parse(cursor.out.trim().split('\n').pop())
  } catch {
    verdict = null
  }

  const value = {
    verdict,
    // goal-check answers "is this plan finished" with one exit code. It is the only signal that can
    // end a run successfully, and every input it reads is a proxy.
    goalDone: run('node', [join(scriptDir, 'goal-check.mjs'), planPath]).ok,
    // --strict exits 2 specifically for "this plan cannot be trusted to tell you when a step failed".
    // Distinct from exit 1, which merely means a step failed.
    unfalsifiable: run('node', [join(scriptDir, 'verify-plan.mjs'), planPath, '--strict']).code === 2
  }

  try {
    writeFileSync(cachePath(runId), `${JSON.stringify({ key, value }, null, 2)}\n`)
  } catch {
    /* the cache is an optimisation, not a dependency */
  }

  return value
}

// ── The decision ───────────────────────────────────────────────────────────────
//
// TWO EVALUATIONS, NOT ONE ORDERED LIST.
//
// A single list with `tree red -> release` above the halt conditions silently abandons runs: a run
// that is red AND stuck — or red and plan-drifted, or red and preflight-failed — releases every turn,
// forever. The repair loop eventually steps aside, the tree stays red, the driver keeps releasing, the
// pointer stays active, and NO HALT REPORT IS EVER WRITTEN. You come back to a run that looks like it
// just stopped, with nothing saying why.
//
// It also makes the termination property vacuous: releases do not increment `iteration`, so a
// perpetually-red run burns zero budget and exhaustion is unreachable.
//
// So: HALT CHECKS run unconditionally, with tree state irrelevant. Only if none fire does the DRIVE
// CHECK look at whether the tree is red.
export const decide = (state, { payload = {}, signals = null, treeGreen = true, now = Date.now() } = {}) => {
  // ── FAST PATH ────────────────────────────────────────────────────────────────
  // The overwhelmingly common case: every ordinary turn has no active run. It must cost as close to
  // nothing as possible, because it runs on every Stop forever.
  if (!state) return { action: 'release', why: 'no active run' }
  if (payload.stop_hook_active === true) return { action: 'release', why: 'stop hook already active' }

  const budget = { ...DEFAULT_BUDGET, ...(state.budget ?? {}) }

  // ── HALT CHECKS — unconditional ──────────────────────────────────────────────
  const haltIf = (condition, reason) => (condition ? { action: 'halt', why: reason } : null)

  const startedAt = Date.parse(state.startedAt ?? 0)
  const beatAt = Date.parse(state.lastBeatAt ?? 0)

  const halts = [
    haltIf(state.iteration >= budget.iterations, `iteration budget spent (${budget.iterations}) — resume in a fresh session`),
    haltIf(Number.isFinite(startedAt) && now - startedAt > budget.runMs, 'run wall-clock budget spent'),
    haltIf(Number.isFinite(beatAt) && now - beatAt > budget.iterationMs, 'iteration wall-clock budget spent'),
    haltIf(signals?.verdict?.blockedBecause === 'plan-changed', 'plan changed mid-run'),
    haltIf(signals?.unfalsifiable === true, 'plan is unfalsifiable — its checks cannot fail'),
    haltIf(state.phaseIteration >= PHASE_STUCK_AT, `phase stuck: ${PHASE_STUCK_AT} iterations with no new step passing`),
    haltIf(state.redIterations >= RED_CEILING, `tree red for ${RED_CEILING} iterations — the repair loop did not converge`),
    haltIf(
      signals?.verdict?.blockedBecause === 'needs-human' || signals?.verdict?.blockedBecause === 'low-confidence',
      `${signals?.verdict?.blockedBecause}: ${signals?.verdict?.needsHuman ?? 'a phase cannot be proved'}`
    ),
    haltIf(
      !state.planPath && (state.planlessIterations ?? 0) >= PLANLESS_CEILING,
      `no plan bound after ${PLANLESS_CEILING} turns — the loop cannot drive work it cannot measure. ` +
        'Bind one with `run-state.mjs plan <path>`, or this is not Large-tier work.'
    ),
    haltIf(signals?.goalDone === true, 'done')
  ]

  const halted = halts.find(Boolean)

  if (halted) return { ...halted, success: halted.why === 'done' }

  // ── DRIVE CHECK — only reached when no halt fired ────────────────────────────
  if (state.paused) return { action: 'release', why: 'run paused by the user' }

  // The repair loop owns a red tree. Standing down here is correct whether or not an earlier hook's
  // block short-circuits later ones — hook ordering is not something to design on.
  if (!treeGreen) return { action: 'release', why: 'tree red — the repair loop owns it', red: true }

  // Stand aside while the plan is being written, but count the turns — the halt check above turns that
  // patience into a bounded number rather than an indefinite one.
  if (!state.planPath) return { action: 'release', why: 'no plan bound yet — planning in progress', planless: true }

  return { action: 'drive', why: 'next phase', next: signals?.verdict?.next ?? null }
}

// ── The halt report ────────────────────────────────────────────────────────────
//
// A halt must not brick the next run. Staging without committing means a run halting mid-phase leaves
// a dirty tree, which preflight's clean-tree check then refuses to start on — so ONE BAD HALT WOULD
// BLOCK EVERY FUTURE RUN until someone cleaned up by hand. The report therefore carries a diff summary
// against `baseSha` and two explicit paths, resume or abandon, with the exact commands for each.
export const haltReport = (state, reason, sessionId = null) => {
  const base = state.baseSha ?? null
  const diff = base ? run('git', ['diff', '--stat', `${base}..HEAD`]) : { ok: false, out: '' }
  const working = run('git', ['status', '--porcelain', '--untracked-files=no'])

  return [
    `# Run halted — ${reason}`,
    '',
    `**Run:** \`${state.runId}\``,
    `**Objective:** ${state.objective ?? '(none recorded)'}`,
    `**Started:** ${state.startedAt ?? '?'}`,
    `**Iterations:** ${state.iteration ?? 0}`,
    `**Base commit:** \`${base ?? '(not recorded)'}\``,
    '',
    '## What changed',
    '',
    '```',
    (diff.out || '(no committed changes)').trim(),
    '```',
    '',
    '### Uncommitted, in the working tree',
    '',
    '```',
    (working.out || '(clean)').trim(),
    '```',
    '',
    '## Two ways out',
    '',
    'This run left the working tree as it is. It is NOT committed and NOT reverted — the loop stages,',
    'you decide. Preflight refuses to start a new run on a dirty tree, so one of these has to happen',
    'before the next `/build`.',
    '',
    '**Resume this work** — keep the changes and continue:',
    '',
    '```bash',
    'npm run verify           # see what state it is actually in',
    `/build --resume          # picks up from phase ${state.phaseCursor?.phase ?? '?'}`,
    '```',
    '',
    '**Abandon this work** — discard everything the run touched:',
    '',
    '```bash',
    'git diff                 # READ THIS FIRST — the run may have made changes worth keeping',
    `git stash push -m "abandoned run ${state.runId ?? ''}"`,
    '```',
    '',
    '`git stash`, not `git checkout -- .` — a stash is recoverable, and `guard-destructive` blocks the',
    'destructive forms anyway.',
    '',
    '## Attempts',
    '',
    describeAttempts(sessionId) || '  (none recorded)',
    ''
  ].join('\n')
}

// ── The block reason — this is the context the next iteration gets ─────────────
//
// Not a complaint. The reason IS the next action, plus what has already been tried, so the model can
// read its own failed hypotheses instead of reproducing them. That is the difference between the loop
// as a brake and the loop as a loop.
const driveReason = (state, signals, sessionId = null) => {
  const next = signals?.verdict?.next
  const attempts = describeAttempts(sessionId)

  return [
    `TASK LOOP — iteration ${(state.iteration ?? 0) + 1} of ${(state.budget ?? DEFAULT_BUDGET).iterations}.`,
    '',
    `Objective: ${state.objective ?? '(none recorded)'}`,
    state.planPath ? `Plan: ${state.planPath}` : '',
    '',
    next
      ? `NEXT — phase ${next.phase}: ${next.title} (${next.passed}/${next.total} steps passing).`
      : 'NEXT — no incomplete phase reported; re-read the plan and the cursor.',
    '',
    'Continue that phase now. Follow the `implement-plan` skill: implement, gate with',
    '`npm run verify:fast`, then append to `implementation-log.md`. Do not start a later phase.',
    attempts ? `\nAlready tried in this run — do not repeat these:\n${attempts}` : '',
    '',
    'Stop and report instead of continuing if: the plan is wrong, a Roblox API behaves differently from',
    'what it assumed, or you have failed the same gate three times.'
  ]
    .filter(line => line !== '')
    .join('\n')
}

const block = reason => {
  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`)
  process.exit(0)
}

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

// ── main ───────────────────────────────────────────────────────────────────────

const main = async () => {
  // --decide exists so the suite can exercise the decision from a fabricated state without a hook
  // payload, a git tree, or a plan. The decision is the part that must be right; the plumbing around
  // it is exercised separately.
  if (process.argv.includes('--decide')) {
    const statePath = process.argv[process.argv.indexOf('--decide') + 1]
    const payloadIndex = process.argv.indexOf('--payload')
    const state = JSON.parse(readFileSync(statePath, 'utf8'))
    const payload = payloadIndex === -1 ? {} : JSON.parse(readFileSync(process.argv[payloadIndex + 1], 'utf8'))
    const signalsIndex = process.argv.indexOf('--signals')
    const signals = signalsIndex === -1 ? null : JSON.parse(readFileSync(process.argv[signalsIndex + 1], 'utf8'))
    const treeGreen = !process.argv.includes('--red')
    const nowIndex = process.argv.indexOf('--now')
    const now = nowIndex === -1 ? Date.now() : Number(process.argv[nowIndex + 1])

    console.log(JSON.stringify(decide(state.runId ? state : null, { payload, signals, treeGreen, now })))

    return 0
  }

  if (process.argv.includes('--status')) {
    const state = activeRun(process.env.CLAUDE_SESSION_ID)

    // `.hooks[name].last`, matching what beat() actually writes. A reader that invents its own field
    // names reports `never` forever, including while the driver is firing on every turn.
    const last = (() => {
      try {
        return JSON.parse(readFileSync('.claude/.hook-heartbeat.json', 'utf8')).hooks?.['task-driver'] ?? null
      } catch {
        return null
      }
    })()

    // SOMETHING MUST READ THE ABSENCE. A driver that never fires never beats, and nothing notices —
    // the loop simply does not start and looks like nothing happened.
    console.log(`  driver last beat: ${last?.last ?? 'never'}${last ? ` (fired ${last.fired}×)` : ''}`)
    console.log(state ? `  active run: ${state.runId} — iteration ${state.iteration}` : '  no active run')

    return 0
  }

  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    // An unparseable payload must RELEASE. Blocking on it would trap every turn in the repo behind a
    // bug in the driver's own input handling.
    return 0
  }

  beat('task-driver', payload)

  const state = activeRun(payload.session_id ?? process.env.CLAUDE_SESSION_ID)

  // Fast path, before any expensive signal is computed.
  const fast = decide(state, { payload })

  if (fast.action === 'release') return 0

  const treeGreen = run('npm', ['run', '--silent', 'verify:fast']).ok
  const signals = state.planPath ? cachedSignals(state.runId, state.planPath, hashPlan(state.planPath)) : null
  const verdict = decide(state, { payload, signals, treeGreen })

  if (verdict.action === 'halt') {
    const report = haltReport(state, verdict.why, payload.session_id)

    halt(state.runId, verdict.why, report)

    // Loud, not just written. A report nobody reads is a loop that stopped an hour ago without telling
    // anyone — so the halt also blocks once, and the model's next act is to tell the user.
    block(
      `TASK LOOP HALTED — ${verdict.why}\n\n` +
        `Report: ${join(RUN_ROOT, state.runId, 'halt-report.md')}\n\n` +
        `The run is over and will not restart. Read the report and tell the user what happened, what ` +
        `changed, and which of the two paths it lists you recommend. Do not start another run.`
    )
  }

  if (verdict.action === 'release') {
    // A red release still costs budget, or a perpetually-red run never terminates. The same is true of
    // a planless one: patience has to be counted or it is indistinguishable from a stall.
    if (verdict.red) update(state.runId, { redIterations: (state.redIterations ?? 0) + 1 })
    if (verdict.planless) update(state.runId, { planlessIterations: (state.planlessIterations ?? 0) + 1 })

    return 0
  }

  const advanced = signals?.verdict?.next?.passed ?? -1
  const samePhase = state.phaseCursor?.phase === signals?.verdict?.next?.phase
  const noProgress = samePhase && state.phaseCursor?.passed === advanced

  update(state.runId, {
    iteration: (state.iteration ?? 0) + 1,
    // Progress, not attempts. A phase that produced a new step PASS is converging, and resetting the
    // counter is what stops the driver punishing a run that is working.
    phaseIteration: noProgress ? (state.phaseIteration ?? 0) + 1 : 0,
    redIterations: 0,
    phaseCursor: signals?.verdict?.next ?? null
  })

  block(driveReason(state, signals, payload.session_id))

  return 0
}

if (process.argv[1]?.endsWith('task-driver.mjs')) process.exit(await main())
