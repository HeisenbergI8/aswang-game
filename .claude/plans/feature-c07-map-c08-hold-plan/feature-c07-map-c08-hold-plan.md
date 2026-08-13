# Plan: C07's map half and C08 — the Hold task

## 1. Plan Overview

- **Plan Type:** feature
- **Milestone:** M3 (C07 map half, C08)
- **Description:** Six phases. Phases 1–2 finish C07: a `TaskPoint` pool discovered by
  CollectionService tag, a pool-health verdict that makes an empty map loud, a `Random.new()` created
  once on the server with no argument, and the 5-of-12 draw run at `STARTING` with the chosen set held
  as `TaskService` state. Phases 3–5 build C08: server-timed hold accumulation over a pure module, a
  `RequestTaskProgress` handler that takes **no arguments** and re-derives everything from server
  state, and a per-player `TaskProgressChanged` that carries the global bar plus the progress of the
  one task point the receiving player is standing at. Phase 6 adds the ProximityPrompt affordance in
  isolation, because no ProximityPrompt exists anywhere in this repository and its event behaviour is
  unconfirmed.
- **Date:** 2026-08-12
- **What the client is told:** three new facts, and one of them is deliberately per-player.
  1. **`TaskProgressChanged`** — `{ TasksCompleted, TasksRequired, YourTaskProgress: number? }`, fired
     with `FireClient`, never `FireAllClients`. The first two fields are identical for every player and
     already exist on `RoundSnapshot`. The third is the 0..1 fill of the task point **this** player is
     currently standing at, and `nil` for everyone who is not standing at one.
  2. **Which five of the twelve are live**, via a replicated CollectionService tag `ActiveTaskPoint` on
     the chosen parts. This is public **by design** — players must be able to find tasks — and §1.3
     explains why "the chosen set is server state" does not mean "the chosen set is a secret".
  3. **`RoundSnapshot.TasksCompleted`** already exists and now actually moves. C01 built it that way.

  `ClientRoundSnapshot` gains **no** field. `RoundEnded` gains no field. `RoleAssigned` gains no field.
  `check-secrecy.mjs`'s `REVEAL_ALLOWLIST` is not touched. No new remote is declared — both remotes
  this plan uses are already in `Remotes.luau`.

### 1.1 What is deliberately NOT in this plan

- **C09 (Timing, Fetch) and C10 (Two-person).** No `TaskType` branch is written for them. Phase 2 reads
  a `TaskType` attribute off each anchor and defaults it to `HOLD`, which is the *only* concession made
  to them: it is one line, it costs nothing, and without it C09 has to revisit discovery.
- **C11 — the escape gate and the survivors' win.** `RoundState.GateOpen` is **not written by this
  plan**. At 5/5 the counter reads 5/5 and nothing else happens; the round still ends on the sunrise
  timer or on C06's attrition win. That is a runnable, honest intermediate state and it keeps the gate's
  ownership with the chunk that is named for it.
- **C12 — the Aswang's fake task list.** Nothing is built for it. §1.4 records the two design decisions
  that keep it cheap, and both were made for C08's own reasons.
- **C17 — the greybox.** Phase 2.1 places a **disposable** test rig so C08 is verifiable at all. It is
  not the greybox, it is not a deliverable, and C17 deletes it wholesale.
- **Nothing from spec §3's OUT list.**

### 1.2 The one thing this plan changes about an existing service

`RoundService` gains exactly one public function, `SetTasksCompleted`, and loses one stale TODO. It does
**not** learn to require `TaskService`, and that is a deliberate reversal of the seam comment at
`RoundService.luau:578`. See Step 3.4 — the direction matters enough that getting it backwards is a
require cycle, which `init.server.luau` swallows into a single `warn` and which looks in-game exactly
like "nobody has joined yet".

### 1.3 "The chosen set is server state" — what that does and does not mean

C07's brief says the chosen set is server state. It is, in the sense that matters: **the server decides
it, and no client can predict it or extend it.** That is what the seed warnings in both
`TaskService.luau`'s header and `TaskSelection.luau`'s header are protecting, and this plan honours them
exactly — one `Random.new()`, no argument, created once, never sent.

It is **not** a secret. Five ProximityPrompts appear on five parts and every player can see them; that
is the game working. A plan that tried to hide the selection would be hiding the objective from the
people who have to complete it. What must never happen is a client knowing the selection *before*
`STARTING` resolves, or being able to derive the *next* round's selection from this one's — and both of
those are properties of the RNG, not of the tag.

### 1.4 Two decisions made for C08 that happen to make C12 cheap

Neither is speculative work; both are required by C08's own secrecy constraint (§4 risk R1).

1. **Hold progress does not scale with the number of people present.** The rate is the **maximum**
   contributor weight, never the sum. Three survivors on one task finish it in exactly `HoldTime`, the
   same as one. This exists so that at C12 an Aswang standing on a task with a survivor changes *nothing
   a third party can observe* — with a summed rate, the bar would visibly slow whenever the monster
   "helped", which is a role oracle readable by anyone watching the bar.
2. **`TaskProgressChanged` is fired per player, not broadcast.** Fractional per-task progress reaches
   only the player standing on that task. Without this, a survivor who can see who is standing at task 3
   and can also see task 3's bar frozen has identified the Aswang the moment C12 zeroes its weight.
   The per-player shape means C12 can lie to exactly one client without touching anyone else's payload.

## 2. Comprehensive Plan by Phases

### Phase 1: The types, the pool verdict, and the Config knobs

Everything in this phase is provable from a terminal. No Roblox API is touched.

#### Step 1.1: Declare the three new types

**File:** `src/shared/Types.luau`
**Verify:** `npm run verify:fast`

`TaskPoolVerdict`, `TaskProgressVerdict` and `TaskProgressPayload`, following the `KillVerdict` /
`PlayerKilledPayload` precedent — a literal union so a refusal can be logged with a reason, and a typed
payload local for the one thing that crosses the wire.

Inserted directly above `-- SERVER ONLY. Never send this table to a client.`

```diff
+--[[
+	The verdict from `server/pure/TaskPool.luau` (C07) — is the map's TaskPoint pool usable.
+
+	EMPTY and SHORT are the two that BLOCK a draw. DUPLICATE_ID and OVERSIZED are loud and
+	non-blocking: the round still runs, and the map still has a defect somebody has to fix. That split
+	is why this is a union rather than a boolean — "unusable" and "usable but wrong" send a reader to
+	two different places, and a boolean would collapse them into a shrug.
+
+	This one is SAFE TO LOG AND SAFE TO SHOW. It describes the map, not a player, and every fact in it
+	is readable off the workspace by any client that cares to count tagged parts.
+]]
+export type TaskPoolVerdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"
+
+--[[
+	Why the server refused a RequestTaskProgress. Same shape and same rule as KillVerdict: a union so
+	the server can log WHY, and NEVER echoed to any client.
+
+	The echo rule is not inherited caution here, it is the specific hazard C08 has to design around.
+	C12 adds a sixth value — the Aswang's contribution does not count — and echoing that value would
+	be a role oracle any client could read by standing on a task and listening. There is no safe
+	subset to return, so the handler returns NOTHING on every refusal, exactly as the kill does.
+
+	NO_TASK_IN_RANGE covers both "you are nowhere near one" and "that point is not one of this round's
+	five". They are deliberately the same value: distinguishing them would tell a client which of the
+	twelve are live faster than walking there would.
+]]
+export type TaskProgressVerdict =
+	"OK"
+	| "WRONG_PHASE"
+	| "NOT_ALIVE"
+	| "NO_TASK_IN_RANGE"
+	| "ALREADY_COMPLETE"
+
+--[[
+	The task bar (§4.4, C08). THREE FIELDS, AND THE THIRD IS THE ONE WITH A DESIGN BEHIND IT.
+
+	It does NOT carry who did what — not a UserId, not a name, not a count of who is present. §4.4 says
+	"a global task bar shows overall progress (not who did what)" and this payload is that sentence.
+
+	`YourTaskProgress` is the 0..1 fill of the ONE task point the receiving player is standing at, and
+	nil for everyone else. That is why this remote is fired with FireClient per player and never with
+	FireAllClients, and the reason is a leak rather than a saving: a survivor who can see who is
+	standing at task 3 AND can see task 3's bar frozen has identified the Aswang the moment C12 zeroes
+	its weight. Per-task fractional progress reaching a bystander is that leak; reaching only the
+	person standing on it is not.
+
+	READ THE RoundEndedPayload COMMENT ABOVE BEFORE ADDING A FIELD. An EXTRA field on an annotated
+	table is accepted silently by the typechecker, and `TaskProgressChanged` is not on
+	check-secrecy.mjs's REVEAL_ALLOWLIST — so its broadcast rule DOES run over this call, which catches
+	a field named `role` or `aswang` or `killer` and catches nothing else. A field named
+	`PresentPlayerCount` would pass every check in this repo and would still be the oracle above.
+]]
+export type TaskProgressPayload = {
+	TasksCompleted: number,
+	TasksRequired: number,
+	YourTaskProgress: number?,
+}
+
 -- SERVER ONLY. Never send this table to a client.
 export type RoundState = {
```

**`ActiveTask` is not changed.** It already carries `Id`, `Type`, `SpawnPointName`, `Progress` and
`Completed`, which is the whole of what Phase 3 needs. Resisting the urge to add `Position` to it is
deliberate: the position lives on the anchor part, the anchor part is what the server measures against,
and a copy of a position in a second place is a copy that goes stale when C17 moves the greybox.

#### Step 1.2: `src/server/pure/TaskPool.luau` — is this map's pool usable

**File:** `src/server/pure/TaskPool.luau`
**Verify:** `npm run analyze`

A pure function over a plain list of discovered point names returning a verdict. This is what makes "no
`TaskPoint` in the map" loud instead of silent, and putting the decision in a pure module is what makes
"loud" testable rather than asserted.

