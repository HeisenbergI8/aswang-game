# Plan: C02–C04 — Rate Limit, the Secret, and the Transform

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M2 (docs/MVP-SPEC.md §12), covering `docs/BUILD-PLAN.md` chunks **C02, C03, C04**
- **Description:** Build the rate-limit core first so every later remote handler is born compliant
  (`AntiCheatService` + `pure/TokenBucket`), then the secret role draw (`RoleService` + a **server-only**
  `pure/RoleDraw`), then the public transform (`MonsterService` + `pure/TransformRules`). Three chunks,
  one plan, in strict dependency order. Each chunk's own **Done** and **Verify** lines from
  `docs/BUILD-PLAN.md` survive verbatim as a phase gate so the boundaries cannot blur.
- **Date:** 2026-08-10
- **Branch:** `m1-round-state-machine` (C01 landed at `dc06307`)
- **What the client is told:**
  - **C02 — nothing new.** A refusal is logged server-side only. The refusing player is not told, and no
    other client learns anything. (Kicking and player-facing feedback are C41.)
  - **C03 — exactly one new thing, to exactly one player.** `RoleAssigned` fires with
    `Types.RoleAssignedPayload = { Role: Role }` via `:FireClient(player, payload)`. It carries the
    receiver's **own** role and nothing else — no UserId, no roster, no count, no seed, no history.
    Every other client learns **nothing**: no attribute, no tag, no Highlight, no speed change, no tool,
    no sound, no snapshot field. `ClientRoundSnapshot.YourRole` stays **unset** (see the C01 comment in
    `RoundService.buildSnapshot`) — one carrier is auditable in a way that two are not.
  - **C04 — the transform, publicly and deliberately.** `MonsterTransformed` fires to **all** clients
    with `{ Character: Model, Transformed: boolean }`. This is the one thing in the game that
    legitimately reveals the Aswang (§4.3), and it reveals it only **at the moment of transforming** —
    not before, and only to players who can see or hear it. The payload carries a character, never a
    role string and never a UserId that is not already visible in the workspace.

### 1.1 The open design question, decided

**Decision: `src/server/pure/RoleDraw.luau`. Not `src/shared/pure/`.**

Reasoning, and why the cheaper option was rejected:

- `default.project.json` maps `src/shared` **wholesale** into `ReplicatedStorage`, so every module under
  `src/shared/pure/` is `require()`-able **and callable** by any client. That is stated in
  `docs/BUILD-PLAN.md` §12 and was measured this session.
- The published algorithm is not the risk. **Algorithm + inputs + seed = this round's assignment.** An
  exploiter who can reproduce all three knows the Aswang *before the round starts*, with no remote to
  intercept and nothing for `check:secrecy` to see — it is the one leak in this game that leaves no
  trace on the wire.
- `src/shared/pure/` + server-only entropy is *sufficient* and is what C03 proposes. It is rejected here
  because it is sufficient **only while every future edit keeps it sufficient**. It puts the draw's code
  one careless `Random.new(state.RoundNumber)` away from total compromise, in a file that replicates,
  guarded by nothing mechanical. `src/server/pure/` removes the entire class: the module does not
  replicate, so the client cannot call it even with a correct seed guess.
- **The server location costs no testability**, which is the only reason `pure/` exists. Lune resolves
  test requires by **file path** and knows nothing about Rojo:
  `require("../src/server/pure/RoleDraw")` works exactly as `require("../src/shared/pure/RoundTransitions")`
  already does in `tests/round-transitions.test.luau`. Verified by reading the existing test, not assumed.
- **Both rules from C03's warning block are kept anyway**, because defence in depth is the point:
  - **Server-only entropy.** `Random.new()` with no argument, created once in `RoleService.Init()`. Never
    `Random.new(state.RoundNumber)`, never `Random.new(os.time())`, never `os.clock()`.
  - **The history never replicates.** It is a module-local table in `RoleService`, keyed by UserId,
    server-only, in-memory (disk is C31). It is **a draw input**, so it is treated as secret even though
    every past Aswang was already revealed by `RoundEnded` — every input a client holds shrinks the
    search space for the seed it does not.

**Two measured consequences of the server location, both of which the plan handles:**

1. `check-config.mjs` governs `src/(server|client)/` and **not** `src/shared/`. So `src/server/pure/RoleDraw.luau`
   *is* subject to `check:config`, while `src/shared/pure/TokenBucket.luau` is not. This is a benefit, not a
   cost: the anti-repeat weights are balance knobs (§4.2 "heavily reduced weight", Appendix A tuning), so
   they belong in `Config.Roles` and must be **passed in as a parameter**. Step 4.3 gates on exactly this.
2. It deviates from `tests/README.md`, which says pure modules live in `src/shared/pure/`. That file is
   updated in Step 4.4 to name both locations and the rule that chooses between them. `CLAUDE.md` and
   `docs/BUILD-PLAN.md` carry the same wording and are raised in **Follow Ups** rather than edited here.

**The rule this establishes, for every future pure module:** a pure module goes in `src/shared/pure/` by
default; it goes in `src/server/pure/` when **an input or the output is secret**. `TokenBucket` and
`TransformRules` publish nothing `Config.luau` does not already replicate, so they stay in `shared`.
`RoleDraw` decides the secret, so it does not. `TaskSelection` (C07) is the next module that will have to
answer this question — a client-derivable task set is a pacing advantage, not a game-ender, so it is a
judgement call and is flagged in Follow Ups rather than pre-decided here.

### 1.2 Phase map and chunk boundaries

| Phase | Chunk | What lands | Gate |
| --- | --- | --- | --- |
| 1 | shared | `Config.AntiCheat`, `Config.Roles` weights, `Types`, remote-surface audit | `npm run verify` |
| 2 | C02a | `pure/TokenBucket.luau` + its test | `npm run test:unit` |
| 3 | **C02** | `AntiCheatService` | **C02 gate** — `npm run verify` |
| 4 | C03a | `src/server/pure/RoleDraw.luau` + its test | `npm run test:unit` |
| 5 | **C03** | `RoleService`, `RoundService` wiring, the private intro | **C03 gate** — `npm run verify` + `exploit-auditor` |
| 6 | C04a | `pure/TransformRules.luau` + its test, `MonsterService` handler | `npm run verify:fast` |
| 7 | **C04** | forced revert, client reaction, spectator containment | **C04 gate** — two clients in Studio |

Seven phases, and the task loop drives roughly one per iteration with a cap of 8. This fits in one run
with one iteration of slack. It does not fit with two.

### 1.3 Three constraints that shape every phase

- **`RoundService` owns the phase.** Nothing added here calls `setPhase`. `RoleService` is *called by*
  `enterStarting`; `MonsterService` *subscribes to* `RoundService.PhaseChanged`. Neither drives it.
- **Every `OnServerEvent` consults `AntiCheatService` first.** `check-ratelimit.mjs` matches
  `/\bAntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)\b/` within 1200 characters of the
  `.OnServerEvent:Connect(`. The `Consume` name and the guard's position at the top of the handler are
  therefore both load-bearing, not stylistic.
- **`RequestTransform` in Phase 6 is the first real `OnServerEvent` handler in the repo.**
  `check:ratelimit` has passed vacuously until now. Step 6.3 is the moment it starts meaning something,
  which is why it is that step's gate.

## 2. Comprehensive Plan by Phases

### Phase 1: Foundation — Config, Types, and the remote surface

Nothing gameplay-facing lands here. This phase exists so that Phases 2–7 never have to add a number, a
type or a remote mid-flight, and so `check:config` is satisfiable from the first line of service code.

#### Step 1.1: Add the `Config.AntiCheat` section and pin every budget with a test

**File:** `src/shared/Config.luau`, `tests/anti-cheat-budgets.test.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

A per-remote budget for every one of the eight names in `Remotes.EVENTS_UP`, plus the bucket defaults and
the `LogOnly` switch, with a test that fails when a remote is added without a budget.

```diff
 	Performance = {
 		-- Mobile is ~60% of players. Many dynamic lights is the #1 mobile FPS killer.
 		MaxVisibleLights = 8,
 		TargetFPSMobile = 30,
 	},
 
