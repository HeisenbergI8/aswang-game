#!/usr/bin/env node
// Balance numbers live in `src/shared/Config.luau` and nowhere else.
//
//   node .claude/scripts/check-config.mjs [--json]
//   node .claude/scripts/check-config.mjs --self-test
//
// Spec §6.5: "Put every tunable number in one Config.lua. You will change these constantly during
// playtesting, and hunting magic numbers across 10 files is how a weekend disappears." The whole
// balance loop in §12 (M12: tune until neither side wins >60%) depends on there being one file to
// tune. A kill range hardcoded in MonsterService is a number that will be missed and will silently
// disagree with the one in Config.
//
// ── CALIBRATION IS THE HARD PART ───────────────────────────────────────────────
//
// A check that flags every numeric literal is a check somebody disables on day two, and then the rule
// is gone. So the threshold is drawn where a number stops looking like an index or an idiom and
// starts looking like a KNOB:
//
//   allowed: 0, 1, 2, -1, 0.5, and anything inside a `for i = 1, n` header or an array index
//   flagged: everything else — 8 (kill range), 30 (cooldown), 1.2 (transform time), 420 (duration)
//
// Comparison against Config is the giveaway shape and always allowed: `if elapsed > Config.X then`.

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, listLuau, lineOf, readSource, report } from './lib/luau-source.mjs'

const CONFIG_FILE = 'src/shared/Config.luau'

// Small integers that carry structure rather than balance.
const IDIOMATIC = new Set(['0', '1', '2', '-1', '0.5', '100'])

// Directories whose numbers are gameplay knobs. Types and Enums hold no tunables; Config IS the file.
const GOVERNED = /(^|\/)src\/(server|client)\//

export const scan = files => {
  const findings = []

  for (const file of files) {
    if (!GOVERNED.test(file)) continue

    const { raw, code } = readSource(file)
    const rawLines = raw.split('\n')

    for (const match of code.matchAll(/(?<![\w.])(-?\d+(?:\.\d+)?)(?![\w.])/g)) {
      const literal = match[1]

      if (IDIOMATIC.has(literal)) continue

      const line = lineOf(code, match.index)
      const text = rawLines[line - 1] ?? ''

      // A numeric for-loop header is control flow, not balance.
      if (/\bfor\s+\w+\s*=\s*[^,]+,/.test(text)) continue

      // A line that already reads from Config is comparing against the knob, not inventing one.
      if (/\bConfig\./.test(text)) continue

      if (hasWaiver(rawLines, line, 'config')) continue

      findings.push({
        file,
        line,
        why: `magic number ${literal}`,
        detail: `Spec §6.5: every tunable lives in ${CONFIG_FILE}. Move it there and read it, or waive with \`-- config-ok: <reason>\`.`
      })
    }
  }

  return findings
}

const selfTest = () => {
  const dir = mkdtempSync(join(tmpdir(), 'config-'))
  const serverDir = join(dir, 'src', 'server')
  const sharedDir = join(dir, 'src', 'shared')

  mkdirSync(serverDir, { recursive: true })
  mkdirSync(sharedDir, { recursive: true })

  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag, inShared = false) => {
    ran += 1

    const path = join(inShared ? sharedDir : serverDir, 'Module.luau')

    writeFileSync(path, source)

    const flagged = scan([path]).length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
  }

  // BLOCK — each of these is a knob that would go missing at balance time.
  check('a hardcoded kill range', 'if distance <= 8 then kill() end', true)
  check('a hardcoded cooldown', 'lastKill = now + 30', true)
  check('a hardcoded transform time', 'task.wait(1.2)', true)
  check('a hardcoded round duration', 'local remaining = 420 - elapsed', true)

  // ALLOW — the larger half, on purpose.
  check('reading the knob from Config', 'if distance <= Config.Monster.KillRange then kill() end', false)
  check('comparing against Config with arithmetic', 'local remaining = Config.Round.Duration - elapsed', false)
  check('a zero initialiser', 'local count = 0', false)
  check('an increment', 'count += 1', false)
  check('an array index', 'local first = list[1]', false)
  check('a numeric for loop', 'for i = 1, 12 do spawn(i) end', false)
  check('a percentage-style half', 'local half = total * 0.5', false)
  check('a number inside a comment', '-- the kill range is 8 studs\nlocal x = Config.Monster.KillRange', false)
  check('a number inside a string', 'print("waited 30 seconds")', false)
  check('Config.luau itself', 'local Config = { Round = { Duration = 420 } }', false, true)
  check('a waived literal', 'local frames = 60 -- config-ok: RunService heartbeat rate, not balance', false)

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-config: ${ran - failures}/${ran}` : `  PASS  check-config: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-config.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(listLuau())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(findings, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  process.exit(report('config', findings, { note: 'balance stays data-driven' }))
}
