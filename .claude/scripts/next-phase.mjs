#!/usr/bin/env node
// Where is this run up to, and what is next?
//
//   node .claude/scripts/next-phase.mjs <plan> [--json]
//
// VERIFY-PLAN IS PRIMARY. `implementation-log.md` is narrative only.
//
// Reading the implementation log to decide phase completion is tempting and wrong: that log is prose
// written by the model, and trusting it to decide whether the loop keeps going is exactly what
// `claim-check.mjs` exists to prevent, reintroduced at the most load-bearing joint in the system.
// Exit codes decide; prose describes.
//
// UNIT RECONCILIATION. The cursor thinks in phases; the evidence is per step. Plans number steps
// `#### Step N.M`, so the phase is the prefix. A phase is `done` when every step PASSes, `partial`
// when some do, `pending` when none do — and that distinction is exactly what a phase-level signal
// cannot give you.

import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { activeRun, hashPlan } from './run-state.mjs'

// Resolve the sibling script against THIS file, not the cwd. Invoked from anywhere but the repo root,
// a cwd-relative path silently finds nothing and the cursor reports zero phases — which reads as
// "no plan" rather than "I could not run".
const VERIFY_PLAN = join(dirname(fileURLToPath(import.meta.url)), 'verify-plan.mjs')

const planPath = process.argv[2]
const asJson = process.argv.includes('--json')

if (!planPath) {
  console.error('usage: next-phase.mjs <plan> [--json]')
  process.exit(2)
}

