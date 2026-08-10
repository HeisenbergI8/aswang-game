---
name: playtest
description: Run and record a structured playtest with real humans — the M5 and M12 gates from the spec. Use when the user is about to test with players, is reporting what testers said, or asks whether the game is fun or balanced. This is about judgement with humans, not about verification; for "does it work", use the playtester agent.
---

# Playtest

`playtester` answers *does it work*. This answers *is it worth building*, and those are not the same
question — a round can pass every gate in this repo and still be boring, which is the only failure that
matters.

The spec is unusually direct about this:

> **M5 is the real gate.** If 6 people don't want a 6th round, no amount of art, monetization, or
> marketing will save it — **change the design then, not after launch.** This is the cheapest moment in
> the entire project to be wrong.

## Do not skip past the gates

| Gate | When | Bar |
| --- | --- | --- |
| **M5** | after salt + ghosts, **before any art or UI** | 6 real humans, 5 rounds. Do they want a 6th? |
| **M6** | after the Solo Trial | a brand-new player reaches a first objective in under 60 seconds |
| **M12** | after the full loop | 8 players. Neither side wins more than ~60% |

M5 comes **before** art deliberately. Art makes a bad loop feel better for one session and costs weeks;
finding out at M5 costs an evening. If you are being asked to build the map before M5 has happened, say
so.

## Before the session

- **`Config.Debug.SoloTesting` must be OFF.** `tests/config.test.luau` asserts it, but check anyway — a
  session run with it on is not the game.
- **`npm run verify` green**, and the place **published**. Testers join the published place, not your
  Studio.
- **Write down the Config values you are testing.** Every number in Appendix A is "a starting value to
  tune", so a session whose settings you cannot reconstruct taught you nothing.
- **Recruit for the real count.** Three players is the minimum viable round and it plays differently from
  eight. Test the count you expect to have at launch, which for a new game is the low one.

## During — record, do not defend

Two rules, and the second is harder:

1. **Write down what people SAY, verbatim, in the moment.** "I didn't know what to do" is data. Your
   summary of it a day later is not.
2. **Do not explain the game while they play.** The moment you explain something is the moment you have
   found an FTUE bug, and explaining it hides the bug. Write down what you wanted to say instead.

Watch for these specifically — they map to what the spec says kills games of this exact shape:

| Watch for | Because |
| --- | --- |
| A player standing still, looking around | §10 — they do not know what to do. This is the 80% failure |
| Someone dying first and going quiet | §4.7 — the ghost system exists to stop exactly this |
| Nobody witnessing a transform all round | §4.3 — the tell is the whole design; if it is never seen it is not working |
| Salt never thrown, or thrown and missed every time | §4.6 — the counterplay is decorative if it never lands |
| The Aswang winning by hiding rather than hunting | §2 — "the monster must risk exposure to kill" |
| Silence where accusation should be | §4.5 — the quick-chat wheel is not doing its job |
| Anyone leaving mid-session | the strongest possible negative signal |

## After every session — the numbers that decide things

```
Rounds played:            
Players who wanted a 6th round:      / 6      ← THE M5 GATE
Side win rate:            survivors __ / aswang __
Rounds where a transform was witnessed:  __ / __
Rounds where salt hit:                   __ / __
First-objective time, new players:       __ s   ← the M6 gate, target < 60
Players who quit mid-session:            __
```

Then Appendix A tells you which knob to turn, and **turn ONE per session**. Two changes at once and you
learn nothing about either:

| Symptom | Knob |
| --- | --- |
| Survivors rarely finish tasks | `Round.Duration` up, or `Tasks.TotalRequired` down |
| Aswang wins too often | `Monster.KillCooldown` up, or `Salt.SpawnCount` up |
| Aswang can't get kills | `Monster.KillCooldown` down, or `Monster.TransformTime` down |
| Aswang always caught transforming | `Monster.TransformTime` down |
| Aswang too sneaky | `Monster.TransformTime` up |
| Kills feel unreliable | `Monster.KillRange` up |
| Rounds drag / players idle | `Round.Duration` down |

Every one of these lives in `src/shared/Config.luau`. That is why `check:config` refuses magic numbers
elsewhere — at M12 you will be changing these constantly, and a value hidden in a service is a value you
will not find.

## Write it down where it survives

Create `docs/playtests/YYYY-MM-DD-<n>players.md`:

```markdown
# Playtest — YYYY-MM-DD · N players · M rounds

**Build:** <git sha> · **Config changed since last session:** <the one knob, or "none">

## Numbers
[the block above, filled in]

## Verbatim
- "..." — what they were doing when they said it

## What I changed as a result
- <one knob>, and what I expect to see next session

## What I am NOT changing yet
- <the thing you were tempted by, and why one session is not enough evidence>
```

That last section matters more than it looks. The failure mode after a playtest is changing five things
because five people said five things, and then having no idea which change did what.

## When the M5 gate fails

If fewer than half want a sixth round, **stop building**. Do not proceed to art, UI, or monetization —
those are all downstream of a loop that people want to repeat, and the spec's whole build order (§12)
assumes M5 passed.

The design changes worth considering, in the spec's own order of preference: shorten the round, raise the
task count so the finale comes sooner, make the transform more visible, add salt. All of them are Config
values, which means the next session can test a different game for the price of an evening.

That is the point of having put every number in one file.
