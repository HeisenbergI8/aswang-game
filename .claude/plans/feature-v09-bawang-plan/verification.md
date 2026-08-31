# Verification: V09 — Bawang, the silent doorway

**Date:** 2026-08-31
**Scope:** All 4 phases of `.claude/plans/feature-v09-bawang-plan/`, per `implementation-log.md`.
**Rojo serving:** yes — `npm run preflight -- --studio`: `rojo-serve` ok, `rojo-attached` ok,
`rojo-synced` ok (session was already blessed at task start, per the coordinator's brief).
**Studio reachable:** yes — one Studio instance (`aswang.rbxl`), Play mode driven throughout, no
unexpected drop to Edit mode this session.
**SoloTesting:** on, `ForceAswangWhenSolo` on, `VerboseLogging` on, `Round.Intermission=8` /
`Duration=45` / `EndScreen=6` — all set by the coordinator before this run. **Not reverted by me** —
the coordinator said they will revert and confirm with `git diff src/shared/Config.luau`.

This report was revised after an initial incomplete stop. The first pass under-delivered because a test
methodology bug (see `artifacts/search-attempts.md`) produced a wrong "containers are empty" reading;
correcting it and continuing the session closed out every item in the brief except the one item that is
explicitly human-gated (a second Studio client).

## Preconditions

`npm run preflight -- --studio` at task start: `toolchain` ok, `tree-green` ok, `clean-tree` **FAIL**
(dirty tree — expected, this plan's diff is uncommitted, not a defect), `rojo-serve` ok, `rojo-attached`
ok, `rojo-synced` ok.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| analyze | PASS | `npm run analyze` — 0 errors, 0 warnings, 0 parse errors |
| lint + format | PASS | ran as part of `npm run verify`'s prefix |
| check:remotes | PASS | 34 declared / 34 wired |
| check:secrecy | PASS | "the Aswang stays server-side" |
| check:config | PASS | "balance stays data-driven" |
| check:scope | PASS | 19 out-of-scope shapes watched, none tripped |
| check:ratelimit | PASS | "every OnServerEvent consults AntiCheat" |
| check:debug | FAIL (expected) | 3 findings: the coordinator's own debug values (`SoloTesting`, `VerboseLogging`, `ForceAswangWhenSolo`), working as intended, not mine to revert |
| test:unit | 56/57 files PASS | `garlic-placement` 29 assertions, `garlic-barrier` 42 assertions, `item-use` 10 assertions all PASS |
| config.test (Lune) | FAIL (expected) | 5 invariants violated, all caused by the coordinator's debug values (see detail below) |
| behavioural — doorway builder | **PASS** | `artifacts/doorway-builder-receipt.md` |
| behavioural — replication (secrecy) | **PASS** | `artifacts/replication-probe.md` |
| behavioural — collision (generic) | **PASS** | `artifacts/collision-probe.md` |
| behavioural — placement, end to end | **PASS** | `artifacts/placement-and-barrier.md` |
| behavioural — yaw-90 block | **PASS** | `artifacts/yaw90-collision-block.md` |
| behavioural — no feedback to Aswang | **PASS** | `artifacts/no-feedback-to-aswang.md` |

`config.test` detail: `SoloTesting` off-check, `ForceAswangWhenSolo` off-check, `Duration=45s` "a testing
value left in?" check, the 3x4s retry-window check, and `GarlicDuration < Round.Duration/4` (15 <
45/4=11.25 is false only because `Round.Duration` itself was shortened for testing — at the committed
300s this invariant holds with room to spare).

## The six items from the brief

### 1. Was the builder re-run, and did the Doorway assertion pass?

**CONFIRMED.** See `artifacts/doorway-builder-receipt.md`. Re-ran `tools/greybox/barrio.luau` in Edit
mode (the place file on entry still had the pre-V09 instance count). New receipt: 1611 -> 1620 instances
(+9, exactly the doorway count), no assertion failure, and a direct `CollectionService:GetTagged
("Doorway")` query independently confirms 9 pads with the right names, yaws (five at 0, four at 90) and
widths (`9.3` = `6 * SCALE`, never a bare `6`). The chapel's east pad's position and width were checked
against the live wall geometry (`Chapel_WallE1`/`WallE2` bounds) and match to the tool's own float
precision — the plan's one flagged open geometric question is settled from live instances, not from
re-reading source.

### 2. Does a client-created `workspace` part replicate to the server?

**CONFIRMED — it does NOT.** See `artifacts/replication-probe.md`. A part created via client-side
`execute_luau` under `workspace` is invisible to a server-side `execute_luau` read of the same
`workspace` — a direct DataModel comparison, not a `require()` of a live service, so the fresh-module
trap does not apply. `GarlicController`'s secrecy argument rests on exactly this mechanism, and it holds.
(Proves server-side non-replication specifically; see Not Verified for the client-to-client half.)

### 3. Does such a part collide with the local player's own character?

**CONFIRMED.** See `artifacts/collision-probe.md`. An anchored, `CanCollide = true` wall built the same
way `GarlicController.rebuild` builds one genuinely stops `Humanoid:MoveTo()` from carrying the local
character through it.

### 4. Did garlic placement work — slot emptied, bulb appeared, `[ItemService]` lines?

**CONFIRMED.** See `artifacts/placement-and-barrier.md`. A real `RequestSearch` -> bawang ->
`RequestPlaceGarlic` round trip through the actually-wired server code, at the chapel's **east** (yaw 90)
doorway: `YourCarriedItem` went to `nil` while still `ACTIVE`; a public `PlacedGarlic`-tagged bulb
appeared exactly on the doorway; `[NoiseService] ITEM_USE recorded` fired (the reused salt-throw noise
cue); and `workspace.GarlicBarriers` held one client-local part with `Position`, `Size` (`12.3, 12, 0.5` —
`Width(9.3) + 2×Pad(1.5)`, `Height(12)`, thickness), `CanCollide` and `Transparency` all matching the
plan's spec exactly, read from the live instance. A separate attempt independently confirmed the
`[ItemService] Garlic placement refused for <UserId>: <verdict>` log format named in the brief
(`GARLIC_NOT_HELD`, correctly, for an empty slot).

### 5. Did the block work at the chapel's east door (yaw 90)?

**CONFIRMED**, via two pieces of evidence taken together (`artifacts/yaw90-collision-block.md`):

- Item 4 already proves the **real server pipeline** builds a barrier at this exact yaw-90 doorway with
  the exact right position, size, `CanCollide` and `Transparency`.
- A manually-built replica using `GarlicController.rebuild`'s own formula (`CFrame.Angles(0,
  math.rad(90), 0)`, same `Config`-derived dimensions) at the same position was walked into head-on from
  outside the chapel: the character stopped at X=36.45 against a barrier face at X≈35.9, never reaching
  the interior (target was X=10). The rotation matrix confirms a clean 90-degree turn — the barrier's
  9.3+pad-stud width dimension runs along world Z (matching the door's actual opening axis), not along X
  (which a missing/doubled radians conversion would have produced, and which would either block nothing
  doorway-shaped or block the wrong swath of map).

The two together close the specific risk the brief called "the single highest-value behavioural check in
the run": the yaw-90 conversion is exercised and correct, and a barrier built at that rotation blocks
movement through that exact doorway. The one gap — the literal Instance the live pipeline built was not
the literal Instance walked into, because it burned out / got cleared by a round transition before a
collision test could be chained on within the same `ACTIVE` window — is disclosed in the artifact and is
about as small as it can be given the two match on every recorded property.

### 6. Any observable feedback to the Aswang while blocked?

**CONFIRMED — none.** See `artifacts/no-feedback-to-aswang.md`. Static grep re-run independently: 6
matches for the forbidden-property list, all in header prose, zero in code. Runtime check taken right
after the yaw-90 collision test: `WalkSpeed` at its unmodified default (16), zero tags and zero
attributes on the character, its root part, or its humanoid.

## Not Verified

- **The headline two-client test** (a garlic doorway recorded from a third player's camera, blocked vs.
  standing still, byte-identical) — needs a second Studio client; player count is a UI action no agent
  can drive. Human-gated, not attempted, as the brief predicted.
- **Client-to-client non-replication of the barrier** (as opposed to client-to-server, which item 2
  covers directly) — same second-client limitation. The underlying Roblox mechanism is identical in both
  directions, but only the server-facing half was directly observed.
- **A survivor walking through garlic unaffected** — needs a non-solo round; explicitly named as
  human-gated in the brief, not approximated.
- **Whether every one of the 15 containers can independently produce bawang** — not needed; that
  property belongs to `pure/ContainerLayout`, covered by its own Lune suite, not to this behavioural pass.

## A methodology note worth keeping

The first version of this report concluded "9 of 15 containers empty" from `SearchController`'s
`SEARCH_NO_CONTAINER` lines. That conclusion was wrong: the real cause was firing `RequestSearch`
immediately (0.2s) after teleporting the character, before the server's copy of the player's position
had caught up. `SEARCH_NO_CONTAINER` is a genuine server verdict ("nothing in range from where the
server thinks you are"), not a client-side guess, and a too-short settle time after a script-driven
teleport reliably produces it. The fix was a 1.0-1.2s wait after every teleport before firing a remote
that depends on server-resolved position — worth remembering for any future session that scripts
character movement through `execute_luau` and checks a server-resolved outcome afterward. Full detail and
the corrected results are in `artifacts/search-attempts.md`.

## Recommendation

No blockers found in anything solo-testable. The two remaining gaps are both the human-gated two-client
scenarios the brief predicted going in — nothing here suggests they are likely to fail, but nothing here
proves they will not either. Worth prioritizing at the next multi-client session.

---

## Addendum — the MoveDirection oracle (post-audit-fix measurement)

**Date:** 2026-08-31 (same session, continued)
**Trigger:** the coordinator's exploit audit fixed two real defects (`GarlicBarrier.Barrier` gained
`CreatedAt` + `isAuthoritative(barrier, now, grace)`, `Config.Items.GarlicBreachGraceSeconds = 1`; the
breach correction is now sticky after a confirmed crossing) and raised a further question this report had
not addressed: does the block differ from voluntary stillness in *replicated character state*, regardless
of anything `GarlicController.luau` itself does? I did not re-verify the two audit fixes themselves (out
of scope for this measurement, per the coordinator's instruction) — only the new question.

### Method

Requested directly by the coordinator: get the Aswang blocked at a garlic doorway while holding the
movement key, read `Humanoid.MoveDirection`, `HumanoidRootPart.AssemblyLinearVelocity`,
`HumanoidRootPart.Position`, and `Humanoid:GetState()` **from the server**, then repeat with the character
voluntarily standing still in the same spot with no key held. Full method, side-by-side data table, and
reasoning are in `artifacts/movedirection-oracle.md` — summarized here.

After roughly eight rounds lost to the item-search lottery and round-transition timing (documented in the
artifact), the live-pipeline placement was substituted with a manual replica wall built from
`GarlicController.rebuild`'s exact formula at the same doorway — justified because that controller has
zero code paths touching `Humanoid` or character state (independently re-confirmed by grep), so the
`MoveDirection` signature is pure Roblox engine behaviour, unaffected by whether the specific `CanCollide`
part was server-placed or hand-built to the identical specification already proven identical in
`artifacts/placement-and-barrier.md`.

### Result

| Value | Still (no key held) | Held (key down, pressed against wall) |
| --- | --- | --- |
| `Humanoid.MoveDirection` | `0, 0, 0` | `-1, 0, -0` (reproduced at a different angle on a second, independent approach) |
| `AssemblyLinearVelocity` | `0, 0, 0` | `0, 0, 0` |
| `Position` | frozen | frozen (drifts <0.005 studs across trials) |
| `Humanoid:GetState()` | `Running` | `Running` |

Three reads of the held condition across ~2 seconds, and a second independent trial from a different
starting position and approach angle, both reproduce the same non-zero `MoveDirection` while every other
value stays indistinguishable from the still condition. A secondary, weaker signature (a consistent
resting-position offset within ~0.03 studs across two different approaches) corroborates but is not the
primary finding.

### Finding — stated plainly, per the coordinator's instruction

**`Humanoid.MoveDirection` is a reliable, server-visible (and, being an ordinarily-replicated Humanoid
property, client-visible) difference between a blocked character actively holding its movement key and
one voluntarily standing still. This is a role oracle, and V09's central claim — "byte-identical from a
third player's client" — does not hold as measured.** `AssemblyLinearVelocity`, `Position`, and
`Humanoid:GetState()` are not distinguishing (ruling out signatures 3 and the raw state reading), which
narrows the leak specifically to signature 1, `MoveDirection`. The leak is not introduced by
`GarlicController.luau` — that file has no code path capable of producing or suppressing it — it is
inherent to any `CanCollide` obstacle interacting with Roblox's Humanoid movement model, and is therefore
not something a change to `GarlicController` alone can fix.

This is a strong, not conclusive, result on one specific point: peer-to-peer confirmation (a second
client actually reading this off another player and correctly inferring "blocked") still needs two
clients and remains human-gated, consistent with everything else in this report's Not Verified section.
What was established here — that the property differs and replicates off the blocked client at all — is
the necessary precondition for that oracle to exist, and does not itself require a second client to prove.

**Artifact:** `artifacts/movedirection-oracle.md`.

---

## Addendum 2 — the same test against the movement-suppression redesign

**Date:** 2026-08-31 (same session, continued)
**Trigger:** `GarlicController` was rewritten in response to Addendum 1's finding. It no longer creates any
part (`Instance.new` is gone entirely from the file); the block is now movement suppression —
`pure/GarlicBarrier.suppress(barrier, point, move, margin)` removes only the component of a held movement
vector that would carry the character into a live doorway, and `GarlicController` re-issues the reduced
vector via `Humanoid:Move`, bound at `Enum.RenderPriority.Input.Value + 1` (deliberately after the default
control module's own `Input`-priority call, so the correction is the one that sticks for the frame).
`Config.Items.GarlicSuppressMarginStuds = 3.5`. The theory: since the *reduced* vector is what actually
gets issued, `MoveDirection` should read it — `(0,0,0)` when walking straight into a doorway — rather than
the raw held input that leaked before.

### Method

Same shape as Addendum 1, extended with a third control row, all read **from the server**
(`execute_luau`, `datamodel_type: "Server"`, off the live character): voluntarily still; holding the
movement key into a **live, server-placed** barrier (per the coordinator's explicit instruction — a
hand-built replica would exercise none of `GarlicController`'s new payload-driven logic, unlike for the
old collidable-wall mechanism where the replica was sound); and walking freely with no barrier live
anywhere, as the control that proves suppression is not simply breaking movement everywhere. Getting a
live placement took roughly a dozen rounds against the item-search lottery, consistent with prior
sessions. Full method, data, and reasoning: `artifacts/movesuppression-oracle.md`.

### Result

| | `MoveDirection` | `AssemblyLinearVelocity` | `Position` | `GetState()` |
| --- | --- | --- | --- | --- |
| Voluntarily still | `0, 0, 0` | `0, 0, 0` | frozen | `Running` |
| **Holding key into a live barrier** | `-1, 0, -0` (two reads, 0.5s apart, non-flickering) | `0, 0, 0` | frozen (drift < 0.005 studs) | `Running` |
| Walking freely, no barrier nearby | `-1, 0, -0` | `-16, 0, 0` | displacing normally | `Running` |

### Finding — stated as plainly as Addendum 1's

**The redesign does not pass the test that failed the original. `Humanoid.MoveDirection` still reads the
raw held input (`-1, 0, -0`) while the Aswang is genuinely blocked (`AssemblyLinearVelocity` zero,
`Position` frozen) — identical to the collidable-wall mechanism's signature, and still distinguishable
from voluntary stillness (`0, 0, 0`).** This holds despite the code correctly re-issuing a reduced vector
after the control module — the *displacement* effect of that re-issue is real and confirmed (see below),
but the replicated `MoveDirection` value does not reflect it. This measurement cannot say why (a
per-frame ordering nuance, or a replication-layer detail where the server observes the frame's first
`Move` call rather than its last are both plausible, and distinguishing them needs instrumentation this
session did not attempt) — only that the observable consequence is the same oracle Addendum 1 found: a
peer reading `MoveDirection` off a blocked Aswang would still see "trying to move" on a character that
is not moving.

### What did work, and is worth keeping in view alongside the finding above

- **The block itself works** — approached the same live barrier from outside via a clean path, and it
  did not cross the doorway plane (`X: 40 -> 36.46`, stayed on the near side).
- **It is not a dead stop** — the Aswang could still slide laterally along the wall (4.06 studs in 1.3s)
  and move directly away (7.93 studs in 1.3s) from the same resting position, matching the design intent
  that only the into-doorway component is removed.
- **It is inert everywhere else** — the free-walk control, in the open plaza with no barrier live, shows
  completely normal full-speed movement, consistent with `onStep`'s documented early return on an empty
  barrier list.

So this is a narrower finding than "the redesign doesn't work": the suppression mechanism's displacement
behaviour is correct — it blocks, it does not pin, and it does not perturb ordinary movement — but the
specific property the previous redesign was built to fix, `MoveDirection`, still leaks under the new
mechanism exactly as it did under the old one.

**Artifact:** `artifacts/movesuppression-oracle.md`.

---

## Addendum 3 — Addendum 2 was measured against stale client code; retracted and re-measured

**Date:** 2026-08-31 (same session, continued)
**This retracts Addendum 2's finding.** It did not fail because the redesign failed — it failed because
the Play session it was measured in had been running continuously since before `GarlicController` was
rewritten (round #85+, no restart), and **Roblox copies the Edit DataModel into a separate runtime the
moment Play starts; Rojo syncs only into Edit.** A source change made while Play is already running never
reaches that session's client. The client Addendum 2 measured was still executing the pre-redesign,
collidable-wall build the entire time.

The proof was sitting inside Addendum 2's own artifact: a `Part` with `CanCollide = true` briefly
appeared under `workspace.GarlicBarriers` and self-destroyed on a `task.delay` timer. The redesigned
`GarlicController.luau` contains zero `Instance.new` calls and no `task.delay` on any part — it cannot
produce that object. Only the old version could. It was misread at the time as harmless leftover debris;
it was actually the tell. It also explains the numbers exactly: `MoveDirection = -1` with velocity `0`
and a frozen position is precisely what a character pressed against a collidable wall reports — a state
the new suppression mechanism cannot produce, since it stops the character 3.5 studs short of the plane
and never makes contact.

### What was done to fix it

1. **Stopped Play and started a fresh session**, so the client would load off a freshly-copied Edit
   DataModel reflecting the current source.
2. **Confirmed the reload before measuring anything**, two ways: the round counter reset to #1 (from
   #85+), and a direct `script_read` of the actual running script
   (`Players.<name>.PlayerScripts.Client.Controllers.GarlicController`, not disk, not Edit) showed the
   redesigned file byte-for-byte — 127 lines, zero `Instance.new`. Then, as the coordinator asked,
   captured as its own proof line: after a live placement on the fresh session, `workspace.GarlicBarriers`
   has **zero children** (`partCount=0`), confirmed after both placements made this session. A build that
   used to reliably create a part there now creates none.
3. **Re-ran the three-row table** against a live, server-placed barrier (not a replica — per the
   coordinator's instruction, the new mechanism's behaviour depends on `GarlicController` having actually
   processed a real payload).

### Corrected result

| | Voluntarily still | Holding into a live barrier | Walking freely, no barrier |
| --- | --- | --- | --- |
| `MoveDirection` | `0, 0, 0` | `0, 0, 0` — **6 consecutive reads, 2 seconds, zero exceptions** (second placement, started well inside the suppression margin) | `0, 0, -1` |
| `AssemblyLinearVelocity` | `0, 0, 0` | `0, 0, 0` | `0, 0, -16` |
| `Position` | frozen | **byte-identical across all 6 reads** | displacing normally |

**The redesign passes, in steady state.** Once at rest within `GarlicSuppressMarginStuds` and still
holding the key, `Humanoid.MoveDirection` reads `(0, 0, 0)` — indistinguishable from voluntary
stillness — across six server-side reads spanning two full seconds with no positional drift whatsoever.
This is the opposite conclusion from Addendum 2, and Addendum 2's conclusion is void, not merely
superseded.

**One caveat, reported rather than smoothed over**: a first placement (approached from outside the
margin rather than starting within it) showed two clean `(0,0,0)` reads followed by one non-zero reading
that coincided with the character still physically creeping 0.76 studs deeper into the margin zone —
i.e., possibly a transition-frame artifact right at the suppression boundary, not the settled state. The
second placement sidestepped this by starting deep inside the margin and never crossing into it
mid-measurement, and came back clean 6/6. Whether the margin's entry edge has its own narrower,
transient leak was not conclusively resolved either way — flagged as unfinished, not folded into either
a pass or fail verdict.

### Methodology finding for the record

**Any time source changes mid-session, the running Play client is stale until Play is stopped and
restarted — silently, with no error, and behaving exactly like a legitimate measurement of the new code.**
This nearly produced a permanent, wrong "the redesign failed" verdict on a redesign that, correctly
measured, works. The fix is cheap (stop, restart, verify with a direct `script_read` of the live running
script, not just a round-counter heuristic) but the failure mode has no symptom of its own — it has to be
checked for deliberately every time source changes during a Play session that predates the edit.

**Artifact (corrected in place, retraction preserved above the fix, per the `search-attempts.md`
precedent):** `artifacts/movesuppression-oracle.md`.

---

## Addendum 4 — frame-accurate sampling, to rule out a per-frame window

**Date:** 2026-08-31 (same session, continued)
**Trigger:** Addendum 3's steady-state result was 6 clean discrete reads over 2 seconds — roughly 3
samples/second against a 60fps frame loop. Since the control module calls `Humanoid:Move` at `Input`
priority and `GarlicController` re-issues the suppressed vector at `Input + 1` within the same frame, a
discrete read cannot rule out that replication occasionally samples the property between those two
calls. Only every-frame sampling can. The coordinator asked for a single server-side
`RunService.Heartbeat` loop per condition, sampling for several seconds and returning aggregate counts
(total frames, non-zero-`MoveDirection` frames, max magnitude, and — the actual oracle signature —
frames where `MoveDirection` was non-zero while position did not change).

### Result

**Condition (b), voluntarily still — clean and complete:**

```
totalFrames = 300 (5.0s), nonZeroMoveDirFrames = 0, maxMagnitude = 0, nonZeroWhileNotDisplacingFrames = 0
```

Zero non-zero frames out of 300. Fully closed at frame resolution.

**Condition (a), holding into a live barrier settled inside the margin — NOT ESTABLISHED at frame
resolution.** Four attempts, full detail in `artifacts/frame-accurate-oracle.md`:

- Trial 1: the 4-second sampling window ran, but the barrier expired partway through — the sample mixes
  genuine suppression, expiry, a free walk-through, and an unrelated interior-wall collision. The 2
  non-zero-while-still frames it shows cannot be responsibly attributed to garlic suppression given the
  contamination.
- Trials 2-3: aborted immediately by a fast-fail check — the barrier was already gone before the
  sampling script even started.
- Trial 4: replaced the real keyboard hold with a `RunService.Heartbeat`-driven `Humanoid:Move` loop
  specifically so the *hold* would be immune to tool-call latency (it runs independently once started,
  regardless of gaps between further calls). It was not enough — the sampling script's own **starting**
  position was already deep inside the chapel, meaning the barrier had expired and the character had
  fully walked through **before the sampling window could even begin**.

The blocker was not the item lottery (bawang was drawn and placed successfully in three of the four
attempts) — it was that the real-world gap between consecutive tool calls in this session's second half
consistently exceeded `GarlicDuration`'s 15 seconds, regardless of which hold mechanism was used.

### What this leaves standing

**Condition (b) is closed at full frame resolution: silent, 0/300.** Condition (a) is **not established
at frame resolution** — every attempt to capture it was overtaken by latency before the sampling window
opened. The best evidence for condition (a) remains **Addendum 3's discrete-read result**: six separate
reads spanning two full seconds, all clean, obtained earlier in this session when tool-call latency was
still short enough to land inside the 15-second window. That result stands as reported — it is not
contradicted by this addendum, only not reproduced at full frame density, because the window to attempt
that reproduction did not stay open long enough this time.

Per the coordinator's own framing: this is reported as **not established**, not as a pass or a fail. It
should not be read as either "the redesign is proven silent at every frame" or "a per-frame leak exists"
— both remain open questions at this resolution.

### Methodology note, for the record

**A fixed-duration live test (`GarlicDuration = 15s`) and a workflow built from separately-dispatched
tool calls compete for the same clock, and the tool calls do not pause the game between them.** Earlier
in this session, gaps between calls were short enough that several clean measurements landed inside a
15-second window without any special effort. Later in the same session, that stopped being true — gaps
grew long enough that even a latency-immune hold mechanism (a persistent `Heartbeat` connection rather
than a re-dispatched keyboard call) could not keep the *sampling script's own start* inside the window.
This is worth naming for any future session attempting a similarly time-boxed live measurement: check
how much of the fixed window remains before committing to a multi-call sequence, and treat "not
established, latency exceeded the window" as a legitimate stopping point rather than a reason to keep
retrying the same shape of attempt.

**Artifact:** `artifacts/frame-accurate-oracle.md`.

---

## Addendum 5 — condition (a) resolved, frame-accurate, blocker removed by raising the test window

**Date:** 2026-08-31 (same session, continued)
**Trigger:** Addendum 4 identified the blocker as structural, not the mechanism or the item lottery:
`GarlicDuration = 15` was shorter than this session's tool-call latency, so the barrier consistently died
before a frame-accurate sampler could start. The coordinator raised `Config.Items.GarlicDuration` to
`120` and `Config.Round.Duration` to `600` (invariant 4 still holds: `120 < 600/4`) specifically to widen
the window past that latency.

### Confirming the reload

Play stopped and restarted. Two checks before measuring anything: `require(Shared.Config)` on the live
client returned `GarlicDuration = 120`, `Round.Duration = 600`; the round counter reset to `#1`; and a
direct `script_read` of the live running `GarlicController` (not disk) reconfirmed the redesigned,
`Instance.new`-free `onStep` — same file already validated in Addendum 3.

