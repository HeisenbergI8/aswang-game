#!/usr/bin/env node
// Every `OnServerEvent` handler must pass through AntiCheatService before it does anything.
//
//   node .claude/scripts/check-ratelimit.mjs [--json]
//   node .claude/scripts/check-ratelimit.mjs --self-test
//
// Spec §6.2 states the rule twice — "Every RemoteEvent is rate-limited and validates types, state,
// distance, and cooldown" — and §11 lists exploiters revealing the Aswang as a HIGH severity risk.
// A remote handler with no rate limit is a free firehose into server state: an exploiter calls
// RequestKill a thousand times a second and either finds the validation gap or takes the server down.
//
// The check is deliberately shallow. It asks ONE question — does this handler consult AntiCheat at
// all — because that is the question a static reader can answer honestly. Whether the validation is
// CORRECT is `exploit-auditor`'s job, and pretending a grep could decide it would be worse than not
// checking.
//
// It currently passes vacuously: no OnServerEvent handler exists yet. That is the intended shape of a
// good gate — it costs nothing today and fails the moment M2 wires the first remote without a limit.

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, listLuau, lineOf, readSource, report } from './lib/luau-source.mjs'

// The handler body is everything up to the matching `end)`. Rather than parse Luau, take a generous
// window: a handler longer than this has other problems.
const WINDOW = 1200

const GUARDED = /\bAntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)\b/

export const scan = files => {
  const findings = []

  for (const file of files) {
    if (!/(^|\/)src\/server\//.test(file)) continue

    const { raw, code } = readSource(file)
    const rawLines = raw.split('\n')

    for (const match of code.matchAll(/\.OnServerEvent:Connect\s*\(/g)) {
      const body = code.slice(match.index, match.index + WINDOW)

      if (GUARDED.test(body)) continue

      const line = lineOf(code, match.index)

      if (hasWaiver(rawLines, line, 'ratelimit')) continue

      findings.push({
        file,
        line,
        why: 'OnServerEvent handler with no AntiCheat rate limit',
        detail:
          'Spec §6.2: every remote is rate-limited and validates types, state, distance and cooldown. ' +
          'Call AntiCheatService.Allow(player, "<action>") first and return early when it refuses.'
      })
    }
  }

  return findings
}

const selfTest = () => {
  // The temp file lives under a real `src/server/` path because the path filter IS part of the
  // behaviour under test. Bypassing it would leave the filter — the thing most likely to be quietly
  // wrong — unexercised, and every case would still pass.
  const dir = mkdtempSync(join(tmpdir(), 'ratelimit-'))
  const serverDir = join(dir, 'src', 'server')
  const clientDir = join(dir, 'src', 'client')

  mkdirSync(serverDir, { recursive: true })
  mkdirSync(clientDir, { recursive: true })

  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag, onClient = false) => {
    ran += 1

    const path = join(onClient ? clientDir : serverDir, 'Module.luau')

    writeFileSync(path, source)

    const flagged = scan([path]).length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
  }

  // BLOCK
  check('an unguarded handler', 'Remotes.Get("RequestKill").OnServerEvent:Connect(function(player, target)\n\tkill(player, target)\nend)', true)
  check('a handler that only validates distance', 'ev.OnServerEvent:Connect(function(p, t)\n\tif dist(p, t) > 8 then return end\nend)', true)

  // ALLOW
  check(
    'a handler that consults AntiCheat',
    'ev.OnServerEvent:Connect(function(player, target)\n\tif not AntiCheat.Allow(player, "kill") then return end\n\tkill(player, target)\nend)',
    false
  )
  check(
    'the service-qualified form',
    'ev.OnServerEvent:Connect(function(p)\n\tif not AntiCheatService.Consume(p, "salt") then return end\nend)',
    false
  )
  check('a client-side listener', 'ev.OnClientEvent:Connect(function(phase) render(phase) end)', false, true)
  check('a comment about OnServerEvent', '-- every .OnServerEvent:Connect( must be rate limited\nlocal x = 1', false)
  check('a waived handler', 'ev.OnServerEvent:Connect(function(p) -- ratelimit-ok: read-only ping\n\tpong(p)\nend)', false)

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-ratelimit: ${ran - failures}/${ran}` : `  PASS  check-ratelimit: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-ratelimit.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(listLuau())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(findings, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  process.exit(report('ratelimit', findings, { note: 'every OnServerEvent consults AntiCheat' }))
}
