#!/usr/bin/env node
// Episodic capture — the staging area BEFORE `.claude/lessons/`.
//
//   record    UserPromptSubmit hook — log a user message that looks like a correction
//   reflect   Stop hook — log MY OWN admission of error
//   finding   SubagentStop hook — log that an adversarial agent reported something
//   list      human-readable, newest first
//   status    counts + whether a review is due (wired into `npm run verify`)
//   clear     empty the file after a review has distilled it
//
// WHY THIS EXISTS
// `.claude/lessons/` is semantic memory: distilled, curated, capped at 40, injected into context. It
// has no episodic layer underneath it, so a mistake nobody wrote down IN THE MOMENT is gone. Capture
// would otherwise depend entirely on the agent volunteering that it had erred, which is the one moment
// it is least inclined to.
//
// The only other automatic signal is `lessons.mjs nudge`, which fires on "the same command failed and
// later passed". Measured in the system this is adapted from, that signal caught NONE of five real
// mistakes in a session — all were reasoning errors with no failing command, and the nudge is blind to
// those.
//
// THE DESIGN RULE: capture generously, distil strictly.
// A candidate costs nothing — this file is NEVER read into context, only by a human or an explicit
// review. A missed candidate is a lesson lost forever; a noisy candidate is one line somebody skims
// past. Those costs are wildly asymmetric, so this errs toward recording. The four-test bar in
// `lesson-keeper` is where strictness lives, and NOTHING here ever writes a lesson.

import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

const PATH = '.claude/.candidates.jsonl'

// Below this there is nothing to cluster — a review of four entries finds four one-offs. Past it,
// patterns start being visible and the reviewer is the thing that is late.
const REVIEW_THRESHOLD = 15

// Ring buffer. Unbounded growth makes the eventual review unreadable, which is the failure mode that
// turns a knowledge base into a log.
const MAX_ENTRIES = 300

// ---------------------------------------------------------------------------- signals
//
// Four INDEPENDENT families, because any single family has blind spots. Word lists in particular miss
// corrections phrased as instructions ("adjust the kill range") or as resignation ("this is useless
// now") — both real, both invisible to family A alone.

// A. The user says something is wrong, in words.
const EXPLICIT = [
  /\bno\b/i,
  /\bnope\b/i,
  /\bwrong\b/i,
  /\bincorrect\b/i,
  /\bmistake\b/i,
  /\bnot (what|right|correct|true)\b/i,
  /\bdon'?t\b/i,
  /\bdoesn'?t\b/i,
  /\bshouldn'?t\b/i,
  /\bdidn'?t\b/i,
  /\bnever\b/i,
  /\bstop\b/i,
  /\bwait\b/i
]

// B. The user is redirecting the work — a correction that never uses a negative word.
const REDIRECT = [
  /\binstead\b/i,
  /\bactually\b/i,
  /\brather than\b/i,
  /\bredo\b/i,
  /\brevert\b/i,
  /\bundo\b/i,
  /\badjust\b/i,
  /\bchange it\b/i,
  /\bfix (it|that|this)\b/i,
  /\bi want you to\b/i,
  /\bi don'?t want\b/i,
  /\byou need to\b/i,
  /\bmake sure\b/i,
  /\bnext time\b/i,
  /\bin the future\b/i,

  // A correction of PROCESS rather than of output. Bare "tell me" is deliberately NOT a pattern:
  // "tell me if the transform is visible" is an ordinary request and would false-positive.
  /\bbefore (doing|making|you|any)\b/i
]

// C. The user is interrogating MY behaviour. A question about what I did is nearly always a correction
// wearing a question mark.
const INTERROGATIVE = [
  /\bwhy (did|are|is|isn'?t|can'?t|cannot|would|no|there)\b/i,
  /\bhow come\b/i,
  /\bdid you\b/i,
  /\bare you (sure|done)\b/i,
  /\bwhat happened\b/i,
  /\bi (told|asked) you\b/i,
  /\byou (said|told|claimed|forgot|missed)\b/i,
  /\bstill (not|broken|failing|wrong)\b/i,
  /\buseless\b/i
]

// D. MY OWN admissions. The "two eyes" half — the agent catching itself rather than waiting to be
// caught. Deliberately narrow: phrases used when conceding a specific error, not ordinary hedging.
const SELF_CORRECTION = [
  /\bi was wrong\b/i,
  /\bmy (mistake|error|miss)\b/i,
  /\bi missed\b/i,
  /\bi should have\b/i,
  /\bthat'?s wrong\b/i,
  /\bcorrecting\b/i,
  /\bi got .{0,20}wrong\b/i,
  /\bi (incorrectly|wrongly|falsely)\b/i,
  /\bwas never actually\b/i
]

