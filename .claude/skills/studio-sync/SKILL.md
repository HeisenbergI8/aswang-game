---
name: studio-sync
description: How code, the map, and Roblox Studio relate in this project, and how to use the Studio MCP tools without destroying work. Load BEFORE touching anything in Studio, before using any mcp__Roblox_Studio__ tool, and whenever something in Studio does not match what is on disk.
---

# Studio Sync

## The golden rule

> **Files on disk are the source of truth. Studio is the renderer.**

Two things live in two places, and confusing them is how a day disappears:

| Thing | Lives in | Backed up by |
| --- | --- | --- |
| **Code** | `src/`, in Git | Git |
| **The map** — geometry, lighting, sounds, spawn points | the Studio place file | **Roblox cloud place-version history only** |

Place files (`.rbxl`) are gitignored: they are binary, huge, and merge-hostile. The map's backup is
**File → Publish to Roblox**, done regularly. Git will not save it, and neither will this harness.

## Never write scripts inside Studio

Rojo syncs `src/` into three locations and overwrites what it finds there:

| Studio location | Synced from |
| --- | --- |
| `ServerScriptService.Server` | `src/server/` |
| `ReplicatedStorage.Shared` | `src/shared/` |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client/` |

A script written into any of those from inside Studio is destroyed the next time a file under `src/` is
saved. Silently — no error, no diff, and nothing to recover, because it never existed on disk.

`guard-studio-sync.mjs` refuses those writes mechanically. If you see its denial, it is working: edit the
file under `src/` instead, and Rojo pushes it into Studio in under a second.

**Rojo deliberately does not touch `Workspace` or `Lighting`**, so it can never stomp the map. That is
also why a change to the map is invisible to `git status` — if a task spawn point is missing, no amount
of reading `src/` will tell you.

## What Studio MCP is genuinely for

Everything except writing script source. This is the only tool in the project that observes the game
actually running, which makes it the only source of behavioural evidence.

| Tool | Use |
| --- | --- |
| `list_roblox_studios`, `set_active_studio` | find and select the running Studio |
| `get_studio_state` | **check this first** — confirm which place is open before trusting anything |
| `start_stop_play` | enter and leave Play mode |
| `get_console_output` | the primary evidence source; every service logs its phase |
| `execute_luau` | probe live state, call a service, read a value |
| `screen_capture` | the artifact for any visual claim |
| `inspect_instance`, `search_game_tree` | confirm what exists in the DataModel |
| `script_read`, `script_grep` | read what Studio currently has — useful for proving a sync gap |
| `user_keyboard_input`, `user_mouse_input` | drive an interaction the way a player would |
| `generate_mesh`, `generate_material`, `generate_procedural_model` | see `asset-pipeline` |
| `search_asset`, `insert_asset` | Creator Store assets — see `asset-pipeline` |

## Before you trust anything you see in Studio

Three checks, in order. Skipping the first is the most expensive mistake available here, because a stale
Studio looks exactly like a working one.

```bash
npm run preflight -- --studio      # is `rojo serve` running at all?
```

1. **Is Rojo serving?** If not, Studio is showing code from before your change. Everything you observe is
   about the old version, and nothing warns you.
2. **Is the Rojo plugin CONNECTED?** Serving and connected are different states. In Studio: Plugins →
   Rojo → the panel says which.
3. **Is the right place open?** `get_studio_state`. Two Studio windows is normal and picking the wrong
   one produces confident nonsense.

If a script's behaviour in Studio contradicts what you read on disk, the answer is almost always one of
those three — not a Luau mystery.

## Solo testing

Most of this game needs three players (`Config.Round.MinPlayers`). `Config.Debug.SoloTesting` forces a
round with one so the state machine can be exercised.

- A solo round proves the **state machine**. It proves nothing about the **social loop**, which is the
  actual product.
- If you turn it on, turn it off, and say so in any report.
- `tests/config.test.luau` asserts it is `false`, so shipping with it on fails the gate. That assertion
  exists because a published place with `SoloTesting = true` skips `MinPlayers` for everyone.

## When Studio and disk disagree

| Symptom | Almost always |
| --- | --- |
| A change has no effect | Rojo not connected, or the plugin needs reconnecting |
| A client script does nothing at all, no error | An undeclared remote — `WaitForChild` hangs forever. Run `npm run check:remotes` |
| A module is `nil` | The sourcemap is stale, or the file is not under a synced root. `npm run sourcemap` |
| A part or light is missing | It is in the MAP, not the code. `git status` will never show it |
| It worked yesterday and not today | Check whether the place file was reverted in Roblox's version history |

## Commands

| What | Command |
| --- | --- |
| Start live sync | `rojo serve` |
| Regenerate the sourcemap | `npm run sourcemap` |
| Build a place file from disk | `npm run build` |
| Reinstall the Studio plugin | `rojo plugin install` |

`npm run build` produces `build/aswang.rbxl`, which contains the CODE and an empty world. It is not your
map and must never be published over it.
