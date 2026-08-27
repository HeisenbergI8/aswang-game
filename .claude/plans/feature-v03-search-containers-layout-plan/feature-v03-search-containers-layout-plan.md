# Plan: V03 — SearchService, containers and the layout seed

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** V03 (`docs/BUILD-PLAN.md` lines 204–225). Deps: V02, which has landed.
- **Description:** Seed ~15 tagged containers with 7 items at `STARTING`, from a server-only draw
  that no client can reproduce; validate a 6-second hold server-side (phase, distance, one searcher
  per container); tell the finder what they found and nobody else anything.
- **Date:** 2026-08-27
- **What the client is told:** Three fields, to **one** player, on `SearchUpdate` — `Verdict`,
  `HoldSeconds`, `Found: ItemType?`. **No container identity appears in any payload, in either
  direction.** The client never names a container when requesting; the server resolves it from that
  player's own character position, exactly as `ItemService`'s pickup does. Nothing new goes on
  `ClientRoundSnapshot`; `YourCarriedItem` stays without a producer (V08 owns it). No attribute, no
  tag, no broadcast.

### 1.1 Preamble — the constraints every phase in this plan is bound by

*(Read alongside Phase 1 via `--with-preamble`, and repeated inside the phases that depend on each
line, because a phase is sliced and read alone.)*

**The four questions this plan was asked, answered up front.**

**Q1 — where the pool comes from, and what happens when the map is short.** `CollectionService`
tag `SearchContainer`, `BasePart` only, keyed by unique `Name`, **sorted** before use because
`GetTagged`'s order is engine-defined and must never become a hidden input to a random draw
(`ItemService.discoverPool` states this rule at `src/server/Services/ItemService.luau:86-88` and this
plan copies it). The verdict comes from the **existing** `server/pure/SearchPool.evaluate(names,
required, expected)` — it is generic over three numbers and names no mechanic, so V03 consumes it
rather than growing a second copy. `required` is the item total (4 + 2 + 1 = 7, summed from
`Config.Items`, never typed as a literal); `expected` is `Config.Search.ContainerCount`.

The verdict does **not** gate the seed except at `EMPTY`:

| Verdict | What SearchService does |
| --- | --- |
| `EMPTY` | Warn unconditionally. `layout = nil`. Every `RequestSearch` answers `SEARCH_NO_CONTAINER`. **The round still runs** — SearchService must never block a phase transition, because `RoundService` owns the phase (spec §6.4) |
| `SHORT` | **Seed anyway, into what exists**, and warn. A greybox barrio with 8 containers must still be playable; refusing to seed makes the game unwinnable in a way that looks like a bug rather than a map defect. `ContainerLayout.draw` places `math.min(#queue, containerCount)` items in a stated priority order and reports `Placed` |
| `DUPLICATE_ID` | `evaluate` has already dropped the duplicates from `Unique`. Warn naming them, seed over `Unique` |
| `OVERSIZED` | Seed over all of them, warn that the map and `Config.Search.ContainerCount` disagree |
| `OK` | Seed. Log the **count** under `Config.Debug.VerboseLogging` and never the contents |

**Q2 — what crosses the wire, and whether it can be differenced.** Covered in full at Step 2.1 and
re-checked in Phase 3's issues block. The short form: no payload carries a container identity, so
there is nothing to difference. What two colluding clients can pool is what they each found by
standing at a container and opening it — the intended information, and §4.5 gives them a phrase for
it.

**Q3 — the lock, and what releases it.** `holds: { [number]: Hold }` keyed by UserId is the single
authority; `occupied: { [number]: number }` keyed by container index is a **reverse index**
maintained by exactly two functions, `beginHold` and `releaseHold`. Six release paths, all routed
through `releaseHold(userId)`: the hold completes, the player cancels, the player leaves
`Config.Search.RangeStuds`, the player stops being `ALIVE` (death or character removal), the player
leaves the server, and the phase leaves `ACTIVE`. Enumerated as diffs in Step 3.2.

**Q4 — Config.** Already present from V02: `Search.ContainerCount = 15`, `Search.SearchTime = 6`,
`Items.SaltSpawnCount = 4`, `Items.GarlicSpawnCount = 2`, `Items.BuntotPagiSpawnCount = 1`. **To
add:** `Search.RangeStuds` (Step 1.3) and two `AntiCheat.Budgets` entries (Step 2.3).
`Search.NoiseRadius` exists and V03 **does not read it** — noise is V04.

**The three rules this chunk exists to honour, restated so no phase has to look them up.**

1. **`src/server/pure/`, not `src/shared/pure/`.** `default.project.json` maps `src/shared` wholesale
   into `ReplicatedStorage`, so a LocalScript can `require()` **and call** anything there. The
   algorithm being public is fine; a reproducible draw is not. `src/server` maps to
   `ServerScriptService`, which does not replicate. `RoleDraw.luau` and `SearchPool.luau` are already
   there for this reason.
2. **`Random.new()` with no argument.** `Random.new(roundNumber)` and `Random.new(os.time())` are
   fatal — `os.time()` is client-observable to the second, and either turns the draw into something a
   client replays before the round starts, with no remote to intercept and nothing for
   `check:secrecy` to see (spec §6.2, §4.4).
3. **The Aswang searches on identical rules.** No branch in `SearchService` may read
   `RoundService.GetAswangUserId()`, and none does. Spec §4.4 and Amendment A2's generalisation: any
   activity the monster cannot perform sincerely becomes an oracle that identifies it.

**The literal-union trap, which this module walks straight into.**
`.claude/lessons/pure-module-unions-widen-in-lists.md`: a literal union survives `require` as a
**scalar** and does **not** survive it inside a **list** — the element arrives as a union of plain
`string`s, `::` cannot narrow it back, and the analyzer reports at the *call site*, naming the wrong
file. `ContainerLayout` returns a container of item ids and would hit this exactly. **So it returns
plain `string` and narrows with a FUNCTION** (`ContainerLayout.itemAt`), which is the lesson's stated
remedy: a literal in a `return`, checked against an annotated return type, is narrowing the analyzer
performs — and it beats a cast, since an unknown id returns `nil` to drop with a `warn` where a cast
would wave it into a client payload.

## 2. Comprehensive Plan by Phases

### Phase 1: The draw, its proof, and the two numbers it needs

Leaves the game byte-for-byte unchanged at runtime — nothing requires the new module yet. Ends green
on `npm run verify:fast`.

#### Step 1.1: Write `ContainerLayout` — the server-only layout draw

**File:** `src/server/pure/ContainerLayout.luau`
**Verify:** `npm run analyze`

A new pure module `(containerCount, counts, nextInt) -> Layout`, matching `RoleDraw.luau`'s shape and
header discipline: no `require(script.Parent.X)`, no Roblox datatypes, no tunable numbers (`src/server/`
is governed by `check:config`, so the counts arrive as a parameter), injected randomness, degenerate
inputs answered rather than thrown. `Contents` is `{ [number]: string }` — deliberately plain
`string` — and `ContainerLayout.itemAt` is the narrowing function.

```diff
+--!strict
+--[[
+	ContainerLayout — which container holds which item, as a pure function. (V03, §4.4)
+
+		(containerCount, counts, nextInt) -> Layout
+
+	WHY THIS FILE IS UNDER src/server/pure/ AND NOT src/shared/pure/
+	----------------------------------------------------------------
+	`default.project.json` maps `src/shared` wholesale into ReplicatedStorage, so every module there is
+	require-able AND CALLABLE by any client. That is harmless for logic — logic is never secret — and
+	it is the whole game for this one.
+
+	Algorithm + inputs + seed = this round's layout. A client that can call this function AND supply
+	its inputs knows where the buntot pagi is before anyone has opened anything: no remote to
+	intercept, nothing on the wire, and nothing for `check:secrecy` to see. §6.2 names the layout seed
+	as server-only state in the same breath as the Aswang's identity, and for the same reason.
+
+	`src/server` maps to ServerScriptService, which does not replicate. Two rules are still enforced at
+	the CALL SITE, because defence in depth is the point and the next author may not read this comment:
+
+	  · The RNG is INJECTED, never created here, and SearchService seeds it with `Random.new()` — no
+	    argument. `Random.new(roundNumber)` and `Random.new(os.time())` are both client-observable and
+	    both fatal. §4.4 says so in one sentence and it is the sentence this module exists to obey.
+	  · The LAYOUT IS NEVER LOGGED, not even under Config.Debug.VerboseLogging. In a Studio solo test
+	    the server and client share one output window, so a print of where the buntot pagi is arrives
+	    in front of the person playing.
+
+	Lune resolves test requires by FILE PATH and knows nothing about Rojo, so this location costs no
+	testability — `tests/container-layout.test.luau` requires "../src/server/pure/ContainerLayout" and
+	runs identically. `RoleDraw` and `SearchPool` are here on exactly this argument.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes, same rule as every other pure module.
+
+	WHY `Contents` IS `{ [number]: string }` AND NOT `{ [number]: Item }`
+	---------------------------------------------------------------------
+	Because a literal union survives `require` as a SCALAR and does not survive it inside a container.
+	The element arrives at the call site as a union of plain `string`s, `::` fails with "none of the
+	union options are compatible" because Luau distributes the cast and widens every option, and the
+	analyzer reports it in SearchService — naming the wrong file, which is what cost C21 eight failed
+	fixes. See `.claude/lessons/pure-module-unions-widen-in-lists.md`.
+
+	So the container holds plain strings and `itemAt` below does the narrowing, which is the lesson's
+	stated remedy: a literal in a `return` checked against an annotated return type is narrowing the
+	analyzer performs. It also beats a cast on behaviour — an unknown id returns `nil` for the caller
+	to drop with a `warn`, where a cast would wave it into a client payload.
+
+	NOTE `check-config.mjs` governs `src/server/`, so this file may not contain a tunable number. That
+	is why `counts` is a parameter. It is the right shape anyway: 4/2/1 are §4.4 balance knobs and V16
+	is expected to move them.
+]]
+
+-- Structurally identical to `Types.ItemType`; Luau unions are structural, so the two are the same
+-- type and pass to each other without a cast. Re-declared rather than required, because a pure module
+-- that reaches for `Types` stops being runnable from a terminal and the whole point is lost.
+export type Item = "SALT" | "BAWANG" | "BUNTOT_PAGI"
+
+-- How many of each item the round places. Read from `Config.Items.*SpawnCount` by the caller.
+export type Counts = {
+	Salt: number,
+	Bawang: number,
+	BuntotPagi: number,
+}
+
+export type Layout = {
+	ContainerCount: number,
+	-- Container index -> item id. ABSENT means empty, and most of them are absent: seven items across
+	-- fifteen containers is §4.4's whole risk economy — "you will open empty ones, and that is the
+	-- point". PLAIN `string` deliberately; read it through `itemAt`.
+	Contents: { [number]: string },
+	-- How many items actually landed. Equals the item total on a healthy map and is LOWER on a SHORT
+	-- one, which is the number the caller warns on.
+	Placed: number,
+}
+
+local ContainerLayout = {}
+
+--[[
+	PLACEMENT PRIORITY, WHICH ONLY MATTERS ON A BROKEN MAP — and matters completely there.
+
+	On a healthy pool every item is placed and the order is invisible. On a SHORT pool (fewer distinct
+	containers than items) something has to be dropped, and dropping the wrong thing makes the round
+	unwinnable rather than merely thin:
+
+	  1. BUNTOT_PAGI — the only thing in the game that kills the Aswang (§4.6). Drop it and the
+	     survivors' second win condition does not exist at all.
+	  2. SALT       — the only counterplay, and the only thing that weakens the Aswang toward the
+	     state the buntot pagi requires. Drop it and the buntot pagi can never be used.
+	  3. BAWANG     — buys time, never safety (§4.6, invariant 4). The one that can be missing while
+	     the round still resolves the way it is meant to.
+
+	This does make a SHORT map's contents partly predictable. That is acceptable and not worth
+	defending against: a SHORT map is a fault state the caller warns about loudly, and an exploiter who
+	knows the layout of a map that cannot be played has won nothing.
+]]
+local function buildQueue(counts: Counts): { string }
+	local queue: { string } = {}
+
+	for _ = 1, counts.BuntotPagi do
+		table.insert(queue, "BUNTOT_PAGI")
+	end
+
+	for _ = 1, counts.Salt do
+		table.insert(queue, "SALT")
+	end
+
+	for _ = 1, counts.Bawang do
+		table.insert(queue, "BAWANG")
+	end
+
+	return queue
+end
+
+--[[
+	A PARTIAL FISHER-YATES, which is the whole algorithm and is worth naming rather than reading off.
+
+	`order` starts as 1..containerCount. For each slot we swap in one uniformly-chosen element from the
+	untouched tail, so after `placeable` iterations the first `placeable` entries are a uniform random
+	SUBSET in uniform random ORDER. Two properties fall out for free, and they are exactly the two the
+	test asserts:
+
+	  · no container can be double-seeded — a swapped-out index moves into the tail and is never
+	    revisited, so the indices written are distinct by construction rather than by a check
+	  · every container is equally likely to receive any particular item, including the buntot pagi
+
+	The alternative — draw a random index and retry on collision — is the same distribution with an
+	unbounded loop, and an unbounded loop inside `enterStarting` is a round that hangs in STARTING.
+
+	`nextInt(lo, hi)` returns an integer in [lo, hi] INCLUSIVE. The signature matches
+	`Random:NextInteger` so the caller passes a one-line adapter and nothing has to be remembered.
+
+	DEGENERATE INPUTS RETURN A SENSIBLE LAYOUT rather than erroring, for RoleDraw's reason: a live
+	server that reached one of these has a bigger problem than the draw, and erroring here would leave
+	the round in STARTING with no layout and no log.
+]]
+function ContainerLayout.draw(
+	containerCount: number,
+	counts: Counts,
+	nextInt: (number, number) -> number
+): Layout
+	local queue = buildQueue(counts)
+	local placeable = math.min(#queue, math.max(containerCount, 0))
+	local contents: { [number]: string } = {}
+	local order: { number } = {}
+
+	for index = 1, containerCount do
+		order[index] = index
+	end
+
+	for slot = 1, placeable do
+		local pick = nextInt(slot, containerCount)
+
+		order[slot], order[pick] = order[pick], order[slot]
+		contents[order[slot]] = queue[slot]
+	end
+
+	return {
+		ContainerCount = containerCount,
+		Contents = contents,
+		Placed = placeable,
+	}
+end
+
+--[[
+	THE NARROWING FUNCTION, and it is the reason `Contents` holds plain strings.
+
+	An unrecognised id returns nil, which the caller drops with a warn. A cast would have waved it into
+	a client payload instead — see the header, and the lesson it cites.
+]]
+function ContainerLayout.itemAt(layout: Layout, containerIndex: number): Item?
+	local id = layout.Contents[containerIndex]
+
+	if id == "SALT" then
+		return "SALT"
+	elseif id == "BAWANG" then
+		return "BAWANG"
+	elseif id == "BUNTOT_PAGI" then
+		return "BUNTOT_PAGI"
+	end
+
+	return nil
+end
+
+return ContainerLayout
```

