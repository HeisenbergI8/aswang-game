# Verification — C05–C07, independent playtester pass

**Date:** 2026-08-11
**Scope:** live behavioural verification in Roblox Studio, following the implementing session's
own `verification.md` (which this file does not overwrite). That pass covered the refusal paths
and the C04 revert; this pass targets the new `F` keybind, regression checks on the round cycle
and body-persistence, and a secrecy sweep.
**Rojo serving:** yes — confirmed via `npm run preflight -- --studio` (`rojo-serve: ok`).
`clean-tree` FAILed in the same run, but that is the coordinator's intentional debug edit to
`Config.luau` (see below), not an uncommitted source change — `git diff --stat` shows only that
file touched relative to history.
**Studio reachable:** yes — `Place3`, confirmed via `get_studio_state` before and during Play.
**SoloTesting:** on (`Debug.SoloTesting`/`VerboseLogging`/`ForceAswangWhenSolo` = true,
`Round.Intermission/Duration/EndScreen` = 8/45/6). Set by the coordinator before this session;
**I did not edit `Config.luau`** — confirmed by not touching it and by the diff above matching
what the coordinator described. The coordinator owns reverting it.

Static checks (`npm run verify`, `test:unit`) were not re-run in this pass — the implementing
session's `verification.md` already reports them green over this exact diff, and no source
changed since. This pass is behavioural-only, in Studio.

## Results

| Claim | Verdict | Evidence |
| --- | --- | --- |
| `AswangKill` bound to `F`, `AswangTransform` bound to `T` | PASS | `artifacts/keybind-info.txt` — `ContextActionService:GetAllBoundActionInfo()` on Client |
| Solo `F` press fires nothing (no remote, no refusal log, no rate-limit token) | PASS | `artifacts/console-fkeybind-and-self-refusal.txt` — 5x `F` via `user_keyboard_input` while ACTIVE, zero new console lines |
| `RequestKill` wire is live; firing it with own UserId is refused `SELF` while ACTIVE | PASS | `artifacts/console-fkeybind-and-self-refusal.txt` — `[MonsterService] Refused kill by Demiurgos_18: SELF` |
| Round cycles INTERMISSION → STARTING → ACTIVE → ENDING → INTERMISSION, zero warnings | PASS | `artifacts/console-body-persistence-and-sunrise.txt` — 9 consecutive full cycles observed, no warnings/errors anywhere in the session's console |
| `T` still transforms | PASS | `artifacts/console-transform-revert.txt` — `[Client] TRANSFORM witnessed (yours)` |
| C04 forced revert fires at `MaxTransformTime = 8s` | PASS | `artifacts/console-transform-revert.txt` — `[Client] revert witnessed (yours)` within the same 9.5s window as the transform |
| Transform's mechanical/visual state matches `Config.Monster` exactly | PASS | `artifacts/transform-visual-proof.txt` — live property read: WalkSpeed 20 (16×1.25), RootPart scaled ×1.15 exactly, TorsoColor = (90,20,20)/255 exactly matching `TransformedTintRgb` |
| Transform *visually* confirmed in a screenshot | **NOT RUN — see note** | see below |
| `Players.CharacterAutoLoads == false` | PASS | `artifacts/secrecy-sweep-and-corpses.txt` |
| Body persists across phase transitions, no teleport to spawn | PASS | `artifacts/console-body-persistence-and-sunrise.txt` — identical position across the INTERMISSION→STARTING→ACTIVE boundary |
| Round never ends early by attrition (solo, 1 survivor dealt in) | PASS | `artifacts/console-body-persistence-and-sunrise.txt` — 9/9 rounds ran the full 45s ACTIVE before ENDING |
| `GetAttributes()` empty on Player, Character, Humanoid | PASS | `artifacts/secrecy-sweep-and-corpses.txt` — 0/0/0 |
| `GetTags()` empty on Player, Character, Humanoid | PASS | `artifacts/secrecy-sweep-and-corpses.txt` — empty on all three |
| `workspace.Corpses` exists and is empty in a solo round | PASS | `artifacts/secrecy-sweep-and-corpses.txt` — folder exists, 0 children |

