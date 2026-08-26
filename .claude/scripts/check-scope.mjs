#!/usr/bin/env node
// The scope-creep alarm. Spec Appendix C.5 asks for it by name:
//
//   "if you ever find yourself building 'more zones,' 'a mountain,' 'unlockable weapons,' or
//    'a campaign,' you have started rebuilding Takbo Aswang. Stop and re-read this appendix."
//
//   node .claude/scripts/check-scope.mjs [--json]
//   node .claude/scripts/check-scope.mjs --self-test
//
// ── WHY A GREP DESERVES TO BE A GATE HERE ──────────────────────────────────────
//
// Normally "grep for a word" is the weakest possible check — it proves text was typed, nothing more.
// This is the exception, and it is worth being explicit about why: the failure mode being guarded is
// itself textual. Nobody builds a second monster by accident; they build it by writing
// `ManananggalService.luau` on an evening when the spec is not open. The token IS the event.
//
// The spec's §3 OUT list killed a comparable game with 2.5M visits and 16 months of work. The cost of
// this check being slightly noisy is one waiver comment. The cost of it not existing is the project.
//
// It is deliberately scoped to `src/` — docs, ROADMAP and plans are exactly where these ideas SHOULD
// live, and flagging them there would train everyone to ignore it.

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, listLuau, lineOf, readSource, report } from './lib/luau-source.mjs'

// Each entry cites the spec line that put it out of scope, so a finding argues its own case rather
// than asserting one.
//
// Matched against WHOLE WORDS, after identifiers are split on case and on the letter/digit boundary.
// `\b` anchors were the first attempt and they failed on every realistic spelling: `ManananggalService`
// has no word boundary after "manananggal", and neither does `startVote` before "vote" — so the four
// most likely first appearances of a scope breach all read as clean. Splitting first is what makes
// `startVote` a hit and `devotion` a miss, which is the distinction that matters.
export const OUT_OF_SCOPE = [
  { word: /^manananggal$/i, why: 'a second monster', cite: '§3 OUT — all other monsters' },
  { word: /^tiktik$/i, why: 'a second monster', cite: '§3 OUT — all other monsters' },
  { word: /^kapre$/i, why: 'a second monster', cite: '§3 OUT — all other monsters' },
  { word: /^tiyanak$/i, why: 'a second monster', cite: '§3 OUT — all other monsters' },
  { word: /^tikbalang$/i, why: 'a second monster', cite: '§3 OUT — all other monsters' },
  { word: /^meetings?$/i, why: 'emergency meetings', cite: '§4.5 — a deliberate design cut' },
  { word: /^vot(e|es|ed|er|ers|ing)$/i, why: 'voting', cite: '§3 OUT — emergency meetings / voting' },
  { word: /^eject(ed|ion|s)?$/i, why: 'ejection', cite: '§3 OUT — no voting means nothing to eject' },
  { word: /^campaigns?$/i, why: 'a campaign', cite: 'Appendix C.5 — the trap that killed the competitor' },
  { word: /^zones?$/i, why: 'zone-based progression', cite: 'Appendix C.5 — 7 zones took them 16 months' },
  // v2.0 ships ONE thing that damages the Aswang — the buntot pagi, one per round, breaks on use.
  // Appendix C.5's exception depends on that being true, so a GENERIC weapon noun is still the event
  // worth catching: an armoury forms by someone writing `local weapon` before it forms by someone
  // adding a second named item. `BuntotPagi` splits to Buntot + Pagi and matches neither.
  { word: /^weapons?$/i, why: 'a generic weapon system', cite: '§3 OUT — no weapon beyond the buntot pagi' },
  { word: /^(machete|bolo)$/i, why: 'a weapon', cite: '§3 OUT — no weapon beyond the buntot pagi' },
  { word: /^microphones?$/i, why: 'a mic-driven mechanic', cite: '§4.5 — rejected on three independent grounds' },
  // ARMED AT V01, with the ghost system deleted in the same diff. §4.7 cuts ghosts; dead players
  // spectate, and `PlayerState`'s dead member is spelled DEAD for exactly this reason — a state
  // literal is a string, and the scanner reads strings.
  //
  // The two ALLOW cases below — a corpse and a husk — are the near misses this must not catch. Both
  // are real, both survive v2.0, and neither contains the bare word.
  { word: /^ghosts?$/i, why: 'the ghost system', cite: '§4.7 — cut in v2.0' },
  { word: /^sabotage[ds]?$/i, why: 'sabotage systems', cite: '§3 OUT' },
  { word: /^trades?$|^trading$/i, why: 'trading', cite: '§3 OUT' },
  { word: /^guilds?$/i, why: 'guilds', cite: '§3 OUT' },
  { word: /^pets?$/i, why: 'pets', cite: '§3 OUT' },
  { word: /^seasons?$/i, why: 'leaderboard seasons', cite: '§3 OUT' }
]

