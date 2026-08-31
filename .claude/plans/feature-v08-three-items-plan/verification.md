# Verification: V08 — ItemService: the three items

**Date:** 2026-08-29
**Scope:** `.claude/plans/feature-v08-three-items-plan/` — all 5 phases, per `implementation-log.md`
**Rojo serving:** yes, throughout — `npm run preflight -- --studio` reported `rojo-serve` / `rojo-attached`
/ `rojo-synced` all green each time it was checked.
**Studio reachable:** yes for the probe work below; behavioural evidence for the full search chain was
NOT captured (see "Not Verified"). Three separate Play sessions dropped from Play back to Edit mode on
their own partway through, for no code-visible reason — recorded as an environmental constraint on this
run rather than a defect, so a future run does not spend the same budget re-discovering it.
**SoloTesting:** was on (with `VerboseLogging` on and `Round.Intermission/Duration/EndScreen` shortened)
for the portion of this session that used Studio. **The coordinator has since reverted all debug values**
— `npm run verify` is reported EXIT 0 with 49/49 suites on the current tree. This document does not
re-run Studio against that reverted tree; the Studio evidence below was captured against an earlier
version of the tree, noted per-item below.

## Static verification

Run earlier in this session, against the tree as implemented (debug values off at that point):

| Check | Result |
| --- | --- |
| `npm run analyze` | PASS — 0 errors, 0 warnings, 0 parse errors |
| `npm run lint` | PASS — 0 errors, 0 warnings |
| `npm run fmt:check` | PASS |
| `check:remotes` | PASS — 32 declared, 32 wired |
| `check:secrecy` | PASS |
| `check:config` | PASS |
| `check:scope` | PASS |
| `check:ratelimit` | PASS |
| `check:testcount` | PASS |
| `test:unit` | 48/49 files passed. The one failure was `tests/config.test.luau`, and it failed
  **only** on the three debug-value assertions (`SoloTesting == false`, a round-length floor, session
  retry timing) that are true by design while the debug values are set for Studio testing — exactly
  the behaviour CLAUDE.md documents (`tests/config.test.luau` asserts `SoloTesting == false`). All
  other assertions in that file, and all 48 other suites, passed, including the four new/changed V08
  suites: `item-carry` (49 assertions), `item-drop` (26), `item-throw` (81), `item-use` (10). |

The coordinator has since confirmed `npm run verify` is EXIT 0 with 49/49 suites on the current
(debug-values-reverted) tree. This session did not re-run that command itself after the revert.

## Behavioural verification

### What was established

**1. The remote surface for the new/changed verbs — `artifacts/remote-probe-log.txt`.**

Method: transient `OnServerEvent` listeners attached server-side on `RequestDropItem`,
`RequestThrowSalt` and `RequestSearch` (per `.claude/lessons/prove-input-at-the-remote-not-the-outcome.md`
— measure the remote boundary, not the gameplay outcome), then X, Q and E driven one at a time via
`user_keyboard_input`. Disconnected immediately after capture.

Result: exactly 3 events fired for 3 key presses, one per remote, in press order:

- `RequestDropItem` (X) — **0 arguments**. Confirmed.
- `RequestThrowSalt` (Q) — 1 argument (a direction), as designed.
- `RequestSearch` (E) — 0 arguments.

**The negative is confirmed by the count, not inferred**: no fourth event, so X did not also fire
`RequestThrowSalt` or `RequestSearch`, and neither of the other keys cross-fired either. This directly
answers brief question 4.

**2. The one genuinely unverified Roblox behaviour in this chunk — `artifacts/touched-pickup-probe.txt`.**

Method: rather than driving the full search → drop → walk-over chain, isolated the specific engine
question. Built a probe `Part` in `workspace` matching `placeItem`'s real properties exactly
(`Anchored = true`, `CanCollide = false`, `CanTouch` left at its engine default of `true` — the same
shape `src/server/Services/ItemService.luau:428-463` creates for a dropped item), attached a `Touched`
listener, and walked the character into it using `mcp__Roblox_Studio__character_navigation` (real
pathfinding movement from 10 studs away, not a teleport-into-overlap).

Result: **`Touched` fired.** Two hits were recorded — the character's hair accessory `Handle` and its
`Head` — both resolving to the same character `Model` via `hit:FindFirstAncestorOfClass("Model")`,
which is the identical lookup `placeItem`'s own `Touched` handler performs
(`ItemService.luau:483`) before calling `Players:GetPlayerFromCharacter`.

**Conclusion: `Touched` does fire for an anchored, `CanCollide = false` part when a live character
walks into it, in this Studio/engine version.** The pickup mechanism's foundational assumption holds.
Probe part and connection were destroyed/disconnected immediately after capture; nothing was left in
`workspace`.

**Caveat, stated in the artifact and repeated here:** this proves the ENGINE BEHAVIOUR — that `Touched`
fires on this part shape — not the full production code path end to end (an item actually reaching a
player's slot after a real walk-over, with the distance re-check, `ItemCarry.evaluate`, and the slot
update all firing correctly in sequence). That full chain was not observed; see "Not Verified" below.

