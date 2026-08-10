#!/usr/bin/env node
// PreToolUse guard on Bash: blocks destructive commands that reach outside this repository, and the
// handful of in-repo commands that destroy work irrecoverably.
//
// The rule it enforces is simple and unconditional:
//
//   A command may delete, overwrite, or move things INSIDE this repo (and the OS temp dir). Anything
//   reaching outside is denied — no exceptions, no heuristics about intent.
//
// It also denies four commands that destroy work without ever calling `rm`. These are the ones a naive
// "block rm" guard misses:
//
//   git clean -fdx      removes untracked+ignored files
//   git reset --hard    discards uncommitted changes
//   git checkout -- .   same
//   git restore .       same
//
// Deliberately NOT exhaustive against a determined adversary — shell is too flexible for that. It is
// built to stop a confused agent, which is the actual threat.
//
// Test it without running anything:
//   echo '{"tool_input":{"command":"rm -rf ~/Documents"}}' | node .claude/scripts/guard-destructive.mjs

import { tmpdir } from 'node:os'
import { resolve, sep } from 'node:path'

const REPO = process.cwd()

// Destructive commands whose path arguments must stay inside the repo.
const DESTRUCTIVE = /^(rm|rmdir|unlink|shred|truncate|mv|dd|chown|chmod|cp|ln|tee|rsync)$/

// Interpreters that take code as a string argument. Their contents cannot be parsed reliably, so any
// destructive-looking payload is refused rather than guessed at.
const INTERPRETERS = /^(eval|bash|sh|zsh|ksh|node|nodejs|python|python3|perl|ruby|osascript|lune)$/

const DESTRUCTIVE_PAYLOAD = /\b(rm\b|rmdir|unlink|rmtree|rmSync|shutil|removeSync|remove_tree|shred|mkfs)/

