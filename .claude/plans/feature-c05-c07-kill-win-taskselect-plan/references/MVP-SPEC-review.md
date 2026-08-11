# `docs/MVP-SPEC.md` — review

Read: §3 (`:42-79`), §4.3 (`:108-124`), §4.4 (`:126-143`), §4.7 (`:168-176`), §4.8 (`:178-185`),
§4.9 (`:187-193`), §6.2 (`:238-248`), §6.4 (`:283-298`).

## §4.3 — the kill — `docs/MVP-SPEC.md:108-124`

```
3. While transformed: **+25% move speed**, can kill on touch/prompt within 8 studs.
4. After a kill (or after 8s), it must **revert** (1.0s). Corpse remains for 45s, then fades.
5. **Kill cooldown: 30s** from revert.

**Rules to enforce server-side:** distance ≤ 8 studs, raycast line-of-sight, cooldown elapsed, both
alive, round `ACTIVE`. The client only *requests* a kill; the server decides.
```

**IMPORTANT** — step 3 is where "the killer must be transformed" comes from. The kill is a property of
the **form**, not of the role. C05's bullet list omits it; the plan adds it as a seventh condition and
flags it, because deleting it would let the Aswang kill from inside a crowd wearing a survivor's face
and would remove the risk half of §2's risk/reward pillar.

**IMPORTANT** — step 4 makes the revert a **consequence of the kill**, and step 5 anchors the cooldown
to that revert. In the plan those are one line: `commitKill` calls `revert(killer)`, and `revert()`
already stamps `LastRevertedAt` (`src/server/Services/MonsterService.luau:264`). There is no separate
cooldown timer to keep in sync, which is the point.

**NOTE** — the five verbatim rules are five, not six or seven. "Killer is Aswang, target is not" is not
in this list; it comes from §6.2 and from C05's own bullet. Both belong in the validator.

## §4.8 — win conditions — `docs/MVP-SPEC.md:178-185`

```
| **Aswang wins** | Living survivors ≤ 2, **or** sunrise timer hits 0 with tasks incomplete |
```

**IMPORTANT** — read literally against `Config.Round.MinPlayers = 3`, this is true before anyone moves:
three players is one Aswang and two survivors. The spec is describing the 6–8 player round it pictures
in §1 and does not restate the floor. Phase 5's clamp (`min(threshold, dealtIn - 1)`, with a guard at
zero) is the plan's reading of what the rule *means* — most of them are dead — and it is what keeps a
solo Studio round runnable.

**NOTE** — the timeout half is already implemented: `RoundTransitions` returns `ENDING` on expiry and
`RoundService.step` raises `Enums.RoundResult.Timeout`
(`src/server/Services/RoundService.luau:313-316`). This plan does not touch it.

## §4.9 — tone as a business constraint — `docs/MVP-SPEC.md:187-193`

```
**Blood, gore, and intense violence push you to 13+ and cut off a large part of your audience** ...
Kills should be a grab, a scream, a fade to black — no blood pools, no dismemberment.
```

**IMPORTANT** — this is why the plan's corpse is an anchored, un-ragdolled body that tweens to
transparent. It also rules out `Humanoid.Health = 0` as the kill mechanism: the default death animation
and the falling body are exactly the "graphic" register this section is protecting the rating from.

## §4.4 — tasks — `docs/MVP-SPEC.md:126-143`

```
**The rule: 12 possible task locations exist on the map. Each round randomly picks 5.**
```

**NOTE** — "randomly picks 5" is the whole of C07's pure half. The rest of §4.4 (four types, the global
bar, the Aswang's fake list) is C08–C10 and is out of this plan's scope.

## §4.7 — ghosts — `docs/MVP-SPEC.md:168-176`

```
**The fix:** a dead survivor becomes a **ghost**
```

**IMPORTANT** — this is the licence for the plan's decision to set a killed player's `PlayerState` to
`GHOST` rather than adding a fifth enum value. It also means C05 **creates** the dead-player gap this
section calls "silently fatal", and C15 closes it. Worth knowing before any playtest between the two.

## §6.2 — server authority — `docs/MVP-SPEC.md:238-248`

```
- The Aswang's identity is **server-only state**. It is never sent to other clients in any form.
- Clients *request* actions (`RequestKill`, ...). The server validates and decides.
```

**IMPORTANT** — `RequestKill` is named here by the spec itself. The plan's handler returns **nothing**
on every refusal, including line-of-sight, because any distinguishable reply is a role oracle once the
attacker controls the target.

## §6.4 — the state machine and its edge cases — `docs/MVP-SPEC.md:283-298`

```
- Player count drops below minimum mid-round → finish the round, then return to `IDLE`.
- A player joins mid-round → spectator until `ENDING`.
- Last survivor and Aswang both alive at timer end → Aswang wins (tasks incomplete).
```

**IMPORTANT** — the first bullet is the precedent for Phase 5's decision to evaluate the win **only on
a kill, never on a disconnect**. `RoundTransitions` already refuses to consult the headcount during
ACTIVE for the same reason (`src/shared/pure/RoundTransitions.luau:53-61`); doing the opposite here
would reintroduce the exploit through a different door.

**NOTE** — the second bullet is the C04 remnant, and the plan's Phase 1 is the missing half of it.

## §3 — the scope line — `docs/MVP-SPEC.md:66-79`

**NOTE** — nothing in this plan touches the OUT list. The one place it comes close is
`KillValidation`'s `TARGET_IS_ASWANG` verdict, which exists **because** "multiple Aswangs per round" is
banned: if `Config.Roles.AswangCount` is ever moved, the failure must be a refusal rather than two
monsters killing each other.
