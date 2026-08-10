#!/usr/bin/env node
// The lesson store: a small, deliberately-capped set of things learned the hard way in THIS repo.
//
// Design constraints that produced this shape:
//
//   1. Lessons live in-repo, in `.claude/lessons/`, which is TRACKED here — so a lesson shows up in a
//      diff and can be argued with, rather than accumulating invisibly.
//
//   2. A knowledge base nobody reads is a log. Retrieval is therefore a HOOK, not a habit: `inject`
//      runs on UserPromptSubmit and pushes matching lessons into context whether or not the model
//      remembers this file exists.
//
//   3. Leanness is enforced by `audit`, which is wired into `npm run verify`. A cap that is only a
//      comment is not a cap.
//
// Subcommands:
//   inject   UserPromptSubmit hook — emit matching lessons as additionalContext
//   nudge    Stop hook — after a struggle-then-recover turn, suggest recording a lesson
//   audit    exit non-zero on cap breach / malformed file / duplicate id
//   list     human-readable table
//   stats    usage counters, to make pruning a data decision

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const DIR = '.claude/lessons'
const STATE = '.claude/.lessons-state.json'
const LEDGER = '.claude/.run-ledger.json'

// The cap is the whole point. Past ~40 the index stops being scannable and injection stops being
// cheap, so growth beyond it must be paid for by consolidating or pruning something else.
const MAX_LESSONS = 40
const MAX_BODY_LINES = 25

// A lesson is retrieved by keyword. Terms this common match everything, which would inject the whole
// store on every prompt and train the reader to ignore it.
const STOP_TERMS = new Set(['the', 'a', 'is', 'in', 'to', 'and', 'or', 'of', 'it', 'this', 'that', 'code', 'file', 'game'])

const REQUIRED = ['id', 'trigger', 'scope', 'learned']

// ---------------------------------------------------------------------------- io

const readState = () => {
  try {
    return JSON.parse(readFileSync(STATE, 'utf8'))
  } catch {
    return { sessions: {}, hits: {} }
  }
}

const writeState = state => {
  try {
    mkdirSync('.claude', { recursive: true })
    writeFileSync(STATE, `${JSON.stringify(state)}\n`)
  } catch {
    /* state is an optimisation, never a hard dependency */
  }
}

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

// ---------------------------------------------------------------------------- parsing

// Deliberately not YAML. Three scalar fields and a comma list do not justify a dependency, and a
// parser that cannot throw on exotic input is a parser that cannot break the hook.
export const parseLesson = (name, raw) => {
  const match = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(raw)

  if (!match) return { name, error: 'missing frontmatter block' }

  const meta = {}

  for (const line of match[1].split('\n')) {
    const separator = line.indexOf(':')

    if (separator === -1) continue

    meta[line.slice(0, separator).trim()] = line.slice(separator + 1).trim()
  }

  const missing = REQUIRED.filter(key => !meta[key])

  if (missing.length) return { name, error: `missing frontmatter: ${missing.join(', ')}` }

  const body = match[2].trim()

  const terms = meta.trigger
    .split(',')
    .map(term => term.trim().toLowerCase())
    .filter(term => term && !STOP_TERMS.has(term))

  return {
    name,
    id: meta.id,
    scope: meta.scope,
    learned: meta.learned,
    evidence: meta.evidence ?? '',

    // Optional. `encoded: <path>` names the guard or doc that replaced this lesson; `encodedAtHits:`
    // records the hit count when that happened, so "quiet since" is measurable.
    encoded: meta.encoded ?? '',
    encodedAtHits: meta.encodedAtHits ?? '',
    terms,
    body,
    bodyLines: body.split('\n').length,

    summary: (body.split('\n').find(line => line.startsWith('**Lesson:**')) ?? body.split('\n')[0] ?? '')
      .replace('**Lesson:**', '')
      .trim()
  }
}

const loadLessons = () => {
  if (!existsSync(DIR)) return []

  return readdirSync(DIR)
    .filter(name => name.endsWith('.md'))
    .sort()
    .map(name => parseLesson(name, readFileSync(join(DIR, name), 'utf8')))
}

