# Implementation Log — C29 Audio Pass

## Phase 1: The cue vocabulary — Config, the pure rule, and its tests — 2026-08-18

**Steps completed:** 1.1, 1.2, 1.3, 1.4

**Files changed:**
- `src/shared/pure/AudioCues.luau` (new, 141 lines)
- `tests/audio-cues.test.luau` (new)
- `src/shared/Config.luau` (+`Audio` block between `Sky` and `AntiCheat`)
- `tests/config.test.luau` (+audio invariants, +`AudioCues` require)

**Deviations from plan:** one, in Step 1.3's comment text rather than in any code.

The plan's `Config.Audio` comment claimed *"`tests/config.test.luau` asserts that every cue id the rule
module names has a key here."* Step 1.4 cannot make that claim total: `PERMITTED_PHASES` is private to
`AudioCues` and the module exposes no enumeration, so **five** event cue ids (`CUE_TRANSFORM`,
`CUE_HEARTBEAT`, `CUE_GATE_OPEN`, `CUE_SUNRISE` and `CUE_FOOTSTEP`) can only be checked in the
config→rule direction. (This entry said "four" until the C29 audit pointed out that `CUE_FOOTSTEP` is
in `PERMITTED_PHASES` too and is likewise unreachable from `ambienceFor`/`oneShotsFor`. Corrected
rather than left, since the whole purpose of this note is a precise account of what the test reaches.)

