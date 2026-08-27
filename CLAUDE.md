# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What This Is

**ASWANG: Survive the Night** — a co-op horror game for Roblox. Filipino folklore, hidden-monster
gameplay. 3–5 players, one is secretly the Aswang. Survivors search the barrio for salt, bawang and a
buntot pagi, and win by living until sunrise or by killing it.

**The spec is at v2.0 — a mechanics rewrite.** Tasks, the escape gate and ghosts are gone; searching,
feeding, camouflage and three items replace them. `docs/MVP-SPEC.md`'s opening section lists what
changed and why. Forty chunks shipped under v1.3 and are in git history as `C01`–`C40`; v2.0 work is
numbered `V01`+ in `docs/BUILD-PLAN.md`. **If something in the code contradicts the spec, the code is
the stale one** — the rewrite lands chunk by chunk, and V01 is the demolition.

Stack: Luau (`--!strict`), Rojo 7 syncing `src/` into Studio, StyLua + selene + luau-lsp, Lune for unit
tests. Node is present only because the harness hooks are node scripts; there is no JavaScript in the
game.

Solo developer, zero art budget, no deadline. The goal is a shipped, profitable game.

## Requirements

**`docs/MVP-SPEC.md` is the source of truth for WHAT to build.** Answer design questions from it rather
than from inference or from general Roblox practice.

Three parts of it are load-bearing enough to name here:

| Section | Why it binds |
| --- | --- |
| **§3 — the hard line** | The ✅ IN / ❌ OUT lists. If a feature is not in that document it does not go in the MVP. `check:scope` enforces the OUT list mechanically |
| **§6.2 — server authority** | The Aswang's identity is server-only state. The client only *requests* |
| **Appendix C** | A teardown of the closest competitor: 2.5M visits, 1.43M players, **$0 earned**. Five named causes, five fixes, all of which are in the MVP scope |

Appendix C is the reason the scope line is drawn where it is. That game spent 16 months building
consumable content — seven zones, a mountain, unlockable weapons — and 79.9% of its players never
completed a single objective. **§C.5 is an explicit list of things not to rebuild.**

**Precedence:** `docs/MVP-SPEC.md` → this file → the code. When the spec and an instinct conflict, the
spec wins and the conflict gets raised rather than quietly resolved.

## Commands

```bash
rojo serve                # live sync into Studio. Started automatically before any Studio MCP call
npm run rojo:status       # the three facts: serving, attached, synced
npm run rojo:bless        # record this server session as proven-syncing (after a canary check)
npm run verify            # THE gate: analyze + lint + format + 5 checks + tests + harness  (~15s)
npm run verify:fast       # analyze + remotes + secrecy + toolchain                          (~3s)
```

| Command | What it does |
| --- | --- |
| `npm run analyze` | `luau-lsp analyze` over `src/`, graded against `analyze-baseline.json`. The typecheck |
| `npm run lint` | selene |
| `npm run fmt` / `fmt:check` | StyLua over `src` and `tests` |
| `npm run test:unit` | every `tests/*.test.luau`, under Lune |
| `npm run build` | `rojo build` → `build/aswang.rbxl` (code + empty world; **not your map**) |
| `npm run sourcemap` | regenerate `sourcemap.json` for the analyzer |
| `npm run check:toolchain` | verify the five pinned tools, fetch Roblox API definitions, refresh the sourcemap |
| `npm run preflight` | task-loop entry conditions; `-- --studio` adds a Rojo check |
| `npm run verify:plan <plan>` | run a plan's `**Verify:**` lines and grade the checks themselves |
| `npm run plan:phase -- <plan> [N]` | the plan's phase index, or one phase. **Read plans through this, never whole** |
| `npm run goal <plan-dir>` | one exit code for "is this plan finished" |
| `npm run check:guards` | the harness's own 28 suites, unconditionally |

**Prefer `npm run verify` over running checks individually**, and `verify:fast` mid-task. It is the same
gate the hooks, the commit guard and the task loop all use, so your report and theirs cannot disagree.

