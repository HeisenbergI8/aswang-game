#!/usr/bin/env node
// PreToolUse guard: denies Write/Edit outside a per-agent allowlist of paths.
//
// Registered SESSION-WIDE in .claude/settings.json, and scoped per agent here IN THE SCRIPT by reading
// `agent_type` off the hook payload.
//
// It is not declared in each subagent's frontmatter `hooks:` block. That is documented as "scoped to
// this subagent" and has been observed not to fire, while settings.json hooks fired normally in the
// same session. Config-level scoping is therefore not trustworthy; script-level scoping is, because
// `agent_type` is on the payload and this file decides what to do with it. (`tools:` in frontmatter
// DOES work — that is how the auditors lose Edit/Write entirely.)
//
// The main thread and unlisted agents are unrestricted. This guard holds specific agents to their
// stated role; it does not lock down the session.
//
// IMPORTANT: for a listed agent it fails CLOSED. If the payload cannot be parsed or carries no
// file_path, the write is denied. A guard that fails open is worse than no guard, because it produces
// confidence it has not earned.

import { tmpdir } from 'node:os'
import { relative, resolve, sep } from 'node:path'

// Scratch space is legitimate: the session scratchpad and OS temp live outside the repo and are meant
// to be written to. Everything else outside the repo is not.
const SAFE_OUTSIDE = [resolve(tmpdir()), '/private/tmp', '/tmp', '/private/var/folders', '/var/folders']

const isScratch = absolute => SAFE_OUTSIDE.some(area => absolute === area || absolute.startsWith(area + sep))

// `agent_type` is the `name:` from the agent's frontmatter, not the filename.
export const RULES = {
  // Plans, not code. The architect designs; it does not build.
  architect: ['.claude/plans'],

  // Its report and its artifacts, plus Lune tests it was asked to add. NEVER the source under test —
  // a playtester that repairs what it tests produces a report describing its own edits.
  playtester: ['.claude/plans', 'tests']
}

// A single Write to a plan document larger than this is refused, so the architect writes a skeleton and
// fills phases in with Edit.
//
// HONEST LIMIT: this cannot prevent the failure that motivates it. A PreToolUse hook only sees calls
// that were EMITTED, and the expensive form of this failure is a generation that times out before the
// call is emitted — costing an hour and saving zero bytes, because a Write is atomic. What this does
// prevent is the monolithic write that SUCCEEDS, which is how the habit survives.
export const PLAN_WRITE_MAX_LINES = 600

const isUnder = (target, prefix) => target === prefix || target.startsWith(`${prefix}/`)

// Minimal glob: `**` crosses directory separators, `*` does not.
const globToRegExp = pattern => {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  const body = escaped.replace(/\*\*/g, ' ').replace(/\*/g, '[^/]*').replace(/ /g, '.*')

  return new RegExp(`^${body}$`)
}

export const permits = (agentType, target) => {
  const allowed = RULES[agentType]

  if (!allowed) return true

  return allowed.some(rule => (rule.includes('*') ? globToRegExp(rule).test(target) : isUnder(target, rule)))
}

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

const main = async () => {
  let payload

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    // An unparseable payload cannot be attributed to a restricted agent, so it cannot be judged.
    // Allowing is correct here: the alternative blocks every write in the session.
    process.exit(0)
  }

  const allowed = RULES[payload?.agent_type]
  const filePath = payload?.tool_input?.file_path

  // Containment applies to EVERY agent and to the main thread — not just the two with role rules.
  // Writing outside the repository is never legitimate here.
  if (typeof filePath === 'string' && filePath) {
    const absolute = resolve(process.cwd(), filePath)
    const outside = relative(process.cwd(), absolute).startsWith('..')

    if (outside && !isScratch(absolute)) {
      deny(
        `Writing outside this repository is not permitted (${filePath}). Scratch files belong in the ` +
          `session scratchpad or ${tmpdir()}. If this file genuinely belongs elsewhere, ask the user to ` +
          `place it themselves.`
      )
    }
  }

  if (!allowed) process.exit(0)

  if (typeof filePath !== 'string' || !filePath) {
    deny(`guard-agent-write.mjs saw no file_path on a ${payload?.tool_name ?? 'unknown'} call`)
  }

  const target = relative(process.cwd(), resolve(process.cwd(), filePath))

  // Allowed path, but not in one shot. Write only — an Edit appending a phase is the protocol working.
  if (permits(payload.agent_type, target) && payload.agent_type === 'architect' && payload.tool_name === 'Write' && target.endsWith('.md')) {
    const lines = String(payload.tool_input?.content ?? '').split('\n').length

    if (lines > PLAN_WRITE_MAX_LINES) {
      deny(
        `That is a ${lines}-line Write to a plan document; the ceiling for a single Write is ` +
          `${PLAN_WRITE_MAX_LINES}. Write the SKELETON first — title, Plan Overview, and every ` +
          `"### Phase N" / "#### Step N.M" heading with its **File:** and **Verify:** lines and a ` +
          `one-sentence intent, no diff blocks. Then append one phase per Edit call. A Write is atomic: ` +
          `if generation times out you save zero bytes.`
      )
    }
  }

  if (permits(payload.agent_type, target)) process.exit(0)

  deny(
    `The ${payload.agent_type} agent may only write to: ${allowed.join(', ')}. Blocked write to ${target}. ` +
      `If this file genuinely needs changing, report it instead of editing it.`
  )
}

if (process.argv[1]?.endsWith('guard-agent-write.mjs')) main()
