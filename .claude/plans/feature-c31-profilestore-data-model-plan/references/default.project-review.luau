--!strict
--[[
	REVIEW — default.project.json:1-26 (the whole file)
	Read for: where a vendored dependency can be mapped without landing inside `src/`.
	Written as .luau for the plan-phase reference convention; the source is JSON.
]]

--[[
	{
	  "name": "aswang-game",
	  "tree": {
	    "$className": "DataModel",
	    "ReplicatedStorage": { "Shared": { "$path": "src/shared" } },
	    "ServerScriptService": { "Server": { "$path": "src/server" } },
	    "StarterPlayer": { "StarterPlayerScripts": { "Client": { "$path": "src/client" } } }
	  }
	}
]]

-- NOTE: three mappings, and every one of them points at a directory under `src/`. That is not a
-- coincidence — it is why every gate in this repo can be scoped to `src/` and still cover all the
-- game code. A fourth mapping pointing OUTSIDE `src/` is the seam the plan uses for `vendor/`.

-- IMPORTANT: `ReplicatedStorage.Shared` maps `src/shared` WHOLESALE, which is the mechanism behind
-- CLAUDE.md's warning that everything in `src/shared/pure/` is requirable AND CALLABLE by any client.
-- ProfileMigration lands there (fixed by BUILD-PLAN.md:947) and that is harmless: it publishes a
-- table of defaults and a coercion function, and Config.luau — already replicated — gives away more.
-- Logic is not secret; inputs and seeds are, and this module takes neither.

-- IMPORTANT: ProfileStore must NOT be mapped into ReplicatedStorage. It is server infrastructure and
-- a client has no business holding a DataStore wrapper. The plan adds it as a SIBLING of `Server`
-- under ServerScriptService:
--
--     "ServerScriptService": {
--       "Server":   { "$path": "src/server" },
--       "Packages": { "$path": "vendor" }
--     }
--
-- Sibling, not child: a child would put the file under `src/server/` and back inside selene, StyLua,
-- luau-lsp and all five check scripts. The Studio path becomes
-- ServerScriptService.Packages.ProfileStore.

-- NOTE: changing this file requires RESTARTING `rojo serve`. A running server does not pick up a new
-- tree mapping, and the symptom is `WaitForChild("Packages")` hanging forever with no error — the
-- same silent-hang failure mode check:remotes exists to prevent for undeclared remotes.

-- NOTE: `npm run build` (rojo build against this file) is the only command that actually resolves the
-- project tree, which is why the plan gates the mapping step on it rather than on analyze. A missing
-- directory or a duplicate child name fails the build and nothing else.

-- QUESTION: the sourcemap is generated from this file (`npm run sourcemap`), so `vendor/` will appear
-- in sourcemap.json once mapped, and luau-lsp will be able to resolve the require. Whether it then
-- REPORTS diagnostics for a file outside its `src` argument is the open question the plan's Step 2.3
-- answers empirically with `npm run verify`, with a documented fallback ladder if it does.
