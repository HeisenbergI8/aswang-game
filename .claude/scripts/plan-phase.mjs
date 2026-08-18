#!/usr/bin/env node
// plan-phase.mjs — read ONE phase of a plan instead of the whole document.
//
// WHY THIS EXISTS
// The plan document is the executable contract, and it is large: the c13–c16 plan is 224KB — roughly
// 57k tokens — across 8 phases. But nothing ever needs all of it at once. `implement-plan` works one
// phase at a time; the auditor traces one phase's steps at a time; the playtester verifies one phase.
// Loading the whole document to do a seventh of the work costs about 8x what the work in front of you
// needs, and it is re-paid on every turn of that agent's run and again by every agent launched beside it.
//
// This SLICES the canonical document rather than splitting it on disk. `verify-plan.mjs`,
// `next-phase.mjs` and `goal-check.mjs` keep reading exactly the file they always read, the plan stays
// one reviewable artifact in one diff, and none of the seven existing plans need migrating.
//
// usage:
//   node .claude/scripts/plan-phase.mjs <plan-dir|plan.md>            list phases with sizes + references
//   node .claude/scripts/plan-phase.mjs <plan-dir|plan.md> <N>        print phase N only
//   node .claude/scripts/plan-phase.mjs <plan-dir|plan.md> <N> --with-preamble
//                                                                     ...prefixed by everything above Phase 1
//
// exit: 0 ok · 1 unreadable plan, no phases, or unknown phase number

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

// Mirrors verify-plan.mjs's resolvePlanFile. Duplicated rather than imported on purpose: verify-plan is
// the load-bearing grader and this is a read-only convenience, so it does not get to widen that file's
// export surface. If the rule changes there, change it here — `plans` in harness-selftest covers both.
const resolvePlanFile = planPath => {
  let stats
  try {
    stats = statSync(planPath)
  } catch {
    return { error: `cannot read ${planPath}` }
  }
  if (!stats.isDirectory()) return { file: planPath }

  const candidates = readdirSync(planPath).filter(
    name => name.endsWith('.md') && name !== 'implementation-log.md' && name !== 'verification.md',
  )
  if (candidates.length === 0) {
    return { error: `${planPath} is a plan DIRECTORY with no plan document in it.` }
  }
  const named = candidates.find(name => name.endsWith('-plan.md')) ?? candidates[0]
  return { file: join(planPath, named) }
}

// A phase runs from its `### Phase N:` heading to the next `### Phase N:` or the next h2 — whichever
// comes first. It must NOT end at an arbitrary h3: phase bodies legitimately contain them (Phase 4 of
// the c13 plan carries "### Why a glow everyone can see is not a third role-carrying remote"). Headings
// inside fenced code are ignored, because a plan may quote its own shape in an example.
export const parsePhases = markdown => {
  const lines = markdown.split('\n')
  const phases = []
  let fenced = false

  lines.forEach((line, i) => {
    if (/^\s*```/.test(line)) fenced = !fenced
    if (fenced) return

    const phase = line.match(/^###\s+Phase\s+(\d+)\s*:\s*(.+?)\s*$/)
    if (phase) {
      if (phases.length > 0) phases[phases.length - 1].end = i - 1
      phases.push({ number: Number(phase[1]), title: phase[2], start: i, end: lines.length - 1 })
      return
    }
    // Any h2 closes the phase section — "## 3. Related Files" is where the last phase stops.
    if (/^##[^#]/.test(line) && phases.length > 0 && phases[phases.length - 1].end === lines.length - 1) {
      phases[phases.length - 1].end = i - 1
    }
  })

  return { lines, phases }
}

const est = text => Math.round(text.length / 4)

const sliceOf = (lines, phase) => lines.slice(phase.start, phase.end + 1).join('\n')

// Which reference reviews does this phase actually need? The architect writes a `references/` directory
// per plan — 16 files, ~22k tokens, on the c13 plan. Reading all of them to implement one phase is the
// same waste as reading the whole plan.
//
// Plans do NOT cite reviews by filename — checked across all seven, zero mentions — so matching on the
// name finds nothing. The durable link is the step's `**File:**` line: the architect names a review after
// the source file it reviewed (`RoundService.luau` → `RoundService-review.luau`), so the phase's own file
// targets resolve to its reviews. A phase whose files were never reviewed correctly lists none.
export const referenceStems = slice => {
  const stems = new Set()
  for (const line of slice.split('\n')) {
    const file = line.match(/^\*\*File:\*\*\s*(.+?)\s*$/)
    if (!file) continue
    for (const target of file[1].split(',')) {
      const path = target.replace(/[`\s]/g, '')
      if (!path) continue
      const base = path.slice(path.lastIndexOf('/') + 1)
      stems.add(base.replace(/\.[^.]+$/, ''))
    }
  }
  return stems
}

const referencesFor = (planFile, slice) => {
  const dir = join(planFile.slice(0, planFile.lastIndexOf('/')), 'references')
  let names
  try {
    names = readdirSync(dir)
  } catch {
    return []
  }

  const stems = referenceStems(slice)

  return names.filter(name => {
    const stem = name.replace(/-review\.[^.]+$/, '')
    return stems.has(stem) || slice.includes(name)
  })
}

