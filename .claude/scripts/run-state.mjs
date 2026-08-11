#!/usr/bin/env node
// Run state for the task loop — the thing that makes iteration N+1 differ from N.
//
// Without it every turn starts blind: the activity ledger keys on `prompt_id`, each iteration is a
// new one, so nothing an iteration learns survives the turn ending. A loop built on that repeats
// itself verbatim. State therefore lives in files, never in context.
//
//   .claude/.run/current            pointer: { runId, sessionId, lastBeatAt }
//   .claude/.run/<id>/state.json    the run record
//
// Nothing here blocks anything. It is read and written by hooks that decide.

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export const RUN_ROOT = '.claude/.run'
const POINTER = join(RUN_ROOT, 'current')

// A session that dies mid-run leaves the pointer behind. Without expiry, "no active run → release"
// quietly stops being true and every later turn is driven by a dead objective — which looks exactly
// like the loop working.
const STALE_MS = 2 * 60 * 60 * 1000

const readJson = path => {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

const writeJson = (path, value) => {
  mkdirSync(join(path, '..'), { recursive: true })
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`)
}

export const hashPlan = planPath => {
  try {
    return createHash('sha1').update(readFileSync(planPath, 'utf8')).digest('hex').slice(0, 12)
  } catch {
    return null
  }
}

const headSha = () => {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8', stdio: 'pipe' }).trim().slice(0, 12)
  } catch {
    return null
  }
}

export const statePath = runId => join(RUN_ROOT, runId, 'state.json')

// ── Pointer ────────────────────────────────────────────────────────────────────

export const readPointer = () => readJson(POINTER)

export const clearPointer = () => {
  try {
    rmSync(POINTER, { force: true })
  } catch {
    /* already gone */
  }
}

// The ONE function every caller should use. Returns null — meaning "no run, release" — for all four
// reasons a pointer should be ignored, so no caller has to remember the list.
//
// `sessionId` matters: two Claude Code windows on this repo would both read this pointer and both
// drive. Ownership by convention is not ownership.
export const activeRun = sessionId => {
  const pointer = readPointer()

  if (!pointer?.runId) return null
  if (sessionId && pointer.sessionId && pointer.sessionId !== sessionId) return null

  const age = Date.now() - Date.parse(pointer.lastBeatAt ?? 0)

  if (!Number.isFinite(age) || age > STALE_MS) {
    clearPointer()

    return null
  }

  const state = readJson(statePath(pointer.runId))

  if (!state || state.halted) return null

  return state
}

// ── Lifecycle ──────────────────────────────────────────────────────────────────

export const init = ({ objective, milestone, planPath, sessionId, budget = {} }) => {
  const runId = `${new Date().toISOString().replace(/[:.]/g, '-')}-${milestone ?? 'run'}`

  const state = {
    runId,
    objective,
    milestone: milestone ?? null,
    planPath: planPath ?? null,

    // Without planHash, an architect amending the plan mid-run silently changes what the phase
    // cursor means. Without baseSha, "what did this run change" and "roll it back" are both
    // unanswerable at halt time — which is exactly when they are asked.
    planHash: planPath ? hashPlan(planPath) : null,
    baseSha: headSha(),

    iteration: 0,
    phaseIteration: 0,
    redIterations: 0,
    planlessIterations: 0,
    phaseCursor: null,

    startedAt: new Date().toISOString(),
    lastBeatAt: new Date().toISOString(),
    budget: { iterations: 8, runMs: 4 * 60 * 60 * 1000, iterationMs: 35 * 60 * 1000, ...budget },

    paused: false,
    halted: false,
    haltReason: null
  }

  mkdirSync(join(RUN_ROOT, runId), { recursive: true })
  writeJson(statePath(runId), state)
  writeJson(POINTER, { runId, sessionId: sessionId ?? null, lastBeatAt: state.lastBeatAt })

  return state
}

export const update = (runId, patch) => {
  const current = readJson(statePath(runId))

  if (!current) return null

  const next = { ...current, ...patch, lastBeatAt: new Date().toISOString() }

  writeJson(statePath(runId), next)

  const pointer = readPointer()

  if (pointer?.runId === runId) writeJson(POINTER, { ...pointer, lastBeatAt: next.lastBeatAt })

  return next
}

// Halting is terminal and must leave something a person can read. A report nobody reads is a loop
// that stopped an hour ago without telling anyone.
export const halt = (runId, reason, report = '') => {
  const state = update(runId, { halted: true, haltReason: reason })

  if (report) {
    try {
      writeFileSync(join(RUN_ROOT, runId, 'halt-report.md'), `${report}\n`)
    } catch {
      /* the block reason still carries the essentials */
    }
  }

  clearPointer()

  return state
}

// ── ATTEMPTS LIVE IN verify-gate.mjs, NOT HERE ─────────────────────────────────
//
// This file used to carry recordAttempt / recentAttempts / describeAttempts over
// `.claude/.run/<runId>/attempts.jsonl`. It was a complete, plausible implementation with exactly one
// problem: nothing ever called the writer. `task-driver` read it on every drive and every halt, and
// got an empty string every time — which is why the only halt report this repo has produced says
// `## Attempts` / `(none recorded)`.
//
// `verify-gate.mjs` was independently keeping the same ledger, keyed `session:agent`, and writing it
// for real. That one won. The driver imports `describeAttempts` from there.

// ── CLI ────────────────────────────────────────────────────────────────────────

if (process.argv[1]?.endsWith('run-state.mjs')) {
  const [, , command, ...rest] = process.argv

  if (command === 'status') {
    const pointer = readPointer()

    if (!pointer) {
      console.log('  no active run')
      process.exit(0)
    }

    const state = readJson(statePath(pointer.runId))
    const age = Math.round((Date.now() - Date.parse(pointer.lastBeatAt ?? 0)) / 1000)

    console.log(`  run: ${pointer.runId}`)
    console.log(`  objective: ${state?.objective ?? '(unreadable)'}`)
    console.log(`  session: ${pointer.sessionId ?? 'unowned'} · last beat ${age}s ago`)
    console.log(
      `  iteration ${state?.iteration ?? 0}/${state?.budget?.iterations ?? '?'} · phase ${state?.phaseCursor?.phase ?? '?'}`
    )
    if (state?.paused) console.log('  PAUSED — /build --resume to continue')
    if (state?.halted) console.log(`  HALTED — ${state.haltReason}`)
    process.exit(0)
  }

  if (command === 'halt') {
    const pointer = readPointer()

    if (!pointer) {
      console.log('  no active run')
      process.exit(0)
    }

    halt(pointer.runId, rest.join(' ') || 'halted by hand')
    console.log(`  halted ${pointer.runId}`)
    process.exit(0)
  }

  // A run is created by `/build` BEFORE a plan exists — the architect has not run yet, and for the
  // smaller tiers it never will. Binding the plan afterwards is what gives the cursor something to
  // read, and it stamps `planHash` at that moment so drift is measured from when the plan became the
  // contract rather than from when the run started.
  if (command === 'plan') {
    const pointer = readPointer()
    const planPath = rest[0]

    if (!pointer) {
      console.log('  no active run — start one with /build <milestone>')
      process.exit(1)
    }

    if (!planPath || !existsSync(planPath)) {
      console.log(`  no such plan: ${planPath ?? '(none given)'}`)
      process.exit(1)
    }

    update(pointer.runId, { planPath, planHash: hashPlan(planPath) })
    console.log(`  run ${pointer.runId} is now driven by ${planPath}`)
    process.exit(0)
  }

  console.log('usage: run-state.mjs <status|halt|plan <path>>')
}
