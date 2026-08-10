#!/usr/bin/env node
// Stop gate: refuses to let a turn end on an unsupported claim about verification.
//
// The failure this exists for is "Done! The tree is green." when nothing ran, or when it ran and
// failed. `verify-gate.mjs` already blocks ending on a RED tree; it cannot catch a claim about a run
// that never happened while the tree is green. This can, because `record-activity.mjs` writes down
// what actually ran.
//
// Two independent checks, in increasing order of what they need:
//
//   A. SOURCE TOUCHED, NOTHING VERIFIED — needs only the ledger. Editing src/ and ending the turn with
//      no successful verification recorded is blocked outright.
//
//   B. CLAIM WITHOUT A RUN — needs `last_assistant_message` on the Stop payload, which is not
//      guaranteed on every build. If it is absent this check silently does nothing and A still applies.
//      Run with --probe to see what the payload actually carries.
//
// Like the verify gate, it keeps its own consecutive-block counter so it can never trap a session.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

import { beat } from './hook-heartbeat.mjs'

const LEDGER = '.claude/.run-ledger.json'
const STATE = '.claude/.claim-state.json'
const MAX_BLOCKS = 2

// ── USE vs MENTION ─────────────────────────────────────────────────────────────
//
// The patterns below hunt for an ASSERTION that a gate is green. A regex cannot tell that apart from a
// phrase being QUOTED — and this hook's own subject IS that assertion, so any message documenting it
// trips forever. In the system this is adapted from, the raw matcher fired 29 times in one session on
// pasted command output, a pattern table, and an acceptance criterion; the 29th fired on the very
// table enumerating the first 28.
//
// Worse than noisy: pasting REAL output as evidence is the practice this repo wants, and the raw
// matcher penalised it while a bare prose assertion looked identical.
//
// TWO DELIBERATE CHOICES:
//   1. Bold runs are NOT stripped. A genuine claim is often written **in bold for emphasis**, so
//      stripping it would let the exact sentence this gate exists for walk straight through.
//   2. Quoted spans are bounded and single-line. An unbounded `"[^"]*"` swallows everything between
//      two distant quotes, which could hide a real claim sitting between them.
//
// This weakens check B slightly — output faked inside a fence is no longer read as a claim. Accepted:
// check A does not depend on the message at all, and the ledger is what this gate is built on.
export const stripQuoted = text =>
  text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/"[^"\n]{0,200}"/g, ' ')
    .replace(/[“”][^“”\n]{0,200}[“”]/g, ' ')

