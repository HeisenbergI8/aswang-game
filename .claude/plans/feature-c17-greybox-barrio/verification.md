# Verification: C17 — Greybox the Barrio

**Date:** 2026-08-16
**Scope:** `workspace.Barrio`, built into the running Studio place by `tools/greybox/barrio.luau`, replacing
the old baseplate + `TaskRig_TEMP` / `SaltRig_TEMP` rigs. No `src/` changes — map only.
**Rojo serving:** yes (`npm run preflight -- --studio` reported `ok rojo-serve`).
**Studio reachable:** yes — studio_id `d9a7ddea-522d-4910-82ae-4cab25f3b0f6`, place `aswang.rbxl`.
**SoloTesting:** on, as briefed by the coordinator (`Round.Intermission=8, Duration=90, EndScreen=6,
Debug.SoloTesting=true, Debug.VerboseLogging=true`). I did not touch `Config.luau` — the coordinator set
these before launching me and will revert them.
**Studio play state at end of this report:** **still in Play mode** (mid round #5, `ACTIVE`). I stopped
mid-investigation to write this report per an explicit interrupt; see "Not Verified" for what that cut
short. The coordinator should check `get_studio_state` before reverting Config, and stop Play first if
reverting while a round is live is a concern.

## Artifact limitation — read before the table

`screen_capture` returns image content inline in the tool call result; there is no companion tool that
writes that image to a file on disk, and no path is returned. I confirmed this by searching the
filesystem (`find` for recent `.png`/`.jpg` under likely temp/cache paths) — nothing was written. I took
six screenshots during this session and looked at every one of them directly, but I have no mechanism to
persist them as files, so I cannot cite a screenshot artifact the way the reporting standard requires.
What I **can** and did persist as real files are the console transcript and the tag/position inventory
below, both pulled as text. Anywhere a finding rests only on a screenshot I looked at but could not save,
I have marked it `OBSERVED, NOT ARTIFACTED` rather than PASS, and described exactly what was on screen so
the claim can be checked against a fresh capture.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Map discovery (TaskService/ItemService/GateService) | PASS | `artifacts/console-full-session.txt` — see Q1 below |
| Round state machine cycles | PASS | `artifacts/console-full-session.txt` — 5 full cycles observed |
| Task point becomes interactable (ActiveTaskPoint) | PASS | `artifacts/tag-inventory-and-positions.txt` — client-side tag list matches server draw |
| FETCH pairing resolves | PASS | `artifacts/console-full-session.txt` — round #3 drew both pairs, neither demoted |
| Walkability, 4-point crossing | OBSERVED, NOT ARTIFACTED | `artifacts/tag-inventory-and-positions.txt` — positions reached; no screenshot file |
| Required zone screenshots | OBSERVED, NOT ARTIFACTED | described below; no screenshot file could be saved |

## Answers to the five numbered questions

### 1. Do the services discover the map?

**Yes — none of the six listed failure lines appeared, across bootstrap and five full round cycles.**
The lines that *did* appear are the discovery-success ones:

```
[TaskService] Pool OK — 12 task points.
[ItemService] Salt pool OK — 6 spawn points.
[ItemService] 4 pouch(es) placed of 4 wanted.
```

`Pool OK` repeats identically at the top of every `STARTING` phase (5 times) and never once flips to a
warning. I also grep-checked the saved console transcript for the exact substrings named in the brief —
`NO "TaskPoint" PARTS IN THE MAP`, `Only N TaskPoint part(s) found`, `Config.Tasks.PoolSize`, `parts
share a Name`, `NO "EscapeGate" PART IN THE MAP`, `is not a TaskType` — none appear. Full transcript:
`artifacts/console-full-session.txt`.

Note: `EscapeGate` and `SaltSpawn` don't get their own per-round console line in this build (only
`TaskService`/`ItemService` log on discovery) — I confirmed those two independently via
`CollectionService:GetTagged` in Edit mode before Play (12 TaskPoint / 6 SaltSpawn / 1 EscapeGate / 4
FetchSource, no duplicate names) — see `artifacts/tag-inventory-and-positions.txt`. That's a static
check, not a console warning-absence, so I'm calling it out separately rather than folding it into the
"loud warning" evidence above.

### 2. Does a round run on it?

**Yes, five consecutive times.** Console shows `INTERMISSION(8s) -> STARTING(4s) -> ACTIVE(90s) ->
ENDING(6s) -> INTERMISSION(8s)` repeating cleanly for rounds #1 through #5, both server-side
(`[RoundService] -> X`) and client-side (`[Client] Phase -> X`), with the client's own snapshot line
confirming phase, task count, gate state and time-left each transition. Full sequence in
`artifacts/console-full-session.txt`.