+	--[[
+		Rate limits, one budget per client->server remote (C02).
+
+		A budget is a token bucket: `Capacity` tokens, refilling at `RefillPerSecond`, one token per
+		request. Capacity is the BURST a legitimate player may produce in one moment; RefillPerSecond is
+		the SUSTAINED rate they may hold.
+
+		Tune these LOOSER than legitimate play, never tighter. A limiter that refuses a real player is a
+		gameplay bug that presents as lag, and it is far more expensive than an exploiter getting three
+		extra requests through — the validation behind the limiter is what actually refuses them.
+		`tests/anti-cheat-budgets.test.luau` pins that relationship for the remotes where a legitimate
+		cadence is known.
+	]]
+	AntiCheat = {
+		-- Every name here must appear in Remotes.EVENTS_UP, and every name there must appear here.
+		-- The test pins BOTH directions, because a budget for a remote that no longer exists is a
+		-- rename nobody noticed and a remote with no budget is refused outright (see UnknownRemote).
+		Budgets = {
+			-- A presence heartbeat while standing at a task point. Must out-pace the snapshot tick or
+			-- a player holding a task is throttled while doing exactly what the game asked of them.
+			RequestTaskProgress = { Capacity = 12, RefillPerSecond = 6 },
+			-- Deliberate, rare acts. Capacity covers a double-tap and a reconnect retry; nothing more.
+			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
+			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
+			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
+			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
+			RequestGhostSpook = { Capacity = 2, RefillPerSecond = 0.05 },
+			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
+			RequestClaimDaily = { Capacity = 2, RefillPerSecond = 0.1 },
+		},
+
+		-- One request costs one token. Here rather than in the service so C41 can price an expensive
+		-- handler higher without touching code.
+		DefaultCost = 1,
+
+		-- FAIL CLOSED. A remote with no budget is refused, not allowed. The alternative — allowing the
+		-- unknown — means a new remote added without a budget is silently unlimited, which is exactly
+		-- the state C02 exists to make impossible.
+		AllowUnbudgetedRemote = false,
+
+		-- C02 LOGS. C41 ENFORCES. Kicking on a rate limit before there is real data behind the numbers
+		-- kicks real players on bad connections, and a false kick is unrecoverable.
+		LogOnly = true,
+		-- One log line per player per remote per this many seconds. An exploiter firing 1000/s would
+		-- otherwise produce 1000 warn() calls per second, which is its own denial of service.
+		LogThrottleSeconds = 5,
+	},
+
 	Debug = {
```

```luau
--!strict
--[[
	tests/anti-cheat-budgets.test.luau

	Every client->server remote has a rate-limit budget, and every budget belongs to a real remote.

	WHY THE NAME LIST IS DUPLICATED HERE, AND WHY THAT IS THE LEAST-BAD OPTION
	--------------------------------------------------------------------------
	`src/shared/Remotes.luau` calls `game:GetService` at module scope, so Lune cannot require it — there
	is no DataModel. The list below is therefore a hand copy, and a hand copy can drift.

	It is still worth having, because drift in the direction that matters is caught from the other side:
	`check:remotes` fails on any remote used but not declared in Remotes.luau, and the EXTRA_BUDGETS
	assertion below fails on any budget naming a remote this list does not carry. What survives both is
	the narrow case of a remote added to Remotes.luau and to nothing else — which the C41 sweep
	("every OnServerEvent handler consults AntiCheatService") is the real answer to.

	The clean fix is a check script that parses both files. It is named in the plan's Follow Ups rather
	than built here, because C02 is not the chunk that should be growing the harness.
]]

local Config = require("../src/shared/Config")

-- Hand copy of Remotes.EVENTS_UP as of C02. See the header for why.
local UP_REMOTES = {
	"RequestTaskProgress",
	"RequestTransform",
	"RequestKill",
	"RequestThrowSalt",
	"RequestQuickChat",
	"RequestGhostSpook",
	"RequestEquipCosmetic",
	"RequestClaimDaily",
}

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

--------------------------------------------------------------------------------
-- Coverage, both directions
--------------------------------------------------------------------------------

for _, name in UP_REMOTES do
	local budget = Config.AntiCheat.Budgets[name]

	check(`{name} has a declared budget`, budget ~= nil)

	if budget then
		check(`{name} allows at least one request`, budget.Capacity >= 1, `Capacity={budget.Capacity}`)
		check(
			`{name} refills, so the bucket is not a one-shot`,
			budget.RefillPerSecond > 0,
			`RefillPerSecond={budget.RefillPerSecond}`
		)
	end
end

local declared = {}
for _, name in UP_REMOTES do
	declared[name] = true
end

for name in Config.AntiCheat.Budgets do
	check(`the budget for {name} names a remote that exists`, declared[name] == true)
end

--------------------------------------------------------------------------------
-- The relationships. A limiter tighter than legitimate play is a gameplay bug.
--------------------------------------------------------------------------------

-- Spec §4.4: task progress is reported as PRESENCE while the server accumulates. A player standing at
-- a task point reports at least as often as the HUD updates, so a slower refill throttles correct play.
check(
	"task progress refills faster than the snapshot tick",
	Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond >= 1 / Config.Round.SnapshotInterval,
	`refill={Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond}`
)

-- Spec §4.3: the Aswang may transform once per kill cycle. One token must be available at least that
-- often or the limiter, not the cooldown, becomes the thing gating the monster.
check(
	"a transform token is available well inside the kill cooldown",
	1 / Config.AntiCheat.Budgets.RequestTransform.RefillPerSecond <= Config.Monster.KillCooldown,
	`{1 / Config.AntiCheat.Budgets.RequestTransform.RefillPerSecond}s per token`
)

-- Spec §4.6: one pouch carried at a time, so a burst larger than the carry limit is never legitimate —
-- but it must at least cover it, plus a retry.
check(
	"salt throws burst at least as far as the carry limit",
	Config.AntiCheat.Budgets.RequestThrowSalt.Capacity >= Config.Salt.CarryLimit
)

-- Spec §4.7: one spook per round. Capacity below that refuses the feature outright.
check(
	"the ghost can afford its one spook",
	Config.AntiCheat.Budgets.RequestGhostSpook.Capacity >= Config.Ghost.SpooksPerRound
)

--------------------------------------------------------------------------------
-- The policy switches
--------------------------------------------------------------------------------

-- C02 is log-only by design; C41 turns this off with real data behind it. Pinned so that flipping it
-- early is a deliberate act that breaks a test rather than a quiet edit.
check("rate limiting is still log-only until C41", Config.AntiCheat.LogOnly == true)

-- Fail closed. See the Config comment.
check("an unbudgeted remote is refused", Config.AntiCheat.AllowUnbudgetedRemote == false)

check("a request costs at least one token", Config.AntiCheat.DefaultCost >= 1)

if failures > 0 then
	error(`{failures} anti-cheat budget failure(s)`, 0)
end

print(`  PASS  anti-cheat-budgets: {#UP_REMOTES} remotes budgeted + 7 invariants`)
```

#### Step 1.2: Add the role-draw weights and pin their relationships

**File:** `src/shared/Config.luau`, `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

`Config.Roles` gains the anti-repeat weights. The existing balance-invariant suite gains the assertions
that make "heavily reduced" (§4.2) a checkable statement rather than a word.

```diff
 	Roles = {
 		AswangCount = 1,
 		-- A player who was Aswang recently gets reduced weight in the draw.
 		-- Nothing kills a session faster than never being the monster.
 		RepeatCooldownRounds = 2,
 		IntroDuration = 3,
+
+		--[[
+			The anti-repeat weights (§4.2 "heavily reduced weight"). A player's draw weight is picked by
+			how many rounds ago they were last the Aswang:
+
+				1 round ago                        -> RecentAswangWeight
+				2..RepeatCooldownRounds rounds ago -> OlderAswangWeight
+				never, or longer ago               -> BaseWeight
+
+			NONE OF THESE MAY BE ZERO. A zero weight is not "unlikely", it is "impossible", and with
+			MinPlayers = 3 a zero-weight rule can leave a round with no eligible Aswang at all. The draw
+			would then have to fall back to something, and a fallback that fires under a condition
+			nobody tested is worse than a small number. `tests/role-draw.test.luau` proves no player
+			starves; `tests/config.test.luau` proves the numbers stay ordered and positive.
+		]]
+		BaseWeight = 1,
+		RecentAswangWeight = 0.1,
+		OlderAswangWeight = 0.4,
 	},
```

```diff
 -- Spec §5: many dynamic lights is the #1 mobile FPS killer, and 60% of players are on mobile.
 check("the mobile light budget is still capped", Config.Performance.MaxVisibleLights <= 8)
 
+-- Spec §4.2: the anti-repeat weighting must be MONOTONIC in recency — more recent means less likely —
+-- and never zero. Three numbers in the wrong order still draw an Aswang every round, so nothing about
+-- the game looks broken; the only symptom is players quietly being the monster twice in a row.
+check(
+	"a more recent Aswang is less likely than an older one",
+	Config.Roles.RecentAswangWeight < Config.Roles.OlderAswangWeight,
+	`recent={Config.Roles.RecentAswangWeight}, older={Config.Roles.OlderAswangWeight}`
+)
+
+check(
+	"any recent Aswang is less likely than someone who has never been one",
+	Config.Roles.OlderAswangWeight < Config.Roles.BaseWeight,
+	`older={Config.Roles.OlderAswangWeight}, base={Config.Roles.BaseWeight}`
+)
+
+-- Zero is a ban, not a discount. See the Config comment.
+check(
+	"nobody is ever excluded from the draw outright",
+	Config.Roles.RecentAswangWeight > 0,
+	`recent={Config.Roles.RecentAswangWeight}`
+)
+
+-- Spec §4.2: history covers the last 2 rounds. A history as long as the server is large would give
+-- every player a reduced weight at once, which is the same as no weighting at all.
+check(
+	"the anti-repeat history is shorter than a full server",
+	Config.Roles.RepeatCooldownRounds >= 1
+		and Config.Roles.RepeatCooldownRounds < Config.Round.MaxPlayers,
+	`RepeatCooldownRounds={Config.Roles.RepeatCooldownRounds}`
+)
+
+-- Spec §4.2 / §3: exactly one Aswang, and at least two survivors at the minimum player count — a
+-- round drawn with AswangCount >= MinPlayers is over before ACTIVE begins.
+check(
+	"a minimum-sized round still has survivors in it",
+	Config.Roles.AswangCount < Config.Round.MinPlayers,
+	`AswangCount={Config.Roles.AswangCount}, MinPlayers={Config.Round.MinPlayers}`
+)
+
+-- Spec §4.2: the 3-second private intro plays during STARTING. If it outlasts StartingDelay it is
+-- still on screen when ACTIVE begins, and the Aswang spends the opening seconds of the round reading
+-- a card instead of moving — the one moment when standing still is most conspicuous.
+check(
+	"the Aswang intro finishes before the round goes live",
+	Config.Roles.IntroDuration < Config.Round.StartingDelay,
+	`IntroDuration={Config.Roles.IntroDuration}, StartingDelay={Config.Round.StartingDelay}`
+)
+
 -- Spec §6.5 / README: shipping with SoloTesting on skips MinPlayers for everyone.
 check(
 	"solo testing is off",
 	Config.Debug.SoloTesting == false,
 	"this must never be true on a published place"
 )
 
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end
 
-print("  PASS  config: 13 balance invariants")
+print("  PASS  config: 19 balance invariants")
```

> **NOTE** the final `print` count. It is prose, not an assertion, and nothing fails if it is wrong —
> which is exactly why it gets missed. Six checks are added, so 13 becomes 19.

#### Step 1.3: Add the four new types

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

`TokenBucketState`, `RoleAssignedPayload`, `MonsterTransformedPayload`, `TransformVerdict`. Each is the
contract for something that crosses a boundary in a later phase.

```diff
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

Added above `RoundState`:

```diff
+--[[
+	One player's bucket for one remote (C02). Server-only state; it is never sent anywhere, and it is
+	declared here rather than inside AntiCheatService so `pure/TokenBucket.luau` and the service agree
+	on the shape without the pure module having to require anything.
+
+	The bucket carries its OWN capacity and refill rate rather than taking a budget alongside. That is
+	what lets `TokenBucket.consume` have exactly the signature C02 asks for — `(bucket, now, cost) ->
+	(allowed, newBucket)` — with no fourth argument that every caller has to look up and can get wrong.
+	The values are copied out of Config.AntiCheat.Budgets when the bucket is created.
+
+	`LastRefillAt` is an os.clock() timestamp, and os.clock() is NOT guaranteed monotonic across a
+	Roblox server's lifetime. TokenBucket.consume handles a value in the future; see Step 2.1.
+]]
+export type TokenBucketState = {
+	Tokens: number,
+	LastRefillAt: number,
+	Capacity: number,
+	RefillPerSecond: number,
+}
+
+--[[
+	THE payload for the one remote allowed to carry a role, and the reason it has exactly one field.
+
+	`RoleAssigned` is fired to a single player with `:FireClient`, so it is on check-secrecy.mjs's
+	REVEAL_ALLOWLIST — which means the scanner SKIPS the call entirely rather than inspecting it. Read
+	the RoundEndedPayload comment above: an EXTRA field on an annotated table is accepted silently by
+	the typechecker too. So both guards are off here, and this type is documentation backed by a habit.
+
+	Concretely, the fields that must never appear: a UserId (the receiver already knows who they are),
+	a roster, a survivor count, a round seed, the draw history, or the other players' roles. Any of
+	them turns a private message into a broadcast the moment a client is compromised — which, for the
+	player who IS the Aswang, is the case that matters least, and for everyone else is the whole game.
+]]
+export type RoleAssignedPayload = {
+	Role: Role, -- the RECEIVING player's own role, and nothing else
+}
+
+--[[
+	The transform broadcast (§4.3). PUBLIC BY DESIGN — this is the one thing in the game that
+	legitimately reveals the Aswang, and replicating it is correct rather than tolerated.
+
+	It carries a Model that is already in the workspace and already replicated. It does NOT carry a
+	role string: "this character transformed" is a fact about the world, while "this player is the
+	Aswang" is an inference the client is welcome to make and the server never states. The distinction
+	matters at C14, where salt forces a revert — a reverted player is still the Aswang, and nothing in
+	this payload says so.
+]]
+export type MonsterTransformedPayload = {
+	Character: Model,
+	Transformed: boolean, -- true on transform, false on revert
+}
+
+--[[
+	The verdict from `pure/TransformRules.luau` (C04). A literal union rather than a boolean so the
+	server can log WHY it refused — an exploiter probing the boundary and a real player hitting a
+	cooldown look identical in a boolean, and telling them apart is what C41 needs.
+
+	NOT_ALIVE covers the spectator-containment case carried over from C01; it is wired at Step 7.2.
+]]
+export type TransformVerdict =
+	"OK"
+	| "NOT_ASWANG"
+	| "WRONG_PHASE"
+	| "NOT_ALIVE"
+	| "ALREADY_TRANSFORMED"
+	| "ON_COOLDOWN"
+
```

> **IMPORTANT** — the verdict union is a `Types.TransformVerdict`, but `pure/TransformRules.luau`
> **re-declares it locally** and does not require `Types`. That is the rule for everything under
> `pure/` (`tests/README.md`, and the header comment in `RoundTransitions.luau`): Lune has no
> DataModel, and `Enums.luau` requires `script.Parent.Types`, so a pure module that requires either
> stops being runnable from a terminal. Luau literal unions are **structural**, so the two declarations
> are the same type and pass to each other without a cast. The only cost is keeping the lists in step —
> which is the same trade `RoundTransitions.RoundPhase` already makes and which C01 documented.

#### Step 1.4: Audit the remote surface — confirm all three exist, add none

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run check:remotes`

`RoleAssigned` and `MonsterTransformed` are already in `EVENTS_DOWN`; `RequestTransform` is already in
`EVENTS_UP`. This step confirms that by reading, adds a comment recording which chunk wires each, and
**adds no new remote**.

**Verified by reading `src/shared/Remotes.luau`, not assumed** — all three exist, in the correct
direction list. See `references/Remotes-review.luau`. The request asked for "all four needed"; there are
**three**, and the fourth (`RequestKill`) belongs to C05 and is deliberately left unwired.

```diff
 -- Server -> Client (the server tells you things)
 local EVENTS_DOWN = {
 	"RoundSnapshot", -- periodic ClientRoundSnapshot for HUD
 	"PhaseChanged",
-	"RoleAssigned", -- fired ONLY to the player it concerns
+	"RoleAssigned", -- C03. FireClient ONLY, to the one player it concerns. Never FireAllClients.
 	"TaskProgressChanged",
 	"PlayerKilled",
-	"MonsterTransformed", -- public by design: this is the tell
+	"MonsterTransformed", -- C04. Public by design: this is the tell, and broadcasting it is correct.
 	"SaltEffect",
 	"RoundEnded", -- includes the reveal
 	"QuickChatBroadcast",
 	"ProfileUpdated",
 }
 
 -- Client -> Server (the client asks; the server decides)
 local EVENTS_UP = {
 	"RequestTaskProgress",
-	"RequestTransform",
+	"RequestTransform", -- C04. The first handler in this repo to consult AntiCheatService.
 	"RequestKill",
```

> **NOTE** these are comment-only edits. `check-remotes.mjs` parses the two lists out of this file with
> comments already stripped (`readSource(...).withStrings`), so a comment inside a list cannot change
> what it declares — confirmed by reading `.claude/scripts/lib/luau-source.mjs`.
>
> **NOTE** `check:remotes` reports declared-but-unwired names as a NOTE and never a failure, by design
> (the scaffold declares the whole surface up front). So this step's check does **not** prove the three
> names exist — it proves nothing in the tree *uses* an undeclared or wrong-direction remote, which is
> the failure that hangs a client forever on `WaitForChild`. The existence half is proven by reading,
> and it is recorded in the reference review.

#### Step 1.5: Phase 1 gate

**File:** — (verification only)
**Verify:** `npm run verify`

The whole tree green before any service code is written.

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — nothing here touches a role at runtime. `RoleAssignedPayload` is a *type*, and
  `src/shared/Types.luau` already replicates to every client; a type declaration publishes a field name,
  not a value.
- **Remote direction** — no remote added, no remote fired. Comment-only edits to `Remotes.luau`.
- **Rate limiting** — no handler exists yet. `check:ratelimit` still passes vacuously after this phase.
- **Magic numbers** — every number added lands in `Config.luau`, which is where `check:config` wants
  them. The new numbers in `tests/` are fine: `check-config.mjs` governs `src/(server|client)/` only.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — not reachable from this phase.
- **Strict Luau** — the four new types are plain records and a literal union; no enum casts needed.
- **Mobile budget** — nothing rendered, nothing per-frame.
- **Scope** — no token from §3's OUT list. `check:scope` matches whole words after splitting
  identifiers, so none of `AntiCheat`, `Budgets` or `RefillPerSecond` can trip it.

**Issues identified:**

- **The budget-name list is duplicated between `Config.luau` and the test.** `Remotes.luau` calls
  `game:GetService` at module scope, so Lune cannot require it. Both directions are pinned inside the
  test, and the residual gap (a remote added to `Remotes.luau` and nowhere else) is named in Follow Ups
  as work for C41.
- **`Config.AntiCheat.LogOnly = true` means C02 ships a limiter that refuses nothing.** That is C02's
  stated design ("log-only on rejection; kicking is C41"), and it means the *only* runtime proof
  available in this plan that the limiter works is the Lune test over the pure bucket. Stated here so
  nobody reads a quiet console during the C04 playtest as evidence the limiter is running.
- **`print` counts in test files are prose.** `tests/config.test.luau` ends with a literal
  `13 balance invariants`. Nothing asserts it. Updated to 19 in Step 1.2.

### Phase 2: C02a — the token bucket, proven from a terminal

#### Step 2.1: Write `src/shared/pure/TokenBucket.luau`

**File:** `src/shared/pure/TokenBucket.luau`
**Verify:** `npm run analyze`

`(bucket, now, cost) -> (allowed, newBucket)`, with the backwards-clock clamp that is the whole reason
this is a pure function and not three lines inside the service.

```luau
--!strict
--[[
	TokenBucket — the rate limiter's arithmetic, as a pure function.

		(bucket, now, cost) -> (allowed, newBucket)

	WHY THIS IS A MODULE AND NOT THREE LINES INSIDE AntiCheatService
	----------------------------------------------------------------
	It is four lines of arithmetic with one genuinely hostile input: `now`. A rate limiter is the piece
	of infrastructure that must keep working while everything around it misbehaves, and its failure mode
	is silent in both directions — too loose and it refuses nothing, too tight and it refuses a real
	player on a bad connection while looking exactly like lag. Neither shows up in Studio.

	Pulled out here, `tests/token-bucket.test.luau` walks steady state, burst, refill and a clock jump
	backwards in milliseconds. Left inline, "does the limiter refill correctly after the clock moves
	backwards" is a question nobody can answer without waiting for it to happen on a live server.

	IT IS SAFE THAT THIS FILE REPLICATES. `src/shared` maps wholesale into ReplicatedStorage, so any
	client can require AND call this (docs/BUILD-PLAN.md §12). It publishes nothing:
	`Config.AntiCheat.Budgets` is itself replicated, so the numbers were already public, and knowing the
	algorithm does not let a client spend tokens it does not have — the buckets live on the server. Only
	a module whose INPUTS or OUTPUT are secret belongs in `src/server/pure/`; see the plan's §1.1.

	NO `script.Parent` REQUIRES — the rule for everything under `pure/` (tests/README.md). The bucket
	type is therefore re-declared here rather than required from Types; Luau records are structural, so
	this type and `Types.TokenBucketState` are the same type.
]]

export type Bucket = {
	Tokens: number,
	LastRefillAt: number,
	Capacity: number,
	RefillPerSecond: number,
}

local TokenBucket = {}

-- A full bucket. Starting full rather than empty is deliberate: a player's first action after joining
-- is legitimate, and a limiter that refuses it teaches them the game is broken.
function TokenBucket.new(capacity: number, refillPerSecond: number, now: number): Bucket
	return {
		Tokens = capacity,
		LastRefillAt = now,
		Capacity = capacity,
		RefillPerSecond = refillPerSecond,
	}
end

--[[
	Refill for the elapsed time, then spend if there is enough.

	Returns a NEW bucket every time, including on refusal — the refusal still refilled, and a caller
	that discards the returned bucket on `false` would freeze the player's tokens at whatever they held
	when they were first refused. That is the shape of bug this signature exists to make obvious: there
	is no in-place mutation to forget to save.

	THE CLOCK MOVING BACKWARDS
	--------------------------
	`now` comes from os.clock(), which this repo already uses for every round timer. It is not
	guaranteed monotonic, and the failure is asymmetric:

	  · Left unhandled, `elapsed` goes negative, tokens go DOWN on a refill, and a large enough jump
	    drives the bucket negative — the player is refused until real time makes up the difference.
	  · Clamping `elapsed` to zero but LEAVING `LastRefillAt` in the future is the subtler version of
	    the same bug: every subsequent call also computes a negative elapsed, so the bucket does not
	    refill at all until the clock catches up. A 60-second backwards jump mutes the remote for 60
	    seconds.

	So it clamps AND RE-ANCHORS: `LastRefillAt` is set to `now` unconditionally. A backwards jump costs
	the player the refill they had accrued and nothing more. `tests/token-bucket.test.luau` pins the
	re-anchoring specifically, because the clamp alone passes a naive test.
]]
function TokenBucket.consume(bucket: Bucket, now: number, cost: number): (boolean, Bucket)
	local elapsed = now - bucket.LastRefillAt

	if elapsed < 0 then
		elapsed = 0
	end

	local tokens = math.min(bucket.Capacity, bucket.Tokens + elapsed * bucket.RefillPerSecond)
	local allowed = tokens >= cost

	return allowed,
		{
			Tokens = if allowed then tokens - cost else tokens,
			LastRefillAt = now,
			Capacity = bucket.Capacity,
			RefillPerSecond = bucket.RefillPerSecond,
		}
end

return TokenBucket
```

> **IMPORTANT** — `cost > Capacity` is refused **forever** and by construction: the bucket can never
> hold enough. Today that is unreachable (`DefaultCost = 1`, every capacity ≥ 2) and Step 2.2 pins the
> behaviour so C41 cannot introduce it by pricing a handler above its own capacity. The test asserts
> refusal rather than an error, because a limiter that throws is worse than one that refuses.

#### Step 2.2: Write `tests/token-bucket.test.luau`

**File:** `tests/token-bucket.test.luau`
**Verify:** `lune run tests/token-bucket.test.luau`

Steady state, burst exhaustion, refill over time, a clock jump **backwards**, and a cost larger than the
bucket — the four C02 requires plus the one that would otherwise deadlock a remote forever.

```luau
--!strict
--[[
	tests/token-bucket.test.luau

	The rate limiter's arithmetic, including the input that will actually break it.

	C02 names four scenarios — steady state, burst, refill, clock jump backwards. Three of them are the
	happy path in different clothes. The fourth is the one worth writing a test for, and it is written
	here in the form that a naive implementation FAILS: not "does a backwards jump grant free tokens"
	(clamping elapsed to zero passes that) but "does the bucket still refill AFTERWARDS".
]]

local TokenBucket = require("../src/shared/pure/TokenBucket")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

local function approx(a: number, b: number): boolean
	return math.abs(a - b) < 0.0001
end

--------------------------------------------------------------------------------
-- Steady state — a legitimate player at the sustained rate is never refused
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)
	local refused = 0

	-- One request per second against a 1/s refill, for twice as long as the bucket is deep. A limiter
	-- that leaks capacity — refunding less than it charges, or re-anchoring wrongly — fails here and
	-- nowhere else, because the deficit only becomes visible after it accumulates.
	for second = 1, 20 do
		local allowed, next = TokenBucket.consume(bucket, second, 1)

		bucket = next

		if not allowed then
			refused += 1
		end
	end

	check("steady state at the refill rate is never refused", refused == 0, `{refused} refused`)
	check("steady state does not drift the bucket", approx(bucket.Tokens, 4), `tokens={bucket.Tokens}`)
end

--------------------------------------------------------------------------------
-- Burst — capacity is the burst, and the next one is refused
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)
	local allowedCount = 0

	-- Ten requests in the SAME instant. Capacity is 5, so exactly 5 get through.
	for _ = 1, 10 do
		local allowed, next = TokenBucket.consume(bucket, 0, 1)

		bucket = next

		if allowed then
			allowedCount += 1
		end
	end

	check("a burst is capped at capacity", allowedCount == 5, `{allowedCount} allowed`)
	check("an exhausted bucket holds no tokens", approx(bucket.Tokens, 0), `tokens={bucket.Tokens}`)
end

--------------------------------------------------------------------------------
-- Refill — and the ceiling, which is the half that is usually missing
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 0)

	for _ = 1, 5 do
		local _, next = TokenBucket.consume(bucket, 0, 1)
		bucket = next
	end

	-- 2.5 seconds at 1/s buys two whole requests and not a third.
	local first, afterFirst = TokenBucket.consume(bucket, 2.5, 1)
	local second, afterSecond = TokenBucket.consume(afterFirst, 2.5, 1)
	local third = TokenBucket.consume(afterSecond, 2.5, 1)

	check("refill grants the first whole token", first)
	check("refill grants the second whole token", second)
	check("refill does not grant a partial token", not third)

	-- Idle for far longer than it takes to fill. Without the min() a long-idle player banks an
	-- unbounded burst, which is the exact shape an exploiter waits for.
	local _, idle = TokenBucket.consume(TokenBucket.new(5, 1, 0), 1000, 1)

	check("an idle bucket never exceeds capacity", approx(idle.Tokens, 4), `tokens={idle.Tokens}`)
end

--------------------------------------------------------------------------------
-- The clock jumps BACKWARDS
--------------------------------------------------------------------------------

do
	local bucket = TokenBucket.new(5, 1, 100)

	for _ = 1, 5 do
		local _, next = TokenBucket.consume(bucket, 100, 1)
		bucket = next
	end

	-- The clock is now 60 seconds EARLIER than the last refill.
	local allowed, jumped = TokenBucket.consume(bucket, 40, 1)

	check("a backwards jump grants no free tokens", not allowed)
	check("a backwards jump never drives the bucket negative", jumped.Tokens >= 0, `tokens={jumped.Tokens}`)

	-- THE ASSERTION THAT MATTERS. A limiter that clamps `elapsed` but leaves LastRefillAt in the
	-- future passes both checks above and then refuses this one for a further 60 seconds.
	check(
		"the bucket re-anchors, so it refills normally after the jump",
		jumped.LastRefillAt == 40,
		`LastRefillAt={jumped.LastRefillAt}`
	)

	local recovered = TokenBucket.consume(jumped, 45, 1)

	check("five seconds after the jump, requests flow again", recovered)
end

--------------------------------------------------------------------------------
-- Degenerate input, and purity
--------------------------------------------------------------------------------

do
	-- A cost above capacity can never be paid. It must REFUSE, not error: the limiter is the thing
	-- that has to keep working when the configuration is wrong.
	local allowed, next = TokenBucket.consume(TokenBucket.new(2, 1, 0), 1000, 5)

	check("a cost above capacity is refused rather than erroring", not allowed)
	check("a refused oversized cost still leaves a full bucket", approx(next.Tokens, 2), `tokens={next.Tokens}`)

	-- Purity: the input table is untouched, so a caller that discards the result changes nothing.
	local original = TokenBucket.new(5, 1, 0)
	local before = original.Tokens

	TokenBucket.consume(original, 0, 1)

	check("consume does not mutate its input", original.Tokens == before, `tokens={original.Tokens}`)
end

if failures > 0 then
	error(`{failures} token-bucket failure(s)`, 0)
end

print("  PASS  token-bucket: steady state, burst, refill, backwards clock, degenerate cost, purity")
```

> **NOTE** the "re-anchors" assertion is the one that earns this test its place. Every other assertion
> here passes against an implementation that clamps `elapsed` to zero and stops there — the version
> most people write first.

#### Step 2.3: Phase 2 gate — the whole suite

**File:** — (verification only)
**Verify:** `npm run test:unit`

Proves the new test runs under the same runner as the existing three and breaks none of them.

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — none. `TokenBucket` never sees a UserId, a role, or a player; the service keys
  buckets by UserId and the pure module receives only numbers.
- **Remote direction** — no remote touched.
- **Rate limiting** — this *is* the rate limiter, and no handler consults it yet. Phase 3 wires it.
- **Magic numbers** — `src/shared/pure/` is not governed by `check:config` (the check covers
  `src/(server|client)/`, confirmed by reading `check-config.mjs`), and the module contains no
  literals regardless: every number arrives as an argument. The test file is full of literals and that
  is correct — a test's numbers *are* the test.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — bucket cleanup is Phase 3's concern.
- **Strict Luau** — `TokenBucket.consume` returns two values; the multi-return is what makes
  `local allowed, next = ...` typecheck. The `if allowed then tokens - cost else tokens` expression is
  an if-expression, not a statement, and needs no cast.
- **Mobile budget** — pure arithmetic, no allocation per frame. It allocates one small table per
  request, which is per-remote-call rather than per-frame.
- **Scope** — clean.

**Issues identified:**

- **`os.clock()` is the clock, and this plan does not prove it is monotonic on a Roblox server.** The
  module is written to survive it going backwards *because* that has not been proven either way. This is
  the honest position: the code is correct under both assumptions, and the assumption itself is raised
  in Follow Ups rather than asserted here.
- **A new bucket starts FULL.** That is a deliberate choice (a player's first action is legitimate) and
  it means a player who rejoins repeatedly gets a fresh full bucket each time — buckets are keyed by
  UserId and dropped on `PlayerRemoving` in Step 3.1. Rejoin-to-reset is therefore a real, if
  expensive, bypass of a *sustained* limit. It costs a full reconnect per burst, which is slower than
  the limit it evades, so it is recorded rather than fixed; C41 is where session-persistent counters
  belong if they ever earn their keep.

### Phase 3: C02 — AntiCheatService

> **C02 Done** (verbatim, `docs/BUILD-PLAN.md`): every `Remotes.Up` name has a declared budget; a burst
> is refused; the refusal is logged.
> **C02 Verify** (verbatim): `lune run tests/token-bucket.test.luau` — steady state, burst, refill, clock
> jump backwards.

#### Step 3.1: Implement `AntiCheatService.Consume(player, remoteName)`

**File:** `src/server/Services/AntiCheatService.luau`
**Verify:** `npm run analyze`

Per-player, per-remote buckets in a server-only table, created lazily, cleaned up on `PlayerRemoving`.

Replaces the stub wholesale. The full file:

```luau
--!strict
--[[
	AntiCheatService — the rate-limit core (C02).

	Every OnServerEvent handler in this game calls Consume() before it does anything else, and
	`check:ratelimit` fails the build if one does not. This chunk is built BEFORE any handler exists so
	that every later handler is born compliant rather than retrofitted — retrofitting a limiter means
	auditing handlers that already work, which is the audit nobody finishes.

	WHAT THIS SERVICE IS, AND IS NOT
	--------------------------------
	It answers ONE question: has this player asked for this remote more often than a human could? It
	does NOT validate the request. Distance, line of sight, phase, cooldown and role all belong to the
	service that owns the mechanic, because only that service knows what "valid" means. A limiter that
	tried to validate would need to know everything and would be wrong about most of it.

	The split matters for reading the code too: a handler that consults Consume() and then does no
	validation of its own is NOT protected, and `check:ratelimit` — which is a text tripwire, by its own
	admission — will report it as clean. That gap is what `exploit-auditor` is for.

	LOG-ONLY, DELIBERATELY (C02; enforcement is C41)
	------------------------------------------------
	A refused request IS refused — Consume returns false and the handler returns early. What `LogOnly`
	governs is everything BEYOND refusal: kicking, throttling, flagging an account. None of that exists
	yet and none of it should, because kicking on a limit with no real data behind the numbers kicks
	real players on bad connections, and a false kick is unrecoverable. C41 flips the flag with a
	playtest's worth of evidence behind it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TokenBucket = require(Shared.pure.TokenBucket)
local Types = require(Shared.Types)

local AntiCheatService = {}

-- SERVER-ONLY state. buckets[userId][remoteName] -> bucket. Never replicated, never attributed.
local buckets: { [number]: { [string]: Types.TokenBucketState } } = {}

-- lastLoggedAt[userId][remoteName] -> os.clock() of the last warn for that pair. An exploiter firing a
-- thousand requests a second would otherwise produce a thousand warn() calls a second, which is its
-- own denial of service and buries every other line in the output window.
local lastLoggedAt: { [number]: { [string]: number } } = {}

local function bucketFor(userId: number, remoteName: string, now: number): Types.TokenBucketState?
	local budget = Config.AntiCheat.Budgets[remoteName]

	if budget == nil then
		return nil
	end

	local playerBuckets = buckets[userId]

	if playerBuckets == nil then
		playerBuckets = {}
		buckets[userId] = playerBuckets
	end

	local bucket = playerBuckets[remoteName]

	if bucket == nil then
		bucket = TokenBucket.new(budget.Capacity, budget.RefillPerSecond, now)
		playerBuckets[remoteName] = bucket
	end

	return bucket
end

local function logRefusal(player: Player, remoteName: string, now: number)
	local playerLogs = lastLoggedAt[player.UserId]

	if playerLogs == nil then
		playerLogs = {}
		lastLoggedAt[player.UserId] = playerLogs
	end

	local last = playerLogs[remoteName]

	if last ~= nil and now - last < Config.AntiCheat.LogThrottleSeconds then
		return
	end

	playerLogs[remoteName] = now

	-- UNGATED by VerboseLogging, matching RoundService's treatment of a dropped round result: this is a
	-- fault, not routine tracing, and a published server is exactly where it matters. Safe to log —
	-- a remote name and a UserId, never a role.
	warn(`[AntiCheat] Rate limit refused {player.Name} ({player.UserId}) on {remoteName}`)
end

--[[
	The one entry point. Returns true when the request may proceed.

		if not AntiCheatService.Consume(player, "RequestTransform") then
			return
		end

	The NAME of this function is load-bearing, not stylistic: `check-ratelimit.mjs` matches
	`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of an
	`.OnServerEvent:Connect(`. Renaming it to something outside that set turns every handler in the game
	into an unguarded one as far as the gate is concerned, silently and all at once.
]]
function AntiCheatService.Consume(player: Player, remoteName: string): boolean
	local now = os.clock()
	local bucket = bucketFor(player.UserId, remoteName, now)

	if bucket == nil then
		-- FAIL CLOSED. A remote with no budget is refused. The alternative means any remote added
		-- without a Config entry is silently unlimited, which is the exact state C02 exists to prevent.
		logRefusal(player, `{remoteName} (no budget declared)`, now)

		return Config.AntiCheat.AllowUnbudgetedRemote
	end

	local allowed, next = TokenBucket.consume(bucket, now, Config.AntiCheat.DefaultCost)

	-- Store the returned bucket on BOTH paths. A refusal still refilled, and discarding it here would
	-- freeze the player's tokens at the moment they were first refused — a permanent mute.
	local playerBuckets = buckets[player.UserId]

	if playerBuckets then
		playerBuckets[remoteName] = next
	end

	if not allowed then
		logRefusal(player, remoteName, now)
	end

	return allowed
