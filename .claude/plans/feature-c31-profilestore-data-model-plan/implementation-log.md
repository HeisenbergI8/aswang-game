# C31 — implementation log

## Phase 1: The schema and the migration — provable without Roblox

### Step 1.1 — Reconcile `PlayerProfile` with §6.6
`src/shared/Types.luau` — added the missing `Purchases: { GamepassCacheUTC: number }` field with the
comment explaining it is a cache STAMP, not an entitlement (Roblox stays the authority on ownership).
The declared type and §6.6 now agree.
**Verify:** `npm run verify:fast` — analyze ok, remotes ok, secrecy ok.

### Step 1.2 — The pure migration module
`src/shared/pure/ProfileMigration.luau` (new). `CURRENT_VERSION = 1`, `template()`, `migrate(stored: any)`
returning `{ Outcome, Profile, FromVersion, Applied }`. No `script` requires; `Profile` is re-declared
locally and is structurally identical to `Types.PlayerProfile`.

`Outcome` appears only as a SCALAR field, never inside a list, per
`.claude/lessons/pure-module-unions-widen-in-lists.md`. `Applied` is plain `{ string }`.

The four outcomes: FRESH (nothing stored), CURRENT, MIGRATED, REFUSED. REFUSED is the load-bearing one —
a profile from a newer build is never reconciled, because reconciling would delete fields this build has
never heard of and the next autosave would write that deletion back.
**Verify:** `npm run analyze` — ok.

### Step 1.3 — The Lune test
`tests/profile-migration.test.luau` (new). 42 assertions over fresh, v0, current, corrupt and future.

**One deviation from the plan, and it was a real hole.** The plan's fresh-player loop read
`for _, stored in { nil, 7, "profile", true } :: { any }`. Luau drops a leading `nil` from an array
literal, so that loop runs THREE times, not four — and the case it silently skipped was `migrate(nil)`,
the first-time player, which is the most-executed path this module has. The suite passed at 36
assertions while never once calling it. Split `nil` out into its own explicit block (4 assertions) and
added NaN to the loop; 42 now, and the first-time player is genuinely covered.
**Verify:** `lune run tests/profile-migration.test.luau` — PASS, 42 assertions.

### Step 1.4 — `Config.Profile` and its invariants
`src/shared/Config.luau` — added `Profile = { StoreName, SessionStartAttempts = 3,
SessionStartRetryDelay = 4, ShutdownFlushBudget = 25 }`. The schema version deliberately does NOT live
here: `ProfileMigration` must run under Lune and cannot require `Config`, so a copy here would be a
second source of truth for the one number where disagreement means data loss.

`tests/config.test.luau` — three new invariants: the shutdown budget stays inside Roblox's ~30s
`BindToClose` window; session retries (3 x 4s = 12s) resolve before a round can start
(`Intermission 25 + StartingDelay 4 = 29s`); at least one attempt is made.
**Verify:** `lune run tests/config.test.luau` — PASS, 100 balance invariants (was 97).

## Phase 2: Vendor ProfileStore where the gates cannot see it

### Step 2.1 — Fetch and pin the source
`vendor/ProfileStore.luau` (new, 2242 lines). Fetched by resolved SHA, not by branch:
`45c9847cbcf1fc260369c50eb335aba7c35aecdd` from MadStudioRoblox/ProfileStore. Unmodified.

**The API was confirmed by reading the vendored source, not assumed.** Every call the plan is written
against exists with the shape the plan claimed: `New(store_name, template?)` (:42),
`StartSessionAsync(key, params?)` with `{ Steal, Cancel }` (:60, impl :1364),
`DataStoreState` as the four-state union (:36, :335), `OnLastSave` reporting
`"Manual" | "External" | "Shutdown"` (:117), `Reconcile`/`EndSession`/`AddUserId` (:142-148). No wrapper
adaptation was needed.
**Verify:** `test -f vendor/ProfileStore.luau` — ok.

