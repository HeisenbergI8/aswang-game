# Plan: C31 — ProfileStore and the Data Model

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M9 (chunk C31, `docs/BUILD-PLAN.md:658-673`; deps C19)
- **Description:** Give the game persistent per-player data. Vendor ProfileStore as the session-locked
  DataStore wrapper (§6.1 forbids hand-rolling one), define the `Profile` table from §6.6 with
  `SchemaVersion = 1` and a written migration path, and make `ProgressionService` own the profile —
  session on join, save on meaningful change, end on leave, flush on `BindToClose`.
- **Date:** 2026-08-19
- **What the client is told:** **nothing new.** C31 adds no remote, no attribute, no tag, no
  `leaderstats`. `Remotes.luau` is untouched, so `check:remotes` and `check:ratelimit` stay vacuous over
  this chunk by construction. The profile is read and written on the server only; C33/C34 own showing
  any of it to a player, and that will be a deliberate new remote reviewed on its own.

### 1.1 The three decisions this plan settles

Everything below depends on these three, and each is repeated inside the phase that acts on it, because
phases are read one at a time through `npm run plan:phase`.

**(a) ProfileStore is VENDORED OUTSIDE `src/`, at `vendor/ProfileStore.luau`, mapped into Studio by
Rojo as `ServerScriptService.Packages`.**

This is the decision the whole chunk hinges on, and it is settled by reading the gates rather than by
taste. Every check in this repo is scoped to `src/`, and measurably so:

| Gate | Scope | Sees `vendor/`? |
| --- | --- | --- |
| `npm run analyze` | `luau-lsp analyze … src` (`check-analyze.mjs:104`) | no |
| `npm run lint` | `selene src` (`package.json`) | no |
| `npm run fmt:check` | `stylua --check src tests` (`package.json`) | no |
| `check:config` | `GOVERNED = /(^\|\/)src\/(server\|client)\//` (`check-config.mjs:41`) | no |
| `check:scope` · `check:secrecy` · `check:ratelimit` | `listLuau()`, default root `src` (`lib/luau-source.mjs:21`) | no |

So third-party source under `vendor/` needs **no StyLua ignore, no selene exclude, no waiver comments,
and — critically — no change to `analyze-baseline.json`.** That last one is not a convenience, it is a
hard constraint: `check-analyze.mjs --update` **refuses to run when `CLAUDE_AGENT_TYPE` is set**, so an
agent implementing this plan physically cannot re-bless the baseline. Any design that needed the
baseline widened would be a design that halts the run and waits for a human. Keeping ProfileStore out
of `src/` is what makes the chunk implementable unattended.

The rejected alternatives, briefly: vendoring to `src/server/Vendor/` puts ~1,500 lines of someone
else's Luau inside all seven gates and buys nothing; and **writing our own session-locked wrapper is
refused outright** — §6.1 names ProfileStore and says "do **not** hand-roll DataStore access", and
`docs/BUILD-PLAN.md:663` prices the alternative at a week. Session locking is the part that is easy to
get wrong and impossible to notice: the symptom is duplicated or rolled-back player data on a
server-hop, weeks later, with no error.

**(b) The migration seam is `src/shared/pure/ProfileMigration.luau`, pure and Lune-runnable.**

Fixed by `docs/BUILD-PLAN.md:947` — the module/test pairing is registry-level and not open. It therefore
**must not** `require(script.Parent.Types)`: Lune has no `script`. Any literal union it needs is
re-declared locally (Luau unions are structural, so the local type and `Types.X` are the same type).
Per `.claude/lessons/pure-module-unions-widen-in-lists.md`, a literal union survives `require` as a
scalar and **not inside a list** — so this module's outcome union is a scalar field that callers compare
against a string literal with `==`, and is never cast and never returned inside an array. The impure
half stays in `ProgressionService`, which does the DataStore-shaped work and calls the pure function
for every decision about shape.

**(c) The shutdown flush goes through a leaf registry, `src/server/ShutdownFlush.luau`.**

`RoundService.luau:1339` already owns the single `game:BindToClose(onServerClosing)`, and its comment at
`:1199-1207` says why there is exactly one. C31 must put the profile flush on that path **without
`RoundService` requiring `ProgressionService`** — because the established dependency direction in this
repo is *everything → RoundService* (seven services require it and subscribe to `PhaseChanged`;
RoundService requires only `RoleService`). ProgressionService will subscribe to `PhaseChanged` too, so
a `RoundService → ProgressionService` require would close a cycle, and a require cycle here errors at
load, is swallowed into one `warn` by `init.server.luau:74-78`, and leaves the server sitting in IDLE
forever looking exactly like "nobody has joined yet".

A leaf module both sides require breaks that: `ShutdownFlush` requires nothing, so it cannot participate
in a cycle. **It is a plain function registry, not a `BindableEvent`, and that is load-bearing:** a
`BindableEvent:Fire()` resumes each handler on its own thread, so `Fire` returns as soon as a handler
yields — and `Profile:EndSession()` yields on a DataStore write. Firing a BindableEvent from
`BindToClose` would return immediately and let the server die mid-write, which is precisely the data
loss this chunk exists to prevent. `flushAll()` calls its callbacks sequentially on the `BindToClose`
thread, where yielding is what Roblox waits for.

### 1.2 What needs a human, and what an agent can do

Stated up front so no phase silently assumes a Roblox behaviour it cannot exercise.

- **Phases 1–3 need no Studio at all.** The pure migration, its Lune test, the Config block, the
  vendoring and the whole service compile and typecheck from the terminal.
- **Persistence itself cannot be proven from the terminal.** DataStore access in Studio requires
  *Game Settings → Security → Enable Studio Access to API Services*, and it only works in a **published**
  place. Both are Studio UI actions; no agent can drive either. Phase 4 makes this a step with **no
  `**Verify:**` line**, which `verify-plan.mjs` reports as `unverifiable` and `next-phase.mjs` marks
  `needs-human` — the honest answer, rather than a check that always passes.
- **Until that switch is flipped, ProfileStore silently uses mock storage.** It exposes
  `ProfileStore.DataStoreState` (`"NotReady" | "NoInternet" | "NoAccess" | "Access"`), and data persists
  only on `"Access"`. Step 4.1 makes that state legible in the log, so a rejoin test that "failed" for
  want of a checkbox cannot be mistaken for a code bug.
- **The playtester CAN drive the rest** once the switch is on: join, play a round to ENDING, leave,
  rejoin, read the profile back. Step 4.4 is that protocol.

---

## 2. Comprehensive Plan by Phases

### Phase 1: The schema and the migration — provable without Roblox

Everything here runs under Lune or the analyzer. Nothing in this phase touches the DataModel, and that
is deliberate: the migration is the one part of C31 that can be *proven* rather than observed, so it
lands first and lands tested.

#### Step 1.1: Reconcile `PlayerProfile` with §6.6 — add the missing `Purchases` field

**File:** `src/shared/Types.luau`
**Verify:** `npm run verify:fast`

`Types.luau:35-46` matches the spec's table except for `Purchases = { GamepassCacheUTC = 0 }`. Add it
so the declared type and §6.6 agree before anything is written against either.

```diff
 export type PlayerProfile = {
 	SchemaVersion: number, -- versioned from day one; write the migration path
 	XP: number,
 	Level: number,
 	Coins: number,
 	Stats: PlayerStats,
 	Cosmetics: Cosmetics,
 	Daily: {
 		LastClaimUTC: number,
 		Streak: number,
 	},
+	--[[
+		§6.6's fourth field, missing from the scaffold. A CACHE STAMP, not an entitlement: it records
+		when this server last asked Roblox which gamepasses the player owns, so C35 can avoid a
+		`UserOwnsGamePassAsync` call on every check. Ownership itself is never stored here — a cached
+		"owns it" is a value that survives a refund, and the authority is Roblox, not us.
+	]]
+	Purchases: {
+		GamepassCacheUTC: number,
+	},
 }
```

Note the type here and `ProfileMigration.Profile` in Step 1.2 are **two declarations of the same
shape**, deliberately. The pure module cannot require this file (Lune has no `script`), and Luau's
structural typing makes them interchangeable at the call site anyway. Step 3.1 passes a
`ProfileMigration.Profile` where a `Types.PlayerProfile` is expected without a cast; if that ever stops
compiling, the two shapes have drifted and the analyzer is telling you so.

#### Step 1.2: Write the pure migration module

**File:** `src/shared/pure/ProfileMigration.luau`
**Verify:** `npm run analyze`

`template()`, `CURRENT_VERSION`, and `migrate(stored)` returning a result table whose outcome is a
scalar union. No `script` requires; the profile shape is re-declared locally.

**The signature, settled:**

```luau
ProfileMigration.CURRENT_VERSION: number
ProfileMigration.template(): Profile
ProfileMigration.migrate(stored: any): Result
```

`stored: any` and not `Profile?` — the input is whatever came back from a DataStore, written by a build
that no longer exists. Typing it as a `Profile` would be asserting the very thing this function is here
to establish.

`src/shared/pure/RejoinResolve.luau` is the model for the whole shape — locally re-declared unions,
exported so the test can consume them, no `script` anywhere — and `references/RejoinResolve-review.luau`
annotates why each of those is load-bearing, plus why its rejoin concern and C31's are unrelated.

**The union rule, per `.claude/lessons/pure-module-unions-widen-in-lists.md`.** `Outcome` is a literal
union and it appears **only as a scalar field** of the returned table, never inside `Applied` (which is
`{ string }`, plain strings by design). Callers compare it with `==` against a string literal — no cast
anywhere, on either side of the `require`. The lesson's failure needs a union *inside a list*; keeping
the list untyped-by-literals is what makes this module immune to it, and it cost nothing to arrange.

