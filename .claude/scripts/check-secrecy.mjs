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
//   1. A secret-bearing payload on a send — `:FireAllClients(...)` or `:FireClient(...)` carrying a
//      role or a userId the receiver is not entitled to. The payload is resolved back to its `local
//      x = { … }` declaration, so the typed-local idiom this repo recommends is inspected rather than
//      skipped.
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
//
// Rule 1's envelope, measured by an audit rather than guessed. It inspects TABLE-CONSTRUCTOR PAYLOADS
// ONLY: a single `{ … }` bound to a local within 1200 characters of the call, read at its top level.
//
// Four STRUCTURAL classes sit outside that envelope entirely, and the first is the one CLAUDE.md names
// as the whole reason `exploit-auditor` exists:
//
//   · a positional argument that is not a table — `FireAllClients(aswangUserId)` is caught only
//     because the VARIABLE NAME survives in the argument text. One rename defeats it completely.
//   · a helper's return value — `FireAllClients(buildPayload(k))`
//   · a RemoteFunction — `OnServerInvoke = function() return state.AswangUserId end`. THERE IS NO
//     RemoteFunction RULE IN THIS FILE AT ALL. (`Remotes.luau` declares none today, so this is
//     forward-looking rather than live — but it is a hole, not an omission by design.)
//   · a replicated Instance — a StringValue parented to ReplicatedStorage. Rule 4 needs the secret
//     token and the container on the SAME LINE.
//
// And within table payloads, every one of these gets through, each confirmed against the real `scan()`:
//
//   · a field assigned AFTER the constructor      — `payload.KillerUserId = k`
//   · a payload built by a helper                 — `local payload = buildKillPayload(k, v)`
//   · a bracket-string key                        — `{ ["AswangUserId"] = id }`, because `readSource`
//                                                    blanks string contents before this rule sees them
//   · a nested table inside a local               — `Meta = { KillerUserId = k }`
//   · a declaration further than 1200 characters from the call
//   · a field name avoiding both tokens           — `Murderer`, `Attacker`, `SourceUserId`
//
// So this rule raises the cost of a MISTAKE and does nothing against INTENT. That is the intended
// bargain — the realistic failure here is a tired author adding `KillerUserId` to an existing payload,
// and that one is now caught. Do not read a green tick as coverage of the list above.

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

// ── THE FIELD ALLOWLIST, AND WHY THE CALL ALLOWLIST WAS NOT ENOUGH ────────────
//
// REVEAL_ALLOWLIST exempts a CALL. Until this existed it exempted the whole call, so the scanner
// skipped the payload entirely — and Luau independently accepts an EXTRA field on an annotated table
// (measured: a wrong type and a missing field are caught, an extra one is not). Both guards were
// therefore off on exactly the two remotes that carry the secret by design.
//
// The concrete shape: `KillerName = killer.Name` added beside `Result` on the reveal, which is the
// NATURAL way to build a richer end screen. It reaches eight clients with `npm run verify` green.
//
// So an allowlisted remote must also declare the fields it may carry. Adding a field is now an edit to
// THIS file, which shows up in review — the same asymmetry that makes REVEAL_ALLOWLIST worth having.
export const PAYLOAD_FIELDS = new Map([
  // Types.RoundEndedPayload. The round is over; the reveal is the point (spec §4.8).
  ['RoundEnded', new Set(['Result', 'AswangUserId', 'RoundNumber'])],
  // Types.RoleAssignedPayload. Fired to ONE player, carrying ONLY that player's own role (spec §4.2).
  // A UserId here would be pointless (the receiver knows who they are) and a roster would be fatal.
  ['RoleAssigned', new Set(['Role'])]
])