export const matches = (text, patterns) => patterns.some(pattern => pattern.test(text))

const countHits = (text, patterns) => patterns.filter(pattern => pattern.test(text)).length

// USE vs MENTION. Strips code spans, fenced blocks, quoted strings and bold runs before matching.
//
// A message explaining how this detector works — quoting "I was wrong" and "I missed" as examples —
// would otherwise be recorded as a self-correction, and any message documenting the trigger list would
// trip it forever.
//
// Applied to `reflect` ONLY. Assistant output is heavily formatted and quotes things constantly; user
// messages are not, and a user pasting a console error containing "wrong" is a signal worth keeping.
export const stripQuoted = text =>
  text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/"[^"]*"/g, ' ')
    .replace(/\*\*[^*]*\*\*/g, ' ')

// Machine-generated envelopes that arrive on the SAME channel as a user prompt but are not one:
// background-task completions, IDE file-open events, injected reminders.
//
// Measured in this repo on 2026-08-12: of 58 queued candidates, 44 were filed as `user-correction`,
// and a sample of the most recent showed the majority were `<task-notification>` blocks. An agent's
// report reliably contains "wrong", "failed", "should" and "instead" — so the correction classifier
// fired on the AGENT's prose and recorded it as though the user had said it. The backlog became
// unreadable, which is the same as not capturing at all.
//
// STRIPPED RATHER THAN SKIPPED, because a real correction often rides ALONGSIDE one of these: the
// user types an instruction in the same turn an IDE event fires, and this very session opened two
// files mid-conversation. Whatever the user actually wrote survives; the envelope does not.
export const stripEnvelopes = text =>
  text
    .replace(/<task-notification>[\s\S]*?<\/task-notification>/g, ' ')
    .replace(/<ide_opened_file>[\s\S]*?<\/ide_opened_file>/g, ' ')
    .replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, ' ')
    .replace(/<ide_selection>[\s\S]*?<\/ide_selection>/g, ' ')

export const classify = text => {
  const hits = []

  if (matches(text, EXPLICIT)) hits.push('explicit')
  if (matches(text, REDIRECT)) hits.push('redirect')
  if (matches(text, INTERROGATIVE)) hits.push('interrogative')

  return hits
}

// Confidence counts PATTERN hits, not families. Counting families rates "no thats wrong" as marginal
// because both matches sit inside EXPLICIT — obviously a correction, scored as if borderline. Two
// independent signals are two independent signals regardless of which bucket they came from.
export const confidenceOf = text => {
  const total = countHits(text, EXPLICIT) + countHits(text, REDIRECT) + countHits(text, INTERROGATIVE)

  return total >= 2 ? 'high' : 'low'
}

