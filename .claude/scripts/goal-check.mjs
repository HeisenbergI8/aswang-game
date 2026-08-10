#!/usr/bin/env node
// Answers ONE question with an exit code: is this plan finished?
//
//   npm run goal <plan-dir-or-file>          0 = done, 1 = not done, 2 = unusable
//   npm run goal <plan> --json               machine-readable
//   node .claude/scripts/goal-check.mjs --self-test
//
// "Done" otherwise lives in a person's head. Every other check answers a narrower question — is the
// tree green, did this step's token appear, is the analyze baseline unchanged — and someone assembles
// those into a judgement. That assembly is the thing a loop cannot do, and it is the reason a harness
// stops and waits after every phase.
//
// ── THE PART THE SOURCE SYSTEM COULD NOT DO, AND THIS ONE CAN ──────────────────
//
// The harness this is adapted from carries a permanent `????  ui  no screenshot check exists — a
// person still has to look`. It had no way to observe the running product, so `DONE` always meant
// "the machine is satisfied" and never "the screen is right". On 2026-08-07 a stats strip in that repo
// passed the full gate, 27 unit tests and a measured viewport check while every card label wrapped
// onto two lines.
//
// THIS repo has Roblox Studio MCP, so an agent can press Play, read the console, and capture the
// screen. That makes runtime evidence a FILE, and a file is checkable. The `artifact` check below
// therefore requires that `verification.md` cite at least one file that exists in the plan's
// `artifacts/` directory — you cannot satisfy it with prose.
//
// It still cannot judge whether the screenshot shows the right thing. A person looks at the artifact;
// the machine only refuses to accept a claim with nothing behind it.

import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

// ── NO SHELL. EVER. ────────────────────────────────────────────────────────────
//
// Plan directories are named by the ARCHITECT — a model — so a model-chosen filename reaches this
// code. A plan file named `$(touch marker)-plan.md` would create `marker` if the name were spliced
// into a shell string; `JSON.stringify` does NOT prevent that, because command substitution expands
// inside double quotes. The driver calls this script unattended, which is what turns an odd filename
// into arbitrary code execution.
//
// `execFileSync(file, args)` invokes no shell, so `$()`, backticks, `;` and `|` are inert literal
// characters in an argv element. Nothing has to recognise an attack, so nothing can fail to.
const passes = (file, args) => {
  try {
    execFileSync(file, args, { stdio: 'pipe', encoding: 'utf8' })

    return true
  } catch {
    return false
  }
}

export const resolvePlanFile = target => {
  if (!existsSync(target)) return null
  if (statSync(target).isFile()) return target

  const found = readdirSync(target).find(name => name.endsWith('-plan.md'))

  return found ? join(target, found) : null
}

