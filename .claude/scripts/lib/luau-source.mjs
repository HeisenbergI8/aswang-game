// Shared source reader for every check under .claude/scripts/.
//
// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────────
//
// Every check here answers a question about Luau source by matching text. That makes each one
// vulnerable to the same bug in two ways:
//
//   USE vs MENTION — a comment saying "never fire the role to all clients" contains the exact tokens
//   the secrecy check hunts for. Matching raw source means any file DOCUMENTING a rule trips the
//   check written to enforce it. That has bitten this class of tool repeatedly; the fix is to strip
//   comments and string literals ONCE, here, rather than in five files that will drift apart.
//
//   LINE ATTRIBUTION — a finding without a `file:line` is unactionable, so stripping must preserve
//   line count. Every removal below substitutes spaces rather than deleting, so line N stays line N.

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

export const SRC = 'src'

export const listLuau = (root = SRC) => {
  const found = []

  const walk = dir => {
    let entries

    try {
      entries = readdirSync(dir)
    } catch {
      return
    }

    for (const name of entries.sort()) {
      const path = join(dir, name)

      if (statSync(path).isDirectory()) walk(path)
      else if (name.endsWith('.luau') || name.endsWith('.lua')) found.push(path)
    }
  }

  walk(root)

  return found.map(path => relative(process.cwd(), path))
}

const blank = text => ' '.repeat(text.length)

// Replaces comments and string literals with spaces, preserving every newline and every offset.
//
// Handles, in this order: long comments `--[[ ]]` and `--[==[ ]==]`, line comments `--`, long strings
// `[[ ]]`, quoted strings, and Luau interpolated strings `` `...` ``. Interpolation is treated as a
// string wholesale, which is correct for these checks: `` `Role is {role}` `` is text, not a use.
export const stripNonCode = source => {
  let out = ''
  let i = 0

  const n = source.length

  while (i < n) {
    const rest = source.slice(i)

    // Long comment: --[=*[ ... ]=*]
    const longComment = /^--\[(=*)\[/.exec(rest)

    if (longComment) {
      const close = `]${longComment[1]}]`
      const end = source.indexOf(close, i + longComment[0].length)
      const stop = end === -1 ? n : end + close.length
      const span = source.slice(i, stop)

      out += span.replace(/[^\n]/g, ' ')
      i = stop
      continue
    }

    // Line comment
    if (rest.startsWith('--')) {
      const end = source.indexOf('\n', i)
      const stop = end === -1 ? n : end

      out += blank(source.slice(i, stop))
      i = stop
      continue
    }

    // Long string: [=*[ ... ]=*]
    const longString = /^\[(=*)\[/.exec(rest)

    if (longString) {
      const close = `]${longString[1]}]`
      const end = source.indexOf(close, i + longString[0].length)
      const stop = end === -1 ? n : end + close.length
      const span = source.slice(i, stop)

      out += span.replace(/[^\n]/g, ' ')
      i = stop
      continue
    }

    const quote = source[i]

    if (quote === '"' || quote === "'" || quote === '`') {
      let j = i + 1

      while (j < n) {
        if (source[j] === '\\') {
          j += 2
          continue
        }

        if (source[j] === quote || source[j] === '\n') break

        j += 1
      }

      const stop = Math.min(j + (source[j] === quote ? 1 : 0), n)
      const span = source.slice(i, stop)

      out += span.replace(/[^\n]/g, ' ')
      i = stop
      continue
    }

    out += quote
    i += 1
  }

  return out
}

// Same as above but KEEPS string literal contents, because some checks are about the strings
// themselves — a remote name, an attribute key. Comments are still removed, so a rule quoted in a
// comment cannot trip a check.
export const stripComments = source => {
  let result = ''
  let i = 0

  const n = source.length

  while (i < n) {
    const rest = source.slice(i)
    const longComment = /^--\[(=*)\[/.exec(rest)

    if (longComment) {
      const close = `]${longComment[1]}]`
      const end = source.indexOf(close, i + longComment[0].length)
      const stop = end === -1 ? n : end + close.length

      result += source.slice(i, stop).replace(/[^\n]/g, ' ')
      i = stop
      continue
    }

    if (rest.startsWith('--')) {
      const end = source.indexOf('\n', i)
      const stop = end === -1 ? n : end

      result += blank(source.slice(i, stop))
      i = stop
      continue
    }

    result += source[i]
    i += 1
  }

  return result
}

export const readSource = path => {
  const raw = readFileSync(path, 'utf8')

  return { path, raw, code: stripNonCode(raw), withStrings: stripComments(raw) }
}

export const lineOf = (text, index) => text.slice(0, index).split('\n').length

// ── The escape hatch ───────────────────────────────────────────────────────────
//
// A guard with no way to say "yes, deliberately" gets switched off the first time it is wrong, and
// then it protects nothing. Every check here honours a trailing comment on the offending line:
//
//   Remotes.Get("RoundEnded"):FireAllClients(payload) -- secrecy-ok: the round is over, this is the reveal
//
// The REASON is mandatory. An opt-out with no reason is a silent disable wearing a comment's clothes,
// and the point is that a reviewer reading the diff can weigh it.
export const hasWaiver = (rawLines, lineNumber, tag) => {
  const line = rawLines[lineNumber - 1] ?? ''
  const match = new RegExp(`--\\s*${tag}-ok:\\s*(\\S.*)$`).exec(line)

  return match ? match[1].trim() : null
}

export const report = (name, findings, { note = '' } = {}) => {
  for (const finding of findings) {
    console.error(`  FAIL  ${finding.file}:${finding.line} — ${finding.why}`)
    if (finding.detail) console.error(`        ${finding.detail}`)
  }

  if (findings.length) {
    console.error(`- ${name}: ${findings.length} finding(s)`)

    return 1
  }

  console.log(`- ${name}: ok${note ? ` (${note})` : ''}`)

  return 0
}
