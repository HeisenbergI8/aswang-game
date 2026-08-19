# vendor/

Third-party Luau, **outside `src/` on purpose**. Nothing in here is ours and nothing in here is edited.

## Why it is not in `src/`

Every gate in this repo is scoped to `src/` — `selene src`, `stylua src tests`, `luau-lsp … src`, and
`listLuau()`'s default root for the five `check:*` scripts. Vendoring here therefore needs no StyLua
ignore, no selene exclude, no waiver comments, and **no entry in `analyze-baseline.json`**. That last
one matters more than it looks: `check-analyze.mjs --update` refuses to run under an agent, so a
dependency that forced the baseline open would halt an unattended build.

Rojo maps this directory to `ServerScriptService.Packages` (see `default.project.json`). It is
server-only — never `ReplicatedStorage`, so no client can require it.

The trade-off worth naming: `check:scope` never sees this directory either. That is correct for one
storage library with a single call site — flagging a third-party library's vocabulary would train
everyone to ignore the check — but it would not be correct as a habit of vendoring gameplay code.

## ProfileStore

| | |
| --- | --- |
| Source | https://github.com/MadStudioRoblox/ProfileStore |
| Commit | `45c9847cbcf1fc260369c50eb335aba7c35aecdd` |
| Vendored | 2026-08-19, chunk C31 |
| Modified | **no** — byte-identical to upstream, 2242 lines |
| Used by | `src/server/Services/ProgressionService.luau`, and nothing else |

Required by `docs/MVP-SPEC.md` §6.1: "**ProfileStore** (or similar session-locked DataStore wrapper) —
prevents data loss and duplication bugs. Do **not** hand-roll DataStore access."

### The API this repo is written against

Confirmed by reading the vendored source at the pinned SHA, not assumed:

| Call | Shape | Source |
| --- | --- | --- |
| `ProfileStore.New(store_name, template?)` | returns a store | line 42 |
| `store:StartSessionAsync(key, params?)` | `params = { Steal: boolean?, Cancel: () -> boolean }` | line 60, impl 1364 |
| `ProfileStore.DataStoreState` | `"NotReady" \| "NoInternet" \| "NoAccess" \| "Access"` | line 36 |
| `profile.Data` · `:IsActive()` · `:Reconcile()` · `:Save()` · `:EndSession()` | session lifecycle | lines 142–145 |
| `profile.OnLastSave` | reason is `"Manual" \| "External" \| "Shutdown"` | line 117 |
| `profile:AddUserId(id)` | GDPR association | line 148 |

`ProfileStore.SetConstant` is deliberately **not** used. It would let us tune the internal autosave
period, but its `ConstantName` values are internal to this file and would have to be re-verified on
every upgrade. This repo tunes only its own knobs, in `Config.Profile`.

### Upgrading

Re-fetch by a new SHA, update the row above, and run `npm run verify` plus a rejoin playtest. Only
`ProgressionService` names a ProfileStore symbol, so an API change has exactly one call site to fix.

### How the analyzer is kept off this directory

`check-analyze.mjs` passes `--ignore=**/vendor/**` to `luau-lsp analyze`. The file is still USED for
type resolution — it has to be, `ProgressionService` requires it — but its diagnostics are not
reported.

This was measured, not assumed. `luau-lsp` is invoked over `src` only, so vendoring alone produced no
diagnostics at all; the ~20 errors appeared the moment `ProgressionService` first required the module
and pulled it in transitively. Two rungs were tried before the flag:

1. **`vendor/.luaurc` with `{ "languageMode": "nonstrict" }`** — took 20+ diagnostics down to 18 and
   did not clear them. ProfileStore's own type annotations are what luau-lsp disagrees with, and
   nonstrict does not stop it checking them. **Not kept**, because with `--ignore` in place it changed
   nothing measurable, and a file that does nothing reads as load-bearing to the next person.
2. **`analyze-baseline.json`** — rejected, not merely unused. The baseline is keyed on
   file+kind+message, so 18 third-party entries would churn on every dependency upgrade, and
   `check-analyze.mjs --update` refuses to run under an agent — a ProfileStore bump would then halt an
   unattended build on a file nobody here may edit. The baseline is still `"known": []`.

The gate over `src/` is unchanged in strength, and that was verified in both directions: a deliberate
type error in `src/shared/pure/` still fails `npm run analyze`, while `vendor/`'s do not.