export const CLAIM_PATTERNS = [
  /\b\d+\s*\/\s*\d+\s+(tests?|invariants?|checks?|passing|pass)\b/i,
  /\b(tests?|suite|specs?|invariants?)\s+(all\s+)?pass(ed|ing)?\b/i,
  /\ball\s+(tests?|checks?|gates?)\s+(are\s+)?(green|passing|pass)\b/i,
  /\b(verify|analyze|analysis|typecheck|lint|selene|stylua|baseline|gates?|the tree)\s+(is\s+|are\s+)?(green|clean|passing|passes|passed)\b/i,

  // NARROWED on purpose. Both of the next two fire on prose ABOUT exit codes and baselines rather than
  // on a claim — "a zero exit means PASS", "the baseline unchanged line is what proves it". Requiring
  // a verification noun within ~45 characters keeps every real claim shape and drops the descriptions.
  /\b(verify|analyze|lint|tests?|build|baseline|gates?|check:\w+)\b[^.\n]{0,45}\bexit\s*=?\s*0\b/i,

  // "unchanged" followed by a noun is MODIFYING it ("the baseline unchanged line"), not asserting a
  // state. The negative lookahead separates them while keeping the real shape.
  /\b(baseline|suite|tests?|diagnostics)\s+(is\s+|are\s+|was\s+|remains?\s+)?unchanged\b(?!\s+(line|message|check|string|pattern|rule|text|claim|clause))/i,
  /\bI\s+ran\s+the\s+(tests?|suite|gates?|checks?|verify)\b/i,

  // Repo-specific, and the most damaging claim available here: asserting the game was OBSERVED running
  // when Studio was never driven. A screenshot that does not exist stops anyone else from looking.
  /\b(round|phase|transform|kill|task|trial)\w*\s+(works?|worked|fires?|fired|cycles?|cycled)\s+(correctly|fine|as expected|in studio)\b/i,
  /\b(tested|verified|confirmed)\s+(it\s+)?in\s+studio\b/i
]

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readText = path => {
  try {
    return readFileSync(path, 'utf8')
  } catch {
    return null
  }
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
    // No payload is not grounds to trap a turn.
    process.exit(0)
  }

  beat('claim-check', payload)

  if (process.argv.includes('--probe')) {
    console.error(
      JSON.stringify({ keys: Object.keys(payload), hasMessage: 'last_assistant_message' in payload }, null, 2)
    )
    process.exit(0)
  }

  if (payload.stop_hook_active === true) process.exit(0)

  const turn = payload.prompt_id ?? payload.session_id ?? 'unknown'
  const key = `${payload.session_id ?? 'unknown'}:${turn}`
  const state = readJson(STATE, {})

  // Stand aside rather than trap the session. The model has been told twice.
  if ((state[key] ?? 0) >= MAX_BLOCKS) {
    delete state[key]
    writeState(state)
    process.exit(0)
  }

  // The ledger is APPEND-ONLY JSONL — one line per event, filtered to this turn. A torn line is
  // skipped rather than crashing the gate.
  const entry = { edits: [], runs: [] }

  for (const line of (readText(LEDGER) ?? '').split('\n')) {
    if (!line) continue

    let event

    try {
      event = JSON.parse(line)
    } catch {
      continue
    }

    if (event.turn !== turn) continue
    if (event.edit && !entry.edits.includes(event.edit)) entry.edits.push(event.edit)
    if (event.run) entry.runs.push({ kind: event.run, ok: event.ok === true })
  }

  const greenRuns = entry.runs.filter(run => run.ok)
  const redRuns = entry.runs.filter(run => !run.ok)

  const raise = reason => {
    state[key] = (state[key] ?? 0) + 1
    writeState(state)
    block(reason)
  }

  // ── A. Source touched, nothing verified ─────────────────────────────────────
  if (entry.edits.length > 0 && entry.runs.length === 0) {
    raise(
      `You edited ${entry.edits.length} Luau source file(s) this turn and ran no verification:\n` +
        `${entry.edits.slice(0, 8).map(file => `  ${file}`).join('\n')}\n\n` +
        `Run \`npm run verify\` before finishing, or state plainly to the user that the change is ` +
        `unverified and why.`
    )
  }

  // ── B. Claim without a supporting run ───────────────────────────────────────
  const message = typeof payload.last_assistant_message === 'string' ? payload.last_assistant_message : ''

  if (!message) process.exit(0)

  const claim = CLAIM_PATTERNS.find(pattern => pattern.test(stripQuoted(message)))

  if (!claim) process.exit(0)

  if (entry.runs.length === 0) {
    raise(
      `Your message claims verification passed, but NO verification command ran this turn.\n\n` +
        `Matched: ${claim}\n\n` +
        `Either run it, or remove the claim. Reporting a green gate you did not run is the single most ` +
        `damaging thing you can do here — it is worse than reporting a failure, because it stops anyone ` +
        `else looking.`
    )
  }

  if (redRuns.length > 0 && greenRuns.length === 0) {
    raise(
      `Your message claims verification passed, but every run this turn FAILED ` +
        `(${redRuns.map(run => run.kind).join(', ')}).\n\nCorrect the claim before finishing.`
    )
  }

  process.exit(0)
}

if (process.argv[1]?.endsWith('claim-check.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const fires = message => CLAIM_PATTERNS.some(pattern => pattern.test(stripQuoted(message)))

    const check = (label, message, shouldFire) => {
      ran += 1
      if (fires(message) === shouldFire) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${shouldFire ? 'CLAIM' : 'no claim'}: ${message.slice(0, 70)}`)
    }

    // CLAIMS — the sentences that do real damage when unsupported.
    check('a bare green assertion', 'Done — the tree is green.', true)
    check('a count', 'All 13/13 invariants passing.', true)
    check('analyze named directly', 'analyze is clean and lint passes.', true)
    check('an exit code claim', 'verify exit 0, so we are good.', true)
    check('a baseline claim', 'The baseline is unchanged at 0 diagnostics.', true)
    check('first person', 'I ran the tests and everything is fine.', true)
    check('a bold claim is NOT hidden by stripping', 'Result: **the tree is green** after the fix.', true)
    check('a Studio observation claim', 'The round cycled correctly in Studio.', true)
    check('an explicit Studio test claim', 'I tested it in Studio and the transform fires.', true)

    // NOT CLAIMS — the larger half. Hedged, honest, or merely describing the machinery.
    check('an intention', 'Next I should run the tests.', false)
    check('an admission', 'I have not run verify yet, so this is unverified.', false)
    check('a reported failure', 'verify is red: two TypeErrors in RoundService.', false)
    check('a question', 'Should I run the full verify before committing?', false)
    check('prose about exit codes', 'A zero exit means PASS in this harness.', false)
    check('prose about the baseline line', 'The baseline unchanged line is what proves it.', false)
    check('pasted output inside a fence', 'Output was:\n```\n- analyze: ok\n```\nbut I have not re-run it.', false)
    check('a quoted pattern being documented', 'The gate matches "the tree is green" as a claim.', false)
    check('an inline code mention', 'The `verify passes` phrase is what trips it.', false)
    check('describing what the gate does', 'This blocks when tests pass is asserted without a run — see the note.', true)

    console.log(failures ? `  FAIL  claim-check: ${ran - failures}/${ran}` : `  PASS  claim-check: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  main()
}
