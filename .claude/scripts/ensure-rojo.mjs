#!/usr/bin/env node
// PreToolUse on `mcp__Roblox_Studio__.*` — keeps `rojo serve` alive, and keeps the harness honest about
// what that does and does not prove.
//
//   node .claude/scripts/ensure-rojo.mjs             reads a hook payload on stdin, never blocks
//   node .claude/scripts/ensure-rojo.mjs --status    the three facts, and the verdict
//   node .claude/scripts/ensure-rojo.mjs --bless     record THIS server session as proven-syncing
//   node .claude/scripts/ensure-rojo.mjs --self-test
//
// ── WHY A HOOK AND NOT A LINE IN A SKILL ───────────────────────────────────────
//
// CLAUDE.md says "start this first, every session" and the playtester's Step 1 says to stop if Rojo is
// down. Both are directives, and the failure they guard is the one that looks most like success: with
// no server, `src/` simply is not in Studio, so an agent can drive the place, screenshot it, read the
// console and report a green verification of code from an hour ago.
//
// ── THREE FACTS, NOT ONE, AND THE FOURTH THAT NO SCRIPT CAN SEE ────────────────
//
// The first version of this file collapsed these and shipped a FALSE GREEN within the hour. It is worth
// recording exactly how, because the shape recurs:
//
//   1. `serving`   — the port answers.        Proves a server exists. Nothing more.
//   2. `attached`  — a RobloxStudio process holds a socket to it.
//   3. `sessionId` — which server session that is. Rojo mints a new one per `rojo serve`.
//   4. IS STUDIO'S TREE ACTUALLY CURRENT?  ← unobservable from here
//
// What happened: the user's `rojo serve` died mid-session. This hook restarted it, correctly. Studio's
// plugin then held an ESTABLISHED socket against the NEW server — a retry loop produces one just as a
// healthy sync does — so a check that read fact 2 reported "connected: yes" while the DataModel still
// held pre-restart content. Every edit made for the next twenty minutes went nowhere, and the checks
// said green. That is the exact failure this file exists to prevent, produced BY this file.
//
// Fact 4 needs a DataModel read, which means MCP, which a node hook does not have. So it is not guessed:
// `--bless` records the sessionId that an agent or a human has PROVEN to be syncing — write a canary
// into a synced file, read it back out of the DataModel, then bless. `startServer` clears the blessing,
// because a new server session invalidates every plugin attached to the old one.
//
// THE POINT IS THE DEFAULT. Unblessed reads as NOT PROVEN, so a forgotten bless costs a stopped run
// rather than a fabricated verification. The old check failed open; this one fails closed.
//
// ── IT NEVER EMITS A PERMISSION DECISION ───────────────────────────────────────
//
// `guard-studio-sync.mjs` is registered on the SAME matcher and DENIES writes to script source inside
// Studio. An `allow` from this hook could override that deny depending on which hook the runtime
// consults last, and task-driver.mjs already records the house rule: hook ordering is not something to
// design on. So this one writes nothing to stdout and always exits 0.

import { execFileSync, spawn } from 'node:child_process'
import { existsSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'

import { beat } from './hook-heartbeat.mjs'

// Rojo's default serve port. Overridable ONLY so the cold-start path can be exercised for real against
// a scratch port — proving it by killing the live server would detach the Studio plugin, and
// reattaching is the one step no script here can perform. Nothing in normal operation sets this.
export const ROJO_PORT = Number(process.env.ASWANG_ROJO_PORT ?? 34872)
export const ROJO_URL = `http://localhost:${ROJO_PORT}/api/rojo`

// The repo root, derived from this file's own location rather than from cwd. A hook's cwd is whatever
// the runtime hands it, and a `rojo serve` started in the wrong directory serves the wrong project.
const ROOT = resolve(dirname(new URL(import.meta.url).pathname), '..', '..')
const STATE_DIR = join(ROOT, '.claude', '.run')
const LOG_PATH = join(STATE_DIR, 'rojo.log')
const STATE_PATH = join(STATE_DIR, 'rojo-ensure.json')

// Short, because this runs before EVERY Studio MCP call. A live local server answers in well under
// 100ms; anything slower is indistinguishable from down for our purposes.
const PROBE_MS = 1500
const START_TIMEOUT_MS = 12000
const POLL_MS = 300
// A failed start must not be retried on every tool call — that would add START_TIMEOUT_MS to each one
// and turn a missing binary into a stalled session.
export const RETRY_COOLDOWN_MS = 60000

export const serving = async (url = ROJO_URL, timeoutMs = PROBE_MS) => {
  try {
    return (await fetch(url, { signal: AbortSignal.timeout(timeoutMs) })).ok
  } catch {
    return false
  }
}

// ── Which server session this is ───────────────────────────────────────────────
//
// `/api/rojo` answers in MessagePack, and pulling in a decoder to read one field would be the tail
// wagging the dog. The sessionId is a UUID and UUIDs survive binary framing intact, so it is matched
// out of the raw bytes. A miss returns null, which `syncVerdict` treats as NOT PROVEN — the safe
// direction, and the reason this is allowed to be a regex at all.
export const parseSessionId = buffer => {
  const found = Buffer.from(buffer ?? [])
    .toString('latin1')
    .match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)

  return found ? found[0] : null
}

