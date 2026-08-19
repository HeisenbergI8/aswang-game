--!strict
--[[
	REVIEW — .claude/scripts/check-analyze.mjs:26-28, 86-111, 168-172
	Read for: what the typecheck actually looks at, and who is allowed to widen it.
	Written as .luau for the plan-phase reference convention; the source is JavaScript.
]]

--------------------------------------------------------------------------------
-- :95-105 — the invocation
--------------------------------------------------------------------------------

--[[
	const args = [
	  'analyze',
	  `--sourcemap=${SOURCEMAP}`,
	  '--base-luaurc=.luaurc',
	  `--definitions=${DEFS_PATH}`,
	  '--no-strict-dm-types',
	  'src'                                   // <- the only path argument
	]
]]
-- IMPORTANT: `src` and nothing else. This is one of the four measurements the plan's vendoring
-- decision rests on: third-party Luau at `vendor/ProfileStore.luau` is not a file the analyzer is
-- asked about. (The other three: `selene src` and `stylua src tests` in package.json, and
-- listLuau()'s default root of `src` in lib/luau-source.mjs:21.)
-- NOTE: `--base-luaurc=.luaurc` means a nested `vendor/.luaurc` would apply to that directory — the
-- documented fallback in the plan's Step 2.3 if diagnostics ever do surface from there.

--------------------------------------------------------------------------------
-- :87 — the sourcemap regenerates itself
--------------------------------------------------------------------------------

--	if (sourcemapStale()) regenerateSourcemap()
-- NOTE: so `npm run analyze` picks up the new `Packages` mapping without a separate
-- `npm run sourcemap`. Useful, but do not rely on it while `rojo serve` is running against an old
-- project file — see the default.project.json review.

--------------------------------------------------------------------------------
-- :26-28 and :168-172 — the constraint that shapes the whole plan
--------------------------------------------------------------------------------

--	`analyze-baseline.json` sits at the repository ROOT, tracked, deliberately. [...] `--update`
--	refuses to run when CLAUDE_AGENT_TYPE is set: re-blessing is a human act.
-- IMPORTANT: AN AGENT IMPLEMENTING THIS PLAN CANNOT WIDEN THE BASELINE. Any design that needed it
-- widened would halt the run and wait for a human. That is the strongest single argument for
-- vendoring outside `src/` — it is not a tidiness preference, it is what keeps C31 implementable
-- unattended. The baseline currently reads `"known": []`, and Step 2.3's deliverable is that it
-- still does.

--------------------------------------------------------------------------------
-- :39-44 — why the baseline is keyed the way it is
--------------------------------------------------------------------------------

--	The identity of a diagnostic [...] Line and column are DELIBERATELY EXCLUDED
-- NOTE: relevant only if the fallback ladder ever reaches step 3. A blessed diagnostic survives the
-- file moving, so a vendored library's error would stay blessed across an upgrade that shifted it —
-- which is another reason to prefer `vendor/.luaurc` over blessing.