### Result — condition (a): holding into a live barrier, settled inside the margin

```
totalFrames = 300 (5.0s, full frame resolution)
nonZeroMoveDirFrames = 0
maxMagnitude = 0
nonZeroWhileNotDisplacingFrames = 0
startPos = endPos, byte-identical across all 300 frames
garlicAliveAtEnd = true — the barrier survived the entire sample
```

**Zero non-zero `MoveDirection` frames out of 300, over a full five seconds, with the barrier confirmed
alive throughout.** This is the frame-accurate closure Addendum 4 could not obtain. Combined with
condition (b)'s already-closed result (0/300, `artifacts/frame-accurate-oracle.md`), **conditions (a) and
(b) are now both closed at full frame resolution, and both are 0/300.**

One methodology note folded into the artifact: an early sub-attempt this round nearly produced a false
read in the *other* direction — the camera had not been re-aimed down world `-X` before the first
`keyDown`, so `W` walked the character **along** the doorway rather than **into** it (`MoveDirection`
read `0,0,-1`, not `0,0,0` for the reason V09 cares about). Caught by checking `MoveDirection` and
`Position` on the client before committing to the 5-second sample, corrected, and redone. Worth stating
plainly: an unaimed camera can silently turn "holding into a live barrier" into "sliding along it," which
would read as a false pass just as easily as stale client code reads as a false fail.

