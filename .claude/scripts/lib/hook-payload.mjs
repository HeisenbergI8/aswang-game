// Shared readers for the hook payload shape.
//
// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────────
//
// `commandFailed` lived twice — as `failed()` in record-activity.mjs and `didFail()` in
// loop-breaker.mjs, byte-identical apart from the name. Both encode the same delicate rule, and both
// are load-bearing in opposite directions: record-activity's copy decides whether a run counts as
// evidence for `claim-check`, and loop-breaker's decides whether to escalate. A drift between them
// would produce a ledger that disagrees with the breaker about what happened, with nothing to notice.
//
// Neither copy had a test. One copy, tested in both directions, is the whole point of moving it here.

// ── POSITIVE EVIDENCE OF FAILURE ONLY ──────────────────────────────────────────
//
// The payload's shape is not guaranteed across builds, so this probes several candidate fields and
// DEFAULTS TO "passed" when it cannot tell. That direction is deliberate in both callers: a breaker
// that fires spuriously gets switched off, and a ledger that invents failures blocks honest turns.
export const commandFailed = payload => {
  if (payload?.hook_event_name === 'PostToolUseFailure') return true

  const response = payload?.tool_response

  if (!response || typeof response !== 'object') return false

  for (const field of ['exit_code', 'exitCode', 'code', 'status', 'returnCode']) {
    if (typeof response[field] === 'number') return response[field] !== 0
  }

  for (const field of ['is_error', 'isError', 'error', 'failed']) {
    if (typeof response[field] === 'boolean') return response[field]
  }

  return false
}

if (process.argv[1]?.endsWith('hook-payload.mjs') && process.argv.includes('--self-test')) {
  let failures = 0
  let ran = 0

  const check = (label, actual, expected) => {
    ran += 1
    if (actual === expected) return

    failures += 1
    console.log(`  FAIL  ${label} — expected ${expected}, got ${actual}`)
  }

  // FAILED — the shapes that must escalate.
  check('a PostToolUseFailure event', commandFailed({ hook_event_name: 'PostToolUseFailure' }), true)
  check('a non-zero exit_code', commandFailed({ tool_response: { exit_code: 1 } }), true)
  check('a non-zero camelCase exitCode', commandFailed({ tool_response: { exitCode: 2 } }), true)
  check('an is_error boolean', commandFailed({ tool_response: { is_error: true } }), true)

  // PASSED — and this is the half that must not drift, because a false failure blocks honest work.
  check('a zero exit_code', commandFailed({ tool_response: { exit_code: 0 } }), false)
  check('is_error false', commandFailed({ tool_response: { is_error: false } }), false)
  check('an unrecognised response shape defaults to passed', commandFailed({ tool_response: { stdout: 'ok' } }), false)
  check('a string response is not an object', commandFailed({ tool_response: 'ok' }), false)
  check('no tool_response at all', commandFailed({}), false)
  check('no payload at all', commandFailed(), false)
  check('an ordinary PostToolUse with no signal', commandFailed({ hook_event_name: 'PostToolUse' }), false)

  // PRECEDENCE — a numeric field wins over a later boolean, so a zero exit is not overridden by a
  // stray `error` key. Reversing this would mark every successful command as failed.
  check('exit_code 0 wins over a truthy error flag', commandFailed({ tool_response: { exit_code: 0, error: true } }), false)

  console.log(failures ? `  FAIL  hook-payload: ${ran - failures}/${ran}` : `  PASS  hook-payload: ${ran}/${ran} cases`)
  process.exit(failures ? 1 : 0)
}