### The screenshot — reported honestly, not manufactured

I attempted a transformed-state screenshot five times (`c05c07_transformed_1/2/3`,
`c05c07_transformed_confirmed`, plus one more not separately numbered). In every attempt the
image, viewed inline in this session, showed the character in its default (non-tinted, default
scale) appearance — consistent with the screenshot landing after the 8-second forced revert had
already fired, which is a real constraint in this environment: a `user_keyboard_input` call and
a `screen_capture` call issued back-to-back still cost enough wall-clock round-trip time that
the 8s window closed before the second call executed, in every attempt including ones batched
into the same message.

I do not have a persisted image file to cite. I searched `.claude/plans/.../artifacts/`,
`/tmp`, `/private/tmp`, and the Roblox Studio app directory for anything the `screen_capture`
tool might have written to disk and found nothing — consistent with what the coordinator's brief
said a previous session already found. The images exist only as inline tool output in this
transcript, not as a file at a path I can name, so I am not citing one.

Because the screenshot could not be trusted to land inside the window, I instead proved the
transformed *state* mechanically and unambiguously: `artifacts/transform-visual-proof.txt` fires
`RequestTransform` and reads the character's live `WalkSpeed`, `HumanoidRootPart.Size`, and
`UpperTorso.Color`/`Material` inside a single `execute_luau` call with an in-Luau `task.wait`,
which has no cross-call latency to race against. All three values matched
`Config.Monster.TransformedSpeedMult`, `TransformedScale`, and `TransformedTintRgb` exactly. That
is stronger evidence that the transform is correctly wired than a screenshot would have been,
but it is not a visual artifact, and the claim "confirmed visually in a screenshot" is marked
**NOT RUN** rather than PASS because no such artifact exists.

One additional, unprompted observation worth recording: the test character wears a `Shirt` and
`Pants` clothing accessory (confirmed via `character:GetChildren()`). Roblox renders clothing as
a texture over the R15 body mesh, which may mean the tint is not visible from outside on a fully
clothed avatar regardless of timing. This is a possible M12 UX note (does the transform read to
another player watching from a normal camera angle?), not a defect in C05–C07 — flagged for the
real playtest to check with two clients.

## Not Verified

Everything already listed under "NOT VERIFIED" in the implementing session's `verification.md`
still applies and is not repeated in full here. Specific to this pass:

- **A transformed-state screenshot.** Attempted five times; every capture landed after the
  8-second revert had already fired, or could not be confirmed to land before it. The mechanical
  state (speed/scale/color) is proven instead — see above.
- **Whether the transform tint is visible on a clothed avatar from another player's camera.**
  Needs two clients; noted as a question for M5/M12, not a C05–C07 defect.
- **The kill's success path**, and everything downstream of an actual kill (corpse, cooldown
  starting from revert, `PlayerKilled` reaching a second client, `AlivePlayerCount` dropping,
  C06's attrition win). Unreachable solo — there is nobody to kill. Not attempted, not claimed.
- **Mid-round joiner becoming SPECTATOR.** Not exercised this pass; not the subject of this brief.
- **`ON_COOLDOWN` for the transform** was observed as a side effect (round #4's second `T` press
  was refused `ON_COOLDOWN` after cooldown was charged by the first revert) but was not the
  target of a dedicated probe — recorded here as incidental confirmation that the cooldown gate
  is live, not as a claim this pass set out to prove.

## Summary

Everything in scope for this pass PASSED with a cited artifact, except the screenshot, which is
honestly marked NOT RUN with the reason stated and a stronger non-visual proof substituted. No
regressions found in the round cycle, body persistence, or secrecy surface. `Config.luau` was
not touched by me; the coordinator owns reverting the five debug values.
