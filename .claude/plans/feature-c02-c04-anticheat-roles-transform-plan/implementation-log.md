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

---

## Phases 2–7 (retro-documented)

**This section was written after the fact, and that is itself a finding.** The log stopped at Phase 1
when the `/build` loop halted, and was not resumed — so an auditor tracing Phases 2–7 had to verify 26 of
31 steps from the diff alone. `CLAUDE.md` treats this file as the thing an auditor traces against; an
absent log does not mean absent work, but it costs a reviewer the ability to tell the difference.

### Phase 2–3 — C02, the rate limiter
`pure/TokenBucket.luau` + `AntiCheatService`. Clamps AND re-anchors on a backwards clock; the test pins
the re-anchoring specifically, since clamping alone passes a naive test. Fails closed on an unbudgeted
remote. Stores the refilled bucket on the refusal path (discarding it freezes tokens permanently).

### Phase 4–5 — C03, the secret
`server/pure/RoleDraw.luau` (NOT shared — see the file header), `RoleService`, the private intro.

**Deviation 1 — RNG warm-up.** The plan's Park–Miller LCG failed its own "different streams draw
different Aswangs" check: the first output for seed *n* is `n·16807/2^31`, so seeds 1–50 all yield
< 0.0004 and roll into the bottom of the cumulative range, drawing the same candidate. Added
`RNG_WARMUP = 10`. Verified by the auditor as a real defect, correctly fixed, not weakening the test.

**Deviation 2 — `drewAswang`.** The plan's assignment loop did not typecheck. Root cause, measured over
six attempts: **generalized iteration widens a singleton union** — `for k, v in { [K]: "A"|"B" }` yields
plain `string`, and no cast, typed local or typed helper repairs it because each receives an
already-widened value. Fixed by reducing the iterated value to a boolean at the loop boundary and
writing bare literals. Distinct from the `Enums.X` widening CLAUDE.md documents, where a cast DOES work.

### Phase 6–7 — C04, the transform
`pure/TransformRules.luau`, `MonsterService`, and the three client controllers.

**Deviation 3 — inline `Consume`.** `check:ratelimit` is a PROXIMITY tripwire (1200 chars from the
`OnServerEvent:Connect`). A named handler rate-limited 250 lines away reads as unguarded. The guard now
sits inline at the connect site, which is also where a reader will look.

**Deviation 4 — `Generation` counter** replacing the plan's `RevertThread` + `task.cancel`. Judged by the
auditor as strictly narrower and more robust — it removes the self-cancellation trap as a class. Cost:
`MonsterService`'s public API was silently narrowed to `Init`/`Start`; the plan exported
`IsTransformed`/`Revert` for C05 and C14 to call. **Carried forward as a known gap.**

**Miss — Step 7.3 was two-thirds undelivered.** The step names three client files; only
`CameraFXController` was wired. `grep -rn "RequestTransform" src/client/` returned nothing, so no client
could fire a transform and Step 7.5's "press T" was impossible. Caught by the auditor. Fixed:
`InputController` binds T via ContextActionService gated on the client's own role (UX courtesy, not
security — the server re-evaluates regardless); `AudioController` creates the stinger at the correct
range with an empty SoundId, deferred to C29.

### Post-audit security fixes (exploit-auditor, C04 gate FAILED then re-fixed)

1. **Critical — the revert branded the Aswang permanently.** `removeLook` restored hardcoded defaults
   (white / Plastic / scale 1.0) instead of captured originals, making the ex-Aswang the only character
   in the game with those exact values — readable map-wide, retroactively, with no remote to intercept.
   It also defeated the mechanic outright: §4.3's revert exists so the Aswang blends back in. Fixed with
   `captureLook`/`restoreLook`, mirroring the discipline `BaseWalkSpeed` already had.
2. **High — revert fired for a transform never applied.** `Transformed` is set before the windup, so a
   revert during it ran full cleanup and a broadcast for a player nobody saw transform. Split into
   `Applied` (cleanup) and `Announced` (broadcast); added `AppliedTo` so cleanup targets the character
   that was changed rather than whatever the player is wearing now.
3. **Medium — the windup was invisible.** Nothing was applied until after `task.wait(TransformTime)`.
   The tell now starts with the windup and escalates, which is the entire risk half of §4.3.
4. **Medium — an Aswang could void a round by quitting during STARTING.** `onPlayerRemoving` guarded
   only on ACTIVE, while the role card shows for the whole of StartingDelay. Now covers STARTING too,
   and RoleService's comment claiming it was handled — which it was not — is corrected.
5. **Low** — forced-revert timer registered before the broadcast (guarantees before announcements);
   `revert` reads rather than constructs state; effects tracked individually rather than destroying
   every PointLight/ParticleEmitter on the Head.

### Verification (playtester, live Studio)

Artifacts: `artifacts/console-01-bootstrap-roles-anticheat.txt`,
`artifacts/console-02-role-intro-secrecy-tkey.txt`, and `verification.md`.

Established: bootstrap loads 13 services with zero warnings and `RoleDraw` resolves (the plan's biggest
open question); the draw logs a count and never a name; `TransformRules`' precedence is correct live
(`WRONG_PHASE` in INTERMISSION, `NOT_ASWANG` in ACTIVE); the rate limiter let exactly 3 through before
refusing, with `Consume` demonstrably ahead of validation; no attributes or tags on Player, Character or
Humanoid.

**NOT established — the transform itself.** A 1-player SoloTesting round can never draw an Aswang:
`picks = clamp(AswangCount, 0, max(#candidates-1, 0))` is 0 for one candidate. Confirmed across three
ACTIVE phases. **C04's visual path needs two clients and cannot be solo-tested at all.**