// Field names assigned at the TOP LEVEL of a table constructor, given text starting at its `{`.
//
// `=(?!=)` so `Result = (a == b)` yields `Result` and not `a`. Depth 1 — not 0 — is the top level,
// because the constructor's own opening brace is the first token counted; getting that wrong returns
// an empty list for every payload, which reads exactly like "nothing to flag".
export const constructorFields = (body) => {
  const fields = []
  let depth = 0

  for (const token of body.matchAll(/[{}]|([A-Za-z_]\w*)\s*=(?!=)/g)) {
    if (token[0] === '{') depth += 1
    else if (token[0] === '}') depth -= 1
    else if (depth === 1 && token[1]) fields.push(token[1])
  }

  return fields
}

//[[
//  Resolve the payload of a Fire* call to a list of field names, following ONE level of indirection.
//
//  Three shapes reach this, and the third is the one that matters:
//    :FireAllClients({ Result = r })                  -> read inline
//    :FireClient(player, { Role = role })             -> read inline, past the player argument
//    local payload: T = { ... } ; :FireAllClients(payload) -> follow the local BACKWARDS
//
//  The third is what both real call sites use, because `FireAllClients` takes `...any` and a typed
//  local is the only thing that checks anything at all. A checker that cannot read it is a checker
//  that fires on hypotheticals.
//]]
export const payloadFieldsAt = (code, open) => {
  const args = argsAt(code, open)
  const inline = args.indexOf('{')

  if (inline !== -1) return constructorFields(args.slice(inline))

  const identifier = /([A-Za-z_]\w*)\s*\)?\s*$/.exec(args.trim())

  if (!identifier) return []

  // Backwards to the nearest declaration of that name. Bounded window: a payload built further away
  // than this is not one a reader would connect to the call either.
  const window = code.slice(Math.max(0, open - 1200), open)
  const declaration = new RegExp(`local\\s+${identifier[1]}\\s*(?::[^=]+)?=\\s*\\{`, 'g')
  let last = null

  for (const match of window.matchAll(declaration)) last = match

  if (!last) return []

  return constructorFields(window.slice(last.index + last[0].length - 1))
}

export const strayFields = (remote, fields) => {
  const allowed = PAYLOAD_FIELDS.get(remote)

  if (!allowed) return []

  return fields.filter(field => !allowed.has(field))
}

// Tokens that name the secret. Deliberately broad on the monster side and narrow on the generic side:
// `role` alone would match `RoleService`, so it only counts inside a payload.
//  `killer\w*` and `aswang\w*` are PREFIXES, not exact words, and that is the point of the change.
//
//  The old list enumerated `aswanguserid` and `iskiller` by hand and therefore matched neither
//  `KillerUserId` nor `KillerName` — the two most natural wrong fields this game will ever grow, on
//  exactly the broadcast C05 added. A killer field on `PlayerKilled` would have typechecked, scanned
//  clean and shipped, because §4.8 puts the reveal on the end screen and nothing else was watching.
//
//  Widening is safe because of WHERE this regex is applied: broadcast payloads, attribute names and
//  tag names — never general server code. `commitKill(killer, victim)` is untouched; a `killer` field
//  crossing to every client is not, and the `-- secrecy-ok: <reason>` waiver is there for the case
//  that turns out to be deliberate.
const SECRET = /\b(aswang\w*|imposter|impostor|monsteruserid|killer\w*|iskiller|isaswang|secretrole)\b/i
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

