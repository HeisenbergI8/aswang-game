#!/usr/bin/env node
// PostToolUse recorder. Writes a per-turn ledger of what ACTUALLY happened: which source files were
// edited, which verification commands ran, whether each one passed, and which review agents finished.
//
// This exists so `claim-check.mjs` can compare a claim against a record instead of taking the model's
// word for it. A model asserting "the tree is green" is a prompt; a ledger entry with an exit code is
// evidence. Nothing here blocks anything — it only observes.
//
// Keyed on `prompt_id`, which the hook payload carries, so "this turn" is a real boundary rather than
// a guess about timing.

import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const LEDGER = '.claude/.run-ledger.json'
const MAX_TURNS_KEPT = 20

// Commands whose exit code is evidence about the tree's health.
//
// The `(?!:)` on the first entry is load-bearing: it separates the closing gate `npm run verify` from
// the mid-task `verify:fast`, and `review-gate.mjs` keys its whole predicate on that distinction.
const VERIFY_PATTERNS = [
  { re: /npm\s+run\s+(--silent\s+)?verify\b(?!:)/, kind: 'verify' },
  { re: /npm\s+run\s+(--silent\s+)?verify:fast\b/, kind: 'verify:fast' },
  { re: /npm\s+run\s+(--silent\s+)?analyze\b|luau-lsp\s+analyze/, kind: 'analyze' },
  { re: /npm\s+run\s+(--silent\s+)?lint\b|\bselene\b/, kind: 'lint' },
  { re: /npm\s+run\s+(--silent\s+)?fmt:check\b|stylua\s+--check/, kind: 'fmt' },
  { re: /npm\s+run\s+(--silent\s+)?check:\w+/, kind: 'check' },
  { re: /npm\s+run\s+(--silent\s+)?test:unit\b|\blune\s+run\b/, kind: 'test:unit' },
  { re: /npm\s+run\s+(--silent\s+)?build\b|rojo\s+build/, kind: 'build' }
]

// The review agents whose completion silences `review-gate.mjs`. Anything else finishing — an
// Explore, a general-purpose agent — must not count, or an unrelated subagent silences the gate.
const REVIEW_AGENTS = /^(playtester|auditor|change-auditor|exploit-auditor)$/

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

// Positive evidence of failure only — same discipline as the loop breaker. When the payload shape is
// unrecognised, treat the run as passing rather than inventing a failure that blocks a turn.
const failed = payload => {
  if (payload.hook_event_name === 'PostToolUseFailure') return true

  const response = payload.tool_response

  if (!response || typeof response !== 'object') return false

  for (const field of ['exit_code', 'exitCode', 'code', 'status', 'returnCode']) {
    if (typeof response[field] === 'number') return response[field] !== 0
  }

  for (const field of ['is_error', 'isError', 'error', 'failed']) {
    if (typeof response[field] === 'boolean') return response[field]
  }

  return false
}

