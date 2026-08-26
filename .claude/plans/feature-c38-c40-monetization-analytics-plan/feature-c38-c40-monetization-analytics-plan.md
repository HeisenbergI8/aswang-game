# Plan: C38 MonetizationService + C40 Analytics

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M10 (C38) and M11 (C40), per `docs/BUILD-PLAN.md:809-821` and `:833-847`
- **Description:** Implement `MonetizationService` — an idempotent `ProcessReceipt`, a gamepass
  ownership cache per `Profile.Purchases.GamepassCacheUTC`, and an end-screen-only shop surface — and
  `AnalyticsService` — the fifteen Appendix B events behind one typed server-side emitter. Both
  services are C01-era ~20-line stubs today (`MonetizationService.luau:1-20`,
  `AnalyticsService.luau:1-19`); nothing is implemented.
- **Date:** 2026-08-20
- **What the client is told:** **Nothing new about any role, and no new field on any existing
  payload.** One new DOWN remote (`ShopOffer`) is added, fired per-player at ENDING, carrying only
  `{ Key, Price, Kind }` triples drawn from `Config.Monetization.Catalogue` plus that player's own
  gamepass-ownership booleans. Analytics adds **no** client-visible surface at all: the emitter's only
  egress is Roblox's own `AnalyticsService`, and Phase 3 adds a check-secrecy rule that makes that
  structural rather than conventional.

### 1.1 Scope

**In:** C38 and C40 only. **Out, deliberately:** C35 (gamepass *benefits* — VIP aura, 2x XP) and C39
(group join reward) are being implemented in parallel and this plan must not touch them; C36 and C37
are human-only Creator Hub work. Where this plan needs something C35 will own, it stops at the
ownership query and says so.

### 1.2 THE BINDING CONSTRAINT — C37 HAS NOT BEEN DONE

**There are no real gamepass or developer-product IDs, and there will be none when this is
implemented.** Every id in `Config.Monetization` is `0`, exactly as `Config.Badges` (`Config.luau:738-746`)
and `Config.Community.GroupId` (`Config.luau:730`) already sit at `0`. Every call site guards on
`id ~= 0` and **no-ops rather than erroring**.

The consequence has to be stated once, loudly, because it will otherwise be reported as a bug or —
worse — as a pass:

> **With every id at 0, the end-screen shop renders an EMPTY offer list, `ProcessReceipt` is never
> invoked by Roblox, and `UserOwnsGamePassAsync` is never called. That is the correct behaviour of a
> correct implementation. A playtester who sees no shop has not found a defect.**

Each phase below closes with an explicit **Cannot be observed until C37** list. Nothing on those lists
may be reported as verified.

### 1.3 The four questions, answered up front

These four answers are load-bearing for phases that are read on their own, so they are stated here in
the preamble (which `npm run plan:phase -- <plan> 1` serves alongside Phase 1) and restated in the
phase that depends on each.

#### Q1 — `ProcessReceipt` idempotency, and where the receipt id lives

**The receipt id lives inside the profile**, in a new bounded ring `Profile.Purchases.Receipts:
{string}`. Not in a side DataStore, and the reason is not convenience:

1. ProfileStore session-locks the profile, so this server is the only writer. A second DataStore would
   be a second write with no shared transaction, and a grant that landed while its receipt record did
   not is precisely the double-grant this chunk exists to prevent.
2. **`Profile.LastSavedData` is the only durability oracle available**, and it can only confirm data
   that is *inside the profile*. See the finding below.

**THE FINDING THAT SHAPES THIS PHASE — `Profile:Save()` DOES NOT YIELD AND DOES NOT REPORT SUCCESS.**
Read at `vendor/ProfileStore.luau:1172-1190`: after the active/view-mode guards it ends in
`task.spawn(SaveProfileAsync, self)` and returns. `ProgressionService.saveNow`
(`ProgressionService.luau:317-323`) therefore returns **before anything is durable**. The obvious
implementation of "grant, save, return `PurchaseGranted`" returns `PurchaseGranted` for a write that
has not happened and may never happen.

The durability signal is `Profile.OnAfterSave`, which fires with `Profile.LastSavedData`
(`vendor/ProfileStore.luau:877` sets `LastSavedData = loaded_data.Data`, i.e. what the DataStore
returned from the successful `UpdateAsync`; `:924` fires the signal). The failure branch at `:926`
retries with backoff instead of firing. So `OnAfterSave` fires **only** on a durable write.

The sequence is therefore:

1. `Receipts.decide` (pure) says `GRANT`, `DUPLICATE` or `UNAVAILABLE`.
2. On `GRANT`: mutate the profile **once** — apply the reward *and* append the receipt id, in the same
   table, in the same tick.
3. `profile:Save()`, then wait on `OnAfterSave` until `LastSavedData.Purchases.Receipts` contains this
   receipt id, bounded by `Config.Monetization.ReceiptDurabilityTimeout`.
4. Confirmed → `Enum.ProductPurchaseDecision.PurchaseGranted`. Not confirmed → `NotProcessedYet`.

**A receipt replayed after a mid-transaction rejoin grants exactly once, in both directions:**

| What happened | On re-delivery | Outcome |
| --- | --- | --- |
| Server died before the write landed | ring has no id, profile has no reward | `GRANT` → granted once |
| Write landed, server died before returning | ring has the id | `DUPLICATE` → `PurchaseGranted`, no second grant |

**When the profile is read-only at the moment the receipt arrives** — the C31 latch,
`ProgressionService.IsReadOnly` (`ProgressionService.luau:365-372`), set when a profile came from a
schema this server does not understand — the answer is **`NotProcessedYet`**. Not "grant anyway": the
grant would be discarded unsaved and the player pays for nothing. Not "eat the purchase": returning
`PurchaseGranted` without granting is a refund request. `NotProcessedYet` is Roblox's own
"ask me again", and the next server the player lands on — or a later session on this one after the
schema catches up — grants it. The same answer covers a nil profile (DataStore outage, mid-load, or
the player already gone), which `ProgressionService.GetProfile`'s header calls "a normal answer, not
an error".

#### Q2 — `role_assigned (role)` and `player_killed`: where analytics is emitted from