// Catastrophic patterns. Each is scoped to the binary actually being invoked, and matched against a
// SINGLE COMMAND SEGMENT — never against the whole command string. Without that scoping,
// `grep -rn "git clean" docs/` gets blocked, and a guard that cries wolf is a guard you switch off.
export const NEVER = [
  { binary: 'rm', pattern: /\s\/(\s|$)/, why: 'rm targeting the filesystem root' },
  { binary: 'rm', pattern: /\s(~|\$HOME)(\/\s*)?(\s|$)/, why: 'rm targeting your home directory' },
  { binary: 'rm', pattern: /\s\.git(\/\s*)?(\s|$)/, why: 'deleting the .git directory destroys all history' },
  { binary: 'sudo', pattern: /./, why: 'sudo — this agent must never escalate privileges' },
  { binary: 'mkfs', pattern: /./, why: 'formatting a filesystem' },
  { binary: 'dd', pattern: /of=\/dev\//, why: 'writing to a raw device' },
  {
    binary: 'git',
    pattern: /^git\s+clean\b.*-[a-zA-Z]*f/,
    why:
      'git clean -f deletes untracked files with no way back. Run `git clean -n` to see what it would ' +
      'remove, then delete what you actually mean by name.'
  },
  { binary: 'git', pattern: /^git\s+reset\b.*--hard/, why: 'git reset --hard discards uncommitted work' },
  { binary: 'git', pattern: /^git\s+checkout\b.*\s--\s+\.(\s|$)/, why: 'git checkout -- . discards uncommitted work' },
  { binary: 'git', pattern: /^git\s+restore\b(?!.*--staged).*\s\.(\s|$)/, why: 'git restore . discards uncommitted work' },
  { binary: 'find', pattern: /-delete\b/, why: 'find -delete — use an explicit path list instead' },
  { binary: 'find', pattern: /-exec\s+rm\b/, why: 'find -exec rm — use an explicit path list instead' },

  // ── REPO-SPECIFIC ────────────────────────────────────────────────────────────
  //
  // Place files are gitignored, binary, and NOT in version control — the map lives in Studio and in
  // Roblox's cloud place-version history. `rm build/aswang.rbxl` is harmless (it is regenerated), but
  // deleting a `.rbxl` a person has been building in is unrecoverable from this machine. The README's
  // whole backup story is "publish regularly", so the local file may be ahead of the cloud.
  {
    binary: 'rm',
    pattern: /\.rbxlx?\b/,
    why:
      'deleting a Roblox place file. Place files are gitignored and hold the MAP, which git cannot ' +
      'restore. If this is only build output, delete the build/ directory by name instead.'
  }
]

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const deny = reason => {
  process.stdout.write(
    `${JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason
      }
    })}\n`
  )
  process.exit(0)
}

// Somewhere the command is allowed to destroy things.
const isInsideSafeArea = absolute => {
  const areas = [REPO, resolve(tmpdir()), '/private/tmp', '/tmp']

  return areas.some(area => absolute === area || absolute.startsWith(area + sep))
}

// Split on shell separators so `cd /; rm -rf x` is examined as two commands.
const splitCommands = command =>
  command
    .split(/(?:&&|\|\||[;\n|])/g)
    .map(part => part.trim())
    .filter(Boolean)

const tokenize = segment => segment.match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? []

const unquote = token => token.replace(/^['"]|['"]$/g, '')

// Exported as one function so the suite drives the identical decision the hook does. A test that
// re-implements the logic tests the test.
export const judge = command => {
  if (typeof command !== 'string' || !command.trim()) return null

  // Fork bomb is a shape, not a binary — the only whole-string check.
  if (/:\(\)\s*\{.*\}\s*;\s*:/.test(command)) return 'Blocked: fork bomb.'

  const segments = splitCommands(command)

  // `cd` moves the ground under every later segment, so `cd ~ && rm -rf Documents` reads as an in-repo
  // relative path while actually deleting your home directory. That is a natural phrasing, not an
  // evasion, so once the command leaves the repo nothing destructive follows.
  const leavesRepo = segments.some(segment => {
    const match = segment.match(/^cd\s+(?!-)(\S+)/)

    if (!match) return false

    const target = unquote(match[1])

    if (/^(~|\$HOME)/.test(target)) return true

    return !isInsideSafeArea(resolve(REPO, target))
  })

  if (leavesRepo) {
    // Only genuinely destructive binaries. `git` and `find` are NOT included: `cd ../other && git log`
    // is ordinary read-only work, and the dangerous forms of both are caught by segment-scoped patterns
    // that do not depend on the working directory at all.
    const anyDestructive = segments.some(segment => {
      const first = tokenize(segment)[0]

      return Boolean(first) && DESTRUCTIVE.test(unquote(first).split('/').pop())
    })

    if (anyDestructive) {
      return (
        'Blocked: this command changes directory to somewhere outside the repository and then runs a ' +
        'destructive command. Relative paths after a `cd` are not what they appear to be.'
      )
    }
  }

  // Redirects overwrite files without any destructive binary being involved.
  //
  // The lookbehind matters more than it appears: without it, the `=>` in an arrow function inside
  // `node -e "…"` reads as a redirect and the whole command is refused. Same for `->`, `>=`, `<>`.
  //
  // A shell redirect only operates OUTSIDE quotes, so quoted payloads are stripped first — otherwise
  // `node -e "…> ~/x"`, a string that merely CONTAINS a redirect, is refused. Escaped quotes must not
  // end the span early: double quotes honour backslash escapes, POSIX single quotes do not.
  //
  // KNOWN LIMIT, recorded rather than fixed: heredoc BODIES are still scanned, so a script containing a
  // redirect-looking string is refused even though the shell never sees it. Use Write/Edit for such
  // content instead, which involves no shell at all.
  const unquotedOnly = command.replace(/"(?:\\.|[^"\\])*"|'[^']*'/g, ' ')

  for (const match of unquotedOnly.matchAll(/(?<![=<>!-])>{1,2}\s*([^\s;|&()]+)/g)) {
    const target = unquote(match[1])

    if (/^(~|\$HOME)/.test(target)) return `Blocked: redirecting output to ${target}, which is outside this repository.`

    if (/^\/dev\/(null|stdout|stderr|tty)$/.test(target)) continue

    const absolute = resolve(REPO, target)

    if (!isInsideSafeArea(absolute)) {
      return `Blocked: redirecting output to a path outside this repository.\n\n  target: ${absolute}`
    }
  }

  for (const segment of segments) {
    const tokens = tokenize(segment)

    if (tokens.length === 0) continue

    // Skip env-var prefixes (FOO=bar cmd) to find the real binary.
    const firstReal = tokens.find(token => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(unquote(token))) ?? tokens[0]
    const binary = unquote(firstReal).split('/').pop()

    for (const entry of NEVER) {
      if (entry.binary !== binary) continue
      if (entry.pattern.test(segment)) return `Blocked: ${entry.why}.\n\nCommand: ${segment.trim().slice(0, 300)}`
    }

    if (INTERPRETERS.test(binary) && DESTRUCTIVE_PAYLOAD.test(segment)) {
      return (
        `Blocked: \`${binary}\` invoked with a destructive payload. This guard cannot verify what paths ` +
        `it would touch. Run the deletion directly with explicit paths so it can be checked.`
      )
    }

    // `xargs rm` receives its targets on stdin, so they cannot be inspected at all.
    if (binary === 'xargs' && /\b(rm|rmdir|unlink|shred)\b/.test(segment)) {
      return 'Blocked: `xargs rm` — the targets arrive on stdin and cannot be checked. Use an explicit path list.'
    }

    // `git -C <path>` relocates git, the same trap as `cd`.
    if (binary === 'git') {
      const dirFlag = segment.match(/-C\s+("[^"]+"|'[^']+'|\S+)/)

      if (dirFlag) {
        const target = unquote(dirFlag[1])
        const outside = /^(~|\$HOME)/.test(target) || !isInsideSafeArea(resolve(REPO, target))

        if (outside) return `Blocked: \`git -C ${target}\` operates on a repository outside this one.`
      }
    }

    if (binary === 'rsync' && /--delete/.test(segment)) {
      return 'Blocked: `rsync --delete` can remove files at the destination. Use an explicit deletion instead.'
    }

    if (!DESTRUCTIVE.test(binary)) continue

    for (const raw of tokens.slice(1)) {
      const token = unquote(raw)

      if (token.startsWith('-')) continue

      if (/^(~|\$HOME)/.test(token)) {
        return `Blocked: \`${binary}\` targeting ${token}, which is outside this repository.`
      }

      // A shell variable expands at runtime, so its target cannot be checked here.
      // `T=~/Documents && rm -rf $T` looks harmless to any static reader.
      if (/\$\{?\w/.test(token)) {
        return (
          `Blocked: \`${binary}\` targeting ${token} — a shell variable whose value cannot be verified ` +
          `before the command runs. Write the path out in full so it can be checked.`
        )
      }

      const absolute = resolve(REPO, token)

      if (!isInsideSafeArea(absolute)) {
        return (
          `Blocked: \`${binary}\` targeting a path outside this repository.\n\n` +
          `  target: ${absolute}\n  repo:   ${REPO}\n\n` +
          `If you genuinely need this, ask the user to run it themselves.`
        )
      }

      if ((binary === 'rm' || binary === 'mv') && absolute === REPO) {
        return 'Blocked: that would remove the repository root itself.'
      }
    }
  }

  return null
}

if (process.argv[1]?.endsWith('guard-destructive.mjs')) {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    process.exit(0)
  }

  const verdict = judge(payload?.tool_input?.command)

  if (verdict) deny(verdict)

  process.exit(0)
}