```diff
+--!strict
+--[[
+	TaskPool — is this map's TaskPoint pool usable, and which names are actually distinct? (C07)
+
+		(names, required, expected) -> report
+
+	WHY THIS IS A MODULE AND NOT AN `if #pool == 0 then warn()` IN THE SERVICE.
+
+	The stub this chunk replaces refused to ship discovery for one stated reason: a service whose only
+	observable behaviour is finding an empty pool is indistinguishable from a broken one. A warn() does
+	not fix that — a warn is only as good as somebody reading the output window on the one run where it
+	fires, and the run where it fires is the run where nothing else is working either. Making the
+	verdict a pure function makes "the pool is empty" something a test asserts from a terminal. That is
+	the difference between loud and merely noisy.
+
+	WHY src/server/pure/ AND NOT src/shared/pure/ — deliberately the opposite of TaskSelection next
+	door. TaskSelection sits under shared/ and its header spends twenty lines earning the right to,
+	because a client can require AND CALL anything under ReplicatedStorage. Nothing here needs that
+	argument re-run: the client renders what the server sends and has no use for a pool verdict, and
+	the inputs are the pool contents themselves — the exact thing TaskService's seed warning says to
+	keep off the wire. Lune resolves by file path, so none of this costs testability. RoleDraw is here
+	for the same reason.
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes: names are plain strings so Lune can run this.
+	The verdict union is re-declared locally; Luau unions are structural, so this type and
+	Types.TaskPoolVerdict are the same type and pass to each other without a cast.
+]]
+
+export type Verdict = "OK" | "EMPTY" | "SHORT" | "DUPLICATE_ID" | "OVERSIZED"
+
+export type Report = {
+	Verdict: Verdict,
+	Unique: { string },
+	Duplicates: { string },
+}
+
+local TaskPool = {}
+
+--[[
+	PRECEDENCE IS BLOCKING-FIRST, and the order is the whole content of this function.
+
+		EMPTY        no usable point at all — the map has no TaskPoint tags, or every one is a dupe
+		SHORT        fewer distinct points than TotalRequired — the gate could never reach 5/5
+		DUPLICATE_ID enough points, but two share a Name — the server cannot tell them apart
+		OVERSIZED    more points than PoolSize expects — harmless, and a sign C17 left one behind
+		OK
+
+	SHORT OUTRANKS DUPLICATE_ID on purpose. Both are map defects; only one of them means the round is
+	unwinnable. A reader who sees DUPLICATE_ID and fixes a name, then discovers the pool was also two
+	points short, has been sent to the second-most-urgent problem first.
+
+	`Duplicates` is returned on EVERY path, including OK, because the caller wants to name the offending
+	parts in its log regardless of whether they blocked anything. `Unique` preserves discovery order,
+	which is `GetTagged`'s order — see Step 2.2 for why the caller sorts it before drawing.
+]]
+function TaskPool.evaluate(names: { string }, required: number, expected: number): Report
+	local seen: { [string]: boolean } = {}
+	local unique: { string } = {}
+	local duplicates: { string } = {}
+
+	for _, name in names do
+		if seen[name] then
+			table.insert(duplicates, name)
+		else
+			seen[name] = true
+			table.insert(unique, name)
+		end
+	end
+
+	local count = #unique
+	local verdict: Verdict = "OK"
+
+	if count == 0 then
+		verdict = "EMPTY"
+	elseif count < required then
+		verdict = "SHORT"
+	elseif #duplicates > 0 then
+		verdict = "DUPLICATE_ID"
+	elseif count > expected then
+		verdict = "OVERSIZED"
+	end
+
+	return { Verdict = verdict, Unique = unique, Duplicates = duplicates }
+end
+
+return TaskPool
```

**`npm run analyze` is the check because this is a new file under `--!strict`**, and the failure this
module is most likely to ship with is the one `Enums.luau` warns about: `local verdict = "OK"` infers as
plain `string` and then fails to satisfy the `Verdict` field. The `: Verdict` annotation on the local is
what makes the reassignments below it legal, and removing it is an analyze error rather than a runtime
one.

#### Step 1.3: `tests/task-pool.test.luau` — every verdict boundary

**File:** `tests/task-pool.test.luau`
**Verify:** `lune run tests/task-pool.test.luau`

Empty, short, exact, oversized, and duplicate-name pools. The empty case is the one that exists for
constraint 4 and it is asserted first.

```diff
+--!strict
+--[[
+	The pool verdict, at every boundary. C07's map half.
+
+	THE FIRST ASSERTION IS THE POINT OF THE WHOLE FILE. "The map has no TaskPoints" is the failure this
+	repo has actually been living with — Workspace is an empty baseplate — and the stub's author was
+	right that a service which can only report it silently is not worth shipping. This test is what
+	turns that report into something a terminal can fail on.
+
+	Boundaries rather than samples: required-1, required, expected, expected+1. Every off-by-one in
+	`evaluate` lands on one of those four and on nothing else.
+]]
+
+local TaskPool = require("../src/server/pure/TaskPool")
+
+local REQUIRED = 5
+local EXPECTED = 12
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+local function names(count: number): { string }
+	local list = {}
+
+	for i = 1, count do
+		table.insert(list, `TaskPoint_{i}`)
+	end
+
+	return list
+end
+
+-- The reason this module exists. An untagged map must be reported, not shrugged at.
+local empty = TaskPool.evaluate({}, REQUIRED, EXPECTED)
+
+check("an empty pool is EMPTY", empty.Verdict == "EMPTY", empty.Verdict)
+check("an empty pool has no unique points", #empty.Unique == 0)
+
+-- One below the gate's requirement: the round could never reach 5/5, so this must block.
+local short = TaskPool.evaluate(names(REQUIRED - 1), REQUIRED, EXPECTED)
+
+check("a pool one short of the requirement is SHORT", short.Verdict == "SHORT", short.Verdict)
+
+-- Exactly enough is fine. The draw returns all of them and the spacing filter falls back; that is
+-- TaskSelection's contract, already proven in tests/task-selection.test.luau.
+local exact = TaskPool.evaluate(names(REQUIRED), REQUIRED, EXPECTED)
+
+check("a pool of exactly the requirement is OK", exact.Verdict == "OK", exact.Verdict)
+
+local full = TaskPool.evaluate(names(EXPECTED), REQUIRED, EXPECTED)
+
+check("the intended 12-point pool is OK", full.Verdict == "OK", full.Verdict)
+check("the intended pool keeps all 12", #full.Unique == EXPECTED, `{#full.Unique}`)
+
+-- Non-blocking, but a defect: C17 left a thirteenth tag somewhere.
+local oversized = TaskPool.evaluate(names(EXPECTED + 1), REQUIRED, EXPECTED)
+
+check("a pool larger than PoolSize is OVERSIZED", oversized.Verdict == "OVERSIZED", oversized.Verdict)
+
+--[[
+	Two parts with one Name. The server identifies a task point by Name, so this is the map defect that
+	would otherwise surface as a task completing itself at the wrong end of the barrio.
+]]
+local duplicated = names(EXPECTED)
+
+table.insert(duplicated, "TaskPoint_3")
+
+local dupes = TaskPool.evaluate(duplicated, REQUIRED, EXPECTED)
+
+check("a repeated Name is DUPLICATE_ID", dupes.Verdict == "DUPLICATE_ID", dupes.Verdict)
+check("the duplicate is named for the log", dupes.Duplicates[1] == "TaskPoint_3")
+check("the duplicate is counted once", #dupes.Unique == EXPECTED, `{#dupes.Unique}`)
+
+--[[
+	SHORT OUTRANKS DUPLICATE_ID. Four distinct names and a repeat is still an unwinnable round, and a
+	reader sent to fix the name first would fix the wrong thing. This assertion is the precedence rule
+	from the module header, pinned.
+]]
+local shortAndDuplicated = names(REQUIRED - 1)
+
+table.insert(shortAndDuplicated, "TaskPoint_1")
+
+local both = TaskPool.evaluate(shortAndDuplicated, REQUIRED, EXPECTED)
+
+check("a short pool reports SHORT even when it also has duplicates", both.Verdict == "SHORT", both.Verdict)
+check("the duplicate is still reported alongside it", #both.Duplicates == 1)
+
+-- A pool of nothing but the same name is EMPTY of usable points, not DUPLICATE_ID.
+local allSame = TaskPool.evaluate({ "A", "A", "A" }, REQUIRED, EXPECTED)
+
+check("a pool of one repeated name is SHORT, not OK", allSame.Verdict == "SHORT", allSame.Verdict)
+check("it keeps exactly one", #allSame.Unique == 1)
+
+if failures > 0 then
+	error(`{failures} task-pool assertion(s) failed`, 0)
+end
+
+print("  PASS  task-pool: 14 assertions across 8 pools")
```

**This check can fail for a real reason and did during planning**: the last pair is the one that catches
a `#names` written where `#unique` was meant. A pool of three identical names has three entries and one
usable point, and an implementation that counts the input reports `OK` on a map with one anchor in it.

#### Step 1.4: The presence knobs, and the three invariants that bind them

**File:** `src/shared/Config.luau` + `tests/config.test.luau`
**Verify:** `lune run tests/config.test.luau`

Three new tunables under `Config.Tasks`, and three new pinned relationships — including the one that
makes Phase 4's zero-argument remote *correct* rather than merely tidy.

```diff
 		MinSpacingStuds = 20,
+
+		--[[
+			How close a player must be to a selected task point for the server to count them present.
+
+			IT MUST BE UNDER HALF `MinSpacingStuds`, and that is a CORRECTNESS constraint, not a tidiness
+			one. `RequestTaskProgress` takes no arguments (Step 4.1): the server decides which task point
+			the player is at by finding one in range of their own character. If two selected points could
+			be in range at once, "which one" stops having an answer, and the only way back is to let the
+			client name it — the client-supplied value this whole design exists to avoid. The draw
+			guarantees the spacing; this number is the half of the pair that can be tuned wrong.
+
+			It is also the distance at which a player is safe to stand still, which is the Aswang's
+			whole opportunity (§4.4, "forces you to stand still and vulnerable"). Tuning it up makes
+			tasks safer; that is an M12 conversation, not a correctness one.
+		]]
+		PresenceRangeStuds = 9,
+
+		--[[
+			How long one presence heartbeat stays valid. A player holding continuously must never fall
+			out of the window between two heartbeats, so this has to exceed `HeartbeatInterval` with room
+			to spare — the interval is a client-side timer, on a phone, over the same connection that is
+			already carrying a snapshot twice a second.
+
+			It is short deliberately. It is the window in which a player who has walked away still
+			counts, and Step 3.3 closes most of that hole a second way by re-measuring distance on every
+			server tick rather than trusting the stamp.
+		]]
+		PresenceGraceSeconds = 0.75,
+
+		-- How often a HOLDING client reports presence. Its reciprocal must stay under
+		-- AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond, or an honest client rate-limits itself
+		-- for doing exactly what the game asked of it — the failure that budget's own comment warns
+		-- about. 4/s against a refill of 6/s leaves headroom for a retry after a dropped packet.
+		HeartbeatInterval = 0.25,
 	},
```

Then the three invariants, appended to `tests/config.test.luau` above its `if failures > 0` block:

```diff
+--[[
+	Spec §4.4 and Step 4.1. `RequestTaskProgress` carries no arguments, so the server resolves which
+	task point a player is at from their position alone. Two selected points are guaranteed to be
+	MinSpacingStuds apart; if the presence radius reached more than half that, a player could stand
+	inside two of them and the resolution would be a coin toss the server has no right to make.
+]]
+check(
+	"a player can only ever be present at one task point at a time",
+	Config.Tasks.PresenceRangeStuds * 2 < Config.Tasks.MinSpacingStuds,
+	`PresenceRangeStuds={Config.Tasks.PresenceRangeStuds}, MinSpacingStuds={Config.Tasks.MinSpacingStuds}`
+)
+
+-- A holding player must not blink out of presence between two heartbeats, or an 8-second hold becomes
+-- a stutter of accumulation with gaps in it and the task takes visibly longer than HoldTime.
+check(
+	"a continuously held task never lapses between heartbeats",
+	Config.Tasks.PresenceGraceSeconds > Config.Tasks.HeartbeatInterval * 2,
+	`Grace={Config.Tasks.PresenceGraceSeconds}, Heartbeat={Config.Tasks.HeartbeatInterval}`
+)
+
+--[[
+	The honest client must fit inside its own budget. C02's comment on RequestTaskProgress already says
+	the budget "must out-pace the snapshot tick or a player holding a task is throttled while doing
+	exactly what the game asked of them" — this is that sentence, pinned against the number that
+	actually drives the sends.
+]]
+check(
+	"a holding client stays inside its own rate-limit budget",
+	Config.Tasks.HeartbeatInterval > 0
+		and 1 / Config.Tasks.HeartbeatInterval < Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond,
+	`{1 / Config.Tasks.HeartbeatInterval}/s vs refill={Config.AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond}/s`
+)
+
 if failures > 0 then
 	error(`{failures} balance invariant(s) violated`, 0)
 end
 
-print("  PASS  config: 26 balance invariants")
+print("  PASS  config: 29 balance invariants")
```

**The count in that final `print` is not decoration.** It is the only thing in the file that notices an
assertion silently deleted during a merge, and leaving it at 26 while adding three is the small lie that
makes it useless.

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

- **A type cannot enforce a send shape.** `TaskProgressPayload` is only per-player because Step 4.2
  fires it with `FireClient`. Nothing in `Types.luau` stops a later author reaching for
  `FireAllClients` with the same annotated table, and `check-secrecy.mjs` would not object — none of
  the three field names carries a secret token. Recorded as risk R1 in §4.
- **Strict Luau, the `Enums.luau` failure.** `local verdict = "OK"` infers as plain `string` and then
  fails to satisfy `Report.Verdict`. The `: Verdict` annotation on the local is load-bearing; six of
  the scaffold's seven original analyze errors were this exact shape.
- **`check:config` does not govern `src/shared/`**, so adding the three knobs is unpoliced in both
  directions: nothing forces a service to read them rather than retype `0.25`. Phases 2–5 are where
  that is actually enforced, by `npm run check:config` on the files that use them.
- **No §6.4 edge case applies to this phase.** Nothing here observes a player.

### Phase 2: The test rig, pool discovery, and the draw

This is C07's map half. It ends with five parts tagged `ActiveTaskPoint` at `STARTING` and nothing else.

#### Step 2.1: Place the disposable `TaskPoint` rig in Studio

**File:** `.claude/plans/feature-c07-map-c08-hold-plan/artifacts/task-rig.md`
**Verify:** `test -f .claude/plans/feature-c07-map-c08-hold-plan/artifacts/task-rig.md`

Twelve grey anchored parts, tagged `TaskPoint`, uniquely named, spaced far enough apart that
`MinSpacingStuds` is genuinely exercised. Executed by the main agent through Studio MCP; the deliverable
is the written record, because the place file is gitignored.

**THIS RIG IS DISPOSABLE AND IT IS NOT C17.** It is twelve grey pads on a baseplate so that C08 has
something to stand on. C17's greybox — the barrio, the chapel, the treeline — remains the user's job and
replaces this wholesale. Everything below lives in one folder for exactly that reason: deleting
`workspace.TaskRig_TEMP` deletes the entire rig and nothing else. None of it is in Git; the place file is
gitignored, which is also why the artifact, not the rig, is this step's deliverable.

**No Script or LocalScript is created inside Studio.** `guard-studio-sync.mjs` refuses that and is right
to — Rojo would overwrite it on the next sync with no error and nothing on disk to recover. Parts,
attributes and tags only, applied by executing code, not by storing it.

Run through `execute_luau`:

```luau
local CollectionService = game:GetService("CollectionService")

local existing = workspace:FindFirstChild("TaskRig_TEMP")

if existing then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = "TaskRig_TEMP"
folder.Parent = workspace

-- A 4x3 grid at a 30-stud pitch. Every pair is at least 30 apart, comfortably clear of
-- Config.Tasks.MinSpacingStuds (20), so the draw's spacing filter never has to fall back in-game.
-- The REJECTION path is already proven purely — tests/task-selection.test.luau draws from twelve
-- points stacked in one room and asserts the fallback fills the round anyway — so the rig does not
-- need to reproduce it, and a rig that did would make every other observation harder to read.
local X = { -45, -15, 15, 45 }
local Z = { -30, 0, 30 }
local index = 0

for _, z in Z do
	for _, x in X do
		index += 1

		local pad = Instance.new("Part")
		pad.Name = string.format("TaskPoint_%02d", index)
		pad.Size = Vector3.new(4, 1, 4)
		pad.Position = Vector3.new(x, 0.5, z)
		pad.Anchored = true
		pad.BrickColor = BrickColor.new("Medium stone grey")
		pad.Material = Enum.Material.Concrete
		pad.Parent = folder

		CollectionService:AddTag(pad, "TaskPoint")
	end
end

-- ONE pad carries the attribute explicitly; the other eleven do not. That is the point: Step 2.3's
-- reader defaults an absent TaskType to HOLD, and a rig where every pad states it would never
-- exercise the default that the whole map is going to rely on.
folder.TaskPoint_01:SetAttribute("TaskType", "HOLD")

print(`[Rig] {index} TaskPoint pads under {folder:GetFullName()}`)
```

**Three things go in the artifact, and the second is the one this plan owes constraint 4:**

1. The output of the snippet above, and a `screen_capture` of the twelve pads.
2. **The empty-pool proof.** Delete `TaskRig_TEMP`, restart the server, and record the console verbatim.
   `TaskService` must say — loudly, unconditionally, and by name — that there are no `TaskPoint` parts.
   A run where the output window is silent is a failed step, not a clean one, and this is the only place
   in the plan where that failure is observable in the real engine rather than in Lune.
3. **The duplicate-name proof.** Rename `TaskPoint_07` to `TaskPoint_06`, restart, record the warning,
   rename it back. Thirty seconds, and it is the difference between believing `DUPLICATE_ID` reaches an
   operator and knowing it.

#### Step 2.2: `TaskService` — discovery, the verdict, and the one `Random.new()`

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run analyze`

Replace the stub's body while keeping its header. Discovery by `CollectionService:GetTagged("TaskPoint")`,
name-uniqueness enforced, the pool verdict logged unconditionally, and the RNG created once as a
server-side local.

**Keep the stub's header, minus its TODOs.** Its seed section is the load-bearing part of this chunk and
it is already correct; the C17 TODO under it is what this step discharges.

```diff
-local TaskService = {}
-
--- TODO(C17): discover the pool by CollectionService tag `TaskPoint`, then call
--- TaskSelection.select(pool, Config.Tasks.TotalRequired, Config.Tasks.MinSpacingStuds, nextFloat)
--- from RoundService's STARTING handler.
--- TODO(M3): implement the 4 task types (Hold, Timing, Fetch, TwoPerson).
--- TODO(M3): validate progress server-side (proximity + rate). Open the gate at 5/5.
--- The Aswang sees a fake task list; its progress must never count.
-
-function TaskService.Init() end
-
-function TaskService.Start() end
+-- TODO(C09/C10): Timing, Fetch and TwoPerson. Step 2.3 reads the TaskType attribute and warns on
+-- anything that is not HOLD, so an anchor asking for one is visible rather than silently mishandled.
+-- TODO(C12): the Aswang sees a fake task list and its progress must never count. See §1.4 of the plan
+-- this file was built from: TaskProgressChanged is per-player and the rate is a MAX, both so that
+-- zeroing the Aswang's weight stays invisible to every other client.
+
+local CollectionService = game:GetService("CollectionService")
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Enums = require(Shared.Enums)
+local Remotes = require(Shared.Remotes)
+-- ONE DIRECTION ONLY, and this is the direction. RoundService must NEVER require TaskService back:
+-- a require cycle errors at load, init.server.luau swallows it into a single warn, and the server sits
+-- in IDLE forever looking exactly like "nobody has joined yet". MonsterService already sits on this
+-- side of the same rule; Step 3.4 deletes the stale TODO that pointed the other way.
+local RoundService = require(script.Parent.RoundService)
+local TaskPool = require(script.Parent.Parent.pure.TaskPool)
+local TaskSelection = require(Shared.pure.TaskSelection)
+local Types = require(Shared.Types)
+
+local TaskService = {}
+
+local TAG_POINT = "TaskPoint"
+
+--[[
+	THE ONE Random, AND IT IS A MODULE LOCAL RATHER THAN A Start() LOCAL.
+
+	A DELIBERATE DEVIATION from this file's own header, which says to create it at Start(). Every
+	property that header actually asks for is preserved and one is strengthened:
+
+	  · no argument                  — unchanged, and it is the whole point. Read the header.
+	  · server-side, never sent      — unchanged
+	  · created exactly ONCE         — STRONGER. A module local cannot be created twice; a Start()
+	                                   local is one stray second call away from a fresh stream, and a
+	                                   fresh stream is not a bug anyone would notice.
+
+	It also makes the type `Random` rather than `Random?`, which deletes the nil branch that `nextFloat`
+	would otherwise need — and the only honest thing that branch could do is error, inside a phase
+	handler, where errors go to one swallowed warn.
+]]
+local rng = Random.new()
+
+-- SERVER-ONLY state. pointsByName is the discovered pool, keyed by the part Name that IS the task Id.
+local pointsByName: { [string]: BasePart } = {}
+
+local function nextFloat(): number
+	return rng:NextNumber()
+end
+
+--[[
+	Discovery. Rebuilt from scratch on every call rather than cached, because C17 will add, move and
+	delete these parts while a server is running and a cached pool would hand out a point that no
+	longer exists.
+
+	SORTED BEFORE THE DRAW. `GetTagged` returns instances in an order this code does not control and
+	should not inherit — RoleDraw's header makes the same argument for candidates. The draw here is
+	seeded from server entropy so reproducibility is not the reason; removing a hidden, engine-defined
+	input to a random selection is.
+]]
+local function discoverPool(): TaskPool.Report
+	local names: { string } = {}
+
+	table.clear(pointsByName)
+
+	for _, instance in CollectionService:GetTagged(TAG_POINT) do
+		if not instance:IsA("BasePart") then
+			warn(
+				`[TaskService] {instance:GetFullName()} is tagged {TAG_POINT} but is a `
+					.. `{instance.ClassName}, not a BasePart — skipped.`
+			)
+			continue
+		end
+
+		table.insert(names, instance.Name)
+
+		if pointsByName[instance.Name] == nil then
+			pointsByName[instance.Name] = instance
+		end
+	end
+
+	table.sort(names)
+
+	return TaskPool.evaluate(names, Config.Tasks.TotalRequired, Config.Tasks.PoolSize)
+end
+
+--[[
+	THE LOUD HALF, and the reason every warn here is UNGATED by VerboseLogging.
+
+	This repo gates routine tracing and warns unconditionally for faults — RoundService's dropped round
+	result and AntiCheatService's refusal both say so. An unusable task pool is a fault: the round runs,
+	nobody can finish it, and the only symptom a player reports is "the game is boring". VerboseLogging
+	is false on a published place, which is exactly where that report comes from.
+
+	The EMPTY message names the tag and the count, because the person reading it is looking at an empty
+	baseplate and needs to know what to do, not that something went wrong.
+]]
+local function reportPool(report: TaskPool.Report)
+	if #report.Duplicates > 0 then
+		warn(
+			`[TaskService] TaskPoint parts share a Name and were skipped: `
+				.. `{table.concat(report.Duplicates, ", ")}. The server identifies a task point BY its `
+				.. `Name, so every tagged part must have a unique one.`
+		)
+	end
+
+	if report.Verdict == "EMPTY" then
+		warn(
+			`[TaskService] NO "{TAG_POINT}" PARTS IN THE MAP. Tag {Config.Tasks.PoolSize} anchored `
+				.. `parts with "{TAG_POINT}" via CollectionService, or no task can ever be completed `
+				.. `and the escape gate can never open.`
+		)
+	elseif report.Verdict == "SHORT" then
+		warn(
+			`[TaskService] Only {#report.Unique} "{TAG_POINT}" part(s) found; `
+				.. `{Config.Tasks.TotalRequired} are needed to open the gate. Rounds are unwinnable.`
+		)
+	elseif report.Verdict == "OVERSIZED" then
+		warn(
+			`[TaskService] {#report.Unique} "{TAG_POINT}" parts found, but Config.Tasks.PoolSize says `
+				.. `{Config.Tasks.PoolSize}. The draw still works; the map and Config disagree.`
+		)
+	elseif Config.Debug.VerboseLogging then
+		print(`[TaskService] Pool OK — {#report.Unique} task points.`)
+	end
+end
```

And in `Start()`, before any subscription:

```diff
+function TaskService.Start()
+	--[[
+		DISCOVERY RUNS AT BOOT, not only at STARTING, and that is the difference between this service
+		and the one the stub refused to ship. On a map with no anchors the operator learns at server
+		start — while they are still looking at the output window — rather than 45 seconds later when
+		the first round draws nothing and nobody is watching.
+	]]
+	reportPool(discoverPool())
+end
```

`Init()` stays empty and stays declared — `init.server.luau` already lists `TaskService` in
`SERVICE_ORDER`, so **no bootstrap change is needed anywhere in this plan.** Step 2.3 is what adds the
`PhaseChanged` subscription to `Start()`.

**`npm run analyze` is the check**, and the failure it is most likely to catch is the one this file
cannot avoid: `GetTagged` returns `{ Instance }`, so `instance.Name` is fine but `instance.Position` is
not — the `IsA("BasePart")` narrowing above is what makes `pointsByName` typecheck at all, and deleting
it as "defensive" is an analyze error rather than a crash in three weeks.

#### Step 2.3: The draw at `STARTING`, the `ActiveTaskPoint` tag, and the teardown

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:config`

Subscribe to `RoundService.PhaseChanged`, draw on `STARTING`, convert `Vector3` to `TaskSelection.Vec3`
at the call site exactly as `MonsterService` does for `KillValidation`, build the `ActiveTask` list, tag
the chosen parts, and clear all of it on the way into `INTERMISSION` / `IDLE`.

```diff
+local TAG_ACTIVE = "ActiveTaskPoint"
+
+-- This round's five, and the parts they stand on. Server state; `activeParts` is what every distance
+-- check in Phase 3 and 4 measures against, so nothing anywhere caches a position.
+local activeTasks: { Types.ActiveTask } = {}
+local activeParts: { [string]: BasePart } = {}
+
+-- Vector3 -> the plain table pure/TaskSelection takes. The pure module cannot mention Vector3: Lune
+-- has no Roblox datatypes. Converted at the call site, exactly as MonsterService does for
+-- KillValidation.
+local function toVec(position: Vector3): TaskSelection.Vec3
+	return { X = position.X, Y = position.Y, Z = position.Z }
+end
+
+--[[
+	The map's half of the type contract, and the one line C09 does not have to revisit discovery for.
+
+	An absent attribute means HOLD. A present one that is not HOLD is a map asking for a mechanic that
+	does not exist yet, and it gets a HOLD plus a warning naming the part — visible, rather than
+	silently mishandled, which is what C09 will want when it starts placing Timing anchors.
+]]
+local function taskTypeOf(part: BasePart): Types.TaskType
+	local requested = part:GetAttribute("TaskType")
+
+	if requested ~= nil and requested ~= Enums.TaskType.Hold then
+		warn(
+			`[TaskService] {part.Name} asks for TaskType "{requested}", which is not built yet `
+				.. `(C09/C10). Using {Enums.TaskType.Hold}.`
+		)
+	end
+
+	return Enums.TaskType.Hold
+end
+
+--[[
+	Torn down on the way into the LOBBY, not on the way out of ACTIVE — the same rule, for the same
+	reason, as MonsterService's corpses. ENDING keeps this round's tasks so the end screen can show a
+	round that finished 4/5, which is the screenshot §4.8 is about.
+]]
+local function clearTasks()
+	for _, part in activeParts do
+		CollectionService:RemoveTag(part, TAG_ACTIVE)
+	end
+
+	table.clear(activeTasks)
+	table.clear(activeParts)
+
+	-- Also resets the HUD's 5/5 during INTERMISSION, which enterIdle already did and
+	-- enterIntermission never has. See Step 3.4 for why this setter is safe to call in any phase.
+	RoundService.SetTasksCompleted(0)
+end
+
+--[[
+	THE DRAW (§4.4, C07). Five of twelve, at STARTING, from a pool discovered a line earlier.
+
+	The chosen parts get the `ActiveTaskPoint` tag, WHICH REPLICATES TO EVERY CLIENT, and that is
+	correct rather than tolerated. Players have to be able to find the objective; five ProximityPrompts
+	appear on five parts and hiding that would be hiding the game from the people playing it. §1.3 of
+	the plan this came from draws the line: what must never leak is the ability to know or derive the
+	selection BEFORE it is made, and that is a property of `Random.new()` having no argument, not of
+	the tag.
+
+	`check:secrecy` inspects CollectionService tags, and this one passes because it carries no role and
+	no UserId. It is named for a place, not for a person.
+]]
+local function selectForRound()
+	local report = discoverPool()
+
+	reportPool(report)
+
+	local pool: { TaskSelection.Point } = {}
+
+	for _, name in report.Unique do
+		local part = pointsByName[name]
+
+		if part ~= nil then
+			table.insert(pool, { Id = name, Position = toVec(part.Position) })
+		end
+	end
+
+	local chosen =
+		TaskSelection.select(pool, Config.Tasks.TotalRequired, Config.Tasks.MinSpacingStuds, nextFloat)
+
+	for _, point in chosen do
+		local part = pointsByName[point.Id]
+
+		if part == nil then
+			continue
+		end
+
+		table.insert(activeTasks, {
+			Id = point.Id,
+			Type = taskTypeOf(part),
+			SpawnPointName = part.Name,
+			Progress = 0,
+			Completed = false,
+		})
+
+		activeParts[point.Id] = part
+		CollectionService:AddTag(part, TAG_ACTIVE)
+	end
+
+	--[[
+		A round that drew fewer than TotalRequired can never reach 5/5, so it can never open the gate.
+		It is still a playable round — the sunrise timer and C06's attrition win both still work — and
+		saying so is more useful than aborting it, because the person who needs to know is the one
+		reading the console, not the eight players in the lobby.
+	]]
+	if #activeTasks < Config.Tasks.TotalRequired then
+		warn(
+			`[TaskService] Round drew {#activeTasks} of {Config.Tasks.TotalRequired} tasks. The escape `
+				.. `gate cannot open this round.`
+		)
+	elseif Config.Debug.VerboseLogging then
+		local ids = {}
+
+		for _, entry in activeTasks do
+			table.insert(ids, entry.Id)
+		end
+
+		print(`[TaskService] Round tasks: {table.concat(ids, ", ")}`)
+	end
+end
+
+local function onPhaseChanged(phase: Types.RoundPhase)
+	if phase == Enums.RoundPhase.Starting then
+		clearTasks()
+		selectForRound()
+	elseif phase == Enums.RoundPhase.Intermission or phase == Enums.RoundPhase.Idle then
+		clearTasks()
+	end
+end
```

and the subscription, appended to `Start()`:

```diff
 	reportPool(discoverPool())
+
+	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
 end
```

**Why the draw happens on the `PhaseChanged` fire rather than from inside `enterStarting`.**
`RoundService.luau:578` carries `-- TODO(C07): TaskService.SelectTasksForRound()`, which asks RoundService
to require TaskService. Following it literally, together with this service needing
`RoundService.SetTasksCompleted`, is a require cycle — and RoundService's own header spells out what that
costs: an error at load, one swallowed `warn`, and a server sitting in IDLE that looks like an empty
lobby. Subscribing instead is the shape `MonsterService` already uses for exactly this reason. Step 3.4
deletes the TODO rather than leaving a comment that recommends a cycle.

**The one behavioural consequence of subscribing**, stated so it is not met as a surprise:
`enterStarting` draws roles *before* `setPhase` deliberately, so no subscriber sees a STARTING round
without an Aswang. Tasks are drawn *on* the fire, so for the duration of one synchronous handler a
STARTING round has no tasks. Nothing observes that — `setPhase` broadcasts the snapshot after every
subscriber has returned, and `TasksCompleted` is 0 either way.

**`npm run check:config` is the check** because this step is where the numbers would go wrong:
`TotalRequired`, `PoolSize` and `MinSpacingStuds` are all read from `Config` here, and the tempting
mistake — `TaskSelection.select(pool, 5, 20, nextFloat)` — is precisely what that gate exists to catch.

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

- **`ActiveTaskPoint` replicates, deliberately.** It is the one thing in this plan that a reviewer
  should stop on, and §1.3 is the written answer. It carries no role and no UserId, `check:secrecy`
  passes it, and the selection becoming visible is the game working. What would be a leak is the
  *unselected* pool or the RNG stream reaching a client, and neither does.
- **A require cycle is one edit away.** The moment anybody acts on `RoundService.luau:578`'s TODO, the
  server boots into a permanent IDLE behind a single `warn`. Step 3.4 deletes the TODO; until it does,
  this phase leaves a live invitation in the tree.
- **§6.4, a player leaving mid-round:** none of this phase observes players. A `TaskPoint` part being
  *deleted* mid-round is the analogous case, and it is handled — `activeParts` holds a reference to a
  destroyed part, whose `.Parent` is nil; Step 3.3's tick must not assume the part is still in the
  workspace.
- **Mobile budget:** twelve tags and five more, no lights, no particles, no per-frame work added yet.
  The tick loop arrives in Phase 3 and is counted there.

### Phase 3: Server-timed accumulation

The half of C08 that decides the shape C09/C10 copy. The client is not involved yet at all.

#### Step 3.1: `src/server/pure/TaskProgress.luau` — the tick and the max rule

**File:** `src/server/pure/TaskProgress.luau`
**Verify:** `npm run lint`

`(progress, elapsed, weight, holdTime) -> (progress, completed)`, plus `strongestWeight` — the maximum,
never the sum. §1.4 decision 1 lives in this file and nowhere else.

```diff
+--!strict
+--[[
+	TaskProgress — how far did one task point get in the last server tick? (§4.4, C08)
+
+		strongestWeight(weights)                     -> weight
+		tick(progress, elapsed, weight, holdTime)    -> { Progress, Completed }
+
+	THE SHAPE THE OTHER THREE TASK TYPES COPY. C09 and C10 differ in what produces a `weight` and in
+	nothing else; the accumulation, the boundary and the clamp are here once.
+
+	WHY THE RATE IS A MAXIMUM AND NOT A SUM — the single decision in this file that is not obvious,
+	and it is a SECRECY decision rather than a balance one.
+
+	A summed rate is the natural design: three survivors on one task, three times the speed. It also
+	makes the bar's speed a function of HOW MANY people are contributing, and at C12 the Aswang's
+	contribution becomes zero. A survivor standing on a task with the monster would then watch the bar
+	move at one-person speed with two people on it, and know. That is a role oracle readable by anyone,
+	built out of nothing but arithmetic, and it would have shipped with every check in this repo green.
+
+	With a maximum, an Aswang on a task changes nothing anyone else can observe. §4.4 also gets what it
+	asked for on its own terms — the task takes HoldTime whether one person or four is doing it, so it
+	"forces you to stand still and vulnerable" for a fixed, predictable, ambushable eight seconds.
+
+	C15's ghosts fall out of the same rule for free: a ghost's weight is Config.Ghost.TaskContributionMult
+	(0.25), so a ghost alone is slow and a ghost helping a survivor is neither faster nor slower than the
+	survivor alone. §4.7 asks for "they still matter", not "they stack".
+
+	NO `script.Parent` REQUIRES and no Roblox datatypes: plain numbers only, so Lune can run this.
+]]
+
+export type Result = {
+	Progress: number,
+	Completed: boolean,
+}
+
+local TaskProgress = {}
+
+-- The strongest contributor present, or 0 when nobody is. An EMPTY list must return 0 rather than
+-- erroring: "nobody is standing here" is the normal state of four of the five task points.
+function TaskProgress.strongestWeight(weights: { number }): number
+	local best = 0
+
+	for _, weight in weights do
+		if weight > best then
+			best = weight
+		end
+	end
+
+	return best
+end
+
+--[[
+	One tick. `elapsed` is SERVER seconds since the last tick — not a count of requests, not a client
+	timestamp — which is the whole of why spamming RequestTaskProgress gains nothing (C08's stated Done
+	condition). A thousand requests a second and one request a second accumulate identically.
+
+	FOUR GUARDS, and each one is a real state rather than defensive padding:
+
+	  · already complete   — a completed task never moves again, and never re-fires completion
+	  · weight <= 0        — nobody eligible is present. FREEZE, do not decay: progress belongs to the
+	                         WORLD, not to the player (§4.4 anti-frustration), so a survivor who dies
+	                         at 90% leaves 90% for whoever arrives next. Decay would recreate exactly
+	                         the "a dead player's task is now unwinnable" class §4.4 deletes.
+	  · elapsed <= 0       — os.clock() is not guaranteed monotonic across a server's lifetime;
+	                         TokenBucket carries the same guard for the same reason
+	  · holdTime <= 0      — a division by zero. It cannot happen through Config, and "cannot happen"
+	                         is how a nan reaches a client and a bar renders empty forever.
+]]
+function TaskProgress.tick(progress: number, elapsed: number, weight: number, holdTime: number): Result
+	local current = math.clamp(progress, 0, 1)
+
+	if current >= 1 then
+		return { Progress = 1, Completed = true }
+	end
+
+	if weight <= 0 or elapsed <= 0 then
+		return { Progress = current, Completed = false }
+	end
+
+	if holdTime <= 0 then
+		return { Progress = 1, Completed = true }
+	end
+
+	local updated = math.clamp(current + (elapsed * weight) / holdTime, 0, 1)
+
+	return { Progress = updated, Completed = updated >= 1 }
+end
+
+return TaskProgress
```

`math.clamp` is confirmed available under Lune — `src/server/pure/RoleDraw.luau` already uses it and
`tests/role-draw.test.luau` runs.

#### Step 3.2: `tests/task-progress.test.luau` — the boundary and the non-scaling property

**File:** `tests/task-progress.test.luau`
**Verify:** `lune run tests/task-progress.test.luau`

Completion at exactly `HoldTime`, no accumulation at weight 0, freeze rather than decay, a clamp at 1.0,
a non-monotonic clock, and the property that matters: N contributors finish no faster than one.

```diff
+--!strict
+--[[
+	Server-timed hold accumulation. C08's boundary, its freeze, and its one secrecy property.
+
+	THE LAST ASSERTION IS THE REASON THIS FILE EXISTS. "Four people do not finish a task faster than
+	one" reads like a balance choice and is a secrecy one: a summed rate makes the bar's speed a
+	function of how many people are contributing, and at C12 the Aswang contributes nothing. Pinned
+	here, in a terminal, because the day somebody "fixes" the max into a sum it will look like an
+	improvement and no other check in this repo will object.
+]]
+
+local Config = require("../src/shared/Config")
+local TaskProgress = require("../src/server/pure/TaskProgress")
+
+local HOLD = Config.Tasks.HoldTime
+local TICK = 0.25
+
+local failures = 0
+
+local function check(label: string, ok: boolean, detail: string?)
+	if ok then
+		return
+	end
+
+	failures += 1
+	print(`  FAIL  {label}{if detail then ` — {detail}` else ""}`)
+end
+
+-- Run a hold at a fixed tick rate and answer: how many seconds until it completed?
+local function secondsToComplete(weights: { number }): number?
+	local progress = 0
+	local elapsedTotal = 0
+	local weight = TaskProgress.strongestWeight(weights)
+
+	for _ = 1, math.ceil((HOLD * 4) / TICK) do
+		local result = TaskProgress.tick(progress, TICK, weight, HOLD)
+
+		progress = result.Progress
+		elapsedTotal += TICK
+
+		if result.Completed then
+			return elapsedTotal
+		end
+	end
+
+	return nil
+end
+
+-- strongestWeight, including the empty case that is the normal state of four of the five task points.
+check("nobody present is weight zero", TaskProgress.strongestWeight({}) == 0)
+check("one contributor is their own weight", TaskProgress.strongestWeight({ 0.25 }) == 0.25)
+check("the strongest wins, not the sum", TaskProgress.strongestWeight({ 0.25, 1, 0.25 }) == 1)
+check("order does not matter", TaskProgress.strongestWeight({ 1, 0.25 }) == 1)
+
+-- The boundary. A single full-weight contributor finishes in HoldTime, not HoldTime plus a tick.
+local alone = secondsToComplete({ 1 })
+
+check("one survivor completes a hold", alone ~= nil)
+check("and does it in HoldTime", alone ~= nil and alone <= HOLD + TICK, `{alone}s vs HoldTime={HOLD}s`)
+check("not sooner", alone ~= nil and alone >= HOLD, `{alone}s vs HoldTime={HOLD}s`)
+
+--[[
+	§1.4 DECISION 1, PINNED. Four contributors take the same time as one. If this ever fails, the rate
+	has become a sum and the Aswang's zeroed weight at C12 is visible to every bystander watching a bar.
+]]
+local crowd = secondsToComplete({ 1, 1, 1, 1 })
+
+check("four contributors finish no faster than one", crowd == alone, `crowd={crowd}s, alone={alone}s`)
+
+-- A ghost alone (C15's 25%) is slow but not stuck, and a ghost alongside a survivor is neither faster
+-- nor slower than the survivor alone. §4.7 asks for "they still matter", not "they stack".
+local ghostAlone = secondsToComplete({ Config.Ghost.TaskContributionMult })
+
+check("a quarter-weight contributor still finishes", ghostAlone ~= nil)
+check(
+	"and takes about four times as long",
+	ghostAlone ~= nil and alone ~= nil and ghostAlone > alone * 3,
+	`ghost={ghostAlone}s, alive={alone}s`
+)
+check(
+	"a quarter-weight helper neither speeds up nor slows down a full one",
+	secondsToComplete({ 1, Config.Ghost.TaskContributionMult }) == alone
+)
+
+-- FREEZE, NOT DECAY. §4.4 assigns progress to the world; a survivor who dies at 90% must leave 90%
+-- behind, or a dead player's task becomes the unwinnable case that rule exists to delete.
+local abandoned = TaskProgress.tick(0.9, 30, 0, HOLD)
+
+check("walking away stops accumulation", abandoned.Progress == 0.9, `{abandoned.Progress}`)
+check("and does not complete it", not abandoned.Completed)
+
+-- The four guards.
+local completed = TaskProgress.tick(1, TICK, 1, HOLD)
+
+check("a completed task stays completed", completed.Completed and completed.Progress == 1)
+
+local clamped = TaskProgress.tick(0.99, HOLD * 10, 1, HOLD)
+
+check("progress never exceeds 1", clamped.Progress == 1, `{clamped.Progress}`)
+check("and reports completion", clamped.Completed)
+
+local backwards = TaskProgress.tick(0.5, -5, 1, HOLD)
+
+check("a clock that ran backwards moves nothing", backwards.Progress == 0.5, `{backwards.Progress}`)
+
+local zeroHold = TaskProgress.tick(0, TICK, 1, 0)
+
+check("a zero HoldTime completes rather than dividing by zero", zeroHold.Completed)
+check("and produces a real number", zeroHold.Progress == zeroHold.Progress, `{zeroHold.Progress}`)
+
+local negative = TaskProgress.tick(-1, TICK, 1, HOLD)
+
+check("a negative progress is clamped up, not accumulated from", negative.Progress > 0)
+
+if failures > 0 then
+	error(`{failures} task-progress assertion(s) failed`, 0)
+end
+
+print("  PASS  task-progress: 20 assertions, incl. the non-scaling property")
```

**`zeroHold.Progress == zeroHold.Progress` is a NaN check, not a tautology.** `0/0` is the one way this
module can produce a value that silently poisons every comparison downstream and renders as an empty bar
forever, and `nan ~= nan` is the only way Luau will tell you.

#### Step 3.3: The tick loop, the presence table, and re-validation at tick time

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:config`

A `task.spawn` loop matching `RoundService.Start`'s shape. Presence is an intent stamp with a grace
window; distance is re-measured against the live character on every tick, so a client that fires once
and teleports away accumulates nothing.

```diff
+local TaskProgress = require(script.Parent.Parent.pure.TaskProgress)
+
+-- One player's most recent claim to be holding something. SERVER-ONLY, never replicated, never
+-- attributed. `At` is an os.clock() stamp; `TaskId` is what the SERVER resolved at the moment the
+-- request arrived, never anything the client named.
+type Presence = {
+	TaskId: string,
+	At: number,
+}
+
+local presence: { [number]: Presence } = {}
+local lastTickAt = os.clock()
+
+--[[
+	THE ONE PLACE A CONTRIBUTION RATE IS DECIDED, and the whole reason it is a function rather than a
+	literal `1` at the call site.
+
+	C08: every ALIVE player contributes at full weight. C12 makes this return 0 for the Aswang. C15
+	makes it return Config.Ghost.TaskContributionMult for a GHOST. Both are an edit to this function
+	and to nothing else, and TaskProgress's max rule is what keeps either edit invisible to a bystander.
+
+	It asks RoundService for the player's state rather than keeping its own copy, exactly as
+	MonsterService does. There is one owner of PlayerStates and this is not it.
+]]
+local function weightFor(player: Player): number
+	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+		return 0
+	end
+
+	return 1
+end
+
+local function positionOf(player: Player): Vector3?
+	local character = player.Character
+
+	if character == nil then
+		return nil
+	end
+
+	local root = character:FindFirstChild("HumanoidRootPart")
+
+	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
+end
+
+--[[
+	WHICH selected task point is this player standing at, decided entirely from the server's own copy
+	of the world. Returns nil when none is in range.
+
+	THE FIRST MATCH WINS AND THAT IS SAFE, because Step 1.4 pins
+	`PresenceRangeStuds * 2 < MinSpacingStuds` — two selected points can never both be in range of one
+	character. That invariant is what lets RequestTaskProgress take no arguments at all (Step 4.1); if
+	it is ever tuned away, this function starts returning an arbitrary one of two answers and the fix
+	is the Config number, not this loop.
+
+	`part.Parent ~= nil` guards a task point deleted from the map mid-round — a live risk while C17 is
+	being built in a running Studio session, and a destroyed part keeps answering `.Position` forever.
+]]
+local function taskPointAt(player: Player): string?
+	local position = positionOf(player)
+
+	if position == nil then
+		return nil
+	end
+
+	for id, part in activeParts do
+		if
+			part.Parent ~= nil
+			and (part.Position - position).Magnitude <= Config.Tasks.PresenceRangeStuds
+		then
+			return id
+		end
+	end
+
+	return nil
+end
+
+local function completedCount(): number
+	local total = 0
+
+	for _, task in activeTasks do
+		if task.Completed then
+			total += 1
+		end
+	end
+
+	return total
+end
+
+--[[
+	THE SERVER TICK. C08's "server-timed", literally: `elapsed` is measured here, from the server's own
+	clock, and it is the only quantity that moves a bar.
+
+	This is what makes "a client spamming RequestTaskProgress gains nothing" true by CONSTRUCTION
+	rather than by a rate limit. The limiter bounds how often a client may ask; this loop makes the
+	answer independent of how often it asked. A thousand requests a second and four requests a second
+	accumulate exactly the same amount, because neither number appears anywhere below.
+
+	DISTANCE IS RE-MEASURED HERE, not trusted from the stamp. A presence entry says "this player
+	asserted, recently, that they are holding task X"; this loop asks the world whether they still are.
+	Without it the grace window is a teleport-and-idle exploit worth PresenceGraceSeconds of free
+	progress per request, which is small and would never have shown up in a playtest.
+
+	Assigning nil to the key currently being visited is defined behaviour in Lua's `next` traversal;
+	inserting a new key during one is not, and nothing here does.
+]]
+local function tick()
+	local now = os.clock()
+	local elapsed = now - lastTickAt
+
+	lastTickAt = now
+
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active or #activeTasks == 0 then
+		return
+	end
+
+	local weights: { [string]: { number } } = {}
+
+	for userId, entry in presence do
+		local player = Players:GetPlayerByUserId(userId)
+
+		if player == nil or now - entry.At > Config.Tasks.PresenceGraceSeconds then
+			presence[userId] = nil
+			continue
+		end
+
+		if taskPointAt(player) ~= entry.TaskId then
+			continue
+		end
+
+		local bucket = weights[entry.TaskId]
+
+		if bucket == nil then
+			bucket = {}
+			weights[entry.TaskId] = bucket
+		end
+
+		table.insert(bucket, weightFor(player))
+	end
+
+	local anyCompleted = false
+
+	for _, task in activeTasks do
+		if task.Completed then
+			continue
+		end
+
+		local weight = TaskProgress.strongestWeight(weights[task.Id] or {})
+		local result = TaskProgress.tick(task.Progress, elapsed, weight, Config.Tasks.HoldTime)
+
+		task.Progress = result.Progress
+
+		if result.Completed then
+			task.Completed = true
+			anyCompleted = true
+
+			if Config.Debug.VerboseLogging then
+				print(`[TaskService] Task complete: {task.Id}`)
+			end
+		end
+	end
+
+	if anyCompleted then
+		RoundService.SetTasksCompleted(completedCount())
+	end
+
+	publishProgress(anyCompleted)
+end
```

and the loop, appended to `Start()` after the subscription:

```diff
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+
+	task.spawn(function()
+		while true do
+			tick()
+			task.wait(0.25) -- config-ok: scheduler tick, not a balance knob
+		end
+	end)
 end
```

`publishProgress` arrives in Step 4.3; until then it is a two-line stub that does nothing, so this step
lands runnable.

**§5's mobile budget, counted.** One server-side loop at 4 Hz doing at most `#presence × #activeTasks`
distance comparisons — with eight players and five tasks, forty subtractions a tick. No lights, no
particles, no client-side per-frame work. The `0.25` carries the same `config-ok` waiver, with the same
reason, as `RoundService.Start`'s tick: a scheduler interval is not a balance knob and putting it in
`Config` would invite it to be tuned as one.

**`npm run check:config` is the check** because this step reads four Config values and is the single
most likely place in the plan for a `8` or a `0.75` to be typed instead. The gate allows the `0.25` only
because of the waiver, and the waiver is visible in a diff.

#### Step 3.4: `RoundService.SetTasksCompleted`, and retiring the C07 seam

**File:** `src/server/Services/RoundService.luau`
**Verify:** `npm run test:unit`

One clamped setter, and the deletion of the `TODO(C07): TaskService.SelectTasksForRound()` comment,
which points the dependency the wrong way round.

```diff
 function RoundService.GetPlayerState(player: Player): PlayerState
 	return state.PlayerStates[player.UserId] or Enums.PlayerState.Lobby
 end
+
+--[[
+	How many of this round's tasks are done (§4.4, C08). WRITTEN BY TaskService, READ BY THE SNAPSHOT.
+
+	This service owns the counter for the same reason it owns PlayerStates: `buildSnapshot` is the only
+	thing that sends it, and a counter living next to its sender cannot drift from what the HUD shows.
+	TaskService owns the TASKS; this owns the NUMBER on the bar.
+
+	NOT A PHASE, AND DELIBERATELY NOT GUARDED LIKE ONE. `setPhase` stays private and stays this
+	service's alone; a count is data, and TaskService legitimately writes it in three situations —
+	a completion during ACTIVE, a reset when it clears the round's tasks on the way into INTERMISSION,
+	and the same reset again at IDLE. Refusing the call outside ACTIVE would break the middle one, and
+	that one is a real fix: `enterIdle` resets this counter and `enterIntermission` never has, so until
+	now the HUD showed last round's 4/5 for the whole intermission.
+
+	The clamp is the only validation worth having. A count above TotalRequired would render as 7/5 and
+	a negative one as -1/5, and neither is worth a caller having to remember.
+]]
+function RoundService.SetTasksCompleted(count: number)
+	state.TasksCompleted = math.clamp(count, 0, Config.Tasks.TotalRequired)
+end
```

and the seam comment, which is now actively wrong:

```diff
 	setPhase(Enums.RoundPhase.Starting, Config.Round.StartingDelay)
-	-- TODO(C07): TaskService.SelectTasksForRound()
 end
```

```diff
 -- TODO(C03): assign roles via RoleService in STARTING
--- TODO(C07): pick tasks via TaskService in STARTING; TODO(C11): win conditions in ACTIVE
+-- TODO(C11): win conditions in ACTIVE
+-- Tasks are NOT drawn from here. TaskService subscribes to PhaseChanged and draws on STARTING, because
+-- it needs SetTasksCompleted above and requiring it back from here would be a load-time require cycle
+-- — see this file's header on RoleService for what that costs.
 -- TODO(C15): convert dead players to ghosts via GhostService
```

**Deleting a TODO is a real deliverable here, not tidying.** It is an instruction to build a require
cycle, sitting in the file most likely to be read by whoever builds C09. The replacement comment says
what happens instead and why, in the place someone will look for it.

**`npm run test:unit` is the check** — every Lune suite, including the two this plan adds and the
`config.test.luau` invariants from Step 1.4. It is the broadest gate in the plan that does not need
Studio, and this is the step where a `Config.Tasks.TotalRequired` typo would take the clamp with it.

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

- **The max rule is one edit from being a leak.** Nothing in the engine, the analyzer or the five checks
  objects to `strongestWeight` becoming a sum. `tests/task-progress.test.luau`'s non-scaling assertion is
  the entire defence, and it is why that assertion exists rather than a comment. Risk R2 in §4.
- **Two writers of `state.TasksCompleted`.** `enterIdle` and `SetTasksCompleted`. They cannot disagree —
  `enterIdle` writes 0 and `clearTasks` writes 0 — but a third writer added later could, and there is no
  check that would notice.
- **§6.4, a player leaving mid-hold:** covered twice. `GetPlayerByUserId` returns nil and the entry is
  dropped; the grace window expires it regardless. The task keeps its partial progress, which is §4.4's
  anti-frustration rule working as intended rather than a leak of state.
- **§6.4, a player dying mid-hold:** `weightFor` reads `GetPlayerState`, so a killed player stops
  contributing on the next tick without any bookkeeping here. At C15 the same line starts returning the
  ghost multiplier instead of 0, which is the behaviour §4.7 actually asks for.
- **Phase ownership:** `SetTasksCompleted` writes a counter, never `setPhase`, which stays a private
  local in `RoundService`. Worth restating because this is the first function this repo has added to
  `RoundService` at another service's request.

### Phase 4: The remote surface

Two remotes, both already declared. Nothing is added to `Remotes.luau`.

#### Step 4.1: `RequestTaskProgress` — no arguments, `Consume` first, silence on refusal

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:ratelimit`

The handler takes no arguments at all, following `RequestTransform`'s precedent: the server derives
which task point from its own copy of the world, so there is no client-supplied value to refuse to
trust. `AntiCheatService.Consume` is the first line, inline at the connect site.

```diff
+local AntiCheatService = require(script.Parent.AntiCheatService)
+
+--[[
+	Everything the server checks before it believes a player is standing on a task.
+
+	Returns a verdict AND the resolved task Id, because the caller needs both and deriving the Id twice
+	is how the two answers drift apart. The verdict is for the LOG ONLY — read Types.TaskProgressVerdict
+	before echoing any of it anywhere.
+
+	NOT_ALIVE is where C15 will change: §4.7 wants a GHOST to contribute at a reduced rate, so this line
+	becomes an allowlist of ALIVE and GHOST and `weightFor` supplies the difference. Today a ghost is
+	refused, which is correct for C08 and wrong for §4.7 — named here so it is found rather than
+	rediscovered.
+]]
+local function evaluatePresence(player: Player): (Types.TaskProgressVerdict, string?)
+	if RoundService.GetPhase() ~= Enums.RoundPhase.Active then
+		return "WRONG_PHASE", nil
+	end
+
+	if RoundService.GetPlayerState(player) ~= Enums.PlayerState.Alive then
+		return "NOT_ALIVE", nil
+	end
+
+	local id = taskPointAt(player)
+
+	if id == nil then
+		return "NO_TASK_IN_RANGE", nil
+	end
+
+	for _, task in activeTasks do
+		if task.Id == id and task.Completed then
+			return "ALREADY_COMPLETE", nil
+		end
+	end
+
+	return "OK", id
+end
+
+--[[
+	THE ONLY THING A CLIENT CAN DO TO A TASK: assert that it is present. It cannot report progress and
+	it cannot report completion, which is C08's stated rule, and the shape here is what makes that
+	structural rather than enforced — there is no argument in which a completion could arrive.
+
+	EVERY REFUSAL RETURNS NOTHING. No verdict, no false, no error. Types.TaskProgressVerdict explains
+	why in full; the short version is that C12 adds a value meaning "you are the Aswang" and there is
+	no safe subset to send once that exists.
+
+	The stamp records the SERVER's resolution of which task point, never anything the client named,
+	and Step 3.3's tick re-checks it anyway.
+]]
+local function notePresence(player: Player)
+	local verdict, id = evaluatePresence(player)
+
+	if verdict ~= "OK" or id == nil then
+		if Config.Debug.VerboseLogging then
+			-- Server console only, and off on a published place. Re-read this line at C12: the verdict
+			-- set gains a value that names a role, and a developer running Play Solo sees this window.
+			print(`[TaskService] Refused progress for {player.Name}: {verdict}`)
+		end
+
+		return
+	end
+
+	presence[player.UserId] = { TaskId = id, At = os.clock() }
+end
```

and the handler, in `Start()`:

```diff
+	--[[
+		THE RATE LIMIT LIVES HERE, INLINE, for the reason MonsterService's two handlers spell out:
+		`check-ratelimit.mjs` matches the Consume call within 1200 characters of the connect site, so a
+		handler that IS limited but does it 200 lines away reads as unguarded and fails the build. A
+		reader skimming the connect site should see the guard without following a call.
+
+		Consume FIRST, before any state is read. This is the highest-frequency remote in the game — an
+		honest client sends four a second while holding — so a handler that validated first would be
+		doing five reads and a distance sweep per refused request, which is what makes a remote worth
+		spamming even when it achieves nothing.
+	]]
+	Remotes.Get("RequestTaskProgress").OnServerEvent:Connect(function(player: Player)
+		if not AntiCheatService.Consume(player, "RequestTaskProgress") then
+			return
+		end
+
+		notePresence(player)
+	end)
```

**No `typeof` guard on an argument, because there is no argument.** `RequestKill` needs
`if typeof(targetUserId) ~= "number"` precisely because it accepts one; this handler's signature ignores
anything a client sends, so a table, a function or a 4 MB string arrives and is discarded by the
argument list itself. That is the strongest form of "the client only requests" available in this
codebase, and it is only reachable because Step 1.4 pinned the spacing invariant that makes the task
point derivable.

**`npm run check:ratelimit` is the check.** It is the gate this step exists to satisfy, it fails
outright if `Consume` drifts more than 1200 characters from the connect site, and it is the first time
in this plan that a check would go red for a real reason rather than a typo.

#### Step 4.2: `TaskProgressChanged` — per player, typed local, global bar plus your own fill

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:remotes`

`FireClient` per player, built as a `Types.TaskProgressPayload` local rather than an inline table, for
the reason `Types.luau` spells out three times: an inline literal is checked against nothing.

```diff
+local progressRemote = Remotes.Get("TaskProgressChanged")
+
+-- The last YourTaskProgress each client was sent, so a bar that has not moved costs nothing. nil is a
+-- meaningful value here: "this player is not standing on anything", and it must be SENT once so the
+-- client can clear its bar.
+local lastSentProgress: { [number]: number } = {}
+
+--[[
+	THE TASK BAR (§4.4). FireClient per player, NEVER FireAllClients, and the reason is a leak rather
+	than a saving.
+
+	Two facts leave here. `TasksCompleted` / `TasksRequired` are the global bar and are identical for
+	every player — §4.4's "overall progress, not who did what". `YourTaskProgress` is the fill of the
+	one point the receiving player is standing on, and it reaches nobody else.
+
+	If per-task fractional progress were broadcast, a survivor who can see WHO is standing at task 3 —
+	which they can, characters replicate — and can also see task 3's bar frozen would have identified
+	the Aswang the instant C12 zeroes its weight. Broadcasting the fill would hand every bystander a
+	role oracle rendered as a UI element. Per-player is what makes C12 a change to `weightFor` instead
+	of a redesign of this remote.
+
+	Built as a TYPED LOCAL, not an inline table: FireClient takes `...any`, so an inline literal is
+	checked against nothing at all. The annotation catches a wrong type and a missing field but NOT an
+	extra one — see Types.TaskProgressPayload, and note that a field named `PresentPlayerCount` would
+	satisfy every check in this repo and reinstate the oracle above in one line.
+]]
+local function publishProgress(completionChanged: boolean)
+	local completed = completedCount()
+
+	for _, player in Players:GetPlayers() do
+		local entry = presence[player.UserId]
+		local yours: number? = nil
+
+		if entry ~= nil then
+			for _, task in activeTasks do
+				if task.Id == entry.TaskId then
+					yours = task.Progress
+					break
+				end
+			end
+		end
+
+		if not completionChanged and yours == lastSentProgress[player.UserId] then
+			continue
+		end
+
+		lastSentProgress[player.UserId] = yours
+
+		local payload: Types.TaskProgressPayload = {
+			TasksCompleted = completed,
+			TasksRequired = Config.Tasks.TotalRequired,
+			YourTaskProgress = yours,
+		}
+
+		progressRemote:FireClient(player, payload)
+	end
+end
```

`publishProgress` must be declared **above** `tick` — Step 3.3 calls it and Luau resolves locals in
declaration order. Step 3.3 leaves it as a no-op stub for exactly this reason; this step replaces the
stub in place.

`lastSentProgress` is cleared in two places: `clearTasks` (Step 2.3) and a new `onPlayerRemoving`:

```diff
+local function onPlayerRemoving(player: Player)
+	presence[player.UserId] = nil
+	lastSentProgress[player.UserId] = nil
+end
```

```diff
 	RoundService.PhaseChanged.Event:Connect(onPhaseChanged)
+	Players.PlayerRemoving:Connect(onPlayerRemoving)
```

**`npm run check:remotes` is the check**, and it is the one that catches this step's real failure mode.
`TaskProgressChanged` is in `EVENTS_DOWN` and `RequestTaskProgress` in `EVENTS_UP`; firing either from
the wrong side is a mistake with no symptom on the server and a permanent `WaitForChild` hang on the
client — no error, no output, no stack trace. **No remote is added to `Remotes.luau` by this plan.**

#### Step 4.3: The send budget, and the secrecy pass over what actually goes out

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run check:secrecy`

A completion reaches everyone; a moving fill reaches only the player it belongs to, and only when the
value changed. §5's mobile budget is one reason this is a step; the other is that "who receives a
message" is itself a channel, and this is where it gets read as one.

**The budget, counted against §5.** With eight players and one person holding, `publishProgress` sends
one message per tick — 4/s total, against `RoundSnapshot`'s existing 16/s for the same eight players. A
completion sends eight, five times a round. The `continue` on an unchanged value is what keeps the seven
players standing in a field from receiving four identical messages a second each; without it this remote
would cost twice what the snapshot does and carry nothing new.

**"Who receives a message" is a channel, and here is the audit of it.** A client can observe *that* it
received a `TaskProgressChanged`, and traffic analysis is not something a Roblox client can do to
another client's connection — but it is worth stating what a compromised client learns from its own
stream, because that is the reachable half:

| What a client sees | What it can infer | Verdict |
| --- | --- | --- |
| Its own `YourTaskProgress` moving | it is standing on a live task and someone eligible is holding it | fine — it is that someone |
| Its own `YourTaskProgress` frozen at a live point | nobody eligible is holding — **at C12, "I am the Aswang"** | fine; it already knows |
| `TasksCompleted` moving | the survivors are making progress | fine — §4.4 wants this public |
| Nothing at all | it is not standing on a live task point | fine — it can see that |

The row that would be fatal is "another player's `YourTaskProgress`", and there is no such row because
the field is only ever sent to its owner. That is the whole of §1.4 decision 2, checked rather than
asserted.

**`npm run check:secrecy` is the check.** `TaskProgressChanged` is deliberately **not** on
`REVEAL_ALLOWLIST`, so unlike `RoundEnded` the scanner does inspect this call: it resolves the typed
local back to its declaration and reads the fields. It would catch a `Role`, an `AswangUserId` or a
`Killer*` added here. It would **not** catch `PresentPlayerCount`, and that is the limit worth knowing —
which is what §4's risk R1 and an `exploit-auditor` pass are for.

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

- **`check:ratelimit` is a proximity tripwire and this handler is trivially compliant.** Green here
  means the `Consume` call is near the connect site, not that the handler is safe. What actually makes
  it safe is that `evaluatePresence` re-derives every input from server state — and no check in this
  repo can see that. `exploit-auditor` is mandatory on this diff; `review-gate.mjs` will name it.
- **The bar goes stale for one phase transition.** `tick` returns early outside ACTIVE, so the last
  `TaskProgressChanged` before ENDING is the last one sent. `RoundSnapshot` carries `TasksCompleted`
  twice a second and corrects the global bar; `YourTaskProgress` simply stops moving, which is correct
  — the round is over.
- **§6.4, a player joining mid-round** is a SPECTATOR, so `evaluatePresence` returns `NOT_ALIVE` and
  they contribute nothing. They still receive `TaskProgressChanged` with `YourTaskProgress = nil`,
  which is the truth and tells them nothing.
- **Remote direction:** `RequestTaskProgress` is `OnServerEvent` on a remote in `EVENTS_UP`;
  `TaskProgressChanged` is `FireClient` on one in `EVENTS_DOWN`. Neither list changes.

### Phase 5: The client reports presence, and nothing else

The client after this phase can say "I am holding" and can render what it is told. It cannot compute a
completion, and deleting every line of it changes no outcome the server produces.

#### Step 5.1: `TaskController` — receive the bar, own no truth

**File:** `src/client/Controllers/TaskController.luau` + `src/client/init.client.luau`
**Verify:** `npm run analyze`

Caches the last `TaskProgressChanged`, exposes it for C18's HUD, and drives the presence heartbeat while
the local player is holding. Registered in `CONTROLLER_ORDER` before `InputController`, which requires it.

```diff
+--!strict
+--[[
+	TaskController — the task bar, and the presence heartbeat. (§4.4, C08)
+
+	IT OWNS NO TRUTH, and that is a testable claim rather than a slogan: delete every line of this file
+	and no outcome the server produces changes. It cannot complete a task, it cannot advance a bar, it
+	cannot choose which task point it is reporting. It says "I am holding" four times a second and
+	renders whatever comes back. Apply that test to anything added here.
+
+	Milestone M7 owns the real bar (C18). Today this is a cache with a print behind VerboseLogging, and
+	`GetLatest` is the seam C18 draws from.
+]]
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.Config)
+local Remotes = require(Shared.Remotes)
+local Types = require(Shared.Types)
+
+local TaskController = {}
+
+local latest: Types.TaskProgressPayload? = nil
+local holding = false
+
+function TaskController.GetLatest(): Types.TaskProgressPayload?
+	return latest
+end
+
+--[[
+	Set by InputController when the hold begins and ends (Step 5.2), and by the ProximityPrompt at
+	Step 6.3.
+
+	A STUCK `true` COSTS RATE-LIMIT TOKENS AND NOTHING ELSE. The server re-measures distance on every
+	tick, so a client left holding while its player walks away accumulates zero — the failure is a
+	throttled player, not a free task, and it is self-inflicted. That is the property to preserve if
+	this ever grows a second caller.
+]]
+function TaskController.SetHolding(value: boolean)
+	holding = value
+end
+
+function TaskController.Init()
+	latest = nil
+	holding = false
+end
+
+function TaskController.Start()
+	Remotes.Get("TaskProgressChanged").OnClientEvent:Connect(function(payload: Types.TaskProgressPayload)
+		latest = payload
+
+		if Config.Debug.VerboseLogging then
+			local fill = if payload.YourTaskProgress ~= nil
+				then `{math.floor(payload.YourTaskProgress * 100)}%`
+				else "-"
+
+			print(`[Task] {payload.TasksCompleted}/{payload.TasksRequired} · here: {fill}`)
+		end
+	end)
+
+	--[[
+		THE HEARTBEAT. It reports PRESENCE and only presence — no task id, no elapsed time, no progress,
+		no completion. `FireServer()` with no arguments is the entire message, and the server ignores
+		anything a modified client adds to it because the handler's signature takes none.
+
+		The interval is Config's, and tests/config.test.luau pins its reciprocal below
+		AntiCheat.Budgets.RequestTaskProgress.RefillPerSecond so an honest hold never throttles itself.
+	]]
+	task.spawn(function()
+		while true do
+			if holding then
+				Remotes.Get("RequestTaskProgress"):FireServer()
+			end
+
+			task.wait(Config.Tasks.HeartbeatInterval)
+		end
+	end)
+end
+
+return TaskController
```

and the registration:

```diff
 local CONTROLLER_ORDER = {
 	"AudioController",
 	"CameraFXController",
 	"UIController",
 	"QuickChatController",
+	"TaskController",
 	"InputController",
 }
```

**Before `InputController`, deliberately.** The order governs `Init`/`Start`, not requires — the require
is direct, exactly as `InputController` already requires `UIController` — but `InputController.Start`
binds a key that calls into this controller, and a bind that can fire before `Init` has run is a race
worth not having.

**`npm run analyze` is the check.** The likely failure is `payload.YourTaskProgress * 100` on a `number?`
without the `~= nil` narrowing, which is an analyze error and not a runtime one.

#### Step 5.2: The `E` bind — hold begins, hold ends

**File:** `src/client/Controllers/InputController.luau`
**Verify:** `npm run lint`

`ContextActionService` with `Begin` and `End`, matching the `T`/`F` binds already there. `E` because it
is ProximityPrompt's default key, which makes Phase 6 a swap rather than a rewrite.

```diff
+local TaskController = require(script.Parent.TaskController)
 local UIController = require(script.Parent.UIController)
```

```diff
 local TRANSFORM_ACTION = "AswangTransform"
 local KILL_ACTION = "AswangKill"
+local TASK_ACTION = "TaskHold"
```

```diff
+--------------------------------------------------------------------------------
+-- The hold (§4.4, C08)
+--------------------------------------------------------------------------------
+
+--[[
+	THE TWO BINDS ABOVE GATE ON UIController.GetMyRole(). THIS ONE MUST NOT, AND THE ABSENCE IS THE
+	SECURITY PROPERTY.
+
+	A role gate here would be a client that behaves differently depending on who it is, and every one
+	of those is a confession waiting to be recorded. The transform and kill binds can afford it because
+	the actions they guard are the Aswang's alone and visible when used; a task is something all eight
+	players do all round, so an Aswang whose client sent no heartbeat — or sent one at a different rate,
+	or stopped when the bar stopped — would be distinguishable from a survivor's by anyone who could
+	watch the wire, and identical-looking to anyone who could not only by accident.
+
+	SO: THE ASWANG'S CLIENT SENDS EXACTLY WHAT A SURVIVOR'S SENDS. C12 makes the server value it at
+	zero. Nothing on this side of the boundary knows the difference, which is the only arrangement that
+	is still true when the client is compromised.
+
+	Cancel is handled alongside End: ContextActionService raises it when a bind is unbound or the input
+	is interrupted, and treating it as Pass would leave `holding` true forever. See Follow Ups — this
+	is the one enum member in the plan that is not already used elsewhere in this repository.
+]]
+local function onTaskAction(
+	_actionName: string,
+	inputState: Enum.UserInputState
+): Enum.ContextActionResult
+	if inputState == Enum.UserInputState.Begin then
+		TaskController.SetHolding(true)
+
+		return Enum.ContextActionResult.Sink
+	end
+
+	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
+		TaskController.SetHolding(false)
+
+		return Enum.ContextActionResult.Sink
+	end
+
+	return Enum.ContextActionResult.Pass
+end
```

```diff
 	ContextActionService:BindAction(TRANSFORM_ACTION, onTransformAction, false, Enum.KeyCode.T)
 	ContextActionService:BindAction(KILL_ACTION, onKillAction, false, Enum.KeyCode.F)
+	-- `E` because it is ProximityPrompt's default key, so Step 6.3 is a swap rather than a retraining.
+	-- `false` for createTouchButton matches the two binds above: mobile is C27's subject, and this is a
+	-- known hole rather than an oversight. It is a WORSE hole here than for the other two — 60% of the
+	-- audience per §5, and tasks are what all eight players do all round.
+	ContextActionService:BindAction(TASK_ACTION, onTaskAction, false, Enum.KeyCode.E)
```

**`npm run lint` is the check.** selene is what catches the shape this step is most likely to ship: an
unused `TaskController` require if the bind is added and the handler is not, or a shadowed
`inputState`. It is a weaker gate than `analyze` and it is the honest one for a file whose real
verification is a human pressing `E`, which Phase 6's playtest provides.

#### Step 5.3: The role gate that must NOT be added here

**File:** `src/client/Controllers/TaskController.luau` + `src/client/Controllers/InputController.luau`
**Verify:** `npm run check:secrecy`

A read of the whole client task path against the one question that matters: is there anything on it
that differs between the Aswang's client and a survivor's?

The answer must be no, in all four of these, and each is a line someone will be tempted to add:

| Tempting addition | Why it is refused |
| --- | --- |
| Gate the `E` bind on `GetMyRole()` | Step 5.2's header. The Aswang's client must send what a survivor's sends. |
| Grey out the prompt on a task the Aswang cannot complete | Renders the server's refusal on screen. It is the oracle, drawn. |
| Cache `TasksCompleted` and compare it to a locally-predicted value | A client that can detect "my hold did not count" has computed its own role from timing. C12's whole job is to make that *not* be visible; predicting it locally defeats C12 before it is written. |
| Log `YourTaskProgress` alongside `GetMyRole()` | The two facts are separately harmless. `check:secrecy` reads neither line. An `exploit-auditor` reads both. |

**`npm run check:secrecy` is the check**, and rule 3 is the one doing work: `AswangUserId` appearing
anywhere under `src/client/` fails, whether it is received or merely guessed at. It will not catch the
third row of that table, which is why the row is written down — and why `exploit-auditor` is mandatory
on this plan regardless of what any gate reports.

#### Phase 5 — Potential Issues

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

- **`Enum.UserInputState.Cancel` is the one unverified API in this phase.** It is used nowhere else in
  this repository. If it does not raise as expected, `holding` sticks `true` and the client burns
  rate-limit tokens; it does not gain progress, because the server re-measures distance. Follow Ups
  question Q2.
- **Mobile cannot do tasks yet.** `createTouchButton` is `false`, matching the transform and kill binds,
  so 60% of the audience per §5 has no way to complete an objective. That is C27's subject and it is a
  bigger hole here than for the other two binds — a mobile player can at least *watch* a transform.
  Named so it is not rediscovered as a bug.
- **No §3 OUT-list token reaches the client.** The controller renders a bar and sends an empty request.
- **`YourTaskProgress` is a `number?` and the HUD is not built yet.** C18 inherits a field that is
  legitimately nil most of the time; a bar that renders nil as 0 and a bar that hides itself are
  different designs, and this plan picks neither.

### Phase 6: The ProximityPrompt affordance — unconfirmed API, isolated on purpose

`ProximityPrompt` appears **zero times** in `src/` today. Hard Rule 1 says do not guess a Roblox API, so
this phase begins by confirming the behaviour in Studio and is last so that a run which stops short still
leaves C08 complete and playable on the `E` bind.

#### Step 6.1: Confirm ProximityPrompt's hold events in Studio

**File:** `.claude/plans/feature-c07-map-c08-hold-plan/artifacts/proximity-prompt-probe.md`
**Verify:** `test -f .claude/plans/feature-c07-map-c08-hold-plan/artifacts/proximity-prompt-probe.md`

Four specific questions, each with a stated consequence. No game code is written.

**The design this phase commits to before asking anything**, because it is what keeps the questions
small: **the ProximityPrompt is an affordance and decides nothing.** It says "there is a task here, hold
E". The presence signal stays the `ContextActionService` bind from Step 5.2, and the timing stays the
server's tick from Step 3.3. A prompt with `HoldDuration = 8` would fill on the *client's* clock and
finish at a different moment from the server's bar, which is the one thing C08 is named for not doing.

| Probe | Consequence if the answer is not the expected one |
| --- | --- |
| Does a `ProximityPrompt` created on the SERVER and parented to an anchored `BasePart` appear for a client at all? | If not, prompts move to `TaskController` creating them locally off the `ActiveTaskPoint` tag — client-side decoration over server-side truth, which is legal and slightly more code. |
| With `HoldDuration = 0` and `KeyboardKeyCode = E`, does the prompt's own input conflict with the `E` bind — does one sink the other, does the prompt fire `Triggered` on every press? | A `Triggered` per press is harmless (nothing listens). If the bind stops receiving `Begin`, the prompt takes `KeyboardKeyCode = Unknown` and becomes purely visual. |
| What are `MaxActivationDistance` and `RequiresLineOfSight` defaulted to, and does setting the first from `Config.Tasks.PresenceRangeStuds` make the prompt appear exactly where the server would accept presence? | If they disagree, the prompt is showing an affordance the server refuses — the worst of the three outcomes, and the reason this question is asked before any code. |
| Does `Enum.UserInputState.Cancel` actually raise for a `ContextActionService` bind, and when? | Follow Ups Q2. If it never raises, `holding` can stick `true`; the cost is rate-limit tokens, never progress. |

Run through `execute_luau` against a `TaskPoint_01` from the Step 2.1 rig, and record the output and a
`screen_capture` verbatim. **A probe that cannot be run is a recorded answer of "unknown" and Step 6.3
proceeds on the fallback column** — it is not a reason to skip the artifact.

#### Step 6.2: The server creates and destroys the prompts

**File:** `src/server/Services/TaskService.luau`
**Verify:** `npm run verify`

One prompt per selected point, created alongside the `ActiveTaskPoint` tag and destroyed with it. The
prompt is an affordance; it decides nothing.

```diff
+--[[
+	The affordance §4.4 names, and NOTHING ELSE. HoldDuration is zero on purpose: a prompt that held for
+	HoldTime would fill on the CLIENT's clock and complete at a different moment from the server's bar,
+	which is precisely the thing "server-timed" rules out. The prompt says a task is here; Step 3.3
+	decides whether it is being done.
+
+	MaxActivationDistance is read from the same Config value the server validates against, so a prompt
+	is never visible at a distance the server would refuse. Those two numbers disagreeing is the failure
+	mode Step 6.1 asks about first — a player holding at a prompt that does nothing has no way to tell
+	that from a broken game.
+]]
+local function attachPrompt(part: BasePart)
+	local prompt = Instance.new("ProximityPrompt")
+
+	prompt.Name = "TaskPrompt"
+	prompt.ActionText = "Hold"
+	prompt.ObjectText = "Task"
+	prompt.HoldDuration = 0
+	prompt.MaxActivationDistance = Config.Tasks.PresenceRangeStuds
+	prompt.RequiresLineOfSight = false
+	prompt.Parent = part
+end
+
+local function detachPrompt(part: BasePart)
+	local prompt = part:FindFirstChild("TaskPrompt")
+
+	if prompt ~= nil then
+		prompt:Destroy()
+	end
+end
```

wired into the two places that already own a chosen part's lifetime:

```diff
 		activeParts[point.Id] = part
 		CollectionService:AddTag(part, TAG_ACTIVE)
+		attachPrompt(part)
```

```diff
 	for _, part in activeParts do
 		CollectionService:RemoveTag(part, TAG_ACTIVE)
+		detachPrompt(part)
 	end
```

**The prompt carries no secret and no per-player state.** `ActionText` and `ObjectText` are the same
strings for all eight players; there is no branch on role anywhere in this step, and there must never
be one — a prompt that read differently for the Aswang would be §4.4's fake list rendered into the
world, which is not what §4.4 asks for and is a confession on a stream.

**`npm run verify` is the check** — the full gate, once, at the point where every file this plan touches
is present. It is the only step that runs it, and it is worth its ~15 seconds here: this is the last
step in the plan that changes server code.

#### Step 6.3: Apply the probe's answers to the prompt and the bind

**File:** `src/client/Controllers/TaskController.luau`

Whatever Step 6.1 recorded, applied: a `KeyboardKeyCode` change if the prompt and the bind fight over
`E`, client-side prompt creation if a server-created one does not appear, a `MaxActivationDistance`
correction if the prompt's reach and the server's disagree.

**This step deliberately has no `**Verify:**` line.** What it changes is how a prompt looks and feels to
a person standing in front of it, and there is no command in this repo that can read that. Inventing a
`grep` here would report green on text being typed and would tell the loop that a phase built on an
unconfirmed API had been proven. `verify-plan` reports this step as `unverifiable`, `next-phase.mjs`
marks Phase 6 `needs-human`, and a person is asked — which is the correct answer and the reason this
phase is last.

**The playtester is what closes this phase**, and its brief is C08's stated Done condition, not this
step: hold a task to completion in `HoldTime`; walk away mid-hold and show the bar freezes rather than
resets; then fire `RequestTaskProgress` in a loop from `execute_luau` while standing nowhere near a task
and show that nothing moves. That third one is 🔒 mandatory and is the artifact this plan is judged on.

#### Phase 6 — Potential Issues

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

- **This whole phase rests on an API this repository has never used.** That is why it is last, why it
  opens with a probe, and why C08 is complete and playable without it — Phases 1–5 leave a working
  hold on the `E` bind. A run that halts at Phase 5 has shipped the chunk.
- **A prompt is a per-task Instance in the workspace.** Five of them, no lights, no particles. Against
  §5's mobile budget that is negligible; a prompt per point in the *pool* rather than per *selected*
  point would be twelve, and would also tell every client which twelve exist, which is information the
  tag deliberately does not give.
- **`MaxActivationDistance` and `PresenceRangeStuds` must not drift apart.** They are the same number
  today because this step reads Config. If C18 hardcodes a prompt distance, the affordance and the
  validation disagree and the symptom is "the game randomly ignores me".
- **Scope:** a ProximityPrompt is §4.4's stated interaction. Nothing here is a weapon, an inventory or
  a second monster.

## 3. Related Files

Every file below was read while planning. Annotated excerpts are in `references/`.

| File | Read for | Created / changed here |
| --- | --- | --- |
| `docs/BUILD-PLAN.md` §3 | C07 and C08's definitions and Done conditions | — |
| `docs/MVP-SPEC.md` §4.4, §4.7, §4.8, §5, §6.4 | tasks, ghosts, the win, the mobile budget, the edge cases | — |
| `src/shared/pure/TaskSelection.luau` | the draw, and the seed warning that binds this plan | unchanged — already proven |
| `tests/task-selection.test.luau` | what the draw is already proven to do, incl. the spacing fallback | unchanged |
| `src/server/Services/TaskService.luau` | the stub's header, which is the chunk's specification | **replaced body, header kept** |
| `src/server/Services/RoundService.luau` | phase ownership, the snapshot, `Start`'s loop shape, the C07 seam | **+`SetTasksCompleted`, −1 TODO** |
| `src/server/Services/MonsterService.luau` | the reference for a service that subscribes to phase and converts at the call site | unchanged |
| `src/server/Services/AntiCheatService.luau` | `Consume`'s name and the 1200-character proximity rule | unchanged |
| `src/server/pure/RoleDraw.luau` | why a pure module lives under `server/` | unchanged |
| `src/shared/Types.luau` | `ActiveTask`, and three payload comments about what the typechecker misses | **+3 types** |
| `src/shared/Remotes.luau` | both remotes already declared, in the right lists | **unchanged — no new remote** |
| `src/shared/Config.luau` | `Tasks.*`, `AntiCheat.Budgets.RequestTaskProgress`, `Ghost.TaskContributionMult` | **+3 knobs** |
| `tests/config.test.luau` | the 26 pinned relationships and the count in its final print | **+3 invariants** |
| `src/server/init.server.luau` | `SERVICE_ORDER` — `TaskService` is already listed | unchanged |
| `src/client/init.client.luau` | `CONTROLLER_ORDER`, and the M1 snapshot smoke test | **+1 entry** |
| `src/client/Controllers/InputController.luau` | the `T`/`F` binds, and the role gate this one must not copy | **+1 bind** |
| `src/client/Controllers/UIController.luau` | where the local role lives, and why nothing else may read it | unchanged |
| `.claude/scripts/check-config.mjs` | the `config-ok` waiver, and which literals are idiomatic | — |
| `.claude/scripts/check-secrecy.mjs` | what the tag and payload rules actually inspect, and what they miss | — |
| `.claude/scripts/verify-plan.mjs` | why every step in a phase needs its own check | — |

**New files:** `src/server/pure/TaskPool.luau`, `src/server/pure/TaskProgress.luau`,
`src/client/Controllers/TaskController.luau`, `tests/task-pool.test.luau`,
`tests/task-progress.test.luau`.

## 4. Follow Ups

### Questions / Clarifications

**Q1 — Should a round with an unusable pool abort instead of running?** This plan says no: it warns
loudly and lets the round run on the sunrise timer and C06's attrition win. Aborting would need
`RoundService.EndRound(ABORTED)`, which only fires in `ACTIVE`, and the discovery happens in `STARTING`
— so it would mean a new transition, which is the state machine, which is the thing this repo is most
careful about. The current answer keeps the ownership clean and makes the failure a console fact rather
than a gameplay event. Worth revisiting only if C17 turns out to break the pool often.

**Q2 — `Enum.UserInputState.Cancel`.** Used nowhere in this repository. The plan handles it alongside
`End`; if it never raises, `holding` can stick `true` and the client burns rate-limit tokens without
gaining progress. Confirmed by Step 6.1's fourth probe, not by assumption.

**Q3 — `ProximityPrompt` in its entirety.** Zero occurrences in `src/`. Every property this plan sets
(`HoldDuration`, `MaxActivationDistance`, `RequiresLineOfSight`, `ObjectText`) is stated from the API
surface and **not** from anything observed in this codebase. That is why Phase 6 is isolated and last.

**Q4 — Ghosts are currently refused, and §4.7 says they should not be.** `evaluatePresence` returns
`NOT_ALIVE` for a `GHOST`, so a dead player cannot contribute at 25%. That is correct for C08 — ghosts
do not exist until C15 — and it is a behaviour C15 must change in exactly two places, `evaluatePresence`
and `weightFor`. Recorded so C15 does not have to rediscover both.

**Q5 — `Config.Tasks.PoolSize` is now advisory.** Discovery counts whatever is tagged; `PoolSize` only
drives the `OVERSIZED` warning. §4.4 says twelve, so the number is meaningful — but nothing enforces it,
and after C17 the map is the authority. Consider whether `PoolSize` should be deleted at C17 rather than
left as a number that can disagree with reality.

**Q6 — `check-secrecy.mjs` has no field allowlist for `TaskProgressChanged`.** `Types.luau` already
proposes one for the two reveal remotes; this plan adds a third payload whose safety rests on a field
name never appearing (`PresentPlayerCount`, `HolderCount`, `Contributors`). A harness change with its
own self-test obligations, and out of scope here.

### Issues Found

| Phase | Issue | Severity | Status |
| --- | --- | --- | --- |
| 1, 4 | **R1 — nothing enforces that `TaskProgressChanged` is per-player.** A later author reaching for `FireAllClients` with the same typed payload passes `analyze`, `check:secrecy` and `check:remotes`, and hands every bystander a per-task bar. §1.4 decision 2 is the entire defence and it is prose. | 🔴 High | Open — `exploit-auditor` brief |
| 3 | **R2 — nothing enforces that the contribution rate is a MAX and not a SUM.** Changing it looks like a feature ("teamwork should be faster") and would make the Aswang's zeroed weight visible to bystanders at C12. `tests/task-progress.test.luau`'s non-scaling assertion is the only thing that would object. | 🔴 High | Mitigated by test |
| 2, 3 | **R3 — the Aswang miming at a task and never completing it is an inherent tell.** §4.4 says the Aswang "can fake-perform the animation", so a survivor who watches someone stand on a task for 20 seconds with no completion has learned something. This is spec-level and pre-existing, not created by this plan, and C12 is where it is traded off. | 🟡 Medium | Accepted (spec §4.4) |
| 2 | **R4 — `RoundService.luau:578`'s TODO instructs a require cycle.** Deleted at Step 3.4. Between Phase 2 and Phase 3 the tree contains both the working subscription and the comment recommending the cycle. | 🟡 Medium | Closed at 3.4 |
| 2 | **R5 — the test rig is invisible to Git and one Studio session from being wrong.** Every C08 verification depends on twelve parts in a gitignored binary. The artifact from Step 2.1 is the only record that they existed and what they were. | 🟡 Medium | Mitigated by artifact |
| 1, 3 | **R6 — `PresenceRangeStuds * 2 < MinSpacingStuds` is load-bearing for correctness, not tidiness.** Tuning it away at M12 makes `taskPointAt` return an arbitrary one of two answers. Pinned in `config.test.luau`, and the comment on the knob says why. | 🟡 Medium | Mitigated by test |
| 6 | **R7 — Phase 6 rests entirely on an unconfirmed API.** Isolated last so a run that stops short still ships a complete C08 on the `E` bind. Step 6.3 carries no check and reports `needs-human` by design. | 🟢 Low | Open by design |
| 5 | **R8 — mobile cannot complete a task.** `createTouchButton` is false, matching the existing binds. 60% of the audience per §5. C27's subject; worse here than for transform or kill. | 🟢 Low | Deferred to C27 |