export const readSessionId = async (url = ROJO_URL, timeoutMs = PROBE_MS) => {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) })

    if (!response.ok) return null

    return parseSessionId(Buffer.from(await response.arrayBuffer()))
  } catch {
    return null
  }
}

// ── Is a Studio process holding a socket ───────────────────────────────────────
//
// PURE, and exported, because a self-test that needs a running Studio fails on a train and gets
// deleted. Given lsof's output: is a Roblox Studio process holding an established connection whose
// REMOTE end is the Rojo port?
//
// The direction matters. Rojo's own socket appears as `:34872->:63913` — the port on the LOCAL side.
// Matching the port anywhere in the line would count the server as its own client.
//
// NAMED `attached`, NOT `connected`. The old name is why a socket got read as a working sync; a check
// whose name overclaims will be believed over its own documentation.
export const parseStudioConnections = (output, port = ROJO_PORT) =>
  String(output ?? '')
    .split('\n')
    .slice(1) // the COMMAND/PID/... header
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => line.split(/\s+/))
    .filter(fields => /^roblox/i.test(fields[0] ?? ''))
    .map(fields => ({ command: fields[0], pid: fields[1], name: fields.find(field => field.includes('->')) ?? '' }))
    .filter(entry => new RegExp(`->\\S*[:.]${port}$`).test(entry.name))

export const studioAttached = () => {
  try {
    // `+c 0` defeats lsof's 9-character COMMAND truncation, which renders "RobloxStudio" as "RobloxStu".
    const out = execFileSync('lsof', ['+c', '0', '-nP', `-iTCP:${ROJO_PORT}`, '-sTCP:ESTABLISHED'], {
      encoding: 'utf8',
      stdio: 'pipe',
      timeout: 3000
    })

    return parseStudioConnections(out).length > 0
  } catch {
    // lsof exits non-zero when nothing matches, and may be absent entirely. Both mean "cannot show a
    // socket", which is the answer that refuses to license evidence — the safe direction.
    return false
  }
}

// ── The verdict ────────────────────────────────────────────────────────────────
//
// PURE, and the whole domain is enumerated in the self-test rather than sampled. The lesson
// `green-after-each-patch-hides-a-loop` is explicit about why: for a predicate over a bounded domain,
// four reactive patches failed to converge on what one grid found in a single pass. There are 24 cells
// here and all 24 are pinned.
//
// ORDER IS THE MEANING. Each answer names the FIRST thing that is not established, so the message is
// always the next action rather than the last symptom.
export const syncVerdict = ({ serving = false, attached = false, sessionId = null, blessedSessionId = null } = {}) => {
  if (!serving) return 'no-server'
  if (!attached) return 'not-attached'
  if (!sessionId) return 'unknown-session'
  if (blessedSessionId !== sessionId) return 'unblessed-session'

  return 'ok'
}

