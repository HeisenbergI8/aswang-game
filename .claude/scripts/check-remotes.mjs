#!/usr/bin/env node
// Every remote used anywhere must be DECLARED in `src/shared/Remotes.luau`, and must be used in the
// direction it was declared for.
//
//   node .claude/scripts/check-remotes.mjs [--json]
//   node .claude/scripts/check-remotes.mjs --self-test
//
// ── WHY THIS IS THE FIRST CHECK TO REACH FOR ───────────────────────────────────
//
// `Remotes.Get(name)` resolves through `folder:WaitForChild(name)` on the client. A name the server
// never created does not error — IT HANGS FOREVER. The screen loads, nothing happens, no output, no
// stack trace. That is the most expensive failure shape in this repo because it looks like a
// gameplay bug and is actually a typo, and no compiler catches it: both sides are just strings.
//
// The direction rules are the second half:
//
//   DOWN events (server → client) may be fired only with :FireClient / :FireAllClients, on the SERVER,
//   and listened to with .OnClientEvent on the CLIENT.
//   UP events (client → server) are the mirror.
//
// A client that calls `:FireServer("PhaseChanged")` is not a compile error either; it is a remote
// nobody is listening on, and it fails silently in exactly the same way.

import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, listLuau, lineOf, readSource, report } from './lib/luau-source.mjs'

const REMOTES_FILE = 'src/shared/Remotes.luau'