// Keeps the last MAX_TURNS_KEPT turns. Called only from the main thread — see the note at the append
// site.
const compact = () => {
  let lines

  try {
    lines = readFileSync(LEDGER, 'utf8').split('\n').filter(Boolean)
  } catch {
    return
  }

  if (lines.length < 400) return

  const seen = []

  for (const line of lines) {
    try {
      const { turn } = JSON.parse(line)

      if (turn && !seen.includes(turn)) seen.push(turn)
    } catch {
      /* a torn line is discarded rather than crashing the hook */
    }
  }

  const keep = new Set(seen.slice(-MAX_TURNS_KEPT))
  const kept = lines.filter(line => {
    try {
      return keep.has(JSON.parse(line).turn)
    } catch {
      return false
    }
  })

  writeFileSync(LEDGER, kept.join('\n') + '\n')
}

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const turn = payload.prompt_id ?? payload.session_id ?? 'unknown'

  // ── APPEND-ONLY ─────────────────────────────────────────────────────────────
  //
  // One appended line per event, with no lock. A read-modify-write over a single JSON object is fine
  // with one writer, and this harness MANDATES concurrent playtester + auditor — two processes that
  // both fire PostToolUse, so the slower write silently discards the faster one's records. That is
  // not merely a lost log line: `claim-check.mjs` reads this file to decide whether a claim about a
  // green gate is supported, so a dropped record turns an honest statement into a blocked turn.
  //
  // POSIX append is atomic below PIPE_BUF and every line here is far under it.
  const events = []
  const tool = payload.tool_name

  if (payload.hook_event_name === 'SubagentStop') {
    const agent = payload.agent_type

    if (typeof agent === 'string' && REVIEW_AGENTS.test(agent)) events.push({ turn, agent })
  }

  // ── LAUNCHES COUNT, NOT ONLY COMPLETIONS ────────────────────────────────────
  //
  // SubagentStop fires when an agent FINISHES, and the reviewers here are deliberately launched in the
  // background — so they finish two or three turns after the turn that edited the source. The editing
  // turn therefore always looked unreviewed, and `review-gate` nudged for reviewers that were at that
  // moment already running. Every nudge in this session's C02-C04 work was that, not a real omission.
  //
  // Recording the LAUNCH fixes it and fixes the resumed-agent case at the same time: continuing an
  // auditor with SendMessage keeps its prior findings in context and is strictly better than a fresh
  // spawn, but it emits no SubagentStop of its own until it stops again.
  //
  // The gate is not weakened by this. A launch that is later skipped or dies still leaves the work
  // unreviewed — but that shows up as a missing REPORT, which a person reads, rather than as a nudge
  // fired at a model that already did the right thing and has no way to say so.
  if (tool === 'Agent' || tool === 'Task') {
    const agent = payload.tool_input?.subagent_type

    if (typeof agent === 'string' && REVIEW_AGENTS.test(agent)) events.push({ turn, agent, launched: true })
  }

  // ── A RESUME IS DELIBERATELY *NOT* CREDITED ─────────────────────────────────
  //
  // The first version of this credited every `SendMessage` as a review touch, on the reasoning that a
  // resumed auditor keeps its own findings in context and should not read as nothing. An audit proved
  // that unconditional: a message to ANY agent — a research task, anything — silenced the gate, which
  // is exactly the hole the `Task`/`Agent` branch above is written to avoid. A resume carries only the
  // target's id, never its type, so there is nothing here to filter on.
  //
  // So it is dropped, and the cost is a spurious nudge on the rare turn that only resumes a reviewer.
  // That is the right direction to fail: a gate that asks when it needn't costs one sentence, and a
  // gate that can be silenced by an unrelated message costs the thing it was guarding. Recording the
  // LAUNCH above already fixes the case that actually mattered — background reviewers finishing two
  // or three turns after the turn that edited the source.

  if (tool === 'Edit' || tool === 'Write' || tool === 'NotebookEdit') {
    const file = payload.tool_input?.file_path

    // Only TRACKED game source counts. Edits to .claude/, plans, or scratch are not the thing a
    // "the tree is green" claim is about.
    if (typeof file === 'string' && /(^|\/)src\/.*\.luau$/.test(file)) {
      events.push({ turn, edit: file })
    }
  }

  if (tool === 'Bash') {
    const command = payload.tool_input?.command ?? ''
    const match = VERIFY_PATTERNS.find(pattern => pattern.re.test(command))

    if (match) {
      // `cmd` is here because `lessons.mjs nudge` keys its failed-then-recovered detection on the
      // command string. Omitting it makes every run hash to '' and count as failed, and the nudge can
      // then never fire — a green test over a dead mechanism.
      events.push({ turn, run: match.kind, ok: !failed(payload), cmd: command.trim().slice(0, 80) })
    }
  }

  if (!events.length) process.exit(0)

  mkdirSync(dirname(LEDGER), { recursive: true })
  appendFileSync(LEDGER, events.map(event => JSON.stringify(event)).join('\n') + '\n')

  // COMPACTION IS THE ONE RACY OPERATION LEFT, so only the main thread does it. Agents append and
  // never rewrite; the main thread is never concurrent with itself, so the rewrite has a single
  // writer by construction.
  if (!process.env.CLAUDE_AGENT_TYPE) compact()

  process.exit(0)
}

main()