// The reason string IS what preflight prints, so each names what to DO. "studio not connected" sends
// nobody anywhere; "click Plugins -> Rojo -> Connect" does.
export const VERDICT_REASONS = {
  'no-server': 'rojo serve is not running — code on disk is NOT in Studio, so nothing observed there is evidence',
  'not-attached':
    'no Roblox Studio process is attached to the Rojo server — open the place and click Plugins -> Rojo -> Connect',
  'unknown-session': 'the Rojo server did not report a session id — cannot tell which server Studio is attached to',
  'unblessed-session':
    'this Rojo server session has NOT been proven to sync. A socket is not a sync: a plugin retry loop ' +
    'looks identical. Write a canary into a synced file, read it back from the DataModel via MCP, then ' +
    'run `npm run rojo:bless`',
  ok: null
}

// ── Retry cooldown ─────────────────────────────────────────────────────────────
export const shouldAttempt = (state, now, cooldownMs = RETRY_COOLDOWN_MS) => {
  const last = Number(state?.lastAttemptAt ?? 0)

  if (!Number.isFinite(last) || last <= 0) return true
  // A previous SUCCESS is not a reason to wait: if the server has since died, restarting it promptly is
  // the entire point. Only a recent FAILURE earns a cooldown.
  if (state?.lastResult === 'started') return true

  return now - last >= cooldownMs
}

const readState = () => {
  try {
    return JSON.parse(readFileSync(STATE_PATH, 'utf8'))
  } catch {
    return {}
  }
}

const writeState = value => {
  try {
    mkdirSync(STATE_DIR, { recursive: true })
    writeFileSync(STATE_PATH, `${JSON.stringify(value, null, 2)}\n`)
  } catch {
    /* state is an optimisation, not a dependency */
  }
}

export const blessedSessionId = () => readState().blessedSessionId ?? null

export const bless = sessionId => {
  writeState({ ...readState(), blessedSessionId: sessionId })

  return sessionId
}

const note = message => {
  try {
    mkdirSync(STATE_DIR, { recursive: true })
    writeFileSync(openSync(LOG_PATH, 'a'), `[ensure-rojo ${new Date().toISOString()}] ${message}\n`)
  } catch {
    /* logging must never be the reason a tool call fails */
  }
}

// Detached, with stdio pointed at the log. `unref()` lets this hook exit while the server keeps running
// — a foreground spawn would hang the tool call forever, since `rojo serve` never returns.
export const startServer = () => {
  mkdirSync(STATE_DIR, { recursive: true })

  const fd = openSync(LOG_PATH, 'a')
  const args = ['serve', 'default.project.json']

  if (ROJO_PORT !== 34872) args.push('--port', String(ROJO_PORT))

  const child = spawn('rojo', args, { cwd: ROOT, detached: true, stdio: ['ignore', fd, fd] })

  child.unref()

  return child.pid ?? null
}

const sleep = ms => new Promise(done => setTimeout(done, ms))

export const ensure = async ({ now = Date.now() } = {}) => {
  if (await serving()) return { ok: true, action: 'already-serving' }

  const state = readState()

  if (!shouldAttempt(state, now)) return { ok: false, action: 'cooling-down', reason: state.reason ?? 'a recent start failed' }

  let pid = null

  try {
    pid = startServer()
  } catch (error) {
    const reason = `could not spawn rojo — ${error.message}`

    writeState({ ...state, blessedSessionId: null, lastAttemptAt: now, lastResult: 'failed', reason })
    note(reason)

    return { ok: false, action: 'spawn-failed', reason }
  }

  const deadline = now + START_TIMEOUT_MS

  while (Date.now() < deadline) {
    await sleep(POLL_MS)

    if (await serving()) {
      // THE BLESSING DIES WITH THE OLD SERVER. A new `rojo serve` mints a new sessionId, and every
      // plugin still pointed at the old one is holding a tree that will never update again. Carrying
      // the blessing across a restart is precisely the bug this rewrite exists to fix.
      writeState({ lastAttemptAt: now, lastResult: 'started', pid, blessedSessionId: null })
      note(`started rojo serve (pid ${pid}) — blessing CLEARED; Studio must reconnect and be re-blessed`)

      return { ok: true, action: 'started', pid }
    }
  }

  const reason = `rojo serve did not answer on :${ROJO_PORT} within ${START_TIMEOUT_MS}ms — see ${LOG_PATH}`

  writeState({ ...state, blessedSessionId: null, lastAttemptAt: now, lastResult: 'failed', reason })
  note(reason)

  return { ok: false, action: 'start-timed-out', reason }
}