```diff
+--!strict
+--[[
+	ProfileMigration — what a saved player looks like, and how an old one becomes a current one.
+	(§6.6, C31)
+
+		migrate(whatever the DataStore returned) -> { Outcome, Profile, FromVersion, Applied }
+
+	WHY THIS EXISTS BEFORE IT IS NEEDED. C31's brief is explicit: "SchemaVersion = 1 and the migration
+	path written on day one, before you need it. You will change the schema; the question is only
+	whether the migration exists when you do." The expensive version of this module is the one written
+	in a hurry against live player data.
+
+	NO `script` REQUIRES, AND THE SHAPE IS RE-DECLARED. Lune has no `script`, so a pure module that
+	reaches for `Types` stops being runnable from a terminal and the whole point is lost. `Profile`
+	below and `Types.PlayerProfile` are the same structural type and pass to each other uncast.
+
+	`Outcome` IS A SCALAR AND NEVER TRAVELS IN A LIST. A literal union survives `require` as a scalar
+	and does NOT survive inside an array — see `.claude/lessons/pure-module-unions-widen-in-lists.md`,
+	which cost eight failed fixes to learn. `Applied` is deliberately `{ string }`.
+
+	EVERY FIELD IS COERCED, NOT TRUSTED. A stored profile is attacker-adjacent input: not because a
+	client can write it (nothing here takes a client value — §6.6's fourth rule), but because a
+	corrupt or truncated save must degrade to a default rather than propagate a `nil` into a service.
+]]
+
+export type Stats = {
+	Rounds: number,
+	Survived: number,
+	AswangRounds: number,
+	AswangWins: number,
+	Kills: number,
+	TasksDone: number,
+}
+
+export type Cosmetics = {
+	Owned: { [string]: boolean },
+	Equipped: {
+		Skin: string,
+		Lantern: string,
+		DeathFX: string,
+	},
+}
+
+export type Profile = {
+	SchemaVersion: number,
+	XP: number,
+	Level: number,
+	Coins: number,
+	Stats: Stats,
+	Cosmetics: Cosmetics,
+	Daily: {
+		LastClaimUTC: number,
+		Streak: number,
+	},
+	Purchases: {
+		GamepassCacheUTC: number,
+	},
+}
+
+--[[
+	FRESH    nothing was stored — a first-time player.
+	CURRENT  stored at the version we run; fields reconciled, version untouched.
+	MIGRATED stored at an older version; upgraded, and `Applied` says how.
+	REFUSED  stored at a NEWER version than this server understands. See `migrate`.
+]]
+export type Outcome = "FRESH" | "CURRENT" | "MIGRATED" | "REFUSED"
+
+export type Result = {
+	Outcome: Outcome,
+	Profile: Profile,
+	FromVersion: number,
+	Applied: { string },
+}
+
+local ProfileMigration = {}
+
+ProfileMigration.CURRENT_VERSION = 1
+
+-- A cosmetic id longer than this is not a cosmetic id. Bounds on a stored string keep a corrupt save
+-- from becoming a 4MB key in the next write.
+local MAX_ID_LENGTH = 64
+local MAX_OWNED_COSMETICS = 256
+
+-- `value == value` is the NaN test. A NaN that reaches DataStore fails the write for the whole
+-- profile, so it is dropped here rather than diagnosed three layers away.
+local function num(value: any, fallback: number): number
+	if type(value) ~= "number" or value ~= value or value < 0 then
+		return fallback
+	end
+
+	return math.floor(value)
+end
+
+local function str(value: any, fallback: string): string
+	if type(value) ~= "string" or #value == 0 or #value > MAX_ID_LENGTH then
+		return fallback
+	end
+
+	return value
+end
+
+local function ownedFrom(value: any): { [string]: boolean }
+	local owned: { [string]: boolean } = {}
+
+	if type(value) ~= "table" then
+		return owned
+	end
+
+	local count = 0
+
+	for key, flag in value do
+		if type(key) ~= "string" or flag ~= true or #key > MAX_ID_LENGTH then
+			continue
+		end
+
+		count += 1
+
+		if count > MAX_OWNED_COSMETICS then
+			break
+		end
+
+		owned[key] = true
+	end
+
+	return owned
+end
+
+function ProfileMigration.template(): Profile
+	return {
+		SchemaVersion = ProfileMigration.CURRENT_VERSION,
+		XP = 0,
+		Level = 1,
+		Coins = 0,
+		Stats = {
+			Rounds = 0,
+			Survived = 0,
+			AswangRounds = 0,
+			AswangWins = 0,
+			Kills = 0,
+			TasksDone = 0,
+		},
+		Cosmetics = {
+			Owned = {},
+			Equipped = {
+				Skin = "default",
+				Lantern = "default",
+				DeathFX = "default",
+			},
+		},
+		Daily = {
+			LastClaimUTC = 0,
+			Streak = 0,
+		},
+		Purchases = {
+			GamepassCacheUTC = 0,
+		},
+	}
+end
+
+--[[
+	Field-by-field, defaulting anything missing or malformed. This is what makes a v0 profile — one
+	written before `SchemaVersion` existed, so a bare `{ XP = 120 }` — become a whole v1 profile that
+	keeps the 120.
+]]
+local function reconcile(stored: { [string]: any }): Profile
+	local base = ProfileMigration.template()
+	local stats: any = if type(stored.Stats) == "table" then stored.Stats else {}
+	local cosmetics: any = if type(stored.Cosmetics) == "table" then stored.Cosmetics else {}
+	local equipped: any = if type(cosmetics.Equipped) == "table" then cosmetics.Equipped else {}
+	local daily: any = if type(stored.Daily) == "table" then stored.Daily else {}
+	local purchases: any = if type(stored.Purchases) == "table" then stored.Purchases else {}
+
+	return {
+		SchemaVersion = ProfileMigration.CURRENT_VERSION,
+		XP = num(stored.XP, base.XP),
+		Level = math.max(num(stored.Level, base.Level), 1),
+		Coins = num(stored.Coins, base.Coins),
+		Stats = {
+			Rounds = num(stats.Rounds, 0),
+			Survived = num(stats.Survived, 0),
+			AswangRounds = num(stats.AswangRounds, 0),
+			AswangWins = num(stats.AswangWins, 0),
+			Kills = num(stats.Kills, 0),
+			TasksDone = num(stats.TasksDone, 0),
+		},
+		Cosmetics = {
+			Owned = ownedFrom(cosmetics.Owned),
+			Equipped = {
+				Skin = str(equipped.Skin, base.Cosmetics.Equipped.Skin),
+				Lantern = str(equipped.Lantern, base.Cosmetics.Equipped.Lantern),
+				DeathFX = str(equipped.DeathFX, base.Cosmetics.Equipped.DeathFX),
+			},
+		},
+		Daily = {
+			LastClaimUTC = num(daily.LastClaimUTC, 0),
+			Streak = num(daily.Streak, 0),
+		},
+		Purchases = {
+			GamepassCacheUTC = num(purchases.GamepassCacheUTC, 0),
+		},
+	}
+end
+
+function ProfileMigration.migrate(stored: any): Result
+	if type(stored) ~= "table" then
+		return {
+			Outcome = "FRESH",
+			Profile = ProfileMigration.template(),
+			FromVersion = 0,
+			Applied = {},
+		}
+	end
+
+	local version = num(stored.SchemaVersion, 0)
+
+	--[[
+		A PROFILE FROM THE FUTURE IS NOT MIGRATED, IT IS REFUSED — and this is the branch that matters
+		most, because it is the one that loses data if it is wrong.
+
+		A player who joined a server running a newer build, then joins an older one (a rolled-back
+		deploy, a lagging server that has not restarted), arrives with fields this code has never heard
+		of. Reconciling them DELETES those fields, and the next autosave writes the deletion back. The
+		refusal is the only safe answer: the caller latches the profile read-only, touches nothing, and
+		whatever is saved is byte-identical to what was read.
+
+		The returned `Profile` is a template purely so callers never handle a `nil`. It must never be
+		written — see `ProgressionService`'s read-only latch (Step 3.2).
+	]]
+	if version > ProfileMigration.CURRENT_VERSION then
+		return {
+			Outcome = "REFUSED",
+			Profile = ProfileMigration.template(),
+			FromVersion = version,
+			Applied = {},
+		}
+	end
+
+	local applied: { string } = {}
+
+	if version < 1 then
+		table.insert(applied, "v0->v1 defaults filled, SchemaVersion stamped")
+	end
+
+	-- Annotated local with literal branches. The analyzer narrows a literal checked against a declared
+	-- type; it does NOT narrow a `::` cast over a union, which is the trap the lesson documents.
+	local outcome: Outcome = if version < ProfileMigration.CURRENT_VERSION then "MIGRATED" else "CURRENT"
+
+	return {
+		Outcome = outcome,
+		Profile = reconcile(stored),
+		FromVersion = version,
+		Applied = applied,
+	}
+end
+
+return ProfileMigration
```

#### Step 1.3: Pin the migration with a Lune test, including v0 → v1

**File:** `tests/profile-migration.test.luau`
**Verify:** `lune run tests/profile-migration.test.luau`

The chunk's own Done condition — "a v0 profile migrates to v1 cleanly" — becomes an assertion, alongside
the fresh, already-current, partially-corrupt and newer-than-us cases. This is the strongest check in
the plan and the only one that proves behaviour rather than shape, which is why it lands in Phase 1.

Follow the existing suite conventions exactly — `tests/rejoin-resolve.test.luau` is the model and
`references/rejoin-resolve.test-review.luau` annotates the four that have teeth. Require
by relative path, reuse the module's exported types, a local `check` that bumps `checked`, `error(…, 0)`
on failure, and a `PASS` line whose count is **interpolated, never typed** — `check:testcount` fails a
literal digit outside `{…}`.