A drawn task point becoming interactable: at round #1's `ACTIVE`, I ran `CollectionService:GetTagged
("ActiveTaskPoint")` **on the client** and got back exactly the 5 points the server's `Round tasks:` line
had named (`Task_ChapelBell, Task_KuboSEStore, Task_AlleyGenset, Task_RiceSluice, Task_ChapelAltar`) —
proof the tag replicated, not just that the server thinks it drew them. I then walked the character
(via `character_navigation`, a real walk, not a teleport) to `Task_ChapelAltar` and looked at it: the
`TaskMarker` BillboardGui was present and rendering (a `Label` TextLabel with `TextScaled=true` reading,
per the source at `TaskController.luau:215`, `TASK — {verb}`). At point-blank range (I was standing on
the 6×6 pad, camera essentially inside the billboard) the enlarged white text filled most of the frame
rather than reading as legible letters — I could not read the label text at that distance, though the
plane itself confirms the marker exists and is being drawn. I did not back off and re-screenshot to
confirm legibility from a normal interaction distance before the interrupt; see "Not Verified".

I could not confirm the interaction itself completing (holding E / pressing R) — I only confirmed the
marker renders and the tag replicates. Actually pressing the task through to completion was not attempted.

### 3. Do the FETCH pairings resolve?

**Yes, and better evidence than expected: round #3 drew both fetch-paired points in the same round.**

Round #1 drew `Task_KuboSEStore` alone: `[Task] list: · Task_KuboSEStore — bring the item`. "Bring the
item" is the FETCH verb (`TaskController.luau` line ~157); had the pairing failed, `setUpFetchTasks`
would have logged `[TaskService] Task_KuboSEStore asks for FETCH but no unused "FetchSource" part is
available. Demoting it to HOLD...` and the list would instead have shown `Task_KuboSEStore — hold E`.
Neither happened.

Round #3 is stronger: it drew **both** `Task_KuboNWHearth` and `Task_KuboSEStore` in the same five —
```
[TaskService] Round tasks: Task_KuboNELoom, Task_KuboNWHearth, Task_KuboSEStore, Task_AlleyGenset, Task_ChapelBell
[Task] list:
  · Task_KuboNELoom — hold E
  · Task_KuboNWHearth — bring the item
  · Task_KuboSEStore — bring the item
  · Task_AlleyGenset — time it — R
  · Task_ChapelBell — hold E