### Step 2.2 — Rojo mapping
`default.project.json` — `Packages: { $path: "vendor" }` as a SIBLING of `Server` under
`ServerScriptService`, never under `ReplicatedStorage`, so no client can require it.
**Verify:** `npm run build` — "Built project to aswang.rbxl". (Needed `mkdir -p build` first, exactly as
the plan warned: `build/` is gitignored and Rojo will not create it.)

### Step 2.3 — Prove every gate still ignores it
**This step's deliverable is a NON-change, and it held.** `npm run verify` is fully green with the
vendored file in the tree: analyze ok, selene 0 errors/0 warnings, fmt:check ok, all five repo checks ok,
34 Lune suites ok. `analyze-baseline.json` still reads `"known": []` — no re-bless, no waiver, no StyLua
ignore, no selene exclude. Confirmed `vendor/` is tracked, not gitignored (`git check-ignore` exit 1).

**One real failure, found and fixed here.** `check:testcount` flagged
`tests/profile-migration.test.luau:194` — the PASS summary read "over fresh, v0, current, corrupt and
future", and the `0` in "v0" parses as a hardcoded tally. Reworded to "legacy" rather than waived: it
was not a fact about the input domain, so a waiver would have been the wrong instrument.
**Verify:** `npm run verify` — green.

### Step 2.4 — Provenance
`vendor/README.md` (new). Source, pinned SHA, unmodified status, the single call site, the confirmed API
table with source line numbers, the upgrade procedure, and the `.luaurc` fallback ladder. Also records
the accepted trade: `check:scope` does not see `vendor/` either, which is right for one storage library
with one call site and would not be right as a habit.
**Verify:** `test -f vendor/README.md` — ok.

## Phase 3: ProgressionService owns the profile

### Step 3.3 (written first) — the shutdown registry
`src/server/ShutdownFlush.luau` (new). `register(name, fn)` / `flushAll()`. Requires only `Config`, so
it cannot close a require cycle. Lives BESIDE `Services/` so `init.server.luau`'s loader — which walks
`SERVICE_ORDER` inside that folder — never tries to Init/Start it.

Written before its callers so nothing required a file that did not exist yet.
**Verify:** `npm run lint` — selene 0 errors, 0 warnings.

### Steps 3.1 / 3.2 — the service
`src/server/Services/ProgressionService.luau` — replaced the 20-line four-TODO stub.

Load path: `StartSessionAsync` with `Config.Profile` retries and a `Cancel` callback, then `AddUserId`,
`Reconcile()`, then the pure migration. A REFUSED migration latches `readOnly[userId]` and never touches
`Data`, so the eventual write is byte-identical to the read. `OnSessionEnd` → `Kick` handles another
server stealing the lock.

API for C32/C33/C35: `GetProfile` (returns the live table; nil is a normal answer),
`Award(player, xp, coins, reason)` (the only currency write path, NaN- and negative-guarded, saves
immediately), `BumpStat` (no save — ProfileStore autosaves), `FlushAll`.

A failed load is deliberately not fatal: they play, nothing saves, the warn says so. Kicking on a
DataStore outage turns a Roblox incident into an empty server.
**Verify:** `npm run check:config` ok; `npm run analyze` ok.

### Step 3.4 — `BindToClose`
`RoundService.luau` — added the `ShutdownFlush` require (a leaf, so no cycle) and replaced
`onServerClosing`'s TODO with `ShutdownFlush.flushAll()`. `ProgressionService.Start` registers itself
first, before any player connection, so a server dying during startup still flushes what it loaded.
RoundService never names ProgressionService, so the dependency edge points the way every other one does.
**Verify:** `npm run verify` — green (analyze, selene 0/0, fmt, five checks, 34 Lune suites, 28 harness
suites).

### The one thing that did not go to plan: the analyzer and `vendor/`

Step 2.3 passed `npm run verify` green with the vendored file in the tree — but that green was
**premature, not wrong**: nothing required ProfileStore yet, so the analyzer never loaded it. The moment
Step 3.1's `require` landed, `luau-lsp` pulled it in transitively and reported ~20 diagnostics against a
file this repo may not edit. The plan anticipated exactly this and wrote a three-rung ladder; both of
its rungs were tried and neither was kept:

