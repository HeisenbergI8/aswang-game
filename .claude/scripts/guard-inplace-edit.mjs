#!/usr/bin/env node
// PreToolUse guard on Bash: refuses `perl -i` / `sed -i` style edits to files Rojo is watching.
//
//   node .claude/scripts/guard-inplace-edit.mjs            reads a hook payload on stdin
//   node .claude/scripts/guard-inplace-edit.mjs --self-test
//
// ── WHY THIS EXISTS: IT CRASHES ROJO, AND THE CRASH IS INVISIBLE ───────────────
//
// `perl -i` and `sed -i` do NOT edit in place. They write a sibling temp file in the same directory and
// rename it over the original. Rojo 7.7.0's file watcher sees the temp file appear, tries to canonicalize
// it, finds it already renamed away, and panics:
//
//   [ERROR rojo] Rojo crashed! You are running Rojo 7.7.0.
//   Details: called `Result::unwrap()` on an `Err` value: Custom { kind: NotFound,
//     error: Error { kind: Canonicalize, ... path: ".../src/shared/XXza2moh" } }
//   in file src/change_processor.rs on line 172
//
// Observed three times in one session. What makes it worth a guard rather than a note is the SHAPE of
// the failure: the edit succeeds on disk, the shell reports success, and the server dies silently in a
// background process nobody is watching. Every subsequent edit then goes nowhere, Studio keeps serving
// the tree it already had, and any verification done against it describes code from before the crash.
//
// That is the same false-green this repo's Rojo checks exist to catch — `ensure-rojo.mjs` restarts the
// dead server and `preflight`'s `rojo-synced` refuses to call it evidence — but catching it after the
// fact still costs the session. This removes the cause.
//
// ── NARROW BY CONSTRUCTION ─────────────────────────────────────────────────────
//
// It denies ONLY the combination of an in-place-rewrite tool AND a path under a Rojo-watched root.
// `perl -i` over `docs/`, `sed -i` over `.claude/`, and every read-only use stay allowed — including
// `grep -i`, which is ignore-case and has nothing to do with this.
//
// The fix is never "disable the guard": write the whole file instead. `node -e "fs.writeFileSync(...)"`,
// a `>` redirect, and the Edit/Write tools all truncate the existing inode without creating a sibling,
// and Rojo handles them correctly.

// The roots Rojo watches, from default.project.json. A rewrite anywhere under these can kill the server.
export const WATCHED_ROOTS = ['src', 'vendor']

// Tools whose in-place flag is implemented as write-temp-then-rename.
const REWRITERS = /^(perl|sed|ruby|gsed|gawk)$/

// sed: `-i`, `-i.bak`, `-i ''`. perl/ruby: a flag cluster containing `i`, e.g. `-i`, `-pi`, `-0pi`.
const SED_INPLACE = /^-i/
const CLUSTER_INPLACE = /^-[0-9a-zA-Z]*i/

const PATH_IN_WATCHED = new RegExp(`(^|[\\s'"=(])(\\./)?(${WATCHED_ROOTS.join('|')})/`)

// ── The decision ───────────────────────────────────────────────────────────────
//
// PURE and exported, so both directions are pinned without a shell.
export const inPlaceRisk = command => {
  const text = String(command ?? '')

  if (!PATH_IN_WATCHED.test(text)) return null

  // Split on shell separators so `grep -i foo src/x | sed 's/a/b/'` is judged per segment rather than
  // as one soup — otherwise any `-i` anywhere would convict any tool anywhere.
  for (const segment of text.split(/\|\||&&|[;|\n]/)) {
    const tokens = segment.trim().split(/\s+/).filter(Boolean)
    if (!tokens.length) continue

    // Skip a leading env assignment or `sudo`-style prefix.
    let at = 0
    while (at < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[at])) at += 1
    if (at >= tokens.length) continue

    const tool = (tokens[at].split('/').pop() ?? '').trim()
    if (!REWRITERS.test(tool)) continue

    const flags = tokens.slice(at + 1)
    const isSed = tool === 'sed' || tool === 'gsed'
    const inPlace = flags.some(token =>
      token.startsWith('--') ? token === '--in-place' || token.startsWith('--in-place=') : isSed ? SED_INPLACE.test(token) : CLUSTER_INPLACE.test(token)
    )

    if (!inPlace) continue
    // The path must be in THIS segment, not merely somewhere in the command line.
    if (!PATH_IN_WATCHED.test(segment)) continue

    return { tool, segment: segment.trim() }
  }

  return null
}

