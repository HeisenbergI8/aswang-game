# `docs/BUILD-PLAN.md` — review

Read: C04's warning block (`docs/BUILD-PLAN.md:203-219`), C05 (`:223-241`), C06 (`:245-252`),
C07 (`:256-268`).

## C04's carried-over warning — `docs/BUILD-PLAN.md:203-219`

```
> Add the containment half here, before the kill exists: no character for `SPECTATOR`, or an observer
> camera and no collision. Gate on `RoundService.GetPlayerState(player) == Enums.PlayerState.Alive` —
> an **allowlist**, never `~= SPECTATOR`. `PlayerState` has four values, so a denylist also admits
> `LOBBY` and `GHOST`; C15 makes `GHOST` real and a ghost must not be killable.
```

Says what: the containment was chartered for C04 and not delivered; the fix must be an allowlist.

**IMPORTANT** — "no character for SPECTATOR" and the kill's `== ALIVE` gate are **two different
allowlists over the same enum**, and the document's single sentence hides that. `LOBBY` must have a body
(everyone between rounds does) and must not be killable. Plan Step 1.2 splits them into `mayHaveBody`
and `mayBeKilled` for this reason, and Step 1.3 pins the `LOBBY` row precisely because merging them is
the natural simplification.

**IMPORTANT** — "or an observer camera and no collision" is the alternative this plan does **not** take.
An observer camera is client-side, so a server-only containment would still leave a collidable body in
the world if the client ignored it. No character is the only option a compromised client cannot undo.

```
> **Verify the premise in Studio before building the fix.** What is established is that nothing in
> `src/` prevents a spectator spawning ... The place file is gitignored, so a `SpawnLocation` or a
> property set in Studio could already handle this and no check in the repo would see it.
```

**IMPORTANT** — this is the source of plan Step 1.1, and it is the only step in the plan whose check is
a `test -f`. No command in this repo can read a property out of a place file, so the deliverable is a
written finding rather than an exit code.

## C05 — `docs/BUILD-PLAN.md:223-241`

```
- `RequestKill(targetUserId)` → distance ≤ 8, **raycast line of sight**, cooldown elapsed, both alive,
  phase `ACTIVE`, killer is Aswang, target is not.
- `src/shared/pure/KillValidation.luau` — `(killerPos, targetPos, config, now, lastKillAt) → verdict`.
- Corpse persists `CorpseDuration`, then fades. `PlayerKilled` broadcast (position and victim — **never**
  the killer).
- Kill cooldown starts from *revert*, not from the kill.
```

**NOTE** — the signature in the second bullet takes `config`; the plan's module takes `Range` and
`Cooldown` as scalars instead. Passing the whole `Config` table would make the pure module depend on
`Config`'s *shape*, and `Config` is the file M12 rewrites most.

**NOTE** — `lastKillAt` is named in the bullet but the fourth bullet contradicts it: the cooldown runs
from the **revert**. The plan's field is `LastRevertedAt`, matching `MonsterService`'s existing
`MonsterState.LastRevertedAt` (`src/server/Services/MonsterService.luau:67`), which is already stamped
by `revert()` and already read by `TransformRules`. There is no separate "last kill" timestamp anywhere
and this plan does not add one.

**IMPORTANT** — the six conditions listed do **not** include "must be transformed". §4.3 step 3 of the
spec does. The plan adds it as a seventh, gated on `Announced` rather than `Transformed`, and flags it
in Follow Ups rather than slipping it in.

```
**Verify** ... Playtester attempts an out-of-range kill via `execute_luau` and captures the refusal.
```

**IMPORTANT** — the Done line is written entirely in terms of **refusals**. That is what makes C05
verifiable at all by an agent, and it is the basis of the plan's §5 ceiling: the success path is not in
the chunk's own acceptance criteria.

## C06 — `docs/BUILD-PLAN.md:245-252`

```
Living survivors ≤ 2 → `RoundService.EndRound(AswangWin)`. The timeout half already works.
Add to `pure/RoundTransitions.luau` or a sibling; do not scatter the check.
**Verify** unit test on the win predicate; playtester drives a solo round to the ≤2 condition.
```

**IMPORTANT** — "playtester drives a solo round to the ≤2 condition" is not achievable and the plan
says so. A solo round has **zero** survivors, so the condition is true before ACTIVE begins; driving it
would mean the round ends instantly, which is the bug rather than the verification. Phase 5's dealt-in
clamp is the answer, and the Lune suite is the whole of that chunk's mechanical evidence.

**NOTE** — "a sibling" is taken: `pure/WinConditions.luau`. Threading a roster count through
`RoundTransitions` would multiply its exhaustive 5×2×2 table, which is that module's entire value.

## C07 — `docs/BUILD-PLAN.md:256-268`

```
- `src/shared/pure/TaskSelection.luau` — `(pool, count, seed) → chosen` ...
- Task points discovered in the map by CollectionService tag (`TaskPoint`) ... the greybox at C25
  places them and this reads them.
```

**IMPORTANT** — `TaskPoint` appears **zero times** in `src/` (verified). The plan builds the first
bullet and explicitly refuses the second; the omission is written into the plan's §1.1 so it reads as
deliberate.

**QUESTION** — this bullet says the greybox is at **C25**; the task brief says **C17**. The plan writes
C17 into `TaskService`'s header. Whichever is right, one of the two documents is stale and the
discrepancy should be resolved in `BUILD-PLAN.md` rather than carried forward.

**IMPORTANT** — `(pool, count, seed)` puts a generator inside a module that replicates to every client.
The plan takes `nextFloat` instead, matching `src/server/pure/RoleDraw.luau:99`. Flagged as a deviation
in Follow Ups.
