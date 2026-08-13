# Step 6.1 — the ProximityPrompt probe

Captured 2026-08-12, Studio place `Place3`, against `TaskPoint_01` and the live rig from Step 2.1.
`ProximityPrompt` appeared **zero times** in `src/` before this phase, so none of its behaviour was
assumed.

## The four questions, answered

### 1. Does a server-created `ProximityPrompt` parented to an anchored `BasePart` reach a client?

**Yes.** Read from the **Client** datamodel during a live round, with all five prompts created by
`TaskService.attachPrompt` on the server:

```
ActiveTaggedOnClient: 5
TaskPoint_04:prompt=true,dist=3   TaskPoint_05:prompt=true,dist=94
TaskPoint_06:prompt=true,dist=67  TaskPoint_08:prompt=true,dist=30
TaskPoint_12:prompt=true,dist=60
ProximityPromptsEnabledGlobally: true   KeyboardEnabled: true
```

Both the `ActiveTaskPoint` tag and the `TaskPrompt` instance replicate. The plan's fallback — moving
prompt creation into `TaskController` off the tag — is **not needed**.

**On-screen rendering is NOT confirmed by screenshot, and the reason is the tool rather than the code.**
With the character standing 3.5 studs from `TaskPoint_04` (inside the 9-stud activation range,
`Enabled = true`), `screen_capture` shows the pad and the avatar and no prompt. The same captures show
no Roblox topbar, no chat and no health bar either — none of the CoreGui a live Play session always has.
So `screen_capture` is compositing the viewport without CoreGui, which is where a `Style = Default`
prompt draws.

Recorded as **replication confirmed, rendering unverified**. It is a one-glance check for a human at the
keyboard and it is the kind of thing this repo's artifact rule exists to keep honest.

### 2. Does the prompt's own `E` collide with the `ContextActionService` bind?

**Unresolved by static probe; a documented escape exists.** `KeyboardKeyCode` defaults to `E`, which is
the same key Step 5.2 binds. The prompt can be fully disowned:

```
CanDisownKey: true    KeyAfterDisown: "None"     (Enum.KeyCode.Unknown)
Exclusivity: OnePerButton    Style: Default
```

So if the two fight, `prompt.KeyboardKeyCode = Enum.KeyCode.Unknown` makes the prompt purely visual and
the bind keeps the input. Nothing in this plan depends on the prompt's input: `HoldDuration = 0` and
nothing listens to `Triggered`, so a `Triggered` per press is inert. **Which one wins is a question for a
human pressing the key**, and it is exactly what Step 6.3 is reserved for.

### 3. Defaults, and do they agree with what the server accepts?

**They do not, and this is the answer that changed the code.**

| Property | Default | Set to | Why it matters |
| --- | --- | --- | --- |
| `MaxActivationDistance` | **10** | `Config.Tasks.PresenceRangeStuds` = 9 | The default is WIDER than the server accepts |
| `RequiresLineOfSight` | **true** | `false` | The default hides a prompt the server would accept |
| `HoldDuration` | 0 | 0 | Left at 0 deliberately — see below |
| `ActionText` | `"Interact"` | `"Hold"` | — |

The first row is the failure Step 6.1 was written to catch before any code shipped: a prompt visible at
10 studs on a task the server refuses at 9 gives the player one stud of "hold does nothing", which is
indistinguishable from a broken game. Setting both explicitly is **required**, not cosmetic, and
`attachPrompt`'s comment now says so with the measured numbers in it.

Verified the assignment holds: `SetToNine: 9`, `AssignmentHolds: true`.

`HoldDuration` stays 0 because a prompt that held for `HoldTime` would fill on the **client's** clock and
complete at a different moment from the server's bar — precisely what "server-timed" rules out.

### 4. Does `Enum.UserInputState.Cancel` exist?

**It exists** (`CancelExists: true`, `CancelName: "Cancel"`). *When* it raises is a runtime question this
probe cannot answer, and the consequence is bounded and already written down: if it never raises,
`holding` sticks `true` and the client burns rate-limit tokens. It gains no progress, because the server
re-measures distance every tick.

## A trap this probe uncovered, worth more than the probe

The first run of question 3 reported `MaxActivationDistance: 0` and `Matches: false`, which reads as the
prompt refusing the Config value. It was neither.

**`execute_luau`'s `require` cache is stale, and is not the running game's.** Enumerating the loaded
table showed `Config.Tasks` holding only the six original scaffold keys:

```
TaskKeys: FetchTime=25 HoldTime=8 PoolSize=12 TimingAttempts=3 TotalRequired=5 TwoPersonTime=12
ConfigHasPresenceKnob: true      -- the SOURCE has it
PresenceRangeType: "nil"         -- the LOADED TABLE does not
```

It is missing `MinSpacingStuds`, which has been committed since `c15aafc` — so that cached module
predates this plan entirely. The `.Source` property is current; the required table is not.

**The running server was never affected**, and there are two independent proofs:

1. The draw calls `TaskSelection.select(..., Config.Tasks.MinSpacingStuds, ...)`, and `respectsSpacing`
   evaluates `minSpacing <= 0`. A nil there raises. Three rounds drew without error.
2. Every server-created prompt reports `dist=9` — that 9 came from `Config.Tasks.PresenceRangeStuds`,
   a knob this plan added in Phase 1.

This is the same family as the `RoundService.GetPhase()` misread in `artifacts/task-rig.md`: **the
executor's Luau environment is not the game's.** The rule that follows is the one both incidents support
— measure through datamodel state (tags, instances, properties) or the console, never through a module
the executor required.

## What Step 6.3 is left to decide

Only question 2, and only by a person pressing `E` while standing on a pad:

- If the bind receives `Begin`/`End` normally, nothing changes.
- If the prompt swallows the key, set `prompt.KeyboardKeyCode = Enum.KeyCode.Unknown` in `attachPrompt`.

Both branches are one line, and the plan is correct that no `grep` in this repo can tell them apart.