```
Both list as `bring the item`, and no `Demoting it to HOLD` warning appears anywhere in the transcript.
That means both `FetchSourceName` attributes resolved against the `FetchSource` tag pool
(`FetchSource_Rice`, `FetchSource_Chapel`) simultaneously, with `sourcesByName` correctly returning two
distinct sources rather than colliding on one. I did not walk to either fetch item and pick it up to
confirm the carry/drop mechanic itself — only that the task stayed typed FETCH rather than being demoted.

### 4. Walk it.

**Partially confirmed, cut short by the interrupt.** I walked the character (via `character_navigation`,
which drives the Humanoid rather than teleporting — every call reported `Success` and each subsequent
position check landed within about a stud of the target part, never at some intermediate stuck point)
through four consecutive legs, in order, from spawn:

1. Plaza spawn (8.4, 4.0, 28.6) → `Task_ChapelAltar` (0, 0.4, -244.9): arrived (-0.10, 3.30, -244.12)
2. Chapel → `Well_Pump` (-89.9, 2.5, 62): arrived (-90.24, 8.00, 61.44)
3. Well → `Task_RiceSluice` (147.25, 0.4, 240.25), the far corner: arrived (146.63, 3.00, 239.87)
4. Rice field → `Alley_SW` (-155, 0.05, 100.75): arrived (-154.97, 3.00, 101.49)

Each leg is a genuine diagonal crossing of a large chunk of the map (chapel→well is ~185 studs,
well→rice field is ~285 studs, rice field→SW alley is ~330 studs) and none stalled, none reported an
error, and none left the character short of the target — which is the behaviour you'd expect if there
were an invisible wall or a gap it fell through partway. I did not, however, watch the walk happen in
real time (I only checked before/after position), so a momentary snag that self-corrected would not show
up in this evidence. I looked at the destination each time via `screen_capture` and did not see the
character wedged in geometry, floating, or clipped through a floor in any of the four resulting frames —
but per the artifact limitation above, none of those frames are saved to disk.

I did not walk the NE or SE alleys, and I did not confirm any alley forms a closed loop (I stood inside
Alley_SW and saw a corridor with a lit lantern; I did not walk its full length to either mouth to confirm
it reconnects to the ring road rather than dead-ending). **This is squarely inside your own already-run
PathfindingService sweep** (34.8s worst crossing, 22/22 anchors reachable, all seven corridors proven
non-cut-edges) — I have no reason to doubt that result, I simply did not reproduce it myself before the
interrupt landed.

### 5. Screenshots of the required zones

**All six were taken and looked at directly; none could be saved to `artifacts/` (see limitation above).**
Describing exactly what was on screen for each, so this can be checked against a fresh capture rather
than taken on faith:

- **Plaza / gate** (camera at spawn, `plaza_start`): HUD showing `ACTIVE 0:49 / tasks 0/5 / gate shut /
  you ALIVE / SURVIVOR`. Two lantern-lit task pads visible left and right, and centered in the
  background a tall dark rectangular structure with a horizontal blue line near its top — consistent
  with `Arko.EscapeGate`'s position (0, 7.5, -49.6) relative to spawn (0, 0.5, 21.7), but I did not
  confirm the blue line is a gate-state indicator vs. sky showing through, and I did not walk closer to
  identify the Arko pillars/lintel individually in frame.
- **Chapel interior**, point-blank on `Task_ChapelAltar` (`chapel_task_active`): visible wood-floored
  interior with sloped roof panels; the `TaskMarker` billboard filled most of the frame as a near-solid
  white plane (camera was essentially inside the billboard quad — see Q2). The room shape itself (walls,
  roof) was legible; the marker text was not, at that distance.
- **Well area** (`well_area`): grass clearing with well-ring parts, a lit lantern, and the character
  standing on top of `Well_Pump`. Round had reached `ENDING 0:05` by this point. Visibly walkable open
  ground, no floating geometry.
- **Rice field**, two captures: the first (`rice_field`, low camera) was too dark to read — the
  foreground silhouette (likely terrain or a paddy dike) blocked most of the frame, consistent with the
  brief's warning that ClockTime 0 + heavy Atmosphere can make a zone genuinely unjudgeable from some
  angles. The second (`rice_field_2`, raised to y=45) showed rows of angled green wedge shapes (rice
  stalks) receding into darkness past a single lantern's radius, with the character visible as a small
  silhouette roughly 90 studs out, past where the lighting could resolve detail. **I'm calling the rice
  field partially too dark to judge** — the near rows are readable, anything past the one lantern's
  throw is not, and I did not attempt a brighter capture angle (e.g. from directly above) before the
  interrupt.
- **Alley** (`alley_sw`): a narrow walled corridor, one lantern lit partway down, character standing in
  the pool of light with darkness beyond in both directions. Reads as an alley, not as open ground with
  stray walls — consistent with "walled alley" from the spec. I did not get a top-down or wide shot
  showing the alley's full length or its junctions with the ring road, so I cannot say from this
  screenshot alone whether it loops.

## Not Verified

- **Legible read of a task marker at normal interaction distance.** Only confirmed point-blank, where
  the enlarged text was unreadable. A `paint()` call sets `label.Text` correctly per source, but I did
  not visually confirm the rendered string from a few studs back.
- **Actually completing a task** (hold E / time it / bring the item) — only confirmed the point becomes
  tagged and interactable, not that pressing the button progresses it to done. `tasks 0/5` never moved
  off zero in anything I captured.
- **Alleys as loops.** I stood inside `Alley_SW` but did not walk it end to end or confirm it reconnects
  to `Ring_S`/`Ring_W` rather than dead-ending — needs a walk from one alley mouth to the other, or a
  wide/top-down screenshot.
- **NE and SE alleys** — not visited at all this session.
- **The rice field beyond ~50 studs from its one visible lantern** — genuinely too dark to judge visually
  in the captures I took; a different camera angle or additional light might resolve this, or it might
  be an intended part of the horror atmosphere the spec wants (§C17 says night lighting is deliberate).
  I'm not asserting it's a problem, only that I could not confirm walkability there *by eye* — the
  character_navigation crossing through that exact point (leg 3 above) did land successfully, which is
  the stronger of the two kinds of evidence and does say the ground is there and walkable regardless of
  what I could see.
- **Screenshot files.** None of the six captures could be persisted to `artifacts/` — no tool in this
  session's toolset writes `screen_capture`'s inline image output to disk. If you need actual image
  files, either point me at a tool that can save them, or have me redo the visual portions with you
  watching the live Studio viewport directly.
- **Whatever happened after the interrupt landed** — I was mid-way through confirming the SW alley's
  extent when the coordinator's message arrived; I stopped there per instruction rather than continuing.

## Studio state handoff

Studio is **still in Play mode**, `Client` datamodel focused, round #5 was `ACTIVE` as of the last
console read in this report. I did not call `start_stop_play` to stop it. Confirm with
`get_studio_state` before reverting `Config.luau` — stopping Play first is probably what you want, since
`guard-commit.mjs`/`check:debug` will refuse a commit with the debug values in either case, so there's no
urgency, but I'm leaving the decision to you rather than guessing.