// ── --self-test ────────────────────────────────────────────────────────────────
const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const HEADER = 'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME'
  const studio = 'RobloxStudio 57599 dev 37u IPv4 0x4b77 0t0 TCP 127.0.0.1:63913->127.0.0.1:34872 (ESTABLISHED)'
  const rojoSide = 'rojo 95252 dev 7u IPv4 0x208e 0t0 TCP 127.0.0.1:34872->127.0.0.1:63913 (ESTABLISHED)'
  const listen = 'rojo 95252 dev 6u IPv4 0x9538 0t0 TCP 127.0.0.1:34872 (LISTEN)'

  // ATTACHED — the case the socket half rests on.
  check('an attached Studio is detected', parseStudioConnections([HEADER, studio, rojoSide, listen].join('\n')).length, 1)
  check('the detected entry carries the pid', parseStudioConnections([HEADER, studio].join('\n'))[0].pid, '57599')
  check('truncated lsof output still matches', parseStudioConnections([HEADER, studio.replace('RobloxStudio', 'RobloxStu')].join('\n')).length, 1)

  // NOT ATTACHED — each of these would be a false positive.
  check('a listening server alone is not an attachment', parseStudioConnections([HEADER, listen].join('\n')).length, 0)
  check("rojo's own socket is not an attached Studio", parseStudioConnections([HEADER, rojoSide].join('\n')).length, 0)
  check('empty output is not an attachment', parseStudioConnections('').length, 0)
  check('a header with no rows is not an attachment', parseStudioConnections(HEADER).length, 0)
  check('null output is not an attachment', parseStudioConnections(null).length, 0)
  check(
    'a Studio attached to some OTHER port does not count',
    parseStudioConnections([HEADER, studio.replace('->127.0.0.1:34872', '->127.0.0.1:9999')].join('\n')).length,
    0
  )
  check(
    'a port that merely ENDS in the rojo port does not match',
    parseStudioConnections([HEADER, studio.replace('->127.0.0.1:34872', '->127.0.0.1:134872')].join('\n')).length,
    0
  )

  // The sessionId reader.
  check('a session id is pulled out of binary framing', parseSessionId(Buffer.from('\x82\xa9sessionId\xd9$4359af46-6699-420b-8f8e-a04080ba1647', 'latin1')), '4359af46-6699-420b-8f8e-a04080ba1647')
  check('no uuid means no session id', parseSessionId(Buffer.from('nothing here', 'latin1')), null)
  check('empty input means no session id', parseSessionId(null), null)

  // ── THE VERDICT GRID — all 24 cells, written out rather than computed ────────
  //
  // Computing the expectations from the same logic under test would assert only that the function
  // equals itself. Each row below is an independent claim about what this repo should DO in that state.
  const S1 = 'aaaaaaaa-1111-2222-3333-cccccccccccc'
  const S2 = 'bbbbbbbb-4444-5555-6666-dddddddddddd'

  const GRID = [
    // serving, attached, sessionId, blessed, expected
    [false, false, null, null, 'no-server'],
    [false, false, null, S1, 'no-server'],
    [false, false, null, S2, 'no-server'],
    [false, false, S1, null, 'no-server'],
    [false, false, S1, S1, 'no-server'],
    [false, false, S1, S2, 'no-server'],
    [false, true, null, null, 'no-server'],
    [false, true, null, S1, 'no-server'],
    [false, true, null, S2, 'no-server'],
    [false, true, S1, null, 'no-server'],
    [false, true, S1, S1, 'no-server'],
    [false, true, S1, S2, 'no-server'],
    [true, false, null, null, 'not-attached'],
    [true, false, null, S1, 'not-attached'],
    [true, false, null, S2, 'not-attached'],
    [true, false, S1, null, 'not-attached'],
    [true, false, S1, S1, 'not-attached'],
    [true, false, S1, S2, 'not-attached'],
    [true, true, null, null, 'unknown-session'],
    [true, true, null, S1, 'unknown-session'],
    [true, true, null, S2, 'unknown-session'],
    // The cell that caused the incident: server up, Studio holding a socket, but the session it was
    // blessed against is gone. MUST be red.
    [true, true, S1, S2, 'unblessed-session'],
    [true, true, S1, null, 'unblessed-session'],
    [true, true, S1, S1, 'ok']
  ]

  for (const [srv, att, sid, blessedId, expected] of GRID) {
    check(
      `verdict(serving=${srv}, attached=${att}, session=${sid ? (sid === S1 ? 'S1' : 'S2') : 'none'}, blessed=${blessedId ? (blessedId === S1 ? 'S1' : 'S2') : 'none'})`,
      syncVerdict({ serving: srv, attached: att, sessionId: sid, blessedSessionId: blessedId }),
      expected
    )
  }

  check('the grid covers the whole domain', GRID.length, 2 * 2 * 2 * 3)
  check('exactly one cell is ok', GRID.filter(row => row[4] === 'ok').length, 1)
  check('every verdict has a reason entry', [...new Set(GRID.map(row => row[4]))].every(v => v in VERDICT_REASONS), true)
  check('only ok has a null reason', VERDICT_REASONS.ok, null)

  // The cooldown, both directions.
  check('a first attempt is allowed', shouldAttempt({}, 1000), true)
  check('a failure inside the cooldown is not retried', shouldAttempt({ lastAttemptAt: 1000, lastResult: 'failed' }, 1000 + RETRY_COOLDOWN_MS - 1), false)
  check('a failure past the cooldown is retried', shouldAttempt({ lastAttemptAt: 1000, lastResult: 'failed' }, 1000 + RETRY_COOLDOWN_MS), true)
  check('a previous success never blocks a restart', shouldAttempt({ lastAttemptAt: 1000, lastResult: 'started' }, 1001), true)

  console.log(failures ? `  FAIL  ensure-rojo: ${ran - failures}/${ran}` : `  PASS  ensure-rojo: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

if (process.argv[1]?.endsWith('ensure-rojo.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  if (process.argv.includes('--bless')) {
    const sessionId = await readSessionId()

    if (!sessionId) {
      console.log('  cannot bless — the Rojo server did not report a session id. Is `rojo serve` running?')
      process.exit(1)
    }

    bless(sessionId)
    console.log(`  blessed rojo session ${sessionId}`)
    console.log('  This records that Studio was PROVEN to be syncing from this server. It is cleared')
    console.log('  automatically if the server restarts.')
    process.exit(0)
  }

  if (process.argv.includes('--status')) {
    const up = await serving()
    const sessionId = up ? await readSessionId() : null
    const attached = studioAttached()
    const verdict = syncVerdict({ serving: up, attached, sessionId, blessedSessionId: blessedSessionId() })

    console.log(`  serving on :${ROJO_PORT}: ${up ? 'yes' : 'NO'}`)
    console.log(`  studio attached:        ${attached ? 'yes' : 'NO'}`)
    console.log(`  server session:         ${sessionId ?? '(unknown)'}`)
    console.log(`  blessed session:        ${blessedSessionId() ?? '(none)'}`)
    console.log(`  verdict:                ${verdict}`)

    if (VERDICT_REASONS[verdict]) console.log(`\n  ${VERDICT_REASONS[verdict]}`)
    console.log(`  log: ${existsSync(LOG_PATH) ? LOG_PATH : '(none yet)'}`)
    process.exit(verdict === 'ok' ? 0 : 1)
  }

  // Hook mode. Drain stdin so the runtime never blocks on an unread pipe, then act and get out of the
  // way. NOTHING is written to stdout and the exit code is always 0: this hook's job is to remove a
  // missing server, never to have an opinion about the tool call it preceded.
  const raw = await readStdin().catch(() => '')

  let payload = {}

  try {
    payload = JSON.parse(raw)
  } catch {
    /* an unparseable payload is not a reason to skip starting the server */
  }

  // `hook-heartbeat.mjs` names any hook registered but never fired, because a hook that silently never
  // runs looks exactly like a hook with nothing to do.
  beat('ensure-rojo', payload)

  await ensure().catch(() => null)

  process.exit(0)
}
