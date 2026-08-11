#!/usr/bin/env node
// `/build` — the loop's entry point, and the pause that keeps it out of the user's way.
//
// Registered on `UserPromptSubmit`. Reads the prompt, and:
//
//   /build <milestone> [--tier small|medium|large]   creates the run record ITSELF
//   /build --status | --halt | --resume              steers a live run
//   anything else, while a run is live               pauses the run
//
// ── A SKILL IS INSTRUCTIONS TO THE MODEL; THIS IS A MECHANISM ─────────────────
//
// If the model is merely *told* to run `run-state.mjs init` and does not, there is no run — and the
// driver releases forever, which is INDISTINGUISHABLE FROM WORKING CORRECTLY. That is the
// directive-not-mechanism failure appearing at the loop's entry point, where it is least visible. So
// the hook writes the state; the skill carries only the narrative and the tier reasoning.
//
// ── WHY A USER MESSAGE PAUSES ─────────────────────────────────────────────────
//
// Stated rather than left implicit: a user message PAUSES the run, it does not amend the objective.
// The loop advances only while the user is silent. The alternative — a loop that reinterprets its goal
// from conversation — is how a run quietly becomes something nobody asked for.

import { activeRun, halt, init, update } from './run-state.mjs'

// `/build*` is exempt from the pause, or the pause fires on the very message meant to clear it:
// `--resume` is itself a user prompt, and whether it worked would depend on hook-versus-skill ordering
// within the turn. Not something to leave to chance.
export const isBuildCommand = prompt => /^\s*\/build\b/.test(prompt ?? '')

