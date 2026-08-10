# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What This Is

**ASWANG: Survive the Night** — a co-op horror game for Roblox. Filipino folklore, hidden-monster
gameplay. 6–8 players, one is secretly the Aswang.

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
rojo serve                # live sync into Studio — start this first, every session
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
| `npm run goal <plan-dir>` | one exit code for "is this plan finished" |
| `npm run check:guards` | the harness's own 22 suites, unconditionally |

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
(`RequestKill`, `RequestTaskProgress`, `RequestThrowSalt`); the server validates distance, line of sight,
cooldown and phase, then decides. A design where the client computes an outcome is rejected, not fixed.

**The secret.** The Aswang's identity never leaves the server in any form. Not a tag, not an attribute,
not a name colour, not a "hidden" value. Two remotes may legitimately carry it and they are listed in
`check-secrecy.mjs` with their reasons: `RoundEnded` (the round is over — the reveal is the point) and
`RoleAssigned` (fired to exactly one player, carrying only their own role). Adding a third requires
editing that file, which shows up in review. That asymmetry is the design.

The subtler leak is a **derived hint**: a speed multiplier, a Highlight, a tool in the backpack, a sound
played to one player. None of them contains the word "role" and every one is readable by any client.

**`RoundService` owns the phase.** Nothing else calls `setPhase`. Every service subscribes to phase
changes. Spec §6.4 says so because the state machine is where this genre's bugs live.

**Every tunable is in `Config.luau`.** Balance is data. `tests/config.test.luau` pins thirteen
*relationships* between those numbers — salt must reach further than the Aswang kills, the reveal must
outlast the stun, the kill cooldown must outlast a full transform cycle. Those are silent invariants: no
symptom tells you when two numbers that must agree have stopped agreeing.

**Strict Luau, and it bites.** `Enums.RoundPhase.Idle` infers as plain `string` without its `:: Types.X`
cast, and then fails to satisfy a parameter typed as the literal union. Six of the scaffold's seven
original analyze errors were exactly that.

### Where testable logic goes

Lune is not Roblox — no `game`, no `Instance`, no `script.Parent`. So `tests/` covers **pure modules
only**.

That is a constraint worth designing around rather than accepting. When a piece of gameplay logic is
worth proving — role weighting for the anti-repeat draw, the 5-of-12 task selection, an XP curve — write
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

**Which auditor:** `auditor` traces a written plan step by step and requires a plan directory.
`change-auditor` audits the working diff against the user's request. Presence of a plan decides it.

**Planning means the `architect` agent — never the built-in `Plan` agent.** They describe themselves
almost identically, but `Plan` has no Write tool: it reports in chat and creates no plan directory.
Everything downstream needs that directory — `implement-plan` reads it, `auditor` traces against it,
`verify-plan.mjs` and `goal-check.mjs` grade it, and `/build`'s cursor walks its `#### Step N.M` headings.
Picking `Plan` produces a plausible answer and silently breaks all five.

**Trivial tier still gets `npm run verify`** and a plain statement of what changed. It skips the agents,
not the checking.

**Spawning policy:** auto-spawn for Small and Medium — say which tier you picked in one line, then
proceed. For **Large**, state the tier and the agents you intend to run and **wait for confirmation**.

**Naming the tier out loud is the enforcement.** Routing is a judgement no hook can make, so the safeguard
is visibility: a tier stated in one line is a claim the user can correct in three words. A tier never
stated cannot be challenged. Skipping the announcement is the actual failure mode, not choosing wrong.

**Run the reviewers concurrently — this is the default, not an optimisation.** Launch them in one message
with `run_in_background: true`. They share no data: the playtester drives the running place, the auditors
read the diff. Sequencing them only adds the slower one's wall clock to the faster one's.

**Finish editing before you trigger them.** A review pass costs 5–8 minutes of wall clock; `review-gate.mjs`
fires on every turn that touches a tracked `.luau` file and goes green. So applying an auditor's
recommended fixes *in a later turn* buys a second full review round — for this repo's real numbers, ~8
minutes to re-audit six lines. Do the work, self-review, apply what you already know needs applying, run
`verify`, and **only then** launch the reviewers. Where an auditor's finding is genuinely new, batch every
resulting fix into a single turn rather than trickling them out.

**The playtester cannot edit `Config.luau` — set debug values yourself, before launching it.**
`guard-agent-write.mjs` scopes its writes to `.claude/plans/` and `tests/`, so asking it to shorten
`Round.Duration` for a fast cycle is asking for something it will correctly refuse twice and then report.
A round cycle is 461s at committed values; drop `Intermission/Duration/EndScreen` to 8/20/6 and set
`Debug.SoloTesting`/`VerboseLogging` yourself first, then revert all five and confirm with
`git diff src/shared/Config.luau` that only intended changes survive. `verify` goes red while they are
set — `tests/config.test.luau` asserts `SoloTesting == false` — which is the test working, and
`guard-commit.mjs` refuses a red tree anyway, so the values cannot reach history.