#### Step 1.2: Write the 10,000-draw suite

**File:** `tests/container-layout.test.luau`
**Verify:** `lune run tests/container-layout.test.luau`

The chunk's stated Verify line, made concrete: exactness on every one of 10,000 draws, plus **two**
distribution bands with stated thresholds and a hermetic seed. Also the `SHORT`-pool boundary and the
priority order, because that path is the one a greybox map actually takes.

**The degeneracy thresholds, derived rather than chosen.** "Not degenerate" is not a check. Over
`DRAWS = 10000` draws of `ITEMS = 7` items into `CONTAINERS = 15`, each container's occupancy count is
Binomial(10000, 7/15):

| Band | Expected | σ | Band width | In σ | Two-sided p, per container |
| --- | --- | --- | --- | --- | --- |
| **any item** in container *i* | 10000 × 7/15 = **4666.7** | √(10000 × 7/15 × 8/15) = **49.9** | ±5% = ±233 | ±4.68σ | ≈ 3 × 10⁻⁶ |
| **buntot pagi** in container *i* | 10000 × 1/15 = **666.7** | √(10000 × 1/15 × 14/15) = **24.9** | ±15% = ±100 | ±4.01σ | ≈ 6 × 10⁻⁵ |

**Why two bands and not one.** The aggregate band catches every *marginal* degeneracy — an off-by-one
that never picks container 1 or 15, a shuffle biased toward low indices, items only ever landing in
the first seven slots. It cannot catch a *correlation*: if the buntot pagi always landed in the same
container as a salt, the aggregate counts would stay flat while the one item that decides the round
became predictable. The second band is aimed at exactly that, and it is aimed at the buntot pagi
because there is one of it and §4.6 makes it the only thing that kills.

**Why a fixed seed and a hand-rolled generator.** The suite injects a deterministic **xorshift32**
`nextInt` rather than `math.random`, so the pass/fail is a property of the algorithm and not of the
Lune build's RNG. An unseeded band that fails one run in twenty thousand is a flake that costs more
attention than it catches; a hermetic one makes the band a genuine regression check, and the widths
above are then the honest tolerance for this seed's own noise rather than a guess.

```diff
+--!strict
+--[[
+	tests/container-layout.test.luau
+
+	V03's stated Verify line: 10,000 draws asserting every item placed exactly once, no container
+	double-seeded, and a distribution across the pool that is not degenerate.
+
+	THE LAST THIRD IS THE PART WORTH ARGUING ABOUT, because "not degenerate" is not a check. Two bands
+	are asserted and they catch different failures:
+
+	  · OCCUPANCY, any item, per container. Expected 10000 x 7/15 = 4666.7, sd 49.9. The band is +-5%
+	    (+-233), which is +-4.68 sd. This catches every MARGINAL degeneracy: an off-by-one that never
+	    picks container 1 or 15, a bias toward low indices, items only ever landing in the first seven.
+	  · THE BUNTOT PAGI, per container. Expected 10000/15 = 666.7, sd 24.9, band +-15% (+-100), which is
+	    +-4.01 sd. This catches a CORRELATION the first band cannot see: if the one item that decides
+	    the round always landed beside a salt, the aggregate counts would stay flat while the layout
+	    became predictable. There is one buntot pagi and §4.6 makes it the only thing that kills, so it
+	    is the item worth watching on its own.
+
+	THE GENERATOR IS HAND-ROLLED AND SEEDED, and that is deliberate rather than lazy. A band asserted
+	over `math.random` is a band whose pass depends on the Lune build, and one that fails a run in
+	twenty thousand is a flake that costs more attention than it catches. xorshift32 makes this
+	hermetic, so a failure means the ALGORITHM changed — which is the only thing this file is for.
+]]
+
+local ContainerLayout = require("../src/server/pure/ContainerLayout")
+
+local DRAWS = 10000
+local CONTAINERS = 15
+local COUNTS = { Salt = 4, Bawang = 2, BuntotPagi = 1 }
+local ITEMS = COUNTS.Salt + COUNTS.Bawang + COUNTS.BuntotPagi
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
+-- xorshift32. Period 2^32-1, and the modulo bias over a range of 15 is far below anything the bands
+-- below could resolve.
+local function generator(seed: number): (number, number) -> number
+	local state = seed
+
+	return function(lo: number, hi: number): number
+		state = bit32.bxor(state, bit32.lshift(state, 13))
+		state = bit32.bxor(state, bit32.rshift(state, 17))
+		state = bit32.bxor(state, bit32.lshift(state, 5))
+
+		return lo + state % (hi - lo + 1)
+	end
+end
+
+local nextInt = generator(0x2A5C1D07)
+
+--------------------------------------------------------------------------------
+-- Exactness, on every single draw. One counter per failure MODE rather than a
+-- check() per draw, so a broken algorithm reports once instead of 10,000 times.
+--------------------------------------------------------------------------------
+
+local occupancy: { number } = {}
+local buntotPagi: { number } = {}
+
+for index = 1, CONTAINERS do
+	occupancy[index] = 0
+	buntotPagi[index] = 0
+end
+
+local wrongPlaced = 0
+local wrongMultiset = 0
+local outOfRange = 0
+
+for _ = 1, DRAWS do
+	local layout = ContainerLayout.draw(CONTAINERS, COUNTS, nextInt)
+	local tally = { SALT = 0, BAWANG = 0, BUNTOT_PAGI = 0 }
+	local occupied = 0
+
+	for containerIndex, id in layout.Contents do
+		occupied += 1
+
+		if containerIndex < 1 or containerIndex > CONTAINERS or containerIndex % 1 ~= 0 then
+			outOfRange += 1
+			continue
+		end
+
+		occupancy[containerIndex] += 1
+		tally[id] = (tally[id] or 0) + 1
+
+		if id == "BUNTOT_PAGI" then
+			buntotPagi[containerIndex] += 1
+		end
+	end
+
+	-- `Contents` is keyed BY container index, so a count of 7 distinct keys IS "no container was
+	-- double-seeded". A second write to one index would leave 6 keys, not 7.
+	if occupied ~= ITEMS or layout.Placed ~= ITEMS then
+		wrongPlaced += 1
+	end
+
+	if
+		tally.SALT ~= COUNTS.Salt
+		or tally.BAWANG ~= COUNTS.Bawang
+		or tally.BUNTOT_PAGI ~= COUNTS.BuntotPagi
+	then
+		wrongMultiset += 1
+	end
+end
+
+check(
+	`all {DRAWS} draws fill exactly {ITEMS} distinct containers — no container double-seeded`,
+	wrongPlaced == 0,
+	`{wrongPlaced} draw(s) did not`
+)
+
+check(
+	"every item is placed exactly once, every draw",
+	wrongMultiset == 0,
+	`{wrongMultiset} draw(s) had the wrong item multiset`
+)
+
+check("no container index outside 1..CONTAINERS was ever written", outOfRange == 0, `{outOfRange} did`)
+
+--------------------------------------------------------------------------------
+-- Distribution. The thresholds and their derivation are in the header.
+--------------------------------------------------------------------------------
+
+local expectedOccupancy = DRAWS * ITEMS / CONTAINERS
+local occupancyBand = expectedOccupancy * 0.05
+local expectedPagi = DRAWS / CONTAINERS
+local pagiBand = expectedPagi * 0.15
+
+local occupancyStrays: { string } = {}
+local pagiStrays: { string } = {}
+
+for index = 1, CONTAINERS do
+	if math.abs(occupancy[index] - expectedOccupancy) > occupancyBand then
+		table.insert(occupancyStrays, `#{index}={occupancy[index]}`)
+	end
+
+	if math.abs(buntotPagi[index] - expectedPagi) > pagiBand then
+		table.insert(pagiStrays, `#{index}={buntotPagi[index]}`)
+	end
+end
+
+check(
+	`every container is hit {math.floor(expectedOccupancy)} +- 5% times across {DRAWS} draws`,
+	#occupancyStrays == 0,
+	`outside the band: {table.concat(occupancyStrays, ", ")}`
+)
+
+check(
+	`the buntot pagi lands in every container {math.floor(expectedPagi)} +- 15% times`,
+	#pagiStrays == 0,
+	`outside the band: {table.concat(pagiStrays, ", ")}`
+)
+
+--------------------------------------------------------------------------------
+-- The SHORT map. A greybox barrio with three containers must still be playable,
+-- and WHICH three items survive is the difference between thin and unwinnable.
+--------------------------------------------------------------------------------
+
+local short = ContainerLayout.draw(3, COUNTS, nextInt)
+local shortTally = { SALT = 0, BAWANG = 0, BUNTOT_PAGI = 0 }
+
+for _, id in short.Contents do
+	shortTally[id] += 1
+end
+
+check("a 3-container pool places 3 items and no more", short.Placed == 3, `Placed={short.Placed}`)
+
+check(
+	"the buntot pagi survives a SHORT pool — it is the only thing that kills",
+	shortTally.BUNTOT_PAGI == 1,
+	`BUNTOT_PAGI={shortTally.BUNTOT_PAGI}`
+)
+
+check(
+	"salt takes the remaining slots ahead of bawang — the weaken step gates the kill",
+	shortTally.SALT == 2 and shortTally.BAWANG == 0,
+	`SALT={shortTally.SALT}, BAWANG={shortTally.BAWANG}`
+)
+
+-- A map with no containers at all. `SearchService` never calls this path — it refuses at the EMPTY
+-- verdict — but the module must not throw if a future caller forgets.
+local none = ContainerLayout.draw(0, COUNTS, nextInt)
+
+check("an empty pool places nothing and does not error", none.Placed == 0)
+check("an empty pool has no contents", next(none.Contents) == nil)
+
+--------------------------------------------------------------------------------
+-- itemAt: the narrowing function, which is the reason Contents holds strings.
+--------------------------------------------------------------------------------
+
+local narrow = ContainerLayout.draw(CONTAINERS, COUNTS, nextInt)
+local narrowed = 0
+
+for containerIndex in narrow.Contents do
+	if ContainerLayout.itemAt(narrow, containerIndex) ~= nil then
+		narrowed += 1
+	end
+end
+
+check("itemAt narrows every placed id", narrowed == ITEMS, `narrowed {narrowed} of {ITEMS}`)
+check("itemAt returns nil for an empty container", ContainerLayout.itemAt(none, 1) == nil)
+
+-- An id the module does not recognise is DROPPED, not cast. This is the behaviour a `::` would have
+-- destroyed, and the reason the lesson prescribes a function.
+local forged = { ContainerCount = 1, Contents = { [1] = "SPAM" }, Placed = 1 }
+
+check("itemAt drops an unrecognised id rather than passing it on", ContainerLayout.itemAt(forged, 1) == nil)
+
+if failures > 0 then
+	error(`{failures} container-layout failure(s)`, 0)
+end
+
+print(
+	`  PASS  container-layout: {checked} assertions — exactness over {DRAWS} draws, two distribution `
+		.. `bands, the SHORT priority order, and itemAt`
+)
```

**NOTE on the foot** — `error(msg, 0)` then a `PASS` line, copied verbatim from
`tests/search-pool.test.luau:1265` and `tests/role-draw.test.luau`. It is what makes
`lune run tests/container-layout.test.luau` a check that can fail rather than a script that prints,
and `npm run test:unit` discovers the file by glob, so there is nothing to register.

#### Step 1.3: Add `Search.RangeStuds`, and pin the two relationships it enters

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/config.test.luau`