// ── The artifact check ─────────────────────────────────────────────────────────
//
// Two conditions, and the second is the one that matters. A directory containing files proves someone
// ran something; a verification report that NAMES one of those files proves the report is about them.
// Without the citation, an agent can drop a stale screenshot in the directory and write anything.
export const artifactCheck = planDir => {
  const artifactsDir = join(planDir, 'artifacts')
  const verification = join(planDir, 'verification.md')

  if (!existsSync(artifactsDir)) return { ok: false, detail: 'artifacts/ absent' }

  const files = readdirSync(artifactsDir).filter(name => !name.startsWith('.'))

  if (files.length === 0) return { ok: false, detail: 'artifacts/ is empty' }

  let report = ''

  try {
    report = readFileSync(verification, 'utf8')
  } catch {
    return { ok: false, detail: `${files.length} artifact(s), but no verification.md cites them` }
  }

  const cited = files.filter(name => report.includes(name))

  return cited.length > 0
    ? { ok: true, detail: `${cited.length} of ${files.length} artifact(s) cited` }
    : { ok: false, detail: `${files.length} artifact(s) present, none cited in verification.md` }
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

  // The verdict combiner: DONE requires every check, and `next` names the FIRST unmet one so the
  // report says what to do rather than how far along it is.
  const verdict = checks => ({
    done: checks.every(entry => entry.ok),
    next: checks.find(entry => !entry.ok)?.key ?? null
  })

  check('every check green is done', verdict([{ key: 'plan', ok: true }, { key: 'tree', ok: true }]), {
    done: true,
    next: null
  })
  check(
    'the first unmet check is named',
    verdict([{ key: 'plan', ok: true }, { key: 'tree', ok: false }, { key: 'artifact', ok: false }]),
    { done: false, next: 'tree' }
  )

  // The property that makes the artifact check worth having: presence alone is not enough.
  const cite = (files, report) => files.filter(name => report.includes(name)).length > 0

  check('an artifact nobody cited does not count', cite(['play-1.png'], 'The round worked fine.'), false)
  check('a cited artifact counts', cite(['play-1.png'], 'See artifacts/play-1.png at 1080p.'), true)
  check('one citation out of several is enough', cite(['a.png', 'b.log'], 'output in b.log'), true)

  console.log(failures ? `  FAIL  goal-check: ${ran - failures}/${ran}` : `  PASS  goal-check: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('goal-check.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const target = process.argv[2]
  const asJson = process.argv.includes('--json')

  if (!target) {
    console.error('usage: goal-check.mjs <plan-dir-or-file> [--json]')
    process.exit(2)
  }

  const planFile = resolvePlanFile(target)

  if (!planFile) {
    console.error(`FAIL  no plan document found at ${target}`)
    process.exit(2)
  }

  const planDir = planFile.slice(0, planFile.lastIndexOf('/'))

  // ── 1. The plan's own steps ──────────────────────────────────────────────────
  //
  // verify-plan.mjs is the authority; parse its summary rather than re-implementing it. Its
  // check-quality line matters as much as its pass count: a plan whose checks cannot fail is not
  // evidence of completion.
  let planOut = ''

  try {
    planOut = execFileSync('node', ['.claude/scripts/verify-plan.mjs', planFile], { stdio: 'pipe', encoding: 'utf8' })
  } catch (error) {
    planOut = `${error.stdout ?? ''}${error.stderr ?? ''}`
  }

  const summary = planOut.match(/(\d+) passed, (\d+) failed, (\d+) unverifiable/)
  const quality = planOut.match(/checks: (\d+) discriminating/)

  const planPass = summary ? Number(summary[1]) : 0
  const planTotal = summary ? Number(summary[1]) + Number(summary[2]) + Number(summary[3]) : 0
  const discriminating = quality ? Number(quality[1]) : 0
  const planDone = summary ? Number(summary[2]) === 0 : false

  // ── 2..5 ─────────────────────────────────────────────────────────────────────
  const treeGreen = passes('npm', ['run', '--silent', 'verify'])
  const artifact = artifactCheck(planDir)

  const logFile = join(planDir, 'implementation-log.md')
  const logged = existsSync(logFile) && readFileSync(logFile, 'utf8').includes('Phase')

  const checks = [
    { key: 'plan', ok: planDone, detail: `${planPass}/${planTotal} steps` },
    { key: 'tree', ok: treeGreen, detail: 'npm run verify' },
    { key: 'artifact', ok: artifact.ok, detail: artifact.detail },
    { key: 'log', ok: logged, detail: 'implementation-log.md' }
  ]

  const done = checks.every(check => check.ok)
  const next = checks.find(check => !check.ok)

  // A weak check set does not block DONE — the steps did pass — but it must be stated, because
  // "15 of 16 passed" reads very differently when only 2 of them could have failed. Compared against
  // steps that HAVE a check, not against every step: a step honestly marked unverifiable is not a
  // weak check.
  const checked = planTotal - (summary ? Number(summary[3]) : 0)
  const weak = checked > 0 && discriminating <= checked / 3

  if (asJson) {
    console.log(
      JSON.stringify({
        done,
        progress: checks.filter(check => check.ok).length / checks.length,
        next: next ? `${next.key}: ${next.detail}` : null,
        planPass,
        planTotal,
        discriminating,
        weakChecks: weak
      })
    )
    process.exit(done ? 0 : 1)
  }

  for (const check of checks) {
    console.log(`  ${check.ok ? 'PASS ' : 'TODO '} ${check.key.padEnd(10)} ${check.detail}`)
  }

  console.log('  ????  judgement  an artifact exists and is cited — whether it shows the RIGHT thing needs a person')

  if (weak) {
    console.log(`\nWARN  only ${discriminating} of ${checked} plan checks can actually fail.`)
    console.log('      Treat "steps passed" as weak evidence here.')
  }

  console.log(done ? '\nDONE' : `\nNOT DONE — next: ${next.key} (${next.detail})`)
  process.exit(done ? 0 : 1)
}
