#!/usr/bin/env node
// Stop hook: once per session, if this session recorded a real correction, ask the USER whether it
// should become a lesson.
//
// Adapted from the same hook in the new-admin-frontend repo, where it was written after the identical
// failure showed up there: 110 candidates against a review threshold of 15, and `/lessons-review` had
// never run. This repo was measured at 58 candidates and ZERO lessons on 2026-08-12 — the capture half
// of the loop has been working perfectly and the distil half has never happened once.
//
// WHY THIS EXISTS
// ---------------
// The capture half of the learning loop is automatic; the distil half is not. `/lessons-review` is
// user-invoked, so it only runs when someone remembers. The gap is narrower than "nobody reviews the
// backlog": a correction is freshest at the moment it happens, and nothing brings it up then. Asked a
// week later against a list of 58 one-line snippets, neither of us can reconstruct what mattered.
//
// WHY IT ASKS RATHER THAN WRITES
// ------------------------------
// `lesson-keeper` is explicit that recording is a human decision point, and that the capture is
// automatic *precisely so* the admission is not. This hook does not write a lesson, propose wording,
// or touch `.claude/lessons/`. It surfaces one question and gets out of the way.
//
// WHY IT BLOCKS ONCE
// ------------------
// A non-blocking Stop message is not reliably read. A gate that blocks every turn is a gate that gets
// switched off. So: at most one block per session, and only when there is something concrete to point
// at.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const CANDIDATES = '.claude/.candidates.jsonl'
const STATE = '.claude/.lesson-prompt-state.json'

// Only the strong signals. A low-confidence match is exactly the noise this must not nag about.
const WORTH_ASKING = new Set(['self-correction'])
const HIGH = 'high'

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

// Entries recorded since this session started. `startedAt` is stamped the first time the session is
// seen, so a long-running session does not keep re-reading yesterday's rows.
export const freshSignals = (lines, since) =>
  lines
    .map(line => {
      try {
        return JSON.parse(line)
      } catch {
        return null
      }
    })
    .filter(Boolean)
    .filter(entry => typeof entry.at === 'string' && entry.at >= since)
    .filter(entry => WORTH_ASKING.has(entry.kind) || entry.confidence === HIGH)

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  // Never interrupt a supervised /build run — it has its own driver and halt reporting.
  if (payload?.stop_hook_active) process.exit(0)

  const session = payload?.session_id ?? 'unknown'
  const state = readJson(STATE, {})

  if (state.promptedSession === session) process.exit(0)

  if (!existsSync(CANDIDATES)) process.exit(0)

  const since = state.session === session && state.startedAt ? state.startedAt : new Date().toISOString()

  const save = extra => {
    mkdirSync(dirname(STATE), { recursive: true })
    writeFileSync(STATE, `${JSON.stringify({ session, startedAt: since, ...extra })}\n`)
  }

  const lines = readFileSync(CANDIDATES, 'utf8').trim().split('\n').filter(Boolean)
  const fresh = freshSignals(lines, since)

  if (fresh.length === 0) {
    save({})
    process.exit(0)
  }

  save({ promptedSession: session })

  const examples = fresh
    .slice(-3)
    .map(entry => `  · [${entry.kind}] ${String(entry.text ?? '').slice(0, 100)}`)
    .join('\n')

  const reason =
    `This session recorded ${fresh.length} correction signal(s):\n${examples}\n\n` +
    `Before you finish: ASK THE USER whether any of this is worth a lesson. One short question, ` +
    `their call — do not write one yourself and do not pad the answer.\n\n` +
    `The bar (.claude/skills/lesson-keeper/SKILL.md): will it recur, was it non-obvious, does it ` +
    `change what you would DO, did it cost something real. All four, or it is a discard — and ` +
    `"discard" is the right answer most of the time.\n\n` +
    `If it is mechanically checkable, propose a guard instead. An encoded rule beats a written one.\n\n` +
    `This fires at most once per session.`

  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`)
  process.exit(0)
}

if (process.argv[1] && process.argv[1].endsWith('lesson-prompt.mjs')) await main()