**`execute_luau` cannot read a live service's state.** With `datamodel_type: "Server"` it runs with its
own module require-cache: `require(…RoundService)` there returns a fresh, un-`Init()`'d copy reading
`IDLE`, while the real service is in `ACTIVE`. It sees the same Instance tree, so it looks like it
worked. Read server state through a field the server already publishes — `RoundSnapshot`'s `YourState`
is populated by calling `GetPlayerState()`, so the console line proves the call.

**Launch all three in the same message as each other, first time.** Naming two and adding the playtester
after the gate objects costs a whole extra round trip. The one case for omitting an agent is a
*precondition you have checked this turn* — e.g. the playtester cannot verify anything when `rojo serve`
is down or Studio is not connected, and re-running it just reproduces the same refusal. Check
(`ReplicatedStorage` empty in `search_game_tree` means Rojo never synced), then say why in one line.

The ordering that *is* real: they all run **after** implementation, and an auditor with no
`implementation-log.md` to read has nothing to trace.

### Claims about verification are checked, not trusted

`record-activity.mjs` writes a per-turn ledger of what actually happened — which `src/**.luau` files were
edited, which commands ran, each one's exit code, and which review agents finished. `claim-check.mjs`
reads it on `Stop` and blocks the turn when:

- **source was edited and nothing was verified**, or
- **the message claims a green gate that no run supports** — "the tree is green", "13/13 invariants",
  "analyze is clean", "I tested it in Studio", when the ledger has no successful run.

Deliberately narrow. Hedged or honest language passes untouched: "I have not run the tests yet", "next I
should run verify", and reporting a genuine failure are all fine and are pinned as test cases. The gate
exists for the one sentence that does real damage — *asserting* a green gate that was never run — because
a false green is worse than a reported red. It stops anyone else looking.

### The artifact directory

| Stage | Invoke | Writes |
| --- | --- | --- |
| Plan | `architect` agent | `<plan>/<type>-<name>-plan.md`, `references/`, an empty `artifacts/` |
| Build | `implement-plan` skill | `<plan>/implementation-log.md` |
| Verify | `playtester` agent | `<plan>/verification.md` + files in `<plan>/artifacts/` |
| Audit | `auditor` · `change-auditor` · `exploit-auditor` | nothing — they report in chat, scored /100 |

**The auditors write nothing.** They report as their final message, scored out of 100 against a rubric.
The score measures **how much the auditor's own evidence is worth**, not how good the code is — an
implementation it could only read, never play, caps around the mid-60s. Treat a high score with no
runtime evidence as a red flag rather than a pass.

Supporting skills: `lean-code` (before writing), `studio-sync` (before touching Studio), `asset-pipeline`
(before making any art or sound), `playtest` (for the M5/M12 human gates), `debug-ladder` (after two
failed fix attempts), `lesson-keeper`, `lessons-review`, `git-committer`. The built-in `/simplify`,
`/code-review` and `/security-review` cover post-write cleanup and review — do not duplicate them.

### The task loop — `/build`

A supervised loop: code decides *whether* to continue and *what is next*, the model does the work.
`task-driver.mjs` on `Stop` decides; `build-trigger.mjs` on `UserPromptSubmit` creates the run record
itself, because a skill that merely *tells* the model to create one produces no run when it forgets — and
a driver with no run releases forever, which is indistinguishable from working correctly.

**The loop can only drive Large-tier work, and that is a property of the tiers rather than a gap.** The
cursor advances through `#### Step N.M` headings, and the routing table gives an architect — so a plan —
to Large only. `/build --tier small|medium` is therefore **refused with an explanation** rather than
started. A run whose plan is not yet bound releases for three turns, then halts with `no plan bound`.

Halt conditions are evaluated **unconditionally, before** the tree is consulted. A single ordered list
with `tree red → release` above them silently abandons runs: a run that is red *and* stuck releases every
turn forever and **no halt report is ever written**. Four regression cases pin it.

A halt reporting `done` means **four proxies were satisfied**: plan steps passed, `verify` green,
`implementation-log.md` present, and `verification.md` citing a file that exists in `artifacts/`. The
artifact check is the strongest of the four and is still a proxy — it proves a screenshot exists and was
cited, never that it shows the right thing.

### The repair loop

A blocking `Stop` hook re-invokes the model with `reason` as feedback. `verify-gate.mjs` uses that as a
loop rather than a brake:

| | a brake would be | this is |
| --- | --- | --- |
| Predicate | "is the tree red?" | red, keyed on WHICH failure |
| Reason | "fix it" — a complaint | the next action, plus what was already tried |
| Exhaustion | reset and allow | escalate, then HALT with a report |

**Progress, not attempts, drives escalation.** Counting retries punishes a loop that is converging — three
different fixes producing three different failures is progress — and rewards one that thrashes with a
reworded command. Each iteration hashes the failure SET (analyzer diagnostics, selene warnings, stylua
diffs and check-script `FAIL` lines, with line and column numbers stripped, since the same error sliding
down a file is not progress). A changed fingerprint resets the counter; an unchanged one escalates.