**Tested against an earlier tree.** Two things changed in `ItemService.luau` after this probe was run:
the drop now places the item `Config.Items.DropForwardStuds` (6 studs) in front of the dropper via
`root.CFrame.LookVector`, rather than at the dropper's own root. This does not affect the probe's
finding — the probe tested the PART SHAPE (`Anchored`/`CanCollide`/`Touched`), not its placement — but
it means the drop→pickup *distance* in the live game is now different from what a reader might assume
from the probe's own test geometry (character walked to a fixed point 10 studs away, not to a point
`DropForwardStuds` from a drop origin). The `Touched`-fires finding itself is not affected by this
change, since it is about the engine and the part properties, not about where the part is placed.

**3. The round state machine, under `SoloTesting`, produces a clean container search with no item found
— screenshots and console lines captured but not saved to `artifacts/` before the session moved on
(see "Not Verified").** Two full 6-second `RequestSearch` holds were driven to completion
(`Container_KuboNW_Chest`, then `Container_StallNW_Goods`), both confirmed complete — not merely fired
— by re-searching the same container immediately after and receiving `SearchController:
SEARCH_ALREADY_SEARCHED`, which only the server sets once a search has actually resolved
(`opened[hold.ContainerIndex] = true` is set at resolution, not at request). Both containers had no
item that round (plausible: only 7 of 15 containers are seeded per round). The HUD status line read
`ALIVE` with no item suffix in both cases, which is `render`'s correct behaviour for an empty slot. No
item-bearing container was reached before the session was redirected away from Studio work.

### What was NOT established

- **The full `SearchService.ItemFound` → `ItemService.onItemFound` → slot → `RoundService` snapshot →
  HUD chain was never observed with an actual item.** Two searches completed cleanly but both drew
  empty containers; no screenshot exists showing the HUD status line carrying `salt` / `bawang` /
  `buntot pagi`. This is brief question 1, unanswered.
- **The drop key → floor part → walk-back-over → pickup chain was never driven end to end.** The
  `Touched`-fires finding (above) establishes the engine precondition is sound, but no test held an
  actual item, pressed X, confirmed a part in `workspace.DroppedItems`, confirmed the HUD label
  cleared, and then walked back over it to confirm re-pickup. This is brief question 2, unanswered in
  its full form — only the engine precondition behind it is answered.
- **The full-handed-search-spills-not-destroys path (brief question 3) was not tested.** No attempt
  held an item and searched a second yielding container.
- **The salt hit's five jobs on a transformed Aswang (brief question 5) were not tested.** No
  multi-role scenario was reached — `SoloTesting` forces a single-role round and this session never
  got as far as holding salt to throw.
- **No file named `search-active-window.txt` exists in `artifacts/`.** `touched-pickup-probe.txt`
  references it as a place where "closest available evidence on the full chain" might be found; that
  file was never written, so treat that reference in the touched-pickup artifact as stale — the chain
  evidence it points at does not exist. The two files actually present are `remote-probe-log.txt` and
  `touched-pickup-probe.txt`, both cited above.
- **No HUD screenshot was saved to `artifacts/`.** Several were captured to the Studio session during
  this run (an empty-hand HUD, and two post-search HUD states both showing no item), but none were
  written to disk before the session was redirected, so none can be cited as evidence here per this
  agent's own reporting standard — a claim with no artifact is worse than silence.
- **A stale-text finding, not gated behind Studio access, worth flagging separately:**
  `UIController.promptFor` (`src/client/Controllers/UIController.luau:1592-1616`) still returns
  `"survive until sunrise · Q throw salt · walk over a pouch to take it"` (and the touch-pad
  equivalent), unchanged by V08's Phase 5. This describes the pre-V08 mechanic exactly — the deleted
  `SaltCarry.pickupTick`'s "walk over a pouch" pickup — and names none of V08's actual verbs: no `E`
  search, no `X` drop, no mention of bawang or buntot pagi. This function was not touched by Phase 5's
  diff (which only changed the carried-item render and `ActionHandlers.Drop`), so it was not caught by
  any phase's own review. It was visible on-screen in every HUD screenshot taken this session. This is
  onboarding copy shown to every player and is now actively wrong about how to pick up an item — worth
  a follow-up fix, though it is a text bug, not a mechanic bug, and does not block anything above.

## Confidence

- Remote-argument evidence (question 4): **high**. Directly measured, method matches the repo's own
  lesson, negative confirmed by count.
- `Touched`-fires-on-this-shape (the core of question 2): **high**, for the specific engine question.
  **Low-to-none** for "the pickup mechanic works end to end in the current tree" — that was not tested,
  and the drop's placement geometry changed after this probe ran.
- Search mechanic completing cleanly with no item (partial evidence toward question 1): **medium** —
  two completed searches, confirmed by the `ALREADY_SEARCHED` re-check, but zero of the two happened to
  draw an item, so the item-carrying half of the chain remains untested rather than tested-and-passing.
- Questions 1 (full), 2 (full chain), 3 and 5: **not established.** Say so rather than infer a pass —
  none of these were observed.

## Recommendation

The two highest-value open questions from the brief — does `Touched` fire on this part shape, and does
`RequestDropItem` arrive clean with no cross-fire — are answered with high confidence and needed no
round timing at all, which is the shape the repo's own lesson predicts. The remaining questions (does a
search actually populate the slot with an item a player can see; does the full drop/pickup loop close;
does a full hand spill instead of destroy; does the salt hit still do its five jobs) all need a live
round with an item-bearing container or a second/transformed role, and were not reached in this session.
A follow-up Studio session — with the debug values the coordinator already reverted set again
deliberately for that purpose — could finish them relatively cheaply now that the round-length problem
(20s vs. a 6s search) that consumed most of this session's early budget is understood and no longer a
timing trap.