Adds one key to `Config.Search`, and adds two assertions to `tests/config.test.luau` — the pool must
comfortably exceed the items placed, and a search must be long enough to be punished for. §6.5's
invariants are about relationships nothing else reports; these are two more of them.

**Second file in this step:** `tests/config.test.luau`. The Verify line runs it, so the two land
together or the step fails — which is the point: a Config key with no relationship pinned is the exact
shape §6.5 warns about.

```diff
 	Search = {
 		-- How many searchable containers the barrio holds. It must comfortably exceed the total items
 		-- placed (Items.*SpawnCount sums to 7) or every container is a hit and searching stops being a
 		-- gamble. V03 owns the layout draw and the map-side tag contract.
 		ContainerCount = 15,
 		-- Seconds to search one container, uninterrupted. The exposure window: long enough that being
 		-- caught mid-search is a real risk, short enough that a survivor will still take the risk.
 		SearchTime = 6,
+
+		--[[
+			V03. How close you must be to a `SearchContainer` to start a search — AND STAY, for the
+			whole six seconds. Leaving this radius releases the hold, which is the rule that makes
+			§4.4's exposure real: a search you could walk away from and come back to would cost
+			nothing, and the cost is the mechanic.
+
+			LARGER THAN `Salt.PickupRangeStuds` (6) ON PURPOSE, and the difference is the interaction.
+			Salt is picked up by walking over it, so its radius is a footprint. A container is opened
+			by standing at it, so its radius is an arm's length plus the slack a phone player needs to
+			hold still for six seconds — §5 puts ~60% of players on one, and a radius tuned on a mouse
+			is a radius that cancels their search every time the thumbstick drifts.
+
+			IT IS ALSO JUST OUTSIDE `Monster.KillRange` (8) AT THIS VALUE, which is worth seeing rather
+			than preserving blindly: a searcher is standing roughly where the Aswang can reach them. If
+			a later tune raises this well above KillRange, searching becomes something you do from
+			outside kill range and §4.4's trade quietly evaporates. Re-open at V16.
+		]]
+		RangeStuds = 10,
+
 		-- Studs the noise carries. DELIBERATELY LARGER THAN ANY OTHER RANGE IN THIS FILE — the point is
 		-- that searching summons the monster, not that it might. Compare Tracker.EarlyRadius = 40: a
 		-- searching survivor is louder than the tracker is sharp, for the whole first half of the night.
 		NoiseRadius = 60,
 	},
```

And in `tests/config.test.luau`, beside the existing §6.5 relationships:

```diff
+--[[
+	V03, §4.4. THE POOL MUST COMFORTABLY EXCEED THE ITEMS IN IT.
+
+	"Seven items across fifteen containers. You will open empty ones, and that is the point." If the
+	item counts climb toward the container count, every container becomes a hit, the six seconds stop
+	being a gamble and searching degenerates into a walk — which is precisely what §4.4 says the
+	randomisation exists to prevent.
+
+	`>= 2 x` is a TIGHT pin: 15 >= 14 passes with one container to spare. That tightness is deliberate
+	rather than accidental. A looser `>= total + 1` would pass at 8 containers holding 7 items, where
+	the property this protects has already been destroyed — so the loose version could never fire and
+	would not be worth the line. If a V16 tune raises an item count and this fails, the fix is to raise
+	ContainerCount and tag more parts in the map, not to widen the pin.
+]]
+local totalItems = Config.Items.SaltSpawnCount
+	+ Config.Items.GarlicSpawnCount
+	+ Config.Items.BuntotPagiSpawnCount
+
+check(
+	"searching is still a gamble — the container pool is at least twice the items placed in it",
+	Config.Search.ContainerCount >= totalItems * 2,
+	`ContainerCount={Config.Search.ContainerCount}, items={totalItems}`
+)
+
+--[[
+	V03, §4.4. A SEARCH MUST OUTLAST THE ASWANG'S WHOLE APPROACH OVERHEAD.
+
+	§4.4: the six seconds "are why the layout being random costs something". The cost is only real if
+	an Aswang who notices a search starting can transform, close, and still arrive — so the hold must
+	exceed the fixed price of a transform and the revert that follows it. Below that, a searcher is
+	finished before the monster has finished changing shape and the risk economy is a decoration.
+
+	This is a JUDGEMENT rather than an arithmetic identity — it does not account for distance, which
+	the map decides — so it is pinned as a floor and expected to be re-argued at V16 with real players.
+]]
+check(
+	"a search lasts longer than a transform and a revert — the monster can reach you mid-hold",
+	Config.Search.SearchTime > Config.Monster.TransformTime + Config.Monster.RevertTime,
+	`SearchTime={Config.Search.SearchTime}, Transform+Revert=`
+		.. `{Config.Monster.TransformTime + Config.Monster.RevertTime}`
+)
+
+-- V03. A radius of zero or less is unsearchable and would read as a dead key bind.
+check(
+	"a container can actually be reached",
+	Config.Search.RangeStuds > 0,
+	`RangeStuds={Config.Search.RangeStuds}`
+)
```

#### Phase 1 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the module is under `src/server/pure/`, so it does not replicate. Confirm the
  path in the diff before anything else; `src/shared/pure/ContainerLayout.luau` would be a silent,
  complete defeat of the chunk with every check still green.
- **Remote direction** — no remote in this phase.
- **Rate limiting** — no handler in this phase.
- **Magic numbers** — `check:config` governs `src/server/`, so `ContainerLayout.luau` must contain no
  tunable. The 4/2/1 counts arrive as `Counts`; `0`, `1` and `2` are on `IDIOMATIC` and the loop
  headers are exempt, so a correct implementation needs no waiver. `tests/` is not governed, which is
  why the xorshift constants are allowed to sit in the suite.
- **Phase ownership** — nothing here touches the phase.
- **Player leaving mid-round** — not reachable from a pure module.
- **Strict Luau** — the whole reason `Contents` is `{ [number]: string }`. If `analyze` reports "none
  of the union options are compatible" at a *call site* in a later phase, the fix belongs here, not
  there.
- **Mobile budget** — no lights, no particles, no per-frame work.
- **Scope** — "container", "search" and "layout" are not on §3's OUT list, and `BuntotPagi` splits to
  Buntot + Pagi under `check:scope`'s word splitter, matching nothing.

**Issues identified:**

- **`ContainerLayout.draw` must clamp `containerCount` before building `order`.** `for index = 1,
  containerCount` with a negative argument simply does not run, so `order` stays empty and `placeable`
  is already `math.min(#queue, math.max(containerCount, 0)) = 0`. Safe, but only because both guards
  are present — do not remove either.
- **`tally[id] = (tally[id] or 0) + 1` in the test is defensive on purpose.** If the module ever emits
  an id outside the three, the tally would otherwise error inside the loop and report as a crash
  rather than as `wrongMultiset`. The `itemAt` forged-id assertion at the foot covers the same class
  from the other side.
- **The 5% band is asserted at ±4.68σ, and that is the honest reading.** It is not "5% is the right
  amount of randomness" — it is "a fixed-seed run of this algorithm sits inside 5%, and anything that
  does not is a changed algorithm". Stated so nobody widens it to make a real regression pass.

### Phase 2: The network surface, its types, and its budgets

Three remotes declared, two budgets added, nothing fired yet. Ends green on `npm run verify:fast`.

#### Step 2.1: Add the search verdict and the update payload to `Types`

**File:** `src/shared/Types.luau`
**Verify:** `npm run analyze`

`SearchVerdict` (a `SEARCH_`-prefixed literal union, following `TrialPhase`'s precedent so a handler
wired to the wrong remote is a type error) and `SearchUpdatePayload` — three fields, and the absent
ones are the security design.

```diff
+--[[
+	V03, §4.4. The answer to "may I search what I am standing at, and what did I get".
+
+	PREFIXED `SEARCH_` FOR `TrialPhase`'S REASON, restated because it is not decoration. `SaltVerdict`
+	already carries a bare `WRONG_PHASE` and `MonsterState` a bare `NORMAL`; a third union sharing
+	those spellings makes a handler wired to the wrong remote a working program with the wrong
+	meaning. `check:remotes` and `check:secrecy` are text tripwires and would pass a semantic mix-up
+	like that. The prefix makes it an analyzer error instead.
+
+	SEARCH_STARTED IS A VERDICT RATHER THAN A SECOND REMOTE. The client needs to know its hold began
+	so it can draw a bar; that is the same conversation as the refusals, on the same wire, to the same
+	one player.
+
+	NONE OF THESE NAMES A CONTAINER, AND NONE NAMES A PLAYER. `SEARCH_OCCUPIED` says "someone is at
+	this one" and `SEARCH_ALREADY_SEARCHED` says "this one is spent" — both are facts about the world
+	that §4.4 puts in the world deliberately ("items belong to the world, not to individuals"), both
+	concern a container the receiver is already standing at, and neither is role-correlated because
+	the Aswang searches on identical rules.
+]]
+export type SearchVerdict =
+	"SEARCH_STARTED" -- the hold began; HoldSeconds is how long it will take
+	| "SEARCH_OK" -- the hold completed; `Found` is the item, or nil for an empty container
+	| "SEARCH_INTERRUPTED" -- you cancelled, moved out of range, died, or the round moved on
+	| "SEARCH_WRONG_PHASE" -- searching is an ACTIVE-phase activity and nothing else
+	| "SEARCH_NOT_ALIVE" -- dead players and mid-round spectators do not search
+	| "SEARCH_NO_CONTAINER" -- nothing tagged within Config.Search.RangeStuds, or the map has no pool
+	| "SEARCH_OCCUPIED" -- somebody else is holding this container right now
+	| "SEARCH_ALREADY_SEARCHED" -- this container was opened earlier in the round
+	| "SEARCH_BUSY" -- you are already holding a different container
+
+--[[
+	V03, §4.4. `SearchUpdate`'s payload. FireClient to ONE player, always; there is no broadcast form
+	of this remote and there must not be.
+
+	THE ABSENT FIELDS ARE THE SECURITY DESIGN, so they are listed rather than merely omitted:
+
+	  · NO CONTAINER ID, in either direction. The client does not name one when it requests — the
+	    server resolves the nearest tagged part from that player's own character position, which is
+	    `ItemService`'s stated rule for pickups — and the server does not name one when it answers.
+	    There is therefore NO KEY ON WHICH TWO CLIENTS COULD DIFFERENCE THEIR PAYLOADS. What colluding
+	    players can pool is what each of them found by standing somewhere and opening something, which
+	    is the information §4.4 intends them to have and §4.5 gives them a phrase for.
+	  · NO LAYOUT, NO REMAINING COUNT, NO "3 of 7 found". A count is a map index compressed: it tells
+	    a client how much of the pool is still worth walking to, which is exactly the walk §4.4 wants
+	    to cost something. It also would not survive Amendment A3's spirit — see `ClientRoundSnapshot`.
+	  · NO SEARCHER. `SEARCH_OCCUPIED` does not say who.
+
+	`Found` IS NOT A ROLE ORACLE. The Aswang searches on identical rules and can find any of the three
+	(§4.4 — denying survivors the buntot pagi is a legitimate strategy that looks exactly like
+	survival), so this field's value distribution is the same for both roles.
+]]
+export type SearchUpdatePayload = {
+	Verdict: SearchVerdict,
+	-- Config.Search.SearchTime on SEARCH_STARTED, 0 on every other verdict. The client draws its own
+	-- bar from this one number; the server does not stream progress, because a per-frame per-player
+	-- remote would be a network cost paid for something the client can interpolate. It carries no
+	-- information — Config is replicated, so the client already knew it.
+	HoldSeconds: number,
+	-- What THIS player just found. nil on every path except a completed search of a seeded container,
+	-- including a completed search of an empty one — "you searched it and it held nothing" and "you
+	-- did not finish" are different verdicts, not different Found values.
+	Found: ItemType?,
+}
```

**NOTE on `Found: ItemType?`** — this is a **scalar** union crossing the `require` boundary, which the
lesson says is fine and needs no restructuring. It arrives from `ContainerLayout.itemAt`, already
narrowed by a function rather than a cast, so the value that reaches this field is one the analyzer
has checked against an annotated return type. That chain is the entire reason `Contents` holds plain
strings; do not shortcut it with a `::` at the assignment.

#### Step 2.2: Declare `RequestSearch`, `RequestCancelSearch` and `SearchUpdate`

**File:** `src/shared/Remotes.luau`
**Verify:** `npm run verify:fast`

