--!strict
--[[
	REVIEW — package.json:14-17, 19-33 (the scripts block)
	Read for: the remaining two tool scopes, and which commands a plan Verify line may use.
	Written as .luau for the plan-phase reference convention; the source is JSON.
]]

--	"lint":      "selene src",
--	"fmt":       "stylua src tests",
--	"fmt:check": "stylua --check src tests",
-- IMPORTANT: pillars three and four of the vendoring decision. selene never leaves `src`, and StyLua
-- covers `src` and `tests` only. So `vendor/ProfileStore.luau` needs no `.styluaignore` entry and no
-- selene `exclude` — the configs stay untouched, which means there is no new place for a future
-- exclusion to hide. (`selene.toml` is one line, `std = "roblox"`; `.styluaignore` is empty. Both
-- confirmed.)
-- NOTE: `fmt` covers `tests`, so tests/profile-migration.test.luau is formatted like the rest. Several
-- assertion lines in the plan's suite run past stylua.toml's `column_width = 100`; run `npm run fmt`
-- before `fmt:check` sees them.

--	"analyze":   "node .claude/scripts/check-analyze.mjs",
--	"test:unit": "node .claude/scripts/run-luau-tests.mjs",
--	"verify:fast": analyze + check:remotes + check:secrecy + toolchain
--	"verify":      analyze + lint + fmt:check + the five checks + check:debug + check:testcount
--	               + test:unit + harness self-tests
-- NOTE: `verify` does NOT include `build`. That is why the plan gates the Rojo mapping step on
-- `npm run build` specifically — nothing else in the gate resolves the project file, so a typo there
-- would otherwise survive a fully green tree until someone opened Studio.
-- NOTE: `verify` DOES include check:testcount and the harness self-tests, so Step 1.3's PASS line and
-- Step 1.4's added invariants are both covered by the Phase 3 and Phase 4 `npm run verify` steps as
-- well as by their own Lune runs.

--	"verify:plan": "node .claude/scripts/verify-plan.mjs",
--	"plan:phase":  "node .claude/scripts/plan-phase.mjs",
--	"goal":        "node .claude/scripts/goal-check.mjs",
-- IMPORTANT: `plan:phase` resolves a phase's reference reviews by matching each step's `**File:**`
-- basename against `[fileName]-review.luau` in this directory. That is why every step in the plan
-- carries a File line — including Step 4.3, whose "file" is the Studio place — and why these review
-- files are named after their sources rather than after their topics.
-- NOTE: `goal` will not report DONE until verification.md cites a file that exists in `artifacts/`.
-- The directory is created empty by this plan; Step 4.4's screenshot is what fills it.
