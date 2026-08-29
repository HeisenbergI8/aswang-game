# Verification — barrio realism pass

**Who verified this, and it matters.** This was verified in-session by the implementer, not by an
independent `playtester` agent. That is a weaker arrangement than this repo's pipeline normally uses,
and it is stated first because everything below should be read knowing the person checking the work is
the person who did it. An independent pass over the diff is still worth buying.

## Artifacts

| File | What it holds |
| --- | --- |
| `artifacts/hero-zone.md` | The Phase 4 approval gate — four numbers, three screenshot descriptions, the three questions and their answers, and the stilt/layout decision |
| `artifacts/final-perf.md` | The finished map's numbers, the authored lighting, and what is still unmeasured |

## What was actually run

| Check | Result |
| --- | --- |
| `npm run verify` | **green, exit 0** |
| `npm run verify:plan` | **28 passed, 0 failed, 5 unverifiable, 0 self-satisfying** |
| `barrio.luau` in Studio Edit mode | builds clean; receipt asserts pass |
| `measure.luau` after every build | **10/10 `ok`** on the final run |
| Live DataModel tag counts | `SearchContainer=15 SaltSpawn=6 AmbientSpawn=16 TaskPoint=2(TrialOnly) EscapeGate=0 FetchSource=0` |
| Live MeshPart census | 31 placed, matching the registry's `Placed` column exactly |
| Screenshots | 6 taken and looked at directly |

## What the evidence supports

- **The v2.0 map contract is satisfied in the live place**, read back from the DataModel rather than
  inferred from source. Searching has fifteen containers where it had zero.
- **The layout did not move.** Crossing time is 34.8s at the start of the plan and 34.8s at the end,
  across eight phases, measured after every build.
- **The map got smaller.** 1,155 → 1,133 instances, with substantially more detail.
- **The container visibility failure found at the Phase 4 gate is fixed**, and the fix was confirmed by
  re-taking the identical camera shot and comparing.

## What it does NOT support

- **No screenshot is on disk.** `screen_capture` returns images inline and no tool in this session
  persists them. Both artifact files describe each capture precisely enough to be re-taken and
  disagreed with, which is the honest substitute, not an equivalent. **This is the weakest link in the
  verification and it is the same limitation C17 recorded.**
- **No FPS reading on a physical phone.** §5 calls the mobile budget non-negotiable. Part count,
  triangle count, collider count and light overlap are all inside budget and asserted — those are good
  proxies and they are proxies.
- **Nothing was verified with `Lighting.Technology = Future`**, which §5 requires and which cannot be
  set or even read from this context. Every capture was taken without it.
- **No round was played on the finished map.** The services were confirmed to *discover* it
  (`[SearchService] Container pool OK — 15 containers`, `[ItemService] Salt pool OK — 6 spawn points`),
  not that a round plays well on it.
- **Whether the barrio is frightening, and whether searching it feels like survival or a chore.** That
  is V16's question. Nothing here answers it and no gate in this plan could.

## The failure worth reading before trusting any of this

Phase 7's bamboo rewrite silently deleted the fence runs, the banana coordinate table, the
`FieldDressing` folder and the scarecrows. **The build stayed green, `measure.luau` returned all ten
`ok` lines, and the part count went down** — which was that phase's goal, so the deletion read as
success. It was caught by counting MeshParts in the live map, not by any gate.

It is fixed and now asserted by name in `tests/barrio-budget.test.luau`. It is recorded here because it
is direct evidence that a green tree over this particular kind of work means less than it looks like.
