# ASWANG: Survive the Night

A co-op horror game for Roblox. Filipino folklore, hidden-monster gameplay.

**Read the design doc first:** [`docs/MVP-SPEC.md`](docs/MVP-SPEC.md) — it defines the whole MVP,
what's deliberately out of scope, the architecture, and the balance numbers.

**Then read [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md)** — the spec broken into 45 sequenced chunks,
each with its dependencies, its definition of done, and the command that verifies it. The spec says
*what*; the build plan says *what's next*.

---

## Daily workflow

Open **two** things: this folder in VS Code, and your place in Roblox Studio.

```bash
rojo serve
```

Then in Studio: **Plugins → Rojo → Connect**. That's it. Save a file in VS Code and the
script updates in Studio instantly.

```
VS Code + Claude Code  ──edit──>  src/*.luau  ──Rojo──>  Roblox Studio
                                                              │
Claude Code Desktop  ──MCP──> inspects, runs, screenshots ─────┘
```

---

## ⚠️ The golden rule

> **Files on disk are the source of truth. Studio is the renderer.**

- **Code** lives in `src/` and is edited in VS Code. Rojo pushes it into Studio.
- **The map** (geometry, lighting, sounds) lives in the Studio place file, *not* in Git.
- **Never let Claude edit scripts directly inside Studio via MCP** while Rojo is connected —
  the next sync will overwrite them and the work is gone. Use MCP for *inspecting*
  instances, reading console output, running test code, and screenshots.

Rojo only manages three locations. It deliberately does **not** touch `Workspace` or
`Lighting`, so it can never stomp your map:

| Studio location | Synced from |
|---|---|
| `ServerScriptService.Server` | `src/server/` |
| `ReplicatedStorage.Shared` | `src/shared/` |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client/` |

### Your map is not backed up by Git

Place files (`.rbxl`) are gitignored — they're binary and merge-hostile. Your map's backup
is **Roblox's cloud place-version history**, so **publish regularly** (File → Publish to Roblox).
That is your undo button for the map.

---

## Project structure

```
src/
  shared/                    → ReplicatedStorage.Shared
    Config.luau              ★ every tunable number lives here — no magic numbers elsewhere
    Enums.luau                 RoundPhase, Role, TaskType, ...
    Types.luau                 Luau types (PlayerProfile, RoundState, ...)
    Remotes.luau               every RemoteEvent declared in one auditable place
  server/                    → ServerScriptService.Server
    init.server.luau           bootstrap: Init() on all services, then Start()
    Services/
      RoundService.luau      ★ the state machine — nothing else mutates phase
      RoleService.luau         secret role assignment (M2)
      MonsterService.luau      transform + kill validation (M2)
      TaskService.luau         5-of-12 randomized tasks (M3)
      ItemService.luau         salt: stun + reveal (M4)
      GhostService.luau        dead players stay useful (M4)
      TrialService.luau      ★ Solo Trial — tutorial + low-population fallback (M6)
      ProgressionService.luau  XP, coins, saving (M9)
      BadgeService.luau        the 5 funnel badges (M9)
      MonetizationService.luau passes, products, private servers (M10)
      CommunityService.luau    group reward + social links (M10)
      AnalyticsService.luau    the funnel (M11)
      AntiCheatService.luau    rate limits, server authority (M11)
  client/                    → StarterPlayer.StarterPlayerScripts.Client
    init.client.luau           bootstrap
    Controllers/               UI, input, quick chat, camera FX, audio (M7–M8)
docs/
  MVP-SPEC.md              ★ the design doc — read this before writing code
                             Appendix C is a teardown of the closest competitor
  BUILD-PLAN.md            ★ the spec as 45 ordered chunks — what to build next
```

Each stub carries `TODO(Mx)` markers tying it to a milestone in the spec.

---

## Commands

| What | Command |
|---|---|
| Start live sync | `rojo serve` |
| **The gate** — analyze, lint, format, 5 project checks, unit tests | `npm run verify` |
| The fast gate, for mid-task | `npm run verify:fast` |
| First-time setup / repair the toolchain | `rokit install && npm run check:toolchain` |
| Format | `npm run fmt` |
| Unit tests (Lune) | `npm run test:unit` |
| Build a place file (code + empty world) | `npm run build` |
| Reinstall Studio plugin | `rojo plugin install` |

Tool versions are pinned in `rokit.toml`, so this project builds identically on any machine. `npm` is
here only as a task runner and to host the Claude Code hooks — there is no JavaScript in the game.

`npm run check:toolchain` fetches the Roblox API type definitions into `.luau-defs/` on first run. Without
them the analyzer reports a confident green while knowing nothing about Roblox, so it is worth running
once after cloning.

---

## Working with Claude Code

`CLAUDE.md` is the authority on how work is done here — the routing table, the agents, and what is
enforced by code rather than by instruction.

The short version: **`npm run verify` is the single gate**, and a set of hooks in `.claude/` makes several
of this project's rules mechanical rather than remembered. Five are specific to this game:

| Check | Refuses |
|---|---|
| `check:secrecy` | the Aswang's identity reaching any client |
| `check:remotes` | a remote that isn't declared, or is fired in the wrong direction |
| `check:config` | a balance number typed anywhere but `Config.luau` |
| `check:scope` | anything from the spec's §3 OUT list appearing in `src/` |
| `check:ratelimit` | an `OnServerEvent` handler with no rate limit |

A sixth guard refuses script writes *inside Studio*, because Rojo would overwrite them on the next sync.

Run `npm run check:guards` to execute the harness's own 22 test suites.

---

## The security rule that matters most

The Aswang's identity is **server-only state**. It is never replicated to another client —
not as a tag, not as an attribute, not as a "hidden" value. Assume every client is
compromised, because in a game where knowing the imposter wins the round, someone will try.

The client only ever *requests* (`RequestKill`, `RequestTaskProgress`). The server validates
distance, line of sight, cooldown, and phase, then decides. See spec §6.2.

---

## Where to start

**Chunk C01 in [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md)** — finishing the round state machine.
`RoundService.luau` already has the state machine wired and broadcasting phase changes; what's left is
the §6.4 edge cases and the client snapshot. Press Play in Studio with `Config.Debug.SoloTesting = true`
and watch the phases cycle in the output.

The gate that matters is **C19 / M5: play it with 6 real humans before building any art or UI.**
If they don't want a 6th round, change the design then — that's the cheapest moment in the
whole project to be wrong.