const main = () => {
  const [planPath, phaseArg] = process.argv.slice(2)
  const withPreamble = process.argv.includes('--with-preamble')

  if (!planPath) {
    console.error('usage: plan-phase.mjs <plan-dir|plan.md> [N] [--with-preamble]')
    return 1
  }

  const resolved = resolvePlanFile(planPath)
  if (resolved.error) {
    console.error(`FAIL  ${resolved.error}`)
    return 1
  }

  let markdown
  try {
    markdown = readFileSync(resolved.file, 'utf8')
  } catch {
    console.error(`FAIL  cannot read ${resolved.file}`)
    return 1
  }

  const { lines, phases } = parsePhases(markdown)
  if (phases.length === 0) {
    console.error(
      `FAIL  no "### Phase N: title" headings found in ${resolved.file}\n` +
        '      A plan the architect wrote should have them; if this is a verification-only directory, ' +
        'there is no phase to slice.',
    )
    return 1
  }

  // No phase number: the index. Cheap to read, and it is what tells an agent which phase to ask for.
  if (phaseArg === undefined) {
    console.log(`${resolved.file}`)
    console.log(`  whole document: ${est(markdown)} tokens (est), ${phases.length} phases\n`)
    for (const phase of phases) {
      const slice = sliceOf(lines, phase)
      const steps = (slice.match(/^####\s+Step\s+\d+\.\d+/gm) ?? []).length
      const refs = referencesFor(resolved.file, slice)
      console.log(
        `  Phase ${phase.number}: ${phase.title}\n` +
          `    lines ${phase.start + 1}-${phase.end + 1} · ${est(slice)} tokens (est) · ${steps} steps` +
          (refs.length ? `\n    references: ${refs.join(', ')}` : ''),
      )
    }
    console.log(`\n  read one with:  npm run plan:phase -- ${planPath} <N>`)
    return 0
  }

  const wanted = Number(phaseArg)
  const phase = phases.find(p => p.number === wanted)
  if (!phase) {
    console.error(
      `FAIL  no Phase ${phaseArg} in ${resolved.file} — it has ${phases.map(p => p.number).join(', ')}`,
    )
    return 1
  }

  if (withPreamble && phases[0].start > 0) {
    console.log(lines.slice(0, phases[0].start).join('\n'))
  }
  console.log(sliceOf(lines, phase))
  return 0
}

// ── SELF-TEST ─────────────────────────────────────────────────────────────────
//
// Both directions. The ones that matter are the NEGATIVES: a slicer that swallows the next phase, or
// that breaks a phase at an ordinary `###` subsection, hands an implementer a truncated contract and
// nothing downstream notices — `verify-plan` still grades the whole document and still passes.
const selfTest = () => {
  let ran = 0
  let failures = 0
  const check = (name, actual, expected) => {
    ran++
    const got = JSON.stringify(actual)
    const want = JSON.stringify(expected)
    if (got !== want) {
      failures++
      console.error(`  FAIL  plan-phase: ${name}\n        expected ${want}\n        got      ${got}`)
    }
  }
  const shape = markdown =>
    parsePhases(markdown).phases.map(p => ({ n: p.number, title: p.title, start: p.start, end: p.end }))

  check('no phase headings yields no phases', shape('# Plan\n\nsome prose\n'), [])

  check('a lone phase runs to end of document', shape('### Phase 1: only\na\nb'), [
    { n: 1, title: 'only', start: 0, end: 2 },
  ])

  check(
    'a phase ends the line before the next phase',
    shape('### Phase 1: first\na\n### Phase 2: second\nb'),
    [
      { n: 1, title: 'first', start: 0, end: 1 },
      { n: 2, title: 'second', start: 2, end: 3 },
    ],
  )

  // The c13 plan's Phase 4 carries "### Why a glow everyone can see is not..." — breaking there would
  // cut the phase in half and silently drop its remaining steps.
  check(
    'an ordinary ### subsection stays INSIDE its phase',
    shape('### Phase 1: first\na\n### Some Aside\nb\n### Phase 2: second\nc'),
    [
      { n: 1, title: 'first', start: 0, end: 3 },
      { n: 2, title: 'second', start: 4, end: 5 },
    ],
  )

  check('an h2 closes the last phase', shape('### Phase 1: first\na\n## 3. Related Files\nb'), [
    { n: 1, title: 'first', start: 0, end: 1 },
  ])

  check(
    'a phase heading inside a code fence is not a phase',
    shape('### Phase 1: real\na\n\n```\n### Phase 9: fake\n```\n'),
    [{ n: 1, title: 'real', start: 0, end: 6 }],
  )

  check('phase numbers are not assumed contiguous', shape('### Phase 2: two\na\n### Phase 7: seven\nb'), [
    { n: 2, title: 'two', start: 0, end: 1 },
    { n: 7, title: 'seven', start: 2, end: 3 },
  ])

  // Reference mapping — the link is the step's **File:** line, not a filename mention.
  check('a File: line yields the source basename as a stem', [...referenceStems(
    '**File:** `src/server/Services/RoundService.luau`',
  )], ['RoundService'])

  check('a comma-separated File: line yields every stem', [...referenceStems(
    '**File:** `src/shared/Config.luau`, `src/shared/Types.luau`',
  )], ['Config', 'Types'])

  check('a dotted filename keeps everything before the LAST dot', [...referenceStems(
    '**File:** `tests/config.test.luau`',
  )], ['config.test'])

  check('prose that merely names a file is not a File: line', [...referenceStems(
    'we also touch `src/shared/Config.luau` here',
  )], [])

  console.log(
    failures ? `  FAIL  plan-phase: ${ran - failures}/${ran}` : `  PASS  plan-phase: ${ran}/${ran} cases`,
  )
  return failures ? 1 : 0
}

if (process.argv.includes('--self-test')) process.exit(selfTest())

if (process.argv[1]?.endsWith('plan-phase.mjs')) {
  process.exit(main())
}