Two up, one down, each with the argument it does **not** carry written down beside it.

In `EVENTS_DOWN`:

```diff
 	"TeachingCue",
+	--[[
+		V03, §4.4. FireClient to the ONE player whose search it is. Never FireAllClients — there is no
+		broadcast form of this payload and adding one would be a redesign, not an optimisation.
+
+		WHAT A SECOND CLIENT LEARNS FROM THIS REMOTE: nothing, because it never receives it. The
+		public half of searching is NOISE, and noise is V04's chunk — it will be a broadcast that
+		names a position and no player, and it is deliberately not this remote.
+
+		THE PAYLOAD NAMES NO CONTAINER. `Types.SearchUpdatePayload` carries a verdict, a duration and
+		an optional item, and the reasoning for each absent field is written there. The property worth
+		repeating here is the structural one: with no container id in the payload there is no key on
+		which two colluding clients could difference their updates to reconstruct the layout. The
+		layout exists only in a server-side table and in `server/pure/ContainerLayout`, which does not
+		replicate.
+
+		IT IS NOT A ROLE ORACLE. §4.4 has the Aswang searching on identical rules, so both roles
+		receive this remote with the same verdicts at the same rate for the same reasons.
+	]]
+	"SearchUpdate",
 }
```

In `EVENTS_UP`:

```diff
 	"RequestTrialThrow",
+	--[[
+		V03, §4.4. NO ARGUMENTS, and the absent argument is the entire security design.
+
+		THE CONTAINER IS NOT NAMED BY THE CLIENT. The server resolves the nearest `SearchContainer`
+		part within `Config.Search.RangeStuds` of that player's OWN character position — the rule
+		`ItemService`'s header states for pickups, applied to the one interaction that has a remote:
+		"the server resolves what a player is standing at from that player's own character position,
+		and the client names nothing."
+
+		A `RequestSearch(containerName)` would have been strictly worse in three ways, and the third
+		is the one that matters. It needs a verdict for "that container is not near you"; it needs
+		validation that the named part is the one you are standing at, which is the distance
+		comparison the server was already positioned to make; and it hands a compromised client a
+		PROBE — name every tagged part in turn, read the verdicts, and learn which containers are
+		spent and which are occupied without walking anywhere. The map's part names are readable by
+		any client (Workspace replicates), so the probe would have been trivial to write.
+	]]
+	"RequestSearch",
+	--[[
+		V03. Also argument-free: it means "I let go", and the server already knows whose hold it is.
+
+		SEPARATE FROM `RequestSearch` RATHER THAN A TOGGLE ON IT. A toggle desynchronises the moment a
+		packet is dropped or a token is refused — the client believes it stopped, the server believes
+		it started again — and the failure is a search that silently never completes. Two remotes make
+		each message idempotent: a duplicate cancel releases nothing, a duplicate start hits
+		SEARCH_BUSY.
+
+		THE SERVER DOES NOT DEPEND ON THIS ARRIVING. Five other release paths exist (distance, death,
+		leave, completion, phase change), so a cancel lost to the rate limiter costs at most the
+		remainder of one hold. That is why its budget is the more generous of the two — see Step 2.3.
+	]]
+	"RequestCancelSearch",
 }
```

#### Step 2.3: Budget both up-remotes

**File:** `src/shared/Config.luau`
**Verify:** `lune run tests/anti-cheat-budgets.test.luau`

Two `AntiCheat.Budgets` entries plus the matching `UP_REMOTES` entries in
`tests/anti-cheat-budgets.test.luau`. The suite cross-checks both directions, so this step cannot
land half-done.

**Second file in this step:** `tests/anti-cheat-budgets.test.luau`. That file's `UP_REMOTES` is a hand
copy of `Remotes.EVENTS_UP` (its header explains why Lune cannot require `Remotes.luau`), and it
asserts in both directions — a budget naming a remote the list lacks fails, and a listed remote with no
budget fails. So the Verify line for this step genuinely discriminates: forget the Config entry and it
goes red.

**`AllowUnbudgetedRemote` does not save you.** `AntiCheatService.Consume` **fails closed** — a remote
with no budget is refused (`src/server/Services/AntiCheatService.luau:112-119`). A missing budget here
is not "unlimited searching", it is "searching does not work at all, for everyone, silently".

```diff
 		Budgets = {
 			RequestTransform = { Capacity = 3, RefillPerSecond = 0.2 },
 			RequestKill = { Capacity = 3, RefillPerSecond = 0.25 },
 			RequestThrowSalt = { Capacity = 3, RefillPerSecond = 0.2 },
 			RequestQuickChat = { Capacity = 4, RefillPerSecond = 0.5 },
+			--[[
+				V03, §4.4. THE MOST FREQUENT REMOTE A SURVIVOR FIRES, and the budget is sized from the
+				mechanic rather than from a feeling. A search takes Search.SearchTime = 6 seconds, so
+				an honest player starts one every ~7s at absolute best and usually far less often.
+				RefillPerSecond = 0.3 pays for one start every ~3.3s, which is roughly twice the
+				fastest honest rate and leaves room for the two cases that legitimately burn a token
+				without a search happening: a refusal (SEARCH_NO_CONTAINER when the thumb misses) and
+				a restart after an interruption.
+
+				Capacity 4 is the burst. A player walking a row of containers in a house genuinely
+				fires four starts in quick succession as they cancel and re-target.
+			]]
+			RequestSearch = { Capacity = 4, RefillPerSecond = 0.3 },
+			--[[
+				V03. DELIBERATELY MORE GENEROUS THAN `RequestSearch`, and the asymmetry is the point.
+
+				A refused START costs a player one search. A refused CANCEL leaves them holding a
+				container they asked to let go of, which reads as the game ignoring their input — the
+				worse of the two failures, and the one a player blames the game for. The server has
+				five other release paths so the hold is never actually stuck, but "it releases when you
+				walk away" is not the feedback the button promised.
+
+				Cancels also arrive in bursts honestly: a key tapped rather than held fires start and
+				cancel back to back.
+			]]
+			RequestCancelSearch = { Capacity = 6, RefillPerSecond = 0.5 },
 			RequestEquipCosmetic = { Capacity = 5, RefillPerSecond = 0.5 },
```

And in `tests/anti-cheat-budgets.test.luau`'s hand copy:

```diff
 	"RequestTrialThrow",
+	-- V03. Both argument-free: the server resolves the container from the player's own position, and
+	-- a cancel means "I let go". The cancel's budget is the more generous of the two on purpose —
+	-- see Config, and note that Consume FAILS CLOSED, so a missing budget here disables searching
+	-- entirely rather than leaving it unlimited.
+	"RequestSearch",
+	"RequestCancelSearch",
 }
```

#### Phase 2 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — `SearchUpdate` is a new down remote. It is **not** added to
  `check-secrecy.mjs`'s `REVEAL_ALLOWLIST` and must not be: it carries no role, so it needs no
  exemption. If a later change makes the scanner flag it, the payload is wrong, not the scanner.
  Re-read `Types.SearchUpdatePayload`'s absent-field list before adding any field to it.
- **Remote direction** — `SearchUpdate` in `EVENTS_DOWN`, `RequestSearch` and `RequestCancelSearch` in
  `EVENTS_UP`. `check:remotes` fails on a remote fired in the wrong direction, and it is the reason a
  client `WaitForChild` on a name the server never created hangs forever with no error.
- **Rate limiting** — the budgets land in this phase; the handlers that consume them land in 3.3. The
  order is deliberate: `Consume` fails closed, so a handler written before its budget exists would be
  a handler that refuses everything.
- **Magic numbers** — the four budget numbers are in `Config`, where `check:config` wants them.
- **Phase ownership** — nothing here touches the phase.
- **Player leaving mid-round** — `AntiCheatService.onPlayerRemoving` already clears buckets by UserId,
  so the two new budgets need no cleanup of their own.
- **Strict Luau** — `SearchVerdict` is a literal union used as a **scalar** field on
  `SearchUpdatePayload`, which survives `require` intact. `Found: ItemType?` likewise.
- **Mobile budget** — one remote per search start and one per finish, per player. Compare
  `Round.SnapshotInterval = 0.5`, which is several per second per player for the whole round.
- **Scope** — nothing added.

**Issues identified:**

- **The hand copy in `tests/anti-cheat-budgets.test.luau` can drift, and this step widens the gap by
  two.** The file's own header names the clean fix — a check script parsing both files — and defers
  it. This plan defers it too, for the same reason: V03 is not the chunk that should be growing the
  harness. Carried to Follow Ups.
- **Nothing fires these remotes at the end of Phase 2.** `check:remotes` fails on a remote *used* but
  not declared, not on one declared but unused, so the tree is green and the surface is inert. That is
  the intended resting state for this phase.

### Phase 3: SearchService — the pool, the seed, the lock and the two handlers

The chunk's substance. Ends green on `npm run verify:fast`.

#### Step 3.1: The service — discovery, the seed at `STARTING`, and the V08 seam

**File:** `src/server/Services/SearchService.luau`
**Verify:** `npm run analyze`