export const parseBuild = prompt => {
  const text = (prompt ?? '').trim()

  if (!isBuildCommand(text)) return null

  const args = text
    .replace(/^\s*\/build\b/, '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)

  const flag = name => args.includes(`--${name}`)
  const value = name => {
    const at = args.indexOf(`--${name}`)

    return at === -1 ? null : (args[at + 1] ?? null)
  }

  return {
    status: flag('status'),
    halt: flag('halt'),
    resume: flag('resume'),
    tier: value('tier'),
    // The first non-flag token. `--tier medium` must not be mistaken for the milestone name.
    milestone: args.find((arg, i) => !arg.startsWith('--') && !args[i - 1]?.startsWith('--')) ?? null
  }
}

// ── THE TIER IS NOT GUESSED HERE, DELIBERATELY ─────────────────────────────────
//
// A `suggestTier({ files, milestone })` heuristic lived here, exported and pinned by five self-test
// cases — and was never called. It read as a working feature in the tests while `main()` took the tier
// from `--tier` or left it null.
//
// It is not restored, because the omission was right: sizing is CLAUDE.md's routing table applied by
// the model, announced in one line so the user can correct it in three words. A hook guessing from a
// file count would produce a number nobody stated and nobody could challenge, which is the failure
// mode the announcement rule exists to prevent. When no `--tier` is given, `main()` says so and asks.

const emit = context => {
  // additionalContext is how a UserPromptSubmit hook speaks to the model without blocking the turn.
  process.stdout.write(
    `${JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: context } })}\n`
  )
  process.exit(0)
}

const readStdin = async () => {
  const chunks = []

  for await (const chunk of process.stdin) chunks.push(chunk)

  return Buffer.concat(chunks).toString('utf8')
}

const main = async () => {
  let payload = {}

  try {
    payload = JSON.parse(await readStdin())
  } catch {
    return 0
  }

  const prompt = payload.prompt ?? ''
  const sessionId = payload.session_id ?? process.env.CLAUDE_SESSION_ID
  const existing = activeRun(sessionId)

  if (!isBuildCommand(prompt)) {
    // Any other user message pauses a live run. Silent when there is no run, which is every ordinary
    // turn in this repo.
    if (existing && !existing.paused) update(existing.runId, { paused: true })

    return 0
  }

  const parsed = parseBuild(prompt)

  if (parsed.status) {
    if (!existing) emit('TASK LOOP: no active run.')

    emit(
      `TASK LOOP STATUS\n` +
        `  run: ${existing.runId}\n` +
        `  objective: ${existing.objective}\n` +
        `  plan: ${existing.planPath ?? '(none)'}\n` +
        `  iteration ${existing.iteration}/${existing.budget?.iterations ?? '?'}\n` +
        `  paused: ${existing.paused}\n\n` +
        `This run claims EXCLUSIVE OWNERSHIP of the working tree. Do not start editing while it is live.`
    )
  }

  if (parsed.halt) {
    if (!existing) emit('TASK LOOP: no active run to halt.')

    halt(existing.runId, 'halted by the user')
    emit(`TASK LOOP: run ${existing.runId} halted at the user's request. Tell the user it is stopped.`)
  }

  if (parsed.resume) {
    if (!existing) emit('TASK LOOP: no active run to resume. Start one with `/build <milestone>`.')

    update(existing.runId, { paused: false })
    emit(
      `TASK LOOP RESUMED — ${existing.objective}\n` +
        `Continue from phase ${existing.phaseCursor?.phase ?? '(re-read the cursor)'}. The phase may be ` +
        `PARTIALLY implemented — check what actually landed before writing anything.`
    )
  }

  if (!parsed.milestone) {
    emit('TASK LOOP: `/build <milestone> [--tier small|medium|large]` — which milestone? (see docs/MVP-SPEC.md §12)')
  }

  if (existing) {
    emit(
      `TASK LOOP: run ${existing.runId} is already active for "${existing.objective}". ` +
        `Use \`/build --status\`, \`/build --halt\`, or \`/build --resume\`. Tell the user; start nothing.`
    )
  }

  // ── THE LOOP CAN ONLY DRIVE LARGE-TIER WORK ─────────────────────────────────
  //
  // Not a limitation to work around — a consequence of what the tiers produce. The cursor advances
  // through `#### Step N.M` headings, and CLAUDE.md's routing table gives an architect (and therefore
  // a plan) to LARGE only. Small and Medium go straight to implementation, so there is no plan, no
  // phases, and nothing for the cursor to read.
  //
  // Refusing out loud beats a silent no-op: a run that appeared to start and then drove nothing would
  // look exactly like the loop working, which is the failure this whole system exists to prevent.
  const tier = parsed.tier ?? null

  if (tier === 'small' || tier === 'medium') {
    emit(
      `TASK LOOP: refusing to start a ${tier}-tier run.\n\n` +
        `The loop advances through the phases of a PLAN, and per CLAUDE.md's routing table only Large ` +
        `produces one — Small and Medium go straight to implementation with no architect. A ${tier} run ` +
        `would have nothing to drive.\n\n` +
        `Do the work directly instead: implement it, then run \`playtester\` and \`change-auditor\`. That ` +
        `is the right shape for this size and it is what the routing table already prescribes.\n\n` +
        `If this genuinely needs phasing, it is Large — say so and re-run \`/build ${parsed.milestone} --tier large\`.`
    )
  }

  const created = init({
    objective: `Build ${parsed.milestone}`,
    milestone: parsed.milestone,
    planPath: null,
    sessionId
  })

  emit(
    `TASK LOOP STARTED — run ${created.runId}\n` +
      `  objective: ${created.objective}\n` +
      `  tier: ${tier ?? 'NOT SPECIFIED'}\n\n` +
      (tier
        ? ''
        : `No --tier given. Size the task first using CLAUDE.md's routing table, state the tier in one ` +
          `line, and for Large WAIT for the user to confirm before spawning the architect.\n\n`) +
      `Then: read the milestone's row in docs/MVP-SPEC.md §12, produce or locate the plan, record it ` +
      `with \`node .claude/scripts/run-state.mjs plan <path>\`, and work phase by phase. The driver will ` +
      `re-invoke you after each turn until the plan is done or a cap is hit.\n\n` +
      `This run claims exclusive ownership of the working tree.`
  )

  return 0
}

if (process.argv[1]?.endsWith('build-trigger.mjs')) {
  if (process.argv.includes('--self-test')) {
    let failures = 0
    let ran = 0

    const check = (label, actual, expected) => {
      ran += 1
      if (JSON.stringify(actual) === JSON.stringify(expected)) return

      failures += 1
      console.log(`  FAIL  ${label} — expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
    }

    check('a plain message is not a build command', isBuildCommand('please fix the round timer'), false)
    check('/build is', isBuildCommand('/build M3'), true)
    check('leading whitespace still counts', isBuildCommand('  /build M3'), true)
    check('/buildings is not /build', isBuildCommand('/buildings are nice'), false)
    check('the milestone is parsed', parseBuild('/build M3').milestone, 'M3')
    check('a tier value is not mistaken for the milestone', parseBuild('/build --tier medium M3').milestone, 'M3')
    check('--status is recognised', parseBuild('/build --status').status, true)
    check('--status has no milestone', parseBuild('/build --status').milestone, null)
    check('tier is read', parseBuild('/build M3 --tier large').tier, 'large')
    check('no --tier leaves it null, to be asked for rather than guessed', parseBuild('/build M3').tier, null)

    console.log(failures ? `  FAIL  build-trigger: ${ran - failures}/${ran}` : `  PASS  build-trigger: ${ran}/${ran} cases`)
    process.exit(failures ? 1 : 0)
  }

  process.exit(await main())
}
