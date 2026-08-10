#!/usr/bin/env node
// Makes the gate runnable. Every other check assumes five binaries and one generated file exist;
// this is the one that establishes them, so a fresh clone can go from `git clone` to `npm run verify`
// without anybody remembering a setup step.
//
//   node .claude/scripts/check-toolchain.mjs [--quiet] [--offline]
//   node .claude/scripts/check-toolchain.mjs --self-test
//
// ── WHAT IT ESTABLISHES ────────────────────────────────────────────────────────
//
//   rokit tools     rojo, stylua, selene, luau-lsp, lune — pinned in rokit.toml, so the gate behaves
//                   identically on any machine. A missing one is repaired with `rokit install`.
//   globalTypes     the Roblox API surface as Luau type definitions. WITHOUT IT, `luau-lsp analyze`
//                   still exits 0 while reporting `Unknown global 'warn'` on every line — a green
//                   result from a checker that has been told nothing about the platform. That is the
//                   worst failure shape available: silent, total, and it looks like success.
//   sourcemap.json  the filesystem→DataModel mapping, regenerated from default.project.json. Stale
//                   means `require(script.Parent.X)` resolves to the wrong file or none at all.
//
// globalTypes and sourcemap are both BUILD INPUTS, not source: gitignored, regenerated on demand.

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'

export const DEFS_DIR = '.luau-defs'
export const DEFS_PATH = `${DEFS_DIR}/globalTypes.d.luau`
export const SOURCEMAP = 'sourcemap.json'
const PROJECT = 'default.project.json'

const DEFS_URL = 'https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau'

// Roblox ships API changes weekly. Older than this and the definitions are worth refreshing — but
// staleness only WARNS, because a plane with no wifi is not a reason to fail the build.
const DEFS_STALE_DAYS = 30

const TOOLS = ['rojo', 'stylua', 'selene', 'luau-lsp', 'lune']

const run = (file, args) => {
  try {
    return { ok: true, out: execFileSync(file, args, { encoding: 'utf8', stdio: 'pipe' }) }
  } catch (error) {
    return { ok: false, out: `${error.stdout ?? ''}${error.stderr ?? ''}` }
  }
}

export const missingTools = () => TOOLS.filter(tool => !run(tool, ['--version']).ok)

// A definitions file that exists but is truncated is worse than one that is absent: `analyze` loads
// it, resolves half the API, and reports errors about correct code. Size is a crude but sufficient
// integrity signal — the real file is ~1MB and nothing legitimate is under 100KB.
const DEFS_MIN_BYTES = 100_000

export const defsState = () => {
  if (!existsSync(DEFS_PATH)) return { ok: false, reason: 'absent' }

  const { size, mtimeMs } = statSync(DEFS_PATH)

  if (size < DEFS_MIN_BYTES) return { ok: false, reason: `truncated (${size} bytes)` }

  const ageDays = (Date.now() - mtimeMs) / 86_400_000

  return { ok: true, stale: ageDays > DEFS_STALE_DAYS, ageDays: Math.round(ageDays) }
}

const fetchDefs = async () => {
  const response = await fetch(DEFS_URL, { signal: AbortSignal.timeout(30_000) })

  if (!response.ok) throw new Error(`HTTP ${response.status}`)

  const text = await response.text()

  if (text.length < DEFS_MIN_BYTES) throw new Error(`response too small (${text.length} bytes)`)

  mkdirSync(DEFS_DIR, { recursive: true })
  writeFileSync(DEFS_PATH, text)

  return text.length
}

// The sourcemap is regenerated whenever any project file is newer than it. Cheap (~50ms) and it
// removes a whole class of "the analyzer cannot find the module I just added".
export const sourcemapStale = () => {
  if (!existsSync(SOURCEMAP)) return true

  const mapTime = statSync(SOURCEMAP).mtimeMs

  if (statSync(PROJECT).mtimeMs > mapTime) return true

  // Only the tree shape matters, and Rojo derives it from directory contents — so a directory mtime
  // is the right signal and walking every file would be wasted work.
  const dirs = ['src', 'src/shared', 'src/server', 'src/server/Services', 'src/client', 'src/client/Controllers']

  return dirs.some(dir => existsSync(dir) && statSync(dir).mtimeMs > mapTime)
}

export const regenerateSourcemap = () => run('rojo', ['sourcemap', PROJECT, '--output', SOURCEMAP])

const main = async () => {
  const quiet = process.argv.includes('--quiet')
  const offline = process.argv.includes('--offline')
  const say = message => {
    if (!quiet) console.log(message)
  }

  const missing = missingTools()

  if (missing.length) {
    console.error(`  FAIL  toolchain: ${missing.join(', ')} not on PATH`)
    console.error('        Run `rokit install` — every tool is pinned in rokit.toml so the gate is')
    console.error('        identical on every machine. Install rokit itself from rojo-rbx/rokit.')

    return 1
  }

  let defs = defsState()

  if (!defs.ok) {
    if (offline) {
      console.error(`  FAIL  toolchain: ${DEFS_PATH} is ${defs.reason} and --offline was given`)
      console.error('        Without it `luau-lsp analyze` exits 0 while knowing nothing about Roblox.')

      return 1
    }

    say(`  …fetching Roblox API definitions (${defs.reason})`)

    try {
      const bytes = await fetchDefs()

      say(`  …wrote ${DEFS_PATH} (${Math.round(bytes / 1024)} KB)`)
      defs = defsState()
    } catch (error) {
      console.error(`  FAIL  toolchain: could not fetch ${DEFS_PATH} — ${error.message}`)
      console.error(`        Fetch it by hand from ${DEFS_URL}`)

      return 1
    }
  }

  if (sourcemapStale()) {
    const result = regenerateSourcemap()

    if (!result.ok) {
      console.error('  FAIL  toolchain: rojo sourcemap failed')
      console.error(result.out.trim())

      return 1
    }

    say('  …regenerated sourcemap.json')
  }

  if (defs.stale) {
    say(`  warn  ${DEFS_PATH} is ${defs.ageDays} days old — delete it to refresh the Roblox API surface`)
  }

  say(`- toolchain: ok (${TOOLS.length} tools, definitions, sourcemap)`)

  return 0
}

const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  // The decision logic, exercised without touching the network. A self-test that needs a live fetch
  // fails on a train and then gets deleted.
  const classify = state => (!state.ok ? 'repair' : state.stale ? 'warn' : 'ok')

  check('absent definitions are repaired', classify({ ok: false, reason: 'absent' }), 'repair')
  check('truncated definitions are repaired', classify({ ok: false, reason: 'truncated (12 bytes)' }), 'repair')
  check('stale definitions only warn', classify({ ok: true, stale: true, ageDays: 90 }), 'warn')
  check('fresh definitions pass', classify({ ok: true, stale: false, ageDays: 2 }), 'ok')

  // Truncation must be caught: a half-written file is the failure that produces confident wrong
  // answers, where an absent one produces an obvious one.
  check('the integrity floor is above any plausible partial write', DEFS_MIN_BYTES >= 100_000, true)
  check('every tool the gate shells out to is listed', TOOLS.includes('luau-lsp') && TOOLS.includes('lune'), true)

  console.log(failures ? `  FAIL  check-toolchain: ${ran - failures}/${ran}` : `  PASS  check-toolchain: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-toolchain.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  process.exit(await main())
}
