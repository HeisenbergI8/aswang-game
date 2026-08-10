--!strict
--[[
	REVIEW — default.project.json (and package.json, and .claude/scripts/check-analyze.mjs)

	Read to answer the plan's central design question with a fact rather than a belief.
]]

--[[
	IMPORTANT — the mapping. THIS is the fact §1.1 turns on:

		"ReplicatedStorage": { "Shared": { "$path": "src/shared" } },
		"ServerScriptService": { "Server": { "$path": "src/server" } },
		"StarterPlayer": { "StarterPlayerScripts": { "Client": { "$path": "src/client" } } }

	`src/shared` is mapped WHOLESALE — there is no exclusion, no glob, no `$ignoreUnknownInstances`
	carve-out. So every file under `src/shared/pure/` lands in ReplicatedStorage and replicates to every
	client, which can `require()` and CALL it.

	`src/server` lands in ServerScriptService, which does not replicate. A new `src/server/pure/`
	directory therefore becomes `ServerScriptService.Server.pure` and is invisible to clients.

	QUESTION — the require path. `src/server/init.server.luau` makes `Server` a Script with `Services`
	and `pure` as sibling children, so `script.Parent.Parent.pure.RoleDraw` from a service SHOULD
	resolve. Not confirmed in a running place; recorded as Follow Up #2 and as the first thing to check
	at first sync. RoundService already proves the nested-folder form works on the shared side
	(`require(Shared.pure.RoundTransitions)`).
]]

--[[
	NOTE — check-analyze.mjs regenerates a stale sourcemap before running:

		import { DEFS_PATH, SOURCEMAP, regenerateSourcemap, sourcemapStale } from './check-toolchain.mjs'
		if (sourcemapStale()) regenerateSourcemap()

	So adding `src/server/pure/` needs no manual `npm run sourcemap`; `npm run analyze` handles it. This
	is why Step 4.1's Verify line is `npm run analyze` and not a sourcemap command.

	NOTE also the analyze BASELINE: diagnostics are graded against analyze-baseline.json, fingerprinted
	WITHOUT line and column. A genuinely new error fails; an existing one moving down a file does not.
	`--update` refuses to run under an agent, so no step in this plan can re-bless the baseline.
]]

--[[
	NOTE — package.json, the commands every Verify line in this plan uses:

		verify      = analyze + lint + fmt:check + 5 checks + test:unit + harness   (~15s)
		verify:fast = analyze + check:remotes + check:secrecy + toolchain           (~3s)
		test:unit   = node .claude/scripts/run-luau-tests.mjs  -> every tests/*.test.luau under Lune

	run-luau-tests.mjs discovers `tests/*.test.luau` by suffix and fails on the first non-zero exit, so
	the four new test files are picked up with no registration step.
]]

--[[
	IMPORTANT — the golden rule this plan obeys by never touching Studio:

		"Files on disk are the source of truth. Studio is the renderer."

	and: "The MAP is not in Git." Which is why the rig type (R6 vs R15) and whether a SPECTATOR spawns
	are both questions this plan RAISES rather than answers — neither is knowable from the repository.
]]