end

local function onPlayerRemoving(player: Player)
	buckets[player.UserId] = nil
	lastLoggedAt[player.UserId] = nil
end

function AntiCheatService.Init()
	table.clear(buckets)
	table.clear(lastLoggedAt)
end

function AntiCheatService.Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return AntiCheatService
```

> **NOTE** no change to `src/server/init.server.luau` is needed. `AntiCheatService` already sits second
> in `SERVICE_ORDER`, under "Infrastructure first", ahead of every gameplay service — so its `Init()`
> has run before `MonsterService.Start()` connects the first handler in Phase 6. Verified by reading
> the bootstrap; see `references/init.server-review.luau`.

#### Step 3.2: Budgets from Config, fail closed on an unknown remote, log-only refusal

**File:** `src/server/Services/AntiCheatService.luau`
**Verify:** `npm run check:config`

No capacity, rate or cost is typed in this file. An unbudgeted remote name is **refused**, not allowed.

This is a review step over the file written in 3.1 rather than a second edit to it, and its check is the
one that can actually fail: `src/server/` **is** governed by `check-config.mjs`, so any of the following
turns the tree red.

| Tempting shortcut | What `check:config` does |
| --- | --- |
| `TokenBucket.new(10, 2, now)` | flags `10` and `2` — budgets belong in `Config.AntiCheat.Budgets` |
| `if now - last < 5 then` | flags `5` — that is `Config.AntiCheat.LogThrottleSeconds` |
| `TokenBucket.consume(bucket, now, 1)` | **allowed** — `1` is on the idiomatic list, which is why the cost is still written as `Config.AntiCheat.DefaultCost`: correctness, not the check |

Three facts the step must leave true, each of them a decision rather than a detail:

1. **Fail closed.** `bucketFor` returns `nil` for an unknown remote and `Consume` returns
   `Config.AntiCheat.AllowUnbudgetedRemote`, which is `false`. A future author who adds a remote and
   forgets its budget gets a dead remote and a `warn` naming it — loud, immediate, and fixable. The
   inverse gets a silently unlimited remote and no symptom at all.
2. **The returned bucket is stored on the refusal path too.** Discarding it on `false` freezes the
   player's tokens at the moment of first refusal, which is a permanent mute that looks exactly like the
   limiter working.
3. **Refusal is not escalation.** `Consume` returns `false` whether or not `LogOnly` is set;
   `LogOnly` gates kicking and throttling, neither of which exists until C41. Pinned by
   `tests/anti-cheat-budgets.test.luau`, so flipping it early breaks a test rather than a playtest.

#### Step 3.3: C02 phase gate

**File:** — (verification only)
**Verify:** `npm run verify`

C02's Done restated as three checkable facts, all green.

| C02 Done, verbatim | How it is checked here | Where |
| --- | --- | --- |
| every `Remotes.Up` name has a declared budget | `lune run tests/anti-cheat-budgets.test.luau`, both directions | Step 1.1 |
| a burst is refused | `lune run tests/token-bucket.test.luau` — 10 requests in one instant, 5 allowed | Step 2.2 |
| the refusal is logged | `logRefusal` on every `false`, throttled per player per remote | Step 3.1 |

**C02's own Verify line is `lune run tests/token-bucket.test.luau`** and it is satisfied by Step 2.2.
`npm run verify` is used as the gate here because it runs that test *and* the rest of the tree, and
because a chunk gate should notice damage outside its own files.

**What C02 does NOT prove, stated plainly.** No handler consults `Consume` yet — Phase 6 is where the
first one appears. Until then `check:ratelimit` still passes vacuously, and the *service* half of this
chunk has no runtime evidence behind it at all. Anyone reading a green Phase 3 as "the limiter is
working in Studio" is reading more than is there.

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the refusal log prints a player name, a UserId and a remote name. None of those
  is the secret, and every one is already known to whoever reads a server log. It must never grow to
  include the role, and `RequestTransform` refusals are the tempting place to add it (`"the Aswang was
  rate-limited"`), which would put the secret in a log that C40's analytics will later ship off-server.
- **Remote direction** — no remote touched.
- **Rate limiting** — the mechanism itself; no handler yet.
- **Magic numbers** — every budget in `Config.AntiCheat`. `check:config` governs this file. See 3.2.
- **Phase ownership** — `AntiCheatService` neither reads nor sets the phase. It is deliberately phase
  agnostic: a limiter that only ran during `ACTIVE` would leave the lobby unlimited.
- **Player leaving mid-round** — `onPlayerRemoving` drops both tables. Without it the maps grow for the
  life of the server. Note the rejoin-resets-buckets consequence recorded in Phase 2.
- **Strict Luau** — `bucketFor` returns `Types.TokenBucketState?` and the `nil` branch is handled before
  use. `Config.AntiCheat.Budgets[remoteName]` indexes a table literal with a string, which infers fine;
  no cast needed.
- **Mobile budget** — server-side only, no rendering, no per-frame work.
- **Scope** — clean.

**Issues identified:**

- **`check:ratelimit` cannot see this service working.** It matches text near an `OnServerEvent`
  handler; with no handler in the tree it passes vacuously and will keep doing so until Step 6.3. The
  only evidence C02 has is the Lune test over the pure bucket. Recorded so the C02 gate is not
  mistaken for runtime proof.
- **`Consume` is keyed on a string the caller supplies.** A handler that passes the wrong name silently
  gets the wrong budget — or, if the name is misspelled, gets refused entirely by the fail-closed path.
  The refusal is loud, so the failure mode is the safe one, but nothing checks that the string matches
  the remote the handler is actually connected to. C41's sweep is the right place for that.
- **A single global clock.** All buckets read `os.clock()` inside `Consume` rather than taking `now` as
  an argument. That is the boundary between the pure module (takes `now`) and the Roblox-shaped wrapper
  (reads it), and it is why the *arithmetic* is testable and the *service* is not.

### Phase 4: C03a — the role draw, pure and server-only

#### Step 4.1: Create `src/server/pure/RoleDraw.luau`

**File:** `src/server/pure/RoleDraw.luau`
**Verify:** `npm run analyze`

`(candidates, history, aswangCount, weights, nextFloat) -> assignments`. The RNG is **injected**, which is
what makes it deterministic given a seed without the module ever holding a seed.

**This step creates a new directory, `src/server/pure/`.** See §1.1 for the decision and its two measured
consequences. `npm run analyze` regenerates a stale sourcemap before running (confirmed by reading
`check-analyze.mjs`, which calls `regenerateSourcemap()` when `sourcemapStale()`), so the new folder needs
no manual `npm run sourcemap`.

```luau
--!strict
--[[
	RoleDraw — who is the Aswang, as a pure function.

		(candidates, history, aswangCount, weights, nextFloat) -> { [userId]: Role }

	WHY THIS FILE IS UNDER src/server/pure/ AND NOT src/shared/pure/
	----------------------------------------------------------------
	`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module there is
	require-able AND CALLABLE by any client. For `TokenBucket` that is harmless — Config.AntiCheat is
	replicated anyway, so the module publishes nothing new.

	For this module it is the security of the entire game. The algorithm being public is fine; a
	REPRODUCIBLE draw is not. Algorithm + inputs + seed = this round's assignment, and an exploiter who
	reproduces all three knows the Aswang BEFORE the round starts — with no remote to intercept and
	nothing for `check:secrecy` to see. It is the only leak in this game that leaves no trace on the
	wire.

	`src/server` maps to ServerScriptService, which does not replicate. So the client cannot call this
	even with a correct guess at every input. Two rules are still enforced at the call site, because
	defence in depth is the point and because the next author may not read this comment:

	  · The RNG is INJECTED, never created here, and RoleService seeds it with `Random.new()` — no
	    argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and
	    both fatal.
	  · `history` is server-only in-memory state. It is a DRAW INPUT, so it is treated as secret even
	    though every past Aswang was already revealed by RoundEnded (§4.8): every input a client holds
	    shrinks the search space for the one it does not.

	Lune resolves test requires by FILE PATH and knows nothing about Rojo, so this location costs no
	testability — `tests/role-draw.test.luau` requires "../src/server/pure/RoleDraw" and runs identically.

	NO `script.Parent` REQUIRES, same rule as every other pure module. The Role type is re-declared
	below; Luau literal unions are structural, so this and `Types.Role` are the same type.

	NOTE `check-config.mjs` governs `src/server/`, so this file — unlike `src/shared/pure/` — may not
	contain a tunable number. That is why `weights` is a parameter. It is the right shape anyway: §4.2's
	"heavily reduced weight" is a balance knob and M12 tunes it.
]]

export type Role = "SURVIVOR" | "ASWANG"

export type Weights = {
	Base: number, -- never been the Aswang, or longer ago than HistoryRounds
	Recent: number, -- the Aswang in the immediately previous round
	Older: number, -- the Aswang within HistoryRounds, but not last round
	HistoryRounds: number, -- how far back the history is consulted
}

-- Most recent round FIRST. history[1] is the UserIds drawn as Aswang last round.
export type History = { { number } }

local RoleDraw = {}

