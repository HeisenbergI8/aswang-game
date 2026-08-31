# Artifact — Phase 2, Step 2.6: the resting height, measured in the running game

Studio session `ab384d6d`, place `aswang.rbxl`, Rojo blessed (`rojo:status` verdict `ok`), Play mode,
18 ambient rigs live.

## 1. The unverified half: what `HipHeight` measures from

Step 2.5 wrote `footOffsetOf` as `HipHeight + root.Size.Y / 2` and flagged the reference point as
**not verified in this codebase** — the two readings differ by ~1 stud, which is small enough to look
like a modelling choice and large enough to be a tell. Measured directly against a live R15 character:

```
RigType            = Enum.HumanoidRigType.R15
HipHeight          = 1.9980
root.Size.Y        = 2.0000
root.Position.Y    = 3.0980
lowest part bottom = 0.1051
TRUE foot offset   = 2.9929   <- root centre to lowest point of the character
HipHeight + Sy/2   = 2.9980   (delta +0.0051)
HipHeight alone    = 1.9980   (delta -0.9949)
```

**The underside reading is correct.** `HipHeight + root.Size.Y / 2` is accurate to 0.005 studs;
`HipHeight` alone would have been wrong by 0.99. The Follow Up is closed empirically, not from docs.

## 2. The defect this phase existed to remove, observed before the fix

First run, after Phase 2's `buildEntity` change was already synced and running:

```
Ambient_CAT_1        h=1.20 bottom=-0.200 ground=0.000  err=-0.200
Ambient_CAT_3        h=1.20 bottom=-0.200 ground=2.000  err=-2.200
Ambient_GOAT_10      h=2.20 bottom=-0.700 ground=0.800  err=-1.500
Ambient_VILLAGER_16  h=5.00 bottom=-2.100 ground=0.000  err=-2.100
...
WORST vertical error: -2.200 studs on Ambient_CAT_3
```

**Every rig's centre was at exactly 0.4** — the spawn pad's height — regardless of form height or of
the ground beneath it. `buildEntity` was seating them correctly and something was undoing it.

## 3. The site the plan did not name

`wanderTick` retargets from `home * CFrame.new(dx, 0, dz)`, and `home` is the pad's CFrame. Every
target therefore inherited y = 0.4, and each rig walked back to pad height within a Heartbeat of
spawning. **It is the third site that decides a rig's Y and it is the one that outlives the other two.**

Fixed by seating the retarget on its own ground (one raycast per retarget — roughly two a second
across the whole population, against the eighteen-a-frame `groundYUnder`'s header refuses), and by
flattening the facing vector so a rig crossing a kerb does not pitch nose-down.

## 4. After the fix — free rigs

Same probe, after one full retarget cycle:

```
Ambient_CAT_1        h=1.20 bottom=+0.000 ground=+0.000 err=+0.000
Ambient_DOG_5        h=1.90 bottom=+0.798 ground=+0.800 err=-0.002
Ambient_CHICKEN_15   h=1.10 bottom=+0.300 ground=+0.300 err=+0.000
Ambient_VILLAGER_17  h=5.00 bottom=+0.003 ground=+0.000 err=+0.003
...
18 rigs; WORST vertical error +0.003 studs (Ambient_VILLAGER_17)
```

**2.200 studs → 0.003.** The residuals are mid-step interpolation, not seating error. Note the rigs now
sit at genuinely different heights (0.0, 0.3, 0.8) matching the ground they stand on.

## 5. After the fix — free vs puppeted, which is the leak itself

`AmbientRig.puppetY` evaluated against every live rig, for a monster standing on that rig's own ground
with the foot offset measured in §1:

```
Ambient_CAT_1        h=1.20 ground=+0.000 free=+0.6000 puppeted=+0.5949  delta=-0.0051
Ambient_DOG_5        h=1.90 ground=+0.800 free=+1.7500 puppeted=+1.7449  delta=-0.0051
Ambient_GOAT_11      h=2.20 ground=+0.000 free=+1.1000 puppeted=+1.0949  delta=-0.0051
Ambient_VILLAGER_18  h=5.00 ground=+0.000 free=+2.5000 puppeted=+2.4949  delta=-0.0051
...
WORST free-vs-puppeted delta: -0.0051 studs
```

**−0.0051 studs, uniform across all six forms**, and it is entirely the §1 measurement residual. Before
this phase the delta was **+2.6 studs, constant** — a disguised cat floating twice its own height above
every real cat, readable in one frame with no motion.

## What this does NOT prove

`ClaimSlot` returned `nil` when called through `execute_luau`, because `require` from the MCP console
hands back a **fresh module instance with an empty roster**, not the live one — the trap CLAUDE.md
names. So §5 evaluates `AmbientRig.puppetY` against real geometry rather than driving
`AmbientService.PuppetSlot` end to end.

The wiring between them is covered by `npm run analyze` (the third argument is required, so a stale
two-argument call site is an error rather than a silent `nil`) and by
`tests/ambient-rig.test.luau`'s 190 assertions over the equality. **An end-to-end camouflage capture
needs a real reveal and a second player**, which is the solo-testing limit
`.claude/agents/playtester.md` documents. Phase 6's Humanoid parity capture is the natural place.

## Capture

`ScreenCapture_1`, camera at (-93, 4, 112) looking at the villager pair near (-99.5, 2.5, 93.8).
Both villagers stand with feet on the ground; neither floats. Recorded in the session transcript.
