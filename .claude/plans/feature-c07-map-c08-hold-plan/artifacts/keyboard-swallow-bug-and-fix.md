# The E-key was swallowed by the ProximityPrompt — found, diagnosed, and confirmed fixed

Captured 2026-08-12, Studio place `Place3`, `rojo serve` live, against the live `workspace.TaskRig_TEMP`
rig from Step 2.1. Single-player Solo Testing, Config debug values as set by the coordinator
(`Round.Intermission=8`, `Duration=90`, `EndScreen=6`, `Debug.SoloTesting`/`VerboseLogging=true`).

## What Step 6.1's probe left open

`artifacts/proximity-prompt-probe.md` §2 flagged, unresolved: `ProximityPrompt.KeyboardKeyCode` defaults
to `E`, the exact key `InputController` binds via `ContextActionService` for the hold. It named the
question ("does the prompt's own E collide with the CAS bind?") and the fix if it did
(`prompt.KeyboardKeyCode = Enum.KeyCode.Unknown`), but left it for "a human pressing E" because no static
check can tell the two branches apart.

## What actually happened, first try

Before the coordinator's fix, `attachPrompt` in `src/server/Services/TaskService.luau` set
`ActionText`, `MaxActivationDistance` and `RequiresLineOfSight`, but left `KeyboardKeyCode` at its
default (`E`).

Method: `user_keyboard_input` (`keyDown`/`keyUp` on `E`) against the live Client datamodel — the same
mechanism a human keypress produces — while standing 3.5–3.6 studs from an `ActiveTaskPoint`'s
`TaskPrompt` (`Enabled=true`, `MaxActivationDistance=9`). Confirmed via `UserInputService:IsKeyDown` that
the key really was down at the engine level throughout.

**Result: nothing.** No `[TaskService] Refused progress` line, no `[Task]` client print, no completion —
for an entire 90-second `ACTIVE` phase held continuously on an active pad. Contrast: the identical
mechanism, fired from **off** any task point, produced a steady stream of
`[TaskService] Refused progress for Demiurgos_18: NO_TASK_IN_RANGE`, proving `InputController`'s bind and
`TaskController`'s heartbeat loop both work correctly *when the input reaches them* — it was specifically
the on-pad case that produced silence.

## Root-cause confirmation

Live diagnostic (not a source edit): set `workspace.TaskRig_TEMP.TaskPoint_04.TaskPrompt.KeyboardKeyCode
= Enum.KeyCode.Unknown` via `execute_luau` on the Client datamodel — the exact mitigation Step 6.1 named —
then pressed `E` again on that one pad only.

```
[Task] 0/5 · here: 3%
[Task] 0/5 · here: 6%
[Task] 0/5 · here: 9%
[Task] 0/5 · here: 12%
[Task] 0/5 · here: 16%
[Task] 0/5 · here: 19%
```

Fill climbed immediately. This isolates the cause precisely: the `ProximityPrompt`'s own key handling was
consuming the `E` `InputBegan` event before `ContextActionService`'s `TaskAction` bind ever received it,
so `InputController.onTaskAction` never fired `Begin`, `TaskController.SetHolding(true)` was never
called, and the heartbeat loop's `if holding then` gate stayed closed — indefinitely, with no error, no
warning, and no console output of any kind. **A player pressing E while standing on a task pad, in the
shipped-before-this-fix code, could not complete the Hold task at all.**

## The fix, applied by the coordinator, and confirmed live

`attachPrompt` now sets `prompt.KeyboardKeyCode = Enum.KeyCode.None` (equivalent zero value to `Unknown`
at runtime; `None` was used because `Unknown` is absent from the analyzer's `Enum.KeyCode` type and fails
`npm run analyze`). Restarted Play so the server created fresh prompts from the corrected module.

```
inspect_instance Workspace.TaskRig_TEMP.TaskPoint_02.TaskPrompt
KeyboardKeyCode: "Enum.KeyCode.None"   MaxActivationDistance: 9   RequiresLineOfSight: false
```

The fix is live without any runtime override this time. A normal `E` press — `user_keyboard_input`
`keyDown`, no property poking — now produces climbing `[Task]` prints and eventual
`[TaskService] Task complete: <id>` in every subsequent round tested (see
`hold-completion-and-spam-immunity.md`).

## A minor side effect worth naming, not blocking

Every prompt creation now logs, from Roblox's own CoreScript, not this repo's code:

```
CoreGui.RobloxGui.CoreScripts/ProximityPrompt:385: ProximityPrompt 'TaskPrompt' has an unsupported
keycode for rendering UI: Enum.KeyCode.None
```

This is Roblox's UI layer complaining it cannot draw a key-hint icon for `KeyboardKeyCode = None`. It is
noise, not a functional defect — the mechanic works, confirmed above — but it means the ProximityPrompt's
visual "Hold [E]" hint likely does not render correctly (on top of the pre-existing, separate
`screen_capture`-excludes-CoreGui limitation that already prevented a screenshot from confirming prompt
UI either way). Since `HoldDuration = 0` and nothing listens to `Triggered`, the prompt's own input
handling was never load-bearing — `ClickablePrompt` still lets a player click it — but the **hint text a
player reads to learn "press E here"** may now be degraded. Worth a look whenever M7 builds the real task
HUD (`TaskController`'s own comment already names that milestone as the point this stub gets replaced),
not a blocker for C08's Done condition.
