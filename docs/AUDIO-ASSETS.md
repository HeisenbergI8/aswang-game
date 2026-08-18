# Audio assets

Every sound in the game, with the record `Config.Audio.Assets` cannot hold. C29 (§5, §14.3).

**Sourced, never generated** — there is no text-to-audio tool in this toolchain. Everything here came
from `search_asset` over the Creator Store with `priceFilter: "free"`.

**If a sound stops playing, look here first.** Roblox moderation can pull an asset, and the symptom is
silence with no error and nothing in `git status`. The row below is how you know what used to be there.

## Status: sourced, NOT yet approved

Every id below was chosen by search, on the strength of its name, description and duration. **Nobody has
listened to any of them.** The Approved column is empty on purpose and stays empty until the C29 Step 4.5
headphone listen — "does this sound scary" is not a thing a search filter answers, which is why C29 is a
🧍 chunk. Swap freely from the rejected-candidates table below; a swap is one line in `Config.Audio.Assets`.

**Two caveats that will bite before the listen does:**

1. **The place is unpublished** (`search_asset` reported `isPublished: false`). Roblox gates audio by
   experience, so some of these may not load until the place is published. A cue that logs but makes no
   sound is this, not the code.
2. **Durations are only known where the creator recorded one.** Pro Sound Effects publishes duration in
   the description; most community uploads do not. `unknown` below means unknown, not unchecked.

| Cue id | Asset id | Name | Creator | Duration | Sourced | Approved |
| --- | --- | --- | --- | --- | --- | --- |
| CUE_BED_LOBBY | 9112764040 | Crickets Canyon 1 (SFX) | ProSoundEffects | 36.0s, loop | 2026-08-18 | |
| CUE_BED_NIGHT | 9112764573 | Crickets Night 3 (SFX) | ProSoundEffects | 64.0s, loop | 2026-08-18 | |
| CUE_BED_DAWN | 9112831284 | Morning Birds 1 (SFX) | ProSoundEffects | 36.0s, loop | 2026-08-18 | |
| CUE_WIND | 125270272833477 | Wind Gust | MagmaBombe | unknown | 2026-08-18 | |
| CUE_DOGS | 9120051478 | Timber Wolves Distant Bursts Of Barking 1 (SFX) | ProSoundEffects | 9.8s | 2026-08-18 | |
| CUE_FOOTSTEP | 132221529613537 | FOOTSTEPS_(A)_Walking_Loop_01 | julius90744 | unknown | 2026-08-18 | |
| CUE_TRANSFORM | 9125474505 | Creature Screech Pterodactyl Vocals Screams (SFX) | ProSoundEffects | 1.2s | 2026-08-18 | |
| CUE_HEARTBEAT | 139459003161851 | heartbeat | vinndication | unknown | 2026-08-18 | |
| CUE_GATE_OPEN | 133202590810335 | Heavy Door Open | r_cg0 | unknown | 2026-08-18 | |
| CUE_SUNRISE | 4501062448 | Riser | PuffoThePufferfish | unknown | 2026-08-18 | |

## Why these, where the choice was not obvious

- **`CUE_FOOTSTEP` is a walking LOOP, not a single step.** The controller retargets the `Humanoid`'s
  existing `Running` sound, and that sound is a loop the engine plays while a character moves — a
  one-shot single footstep there would play once and stop. This is the row most likely to be wrong;
  `footstep grass 4` is the single-step alternative if the retarget turns out to work differently.
- **`CUE_TRANSFORM` is a 1.2s screech, and `Config.Monster.TransformTime` is 1.2s.** That is deliberate:
  §4.3's tell should end when the windup ends, so a witness who hears it and turns sees the thing that
  made it. The `asset-pipeline` skill calls this "the single highest-value sound in the game" and it is
  the one most worth rejecting and re-sourcing if it is not right.
- **`CUE_DOGS` is wolves.** The Creator Store's free "distant barking at night" is a Pro Sound Effects
  wolf recording; it reads as distant dogs in context but a Filipino barrio should not have wolves in it
  if the recording is identifiable. `dog-barks-through-a-wall` is the alternative and is a genuine dog.
- **Three beds are all "loop"-marked by the creator**, which matters more than it looks: `CUE_BED_*` and
  `CUE_HEARTBEAT` play `Looped = true`, and an audible seam at the loop point is the most common defect
  in free ambience. The heartbeat is the one to listen to hardest — it is the only loop here whose
  creator did not mark it as one.

## Rejected candidates

Kept deliberately: the second-best option for each cue, so a moderated asset is a one-line swap rather
than a second search.

| Cue id | Asset id | Name | Why not chosen |
| --- | --- | --- | --- |
| CUE_BED_LOBBY | 9112764023 | Crickets Canyon 2 (SFX) | 46.2s; near-identical to the chosen one, kept as the drop-in |
| CUE_BED_NIGHT | 9117114470 | Night Jungle 8 (SFX) | Denser and more tense, but jungle rather than village |
| CUE_BED_NIGHT | 9112777821 | Farmland Presence 2 (SFX) | Rural and right in character, but has birds — reads as evening, not night |
| CUE_BED_DAWN | 9119673937 | Sunrise Birds 5 (SFX) | Also good; chosen one is loop-marked, this is not |
| CUE_WIND | 9126166856 | Vocal Wind Blowing Air Through Lips (SFX) | It is a person blowing into a microphone |
| CUE_DOGS | 76033031154818 | dog-barks-through-a-wall | An actual dog, but muffled-through-a-wall is a specific place the barrio is not |
| CUE_FOOTSTEP | 135037154891351 | footstep grass 4 | Single step; use if the `Running` retarget wants a one-shot |
| CUE_TRANSFORM | 116576934219692 | Distant Reverbed Monster Roar | Reverb reads as distance, which fights a 40-stud proximity tell |
| CUE_TRANSFORM | 9113984056 | Creature Mix Weird Deep Monster Breathing 3 (SFX) | 5.3s — longer than `Monster.TransformTime` (1.2s), so it would outlive the windup |
| CUE_HEARTBEAT | 2867269913 | Heartbeat sound | Older upload, kept as the swap if the chosen one seams |
| CUE_GATE_OPEN | 78365732356269 | creaking-door-2 | Creak without the weight; the gate should sound heavy |
| CUE_SUNRISE | 1836093883 | Introspective Slow Motion | Musical rather than diegetic; would fight the dawn bed |

## Searches that found nothing usable

Recorded so the next pass does not repeat them. The Creator Store search is unexpectedly literal —
`monster`, `growl`, `creature roar beast`, `horror stinger` and `footsteps` (plural) all returned **zero**
results, while `roar`, `creature` and `footstep` (singular) returned eight each. Single common nouns work;
descriptive phrases mostly do not.