// Parses the two declaration lists out of Remotes.luau. Reading the file rather than duplicating the
// names here is the point: a second copy of the list is a second thing to forget to update, and it
// would go stale in exactly the direction that makes this check pass when it should fail.
export const declared = source => {
  const listOf = name => {
    const start = source.indexOf(`local ${name} = {`)

    if (start === -1) return []

    const end = source.indexOf('\n}', start)
    const body = source.slice(start, end === -1 ? source.length : end)

    return [...body.matchAll(/["']([\w]+)["']/g)].map(match => match[1])
  }

  return { down: listOf('EVENTS_DOWN'), up: listOf('EVENTS_UP') }
}

export const scan = (files, lists) => {
  const findings = []
  const known = new Set([...lists.down, ...lists.up])
  const used = new Set()

  for (const file of files) {
    if (file.endsWith('Remotes.luau')) continue

    const { raw, withStrings } = readSource(file)
    const rawLines = raw.split('\n')
    const isClient = /(^|\/)src\/client\//.test(file)
    const isServer = /(^|\/)src\/server\//.test(file)

    const add = (index, why, detail) => {
      const line = lineOf(withStrings, index)

      if (hasWaiver(rawLines, line, 'remotes')) return

      findings.push({ file, line, why, detail })
    }

    //  The trailing context is a LOOKAHEAD, and that is not a style choice.
    //
    //  It used to be a plain group — `\)([\s\S]{0,40})` — which `matchAll` CONSUMES. Two
    //  `Remotes.Get(...)` calls within 40 characters of each other therefore produced ONE match: the
    //  second was inside the first's swallowed context and never scanned. Adjacent declarations are the
    //  normal way to write this file, so the blind spot was the common case rather than a corner.
    //
    //  Every direction check below runs off this loop, so the cost was not a miscount in the
    //  "declared but not yet wired" note — it was `check:remotes` silently failing to see a client
    //  firing a DOWN event, which is the exact class of bug this script exists to catch. Found when
    //  `PlayerKilled` reported as unwired while being demonstrably fired and listened to.
    //
    //  `(?=(...))` matches the same 40 characters without advancing lastIndex, so the next Get is still
    //  there to be found. The capture group inside a lookahead still populates `match[2]`.
    for (const match of withStrings.matchAll(/Remotes\.Get\(\s*["']([\w]+)["']\s*\)(?=([\s\S]{0,40}))/g)) {
      const [, name, after] = match

      used.add(name)

      if (!known.has(name)) {
        add(
          match.index,
          `remote "${name}" is not declared in ${REMOTES_FILE}`,
          'On the client this resolves through WaitForChild and HANGS FOREVER — no error, no output. Add it to EVENTS_DOWN or EVENTS_UP.'
        )
        continue
      }

      const isDown = lists.down.includes(name)
      const fires = /:\s*Fire(Server|Client|AllClients)/.exec(after)
      // `[.:]`, not `:` — the signal is a PROPERTY access (`.OnServerEvent`), not a method call. The
      // colon-only form matched nothing, so every direction violation on a listener read as ALLOW.
      const listens = /[.:]\s*(OnServerEvent|OnClientEvent)/.exec(after)

      if (fires) {
        const kind = fires[1]

        if (isDown && kind === 'Server') {
          add(match.index, `"${name}" is a DOWN event but is fired with :FireServer`, 'Nothing listens on the server for it.')
        }

        if (!isDown && kind !== 'Server') {
          add(match.index, `"${name}" is an UP event but is fired with :Fire${kind}`, 'Nothing listens on the client for it.')
        }

        if (isDown && isClient) {
          add(match.index, `client code fires the DOWN event "${name}"`, 'Only the server may fire a server→client remote.')
        }

        if (!isDown && isServer) {
          add(match.index, `server code fires the UP event "${name}"`, 'Only the client may fire a client→server remote.')
        }
      }

      if (listens) {
        const kind = listens[1]

        if (isDown && kind === 'OnServerEvent') {
          add(match.index, `"${name}" is a DOWN event but is listened to with OnServerEvent`, 'No client fires it.')
        }

        if (!isDown && kind === 'OnClientEvent') {
          add(match.index, `"${name}" is an UP event but is listened to with OnClientEvent`, 'No server fires it.')
        }
      }
    }
  }

  return { findings, used, known }
}

// Declared-but-unused is reported as a NOTE, never a failure. The scaffold declares the whole network
// surface up front on purpose — that is what makes it auditable at a glance — so failing on it would
// mean the repo is red until the last milestone lands.
const unused = (known, used) => [...known].filter(name => !used.has(name))

const selfTest = () => {
  const dir = mkdtempSync(join(tmpdir(), 'remotes-'))
  const lists = { down: ['PhaseChanged', 'RoundEnded'], up: ['RequestKill'] }

  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag, name = 'src/server/X.luau') => {
    ran += 1

    const path = join(dir, name)

    mkdirSync(join(path, '..'), { recursive: true })
    writeFileSync(path, source)

    const { findings } = scan([path], lists)
    const flagged = findings.length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
    for (const finding of findings) console.log(`        ${finding.why}`)
  }

  // BLOCK — every one of these hangs or no-ops silently at runtime.
  check('an undeclared remote', 'Remotes.Get("PhasChanged"):FireAllClients(x)', true)
  check('a DOWN event fired to the server', 'Remotes.Get("PhaseChanged"):FireServer(x)', true)
  check('an UP event broadcast', 'Remotes.Get("RequestKill"):FireAllClients(x)', true)
  check('the client firing a DOWN event', 'Remotes.Get("PhaseChanged"):FireAllClients(x)', true, 'src/client/Y.luau')
  check('a DOWN event listened to on the server', 'Remotes.Get("PhaseChanged").OnServerEvent:Connect(f)', true)

  // ALLOW
  check('a declared DOWN broadcast from the server', 'Remotes.Get("PhaseChanged"):FireAllClients(phase)', false)
  check('a declared DOWN event to one player', 'Remotes.Get("RoundEnded"):FireClient(player, payload)', false)
  check('the server listening for an UP event', 'Remotes.Get("RequestKill").OnServerEvent:Connect(f)', false)
  check('the client firing an UP event', 'Remotes.Get("RequestKill"):FireServer(target)', false, 'src/client/Y.luau')
  check('the client listening for a DOWN event', 'Remotes.Get("PhaseChanged").OnClientEvent:Connect(f)', false, 'src/client/Y.luau')
  check('a remote captured into a variable for later use', 'local ev = Remotes.Get("PhaseChanged")\nev:FireAllClients(x)', false)
  check('a name mentioned only in a comment', '-- "PhasChanged" was the old spelling\nlocal x = 1', false)
  check('a waived deliberate direction break', 'Remotes.Get("PhaseChanged"):FireServer(x) -- remotes-ok: studio-only probe', false)

  //  ADJACENCY. Every case above uses exactly ONE Remotes.Get, which is precisely why this scanner
  //  spent its whole life blind to the second one: the trailing context group was consumed, so a Get
  //  within 40 characters of a preceding Get was never scanned at all. These are the regression
  //  guards, and they must stay in both directions.
  check(
    'a violation on the Get immediately after another',
    'Remotes.Get("PhaseChanged").OnClientEvent:Connect(f)\nRemotes.Get("PhaseChanged"):FireAllClients(x)',
    true,
    'src/client/Y.luau'
  )
  check(
    'a violation three Gets deep',
    'local a = Remotes.Get("PhaseChanged")\nlocal b = Remotes.Get("RoundEnded")\nRemotes.Get("PhaseChanged"):FireServer(x)',
    true
  )
  check(
    'two adjacent declarations, both correct',
    'local a = Remotes.Get("PhaseChanged")\nlocal b = Remotes.Get("RoundEnded")',
    false
  )

  //  The same bug seen from the other side. `used` drives the "declared but not yet wired" note, and
  //  it is what first exposed this: PlayerKilled was fired AND listened to and still reported unwired.
  //  Asserted directly rather than through `check`, which only sees findings.
  {
    ran += 1

    const path = join(dir, 'src/server/Adjacent.luau')

    mkdirSync(join(path, '..'), { recursive: true })
    writeFileSync(path, 'local a = Remotes.Get("PhaseChanged")\nlocal b = Remotes.Get("RoundEnded")')

    const { used } = scan([path], lists)

    if (!used.has('PhaseChanged') || !used.has('RoundEnded')) {
      failures += 1
      console.log(`  FAIL  both adjacent Gets are counted as used — got [${[...used].join(', ')}]`)
    }
  }

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-remotes: ${ran - failures}/${ran}` : `  PASS  check-remotes: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-remotes.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  let lists

  try {
    lists = declared(readSource(REMOTES_FILE).withStrings)
  } catch {
    console.error(`  FAIL  cannot read ${REMOTES_FILE} — the network surface has no single declaration point`)
    process.exit(1)
  }

  if (!lists.down.length && !lists.up.length) {
    console.error(`  FAIL  ${REMOTES_FILE} declares no events — EVENTS_DOWN / EVENTS_UP were not parsed`)
    process.exit(1)
  }

  const { findings, used, known } = scan(listLuau(), lists)
  const idle = unused(known, used)

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ findings, unused: idle }, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  const code = report('remotes', findings, {
    note: `${known.size} declared, ${used.size} wired`
  })

  if (!findings.length && idle.length) {
    console.log(`        ${idle.length} declared but not yet wired: ${idle.join(', ')}`)
  }

  process.exit(code)
}
