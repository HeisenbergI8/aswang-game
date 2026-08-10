# Implementation log — C02–C04 (AntiCheat, Roles, Transform)

Run `2026-08-10T14-31-09-604Z-C02-C04`. Branch `m1-round-state-machine`, on top of C01 (`dc06307`).

---

## Phase 1: Foundation — Config, Types, and the remote surface

Nothing gameplay-facing. Numbers, types and comments only, so Phases 2–7 never have to add a number
mid-flight and `check:config` is satisfiable from the first line of service code.

### Step 1.1 — `Config.AntiCheat` + `tests/anti-cheat-budgets.test.luau`

Added `Config.AntiCheat` with a budget for all eight `EVENTS_UP` remotes, `DefaultCost`,
`AllowUnbudgetedRemote = false` (fail closed), `LogOnly = true`, `LogThrottleSeconds`.

New test pins coverage in **both** directions — every remote has a budget, every budget names a real
remote — plus four relationships tied to spec numbers rather than to the budgets themselves:

- task-progress refill ≥ `1 / Round.SnapshotInterval` (a limiter slower than the HUD tick throttles a
  player for doing exactly what the game asked)
- one transform token available inside `Monster.KillCooldown` (else the limiter, not the cooldown,
  gates the monster)
- salt burst ≥ `Salt.CarryLimit`; ghost spook capacity ≥ `Ghost.SpooksPerRound`

**Verify:** `lune run tests/anti-cheat-budgets.test.luau` → `PASS 8 remotes budgeted + 7 invariants`

### Step 1.2 — role-draw weights + six new balance invariants

`Config.Roles` gains `BaseWeight = 1`, `RecentAswangWeight = 0.1`, `OlderAswangWeight = 0.4`.

Six assertions added to `tests/config.test.luau` making §4.2's "heavily reduced weight" checkable:
weights monotonic in recency, none zero (a zero weight is a **ban**, not a discount, and with
`MinPlayers = 3` it can leave a round with no eligible Aswang), history shorter than a full server,
`AswangCount < MinPlayers`, and `IntroDuration < StartingDelay` so the intro cannot still be on screen
when ACTIVE begins.

Trailing `print` count updated 13 → 19. It is prose, nothing asserts it, which is exactly why it gets
missed.

**Verify:** `lune run tests/config.test.luau` → `PASS 19 balance invariants`

### Step 1.3 — four new types

`TokenBucketState`, `RoleAssignedPayload`, `MonsterTransformedPayload`, `TransformVerdict` added to
`src/shared/Types.luau`, each above `RoundState`.

`RoleAssignedPayload` carries exactly one field, and its comment records why: `RoleAssigned` is on
`check-secrecy.mjs`'s REVEAL_ALLOWLIST so the scanner skips the call, and Luau silently accepts an
**extra** field on an annotated table (measured during C01). Both guards are off there, so the type is
documentation backed by a habit — which is why `exploit-auditor` gates Phase 5.

`MonsterTransformedPayload` deliberately carries no role string: "this character transformed" is a fact
about the world; "this player is the Aswang" is an inference the client may make and the server never
states. That distinction matters at C14, where salt forces a revert on someone who is still the Aswang.

**Verify:** `npm run analyze` → `ok`, 0 errors

### Step 1.4 — remote surface audit, comment-only

Confirmed by reading that all three needed remotes already exist in the correct direction lists:
`RoleAssigned` and `MonsterTransformed` in `EVENTS_DOWN`, `RequestTransform` in `EVENTS_UP`. **No remote
added.** Comments now record which chunk wires each.

Honest limit, carried from the plan: `check:remotes` reports declared-but-unwired as a NOTE and never a
failure, so this step's check does not prove those three exist — it proves nothing in the tree *uses* an
undeclared or wrong-direction remote. The existence half is proven by reading.

**Verify:** `npm run check:remotes` → `ok (18 declared, 3 wired)`

### Step 1.5 — Phase 1 gate

**Verify:** `npm run verify` → green. analyze 0 errors; remotes, secrecy, config, scope, ratelimit all
ok; `test:unit: 3 file(s) ok`.

### Notes carried forward

- `check:ratelimit` still passes **vacuously** — there are no `OnServerEvent` handlers in the repo at
  all. It stays vacuous until Step 6.3. A green tree at the end of Phase 3 says nothing about whether
  the limiter runs.
- The `EVENTS_UP` name list is duplicated between `Config.luau` and the new test because `Remotes.luau`
  calls `game:GetService` at module scope and Lune cannot require it. Both directions are pinned inside
  the test; the residual gap (a remote added to `Remotes.luau` and nowhere else) is C41's sweep.