// Phase titles, so the block reason can name the phase rather than number it.
const phaseTitles = () => {
  const titles = new Map()

  try {
    for (const line of readFileSync(planPath, 'utf8').split('\n')) {
      const match = line.match(/^###\s+Phase\s+(\d+)\s*:\s*(.+)$/)

      if (match) titles.set(match[1], match[2].trim())
    }
  } catch {
    /* the plan is unreadable; the caller reports that */
  }

  return titles
}

// verify-plan prints one line per step: `PASS  Step 2.1 — title  [real]`.
const stepResults = () => {
  let out = ''

  try {
    out = execFileSync('node', [VERIFY_PLAN, planPath], { encoding: 'utf8', stdio: 'pipe' })
  } catch (error) {
    out = `${error.stdout ?? ''}${error.stderr ?? ''}`
  }

  const steps = []

  for (const line of out.split('\n')) {
    const match = line.match(/^(PASS|FAIL|SKIP|BLOCK)\s+Step\s+(\d+)\.(\d+)/)

    if (!match) continue

    // Absent (an older plan run, a format change) is treated as `none` — unknown confidence must not
    // read as discriminating.
    const kind = line.match(/\[(real|self|exists|none|shared)\]\s*$/)?.[1] ?? 'none'

    steps.push({ result: match[1], phase: match[2], step: `${match[2]}.${match[3]}`, shape: kind })
  }

  // The classifier's own tally, parsed rather than recomputed — one definition of "discriminating",
  // in one place.
  const tally = out.match(/checks: (\d+) discriminating, (\d+) file-exists, (\d+) self-satisfying/)

  return {
    steps,
    quality: tally
      ? { discriminating: Number(tally[1]), weak: Number(tally[2]) + Number(tally[3]) }
      : { discriminating: 0, weak: 0 }
  }
}

// ── PLAN DRIFT ─────────────────────────────────────────────────────────────────
//
// The run records the plan's hash at start. If the document has changed since, every phase number,
// step id and check below describes a plan that is no longer the one on disk — the cursor is a map of
// somewhere else. Renumbering one phase is enough to make "continue from phase 4" mean a different
// thing than it did when the run began.
//
// This halts rather than warns, and deliberately does not try to work out whether the edit was
// harmless. Distinguishing a typo fix from a resequenced phase is exactly the judgement a loop should
// not make unsupervised; a human re-reading the plan costs a minute.
const drift = (() => {
  const run = activeRun(process.env.CLAUDE_SESSION_ID)

  if (!run?.planHash || !run.planPath) return null

  const current = hashPlan(run.planPath)

  return current && current !== run.planHash ? { was: run.planHash, now: current } : null
})()

const { steps, quality } = stepResults()
const titles = phaseTitles()

// ── THE QUIET FAILURE ──────────────────────────────────────────────────────────
//
// `needs-human` is the LOUD failure: a phase that cannot be proved, halting visibly. The quiet one is
// a plan that is 100% verifiable and proves almost nothing — every step PASSes on a grep for a token
// it typed, so the cursor advances over work nobody checked. A false PASS is strictly worse than a
// halt: a halt is loud and wrong; a false PASS is silent, wrong, AND moves the loop forward on it.
//
// PER PHASE, NOT PER PLAN. A plan-wide ratio is wrong in both directions, and the second is the one
// that ships: a strong plan carrying one all-grep phase averages out above the threshold, and the
// cursor walks straight through the phase nobody checked.
const checkable = quality.discriminating + quality.weak
const isWeak = step => step.shape !== 'real'

const byPhase = new Map()

for (const step of steps) {
  const bucket = byPhase.get(step.phase) ?? []

  bucket.push(step)
  byPhase.set(step.phase, bucket)
}

const phases = [...byPhase.entries()]
  .sort((a, b) => Number(a[0]) - Number(b[0]))
  .map(([phase, list]) => {
    const passed = list.filter(step => step.result === 'PASS').length

    // A SKIP cannot prove completion — the step is honestly unverifiable. A phase containing one is
    // `needs-human` rather than done. Blocked commands count the same way: an unrun check is not a
    // passed one.
    const unprovable = list.some(step => step.result === 'SKIP' || step.result === 'BLOCK')

    // Only checks that RAN count toward confidence. A SKIP already forces needs-human, and letting it
    // also count as weak would double-penalise the same step.
    const executed = list.filter(step => step.result === 'PASS' || step.result === 'FAIL')
    const weak = executed.filter(isWeak).length
    const strong = executed.length - weak
    const lowConfidence = executed.length > 0 && weak > executed.length * 0.66

    let status = 'pending'

    if (passed === list.length) status = lowConfidence ? 'low-confidence' : 'done'
    else if (unprovable) status = 'needs-human'
    else if (passed > 0) status = 'partial'

    return { phase, title: titles.get(phase) ?? '', total: list.length, passed, status, strong, weak }
  })

// `low-confidence` is treated exactly like `needs-human` by the driver — halt once, sign-off path,
// same conditions. It is a separate status only so the report says which of the two it is.
const blocked = phases.find(phase => phase.status === 'needs-human' || phase.status === 'low-confidence')
const next = phases.find(phase => phase.status !== 'done')
const allDone = phases.length > 0 && phases.every(phase => phase.status === 'done')

const verdict = {
  planPath,
  phases,
  allDone: drift ? false : allDone,
  needsHuman: drift ? 'plan changed mid-run' : blocked ? `phase ${blocked.phase}: ${blocked.title}` : null,
  blockedBecause: drift ? 'plan-changed' : (blocked?.status ?? null),
  planDrift: drift,
  quality,
  next: next ? { phase: next.phase, title: next.title, passed: next.passed, total: next.total } : null
}

if (asJson) {
  console.log(JSON.stringify(verdict))
  process.exit(verdict.allDone ? 0 : 1)
}

// Printed before the phase table, because the table below it is the thing that cannot be trusted.
if (drift) {
  console.log(
    `PLAN CHANGED MID-RUN — the document was edited after this run started.\n` +
      `  recorded ${drift.was.slice(0, 12)} · on disk ${drift.now.slice(0, 12)}\n` +
      `  Every phase and step id below refers to the plan as it was. Re-read it, then start a new run.\n`
  )
}

for (const phase of phases) {
  console.log(`  ${phase.status.padEnd(11)} phase ${phase.phase}  ${phase.passed}/${phase.total}  ${phase.title}`)
}

if (blocked) {
  // The two statuses want different remedies, and offering the wrong one first is how a run gets waved
  // through. `needs-human` is a statement about the WORK — a person must look. `low-confidence` is a
  // statement about the PLAN — the checks are too weak to prove anything, so strengthen them first.
  console.log(
    blocked.status === 'low-confidence'
      ? `\nLOW CONFIDENCE — ${verdict.needsHuman} passes, but only ${blocked.strong} of ` +
          `${blocked.strong + blocked.weak} checks in THIS PHASE can fail ` +
          `(${quality.discriminating}/${checkable} plan-wide). Passing proves little.\n` +
          `  FIRST: strengthen the checks — a command that runs something, not a grep for a token the step types.\n` +
          `  ONLY THEN: approve, which records that you accept this phase as unproven.`
      : `\nNEEDS HUMAN — ${verdict.needsHuman} has a step no command can prove.\n` +
          `  Look at the step, then approve it by id with a reason.`
  )
} else if (allDone) {
  console.log('\nALL PHASES DONE')
} else if (next) {
  console.log(`\nNEXT — phase ${next.phase}: ${next.title} (${next.passed}/${next.total} steps passing)`)
} else {
  console.log('\nNo phases found — is this a plan document?')
}

// verdict.allDone, not allDone — drift forces a non-zero exit, and the driver reads the exit code.
process.exit(verdict.allDone ? 0 : 1)