1. **`vendor/.luaurc` = nonstrict** (the plan's rung 2) — 20+ down to 18, not cleared. ProfileStore's own
   annotations are what luau-lsp disagrees with, and nonstrict does not stop it checking them. Deleted
   afterwards: with the fix below in place it changed nothing measurable, and a file that does nothing
   reads as load-bearing.
2. **Re-blessing `analyze-baseline.json`** (rung 3) — rejected rather than escalated. The baseline is
   keyed on file+kind+message, so 18 third-party entries would churn on every dependency upgrade, and
   `--update` refuses to run under an agent — a future ProfileStore bump would halt an unattended build
   on a file nobody here owns.

**What was done instead:** `check-analyze.mjs` now passes `--ignore=**/vendor/**` to `luau-lsp analyze`.
The file is still USED for type resolution (it must be) but is not GRADED. One line, visible in a diff,
and `analyze-baseline.json` stays `"known": []`.

**Proven in both directions, because a weakened gate looks exactly like a clean one.** A deliberate type
error written into `src/shared/pure/` still fails `npm run analyze` with `--ignore` in place; removing
the probe returns it to green. The gate over `src/` is unchanged in strength. `npm run check:guards`
passes all 28 suites after the edit.

This is a harness-script change, so per CLAUDE.md it earns `check:guards` (done) plus a `change-auditor`
pass rather than `exploit-auditor`.

## Phase 4: Make persistence observable, then observe it

### Step 4.1 — `DataStoreState` legible
`ProgressionService.Start` warns loudly when `ProfileStore.DataStoreState ~= "Access"`, naming the exact
Studio setting. A `warn`, not an `error`: a local session without API access is a legitimate way to test
everything except persistence. Wrapped in `task.spawn` because the state may still read `"NotReady"` on
the bootstrap thread and a false alarm every launch is how a warning gets ignored.
**Verify:** `npm run verify:fast` — ok.

### Step 4.2 — One flat award at ENDING
Subscribes to `RoundService.PhaseChanged`; on ENDING, bumps `Stats.Rounds` and awards
`Config.Economy.XPPerRound` / `CoinsPerRound` to every player not LOBBY or SPECTATOR (a GHOST played the
round; a SPECTATOR joined after the draw). Reads `GetPlayerState` and never the role — a role-conditional
award would make the XP number itself a derived hint. C32 replaces the policy, not the plumbing.
**Verify:** `npm run verify` — green.

### Steps 4.3 / 4.4 — BLOCKED ON A HUMAN, and not attempted

**Step 4.3 is two Studio UI actions no agent can drive** — publish the place, and Game Settings >
Security > Enable Studio Access to API Services. It has no `**Verify:**` line by design and
`verify-plan.mjs` reports it `unverifiable`, which is the accurate answer.

**Step 4.4's playtest was deliberately NOT launched, on a precondition checked this turn.**
`search_game_tree` over `ServerScriptService` in the running Server datamodel returns only
`Server.Services` and `Server.pure`: there is **no `Packages` child and no `ShutdownFlush`**. The running
DataModel predates both this phase's `default.project.json` change and the new leaf module, so
`ProgressionService`'s `WaitForChild("Packages")` would hang forever — no error, no output, exactly the
silent-hang failure mode `check:remotes` exists to prevent for remotes. A playtester launched into that
would have spent 5–8 minutes and 150–250k tokens rediscovering a hang already visible from the tree.

`rojo serve` (pid 78052) has been running since before `default.project.json` gained the `Packages`
mapping, and a running Rojo server does not pick up a new tree mapping — the plan's Phase 2 issues list
predicted this exact symptom. Studio is also currently in Play mode.

**What a human does to unblock, in order:** stop Play; restart `rojo serve`; confirm
`ServerScriptService.Packages.ProfileStore` exists in the tree; publish the place; enable API services;
restart Studio if the state still reads `NoAccess`. Then set `Config.Round.Intermission/Duration/
EndScreen` to `8/20/6` plus `Debug.SoloTesting` and `VerboseLogging` before briefing the playtester, and
revert all five afterwards (`guard-commit.mjs` runs `check:debug` and will refuse the commit otherwise).

**Plan graders at handoff:** 14 passed, 1 failed (4.4's artifact, blocked above), 1 unverifiable (4.3).

## Post-review: the `--ignore` glob was wrong, and the self-test that would have caught it

`change-auditor` found a real defect in the Phase 3 fix and **proved it rather than asserting it**: the
glob was written `**/vendor/**`, which matches a `vendor` path segment ANYWHERE — including inside our
own tree. It planted a type error at `src/shared/vendor/__probe.luau` and `npm run analyze` reported
`ok`. I reproduced that before acting on it.

That is the exact failure `check-analyze.mjs`'s own header warns about: a gate reporting confident green
over a broken tree. Nothing under `src/` matches today, so it was latent — but the blast radius is total
silence, not a warning.

**Fixed:** the glob is now anchored to `vendor/**`. Both directions re-measured by hand: a type error at
`src/shared/vendor/` is now REPORTED, and `vendor/ProfileStore.luau`'s diagnostics stay suppressed.

**Also corrected:** the comment said "~20 diagnostics". The auditor measured 89 with the flag removed.
The comment now says 89.

**The gap this really exposed** was in the test, not the flag. `check-analyze`'s eleven existing cases
are pure functions over a sample string — `parse`, `fingerprint`, `grade` — and *none of them can see a
glob*, so all eleven passed over the broken pattern. Added three integration cases to
`check-analyze.mjs --self-test` that invoke the real `luau-lsp` over real probe files:

  · ALLOW — a diagnostic under `vendor/` is suppressed
  · DENY  — a diagnostic under `src/` is reported
  · DENY  — a diagnostic under `src/**/vendor/**` is reported (the case that regressed)

Cleanup is in a `finally`, because a probe left behind under `src/` poisons every later analyze run —
which happened once during this session and turned the Stop gate red. The cases SKIP rather than fail
when the toolchain is absent.

**`check-analyze`: 11/11 → 14/14 cases. `npm run check:guards`: 28 suites ok. `npm run verify`: green.**

### Auditor scores at handoff

- `change-auditor` (harness change): **90/100**. One Medium finding, fixed above; one Low (the stale
  diagnostic count), fixed above.
- `auditor` (plan fidelity): **77/100**, with **Behavioural evidence 5/20** — its own words: "no Studio
  session, no DataStore write, no round observed". All 16 steps traced; no undocumented deviations. It
  independently reproduced the leading-`nil` bug and confirmed no other test file carries the pattern.

Both scores measure the auditors' evidence, not the code. The 5/20 is the honest number for this chunk:
**nothing here has been proven to persist anything.** That is Step 4.4's job and it has not run.

## Post-review: exploit-auditor — 89/100, two real defects, both reproduced at runtime

It confirmed the secrecy question in the direction that matters: **no remote, no `OnServerEvent`, no
attribute, no tag, no `leaderstats`, no `Instance`.** `Stats.AswangRounds`/`AswangWins` are declared in
three places and have **zero writers and zero readers**; `src/client/` has no reference to `Profile` or
`Progression` at all. It also proved the award loop cannot leak by TIMING — `Profile:Save()` is
`task.spawn` (`vendor/ProfileStore.luau:1188`), so the loop completes in one frame for all eight players
and cannot stagger per role.

Two defects were real, and it reproduced both under Lune rather than asserting them.

### FIXED (High) — the read-only latch did not hold

`profile:Reconcile()` ran **two lines before** the REFUSED check. `Reconcile` walks the v1 template and
writes every missing key into `Data`, recursing into nested tables — so a v2 profile passing through a
v1 server was stamped with v1 defaults *before* anything decided it must not be touched, and ProfileStore
autosaves regardless of what we latch afterwards. The auditor replayed `ReconcileTable` over a v99
profile and watched six v1 keys get injected.

That defeated a claim the code made **three times** ("byte-identical to what it read") in
`ProgressionService.luau` twice and `ProfileMigration.luau` once. A comment asserting an invariant is
exactly what the `green-after-each-patch-hides-a-loop` lesson says to distrust.

The damage is additive, so nothing breaks on the day — it lands on whoever writes v2, because in-place
migrations are keyed on a field being ABSENT, and a re-materialised `Coins = 0` makes the v2 server skip
its own migration and read that zero as authoritative.

**Fix:** `Reconcile()` moved inside the non-REFUSED branch, after the version is classified.

### FIXED (Medium) — `math.huge` walked through every guard

`x ~= x or x < 0` catches NaN and negatives and misses infinity: `math.floor(math.huge)` is `inf` rather
than an error, `inf ~= inf` is false, `inf < 0` is false. The auditor measured a stored `XP = math.huge`
surviving `migrate` intact and classified `CURRENT`.

The comment claimed the guard prevented "a table that then fails every subsequent DataStore write for
that player, silently, forever" — and `inf` produces *exactly that*, because JSON cannot encode it. An
overflowing XP multiplier chain reaches ~1e308 without a single division by zero.

**Fix:** one finite predicate, `x >= 0 and x < math.huge`, in `ProfileMigration.num`, `Award` and
`BumpStat`. It rejects NaN too — NaN fails every comparison — so the two guards collapse into one.
**Pinned with 7 new assertions** (`+inf`, `-inf`, nested, timestamp, and a finite-survival loop);
the suite is 42 → 49.

### FIXED (Low) — `ShutdownFlush`'s comment described a yield that does not happen

`Profile:EndSession()` does **not** yield; it is `task.spawn(SaveProfileAsync, ...)`
(`vendor:1090`). So `flushAll` returns in microseconds, `ShutdownFlushBudget` is never approached, and
"flush complete" prints while writes are in flight. **No data is lost** — ProfileStore registers its own
`BindToClose` (`vendor:2208-2239`) that yields until its save jobs drain, and Roblox waits for both
bindings. The auditor also checked the double-release race and found it safe.

But that is a guarantee for PROFILES from a vendored file, not a property of this registry — and the
comment told the next author the opposite. **Fix:** the header now says what actually holds the process
open, and warns that a handler which spawns and returns will not be waited for by anything.

### FIXED (Low) — the backfill guard could not see an in-flight start

`sessions[userId]` is not written until `StartSessionAsync` RETURNS, so during a slow start (contested
lock, or 3 x 4s of retries) the guard read `nil`. Not reachable today — there is no yield between the
connect and the backfill loop — but the failure mode is a lock held with **no entry in `sessions`**,
which `PlayerRemoving` cannot release, making the next server that player joins wait it out.

**Fix:** an `inFlight` set entered before `StartSessionAsync` and cleared on every exit path, checked
inside `startSession` itself rather than at one call site. Safety by guard, not by statement order.

### FIXED (Low) — `GetProfile` was a third write path

It returns the live table and consults neither the latch nor the finite guard. `local p =
GetProfile(player); p.Coins += price` is the natural line for C34 and it silently writes into a
read-only profile. **Fix:** the comment now says reads only and names `Award`/`BumpStat` as the write
paths, plus a new `IsReadOnly(player)` so C33/C34/C35 can refuse a purchase rather than take a payment
that will never be saved.

### Carried forward, NOT fixed here

**`ProfileUpdated` is declared and unwired** (`Remotes.luau:40`). `check-secrecy.mjs:87-93` enforces
`PAYLOAD_FIELDS` only on the two allowlisted remotes, so **C33 firing `ProfileUpdated` with a whole
profile would pass `verify` green** while shipping `AswangRounds` to a client. Not a C31 defect. It
belongs in C33's brief, and it is the single most valuable thing this audit found for the future.

**`npm run verify` green after all five fixes.** 34 Lune suites, profile-migration at 49 assertions.
