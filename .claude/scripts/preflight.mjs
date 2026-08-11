#!/usr/bin/env node
// Entry conditions for a task-loop run, checked BEFORE an iteration is spent.
//
//   node .claude/scripts/preflight.mjs [--studio] [--json]
//   node .claude/scripts/preflight.mjs --self-test
//
// ── WHY THIS IS AN ENTRY CONDITION AND NOT A FIELD IN A REPORT ─────────────────
//
// The playtester's template carries `Studio reachable: yes | no` as a line to fill in. A human reading
// "no" stops. A loop reading "no" carries on and spends its entire budget verifying code it never
// ran — every check passes, and none of it means anything.
//
// For this repo the specific trap is Rojo. If `rojo serve` is not running, files on disk are simply
// not in Studio: an agent can implement eight phases, screenshot the place, and report success while
// looking at code from an hour ago. That is not a subtle failure, but it is an INVISIBLE one, because
// everything on the filesystem side looks exactly right.
//
// THIS IS AN ENTRY CHECK, RUN BY HAND. `build/SKILL.md` runs it before the first phase and the
// playtester runs it before trusting anything it sees in Studio. It answers "is it healthy right now",
// a question with no memory.
//
// It is deliberately NOT a halt condition. The driver once carried a `preflightFailures >= 2` halt, but
// nothing ever wrote that field, so the halt could not fire — a guard that reads as protection and is
// not. Rather than add a third `verify:fast` per turn to feed it, the halt was removed and this stayed
// exactly what it already was: the check you run before starting.

import { execFileSync } from 'node:child_process'

// Rojo's default serve port. Its HTTP API answers on /api/rojo with server metadata, so a response of
// any kind proves a live server rather than merely an open socket.
const ROJO_URL = 'http://localhost:34872/api/rojo'
const TIMEOUT_MS = 3000

const reachable = async url => {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) })

    return response.ok
  } catch {
    return false
  }
}

const runs = (file, args) => {
  try {
    execFileSync(file, args, { stdio: 'pipe', encoding: 'utf8' })

    return true
  } catch {
    return false
  }
}

// ── The checks ─────────────────────────────────────────────────────────────────
//
// Each returns { ok, reason } where `reason` is the HALT REASON verbatim, so the driver never has to
// invent wording for a condition it did not evaluate.

export const toolchainCheck = () =>
  runs('node', ['.claude/scripts/check-toolchain.mjs', '--quiet'])
    ? { name: 'toolchain', ok: true }
    : { name: 'toolchain', ok: false, reason: 'toolchain incomplete — run `npm run check:toolchain`' }

// REFUSE, DO NOT REPAIR. A run that begins by fixing something it did not cause can no longer say
// which part of its own diff is its work — and "what did this run change" is the first question asked
// at halt time.
export const treeGreenCheck = () =>
  runs('npm', ['run', '--silent', 'verify:fast'])
    ? { name: 'tree-green', ok: true }
    : { name: 'tree-green', ok: false, reason: 'started on a red tree' }

// Untracked files are ignored deliberately: scratch notes, editor droppings and generated artifacts
// are not changes to the project, and refusing to start because someone left a TODO.md around would
// make this check the first thing anyone disables.
export const cleanTreeCheck = () => {
  try {
    const porcelain = execFileSync('git', ['status', '--porcelain', '--untracked-files=no'], {
      encoding: 'utf8',
      stdio: 'pipe'
    }).trim()

    return porcelain
      ? { name: 'clean-tree', ok: false, reason: 'dirty tree — cannot attribute the diff' }
      : { name: 'clean-tree', ok: true }
  } catch {
    // Not a git repo, or git unavailable. Attribution is impossible either way, but that is a
    // property of the environment rather than a failing precondition, so it does not block.
    return { name: 'clean-tree', ok: true, note: 'not a git working tree' }
  }
}

export const rojoCheck = async () =>
  (await reachable(ROJO_URL))
    ? { name: 'rojo-serve', ok: true }
    : {
        name: 'rojo-serve',
        ok: false,
        reason: 'rojo serve is not running — code on disk is NOT in Studio, so nothing observed there is evidence'
      }

export const preflight = async ({ needsStudio = false } = {}) => {
  const checks = [toolchainCheck(), treeGreenCheck(), cleanTreeCheck()]

  // CONDITIONAL, deliberately. A phase that touches no runtime behaviour must not be blocked by a
  // Rojo server nobody asked to be running — that would make every run require a second terminal.
  if (needsStudio) checks.push(await rojoCheck())

  const failed = checks.filter(check => !check.ok)

  return { ok: failed.length === 0, checks, failed, reason: failed[0]?.reason ?? null }
}

// ── --self-test ────────────────────────────────────────────────────────────────
//
// Pins the DECISION logic, not the network. A self-test that needs a live Rojo server fails on a
// train and gets deleted; one that pins how results are combined keeps working and is the part that
// has actually been wrong.
const selfTest = async () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const combine = checks => {
    const failed = checks.filter(entry => !entry.ok)

    return { ok: failed.length === 0, reason: failed[0]?.reason ?? null }
  }

  check('all green passes', combine([{ ok: true }, { ok: true }]), { ok: true, reason: null })
  check(
    'the FIRST failure names the halt reason',
    combine([{ ok: true }, { ok: false, reason: 'started on a red tree' }, { ok: false, reason: 'dirty tree' }]),
    { ok: false, reason: 'started on a red tree' }
  )
  check('a single failure fails the set', combine([{ ok: false, reason: 'toolchain incomplete' }]), {
    ok: false,
    reason: 'toolchain incomplete'
  })
  check('an empty set is vacuously ok', combine([]), { ok: true, reason: null })

  // The Rojo check is CONDITIONAL. Asserted directly against the real function so a change to the
  // default can never slip through: a preflight that silently started demanding a Rojo server would
  // block every non-Studio run in the repo.
  const withoutStudio = await preflight({ needsStudio: false })

  check('rojo-serve is not checked unless the work needs Studio', withoutStudio.checks.some(entry => entry.name === 'rojo-serve'), false)

  const names = (await preflight({ needsStudio: true })).checks.map(entry => entry.name)

  check('rojo-serve IS checked when the work needs Studio', names.includes('rojo-serve'), true)

  // The reason string is what the halt report prints, so it must say what to DO, not merely what is
  // wrong. "rojo serve is not running" sends someone to a terminal; "studio unreachable" does not.
  const rojo = await rojoCheck()

  check('the rojo reason names the command when it fails', rojo.ok || rojo.reason.includes('rojo serve'), true)

  console.log(failures ? `  FAIL  preflight: ${ran - failures}/${ran} cases` : `  PASS  preflight: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('preflight.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(await selfTest())

  const result = await preflight({ needsStudio: process.argv.includes('--studio') })

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(result))
  } else {
    for (const check of result.checks) {
      console.log(`  ${check.ok ? 'ok  ' : 'FAIL'}  ${check.name}${check.reason ? ` — ${check.reason}` : ''}`)
    }

    console.log(result.ok ? '\n  preflight passed' : `\n  preflight FAILED — ${result.reason}`)
  }

  process.exit(result.ok ? 0 : 1)
}