### The five repo-specific checks

These are the ones worth knowing by name. Each exists because the failure it catches is silent.

| Check | Catches | Why it is silent otherwise |
| --- | --- | --- |
| `check:remotes` | a remote used but not declared in `Remotes.luau`; a remote fired in the wrong direction | On the client, `WaitForChild` on a name the server never created **hangs forever** — no error, no output, no stack trace |
| `check:secrecy` | the Aswang's identity reaching a client — broadcasts, attributes, tags | Attributes and CollectionService tags replicate to **every** client. There is no private one, and nothing warns you |
| `check:config` | a balance number typed outside `Config.luau` | At M12 you tune constantly. A number hidden in a service is one you will not find |
| `check:scope` | a token from §3's OUT list appearing in `src/` | Nobody builds a second monster by accident; they build it on an evening when the spec is not open |
| `check:ratelimit` | an `OnServerEvent` handler that never consults `AntiCheatService` | An unguarded handler is a free firehose into server state |

Every one honours an inline waiver with a mandatory reason — `-- secrecy-ok: <why>`, `-- config-ok: <why>`
— so a deliberate exception shows up in a diff and can be argued with, rather than being silently
disabled.

`check:secrecy` and `check:ratelimit` are **text tripwires on obvious shapes**. They cannot follow data
flow. That is what `exploit-auditor` is for, and neither replaces the other.

## Architecture

### The golden rule

> **Files on disk are the source of truth. Studio is the renderer.**

Rojo syncs three locations and overwrites what it finds there:

| Studio location | Synced from |
| --- | --- |
| `ServerScriptService.Server` | `src/server/` |
| `ReplicatedStorage.Shared` | `src/shared/` |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client/` |

**Never write script source inside Studio.** The next sync destroys it silently — no error, no diff, and
nothing to recover because it never existed on disk. `guard-studio-sync.mjs` refuses those writes; every
other Studio MCP tool stays fully available, and they are how the `playtester` earns its evidence. See
`.claude/skills/studio-sync/SKILL.md`.

**Rojo is started for you. It is not synced for you.** `ensure-rojo.mjs` fires before every
`mcp__Roblox_Studio__*` call and starts `rojo serve` if the port is silent. That removes the forgotten
terminal, and nothing more — `preflight -- --studio` reports **three** separate facts:

| Line | Proves |
| --- | --- |
| `rojo-serve` | the port answers. A server exists |
| `rojo-attached` | a RobloxStudio process holds a socket to it |
| `rojo-synced` | **the only one that licenses evidence** — this server session was PROVEN to sync |

The third exists because the first two were once collapsed into "connected" and shipped a false green: a
Studio plugin retry loop holds an ESTABLISHED socket exactly like a healthy sync does. Proving a sync
needs a DataModel read, which needs MCP, which a hook does not have — so `npm run rojo:bless` records a
session id you have proven by writing a canary into a synced file and reading it back out of Studio.
A restarted server clears the blessing automatically. **Unblessed reads as not-proven**, so a forgotten
bless costs a stopped run rather than a fabricated verification.

**Never `perl -i` or `sed -i` a file under `src/`.** They rename a sibling temp file over the original
and Rojo 7.7.0 panics in `change_processor.rs:172` — while the edit succeeds and the shell reports
success. `guard-inplace-edit.mjs` refuses those; write the whole file instead.

**The MAP is not in Git.** Geometry, lighting, sounds and spawn points live in the place file, which is
gitignored — binary and merge-hostile. Its backup is Roblox's cloud place-version history, so **publish
regularly**. A missing prop will never show up in `git status`.

### Layout

```
src/shared/          → ReplicatedStorage.Shared
  Config.luau        ★ every tunable number. No magic numbers elsewhere (check:config)
  Enums.luau           string constants, carrying LITERAL types — the casts are load-bearing
  Types.luau           domain models. RoundState is server-only; ClientRoundSnapshot is the contract
  Remotes.luau       ★ the entire network surface, declared once (check:remotes)