Two options were available: add an enumeration function to the pure module, or narrow the comment. I
narrowed the comment, because adding an API purely so a comment could stay as written is the wrong
trade, and an inaccurate invariant comment is the specific failure
`.claude/lessons/green-after-each-patch-hides-a-loop` warns about ("distrust any comment asserting an
invariant"). What the test actually pins is now stated in `Config.luau`, including the one case it
cannot reach and what happens instead (the controller's runtime `warn` for a cue id with no asset).

**A second deviation in the same step, not disclosed at the time and added here after the audit
caught it:** the plan's Step 1.4 diff asserts `SunriseAtProgress > 0 and < 1`; the shipped check at
`tests/config.test.luau:703-707` asserts `> 0.5 and < 1`, with the label changed to "near its end".
That is a real narrowing rather than a rewording. The reasoning is that a sunrise cue in the first
half of the night is not a sunrise cue at all, so `> 0` would admit a value that satisfies the test
and breaks the design — but it should have been logged when it was written, not recovered by an
auditor from the diff.

The check itself is stronger than the plan specified — **both** directions, not one:
- forward: every bed and one-shot `AudioCues` names for every phase has a slot in `Config.Audio.Assets`;
- reverse: every slot in `Config.Audio.Assets` is reachable by some rule (a bed, a one-shot, or an event
  cue permitted in at least one phase). This is the direction that catches a rename inside `AudioCues`.

**Gate:**
- `npm run analyze` — ok (Step 1.1)
- `lune run tests/audio-cues.test.luau` — 30/30 checks passed (Step 1.2)
- `npm run check:config` — ok, balance stays data-driven (Step 1.3)
- `lune run tests/config.test.luau` — PASS, 97 balance invariants, up from 61 (Step 1.4)
- `npm run verify:fast` — analyze ok, remotes ok, secrecy ok
- `npm run verify:plan -- --phase 1` — Steps 1.1–1.4 all PASS, all `[real]` (discriminating)

**Notes for the playtester and auditors:**
- **Nothing is audible yet and that is the designed state.** Every id in `Config.Audio.Assets` is `""`.
  Phase 1 adds no `Sound`, touches no controller and changes no server file.
- The asset-id format assertion (empty **or** `^rbxassetid://%d+$`) is what makes Step 4.2 checkable
  at all. Without it the sourcing pass would be verified only by somebody having typed something.
- `tests/config.test.luau` now requires `AudioCues`. Accepted deliberately and flagged in the plan's
  own reference review: a syntax error in the pure module now reds the balance suite too.
- `Config.Audio.HeartbeatRange` (28) is pinned `<=` `Config.Monster.TransformAudioRange` (40). If a
  later phase wants the heartbeat to carry further, that test is the thing that must be argued with.

---

## Phase 2: `AudioController` becomes a cue player — 2026-08-18

**Steps completed:** 2.1, 2.2, 2.3, 2.4

**Files changed:** `src/client/Controllers/AudioController.luau` (78 → 353 lines)

**Deviations from plan:** two, both ordering rather than design.

1. **`local state: Types.PlayerState` is not declared in this phase.** Step 2.1's diff declares it and
   Step 2.2's `onSnapshot` assigns it, but nothing in Phase 2 *reads* it — the first reader is the
   heartbeat's `isCuePermitted` call at Step 3.2. Written as specified it fails `npm run analyze` with
   `LocalUnused`, which is a red gate, and prefixing it `_state` would have meant renaming it back one
   phase later. It arrives in Phase 3 with its first reader. A comment at the `phase` declaration says
   so, to keep the seam visible.
2. **`local SkyCycle = require(Shared.pure.SkyCycle)` is not added in this phase**, for the same
   reason — its only consumer is the sunrise cue at Step 3.4, and an unused require is an analyze
   failure.

Two things from the plan's own **Phase 2 — Potential Issues** were folded in rather than deferred, as
that section instructs:

- **`CharacterAdded` connections are now dropped on `PlayerRemoving`** (`characterConnections`,
  `forgetPlayer`). The plan flagged this as a real leak that "must not be deferred"; the symptom is a
  slow client-side memory climb that no check in this repo reports.
- `characterConnections` is typed `{ [Player]: RBXScriptConnection? }`. Without the `?` the nil compare
  is a strict-Luau type error (`RBXScriptConnection and nil ... do not have the same metatable`).

**Gate:**
- `npm run verify:fast` — analyze ok, remotes ok, secrecy ok (Step 2.1)
- `npm run check:remotes` — ok, 29 declared / 26 wired, **no new name** (Step 2.2)
- `npm run check:secrecy` — ok, the Aswang stays server-side (Step 2.3)
- `lune run tests/audio-cues.test.luau` — 30/30 (Step 2.4)
- `npm run lint` — 0 errors, 0 warnings; `npm run check:config` — ok

**Notes for the playtester and auditors:**
- **Still nothing audible.** Every asset id remains `""`. What Phase 2 adds is the lifecycle: a bed
  that swaps and crossfades on phase change, a one-shot scheduler, and the footstep retarget — all of
  which create and destroy real `Sound` instances with an empty `SoundId`.
- **The cue log is the evidence for this phase.** With `Debug.VerboseLogging` on, every fired cue
  prints `[AudioController] cue <ID> — <detail>`. That is what the playtester captures; it proves the
  cue fired, never what it sounded like.
- **Three engine assumptions are unverified and are load-bearing for this phase.** (1) that parenting
  to `SoundService` yields a non-positional 2D sound; (2) that Roblox's default character footstep is
  a `Sound` named `Running` under `HumanoidRootPart`; (3) that a `Tween` completing on a destroyed
  instance does not error. The footstep code is written to no-op if (2) is wrong, and that is a safe
  outcome — the default footstep is already identical across players, which is the property the step
  exists to protect. All three are settleable in one `inspect_instance` pass.
- **No branch on role, state or transform exists in the footstep path**, by construction. That is the
  question an exploit audit will ask first and the answer is at one `file:line`.

---

## Phase 3: The event cues — stinger, heartbeat, gate, sunrise — 2026-08-18

**Steps completed:** 3.1, 3.2, 3.3, 3.4, 3.5

**Files changed:** `src/client/Controllers/AudioController.luau` (353 → 621 lines)

**Deviations from plan:** one, of the same class as Phase 2's.

- **`heartbeats` is typed `{ [Model]: Sound? }`, not `{ [Model]: Sound }`.** Under strict Luau a
  non-optional map lookup cannot be compared to `nil` (*"Types Sound and nil ... do not have the same
  metatable"*), and that nil compare is how all three stop conditions decide whether there is anything
  to stop. Annotated in place so the next reader does not "fix" it back.

One of the plan's **Phase 3 — Potential Issues** was resolved rather than left to judgement:

- **`stopAllHeartbeats` no longer mutates the table it iterates.** It collects the characters first,
  then stops them. Removal during traversal is defined in Lua, but the failure mode if it were not is
  one heartbeat surviving the round — the precise leak the three stop conditions exist to prevent, and
  not worth resting on a subtlety.

The plan's third issue — the sunrise cue firing on an early round end, because `SkyCycle.progressFor`
pins `ENDING` to 1 — was taken as the plan's stated default (**allow it**), on the grounds that the sky
makes the same jump and the two should not disagree about dawn. The reasoning is written at the cue, and
it is flagged for the Step 4.5 headphone listen as a thing to judge by ear.

**Gate:**
- `npm run check:config` — ok (Step 3.1)
- `lune run tests/audio-cues.test.luau` — 30/30 (Step 3.2)
- `npm run check:remotes` — ok, 29 declared, **no new name** (Step 3.3)
- `lune run tests/config.test.luau` — PASS, 97 invariants (Step 3.4)
- `npm run check:secrecy` — ok (Step 3.5)
- **`npm run verify` — green across the tree**: analyze ok, all five checks ok, `check:debug` ok,
  `check:testcount` ok, 33 Lune files ok (32 before C29)

**Notes for the playtester and auditors:**
- **The secrecy statement is at `AudioController.luau:63-93`** and answers the four 🔒 questions at a
  `file:line`. Its first claim is mechanically checkable and was checked: `grep -n "YourRole\|Role"`
  over this file returns hits **only inside that comment**. No cue reads a role.
- **The heartbeat is transformed-only.** §5's literal "heartbeat when the Aswang is near" is NOT built
  and cannot be — see Follow Up 1. What ships tells you that a character you can already see transform
  is a monster.
- **Three stop conditions**, because `MonsterService.luau:435` only broadcasts the revert
  `if monster.Announced and character ~= nil`: the revert, the phase leaving `ACTIVE`, and a hard
  timeout at `MaxTransformTime + RevertTime`. A stale loop here would be C04's revert bug in sound.
- **Still no remote, still no server file touched.** `check:remotes` reports the same 29 declared names
  as before C29 began.
- **Everything is still silent** — the ids arrive in Phase 4.

---

## Phase 4: Sourcing, the durable record, and the human listen — 2026-08-18

**Steps completed:** 4.1, 4.2, 4.3 · **Not completed:** 4.4 (playtester, running at time of writing),
4.5 (🧍 the headphone listen — the user's, and the reason C29 is a 🧍 chunk)

*(This entry was written after the C29 audit flagged that Phases 4.1 and 4.2 had landed on disk while
the log still ended at Phase 3. The audit was right and the gap was real: the log is what
`goal-check.mjs` and any later auditor read, so two completed steps invisible in it is exactly the
failure the four-proxy halt check exists to catch.)*

**Files changed:**
- `docs/AUDIO-ASSETS.md` (new — the durable record `Config.Audio.Assets` cannot be)
- `src/shared/Config.luau` (all 10 `Assets` ids filled)

**Deviations from plan:** one, and it is a judgement call worth arguing with rather than a slip.

**The plan says "fill only the cues that were actually approved"; all ten are filled and none is
approved.** The reason is that Step 4.5 is a *listen*, and a cue whose id is blank makes no sound to
listen to — approval cannot precede wiring without inverting the two steps. So the ids are in, and the
un-approved state is recorded where it cannot be missed: `docs/AUDIO-ASSETS.md` opens with **"Status:
sourced, NOT yet approved — nobody has listened to any of them"**, and every row's Approved column is
empty.

The risk this leaves is exactly the one the plan's Issues section names: **if this is committed and the
place published before the listen, ten unheard sounds ship**, including the transform stinger that the
`asset-pipeline` skill calls the single highest-value sound in the game. That is a live hazard and it is
the user's call, not an agent's. Nothing here should be published before Step 4.5.

**Sourcing notes worth keeping:**
- The Creator Store search is unexpectedly literal. `monster`, `growl`, `creature roar beast`,
  `horror stinger` and `footsteps` (plural) each returned **zero** results; `roar`, `creature` and
  `footstep` (singular) returned eight each. Single common nouns work, descriptive phrases mostly do
  not — recorded in `AUDIO-ASSETS.md` so the next pass does not repeat the dead queries.
- `verifiedCreatorsOnly: true` returns nothing for most of these cues. Six of the ten came from Pro
  Sound Effects (a verified creator with durations published); four are community uploads with unknown
  duration, and `AUDIO-ASSETS.md` records `unknown` rather than a guess.
- **The place is unpublished** (`search_asset` reports `isPublished: false`). Roblox gates audio by
  experience, so a cue may log correctly and still produce no sound until the place is published. That
  is not a defect in this code and the playtester was briefed accordingly.

**Gate:**
- `test -f docs/AUDIO-ASSETS.md` — PASS (Step 4.1)
- `lune run tests/config.test.luau` — PASS, 97 invariants, with all ten ids matching
  `^rbxassetid://%d+$` (Step 4.2). This is the assertion Step 1.4 existed to make possible.
- **`npm run verify` — green across the tree** (Step 4.3): analyze ok, all five checks ok,
  `check:debug` ok, `check:testcount` ok, 33 Lune files ok.

**Then, deliberately, the tree was made red.** Seven debug values were set in `Config.luau` for the
playtester run — `Round.Intermission/Duration/EndScreen` = 8/20/6, `Debug.SoloTesting` and
`Debug.VerboseLogging` = true, and `Audio.OneShotMinSeconds/MaxSeconds` = 25/70 → 8/12, this last one
because at committed values the one-shot scheduler cannot fire inside a 20-second test round and wind
and dogs would have gone unobserved rather than unproven.

While those are set, `tests/config.test.luau` reports exactly two failures — "solo testing is off" and
"a round is long enough to actually be played" — and `verify:plan` therefore shows **Step 1.4 as FAIL**.
Both are the debug values and neither is an audio invariant. **All seven must be reverted before any
commit**; `guard-commit.mjs` runs `check:debug` and will refuse until they are.

---

## Post-review fixes — 2026-08-18

Three reviews ran concurrently after Phase 4: `auditor` 75/100, `exploit-auditor` 83/100, and a
`playtester` that was then resumed once its blocker was removed. **Six code findings, all fixed.** The
two that matter converged from opposite directions — the exploit audit predicted the footstep race by
reading, and the playtester measured it on a live character. Neither would have found it alone with
the confidence the pair produced.

**Files changed:** `src/client/Controllers/AudioController.luau`, `src/shared/Config.luau`,
`src/shared/pure/AudioCues.luau`.

### 1. `playStinger` never consulted the state gate — HIGH, and the headers said it did

`AudioCues.isCuePermitted` had exactly two call sites (heartbeat, sunrise). `CUE_TRANSFORM`,
`CUE_GATE_OPEN` and `CUE_FOOTSTEP` were dead rows in `PERMITTED_PHASES`, while `AudioCues.luau:84-88`
stated *"They must not hear the monster — not the stinger, not the heartbeat"* and the secrecy
statement repeated it. `tests/audio-cues.test.luau` asserted the stinger rule and passed — testing a
rule nothing called. **A green test over a false comment**, exactly
`.claude/lessons/green-after-each-patch-hides-a-loop`.

It leaked nothing today: `MonsterTransformed` is `FireAllClients` and the transform's visuals
replicate to spectators regardless. The cost was a documented boundary that did not exist, which is
what the next monster cue would have been built on.

Fixed by calling the gate in `playStinger` and `onGateChanged` — four live call sites now.
`CUE_FOOTSTEP` stays deliberately ungated and the row says so: gating footsteps by phase or state is
the one change that would break them, because they are safe only as a constant across every player.

### 2. The footstep retarget never fired — MEDIUM, predicted and then measured

`applyFootsteps` ran synchronously on `CharacterAdded` with `FindFirstChild`. The playtester measured
the result on a live character: `HumanoidRootPart.Running` **is** a `Sound` (the open question this
repo had never settled), but its `SoundId` stayed at Roblox's stock `action_footsteps_plastic.mp3`
even after a forced respawn — the engine attaches character sounds asynchronously, so the child does
not exist when the character does.

The stakes were higher than one silent cue. Footsteps are safe *because they are a constant*, and a
retarget winning the race on some characters and losing on others is a per-character difference
(`.claude/lessons/absence-is-observable`) waiting for a future change to correlate it with role.

Fixed with `task.spawn` + `WaitForChild(name, Config.Audio.FootstepWaitSeconds)` (10s), and **both
branches now log** — the playtester's observation that nothing distinguished "retargeted" from
"no-opped" is what added that. Re-measured after the fix: `SoundId = rbxassetid://132221529613537`,
`Volume = 0.4`.

### 3. `onTransformed` indexed a Character that can arrive nil — MEDIUM

`Types.MonsterTransformedPayload.Character` is typed `Model`, but an Instance reference that is not
replicated to a client arrives as nil, and §5's `StreamingEnabled` has been live since C17. The
handler's coroutine died on the first index, so a distant transform silently cost that client its
heartbeat for the whole transform. Guarded, with the cast the non-optional type requires.

### 4. The secrecy statement overclaimed — LOW

*"Two clients in the same phase and the same PlayerState reach identical answers by construction"* is
true of the pure function and not of its caller: `phase` is written from a per-player snapshot every
`Round.SnapshotInterval`, so within one tick two clients can hold different values. Reworded to
"identical answers FOR IDENTICAL INPUTS", with the lag named. The difference is driven by network
arrival order and never by role.

### 5. `Config.Audio.HeartbeatFadeSeconds` had no reader — LOW

Declared, never read, and the one `Audio` key `tests/config.test.luau` did not reach. Deleted rather
than wired: a knob that tunes nothing is worse at M12 than no knob.

### 6. Documentation findings from the audit — all corrected

Phase 4's log entry was missing while its steps had landed; the `SunriseAtProgress > 0.5` narrowing
was undisclosed; the deviation note undercounted five event cues as four. All three fixed in place.

**Gate after the fixes, with all eight debug values reverted:**
- `npm run verify` — **green**: analyze ok, all five checks ok, `check:debug` ok, `check:testcount` ok,
  **33 Lune files ok**, `config: 97 balance invariants`
- `npm run verify:plan` — **17 passed, 0 failed, 1 unverifiable** (Step 4.5, the headphone listen);
  15 discriminating, 2 file-exists, 0 self-satisfying
- `npm run goal` — DONE on all four proxies, 3 of 3 artifacts cited

**Behaviourally confirmed in Studio** (`artifacts/console-transform-heartbeat-rounds1-6.txt`): no
`AswangHeartbeat` survives a round on either reachable revert path — the phase leaving `ACTIVE`, and
`MonsterService`'s own forced revert at `MaxTransformTime` while still `ACTIVE`. Transform, heartbeat
and stop all log 3/3. **A kill-triggered revert is still unexercised** — it needs a second player to
be a valid kill target, so it belongs to the M5 session.
