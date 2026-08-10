#!/usr/bin/env node
// PostToolUse gate on Write/Edit of a .luau file: runs the analyzer immediately after the edit.
//
// Catches the class of defect that hand-edits produce in strict Luau — a type that no longer matches,
// a dropped return, an enum field inferred as `string` — at the moment it is written rather than at
// review time.
//
// Filters on file_path in the SCRIPT rather than in the hook's `if` field, because path globs inside
// `if` are not confirmed to apply and a filter that silently does not fire is worse than no filter.
//
// Exit 2 does NOT block on PostToolUse, so this uses {"decision":"block"} to put the analyzer output in
// front of the model.
//
// ── COALESCING ─────────────────────────────────────────────────────────────────
//
// A full analyze is ~1s. Running one per edit is affordable but wasteful in two specific ways:
//
//   1. Parallel edits in one message land within a few hundred milliseconds of each other, so the
//      analyzer runs on a HALF-APPLIED change and reports errors the very next edit is about to fix —
//      then blocks on them.
//   2. Sequential edits inside one phase re-run a whole-project check that cannot have changed
//      meaningfully.
//
// Two suppressions, both of which FAIL SAFE (a skip can only defer a check, never approve a broken
// tree):
//
//   GRACE  — wait 400ms and re-read the sequence counter. If another .luau edit arrived, that edit's
//            hook has the more complete tree and will run instead. Trailing-edge debouncing.
//   WINDOW — if the last run was GREEN and less than 15s ago, skip. A red result is NEVER suppressed:
//            when the tree is broken the model is iterating on the fix and needs to know the moment it
//            goes green.
//
// THE GUARANTEE IS UNCHANGED: no phase boundary is crossed without a green analyze. `verify-gate.mjs`
// runs `verify:fast` on Stop and SubagentStop, and `implement-plan` runs it at every phase boundary.
// This gate is early warning; those are the boundary.

import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const STATE_PATH = '.claude/.analyze-state.json'
const GRACE_MS = 400
const WINDOW_MS = 15_000

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readState = () => {
  try {
    return { seq: 0, lastGreenAt: 0, pending: [], ...JSON.parse(readFileSync(STATE_PATH, 'utf8')) }
  } catch {
    return { seq: 0, lastGreenAt: 0, pending: [] }
  }
}

// Concurrent hooks can interleave here. A lost write costs at most one redundant analyze run, which is
// the safe direction — it can never cause a check to be skipped that was needed.
const writeState = state => {
  try {
    mkdirSync(dirname(STATE_PATH), { recursive: true })
    writeFileSync(STATE_PATH, JSON.stringify(state))
  } catch {
    /* state is an optimisation; losing it only means analyzing more often */
  }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const filePath = payload?.tool_input?.file_path

  // Only game source. Editing a test or a harness script does not change what the analyzer sees, since
  // it runs over `src/` alone.
  if (typeof filePath !== 'string' || !/(^|\/)src\/.*\.luau?$/.test(filePath)) process.exit(0)

  // Claim a sequence number. Anything arriving after this point is "newer than me".
  const claimed = readState()
  const mySeq = (claimed.seq ?? 0) + 1
  const pending = [...new Set([...(claimed.pending ?? []), filePath])]

  writeState({ ...claimed, seq: mySeq, pending })

  const now = Date.now()

  // WINDOW: a green result less than 15s old still stands. A red one never suppresses.
  if (claimed.lastGreenAt && now - claimed.lastGreenAt < WINDOW_MS) process.exit(0)

  // GRACE: let a parallel batch finish landing, then defer to whoever edited last.
  await sleep(GRACE_MS)

  if ((readState().seq ?? 0) > mySeq) process.exit(0)

  try {
    execFileSync('npm', ['run', '--silent', 'analyze'], { encoding: 'utf8', stdio: 'pipe' })
    writeState({ ...readState(), lastGreenAt: Date.now(), pending: [] })
    process.exit(0)
  } catch (error) {
    // Clearing lastGreenAt is what makes the next edit check immediately instead of waiting out the
    // window — a broken tree gets fast feedback, a healthy one does not.
    writeState({ ...readState(), lastGreenAt: 0 })

    const output = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim().split('\n').slice(0, 20).join('\n')

    process.stdout.write(
      `${JSON.stringify({
        decision: 'block',
        reason: `The Luau analyzer failed after editing ${filePath}. Fix it before continuing.\n\n${output}`
      })}\n`
    )
    process.exit(0)
  }
}

if (process.argv[1]?.endsWith('gate-luau-analyze.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const check = (label, actual, expected) => {
      ran += 1
      if (actual === expected) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${expected}, got ${actual}`)
    }

    const watched = path => /(^|\/)src\/.*\.luau?$/.test(path)

    check('a server module is watched', watched('src/server/Services/RoundService.luau'), true)
    check('a shared module is watched', watched('src/shared/Config.luau'), true)
    check('a .lua file is watched too', watched('src/client/init.client.lua'), true)
    check('a test is not — the analyzer does not read tests/', watched('tests/config.test.luau'), false)
    check('a harness script is not', watched('.claude/scripts/check-remotes.mjs'), false)
    check('a markdown file is not', watched('docs/MVP-SPEC.md'), false)

    // The suppression rules, exercised as pure decisions. A skip must only ever be able to DEFER.
    const suppress = ({ lastGreenAt, now, newerSeq }) => {
      if (lastGreenAt && now - lastGreenAt < WINDOW_MS) return 'window'
      if (newerSeq) return 'grace'

      return 'run'
    }

    check('a recent GREEN suppresses', suppress({ lastGreenAt: 1000, now: 5000, newerSeq: false }), 'window')
    check('a stale green does not', suppress({ lastGreenAt: 1000, now: 1000 + WINDOW_MS + 1, newerSeq: false }), 'run')
    check('a RED never suppresses', suppress({ lastGreenAt: 0, now: 5000, newerSeq: false }), 'run')
    check('a newer edit takes over', suppress({ lastGreenAt: 0, now: 5000, newerSeq: true }), 'grace')

    console.log(failures ? `  FAIL  gate-luau-analyze: ${ran - failures}/${ran}` : `  PASS  gate-luau-analyze: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  main()
}