--[[
	How likely this player is to be drawn, relative to everyone else.

	Returns a weight rather than a boolean because §4.2 asks for "heavily reduced", not "excluded". A
	zero would be an exclusion, and with MinPlayers = 3 a rule that excludes two players leaves a round
	with nobody eligible — a fallback firing under a condition nobody tested. `tests/config.test.luau`
	pins the weights positive and ordered.
]]
function RoleDraw.weightFor(userId: number, history: History, weights: Weights): number
	for roundsAgo, aswangs in history do
		if roundsAgo > weights.HistoryRounds then
			break
		end

		for _, id in aswangs do
			if id == userId then
				return if roundsAgo == 1 then weights.Recent else weights.Older
			end
		end
	end

	return weights.Base
end

--[[
	Weighted sampling WITHOUT replacement, then everyone left over is a survivor.

	`nextFloat` must return a value in [0, 1). It is called exactly once per Aswang drawn, so a caller
	can reproduce a draw exactly by replaying the same stream — which is what makes 10,000 seeded rounds
	testable, and which is precisely why the module must not replicate.

	`candidates` must be in a DETERMINISTIC order. `Players:GetPlayers()` is not, so RoleService sorts
	by UserId before calling; without that, "same seed, same result" is false and the test that proves
	this function correct proves nothing about the game.

	Degenerate inputs return a sensible assignment rather than erroring. A live server that reached one
	of these has a bigger problem than the draw, and the draw erroring inside `enterStarting` would
	leave the round stuck in STARTING with no Aswang and no log.
]]
function RoleDraw.draw(
	candidates: { number },
	history: History,
	aswangCount: number,
	weights: Weights,
	nextFloat: () -> number
): { [number]: Role }
	local assignments: { [number]: Role } = {}

	for _, userId in candidates do
		assignments[userId] = "SURVIVOR"
	end

	-- Never draw every candidate as the Aswang: a round with no survivors is over before it starts.
	local picks = math.clamp(aswangCount, 0, math.max(#candidates - 1, 0))

	if picks == 0 then
		return assignments
	end

	-- A working copy, so removing a drawn player does not disturb the caller's list.
	local remaining = table.clone(candidates)

	for _ = 1, picks do
		local total = 0

		for _, userId in remaining do
			total += RoleDraw.weightFor(userId, history, weights)
		end

		-- Every weight is positive by contract (tests/config.test.luau), so this is unreachable. It is
		-- here because the alternative to an unreachable branch is an unreachable crash: a caller
		-- passing zeroed weights would otherwise roll into an empty range and pick nobody.
		local chosenIndex = #remaining

		if total > 0 then
			local roll = nextFloat() * total
			local cumulative = 0

			for index, userId in remaining do
				cumulative += RoleDraw.weightFor(userId, history, weights)

				if roll < cumulative then
					chosenIndex = index
					break
				end
			end
		end

		assignments[remaining[chosenIndex]] = "ASWANG"
		table.remove(remaining, chosenIndex)
	end

	return assignments
end

return RoleDraw
```

> **IMPORTANT** — `chosenIndex` defaults to `#remaining` rather than `1`. Floating-point accumulation can
> leave `roll` a hair above the final `cumulative`, and the loop then falls through without matching. The
> default is the last element, which is where a roll at the top of the range belongs. Defaulting to `1`
> would bias the first candidate — a bias of maybe one round in a million, invisible in a playtest and
> permanent.

#### Step 4.2: Write `tests/role-draw.test.luau`

**File:** `tests/role-draw.test.luau`
**Verify:** `lune run tests/role-draw.test.luau`

10,000 seeded draws: back-to-back Aswang rate strictly below the unweighted baseline, and no player
starves. Plus the degenerate cases that would otherwise error on a live server.

```luau
--!strict
--[[
	tests/role-draw.test.luau

	The one decision the whole game rests on, proven over ten thousand rounds.

	C03's Verify line asks for two numbers, and they pull in OPPOSITE directions — that is why both are
	required and why either alone is misleading:

	  · back-to-back Aswang rate BELOW the unweighted baseline  — the anti-repeat actually works
	  · every player eventually eligible                        — it did not work by banning people

	A draw that excluded the last Aswang outright would ace the first and fail the second, and would
	feel fine for two rounds before a player noticed they were never the monster on a full server.

	LUNE HAS NO `Random`. That is a feature here: the module takes an injected `nextFloat`, so the test
	supplies a Park–Miller LCG and gets exact reproducibility, while RoleService supplies
	`Random.new()` — no argument, server-only entropy — and gets a draw nobody can replay.
]]

local Config = require("../src/shared/Config")
local RoleDraw = require("../src/server/pure/RoleDraw")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- Park–Miller minimal standard. Deterministic, and every intermediate value stays exactly
-- representable in a float64, so this produces identical streams on every machine.
local function makeRng(seed: number): () -> number
	local state = seed % 2147483647

	if state <= 0 then
		state += 2147483646
	end

	return function(): number
		state = (state * 16807) % 2147483647

		return (state - 1) / 2147483646
	end
end

-- The real weights, so this test fails when someone tunes them past the point of working.
local WEIGHTS: RoleDraw.Weights = {
	Base = Config.Roles.BaseWeight,
	Recent = Config.Roles.RecentAswangWeight,
	Older = Config.Roles.OlderAswangWeight,
	HistoryRounds = Config.Roles.RepeatCooldownRounds,
}

local PLAYERS = { 101, 102, 103, 104, 105, 106, 107, 108 }

local function aswangIn(assignments: { [number]: RoleDraw.Role }): number?
	for userId, role in assignments do
		if role == "ASWANG" then
			return userId
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Shape: exactly one Aswang, everyone else a survivor, nobody missing
--------------------------------------------------------------------------------

do
	local assignments = RoleDraw.draw(PLAYERS, {}, Config.Roles.AswangCount, WEIGHTS, makeRng(1))
	local aswangs = 0
	local assigned = 0

	for _, userId in PLAYERS do
		local role = assignments[userId]

		check(`player {userId} was assigned a role`, role ~= nil)

		if role ~= nil then
			assigned += 1
		end

		if role == "ASWANG" then
			aswangs += 1
		end
	end

	check("everyone in the round got a role", assigned == #PLAYERS, `{assigned}/{#PLAYERS}`)
	check("exactly AswangCount monsters", aswangs == Config.Roles.AswangCount, `{aswangs}`)
end

--------------------------------------------------------------------------------
-- Determinism: the property that makes the 10,000-round simulation meaningful
--------------------------------------------------------------------------------

do
	local first = RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(42))
	local again = RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(42))
	local other = RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(4242))

	check("the same stream draws the same Aswang", aswangIn(first) == aswangIn(again))

	-- Not a correctness property — a smoke test that the stream is CONSULTED at all. A draw that
	-- ignored nextFloat and returned candidates[1] would pass every other assertion in this file.
	local differed = false

	for seed = 1, 50 do
		if aswangIn(RoleDraw.draw(PLAYERS, {}, 1, WEIGHTS, makeRng(seed))) ~= aswangIn(first) then
			differed = true
			break
		end
	end

	check("different streams can draw different Aswangs", differed)
end

--------------------------------------------------------------------------------
-- The weighting itself
--------------------------------------------------------------------------------

do
	local history = { { 101 }, { 102 }, { 103 } }

	check(
		"last round's Aswang carries the recent weight",
		RoleDraw.weightFor(101, history, WEIGHTS) == WEIGHTS.Recent
	)
	check(
		"the round before carries the older weight",
		RoleDraw.weightFor(102, history, WEIGHTS) == WEIGHTS.Older
	)
	check(
		"beyond the history window, full weight returns",
		RoleDraw.weightFor(103, history, WEIGHTS) == WEIGHTS.Base,
		`RepeatCooldownRounds={WEIGHTS.HistoryRounds}`
	)
	check(
		"a player who has never been the Aswang carries full weight",
		RoleDraw.weightFor(999, history, WEIGHTS) == WEIGHTS.Base
	)
end

--------------------------------------------------------------------------------
-- 10,000 rounds — C03's Verify line, both halves
--------------------------------------------------------------------------------

do
	local ROUNDS = 10000
	local rng = makeRng(20260810)
	local history: RoleDraw.History = {}
	local timesDrawn: { [number]: number } = {}
	local backToBack = 0
	local previous: number? = nil

	for _, userId in PLAYERS do
		timesDrawn[userId] = 0
	end

	for _ = 1, ROUNDS do
		local assignments = RoleDraw.draw(PLAYERS, history, Config.Roles.AswangCount, WEIGHTS, rng)
		local aswang = aswangIn(assignments)

		if aswang ~= nil then
			timesDrawn[aswang] += 1

			if aswang == previous then
				backToBack += 1
			end

			previous = aswang

			-- Most recent first, trimmed to the window the draw actually consults.
			table.insert(history, 1, { aswang })

			while #history > WEIGHTS.HistoryRounds do
				table.remove(history)
			end
		end
	end

	-- With no weighting at all, the same player draws again with probability 1/#players.
	local baseline = 1 / #PLAYERS
	local rate = backToBack / ROUNDS

	check(
		"back-to-back Aswang is rarer than an unweighted draw",
		rate < baseline,
		`rate={rate}, unweighted baseline={baseline}`
	)

	-- "Heavily reduced" (§4.2) is a stronger claim than "reduced". Half the baseline is a floor with
	-- room to tune inside it: at the shipped weights the expected rate is roughly 0.014.
	check("back-to-back is HEAVILY reduced, not marginally", rate < baseline * 0.5, `rate={rate}`)

	-- No starvation. Anti-repeat should make the distribution MORE even, not less, so a player far
	-- below their share means the weighting has become an exclusion.
	local fairShare = ROUNDS / #PLAYERS

	for _, userId in PLAYERS do
		check(
			`player {userId} is not starved of the role`,
			timesDrawn[userId] > fairShare * 0.5,
			`drawn {timesDrawn[userId]} of {ROUNDS}, fair share {fairShare}`
		)
	end
end

--------------------------------------------------------------------------------
-- Degenerate rosters. A live server reaching one of these must not get an error.
--------------------------------------------------------------------------------