// ---------------------------------------------------------------------------- io

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const readAll = () => {
  try {
    return readFileSync(PATH, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map(line => {
        try {
          return JSON.parse(line)
        } catch {
          return null
        }
      })
      .filter(Boolean)
  } catch {
    return []
  }
}

// Skips an entry identical to one already in the recent tail. Repeats are harmless individually, but a
// review that has to skim past them is a review that stops happening.
const isDuplicate = entry => readAll().slice(-25).some(prior => prior.kind === entry.kind && prior.text === entry.text)

const append = entry => {
  if (isDuplicate(entry)) return

  try {
    mkdirSync(dirname(PATH), { recursive: true })
    appendFileSync(PATH, `${JSON.stringify(entry)}\n`)

    const all = readAll()

    if (all.length > MAX_ENTRIES) {
      writeFileSync(PATH, `${all.slice(-MAX_ENTRIES).map(item => JSON.stringify(item)).join('\n')}\n`)
    }
  } catch {
    /* capture is best-effort — it must never be the reason a turn fails */
  }
}

// Stored TRUNCATED, not in full. Enough to recognise the incident during review, short enough that the
// file stays skimmable and carries no long verbatim payloads.
const snippet = (text, max = 220) => text.replace(/\s+/g, ' ').trim().slice(0, max)

// ---------------------------------------------------------------------------- commands

const record = async payload => {
  const raw = typeof payload?.prompt === 'string' ? payload.prompt : ''

  // Envelopes off BEFORE anything is classified, scored or stored. Doing it here rather than inside
  // `classify` means the snippet written to the backlog is also the human's words — a row whose text
  // is an agent's report is unreadable later even if its kind happened to be right.
  const prompt = stripEnvelopes(raw)

  if (!prompt.trim()) return

  const signals = classify(prompt)

  if (signals.length === 0) return

  append({
    at: new Date().toISOString(),
    kind: 'user-correction',
    signals,
    confidence: confidenceOf(prompt),
    text: snippet(prompt)
  })
}

const reflect = async payload => {
  // `last_assistant_message` is not guaranteed present on every build's Stop payload. When it is
  // absent this silently does nothing rather than guessing.
  const message = typeof payload?.last_assistant_message === 'string' ? payload.last_assistant_message : ''

  if (!message.trim()) return
  if (!matches(stripQuoted(message), SELF_CORRECTION)) return

  append({ at: new Date().toISOString(), kind: 'self-correction', signals: ['self'], confidence: 'high', text: snippet(message) })
}

// An adversarial agent finishing is itself worth noting: the playtester and the auditors exist to find
// what the main thread missed, and their findings are reported in chat and then evaporate. This records
// that a review happened so the distillation step knows to look.
const finding = async payload => {
  const type = typeof payload?.agent_type === 'string' ? payload.agent_type : ''

  if (!/playtester|auditor/i.test(type)) return

  append({
    at: new Date().toISOString(),
    kind: 'agent-review',
    signals: [type],
    confidence: 'low',
    text: `${type} completed — check its findings for anything worth distilling`
  })
}

const list = () => {
  const all = readAll()

  if (all.length === 0) {
    console.log('- no candidates recorded')

    return
  }

  for (const entry of [...all].reverse()) {
    console.log(`  ${entry.at?.slice(0, 16) ?? '?'}  [${entry.kind}] ${entry.confidence === 'high' ? '**' : '  '} ${entry.text}`)
  }

  console.log(`\n  ${all.length} candidates (${all.filter(entry => entry.confidence === 'high').length} high-confidence)`)
}

// Wired into `verify` so the ANSWER to "is it time to review yet" is printed by the tooling rather than
// remembered by anyone. Never exits non-zero — a full candidates file is a prompt, not a build failure.
const status = () => {
  const all = readAll()
  const high = all.filter(entry => entry.confidence === 'high').length

  if (all.length >= REVIEW_THRESHOLD) {
    console.log(`- candidates: ${all.length} (${high} high) — REVIEW DUE, run \`/lessons-review\``)
  } else {
    console.log(`- candidates: ${all.length}/${REVIEW_THRESHOLD} (${high} high)`)
  }
}

// `clear` wipes everything, which is only correct if everything was read. A review works newest first
// and rarely finishes the whole backlog in one sitting, so `--before <ISO-date>` clears the part that
// WAS read. Dropping an unread backlog is worse than leaving it: the next review starts from a false
// baseline and the incidents are gone.
// Arg parsing is split out and pure so both directions can be self-tested. The failure it prevents
// happened: `clear --help` found no `--before`, fell through to the wipe-everything branch, and took
// 80 unreviewed candidates with it. The file is gitignored, so there was nothing to recover. An
// unrecognised flag must therefore REFUSE rather than fall back to the destructive default.
export const parseClearArgs = args => {
  if (args.length === 0) return { ok: true, before: null }

  if (args[0] !== '--before') {
    return { ok: false, error: `unknown argument ${JSON.stringify(args[0])} — expected \`--before <ISO-date>\` or no arguments` }
  }

  if (args.length === 1) return { ok: false, error: '--before needs an ISO date' }
  if (args.length > 2) {
    return { ok: false, error: `unexpected extra arguments after --before: ${JSON.stringify(args.slice(2))}` }
  }

  return { ok: true, before: args[1] }
}

const clear = () => {
  const parsed = parseClearArgs(process.argv.slice(3))

  if (!parsed.ok) {
    console.error(`- ${parsed.error}`)
    process.exitCode = 1

    return
  }

  const before = parsed.before

  let entries

  try {
    entries = readFileSync(PATH, 'utf8').split('\n').filter(Boolean)
  } catch {
    console.log('- nothing to clear')

    return
  }

  if (!before) {
    writeFileSync(PATH, '')
    console.log(`- candidates cleared (${entries.length} removed)`)

    return
  }

  const cutoff = Date.parse(before)

  if (Number.isNaN(cutoff)) {
    console.error(`- --before needs an ISO date, got ${JSON.stringify(before)}`)
    process.exitCode = 1

    return
  }

  const kept = entries.filter(line => {
    try {
      return Date.parse(JSON.parse(line).at) >= cutoff
    } catch {
      // An unparseable line cannot be shown to have been reviewed, so it stays.
      return true
    }
  })

  writeFileSync(PATH, kept.length ? `${kept.join('\n')}\n` : '')
  console.log(`- cleared ${entries.length - kept.length} candidates before ${before}, ${kept.length} kept`)
}

// ---------------------------------------------------------------------------- entry

const selfTest = () => {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (JSON.stringify(actual) === JSON.stringify(expected)) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }

  const captured = text => classify(text).length > 0

  // CAPTURE — verbatim shapes of real corrections. Written from observed messages rather than from
  // imagination; a list written from imagination misses about half of them.
  check('a flat contradiction', captured('no thats wrong'), true)
  check('a redirect with no negative word', captured('adjust the kill range instead'), true)
  check('an interrogation', captured('why is there no playtester?'), true)
  check('a process correction', captured('before doing anything tell me your plan'), true)
  check('resignation', captured('this is useless now'), true)
  check('a forward-looking instruction', captured('next time run the analyzer first'), true)

  //  ENVELOPES. The failure these prevent was measured, not imagined: 44 of 58 rows in this repo's
  //  backlog were filed as user corrections, and the recent ones were mostly agent reports. An
  //  agent's prose is full of "wrong", "failed" and "should", so the classifier fired on IT.
  const capturedAfterStrip = text => classify(stripEnvelopes(text)).length > 0

  check(
    'a task-notification is not a user correction',
    capturedAfterStrip('<task-notification>the fix was wrong and should be reverted</task-notification>'),
    false
  )
  check(
    'a system-reminder is not a user correction',
    capturedAfterStrip('<system-reminder>you should not have skipped the tests</system-reminder>'),
    false
  )
  check(
    'an IDE file-open event is not a user correction',
    capturedAfterStrip('<ide_opened_file>why is check-debug.mjs open?</ide_opened_file>'),
    false
  )

  //  THE ALLOW HALF, which is the half that matters: a real correction arriving in the SAME turn as
  //  an envelope must still be captured. Stripping rather than skipping is what buys this, and it is
  //  not hypothetical — this repo's own session had IDE events fire mid-instruction twice.
  check(
    'a real correction riding alongside an envelope survives',
    capturedAfterStrip('<ide_opened_file>README.md</ide_opened_file>no thats wrong, do it the other way'),
    true
  )
  check(
    'a real correction after a task-notification survives',
    capturedAfterStrip('<task-notification>agent finished</task-notification>stop and tell me your plan instead'),
    true
  )

  // NOT CAPTURED — ordinary work, which is the overwhelming majority of messages.
  check('a plain request', captured('add the salt throw handler'), false)
  check('a neutral question', captured('where does RoundService set the phase?'), false)
  check('an approval', captured('looks good, ship it'), false)

  // Confidence must reflect evidence strength, not which bucket the matches landed in.
  check('two matches in ONE family still rate high', confidenceOf('no thats wrong'), 'high')
  check('a single signal rates low', confidenceOf('why is that?'), 'low')

  // USE vs MENTION on the self-correction path.
  check('a real admission is caught', matches(stripQuoted('I was wrong about the phase order.'), SELF_CORRECTION), true)
  check('a quoted example is not', matches(stripQuoted('The detector matches "I was wrong" as an admission.'), SELF_CORRECTION), false)
  check('a fenced example is not', matches(stripQuoted('```\nI missed the remote\n```'), SELF_CORRECTION), false)
  check('a bold example is not', matches(stripQuoted('It fires on **I should have** phrases.'), SELF_CORRECTION), false)

  // CLEAR ARGS — the destructive default. `clear --help` once wiped 80 unreviewed candidates from a
  // gitignored file. Both directions matter here more than anywhere else in this script: the REFUSE
  // half prevents the data loss, and the ALLOW half is what keeps the reviewed-tail workflow usable.
  check('bare clear still wipes', parseClearArgs([]), { ok: true, before: null })
  check('--before with a date is accepted', parseClearArgs(['--before', '2026-08-10']), {
    ok: true,
    before: '2026-08-10',
  })
  check('--help REFUSES rather than wiping', parseClearArgs(['--help']).ok, false)
  check('an unknown flag REFUSES', parseClearArgs(['--all']).ok, false)
  check('a bare date with no flag REFUSES', parseClearArgs(['2026-08-10']).ok, false)
  check('--before with no date REFUSES', parseClearArgs(['--before']).ok, false)
  check('extra args after --before REFUSE', parseClearArgs(['--before', '2026-08-10', 'oops']).ok, false)

  console.log(failures ? `  FAIL  candidates: ${ran - failures}/${ran}` : `  PASS  candidates: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

const main = async () => {
  const command = process.argv[2]

  if (command === '--self-test') process.exit(selfTest())
  if (command === 'list') return list()
  if (command === 'status') return status()
  if (command === 'clear') return clear()

  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  if (command === 'record') await record(payload)
  if (command === 'reflect') await reflect(payload)
  if (command === 'finding') await finding(payload)

  process.exit(0)
}

main()