The C02–C04 plan raised this twice — at
`.claude/plans/feature-c02-c04-anticheat-roles-transform-plan/feature-c02-c04-anticheat-roles-transform-plan.md:1149`
("a log that C40's analytics will later ship off-server") and again at `:2627` ("safe on a server
console and NOT safe as a C40 analytics event"). This plan is the chunk that has to answer it.

**Where events are emitted from:** the server, and only the server. Our `AnalyticsService.Emit` is a
**server module with no remote surface**, and its sole egress is Roblox's own built-in
`AnalyticsService`, confirmed from this repo's vendored definitions at `.luau-defs/globalTypes.d.luau:9229-9235`:

```
function LogCustomEvent(self, player: Player, eventName: string, value: number?, customFields: { [string]: any }?): nil
function LogFunnelStepEvent(self, player: Player, funnelName: string, funnelSessionId: string?, step: number?, stepName: string?, customFields: { [string]: any }?): nil
```

Those write to the Creator Hub dashboard. They are not remotes; there is no client subscriber, no
replicated container, no attribute and no tag. **`role_assigned (role)` going to Roblox's telemetry
backend is not a leak — it is the only place the role may go besides `RoleAssigned` and `RoundEnded`.**

**Proving no path reaches a client**, structurally rather than by inspection — Phase 3, Step 3.2 adds
**check-secrecy Rule 6**: `src/server/Services/AnalyticsService.luau` may not `require` `Remotes`, may
not contain `FireClient` / `FireAllClients` / `:Fire(`, and may not name `ReplicatedStorage`. The
emitter becomes a file that *cannot* reach a client without a diff to the check script, which is the
same asymmetry `REVEAL_ALLOWLIST` (`check-secrecy.mjs:70-73`) already buys for the two reveal remotes.

**How `check:secrecy` sees a call site today, stated plainly because it is the gap:** rules 0–4 scan
`Fire*` payloads, attribute names and tag names — *not general server code*
(`check-secrecy.mjs:169-183` says so of Rule 5's scope). A line reading
`RobloxAnalytics:LogCustomEvent(player, "role_assigned", nil, { role = role })` matches **no** existing
rule and passes `npm run verify` green. That is correct — it is not a leak — but it means
`check:secrecy` is not what protects this. **Rule 6 is.** Anyone reading Phase 3 in isolation needs
that sentence, so it is repeated inside the phase.

**`player_killed (secondsIntoRound, wasIsolated)` against Amendment A3** (`docs/MVP-SPEC.md:219-244`):
A3 removed the `PlayerKilled` *broadcast* and `ClientRoundSnapshot.AlivePlayerCount` because a
sub-second global death signal is the missing input to a positional attack that identifies the Aswang.
`PlayerKilled` survives as a **`FireClient` to the victim alone**.

Two rules follow, and they are the whole answer:

1. **The analytics emit is a separate statement from the remote fire, and it is logged against the
   VICTIM.** `LogCustomEvent`'s first argument is a `Player`; passing the killer would attribute a
   per-player event to the Aswang in the exported data. Pass the victim.
2. **`wasIsolated` is computed on the server and never crosses a remote.** It is a boolean about how
   many living survivors were within `Config.Monster.KillRange`-ish distance of the victim at the
   moment of the kill — a fact the server already has. It must not be added to the `PlayerKilled`
   payload "since we're computing it anyway": that payload goes to the victim, the victim is about to
   become a ghost, and a ghost is explicitly barred from revealing the Aswang (§4.7).

> **An analytics call site must not become the broadcast A3 removed.** Adding `:FireAllClients` beside
> an `Emit` is the exact regression, and it is easy because the two lines read alike.

#### Q3 — Where the pure, testable logic goes: `src/server/pure/`, all three modules

`src/server/pure/` already exists with ten modules (`RoleDraw`, `TaskWeight`, `TimingWindow`, …) and
`tests/` requires them by file path (`tests/fetch-carry.test.luau:16` → `require("../src/server/pure/FetchCarry")`),
because Lune resolves by path and cares nothing for Rojo. Nothing is lost by choosing it:
`check-config.mjs`'s `GOVERNED` regex is `src/(server|client)/`, so `src/server/pure/` is still
policed for magic numbers.

| Module | Placement | Why |
| --- | --- | --- |
| `Receipts.luau` | `src/server/pure/` | Anti-replay is a security decision. No client code path needs it, and `src/shared/pure/` is **requirable AND runnable by any client** (CLAUDE.md). Publishing the exact shape of the replay record buys a would-be exploiter a map of the guard for zero benefit to any legitimate client |
| `GamepassCache.luau` | `src/server/pure/` | Staleness is decided by the server alone. A client that could run it would learn only what `Config` already replicates, but there is no caller to justify the placement, and placement follows **who calls it** |
| `AnalyticsEvents.luau` | `src/server/pure/` | Holds the fifteen Appendix B names as a frozen table **and a literal union type**, so `analyze` rejects a typo'd event name at every call site. Server-only for the same reason: no client emits |

The contrast that makes the rule legible: `shared/pure/XPCurve` and `shared/pure/Cosmetics` are in
`Shared` because the **client legitimately runs them** — the level bar and the shop panel need them.
Nothing here has that property.

#### Q4 — What structurally enforces "shop on the end screen only" (§8.4)

§8.4: "Show the cosmetic shop **on the end screen** … never mid-round." Three mechanisms, in
decreasing strength:

1. **The client never touches `MarketplaceService`.** Every prompt is server-initiated:
   `MarketplaceService:PromptProductPurchase(player, productId, …)` and `PromptGamePassPurchase(player, gamePassId)`
   both take a `Player` and are called from `MonetizationService`
   (`.luau-defs/globalTypes.d.luau:14130`, `:14135`). The client sends a **string key** into
   `Config.Monetization.Catalogue` — never an id, never a price — the same absent-argument design
   `RequestBuyCosmetic` uses (`Remotes.luau`, C34's comment).
2. **The handler gates on the server-owned phase.** `RoundService.GetPhase()` (`RoundService.luau:89`)
   is server-only state that nothing outside `RoundService` sets (`RoundService.luau:9-12`). A
   `RequestPromptPurchase` arriving in `ACTIVE` is refused before any id is resolved.
3. **There is no client-side source for the offer list.** `ShopOffer` is fired from exactly one call
   site — `MonetizationService`'s `RoundService.PhaseChanged` subscription, on `ENDING`. A mid-round
   shop has no data to draw.

**The honest limit, stated rather than papered over:** `PromptGamePassPurchase` appears callable from a
LocalScript, so a modified client can open Roblox's own purchase UI whenever it likes. That costs the
player their own Robux, `ProcessReceipt` still grants exactly once, and nothing about the round
changes. §8.4 is a **conversion/placement rule for honest clients**, not a security boundary, and
mechanism 2 is what makes it structural for every client that has not been modified. This is recorded
in Follow Ups as an unverified API-security claim rather than asserted.

### 1.4 What must NOT be built here

`docs/MVP-SPEC.md` §8.3 is a hard line and `check:scope` does not cover it: **no extra salt, no extra
lives, no revives, no see-through-walls, no longer transform, and no "higher chance to be the
Aswang".** `Config.Monetization.Catalogue` carries cosmetics, identity and convenience only (§8.2).
Any entry whose effect touches a round is a rejected diff, not a tunable.

## 2. Comprehensive Plan by Phases

### Phase 1: The data contract and the three pure cores

Types, Config and three pure modules under `src/server/pure/`, each landing with a Lune test. Nothing
in this phase requires a DataModel, so all of it is verifiable from a terminal, and the game stays
runnable in Studio throughout because nothing existing changes behaviour.

#### Step 1.1: Add the `Config.Monetization` block with every product id zeroed

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

Catalogue of §8.2's five products keyed by string, each with `Id = 0`, a `Kind`, and a display price;
plus the cache TTL, the receipt-ring bound and the durability timeout. New invariants pinned in
`tests/config.test.luau` alongside its existing thirteen.

Insert after the `Community` block and before `Badges` (`Config.luau:729-746`), so the three
"IDs a human must fill in after Creator Hub work" blocks sit together.

```diff
 	Community = {
 		GroupId = 0, -- TODO(M10): set once the Roblox group exists
 		GroupJoinRewardCoins = 250,
 
 		-- C24, §9 item 3. A waiting player must never see a static screen.
 		LobbyTipSeconds = 7, -- how long each tip holds before the next
 	},
 
+	--[[
+		MONETIZATION (C38, §8). SOCIAL ACCESS · IDENTITY · CONVENIENCE — NEVER ADVANTAGE (§8.1).
+
+		EVERY `Id` HERE IS 0 AND MUST STAY 0 UNTIL A HUMAN DOES C37. That is not a placeholder to be
+		tidied away: C37 is Creator Hub work no agent can perform, and a guessed id is a live product
+		belonging to somebody else. Every read of these ids guards on `~= 0` and NO-OPS — the same
+		shape `Badges` below and `Community.GroupId` above already use.
+
+		WHAT MAY GO IN THIS TABLE is fixed by §8.3, and `check:scope` does NOT cover it: no extra
+		salt, no extra lives, no revives, no see-through-walls, no longer transform, and above all no
+		"higher chance to be the Aswang" — §8.3 calls that one out by name as the thing that "directly
+		takes the fun role from non-payers". An entry whose effect touches a round is a rejected diff,
+		not a number to tune.
+
+		`Price` is DISPLAY ONLY. Roblox owns the real price, the client is shown this one, and no
+		arithmetic anywhere reads it — a stale price here misprints a label and cannot mischarge.
+	]]
+	Monetization = {
+		--[[
+			§8.2's ladder. `Kind` decides which API a prompt goes through: "Gamepass" ->
+			`PromptGamePassPurchase`, "Product" -> `PromptProductPurchase`. The Private Server is
+			deliberately absent — Roblox sells it from its own UI and there is nothing for this
+			service to prompt — even though §8.2 calls it "your #1 earner".
+		]]
+		Catalogue = {
+			starter_pack = { Id = 0, Kind = "Gamepass", Price = 79 },
+			survivor_pack = { Id = 0, Kind = "Gamepass", Price = 249 },
+			vip = { Id = 0, Kind = "Gamepass", Price = 799 },
+			coins_small = { Id = 0, Kind = "Product", Price = 99, Coins = 500 },
+			coins_large = { Id = 0, Kind = "Product", Price = 399, Coins = 2400 },
+		},
+
+		--[[
+			HOW LONG A GAMEPASS OWNERSHIP ANSWER IS TRUSTED, in seconds.
+
+			`Types.PlayerProfile.Purchases.GamepassCacheUTC` is a CACHE STAMP, not an entitlement —
+			its own comment says ownership is never stored because "a cached owns-it is a value that
+			survives a refund". This number bounds how wrong that can get. Ten minutes is well under a
+			session and well over a round, so a player who buys mid-session sees it at the next round
+			boundary rather than on a rejoin.
+		]]
+		GamepassCacheSeconds = 600,
+
+		--[[
+			HOW MANY RECEIPT IDS THE PROFILE REMEMBERS — the anti-replay ring.
+
+			Bounded because an unbounded list eventually exceeds the DataStore value cap and takes the
+			whole profile down with it, silently, for the player who bought the most. 24 is far more
+			than the set of receipts Roblox can have in flight for one player at once, so the eviction
+			this bound implies is not reachable by a real purchase history — see
+			`server/pure/Receipts.luau`, which makes the eviction rule explicit rather than emergent.
+		]]
+		ReceiptHistory = 24,
+
+		--[[
+			HOW LONG `ProcessReceipt` WAITS FOR THE WRITE TO BE DURABLE before answering
+			`NotProcessedYet`.
+
+			`Profile:Save()` does not yield (`vendor/ProfileStore.luau:1172-1190` ends in a
+			`task.spawn`), so the grant is confirmed by watching `Profile.OnAfterSave` for the receipt
+			id to appear in `LastSavedData`. Generous on purpose: timing out is not a lost purchase —
+			Roblox re-delivers the receipt and the ring makes the replay a no-op — but it IS a player
+			staring at a purchase that has not landed, so the budget should cover a slow DataStore
+			rather than a fast one.
+		]]
+		ReceiptDurabilityTimeout = 10,
+	},
+
 	-- Award thresholds mirror the public funnel we can read back via the API.
 	Badges = {
```

And the invariants, appended to `tests/config.test.luau` before its `if failures > 0` tail. These pin
*relationships*, which is what that suite is for — a lone number is not an invariant.

```diff
+--[[
+	C38. Four relationships between Monetization's numbers, none of which has a symptom when it breaks.
+]]
+for key, entry in Config.Monetization.Catalogue do
+	check(
+		`catalogue entry {key} has an id awaiting C37`,
+		entry.Id == 0,
+		`{key}.Id = {entry.Id} — a real id must not be committed before C37 exists`
+	)
+
+	check(
+		`catalogue entry {key} is a gamepass or a product`,
+		entry.Kind == "Gamepass" or entry.Kind == "Product",
+		`{key}.Kind = {entry.Kind}`
+	)
+end
+
+--[[
+	THE RING MUST OUTLAST THE IN-FLIGHT SET. Roblox re-delivers unacknowledged receipts, so the ring
+	has to hold more ids than can plausibly be outstanding at once. Pinned against the shop's own size
+	rather than as a bare number: a catalogue that grows makes a short ring likelier to evict a live
+	receipt, and nothing about either number looks wrong on its own.
+]]
+local catalogueSize = 0
+for _ in Config.Monetization.Catalogue do
+	catalogueSize += 1
+end
+
+check(
+	"the receipt ring outlasts a full catalogue bought twice over",
+	Config.Monetization.ReceiptHistory >= catalogueSize * 2,
+	`ring {Config.Monetization.ReceiptHistory} vs catalogue {catalogueSize}`
+)
+
+--[[
+	THE DURABILITY WAIT MUST FIT INSIDE THE SHUTDOWN BUDGET. A receipt can arrive during
+	`BindToClose`, and `ShutdownFlush` gets `Profile.ShutdownFlushBudget` seconds before Roblox kills
+	the process mid-write. A durability wait longer than that budget is a wait the process does not
+	survive, and the purchase is answered by nobody.
+]]
+check(
+	"a receipt's durability wait fits inside the shutdown flush budget",
+	Config.Monetization.ReceiptDurabilityTimeout < Config.Profile.ShutdownFlushBudget,
+	`wait {Config.Monetization.ReceiptDurabilityTimeout}s vs budget {Config.Profile.ShutdownFlushBudget}s`
+)
+
+--[[
+	THE GAMEPASS CACHE MUST OUTLAST A ROUND AND NOT A SESSION. Shorter than a round and every player
+	costs a `UserOwnsGamePassAsync` call per round for an answer that almost never changes; longer
+	than a session and a refund is invisible until tomorrow.
+]]
+check(
+	"the gamepass cache outlives a whole round cycle",
+	Config.Monetization.GamepassCacheSeconds
+		> Config.Round.Duration + Config.Round.Intermission + Config.Round.EndScreen,
+	`cache {Config.Monetization.GamepassCacheSeconds}s vs one full cycle`
+)
```

#### Step 1.2: Add `src/server/pure/AnalyticsEvents.luau` — the fifteen names as a literal union

**File:** `src/server/pure/AnalyticsEvents.luau`
**Verify:** `lune run tests/analytics-events.test.luau`

The exact fifteen names from `docs/MVP-SPEC.md:694`, frozen, plus `export type Event` as their literal
union so `analyze` rejects a typo at every call site. The test pins the set exactly — count and
spelling — so a sixteenth event or a renamed one fails from a terminal.

**Why a pure module rather than `Enums.luau`:** `Enums.luau` requires `script.Parent.Types`, so Lune
cannot load it (`tests/README.md`, and `tests/anti-cheat-budgets.test.luau:8-10` explains the same
constraint for `Remotes`). Putting the names here makes "all fifteen, spelled correctly" a terminal
check instead of a hand copy. **Server-only, per Q3:** no client emits, so nothing gains from
`src/shared/pure/`.

```diff
+--!strict
+--[[
+	AnalyticsEvents — the fifteen event names from docs/MVP-SPEC.md Appendix B (`:694`), and nothing
+	else. (C40)
+
+	THE NAMES ARE A CONTRACT WITH A DASHBOARD, NOT AN IMPLEMENTATION DETAIL. Once an event has been
+	emitted under a name, that name is what the Creator Hub funnel is keyed on; renaming it later does
+	not rename the history, it starts a second series and silently halves both. So the set is frozen
+	here, pinned by `tests/analytics-events.test.luau`, and `Event` is a LITERAL UNION so a typo at a
+	call site is an analyze error rather than a metric that reads zero forever.
+
+	Zero is exactly what a typo looks like on a dashboard, and zero is also what "this never happens"
+	looks like. That ambiguity is the whole reason this file exists.
+
+	WHY server/pure AND NOT shared/pure: nothing on the client emits an analytics event, and
+	`src/shared/pure/` is requirable AND RUNNABLE by any client (CLAUDE.md). Placement follows who
+	calls it. `check:config` still governs this path — its GOVERNED regex is `src/(server|client)/`.
+
+	NO `script.Parent` REQUIRES (tests/README.md) — this module requires nothing at all.
+]]
+
+local AnalyticsEvents = {}
+
+--[[
+	The literal union. Every field below carries its `:: Event` cast for the reason CLAUDE.md gives
+	about `Enums.RoundPhase`: without it each field infers as plain `string` and fails to satisfy a
+	parameter typed as this union, which is how the scaffold shipped six analyze errors.
+]]
+export type Event =
+	"player_joined"
+	| "round_started"
+	| "role_assigned"
+	| "task_completed"
+	| "player_killed"
+	| "transform_witnessed"
+	| "salt_used"
+	| "round_ended"
+	| "player_left"
+	| "shop_opened"
+	| "purchase_completed"
+	| "daily_claimed"
+	| "trial_started"
+	| "trial_completed"
+	| "group_join_reward_claimed"
+
+AnalyticsEvents.Name = table.freeze({
+	PlayerJoined = "player_joined" :: Event,
+	RoundStarted = "round_started" :: Event,
+	RoleAssigned = "role_assigned" :: Event,
+	TaskCompleted = "task_completed" :: Event,
+	PlayerKilled = "player_killed" :: Event,
+	TransformWitnessed = "transform_witnessed" :: Event,
+	SaltUsed = "salt_used" :: Event,
+	RoundEnded = "round_ended" :: Event,
+	PlayerLeft = "player_left" :: Event,
+	ShopOpened = "shop_opened" :: Event,
+	PurchaseCompleted = "purchase_completed" :: Event,
+	DailyClaimed = "daily_claimed" :: Event,
+	TrialStarted = "trial_started" :: Event,
+	TrialCompleted = "trial_completed" :: Event,
+	GroupJoinRewardClaimed = "group_join_reward_claimed" :: Event,
+})
+
+--[[
+	THE FUNNEL (§9.5, and BUILD-PLAN C40's "the funnel that matters"):
+	joined -> reached an ACTIVE round -> completed a round -> returned on day 2.
+
+	A separate concept from the events above, because Roblox models it separately —
+	`LogFunnelStepEvent` takes a funnel name and a step INDEX, and the index is what orders the chart.
+	Steps are 1-based and contiguous; a gap renders as a step nobody reached.
+
+	§9.5's warning is the reason step 2 exists at all: if the joined -> ACTIVE rate is low, players are
+	bouncing off an empty lobby and every other retention number is lying to you.
+]]
+AnalyticsEvents.Funnel = table.freeze({
+	Name = "core_loop",
+	Steps = table.freeze({
+		Joined = 1,
+		ReachedActiveRound = 2,
+		CompletedRound = 3,
+		ReturnedDayTwo = 4,
+	}),
+})
+
+return AnalyticsEvents
```

The suite. It pins the set **exactly**, in both directions, against a hand-written literal list —
deriving the expected list from the module would make it agree with itself and prove nothing, which is
the same trap `tests/daily-streak.test.luau`'s header names about its timestamps.

```diff
+--!strict
+--[[
+	The fifteen Appendix B analytics event names (C40).
+
+	WHY THIS IS WORTH A SUITE. A wrong event name has no symptom. Nothing errors, `analyze` is happy
+	as long as the union agrees with itself, the call site runs, and the Creator Hub simply shows zero
+	for a series nobody is writing to — which is indistinguishable from an event that genuinely never
+	fires. By the time anyone notices, the history that would have been there does not exist and
+	cannot be backfilled.
+
+	THE EXPECTED LIST BELOW IS TYPED OUT BY HAND from docs/MVP-SPEC.md:694, not derived from the
+	module. A test that builds its expectation out of the thing under test passes on a rename.
+]]
+
+local AnalyticsEvents = require("../src/server/pure/AnalyticsEvents")
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
+-- Hand-copied from docs/MVP-SPEC.md:694. Order is the spec's; nothing depends on it, but a diff
+-- against the spec line should read as a diff.
+local EXPECTED = {
+	"player_joined",
+	"round_started",
+	"role_assigned",
+	"task_completed",
+	"player_killed",
+	"transform_witnessed",
+	"salt_used",
+	"round_ended",
+	"player_left",
+	"shop_opened",
+	"purchase_completed",
+	"daily_claimed",
+	"trial_started",
+	"trial_completed",
+	"group_join_reward_claimed",
+}
+
+local emitted: { [string]: boolean } = {}
+local count = 0
+
+for _, name in AnalyticsEvents.Name do
+	emitted[name] = true
+	count += 1
+end
+
+check("exactly fifteen events are declared", count == #EXPECTED, `{count} declared, {#EXPECTED} in Appendix B`)
+
+-- Direction 1: every spec name exists in the module.
+for _, name in EXPECTED do
+	check(`Appendix B's "{name}" is declared`, emitted[name] == true)
+end
+
+-- Direction 2: the module declares nothing the spec does not list. Without this a sixteenth event
+-- slips in and the count check above is the only thing standing in its way.
+local expectedSet: { [string]: boolean } = {}
+for _, name in EXPECTED do
+	expectedSet[name] = true
+end
+
+for _, name in AnalyticsEvents.Name do
+	check(`"{name}" appears in Appendix B`, expectedSet[name] == true, "not a spec event")
+end
+
+-- The funnel's steps must be 1-based and contiguous, or a chart renders a step nobody reached.
+local seen: { [number]: boolean } = {}
+local steps = 0
+
+for _, index in AnalyticsEvents.Funnel.Steps do
+	seen[index] = true
+	steps += 1
+end
+
+for index = 1, steps do
+	check(`funnel step {index} exists`, seen[index] == true, "funnel indices must be contiguous from 1")
+end
+
+if failures > 0 then
+	error(`{failures} analytics-event failure(s)`, 0)
+end
+
+print(`  PASS  analytics-events: {checked} assertions over {count} events`)
```

#### Step 1.3: Widen `Profile.Purchases` with the receipt ring, and migrate it

**File:** `src/shared/Types.luau`
**Verify:** `lune run tests/profile-migration.test.luau`

`Receipts: { string }` beside the existing `GamepassCacheUTC`, plus a **`SchemaVersion` bump to 3**
with its own `Applied` line. `ProfileMigration.template` and `reconcile` gain the field with a
bounded, sanitising reader.

> **Read `references/ProfileMigration-review.luau` before starting this step.** It is not attached to
> this phase automatically — the step's `**File:**` line names `Types.luau` — and it carries the
> version reasoning in full.

**THIS IS A v3 BUMP. `CURRENT_VERSION` IS 2 AND v2 IS ALREADY SPENT.** C35 consumed it for
`FirstSeenUTC` and `GroupRewardClaimed` (`ProfileMigration.luau:103`, `:325-333`), so this field
cannot ride along on v2 the way those two rode together. Every plan that adds a persisted field from
here forward opens its own version.

**Why bump at all, when `reconcile` already defaults absent fields.** It is a fair question — v1→v2's
own comment says that migration "IS ADDITIVE AND HAS NO STEP TO RUN", and this one is additive too.
The bump is not for the *reader*; it is for the **`version > CURRENT_VERSION` refusal**
(`ProfileMigration.luau:308-315`). That branch is what protects a player who lands on an older server
after playing on a newer one: it latches them read-only and touches nothing, so nothing is deleted.

Without a bump, a profile carrying granted receipts reads as v2 to a server that has never heard of
`Receipts`, `reconcile` drops the field, and the next autosave writes the deletion back. **The ring is
the one field in this profile where that is not a cosmetic loss: erasing it re-arms every receipt
Roblox has not yet retired, and the replay grants a second time.** That is precisely the double-grant
this plan exists to prevent, arriving through the data model instead of through the handler.

So the cost is understood and accepted: **during a staged deploy, a v3 player on a v2 server is
latched read-only, and `ApplyReceipt` answers `UNAVAILABLE` → `NotProcessedYet`.** The purchase is not
lost — Roblox re-delivers it on a v3 server. That is the read-only branch of Q1 working as designed,
and it is strictly better than the alternative, which is granting twice.

```diff
 ProfileMigration.CURRENT_VERSION = 3
```

```diff
+	--[[
+		v2->v3 IS ADDITIVE AND HAS NO STEP TO RUN, like v1->v2 above: `reconcile` defaults `Receipts`
+		to an empty ring, which is the correct answer for a player who has never had one.
+
+		THE BUMP IS NOT FOR THE READER, IT IS FOR THE REFUSAL. A v3 profile carrying granted receipt
+		ids, read by a v2 server, loses the ring to `reconcile` and the next autosave writes the
+		deletion back — which RE-ARMS every receipt Roblox has not yet retired and grants them a second
+		time. The `version > CURRENT_VERSION` branch above is what makes that impossible, and it only
+		fires if the version says so.
+	]]
+	if version < 3 then
+		table.insert(applied, "v2->v3 Purchases.Receipts added")
+	end
```

```diff
 	Purchases: {
 		GamepassCacheUTC: number,
+		--[[
+			C38. THE ANTI-REPLAY RING — the ids of the last `Config.Monetization.ReceiptHistory`
+			developer-product receipts this player's profile has already granted.
+
+			IN THE PROFILE, NOT IN A SIDE DATASTORE, and that is the design rather than the
+			convenient option. Two reasons, and the second is the one that is not obvious:
+
+			  1. ProfileStore session-locks this key, so one server is the only writer. A separate
+			     store would be a second write with no shared transaction, and a grant that landed
+			     while its receipt record did not is the double-grant this field exists to prevent.
+			  2. `Profile.LastSavedData` is the ONLY durability oracle ProfileStore offers, and it can
+			     only confirm data that is inside the profile. `Profile:Save()` does not yield
+			     (`vendor/ProfileStore.luau:1172-1190`), so "the grant is durable" is answered by
+			     watching for THIS id to appear in `LastSavedData`. Put the id anywhere else and the
+			     question becomes unanswerable.
+
+			BOUNDED, and the bound is a correctness statement rather than a tidiness one: an unbounded
+			list eventually exceeds the DataStore value cap and takes the whole profile down for the
+			player who bought the most.
+
+			NOT A PURCHASE HISTORY, and must never be read as one. It answers exactly one question —
+			"have I already granted this receipt" — and the oldest entries fall off. Anything that
+			wants to know what a player owns asks Roblox (gamepasses) or reads `Cosmetics.Owned`.
+		]]
+		Receipts: { string },
 	},
```

`ProfileMigration` gains the field in both places. The reader is bounded and sanitising for the same
reason `ownedFrom` is: a stored value is whatever a previous version of this code, or a corrupt write,
happened to leave there.

```diff
+--[[
+	C38. The receipt ring, read defensively out of a stored profile.
+
+	CAPPED ON THE WAY IN, exactly as `ownedFrom` caps the cosmetic inventory, and for the same reason
+	its comment gives: a write path that could exceed the cap produces a profile that silently loses
+	entries the next time it is loaded. Keeps the TAIL rather than the head — the newest ids are the
+	ones a re-delivery could still be about.
+]]
+local function receiptsFrom(stored: any, limit: number): { string }
+	if type(stored) ~= "table" then
+		return {}
+	end
+
+	local list = stored :: { any }
+	local out = {}
+	local first = math.max(1, #list - limit + 1)
+
+	for index = first, #list do
+		local id = list[index]
+
+		if type(id) == "string" and #id > 0 then
+			table.insert(out, id)
+		end
+	end
+
+	return out
+end
```

```diff
 		Purchases = {
-			GamepassCacheUTC = 0,
+			GamepassCacheUTC = 0,
+			Receipts = {},
 		},
```

```diff
 		Purchases = {
 			GamepassCacheUTC = num(purchases.GamepassCacheUTC, 0),
+			Receipts = receiptsFrom(purchases.Receipts, MAX_RECEIPTS),
 		},
```

`MAX_RECEIPTS` is declared beside `MAX_OWNED_COSMETICS` in the same file. **It is a duplicate of
`Config.Monetization.ReceiptHistory` and must be**: this is a `shared/pure/` module and CLAUDE.md
forbids it from requiring anything, so the number is re-declared locally with a `-- config-ok:` waiver
naming the constraint. `tests/config.test.luau` is where the two are pinned to agree — add that
assertion in Step 1.1's block if the implementer prefers, or accept the existing precedent that
`MAX_OWNED_COSMETICS` already sets.

#### Step 1.4: Add `src/server/pure/Receipts.luau` — the whole idempotency decision

**File:** `src/server/pure/Receipts.luau`
**Verify:** `lune run tests/receipts.test.luau`

`Receipts.decide(state, receiptId, options) -> Decision`, returning `GRANT` / `DUPLICATE` /
`UNAVAILABLE`, plus `Receipts.record` returning the new bounded ring with the oldest id evicted. Pure
over plain tables; the test covers replay, eviction, read-only, and a malformed receipt id.

**The decision this module owns, restated for a reader who has only this phase:** a receipt arrives,
possibly for the second time, possibly while the profile cannot be written. Three answers, and
choosing wrongly between the last two is the failure BUILD-PLAN calls "unrecoverable, and one is a
refund request" (`docs/BUILD-PLAN.md:811-813`).

```diff
+--!strict
+--[[
+	Receipts — the `ProcessReceipt` idempotency decision, as a pure function. (C38, §8)
+
+		decide(state, receiptId) -> Decision   -- grant, skip, or refuse to answer yet
+		record(ring, receiptId, limit) -> { string }
+
+	WHY THIS IS PURE AND TESTED RATHER THAN THREE LINES IN A SERVICE. BUILD-PLAN C38: "Getting this
+	wrong either double-grants or eats a real purchase; both are unrecoverable and one is a refund
+	request." Neither failure has a symptom on the day. A double grant looks like a generous game; an
+	eaten purchase looks like a player who is mistaken about what they bought. There is no log line
+	either way, and the DataStore no longer holds the evidence.
+
+	THE THREE ANSWERS, and the distinction between the last two is the whole module:
+
+	  GRANT       first time this receipt has been seen, and the profile can be written. Apply it.
+	  DUPLICATE   this receipt id is already in the ring. The grant already happened and is already
+	              durable — that is the ONLY way an id gets into the ring. Answer PurchaseGranted and
+	              apply NOTHING.
+	  UNAVAILABLE the profile cannot be written right now — absent, or held read-only by C31's latch.
+	              Answer NotProcessedYet. NOT "grant anyway" (the grant is discarded unsaved and the
+	              player paid for nothing) and NOT "PurchaseGranted without granting" (that is the
+	              refund request). NotProcessedYet is Roblox's own "ask me again", and the next server
+	              the player lands on grants it.
+
+	THE INVARIANT THAT MAKES DUPLICATE SAFE: an id is appended to the ring in the SAME profile
+	mutation as the grant, and the pair is confirmed durable together via `Profile.LastSavedData`
+	before `PurchaseGranted` is returned. So "the id is in the stored ring" and "the reward is in the
+	stored profile" are the same fact. A caller that appends the id on a different write than the
+	grant breaks this module's guarantee without changing a line of it.
+
+	NO `script.Parent` REQUIRES (tests/README.md). `Decision` is a SCALAR and never travels in a list
+	— see `.claude/lessons/pure-module-unions-widen-in-lists.md`. The ring bound arrives as a
+	parameter out of `Config.Monetization.ReceiptHistory`.
+
+	NOTHING SECRET PASSES THROUGH. A receipt is one player's own purchase, and no other player, no
+	role and no round state appears in any signature here.
+]]
+
+local Receipts = {}
+
+export type Decision = "GRANT" | "DUPLICATE" | "UNAVAILABLE"
+
+--[[
+	What the caller knows about the profile at the moment the receipt landed.
+
+	`Ring` is nil when there is no profile at all — a DataStore outage, a player mid-load, or a player
+	who has already left, all of which `ProgressionService.GetProfile`'s header calls normal answers
+	rather than errors. An EMPTY ring is a different thing entirely: a profile that exists and has
+	granted nothing yet.
+]]
+export type State = {
+	Ring: { string }?,
+	ReadOnly: boolean,
+}
+
+--[[
+	A RECEIPT ID THAT IS NOT A NON-EMPTY STRING IS UNAVAILABLE, NOT GRANT.
+
+	`ProcessReceipt`'s argument is typed `{ [string]: any }` in this repo's own Roblox definitions
+	(`.luau-defs/globalTypes.d.luau:14069`), so every field in it is `any` and `receiptInfo.PurchaseId`
+	is whatever arrives. An unusable id cannot be recorded, so granting on one would grant again on
+	every re-delivery forever — the double-grant, in its most durable form. Refusing means Roblox
+	retries, which is recoverable.
+]]
+local function usableId(receiptId: unknown): boolean
+	return type(receiptId) == "string" and #(receiptId :: string) > 0
+end
+
+function Receipts.decide(state: State, receiptId: unknown): Decision
+	if not usableId(receiptId) then
+		return "UNAVAILABLE"
+	end
+
+	local ring = state.Ring
+
+	if ring == nil then
+		return "UNAVAILABLE"
+	end
+
+	--[[
+		THE DUPLICATE CHECK COMES BEFORE THE READ-ONLY CHECK, and the order is load-bearing.
+
+		A read-only profile whose ring ALREADY contains this id has nothing left to do: the grant
+		landed on an earlier session and is durable. Answering UNAVAILABLE there would leave Roblox
+		re-delivering a receipt that can never be retired, on every join, forever — a purchase stuck
+		in limbo for a player whose only crime was landing on a server running an older schema.
+	]]
+	for _, seen in ring do
+		if seen == receiptId then
+			return "DUPLICATE"
+		end
+	end
+
+	if state.ReadOnly then
+		return "UNAVAILABLE"
+	end
+
+	return "GRANT"
+end
+
+--[[
+	The ring with `receiptId` appended, oldest evicted, capped at `limit`.
+
+	RETURNS A NEW TABLE rather than mutating, so a caller cannot half-apply it: the grant and the
+	append have to reach the profile together, and an in-place mutation makes "together" something the
+	caller has to remember rather than something the shape enforces.
+
+	IDEMPOTENT ON ITS OWN TERMS — appending an id already present returns the ring unchanged — so a
+	caller that skips `decide` still cannot produce a ring with a repeat in it.
+]]
+function Receipts.record(ring: { string }, receiptId: string, limit: number): { string }
+	for _, seen in ring do
+		if seen == receiptId then
+			return table.clone(ring)
+		end
+	end
+
+	local out = table.clone(ring)
+	table.insert(out, receiptId)
+
+	--[[
+		EVICT FROM THE FRONT. The newest ids are the ones a re-delivery could still be about; Roblox
+		retires a receipt once it is acknowledged, so an id old enough to fall off this ring is one
+		nothing is asking about any more. `limit` below 1 is clamped rather than trusted: a zero would
+		evict the id being recorded and turn every purchase into a permanent re-grant loop.
+	]]
+	local cap = math.max(1, math.floor(limit))
+
+	while #out > cap do
+		table.remove(out, 1)
+	end
+
+	return out
+end
+
+return Receipts
```

The suite covers all three decisions, both orderings of the read-only/duplicate interaction, eviction,
and the malformed-id case. Its most important assertion is the **replay-after-rejoin** one, which is
C38's stated Done condition:

```diff
+--!strict
+--[[
+	`ProcessReceipt` idempotency (C38).
+
+	BUILD-PLAN's Done condition for C38 is "a purchase grants exactly once and survives a rejoin
+	mid-transaction", and the Verify line under it needs a human with a real developer product — which
+	C37 has not created and will not before this ships. This suite is what CAN be proved from a
+	terminal, and it is deliberately the whole decision rather than a corner of it.
+
+	THE TWO FAILURES THIS IS AGAINST ARE BOTH SILENT. A double grant reads as a generous game; an
+	eaten purchase reads as a confused player. Neither logs, and by the time either is noticed the
+	DataStore no longer holds what happened.
+]]
+
+local Config = require("../src/shared/Config")
+local Receipts = require("../src/server/pure/Receipts")
+
+type State = Receipts.State
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
+local LIMIT = 4 -- NOT Config's, so the eviction assertions pass because the logic is right
+
+-- ── The three decisions ───────────────────────────────────────────────────────
+
+check(
+	"a first-time receipt on a writable profile grants",
+	Receipts.decide({ Ring = {}, ReadOnly = false }, "r1") == "GRANT"
+)
+
+check(
+	"a receipt already in the ring is a duplicate",
+	Receipts.decide({ Ring = { "r1" }, ReadOnly = false }, "r1") == "DUPLICATE"
+)
+
+check(
+	"a first-time receipt on a READ-ONLY profile is unavailable, not granted",
+	Receipts.decide({ Ring = {}, ReadOnly = true }, "r1") == "UNAVAILABLE",
+	"granting into a profile that will never be saved means the player paid for nothing"
+)
+
+check(
+	"no profile at all is unavailable",
+	Receipts.decide({ Ring = nil, ReadOnly = false }, "r1") == "UNAVAILABLE"
+)
+
+--[[
+	THE ORDERING CASE. A read-only profile that has ALREADY granted this receipt must answer
+	DUPLICATE, not UNAVAILABLE — otherwise Roblox re-delivers it on every join forever and the
+	purchase never retires.
+]]
+check(
+	"a duplicate on a read-only profile still retires the receipt",
+	Receipts.decide({ Ring = { "r1" }, ReadOnly = true }, "r1") == "DUPLICATE"
+)
+
+-- ── Malformed receipt ids ─────────────────────────────────────────────────────
+
+for label, id in { empty = "", number = 7, nothing = nil, table_ = {} } :: { [string]: any } do
+	check(
+		`a {label} receipt id is unavailable rather than granted`,
+		Receipts.decide({ Ring = {}, ReadOnly = false }, id) == "UNAVAILABLE",
+		"an id that cannot be recorded would grant again on every re-delivery"
+	)
+end
+
+-- ── The ring ──────────────────────────────────────────────────────────────────
+
+check("recording appends", #Receipts.record({}, "r1", LIMIT) == 1)
+check("recording is idempotent", #Receipts.record({ "r1" }, "r1", LIMIT) == 1)
+check("recording does not mutate its input", (function()
+	local ring = { "r1" }
+	Receipts.record(ring, "r2", LIMIT)
+
+	return #ring == 1
+end)())
+
+local full = {}
+for index = 1, LIMIT do
+	full = Receipts.record(full, `r{index}`, LIMIT)
+end
+
+local evicted = Receipts.record(full, "r5", LIMIT)
+
+check("the ring stays capped", #evicted == LIMIT, `{#evicted} entries`)
+check("eviction drops the OLDEST id", evicted[1] == "r2", `head is {evicted[1]}`)
+check("eviction keeps the newest id", evicted[#evicted] == "r5")
+
+check(
+	"a zero limit is clamped rather than trusted",
+	#Receipts.record({}, "r1", 0) == 1,
+	"a zero cap would evict the id being recorded and re-grant forever"
+)
+
+--[[
+	── THE DONE CONDITION: EXACTLY ONCE ACROSS A MID-TRANSACTION REJOIN ──────────
+
+	Both crash points, walked as the server would. The property under test is that the reward is
+	applied exactly once whichever side of the durable write the process died on.
+]]
+local function replay(ringAfterCrash: { string }): number
+	local grants = 0
+	local ring = ringAfterCrash
+
+	-- Roblox re-delivers the same receipt until it is acknowledged. Three deliveries is more than it
+	-- takes to expose a double grant and cheap enough to be worth the certainty.
+	for _ = 1, 3 do
+		if Receipts.decide({ Ring = ring, ReadOnly = false }, "r-crash") == "GRANT" then
+			grants += 1
+			ring = Receipts.record(ring, "r-crash", LIMIT)
+		end
+	end
+
+	return grants
+end
+
+check(
+	"a crash BEFORE the write grants exactly once on re-delivery",
+	replay({}) == 1,
+	`granted {replay({})} times`
+)
+
+check(
+	"a crash AFTER the write grants exactly zero more times",
+	replay({ "r-crash" }) == 0,
+	`granted {replay({ "r-crash" })} times`
+)
+
+-- The shipped bound gets its own look, since every assertion above ran on LIMIT.
+check(
+	"the shipped ring bound is usable",
+	Config.Monetization.ReceiptHistory >= 1,
+	`{Config.Monetization.ReceiptHistory}`
+)
+
+if failures > 0 then
+	error(`{failures} receipt failure(s)`, 0)
+end
+
+print(`  PASS  receipts: {checked} assertions`)
```

#### Step 1.5: Add `src/server/pure/GamepassCache.luau` — the staleness rule

**File:** `src/server/pure/GamepassCache.luau`
**Verify:** `lune run tests/gamepass-cache.test.luau`

`GamepassCache.isStale(stampUTC, nowUTC, ttl) -> boolean`, with the clock-skew and never-checked cases
pinned. This is the module `Types.luau:46-51` describes: the stamp says *when we last asked Roblox*,
and ownership itself is never stored.

```diff
+--!strict
+--[[
+	GamepassCache — when to ask Roblox about gamepass ownership again. (C38, §8.2)
+
+		isStale(stampUTC, nowUTC, ttlSeconds) -> boolean
+
+	WHAT `Profile.Purchases.GamepassCacheUTC` IS, restated from its own declaration in Types.luau
+	because the distinction is the entire reason this module is small: it is A CACHE STAMP, NOT AN
+	ENTITLEMENT. It records WHEN this server last asked Roblox which passes the player owns. Ownership
+	itself is never stored, because a cached "owns it" is a value that survives a refund — and a
+	refunded VIP who keeps their aura forever is a bug with no expiry and no error.
+
+	So the only question here is "should we ask again", and the only wrong answers are cheap ones:
+	asking too often spends a web call, asking too rarely delays a genuine purchase by up to one TTL.
+	Neither is a correctness failure, which is why the module holds a rule rather than a mechanism.
+
+	THE CASE THAT IS NOT OBVIOUS IS THE CLOCK. `os.time()` is a server clock, the stamp was written by
+	a DIFFERENT server, and nothing guarantees the second is ahead of the first. A naive
+	`now - stamp > ttl` reads a future stamp as fresh and pins a player's ownership answer until the
+	clocks agree — which could be hours. A stamp in the future is therefore STALE: re-asking is the
+	cheap direction, and it self-heals by rewriting the stamp with this server's clock.
+
+	NO `script.Parent` REQUIRES (tests/README.md). The TTL arrives as a parameter out of
+	`Config.Monetization.GamepassCacheSeconds`.
+]]
+
+local GamepassCache = {}
+
+function GamepassCache.isStale(stampUTC: number, nowUTC: number, ttlSeconds: number): boolean
+	--[[
+		A NaN or infinite stamp is stale. `stampUTC ~= stampUTC` is the NaN test; the finite bound
+		catches the infinity a `~= itself` test misses entirely — the same predicate
+		`ProgressionService.Award` uses, and for the same reason its comment gives.
+	]]
+	if not (stampUTC >= 0 and stampUTC < math.huge) then
+		return true
+	end
+
+	-- Never asked. `0` is the template's value, so this is every player's first check.
+	if stampUTC == 0 then
+		return true
+	end
+
+	-- A stamp from the future: another server's clock is ahead of ours. See the header.
+	if stampUTC > nowUTC then
+		return true
+	end
+
+	return nowUTC - stampUTC >= ttlSeconds
+end
+
+return GamepassCache
```

```diff
+--!strict
+--[[
+	The gamepass ownership cache's staleness rule (C38).
+
+	Small, and worth pinning anyway for one case: a stamp written by a server whose clock is AHEAD of
+	this one. The naive subtraction reads it as fresh and freezes a player's ownership answer until
+	the clocks agree, which is a bug that only appears across machines and therefore never in Studio.
+]]
+
+local Config = require("../src/shared/Config")
+local GamepassCache = require("../src/server/pure/GamepassCache")
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
+local NOW = 1755000000 -- an arbitrary real Unix second; nothing depends on which
+local TTL = 600
+
+check("a never-checked profile is stale", GamepassCache.isStale(0, NOW, TTL))
+check("a fresh stamp is not stale", not GamepassCache.isStale(NOW - 1, NOW, TTL))
+check("a stamp exactly one TTL old is stale", GamepassCache.isStale(NOW - TTL, NOW, TTL))
+check("a stamp just inside the TTL is fresh", not GamepassCache.isStale(NOW - TTL + 1, NOW, TTL))
+check("an ancient stamp is stale", GamepassCache.isStale(NOW - TTL * 100, NOW, TTL))
+
+check(
+	"a stamp from the FUTURE is stale, not fresh",
+	GamepassCache.isStale(NOW + 3600, NOW, TTL),
+	"another server's clock ran ahead; re-asking is the cheap direction and self-heals"
+)
+
+check("a NaN stamp is stale", GamepassCache.isStale(0 / 0, NOW, TTL))
+check("an infinite stamp is stale", GamepassCache.isStale(math.huge, NOW, TTL))
+check("a negative stamp is stale", GamepassCache.isStale(-1, NOW, TTL))
+
+check(
+	"the shipped TTL is a positive number of seconds",
+	Config.Monetization.GamepassCacheSeconds > 0,
+	`{Config.Monetization.GamepassCacheSeconds}`
+)
+
+if failures > 0 then
+	error(`{failures} gamepass-cache failure(s)`, 0)
+end
+
+print(`  PASS  gamepass-cache: {checked} assertions`)
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing in this phase touches a role. `AnalyticsEvents.luau` holds the *name*
  `role_assigned`, which is a string constant and not a role; the value that fills it does not appear
  until Phase 3. `Receipts` and `GamepassCache` take no player and no round state.
- **Remote direction** — no remotes in this phase. `Remotes.luau` is untouched until Phase 4.
- **Rate limiting** — no `OnServerEvent` handlers in this phase.
- **Magic numbers** — `check:config` governs `src/server/pure/`, so the three new modules must read
  every bound from a parameter. `MAX_RECEIPTS` in `ProfileMigration.luau` is the one duplicate, and it
  needs a `-- config-ok:` waiver naming the no-requires constraint that forces it.
- **Phase ownership** — nothing here touches `setPhase`.
- **Player leaving mid-round** — not reachable from pure modules, but `Receipts.State.Ring = nil` is
  the shape that represents it and the suite covers it.
- **Strict Luau** — `AnalyticsEvents.Name`'s fields each need their `:: Event` cast or they infer as
  plain `string` and fail to satisfy `Emit`'s parameter in Phase 3. This is the exact failure
  CLAUDE.md names about `Enums.RoundPhase.Idle`, and it will not show up until Phase 3 compiles.
- **Mobile budget** — nothing rendered, nothing per-frame.
- **Scope** — `Config.Monetization.Catalogue` is the §8.3 tripwire. `check:scope` does **not** cover
  §8.3, so the only guard is the reviewer: cosmetics, identity and convenience only.

**Issues identified:**

- **`Decision` and `Event` are literal unions returned as scalars.** Both are safe as written —
  `decide` returns one value and `Name`'s fields are cast individually — but `.claude/lessons/pure-module-unions-widen-in-lists.md`
  documents that a union widens to `string` when it travels inside a list across a `require`
  boundary. `AnalyticsEvents.Name` is a table of them, so a caller that iterates it and passes the
  result on may need a re-annotation at the far side, exactly as `ProgressionService.awardRound`
  re-annotates `RoundResult`. Flagged rather than pre-solved, because the analyzer is the authority.
- **`ProfileMigration`'s ring bound is a duplicated number by necessity.** A `shared/pure/` module may
  not require `Config`, so `MAX_RECEIPTS` and `Config.Monetization.ReceiptHistory` can silently
  disagree. The existing `MAX_OWNED_COSMETICS` sets the precedent, and the honest fix is an assertion
  in `tests/config.test.luau` pinning the two — noted in Follow Ups rather than added here, since it
  needs `ProfileMigration` to export the constant.
- **The `Receipts.Ring == nil` and `ReadOnly == true` states are indistinguishable to the caller.**
  Both answer `UNAVAILABLE`, which is correct for the decision but loses the reason. Phase 2's caller
  should log which one it was; a "purchases keep coming back" report is unrecoverable without it.

#### Cannot be observed until C37 (Phase 1)

Nothing. Every step in this phase is terminal-verifiable and product-independent — which is why the
plan front-loads it. **This is the only phase of which that is true.**

### Phase 2: MonetizationService — the durable grant and the ownership cache

The Roblox-shaped half. `ProcessReceipt` wired to the pure decision, one new guarded write path on
`ProgressionService`, and the gamepass cache. No remotes yet, so the network surface is unchanged and
the game stays runnable.

#### Step 2.1: Add `ProgressionService.ApplyReceipt` — one atomic mutation, then a durability wait

**File:** `src/server/Services/ProgressionService.luau`
**Verify:** `npm run analyze`

The new guarded write path, joining `Award` / `SpendCoins` / `GrantCosmetic` / `SetEquipped` /
`SetDaily`. It applies the reward and appends the receipt id in one mutation, calls `profile:Save()`,
then waits on `profile.OnAfterSave` for `LastSavedData` to contain the id. Returns
`"GRANTED" | "DUPLICATE" | "UNAVAILABLE"`.

**Why this lives in `ProgressionService` and not in `MonetizationService`**, restated because a reader
who has only this phase will otherwise put it in the obvious place: the profile table, the session
map, the read-only latch and `saveNow` are all private to this module, and `GetProfile`'s own header
(`ProgressionService.luau:344-358`) says in bold that currency, stats and cosmetics go through the
guarded write paths and **nothing else**. A grant assembled in `MonetizationService` would be
`GetProfile(player).Coins += n` — the exact line that header warns about, which compiles, runs, and
silently writes into a read-only profile.

> **Read `references/ProfileStore-review.luau` before starting this step.** It is not attached to this
> phase automatically — no step's `**File:**` line names `vendor/ProfileStore.luau` — and it is the
> most important review in this plan.

**The finding that shapes this step, repeated here in full because Phase 2 is read alone:**
`Profile:Save()` **does not yield and does not report success**. `vendor/ProfileStore.luau:1172-1190`
ends in `task.spawn(SaveProfileAsync, self)`. So `saveNow` returns before anything is durable, and
"grant, save, return `PurchaseGranted`" returns `PurchaseGranted` for a write that has not happened.
The durability oracle is `Profile.OnAfterSave`, which fires with `Profile.LastSavedData` — set from
the DataStore's own returned data at `vendor/ProfileStore.luau:877` and fired at `:924`, on the
success branch only; the failure branch at `:926` retries with backoff and fires nothing.

```diff
+--[[
+	APPLY A DEVELOPER-PRODUCT RECEIPT (C38). THE ONLY WRITE PATH THAT PROMISES DURABILITY, and the
+	only one in this file that YIELDS.
+
+	Every other write path here is fire-and-forget by design: `Award` mutates, calls `saveNow` and
+	returns, because losing one round's XP to a DataStore hiccup costs a player fifty points. A
+	RECEIPT IS DIFFERENT IN KIND. Roblox has already taken the player's Robux by the time
+	`ProcessReceipt` is called, and the answer we return decides whether it keeps trying. Returning
+	"granted" for a write that never landed is a refund request; returning "not yet" for a write that
+	did land is a double grant. So this one has to know.
+
+	WHY IT HAS TO YIELD AT ALL — the sentence that makes the rest of this function make sense:
+
+	    `Profile:Save()` DOES NOT YIELD AND DOES NOT REPORT SUCCESS.
+
+	`vendor/ProfileStore.luau:1172-1190` ends in `task.spawn(SaveProfileAsync, self)`. `saveNow` above
+	therefore returns before anything is durable, and it is exactly right for what it is used for. It
+	is not enough here.
+
+	The oracle is `Profile.OnAfterSave`, which fires with `Profile.LastSavedData` — assigned from the
+	DataStore's OWN returned data (`vendor/ProfileStore.luau:877`) and fired at `:924`, on the success
+	branch only. The failure branch retries with backoff and fires nothing. So a fire of that signal
+	carrying our receipt id is proof the write landed, and it is the only such proof available.
+
+	WHICH IS WHY THE RECEIPT ID IS IN THE PROFILE. `LastSavedData` can only confirm what is inside the
+	profile; a receipt id in a side DataStore would make "is the grant durable" unanswerable, on top of
+	splitting the grant and its record across two writes with no shared transaction.
+
+	ORDER, AND ALL OF IT MATTERS:
+	  1. decide, from the LIVE ring and the read-only latch
+	  2. on GRANT, mutate ONCE — reward and receipt id in the same table in the same tick
+	  3. Save, then wait for the id to appear in LastSavedData
+	  4. only then answer GRANTED
+
+	A caller that appends the id on a different write than the grant breaks `pure/Receipts`'
+	guarantee without changing a line of it — see that module's header.
+]]
+function ProgressionService.ApplyReceipt(
+	player: Player,
+	receiptId: string,
+	xp: number,
+	coins: number
+): Receipts.Decision
+	local userId = player.UserId
+	local profile = sessions[userId]
+
+	local decision = Receipts.decide({
+		Ring = if profile ~= nil then (profile.Data :: Profile).Purchases.Receipts else nil,
+		ReadOnly = readOnly[userId] == true,
+	}, receiptId)
+
+	if decision ~= "GRANT" then
+		--[[
+			LOG WHICH UNAVAILABLE IT WAS. `pure/Receipts` collapses "no profile" and "read-only" into
+			one answer, which is right for the decision and lossy for the operator: "purchases keep
+			coming back" is unrecoverable without knowing which. Not gated on VerboseLogging — a
+			receipt is rare and this is the line someone will need at 2am.
+		]]
+		if decision == "UNAVAILABLE" then
+			warn(
+				`[Progression] receipt {receiptId} for {player.Name} unavailable: `
+					.. `profile={if profile ~= nil then "present" else "absent"} `
+					.. `readOnly={readOnly[userId] == true}`
+			)
+		end
+
+		return decision
+	end
+
+	--[[
+		Same finite predicate as `Award` — see its comment on why infinity is the case that matters.
+		A malformed reward must not be written, and it must not be answered GRANTED either: refusing
+		here leaves the receipt un-retired, which Roblox retries, which is the recoverable direction.
+	]]
+	if not (xp >= 0 and xp < math.huge and coins >= 0 and coins < math.huge) then
+		warn(`[Progression] refused a malformed receipt grant for {player.Name}: {xp} XP / {coins} coins`)
+
+		return "UNAVAILABLE"
+	end
+
+	local data: Profile = (profile :: any).Data
+
+	-- ONE MUTATION. The reward and the receipt id reach the stored table together or not at all.
+	data.XP += xp
+	data.Coins += coins
+	data.Purchases.Receipts =
+		Receipts.record(data.Purchases.Receipts, receiptId, Config.Monetization.ReceiptHistory)
+
+	return if waitForDurableReceipt(profile, receiptId) then "GRANT" else "UNAVAILABLE"
+end
```

The durability wait itself, declared above `ApplyReceipt` beside `saveNow`:

```diff
+--[[
+	Block until `receiptId` is visible in what the DataStore actually stored, or the budget runs out.
+
+	CONNECT BEFORE SAVING. `Save` spawns the write immediately, so a connection made afterwards can
+	miss a fast save entirely and time out on a grant that already landed — which answers
+	NotProcessedYet for a durable write, and then the re-delivery answers DUPLICATE and the player
+	waits an extra round trip for something they already own. Not fatal, and avoidable by ordering.
+
+	CHECK `LastSavedData` FIRST TOO, for the same race in the other direction: an autosave may have
+	swept the mutation up before we asked.
+
+	THE TIMEOUT IS NOT A LOST PURCHASE. Roblox re-delivers an unacknowledged receipt, and the ring
+	makes the replay a no-op if the write did eventually land. It is a player waiting, which is why
+	`Config.Monetization.ReceiptDurabilityTimeout` is generous rather than tight, and why
+	tests/config.test.luau pins it under the BindToClose budget.
+]]
+local function receiptIsDurable(profile: any, receiptId: string): boolean
+	local saved: any = profile.LastSavedData
+	local purchases: any = if type(saved) == "table" then saved.Purchases else nil
+	local ring: any = if type(purchases) == "table" then purchases.Receipts else nil
+
+	if type(ring) ~= "table" then
+		return false
+	end
+
+	for _, id in ring :: { any } do
+		if id == receiptId then
+			return true
+		end
+	end
+
+	return false
+end
+
+local function waitForDurableReceipt(profile: any, receiptId: string): boolean
+	if receiptIsDurable(profile, receiptId) then
+		return true
+	end
+
+	local done = false
+	local connection = profile.OnAfterSave:Connect(function()
+		if receiptIsDurable(profile, receiptId) then
+			done = true
+		end
+	end)
+
+	profile:Save()
+
+	local deadline = os.clock() + Config.Monetization.ReceiptDurabilityTimeout
+
+	while not done and os.clock() < deadline do
+		--[[
+			A FIXED POLL RATHER THAN AN EVENT WAIT, deliberately. `profile:IsActive()` can go false
+			under us — the player leaves, `endSession` runs, `EndSession` saves and releases the lock —
+			and a bare signal wait would hang until the timeout with nothing left to fire it. Polling
+			lets the loop below notice.
+		]]
+		task.wait(Config.Monetization.ReceiptPollInterval)
+
+		if not profile:IsActive() then
+			break
+		end
+	end
+
+	connection:Disconnect()
+
+	-- Re-check rather than trusting `done`: EndSession's own save may have landed it on the way out.
+	return done or receiptIsDurable(profile, receiptId)
+end
```

`Config.Monetization.ReceiptPollInterval` joins the block from Step 1.1 (`0.25`, with a comment saying
it is a poll cadence rather than a balance knob). The requires at the head of `ProgressionService`
gain `Receipts`:

```diff
 local ProfileMigration = require(Shared.pure.ProfileMigration)
+-- C38. `src/server/pure/`, not `Shared` — the anti-replay decision has no client caller. See its
+-- header for why the id lives in the profile rather than in a side DataStore.
+local Receipts = require(script.Parent.Parent.pure.Receipts)
```

#### Step 2.2: Wire `MarketplaceService.ProcessReceipt` in `MonetizationService`

**File:** `src/server/Services/MonetizationService.luau`
**Verify:** `npm run check:config`

Maps `ApplyReceipt`'s three outcomes onto the two `Enum.ProductPurchaseDecision` values, resolves the
product id back to a catalogue key, and refuses an unknown id. Every timeout and bound read from
`Config.Monetization`.

`ProcessReceipt` is a **field assignment on `MarketplaceService`**, not a signal connection — this
repo's own definitions type it as
`ProcessReceipt: (receiptInfo: { [string]: any }) -> EnumProductPurchaseDecision`
(`.luau-defs/globalTypes.d.luau:14069`). **Only one assignment may exist in the whole game**; a second
silently replaces the first.

```diff
 --!strict
 --[[
 	MonetizationService — Gamepasses, developer products, private servers.
 
 	Milestone: M10
 	Spec: docs/MVP-SPEC.md
 ]]
 
+local MarketplaceService = game:GetService("MarketplaceService")
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local GamepassCache = require(script.Parent.Parent.pure.GamepassCache)
+local ProgressionService = require(script.Parent.ProgressionService)
+
 local MonetizationService = {}
 
-- TODO(M10): MarketplaceService.ProcessReceipt — MUST be idempotent, and must
--            only return PurchaseGranted after the grant is durably saved.
--- TODO(M10): cache gamepass ownership; re-check on join.
--- SELL: cosmetics, identity, private servers. NEVER in-round advantage (spec §8.3).
+--[[
+	SELL: cosmetics, identity, private servers. NEVER in-round advantage (spec §8.3), and the list of
+	what that rules out is explicit: extra salt, extra lives, revives, see-through-walls, a longer
+	transform, and "higher chance to be the Aswang". `check:scope` does NOT cover §8.3 — the catalogue
+	in `Config.Monetization` is the whole surface, and a reviewer is the whole guard.
+
+	EVERY PRODUCT ID IS 0 UNTIL A HUMAN DOES C37. Every read guards on `~= 0` and no-ops. That means
+	NOTHING IN THIS FILE CAN BE OBSERVED WORKING YET: Roblox never calls `ProcessReceipt` for a
+	product that does not exist, and `UserOwnsGamePassAsync` is never reached. An empty shop is this
+	file working correctly.
+]]
+
+--[[
+	Resolve a developer-product id back to its catalogue entry.
+
+	LINEAR OVER FIVE ENTRIES, ONCE PER PURCHASE, so an index would be a cache to invalidate for
+	nothing. Returns nil for an unknown id — including EVERY id while the catalogue is zeroed, which
+	is why the `Id == 0` skip comes first: without it, a receipt for any product would match the first
+	zeroed entry and grant the wrong reward the moment C37 lands a single real id.
+]]
+local function productFor(productId: number): (string?, any)
+	for key, entry in Config.Monetization.Catalogue do
+		if entry.Id ~= 0 and entry.Id == productId and entry.Kind == "Product" then
+			return key, entry
+		end
+	end
+
+	return nil, nil
+end
+
+--[[
+	`MarketplaceService.ProcessReceipt` — ASSIGNED, NOT CONNECTED, and assigned exactly once in the
+	whole game. It is a FIELD (`.luau-defs/globalTypes.d.luau:14069` types it as a function-valued
+	property), so a second assignment anywhere silently replaces this one and every purchase after
+	that is answered by whichever module loaded last.
+
+	WHAT THE TWO RETURN VALUES MEAN, because choosing between them is the whole chunk:
+	  PurchaseGranted   we are done; Roblox retires the receipt and never asks again.
+	  NotProcessedYet   ask us again — a different server, a later session, whenever.
+
+	There is no third option, and in particular there is no way to say "this purchase was invalid".
+	So every path that cannot durably grant must answer NotProcessedYet, INCLUDING the paths that look
+	like errors: no profile, a read-only profile, an unknown product id. Answering PurchaseGranted to
+	get rid of an awkward case is the refund request BUILD-PLAN warns about.
+
+	RECEIPTINFO'S FIELD NAMES ARE NOT VERIFIED BY ANYTHING IN THIS REPO — the definitions type the
+	whole table as `{ [string]: any }`, so `PurchaseId`, `PlayerId` and `ProductId` come from Roblox's
+	documentation rather than from a signature. Read every one defensively and refuse rather than
+	assume; see this plan's Follow Ups.
+]]
+local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
+	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
+	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
+
+	local receiptId = receiptInfo.PurchaseId
+	local userId = receiptInfo.PlayerId
+	local productId = receiptInfo.ProductId
+
+	if type(receiptId) ~= "string" or type(userId) ~= "number" or type(productId) ~= "number" then
+		warn(`[Monetization] malformed receipt; answering NotProcessedYet`)
+
+		return notYet
+	end
+
+	local key, entry = productFor(productId)
+
+	if key == nil then
+		--[[
+			AN UNKNOWN PRODUCT IS NotProcessedYet, NOT PurchaseGranted, and this is the case that will
+			actually happen: a product created in the Creator Hub before its id reaches Config. The
+			purchase then retires the moment someone fills the id in. Answering PurchaseGranted here
+			would take the money and grant nothing, permanently.
+		]]
+		warn(`[Monetization] receipt for unknown product {productId}; answering NotProcessedYet`)
+
+		return notYet
+	end
+
+	--[[
+		THE PLAYER MUST BE ON THIS SERVER. `ProcessReceipt` fires on the server the purchase was made
+		on, but a re-delivery can arrive after they have gone. `ApplyReceipt` needs a live session, so
+		with no player there is nothing to grant into and NotProcessedYet is the honest answer —
+		Roblox re-delivers on their next join.
+	]]
+	local player = Players:GetPlayerByUserId(userId)
+
+	if player == nil then
+		return notYet
+	end
+
+	local decision = ProgressionService.ApplyReceipt(player, receiptId, 0, entry.Coins)
+
+	if decision == "GRANT" or decision == "DUPLICATE" then
+		return granted
+	end
+
+	return notYet
+end
```

`Init` performs the assignment; `Start` stays empty for this step.

```diff
-function MonetizationService.Init() end
+function MonetizationService.Init()
+	--[[
+		IN `Init`, NOT `Start`. A receipt can arrive the instant the server accepts a player, and
+		`init.server.luau` runs every `Init` before any `Start` — so assigning here closes the window
+		in which a purchase could land with no handler and be answered by Roblox's default.
+
+		The handler itself needs nothing from another service at assignment time; it calls
+		`ProgressionService` only when a receipt actually arrives, which is long after both phases.
+	]]
+	MarketplaceService.ProcessReceipt = processReceipt
+end
```

#### Step 2.3: The gamepass ownership cache, no-opping on a zeroed id

**File:** `src/server/Services/MonetizationService.luau`
**Verify:** `npm run verify:fast`

`MonetizationService.OwnsGamepass(player, key)` behind `GamepassCache.isStale`, calling
`UserOwnsGamePassAsync` at most once per player per TTL, and returning `false` without any call when
the id is `0`. This is the query C35 will consume; this plan stops at the query.

```diff
+--[[
+	GAMEPASS OWNERSHIP, CACHED PER SERVER FOR `Config.Monetization.GamepassCacheSeconds`.
+
+	WHAT IS AND IS NOT PERSISTED, because the distinction is the whole design and
+	`Types.PlayerProfile.Purchases.GamepassCacheUTC` states it at its declaration: the PROFILE stores
+	only WHEN we last asked. Ownership itself lives in this server's memory and dies with it. A
+	persisted "owns it" is a value that survives a refund, and a refunded VIP keeping their aura
+	forever is a bug with no expiry and no error message.
+
+	SO THIS IS A CACHE, NOT AN ENTITLEMENT, and Roblox is the authority every time the stamp expires.
+
+	THE ANSWER IS A SECRET ABOUT NOBODY. A gamepass is public information — Roblox's own inventory API
+	serves it — so nothing here is subject to §6.2. It is listed in this plan's secrecy review anyway
+	because C35 will hang VISIBLE EFFECTS off this answer (an aura, a name colour), and a visible
+	effect keyed on anything is a channel. That is C35's problem to solve, not this one's, and this
+	function deliberately hands back a boolean and no rendering.
+]]
+local owned: { [number]: { [string]: boolean } } = {}
+
+function MonetizationService.OwnsGamepass(player: Player, key: string): boolean
+	local entry = Config.Monetization.Catalogue[key]
+
+	--[[
+		THE ZEROED-ID NO-OP, and it must be a no-op rather than an error. Until a human does C37 every
+		id here is 0, and `UserOwnsGamePassAsync(userId, 0)` is a web call whose answer is meaningless
+		at best. Returning false without asking is what makes the whole service runnable — and
+		harmless — before the products exist.
+	]]
+	if entry == nil or entry.Kind ~= "Gamepass" or entry.Id == 0 then
+		return false
+	end
+
+	local userId = player.UserId
+	local profile = ProgressionService.GetProfile(player)
+
+	--[[
+		NO PROFILE MEANS NO STAMP TO READ OR WRITE — a DataStore outage, a player mid-load, or one who
+		has already left, all of which `GetProfile`'s header calls normal answers. Ask Roblox directly
+		and cache in memory for the session; the miss costs a web call and nothing else.
+	]]
+	local stamp = if profile ~= nil then profile.Purchases.GamepassCacheUTC else 0
+	local cached = owned[userId]
+
+	if
+		cached ~= nil
+		and cached[key] ~= nil
+		and not GamepassCache.isStale(stamp, os.time(), Config.Monetization.GamepassCacheSeconds)
+	then
+		return cached[key]
+	end
+
+	--[[
+		`UserOwnsGamePassAsync` IS A WEB CALL AND CAN THROW. An error here must not propagate into
+		whatever asked — a failed ownership check is "we do not know", and the safe unknown is FALSE.
+		Erring toward false means a genuine owner briefly loses a cosmetic; erring toward true means a
+		non-owner gains one, which is the direction that costs money.
+
+		`:: any` on the pcall for the reason CLAUDE.md gives about `() -> ()`: a pcall over a typed
+		call binds fewer values than --!strict expects.
+	]]
+	local ok, result = pcall(function()
+		return MarketplaceService:UserOwnsGamePassAsync(userId, entry.Id)
+	end)
+
+	if not ok then
+		warn(`[Monetization] ownership check failed for {player.Name}/{key}: {result}`)
+
+		return false
+	end
+
+	if cached == nil then
+		cached = {}
+		owned[userId] = cached
+	end
+
+	;(cached :: { [string]: boolean })[key] = result == true
+
+	--[[
+		STAMP THE PROFILE THROUGH A GUARDED WRITE PATH, never `GetProfile(...).Purchases.X = y`. That
+		line compiles, runs, and writes into a profile this server has latched read-only — the exact
+		trap `GetProfile`'s header names. `SetGamepassChecked` is a one-line addition to
+		ProgressionService's write paths, guarded like the rest, with NO `saveNow`: a cache stamp is
+		not a change a player would be angry to lose, and ProfileStore autosaves.
+	]]
+	ProgressionService.SetGamepassChecked(player, os.time())
+
+	return result == true
+end
```

`Players.PlayerRemoving` drops the memory cache, and `ProgressionService` gains the one-line stamp
writer beside `SetDaily`:

```diff
-function MonetizationService.Start() end
+function MonetizationService.Start()
+	--[[
+		DROP THE IN-MEMORY OWNERSHIP CACHE ON LEAVE. Keyed by UserId, so without this a long-lived
+		server accumulates one table per player who has ever joined — a slow leak with no symptom
+		until it has one.
+	]]
+	Players.PlayerRemoving:Connect(function(player)
+		owned[player.UserId] = nil
+	end)
+end
```

```diff
+--[[
+	STAMP WHEN WE LAST ASKED ROBLOX ABOUT GAMEPASSES (C38). A cache stamp, not an entitlement — see
+	`Types.PlayerProfile.Purchases.GamepassCacheUTC`.
+
+	NO `saveNow`, deliberately, for the reason `BumpStat` next door gives: this is not a change a
+	player would be angry to lose, and ProfileStore autosaves. The worst case of losing it is one
+	extra web call on their next session.
+]]
+function ProgressionService.SetGamepassChecked(player: Player, whenUTC: number): boolean
+	local userId = player.UserId
+	local profile = sessions[userId]
+
+	if profile == nil or readOnly[userId] then
+		return false
+	end
+
+	-- Same finite test as `Award` — see its comment on why infinity is the case that matters.
+	if not (whenUTC >= 0 and whenUTC < math.huge) then
+		return false
+	end
+
+	;(profile.Data :: Profile).Purchases.GamepassCacheUTC = whenUTC
+
+	return true
+end
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing here reads a role or the round. `OwnsGamepass` returns a boolean about
  a public fact and deliberately renders nothing; the moment C35 hangs an aura off it, that becomes a
  visible channel keyed on a purchase, which is C35's problem and must not be pre-empted here.
- **Remote direction** — still no remotes. `Remotes.luau` is untouched until Phase 4.
- **Rate limiting** — no `OnServerEvent` handlers yet. `ProcessReceipt` is not a remote and
  `check:ratelimit` correctly does not see it; the rate limiter on purchases is Roblox's own.
- **Magic numbers** — `check:config` governs this file. The `0` in `entry.Id == 0` and the `0` XP
  argument are both idiomatic and allowed; the timeout, poll interval and ring bound must all be read
  from `Config.Monetization`.
- **Phase ownership** — nothing here calls `setPhase` or reads the phase. The phase gate arrives in
  Phase 4.
- **Player leaving mid-round** — the case that bites here. `waitForDurableReceipt` yields, and the
  player can leave during the yield: `endSession` runs, `EndSession` saves and releases the lock, and
  `profile:IsActive()` goes false. The loop breaks on that and re-checks `LastSavedData`, because
  `EndSession`'s own save may well have landed the grant on the way out.
- **Strict Luau** — `receiptInfo` is `{ [string]: any }`, so every field needs a `type()` check rather
  than a cast. `pcall` over a typed call needs the `:: any` treatment CLAUDE.md describes.
- **Mobile budget** — nothing rendered.
- **Scope** — the §8.3 list. Nothing in the catalogue may affect a round.

**Issues identified:**

- **(Medium) `waitForDurableReceipt` yields inside `ProcessReceipt`.** Roblox calls `ProcessReceipt`
  on its own thread, so yielding is permitted, but a slow DataStore holds that thread for up to
  `ReceiptDurabilityTimeout`. Whether Roblox serialises concurrent receipts for the same player, and
  what it does if the callback is still running when it wants to re-deliver, is **not verified by
  anything in this repo**. Recorded in Follow Ups. The design is safe either way — a concurrent
  re-delivery reads the live ring and answers `DUPLICATE`, or reads it before the mutation and
  produces a second `GRANT` whose `Receipts.record` is idempotent — but "safe either way" is reasoning
  rather than evidence.
- **(Medium) `receiptInfo`'s field names are unverified.** `.luau-defs/globalTypes.d.luau:14069` types
  the argument as `{ [string]: any }`, so `PurchaseId` / `PlayerId` / `ProductId` come from Roblox's
  documentation and nothing in this repo confirms them. The handler refuses rather than assumes, so a
  wrong name degrades to `NotProcessedYet` — recoverable — rather than to a wrong grant. **This is the
  single most important thing for a human to confirm at C37.**
- **(Low) `productFor` is O(catalogue) per receipt and per zeroed id returns nil for everything.** The
  `entry.Id ~= 0` guard has to come first or a partially-filled catalogue matches the wrong entry. It
  does; noted because reordering it looks harmless.
- **(Low) One `ProcessReceipt` assignment, game-wide.** It is a field, not a signal. If C35 or C39
  adds a second, purchases are answered by whichever module loaded last and this one silently stops
  running. There is no check for this — noted in Follow Ups as a candidate for `check:remotes`'
  neighbourhood.

#### Cannot be observed until C37 (Phase 2)

**Everything behavioural in this phase.** Specifically, none of the following may be reported as
verified by a playtester or by any agent:

- `ProcessReceipt` ever running. Roblox does not deliver receipts for products that do not exist, so
  the callback is assigned and never invoked. **Its assignment is observable; its behaviour is not.**
- The exactly-once property across a rejoin — C38's stated Done condition. What Phase 1's
  `tests/receipts.test.luau` proves is that the *decision* is correct over every state; what remains
  unproven is that the Roblox-shaped wiring around it passes the right state in. That gap closes only
  with a real product and an alt account (`docs/BUILD-PLAN.md:820`).
- The durability wait. `OnAfterSave` fires on ordinary saves, so the mechanism can be exercised, but
  "a receipt was confirmed durable" cannot be, because no receipt arrives.
- `UserOwnsGamePassAsync` ever being called. Every id is `0`, so `OwnsGamepass` returns false at the
  guard and the web call is never reached.

What **is** observable in Studio after this phase: the server boots with no new warnings, every
service still starts, and a round still cycles. That is the honest claim, and it is worth making
because a broken `Init` assignment would break the bootstrap.

### Phase 3: AnalyticsService — the emitter, its structural egress guard, and fifteen call sites

#### Step 3.1: Implement the emitter over Roblox's built-in `AnalyticsService`

**File:** `src/server/Services/AnalyticsService.luau`
**Verify:** `npm run analyze`

`AnalyticsService.Emit(player, event, fields)` typed on `AnalyticsEvents.Event`, wrapping
`game:GetService("AnalyticsService"):LogCustomEvent`. **The name collision is the trap** — our module
and Roblox's service share a name — so the service is bound to a local named `RobloxAnalytics`.

**Q2's answer restated in full, because this phase is read alone.** Every event is emitted **from the
server and only from the server**. The emitter's sole egress is Roblox's built-in `AnalyticsService`,
confirmed from this repo's own vendored definitions at `.luau-defs/globalTypes.d.luau:9229-9235`:
`LogCustomEvent(self, player, eventName, value?, customFields?)` and
`LogFunnelStepEvent(self, player, funnelName, funnelSessionId?, step?, stepName?, customFields?)`.
Those write to the Creator Hub. They are not remotes: no client subscriber, no replicated container,
no attribute, no tag. **So `role_assigned (role)` reaching Roblox's telemetry backend is not a leak.**

**And `check:secrecy` does not see it either way.** Rules 0–4 scan `Fire*` payloads, attribute names
and tag names — *not general server code* (`check-secrecy.mjs:169-183` says exactly that of Rule 5's
scope). A line reading `RobloxAnalytics:LogCustomEvent(player, "role_assigned", nil, { role = role })`
matches no existing rule and passes `npm run verify` green. That is the correct outcome and it is also
the gap: **nothing mechanical currently distinguishes that line from one that fires a remote.**
Step 3.2 is what closes it.

```diff
 --!strict
 --[[
 	AnalyticsService — Emits the gameplay funnel events.
 
 	Milestone: M11
 	Spec: docs/MVP-SPEC.md
 ]]
 
+local Players = game:GetService("Players")
+
+--[[
+	THE NAME COLLISION IS THE TRAP IN THIS FILE. Roblox ships its OWN service called
+	`AnalyticsService`, and this module is also called `AnalyticsService`. Bound to `RobloxAnalytics`
+	so that every call site reads unambiguously and nobody writes `AnalyticsService:LogCustomEvent`
+	against our own table and gets a nil-call at runtime, in a service whose entire job is to be
+	silent when it works.
+]]
+local RobloxAnalytics = game:GetService("AnalyticsService")
+
+local AnalyticsEvents = require(script.Parent.Parent.pure.AnalyticsEvents)
+
 local AnalyticsService = {}
 
--- TODO(M11): emit the events listed in docs/MVP-SPEC.md Appendix B.
--- The funnel that matters: joined -> reached ACTIVE round -> completed a round
--- -> returned on day 2. Track win rate per side from day one or you cannot balance.
+type Event = AnalyticsEvents.Event
+
+--[[
+	══ THIS FILE HAS NO CLIENT EGRESS, AND THAT IS ENFORCED RATHER THAN INTENDED ══════════════════
+
+	`check-secrecy.mjs` Rule 6 refuses this file if it requires `Remotes`, names `ReplicatedStorage`,
+	or contains `FireClient` / `FireAllClients` / `:Fire(`. Adding any of them means editing that
+	check script, which shows up in a diff — the same asymmetry `REVEAL_ALLOWLIST` buys for the two
+	remotes allowed to carry the reveal.
+
+	WHY THAT RULE EXISTS RATHER THAN A COMMENT. Two events here carry things that must never reach a
+	client, and both were flagged during C02–C04 as the thing C40 would get wrong:
+
+	  · `role_assigned (role)` IS the secret (§6.2). It is safe here because Roblox's telemetry
+	    backend is not a client. It would be fatal one line lower, in a broadcast.
+	  · `player_killed (secondsIntoRound, wasIsolated)` is Amendment A3's death oracle in a table.
+	    A3 (docs/MVP-SPEC.md:219-244) DELETED the global death signal — the `PlayerKilled` broadcast
+	    and `ClientRoundSnapshot.AlivePlayerCount` — because a sub-second "someone just died" plus
+	    replicated positions identifies the Aswang without anybody witnessing a transform. An
+	    analytics call site must not become the broadcast A3 removed, and the two lines read alike.
+
+	NOTHING HERE READS BACK, EITHER. There is no query API on this module and there must not be: a
+	"how many kills so far" helper is a role hint with a friendly name.
+]]
+
+--[[
+	Emit one Appendix B event for one player.
+
+	`event` IS THE LITERAL UNION out of `pure/AnalyticsEvents`, so a misspelled name is an analyze
+	error rather than a dashboard series that reads zero forever — which is indistinguishable from an
+	event that genuinely never fires, and is the failure mode this whole design is against.
+
+	`pcall` BECAUSE TELEMETRY MUST NEVER BREAK GAMEPLAY. `LogCustomEvent` is a web-backed call in a
+	service that may be disabled in a local Studio session; an error propagating out of here would
+	take down whatever was mid-kill or mid-round when it fired. A dropped metric is a cost; a dropped
+	round is a bug.
+
+	`:: any` on the pcall for the reason CLAUDE.md gives about `() -> ()` — a pcall over a typed call
+	binds fewer values than --!strict expects.
+]]
+function AnalyticsService.Emit(player: Player, event: Event, fields: { [string]: any }?)
+	local ok, err = pcall(function()
+		RobloxAnalytics:LogCustomEvent(player, event, nil, fields)
+	end)
+
+	if not ok then
+		--[[
+			WARN WITHOUT THE FIELDS. `fields` can contain the role. A server console is a safe place
+			for it (`MonsterService`'s own gating comment makes the same call), but a warn line is the
+			kind of thing that gets piped somewhere else later, and this one carries no information
+			worth that risk.
+		]]
+		warn(`[Analytics] {event} failed to log: {err}`)
+	end
+end
```

#### Step 3.2: Add check-secrecy Rule 6 — the emitter has no client egress

**File:** `.claude/scripts/check-secrecy.mjs`
**Verify:** `npm run check:guards`

`AnalyticsService.luau` may not require `Remotes`, may not contain `FireClient` / `FireAllClients` /
`:Fire(`, and may not name `ReplicatedStorage`. Proven in **both** directions in the script's own
`--self-test`, per `harness-selftest.mjs`'s header rule. This is what makes Q2's answer structural.

`check-secrecy` is already listed in `harness-selftest.mjs`'s `SUITES` (`:93`), so **no `SUITES` edit
is needed** — the new cases go inside the script's existing `--self-test`.

Rule 6 sits beside Rule 5's `ROLE_BLIND` list, which it deliberately mirrors: Rule 5 names files that
must not be *able* to tell who the Aswang is; Rule 6 names a file that must be able to tell and must
not be able to *say*.

```diff
+//[ Rule 6 ] The analytics emitter must have no client egress.
+//
+// Not "must not leak the secret" — Rule 5 covers files that must not be able to TELL. This is the
+// opposite shape: AnalyticsService legitimately RECEIVES the role, because Appendix B asks for
+// `role_assigned (role)` and Roblox's own telemetry backend is not a client. What it must never gain
+// is a way to say it to one.
+//
+// WHY A FILE RULE RATHER THAN A PAYLOAD RULE. Rules 0-4 scan Fire* payloads, attributes and tags, so
+// a `LogCustomEvent(player, "role_assigned", nil, { role = role })` line matches nothing and passes
+// green — correctly, since it is not a leak. But that means NOTHING mechanical separates it from a
+// line one character different that fires a remote instead, in the one file in this game that is
+// guaranteed to be holding the role when someone is wiring up a funnel. The C02-C04 plan flagged
+// exactly this twice (its lines 1149 and 2627) and left it for C40 to answer. This is the answer.
+//
+// The forbidden set is deliberately crude: anything that could reach a client at all. An emitter has
+// no legitimate use for any of it, so a false positive here is a design change, not a nuisance.
+const NO_CLIENT_EGRESS = ['AnalyticsService.luau']
+
+const EGRESS = /:Fire(?:AllClients|Client)?\s*\(|\bRemotes\b|\bReplicatedStorage\b/
```

The scan clause, beside Rule 5's at `check-secrecy.mjs:402`:

```diff
+    // ── Rule 6: the analytics emitter reaching for a client ────────────────────
+    if (NO_CLIENT_EGRESS.some(name => file.endsWith(name))) {
+      for (const match of code.matchAll(new RegExp(EGRESS, 'g'))) {
+        const line = lineOf(code, match.index)
+
+        if (hasWaiver(rawLines, line, 'secrecy')) continue
+
+        findings.push({
+          file,
+          line,
+          why: `analytics emitter reaching for a client (\`${match[0].trim()}\`)`,
+          detail:
+            'AnalyticsService holds the role by design (Appendix B: `role_assigned (role)`) and must ' +
+            'have no way to send it anywhere but Roblox\'s telemetry backend. Its only egress is ' +
+            'AnalyticsService:LogCustomEvent / LogFunnelStepEvent. If a remote genuinely belongs here, ' +
+            'move it to the service that owns the fact instead.'
+        })
+      }
+    }
```

**Both directions, per `harness-selftest.mjs`'s header — the ALLOW case is the half that matters.**
Four cases, and the third and fourth are the ones that prove the rule is narrow enough to live with:

```diff
+  // ── Rule 6 ──────────────────────────────────────────────────────────────────
+  writeFileSync(
+    join(servicesDir, 'AnalyticsService.luau'),
+    'local Remotes = require(Shared.Remotes)\nRemotes.Get("X"):FireAllClients(role)\n'
+  )
+  expect('rule 6 flags a remote in the emitter', scan([join(servicesDir, 'AnalyticsService.luau')]).length > 0)
+
+  // ALLOW: the real shape. Holds the role, logs it, reaches no client.
+  writeFileSync(
+    join(servicesDir, 'AnalyticsService.luau'),
+    'local RobloxAnalytics = game:GetService("AnalyticsService")\n'
+      + 'RobloxAnalytics:LogCustomEvent(player, "role_assigned", nil, { role = role })\n'
+  )
+  expect('rule 6 allows logging the role to Roblox telemetry', scan([join(servicesDir, 'AnalyticsService.luau')]).length === 0)
+
+  // ALLOW: a waiver still works, and shows up in a diff. Same contract as every other rule here.
+  writeFileSync(
+    join(servicesDir, 'AnalyticsService.luau'),
+    '-- secrecy-ok: deliberate, argued in review\nRemotes.Get("X"):FireAllClients(role)\n'
+  )
+  expect('rule 6 honours a waiver', scan([join(servicesDir, 'AnalyticsService.luau')]).length === 0)
+
+  // ALLOW: the rule is scoped to ONE file. A remote in any other service is rules 0-4's business.
+  writeFileSync(
+    join(servicesDir, 'RoundService.luau'),
+    'local Remotes = require(Shared.Remotes)\nRemotes.Get("PhaseChanged"):FireAllClients(phase)\n'
+  )
+  expect('rule 6 does not touch other services', scan([join(servicesDir, 'RoundService.luau')]).length === 0)
```

#### Step 3.3: The fifteen call sites

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run check:secrecy`

Each of the fifteen events emitted from the server module that already owns the fact. The two
sensitive ones — `role_assigned` and `player_killed` — follow Q2's rules exactly.

**The principle: emit from the module that already holds the fact.** Not from a central listener that
has to be told, because being told is a second data path and a second data path over the role is
exactly what this plan is trying not to build.

| # | Event | File | Anchor | Payload |
| --- | --- | --- | --- | --- |
| 1 | `player_joined` | `AnalyticsService.luau` | `Players.PlayerAdded` | — |
| 2 | `round_started` | `RoundService.luau` | `enterActive` (`:834`) | `playerCount` |
| 3 | `role_assigned` | `RoleService.luau` | beside the `RoleAssigned` fire (`:271-274`) | `role` |
| 4 | `task_completed` | `TaskService.luau` | `task.Completed = true` (`:1149`, `:1392`) | `type`, `secondsIntoRound` |
| 5 | `player_killed` | `RoundService.luau` | `MarkKilled` (`:920`), kill path only | `secondsIntoRound`, `wasIsolated` |
| 6 | `transform_witnessed` | `MonsterService.luau` | `announceTransform` (`:468`) | — |
| 7 | `salt_used` | `ItemService.luau` | where `Hit` is resolved (`:558`) | `hit` |
| 8 | `round_ended` | `RoundService.luau` | `enterEnding` (`:847`) | `winner`, `duration`, `survivorsAlive` |
| 9 | `player_left` | `AnalyticsService.luau` | `Players.PlayerRemoving` | `phase`, `secondsInSession` |
| 10 | `shop_opened` | `MonetizationService.luau` | `RequestOpenShop` handler | — |
| 11 | `purchase_completed` | `MonetizationService.luau` | after a `GRANT` in `processReceipt` | `productId` |
| 12 | `daily_claimed` | `DailyService.luau` | after a successful claim | `streak` |
| 13 | `trial_started` | `TrialService.luau` | `RequestStartTrial` success | — |
| 14 | `trial_completed` | `TrialService.luau` | trial resolution | — |
| 15 | `group_join_reward_claimed` | **C39, not this plan** | — | — |

**Event 15 is not wired by this plan, deliberately.** `group_join_reward_claimed` belongs in C39's
claim path, and C39 is being implemented in parallel — editing `CommunityService.luau` here would
collide with work in flight. The name exists in `pure/AnalyticsEvents`, so C39's one-line call
typechecks the moment it is written. **This is the one Appendix B event that will read zero after this
plan lands, and it will not be a defect.** Raised in Follow Ups so it is handed over rather than lost.

Events 10 and 11 land with Phase 4 and Phase 2's file respectively; the table lists all fifteen in one
place because "all 15 fire" is C40's Done condition and a reader needs the whole set.

**The two sensitive call sites, in full.** `role_assigned`, in `RoleService` beside the existing fire:

```diff
 		local payload: Types.RoleAssignedPayload =
 			{ Role = role }
 
 		Remotes.Get("RoleAssigned"):FireClient(player, payload)
+
+		--[[
+			C40, Appendix B: `role_assigned (role)`. THIS LINE CARRIES THE SECRET ON PURPOSE, and it
+			is safe for exactly one reason: `AnalyticsService.Emit`'s only egress is Roblox's own
+			telemetry backend, which is not a client. `check-secrecy` Rule 6 is what keeps that true —
+			the emitter cannot gain a remote without a diff to the check script.
+
+			DELIBERATELY THE STATEMENT AFTER THE FIRE, not a field on the payload above. Adding `role`
+			to a payload is what `PAYLOAD_FIELDS` exists to refuse; `RoleAssigned` already carries the
+			role to the one player it concerns and must carry nothing else (check-secrecy.mjs:90-92).
+		]]
+		AnalyticsService.Emit(player, AnalyticsEvents.Name.RoleAssigned, { role = role })
```

`player_killed`, in `RoundService.MarkKilled`, on the kill path only:

```diff
+	--[[
+		C40, Appendix B: `player_killed (secondsIntoRound, wasIsolated)`.
+
+		AGAINST AMENDMENT A3 (docs/MVP-SPEC.md:219-244), WHICH THIS LINE MUST NOT UNDO. A3 deleted the
+		global death signal — the `PlayerKilled` broadcast and `ClientRoundSnapshot.AlivePlayerCount` —
+		because "someone just died" plus replicated positions identifies the Aswang without anybody
+		witnessing a transform. `PlayerKilled` survives only as a FireClient to the victim alone.
+
+		THREE RULES, and each one is a way this line could go wrong:
+
+		  1. LOGGED AGAINST THE VICTIM, not the killer. `LogCustomEvent`'s first argument is a Player;
+		     passing the killer would attribute a per-player telemetry event to the Aswang.
+		  2. `wasIsolated` IS COMPUTED HERE AND GOES NOWHERE ELSE. It must not be added to the
+		     `PlayerKilled` payload "since we are computing it anyway" — that payload goes to the
+		     victim, who is about to become a ghost, and §4.7 bars a ghost from revealing the Aswang.
+		  3. NO BROADCAST. Adding `:FireAllClients` beside this line is the exact regression A3
+		     removed, and the two statements read alike.
+	]]
+	if causedByKill then
+		AnalyticsService.Emit(player, AnalyticsEvents.Name.PlayerKilled, {
+			secondsIntoRound = os.clock() - state.RoundStartedAt,
+			wasIsolated = livingSurvivorsNear(player) <= Config.Analytics.IsolationWitnesses,
+		})
+	end
```

`livingSurvivorsNear` is a small server-local helper counting living survivors within
`Config.Analytics.IsolationRadius` of the victim's last position. Both numbers join `Config` in a new
`Analytics` block; `IsolationWitnesses` defaults to `0` — *nobody else was near* — which is the
reading §4 implies by "isolated" and the one that will actually correlate with kills.

> **`wasIsolated` is a measurement, not a mechanic.** Nothing in the game may branch on it. If a future
> chunk wants to, that is a design change, not a refactor.

The join/leave pair, in `AnalyticsService.Start`:

```diff
+function AnalyticsService.Start()
+	Players.PlayerAdded:Connect(function(player)
+		joinedAt[player.UserId] = os.clock()
+
+		AnalyticsService.Emit(player, AnalyticsEvents.Name.PlayerJoined)
+		AnalyticsService.Step(player, AnalyticsEvents.Funnel.Steps.Joined)
+	end)
+
+	Players.PlayerRemoving:Connect(function(player)
+		local started = joinedAt[player.UserId]
+
+		--[[
+			`phase` IS PUBLIC — every client already receives `PhaseChanged` — so naming it here adds
+			nothing a player does not have. It is worth recording because §9.5's "% of joins that
+			reached an ACTIVE round" is answered by WHERE people leave, and if that number is low every
+			other retention figure is lying to you.
+
+			A PUSHED COPY, NOT `RoundService.GetPhase()`. See the note under this diff — reading it
+			would be a require cycle. The copy labels a metric and decides nothing, which is what makes
+			a copy acceptable at all: RoundService still owns the phase (§6.4).
+		]]
+		AnalyticsService.Emit(player, AnalyticsEvents.Name.PlayerLeft, {
+			phase = lastPhase,
+			secondsInSession = if started ~= nil then os.clock() - started else 0,
+		})
+
+		joinedAt[player.UserId] = nil
+	end)
+end
```

**Two things in that snippet are load-bearing and would otherwise be discovered the hard way.**

**1. `lastPhase` is a pushed copy, and it has to be.** `AnalyticsService` reading `RoundService` while
`RoundService` calls `AnalyticsService.Emit` is a **require cycle**, and `RoundService`'s own header
(`:26-28`) spells out what one costs in this repo: it errors at load, `init.server.luau` swallows it
into a single `warn`, and the server sits in IDLE forever looking exactly like "nobody has joined
yet". Break it the direction `ShutdownFlush` already does — **`AnalyticsService` requires nothing but
its own pure module**, which is also what keeps Rule 6's `ReplicatedStorage` clause satisfiable.
`RoundService` pushes on its existing `PhaseChanged` path:

```diff
+--[[
+	C40. PUSHED, NOT PULLED, and the direction is the whole point — see this file's header on require
+	cycles. `AnalyticsService` requires nothing, so it cannot ask; it is told.
+]]
+function AnalyticsService.SetPhase(phase: string)
+	lastPhase = phase
+end
```

`AnalyticsService` is first in `SERVICE_ORDER` (`init.server.luau:21`) and `RoundService` is last, so
the module reference resolves long before any push happens.

**2. `state.RoundStartedAt` does not exist yet.** `RoundService`'s state table has `PhaseEndsAt`
(`:52`) and no round-start timestamp — and `PhaseEndsAt` is per-*phase*, so deriving "seconds into the
round" from it works today by coincidence and silently starts measuring something else the first time
a duration is tuned. That is M12, which is the one milestone where these numbers are what you are
reading. Add the field, set it in `enterActive`:

```diff
 	PhaseEndsAt = 0,
+	--[[
+		C40. `os.clock()` at the moment ACTIVE began, for the `secondsIntoRound` field on
+		`task_completed` and `player_killed`. A SEPARATE FIELD FROM `PhaseEndsAt` on purpose: that one
+		is per-phase and moves with any duration tuned at M12.
+	]]
+	RoundStartedAt = 0,
```

#### Step 3.4: The funnel that matters, as `LogFunnelStepEvent`

**File:** `src/server/Services/AnalyticsService.luau`
**Verify:** `npm run verify:fast`

`joined → reached an ACTIVE round → completed a round → returned on day 2` as a four-step named
funnel, plus win rate per side, which Appendix A's <60% tuning target needs from day one.

This is the step BUILD-PLAN calls "the funnel that matters" (`docs/BUILD-PLAN.md:837-838`), and §9.5
says why step 2 in particular: **if the joined → ACTIVE rate is low, players are bouncing off an empty
lobby and every other retention number you have is lying to you.**

```diff
+--[[
+	THE FUNNEL (§9.5, BUILD-PLAN C40). A SEPARATE ROBLOX API from `LogCustomEvent`, because Roblox
+	models a funnel separately — `LogFunnelStepEvent` takes a funnel name and a step INDEX, and the
+	index is what orders the chart (`.luau-defs/globalTypes.d.luau:9231`).
+
+	NOT DEDUPLICATED HERE. A player who plays four rounds hits step 3 four times, and that is the
+	right shape for a funnel that measures a session's behaviour rather than a lifetime. Appendix B's
+	five BADGES are the lifetime-unique view of the same funnel and are C-something else's job; the
+	spec is explicit that badge counts are "unique-player lifetime totals, not daily rates", which is
+	exactly why both exist.
+]]
+function AnalyticsService.Step(player: Player, step: number)
+	local ok, err = pcall(function()
+		RobloxAnalytics:LogFunnelStepEvent(player, AnalyticsEvents.Funnel.Name, nil, step)
+	end)
+
+	if not ok then
+		warn(`[Analytics] funnel step {step} failed to log: {err}`)
+	end
+end
```

Steps 2 and 3 are driven from `RoundService`'s own transitions, which is where "reached an ACTIVE
round" and "completed a round" are facts rather than inferences:

```diff
+	--[[
+		C40 funnel step 2, §9.5's "% of joins that reached an ACTIVE round" — the number that decides
+		whether every other retention figure is meaningful. Fired for everyone DEALT IN, not everyone
+		present: a spectator who joined mid-round has not reached an active round in the sense that
+		matters.
+	]]
+	for _, player in dealtInPlayers() do
+		AnalyticsService.Step(player, AnalyticsEvents.Funnel.Steps.ReachedActiveRound)
+	end
```

**Step 4, "returned on day 2", is not emitted from a session event at all** — no server can observe a
return while it is happening, and `Players.PlayerAdded` fires long before there is a profile to ask.
It rides on **`ProgressionService.ProfileLoaded`**, which C35 added for exactly this shape:

```diff
+	--[[
+		C40 funnel step 4, "returned on day 2". ON `ProfileLoaded`, NOT `PlayerAdded`, and NOT on a
+		poll of `GetProfile`.
+
+		THE SECOND ARGUMENT IS THE ENTIRE REASON THIS WORKS, and its own declaration
+		(`ProgressionService.luau:60-72`) explains the trap it exists to avoid: `startSession` stamps
+		`FirstSeenUTC` for anyone who has none, so by the time a subscriber could read the LIVE
+		profile it already says "today", and a returning player would be indistinguishable from a new
+		one. `firstSeenBefore` is the pre-stamp value.
+
+		`dayIndex` COMES FROM `shared/pure/DailyStreak`, which already owns UTC-day arithmetic and has
+		a suite behind it. Inventing a second day boundary here would give the funnel and the streak
+		two definitions of "a day" that can disagree — silently, and only for players near midnight.
+
+		`firstSeenBefore <= 0` MEANS A BRAND NEW PLAYER, not a returning one: they had no stamp at all.
+		Guarding on it is what keeps step 4 from firing for everybody on their first ever join.
+	]]
+	ProgressionService.ProfileLoaded:Connect(function(player, firstSeenBefore)
+		if firstSeenBefore <= 0 then
+			return
+		end
+
+		if DailyStreak.dayIndex(firstSeenBefore) < DailyStreak.dayIndex(os.time()) then
+			AnalyticsService.Step(player, AnalyticsEvents.Funnel.Steps.ReturnedDayTwo)
+		end
+	end)
```

**This subscription is the reason `AnalyticsService` may require `ProgressionService` but still not
`RoundService`.** The cycle in Q2's note is specifically `RoundService ↔ AnalyticsService`;
`ProgressionService` does not require `AnalyticsService`, so this direction is safe — and
`ProgressionService` sits ahead of `RoundService` and behind `AnalyticsService` in `SERVICE_ORDER`,
which is why the push-not-pull rule applies to the phase and not to this.

`DailyStreak` is a `shared/pure/` module, so requiring it means naming `ReplicatedStorage` — which
**Rule 6 forbids in this file**. Resolve it by having `ProgressionService` pass the already-computed
answer, or by moving this one subscription into `ProgressionService`'s own module and calling
`AnalyticsService.Step` from there. **Flagged in Follow Ups as the one place Rule 6 and this
subscription genuinely collide**, rather than quietly waived — a `-- secrecy-ok:` on the emitter's
`ReplicatedStorage` line would reopen the whole egress surface the rule exists to close.

**Win rate per side** rides on `round_ended`'s existing `winner` field rather than a sixteenth event —
Appendix B has fifteen names and this plan does not add one. `round_ended (winner, duration,
survivorsAlive)` segmented by `winner` **is** the win rate, and Appendix A's target is that neither
side exceeds 60%.

> **This is the only place in the plan where a number is being collected in order to change the
> design.** M12 tunes `Config` until this ratio sits inside the band; a funnel that does not carry
> `winner` makes that milestone guesswork.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the whole phase, and the two call sites named in Step 3.3 are the ones to
  re-read. Rule 6 covers the emitter; **it does not cover the call sites**, so `RoleService` and
  `RoundService` still rely on rules 0–4 plus review. The specific regression to look for is a
  `FireAllClients` added *beside* an `Emit`, which is how a death oracle comes back.
- **Remote direction** — no remotes added in this phase. `AnalyticsService` must contain none at all;
  Rule 6 refuses one.
- **Rate limiting** — no new `OnServerEvent` handlers. The analytics calls added to existing handlers
  sit *after* those handlers' existing `AntiCheatService.Consume`, never before.
- **Magic numbers** — `Config.Analytics.IsolationRadius` and `IsolationWitnesses` are new tunables and
  must be read, not repeated. `check:config` governs both files.
- **Phase ownership** — `AnalyticsService.SetPhase` **stores** a phase; it must never be mistaken for
  setting one. Nothing outside `RoundService` calls `setPhase`, and the pushed copy decides nothing.
- **Player leaving mid-round** — `player_left` fires on `PlayerRemoving`, which runs while the player
  is still in `Players`. `joinedAt` is cleared there; without that the map leaks one entry per
  lifetime join.
- **Strict Luau** — `AnalyticsEvents.Name`'s fields must satisfy `Emit`'s `Event` parameter. Missing
  the `:: Event` casts in Phase 1 surfaces *here*, as a wall of analyze errors at the call sites,
  which reads as fifteen bugs rather than one.
- **Mobile budget** — nothing rendered; `Emit` is a bounded server call on discrete events, not a
  per-frame one. `task_completed` is the highest-frequency of them and it is once per task, not once
  per progress tick.
- **Scope** — nothing from §3's OUT list. Analytics observes; it must not add a mechanic.

**Issues identified:**

- **(High) `transform_witnessed` has no agreed definition, and the obvious one is a secrecy hazard.**
  Appendix B names the event and nothing defines "witnessed". Counting every client that received the
  `MonsterTransformed` broadcast measures *replication*, not witnessing. Counting players with line of
  sight means running a server-side visibility test per player per transform — new per-transform work,
  and a query whose *result* is a fact about who saw the Aswang. **Proposed:** emit once per transform,
  logged against the transforming player, with a `nearbyPlayers` count computed from the same radius
  `wasIsolated` uses. That measures the tell's reach without asking who saw it. Raised in Follow Ups
  as a decision, not settled here.
- **(Medium) Rule 6 protects the emitter, not the call sites.** A `FireAllClients` in `RoundService`
  beside the `player_killed` emit is caught by rules 0–4 only if its *payload text* names the secret —
  and A3's whole point is that a payload naming nobody (a bare "someone died") is already fatal.
  Nothing mechanical catches that. It is why Step 3.3's diff carries the three-rule comment, and why
  `exploit-auditor` is mandatory on this phase.
- **(Medium) Rule 6 forbids `ReplicatedStorage`, and funnel step 4 needs `shared/pure/DailyStreak`.**
  A genuine collision between two things this plan wants, not an oversight. Requiring a shared pure
  module means naming `ReplicatedStorage`, which Step 3.2's rule refuses. **Do not waive it** — the
  waiver would reopen the entire egress surface the rule exists to close, for a date comparison.
  Resolve it the other way: move the `ProfileLoaded` subscription into `ProgressionService`, which
  already requires `DailyStreak`, and have it call `AnalyticsService.Step`. Named in Follow Ups as a
  decision for the implementer rather than settled here, because it changes which file owns a
  subscription.
- **(Medium) `AnalyticsService` now has one legitimate service dependency.** `ProgressionService` for
  `ProfileLoaded`. That is safe — `ProgressionService` does not require `AnalyticsService` — but it
  means the "requires nothing" line in Step 3.1's header comment is no longer literally true and must
  be rewritten to say what it actually means: **no `RoundService`, and no path to a client.**
- **(Low) The funnel is not deduplicated per session.** Deliberate, and stated in the code comment so
  it is not "fixed" later: step 3 firing four times for four rounds is the intended shape.
- **(Low) `group_join_reward_claimed` will read zero.** C39 owns its call site. Handed over in Follow
  Ups.

#### Cannot be observed until C37 (Phase 3)

- **`purchase_completed (productId)`.** No product exists, so `processReceipt` never runs and this
  event never fires. Its call site is code that can be read and not behaviour that can be seen.
- **`shop_opened`** is observable only in the weak sense that Phase 4's remote can be fired; with a
  zeroed catalogue there is no shop to open in the product sense, though the panel path does run.

**Everything else in this phase IS observable without C37**, and this is the phase where a playtester
earns real evidence: thirteen of the fifteen events fire during an ordinary Studio round, and Roblox's
Creator Hub shows custom events for a published place. Two caveats a playtester must respect —
analytics requires Studio API access enabled (the same setting `ProgressionService` needs, per the C31
log), and **Creator Hub ingestion is not instant**, so "the event did not appear" after one minute is
not evidence that it did not fire.

Additionally, `group_join_reward_claimed` cannot be observed because **C39 owns it**, which is a scope
boundary rather than a C37 one.

### Phase 4: The end-screen shop surface

#### Step 4.1: Declare the three remotes in `Remotes.luau`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

`ShopOffer` DOWN; `RequestOpenShop` and `RequestPromptPurchase` UP. Each with the comment the file's
convention requires, naming what the payload may and may not carry.

**Q4 restated, because this phase is read alone.** §8.4: show the shop **on the end screen**, never
mid-round. Three mechanisms, in decreasing strength: (1) the client never touches `MarketplaceService`
— every prompt is server-initiated, and the client sends a catalogue **key**, never an id and never a
price; (2) the handler gates on `RoundService.GetPhase()`, which is server-only state nothing outside
`RoundService` sets; (3) `ShopOffer` has exactly one call site, in the `PhaseChanged`→ENDING
subscription, so a mid-round shop has no data to draw.

```diff
 	"RoundEnded", -- includes the reveal
 	"QuickChatBroadcast",
+	--[[
+		C38, §8.4. THE END-SCREEN SHOP'S OFFER LIST. FireClient, per player, ONE call site: the
+		`PhaseChanged` -> ENDING subscription in MonetizationService.
+
+		PER PLAYER AND NOT A BROADCAST, because the payload carries which gamepasses THAT player
+		already owns — so the offer list hides what they have. A broadcast would hand eight clients
+		eight players' purchase histories, which is the same mistake `ProfileUpdated`'s comment above
+		talks itself out of.
+
+		WHAT IT MAY CARRY: a list of `{ Key, Kind, Price, Owned }`. Key is a catalogue key, Price is
+		DISPLAY ONLY (Roblox owns the real price and no arithmetic reads this one), Owned is about the
+		receiving player alone. NO ROLE, NO USERID, NO ROUND STATE — it is fired at ENDING, when the
+		reveal has already gone out on `RoundEnded`, and it must not become a second channel for it.
+
+		THE ONE CALL SITE IS THE §8.4 ENFORCEMENT. A second one, anywhere, is how "never mid-round"
+		stops being structural and becomes a convention.
+	]]
+	"ShopOffer",
```

```diff
 	"RequestTrialThrow",
+	--[[
+		C38, §8.4. NO ARGUMENTS — it means "I opened the shop panel", and the server already knows
+		whose session it is.
+
+		THE ONLY REMOTE IN THIS GAME WHOSE SOLE EFFECT IS TELEMETRY, and that is worth saying out
+		loud. A lying client can fire it whenever the rate limit allows; what that buys is a corrupted
+		`shop_opened` count and nothing else — no state changes, no purchase is prompted, no
+		information comes back. The phase gate means a mid-round call is refused and therefore never
+		counted, so the metric stays a metric about the end screen.
+	]]
+	"RequestOpenShop",
+	--[[
+		C38, §8.2/§8.4. Carries a CATALOGUE KEY and nothing else — no product id, no price, no
+		quantity. Same absent-argument design as `RequestBuyCosmetic` above and for the same reason:
+		the server resolves the key against `Config.Monetization.Catalogue` and prompts with ITS id at
+		ITS price, so there is no number here for a compromised client to shrink and no id a client
+		could substitute for a cheaper product's.
+
+		THE PROMPT IS SERVER-INITIATED. `MarketplaceService:PromptProductPurchase(player, id)` and
+		`PromptGamePassPurchase(player, id)` both take a Player and are called from
+		MonetizationService; the client never touches MarketplaceService. That is mechanism 1 of the
+		three that keep §8.4 structural — the handler's ENDING phase check is mechanism 2.
+	]]
+	"RequestPromptPurchase",
```

#### Step 4.2: Budget the two new UP remotes

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

Entries in `Config.AntiCheat.Budgets` — required, because `AllowUnbudgetedRemote = false` refuses an
unbudgeted remote outright (`Config.luau:1085`) — plus the hand copy in the test's `UP_REMOTES`, which
pins both directions.

**A missing budget here does not fail open, it fails closed** — the remote is refused outright. So the
symptom of forgetting this step is "the shop button does nothing", with no error, which is why the
budgets table's own header requires every `EVENTS_UP` name to appear in it.

```diff
 			RequestTrialThrow = { Capacity = 3, RefillPerSecond = 0.2 },
+			--[[
+				C38. A PANEL OPENING, on a screen the player is already sitting on. Priced like
+				`RequestEquipCosmetic` rather than like a button press: an end screen invites browsing,
+				and a player who opens, closes and reopens the shop is behaving normally.
+
+				ITS ONLY EFFECT IS A METRIC, so what a spammer buys is a corrupted `shop_opened` count
+				and nothing else. The limiter is here to keep the count honest and the handler cheap,
+				not to protect state — there is no state behind it.
+			]]
+			RequestOpenShop = { Capacity = 5, RefillPerSecond = 0.5 },
+			--[[
+				C38. OPENS A ROBLOX PURCHASE PROMPT. Tighter than the panel above, because each call
+				puts a modal in front of the player: a handler that could be driven at speed is a way
+				to make the game unplayable for someone whose client has been compromised by a friend's
+				exploit script, and Roblox's own UI is not something this game can dismiss.
+
+				Priced like `RequestGhostSpook` — a deliberate, rare act. Capacity covers a double-tap
+				and a reconnect retry; nothing more.
+			]]
+			RequestPromptPurchase = { Capacity = 2, RefillPerSecond = 0.1 },
```

The hand copy in `tests/anti-cheat-budgets.test.luau`, whose header explains why the duplication is
the least-bad option (`:8-20` — `Remotes.luau` calls `game:GetService` at module scope, so Lune cannot
require it):

```diff
 	"RequestTrialThrow",
+	-- C38, §8.4. The end-screen shop's two remotes. `RequestOpenShop` is the only remote in this game
+	-- whose sole effect is telemetry; `RequestPromptPurchase` carries a catalogue key and no id.
+	"RequestOpenShop",
+	"RequestPromptPurchase",
```

#### Step 4.3: The two handlers — AntiCheat first, then the ENDING phase gate

**File:** `src/server/Services/MonetizationService.luau`
**Verify:** `npm run check:ratelimit`

`AntiCheatService.Consume` before any work (`AntiCheatService.luau:106`), then
`RoundService.GetPhase() ~= Enums.RoundPhase.Ending` → return. `RequestOpenShop` is argument-free and
its only effect is a `shop_opened` emit; `RequestPromptPurchase` carries a catalogue **key**.

**This step is mechanism 2 of Q4** — the one that makes §8.4 structural rather than conventional. The
phase is server-only state that nothing outside `RoundService` sets (`RoundService.luau:9-12`), so a
mid-round request is refused against a fact the client cannot influence.

```diff
+--[[
+	C38, §8.4. THE SHOP PANEL WAS OPENED. Argument-free, and its ONLY effect is one analytics event.
+
+	THE PHASE GATE IS NOT DEFENSIVE HERE, IT IS DEFINITIONAL. `shop_opened` is supposed to mean "a
+	player looked at the shop on the end screen", so a call arriving in ACTIVE is not a threat to
+	refuse — it is a measurement that would be WRONG to count. Refusing it keeps the metric a metric
+	about the end screen, which is the only thing §8.4 wants it to be.
+
+	WHAT A LYING CLIENT BUYS, stated plainly as `ReportGhostPosition`'s comment does: a corrupted
+	`shop_opened` count, bounded by the rate limit, and nothing else. No state changes, no prompt
+	opens, and nothing comes back — this handler returns no value at all.
+]]
+Remotes.Get("RequestOpenShop").OnServerEvent:Connect(function(player)
+	if not AntiCheatService.Consume(player, "RequestOpenShop") then
+		return
+	end
+
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Ending then
+		return
+	end
+
+	AnalyticsService.Emit(player, AnalyticsEvents.Name.ShopOpened)
+end)
+
+--[[
+	C38, §8.2/§8.4. PROMPT A PURCHASE. The client names a CATALOGUE KEY; the server resolves the id.
+
+	THE ABSENT ARGUMENTS ARE THE SECURITY DESIGN, exactly as `RequestBuyCosmetic`'s declaration says
+	of itself: there is no product id here for a client to substitute a cheaper product's, and no
+	price for one to shrink. `Config.Monetization.Catalogue` is the only source of both.
+
+	ORDER: rate limit, THEN phase, THEN resolve. Resolving first would do catalogue work on behalf of
+	a request that is about to be refused, and `check:ratelimit` reads the first thing in the handler
+	body for a reason.
+
+	THE ZEROED-ID NO-OP IS THE LAST GATE. Until a human does C37 every id is 0, and
+	`PromptProductPurchase(player, 0)` is a prompt for a product that does not exist. Returning
+	silently is correct and is what makes the whole surface safe to ship before C37.
+]]
+Remotes.Get("RequestPromptPurchase").OnServerEvent:Connect(function(player, key)
+	if not AntiCheatService.Consume(player, "RequestPromptPurchase") then
+		return
+	end
+
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Ending then
+		return
+	end
+
+	-- A client can send anything. `key` is untrusted until it resolves against the catalogue.
+	if type(key) ~= "string" then
+		return
+	end
+
+	local entry = Config.Monetization.Catalogue[key]
+
+	if entry == nil or entry.Id == 0 then
+		return
+	end
+
+	--[[
+		`pcall` because both prompts are web-backed and can throw, and a throw inside a remote handler
+		on the end screen would take down whatever else that thread was doing. A failed prompt is a
+		player who taps again.
+	]]
+	local ok, err = pcall(function()
+		if entry.Kind == "Gamepass" then
+			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
+		else
+			MarketplaceService:PromptProductPurchase(player, entry.Id)
+		end
+	end)
+
+	if not ok then
+		warn(`[Monetization] prompt failed for {player.Name}/{key}: {err}`)
+	end
+end)
```

**Both handlers are inside `MonetizationService.Start`**, not `Init` — they call `RoundService` and
`AnalyticsService`, and `init.server.luau`'s two-phase lifecycle exists so that cross-service calls
happen only after every `Init` has run.

**A require-direction note.** `MonetizationService` requires `RoundService`, and `RoundService` does
**not** require `MonetizationService` — one direction, the same rule `RoleService` follows
(`RoundService.luau:26-28`). Keep it that way: the ENDING push in Step 4.4 is a subscription
`MonetizationService` makes, never a call `RoundService` issues.

#### Step 4.4: Fire `ShopOffer` from the ENDING transition, and draw the panel

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `npm run verify`

One call site, in `MonetizationService`'s `RoundService.PhaseChanged` subscription. The client panel
renders what it is given and has no other source — mechanism 3 of Q4. With every id at `0` the offer
list is empty and the panel does not appear.

```diff
+	--[[
+		C38, §8.4. THE ONLY PLACE `ShopOffer` IS EVER FIRED, and that is mechanism 3 of the three that
+		keep the shop on the end screen. A second call site anywhere turns §8.4 from a structural
+		property back into a convention, which is what the placement rule is trying not to be.
+
+		PER PLAYER, because the payload says which passes THAT player owns. A broadcast would hand
+		eight clients eight players' purchase histories.
+
+		`OwnsGamepass` YIELDS on a cache miss, so this loop is spawned rather than run inline: eight
+		players times one `UserOwnsGamePassAsync` each would otherwise hold up the ENDING transition
+		behind a web call, and the end screen is the one moment §8.4 cares about being smooth.
+	]]
+	RoundService.PhaseChanged:Connect(function(phase: string)
+		if phase ~= Enums.RoundPhase.Ending then
+			return
+		end
+
+		for _, player in Players:GetPlayers() do
+			task.spawn(function()
+				local offers = {}
+
+				for key, entry in Config.Monetization.Catalogue do
+					--[[
+						EVERY ID IS 0 UNTIL C37, so this filter empties the list entirely and the
+						panel never appears. That is the correct behaviour of a correct
+						implementation, not a bug — see this plan's §1.2.
+					]]
+					if entry.Id ~= 0 then
+						table.insert(offers, {
+							Key = key,
+							Kind = entry.Kind,
+							Price = entry.Price,
+							Owned = MonetizationService.OwnsGamepass(player, key),
+						})
+					end
+				end
+
+				-- Nothing to show. Sending an empty list would make the client decide whether to draw
+				-- a shop, which is a decision the server is already holding the facts for.
+				if #offers == 0 then
+					return
+				end
+
+				Remotes.Get("ShopOffer"):FireClient(player, offers)
+			end)
+		end
+	end)
```

The client side is deliberately thin — **this is not the HUD chunk.** C26 owns the end screen's visual
design and `.claude/skills/ui-polish` is the authority on motion, thumb zones and scaling. What Phase 4
adds is the data path and one button, nothing styled:

```diff
+	--[[
+		C38, §8.4. The end-screen shop panel's DATA PATH ONLY — C26 owns how it looks.
+
+		THE CLIENT HAS NO OTHER SOURCE FOR THIS LIST, and that is the point rather than an
+		implementation convenience: `Config` is replicated, so a determined client could read the
+		catalogue itself, but it cannot learn WHICH passes it owns and it cannot make the server
+		prompt outside ENDING. The panel renders what it is handed.
+
+		NOTHING IS COMPUTED HERE. No price arithmetic, no ownership inference, no "you can afford
+		this" — the server sent `Price` for display and `Owned` as a fact.
+	]]
+	Remotes.Get("ShopOffer").OnClientEvent:Connect(function(offers)
+		UIController.ShowShopOffers(offers)
+	end)
```

**The buy button fires the remote and does nothing else** — no `MarketplaceService` call on the
client. That is mechanism 1 of Q4, and it is the line most likely to be "simplified" later by someone
who notices the client *could* prompt directly.

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — `ShopOffer` fires at ENDING, after `RoundEnded` has already carried the reveal.
  It must not become a second channel for it: no UserIds, no role, no round state. `Owned` is about
  the receiving player alone, which is why this is `FireClient` and never `FireAllClients`.
- **Remote direction** — `ShopOffer` in `EVENTS_DOWN` fired with `FireClient` and listened to with
  `OnClientEvent`; the two `Request*` in `EVENTS_UP` fired from the client and handled with
  `OnServerEvent`. `check:remotes` catches a name used but not declared — and the failure it prevents
  is the silent one: `WaitForChild` on a name the server never created **hangs forever**.
- **Rate limiting** — both new handlers call `AntiCheatService.Consume` as their first statement.
  `check:ratelimit` reads a 1200-character window from `OnServerEvent:Connect`, so the call must be
  near the top, and it should be first anyway.
- **Magic numbers** — the two budgets live in `Config.AntiCheat.Budgets`. `entry.Id == 0` and
  `#offers == 0` are idiomatic and allowed.
- **Phase ownership** — `MonetizationService` **reads** the phase and subscribes to `PhaseChanged`. It
  must never call `setPhase`, and the ENDING check is a read of `RoundService.GetPhase()` rather than
  a local copy that could drift.
- **Player leaving mid-round** — the `task.spawn` in the ENDING loop yields on `OwnsGamepass`. A
  player can leave during that yield, so `FireClient` may be called on a player no longer in
  `Players`. Re-check `player.Parent == Players` after the yield, the way `startSession` does
  (`ProgressionService.luau:215`).
- **Strict Luau** — the `PhaseChanged` handler receives a phase that arrives as plain `string` across
  the `BindableEvent` boundary; comparing it to `Enums.RoundPhase.Ending` is fine, but binding it to a
  `RoundPhase`-typed local needs a re-annotation. `pcall` over the prompt calls needs the `:: any`
  treatment CLAUDE.md describes.
- **Mobile budget** — a panel on the end screen, not during a chase, so it is outside §5's worst case.
  It still must not add lights or particles, and the offer list is at most five rows.
- **Scope** — §8.3. The catalogue is the whole surface and nothing in it may touch a round.

**Issues identified:**

- **(High) `PromptGamePassPurchase` appears callable from a LocalScript, so mechanism 1 is not a
  security boundary.** A modified client can open Roblox's purchase UI whenever it likes. The cost is
  the player's own Robux, `ProcessReceipt` still grants exactly once, and no round state changes — so
  **§8.4 is a conversion and placement rule for honest clients, enforced structurally by mechanism 2
  for every client that has not been modified.** Stated rather than papered over. The security level
  of those two methods is **not confirmed by anything in this repo** — the vendored definitions carry
  signatures but no security tags — and it is in Follow Ups as an unverified API claim.
- **(Medium) `ShopOffer` fires on ENDING and the end screen lasts `Config.Round.EndScreen` seconds.**
  A cache miss on `OwnsGamepass` costs a web call per player, so on a cold server the offers can
  arrive after the player has already seen the end screen without a shop. Not a correctness failure,
  but it is a conversion one, and §8.4's entire argument is about conversion. Warming the cache at
  `ProfileLoaded` instead is the obvious fix and is named in Follow Ups rather than added, because it
  changes when the web calls happen for every player on every join.
- **(Medium) `RequestOpenShop` is client-attested telemetry.** `shop_opened` counts what clients claim.
  The rate limit and the phase gate bound the lie, and the alternative — emitting server-side when
  `ShopOffer` is sent — measures *impressions* rather than *opens*, which is a different funnel
  number. Both are defensible; this plan picks opens because that is the Appendix B name. Collapsing
  the remote and measuring impressions instead is a one-line change and is offered in Follow Ups.
- **(Low) The panel does not appear at all before C37.** Correct behaviour, and the single most likely
  thing to be reported as a defect by anyone who did not read §1.2.

#### Cannot be observed until C37 (Phase 4)

- **The shop panel appearing.** Every catalogue id is `0`, the offer filter empties the list, and
  `ShopOffer` is never fired. **A playtester will see no shop on the end screen, and that is this
  phase working.**
- **Any purchase prompt.** `RequestPromptPurchase` returns at the `entry.Id == 0` guard before
  reaching `MarketplaceService`, so neither prompt method is ever called.
- **`purchase_completed`.** Still unreachable, for the same reason as in Phase 2.
- **Whether the offer list's `Owned` flags are correct.** `OwnsGamepass` returns `false` at its own
  zeroed-id guard without asking Roblox, so every flag is `false` and the correctness of the cache
  cannot be observed.

**What IS observable after this phase**, and what a playtester should be briefed to check instead:

- `npm run check:remotes` passes, which proves the three remotes are declared in the right direction
  lists — the failure mode that otherwise hangs a client's `WaitForChild` forever with no error.
- Firing `RequestOpenShop` during ACTIVE is refused and during ENDING is accepted. **This is the
  §8.4 phase gate, and it is fully testable without a single product existing** — it is the most
  valuable thing a playtester can establish in this phase.
- A round still cycles end to end with the new subscription attached, and the ENDING transition is not
  delayed by it.

## 3. Related Files

Every file below has an annotated review in `references/`, cited by line range. **An excerpt is a
frozen snapshot** — open the real file to see whether it has moved.

| File | Why it was read | Review |
| --- | --- | --- |
| `src/server/Services/MonetizationService.luau` | The C38 stub being replaced | `MonetizationService-review.luau` |
| `src/server/Services/AnalyticsService.luau` | The C40 stub being replaced | `AnalyticsService-review.luau` |
| `src/server/Services/ProgressionService.luau` | The profile API `ApplyReceipt` joins, and the two new BindableEvents | `ProgressionService-review.luau` |
| `vendor/ProfileStore.luau` | **`Save()` does not yield** — the finding that shaped Q1 | `ProfileStore-review.luau` |
| `src/shared/Types.luau` | `Purchases.GamepassCacheUTC`'s cache-not-entitlement rule | `Types-review.luau` |
| `src/shared/pure/ProfileMigration.luau` | v2 is spent; the v3 bump and the future-version refusal | `ProfileMigration-review.luau` |
| `src/shared/Remotes.luau` | The declaration convention and the payload traps already documented there | `Remotes-review.luau` |
| `src/shared/Config.luau` | `Badges`/`Community` zeroed-id precedent, `AntiCheat.Budgets` fail-closed rule | `Config-review.luau` |
| `src/server/Services/RoundService.luau` | Phase ownership, the require-cycle warning, no round-start timestamp | `RoundService-review.luau` |
| `.claude/scripts/check-secrecy.mjs` | What it scans and what it cannot — the gap Rule 6 fills | `check-secrecy-review.luau` |
| `.luau-defs/globalTypes.d.luau` | `ProcessReceipt`, the prompts, and Roblox's own `AnalyticsService` | `globalTypes-review.luau` |
| `docs/MVP-SPEC.md` | §8.2/§8.3/§8.4, §6.6, Appendix B, Amendment A3 | `MVP-SPEC-review.luau` |

**Not read, deliberately:** `CosmeticsService.luau`, `DailyService.luau`, `CommunityService.luau` and
`TrialService.luau` beyond locating their analytics anchors. Their call sites are one line each and
the brief scoped this plan to C38 and C40.

## 4. Follow Ups

### Questions / Clarifications

1. **`receiptInfo`'s field names are unverified.** `.luau-defs/globalTypes.d.luau:14069` types the
   argument as `{ [string]: any }`, so `PurchaseId`, `PlayerId` and `ProductId` come from Roblox's
   documentation and **nothing in this repo confirms them**. The handler refuses rather than assumes,
   so a wrong name degrades to `NotProcessedYet` rather than to a wrong grant. **This is the single
   most important thing for a human to confirm when C37 is done.**
2. **Whether Roblox serialises concurrent `ProcessReceipt` calls for one player** is unverified, and
   `waitForDurableReceipt` yields inside the callback. The design is safe under either answer — a
   concurrent re-delivery either reads the live ring and answers `DUPLICATE`, or produces a second
   `GRANT` whose `Receipts.record` is idempotent — but that is reasoning, not evidence.
3. **The security level of `PromptGamePassPurchase` / `PromptProductPurchase` is unverified.** Both
   take a `Player` and are called server-side here. If a LocalScript can also call them, §8.4's
   "never mid-round" is a rule for honest clients only, which is how this plan describes it.
4. **`transform_witnessed` has no agreed definition.** Appendix B names it; nothing says what
   "witnessed" means. Proposed: once per transform, logged against the transforming player, with a
   `nearbyPlayers` count from the same radius `wasIsolated` uses — measuring the tell's reach without
   asking who saw it. **A decision, not a detail.**
5. **Rule 6 and funnel step 4 collide.** The emitter may not name `ReplicatedStorage`, and
   `shared/pure/DailyStreak` lives there. Move the `ProfileLoaded` subscription into
   `ProgressionService` rather than waiving the rule. Which file owns that subscription is the
   implementer's call; **waiving Rule 6 is not.**
6. **`group_join_reward_claimed` is not wired by this plan.** It belongs to C39's claim path, which is
   in flight in parallel. The name exists in `pure/AnalyticsEvents` so C39's one-line call typechecks
   the moment it is written. **This event will read zero after this plan lands and that is not a
   defect** — it is a handoff.
7. **Warming the gamepass cache at `ProfileLoaded`** would remove the web-call latency from the ENDING
   transition. Not done here because it changes when web calls happen for every player on every join,
   which is a cost worth deciding deliberately rather than inheriting.
8. **`shop_opened` measures opens, not impressions**, and needs a client-attested remote to do so.
   Collapsing `RequestOpenShop` and emitting server-side when `ShopOffer` is sent is a one-line change
   that trades the Appendix B name's literal meaning for one fewer remote.
9. **`ProfileMigration`'s `MAX_RECEIPTS` duplicates `Config.Monetization.ReceiptHistory`** by
   necessity — a `shared/pure/` module may not require `Config`. `MAX_OWNED_COSMETICS` sets the
   precedent. An assertion pinning the two would need `ProfileMigration` to export the constant.
10. **A check that parses `Remotes.luau` and `Config.AntiCheat.Budgets` together** would retire the
    hand copy in `tests/anti-cheat-budgets.test.luau`. Named in that file's own header as the clean
    fix and deferred there too; noted again because this plan adds two more entries to the hand copy.
11. **Nothing guards against a second `MarketplaceService.ProcessReceipt` assignment.** It is a field,
    not a signal, so a second one silently replaces the first and purchases are answered by whichever
    module loaded last. A one-line addition to `check:remotes`' neighbourhood would catch it.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 1 | `MAX_RECEIPTS` duplicates a Config number; a `shared/pure/` module cannot require `Config` | Low | Accepted — precedent is `MAX_OWNED_COSMETICS`; waiver required |
| 1 | `Receipts.Ring == nil` and `ReadOnly` are indistinguishable to the caller | Low | Resolved in Phase 2 — `ApplyReceipt` logs which |
| 1 | v3 bump latches v3 players read-only on v2 servers during a staged deploy | Medium | Accepted deliberately — `NotProcessedYet` beats a double grant |
| 2 | `receiptInfo` field names unverified | Medium | Open — Q1 above; degrades safely |
| 2 | Concurrent `ProcessReceipt` behaviour unverified while the callback yields | Medium | Open — Q2 above; safe under either answer |
| 2 | A second `ProcessReceipt` assignment would silently win | Low | Open — Q11 above |
| 3 | `transform_witnessed` undefined by the spec | High | Open — Q4 above; needs a decision before implementation |
| 3 | Rule 6 protects the emitter, not the call sites | Medium | Mitigated — three-rule comment at the call site; `exploit-auditor` mandatory |
| 3 | Rule 6 forbids `ReplicatedStorage`; funnel step 4 needs `DailyStreak` | Medium | Open — Q5 above; do not waive |
| 3 | `AnalyticsService` now requires `ProgressionService`, so "requires nothing" is untrue | Medium | Fix in Step 3.1's header comment |
| 3 | `group_join_reward_claimed` will read zero | Low | Handed to C39 — Q6 above |
| 4 | Client-side `PromptGamePassPurchase` defeats mechanism 1 | High | Accepted — §8.4 is a conversion rule; mechanism 2 is the structural one |
| 4 | `OwnsGamepass` latency can delay `ShopOffer` past the end screen | Medium | Open — Q7 above |
| 4 | `shop_opened` is client-attested | Medium | Accepted — bounded by rate limit and phase gate; Q8 offers the alternative |
| 4 | `FireClient` may run after the player left, across the `OwnsGamepass` yield | Medium | Fix in Step 4.4 — re-check `player.Parent == Players` |
