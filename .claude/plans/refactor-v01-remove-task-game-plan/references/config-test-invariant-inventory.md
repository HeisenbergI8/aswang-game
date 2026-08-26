# Inventory — every `check(...)` in `tests/config.test.luau`, tagged

Generated against the tree at `79e5fb5`. `TASKS` / `GHOST` mean the block reads `Config.Tasks` or
`Config.Ghost` and therefore **dies with Step 4.2**. Line ranges are the full `check(` … `)` call and
do NOT include the leading comment block, which must be deleted with it.

**19 of 71 blocks are tagged.** Plus one untagged block that must also go — see the note at the end.

```
30-34     -             "the Solo Trial offers itself exactly below the minimum player count"
37-41     TASKS         "there are more task locations than tasks required"
44-47     -             "the server can actually reach the minimum"
50-54     -             "servers stay small enough for paranoia"
59-63     -             "the kill cooldown outlasts a full transform cycle"
67-71     -             "the transform is long enough to be seen"
74-78     -             "salt reaches further than the Aswang kills"
82-86     -             "the salt reveal outlasts the stun"
90-94     GHOST         "ghosts contribute, but less than the living"
99-103    -             "there are at least as many salt spawn points as pouches"
112-116   -             "salt is scarcer than the roster"
120-124   -             "the throw cone is a cone"
128-133   TASKS         "a pouch is picked up closer than a task is held"
137-141   GHOST         "the ghost roster is not pushed faster than the snapshot"
145-149   GHOST         "a ghost gets at least one spook"
159-163   GHOST         "a spook lasts long enough to notice and not longer than the reveal"
174-178   -             "the kill cooldown outlasts the salt stun"
182-188   TASKS GHOST   "a spook does not point at the ghost that caused it"
199-203   -             "the FTUE conversion gate is still set to the spec's threshold"
211-215   -             "a more recent Aswang is less likely than an older one"
217-221   -             "any recent Aswang is less likely than someone who has never been one"
224-228   -             "nobody is ever excluded from the draw outright"
232-237   -             "the anti-repeat history is shorter than a full server"
241-245   -             "a minimum-sized round still has survivors in it"
250-254   -             "the Aswang intro finishes before the round goes live"
257-261   -             "solo testing is off"
270-274   -             "the solo forced-Aswang override is off"
279-283   -             "a round is long enough to actually be played"
293-299   -             "the attrition win is reachable but not free on a full server"
303-307   -             "the corpse fades inside its own lifetime"
312-316   -             "a body outlives the cooldown, so two kills can be evidence at once"
320-324   TASKS         "selected task points are spread further apart than the Aswang can reach"
331-336   -             "a lobby death always recovers well before the next round starts"
350-354   TASKS         "a player can only ever be present at one task point at a time"
358-362   TASKS         "a continuously held task never lapses between heartbeats"
370-376   TASKS         "a holding client stays inside its own rate-limit budget"
382-387   TASKS         "the timing green zone sits inside the bar"
399-406   TASKS         "the timing grace widens the zone rather than replacing it"
410-414   TASKS         "the fetch deliver hold is a small part of the errand"
423-429   TASKS GHOST   "a ghost is not a two-person participant"
436-440   TASKS         "the escape gate stays inside the Aswang's reach"
450-454   -             "the chase starts before the trial ends"
456-460   -             "salt is in hand before the thing it defends against arrives"
462-466   -             "the folklore line lands after the transform, not before"
468-473   -             "the handoff has room to be read"
482-486   -             "the trial's offer threshold and the round's floor are the same line"
488-492   TASKS         "the trial's two tasks can actually be drawn"
501-505   -             "the trial's scripted Aswang cannot catch the player"
521-525   -             "one chase tick cannot cross the rig's whole hold zone"
541-545   -             "the accusation reaches further than the Aswang kills"
555-560   TASKS         "the accusation is not a map-scale radar"
569-573   -             "the accusation's field of view is a forward cone"
591-596   -             "the map keeps some of the light budget"
603-608   -             "the light cull runs slower than the snapshot it is not driven by"
623-627   -             "the night ends later than it starts"
630-634   -             "both ends of the night are real clock times"
641-648   -             "dawn is brighter, further-seeing and less foggy than night"
655-661   -             "dawn is warmer than the night it replaces"
671-675   -             "the sky settles back to night before the next round starts"
692-696   -             "the heartbeat never carries further than the transform tell"
703-707   -             "the sunrise cue fires inside the round, near its end"
715-719   -             "a one-shot is cleaned up before the next one is scheduled"
721-725   -             "the one-shot interval band is not inverted"
731-735   -             "the dawn bed finishes fading in before the end screen is over"
807-811   -             "the shutdown flush budget stays inside Roblox's BindToClose window"
818-823   -             "session retries resolve before a round can start"
851-855   -             "a perfect Aswang round pays more than a perfect survivor round"
856-860   -             "a perfect Aswang round does not pay double a perfect survivor round"
884-888   -             "a week of daily claims does not buy the cheapest cosmetic on its own"
```

## NOTE — one untagged block also dies

`293-299` — "the attrition win is reachable but not free on a full server" — reads only
`Config.Round.*`, so it carries no tag. It pins v1.3's attrition rule, whose module `WinConditions` is
deleted in Step 3.3 and whose threshold `Config.Round.AswangWinSurvivorThreshold` is deleted in Step
4.2. Delete it with the nineteen.

## IMPORTANT — three of these are real losses, not dead weight

- `128-133` "a pouch is picked up closer than a task is held" — the ONLY invariant pinning
  `Config.Salt.PickupRangeStuds` against anything. After V01 it has no second operand until V03 gives
  containers a search range.
- `555-560` "the accusation is not a map-scale radar" — pins `Config.QuickChat.AccuseRangeStuds`
  against `Config.Tasks.MarkerVisibleStuds / 2`. Same problem: the right-hand side disappears.
- `293-299` — pinned that a full-server round was winnable at ALL. V11 owns its replacement.

All three are **silent** invariants: nothing in the running game reports when they stop holding. Spec
§6.5 names six v2.0 invariants and is where their replacements belong.

## NOTE — `488-492` needs its operand rehomed, not just deleted

"the trial's two tasks can actually be drawn" compares `Config.Trial.TasksToComplete` against
`Config.Tasks.PoolSize`. After Step 4.1 the trial reads its own `Config.Trial.PresenceRangeStuds` and
`HoldTime`, but it never had its own pool size — its points come from the trial-zone attribute
(`TrialService.luau:338-339`). Delete the invariant; do not invent a `Config.Trial.PoolSize` for it.

## NOTE — the PASS line must not be touched

`check-testcount.mjs` exists because this exact file once ended with a hardcoded `34` that survived
seven additions and would have survived seven deletions. The tally is interpolated now; nineteen
deletions move it by themselves.
