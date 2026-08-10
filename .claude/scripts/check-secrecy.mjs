#!/usr/bin/env node
// THE check for this game. The Aswang's identity is server-only state; if it ever reaches another
// client in any form, the game is over — not "less fun", over, because knowing the imposter is the
// entire win condition. Spec §4.2 and §6.2 both say it, and a rule stated twice in prose and enforced
// nowhere is a rule that will be broken by a tired author at 1am.
//
//   node .claude/scripts/check-secrecy.mjs [--json]
//   node .claude/scripts/check-secrecy.mjs --self-test
//
// ── WHAT IT LOOKS FOR ──────────────────────────────────────────────────────────
//
// Four shapes, each of which has shipped in real Roblox social-deduction games:
//
//   1. A secret-bearing payload on a broadcast — `:FireAllClients(...)` carrying a role or a userId
//      the receiver is not entitled to.
//   2. Attributes and CollectionService tags. Both REPLICATE TO EVERY CLIENT. `SetAttribute("Role",
//      …)` on a character is the single most common way this leaks, and it looks like local state.
//   3. The client naming the secret at all. `AswangUserId` appearing anywhere under `src/client/`
//      means either it is being received or it is being guessed at; both are wrong.
//   4. The secret written into a replicated container — ReplicatedStorage, Workspace, or a Player
//      instance.
//
// ── WHAT IT CANNOT SEE, STATED PLAINLY ────────────────────────────────────────
//
// Data flow. `local x = state.AswangUserId` followed twenty lines later by `event:FireAllClients(x)`
// passes this check. Renaming the variable defeats it entirely. This is a tripwire on the OBVIOUS
// forms, not a proof of secrecy — the proof is `exploit-auditor` reading the diff, and the tripwire
// exists so that agent has less to catch.

import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { hasWaiver, listLuau, lineOf, readSource, report } from './lib/luau-source.mjs'

// Remotes that are ALLOWED to carry the secret, each with the reason it is safe. Anything not on this
// list is refused, so adding a leak requires editing this file — which shows up in a diff and in
// review. That asymmetry is the whole design.
export const REVEAL_ALLOWLIST = new Map([
  ['RoundEnded', 'the round is over — the reveal is the point (spec §4.8)'],
  ['RoleAssigned', 'fired to exactly one player, carrying only that player\'s OWN role (spec §4.2)']
])

// Tokens that name the secret. Deliberately broad on the monster side and narrow on the generic side:
// `role` alone would match `RoleService`, so it only counts inside a payload.
const SECRET = /\b(aswang|imposter|impostor|monsteruserid|iskiller|isaswang|aswanguserid|secretrole)\b/i
const ROLE_TOKEN = /\b(role|roles)\b/i

// Balanced-paren extraction from an offset pointing at the `(`. Returns the argument text.
const argsAt = (code, open) => {
  let depth = 0

  for (let i = open; i < code.length; i += 1) {
    if (code[i] === '(') depth += 1
    else if (code[i] === ')') {
      depth -= 1

      if (depth === 0) return code.slice(open + 1, i)
    }
  }

  return code.slice(open + 1)
}