do
	local empty = RoleDraw.draw({}, {}, 1, WEIGHTS, makeRng(7))

	check("an empty roster draws nobody", next(empty) == nil)

	local solo = RoleDraw.draw({ 101 }, {}, 1, WEIGHTS, makeRng(7))

	check("a single player is never the Aswang alone", solo[101] == "SURVIVOR")

	local greedy = RoleDraw.draw(PLAYERS, {}, #PLAYERS + 5, WEIGHTS, makeRng(7))
	local survivors = 0

	for _, role in greedy do
		if role == "SURVIVOR" then
			survivors += 1
		end
	end

	check("a round always keeps at least one survivor", survivors >= 1, `survivors={survivors}`)

	local none = RoleDraw.draw(PLAYERS, {}, 0, WEIGHTS, makeRng(7))

	check("asking for zero Aswangs draws zero", aswangIn(none) == nil)
end

if failures > 0 then
	error(`{failures} role-draw failure(s)`, 0)
end

print("  PASS  role-draw: shape, determinism, weighting, 10000 rounds, degenerate rosters")
```

> **QUESTION** — the `rate < baseline * 0.5` assertion couples the test to the shipped weights. At M12
> the weights get tuned, and a tuning pass that softens `RecentAswangWeight` toward `OlderAswangWeight`
> would break it. That is arguably the test doing its job (§4.2 says *heavily*), but the person tuning
> will read it as a broken test. Flagged in Follow Ups rather than softened here: a threshold argued
> over once is worth more than one nobody notices.

#### Step 4.3: Prove no weight was typed into the draw

**File:** `src/server/pure/RoleDraw.luau`
**Verify:** `npm run check:config`

`src/server/pure/` is governed by `check:config`. A weight hardcoded here fails the check, which is the
mechanism that keeps the draw tunable at M12.

#### Step 4.4: Record the two pure locations and the rule that picks between them

**File:** `tests/README.md`
**Verify:** `grep -n "src/server/pure" tests/README.md`

The one honest-but-weak check in this plan: it proves the text was written, nothing more. The decision it
records is in §1.1 and the Follow Ups name the two other files that repeat the old wording.

```diff
 ## Growing the pure layer
 
 When a piece of gameplay logic is worth testing — role-weighting for the anti-repeat draw, the 5-of-12
 task selection, XP curves — write it as a pure function taking plain tables, put it in
-`src/shared/pure/`, and have the service call it. The Roblox-shaped wrapper stays thin and untestable;
+`src/shared/pure/` (or `src/server/pure/` — see below), and have the service call it. The Roblox-shaped
+wrapper stays thin and untestable;
 the decision it makes becomes provable here.
+
+### Two pure locations, and the rule that picks between them
+
+| Location | Replicates to clients? | Use when |
+| --- | --- | --- |
+| `src/shared/pure/` | **Yes** — `src/shared` maps wholesale into ReplicatedStorage | the default |
+| `src/server/pure/` | No — ServerScriptService does not replicate | an INPUT or the OUTPUT is secret |
+
+Everything under `src/shared/pure/` can be `require()`d **and called** by any client. That is harmless
+for `RoundTransitions` and `TokenBucket`: `Config.luau` is itself replicated, so they publish nothing
+that was private. Logic is not secret.
+
+**Inputs and seeds are.** `RoleDraw` decides who the Aswang is, so it lives in `src/server/pure/`
+(C03). If a client could reproduce the algorithm, its inputs and its seed, it would know the Aswang
+before the round started — with no remote to intercept and nothing for `check:secrecy` to see.
+
+Lune resolves requires by FILE PATH and knows nothing about Rojo, so the server location costs no
+testability at all: `require("../src/server/pure/RoleDraw")` works exactly like the shared form.
+
+One difference worth knowing: `check:config` governs `src/server/` and `src/client/` but NOT
+`src/shared/`. So a module in `src/server/pure/` may not contain a tunable number — pass it in. That is
+the better shape for a pure function anyway.
```

#### Step 4.5: Phase 4 gate — the whole suite

**File:** — (verification only)
**Verify:** `npm run test:unit`

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — this is the phase where it would happen. The module decides the secret, and the
  containment is structural: it lives under `src/server/`, so it does not replicate at all. Confirm
  nothing imports it from `src/shared/` or `src/client/` — a single `require` from a shared module
  would drag it back across the boundary. Nothing here writes an attribute or a tag.
- **Remote direction** — no remote touched. The draw's OUTPUT crosses in Phase 5.
- **Rate limiting** — no handler.
- **Magic numbers** — `src/server/pure/` **is** governed by `check:config`; Step 4.3 is that check. The
  only literals in the module are `0`, `1` and `-1`, all on the idiomatic list.
- **Phase ownership** — `RoleDraw` knows nothing about phases. `RoundService` decides *when*.
- **Player leaving mid-round** — the draw is a snapshot of the roster at `STARTING`. Someone leaving
  after it is `RoundService`'s existing Aswang-leaves case, untouched here.
- **Strict Luau** — `Role` is re-declared locally as a literal union rather than imported, so no
  `:: Types.Role` cast is needed. `table.clone` and `math.clamp` are both standard Luau and available
  under Lune.
- **Mobile budget** — server-only, runs once per round.
- **Scope** — clean.

**Issues identified:**

- **Candidate ORDER is part of the contract and is not enforceable here.** "Same seed, same result"
  holds only if `candidates` arrives in a stable order, and `Players:GetPlayers()` does not guarantee
  one. The sort belongs at the call site (Step 5.1) and the pure test cannot catch its absence — it
  always passes a literal array. This is the seam where a correct pure function and a correct-looking
  service produce a non-reproducible draw, and it is worth an explicit look during the C03 audit.
- **The test's back-to-back threshold is coupled to the shipped weights.** See the QUESTION above and
  Follow Ups.
- **The history is trimmed by the TEST, not by the module.** `RoleDraw.weightFor` stops reading past
  `HistoryRounds`, so an over-long history is harmless — but the service must still trim it or the table
  grows for the life of the server. Step 5.1 owns that.
- **`tests/README.md`, `CLAUDE.md` and `docs/BUILD-PLAN.md` all say pure modules live in
  `src/shared/pure/`.** Only the first is updated here. The other two are authority documents and are
  raised in Follow Ups for the user to change, per `CLAUDE.md`'s precedence rule.

### Phase 5: C03 — RoleService, the secret

> **C03 Done** (verbatim): roles assigned; a player who was Aswang last round is measurably less likely
> to draw it again; nothing about the assignment is readable from another client.
> **C03 Verify** (verbatim): `lune run tests/role-draw.test.luau` — over 10,000 seeded draws, back-to-back
> Aswang rate is below the unweighted baseline, and every player is eventually eligible (no starvation).
> `npm run check:secrecy` clean. **`exploit-auditor` is mandatory on this chunk** — if it finds one leak
> here, the chunk is not done regardless of what the tests say.

#### Step 5.1: Implement `RoleService` — the draw, the server-side store, the history

**File:** `src/server/Services/RoleService.luau`
**Verify:** `npm run analyze`

Server-only role table, in-memory history of the last `RepeatCooldownRounds` rounds, `Random.new()` with
no argument created once in `Init()`.

Replaces the stub wholesale. The full file:

```luau
--!strict
--[[
	RoleService — the secret (C03).

	This is the one piece of state the whole game rests on. Everything else in this repo can be wrong
	and the game is worse; this being wrong and the game is OVER, because knowing the imposter is the
	entire win condition (§4.2, §6.2, Appendix C).

	WHAT LEAVES THIS SERVICE, EXHAUSTIVELY
	--------------------------------------
	  · `RoleAssigned`, via :FireClient, to ONE player, carrying ONE field: that player's own role.
	  · `AssignRoles` returns the Aswang's UserId to RoundService, in server memory, so that the
	    existing Aswang-leaves case and the end-of-round reveal keep reading it where they already do.

	That is the whole list. Not an attribute, not a tag, not a Highlight, not a name colour, not a
	walkspeed, not a tool in a backpack, not a sound played to one player. §6.2 calls the last few
	"derived hints": none of them contains the word "role" and every one is readable by any client.
	`check:secrecy` catches the obvious three shapes and cannot see a derived hint at all — which is why
	`exploit-auditor` GATES this chunk.

	WHY THE ROSTER IS PASSED IN RATHER THAN READ
	--------------------------------------------
	`AssignRoles(candidates)` takes the roster instead of asking RoundService for it. Two reasons, and
	the second is the load-bearing one:

	  1. RoundService requires RoleService. If RoleService required RoundService back, the cycle would
	     error at require time and take the bootstrap with it.
	  2. `RoleDraw` is only reproducible-from-a-seed if `candidates` arrives in a DETERMINISTIC order,
	     and `Players:GetPlayers()` does not promise one. RoundService sorts. Putting the sort at the
	     call site keeps the ordering requirement next to the thing that satisfies it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- script.Parent is Services; script.Parent.Parent is the `Server` script that src/server/init.server.luau
-- becomes, and `pure` is a sibling folder of Services beneath it.
local RoleDraw = require(script.Parent.Parent.pure.RoleDraw)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type Role = Types.Role

local RoleService = {}

-- SERVER-ONLY state. None of these three tables is ever replicated, serialised, attributed or logged.
local roles: { [number]: Role } = {}

-- Most recent round FIRST, trimmed to Config.Roles.RepeatCooldownRounds. In memory only — C31 owns
-- disk. It is a DRAW INPUT, so it is as secret as the draw itself even though every past Aswang was
-- already revealed by RoundEnded: every input a client holds shrinks the search space for the seed.
local history: RoleDraw.History = {}

--[[
	THE SEED, and the single most dangerous line in this repository.

	`Random.new()` with NO ARGUMENT. Roblox seeds it from a source the client cannot observe.

	`Random.new(state.RoundNumber)` and `Random.new(os.time())` are both fatal: RoundNumber is in the
	snapshot every client receives, and a wall clock is a search space of a few thousand values. Either
	one, combined with the published roster and the published algorithm, lets an exploiter replay the
	draw locally and know the Aswang before ACTIVE — with no remote to intercept and nothing for
	`check:secrecy` to see. Putting RoleDraw under src/server/pure/ removes the algorithm from their
	reach as well; this line is the half that still has to be right.

	Created ONCE and reused, so the stream never restarts and consecutive rounds are not correlated.
]]
local rng: Random = nil :: any

--------------------------------------------------------------------------------
-- Queries. Server-side callers only.
--------------------------------------------------------------------------------

function RoleService.GetRole(player: Player): Role?
	return roles[player.UserId]
end

function RoleService.IsAswang(player: Player): boolean
	return roles[player.UserId] == Enums.Role.Aswang
end

--------------------------------------------------------------------------------
-- The draw
--------------------------------------------------------------------------------

--[[
	Called by RoundService.enterStarting with a SORTED list of the UserIds dealt into this round.
	Returns the Aswang's UserId so RoundService can keep it in the one place the reveal already reads.
]]
function RoleService.AssignRoles(candidates: { number }): number?
	table.clear(roles)

	local weights: RoleDraw.Weights = {
		Base = Config.Roles.BaseWeight,
		Recent = Config.Roles.RecentAswangWeight,
		Older = Config.Roles.OlderAswangWeight,
		HistoryRounds = Config.Roles.RepeatCooldownRounds,
	}

	local assignments = RoleDraw.draw(
		candidates,
		history,
		Config.Roles.AswangCount,
		weights,
		function(): number
			return rng:NextNumber()
		end
	)

	local aswangUserId: number? = nil

	for userId, role in assignments do
		roles[userId] = role

		if role == Enums.Role.Aswang then
			aswangUserId = userId
		end
	end

	if aswangUserId ~= nil then
		table.insert(history, 1, { aswangUserId })

		while #history > Config.Roles.RepeatCooldownRounds do
			table.remove(history)
		end
	end

	-- Told LAST, after the table is complete, so nothing can observe a half-assigned round.
	for userId, role in roles do
		local player = Players:GetPlayerByUserId(userId)

		if player == nil then
			-- Drawn, then disconnected inside STARTING. If it was the Aswang, RoundService's existing
			-- onPlayerRemoving case aborts the round; there is nothing to do here but not error.
			continue
		end

		-- A TYPED LOCAL, not an inline table. FireClient takes `...any`, so an inline literal is
		-- checked against nothing at all. This catches a wrong type and a missing field — it does NOT
		-- catch an EXTRA one, which is exactly the leak shape (see the Types.RoundEndedPayload comment
		-- that C01 left). Whatever is added here must be re-read as though every client received it.
		local payload: Types.RoleAssignedPayload = { Role = role }

		Remotes.Get("RoleAssigned"):FireClient(player, payload)
	end

	if Config.Debug.VerboseLogging then
		-- Deliberately COUNTS, never names. This line is one careless edit away from being the leak,
		-- and a Studio output window is a screenshot away from being public.
		print(`[RoleService] Drew {#candidates} roles.`)
	end

	return aswangUserId
end

-- Called by RoundService when a round ends and the lobby reopens. The HISTORY deliberately survives —
-- that is the whole anti-repeat mechanism — while the live assignments do not.
function RoleService.ClearRoles()
	table.clear(roles)
end

function RoleService.Init()
	rng = Random.new()
	table.clear(roles)
	table.clear(history)
end

function RoleService.Start() end

return RoleService
```

> **QUESTION** — `require(script.Parent.Parent.pure.RoleDraw)`. Rojo makes `src/server/init.server.luau`
> a `Script` named `Server` and nests `Services/` and `pure/` beneath it, so this path should resolve —
> but I have **not** confirmed it in a running Studio session, and this plan does not guess about Roblox
> behaviour. It is the first thing to check at first sync. If it does not resolve, the fix is a
> `ServerScriptService.Server.pure` lookup rather than a traversal, and the module must **not** be moved
> to `src/shared/` to make the require simpler — that would undo §1.1's entire decision.
>
> **IMPORTANT** — `local rng: Random = nil :: any` is initialised in `Init()`. `init.server.luau` runs
> every `Init()` before any `Start()`, so no caller can reach `AssignRoles` first. The `:: any` is the
> same idiom the bootstrap already uses for its `pcall` typing; the alternative, `Random?`, would push a
> nil check into the hot path for a value that is never nil after `Init()`.

#### Step 5.2: Fire `RoleAssigned` to exactly one player, carrying only their own role

**File:** `src/server/Services/RoleService.luau`
**Verify:** `npm run check:secrecy`

`:FireClient(player, payload)` in a loop over the roster — never `:FireAllClients`, never an attribute,
never a tag.

A review step over the file from 5.1, gated on the check that exists for exactly this. What
`check:secrecy` will and will not catch here, read from `check-secrecy.mjs` rather than assumed:

| Shape | Caught? |
| --- | --- |
| `Remotes.Get("RoundSnapshot"):FireAllClients({ Role = role })` | **yes** — not on the allowlist |
| `character:SetAttribute("Role", role)` | **yes** — attributes replicate to every client |
| `CollectionService:AddTag(char, "Aswang")` | **yes** — tags replicate to every client |
| `Remotes.Get("RoleAssigned"):FireClient(player, payload)` | allowed, by name, with a reason on record |
| `local x = aswangUserId` then `ev:FireAllClients(x)` twenty lines later | **no** — it cannot follow data flow |
| a Highlight, a walkspeed bump, a tool, a sound played to one player | **no** — no token names the secret |

The last two rows are why `exploit-auditor` gates this chunk and why the service adds **nothing** to the
Aswang's character in this phase. The speed change that C04 does add is applied only *while transformed*,
which is already public.

**Fire to every player, not only to the Aswang.** Three reasons, in order of weight:

1. C18 gates the transform button on the client's **own** `RoleAssigned`, never on a broadcast. A
   survivor's client needs to have been told something in order to know it is not the Aswang.
2. Uniform traffic. Every client receives exactly one `RoleAssigned` per round, so the *presence* of the
   message is not itself a signal to anything sitting between the server and a client.
3. It keeps the count of role carriers at one. A second private channel for "you are a survivor" would
   be a second thing to audit, and `check-secrecy.mjs`'s allowlist is only meaningful while it is short.

#### Step 5.3: Wire the draw into `RoundService.enterStarting`

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run check:remotes`

`RoleService.AssignRoles()` is called from `enterStarting`, and hands the Aswang's UserId back through a
setter so `state.AswangUserId` stays where the Aswang-leaves case and the reveal already read it.

```diff
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.Config)
 local Enums = require(Shared.Enums)
 local Remotes = require(Shared.Remotes)
+local RoleService = require(script.Parent.RoleService)
 local RoundTransitions = require(Shared.pure.RoundTransitions)
 local Types = require(Shared.Types)
```

```diff
 local function setAllPlayerStates(newState: PlayerState)
 	table.clear(state.PlayerStates)
 	for _, player in Players:GetPlayers() do
 		state.PlayerStates[player.UserId] = newState
 	end
 end
 
+--[[
+	The roster dealt into this round, SORTED.
+
+	The sort is not cosmetic. `RoleDraw.draw` is only reproducible from a seed if its candidate list
+	arrives in a stable order, and `Players:GetPlayers()` makes no such promise. Without it the draw is
+	still fair and still secret — but `tests/role-draw.test.luau` stops describing the game, because the
+	property it proves ("same stream, same Aswang") would no longer hold at the call site.
+]]
+local function dealtInUserIds(): { number }
+	local userIds = {}
+
+	for userId, playerState in state.PlayerStates do
+		if playerState == Enums.PlayerState.Alive then
+			table.insert(userIds, userId)
+		end
+	end
+
+	table.sort(userIds)
+
+	return userIds
+end
+
```

```diff
 local function enterIdle()
 	state.AswangUserId = nil
 	state.TasksCompleted = 0
 	state.GateOpen = false
+	-- The live assignments go; RoleService's HISTORY deliberately survives, because it is the whole
+	-- anti-repeat mechanism and a server that reset it every lobby would have no memory at all.
+	RoleService.ClearRoles()
 	-- Spectator status lifts here: whoever is on the server is a candidate for the next round.
 	setAllPlayerStates(Enums.PlayerState.Lobby)
 	setPhase(Enums.RoundPhase.Idle)
 end
 
 local function enterIntermission()
+	RoleService.ClearRoles()
 	setAllPlayerStates(Enums.PlayerState.Lobby)
 	setPhase(Enums.RoundPhase.Intermission, Config.Round.Intermission)
 end
 
 local function enterStarting()
 	state.RoundNumber += 1
 	-- Everyone present when the round is drawn is dealt in. Anyone arriving from here until the
 	-- next INTERMISSION becomes a SPECTATOR in onPlayerAdded.
 	setAllPlayerStates(Enums.PlayerState.Alive)
+
+	-- BEFORE setPhase, deliberately. setPhase fires PhaseChanged and pushes a snapshot to every
+	-- client; drawing first means no subscriber can observe a STARTING round that has no Aswang yet.
+	-- The snapshot carries no role either way — this is about services, not clients.
+	state.AswangUserId = RoleService.AssignRoles(dealtInUserIds())
+
 	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
-	-- TODO(C03): RoleService.AssignRoles()
 	-- TODO(C07): TaskService.SelectTasksForRound()
 end
```

> **IMPORTANT** — `RoundService` requires `RoleService`, and `RoleService` must **never** require
> `RoundService` back. A require cycle errors at load and `init.server.luau` swallows it into a single
> `warn` line, leaving a server that sits in IDLE forever and looks exactly like "nobody has joined
> yet". That is the failure shape C01 wrote its `Start()` ordering comment about.
>
> **NOTE** the phase is still set in exactly one place. `RoleService` is *called by* `enterStarting`; it
> does not set, read or react to the phase. Spec §6.4, and `CLAUDE.md`'s rule.
>
> **NOTE** `state.AswangUserId` keeps its existing meaning and its existing readers — `onPlayerRemoving`
> (the Aswang-leaves abort) and `enterEnding` (the reveal). Nothing new reads it, and nothing new
> broadcasts it.

#### Step 5.4: The 3-second private intro, on the client that owns the role

**File:** `src/client/Controllers/UIController.luau`
**Verify:** `npm run check:config`

The client caches its **own** role from `RoleAssigned` and shows the intro for `Config.Roles.IntroDuration`.
No client ever holds another player's role, and the duration is not typed into the controller.

Replaces the `UIController` stub's body. Ugly and functional — the themed version is C18/C26.

```luau
--!strict
--[[
	UIController — HUD: task bar, sunrise timer, role card, end screen.

	Milestone: M7. Today it owns exactly one thing: the 3-second private role intro (§4.2, C03).

	THIS CONTROLLER HOLDS THE ONLY COPY OF THE ROLE THAT EXISTS ON ANY CLIENT, and it is this client's
	OWN role, received on RoleAssigned. Two rules follow and they are not stylistic:

	  · `myRole` is a module local. It is never written to an attribute, a StringValue, the character,
	    or anything under ReplicatedStorage or Workspace — all of which replicate.
	  · Nothing on screen may differ between a survivor's client and the Aswang's EXCEPT what only that
	    player can see. A recording of the Aswang's screen is a confession; a recording of anyone else's
	    must not be.

	This controller must never learn anyone else's role. If a future screen needs one, the answer is
	that it does not — §4.8's reveal arrives on RoundEnded when the round is over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local UIController = {}

-- This client's OWN role, and nothing else. Read the header before adding to this.
local myRole: Types.Role? = nil

function UIController.GetMyRole(): Types.Role?
	return myRole
end

local function showIntro(role: Types.Role)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoleIntro"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new()
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = if role == Enums.Role.Aswang
		then "YOU ARE THE ASWANG.\nDo not get seen."
		else "You are a survivor.\nFinish five tasks and escape."
	label.Parent = screenGui

	screenGui.Parent = playerGui

	task.delay(Config.Roles.IntroDuration, function()
		screenGui:Destroy()
	end)
end

function UIController.Init() end

function UIController.Start()
	Remotes.Get("RoleAssigned").OnClientEvent:Connect(function(payload: Types.RoleAssignedPayload)
		myRole = payload.Role

		showIntro(payload.Role)
	end)
end

return UIController
```

> **IMPORTANT** — every number in this file comes from `Config` or is on `check-config.mjs`'s idiomatic
> list (`0`, `1`, `0.5`). `src/client/` **is** governed, so `task.delay(3, ...)` would fail the check —
> which is the point of gating this step on `npm run check:config`. `0.35` is a magic number and must
> either move to a `Config` entry or carry `-- config-ok: placeholder styling, replaced at C18`. Prefer
> the waiver: a scrim opacity that C18 will delete is not a balance knob, and `Config.luau` is for
> balance.
>
> **NOTE** the survivor branch is deliberate, not filler. If only the Aswang saw a card, the *absence*
> of a card would teach a new player what they are before they had learned there was anything to hide —
> and at C20 a first-round player is exactly who is watching.
>
> **NOTE** `src/client/init.client.luau` needs **no change**. It already requires and starts every
> controller in `CONTROLLER_ORDER`, and `UIController` is in it.

#### Step 5.5: C03 phase gate — and the auditor that outranks it

**File:** — (verification only)
**Verify:** `npm run verify`

`exploit-auditor` **gates this chunk**. A green tree here is necessary and not sufficient: if the auditor
finds one leak path, C03 is not done regardless of what any test reports.

| C03 Done, verbatim | How it is checked | Where |
| --- | --- | --- |
| roles assigned | `lune run tests/role-draw.test.luau` shape assertions; playtester sees the intro | 4.2, playtest |
| a player who was Aswang last round is **measurably** less likely | 10,000 seeded rounds, rate below the unweighted baseline | 4.2 |
| nothing about the assignment is readable from another client | `npm run check:secrecy` + **`exploit-auditor`** | 5.2, 5.5 |

**Run `exploit-auditor` concurrently with the `playtester`** — in one message, `run_in_background: true`.
They share no data: one drives the running place, the other reads the diff. Sequencing them only adds the
slower one's wall clock to the faster one's.

**What to point the auditor at**, because a scoped question gets a better answer than "audit this":

1. Every path out of `RoleService` — is `RoleAssigned`/`FireClient` genuinely the only one?
2. `dealtInUserIds()` and `RoleDraw` — could a client reproduce the roster, the history and the seed?
3. Derived hints on the Aswang's character during `STARTING` and `ACTIVE`, before any transform: speed,
   Highlight, backpack, sounds, attributes, tags.
4. `UIController.myRole` — does it reach any replicated container?
5. The `warn`/`print` lines added in Phases 3 and 5 — do any of them name a role, and would C40's
   analytics ship them off-server?

**A high score with no leak found is not the same as no leak.** `CLAUDE.md` is explicit that the score
measures the auditor's own evidence, and an auditor that could only read the code caps in the mid-60s.

#### Phase 5 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the whole phase. See the table in Step 5.2 for what `check:secrecy` catches and,
  more importantly, what it cannot: it does not follow data flow, and a *derived hint* contains no token
  it looks for.
- **Remote direction** — `RoleAssigned` is a DOWN event, fired from the server with `:FireClient`,
  listened to on the client with `.OnClientEvent`. All three halves are in this phase and
  `check:remotes` reads all three.
- **Rate limiting** — no `OnServerEvent` added. `RoleAssigned` is server→client, so there is nothing for
  a client to spam.
- **Magic numbers** — the weights are in `Config.Roles`, the intro duration is read not typed. The one
  judgement call is the placeholder scrim opacity; waive it rather than promoting it to a balance knob.
- **Phase ownership** — `RoleService` never touches the phase. `RoundService.enterStarting` calls it.
- **Player leaving mid-round** — three cases, and all three already have an owner:
  - drawn, then disconnects **inside STARTING** — `AssignRoles` skips a nil player rather than erroring;
    if it was the Aswang, `onPlayerRemoving` aborts the round, and that path is C01's, unchanged.
  - the Aswang disconnects during ACTIVE — `enterEnding(Aborted)`, unchanged.
  - a survivor disconnects — their `PlayerStates` entry is dropped; `roles` keeps a stale entry until the
    next `ClearRoles`. Harmless (nothing indexes `roles` by a departed player) but worth naming.
- **Strict Luau** — `Enums.Role.Aswang` carries its `:: Types.Role` cast already, so comparisons
  typecheck. `local rng: Random = nil :: any` is the deliberate idiom; a `Random?` would push a nil check
  into every draw.
- **Mobile budget** — one `ScreenGui` created and destroyed per round. No lights, no particles.
- **Scope** — clean. No second monster, no voting.

**Issues identified:**

- **`Random.new()`'s entropy source is documented behaviour I have not independently verified.** Roblox
  documents the no-argument form as arbitrarily seeded. This plan does not guess about Roblox APIs, so
  it is raised in Follow Ups with the concrete question: is the default seed derivable from anything a
  client observes? The `src/server/pure/` placement means even a weak seed does not hand over the
  algorithm, which is why that decision is defence in depth rather than belt-and-braces.
- **`require(script.Parent.Parent.pure.RoleDraw)` is unconfirmed in a running place.** See the QUESTION
  in Step 5.1. It is the first thing to check at first sync, and the fix is never "move it to shared".
- **`RoleAssigned` sits on `check-secrecy.mjs`'s `REVEAL_ALLOWLIST`, so the scanner skips the call
  entirely** rather than inspecting the payload. Combined with Luau accepting an **extra** field on an
  annotated table, a second field added to `RoleAssignedPayload` would pass both `npm run analyze` and
  `npm run check:secrecy`. C41 is chartered to add a field allowlist for the two reveal remotes; until
  then this payload is guarded by a habit and by the auditor.
- **A stale `roles` entry survives a disconnect** until the next `ClearRoles()`. Nothing reads it, and
  cleaning it up on `PlayerRemoving` would need `RoleService` to connect to `Players`, which is fine —
  it is left out only because "the roles table is cleared exactly at round boundaries" is easier to
  reason about than two clearing rules. Recorded so it is a decision rather than an oversight.

### Phase 6: C04a — transform validation and the first real remote handler

#### Step 6.1: Write `src/shared/pure/TransformRules.luau`

**File:** `src/shared/pure/TransformRules.luau`
**Verify:** `npm run analyze`

`(request) -> verdict`, where verdict is one of six literals. Every rule §4.3 states for the transform,
and nothing that needs a DataModel.

```luau
--!strict
--[[
	TransformRules — may this player transform right now, and if not, why not.

		(request) -> verdict

	§4.3 lists the transform's preconditions in prose. Every one of them is a comparison over numbers,
	booleans and two string enums — no raycast, no character, no DataModel — so all of it is testable
	from a terminal and none of it needs Studio. (C05's kill validation is the opposite case: the
	raycast is irreducibly Roblox, which is why `pure/KillValidation.luau` will be everything EXCEPT
	the raycast.)

	THIS ONE STAYS IN src/shared/pure/, unlike RoleDraw, and the difference is worth stating because it
	is the rule the next author will have to apply. A client can require and call this. It learns
	nothing: every input is either a value that client already holds (its own role, the phase, its own
	state) or a Config number that already replicates. Calling it locally produces a verdict with no
	authority — the server evaluates its own copy against its own state, which is the only one that
	counts. Logic is not secret; inputs and seeds are.

	THE VERDICT NEVER REACHES A CLIENT. It exists so the server can log WHY it refused: an exploiter
	probing the boundary and a real player mashing a key during INTERMISSION are the same `false` and
	very different events, and telling them apart is what C41 needs. Echoing it back would also hand a
	client a free oracle for `NOT_ASWANG`.

	NO `script.Parent` REQUIRES. The three enums are re-declared; Luau literal unions are structural,
	so these and their Types.luau counterparts are the same types.
]]

export type RoundPhase = "IDLE" | "INTERMISSION" | "STARTING" | "ACTIVE" | "ENDING"
export type PlayerState = "LOBBY" | "ALIVE" | "GHOST" | "SPECTATOR"

export type Verdict =
	"OK"
	| "NOT_ASWANG"
	| "WRONG_PHASE"
	| "NOT_ALIVE"
	| "ALREADY_TRANSFORMED"
	| "ON_COOLDOWN"

export type Request = {
	IsAswang: boolean,
	Phase: RoundPhase,
	PlayerState: PlayerState,
	Transformed: boolean,
	Now: number,
	LastRevertedAt: number?, -- nil means "has never transformed this round"
	Cooldown: number,
}

local TransformRules = {}

--[[
	The order of these checks is FIXED, and it is part of the contract rather than an implementation
	detail: it decides which reason a log line carries when more than one applies. A spectator who is
	also on cooldown should read as NOT_ALIVE, because that is the fact worth acting on.

	World-level facts first (phase, then liveness), then facts about this player (role), then facts
	about this player's monster state (already transformed, cooldown).
]]
function TransformRules.evaluate(request: Request): Verdict
	if request.Phase ~= "ACTIVE" then
		return "WRONG_PHASE"
	end

	--[[
		AN ALLOWLIST, NEVER A DENYLIST. `PlayerState ~= "SPECTATOR"` would read identically today and
		would admit LOBBY and GHOST — and C15 makes GHOST real, at which point a dead player transforms.
		`PlayerState` has four values and exactly one of them may act.

		This is C04's carried-over warning from C01, and Step 7.2 is where the test proves all four.
	]]
	if request.PlayerState ~= "ALIVE" then
		return "NOT_ALIVE"
	end

	if not request.IsAswang then
		return "NOT_ASWANG"
	end

	if request.Transformed then
		return "ALREADY_TRANSFORMED"
	end

	--[[
		THE COOLDOWN RUNS FROM REVERT, NOT FROM THE TRANSFORM (§4.3 step 5).

		Measured from the transform, an Aswang who holds the form for its full duration serves most of
		the cooldown while still being a monster, and the "every kill is a gamble" pillar collapses:
		the punishment for a failed hunt would be nearly zero. `tests/config.test.luau` already pins
		`KillCooldown > TransformTime + RevertTime` for the same reason.

		A nil LastRevertedAt means this is the round's first transform, which is never on cooldown.
	]]
	local lastRevertedAt = request.LastRevertedAt

	if lastRevertedAt ~= nil and request.Now - lastRevertedAt < request.Cooldown then
		return "ON_COOLDOWN"
	end

	return "OK"
end

return TransformRules
```

> **QUESTION** — `Cooldown` is fed from `Config.Monster.KillCooldown`, because §4.3 names exactly one
> cooldown ("Kill cooldown: 30s from revert") and `Config` carries exactly one. So the re-transform gate
> and the kill gate are the same 30 seconds. That is a defensible reading and it is the one the shipped
> numbers assume — but it is a *reading*, and C05 may want them separate (a monster that can re-transform
> before it can kill is a real design option). Raised in Follow Ups. The parameter is named `Cooldown`
> rather than `KillCooldown` precisely so splitting them later is a Config change and a call-site change,
> not a rewrite of this module.

#### Step 6.2: Write `tests/transform-rules.test.luau`

**File:** `tests/transform-rules.test.luau`
**Verify:** `lune run tests/transform-rules.test.luau`

All six verdicts, the cooldown boundary at exactly `KillCooldown`, and the rule that the cooldown is
measured **from revert**, not from the transform.

```luau
--!strict
--[[
	tests/transform-rules.test.luau

	§4.3's transform preconditions, each one proven to REFUSE as well as to allow.

	The allow half is the half that gets written and the half that matters least. A rule engine that
	only ever says OK passes a happy-path test and hands the game to the first person who fires the
	remote from the lobby. So every case below appears twice: once where the rule permits, once where
	it is the only thing standing in the way.

	Step 7.2 extends the PlayerState block to all four states. Everything else lands here.
]]

local Config = require("../src/shared/Config")
local TransformRules = require("../src/shared/pure/TransformRules")

local failures = 0

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		return
	end

	failures += 1
	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
end

-- A request that passes every rule. Each case below breaks exactly one field, so a failure names the
-- rule that broke rather than "something in the table".
local function request(overrides: { [string]: any }): TransformRules.Request
	local base: TransformRules.Request = {
		IsAswang = true,
		Phase = "ACTIVE",
		PlayerState = "ALIVE",
		Transformed = false,
		Now = 1000,
		LastRevertedAt = nil,
		Cooldown = Config.Monster.KillCooldown,
	}

	for key, value in overrides do
		(base :: any)[key] = value
	end

	return base
end

local function verdict(overrides: { [string]: any }): TransformRules.Verdict
	return TransformRules.evaluate(request(overrides))
end

--------------------------------------------------------------------------------
-- The happy path
--------------------------------------------------------------------------------

check("a live Aswang in ACTIVE with no history may transform", verdict({}) == "OK", verdict({}))

--------------------------------------------------------------------------------
-- Phase
--------------------------------------------------------------------------------

for _, phase in { "IDLE", "INTERMISSION", "STARTING", "ENDING" } do
	check(`transforming during {phase} is refused`, verdict({ Phase = phase }) == "WRONG_PHASE")
end

--------------------------------------------------------------------------------
-- Role
--------------------------------------------------------------------------------

check("a survivor may not transform", verdict({ IsAswang = false }) == "NOT_ASWANG")

--------------------------------------------------------------------------------
-- Already transformed — the double-tap, and the exploiter's re-entry
--------------------------------------------------------------------------------

check(
	"transforming while transformed is refused",
	verdict({ Transformed = true }) == "ALREADY_TRANSFORMED"
)

--------------------------------------------------------------------------------
-- Cooldown, measured FROM REVERT
--------------------------------------------------------------------------------

do
	local cooldown = Config.Monster.KillCooldown

	check(
		"one second after reverting is refused",
		verdict({ Now = 1000, LastRevertedAt = 999 }) == "ON_COOLDOWN"
	)

	-- The boundary, both sides. An off-by-one here is a rule that is silently a second wrong forever.
	check(
		"a hair under the cooldown is refused",
		verdict({ Now = 1000, LastRevertedAt = 1000 - cooldown + 0.01 }) == "ON_COOLDOWN"
	)

	check(
		"exactly the cooldown is allowed",
		verdict({ Now = 1000, LastRevertedAt = 1000 - cooldown }) == "OK"
	)

	check(
		"long past the cooldown is allowed",
		verdict({ Now = 1000, LastRevertedAt = 1000 - cooldown * 2 }) == "OK"
	)

	-- THE RULE THAT IS EASY TO GET BACKWARDS. Measured from the transform instead of the revert, an
	-- Aswang serves most of its cooldown while still being a monster. A full cycle is
	-- TransformTime + MaxTransformTime + RevertTime, and that must still leave time on the clock.
	local cycle = Config.Monster.TransformTime + Config.Monster.MaxTransformTime + Config.Monster.RevertTime

	check(
		"a full transform cycle does not itself exhaust the cooldown",
		cycle < cooldown,
		`cycle={cycle}s, cooldown={cooldown}s`
	)

	check(
		"the first transform of a round is never on cooldown",
		verdict({ Now = 0, LastRevertedAt = nil }) == "OK"
	)
end

--------------------------------------------------------------------------------
-- Precedence — which reason wins when several apply
--------------------------------------------------------------------------------

do
	-- Not correctness so much as log stability: C41 reads these reasons, and a reason that changes
	-- because an unrelated rule was reordered is a metric that quietly stops meaning anything.
	check(
		"phase outranks role",
		verdict({ Phase = "IDLE", IsAswang = false }) == "WRONG_PHASE"
	)

	check(
		"liveness outranks role",
		verdict({ PlayerState = "GHOST", IsAswang = false }) == "NOT_ALIVE"
	)

	check(
		"role outranks the cooldown",
		verdict({ IsAswang = false, LastRevertedAt = 999.9 }) == "NOT_ASWANG"
	)
end

if failures > 0 then
	error(`{failures} transform-rule failure(s)`, 0)
end

print("  PASS  transform-rules: 6 verdicts, cooldown boundary, precedence")
```

#### Step 6.3: `MonsterService` — `RequestTransform`, rate-limited first, validated second

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:ratelimit`

The first `OnServerEvent` handler in the repo. `AntiCheatService.Consume` is the first statement in the
body; `TransformRules.evaluate` is the second.

Replaces the stub. This step lands the head of the file — requires, state, and the handler; Step 6.4
lands the transform body it calls.

```luau
--!strict
--[[
	MonsterService — the transform (C04). §4.3 steps 1–3.

	THE TRANSFORM IS PUBLIC BY DESIGN, and that is the whole point of the mechanic. It is the only
	thing in this game that legitimately reveals the Aswang, it is the game's signature clippable
	moment, and it gives survivors real information with no UI at all — which is what makes grouping
	up genuinely protective. Broadcasting it is correct, not a compromise.

	Read that alongside RoleService's header and the asymmetry is the design: the identity never
	leaves the server, and the ACT of transforming is shouted to everybody. A player who witnesses it
	learns who the Aswang is by seeing, which is exactly the game.

	NO CUSTOM MESH (§4.3, and §3's OUT list). The avatar is reused with a scale change, a colour and
	material shift, glowing eyes and a particle emitter. That is why this mechanic is cheap, and
	"cheap" is load-bearing for a project with no art budget.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local RoleService = require(script.Parent.RoleService)
local RoundService = require(script.Parent.RoundService)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local TransformRules = require(Shared.pure.TransformRules)
local Types = require(Shared.Types)

local MonsterService = {}

type MonsterState = {
	Transformed: boolean,
	LastRevertedAt: number?, -- nil until the first revert of the round; drives the cooldown
	BaseWalkSpeed: number?, -- captured at transform so revert restores rather than assumes 16
	RevertThread: thread?, -- the forced-revert timer, cancelled by an earlier revert (Step 7.1)
}

-- SERVER-ONLY, keyed by UserId. Note what is NOT here: the role. That lives in RoleService and is
-- asked for per request, so this table cannot become a second place the secret is kept.
local monsters: { [number]: MonsterState } = {}

local function stateFor(userId: number): MonsterState
	local existing = monsters[userId]

	if existing ~= nil then
		return existing
	end

	local created: MonsterState = {
		Transformed = false,
		LastRevertedAt = nil,
		BaseWalkSpeed = nil,
		RevertThread = nil,
	}

	monsters[userId] = created

	return created
end

function MonsterService.IsTransformed(player: Player): boolean
	return stateFor(player.UserId).Transformed
end

--------------------------------------------------------------------------------
-- The remote. THE FIRST OnServerEvent HANDLER IN THIS REPOSITORY.
--------------------------------------------------------------------------------

local function onRequestTransform(player: Player)
	--[[
		RATE LIMIT FIRST, BEFORE ANY WORK. Not stylistic:

		  · `check-ratelimit.mjs` looks for an AntiCheat call within 1200 characters of the
		    `.OnServerEvent:Connect(`, so a guard placed after a long validation block is a guard the
		    gate may not see.
		  · More importantly, everything below this line reads service state and allocates. A handler
		    that validates before it limits is a free firehose that happens to return false — the cost
		    is paid whether or not the request was legitimate.
	]]
	if not AntiCheatService.Consume(player, "RequestTransform") then
		return
	end

	local monster = stateFor(player.UserId)

	-- Every input is read from the SERVER's own state. The client sent no arguments and could not
	-- usefully send any: there is nothing about this decision it is entitled to assert.
	local decision = TransformRules.evaluate({
		IsAswang = RoleService.IsAswang(player),
		Phase = RoundService.GetPhase(),
		PlayerState = RoundService.GetPlayerState(player),
		Transformed = monster.Transformed,
		Now = os.clock(),
		LastRevertedAt = monster.LastRevertedAt,
		Cooldown = Config.Monster.KillCooldown,
	})

	if decision ~= "OK" then
		-- GATED, and it must stay gated. `NOT_ASWANG` in a log line is a statement about a player's
		-- role. It is safe on a server console and it is NOT safe as a C40 analytics event, which is
		-- exactly the kind of pipe this line will be near when someone is wiring up funnels.
		if Config.Debug.VerboseLogging then
			print(`[Monster] Refused RequestTransform from {player.Name}: {decision}`)
		end

		return
	end

	MonsterService.BeginTransform(player, monster)
end

function MonsterService.Init()
	table.clear(monsters)
end

function MonsterService.Start()
	Remotes.Get("RequestTransform").OnServerEvent:Connect(onRequestTransform)

	Players.PlayerRemoving:Connect(function(player: Player)
		local monster = monsters[player.UserId]

		if monster ~= nil and monster.RevertThread ~= nil then
			task.cancel(monster.RevertThread)
		end

		monsters[player.UserId] = nil
	end)
end

return MonsterService
```

> **IMPORTANT** — `check:ratelimit` stops being vacuous at this step. It has passed since the scaffold
> because no `OnServerEvent` handler existed; this is the one that gives it something to check, which
> is why it is this step's gate rather than a later one's.
>
> **NOTE** the handler takes **no client arguments**. Nothing needs validating for type, because
> nothing was sent — the request is the whole message. Extra arguments a compromised client appends are
> ignored by construction rather than by a check. C05's `RequestKill(targetUserId)` is the first handler
> that will have to validate a client-supplied value.
>
> **NOTE** the require graph stays acyclic: `MonsterService → RoundService → RoleService`, and
> `MonsterService → RoleService`, `MonsterService → AntiCheatService`. Nothing requires `MonsterService`.

#### Step 6.4: The windup, the broadcast, and the avatar mutation

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run check:config`

1.2s windup, then `MonsterTransformed` to all clients. Scale, colour/material, eye glow, particles and
`+25%` walkspeed — all server-set, all read from `Config.Monster`. **No custom mesh** (§4.3).

First, the Config the visuals read. Note the RGB triples — this is not a style preference:

```diff
 	Monster = {
 		TransformTime = 1.2, -- visible windup — the core risk/reward moment
 		RevertTime = 1.0,
 		MaxTransformTime = 8, -- forced revert if no kill
 		KillRange = 8, -- studs
 		KillCooldown = 30, -- seconds after revert
 		TransformedSpeedMult = 1.25,
 		TransformAudioRange = 40, -- how far the transform sound carries
 		CorpseDuration = 45,
+
+		--[[
+			Appearance while transformed. §4.3: NO CUSTOM MESH. The player's own avatar is reused with
+			a scale change, a colour and material shift, glowing eyes and a particle emitter — which is
+			why this mechanic costs nothing to build and why §3 puts a custom monster mesh on the OUT
+			list.
+
+			COLOURS ARE RGB TRIPLES, NOT Color3 VALUES, and that is load-bearing rather than fussy:
+			`tests/config.test.luau` requires this file under LUNE, which has no Roblox datatypes at
+			all. A `Color3.fromRGB(...)` here does not fail to typecheck — it fails at test time, in
+			every balance test at once, with an error naming Config rather than the edit that broke it.
+			MonsterService builds the Color3.
+		]]
+		TransformedScale = 1.15,
+		TransformedTintRgb = { 90, 20, 20 },
+		EyeGlowRgb = { 255, 45, 45 },
+		EyeGlowRange = 6,
+		EyeGlowBrightness = 3,
+		TransformParticleRate = 12,
 	},
```

Then the body of `MonsterService`, inserted above the remote handler:

```luau
local function rgb(triple: { number }): Color3
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

--[[
	Scale the avatar. R15 exposes these as NumberValues under the Humanoid; R6 has no equivalent and
	the loop simply finds nothing.

	RIG TYPE IS A PLACE-FILE SETTING AND THE PLACE FILE IS NOT IN GIT, so nothing in this repository
	can tell you which one is in use — see the plan's Follow Ups. The FindFirstChild guards make this
	correct either way: on R6 the Aswang gets the colour, material, eyes, particles and speed, and
	does not grow. That is a weaker tell, not a broken one, and it is a thing to LOOK AT during the
	two-client test rather than a thing to assume.
]]
local SCALE_VALUES = { "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }

local function applyScale(humanoid: Humanoid, scale: number)
	for _, name in SCALE_VALUES do
		local value = humanoid:FindFirstChild(name)

		if value ~= nil and value:IsA("NumberValue") then
			value.Value = scale
		end
	end
end

-- Everything added to the character is parented under one folder, so reverting is a Destroy rather
-- than a list of things to remember to remove. The folder replicates, which is correct: the point is
-- that everyone sees it.
local FX_FOLDER = "AswangTransformFX"

local function addLook(character: Model)
	local existing = character:FindFirstChild(FX_FOLDER)

	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = FX_FOLDER

	local head = character:FindFirstChild("Head")

	if head ~= nil and head:IsA("BasePart") then
		-- Two PointLights, one per eye socket, both counted against Config.Performance.MaxVisibleLights.
		for _, side in { -1, 1 } do
			local light = Instance.new("PointLight")
			light.Color = rgb(Config.Monster.EyeGlowRgb)
			light.Range = Config.Monster.EyeGlowRange
			light.Brightness = Config.Monster.EyeGlowBrightness
			light.Parent = head

			-- `side` positions the light; kept as a plain multiplier so the eye offset is a property
			-- of the head rather than another Config knob nobody will tune.
			light.Name = `AswangEye{side}`
			folder:SetAttribute(light.Name, true)
		end

		local particles = Instance.new("ParticleEmitter")
		particles.Rate = Config.Monster.TransformParticleRate
		particles.Color = ColorSequence.new(rgb(Config.Monster.TransformedTintRgb))
		particles.Parent = head
	end

	folder.Parent = character
end

local function restoreLook(character: Model)
	local folder = character:FindFirstChild(FX_FOLDER)

	if folder ~= nil then
		folder:Destroy()
	end

	local head = character:FindFirstChild("Head")

	if head ~= nil then
		for _, child in head:GetChildren() do
			if child:IsA("PointLight") or child:IsA("ParticleEmitter") then
				child:Destroy()
			end
		end
	end
end

--[[
	§4.3 step 1–3, in order, and the ORDER IS THE DESIGN.

	The broadcast fires FIRST, at the start of the windup — not after it. §4.3: "1.2s transform
	animation, visible to anyone with line of sight". The animation IS the tell, so everyone must be
	able to watch it happen. The mechanical payoff (+25% speed, and the kill at C05) arrives only when
	the windup completes.

	Firing the broadcast after the windup instead would make the transform instantaneous to observers
	and would delete the risk half of the risk/reward moment the whole game is built on.
]]
function MonsterService.BeginTransform(player: Player, monster: MonsterState)
	local character = player.Character

	if character == nil then
		return
	end

	-- Set BEFORE the yield below. A second request arriving during the windup must see
	-- ALREADY_TRANSFORMED, and `task.wait` is a yield point where exactly that can happen.
	monster.Transformed = true

	local payload: Types.MonsterTransformedPayload = { Character = character, Transformed = true }

	Remotes.Get("MonsterTransformed"):FireAllClients(payload)

	addLook(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid ~= nil then
		applyScale(humanoid, Config.Monster.TransformedScale)
	end

	task.wait(Config.Monster.TransformTime)

	-- Re-read the character: a yield is a place where a player can die, respawn or leave.
	if player.Character ~= character or not monster.Transformed then
		return
	end

	if humanoid ~= nil then
		monster.BaseWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = humanoid.WalkSpeed * Config.Monster.TransformedSpeedMult
	end

	MonsterService.ScheduleForcedRevert(player, monster)
end
```

> **IMPORTANT** — the walkspeed is stored and restored, never assumed. Writing `humanoid.WalkSpeed = 16`
> on revert would fail `check:config` *and* would silently overwrite whatever a future chunk sets — the
> Solo Trial, a stun, a cosmetic. Capturing the base at transform time is the only version that composes.
>
> **IMPORTANT** — `+25% walkspeed is a derived hint the instant it is applied outside the transform.**
> §6.2 names exactly this shape. It is applied here only *after* `MonsterTransformed` has already told
> every client what is happening, and it is removed at revert. A speed multiplier that outlived the
> transform would be a permanent, silent, client-readable marker of the Aswang.
>
> **QUESTION** — avatar scaling. The `Humanoid` `NumberValue` approach is R15-only, and the rig type
> lives in the place file, which is gitignored. The code is written to no-op safely on R6 rather than to
> guess. Confirm in Studio during the C04 test and record the answer in Follow Ups; `Model:ScaleTo` is
> the alternative and this plan does not assume its behaviour on a character with a `Humanoid`.

#### Step 6.5: Phase 6 gate

**File:** — (verification only)
**Verify:** `npm run verify:fast`

#### Phase 6 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the transform is public and that is correct. Two things to keep checking: the
  broadcast carries a `Model` and a boolean, never a role or a UserId; and nothing added to the
  character in `addLook` survives a revert. An FX folder left behind is a permanent marker naming the
  Aswang, and it would replicate. `restoreLook` (Step 7.1) is what stops that.
- **Remote direction** — `RequestTransform` is UP, fired from the client, listened to on the server with
  `.OnServerEvent`. `MonsterTransformed` is DOWN and broadcast. Both are declared already.
- **Rate limiting** — `AntiCheatService.Consume` is the first statement in the handler. This is the step
  where `check:ratelimit` becomes meaningful.
- **Magic numbers** — every visual number moves to `Config.Monster` in Step 6.4. Watch the ones that do
  not look like knobs: a particle `Rate`, a light `Range`, a scale. `check:config` flags all three.
- **Phase ownership** — `MonsterService` **reads** `RoundService.GetPhase()` and never sets it. The
  phase subscription added in Step 7.1 is a listener on `PhaseChanged`, not a writer.
- **Player leaving mid-round** — `PlayerRemoving` cancels a pending revert thread and drops the state. A
  cancelled thread that was mid-`task.wait` never runs its body, so the character it captured is not
  touched after the player is gone.
- **Strict Luau** — the table passed to `TransformRules.evaluate` is checked against
  `TransformRules.Request` because the parameter is typed; the phase and player state come from
  `RoundService`, which returns `Types.RoundPhase` and `Types.PlayerState`, and those unions are
  structurally identical to the ones re-declared in the pure module. No cast is needed, and if the
  analyzer disagrees the fix is to align the unions, never to add `:: any`.
- **Mobile budget** — **two `PointLight`s per transformed Aswang**, against `MaxVisibleLights = 8`. One
  Aswang means two lights, which is fine; it is worth knowing that C14's reveal glow and C28's lighting
  pass both draw from the same budget. The `ParticleEmitter` runs at 12/s on one part.
- **Scope** — no custom mesh, no second monster, no weapon. `check:scope` splits identifiers on case, so
  none of `TransformedTintRgb` or `AswangEye` can trip it.

**Issues identified:**

- **`task.wait` inside `BeginTransform` is a yield, and a yield is where the world changes.** The
  character is re-read after it and the `Transformed` flag re-checked, because a player can die,
  respawn, leave or be salted (C14) during those 1.2 seconds. This is the single most likely place for a
  "the Aswang is stuck as a monster" bug to be introduced later.
- **The rig type is unknown to this repository.** Avatar scaling is R15-only and the place file is
  gitignored. The code no-ops safely on R6; the answer has to come from Studio.
- **The transform windup and `MaxTransformTime` measure from different instants** — see Step 7.1, which
  starts the forced-revert clock when the windup *completes*, so `MaxTransformTime` means eight seconds
  of being the monster rather than eight seconds that include becoming one. That is a reading of §4.3,
  and it is the reading Appendix A's tuning advice assumes.
- **A refused transform is invisible to the player.** No feedback remote exists and none is added — the
  client will simply see nothing happen. That is acceptable for C04 and is a real FTUE problem at C18,
  where the button should be disabled rather than silently ignored.

### Phase 7: C04 — revert, containment, and the two-client proof

> **C04 Done** (verbatim): any player with line of sight sees the transform; the Aswang cannot stay
> transformed past 8s.
> **C04 Verify** (verbatim): playtester: two clients in Studio, one transforms, screenshot from the
> *other* client's camera showing the silhouette. That screenshot is the artifact.

#### Step 7.1: Forced revert at `MaxTransformTime`, with the 1.0s revert animation

**File:** `src/server/Services/MonsterService.luau`
**Verify:** `npm run analyze`

A server-owned timer, cancelled on an early revert, on death, on phase change and on disconnect. The kill
cooldown clock starts at **revert** and is stored for C05 to read.

```diff
 local AntiCheatService = require(script.Parent.AntiCheatService)
 local RoleService = require(script.Parent.RoleService)
 local RoundService = require(script.Parent.RoundService)
 
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
 local Remotes = require(Shared.Remotes)
```

```luau
--[[
	The forced revert. §4.3: "After a kill (or after 8s), it must revert."

	WHICH INSTANT MaxTransformTime IS MEASURED FROM, and why it is this one: the clock starts when the
	WINDUP COMPLETES, not when the player pressed the button. So MaxTransformTime means eight seconds of
	being the monster, rather than eight seconds that include the 1.2 spent becoming one. Appendix A's
	advice ("raise if the Aswang can't get kills") only makes sense under that reading, and a full cycle
	is then TransformTime + MaxTransformTime + RevertTime = 10.2s, comfortably inside the 30s cooldown —
	which `tests/transform-rules.test.luau` pins.
]]
function MonsterService.ScheduleForcedRevert(player: Player, monster: MonsterState)
	if monster.RevertThread ~= nil then
		task.cancel(monster.RevertThread)
	end

	monster.RevertThread = task.delay(Config.Monster.MaxTransformTime, function()
		MonsterService.Revert(player)
	end)
end

--[[
	Revert, from any cause: the forced timer, a phase change, C14's salt, C05's kill.

	THE SELF-CANCELLATION TRAP. `Revert` is called BY the thread stored in `RevertThread`, so cancelling
	that thread unconditionally means a `task.cancel` on the coroutine currently running this function —
	which kills it mid-way and leaves the player transformed forever with the flag already cleared. The
	`coroutine.running()` comparison is the whole guard, and this is the kind of bug that only appears on
	the forced-revert path, i.e. only when the Aswang failed to get a kill.
]]
function MonsterService.Revert(player: Player)
	local monster = monsters[player.UserId]

	if monster == nil or not monster.Transformed then
		return
	end

	monster.Transformed = false

	if monster.RevertThread ~= nil and monster.RevertThread ~= coroutine.running() then
		task.cancel(monster.RevertThread)
	end

	monster.RevertThread = nil

	local character = player.Character

	-- Told immediately, at the START of the 1.0s revert animation, for the same reason the transform is:
	-- the animation is visible and everyone should see it happen.
	if character ~= nil then
		local payload: Types.MonsterTransformedPayload = { Character = character, Transformed = false }

		Remotes.Get("MonsterTransformed"):FireAllClients(payload)
	end

	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil

	-- Speed drops at the START of the revert. Holding +25% through the revert animation would let a
	-- failed hunt end with a free escape, and it would leave a client-readable marker on a player who
	-- is, as far as everyone watching is concerned, human again.
	if humanoid ~= nil and monster.BaseWalkSpeed ~= nil then
		humanoid.WalkSpeed = monster.BaseWalkSpeed
		monster.BaseWalkSpeed = nil
	end

	task.wait(Config.Monster.RevertTime)

	if character ~= nil then
		restoreLook(character)

		if humanoid ~= nil then
			applyScale(humanoid, 1)
		end
	end

	-- SET AT THE END, when the player is fully human again — §4.3 step 5, "30s from revert". Setting it
	-- when the revert BEGAN would hand back a second of cooldown for free every cycle.
	monster.LastRevertedAt = os.clock()
end
```

And the phase subscription, added to `MonsterService.Start()`:

```diff
 function MonsterService.Start()
 	Remotes.Get("RequestTransform").OnServerEvent:Connect(onRequestTransform)
 
+	--[[
+		`.Event`, because RoundService.PhaseChanged is a BindableEvent rather than a signal object.
+		`PhaseChanged:Connect(...)` is the natural thing to type and it errors at runtime inside a
+		pcall'd Start(), which surfaces as one warn line and a service that silently never reacts.
+
+		MonsterService SUBSCRIBES. It never calls setPhase — spec §6.4, and RoundService owns the phase.
+	]]
+	RoundService.PhaseChanged.Event:Connect(function(newPhase: Types.RoundPhase)
+		if newPhase == Enums.RoundPhase.Active then
+			return
+		end
+
+		-- Leaving ACTIVE for any reason — a win, the sunrise, an abort — un-transforms everybody. An
+		-- Aswang left mid-transform when the round ended would still be a monster on the end screen and
+		-- would carry the look into the next round's lobby.
+		for userId in monsters do
+			local player = Players:GetPlayerByUserId(userId)
+
+			if player ~= nil then
+				task.spawn(MonsterService.Revert, player)
+			end
+		end
+
+		-- STARTING is a new round: cooldowns and transform history do not carry over. Reverting first
+		-- (above) means no pending thread is orphaned by the clear.
+		if newPhase == Enums.RoundPhase.Starting then
+			table.clear(monsters)
+		end
+	end)
+
 	Players.PlayerRemoving:Connect(function(player: Player)
```

> **IMPORTANT** — `task.spawn(MonsterService.Revert, player)` rather than a direct call. `Revert` yields
> for `RevertTime`, and yielding inside a `BindableEvent` handler would stall `setPhase` — which runs
> inside `RoundService`'s tick loop, ahead of the snapshot broadcast. One yielding subscriber would delay
> every client's phase update by a second.
>
> **NOTE** iterating `monsters` while `Revert` mutates entries is safe here because `Revert` only writes
> to existing entries and never adds or removes keys; the removal happens in `PlayerRemoving` and the
> clear happens after the loop.

#### Step 7.2: Spectator containment — an allowlist, never a denylist

**File:** `src/shared/pure/TransformRules.luau`, `tests/transform-rules.test.luau`,
`src/server/Services/MonsterService.luau`
**Verify:** `lune run tests/transform-rules.test.luau`

C04's carried-over warning. Transform eligibility is gated on `PlayerState == ALIVE`, proven for all four
states in the pure test. The *body* half of containment is premise-unverified and is Step 7.5.

The rule half is already in `TransformRules.evaluate` from Step 6.1 and already wired in Step 6.3. What
this step adds is the **proof**, which is what makes it a step rather than a comment:

```diff
 --------------------------------------------------------------------------------
 -- Role
 --------------------------------------------------------------------------------
 
 check("a survivor may not transform", verdict({ IsAswang = false }) == "NOT_ASWANG")
 
+--------------------------------------------------------------------------------
+-- Liveness — an ALLOWLIST, and the reason it must be one
+--------------------------------------------------------------------------------
+
+--[[
+	`PlayerState ~= "SPECTATOR"` reads identically today and is wrong in a way that only shows up later:
+	PlayerState has FOUR values, so a denylist also admits LOBBY and GHOST. C15 makes GHOST real, and a
+	ghost that can transform — or, once C05 lands, be killed — is the kind of bug that gets found by a
+	player rather than by a test.
+
+	Written as an exhaustive loop over all four states rather than three spot checks, so adding a fifth
+	state to Types.PlayerState and forgetting it here fails immediately.
+]]
+local ALL_PLAYER_STATES: { TransformRules.PlayerState } = { "LOBBY", "ALIVE", "GHOST", "SPECTATOR" }
+
+check("every PlayerState is covered", #ALL_PLAYER_STATES == 4, `got {#ALL_PLAYER_STATES}`)
+
+for _, playerState in ALL_PLAYER_STATES do
+	local expected = if playerState == "ALIVE" then "OK" else "NOT_ALIVE"
+
+	check(
+		`a {playerState} player transforming -> {expected}`,
+		verdict({ PlayerState = playerState }) == expected,
+		verdict({ PlayerState = playerState })
+	)
+end
+
```

Update the closing line to match:

```diff
-print("  PASS  transform-rules: 6 verdicts, cooldown boundary, precedence")
+print("  PASS  transform-rules: 6 verdicts, all 4 player states, cooldown boundary, precedence")
```

> **IMPORTANT — the half this step does NOT deliver, stated plainly.** C04's warning block asks for a
> spectator to be *contained*: no character, or an observer camera and no collision. This step delivers
> only the **rule** — a spectator cannot transform. It does not stop a spectator walking the Barrio ten
> studs from a transforming Aswang and watching it happen.
>
> That half is deliberately not planned, because **its premise is unverified and this plan does not guess
> about Roblox behaviour.** What is established is that nothing in `src/` prevents a spectator spawning:
> no `CharacterAutoLoads`, `LoadCharacter` or teleport logic exists anywhere in the tree. But the place
> file is gitignored, so a `SpawnLocation` or a property set in Studio could already handle it and no
> check in this repository would see it.
>
> **Verify the premise in Studio before building the fix** — join mid-round as a second client and look.
> If the spectator does spawn and walk, the containment work is a small follow-on chunk, and it belongs
> before C05 rather than inside C04: once a kill exists, an uncounted spectator is also an unkillable
> one. Raised in Follow Ups with that ordering.

#### Step 7.3: Client reaction to `MonsterTransformed`

**File:** `src/client/Controllers/CameraFXController.luau`, `src/client/Controllers/AudioController.luau`,
`src/client/Controllers/InputController.luau`
**Verify:** `npm run check:secrecy`

Every client reacts to the transform because that is the point. No client infers a role from anything
other than the broadcast it was sent — and the input that *sends* `RequestTransform` is gated on the
client's own `RoleAssigned`, never on a broadcast.

**`InputController` — the minimum input, because without it C04 cannot be tested by a human at all.**
C18 owns the real mobile button; this is a keyboard bind so the two-client test in Step 7.5 is possible.

```luau
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIController = require(script.Parent.UIController)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local Remotes = require(Shared.Remotes)

local TRANSFORM_ACTION = "AswangTransform"

function InputController.Start()
	ContextActionService:BindAction(TRANSFORM_ACTION, function(_, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		--[[
			GATED ON THIS CLIENT'S OWN ROLE, from its own RoleAssigned. Never on a broadcast, never on
			anything derived from another player.

			This gate is UX and rate-limit courtesy, NOT security: the server re-evaluates every rule in
			TransformRules against its own state and refuses regardless of what the client believes. A
			compromised client can delete this check and gain exactly nothing, which is the correct
			relationship between a client-side gate and a server-side one.
		]]
		if UIController.GetMyRole() ~= Enums.Role.Aswang then
			return Enum.ContextActionResult.Pass
		end

		Remotes.Get("RequestTransform"):FireServer()

		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.T)
end
```

**`CameraFXController` — the witness reaction.** Every client runs this, including the Aswang's.

```luau
Remotes.Get("MonsterTransformed").OnClientEvent:Connect(function(payload: Types.MonsterTransformedPayload)
	--[[
		NO ROLE INFERENCE IS STORED. The client may draw whatever conclusion a human would from watching
		a neighbour sprout eyes — that is the game — but nothing here writes "that player is the Aswang"
		into a variable, an attribute, or anything else another client could read back.

		Deliberately not filtered by distance or line of sight on the client. Whether a player CAN see
		the transform is decided by the camera and the geometry, exactly as it would be for any other
		thing happening in the world. A client-side "am I close enough" test would be a second, wrong
		answer to a question the renderer already answers correctly.
	]]
	if payload.Transformed then
		shake()
	end
end)
```

**`AudioController` — the stinger, carrying `TransformAudioRange` (40 studs).** A `Sound` parented to
the transforming character's `Head` with `RollOffMaxDistance = Config.Monster.TransformAudioRange`.

> **NOTE** the stinger has **no `SoundId`** in this chunk and that is deliberate rather than unfinished.
> There is no audio in this project until C29, which loads the `asset-pipeline` skill first. Wiring the
> emitter now — correct position, correct rolloff, right moment — means C29 is a `SoundId` and a mix, not
> an integration. It is also honest: a silent transform in the C04 playtest is expected, not a bug.
>
> **IMPORTANT** — `check:secrecy` flags any `AswangUserId` reference **anywhere under `src/client/`**. No
> client file in this phase may name it, including in a comment about not naming it — comments are
> stripped before matching, so a comment is safe, but the rule is easier to keep by not writing it.

#### Step 7.4: C04 phase gate — the mechanical half

**File:** — (verification only)
**Verify:** `npm run verify`

| C04 Done, verbatim | What a green tree here actually proves |
| --- | --- |
| any player with line of sight sees the transform | **nothing.** `FireAllClients` is called; that it renders on another machine is Step 7.5 |
| the Aswang cannot stay transformed past 8s | the forced-revert timer exists and typechecks; that it fires is Step 7.5 |

Both halves of C04's Done are **runtime claims about two machines**, and no command in this repository
can reach them. That is not a weakness in the plan — it is the reason C04's own Verify line names the
playtester and a screenshot instead of a command.

#### Step 7.5: The two-client artifact — the half no command can produce

**File:** `.claude/plans/feature-c02-c04-anticheat-roles-transform-plan/artifacts/`

**This step deliberately carries no `Verify:` line.** `verify-plan.mjs` will report it `unverifiable` and
`next-phase.mjs` will mark Phase 7 `needs-human`. That is the correct outcome, not a gap: the entire claim
of C04 is that the transform is **publicly visible**, and a screenshot taken from the transforming
player's own camera proves nothing about that. The artifact is a screenshot from the **other** client's
camera. One client, however green the tree, cannot produce it.

**What the playtester must set up**, and why each part is not optional:

1. **Two clients in Studio.** `Config.Debug.SoloTesting = true` gets a round started below `MinPlayers`,
   but it cannot manufacture a second camera. Two clients is the requirement, not a preference.
2. **Find out which one is the Aswang without leaking it into the evidence.** The role is server-only, so
   the honest route is to read it from the server — a server-side `execute_luau` against
   `RoleService.GetRole`, or the `RoleService` draw log with `Config.Debug.VerboseLogging` on. Do **not**
   add a temporary broadcast to find out; a debugging leak is still a leak, and it is the kind that gets
   left in.
3. **Press `T` on the Aswang's client.** The bind from Step 7.3.
4. **Screenshot from the OTHER client's camera, during the 1.2s windup and again while transformed.**
   The windup shot is the one that matters: §4.3's whole design is that the *becoming* is visible.
5. **Then wait 8 seconds without pressing anything** and screenshot the same camera showing a reverted,
   ordinary avatar. That is the second half of C04's Done and it is the half most likely to be skipped.

**Three failures to look for specifically**, because each one passes every automated check in this repo:

- The other client sees **nothing** — a `MonsterTransformed` listener that never connected, or a
  broadcast fired before the character existed.
- The other client sees the transform but it **never reverts** — the self-cancellation trap in
  `MonsterService.Revert` (Step 7.1), which only manifests on the forced-revert path, i.e. only when the
  Aswang failed to get a kill. That is the common case in real play and the rare one in a hurried test.
- The Aswang **stays fast after reverting** — `BaseWalkSpeed` not restored. A permanent, silent,
  client-readable marker of the Aswang, and exactly the "derived hint" §6.2 warns about.

Save the screenshots into this plan's `artifacts/` directory and cite them by filename in
`verification.md`. `goal-check.mjs` requires a cited file that actually exists there before it reports
DONE, and that check is the strongest of the four it makes — it is still only a proxy, because it proves
a screenshot exists and was cited, never that it shows the right thing. Somebody has to look.

#### Phase 7 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the highest-risk item in this phase is a **revert that does not fully revert**.
  A leftover FX folder, an unrestored walkspeed or a scale that stayed applied is a permanent
  client-readable marker on the Aswang, and none of it contains the word "role" so nothing will flag it.
  Check `restoreLook`, `applyScale(humanoid, 1)` and `BaseWalkSpeed` on **every** revert path: the
  forced timer, the phase change, and a disconnect.
- **Remote direction** — `RequestTransform` fired from the client with `:FireServer`;
  `MonsterTransformed` listened to on the client with `.OnClientEvent`. Both halves are new in this
  phase and `check:remotes` reads both.
- **Rate limiting** — unchanged from Phase 6; the client-side gate in `InputController` is UX, and the
  server does not trust it.
- **Magic numbers** — `Enum.KeyCode.T` is not a number. Watch the shake/vignette magnitudes in
  `CameraFXController`: those are the literals most likely to be typed inline, and `src/client/` is
  governed.
- **Phase ownership** — `MonsterService` subscribes via `RoundService.PhaseChanged.Event`. It never sets
  the phase, and the `.Event` (BindableEvent) form is easy to get wrong in a way that fails silently
  inside a pcall'd `Start()`.
- **Player leaving mid-round** — §6.4's five cases, and which apply here:
  - **the Aswang leaves mid-round** — `RoundService` already aborts the round; the phase leaves ACTIVE,
    the subscription force-reverts, and `PlayerRemoving` cancels the pending thread. A player who leaves
    *while transformed* leaves a character that Roblox destroys, so the FX go with it.
  - **a player joins mid-round** — SPECTATOR, refused by the allowlist. The body half is unresolved; see
    Step 7.2 and Follow Ups.
  - **count drops below minimum** — the round finishes, unchanged by this plan.
  - the remaining two (timer-end win, `BindToClose`) are untouched.
- **Strict Luau** — `coroutine.running()` returns a thread and compares against `monster.RevertThread`,
  which is typed `thread?`. `task.delay` returns a thread. The `if ... then ... else nil` expression for
  `humanoid` infers `Humanoid?` and every use is nil-guarded.
- **Mobile budget** — two `PointLight`s plus one `ParticleEmitter` per transformed Aswang, against
  `MaxVisibleLights = 8`, plus whatever camera shake `CameraFXController` runs. Shake is per-frame work
  on the client for the duration of the effect — keep it short and bounded, and confirm on a phone at
  C27 rather than assuming Studio's framerate means anything.
- **Scope** — no custom mesh, no combat, no second monster.

**Issues identified:**

- **`Humanoid.Died` is not handled.** A transformed Aswang who dies keeps its `MonsterState` until the
  phase changes. There is no way to die yet — C05 builds the kill — so this is correct scope for C04 and
  a required input to C05. Recorded rather than pre-built.
- **A respawn during the transform orphans the FX on the old character.** `BeginTransform` re-reads
  `player.Character` after the windup, so the *mechanical* half is safe; the FX folder is parented to the
  character Roblox is about to destroy, so it goes with it. Worth one look during the two-client test.
- **The spectator BODY is still uncontained**, premise unverified. It must be resolved before C05, not
  before C04: an uncounted spectator becomes an *unkillable* one the moment a kill exists.
- **Phase 7 will report `needs-human`** because Step 7.5 carries no check. That is the designed outcome.
  A run that halts here with `needs-human` has not failed — it has correctly asked for the one thing a
  terminal cannot provide.

## 3. Related Files

Every file below was read while planning. Each has an annotated review in `references/` covering only the
lines this plan depends on.

**Created**

| File | Phase | Why |
| --- | --- | --- |
| `src/shared/pure/TokenBucket.luau` | 2 | the rate limiter's arithmetic, and its hostile `now` |
| `src/server/pure/RoleDraw.luau` | 4 | the secret. **Server-side pure** — see §1.1 |
| `src/shared/pure/TransformRules.luau` | 6 | §4.3's transform preconditions |
| `tests/anti-cheat-budgets.test.luau` | 1 | every UP remote has a budget, both directions |
| `tests/token-bucket.test.luau` | 2 | C02's own Verify line |
| `tests/role-draw.test.luau` | 4 | C03's own Verify line — 10,000 seeded draws |
| `tests/transform-rules.test.luau` | 6, 7 | six verdicts, four player states, the cooldown boundary |

**Modified**

| File | Phase | Change |
| --- | --- | --- |
| `src/shared/Config.luau` | 1, 6 | `AntiCheat` section; `Roles` weights; `Monster` FX block |
| `src/shared/Types.luau` | 1 | four new types, each a boundary contract |
| `src/shared/Remotes.luau` | 1 | comments only; no remote added |
| `src/server/Services/AntiCheatService.luau` | 3 | stub → the rate-limit core |
| `src/server/Services/RoleService.luau` | 5 | stub → the draw, the store, the history |
| `src/server/Services/MonsterService.luau` | 6, 7 | stub → transform, broadcast, forced revert |
| `src/server/Services/RoundService.luau` | 5 | `enterStarting` draws roles; lobby clears them |
| `src/client/Controllers/UIController.luau` | 5 | the 3-second private intro; holds this client's own role |
| `src/client/Controllers/InputController.luau` | 7 | `T` → `RequestTransform`, gated on own role |
| `src/client/Controllers/CameraFXController.luau` | 7 | witness reaction to `MonsterTransformed` |
| `src/client/Controllers/AudioController.luau` | 7 | the stinger's rig, `SoundId` at C29 |
| `tests/config.test.luau` | 1 | six new balance invariants (13 → 19) |
| `tests/README.md` | 4 | the two pure locations and the rule between them |

**Read, unchanged** — `src/server/init.server.luau` (`SERVICE_ORDER` already correct),
`src/client/init.client.luau`, `src/shared/Enums.luau`, `src/shared/pure/RoundTransitions.luau`,
`tests/round-transitions.test.luau`, `default.project.json`, `package.json`,
`.claude/scripts/check-{ratelimit,config,secrecy,remotes,scope,analyze}.mjs`,
`.claude/scripts/lib/luau-source.mjs`, `.claude/scripts/verify-plan.mjs`,
`.claude/scripts/run-luau-tests.mjs`, `docs/MVP-SPEC.md` §3/§4.2/§4.3/§6.2–6.5/Appendix A,
`docs/BUILD-PLAN.md` C01–C05 + §12, `CLAUDE.md`.

## 4. Follow Ups

### Questions / Clarifications

1. **`Random.new()`'s entropy source.** Roblox documents the no-argument form as arbitrarily seeded. This
   plan does not guess about Roblox APIs, so the question is put here rather than answered: is the
   default seed derivable from anything a client can observe? The `src/server/pure/` placement means a
   weak seed alone is not sufficient to replay the draw — the exploiter would also need the algorithm,
   which no longer replicates. If a stronger source is wanted, `HttpService:GenerateGUID()` hashed into a
   seed is the usual answer, and it needs verifying before it is written.

2. **`require(script.Parent.Parent.pure.RoleDraw)`.** Rojo should nest `Services/` and `pure/` beneath the
   `Server` script that `init.server.luau` becomes, but this is unconfirmed in a running place. First
   thing to check at first sync. **If it does not resolve, the fix is a different lookup, never moving
   the module to `src/shared/`** — that would undo §1.1.

3. **Avatar rig type (R6 vs R15).** Scaling is R15-only and the rig is a place-file setting outside Git.
   The code no-ops safely on R6, which means the Aswang would get colour, eyes, particles and speed but
   no size change — a weaker tell. Confirm during the C04 two-client test and record the answer.

4. **Is the transform cooldown the same as the kill cooldown?** §4.3 names one cooldown and `Config`
   carries one, so this plan uses `KillCooldown` for both. C05 may want them separate — a monster that
   can re-transform before it can kill is a real design option. `TransformRules.Request.Cooldown` is
   named generically so splitting them is a Config change, not a rewrite.

5. **`tests/role-draw.test.luau` asserts `rate < baseline * 0.5`**, which couples the test to the shipped
   weights. At M12 a tuning pass that softens `RecentAswangWeight` will break it. Arguably the test doing
   its job (§4.2 says *heavily*), but the person tuning will read it as a broken test. Decide now whether
   that threshold is an invariant or a starting value.

6. **`CLAUDE.md` and `docs/BUILD-PLAN.md` both state that pure modules live in `src/shared/pure/`.**
   Step 4.4 updates `tests/README.md`; the other two are authority documents and are not edited by this
   plan, per `CLAUDE.md`'s precedence rule. **They are now factually incomplete** and should gain the
   `src/server/pure/` case. `docs/BUILD-PLAN.md` §12's pure-module table lists `pure/RoleDraw.luau` under
   C03 and its own C03 warning block explicitly authorises the server location, so this is a wording gap
   rather than a conflict.

7. **`TaskSelection` (C07) faces the same question and this plan does not pre-decide it.** A
   client-derivable task set is a pacing advantage — an exploiter who knows which 5 of 12 spawn can
   pre-position — not a game-ender. That is a judgement call, and it should be made in C07's plan with
   §1.1's rule in hand: shared by default, server when an input or the output is secret.

8. **The request described "all four" remotes as already declared; there are three.** `RoleAssigned`,
   `RequestTransform` and `MonsterTransformed` exist and are correctly placed. `RequestKill` also exists
   but belongs to C05 and is deliberately left unwired by this plan.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 7 | **Spectator BODY containment is not delivered.** C04's warning asks for no character / observer camera; this plan delivers only the rule (a spectator cannot transform). Premise unverified — nothing in `src/` prevents a spawn, but the place file could already handle it. **Must be resolved before C05**, when an uncounted spectator also becomes unkillable | High | Deferred — verify in Studio first, then a small chunk before C05 |
| 5 | `RoleAssigned` is on `check-secrecy.mjs`'s `REVEAL_ALLOWLIST`, so the scanner skips the call entirely — and Luau silently accepts an **extra** field on an annotated table. A second field added to `RoleAssignedPayload` passes `analyze` and `check:secrecy` both | High | Open — C41 is chartered to add a field allowlist; until then, habit + `exploit-auditor` |
| 1 | The UP-remote name list is duplicated between `Config.AntiCheat.Budgets` and `tests/anti-cheat-budgets.test.luau`, because `Remotes.luau` calls `game:GetService` at module scope and Lune cannot require it. Both directions are pinned inside the test; a remote added to `Remotes.luau` and nowhere else still slips through | Medium | Open — a `check-budgets.mjs` parsing both files is the clean fix, and belongs with C41 rather than C02 |
| 3 | `check:ratelimit` passes **vacuously** until Step 6.3. C02 therefore ships with no runtime evidence for the service half at all — only the Lune test over the pure bucket | Medium | Accepted — inherent to building the limiter before any handler, which is C02's whole point |
| 3 | `Config.AntiCheat.LogOnly = true` means nothing is ever kicked. A quiet console during the C04 playtest is **not** evidence the limiter is running | Medium | Accepted — C41 owns enforcement, per C02 |
| 2 | A rejoining player gets fresh, full buckets: buckets are keyed by UserId and dropped on `PlayerRemoving`. Rejoin-to-reset bypasses a *sustained* limit at the cost of a full reconnect | Low | Accepted — slower than the limit it evades; session-persistent counters belong at C41 if ever |
| 7 | The transform stinger has no `SoundId`. A silent transform in the C04 test is expected | Low | By design — C29 owns audio and loads `asset-pipeline` first |
| 7 | A refused transform gives the player no feedback at all — the button appears to do nothing | Low | Open — acceptable for C04, a real FTUE problem at C18 where the button should be disabled instead |
| 5 | A stale `roles` entry survives a disconnect until the next `ClearRoles()`. Nothing reads it | Low | Accepted — one clearing rule at round boundaries is easier to reason about than two |
| 7 | `Humanoid.Died` does not revert a transformed Aswang. There is no way to die until C05 | Low | Deferred — a required input to C05 |
| 6 | Two `PointLight`s per transformed Aswang against `MaxVisibleLights = 8`, shared with C14's reveal glow and C28's lighting pass | Low | Watch — confirm on a real phone at C27, not in Studio |