// ---------------------------------------------------------------------------- matching

// Substring rather than word matching, on purpose: "remote" should match "remotes", "transform"
// should match "transforming". False positives cost a few hundred tokens; false negatives cost the
// entire mechanism, because a lesson that fails to surface is a lesson that was never written.
export const matches = (lesson, text) => lesson.terms.some(term => text.includes(term))

// ---------------------------------------------------------------------------- inject

const inject = async () => {
  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    /* fall through to an empty prompt — the index still injects once */
  }

  const lessons = loadLessons().filter(lesson => !lesson.error)

  if (lessons.length === 0) process.exit(0)

  const prompt = String(payload?.prompt ?? '').toLowerCase()
  const session = String(payload?.session_id ?? 'unknown')
  const state = readState()

  const firstOfSession = !state.sessions[session]

  state.sessions[session] = true

  const hits = lessons.filter(lesson => prompt && matches(lesson, prompt))

  for (const lesson of hits) state.hits[lesson.id] = (state.hits[lesson.id] ?? 0) + 1

  const sessionIds = Object.keys(state.sessions)

  if (sessionIds.length > 200) for (const id of sessionIds.slice(0, sessionIds.length - 200)) delete state.sessions[id]

  writeState(state)

  const sections = []

  if (firstOfSession) {
    sections.push(
      `## Lessons on file (${lessons.length}/${MAX_LESSONS})\n\n` +
        `Hard-won specifics about this repo. Full text is injected when a prompt matches a lesson's ` +
        `triggers; read one directly from \`${DIR}/\` if the summary looks relevant.\n\n` +
        lessons.map(lesson => `- **${lesson.id}** (${lesson.scope}) — ${lesson.summary}`).join('\n')
    )
  }

  if (hits.length) {
    sections.push(
      `## Lessons matching this request\n\n` +
        hits
          .map(
            lesson =>
              `### ${lesson.id}\n_Learned ${lesson.learned}${lesson.evidence ? ` — ${lesson.evidence}` : ''}_\n\n${lesson.body}`
          )
          .join('\n\n---\n\n')
    )
  }

  if (sections.length === 0) process.exit(0)

  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: sections.join('\n\n') }
    })}\n`
  )
  process.exit(0)
}

// ---------------------------------------------------------------------------- nudge

// Fires on Stop. NEVER blocks — a knowledge-capture prompt that can trap a session would be traded
// away the first time it misfires, and then the whole mechanism is gone.
//
// The signal is struggle-then-recover: the same command failed and later passed in this turn. That is
// the shape of "something non-obvious was learned", and it is far more selective than "an error
// occurred", which is true of nearly every turn.
//
// It reads `cmd` and `ok`, which is what record-activity.mjs actually writes. A reader that invents
// its own field names produces a mechanism that is green in its tests and has never once fired.
const nudge = async () => {
  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const session = String(payload?.session_id ?? 'unknown')
  const state = readState()

  if (state.nudged?.[session]) process.exit(0)

  let lines

  try {
    lines = readFileSync(LEDGER, 'utf8').split('\n').filter(Boolean)
  } catch {
    process.exit(0)
  }

  const runs = []
  let latest = null

  for (const line of lines) {
    try {
      const event = JSON.parse(line)

      if (event.run) {
        if (event.turn !== latest) {
          latest = event.turn
          runs.length = 0
        }

        runs.push(event)
      }
    } catch {
      /* torn line */
    }
  }

  if (!runs.length) process.exit(0)

  const failed = new Set()
  let recovered = false

  for (const run of runs) {
    const key = String(run.cmd ?? '').trim().slice(0, 80)

    if (!key) continue
    if (!run.ok) failed.add(key)
    else if (failed.has(key)) recovered = true
  }

  if (!recovered) process.exit(0)

  const lessons = loadLessons().filter(lesson => !lesson.error)

  state.nudged = { ...(state.nudged ?? {}), [session]: true }
  writeState(state)

  process.stdout.write(
    `${JSON.stringify({
      systemMessage:
        `A command failed and later passed this turn. If the cause was non-obvious, will recur, and ` +
        `changes what you would do next time, record it: see \`.claude/skills/lesson-keeper/SKILL.md\`. ` +
        `If it was a one-off, record nothing — the store is ${lessons.length}/${MAX_LESSONS} and stays ` +
        `lean by refusing most candidates.`
    })}\n`
  )
  process.exit(0)
}

// ---------------------------------------------------------------------------- audit

const STALE_AFTER_SESSIONS = 25

const audit = () => {
  const auditState = readState()
  const auditSessions = Object.keys(auditState.sessions ?? {}).length

  const lessons = loadLessons()
  const errors = []
  const warnings = []

  for (const lesson of lessons) {
    if (lesson.error) {
      errors.push(`${lesson.name}: ${lesson.error}`)
      continue
    }

    if (lesson.bodyLines > MAX_BODY_LINES) {
      warnings.push(`${lesson.id}: body is ${lesson.bodyLines} lines (>${MAX_BODY_LINES}) — tighten or split`)
    }

    if (lesson.terms.length === 0) warnings.push(`${lesson.id}: no usable trigger terms — it can never be retrieved`)

    // ── GRADUATION ──────────────────────────────────────────────────────────
    //
    // The intended end state for any lesson is DELETION. Once it hardens into a standing rule it
    // graduates into CLAUDE.md, a hook, or a check script, and the lesson file is removed. Nothing
    // drives that on its own, so the store only ever grows — an accumulator wearing a curated set's
    // clothes.
    //
    // The signal was already being recorded and never read: `state.hits` counts how often each lesson
    // matched a prompt. A lesson names its encoding with `encoded: <path>`; if that guard exists and
    // the lesson has since gone quiet, it has done its job.
    //
    // Reported, never automatic. The hit count can fall because the guard works OR because nobody has
    // touched that area this month, and only a person can tell those apart.
    if (lesson.encoded) {
      const guardExists = lesson.encoded
        .split(',')
        .map(path => path.trim())
        .filter(Boolean)
        .every(path => existsSync(path))

      const hitsSince = (auditState.hits?.[lesson.id] ?? 0) - Number(lesson.encodedAtHits ?? 0)

      if (!guardExists) {
        warnings.push(`${lesson.id}: encoded as ${lesson.encoded}, which does not exist`)
        // `<= 0`, not `=== 0`. A stale or over-stated encodedAtHits makes this negative, and testing for
        // exact zero silently skips the whole check — which is how it would ship looking correct.
      } else if (hitsSince <= 0 && auditSessions >= STALE_AFTER_SESSIONS) {
        warnings.push(
          `${lesson.id}: GRADUATED — ${lesson.encoded} is in place and it has not matched a prompt since. ` +
            'Verify the guard has both-direction tests, then delete the lesson.'
        )
      }
    }
  }

  const valid = lessons.filter(lesson => !lesson.error)
  const seen = new Map()

  for (const lesson of valid) {
    if (seen.has(lesson.id)) errors.push(`duplicate id "${lesson.id}" in ${seen.get(lesson.id)} and ${lesson.name}`)
    seen.set(lesson.id, lesson.name)
  }

  if (valid.length > MAX_LESSONS) {
    errors.push(
      `${valid.length} lessons exceeds the cap of ${MAX_LESSONS}. Consolidate overlapping entries, promote ` +
        `settled ones into CLAUDE.md or a check script, or prune what no longer applies.`
    )
  }

  // Consolidation candidates: heavy trigger overlap means one prompt drags in both, which is the
  // symptom of two files describing one lesson.
  for (let i = 0; i < valid.length; i += 1) {
    for (let j = i + 1; j < valid.length; j += 1) {
      const shared = valid[i].terms.filter(term => valid[j].terms.includes(term))

      if (shared.length >= 3) {
        warnings.push(`${valid[i].id} + ${valid[j].id} share ${shared.length} triggers (${shared.join(', ')}) — consolidate?`)
      }
    }
  }

  if (auditSessions >= STALE_AFTER_SESSIONS) {
    for (const lesson of valid) {
      if (!auditState.hits?.[lesson.id]) {
        warnings.push(`${lesson.id}: never matched a prompt in ${auditSessions} sessions — wrong triggers, or prune it`)
      }
    }
  }

  for (const warning of warnings) console.log(`  warn  ${warning}`)
  for (const error of errors) console.error(`  FAIL  ${error}`)

  if (errors.length) {
    console.error(`- lessons: ${errors.length} error(s)`)
    process.exit(1)
  }

  console.log(`- lessons: ${valid.length}/${MAX_LESSONS} ok${warnings.length ? `, ${warnings.length} warning(s)` : ''}`)
  process.exit(0)
}

// ---------------------------------------------------------------------------- list / stats

const list = () => {
  const lessons = loadLessons()

  if (!lessons.length) return console.log('No lessons recorded yet.')

  const state = readState()

  for (const lesson of lessons) {
    if (lesson.error) {
      console.log(`  !! ${lesson.name}: ${lesson.error}`)
      continue
    }

    console.log(`\n  ${lesson.id}  [${lesson.scope}]  ${lesson.learned}  hits:${state.hits?.[lesson.id] ?? 0}`)
    console.log(`     ${lesson.summary}`)
    console.log(`     triggers: ${lesson.terms.join(', ')}`)
  }

  console.log(`\n  ${lessons.length}/${MAX_LESSONS}`)
}

const stats = () => {
  const state = readState()

  console.log(`sessions seen: ${Object.keys(state.sessions ?? {}).length}`)
  console.log('hits by lesson:')

  const entries = Object.entries(state.hits ?? {}).sort((a, b) => b[1] - a[1])

  if (!entries.length) console.log('  (none yet)')
  for (const [id, count] of entries) console.log(`  ${count}\t${id}`)
}

// ---------------------------------------------------------------------------- main

const command = process.argv[2]

if (command === '--self-test') {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const good = ['---', 'id: remote-hangs', 'trigger: remote, WaitForChild, hang', 'scope: harness', 'learned: 2026-08-10', '---', '**Lesson:** An undeclared remote hangs forever.'].join('\n')
  const parsed = parseLesson('x.md', good)

  check('a well-formed lesson parses', parsed.id, 'remote-hangs')
  check('triggers are lowercased and split', parsed.terms, ['remote', 'waitforchild', 'hang'])
  check('the summary is the index line', parsed.summary, 'An undeclared remote hangs forever.')
  check('missing frontmatter is an error', parseLesson('y.md', 'no frontmatter').error, 'missing frontmatter block')
  check(
    'a missing required field is named',
    parseLesson('z.md', ['---', 'id: a', 'trigger: b', '---', 'body'].join('\n')).error,
    'missing frontmatter: scope, learned'
  )

  // Retrieval is the whole mechanism: a lesson that cannot be matched was never written.
  check('a matching prompt retrieves it', matches(parsed, 'why does this remote hang'), true)
  check('substring matching survives plurals', matches(parsed, 'the remotes are declared'), true)
  check('an unrelated prompt does not', matches(parsed, 'adjust the lighting fog'), false)

  // Stop terms must not be retrievable, or one lesson injects on every prompt.
  const noisy = parseLesson('n.md', ['---', 'id: n', 'trigger: the, a, game', 'scope: x', 'learned: 2026-08-10', '---', 'b'].join('\n'))

  check('stop terms are dropped from triggers', noisy.terms, [])

  console.log(failures ? `  FAIL  lessons: ${ran - failures}/${ran}` : `  PASS  lessons: ${ran}/${ran} cases`)
  process.exit(failures ? 1 : 0)
} else if (command === 'inject') await inject()
else if (command === 'nudge') await nudge()
else if (command === 'audit') audit()
else if (command === 'list') list()
else if (command === 'stats') stats()
else {
  console.error('usage: lessons.mjs <inject|nudge|audit|list|stats|--self-test>')
  process.exit(2)
}
