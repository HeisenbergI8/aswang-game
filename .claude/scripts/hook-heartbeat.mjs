#!/usr/bin/env node
// Records that a hook FIRED, and what its payload actually carried.
//
// Two jobs, both answering questions a harness otherwise guesses at.
//
// 1. LIVENESS. The worst failure mode in a hook-driven harness is a hook that is configured and
//    silently does not fire. Nothing detects that on its own: a guard that never runs looks exactly
//    like a guard with nothing to do. Comparing the hooks REGISTERED in settings.json against the
//    hooks that have EVER fired turns that silence into an alarm.
//
// 2. PAYLOAD SHAPE. Caps and gates you cannot measure are decoration. Before building anything that
//    reads a payload field, the honest move is to find out what the payload actually carries. This
//    records the KEY NAMES seen per event — never the values, which would put message text on disk.
//
// Called by other hooks, never registered directly. Writes only; it can never block anything.
//
// ── APPEND-ONLY ────────────────────────────────────────────────────────────────
//
// FOUR hooks are registered on `Stop` here and every one calls beat(). A read-modify-write over one
// JSON object loses increments when they race, and a hook whose beats were lost gets reported as
// DEAD — the false alarm that gets an alarm ignored. So: one appended line per beat, which POSIX
// guarantees atomic below PIPE_BUF, and `.hook-heartbeat.json` is a DERIVED VIEW folded from it.
//
// The view write is racy and deliberately left so: it self-heals on the next beat. A derived file
// that goes stale for one event is a different class of problem from a source of truth that loses
// data.

import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const JSONL = '.claude/.hook-heartbeat.jsonl'
const VIEW = '.claude/.hook-heartbeat.json'

// Folded back to one snapshot line per hook once the log passes this, so it cannot grow without
// bound. Snapshot lines carry `fired`, so compaction preserves the running total — a count that
// silently restarted would look exactly like a hook that stopped firing.
const COMPACT_AT = 2000

export const foldBeats = (text = '') => {
  const hooks = {}

  for (const line of text.split('\n')) {
    if (!line) continue

    let event

    try {
      event = JSON.parse(line)
    } catch {
      continue // a torn line is skipped rather than crashing every hook that beats
    }

    if (!event?.n) continue

    const entry = (hooks[event.n] ??= { fired: 0, keys: [] })

    entry.fired += typeof event.fired === 'number' ? event.fired : 1

    if (event.t) entry.last = event.t
    if (event.ev) entry.event = event.ev

    for (const key of event.k ?? []) {
      if (!entry.keys.includes(key)) entry.keys.push(key)
    }
  }

  return { hooks }
}

const readLog = () => {
  try {
    return readFileSync(JSONL, 'utf8')
  } catch {
    return ''
  }
}

// COMPACTION IS THE ONE RACY OPERATION LEFT, so only the main thread performs it. Agents append and
// never rewrite, and the main thread is never concurrent with itself.
const compact = folded => {
  if (process.env.CLAUDE_AGENT_TYPE) return

  const lines = readLog().split('\n').filter(Boolean)

  if (lines.length < COMPACT_AT) return

  const snapshot = Object.entries(folded.hooks).map(([name, entry]) =>
    JSON.stringify({ n: name, fired: entry.fired, t: entry.last, ev: entry.event, k: entry.keys })
  )

  writeFileSync(JSONL, `${snapshot.join('\n')}\n`)
}

export const beat = (name, payload) => {
  // A hook driven by its own test suite must not register as ALIVE. Liveness means "fired for a real
  // event"; a test harness calling the CLI eight times would mark the newest, least-proven hook as
  // healthy on the strength of nothing, inverting the one signal this file exists to give.
  if (process.env.CLAUDE_HOOK_TEST === '1') return

  try {
    mkdirSync('.claude', { recursive: true })

    // Key names only. Values are never recorded — a payload can contain a whole assistant message.
    appendFileSync(
      JSONL,
      `${JSON.stringify({
        n: name,
        t: new Date().toISOString(),
        ev: payload?.hook_event_name ?? 'unknown',
        k: Object.keys(payload ?? {})
      })}\n`
    )

    const folded = foldBeats(readLog())

    writeFileSync(VIEW, `${JSON.stringify(folded, null, 2)}\n`)
    compact(folded)
  } catch {
    // A heartbeat must never be the reason a hook fails.
  }
}

// ── CLI: report which registered hooks have never fired ────────────────────────

if (process.argv[1]?.endsWith('hook-heartbeat.mjs')) {
  const registered = []

  try {
    const settings = JSON.parse(readFileSync('.claude/settings.json', 'utf8'))

    for (const [event, matchers] of Object.entries(settings.hooks ?? {})) {
      for (const matcher of matchers) {
        for (const hook of matcher.hooks ?? []) {
          const script = (hook.args ?? []).find(arg => arg.endsWith('.mjs'))

          if (script) registered.push({ event, name: script.split('/').pop().replace('.mjs', '') })
        }
      }
    }
  } catch {
    console.log('- heartbeat: settings.json unreadable')
    process.exit(0)
  }

  // Folded from the append-only log rather than read off the view, so the report cannot be one beat
  // behind a concurrent write.
  const seen = foldBeats(readLog()).hooks

  // Only hooks that call `beat()` can be reported on, so an absence here is not proof of death for
  // the ones that do not. Naming which are instrumented keeps that honest.
  //
  // Deduplicated by NAME: `verify-gate` is registered on both Stop and SubagentStop, and listing it
  // twice makes the alarm read as a bug in the alarm — which is how an alarm gets ignored.
  // `ensure-rojo` is here because it is the one hook whose failure is INVISIBLE BY CONSTRUCTION: it
  // emits nothing, decides nothing, and exits 0 either way. If it stops firing, Studio silently goes
  // back to needing a hand-started server — and the first symptom is a verification of stale code.
  const instrumented = ['verify-gate', 'claim-check', 'review-gate', 'task-driver', 'ensure-rojo']
  const silent = [...new Set(registered.map(hook => hook.name))].filter(
    name => instrumented.includes(name) && !seen[name]
  )

  for (const [name, entry] of Object.entries(seen)) {
    console.log(`  ${name}: fired ${entry.fired}× on ${entry.event}, last ${entry.last}`)
  }

  if (silent.length) {
    console.log(`  WARN  registered but never fired: ${silent.join(", ")}`)
    console.log('        "configured" and "firing" are different states — probe before relying on it.')
  } else if (!Object.keys(seen).length) {
    console.log('- heartbeat: nothing recorded yet — run a turn first')
  } else {
    console.log(`- heartbeat: ${Object.keys(seen).length} hook(s) alive`)
  }
}
