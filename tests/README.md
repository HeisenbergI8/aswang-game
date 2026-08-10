# Unit tests

Run with `npm run test:unit`. Every `tests/*.test.luau` executes under [Lune](https://lune-org.github.io/docs),
a standalone Luau runtime — no Studio, no Roblox, no place file.

## What can be tested here, and what cannot

Lune is not Roblox. It has no `game`, no `Instance`, no `task.wait` against a real scheduler, and no
`script.Parent`. So this directory covers exactly one thing:

> **Pure modules — no Roblox globals, no `script.Parent` requires.**

Today that is `Config.luau`, and the tests over it assert the *relationships between balance numbers*
that the spec depends on. Those are worth pinning precisely because they are invisible: nothing warns
you when `Trial.OfferBelowPlayerCount` drifts away from `Round.MinPlayers`, and the symptom is a Solo
Trial that never offers itself during exactly the dead-server hour it exists for.

Anything touching the DataModel is verified by the `playtester` agent driving real Studio through MCP
instead — see `.claude/skills/studio-sync/SKILL.md`. That split is honest about where each tool's
evidence actually reaches.

## Writing one

```luau
local Config = require("../src/shared/Config")

local failures = 0

local function check(label: string, ok: boolean)
	if not ok then
		failures += 1
		print(`  FAIL  {label}`)
	end
end

check("a round is long enough to finish five tasks", Config.Round.Duration >= 300)

if failures > 0 then
	error(`{failures} failure(s)`, 0)
end
```

A non-zero exit is the whole protocol — `error()` produces one. The runner reports the file and the
output; it does not parse a format, so there is nothing to keep in sync.

## Growing the pure layer

When a piece of gameplay logic is worth testing — role-weighting for the anti-repeat draw, the 5-of-12
task selection, XP curves — write it as a pure function taking plain tables, and have the service call
it. The Roblox-shaped wrapper stays thin and untestable; the decision it makes becomes provable here.

### There are TWO pure locations, and secrecy picks between them

Lune resolves requires by **file path** and knows nothing about Rojo, so both are equally testable —
`require("../src/shared/pure/X")` and `require("../src/server/pure/X")` both just work. The choice is
about replication, not about tests.

| | `src/shared/pure/` | `src/server/pure/` |
| --- | --- | --- |
| Reaches the client | **yes** — requirable *and callable* by any LocalScript | no — ServerScriptService does not replicate |
| `check:config` governs it | no (the check covers `src/(server\|client)/`) | **yes** — no tunable number may be typed there |
| Use it for | arithmetic whose inputs are already public | anything whose **inputs, seed or output** are secret |

`pure/TokenBucket.luau` is shared: `Config.AntiCheat.Budgets` already replicates, so the module
publishes nothing new, and knowing the algorithm buys a client nothing because the buckets live on the
server.

`server/pure/RoleDraw.luau` is not. A published algorithm is not a leak, but a **reproducible draw** is:
algorithm + inputs + seed = this round's Aswang, known before the round starts, with no remote to
intercept and nothing for `check:secrecy` to see. It is the only leak in this game that leaves no trace
on the wire.

Because `check:config` governs `src/server/`, a module there takes its numbers as **parameters** rather
than reading Config directly — which is the right shape anyway, since those numbers are what M12 tunes.
