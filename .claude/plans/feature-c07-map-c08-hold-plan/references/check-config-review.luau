--!strict
-- REVIEW: .claude/scripts/check-config.mjs:1-60
--
-- Read to know exactly which literals in the new service will go red, so the plan's diffs are
-- paste-ready rather than a first draft that fails the gate.

-- ── CALIBRATION IS THE HARD PART ───────────────────────────────────────────────
-- allowed: 0, 1, 2, -1, 0.5, and anything inside a `for i = 1, n` header or an array index
-- flagged: everything else — 8 (kill range), 30 (cooldown), 1.2 (transform time), 420 (duration)
const IDIOMATIC = new Set(['0', '1', '2', '-1', '0.5', '100'])
-- IMPORTANT, and it settles three things in the plan's diffs:
--   · TaskService.weightFor returning `1` for a full contributor — ALLOWED (idiomatic). Good, because
--     the alternative would be a Config knob named "one".
--   · TaskController's `payload.YourTaskProgress * 100` — ALLOWED (100 is idiomatic).
--   · TaskProgress's `math.clamp(x, 0, 1)` — ALLOWED, and it lives under src/shared|server/pure anyway.

const GOVERNED = /(^|\/)src\/(server|client)\//
-- IMPORTANT and a real gap worth knowing: `src/shared/` is NOT governed, so pure modules under
-- src/shared/pure/ are unchecked. But src/server/pure/ IS governed — both new pure modules live there,
-- so their literals ARE scanned. TaskProgress.tick's `0` and `1` are idiomatic and pass; anything else
-- would have needed a waiver, which is a good forcing function for a module that should contain no
-- balance numbers at all.
-- NOTE this also means Step 1.4's additions to Config.luau are unpoliced in both directions: nothing
-- forces a service to READ them rather than retype 0.25. The enforcement is on the consuming files,
-- which is why Steps 2.3 and 3.3 are the two gated on `npm run check:config`.

// A numeric for-loop header is control flow, not balance.
if (/\bfor\s+\w+\s*=\s*[^,]+,/.test(text)) continue
-- NOTE: this is what lets tests/task-pool.test.luau's `for i = 1, count` pass — although tests/ is not
-- governed either, so it is moot there. It matters for `math.ceil((HOLD * 4) / TICK)` only if that
-- expression ever migrated into src/.

// A line that already reads from Config is comparing against the knob, not inventing one.
if (/\bConfig\./.test(text)) continue
-- IMPORTANT and it is why several of the plan's warn() strings are safe: a line containing
-- `Config.Tasks.PoolSize` inside an interpolated message passes wholesale, even though it also contains
-- other numbers. Useful, and worth not relying on — a warn built from a concatenation across lines
-- would split the Config reference away from a literal on another line.

-- Every one honours an inline waiver with a mandatory reason — `-- config-ok: <why>`
-- IMPORTANT: the ONE literal in this plan that needs a waiver is the tick interval:
--     task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
-- Copied verbatim from RoundService.luau:918, with the same reason. A scheduler interval is not a
-- balance knob, and putting it in Config would invite M12 to tune it as one. The waiver makes the
-- exception visible in a diff and arguable, rather than silently disabling the rule.
-- NOTE the three genuinely tunable numbers (PresenceRangeStuds, PresenceGraceSeconds,
-- HeartbeatInterval) go in Config instead, which is the distinction this check is calibrated around.
