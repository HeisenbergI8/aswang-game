--!strict
--[[
	REVIEW — .claude/scripts/check-config.mjs:28-41, 47-63
	Read for: exactly which files must have no magic numbers, and which of C31's numbers are exempt.
	Written as .luau for the plan-phase reference convention; the source is JavaScript.
]]

--------------------------------------------------------------------------------
-- :38-41 — the scope, and the second pillar of the vendoring decision
--------------------------------------------------------------------------------

--	// Directories whose numbers are gameplay knobs. Types and Enums hold no tunables; Config IS the file.
--	const GOVERNED = /(^|\/)src\/(server|client)\//
-- IMPORTANT: `src/server/` and `src/client/` ONLY. Three consequences for this plan, all load-bearing:
--   1. `vendor/ProfileStore.luau` is not governed — no waivers needed for a third-party library that
--      is full of timeouts and retry counts.
--   2. `src/shared/pure/ProfileMigration.luau` is not governed either, so MAX_ID_LENGTH = 64 and
--      MAX_OWNED_COSMETICS = 256 need no `-- config-ok:` comment. They are bounds on corrupt input,
--      not balance knobs, and the check agrees by construction.
--   3. `src/server/Services/ProgressionService.luau` and `src/server/ShutdownFlush.luau` ARE governed.
--      Every retry count, delay and budget must be read from Config.Profile. That is what makes
--      `npm run check:config` a real gate on the plan's Step 3.1 rather than a formality.

--------------------------------------------------------------------------------
-- :31-37 — the calibration, quoted because it decides what needs a Config entry
--------------------------------------------------------------------------------

--	//   allowed: 0, 1, 2, -1, 0.5, and anything inside a `for i = 1, n` header or an array index
--	//   flagged: everything else — 8 (kill range), 30 (cooldown), 1.2 (transform time), 420 (duration)
-- NOTE: IDIOMATIC is {0, 1, 2, -1, 0.5, 100}. So `SchemaVersion = 1`, `Level = 1` and every `= 0`
-- default in the profile template pass on their own merits even where the file IS governed. The three
-- numbers C31 actually has to name — SessionStartAttempts 3, SessionStartRetryDelay 4,
-- ShutdownFlushBudget 25 — are all above the threshold and all belong in Config anyway.

--------------------------------------------------------------------------------
-- :55-63 — two escape hatches the plan relies on
--------------------------------------------------------------------------------

--	// A numeric for-loop header is control flow, not balance.
--	if (/\bfor\s+\w+\s*=\s*[^,]+,/.test(text)) continue
--	// A line that already reads from Config is comparing against the knob, not inventing one.
--	if (/\bConfig\./.test(text)) continue
-- IMPORTANT: `for attempt = 1, Config.Profile.SessionStartAttempts do` in the plan's Step 3.1 passes
-- on BOTH rules, so it needs no waiver. Worth knowing before someone "fixes" it into a while loop.
-- NOTE: the second rule is line-based, not expression-based. A line mentioning `Config.` anywhere is
-- skipped entirely — so a genuine magic number hidden on the same line as a Config read would slip
-- through. Not a problem this plan creates, but a reason not to write dense arithmetic lines.

-- NOTE: every check here honours `-- config-ok: <reason>` with a MANDATORY reason (hasWaiver from
-- lib/luau-source.mjs). RoundService:1344's `task.wait(0.25) -- config-ok: scheduler tick, not a
-- balance knob` is the model. This plan needs no waiver anywhere; if implementation reaches for one,
-- that is a signal the number belongs in Config.Profile after all.