//  Drop the leading argument from an argument list — for `:FireClient(player, payload)`, the player.
//
//  The comma has to be found at DEPTH ZERO. `FireClient(p, { A = f(x, y), B = 2 })` contains commas
//  inside both a table and a call, and splitting on the first one would hand back a fragment that
//  parses as neither. Returns the whole string unchanged when there is no top-level comma, so a
//  one-argument call is never silently emptied.
const dropFirstArgument = args => {
  let depth = 0

  for (let i = 0; i < args.length; i += 1) {
    const char = args[i]

    if (char === '(' || char === '{' || char === '[') depth += 1
    else if (char === ')' || char === '}' || char === ']') depth -= 1
    else if (char === ',' && depth === 0) return args.slice(i + 1)
  }

  //  NO TOP-LEVEL COMMA MEANS NO PAYLOAD — return nothing, not the recipient.
  //
  //  Returning `args` here left `FireClient(killer)` scanning its own target, which is the exact
  //  false positive this function exists to remove, surviving on the one-argument shape. A signal
  //  remote fired at the Aswang with no payload is a plausible C14 salt-feedback call, and its only
  //  escape would be a waiver that then silences that line permanently.
  return ''
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

    // 0. THE FIELDS OF AN ALLOWLISTED REVEAL, wherever its payload was built.
    //
    // Separate from the scan below, and it has to be. That one only looks at calls whose ARGUMENT TEXT
    // names the secret — so a payload built as `local payload: Types.RoundEndedPayload = {...}` and
    // passed by name is skipped entirely, because `payload` matches no token. Both real reveal sites in
    // this repo are exactly that shape, so the first version of this check fired on neither of them: an
    // audit added `KillerName` to the real payload and the scan returned zero findings.
    //
    // FireClient too, not only FireAllClients — RoleAssigned is a per-player send and is the other
    // remote allowed to carry a role.
    for (const match of withStrings.matchAll(/:Fire(?:AllClients|Client)\s*\(/g)) {
      const remote = remoteNameBefore(withStrings, match.index)

      if (!remote || !REVEAL_ALLOWLIST.has(remote)) continue

      const open = match.index + match[0].length - 1
      const fields = payloadFieldsAt(code, open)
      const stray = strayFields(remote, fields)

      if (stray.length === 0) continue

      add(
        match.index,
        `\`${remote}\` carries ${stray.map(field => `\`${field}\``).join(', ')} — not on its field allowlist`,
        `An allowlisted reveal may carry ONLY ${[...(PAYLOAD_FIELDS.get(remote) ?? [])].join(', ')}. ` +
          'Being on REVEAL_ALLOWLIST exempts the CALL, never the PAYLOAD, and the typechecker does not ' +
          'help — Luau silently accepts an extra field on an annotated table. Add the field here, with ' +
          'a reason, if it genuinely belongs in the reveal.'
      )
    }

    //  1. Sends carrying the secret — BOTH `:FireAllClients` and `:FireClient`.
    //
    //  `:FireClient` was missing for a long time, and it is not the rare case: `broadcastSnapshot` in
    //  RoundService is a per-player `FireClient` loop, so "send this to everyone" is written that way
    //  in this codebase as often as not. A loop firing the Aswang's UserId to each player in turn
    //  reaches exactly as many clients as a broadcast and was invisible to this rule.
    //
    //  The allowlist still governs both, and `RoleAssigned` is on it precisely because it is a
    //  legitimate one-player `FireClient` carrying that player's own role.
    for (const match of code.matchAll(/:Fire(?:AllClients|Client)\s*\(/g)) {
      const open = match.index + match[0].length - 1

      //  THE RECIPIENT IS NOT THE PAYLOAD. `:FireClient(player, payload)` takes the target player
      //  first, and testing the whole argument text meant the RECIPIENT's name was scanned — so
      //  `FireClient(killer, { VictimUserId = v })` tripped the check the moment SECRET grew the
      //  `killer\w*` prefix. That is a false positive on the single most dangerous call site in the
      //  game: a send aimed at the Aswang. The only escape is a waiver, and a waiver disables the line
      //  permanently, including for a later edit that adds a genuinely leaky field to that same call.
      //  So the noise would have trained a silencer onto exactly the line that most needs watching.
      //
      //  `payloadFieldsAt` already skips the recipient; this makes the raw-text test agree with it.
      const args = match[0].includes('FireClient') ? dropFirstArgument(argsAt(code, open)) : argsAt(code, open)

      //  RESOLVE THE PAYLOAD, do not just read the argument text.
      //
      //  Testing `args` alone made this rule dead on every broadcast written in this repo's own house
      //  style. `FireAllClients(payload)` has an argument text of exactly seven characters — `payload`
      //  — so a table containing the literal `AswangUserId` scanned clean and shipped green. And the
      //  typed local is not an unusual shape here: `Types.luau`'s comments RECOMMEND it, because
      //  `FireAllClients` takes `...any` and an inline literal is checked against nothing at all. So
      //  the guard was defeated by the very idiom the codebase tells you to use.
      //
      //  `payloadFieldsAt` already does this resolution for rule 2 (the field allowlist), including
      //  walking back to a `local X = {` declaration. Rule 1 now shares it, so both rules see the same
      //  fields and there is one notion of "what this call actually carries".
      const fields = payloadFieldsAt(code, open)
      const carriesSecret =
        SECRET.test(args) ||
        ROLE_TOKEN.test(args) ||
        fields.some(field => SECRET.test(field) || ROLE_TOKEN.test(field))

      if (!carriesSecret) continue

      // `withStrings`, not `code`: the remote's NAME is a string literal, and `code` has string
      // contents blanked. Reading it from `code` made every call look like an unnamed remote, so the
      // allowlist could never match and the reveal itself was flagged. The two texts are the same
      // length by construction, so the index carries across.
      const remote = remoteNameBefore(withStrings, match.index)

      if (remote && REVEAL_ALLOWLIST.has(remote)) continue

      add(
        match.index,
        // `match[0]` rather than a hardcoded name: this loop matches both send forms now, and reporting
        // `:FireAllClients` at a `:FireClient` call site sends the reader looking for the wrong line.
        `${match[0].trim()} carries what looks like the Aswang's identity on ${remote ? `\`${remote}\`` : 'an unnamed remote'}`,
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

  //  THE TYPED-LOCAL PAYLOAD. Every BLOCK case above passes its table INLINE, which is why this rule
  //  looked healthy for so long while being dead on the shape this repo actually writes: `Types.luau`
  //  recommends the typed local precisely because `FireAllClients` takes `...any` and an inline
  //  literal is checked against nothing. Before the fix, the argument text was the seven characters
  //  `payload` and a table containing `AswangUserId` scanned completely clean.
  check(
    'the secret in a typed local payload, not inline',
    'local payload: Types.PlayerKilledPayload = { VictimUserId = v, AswangUserId = k }\n' +
      'Remotes.Get("PlayerKilled"):FireAllClients(payload)',
    true
  )
  check(
    'the secret in an untyped local payload',
    'local payload = { Role = role }\nRemotes.Get("PhaseChanged"):FireAllClients(payload)',
    true
  )
  check(
    'a killer field in a local payload on a non-allowlisted remote',
    'local payload = { VictimUserId = v, KillerUserId = k }\n'
      + 'Remotes.Get("PlayerKilled"):FireAllClients(payload)',
    true
  )

  //  A per-player `FireClient` LOOP reaches every client too, and this rule used to match only
  //  `:FireAllClients`. RoundService's own broadcastSnapshot is written this way, so the shape is
  //  idiomatic here rather than exotic — it was simply invisible.
  check(
    'a FireClient loop carrying the secret to every player in turn',
    'for _, p in Players:GetPlayers() do\n\tRemotes.Get("PhaseChanged"):FireClient(p, { AswangUserId = id })\nend',
    true
  )
  check(
    'a legitimate one-player FireClient on an allowlisted remote',
    'Remotes.Get("RoleAssigned"):FireClient(player, { Role = role })',
    false
  )

  //  THE RECIPIENT IS NOT THE PAYLOAD, in both directions. Widening SECRET to `killer\w*` made the
  //  target of a FireClient scannable, so a send TO the killer tripped the check on the variable name
  //  alone — a false positive on the most dangerous call site in the game, whose only escape is a
  //  waiver that would then silence that line forever. C14's salt feedback is the next real one.
  check(
    'a send addressed TO the killer, carrying nothing secret',
    'Remotes.Get("SaltEffect"):FireClient(killer, { VictimUserId = v })',
    false
  )
  check(
    'the same shape but the PAYLOAD carries the secret — must still block',
    'Remotes.Get("SaltEffect"):FireClient(target, { KillerUserId = k })',
    true
  )

  //  THESE THREE PIN THE DEPTH-AWARE SPLIT ITSELF, which is the whole substance of dropFirstArgument.
  //  An audit replaced it with a one-line `args.indexOf(',')` and the suite still reported 29/29 — the
  //  cases above exercise the BRANCH but not the parsing, so they could not tell a correct
  //  implementation from a naive one. Each of these dies under the naive split.
  //  The sharp one: the recipient expression contains a comma AND a secret-looking token after it.
  //  A naive `indexOf(',')` split keeps `killerPlayer), { … }` and flags a clean payload; the
  //  depth-aware split drops the whole recipient and correctly allows. The `pick(a, b)` pair below
  //  does NOT discriminate — a naive split happens to give the right answer on both — so this case is
  //  the one carrying the weight.
  check(
    'a recipient expression whose own arguments look secret, with a clean payload',
    'Remotes.Get("SaltEffect"):FireClient(pick(a, killerPlayer), { VictimUserId = v })',
    false
  )
  check(
    'a recipient expression containing its own comma, with a clean payload',
    'Remotes.Get("SaltEffect"):FireClient(pick(a, b), { VictimUserId = v })',
    false
  )
  check(
    'the same, but the payload really does carry the secret',
    'Remotes.Get("SaltEffect"):FireClient(pick(a, b), { KillerUserId = k })',
    true
  )
  // A one-argument send has no payload at all, so there is nothing to scan and nothing to flag.
  check('a payload-less send addressed to the killer', 'Remotes.Get("SaltEffect"):FireClient(killer)', false)


  // ALLOW — every one of these is correct code that a blunter check would refuse.
  check('the end-of-round reveal', 'Remotes.Get("RoundEnded"):FireAllClients({ AswangUserId = id })', false)

  // THE FIELD ALLOWLIST. Being on REVEAL_ALLOWLIST exempts the CALL, never the PAYLOAD — and the
  // typechecker does not help either, because Luau silently accepts an extra field on an annotated
  // table. Before this pair of cases both guards were off on the two remotes that carry the secret.
  check(
    'a stray name smuggled onto the reveal',
    'Remotes.Get("RoundEnded"):FireAllClients({ Result = r, AswangUserId = id, KillerName = killer.Name })',
    true
  )
  check(
    'the reveal carrying only its declared fields',
    'Remotes.Get("RoundEnded"):FireAllClients({ Result = r, AswangUserId = id, RoundNumber = n })',
    false
  )
  check(
    'a roster smuggled onto the private role assignment',
    'Remotes.Get("RoleAssigned"):FireAllClients({ Role = role, Roster = everyone })',
    true
  )

  // THE SHAPE THE REAL CODE USES, and the one the first version of this check could not see. Both
  // reveal sites build a TYPED LOCAL and pass the variable, because FireAllClients takes `...any` and
  // the annotation is the only thing checking anything. An audit proved the inline-only version
  // returned zero findings against the real file — a checker that only fires on hypotheticals.
  check(
    'a stray field on a payload built as a typed local',
    'local payload: Types.RoundEndedPayload = {\n\tResult = r,\n\tKillerName = k,\n}\nRemotes.Get("RoundEnded"):FireAllClients(payload)',
    true
  )
  check(
    'a typed-local payload carrying only declared fields',
    'local payload: Types.RoundEndedPayload = {\n\tResult = r,\n\tRoundNumber = n,\n}\nRemotes.Get("RoundEnded"):FireAllClients(payload)',
    false
  )
  check(
    'a stray field on a per-player RoleAssigned local',
    'local payload: Types.RoleAssignedPayload = {\n\tRole = role,\n\tOthers = roster,\n}\nRemotes.Get("RoleAssigned"):FireClient(player, payload)',
    true
  )
  check(
    'a nested value is not mistaken for a stray field',
    'Remotes.Get("RoundEnded"):FireAllClients({ Result = r, RoundNumber = { n = 1 } })',
    false
  )
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