// The remote name for a `Remotes.Get("X"):FireAllClients(` call, when it is written inline. When the
// event is held in a variable the name is unknown, and an unknown name is NOT allowlisted — the
// conservative direction, because the allowlist is what makes a leak require a deliberate edit.
const remoteNameBefore = (code, callIndex) => {
  const window = code.slice(Math.max(0, callIndex - 160), callIndex)
  const match = /Remotes\.Get\(\s*["']([\w]+)["']\s*\)\s*$/.exec(window)

  return match ? match[1] : null
}

export const scan = files => {
  const findings = []

  for (const file of files) {
    const { raw, code, withStrings } = readSource(file)
    const rawLines = raw.split('\n')
    const isClient = /(^|\/)src\/client\//.test(file)

    const add = (index, why, detail) => {
      const line = lineOf(code, index)
      const waiver = hasWaiver(rawLines, line, 'secrecy')

      if (waiver) return

      findings.push({ file, line, why, detail })
    }

    // 1. Broadcasts carrying the secret.
    for (const match of code.matchAll(/:FireAllClients\s*\(/g)) {
      const open = match.index + match[0].length - 1
      const args = argsAt(code, open)

      if (!SECRET.test(args) && !ROLE_TOKEN.test(args)) continue

      // `withStrings`, not `code`: the remote's NAME is a string literal, and `code` has string
      // contents blanked. Reading it from `code` made every call look like an unnamed remote, so the
      // allowlist could never match and the reveal itself was flagged. The two texts are the same
      // length by construction, so the index carries across.
      const remote = remoteNameBefore(withStrings, match.index)

      if (remote && REVEAL_ALLOWLIST.has(remote)) continue

      add(
        match.index,
        `:FireAllClients carries what looks like the Aswang's identity on ${remote ? `\`${remote}\`` : 'an unnamed remote'}`,
        remote
          ? `Only ${[...REVEAL_ALLOWLIST.keys()].join(', ')} may. Add a reason to REVEAL_ALLOWLIST if this is genuinely the reveal.`
          : 'The remote is held in a variable, so its name cannot be checked here. Call it inline as Remotes.Get("Name"):FireAllClients(...).'
      )
    }

    // 2. Attributes and tags replicate to every client. There is no private attribute.
    for (const match of withStrings.matchAll(/:SetAttribute\s*\(\s*["']([^"']+)["']/g)) {
      if (!SECRET.test(match[1]) && !ROLE_TOKEN.test(match[1])) continue

      add(
        match.index,
        `SetAttribute("${match[1]}", …) — attributes replicate to EVERY client`,
        'There is no private attribute. Keep the role in a server-side table keyed by UserId.'
      )
    }

    for (const match of withStrings.matchAll(/:AddTag\s*\(\s*[^,]+,\s*["']([^"']+)["']/g)) {
      if (!SECRET.test(match[1]) && !ROLE_TOKEN.test(match[1])) continue

      add(
        match.index,
        `CollectionService:AddTag(…, "${match[1]}") — tags replicate to EVERY client`,
        'Same trap as attributes. Server-side table, keyed by UserId.'
      )
    }

    // 3. The client must not know the field exists.
    if (isClient) {
      for (const match of code.matchAll(/\bAswangUserId\b/g)) {
        add(
          match.index,
          'client code references AswangUserId',
          'The client is never told who the Aswang is. If this is the end-of-round reveal, read it from the RoundEnded payload instead and name it accordingly.'
        )
      }
    }

    // 4. The secret written into a replicated container.
    for (const match of code.matchAll(/\b(ReplicatedStorage|Workspace)\b[^\n]{0,80}/g)) {
      if (!SECRET.test(match[0])) continue

      add(
        match.index,
        `${match[1]} referenced on a line naming the Aswang`,
        'Anything parented under a replicated container is readable by every client, including its Name and every Value.'
      )
    }
  }

  return findings
}

// ── --self-test: both directions ───────────────────────────────────────────────
//
// The ALLOW cases outnumber the BLOCK cases deliberately. A guard that only proves it can refuse has
// proven the cheap half; the expensive failure is refusing correct code until somebody disables it.
const selfTest = () => {
  const dir = mkdtempSync(join(tmpdir(), 'secrecy-'))
  let failures = 0
  let ran = 0

  const check = (label, source, shouldFlag, subdir = 'src/server') => {
    ran += 1

    const path = join(dir, 'file.luau')

    writeFileSync(path, source)

    const findings = scan([path]).map(f => ({ ...f, file: subdir }))
    const flagged = findings.length > 0

    if (flagged === shouldFlag) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${shouldFlag ? 'BLOCK' : 'ALLOW'}, got ${flagged ? 'BLOCK' : 'ALLOW'}`)
    for (const finding of findings) console.log(`        ${finding.why}`)
  }

  // BLOCK
  check('broadcasting the role on an arbitrary remote', 'Remotes.Get("PhaseChanged"):FireAllClients({ Role = role })', true)
  check('broadcasting the aswang id', 'Remotes.Get("RoundSnapshot"):FireAllClients({ AswangUserId = id })', true)
  check('an unnamed remote broadcasting a role', 'local ev = something\nev:FireAllClients({ Role = r })', true)
  check('a role attribute', 'character:SetAttribute("Role", "ASWANG")', true)
  check('a role tag', 'CollectionService:AddTag(char, "Aswang")', true)

  // ALLOW — every one of these is correct code that a blunter check would refuse.
  check('the end-of-round reveal', 'Remotes.Get("RoundEnded"):FireAllClients({ AswangUserId = id })', false)
  check('a private role assignment', 'Remotes.Get("RoleAssigned"):FireClient(player, role)', false)
  check('a comment describing the rule', '-- never FireAllClients the Aswang role to anyone\nlocal x = 1', false)
  check('a docstring naming the secret', '--[[ AswangUserId is THE SECRET; never replicate it ]]\nlocal y = 2', false)
  check('the transform, which is public by design', 'Remotes.Get("MonsterTransformed"):FireAllClients(character)', false)
  check('a server-side role table', 'local roles: { [number]: Types.Role } = {}\nroles[player.UserId] = "ASWANG"', false)
  check('a service named after roles', 'local RoleService = require(script.Parent.RoleService)', false)
  check('a waived deliberate broadcast', 'Remotes.Get("Custom"):FireAllClients({ Role = r }) -- secrecy-ok: debug build only', false)
  check('an unrelated attribute', 'character:SetAttribute("Stunned", true)', false)
  check('a phase broadcast with no secret', 'Remotes.Get("PhaseChanged"):FireAllClients(phase, seconds)', false)

  rmSync(dir, { recursive: true, force: true })

  console.log(failures ? `  FAIL  check-secrecy: ${ran - failures}/${ran}` : `  PASS  check-secrecy: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('check-secrecy.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  const findings = scan(listLuau())

  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(findings, null, 2))
    process.exit(findings.length ? 1 : 0)
  }

  process.exit(
    report('secrecy', findings, {
      note: 'the Aswang stays server-side'
    })
  )
}