src/server/          → ServerScriptService.Server
  init.server.luau     bootstrap: Init() on every service, then Start()
  Services/            RoundService is the reference shape — read it before adding one
src/client/          → StarterPlayer.StarterPlayerScripts.Client
  Controllers/
tests/                 Lune unit tests over PURE modules only
```

### The rules that matter

**Server authority.** The client is an untrusted renderer and input device. It *requests*
(`RequestKill`, `RequestSearch`, `RequestThrowSalt`, `RequestStrike`); the server validates distance,
line of sight, cooldown and phase, then decides. A design where the client computes an outcome is rejected, not fixed.

**The secret.** The Aswang's identity never leaves the server in any form. Not a tag, not an attribute,
not a name colour, not a "hidden" value. Two remotes may legitimately carry it and they are listed in
`check-secrecy.mjs` with their reasons: `RoundEnded` (the round is over — the reveal is the point) and
`RoleAssigned` (fired to exactly one player, carrying only their own role). Adding a third requires
editing that file, which shows up in review. That asymmetry is the design.

The subtler leak is a **derived hint**: a speed multiplier, a Highlight, a tool in the backpack, a sound
played to one player. None of them contains the word "role" and every one is readable by any client.

**`RoundService` owns the phase.** Nothing else calls `setPhase`. Every service subscribes to phase
changes. Spec §6.4 says so because the state machine is where this genre's bugs live.

**Every tunable is in `Config.luau`.** Balance is data. `tests/config.test.luau` pins *relationships*
between those numbers, not the numbers themselves — salt must reach further than the Aswang kills, the
reveal must outlast the stun, the feed must last longer than it takes to cross fifteen studs and swing.
Those are silent invariants: no symptom tells you when two numbers that must agree have stopped
agreeing.

**v2.0 makes this load-bearing rather than tidy.** Spec §6.5 names six invariants, and two of them
guard win conditions that fail *silently* — tighten `SaltDamage` or `SaltSpawnCount` without checking
invariant 1 and survivors can no longer weaken the Aswang enough to kill it, with nothing in the game
to tell you. The new mechanics interact multiplicatively (health × salt count × feed heal × a
two-condition strike gate), which is a space you cannot check by playing.

**Strict Luau, and it bites.** `Enums.RoundPhase.Idle` infers as plain `string` without its `:: Types.X`
cast, and then fails to satisfy a parameter typed as the literal union. Six of the scaffold's seven
original analyze errors were exactly that.

### Where testable logic goes

Lune is not Roblox — no `game`, no `Instance`, no `script.Parent`. So `tests/` covers **pure modules
only**.

That is a constraint worth designing around rather than accepting. When a piece of gameplay logic is
worth proving — role weighting for the anti-repeat draw, the container layout draw, the health floor,
the camouflage gate, an XP curve — write
it as a **pure function over plain tables** in `src/shared/pure/`, and have the service call it. The
Roblox-shaped wrapper stays thin and untestable; the decision becomes the best-verified thing in the
repo, and a plan step can be gated on `lune run tests/<x>.test.luau` instead of on a grep.

Pure modules also **must not** `require(script.Parent.X)` — Lune has no `script`, so a pure module that
reaches for `Types` or `Enums` stops being runnable from a terminal and the whole point is lost.
Re-declare the literal union locally; Luau unions are structural, so the local type and `Types.RoundPhase`
are the same type and pass to each other without a cast.

**`src/shared/pure/` is requirable and callable by any client** — `default.project.json` maps
`src/shared` wholesale into `ReplicatedStorage`, so a LocalScript can `require()` the module and *run*
it. Callable, not merely readable: reading `.Source` needs plugin security, and relying on that is the
mistake. For a transition table or an XP curve this costs nothing — `Config.luau` is replicated too, so
those modules publish nothing already public. Logic is not secret.

**Inputs and seeds are.** A published algorithm is not a leak, but one whose **inputs a client can
supply** is: it replays the draw locally and knows the Aswang before the round starts, with no remote to
intercept and nothing for `check:secrecy` to see. `Random.new()` with no argument is fine;
`Random.new(roundNumber)` and `Random.new(os.time())` are fatal, and `os.time()` is client-observable to
the second. Seed from server-only entropy and keep draw inputs off the wire, or put the module in
`src/server/pure/` and point the test at that path — Lune resolves by file path and cares nothing for
Rojo. Testability is why `pure/` exists; `Shared` is not.

Anything touching the DataModel is verified by the `playtester` driving real Studio instead.

## Working Pipeline

### Routing — size the task first, then pick the agents

Do not run the whole pipeline on every task, and do not skip verification because a task looks small.
**Planning scales with uncertainty; verification is close to constant.**

| Tier | What it looks like | architect | implement-plan | playtester | audit |
| --- | --- | --- | --- | --- | --- |
| **Trivial** | a comment, a rename, one Config value | — | — | — | — |
| **Small** | one function, precisely specified | — | — | ✅ | `change-auditor` |
| **Medium** | one system end-to-end, ~3 files, mechanics known | — | ✅ | ✅ | `change-auditor` |
| **Large** | a whole milestone, a new system, unverified Roblox behaviour | ✅ | ✅ | ✅ | `auditor` |

**Promote a tier** — regardless of file count — when any of these is true: a milestone from §12 is the
input; a Roblox API's behaviour is unverified; the change touches the role secret or the remote surface;
or more than one defensible approach exists.

**`exploit-auditor` runs IN ADDITION, at any tier**, whenever the diff touches `src/server/**`,
`Remotes.luau`, `RoleService`, `MonsterService` or `AntiCheatService`. `review-gate.mjs` names it
automatically for those paths. It is not a tier — it is a surface.

### Which reviewers actually run — surface-based, not one-size

A full three-reviewer pass costs 150–250k tokens, so reviewers are chosen by **what the diff touches and
what you are about to claim**:

| Condition | Reviewer |
| --- | --- |
| 🔒 surface — `src/server/**`, `Remotes.luau`, Role/Monster/AntiCheat | **`exploit-auditor`, always.** Non-negotiable |
| Large tier, or a diff over ~3 files | **+ `auditor`** (plan exists) or **`change-auditor`** (no plan) |
| You are about to state that something *works* | **+ `playtester`**, and it must return an artifact |
| Small diff, green tree, no behavioural claim | **none.** `npm run verify` and a plain statement |
| Harness scripts (`.claude/scripts/**`) | **`check:guards` + `change-auditor`.** Not `exploit-auditor` — no game surface, no Luau |

**The 🔒 row is the one that is not a judgement call.** In this repo's C04 work `analyze`, all five checks
and six Lune suites were green over a Critical bug: the transform's revert restored hardcoded defaults
instead of captured state, permanently branding the ex-Aswang in a way readable map-wide. Only
`exploit-auditor` found it. Static green over a secrecy surface means very little.

**Scope every brief — this is a rule, not a preference.** "Audit the diff" costs three times "audit
`MonsterService`'s revert path and answer these four questions", and returns less. Every brief names
**the files, the phase, and the questions**:

> Audit **Phase 3 only** of `.claude/plans/feature-c13-c16-salt-ghosts-plan/` — load it with
> `npm run plan:phase -- <plan> 3`. Files: `MonsterService.luau`, `SaltThrow.luau`. Answer: (1) does the
> throw resolve server-side, (2) is the cooldown read from `Config`, (3) does the revert restore captured
> state, (4) any step with no traceable `file:line`.

An unscoped brief is how an agent ends up reading a 57k-token plan and a 690KB source tree to check one
function — and every turn of that agent then re-carries all of it. **Context size multiplies by turn
count**, so what a brief lets an agent load is the single biggest lever on what a review costs.

**Planning means the `architect` agent — never the built-in `Plan` agent.** They describe themselves
almost identically, but `Plan` has no Write tool, so it creates no plan directory — and `implement-plan`,
`auditor`, `verify-plan.mjs`, `goal-check.mjs` and `/build`'s cursor all need one. Picking `Plan`
produces a plausible answer and silently breaks all five.

**Trivial tier still gets `npm run verify`** and a plain statement of what changed. It skips the agents,
not the checking.

**Spawning policy:** auto-spawn for Small and Medium — say which tier you picked in one line, then
proceed. For **Large**, state the tier and the agents you intend to run and **wait for confirmation**.
Routing is a judgement no hook can make, so naming the tier out loud IS the enforcement: a tier stated
in one line can be corrected in three words, and one never stated cannot be challenged.

**Launch them concurrently, all of them, in one message, with `run_in_background: true`.** They share no
data — the playtester drives the running place, the auditors read the diff — so sequencing only adds the
slower one's wall clock to the faster one's, and naming two now to add the third when the gate objects
costs a whole extra round trip. Omit an agent only for a *precondition you checked this turn*: the
playtester establishes nothing when `rojo serve` is down (`ReplicatedStorage` empty in `search_game_tree`
means Rojo never synced). Check, then say why in one line.

**Finish editing before you trigger them.** A review pass costs 5–8 minutes **and 150–250k tokens**, and
`review-gate.mjs` fires on every turn that edits a tracked `.luau` file and goes green — so applying an
auditor's fixes *in a later turn* buys a second full review round at full price. Do the work,
self-review, apply what you already know needs applying, run `verify`, and only then launch. Batch any
genuinely new findings into a single turn.

Subagents do not share the main thread's cache or each other's — every agent you launch re-reads its
material cold. Three agents on the same change is three cold reads of the same plan and the same source,
which is why the surface-based table above launches the reviewers a diff *earns*, not all of them.

They run **after** implementation: an auditor with no `implementation-log.md` has nothing to trace.

**Set the playtester's debug values yourself, before launching it** — it cannot edit `Config.luau` and
will correctly refuse. A round cycle is 461s at committed values; set `Round.Intermission/Duration/
EndScreen` to 8/20/6 plus `Debug.SoloTesting`/`VerboseLogging`, then revert all five afterwards and
confirm with `git diff src/shared/Config.luau`. `guard-commit.mjs` runs `check:debug` and refuses to
commit them, so they cannot reach history. Two Studio traps — `execute_luau` cannot read a live
service's state, and player count is a UI action no agent can drive — are explained in
`.claude/agents/playtester.md`; read it before briefing one.

### Claims about verification are checked, not trusted

`record-activity.mjs` ledgers every edit, command and exit code per turn, and `claim-check.mjs` blocks on
`Stop` when source was edited and nothing was verified, or when the message **asserts** a green gate no
run supports — "the tree is green", "13/13 invariants", "I tested it in Studio".

So state only what ran. Hedged and honest language passes untouched ("I have not run the tests yet",
"next I should run verify", and any report of a genuine failure), because a false green is worse than a
reported red — it stops anyone else looking.

### The artifact directory

| Stage | Invoke | Writes |
| --- | --- | --- |
| Plan | `architect` agent | `<plan>/<type>-<name>-plan.md`, `references/`, an empty `artifacts/` |
| Build | `implement-plan` skill | `<plan>/implementation-log.md` |
| Verify | `playtester` agent | `<plan>/verification.md` + files in `<plan>/artifacts/` |
| Audit | `auditor` · `change-auditor` · `exploit-auditor` | nothing — they report in chat, scored /100 |

**The auditors write nothing** — they report in chat, scored out of 100. That score measures **how much
the auditor's own evidence is worth**, not how good the code is: an implementation it could only read,
never play, caps around the mid-60s. Treat a high score with no runtime evidence as a red flag.

**Start a fresh session at each milestone boundary.** The artifact directory is the handoff — the plan,
`implementation-log.md`, `verification.md` and `artifacts/` carry the state that matters, which is the
whole reason they are files rather than conversation. A session carried across milestones re-processes
its entire history on every remaining turn and buys nothing the plan directory does not already hold.
Finish the milestone, commit, then open a new session and read the plan index.

Supporting skills: `lean-code` (before writing), `studio-sync` (before touching Studio), `asset-pipeline`
(before making any art or sound), `ui-polish` (before any HUD change, and for C26/C27), `playtest` (for
the M5/M12 human gates), `debug-ladder` (after two failed fix attempts), `lesson-keeper`,
`lessons-review`, `git-committer`. The built-in `/simplify`, `/code-review` and `/security-review` cover
post-write cleanup and review — do not duplicate them.

### The task loop — `/build`

A supervised loop: code decides *whether* to continue and *what is next*, the model does the work.
`task-driver.mjs` on `Stop` decides; `build-trigger.mjs` on `UserPromptSubmit` creates the run record.

**The loop can only drive Large-tier work**, because its cursor walks `#### Step N.M` headings and only
Large gets an architect, so only Large has a plan. `/build --tier small|medium` is **refused with an
explanation** rather than started. A run whose plan is not bound releases for three turns, then halts.

A halt reporting `done` means **four proxies were satisfied**: plan steps passed, `verify` green,
`implementation-log.md` present, and `verification.md` citing a file that exists in `artifacts/`. The
artifact check is the strongest and is still a proxy — it proves a screenshot was cited, never that it
shows the right thing.

### The repair loop

A red tree makes `verify-gate.mjs` block `Stop` with the failure and the next action; **it escalates on
lack of progress, not on attempts**, so three different fixes producing three different failures is fine
and a repeat is not. The ladder is block → escalate (points at `debug-ladder`) → HALT with a report,
after which it never blocks that run again. `loop-breaker.mjs` does the same for a repeated Bash command.

Two things follow for you: when it escalates, **change the kind of fix rather than its details**, and
when it halts, **stop and tell the user** — do not start a fourth attempt. A read-only reviewer that
cannot repair `src/` is blocked once and told to report the red tree instead (`canRepair`).

### Lessons and candidates

`.claude/lessons/` is a capped store (40) of things this repo taught the hard way; `lessons.mjs inject`
pushes matching ones into context automatically, so there is nothing to remember. The bar is four tests
— recurrence, non-obviousness, behaviour change, real cost — at roughly one per session, often zero, and
**the intended end state of a lesson is deletion** once it graduates into this file or a check script.

`.claude/.candidates.jsonl` is the episodic layer beneath it: incidents captured automatically, **never
injected into context** and therefore free. `verify` prints `- candidates: N/15`; at 15 run
`/lessons-review`. Capture generously, distil strictly.

### The harness

Rules enforced by code rather than by instruction, so they hold regardless of what a model decides:

| Mechanism | Enforces | Where |
| --- | --- | --- |
| `tools:` frontmatter | the three auditors have no Edit/Write at all | `.claude/agents/*-auditor.md` |
| `PreToolUse` write guard | architect writes only to `.claude/plans/`; playtester to plans and `tests/` | `guard-agent-write.mjs`, scoped by `agent_type` |
| `PreToolUse` Studio guard | no script source written inside Studio, where Rojo would overwrite it | `guard-studio-sync.mjs` |
| `PreToolUse` Rojo starter | `rojo serve` is running before anything looks at Studio. Cannot connect the plugin, so `preflight` checks that separately | `ensure-rojo.mjs` |
| `PreToolUse` in-place guard | no `perl -i` / `sed -i` on a Rojo-watched path — it CRASHES Rojo 7.7.0 and the edit still succeeds | `guard-inplace-edit.mjs` |
| `PreToolUse` destructive guard | nothing destructive reaches outside the repo; no `git clean -f`, `reset --hard`; no deleting a `.rbxl` | `guard-destructive.mjs` |
| `PreToolUse` commit guard | no place file, sourcemap, build output or harness state committed; no commits on a red tree | `guard-commit.mjs` |
| `PostToolUse` analyze gate | `.luau` edits typechecked at write time, coalesced | `gate-luau-analyze.mjs` |
| `PostToolUse` loop breaker | the same command failing 3× is blocked; a second block halts | `loop-breaker.mjs` |
| `Stop` / `SubagentStop` gate | a red tree drives a REPAIR LOOP, not a two-block brake | `verify-gate.mjs` |
| `Stop` claim gate | a claim about a green gate is checked against a ledger | `claim-check.mjs` |
| `Stop` review gate | the reviewers are named when source changed and `verify` went green | `review-gate.mjs` |
| `Stop` driver | the task loop's whether-and-what-next decision | `task-driver.mjs` |
| `Stop` loop-pause gate | a live `/build` run is never ended by ASKING to continue it — the run is the permission, and a user reply pauses it | `guard-loop-pause.mjs` |
| `permissions.deny` + `autoMode.hard_deny` | declarative backstop; holds if a hook script errors | `.claude/settings.json` |
| `analyze-baseline.json` | tracked at the repo root, so widening the gate shows in a diff. `--update` refuses to run under an agent | `check-analyze.mjs` |
| 31 self-test suites | every guard and gate proven in BOTH directions | `harness-selftest.mjs` |

All hook wiring lives in `.claude/settings.json`. **Do not move per-agent hooks into agent frontmatter** —
`hooks:` there is documented as agent-scoped and has been observed not to fire, while settings.json hooks
fired normally in the same session. Per-agent scoping is done inside the scripts by reading `agent_type`
off the payload. (`tools:` in frontmatter *does* work.)

**Writing or changing a guard? The ALLOW cases are the half that matters** — see the header of
`harness-selftest.mjs`. Every suite must prove both directions, and be listed in `SUITES`.

**Two honest limits.** `disableAllHooks` turns all of it off, and the playtester retains Bash — so it is
guarded on the Edit/Write path, not sandboxed. The `.claude/scripts/` checks work regardless, which is why
they are the foundation rather than the decoration.

**A configured hook that silently never fires looks exactly like a guard with nothing to do.**
`hook-heartbeat.mjs` records every fire and `npm run verify` reports any registered-but-never-fired hook.
A `WARN` there after editing `settings.json` usually means the session needs restarting — but check
rather than assume.

## Git

`.claude/` is **tracked** here, unlike most setups. The agents, skills, scripts and lessons are the
project's process; an untracked harness has no history and cannot be reviewed in a diff. Only its runtime
state is ignored, via `.claude/.gitignore`.

Commits use conventional-commit prefixes scoped by system (`feat(round):`, `fix(monster):`,
`balance(salt):`), a prose body explaining *why*, and no tool attribution. `balance` is its own type
because a commit that only moves numbers in `Config.luau` is a distinct kind of change during M12, and
`git log --grep balance` is how you reconstruct what a playtest was testing. See
`.claude/skills/git-committer/SKILL.md`.

## Where to start

**Chunk V01 — the demolition.** The v1.3 game is built and committed; v2.0 replaces its middle. V01
deletes the task system, the escape gate and ghosts so the tree stops describing a game that is no
longer the design. Read `docs/BUILD-PLAN.md` §0 first — it says exactly what dies, what is reworked,
and what survives untouched.

**Every V-chunk is Large tier**, by the author's decision, so the supervised loop can own all of them:
`/build V01`. That is a deliberate override of the routing table above, argued in the build plan's
deviation note. The routing table still governs anything that is *not* a numbered chunk.

The gate that matters is **V16: play it with real humans before polishing anything.** v2.0 asks three
specific questions there — does hiding win, does anyone ever kill the Aswang, and does searching feel
like survival or like a chore. The third one is whether this rewrite was worth doing, and the honest
place to find out is V16 rather than launch. See `.claude/skills/playtest/SKILL.md`.