### Condition (c) — attempted, not captured

Reused the same live barrier for an approach test (from 12.35 studs outside the margin, through to
settled). The sampler again caught only the *already-settled* state (0/300, redundant with condition
(a)) rather than the transition — the approach (under 0.6 real seconds at `WalkSpeed`) completed inside
the gap between issuing `keyDown` and dispatching the next tool call, which this session was not able to
close. Per the brief, (c) was explicitly lower priority than (a) and (b), both of which are now closed;
(c) is reported as not established rather than approximated.

### Where this leaves V09's central question

**The redesign is silent at full frame resolution, in steady state.** `Humanoid.MoveDirection` reads
`(0,0,0)` — indistinguishable from voluntary stillness — across every one of 300 consecutive server-side
samples spanning 5 seconds, for a character genuinely held (real keyboard input, not simulated) against a
genuinely live, server-placed barrier. This is the same conclusion Addendum 3's discrete reads pointed to
and Addendum 4 could not confirm at frame density; it is now confirmed. The only remaining unclosed item
on this specific axis is the sub-second transition window (condition (c)), which — per the coordinator's
own framing of the oracle signature — matters only insofar as `MoveDirection` is non-zero **while
position is unchanged**; nothing observed in this session's data (across any of the six artifacts in this
plan) has shown that combination outside of stale-client or contaminated conditions.

**Artifact:** `artifacts/frame-accurate-oracle-resolved.md`.