Header, requires, tag discovery through `SearchPool.evaluate`, the phase subscription that seeds at
`STARTING` and clears at every phase that is not `ACTIVE`, the `ItemFound` BindableEvent that V08
connects to, and `Init`/`Start`. (Bootstrap registration is Step 4.3, with the client's.)

**The V08 seam, stated at its narrowest.** V03's Done line is "searching yields items". V08 owns
`ItemService`, inventory and the three items. So V03 **tells the finder what they found and records it
server-side, and grants nothing**: no `Tool`, no carry slot, no touch of `ItemService.carried`, no
producer for `ClientRoundSnapshot.YourCarriedItem` (V02 deliberately left that field without one).
The seam is one BindableEvent, `SearchService.ItemFound`, firing `(player, itemId: string)`, which V03
connects to nothing. That is the whole handover, and it is flagged in Follow Ups as an explicit
partial.

```diff
+--!strict
+--[[
+	SearchService — the container layout, and the six seconds it costs to open one. (V03, §4.4)
+
+	Milestone: V03. Spec: docs/MVP-SPEC.md §4.4, §6.2.
+
+	SEARCHING IS THE ONLY ACTIVITY IN THE GAME (§4.4). There are no tasks; V01 deleted them. Four
+	things happen in this file and each is server-decided:
+
+	  · the tagged pool is discovered and judged at STARTING       (SearchPool.evaluate)
+	  · a layout is drawn from server-only entropy                 (server/pure/ContainerLayout)
+	  · RequestSearch is resolved into a hold on one container     (nearest, from the player's own
+	                                                                position — the client names nothing)
+	  · the hold completes after Config.Search.SearchTime and the finder alone is told what was in it
+
+	THE LAYOUT NEVER CROSSES THE WIRE, AND NEVER REACHES A LOG. Not as a payload, not as an attribute,
+	not as a tag — attributes and CollectionService tags replicate to EVERY client and there is no
+	private one. The log rule is the less obvious half: in a Studio solo test the server and client
+	share one output window, so `print`ing where the buntot pagi is puts it in front of the person
+	playing. Log COUNTS and VERDICTS, never contents.
+
+	THE ASWANG SEARCHES ON IDENTICAL RULES, AND NO BRANCH IN THIS FILE READS ITS IDENTITY. §4.4 wants
+	it that way — rummaging inside a house is blending justified by mechanics rather than performed,
+	and denying survivors the buntot pagi is a real strategy that looks exactly like survival. It is
+	also Amendment A2's generalisation: any activity the monster cannot perform sincerely becomes an
+	oracle that identifies it. `RoundService.GetAswangUserId` must not appear in this file. If a future
+	change wants a role-dependent search, that is a spec conversation, not an implementation detail.
+
+	ROUNDSERVICE OWNS THE PHASE (§6.4). This service subscribes and never calls setPhase, and it never
+	blocks or delays a transition — an EMPTY map produces a round with nothing to find and a loud warn,
+	not a round that will not start.
+
+	V03 GRANTS NOTHING. `ItemFound` below is the seam V08 connects; see its comment.
+]]
+
+local CollectionService = game:GetService("CollectionService")
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local AntiCheatService = require(script.Parent.AntiCheatService)
+local RoundService = require(script.Parent.RoundService)
+-- The one verdict module every tag-driven pool in this game shares. Generic over
+-- (names, required, expected) and naming no mechanic, so this is a second CALLER rather than a second
+-- copy — ItemService's salt pool is the first.
+local SearchPool = require(script.Parent.Parent.pure.SearchPool)
+local ContainerLayout = require(script.Parent.Parent.pure.ContainerLayout)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
+
+local SearchService = {}
+
+local TAG_CONTAINER = "SearchContainer"
+
+--[[
+	THE SEAM TO V08, and V03 connects nothing to it.
+
+	V03's Done line is "searching yields items". V08 owns ItemService, the three items and the carry
+	slot, so this chunk stops at telling the finder and recording the find. It creates no Tool, touches
+	no carry count and produces no `ClientRoundSnapshot.YourCarriedItem` — V02 left that field without
+	a producer deliberately and V08 is the chunk that adds one.
+
+	Fires (player, itemId) where itemId is a PLAIN STRING. A BindableEvent's arguments are `...any`, so
+	the connector must narrow it — `ContainerLayout.itemAt`-style, with a function and not a cast, for
+	the reason in that module's header.
+
+	A BindableEvent rather than a direct call for `RoundService.PhaseChanged`'s reason: it lets V08
+	depend on this service without this service depending on V08, so the arrow cannot become a cycle.
+	A require cycle errors at load, init.server.luau swallows it into one warn, and the server sits
+	looking exactly like "nobody has joined yet".
+]]
+SearchService.ItemFound = Instance.new("BindableEvent")
+
+--------------------------------------------------------------------------------
+-- SERVER-ONLY state. None of this replicates. None of it is logged in full.
+--------------------------------------------------------------------------------
+
+-- Every `SearchContainer` part, keyed by Name. Rebuilt on every seed rather than cached, for the
+-- reason any tag-driven pool is: the map author will add, move and delete these parts while a server
+-- is running, and a cached part is one that can stop existing.
+local containersByName: { [string]: BasePart } = {}
+
+--[[
+	Container index -> Name, and its inverse. THE INDEX IS THE POSITION IN THE SORTED NAME LIST, which
+	is what ties `ContainerLayout`'s abstract 1..n to actual parts in the world.
+
+	A CLIENT CAN DERIVE THIS ORDERING AND IT DOES NOT MATTER. Workspace replicates, so any client can
+	read every tagged part's Name and sort them. What it cannot derive is the CONTENTS, which come from
+	`Random.new()` on this machine and exist only in `layout` below. Publishing an ordering is not
+	publishing a layout — the same distinction `RoleDraw`'s header draws between an algorithm and a
+	reproducible draw.
+]]
+local orderedNames: { string } = {}
+local indexByName: { [string]: number } = {}
+
+-- THE SECRET. Nil outside a round and whenever the map has no usable pool.
+local layout: ContainerLayout.Layout? = nil
+
+-- Container index -> true once opened. Server-only: a client that could read this would know which
+-- containers are still worth walking to, which is exactly the walk §4.4 wants to cost something.
+local opened: { [number]: boolean } = {}
+
+--------------------------------------------------------------------------------
+-- Pool discovery. Lifted almost verbatim from ItemService.discoverPool, which is
+-- the established shape for a tag-driven pool in this repo.
+--------------------------------------------------------------------------------
+
+local function discoverPool(): SearchPool.Report
+	local names: { string } = {}
+
+	table.clear(containersByName)
+
+	for _, instance in CollectionService:GetTagged(TAG_CONTAINER) do
+		if not instance:IsA("BasePart") then
+			warn(
+				`[SearchService] {instance:GetFullName()} is tagged {TAG_CONTAINER} but is a `
+					.. `{instance.ClassName}, not a BasePart — skipped.`
+			)
+			continue
+		end
+
+		table.insert(names, instance.Name)
+
+		-- The `: BasePart?` is load-bearing under --!strict: indexing a `{ [string]: BasePart }` yields
+		-- a non-optional value, so comparing it to nil is a type error rather than a lookup.
+		local existing: BasePart? = containersByName[instance.Name]
+
+		if existing == nil then
+			containersByName[instance.Name] = instance
+		end
+	end
+
+	--[[
+		SORTED, AND THIS LINE IS SECURITY RATHER THAN TIDINESS. `GetTagged`'s order is engine-defined
+		and can differ between servers and between runs. Feeding it into a random draw makes the draw
+		depend on a hidden input — which does not leak anything by itself, but it makes the layout
+		irreproducible for anyone debugging it and, worse, makes "same entropy, same layout" false, so
+		no test could ever pin the wiring. ItemService sorts for the same reason.
+	]]
+	table.sort(names)
+
+	return SearchPool.evaluate(names, SearchService.TotalItems(), Config.Search.ContainerCount)
+end
+
+--[[
+	How many items the round places. SUMMED FROM CONFIG rather than typed, so a V16 tune of any
+	*SpawnCount* moves the pool requirement with it and `check:config` has no literal to flag.
+]]
+function SearchService.TotalItems(): number
+	return Config.Items.SaltSpawnCount
+		+ Config.Items.GarlicSpawnCount
+		+ Config.Items.BuntotPagiSpawnCount
+end
+
+--[[
+	THE LOUD HALF, ungated by VerboseLogging, on this repo's rule that routine tracing is gated and
+	faults warn unconditionally. A barrio with no containers in it is a fault whose only player-visible
+	symptom is that there is nothing to do and nobody knows why.
+
+	NOT ONE OF THESE LINES NAMES A CONTENT. Counts and verdicts only.
+]]
+local function reportPool(report: SearchPool.Report)
+	local required = SearchService.TotalItems()
+
+	if #report.Duplicates > 0 then
+		warn(
+			`[SearchService] {TAG_CONTAINER} parts share a Name and were skipped: `
+				.. `{table.concat(report.Duplicates, ", ")}. Every tagged part needs a unique one.`
+		)
+	end
+
+	if report.Verdict == "EMPTY" then
+		warn(
+			`[SearchService] NO "{TAG_CONTAINER}" PARTS IN THE MAP. Tag {Config.Search.ContainerCount} `
+				.. `anchored parts with "{TAG_CONTAINER}" via CollectionService, or nothing can ever be `
+				.. `found and §4.4's entire loop does not exist — survivors have no activity at all.`
+		)
+	elseif report.Verdict == "SHORT" then
+		warn(
+			`[SearchService] Only {#report.Unique} "{TAG_CONTAINER}" part(s) found; {required} items `
+				.. `are meant to be placed. Fewer will be, buntot pagi and salt first.`
+		)
+	elseif report.Verdict == "OVERSIZED" then
+		warn(
+			`[SearchService] {#report.Unique} "{TAG_CONTAINER}" parts found, but `
+				.. `Config.Search.ContainerCount says {Config.Search.ContainerCount}. Seeding still `
+				.. `works; the map and Config disagree.`
+		)
+	elseif Config.Debug.VerboseLogging then
+		print(`[SearchService] Container pool OK — {#report.Unique} containers.`)
+	end
+end
+
+--------------------------------------------------------------------------------
+-- The seed. This is the function §6.2 names as server-only state.
+--------------------------------------------------------------------------------
+
+local function seedLayout()
+	local report = discoverPool()
+
+	reportPool(report)
+
+	table.clear(orderedNames)
+	table.clear(indexByName)
+	table.clear(opened)
+
+	if report.Verdict == "EMPTY" then
+		-- No pool, no layout, and the round still starts. Every RequestSearch answers
+		-- SEARCH_NO_CONTAINER, which is the truth.
+		layout = nil
+		return
+	end
+
+	for index, name in report.Unique do
+		orderedNames[index] = name
+		indexByName[name] = index
+	end
+
+	--[[
+		`Random.new()` WITH NO ARGUMENT. THIS IS THE LINE THE WHOLE CHUNK IS ABOUT.
+
+		`Random.new(state.RoundNumber)` and `Random.new(os.time())` are both fatal: a client knows the
+		round number and can read the clock to the second, so either one lets it replay this draw
+		locally and know where the buntot pagi is BEFORE the round starts — with no remote to
+		intercept and nothing for `check:secrecy` to see. §4.4 and §6.2 both say so explicitly. The
+		no-argument constructor seeds from server-only entropy.
+
+		The adapter below matches `ContainerLayout.draw`'s `nextInt(lo, hi)` contract, which was
+		written to match `Random:NextInteger` so nothing has to be remembered at the call site.
+	]]
+	local rng = Random.new()
+
+	layout = ContainerLayout.draw(#orderedNames, {
+		Salt = Config.Items.SaltSpawnCount,
+		Bawang = Config.Items.GarlicSpawnCount,
+		BuntotPagi = Config.Items.BuntotPagiSpawnCount,
+	}, function(lo: number, hi: number): number
+		return rng:NextInteger(lo, hi)
+	end)
+
+	if Config.Debug.VerboseLogging then
+		-- COUNTS, NEVER CONTENTS. See the header: in a Studio solo test this window is in front of the
+		-- player. `Placed` and the pool size are safe — both are derivable from Config and the map.
+		local placed = if layout then layout.Placed else 0
+
+		print(`[SearchService] Seeded {placed} item(s) across {#orderedNames} containers.`)
+	end
+end
+
+local function clearLayout()
+	layout = nil
+
+	table.clear(opened)
+	table.clear(orderedNames)
+	table.clear(indexByName)
+	table.clear(containersByName)
+end
+
+--------------------------------------------------------------------------------
+-- Phase subscription. RoundService owns the phase; this only reacts to it.
+--------------------------------------------------------------------------------
+
+--[[
+	A PLACEHOLDER THAT STEP 3.2 REPLACES, and it is here rather than omitted because `gate-luau-analyze
+	.mjs` typechecks every `.luau` write as it happens — a forward reference to a function defined
+	later in the file is an analyzer error in Luau, so 3.1 could not land at all without this.
+
+	Harmless in the interval: nothing creates a hold until Step 3.3 wires the handlers, so there is
+	never anything for it to release. STEP 3.2 REPLACES THE BODY; it must not leave two definitions.
+]]
+local function releaseAllHolds(_verdict: Types.SearchVerdict) end
+
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase == Enums.RoundPhase.Starting then
+		seedLayout()
+	end
+
+	--[[
+		EVERY PHASE THAT IS NOT ACTIVE releases every hold — including STARTING, which is why this sits
+		BELOW the seed above rather than beside it. A hold surviving into the next round would be a
+		player searching a container whose contents have just been redrawn.
+
+		The layout itself is cleared only on the way DOWN (INTERMISSION/IDLE), not at ENDING: §4.8's
+		end screen runs for Config.Round.EndScreen seconds and there is no reason to tear state down
+		while it does. `releaseAllHolds` is defined in Step 3.2.
+	]]
+	if phase ~= Enums.RoundPhase.Active then
+		releaseAllHolds("SEARCH_INTERRUPTED")
+	end
+
+	if phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
+		clearLayout()
+	end
+end
+
+function SearchService.Init()
+	clearLayout()
+end
+
+function SearchService.Start()
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	-- Handlers and the hold tick are wired here too; see Steps 3.2 and 3.3.
+end
+
+return SearchService
```

**IMPORTANT — the placeholder is not optional.** A `local function` must be declared above its callers
in Luau, and `gate-luau-analyze.mjs` typechecks each `.luau` write as it happens — so 3.1 cannot land
with a forward reference to a body that arrives in 3.2. The no-op above is what keeps every step in
this phase individually green. **Step 3.2 replaces its body in place**; two definitions of
`releaseAllHolds` would leave the no-op shadowed or, worse, shadowing.

#### Step 3.2: The hold — one authority, one reverse index, six release paths

**File:** `src/server/Services/SearchService.luau`
**Verify:** `npm run check:config`

`beginHold`, `releaseHold`, `completeHold`, and the `task.spawn` tick that advances them — matching
the loop shape `ItemService` and `RoundService` already use. Every number read from `Config`.

**Q3 answered in code.** `holds` keyed by UserId is the **single authority**; `occupied` keyed by
container index is a **reverse index** written by exactly two functions. Six release paths, all routed
through `releaseHold`. This block goes **above** `onPhaseChanged`, replacing the 3.1 placeholder.

```diff
+--------------------------------------------------------------------------------
+-- The hold. ONE AUTHORITY AND ONE REVERSE INDEX.
+--
+-- `holds` is the truth: a player either has a hold or does not. `occupied` exists
+-- only so that "is anybody on this container" is a lookup rather than a scan of
+-- every player, and it is written by beginHold and releaseHold and by nothing
+-- else. If the two ever disagree, `holds` wins — but the point of confining the
+-- writes to two functions is that they cannot.
+--------------------------------------------------------------------------------
+
+type Hold = {
+	ContainerIndex: number,
+	-- Cached so the tick does not re-resolve the part every pass, and so a container deleted from the
+	-- map mid-hold releases cleanly instead of erroring.
+	Name: string,
+	EndsAt: number,
+}
+
+local holds: { [number]: Hold } = {}
+local occupied: { [number]: number } = {}
+
+--[[
+	WHAT THIS PLAYER HAS FOUND THIS ROUND. Server-only, keyed by UserId, never replicated as a table.
+
+	V03 RECORDS AND GRANTS NOTHING — see `SearchService.ItemFound`. This exists so that V08 has
+	somewhere truthful to read from, and so that a playtester can confirm "searching yields items"
+	from the server side rather than from a client's word for it.
+
+	A ROSTER OF WHO HOLDS WHAT IS A ROSTER OF WHO CAN ANSWER THE ASWANG, which is `ItemService`'s
+	stated reason for keeping `carried` server-side, and §4.5's reason the buntot pagi's carrier
+	announces themselves by CHOICE. Never broadcast this, never mirror it onto an attribute.
+]]
+local foundByPlayer: { [number]: { string } } = {}
+
+local updateRemote = Remotes.Get("SearchUpdate")
+
+--[[
+	FireClient to ONE player, and this is the only function in the file that sends anything.
+
+	Built as a TYPED LOCAL rather than an inline table for `ItemService.broadcastEffect`'s reason:
+	`FireClient` takes `...any`, so an inline literal is unchecked and a typo'd field name would ship.
+	The annotation is what makes `Types.SearchUpdatePayload`'s absent-field argument enforceable.
+]]
+local function sendUpdate(player: Player, verdict: Types.SearchVerdict, found: Types.ItemType?)
+	local payload: Types.SearchUpdatePayload = {
+		Verdict = verdict,
+		-- Only a live hold has a duration. Every refusal and every ending sends 0, so a client cannot
+		-- read a timing difference off a refusal.
+		HoldSeconds = if verdict == "SEARCH_STARTED" then Config.Search.SearchTime else 0,
+		Found = found,
+	}
+
+	updateRemote:FireClient(player, payload)
+end
+
+local function beginHold(player: Player, containerIndex: number, name: string)
+	holds[player.UserId] = {
+		ContainerIndex = containerIndex,
+		Name = name,
+		EndsAt = os.clock() + Config.Search.SearchTime,
+	}
+	occupied[containerIndex] = player.UserId
+
+	sendUpdate(player, "SEARCH_STARTED", nil)
+end
+
+--[[
+	THE ONLY WAY A HOLD ENDS. Every one of the six paths goes through here, and that is the entire
+	design of this section: a release path that clears `holds` without clearing `occupied` locks a
+	container for the rest of the round, with no symptom except that nobody can search it.
+
+	`verdict` is nil when the caller has already sent its own message — `completeHold` sends SEARCH_OK
+	with the item and must not be followed by an INTERRUPTED. Every other caller passes one.
+
+	SAFE TO CALL FOR A PLAYER WITH NO HOLD. Three of the six paths (leaving, dying, a phase change)
+	fire for players who were not searching, and an early return is cheaper than six callers checking.
+]]
+local function releaseHold(userId: number, verdict: Types.SearchVerdict?)
+	local hold = holds[userId]
+
+	if hold == nil then
+		return
+	end
+
+	holds[userId] = nil
+
+	-- Guarded rather than assigned blindly: if two holds ever raced onto one container, clearing the
+	-- index unconditionally would release the OTHER player's lock. beginHold's SEARCH_OCCUPIED check
+	-- makes that unreachable; this makes it harmless if it ever stops being.
+	if occupied[hold.ContainerIndex] == userId then
+		occupied[hold.ContainerIndex] = nil
+	end
+
+	if verdict == nil then
+		return
+	end
+
+	local player = Players:GetPlayerByUserId(userId)
+
+	if player ~= nil then
+		sendUpdate(player, verdict, nil)
+	end
+end
+
+-- Path 6: every phase that is not ACTIVE. REPLACES Step 3.1's placeholder in place — keep the
+-- `local`, and leave only one definition of this name in the file. Dropping the `local` would make it
+-- a global, which selene flags and which would leave the placeholder still shadowing it.
+local function releaseAllHolds(verdict: Types.SearchVerdict)
+	for userId in holds do
+		releaseHold(userId, verdict)
+	end
+end
+
+--[[
+	Path 1: the hold ran its course. The ONLY path that yields an item.
+
+	`opened` is marked BEFORE the item is read, so that no early return below can leave a container
+	both spent and re-searchable. Items belong to the world (§4.4's anti-frustration rule), so a
+	container empties for everyone, not per player.
+]]
+local function completeHold(player: Player, hold: Hold)
+	local current = layout
+
+	opened[hold.ContainerIndex] = true
+
+	releaseHold(player.UserId, nil)
+
+	if current == nil then
+		sendUpdate(player, "SEARCH_OK", nil)
+		return
+	end
+
+	-- Narrowed by a FUNCTION, not a cast. An id the module does not recognise arrives as nil and is
+	-- reported as an empty container rather than waved into the payload — see ContainerLayout's
+	-- header and `.claude/lessons/pure-module-unions-widen-in-lists.md`.
+	local item = ContainerLayout.itemAt(current, hold.ContainerIndex)
+
+	if item == nil then
+		-- §4.4: "You will open empty ones, and that is the point." This is the common case.
+		sendUpdate(player, "SEARCH_OK", nil)
+		return
+	end
+
+	local pocket = foundByPlayer[player.UserId]
+
+	if pocket == nil then
+		pocket = {}
+		foundByPlayer[player.UserId] = pocket
+	end
+
+	table.insert(pocket, item)
+
+	sendUpdate(player, "SEARCH_OK", item)
+
+	-- V08 connects here. V03 connects nothing; see SearchService.ItemFound.
+	SearchService.ItemFound:Fire(player, item)
+end
+
+--[[
+	Resolve the part a hold is on, and how far the searcher has strayed from it.
+
+	Returns nil when the container has stopped existing — a map author deleting a tagged part mid-round
+	is a real thing and it must release the hold rather than error inside the tick.
+]]
+local function holdDistance(player: Player, hold: Hold): number?
+	local container: BasePart? = containersByName[hold.Name]
+	local character = player.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+	if container == nil or root == nil or not root:IsA("BasePart") then
+		return nil
+	end
+
+	return (container.Position - root.Position).Magnitude
+end
+
+--[[
+	THE TICK. Paths 2 (moved out of range) and 3 (no longer ALIVE), plus path 1's trigger.
+
+	Assigning nil to an existing key during a generalised-for traversal is defined behaviour in Luau,
+	so releasing a hold from inside this loop is safe. `releaseHold` writes a DIFFERENT table
+	(`occupied`), which is not being traversed.
+]]
+local function searchTick()
+	local now = os.clock()
+
+	for userId, hold in holds do
+		local player = Players:GetPlayerByUserId(userId)
+
+		-- Path 4's backstop. PlayerRemoving normally gets there first; this covers the window where it
+		-- has not fired yet.
+		if player == nil then
+			releaseHold(userId, nil)
+			continue
+		end
+
+		-- Path 3. DEAD or SPECTATOR, or a character that has gone away underneath them.
+		if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+			releaseHold(userId, "SEARCH_INTERRUPTED")
+			continue
+		end
+
+		local distance = holdDistance(player, hold)
+
+		-- Path 2. Walked away, or the container stopped existing. §4.4's six seconds are only a cost
+		-- if they must be spent standing still — this line is what makes them one.
+		if distance == nil or distance > Config.Search.RangeStuds then
+			releaseHold(userId, "SEARCH_INTERRUPTED")
+			continue
+		end
+
+		if now >= hold.EndsAt then
+			completeHold(player, hold)
+		end
+	end
+end
```

And in `Start`, the loop and path 4, matching `ItemService.Start`'s shape verbatim:

```diff
 function SearchService.Start()
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	-- Path 4. A departing player's hold goes with them, and their pocket with it. Without this both
+	-- tables grow for the life of the server.
+	Players.PlayerRemoving:Connect(function(player: Player)
+		releaseHold(player.UserId, nil)
+
+		foundByPlayer[player.UserId] = nil
+	end)
+
+	task.spawn(function()
+		while true do
+			searchTick()
+			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
+		end
+	end)
 end
```

**NOTE on tick resolution.** `0.25` matches `ItemService`'s pickup loop and `RoundService`'s step
loop, with the same waiver text, so the three agree. It means a hold can overrun its six seconds by up
to a quarter-second and a searcher can be up to a quarter-second late leaving range. Both are well
inside what a player perceives, and neither is exploitable: the overrun favours nobody and the lag
window is 0.25s of walking, which is less than `RangeStuds` is generous by.

#### Step 3.3: The two handlers — `AntiCheatService` first, then the argument

**File:** `src/server/Services/SearchService.luau`
**Verify:** `npm run check:ratelimit`

`RequestSearch` and `RequestCancelSearch`, both argument-free, both consuming a token before
anything else happens.

**`Consume` FIRST, before the argument is even looked at.** `check-ratelimit.mjs` matches
`AntiCheat\w*[.:]\s*(Allow|Check|Consume|RateLimit|Permit)` within 1200 characters of an
`.OnServerEvent:Connect(` — by its own admission a proximity tripwire — so a handler that is limited
but does it further down reads as unguarded and fails the build. `ItemService` states this at
`src/server/Services/ItemService.luau:739-742`.

```diff
+--------------------------------------------------------------------------------
+-- Resolution. The client names nothing; the server decides everything.
+--------------------------------------------------------------------------------
+
+--[[
+	THE NEAREST CONTAINER THIS PLAYER IS STANDING AT, or nil.
+
+	Resolved from the player's OWN character position — `ItemService`'s stated rule, and the reason
+	`RequestSearch` carries no argument. A client that could name a container could probe every one of
+	them from across the map and read the verdicts back as a map index.
+
+	Nearest rather than first-found because two containers can overlap within RangeStuds — under a
+	papag beside a sack — and "the one I am closest to" is the only answer a player will not call a bug.
+]]
+local function nearestContainer(player: Player): (number?, string?)
+	local character = player.Character
+	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
+
+	if root == nil or not root:IsA("BasePart") then
+		return nil, nil
+	end
+
+	local bestIndex: number? = nil
+	local bestName: string? = nil
+	local bestDistance = Config.Search.RangeStuds
+
+	for name, container in containersByName do
+		local distance = (container.Position - root.Position).Magnitude
+
+		if distance <= bestDistance then
+			bestDistance = distance
+			bestName = name
+			bestIndex = indexByName[name]
+		end
+	end
+
+	return bestIndex, bestName
+end
+
+--[[
+	THE GATE, IN BLOCKING-FIRST ORDER, and the order is most of the content.
+
+	Phase and liveness come before anything positional, so a player searching in the lobby is told the
+	true reason rather than "no container near you". Container identity comes last, because it is the
+	only branch that reveals anything about the world, and a player who fails an earlier gate has not
+	earned an answer about the world.
+
+	NO BRANCH HERE READS THE ASWANG'S IDENTITY, and none may. §4.4 and Amendment A2: the monster
+	searches on identical rules, and any activity it cannot perform sincerely becomes an oracle.
+]]
+local function evaluateSearch(player: Player): (Types.SearchVerdict, number?, string?)
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return "SEARCH_WRONG_PHASE", nil, nil
+	end
+
+	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+		return "SEARCH_NOT_ALIVE", nil, nil
+	end
+
+	if holds[player.UserId] ~= nil then
+		return "SEARCH_BUSY", nil, nil
+	end
+
+	local index, name = nearestContainer(player)
+
+	-- Covers both "nothing within RangeStuds" and "this map has no pool at all" — the EMPTY verdict
+	-- leaves containersByName cleared, so the loop above finds nothing and the player is told the
+	-- same true thing either way.
+	if index == nil or name == nil then
+		return "SEARCH_NO_CONTAINER", nil, nil
+	end
+
+	if opened[index] then
+		-- §4.4: items belong to the world, not to individuals. A container someone else emptied is
+		-- empty for you too, and telling you so beats six seconds spent finding out.
+		return "SEARCH_ALREADY_SEARCHED", nil, nil
+	end
+
+	if occupied[index] ~= nil then
+		return "SEARCH_OCCUPIED", nil, nil
+	end
+
+	return "SEARCH_STARTED", index, name
+end
```

And in `Start`, above the tick loop:

```diff
+	--[[
+		CONSUME FIRST. `check-ratelimit.mjs` is a proximity tripwire around `.OnServerEvent:Connect(`,
+		so a handler that limits itself further down reads as unguarded and fails the build. It is also
+		simply correct: the cheapest possible refusal is the one that happens before any work.
+
+		NO ARGUMENT IS ACCEPTED, so there is nothing to type-check after it. Every other handler in
+		this repo validates `unknown` here; this one has nothing to validate, which is the point of
+		the remote carrying no container id.
+	]]
+	Remotes.Get("RequestSearch").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestSearch") then
+			return
+		end
+
+		local verdict, index, name = evaluateSearch(player)
+
+		if verdict ~= "SEARCH_STARTED" or index == nil or name == nil then
+			sendUpdate(player, verdict, nil)
+			return
+		end
+
+		beginHold(player, index, name)
+	end)
+
+	--[[
+		Path 5: the player let go. Also argument-free, also Consume first.
+
+		IDEMPOTENT BY CONSTRUCTION — `releaseHold` returns early for a player with no hold — so a
+		duplicate cancel is free and a cancel that arrives after the hold already completed cannot
+		un-find an item.
+	]]
+	Remotes.Get("RequestCancelSearch").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestCancelSearch") then
+			return
+		end
+
+		releaseHold(player.UserId, "SEARCH_INTERRUPTED")
+	end)
```

#### Phase 3 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the question the chunk's Verify line hands to `exploit-auditor`: *can a client
  derive the layout from anything it receives?* Walk it explicitly:
  - **The payload.** `SearchUpdate` carries no container id in either direction, so there is no key on
    which two clients could difference their updates. `HoldSeconds` is constant and already in
    replicated Config.
  - **The ordering.** `orderedNames` is derivable client-side (Workspace replicates part names). It is
    an ordering, not a layout — the contents come from `Random.new()` on the server and live only in
    `layout`.
  - **The seed.** `Random.new()`, no argument. Grep the diff for `Random.new(` and confirm the
    parentheses are empty; this is the single line that decides the chunk.
  - **The logs.** `seedLayout` prints `Placed` and a pool size, never contents. `reportPool` prints
    verdicts and counts. Nothing prints `layout.Contents`.
  - **Attributes and tags.** None written. `SearchContainer` is a tag the *map* carries, not one this
    service adds, and the service adds no attribute to anything.
  - **The residual, stated honestly:** `SEARCH_ALREADY_SEARCHED` and `SEARCH_OCCUPIED` tell a player
    something about a container they are already standing at. That is world state §4.4 puts in the
    world on purpose, it names no player, and it is not role-correlated because the Aswang searches on
    identical rules.
- **Remote direction** — `SearchUpdate` fired with `FireClient` on the server and listened for on the
  client; both requests fired from the client and handled with `OnServerEvent`.
- **Rate limiting** — both handlers `Consume` on their first line. `check:ratelimit` is this step's
  Verify for exactly that reason.
- **Magic numbers** — `SearchTime`, `RangeStuds`, `ContainerCount` and the three `*SpawnCount`s all
  read from `Config`. The one literal in the phase is the `0.25` tick, waived with the same text
  `ItemService` and `RoundService` already use. `check:config` is Step 3.2's Verify.
- **Phase ownership** — `SearchService` subscribes to `RoundService.PhaseChanged` and never calls
  `setPhase`. Confirm `setPhase` appears nowhere in the diff, and that no path can delay a transition:
  `seedLayout` runs synchronously inside the `STARTING` handler and does not yield.
- **Player leaving mid-round** — spec §6.4's edge cases, resolved: `PlayerRemoving` releases the hold
  and drops the pocket; the tick's `player == nil` branch covers the window before it fires; a death
  or a mid-round spectator fails the `GetPlayerState` check; a container deleted from the map releases
  through `holdDistance` returning nil; a phase change releases everything.
- **Strict Luau** — `local existing: BasePart?` and `local container: BasePart?` are load-bearing:
  indexing a `{ [string]: BasePart }` yields a non-optional value, so comparing to nil is a type error
  rather than a lookup. `evaluateSearch` returns a tuple whose first element is a literal union in
  **scalar** position, which crosses fine.
- **Mobile budget** — server-side only. One 0.25s tick over a table of at most `MaxPlayers = 5`
  entries; no lights, no particles, no client per-frame work added.
- **Scope** — `SearchContainer`, `SearchService`, `ContainerLayout` hit nothing on §3's OUT list.

**Issues identified:**

- **`nearestContainer` uses `<=` rather than `<`, so ties resolve to whichever the hash order visits
  last.** `containersByName` is a hash map and its traversal order is not defined. This is a genuine
  non-determinism, and it is left in deliberately: a tie means two containers at *identical* distance
  to the millistud, and picking either is correct. It must not be "fixed" by iterating `orderedNames`
  and taking the first match — that would make the *lowest sorted name* win every tie, which is a rule
  a client could learn and exploit to target a specific container by standing in a computed spot.
- **A hold survives a `SEARCH_ALREADY_SEARCHED` container being re-seeded.** It cannot happen inside a
  round — `opened` and `layout` are cleared together — but if a future chunk re-seeds mid-round,
  `releaseAllHolds` must be called first. Written here because Phase 3's slice is where someone will
  add that.
- **`foundByPlayer` is written and read by nothing in V03.** That is intentional (V08 owns inventory)
  and it will look like dead code to a reviewer. It is the evidence surface for the playtester and the
  data V08 reads; do not delete it as unused.
- **The Aswang can search and will find items it cannot use.** V03 grants nothing, so this is
  invisible for now. V08 must decide what happens when the Aswang finds the buntot pagi — §4.4 says
  denying survivors items is a legitimate strategy, which implies it *can* hold them. Carried to
  Follow Ups; it is a V08 decision, not a V03 one.

### Phase 4: The client asks, and the seam is written down

Minimal: one controller, one key bind, two registrations. Ends green on `npm run verify`.

#### Step 4.1: `SearchController` — receive the update, hold the bar's state

**File:** `src/client/Controllers/SearchController.luau`
**Verify:** `npm run analyze`

Listens to `SearchUpdate`, keeps a hold deadline, renders the find through the `ShowLine` that
`OnboardingController` already owns. Owns no truth.

```diff
+--!strict
+--[[
+	SearchController — what the six seconds look like from inside. (V03, §4.4)
+
+	OWNS NO TRUTH, and in this file that is not a slogan. The server decides whether a search started,
+	whether it finished and what was in the container; this file holds a deadline so a bar can be drawn
+	between two messages, and drops it the moment the server says otherwise. A client-side timer that
+	completed on its own would be a client deciding it found something.
+
+	NO CONTAINER IS NAMED, IN EITHER DIRECTION. The request carries no argument — the server resolves
+	the nearest container from this player's own character position — and the update carries no id
+	back. So there is nothing in this controller that could be logged, differenced or accumulated into
+	a map of where the items are, which is the property §6.2 asks for and `Types.SearchUpdatePayload`
+	explains at length.
+
+	NO NEW LABEL AND NO NEW HUD. The find renders through `OnboardingController.ShowLine`, which
+	already exists and is already used this way by `TeachingService`'s cues. A carry slot with an icon
+	is V08's — this chunk grants no item, so a carry HUD would be drawing something that is not there.
+]]
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local OnboardingController = require(script.Parent.OnboardingController)
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Types = require(Shared.Types)
+local Remotes = require(Shared.Remotes)
+
+local SearchController = {}
+
+-- os.clock() at which the current hold is due to finish, or nil when not searching. A DISPLAY
+-- estimate: the server owns the real deadline and re-derives it every tick.
+local holdEndsAt: number? = nil
+
+function SearchController.IsHolding(): boolean
+	return holdEndsAt ~= nil
+end
+
+--[[
+	0 to 1 through the current hold, or nil when there is none. Exposed for the bar a later HUD chunk
+	will draw; nothing renders it yet, and that is why this controller adds no GUI of its own.
+
+	CLAMPED AT 1 RATHER THAN COMPLETING. Reaching 1 means "the server should be about to answer", not
+	"the search succeeded" — the server's tick runs at 0.25s, so the bar can sit full for a moment
+	before SEARCH_OK arrives. A bar that cleared itself at 1 would be the client deciding.
+]]
+function SearchController.GetHoldFraction(): number?
+	local endsAt = holdEndsAt
+
+	if endsAt == nil then
+		return nil
+	end
+
+	local remaining = math.max(endsAt - os.clock(), 0)
+
+	return math.clamp(1 - remaining / Config.Search.SearchTime, 0, 1)
+end
+
+-- Player-facing copy lives on the client, the same rule `TeachingLines` follows: the payload carries
+-- an ItemType, never a sentence, so text never crosses the wire.
+local FOUND_LINES: { [string]: string } = {
+	SALT = "You found a pouch of salt.",
+	BAWANG = "You found bawang.",
+	BUNTOT_PAGI = "You found the buntot pagi.",
+}
+
+local function onUpdate(payload: Types.SearchUpdatePayload)
+	if payload.Verdict == "SEARCH_STARTED" then
+		holdEndsAt = os.clock() + payload.HoldSeconds
+		return
+	end
+
+	-- EVERY other verdict ends the hold. Listing them individually would mean a verdict added later
+	-- silently leaves a bar on screen forever.
+	holdEndsAt = nil
+
+	if payload.Verdict ~= "SEARCH_OK" then
+		--[[
+			REFUSALS ARE SILENT IN V03, deliberately. A line for each of six refusal reasons is copy
+			that has to be written, localised and tuned, and §4.4's loop is worth playtesting before
+			any of it is. V16 asks whether searching feels like survival or a chore; six error messages
+			are a good way to make it feel like a chore before anyone has answered that.
+		]]
+		if Config.Debug.VerboseLogging then
+			print(`[SearchController] {payload.Verdict}`)
+		end
+
+		return
+	end
+
+	local found = payload.Found
+
+	if found == nil then
+		-- §4.4: "You will open empty ones, and that is the point."
+		OnboardingController.ShowLine("Empty.")
+		return
+	end
+
+	OnboardingController.ShowLine(FOUND_LINES[found] or "You found something.")
+end
+
+function SearchController.Init()
+	holdEndsAt = nil
+end
+
+function SearchController.Start()
+	Remotes.Get("SearchUpdate").OnClientEvent:Connect(onUpdate)
+end
+
+return SearchController
```

**NOTE on `FOUND_LINES[found]`** — indexing a `{ [string]: string }` with an `ItemType` is fine (the
literal union is a subtype of `string`), and the `or` fallback exists because a table-value annotation
of `{ [string]: string }` gives no exhaustiveness guarantee. This is the same shape
`.claude/lessons/pure-module-unions-widen-in-lists.md` warns about in its "six failed fixes" list — a
`{ [string]: T }` lookup does **not** narrow — so do not try to use it as one.

#### Step 4.2: Bind the key, and register the action

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run check:remotes`

`E` held fires `RequestSearch` on `Begin` and `RequestCancelSearch` on `End`, through one function
registered with `UIController.BindActions` so the HUD and the key cannot drift — the bug
`InputController`'s own header records.

```diff
 local TRANSFORM_ACTION = "AswangTransform"
 local KILL_ACTION = "AswangKill"
 local THROW_ACTION = "SaltThrow"
+local SEARCH_ACTION = "SearchContainer"
```

```diff
+--[[
+	V03, §4.4. A HOLD RATHER THAN A PRESS, which is why this is a PAIR of functions where every other
+	verb in this file is one.
+
+	NOT GATED ON ROLE, and the absence of that gate is the design. `performTransform` and `performKill`
+	check `UIController.GetMyRole()` because they are Aswang verbs; searching is everyone's, and §4.4
+	is explicit that the Aswang searches on identical rules — rummaging in a house is blending
+	justified by mechanics. A gate here would make the monster's client behave differently from a
+	survivor's, which is Amendment A2's oracle in the one place nobody would look for it.
+
+	NEITHER SENDS AN ARGUMENT. The server resolves which container from this player's own character
+	position; naming one here would hand a compromised client a probe. See `Remotes.luau`.
+
+	NO CLIENT-SIDE GATE ON PHASE OR DISTANCE EITHER, unlike `performKill`'s role check. The server
+	answers with a verdict the controller can show, and a client-side pre-check would only ever
+	disagree with it — the client does not know `opened`, and cannot.
+]]
+local function performSearch(): boolean
+	Remotes.Get("RequestSearch"):FireServer()
+
+	return true
+end
+
+local function performCancelSearch(): boolean
+	Remotes.Get("RequestCancelSearch"):FireServer()
+
+	return true
+end
+
+--[[
+	`Begin` starts, `End` AND `Cancel` stop. Cancel matters: ContextActionService fires it when the
+	bind is unbound or the input is stolen — a chat box opening mid-hold — and treating it as anything
+	other than a release leaves a player holding a container they cannot let go of by any input.
+]]
+local function onSearchAction(
+	_actionName: string,
+	inputState: Enum.UserInputState
+): Enum.ContextActionResult
+	if inputState == Enum.UserInputState.Begin then
+		performSearch()
+
+		return Enum.ContextActionResult.Sink
+	end
+
+	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
+		performCancelSearch()
+
+		return Enum.ContextActionResult.Sink
+	end
+
+	return Enum.ContextActionResult.Pass
+end
```

In `Start`:

```diff
 	UIController.BindActions({
 		Transform = performTransform,
 		Kill = performKill,
 		Throw = performThrow,
+		--[[
+			V03. REGISTERED AS A PAIR because §4.4's verb is a hold, not a tap — the pad reports when
+			the thumb goes down and when it comes up, exactly as `BindQuickChat` does for the wheel's
+			press-drag-release. Registering only a `Search` would give a mobile player a way to start a
+			search and no way to stop one.
+
+			THE PAD DOES NOT DRAW A SEARCH BUTTON YET, and that is a real gap rather than a rounding
+			error: searching is the thing all five players do all round, and §5 puts ~60% of them on a
+			phone. It is exactly the hole `InputController`'s header describes closing for tasks, now
+			re-opened by the mechanic that replaced them. Raised in Follow Ups and it must not survive
+			past V16.
+		]]
+		Search = performSearch,
+		CancelSearch = performCancelSearch,
 	})
```

And beside the existing binds:

```diff
 	ContextActionService:BindAction(THROW_ACTION, onThrowAction, false, Enum.KeyCode.Q)
+	-- E, and `false` for the touch-button argument for the same reason every bind in this file passes
+	-- it: NO BIND HERE CREATES A TOUCH BUTTON. A CAS touch button appears for every client that runs
+	-- the bind, and the pad is the one thing in this game that places a touch control.
+	ContextActionService:BindAction(SEARCH_ACTION, onSearchAction, false, Enum.KeyCode.E)
```

**IMPORTANT — `UIController.ActionHandlers` must gain the two fields.** The type at
`src/client/Controllers/UIController.luau:249-253` is `{ Transform, Kill, Throw }`, so adding `Search`
and `CancelSearch` to the table literal without widening the type is an analyzer error. Add both as
`() -> ()` there. **I did not read `buildTouchPad`'s button construction closely enough to diff it**,
so this step widens the contract and wires the keys, and draws no button — see Follow Ups.

#### Step 4.3: Register both bootstraps

**File:** `src/server/init.server.luau`
**Verify:** `npm run verify`

`SearchService` into `SERVICE_ORDER` and `SearchController` into `CONTROLLER_ORDER`
(`src/client/init.client.luau`), each in a position that is a real dependency rather than a
preference.

**Second file in this step:** `src/client/init.client.luau`.

```diff
 	"RoleService",
 	"MonsterService",
 	"ItemService",
+	--[[
+		V03. AFTER ItemService and BEFORE RoundService, and only the second half is load-bearing.
+
+		Like every gameplay service here it holds a module reference from its own `require` at load,
+		and this list governs only Init/Start. What it must not do is start AFTER the state machine:
+		`RoundService` starts last precisely so every subscriber is connected before a phase can
+		change, and a SearchService that started afterwards could miss the STARTING that seeds its
+		layout — producing a round with a nil layout and no warning, because the EMPTY path is the
+		only one that warns and this would not take it.
+
+		It requires `AntiCheatService` and `RoundService` and neither requires it back, so no cycle.
+	]]
+	"SearchService",
 	"TrialService",
```

```diff
 	"OnboardingController",
+	--[[
+		V03. AFTER OnboardingController, and that ordering is a real dependency rather than a
+		preference: this controller REQUIRES it, for `ShowLine`. One-way, exactly as TrialController's
+		does — OnboardingController knows nothing about searching, so the arrow cannot become a cycle.
+
+		Before InputController for the same reason as everything else in this list: it listens for a
+		remote that can arrive the instant a key is pressed.
+	]]
+	"SearchController",
 	"TrialController",
 	"InputController",
```

#### Phase 4 — Potential Issues

After completing this phase, check for:

- **Secret leakage** — the client half. `SearchController` stores a deadline and a copy string, and
  nothing else. Confirm it never accumulates finds into a list, never records a position alongside a
  find, and never writes an attribute — a client-side map of "what I found where" is not a leak by
  itself, but it is the data structure an exploit would want and there is no reason to build it.
  `check:secrecy`'s rule 3 also fails any client file referencing `AswangUserId`; none does.
- **Remote direction** — this step's Verify (`check:remotes` at 4.2) is where the whole surface is
  finally exercised from both sides: the client fires two up-remotes and listens on one down-remote,
  the server does the mirror. A name mismatch here is the failure that hangs `WaitForChild` forever
  with no error, which is why the check exists.
- **Rate limiting** — no new server handler in this phase. Note the client fires `RequestSearch` on
  every `E` press with no local cooldown; that is deliberate (the server's budget is the authority and
  a client-side cooldown is not one) and it is what `RequestSearch`'s Capacity 4 was sized for.
- **Magic numbers** — none. `Config.Search.SearchTime` is read for the fraction; `Enum.KeyCode.E` is
  not a number.
- **Phase ownership** — untouched.
- **Player leaving mid-round** — client-side state dies with the client. Server-side cleanup is
  Phase 3's.
- **Strict Luau** — `payload.Found` arrives as `ItemType?` and is used to index a `{ [string]: string }`,
  which is a subtype relation and not a narrowing; the `or` fallback is what makes it total.
- **Mobile budget** — `GetHoldFraction` is pull-based and nothing calls it yet, so this phase adds
  **zero** per-frame work. When a HUD chunk draws the bar it should read it inside the existing
  `render` at `Round.SnapshotInterval` rather than on `RenderStepped`.
- **Scope** — nothing added.

**Issues identified:**

- **Mobile cannot search.** The actions are registered with `UIController.BindActions` but
  `buildTouchPad` draws four buttons and none of them is Search. Searching is the only activity in the
  game (§4.4) and §5 puts ~60% of players on a phone, so this is the same hole
  `InputController`'s header records closing for tasks — re-opened by the mechanic that replaced them.
  **Severity High**, carried to Follow Ups, and it must be closed before V16's playtest or that
  playtest cannot answer its third question for most of its players.
- **`E` is Roblox's conventional interact key and also the default `ProximityPrompt` key.** No prompt
  exists in this game today, so there is no conflict now. If the map ever gains one, `E` is bound here
  first and the prompt will look broken.
- **`performSearch` returns `boolean` while `ActionHandlers` fields are `() -> ()`.** Luau permits
  discarding return values, so this typechecks — and it keeps the pair consistent with
  `performTransform` and `performKill`, which the HUD path already treats this way.
- **Two more entries in the `ActionHandlers` contract that nothing draws.** A reviewer will read
  `CancelSearch` as unused. It is the half of the pair that makes a hold releasable on touch, and it
  is registered now so the pad chunk has both ends waiting for it.

## 3. Related Files

**Created**

| File | Phase | What it is |
| --- | --- | --- |
| `src/server/pure/ContainerLayout.luau` | 1.1 | The draw. Server-only, Lune-runnable, no Roblox datatypes |
| `tests/container-layout.test.luau` | 1.2 | 10,000 draws, two distribution bands, the SHORT boundary |
| `src/server/Services/SearchService.luau` | 3.1–3.3 | Pool, seed, hold, handlers |
| `src/client/Controllers/SearchController.luau` | 4.1 | The hold's deadline and the find's line |

**Modified**

| File | Phase | Change |
| --- | --- | --- |
| `src/shared/Config.luau` | 1.3, 2.3 | `Search.RangeStuds`; two `AntiCheat.Budgets` entries |
| `tests/config.test.luau` | 1.3 | Three assertions — pool ratio, hold duration, radius floor |
| `src/shared/Types.luau` | 2.1 | `SearchVerdict`, `SearchUpdatePayload` |
| `src/shared/Remotes.luau` | 2.2 | `SearchUpdate` down; `RequestSearch`, `RequestCancelSearch` up |
| `tests/anti-cheat-budgets.test.luau` | 2.3 | Two `UP_REMOTES` entries |
| `src/client/Controllers/InputController.luau` | 4.2 | `E` bind, the action pair, the registration |
| `src/client/Controllers/UIController.luau` | 4.2 | `ActionHandlers` widened by two fields |
| `src/server/init.server.luau` | 4.3 | `SearchService` into `SERVICE_ORDER` |
| `src/client/init.client.luau` | 4.3 | `SearchController` into `CONTROLLER_ORDER` |

**Read, unmodified, reviewed in `references/`** — `SearchPool.luau`, `RoleDraw.luau`,
`RoundService.luau`, `ItemService.luau`, `AntiCheatService.luau`, `Enums.luau`, `Config.luau`,
`Types.luau`, `Remotes.luau`, `init.server.luau`, `InputController.luau`.

**The map, which is not code.** This plan adds a **tag contract** and nothing more:
`Config.Search.ContainerCount` (15) anchored `BasePart`s, each tagged `SearchContainer` via
`CollectionService`, each with a **unique `Name`** — duplicates are dropped by
`SearchPool.evaluate` and warned about. Placement is §4.4's ("across the bahay kubo, the chapel and
the well area — sacks, cabinets, under the papag"). "Build the containers" is not a step in this plan
and cannot be verified by one; the greybox path is covered by the `SHORT`/`EMPTY` handling instead, so
the code lands and runs before the map catches up.

## 4. Follow Ups

### Questions / Clarifications

1. **Does the Aswang keep what it finds?** V03 grants nothing so the question does not arise yet, but
   V08 must answer it. §4.4 says denying survivors the buntot pagi is a legitimate strategy that looks
   exactly like survival, which implies the monster *can* hold items. The trap is the shape of the
   answer, not the answer: if the Aswang's client renders a carry slot differently, or a found item
   behaves differently in its hands, that is Amendment A2's oracle. **Whatever V08 decides, the
   observable behaviour of finding and holding must be identical for both roles.**
2. **`Search.RangeStuds = 10` against `Monster.KillRange = 8` is a guess, not a derivation.** It says
   "a searcher stands roughly where the monster can reach them", which is the §4.4 trade. It is
   pinned only by a `> 0` floor, because I could not find a relationship that is true rather than
   merely plausible. V16 should look at it with real players.
3. **The `>= 2 ×` pool ratio passes at 15 ≥ 14, with one container of margin.** Deliberately tight
   (the reasoning is in the diff), but it means any V16 tune that raises an item count fails
   `tests/config.test.luau` and needs a map change to clear. That is the intended behaviour and it
   will still be surprising the first time it happens.
4. **`tests/anti-cheat-budgets.test.luau`'s `UP_REMOTES` is a hand copy of `Remotes.EVENTS_UP`, and
   this plan adds two more entries to it.** That file's own header names the clean fix — a check script
   parsing both — and defers it. Deferred again here for the same reason: V03 is not the chunk that
   should be growing the harness. The gap is now 13 hand-copied names.
5. **Two Roblox behaviours I did not verify, flagged rather than assumed.** (a)
   `ContextActionService` firing `Enum.UserInputState.Cancel` when a bind is unbound or input is
   stolen — the diff handles it defensively, so being wrong costs nothing, but I have not confirmed
   it in this codebase and no existing bind here handles a hold. (b) `bit32` availability under this
   repo's pinned Lune. `bit32` is standard Luau and I expect it, but if Step 1.2 errors on it, replace
   the xorshift with a `%`-based LCG using constants under 2^26 so the products stay exact in a
   double — **do not** substitute `math.random`, which would give up the hermetic seed the bands
   depend on.
6. **For one chunk there are two salt stories in the tree.** `ItemService` still spawns pouches at
   `SaltSpawn` points every `STARTING` (v1.3, live, and `Config.Salt.PouchPoolSize` still expects six
   of them), while V03 seeds salt into containers and grants nothing. Both run. That is a real
   inconsistency and it is **V08's to resolve, not V03's**: V01 was the demolition chunk and V08 is
   the rebuild, and a service half-rewritten by a chunk that does not own it is the worst of both.
   V03 must not start deleting `spawnPouches`.
7. **"Empty." goes on the onboarding hint label**, which is the surface that teaches new players. A
   routine several-times-a-minute outcome may wear it out or make genuine teaching cues invisible by
   association. Cheap to change; watch for it at V16.
8. **`ClientRoundSnapshot` is not widened by this plan**, and `YourCarriedItem` still has no producer.
   V02 left it that way deliberately and V08 is the chunk that wires it. If a future step wants the
   snapshot to carry *anything* about searching — a count, a "you are searching" flag — that is a
   contract change to argue in a plan, not a field to add.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 4 | **Mobile cannot search.** The actions are registered with `UIController.BindActions`, but `buildTouchPad` draws Transform/Kill/Say/Salt and no Search. Searching is the only activity in the game and §5 puts ~60% of players on a phone. This is the hole `InputController`'s header records closing for tasks, re-opened by the mechanic that replaced them | **High** | Open — must close before V16 or that playtest cannot answer its third question for most of its players |
| 3 | The Aswang can find the buntot pagi and V03 grants nothing, so nothing happens. V08 must decide, and must make both roles' behaviour identical | Medium | Open — V08 |
| 1 | `Config.Search.NoiseRadius` exists and V03 reads it nowhere. Searching is silent until V04 | Medium | Open by design — V04 owns noise, and §4.4 calls it "the entire risk economy", so V03 alone is not §4.4 |
| 3 | `foundByPlayer` is written and read by nothing in V03. Will read as dead code to a reviewer | Low | Open — intentional; it is V08's read surface and the playtester's evidence |
| 2 | `SearchUpdate`'s payload could grow a container id "for the HUD" at any later chunk, and nothing mechanical would stop it — `check:secrecy` only enforces payload fields on the two allowlisted reveal remotes | Low | Documented in `Types.luau`'s absent-field list, which is the only stop |
| 3 | `nearestContainer` resolves exact ties by hash order, which is undefined | Low | Deliberate — a deterministic tie-break would be a rule a client could exploit to target a chosen container |

### What this plan does NOT build

Named explicitly, because a reader finishing V03 will reasonably expect some of it:

- **Noise.** V04. This is the larger half of §4.4 and its absence means V03 ships the *cost* of
  searching without the *risk*. Do not judge the loop's feel until V04 lands.
- **Items you can hold, carry or use.** V08. V03 tells the finder what they found and records it.
- **A container that looks searched.** No animation, no open lid, no attribute — the visible tell rides
  with V04's noise, and V03 deliberately writes nothing public so that the secrecy answer stays
  "nothing about searching reaches a second client".
- **A search bar on the HUD.** `SearchController.GetHoldFraction()` exists and nothing calls it.
- **The map.** Fifteen tagged parts, per the contract in §3 above.