const deny = reason => {
  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason }
    })}\n`
  )
  process.exit(0)
}

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
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

  const denied = command => inPlaceRisk(command) !== null

  // ── DENY: the exact shapes that crashed Rojo this session ───────────────────
  check('perl -0pi over src', denied(`perl -0pi -e 's/a/b/' src/shared/Config.luau`), true)
  check('perl -pi over src', denied(`perl -pi -e 's/a/b/' src/server/Services/RoundService.luau`), true)
  check('perl -i over src', denied(`perl -i -pe 's/a/b/' src/shared/Config.luau`), true)
  check('sed -i with a mac empty suffix', denied(`sed -i '' 's/a/b/' src/client/Controllers/UIController.luau`), true)
  check('sed -i with a backup suffix', denied(`sed -i.bak 's/a/b/' src/shared/Enums.luau`), true)
  check('sed --in-place long form', denied(`sed --in-place 's/a/b/' src/shared/Types.luau`), true)
  check('a leading ./ path still counts', denied(`perl -0pi -e 's/a/b/' ./src/shared/Config.luau`), true)
  check('vendor is watched too', denied(`sed -i '' 's/a/b/' vendor/Promise.luau`), true)
  check('risky segment after a safe one', denied(`grep -n foo src/shared/Config.luau; sed -i '' 's/a/b/' src/shared/Config.luau`), true)
  check('an env prefix does not hide it', denied(`LC_ALL=C sed -i '' 's/a/b/' src/shared/Config.luau`), true)
  check('the finding names the tool', inPlaceRisk(`perl -0pi -e 's/a/b/' src/shared/Config.luau`).tool, 'perl')

  // ── ALLOW: the half that matters. A guard that blocks real work gets disabled ─
  check('perl -i outside the watched roots', denied(`perl -0pi -e 's/a/b/' docs/BUILD-PLAN.md`), false)
  check('sed -i over the harness itself', denied(`sed -i '' 's/a/b/' .claude/scripts/preflight.mjs`), false)
  check('sed -i over tests', denied(`sed -i '' 's/a/b/' tests/config.test.luau`), false)
  check('reading src with sed -n', denied(`sed -n '1,20p' src/shared/Config.luau`), false)
  // grep's -i is ignore-case. Convicting it would make the guard useless within a day.
  check('grep -i over src is ignore-case, not in-place', denied(`grep -i aswang src/shared/Config.luau`), false)
  check('grep -i piped from cat', denied(`cat src/shared/Config.luau | grep -i solo`), false)
  check('perl with no in-place flag', denied(`perl -e 'print 1' src/shared/Config.luau`), false)
  check('a whole-file node write is the RECOMMENDED fix', denied(`node -e "fs.writeFileSync('src/shared/Config.luau', t)"`), false)
  check('a redirect truncates in place and is safe', denied(`cat committed.luau > src/shared/Config.luau`), false)
  check('awk without gawk inplace', denied(`awk '{print}' src/shared/Config.luau`), false)
  check('no path at all', denied(`perl -0pi -e 's/a/b/' README.md`), false)
  check('empty command', denied(''), false)
  check('null command', denied(null), false)
  // `src` as a bare word, not a path, must not arm the check.
  check('the word src without a slash is not a path', denied(`sed -i '' 's/src/dst/' docs/x.md`), false)

  console.log(failures ? `  FAIL  guard-inplace-edit: ${ran - failures}/${ran}` : `  PASS  guard-inplace-edit: ${ran}/${ran} cases`)

  return failures ? 1 : 0
}

if (process.argv[1]?.endsWith('guard-inplace-edit.mjs')) {
  if (process.argv.includes('--self-test')) process.exit(selfTest())

  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const risk = inPlaceRisk(payload?.tool_input?.command)

  if (!risk) process.exit(0)

  deny(
    `\`${risk.tool} -i\` on a Rojo-watched path CRASHES the Rojo server (7.7.0, change_processor.rs:172).\n\n` +
      `It writes a sibling temp file and renames over the original; Rojo's watcher canonicalizes the temp ` +
      `file after it is gone and panics on an unwrap. The edit SUCCEEDS on disk and the server dies in the ` +
      `background — so every later edit goes nowhere and Studio keeps serving the tree it already had.\n\n` +
      `Blocked: ${risk.segment}\n\n` +
      `Write the whole file instead — these truncate the existing inode and Rojo handles them fine:\n` +
      `  node -e "require('fs').writeFileSync('<path>', text)"\n` +
      `  the Edit or Write tool\n` +
      `  a \`>\` redirect\n\n` +
      `If the server has already died, \`npm run rojo:status\` will say so.`
  )
}