```diff
+--!strict
+--[[
+	The profile migration grid (§6.6, C31).
+
+	THE CELL THIS FILE EXISTS FOR is `v0 -> v1 keeps the XP`. A migration that returns a clean, correct,
+	EMPTY profile passes every type check in the repo and silently wipes every player on the day the
+	schema moves. Nothing else in the tree can catch that: the analyzer sees a well-formed `Profile`,
+	and by the time a human notices, the wipe has been autosaved.
+
+	The second thing pinned here is the REFUSAL. A profile written by a newer build must come back
+	`REFUSED` and not `MIGRATED`, because those two outcomes are one comparison apart in the module and
+	the difference is whether a rolled-back deploy deletes fields it has never heard of.
+]]
+
+local ProfileMigration = require("../src/shared/pure/ProfileMigration")
+
+type Outcome = ProfileMigration.Outcome
+
+local failures = 0
+local checked = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	checked += 1
+
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+--------------------------------------------------------------------------------
+-- A fresh player
+--------------------------------------------------------------------------------
+
+do
+	local template = ProfileMigration.template()
+
+	check("the template is at the current version", template.SchemaVersion == ProfileMigration.CURRENT_VERSION)
+	check("a fresh player starts at level 1 with nothing", template.XP == 0 and template.Level == 1 and template.Coins == 0)
+	check("§6.6's Purchases field is present", template.Purchases.GamepassCacheUTC == 0)
+	check("the three cosmetic slots default", template.Cosmetics.Equipped.Skin == "default" and template.Cosmetics.Equipped.Lantern == "default" and template.Cosmetics.Equipped.DeathFX == "default")
+
+	local first = ProfileMigration.template()
+	local second = ProfileMigration.template()
+
+	first.Stats.Kills = 9
+	check("template returns a FRESH table each call, not a shared one", second.Stats.Kills == 0)
+
+	for _, stored in { nil, 7, "profile", true } :: { any } do
+		local result = ProfileMigration.migrate(stored)
+
+		check(`{typeof(stored)} stored -> FRESH`, result.Outcome == "FRESH", result.Outcome)
+		check(`{typeof(stored)} stored -> a whole profile`, result.Profile.Level == 1)
+	end
+end
+
+--------------------------------------------------------------------------------
+-- v0 -> v1. The chunk's Done condition.
+--------------------------------------------------------------------------------
+
+do
+	-- A v0 profile is one written before SchemaVersion existed: no version field, partial shape.
+	local v0 = { XP = 120, Coins = 45, Stats = { Rounds = 3, Kills = 1 } }
+	local result = ProfileMigration.migrate(v0)
+
+	check("v0 is recognised as version 0", result.FromVersion == 0, `{result.FromVersion}`)
+	check("v0 migrates rather than resetting", result.Outcome == "MIGRATED", result.Outcome)
+	check("v0 -> v1 KEEPS the XP", result.Profile.XP == 120, `{result.Profile.XP}`)
+	check("v0 -> v1 KEEPS the coins", result.Profile.Coins == 45)
+	check("v0 -> v1 KEEPS a partial Stats table", result.Profile.Stats.Rounds == 3 and result.Profile.Stats.Kills == 1)
+	check("v0 -> v1 FILLS the stats it did not have", result.Profile.Stats.TasksDone == 0)
+	check("v0 -> v1 FILLS §6.6's newer fields", result.Profile.Purchases.GamepassCacheUTC == 0)
+	check("v0 -> v1 stamps the version", result.Profile.SchemaVersion == ProfileMigration.CURRENT_VERSION)
+	check("the migration says what it did", #result.Applied == 1, `{#result.Applied} entries`)
+	check("the source table is not mutated", v0.Stats.TasksDone == nil and rawget(v0, "SchemaVersion") == nil)
+end
+
+--------------------------------------------------------------------------------
+-- Already current, and corrupt
+--------------------------------------------------------------------------------
+
+do
+	local current = ProfileMigration.template()
+
+	current.XP = 900
+	current.Cosmetics.Owned = { lantern_brass = true }
+
+	local result = ProfileMigration.migrate(current)
+
+	check("a current profile is CURRENT, not MIGRATED", result.Outcome == "CURRENT", result.Outcome)
+	check("a current profile is unchanged", result.Profile.XP == 900)
+	check("owned cosmetics survive", result.Profile.Cosmetics.Owned.lantern_brass == true)
+	check("a current profile applies nothing", #result.Applied == 0)
+
+	local corrupt = ProfileMigration.migrate({
+		SchemaVersion = 1,
+		XP = 0 / 0,
+		Level = -4,
+		Coins = "lots",
+		Cosmetics = { Owned = { [1] = true, ok = true, bad = "yes" }, Equipped = { Skin = "" } },
+	})
+
+	check("NaN XP falls back to the default", corrupt.Profile.XP == 0, `{corrupt.Profile.XP}`)
+	check("a negative level is clamped to 1", corrupt.Profile.Level == 1, `{corrupt.Profile.Level}`)
+	check("a string in a number field falls back", corrupt.Profile.Coins == 0)
+	check("an empty cosmetic id falls back to default", corrupt.Profile.Cosmetics.Equipped.Skin == "default")
+	check("only string keys mapped to `true` survive Owned", corrupt.Profile.Cosmetics.Owned.ok == true and corrupt.Profile.Cosmetics.Owned.bad == nil)
+end
+
+--------------------------------------------------------------------------------
+-- A profile from the future
+--------------------------------------------------------------------------------
+
+do
+	local future = ProfileMigration.migrate({ SchemaVersion = ProfileMigration.CURRENT_VERSION + 1, XP = 5000 })
+
+	check("a newer profile is REFUSED", future.Outcome == "REFUSED", future.Outcome)
+	check("a refusal reports the version it saw", future.FromVersion == ProfileMigration.CURRENT_VERSION + 1)
+	check("a refusal claims no migration steps", #future.Applied == 0)
+
+	local outcomes: { Outcome } = { "FRESH", "CURRENT", "MIGRATED", "REFUSED" }
+
+	check("every outcome is reachable", #outcomes == 4)
+end
+
+do
+	local input = { SchemaVersion = 1, XP = 12 }
+	local first = ProfileMigration.migrate(input)
+	local second = ProfileMigration.migrate(input)
+
+	check("migrate is deterministic", first.Outcome == second.Outcome and first.Profile.XP == second.Profile.XP)
+	check("migrating twice is migrating once", ProfileMigration.migrate(first.Profile).Outcome == "CURRENT")
+end
+
+if failures > 0 then
+	error(`{failures} profile-migration assertion(s) failed`, 0)
+end
+
+print(`  PASS  profile-migration: {checked} assertions over fresh, v0, current, corrupt and future`)
```

**Note on formatting:** several `check(…)` lines above run past 100 columns as written. `npm run fmt`
wraps them; run it before `fmt:check` sees them. The assertions are what matter, not the wrapping.

**`migrate(first.Profile).Outcome == "CURRENT"` is the idempotence check** and it is worth the line: a
migration that is not idempotent corrupts on the second load rather than the first, which means it
passes every test written against a fresh fixture and fails in production a day later.

#### Step 1.4: Add `Config.Profile` and pin its relationships

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

The retry, timeout and shutdown-budget knobs C31 needs, plus two invariants in the existing config suite
so the numbers cannot silently drift apart from `Round` or from Roblox's shutdown window.

These land **before** the service that reads them, so Step 3.1 can be written against `Config.Profile.*`
from its first line and `check:config` has something to point at.

```diff
 	Economy = {
 		XPPerRound = 50,
 		XPWinBonus = 40,
 		XPSurvivorEscapeBonus = 25,
 		CoinsPerRound = 25,
 		XPPerLevel = 500,
 	},
 
+	--[[
+		Profile persistence (C31, §6.6).
+
+		THE SCHEMA VERSION IS NOT HERE, AND THAT IS DELIBERATE. It lives in
+		`shared/pure/ProfileMigration.luau` as `CURRENT_VERSION`, because that module must run under
+		Lune and cannot require this file — Lune has no `script`. Duplicating it here would create two
+		sources of truth for the one number where disagreement means data loss, and the copy the
+		migration actually reads would be the one nobody edited.
+	]]
+	Profile = {
+		--[[
+			The DataStore name. CHANGING THIS ORPHANS EVERY EXISTING PLAYER — it is a new namespace,
+			not a rename, and there is no migration path back. It carries no version suffix on
+			purpose: `ProfileMigration` is how the schema moves, and a name bump would make that
+			module dead code the first time it was needed.
+		]]
+		StoreName = "PlayerProfile",
+
+		-- How many times to retry `StartSessionAsync` before giving up on a player. A failed session
+		-- is not fatal — they play, nothing saves, and the warn says so — but it should be rare.
+		SessionStartAttempts = 3,
+		SessionStartRetryDelay = 4,
+
+		--[[
+			The wall-clock budget `ShutdownFlush.flushAll()` may spend inside `game:BindToClose`.
+			ROBLOX GIVES ABOUT 30 SECONDS AND THEN KILLS THE PROCESS MID-WRITE, so this must stay
+			under it with room to spare — pinned in `tests/config.test.luau` rather than trusted.
+		]]
+		ShutdownFlushBudget = 25,
+	},
+
 	-- The Solo Trial: tutorial + low-population fallback. See spec §9.1.
```

And the invariants, appended to the existing suite above its `if failures > 0` block:

```diff
+--[[
+	C31. Roblox's `BindToClose` window is roughly 30 seconds and then the process dies mid-write —
+	which is the exact failure the flush exists to prevent, arriving by a different door. A budget at
+	or above the window is a budget that has never actually bounded anything.
+]]
+check(
+	"the shutdown flush budget stays inside Roblox's BindToClose window",
+	Config.Profile.ShutdownFlushBudget < 30,
+	`{Config.Profile.ShutdownFlushBudget}s`
+)
+
+--[[
+	C31. A player who joins during INTERMISSION must have a profile — or a settled failure — before
+	the round they joined for begins, or the first thing C32 awards them lands on a profile that is
+	still loading and is thrown away when it arrives.
+]]
+check(
+	"session retries resolve before a round can start",
+	Config.Profile.SessionStartAttempts * Config.Profile.SessionStartRetryDelay
+		< Config.Round.Intermission + Config.Round.StartingDelay,
+	`{Config.Profile.SessionStartAttempts} x {Config.Profile.SessionStartRetryDelay}s`
+)
+
+check("at least one session attempt is made", Config.Profile.SessionStartAttempts >= 1)
+
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — one field to be careful with, and one trap to refuse.** `Stats.AswangRounds` and
  `Stats.AswangWins` are a *history* of how often this player drew the role, and they are written
  server-side only. They are safe in the profile and would be fatal on the wire: a client that can read
  its own `AswangRounds` before a round has ended learns nothing, but a UI that shows them *live*, or an
  anti-repeat weighting that a client could replay, would. C31 sends none of it anywhere. Separately:
  **do not create a `leaderstats` folder.** It is the standard Roblox way to surface XP and it
  replicates to every client by design; C33 will surface progression through a deliberate remote.
- **Strict Luau — two spots.** `local outcome: Outcome = if … then "MIGRATED" else "CURRENT"` must keep
  its annotation; without it the literals widen to `string` and the return type rejects them. And the
  `any`-typed locals in `reconcile` are intentional, not laziness — a stored table is genuinely of
  unknown shape and typing the intermediates would be asserting what the function is checking.
- **Magic numbers — none in the pure module's governed path.** `check:config`'s `GOVERNED` regex is
  `src/(server|client)/` (`check-config.mjs:41`), so `MAX_ID_LENGTH = 64` in `src/shared/pure/` is not
  flagged and needs no waiver. `Config.Profile`'s three numbers are all above the idiomatic threshold
  and are exactly where the check wants them.
- **Player leaving mid-round** — not yet reachable; Phase 1 adds no runtime behaviour. §6.4's cases land
  in Phase 3, where the leave path is written.
- **Scope** — none of C31's vocabulary (`Profile`, `Purchases`, `Cosmetics`, `Daily`, `Streak`,
  `Migration`) collides with §3's OUT tokens. Checked against `check-scope.mjs:38-55`. Note that
  `seasons` and `trades` **are** on the list, so a future daily/battle-pass idea does not get to reuse
  those words in `src/`.

---

### Phase 2: Vendor ProfileStore where the gates cannot see it

#### Step 2.1: Fetch and pin the ProfileStore source

**File:** `vendor/ProfileStore.luau`
**Verify:** `test -f vendor/ProfileStore.luau`

One file, unmodified, from MadStudioRoblox/ProfileStore.

**Fetch it by commit SHA, not by branch.** `main` moves; a vendored dependency that changes underneath
the repo is the same class of problem as an untracked map file. Resolve the SHA first, fetch by it, and
record it in Step 2.4:

```bash
mkdir -p vendor
git ls-remote https://github.com/MadStudioRoblox/ProfileStore HEAD   # → record this SHA
curl -fsSL -o vendor/ProfileStore.luau \
  "https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/<SHA>/ProfileStore.luau"
```

**Do not edit the file.** Not the formatting, not the types, not a stray `--!strict`. The whole value of
vendoring outside `src/` is that this file is never our problem; the moment it is edited it becomes a
fork that has to be re-applied on every upgrade.

**The API this plan is written against**, confirmed by reading the source rather than assumed — the
plan's Hard Rule 1 applies to third-party Luau exactly as it does to Roblox itself:

| Call | Shape |
| --- | --- |
| `ProfileStore.New(store_name, template?)` | returns a store |
| `store:StartSessionAsync(key, params?)` | `params = { Steal: boolean?, Cancel: () -> boolean }`; returns `Profile?` |
| `ProfileStore.DataStoreState` | `"NotReady" \| "NoInternet" \| "NoAccess" \| "Access"` |
| `ProfileStore.IsClosing` · `ProfileStore.IsCriticalState` | booleans |
| `profile.Data` · `profile.LastSavedData` · `profile.Session` | the saved table, the last write, the lock |
| `profile:IsActive()` · `:Reconcile()` · `:Save()` · `:EndSession()` | session lifecycle |
| `profile:AddUserId(id)` · `:RemoveUserId(id)` | GDPR association |
| `profile.OnSessionEnd` · `.OnLastSave` · `.OnAfterSave` | signals; `OnLastSave` reports `"Manual" \| "External" \| "Shutdown"` |
| `ProfileStore.Mock.*` | mirrors the store against mock storage |

**`ProfileStore.SetConstant` is deliberately not used by this plan.** It exists and would let us tune
the internal autosave period, but its `ConstantName` values are internal to the vendored file and would
have to be re-verified on every upgrade. C31 tunes only its own knobs, in `Config.Profile`. Raised in
Follow Ups.

If the vendored source's API differs from the table above, **adapt Step 3.1's wrapper and nothing
else** — `ProgressionService` is the only file in this repo that will ever name a ProfileStore symbol,
which is the point of routing everything through it.

#### Step 2.2: Map `vendor/` into Studio as `ServerScriptService.Packages`

**File:** `default.project.json`
**Verify:** `npm run build`

A second child under `ServerScriptService`, so Rojo syncs it and `rojo build` proves the tree resolves.

```diff
     "ServerScriptService": {
       "Server": {
         "$path": "src/server"
-      }
+      },
+
+      "Packages": {
+        "$path": "vendor"
+      }
     },
```

**`Packages` is a SIBLING of `Server`, not a child of it, and that is the whole design.** A child would
put the vendored file under `src/server/`, back inside every gate. As a sibling it lands at
`ServerScriptService.Packages.ProfileStore`, server-only (never `ReplicatedStorage` — nothing a client
can require), and its source directory is `vendor/`, which `selene src`, `stylua src tests`,
`luau-lsp … src` and `listLuau()`'s default root all decline to look at.

**`npm run build` is the right check here** because it is the one command that actually resolves the
project file: a typo in the JSON, a missing directory, or a name collision under `ServerScriptService`
all fail it, and none of them fail `analyze`.

**Run `mkdir -p build` first.** `build/` is gitignored and therefore absent on a clean tree, and Rojo
reports that as `failed to create file build/aswang.rbxl` — a real failure with nothing to do with the
project file, and exactly the kind of red herring that costs twenty minutes. Measured on this tree
before the plan was written.

The require side, for Step 3.1:

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))
```

**Regenerate the sourcemap after this step** — `npm run sourcemap`, or let `npm run analyze` do it
(`check-analyze.mjs:87` regenerates when stale). Without it the analyzer has no idea `Packages` exists.
Note that luau-lsp may resolve this require to `any` rather than to the module's real type; that is
acceptable and even convenient here, since the vendored file is not typed to this repo's standard. It is
also why every ProfileStore value crossing into our code gets an explicit local annotation in Step 3.1.

#### Step 2.3: Prove every gate still ignores it

**File:** `analyze-baseline.json`
**Verify:** `npm run verify`

The claim in §1.1(a) is falsifiable and this step falsifies it: the whole gate must stay green with
third-party source in the tree and the baseline still empty.

**This step's deliverable is a NON-change.** `analyze-baseline.json` must still read `"known": []` after
the vendoring, and `npm run verify` — analyze, selene, StyLua, all five repo checks, every Lune suite and
the harness self-tests — must be green:

```diff
 {
   "note": "Diagnostics allowed to fail. …",
   "blessedAt": "2026-08-10",
   "known": []
 }
```

Both scopes are annotated in `references/check-analyze-review.luau` (the analyzer's `src`-only
invocation, and `--update` refusing to run under an agent) and `references/check-config-review.luau`
(the `GOVERNED` regex), with `references/package-review.luau` covering `selene src` and
`stylua src tests`. Read those before concluding a gate has been missed.

**Why the non-change is worth a step of its own.** `check-analyze.mjs --update` refuses to run when
`CLAUDE_AGENT_TYPE` is set, so if vendoring did produce diagnostics, an agent could not clear them and
the run would halt waiting on a human. Confirming it does not is what makes the rest of this plan
implementable unattended, and confirming it *here* means the failure surfaces before a service has been
written against it.

**If `npm run verify` does report diagnostics naming `vendor/ProfileStore.luau`**, work this ladder in
order and do not skip to the end:

1. **Confirm the source.** `luau-lsp analyze` is invoked over `src` only (`check-analyze.mjs:104`), so a
   `vendor/` diagnostic means it is being pulled in transitively. Read the file path in the message.
2. **Add `vendor/.luaurc` with `{ "languageMode": "nonstrict" }`.** The analyzer is run with
   `--base-luaurc=.luaurc`, and a nested `.luaurc` applies to its own directory. Third-party code was
   never written to this repo's strict standard and should not be graded against it.
3. **Only then, a human re-blesses the baseline** with `node .claude/scripts/check-analyze.mjs --update`
   and says why in the commit. An agent must stop and ask rather than attempt this.

Step 3 is last because widening the baseline is the one action that makes every future analyze weaker,
and it is tracked at the repo root precisely so it has to be argued for in a diff.

#### Step 2.4: Record the pin and the fallback

**File:** `vendor/README.md`
**Verify:** `test -f vendor/README.md`

What version landed, where it came from, that it is unmodified, and what to do if a future analyzer
does start reporting on it.

A vendored file with no provenance is indistinguishable from a file somebody wrote, and the next person
to see a bug in it will debug it as ours. Record the SHA resolved in Step 2.1.

```diff
+# vendor/
+
+Third-party Luau, **outside `src/` on purpose**. Nothing in here is ours and nothing in here is edited.
+
+## Why it is not in `src/`
+
+Every gate in this repo is scoped to `src/` — `selene src`, `stylua src tests`, `luau-lsp … src`, and
+`listLuau()`'s default root for the five `check:*` scripts. Vendoring here therefore needs no StyLua
+ignore, no selene exclude, no waiver comments, and **no entry in `analyze-baseline.json`**. That last
+one matters more than it looks: `check-analyze.mjs --update` refuses to run under an agent, so a
+dependency that forced the baseline open would halt an unattended build.
+
+Rojo maps this directory to `ServerScriptService.Packages` (see `default.project.json`). It is
+server-only — never `ReplicatedStorage`, so no client can require it.
+
+## ProfileStore
+
+| | |
+| --- | --- |
+| Source | https://github.com/MadStudioRoblox/ProfileStore |
+| Commit | `<SHA recorded at vendoring time>` |
+| Vendored | 2026-08-19, chunk C31 |
+| Modified | **no** — byte-identical to upstream |
+| Used by | `src/server/Services/ProgressionService.luau`, and nothing else |
+
+Required by `docs/MVP-SPEC.md` §6.1: "**ProfileStore** (or similar session-locked DataStore wrapper) —
+prevents data loss and duplication bugs. Do **not** hand-roll DataStore access."
+
+### Upgrading
+
+Re-fetch by a new SHA, update the row above, and run `npm run verify` plus a rejoin playtest. Only
+`ProgressionService` names a ProfileStore symbol, so an API change has exactly one call site to fix.
+
+### If the analyzer ever starts reporting on this directory
+
+Add `vendor/.luaurc` with `{ "languageMode": "nonstrict" }` before considering anything else. Do not
+re-bless `analyze-baseline.json` to silence third-party code without saying why in the commit.
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Scope — `check:scope` never sees `vendor/`, and that is a real hole worth naming.** It is the right
  trade (flagging a third-party library's vocabulary would train everyone to ignore the check, exactly
  as `check-scope.mjs:20-21` argues for docs), but it means a vendored dependency is outside the scope
  alarm. Acceptable for one storage library with a single call site; it would not be acceptable as a
  habit of vendoring gameplay code.
- **`.gitignore` — confirm `vendor/` is tracked.** `build/`, `sourcemap.json` and the place file are
  ignored here; a vendored dependency that lands inside an ignored path would vanish on a fresh clone
  and the failure would be "ProfileStore is nil" on someone else's machine. Check before committing.
- **`rojo serve` must be restarted** after `default.project.json` changes — a running server does not
  pick up a new tree mapping, and the symptom is `WaitForChild("Packages")` hanging forever with no
  error, which is the same silent-hang failure `check:remotes` exists to prevent for remotes.
- **Secret leakage · remotes · rate limiting · phase ownership** — none. This phase adds no Luau of our
  own, no remote and no runtime behaviour.
- **Mobile budget** — none; ProfileStore does no per-frame work. Its autosave is a background task on
  the server.

---

### Phase 3: ProgressionService owns the profile

#### Step 3.1: Start a session on join, migrate on read

**File:** `src/server/Services/ProgressionService.luau`
**Verify:** `npm run check:config`

`StartSessionAsync` with retries from `Config.Profile`, `Reconcile()`, then the pure migration, then
`AddUserId`. Every number read from Config, which is what this check proves.

This replaces the four `TODO(M9)` lines in the 20-line stub. **`ProgressionService` is the only file in
this repo that will ever name a ProfileStore symbol** — that is what makes the vendored dependency
replaceable and what keeps an upstream API change to one call site.

```diff
 --!strict
 --[[
-	ProgressionService — XP, levels, coins, daily streak, ProfileStore persistence.
-
-	Milestone: M9
-	Spec: docs/MVP-SPEC.md
+	ProgressionService — the profile: load it, hold it, save it. (M9, C31, §6.6)
+
+	WHAT IT OWNS. One session-locked profile per player, from join to leave, plus the single write path
+	every other service must go through to change one. It owns the DATA; C32 owns the POLICY of what a
+	round is worth, C33 the daily streak, C35 the gamepass cache.
+
+	THE SECRET IS NOT IN HERE, AND ONE FIELD IS WORTH NAMING. `Stats.AswangRounds` and `AswangWins` are
+	a history of how often this player drew the role. Server-only, like the rest of the profile — but
+	unlike XP they would be a genuine leak if surfaced, so no remote in this file, no attribute, no
+	tag, and NO `leaderstats` FOLDER: `leaderstats` is the standard Roblox way to show a number and it
+	replicates to every client by design. C33 surfaces progression through a deliberate remote.
+
+	NOTHING HERE TAKES A CLIENT VALUE — §6.6's fourth rule. `Award` and `BumpStat` are called by
+	server code with server-computed numbers; there is no `OnServerEvent` handler in this file, which
+	is why `check:ratelimit` has nothing to say about it. If that ever changes, the handler consults
+	`AntiCheatService` first and the remote is declared in `Remotes.luau` — both, or neither.
+
+	THE WRAPPER IS THIN ON PURPOSE. Every decision about SHAPE lives in
+	`shared/pure/ProfileMigration.luau`, which runs under Lune and is tested exhaustively. What is left
+	here is the part Lune cannot see: DataStore calls, player lifecycle, and the shutdown flush.
 ]]
 
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local ServerScriptService = game:GetService("ServerScriptService")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local ProfileMigration = require(Shared.pure.ProfileMigration)
+local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)
+
+--[[
+	Vendored, and deliberately outside `src/` — see `vendor/README.md`. It is at
+	`ServerScriptService.Packages`, a SIBLING of `Server`, so no client can require it and no gate in
+	this repo has to grade someone else's Luau.
+]]
+local Packages = ServerScriptService:WaitForChild("Packages")
+local ProfileStore = require(Packages:WaitForChild("ProfileStore"))
+
+type Profile = ProfileMigration.Profile
+
 local ProgressionService = {}
 
--- TODO(M9): integrate a session-locked datastore wrapper (ProfileStore).
---            Do NOT hand-roll DataStore access — data loss and duplication bugs.
--- TODO(M9): schema versioning + migration on read (Types.PlayerProfile).
--- TODO(M9): save on meaningful change, on leave, and in game:BindToClose().
+--[[
+	SERVER-ONLY STATE. Keyed by UserId, never replicated, never enumerated to a client.
+
+	`sessions` holds the live ProfileStore profile object, not our table — `profile.Data` is the table.
+	`readOnly` latches a player whose stored profile came from a NEWER schema than this server runs:
+	we never touch their `Data`, so whatever ProfileStore writes back is byte-identical to what it
+	read. See `ProfileMigration.migrate`'s REFUSED branch for why that is the only safe answer.
+]]
+local sessions: { [number]: any } = {}
+local readOnly: { [number]: boolean } = {}
+local store: any = nil
+
+local function keyFor(player: Player): string
+	return `Player_{player.UserId}`
+end
+
+-- `source` is `any`, so the cast always holds. Copying key-by-key rather than reassigning
+-- `profile.Data` keeps the table identity ProfileStore was handed at session start — see the
+-- QUESTION in Follow Ups.
+local function copyInto(target: any, source: any)
+	for key, value in source :: { [string]: any } do
+		target[key] = value
+	end
+end
+
+local function startSession(player: Player)
+	local userId = player.UserId
+	local profile: any = nil
+
+	for attempt = 1, Config.Profile.SessionStartAttempts do
+		--[[
+			`Cancel` is checked by ProfileStore while it waits on another server's lock. Without it, a
+			player who joins and leaves inside the lock window leaves a request in flight that resolves
+			into a session nobody ends.
+		]]
+		profile = store:StartSessionAsync(keyFor(player), {
+			Cancel = function()
+				return player.Parent ~= Players
+			end,
+		})
+
+		if profile ~= nil or player.Parent ~= Players then
+			break
+		end
+
+		warn(`[Progression] session start failed for {player.Name}, attempt {attempt}`)
+
+		if attempt < Config.Profile.SessionStartAttempts then
+			task.wait(Config.Profile.SessionStartRetryDelay)
+		end
+	end
+
+	--[[
+		A FAILED LOAD IS NOT FATAL AND MUST NOT BE. Kicking a player because a DataStore was briefly
+		unavailable turns a Roblox outage into an empty server. They play; nothing saves; the warn says
+		so. `GetProfile` returns nil and every caller already has to handle that, because a player can
+		leave between the award and the write.
+	]]
+	if profile == nil then
+		warn(`[Progression] no profile for {player.Name} — nothing will be saved this session`)
+		return
+	end
+
+	-- They left while we were loading. Release the lock immediately or the next server waits it out.
+	if player.Parent ~= Players then
+		profile:EndSession()
+		return
+	end
+
+	profile:AddUserId(userId)
+	profile:Reconcile()
+
+	local result = ProfileMigration.migrate(profile.Data)
+
+	if result.Outcome == "REFUSED" then
+		readOnly[userId] = true
+		warn(
+			`[Progression] {player.Name} has a v{result.FromVersion} profile and this server writes `
+				.. `v{ProfileMigration.CURRENT_VERSION}. Read-only for this session.`
+		)
+	else
+		copyInto(profile.Data, result.Profile)
+	end
+
+	--[[
+		ProfileStore ends a session on its own when another server steals the lock — which is what
+		happens when a player rejoins elsewhere before this server has released. Kicking is correct
+		and is the standard handling: the profile they are holding is no longer theirs to write.
+	]]
+	profile.OnSessionEnd:Connect(function()
+		sessions[userId] = nil
+		readOnly[userId] = nil
+
+		if player.Parent == Players then
+			player:Kick("Your data was opened on another server. Rejoin to continue.")
+		end
+	end)
+
+	sessions[userId] = profile
+
+	if Config.Debug.VerboseLogging then
+		print(`[Progression] {player.Name}: {result.Outcome} from v{result.FromVersion}`)
+	end
+end
 
 function ProgressionService.Init() end
 
 function ProgressionService.Start() end
 
 return ProgressionService
```

**`check:config` is the right gate for this step** and it will genuinely fail if written carelessly: a
retry count or a delay typed as a literal here is exactly what it catches. Note that `for attempt = 1,
Config.Profile.SessionStartAttempts do` passes on both of its rules — a numeric for header is control
flow, and a line naming `Config.` is reading the knob rather than inventing one (`check-config.mjs:57-63`).

#### Step 3.2: End the session on leave, and expose a server-only mutation API

**File:** `src/server/Services/ProgressionService.luau`
**Verify:** `npm run analyze`

`GetProfile` / `Award` / `BumpStat`, all taking server-computed values only, plus the read-only latch
for a profile the migration refused, and the lifecycle wiring in `Init`/`Start`.

**This is the API C32, C33 and C35 will build on**, so it is worth getting the shape right once: reads
return the table, writes go through one guarded function, and there is no third door.

```diff
+--[[
+	`Save` on a MEANINGFUL CHANGE, which is §6.6's third rule and the one most often skipped. It does
+	not mean "on every field write" — ProfileStore autosaves on its own schedule, and a `Save()` per XP
+	point is a request budget spent on nothing. It means: after a change a player would be angry to
+	lose. A round's award is one. A cosmetic purchase (C34) is one. A stat increment is not.
+]]
+local function saveNow(userId: number)
+	local profile = sessions[userId]
+
+	if profile ~= nil and profile:IsActive() then
+		profile:Save()
+	end
+end
+
+local function endSession(userId: number)
+	local profile = sessions[userId]
+
+	sessions[userId] = nil
+	readOnly[userId] = nil
+
+	--[[
+		`EndSession` SAVES AND THEN RELEASES THE LOCK, in that order, which is why a leaving player
+		needs no explicit `Save` first. It is also why a read-only profile is safe to end: we never
+		mutated `Data`, so the write is byte-identical to the read.
+	]]
+	if profile ~= nil then
+		profile:EndSession()
+	end
+end
+
+type StatName = "Rounds" | "Survived" | "AswangRounds" | "AswangWins" | "Kills" | "TasksDone"
+
+--[[
+	READ. Returns the LIVE table, not a copy — callers must not hand it to anything that replicates.
+	Nil is a normal answer, not an error: a DataStore outage, a player mid-load, or a player who has
+	already left all produce one.
+]]
+function ProgressionService.GetProfile(player: Player): Profile?
+	local profile = sessions[player.UserId]
+
+	return if profile ~= nil then profile.Data else nil
+end
+
+--[[
+	THE ONLY WRITE PATH FOR CURRENCY, and the enforcement point for §6.6's fourth rule.
+
+	Every argument is computed on the server. NO CLIENT VALUE REACHES THIS FUNCTION — not through a
+	remote, not through an attribute, not laundered through a "requested amount". The validation below
+	is therefore not defending against a player; it is defending against a bug in C32 writing a NaN or
+	a negative into a table that then fails every subsequent DataStore write for that player, silently,
+	forever.
+
+	Returns whether anything was written, so a caller can log a refusal instead of assuming.
+]]
+function ProgressionService.Award(player: Player, xp: number, coins: number, reason: string): boolean
+	local userId = player.UserId
+	local profile = sessions[userId]
+
+	if profile == nil or readOnly[userId] then
+		return false
+	end
+
+	-- `value ~= value` is the NaN test. A NaN in a profile poisons every write for that key.
+	if xp ~= xp or coins ~= coins or xp < 0 or coins < 0 then
+		warn(`[Progression] refused a malformed award to {player.Name} ({reason}): {xp} xp, {coins} c`)
+		return false
+	end
+
+	local data: Profile = profile.Data
+
+	data.XP += math.floor(xp)
+	data.Coins += math.floor(coins)
+
+	saveNow(userId)
+
+	if Config.Debug.VerboseLogging then
+		print(`[Progression] {player.Name} +{xp} xp +{coins} coins ({reason})`)
+	end
+
+	return true
+end
+
+-- Stat bookkeeping. No `Save` — see `saveNow`'s comment on what "meaningful" means.
+function ProgressionService.BumpStat(player: Player, stat: StatName, amount: number)
+	local userId = player.UserId
+	local profile = sessions[userId]
+
+	if profile == nil or readOnly[userId] or amount ~= amount or amount < 0 then
+		return
+	end
+
+	local data: Profile = profile.Data
+
+	data.Stats[stat] += math.floor(amount)
+end
+
+--[[
+	Called from `ShutdownFlush` on `BindToClose`. Ends every live session, which saves each one.
+	SEQUENTIAL AND YIELDING ON PURPOSE — see `ShutdownFlush.flushAll`.
+]]
+function ProgressionService.FlushAll()
+	for userId in sessions do
+		endSession(userId)
+	end
+end
+
 function ProgressionService.Init()
+	--[[
+		`New` is cheap and does no I/O, so it belongs in Init: the store must exist before any other
+		service's `Start` can call `GetProfile`. The TEMPLATE is the pure module's — one definition of
+		a fresh player, shared by ProfileStore's own reconcile and by our migration.
+	]]
+	store = ProfileStore.New(Config.Profile.StoreName, ProfileMigration.template())
+
+	table.clear(sessions)
+	table.clear(readOnly)
 end
 
 function ProgressionService.Start()
+	Players.PlayerAdded:Connect(function(player)
+		task.spawn(startSession, player)
+	end)
+
+	Players.PlayerRemoving:Connect(function(player)
+		endSession(player.UserId)
+	end)
+
+	--[[
+		Anyone who joined before this ran. The same backfill `RoundService.Start` does and for the same
+		reason: connecting first means the window cannot drop a player, and the price is that someone
+		arriving inside it is handled twice. `startSession` is NOT idempotent — a second
+		`StartSessionAsync` for a key this server already holds is a lock fight with itself — so the
+		guard is explicit.
+	]]
+	for _, player in Players:GetPlayers() do
+		if sessions[player.UserId] == nil then
+			task.spawn(startSession, player)
+		end
+	end
 end
```

**`task.spawn(startSession, player)` and not a direct call**: `StartSessionAsync` yields, and a yielding
`PlayerAdded` handler blocks every later-connected handler for that player. This service is third in
`SERVICE_ORDER` (`init.server.luau:19-51`), so its connections are made early and a yield here would
stall the whole join path.

**`npm run analyze` is the right gate for this step**: `Award`'s `data: Profile` annotation, `StatName`
as a literal-union parameter, and `data.Stats[stat] += …` are exactly the shapes strict Luau rejects
when the types have drifted, and the annotation on `local data: Profile = profile.Data` is what forces
the check at all — `profile` is `any`, so without it every field access would pass vacuously.

#### Step 3.3: The shutdown registry

**File:** `src/server/ShutdownFlush.luau`
**Verify:** `npm run lint`

A leaf module with `register(name, fn)` and `flushAll()`. Requires only `Config`, so it cannot close a
cycle with any service.

**Why this exists rather than a direct call or a BindableEvent** — both alternatives were considered and
both are wrong, for different reasons:

- **`RoundService` requiring `ProgressionService`** closes a require cycle. Step 4.2 has
  ProgressionService subscribe to `RoundService.PhaseChanged`, which is how all seven other subscribing
  services do it, so the reverse edge would complete a loop. A require cycle errors at load, is
  swallowed into one `warn` by `init.server.luau:74-78`, and leaves the server in IDLE forever looking
  exactly like "nobody has joined yet". `RoundService`'s own header warns about this in the same words.
- **A `BindableEvent` fired from `BindToClose`** is worse, because it *looks* right. `Fire` resumes each
  handler on its own thread and returns as soon as one yields — and `EndSession()` yields on a DataStore
  write. `BindToClose` would return, Roblox would kill the process, and the saves would be half-written.
  This is a silent data-loss bug that no gate in this repo can see.

A plain function registry called synchronously on the `BindToClose` thread is the shape that actually
waits. `references/init.server-review.luau` carries the two facts this rests on: the loader walks
`SERVICE_ORDER` inside `script.Services` only, so a module beside that folder is never `Init`ed; and a
require cycle lands in a single `warn` and is swallowed.

```diff
+--!strict
+--[[
+	ShutdownFlush — the one place work registers itself to run before the server dies. (C31, §6.4)
+
+	§6.4's fifth edge case: "Server shutdown → `game:BindToClose()` must flush all player data."
+	`RoundService` owns the single `BindToClose` binding (see its `onServerClosing`), and this module
+	is how anything else gets onto that path WITHOUT RoundService requiring it — which would close a
+	require cycle, because the services that need flushing also subscribe to `PhaseChanged`.
+
+	IT IS NOT A BindableEvent, AND THAT IS THE WHOLE POINT. `BindableEvent:Fire` resumes each handler
+	on its own thread and returns the moment one yields. `Profile:EndSession()` yields on a DataStore
+	write. Firing an event here would let `BindToClose` return while the writes were still in flight,
+	Roblox would kill the process, and player data would be lost — silently, and only under shutdown,
+	which is the hardest condition to reproduce. These callbacks are CALLED, in order, on the closing
+	thread, where a yield is exactly what Roblox waits for.
+
+	NOT A SERVICE. It lives beside `Services/` rather than inside it precisely so `init.server.luau`'s
+	loader, which walks `SERVICE_ORDER` inside that folder, never tries to `Init`/`Start` it.
+]]
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
+
+local ShutdownFlush = {}
+
+type Handler = {
+	Name: string,
+	Flush: () -> (),
+}
+
+local handlers: { Handler } = {}
+
+--[[
+	Registration happens in a service's `Start()`. Order is registration order, and callers should not
+	depend on it: if two flushes must be sequenced, that is one flush with two steps inside it.
+]]
+function ShutdownFlush.register(name: string, flush: () -> ())
+	table.insert(handlers, { Name = name, Flush = flush })
+end
+
+--[[
+	Roblox allows roughly 30 seconds inside `BindToClose` and then kills the process mid-write, so the
+	budget is checked BETWEEN handlers. It cannot interrupt one that is already running — nothing can,
+	short of abandoning a DataStore call in flight — but it stops a stuck first handler from consuming
+	the window that the rest needed. `Config.Profile.ShutdownFlushBudget` is pinned below 30 in
+	`tests/config.test.luau`.
+]]
+function ShutdownFlush.flushAll()
+	local deadline = os.clock() + Config.Profile.ShutdownFlushBudget
+
+	for _, handler in handlers do
+		if os.clock() > deadline then
+			warn(`[ShutdownFlush] budget exhausted before {handler.Name} ran`)
+			continue
+		end
+
+		-- `:: any` because `pcall` over a `() -> ()` is typed as returning only the boolean, so
+		-- binding `err` is an arity error under --!strict. Same bite as `init.server.luau:93-95`.
+		local ok, err = pcall(handler.Flush :: any)
+
+		if not ok then
+			warn(`[ShutdownFlush] {handler.Name} errored: {err}`)
+		end
+	end
+end
+
+return ShutdownFlush
```

**`npm run lint` is the honest gate here.** selene over `src` catches an undefined global, an unused
local or a shadowed name in a new module — real failures, and the ones this file could plausibly have.
It does not prove the flush works; that is Step 4.4's shutdown case, and this plan does not pretend
otherwise.

#### Step 3.4: Put the flush on `BindToClose` without RoundService reaching across

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run verify`

`onServerClosing` calls `ShutdownFlush.flushAll()`; ProgressionService registers itself in `Start()`.

C01 left this hook empty on purpose — `RoundService.luau:1199-1207` says "it exists NOW so that there is
exactly one flush point when there is something to flush, rather than three services each binding their
own and racing". C31 is the chunk that fills it, and it fills it **without naming `ProgressionService`
in `RoundService`**, so the dependency edge points the way every other edge in this repo points.

In `RoundService.luau`, alongside the existing requires:

```diff
 local RoleService = require(script.Parent.RoleService)
+-- A LEAF. It requires nothing but Config, so it cannot participate in a require cycle — which is the
+-- reason the flush goes through it instead of this service requiring ProgressionService directly.
+local ShutdownFlush = require(script.Parent.Parent.ShutdownFlush)
 local BodyTransitions = require(Shared.pure.BodyTransitions)
```

and in `onServerClosing`:

```diff
 local function onServerClosing()
 	-- Spec §6.4: a shutdown must flush player data before the process dies, and Roblox gives you a
-	-- short window to do it. Nothing owns player data yet — ProfileStore lands at C31 — so this is
-	-- deliberately empty. It exists NOW so that there is exactly one flush point when there is
-	-- something to flush, rather than three services each binding their own and racing.
-	-- TODO(C31): flush every loaded profile here, and only here.
+	-- short window to do it. This is still the ONLY `BindToClose` in the game; C31 filled it by way
+	-- of a registry rather than by this service learning what a profile is. Anything else needing to
+	-- run before the process dies calls `ShutdownFlush.register` in its own `Start()`.
+	--
+	-- SYNCHRONOUS AND YIELDING. `flushAll` calls its handlers on this thread; a DataStore write inside
+	-- one is exactly the yield Roblox is waiting on here.
+	ShutdownFlush.flushAll()
+
 	if Config.Debug.VerboseLogging then
-		print("[RoundService] Server closing — nothing to flush yet.")
+		print("[RoundService] Server closing — flush complete.")
 	end
 end
```

and in `ProgressionService.Start()`, at the top, before the player connections:

```diff
 function ProgressionService.Start()
+	--[[
+		§6.6's third rule: save on meaningful change, ON LEAVE, and on `BindToClose`. `PlayerRemoving`
+		covers the second; this covers the third. Registered FIRST, before any player can be loaded,
+		so a server that dies during startup still flushes whatever it managed to load.
+	]]
+	ShutdownFlush.register("Progression", ProgressionService.FlushAll)
+
 	Players.PlayerAdded:Connect(function(player)
 		task.spawn(startSession, player)
 	end)
```

**`npm run verify` closes this phase** because this is the first point at which the whole thing hangs
together: the full gate covers the new service and the new leaf module under `analyze`, `selene`,
StyLua, all five repo checks, every Lune suite including Phase 1's, and the harness self-tests. It is
also the moment a require cycle would show up as a load-order problem the analyzer can see.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — the profile is a new store of role history, and it stays server-side.**
  `Stats.AswangRounds` / `AswangWins` accumulate how often a player drew the role. Nothing in this phase
  sends them anywhere, creates a `leaderstats` folder, or sets an attribute. Worth an `exploit-auditor`
  pass on the diff regardless: `src/server/**` is the 🔒 surface and `review-gate.mjs` will name it.
- **Player leaving mid-round — §6.4's five cases, mapped.** *(a)* The **Aswang leaves mid-round**: the
  round aborts, and `PlayerRemoving` ends their session normally; nothing about the profile is
  role-conditional, so there is no path where the round outcome changes what is written. *(b)* **Leaving
  during a load** is the case that bites — handled twice, by the `Cancel` callback while waiting on the
  lock and by the `player.Parent ~= Players` check after it, because a session started for an absent
  player is a lock nobody releases and the next server they join waits it out. *(c)* **Rejoining the same
  server before the lock releases** is ProfileStore's problem by design, and `OnSessionEnd` → `Kick` is
  the correct handling. *(d)* **Joining mid-round** and *(e)* **dropping below MinPlayers** touch the
  round, not the profile.
- **Phase ownership — untouched.** Nothing here calls `setPhase`. Step 4.2 *subscribes*.
- **Rate limiting** — vacuous, correctly: no `OnServerEvent` handler exists in either new file, so
  `check:ratelimit` has nothing to consult `AntiCheatService` about. That is a property to preserve, not
  a gap to fill.
- **A real risk this phase cannot close: `store` is `any`.** The vendored require gives the analyzer
  nothing, so `store:StartSessionAsync(...)` typechecks whatever it is spelled. A typo in a ProfileStore
  method name is a runtime error at the first join and is invisible to `npm run verify`. This is the
  strongest argument for Step 4.4's playtest being mandatory rather than nice to have, and it is why
  Step 3.1 annotates every value crossing back out of ProfileStore.
- **Strict Luau** — three spots: `pcall(handler.Flush :: any)` (the documented arity bite),
  `local data: Profile = profile.Data` (without it the `any` swallows every field check), and
  `StatName` declared locally as a literal union.

---

### Phase 4: Make persistence observable, then observe it

#### Step 4.1: Make `DataStoreState` legible

**File:** `src/server/Services/ProgressionService.luau`
**Verify:** `npm run verify:fast`

Log the state at `Start()` and warn loudly when it is not `"Access"`, so a mock-storage session is never
mistaken for a persistence bug.

**This step exists because of a specific, likely, and very expensive confusion.** DataStore access in
Studio needs *Enable Studio Access to API Services* **and** a published place. With either missing,
ProfileStore does not error — it falls back to mock storage and everything works, right up until the
data is gone on the next Play. A playtester would report "rejoin loses XP", the obvious reading is a
bug in the flush, and the actual cause is a checkbox. Naming the state out loud costs six lines.

```diff
 function ProgressionService.Start()
 	ShutdownFlush.register("Progression", ProgressionService.FlushAll)
 
+	--[[
+		`DataStoreState` is `"NotReady" | "NoInternet" | "NoAccess" | "Access"`, and data persists ONLY
+		on `"Access"`. Anything else means ProfileStore is quietly using mock storage — which behaves
+		perfectly within one session and loses everything between them.
+
+		This is a `warn`, not an `error`. A local Studio session without API access is a legitimate way
+		to test everything except persistence, and refusing to start would make the rest of the game
+		untestable to fix a problem that is not a code problem.
+	]]
+	task.spawn(function()
+		if ProfileStore.DataStoreState ~= "Access" then
+			warn(
+				`[Progression] DataStoreState is "{ProfileStore.DataStoreState}" — NOTHING WILL `
+					.. `PERSIST. In Studio: Game Settings > Security > Enable Studio Access to API `
+					.. `Services, and the place must be published.`
+			)
+		elseif Config.Debug.VerboseLogging then
+			print("[Progression] DataStore access confirmed — profiles will persist.")
+		end
+	end)
+
 	Players.PlayerAdded:Connect(function(player)
```

**`task.spawn` because the state may still be `"NotReady"`** at `Start()` — ProfileStore determines it
with its own request. Reading it on the bootstrap thread would report `"NotReady"` on a healthy server
and produce a false alarm every launch, which is how a warning gets ignored. Deferring one frame is the
minimum; if it still reads `"NotReady"` in practice, poll it behind `Config.Profile.SessionStartRetryDelay`
rather than adding a new constant. Flagged in Follow Ups as unconfirmed behaviour.

#### Step 4.2: One server-computed award at ENDING, so there is something to persist

**File:** `src/server/Services/ProgressionService.luau`
**Verify:** `npm run verify`

Subscribe to `RoundService.PhaseChanged`; on ENDING, increment `Stats.Rounds` and award
`Config.Economy.XPPerRound`. Deliberately flat — C32 replaces the policy, not the plumbing.

**Why C31 awards anything at all, when C32 owns XP.** The chunk's own Verify line is "playtester: earn
XP, leave, rejoin, XP present". Persistence is not observable without something being persisted, so C31
ships **one** award: a flat per-round grant to every player the round dealt in. C32 replaces the *policy*
— §4.8's win bonus, the survivor escape bonus, the per-role split — and touches nothing else, because
the write path, the save point and the subscription are already here. This overlap is deliberate and
minimal; it is recorded in Follow Ups so C32 knows exactly what to replace.

```diff
+local RoundService = require(script.Parent.RoundService)
```

```diff
+--[[
+	SUBSCRIBE, NEVER SET. `RoundService` owns the phase (§6.4) and this service is one of eight that
+	listen. The edge points that way for a second reason too: it is why the shutdown flush goes through
+	`ShutdownFlush` rather than RoundService calling into here — the reverse require would close a cycle.
+]]
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase ~= Enums.RoundPhase.Ending then
+		return
+	end
+
+	--[[
+		A FLAT AWARD, AND C32 REPLACES IT. §4.8's real table — win bonus, survivor escape bonus, the
+		Aswang's own split — is C32's work and belongs in a pure `XPCurve`-shaped module where it can
+		be tested. What C31 owns is that the number reaches the profile and survives a rejoin.
+
+		LOBBY IS THE EXCLUSION, not "alive" — someone who died in the third minute played the round and
+		is a GHOST at ENDING. A SPECTATOR joined after the draw and did not.
+	]]
+	for _, player in Players:GetPlayers() do
+		local state = RoundService.GetPlayerState(player)
+
+		if state == Enums.PlayerState.Lobby or state == Enums.PlayerState.Spectator then
+			continue
+		end
+
+		ProgressionService.BumpStat(player, "Rounds", 1)
+		ProgressionService.Award(player, Config.Economy.XPPerRound, Config.Economy.CoinsPerRound, "round")
+	end
+end
```

wired in `Start()`, after the player connections:

```diff
 	for _, player in Players:GetPlayers() do
 		if sessions[player.UserId] == nil then
 			task.spawn(startSession, player)
 		end
 	end
+
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
 end
```

**Two strict-Luau requirements this step introduces**, both of which `npm run verify` will catch:

- `Enums.RoundPhase.Ending` and `Enums.PlayerState.Lobby` infer as plain `string` without a
  `:: Types.RoundPhase` cast — but here they are only ever **compared** with `==`, never passed or
  assigned, so no cast is needed. Adding one anyway is harmless; leaving one out where a value is
  *passed* is what fails. Add `local Enums = require(Shared.Enums)` and `local Types = require(Shared.Types)`
  to the requires.
- `onPhaseChanged` is declared **above** `ProgressionService.Start` but references
  `ProgressionService.BumpStat` and `.Award`, which are defined earlier in the file. Keep that order.

**`npm run verify` gates this step** rather than `analyze` alone, because the award reads
`Config.Economy.*` and a literal slipped in here is exactly what `check:config` is for — and because
this is the last code step, so the tree must be green before a human is asked to do anything in Studio.

#### Step 4.3: Enable Studio API services and publish the place

**File:** Studio — the published place file (not in Git)

Two UI actions no agent can drive. This step has no `**Verify:**` line on purpose — `verify-plan.mjs`
reports it as `unverifiable` and `next-phase.mjs` marks the phase `needs-human`, which is the accurate
answer. A `grep` that always passes would be worse than admitting a person is needed.

**What the human does, once:**

1. **Publish the place.** File → Publish to Roblox. DataStore keys are scoped to a published universe;
   an unpublished place has nowhere to write.
2. **Enable API access.** Home → Game Settings → Security → **Enable Studio Access to API Services** → on
   → Save.
3. **Confirm it took.** Press Play and read the output. Step 4.1's line must say
   `DataStore access confirmed`, not `DataStoreState is "NoAccess"`. If it still says `NoAccess`,
   Studio needs restarting after the setting change.

**Until step 2 is done, every persistence result in this plan is meaningless** — the code runs, the
profile loads, the XP awards, and mock storage throws it all away between sessions. That is the single
most likely way this chunk gets a false red or a false green, which is why it is a numbered step rather
than a footnote.

**Also for the human, before launching the playtester** (per `.claude/agents/playtester.md`): set
`Config.Round.Intermission/Duration/EndScreen` to `8/20/6` plus `Debug.SoloTesting` and
`Debug.VerboseLogging`, because a round cycle at committed values is 461s and Step 4.4 needs several.
Revert all five afterwards and confirm with `git diff src/shared/Config.luau` — `guard-commit.mjs` runs
`check:debug` and will refuse the commit otherwise. The playtester cannot edit `Config.luau` itself and
will correctly refuse to try.

#### Step 4.4: The rejoin evidence

**File:** `.claude/plans/feature-c31-profilestore-data-model-plan/artifacts/rejoin-evidence.md`
**Verify:** `test -f .claude/plans/feature-c31-profilestore-data-model-plan/artifacts/rejoin-evidence.md`

The playtester's protocol: earn, leave, rejoin, read back — plus the shutdown case. The chunk's Done
condition is "data survives rejoin **and a server shutdown**", which is two tests, and the second one is
the one people skip.

**This is the only step that proves the chunk works.** Everything before it proves shape: `analyze`
cannot see past `store: any`, and Lune cannot see a DataStore at all. Brief the playtester tightly —
name the files, the phase, and the questions, per CLAUDE.md's scoping rule:

> Verify **Phase 4 only** of `.claude/plans/feature-c31-profilestore-data-model-plan/` — load it with
> `npm run plan:phase -- feature-c31-profilestore-data-model-plan 4`. Answer, with evidence:
> (1) does the output say `DataStore access confirmed`; (2) after one round, does XP go up; (3) after
> leaving and rejoining, is the XP still there; (4) after stopping the server *without* leaving first
> and starting it again, is the XP still there; (5) does a second Play session start from the saved
> values rather than from zero.

**Reading a profile back without a remote.** C31 sends nothing to the client, so there is no UI to read.
The playtester reads server state through `execute_luau`, and there is a trap worth stating: it **cannot
read a live service's in-memory state** — a fresh `require` gets a different module instance. Read the
DataStore, not the service:

```luau
-- In Studio, server context, with API access ON.
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("PlayerProfile")
local ok, value = pcall(function()
	return store:GetAsync("Player_<UserId>")
end)

print(ok, value)
```

**Expect the shape ProfileStore writes, not our table directly** — it wraps `Data` alongside its own
session metadata. Read the returned table rather than assuming the field name; the assertion is that the
XP is present and non-zero, not that it sits at a particular key.

**The evidence file** goes in `artifacts/` and is cited by `verification.md`. `goal-check.mjs` will not
report DONE until `verification.md` cites a file that actually exists in that directory, so a screenshot
of the console showing the XP before leaving and after rejoining is the deliverable, not a summary of it.

**The shutdown case has a specific failure signature worth watching for:** if `flushAll` were a
`BindableEvent` (see Step 3.3), stopping the server would appear to work and the data would be a round
behind. So test (4) by *stopping the server*, not by leaving — leaving exercises `PlayerRemoving`, which
is a different code path with a different bug.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — does anything added here put a role, a UserId, or a derived hint on a path a
  second client can read? Attributes and CollectionService tags both replicate; there is no private one.
- **Remote direction** — declared in the right list, fired from the right side, listened to on the other.
- **Rate limiting** — every `OnServerEvent` handler consults `AntiCheatService` before doing work.
- **Magic numbers** — every tunable in `Config.luau`, read rather than repeated.
- **Phase ownership** — nothing outside `RoundService` calls `setPhase`.
- **Player leaving mid-round** — the spec (§6.4) lists five edge cases that will bite; which apply here?
- **Strict Luau** — enum fields need their literal type; `pcall` over a `() -> ()` returns one value.
- **Mobile budget** — new lights, particles or per-frame work counted against §5's limits.
- **Scope** — nothing from §3's OUT list crept in.

**Issues identified:**

- **Secret leakage — the award loop reads round state, and must not read the ROLE.** `onPhaseChanged`
  calls `GetPlayerState`, never `GetAswangUserId`. That is a line worth holding: the moment the award is
  role-conditional, the XP number itself becomes a derived hint — a player who compares their end-screen
  total against a friend's learns something the round never told them. C32 will want a per-role split
  for balance reasons, and that is the point at which it must be checked that nothing the client can see
  differs by role. Raised in Follow Ups.
- **Phase ownership — subscribed, never set.** `RoundService.PhaseChanged.Event:Connect` and nothing
  else; no `setPhase`, no `EndRound`.
- **Player leaving mid-round — the award races the leave, and loses gracefully.** A player who quits
  during ENDING may have had `PlayerRemoving` fire before the award loop reaches them; `Award` returns
  `false` for a missing session and nothing is written. That is correct behaviour and not a bug to fix:
  the alternative is holding a session open for an absent player, which is a lock the next server waits
  on. Worth saying out loud so it is not "fixed" later.
- **Magic numbers** — `Config.Economy.XPPerRound` and `CoinsPerRound` already exist
  (`Config.luau:434-438`); this step **reads** them and adds none.
- **Mobile budget** — none. One loop over at most eight players, once per round, on the server.
- **Scope** — C32 (XP, levels, coins) and C33 (daily streak) are the next chunks and are explicitly NOT
  in this plan. The flat award in 4.2 is the single deliberate overlap and is recorded below.
- **The unverifiable step is real, not a gap.** Step 4.3 has no check because two Studio UI toggles have
  no command. `verify-plan` reporting it `unverifiable` is the plan working as intended.

---

## 3. Related Files

| File | Role in this plan | Reference review |
| --- | --- | --- |
| `src/server/Services/ProgressionService.luau` | the stub C31 fills; owns the profile | `ProgressionService-review.luau` |
| `src/server/Services/RoundService.luau` | holds the only `BindToClose`; the phase it broadcasts | `RoundService-review.luau` |
| `src/server/init.server.luau` | Init/Start bootstrap and `SERVICE_ORDER`; swallows a require cycle | `init.server-review.luau` |
| `src/shared/Types.luau` | `PlayerProfile`, missing §6.6's `Purchases` | `Types-review.luau` |
| `src/shared/Config.luau` | `Economy` exists; `Profile` is added | `Config-review.luau` |
| `src/shared/pure/RejoinResolve.luau` | the OTHER rejoin concern — read so this plan does not contradict it | `RejoinResolve-review.luau` |
| `tests/rejoin-resolve.test.luau` | the suite conventions Step 1.3 follows | `rejoin-resolve.test-review.luau` |
| `default.project.json` | where `vendor/` gets mapped | `default.project-review.luau` |
| `.claude/scripts/check-analyze.mjs` | proves analyze is scoped to `src`; `--update` refuses agents | `check-analyze-review.luau` |
| `.claude/scripts/check-config.mjs` | the `GOVERNED` regex the vendoring decision rests on | `check-config-review.luau` |
| `package.json` | `selene src`, `stylua src tests` — the other two scopes | `package-review.luau` |

**Read but not reviewed:** `docs/MVP-SPEC.md` §6.1, §6.4, §6.5, §6.6; `docs/BUILD-PLAN.md:658-673` and
`:947`; `CLAUDE.md`; `.claude/lessons/pure-module-unions-widen-in-lists.md`;
`.claude/scripts/check-scope.mjs` (OUT list checked for collisions — none);
`.claude/scripts/check-ratelimit.mjs`, `check-testcount.mjs`, `run-luau-tests.mjs`,
`lib/luau-source.mjs` (`listLuau`'s default root); `selene.toml`; `stylua.toml`; `.luaurc`.

**Not read, and deliberately:** `src/client/**`. C31 adds nothing a client can see, and a plan that
needed to read the controllers would be a plan that had already broken that promise.

## 4. Follow Ups

### Questions / Clarifications

1. **Can `Profile.Data` be reassigned, or must it be mutated in place?** Step 3.1 copies key-by-key with
   `copyInto` rather than writing `profile.Data = result.Profile`, because I could not confirm from the
   API surface whether ProfileStore captures the table identity at session start. Copying is safe under
   both answers, so this is a correctness question about *style*, not about data loss. Resolve it by
   reading the vendored source at Step 3.1 and simplify if reassignment is supported.
2. **Does `ProfileStore.DataStoreState` read `"NotReady"` at `Start()`?** Step 4.1 defers the check with
   `task.spawn` on the assumption that it does. If a healthy server still reports `"NotReady"` one frame
   in, the warning fires every launch and gets ignored — poll it instead, behind the existing
   `Config.Profile.SessionStartRetryDelay`, and do not add a constant for it. **Unconfirmed Roblox/
   third-party behaviour; the playtester answers it in Step 4.4.**
3. **`ProfileStore.SetConstant` is not used.** It would let us tune the internal autosave period, but its
   `ConstantName` values live inside the vendored file and would need re-verifying on every upgrade. If
   playtesting shows saves are too sparse, that is the knob — and it should arrive with a `Config` entry
   and a note in `vendor/README.md`, not as a bare call.
4. **C32 must decide whether a per-role XP split is a leak.** The flat award in Step 4.2 is deliberately
   role-blind. §4.8's real award table is not, and the moment the number differs by role, any client that
   can see its own total can reason about a round it just played. That is a question for `exploit-auditor`
   at C32, not a problem to solve here — but it should not be discovered there for the first time.
5. **`Config.Profile.StoreName` carries no version suffix, on purpose.** Changing it orphans every
   existing player. If a future schema change is ever thought to need a new store, the answer is almost
   certainly a migration step in `ProfileMigration` instead — that module exists precisely so the store
   name never has to move.
6. **`vendor/` is a new tracked directory.** Confirm it is not caught by `.gitignore` before committing;
   a vendored dependency inside an ignored path fails only on a fresh clone.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 2 | `check:scope` does not see `vendor/` — a vendored library is outside the scope alarm | Low | Accepted; right trade for one storage library with one call site |
| 3 | `store` and `profile` are `any` — a mistyped ProfileStore method is invisible to `npm run verify` | Medium | Mitigated: one call site, every value re-annotated on the way out, Step 4.4 mandatory |
| 3 | A `BindableEvent` shutdown flush would lose data silently; no gate in this repo can detect it | High | Closed by design — `ShutdownFlush` is a synchronous registry, and Step 3.3 says why |
| 3 | `ShutdownFlushBudget` cannot interrupt a handler already running, only skip later ones | Low | Accepted; nothing can abandon a DataStore call in flight |
| 4 | C31 ships one flat XP award, which is C32's territory | Low | Deliberate: the chunk's own Verify line requires observable earning. C32 replaces the policy, not the plumbing |
| 4 | Persistence is unprovable without a published place and API access — a human gate | Medium | Step 4.3, with no `**Verify:**` line, so the plan reports `needs-human` honestly |
| 4 | `execute_luau` cannot read a live service's in-memory state | Low | Step 4.4 reads the DataStore directly instead |