The ladder is **block** → **escalate** (names what was tried, points at `debug-ladder`) → **HALT** (writes
a report, tells the model to stop and report, never blocks that run again). `loop-breaker.mjs` does the
same for a repeated Bash command: inject at 2, block at 3, halt on a second block.

### Lessons and candidates

`.claude/lessons/` holds a **capped** set of things this repo taught the hard way — one file per lesson,
40 maximum. Retrieval is mechanical: `lessons.mjs inject` runs on `UserPromptSubmit`, pushing the index in
once per session and the full text of any lesson whose `trigger:` terms match. A non-matching prompt costs
nothing.

The bar is four tests, all of which must pass — recurrence, non-obviousness, behaviour change, real cost
— and the expected rate is about one per session, often zero. **The intended end state for any lesson is
deletion**: once it hardens into a rule it graduates into this file or into a check script, and the lesson
is removed. The store shrinking because three entries became one guard is the system working.

`.claude/.candidates.jsonl` is the episodic layer beneath it — raw incidents captured automatically,
**never injected into context** and therefore free. `npm run verify` prints `- candidates: N/15`; at 15 a
review is due. Capture generously, distil strictly: a missed candidate is a lesson lost, a noisy one is a
line somebody skims.

### The harness

Rules enforced by code rather than by instruction, so they hold regardless of what a model decides:

| Mechanism | Enforces | Where |
| --- | --- | --- |
| `tools:` frontmatter | the three auditors have no Edit/Write at all | `.claude/agents/*-auditor.md` |
| `PreToolUse` write guard | architect writes only to `.claude/plans/`; playtester to plans and `tests/` | `guard-agent-write.mjs`, scoped by `agent_type` |
| `PreToolUse` Studio guard | no script source written inside Studio, where Rojo would overwrite it | `guard-studio-sync.mjs` |
| `PreToolUse` destructive guard | nothing destructive reaches outside the repo; no `git clean -f`, `reset --hard`; no deleting a `.rbxl` | `guard-destructive.mjs` |
| `PreToolUse` commit guard | no place file, sourcemap, build output or harness state committed; no commits on a red tree | `guard-commit.mjs` |
| `PostToolUse` analyze gate | `.luau` edits typechecked at write time, coalesced | `gate-luau-analyze.mjs` |
| `PostToolUse` loop breaker | the same command failing 3× is blocked; a second block halts | `loop-breaker.mjs` |
| `Stop` / `SubagentStop` gate | a red tree drives a REPAIR LOOP, not a two-block brake | `verify-gate.mjs` |
| `Stop` claim gate | a claim about a green gate is checked against a ledger | `claim-check.mjs` |
| `Stop` review gate | the reviewers are named when source changed and `verify` went green | `review-gate.mjs` |
| `Stop` driver | the task loop's whether-and-what-next decision | `task-driver.mjs` |
| `permissions.deny` + `autoMode.hard_deny` | declarative backstop; holds if a hook script errors | `.claude/settings.json` |
| `analyze-baseline.json` | tracked at the repo root, so widening the gate shows in a diff. `--update` refuses to run under an agent | `check-analyze.mjs` |
| 22 self-test suites | every guard and gate proven in BOTH directions | `harness-selftest.mjs` |

All hook wiring lives in `.claude/settings.json`. **Do not move per-agent hooks into agent frontmatter** —
`hooks:` in frontmatter is documented as agent-scoped and has been observed not to fire, while
settings.json hooks fired normally in the same session. Per-agent scoping is done inside the scripts by
reading `agent_type` off the payload. (`tools:` in frontmatter *does* work.)

**The ALLOW half of every suite is the important half.** A guard that only proves it can refuse has proven
the cheap half; the expensive failure is refusing correct work until somebody switches it off, and then it
protects nothing. `guards.test.mjs` carries 31 allow cases against 26 blocks, and several of the allows
are shapes a naive version genuinely did refuse.

**Two honest limits.** `disableAllHooks` turns all of it off, and the playtester retains Bash — so it is
guarded on the Edit/Write path, not sandboxed. The `.claude/scripts/` checks work regardless, which is why
they are the foundation rather than the decoration.

**A hook that is configured and silently not firing is the worst failure available here**, because it looks
exactly like a guard with nothing to do. `hook-heartbeat.mjs` records every fire and `npm run verify`
reports any registered-but-never-fired hook. A `WARN` there after editing `settings.json` usually means the
session needs restarting for the new wiring to take effect — but check rather than assume.

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

**Milestone M1 — the round skeleton.** `RoundService.luau` has the state machine wired and broadcasting
phase changes. Press Play in Studio with `Config.Debug.SoloTesting = true` and watch the phases cycle,
then build M2 on top.

The gate that matters is **M5: play it with 6 real humans before building any art or UI.** If they do not
want a 6th round, change the design then — that is the cheapest moment in the whole project to be wrong,
and no amount of harness will tell you the answer. See `.claude/skills/playtest/SKILL.md`.