// `MonsterServiceV2` → Monster, Service, V, 2. Offsets are preserved so a finding can name its line.
export const words = text => {
  const out = []

  for (const run of text.matchAll(/[A-Za-z0-9_]+/g)) {
    let offset = run.index

    for (const part of run[0].split(/_+|(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])/)) {
      if (part) out.push({ word: part, index: offset })
      offset += part.length + 1
    }
  }

  return out
}

export const scan = files => {
  const findings = []

  for (const file of files) {
    // `withStrings` rather than `code`: a UI label reading "Vote to eject" is exactly as much of a
    // scope breach as a function called `vote`, and it is the more likely first appearance. Comments
    // are still stripped, so a note explaining why voting was cut cannot trip this.
    const { raw, withStrings } = readSource(file)
    const rawLines = raw.split('\n')

    for (const { word, index } of words(withStrings)) {
      const entry = OUT_OF_SCOPE.find(candidate => candidate.word.test(word))

      if (!entry) continue

      const line = lineOf(withStrings, index)

      if (hasWaiver(rawLines, line, 'scope')) continue

      findings.push({
        file,
        line,
        why: `${entry.why} — "${word}" is out of MVP scope`,
        detail: `${entry.cite}. It belongs in ROADMAP.md, which the spec calls your marketing calendar (§3).`
      })
    }
  }

  return findings
}

const selfTest = () => {
  const dir = mkdtempSync(join(tmpdir(), 'scope-'))
  const src = join(dir, 'src', 'server')

  mkdirSync(src, { recursive: true })

  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag) => {
    ran += 1

    const path = join(src, 'Module.luau')

    writeFileSync(path, source)

    const flagged = scan([path]).length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
    for (const finding of scan([path])) console.log(`        ${finding.why}`)
  }

  // BLOCK
  check('a second monster', 'local ManananggalService = {}', true)
  check('a voting system', 'function startVote(player) end', true)
  check('an emergency meeting', 'Remotes.Get("CallMeeting"):FireServer()', true)
  check('a weapon', 'local weapon = Instance.new("Tool")', true)
  check('a campaign flag', 'if profile.CampaignChapter > 3 then end', true)
  check('a UI label offering to vote', 'button.Text = "Vote to eject"', true)
  check('a mic-driven mechanic', 'local microphoneLevel = 0', true)
  check('the ghost system', 'local GhostService = {}', true)
  check('a ghost in a UI string', 'label.Text = "your chat reaches ghosts only"', true)

  // ALLOW
  check('the one monster in scope', 'local MonsterService = require(script.Parent.MonsterService)', false)
  check('salt, the first of three items', 'ItemService.ThrowSalt(player, target)', false)
  check('bawang, the second', 'ItemService.PlaceGarlic(player, doorway)', false)
  check('the buntot pagi, which is not a "weapon"', 'local buntotPagi = ItemService.Take("BuntotPagi")', false)
  check('a corpse, which is not a ghost', 'BodyService.SpawnCorpse(player)', false)
  check('a husk, which is also not a ghost', 'local husk = BodyService.SpawnHusk(player)', false)
  check('a comment explaining the cut', '-- voting was cut deliberately; see spec §4.5\nlocal x = 1', false)
  check('a docstring naming rejected monsters', '--[[ Manananggal and Tiktik are v2 — see ROADMAP.md ]]\nlocal y = 2', false)
  check('a word that merely contains a token', 'local devotion = 1', false)
  check('promotion, which is not a season', 'local promoted = true', false)
  check('a waived deliberate mention', 'local isVote = false -- scope-ok: analytics field name required by the dashboard', false)

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-scope: ${ran - failures}/${ran}` : `  PASS  check-scope: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-scope.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(listLuau())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(findings, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  process.exit(report('scope', findings, { note: `${OUT_OF_SCOPE.length} out-of-scope shapes watched` }))
}
