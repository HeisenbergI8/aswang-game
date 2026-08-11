# Step 1.1 — Spectator premise, probed in Studio

**Date:** 2026-08-11 · **Studio:** `Place3` (id `7107daa3-2aac-4437-a1cf-546ecae82ce7`) · live Play session
**Config at probe time:** `Round.Intermission/Duration/EndScreen = 8/20/6`,
`Debug.SoloTesting/VerboseLogging/ForceAswangWhenSolo = true` (all six reverted after the probe)

## Verdict

**The premise holds. The place file does NOT contain a mid-round joiner.** `Players.CharacterAutoLoads`
reads `true`, so Roblox spawns a joiner automatically regardless of the `SPECTATOR` state `RoundService`
assigns them. Steps 1.2–1.4 build as written — this is row 1 of the plan's branch table, the expected case.

## Probe 1 — the premise

```
CharacterAutoLoads = true
RespawnTime = 3
player Demiurgos_18 | Character = Demiurgos_18 | PlayerState attr = nil | attrs = 0 | tags = 0
SpawnLocation Workspace.SpawnLocation | Enabled = true | Neutral = true | AllowTeamChangeOnTouch = false
SpawnLocation count = 1
```

| Reading | Consequence |
| --- | --- |
| `CharacterAutoLoads = true` | The gitignored place file is not doing containment. Nothing anywhere prevents a `SPECTATOR` spawning |
| One `SpawnLocation`, `Enabled = true`, `Neutral = true` | Step 1.4's `LoadCharacter()` has a destination. A disabled or absent spawn would have made the phase spawn nobody |
| `PlayerState` attribute is `nil`, 0 attributes, 0 tags | **The negative control passes.** `RoundService` keeps player state server-side and does not attribute it. A value here would have been a secrecy leak outranking this whole phase |

## Probe 2 — the plan's highest-risk assumption, tested rather than assumed

Follow-up #1 records that `Players.CharacterAutoLoads` and `player:LoadCharacter()` are **first uses in
this repository** and asserted from documentation. All three assertions were exercised in the live
session before any code was written:

```
set CharacterAutoLoads = false
destroyed character; waiting 6s (RespawnTime is 3s)
after 6s: Character = nil  <-- expect nil if the flag is respected
LoadCharacter() pcall ok = true
after LoadCharacter: Character = Demiurgos_18
spawned at 4.0508, 3.9961, 2.0645
second LoadCharacter ok = true | Character = Demiurgos_18
restored CharacterAutoLoads = true
```

| Assertion | Result |
| --- | --- |
| `CharacterAutoLoads = false` suppresses the automatic spawn | **Confirmed** — `Character` was still `nil` 6s after destruction, at double `RespawnTime` |
| `LoadCharacter()` spawns at an enabled `SpawnLocation` | **Confirmed** — spawned at `(4.05, 4.00, 2.06)`, the `SpawnLocation`'s position |
| A second `LoadCharacter()` on a player who already has one | **Does not error** — it respawns them |

**One correction to Step 1.4's reasoning.** The step's comment calls the `player.Character == nil` guard
"load bearing rather than an optimisation", implying `LoadCharacter()` on an existing character is unsafe.
It is not — it succeeds and respawns. The guard is still correct and must stay, but for a different
reason: without it, every `setAllPlayerStates` call teleports every already-embodied player back to spawn.
That is a gameplay bug (a LOBBY→LOBBY no-op transition would yank players mid-walk), not a crash. Worth
stating accurately so nobody later removes it believing it guards against nothing.

## Method note, recorded because it cost time

`execute_luau` returned `phase = IDLE` from `RoundService.GetPhase()` while the console showed the round
cycling `INTERMISSION → STARTING → ACTIVE → ENDING`. This is the documented trap in
`.claude/agents/playtester.md`: **a `require` from `execute_luau` yields a module instance with its own
state, not the live service's.** Everything above is read from the DataModel directly (`Players`,
`workspace`) or from console output, both of which are trustworthy. No claim in this file rests on a
service's internal state read through `execute_luau`.

## What this probe could not establish

- **An actual mid-round join.** Studio's player count is a UI action no agent can drive, so a second
  player never joined mid-round. What is established is the mechanism (`CharacterAutoLoads = true` spawns
  everyone) and the fix's two primitives, not the end-to-end scenario. That scenario is on the plan's
  NOT VERIFIED list along with the rest of the two-client work.
