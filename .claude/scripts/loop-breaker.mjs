#!/usr/bin/env node
// Counts consecutive failures of the SAME Bash command and escalates.
//
// This is the mechanism behind the `debug-ladder` skill's three-attempt threshold. A skill alone
// cannot enforce it: a model stuck in a loop will not invoke its own anti-loop skill, because not
// noticing is the failure. The counter therefore lives outside the model.
//
//   2 consecutive failures -> inject the ladder into context (non-blocking)
//   3 consecutive failures -> block, forcing escalation to the user
//   a SECOND block         -> halt; the directive has already been given and ignored
//
// Registered on BOTH PostToolUse and PostToolUseFailure, de-duplicating on tool_use_id. Failure
// detection probes several candidate fields and defaults to "not a failure" when it cannot tell — a
// breaker that fires spuriously is worse than one that occasionally misses.
//
// Verify what it actually sees with:  node .claude/scripts/loop-breaker.mjs --debug < payload.json

import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const STATE_PATH = '.claude/.loop-state.json'
const INJECT_AT = 2
const BLOCK_AT = 3

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readState = () => {
  try {
    return JSON.parse(readFileSync(STATE_PATH, 'utf8'))
  } catch {
    return { entries: {}, seen: [] }
  }
}

const writeState = state => {
  mkdirSync(dirname(STATE_PATH), { recursive: true })
  // Keep the seen-list bounded; it only exists to de-duplicate double-fired events.
  state.seen = state.seen.slice(-200)
  writeFileSync(STATE_PATH, `${JSON.stringify(state)}\n`)
}

// Returns true only when the payload gives positive evidence of failure.
const didFail = payload => {
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

const main = async () => {
  const debug = process.argv.includes('--debug')

  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  if (debug) {
    console.error(JSON.stringify({ event: payload.hook_event_name, tool_response: payload.tool_response }, null, 2))
    console.error(`didFail() => ${didFail(payload)}`)
    process.exit(0)
  }

  const command = payload?.tool_input?.command

  if (typeof command !== 'string' || !command.trim()) process.exit(0)

  const state = readState()
  const useId = payload.tool_use_id

  // Both candidate events may fire for one command; count it once.
  if (useId) {
    if (state.seen.includes(useId)) process.exit(0)

    state.seen.push(useId)
  }

  const scope = `${payload.session_id ?? 'unknown'}:${payload.agent_id ?? 'main'}`
  const key = `${scope}:${createHash('sha1').update(command.trim()).digest('hex').slice(0, 12)}`

  if (!didFail(payload)) {
    if (state.entries[key]) delete state.entries[key]

    writeState(state)
    process.exit(0)
  }

  const entry = state.entries[key] ?? { count: 0, command: command.trim().slice(0, 200), events: [] }

  entry.events = [...new Set([...(entry.events ?? []), payload.hook_event_name ?? 'unknown'])]
  entry.count += 1
  state.entries[key] = entry
  writeState(state)

  if (entry.count >= BLOCK_AT) {
    // COUNT SURVIVES THE BLOCK, deliberately. Deleting the counter here would restart it the moment
    // the block was issued: the same command could fail forever, blocked every third time, with the
    // identical message and no escalation. Blocking is a rung on the ladder, not the end of it.
    //
    // The success path above still deletes, and that is correct — a command that passed has nothing
    // left to count.
    entry.blocked = (entry.blocked ?? 0) + 1
    state.entries[key] = entry
    writeState(state)

    if (entry.blocked >= 2) {
      process.stdout.write(
        `${JSON.stringify({
          decision: 'block',
          reason:
            `HALT — this command has been blocked ${entry.blocked} times and has now failed ` +
            `${entry.count} times in total:\n\n    ${entry.command}\n\n` +
            `Do not run it again and do not try another variation. Stop and tell the user: the verbatim ` +
            `symptom, every hypothesis already tried, what you now believe the cause is, and what you ` +
            `would need in order to be sure.`
        })}\n`
      )
      process.exit(0)
    }

    process.stdout.write(
      `${JSON.stringify({
        decision: 'block',
        reason:
          `This command has now failed ${entry.count} times unchanged:\n\n    ${entry.command}\n\n` +
          `Stop retrying it. Load the \`debug-ladder\` skill, write the attempt ledger, and escalate to ` +
          `the user with: the verbatim symptom, every hypothesis already tried, what you now believe the ` +
          `cause is, and what you would need in order to be sure.`
      })}\n`
    )
    process.exit(0)
  }

  if (entry.count >= INJECT_AT) {
    process.stdout.write(
      `${JSON.stringify({
        hookSpecificOutput: {
          hookEventName: payload.hook_event_name ?? 'PostToolUse',
          additionalContext:
            `This exact command has failed ${entry.count} times in a row. Before running it again, load ` +
            `the \`debug-ladder\` skill: write down the hypothesis you have already disproved, and make ` +
            `your next attempt differ in KIND, not in detail. One more identical failure will be blocked.`
        }
      })}\n`
    )
  }

  process.exit(0)
}

main()
